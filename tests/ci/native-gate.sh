#!/usr/bin/env bash
#
# Gate for exim/check_message.conf.custom.post (native X-Spam-Status mapping).
#
# The pre-scan hook (acl_check_message.pre.conf, covered by acl-gate.sh)
# runs BEFORE SpamAssassin/rspamd in the DATA ACL, and that stage wipes
# every X-Spam-* header before writing its own verdict. So a native
# header added in pre.conf would never reach the mailbox whenever the
# recipient uses SA/rspamd — which is exactly when native handling
# matters. The translation into X-Spam-Status therefore lives in the
# Easy Spam Fighter *.custom.post slot: after the SA/rspamd stage, and
# — critically — before the ClamAV stage, whose stock file ends with a
# bare `accept` and must stay last. Anything included after it (notably
# DirectAdmin's own acl_check_message.post.conf slot) never executes;
# that placement bug shipped once and was caught live, so this gate
# stages a terminal `accept` after the hook exactly like clamav.conf:
# if the hook ever lands past a terminal verb again, every NATIVE case
# below goes red. This gate proves the whole assembly:
#
#   1. The post file holds no message-stopping verbs (same fail-open
#      contract as the pre file: deny/defer/drop/discard/require are
#      rejected after comment stripping).
#   2. The pre file never adds X-Spam-Status itself — native mapping is
#      the post file's job alone, so the two cannot fight.
#   3. `exim -bh` runs the chain pre -> fake SA -> post against a stub
#      scanner, once per interesting combination: Spamtroll spam with
#      SA ham/silent/skipped must yield our native Yes; SA spam must
#      keep SA's Yes untouched (never downgrade another engine);
#      everything else must add no X-Spam-Status at all. Every case
#      must still ACCEPT.
#
# The fake SA stage mirrors the stock DA behavior it stands in for
# (/etc/exim/spamd.acl_smtp_data.conf): unconditional
# `remove_header X-Spam-*`, then `acl_m_is_spam = 1` plus
# `X-Spam-Status: Yes` on spam only. The variable assignment is the
# load-bearing part: in-ACL add_header output is invisible to $h_ in
# the same run, so the post hook must read the variable, not the header.
#
# Needs Exim. All fixtures live in a temporary directory; the installed
# scanner is never overwritten. Staging into a world-readable temp dir
# sidesteps the TRUSTED_CONFIG_LIST demotion problem (see acl-gate.sh).

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PRE="${REPO_DIR}/exim/acl_check_message.pre.conf"
HOOK="${1:-$REPO_DIR/exim/check_message.conf.custom.post}"
EXIM="$(command -v exim4 || command -v exim)"
rc=0

if [[ -z "$EXIM" ]]; then
    echo "FAIL: no exim binary on PATH"
    exit 1
fi

echo "== 1. fail-open policy: no message-stopping verbs in hook file =="
hits=$(sed 's/#.*//' "$HOOK" | grep -nE '^[[:space:]]*(deny|defer|drop|discard|require)([[:space:]]|$)')
if [[ -n "$hits" ]]; then
    echo "  FAIL  the hook ACL can now stop mail:"
    awk '{ print "        " $0 }' <<<"$hits"
    rc=1
else
    echo "  ok  only fail-open verbs present"
fi

echo "== 2. division of labor: only the hook maps to X-Spam-Status =="
# Note: the literal "X-Spam-Status" is not a substring of
# "X-Spamtroll-Status", so the info headers never match this grep.
pre_adds=$(sed 's/#.*//' "$PRE" | grep -cE 'add_header.*X-Spam-Status' || true)
hook_adds=$(sed 's/#.*//' "$HOOK" | grep -cE 'add_header.*X-Spam-Status' || true)
if (( pre_adds != 0 )); then
    echo "  FAIL  pre file adds X-Spam-Status ${pre_adds}x (wiped by SA stage anyway)"
    rc=1
elif (( hook_adds != 1 )); then
    echo "  FAIL  hook file adds X-Spam-Status ${hook_adds}x, want exactly 1"
    rc=1
else
    echo "  ok  pre adds none, hook adds exactly one"
fi

echo "== 3. verdict translation (exim -bh: pre -> fake SA -> hook) =="
WORKDIR="$(mktemp -d /tmp/spamtroll-native-gate.XXXXXX)" || exit 1
STUB="$WORKDIR/spamtroll-check"
trap 'rm -rf "$WORKDIR"' EXIT
chmod 755 "$WORKDIR"
sed "s|/usr/local/bin/spamtroll-check|$STUB|g" "$PRE" > "$WORKDIR/pre.conf" || exit 1
cp "$HOOK" "$WORKDIR/hook.conf" || exit 1
chmod 644 "$WORKDIR/pre.conf" "$WORKDIR/hook.conf"

# Minimal config reproducing the stock DATA ACL order: our pre hook,
# then the SA/rspamd stage, then our hook, then a bare `accept`
# standing in for the terminal ClamAV stage (whose stock file must
# stay last and ends the ACL). The marker sits between hook and
# terminal accept: reached means the hook let the message through;
# the final ACCEPT means the whole chain completed. Routers and
# transports exist only so that -bh gets far enough to run the DATA ACL.
write_harness() {  # sa mode: spam | ham | off
    local sa="$1"
    {
        printf 'exim_path = %s\n' "$EXIM"
        printf 'spool_directory = %s/spool\n' "$WORKDIR"
        printf 'keep_environment = ^PATH$\n'
        printf 'acl_smtp_rcpt = acl_check_rcpt\n'
        printf 'acl_smtp_data = acl_check_message\n'
        printf 'domainlist local_domains = example.org\n'
        printf 'begin acl\n'
        printf 'acl_check_rcpt:\n  accept\nacl_check_message:\n'
        printf '  .include %s/pre.conf\n' "$WORKDIR"
        if [[ "$sa" != "off" ]]; then
            printf '  warn\n    remove_header = X-Spam-Bar : X-Spam-Score : X-Spam-Report : X-Spam-Status\n'
            if [[ "$sa" == "spam" ]]; then
                printf '  warn\n    set acl_m_is_spam = 1\n    add_header = X-Spam-Status: Yes, score=15.0\n'
            fi
        fi
        printf '  .include %s/hook.conf\n' "$WORKDIR"
        printf '  warn\n    add_header = X-Spamtroll-Test-After: reached\n  accept\n'
        printf 'begin routers\nr_local:\n  driver = accept\n  transport = t_null\nbegin transports\nt_null:\n  driver = appendfile\n  file = /dev/null\n  user = %s\n' "${USER:-root}"
    } > "$WORKDIR/harness.conf"
    chmod 644 "$WORKDIR/harness.conf"
}

native_case() {  # name, source-ip, stub exit, stub stdout, sa mode, expectation
    local name="$1" ip="$2" code="$3" score="$4" sa="$5" want="$6"

    printf '#!/bin/bash\nprintf %%s "%s"\nexit %s\n' "$score" "$code" > "$STUB"
    chmod 755 "$STUB"
    write_harness "$sa"

    local log
    log=$(printf 'HELO t.example.net\r\nMAIL FROM:<s@example.net>\r\nRCPT TO:<v@example.org>\r\nDATA\r\nFrom: S <s@example.net>\r\nTo: v@example.org\r\nSubject: hi\r\nMessage-Id: <a@b>\r\n\r\nbody\r\n.\r\nQUIT\r\n' \
        | "$EXIM" -bh "$ip" -C "$WORKDIR/harness.conf" 2>&1)

    local accepted=no
    grep -qE 'end of ACL "?acl_check_message"?: ACCEPT' <<<"$log" && accepted=yes
    local status
    status=$(grep -o 'X-Spam-Status: [^[:cntrl:]]*' <<<"$log" | tail -1)
    status="${status:-none}"

    local ok=no
    case "$want" in
        NATIVE) [[ "$status" == "X-Spam-Status: Yes, spamtroll score=${score}" ]] && ok=yes ;;
        SA)     [[ "$status" == "X-Spam-Status: Yes, score=15.0" ]] && ok=yes ;;
        NONE)   [[ "$status" == "none" ]] && ok=yes ;;
    esac
    # Our header must never appear alongside (or instead of) SA's verdict.
    if [[ "$want" == "SA" ]] && grep -q 'spamtroll score=' <<<"$log"; then
        ok=no
    fi

    if [[ "$accepted" == yes && "$ok" == yes ]] && grep -q 'X-Spamtroll-Test-After: reached' <<<"$log"; then
        printf '  ok    %-42s accept=%-3s %s\n' "$name" "$accepted" "$status"
    else
        printf '  FAIL  %-42s accept=%-3s %s (expected %s)\n' "$name" "$accepted" "$status" "$want"
        grep -iE -A1 'error|failed|refused|cannot|denied|rejected|[45][0-9][0-9] ' <<<"$log" \
            | grep -v '^--$' | head -6 | awk '{ print "          " $0 }'
        rc=1
    fi
}

native_case 'spamtroll spam + SA ham -> native Yes'    203.0.113.9 1 18  ham  NATIVE
native_case 'spamtroll spam + SA off -> native Yes'    203.0.113.9 1 18  off  NATIVE
native_case 'spamtroll spam + SA spam -> SA Yes kept'  203.0.113.9 1 18  spam SA
native_case 'spamtroll clean + SA ham -> no Status'    203.0.113.9 0 -14 ham  NONE
native_case 'spamtroll clean + SA spam -> SA Yes'      203.0.113.9 0 -14 spam SA
native_case 'suspicious + SA ham -> no Status'         203.0.113.9 3 5.5 ham  NONE
native_case 'scan error + SA ham -> no Status'        203.0.113.9 2 ''  ham  NONE
native_case 'spamtroll spam via loopback -> no Status' 127.0.0.1  1 18  ham  NONE

exit "$rc"
