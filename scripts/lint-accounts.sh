#!/usr/bin/env bash
# lint-accounts.sh [root]
#
# Req 1.4 (review D5, 2026-09-09): every definition under image/ declares a
# non-root runtime account with UID 65532. The criterion had no mechanism:
# nothing read a definition's `accounts:` block, the e2e assertion reads the
# pod's declared securityContext (which the charts set), and a definition
# running as root would have passed every gate. Rules, each a violation by
# name: the block exists; `run-as` names a user; that user is defined under
# `users:` with `uid: 65532` and is not root. Every definition is judged,
# variants included (a -dev image is never published, but a definition
# directory is a runtime image here by construction).
#
# python3 + PyYAML (the lint-accepted-risk.sh precedent); the `# syntax=`
# line is a comment to the parser. Exit 1 on any violation.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ROOT="${ROOT%/}"

python3 - "$ROOT" <<'PY'
import glob, os, sys, yaml
root = sys.argv[1]
files = sorted(glob.glob(os.path.join(root, "image", "*", "image.yaml")))
violations = 0
def err(rel, msg):
    global violations
    print(f"::error file={rel}::lint-accounts: {msg} (Req 1.4)")
    violations += 1
for f in files:
    rel = os.path.relpath(f, root)
    try:
        doc = yaml.safe_load(open(f)) or {}
    except Exception as e:  # noqa: BLE001
        err(rel, f"not parseable YAML: {e}"); continue
    acc = doc.get("accounts") if isinstance(doc, dict) else None
    if not isinstance(acc, dict):
        err(rel, "no accounts block; declare run-as and a nonroot user with uid 65532"); continue
    run_as = acc.get("run-as")
    if not run_as:
        err(rel, "accounts.run-as is missing; the runtime image must run as the nonroot account"); continue
    users = {u.get("name"): u for u in (acc.get("users") or []) if isinstance(u, dict)}
    u = users.get(run_as)
    if run_as == "root" or (u is not None and u.get("uid") == 0):
        err(rel, f"accounts.run-as is '{run_as}', a root account; every runtime image runs as a non-root account with uid 65532"); continue
    if u is None:
        err(rel, f"accounts.run-as names '{run_as}', which accounts.users does not define"); continue
    if u.get("uid") != 65532:
        err(rel, f"account '{run_as}' has uid {u.get('uid')}; the runtime account is uid 65532")
if violations:
    print(f"lint-accounts: {violations} violation(s)")
    sys.exit(1)
print(f"lint-accounts: {len(files)} definition(s) run as a non-root account with uid 65532 (Req 1.4)")
PY
