#!/usr/bin/env bash
# Tests for scripts/release-policy.sh (review D3, 2026-09-09): the one reader
# of catalogue-policy.yaml's `release` section. Contract: each switch is
# returned only when it is written exactly as the criteria name it, and a
# misspelt or wrongly typed value is a refusal (exit 2) naming the key, the
# value and what is accepted, never a default. build.yml used to read the
# switches as raw strings and compare them to 'true' and 'on-change', so
# `yes`, `True` or `on_change` silently took the fail-open branch.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
RP="$HERE/release-policy.sh"
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
fresh() { SB=$(mktemp -d); policy; }
policy() { # a well-formed release section; overrides via sed in the cases
  cat > "$SB/catalogue-policy.yaml" <<'EOF'
release:
  public: true
  fail_closed: false
  publish_policy: on-change
  page: true
  schedule: &build_cron "47 4 * * *"
  platforms:
    - linux/amd64
    - linux/arm64
verification:
  registry: ghcr.io/acme/imgs
workflows:
  build.yml:
    schedule: *build_cron
EOF
}

# 1: every query returns the declared value, exactly
fresh
expect "public" 0 0 "$("$RP" "$SB" public)" "true"
[ "$("$RP" "$SB" fail-closed)" = "false" ] && pass "fail-closed" || fail "fail-closed" "$("$RP" "$SB" fail-closed 2>&1)"
[ "$("$RP" "$SB" publish-policy)" = "on-change" ] && pass "publish-policy" || fail "publish-policy" "$("$RP" "$SB" publish-policy 2>&1)"
[ "$("$RP" "$SB" schedule)" = "47 4 * * *" ] && pass "schedule" || fail "schedule" "$("$RP" "$SB" schedule 2>&1)"
[ "$("$RP" "$SB" platforms | paste -sd,)" = "linux/amd64,linux/arm64" ] && pass "platforms, one per line" || fail "platforms" "$("$RP" "$SB" platforms 2>&1)"
[ "$("$RP" "$SB" page)" = "true" ] && pass "page (Req 6.61)" || fail "page" "$("$RP" "$SB" page 2>&1)"
out=$("$RP" "$SB" check 2>&1); rc=$?
expect "check passes a well-formed section, naming the values" 0 "$rc" "$out" "fail_closed=false" "publish_policy=on-change" "page=true" "2 platform(s)"

# 2: the YAML 1.1 spellings PyYAML reads as booleans are refused: the two
#    dialects in play (mikefarah yq on the runner, PyYAML here) disagree on
#    them, and a switch two readers disagree on is not declared
for v in yes True on 1 '"true"'; do
  fresh; sed -i "s/^  fail_closed: false/  fail_closed: $v/" "$SB/catalogue-policy.yaml"
  out=$("$RP" "$SB" fail-closed 2>&1); rc=$?
  expect "fail_closed: $v is refused naming key and value" 2 "$rc" "$out" "fail_closed" "true or false"
done
fresh; sed -i "s/^  public: true/  public: yes/" "$SB/catalogue-policy.yaml"
out=$("$RP" "$SB" public 2>&1); rc=$?
expect "public: yes is refused" 2 "$rc" "$out" "public"

# 3: a publish policy outside the two the criteria name is refused
for v in on_change Always never; do
  fresh; sed -i "s/^  publish_policy: on-change/  publish_policy: $v/" "$SB/catalogue-policy.yaml"
  out=$("$RP" "$SB" publish-policy 2>&1); rc=$?
  expect "publish_policy: $v is refused" 2 "$rc" "$out" "publish_policy" "on-change or always"
done
fresh; sed -i "s/^  publish_policy: on-change/  publish_policy: always/" "$SB/catalogue-policy.yaml"
[ "$("$RP" "$SB" publish-policy)" = "always" ] && pass "publish_policy: always is accepted" || fail "always accepted"

# 4: a missing key is a refusal, never a default
fresh; sed -i "/^  fail_closed:/d" "$SB/catalogue-policy.yaml"
out=$("$RP" "$SB" fail-closed 2>&1); rc=$?
expect "a missing switch is refused naming it" 2 "$rc" "$out" "fail_closed"
out=$("$RP" "$SB" check 2>&1); rc=$?
expect "check refuses the same hole" 2 "$rc" "$out" "fail_closed"

fresh; sed -i "s/^  page: true/  page: yes/" "$SB/catalogue-policy.yaml"
out=$("$RP" "$SB" page 2>&1); rc=$?
expect "the page switch takes only true or false" 2 "$rc" "$out" "page is 'yes'"
fresh; sed -i "/^  page:/d" "$SB/catalogue-policy.yaml"
out=$("$RP" "$SB" check 2>&1); rc=$?
expect "check refuses a missing page switch" 2 "$rc" "$out" "page is missing"

# 5: platforms must be a non-empty list of os/arch pairs; the schedule a
#    five-field cron
fresh; sed -i "s#^    - linux/arm64#    - arm64#" "$SB/catalogue-policy.yaml"
out=$("$RP" "$SB" platforms 2>&1); rc=$?
expect "a platform without an os/ prefix is refused" 2 "$rc" "$out" "arm64"
fresh; sed -i 's/^  schedule: &build_cron "47 4 \* \* \*"/  schedule: \&build_cron "daily"/' "$SB/catalogue-policy.yaml"
out=$("$RP" "$SB" schedule 2>&1); rc=$?
expect "a schedule that is not a five-field cron is refused" 2 "$rc" "$out" "schedule"

# 6: no policy file, unknown query: refusals by name
out=$("$RP" "$SB/nope" public 2>&1); rc=$?
expect "no policy file is refused naming the root" 2 "$rc" "$out" "catalogue-policy.yaml"
out=$("$RP" "$SB" colour 2>&1); rc=$?
expect "an unknown query is refused" 2 "$rc" "$out" "colour"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all release-policy tests passed"
