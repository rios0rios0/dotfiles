#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0

echo "[test-modify-scripts] testing modify scripts with sample input..." >&2

# Test a modify script by feeding input and checking output
test_modify() {
    local file="$1"
    local input="$2"
    local check_pattern="$3"
    local description="$4"

    if [ ! -f "$file" ]; then
        echo "[test-modify-scripts] SKIP: $description (file not found)" >&2
        return
    fi

    local output
    output=$(echo "$input" | bash "$file" 2>/dev/null) || {
        echo "[test-modify-scripts] FAIL: $description (script failed)" >&2
        EXIT_CODE=1
        return
    }

    if [ -n "$check_pattern" ] && ! echo "$output" | grep -qE "$check_pattern"; then
        echo "[test-modify-scripts] FAIL: $description (expected pattern '$check_pattern' not in output)" >&2
        EXIT_CODE=1
        return
    fi

    echo "[test-modify-scripts] PASS: $description" >&2
}

# Test termux.properties modify script
test_modify \
    "$REPO_ROOT/dot_termux/modify_termux.properties.tmpl" \
    "" \
    "extra-keys" \
    "termux.properties adds extra-keys"

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-modify-scripts] all modify script tests passed" >&2
fi

exit $EXIT_CODE
