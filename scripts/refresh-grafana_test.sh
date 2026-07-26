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
SYNTAX="# syntax=dhi.io/build:2-alpine3.23@sha256:c95f20fcbd7f1dcff9661aa7122d811378aebd436c0927ffb73feca655d3c7bc"

# grafana-shaped definition at a given version/major.minor/major. Mirrors the
# real image/grafana/image.yaml: no git source ref, a per-arch checksum
# expression, and the version echoed into tags, spdx, purl and annotations.
grafana_def() { # ver majmin maj
  cat <<EOF
$SYNTAX

name: Grafana $2.x
image: ghcr.io/mm-weber/dhc/grafana
variant: runtime
tags:
  - $3-alpine3.23
  - $2-alpine3.23
  - $1-alpine3.23
platforms:
  - linux/amd64
  - linux/arm64
vars:
  # Per-arch tarball SHA-256 (from https://dl.grafana.com/oss/release/
  # grafana-$1.linux-<arch>.tar.gz.sha256), selected by target arch.
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
          - url: https://dl.grafana.com/oss/release/grafana-$1.linux-\${target.arch}.tar.gz
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
  # Renovate rewrites only the version inside the tarball url; every derived
  # field still holds its old value when the postUpgradeTask runs.
  sed -i -E "s@(url: https://dl\.grafana\.com/oss/release/grafana-)[0-9][^/]*(\.linux-)@\1${2}\2@" \
    "$SB/image/grafana/image.yaml"
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
assert "minor: checksum comment url"       "$F" "grafana-13.1.1.linux-<arch>"
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

# 4: a definition with no dl.grafana.com tarball must fail loudly, not silently
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
