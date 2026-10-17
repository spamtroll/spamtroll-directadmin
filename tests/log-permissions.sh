#!/usr/bin/env bash
# Exercise the actual lifecycle scripts and logrotate in an isolated
# filesystem fixture. Only their fixed installation paths are rewritten;
# the DirectAdmin rebuild command is replaced by a harmless fixture.
# Requires Linux, root, admin/mail accounts, python3 and logrotate.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo 'FAIL: run this fixture as root'; exit 1; }
for tool in python3 logrotate runuser; do
    command -v "$tool" >/dev/null || { echo "FAIL: missing $tool"; exit 1; }
done
id admin >/dev/null
getent group mail >/dev/null

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d /tmp/spamtroll-log-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
chmod 755 "$WORK"
PLUGIN="$WORK/usr/local/directadmin/plugins/spamtroll"
mkdir -p "$PLUGIN" "$WORK/usr/local/bin" "$WORK/etc/logrotate.d" "$WORK/var/log"
cp -r "$REPO_DIR/scripts" "$REPO_DIR/exim" "$PLUGIN/"

python3 - "$WORK" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
plugin = root / 'usr/local/directadmin/plugins/spamtroll'
for path in [*plugin.joinpath('scripts').glob('*.sh'), plugin/'exim/spamtroll-logrotate']:
    text = path.read_text()
    for prefix in ['/usr/local/directadmin', '/usr/local/bin', '/etc/exim.acl_check_message.pre.conf', '/etc/exim.acl_check_message.post.conf', '/etc/logrotate.d', '/var/log']:
        text = text.replace(prefix, str(root) + prefix)
    path.write_text(text)
PY

cat > "$WORK/usr/local/directadmin/directadmin" <<'SH'
#!/bin/bash
[[ "$*" == 'build exim_conf' ]] || exit 1
echo 'fixture: Exim rebuild requested'
SH
chmod 755 "$WORK/usr/local/directadmin/directadmin"

assert_writable() {
    local path="$1"
    [[ "$(stat -c '%a %U %G' "$path")" == '660 admin mail' ]]
    printf 'mail fixture\n' | runuser -u mail -- tee -a "$path" >/dev/null
    printf 'admin fixture\n' | runuser -u admin -- tee -a "$path" >/dev/null
    echo "  ok  mail and admin can append to ${path#"$WORK"}"
}

# Reproduce the production failure: a log created by old logrotate.
mkdir -p "$PLUGIN/data"
printf 'ENABLED=false\nAPI_KEY="fixture-not-a-real-key"\n' > "$PLUGIN/data/spamtroll.conf"
CONFIG_HASH="$(sha256sum "$PLUGIN/data/spamtroll.conf")"
printf 'preserved log entry\n' > "$WORK/var/log/spamtroll.log"
chmod 640 "$WORK/var/log/spamtroll.log"
chown root:root "$WORK/var/log/spamtroll.log"
if runuser -u mail -- test -w "$WORK/var/log/spamtroll.log"; then
    echo 'FAIL: old rotation fixture should be unwritable'
    exit 1
fi

bash "$PLUGIN/scripts/update.sh" > "$WORK/update.out"
assert_writable "$WORK/var/log/spamtroll.log"
assert_writable "$WORK/var/log/spamtroll/quota_skipped.log"
grep -q 'preserved log entry' "$WORK/var/log/spamtroll.log"
[[ "$(sha256sum "$PLUGIN/data/spamtroll.conf")" == "$CONFIG_HASH" ]]
[[ "$(readlink "$WORK/usr/local/bin/spamtroll-check")" == "$PLUGIN/exim/spamtroll-check" ]]
[[ -f "$WORK/etc/exim.acl_check_message.post.conf" ]]
grep -q 'X-Spam-Status: Yes, spamtroll' "$WORK/etc/exim.acl_check_message.post.conf"
echo '  ok  update preserves configuration, old log and scanner symlink'

bash "$PLUGIN/scripts/update.sh" > "$WORK/update-again.out"
assert_writable "$WORK/var/log/spamtroll.log"
[[ "$(sha256sum "$PLUGIN/data/spamtroll.conf")" == "$CONFIG_HASH" ]]
echo '  ok  repeated update preserves configuration'

logrotate --force --state "$WORK/logrotate.state" "$WORK/etc/logrotate.d/spamtroll"
assert_writable "$WORK/var/log/spamtroll.log"
assert_writable "$WORK/var/log/spamtroll/quota_skipped.log"
grep -q 'preserved log entry' "$WORK/var/log/spamtroll.log.1"
echo '  ok  actual rotation preserves history and writable logs'

# A separate fresh fixture state also exercises the installer path.
rm "$PLUGIN/data/spamtroll.conf" "$WORK/var/log/spamtroll.log" "$WORK/var/log/spamtroll/quota_skipped.log"
bash "$PLUGIN/scripts/install.sh" > "$WORK/install.out"
assert_writable "$WORK/var/log/spamtroll.log"
assert_writable "$WORK/var/log/spamtroll/quota_skipped.log"
grep -q '^ENABLED=false$' "$PLUGIN/data/spamtroll.conf"
[[ "$(stat -c '%a %U %G' "$PLUGIN/data/spamtroll.conf")" == '640 admin mail' ]]
echo '  ok  fresh install provisions logs and keeps scanning disabled'
