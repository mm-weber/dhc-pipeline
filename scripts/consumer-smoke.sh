#!/usr/bin/env bash
# consumer-smoke.sh --root <dir> --readme <README.md> --ref <image@sha256:...> \
#                   --out <smoke.md> --json <smoke.json>
#
# The daily consumer smoke test (task 13.4, Req 9.13): the verification
# recipe README.md publishes between the render-verification markers, run
# VERBATIM against one published digest, so the README's verify section is
# a tested contract rather than prose. Three parts:
#
#   1. The recipe, step by step. The fenced block is extracted, its REF=
#      line replaced by the smoke digest, and each step (a command with its
#      continuation lines) run in a scratch directory with the recipe's own
#      variables. A step that exits non-zero fails the run naming the step.
#   2. The authoritative consumer's suppressions, from the same extracted
#      document (openvex.json, which the recipe wrote). Every not_affected or
#      fixed statement whose finding the authoritative consumer still REPORTS
#      is a suppression missing in the authoritative consumer: the run fails
#      naming the statement. A finding it does not report at all is neither
#      (nothing to suppress); an affected statement suppresses nothing by
#      design.
#   3. ADR 0004's regression check: trivy reading `--vex oci` (the attestation
#      itself, exactly one per digest, Req 6.44) must suppress what the
#      extracted document suppresses; suppressing less is the authoritative
#      consumer missing suppressions for anyone who follows that reading, and
#      fails the run naming the statements. Suppressing more is reported.
#
# Every other declared consumer's result goes into the VEX portability block
# (vex-portability.sh), informational (Req 9.12, 9.13). cosign, jq, trivy,
# grype and docker come from PATH; the tests stub them.
#
# Exit 0: recipe ran, suppressions landed. Exit 1: a failed step or a
# missing suppression. Exit 2: no recipe to run.
set -uo pipefail
ROOT=. README="" REF="" OUT="" JSON=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --readme) README="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --json) JSON="$2"; shift 2 ;;
    *) echo "::error::consumer-smoke: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$README" ] && [ -n "$REF" ] && [ -n "$OUT" ] && [ -n "$JSON" ] || { echo "::error::consumer-smoke: usage: --root <dir> --readme <README.md> --ref <image@digest> --out <smoke.md> --json <smoke.json>" >&2; exit 2; }
err() { printf '::error::consumer-smoke: %s\n' "$1" >&2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$ROOT" && pwd)"
AUTH=$("$HERE/triage-policy.sh" "$ROOT" authoritative-consumer) || exit 2
mapfile -t OTHERS < <("$HERE/triage-policy.sh" "$ROOT" other-consumers)

# 1. the recipe, extracted and run verbatim
WORK=$(mktemp -d)
trap '[ -n "${SMOKE_KEEP_WORK:-}" ] || rm -rf "$WORK"' EXIT
python3 - "$README" "$REF" "$WORK/steps" <<'PY'
import re, sys
readme, ref, out = sys.argv[1:4]
text = open(readme).read()
m = re.search(r"<!-- render-verification:begin -->\n```sh\n(.*?)```\n<!-- render-verification:end -->", text, re.S)
if not m:
    print("::error::consumer-smoke: no rendered recipe between the render-verification markers in " + readme, file=sys.stderr)
    sys.exit(2)
lines = m.group(1).splitlines()
# assignments stay as they are (with REF replaced); commands are grouped with their continuation lines
prelude, steps, cur = [], [], []
for line in lines:
    if re.match(r"^\s*#", line) or not line.strip():
        if cur: cur.append(line)
        continue
    if re.match(r"^[A-Z_]+=", line) and not cur:
        if line.startswith("REF="):
            line = f"REF={ref}"
        prelude.append(line); continue
    cur.append(line)
    if not line.rstrip().endswith("\\"):
        steps.append("\n".join(cur)); cur = []
if cur: steps.append("\n".join(cur))
with open(out, "w") as f:
    f.write("\n".join(prelude) + "\n")
    f.write("\x1e".join(steps))
print(len(steps))
PY
rc=$?; [ "$rc" -eq 0 ] || exit "$rc"
prelude=$(head -n "$(grep -c '^[A-Z_]*=' "$WORK/steps" | head -1)" "$WORK/steps")
mapfile -d $'\x1e' -t STEPS < <(tail -n +"$(( $(grep -c '^[A-Z_]*=' "$WORK/steps") + 1 ))" "$WORK/steps")
mkdir -p "$WORK/run"
ran=0; failed=0; failed_names=()
for step in "${STEPS[@]}"; do
  [ -n "${step//[[:space:]]/}" ] || continue
  ran=$((ran + 1))
  name=$(printf '%s\n' "$step" | grep -v -E '^\s*#' | head -1 | sed 's/#.*//; s/[[:space:]]*\\$//; s/^[[:space:]]*[{]*[[:space:]]*//' | cut -c1-60)
  (cd "$WORK/run" && bash -o pipefail -c "$prelude"$'\n'"$step" > "$WORK/step-${ran}.out" 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    failed=$((failed + 1)); failed_names+=("$name")
    err "recipe step ${ran} failed (exit ${rc}): ${name}"
    sed 's/^/    /' "$WORK/step-${ran}.out" | tail -5 >&2
  fi
done

# 2. the authoritative consumer's suppressions, from the document the recipe extracted
doc="$WORK/run/openvex.json"
suppressing=0; affected=0; landed=0; missing=0; missing_names=(); measured=""
oci_note="not measured"; oci_agrees=null; oci_missing=()
mkdir -p "$WORK/vex"; cp "$doc" "$WORK/vex/openvex.json" 2>/dev/null || true
if [ -s "$doc" ] && "$HERE/vex-consumer.sh" "$AUTH" "$WORK/auth.jsonl" --root "$ROOT" --scan "$REF" --vex-dir "$WORK/vex" --remote >/dev/null 2>"$WORK/auth.err"; then
  measured=1
  python3 - "$doc" "$WORK/auth.jsonl" "$WORK/verdict" <<'PY'
import json, sys
doc, rec, out = sys.argv[1:4]
d = json.load(open(doc))
def key(purl):
    base = (purl or "").split("?")[0]
    if "@" in base:
        n, _, v = base.rpartition("@")
        if v.startswith("v") and len(v) > 1 and v[1].isdigit(): v = v[1:]
        base = f"{n}@{v}"
    return base
statements = []  # (vuln, key, status)
affected = 0
for s in d.get("statements") or []:
    vuln = (s.get("vulnerability") or {}).get("name") or (s.get("vulnerability") or {}).get("@id") or ""
    status = s.get("status") or ""
    subs = [sub.get("@id") for p in (s.get("products") or []) for sub in (p.get("subcomponents") or []) if sub.get("@id")]
    if status in ("not_affected", "fixed"):
        for sub in subs or [""]:
            statements.append((vuln, key(sub), status))
    elif status == "affected":
        affected += 1
rows = [json.loads(l) for l in open(rec) if l.strip()]
reported = {(r["vulnerability"], r["key"]) for r in rows if not r["suppressed"]}
landed = [s for s in statements if (s[0], s[1]) not in reported]
missing = [s for s in statements if (s[0], s[1]) in reported]
suppressed_keys = sorted({(r["vulnerability"], r["key"]) for r in rows if r["suppressed"] and r["by"] == "vex"})
json.dump({"suppressing": len(statements), "affected": affected, "landed": len(landed), "missing": missing,
           "suppressed": suppressed_keys}, open(out, "w"))
PY
  suppressing=$(jq '.suppressing' "$WORK/verdict"); affected=$(jq '.affected' "$WORK/verdict"); landed=$(jq '.landed' "$WORK/verdict"); missing=$(jq '.missing | length' "$WORK/verdict")
  mapfile -t missing_names < <(jq -r '.missing[] | "\(.[0]) (\(.[1]), \(.[2]))"' "$WORK/verdict")
  for m in "${missing_names[@]}"; do
    err "${m} is still reported by ${AUTH}: the published statement did not land in the authoritative consumer (Req 9.13)"
  done
  # 3. the --vex oci reading (ADR 0004): the attestation itself, one per digest
  if [ "$AUTH" = trivy ] && "$HERE/vex-consumer.sh" trivy "$WORK/oci.jsonl" --root "$ROOT" --scan "$REF" --vex-oci --remote >/dev/null 2>"$WORK/oci.err"; then
    python3 - "$WORK/verdict" "$WORK/oci.jsonl" "$WORK/oci-verdict" <<'PY'
import json, sys
verdict, rec, out = sys.argv[1:4]
v = json.load(open(verdict))
file_set = {tuple(x) for x in v["suppressed"]}
oci_set = {(r["vulnerability"], r["key"]) for r in (json.loads(l) for l in open(rec) if l.strip()) if r["suppressed"] and r["by"] == "vex"}
json.dump({"file": len(file_set), "oci": len(oci_set), "missing_in_oci": sorted(file_set - oci_set), "extra_in_oci": sorted(oci_set - file_set)}, open(out, "w"))
PY
    f=$(jq '.file' "$WORK/oci-verdict"); o=$(jq '.oci' "$WORK/oci-verdict")
    mapfile -t oci_missing < <(jq -r '.missing_in_oci[] | .[0]' "$WORK/oci-verdict")
    if [ "${#oci_missing[@]}" -gt 0 ]; then
      oci_agrees=false; oci_note="--vex oci suppresses ${o} statement(s), the extracted document ${f}: ${oci_missing[*]} missing (ADR 0004)"
      err "trivy --vex oci suppresses ${o} statement(s), the extracted document ${f}: ${oci_missing[*]}"
    elif [ "$(jq '.extra_in_oci | length' "$WORK/oci-verdict")" -gt 0 ]; then
      oci_agrees=false; oci_note="--vex oci suppresses ${o} statement(s), the extracted document ${f}: more in the attestation than the extracted document reads (reported, not gated)"
    else
      oci_agrees=true; oci_note="--vex oci: same ${f} suppression(s) as the extracted document"
    fi
  else
    oci_note="--vex oci: not measured ($(tr -d '\n' < "$WORK/oci.err" 2>/dev/null | cut -c1-160))"
  fi
else
  err "the authoritative consumer (${AUTH}) could not be run on ${REF}: $(tr -d '\n' < "$WORK/auth.err" 2>/dev/null | cut -c1-200)"
fi

# the other consumers, into the portability block (informational)
{
  echo "#### Consumer smoke test (Req 9.13)"
  echo
  echo "- digest: \`${REF}\`"
  echo "- recipe: ${ran} step(s) ran, ${failed} failed${failed_names:+ (${failed_names[*]})}"
  if [ -n "$measured" ]; then
    echo "- statements in the attested document: ${suppressing} suppressing (not_affected or fixed), ${affected} affected"
    echo "- ${AUTH} (authoritative): ${landed} of ${suppressing} suppressing statement(s) landed, ${missing} missing${missing_names:+: ${missing_names[*]}}"
    echo "- ${oci_note}"
  else
    echo "- ${AUTH} (authoritative): not measured"
  fi
  echo
} > "$OUT"
records=("$WORK/auth.jsonl")
for o in "${OTHERS[@]}"; do
  if [ -n "$measured" ] && "$HERE/vex-consumer.sh" "$o" "$WORK/${o}.jsonl" --root "$ROOT" --scan "$REF" --vex-dir "$WORK/vex" --remote >/dev/null 2>"$WORK/${o}.err"; then
    records+=("$WORK/${o}.jsonl")
  else
    records+=("$WORK/${o}.missing.jsonl")
  fi
done
if [ -n "$measured" ]; then
  "$HERE/vex-portability.sh" --root "$ROOT" --label "smoke ${REF}" --out "$OUT" --append --json "$WORK/portability.json" "${records[@]}" >/dev/null || true
fi

python3 - "$JSON" "$REF" "$ran" "$failed" "$suppressing" "$affected" "$landed" "$missing" "$oci_agrees" "$oci_note" "$WORK/portability.json" <<'PY'
import json, os, sys
out, ref, ran, failed, supp, aff, landed, missing, oci_agrees, oci_note, port = sys.argv[1:12]
p = json.load(open(port)) if os.path.exists(port) else None
json.dump({"ref": ref, "recipe": {"ran": int(ran), "failed": int(failed)},
           "authoritative": {"suppressing": int(supp), "affected": int(aff), "landed": int(landed), "missing": int(missing)},
           "oci": {"agrees": None if oci_agrees == "null" else oci_agrees == "true", "note": oci_note},
           "portability": p}, open(out, "w"), indent=1)
PY
echo "consumer-smoke: ${REF}: recipe ${ran} step(s) (${failed} failed), ${AUTH}: ${landed}/${suppressing} suppressions landed (${missing} missing), ${oci_note}"
[ "$failed" -eq 0 ] && [ "$missing" -eq 0 ] && [ -n "$measured" ] && [ "${#oci_missing[@]}" -eq 0 ] || exit 1
