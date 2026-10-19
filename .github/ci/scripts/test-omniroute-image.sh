#!/bin/bash
set -euo pipefail

# Tests the OmniRoute image pin updater without GitHub, the registry or Docker: `gh` and
# `docker` are stubs that return a fixed run and digest, and the Compose file is a fixture in
# a temp directory. The cases that matter are the first switch away from the official image,
# an unchanged pin, --check in both directions, --tag bypassing GitHub, an unquoted pin, a
# mirror repository, and every failure leaving the file untouched.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-omniroute-image] testing the OmniRoute image pin updater..." >&2

pass() { echo "[test-omniroute-image] PASS: $1" >&2; }
fail() { echo "[test-omniroute-image] FAIL: $1" >&2; EXIT_CODE=1; }

SCRIPT="$REPO_ROOT/local-services/omniroute/update-image.sh"
COMPOSE="$TMP/compose.yaml"
DIGEST_OFFICIAL="sha256:$(printf 'c%.0s' {1..64})"
DIGEST_A="sha256:$(printf 'a%.0s' {1..64})"
DIGEST_B="sha256:$(printf 'b%.0s' {1..64})"
SHA_A="$(printf '1%.0s' {1..40})"

# Lay the fixture out exactly as the repository's Compose file does: the official image in the
# omniroute service, an unrelated image beside it, and a comment that must survive.
cat > "$COMPOSE" <<YAML
name: 'dotfiles'

services:
  redis:
    image: 'docker.io/library/redis:8.6.5-alpine'
  omniroute:
    # Known-good release image digest.
    image: 'ghcr.io/diegosouzapw/omniroute@${DIGEST_OFFICIAL}'
    platform: 'linux/amd64'
YAML
chmod 0644 "$COMPOSE"

mkdir -p "$TMP/stub"
cat > "$TMP/stub/gh" <<'STUB_GH'
#!/bin/bash
set -euo pipefail
case "$*" in
    *"repos/rios0rios0/OmniRoute/actions/workflows/publish-ghcr.yml/runs"*)
        if [[ "${FAKE_GH_FAIL:-}" == "true" ]]; then
            exit 1
        fi
        if [[ "${FAKE_GH_EMPTY:-}" == "true" ]]; then
            sha=""
        else
            sha="${FAKE_GH_SHA:-0123456789012345678901234567890123456789}"
        fi
        printf '%s\t%s\t%s\n' "$sha" "2026-10-19T12:00:00Z" "https://example.invalid/run/1"
        ;;
    *)
        echo "stub gh: unhandled: $*" >&2
        exit 2
        ;;
esac
STUB_GH

cat > "$TMP/stub/docker" <<'STUB_DOCKER'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "${FAKE_DOCKER_LOG:?}"
if [[ "${FAKE_DOCKER_FAIL:-}" == "true" ]]; then
    exit 1
fi
case "$*" in
    *"buildx imagetools inspect "*"--format"*)
        printf '%s\n' "${FAKE_DIGEST:?}"
        ;;
    *)
        echo "stub docker: unhandled: $*" >&2
        exit 2
        ;;
esac
STUB_DOCKER
chmod +x "$TMP/stub/gh" "$TMP/stub/docker"

export PATH="$TMP/stub:$PATH"
export FAKE_DOCKER_LOG="$TMP/docker.log"
export OMNIROUTE_COMPOSE="$COMPOSE"
touch "$FAKE_DOCKER_LOG"

image_line_of() { grep -E '^[[:space:]]*image:' "$1"; }
image_line() { image_line_of "$COMPOSE"; }
checksum() { cksum "$COMPOSE"; }

if [[ -x "$SCRIPT" ]]; then
    pass "the updater is executable"
else
    fail "the updater is not executable"
fi

if "$SCRIPT" --help >/dev/null 2>&1; then
    pass "--help exits 0"
else
    fail "--help does not exit 0"
fi
if "$SCRIPT" --bogus >/dev/null 2>&1; then
    fail "an unknown argument exits 0"
else
    pass "an unknown argument exits non-zero"
fi

if OMNIROUTE_COMPOSE="$TMP/missing.yaml" "$SCRIPT" >/dev/null 2>&1; then
    fail "a missing Compose file exits 0"
else
    pass "a missing Compose file exits non-zero"
fi

# The first run moves the pin from the official image to the fork's build.
if FAKE_DIGEST="$DIGEST_A" FAKE_GH_SHA="$SHA_A" "$SCRIPT" 2>"$TMP/first.log"; then
    pass "the first pin update succeeds"
else
    fail "the first pin update failed: $(cat "$TMP/first.log")"
fi
if image_line | grep -qF "image: 'ghcr.io/rios0rios0/omniroute@${DIGEST_A}'"; then
    pass "the omniroute image points at the fork digest"
else
    fail "the omniroute image was not rewritten: $(image_line)"
fi
if image_line | grep -qF 'docker.io/library/redis:8.6.5-alpine'; then
    pass "the unrelated image is untouched"
else
    fail "the redis image changed: $(image_line)"
fi
if grep -q '# Known-good release image digest.' "$COMPOSE"; then
    pass "the comment survives the rewrite"
else
    fail "the comment was dropped"
fi
if [[ "$(stat -c %a "$COMPOSE")" == "644" ]]; then
    pass "the Compose file keeps its mode"
else
    fail "the Compose file mode changed to $(stat -c %a "$COMPOSE")"
fi
if grep -q ':sha-'"$SHA_A" "$FAKE_DOCKER_LOG"; then
    pass "the digest is resolved through the immutable sha-<commit> tag"
else
    fail "the updater did not use the sha-<commit> tag: $(cat "$FAKE_DOCKER_LOG")"
fi
if grep -q ':feat-model-quota-api' "$FAKE_DOCKER_LOG"; then
    fail "the mutable branch tag was resolved"
else
    pass "the mutable branch tag is never pinned"
fi

# An unchanged pin is a no-op, not a rewrite.
before="$(checksum)"
if FAKE_DIGEST="$DIGEST_A" FAKE_GH_SHA="$SHA_A" "$SCRIPT" 2>"$TMP/second.log"; then
    pass "a repeated update succeeds"
else
    fail "a repeated update failed"
fi
if grep -q 'already pinned' "$TMP/second.log"; then
    pass "a repeated update reports the pin is current"
else
    fail "a repeated update does not say the pin is current"
fi
if [[ "$(checksum)" == "$before" ]]; then
    pass "a repeated update leaves the file byte-identical"
else
    fail "a repeated update rewrote the file"
fi

# --check: 0 when the file holds the newest digest, 1 when it does not.
if FAKE_DIGEST="$DIGEST_A" FAKE_GH_SHA="$SHA_A" "$SCRIPT" --check >/dev/null 2>&1; then
    pass "--check exits 0 for a current pin"
else
    fail "--check fails for a current pin"
fi
if FAKE_DIGEST="$DIGEST_B" FAKE_GH_SHA="$SHA_A" "$SCRIPT" --check >/dev/null 2>&1; then
    fail "--check exits 0 for a stale pin"
else
    pass "--check exits non-zero for a stale pin"
fi
if [[ "$(checksum)" == "$before" ]]; then
    pass "--check never rewrites the file"
else
    fail "--check rewrote the file"
fi

# --tag bypasses GitHub entirely, which is what a release tag needs.
rm -f "$FAKE_DOCKER_LOG"
if FAKE_GH_FAIL=true FAKE_DIGEST="$DIGEST_B" "$SCRIPT" --tag v9.9.9 2>"$TMP/tag.log"; then
    pass "--tag succeeds without a GitHub lookup"
else
    fail "--tag failed: $(cat "$TMP/tag.log")"
fi
if image_line | grep -qF "ghcr.io/rios0rios0/omniroute@${DIGEST_B}"; then
    pass "--tag pins the digest of that tag"
else
    fail "--tag did not rewrite the image: $(image_line)"
fi
if grep -q ':v9.9.9' "$FAKE_DOCKER_LOG"; then
    pass "--tag resolves the named tag"
else
    fail "--tag did not resolve the named tag: $(cat "$FAKE_DOCKER_LOG")"
fi

# An unquoted pin is a valid Compose reference, and the writer must accept whatever the reader
# does: a rewrite that only recognizes the quoted form fails on a real Compose file.
cat > "$TMP/unquoted.yaml" <<YAML
services:
  omniroute:
    image: ghcr.io/diegosouzapw/omniroute@${DIGEST_OFFICIAL}
YAML
if OMNIROUTE_COMPOSE="$TMP/unquoted.yaml" FAKE_DIGEST="$DIGEST_A" FAKE_GH_SHA="$SHA_A" "$SCRIPT" 2>"$TMP/unquoted.log"; then
    pass "an unquoted pin is updated"
else
    fail "an unquoted pin could not be updated: $(cat "$TMP/unquoted.log")"
fi
if grep -qE "^[[:space:]]*image: ghcr\.io/rios0rios0/omniroute@${DIGEST_A}[[:space:]]*$" "$TMP/unquoted.yaml"; then
    pass "the rewrite keeps the pin unquoted"
else
    fail "the unquoted pin was not rewritten: $(image_line_of "$TMP/unquoted.yaml")"
fi

# A pin written by an earlier run against another repository stays readable: OMNIROUTE_IMAGE
# may name a mirror, and the file that run wrote must not become unreadable input to the next.
MIRROR="ghcr.io/mirror-org/omniroute"
cat > "$TMP/mirror.yaml" <<YAML
services:
  omniroute:
    image: '${MIRROR}@${DIGEST_A}'
YAML
if OMNIROUTE_COMPOSE="$TMP/mirror.yaml" OMNIROUTE_IMAGE="$MIRROR" FAKE_DIGEST="$DIGEST_B" FAKE_GH_SHA="$SHA_A" "$SCRIPT" 2>"$TMP/mirror.log"; then
    pass "a mirror pin is updated"
else
    fail "a mirror pin could not be updated: $(cat "$TMP/mirror.log")"
fi
if grep -qF "image: '${MIRROR}@${DIGEST_B}'" "$TMP/mirror.yaml"; then
    pass "the mirror pin holds the new digest"
else
    fail "the mirror pin was not rewritten: $(image_line_of "$TMP/mirror.yaml")"
fi
if OMNIROUTE_COMPOSE="$TMP/mirror.yaml" OMNIROUTE_IMAGE="$MIRROR" FAKE_DIGEST="$DIGEST_B" FAKE_GH_SHA="$SHA_A" "$SCRIPT" --check >/dev/null 2>&1; then
    pass "--check accepts the mirror pin it just wrote"
else
    fail "--check rejects the mirror pin it just wrote"
fi

# The repository is part of the pin: an equal digest built into another repository is still a
# different image, so it must be neither reported current nor left in place.
cat > "$TMP/repository.yaml" <<YAML
services:
  omniroute:
    image: 'ghcr.io/rios0rios0/omniroute@${DIGEST_A}'
YAML
if OMNIROUTE_COMPOSE="$TMP/repository.yaml" OMNIROUTE_IMAGE="$MIRROR" FAKE_DIGEST="$DIGEST_A" FAKE_GH_SHA="$SHA_A" "$SCRIPT" --check >/dev/null 2>&1; then
    fail "--check exits 0 when only the repository differs"
else
    pass "--check reports a differing repository with an equal digest"
fi
if OMNIROUTE_COMPOSE="$TMP/repository.yaml" OMNIROUTE_IMAGE="$MIRROR" FAKE_DIGEST="$DIGEST_A" FAKE_GH_SHA="$SHA_A" "$SCRIPT" 2>"$TMP/repository.log"; then
    if grep -qF "image: '${MIRROR}@${DIGEST_A}'" "$TMP/repository.yaml"; then
        pass "an equal digest in another repository is rewritten"
    else
        fail "the repository was not rewritten: $(image_line_of "$TMP/repository.yaml")"
    fi
else
    fail "the repository switch failed: $(cat "$TMP/repository.log")"
fi

# The value reaches a sed program, so a character it cannot express is refused up front rather
# than producing a rewrite that matches nothing.
if OMNIROUTE_IMAGE='ghcr.io/example/omni#route' OMNIROUTE_COMPOSE="$TMP/mirror.yaml" "$SCRIPT" >/dev/null 2>&1; then
    fail "an image repository with sed metacharacters exits 0"
else
    pass "an image repository with sed metacharacters is refused"
fi

# Failures leave the pin where it was.
before="$(checksum)"
if FAKE_GH_EMPTY=true FAKE_DIGEST="$DIGEST_B" "$SCRIPT" >/dev/null 2>&1; then
    fail "a missing successful run exits 0"
else
    pass "a missing successful run exits non-zero"
fi
if FAKE_DOCKER_FAIL=true FAKE_GH_SHA="$SHA_A" "$SCRIPT" >/dev/null 2>&1; then
    fail "an unresolvable digest exits 0"
else
    pass "an unresolvable digest exits non-zero"
fi
if [[ "$(checksum)" == "$before" ]]; then
    pass "failed lookups leave the pin untouched"
else
    fail "a failed lookup rewrote the pin"
fi

# A file with no recognised OmniRoute image is refused rather than half-rewritten.
cat > "$TMP/other.yaml" <<'YAML'
services:
  omniroute:
    image: 'ghcr.io/example/omniroute:latest'
YAML
if OMNIROUTE_COMPOSE="$TMP/other.yaml" FAKE_DIGEST="$DIGEST_A" "$SCRIPT" >/dev/null 2>&1; then
    fail "a file without a digest pin exits 0"
else
    pass "a file without a digest pin exits non-zero"
fi

if (( EXIT_CODE == 0 )); then
    echo "[test-omniroute-image] all checks passed" >&2
fi
exit "$EXIT_CODE"
