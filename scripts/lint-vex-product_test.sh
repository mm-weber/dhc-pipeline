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

# shellcheck disable=SC2001  # sed indents every line of the captured output;
# the parameter-expansion form shellcheck suggests replaces one substring, not
# every line start.
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

# shellcheck disable=SC2001  # as above
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

# The status decides whether the product purl must carry a version (Req 6.20 /
# 6.21), so it is a fixture parameter rather than a constant. It is spliced in
# as raw JSON — a case needs to write a status that is not a string at all —
# and an empty argument omits the key entirely.
stmt_status() { # status JSON (empty omits the key), CVE, [product JSON blobs…]
  local cve="$2" status="$1"; shift 2
  local products="" p line extra
  for p in "$@"; do
    [ -z "$products" ] || products="$products,"
    products="$products$p"
  done
  line=""
  [ -z "$status" ] || line="  \"status\": $status,"
  # justification and impact_statement belong to not_affected, action_statement
  # to affected (OpenVEX §Status Justifications). Branching keeps every fixture
  # a document a VEX consumer would accept, so a case that passes here is not
  # passing on a shape only this lint tolerates.
  case "$status" in
    '"not_affected"')
      extra='  "status_notes": "Architectural analysis of the shipped entrypoint; see triage/LOG.md 2026-07-26.",
  "justification": "vulnerable_code_not_in_execute_path",
  "impact_statement": "This image does not start the vulnerable server, so the disclosing handler is never routed or invoked.",' ;;
    '"affected"')
      extra='  "status_notes": "Reachable from the shipped entrypoint; see triage/LOG.md 2026-07-26.",
  "action_statement": "Upgrade to grafana 13.1.1-alpine3.23 or later.",' ;;
    *)
      extra='  "status_notes": "See triage/LOG.md 2026-07-26.",' ;;
  esac
  cat <<EOF
{
  "vulnerability": { "name": "$cve" },
  "products": [$products],
$line
$extra
  "timestamp": "2026-07-26T00:00:00Z"
}
EOF
}

stmt() { # CVE, [product JSON blobs…] — the not_affected common case
  stmt_status '"not_affected"' "$@"
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

vex_status() { # status JSON, CVE, product purl, [subcomponent purls…] — the
               # one-statement, one-product case at a chosen status
  local status="$1" cve="$2" purl="$3"; shift 3
  write_doc "$SB/triage/vex/${cve}.openvex.json" \
    "$(stmt_status "$status" "$cve" "$(prod "$purl" "$@")")"
}

vex() { # CVE, product purl, [subcomponent purls…] — the one-statement,
        # one-product common case, written to triage/vex/<CVE>.openvex.json
  vex_status '"not_affected"' "$@"
}

GRAFANA_PRODUCT="pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana"
VALKEY_PRODUCT="pkg:oci/valkey?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fvalkey"
TEMPO="pkg:golang/github.com/grafana/tempo"
PROM="pkg:golang/github.com/prometheus/prometheus"
DIGEST="sha256:829bf58050a8e341525e85d8b0a36c8380434aa8295ec2951f2cc46800357863"
# The same product, versioned the two ways a real one can be: the published tag
# and the RepoDigest Trivy puts in its root component purl.
GRAFANA_TAGGED="pkg:oci/grafana@13.1.1-alpine3.23?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana"
GRAFANA_PINNED="pkg:oci/grafana@$DIGEST?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana"
CVE1=CVE-2026-28377
CVE2=CVE-2026-42151
CVE3=CVE-2026-59371

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

# 19: a digest pins this not_affected statement to one build (triage/README.md:
# "No digest in the product purl"). It suppresses until the next rebuild and
# then stops, silently — the same failure as a wrong host, just deferred.
# Whether that holds depends on the status; the status matrix is Req 6.20/6.21
# below, and this same purl under `fixed` is case 34.
fresh; vex "$CVE1" "$GRAFANA_PINNED" "$TEMPO"
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

# --- Req 6.20 / 6.21: the product version depends on the status --------------
#
# One rule for both statuses is wrong for one of them, because they make
# different kinds of claim:
#
#   not_affected is a claim about code structure — the vulnerable path is not
#   reachable in this image. That stays true across rebuilds, so a version
#   makes the statement suppress until the next build and then silently stop
#   matching (Req 6.20).
#
#   fixed is a claim that specific versions carry a remedy. Stated versionless
#   it asserts that every image published under that name carries the fix,
#   which is false while an older tag is still pullable from the registry
#   (Req 6.21).
#
# The version is what follows '@' before any '?qualifiers' or '#subpath', so a
# tag and a digest both count as one.

# 32: the new rule. A fixed statement with no version excuses the finding on
# images that do not have the fix.
fresh; vex_status '"fixed"' "$CVE1" "$GRAFANA_PRODUCT" "$PROM"
run_case "fixed with a versionless product fails" 1
run_case "versionless fixed product is reported under Req 6.21" 1 "Req 6.21"
run_case "versionless fixed product quotes the product" 1 "$GRAFANA_PRODUCT"
run_case "versionless fixed product names the status that requires a version" 1 "fixed"
run_case "versionless fixed product says a version is what is missing" 1 "version"
# The author needs the reason, not the rule: what is still pullable is what
# makes a versionless fixed claim false.
run_case "versionless fixed product says why: an older tag stays pullable" 1 "registry"
run_case "versionless fixed product names the file" 1 "triage/vex/$CVE1.openvex.json"
run_case "versionless fixed product is a GitHub annotation" 1 "::error file=triage/vex/$CVE1.openvex.json"

# 33: with the published tag it is exactly the claim the author means to make
fresh; vex_status '"fixed"' "$CVE1" "$GRAFANA_TAGGED" "$PROM"
run_case "fixed with a tag-shaped version passes" 0
refute_case "a versioned fixed product emits no annotation" 0 "::error"
run_case "a passing fixed run names the file it checked" 0 "triage/vex/$CVE1.openvex.json"

# 34: byte for byte the product purl of case 19 — the one that must fail under
# not_affected — and here it must pass. The purl alone cannot decide this.
fresh; vex_status '"fixed"' "$CVE1" "$GRAFANA_PINNED" "$TEMPO"
run_case "fixed with a digest-shaped version passes" 0

# 35: the old rule, kept — now carried by the status it belongs to
fresh; vex "$CVE1" "$GRAFANA_TAGGED" "$TEMPO"
run_case "not_affected with a tag-shaped version fails" 1 "13.1.1-alpine3.23"
run_case "versioned not_affected product is reported under Req 6.20" 1 "Req 6.20"
run_case "versioned not_affected product names the status that forbids one" 1 "not_affected"
run_case "versioned not_affected product says why: the next rebuild" 1 "rebuild"

# 36: and versionless it is the shape this repo ships
fresh; vex "$CVE1" "$GRAFANA_PRODUCT" "$TEMPO"
refute_case "not_affected with a versionless product is not reported" 0 "::error"

# 37: the rule is "not fixed", not "not_affected" — every other status forbids
# a version for the same reason, and none of them requires one
fresh; vex_status '"under_investigation"' "$CVE1" "$GRAFANA_PINNED" "$TEMPO"
run_case "under_investigation with a versioned product fails" 1 "Req 6.20"
fresh; vex_status '"affected"' "$CVE1" "$GRAFANA_TAGGED" "$TEMPO"
run_case "affected with a versioned product fails" 1 "Req 6.20"
fresh; vex_status '"affected"' "$CVE1" "$GRAFANA_PRODUCT" "$TEMPO"
run_case "affected with a versionless product passes" 0

# 38: OpenVEX makes status required, so a statement without one is already
# broken — it must not be broken into a free pass for a pinned product
fresh; vex_status "" "$CVE1" "$GRAFANA_PINNED" "$TEMPO"
run_case "a statement with no status fails on a versioned product" 1 "Req 6.20"
fresh; vex_status "" "$CVE1" "$GRAFANA_PRODUCT" "$TEMPO"
run_case "a statement with no status and a versionless product passes" 0

# 39: present but empty is not present
fresh; vex_status '""' "$CVE1" "$GRAFANA_PINNED" "$TEMPO"
run_case "an empty status fails on a versioned product" 1 "Req 6.20"
fresh; vex_status '""' "$CVE1" "$GRAFANA_PRODUCT" "$TEMPO"
run_case "an empty status and a versionless product passes" 0

# 40: and neither is a status that is not a string. jq hands a stringified
# array or object to any comparison that assumed one, and an object whose
# rendering merely contains the word is not the fixed label.
fresh; vex_status '["fixed"]' "$CVE1" "$GRAFANA_PINNED" "$TEMPO"
run_case "an array status is not the fixed label" 1 "Req 6.20"
fresh; vex_status '{"label": "fixed"}' "$CVE1" "$GRAFANA_PINNED" "$TEMPO"
run_case "an object status that merely contains fixed is not the fixed label" 1 "Req 6.20"
fresh; vex_status 'null' "$CVE1" "$GRAFANA_PRODUCT" "$TEMPO"
run_case "a null status with a versionless product passes" 0

# 41: OpenVEX status labels are a closed set of lower-case strings (spec,
# Status Labels), so "Fixed" is not the fixed label: no consumer reads it as
# one, and a lint that did would bless a document that suppresses nothing.
# Compared case-sensitively — unlike the purl type above, which purl itself
# declares case-insensitive.
fresh; vex_status '"Fixed"' "$CVE1" "$GRAFANA_PINNED" "$TEMPO"
run_case "a status differing only in case is not the fixed label" 1 "Req 6.20"
fresh; vex_status '"FIXED"' "$CVE1" "$GRAFANA_PRODUCT" "$TEMPO"
run_case "an upper-case status does not demand a version" 0

# 42: '@' delimits the version only before the qualifiers; inside a qualifier
# value it is an ordinary character. A fixed product whose only '@' sits there
# is still versionless, and a not_affected one still clean.
fresh; vex_status '"fixed"' "$CVE1" "pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana&tag=13.1.1@sha256" "$PROM"
run_case "an '@' inside a qualifier value is not a product version" 1 "Req 6.21"
fresh; vex "$CVE1" "pkg:oci/grafana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana&tag=13.1.1@sha256" "$TEMPO"
run_case "an '@' inside a qualifier leaves a not_affected product clean" 0

# 43: an empty version component is no version — purl reads 'name@' unversioned
fresh; vex_status '"fixed"' "$CVE1" "pkg:oci/grafana@?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" "$PROM"
run_case "a fixed product with an empty version component fails" 1 "Req 6.21"

# --- making one rule conditional must not make the others conditional -------

# 44: a fixed statement is checked exactly as hard as any other
fresh; vex_status '"fixed"' "$CVE1" "pkg:oci/grafana@13.1.1-alpine3.23?repository_url=quay.io%2Fmm-weber%2Fdhc%2Fgrafana" "$PROM"
run_case "a fixed statement's repository_url is still checked" 1 "quay.io/mm-weber/dhc/grafana"
fresh; vex_status '"fixed"' "$CVE1" "$GRAFANA_TAGGED" "$TEMPO@v1.5.1"
run_case "a fixed statement's subcomponent version is still checked" 1 "$TEMPO@v1.5.1"
fresh; vex_status '"fixed"' "$CVE1" "pkg:docker/grafana@13.1.1-alpine3.23?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" "$PROM"
run_case "a fixed statement with a non-oci purl type still fails" 1 "pkg:docker/grafana"
fresh; vex_status '"fixed"' "$CVE1" "pkg:oci/graphana@13.1.1-alpine3.23?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgraphana" "$PROM"
run_case "a fixed statement naming no image definition still fails" 1 "image/graphana/image.yaml"
fresh; vex_status '"fixed"' "$CVE1" "$GRAFANA_TAGGED"
run_case "a fixed statement with no subcomponents still fails" 1 "subcomponent"

# 45: the missing version and the missing definition are both the author's to
# fix; stopping at the first sends them round the loop twice
fresh; vex_status '"fixed"' "$CVE1" "pkg:oci/graphana?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgraphana" "$PROM"
run_case "a versionless fixed product with no definition reports the version" 1 "Req 6.21"
run_case "a versionless fixed product with no definition reports both defects" 1 "image/graphana/image.yaml"

# 46: but an identifier that is not a purl at all gets one diagnosis, not two.
# "Add a version" is noise when the whole shape is wrong.
fresh; vex_status '"fixed"' "$CVE1" "ghcr.io/mm-weber/dhc/grafana:13.1.1-alpine3.23" "$PROM"
run_case "a fixed statement with a bare image reference fails" 1 "not a package URL"
refute_case "a non-purl fixed product is not also reported as versionless" 1 "Req 6.21"

# --- mixed statuses in one document -----------------------------------------

# 47: both rules fire in one run, each naming its own statement, and the clean
# statement beside them is left alone
fresh
write_doc "$SB/triage/vex/mixed.openvex.json" \
  "$(stmt_status '"fixed"' "$CVE1" "$(prod "$GRAFANA_TAGGED" "$PROM")")" \
  "$(stmt_status '"fixed"' "$CVE2" "$(prod "$GRAFANA_PRODUCT" "$PROM")")" \
  "$(stmt_status '"not_affected"' "$CVE3" "$(prod "$GRAFANA_PINNED" "$TEMPO")")"
run_case "the versionless fixed statement in a mixed file is named by its CVE" 1 "$CVE2"
run_case "the versioned not_affected statement is named in the same run" 1 "$CVE3"
run_case "a mixed-status file reports Req 6.21" 1 "Req 6.21"
run_case "a mixed-status file reports Req 6.20 in the same run" 1 "Req 6.20"
refute_case "the clean fixed statement beside them is not reported" 1 "$CVE1"

# 48: the shape Req 6.22 produces, and the reason one rule for both statuses
# cannot work. CVE-2026-42151 was not_affected against grafana 13.0.4 until the
# 13.1.1 bump moved prometheus past the fix; the earlier claim is retained
# rather than deleted, and a later fixed statement supersedes it. The retained
# claim must stay versionless and the superseding one must carry a version, in
# the same document, for the same CVE and the same image.
fresh
write_doc "$SB/triage/vex/$CVE2.openvex.json" \
  "$(stmt_status '"not_affected"' "$CVE2" "$(prod "$GRAFANA_PRODUCT" "$PROM")")" \
  "$(stmt_status '"fixed"' "$CVE2" "$(prod "$GRAFANA_TAGGED" "$PROM")")"
run_case "a superseded statement retained beside its replacement passes" 0
refute_case "the supersession shape emits no annotation" 0 "::error"
run_case "the supersession run names the file it checked" 0 "triage/vex/$CVE2.openvex.json"

echo
if [ "$FAILURES" -eq 0 ]; then echo "all lint-vex-product tests passed"; else echo "$FAILURES failing assertion(s)"; fi
exit $((FAILURES > 0))
