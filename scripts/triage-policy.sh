#!/usr/bin/env bash
# triage-policy.sh <root> <query> [arg]
#
# The one reader of catalogue-policy.yaml's `triage` section (task 10.1,
# Req 6.49): the decision aperture, the exception ceilings, the KEV ceiling,
# the expiry warning window and the KEV feed. Every consumer reads through
# this script (the accepted-risk lint, the exception tiering in both arms,
# scan-image.sh's --severity, the workflows' counts and the issue filer's
# ranking), so a fork edits one file and every gate follows (Req 7.7).
#
#   aperture           severities in rank order, comma-joined (CRITICAL,HIGH)
#   ceiling <SEV>      exception ceiling for one aperture severity, in days
#   largest-ceiling    the outer bound the lint enforces from decided_at
#   kev-ceiling        the ceiling for a finding listed in CISA KEV, in days
#   expiry-warning     the window the rescan reports lapsing exceptions in
#   kev-feed           the KEV catalogue URL both arms fetch
#   resolved-labels    the closing labels per evidence grade, as JSON
#                      {grade: {name, color, description}} (task 10.6, Req 6.56)
#   consumers          the VEX consumers, "<name>\t<authoritative>" per line
#                      in declared order (task 13.4, Req 9.11)
#   authoritative-consumer   the one consumer marked authoritative
#   other-consumers    every other consumer, one per line
#   consumer-gating    true|false: whether a portability divergence fails a
#                      run (a fork switch; false here, design Decision 10)
#
# Durations are whole days written as `<n>d`: the exception schema carries
# dates, so a sub-day ceiling would be unenforceable; a fork wanting one
# switches decided_at and expired_at to datetimes and this reader with them.
# A section with holes (a missing key, an aperture severity without a
# ceiling, a malformed duration) refuses with exit 2 and names the hole,
# because a gate that reads a default instead of a declared value has stopped
# being declared.
set -euo pipefail

err() { printf '::error::triage-policy: %s\n' "$1" >&2; }
if [ "$#" -lt 2 ]; then
  err "usage: triage-policy.sh <root> <aperture|ceiling <SEV>|largest-ceiling|kev-ceiling|expiry-warning|kev-feed|resolved-labels|consumers|authoritative-consumer|other-consumers|consumer-gating>"
  exit 2
fi
ROOT="$1"; QUERY="$2"; ARG="${3:-}"
POLICY="$ROOT/catalogue-policy.yaml"
[ -f "$POLICY" ] || { err "no catalogue-policy.yaml under ${ROOT}"; exit 2; }

python3 - "$POLICY" "$QUERY" "$ARG" <<'PY'
import re, sys, yaml
policy, query, arg = sys.argv[1], sys.argv[2], sys.argv[3]
def refuse(msg):
    print(f"::error::triage-policy: {msg} (catalogue-policy.yaml triage section, Req 6.49)", file=sys.stderr)
    sys.exit(2)
doc = yaml.safe_load(open(policy)) or {}
t = doc.get("triage") or {}
def days(key, value):
    m = re.fullmatch(r"(\d+)d", str(value).strip())
    if not m:
        refuse(f"{key} is '{value}'; durations are whole days written as <n>d")
    return int(m.group(1))
aperture = t.get("aperture")
if not isinstance(aperture, list) or not aperture:
    refuse("aperture is missing or empty")
aperture = [str(s) for s in aperture]
ceilings = t.get("ceilings") or {}
for sev in aperture:
    if sev not in ceilings:
        refuse(f"aperture severity {sev} has no ceiling")
if query == "aperture":
    print(",".join(aperture))
elif query == "ceiling":
    if arg not in aperture:
        refuse(f"{arg or '(none)'} is not in the aperture {aperture}")
    print(days(f"ceilings.{arg}", ceilings[arg]))
elif query == "largest-ceiling":
    print(max(days(f"ceilings.{s}", ceilings[s]) for s in aperture))
elif query == "kev-ceiling":
    if "kev_ceiling" not in t: refuse("kev_ceiling is missing")
    print(days("kev_ceiling", t["kev_ceiling"]))
elif query == "expiry-warning":
    if "expiry_warning" not in t: refuse("expiry_warning is missing")
    print(days("expiry_warning", t["expiry_warning"]))
elif query == "kev-feed":
    if not t.get("kev_feed"): refuse("kev_feed is missing")
    print(t["kev_feed"])
elif query == "resolved-labels":
    import json
    labels = t.get("resolved_labels") or {}
    for grade in ("fixed", "removed", "not_affected", "accepted", "absent"):
        entry = labels.get(grade)
        if not isinstance(entry, dict) or not entry.get("name"):
            refuse(f"resolved_labels.{grade} has no name")
    print(json.dumps({g: {"name": str(e["name"]), "color": str(e.get("color", "")), "description": str(e.get("description", ""))}
                      for g, e in labels.items()}, sort_keys=True))
elif query in ("consumers", "authoritative-consumer", "other-consumers", "consumer-gating"):
    def refuse_c(msg):
        print(f"::error::triage-policy: {msg} (catalogue-policy.yaml consumers section, Req 9.11)", file=sys.stderr)
        sys.exit(2)
    c = doc.get("consumers") or {}
    lst = c.get("list") if isinstance(c, dict) else None
    if not isinstance(lst, list) or not lst:
        refuse_c("consumers.list is missing")
    names, flags = [], []
    for e in lst:
        if not isinstance(e, dict) or not e.get("name") or not isinstance(e.get("authoritative"), bool):
            refuse_c("every consumer needs a name and a boolean authoritative flag")
        names.append(str(e["name"])); flags.append(e["authoritative"])
    if len(names) != len(set(names)):
        refuse_c("consumer names must be unique")
    if sum(flags) != 1:
        refuse_c(f"exactly one consumer must be authoritative, {sum(flags)} are")
    if query == "consumers":
        for n, f in zip(names, flags):
            print(f"{n}\t{'true' if f else 'false'}")
    elif query == "authoritative-consumer":
        print(names[flags.index(True)])
    elif query == "other-consumers":
        for n, f in zip(names, flags):
            if not f: print(n)
    else:
        g = c.get("gating", False)
        if not isinstance(g, bool):
            refuse_c("consumers.gating must be true or false")
        print("true" if g else "false")
else:
    print(f"::error::triage-policy: unknown query '{query}'", file=sys.stderr); sys.exit(2)
PY
