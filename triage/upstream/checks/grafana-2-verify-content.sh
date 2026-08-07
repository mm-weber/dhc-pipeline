#!/usr/bin/env bash
# STEP 2 — the actual proof. Downloads real tarballs, so budget ~1.5 GB of
# transfer and a few minutes.
#
# This is the measurement the original investigation got wrong. It used:
#
#     curl -sSL <url> | sha256sum          # <-- DO NOT DO THIS
#
# On a 322 MiB object with no --fail and no length check, a transfer that drops
# at 300 MiB still pipes 300 MiB into sha256sum, which prints a confident and
# completely wrong digest. Every "the alias serves different bytes" number came
# from that command, measured once.
#
# Here every download goes to a file, --fail turns HTTP errors into errors, the
# byte count is checked against Content-Length before the hash is trusted, and
# each URL is fetched PASSES times so a one-off is visibly a one-off.
#
# Usage:
#   ./grafana-2-verify-content.sh                 # 13.0.4, both arches, both paths
#   VERSIONS=13.1.1 ./grafana-2-verify-content.sh
#   PASSES=5 ./grafana-2-verify-content.sh
set -uo pipefail

VERSIONS=${VERSIONS:-"13.0.4"}
ARCHES=${ARCHES:-"amd64 arm64"}
PASSES=${PASSES:-3}
KEEP=${KEEP:-0}          # KEEP=1 keeps the tarballs for step 3
WORK=${WORK:-"$(mktemp -d -t grafana-verify-XXXXXX)"}

declare -A BUILD_ID=( [13.0.4]=29751385932 [13.1.1]=29761037902 )

# Portability: macOS has shasum, no sha256sum; GNU stat and BSD stat differ.
sha256_of() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1
              else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
size_of()   { wc -c < "$1" | tr -d ' '; }

url_for() {
  if [ "$3" = alias ]; then echo "https://dl.grafana.com/oss/release/grafana-$1.linux-$2.tar.gz"
  else echo "https://dl.grafana.com/grafana/release/$1/grafana_$1_${BUILD_ID[$1]}_linux_$2.tar.gz"; fi
}

echo "workdir: $WORK"
echo

for v in $VERSIONS; do
  for a in $ARCHES; do
    for k in alias perbuild; do
      u=$(url_for "$v" "$a" "$k")
      echo "=============================================================="
      echo "$v $a $k"
      echo "  $u"

      sidecar=$(curl -fsSL --max-time 30 "$u.sha256" 2>/dev/null | awk '{print $1}')
      echo "  sidecar says: ${sidecar:-<could not fetch>}"

      expect=$(curl -sSI -L --max-time 30 "$u" 2>/dev/null \
               | grep -i '^content-length:' | tail -1 | tr -d '\r' | awk '{print $2}')
      echo "  content-length: ${expect:-<unknown>}"

      for i in $(seq 1 "$PASSES"); do
        f="$WORK/$v.$a.$k.tgz"
        if ! curl -fSL --max-time 1800 --speed-limit 1024 --speed-time 60 -o "$f" "$u" 2>"$WORK/err"; then
          echo "  pass $i: TRANSFER FAILED ($(tr -d '\n' < "$WORK/err"))"
          echo "           ^ the old repro would have silently hashed this"
          continue
        fi
        got_size=$(size_of "$f")
        if [ -n "$expect" ] && [ "$got_size" != "$expect" ]; then
          echo "  pass $i: SHORT READ — got $got_size, expected $expect. Hash not trustworthy."
          continue
        fi
        got=$(sha256_of "$f")
        if [ -n "$sidecar" ] && [ "$got" = "$sidecar" ]; then verdict="matches its sidecar"
        elif [ -n "$sidecar" ];                          then verdict=">>> CONTRADICTS ITS SIDECAR <<<"
        else                                                  verdict="(no sidecar to compare)"
        fi
        echo "  pass $i: $got  ($got_size bytes)  $verdict"
      done
      [ "$KEEP" = 1 ] || rm -f "$WORK/$v.$a.$k.tgz"
    done
  done
done

echo
echo "=============================================================="
echo "Reading the result:"
echo
echo "  All passes identical, matching sidecar   -> that path is healthy."
echo "  All passes identical, CONTRADICTS sidecar-> object was replaced and the"
echo "                                              sidecar was not regenerated."
echo "                                              This is the reportable bug."
echo "  Passes DIFFER from each other            -> not a stale sidecar; either"
echo "                                              a live rewrite or a flaky"
echo "                                              transfer. Re-run with PASSES=10."
echo "  alias hash == perbuild hash              -> the two paths are the same"
echo "                                              bytes; the 'two artifacts'"
echo "                                              theory is dead."
echo
[ "$KEEP" = 1 ] && echo "tarballs kept in $WORK — run grafana-3-compare-contents.sh next"
echo "delete when done: rm -rf $WORK"
