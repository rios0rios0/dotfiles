#!/bin/bash
set -euo pipefail

# Guards the contract of the unattended `terra update` calls in both dependency installers:
# since terra 1.16.10 that command skips the update -- reporting "Non-interactive session -
# skipping update of <name>. Set TERRA_ASSUME_YES=true" -- whenever stdin is not a terminal,
# a pipe included, so a `yes y` pipe alone leaves an unattended `chezmoi apply` downloading
# nothing. Every invocation must carry TERRA_ASSUME_YES=true.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0

echo "[test-terra-update] testing the unattended terra update calls..." >&2

pass() { echo "[test-terra-update] PASS: $1" >&2; }
fail() { echo "[test-terra-update] FAIL: $1" >&2; EXIT_CODE=1; }

# check_installer <label> <file>: every non-comment line that invokes `terra update` must set
# TERRA_ASSUME_YES=true on the same line.
check_installer() {
    local label="$1"
    local file="$2"
    local invocations
    invocations="$(grep -v '^[[:space:]]*#' "$file" | grep 'terra update' || true)"

    if [[ -z "$invocations" ]]; then
        fail "$label no longer calls 'terra update' at all"
        return
    fi

    if grep -q 'TERRA_ASSUME_YES=true terra update' <<<"$invocations"; then
        pass "$label sets TERRA_ASSUME_YES on its terra update"
    else
        fail "$label calls 'terra update' without TERRA_ASSUME_YES=true: $invocations"
    fi

    local missing
    missing="$(grep -v 'TERRA_ASSUME_YES=true' <<<"$invocations" || true)"
    if [[ -n "$missing" ]]; then
        fail "$label has a terra update invocation without the variable: $missing"
    fi
}

check_installer "the Linux installer" "$REPO_ROOT/.chezmoiscripts/run_once_before_linux-002-install-dependencies.sh.tmpl"
check_installer "the Android installer" "$REPO_ROOT/.chezmoiscripts/run_once_before_android-002-install-dependencies.sh.tmpl"

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-terra-update] all terra update tests passed" >&2
fi
exit $EXIT_CODE
