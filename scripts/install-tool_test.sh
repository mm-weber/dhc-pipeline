#!/usr/bin/env bash
# Tests for scripts/install-tool.sh — self-contained sandbox, no network.
#
# Same defect class as install-scanners_test.sh: a binary installed whose
# checksum did not match or never got computed. The contract differs where the
# script does — one tool per invocation, and kind is a bare binary while
# kyverno is a tarball, so both artifact shapes are exercised.
#
#   scripts/install-tool.sh <kind|kyverno|helm|ct> [<destdir>]
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

# helm's binaries live on get.helm.sh (the GitHub release carries source
# only), so its fixture sits at the served root; ct is a github tarball whose
# archive also ships the lint configs ct needs at runtime.
HELM_VER=4.2.4
CT_VER=3.14.0
HELM_ASSET="helm-v${HELM_VER}-linux-amd64.tar.gz"
CT_ASSET="chart-testing_${CT_VER}_linux_amd64.tar.gz"
CT_URLDIR="helm/chart-testing/releases/download/v${CT_VER}"
HELM_PIN=c306b46f719b0a4da32d0f78ee21bf90ce8d602f15b22ab753f0674d1670a7f3
CT_PIN=d16f0583616885423826241164ce1f6589c6fe5332fa74f374ebd2bd3cb3fe1f
HELM_DEP=helm/helm
CT_DEP=helm/chart-testing

# syft generates the SBOMs the release arm attests per platform manifest
# (Req 2.9); its archive is a github tarball with the binary at the root.
SYFT_VER=1.51.1
SYFT_ASSET="syft_${SYFT_VER}_linux_amd64.tar.gz"
SYFT_URLDIR="anchore/syft/releases/download/v${SYFT_VER}"
SYFT_PIN=8fcb33017a0dc1058298c923c436d19dfa68ae93968e0b423248542e3afb9fc3
SYFT_DEP=anchore/syft

# crane lists registry tags for the rescan enumeration (Req 2.22, task 9.3);
# a github tarball with the binary at the root, and the one asset here whose
# filename carries NO version — only the URL path does.
CRANE_VER=0.22.0
CRANE_ASSET="go-containerregistry_Linux_x86_64.tar.gz"
CRANE_URLDIR="google/go-containerregistry/releases/download/v${CRANE_VER}"
CRANE_PIN=edb74d53fad9a596860f59d1c5d04a43dfb5f441dc71f57060dd0bf39483c833
CRANE_DEP=google/go-containerregistry

# vexctl merges several OpenVEX documents into one for the rescan's
# carry-forward (task 10.3); a bare binary like kind, version in the URL only.
VEXCTL_VER=0.4.4
VEXCTL_ASSET="vexctl-linux-amd64"
VEXCTL_URLDIR="openvex/vexctl/releases/download/v${VEXCTL_VER}"
VEXCTL_PIN=d315e2778af88b999ad4bba30a08aa2677ed701638e16c341b6d57b43c1e064d
VEXCTL_DEP=openvex/vexctl

DEFAULT_ARCH=x86_64
ARCH="$DEFAULT_ARCH"

KIND_MARKER="kind v${KIND_VER} (dhc-test-fixture)"
KYVERNO_MARKER="kyverno v${KYVERNO_VER} (dhc-test-fixture)"
HELM_MARKER="helm v${HELM_VER} (dhc-test-fixture)"
CT_MARKER="ct v${CT_VER} (dhc-test-fixture)"
SYFT_MARKER="syft v${SYFT_VER} (dhc-test-fixture)"
CRANE_MARKER="crane v${CRANE_VER} (dhc-test-fixture)"
VEXCTL_MARKER="vexctl v${VEXCTL_VER} (dhc-test-fixture)"

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
make_vexctl_asset() { # marker
  mkdir -p "$UP/$VEXCTL_URLDIR"
  printf '#!/bin/sh\necho "%s"\n' "$1" > "$UP/$VEXCTL_URLDIR/$VEXCTL_ASSET"
}
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

# helm nests its binary under linux-amd64/ — the member path, not the archive
# root, is what the script must extract.
make_helm_asset() { # marker
  local stage
  stage=$(mktemp -d "$SB/stage.XXXXXX")
  mkdir -p "$stage/linux-amd64"
  printf '#!/bin/sh\necho "%s"\n' "$1" > "$stage/linux-amd64/helm"
  chmod +x "$stage/linux-amd64/helm"
  printf 'Apache License 2.0\n' > "$stage/linux-amd64/LICENSE"
  mkdir -p "$UP"
  tar -czf "$UP/$HELM_ASSET" -C "$stage" linux-amd64
  rm -rf "$stage"
}
# ct's archive carries the binary plus the etc/ lint configs ct lint reads;
# both must come from the verified bytes, nothing else from the archive.
make_ct_asset() { # marker
  local stage
  stage=$(mktemp -d "$SB/stage.XXXXXX")
  printf '#!/bin/sh\necho "%s"\n' "$1" > "$stage/ct"
  chmod +x "$stage/ct"
  mkdir -p "$stage/etc"
  printf '# dhc-test-fixture lintconf\n' > "$stage/etc/lintconf.yaml"
  printf '# dhc-test-fixture chart schema\n' > "$stage/etc/chart_schema.yaml"
  printf 'Apache License 2.0\n' > "$stage/LICENSE"
  mkdir -p "$UP/$CT_URLDIR"
  tar -czf "$UP/$CT_URLDIR/$CT_ASSET" -C "$stage" ct etc LICENSE
  rm -rf "$stage"
}

make_syft_asset() { # marker
  local stage
  stage=$(mktemp -d "$SB/stage.XXXXXX")
  printf '#!/bin/sh\necho "%s"\n' "$1" > "$stage/syft"
  chmod +x "$stage/syft"
  printf 'Apache License 2.0\n' > "$stage/LICENSE"
  mkdir -p "$UP/$SYFT_URLDIR"
  tar -czf "$UP/$SYFT_URLDIR/$SYFT_ASSET" -C "$stage" syft LICENSE
  rm -rf "$stage"
}

make_crane_asset() { # marker
  local stage
  stage=$(mktemp -d "$SB/stage.XXXXXX")
  printf '#!/bin/sh\necho "%s"\n' "$1" > "$stage/crane"
  chmod +x "$stage/crane"
  printf 'Apache License 2.0\n' > "$stage/LICENSE"
  mkdir -p "$UP/$CRANE_URLDIR"
  tar -czf "$UP/$CRANE_URLDIR/$CRANE_ASSET" -C "$stage" crane LICENSE
  rm -rf "$stage"
}

setup() { # fresh sandbox: all assets served, empty destdir, shipped pins in force
  SB=$(mktemp -d)
  UP="$SB/upstream"
  DEST="$SB/bin"
  PINS=""
  ARCH="$DEFAULT_ARCH"
  mkdir -p "$DEST"
  make_kind_asset "$KIND_MARKER"
  make_kyverno_asset "$KYVERNO_MARKER"
  make_helm_asset "$HELM_MARKER"
  make_ct_asset "$CT_MARKER"
  make_syft_asset "$SYFT_MARKER"
  make_crane_asset "$CRANE_MARKER"
  make_vexctl_asset "$VEXCTL_MARKER"
}

write_pins() { # record the fixtures' real digests — the offline success path
  PINS="$SB/pins.sha256"
  : > "$PINS"
  (cd "$UP/$KIND_URLDIR" && sha256sum "$KIND_ASSET") >> "$PINS"
  (cd "$UP/$KYVERNO_URLDIR" && sha256sum "$KYVERNO_ASSET") >> "$PINS"
  (cd "$UP" && sha256sum "$HELM_ASSET") >> "$PINS"
  (cd "$UP/$CT_URLDIR" && sha256sum "$CT_ASSET") >> "$PINS"
  (cd "$UP/$SYFT_URLDIR" && sha256sum "$SYFT_ASSET") >> "$PINS"
  (cd "$UP/$CRANE_URLDIR" && sha256sum "$CRANE_ASSET") >> "$PINS"
  (cd "$UP/$VEXCTL_URLDIR" && sha256sum "$VEXCTL_ASSET") >> "$PINS"
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

setup; write_pins; invoke helm
assert_rc        "helm: matching checksum installs cleanly" 0
assert_installed "helm is installed and executable" helm
assert_payload   "installed helm is the nested member that was verified" helm "$HELM_MARKER"
assert_out       "reports the helm version it installed" "$HELM_VER"

# The nested linux-amd64/ scaffolding and licence stay out of the PATH dir.
stray=""
for f in "$DEST"/* "$DEST"/.[!.]*; do
  [ -e "$f" ] || continue
  case "${f##*/}" in helm) ;; *) stray="$stray ${f##*/}" ;; esac
done
if [ -z "$stray" ]; then pass "only the helm binary lands in destdir"
else fail "only the helm binary lands in destdir" "destdir also holds:$stray"; fi

setup; write_pins; invoke ct
assert_rc        "ct: matching checksum installs cleanly" 0
assert_installed "ct is installed and executable" ct
assert_payload   "installed ct is the archive that was verified" ct "$CT_MARKER"
assert_out       "reports the ct version it installed" "$CT_VER"
if [ -f "$DEST/ct-etc/lintconf.yaml" ] && [ -f "$DEST/ct-etc/chart_schema.yaml" ]; then
  pass "ct lint configs land in destdir/ct-etc from the verified archive"
else
  fail "ct lint configs land in destdir/ct-etc from the verified archive" \
       "missing under $DEST/ct-etc" "$OUT"
fi

# Beyond the binary and its configs, the archive contributes nothing to destdir.
stray=""
for f in "$DEST"/* "$DEST"/.[!.]*; do
  [ -e "$f" ] || continue
  case "${f##*/}" in ct | ct-etc) ;; *) stray="$stray ${f##*/}" ;; esac
done
if [ -z "$stray" ]; then pass "only ct and ct-etc land in destdir"
else fail "only ct and ct-etc land in destdir" "destdir also holds:$stray"; fi

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

setup; write_pins
make_helm_asset "PWNED-helm"
invoke helm
assert_rc     "a helm checksum mismatch fails" 1
assert_absent "the unverified helm is not installed" helm

setup; write_pins
make_ct_asset "PWNED-ct"
invoke ct
assert_rc     "a ct checksum mismatch fails" 1
assert_absent "the unverified ct is not installed" ct
if [ -e "$DEST/ct-etc" ]; then
  fail "no ct-etc appears for an unverified ct" "$DEST/ct-etc exists — configs from an unverified archive" "$OUT"
else pass "no ct-etc appears for an unverified ct"; fi

# --- 5: the shipped pins are live and are the documented ones ---------------

setup; invoke kind
assert_rc     "with no pin override the kind fixture is rejected" 1
assert_absent "nothing is installed when the shipped pin does not match" kind
assert_out    "the shipped kind pin is the documented digest" "$KIND_PIN"

setup; invoke kyverno
assert_rc     "with no pin override the kyverno fixture is rejected" 1
assert_absent "nothing is installed when the shipped pin does not match (kyverno)" kyverno
assert_out    "the shipped kyverno pin is the documented digest" "$KYVERNO_PIN"

setup; invoke helm
assert_rc     "with no pin override the helm fixture is rejected" 1
assert_absent "nothing is installed when the shipped pin does not match (helm)" helm
assert_out    "the shipped helm pin is the documented digest" "$HELM_PIN"

setup; invoke ct
assert_rc     "with no pin override the ct fixture is rejected" 1
assert_absent "nothing is installed when the shipped pin does not match (ct)" ct
assert_out    "the shipped ct pin is the documented digest" "$CT_PIN"

setup; invoke syft
assert_absent "nothing is installed when the shipped pin does not match (syft)" syft
assert_out    "the shipped syft pin is the documented digest" "$SYFT_PIN"

setup; invoke crane
assert_absent "nothing is installed when the shipped pin does not match (crane)" crane
assert_out    "the shipped crane pin is the documented digest" "$CRANE_PIN"

setup; invoke vexctl
assert_absent "nothing is installed when the shipped pin does not match (vexctl)" vexctl
assert_out    "the shipped vexctl pin is the documented digest" "$VEXCTL_PIN"

setup; write_pins; invoke vexctl
assert_rc        "vexctl: matching checksum installs cleanly" 0
assert_installed "vexctl is installed and executable" vexctl
assert_payload   "installed vexctl is the artifact that was verified" vexctl "$VEXCTL_MARKER"

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
assert_pin_block helm HELM "$HELM_DEP" "$HELM_VER" "$HELM_PIN"
assert_pin_block vexctl VEXCTL "$VEXCTL_DEP" "$VEXCTL_VER" "$VEXCTL_PIN"
assert_pin_block ct CT "$CT_DEP" "$CT_VER" "$CT_PIN"
assert_pin_block syft SYFT "$SYFT_DEP" "$SYFT_VER" "$SYFT_PIN"

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
