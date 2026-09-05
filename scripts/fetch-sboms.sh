#!/usr/bin/env bash
# fetch-sboms.sh <root> <enumeration.tsv> <out-dir>
#
# The attested CycloneDX SBOM of every supported platform manifest, read only
# through `cosign verify-attestation --type cyclonedx` against the role
# identities catalogue-policy.yaml admits for cyclonedx (Req 6.58; task 10.6).
# The release job attests the SBOM to each platform manifest (build.yml), so
# that is where it is read. Output: <out-dir>/sha256-<manifest hex>.cdx.json,
# the bare CycloneDX document (the in-toto predicate). A manifest with no
# verifiable SBOM is named as a warning and skipped, never invented: the
# lifecycle tool then claims no version bump for it (Req 6.56). Superseded
# rows are not read; they hold no issues.
set -uo pipefail
ROOT="${1:?usage: fetch-sboms.sh <root> <enumeration.tsv> <out-dir>}"
TSV="${2:?usage: fetch-sboms.sh <root> <enumeration.tsv> <out-dir>}"
OUT="${3:?usage: fetch-sboms.sh <root> <enumeration.tsv> <out-dir>}"
[ -f "$TSV" ] || { echo "::error::fetch-sboms: enumeration '$TSV' does not exist" >&2; exit 2; }
[ -f "$ROOT/catalogue-policy.yaml" ] || { echo "::error::fetch-sboms: no catalogue-policy.yaml under '$ROOT'" >&2; exit 2; }

ISSUER=$(python3 -c 'import sys,yaml; print((yaml.safe_load(open(sys.argv[1])) or {}).get("verification",{}).get("issuer",""))' "$ROOT/catalogue-policy.yaml")
mapfile -t IDS < <(python3 - "$ROOT/catalogue-policy.yaml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1])) or {}
for role in ((doc.get("verification") or {}).get("roles") or {}).values():
    if "cyclonedx" in (role.get("attests") or []) and role.get("identity"):
        print(role["identity"])
PY
)
[ -n "$ISSUER" ] && [ "${#IDS[@]}" -gt 0 ] || { echo "::error::fetch-sboms: catalogue-policy.yaml names no issuer or no role that attests cyclonedx (Req 6.58)" >&2; exit 2; }
mkdir -p "$OUT"

declare -A seen=()
total=0; fetched=0; missing=0
# shellcheck disable=SC2034  # tag and digest are the enumeration's columns, unused here
while IFS=$'\t' read -r repo tag digest platform manifest status; do
  [ -n "$repo" ] && [ "$status" = "supported" ] || continue
  ref="${repo}@${manifest}"
  [ -n "${seen[$ref]:-}" ] && continue
  seen[$ref]=1
  total=$((total + 1))
  out="$OUT/sha256-${manifest#sha256:}.cdx.json"
  ok=false; why=""
  for id in "${IDS[@]}"; do
    # stdin is the enumeration here; a tool that read it would eat the rows
    if cosign verify-attestation --type cyclonedx --certificate-oidc-issuer "$ISSUER" --certificate-identity "$id" "$ref" </dev/null 2>"$OUT/.err" \
         | jq -cn 'first(inputs | .payload | @base64d | fromjson | select(.predicateType == "https://cyclonedx.org/bom") | .predicate)' > "$out.tmp" 2>/dev/null \
       && [ -s "$out.tmp" ]; then
      mv "$out.tmp" "$out"; ok=true; break
    fi
    why=$(tail -n 1 "$OUT/.err" 2>/dev/null || true)
  done
  rm -f "$out.tmp" "$OUT/.err"
  if [ "$ok" = true ]; then
    fetched=$((fetched + 1))
    echo "fetch-sboms: ${ref} (${platform}): $(jq '.components | length' "$out") component(s)"
  else
    missing=$((missing + 1))
    echo "::warning::fetch-sboms: no verifiable CycloneDX SBOM on ${ref} (${platform})${why:+: ${why}}; no version bump will be claimed for it"
  fi
done < "$TSV"
echo "fetch-sboms: ${fetched} of ${total} supported platform manifest(s) read through verification, ${missing} without"
