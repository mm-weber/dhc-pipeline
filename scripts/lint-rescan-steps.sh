#!/usr/bin/env bash
# lint-rescan-steps.sh [workflow]
#
# Review disposition D1 (2026-09-09): in the rescan workflow every step after
# the scan is a daily assertion or a publication, and each of them must run
# whether or not an unrelated earlier step failed. GitHub's default step
# condition is success(), which is false after any earlier failure, so a
# designed persistent failure (an upstream signal that moved, register M18)
# or a KEV feed outage used to suspend the visibility invariant, the
# admission proof, the posture checks, the smoke test and the status issue
# for as long as it lasted. The rule this lint holds: every step after the
# step whose id is `scan` declares an `if:` that contains `always()`, stating
# its real data dependency beside it (`steps.<producer>.outcome ==
# 'success'`) and refusing by name inside the step when an input file is
# missing. Steps before the scan are the producers (login, install,
# enumerate) and are not judged.
#
# Reads the workflow as YAML (PyYAML, the validate job's dependency); a
# missing scan step or an unreadable file is a refusal, not a vacuous pass.
# Exit 1 on any violation.
set -euo pipefail

WF="${1:-$(cd "$(dirname "$0")/.." && pwd)/.github/workflows/rescan.yml}"
[ -f "$WF" ] || { echo "::error::lint-rescan-steps: ${WF} does not exist"; exit 1; }

python3 - "$WF" <<'PY'
import sys, yaml
path = sys.argv[1]
try:
    wf = yaml.safe_load(open(path))
except Exception as e:  # noqa: BLE001
    print(f"::error file={path}::lint-rescan-steps: not parseable YAML: {e}")
    sys.exit(1)
jobs = (wf or {}).get("jobs") or {}
if len(jobs) != 1:
    print(f"::error file={path}::lint-rescan-steps: expected one job, found {len(jobs)}")
    sys.exit(1)
steps = list(jobs.values())[0].get("steps") or []
scan = next((i for i, s in enumerate(steps) if s.get("id") == "scan"), None)
if scan is None:
    print(f"::error file={path}::lint-rescan-steps: no step with `id: scan`; the rule needs the boundary it is measured from")
    sys.exit(1)
violations = 0
later = steps[scan + 1:]
for s in later:
    name = s.get("name") or s.get("uses") or "<unnamed>"
    cond = str(s.get("if") or "")
    if "always()" not in cond:
        what = "declares no if: (it needs one containing always())" if not cond else f"has if: '{cond}' without always()"
        print(f"::error file={path}::lint-rescan-steps: step '{name}' {what}; every step after the scan runs regardless of earlier failures and refuses by name on a missing input (review disposition D1)")
        violations += 1
if violations:
    print(f"lint-rescan-steps: {violations} violation(s)")
    sys.exit(1)
print(f"lint-rescan-steps: {len(later)} step(s) after the scan carry always(); no daily assertion or publication is suspended by an unrelated failure")
PY
