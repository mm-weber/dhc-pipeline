#!/usr/bin/env bash
# Tests for scripts/refresh-grafana.sh — the postUpgradeTask for the
# tarball-repackage archetype (ADR 0002). Where refresh-definition.sh resolves a
# git tag to a commit sha, this one re-pins the two per-arch tarball checksums
# and regenerates every version-derived field. Self-contained: the dl.grafana.com
# fetch is stubbed via REFRESH_GRAFANA_SHA256_AMD64/_ARM64 so no network (and no
# 100MB download) is needed — the devcontainer firewall blocks dl.grafana.com
# anyway.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/refresh-grafana.sh"
FAILURES=0
OLD_AMD64=$(printf '1%.0s' $(seq 64))
OLD_ARM64=$(printf '2%.0s' $(seq 64))
NEW_AMD64=$(printf '3%.0s' $(seq 64))
NEW_ARM64=$(printf '4%.0s' $(seq 64))
# Build ids are opaque CI run ids in the artifact filename; not derivable from
# the version, resolved from the GitHub release assets and stubbed here.
OLD_BUILD=11111111111
NEW_BUILD=22222222222
SYNTAX="# syntax=dhi.io/build:2-alpine3.23@sha256:c95f20fcbd7f1dcff9661aa7122d811378aebd436c0927ffb73feca655d3c7bc"

# grafana-shaped definition at a given version/major.minor/major. Mirrors the
# real image/grafana/image.yaml: no git source ref, a per-arch checksum
# expression, and the version echoed into tags, spdx, purl and annotations.
grafana_def() { # ver majmin maj
  # '+' is illegal in an OCI tag, so the full tag carries the build separator
  # as '_' (the eclipse-temurin convention) while every other field keeps the
  # upstream version verbatim.
  local tagver="${1//+/_}"
  cat <<EOF
$SYNTAX

name: Grafana $2.x
image: ghcr.io/mm-weber/dhc/grafana
variant: runtime
tags:
  - $3-alpine3.23
  - $2-alpine3.23
  - $tagver-alpine3.23
platforms:
  - linux/amd64
  - linux/arm64
vars:
  # Per-arch tarball SHA-256, from the sidecar beside the per-build artifact
  # (grafana_$1_<build-id>_linux_<arch>.tar.gz.sha256), selected by target arch.
  GRAFANA_SHA256: '#{ target.arch == "amd64" ? "$OLD_AMD64" : "$OLD_ARM64" }'
  SEMVER_MAJOR_MINOR_VERSION: "$2"
  SEMVER_MAJOR_VERSION: "$3"
  SEMVER_VERSION: $1
  VERSION: $1
contents:
  builds:
    - name: grafana
      contents:
        files:
          - url: https://dl.grafana.com/grafana/release/$1/grafana_${1}_${OLD_BUILD}_linux_\${target.arch}.tar.gz
            path: \${source.dir}/grafana.tar.gz
            spdx:
              name: grafana
              version: $1
              packages:
                - name: grafana
                  purl: pkg:generic/grafana@$1
                  license: AGPL-3.0
annotations:
  GRAFANA_VERSION: $1
EOF
}

# a definition with no dl.grafana.com tarball (the cert-manager shape)
git_def() {
  cat <<EOF
$SYNTAX
image: ghcr.io/mm-weber/dhc/cert-manager-controller
vars:
  SEMVER_VERSION: 1.21.0
contents:
  builds:
    - contents:
        files:
          - url: git+https://github.com/cert-manager/cert-manager.git#v1.21.0
EOF
}

assert() { # label file 'grep-pattern'
  if grep -qF -- "$3" "$2"; then echo "ok   $1"; else
    echo "FAIL $1: expected to find '$3' in $2"; sed 's/^/    /' "$2"; FAILURES=$((FAILURES+1)); fi
}
refute() { # label file 'grep-pattern'
  if grep -qF -- "$3" "$2"; then
    echo "FAIL $1: did NOT expect '$3' in $2"; FAILURES=$((FAILURES+1)); else echo "ok   $1"; fi
}

# run the refresh on a sandbox dir after simulating a Renovate url bump to $newver
run_bump() { # old_ver new_ver
  SB=$(mktemp -d); mkdir -p "$SB/image/grafana"
  grafana_def "$1" "${1%.*}" "${1%%.*}" > "$SB/image/grafana/image.yaml"
  # Renovate rewrites only the version it captured — the path segment. The build
  # id in the filename still belongs to the old release, and every derived field
  # still holds its old value, when the postUpgradeTask runs.
  sed -i -E "s@(/grafana/release/)[^/]+/@\1${2}/@" "$SB/image/grafana/image.yaml"
  REFRESH_GRAFANA_BUILD_ID="$NEW_BUILD" \
  REFRESH_GRAFANA_SHA256_AMD64="$NEW_AMD64" REFRESH_GRAFANA_SHA256_ARM64="$NEW_ARM64" \
    "$SCRIPT" "$SB/image/grafana"
  F="$SB/image/grafana/image.yaml"
}

# 1: minor bump 13.0.4 -> 13.1.1 (the real upgrade Renovate will offer first)
run_bump 13.0.4 13.1.1
assert "minor: amd64 checksum re-pinned"   "$F" "\"amd64\" ? \"$NEW_AMD64\""
assert "minor: arm64 checksum re-pinned"   "$F" ": \"$NEW_ARM64\" }"
assert "minor: VERSION"                    "$F" "VERSION: 13.1.1"
assert "minor: SEMVER_VERSION"             "$F" "SEMVER_VERSION: 13.1.1"
assert "minor: SEMVER_MAJOR_MINOR"         "$F" 'SEMVER_MAJOR_MINOR_VERSION: "13.1"'
assert "minor: SEMVER_MAJOR"               "$F" 'SEMVER_MAJOR_VERSION: "13"'
assert "minor: full tag"                   "$F" "- 13.1.1-alpine3.23"
assert "minor: minor alias tag"            "$F" "- 13.1-alpine3.23"
assert "minor: major alias tag"            "$F" "- 13-alpine3.23"
assert "minor: display name"               "$F" "name: Grafana 13.1.x"
assert "minor: spdx version"               "$F" "version: 13.1.1"
assert "minor: purl"                       "$F" "purl: pkg:generic/grafana@13.1.1"
assert "minor: annotation"                 "$F" "GRAFANA_VERSION: 13.1.1"
assert "minor: checksum comment url"       "$F" "grafana_13.1.1_<build-id>_linux_<arch>"
assert "minor: tarball url rebuilt"        "$F" "url: https://dl.grafana.com/grafana/release/13.1.1/grafana_13.1.1_${NEW_BUILD}_linux_"
refute "minor: stale build id gone"        "$F" "$OLD_BUILD"
refute "minor: no stale 13.0.4"            "$F" "13.0.4"
refute "minor: no stale amd64 checksum"    "$F" "$OLD_AMD64"
refute "minor: no stale arm64 checksum"    "$F" "$OLD_ARM64"

# 2: patch bump 13.0.4 -> 13.0.5 (major.minor unchanged; aliases must not move)
run_bump 13.0.4 13.0.5
assert "patch: full tag"                   "$F" "- 13.0.5-alpine3.23"
assert "patch: minor alias unchanged"      "$F" "- 13.0-alpine3.23"
assert "patch: SEMVER_MAJOR_MINOR kept"    "$F" 'SEMVER_MAJOR_MINOR_VERSION: "13.0"'
assert "patch: display name kept"          "$F" "name: Grafana 13.0.x"
refute "patch: no stale 13.0.4"            "$F" "13.0.4"

# 3: major bump 13.0.4 -> 14.0.0 (dashboard-gated, but refresh must be correct)
run_bump 13.0.4 14.0.0
assert "major: SEMVER_MAJOR"               "$F" 'SEMVER_MAJOR_VERSION: "14"'
assert "major: SEMVER_MAJOR_MINOR"         "$F" 'SEMVER_MAJOR_MINOR_VERSION: "14.0"'
assert "major: major alias tag"            "$F" "- 14-alpine3.23"
assert "major: minor alias tag"            "$F" "- 14.0-alpine3.23"
assert "major: full tag"                   "$F" "- 14.0.0-alpine3.23"
assert "major: display name"               "$F" "name: Grafana 14.0.x"

# 4: out-of-band security build 13.0.4 -> 13.0.4+security-01. Upstream serves
# these from the SAME templatable /oss/release/ path (verified against
# dl.grafana.com), so the refresh is fully automatic. Two things still bite:
# '+' is an ERE metacharacter, and '+' is ILLEGAL in an OCI tag — docker rejects
# "13.0.4+security-01-alpine3.23" as an invalid reference — so the full tag
# carries the build separator as '_' while every other field keeps the version
# verbatim.
run_bump 13.0.4 13.0.4+security-01
assert "security: VERSION keeps the suffix"     "$F" "VERSION: 13.0.4+security-01"
assert "security: SEMVER_VERSION"               "$F" "SEMVER_VERSION: 13.0.4+security-01"
# Anchored on the `url:` key on purpose: the checksum-provenance comment names
# the same tarball, so an unanchored match reports success off the comment while
# the real url is wrong.
assert "security: url keeps the suffix"         "$F" "url: https://dl.grafana.com/grafana/release/13.0.4+security-01/grafana_13.0.4+security-01_${NEW_BUILD}_linux_"
refute "security: url suffix not doubled"       "$F" "security-01+security-01"
assert "security: purl keeps the suffix"        "$F" "purl: pkg:generic/grafana@13.0.4+security-01"
assert "security: full tag uses '_' separator"  "$F" "- 13.0.4_security-01-alpine3.23"
assert "security: minor alias unchanged"        "$F" "- 13.0-alpine3.23"
assert "security: major alias unchanged"        "$F" "- 13-alpine3.23"
assert "security: SEMVER_MAJOR_MINOR kept"      "$F" 'SEMVER_MAJOR_MINOR_VERSION: "13.0"'
assert "security: checksums re-pinned"          "$F" "\"amd64\" ? \"$NEW_AMD64\""
# no tag line may contain '+' — that is precisely what docker rejects
if awk '/^tags:/{t=1;next} /^[^[:space:]-]/{t=0} t&&/\+/{found=1} END{exit !found}' "$F"; then
  echo "FAIL security: a tag line contains '+' (invalid OCI reference)"; FAILURES=$((FAILURES+1))
else
  echo "ok   security: no tag line contains '+'"
fi

# 5: the regular patch that supersedes a security build (grafana's real pattern:
# v13.0.1+security-01 was followed by v13.0.2). The old version contains '+' and
# its tag carries '_', so neither is found by the same pattern — the version
# substitution and the tag rewrite have to be independent.
run_bump 13.0.4+security-01 13.0.5
assert "supersede: VERSION"               "$F" "VERSION: 13.0.5"
assert "supersede: full tag"              "$F" "- 13.0.5-alpine3.23"
assert "supersede: url"                   "$F" "url: https://dl.grafana.com/grafana/release/13.0.5/grafana_13.0.5_${NEW_BUILD}_linux_"
refute "supersede: no stale security"     "$F" "security-01"
refute "supersede: no stale '+' version"  "$F" "13.0.4+"
# no tag line may contain '+' — that is precisely what docker rejects
if awk '/^tags:/{t=1;next} /^[^[:space:]-]/{t=0} t&&/\+/{found=1} END{exit !found}' "$F"; then
  echo "FAIL supersede: a tag line contains '+' (invalid OCI reference)"; FAILURES=$((FAILURES+1))
else
  echo "ok   supersede: no tag line contains '+'"
fi

# 5b: a definition still pinned to the legacy /oss/release/ version alias is
# MIGRATED to the per-build url, not merely refreshed in place. The alias is the
# path whose contents were observed drifting from its own published checksum.
SB=$(mktemp -d); mkdir -p "$SB/image/grafana"
grafana_def 13.0.4 13.0 13 > "$SB/image/grafana/image.yaml"
F="$SB/image/grafana/image.yaml"
# shellcheck disable=SC2016  # ${target.arch} is a DHI template token, not a shell var
sed -i -E 's@url: https://dl\.grafana\.com/[^[:space:]]*@url: https://dl.grafana.com/oss/release/grafana-13.0.4.linux-${target.arch}.tar.gz@' "$F"
assert "migrate: fixture starts on the alias" "$F" "/oss/release/grafana-13.0.4.linux-"
REFRESH_GRAFANA_BUILD_ID="$NEW_BUILD" \
REFRESH_GRAFANA_SHA256_AMD64="$NEW_AMD64" REFRESH_GRAFANA_SHA256_ARM64="$NEW_ARM64" \
  "$SCRIPT" "$SB/image/grafana"
assert "migrate: now on the per-build url" "$F" "url: https://dl.grafana.com/grafana/release/13.0.4/grafana_13.0.4_${NEW_BUILD}_linux_"
refute "migrate: alias url gone"           "$F" "url: https://dl.grafana.com/oss/release/"

# 6: a definition with no dl.grafana.com tarball must fail loudly, not silently
SB=$(mktemp -d); mkdir -p "$SB/image/x"; git_def > "$SB/image/x/image.yaml"
if REFRESH_GRAFANA_SHA256_AMD64="$NEW_AMD64" REFRESH_GRAFANA_SHA256_ARM64="$NEW_ARM64" \
   "$SCRIPT" "$SB/image/x" >/dev/null 2>&1; then
  echo "FAIL guard: non-grafana definition should exit non-zero"; FAILURES=$((FAILURES+1))
else
  echo "ok   guard: non-grafana definition exits non-zero"
fi

# 5: a missing definition dir must fail loudly
if "$SCRIPT" "$(mktemp -d)/nope" >/dev/null 2>&1; then
  echo "FAIL guard: missing image.yaml should exit non-zero"; FAILURES=$((FAILURES+1))
else
  echo "ok   guard: missing image.yaml exits non-zero"
fi

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES test(s) failed"; exit 1; fi
echo "all refresh-grafana tests passed"
