#!/usr/bin/env bash
# Tests for scripts/check-attestation-count.sh: the "exactly one OpenVEX
# attestation" invariant (task 10.3, Req 6.44, 6.45).
#
# crane is stubbed; what the suite pins is where the count is read (the .att
# tag beside each digest, index and platform manifests alike), what counts
# (OpenVEX layers only, an SPDX layer is not one), the verdicts and the naming.
# shellcheck disable=SC2015  # `test && pass || fail`: pass never fails, so the idiom is exact here
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-attestation-count.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }
att() { # <hex> <openvex layers> [<spdx layers>] -> writes the stub's manifest for sha256-<hex>.att
  local hex="$1" n="$2" spdx="${3:-1}" layers="" i
  for ((i = 0; i < spdx; i++)); do layers="${layers}{\"annotations\":{\"predicateType\":\"https://spdx.dev/Document\"}},"; done
  for ((i = 0; i < n; i++)); do layers="${layers}{\"annotations\":{\"predicateType\":\"https://openvex.dev/ns\"}},"; done
  printf '{"schemaVersion":2,"layers":[%s]}\n' "${layers%,}" > "$SB/att-${hex}.json"
}
fresh() {
  SB=$(mktemp -d); mkdir -p "$SB/bin"
  cat > "$SB/enum.tsv" <<'TSV'
ghcr.io/acme/dhc/grafana	13-alpine3.23	sha256:aa	linux/amd64	sha256:a1	supported
ghcr.io/acme/dhc/grafana	13-alpine3.23	sha256:aa	linux/arm64	sha256:a2	supported
ghcr.io/acme/dhc/grafana	13.1.3-alpine3.23	sha256:aa	linux/amd64	sha256:a1	supported
ghcr.io/acme/dhc/valkey	9.0.5-alpine3.23	sha256:bb	linux/amd64	sha256:b1	superseded
TSV
  cat > "$SB/bin/crane" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "crane $*" >> "${STUB_ARGV}"
[ "$1" = "manifest" ] || { echo "stub: unexpected $*" >&2; exit 2; }
ref="$2"; hex="${ref##*sha256-}"; hex="${hex%.att}"
f="${STUB_DIR}/att-${hex}.json"
[ -f "$f" ] || { echo "MANIFEST_UNKNOWN" >&2; exit 1; }
cat "$f"
STUB
  chmod +x "$SB/bin/crane"
  export STUB_ARGV="$SB/argv" STUB_DIR="$SB"; : > "$STUB_ARGV"
}
run() { PATH="$SB/bin:$PATH" "$CHECK" "$SB/enum.tsv" "$SB/out.json" 2>&1; }

# 1: exactly one everywhere passes, index and manifests both counted, each once
fresh; att aa 1; att a1 1; att a2 1; att bb 1; att b1 1
out=$(run); rc=$?
[ "$rc" -eq 0 ] && pass "exactly one OpenVEX attestation everywhere passes" || fail "exactly one everywhere should pass (rc=$rc)" "$out"
[ "$(grep -c '^crane manifest' "$STUB_ARGV")" -eq 5 ] && pass "every digest and manifest is read once, shared ones once" || fail "expected 5 manifest reads" "$(cat "$STUB_ARGV")"
grep -q 'sha256-aa.att' "$STUB_ARGV" && pass "the count is read from the .att tag beside the digest" || fail "no .att read" "$(cat "$STUB_ARGV")"
[ "$(jq '.checked' "$SB/out.json")" = "5" ] && pass "the JSON record counts what was checked" || fail "record" "$(cat "$SB/out.json")"

# 2: two OpenVEX layers on a platform manifest fail the run, by name
fresh; att aa 1; att a1 2; att a2 1; att bb 1; att b1 1
out=$(run); rc=$?
[ "$rc" -eq 1 ] && pass "two attestations on a manifest fail the run" || fail "should fail (rc=$rc)" "$out"
grep -q 'sha256:a1 (manifest) carries 2' <<<"$out" && pass "naming the manifest and the count" || fail "naming" "$out"
grep -q 'Req 6.44' <<<"$out" && pass "citing the requirement" || fail "requirement" "$out"
[ "$(jq '.deviations' "$SB/out.json")" = "1" ] && pass "and records one deviation" || fail "record" "$(cat "$SB/out.json")"

# 3: none is a deviation too (a digest publishing no decisions), including a
#    digest with no .att tag at all
fresh; att aa 1; att a1 1; att a2 0; att bb 1
out=$(run); rc=$?
[ "$rc" -eq 1 ] && pass "zero attestations fail the run" || fail "zero should fail (rc=$rc)" "$out"
grep -q 'sha256:a2 (manifest) carries 0' <<<"$out" && pass "an .att tag with no OpenVEX layer counts zero" || fail "zero named" "$out"
grep -q 'sha256:b1 (manifest) carries 0' <<<"$out" && pass "a missing .att tag counts zero, not an error" || fail "missing att" "$out"
[ "$(jq '.deviations' "$SB/out.json")" = "2" ] && pass "both deviations recorded" || fail "record" "$(cat "$SB/out.json")"

# 4: SPDX layers do not count; only the OpenVEX predicate type does
fresh; att aa 1 3; att a1 1 2; att a2 1 0; att bb 1 5; att b1 1 1
out=$(run); rc=$?
[ "$rc" -eq 0 ] && pass "other predicate types are not counted" || fail "spdx counted (rc=$rc)" "$out"

# 5: a missing enumeration is a usage error, never a clean run
fresh; out=$(PATH="$SB/bin:$PATH" "$CHECK" "$SB/absent.tsv" 2>&1); rc=$?
[ "$rc" -eq 2 ] && pass "a missing enumeration is refused" || fail "should be refused (rc=$rc)" "$out"

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES test(s) failed"; exit 1; fi
echo "all check-attestation-count tests passed"
