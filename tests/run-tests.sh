#!/usr/bin/env bash
#
# Regression tests for exim/spamtroll-check.
#
# The point of this file is the exit-code contract the Exim ACL depends
# on, and the fail-open guarantee: no API condition may ever produce a
# non-zero exit other than an explicit `blocked` (1) or `suspicious` (3)
# verdict. It also pins down that the API key never reaches argv.
#
# curl is stubbed with a shim on PATH that records its argv, its stdin
# and the contents of the -K config file it was handed, then replies
# with a canned body and status code.
#
# Requires: bash 4+, jq, base64, awk. python3 is optional — the MIME
# decoding assertions are skipped without it.
#
#   ./tests/run-tests.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$REPO_DIR/exim/spamtroll-check"

if (( BASH_VERSINFO[0] < 4 )); then
    echo "FATAL: these tests need bash 4+ (spamtroll-check uses \${var,,}); found $BASH_VERSION" >&2
    exit 2
fi
for tool in jq base64 awk; do
    command -v "$tool" >/dev/null 2>&1 || { echo "FATAL: missing $tool" >&2; exit 2; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
API_KEY_VALUE="testkeytestkeytestkey123"
MSGID="1bXTIK-0001yO-VA"

mkdir -p "$WORK/bin" "$WORK/spool/input"

cat > "$WORK/bin/curl" <<'SHIM'
#!/usr/bin/env bash
: > "$CURL_ARGV_LOG"
: > "$CURL_CONFIG_LOG"
prev=""
for arg in "$@"; do
    printf '%s\n' "$arg" >> "$CURL_ARGV_LOG"
    if [[ "$prev" == "-K" && -r "$arg" ]]; then
        cat "$arg" >> "$CURL_CONFIG_LOG"
    fi
    prev="$arg"
done
cat > "$CURL_BODY_LOG"
[[ "${CURL_FAKE_EXIT:-0}" != "0" ]] && exit "${CURL_FAKE_EXIT}"
printf '%s\n%s' "${CURL_FAKE_BODY:-}" "${CURL_FAKE_CODE:-200}"
exit 0
SHIM
chmod 755 "$WORK/bin/curl"

export CURL_ARGV_LOG="$WORK/curl.argv"
export CURL_CONFIG_LOG="$WORK/curl.config"
export CURL_BODY_LOG="$WORK/curl.stdin"
export PATH="$WORK/bin:$PATH"
export SPAMTROLL_CONFIG_FILE="$WORK/spamtroll.conf"
export SPAMTROLL_LOG_FILE="$WORK/spamtroll.log"
export LOG_DIR="$WORK/logdir"

b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

write_config() {
    cat > "$SPAMTROLL_CONFIG_FILE" <<EOF
ENABLED=${1-true}
API_KEY="${2-$API_KEY_VALUE}"
API_URL="https://api.spamtroll.io/api/v1"
LOG_LEVEL="${3-info}"
TIMEOUT=${4-5}
WHITELIST="${5-}"
BLACKLIST="${6-}"
EOF
}

write_spool() {
    printf '%s-D\n%s' "$MSGID" "$1" > "$WORK/spool/input/${MSGID}-D"
}

# run_check <from> <to> <subject> <raw-headers>
# Returns the script's stdout in $OUT and its exit status in $RC.
run_check() {
    : > "$SPAMTROLL_LOG_FILE"
    OUT=$("$CHECK" \
        "i198.51.100.7" \
        "ssender@example.com" \
        "m$MSGID" \
        "d$WORK/spool" \
        "f$(b64 "${1:-Sender <sender@example.com>}")" \
        "t$(b64 "${2:-victim@example.org}")" \
        "u$(b64 "${3:-Hello there}")" \
        "n$(b64 "<abc@example.com>")" \
        "h$(b64 "${4:-From: Sender <sender@example.com>}")" \
        "b$(b64 "short fallback body")")
    RC=$?
}

ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

expect_rc() {
    if [[ "$RC" == "$1" ]]; then ok "$2"; else bad "$2" "expected exit $1, got $RC"; fi
}

expect_contains() {
    if [[ "$1" == *"$2"* ]]; then ok "$3"; else bad "$3" "expected to contain: $2"; fi
}

expect_not_contains() {
    if [[ "$1" != *"$2"* ]]; then ok "$3"; else bad "$3" "must NOT contain: $2"; fi
}

expect_eq() {
    if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3" "expected [$2], got [$1]"; fi
}

api_reply() {
    export CURL_FAKE_BODY="$1"
    export CURL_FAKE_CODE="$2"
    export CURL_FAKE_EXIT="${3:-0}"
}

ok_body() {
    printf '{"success":true,"data":{"status":"%s","spam_score":%s}}' "$1" "$2"
}

echo "== exit-code contract =="

write_config true
write_spool "plain body text"

api_reply "$(ok_body safe -2.5)" 200
run_check
expect_rc 0 "safe verdict exits 0"
expect_contains "$OUT" "-2.5" "score is written to stdout for X-Spamtroll-Score"

api_reply "$(ok_body blocked 22.5)" 200
run_check
expect_rc 1 "blocked verdict exits 1"
expect_contains "$OUT" "22.5" "blocked score on stdout"

api_reply "$(ok_body suspicious 8)" 200
run_check
expect_rc 3 "suspicious verdict exits 3 (not reported as clean)"

echo "== fail-open on every error path =="

# Exit 2 is the ACL's "no verdict" code: it matches none of the
# X-Spamtroll-Status rules, so the message is accepted with no header.
# Exit 0 would accept it too, but would stamp it "clean" — a claim the
# scanner never made.

api_reply '{"success":false,"error":{"code":"QUOTA_EXCEEDED","message":"Daily scan limit reached.","usage":{"current":200,"limit":200,"plan":"free"}}}' 402
run_check
expect_rc 2 "HTTP 402 quota exhausted fails open, unmarked"
if [[ -s "$LOG_DIR/quota_skipped.log" ]]; then ok "402 recorded in quota_skipped.log"; else bad "402 recorded in quota_skipped.log" "file empty or missing"; fi

api_reply '{"error":true,"message":"Rate limit exceeded. Maximum 100 requests per minute."}' 429
run_check
expect_rc 2 "HTTP 429 (limiter body shape C) fails open, unmarked"

api_reply '{"success":false,"error":{"code":"UNAUTHORIZED","message":"Invalid API key"}}' 401
run_check
expect_rc 2 "HTTP 401 fails open, unmarked"

api_reply '{"success":false,"error":{"code":"FORBIDDEN","message":"Platform is disabled"}}' 403
run_check
expect_rc 2 "HTTP 403 fails open, unmarked"

api_reply '<html><head><title>502 Bad Gateway</title></head></html>' 502
run_check
expect_rc 2 "HTML error page fails open, unmarked"

api_reply '' 200
run_check
expect_rc 2 "empty body fails open, unmarked"

api_reply 'not json at all' 200
run_check
expect_rc 2 "unparseable body fails open, unmarked"

api_reply '{"success":true,"data":{"status":"weird-new-status","spam_score":99}}' 200
run_check
expect_rc 2 "unknown verdict string fails open, unmarked"

api_reply '' '' 7
run_check
expect_rc 2 "curl connection failure fails open, unmarked"

api_reply '' '' 28
run_check
expect_rc 2 "curl timeout fails open, unmarked"
api_reply "$(ok_body safe 0)" 200

write_config false
run_check
expect_rc 2 "disabled plugin does not scan and does not mark"

write_config true ""
run_check
expect_rc 2 "missing API key does not scan and does not mark"

write_config true "short"
run_check
expect_rc 2 "malformed API key does not scan and does not mark"

echo "== API key never reaches argv =="

write_config true
api_reply "$(ok_body safe 0)" 200
run_check
expect_not_contains "$(cat "$CURL_ARGV_LOG")" "$API_KEY_VALUE" "key absent from curl argv"
expect_contains "$(cat "$CURL_CONFIG_LOG")" "$API_KEY_VALUE" "key delivered through the -K config file"
expect_not_contains "$(cat "$SPAMTROLL_LOG_FILE")" "$API_KEY_VALUE" "key absent from the plugin log"

echo "== whitelist / blacklist =="

write_config true "$API_KEY_VALUE" info 5 "sender@example.com" ""
run_check
expect_rc 0 "whitelisted sender exits 0"

write_config true "$API_KEY_VALUE" info 5 "" "example.com"
run_check
expect_rc 1 "blacklisted sender domain exits 1"

echo "== argument integrity and log-injection =="

write_config true
api_reply "$(ok_body safe 1)" 200
NASTY='x" status="<svg onload=alert(1)>" y='
run_check "Sender <sender@example.com>" "$NASTY" "Re: \"pilne\" sprawy"
expect_rc 0 "quotes in To:/Subject: do not break argument splitting"
expect_contains "$(cat "$CURL_BODY_LOG")" 'Re: \"pilne\" sprawy' "subject survives verbatim into the payload"
LOGLINE=$(cat "$SPAMTROLL_LOG_FILE")
expect_not_contains "$LOGLINE" 'status="<svg' "quote in To: cannot inject a log field"
expect_contains "$LOGLINE" "status=safe" "real status field is present"

echo "== payload shape =="

write_spool "plain body text"
api_reply "$(ok_body safe 0)" 200
run_check
PAYLOAD=$(cat "$CURL_BODY_LOG")
expect_contains "$(jq -r '.source' <<<"$PAYLOAD")" "email" "source is email"
expect_contains "$(jq -r '.content' <<<"$PAYLOAD")" "plain body text" "body comes from the spool, not \$message_body"
expect_contains "$(jq -r '.headers | keys | join(",")' <<<"$PAYLOAD")" "list-id" "sender_context headers are sent"
expect_not_contains "$(jq -r '.headers | keys | join(",")' <<<"$PAYLOAD")" "authentication-results" "forgeable Authentication-Results is not forwarded"

HDRS='From: Sender <sender@example.com>
List-Id: <news.example.com>
List-Unsubscribe: <mailto:u@example.com>
Precedence: bulk
Received-SPF: pass (example.com: domain of sender@example.com designates
 198.51.100.7 as permitted sender)'
run_check "Sender <sender@example.com>" "victim@example.org" "Hello there" "$HDRS"
PAYLOAD=$(cat "$CURL_BODY_LOG")
expect_eq "$(jq -r '.headers["list-id"]' <<<"$PAYLOAD")" "<news.example.com>" "List-Id extracted from the raw header block, exactly once"
expect_eq "$(jq -r '.headers.precedence' <<<"$PAYLOAD")" "bulk" "Precedence extracted, exactly once"
expect_contains "$(jq -r '.headers["received-spf"]' <<<"$PAYLOAD")" "permitted sender" "folded Received-SPF is unfolded"
expect_contains "$(jq -r '.raw_message' <<<"$PAYLOAD")" "List-Id:" "raw_message carries the header block"
expect_contains "$(jq -r '.raw_message' <<<"$PAYLOAD")" "plain body text" "raw_message carries the body"

echo "== body larger than message_body_visible =="

LONG=$(awk 'BEGIN { for (i = 0; i < 400; i++) printf "the quick brown fox jumps over the lazy dog " }')
write_spool "$LONG"
run_check
BODYLEN=$(jq -r '.content | length' <<<"$(cat "$CURL_BODY_LOG")")
if (( BODYLEN > 500 )); then ok "more than 500 bytes of body reach the API ($BODYLEN)"; else bad "more than 500 bytes of body reach the API" "content was only $BODYLEN chars"; fi

echo "== MIME decoding =="

if command -v python3 >/dev/null 2>&1; then
    MIME_HDRS='From: Sender <sender@example.com>
Subject: =?UTF-8?B?TmEgY2h3aWzEmQ==?=
MIME-Version: 1.0
Content-Type: text/plain; charset="utf-8"
Content-Transfer-Encoding: base64'
    write_spool "$(printf 'ZmlybXdhcmUgdXBncmFkZSBub3RpY2U=\n')"
    run_check "Sender <sender@example.com>" "victim@example.org" "Na chwilę" "$MIME_HDRS"
    expect_contains "$(jq -r '.content' <<<"$(cat "$CURL_BODY_LOG")")" "firmware upgrade notice" "base64 body is MIME-decoded before scanning"
else
    echo "  skip base64 MIME decoding (no python3)"
fi

echo
printf 'passed: %d  failed: %d\n' "$PASS" "$FAIL"
(( FAIL == 0 )) || exit 1
