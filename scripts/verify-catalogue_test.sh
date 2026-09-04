#!/usr/bin/env bash
# Tests for scripts/verify-catalogue.sh: the daily admission proof (task 9.6,
# Req 2.24).
#
# The requirement: the rendered admission policy, applied against the live
# registry, must ADMIT every digest a catalogue tag references and must
# REJECT the declared unsigned control, every day, or the run fails naming
# what deviated. The control exists because a policy that admits everything
# is indistinguishable from one that works, until something it should reject
# gets through.
#
# kyverno is stubbed: what the suite pins is the resource set handed to it
# (one Pod per unique tag-referenced digest plus the control), the exact
# invocation, and the verdict logic over its report, including the case the
# tool itself could not verify (result "error"), which is never a pass.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
VERIFY="$HERE/verify-catalogue.sh"
FAILURES=0

pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

CONTROL="ghcr.io/acme/dhc/grafana@sha256:4660000000000000000000000000000000000000000000000000000000000000"

fresh() {
  SB=$(mktemp -d)
  mkdir -p "$SB/root/policies" "$SB/bin"
  cat > "$SB/root/catalogue-policy.yaml" <<EOF
verification:
  registry: ghcr.io/acme/dhc
  issuer: https://token.actions.githubusercontent.com
  roles:
    releaser:
      identity: https://github.com/acme/dhc/.github/workflows/build.yml@refs/heads/main
      attests: [spdxjson, cyclonedx, vuln, openvex]
    re-attester:
      identity: https://github.com/acme/dhc/.github/workflows/rescan.yml@refs/heads/main
      attests: [openvex, vuln]
  required:
    signature: releaser
    attestations:
      spdxjson: [releaser]
      openvex: [releaser, re-attester]
  control: ${CONTROL}
EOF
  # cosign, the second opinion on a digest the policy rejects alone: each
  # call answers ok unless STUB_COSIGN_FAIL names it as "<ref substring>|<what>"
  # entries, what being sig, spdxjson:<role>, or openvex:<role>.
  cat > "$SB/bin/cosign" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "cosign $*" >> "${STUB_ARGV}"
ref="${*: -1}"; what="sig"; role=""
type=""; id=""; prev=""
for a in "$@"; do
  [ "$prev" = "--type" ] && type="$a"; [ "$prev" = "--certificate-identity" ] && id="$a"; prev="$a"
done
case "$id" in *build.yml*) role=releaser;; *rescan.yml*) role=re-attester;; esac
[ "$1" = "verify-attestation" ] && what="${type}:${role}"
IFS=';' read -r -a rules <<< "${STUB_COSIGN_FAIL:-}"
for r in "${rules[@]}"; do
  [ -z "$r" ] && continue
  sub="${r%%|*}"; w="${r#*|}"
  if [[ "$ref" == *"$sub"* && "$w" == "$what" ]]; then echo "Error: no matching ${what} found for ${ref} (stub)" >&2; exit 1; fi
done
echo '{"verified":"stub"}'
STUB
  chmod +x "$SB/bin/cosign"
  printf 'apiVersion: kyverno.io/v1\nkind: ClusterPolicy\nmetadata: {name: verify-catalogue-images}\n' > "$SB/root/policies/verify-catalogue-images.yaml"
  # Two tags sharing one digest, a two-platform index, a superseded bare
  # manifest: three unique tag-referenced digests -> three admit Pods.
  cat > "$SB/enum.tsv" <<'EOF'
ghcr.io/acme/dhc/solo	1-alpine3.23	sha256:aaaa	linux/amd64	sha256:aaa1	supported
ghcr.io/acme/dhc/solo	1.0-alpine3.23	sha256:aaaa	linux/amd64	sha256:aaa1	supported
ghcr.io/acme/dhc/valkey	9-alpine3.23	sha256:bbbb	linux/amd64	sha256:bbb1	supported
ghcr.io/acme/dhc/valkey	9-alpine3.23	sha256:bbbb	linux/arm64	sha256:bbb2	supported
ghcr.io/acme/dhc/valkey	9.0.5-alpine3.23	sha256:cccc	-	sha256:cccc	superseded
EOF
  cat > "$SB/bin/kyverno" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "kyverno $*" >> "${STUB_ARGV}"
# find the --resource file and enumerate its Pods, answering per name
res=""; prev=""
for a in "$@"; do [ "$prev" = "--resource" ] && res="$a"; prev="$a"; done
cat "$res" >> "${STUB_ARGV}.pods"
echo "Applying 1 policy rule(s) to N resource(s)..."
python3 - "$res" <<'PY'
import os, sys, yaml
pods = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
fail_names = os.environ.get("STUB_FAIL", "").split()
err_names = os.environ.get("STUB_ERROR", "").split()
results = []
for p in pods:
    n = p["metadata"]["name"]
    if n in err_names: r = "error"
    elif n in fail_names: r = "fail"
    elif n.startswith("control"): r = "pass" if os.environ.get("STUB_PASS_CONTROL") else "fail"
    else: r = "pass"
    results.append({"result": r, "policy": "verify-catalogue-images", "rule": "require-signature-and-attestations",
                    "resources": [{"kind": "Pod", "name": n}], "message": f"stub {r}"})
import json
print(json.dumps({"kind": "ClusterReport", "summary": {}, "results": results}))
PY
STUB
  chmod +x "$SB/bin/kyverno"
  export STUB_ARGV="$SB/argv"
  unset STUB_FAIL STUB_ERROR STUB_PASS_CONTROL STUB_COSIGN_FAIL
  : > "$SB/argv"
}
run() { PATH="$SB/bin:$PATH" "$VERIFY" "$SB/root" "$SB/enum.tsv" "$SB/report.json" 2>&1; }

# 1: every tag-referenced digest admitted, the control rejected: exit 0.
fresh
out=$(run); rc=$?
[ "$rc" -eq 0 ] && pass "admit-all, reject-control exits 0" || fail "admit-all, reject-control exits 0" "$out"
n=$(grep -c "^kind: Pod" "$SB/argv.pods"); [ "$n" = "4" ] && pass "one Pod per unique tag-referenced digest plus the control" || fail "one Pod per unique tag-referenced digest plus the control" "got $n" "$(cat "$SB/argv.pods")"
[ "$(grep -c '^kyverno apply' "$SB/argv")" -eq 4 ] && pass "each Pod is applied alone, never in a batch" || fail "each Pod is applied alone" "$(cat "$SB/argv")"
grep -q "image: ghcr.io/acme/dhc/solo@sha256:aaaa$" "$SB/argv.pods" && pass "a digest shared by two tags is one Pod, by index digest" || fail "a digest shared by two tags is one Pod, by index digest" "$(cat "$SB/argv.pods")"
grep -q "image: ${CONTROL}$" "$SB/argv.pods" && pass "the control is in the resource set" || fail "the control is in the resource set" "$(cat "$SB/argv.pods")"
grep -q "3 admitted, control rejected" <<<"$out" && pass "summary states both halves" || fail "summary states both halves" "$out"
[ -s "$SB/report.json" ] && pass "the parsed report is written for the artifact" || fail "the parsed report is written for the artifact"

# 2: the invocation is the design's: the rendered policy, the resource file,
#    the live registry, a JSON policy report. No credentials on the command
#    line: kyverno reads the job's docker login, which is the intent here
#    (admission is what a pulling consumer experiences).
grep -qE "kyverno apply .*policies/verify-catalogue-images.yaml .*--resource .*--registry" "$SB/argv" \
  && pass "applies the rendered policy against the registry" || fail "applies the rendered policy against the registry" "$(cat "$SB/argv")"
grep -qE -- "-p .*--output-format json|--policy-report .*--output-format json" "$SB/argv" \
  && pass "asks for a JSON policy report" || fail "asks for a JSON policy report" "$(cat "$SB/argv")"

# 3: a tag-referenced digest the policy rejects fails the run, named with
#    its tags, so the reader knows which promise broke. The shared-digest
#    case pins the tag join: mawk once produced ",1-alpine3.23,…" here.
fresh
export STUB_FAIL="admit-001 admit-002"
out=$(run); rc=$?
[ "$rc" -ne 0 ] && pass "a rejected catalogue digest fails the run" || fail "a rejected catalogue digest fails the run" "$out"
grep -q "sha256:bbbb" <<<"$out" && grep -q "9-alpine3.23" <<<"$out" \
  && pass "naming the digest and its tags" || fail "naming the digest and its tags" "$out"
grep -q "(tags: 1-alpine3.23,1.0-alpine3.23)" <<<"$out" \
  && pass "tags sharing a digest join cleanly" || fail "tags sharing a digest join cleanly" "$out"

# 4: a control that gets ADMITTED is the worst outcome: the policy proves
#    nothing. Fails loudly even though every catalogue digest passed.
fresh
export STUB_PASS_CONTROL=1
out=$(run); rc=$?
[ "$rc" -ne 0 ] && pass "an admitted control fails the run" || fail "an admitted control fails the run" "$out"
grep -qi "control" <<<"$out" && grep -qi "admitted" <<<"$out" && pass "saying the control was admitted" || fail "saying the control was admitted" "$out"

# 5: "error" (the tool could not verify: registry, Rekor, Fulcio) is not a
#    pass and not a reject; it fails the run by name.
fresh
export STUB_ERROR="admit-001"
out=$(run); rc=$?
[ "$rc" -ne 0 ] && pass "a verification error fails the run" || fail "a verification error fails the run" "$out"
grep -q "sha256:aaaa" <<<"$out" && grep -qi "error" <<<"$out" && pass "naming it as an error, not a rejection" || fail "naming it as an error, not a rejection" "$out"

# 6: refusals: no enumeration, no declared control.
fresh
rm "$SB/enum.tsv"
out=$(run); rc=$?
[ "$rc" -eq 2 ] && pass "a missing enumeration refuses with exit 2" || fail "a missing enumeration refuses with exit 2" "rc=$rc" "$out"
fresh
printf 'verification:\n  registry: ghcr.io/acme/dhc\n' > "$SB/root/catalogue-policy.yaml"
out=$(run); rc=$?
[ "$rc" -eq 2 ] && pass "no declared control refuses with exit 2" || fail "no declared control refuses with exit 2" "rc=$rc" "$out"
grep -q "control" <<<"$out" && pass "saying what is missing" || fail "saying what is missing" "$out"

echo
# --- the cosign second opinion on a rejected digest --------------------------
#
# Kyverno's rejection reasons are terse ("unverified image"); cosign's are not.
# For a digest the policy rejects, the proof asks cosign the same
# questions, one per role and type, on the index and on every platform
# manifest the enumeration lists, and records each answer, so the next run
# says which check fails and where rather than that something did.
fresh; export STUB_FAIL="admit-002" STUB_COSIGN_FAIL="sha256:bbb2|sig;sha256:bbbb|openvex:re-attester"
out=$(run); rc=$?
[ "$rc" -eq 1 ] && pass "a rejected digest fails the proof" || fail "rc=$rc" "$out"
grep -q "::notice::verify-catalogue: cosign on ghcr.io/acme/dhc/valkey@sha256:bbbb" <<<"$out" && pass "cosign's second opinion is annotated" || fail "notice" "$out"
grep -q "manifest sha256:bbb2 signature: no matching sig" <<<"$out" && pass "naming the platform manifest whose signature fails" || fail "manifest sig" "$out"
grep -q "index openvex by re-attester: no matching openvex" <<<"$out" && pass "and the attestation and role that fail on the index" || fail "index att" "$out"
grep -q "index signature: ok" <<<"$out" && pass "and what passes" || fail "ok" "$out"
[ "$(grep -c 'cosign verify --certificate-oidc-issuer https://token.actions.githubusercontent.com --certificate-identity https://github.com/acme/dhc/.github/workflows/build.yml@refs/heads/main' "$SB/argv")" -eq 3 ] && pass "the signature is checked on the index and both manifests, releaser identity" || fail "verify calls" "$(grep cosign "$SB/argv")"
[ "$(grep -c 'cosign verify-attestation --type openvex' "$SB/argv")" -eq 6 ] && pass "openvex is checked for both roles on all three" || fail "openvex calls" "$(grep 'verify-attestation' "$SB/argv")"
[ "$(jq -r '.resources[] | select(.name=="admit-002") | .cosign["ghcr.io/acme/dhc/valkey@sha256:bbb2"].signature' "$SB/report.json")" != "ok" ] && pass "the report keeps every answer" || fail "report" "$(cat "$SB/report.json")"
fresh
out=$(run); rc=$?
[ "$(grep -c '^cosign' "$SB/argv")" -eq 0 ] && pass "an admitted digest gets no cosign call" || fail "cosign on admitted" "$(grep cosign "$SB/argv")"

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all verify-catalogue tests passed"
