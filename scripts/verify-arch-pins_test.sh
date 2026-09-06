#!/usr/bin/env bash
# Tests for scripts/verify-arch-pins.sh — self-contained sandbox, no network.
#
# The artifacts are served over file:// URLs so the real curl path is exercised
# end to end: the point of this script is that it FETCHES, and a stubbed fetch
# would test nothing.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
VERIFY="$HERE/verify-arch-pins.sh"
FAILURES=0

run_case() { # name, expected_exit, expect_substring(optional) — definition in $SB
  local name="$1" expected="$2" substr="${3:-}"
  local out rc
  out=$("$VERIFY" "$SB" 2>&1); rc=$?
  if [ "$rc" -ne "$expected" ]; then
    echo "FAIL $name: exit $rc, expected $expected"; echo "$out" | sed 's/^/    /'
    FAILURES=$((FAILURES+1)); return
  fi
  if [ -n "$substr" ] && ! grep -qF "$substr" <<<"$out"; then
    echo "FAIL $name: output missing '$substr'"; echo "$out" | sed 's/^/    /'
    FAILURES=$((FAILURES+1)); return
  fi
  echo "ok   $name"
}

refute_case() { # name, expected_exit, forbidden_substring
  local name="$1" expected="$2" substr="$3"
  local out rc
  out=$("$VERIFY" "$SB" 2>&1); rc=$?
  if [ "$rc" -ne "$expected" ]; then
    echo "FAIL $name: exit $rc, expected $expected"; echo "$out" | sed 's/^/    /'
    FAILURES=$((FAILURES+1)); return
  fi
  if grep -qF "$substr" <<<"$out"; then
    echo "FAIL $name: output should not contain '$substr'"; echo "$out" | sed 's/^/    /'
    FAILURES=$((FAILURES+1)); return
  fi
  echo "ok   $name"
}

# Sandbox holds both the definition and the "upstream" artifacts it points at.
fresh() {
  SB=$(mktemp -d)
  mkdir -p "$SB/dist" "$SB/api"
  printf 'amd64 payload\n' > "$SB/dist/app_amd64.tar.gz"
  printf 'arm64 payload — deliberately different bytes\n' > "$SB/dist/app_arm64.tar.gz"
  SHA_AMD=$(sha256sum "$SB/dist/app_amd64.tar.gz" | cut -d' ' -f1)
  SHA_ARM=$(sha256sum "$SB/dist/app_arm64.tar.gz" | cut -d' ' -f1)
  # The publisher's version statement (Req 3.9, task 11.3): the third value,
  # served from a file:// tree for the version the fixture declares.
  statement "$SHA_AMD" "$SHA_ARM"
  export DHC_VERSIONS_API="file://$SB/api"
}
statement() { # amd64_sha arm64_sha [version]
  printf '{"version":"%s","packages":[{"os":"linux","arch":"amd64","url":"https://dl.example.com/app_1.0.0_linux_amd64.tar.gz","sha256":"%s"},{"os":"linux","arch":"arm64","url":"https://dl.example.com/app_1.0.0_linux_arm64.tar.gz","sha256":"%s"}]}\n' \
    "${3:-1.0.0}" "$1" "$2" > "$SB/api/${3:-1.0.0}"
}

# Writes image.yaml with the catalog's per-arch idiom: one url carrying
# ${target.arch}, one var carrying a #{ } ternary over the two checksums.
write_def() { # amd64_sha, arm64_sha, [url_override]
  # NB: the default url is assigned in its own statement. Written as
  # ${3:-…app_\${target.arch}.tar.gz}, bash takes the inner '}' as the closing
  # brace of the outer expansion and yields app_${target.arch.tar.gz}.
  local amd="$1" arm="$2" url="${3:-}"
  [ -n "$url" ] || url="file://$SB/dist/app_\${target.arch}.tar.gz"
  cat > "$SB/image.yaml" <<EOF
name: App
image: ghcr.io/mm-weber/dhc/app
vars:
  APP_SHA256: '#{ target.arch == "amd64" ? "$amd" : "$arm" }'
  VERSION: 1.0.0
contents:
  builds:
    - name: app
      contents:
        files:
          - url: $url
            path: \${source.dir}/app.tar.gz
EOF
}

BOGUS=0000000000000000000000000000000000000000000000000000000000000000

# 1: both arches match their pins
fresh; write_def "$SHA_AMD" "$SHA_ARM"
run_case "matching pins pass" 0
run_case "names amd64" 0 "amd64"
run_case "names arm64" 0 "arm64"

# 2: arm64 pin wrong — THE case that motivated this script. amd64 is fine, so a
# gate that only builds amd64 sees nothing wrong.
fresh; write_def "$SHA_AMD" "$BOGUS"
run_case "wrong arm64 pin fails" 1
run_case "failure names arm64" 1 "arm64"
run_case "failure shows the pinned value" 1 "$BOGUS"
run_case "failure shows what upstream actually served" 1 "$SHA_ARM"
refute_case "a good amd64 is not blamed" 1 "amd64 MISMATCH"

# 3: amd64 pin wrong
fresh; write_def "$BOGUS" "$SHA_ARM"
run_case "wrong amd64 pin fails" 1
run_case "failure names amd64" 1 "amd64"

# 4: both wrong — both reported, not just the first
fresh; write_def "$BOGUS" "$BOGUS"
run_case "both wrong fails" 1
run_case "reports amd64" 1 "amd64"
run_case "reports arm64" 1 "arm64"

# 5: definition with no per-arch checksum expression is skipped, not failed —
# most definitions build from source and pin nothing per arch.
fresh
cat > "$SB/image.yaml" <<'EOF'
name: App
image: ghcr.io/mm-weber/dhc/app
vars:
  VERSION: 1.0.0
EOF
run_case "no per-arch pin is skipped" 0 "nothing to verify"

# 6: url without ${target.arch} is not a per-arch artifact
fresh
cat > "$SB/image.yaml" <<EOF
vars:
  APP_SHA256: '#{ target.arch == "amd64" ? "$SHA_AMD" : "$SHA_ARM" }'
contents:
  builds:
    - contents:
        files:
          - url: file://$SB/dist/app_amd64.tar.gz
EOF
run_case "url without target.arch is skipped" 0 "nothing to verify"

# 7: a fetch that fails is a failure, never a silent pass — the whole point is
# that an unverified pin must not look like a verified one.
fresh; write_def "$SHA_AMD" "$SHA_ARM" "file://$SB/does-not-exist_\${target.arch}.tar.gz"
run_case "unfetchable artifact fails" 1
run_case "fetch failure is named as such" 1 "could not fetch"

# 8: missing definition
SB=$(mktemp -d)
run_case "missing image.yaml fails" 1 "no image.yaml"

# 9: the pinned url is echoed so a reviewer can see WHICH path was verified —
# the alias-vs-per-build distinction this whole episode turned on.
fresh; write_def "$SHA_AMD" "$SHA_ARM"
run_case "reports the url verified" 0 "dist/app_amd64.tar.gz"

# --- Req 3.9 (task 11.3): the version statement is the third value -----------

# 10: pinned and served agree, the statement says otherwise for arm64: a failure naming all three
fresh; write_def "$SHA_AMD" "$SHA_ARM"; statement "$SHA_AMD" "$BOGUS"
run_case "statement disagrees: fails" 1
run_case "statement disagrees: names the statement's value" 1 "version statement $BOGUS"
run_case "statement disagrees: names what was served" 1 "upstream served $SHA_ARM"
refute_case "statement disagrees: amd64 is not blamed" 1 "amd64 MISMATCH"
run_case "statement agrees: said so" 1 "amd64 OK"

# 11: no statement for the version: nothing is verified, by name
fresh; write_def "$SHA_AMD" "$SHA_ARM"; rm "$SB/api/1.0.0"
run_case "missing statement fails" 1 "could not read the version statement for 1.0.0"

# 12: a host with no known statement origin fails closed
fresh; write_def "$SHA_AMD" "$SHA_ARM"; unset DHC_VERSIONS_API
run_case "unknown origin fails closed" 1 "no version statement origin is known"

echo
if [ "$FAILURES" -eq 0 ]; then echo "all verify-arch-pins tests passed"; else echo "$FAILURES failing assertion(s)"; fi
exit $((FAILURES > 0))
