#!/usr/bin/env bash
# Tests for scripts/render-verification.sh: sandboxed repo, no fixture files.
# Contract under test (Req 7.8, 7.9): the verification section of
# catalogue-policy.yaml is the single source; the script renders
# policies/verify-catalogue-images.yaml and the fenced snippets between
# render-verification markers in README.md and docs/user-manual.md; --check
# re-renders and fails naming any artifact that differs from the committed copy.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
RENDER="$HERE/render-verification.sh"
FAILURES=0

pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

BEGIN='<!-- render-verification:begin -->'
END='<!-- render-verification:end -->'

fresh() { # sandbox repo with policy file + marker-bearing docs
  SB=$(mktemp -d)
  mkdir -p "$SB/policies" "$SB/docs"
  cat > "$SB/catalogue-policy.yaml" <<'EOF'
release:
  public: true
  fail_closed: false
  publish_policy: on-change
  platforms: [linux/amd64]
verification:
  registry: ghcr.io/acme/imgs
  issuer: https://issuer.example/oidc
  roles:
    releaser:
      identity: https://github.com/acme/repo/.github/workflows/build.yml@refs/heads/main
      attests: [spdxjson, cyclonedx, vuln, openvex]
    re-attester:
      identity: https://github.com/acme/repo/.github/workflows/rescan.yml@refs/heads/main
      attests: [openvex, vuln]
  required:
    signature: releaser
    attestations:
      spdxjson: [releaser]
      openvex: [releaser, re-attester]
triage:
  aperture: [CRITICAL, HIGH]
consumers:
  list:
    - name: trivy
      authoritative: true
    - name: grype
      authoritative: false
  gating: false
EOF
  printf 'intro\n%s\nstale snippet\n%s\noutro\n' "$BEGIN" "$END" > "$SB/README.md"
  printf 'manual\n%s\nstale snippet\n%s\ntail\n' "$BEGIN" "$END" > "$SB/docs/user-manual.md"
}

snippet() { sed -n "/$1/,/$2/p" "$3"; } # begin-regex end-regex file

# 1: render produces the Kyverno artifact from policy values, no hardcodes
fresh
out=$("$RENDER" "$SB" 2>&1); rc=$?
POL="$SB/policies/verify-catalogue-images.yaml"
if [ "$rc" -ne 0 ]; then fail "render exits 0" "$out"
elif [ ! -f "$POL" ]; then fail "renders policies/verify-catalogue-images.yaml"
else pass "render exits 0 and writes the policy artifact"; fi
for want in \
  "verifyImages" \
  "ghcr.io/acme/imgs/*" \
  "https://issuer.example/oidc" \
  "https://github.com/acme/repo/.github/workflows/build.yml@refs/heads/main" \
  "https://github.com/acme/repo/.github/workflows/rescan.yml@refs/heads/main" \
  "https://spdx.dev/Document" \
  "https://openvex.dev/ns"; do
  grep -qF -- "$want" "$POL" && pass "policy artifact carries $want" || fail "policy artifact carries $want"
done
grep -qF "mm-weber" "$POL" && fail "policy artifact has no out-of-band hardcode" || pass "policy artifact has no out-of-band hardcode"

# 1b (task 14.1, Req 2.2, 7.8, 7.9): the registry gate policy is the second
#    rendered Kyverno artifact. Its allowed-image glob comes from `registry:`,
#    so a fork's chart gate admits the fork's namespace rather than this
#    instance's; both container lists carry the glob, and no hardcode survives.
RR="$SB/policies/restrict-registries.yaml"
if [ ! -f "$RR" ]; then fail "renders policies/restrict-registries.yaml"
else
  pass "renders policies/restrict-registries.yaml"
  for want in "name: restrict-registries" "name: check-registry" "ghcr.io/acme/imgs/*" "=(initContainers):"; do
    grep -qF -- "$want" "$RR" && pass "registry policy carries $want" || fail "registry policy carries $want"
  done
  [ "$(grep -cF 'image: "ghcr.io/acme/imgs/*"' "$RR")" = "2" ] && pass "registry policy globs containers and initContainers" || fail "registry policy globs containers and initContainers" "$(cat "$RR")"
  grep -qF "mm-weber" "$RR" && fail "registry policy has no out-of-band hardcode" || pass "registry policy has no out-of-band hardcode"
  grep -q "render-verification" "$RR" && pass "registry policy says it is rendered" || fail "registry policy says it is rendered"
fi

# 2: role separation in the artifact: the SPDX attestation block admits only
#    the releaser; the rescan identity appears only for openvex
spdx_block=$(awk '/spdx.dev\/Document/{f=1} f{print} f&&/openvex.dev\/ns/{exit}' "$POL")
if grep -qF "rescan.yml" <<<"$spdx_block"; then
  fail "spdx attestor block excludes the re-attester" "$spdx_block"
else
  pass "spdx attestor block excludes the re-attester"
fi

# 2b: "either role" is count: 1. Kyverno's RequiredCount is the number of
#     entries unless count is set (measured 2026-09-03: a single-role-signed
#     OpenVEX document failed "requiredCount: 2"); a single-role set needs none.
vex_block=$(awk '/openvex.dev\/ns/{f=1} f{print}' "$POL")
grep -qE "^\s+- count: 1$" <<<"$vex_block" && pass "the two-role openvex attestor set says count: 1" || fail "the two-role openvex attestor set says count: 1" "$vex_block"
grep -qE "^\s+- count:" <<<"$spdx_block" && fail "the single-role spdx attestor set carries no count" "$spdx_block" || pass "the single-role spdx attestor set carries no count"

# 3: snippets rendered between markers in both docs, from policy values
for doc in "$SB/README.md" "$SB/docs/user-manual.md"; do
  body=$(snippet "render-verification:begin" "render-verification:end" "$doc")
  grep -qF "stale snippet" <<<"$body" && fail "$(basename "$doc") snippet replaced" || pass "$(basename "$doc") snippet replaced"
  for want in \
    "--certificate-oidc-issuer https://issuer.example/oidc" \
    "--certificate-identity https://github.com/acme/repo/.github/workflows/build.yml@refs/heads/main" \
    "ghcr.io/acme/imgs" \
    "--type spdxjson" \
    "--type openvex"; do
    grep -qF -- "$want" <<<"$body" && pass "$(basename "$doc") snippet carries $want" || fail "$(basename "$doc") snippet carries $want"
  done
  # 3a (task 13.4, Req 9.11, 9.13): one scan step per declared consumer, the
  # authoritative one first and marked, the aperture from the policy, the
  # extracted document written to a file both steps read; no vexctl merge
  # (ADR 0003 retired it). This is the recipe the daily smoke test runs verbatim.
  for want in \
    "> openvex.json" \
    'trivy image --vex openvex.json --show-suppressed --severity CRITICAL,HIGH "$REF"   # authoritative consumer' \
    'grype "$REF" --vex openvex.json                                                    # declared consumer, informational'; do
    grep -qF -- "$want" <<<"$body" && pass "$(basename "$doc") snippet carries $want" || fail "$(basename "$doc") snippet carries $want" "$body"
  done
  grep -q 'vexctl' <<<"$body" && fail "$(basename "$doc") snippet has no vexctl merge step" || pass "$(basename "$doc") snippet has no vexctl merge step"
  authline=$(grep -n 'authoritative consumer' <<<"$body" | cut -d: -f1); otherline=$(grep -n 'declared consumer, informational' <<<"$body" | cut -d: -f1)
  [ -n "$authline" ] && [ -n "$otherline" ] && [ "$authline" -lt "$otherline" ] && pass "$(basename "$doc") authoritative consumer step comes first" || fail "$(basename "$doc") step order"
  grep -qF "intro" "$doc" >/dev/null 2>&1 || true
done
grep -qF "intro" "$SB/README.md" && pass "text outside markers untouched" || fail "text outside markers untouched"

# 3b: every rendered file ends with a newline. yamllint's
# new-line-at-end-of-file rule is an error in this repo, so an artifact
# without one fails the validate gate (measured on PR #106, run 33110774290).
for f in "$POL" "$SB/policies/restrict-registries.yaml" "$SB/README.md" "$SB/docs/user-manual.md"; do
  if [ -n "$(tail -c 1 "$f")" ]; then
    fail "$(basename "$f") ends with a newline"
  else
    pass "$(basename "$f") ends with a newline"
  fi
done

# 4: idempotent: a second render changes nothing
cp "$POL" "$POL.first"; cp "$SB/README.md" "$SB/README.md.first"
"$RENDER" "$SB" >/dev/null 2>&1
if diff -q "$POL" "$POL.first" >/dev/null && diff -q "$SB/README.md" "$SB/README.md.first" >/dev/null; then
  pass "render is idempotent"
else
  fail "render is idempotent"
fi
rm -f "$POL.first" "$SB/README.md.first"

# 5: --check on a freshly rendered tree exits 0
out=$("$RENDER" --check "$SB" 2>&1); rc=$?
[ "$rc" -eq 0 ] && pass "--check clean tree exits 0" || fail "--check clean tree exits 0" "$out"

# 6: --check names a tampered policy artifact and fails (Req 7.9)
echo "# drift" >> "$POL"
out=$("$RENDER" --check "$SB" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && grep -qF "policies/verify-catalogue-images.yaml" <<<"$out"; then
  pass "--check fails naming the drifted policy artifact"
else
  fail "--check fails naming the drifted policy artifact" "exit=$rc" "$out"
fi
"$RENDER" "$SB" >/dev/null 2>&1 # restore

# 6b: and a tampered registry policy, by its own name (Req 7.9)
sed -i 's#ghcr.io/acme/imgs/\*#docker.io/*#' "$SB/policies/restrict-registries.yaml"
out=$("$RENDER" --check "$SB" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && grep -qF "policies/restrict-registries.yaml" <<<"$out"; then
  pass "--check fails naming the drifted registry policy"
else
  fail "--check fails naming the drifted registry policy" "exit=$rc" "$out"
fi
"$RENDER" "$SB" >/dev/null 2>&1 # restore

# 7: --check names a tampered snippet and fails
sed -i 's/--type openvex/--type tampered/' "$SB/README.md"
out=$("$RENDER" --check "$SB" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && grep -qF "README.md" <<<"$out"; then
  pass "--check fails naming the drifted README snippet"
else
  fail "--check fails naming the drifted README snippet" "exit=$rc" "$out"
fi

# 7b: rendering must not depend on the local awk's escape handling. GitHub's
# runners ship gawk, which strips a backslash before a newline in a -v
# assignment, while this devcontainer ships mawk, which keeps it: the shell
# line continuations in the snippet therefore rendered clean locally and
# drifted in CI (PR #106, run 33110992171). A stub awk mimicking gawk
# reproduces that here.
fresh
STUB=$(mktemp -d)
cat > "$STUB/awk" <<'STUBEOF'
#!/usr/bin/env python3
import os, sys
argv, out, i = sys.argv[1:], [], 0
while i < len(argv):
    if argv[i] == "-v" and i + 1 < len(argv):
        out += ["-v", argv[i + 1].replace("\\\n", "\n")]  # gawk eats it
        i += 2
    else:
        out.append(argv[i]); i += 1
os.execv("/usr/bin/mawk", ["/usr/bin/mawk"] + out)
STUBEOF
chmod +x "$STUB/awk"
PATH="$STUB:$PATH" "$RENDER" "$SB" >/dev/null 2>&1
body=$(snippet "render-verification:begin" "render-verification:end" "$SB/README.md")
if grep -qF '"$REF" \' <<<"$body"; then
  pass "rendering survives a gawk-style awk (line continuations preserved)"
else
  fail "rendering survives a gawk-style awk (line continuations preserved)" "$body"
fi

# 8: a target without markers fails naming the file and the marker
fresh
printf 'no markers here\n' > "$SB/README.md"
out=$("$RENDER" "$SB" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && grep -qF "README.md" <<<"$out" && grep -qF "render-verification:begin" <<<"$out"; then
  pass "missing markers fail naming file and marker"
else
  fail "missing markers fail naming file and marker" "exit=$rc" "$out"
fi

# 9 (task 18.5, slice 4.2.1; Req 2.28, 2.30, 7.9; ADR 0005 as amended
#    2026-11-13): the provenance mode decides what the verification policy
#    holds. With release.provenance required the one verifyImages entry gains
#    one more attestation: the declared predicate type, the releaser's keyless
#    entry, and the five declared expectations as conditions of equality on
#    the statement's fields. With report and off the policy is byte for byte
#    the one rendered before the track. The declared values below differ from
#    every part of the releaser's identity, so a render that derives them
#    from the identity fails here.
PROV_GOLD=$(mktemp)
cat > "$PROV_GOLD" <<'GOLD'
# Rendered by scripts/render-verification.sh from catalogue-policy.yaml's
# verification section (Req 7.8); do not edit: edit the policy file and
# re-render. validate.yml fails on any drift (Req 7.9).
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-catalogue-images
  annotations:
    policies.kyverno.io/title: Verify Catalogue Images
    policies.kyverno.io/category: dhc-supply-chain
    policies.kyverno.io/description: >-
      Admits an image from ghcr.io/acme/imgs solely on a cosign keyless
      signature from the declared releaser identity, with the required
      attestations present from their declared roles (Req 2.23).
spec:
  validationFailureAction: Enforce
  background: false
  webhookTimeoutSeconds: 30
  rules:
    - name: require-signature-and-attestations
      match:
        any:
          - resources:
              kinds:
                - Pod
      verifyImages:
        - imageReferences:
            - "ghcr.io/acme/imgs/*"
          attestors:
            - entries:
                - keyless:
                    subject: https://github.com/acme/repo/.github/workflows/build.yml@refs/heads/main
                    issuer: https://issuer.example/oidc
                    rekor:
                      url: https://rekor.sigstore.dev
          attestations:
            - type: https://spdx.dev/Document
              attestors:
                - entries:
                    - keyless:
                        subject: https://github.com/acme/repo/.github/workflows/build.yml@refs/heads/main
                        issuer: https://issuer.example/oidc
                        rekor:
                          url: https://rekor.sigstore.dev
            - type: https://openvex.dev/ns
              attestors:
                - count: 1
                  entries:
                    - keyless:
                        subject: https://github.com/acme/repo/.github/workflows/build.yml@refs/heads/main
                        issuer: https://issuer.example/oidc
                        rekor:
                          url: https://rekor.sigstore.dev
                    - keyless:
                        subject: https://github.com/acme/repo/.github/workflows/rescan.yml@refs/heads/main
                        issuer: https://issuer.example/oidc
                        rekor:
                          url: https://rekor.sigstore.dev
GOLD

prov_root() { # mode [fault]: a fresh sandbox in that mode, the declaration whole or faulty
  fresh
  POL="$SB/policies/verify-catalogue-images.yaml"
  sed -i "s/^  publish_policy: on-change\$/&\n  provenance: $1/" "$SB/catalogue-policy.yaml"
  [ "${2:-}" = "absent" ] && return 0
  cat > "$SB/.declaration" <<'EOF'
  provenance:
    predicate_type: https://slsa.dev/provenance/v1
    expectations:
      builder_identity: https://github.com/acme/builders/.github/workflows/release.yml@refs/tags/v7
      build_type: https://buildtypes.example/workflow/v9
      source_repository: https://github.com/acme/source
      workflow_path: .github/workflows/release.yml
      ref: refs/heads/stable
EOF
  case "${2:-}" in
    missing:*) sed -i "/^      ${2#missing:}: /d" "$SB/.declaration" ;;
    number) sed -i 's#^      build_type: .*#      build_type: 42#' "$SB/.declaration" ;;
    empty) sed -i 's#^      workflow_path: .*#      workflow_path: ""#' "$SB/.declaration" ;;
    predicate) sed -i 's#^    predicate_type: .*#    predicate_type: https://slsa.dev/provenance/v0.2#' "$SB/.declaration" ;;
  esac
  sed -i "/^      openvex: \[releaser, re-attester\]\$/r $SB/.declaration" "$SB/catalogue-policy.yaml"
  rm -f "$SB/.declaration"
}

prov_parsed() { # question rendered-policy earlier-policy: exit 0 when the parsed structure answers yes
  python3 - "$@" <<'PY'
import copy, sys, yaml
question, rendered, earlier = sys.argv[1:4]
def no(why):
    print(why); sys.exit(1)
try:
    doc = yaml.safe_load(open(rendered))
    rules = doc["spec"]["rules"]
    entries = rules[0]["verifyImages"]
except Exception as e:
    no(f"not a policy with a verifyImages rule: {e}")
gold = yaml.safe_load(open(earlier))
gold_atts = gold["spec"]["rules"][0]["verifyImages"][0]["attestations"]
atts = entries[0].get("attestations") or []
releaser = "https://github.com/acme/repo/.github/workflows/build.yml@refs/heads/main"
want_attestors = [{"entries": [{"keyless": {
    "subject": releaser,
    "issuer": "https://issuer.example/oidc",
    "rekor": {"url": "https://rekor.sigstore.dev"}}}]}]
want_conditions = [{"all": [
    {"key": "{{ runDetails.builder.id }}", "operator": "Equals",
     "value": "https://github.com/acme/builders/.github/workflows/release.yml@refs/tags/v7"},
    {"key": "{{ buildDefinition.buildType }}", "operator": "Equals",
     "value": "https://buildtypes.example/workflow/v9"},
    {"key": "{{ buildDefinition.externalParameters.workflow.repository }}", "operator": "Equals",
     "value": "https://github.com/acme/source"},
    {"key": "{{ buildDefinition.externalParameters.workflow.path }}", "operator": "Equals",
     "value": ".github/workflows/release.yml"},
    {"key": "{{ buildDefinition.externalParameters.workflow.ref }}", "operator": "Equals",
     "value": "refs/heads/stable"},
]}]
if question == "one-entry":
    if len(rules) != 1 or len(entries) != 1:
        no(f"{len(rules)} rule(s), {len(entries)} verifyImages entr(ies) in the first")
    sys.exit(0)
if question == "rest-unchanged":
    cut = copy.deepcopy(doc)
    cut["spec"]["rules"][0]["verifyImages"][0]["attestations"] = atts[:len(gold_atts)]
    if cut != gold:
        no("the policy differs from the earlier one outside the added attestation")
    sys.exit(0)
if len(atts) != len(gold_atts) + 1 or atts[:len(gold_atts)] != gold_atts:
    no(f"{len(atts)} attestation(s), types {[a.get('type') for a in atts]}: wanted the earlier {len(gold_atts)} and one more after them")
added = atts[-1]
if question == "one-more":
    sys.exit(0)
if question == "type":
    if added.get("type") != "https://slsa.dev/provenance/v1" or sorted(added) != ["attestors", "conditions", "type"]:
        no(f"type {added.get('type')!r}, keys {sorted(added)}")
    sys.exit(0)
if question == "attestor":
    if added.get("attestors") != want_attestors:
        no(yaml.safe_dump(added.get("attestors")))
    sys.exit(0)
if question == "conditions":
    if added.get("conditions") != want_conditions:
        no(yaml.safe_dump(added.get("conditions"), width=200))
    sys.exit(0)
no(f"unknown question {question}")
PY
}

# 9a: required renders the attestation, asserted on the parsed structure
prov_root required
out=$("$RENDER" "$SB" 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ -f "$POL" ] && pass "provenance required: render exits 0 and writes the policy" || fail "provenance required: render exits 0 and writes the policy" "exit=$rc" "$out"
while IFS='|' read -r question name; do
  if why=$(prov_parsed "$question" "$POL" "$PROV_GOLD" 2>&1); then pass "provenance required: $name"; else fail "provenance required: $name" "$why"; fi
done <<'EOF'
one-entry|the policy parses and holds one rule with one verifyImages entry
one-more|the entry holds the earlier attestations and one more after them
type|the added attestation is of the declared predicate type, with attestors and conditions beside it
attestor|the added attestation's one attestor is the releaser's keyless entry under the declared issuer
conditions|the added attestation's conditions are the five declared values, each Equals, keyed inside the predicate
rest-unchanged|outside the added attestation the policy is the earlier one
EOF

# 9b: report and off render the policy of before the track, byte for byte,
#     and --check passes a tree rendered under its own mode, in all three
for m in report off required; do
  prov_root "$m"
  out=$("$RENDER" "$SB" 2>&1); rc=$?
  if [ "$m" != required ]; then
    if [ "$rc" -eq 0 ] && cmp -s "$POL" "$PROV_GOLD"; then
      pass "provenance $m: the policy is byte for byte the earlier one"
    else
      fail "provenance $m: the policy is byte for byte the earlier one" "exit=$rc" "$out" "$(diff "$PROV_GOLD" "$POL" 2>&1)"
    fi
  fi
  out=$("$RENDER" --check "$SB" 2>&1); rc=$?
  [ "$rc" -eq 0 ] && pass "provenance $m: --check passes the tree rendered under it" || fail "provenance $m: --check passes the tree rendered under it" "exit=$rc" "$out"
done

# 9c: a committed policy rendered under another mode is drift (Req 7.9)
while read -r committed declared; do
  prov_root "$committed"
  "$RENDER" "$SB" >/dev/null 2>&1
  sed -i "s/^  provenance: $committed\$/  provenance: $declared/" "$SB/catalogue-policy.yaml"
  out=$("$RENDER" --check "$SB" 2>&1); rc=$?
  if [ "$rc" -eq 1 ] && grep -qF "policies/verify-catalogue-images.yaml" <<<"$out"; then
    pass "provenance $declared: --check fails naming the policy rendered under $committed"
  else
    fail "provenance $declared: --check fails naming the policy rendered under $committed" "exit=$rc" "$out"
  fi
done <<'EOF'
report required
required report
EOF

# 9d: a declaration that cannot serve ends the render: one error line naming
#     the dotted key, nothing written. Under required since slice 4.2.1 (the
#     policy rule needs the five values); under report since slice 4.3.1 (the
#     instruction block's provenance step needs them too), which turned the
#     nine report lines that wanted exit 0 here into nine refusals. Under off
#     the same declaration is no error for this file: nothing of it is rendered.
while read -r fault key; do
  for m in required report; do
    prov_root "$m" "$fault"
    out=$("$RENDER" "$SB" 2>&1); rc=$?
    errs=$(grep '^::error::render-verification: ' <<<"$out")
    if [ "$rc" -ne 0 ] && [ "$(grep -c . <<<"$errs")" = "1" ] && grep -qE "(^|[^A-Za-z0-9_.])$(sed 's/\./\\./g' <<<"$key")([^A-Za-z0-9_.]|\.?\$)" <<<"$errs" \
       && [ ! -e "$POL" ] && [ ! -e "$SB/policies/restrict-registries.yaml" ] && grep -qF "stale snippet" "$SB/README.md" && grep -qF "stale snippet" "$SB/docs/user-manual.md"; then
      pass "provenance $m: a declaration with $fault is refused naming $key, nothing written"
    else
      fail "provenance $m: a declaration with $fault is refused naming $key, nothing written" "exit=$rc" "$out" "$(ls "$SB/policies")"
    fi
  done
  prov_root off "$fault"
  out=$("$RENDER" "$SB" 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && cmp -s "$POL" "$PROV_GOLD"; then
    pass "provenance off: a declaration with $fault is no error, the policy the earlier one"
  else
    fail "provenance off: a declaration with $fault is no error, the policy the earlier one" "exit=$rc" "$out"
  fi
done <<'EOF'
absent verification.provenance
missing:builder_identity verification.provenance.expectations.builder_identity
missing:build_type verification.provenance.expectations.build_type
missing:source_repository verification.provenance.expectations.source_repository
missing:workflow_path verification.provenance.expectations.workflow_path
missing:ref verification.provenance.expectations.ref
number verification.provenance.expectations.build_type
empty verification.provenance.expectations.workflow_path
predicate verification.provenance.predicate_type
EOF
rm -f "$PROV_GOLD"

# 10 (task 18.5, slice 4.3.1; Req 2.25, 2.30, 7.9; spec FR-4; ADR 0005
#    decision 2): the provenance mode decides what the instruction block holds.
#    With report and required: directly after the VEX step and before the
#    first scan step, the sentence saying which digests carry provenance and
#    the consumer step, cosign and then jq over the five DECLARED values.
#    With off, and with no release.provenance key at all (the sandboxes of
#    cases 1 to 8; read here as off), one sentence that releases attest none,
#    and no step. BuildKit's inspect line stays in every mode, labelled
#    supplementary. Both documents get the same block.
prov_block() { # mode: the block that mode renders for prov_root's sandbox, fence to fence
  cat <<'EOF'
```sh
# rendered by scripts/render-verification.sh from catalogue-policy.yaml; do not edit
REF=ghcr.io/acme/imgs/IMAGE:TAG        # any catalogue tag, e.g. grafana:13.1.3-alpine3.23
ISSUER='--certificate-oidc-issuer https://issuer.example/oidc'
BUILD='--certificate-identity https://github.com/acme/repo/.github/workflows/build.yml@refs/heads/main'
RESCAN='--certificate-identity https://github.com/acme/repo/.github/workflows/rescan.yml@refs/heads/main'

cosign verify $ISSUER $BUILD "$REF"                          # signature: the release workflow on main
cosign verify-attestation $ISSUER $BUILD --type spdxjson "$REF" \
  | jq -r '.payload | @base64d | fromjson | .predicate'      # SBOM
{ cosign verify-attestation $ISSUER $BUILD --type openvex "$REF" 2>/dev/null \
  || cosign verify-attestation $ISSUER $RESCAN --type openvex "$REF"; } \
  | jq -r '.payload | @base64d | fromjson | .predicate' > openvex.json   # VEX: releaser or re-attester
EOF
  if [ "$1" = off ]; then
    echo '# Releases attest no SLSA provenance while release.provenance is off (Req 2.30); there is no step to run.'
  else
    echo '# SLSA provenance (Req 2.25): every digest released while the provenance mode is not off carries it. A digest'
    if [ "$1" = required ]; then
      echo '# released before that carries none until its definition is released again, and the verification policy above'
      echo '# admits no image without it.'
    else
      echo '# released before that carries none until its definition is released again; the catalogue status issue names'
      echo '# the supported digests that lack it.'
    fi
    cat <<'EOF'
cosign verify-attestation $ISSUER $BUILD --type slsaprovenance1 "$REF" \
  | jq -r '.payload | @base64d' \
  | jq -es 'any(.[]; .predicate.runDetails.builder.id == "https://github.com/acme/builders/.github/workflows/release.yml@refs/tags/v7" and .predicate.buildDefinition.buildType == "https://buildtypes.example/workflow/v9" and .predicate.buildDefinition.externalParameters.workflow.repository == "https://github.com/acme/source" and .predicate.buildDefinition.externalParameters.workflow.path == ".github/workflows/release.yml" and .predicate.buildDefinition.externalParameters.workflow.ref == "refs/heads/stable")'   # SLSA provenance: signed by the release workflow, and built from this repository, workflow file and ref
EOF
  fi
  cat <<'EOF'
trivy image --vex openvex.json --show-suppressed --severity CRITICAL,HIGH "$REF"   # authoritative consumer
grype "$REF" --vex openvex.json                                                    # declared consumer, informational
# BuildKit provenance is attached at build time as supplementary detail; no policy verifies it
# (Req 2.25). Inspect it with the buildx CLI plugin:
docker buildx imagetools inspect "$REF" --format '{{ json .Provenance }}'
```
EOF
}

prov_block_is() { # mode name: both documents hold exactly that mode's block between their markers
  local doc want
  want=$(prov_block "$1")
  for doc in README.md docs/user-manual.md; do
    if [ "$(snippet "render-verification:begin" "render-verification:end" "$SB/$doc" | sed '1d;$d')" = "$want" ]; then
      pass "$2: $doc holds the block of mode $1"
    else
      fail "$2: $doc holds the block of mode $1" "$(diff <(echo "$want") <(snippet "render-verification:begin" "render-verification:end" "$SB/$doc" | sed '1d;$d') 2>&1)"
    fi
  done
}

# 10a: the block of each mode, in both documents; off and a policy file
#      without the key give no cosign step of the provenance type anywhere
for m in report required off; do
  prov_root "$m"
  "$RENDER" "$SB" >/dev/null 2>&1
  prov_block_is "$m" "provenance $m"
done
fresh
"$RENDER" "$SB" >/dev/null 2>&1
prov_block_is off "no release.provenance key (read as off)"
for m in off none; do
  if [ "$m" = off ]; then prov_root off; label="provenance off"; else fresh; label="no release.provenance key (read as off)"; fi
  "$RENDER" "$SB" >/dev/null 2>&1
  if grep -qF "slsaprovenance1" "$SB/README.md" "$SB/docs/user-manual.md"; then
    fail "$label: no document holds a step of type slsaprovenance1" "$(grep -F slsaprovenance1 "$SB/README.md" "$SB/docs/user-manual.md")"
  elif grep -qF "Releases attest no SLSA provenance" "$SB/README.md" && grep -qF "Releases attest no SLSA provenance" "$SB/docs/user-manual.md"; then
    pass "$label: no document holds a step of type slsaprovenance1, both say that releases attest none"
  else
    fail "$label: no document holds a step of type slsaprovenance1, both say that releases attest none"
  fi
done

# 10b: a block rendered under another mode is drift in both documents (Req 7.9)
while read -r committed declared; do
  prov_root "$committed"
  "$RENDER" "$SB" >/dev/null 2>&1
  sed -i "s/^  provenance: $committed\$/  provenance: $declared/" "$SB/catalogue-policy.yaml"
  out=$("$RENDER" --check "$SB" 2>&1); rc=$?
  if [ "$rc" -eq 1 ] && grep -qF "file=README.md::" <<<"$out" && grep -qF "file=docs/user-manual.md::" <<<"$out"; then
    pass "provenance $declared: --check fails naming both documents rendered under $committed"
  else
    fail "provenance $declared: --check fails naming both documents rendered under $committed" "exit=$rc" "$out"
  fi
done <<'EOF'
off report
report off
report required
required report
off required
required off
EOF

# 10c: the step WORKS. It is taken out of the rendered block (from the line
#      naming the provenance type through the first line that does not end in
#      a backslash), put behind the block's own REF, ISSUER and BUILD lines and
#      run by sh, with the real jq and a stand-in cosign that logs its
#      arguments and prints the envelopes laid down, one JSON line per
#      statement, the way cosign does. A text comparison cannot hold this.
STEPDIR=$(mktemp -d); mkdir "$STEPDIR/bin"
cat > "$STEPDIR/bin/cosign" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$COSIGN_LOG"
cat "$COSIGN_OUT"
exit "$COSIGN_RC"
EOF
chmod +x "$STEPDIR/bin/cosign"
PROV_B='https://github.com/acme/builders/.github/workflows/release.yml@refs/tags/v7'
PROV_T='https://buildtypes.example/workflow/v9'
PROV_R='https://github.com/acme/source'
PROV_P='.github/workflows/release.yml'
PROV_F='refs/heads/stable'

prov_wrap() { # a statement on stdin: the envelope line cosign prints for it
  base64 -w0 | jq -Rc '{payloadType: "application/vnd.in-toto+json", payload: ., signatures: [{keyid: "", sig: "MEUCIQ"}]}'
}
prov_envelope() { # builder buildType repository path ref: the envelope of a statement carrying them
  jq -cn --arg b "$1" --arg t "$2" --arg r "$3" --arg p "$4" --arg f "$5" '{
    _type: "https://in-toto.io/Statement/v1",
    subject: [{name: "ghcr.io/acme/imgs/IMAGE", digest: {sha256: "00"}}],
    predicateType: "https://slsa.dev/provenance/v1",
    predicate: {
      buildDefinition: {buildType: $t, externalParameters: {workflow: {ref: $f, repository: $r, path: $p}}},
      runDetails: {builder: {id: $b}}}}' | prov_wrap
}
prov_step_of() { # doc: the step of that document's block as $STEPDIR/step.sh; HAVE_STEP says whether there is one
  HAVE_STEP=no
  awk '/--type slsaprovenance1/{f=1} f{print} f&&!/\\$/{exit}' "$1" > "$STEPDIR/step"
  [ -s "$STEPDIR/step" ] || return 0
  { grep -E '^(REF|ISSUER|BUILD)=' "$1"; cat "$STEPDIR/step"; } > "$STEPDIR/step.sh"
  HAVE_STEP=yes
}
prov_want() { # zero|nonzero name [cosign-exit], the envelopes on stdin: run the step, judge its exit status
  local rc
  cat > "$STEPDIR/envelopes"; : > "$STEPDIR/log"
  if [ "$HAVE_STEP" != yes ]; then fail "$2" "the block holds no step of type slsaprovenance1"; return; fi
  ( cd "$STEPDIR" && COSIGN_OUT="$STEPDIR/envelopes" COSIGN_LOG="$STEPDIR/log" COSIGN_RC="${3:-0}" PATH="$STEPDIR/bin:$PATH" sh ./step.sh > "$STEPDIR/stdout" 2>&1 ); rc=$?
  if { [ "$1" = zero ] && [ "$rc" -eq 0 ]; } || { [ "$1" = nonzero ] && [ "$rc" -ne 0 ]; }; then
    pass "$2"
  else
    fail "$2" "exit=$rc, wanted $1" "$(cat "$STEPDIR/stdout")"
  fi
}

for m in report required; do
  prov_root "$m"
  "$RENDER" "$SB" >/dev/null 2>&1
  prov_step_of "$SB/docs/user-manual.md"
  prov_envelope "$PROV_B" "$PROV_T" "$PROV_R" "$PROV_P" "$PROV_F" | prov_want zero "provenance $m: the step exits 0 on a statement carrying the five declared values"
  asked='verify-attestation --certificate-oidc-issuer https://issuer.example/oidc --certificate-identity https://github.com/acme/repo/.github/workflows/build.yml@refs/heads/main --type slsaprovenance1 ghcr.io/acme/imgs/IMAGE:TAG'
  if [ "$HAVE_STEP" = yes ] && [ "$(cat "$STEPDIR/log")" = "$asked" ]; then
    pass "provenance $m: the step asks cosign once, under the declared issuer and the releaser's identity"
  else
    fail "provenance $m: the step asks cosign once, under the declared issuer and the releaser's identity" "$(cat "$STEPDIR/log" 2>/dev/null)"
  fi
  prov_envelope "$PROV_B.x" "$PROV_T" "$PROV_R" "$PROV_P" "$PROV_F" | prov_want nonzero "provenance $m: the step refuses a statement with another builder identity"
  prov_envelope "$PROV_B" "$PROV_T.x" "$PROV_R" "$PROV_P" "$PROV_F" | prov_want nonzero "provenance $m: the step refuses a statement with another build type"
  prov_envelope "$PROV_B" "$PROV_T" "$PROV_R.x" "$PROV_P" "$PROV_F" | prov_want nonzero "provenance $m: the step refuses a statement with another source repository"
  prov_envelope "$PROV_B" "$PROV_T" "$PROV_R" "$PROV_P.x" "$PROV_F" | prov_want nonzero "provenance $m: the step refuses a statement with another workflow path"
  prov_envelope "$PROV_B" "$PROV_T" "$PROV_R" "$PROV_P" "$PROV_F.x" | prov_want nonzero "provenance $m: the step refuses a statement with another ref"
  prov_want nonzero "provenance $m: the step refuses when cosign prints no statement and exits 0" </dev/null
  prov_want nonzero "provenance $m: the step refuses when cosign prints no statement and exits 1" 1 </dev/null
  { prov_envelope "$PROV_B" "$PROV_T" "$PROV_R" "$PROV_P" "$PROV_F.x"; prov_envelope "$PROV_B" "$PROV_T" "$PROV_R" "$PROV_P" "$PROV_F"; } \
    | prov_want zero "provenance $m: the step exits 0 on a statement meeting the five after one that does not"
  { prov_envelope "$PROV_B" "$PROV_T" "$PROV_R" "$PROV_P" "$PROV_F"; prov_envelope "$PROV_B.x" "$PROV_T" "$PROV_R" "$PROV_P" "$PROV_F"; } \
    | prov_want zero "provenance $m: the step exits 0 on a statement meeting the five before one that does not"
  { prov_envelope "$PROV_B.x" "$PROV_T" "$PROV_R" "$PROV_P" "$PROV_F"; prov_envelope "$PROV_B" "$PROV_T" "$PROV_R" "$PROV_P" "$PROV_F.x"; } \
    | prov_want nonzero "provenance $m: the step refuses two statements that meet the five only between them"
  printf 'null' | prov_wrap | prov_want nonzero "provenance $m: the step refuses a payload of JSON null"
done

# 10d: the five values stand in the jq program as JSON string literals: a
#      declared value holding a double quote and a backslash is compared as
#      it is declared
prov_root report
sed -i 's#^      ref: refs/heads/stable$#      ref: refs/heads/sta"b\\le#' "$SB/catalogue-policy.yaml"
"$RENDER" "$SB" >/dev/null 2>&1
prov_step_of "$SB/README.md"
prov_envelope "$PROV_B" "$PROV_T" "$PROV_R" "$PROV_P" 'refs/heads/sta"b\le' | prov_want zero "provenance report: the step exits 0 on a declared ref holding a double quote and a backslash"
prov_envelope "$PROV_B" "$PROV_T" "$PROV_R" "$PROV_P" "$PROV_F" | prov_want nonzero "provenance report: the step refuses another ref than the declared one holding a double quote and a backslash"
rm -rf "$STEPDIR"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all render-verification tests passed"
