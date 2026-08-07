#!/usr/bin/env bash
# STEP 3 — only worth running if step 2 showed the two paths hashing
# differently. Answers: are they different BUILDS of the same thing, or just
# different packaging of identical files?
#
# This matters because we re-pinned the image definition from the alias path to
# the per-build path. If the two contain a different grafana binary, that change
# altered what we ship. If they differ only in tar/gzip framing, it did not.
#
# Run step 2 with KEEP=1 first, then point this at that workdir:
#   KEEP=1 VERSIONS=13.1.1 ARCHES=amd64 ./grafana-2-verify-content.sh
#   WORK=/tmp/grafana-verify-XXXX ./grafana-3-compare-contents.sh
set -uo pipefail

WORK=${WORK:?set WORK to the directory step 2 printed (run it with KEEP=1)}
VER=${VER:-13.1.1}
ARCH=${ARCH:-amd64}

A="$WORK/$VER.$ARCH.alias.tgz"
B="$WORK/$VER.$ARCH.perbuild.tgz"
for f in "$A" "$B"; do
  [ -s "$f" ] || { echo "missing $f — re-run step 2 with KEEP=1"; exit 1; }
done

sha256_of() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1
              else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

rm -rf "$WORK/xA" "$WORK/xB"; mkdir -p "$WORK/xA" "$WORK/xB"
tar -xzf "$A" --strip-components=1 -C "$WORK/xA"
tar -xzf "$B" --strip-components=1 -C "$WORK/xB"

echo "=== file lists ==============================================="
if diff <(cd "$WORK/xA" && find . -type f | sort) \
        <(cd "$WORK/xB" && find . -type f | sort) > "$WORK/listdiff"; then
  echo "  identical file lists"
else
  echo "  DIFFERENT file lists:"; sed 's/^/    /' "$WORK/listdiff" | head -40
fi

echo
echo "=== the binary that actually matters ========================="
for side in xA:alias xB:perbuild; do
  d="$WORK/${side%%:*}"; label="${side##*:}"
  bin="$d/bin/grafana"
  if [ -f "$bin" ]; then
    printf '  %-9s bin/grafana  %s  (%s bytes)\n' "$label" "$(sha256_of "$bin")" "$(wc -c < "$bin" | tr -d ' ')"
  else
    printf '  %-9s bin/grafana  <missing>\n' "$label"
  fi
  printf '  %-9s VERSION      %s\n' "$label" "$(cat "$d/VERSION" 2>/dev/null || echo n/a)"
  # Grafana ships OSS and Enterprise builds. If one path carried the
  # enterprise-capable build, "drift" would be the wrong word entirely.
  printf '  %-9s enterprise refs in binary: %s\n' "$label" \
    "$(strings "$bin" 2>/dev/null | grep -c 'grafana-enterprise' || echo 0)"
done

echo
echo "=== verdict =================================================="
if cmp -s "$WORK/xA/bin/grafana" "$WORK/xB/bin/grafana"; then
  echo "  IDENTICAL grafana binaries."
  echo "  The two tarballs differ only in packaging (tar mtimes, gzip framing,"
  echo "  file ordering). Nothing about what we ship changed when we re-pinned."
else
  echo "  DIFFERENT grafana binaries — these are genuinely different builds."
  echo "  Re-pinning changed the bytes we ship. Worth stating explicitly in the"
  echo "  definition comment and in the upstream report."
fi

echo
echo "  (optional, needs Go installed — shows toolchain + module set per side)"
echo "    go version -m $WORK/xA/bin/grafana | head -5"
echo "    go version -m $WORK/xB/bin/grafana | head -5"
