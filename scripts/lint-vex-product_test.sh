#!/usr/bin/env bash
# Tests for scripts/lint-vex-product.sh — self-contained sandbox, no network.
#
# A VEX statement whose product identifier is wrong raises no error anywhere. It
# simply never matches: the finding stays, the statement is inert, and nothing
# says why. This repo spent a full day on exactly that — two not_affected
# statements that had never suppressed anything on the PR gate.
#
# The gate cannot close that gap by itself. It infers coverage from "did a
# finding disappear", which cannot tell a correct statement from an inert one,
# and it strips the repository_url qualifier before scanning because the
# throwaway local registry it pushes to has a different host. With that
# qualifier stripped the gate still catches a wrong image name, a near-miss
# name, a wrong purl type and a wrong subcomponent — and nothing whatsoever
# about the registry host. This lint is the only check left on it, by exact
# string comparison rather than inference.
#
# Exit contract, pinned exactly — an absent implementation exits 127, so no
# error-case assertion here may be satisfied by "command not found":
#   0 — every product identifier checks out, and the run names what it checked
#       (a lint that globs nothing must not be indistinguishable from a pass)
#   1 — at least one violation, each emitted as a
#       ::error file=<repo-relative path>:: annotation, quoting both the value
#       found and the value expected
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LINT="$HERE/lint-vex-product.sh"
FAILURES=0

run_case() { # name, expected_exit, expect_substring(optional) — sandbox in $SB
  local name="$1" expected="$2" substr="${3:-}"
  local out rc
  out=$("$LINT" "$SB" 2>&1); rc=$?
  if [ "$rc" -ne "$expected" ]; then
    echo "FAIL $name: exit $rc, expected $expected"; echo "$out" | sed 's/^/    /'
    FAILURES=$((FAILURES+1)); return
  fi
  if [ -n "$substr" ] && ! grep -qF "$substr" <<<"$out"; then
    echo "FAIL $name: output missing '$substr'"; echo "$out" | sed 's/^/    /'
    FAILURES=$((FAILURES+1)); return
  fi
  echo "ok   $name"
}

refute_case() { # name, expected_exit, forbidden_substring
  local name="$1" expected="$2" substr="$3"
  local out rc
  out=$("$LINT" "$SB" 2>&1); rc=$?
  if [ "$rc" -ne "$expected" ]; then
    echo "FAIL $name: exit $rc, expected $expected"; echo "$out" | sed 's/^/    /'
    FAILURES=$((FAILURES+1)); return
  fi
  if grep -qF "$substr" <<<"$out"; then
    echo "FAIL $name: output should not contain '$substr'"; echo "$out" | sed 's/^/    /'
    FAILURES=$((FAILURES+1)); return
  fi
  echo "ok   $name"
}

# Two definitions, so a statement can name the wrong one of a pair that both
# exist — the copy-paste that no "does this image exist" check would catch.
fresh() {
  SB=$(mktemp -d)
  mkdir -p "$SB/image/grafana" "$SB/image/valkey" "$SB/triage/vex"
  printf 'name: Grafana 13.1.x\nimage: ghcr.io/mm-weber/dhc/grafana\n' > "$SB/image/grafana/image.yaml"
  printf 'name: Valkey 9.0.x\nimage: ghcr.io/mm-weber/dhc/valkey\n' > "$SB/image/valkey/image.yaml"
}

# --- fixture builders -------------------------------------------------------
# Documents are assembled from parts so a case can corrupt exactly one
# identifier and leave everything else alone; a failure then names the rule
# under test and nothing else. Shapes follow triage/vex/CVE-2026-28377.openvex.json.

prod() { # product purl, [subcomponent purls…]
  # With no subcomponent argument the product carries no subcomponents key at
  # all — a whole-image claim, which is a different and much broader statement
  # than any of the recipes in triage/README.md produce.
  local purl="$1"; shift
  local subs="" s
  if [ "$#" -eq 0 ]; then printf '{"@id": "%s"}' "$purl"; return; fi
  for s in "$@"; do
    [ -z "$subs" ] || subs="$subs,"
    subs="$subs$(printf '{"@id": "%s"}' "$s")"
  done
  printf '{"@id": "%s", "subcomponents": [%s]}' "$purl" "$subs"
}

stmt() { # CVE, [product JSON blobs…]
  local cve="$1"; shift
  local products="" p
  for p in "$@"; do
    [ -z "$products" ] || products="$products,"
    products="$products$p"
  done
  cat <<EOF
{
  "vulnerability": { "name": "$cve" },
  "products": [$products],
  "status": "not_affected",
  "status_notes": "Architectural analysis of the shipped entrypoint; see triage/LOG.md 2026-07-26.",
  "justification": "vulnerable_code_not_in_execute_path",
  "impact_statement": "This image does not start the vulnerable server, so the disclosing handler is never routed or invoked.",
  "timestamp": "2026-07-26T00:00:00Z"
}
EOF
}

write_doc() { # file, [statement JSON blobs…]
  local f="$1"; shift
  local body="" s
  for s in "$@"; do
    [ -z "$body" ] || body="$body,"
    body="$body$s"
  done
  cat > "$f" <<EOF
{
  "@context": "https://openvex.dev/ns/v0.2.0",
  "@id": "https://openvex.dev/docs/public/vex-829bf58050a8e341525e85d8b0a36c8380434aa8295ec2951f2cc46800357863",
  "author": "dhc-pipeline triage (mm-weber)",
  "version": 1,
  "statements": [$body],
  "timestamp": "2026-07-26T00:00:00Z"
}
EOF
}

vex() { # CVE, product purl, [subcomponent purls…] — the one-statement,
        # one-product common case, written to triage/vex/<CVE>.openvex.json
  local cve="$1" purl="$2"; shift 2
  write_doc "$SB/triage/vex/${cve}.openvex.json" "$(stmt "$cve" "$(prod "$purl" "$@")")"
}

GRAFANA_PRODUCT="pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana"
VALKEY_PRODUCT="pkg:oci/valkey?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fvalkey"
TEMPO="pkg:golang/github.com/grafana/tempo"
PROM="pkg:golang/github.com/prometheus/prometheus"
DIGEST="sha256:829bf58050a8e341525e85d8b0a36c8380434aa8295ec2951f2cc46800357863"
CVE1=CVE-2026-28377
CVE2=CVE-2026-42151

# --- the shapes that must pass ----------------------------------------------

# 1: the statement this repo actually ships
fresh; vex "$CVE1" "$GRAFANA_PRODUCT" "$TEMPO"
run_case "the repo's own statement shape passes" 0
# A lint whose glob is wrong passes vacuously and looks identical to a clean
# run. Naming the file it validated is what tells those two apart.
run_case "a passing run names the file it checked" 0 "triage/vex/$CVE1.openvex.json"
refute_case "a passing run emits no annotation" 0 "::error"

# 2: the lane starts empty — nothing is excused until a decision is made
fresh
run_case "empty vex lane passes" 0

# 3: and it may not exist at all yet
fresh; rmdir "$SB/triage/vex"
run_case "absent vex lane passes" 0

# 4: a root that is not there is not a clean tree. Reporting success on a path
# that holds nothing is the same invisible failure one level up.
SB="$(mktemp -d)/no-such-root"
run_case "nonexistent root fails" 1

# 5: prose in the lane is documentation, not a statement
fresh; vex "$CVE1" "$GRAFANA_PRODUCT" "$TEMPO"
printf '# how to author a statement\n' > "$SB/triage/vex/README.md"
run_case "non-json file in the lane is ignored" 0

# 6: several statements per file, several products per statement, several
# subcomponents per product — all legal OpenVEX, none of it exotic
fresh
write_doc "$SB/triage/vex/$CVE1.openvex.json" \
  "$(stmt "$CVE1" "$(prod "$GRAFANA_PRODUCT" "$TEMPO" "$PROM")" "$(prod "$VALKEY_PRODUCT" "$TEMPO")")" \
  "$(stmt "$CVE2" "$(prod "$GRAFANA_PRODUCT" "$PROM")")"
run_case "several statements, products and subcomponents pass" 0

# --- rule 3: the registry host, the whole reason this lint exists -----------

# 7: THE case. The gate strips repository_url before scanning, so this is
# invisible everywhere else: the statement parses, names a real image, carries a
# clean subcomponent, and suppresses nothing on any registry we publish to.
fresh; vex "$CVE1" "pkg:oci/grafana?repository_url=docker.io%2Fmm-weber%2Fdhc%2Fgrafana" "$TEMPO"
run_case "wrong registry host fails" 1
run_case "wrong host names the file" 1 "triage/vex/$CVE1.openvex.json"
# Both values are quoted decoded: comparing an encoded string against a decoded
# one is what makes these mismatches hard to see in the first place.
run_case "wrong host quotes the value found" 1 "docker.io/mm-weber/dhc/grafana"
run_case "wrong host quotes the value expected" 1 "ghcr.io/mm-weber/dhc/grafana"
run_case "wrong host is a GitHub annotation" 1 "::error file=triage/vex/$CVE1.openvex.json"

# 8: right host, wrong path — the org/namespace segment dropped
fresh; vex "$CVE1" "pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fgrafana" "$TEMPO"
run_case "right host with wrong path fails" 1 "ghcr.io/mm-weber/grafana"
run_case "wrong path quotes the value expected" 1 "ghcr.io/mm-weber/dhc/grafana"

# 9: no qualifier at all. Trivy's root component purl carries one, so a product
# without it matches nothing — and the author gets no hint of that.
fresh; vex "$CVE1" "pkg:oci/grafana" "$TEMPO"
run_case "product without repository_url fails" 1 "repository_url"
run_case "missing qualifier says which value it wanted" 1 "ghcr.io/mm-weber/dhc/grafana"

# 10: present but empty is not present
fresh; vex "$CVE1" "pkg:oci/grafana?repository_url=" "$TEMPO"
run_case "empty repository_url fails" 1 "ghcr.io/mm-weber/dhc/grafana"

# 11: double-encoded — the shape you get from pasting an already-encoded value
# through a second encoder. Decodes to a literal '%2F' string, matches nothing.
fresh; vex "$CVE1" "pkg:oci/grafana?repository_url=ghcr.io%252Fmm-weber%252Fdhc%252Fgrafana" "$TEMPO"
run_case "double-encoded repository_url fails" 1 "ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana"

# 12: percent-encoding hex is case-insensitive (RFC 3986 §6.2.2.1), so this is
# byte-for-byte the same URL and must not be flagged
fresh; vex "$CVE1" "pkg:oci/grafana?repository_url=ghcr.io%2fmm-weber%2fdhc%2fgrafana" "$TEMPO"
run_case "lowercase percent-encoding passes" 0

# 13: a qualifier value is percent-decoded on parse and '/' is not a delimiter
# inside one, so an unencoded value decodes to the identical URL. Non-canonical,
# not wrong — and failing it would reject statements that do suppress.
fresh; vex "$CVE1" "pkg:oci/grafana?repository_url=ghcr.io/mm-weber/dhc/grafana" "$TEMPO"
run_case "unencoded slashes in the qualifier pass" 0

# 14: purl qualifiers are an unordered set and repository_url is not required to
# come first or alone — a lint that string-matches '?repository_url=' breaks here
fresh; vex "$CVE1" "pkg:oci/grafana?arch=amd64&repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana&tag=13.1.1" "$TEMPO"
run_case "extra qualifiers in unexpected order pass" 0

# 15: the copy-paste between two images that both exist. Nothing about this
# statement is malformed; it is simply about a different image than it says.
fresh; vex "$CVE1" "pkg:oci/valkey?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" "$TEMPO"
run_case "product carrying another image's repository_url fails" 1 "ghcr.io/mm-weber/dhc/valkey"
run_case "cross-image paste quotes what the statement says" 1 "ghcr.io/mm-weber/dhc/grafana"

# --- rules 1 and 2: the product purl itself ---------------------------------

# 16: a name with no definition behind it. The near-miss spelling is the point:
# it reads correct and suppresses nothing.
fresh; vex "$CVE1" "pkg:oci/graphana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgraphana" "$TEMPO"
run_case "product naming no image definition fails" 1 "image/graphana/image.yaml"

# 17: pkg:docker is a real purl type and an inert one here
fresh; vex "$CVE1" "pkg:docker/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" "$TEMPO"
run_case "non-oci purl type fails" 1 "pkg:docker/grafana"
run_case "wrong type names the type required" 1 "oci"

# 18: a bare image reference where a purl belongs — the most natural thing to
# write by hand, and completely inert
fresh; vex "$CVE1" "ghcr.io/mm-weber/dhc/grafana" "$TEMPO"
run_case "a bare image reference is not a purl and fails" 1 "ghcr.io/mm-weber/dhc/grafana"
run_case "non-purl product says a purl was expected" 1 "pkg:oci/"

# 19: a digest pins the statement to one build (triage/README.md: "No digest in
# the product purl"). It suppresses until the next rebuild and then stops,
# silently — the same failure as a wrong host, just deferred.
fresh; vex "$CVE1" "pkg:oci/grafana@$DIGEST?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" "$TEMPO"
run_case "product purl carrying a digest fails" 1 "$DIGEST"

# --- rule 4: versionless subcomponents --------------------------------------

# 20: Go module versions move on every upstream rebuild, so a versioned
# subcomponent stops matching at the next bump and says nothing when it does
fresh; vex "$CVE1" "$GRAFANA_PRODUCT" "$TEMPO@v1.5.1-0.20260114120000-abcdef012345"
run_case "versioned subcomponent fails" 1 "$TEMPO@v1.5.1-0.20260114120000-abcdef012345"
run_case "versioned subcomponent says the version is the defect" 1 "version"
run_case "versioned subcomponent names the file" 1 "triage/vex/$CVE1.openvex.json"

# 21: a module path is not a purl
fresh; vex "$CVE1" "$GRAFANA_PRODUCT" "github.com/grafana/tempo"
run_case "subcomponent that is not a purl fails" 1 "github.com/grafana/tempo"

# 22: no subcomponents at all is a whole-image not_affected claim. Every recipe
# in triage/README.md scopes the suppression to one package; an unscoped one
# excuses the CVE everywhere in the image, which is the VEX-washing shape.
fresh; vex "$CVE1" "$GRAFANA_PRODUCT"
run_case "product with no subcomponents fails" 1 "subcomponent"

# 23: and the empty-list spelling of the same thing
fresh
write_doc "$SB/triage/vex/$CVE1.openvex.json" \
  "$(stmt "$CVE1" "$(printf '{"@id": "%s", "subcomponents": []}' "$GRAFANA_PRODUCT")")"
run_case "empty subcomponents list fails" 1 "subcomponent"

# --- documents that are not statements --------------------------------------

# 24: a statement with no products names nothing and suppresses nothing
fresh
write_doc "$SB/triage/vex/$CVE1.openvex.json" "$(stmt "$CVE1")"
run_case "statement with no products fails" 1 "$CVE1"

# 25: a document with no statements is committed weight that excuses nothing
fresh; write_doc "$SB/triage/vex/$CVE1.openvex.json"
run_case "document with no statements fails" 1 "triage/vex/$CVE1.openvex.json"

# 26: valid json that is not OpenVEX — e.g. a Trivy report parked in the lane
fresh; printf '{"SchemaVersion": 2, "Results": []}\n' > "$SB/triage/vex/$CVE1.openvex.json"
run_case "json that is not a VEX document fails" 1 "statements"

# 27: unparseable json must be loud. Skipping it would let a statement stop
# being checked by breaking it — the one thing this lint cannot allow.
fresh; vex "$CVE2" "$GRAFANA_PRODUCT" "$PROM"
printf '{ "statements": [ \n' > "$SB/triage/vex/broken.openvex.json"
run_case "unparseable json fails" 1 "triage/vex/broken.openvex.json"
run_case "unparseable json does not stop the other files being checked" 1 "triage/vex/$CVE2.openvex.json"

# --- everything is reported, not just the first thing found -----------------

# 28: a bad product beside a good one in the same statement
fresh
write_doc "$SB/triage/vex/$CVE1.openvex.json" \
  "$(stmt "$CVE1" "$(prod "$GRAFANA_PRODUCT" "$TEMPO")" \
                  "$(prod "pkg:oci/valkey?repository_url=quay.io%2Fmm-weber%2Fdhc%2Fvalkey" "$TEMPO")")"
run_case "one bad product beside a good one is caught" 1 "quay.io/mm-weber/dhc/valkey"

# 29: a bad statement beside a good one in the same file. With several
# statements per file, naming only the file leaves the reader to guess which.
fresh
write_doc "$SB/triage/vex/$CVE1.openvex.json" \
  "$(stmt "$CVE1" "$(prod "$GRAFANA_PRODUCT" "$TEMPO")")" \
  "$(stmt "$CVE2" "$(prod "pkg:oci/grafana?repository_url=quay.io%2Fmm-weber%2Fdhc%2Fgrafana" "$PROM")")"
run_case "the offending statement is named by its CVE" 1 "$CVE2"

# 30: a bad file beside a good one
fresh
vex "$CVE1" "$GRAFANA_PRODUCT" "$TEMPO"
vex "$CVE2" "pkg:oci/grafana?repository_url=quay.io%2Fmm-weber%2Fdhc%2Fgrafana" "$PROM"
run_case "a bad file beside a good one fails" 1 "triage/vex/$CVE2.openvex.json"

# 31: two different defects in one product — an implementation that stops at the
# first sends the author round the loop twice
fresh; vex "$CVE1" "pkg:oci/grafana?repository_url=quay.io%2Fmm-weber%2Fdhc%2Fgrafana" "$TEMPO@v1.5.1"
run_case "the product defect is reported" 1 "quay.io/mm-weber/dhc/grafana"
run_case "the subcomponent defect is reported in the same run" 1 "$TEMPO@v1.5.1"

echo
if [ "$FAILURES" -eq 0 ]; then echo "all lint-vex-product tests passed"; else echo "$FAILURES failing assertion(s)"; fi
exit $((FAILURES > 0))
