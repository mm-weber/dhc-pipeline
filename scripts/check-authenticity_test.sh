#!/usr/bin/env bash
# Tests for scripts/check-authenticity.sh: the daily re-verification of every
# definition's declared authenticity signal (Req 3.10; task 11.3) and the
# lapsed compat review-by report (Req 4.9). git ls-remote is stubbed, GitHub's
# verification statement and the publisher's version statement are served
# from file:// trees, the sidecars are files beside the "tarballs".
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-authenticity.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

COMMIT="4a12e725a55a520476eac1a4c123e8461024bbef"
TAGOBJ="5076ef4694884edd1d0c12ae890bf96bec08d528"
OTHER="1111111111111111111111111111111111111111"
A=$(printf 'a%.0s' $(seq 64)); B=$(printf 'b%.0s' $(seq 64)); C=$(printf 'c%.0s' $(seq 64))

fresh() {
  SB=$(mktemp -d); mkdir -p "$SB/root/image" "$SB/root/chart" "$SB/bin" "$SB/api" "$SB/dist" "$SB/versions"
  # git ls-remote: "<sha>\t<ref>" for the refs the stub is told about
  cat > "$SB/bin/git" <<'STUB'
#!/usr/bin/env bash
[ "$1" = ls-remote ] || { echo "stub git: unexpected $1" >&2; exit 2; }
printf 'git %s\n' "$*" >> "${STUB_DIR}/git.log"
ref="$3"
while IFS='|' read -r r sha; do
  if [ "$r" = "$ref" ]; then [ -n "$sha" ] && printf '%s\t%s\n' "$sha" "$ref"; exit 0; fi
done < "${STUB_DIR}/refs"
exit 0
STUB
  chmod +x "$SB/bin/git"
  : > "$SB/refs"
  export STUB_DIR="$SB" DHC_GITHUB_API="file://$SB/api" DHC_VERSIONS_API="file://$SB/versions" DHC_TODAY="2026-09-06"
}
git_def() { # name class repo tag checksum
  mkdir -p "$SB/root/image/$1"
  cat > "$SB/root/image/$1/image.yaml" <<DEF
image: ghcr.io/acme/dhc/$1
vars:
  VERSION: 1.0.0
contents:
  builds:
    - contents:
        files:
          - url: git+https://github.com/$3.git#$4
            # authenticity: $2
            checksum: $5
DEF
}
tarball_def() { # name amd64_sha arm64_sha version
  mkdir -p "$SB/root/image/$1"
  cat > "$SB/root/image/$1/image.yaml" <<DEF
image: ghcr.io/acme/dhc/$1
vars:
  APP_SHA256: '#{ target.arch == "amd64" ? "$2" : "$3" }'
  SEMVER_VERSION: $4
  VERSION: $4
contents:
  builds:
    - contents:
        files:
          - url: file://$SB/dist/app_\${target.arch}.tar.gz
            # authenticity: cross-origin-checksum
DEF
}
verification() { # tag|commit owner/repo sha verified reason
  local dir="$SB/api/repos/$2"
  if [ "$1" = tag ]; then mkdir -p "$dir/git/tags"; printf '{"object":{"sha":"x"},"verification":{"verified":%s,"reason":"%s"}}\n' "$4" "$5" > "$dir/git/tags/$3"
  else mkdir -p "$dir/commits"; printf '{"commit":{"verification":{"verified":%s,"reason":"%s"}}}\n' "$4" "$5" > "$dir/commits/$3"; fi
}
refs() { printf '%s\n' "$@" >> "$SB/refs"; } # "refs/tags/v1|<sha>" lines; an empty sha means absent
statement() { # version amd64 arm64
  printf '{"packages":[{"os":"linux","arch":"amd64","url":"https://x/app_%s_linux_amd64.tar.gz","sha256":"%s"},{"os":"linux","arch":"arm64","url":"https://x/app_%s_linux_arm64.tar.gz","sha256":"%s"}]}\n' "$1" "$2" "$1" "$3" > "$SB/versions/$1"
}
sidecars() { printf '%s\n' "$1" > "$SB/dist/app_amd64.tar.gz.sha256"; printf '%s\n' "$2" > "$SB/dist/app_arm64.tar.gz.sha256"; }
# The check re-verifies ACTIVE definitions (Req 3.10 as amended; task 14.2):
# a case that writes no policy file gets every definition it created listed,
# the pre-14.2 behaviour; a case about deactivation writes its own.
policy() { { printf 'active_set:\n'; printf '  - %s\n' "$@"; } > "$SB/root/catalogue-policy.yaml"; }
run() {
  [ -f "$SB/root/catalogue-policy.yaml" ] || policy $(ls "$SB/root/image")
  PATH="$SB/bin:$PATH" "$CHECK" "$SB/root" "$SB/out.jsonl" 2>&1
}
rec() { jq -r "$1" "$SB/out.jsonl"; }

# 1: every class verifies: exit 0, one record per definition, all ok
fresh
git_def cm signed-tag cert-manager/cert-manager v1.21.1 "$COMMIT"; refs "refs/tags/v1.21.1^{}|$COMMIT" "refs/tags/v1.21.1|$TAGOBJ"; verification tag cert-manager/cert-manager "$TAGOBJ" true valid
git_def valkey signed-commit valkey-io/valkey 9.1.2 "$COMMIT"; refs "refs/tags/9.1.2^{}|" "refs/tags/9.1.2|$COMMIT"; verification commit valkey-io/valkey "$COMMIT" true valid
tarball_def grafana "$A" "$B" 13.1.5; statement 13.1.5 "$A" "$B"; sidecars "$A" "$B"
out=$(run); rc=$?
[ "$rc" -eq 0 ] && pass "every declared signal verifies: exit 0" || fail "rc=$rc" "$out"
[ "$(rec 'select(.ok) | .definition' | sort | tr '\n' ' ')" = "cm grafana valkey " ] && pass "one ok record per definition" || fail "records" "$(cat "$SB/out.jsonl")"
grep -q "3 signal(s) verified, 0 mismatch(es)" <<<"$out" && pass "the summary line counts" || fail "summary" "$out"
grep -q "cm (signed-tag, v1.21.1): tag object 5076ef469488 on commit 4a12e725a55a, GitHub verification: valid" <<<"$out" && pass "signed-tag names the tag object and the commit" || fail "signed-tag detail" "$out"
grep -q "grafana (cross-origin-checksum, 13.1.5): amd64 aaaaaaaaaaaa… agreed by the" <<<"$out" && pass "cross-origin names both origins per architecture" || fail "cross-origin detail" "$out"

# 2: a tag that moved is a mismatch, named, and fails the run
fresh
git_def cm signed-tag cert-manager/cert-manager v1.21.1 "$COMMIT"; refs "refs/tags/v1.21.1^{}|$OTHER" "refs/tags/v1.21.1|$TAGOBJ"; verification tag cert-manager/cert-manager "$TAGOBJ" true valid
out=$(run); rc=$?
[ "$rc" -eq 1 ] && grep -q "::error::check-authenticity: cm (signed-tag, v1.21.1): tag v1.21.1 now points at 111111111111, the definition pins 4a12e725a55a: the tag moved (Req 3.10)" <<<"$out" && pass "a moved tag is a mismatch, by name" || fail "moved tag" "rc=$rc" "$out"
[ "$(rec 'select(.ok | not) | .definition')" = "cm" ] && pass "the record says which definition" || fail "record" "$(cat "$SB/out.jsonl")"

# 3: a signature that no longer verifies, a lightweight tag under signed-tag, a vanished tag
fresh
git_def app signed-commit acme/app v0.1.0 "$COMMIT"; refs "refs/tags/v0.1.0^{}|" "refs/tags/v0.1.0|$COMMIT"; verification commit acme/app "$COMMIT" false unsigned
git_def lw signed-tag acme/lw v1.0.0 "$COMMIT"; refs "refs/tags/v1.0.0^{}|" "refs/tags/v1.0.0|$COMMIT"
git_def gone signed-commit acme/gone v2.0.0 "$COMMIT"; refs "refs/tags/v2.0.0^{}|" "refs/tags/v2.0.0|"
out=$(run); rc=$?
[ "$rc" -eq 1 ] && pass "mismatches fail the run" || fail "rc=$rc" "$out"
grep -q "app (signed-commit, v0.1.0): GitHub reports commit 4a12e725a55a (v0.1.0) as not verified (unsigned)" <<<"$out" && pass "an unverified commit is named with GitHub's reason" || fail "unsigned" "$out"
grep -q "lw (signed-tag, v1.0.0): declared signed-tag, but v1.0.0 is a lightweight tag" <<<"$out" && pass "a lightweight tag under signed-tag is a mismatch" || fail "lightweight" "$out"
grep -q "gone (signed-commit, v2.0.0): tag v2.0.0 no longer exists" <<<"$out" && pass "a vanished tag is a mismatch" || fail "vanished" "$out"
[ "$(rec 'select(.ok | not) | .definition' | wc -l)" -eq 3 ] && pass "three records, all not ok" || fail "records" "$(cat "$SB/out.jsonl")"

# 4: the cross-origin checksum: a sidecar that changed, a statement that disagrees, a statement that is missing
fresh
tarball_def grafana "$A" "$B" 13.1.5; statement 13.1.5 "$A" "$B"; sidecars "$A" "$C"
out=$(run); rc=$?
[ "$rc" -eq 1 ] && grep -q "arm64: pinned bbbbbbbbbbbb…, origin sidecar cccccccccccc…, version statement bbbbbbbbbbbb… do not agree" <<<"$out" && pass "a sidecar that changed is named with every value" || fail "sidecar" "rc=$rc" "$out"
fresh
tarball_def grafana "$A" "$B" 13.1.5; statement 13.1.5 "$A" "$C"; sidecars "$A" "$B"
out=$(run); rc=$?
[ "$rc" -eq 1 ] && grep -q "version statement cccccccccccc… do not agree" <<<"$out" && pass "a disagreeing statement is named" || fail "statement" "rc=$rc" "$out"
fresh
tarball_def grafana "$A" "$B" 13.1.5; sidecars "$A" "$B"
out=$(run); rc=$?
[ "$rc" -eq 1 ] && grep -q "could not read the version statement" <<<"$out" && pass "a missing statement is a mismatch, not a pass" || fail "missing statement" "rc=$rc" "$out"

# 5: a definition without a verifiable class fails by name
fresh
mkdir -p "$SB/root/image/bare"; printf 'image: ghcr.io/acme/dhc/bare\nvars:\n  VERSION: 1.0.0\n' > "$SB/root/image/bare/image.yaml"
out=$(run); rc=$?
[ "$rc" -eq 1 ] && grep -q "bare (none, ?): no verifiable authenticity class declared" <<<"$out" && pass "no class: a mismatch, by name" || fail "no class" "rc=$rc" "$out"

# 6: Req 4.9: a lapsed compat review-by date is reported, a future one is not, and neither fails the run
fresh
git_def valkey signed-commit valkey-io/valkey 9.1.2 "$COMMIT"; refs "refs/tags/9.1.2^{}|" "refs/tags/9.1.2|$COMMIT"; verification commit valkey-io/valkey "$COMMIT" true valid
mkdir -p "$SB/root/chart/valkey" "$SB/root/chart/grafana"
printf 'upstream:\n  name: valkey\ncompat:\n  reason: the chart assumes a shell\n  issue: https://github.com/valkey-io/valkey-helm/issues/1\n  review_by: 2026-09-01\n' > "$SB/root/chart/valkey/chart.yaml"
printf 'upstream:\n  name: grafana\ncompat:\n  reason: x\n  review_by: 2026-12-01\n' > "$SB/root/chart/grafana/chart.yaml"
out=$(run); rc=$?
[ "$rc" -eq 0 ] && pass "a lapsed review-by date does not fail the run" || fail "rc=$rc" "$out"
grep -q "::warning::check-authenticity: chart valkey: the compat decision's review-by date 2026-09-01 has passed (today 2026-09-06)" <<<"$out" && pass "the lapse is reported by name" || fail "lapse" "$out"
grep -q "1 lapsed compat review-by date(s)" <<<"$out" && pass "and counted" || fail "count" "$out"
[ "$(rec 'select(.class == "compat" and .ok) | .definition')" = "chart/grafana" ] && pass "a future date is recorded as ahead" || fail "future" "$(cat "$SB/out.jsonl")"

# 7: Req 3.10 (task 14.2): an inactive definition is outside the tracking
#    scope, so its signal is not re-verified: a tag that moved under it does
#    not fail the run, no record is written for it, and the summary says so
fresh
git_def cm signed-tag cert-manager/cert-manager v1.21.1 "$COMMIT"; refs "refs/tags/v1.21.1^{}|$COMMIT" "refs/tags/v1.21.1|$TAGOBJ"; verification tag cert-manager/cert-manager "$TAGOBJ" true valid
git_def old signed-tag acme/old v1.0.0 "$COMMIT"; refs "refs/tags/v1.0.0^{}|$OTHER" "refs/tags/v1.0.0|$TAGOBJ"
policy cm
out=$(run); rc=$?
[ "$rc" -eq 0 ] && pass "an inactive definition's moved tag does not fail the run" || fail "inactive" "rc=$rc" "$out"
[ "$(rec '.definition' | sort | tr '\n' ' ')" = "cm " ] && pass "no record for the inactive definition" || fail "records" "$(cat "$SB/out.jsonl")"
grep -q "1 inactive definition(s) not re-verified" <<<"$out" && pass "the summary counts the inactive definition" || fail "summary" "$out"
grep -q "old" <<<"$(rec '.definition')" && fail "inactive not recorded" || pass "the inactive definition is named nowhere in the records"
# and a malformed set is the reader's refusal, not a silent empty scope
policy cm typo
out=$(run); rc=$?
[ "$rc" -eq 2 ] && grep -q "typo" <<<"$out" && pass "a malformed active set refuses naming the entry" || fail "malformed" "rc=$rc" "$out"

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES test(s) failed"; exit 1; fi
echo "all check-authenticity tests passed"
