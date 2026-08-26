#!/usr/bin/env bash
# lint-workflow-policy.sh [root]: compare every workflow's schedule cron and
# permissions blocks against catalogue-policy.yaml's `workflows:` declarations
# (Req 7.10). GitHub reads schedule triggers and permissions only as literal
# workflow YAML, so this lint is what binds the literals to the one committed
# home of declared values (Req 7.7); each mismatch fails by name.
#
# Direction is deliberate: a schedule declared but not yet wired into its
# workflow passes with a notice (task 9.2 wires build.yml's cron), while a
# cron or permissions block present in a workflow must match its declaration
# exactly, and every workflow file must be declared.
#
# YAML via python3 + PyYAML (the lint-accepted-risk.sh precedent; installed by
# validate.yml's yamllint step, present in the devcontainer).
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ROOT="${ROOT%/}"

python3 - "$ROOT" <<'PY'
import glob, os, sys, yaml

root = sys.argv[1]
policy_path = os.path.join(root, "catalogue-policy.yaml")
if not os.path.isfile(policy_path):
    print(f"lint-workflow-policy: no catalogue-policy.yaml under {root}", file=sys.stderr)
    sys.exit(1)
declared = (yaml.safe_load(open(policy_path)) or {}).get("workflows") or {}

failures = 0
def err(wf, msg):
    global failures
    print(f"::error file=.github/workflows/{wf}::lint-workflow-policy: {wf}: {msg} (Req 7.10)")
    failures += 1

for path in sorted(glob.glob(os.path.join(root, ".github", "workflows", "*.yml"))):
    wf = os.path.basename(path)
    doc = yaml.safe_load(open(path)) or {}
    decl = declared.get(wf)
    if decl is None:
        err(wf, "workflow has no declaration in catalogue-policy.yaml's workflows section")
        continue

    # Schedule: PyYAML parses the bare `on:` key as boolean True.
    on = doc.get("on", doc.get(True, {})) or {}
    crons = [e.get("cron") for e in (on.get("schedule") or []) if isinstance(e, dict)]
    want_cron = decl.get("schedule")
    if crons and want_cron is None:
        err(wf, f"schedule trigger '{crons[0]}' is not declared (declaration says none)")
    elif crons and crons[0] != want_cron:
        err(wf, f"schedule trigger '{crons[0]}' differs from declared '{want_cron}'")
    elif len(crons) > 1:
        err(wf, f"carries {len(crons)} schedule triggers; one declared value covers one")
    elif not crons and want_cron:
        print(f"lint-workflow-policy: {wf}: declared schedule '{want_cron}' not yet wired into the workflow (allowed; wire it to close the loop)")

    def diff_perms(where, actual, wanted):
        actual = actual or {}
        wanted = wanted or {}
        keys = sorted(set(actual) | set(wanted))
        bad = [k for k in keys if actual.get(k) != wanted.get(k)]
        if bad:
            detail = ", ".join(f"{k}: workflow says {actual.get(k)!r}, declared {wanted.get(k)!r}" for k in bad)
            err(wf, f"{where} permissions differ: {detail}")

    diff_perms("workflow-default", doc.get("permissions"), decl.get("permissions"))

    decl_jobs = decl.get("jobs") or {}
    for job, spec in (doc.get("jobs") or {}).items():
        if not isinstance(spec, dict) or "permissions" not in spec:
            continue
        if job not in decl_jobs:
            err(wf, f"job '{job}' carries an explicit permissions block with no declaration")
            continue
        diff_perms(f"job '{job}'", spec.get("permissions"), (decl_jobs.get(job) or {}).get("permissions"))
    for job in decl_jobs:
        spec = (doc.get("jobs") or {}).get(job)
        if not isinstance(spec, dict) or "permissions" not in spec:
            err(wf, f"declared job '{job}' permissions are not present in the workflow")

if failures:
    print(f"lint-workflow-policy: {failures} declaration mismatch(es)", file=sys.stderr)
    sys.exit(1)
print("lint-workflow-policy: every workflow schedule and permissions block matches catalogue-policy.yaml")
PY
