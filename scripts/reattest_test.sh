#!/usr/bin/env bash
# Tests for scripts/reattest.sh: the rescan's re-attestation, replacing
# (task 10.3; Req 6.42, 6.43, 6.55, 6.58; ADR 0004).
#
# cosign, trivy, crane, vexctl and curl are stubbed; the compiler is real. What
# the suite pins is the contract: every report attested with --replace before
# compiling; the previous document read only through verify-attestation against
# the policy's role identities; nothing written when the statement set is
# unchanged and every count is one; --replace on the digest AND every platform
# manifest when it differs or a count is wrong; several previous documents
# merged with vexctl; a digest with a missing report skipped whole; --dry-run
# writes nothing; a failed write fails the run; and the record that makes the
# first real run a measurement.
# shellcheck disable=SC2015  # `test && pass || fail`: pass never fails, so the idiom is exact here
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REATTEST="$HERE/reattest.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }
INDEX="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
M1="sha256:a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"
BUILD_ID="https://github.com/acme/dhc/.github/workflows/build.yml@refs/heads/main"
RESCAN_ID="https://github.com/acme/dhc/.github/workflows/rescan.yml@refs/heads/main"

att() { # <digest> <openvex layers> [<logIndex>...] -> the stub's .att manifest
  local d="$1" n="$2"; shift 2
  local idxs
  idxs=$(printf '%s\n' "$@" | jq -R 'select(. != "") | tonumber' | jq -s -c .)
  jq -n --argjson n "$n" --argjson idxs "$idxs" '
    {schemaVersion: 2,
     layers: ([{annotations: {predicateType: "https://spdx.dev/Document"}}]
              + [range($n) as $i
                 | {annotations: ({predicateType: "https://openvex.dev/ns"}
                                  + (if $idxs[$i] then {"dev.sigstore.cosign/bundle": ({Payload: {logIndex: $idxs[$i]}} | tojson)} else {} end))}])}'     > "$SB/att-${d#sha256:}.json"
}
envelope() { # <identity: build|rescan> <document.json> -> one DSSE-shaped line the cosign stub returns
  local who="$1" doc="$2"
  jq -c --slurpfile d "$doc" '{predicateType:"https://openvex.dev/ns", predicate:$d[0]}' -n \
    | { read -r stmt; printf '{"payloadType":"application/vnd.in-toto+json","payload":"%s","signatures":[]}\n' "$(printf '%s' "$stmt" | base64 -w0)"; } \
    >> "$SB/verify-${who}.jsonl"
}
report() { # writes today's report for the one manifest: one uncovered finding
  mkdir -p "$SB/out/trivy"
  cat > "$SB/out/trivy/grafana__${INDEX:7:12}__linux-amd64.json" <<JSON
{"SchemaVersion":2,"CreatedAt":"2026-09-03T06:00:00Z","ArtifactName":"ghcr.io/acme/dhc/grafana",
 "Results":[{"Target":"usr/share/grafana/bin/grafana","Class":"lang-pkgs","Type":"gobinary","Vulnerabilities":[
   {"VulnerabilityID":"CVE-2026-43871","PkgName":"github.com/apache/thrift","Severity":"HIGH",
    "PkgIdentifier":{"PURL":"pkg:golang/github.com/apache/thrift@v0.23.1"}}]}]}
JSON
}
fresh() {
  SB=$(mktemp -d); mkdir -p "$SB/bin" "$SB/root/image/grafana" "$SB/root/triage/vex" "$SB/out"
  cat > "$SB/root/catalogue-policy.yaml" <<EOF2
verification:
  registry: ghcr.io/acme/dhc
  issuer: https://token.actions.githubusercontent.com
  roles:
    releaser:
      identity: $BUILD_ID
      attests: [spdxjson, cyclonedx, vuln, openvex]
    re-attester:
      identity: $RESCAN_ID
      attests: [openvex, vuln]
EOF2
  printf 'name: Grafana 13.1.x\nimage: ghcr.io/acme/dhc/grafana\ntags:\n  - 13-alpine3.23\n  - 13.1.5-alpine3.23\n' > "$SB/root/image/grafana/image.yaml"
  printf 'ghcr.io/acme/dhc/grafana\t13.1.5-alpine3.23\t%s\tlinux/amd64\t%s\tsupported\n' "$INDEX" "$M1" > "$SB/enum.tsv"
  cat > "$SB/bin/cosign" <<'STUB'
#!/usr/bin/env bash
printf 'cosign %s\n' "$*" >> "${STUB_ARGV}"
case "$1" in
  verify-attestation)
    for a in "$@"; do case "$a" in *build.yml*) f="${STUB_DIR}/verify-build.jsonl";; *rescan.yml*) f="${STUB_DIR}/verify-rescan.jsonl";; esac; done
    [ -f "${f:-}" ] && cat "$f" && exit 0
    echo "no matching attestations" >&2; exit 1 ;;
  attest)
    [ -n "${STUB_FAIL_ATTEST:-}" ] && { echo "stub: refused" >&2; exit 1; }
    # A budget of attempts that fail the way Rekor did on 2026-09-04, then succeed.
    if [ -s "${STUB_DIR}/attest-fail-budget" ] && [ "$(cat "${STUB_DIR}/attest-fail-budget")" -gt 0 ]; then
      echo $(( $(cat "${STUB_DIR}/attest-fail-budget") - 1 )) > "${STUB_DIR}/attest-fail-budget"
      echo "Signature already exists. Fetching and verifying inclusion proof." >&2
      echo "Error: signing ${@: -1}: [GET /api/v1/log/entries/{entryUUID}][404] getLogEntryByUuidNotFound" >&2
      exit 1
    fi
    exit 0 ;;
esac
exit 2
STUB
  cat > "$SB/bin/trivy" <<'STUB'
#!/usr/bin/env bash
printf 'trivy %s\n' "$*" >> "${STUB_ARGV}"
out=""; while [ $# -gt 0 ]; do case "$1" in --output) out="$2"; shift;; esac; last="$1"; shift; done
cp "$last" "$out"
STUB
  cat > "$SB/bin/crane" <<'STUB'
#!/usr/bin/env bash
printf 'crane %s\n' "$*" >> "${STUB_ARGV}"
ref="$2"; hex="${ref##*sha256-}"; hex="${hex%.att}"
f="${STUB_DIR}/att-${hex}.json"; [ -f "$f" ] || { echo MANIFEST_UNKNOWN >&2; exit 1; }
cat "$f"
STUB
  cat > "$SB/bin/vexctl" <<'STUB'
#!/usr/bin/env bash
printf 'vexctl %s\n' "$*" >> "${STUB_ARGV}"
shift; jq -s '{"@context":"https://openvex.dev/ns/v0.2.0","@id":"merged","author":"stub","version":1,"timestamp":"2026-01-01T00:00:00Z",statements:(map(.statements[]))}' "$@"
STUB
  cat > "$SB/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "${STUB_ARGV}"
exit 0
STUB
  chmod +x "$SB"/bin/*
  export STUB_ARGV="$SB/argv" STUB_DIR="$SB"; : > "$STUB_ARGV"
  report
  att "$INDEX" 1 4242; att "$M1" 1 4243
}
run() { PATH="$SB/bin:$PATH" "$REATTEST" "$SB/root" "$SB/enum.tsv" "$SB/out" "$@" 2>&1; }
rec() { jq -r "$1" "$SB/out/reattest.jsonl"; }
calls() { grep -c "$1" "$STUB_ARGV" || true; }
compiled_doc() { local f; for f in "$SB"/out/reattest/grafana__*/out/*.openvex.json; do echo "$f"; return; done; }

# 1: no previously attested document: the report is attested with --replace
#    first, and the document is then attested to the digest AND the manifest
fresh
out=$(run); rc=$?
[ "$rc" -eq 0 ] && pass "a clean first run exits 0" || fail "rc=$rc" "$out"
[ "$(calls 'cosign attest --yes --type vuln --replace')" -eq 1 ] && pass "today's report is attested with --replace (Req 6.42)" || fail "vuln attest calls" "$(cat "$STUB_ARGV")"
grep -q "type vuln --replace --predicate .* ghcr.io/acme/dhc/grafana@${M1}" "$STUB_ARGV" && pass "to the platform manifest" || fail "vuln target" "$(cat "$STUB_ARGV")"
grep -q "cosign verify-attestation --type openvex --certificate-oidc-issuer https://token.actions.githubusercontent.com --certificate-identity ${BUILD_ID}" "$STUB_ARGV" && pass "the previous document is read through verification, releaser identity" || fail "verify releaser" "$(cat "$STUB_ARGV")"
grep -q "certificate-identity ${RESCAN_ID}" "$STUB_ARGV" && pass "and re-attester identity (Req 6.58)" || fail "verify re-attester" "$(cat "$STUB_ARGV")"
[ "$(calls "type openvex --replace --predicate .* ghcr.io/acme/dhc/grafana@${INDEX}")" -eq 1 ] && pass "the document is attested to the digest with --replace" || fail "index attest" "$(cat "$STUB_ARGV")"
[ "$(calls "type openvex --replace --predicate .* ghcr.io/acme/dhc/grafana@${M1}")" -eq 1 ] && pass "and to the platform manifest (Req 6.43)" || fail "manifest attest" "$(cat "$STUB_ARGV")"
[ "$(rec '.reattested')" = "true" ] && [ "$(rec '.previous_documents')" = "0" ] && pass "the record says why: no previous document" || fail "record" "$(cat "$SB/out/reattest.jsonl")"
[ "$(rec '.compiled.under_investigation')" = "1" ] && pass "and what was compiled (one uncovered finding)" || fail "compiled counts" "$(cat "$SB/out/reattest.jsonl")"
grep -q 'rekor.sigstore.dev/api/v1/log/entries?logIndex=4242' "$STUB_ARGV" && pass "the replaced entry's Rekor index is looked up (the measurement)" || fail "rekor lookup" "$(cat "$STUB_ARGV")"
[ "$(rec '.rekor_retained[0].retained')" = "true" ] && pass "and its retention recorded" || fail "retention" "$(cat "$SB/out/reattest.jsonl")"
FIRST=$(mktemp); cp "$(compiled_doc)" "$FIRST"   # survives the next fresh sandbox

# 2: unchanged: the previously attested document has the same statement set
#    and every count is one, so the report is re-attested and nothing else is
fresh; envelope build "$FIRST"
out=$(run); rc=$?
[ "$rc" -eq 0 ] && pass "unchanged run exits 0" || fail "rc=$rc" "$out"
[ "$(calls 'type vuln --replace')" -eq 1 ] && pass "the report is still attested daily" || fail "vuln attest" "$(cat "$STUB_ARGV")"
[ "$(calls 'type openvex --replace')" -eq 0 ] && pass "no OpenVEX write when the statement set is unchanged" || fail "unexpected openvex attest" "$(cat "$STUB_ARGV")"
[ "$(rec '.differs')" = "false" ] && [ "$(rec '.reattested')" = "false" ] && [ "$(rec '.previous_documents')" = "1" ] && pass "recorded as unchanged with one previous document" || fail "record" "$(cat "$SB/out/reattest.jsonl")"
[ "$(calls 'curl')" -eq 0 ] && pass "no Rekor lookup when nothing was replaced" || fail "curl called" "$(cat "$STUB_ARGV")"

# 3: differs: the attested document carries a statement today's compile does
#    not (a decision retired), so the digest and manifest are replaced
fresh; jq '.statements += [{"vulnerability":{"name":"CVE-2026-00009"},"products":[{"@id":"pkg:oci/grafana@'"$INDEX"'"}],"status":"under_investigation","timestamp":"2026-08-01T00:00:00Z"}]' "$FIRST" > "$SB/prev.json"; envelope build "$SB/prev.json"
out=$(run); rc=$?
[ "$(rec '.differs')" = "true" ] && [ "$(rec '.reattested')" = "true" ] && pass "a different statement set is re-attested" || fail "record" "$(cat "$SB/out/reattest.jsonl")"
[ "$(calls 'type openvex --replace')" -eq 2 ] && pass "on the digest and the one manifest" || fail "openvex attest count" "$(cat "$STUB_ARGV")"

# 4: a document-level difference alone (id, timestamp, version) is not a
#    difference: those are compile artefacts, not content
fresh; jq '.["@id"] = "https://openvex.dev/docs/other" | .timestamp = "2026-01-01T00:00:00Z" | .version = 7' "$FIRST" > "$SB/prev.json"; envelope rescan "$SB/prev.json"
out=$(run); rc=$?
[ "$(rec '.differs')" = "false" ] && [ "$(calls 'type openvex --replace')" -eq 0 ] && pass "document id, timestamp and version are ignored by the differs test" || fail "canonicalisation" "$(cat "$SB/out/reattest.jsonl")"

# 5: wrong count: two OpenVEX attestations on the digest, both verifying; the
#    carry-forward input is their vexctl merge, and the count is repaired even
#    though the merged set equals today's
fresh; att "$INDEX" 2 5001 5002; envelope build "$FIRST"; envelope rescan "$FIRST"
out=$(run); rc=$?
[ "$(calls 'vexctl merge')" -eq 1 ] && pass "several previous documents are merged with vexctl" || fail "vexctl" "$(cat "$STUB_ARGV")"
[ "$(rec '.previous_documents')" = "2" ] && [ "$(rec '.wrong_count')" = "true" ] && [ "$(rec '.reattested')" = "true" ] && pass "and the count is repaired by a replace (Req 6.43, 6.44)" || fail "record" "$(cat "$SB/out/reattest.jsonl")"
[ "$(rec '.openvex_before.index.openvex')" = "2" ] && pass "the record keeps the before-state (two layers)" || fail "before" "$(cat "$SB/out/reattest.jsonl")"
[ "$(calls 'logIndex=5001')" -eq 1 ] && [ "$(calls 'logIndex=5002')" -eq 1 ] && pass "both replaced entries are looked up in Rekor" || fail "rekor" "$(cat "$STUB_ARGV")"

# 6: a manifest without today's report: the digest is skipped whole, named,
#    and nothing is written for it
fresh; rm "$SB"/out/trivy/*.json
out=$(run); rc=$?
[ "$rc" -eq 0 ] && pass "a skipped digest is not a failed run" || fail "rc=$rc" "$out"
grep -q 'skipped' <<<"$out" && grep -q "$INDEX" <<<"$out" && pass "the skip names the digest" || fail "naming" "$out"
[ "$(calls 'cosign attest')" -eq 0 ] && pass "and nothing was attested for it" || fail "attested" "$(cat "$STUB_ARGV")"
[ "$(rec '.skipped')" != "null" ] && pass "and the record says so" || fail "record" "$(cat "$SB/out/reattest.jsonl")"

# 7: --dry-run decides everything and writes nothing
fresh
out=$(run --dry-run); rc=$?
[ "$(calls 'cosign attest')" -eq 0 ] && pass "--dry-run makes no cosign attest call" || fail "attest in dry-run" "$(cat "$STUB_ARGV")"
grep -q 'would run: cosign attest --yes --type openvex --replace' <<<"$out" && pass "and says what it would have run" || fail "dry-run output" "$out"
[ "$(rec '.dry_run')" = "true" ] && pass "and records the dry run" || fail "record" "$(cat "$SB/out/reattest.jsonl")"

# 8: a refused write fails the run, by name, after a bounded number of attempts
fresh
out=$(REATTEST_RETRY_DELAY=0 STUB_FAIL_ATTEST=1 run); rc=$?
[ "$rc" -eq 1 ] && pass "a refused attestation fails the run" || fail "rc=$rc" "$out"
grep -q "::error::reattest: cosign attest --type vuln --replace failed for ghcr.io/acme/dhc/grafana@${M1}" <<<"$out" && pass "naming the target" || fail "naming" "$out"
[ "$(calls 'type vuln --replace')" -eq 3 ] && pass "after three attempts, not one and not forever" || fail "attempts" "$(cat "$STUB_ARGV")"
grep -q "(attempt 2 of 3)" <<<"$out" && pass "each failed attempt named on the way" || fail "attempt warnings" "$out"
[ "$(rec '.failed')" = "scan report attestation" ] && [ "$(rec '.retries')" = "2" ] && pass "and the record counts the retries" || fail "record" "$(cat "$SB/out/reattest.jsonl")"

# 9: the open-issue map reaches the compiler, so the statement names its issue
fresh; printf '{"CVE-2026-43871":"https://github.com/acme/dhc/issues/9"}\n' > "$SB/issues.json"
out=$(REATTEST_ISSUES="$SB/issues.json" run); rc=$?
grep -q 'issues/9' "$(compiled_doc)" && pass "the compiled statement carries the open issue link" || fail "issue link" "$(cat "$(compiled_doc)")"

# 10: a Sigstore blip is retried, not failed. Measured 2026-09-04 (run
#     33854524508): Rekor answered "already exists" to an upload cosign's client
#     had retried, then 404 for the entry by UUID from a lagging replica, and
#     one of ninety writes failed the day. A new attempt signs with fresh keys
#     and lands a new entry, so one failed attempt is named and tried again.
fresh; echo 1 > "$SB/attest-fail-budget"
out=$(REATTEST_RETRY_DELAY=0 run); rc=$?
[ "$rc" -eq 0 ] && pass "one failed attempt does not fail the run" || fail "rc=$rc" "$out"
[ "$(calls 'type vuln --replace')" -eq 2 ] && pass "the write was attempted again" || fail "attempts" "$(cat "$STUB_ARGV")"
grep -q "::warning::reattest: cosign attest --type vuln --replace failed for ghcr.io/acme/dhc/grafana@${M1} (attempt 1 of 3)" <<<"$out" && pass "and the failed attempt is named" || fail "warning" "$out"
[ "$(rec '.retries')" = "1" ] && [ "$(rec '.reattested')" = "true" ] && pass "counted in the record, which is otherwise a normal one" || fail "record" "$(cat "$SB/out/reattest.jsonl")"
grep -q '0 failed, 1 retried' <<<"$out" && pass "and in the summary line" || fail "summary" "$out"

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES test(s) failed"; exit 1; fi
echo "all reattest tests passed"
