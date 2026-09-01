#!/usr/bin/env bash
# scan-image.sh <ref> <definition> <vex-dir> <out-json> [--remote] [--platform P]
#
# The one scan both arms run (task 9.1). The pull request gate and the
# release-time scan of the pushed digest must apply the same inputs, or the
# gate stops predicting what release does; two copies of a long trivy
# invocation drift on the first flag either one gains, and the drift is
# invisible (a scan missing --vex reports findings that are covered, a scan
# missing --ignorefile fails on accepted risk, and both look like real results).
#
# Two suppression inputs, deliberately different in kind:
#
#   --vex         applicability claims, compiled for this digest: the
#                 vulnerable code cannot execute here. Evidence-backed,
#                 published with the image, no expiry.
#   --ignorefile  risk decisions: it is real and we ship anyway, for a bounded
#                 time. Internal, expires (Req 6.9), and cluster B publishes it
#                 as an `affected` statement rather than hiding it.
#
# --show-suppressed keeps what was suppressed in the report (Req 6.55) so a
# statement that silently matched nothing is distinguishable from one that
# worked, and so both arms attest reports of one shape. --exit-code 0 keeps the
# decision with the caller: the gate counts, the release arm compiles
# under_investigation statements (Req 2.12), and neither wants trivy's verdict.
#
# Refuses rather than returning a half result: a failed scan or a missing
# report is what Req 2.26 turns into "sign nothing, tag nothing".
set -euo pipefail

if [ "$#" -lt 4 ]; then
  echo "usage: scan-image.sh <ref> <definition> <vex-dir> <out-json> [--remote] [--platform P]" >&2
  exit 2
fi
REF="$1"; DEFINITION="$2"; VEXDIR="$3"; OUT="$4"; shift 4

REMOTE=""
PLATFORM=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --remote) REMOTE=1; shift ;;
    --platform) PLATFORM="${2:?--platform needs a value}"; shift 2 ;;
    *) echo "scan-image: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

args=()
# One --vex per compiled document. An empty directory is a legitimate state
# (ADR 0003: a digest can have nothing to say) and must still scan.
shopt -s nullglob
for f in "$VEXDIR"/*.json; do args+=(--vex "$f"); done
shopt -u nullglob

accepted="triage/accepted-risk/${DEFINITION}.yaml"
[ -f "$accepted" ] && args+=(--ignorefile "$accepted")

# A pushed digest is read from the registry, one platform manifest at a time.
# Measured (task 8.3): --platform without --image-src remote is silently
# ignored, and trivy then scans whatever the runner's own architecture
# resolves to, which is how an arm64 manifest went unscanned while looking
# scanned.
[ -n "$REMOTE" ] && args+=(--image-src remote)
[ -n "$PLATFORM" ] && args+=(--platform "$PLATFORM")

rm -f "$OUT"
rc=0
trivy image "${args[@]}" \
  --severity HIGH,CRITICAL \
  --pkg-types os,library \
  --show-suppressed \
  --format json --output "$OUT" \
  --no-progress --exit-code 0 "$REF" || rc=$?

if [ "$rc" -ne 0 ]; then
  echo "::error::scan-image: trivy exited ${rc} scanning ${REF}${PLATFORM:+ (${PLATFORM})}; that digest has no usable scan result (Req 2.26)" >&2
  exit 1
fi
if [ ! -s "$OUT" ]; then
  echo "::error::scan-image: no report was written for ${REF}${PLATFORM:+ (${PLATFORM})}; a manifest with no report is not a manifest with no findings (Req 2.26)" >&2
  exit 1
fi

echo "scan-image: ${REF}${PLATFORM:+ (${PLATFORM})} -> ${OUT}"
