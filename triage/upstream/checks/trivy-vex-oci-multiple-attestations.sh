#!/usr/bin/env bash
# Reproduce the measurement behind ADR 0004: with more than one OpenVEX
# attestation on a digest, `trivy --vex oci` applies one of them chosen
# nondeterministically. Measured 2026-08-23 with trivy 0.72.0, cosign v2.6.0.
#
# Run it after any Trivy or cosign bump, and before trusting that "exactly one
# OpenVEX attestation per digest" is still the only safe shape. The failure
# mode it guards against is silent: a consumer gets a different VEX document
# on different days and nothing tells them.
#
#   ./trivy-vex-oci-multiple-attestations.sh          # ~2 min, local registry on :5000
#   RUNS=8 ./trivy-vex-oci-multiple-attestations.sh   # more runs per layer set
#
# Needs: docker (daemon), trivy, cosign v2.x (v3 writes bundles Trivy cannot
# read), jq, curl. Pulls ghcr.io/distribution/distribution:3.0.0 and one public
# catalogue image. Nothing here touches ghcr.io write paths.
set -euo pipefail

RUNS="${RUNS:-4}"
PORT="${PORT:-5000}"
DB="${TRIVY_DB_REPOSITORY:-ghcr.io/aquasecurity/trivy-db:2}"
CONTROL="${CONTROL:-ghcr.io/mm-weber/dhc/hardened-app:0.1.0-alpine3.23}"
REG_IMAGE="ghcr.io/distribution/distribution:3.0.0"
NAME="vexoci-check-registry"

WORK="$(mktemp -d)"
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

case "$(cosign version 2>/dev/null | awk '/GitVersion/ {print $2}')" in
  v2.*) ;;
  *) echo "cosign v2.x required: v3 stores attestations as bundles that trivy --vex oci does not read (measured)" >&2; exit 2 ;;
esac

echo "== local registry on :$PORT, control image pushed by digest"
docker run -d --name "$NAME" -p "$PORT:5000" "$REG_IMAGE" >/dev/null
sleep 2
docker pull -q "$CONTROL" >/dev/null
docker tag "$CONTROL" "localhost:$PORT/check/control:1"
docker push -q "localhost:$PORT/check/control:1" >/dev/null
DIGEST="$(docker inspect --format '{{index .RepoDigests}}' "localhost:$PORT/check/control:1" | grep -o "localhost:$PORT/check/control@sha256:[a-f0-9]*" | head -1 | sed 's/.*@//')"
REF="localhost:$PORT/check/control@$DIGEST"
echo "   $REF"

cd "$WORK"
export COSIGN_PASSWORD=""
cosign generate-key-pair >/dev/null 2>&1

scan() {  # -> number of HIGH/CRITICAL findings after --vex oci
  trivy image --db-repository "$DB" --image-src remote --severity HIGH,CRITICAL \
    --vex oci --format json --output "$WORK/scan.json" --no-progress --exit-code 0 "$REF" >/dev/null 2>&1
  jq -r '[.Results[]?.Vulnerabilities[]?] | length' "$WORK/scan.json"
}

echo "== baseline (no attestation)"
BASE="$(scan)"
echo "   findings: $BASE"
CVE="$(jq -r '[.Results[]?.Vulnerabilities[]?][0].VulnerabilityID' "$WORK/scan.json")"
PKG="$(jq -r '[.Results[]?.Vulnerabilities[]?][0].PkgIdentifier.PURL' "$WORK/scan.json" | sed 's/@.*//')"
[ -n "$CVE" ] && [ "$CVE" != "null" ] || { echo "control image has no HIGH/CRITICAL finding to suppress; pick another CONTROL" >&2; exit 2; }
echo "   statement under test: $CVE not_affected in $PKG (expected findings with it applied: $((BASE - 1)))"

cat > "$WORK/A.json" <<EOF
{"@context":"https://openvex.dev/ns/v0.2.0","@id":"urn:check:A","author":"check","timestamp":"2026-01-01T00:00:00Z","version":1,"statements":[]}
EOF
cat > "$WORK/B.json" <<EOF
{"@context":"https://openvex.dev/ns/v0.2.0","@id":"urn:check:B","author":"check","timestamp":"2026-01-02T00:00:00Z","version":1,
 "statements":[{"vulnerability":{"name":"$CVE"},"products":[{"@id":"pkg:oci/control@$DIGEST","subcomponents":[{"@id":"$PKG"}]}],
 "status":"not_affected","justification":"vulnerable_code_not_in_execute_path"}]}
EOF

att() {  # att <doc> [--replace]
  cosign attest --yes --key "$WORK/cosign.key" --type openvex --predicate "$WORK/$1.json" ${2:-} --tlog-upload=false "$REF" >/dev/null 2>&1
}
layers() {
  curl -s -H "Accept: application/vnd.oci.image.manifest.v1+json" \
    "http://localhost:$PORT/v2/check/control/manifests/sha256-${DIGEST#sha256:}.att" | jq -r '.layers | length'
}
case_run() {  # case_run "<label>" <first doc> [more docs...]; first is attested with --replace
  local label="$1"; shift
  att "$1" --replace; shift
  for d in "$@"; do att "$d"; done
  local n; n="$(layers)"
  local out=""
  for _ in $(seq "$RUNS"); do out="$out $(scan)"; done
  printf '   %-12s layers=%s  findings over %s runs:%s\n' "$label" "$n" "$RUNS" "$out"
}

echo "== one attestation (expected: stable)"
case_run "[A]" A
case_run "[B]" B
echo "== several attestations, appended (expected by ADR 0004: unstable, or at least not manifest order)"
case_run "[A,B]" A B
case_run "[B,A]" B A
case_run "[A,B,A]" A B A
case_run "[A,A,B]" A A B
echo "== --replace after several (expected: one layer, stable)"
att B; att A; att B --replace
printf '   replace->B  layers=%s  findings over %s runs:' "$(layers)" "$RUNS"; for _ in $(seq "$RUNS"); do printf ' %s' "$(scan)"; done; echo
echo
echo "Read the table: a layer set whose findings differ between runs is the defect;"
echo "the single-layer rows are the shape the catalogue keeps (ADR 0004)."
