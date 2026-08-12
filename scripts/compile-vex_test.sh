#!/usr/bin/env bash
# Tests for scripts/compile-vex.sh — Req 6.28, 6.29, 6.30.
#
# What makes this worth a compiler rather than a jq expression: a product
# identifier Trivy does not match is completely inert, and inert is
# indistinguishable from correct. Measured on the published image, one real
# finding, one statement each:
#
#   pkg:oci/grafana@13.0.4-alpine3.23  fixed  -> reported 1, suppressed 0
#   pkg:oci/grafana@sha256:b6987eb...  fixed  -> reported 0, suppressed 1
#
# Trivy builds the product identifier from the RepoDigest, so a tag never
# matches. Source carries the tag because that is what a human can review;
# compilation turns it into the digest, which is what Trivy compares.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
COMPILE="$HERE/compile-vex.sh"
DIGEST="sha256:b6987eb3910fe3f4a05011f76f76c5d56728017a6db1afb491d7f4ba51ff182e"
FAILURES=0
SB=""

fresh() { SB=$(mktemp -d); mkdir -p "$SB/src" "$SB/out"; }

# A source document in the shape triage/vex/ actually holds.
src() { # $1 = filename, $2 = product @id, $3 = status, [$4 = second product @id]
  local extra=""
  [ -n "${4:-}" ] && extra=",{\"@id\":\"$4\",\"subcomponents\":[{\"@id\":\"pkg:golang/example.com/m\"}]}"
  cat > "$SB/src/$1" <<JSON
{"@context":"https://openvex.dev/ns/v0.2.0","@id":"https://openvex.dev/docs/public/t",
 "author":"test","version":1,
 "statements":[{"vulnerability":{"name":"CVE-2026-00001"},
   "products":[{"@id":"$2","subcomponents":[{"@id":"pkg:golang/github.com/grafana/tempo"}]}$extra],
   "status":"$3","timestamp":"2026-08-04T00:00:00Z"}]}
JSON
}

run() { "$COMPILE" "$SB/src" "$SB/out" grafana "$DIGEST" 13.1.1-alpine3.23 13-alpine3.23 2>&1; }

# products() prints every compiled product @id across all output documents.
products() { cat "$SB/out"/*.json 2>/dev/null | jq -r '.statements[]?.products[]?."@id"' 2>/dev/null; }

check() { # name, expected, actual
  if [ "$2" = "$3" ]; then echo "ok   $1"
  else echo "FAIL $1: expected '$2', got '$3'"; FAILURES=$((FAILURES+1)); fi
}
contains() { # name, haystack, needle
  if grep -qF "$3" <<<"$2"; then echo "ok   $1"
  else echo "FAIL $1: missing '$3' in:"; echo "$2" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); fi
}

# --- Req 6.29: the product becomes the scanned image's digest ----------------

# 1: a versionless source product claims every build, so it compiles for this one.
fresh
src a.json "pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" not_affected
run >/dev/null
check "versionless product gets the digest" "pkg:oci/grafana@$DIGEST" "$(products)"

# 2: a source tag matching the build is the same claim, scoped to this release.
fresh
src a.json "pkg:oci/grafana@13.1.1-alpine3.23?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" fixed
run >/dev/null
check "matching tag is replaced by the digest" "pkg:oci/grafana@$DIGEST" "$(products)"

# 3: qualifiers go. Trivy compares repository_url exactly and the gate scans a
#    throwaway local registry, so a real repository_url never matches there
#    (upstream trivy#9399). lint-vex-product.sh is what checks the host instead.
fresh
src a.json "pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" not_affected
run >/dev/null
check "qualifiers are stripped" "pkg:oci/grafana@$DIGEST" "$(products)"

# --- Req 6.30: a claim does not outlive the release it was argued about ------

# 4: THE case behind review finding 2.4. A statement argued about 13.0.4 must
#    not suppress on 13.1.1, which nobody examined. Anchored against a document
#    that does survive, so an empty output cannot pass this.
fresh
src a.json "pkg:oci/grafana@13.0.4-alpine3.23?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" fixed
src b.json "pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" not_affected
run >/dev/null
check "non-matching tag is dropped, matching one kept" "pkg:oci/grafana@$DIGEST" "$(products)"

# 5: dropping is reported. A silent drop is the failure this whole lane exists
#    to prevent, and it looks exactly like a statement that worked.
fresh
src a.json "pkg:oci/grafana@13.0.4-alpine3.23?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" fixed
out=$(run)
contains "a dropped statement is reported" "$out" "13.0.4-alpine3.23"
contains "the drop names the CVE" "$out" "CVE-2026-00001"

# 6: a statement about another image is dropped, not restamped onto this one.
#    Anchored the same way.
fresh
src a.json "pkg:oci/valkey?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fvalkey" not_affected
src b.json "pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" not_affected
run >/dev/null
check "another image's statement is dropped" "pkg:oci/grafana@$DIGEST" "$(products)"

# 7: a document left with no statements is not written at all — an empty
#    document is a file Trivy reads and learns nothing from. Named rather than
#    counted, so this cannot pass by writing nothing at all.
fresh
src a.json "pkg:oci/grafana@13.0.4-alpine3.23?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" fixed
src b.json "pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" not_affected
run >/dev/null
check "emptied document is not written, surviving one is" "b.json" "$(ls "$SB/out" | tr '\n' ' ' | sed 's/ $//')"

# --- the parts that must survive compilation --------------------------------

# 8: subcomponents are what scope a suppression to one package. Losing them
#    would widen every statement to the whole image.
fresh
src a.json "pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" not_affected
run >/dev/null
check "subcomponent survives" "pkg:golang/github.com/grafana/tempo" \
  "$(cat "$SB/out"/*.json | jq -r '.statements[0].products[0].subcomponents[0]."@id"')"

# 9: status and timestamp are the claim and its supersession order (Req 6.22).
fresh
src a.json "pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" fixed
run >/dev/null
check "status survives"    "fixed"                "$(cat "$SB/out"/*.json | jq -r '.statements[0].status')"
check "timestamp survives" "2026-08-04T00:00:00Z" "$(cat "$SB/out"/*.json | jq -r '.statements[0].timestamp')"

# 10: one statement, two products, one of them another image. The statement
#     survives with only the product that applies.
fresh
src a.json "pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" not_affected \
          "pkg:oci/valkey?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fvalkey"
run >/dev/null
check "only the applicable product survives" "pkg:oci/grafana@$DIGEST" "$(products)"

# --- inputs that are not decisions ------------------------------------------

# 11: no source documents is a normal state, not a failure.
fresh
out=$(run); rc=$?
check "empty source dir exits 0" "0" "$rc"

# 12: a missing digest cannot produce a matching product, so it is a usage
#     error rather than a document full of unmatchable statements.
fresh
src a.json "pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" not_affected
"$COMPILE" "$SB/src" "$SB/out" grafana >/dev/null 2>&1; rc=$?
if [ "$rc" -ne 0 ]; then echo "ok   missing digest is a usage error"
else echo "FAIL missing digest is a usage error: exit 0"; FAILURES=$((FAILURES+1)); fi

# 13: a source directory that is not there is not a clean tree. Compiling
#     nothing and reporting success is the same invisible failure one level up.
fresh
"$COMPILE" "$SB/nope" "$SB/out" grafana "$DIGEST" 13.1.1-alpine3.23 >/dev/null 2>&1; rc=$?
if [ "$rc" -ne 0 ]; then echo "ok   missing source dir is an error"
else echo "FAIL missing source dir is an error: exit 0"; FAILURES=$((FAILURES+1)); fi

# 14: a product that is not a pkg:oci purl matches no container image, and the
#     reason it was dropped has to say that rather than blame the image name.
fresh
src a.json "pkg:golang/github.com/grafana/tempo" not_affected
src b.json "pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" not_affected
out=$(run)
contains "a non-oci product is dropped as such" "$out" "not a pkg:oci purl"
check "a non-oci product does not reach the output" "pkg:oci/grafana@$DIGEST" "$(products)"

# --- Req 6.32: what was dropped has to be readable by something -------------
#
# The drop lines above are prose on stdout, which is fine for a human reading a
# log and useless to a job summary. A workflow that greps prose breaks the first
# time the wording changes, so the counts and reasons are also emitted as JSON
# when COMPILE_VEX_REPORT names a path. This is what stops the rescan's
# fail-soft path being indistinguishable from its success path — the same
# defect as an inert statement, one level up.

run_report() { COMPILE_VEX_REPORT="$SB/report.json" run; }
rjq() { jq -r "$1" "$SB/report.json" 2>/dev/null; }

# 15: the report records what compiled and against what
fresh
src a.json "pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" not_affected
run_report >/dev/null
check "report names the image"     "grafana"  "$(rjq '.image')"
check "report names the digest"    "$DIGEST"  "$(rjq '.digest')"
check "report counts compiled"     "1"        "$(rjq '.compiled')"
check "report counts dropped"      "0"        "$(rjq '.dropped')"

# 16: a drop is recorded with the reason, not just counted. A count says
#     something vanished; only the reason says whether that was correct.
fresh
src a.json "pkg:oci/grafana@13.0.4-alpine3.23?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" fixed
src b.json "pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" not_affected
run_report >/dev/null
check "report counts the drop"      "1"                "$(rjq '.dropped')"
check "the drop names its CVE"      "CVE-2026-00001"   "$(rjq '.drops[0].cve')"
contains "the drop quotes the product" "$(rjq '.drops[0].product')" "13.0.4-alpine3.23"
contains "the drop gives a reason"     "$(rjq '.drops[0].reason')" "not a tag of this build"

# 17: drops are classified, because they are not equally interesting. A
#     statement for another catalogue image was never going to apply and is
#     noise; a statement scoped to another release is the one a reviewer has to
#     see. Classifying here rather than filtering means the report keeps
#     everything and the caller decides what to render.
fresh
src a.json "pkg:oci/grafana@13.0.4-alpine3.23?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" fixed
src b.json "pkg:oci/valkey?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fvalkey" not_affected
src c.json "pkg:golang/github.com/grafana/tempo" not_affected
run_report >/dev/null
check "a wrong tag is kind=tag"        "tag"       "$(rjq '.drops[] | select(.product|test("13.0.4")) | .kind')"
check "another image is kind=image"    "image"     "$(rjq '.drops[] | select(.product|test("valkey")) | .kind')"
check "a non-oci purl is kind=malformed" "malformed" "$(rjq '.drops[] | select(.product|test("golang")) | .kind')"
check "all three are still recorded"   "3"         "$(rjq '.dropped')"

# 18: no report is asked for, none is written, and nothing complains
fresh
src a.json "pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" not_affected
run >/dev/null; rc=$?
check "no report requested, exit still 0" "0" "$rc"
if [ ! -e "$SB/report.json" ]; then echo "ok   no report requested, none written"
else echo "FAIL no report requested, none written"; FAILURES=$((FAILURES+1)); fi

# --- a variant definition publishes under its sibling's name ----------------
#
# Every definition's directory name equalled the last segment of its `image:`
# until image/valkey-compat/, which publishes to .../valkey as a `-compat` tag
# (docs/CONVENTIONS.md, "Naming"). Trivy builds the product purl from the
# scanned image's RepoDigest, so on a compat build it sees `valkey` — keying
# compilation on the directory stamped `valkey-compat` into every product and
# matched nothing at all, which is the inert case this whole lane exists to
# catch, arriving through the caller.

# defs() lays out a definition tree the compiler can resolve, and runs it from
# there: the product name comes from the definition's `image:`, so the script
# has to be able to find the definition.
defs() { # $1 = directory under image/, $2 = published repository
  mkdir -p "$SB/image/$1"
  printf 'image: %s\ntags:\n  - 9.1.1-alpine3.23-compat\n' "$2" > "$SB/image/$1/image.yaml"
}
run_in_root() { ( cd "$SB" && "$COMPILE" "$SB/src" "$SB/out" "$@" 2>&1 ); }

# 19: the product name comes from `image:`, not from the directory. A statement
#     written the way Trivy will read it survives a compat build.
fresh
defs valkey-compat ghcr.io/mm-weber/dhc/valkey
src a.json "pkg:oci/valkey@9.1.1-alpine3.23-compat?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fvalkey" fixed
run_in_root valkey-compat "$DIGEST" 9.1.1-alpine3.23-compat >/dev/null
check "variant compiles under its published name" "pkg:oci/valkey@$DIGEST" "$(products)"

# 20: and the directory name is not a product identifier. Written that way a
#     statement passes review, compiles, and suppresses nothing.
fresh
defs valkey-compat ghcr.io/mm-weber/dhc/valkey
src a.json "pkg:oci/valkey-compat?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fvalkey" not_affected
out=$(run_in_root valkey-compat "$DIGEST" 9.1.1-alpine3.23-compat)
check "the directory name is not a product" "" "$(products)"
contains "and the drop says which name was built" "$out" "building 'valkey'"

# 21: the runtime sibling's release tags are not this build's. Two definitions
#     share one repository, so the tag list is the only thing separating them.
fresh
defs valkey-compat ghcr.io/mm-weber/dhc/valkey
src a.json "pkg:oci/valkey@9.1.1-alpine3.23?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fvalkey" fixed
run_in_root valkey-compat "$DIGEST" 9.1.1-alpine3.23-compat >/dev/null
check "the sibling's tag is dropped" "" "$(products)"

# 22: the report still identifies the definition, not the published name. Both
#     valkey definitions compile as `valkey`, and a rescan summary that labelled
#     its rows with that would render two rows nothing tells apart.
fresh
defs valkey-compat ghcr.io/mm-weber/dhc/valkey
src a.json "pkg:oci/valkey?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fvalkey" not_affected
COMPILE_VEX_REPORT="$SB/report.json" run_in_root valkey-compat "$DIGEST" 9.1.1-alpine3.23-compat >/dev/null
check "report keeps the definition as its identity" "valkey-compat" "$(rjq '.image')"
check "report names the resolved product too"       "valkey"        "$(rjq '.product')"

# 23: no definition in reach is the pre-variant contract — the name given is
#     the name used. Every caller relied on that before variants existed, and
#     the tests above run without a definition tree.
fresh
src a.json "pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" not_affected
run_in_root grafana "$DIGEST" 13.1.1-alpine3.23 >/dev/null
check "no definition tree falls back to the given name" "pkg:oci/grafana@$DIGEST" "$(products)"

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES test(s) failed"; exit 1; fi
echo "all tests passed"
