#!/usr/bin/env bash
# Tests for scripts/lint-release-steps.sh (Req 2.26): in the build workflow's
# release job the rule is the opposite of the rescan workflow's (review
# disposition D1, scripts/lint-rescan-steps.sh). A pushed digest whose
# release-time scan produced no report, or left a platform manifest
# unscanned, is signed by nothing, attested by nothing and carries no tag, so
# every step after the step whose id is `relscan` must keep GitHub's default
# step condition, success(): the fail-closed gate, the report attestations,
# the OpenVEX compilation, the signing and the tagging are all stopped by a
# failed scan. An `always()`, a `failure()`, a `!cancelled()` or a
# `success() ||` added to any of them would publish that digest anyway. The
# lint reads the workflow as YAML, finds the `relscan` step, and fails naming
# each later step whose condition escapes that default. Steps before the scan
# are the producers (metadata, build, manifest enumeration) and are not
# judged.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LINT="$HERE/lint-release-steps.sh"
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
wf() { # writes $SB/build.yml: a release job made of the step lines given
  { printf 'name: build\non:\n  push:\n    branches: [main]\njobs:\n  release:\n    runs-on: ubuntu-latest\n    steps:\n'; printf '%s\n' "$@"; } > "$SB/build.yml"
}
fresh() { SB=$(mktemp -d); }

# 1: a step after the scan that escapes the default condition is named, with
#    the requirement it breaks, so the violation cannot pass unnoticed
fresh
wf '      - name: resolve the definition metadata' '        id: meta' '        run: true' \
   '      - name: build and push by digest' '        id: build' '        run: true' \
   '      - name: release-time scan of the pushed digest (Req 2.8)' '        id: relscan' '        run: true' \
   '      - name: sign and attest (Req 2.9)' '        if: always() && github.ref == '"'"'refs/heads/main'"'"'' '        run: true'
out=$("$LINT" "$SB/build.yml" 2>&1); rc=$?
expect "a release step that runs after a failure is refused by name" 1 "$rc" "$out" "sign and attest" "Req 2.26"


# 2: a workflow the lint cannot judge is a refusal, not a vacuous pass. A path
#    that is not there, a file that is not parseable YAML, and a release job in
#    which no step carries `id: relscan` each leave the lint without the
#    boundary Req 2.26 is measured from. Printing the success summary for any of
#    them would clear a release whose conditions were never read, and a Python
#    traceback is no refusal either: it cites no requirement and tells a
#    reviewer nothing to fix. So each input stops the lint by name, naming the
#    file and the requirement, and reports no step count it never judged.
report=""
accepted=0
fresh
wf '      - name: resolve the definition metadata' '        id: meta' '        run: true' \
   '      - name: build and push by digest' '        id: build' '        run: true'
printf '%s\n' ': this is not: valid yaml: [' > "$SB/broken.yml"
for shape in missing unparseable no-relscan; do
  case "$shape" in
    missing)     target="$SB/absent-build.yml" ;;
    unparseable) target="$SB/broken.yml" ;;
    no-relscan)  target="$SB/build.yml" ;;
  esac
  out=$("$LINT" "$target" 2>&1); rc=$?
  if [ "$rc" -eq 0 ]; then accepted=$((accepted+1)); fi
  if grep -qF -- "$target" <<<"$out"; then named_path=yes; else named_path=no; fi
  if grep -qF -- "Req 2.26" <<<"$out"; then named_req=yes; else named_req=no; fi
  if grep -qF -- "Traceback" <<<"$out"; then traced=present; else traced=none; fi
  if grep -qF -- "step(s) after the release-time scan" <<<"$out"; then summary=printed; else summary=absent; fi
  report="$report
$shape: exit $rc
$shape: names the path: $named_path
$shape: names Req 2.26: $named_req
$shape: traceback: $traced
$shape: success summary: $summary
$shape: said: $out"
done
# The exit slot carries how many of the three workflows the lint accepted: a
# boundary it cannot find must stop it every time, so that count is 0.
expect "a workflow it cannot judge is refused, never a vacuous pass" 0 "$accepted" "$report" \
  "missing: exit 1" \
  "missing: names the path: yes" \
  "missing: names Req 2.26: yes" \
  "missing: traceback: none" \
  "missing: success summary: absent" \
  "unparseable: exit 1" \
  "unparseable: names the path: yes" \
  "unparseable: names Req 2.26: yes" \
  "unparseable: traceback: none" \
  "unparseable: success summary: absent" \
  "no-relscan: exit 1" \
  "no-relscan: names the path: yes" \
  "no-relscan: names Req 2.26: yes" \
  "no-relscan: traceback: none" \
  "no-relscan: success summary: absent"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all lint-release-steps tests passed"
