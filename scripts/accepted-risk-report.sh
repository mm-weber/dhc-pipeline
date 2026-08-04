#!/usr/bin/env bash
# accepted-risk-report.sh <trivy.json> <accepted-risk.yaml>
#
# Render the accepted-risk half of the scan gate's job summary (Req 6.26, 6.27).
#
# Two things the raw Trivy report cannot tell a reviewer on its own:
#
#   Req 6.27  WHICH BINARY a suppression applied to. An entry scoped to one
#             binary and an entry scoped to the whole image produce the same
#             finding count, so a count cannot distinguish a decision that was
#             argued from one that leaked onto a binary nobody looked at.
#             Trivy carries it as the enclosing Result's Target.
#
#   Req 6.26  WHICH ENTRIES SUPPRESSED NOTHING. Measured against Trivy 0.72.0:
#             a paths: value matching no file is accepted silently, matches
#             nothing, warns nobody and exits 0. That is indistinguishable from
#             an untriaged finding unless the file is compared against the
#             report, which is what this does.
#
# Reporting, never failing: an exception that suppresses nothing leaves nothing
# uncovered, so Req 6.1 is the wrong lever. Same call as the VEX canary warning.
set -uo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: accepted-risk-report.sh <trivy.json> <accepted-risk.yaml>" >&2
  exit 2
fi
TRIVY="$1"
LANE="$2"

# No lane file means nothing is being suppressed, which is the normal state for
# most images and not a condition to report on.
[ -f "$LANE" ] || exit 0
[ -f "$TRIVY" ] || { echo "accepted-risk-report: no such report '$TRIVY'" >&2; exit 2; }

python3 - "$TRIVY" "$LANE" <<'PY'
import json, sys

try:
    import yaml
except ImportError:
    print("::warning::accepted-risk-report: PyYAML missing, cannot check Req 6.26")
    sys.exit(0)

report_path, lane_path = sys.argv[1], sys.argv[2]

with open(report_path) as fh:
    report = json.load(fh)
with open(lane_path) as fh:
    lane = yaml.safe_load(fh) or {}

# Trivy attributes a suppression to the enclosing Result, so the binary is the
# Target, not a field on the finding itself.
suppressed = []
for result in report.get("Results") or []:
    target = result.get("Target", "")
    for mod in result.get("ExperimentalModifiedFindings") or []:
        if not str(mod.get("Source", "")).startswith("triage/accepted-risk/"):
            continue
        finding = mod.get("Finding") or {}
        suppressed.append({
            "cve": finding.get("VulnerabilityID", ""),
            "statement": mod.get("Statement", ""),
            "target": target,
            "pkg": finding.get("PkgName", ""),
        })

if suppressed:
    print("| CVE | Binary | Package | Decision |")
    print("|---|---|---|---|")
    rows = {(s["cve"], s["target"], s["pkg"], s["statement"]) for s in suppressed}
    for cve, target, pkg, statement in sorted(rows):
        print(f"| {cve} | `{target}` | {pkg} | {statement} |")
    print()

# An entry is live if some suppression carries both its id and its statement.
# Statement is what distinguishes two entries inside one file, since Source
# names the file for every entry in it.
applied = {(s["cve"], s["statement"]) for s in suppressed}

for entry in lane.get("vulnerabilities") or []:
    if not isinstance(entry, dict):
        continue
    ident = str(entry.get("id", ""))
    if (ident, str(entry.get("statement", ""))) in applied:
        continue
    paths = ", ".join(str(p) for p in (entry.get("paths") or [])) or "(none)"
    print(f"> **Req 6.26** — `{ident or '?'}` suppressed nothing. Its `paths:` "
          f"({paths}) matched no binary in this image, or the finding is already "
          f"gone. Trivy reports neither case, so this entry is either failing to "
          f"apply the decision it records, or is ready to be removed.")
PY
