#!/usr/bin/env bash
# Tests for scripts/render-tracking.sh (Req 1.14, 3.2, 3.11; task 14.2): the
# tracking scope is a rendered ignorePaths block between the
# `// render-tracking:begin` and `// render-tracking:end` markers of
# renovate.json5, listing every inactive definition directory and every chart
# directory deploying no active definition, so Renovate opens no bump for
# them. Rendered from catalogue-policy.yaml's active set and each chart's
# deploys list; --check fails naming the file when the committed block drifts
# (Req 7.9 pattern). Line-based splicing, never a JSON5 round trip: the file
# carries load-bearing comments.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
RENDER="$HERE/render-tracking.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

BEGIN='// render-tracking:begin'
END='// render-tracking:end'
fresh() {
  SB=$(mktemp -d)
  for n in app old older; do mkdir -p "$SB/image/$n"; printf 'image: ghcr.io/acme/imgs/%s\n' "$n" > "$SB/image/$n/image.yaml"; done
  mkdir -p "$SB/chart/app" "$SB/chart/old" "$SB/chart/mixed"
  printf 'deploys: [app]\n' > "$SB/chart/app/chart.yaml"
  printf 'deploys: [old, older]\n' > "$SB/chart/old/chart.yaml"
  printf 'deploys: [old, app]\n' > "$SB/chart/mixed/chart.yaml"
  printf 'active_set: [app]\n' > "$SB/catalogue-policy.yaml"
  cat > "$SB/renovate.json5" <<EOF
{
  // a load-bearing comment before the block
  enabledManagers: ["custom.regex"],
  $BEGIN
  ignorePaths: ["stale/**"],
  $END
  customManagers: [],
}
EOF
}
block() { sed -n "/render-tracking:begin/,/render-tracking:end/p" "$SB/renovate.json5"; }

# 1: an inactive definition and the charts deploying only inactive
#    definitions are listed; a chart deploying a mix is not; each entry
#    says why; the text outside the markers is untouched
fresh
out=$("$RENDER" "$SB" 2>&1); rc=$?
[ "$rc" -eq 0 ] && pass "render exits 0" || fail "render exits 0" "$out"
b=$(block)
grep -qF '"image/old/**"' <<<"$b" && pass "an inactive definition directory is ignored" || fail "an inactive definition directory is ignored" "$b"
grep -qF '"image/older/**"' <<<"$b" && pass "the second inactive definition too" || fail "the second inactive definition too" "$b"
grep -qF '"chart/old/**"' <<<"$b" && pass "a chart deploying only inactive definitions is ignored" || fail "a chart deploying only inactive definitions is ignored" "$b"
grep -qF 'chart/mixed' <<<"$b" && fail "a chart deploying an active definition is not ignored" "$b" || pass "a chart deploying an active definition is not ignored"
grep -qF 'image/app' <<<"$b" && fail "an active definition is not ignored" "$b" || pass "an active definition is not ignored"
grep -qF 'stale/**' <<<"$b" && fail "the stale block is replaced" "$b" || pass "the stale block is replaced"
grep -qE '^\s+ignorePaths: \[$' <<<"$b" && pass "the block is an ignorePaths array" || fail "the block is an ignorePaths array" "$b"
grep -qF 'inactive definition' <<<"$b" && pass "an entry says why it is ignored" || fail "an entry says why it is ignored" "$b"
grep -qF 'load-bearing comment' "$SB/renovate.json5" && grep -qF 'customManagers: [],' "$SB/renovate.json5" && pass "text outside the markers untouched" || fail "text outside the markers untouched" "$(cat "$SB/renovate.json5")"
# the rendered block must be JSON5 the validator can read: no trailing garbage,
# one entry per line, each a quoted glob followed by a comma
entries=$(grep -E '^\s+"(image|chart)/' <<<"$b")
[ "$(wc -l <<<"$entries")" -eq 3 ] && pass "exactly three entries" || fail "exactly three entries" "$entries"
grep -vqE '^\s+"[a-z/*.-]+",( //.*)?$' <<<"$entries" && fail "every entry is a quoted glob with a trailing comma" "$entries" || pass "every entry is a quoted glob with a trailing comma"

# 2: everything active renders an empty array, the reference instance's shape
fresh; printf 'active_set: [app, old, older]\n' > "$SB/catalogue-policy.yaml"
"$RENDER" "$SB" >/dev/null 2>&1
b=$(block)
grep -qE '^\s+ignorePaths: \[\],$' <<<"$b" && pass "all active renders ignorePaths: []" || fail "all active renders ignorePaths: []" "$b"

# 3: idempotent, --check clean, --check names drift
fresh; "$RENDER" "$SB" >/dev/null 2>&1; cp "$SB/renovate.json5" "$SB/first"
"$RENDER" "$SB" >/dev/null 2>&1
cmp -s "$SB/renovate.json5" "$SB/first" && pass "render is idempotent" || fail "render is idempotent"
out=$("$RENDER" --check "$SB" 2>&1); rc=$?
[ "$rc" -eq 0 ] && pass "--check on a rendered tree exits 0" || fail "--check on a rendered tree exits 0" "$out"
sed -i 's#"image/old/\*\*"#"image/elsewhere/**"#' "$SB/renovate.json5"
out=$("$RENDER" --check "$SB" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && grep -qF "renovate.json5" <<<"$out" && grep -qF "Req 7.9" <<<"$out"; then pass "--check fails naming the drifted file"; else fail "--check fails naming the drifted file" "exit=$rc" "$out"; fi
# --check writes nothing
grep -qF 'image/elsewhere' "$SB/renovate.json5" && pass "--check leaves the file as it found it" || fail "--check leaves the file as it found it"

# 4: a malformed active set is the reader's refusal, not a rendered guess
fresh; printf 'active_set: [app, typo]\n' > "$SB/catalogue-policy.yaml"
out=$("$RENDER" "$SB" 2>&1); rc=$?
[ "$rc" -ne 0 ] && grep -qF "typo" <<<"$out" && pass "a malformed active set refuses naming the entry" || fail "a malformed active set refuses naming the entry" "exit=$rc" "$out"

# 5: missing markers fail naming the file and the marker
fresh; printf '{\n  enabledManagers: [],\n}\n' > "$SB/renovate.json5"
out=$("$RENDER" "$SB" 2>&1); rc=$?
[ "$rc" -ne 0 ] && grep -qF "renovate.json5" <<<"$out" && grep -qF "render-tracking:begin" <<<"$out" && pass "missing markers fail naming file and marker" || fail "missing markers fail naming file and marker" "exit=$rc" "$out"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all render-tracking tests passed"
