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

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all render-verification tests passed"
