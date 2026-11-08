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
# Exits 0 once both fields are filled, 2 with no argument and 2 when no
# database origin is declared.
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

python3 - "$PRED" "${TRIVY_DB_REPOSITORY:-}" "$VERSION_JSON" <<'PY'
import json, os, sys

pred_path, uri, version_json = sys.argv[1:4]
version = json.loads(version_json)["VulnerabilityDB"]["UpdatedAt"]

with open(pred_path) as fh:
    doc = json.load(fh)
db = doc.setdefault("scanner", {}).setdefault("db", {})
db["uri"] = uri
db["version"] = version

tmp = pred_path + ".tmp"
with open(tmp, "w") as fh:
    json.dump(doc, fh, indent=2)
    fh.write("\n")
os.replace(tmp, pred_path)

print(f"fill-scanner-db: {pred_path} -> db {uri} (updated {version})")
PY
