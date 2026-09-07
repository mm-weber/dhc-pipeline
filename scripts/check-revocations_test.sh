#!/usr/bin/env bash
# Tests for scripts/check-revocations.sh (task 13.3; Req 9.5 to 9.7): the
# revocation record read against the rescan's enumeration. A catalogue tag
# that still references a recorded digest, as its index or as one of its
# platform manifests, is a failure of the run by name; a recorded digest no
# tag references is what a revocation should look like the day after. The
# schema half (Req 9.6) is exercised through yamale with the real schema.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CHECK="$HERE/check-revocations.sh"
SCHEMA="$ROOT/triage/revocations.schema.yaml"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

A=$(printf 'a%.0s' $(seq 64)); B=$(printf 'b%.0s' $(seq 64)); C=$(printf 'c%.0s' $(seq 64)); D=$(printf 'd%.0s' $(seq 64)); E=$(printf 'e%.0s' $(seq 64))
SB=$(mktemp -d)
cat > "$SB/enum.tsv" <<EOF
ghcr.io/acme/dhc/solo	1-alpine3.23	sha256:$A	linux/amd64	sha256:$B	supported
ghcr.io/acme/dhc/solo	1-alpine3.23	sha256:$A	linux/arm64	sha256:$C	supported
ghcr.io/acme/dhc/valkey	9-alpine3.23	sha256:$D	linux/amd64	sha256:$E	supported
EOF
replaced() { # digest replacement
  cat <<EOF
  - image: ghcr.io/acme/dhc/solo
    digest: sha256:$1
    reason: the 1.0.0 build shipped a compromised upstream tarball
    replacement: sha256:$2
    advisory: https://github.com/acme/dhc/security/advisories/GHSA-abcd-ef12-3456
    date: 2026-09-07
EOF
}
withdrawn() { # digest
  cat <<EOF
  - image: ghcr.io/acme/dhc/valkey
    digest: sha256:$1
    reason: withdrawn, no fixed upstream release exists
    replacement: none
    withdrawal: delete-version
    advisory: https://github.com/acme/dhc/security/advisories/GHSA-1111-2222-3333
    date: 2026-09-07
EOF
}
run() { OUT=$("$CHECK" "$SB/revocations.yaml" "$SB/enum.tsv" "$SB/out.json" 2>&1); RC=$?; }
expect_in() { grep -qF -- "$2" <<<"$OUT" && pass "$1" || fail "$1: expected '$2'" "$OUT"; }

# 1: an empty record
printf 'revocations: []\n' > "$SB/revocations.yaml"; run
[ "$RC" -eq 0 ] && pass "empty: exit 0" || fail "empty: rc=$RC" "$OUT"
expect_in "empty: summary" "revocations: 0 recorded, 0 referenced by a catalogue tag"
jq -e '.revocations == [] and .referenced == []' "$SB/out.json" >/dev/null && pass "empty: record written" || fail "empty: record" "$(cat "$SB/out.json")"

# 2: a revoked digest no catalogue tag references (frozen, as it should be)
{ echo 'revocations:'; replaced "$(printf '9%.0s' $(seq 64))" "$A"; } > "$SB/revocations.yaml"; run
[ "$RC" -eq 0 ] && pass "frozen: exit 0" || fail "frozen: rc=$RC" "$OUT"
expect_in "frozen: summary" "revocations: 1 recorded, 0 referenced by a catalogue tag"
jq -e '(.revocations | length) == 1 and .revocations[0].replacement == ("sha256:" + "'"$A"'")' "$SB/out.json" >/dev/null && pass "frozen: entry carried in the record" || fail "frozen: record" "$(cat "$SB/out.json")"

# 3: a revoked index digest still referenced by a tag (both platform rows, named once)
{ echo 'revocations:'; replaced "$A" "$D"; } > "$SB/revocations.yaml"; run
[ "$RC" -ne 0 ] && pass "index referenced: exit non-zero" || fail "index referenced: rc=0" "$OUT"
expect_in "index referenced: names the tag and the digest" "ghcr.io/acme/dhc/solo:1-alpine3.23 references revoked digest sha256:$A"
expect_in "index referenced: cites the advisory" "GHSA-abcd-ef12-3456"
[ "$(grep -c "solo:1-alpine3.23 references" <<<"$OUT")" -eq 1 ] && pass "index referenced: one line per tag, not per platform" || fail "index referenced: duplicated lines" "$OUT"
expect_in "index referenced: summary" "1 referenced by a catalogue tag"
jq -e '.referenced == [{"image": "ghcr.io/acme/dhc/solo", "tag": "1-alpine3.23", "digest": "sha256:'"$A"'"}]' "$SB/out.json" >/dev/null && pass "index referenced: recorded" || fail "index referenced: record" "$(cat "$SB/out.json")"

# 4: a revoked platform manifest still referenced through its tag's index
{ echo 'revocations:'; withdrawn "$E"; } > "$SB/revocations.yaml"; run
[ "$RC" -ne 0 ] && pass "platform referenced: exit non-zero" || fail "platform referenced: rc=0" "$OUT"
expect_in "platform referenced: names the tag" "ghcr.io/acme/dhc/valkey:9-alpine3.23 references revoked digest sha256:$E"
expect_in "platform referenced: names the platform" "linux/amd64"

# 5: an unreadable record
printf 'revocations: [\n' > "$SB/revocations.yaml"; run
[ "$RC" -ne 0 ] && pass "unreadable: exit non-zero" || fail "unreadable: rc=0" "$OUT"
expect_in "unreadable: named" "revocations: unreadable"

# 6: a record without the list
printf 'other: 1\n' > "$SB/revocations.yaml"; run
[ "$RC" -ne 0 ] && pass "no list: exit non-zero" || fail "no list: rc=0" "$OUT"
expect_in "no list: named" "revocations: no revocations list"

# 7: the schema (Req 9.6), through yamale with the real schema
if command -v yamale >/dev/null 2>&1; then
  { echo 'revocations:'; replaced "$A" "$B"; withdrawn "$C"; } > "$SB/valid.yaml"
  yamale -s "$SCHEMA" "$SB/valid.yaml" >/dev/null 2>&1 && pass "schema: a replaced and a withdrawn entry validate" || fail "schema: valid entries refused" "$(yamale -s "$SCHEMA" "$SB/valid.yaml" 2>&1)"
  { echo 'revocations:'; replaced "$A" "$B" | sed '/advisory:/d'; } > "$SB/noadvisory.yaml"
  yamale -s "$SCHEMA" "$SB/noadvisory.yaml" >/dev/null 2>&1 && fail "schema: an entry without an advisory passed" || pass "schema: an entry without an advisory is refused"
  { echo 'revocations:'; replaced "not-a-digest" "$B"; } > "$SB/baddigest.yaml"
  yamale -s "$SCHEMA" "$SB/baddigest.yaml" >/dev/null 2>&1 && fail "schema: a malformed digest passed" || pass "schema: a malformed digest is refused"
  { echo 'revocations:'; withdrawn "$C" | sed '/withdrawal:/d'; } > "$SB/nowithdrawal.yaml"
  yamale -s "$SCHEMA" "$SB/nowithdrawal.yaml" >/dev/null 2>&1 && fail "schema: a withdrawal without its move passed" || pass "schema: a withdrawal without its move is refused"
  { echo 'revocations:'; replaced "$A" "$B" | sed 's#advisory: .*#advisory: https://example.com/notes#'; } > "$SB/badadvisory.yaml"
  yamale -s "$SCHEMA" "$SB/badadvisory.yaml" >/dev/null 2>&1 && fail "schema: a non-GHSA advisory passed" || pass "schema: a non-GHSA advisory link is refused"
else
  fail "schema: yamale is not installed, the Req 9.6 cases did not run"
fi

echo
if [ "$FAILURES" -eq 0 ]; then echo "all check-revocations tests passed"; else echo "$FAILURES test(s) failed"; exit 1; fi
