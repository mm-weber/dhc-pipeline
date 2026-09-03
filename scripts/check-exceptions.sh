#!/usr/bin/env bash
# check-exceptions.sh gate   <root> <image> <trivy.json> <kev.json>
# check-exceptions.sh rescan <root> <reports-dir> <kev.json>
#
# Exception ceilings tiered by what the finding actually is (task 10.1):
#
#   KEV-listed  -> the policy's kev_ceiling, whatever the severity: CISA says
#                  it is being exploited, and an exception that outlives that
#                  window is a decision nobody re-made (Req 6.50, 6.51)
#   in a report -> the ceiling for the finding's severity there (an uncovered
#                  finding counts too: the exception may not have matched)
#   no finding  -> the largest applicable ceiling: the entry excuses nothing
#                  today, but its clock is still bounded
#
# breach = expired_at - decided_at > tier, in whole days. The lint
# (lint-accepted-risk.sh) bounds every entry by the LARGEST ceiling before
# any scan exists; this is the per-finding tightening that needs a report.
#
# gate: one image, the PR build's report (Req 6.50). rescan: every UNEXPIRED
# exception in every file, against the day's reports for that image (files
# named <image>__*.json in the supported reports directory), because severity
# is re-rated and KEV lists grow after the decision (Req 6.51). Both fail on
# any breach, naming file, exception and tier.
#
# The KEV set is an input, never fetched here; a missing or unparseable file
# is a NON-EVALUATION and refuses with exit 2. The callers turn that into
# "the feed is unavailable, fail closed" (Req 6.59, 6.60): evaluating with an
# empty KEV set would quietly hand every exploited finding the widest tier.
set -euo pipefail

err() { printf '::error::check-exceptions: %s\n' "$1" >&2; }
MODE="${1:-}"
case "$MODE" in
  gate)   [ "$#" -eq 5 ] || { err "usage: check-exceptions.sh gate <root> <image> <trivy.json> <kev.json>"; exit 2; }
          ROOT="$2"; IMAGE="$3"; REPORTS="$4"; KEV="$5" ;;
  rescan) [ "$#" -eq 4 ] || { err "usage: check-exceptions.sh rescan <root> <reports-dir> <kev.json>"; exit 2; }
          ROOT="$2"; IMAGE=""; REPORTS="$3"; KEV="$4" ;;
  *) err "usage: check-exceptions.sh gate|rescan ..."; exit 2 ;;
esac

HERE="$(cd "$(dirname "$0")" && pwd)"
APERTURE=$("$HERE/triage-policy.sh" "$ROOT" aperture)
KEV_DAYS=$("$HERE/triage-policy.sh" "$ROOT" kev-ceiling)
LARGEST=$("$HERE/triage-policy.sh" "$ROOT" largest-ceiling)
CEILINGS=""
IFS=',' read -r -a sevs <<< "$APERTURE"
for s in "${sevs[@]}"; do CEILINGS="${CEILINGS}${s}=$("$HERE/triage-policy.sh" "$ROOT" ceiling "$s") "; done

python3 - "$MODE" "$ROOT" "$IMAGE" "$REPORTS" "$KEV" "$APERTURE" "$KEV_DAYS" "$LARGEST" "$CEILINGS" <<'PY'
import datetime, glob, json, os, sys, yaml
mode, root, image, reports, kev_path, aperture, kev_days, largest, ceilings = sys.argv[1:10]
aperture = aperture.split(",")
kev_days, largest = int(kev_days), int(largest)
ceilings = {kv.split("=")[0]: int(kv.split("=")[1]) for kv in ceilings.split()}
def err(msg): print(f"::error::check-exceptions: {msg}", file=sys.stderr)

try:
    kev = {v.get("cveID") for v in (json.load(open(kev_path)).get("vulnerabilities") or [])}
except Exception as e:
    err(f"no usable KEV set at {kev_path} ({type(e).__name__}); the tiers cannot be evaluated, refusing rather than evaluating without it (Req 6.59, 6.60)")
    sys.exit(2)

def severities(paths):
    """cve -> highest severity (by aperture rank) across reports, from both uncovered
    and ignorefile-suppressed findings."""
    rank = {s: len(aperture) - i for i, s in enumerate(aperture)}
    best = {}
    for p in paths:
        try:
            doc = json.load(open(p))
        except Exception:
            continue
        for r in doc.get("Results") or []:
            found = [(v.get("VulnerabilityID"), v.get("Severity")) for v in r.get("Vulnerabilities") or []]
            found += [((m.get("Finding") or {}).get("VulnerabilityID"), (m.get("Finding") or {}).get("Severity"))
                      for m in r.get("ExperimentalModifiedFindings") or []]
            for cve, sev in found:
                if cve and (cve not in best or rank.get(sev, 0) > rank.get(best[cve], 0)):
                    best[cve] = sev
    return best

def as_date(v):
    try:
        return datetime.date.fromisoformat(str(v))
    except Exception:
        return None

today = datetime.datetime.now(datetime.timezone.utc).date()
lane = os.path.join(root, "triage", "accepted-risk")
if mode == "gate":
    files = [os.path.join(lane, f"{image}.yaml")]
    if not os.path.exists(files[0]):
        print(f"check-exceptions: {image}: no accepted-risk file, nothing to tier")
        sys.exit(0)
    report_paths = {image: [reports]}
else:
    files = sorted(glob.glob(os.path.join(lane, "*.yaml")) + glob.glob(os.path.join(lane, "*.yml")))
    report_paths = {}
    for f in files:
        name = os.path.splitext(os.path.basename(f))[0]
        report_paths[name] = sorted(glob.glob(os.path.join(reports, f"{name}__*.json")))

breaches, checked = [], 0
for f in files:
    name = os.path.splitext(os.path.basename(f))[0]
    rel = os.path.relpath(f, root)
    sev_of = severities(report_paths.get(name, []))
    doc = yaml.safe_load(open(f)) or {}
    for e in doc.get("vulnerabilities") or []:
        cve = e.get("id", "?")
        expiry, decided = as_date(e.get("expired_at")), as_date(e.get("decided_at"))
        if expiry is None:
            continue  # the lint's problem, not a tier
        if mode == "rescan" and expiry < today:
            continue  # lapsed: Req 6.10 reports it, Req 6.51 is about the unexpired
        checked += 1
        if decided is None:
            breaches.append(f"{rel}: {cve} has no usable decided_at, so its ceiling cannot be measured")
            continue
        span = (expiry - decided).days
        if cve in kev:
            tier, why = kev_days, "listed in CISA KEV"
        elif cve in sev_of and sev_of[cve] in ceilings:
            tier, why = ceilings[sev_of[cve]], f"{sev_of[cve]} in the scan report"
        else:
            tier, why = largest, "no finding matched, largest applicable ceiling"
        if span > tier:
            breaches.append(f"{rel}: {cve} runs {span} days from {decided} to {expiry}, over its {tier}-day ceiling ({why})")
        else:
            print(f"check-exceptions: ok {name} {cve}: {span} days within the {tier}-day ceiling ({why})")

for b in breaches:
    err(b)
if breaches:
    err(f"{len(breaches)} exception(s) over their tier across {checked} checked (Req 6.50/6.51)")
    sys.exit(1)
print(f"check-exceptions: {checked} exception(s) within their tiers")
PY
