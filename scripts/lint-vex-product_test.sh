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
NOTES=""   # per-case override for status_notes; see stmt_status

fresh() {
  NOTES=""
  SB=$(mktemp -d)
  mkdir -p "$SB/image/grafana" "$SB/image/valkey" "$SB/triage/vex"
  # tags: is load-bearing since Req 6.20 — a product version has to be one of
  # them, because compilation looks the tag up against the build (Req 6.30).
  printf 'name: Grafana 13.1.x\nimage: ghcr.io/mm-weber/dhc/grafana\ntags:\n  - 13-alpine3.23\n  - 13.1-alpine3.23\n  - 13.1.1-alpine3.23\n' > "$SB/image/grafana/image.yaml"
  printf 'name: Valkey 9.0.x\nimage: ghcr.io/mm-weber/dhc/valkey\ntags:\n  - 9-alpine3.23\n' > "$SB/image/valkey/image.yaml"
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
  # Req 6.31: a versionless product has to say why its claim survives a version
  # change, and most fixtures here are versionless, so the default notes carry
  # that token. $NOTES replaces them for the cases that test the rule itself.
  local notes="${NOTES:-}"
  case "$status" in
    '"not_affected"')
      [ -n "$notes" ] || notes="version-independent: this image never starts the vulnerable server, which is a property of what it runs rather than of a release. Architectural analysis; see triage/LOG.md 2026-07-26."
      extra="  \"status_notes\": \"$notes\",
  \"justification\": \"vulnerable_code_not_in_execute_path\",
  \"impact_statement\": \"This image does not start the vulnerable server, so the disclosing handler is never routed or invoked.\"," ;;
    '"affected"')
      [ -n "$notes" ] || notes="version-independent: reachable from the shipped entrypoint in every release. See triage/LOG.md 2026-07-26."
      extra="  \"status_notes\": \"$notes\",
  \"action_statement\": \"Upgrade to grafana 13.1.1-alpine3.23 or later.\"," ;;
    *)
      [ -n "$notes" ] || notes="version-independent: see triage/LOG.md 2026-07-26."
      extra="  \"status_notes\": \"$notes\"," ;;
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

# --- Req 6.20 / 6.21: a source version is a published tag --------------------
#
# Source is not what a scanner sees. scripts/compile-vex.sh renders these
# documents per build, replacing the product version with the digest of the
# image being scanned (6.29) and dropping any statement whose tag is not a tag
# of that build (6.30). So in source the version is a *scope*, not an
# identifier, and only a published tag can be one:
#
#   a published tag  the claim is about that release. fixed must carry one
#                    (6.21), since a remedy is always about particular versions.
#   no version       the claim holds for every build of that image.
#   a digest         rejected (6.20). It is unreviewable, and it goes stale at
#                    the next rebuild of the same release.
#
# Measured, and the reason the rule changed: a tag-versioned product suppresses
# nothing at all when handed to Trivy directly, because Trivy builds the product
# identifier from the RepoDigest. Compilation is what closes that, and it can
# only look up a tag.
#
# The version is what follows '@' before any '?qualifiers' or '#subpath'.

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

# 34: a digest in source is now the defect. The compiler puts the digest in;
# an author writing one by hand pins a build nobody can look up and that is
# stale the next time the same release is rebuilt.
fresh; vex_status '"fixed"' "$CVE1" "$GRAFANA_PINNED" "$TEMPO"
run_case "fixed with a digest-shaped version fails" 1
run_case "a digest in source is reported under Req 6.20" 1 "Req 6.20"
run_case "the digest defect quotes the version found" 1 "$DIGEST"
run_case "the digest defect says a published tag is expected" 1 "tag"

# 35: the inverse of the old rule. Scoping a not_affected to the release it was
# argued about is now the point — it is what stops the claim outliving that
# release (review finding 2.4), and the compiler drops it on any other build.
fresh; vex "$CVE1" "$GRAFANA_TAGGED" "$TEMPO"
run_case "not_affected scoped to a published tag passes" 0
refute_case "a tag-scoped not_affected emits no annotation" 0 "::error"

# 35b: a version that looks like a tag but is not one this definition publishes
# would be dropped by the compiler on every build, so it suppresses nothing
# and says nothing. That is the inert case this lint exists to catch.
fresh; vex "$CVE1" "pkg:oci/grafana@99.9.9-alpine3.23?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fgrafana" "$TEMPO"
run_case "a version that is not a published tag fails" 1 "Req 6.20"
run_case "the unknown tag is quoted" 1 "99.9.9-alpine3.23"
run_case "the definition's real tags are listed" 1 "13.1.1-alpine3.23"

# 35c: a definition that publishes no tags at all can scope nothing, so any
# version on it is unmatchable rather than merely wrong.
fresh
printf 'name: Grafana\nimage: ghcr.io/mm-weber/dhc/grafana\n' > "$SB/image/grafana/image.yaml"
vex "$CVE1" "$GRAFANA_TAGGED" "$TEMPO"
run_case "a version against a definition with no tags fails" 1 "Req 6.20"

# 36: and versionless it is the shape this repo ships
fresh; vex "$CVE1" "$GRAFANA_PRODUCT" "$TEMPO"
refute_case "not_affected with a versionless product is not reported" 0 "::error"

# --- Req 6.31: versionless is an argument, not a default --------------------
#
# Compilation made scope meaningful and immediately made the default wrong.
# A versionless product claims every build of the image, forever, so a
# structural argument written about 13.0.4 keeps excusing the CVE on a 14.0
# nobody examined — demonstrated on the live lane, where compiling for a
# hypothetical 14.0.0 kept a statement argued in July 2026.
#
# Neither scope is right for both kinds of not_affected. "This image never
# starts a Prometheus server" is as true of 14.0 as of 13.0.4; "this build does
# not reach the symbol" rests on what this release links. Left to a default
# every statement drifts versionless, since that suppresses most and costs
# least to write, so the note is what turns it back into a decision.

# 38: versionless with notes that argue nothing about versions
fresh; NOTES="Architectural analysis of the shipped entrypoint; see triage/LOG.md 2026-07-26."
vex "$CVE1" "$GRAFANA_PRODUCT" "$TEMPO"
run_case "versionless without a version-independence note fails" 1
run_case "it is reported under Req 6.31" 1 "Req 6.31"
run_case "the message quotes the product" 1 "$GRAFANA_PRODUCT"
run_case "the message says what to write" 1 "version-independent:"
# The author needs the reason, not the rule: what a versionless claim covers is
# every future release, which is what makes an undefended one dangerous.
run_case "the message says why: it covers releases nobody examined" 1 "every"
run_case "the message names the file" 1 "triage/vex/$CVE1.openvex.json"

# 39: with the note it is the claim the author means to make
fresh; vex "$CVE1" "$GRAFANA_PRODUCT" "$TEMPO"
run_case "versionless with a version-independence note passes" 0
refute_case "a defended versionless claim emits no annotation" 0 "::error"

# 40: a tag-scoped claim needs no note — its scope already says what it covers,
#     and requiring one would be busywork on the safer of the two forms.
fresh; NOTES="Architectural analysis of the shipped entrypoint; see triage/LOG.md 2026-07-26."
vex "$CVE1" "$GRAFANA_TAGGED" "$TEMPO"
run_case "a tag-scoped claim needs no note" 0

# 41: no status_notes key at all is the same defect, not a different one
fresh
write_doc "$SB/triage/vex/$CVE1.openvex.json" "$(cat <<EOF
{
  "vulnerability": { "name": "$CVE1" },
  "products": [$(prod "$GRAFANA_PRODUCT" "$TEMPO")],
  "status": "not_affected",
  "justification": "vulnerable_code_not_in_execute_path",
  "timestamp": "2026-07-26T00:00:00Z"
}
EOF
)"
run_case "versionless with no status_notes at all fails" 1 "Req 6.31"

# 37: the version rule no longer depends on the status at all. What a version
# may be is a property of the source format — compilation looks a tag up
# against the build regardless of what the statement claims. Only 6.21's
# "fixed must carry one" is status-dependent.
fresh; vex_status '"under_investigation"' "$CVE1" "$GRAFANA_PINNED" "$TEMPO"
run_case "a digest fails on a status other than fixed too" 1 "Req 6.20"
fresh; vex_status '"affected"' "$CVE1" "$GRAFANA_TAGGED" "$TEMPO"
run_case "a published tag passes on a status other than fixed too" 0
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

# 49: a variant definition publishes under its sibling's name. image/valkey-compat/
# emits to ghcr.io/mm-weber/dhc/valkey as a `-compat` tag (docs/CONVENTIONS.md,
# "Naming"), so Trivy reads the product as `valkey` on either build and the tag
# is the only thing separating them. Resolving the purl name through the
# directory made the compat tags unwritable: the only spelling Trivy matches
# scored a Req 6.20 violation, and the spelling that satisfied the lint —
# `pkg:oci/valkey-compat` — is one compilation stamps into a product that
# matches nothing.
compat() { # add the variant definition beside the runtime one
  mkdir -p "$SB/image/valkey-compat"
  printf 'name: Valkey compat 9.1.x\nimage: ghcr.io/mm-weber/dhc/valkey\ntags:\n  - 9-alpine3.23-compat\n  - 9.1.1-alpine3.23-compat\n' > "$SB/image/valkey-compat/image.yaml"
}
VALKEY_COMPAT_TAGGED="pkg:oci/valkey@9.1.1-alpine3.23-compat?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fvalkey"

fresh; compat
write_doc "$SB/triage/vex/$CVE1.openvex.json" \
  "$(stmt_status '"fixed"' "$CVE1" "$(prod "$VALKEY_COMPAT_TAGGED" "$PROM")")"
run_case "a variant's published tag is a valid scope" 0
refute_case "the variant tag emits no annotation" 0 "::error"

# 50: the runtime sibling's tags stay valid under the same name — resolving to
# every definition that publishes the repository is a union, not a swap.
fresh; compat
write_doc "$SB/triage/vex/$CVE1.openvex.json" \
  "$(stmt_status '"fixed"' "$CVE1" "$(prod "pkg:oci/valkey@9-alpine3.23?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fvalkey" "$PROM")")"
run_case "the runtime sibling's tag still passes" 0

# 51: and a tag neither of them publishes is still caught, so the union widened
# the scope rather than removing the rule.
fresh; compat
write_doc "$SB/triage/vex/$CVE1.openvex.json" \
  "$(stmt_status '"fixed"' "$CVE1" "$(prod "pkg:oci/valkey@9.9.9-alpine3.23?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fvalkey" "$PROM")")"
run_case "a tag no definition publishes still fails" 1 "Req 6.20"

# 52: the directory name is not a product identifier. It names a real directory,
# which is exactly why the old resolution accepted it, and Trivy never produces
# it — the statement would pass review and suppress nothing.
fresh; compat
write_doc "$SB/triage/vex/$CVE1.openvex.json" \
  "$(stmt_status '"not_affected"' "$CVE1" "$(prod "pkg:oci/valkey-compat?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2Fvalkey" "$PROM")")"
run_case "a variant's directory name is not a product" 1 "valkey-compat"

echo
if [ "$FAILURES" -eq 0 ]; then echo "all lint-vex-product tests passed"; else echo "$FAILURES failing assertion(s)"; fi
exit $((FAILURES > 0))
