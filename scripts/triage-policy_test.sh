#!/usr/bin/env bash
# Tests for scripts/triage-policy.sh: the one reader of catalogue-policy.yaml's
# triage section (task 10.1, Req 6.49). Every consumer (the accepted-risk lint,
# the exception tiering, both scan arms, the issue filer) reads the aperture and
# the clocks through it, so a fork changes one file and every gate follows.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TP="$HERE/triage-policy.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

fresh() {
  SB=$(mktemp -d)
  cat > "$SB/catalogue-policy.yaml" <<'EOF'
triage:
  aperture: [CRITICAL, HIGH]
  ceilings:
    CRITICAL: 30d
    HIGH: 90d
  kev_ceiling: 14d
  expiry_warning: 14d
  kev_feed: https://example.invalid/kev.json
EOF
}
q() { "$TP" "$SB" "$@" 2>&1; }

fresh
[ "$(q aperture)" = "CRITICAL,HIGH" ] && pass "aperture is the declared list, in rank order" || fail "aperture is the declared list, in rank order" "$(q aperture)"
[ "$(q ceiling HIGH)" = "90" ] && pass "a ceiling reads as whole days" || fail "a ceiling reads as whole days" "$(q ceiling HIGH)"
[ "$(q ceiling CRITICAL)" = "30" ] && pass "per severity" || fail "per severity" "$(q ceiling CRITICAL)"
[ "$(q largest-ceiling)" = "90" ] && pass "the largest ceiling is the outer bound the lint uses" || fail "the largest ceiling" "$(q largest-ceiling)"
[ "$(q kev-ceiling)" = "14" ] && pass "the KEV ceiling" || fail "the KEV ceiling" "$(q kev-ceiling)"
[ "$(q expiry-warning)" = "14" ] && pass "the expiry warning window" || fail "the expiry warning window" "$(q expiry-warning)"
[ "$(q kev-feed)" = "https://example.invalid/kev.json" ] && pass "the KEV feed URL" || fail "the KEV feed URL" "$(q kev-feed)"

# A wider aperture is a fork switch: the order declared is the rank order, and
# every severity in it must carry a ceiling or the tiering has a hole.
fresh
cat > "$SB/catalogue-policy.yaml" <<'EOF'
triage:
  aperture: [CRITICAL, HIGH, MEDIUM]
  ceilings: {CRITICAL: 30d, HIGH: 90d, MEDIUM: 180d}
  kev_ceiling: 14d
  expiry_warning: 14d
  kev_feed: https://example.invalid/kev.json
EOF
[ "$(q aperture)" = "CRITICAL,HIGH,MEDIUM" ] && pass "a wider aperture reads through" || fail "a wider aperture reads through" "$(q aperture)"
[ "$(q largest-ceiling)" = "180" ] && pass "and the largest ceiling follows it" || fail "and the largest ceiling follows it" "$(q largest-ceiling)"

fresh
cat > "$SB/catalogue-policy.yaml" <<'EOF'
triage:
  aperture: [CRITICAL, HIGH]
  ceilings: {CRITICAL: 30d}
  kev_ceiling: 14d
  expiry_warning: 14d
  kev_feed: https://example.invalid/kev.json
EOF
out=$(q aperture); rc=$?
[ "$rc" -eq 2 ] && grep -q "HIGH" <<<"$out" && pass "an aperture severity without a ceiling refuses, naming it" || fail "an aperture severity without a ceiling refuses, naming it" "rc=$rc" "$out"

fresh
sed -i 's/HIGH: 90d/HIGH: 24h/' "$SB/catalogue-policy.yaml"
out=$(q ceiling HIGH); rc=$?
[ "$rc" -eq 2 ] && grep -q "24h" <<<"$out" && pass "a sub-day duration refuses: ceilings are whole days (dates in the schema)" || fail "a sub-day duration refuses" "rc=$rc" "$out"

fresh
out=$(q ceiling MEDIUM); rc=$?
[ "$rc" -eq 2 ] && pass "a ceiling for a severity outside the aperture refuses" || fail "a ceiling for a severity outside the aperture refuses" "rc=$rc" "$out"

fresh
printf 'triage: {}\n' > "$SB/catalogue-policy.yaml"
out=$(q aperture); rc=$?
[ "$rc" -eq 2 ] && grep -qi "aperture" <<<"$out" && pass "an empty triage section refuses, naming what is missing" || fail "an empty triage section refuses" "rc=$rc" "$out"

fresh
out=$(q nonsense); rc=$?
[ "$rc" -eq 2 ] && pass "an unknown query is a usage refusal" || fail "an unknown query is a usage refusal" "rc=$rc"

# The closing labels (task 10.6, Req 6.56) are declared per evidence grade; a
# missing grade is a hole, named.
fresh
out=$(q resolved-labels); rc=$?
[ "$rc" -eq 2 ] && grep -q "resolved_labels.fixed has no name" <<<"$out" && pass "no resolved labels declared: refused, naming the first missing grade" || fail "missing labels" "rc=$rc" "$out"
cat >> "$SB/catalogue-policy.yaml" <<'EOF'
  resolved_labels:
    fixed: {name: "resolved:fixed", color: "0E8A16", description: "bumped"}
    removed: {name: "resolved:removed", color: "0E8A16", description: "gone"}
    not_affected: {name: "resolved:not_affected", color: "1D76DB", description: "statement"}
    accepted: {name: "resolved:accepted", color: "FBCA04", description: "exception"}
    absent: {name: "resolved:absent", color: "C5DEF5", description: "absent"}
EOF
out=$(q resolved-labels); rc=$?
[ "$rc" -eq 0 ] && [ "$(jq -r '.accepted.name' <<<"$out")" = "resolved:accepted" ] && [ "$(jq 'length' <<<"$out")" = "5" ] \
  && pass "resolved-labels is the declared map as JSON, name, colour and description per grade" || fail "resolved-labels" "rc=$rc" "$out"
sed -i '/^    absent:/d' "$SB/catalogue-policy.yaml"
out=$(q resolved-labels); rc=$?
[ "$rc" -eq 2 ] && grep -q "resolved_labels.absent has no name" <<<"$out" && pass "one grade missing: refused by name" || fail "one grade missing" "rc=$rc" "$out"

# The VEX consumers (task 13.4, Req 9.11): a declared list with exactly one
# authoritative, read by both scan arms, the portability block and the daily
# smoke test. A list without exactly one authoritative is a hole, refused.
consumers_policy() { # <yaml body under consumers:>
  fresh
  { cat "$SB/catalogue-policy.yaml"; printf 'consumers:\n%s\n' "$1"; } > "$SB/p2" && mv "$SB/p2" "$SB/catalogue-policy.yaml"
}
consumers_policy '  list:
    - name: trivy
      authoritative: true
    - name: grype
      authoritative: false
  gating: false'
[ "$(q consumers)" = $'trivy\ttrue\ngrype\tfalse' ] && pass "consumers: name and authoritative flag per line, declared order" || fail "consumers list" "$(q consumers)"
[ "$(q authoritative-consumer)" = "trivy" ] && pass "the authoritative consumer by name" || fail "authoritative consumer" "$(q authoritative-consumer)"
[ "$(q other-consumers)" = "grype" ] && pass "the other consumers, one per line" || fail "other consumers" "$(q other-consumers)"
[ "$(q consumer-gating)" = "false" ] && pass "the divergence gating switch reads false" || fail "gating" "$(q consumer-gating)"
consumers_policy '  list:
    - name: trivy
      authoritative: true
    - name: grype
      authoritative: true
  gating: false'
out=$(q authoritative-consumer); rc=$?
[ "$rc" -eq 2 ] && grep -q "exactly one consumer must be authoritative" <<<"$out" && pass "two authoritative consumers: refused" || fail "two authoritative" "rc=$rc" "$out"
consumers_policy '  list:
    - name: trivy
      authoritative: false
  gating: false'
out=$(q consumers); rc=$?
[ "$rc" -eq 2 ] && grep -q "exactly one consumer must be authoritative" <<<"$out" && pass "no authoritative consumer: refused" || fail "no authoritative" "rc=$rc" "$out"
# Req 6.1 as amended (review D5): the gate is built on Trivy's ignore file
# and suppressed-finding reporting, so the authoritative consumer is Trivy
# by name; declaring another is a refusal that says what a fork must add.
consumers_policy '  list:
    - name: grype
      authoritative: true
    - name: trivy
      authoritative: false
  gating: false'
out=$(q authoritative-consumer); rc=$?
[ "$rc" -eq 2 ] && grep -q "gate adapter" <<<"$out" && grep -q "grype" <<<"$out" && pass "a non-Trivy authoritative consumer: refused naming the coupling (Req 6.1)" || fail "non-trivy authoritative" "rc=$rc" "$out"
fresh
out=$(q consumers); rc=$?
[ "$rc" -eq 2 ] && grep -q "consumers.list is missing" <<<"$out" && pass "no consumers section: refused by name" || fail "no consumers section" "rc=$rc" "$out"
consumers_policy '  list:
    - name: trivy
      authoritative: true
  gating: maybe'
out=$(q consumer-gating); rc=$?
[ "$rc" -eq 2 ] && grep -q "consumers.gating must be true or false" <<<"$out" && pass "a non-boolean gating switch: refused" || fail "gating non-boolean" "rc=$rc" "$out"

# The support statement (Req 6.49; review D7): declared once, read here,
# published by the status issue. A hole is a refusal like any other.
support_policy() { # <yaml body under triage.support:>
  fresh
  printf '  support:\n%s\n' "$1" >> "$SB/catalogue-policy.yaml"
}
support_policy '    supported_set: "the digests each definition'"'"'s current tags: reference"
    superseded: "scanned and attested daily; outside issue scope"'
expected='{"superseded": "scanned and attested daily; outside issue scope", "supported_set": "the digests each definition'"'"'s current tags: reference"}'
[ "$(q support)" = "$expected" ] && pass "support: both sentences as JSON, keys sorted" || fail "support statement" "$(q support)" "$expected"
fresh; out=$(q support); rc=$?
[ "$rc" -eq 2 ] && grep -q "support statement is missing: triage.support needs supported_set and superseded" <<<"$out" && pass "support: a missing statement is refused by name" || fail "support missing" "rc=$rc" "$out"
support_policy '    supported_set: "the digests each definition'"'"'s current tags: reference"
    superseded: ""'
out=$(q support); rc=$?
[ "$rc" -eq 2 ] && grep -q "support.superseded is empty" <<<"$out" && pass "support: an empty sentence is refused by name" || fail "support empty" "rc=$rc" "$out"
support_policy '    supported_set: [a, list]
    superseded: "x"'
out=$(q support); rc=$?
[ "$rc" -eq 2 ] && grep -q "support.supported_set is not a string" <<<"$out" && pass "support: a non-string sentence is refused by name" || fail "support non-string" "rc=$rc" "$out"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all triage-policy tests passed"
