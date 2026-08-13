#!/usr/bin/env bash
# Tests for scripts/install-tool.sh — self-contained sandbox, no network.
#
# Same defect class as install-scanners_test.sh: a binary installed whose
# checksum did not match or never got computed. The contract differs where the
# script does — one tool per invocation, and kind is a bare binary while
# kyverno is a tarball, so both artifact shapes are exercised.
#
#   scripts/install-tool.sh <kind|kyverno> [<destdir>]
#
#   Exit 0 on success, exit 1 on any fetch/verification/architecture/usage
#   failure (asserted exactly — an absent script exits 127).
#
#   Seams (same design as install-scanners_test.sh, where the widening is
#   justified at length): INSTALL_TOOL_BASE_URL serves the real download paths
#   from a file:// fixture tree; INSTALL_TOOL_PINS substitutes digests so the
#   success path is reachable offline; INSTALL_TOOL_ARCH pins the architecture
#   so the suite behaves the same on any host. The shipped pins are exercised
#   with no override in group 5 and must reject the fixtures, quoting the
#   documented digests back verbatim.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALL="$HERE/install-tool.sh"
FAILURES=0

# The pins the script must ship with, verified against the digests upstream
# publishes beside each release (kind-linux-amd64.sha256sum, checksums.txt).
KIND_VER=0.32.0
KYVERNO_VER=1.18.2
KIND_ASSET="kind-linux-amd64"
KYVERNO_ASSET="kyverno-cli_v${KYVERNO_VER}_linux_x86_64.tar.gz"
KIND_URLDIR="kubernetes-sigs/kind/releases/download/v${KIND_VER}"
KYVERNO_URLDIR="kyverno/kyverno/releases/download/v${KYVERNO_VER}"
KIND_PIN=50030de23cf40a18505f20426f6a8506bedf13c6e509244bd1fa9463721b0f54
KYVERNO_PIN=cb2feb8356149fd2fe774c894ccf0969f4a60a83867dd913af724f74ffbbc18b
KIND_DEP=kubernetes-sigs/kind
KYVERNO_DEP=kyverno/kyverno

DEFAULT_ARCH=x86_64
ARCH="$DEFAULT_ARCH"

KIND_MARKER="kind v${KIND_VER} (dhc-test-fixture)"
KYVERNO_MARKER="kyverno v${KYVERNO_VER} (dhc-test-fixture)"

list_real_bin() { find /usr/local/bin -maxdepth 1 -printf '%f\n' 2>/dev/null | sort; }
BIN_BEFORE=$(list_real_bin)

pass() { echo "ok   $1"; }
fail() { # name, why, [context]
  local name="$1" why="$2" ctx="${3:-}"
  echo "FAIL $name: $why"
  if [ -n "$ctx" ]; then printf '%s\n' "$ctx" | sed 's/^/    /'; fi
  FAILURES=$((FAILURES+1))
}

assert_rc() { # name, expected_exit
  if [ "$RC" -eq "$2" ]; then pass "$1"; else fail "$1" "exit $RC, expected $2" "$OUT"; fi
}
assert_out() { # name, substring
  if grep -qF "$2" <<<"$OUT"; then pass "$1"; else fail "$1" "output missing '$2'" "$OUT"; fi
}
assert_installed() { # name, tool
  if [ ! -f "$DEST/$2" ]; then fail "$1" "$DEST/$2 does not exist" "$OUT"
  elif [ ! -x "$DEST/$2" ]; then fail "$1" "$DEST/$2 is not executable" "$OUT"
  else pass "$1"; fi
}
assert_absent() { # name, tool
  if [ -e "$DEST/$2" ]; then fail "$1" "$DEST/$2 exists — an unverified binary was installed" "$OUT"
  else pass "$1"; fi
}
assert_payload() { # name, tool, marker
  local got
  if [ ! -x "$DEST/$2" ]; then fail "$1" "$DEST/$2 is not an executable file" "$OUT"; return; fi
  got=$("$DEST/$2" --version 2>&1) || true
  if grep -qF "$3" <<<"$got"; then pass "$1"
  else fail "$1" "installed $2 printed '$got', expected it to contain '$3'"; fi
}
# The Renovate inline-comment pin block — same six-way assertion as
# install-scanners_test.sh, because the same six things can silently break it.
assert_pin_block() { # tool, VARPREFIX, depName, version, sha256
  local tool="$1" pfx="$2" dep="$3" ver="$4" sha="$5"
  local vline="" sline="" text prev val n

  if [ -f "$INSTALL" ]; then
    vline=$(grep -nE "^[[:space:]]*${pfx}_VERSION=" "$INSTALL" | head -1)
    sline=$(grep -nE "^[[:space:]]*${pfx}_SHA256=" "$INSTALL" | head -1)
  fi

  text="${vline#*:}"
  if [ -z "$vline" ]; then
    fail "$tool version pin is a bare quoted semver" "no ${pfx}_VERSION= assignment in $INSTALL"
  elif grep -qE "^[[:space:]]*${pfx}_VERSION=\"[0-9]+\.[0-9]+\.[0-9]+\"[[:space:]]*\$" <<<"$text"; then
    pass "$tool version pin is a bare quoted semver"
  else
    fail "$tool version pin is a bare quoted semver" "got: $text"
  fi

  val=$(sed -nE "s/^[[:space:]]*${pfx}_VERSION=\"?([^\"]*)\"?.*/\1/p" <<<"$text")
  if [ "$val" = "$ver" ]; then pass "$tool version pin is $ver"
  else fail "$tool version pin is $ver" "got: '${val}'"; fi

  if [ -z "$vline" ]; then
    fail "$tool version pin sits directly under a renovate comment" "no ${pfx}_VERSION= assignment"
    fail "the $tool renovate comment declares github-releases and $dep" "no ${pfx}_VERSION= assignment"
  else
    n="${vline%%:*}"
    prev=""
    [ "$n" -gt 1 ] && prev=$(sed -n "$((n-1))p" "$INSTALL")
    if grep -qE '^[[:space:]]*#[[:space:]]*renovate:' <<<"$prev"; then
      pass "$tool version pin sits directly under a renovate comment"
    else
      fail "$tool version pin sits directly under a renovate comment" "line $((n-1)) is: ${prev}"
    fi
    if grep -qE '^[[:space:]]*#[[:space:]]*renovate:.*datasource=github-releases' <<<"$prev" \
       && grep -qF "depName=${dep}" <<<"$prev"; then
      pass "the $tool renovate comment declares github-releases and $dep"
    else
      fail "the $tool renovate comment declares github-releases and $dep" "line $((n-1)) is: ${prev}"
    fi
  fi

  text="${sline#*:}"
  if [ -z "$sline" ]; then
    fail "$tool sha256 pin is 64 lowercase hex" "no ${pfx}_SHA256= assignment in $INSTALL"
    fail "$tool sha256 pin is the documented digest" "no ${pfx}_SHA256= assignment"
  else
    if grep -qE "^[[:space:]]*${pfx}_SHA256=\"[0-9a-f]{64}\"[[:space:]]*\$" <<<"$text"; then
      pass "$tool sha256 pin is 64 lowercase hex"
    else
      fail "$tool sha256 pin is 64 lowercase hex" "got: $text"
    fi
    val=$(sed -nE "s/^[[:space:]]*${pfx}_SHA256=\"?([^\"]*)\"?.*/\1/p" <<<"$text")
    if [ "$val" = "$sha" ]; then pass "$tool sha256 pin is the documented digest"
    else fail "$tool sha256 pin is the documented digest" "got: '${val}'"; fi
  fi
}

assert_source() { # name, present|absent, extended-regex — non-comment lines only
  local name="$1" mode="$2" re="$3" body
  if [ ! -f "$INSTALL" ]; then fail "$name" "$INSTALL does not exist"; return; fi
  body=$(grep -vE '^[[:space:]]*#' "$INSTALL")
  if grep -qE "$re" <<<"$body"; then
    if [ "$mode" = present ]; then pass "$name"; else fail "$name" "script matches /$re/"; fi
  else
    if [ "$mode" = absent ]; then pass "$name"; else fail "$name" "script does not match /$re/"; fi
  fi
}

# kind's asset is the bare binary; kyverno's is a tarball that also carries a
# licence file, so extracting the whole archive into a PATH directory is
# visible (same trick as install-scanners_test.sh).
make_kind_asset() { # marker
  mkdir -p "$UP/$KIND_URLDIR"
  printf '#!/bin/sh\necho "%s"\n' "$1" > "$UP/$KIND_URLDIR/$KIND_ASSET"
}
make_kyverno_asset() { # marker
  local stage
  stage=$(mktemp -d "$SB/stage.XXXXXX")
  printf '#!/bin/sh\necho "%s"\n' "$1" > "$stage/kyverno"
  chmod +x "$stage/kyverno"
  printf 'Apache License 2.0\n' > "$stage/LICENSE"
  mkdir -p "$UP/$KYVERNO_URLDIR"
  tar -czf "$UP/$KYVERNO_URLDIR/$KYVERNO_ASSET" -C "$stage" kyverno LICENSE
  rm -rf "$stage"
}

setup() { # fresh sandbox: both assets served, empty destdir, shipped pins in force
  SB=$(mktemp -d)
  UP="$SB/upstream"
  DEST="$SB/bin"
  PINS=""
  ARCH="$DEFAULT_ARCH"
  mkdir -p "$DEST"
  make_kind_asset "$KIND_MARKER"
  make_kyverno_asset "$KYVERNO_MARKER"
}

write_pins() { # record the fixtures' real digests — the offline success path
  PINS="$SB/pins.sha256"
  : > "$PINS"
  (cd "$UP/$KIND_URLDIR" && sha256sum "$KIND_ASSET") >> "$PINS"
  (cd "$UP/$KYVERNO_URLDIR" && sha256sum "$KYVERNO_ASSET") >> "$PINS"
}

asset_sha() { sha256sum "$1" | cut -d' ' -f1; }

invoke() { # tool — output in $OUT, status in $RC
  local vars=("INSTALL_TOOL_BASE_URL=file://$UP" "INSTALL_TOOL_ARCH=$ARCH")
  [ -n "$PINS" ] && vars+=("INSTALL_TOOL_PINS=$PINS")
  OUT=$(env "${vars[@]}" "$INSTALL" "$1" "$DEST" 2>&1); RC=$?
}

# 0: preflight
if [ -x "$INSTALL" ]; then pass "install-tool.sh exists and is executable"
else
  echo "FAIL install-tool.sh exists and is executable: no executable at $INSTALL"
  FAILURES=$((FAILURES+1))
fi

# --- 1: the success path, both artifact shapes -------------------------------

setup; write_pins; invoke kind
assert_rc        "kind: matching checksum installs cleanly" 0
assert_installed "kind is installed and executable" kind
assert_payload   "installed kind is the artifact that was verified" kind "$KIND_MARKER"
assert_out       "reports the kind version it installed" "$KIND_VER"
assert_absent    "kind: kyverno was not asked for and is not installed" kyverno

setup; write_pins; invoke kyverno
assert_rc        "kyverno: matching checksum installs cleanly" 0
assert_installed "kyverno is installed and executable" kyverno
assert_payload   "installed kyverno is the archive that was verified" kyverno "$KYVERNO_MARKER"
assert_out       "reports the kyverno version it installed" "$KYVERNO_VER"

# destdir is a PATH directory: the tarball's licence file stays out of it.
stray=""
for f in "$DEST"/* "$DEST"/.[!.]*; do
  [ -e "$f" ] || continue
  case "${f##*/}" in kyverno) ;; *) stray="$stray ${f##*/}" ;; esac
done
if [ -z "$stray" ]; then pass "only the kyverno binary lands in destdir"
else fail "only the kyverno binary lands in destdir" "destdir also holds:$stray"; fi

# --- 2: destdir handling ----------------------------------------------------

setup; write_pins; DEST="$SB/fresh-bin"; invoke kind
assert_rc        "a destdir that does not exist is created" 0
assert_installed "…and the binary lands in it" kind

setup; write_pins; invoke kyverno; invoke kyverno
assert_rc      "a second run over an existing install succeeds" 0
assert_payload "…and the binary still works afterwards" kyverno "$KYVERNO_MARKER"

setup; write_pins
printf '#!/bin/sh\necho "PWNED-preexisting"\n' > "$DEST/kind"; chmod +x "$DEST/kind"
invoke kind
assert_rc      "a binary already in destdir does not short-circuit the install" 0
assert_payload "…it is replaced by the verified payload, not trusted" kind "$KIND_MARKER"

# --- 3: an artifact that is not what was pinned ------------------------------
# THE case, once per artifact shape.

setup; write_pins
make_kind_asset "PWNED-kind"
served=$(asset_sha "$UP/$KIND_URLDIR/$KIND_ASSET")
want=$(grep -F "$KIND_ASSET" "$PINS" | cut -d' ' -f1)
invoke kind
assert_rc     "a kind checksum mismatch fails" 1
assert_absent "the unverified kind is not installed" kind
assert_out    "the failure names kind" kind
assert_out    "the failure quotes the pinned digest" "$want"
assert_out    "the failure quotes the digest actually served" "$served"

setup; write_pins
make_kyverno_asset "PWNED-kyverno"
invoke kyverno
assert_rc     "a kyverno checksum mismatch fails" 1
assert_absent "the unverified kyverno is not installed" kyverno
assert_out    "the failure names kyverno" kyverno

# --- 5: the shipped pins are live and are the documented ones ---------------

setup; invoke kind
assert_rc     "with no pin override the kind fixture is rejected" 1
assert_absent "nothing is installed when the shipped pin does not match" kind
assert_out    "the shipped kind pin is the documented digest" "$KIND_PIN"

setup; invoke kyverno
assert_rc     "with no pin override the kyverno fixture is rejected" 1
assert_absent "nothing is installed when the shipped pin does not match (kyverno)" kyverno
assert_out    "the shipped kyverno pin is the documented digest" "$KYVERNO_PIN"

# --- 6: an asset with no recorded pin ---------------------------------------

setup; write_pins
grep -vF "$KIND_ASSET" "$PINS" > "$PINS.trimmed" && mv "$PINS.trimmed" "$PINS"
invoke kind
assert_rc     "an asset with no recorded pin fails" 1
assert_out    "…and says which one" kind
assert_absent "…and installs nothing" kind

# --- 7: a fetch that does not happen ----------------------------------------

setup; write_pins; rm -f "$UP/$KYVERNO_URLDIR/$KYVERNO_ASSET"; invoke kyverno
assert_rc     "an artifact that cannot be fetched fails" 1
assert_out    "the fetch failure names the asset" "$KYVERNO_ASSET"
assert_absent "an unfetchable kyverno is not installed" kyverno

# --- 8: an architecture the pins are not for --------------------------------

setup; write_pins; ARCH=aarch64; invoke kind
assert_rc     "an unsupported architecture fails" 1
assert_out    "the refusal names the architecture" aarch64
assert_absent "no kind is installed on an unsupported architecture" kind

# --- 8b: a tool this script does not pin ------------------------------------
# Refused before any fetch: "install-tool.sh trivy" quietly falling through to
# an unpinned path is a fourth unverified install wearing this script's name.

setup; write_pins; invoke trivy
assert_rc     "an unknown tool is refused" 1
assert_out    "the refusal states the usage" usage
assert_absent "nothing is installed for an unknown tool" trivy

setup; write_pins
OUT=$(env "INSTALL_TOOL_BASE_URL=file://$UP" "INSTALL_TOOL_ARCH=$ARCH" "$INSTALL" 2>&1); RC=$?
assert_rc     "a missing tool argument is refused" 1

# --- 9: the pin block Renovate reads (Req 7.6) ------------------------------

assert_pin_block kind KIND "$KIND_DEP" "$KIND_VER" "$KIND_PIN"
assert_pin_block kyverno KYVERNO "$KYVERNO_DEP" "$KYVERNO_VER" "$KYVERNO_PIN"

# --- 10: what the source must and must not contain --------------------------

assert_source "default destdir is /usr/local/bin" present '/usr/local/bin'
assert_source "the architecture defaults to uname -m" present 'uname[[:space:]]+-m'
assert_source "nothing is piped into a shell" absent '\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh([[:space:]]|$)'
assert_source "nothing is piped into tar" absent 'curl[^|]*\|[[:space:]]*tar'
assert_source "nothing is fetched from a mutable branch" absent 'raw\.githubusercontent\.com'

# --- 11: the test itself stayed inside its sandbox --------------------------
BIN_AFTER=$(list_real_bin)
if [ "$BIN_BEFORE" = "$BIN_AFTER" ]; then pass "the real /usr/local/bin was not touched"
else fail "the real /usr/local/bin was not touched" "it changed during this run — the script ignored its destdir argument"; fi

echo
if [ "$FAILURES" -eq 0 ]; then echo "all install-tool tests passed"; else echo "$FAILURES failing assertion(s)"; fi
exit $((FAILURES > 0))
