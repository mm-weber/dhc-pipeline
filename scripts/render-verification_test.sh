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

# 9d: under required a declaration that cannot serve ends the render: one
#     error line naming the dotted key, nothing written. Under report and off
#     the same declaration is no error for this file: nothing of it is rendered.
while read -r fault key; do
  prov_root required "$fault"
  out=$("$RENDER" "$SB" 2>&1); rc=$?
  errs=$(grep '^::error::render-verification: ' <<<"$out")
  if [ "$rc" -ne 0 ] && [ "$(grep -c . <<<"$errs")" = "1" ] && grep -qE "(^|[^A-Za-z0-9_.])$(sed 's/\./\\./g' <<<"$key")([^A-Za-z0-9_.]|\.?\$)" <<<"$errs" \
     && [ ! -e "$POL" ] && [ ! -e "$SB/policies/restrict-registries.yaml" ] && grep -qF "stale snippet" "$SB/README.md" && grep -qF "stale snippet" "$SB/docs/user-manual.md"; then
    pass "provenance required: a declaration with $fault is refused naming $key, nothing written"
  else
    fail "provenance required: a declaration with $fault is refused naming $key, nothing written" "exit=$rc" "$out" "$(ls "$SB/policies")"
  fi
  for m in report off; do
    prov_root "$m" "$fault"
    out=$("$RENDER" "$SB" 2>&1); rc=$?
    if [ "$rc" -eq 0 ] && cmp -s "$POL" "$PROV_GOLD"; then
      pass "provenance $m: a declaration with $fault is no error, the policy the earlier one"
    else
      fail "provenance $m: a declaration with $fault is no error, the policy the earlier one" "exit=$rc" "$out"
    fi
  done
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

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all render-verification tests passed"
