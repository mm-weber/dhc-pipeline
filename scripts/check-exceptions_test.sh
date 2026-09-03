#!/usr/bin/env bash
# Tests for scripts/check-exceptions.sh: exception ceilings tiered by the
# finding's severity and KEV status (task 10.1, Req 6.50, 6.51, 6.59, 6.60).
#
# The lint bounds every exception by the LARGEST ceiling from decided_at; this
# script applies the tier the finding actually earns: the KEV ceiling when
# CISA lists it as exploited, else the ceiling for its severity in the scan
# report, else (no finding matched) the largest applicable ceiling. The gate
# runs it per image against the PR build's report; the rescan runs it over
# every unexpired exception against the day's reports, because severity and
# KEV status change after the decision. No KEV set means no evaluation, which
# is a refusal, never a pass.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CE="$HERE/check-exceptions.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

TODAY=$(date -u +%F)
d() { date -u -d "$1" +%F; }   # relative dates: the rules are about durations

fresh() {
  SB=$(mktemp -d)
  mkdir -p "$SB/root/triage/accepted-risk" "$SB/reports"
  cat > "$SB/root/catalogue-policy.yaml" <<'EOF'
triage:
  aperture: [CRITICAL, HIGH]
  ceilings: {CRITICAL: 30d, HIGH: 90d}
  kev_ceiling: 14d
  expiry_warning: 14d
  kev_feed: https://example.invalid/kev.json
EOF
  printf '{"vulnerabilities":[{"cveID":"CVE-2026-0003"}]}\n' > "$SB/kev.json"
}
entry() { # id decided expiry -> one yaml entry
  cat <<YAML
  - id: $1
    purls: ["pkg:golang/x"]
    paths: ["usr/local/bin/app"]
    treatment: accept
    owner: mm-weber
    ref: "triage/LOG.md#x"
    blocked: "no fix"
    statement: "accept: x"
    decided_at: $2
    expired_at: $3
YAML
}
# A Trivy report: uncovered findings under Vulnerabilities, ignorefile-suppressed
# ones under ExperimentalModifiedFindings (where an exception's own finding
# shows up when the exception works).
report() { # file, then "ID:SEV:uncovered|suppressed"...
  local f="$1"; shift
  python3 - "$f" "$@" <<'PY'
import json, sys
vulns, mods = [], []
for spec in sys.argv[2:]:
    cve, sev, where = spec.split(":")
    if where == "uncovered": vulns.append({"VulnerabilityID": cve, "Severity": sev, "PkgName": "x"})
    else: mods.append({"Type": "vulnerability", "Status": "ignored", "Source": "triage/accepted-risk/grafana.yaml",
                       "Finding": {"VulnerabilityID": cve, "Severity": sev, "PkgName": "x"}})
json.dump({"Results": [{"Vulnerabilities": vulns, "ExperimentalModifiedFindings": mods}]}, open(sys.argv[1], "w"))
PY
}
gate()   { "$CE" gate   "$SB/root" grafana "$SB/report.json" "${1:-$SB/kev.json}" 2>&1; }
rescan() { "$CE" rescan "$SB/root" "$SB/reports" "${1:-$SB/kev.json}" 2>&1; }

# 1: a HIGH finding's exception within the HIGH ceiling passes.
fresh
{ echo "vulnerabilities:"; entry CVE-2026-0001 "$TODAY" "$(d '+60 days')"; } > "$SB/root/triage/accepted-risk/grafana.yaml"
report "$SB/report.json" "CVE-2026-0001:HIGH:suppressed"
out=$(gate); rc=$?
[ "$rc" -eq 0 ] && pass "HIGH exception within its ceiling passes" || fail "HIGH exception within its ceiling passes" "$out"
grep -q "CVE-2026-0001" <<<"$out" && grep -qi "ok" <<<"$out" && pass "and is listed with its tier" || fail "and is listed with its tier" "$out"

# 2: the same span is a breach when the report says the finding is CRITICAL
#    (30d): the tier follows the finding, not the entry.
fresh
{ echo "vulnerabilities:"; entry CVE-2026-0002 "$TODAY" "$(d '+60 days')"; } > "$SB/root/triage/accepted-risk/grafana.yaml"
report "$SB/report.json" "CVE-2026-0002:CRITICAL:suppressed"
out=$(gate); rc=$?
[ "$rc" -eq 1 ] && pass "CRITICAL finding tiers the exception at 30 days" || fail "CRITICAL finding tiers the exception at 30 days" "rc=$rc" "$out"
grep -q "CVE-2026-0002" <<<"$out" && grep -q "CRITICAL" <<<"$out" && grep -q "30" <<<"$out" \
  && pass "naming the exception, the tier and the ceiling" || fail "naming the exception, the tier and the ceiling" "$out"

# 3: a KEV-listed finding is tiered at the KEV ceiling whatever its severity.
fresh
{ echo "vulnerabilities:"; entry CVE-2026-0003 "$TODAY" "$(d '+20 days')"; } > "$SB/root/triage/accepted-risk/grafana.yaml"
report "$SB/report.json" "CVE-2026-0003:HIGH:suppressed"
out=$(gate); rc=$?
[ "$rc" -eq 1 ] && grep -qi "KEV" <<<"$out" && grep -q "14" <<<"$out" \
  && pass "a KEV-listed finding is held to the KEV ceiling" || fail "a KEV-listed finding is held to the KEV ceiling" "rc=$rc" "$out"

# 4: an exception matching no finding is tiered by the largest ceiling.
fresh
{ echo "vulnerabilities:"; entry CVE-2026-0009 "$TODAY" "$(d '+60 days')"; } > "$SB/root/triage/accepted-risk/grafana.yaml"
report "$SB/report.json" "CVE-2026-0001:HIGH:uncovered"
out=$(gate); rc=$?
[ "$rc" -eq 0 ] && grep -qi "no finding" <<<"$out" && pass "an unmatched exception passes within the largest ceiling" || fail "an unmatched exception passes within the largest ceiling" "rc=$rc" "$out"
fresh
{ echo "vulnerabilities:"; entry CVE-2026-0009 "$TODAY" "$(d '+100 days')"; } > "$SB/root/triage/accepted-risk/grafana.yaml"
report "$SB/report.json" "CVE-2026-0001:HIGH:uncovered"
out=$(gate); rc=$?
[ "$rc" -eq 1 ] && pass "and breaches beyond it" || fail "and breaches beyond it" "rc=$rc" "$out"

# 5: an uncovered finding (the exception did not suppress) still tiers by
#    the report's severity.
fresh
{ echo "vulnerabilities:"; entry CVE-2026-0004 "$TODAY" "$(d '+60 days')"; } > "$SB/root/triage/accepted-risk/grafana.yaml"
report "$SB/report.json" "CVE-2026-0004:CRITICAL:uncovered"
out=$(gate); rc=$?
[ "$rc" -eq 1 ] && pass "severity is read from uncovered findings too" || fail "severity is read from uncovered findings too" "rc=$rc" "$out"

# 6: no KEV set is no evaluation: refuse, never pass (Req 6.59, 6.60).
fresh
{ echo "vulnerabilities:"; entry CVE-2026-0001 "$TODAY" "$(d '+60 days')"; } > "$SB/root/triage/accepted-risk/grafana.yaml"
report "$SB/report.json" "CVE-2026-0001:HIGH:suppressed"
out=$(gate "$SB/missing.json"); rc=$?
[ "$rc" -eq 2 ] && grep -qi "KEV" <<<"$out" && pass "a missing KEV file refuses with exit 2" || fail "a missing KEV file refuses with exit 2" "rc=$rc" "$out"
echo '{ not json' > "$SB/bad.json"
out=$(gate "$SB/bad.json"); rc=$?
[ "$rc" -eq 2 ] && pass "an unparseable KEV file refuses with exit 2" || fail "an unparseable KEV file refuses with exit 2" "rc=$rc" "$out"

# 7: no accepted-risk file for the image is nothing to tier.
fresh
report "$SB/report.json" "CVE-2026-0001:HIGH:uncovered"
out=$(gate); rc=$?
[ "$rc" -eq 0 ] && pass "no exception file is a clean pass" || fail "no exception file is a clean pass" "rc=$rc" "$out"

# 8: an entry without decided_at cannot be tiered: fail by name (the lint
#    also rejects it, but the gate must not silently pass it).
fresh
{ echo "vulnerabilities:"; entry CVE-2026-0001 "$TODAY" "$(d '+60 days')" | grep -v decided_at; } > "$SB/root/triage/accepted-risk/grafana.yaml"
report "$SB/report.json" "CVE-2026-0001:HIGH:suppressed"
out=$(gate); rc=$?
[ "$rc" -eq 1 ] && grep -q "decided_at" <<<"$out" && pass "no decided_at fails by name" || fail "no decided_at fails by name" "rc=$rc" "$out"

# 9: rescan mode: every unexpired exception across every file against the
#    day's reports for that image (files named <image>__*.json), expired
#    ones skipped, KEV re-evaluated.
fresh
mkdir -p "$SB/root/image/grafana" "$SB/root/image/valkey"
{ echo "vulnerabilities:"
  entry CVE-2026-0001 "$TODAY" "$(d '+60 days')"                        # HIGH, fine
  entry CVE-2026-0005 "$(d '-100 days')" "$(d '-1 day')"                # expired: skipped even though its span breached
} > "$SB/root/triage/accepted-risk/grafana.yaml"
{ echo "vulnerabilities:"; entry CVE-2026-0003 "$TODAY" "$(d '+30 days')"; } > "$SB/root/triage/accepted-risk/valkey.yaml"   # KEV-listed, 30 > 14
report "$SB/reports/grafana__abc123__linux-amd64.json" "CVE-2026-0001:HIGH:suppressed" "CVE-2026-0005:HIGH:uncovered"
report "$SB/reports/valkey__def456__linux-amd64.json" "CVE-2026-0003:HIGH:suppressed"
out=$(rescan); rc=$?
[ "$rc" -eq 1 ] && pass "rescan mode fails on a breach" || fail "rescan mode fails on a breach" "rc=$rc" "$out"
grep -q "CVE-2026-0003" <<<"$out" && grep -q "valkey" <<<"$out" && pass "naming the file and exception" || fail "naming the file and exception" "$out"
grep -q "CVE-2026-0005" <<<"$out" && fail "expired exceptions are outside Req 6.51" "$out" || pass "expired exceptions are outside Req 6.51"
grep -qE "ok grafana CVE-2026-0001" <<<"$out" && pass "and the healthy one is listed ok" || fail "and the healthy one is listed ok" "$out"

# 10: rescan mode with nothing breaching exits 0 and counts.
fresh
{ echo "vulnerabilities:"; entry CVE-2026-0001 "$TODAY" "$(d '+60 days')"; } > "$SB/root/triage/accepted-risk/grafana.yaml"
report "$SB/reports/grafana__abc123__linux-amd64.json" "CVE-2026-0001:HIGH:suppressed"
out=$(rescan); rc=$?
[ "$rc" -eq 0 ] && grep -q "1 exception" <<<"$out" && pass "rescan mode passes and counts" || fail "rescan mode passes and counts" "rc=$rc" "$out"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all check-exceptions tests passed"
