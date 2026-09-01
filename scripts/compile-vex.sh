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

python3 - "$SRC" "$OUT" "$IMAGE" "$DIGEST" "$DEFINITION" "$@" <<'PY'
import datetime, glob, json, os, sys

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
if previous:
    if not os.path.isfile(previous):
        print(f"compile-vex: previously attested document '{previous}' does not exist", file=sys.stderr)
        sys.exit(2)
    with open(previous) as fh:
        for st in (json.load(fh).get("statements") or []):
            vuln = st.get("vulnerability")
            name = (vuln.get("name") if isinstance(vuln, dict) else vuln) or ""
            ts = st.get("timestamp")
            if name and ts and name not in first_seen:
                first_seen[name] = ts

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

# Req 2.12. Every finding the release-time scan still reports is uncovered by
# construction (VEX and unexpired exceptions were applied to that scan), so it
# is published as under_investigation, derived from the report and carrying its
# timestamp. Keyed by vulnerability and package so two platform manifests
# reporting the same finding state it once.
investigating = {}
for path in scan_reports:
    with open(path) as fh:
        rep = json.load(fh)
    stamp = rep.get("CreatedAt") or ""
    for result in rep.get("Results") or []:
        for v in result.get("Vulnerabilities") or []:
            cve = v.get("VulnerabilityID")
            if not cve or cve in covered:
                continue
            ident = v.get("PkgIdentifier") or {}
            purl = ident.get("PURL") or ""
            key = (cve, purl or v.get("PkgName") or "")
            if key in investigating:
                continue
            st = {
                "vulnerability": {"name": cve},
                "products": [{"@id": f"pkg:oci/{image}@{d}"} for d in digests],
                "status": "under_investigation",
                # First seen, not "seen again": a rebuild must not reset the
                # clock a decision is measured against.
                "timestamp": first_seen.get(cve, stamp),
                "status_notes": (f"uncovered at release time in this digest's attested "
                                 f"release-time scan report ({os.path.basename(path)}); "
                                 f"awaiting a triage decision"),
            }
            if purl:
                for product in st["products"]:
                    product["subcomponents"] = [{"@id": purl}]
            investigating[key] = st

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
      f"{len(investigating)} under_investigation, {dropped} product(s) dropped")

# Req 6.32. Optional, so every existing caller is unaffected: a workflow that
# wants to render this in a summary asks for it by naming a path.
report = os.environ.get("COMPILE_VEX_REPORT", "")
if report:
    with open(report, "w") as fh:
        json.dump({"image": definition, "product": image, "digest": digest,
                   "digests": digests, "tags": sorted(tags), "compiled": compiled,
                   "under_investigation": len(investigating),
                   "dropped": dropped, "drops": drops},
                  fh, indent=2)
        fh.write("\n")
PY
