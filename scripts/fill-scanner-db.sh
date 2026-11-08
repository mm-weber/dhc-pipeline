#!/usr/bin/env bash
# fill-scanner-db.sh <predicate.json>
#
# The vulnerability database's origin and timestamp, written into a
# cosign-vuln predicate right after conversion (Req 6.55).
#
# `trivy convert --format cosign-vuln` leaves scanner.db.uri and
# scanner.db.version empty (measured on trivy 0.72.0 and 0.75.0), so the
# attested report names the scanner but not the database it matched against,
# and a consumer cannot tell findings from a week-old database apart from
# findings from today's. Two facts on the runner close that gap, and they come
# from different places: the database's UpdatedAt, which
# `trivy version --format json` reports, and the repository the database was
# pulled from, which trivy records nowhere at all, so the declared
# TRIVY_DB_REPOSITORY is the only honest source for the origin.
#
# Nothing else in the predicate moves: the document is loaded, those two
# fields are set, and the result is written beside the target and moved into
# place, so a failure never leaves a truncated predicate where an attestable
# one was.
#
# Exits 0 once both fields are filled, 0 when the predicate already carries
# them and nothing is written, 2 with no argument, 2 when no database origin is
# declared and 2 when trivy reports no database timestamp.
set -euo pipefail

PRED="${1:-}"
[ -n "$PRED" ] || { echo "usage: fill-scanner-db.sh <predicate.json>" >&2; exit 2; }

# Refused before the predicate is read and before trivy is asked anything: an
# undeclared origin would land as an empty db.uri, which attests a claim about
# where the database came from that says nothing while looking filled. Trivy
# records nowhere which repository it pulled the database from, so there is no
# second source to fall back on.
[ -n "${TRIVY_DB_REPOSITORY:-}" ] || {
  echo "::error::fill-scanner-db: TRIVY_DB_REPOSITORY is unset or empty, so the database origin is not declared; trivy records nowhere which repository it pulled the database from, and an empty scanner.db.uri would attest a claim about the origin that says nothing (Req 6.55)" >&2
  exit 2
}

VERSION_JSON=$(trivy version --format json)

# Read before the predicate is opened, so a timestamp trivy did not report is
# refused here and the rewrite's python only ever receives a value that exists:
# a missing fact then cannot be mistaken for a failure to write. The version
# output is the only source for the timestamp, so there is nothing to fall back
# on; an empty scanner.db.version would attest a claim about which database
# matched that says nothing while looking filled.
DB_UPDATED=$(python3 -c 'import json,sys; print(((json.loads(sys.argv[1]) or {}).get("VulnerabilityDB") or {}).get("UpdatedAt") or "")' "$VERSION_JSON")
[ -n "$DB_UPDATED" ] || {
  echo "::error::fill-scanner-db: trivy version --format json carries no vulnerability database timestamp (no VulnerabilityDB.UpdatedAt), so there is no timestamp to attest, and an empty scanner.db.version would attest a claim about which database matched that says nothing (Req 6.55)" >&2
  exit 2
}

python3 - "$PRED" "${TRIVY_DB_REPOSITORY:-}" "$DB_UPDATED" <<'PY'
import json, os, sys

pred_path, uri, version = sys.argv[1:4]

with open(pred_path) as fh:
    doc = json.load(fh)
db = doc.setdefault("scanner", {}).setdefault("db", {})

# What the conversion already wrote about the scanner's own database wins: a
# trivy that fills these fields knows which repository it actually pulled the
# database from, while TRIVY_DB_REPOSITORY only names the one the run was
# configured with. Both facts are still required before this point, so a
# predicate that needs no filling is not a way around the refusals. Decided
# before the dump and the replace, so the file is not even reformatted, and
# said out loud, so a reader of the run can tell a field this script filled
# from one it declined to touch.
if db.get("uri") and db.get("version"):
    print(
        f"fill-scanner-db: {pred_path} left alone, the scanner already names "
        f"its database: {db['uri']} (updated {db['version']})"
    )
    raise SystemExit(0)

db["uri"] = uri
db["version"] = version

tmp = pred_path + ".tmp"
with open(tmp, "w") as fh:
    json.dump(doc, fh, indent=2)
    fh.write("\n")
os.replace(tmp, pred_path)

print(f"fill-scanner-db: {pred_path} -> db {uri} (updated {version})")
PY
