#!/usr/bin/env bash
# Tests for scripts/refresh-grafana.sh — the postUpgradeTask for the
# tarball-repackage archetype (ADR 0002). Where refresh-definition.sh resolves a
# git tag to a commit sha, this one re-pins the two per-arch tarball checksums
# and regenerates every version-derived field. Self-contained: the dl.grafana.com
# fetch is stubbed via REFRESH_GRAFANA_SHA256_AMD64/_ARM64, and the two build-id
# indexes via REFRESH_GRAFANA_APT_URL / REFRESH_GRAFANA_GH_URL, so no network
# (and no 350MB download) is needed. dl.grafana.com is in fact reachable from
# the devcontainer — it is on the firewall allowlist — but a test that depends
# on upstream's index being in a particular state is a test that fails on
# upstream's schedule.
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

# ---------------------------------------------------------------------------
# Build-id resolution (measured 2026-08-07). The id is an opaque CI run id in
# the artifact filename, not derivable from the version, so it has to be looked
# up. GitHub release assets were the only source, and they are not reliable:
# v13.0.3, v12.4.5 and v12.3.8 (2026-06-23) each published with ZERO assets, as
# did v13.0.5, v13.1.2 (2026-08-04) and v13.1.3 (2026-08-07) — while
# apt.grafana.com carries a build id for v13.0.3 regardless. The reverse also
# happens: v13.0.6 had its 12 assets on GitHub hours before apt indexed it.
#
# Neither source is complete, so both are consulted and cross-checked. A
# disagreement between them is not a tie to break — two independent indexes
# naming different builds for one version is a supply-chain signal, and the
# refresh stops rather than picking one.
apt_fixture() { # dir <version:buildid>... -> writes Packages.gz, echoes its file:// url
  local dir="$1"; shift
  : > "$dir/Packages"
  local pair ver id
  for pair in "$@"; do
    ver="${pair%%:*}"; id="${pair##*:}"
    # Real index shape: apt mangles '+security-NN' to '-NN' in Version:, so the
    # filename is the only field carrying the upstream version verbatim — which
    # is why resolution reads Filename: and never Version:.
    printf 'Package: grafana\nVersion: %s\nFilename: pool/main/g/grafana/grafana_%s_%s_linux_amd64.deb\n\n' \
      "${ver//+security-/-}" "$ver" "$id" >> "$dir/Packages"
    # grafana-enterprise ships the same version and build id from a sibling
    # pool dir. It must never be the match: it is a different artifact.
    printf 'Package: grafana-enterprise\nVersion: %s\nFilename: pool/main/g/grafana-enterprise/grafana-enterprise_%s_%s_linux_amd64.deb\n\n' \
      "${ver//+security-/-}" "$ver" "$id" >> "$dir/Packages"
  done
  gzip -kf "$dir/Packages"
  echo "file://$dir/Packages.gz"
}

gh_fixture() { # dir version buildid|"" -> writes releases/tags/v<ver>, echoes base file:// url
  local dir="$1" ver="$2" id="${3:-}"
  mkdir -p "$dir/tags"
  if [ -n "$id" ]; then
    printf '{"assets":[{"name":"grafana-enterprise_%s_%s_linux_amd64.deb"},{"name":"grafana_%s_%s_linux_amd64.deb"}]}\n' \
      "$ver" "$id" "$ver" "$id" > "$dir/tags/v${ver}"
  else
    printf '{"assets":[]}\n' > "$dir/tags/v${ver}"   # the real asset-less release shape
  fi
  echo "file://$dir/tags"
}

# resolve a bump with both sources stubbed; no REFRESH_GRAFANA_BUILD_ID, so the
# resolution path under test actually runs. Echoes nothing; sets F and RC.
run_resolve() { # old_ver new_ver apt_url gh_url
  SB=$(mktemp -d); mkdir -p "$SB/image/grafana"
  grafana_def "$1" "${1%.*}" "${1%%.*}" > "$SB/image/grafana/image.yaml"
  sed -i -E "s@(/grafana/release/)[^/]+/@\1${2}/@" "$SB/image/grafana/image.yaml"
  RESOLVE_ERR="$SB/err.txt"
  REFRESH_GRAFANA_APT_URL="$3" REFRESH_GRAFANA_GH_URL="$4" \
  REFRESH_GRAFANA_SHA256_AMD64="$NEW_AMD64" REFRESH_GRAFANA_SHA256_ARM64="$NEW_ARM64" \
    "$SCRIPT" "$SB/image/grafana" >/dev/null 2>"$RESOLVE_ERR"
  RC=$?
  F="$SB/image/grafana/image.yaml"
}

FX=$(mktemp -d)

# 7: apt resolves what GitHub cannot — the v13.0.3 / v13.1.2 shape, a real
# release whose GitHub entry carries no assets at all.
D=$(mktemp -d); APT=$(apt_fixture "$D" 13.1.2:30777000111)
GH=$(gh_fixture "$FX/gh-empty" 13.1.2 "")
run_resolve 13.1.1 13.1.2 "$APT" "$GH"
assert "resolve: apt covers an asset-less GitHub release" "$F" \
  "url: https://dl.grafana.com/grafana/release/13.1.2/grafana_13.1.2_30777000111_linux_"

# 8: GitHub resolves what apt has not indexed yet — the v13.0.6 shape, assets
# published hours before the apt index caught up.
D=$(mktemp -d); APT=$(apt_fixture "$D" 13.1.1:29761037902)
GH=$(gh_fixture "$FX/gh-new" 13.0.6 30999888777)
run_resolve 13.0.5 13.0.6 "$APT" "$GH"
assert "resolve: github covers a version apt has not indexed" "$F" \
  "url: https://dl.grafana.com/grafana/release/13.0.6/grafana_13.0.6_30999888777_linux_"

# 9: neither source has it — refuse. This is v13.1.2's real state on 2026-08-07,
# three days after release: no GitHub assets, absent from apt. Fabricating or
# falling back to the rewritten /oss/release/ alias would both be worse.
D=$(mktemp -d); APT=$(apt_fixture "$D" 13.1.1:29761037902)
GH=$(gh_fixture "$FX/gh-none" 13.1.2 "")
run_resolve 13.1.1 13.1.2 "$APT" "$GH"
if [ "$RC" -eq 0 ]; then
  echo "FAIL resolve: unresolvable build id should exit non-zero"; FAILURES=$((FAILURES+1))
else
  echo "ok   resolve: unresolvable build id exits non-zero"
fi
assert "resolve: the failure names both sources" "$RESOLVE_ERR" "apt.grafana.com"

# 10: both sources agree — the ordinary case, and the cross-check must pass it.
D=$(mktemp -d); APT=$(apt_fixture "$D" 13.1.1:29761037902)
GH=$(gh_fixture "$FX/gh-agree" 13.1.1 29761037902)
run_resolve 13.0.4 13.1.1 "$APT" "$GH"
assert "resolve: agreeing sources resolve" "$F" \
  "url: https://dl.grafana.com/grafana/release/13.1.1/grafana_13.1.1_29761037902_linux_"

# 11: sources disagree — refuse rather than prefer one. Two independent indexes
# naming different builds for one version means one of them is wrong, and a
# checksum pinned against the wrong build verifies against nothing.
D=$(mktemp -d); APT=$(apt_fixture "$D" 13.1.1:29761037902)
GH=$(gh_fixture "$FX/gh-conflict" 13.1.1 39999999999)
run_resolve 13.0.4 13.1.1 "$APT" "$GH"
if [ "$RC" -eq 0 ]; then
  echo "FAIL resolve: disagreeing sources should exit non-zero"; FAILURES=$((FAILURES+1))
else
  echo "ok   resolve: disagreeing sources exit non-zero"
fi

# 12: grafana-enterprise must never satisfy the lookup. Its stanza carries the
# same version and build id from a sibling pool dir, so an unanchored match on
# the version alone finds it — and it is a different artifact.
D=$(mktemp -d)
: > "$D/Packages"
printf 'Package: grafana-enterprise\nVersion: 13.1.4\nFilename: pool/main/g/grafana-enterprise/grafana-enterprise_13.1.4_31000000000_linux_amd64.deb\n\n' >> "$D/Packages"
gzip -kf "$D/Packages"
GH=$(gh_fixture "$FX/gh-ent" 13.1.4 "")
run_resolve 13.1.1 13.1.4 "file://$D/Packages.gz" "$GH"
if [ "$RC" -eq 0 ]; then
  echo "FAIL resolve: enterprise-only index should not satisfy the lookup"; FAILURES=$((FAILURES+1))
else
  echo "ok   resolve: enterprise-only index does not satisfy the lookup"
fi

# 13: out-of-band security build. '+' is an ERE metacharacter, and apt's
# Version: field mangles 13.0.1+security-01 to 13.0.1-01 — so the lookup has to
# read Filename:, which keeps the upstream version verbatim.
D=$(mktemp -d); APT=$(apt_fixture "$D" 13.0.4+security-01:31222333444)
GH=$(gh_fixture "$FX/gh-sec" 13.0.4+security-01 "")
run_resolve 13.0.4 13.0.4+security-01 "$APT" "$GH"
assert "resolve: security build resolves from the filename" "$F" \
  "url: https://dl.grafana.com/grafana/release/13.0.4+security-01/grafana_13.0.4+security-01_31222333444_linux_"

# ---------------------------------------------------------------------------
# dl.grafana.com is the authority on what is actually fetchable. An index can
# name a build the object store does not serve — the two are populated by
# different pipelines, and apt/GitHub are both indexes. So the resolved
# per-build tarball is confirmed to exist before anything is written to the
# definition, and a miss is reported against dl.grafana.com by name instead of
# surfacing later as a 350MB download that 404s into a checksum complaint.
dl_fixture() { # dir <arch>... -> lays out a per-build tree, echoes its file:// base
  local dir="$1"; shift
  local d="$dir/grafana/release/${DLVER}"
  mkdir -p "$d"
  local arch c
  for arch in "$@"; do
    # amd64 and arm64 share a first letter, so the two sidecars have to be told
    # apart deliberately — otherwise a per-arch mix-up passes both assertions.
    [ "$arch" = amd64 ] && c=1 || c=2
    echo "tarball-bytes-${arch}" > "$d/grafana_${DLVER}_${DLBUILD}_linux_${arch}.tar.gz"
    printf '%s  grafana_%s_%s_linux_%s.tar.gz\n' "$(printf "${c}%.0s" $(seq 64))" \
      "$DLVER" "$DLBUILD" "$arch" > "$d/grafana_${DLVER}_${DLBUILD}_linux_${arch}.tar.gz.sha256"
  done
  echo "file://$dir"
}

# a bump with the build id known and dl.grafana.com stubbed, but the checksums
# NOT stubbed — so fetch_sha and the existence check actually run.
run_dl() { # old_ver new_ver dl_base
  SB=$(mktemp -d); mkdir -p "$SB/image/grafana"
  grafana_def "$1" "${1%.*}" "${1%%.*}" > "$SB/image/grafana/image.yaml"
  sed -i -E "s@(/grafana/release/)[^/]+/@\1${2}/@" "$SB/image/grafana/image.yaml"
  RESOLVE_ERR="$SB/err.txt"
  REFRESH_GRAFANA_BUILD_ID="$DLBUILD" REFRESH_GRAFANA_DL_BASE="$3" \
    "$SCRIPT" "$SB/image/grafana" >/dev/null 2>"$RESOLVE_ERR"
  RC=$?
  F="$SB/image/grafana/image.yaml"
}

DLVER=13.1.5; DLBUILD=31500000000

# 14: the artifact is there — both sidecars are read and pinned per arch.
D=$(mktemp -d); DL=$(dl_fixture "$D" amd64 arm64)
run_dl 13.1.1 "$DLVER" "$DL"
assert "dl: amd64 sidecar pinned" "$F" "\"amd64\" ? \"$(printf '1%.0s' $(seq 64))\""
assert "dl: arm64 sidecar pinned" "$F" ": \"$(printf '2%.0s' $(seq 64))\" }"

# 15: the index named a build dl.grafana.com does not serve. Fail fast, name the
# host, and leave the definition untouched — a half-written pin is worse than
# no bump.
D=$(mktemp -d); DL=$(dl_fixture "$D" amd64)   # arm64 deliberately absent
run_dl 13.1.1 "$DLVER" "$DL"
if [ "$RC" -eq 0 ]; then
  echo "FAIL dl: a missing per-arch artifact should exit non-zero"; FAILURES=$((FAILURES+1))
else
  echo "ok   dl: a missing per-arch artifact exits non-zero"
fi
assert "dl: the failure names dl.grafana.com" "$RESOLVE_ERR" "dl.grafana.com"
refute "dl: definition not half-written"      "$F" "$DLBUILD"

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
