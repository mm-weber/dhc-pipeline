#!/usr/bin/env bash
# check-revocations.sh <revocations.yaml> <enumeration.tsv> <out.json>
#
# The revocation record against the rescan's enumeration (task 13.3;
# Req 9.5 to 9.7). A catalogue tag that still references a recorded digest,
# as its index or as one of its platform manifests, is a failure of the run,
# one line per tag naming the digest, the platform, the revocation date and
# the advisory. A recorded digest no tag references is what a revocation
# looks like the day after: frozen, pullable by digest, listed in the status
# issue.
#
# The record at <out.json> carries every entry (dates as strings) and the
# referenced tags; the status tool reads the entries from it, so the YAML is
# parsed in exactly one place. Shape errors are the schema's business
# (triage/revocations.schema.yaml, validate.yml, Req 9.6); this script
# refuses a file it cannot read or that carries no list (exit 2) and exits 1
# when a tag references a revoked digest.
set -uo pipefail
RECORD="${1:?usage: check-revocations.sh <revocations.yaml> <enumeration.tsv> <out.json>}"
ENUM="${2:?usage: check-revocations.sh <revocations.yaml> <enumeration.tsv> <out.json>}"
OUT="${3:?usage: check-revocations.sh <revocations.yaml> <enumeration.tsv> <out.json>}"

python3 - "$RECORD" "$ENUM" "$OUT" <<'PY'
import json, sys
import yaml

record_path, enum_path, out_path = sys.argv[1:4]
try:
    with open(record_path) as f:
        doc = yaml.safe_load(f)
except Exception as e:  # noqa: BLE001
    print(f"::error::revocations: unreadable ({record_path}: {e})")
    sys.exit(2)
if not isinstance(doc, dict) or not isinstance(doc.get("revocations"), list):
    print(f"::error::revocations: no revocations list in {record_path}")
    sys.exit(2)
entries = [e for e in doc["revocations"] if isinstance(e, dict)]
revoked = {e["digest"]: e for e in entries if e.get("digest")}

# (image, tag, digest) -> how the tag reaches the digest: "index" or a platform
hits = {}
with open(enum_path) as f:
    for line in f:
        cols = line.rstrip("\n").split("\t")
        if len(cols) < 5 or not cols[0]:
            continue
        repo, tag, index_digest, platform, manifest = cols[:5]
        if index_digest in revoked:
            hits.setdefault((repo, tag, index_digest), set()).add("index")
        if manifest in revoked:
            hits.setdefault((repo, tag, manifest), set()).add(platform)

referenced = []
for (repo, tag, digest), vias in sorted(hits.items()):
    e = revoked[digest]
    platforms = sorted(v for v in vias if v != "index")
    how = "as its index" if not platforms else "as its " + ", ".join(platforms) + " platform manifest"
    print(f"::error::{repo}:{tag} references revoked digest {digest} {how} "
          f"(revoked {e.get('date')}, {e.get('advisory')}); the tag must move or the version go (Req 9.7)")
    referenced.append({"image": repo, "tag": tag, "digest": digest})

with open(out_path, "w") as f:
    json.dump({"revocations": entries, "referenced": referenced}, f, indent=1, default=str)
    f.write("\n")
print(f"revocations: {len(entries)} recorded, {len(referenced)} referenced by a catalogue tag")
sys.exit(1 if referenced else 0)
PY
