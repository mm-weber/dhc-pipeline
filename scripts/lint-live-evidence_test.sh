#!/usr/bin/env bash
# Tests for scripts/lint-live-evidence.sh: the live-evidence ledger covers
# every criterion (task 16.1, Req 7.11). docs/live-evidence.md carries one row
# per criterion the requirements name, and this lint holds that a criterion
# cannot arrive without its evidence obligation: every criterion number in
# requirements.md has exactly one row, every row names a criterion that
# exists (a retired number never gets a row back), every row carries one of
# the four statuses (exercised, defect, drill 16.N, unexercised) and every row
# says what its evidence or its reason is.
#
# Row shape, the ledger's own: a Markdown table row whose first cell is the
# criterion number:
#   | 6.55 | mechanism | status | first live exercise | evidence | induced by |
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LINT="$HERE/lint-live-evidence.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

fresh() { # a sandbox with a three-criterion spec; 2.2 is a retired number
  SB=$(mktemp -d); mkdir -p "$SB/.specs/dhc-catalogue-mvp" "$SB/docs"
  cat > "$SB/.specs/dhc-catalogue-mvp/requirements.md" <<'EOF'
# Requirements

## Requirements

### Requirement 1: One

1. THE Catalogue SHALL do the first thing.
2. THE Catalogue SHALL do the second thing.

### Requirement 2: Two

1. WHEN something happens THE CI Pipeline SHALL react.
3. IF a thing is wrong THEN THE CI Pipeline SHALL fail validation naming it.
EOF
}
ledger() { # writes the ledger from the rows given as arguments (full table rows)
  {
    echo "# Live evidence"
    echo
    echo "| Criterion | Mechanism | Status | First live exercise | Evidence | Induced by |"
    echo "|---|---|---|---|---|---|"
    printf '%s\n' "$@"
  } > "$SB/docs/live-evidence.md"
}
R11='| 1.1 | the first thing | exercised | 2026-07-21 | build run 29817266076 | nature |'
R12='| 1.2 | the second thing | defect | 2026-09-01 | the field is empty in every attested report, measured 2026-09-27 | nature |'
R21='| 2.1 | the reaction | drill 16.4 | | the step has run daily since 2026-07-29 with nothing to warn about | pull request |'
R23='| 2.3 | the refusal | unexercised | | no pull request has carried the violation; a 16.15 commit can add it | pull request |'
run() { "$LINT" "$SB" 2>&1; }

# 1: a complete ledger passes and the summary counts the statuses
fresh; ledger "$R11" "$R12" "$R21" "$R23"
out=$(run); rc=$?
[ "$rc" -eq 0 ] && grep -q "lint-live-evidence: 4 criteria, one ledger row each (1 exercised, 1 defect, 1 drill, 1 unexercised)" <<<"$out" \
  && pass "a complete ledger passes with the status counts" || fail "complete ledger" "rc=$rc" "$out"

# 2: a criterion without a row fails, naming the criterion and the ledger
fresh; ledger "$R11" "$R12" "$R21"
out=$(run); rc=$?
[ "$rc" -eq 1 ] && grep -q "::error file=docs/live-evidence.md::live evidence (Req 7.11): criterion 2.3 has no ledger row" <<<"$out" \
  && pass "a missing criterion is named" || fail "missing criterion" "rc=$rc" "$out"

# 3: a row for a number the requirements do not carry fails (2.2 is retired)
fresh; ledger "$R11" "$R12" "$R21" "$R23" '| 2.2 | a ghost | exercised | 2026-07-21 | run 1 | nature |'
out=$(run); rc=$?
[ "$rc" -eq 1 ] && grep -q "::error file=docs/live-evidence.md::live evidence (Req 7.11): row 2.2 names no criterion in requirements.md" <<<"$out" \
  && pass "a row for a retired number is refused" || fail "retired number" "rc=$rc" "$out"

# 4: two rows for one criterion fail
fresh; ledger "$R11" "$R12" "$R21" "$R23" "$R11"
out=$(run); rc=$?
[ "$rc" -eq 1 ] && grep -q "::error file=docs/live-evidence.md::live evidence (Req 7.11): criterion 1.1 has 2 ledger rows" <<<"$out" \
  && pass "a duplicate row is refused" || fail "duplicate row" "rc=$rc" "$out"

# 5: a status outside the four is refused, naming the row and the value
fresh; ledger "$R11" "$R12" "$R21" '| 2.3 | the refusal | pending | | later | pull request |'
out=$(run); rc=$?
[ "$rc" -eq 1 ] && grep -q "::error file=docs/live-evidence.md::live evidence (Req 7.11): row 2.3 status 'pending' is not exercised, defect, drill 16.N or unexercised" <<<"$out" \
  && pass "an unknown status is refused" || fail "unknown status" "rc=$rc" "$out"

# 6: a drill status must name a task of group 16
fresh; ledger "$R11" "$R12" '| 2.1 | the reaction | drill 15.2 | | later | pull request |' "$R23"
out=$(run); rc=$?
[ "$rc" -eq 1 ] && grep -q "row 2.1 status 'drill 15.2' is not exercised, defect, drill 16.N or unexercised" <<<"$out" \
  && pass "a drill outside group 16 is refused" || fail "drill outside 16" "rc=$rc" "$out"

# 7: an empty evidence cell is refused: every row says what it rests on or why not
fresh; ledger "$R11" "$R12" "$R21" '| 2.3 | the refusal | unexercised | | | pull request |'
out=$(run); rc=$?
[ "$rc" -eq 1 ] && grep -q "::error file=docs/live-evidence.md::live evidence (Req 7.11): row 2.3 carries no evidence or reason" <<<"$out" \
  && pass "an empty evidence cell is refused" || fail "empty evidence" "rc=$rc" "$out"

# 8: an empty mechanism cell is refused too
fresh; ledger '| 1.1 | | exercised | 2026-07-21 | run 1 | nature |' "$R12" "$R21" "$R23"
out=$(run); rc=$?
[ "$rc" -eq 1 ] && grep -q "::error file=docs/live-evidence.md::live evidence (Req 7.11): row 1.1 names no mechanism" <<<"$out" \
  && pass "an empty mechanism cell is refused" || fail "empty mechanism" "rc=$rc" "$out"

# 9: a row with too few cells is refused by shape, not silently skipped
fresh; ledger "$R11" "$R12" "$R21" '| 2.3 | the refusal | unexercised |'
out=$(run); rc=$?
[ "$rc" -eq 1 ] && grep -q "::error file=docs/live-evidence.md::live evidence (Req 7.11): row 2.3 has 3 cells, the ledger's rows have 6" <<<"$out" \
  && pass "a malformed row is refused" || fail "malformed row" "rc=$rc" "$out"

# 10: every failure is reported, not just the first
fresh; ledger "$R11" "$R12"
out=$(run); rc=$?
[ "$rc" -eq 1 ] && grep -q "criterion 2.1 has no ledger row" <<<"$out" && grep -q "criterion 2.3 has no ledger row" <<<"$out" \
  && pass "all missing criteria are named in one run" || fail "all failures reported" "rc=$rc" "$out"

# 11: no ledger is a non-evaluation, exit 2, never a pass
fresh; rm -f "$SB/docs/live-evidence.md"
out=$(run); rc=$?
[ "$rc" -eq 2 ] && grep -q "::error::lint-live-evidence: no docs/live-evidence.md under" <<<"$out" \
  && pass "a missing ledger is a refusal, exit 2" || fail "missing ledger" "rc=$rc" "$out"

# 12: no requirements file is a non-evaluation too
fresh; ledger "$R11"; rm -f "$SB/.specs/dhc-catalogue-mvp/requirements.md"
out=$(run); rc=$?
[ "$rc" -eq 2 ] && grep -q "::error::lint-live-evidence: no .specs/dhc-catalogue-mvp/requirements.md under" <<<"$out" \
  && pass "missing requirements are a refusal, exit 2" || fail "missing requirements" "rc=$rc" "$out"

# 13: the repository's own ledger covers the repository's own criteria
out=$("$LINT" "$HERE/.." 2>&1); rc=$?
[ "$rc" -eq 0 ] && grep -qE "lint-live-evidence: [0-9]+ criteria, one ledger row each" <<<"$out" \
  && pass "the real ledger covers the real requirements" || fail "real ledger" "rc=$rc" "$out"

echo
if [ "$FAILURES" -eq 0 ]; then echo "all lint-live-evidence tests passed"; else echo "$FAILURES lint-live-evidence test(s) FAILED"; exit 1; fi
