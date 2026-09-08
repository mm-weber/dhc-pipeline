#!/usr/bin/env bash
# Tests for scripts/vex-portability.sh: the VEX portability block (task 13.4,
# Req 9.12). For each statement the authoritative consumer suppressed on a
# scanned artifact, each other consumer's result: agree (suppressed there
# too), DIVERGENCE (reported there, the statement did not land), or absent
# (that consumer does not know the finding at all: a database difference,
# not a matcher one). Informational by default; the policy file's gating
# switch makes a divergence fail.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
VP="$HERE/vex-portability.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

SB=$(mktemp -d); mkdir -p "$SB/root"; cp "$ROOT/catalogue-policy.yaml" "$SB/root/"
row() { # consumer vuln key suppressed by status
  printf '{"consumer":"%s","vulnerability":"%s","purl":"%s","key":"%s","suppressed":%s,"by":"%s","status":"%s"}\n' "$1" "$2" "$3" "$3" "$4" "$5" "$6"
}
{ row trivy CVE-2026-2001 pkg:golang/github.com/grafana/tempo@1.5.1 true vex not_affected
  row trivy CVE-2026-2002 pkg:apk/alpine/libssl3@3.5.7-r1 true vex fixed
  row trivy CVE-2026-2003 pkg:golang/stdlib@1.26.4 true vex not_affected
  row trivy CVE-2026-3001 pkg:golang/github.com/apache/thrift@0.23.1 true exception ""
  row trivy CVE-2026-1001 pkg:golang/github.com/apache/thrift@0.23.1 false none ""
} > "$SB/trivy.jsonl"
{ row grype CVE-2026-2001 pkg:golang/github.com/grafana/tempo@1.5.1 true vex not_affected
  row grype CVE-2026-2002 pkg:apk/alpine/libssl3@3.5.7-r1 false none ""
  row grype CVE-2026-1001 pkg:golang/github.com/apache/thrift@0.23.1 false none ""
} > "$SB/grype.jsonl"
run() { "$VP" --root "$SB/root" --label "$1" --out "$SB/block.md" --json "$SB/block.json" "${@:2}" 2>&1; }

# 1: the three outcomes, named per statement; exceptions are not statements
out=$(run "grafana@sha256:aaaa (linux/amd64)" "$SB/trivy.jsonl" "$SB/grype.jsonl"); rc=$?
[ "$rc" -eq 0 ] && pass "informational by default: exit 0 with a divergence" || fail "exit" "rc=$rc" "$out"
grep -q '| CVE-2026-2001 | `pkg:golang/github.com/grafana/tempo@1.5.1` | not_affected | agree |' "$SB/block.md" && pass "agree row" || fail "agree row" "$(cat "$SB/block.md")"
grep -qF '| CVE-2026-2002 | `pkg:apk/alpine/libssl3@3.5.7-r1` | fixed | **DIVERGENCE**, reported |' "$SB/block.md" && pass "divergence row: reported by the other consumer" || fail "divergence row" "$(cat "$SB/block.md")"
grep -q '| CVE-2026-2003 | `pkg:golang/stdlib@1.26.4` | not_affected | absent |' "$SB/block.md" && pass "absent row: the other consumer does not know the finding" || fail "absent row" "$(cat "$SB/block.md")"
grep -q 'CVE-2026-3001' "$SB/block.md" && fail "an exception is not a statement" "$(cat "$SB/block.md")" || pass "an exception-suppressed finding is not in the block"
grep -q 'CVE-2026-1001' "$SB/block.md" && fail "a reported finding is not a suppression" "$(cat "$SB/block.md")" || pass "a finding trivy reports is not in the block"
grep -q '^#### VEX portability (Req 9.12)' "$SB/block.md" && pass "the block has its heading" || fail "heading" "$(head -3 "$SB/block.md")"
grep -q 'grafana@sha256:aaaa (linux/amd64): 3 statement(s) trivy suppressed; grype: 1 agree, 1 DIVERGENCE, 1 absent' "$SB/block.md" && pass "the summary line counts per consumer" || fail "summary line" "$(cat "$SB/block.md")"
jq -e '.label == "grafana@sha256:aaaa (linux/amd64)" and .authoritative == "trivy" and .statements == 3 and .consumers.grype.agree == 1 and .consumers.grype.divergence == 1 and .consumers.grype.absent == 1 and (.rows | length) == 3' "$SB/block.json" >/dev/null && pass "the JSON record" || fail "json" "$(cat "$SB/block.json")"
grep -q 'stdlib@1.26.4' "$SB/block.md" && pass "rows show the canonical key" || fail "key shown" "$(cat "$SB/block.md")"

# 2: nothing suppressed: the block says so, one line, no table
{ row trivy CVE-2026-1001 pkg:golang/x@1 false none ""; } > "$SB/t2.jsonl"; : > "$SB/g2.jsonl"
out=$(run "solo@sha256:bbbb" "$SB/t2.jsonl" "$SB/g2.jsonl"); rc=$?
[ "$rc" -eq 0 ] && grep -q 'solo@sha256:bbbb: no statement suppressed by trivy today; nothing to compare' "$SB/block.md" && pass "no suppressions: stated, no table" || fail "no suppressions" "rc=$rc" "$(cat "$SB/block.md")"

# 3: a consumer whose record is missing (its scan failed) is named as unmeasured, not as agreement
out=$(run "grafana@sha256:aaaa" "$SB/trivy.jsonl" "$SB/nonexistent.jsonl"); rc=$?
[ "$rc" -eq 0 ] && grep -q 'grype: not measured (no record' "$SB/block.md" && pass "a missing consumer record is unmeasured, named" || fail "missing record" "rc=$rc" "$(cat "$SB/block.md")"

# 4: gating on: a divergence fails the run by name
sed -i 's/^  gating: false$/  gating: true/' "$SB/root/catalogue-policy.yaml"
out=$(run "grafana@sha256:aaaa" "$SB/trivy.jsonl" "$SB/grype.jsonl"); rc=$?
[ "$rc" -eq 1 ] && grep -q '::error::vex-portability: grafana@sha256:aaaa: CVE-2026-2002 (pkg:apk/alpine/libssl3@3.5.7-r1) suppressed by trivy is reported by grype (consumers.gating is true)' <<<"$out" && pass "gating: a divergence fails by name" || fail "gating" "rc=$rc" "$out"
sed -i 's/^  gating: true$/  gating: false/' "$SB/root/catalogue-policy.yaml"

# 5: the authoritative record must be the authoritative consumer's
out=$(run "x" "$SB/grype.jsonl" "$SB/trivy.jsonl"); rc=$?
[ "$rc" -eq 2 ] && grep -q "first record must be the authoritative consumer's (trivy), got grype" <<<"$out" && pass "the first record must be the authoritative consumer's" || fail "authoritative first" "rc=$rc" "$out"

# 6: several blocks append into one file (the rescan calls it per manifest)
run "a@sha256:1" "$SB/trivy.jsonl" "$SB/grype.jsonl" >/dev/null; cp "$SB/block.md" "$SB/all.md"
"$VP" --root "$SB/root" --label "b@sha256:2" --out "$SB/all.md" --append --json "$SB/b2.json" "$SB/trivy.jsonl" "$SB/grype.jsonl" >/dev/null
[ "$(grep -c '^#### VEX portability' "$SB/all.md")" -eq 1 ] && [ "$(grep -c 'statement(s) trivy suppressed' "$SB/all.md")" -eq 2 ] && pass "--append adds a section under the one heading" || fail "append" "$(cat "$SB/all.md")"

echo
if [ "$FAILURES" -eq 0 ]; then echo "all vex-portability tests passed"; else echo "$FAILURES test(s) failed"; exit 1; fi
