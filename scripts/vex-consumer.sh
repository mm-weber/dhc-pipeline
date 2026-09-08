#!/usr/bin/env bash
# vex-consumer.sh <consumer> <out.jsonl> --root <dir> \
#     (--report <trivy.json> | --scan <ref> (--vex-dir <dir> | --vex-oci) [--remote] [--platform P])
#
# The adapter contract behind the declared VEX consumers (task 13.4,
# Req 9.11): a consumer is a scanner run with the compiled per-digest VEX
# whose findings are emitted in ONE normalised shape, one JSON object per
# line, sorted:
#
#   {"consumer": "trivy", "vulnerability": "CVE-...", "purl": "<the scanner's
#    own spelling>", "key": "<canonical purl>", "suppressed": true|false,
#    "by": "vex"|"exception"|"ignore"|"none", "status": "not_affected"|"fixed"
#    |"affected"|"under_investigation"|""}
#
# The key is what the portability block joins consumers on: the purl without
# qualifiers and without a leading `v` on the version, because the scanners
# spell one package two ways (measured 2026-09-08: trivy pkg:golang/stdlib@v1.26.4,
# syft/grype pkg:golang/stdlib@1.26.4; apk qualifiers arch and distro spelled
# differently). The scanner's own purl is kept beside it.
#
# Modes. --report normalises a report scan-image.sh already wrote (the gate's
# and the rescan's authoritative scan), so the block costs no second trivy
# run; a suppression whose Source is the accepted-risk ignorefile is `by:
# exception`, the catalogue's own decision that no other consumer can see.
# --scan runs the consumer: trivy with the same shape scan-image.sh runs
# minus the ignorefile (the block compares statements, and exceptions are
# ours alone), grype with `--vex` per compiled document and JSON output;
# --vex-oci makes trivy read the attestation instead of files, the other
# reading ADR 0004's regression check compares. Only severities in the
# declared aperture are emitted, for every consumer alike.
#
# Refusals: an undeclared consumer (exit 2; the policy file's list is the
# contract), a consumer that exits non-zero (exit 1, named, no half record).
set -uo pipefail
CONSUMER="${1:?usage: vex-consumer.sh <consumer> <out.jsonl> --root <dir> (--report <trivy.json> | --scan <ref> ...)}"
OUT="${2:?usage: vex-consumer.sh <consumer> <out.jsonl> --root <dir> (--report <trivy.json> | --scan <ref> ...)}"
shift 2
ROOT=. REPORT="" REF="" VEXDIR="" VEXOCI="" REMOTE="" PLATFORM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --report) REPORT="$2"; shift 2 ;;
    --scan) REF="$2"; shift 2 ;;
    --vex-dir) VEXDIR="$2"; shift 2 ;;
    --vex-oci) VEXOCI=1; shift ;;
    --remote) REMOTE=1; shift ;;
    --platform) PLATFORM="$2"; shift 2 ;;
    *) echo "::error::vex-consumer: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
HERE="$(cd "$(dirname "$0")" && pwd)"
err() { printf '::error::vex-consumer: %s\n' "$1" >&2; }

if ! "$HERE/triage-policy.sh" "$ROOT" consumers | cut -f1 | grep -qxF "$CONSUMER"; then
  err "${CONSUMER} is not a declared consumer (catalogue-policy.yaml consumers.list, Req 9.11)"
  exit 2
fi
APERTURE=$("$HERE/triage-policy.sh" "$ROOT" aperture)
[ -n "$REPORT" ] || [ -n "$REF" ] || { err "one of --report <trivy.json> or --scan <ref> is required"; exit 2; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
raw="$WORK/raw.json"

if [ -n "$REPORT" ]; then
  [ "$CONSUMER" = trivy ] || { err "--report is a trivy report; ${CONSUMER} has no report mode"; exit 2; }
  cp "$REPORT" "$raw"
else
  case "$CONSUMER" in
    trivy)
      args=()
      if [ -n "$VEXOCI" ]; then
        args+=(--vex oci)
      else
        [ -n "$VEXDIR" ] || { err "--scan needs --vex-dir <dir> or --vex-oci"; exit 2; }
        shopt -s nullglob; for f in "$VEXDIR"/*.json; do args+=(--vex "$f"); done; shopt -u nullglob
      fi
      [ -n "$REMOTE" ] && args+=(--image-src remote)
      [ -n "$PLATFORM" ] && args+=(--platform "$PLATFORM")
      trivy image "${args[@]}" --severity "$APERTURE" --pkg-types os,library --show-suppressed \
        --format json --output "$raw" --no-progress --exit-code 0 "$REF" || { err "trivy exited $? scanning ${REF}"; exit 1; }
      ;;
    grype)
      [ -n "$VEXDIR" ] || { err "--scan needs --vex-dir <dir> for grype"; exit 2; }
      args=()
      shopt -s nullglob; for f in "$VEXDIR"/*.json; do args+=(--vex "$f"); done; shopt -u nullglob
      src="$REF"; [ -n "$REMOTE" ] && src="registry:${REF}"
      [ -n "$PLATFORM" ] && args+=(--platform "$PLATFORM")
      grype "$src" "${args[@]}" -o json > "$raw" || { err "grype exited $? scanning ${REF}"; exit 1; }
      ;;
    *) err "no adapter for ${CONSUMER}: declare one here before listing it"; exit 2 ;;
  esac
  [ -s "$raw" ] || { err "${CONSUMER} wrote no output for ${REF}"; exit 1; }
fi

python3 - "$CONSUMER" "$raw" "$OUT" "$APERTURE" <<'PY'
import json, sys
consumer, raw, out, aperture = sys.argv[1:5]
aperture = {s.upper() for s in aperture.split(",") if s}
doc = json.load(open(raw))

def key(purl):
    base = (purl or "").split("?")[0]
    if "@" in base:
        name, _, ver = base.rpartition("@")
        if ver.startswith("v") and len(ver) > 1 and ver[1].isdigit():
            ver = ver[1:]
        base = f"{name}@{ver}"
    return base

rows = []
def add(vuln, purl, suppressed, by, status, severity):
    if not vuln or (severity or "").upper() not in aperture:
        return
    rows.append({"consumer": consumer, "vulnerability": vuln, "purl": purl or "", "key": key(purl),
                 "suppressed": bool(suppressed), "by": by, "status": status or ""})

if consumer == "trivy":
    for r in doc.get("Results") or []:
        for v in r.get("Vulnerabilities") or []:
            add(v.get("VulnerabilityID"), (v.get("PkgIdentifier") or {}).get("PURL"), False, "none", "", v.get("Severity"))
        for m in r.get("ExperimentalModifiedFindings") or []:
            if m.get("Type") not in ("", None, "vulnerability"):
                continue
            f = m.get("Finding") or {}
            src = str(m.get("Source") or "")
            status = str(m.get("Status") or "")
            by = "exception" if "accepted-risk" in src else "vex"
            add(f.get("VulnerabilityID"), (f.get("PkgIdentifier") or {}).get("PURL"), True, by, "" if by == "exception" else status, f.get("Severity"))
elif consumer == "grype":
    for m in doc.get("matches") or []:
        v = m.get("vulnerability") or {}; a = m.get("artifact") or {}
        add(v.get("id"), a.get("purl"), False, "none", "", v.get("severity"))
    for im in doc.get("ignoredMatches") or []:
        m = im.get("match") or {}; v = m.get("vulnerability") or {}; a = m.get("artifact") or {}
        rules = im.get("appliedIgnoreRules") or []
        vex = [r for r in rules if r.get("vex-status")]
        if vex:
            add(v.get("id"), a.get("purl"), True, "vex", vex[0].get("vex-status"), v.get("severity"))
        else:
            add(v.get("id"), a.get("purl"), True, "ignore", "", v.get("severity"))
else:
    print(f"::error::vex-consumer: no normaliser for {consumer}", file=sys.stderr); sys.exit(2)

rows.sort(key=lambda r: (r["vulnerability"], r["key"], r["purl"]))
with open(out, "w") as f:
    for r in rows:
        f.write(json.dumps(r, sort_keys=True) + "\n")
print(f"vex-consumer: {consumer}: {len(rows)} finding(s) in the aperture, {sum(1 for r in rows if r['suppressed'] and r['by'] == 'vex')} suppressed by VEX")
PY
