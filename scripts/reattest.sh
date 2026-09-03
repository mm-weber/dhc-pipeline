#!/usr/bin/env bash
# reattest.sh <root> <enumeration.tsv> <out-dir> [--dry-run]
#
# The rescan's re-attestation, replacing (task 10.3; Req 6.42, 6.43, 6.55,
# 6.58; ADR 0004). For every tag-referenced digest in the enumeration:
#
#   1. attest today's scan report to each platform manifest with
#      `cosign attest --type vuln --replace` (Req 6.42), taken with
#      --show-suppressed so covered findings stay visible (Req 6.55);
#   2. read the previously attested OpenVEX document(s) only through
#      `cosign verify-attestation` against the role identities the policy file
#      admits for openvex (Req 6.58); several are merged with vexctl into the
#      one carry-forward input (Req 6.43);
#   3. compile this digest's document from source, exceptions, today's reports,
#      the previous document and the open-issue map (Req 6.37);
#   4. when its statement set differs from the attested one, or the digest or
#      any platform manifest carries a number of OpenVEX attestations other
#      than one, `cosign attest --type openvex --replace` on the digest and on
#      each platform manifest (Req 6.43); otherwise touch nothing.
#
# A digest with a report missing (a scan that failed today) is skipped whole:
# a document compiled from incomplete inputs would state as uncovered what
# was simply not looked at. Skips are named and counted, never silent.
#
# Every step is recorded in <out-dir>/reattest.jsonl, one object per digest,
# with the .att layer lists and Rekor log indexes before and after: the first
# run in this repository is the measurement ADR 0004 left open (keyless
# --replace, Rekor retention), and the record is what makes it one.
#
# Reports are read from <out-dir>/trivy and <out-dir>/trivy-superseded under
# the rescan's naming (<image>__<12 hex>__<platform>.json). Tools come from
# PATH: cosign (v2, the line with --replace), trivy, crane, vexctl, curl.
# REATTEST_ISSUES names the open-issue map handed to the compiler; unset means
# no issue links. --dry-run runs everything but writes nothing to the registry.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:?usage: reattest.sh <root> <enumeration.tsv> <out-dir> [--dry-run]}"
TSV="${2:?usage: reattest.sh <root> <enumeration.tsv> <out-dir> [--dry-run]}"
OUT="${3:?usage: reattest.sh <root> <enumeration.tsv> <out-dir> [--dry-run]}"
DRY=""; [ "${4:-}" = "--dry-run" ] && DRY=1
OPENVEX="https://openvex.dev/ns"
REKOR="${REATTEST_REKOR:-https://rekor.sigstore.dev}"
[ -f "$TSV" ] || { echo "::error::reattest: enumeration '$TSV' does not exist — nothing was re-attested" >&2; exit 2; }
[ -f "$ROOT/catalogue-policy.yaml" ] || { echo "::error::reattest: no catalogue-policy.yaml under '$ROOT'" >&2; exit 2; }
mkdir -p "$OUT/reattest"
RECORD="$OUT/reattest.jsonl"; : > "$RECORD"

# The identities allowed to have attested what we read (Req 2.23, 6.58): the
# policy file's roles whose `attests` lists the type. Read once.
ids_for() { # <type> -> identities, one per line
  python3 - "$ROOT/catalogue-policy.yaml" "$1" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1])) or {}
ver = doc.get("verification") or {}
for role in (ver.get("roles") or {}).values():
    if sys.argv[2] in (role.get("attests") or []) and role.get("identity"):
        print(role["identity"])
PY
}
ISSUER=$(python3 -c 'import sys,yaml; print((yaml.safe_load(open(sys.argv[1])) or {}).get("verification",{}).get("issuer",""))' "$ROOT/catalogue-policy.yaml")
mapfile -t OPENVEX_IDS < <(ids_for openvex)
[ -n "$ISSUER" ] && [ "${#OPENVEX_IDS[@]}" -gt 0 ] || { echo "::error::reattest: catalogue-policy.yaml names no issuer or no role that attests openvex — the previous document cannot be read through verification (Req 6.58)" >&2; exit 2; }

att_layers() { # <repo> <digest> -> JSON: {"openvex": n, "rekor": [logIndex...]} read from the .att tag
  local repo="$1" digest="$2" manifest
  if ! manifest=$(crane manifest "${repo}:sha256-${digest#sha256:}.att" 2>/dev/null); then
    echo '{"openvex":0,"rekor":[]}'; return
  fi
  # A manifest that does not parse is not "one attestation": it is unknown,
  # which the caller treats as a wrong count (a replace is idempotent and
  # repairs it) and names.
  printf '%s' "$manifest" | jq -c --arg t "$OPENVEX" '
    [.layers[]? | select(.annotations.predicateType == $t)]
    | {openvex: length,
       rekor: [ .[] | .annotations["dev.sigstore.cosign/bundle"] // "" | select(. != "")
                | (try (fromjson | .Payload.logIndex) catch empty) ]}' 2>/dev/null \
    || { echo "::warning::reattest: the .att manifest of ${repo}@${digest} is not readable JSON — counted as unknown" >&2; echo '{"openvex":-1,"rekor":[]}'; }
}
registry_write() { # the one seam between "decided" and "pushed"
  if [ -n "$DRY" ]; then echo "reattest (dry-run): would run: $*"; return 0; fi
  "$@"
}

declare -A tags_of=() manifests_of=() platform_of=() status_of=()
while IFS=$'\t' read -r repo tag digest platform manifest status; do
  [ -n "$repo" ] || continue
  key="${repo}@${digest}"
  case " ${tags_of[$key]:-} " in *" ${tag} "*) ;; *) tags_of[$key]="${tags_of[$key]:-} ${tag}" ;; esac
  case " ${manifests_of[$key]:-} " in *" ${manifest} "*) ;; *) manifests_of[$key]="${manifests_of[$key]:-} ${manifest}" ;; esac
  platform_of["${repo}@${manifest}"]="$platform"
  [ "$status" = "supported" ] && status_of[$key]=supported
  : "${status_of[$key]:=superseded}"
done < "$TSV"

digests=0; reattested=0; skipped=0; failed=0
for key in $(printf '%s\n' "${!tags_of[@]}" | sort); do
  repo="${key%@*}"; digest="${key#*@}"; name="${repo##*/}"
  read -r -a tags <<< "${tags_of[$key]}"
  read -r -a manifests <<< "${manifests_of[$key]}"
  hex="${digest#sha256:}"; d12="${hex:0:12}"
  work="$OUT/reattest/${name}__${d12}"; mkdir -p "$work/out"
  digests=$((digests + 1))
  echo "::group::re-attest ${repo}@${digest} (${status_of[$key]}, tags:${tags_of[$key]})"

  # 0. every platform manifest needs today's report, or the digest is skipped whole
  reports=(); missing=()
  for m in "${manifests[@]}"; do
    p="${platform_of[${repo}@${m}]}"
    f="$OUT/trivy/${name}__${d12}__${p//\//-}.json"
    [ -f "$f" ] || f="$OUT/trivy-superseded/${name}__${d12}__${p//\//-}.json"
    if [ -f "$f" ]; then reports+=("$f"); else missing+=("$m ($p)"); fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "::warning::reattest: ${repo}@${digest} skipped — no scan report today for ${missing[*]}; a document compiled from incomplete inputs would state as uncovered what was not looked at"
    skipped=$((skipped + 1))
    jq -cn --arg repo "$repo" --arg digest "$digest" --arg reason "missing report: ${missing[*]}" \
      '{repository:$repo, digest:$digest, skipped:$reason}' >> "$RECORD"
    echo "::endgroup::"; continue
  fi

  # 1. today's scan reports, attested with --replace (Req 6.42)
  reports_attested=0; ok=true
  for i in "${!manifests[@]}"; do
    m="${manifests[$i]}"; f="${reports[$i]}"
    if ! trivy convert --format cosign-vuln --output "$work/vuln-${m#sha256:}.json" "$f"; then
      echo "::error::reattest: trivy convert failed for ${f}"; ok=false; break
    fi
    if registry_write cosign attest --yes --type vuln --replace --predicate "$work/vuln-${m#sha256:}.json" "${repo}@${m}"; then
      reports_attested=$((reports_attested + 1))
    else
      echo "::error::reattest: cosign attest --type vuln --replace failed for ${repo}@${m}"; ok=false; break
    fi
  done
  if [ "$ok" != true ]; then
    failed=$((failed + 1))
    jq -cn --arg repo "$repo" --arg digest "$digest" '{repository:$repo, digest:$digest, failed:"scan report attestation"}' >> "$RECORD"
    echo "::endgroup::"; continue
  fi

  # 2. what the digest carries today, and the previous document read only
  #    through verification (Req 6.58)
  before_index=$(att_layers "$repo" "$digest")
  before_manifests="{}"
  for m in "${manifests[@]}"; do
    before_manifests=$(jq -c --arg m "$m" --argjson v "$(att_layers "$repo" "$m")" '. + {($m): $v}' <<<"$before_manifests")
  done
  : > "$work/envelopes.jsonl"
  for id in "${OPENVEX_IDS[@]}"; do
    cosign verify-attestation --type openvex --certificate-oidc-issuer "$ISSUER" --certificate-identity "$id" \
      "${repo}@${digest}" 2>/dev/null >> "$work/envelopes.jsonl" || true
  done
  jq -c '.payload | @base64d | fromjson | select(.predicateType == "https://openvex.dev/ns") | .predicate' \
    "$work/envelopes.jsonl" 2>/dev/null > "$work/previous-docs.jsonl" || : > "$work/previous-docs.jsonl"
  previous_n=$(grep -c . "$work/previous-docs.jsonl" || true)
  previous=""
  if [ "$previous_n" -eq 1 ]; then
    previous="$work/previous.json"; jq . "$work/previous-docs.jsonl" > "$previous"
  elif [ "$previous_n" -gt 1 ]; then
    # Several documents verified on one digest: the count is wrong (ADR 0004)
    # and the carry-forward input is their field-preserving merge (ADR 0003).
    parts=(); n=0
    while IFS= read -r line; do n=$((n + 1)); printf '%s\n' "$line" > "$work/previous-$n.json"; parts+=("$work/previous-$n.json"); done < "$work/previous-docs.jsonl"
    previous="$work/previous.json"
    if ! vexctl merge "${parts[@]}" > "$previous"; then
      echo "::error::reattest: vexctl merge of ${previous_n} previously attested documents failed for ${repo}@${digest}"
      failed=$((failed + 1)); echo "::endgroup::"; continue
    fi
  fi

  # 3. compile from the named inputs (Req 6.37)
  export COMPILE_VEX_SCAN_REPORTS="${reports[*]}" COMPILE_VEX_MANIFEST_DIGESTS="${manifests[*]}" \
         COMPILE_VEX_REPORT="$work/compile-report.json" COMPILE_VEX_ROOT="$ROOT"
  if [ -n "$previous" ]; then export COMPILE_VEX_PREVIOUS="$previous"; else unset COMPILE_VEX_PREVIOUS; fi
  if [ -n "${REATTEST_ISSUES:-}" ]; then export COMPILE_VEX_ISSUES="$REATTEST_ISSUES"; else unset COMPILE_VEX_ISSUES; fi
  if ! "$HERE/compile-vex.sh" "$ROOT/triage/vex" "$work/out" "$name" "$digest" "${tags[@]}"; then
    echo "::error::reattest: compile-vex failed for ${repo}@${digest}"
    failed=$((failed + 1)); echo "::endgroup::"; continue
  fi
  unset COMPILE_VEX_SCAN_REPORTS COMPILE_VEX_MANIFEST_DIGESTS COMPILE_VEX_REPORT COMPILE_VEX_ROOT COMPILE_VEX_PREVIOUS COMPILE_VEX_ISSUES
  doc=""; for doc in "$work"/out/*.openvex.json; do break; done

  # 4. differs? canonical statement sets; document @id, timestamp and version
  #    are compile artefacts, not content (independent review 1.4)
  differs=$(python3 - "$doc" "${previous:-}" <<'PY'
import json, sys
def canon(path):
    if not path:
        return None
    doc = json.load(open(path))
    return sorted(json.dumps(st, sort_keys=True) for st in (doc.get("statements") or []))
new, old = canon(sys.argv[1]), canon(sys.argv[2])
print("true" if old is None or new != old else "false")
PY
)
  wrong_count=false
  [ "$(jq '.openvex' <<<"$before_index")" -eq 1 ] || wrong_count=true
  jq -e '[.[] | .openvex] | all(. == 1)' <<<"$before_manifests" >/dev/null || wrong_count=true
  did=false
  if [ "$differs" = true ] || [ "$wrong_count" = true ]; then
    reason=$([ "$differs" = true ] && echo "statement set differs" || echo "attestation count is not one")
    [ "$previous_n" -eq 0 ] && reason="no previously attested document"
    echo "reattest: ${repo}@${digest}: ${reason} — attesting with --replace on the digest and ${#manifests[@]} platform manifest(s) (Req 6.43)"
    if registry_write cosign attest --yes --type openvex --replace --predicate "$doc" "${repo}@${digest}"; then
      did=true
      for m in "${manifests[@]}"; do
        registry_write cosign attest --yes --type openvex --replace --predicate "$doc" "${repo}@${m}" || { echo "::error::reattest: cosign attest --type openvex --replace failed for ${repo}@${m}"; did=false; break; }
      done
    else
      echo "::error::reattest: cosign attest --type openvex --replace failed for ${repo}@${digest}"
    fi
    if [ "$did" = true ]; then reattested=$((reattested + 1)); else failed=$((failed + 1)); fi
  else
    echo "reattest: ${repo}@${digest}: statement set unchanged and exactly one attestation everywhere — nothing to write"
  fi

  # 5. the record, with the after-state and the Rekor retention measurement
  after_index=$(att_layers "$repo" "$digest")
  retained="[]"
  if [ "$did" = true ] && [ -z "$DRY" ]; then
    for idx in $(jq -r '.rekor[]' <<<"$before_index"); do
      if curl -fsS --max-time 30 "${REKOR}/api/v1/log/entries?logIndex=${idx}" -o /dev/null; then
        retained=$(jq -c --argjson i "$idx" '. + [{logIndex:$i, retained:true}]' <<<"$retained")
      else
        retained=$(jq -c --argjson i "$idx" '. + [{logIndex:$i, retained:false}]' <<<"$retained")
      fi
    done
  fi
  jq -cn --arg repo "$repo" --arg digest "$digest" --arg status "${status_of[$key]}" \
     --argjson tags "$(printf '%s\n' "${tags[@]}" | jq -R . | jq -s -c .)" \
     --argjson manifests "$(printf '%s\n' "${manifests[@]}" | jq -R . | jq -s -c .)" \
     --argjson reports "$reports_attested" --argjson previous "$previous_n" \
     --argjson before_index "$before_index" --argjson before_manifests "$before_manifests" \
     --argjson differs "$differs" --argjson wrong_count "$wrong_count" --argjson reattested "$did" \
     --argjson after_index "$after_index" --argjson rekor_retained "$retained" --argjson dry "$([ -n "$DRY" ] && echo true || echo false)" \
     --slurpfile compile "$work/compile-report.json" \
     '{repository:$repo, digest:$digest, status:$status, tags:$tags, manifests:$manifests,
       reports_attested:$reports, previous_documents:$previous,
       openvex_before:{index:$before_index, manifests:$before_manifests},
       differs:$differs, wrong_count:$wrong_count, reattested:$reattested, dry_run:$dry,
       openvex_after:{index:$after_index}, rekor_retained:$rekor_retained,
       compiled:{statements:($compile[0].compiled), affected:($compile[0].affected), under_investigation:($compile[0].under_investigation), lapsed:($compile[0].lapsed)}}' >> "$RECORD"
  echo "::endgroup::"
done

echo "reattest: ${digests} tag-referenced digest(s): ${reattested} re-attested, $((digests - reattested - skipped - failed)) unchanged, ${skipped} skipped, ${failed} failed"
[ "$failed" -eq 0 ] || exit 1
