#!/usr/bin/env bash
# Tests for scripts/lint-probes.sh (Req 5.8; task 14.3): every active
# definition is deployed by a chart that declares a functional probe
# (`probe:` in chart/<c>/chart.yaml), or validate fails naming the
# definition. The lint reads YAML only; whether a declared probe name has a
# registration in the e2e suite is the Go side's test
# (test/e2e, TestProbeDeclarations). An inactive definition with no probe is
# not a violation: nothing installs it. There is no placeholder value: a
# chart with nothing to prove declares no probe and its definitions stay
# inactive, never a probe that passes by doing nothing.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LINT="$HERE/lint-probes.sh"
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

fresh() {
  SB=$(mktemp -d)
  for n in app cm-a cm-b db db-compat old; do mkdir -p "$SB/image/$n"; printf 'image: ghcr.io/acme/imgs/%s\n' "$n" > "$SB/image/$n/image.yaml"; done
  chart app "http-200" app
  chart cm "certificate-issuance" cm-a cm-b
  chart db "set-get" db-compat db
  chart old "" old
  policy app cm-a cm-b db db-compat
}
chart() { # dir probe deploys...
  mkdir -p "$SB/chart/$1"; local d="$1" p="$2"; shift 2
  { [ -n "$p" ] && printf 'probe: %s\n' "$p"; printf 'deploys:\n'; printf '  - %s\n' "$@"; } > "$SB/chart/$d/chart.yaml"
}
policy() { { printf 'active_set:\n'; printf '  - %s\n' "$@"; } > "$SB/catalogue-policy.yaml"; }
# proofs: append a proofs: block to the policy file; each argument is one line, already indented relative to its entry
proofs() { printf 'proofs:\n' >> "$SB/catalogue-policy.yaml"; printf '  %s\n' "$@" >> "$SB/catalogue-policy.yaml"; }

# 1: every active definition is deployed by a chart with a probe; the
#    summary counts definitions and the distinct probes covering them
fresh
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "every active definition covered: exit 0" 0 "$rc" "$out" "5 active definition(s)" "3 probe"

# 2: an inactive definition deployed by a chart without a probe is fine
fresh
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "an uncovered inactive definition is not a violation" 0 "$rc" "$out"

# 3: activate it: the violation names the definition and the chart
fresh; policy app cm-a cm-b db db-compat old
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "an active definition whose chart declares no probe fails naming both" 1 "$rc" "$out" "old" "chart/old/chart.yaml" "Req 5.8"

# 4: an active definition no chart deploys at all fails naming it
fresh; mkdir -p "$SB/image/lonely"; printf 'image: ghcr.io/acme/imgs/lonely\n' > "$SB/image/lonely/image.yaml"
policy app cm-a cm-b db db-compat lonely
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "an active definition deployed by no chart fails naming it" 1 "$rc" "$out" "lonely" "no chart" "Req 5.8"

# 5: a shared registration covers every definition its chart deploys, once:
#    the three-definition chart counts one probe
fresh; policy cm-a cm-b
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "one chart, one probe, several definitions" 0 "$rc" "$out" "2 active definition(s)" "1 probe"

# 6: the probe value must be a name, not a placeholder or a structure
fresh; printf 'probe: ""\ndeploys: [app]\n' > "$SB/chart/app/chart.yaml"
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "an empty probe string declares nothing" 1 "$rc" "$out" "app" "Req 5.8"
fresh; printf 'probe: [http-200]\ndeploys: [app]\n' > "$SB/chart/app/chart.yaml"
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "a non-string probe is refused naming the chart" 1 "$rc" "$out" "chart/app/chart.yaml"

# 7: a malformed active set is the reader's refusal, surfaced by name
fresh; policy app typo
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "a malformed active set fails naming the entry" 1 "$rc" "$out" "typo"

# 8: an active definition no chart deploys passes when the policy file declares a none proof for it, and the declaration is printed by name (Req 5.9)
fresh; mkdir -p "$SB/image/lonely"; printf 'image: ghcr.io/acme/imgs/lonely\n' > "$SB/image/lonely/image.yaml"
policy app cm-a cm-b db db-compat lonely
proofs 'lonely:' '  kind: none' '  reason: drill fixture' '  review_by: "2026-11-28"'
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "a declared none proof covers an uncovered active definition and is printed by name" 0 "$rc" "$out" "lonely" "proof none" "drill fixture" "2026-11-28" "Req 5.9"

# 9: the summary counts the declared none proofs beside the probe registrations (Req 5.9)
fresh; mkdir -p "$SB/image/lonely"; printf 'image: ghcr.io/acme/imgs/lonely\n' > "$SB/image/lonely/image.yaml"
policy app cm-a cm-b db db-compat lonely
proofs 'lonely:' '  kind: none' '  reason: drill fixture' '  review_by: "2026-11-28"'
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "the summary counts declared none proofs" 0 "$rc" "$out" "6 active definition(s)" "1 declared none"

# 10: a none proof whose review_by date has passed fails naming the definition and the date (Req 5.10); DHC_TODAY is the clock seam
fresh; mkdir -p "$SB/image/lonely"; printf 'image: ghcr.io/acme/imgs/lonely\n' > "$SB/image/lonely/image.yaml"
policy app cm-a cm-b db db-compat lonely
proofs 'lonely:' '  kind: none' '  reason: drill fixture' '  review_by: "2026-11-28"'
out=$(DHC_TODAY=2026-12-01 "$LINT" "$SB" 2>&1); rc=$?
expect "a lapsed none proof fails by name" 1 "$rc" "$out" "lonely" "2026-11-28" "lapsed" "Req 5.10"

# 11: a review_by equal to today has not passed; the boundary is strictly before today (Req 5.10)
fresh; mkdir -p "$SB/image/lonely"; printf 'image: ghcr.io/acme/imgs/lonely\n' > "$SB/image/lonely/image.yaml"
policy app cm-a cm-b db db-compat lonely
proofs 'lonely:' '  kind: none' '  reason: drill fixture' '  review_by: "2026-11-28"'
out=$(DHC_TODAY=2026-11-28 "$LINT" "$SB" 2>&1); rc=$?
expect "a review_by equal to today has not lapsed" 0 "$rc" "$out" "lonely" "proof none" "Req 5.9"

# 12: the undeclared, uncovered refusal names the three ways out: a chart with a probe, a declared none proof, deactivation (Req 5.8)
fresh; mkdir -p "$SB/image/lonely"; printf 'image: ghcr.io/acme/imgs/lonely\n' > "$SB/image/lonely/image.yaml"
policy app cm-a cm-b db db-compat lonely
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "the uncovered refusal names the none way out" 1 "$rc" "$out" "lonely" "no chart" "proof of kind none" "Req 5.8"

# 13: a none proof for a definition a chart deploys is a contradiction: one proof per definition, the stale entry must go (Req 5.8, 5.9)
fresh
proofs 'app:' '  kind: none' '  reason: stale record' '  review_by: "2026-11-28"'
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "a none proof for a chart-deployed definition fails naming both" 1 "$rc" "$out" "app" "chart/app/chart.yaml" "none" "Req 5.9"

# 14: a refusal from the proofs reader is the lint's failure by name, nothing else checked (Req 5.11; the malformed active set precedent)
fresh
proofs 'app:' '  kind: smoke'
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "a reader refusal surfaces by name and stops the lint" 1 "$rc" "$out" "app" "smoke" "Req 5.11" "nothing checked"

# 15: this repository: every active definition chart-proved, no declared none proof, the lint green (the live state the reference instance ships)
out=$("$LINT" "$HERE/.." 2>&1); rc=$?
expect "the repository passes with zero declared none proofs" 0 "$rc" "$out" "7 active definition(s)" "0 declared none"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all lint-probes tests passed"
