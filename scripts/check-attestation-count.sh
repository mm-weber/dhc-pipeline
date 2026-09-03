#!/usr/bin/env bash
# check-attestation-count.sh <enumeration.tsv> [<out.json>]
#
# The daily invariant behind ADR 0004 (Req 6.44, 6.45): every tag-referenced
# digest, and every platform manifest under it, carries EXACTLY ONE OpenVEX
# attestation. With several, `trivy image --vex oci` applies one of them chosen
# nondeterministically, so a consumer reads a different VEX document on
# different days and nothing tells them; with none, the digest publishes no
# decisions at all. Both look like a clean scan from the outside.
#
# Counted where cosign keeps them: the `.att` tag beside each digest is an OCI
# manifest whose layers are the attestations, each annotated with its predicate
# type. Read anonymously through crane, the way a consumer reads it; a missing
# `.att` tag is zero attestations, not an error.
#
# Every deviation is named (repository, digest, kind, count) and any deviation
# fails the run: an invariant that soft-fails is an opinion.
set -euo pipefail
TSV="${1:?usage: check-attestation-count.sh <enumeration.tsv> [<out.json>]}"
OUT="${2:-}"
OPENVEX="https://openvex.dev/ns"
[ -f "$TSV" ] || { echo "::error::check-attestation-count: enumeration '$TSV' does not exist — nothing was checked" >&2; exit 2; }

count_openvex() { # <repo> <digest> -> number of OpenVEX layers (0 when no .att tag)
  local repo="$1" digest="$2" manifest
  if ! manifest=$(crane manifest "${repo}:sha256-${digest#sha256:}.att" 2>/dev/null); then
    echo 0; return
  fi
  printf '%s' "$manifest" | jq --arg t "$OPENVEX" '[.layers[]? | select(.annotations.predicateType == $t)] | length'
}

declare -A seen=()
rows=()
checked=0; bad=0
while IFS=$'\t' read -r repo _tag digest _platform manifest _status; do
  [ -n "$repo" ] || continue
  for pair in "index:${digest}" "manifest:${manifest}"; do
    kind="${pair%%:*}"; d="${pair#*:}"
    key="${repo}@${d}"
    [ -n "${seen[$key]:-}" ] && continue
    seen[$key]=1
    n=$(count_openvex "$repo" "$d")
    checked=$((checked + 1))
    ok=true
    if [ "$n" -ne 1 ]; then
      ok=false; bad=$((bad + 1))
      echo "::error::check-attestation-count (Req 6.44): ${repo}@${d} (${kind}) carries ${n} OpenVEX attestation(s), not exactly one — a consumer applying --vex oci gets $([ "$n" -eq 0 ] && echo 'no decisions at all' || echo 'one of them at random')"
    fi
    rows+=("$(jq -cn --arg repo "$repo" --arg d "$d" --arg kind "$kind" --argjson n "$n" --argjson ok "$ok" '{repository:$repo, digest:$d, kind:$kind, openvex_attestations:$n, ok:$ok}')")
  done
done < "$TSV"

if [ -n "$OUT" ]; then
  printf '%s\n' "${rows[@]:-}" | jq -s --argjson checked "$checked" --argjson bad "$bad" '{checked:$checked, deviations:$bad, rows: map(select(. != null))}' > "$OUT"
fi
if [ "$bad" -gt 0 ]; then
  echo "check-attestation-count: ${bad} of ${checked} digest(s) deviate from exactly one OpenVEX attestation (Req 6.44)"
  exit 1
fi
echo "check-attestation-count: every one of ${checked} tag-referenced digest(s) and platform manifest(s) carries exactly one OpenVEX attestation ✓"
