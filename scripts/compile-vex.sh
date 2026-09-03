#!/usr/bin/env bash
# compile-vex.sh <src-dir> <out-dir> <definition> <digest> [tag ...]
#
# Render the hand-authored OpenVEX source in triage/vex/ into the documents a
# scanner is actually given (Req 6.28, 6.29, 6.30).
#
# Why this is not a jq expression in a workflow. A product identifier Trivy does
# not match is completely inert, and inert is indistinguishable from correct.
# Measured on the published grafana image, one real finding, one statement each:
#
#   pkg:oci/grafana@13.0.4-alpine3.23  fixed  -> reported 1, suppressed 0
#   pkg:oci/grafana@sha256:b6987eb...  fixed  -> reported 0, suppressed 1
#
# Trivy builds the product identifier from the image's RepoDigest, so a tag
# never matches one. Source carries a tag because that is what a human can
# review and what git can keep stable; compilation turns it into the digest of
# the image being scanned, which is what Trivy compares. Neither form serves
# both purposes, which is the whole reason a compile step exists.
#
# Two transforms, both of which have to happen per build:
#
#   Req 6.30  DROP a statement whose product names a tag this build is not, or
#             an image this build is not. Without it a claim argued about
#             13.0.4 keeps suppressing on 13.1.1, which nobody examined — that
#             is review finding 2.4.
#   Req 6.29  REWRITE every surviving product to this image's digest. Without
#             it nothing matches at all.
#
# Qualifiers are dropped along the way, which is what build.yml used to do
# inline for upstream trivy#9399: the gate scans a throwaway local registry, so
# a real repository_url never matches there. scripts/lint-vex-product.sh is what
# checks the registry host instead, by exact comparison against the definition.
#
# Dropping is reported, never silent. A statement that vanished and a statement
# that worked look identical in a scan report.
#
# Set COMPILE_VEX_REPORT=<path> to also get that as JSON (Req 6.32): image,
# digest, tags, counts, and one record per drop with its reason. A caller
# rendering a job summary reads that rather than grepping the prose above,
# which would break the first time the wording changes.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/definition-lib.sh
. "$HERE/definition-lib.sh"
# The definition tree this compiles against, rooted at the script rather than at
# the caller's cwd. Keyed on cwd, a caller passing absolute src/out paths from
# anywhere else found no definition and fell back to the directory name — the
# inert product this file exists to prevent, reported as a clean compile. Same
# seam lint-pins.sh and lint-vex-product.sh take as their first argument; here
# every positional slot is spoken for, so it arrives as an environment variable.
ROOT="${COMPILE_VEX_ROOT:-$(cd "$HERE/.." && pwd)}"

if [ "$#" -lt 4 ]; then
  echo "usage: compile-vex.sh <src-dir> <out-dir> <definition> <digest> [tag ...]" >&2
  exit 2
fi
SRC="$1"; OUT="$2"; DEFINITION="$3"; DIGEST="$4"; shift 4

if [ ! -d "$SRC" ]; then
  echo "compile-vex: source directory '$SRC' does not exist — no statement was compiled" >&2
  exit 2
fi
mkdir -p "$OUT"

# The product name is the last path segment of the definition's `image:`, not
# the definition's directory name. Those were the same string for every
# definition until image/valkey-compat/, which publishes to .../valkey as a
# `-compat` tag (docs/CONVENTIONS.md, "Naming"). Trivy builds its root component
# purl from the scanned image's RepoDigest, so on a compat build it reads
# `valkey` — keyed on the directory this stamped `valkey-compat` into every
# product, which matches nothing and reports as a clean compile.
#
# The definition name stays the reporting identity: two definitions now share
# one repository, and a summary labelled with the published name would render
# rows nothing tells apart. Falling back to the given name when no definition is
# in reach is the pre-variant contract, which the tests rely on.
IMAGE="$DEFINITION"
DEF_FILE="$ROOT/image/${DEFINITION}/image.yaml"
if [ -f "$DEF_FILE" ]; then
  repo="$(published_repository "$DEF_FILE")"
  [ -n "$repo" ] && IMAGE="${repo##*/}"
fi

# Task 10.2 (Req 6.38). The exception file is keyed by definition, exactly as
# scan-image.sh keys its --ignorefile, so the suppressions in the attested
# report and the statements compiled from them come from one file. Absent is
# the common case (most images carry no exceptions) and compiles as before.
EXCEPTIONS="${COMPILE_VEX_EXCEPTIONS:-$ROOT/triage/accepted-risk/${DEFINITION}.yaml}"
COMPILE_VEX_EXCEPTIONS="$EXCEPTIONS" python3 - "$SRC" "$OUT" "$IMAGE" "$DIGEST" "$DEFINITION" "$@" <<'PY'
import datetime, fnmatch, glob, json, os, re, sys

src, out, image, digest, definition = sys.argv[1:6]
tags = set(sys.argv[6:])
# `definition` is what built this, `image` what it publishes as. They differ for
# a variant, and the report keeps both.

# One document per digest, covering the index and every platform manifest
# (Req 6.29, ADR 0003): several OpenVEX attestations on one digest make
# `trivy --vex oci` apply one of them at random (ADR 0004), so "exactly one" is
# the invariant, not tidiness. The manifest digests arrive by environment
# because every positional slot is spoken for, the seam this script already
# uses for COMPILE_VEX_ROOT and COMPILE_VEX_REPORT.
digests = [digest] + [d for d in os.environ.get("COMPILE_VEX_MANIFEST_DIGESTS", "").split() if d != digest]

# Req 2.12 / 6.37. The release-time scan reports are a named compiler input:
# whatever they still report is uncovered, and it is published as
# under_investigation rather than passing unremarked. A path that does not
# exist is a usage error, never "nothing uncovered": that silence is the
# inert-looks-correct failure this lane exists to prevent.
scan_reports = os.environ.get("COMPILE_VEX_SCAN_REPORTS", "").split()
for path in scan_reports:
    if not os.path.isfile(path):
        print(f"compile-vex: scan report '{path}' does not exist, so what it would have "
              f"reported is unknown; refusing to compile as if nothing were uncovered", file=sys.stderr)
        sys.exit(2)

# The previously attested document, so a finding already stated keeps its first
# seen timestamp instead of resetting on every rebuild (cluster B's clocks).
previous = os.environ.get("COMPILE_VEX_PREVIOUS", "")
first_seen = {}
# Req 6.40. The statements the compiler itself wrote last time (affected,
# under_investigation), keyed by finding and package, so this compile can keep
# their timestamp and record a change in last_updated rather than restating.
previous_written = {}
def vuln_name(st):
    vuln = st.get("vulnerability")
    return (vuln.get("name") if isinstance(vuln, dict) else vuln) or ""
def first_subcomponent(st):
    for product in st.get("products") or []:
        for sub in product.get("subcomponents") or []:
            if sub.get("@id"):
                return sub["@id"]
    return ""
if previous:
    if not os.path.isfile(previous):
        print(f"compile-vex: previously attested document '{previous}' does not exist", file=sys.stderr)
        sys.exit(2)
    with open(previous) as fh:
        for st in (json.load(fh).get("statements") or []):
            name = vuln_name(st)
            ts = st.get("timestamp")
            if name and ts and name not in first_seen:
                first_seen[name] = ts
            if name and st.get("status") in ("affected", "under_investigation"):
                previous_written.setdefault((name, first_subcomponent(st)), st)
def previous_for(cve, purl):
    """The statement this compiler wrote for (finding, package) last time, or
    the closest one it wrote for the finding: a previous document may predate
    subcomponent scoping, and first seen is a property of the finding."""
    for key in ((cve, purl), (cve, "")):
        if key in previous_written:
            return previous_written[key]
    for (name, _), st in previous_written.items():
        if name == cve:
            return st
    return None
def carry_forward(st, purl, stamp):
    """Req 6.40: timestamp is first seen, for life; last_updated records a change
    to the decision-bearing content (status, action statement, packages)."""
    cve = vuln_name(st)
    prev = previous_for(cve, purl)
    st["timestamp"] = (prev.get("timestamp") if prev and prev.get("timestamp") else
                       first_seen.get(cve, stamp))
    if prev is None:
        return
    def shape(x):
        return (x.get("status"), x.get("action_statement"),
                tuple(sorted(sub.get("@id", "") for p in (x.get("products") or [])
                             for sub in (p.get("subcomponents") or []))))
    if shape(prev) != shape(st):
        st["last_updated"] = stamp
    elif prev.get("last_updated"):
        st["last_updated"] = prev["last_updated"]

def parse(pid):
    """(name, version) for a pkg:oci purl, or (None, None) if it is not one."""
    if not pid.startswith("pkg:oci/"):
        return None, None
    rest = pid[len("pkg:oci/"):]
    for sep in ("#", "?"):                 # subpath and qualifiers are not identity
        rest = rest.split(sep)[0]
    if "@" in rest:
        name, _, version = rest.rpartition("@")
        return name, version
    return rest, ""

compiled = dropped = 0
drops = []

def drop(kind, cve, pid, reason):
    """Req 6.32. Printed for a human reading the log AND kept structured, so a
    job summary never has to grep prose that changes wording.

    `kind` classifies rather than filters, because the caller is what knows
    which drops are worth rendering: 'image' is a statement for another
    catalogue image and is pure noise, 'tag' is a claim scoped to another
    release and is the one a reviewer has to see."""
    global dropped
    print(f"compile-vex: dropped {cve} product '{pid}' — {reason}")
    drops.append({"kind": kind, "cve": cve, "product": pid, "reason": reason})
    dropped += 1

merged = []          # every surviving source statement, in file then document order
covered = set()       # CVEs a source statement answers, so 2.12 does not restate them
author = "dhc-pipeline triage"

for path in sorted(glob.glob(os.path.join(src, "*.json"))):
    with open(path) as fh:
        doc = json.load(fh)
    if doc.get("author"):
        author = doc["author"]

    statements = []
    for st in doc.get("statements") or []:
        vuln = st.get("vulnerability")
        cve = (vuln.get("name") if isinstance(vuln, dict) else vuln) or "?"
        products = []
        for product in st.get("products") or []:
            pid = str(product.get("@id", ""))
            name, version = parse(pid)
            if name is None:
                drop("malformed", cve, pid, "not a pkg:oci purl, so it identifies nothing this scan contains")
                continue
            if name != image:
                drop("image", cve, pid, f"names image '{name}', building '{image}'")
                continue
            if version and version not in tags:
                built = ", ".join(sorted(tags)) or "(none)"
                drop("tag", cve, pid, f"tag '{version}' is not a tag of this build ({built})")
                continue
            # Req 6.29. Everything else is the claim and carries through
            # untouched: subcomponents scope it to one package, and timestamp
            # orders supersession (Req 6.22). One product per digest, so a
            # consumer pinning the index or a platform manifest reads the same
            # claim.
            for d in digests:
                copy = dict(product)
                copy["@id"] = f"pkg:oci/{image}@{d}"
                products.append(copy)
        if products:
            st["products"] = products
            statements.append(st)
            compiled += 1
            if st.get("status") in ("not_affected", "fixed"):
                covered.add(cve)

    merged.extend(statements)

# Req 6.38 / 6.41. The exceptions: real findings we ship anyway, for a bounded
# time. Each unexpired one that the attested report lists as suppressed is
# published as `affected` carrying the decision; an expired one is published as
# nothing, and the finding it named, now reported again, is under_investigation
# naming the lapse. Neither is coverage (Req 6.35): Trivy suppresses only
# not_affected and fixed, and the gate counts only those.
exceptions_path = os.environ.get("COMPILE_VEX_EXCEPTIONS", "")
exceptions = []
if exceptions_path and os.path.isfile(exceptions_path):
    import yaml
    with open(exceptions_path) as fh:
        doc = yaml.safe_load(fh) or {}
    for e in doc.get("vulnerabilities") or []:
        if isinstance(e, dict) and e.get("id"):
            exceptions.append(e)
exceptions_name = os.path.basename(exceptions_path) if exceptions_path else ""
def report_date(stamp):
    """The calendar date of a report timestamp, in UTC. Trivy writes RFC 3339
    with nanoseconds and a zone offset, which fromisoformat cannot read raw."""
    if not stamp:
        return None
    text = re.sub(r"(\.\d{6})\d+", r"\1", stamp.strip()).replace("Z", "+00:00")
    try:
        return datetime.datetime.fromisoformat(text).astimezone(datetime.timezone.utc).date()
    except ValueError:
        return None
def as_date(value):
    if isinstance(value, datetime.datetime):
        return value.date()
    if isinstance(value, datetime.date):
        return value
    try:
        return datetime.date.fromisoformat(str(value)[:10])
    except ValueError:
        return None
def expired(entry, today):
    """Trivy's rule and the lint's: an entry is live through its expiry day."""
    exp = as_date(entry.get("expired_at"))
    return exp is not None and today is not None and exp < today
def scoped_to(entry, target, purl):
    paths = entry.get("paths") or []
    if paths and not any(fnmatch.fnmatch(target, p) for p in paths):
        return False
    purls = entry.get("purls") or []
    if purls and purl and not any(purl == p or purl.startswith(p + "@") or purl.startswith(p + "?")
                                  for p in purls):
        return False
    return True
def action_statement(entry):
    treatment = entry.get("treatment", "accept")
    text = str(entry.get("statement", "")).strip()
    # House style writes the statement as "<treatment>: ..."; do not say it twice.
    head = text if text.startswith(f"{treatment}:") else f"{treatment}: {text}"
    parts = [head.rstrip()]
    if entry.get("issue"):
        parts.append(f"Upstream issue: {entry['issue']}.")
    if entry.get("paths"):
        parts.append("Binaries: " + ", ".join(entry["paths"]) + ".")
    if entry.get("expired_at"):
        parts.append(f"Expires: {as_date(entry['expired_at']) or entry['expired_at']}.")
    return " ".join(parts)
# The clock an exception is measured against is the attested report's, not the
# runner's wall clock, so a compile is reproducible from its named inputs.
report_stamps = []
for path in scan_reports:
    with open(path) as fh:
        report_stamps.append(json.load(fh).get("CreatedAt") or "")
compile_stamp = max(report_stamps) if report_stamps else \
    datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
today = report_date(compile_stamp)
# Req 2.12. Every finding the release-time scan still reports is uncovered by
# construction (VEX and unexpired exceptions were applied to that scan), so it
# is published as under_investigation, derived from the report and carrying its
# timestamp. Keyed by vulnerability and package so two platform manifests
# reporting the same finding state it once.
investigating = {}
affected = {}
lapsed = 0
for path in scan_reports:
    with open(path) as fh:
        rep = json.load(fh)
    stamp = rep.get("CreatedAt") or ""
    basename = os.path.basename(path)
    for result in rep.get("Results") or []:
        target = result.get("Target") or ""
        for v in result.get("Vulnerabilities") or []:
            cve = v.get("VulnerabilityID")
            if not cve or cve in covered:
                continue
            ident = v.get("PkgIdentifier") or {}
            purl = ident.get("PURL") or ""
            key = (cve, purl or v.get("PkgName") or "")
            if key in investigating:
                continue
            note = (f"uncovered at release time in this digest's attested "
                    f"release-time scan report ({basename}); awaiting a triage decision")
            # Req 6.41. If an expired exception named this finding, the lapse is
            # why it is reported again, and the note says so: the decision
            # clock restarts, first seen does not.
            lapses = [e for e in exceptions if e.get("id") == cve and expired(e, today)
                      and scoped_to(e, target, purl)]
            if lapses:
                e = lapses[0]
                note = (f"accepted-risk exception ({e.get('treatment', 'accept')}, decided "
                        f"{as_date(e.get('decided_at')) or 'undated'}) expired on "
                        f"{as_date(e.get('expired_at'))}; the finding is still listed in this "
                        f"digest's attested scan report ({basename}); awaiting a new decision")
                lapsed += 1
            st = {
                "vulnerability": {"name": cve},
                "products": [{"@id": f"pkg:oci/{image}@{d}"} for d in digests],
                "status": "under_investigation",
                "status_notes": note,
            }
            if purl:
                for product in st["products"]:
                    product["subcomponents"] = [{"@id": purl}]
            # First seen, not "seen again": a rebuild must not reset the clock
            # a decision is measured against.
            carry_forward(st, purl, stamp)
            investigating[key] = st
        # Req 6.38. What the ignorefile suppressed is in the report by name
        # (--show-suppressed, Req 6.55), each finding attributed to its entry's
        # statement text. Only the file this compile was handed counts: a
        # suppression from another source is not one of ours to publish.
        for mod in result.get("ExperimentalModifiedFindings") or []:
            if mod.get("Type", "vulnerability") != "vulnerability" or mod.get("Status") != "ignored":
                continue
            if exceptions_name and os.path.basename(str(mod.get("Source") or "")) != exceptions_name:
                continue
            f = mod.get("Finding") or {}
            cve = f.get("VulnerabilityID")
            if not cve or cve in covered:
                continue
            purl = (f.get("PkgIdentifier") or {}).get("PURL") or ""
            key = (cve, purl or f.get("PkgName") or "")
            live = [e for e in exceptions if e.get("id") == cve and not expired(e, today)
                    and scoped_to(e, target, purl)]
            exact = [e for e in live if e.get("statement") == mod.get("Statement")]
            entry = (exact or live or [None])[0]
            if entry is None:
                print(f"compile-vex: {cve} is suppressed in {basename} by {exceptions_name} but no "
                      f"unexpired entry there names it for {target}; publishing nothing for it",
                      file=sys.stderr)
                continue
            if key in affected:
                # The same package at the same version in another binary, under
                # its own entry (one entry per binary, Req 6.23): one statement
                # per finding and package, carrying every decision made about it.
                have = affected[key]["action_statement"]
                more = action_statement(entry)
                if more not in have:
                    affected[key]["action_statement"] = f"{have} Also: {more}"
                continue
            st = {
                "vulnerability": {"name": cve},
                "products": [{"@id": f"pkg:oci/{image}@{d}"} for d in digests],
                "status": "affected",
                "action_statement": action_statement(entry),
                "status_notes": (f"accepted-risk exception in {exceptions_name}; real and shipped "
                                 f"for a bounded time, not coverage (Req 6.8)"),
            }
            decided = as_date(entry.get("decided_at"))
            if decided:
                st["action_statement_timestamp"] = f"{decided.isoformat()}T00:00:00Z"
            if purl:
                for product in st["products"]:
                    product["subcomponents"] = [{"@id": purl}]
            carry_forward(st, purl, stamp)
            affected[key] = st
merged.extend(affected[k] for k in sorted(affected))
merged.extend(investigating[k] for k in sorted(investigating))

# One document per digest, written even with zero statements (ADR 0003):
# vexctl, Trivy, cosign and Kyverno all accept an empty statement list, and a
# published digest that carries no OpenVEX attestation at all cannot tell
# "compiled nothing" from "never compiled".
stamps = [st.get("timestamp") for st in merged if st.get("timestamp")]
document = {
    "@context": "https://openvex.dev/ns/v0.2.0",
    "@id": f"https://openvex.dev/docs/dhc/{image}@{digest}",
    "author": author,
    "version": 1,
    "timestamp": max(stamps) if stamps else
                 datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "statements": merged,
}
with open(os.path.join(out, f"{image}.openvex.json"), "w") as fh:
    json.dump(document, fh, indent=2)
    fh.write("\n")

print(f"compile-vex: {compiled} statement(s) compiled for {image}@{digest}, "
      f"{len(affected)} affected from exceptions, {len(investigating)} under_investigation "
      f"({lapsed} lapsed exception(s)), {dropped} product(s) dropped")

# Req 6.32. Optional, so every existing caller is unaffected: a workflow that
# wants to render this in a summary asks for it by naming a path.
report = os.environ.get("COMPILE_VEX_REPORT", "")
if report:
    with open(report, "w") as fh:
        json.dump({"image": definition, "product": image, "digest": digest,
                   "digests": digests, "tags": sorted(tags), "compiled": compiled,
                   "under_investigation": len(investigating),
                   "affected": len(affected), "lapsed": lapsed,
                   "dropped": dropped, "drops": drops},
                  fh, indent=2)
        fh.write("\n")
PY
