#!/usr/bin/env bash
#
# plugin.conf is what DirectAdmin reads, so it is the single source of
# truth for the plugin version. Everything else has to agree with it:
# the CHANGELOG must describe the version we ship, and the admin panel
# must not display a number of its own.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

rc=0

plugin_version=$(sed -n 's/^version=//p' plugin.conf | head -1)
if [[ -z "$plugin_version" ]]; then
    echo "FAIL: plugin.conf has no version= line"
    exit 1
fi
printf '%-22s %s\n' 'plugin.conf' "$plugin_version"

changelog_version=$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | head -1 | tr -d '#[] ')
printf '%-22s %s\n' 'CHANGELOG.md' "${changelog_version:-none}"
if [[ "$changelog_version" != "$plugin_version" ]]; then
    echo "FAIL: shipping ${plugin_version}, but the newest CHANGELOG release is ${changelog_version:-none}"
    rc=1
fi

hardcoded=$(grep -ohE 'v[0-9]+\.[0-9]+\.[0-9]+' admin/index.html | tr -d 'v' | sort -u)
if [[ -n "$hardcoded" ]]; then
    printf '%-22s %s\n' 'admin/index.html' "$(tr '\n' ' ' <<<"$hardcoded")"
    while read -r v; do
        [[ -z "$v" || "$v" == "$plugin_version" ]] && continue
        echo "FAIL: the admin panel shows v${v}, plugin.conf says ${plugin_version}"
        rc=1
    done <<<"$hardcoded"
else
    printf '%-22s %s\n' 'admin/index.html' 'reads plugin.conf (no hardcoded version)'
fi

(( rc == 0 )) && echo "ok: versions agree"
exit "$rc"
