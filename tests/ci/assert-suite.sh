#!/usr/bin/env bash
#
# CI wrapper around tests/run-tests.sh.
#
# run-tests.sh exits 0 when a test is skipped for a missing optional
# dependency, so a runner without python3 turns the MIME-decoding
# assertions into a silent no-op. On a developer's laptop that is a
# convenience; in CI it is lost coverage that nobody notices. This
# wrapper turns any skip into a failure and insists that the summary
# line was actually reached, which a mid-suite abort would swallow.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

out=$(./tests/run-tests.sh 2>&1)
rc=$?
printf '%s\n' "$out"

echo "--- CI assertions ---"

if (( rc != 0 )); then
    echo "FAIL: run-tests.sh exited ${rc}"
    exit 1
fi

if grep -q '^  skip' <<<"$out"; then
    echo "FAIL: the suite skipped tests; the runner is missing a dependency"
    grep '^  skip' <<<"$out" | sed 's/^/       /'
    exit 1
fi

if ! grep -qE '^passed: [0-9]+  failed: 0$' <<<"$out"; then
    echo "FAIL: no summary line; the suite aborted part-way through"
    exit 1
fi

echo "ok: $(grep -oE '^passed: .*' <<<"$out"), no skips"
