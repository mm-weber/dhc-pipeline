#!/usr/bin/env bash
# Tests for scripts/consumer-smoke.sh: the daily consumer smoke test (task
# 13.4, Req 9.13). The recipe README.md publishes between the
# render-verification markers is extracted and run VERBATIM against one
# published digest, every step's exit code checked; then the authoritative
# consumer's suppressions are asserted from the same extracted document: a
# not_affected or fixed statement whose finding the authoritative consumer
# still REPORTS is a missing suppression and fails the run; the other
# consumers go into the portability block. ADR 0004's regression check rides
# along: trivy reading `--vex oci` must suppress what the extracted document
# suppresses, or the authoritative consumer is missing suppressions for
# anyone who follows that reading. cosign, jq, trivy, grype and docker are
# stubbed; the recipe text is the real renderer's shape.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SMOKE="$HERE/consumer-smoke.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

SB=$(mktemp -d); mkdir -p "$SB/bin" "$SB/root/scripts"
cp "$ROOT/catalogue-policy.yaml" "$SB/root/"
cp "$HERE/triage-policy.sh" "$HERE/vex-consumer.sh" "$HERE/vex-portability.sh" "$SB/root/scripts/"
# The README with the rendered recipe, the real shape
cat > "$SB/root/README.md" <<'EOF'
# demo

<!-- render-verification:begin -->
```sh
# rendered by scripts/render-verification.sh from catalogue-policy.yaml; do not edit
REF=ghcr.io/acme/dhc/IMAGE:TAG        # any catalogue tag, e.g. grafana:13.1.3-alpine3.23
ISSUER='--certificate-oidc-issuer https://token.actions.githubusercontent.com'
BUILD='--certificate-identity https://github.com/acme/dhc/.github/workflows/build.yml@refs/heads/main'
RESCAN='--certificate-identity https://github.com/acme/dhc/.github/workflows/rescan.yml@refs/heads/main'

cosign verify $ISSUER $BUILD "$REF"                          # signature: the release workflow on main
cosign verify-attestation $ISSUER $BUILD --type spdxjson "$REF" \
  | jq -r '.payload | @base64d | fromjson | .predicate'      # SBOM
{ cosign verify-attestation $ISSUER $BUILD --type openvex "$REF" 2>/dev/null \
  || cosign verify-attestation $ISSUER $RESCAN --type openvex "$REF"; } \
  | jq -r '.payload | @base64d | fromjson | .predicate' > openvex.json   # VEX: releaser or re-attester
trivy image --vex openvex.json --show-suppressed --severity CRITICAL,HIGH "$REF"   # authoritative consumer
grype "$REF" --vex openvex.json                                                    # declared consumer, informational
# BuildKit provenance is attached at build time and is not verified by the
# policy above (Req 2.25); inspect it with the buildx CLI plugin:
docker buildx imagetools inspect "$REF" --format '{{ json .Provenance }}'
```
<!-- render-verification:end -->
EOF
# The attested OpenVEX document the stubbed cosign returns: two statements
VEXDOC='{"@context":"https://openvex.dev/ns/v0.2.0","@id":"x","statements":[
 {"vulnerability":{"name":"CVE-2026-2001"},"status":"not_affected","products":[{"@id":"pkg:oci/grafana@sha256:aaaa","subcomponents":[{"@id":"pkg:golang/github.com/grafana/tempo@v1.5.1"}]}]},
 {"vulnerability":{"name":"CVE-2026-2002"},"status":"fixed","products":[{"@id":"pkg:oci/grafana@sha256:aaaa","subcomponents":[{"@id":"pkg:apk/alpine/libssl3@3.5.7-r1"}]}]},
 {"vulnerability":{"name":"CVE-2026-5001"},"status":"affected","products":[{"@id":"pkg:oci/grafana@sha256:aaaa","subcomponents":[{"@id":"pkg:golang/x@1"}]}]}]}'
printf '%s' "$VEXDOC" > "$SB/vexdoc.json"
cat > "$SB/bin/cosign" <<'STUB'
#!/usr/bin/env bash
printf 'cosign %s\n' "$*" >> "${STUB_ARGV}"
[ "${STUB_COSIGN_FAIL:-}" = "$1" ] && { echo "stub: $1 refused" >&2; exit 1; }
case "$2" in
  --certificate-oidc-issuer) ;;
esac
if [ "$1" = verify-attestation ]; then
  type=""; while [ $# -gt 0 ]; do [ "$1" = --type ] && type="$2"; shift; done
  case "$type" in
    spdxjson) printf '{"payload":"%s"}\n' "$(printf '{"predicateType":"https://spdx.dev/Document","predicate":{"spdxVersion":"SPDX-2.3"}}' | base64 -w0)" ;;
    openvex) printf '{"payload":"%s"}\n' "$(printf '{"predicateType":"https://openvex.dev/ns","predicate":%s}' "$(cat "${STUB_VEXDOC}")" | base64 -w0)" ;;
  esac
fi
exit 0
STUB
# trivy: JSON when asked (the adapter), a table otherwise (the recipe); the
# suppressed set depends on whether --vex oci or a file was given
cat > "$SB/bin/trivy" <<'STUB'
#!/usr/bin/env bash
printf 'trivy %s\n' "$*" >> "${STUB_ARGV}"
out=""; oci=""; while [ $# -gt 0 ]; do case "$1" in --output) out="$2"; shift 2 ;; --vex) [ "$2" = oci ] && oci=1; shift 2 ;; *) shift ;; esac; done
src="${STUB_TRIVY_JSON}"; [ -n "$oci" ] && [ -n "${STUB_TRIVY_OCI_JSON:-}" ] && src="${STUB_TRIVY_OCI_JSON}"
if [ -n "$out" ]; then cp "$src" "$out"; else echo "Total: 1 (HIGH: 1)"; fi
exit 0
STUB
cat > "$SB/bin/grype" <<'STUB'
#!/usr/bin/env bash
printf 'grype %s\n' "$*" >> "${STUB_ARGV}"
[ "${STUB_GRYPE_FAIL:-}" = 1 ] && { echo "grype stub failure" >&2; exit 1; }
if [[ " $* " == *" -o json "* ]]; then cat "${STUB_GRYPE_JSON}"; else echo "NAME  INSTALLED  VULNERABILITY"; fi
STUB
cat > "$SB/bin/docker" <<'STUB'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >> "${STUB_ARGV}"
echo '{"SLSA":{}}'
STUB
chmod +x "$SB/bin/"*
# trivy JSON: both statements suppressed by the file
cat > "$SB/trivy-good.json" <<'EOF'
{"Results":[{"Vulnerabilities":[{"VulnerabilityID":"CVE-2026-1001","Severity":"HIGH","PkgIdentifier":{"PURL":"pkg:golang/github.com/apache/thrift@v0.23.1"}}],
 "ExperimentalModifiedFindings":[
  {"Type":"vulnerability","Status":"not_affected","Source":"openvex.json","Finding":{"VulnerabilityID":"CVE-2026-2001","Severity":"HIGH","PkgIdentifier":{"PURL":"pkg:golang/github.com/grafana/tempo@v1.5.1"}}},
  {"Type":"vulnerability","Status":"fixed","Source":"openvex.json","Finding":{"VulnerabilityID":"CVE-2026-2002","Severity":"HIGH","PkgIdentifier":{"PURL":"pkg:apk/alpine/libssl3@3.5.7-r1?arch=x86_64&distro=3.23.1"}}}]}]}
EOF
# trivy JSON: CVE-2026-2002 still REPORTED, the statement did not land
cat > "$SB/trivy-missing.json" <<'EOF'
{"Results":[{"Vulnerabilities":[{"VulnerabilityID":"CVE-2026-2002","Severity":"HIGH","PkgIdentifier":{"PURL":"pkg:apk/alpine/libssl3@3.5.7-r1?arch=x86_64&distro=3.23.1"}}],
 "ExperimentalModifiedFindings":[
  {"Type":"vulnerability","Status":"not_affected","Source":"openvex.json","Finding":{"VulnerabilityID":"CVE-2026-2001","Severity":"HIGH","PkgIdentifier":{"PURL":"pkg:golang/github.com/grafana/tempo@v1.5.1"}}}]}]}
EOF
cat > "$SB/grype.json" <<'EOF'
{"matches":[{"vulnerability":{"id":"CVE-2026-2002","severity":"High"},"artifact":{"purl":"pkg:apk/alpine/libssl3@3.5.7-r1?arch=x86_64&distro=alpine-3.23"}}],
 "ignoredMatches":[{"match":{"vulnerability":{"id":"CVE-2026-2001","severity":"High"},"artifact":{"purl":"pkg:golang/github.com/grafana/tempo@v1.5.1"}},"appliedIgnoreRules":[{"vulnerability":"CVE-2026-2001","namespace":"","vex-status":"not_affected"}]}]}
EOF
export STUB_ARGV="$SB/argv" STUB_VEXDOC="$SB/vexdoc.json" STUB_TRIVY_JSON="$SB/trivy-good.json" STUB_GRYPE_JSON="$SB/grype.json"
run() { : > "$STUB_ARGV"; (cd "$SB/root" && PATH="$SB/bin:$PATH" "$SMOKE" --root . --readme README.md --ref "$1" --out "$SB/smoke.md" --json "$SB/smoke.json" 2>&1); }
REF="ghcr.io/acme/dhc/grafana@sha256:aaaa"

# 1: a good day: every recipe step ran verbatim with the digest substituted, both suppressions land, exit 0
out=$(run "$REF"); rc=$?
[ "$rc" -eq 0 ] && pass "good day: exit 0" || fail "good day" "rc=$rc" "$out"
grep -q "cosign verify --certificate-oidc-issuer https://token.actions.githubusercontent.com --certificate-identity https://github.com/acme/dhc/.github/workflows/build.yml@refs/heads/main $REF" "$STUB_ARGV" && pass "the signature step ran with the recipe's identities and the smoke digest" || fail "signature step" "$(cat "$STUB_ARGV")"
grep -q "trivy image --vex openvex.json --show-suppressed --severity CRITICAL,HIGH $REF" "$STUB_ARGV" && pass "the trivy recipe step ran verbatim" || fail "trivy step" "$(cat "$STUB_ARGV")"
grep -q "grype $REF --vex openvex.json" "$STUB_ARGV" && pass "the grype recipe step ran verbatim" || fail "grype step" "$(cat "$STUB_ARGV")"
grep -q "docker buildx imagetools inspect $REF" "$STUB_ARGV" && pass "the provenance step ran" || fail "provenance step" "$(cat "$STUB_ARGV")"
grep -q -- "trivy image --vex oci" "$STUB_ARGV" && pass "the --vex oci reading was taken for the regression comparison" || fail "vex oci" "$(cat "$STUB_ARGV")"
grep -q "recipe: 6 step(s) ran, 0 failed" "$SB/smoke.md" && pass "the block counts the recipe steps" || fail "steps counted" "$(cat "$SB/smoke.md")"
grep -q "statements in the attested document: 2 suppressing (not_affected or fixed), 1 affected" "$SB/smoke.md" && pass "the block counts the document's statements" || fail "statement counts" "$(cat "$SB/smoke.md")"
grep -q "trivy (authoritative): 2 of 2 suppressing statement(s) landed, 0 missing" "$SB/smoke.md" && pass "the authoritative assertion is reported" || fail "authoritative line" "$(cat "$SB/smoke.md")"
grep -q -- "--vex oci: same 2 suppression(s) as the extracted document" "$SB/smoke.md" && pass "the oci reading agrees" || fail "oci line" "$(cat "$SB/smoke.md")"
grep -q '#### VEX portability' "$SB/smoke.md" && grep -q 'grype: 1 agree, 1 DIVERGENCE, 0 absent' "$SB/smoke.md" && pass "the other consumer went into the portability block" || fail "portability" "$(cat "$SB/smoke.md")"
jq -e '.ref == "'"$REF"'" and .recipe.failed == 0 and .authoritative.missing == 0 and .oci.agrees == true' "$SB/smoke.json" >/dev/null && pass "the JSON record" || fail "json" "$(cat "$SB/smoke.json")"

# 2: a recipe step fails: the run fails naming the step
export STUB_COSIGN_FAIL=verify
out=$(run "$REF"); rc=$?
unset STUB_COSIGN_FAIL
[ "$rc" -eq 1 ] && grep -q '::error::consumer-smoke: recipe step 1 failed (exit 1): cosign verify' <<<"$out" && pass "a failed recipe step fails the run naming the step" || fail "failed step" "rc=$rc" "$out"

# 3: a suppression missing in the authoritative consumer fails the run by name
export STUB_TRIVY_JSON="$SB/trivy-missing.json"
out=$(run "$REF"); rc=$?
export STUB_TRIVY_JSON="$SB/trivy-good.json"
[ "$rc" -eq 1 ] && grep -q '::error::consumer-smoke: CVE-2026-2002 (pkg:apk/alpine/libssl3@3.5.7-r1, fixed) is still reported by trivy: the published statement did not land in the authoritative consumer (Req 9.13)' <<<"$out" && pass "a missing authoritative suppression fails by name" || fail "missing suppression" "rc=$rc" "$out"
grep -q "trivy (authoritative): 1 of 2 suppressing statement(s) landed, 1 missing" "$SB/smoke.md" && pass "and the block says so" || fail "block on missing" "$(cat "$SB/smoke.md")"

# 4: the --vex oci reading suppresses less than the extracted document: the authoritative consumer
#    is missing a suppression for anyone who follows that reading (ADR 0004's regression check)
export STUB_TRIVY_OCI_JSON="$SB/trivy-missing.json"
out=$(run "$REF"); rc=$?
unset STUB_TRIVY_OCI_JSON
[ "$rc" -eq 1 ] && grep -q '::error::consumer-smoke: trivy --vex oci suppresses 1 statement(s), the extracted document 2: CVE-2026-2002' <<<"$out" && pass "an oci reading that suppresses less fails by name" || fail "oci less" "rc=$rc" "$out"

# 5: the other consumer failing is not a failure of the run: named in the block
export STUB_GRYPE_FAIL=1
out=$(run "$REF"); rc=$?
unset STUB_GRYPE_FAIL
[ "$rc" -eq 1 ] && grep -q 'recipe step 5 failed' <<<"$out" && pass "a failing grype recipe step is a failed instruction step (the recipe is the contract)" || fail "grype recipe fail" "rc=$rc" "$out"

# 6: no README markers: refused
printf '# nothing\n' > "$SB/root/README-empty.md"
out=$(cd "$SB/root" && PATH="$SB/bin:$PATH" "$SMOKE" --root . --readme README-empty.md --ref "$REF" --out "$SB/s.md" --json "$SB/s.json" 2>&1); rc=$?
[ "$rc" -eq 2 ] && grep -q "no rendered recipe between the render-verification markers" <<<"$out" && pass "a README without the recipe is refused" || fail "no recipe" "rc=$rc" "$out"

echo
if [ "$FAILURES" -eq 0 ]; then echo "all consumer-smoke tests passed"; else echo "$FAILURES test(s) failed"; exit 1; fi
