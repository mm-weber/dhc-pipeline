#!/usr/bin/env bash
# lint-accepted-risk.sh [root] — enforce the risk-treatment lane (Req 6.11, 6.12).
#
# triage/accepted-risk/<image>.yaml is a native Trivy ignorefile: the only place
# in the repo where a real, reachable HIGH/CRITICAL is allowed to stop failing
# the gate. Trivy itself enforces exactly one thing about it — that an entry past
# its expired_at stops suppressing (verified, and silently: nothing is logged).
# Everything that makes such an entry *reviewable* is ours to enforce:
#
#   Req 6.11 — every entry names a treatment, an owner, the reasoning it came
#              from, why avoidance and remediation were unavailable, and an
#              expiry no more than 90 days out.
#   Req 6.12 — no Trivy ignore file lives anywhere else, because Trivy picks up
#              .trivyignore from the working directory by default and that path
#              has no owner, no expiry and no review trail.
#
# The reasoning stays in triage/LOG.md; this file carries only the fields the
# gate and a reviewer need. See triage/README.md.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
LANE="triage/accepted-risk"
MAX_DAYS=90      # Req 6.11 ceiling
NOTICE_DAYS=14   # Req 6.10 notice window
violations=0

# --- Req 6.12: no suppression channel outside the lane ----------------------
# Vendored trees are not ours to police; temp/ is gitignored scratch space.
while IFS= read -r -d '' f; do
  rel="${f#"$ROOT"/}"
  echo "::error file=${rel}::risk treatment (Req 6.12): Trivy ignore file outside ${LANE}/ — a finding is suppressed here with no owner, no expiry and no review trail. Move the decision into ${LANE}/<image>.yaml (see triage/README.md)"
  violations=$((violations + 1))
done < <(find "$ROOT" \
              \( -name .git -o -name node_modules -o -name temp -o -path "$ROOT/$LANE" \) -prune -o \
              -type f -name '.trivyignore*' -print0)

# --- Req 6.11: the lane's own entries ---------------------------------------
PYSRC=$(cat <<'PY'
import datetime
import re
import sys

path, rel, max_days, notice_days = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])

try:
    import yaml
except ImportError:
    print(f"::error file={rel}::risk treatment (Req 6.11): PyYAML is required to lint the accepted-risk lane")
    sys.exit(1)

REQUIRED = ["id", "treatment", "owner", "ref", "blocked", "statement", "expired_at"]
TREATMENTS = ("accept", "transfer")
WHY = {
    "id": "the CVE or advisory this exception covers",
    "treatment": "accept or transfer",
    "owner": "who carries this risk",
    "ref": "the triage/LOG.md entry holding the reasoning",
    "blocked": "why avoidance and remediation were unavailable",
    "statement": "the one-line rationale Trivy renders in its report",
    "expired_at": "the date this decision stops applying",
}

text = open(path, encoding="utf-8").read()
lines = text.splitlines()

try:
    doc = yaml.safe_load(text) or {}
except yaml.YAMLError as exc:
    print(f"::error file={rel}::risk treatment (Req 6.11): not valid YAML — {exc}")
    sys.exit(1)

if not isinstance(doc, dict):
    print(f"::error file={rel}::risk treatment (Req 6.11): expected a mapping with a 'vulnerabilities' list")
    sys.exit(1)

entries = doc.get("vulnerabilities") or []
today = datetime.datetime.now(datetime.timezone.utc).date()
errors = 0


def line_of(ident):
    """Anchor the annotation on the entry's own id line so review lands on it."""
    if ident:
        pattern = re.compile(r"id:\s*['\"]?" + re.escape(str(ident)))
        for number, line in enumerate(lines, 1):
            if pattern.search(line):
                return number
    return 1


def as_date(value):
    # PyYAML resolves an unquoted YYYY-MM-DD to a date; anything else is a string.
    if isinstance(value, datetime.datetime):
        return value.date()
    if isinstance(value, datetime.date):
        return value
    try:
        return datetime.date.fromisoformat(str(value).strip())
    except ValueError:
        return None


for index, entry in enumerate(entries):
    if not isinstance(entry, dict):
        print(f"::error file={rel}::risk treatment (Req 6.11): entry {index} is not a mapping")
        errors += 1
        continue

    ident = entry.get("id")
    label = ident if ident else f"entry {index}"
    line = line_of(ident)

    for field in REQUIRED:
        value = entry.get(field)
        if value is None or (isinstance(value, str) and not value.strip()):
            print(f"::error file={rel},line={line}::risk treatment (Req 6.11): {label} is missing '{field}' ({WHY[field]})")
            errors += 1

    treatment = entry.get("treatment")
    if treatment is not None and treatment not in TREATMENTS:
        print(f"::error file={rel},line={line}::risk treatment (Req 6.11): {label} has treatment '{treatment}' — must be accept or transfer. Avoiding the component is a definition change and fixing it is a bump PR (Req 6.5); neither belongs here")
        errors += 1
    if treatment == "transfer" and not entry.get("issue"):
        print(f"::error file={rel},line={line}::risk treatment (Req 6.11): {label} is a transfer but names no 'issue' — a transfer is an acceptance with an external owner, so the tracker it waits on is what makes it one")
        errors += 1

    raw = entry.get("expired_at")
    if raw is None:
        continue
    expiry = as_date(raw)
    if expiry is None:
        print(f"::error file={rel},line={line}::risk treatment (Req 6.11): {label} has expired_at '{raw}' — not a YYYY-MM-DD date, so Trivy will never expire it")
        errors += 1
        continue

    days = (expiry - today).days
    if days < 0:
        print(f"::error file={rel},line={line}::risk treatment (Req 6.11): {label} expired_at {expiry} is in the past — Trivy already counts this finding again, so re-decide the risk or drop the entry")
        errors += 1
    elif days > max_days:
        print(f"::error file={rel},line={line}::risk treatment (Req 6.11): {label} expired_at {expiry} is {days} days out — more than {max_days} days is an indefinite acceptance wearing a date")
        errors += 1
    elif days <= notice_days:
        owner = entry.get("owner", "?")
        print(f"::warning file={rel},line={line}::risk treatment: {label} expires in {days} days ({expiry}) — owner {owner}")

sys.exit(1 if errors else 0)
PY
)

if [ -d "$ROOT/$LANE" ]; then
  while IFS= read -r -d '' f; do
    rel="${f#"$ROOT"/}"

    # The filename is the scope: it names the image whose scan these exceptions
    # apply to. Per-image rather than one shared file, so accepting a finding for
    # grafana can never silently cover cert-manager, whose exposure to the same
    # module is a different question nobody answered.
    name="$(basename "$f")"; name="${name%.*}"
    if [ ! -f "$ROOT/image/$name/image.yaml" ]; then
      echo "::error file=${rel}::risk treatment (Req 6.11): no image definition 'image/${name}/image.yaml' — the filename names the image these exceptions apply to, so a typo suppresses nothing and says nothing"
      violations=$((violations + 1))
      continue
    fi

    if out=$(python3 -c "$PYSRC" "$f" "$rel" "$MAX_DAYS" "$NOTICE_DAYS" 2>&1); then
      :
    else
      violations=$((violations + 1))
    fi
    if [ -n "$out" ]; then
      printf '%s\n' "$out"
    fi
  done < <(find "$ROOT/$LANE" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0)
fi

if [ "$violations" -gt 0 ]; then
  echo "lint-accepted-risk: ${violations} violation(s) — see triage/README.md (risk treatment)"
  exit 1
fi
echo "lint-accepted-risk: risk-treatment lane satisfied"
