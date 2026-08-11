#!/usr/bin/env bash
# install-scanners.sh [<destdir>]
#
# Install the two CVE scanners this repo's gate runs on — trivy and grype —
# pinned to an exact version and verified against a checksum recorded in this
# file (Req 7.5, docs/CONVENTIONS.md "Pinning"). destdir defaults to
# /usr/local/bin, so build.yml and rescan.yml can call it with no arguments.
#
# Why this exists. It replaces
#
#     curl -fsSL https://raw.githubusercontent.com/…/main/contrib/install.sh | sudo sh
#
# — an unpinned script off a mutable branch, piped into a root shell, on a
# runner holding registry tokens and cosign signing permissions. CVE-2026-33634
# / GHSA-69fq-xp46-6x23 (March 2026) is the price of that: a malicious trivy
# release published, 76 of 77 `aquasecurity/trivy-action` tags force-pushed to a
# credential stealer. Note what a version pin alone would NOT have caught —
# that attack re-published bytes under versions already adopted. The sha256 is
# the control; the version is only how the bytes are addressed.
#
# Caveat, stated rather than buried: INSTALL_SCANNERS_PINS and
# INSTALL_SCANNERS_BASE_URL exist so the test suite can exercise the success
# path offline — no fixture can ever hash to a real release digest. They are
# seams for testing, not knobs for operators, and they mean this control is
# only as strong as the environment it runs in. That costs nothing here:
# setting either in CI requires write access to the workflow, and anyone with
# that could edit this file instead. Neither is set in build.yml or rescan.yml,
# and the shipped pins are exercised with no override at all.
#
# Pinning a scanner is only safe if something bumps it, because a stale scanner
# reports clean and says nothing while it does. The pin block below is shaped
# for the Renovate custom manager in renovate.json5 (Req 7.6): each
# `# renovate:` comment must stay on the line DIRECTLY above its `*_VERSION=`,
# because Renovate binds it positionally — one blank line in between and the
# manager matches nothing, with no error.
#
# Nothing is installed until both artifacts have been fetched and verified. A
# half-done install is worse than no install: the next step finds trivy on PATH
# and reads that as success.
#
# Seams, all defaulted for CI:
#   INSTALL_SCANNERS_BASE_URL   release host (default https://github.com)
#   INSTALL_SCANNERS_PINS       sha256sum(1)-format file replacing the digests
#                               below (used by the test suite, which cannot make
#                               a fixture that hashes to a real release)
#   INSTALL_SCANNERS_ARCH       architecture the pins are for (default uname -m)
set -euo pipefail

DEST_DIR="${1:-/usr/local/bin}"
BASE_URL="${INSTALL_SCANNERS_BASE_URL:-https://github.com}"
BASE_URL="${BASE_URL%/}"
PINS_FILE="${INSTALL_SCANNERS_PINS:-}"
ARCH="${INSTALL_SCANNERS_ARCH:-$(uname -m)}"

# renovate: datasource=github-releases depName=aquasecurity/trivy
TRIVY_VERSION="0.73.0"
TRIVY_SHA256="bbb64b9695866ce4a7a8f5c9592002c5961cab378577fa3f8a040df362b9b2ea"

# renovate: datasource=github-releases depName=anchore/grype
GRYPE_VERSION="0.117.0"
GRYPE_SHA256="38525dab1e06f162ebaa02f94d82d1f807076b011a44180cf2777edf1a7b9c26"

err() { printf '::error::install-scanners: %s\n' "$1" >&2; }

# Both pinned assets are linux/amd64, and the digests above are digests of those
# bytes. On any other architecture every checksum verifies perfectly and the
# binary still cannot run, so refusing here is the only honest outcome — the
# alternative is "cannot execute binary file" hundreds of log lines later, in
# whichever step first calls a scanner.
case "$ARCH" in
  x86_64 | amd64) ;;
  *)
    err "architecture ${ARCH} is not supported — the pinned trivy and grype assets are linux/amd64 only, and a checksum that matches on ${ARCH} still leaves an unrunnable binary"
    exit 1
    ;;
esac

trivy_asset="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
trivy_url="${BASE_URL}/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/${trivy_asset}"
grype_asset="grype_${GRYPE_VERSION}_linux_amd64.tar.gz"
grype_url="${BASE_URL}/anchore/grype/releases/download/v${GRYPE_VERSION}/${grype_asset}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/staged"
mkdir -p "$STAGE"

pinned_sha256() { # asset, shipped-digest -> digest on stdout, 1 if none recorded
  local asset="$1" want="$2"
  if [ -n "$PINS_FILE" ]; then
    # sha256sum(1) format: "<digest>  <filename>". Matched on the whole second
    # field so one asset's name cannot answer for another's by prefix.
    want=$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1; exit }' "$PINS_FILE" 2>/dev/null || true)
  fi
  # No recorded digest is a refusal, never a skip: comparing a computed digest
  # against an empty expected value is the silent pass this script exists to
  # remove.
  [ -n "$want" ] || return 1
  printf '%s\n' "$want"
}

stage() { # tool, asset, url, shipped-digest — verified binary into $STAGE, 1 on refusal
  local tool="$1" asset="$2" url="$3" shipped="$4"
  local tarball="$WORK/$asset" want got

  if ! want=$(pinned_sha256 "$asset" "$shipped"); then
    err "${tool}: no sha256 pinned for ${asset} — an artifact with nothing to compare against is unverified, not verified"
    return 1
  fi

  # Fetch to a file, never a pipe: `curl … | sha256sum` will hash a truncated
  # body and print a confident, wrong digest. -f makes an HTTP error an error
  # instead of a hashed error page.
  if ! curl -fsSL --max-time 300 -o "$tarball" "$url"; then
    err "${tool}: could not fetch ${asset} from ${url}"
    return 1
  fi

  got=$(sha256sum "$tarball" | cut -d' ' -f1)
  if [ "$got" != "$want" ]; then
    # Both digests, always. "Checksum mismatch" on its own sends the reader
    # looking in the wrong place.
    err "${tool}: checksum MISMATCH for ${asset} — pinned ${want}, ${url} served ${got}"
    return 1
  fi

  # Only the binary comes out of the archive. destdir is a PATH directory, and
  # the licence and readme both releases ship have no business in one.
  if ! tar -xzf "$tarball" -C "$STAGE" "$tool"; then
    err "${tool}: verified ${asset} holds no '${tool}' binary at its root"
    return 1
  fi
}

# Both tools are staged before either is installed, and neither refusal exits
# early: fixing pins one failure at a time is how the second one gets missed
# (same rule as verify-arch-pins.sh).
rc=0
stage trivy "$trivy_asset" "$trivy_url" "$TRIVY_SHA256" || rc=1
stage grype "$grype_asset" "$grype_url" "$GRYPE_SHA256" || rc=1
if [ "$rc" -ne 0 ]; then
  err "no scanner was installed — a partial install is a scanner on PATH that nothing vouched for"
  exit 1
fi

# mkdir rather than `install -d`: an argument destdir may not exist yet, and the
# default one does and is not ours to re-chmod. The pinned bytes overwrite
# whatever is already there — an earlier step's leftover binary is not a scanner
# this script verified.
mkdir -p "$DEST_DIR"
install -m 0755 "$STAGE/trivy" "$DEST_DIR/trivy"
install -m 0755 "$STAGE/grype" "$DEST_DIR/grype"

echo "install-scanners: trivy ${TRIVY_VERSION} -> ${DEST_DIR}/trivy (sha256 verified)"
echo "install-scanners: grype ${GRYPE_VERSION} -> ${DEST_DIR}/grype (sha256 verified)"
