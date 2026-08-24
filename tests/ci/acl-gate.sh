#!/usr/bin/env bash
#
# Gate for exim/acl_check_message.pre.conf.
#
# A syntax error in this file is not a failed build on someone's laptop;
# it is a customer's Exim refusing to start. And a `deny` or `defer`
# slipping in is the one regression that turns a spam filter into a mail
# outage. So the file is checked three ways:
#
#   1. `exim -bV -C` parses it inside a scaffold config, which catches
#      unknown verbs, conditions and modifiers with a line number.
#   2. A grep over the comment-stripped file rejects every verb that can
#      stop a message. The file legitimately *talks* about `deny` and
#      `defer` in prose, hence the comment stripping.
#   3. `exim -bh` actually runs the ACL against a fake SMTP session with
#      a stub spamtroll-check, once per exit code the script can produce
#      plus the two loopback addresses. This is the only check that sees
#      runtime expansion failures and host-list mistakes, neither of
#      which -bV can detect: Exim expands strings lazily.
#
# Needs exim4-daemon-light and root (for /usr/local/bin/spamtroll-check).

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ACL="${1:-$REPO_DIR/exim/acl_check_message.pre.conf}"
EXIM="$(command -v exim4 || command -v exim)"
HARNESS=/tmp/spamtroll-acl-harness.conf
STUB=/usr/local/bin/spamtroll-check
rc=0

if [[ -z "$EXIM" ]]; then
    echo "FAIL: no exim binary on PATH"
    exit 1
fi

# Minimal config that reproduces how DirectAdmin pulls the file in: an
# .include inside acl_check_message. The routers/transports exist only
# so that -bh gets far enough to run the DATA ACL.
cat > "$HARNESS" <<HARNESS_EOF
exim_path = ${EXIM}
spool_directory = /var/spool/exim4
keep_environment = ^PATH\$
acl_smtp_rcpt = acl_check_rcpt
acl_smtp_data = acl_check_message
domainlist local_domains = example.org
begin acl
acl_check_rcpt:
  accept
acl_check_message:
  .include ${ACL}
  accept
begin routers
r_local:
  driver = accept
  transport = t_null
begin transports
t_null:
  driver = appendfile
  file = /dev/null
  user = Debian-exim
HARNESS_EOF

echo "== 1. ACL syntax (exim -bV) =="
if out=$("$EXIM" -bV -C "$HARNESS" 2>&1) && ! grep -qi 'configuration error' <<<"$out"; then
    echo "  ok  parses under $("$EXIM" -bV 2>/dev/null | head -1 | cut -d' ' -f1-3)"
else
    echo "  FAIL  the ACL does not parse:"
    grep -i 'error' <<<"$out" | awk '{ print "        " $0 }'
    rc=1
fi

echo "== 2. fail-open policy: no message-stopping verbs =="
hits=$(sed 's/#.*//' "$ACL" | grep -nE '^[[:space:]]*(deny|defer|drop|discard|require)([[:space:]]|$)')
if [[ -n "$hits" ]]; then
    echo "  FAIL  the ACL can now stop mail:"
    awk '{ print "        " $0 }' <<<"$hits"
    echo "        Fail-open is the product's contract; see the header of the ACL file."
    rc=1
else
    verbs=$(sed 's/#.*//' "$ACL" | grep -oE '^[[:space:]]*(accept|warn)([[:space:]]|$)' | tr -d ' \t' | sort -u | tr '\n' ' ')
    echo "  ok  only fail-open verbs present: ${verbs}"
fi

echo "== 3. ACL execution (exim -bh) =="
acl_case() {  # name, source-ip, stub exit code ('absent' = no script), stub stdout, expected header
    local name="$1" ip="$2" code="$3" score="$4" want="$5"

    if [[ "$code" == "absent" ]]; then
        rm -f "$STUB"
    else
        printf '#!/bin/bash\nprintf %%s "%s"\nexit %s\n' "$score" "$code" > "$STUB"
        chmod 755 "$STUB"
    fi

    local log
    log=$(printf 'HELO t.example.net\r\nMAIL FROM:<s@example.net>\r\nRCPT TO:<v@example.org>\r\nDATA\r\nFrom: S <s@example.net>\r\nTo: v@example.org\r\nSubject: hi\r\nMessage-Id: <a@b>\r\n\r\nbody\r\n.\r\nQUIT\r\n' \
        | "$EXIM" -bh "$ip" -C "$HARNESS" 2>&1)

    local accepted=no got
    grep -q 'end of ACL "acl_check_message": ACCEPT' <<<"$log" && accepted=yes
    got=$(grep -o 'X-Spamtroll-Status: [a-z]*' <<<"$log" | tail -1)
    got="${got:-none}"

    if [[ "$accepted" == yes && "$got" == "$want" ]]; then
        printf '  ok    %-30s accept=%-3s %s\n' "$name" "$accepted" "$got"
    else
        printf '  FAIL  %-30s accept=%-3s %s (expected %s)\n' "$name" "$accepted" "$got" "$want"
        rc=1
    fi

    grep -m1 -o 'malformed[^)]*' <<<"$log" | awk '{ print "          exim warning: " $0 }'
}

acl_case 'exit 0 -> clean'        203.0.113.9 0      1.0 'X-Spamtroll-Status: clean'
acl_case 'exit 1 -> spam'         203.0.113.9 1      9.5 'X-Spamtroll-Status: spam'
acl_case 'exit 2 -> fail-open'    203.0.113.9 2      ''  none
acl_case 'exit 3 -> suspicious'   203.0.113.9 3      5.5 'X-Spamtroll-Status: suspicious'
acl_case 'exit 127 -> fail-open'  203.0.113.9 127    ''  none
acl_case 'script missing'         203.0.113.9 absent ''  none
acl_case 'IPv4 loopback skipped'  127.0.0.1   0      1.0 none
acl_case 'IPv6 loopback skipped'  ::1         0      1.0 none

exit "$rc"
