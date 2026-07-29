#!/usr/bin/env bash
# verify-arch-pins.sh <definition-dir>
#
# Verify that EVERY per-arch pinned checksum in a definition matches the bytes
# upstream actually serves at the pinned url.
#
# Why this exists, and why it is not the build's job. The build already verifies
# the checksum — but only for the arch it is building, and the PR gate builds
# amd64 only (build.yml: `load:` needs a single platform for the scan gate). So
# an arm64 pin could enter the repo, pass every check, and only be exercised by
# a release build after merge. That is exactly what happened with grafana
# 13.1.1: both arch pins were supplied by hand via REFRESH_GRAFANA_SHA256_*
# and no machine ever fetched the arm64 tarball they claimed to describe.
#
# A pin nobody exercised is not a pin. This closes that gap without qemu and
# without building an image, so it costs one download per arch.
#
# Definitions that pin nothing per arch (built from source, single artifact)
# are skipped, not failed.
set -euo pipefail

dir="${1:?usage: verify-arch-pins.sh <definition-dir>}"
dir="${dir%/}"
f="$dir/image.yaml"
name=$(basename "$dir")
[ -f "$f" ] || { echo "verify-arch-pins: no image.yaml in $dir" >&2; exit 1; }

# The catalog's per-arch idiom, both halves of it:
#
#   url:  https://…/pkg_${target.arch}.tar.gz
#   VAR:  '#{ target.arch == "amd64" ? "<64hex>" : "<64hex>" }'
#
# Both must be present for there to be anything to verify. Anchored on the
# `url:` key so a comment mentioning the same host cannot match.
# shellcheck disable=SC2016  # ${target.arch} is a literal the frontend expands, not ours
url_tmpl=$(sed -nE 's#^[[:space:]]*-?[[:space:]]*url:[[:space:]]*([a-zA-Z][a-zA-Z0-9+.-]*://[^[:space:]"'"'"']+).*#\1#p' "$f" \
           | grep -F '${target.arch}' | head -1 || true)
pins=$(sed -nE 's/.*target\.arch[[:space:]]*==[[:space:]]*"amd64"[[:space:]]*\?[[:space:]]*"([0-9a-f]{64})"[[:space:]]*:[[:space:]]*"([0-9a-f]{64})".*/\1 \2/p' "$f" \
       | head -1 || true)

if [ -z "$url_tmpl" ] || [ -z "$pins" ]; then
  echo "verify-arch-pins: ${name}: no per-arch pinned artifact — nothing to verify"
  exit 0
fi

# Read back indirectly as sha_<arch> in the loop below.
# shellcheck disable=SC2034
sha_amd64=${pins%% *}
# shellcheck disable=SC2034
sha_arm64=${pins##* }

# Fetch to a file, never a pipe. `curl … | sha256sum` on a large artifact will
# happily hash a truncated body and print a confident, wrong digest — the
# measurement error that cost this repo three wrong diagnoses. -f makes an HTTP
# error an error instead of a hashed error page.
fetch_sha() { # url -> 64-hex on stdout, non-zero on any fetch problem
  local url="$1" tmp rc
  tmp=$(mktemp)
  if curl -fsSL --max-time 900 -o "$tmp" "$url"; then
    sha256sum "$tmp" | cut -d' ' -f1
    rc=0
  else
    rc=1
  fi
  rm -f "$tmp"
  return "$rc"
}

echo "verify-arch-pins: ${name}"
rc=0
for arch in amd64 arm64; do
  url="${url_tmpl//\$\{target.arch\}/$arch}"
  want_var="sha_${arch}"
  want="${!want_var}"

  if ! got=$(fetch_sha "$url"); then
    echo "::error file=${f}::${name}: could not fetch ${arch} artifact — ${url}"
    rc=1
    continue
  fi

  if [ "$got" = "$want" ]; then
    echo "  ${arch} OK  ${want}  ${url}"
  else
    # Both numbers, always. "Checksum mismatch" without them is the message
    # that sent us looking in the wrong place for a week.
    echo "::error file=${f}::${name}: ${arch} MISMATCH — pinned ${want}, upstream served ${got} at ${url}"
    rc=1
  fi
done

exit "$rc"
