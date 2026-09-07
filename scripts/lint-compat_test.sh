#!/usr/bin/env bash
# Tests for scripts/lint-compat.sh: the compat decision's review-by clock
# (Req 4.8; task 11.4). A sandbox of chart/<name>/chart.yaml files; DHC_TODAY
# pins the day.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LINT="$HERE/lint-compat.sh"
FAILURES=0
run_case() { # name expected_exit [substring]
  local name="$1" expected="$2" substr="${3:-}" out rc
  out=$(DHC_TODAY=2026-09-06 "$LINT" "$SB" 2>&1); rc=$?
  if [ "$rc" -ne "$expected" ]; then echo "FAIL $name: exit $rc, expected $expected"; echo "$out" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); return; fi
  if [ -n "$substr" ] && ! grep -qF "$substr" <<<"$out"; then echo "FAIL $name: output missing '$substr'"; echo "$out" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); return; fi
  echo "ok   $name"
}
fresh() { SB=$(mktemp -d); mkdir -p "$SB/chart/valkey" "$SB/chart/grafana"; printf 'upstream:\n  name: grafana\n  repository: https://x\n  version: 1.0.0\n' > "$SB/chart/grafana/chart.yaml"; }
compat() { # review_by [decided_at]
  printf 'upstream:\n  name: valkey\n  repository: https://x\n  version: 0.11.0\ncompat:\n  variant: valkey-compat\n  reason: a shell is needed\n  issue: triage/upstream/x.md\n  decided_at: %s\n  review_by: %s\n' "${2:-2026-08-25}" "$1" > "$SB/chart/valkey/chart.yaml"
}

# 1: no compat block anywhere is the ordinary chart, not a failure
fresh; rm -f "$SB/chart/valkey/chart.yaml"
run_case "a chart without a compat decision passes" 0 "0 compat decision(s)"

# 2: a review-by date ahead passes and is reported with the days left
fresh; compat 2026-11-24
run_case "a future review-by date passes" 0 "review by 2026-11-24 (79 day(s) ahead)"

# 3: the day itself is still ahead (the same rule as expired_at: live through the day)
fresh; compat 2026-09-06
run_case "the review-by day itself still passes" 0

# 4: a past review-by date fails, naming the chart, the date and the remedy
fresh; compat 2026-09-01
run_case "a past review-by date fails" 1 "::error file=chart/valkey/chart.yaml::compat decision (Req 4.8): review_by 2026-09-01 has passed (today 2026-09-06); record a dated re-decision"

# 5: a clock running backwards fails
fresh; compat 2026-08-01 2026-08-25
run_case "review_by before decided_at fails" 1 "a clock running backwards"

# 6: a missing or malformed date fails by name
fresh; compat "next quarter"
run_case "a non-date review_by fails" 1 "review_by is missing or not a YYYY-MM-DD date"
fresh; printf 'upstream:\n  name: valkey\n  repository: https://x\n  version: 0.11.0\ncompat:\n  variant: valkey-compat\n  reason: r\n  issue: i\n  review_by: 2026-11-24\n' > "$SB/chart/valkey/chart.yaml"
run_case "a missing decided_at fails" 1 "decided_at is missing"

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES test(s) failed"; exit 1; fi
echo "all lint-compat tests passed"
