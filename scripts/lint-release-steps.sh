#!/usr/bin/env bash
# lint-release-steps.sh [workflow]
#
# Req 2.26: in the build workflow's release job the rule is the opposite of the
# rescan workflow's (review disposition D1, scripts/lint-rescan-steps.sh). A
# pushed digest whose release-time scan produced no report, or left a platform
# manifest unscanned, is signed by nothing, attested by nothing and carries no
# tag. GitHub's default step condition is success(), which is false after any
# earlier failure, and that default is exactly the fail-closed behaviour the
# release wants: the fail-closed gate, the per-manifest report attestations,
# the OpenVEX compilation, the signing and the tagging are all stopped by a
# failed scan. The rule this lint holds: every step after the step whose id is
# `relscan` keeps that default, so none of them declares a condition
# containing `always()`, `failure()`, `!cancelled()` or `success() ||`, each of
# which would publish the digest anyway. Steps before the scan are the
# producers (metadata, build, manifest enumeration) and are not judged.
#
# Reads the workflow as YAML (PyYAML, the validate job's dependency); a
# missing `relscan` step or an unreadable file is a refusal, not a vacuous
# pass, because a lint that cannot find the boundary it measures from has
# judged no step at all.
# Exit 1 on any violation.
set -euo pipefail

WF="${1:-$(cd "$(dirname "$0")/.." && pwd)/.github/workflows/build.yml}"
[ -f "$WF" ] || { echo "::error::lint-release-steps: ${WF} does not exist; the rule needs the workflow it is measured in (Req 2.26)"; exit 1; }

python3 - "$WF" <<'PY'
import sys, yaml
path = sys.argv[1]
try:
    wf = yaml.safe_load(open(path))
except Exception as e:  # noqa: BLE001
    print(f"::error file={path}::lint-release-steps: not parseable YAML: {e} (Req 2.26)")
    sys.exit(1)
jobs = (wf or {}).get("jobs") or {}
scan_job = next((n for n, j in jobs.items() if any(s.get("id") == "relscan" for s in ((j or {}).get("steps") or []))), None)
if scan_job is None:
    print(f"::error file={path}::lint-release-steps: no step with `id: relscan` in any job; the rule needs the boundary it is measured from, so a workflow whose release job never scans the pushed digest is refused and no step count is reported (Req 2.26)")
    sys.exit(1)
steps = jobs[scan_job].get("steps") or []
scan = next(i for i, s in enumerate(steps) if s.get("id") == "relscan")
# Each of these escapes the default success() condition, so the step would run
# even though the release-time scan it depends on failed.
ESCAPES = ("always()", "failure()", "!cancelled()", "success() ||")
violations = 0
later = steps[scan + 1:]
for s in later:
    name = s.get("name") or s.get("uses") or "<unnamed>"
    cond = str(s.get("if") or "")
    compact = "".join(cond.split())
    hit = next((e for e in ESCAPES if e.replace(" ", "") in compact), None)
    if hit:
        print(f"::error file={path}::lint-release-steps: step '{name}' has if: '{cond}', whose {hit} escapes GitHub's default success() condition; every step after `relscan` stays stopped by a failed release-time scan, because a digest whose scan produced no report is signed by nothing, attested by nothing and carries no tag (Req 2.26)")
        violations += 1
if violations:
    print(f"lint-release-steps: {violations} violation(s)")
    sys.exit(1)
print(f"lint-release-steps: {len(later)} step(s) after the release-time scan keep the default success() condition; a failed scan stops the gate, the attestations, the signing and the tag (Req 2.26)")
PY
