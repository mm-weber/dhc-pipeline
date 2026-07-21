#!/usr/bin/env bash
# Tests for scripts/refresh-definition.sh — the postUpgradeTask that, after
# Renovate bumps a definition's source ref, recomputes the checksum and
# regenerates every version-derived field so the bumped definition is coherent
# (Req 3.2). Self-contained: SHA resolution is stubbed via REFRESH_SHA_OVERRIDE
# so no network is needed.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/refresh-definition.sh"
FAILURES=0
OLD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
NEW_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
SYNTAX="# syntax=dhi.io/build:2-alpine3.23@sha256:c95f20fcbd7f1dcff9661aa7122d811378aebd436c0927ffb73feca655d3c7bc"

# cert-manager-shaped definition at a given version/major.minor/major.
cert_def() { # ver majmin maj  -> stdout
  cat <<EOF
$SYNTAX
image: ghcr.io/mm-weber/dhc/cert-manager-controller
tags:
  - $3-alpine3.23
  - $2-alpine3.23
  - $1-alpine3.23
vars:
  COMMIT_SHA: $OLD_SHA
  SEMVER_MAJOR_MINOR_VERSION: "$2"
  SEMVER_MAJOR_VERSION: "$3"
  SEMVER_VERSION: $1
  VERSION: $1
contents:
  builds:
    - name: cert-manager-controller
      contents:
        files:
          - url: git+https://github.com/cert-manager/cert-manager.git#v$1
            checksum: $OLD_SHA
      pipeline:
        - name: build
          uses: go/build@v1
          with:
            ldflags:
              - -w
              - -s
              - -X github.com/cert-manager/cert-manager/pkg/util.AppVersion=v$1
              - -X github.com/cert-manager/cert-manager/pkg/util.AppGitCommit=$OLD_SHA
EOF
}

# hardened-app-shaped definition (ldflags version has NO 'v' prefix).
hardened_def() { # ver majmin maj
  cat <<EOF
$SYNTAX
image: ghcr.io/mm-weber/dhc/hardened-app
tags:
  - $3-alpine3.23
  - $2-alpine3.23
  - $1-alpine3.23
vars:
  COMMIT_SHA: $OLD_SHA
  SEMVER_MAJOR_MINOR_VERSION: "$2"
  SEMVER_MAJOR_VERSION: "$3"
  SEMVER_VERSION: $1
  VERSION: $1
contents:
  builds:
    - name: hardened-app
      contents:
        files:
          - url: git+https://github.com/mm-weber/hardened-app.git#v$1
            checksum: $OLD_SHA
      pipeline:
        - name: build
          uses: go/build@v1
          with:
            ldflags:
              - -w
              - -s
              - -X main.version=$1
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

# run the refresh on a sandbox dir after simulating a Renovate ref bump to $newtag
run_bump() { # deffn old_ver newtag
  SB=$(mktemp -d); mkdir -p "$SB/image/x"
  "$1" "$2" "${2%.*}" "${2%%.*}" > "$SB/image/x/image.yaml"
  # Renovate changes only the url ref; every derived field still holds its old
  # value at the moment the postUpgradeTask runs. Swap just the #<ref> fragment.
  sed -i -E "s@(url: git\\+https://github.com/[^#]+#).*@\\1${newtag}@" "$SB/image/x/image.yaml"
  REFRESH_SHA_OVERRIDE="$NEW_SHA" "$SCRIPT" "$SB/image/x"
  F="$SB/image/x/image.yaml"
}

# 1: cert-manager minor bump 1.20.3 -> 1.21.0
newtag="v1.21.0"; run_bump cert_def 1.20.3 "$newtag"
assert "cert minor: checksum recomputed"      "$F" "checksum: $NEW_SHA"
assert "cert minor: COMMIT_SHA recomputed"    "$F" "COMMIT_SHA: $NEW_SHA"
assert "cert minor: AppGitCommit recomputed"  "$F" "AppGitCommit=$NEW_SHA"
assert "cert minor: VERSION"                  "$F" "VERSION: 1.21.0"
assert "cert minor: SEMVER_VERSION"           "$F" "SEMVER_VERSION: 1.21.0"
assert "cert minor: SEMVER_MAJOR_MINOR"       "$F" 'SEMVER_MAJOR_MINOR_VERSION: "1.21"'
assert "cert minor: SEMVER_MAJOR"             "$F" 'SEMVER_MAJOR_VERSION: "1"'
assert "cert minor: full tag"                 "$F" "- 1.21.0-alpine3.23"
assert "cert minor: minor alias tag"          "$F" "- 1.21-alpine3.23"
assert "cert minor: major alias tag"          "$F" "- 1-alpine3.23"
assert "cert minor: ldflags AppVersion (v)"   "$F" "AppVersion=v1.21.0"
refute "cert minor: no stale 1.20.3"          "$F" "1.20.3"
refute "cert minor: no stale old sha"         "$F" "$OLD_SHA"

# 2: cert-manager patch bump 1.20.3 -> 1.20.4 (major.minor unchanged)
newtag="v1.20.4"; run_bump cert_def 1.20.3 "$newtag"
assert "cert patch: full tag"                 "$F" "- 1.20.4-alpine3.23"
assert "cert patch: minor alias unchanged"    "$F" "- 1.20-alpine3.23"
assert "cert patch: SEMVER_MAJOR_MINOR kept"  "$F" 'SEMVER_MAJOR_MINOR_VERSION: "1.20"'

# 3: hardened-app minor bump 0.1.0 -> 0.2.0 (ldflags version has no 'v')
newtag="v0.2.0"; run_bump hardened_def 0.1.0 "$newtag"
assert "hardened: VERSION"                     "$F" "VERSION: 0.2.0"
assert "hardened: SEMVER_MAJOR_MINOR"          "$F" 'SEMVER_MAJOR_MINOR_VERSION: "0.2"'
assert "hardened: minor alias tag"             "$F" "- 0.2-alpine3.23"
assert "hardened: ldflags main.version (no v)" "$F" "main.version=0.2.0"
refute "hardened: no stray v0.2.0 in ldflags"  "$F" "main.version=v0.2.0"

# 4: cert-manager major bump 1.20.3 -> 2.0.0 (dashboard-gated, but refresh must still be correct)
newtag="v2.0.0"; run_bump cert_def 1.20.3 "$newtag"
assert "cert major: SEMVER_MAJOR"             "$F" 'SEMVER_MAJOR_VERSION: "2"'
assert "cert major: SEMVER_MAJOR_MINOR"       "$F" 'SEMVER_MAJOR_MINOR_VERSION: "2.0"'
assert "cert major: major alias tag"          "$F" "- 2-alpine3.23"
assert "cert major: full tag"                 "$F" "- 2.0.0-alpine3.23"

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES test(s) failed"; exit 1; fi
echo "all refresh-definition tests passed"
