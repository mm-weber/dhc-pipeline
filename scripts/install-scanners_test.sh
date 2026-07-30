#!/usr/bin/env bash
# Tests for scripts/install-scanners.sh — self-contained sandbox, no network.
#
# What is under test (Req 7.5, CONVENTIONS.md "Pinning"): the script that puts
# trivy and grype on a CI runner that is holding registry tokens and cosign
# signing permissions. It replaces
#
#     curl -fsSL https://raw.githubusercontent.com/…/main/contrib/install.sh | sudo sh
#
# — an unpinned script off a mutable branch, run as root. CVE-2026-33634 /
# GHSA-69fq-xp46-6x23 (March 2026) is what that costs: a malicious trivy
# v0.69.4 published, 76 of 77 `aquasecurity/trivy-action` tags force-pushed to a
# credential stealer, all 7 `aquasecurity/setup-trivy` tags replaced. So the one
# defect these cases exist to catch is a binary installed whose checksum did not
# match or never got computed — and its sibling, a half-finished install a later
# step reads as success.
#
# ---------------------------------------------------------------------------
# The contract asserted here (the implementation is to be derived from it)
#
#   scripts/install-scanners.sh [<destdir>]     destdir defaults to /usr/local/bin
#
#   Exit 0 on success, exit 1 on any fetch, verification or architecture
#   failure. Asserted as an exact code, never as "non-zero": an absent script
#   exits 127, and every failure case below would otherwise be satisfied by
#   "command not found".
#
#   INSTALL_SCANNERS_BASE_URL — overrides the release host (default
#       https://github.com). Everything after the host is the real download
#       path, so with the override set the two fetches are:
#
#         $BASE/aquasecurity/trivy/releases/download/v0.72.0/trivy_0.72.0_Linux-64bit.tar.gz
#         $BASE/anchore/grype/releases/download/v0.116.1/grype_0.116.1_linux_amd64.tar.gz
#
#       The fixture tree below is laid out at exactly those paths and served
#       over file://, so the real curl code path runs end to end and a wrong
#       version, repo or asset name shows up as a failed fetch. A stubbed
#       fetch would test nothing.
#
#   INSTALL_SCANNERS_PINS — optional path to a sha256sum(1)-format file
#       ("<64hex><space><space><asset-filename>", one asset per line) that
#       replaces the digests the script ships with. Absent, the shipped digests
#       apply.
#
#       This second seam is not a convenience, and it is a deliberate widening
#       of the brief — say so in review. The shipped pins are the digests of the
#       real releases; no fixture this test can build will ever hash to them, so
#       with only a base-url override the sole reachable outcome is failure.
#       Every success-path defect — installs bytes it never verified, installs
#       nothing and exits 0, leaves tool A behind after tool B fails, trusts a
#       binary that was already sitting in destdir — would be untestable
#       offline. The shipped pins are still exercised: group 5 runs with no
#       override at all and requires the fixtures to be rejected, with the
#       documented digests quoted back verbatim.
#
#   INSTALL_SCANNERS_ARCH — the architecture the pins are for, default
#       `uname -m`. Both pinned assets are linux/amd64 only, so anything that is
#       not the x86_64 spelling must be refused outright: on an arm64 runner
#       both checksums verify perfectly and the binary still cannot execute.
#       Every case below passes x86_64 explicitly so the suite does not depend
#       on the host it runs on; group 8 passes aarch64 and requires a refusal.
#
#   The pins are carried in the script as a Renovate inline-comment block
#   (group 9 asserts its shape line by line):
#
#     # renovate: datasource=github-releases depName=aquasecurity/trivy
#     TRIVY_VERSION="0.72.0"
#     TRIVY_SHA256="bbb64b96…"
#
#   The shape is load-bearing, not cosmetic. If it drifts, Renovate's manager
#   stops matching, nothing ever bumps the scanner, and a stale scanner reports
#   clean — the silent failure this repo exists to remove (Req 7.6,
#   CONVENTIONS.md "Pinning"). So it is under test, not under review.
#
# Never writes to /usr/local/bin: every invocation is handed an explicit destdir
# inside the sandbox, and the final case fails if the real directory changed.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALL="$HERE/install-scanners.sh"
FAILURES=0

# The pins the script must ship with, verified by hand against the real
# releases. Group 5 requires these exact strings to come back out of it.
TRIVY_VER=0.72.0
GRYPE_VER=0.116.1
TRIVY_ASSET="trivy_${TRIVY_VER}_Linux-64bit.tar.gz"
GRYPE_ASSET="grype_${GRYPE_VER}_linux_amd64.tar.gz"
TRIVY_URLDIR="aquasecurity/trivy/releases/download/v${TRIVY_VER}"
GRYPE_URLDIR="anchore/grype/releases/download/v${GRYPE_VER}"
TRIVY_PIN=bbb64b9695866ce4a7a8f5c9592002c5961cab378577fa3f8a040df362b9b2ea
GRYPE_PIN=0122df7b655981abe547ad3d2190d65551dac6a2bfc80b4dc2a989b5d0587458
TRIVY_DEP=aquasecurity/trivy
GRYPE_DEP=anchore/grype

# The arch every case but group 8 runs as — the `uname -m` spelling, passed
# explicitly so the suite behaves the same wherever it is run.
DEFAULT_ARCH=x86_64
ARCH="$DEFAULT_ARCH"

# Distinguishable payloads: an installed file is only correct if running it
# prints the marker from the archive that was verified.
TRIVY_MARKER="Version: ${TRIVY_VER} (dhc-test-fixture)"
GRYPE_MARKER="grype ${GRYPE_VER} (dhc-test-fixture)"

# Snapshot the one directory this test must never modify.
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
assert_payload() { # name, tool, marker — the installed file must BE the verified archive's binary
  local got
  if [ ! -x "$DEST/$2" ]; then fail "$1" "$DEST/$2 is not an executable file" "$OUT"; return; fi
  got=$("$DEST/$2" --version 2>&1) || true
  if grep -qF "$3" <<<"$got"; then pass "$1"
  else fail "$1" "installed $2 printed '$got', expected it to contain '$3'"; fi
}
# The Renovate inline-comment pin block. Six assertions per tool, because six
# different things can be wrong with it and only one of them is the value.
assert_pin_block() { # tool, VARPREFIX, depName, version, sha256
  local tool="$1" pfx="$2" dep="$3" ver="$4" sha="$5"
  local vline="" sline="" text prev val n

  if [ -f "$INSTALL" ]; then
    vline=$(grep -nE "^[[:space:]]*${pfx}_VERSION=" "$INSTALL" | head -1)
    sline=$(grep -nE "^[[:space:]]*${pfx}_SHA256=" "$INSTALL" | head -1)
  fi

  # A bare quoted semver. A `v` prefix, an unquoted value or a version smuggled
  # into the url instead is a currentValue Renovate cannot compare or replace.
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

  # Renovate binds the comment to the line directly below it. One blank line or
  # one reordering in between and the manager reads nothing — with no error,
  # which is the whole problem.
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
    # Wrong datasource or a typo'd repo tracks nothing, just as silently.
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
    # Uppercase hex or a truncated paste compares unequal against sha256sum
    # output forever — a pin that can only ever fail is not a working pin.
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

assert_source() { # name, present|absent, extended-regex — read on non-comment lines only
  local name="$1" mode="$2" re="$3" body
  if [ ! -f "$INSTALL" ]; then fail "$name" "$INSTALL does not exist"; return; fi
  body=$(grep -vE '^[[:space:]]*#' "$INSTALL")
  if grep -qE "$re" <<<"$body"; then
    if [ "$mode" = present ]; then pass "$name"; else fail "$name" "script matches /$re/"; fi
  else
    if [ "$mode" = absent ]; then pass "$name"; else fail "$name" "script does not match /$re/"; fi
  fi
}

# A fixture release asset, laid down at the exact path the real download url
# has. Contents mirror the real archives: the binary plus the licence file they
# both ship, so extracting the whole tarball into a PATH directory is visible.
make_asset() { # tool, urldir, asset, marker
  local tool="$1" urldir="$2" asset="$3" marker="$4" stage
  stage=$(mktemp -d "$SB/stage.XXXXXX")
  printf '#!/bin/sh\necho "%s"\n' "$marker" > "$stage/$tool"
  chmod +x "$stage/$tool"
  printf 'Apache License 2.0\n' > "$stage/LICENSE"
  mkdir -p "$UP/$urldir"
  tar -czf "$UP/$urldir/$asset" -C "$stage" "$tool" LICENSE
  rm -rf "$stage"
}

setup() { # fresh sandbox: both assets served, empty destdir, shipped pins in force
  SB=$(mktemp -d)
  UP="$SB/upstream"
  DEST="$SB/bin"
  PINS=""
  ARCH="$DEFAULT_ARCH"
  mkdir -p "$DEST"
  make_asset trivy "$TRIVY_URLDIR" "$TRIVY_ASSET" "$TRIVY_MARKER"
  make_asset grype "$GRYPE_URLDIR" "$GRYPE_ASSET" "$GRYPE_MARKER"
}

# Records the fixtures' real digests, so a run with these pins is the success
# path. Anything re-made after this call is, by construction, not what was
# pinned — which is exactly the shape of a repointed release.
write_pins() {
  PINS="$SB/pins.sha256"
  : > "$PINS"
  (cd "$UP/$TRIVY_URLDIR" && sha256sum "$TRIVY_ASSET") >> "$PINS"
  (cd "$UP/$GRYPE_URLDIR" && sha256sum "$GRYPE_ASSET") >> "$PINS"
}

asset_sha() { sha256sum "$1" | cut -d' ' -f1; }

invoke() { # run the script over the sandbox; output in $OUT, status in $RC
  local vars=("INSTALL_SCANNERS_BASE_URL=file://$UP" "INSTALL_SCANNERS_ARCH=$ARCH")
  [ -n "$PINS" ] && vars+=("INSTALL_SCANNERS_PINS=$PINS")
  OUT=$(env "${vars[@]}" "$INSTALL" "$DEST" 2>&1); RC=$?
}

# 0: preflight, so a red suite says "not written yet" once instead of 30 times
if [ -x "$INSTALL" ]; then pass "install-scanners.sh exists and is executable"
else
  echo "FAIL install-scanners.sh exists and is executable: no executable at $INSTALL"
  FAILURES=$((FAILURES+1))
fi

# --- 1: the success path ----------------------------------------------------
# Without one of these, "always fail" would satisfy every case below it.

setup; write_pins; invoke
assert_rc        "matching checksums install cleanly" 0
assert_installed "trivy is installed and executable" trivy
assert_payload   "installed trivy is the archive that was verified" trivy "$TRIVY_MARKER"
assert_installed "grype is installed and executable" grype
assert_payload   "installed grype is the archive that was verified" grype "$GRYPE_MARKER"
assert_out       "reports the trivy version it installed" "$TRIVY_VER"
assert_out       "reports the grype version it installed" "$GRYPE_VER"

# destdir is a PATH directory, not a scratch dir: the archive and its licence
# file have no business landing in it.
stray=""
for f in "$DEST"/* "$DEST"/.[!.]*; do
  [ -e "$f" ] || continue
  case "${f##*/}" in trivy|grype) ;; *) stray="$stray ${f##*/}" ;; esac
done
if [ -z "$stray" ]; then pass "only the two binaries land in destdir"
else fail "only the two binaries land in destdir" "destdir also holds:$stray"; fi

# --- 2: destdir handling ----------------------------------------------------

# A destdir that does not exist yet is created, not fumbled into a silent
# no-install. (The default /usr/local/bin always exists; an argument may not.)
setup; write_pins; DEST="$SB/fresh-bin"; invoke
assert_rc        "a destdir that does not exist is created" 0
assert_installed "…and the binaries land in it" trivy

# Re-running must not fail on an existing target, and must not skip on one.
setup; write_pins; invoke; invoke
assert_rc      "a second run over an existing install succeeds" 0
assert_payload "…and the binaries still work afterwards" trivy "$TRIVY_MARKER"

# The install-skipping shortcut with teeth: `[ -x $dest/trivy ] && exit 0` turns
# anything an earlier step left in destdir into a scanner this script vouched
# for. The pinned bytes must win.
setup; write_pins
printf '#!/bin/sh\necho "PWNED-preexisting"\n' > "$DEST/trivy"; chmod +x "$DEST/trivy"
invoke
assert_rc      "a binary already in destdir does not short-circuit the install" 0
assert_payload "…it is replaced by the verified payload, not trusted" trivy "$TRIVY_MARKER"

# --- 3: a trivy artifact that is not what was pinned ------------------------
# THE case. A well-formed archive carrying a different binary — the only thing
# separating it from the real release is its digest.

setup; write_pins
make_asset trivy "$TRIVY_URLDIR" "$TRIVY_ASSET" "PWNED-trivy"
served=$(asset_sha "$UP/$TRIVY_URLDIR/$TRIVY_ASSET")
want=$(grep -F "$TRIVY_ASSET" "$PINS" | cut -d' ' -f1)
invoke
assert_rc     "a trivy checksum mismatch fails" 1
assert_absent "the unverified trivy is not installed" trivy
assert_absent "and grype is not installed either — no half-done install" grype
assert_out    "the failure names trivy" trivy
assert_out    "the failure quotes the pinned digest" "$want"
assert_out    "the failure quotes the digest actually served" "$served"

# --- 4: same, the other way round -------------------------------------------
# Order-independence: whichever tool is verified first, the other must not be
# left installed. A gate that finds trivy on PATH treats that as success.

setup; write_pins
make_asset grype "$GRYPE_URLDIR" "$GRYPE_ASSET" "PWNED-grype"
invoke
assert_rc     "a grype checksum mismatch fails" 1
assert_absent "the unverified grype is not installed" grype
assert_absent "and trivy is not installed either — no half-done install" trivy
assert_out    "the failure names grype" grype

# --- 5: the shipped pins are live and are the documented ones ---------------
# No override at all. The fixtures cannot hash to the real releases' digests, so
# the only correct outcome is rejection — and the digests it rejects them
# against must be the ones recorded in this repository. Both tools are reported
# in one run: fixing pins one failure at a time is how the second one gets
# missed (same rule as verify-arch-pins.sh).

setup; invoke
assert_rc     "with no pin override the fixtures are rejected" 1
assert_absent "nothing is installed when the shipped pins do not match" trivy
assert_absent "nothing is installed when the shipped pins do not match (grype)" grype
assert_out    "the shipped trivy pin is the documented digest" "$TRIVY_PIN"
assert_out    "the shipped grype pin is the documented digest" "$GRYPE_PIN"

# --- 6: an asset with no recorded pin -------------------------------------
# Nothing to compare against is not "nothing to check". An empty expected value
# compared against a computed digest is the classic silent pass.

setup; write_pins
grep -vF "$GRYPE_ASSET" "$PINS" > "$PINS.trimmed" && mv "$PINS.trimmed" "$PINS"
invoke
assert_rc     "an asset with no recorded pin fails" 1
assert_out    "…and says which one" grype
assert_absent "…and installs neither tool" grype
assert_absent "…and installs neither tool (trivy)" trivy

# --- 7: a fetch that does not happen ----------------------------------------
# curl without -f, or with its exit status unchecked, hashes an error page or a
# zero-byte file and marches on. An unfetchable artifact is a failure, never a
# quiet skip.

setup; write_pins; rm -f "$UP/$TRIVY_URLDIR/$TRIVY_ASSET"; invoke
assert_rc     "an artifact that cannot be fetched fails" 1
assert_out    "the fetch failure names the asset" "$TRIVY_ASSET"
assert_absent "an unfetchable trivy is not installed" trivy
assert_absent "and grype is not installed either" grype

# --- 8: an architecture the pins are not for --------------------------------
# Both pinned assets are linux/amd64. On an arm64 runner every checksum matches
# and the binary is still unrunnable — "cannot execute binary file", hundreds of
# log lines later, in whichever step first calls a scanner. Refusing up front is
# the only honest outcome, and it refuses completely: same no-partial-install
# discipline as the tampering groups.

setup; write_pins; ARCH=aarch64; invoke
assert_rc     "an unsupported architecture fails" 1
assert_out    "the refusal names the architecture" aarch64
assert_absent "no trivy is installed on an unsupported architecture" trivy
assert_absent "no grype is installed on an unsupported architecture" grype

# --- 9: the pin block Renovate reads (Req 7.6) ------------------------------
# A pinned scanner nobody bumps is a scanner that reports clean while the CVE
# it should have found ages in its stale database. The manager that prevents
# that matches on shape, so the shape is asserted here rather than trusted to
# review.

assert_pin_block trivy TRIVY "$TRIVY_DEP" "$TRIVY_VER" "$TRIVY_PIN"
assert_pin_block grype GRYPE "$GRYPE_DEP" "$GRYPE_VER" "$GRYPE_PIN"

# --- 10: what the source must and must not contain --------------------------
# Two defaults cannot be exercised from here — this test may not write to
# /usr/local/bin, and it pins the architecture on every run so it behaves the
# same on any host — so both are read out of the script instead.

assert_source "default destdir is /usr/local/bin" present '/usr/local/bin'
assert_source "the architecture defaults to uname -m" present 'uname[[:space:]]+-m'
# Comments are stripped first: the header will quite reasonably quote the line
# this script replaces.
assert_source "nothing is piped into a shell" absent '\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh([[:space:]]|$)'
assert_source "nothing is fetched from a mutable branch" absent 'raw\.githubusercontent\.com'

# --- 11: the test itself stayed inside its sandbox --------------------------
BIN_AFTER=$(list_real_bin)
if [ "$BIN_BEFORE" = "$BIN_AFTER" ]; then pass "the real /usr/local/bin was not touched"
else fail "the real /usr/local/bin was not touched" "it changed during this run — the script ignored its destdir argument"; fi

echo
if [ "$FAILURES" -eq 0 ]; then echo "all install-scanners tests passed"; else echo "$FAILURES failing assertion(s)"; fi
exit $((FAILURES > 0))
