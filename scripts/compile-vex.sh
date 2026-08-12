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
import glob, json, os, sys

src, out, image, digest, definition = sys.argv[1:6]
tags = set(sys.argv[6:])
# `definition` is what built this, `image` what it publishes as. They differ for
# a variant, and the report keeps both.

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

for path in sorted(glob.glob(os.path.join(src, "*.json"))):
    with open(path) as fh:
        doc = json.load(fh)

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
            # orders supersession (Req 6.22).
            product["@id"] = f"pkg:oci/{image}@{digest}"
            products.append(product)
        if products:
            st["products"] = products
            statements.append(st)
            compiled += 1

    # An emptied document is a file a scanner reads and learns nothing from.
    if statements:
        doc["statements"] = statements
        with open(os.path.join(out, os.path.basename(path)), "w") as fh:
            json.dump(doc, fh, indent=2)
            fh.write("\n")

print(f"compile-vex: {compiled} statement(s) compiled for {image}@{digest}, {dropped} product(s) dropped")

# Req 6.32. Optional, so every existing caller is unaffected: a workflow that
# wants to render this in a summary asks for it by naming a path.
report = os.environ.get("COMPILE_VEX_REPORT", "")
if report:
    with open(report, "w") as fh:
        json.dump({"image": definition, "product": image, "digest": digest,
                   "tags": sorted(tags), "compiled": compiled,
                   "dropped": dropped, "drops": drops},
                  fh, indent=2)
        fh.write("\n")
PY
