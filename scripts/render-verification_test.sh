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

# 2: role separation in the artifact: the SPDX attestation block admits only
#    the releaser; the rescan identity appears only for openvex
spdx_block=$(awk '/spdx.dev\/Document/{f=1} f{print} f&&/openvex.dev\/ns/{exit}' "$POL")
if grep -qF "rescan.yml" <<<"$spdx_block"; then
  fail "spdx attestor block excludes the re-attester" "$spdx_block"
else
  pass "spdx attestor block excludes the re-attester"
fi

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
  grep -qF "intro" "$doc" >/dev/null 2>&1 || true
done
grep -qF "intro" "$SB/README.md" && pass "text outside markers untouched" || fail "text outside markers untouched"

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

# 7: --check names a tampered snippet and fails
sed -i 's/--type openvex/--type tampered/' "$SB/README.md"
out=$("$RENDER" --check "$SB" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && grep -qF "README.md" <<<"$out"; then
  pass "--check fails naming the drifted README snippet"
else
  fail "--check fails naming the drifted README snippet" "exit=$rc" "$out"
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

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all render-verification tests passed"
