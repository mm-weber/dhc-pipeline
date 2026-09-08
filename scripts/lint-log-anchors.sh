#!/usr/bin/env bash
# lint-log-anchors.sh [refs|statements|all] [root]
#
# F13's mechanical link (task 13.6, Req 9.18). triage/LOG.md is prose and
# stays prose; the records the machines read cite it, and this lint holds
# that every citation resolves to a real heading and that every decision
# carries one, so the 1,000-odd lines of reasoning cannot quietly drift away
# from the exceptions and statements that rest on them.
#
# Two halves, run alone or together:
#   refs         every accepted-risk exception's `ref:` (called from
#                lint-accepted-risk.sh, Req 6.7, 6.11)
#   statements   every VEX source statement's log citation, read from
#                status_notes (validate runs this half beside the product lint)
#
# Two citation forms, the ones the records already use:
#   LOG.md#<slug>       a heading's GitHub slug: lowercased, everything but
#                       letters, digits, spaces, dashes and underscores
#                       dropped, spaces to dashes; a dash between spaces is
#                       dropped and its two spaces stay, so the anchor of a
#                       heading written "FIX, then a dash, then stdlib" ends
#                       up "fix--stdlib", double dash, as GitHub renders it
#   LOG.md <YYYY-MM-DD> a day heading (`## <date> ...`) of that date
# A `triage/` prefix is accepted on both. A citation that resolves to nothing
# is named with the nearest heading; a decision with no citation at all is
# named too, because that is the rot F13 called out. Exit 1 on any failure,
# exit 2 when there is no LOG to resolve against.
set -uo pipefail
MODE="${1:-all}"; ROOT="${2:-.}"
case "$MODE" in refs|statements|all) ;; *) echo "::error::lint-log-anchors: usage: lint-log-anchors.sh [refs|statements|all] [root]" >&2; exit 2 ;; esac
LOG="$ROOT/triage/LOG.md"
[ -f "$LOG" ] || { echo "::error::lint-log-anchors: no triage/LOG.md under ${ROOT}; nothing to resolve citations against (Req 9.18)" >&2; exit 2; }

python3 - "$MODE" "$ROOT" <<'PY'
import difflib, glob, json, os, re, sys
import yaml

mode, root = sys.argv[1:3]
log = os.path.join(root, "triage", "LOG.md")

def gh_slug(text):
    t = text.strip().lower()
    t = re.sub(r"[^\w\- ]", "", t)   # GitHub keeps letters, digits, _ and -; drops the rest
    return t.replace(" ", "-")

headings, days = [], set()
for line in open(log, encoding="utf-8"):
    m = re.match(r"^(#{1,6})\s+(.*\S)\s*$", line)
    if not m:
        continue
    text = m.group(2)
    headings.append((gh_slug(text), text))
    d = re.match(r"^(\d{4}-\d{2}-\d{2})\b", text)
    if d and len(m.group(1)) == 2:
        days.add(d.group(1))
slugs = {s for s, _ in headings}
failures = 0
def error(rel, msg):
    global failures
    failures += 1
    print(f"::error file={rel}::LOG anchor (Req 9.18): {msg}")

def resolve(citation):
    """(kind, key, ok): kind slug|date|none."""
    c = (citation or "").strip()
    m = re.match(r"^(?:triage/)?LOG\.md#([A-Za-z0-9._-]+)$", c)
    if m:
        return "slug", m.group(1), m.group(1) in slugs
    m = re.match(r"^(?:triage/)?LOG\.md\s+(\d{4}-\d{2}-\d{2})$", c)
    if m:
        return "date", m.group(1), m.group(1) in days
    return "none", c, False

def nearest(slug):
    cands = difflib.get_close_matches(slug, list(slugs), n=1, cutoff=0.5)
    return f"; nearest: LOG.md#{cands[0]}" if cands else ""

refs = citations = 0
if mode in ("refs", "all"):
    for path in sorted(glob.glob(os.path.join(root, "triage", "accepted-risk", "*.y*ml"))):
        rel = os.path.relpath(path, root)
        try:
            doc = yaml.safe_load(open(path)) or []
        except Exception as e:  # noqa: BLE001
            error(rel, f"unreadable ({e})"); continue
        # Trivy's ignorefile shape: a top-level `vulnerabilities:` list (a bare
        # list is accepted too)
        entries = doc.get("vulnerabilities") if isinstance(doc, dict) else doc
        entries = entries if isinstance(entries, list) else []
        for e in entries:
            if not isinstance(e, dict):
                continue
            ident = str(e.get("id", "?"))
            kind, key, ok = resolve(str(e.get("ref", "") or ""))
            refs += 1
            if ok:
                continue
            if kind == "date":
                error(rel, f"{ident} ref 'LOG.md {key}' names no day heading in triage/LOG.md")
            else:
                error(rel, f"{ident} ref '{e.get('ref', '') or ''}' resolves to no heading in triage/LOG.md{nearest(key) if kind == 'slug' else ''}")

if mode in ("statements", "all"):
    pat = re.compile(r"(?:triage/)?LOG\.md(?:#[A-Za-z0-9._-]+|\s+\d{4}-\d{2}-\d{2})")
    for path in sorted(glob.glob(os.path.join(root, "triage", "vex", "*.json"))):
        rel = os.path.relpath(path, root)
        try:
            doc = json.load(open(path))
        except Exception as e:  # noqa: BLE001
            error(rel, f"unreadable ({e})"); continue
        for s in doc.get("statements") or []:
            vuln = (s.get("vulnerability") or {}).get("name") or (s.get("vulnerability") or {}).get("@id") or "?"
            status = s.get("status") or "?"
            notes = " ".join(str(s.get(k) or "") for k in ("status_notes", "impact_statement", "action_statement", "justification"))
            found = pat.findall(notes)
            citations += 1
            if not found:
                error(rel, f"statement {vuln} ({status}) cites no triage/LOG.md heading; every decision has one")
                continue
            for c in found:
                kind, key, ok = resolve(c.rstrip("."))
                if ok:
                    continue
                if kind == "date":
                    error(rel, f"statement {vuln} ({status}) cites '{c}', and no heading of that day exists in triage/LOG.md")
                else:
                    error(rel, f"statement {vuln} ({status}) cites '{c}', which resolves to no heading in triage/LOG.md{nearest(key)}")

if failures:
    print(f"lint-log-anchors: {failures} citation(s) do not resolve; every exception ref and statement citation must name a triage/LOG.md heading (Req 9.18)")
    sys.exit(1)
parts = []
if mode in ("refs", "all"): parts.append(f"{refs} exception ref(s)")
if mode in ("statements", "all"): parts.append(f"{citations} statement citation(s)")
print(f"lint-log-anchors: {' and '.join(parts)} resolve to LOG.md headings")
PY
