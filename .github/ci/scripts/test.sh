#!/usr/bin/env bash
# Runs the repository's tests: every `test-<name>.sh` beside this script with bash, and every
# `test-<name>.ps1` with pwsh. `make test` runs them all; `make test ONLY="yq chlog"` runs the named
# ones. Every test runs even after one fails, and the exit status is non-zero when any did.
#
# A new test is a new script here: nothing else lists the tests.
set -uo pipefail

cd "$(dirname "$0")/../../.." || exit 1
TESTS_DIR='.github/ci/scripts'

names=("$@")
if [[ "${#names[@]}" -eq 0 ]]; then
    for script in "$TESTS_DIR"/test-*.sh "$TESTS_DIR"/test-*.ps1; do
        name="${script##*/test-}"
        names+=("${name%.*}")
    done
fi

failed=()
skipped=()
for name in "${names[@]}"; do
    if [[ -f "$TESTS_DIR/test-$name.sh" ]]; then
        bash "$TESTS_DIR/test-$name.sh" || failed+=("$name")
    elif [[ ! -f "$TESTS_DIR/test-$name.ps1" ]]; then
        echo "[test] FAIL: no test named '$name' in $TESTS_DIR" >&2
        failed+=("$name")
    elif command -v pwsh > /dev/null; then
        pwsh -NoProfile -File "$TESTS_DIR/test-$name.ps1" || failed+=("$name")
    elif [[ -n "${CI:-}" ]]; then
        # A skip on CI would pass a job that tested nothing.
        echo "[test] FAIL: $name needs pwsh, which is not installed" >&2
        failed+=("$name")
    else
        echo "[test] SKIP: $name needs pwsh, which is not installed" >&2
        skipped+=("$name")
    fi
done

if [[ "${#failed[@]}" -gt 0 ]]; then
    echo "[test] FAILED: ${failed[*]}" >&2
    exit 1
fi
echo "[test] $(( ${#names[@]} - ${#skipped[@]} )) passed, ${#skipped[@]} skipped" >&2
