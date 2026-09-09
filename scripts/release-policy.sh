#!/usr/bin/env bash
# release-policy.sh <root> <query>
#
# The one reader of catalogue-policy.yaml's `release` section (review
# disposition D3, 2026-09-09; the triage-policy.sh shape for the switches
# Req 2.13, 2.14, 2.17, 2.21 and 7.7 name):
#
#   public           true|false   the public-release state (Req 2.21, 2.4)
#   fail-closed      true|false   sign nothing on an uncovered finding (2.13)
#   publish-policy   on-change|always   what a scheduled rebuild publishes (2.15, 2.17)
#   schedule         the daily rebuild's cron, five fields (2.14)
#   platforms        the admitted platforms, os/arch, one per line (7.7)
#   check            every switch above, refusing the first hole; prints them
#
# Each switch is returned only when it is written exactly as the criteria
# name it. build.yml used to read them with yq as raw strings and compare
# them to 'true' and 'on-change', so `yes`, `True` or `on_change` silently
# took the fail-open branch (every rebuild published, no release ever held).
# The two booleans are checked against the file's own text, not a parsed
# value: PyYAML reads `yes` as true and mikefarah's yq reads it as the string
# "yes", and a switch two readers disagree on is not declared. A hole (a
# missing key, a value outside the accepted set, a malformed platform or
# cron) refuses with exit 2 naming the key, the value and what is accepted,
# never a default.
set -euo pipefail

err() { printf '::error::release-policy: %s\n' "$1" >&2; }
if [ "$#" -ne 2 ]; then
  err "usage: release-policy.sh <root> <public|fail-closed|publish-policy|schedule|platforms|check>"
  exit 2
fi
ROOT="${1%/}"; QUERY="$2"
POLICY="$ROOT/catalogue-policy.yaml"
[ -f "$POLICY" ] || { err "no catalogue-policy.yaml under ${ROOT}"; exit 2; }

python3 - "$POLICY" "$QUERY" <<'PY'
import re, sys, yaml
policy, query = sys.argv[1], sys.argv[2]
def refuse(msg):
    print(f"::error file=catalogue-policy.yaml::release-policy: {msg} (catalogue-policy.yaml release section, Req 7.7)", file=sys.stderr)
    sys.exit(2)
text = open(policy).read()
doc = yaml.safe_load(text) or {}
rel = doc.get("release")
if not isinstance(rel, dict):
    refuse("the release section is missing")

def raw_token(key):
    # The scalar as written, so both YAML dialects in play read it alike.
    m = re.search(r"^\s+" + re.escape(key) + r":\s*(?:&\w+\s+)?([^#\n]*?)\s*(?:#.*)?$", text, re.M)
    return m.group(1) if m else None

def boolean(key):
    if key not in rel:
        refuse(f"{key} is missing; write true or false")
    tok = raw_token(key)
    if tok not in ("true", "false"):
        refuse(f"{key} is '{tok if tok is not None else rel.get(key)}'; write exactly true or false, unquoted (yes, on, True and 1 are read differently by the two YAML readers in play)")
    return tok

def publish_policy():
    v = rel.get("publish_policy")
    if v is None:
        refuse("publish_policy is missing; write on-change or always")
    if v not in ("on-change", "always"):
        refuse(f"publish_policy is '{v}'; write on-change or always (Req 2.15, 2.17)")
    return v

def schedule():
    v = rel.get("schedule")
    if v is None:
        refuse("schedule is missing; write the daily rebuild's cron (Req 2.14)")
    if not isinstance(v, str) or len(v.split()) != 5:
        refuse(f"schedule is '{v}'; write a five-field cron such as \"47 4 * * *\" (Req 2.14)")
    return v

def platforms():
    v = rel.get("platforms")
    if not isinstance(v, list) or not v:
        refuse("platforms is missing or empty; list the admitted os/arch pairs (Req 7.7)")
    out = []
    for p in v:
        if not isinstance(p, str) or not re.fullmatch(r"[a-z0-9]+/[a-z0-9]+", p):
            refuse(f"platform '{p}' is not an os/arch pair such as linux/amd64 (Req 2.1, 7.7)")
        out.append(p)
    return out

if query == "public":
    print(boolean("public"))
elif query == "fail-closed":
    print(boolean("fail_closed"))
elif query == "publish-policy":
    print(publish_policy())
elif query == "schedule":
    print(schedule())
elif query == "platforms":
    print("\n".join(platforms()))
elif query == "check":
    pub, fc, pp, sch, pl = boolean("public"), boolean("fail_closed"), publish_policy(), schedule(), platforms()
    print(f"release-policy: public={pub} fail_closed={fc} publish_policy={pp} schedule=\"{sch}\" {len(pl)} platform(s): {', '.join(pl)}")
else:
    refuse(f"unknown query '{query}'; one of public, fail-closed, publish-policy, schedule, platforms, check")
PY
