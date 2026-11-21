#!/usr/bin/env bash
# Measurements behind the PR #100 independent review (2026-08-23).
# Part 1: what Trivy 0.72.0 does with OpenVEX statement fields the spec relies on
#         (timestamp vs last_updated ordering; tolerance of action_statement_timestamp,
#         status_notes, last_updated; what `trivy convert --format cosign-vuln` carries).
# Part 2: the size of the tag-referenced set Req 6.42 would attest daily (anonymous
#         reads against ghcr.io/mm-weber/dhc).
set -uo pipefail
WORK="$(mktemp -d)"
IMG="ghcr.io/mm-weber/dhc/hardened-app:0.1.0-alpine3.23"
echo "== tools"; trivy --version | head -1; vexctl version 2>/dev/null | grep -i gitversion | head -1
DBFLAG=(--db-repository ghcr.io/aquasecurity/trivy-db:2)
if [ -f "$HOME/.cache/trivy/db/metadata.json" ]; then
  echo "trivy db cached: $(jq -r .UpdatedAt "$HOME/.cache/trivy/db/metadata.json")"
  DBFLAG=(--skip-db-update)
fi

scan() { # scan <vexfile-or-empty> <out.json> -> count of HIGH/CRITICAL
  local vex=() ; [ -n "$1" ] && vex=(--vex "$1")
  trivy image "${DBFLAG[@]}" --image-src remote --severity HIGH,CRITICAL --pkg-types os,library \
    "${vex[@]}" --format json --output "$2" --no-progress --exit-code 0 "$IMG" >"$WORK/trivy.log" 2>&1 \
    || { echo "trivy failed:"; tail -5 "$WORK/trivy.log"; return 1; }
  jq -r '[.Results[]?.Vulnerabilities[]?] | length' "$2"
}

echo "== part 1: baseline"
BASE=$(scan "" "$WORK/base.json") || exit 1
DIGEST=$(jq -r '.Metadata.RepoDigests[0]' "$WORK/base.json" | sed 's/.*@//')
CVE=$(jq -r '[.Results[]?.Vulnerabilities[]?][0].VulnerabilityID' "$WORK/base.json")
PKG=$(jq -r '[.Results[]?.Vulnerabilities[]?][0].PkgIdentifier.PURL' "$WORK/base.json" | sed 's/@.*//')
echo "baseline findings: $BASE ; digest: $DIGEST ; statement under test: $CVE in $PKG"
PRODUCT="pkg:oci/hardened-app@$DIGEST"

doc() { # doc <file> <statements-json>
  cat > "$1" <<EOF
{"@context":"https://openvex.dev/ns/v0.2.0","@id":"urn:review:$(basename "$1" .json)","author":"review","timestamp":"2026-08-23T00:00:00Z","version":1,"statements":[$2]}
EOF
}
NA='{"vulnerability":{"name":"'"$CVE"'"},"products":[{"@id":"'"$PRODUCT"'","subcomponents":[{"@id":"'"$PKG"'"}]}],"status":"not_affected","justification":"vulnerable_code_not_in_execute_path","timestamp":"2026-08-01T00:00:00Z"}'
AFF_OLD='{"vulnerability":{"name":"'"$CVE"'"},"products":[{"@id":"'"$PRODUCT"'","subcomponents":[{"@id":"'"$PKG"'"}]}],"status":"affected","action_statement":"transfer: waiting upstream; paths: usr/bin/app; expires 2026-11-02","action_statement_timestamp":"2026-08-10T00:00:00Z","timestamp":"2026-07-01T00:00:00Z","last_updated":"2026-08-20T00:00:00Z","status_notes":"first seen 2026-07-01"}'
AFF_NEW='{"vulnerability":{"name":"'"$CVE"'"},"products":[{"@id":"'"$PRODUCT"'","subcomponents":[{"@id":"'"$PKG"'"}]}],"status":"affected","action_statement":"transfer","action_statement_timestamp":"2026-08-16T00:00:00Z","timestamp":"2026-08-15T00:00:00Z","last_updated":"2026-08-16T00:00:00Z"}'
UI='{"vulnerability":{"name":"'"$CVE"'"},"products":[{"@id":"'"$PRODUCT"'","subcomponents":[{"@id":"'"$PKG"'"}]}],"status":"under_investigation","timestamp":"2026-07-01T00:00:00Z","last_updated":"2026-08-22T00:00:00Z","status_notes":"lapsed: exception expired 2026-08-21"}'

doc "$WORK/d1.json" "$NA"
doc "$WORK/d2.json" "$NA,$AFF_OLD"
doc "$WORK/d3.json" "$NA,$AFF_NEW"
doc "$WORK/d4.json" "$AFF_OLD"
doc "$WORK/d5.json" "$UI"

echo "d1 not_affected(ts 08-01) alone                              -> $(scan "$WORK/d1.json" "$WORK/d1.out.json")  (expect $((BASE-1)): suppressed)"
echo "d2 not_affected(ts 08-01) + affected(ts 07-01, last_updated 08-20) -> $(scan "$WORK/d2.json" "$WORK/d2.out.json")  ($((BASE-1)) means ordering by timestamp, $BASE means by last_updated)"
echo "d3 not_affected(ts 08-01) + affected(ts 08-15)               -> $(scan "$WORK/d3.json" "$WORK/d3.out.json")  ($BASE means the later affected wins and the finding is reported)"
echo "d4 affected with action_statement_timestamp/last_updated/status_notes -> $(scan "$WORK/d4.json" "$WORK/d4.out.json")  (expect $BASE, and no parse error)"
grep -i "vex\|error\|warn" "$WORK/trivy.log" | grep -iv "deprecat" | head -5
echo "d5 under_investigation with last_updated/status_notes        -> $(scan "$WORK/d5.json" "$WORK/d5.out.json")  (expect $BASE)"
echo "-- suppressed finding representation in the JSON report (d1):"
jq -c '[.Results[]?.ExperimentalModifiedFindings[]? | {ID: .Finding.VulnerabilityID, Status, Source, Statement}]' "$WORK/d1.out.json"
echo "-- trivy convert --format cosign-vuln of d1 report: does the predicate carry the suppressed finding?"
if trivy convert --format cosign-vuln --output "$WORK/d1.vuln.json" "$WORK/d1.out.json" >/dev/null 2>&1; then
  echo "   predicate keys: $(jq -r 'keys|join(",")' "$WORK/d1.vuln.json")"
  echo "   scanner.result keys: $(jq -r '.scanner.result | keys | join(",")' "$WORK/d1.vuln.json" 2>/dev/null)"
  echo "   Vulnerabilities in predicate: $(jq '[.scanner.result.Results[]?.Vulnerabilities[]?] | length' "$WORK/d1.vuln.json")"
  echo "   ExperimentalModifiedFindings in predicate: $(jq '[.scanner.result.Results[]?.ExperimentalModifiedFindings[]?] | length' "$WORK/d1.vuln.json")"
  echo "   size: $(wc -c < "$WORK/d1.vuln.json") bytes (hardened-app; grafana's report is larger)"
else
  echo "   trivy convert failed"
fi
echo "-- vexctl merge of d2 (does vexctl accept affected + the timestamp fields?)"
vexctl merge "$WORK/d2.json" > "$WORK/merged.json" 2>"$WORK/vexctl.err"; echo "   exit $? ; $(head -c 300 "$WORK/vexctl.err")"
jq -c '.statements[] | {status, timestamp, last_updated, action_statement_timestamp, status_notes}' "$WORK/merged.json" 2>/dev/null

echo
echo "== part 2: tag-referenced set under ghcr.io/mm-weber/dhc (anonymous)"
total_digests=0; total_pm=0
for repo in hardened-app cert-manager-controller cert-manager-webhook cert-manager-cainjector grafana valkey; do
  tok=$(curl -s "https://ghcr.io/token?scope=repository:mm-weber/dhc/${repo}:pull" | jq -r .token)
  tags=$(curl -s -H "Authorization: Bearer $tok" "https://ghcr.io/v2/mm-weber/dhc/${repo}/tags/list" | jq -r '.tags[]?' | grep -v '^sha256-' | sort)
  declare -A seen=()
  pm=0
  for t in $tags; do
    m=$(curl -s -H "Authorization: Bearer $tok" -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json" "https://ghcr.io/v2/mm-weber/dhc/${repo}/manifests/${t}")
    d=$(printf '%s' "$m" | sha256sum | cut -c1-12)
    if [ -z "${seen[$d]:-}" ]; then
      n=$(printf '%s' "$m" | jq '[.manifests[]? | select(.platform.architecture != "unknown")] | length')
      [ "$n" = "0" ] && n=1
      seen[$d]=$n; pm=$((pm+n))
    fi
  done
  echo "$repo: $(echo "$tags" | wc -w) catalogue tags -> ${#seen[@]} distinct digests, $pm platform manifests; tags: $(echo $tags)"
  total_digests=$((total_digests+${#seen[@]})); total_pm=$((total_pm+pm))
  unset seen
done
echo "TOTAL: $total_digests tag-referenced digests, $total_pm platform manifests to scan and attest per day (Req 6.42)"
echo "-- OpenVEX attestation layers on the current grafana release digest (ADR 0004 says 3):"
tok=$(curl -s "https://ghcr.io/token?scope=repository:mm-weber/dhc/grafana:pull" | jq -r .token)
gd=$(curl -s -I -H "Authorization: Bearer $tok" -H "Accept: application/vnd.oci.image.index.v1+json" "https://ghcr.io/v2/mm-weber/dhc/grafana/manifests/13.1.3-alpine3.23" | grep -i docker-content-digest | awk '{print $2}' | tr -d '\r' | sed 's/sha256://')
curl -s -H "Authorization: Bearer $tok" -H "Accept: application/vnd.oci.image.manifest.v1+json" "https://ghcr.io/v2/mm-weber/dhc/grafana/manifests/sha256-${gd}.att" | jq -r '.layers[] | .annotations["predicateType"]' | sort | uniq -c
rm -rf "$WORK"
