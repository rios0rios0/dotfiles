#!/bin/bash
set -euo pipefail

# Tests two functions dot_zshrc.tmpl defines on Linux and Android alike: `top-size`, which lists the
# biggest entries under a directory, and `sentry-ds`, which runs the Sentry CLI on the work account.
#
# The template is rendered for both platforms and only those blocks are sourced, in a bare zsh, so no
# plugin loads. du, sort, sed and head are the real ones, reached through a PATH that holds nothing
# else: every CI runner has a sudo, and a sudo found on the host would decide which branch of
# `top-size` runs. sudo, sentry and the completion system are stubs.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-zshrc-functions] testing top-size and sentry-ds in dot_zshrc.tmpl..." >&2

pass() { echo "[test-zshrc-functions] PASS: $1" >&2; }
fail() { echo "[test-zshrc-functions] FAIL: $1" >&2; EXIT_CODE=1; }

for tool in chezmoi zsh; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[test-zshrc-functions] FAIL: $tool not installed" >&2
        exit 1
    fi
done
ZSH_BIN="$(type -P zsh)"

# dot_zshrc.tmpl reads nothing but .chezmoi, so a config of its own keeps the host's out of the render
cat > "$TMP/chezmoi.yaml" <<EOF
sourceDir: "$REPO_ROOT"
data:
  deviceName: "testdevice"
EOF

mkdir -p "$TMP/bin/plain" "$TMP/bin/with-sudo" "$TMP/bin/sentry"
for tool in du sed sort head test; do
    ln -s "$(type -P "$tool")" "$TMP/bin/plain/$tool"
    ln -s "$(type -P "$tool")" "$TMP/bin/with-sudo/$tool"
done
# Records each call, answers `sudo -v` with $SUDO_VALIDATE_STATUS, and runs everything else as is
cat > "$TMP/bin/with-sudo/sudo" <<EOF
#!/bin/bash
echo "\$*" >> "$TMP/sudo.log"
[[ "\$1" == -v ]] && exit "\${SUDO_VALIDATE_STATUS:-0}"
exec "\$@"
EOF
for tool in env printenv; do
    ln -s "$(type -P "$tool")" "$TMP/bin/sentry/$tool"
done
cat > "$TMP/bin/sentry/sentry" <<'EOF'
#!/bin/sh
printf 'config=%s\n' "${SENTRY_CONFIG_DIR-<unset>}"
printf 'auth-token=%s\n' "${SENTRY_AUTH_TOKEN-<unset>}"
printf 'token=%s\n' "${SENTRY_TOKEN-<unset>}"
printf 'org=%s\n' "${SENTRY_ORG-<unset>}"
printf '<%s>\n' "$@"
EOF
chmod +x "$TMP/bin/with-sudo/sudo" "$TMP/bin/sentry/sentry"

# The space in the path catches an unquoted expansion. The bytes are random because a file system
# that compresses would shrink zeros and reorder the ranking.
TREE="$TMP/a tree"
mkdir -p "$TREE/.cache" "$TREE/big/nested"
head -c 6291456 /dev/urandom > "$TREE/.cache/blob"
head -c 3145728 /dev/urandom > "$TREE/big/blob"
head -c 1048576 /dev/urandom > "$TREE/big/nested/blob"
head -c 2097152 /dev/urandom > "$TREE/mid.bin"
printf 'x' > "$TREE/small.txt"
ln -s "$TREE" "$TMP/tree-link"

# Runs top-size from a directory: `run_top_size <block> <bin-dir> <cwd> [args...]`. Leaves stdout in
# $TMP/out, stderr in $TMP/err, the status in $STATUS, and starts each run with an empty sudo log.
run_top_size() {
    local block="$1" bin="$2" cwd="$3"
    shift 3
    : > "$TMP/sudo.log"
    STATUS=0
    (cd "$cwd" && LC_ALL=C PATH="$bin" "$ZSH_BIN" -f -c 'source "$1"; shift; top-size "$@"' _ "$block" "$@") \
        > "$TMP/out" 2> "$TMP/err" || STATUS=$?
}

# The path column of what top-size printed, one entry per line
listed() { cut -f2- "$TMP/out"; }

check() {
    local description="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        pass "$description"
    else
        fail "$description"
        echo "  expected: '$expected'" >&2
        echo "  actual:   '$actual'" >&2
    fi
}

for platform in linux android; do
    rendered="$TMP/zshrc-$platform.zsh"
    if ! chezmoi execute-template --config "$TMP/chezmoi.yaml" \
        --override-data "{\"chezmoi\":{\"os\":\"$platform\"}}" \
        < "$REPO_ROOT/dot_zshrc.tmpl" > "$rendered"; then
        fail "$platform: dot_zshrc.tmpl does not render"
        continue
    fi

    top_size="$TMP/top-size-$platform.zsh"
    sentry_ds="$TMP/sentry-ds-$platform.zsh"
    awk '/^top-size\(\) \{$/, /^\}$/' "$rendered" > "$top_size"
    awk '/^unalias sentry-ds /, /^fi$/' "$rendered" > "$sentry_ds"
    # Both fail loudly if a block is renamed or moves under a platform conditional, rather than
    # leaving the cases below with nothing to test
    if ! grep -q 'du ' "$top_size"; then
        fail "$platform: no top-size function in the rendered zshrc"
        continue
    fi
    if ! grep -q 'compdef _sentry-ds sentry-ds' "$sentry_ds"; then
        fail "$platform: no sentry-ds block in the rendered zshrc"
        continue
    fi

    # --- top-size --------------------------------------------------------------------------------

    # given no sudo, as on Termux
    # when top-size runs with its defaults
    run_top_size "$top_size" "$TMP/bin/plain" "$TREE"
    # then every entry is listed largest first, the hidden one too, and the directory's own total is not
    check "$platform: lists the entries largest first, hidden ones included, without the total" \
        "$(printf '%s\n' ./.cache ./big ./mid.bin ./small.txt)" "$(listed)"

    # given a count
    # when / then only that many are listed
    run_top_size "$top_size" "$TMP/bin/plain" "$TREE" 2
    check "$platform: stops at the count" "$(printf '%s\n' ./.cache ./big)" "$(listed)"

    # given a depth of 2
    # when top-size runs
    run_top_size "$top_size" "$TMP/bin/plain" "$TREE" 10 2
    # then entries two levels down are listed, and nothing deeper
    entries="$(listed)"
    check "$platform: lists two levels down at depth 2" "7 yes no" \
        "$(wc -l <<< "$entries" | tr -d ' ') $(grep -qx './big/nested' <<< "$entries" && echo yes || echo no) $(grep -qx './big/nested/blob' <<< "$entries" && echo yes || echo no)"

    # given a directory with a space in its path, named from somewhere else
    # when / then its entries are listed under the name given
    run_top_size "$top_size" "$TMP/bin/plain" "$TMP" 2 1 "$TREE"
    check "$platform: lists the directory it is given" "$(printf '%s\n' "$TREE/.cache" "$TREE/big")" "$(listed)"

    # given a symlink to a directory, such as Termux's ~/storage/shared
    # when / then the directory behind it is listed, not the link itself
    run_top_size "$top_size" "$TMP/bin/plain" "$TMP" 2 1 "$TMP/tree-link"
    check "$platform: follows a symlinked directory" \
        "$(printf '%s\n' "$TMP/tree-link/.cache" "$TMP/tree-link/big")" "$(listed)"

    # given arguments it cannot use
    # when / then each one fails with the usage on stderr and nothing on stdout
    for args in "0" "abc" "-1" "5 0" "5 4" "5 x" "5 1 . extra"; do
        # shellcheck disable=SC2086 # split on purpose: each string is one argument list
        run_top_size "$top_size" "$TMP/bin/plain" "$TREE" $args
        check "$platform: rejects \`top-size $args\`" \
            "1 [top-size] ERROR: usage: top-size [count] [depth: 1-3] [dir] " \
            "$STATUS $(cat "$TMP/err") $(cat "$TMP/out")"
    done

    # given something that is not a directory
    # when / then it fails before du runs, naming the path
    for target in "$TREE/mid.bin" "$TMP/missing"; do
        run_top_size "$top_size" "$TMP/bin/plain" "$TMP" 5 1 "$target"
        check "$platform: rejects ${target#"$TMP"/} as not a directory" \
            "1 [top-size] ERROR: not a directory: $target " "$STATUS $(cat "$TMP/err") $(cat "$TMP/out")"
    done

    if [[ "$(id -u)" -eq 0 ]]; then
        echo "[test-zshrc-functions] SKIP: $platform: sudo cases (running as root, where top-size never uses sudo)" >&2
    else
        # given sudo and a user other than root
        # when top-size runs
        run_top_size "$top_size" "$TMP/bin/with-sudo" "$TREE" 2
        # then sudo authenticates first, and both the directory check and du run through it
        check "$platform: reads through sudo where it exists" \
            "$(printf '%s\n' ./.cache ./big) | -v test du" \
            "$(listed) | $(cut -d' ' -f1 "$TMP/sudo.log" | tr '\n' ' ' | sed 's/ $//')"

        # given a sudo that refuses to authenticate
        # when / then top-size fails instead of printing an empty list, and du never runs
        SUDO_VALIDATE_STATUS=1 run_top_size "$top_size" "$TMP/bin/with-sudo" "$TREE"
        check "$platform: fails when sudo refuses" "1 | -v" "$STATUS | $(cat "$TMP/out")$(cat "$TMP/sudo.log")"
    fi

    # --- sentry-ds -------------------------------------------------------------------------------

    # given an alias of the same name from an earlier version, tokens and an org in the environment,
    # no XDG_CONFIG_HOME, and a `sentry` shell function
    # when the block is sourced twice and sentry-ds runs
    actual="$(env -u XDG_CONFIG_HOME LC_ALL=C PATH="$TMP/bin/sentry" HOME="$TMP/home" \
        SENTRY_AUTH_TOKEN=fixture-token-placeholder SENTRY_TOKEN=fixture-token-placeholder \
        SENTRY_ORG=fixture-org "$ZSH_BIN" -f -c '
            alias sentry-ds="false"
            source "$1"
            source "$1"
            sentry() { return 97; }
            sentry-ds issue list "two words" "" "*.go"
            print -r -- "caller=$SENTRY_AUTH_TOKEN,$SENTRY_TOKEN"
        ' _ "$sentry_ds" 2>&1)" || true
    # then the CLI gets the work store and no token, the org and the arguments pass through as given,
    # and the calling shell keeps its tokens
    check "$platform: runs the CLI on the work store, without the exported tokens" \
        "$(printf '%s\n' "config=$TMP/home/.config/sentry-darksense" 'auth-token=<unset>' 'token=<unset>' \
            'org=fixture-org' '<issue>' '<list>' '<two words>' '<>' '<*.go>' \
            'caller=fixture-token-placeholder,fixture-token-placeholder')" \
        "$actual"

    # given XDG_CONFIG_HOME, where the CLI keeps the personal store
    # when / then the work store sits beside it
    actual="$(LC_ALL=C PATH="$TMP/bin/sentry" HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" "$ZSH_BIN" -f -c '
            source "$1"
            sentry-ds
        ' _ "$sentry_ds" 2>&1 | head -1)" || true
    check "$platform: keeps the work store beside the personal one under XDG_CONFIG_HOME" \
        "config=$TMP/xdg/sentry-darksense" "$actual"

    # given the completion system and Sentry's completion
    # when the block is sourced and sentry-ds is completed
    actual="$(LC_ALL=C PATH="$TMP/bin/sentry" HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" "$ZSH_BIN" -f -c '
            compdef() { print -r -- "compdef $*"; }
            _sentry() { printenv SENTRY_CONFIG_DIR; }
            source "$1"
            _sentry-ds
        ' _ "$sentry_ds" 2>&1)" || true
    # then it is registered, and the CLI that Sentry's completion runs for slugs reads the work store
    check "$platform: completes like sentry, with slugs from the work store" \
        "$(printf '%s\n' 'compdef _sentry-ds sentry-ds' "$TMP/xdg/sentry-darksense")" "$actual"

    # given neither the completion system nor Sentry's completion, as before Oh My Zsh is installed
    # when / then the block sources silently and with status 0, and sentry-ds is still defined
    actual="$(LC_ALL=C PATH="$TMP/bin/sentry" HOME="$TMP/home" "$ZSH_BIN" -f -c '
            source "$1"
            print -r -- "status=$?"
            whence -w sentry-ds
        ' _ "$sentry_ds" 2>&1)" || true
    check "$platform: sources cleanly without a completion system" \
        "$(printf '%s\n' 'status=0' 'sentry-ds: function')" "$actual"
done

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-zshrc-functions] all cases passed" >&2
fi

exit $EXIT_CODE
