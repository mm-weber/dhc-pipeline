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

# 7: every source document merges into ONE compiled document per digest, named
#    after the published image (ADR 0003). Two sources in, one file out: with
#    several OpenVEX attestations on a digest `trivy --vex oci` applies one
#    chosen at random (ADR 0004), so exactly one document is the invariant.
fresh
src a.json "pkg:oci/grafana@13.0.4-alpine3.23?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" fixed
src b.json "pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" not_affected
run >/dev/null
check "sources merge into one named document" "grafana.openvex.json" "$(ls "$SB/out" | tr '\n' ' ' | sed 's/ $//')"
check "and it carries the surviving statement" "1" "$(jq '.statements | length' "$SB/out/grafana.openvex.json")"

# 7b: the document is written even when nothing applies (ADR 0003 measured
#     vexctl, Trivy, cosign and Kyverno all accept an empty statement list).
#     Before ADR 0003 an emptied document was skipped, which left a published
#     digest with no OpenVEX attestation at all and no way to tell "compiled
#     nothing" from "never compiled".
fresh
src a.json "pkg:oci/grafana@13.0.4-alpine3.23?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" fixed
run >/dev/null
check "an empty document is still written" "grafana.openvex.json" "$(ls "$SB/out" | tr '\n' ' ' | sed 's/ $//')"
check "with zero statements"               "0"                    "$(jq '.statements | length' "$SB/out/grafana.openvex.json")"

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

# defs() lays out a definition tree the compiler can resolve: the product name
# comes from the definition's `image:`, so the script has to be able to find the
# definition.
defs() { # $1 = directory under image/, $2 = published repository
  mkdir -p "$SB/image/$1"
  printf 'image: %s\ntags:\n  - 9.1.1-alpine3.23-compat\n' "$2" > "$SB/image/$1/image.yaml"
}
# Rooted at the sandbox the way lint-pins.sh and lint-vex-product.sh take a root
# argument, and run from an unrelated cwd on purpose: the definition lookup is
# the script's own, not the caller's. Keyed on cwd it fell back to the directory
# name from anywhere but the repo root — the inert product this lane exists to
# prevent, wearing a clean compile.
run_in_root() { ( cd / && COMPILE_VEX_ROOT="$SB" "$COMPILE" "$SB/src" "$SB/out" "$@" 2>&1 ); }

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

# --- release-arm inputs: manifest digests and the attested scan report -------
#
# Req 2.9 attests one document to the index AND to every platform manifest, so
# a consumer pinning either resolves the same claims; Req 2.12 turns whatever
# the release-time scan still reports into published under_investigation
# statements, derived from that report and carrying its timestamp.

DOC="$SB/out/grafana.openvex.json"
MANIFEST="sha256:1111111111111111111111111111111111111111111111111111111111111111"
doc() { jq "$@" "$SB/out/grafana.openvex.json"; }

# A trivy report in the shape the release scan writes: post-suppression
# findings are what remains uncovered.
report() { # $1 = filename, $2 = CVE, [$3 = package purl]
  cat > "$SB/$1" <<JSON
{"SchemaVersion":2,"CreatedAt":"2026-08-28T06:00:00Z",
 "ArtifactName":"ghcr.io/mm-weber/dhc/grafana",
 "Results":[{"Target":"grafana","Class":"os-pkgs","Vulnerabilities":[
   {"VulnerabilityID":"$2","PkgName":"openssl","Severity":"HIGH",
    "PkgIdentifier":{"PURL":"${3:-pkg:apk/alpine/openssl@3.5.0}"}}]}]}
JSON
}

# 24: one document covers the index and every scanned platform manifest, so a
#     consumer pinning a platform digest gets the same claims (Req 6.29).
fresh
src a.json "pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" not_affected
COMPILE_VEX_MANIFEST_DIGESTS="$MANIFEST" run >/dev/null
check "index digest is a product"    "pkg:oci/grafana@$DIGEST"   "$(doc -r '.statements[0].products[]."@id"' | grep -F "$DIGEST")"
check "manifest digest is a product" "pkg:oci/grafana@$MANIFEST" "$(doc -r '.statements[0].products[]."@id"' | grep -F "$MANIFEST")"

# 25: an uncovered finding in the attested report is published as
#     under_investigation rather than passing unremarked (Req 2.12).
fresh
report scan.json CVE-2026-99999
COMPILE_VEX_SCAN_REPORTS="$SB/scan.json" run >/dev/null
check "uncovered finding gets a statement"  "CVE-2026-99999"       "$(doc -r '.statements[0].vulnerability.name')"
check "with status under_investigation"     "under_investigation"  "$(doc -r '.statements[0].status')"
check "carrying the report's timestamp"     "2026-08-28T06:00:00Z" "$(doc -r '.statements[0].timestamp')"
# Subcomponents hang off the product, which is where OpenVEX 0.2.0 puts them
# and where every document under triage/vex/ carries them.
check "scoped to the package it was found in" "pkg:apk/alpine/openssl@3.5.0" "$(doc -r '.statements[0].products[0].subcomponents[0]."@id"')"
contains "and saying what it derives from" "$(doc -r '.statements[0].status_notes')" "release-time scan report"

# 26: a finding a source statement already covers is not restated as
#     under_investigation: that would publish two answers to one question.
fresh
src a.json "pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" not_affected
report scan.json CVE-2026-00001
COMPILE_VEX_SCAN_REPORTS="$SB/scan.json" run >/dev/null
check "covered finding keeps its one statement" "1"            "$(doc '.statements | length')"
check "and keeps the source status"             "not_affected" "$(doc -r '.statements[0].status')"

# 27: every platform manifest is scanned separately, so the same finding
#     arrives once per report; the document states it once.
fresh
report scan-amd64.json CVE-2026-99999
report scan-arm64.json CVE-2026-99999
COMPILE_VEX_SCAN_REPORTS="$SB/scan-amd64.json $SB/scan-arm64.json" run >/dev/null
check "one statement per finding, not per report" "1" "$(doc '.statements | length')"

# 28: first seen is the property a clock is measured from (cluster B), so a
#     finding already stated on a previous release keeps that timestamp
#     instead of resetting it on every rebuild.
fresh
report scan.json CVE-2026-99999
cat > "$SB/previous.json" <<'JSON'
{"@context":"https://openvex.dev/ns/v0.2.0","@id":"https://openvex.dev/docs/dhc/previous",
 "author":"dhc-pipeline triage","version":1,
 "statements":[{"vulnerability":{"name":"CVE-2026-99999"},
   "products":[{"@id":"pkg:oci/grafana@sha256:0000000000000000000000000000000000000000000000000000000000000000"}],
   "status":"under_investigation","timestamp":"2026-07-01T00:00:00Z"}]}
JSON
COMPILE_VEX_SCAN_REPORTS="$SB/scan.json" COMPILE_VEX_PREVIOUS="$SB/previous.json" run >/dev/null
check "first seen carries forward"          "2026-07-01T00:00:00Z" "$(doc -r '.statements[0].timestamp')"
check "and the product is this build's"     "pkg:oci/grafana@$DIGEST" "$(doc -r '.statements[0].products[0]."@id"')"

# 29: a report the scan never produced is a usage error, not a clean compile:
#     silently treating a missing report as "nothing uncovered" is exactly the
#     inert-looks-correct failure this lane exists to prevent (Req 2.26 is the
#     workflow's answer; the compiler refuses rather than guesses).
fresh
out=$(COMPILE_VEX_SCAN_REPORTS="$SB/absent.json" run; echo "rc=$?")
contains "a missing scan report fails loudly" "$out" "absent.json"
contains "and exits non-zero"                 "$out" "rc=2"

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES test(s) failed"; exit 1; fi
echo "all tests passed"
