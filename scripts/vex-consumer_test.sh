#!/usr/bin/env bash
# Tests for scripts/vex-consumer.sh: the adapter contract behind the declared
# VEX consumers (task 13.4, Req 9.11). Every consumer emits one normalised
# shape, one JSON object per line: consumer, vulnerability, purl, key (the
# canonical join key), suppressed (bool) and by (vex | exception | ignore |
# none). trivy and grype are stubbed with the JSON shapes measured on
# 2026-09-08 (trivy 0.74.0 --show-suppressed; grype 0.118.0 -o json with
# ignoredMatches and vex-status rules).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
VC="$HERE/vex-consumer.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

SB=$(mktemp -d)
mkdir -p "$SB/bin" "$SB/vex" "$SB/root"
cp "$ROOT/catalogue-policy.yaml" "$SB/root/"
echo '{"@context":"https://openvex.dev/ns/v0.2.0","statements":[]}' > "$SB/vex/doc.openvex.json"

# A trivy report the way scan-image.sh writes one: reported findings, one
# suppressed by a VEX statement, one by the accepted-risk ignorefile.
cat > "$SB/trivy.json" <<'EOF'
{"Results":[{"Target":"grafana","Vulnerabilities":[
  {"VulnerabilityID":"CVE-2026-1001","PkgName":"github.com/apache/thrift","InstalledVersion":"v0.23.1","Severity":"HIGH","PkgIdentifier":{"PURL":"pkg:golang/github.com/apache/thrift@v0.23.1"}},
  {"VulnerabilityID":"CVE-2026-1002","PkgName":"stdlib","InstalledVersion":"v1.26.4","Severity":"CRITICAL","PkgIdentifier":{"PURL":"pkg:golang/stdlib@v1.26.4"}}],
 "ExperimentalModifiedFindings":[
  {"Type":"vulnerability","Status":"not_affected","Source":"/tmp/vex/grafana.openvex.json","Finding":{"VulnerabilityID":"CVE-2026-2001","PkgName":"github.com/grafana/tempo","InstalledVersion":"v1.5.1","Severity":"HIGH","PkgIdentifier":{"PURL":"pkg:golang/github.com/grafana/tempo@v1.5.1"}}},
  {"Type":"vulnerability","Status":"fixed","Source":"/tmp/vex/grafana.openvex.json","Finding":{"VulnerabilityID":"CVE-2026-2002","PkgName":"libssl3","InstalledVersion":"3.5.7-r1","Severity":"HIGH","PkgIdentifier":{"PURL":"pkg:apk/alpine/libssl3@3.5.7-r1?arch=x86_64&distro=3.23.1"}}},
  {"Type":"vulnerability","Status":"ignored","Source":"triage/accepted-risk/grafana.yaml","Finding":{"VulnerabilityID":"CVE-2026-3001","PkgName":"github.com/apache/thrift","InstalledVersion":"v0.23.1","Severity":"HIGH","PkgIdentifier":{"PURL":"pkg:golang/github.com/apache/thrift@v0.23.1"}}},
  {"Type":"misconfiguration","Status":"ignored","Source":"x","Finding":{"VulnerabilityID":"","PkgIdentifier":{}}}]}]}
EOF
# A grype document: one reported, one suppressed by a VEX rule, one by a
# grype ignore rule, one below the aperture (Medium) that must not appear.
cat > "$SB/grype.json" <<'EOF'
{"matches":[
  {"vulnerability":{"id":"CVE-2026-1001","severity":"High"},"artifact":{"name":"github.com/apache/thrift","version":"v0.23.1","purl":"pkg:golang/github.com/apache/thrift@v0.23.1"}},
  {"vulnerability":{"id":"CVE-2026-1002","severity":"Critical"},"artifact":{"name":"stdlib","version":"1.26.4","purl":"pkg:golang/stdlib@1.26.4"}},
  {"vulnerability":{"id":"CVE-2026-9999","severity":"Medium"},"artifact":{"name":"stdlib","version":"1.26.4","purl":"pkg:golang/stdlib@1.26.4"}}],
 "ignoredMatches":[
  {"match":{"vulnerability":{"id":"CVE-2026-2001","severity":"High"},"artifact":{"name":"github.com/grafana/tempo","version":"v1.5.1","purl":"pkg:golang/github.com/grafana/tempo@v1.5.1"}},"appliedIgnoreRules":[{"vulnerability":"CVE-2026-2001","namespace":"","vex-status":"not_affected","vex-justification":"vulnerable_code_not_in_execute_path"}]},
  {"match":{"vulnerability":{"id":"CVE-2026-2002","severity":"High"},"artifact":{"name":"libssl3","version":"3.5.7-r1","purl":"pkg:apk/alpine/libssl3@3.5.7-r1?arch=x86_64&distro=alpine-3.23"}},"appliedIgnoreRules":[{"vulnerability":"CVE-2026-2002","namespace":"","vex-status":"fixed"}]},
  {"match":{"vulnerability":{"id":"CVE-2026-4001","severity":"High"},"artifact":{"name":"foo","version":"1","purl":"pkg:golang/foo@1"}},"appliedIgnoreRules":[{"vulnerability":"CVE-2026-4001","namespace":"","reason":"grype.yaml ignore"}]}],
 "source":{"type":"image"},"descriptor":{"name":"grype","version":"0.118.0"}}
EOF
cat > "$SB/bin/trivy" <<'STUB'
#!/usr/bin/env bash
printf 'trivy %s\n' "$*" >> "${STUB_ARGV}"
out=""; while [ $# -gt 0 ]; do case "$1" in --output) out="$2"; shift 2 ;; *) shift ;; esac; done
[ -n "$out" ] && cp "${STUB_TRIVY_JSON}" "$out"
exit "${STUB_TRIVY_RC:-0}"
STUB
cat > "$SB/bin/grype" <<'STUB'
#!/usr/bin/env bash
printf 'grype %s\n' "$*" >> "${STUB_ARGV}"
[ "${STUB_GRYPE_RC:-0}" -ne 0 ] && { echo "grype stub failure" >&2; exit "${STUB_GRYPE_RC}"; }
cat "${STUB_GRYPE_JSON}"
STUB
chmod +x "$SB/bin/trivy" "$SB/bin/grype"
export STUB_ARGV="$SB/argv" STUB_TRIVY_JSON="$SB/trivy.json" STUB_GRYPE_JSON="$SB/grype.json"
run() { : > "$STUB_ARGV"; PATH="$SB/bin:$PATH" "$VC" "$@" 2>&1; }
field() { jq -r --arg v "$2" --arg f "$3" 'select(.vulnerability == $v) | .[$f]' "$1"; }

# 1: trivy from a report: reported, suppressed by vex, suppressed by exception; no misconfigurations
out=$(run trivy "$SB/out-trivy.jsonl" --root "$SB/root" --report "$SB/trivy.json"); rc=$?
[ "$rc" -eq 0 ] && pass "trivy --report: exit 0" || fail "trivy --report" "rc=$rc" "$out"
[ "$(wc -l < "$SB/out-trivy.jsonl")" -eq 5 ] && pass "trivy --report: five findings, the misconfiguration dropped" || fail "trivy --report count" "$(cat "$SB/out-trivy.jsonl")"
[ "$(field "$SB/out-trivy.jsonl" CVE-2026-1001 suppressed)" = "false" ] && pass "reported finding: suppressed false" || fail "reported" "$(cat "$SB/out-trivy.jsonl")"
[ "$(field "$SB/out-trivy.jsonl" CVE-2026-2001 suppressed)" = "true" ] && [ "$(field "$SB/out-trivy.jsonl" CVE-2026-2001 by)" = "vex" ] && pass "VEX-suppressed finding: suppressed true, by vex" || fail "vex suppressed" "$(cat "$SB/out-trivy.jsonl")"
[ "$(field "$SB/out-trivy.jsonl" CVE-2026-3001 by)" = "exception" ] && pass "ignorefile-suppressed finding: by exception" || fail "exception" "$(cat "$SB/out-trivy.jsonl")"
[ "$(field "$SB/out-trivy.jsonl" CVE-2026-2001 status)" = "not_affected" ] && pass "the statement's status travels" || fail "status" "$(cat "$SB/out-trivy.jsonl")"
jq -e 'select(.consumer != "trivy")' "$SB/out-trivy.jsonl" | grep -q . && fail "consumer field" "$(cat "$SB/out-trivy.jsonl")" || pass "every line names the consumer"
[ ! -s "$STUB_ARGV" ] && pass "trivy --report: no scan was run" || fail "trivy --report ran a scan" "$(cat "$STUB_ARGV")"

# 2: the canonical key: qualifiers dropped, a leading v on the version dropped, so
#    trivy's stdlib@v1.26.4 and grype's stdlib@1.26.4 meet
[ "$(field "$SB/out-trivy.jsonl" CVE-2026-1002 key)" = "pkg:golang/stdlib@1.26.4" ] && pass "key: leading v dropped from the version" || fail "key v" "$(field "$SB/out-trivy.jsonl" CVE-2026-1002 key)"
[ "$(field "$SB/out-trivy.jsonl" CVE-2026-2002 key)" = "pkg:apk/alpine/libssl3@3.5.7-r1" ] && pass "key: qualifiers dropped" || fail "key qualifiers" "$(field "$SB/out-trivy.jsonl" CVE-2026-2002 key)"
[ "$(field "$SB/out-trivy.jsonl" CVE-2026-2002 purl)" = "pkg:apk/alpine/libssl3@3.5.7-r1?arch=x86_64&distro=3.23.1" ] && pass "purl: the scanner's own spelling is kept beside the key" || fail "purl kept" "$(field "$SB/out-trivy.jsonl" CVE-2026-2002 purl)"

# 3: grype from a scan: aperture applied, vex rules read, grype's own ignores told apart
out=$(run grype "$SB/out-grype.jsonl" --root "$SB/root" --scan "registry.example/acme/grafana@sha256:aaaa" --vex-dir "$SB/vex" --remote); rc=$?
[ "$rc" -eq 0 ] && pass "grype --scan: exit 0" || fail "grype --scan" "rc=$rc" "$out"
grep -q -- "grype registry:registry.example/acme/grafana@sha256:aaaa --vex $SB/vex/doc.openvex.json -o json" "$STUB_ARGV" && pass "grype invoked with the registry source, every compiled document and JSON output" || fail "grype argv" "$(cat "$STUB_ARGV")"
[ "$(wc -l < "$SB/out-grype.jsonl")" -eq 5 ] && pass "grype: five findings in the aperture, the Medium dropped" || fail "grype count" "$(cat "$SB/out-grype.jsonl")"
[ "$(field "$SB/out-grype.jsonl" CVE-2026-2001 suppressed)" = "true" ] && [ "$(field "$SB/out-grype.jsonl" CVE-2026-2001 by)" = "vex" ] && [ "$(field "$SB/out-grype.jsonl" CVE-2026-2001 status)" = "not_affected" ] && pass "grype: a vex-status rule is a VEX suppression with its status" || fail "grype vex" "$(cat "$SB/out-grype.jsonl")"
[ "$(field "$SB/out-grype.jsonl" CVE-2026-4001 by)" = "ignore" ] && pass "grype: its own ignore rule is by ignore, not vex" || fail "grype ignore" "$(cat "$SB/out-grype.jsonl")"
[ "$(field "$SB/out-grype.jsonl" CVE-2026-1002 key)" = "pkg:golang/stdlib@1.26.4" ] && pass "grype: the same key as trivy for stdlib" || fail "grype key" "$(field "$SB/out-grype.jsonl" CVE-2026-1002 key)"
[ "$(field "$SB/out-grype.jsonl" CVE-2026-2002 key)" = "pkg:apk/alpine/libssl3@3.5.7-r1" ] && pass "grype: the same key as trivy for the apk package" || fail "grype apk key" "$(field "$SB/out-grype.jsonl" CVE-2026-2002 key)"

# 4: trivy from a scan runs the same shape scan-image.sh runs, VEX only (no ignorefile: the
#    block compares statements, and exceptions are ours alone), --show-suppressed, aperture
out=$(run trivy "$SB/out-trivy2.jsonl" --root "$SB/root" --scan "registry.example/acme/grafana@sha256:aaaa" --vex-dir "$SB/vex" --remote); rc=$?
[ "$rc" -eq 0 ] && pass "trivy --scan: exit 0" || fail "trivy --scan" "rc=$rc" "$out"
argv=$(cat "$STUB_ARGV")
grep -q -- "--vex $SB/vex/doc.openvex.json" <<<"$argv" && grep -q -- "--show-suppressed" <<<"$argv" && grep -q -- "--severity CRITICAL,HIGH" <<<"$argv" && grep -q -- "--image-src remote" <<<"$argv" && ! grep -q -- "--ignorefile" <<<"$argv" \
  && pass "trivy --scan: --vex, --show-suppressed, the aperture, remote, no ignorefile" || fail "trivy argv" "$argv"
# 4b: --vex oci instead of files, the regression check's other reading (ADR 0004)
out=$(run trivy "$SB/out-trivy3.jsonl" --root "$SB/root" --scan "registry.example/acme/grafana@sha256:aaaa" --vex-oci --remote); rc=$?
grep -q -- "--vex oci" "$STUB_ARGV" && ! grep -q -- "--vex $SB" "$STUB_ARGV" && pass "trivy --vex-oci: reads the attestation instead of files" || fail "vex oci argv" "$(cat "$STUB_ARGV")"

# 5: a consumer that fails is a refusal naming it, no half record
export STUB_GRYPE_RC=3
out=$(run grype "$SB/out-grype2.jsonl" --root "$SB/root" --scan "registry.example/acme/grafana@sha256:aaaa" --vex-dir "$SB/vex"); rc=$?
unset STUB_GRYPE_RC
[ "$rc" -eq 1 ] && grep -q "grype exited 3" <<<"$out" && [ ! -e "$SB/out-grype2.jsonl" ] && pass "a failing consumer refuses by name and writes nothing" || fail "failing consumer" "rc=$rc" "$out"

# 6: an undeclared consumer is refused: the list in the policy file is the contract
out=$(run scout "$SB/out-scout.jsonl" --root "$SB/root" --scan x --vex-dir "$SB/vex"); rc=$?
[ "$rc" -eq 2 ] && grep -q "scout is not a declared consumer" <<<"$out" && pass "an undeclared consumer is refused" || fail "undeclared consumer" "rc=$rc" "$out"

# 7: output is sorted and stable
run trivy "$SB/o1.jsonl" --root "$SB/root" --report "$SB/trivy.json" >/dev/null; run trivy "$SB/o2.jsonl" --root "$SB/root" --report "$SB/trivy.json" >/dev/null
cmp -s "$SB/o1.jsonl" "$SB/o2.jsonl" && [ "$(jq -r '.vulnerability' "$SB/o1.jsonl" | head -1)" = "CVE-2026-1001" ] && pass "output sorted by vulnerability then key, stable" || fail "sorted" "$(cat "$SB/o1.jsonl")"

echo
if [ "$FAILURES" -eq 0 ]; then echo "all vex-consumer tests passed"; else echo "$FAILURES test(s) failed"; exit 1; fi
