#!/usr/bin/env bash
# lint-live-evidence.sh [root]
#
# The live-evidence ledger covers every criterion (task 16.1, Req 7.11).
# docs/live-evidence.md records, for every criterion the requirements name,
# the mechanism that criterion rests on and the one live exercise, natural or
# induced, that showed it working, or the reason none has; this lint holds
# that a criterion cannot arrive without its evidence obligation, and that a
# retired number never gets a row back.
#
# Two inputs, both under the root (default: this repository):
#   .specs/dhc-catalogue-mvp/requirements.md
#                the criteria: inside each `### Requirement N:` section,
#                every line `M. ...` is criterion N.M; numbers have gaps
#                (a retired number is never reused), so a number absent
#                from the file is no criterion
#   docs/live-evidence.md
#                the ledger: every table row whose first cell is a criterion
#                number, six cells each:
#                | criterion | mechanism | status | first live exercise | evidence | induced by |
#
# Holds that every criterion has exactly one row, every row names a criterion
# that exists, every row's status is one of exercised, defect, drill 16.N
# (one or more group-16 tasks, `drill 16.4, 16.5`) or unexercised, and every
# row names its mechanism and carries its evidence or its reason. Every
# failure is reported, not just the first. Exit 1 on any failure, exit 2 when
# either input is missing.
set -euo pipefail
[ $# -le 1 ] || { echo "::error::lint-live-evidence: usage: lint-live-evidence.sh [root]" >&2; exit 2; }
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ROOT="${ROOT%/}"
REQS="$ROOT/.specs/dhc-catalogue-mvp/requirements.md"
LEDGER="$ROOT/docs/live-evidence.md"
[ -f "$LEDGER" ] || { echo "::error::lint-live-evidence: no docs/live-evidence.md under ${ROOT}; nothing to hold against the criteria (Req 7.11)" >&2; exit 2; }
[ -f "$REQS" ] || { echo "::error::lint-live-evidence: no .specs/dhc-catalogue-mvp/requirements.md under ${ROOT}; no criteria to cover (Req 7.11)" >&2; exit 2; }

python3 - "$REQS" "$LEDGER" <<'PY'
import re, sys

reqs, ledger = sys.argv[1:3]
REL = "docs/live-evidence.md"
CELLS = 6  # criterion, mechanism, status, first live exercise, evidence, induced by
STATUS = re.compile(r"^(?:exercised|defect|unexercised|drill 16\.\d{1,2}(?:, 16\.\d{1,2})*)$")

# the criteria: N.M for every `M. ...` line inside a `### Requirement N:` section
criteria = set()
section = None
for line in open(reqs, encoding="utf-8"):
    m = re.match(r"^### Requirement (\d+):", line)
    if m:
        section = int(m.group(1)); continue
    if re.match(r"^#{1,3} ", line):  # another chapter or section closes it; `####` stays inside
        section = None; continue
    m = re.match(r"^(\d+)\. ", line)
    if m and section is not None:
        criteria.add(f"{section}.{int(m.group(1))}")

failures = 0
def error(msg):
    global failures
    failures += 1
    print(f"::error file={REL}::live evidence (Req 7.11): {msg}")

# the rows, in file order: every table row whose first cell is a criterion number
rows = {}  # criterion number -> how many rows carry it
counts = {"exercised": 0, "defect": 0, "drill": 0, "unexercised": 0}
for line in open(ledger, encoding="utf-8"):
    m = re.match(r"^\| (\d+\.\d+) \|", line)
    if not m:
        continue
    name = m.group(1)
    rows[name] = rows.get(name, 0) + 1
    s = line.strip()
    s = s[1:] if s.startswith("|") else s
    s = s[:-1] if s.endswith("|") else s
    cells = [c.strip() for c in s.split("|")]
    if len(cells) != CELLS:
        error(f"row {name} has {len(cells)} cells, the ledger's rows have {CELLS}"); continue
    _, mechanism, status, _, evidence, _ = cells
    if name not in criteria:
        error(f"row {name} names no criterion in requirements.md")
    if not mechanism:
        error(f"row {name} names no mechanism")
    if STATUS.match(status):
        counts[status.split(" ")[0]] += 1  # `drill 16.4` counts as drill
    else:
        error(f"row {name} status '{status}' is not exercised, defect, drill 16.N or unexercised")
    if not evidence:
        error(f"row {name} carries no evidence or reason")

# every criterion has exactly one row, in numeric order
for name in sorted(criteria, key=lambda c: tuple(int(x) for x in c.split("."))):
    n = rows.get(name, 0)
    if n == 0:
        error(f"criterion {name} has no ledger row")
    elif n > 1:
        error(f"criterion {name} has {n} ledger rows")

if failures:
    print(f"lint-live-evidence: {failures} failure(s); every criterion has one ledger row, every row a known status and its evidence or reason (Req 7.11)")
    sys.exit(1)
print(f"lint-live-evidence: {len(criteria)} criteria, one ledger row each ({counts['exercised']} exercised, {counts['defect']} defect, {counts['drill']} drill, {counts['unexercised']} unexercised)")
PY
