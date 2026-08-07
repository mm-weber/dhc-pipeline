#!/usr/bin/env bash
# STEP 1 — takes ~10 seconds, downloads nothing large.
#
# Answers three questions without touching a 322 MiB object:
#   * what do the .sha256 sidecars say TODAY, on both paths and both arches?
#   * do the two paths report the same size? (different size => different bytes,
#     settled without downloading either)
#   * does the alias redirect to the per-build object? (if it does, the whole
#     "two paths" question dissolves)
#
# It also compares everything against the values our CI recorded, so a drift
# shows up as a line marked CHANGED rather than a number you have to eyeball.
#
# Usage:  ./grafana-1-quick-check.sh
set -uo pipefail

VERSIONS=${VERSIONS:-"13.0.4 13.1.1"}
ARCHES=${ARCHES:-"amd64 arm64"}

# Build ids taken from the GitHub release asset names (verified in step 0 below).
declare -A BUILD_ID=( [13.0.4]=29751385932 [13.1.1]=29761037902 )

# What we recorded, and where it came from. Anything differing from these is
# news; anything matching confirms the record.
declare -A RECORDED=(
  # 13.0.4 alias — verified OK by CI on 2026-07-21, FAILED 2026-07-26 (amd64)
  [13.0.4:amd64:alias]=cd8c8b31b0482f48f98018030c142919dab6debbe81f747f3521af6f6a6b4490
  [13.0.4:arm64:alias]=bcf8b9fbfac00bece5bccdda44512b9f7ba81d3105db1a255e0efd37a2fbf6df
  # 13.1.1 — our current pins are the per-build values
  [13.1.1:amd64:alias]=0c07116968aea49768af8babd3c3f162d19012655a1a220cd7a9d97efe91da6c
  [13.1.1:amd64:perbuild]=e47443214da0de041ffb29633d0977ce31ba7c8c569f09974ef5294a8ce32f08
  [13.1.1:arm64:perbuild]=28ef74a3bd01fec42fc78b1b9583809f35035654adcbf333c5bba440f418c07d
)

url_for() { # version arch kind
  if [ "$3" = alias ]; then
    echo "https://dl.grafana.com/oss/release/grafana-$1.linux-$2.tar.gz"
  else
    echo "https://dl.grafana.com/grafana/release/$1/grafana_$1_${BUILD_ID[$1]}_linux_$2.tar.gz"
  fi
}

echo "=== 0. build ids, straight from the GitHub release ============================"
echo "(if these disagree with the table above, fix BUILD_ID before trusting anything)"
for v in $VERSIONS; do
  ids=$(curl -fsSL "https://api.github.com/repos/grafana/grafana/releases/tags/v$v" 2>/dev/null \
        | grep -oE "grafana_${v//./\\.}_[0-9]+_linux_amd64\.deb" | head -1 \
        | sed -E 's/.*_([0-9]+)_linux.*/\1/')
  printf '  v%-8s github=%-14s ours=%s  %s\n' "$v" "${ids:-<none>}" "${BUILD_ID[$v]}" \
    "$([ "$ids" = "${BUILD_ID[$v]}" ] && echo MATCH || echo '<-- CHECK')"
done

echo
echo "=== 1. what the .sha256 sidecars say right now ================================="
printf '  %-8s %-6s %-9s %-64s %s\n' VER ARCH PATH SHA256 'VS RECORD'
for v in $VERSIONS; do
  for a in $ARCHES; do
    for k in alias perbuild; do
      u=$(url_for "$v" "$a" "$k")
      s=$(curl -fsSL --max-time 30 "$u.sha256" 2>/dev/null | awk '{print $1}')
      rec="${RECORDED[$v:$a:$k]:-}"
      if   [ -z "$s" ];            then note="fetch failed"
      elif [ -z "$rec" ];          then note="(no record)"
      elif [ "$s" = "$rec" ];      then note="same"
      else                              note="CHANGED (was ${rec:0:8}…)"
      fi
      printf '  %-8s %-6s %-9s %-64s %s\n' "$v" "$a" "$k" "${s:-<none>}" "$note"
    done
  done
done

echo
echo "=== 2. size, redirects, object age ============================================="
echo "(same content-length on both paths is weak evidence of same bytes;"
echo " different content-length is STRONG evidence of different bytes)"
for v in $VERSIONS; do
  for a in $ARCHES; do
    for k in alias perbuild; do
      u=$(url_for "$v" "$a" "$k")
      hdr=$(curl -sSI -L --max-time 30 "$u" 2>/dev/null)
      eff=$(curl -sS -o /dev/null -I -L --max-time 30 -w '%{url_effective}|%{num_redirects}' "$u" 2>/dev/null)
      len=$(grep -i '^content-length:' <<<"$hdr" | tail -1 | tr -d '\r' | awk '{print $2}')
      lm=$(grep -i '^last-modified:'   <<<"$hdr" | tail -1 | tr -d '\r' | cut -d' ' -f2-)
      gen=$(grep -i '^x-goog-generation:' <<<"$hdr" | tail -1 | tr -d '\r' | awk '{print $2}')
      printf '  %-8s %-6s %-9s len=%-12s redirects=%s\n' "$v" "$a" "$k" "${len:-?}" "${eff##*|}"
      printf '  %-8s %-6s %-9s object   last-modified=%s\n' '' '' '' "${lm:-?}"
      [ -n "$gen" ] && printf '  %-8s %-6s %-9s object   x-goog-generation=%s\n' '' '' '' "$gen"

      # The decisive pair. If the sidecar was written seconds after the object,
      # they were published together and there was never a moment when upstream
      # served content contradicting its own checksum — the object simply MOVED.
      # A sidecar written much later means it really was stale for a window.
      shdr=$(curl -sSI -L --max-time 30 "$u.sha256" 2>/dev/null)
      slm=$(grep -i '^last-modified:'      <<<"$shdr" | tail -1 | tr -d '\r' | cut -d' ' -f2-)
      sgen=$(grep -i '^x-goog-generation:' <<<"$shdr" | tail -1 | tr -d '\r' | awk '{print $2}')
      printf '  %-8s %-6s %-9s sidecar  last-modified=%s\n' '' '' '' "${slm:-?}"
      [ -n "$sgen" ] && printf '  %-8s %-6s %-9s sidecar  x-goog-generation=%s\n' '' '' '' "$sgen"
      if [ -n "$gen" ] && [ -n "$sgen" ]; then
        printf '  %-8s %-6s %-9s written %s seconds apart\n' '' '' '' \
          "$(( (sgen - gen) / 1000000 ))"
      fi
    done
  done
done

echo
echo "How to read this:"
echo "  * sidecar CHANGED on a path we pinned  -> upstream moved that object"
echo "  * alias and perbuild same content-length -> likely same bytes; step 2 confirms"
echo "  * redirects > 0 on the alias           -> it points at the per-build object"
echo "  * x-goog-generation is a microsecond timestamp of when the object was WRITTEN"
echo "  * object vs sidecar 'seconds apart':"
echo "      a few seconds -> published together; upstream never contradicted itself,"
echo "                       the object was simply overwritten at some later date"
echo "      hours or days -> the sidecar really was stale for that window"
echo
echo "NOTE: the VS RECORD column compares against values captured 2026-07-21..26."
echo "      For 13.0.4 those are the PRE-rewrite alias digests, so 'CHANGED' there"
echo "      is the expected, already-understood finding — not new news."
echo
echo "Next: ./grafana-2-verify-content.sh   (downloads and hashes; this is the proof)"
