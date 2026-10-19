#!/usr/bin/env bash
set -euo pipefail

# Pins local-services/omniroute/compose.yaml to the image built from the newest successful
# run of the fork's publish workflow, by digest.
#
# Why a digest and not the branch tag: `feat/model-quota-api` moves on every push, so a tag
# cannot name the code a running container holds. The fork publishes `sha-<full commit>` for
# each build; asking GitHub for the newest successful run and resolving that tag ties the pin
# to a commit that passed the build, and the digest ties it to the exact image bytes.
#
# Requires `gh` (authenticated to the fork) and `docker` with buildx. A private package needs
# `docker login ghcr.io` first; a public one resolves anonymously.
#
# Usage:
#   ./update-image.sh              # pin the newest successful build of feat/model-quota-api
#   ./update-image.sh --check      # exit 1 when compose does not hold that digest
#   ./update-image.sh --tag TAG    # pin TAG instead (e.g. a release tag), bypassing GitHub
#   ./update-image.sh --file PATH  # rewrite another compose file
#
# Environment:
#   OMNIROUTE_IMAGE    image repository (default ghcr.io/rios0rios0/omniroute)
#   OMNIROUTE_COMPOSE  compose file (default compose.yaml beside this script)

prefix="omniroute-image"
repo="rios0rios0/OmniRoute"
workflow="publish-ghcr.yml"
branch="feat/model-quota-api"
image="${OMNIROUTE_IMAGE:-ghcr.io/rios0rios0/omniroute}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
compose="${OMNIROUTE_COMPOSE:-$script_dir/compose.yaml}"

log() { echo "[$prefix] $*" >&2; }
fail() { echo "[$prefix] ERROR: $*" >&2; exit 1; }

usage() {
    cat >&2 <<EOF
Usage: update-image.sh [--check] [--tag TAG] [--file PATH] [--help]

Pins the OmniRoute service in the Compose file to the image digest built from the newest
successful run of $workflow on $repo ($branch).

  --check       print the pinned and available digests; exit 1 when they differ
  --tag TAG     pin TAG instead of the newest build (bypasses the GitHub lookup)
  --file PATH   rewrite PATH instead of $compose

Environment overrides:
  OMNIROUTE_IMAGE    image repository (default $image)
  OMNIROUTE_COMPOSE  compose file (default the one beside this script)
EOF
}

check=false
tag=""
while (( $# > 0 )); do
    case "$1" in
        --check)
            check=true
            ;;
        --tag)
            (( $# >= 2 )) || fail "--tag requires a value; see --help"
            tag="$2"
            shift
            ;;
        --file)
            (( $# >= 2 )) || fail "--file requires a value; see --help"
            compose="$2"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            fail "unexpected argument '$1'; see --help"
            ;;
    esac
    shift
done

[[ -f "$compose" ]] || fail "no Compose file at $compose"
[[ -n "$image" ]] || fail "OMNIROUTE_IMAGE is empty"

# The service may still point at the official upstream image on the first run; both shapes
# are rewritable so the switch needs no manual edit. Any other image (redis, a sidecar) is
# left alone.
image_re='ghcr\.io/(rios0rios0|diegosouzapw)/omniroute'
matches="$(grep -cE "^[[:space:]]*image:[[:space:]]*'?${image_re}@sha256:[0-9a-f]{64}'?[[:space:]]*$" "$compose" || true)"
if [[ "$matches" != "1" ]]; then
    fail "expected exactly one found OmniRoute image digest in $compose, found $matches"
fi
current="$(grep -E "^[[:space:]]*image:[[:space:]]*'?${image_re}@sha256:[0-9a-f]{64}'?[[:space:]]*$" "$compose" \
    | sed -E 's/.*@(sha256:[0-9a-f]{64}).*/\1/')"

if [[ -n "$tag" ]]; then
    ref="$tag"
    log "resolving $image:$ref"
else
    command -v gh >/dev/null 2>&1 || fail "gh is required to find the newest build; install it or pass --tag"
    run="$(gh api "repos/$repo/actions/workflows/$workflow/runs?branch=$branch&status=success&per_page=1" \
        --jq '.workflow_runs[0] | [(.head_sha // ""), (.created_at // ""), (.html_url // "")] | @tsv' 2>/dev/null)" \
        || fail "could not read the workflow runs from $repo; is gh authenticated?"
    # `cut`, not `read` with IFS=$'\t': bash treats a tab as IFS whitespace and drops a leading
    # empty field, which would make an empty head_sha shift the timestamp into $sha.
    sha="$(printf '%s\n' "$run" | cut -f1)"
    created="$(printf '%s\n' "$run" | cut -f2)"
    url="$(printf '%s\n' "$run" | cut -f3)"
    [[ -n "$sha" ]] || fail "no successful run of $workflow on $branch yet; push to the branch and let the build finish"
    ref="sha-$sha"
    log "newest successful build: ${sha:0:10} ($created) $url"
    log "resolving $image:$ref"
fi

command -v docker >/dev/null 2>&1 || fail "docker is required to resolve the digest"
digest="$(docker buildx imagetools inspect "$image:$ref" --format '{{.Manifest.Digest}}' 2>/dev/null)" \
    || fail "could not resolve $image:$ref; is buildx available, and the package public or logged in?"
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "unexpected digest '$digest' for $image:$ref"

if [[ "$current" == "$digest" ]]; then
    log "already pinned to $image@$digest ($ref)"
    exit 0
fi

if [[ "$check" == "true" ]]; then
    log "the pin differs: compose has $current, the newest build is $digest ($ref)"
    exit 1
fi

log "pinning $image"
log "  from $current"
log "  to   $digest ($ref)"
tmp="$(mktemp "${compose}.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
sed -E "s#^([[:space:]]*image:[[:space:]]*')${image_re}@sha256:[0-9a-f]{64}'#\1${image}@${digest}'#" \
    "$compose" >"$tmp"
grep -qF "image: '${image}@${digest}'" "$tmp" || fail "the rewrite produced no matching image line; $compose is unchanged"
chmod --reference="$compose" "$tmp"
command mv -f "$tmp" "$compose"
trap - EXIT

log "wrote $compose"
log "next: docker compose pull omniroute && docker compose up -d omniroute"
log "WARN: migrations run on the first start and are one-way; run 'omniroute-backup' before recreating the container"
