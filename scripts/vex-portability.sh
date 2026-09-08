#!/usr/bin/env bash
# vex-portability.sh --root <dir> --label <text> --out <block.md> [--append] \
#                    --json <block.json> <authoritative.jsonl> [<other.jsonl> ...]
#
# The VEX portability block (task 13.4, Req 9.12). The catalogue's statements
# are written for one scanner's matcher; whether they land in another
# scanner is a measurement, not a promise (review F7). For each statement
# the authoritative consumer suppressed on a scanned artifact (a finding with
# suppressed=true and by=vex in its record, exceptions being the catalogue's
# own decision no other consumer can see), each other declared consumer's
# result, joined on the canonical key vex-consumer.sh emits:
#
#   agree        suppressed there too
#   DIVERGENCE   reported there: the statement did not land in that matcher
#   absent       not in that consumer's findings at all: its database does
#                not carry the advisory for that package, nothing to suppress
#   not measured the consumer's record is missing (its scan failed): named,
#                never read as agreement
#
# Informational: exit 0 whatever the block says, unless catalogue-policy.yaml
# sets consumers.gating true, in which case every divergence is an ::error::
# and the exit is 1 (design Decision 10's fork switch). The markdown goes to
# <block.md> (with --append, a new section under the one heading the file
# already has), the counts and rows to <block.json>.
#
# Refuses (exit 2) a first record that is not the authoritative consumer's:
# the policy file says who is authoritative, not the caller.
set -uo pipefail
ROOT=. LABEL="" OUT="" JSON="" APPEND=""
records=()
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --json) JSON="$2"; shift 2 ;;
    --append) APPEND=1; shift ;;
    --*) echo "::error::vex-portability: unknown option '$1'" >&2; exit 2 ;;
    *) records+=("$1"); shift ;;
  esac
done
[ -n "$LABEL" ] && [ -n "$OUT" ] && [ -n "$JSON" ] && [ "${#records[@]}" -ge 1 ] || {
  echo "::error::vex-portability: usage: --root <dir> --label <text> --out <block.md> [--append] --json <block.json> <authoritative.jsonl> [<other.jsonl> ...]" >&2; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
AUTH=$("$HERE/triage-policy.sh" "$ROOT" authoritative-consumer) || exit 2
GATING=$("$HERE/triage-policy.sh" "$ROOT" consumer-gating) || exit 2
mapfile -t OTHERS < <("$HERE/triage-policy.sh" "$ROOT" other-consumers)

python3 - "$AUTH" "$GATING" "$LABEL" "$OUT" "$JSON" "$APPEND" "${#OTHERS[@]}" "${OTHERS[@]}" "${records[@]}" <<'PY'
import json, os, sys
auth, gating, label, out, jsonp, append = sys.argv[1:7]
n_others = int(sys.argv[7])
others = sys.argv[8:8 + n_others]
records = sys.argv[8 + n_others:]

def load(path):
    rows = []
    if not os.path.exists(path):
        return None
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows

first = load(records[0])
if first is None:
    print(f"::error::vex-portability: no authoritative record at {records[0]}", file=sys.stderr); sys.exit(2)
consumer_of_first = next((r["consumer"] for r in first if r.get("consumer")), auth)
if consumer_of_first != auth:
    print(f"::error::vex-portability: first record must be the authoritative consumer's ({auth}), got {consumer_of_first}", file=sys.stderr); sys.exit(2)

# the statements: what the authoritative consumer suppressed by VEX
statements = {}
for r in first:
    if r.get("suppressed") and r.get("by") == "vex":
        statements[(r["vulnerability"], r["key"])] = r.get("status") or ""

# the other consumers' records, by file order matching the declared list
by_consumer = {}
for path in records[1:]:
    rows = load(path)
    name = None
    if rows is not None:
        name = next((r["consumer"] for r in rows if r.get("consumer")), None)
    if name is None:
        # an empty or missing file: attribute it to the next declared consumer without a record
        for o in others:
            if o not in by_consumer:
                name = o; break
    if name is None:
        continue
    by_consumer[name] = (path, rows)

lines = []
if not append or not os.path.exists(out) or "#### VEX portability (Req 9.12)" not in open(out).read():
    lines.append("#### VEX portability (Req 9.12)")
    lines.append("")
    lines.append(f"For each statement {auth} (authoritative) suppressed, each declared consumer's result: agree, DIVERGENCE (reported there), absent (unknown to that consumer's database). Informational; `consumers.gating` in catalogue-policy.yaml is the switch.")
    lines.append("")

result = {"label": label, "authoritative": auth, "statements": len(statements), "consumers": {}, "rows": []}
failures = []
if not statements:
    lines.append(f"- {label}: no statement suppressed by {auth} today; nothing to compare")
else:
    counts = {o: {"agree": 0, "divergence": 0, "absent": 0, "measured": False} for o in others}
    table = []
    for (vuln, key), status in sorted(statements.items()):
        cells = []
        row = {"vulnerability": vuln, "key": key, "status": status, "results": {}}
        for o in others:
            entry = by_consumer.get(o)
            if entry is None or entry[1] is None:
                cells.append("not measured"); row["results"][o] = "not measured"; continue
            counts[o]["measured"] = True
            rows = entry[1]
            hit = [r for r in rows if r["vulnerability"] == vuln and r["key"] == key]
            if not hit:
                cells.append("absent"); counts[o]["absent"] += 1; row["results"][o] = "absent"
            elif all(r.get("suppressed") for r in hit):
                cells.append("agree"); counts[o]["agree"] += 1; row["results"][o] = "agree"
            else:
                cells.append("**DIVERGENCE**, reported"); counts[o]["divergence"] += 1; row["results"][o] = "divergence"
                failures.append(f"{label}: {vuln} ({key}) suppressed by {auth} is reported by {o}")
        table.append(f"| {vuln} | `{key}` | {status} | " + " | ".join(cells) + " |")
        result["rows"].append(row)
    summary = []
    for o in others:
        c = counts[o]
        if not c["measured"]:
            summary.append(f"{o}: not measured (no record, its scan failed or did not run)")
        else:
            summary.append(f"{o}: {c['agree']} agree, {c['divergence']} DIVERGENCE, {c['absent']} absent")
        result["consumers"][o] = {k: v for k, v in c.items()}
    lines.append(f"- {label}: {len(statements)} statement(s) {auth} suppressed; " + "; ".join(summary))
    lines.append("")
    lines.append("| Finding | Package (canonical) | Status | " + " | ".join(others) + " |")
    lines.append("|---|---|---|" + "---|" * len(others))
    lines.extend(table)
lines.append("")

with open(out, "a" if append else "w") as f:
    f.write("\n".join(lines) + "\n")
with open(jsonp, "w") as f:
    json.dump(result, f, indent=1); f.write("\n")

for msg in failures:
    if gating == "true":
        print(f"::error::vex-portability: {msg} (consumers.gating is true)")
    else:
        print(f"vex-portability: {msg}")
print(f"vex-portability: {label}: {len(statements)} statement(s), {len(failures)} divergence(s)")
sys.exit(1 if failures and gating == "true" else 0)
PY
