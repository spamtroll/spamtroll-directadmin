#!/usr/bin/env bash
# Model DirectAdmin's native extraction into an existing plugin. A wrapper
# directory must fail even though tar extraction itself exits successfully.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="${1:-$REPO_DIR/plugin.tar.gz}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/plugin/data/cache"
printf 'preserved synthetic configuration\n' > "$WORK/plugin/data/spamtroll.conf"
chmod 750 "$WORK/plugin/data" "$WORK/plugin/data/cache"
printf 'version=0.0.0\n' > "$WORK/plugin/plugin.conf"
tar -xzf "$ARCHIVE" -C "$WORK/plugin"

cmp "$REPO_DIR/plugin.conf" "$WORK/plugin/plugin.conf"
cmp "$REPO_DIR/scripts/update.sh" "$WORK/plugin/scripts/update.sh"
test -x "$WORK/plugin/scripts/update.sh"
test ! -e "$WORK/plugin/spamtroll"
grep -qx 'preserved synthetic configuration' "$WORK/plugin/data/spamtroll.conf"
python3 - "$ARCHIVE" "$WORK/plugin/data" <<'PY'
import sys, tarfile, stat
from pathlib import Path
with tarfile.open(sys.argv[1]) as archive:
    members = archive.getmembers()
    assert len(members) == len({m.name for m in members}), 'duplicate entries'
    for member in members:
        parts = Path(member.name).parts
        assert not Path(member.name).is_absolute() and '..' not in parts
        assert parts[0] not in {'spamtroll', 'data', 'tests', '.github', '.git'}
        assert member.uid == member.gid == 0, 'archive ownership must be root'
    for name in ['plugin.conf', 'scripts/update.sh', 'LICENSE', 'README.md', 'CHANGELOG.md']:
        assert archive.getmember(name).isfile(), name
assert stat.S_IMODE(Path(sys.argv[2]).stat().st_mode) == 0o750
assert stat.S_IMODE(Path(sys.argv[2], 'cache').stat().st_mode) == 0o750
PY
echo 'ok: native extraction replaces active version/scripts and preserves data'
