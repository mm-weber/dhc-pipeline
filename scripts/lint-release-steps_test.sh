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

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all lint-release-steps tests passed"
