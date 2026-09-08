#!/usr/bin/env bash
# Tests for scripts/lint-log-anchors.sh: F13's mechanical link (task 13.6,
# Req 9.18). triage/LOG.md stays prose; what the lint holds is that every
# accepted-risk exception's `ref:` and every VEX source statement's log
# citation resolves to a real heading, and that every decision carries one.
# Two citation forms, as the records already use them: `LOG.md#<slug>` (the
# heading's GitHub slug: lowercased, punctuation dropped, spaces to dashes)
# and `LOG.md <YYYY-MM-DD>` (a day heading of that date).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LINT="$HERE/lint-log-anchors.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

fresh() {
  SB=$(mktemp -d); mkdir -p "$SB/triage/accepted-risk" "$SB/triage/vex"
  cat > "$SB/triage/LOG.md" <<'EOF'
# triage log

## Rules this log holds itself to

prose

## 2026-08-04 — first treatment: CVE-2026-27145 (#22)

### TRANSFER — stdlib CVE-2026-27145, two bundled plugin binaries (#22)

reasoning

## 2026-08-05 — CVE-2026-21728 is fixed in what we ship (#23)

### FIXED — `github.com/grafana/tempo`, scoped to 13.1.1-alpine3.23 (#23)

reasoning
EOF
}
exception() { # file ref (the ignorefile shape: a vulnerabilities: list)
  cat > "$1" <<EOF
vulnerabilities:
  - id: CVE-2026-27145
    treatment: transfer
    owner: maintainer
    ref: "$2"
    blocked: "no release"
    statement: "transfer: waiting"
    decided_at: 2026-08-04
    expired_at: 2026-10-04
EOF
}
statement() { # file status notes
  cat > "$1" <<EOF
{"@context":"https://openvex.dev/ns/v0.2.0","@id":"x","author":"t","timestamp":"2026-08-05T00:00:00Z","version":1,
 "statements":[{"vulnerability":{"name":"CVE-2026-21728"},"status":"$2","products":[{"@id":"pkg:oci/grafana@13.1.5-alpine3.23"}],"status_notes":"$3"}]}
EOF
}
run() { "$LINT" "$@" "$SB" 2>&1; }

# 1: both halves resolve: a slug ref, a dated citation
fresh
exception "$SB/triage/accepted-risk/grafana.yaml" "LOG.md#transfer--stdlib-cve-2026-27145-two-bundled-plugin-binaries-22"
statement "$SB/triage/vex/CVE-2026-21728.openvex.json" fixed "Commit ancestry; see triage/LOG.md 2026-08-05."
out=$(run all); rc=$?
[ "$rc" -eq 0 ] && grep -q "lint-log-anchors: 1 exception ref(s) and 1 statement citation(s) resolve to LOG.md headings" <<<"$out" && pass "a slug ref and a dated citation both resolve" || fail "both resolve" "rc=$rc" "$out"

# 2: a slug that names no heading fails, naming the file, the ref and the nearest heading
fresh
exception "$SB/triage/accepted-risk/grafana.yaml" "LOG.md#transfer--stdlib-cve-2026-27145-two-bundled-binaries-22"
statement "$SB/triage/vex/CVE-2026-21728.openvex.json" fixed "see triage/LOG.md 2026-08-05."
out=$(run all); rc=$?
[ "$rc" -eq 1 ] && grep -q "::error file=triage/accepted-risk/grafana.yaml::LOG anchor (Req 9.18): CVE-2026-27145 ref 'LOG.md#transfer--stdlib-cve-2026-27145-two-bundled-binaries-22' resolves to no heading in triage/LOG.md" <<<"$out" && pass "an unresolvable ref fails naming the entry and the ref" || fail "unresolvable ref" "rc=$rc" "$out"
grep -q "nearest: LOG.md#transfer--stdlib-cve-2026-27145-two-bundled-plugin-binaries-22" <<<"$out" && pass "and suggests the nearest heading" || fail "nearest" "$out"

# 3: a dated citation with no day heading fails
fresh
exception "$SB/triage/accepted-risk/grafana.yaml" "LOG.md#transfer--stdlib-cve-2026-27145-two-bundled-plugin-binaries-22"
statement "$SB/triage/vex/CVE-2026-21728.openvex.json" fixed "see triage/LOG.md 2026-08-06."
out=$(run all); rc=$?
[ "$rc" -eq 1 ] && grep -q "::error file=triage/vex/CVE-2026-21728.openvex.json::LOG anchor (Req 9.18): statement CVE-2026-21728 (fixed) cites 'triage/LOG.md 2026-08-06', and no heading of that day exists in triage/LOG.md" <<<"$out" && pass "a dated citation without a day heading fails by name" || fail "dated missing" "rc=$rc" "$out"

# 4: a decision without any citation is a decision without a heading: fails
fresh
exception "$SB/triage/accepted-risk/grafana.yaml" "LOG.md#transfer--stdlib-cve-2026-27145-two-bundled-plugin-binaries-22"
statement "$SB/triage/vex/CVE-2026-21728.openvex.json" not_affected "the handler is never routed."
out=$(run all); rc=$?
[ "$rc" -eq 1 ] && grep -q "::error file=triage/vex/CVE-2026-21728.openvex.json::LOG anchor (Req 9.18): statement CVE-2026-21728 (not_affected) cites no triage/LOG.md heading; every decision has one" <<<"$out" && pass "a statement without a citation fails" || fail "no citation" "rc=$rc" "$out"
fresh
exception "$SB/triage/accepted-risk/grafana.yaml" ""
statement "$SB/triage/vex/CVE-2026-21728.openvex.json" fixed "see triage/LOG.md 2026-08-05."
out=$(run all); rc=$?
[ "$rc" -eq 1 ] && grep -q "CVE-2026-27145 ref '' resolves to no heading" <<<"$out" && pass "an empty ref fails" || fail "empty ref" "rc=$rc" "$out"

# 5: the halves run alone: refs (what lint-accepted-risk.sh calls) and statements
fresh
exception "$SB/triage/accepted-risk/grafana.yaml" "LOG.md#transfer--stdlib-cve-2026-27145-two-bundled-plugin-binaries-22"
statement "$SB/triage/vex/CVE-2026-21728.openvex.json" fixed "no citation here"
out=$(run refs); rc=$?
[ "$rc" -eq 0 ] && grep -q "1 exception ref(s)" <<<"$out" && ! grep -q "statement citation" <<<"$out" && pass "refs half alone ignores the statements" || fail "refs half" "rc=$rc" "$out"
out=$(run statements); rc=$?
[ "$rc" -eq 1 ] && grep -q "cites no triage/LOG.md heading" <<<"$out" && pass "statements half alone fails on the missing citation" || fail "statements half" "rc=$rc" "$out"

# 6: the slug rule is GitHub's: backticks, slashes, parentheses and commas dropped, the em dash dropped
#    leaving its two spaces (so a double dash, which is what GitHub's anchor carries), spaces to dashes
fresh
exception "$SB/triage/accepted-risk/grafana.yaml" "LOG.md#fixed--githubcomgrafanatempo-scoped-to-1311-alpine323-23"
statement "$SB/triage/vex/CVE-2026-21728.openvex.json" fixed "see triage/LOG.md 2026-08-05."
out=$(run all); rc=$?
[ "$rc" -eq 0 ] && pass "a heading with backticks, slashes, dots and a hash slugs the GitHub way" || fail "slug rule" "rc=$rc" "$out"

# 7: a slug citation inside a statement's notes resolves too (the same form as a ref)
fresh
exception "$SB/triage/accepted-risk/grafana.yaml" "LOG.md#transfer--stdlib-cve-2026-27145-two-bundled-plugin-binaries-22"
statement "$SB/triage/vex/CVE-2026-21728.openvex.json" fixed "see triage/LOG.md#fixed--githubcomgrafanatempo-scoped-to-1311-alpine323-23"
out=$(run all); rc=$?
[ "$rc" -eq 0 ] && pass "a slug citation in status_notes resolves" || fail "slug in notes" "rc=$rc" "$out"

# 8: no LOG at all is a refusal
fresh; rm "$SB/triage/LOG.md"
exception "$SB/triage/accepted-risk/grafana.yaml" "LOG.md#x"
out=$(run all); rc=$?
[ "$rc" -eq 2 ] && grep -q "no triage/LOG.md" <<<"$out" && pass "a missing LOG refuses" || fail "missing LOG" "rc=$rc" "$out"

echo
if [ "$FAILURES" -eq 0 ]; then echo "all lint-log-anchors tests passed"; else echo "$FAILURES test(s) failed"; exit 1; fi
