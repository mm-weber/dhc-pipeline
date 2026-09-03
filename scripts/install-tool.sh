#!/usr/bin/env bash
# install-tool.sh <kind|kyverno|helm|ct|syft|crane> [<destdir>]
#
# Install one workflow tool pinned to an exact version and verified against a
# sha256 recorded in this file (Req 7.5, docs/CONVENTIONS.md "Pinning").
# destdir defaults to /usr/local/bin; CI passes "${RUNNER_TEMP}/bin" and runs
# as the runner user — none of these tools ever needed root.
#
# Sibling of scripts/install-scanners.sh, not a generalisation of it — that
# script's contract is "both scanners verified before either installs", and
# grafting single-tool selection onto it would rewrite a tested contract to
# save thirty lines of duplication. This one installs exactly one tool per
# invocation: kind provisions the e2e cluster (e2e.yml), kyverno is the
# policy engine behind the Req 4.6 gate (chart.yml, validate.yml), helm
# renders and installs the charts (chart.yml, e2e.yml), ct lints the owned
# charts (chart.yml). All run with the same runner privileges as the
# scanners, and a version pin alone does not survive re-publication of a tag
# we already adopted — CVE-2026-33634's shape (see install-scanners.sh).
#
# What it replaces: kyverno arrived by `curl … | tar -xz -C /usr/local/bin`
# — a pipe, so tar unpacks whatever a truncated or substituted body holds —
# and kind by curl + `sudo mv`, unverified. helm and ct arrived through
# azure/setup-helm (no version input — whatever upstream's latest was that
# day) and chart-testing-action (version-pinned, checksum-unverified), issue
# #74. Fetch-to-file then sha256sum is the same discipline as
# install-scanners.sh, for the same reasons.
#
# helm's binaries are served from get.helm.sh, not the GitHub release (which
# carries source archives only); its pinned sha256 is the one the helm
# project publishes in the release notes and the .sha256sum sidecar beside
# the tarball. ct's archive also carries etc/lintconf.yaml and
# etc/chart_schema.yaml, which `ct lint` needs at runtime: they are installed
# from the same verified bytes into <destdir>/ct-etc/, and chart.yml points
# ct at them explicitly.
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

# renovate: datasource=github-releases depName=helm/helm
HELM_VERSION="4.2.4"
HELM_SHA256="c306b46f719b0a4da32d0f78ee21bf90ce8d602f15b22ab753f0674d1670a7f3"

# renovate: datasource=github-releases depName=helm/chart-testing
CT_VERSION="3.14.0"
CT_SHA256="d16f0583616885423826241164ce1f6589c6fe5332fa74f374ebd2bd3cb3fe1f"

# renovate: datasource=github-releases depName=anchore/syft
SYFT_VERSION="1.51.1"
SYFT_SHA256="8fcb33017a0dc1058298c923c436d19dfa68ae93968e0b423248542e3afb9fc3"

# renovate: datasource=github-releases depName=google/go-containerregistry
CRANE_VERSION="0.22.0"
CRANE_SHA256="edb74d53fad9a596860f59d1c5d04a43dfb5f441dc71f57060dd0bf39483c833"

# renovate: datasource=github-releases depName=openvex/vexctl
VEXCTL_VERSION="0.4.4"
VEXCTL_SHA256="d315e2778af88b999ad4bba30a08aa2677ed701638e16c341b6d57b43c1e064d"

err() { printf '::error::install-tool: %s\n' "$1" >&2; }

# All pinned assets are linux/amd64; on any other architecture the checksum
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
# verified; otherwise the member named by `member` (default: the tool's own
# name at the archive root) is extracted, plus any `extras` — non-binary
# files the tool needs at runtime, installed 0644 under <destdir>/<tool>-etc/
# — and everything else in the archive stays out of the PATH directory.
case "$TOOL" in
  kind)
    version="$KIND_VERSION"
    shipped="$KIND_SHA256"
    asset="kind-linux-amd64"
    url="${BASE_URL}/kubernetes-sigs/kind/releases/download/v${KIND_VERSION}/${asset}"
    tarball=""
    member=""
    extras=""
    ;;
  kyverno)
    version="$KYVERNO_VERSION"
    shipped="$KYVERNO_SHA256"
    asset="kyverno-cli_v${KYVERNO_VERSION}_linux_x86_64.tar.gz"
    url="${BASE_URL}/kyverno/kyverno/releases/download/v${KYVERNO_VERSION}/${asset}"
    tarball=yes
    member=""
    extras=""
    ;;
  helm)
    version="$HELM_VERSION"
    shipped="$HELM_SHA256"
    asset="helm-v${HELM_VERSION}-linux-amd64.tar.gz"
    # get.helm.sh serves from its root — the seam replaces the whole host.
    helm_base="${INSTALL_TOOL_BASE_URL:-https://get.helm.sh}"
    url="${helm_base%/}/${asset}"
    tarball=yes
    member="linux-amd64/helm"
    extras=""
    ;;
  ct)
    version="$CT_VERSION"
    shipped="$CT_SHA256"
    asset="chart-testing_${CT_VERSION}_linux_amd64.tar.gz"
    url="${BASE_URL}/helm/chart-testing/releases/download/v${CT_VERSION}/${asset}"
    tarball=yes
    member=""
    extras="etc/lintconf.yaml etc/chart_schema.yaml"
    ;;
  syft)
    version="$SYFT_VERSION"
    shipped="$SYFT_SHA256"
    asset="syft_${SYFT_VERSION}_linux_amd64.tar.gz"
    url="${BASE_URL}/anchore/syft/releases/download/v${SYFT_VERSION}/${asset}"
    tarball=yes
    member=""
    extras=""
    ;;
  crane)
    # Lists registry tags for the rescan enumeration (Req 2.22, task 9.3).
    # The one asset here whose filename carries no version — only the URL
    # path does, so a Renovate bump still changes the fetched bytes.
    version="$CRANE_VERSION"
    shipped="$CRANE_SHA256"
    asset="go-containerregistry_Linux_x86_64.tar.gz"
    url="${BASE_URL}/google/go-containerregistry/releases/download/v${CRANE_VERSION}/${asset}"
    tarball=yes
    member=""
    extras=""
    ;;
  vexctl)
    # Merges several OpenVEX documents into one, field-preserving (ADR 0003's
    # measurement): the rescan's carry-forward input when a digest still
    # carries more than one OpenVEX attestation (task 10.3, Req 6.43).
    version="$VEXCTL_VERSION"
    shipped="$VEXCTL_SHA256"
    asset="vexctl-linux-amd64"
    url="${BASE_URL}/openvex/vexctl/releases/download/v${VEXCTL_VERSION}/${asset}"
    tarball=""
    member=""
    extras=""
    ;;
  *)
    err "usage: install-tool.sh <kind|kyverno|helm|ct|syft|crane|vexctl> [<destdir>], got '${TOOL}'"
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
  member="${member:-$TOOL}"
  # $extras unquoted on purpose: a space-separated list of member paths.
  # shellcheck disable=SC2086
  if ! tar -xzf "$WORK/$asset" -C "$WORK" "$member" $extras; then
    err "${TOOL}: verified ${asset} does not hold '${member}'${extras:+ (+ ${extras})}"
    exit 1
  fi
else
  mv "$WORK/$asset" "$WORK/$TOOL"
  member="$TOOL"
fi

# The verified bytes overwrite whatever is already there — an earlier step's
# leftover binary is not a tool this script vouched for.
mkdir -p "$DEST_DIR"
install -m 0755 "$WORK/$member" "$DEST_DIR/$TOOL"
if [ -n "$extras" ]; then
  mkdir -p "$DEST_DIR/${TOOL}-etc"
  for x in $extras; do
    install -m 0644 "$WORK/$x" "$DEST_DIR/${TOOL}-etc/${x##*/}"
  done
fi

echo "install-tool: ${TOOL} ${version} -> ${DEST_DIR}/${TOOL} (sha256 verified)"
