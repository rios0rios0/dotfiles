# shellcheck shell=bash
# Shared by the Sentry CLI setup scripts, run_onchange_after_linux-007-setup-sentry-cli.sh.tmpl and
# run_onchange_after_android-006-setup-sentry-cli.sh.tmpl, which include it as a chezmoi template, so
# it must stay pure bash, without template directives.
#
# `sentry-ds` in dot_zshrc.tmpl keeps the work account apart through SENTRY_CONFIG_DIR, which the
# CLI honours from 0.47.0. An older CLI ignores the variable without a word, so `sentry-ds` would run
# on the personal login, and `sentry-ds auth login` would replace it. The dependency installers only
# install the CLI where none exists and never upgrade it, so the setup scripts hold every machine at
# this floor. Raising it changes both scripts, and the next apply re-runs them everywhere.
SENTRY_CLI_MIN_VERSION="0.47.0"

# Prints the version the CLI on PATH reports, or nothing when it reports none
sentry_cli_version() {
    local output
    output="$(sentry --version 2>/dev/null)" || return 0
    if [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
        printf '%s\n' "${BASH_REMATCH[0]}"
    fi
}

# True when version $1 is version $2 or newer; both are MAJOR.MINOR.PATCH
sentry_cli_version_at_least() {
    local have_version="$1" want_version="$2"
    local -a have want
    local i
    IFS=. read -r -a have <<< "$have_version"
    IFS=. read -r -a want <<< "$want_version"
    for i in 0 1 2; do
        (( 10#${have[i]} > 10#${want[i]} )) && return 0
        (( 10#${have[i]} < 10#${want[i]} )) && return 1
    done
    return 0
}

# Upgrades the CLI on PATH when it is older than SENTRY_CLI_MIN_VERSION, or reports no version, with
# `sentry cli upgrade`: it upgrades through whichever method installed the CLI (npm, the curl
# installer, ...), where an `npm install` would leave a standalone binary ahead of it on PATH.
# Returns non-zero, saying why, when the CLI is still older afterwards.
ensure_sentry_cli_version() {
    local prefix="$1" current
    current="$(sentry_cli_version)"
    if [[ -n "$current" ]] && sentry_cli_version_at_least "$current" "$SENTRY_CLI_MIN_VERSION"; then
        return 0
    fi

    echo "[$prefix] the Sentry CLI is ${current:-of an unknown version}, older than $SENTRY_CLI_MIN_VERSION; upgrading..." >&2
    if ! sentry cli upgrade >&2; then
        echo "[$prefix] ERROR: sentry cli upgrade failed; sentry-ds needs $SENTRY_CLI_MIN_VERSION or newer" >&2
        return 1
    fi

    hash -r
    current="$(sentry_cli_version)"
    if [[ -z "$current" ]] || ! sentry_cli_version_at_least "$current" "$SENTRY_CLI_MIN_VERSION"; then
        echo "[$prefix] ERROR: the Sentry CLI is still ${current:-of an unknown version} after sentry cli upgrade; sentry-ds needs $SENTRY_CLI_MIN_VERSION or newer" >&2
        return 1
    fi
    echo "[$prefix] upgraded the Sentry CLI to $current" >&2
}
