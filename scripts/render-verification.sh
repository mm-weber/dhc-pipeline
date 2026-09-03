#!/usr/bin/env bash
# render-verification.sh [--check] [root]: render the verification artifacts
# from catalogue-policy.yaml's `verification` section (Req 7.8), the single
# committed home of the issuer, role identities, registry namespace and
# required predicate types (Req 7.7).
#
# Renders:
#   - policies/verify-catalogue-images.yaml   (Kyverno verifyImages, Req 2.23)
#   - the fenced consumer snippet between
#       <!-- render-verification:begin --> / <!-- render-verification:end -->
#     in README.md and docs/user-manual.md   (Req 2.25)
#
# --check re-renders and fails naming each committed artifact that differs
# (Req 7.9): validate.yml runs this on every PR, so a hand edit to a rendered
# artifact goes red instead of silently forking the declared values.
#
# Rendering and splicing happen in python3 (PyYAML, the dependency
# lint-accepted-risk.sh already leans on; installed by validate.yml's yamllint
# step). Deliberately no awk and no command substitution on the rendered text:
# the snippet carries shell line continuations, gawk strips a backslash before
# a newline in a -v assignment while mawk keeps it, and command substitution
# eats trailing newlines. Text handling stays in one implementation that does
# no escape processing at all (PR #106, run 33110992171).
set -euo pipefail

MODE=render
if [ "${1:-}" = "--check" ]; then MODE=check; shift; fi
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ROOT="${ROOT%/}"
POLICY_FILE="$ROOT/catalogue-policy.yaml"
[ -f "$POLICY_FILE" ] || { echo "render-verification: no catalogue-policy.yaml under $ROOT" >&2; exit 1; }

python3 - "$MODE" "$ROOT" "$POLICY_FILE" <<'PY'
import os, sys, yaml

mode, root, policy_path = sys.argv[1], sys.argv[2], sys.argv[3]

BEGIN = "<!-- render-verification:begin -->"
END = "<!-- render-verification:end -->"
KYVERNO_REL = "policies/verify-catalogue-images.yaml"
DOC_RELS = ["README.md", "docs/user-manual.md"]

pol = yaml.safe_load(open(policy_path))["verification"]
registry, issuer = pol["registry"], pol["issuer"]
roles, required = pol["roles"], pol["required"]

# cosign --type aliases to the predicateType URLs Kyverno matches on.
PREDICATE = {
    "spdxjson": "https://spdx.dev/Document",
    "cyclonedx": "https://cyclonedx.org/bom",
    "openvex": "https://openvex.dev/ns",
    "vuln": "https://cosign.sigstore.dev/attestation/vuln/v1",
}

def keyless(role, indent):
    pad = " " * indent
    return (
        f"{pad}- keyless:\n"
        f"{pad}    subject: {roles[role]['identity']}\n"
        f"{pad}    issuer: {issuer}\n"
        f"{pad}    rekor:\n"
        f"{pad}      url: https://rekor.sigstore.dev\n"
    )

sig_role = required["signature"]
att = required["attestations"]

parts = [f"""# Rendered by scripts/render-verification.sh from catalogue-policy.yaml's
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
      Admits an image from {registry} solely on a cosign keyless
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
            - "{registry}/*"
          attestors:
            - entries:
{keyless(sig_role, 16)}          attestations:
"""]
for alias in ["spdxjson", "openvex", "cyclonedx", "vuln"]:
    if alias not in att:
        continue
    # One attestor set per type. Kyverno requires as many entries of a set
    # to verify as the set has, unless `count` says otherwise (RequiredCount
    # in api/kyverno/v1/image_verification_types.go, measured on 1.18.2 on
    # 2026-09-03 against the live catalogue, where an OpenVEX document signed
    # by one role was rejected with "requiredCount: 2"). Several roles mean
    # "any one of them", which is count: 1; a single role needs no count.
    head = "                - count: 1\n                  entries:\n" if len(att[alias]) > 1 else "                - entries:\n"
    parts.append(f"            - type: {PREDICATE[alias]}\n              attestors:\n{head}")
    for role in att[alias]:
        parts.append(keyless(role, 20))
kyverno_text = "".join(parts)

rel = roles[sig_role]["identity"]
vex_roles = att.get("openvex", [sig_role])
snip = [
    "```sh",
    "# rendered by scripts/render-verification.sh from catalogue-policy.yaml; do not edit",
    f"REF={registry}/IMAGE:TAG        # any catalogue tag, e.g. grafana:13.1.3-alpine3.23",
    f"ISSUER='--certificate-oidc-issuer {issuer}'",
    f"BUILD='--certificate-identity {rel}'",
]
if len(vex_roles) > 1:
    other = [r for r in vex_roles if r != sig_role][0]
    snip.append(f"RESCAN='--certificate-identity {roles[other]['identity']}'")
snip += [
    "",
    'cosign verify $ISSUER $BUILD "$REF"                          # signature: the release workflow on main',
    'cosign verify-attestation $ISSUER $BUILD --type spdxjson "$REF" \\',
    "  | jq -r '.payload | @base64d | fromjson | .predicate'      # SBOM",
]
if len(vex_roles) > 1:
    snip += [
        'cosign verify-attestation $ISSUER $BUILD --type openvex "$REF" 2>/dev/null \\',
        '  || cosign verify-attestation $ISSUER $RESCAN --type openvex "$REF" \\',
        "  | jq -r '.payload | @base64d | fromjson | .predicate'      # VEX: releaser or re-attester",
    ]
else:
    snip += [
        'cosign verify-attestation $ISSUER $BUILD --type openvex "$REF" \\',
        "  | jq -r '.payload | @base64d | fromjson | .predicate'      # VEX, compiled per digest",
    ]
snip += [
    "# BuildKit provenance is attached at build time and is not verified by the",
    "# policy above (Req 2.25); inspect it with the buildx CLI plugin:",
    "docker buildx imagetools inspect \"$REF\" --format '{{ json .Provenance }}'",
    "```",
]
snippet_lines = [line + "\n" for line in snip]

failures = 0
def drift(rel_path):
    global failures
    print(f"::error file={rel_path}::render-verification: {rel_path} differs from its "
          f"rendered form (Req 7.9); edit catalogue-policy.yaml and re-run "
          f"scripts/render-verification.sh")
    failures += 1

def emit(rel_path, text):
    path = os.path.join(root, rel_path)
    if mode == "check":
        current = open(path).read() if os.path.isfile(path) else None
        if current != text:
            drift(rel_path)
    else:
        open(path, "w").write(text)

emit(KYVERNO_REL, kyverno_text)

for rel_path in DOC_RELS:
    path = os.path.join(root, rel_path)
    if not os.path.isfile(path):
        print(f"render-verification: missing target {rel_path}", file=sys.stderr)
        sys.exit(1)
    lines = open(path).readlines()
    begins = [i for i, l in enumerate(lines) if BEGIN in l]
    ends = [i for i, l in enumerate(lines) if END in l]
    if not begins or not ends:
        print(f"render-verification: {rel_path} lacks the {BEGIN} / {END} markers", file=sys.stderr)
        sys.exit(1)
    rebuilt = "".join(lines[: begins[0] + 1] + snippet_lines + lines[ends[0] :])
    emit(rel_path, rebuilt)

if failures:
    sys.exit(1)
if mode != "check":
    print(f"render-verification: rendered {KYVERNO_REL} and {len(DOC_RELS)} snippet(s) "
          f"from catalogue-policy.yaml")
PY
