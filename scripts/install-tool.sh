#!/usr/bin/env bash
# install-tool.sh <kind|kyverno> [<destdir>]
#
# Install one workflow tool pinned to an exact version and verified against a
# sha256 recorded in this file (Req 7.5, docs/CONVENTIONS.md "Pinning").
# destdir defaults to /usr/local/bin; CI passes "${RUNNER_TEMP}/bin" and runs
# as the runner user — neither tool ever needed root.
#
# Sibling of scripts/install-scanners.sh, not a generalisation of it — that
# script's contract is "both scanners verified before either installs", and
# grafting single-tool selection onto it would rewrite a tested contract to
# save thirty lines of duplication. This one installs exactly one tool per
# invocation because each workflow needs exactly one: kind provisions the e2e
# cluster (e2e.yml), kyverno is the policy engine behind the Req 4.6 gate
# (chart.yml, validate.yml). Both run with the same runner privileges as the
# scanners, and a version pin alone does not survive re-publication of a tag
# we already adopted — CVE-2026-33634's shape (see install-scanners.sh).
#
# What it replaces: kyverno arrived by `curl … | tar -xz -C /usr/local/bin`
# — a pipe, so tar unpacks whatever a truncated or substituted body holds —
# and kind by curl + `sudo mv`, unverified. Fetch-to-file then sha256sum is
# the same discipline as install-scanners.sh, for the same reasons.
#
# The pin block is shaped for the Renovate custom manager in renovate.json5
# (Req 7.6): each `# renovate:` comment sits DIRECTLY above its `*_VERSION=`
# line, versions are bare (the URLs add the v), and Renovate bumps only the
# version — the sha256 stays behind, so a bump PR fails until a human records
# the new digest. That friction is the design, not a defect.
#
# Seams, all defaulted for CI (same shape as install-scanners.sh; the test
# suite cannot mint a fixture that hashes to a real release digest):
#   INSTALL_TOOL_BASE_URL   release host (default https://github.com)
#   INSTALL_TOOL_PINS       sha256sum(1)-format file replacing the digests below
#   INSTALL_TOOL_ARCH       architecture the pins are for (default uname -m)
set -euo pipefail

TOOL="${1:-}"
DEST_DIR="${2:-/usr/local/bin}"
BASE_URL="${INSTALL_TOOL_BASE_URL:-https://github.com}"
BASE_URL="${BASE_URL%/}"
PINS_FILE="${INSTALL_TOOL_PINS:-}"
ARCH="${INSTALL_TOOL_ARCH:-$(uname -m)}"

# renovate: datasource=github-releases depName=kubernetes-sigs/kind
KIND_VERSION="0.32.0"
KIND_SHA256="50030de23cf40a18505f20426f6a8506bedf13c6e509244bd1fa9463721b0f54"

# renovate: datasource=github-releases depName=kyverno/kyverno
KYVERNO_VERSION="1.18.2"
KYVERNO_SHA256="cb2feb8356149fd2fe774c894ccf0969f4a60a83867dd913af724f74ffbbc18b"

err() { printf '::error::install-tool: %s\n' "$1" >&2; }

# Both pinned assets are linux/amd64; on any other architecture the checksum
# verifies and the binary still cannot run (same refusal, same reason as
# install-scanners.sh).
case "$ARCH" in
  x86_64 | amd64) ;;
  *)
    err "architecture ${ARCH} is not supported — the pinned assets are linux/amd64 only"
    exit 1
    ;;
esac

# tarball=empty means the asset IS the binary, installed as fetched once
# verified; otherwise the named member is extracted and everything else in the
# archive stays out of the PATH directory.
case "$TOOL" in
  kind)
    version="$KIND_VERSION"
    shipped="$KIND_SHA256"
    asset="kind-linux-amd64"
    url="${BASE_URL}/kubernetes-sigs/kind/releases/download/v${KIND_VERSION}/${asset}"
    tarball=""
    ;;
  kyverno)
    version="$KYVERNO_VERSION"
    shipped="$KYVERNO_SHA256"
    asset="kyverno-cli_v${KYVERNO_VERSION}_linux_x86_64.tar.gz"
    url="${BASE_URL}/kyverno/kyverno/releases/download/v${KYVERNO_VERSION}/${asset}"
    tarball=yes
    ;;
  *)
    err "usage: install-tool.sh <kind|kyverno> [<destdir>] — got '${TOOL}'"
    exit 1
    ;;
esac

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

want="$shipped"
if [ -n "$PINS_FILE" ]; then
  # sha256sum(1) format, matched on the whole filename field (see
  # install-scanners.sh pinned_sha256 for why prefix matches are refused).
  want=$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1; exit }' "$PINS_FILE" 2>/dev/null || true)
fi
# No recorded digest is a refusal, never a skip.
if [ -z "$want" ]; then
  err "${TOOL}: no sha256 pinned for ${asset} — an artifact with nothing to compare against is unverified, not verified"
  exit 1
fi

# Fetch to a file, never a pipe: tar reading from curl unpacks whatever a
# truncated or substituted body holds, and a piped sha256sum hashes it and
# prints a confident, wrong digest.
if ! curl -fsSL --max-time 300 -o "$WORK/$asset" "$url"; then
  err "${TOOL}: could not fetch ${asset} from ${url}"
  exit 1
fi

got=$(sha256sum "$WORK/$asset" | cut -d' ' -f1)
if [ "$got" != "$want" ]; then
  err "${TOOL}: checksum MISMATCH for ${asset} — pinned ${want}, ${url} served ${got}"
  exit 1
fi

if [ -n "$tarball" ]; then
  if ! tar -xzf "$WORK/$asset" -C "$WORK" "$TOOL"; then
    err "${TOOL}: verified ${asset} holds no '${TOOL}' binary at its root"
    exit 1
  fi
else
  mv "$WORK/$asset" "$WORK/$TOOL"
fi

# The verified bytes overwrite whatever is already there — an earlier step's
# leftover binary is not a tool this script vouched for.
mkdir -p "$DEST_DIR"
install -m 0755 "$WORK/$TOOL" "$DEST_DIR/$TOOL"

echo "install-tool: ${TOOL} ${version} -> ${DEST_DIR}/${TOOL} (sha256 verified)"
