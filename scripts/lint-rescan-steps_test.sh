#!/usr/bin/env bash
# Tests for scripts/lint-rescan-steps.sh (review disposition D1, 2026-09-09):
# in the rescan workflow, every step after the scan step declares its own
# condition with `always()`, so no daily assertion or publication is
# suspended by an unrelated earlier failure. The lint reads the workflow as
# YAML, finds the step whose id is `scan`, and fails naming each later step
# whose `if:` is missing or lacks `always()`. Steps before the scan are the
# producers (login, install, enumerate) and are not judged.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LINT="$HERE/lint-rescan-steps.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }
expect() { # name, expected rc, actual rc, output, needles...
  local name="$1" want="$2" rc="$3" out="$4"; shift 4
  if [ "$rc" -ne "$want" ]; then fail "$name" "exit=$rc, wanted $want" "$out"; return; fi
  local n; for n in "$@"; do
    if ! grep -qF -- "$n" <<<"$out"; then fail "$name" "missing '$n'" "$out"; return; fi
  done
  pass "$name"
}
wf() { # writes $SB/rescan.yml from the step lines given
  { printf 'name: rescan\non:\n  schedule:\n    - cron: "17 6 * * *"\njobs:\n  rescan:\n    runs-on: ubuntu-latest\n    steps:\n'; printf '%s\n' "$@"; } > "$SB/rescan.yml"
}
fresh() { SB=$(mktemp -d); }

# 1: every step after the scan carries always(): exit 0, counts named
fresh
wf '      - name: enumerate' '        run: true' \
   '      - name: scan' '        id: scan' '        run: true' \
   '      - name: invariants' '        if: always() && steps.scan.outcome == '"'"'success'"'"'' '        run: true' \
   '      - name: summary' '        if: always()' '        run: true'
out=$("$LINT" "$SB/rescan.yml" 2>&1); rc=$?
expect "every later step conditioned on always(): exit 0" 0 "$rc" "$out" "2 step(s) after the scan"

# 2: a later step without an if: fails naming it
fresh
wf '      - name: scan' '        id: scan' '        run: true' \
   '      - name: authenticity signals' '        run: true' \
   '      - name: summary' '        if: always()' '        run: true'
out=$("$LINT" "$SB/rescan.yml" 2>&1); rc=$?
expect "a step without an if: is named" 1 "$rc" "$out" "authenticity signals" "always()"

# 3: an if: without always() fails naming it (a default-conditioned chain
#    silently inherits every earlier failure)
fresh
wf '      - name: scan' '        id: scan' '        run: true' \
   '      - name: posture' '        if: steps.scan.outcome == '"'"'success'"'"'' '        run: true'
out=$("$LINT" "$SB/rescan.yml" 2>&1); rc=$?
expect "an if: lacking always() is named" 1 "$rc" "$out" "posture"

# 4: steps before the scan are producers and not judged
fresh
wf '      - name: log in' '        run: true' \
   '      - name: enumerate' '        run: true' \
   '      - name: scan' '        id: scan' '        run: true'
out=$("$LINT" "$SB/rescan.yml" 2>&1); rc=$?
expect "producers before the scan are not judged" 0 "$rc" "$out" "0 step(s) after the scan"

# 5: no scan step at all is a refusal by name, not a vacuous pass
fresh
wf '      - name: enumerate' '        run: true' '      - name: summary' '        if: always()' '        run: true'
out=$("$LINT" "$SB/rescan.yml" 2>&1); rc=$?
expect "no step with id scan is refused" 1 "$rc" "$out" "id: scan"

# 7: a second job is a publication too (the catalogue page, task 15.8): it
#    passes when its own if: carries always(), fails by name when it does not
#    or when it declares none; the scan job is found by its scan step
fresh; wf '      - name: scan' '        id: scan' '        run: true' \
   '      - name: summary' '        if: always()' '        run: true'
printf '  page:\n    needs: rescan\n    if: always() && needs.rescan.outputs.page == %s\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/deploy-pages@abc\n' "'true'" >> "$SB/rescan.yml"
out=$("$LINT" "$SB/rescan.yml" 2>&1); rc=$?
expect "a second job conditioned on always() passes, counted" 0 "$rc" "$out" "1 step(s) after the scan" "1 other job(s) conditioned on always()"
fresh; wf '      - name: scan' '        id: scan' '        run: true'
printf '  page:\n    needs: rescan\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/deploy-pages@abc\n' >> "$SB/rescan.yml"
out=$("$LINT" "$SB/rescan.yml" 2>&1); rc=$?
expect "a second job without if: fails naming it" 1 "$rc" "$out" "job 'page' declares no if: (it needs one containing always())"
fresh; wf '      - name: scan' '        id: scan' '        run: true'
printf '  page:\n    needs: rescan\n    if: needs.rescan.result == %s\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/deploy-pages@abc\n' "'success'" >> "$SB/rescan.yml"
out=$("$LINT" "$SB/rescan.yml" 2>&1); rc=$?
expect "a second job whose if: lacks always() fails naming it" 1 "$rc" "$out" "job 'page' has if:" "without always()"
fresh; printf 'jobs:\n  a:\n    steps: []\n  b:\n    steps: []\n' > "$SB/rescan.yml"
out=$("$LINT" "$SB/rescan.yml" 2>&1); rc=$?
expect "no job has a scan step: refused by name" 1 "$rc" "$out" "no step with"

# 6: a missing or unparseable file is a refusal by name
out=$("$LINT" "$SB/nope.yml" 2>&1); rc=$?
expect "a missing workflow is refused" 1 "$rc" "$out" "nope.yml"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all lint-rescan-steps tests passed"
