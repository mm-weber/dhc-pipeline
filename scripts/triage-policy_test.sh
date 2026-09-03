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

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all triage-policy tests passed"
