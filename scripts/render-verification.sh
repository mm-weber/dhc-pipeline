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
# --check re-renders into a scratch copy and fails naming each committed
# artifact that differs (Req 7.9): validate.yml runs this on every PR, so a
# hand edit to a rendered artifact goes red instead of silently forking the
# declared values.
#
# YAML is read with python3 + PyYAML, the same dependency lint-accepted-risk.sh
# already leans on (installed by validate.yml's yamllint step; present in the
# devcontainer). mikefarah yq is NOT assumed: the local container ships the
# incompatible python wrapper under the same name.
set -euo pipefail

MODE=render
if [ "${1:-}" = "--check" ]; then MODE=check; shift; fi
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ROOT="${ROOT%/}"
POLICY_FILE="$ROOT/catalogue-policy.yaml"
[ -f "$POLICY_FILE" ] || { echo "render-verification: no catalogue-policy.yaml under $ROOT" >&2; exit 1; }

BEGIN='<!-- render-verification:begin -->'
END='<!-- render-verification:end -->'
TARGET_DOCS=("README.md" "docs/user-manual.md")
KYVERNO_REL="policies/verify-catalogue-images.yaml"

# Emit the two rendered texts, separated by a NUL, from the policy file.
render_texts() {
  python3 - "$POLICY_FILE" <<'PY'
import sys, yaml

pol = yaml.safe_load(open(sys.argv[1]))["verification"]
registry = pol["registry"]
issuer = pol["issuer"]
roles = pol["roles"]
required = pol["required"]

# cosign --type aliases to the predicateType URLs Kyverno matches on.
PREDICATE = {
    "spdxjson": "https://spdx.dev/Document",
    "cyclonedx": "https://cyclonedx.org/bom",
    "openvex": "https://openvex.dev/ns",
    "vuln": "https://cosign.sigstore.dev/attestation/vuln/v1",
}

def keyless(role):
    return (
        "                - keyless:\n"
        f"                    subject: {roles[role]['identity']}\n"
        f"                    issuer: {issuer}\n"
        "                    rekor:\n"
        "                      url: https://rekor.sigstore.dev\n"
    )

sig_role = required["signature"]
att = required["attestations"]

kyverno = []
kyverno.append(f"""# Rendered by scripts/render-verification.sh from catalogue-policy.yaml's
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
{keyless(sig_role)}          attestations:
""")
for alias in ["spdxjson", "openvex", "cyclonedx", "vuln"]:
    if alias not in att:
        continue
    kyverno.append(f"            - type: {PREDICATE[alias]}\n              attestors:\n                - entries:\n")
    for role in att[alias]:
        # one indent level deeper than the signature attestor block
        block = "\n".join("    " + line if line else line for line in keyless(role).splitlines())
        kyverno.append(block + "\n")
kyverno_text = "".join(kyverno)

rel = roles[sig_role]["identity"]
vex_roles = att.get("openvex", [sig_role])
snippet = []
snippet.append(f"""```sh
# rendered by scripts/render-verification.sh from catalogue-policy.yaml; do not edit
REF={registry}/IMAGE:TAG        # any catalogue tag, e.g. grafana:13.1.3-alpine3.23
ISSUER='--certificate-oidc-issuer {issuer}'
BUILD='--certificate-identity {rel}'
""")
if len(vex_roles) > 1:
    other = [r for r in vex_roles if r != sig_role][0]
    snippet.append(f"RESCAN='--certificate-identity {roles[other]['identity']}'\n")
snippet.append(f"""
cosign verify $ISSUER $BUILD "$REF"                          # signature: the release workflow on main
cosign verify-attestation $ISSUER $BUILD --type spdxjson "$REF" \\
  | jq -r '.payload | @base64d | fromjson | .predicate'      # SBOM
""")
if len(vex_roles) > 1:
    snippet.append("""cosign verify-attestation $ISSUER $BUILD --type openvex "$REF" 2>/dev/null \\
  || cosign verify-attestation $ISSUER $RESCAN --type openvex "$REF" \\
  | jq -r '.payload | @base64d | fromjson | .predicate'      # VEX: releaser or re-attester
""")
else:
    snippet.append("""cosign verify-attestation $ISSUER $BUILD --type openvex "$REF" \\
  | jq -r '.payload | @base64d | fromjson | .predicate'      # VEX, compiled per digest
""")
snippet.append("""# BuildKit provenance is attached at build time and is not verified by the
# policy above (Req 2.25); inspect it with the buildx CLI plugin:
docker buildx imagetools inspect "$REF" --format '{{ json .Provenance }}'
```""")
snippet_text = "".join(snippet)

sys.stdout.write(kyverno_text + "\0" + snippet_text)
PY
}

TEXTS=$(mktemp)
render_texts > "$TEXTS"
KYVERNO_TEXT=$(python3 -c 'import sys; sys.stdout.write(open(sys.argv[1],"rb").read().split(b"\0")[0].decode())' "$TEXTS")
SNIPPET_TEXT=$(python3 -c 'import sys; sys.stdout.write(open(sys.argv[1],"rb").read().split(b"\0")[1].decode())' "$TEXTS")
rm -f "$TEXTS"

splice() { # file -> rendered copy on stdout; fails naming file if markers absent
  local file="$1"
  grep -qF "$BEGIN" "$file" && grep -qF "$END" "$file" || {
    echo "render-verification: $file lacks the ${BEGIN} / ${END} markers" >&2
    return 1
  }
  awk -v begin="$BEGIN" -v end="$END" -v snip="$SNIPPET_TEXT" '
    index($0, begin) { print; print snip; skipping=1; next }
    index($0, end)   { skipping=0 }
    !skipping { print }
  ' "$file"
}

rc=0
# The Kyverno artifact.
KY="$ROOT/$KYVERNO_REL"
if [ "$MODE" = check ]; then
  if [ ! -f "$KY" ] || ! diff -q <(printf '%s\n' "$KYVERNO_TEXT") "$KY" >/dev/null 2>&1; then
    echo "::error file=$KYVERNO_REL::render-verification: $KYVERNO_REL differs from its rendered form (Req 7.9); edit catalogue-policy.yaml and re-run scripts/render-verification.sh"
    rc=1
  fi
else
  # Trailing newline is not cosmetic: yamllint's new-line-at-end-of-file rule
  # is an error in this repo, so an artifact without one fails validate.
  printf '%s\n' "$KYVERNO_TEXT" > "$KY"
fi

# The docs snippets.
for rel in "${TARGET_DOCS[@]}"; do
  file="$ROOT/$rel"
  [ -f "$file" ] || { echo "render-verification: missing target $rel" >&2; exit 1; }
  rendered=$(splice "$file") || exit 1
  if [ "$MODE" = check ]; then
    if ! diff -q <(printf '%s\n' "$rendered") "$file" >/dev/null 2>&1; then
      echo "::error file=$rel::render-verification: $rel snippet differs from its rendered form (Req 7.9); edit catalogue-policy.yaml and re-run scripts/render-verification.sh"
      rc=1
    fi
  else
    printf '%s\n' "$rendered" > "$file"
  fi
done

if [ "$MODE" = check ] && [ "$rc" -ne 0 ]; then exit 1; fi
[ "$MODE" = render ] && echo "render-verification: rendered $KYVERNO_REL and ${#TARGET_DOCS[@]} snippet(s) from catalogue-policy.yaml"
exit 0
