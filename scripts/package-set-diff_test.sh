#!/usr/bin/env bash
# Tests for scripts/package-set-diff.sh: the publish-on-change comparator
# (task 9.2, Req 2.15-2.17).
#
# What this suite pins is the projection, the verdicts and the refusals, not
# the registry: docker and cosign are stubbed, and the fixture SBOMs are
# trimmed copies of the real shapes measured on 2026-09-01 against the first
# 9.1 release (syft 1.51.1 CycloneDX, apk pull checksum in the
# syft:metadata:pullChecksum property, byte-unstable ordering and package-id
# qualifiers across runs).
#
# The one rule under test: equality is the only thing that suppresses a
# publish, so equality must be PROVEN. Anything unprovable (no tag, no
# attestation, mismatched platforms) is `different`; a broken LOCAL SBOM or
# a tool missing from PATH refuses outright, because that means our own
# build or environment is broken, and a broken environment must neither
# publish nor discard (case 9b, measured 2026-09-08).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PSD="$HERE/package-set-diff.sh"
FAILURES=0

pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

REF="ghcr.io/mm-weber/dhc/hardened-app:0.1.0-alpine3.23"
AMD64_DIGEST="sha256:1851851851851851851851851851851851851851851851851851851851851851"

# DSSE envelope the way `cosign verify-attestation` prints one per line:
# {"payload": base64(in-toto statement)}. Built with python3 so the base64 is
# real, not hand-rolled.
dsse() { # <predicateType> <predicate-json-file>
  python3 - "$1" "$2" <<'PY'
import base64, json, sys
stmt = {"_type": "https://in-toto.io/Statement/v0.1",
        "predicateType": sys.argv[1],
        "predicate": json.load(open(sys.argv[2]))}
print(json.dumps({"payload": base64.b64encode(json.dumps(stmt).encode()).decode(),
                  "payloadType": "application/vnd.in-toto+json", "signatures": []}))
PY
}

# A CycloneDX document from a component list, wrapped in the metadata noise a
# real syft run carries. $1 = file, remaining args = component JSON strings.
cdx() {
  local out="$1"; shift
  python3 - "$out" "$@" <<'PY'
import json, sys
comps = [json.loads(a) for a in sys.argv[2:]]
doc = {"bomFormat": "CycloneDX", "specVersion": "1.6",
       "metadata": {"tools": {"components": [{"name": "syft"}]}},
       "components": comps}
json.dump(doc, open(sys.argv[1], "w"))
PY
}

APK_A='{"type":"library","name":"alpine-baselayout-data","version":"3.7.2-r0","purl":"pkg:apk/alpine/alpine-baselayout-data@3.7.2-r0?arch=noarch&distro=alpine-3.23","properties":[{"name":"syft:metadata:pullChecksum","value":"Q1HFMCq7X14VXlXAlzhokUfyovrGM="}]}'
APK_A_NEWCHECKSUM='{"type":"library","name":"alpine-baselayout-data","version":"3.7.2-r0","purl":"pkg:apk/alpine/alpine-baselayout-data@3.7.2-r0?arch=noarch&distro=alpine-3.23","properties":[{"name":"syft:metadata:pullChecksum","value":"Q1REPUBLISHEDREPUBLISHEDXXXXX="}]}'
APK_A_NEWVERSION='{"type":"library","name":"alpine-baselayout-data","version":"3.7.3-r0","purl":"pkg:apk/alpine/alpine-baselayout-data@3.7.3-r0?arch=noarch&distro=alpine-3.23","properties":[{"name":"syft:metadata:pullChecksum","value":"Q1SOMETHINGELSEENTIRELYYYYYYY="}]}'
GO_STD='{"type":"library","name":"stdlib","version":"go1.27.0","purl":"pkg:golang/stdlib@1.27.0"}'
# Never part of the package set: a file (no purl) and the OS component.
FILE_C='{"type":"file","name":"/etc/hosts"}'
OS_C='{"type":"operating-system","name":"alpine","version":"3.23.1"}'
# Byte instability the projection must shrug off: same package, different
# qualifier order, a package-id, extra properties.
APK_A_NOISY='{"type":"library","name":"alpine-baselayout-data","version":"3.7.2-r0","purl":"pkg:apk/alpine/alpine-baselayout-data@3.7.2-r0?distro=alpine-3.23&arch=noarch","properties":[{"name":"syft:cpe23","value":"cpe:2.3:a:x:x:*"},{"name":"syft:metadata:pullChecksum","value":"Q1HFMCq7X14VXlXAlzhokUfyovrGM="}]}'

fresh() { # sandbox with stub docker + cosign and a published amd64 manifest
  SB=$(mktemp -d)
  mkdir -p "$SB/bin" "$SB/att"

  # The published index, the shape `imagetools inspect --raw` prints: one
  # amd64 platform manifest, one BuildKit attestation manifest that MUST be
  # excluded (unknown/unknown + the reference-type annotation).
  cat > "$SB/index.json" <<EOF
{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[
 {"mediaType":"application/vnd.oci.image.manifest.v1+json","digest":"${AMD64_DIGEST}","size":1,"platform":{"architecture":"amd64","os":"linux"}},
 {"mediaType":"application/vnd.oci.image.manifest.v1+json","digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size":1,"platform":{"architecture":"unknown","os":"unknown"},"annotations":{"vnd.docker.reference.type":"attestation-manifest"}}]}
EOF

  cat > "$SB/bin/docker" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "docker $*" >> "${STUB_ARGV}"
if [ "$1 $2 $3 $4" = "buildx imagetools inspect --raw" ]; then
  [ -n "${STUB_NO_TAG:-}" ] && { echo "no such manifest: $5" >&2; exit 1; }
  cat "${STUB_INDEX}"
  exit 0
fi
echo "docker stub: unexpected args $*" >&2; exit 64
STUB

  # cosign is asked to VERIFY, never to download (review D2, Req 6.58's
  # discipline applied to the comparator): the stub answers only when the
  # issuer and identity match what it was told the bundle was signed with,
  # which is what the real tool does against Fulcio's certificate.
  cat > "$SB/bin/cosign" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "cosign $*" >> "${STUB_ARGV}"
if [ "$1" = "verify-attestation" ]; then
  type=""; issuer=""; identity=""; ref=""
  while [ $# -gt 1 ]; do shift
    case "$1" in
      --type) type="$2"; shift ;;
      --certificate-oidc-issuer) issuer="$2"; shift ;;
      --certificate-identity) identity="$2"; shift ;;
      *) ref="$1" ;;
    esac
  done
  [ "$type" = cyclonedx ] || { echo "stub: unexpected --type $type" >&2; exit 64; }
  if [ "$issuer" != "${STUB_ISSUER}" ] || [ "$identity" != "${STUB_IDENTITY}" ]; then
    echo "Error: no matching attestations: none of the signatures were made by ${identity}" >&2; exit 1
  fi
  digest="${ref##*@}"
  f="${STUB_ATT_DIR}/${digest#sha256:}.jsonl"
  [ -f "$f" ] || { echo "Error: no attestations for $ref" >&2; exit 1; }
  cat "$f"
  exit 0
fi
echo "cosign stub: unexpected args $*" >&2; exit 64
STUB
  chmod +x "$SB/bin/docker" "$SB/bin/cosign"
  # The policy file the comparator reads the admitted identities from: the
  # releaser attests cyclonedx, the re-attester does not.
  cat > "$SB/catalogue-policy.yaml" <<'EOF'
verification:
  issuer: https://issuer.example/oidc
  roles:
    releaser:
      identity: https://github.com/acme/repo/.github/workflows/build.yml@refs/heads/main
      attests: [spdxjson, cyclonedx, vuln, openvex]
    re-attester:
      identity: https://github.com/acme/repo/.github/workflows/rescan.yml@refs/heads/main
      attests: [openvex, vuln]
EOF
  export STUB_ARGV="$SB/argv" STUB_INDEX="$SB/index.json" STUB_ATT_DIR="$SB/att" \
         STUB_ISSUER="https://issuer.example/oidc" \
         STUB_IDENTITY="https://github.com/acme/repo/.github/workflows/build.yml@refs/heads/main" \
         PACKAGE_SET_DIFF_ROOT="$SB"
  unset STUB_NO_TAG
  : > "$SB/argv"

  # Published side: the CycloneDX predicate travels in a bundle beside the
  # other predicate types, and the script must pick it out (real bundles
  # carry spdx, openvex and vuln too).
  cdx "$SB/pub.cdx.json" "$APK_A" "$GO_STD" "$FILE_C" "$OS_C"
  { dsse "https://spdx.dev/Document" <(echo '{"spdxVersion":"SPDX-2.3"}')
    dsse "https://cyclonedx.org/bom" "$SB/pub.cdx.json"
  } > "$SB/att/${AMD64_DIGEST#sha256:}.jsonl"

  # Local side: same packages, noisier bytes, different order.
  cdx "$SB/loc.cdx.json" "$GO_STD" "$APK_A_NOISY" "$OS_C" "$FILE_C"
}

run() { # <local-index-digest> then platform=file pairs
  local d="$1"; shift
  PATH="$SB/bin:$PATH" "$PSD" hardened-app "$REF" "$d" "$SB/verdict" "$@" 2>&1
}
verdict() { grep -E "^$1=" "$SB/verdict" | tail -1; }

# 1: same content through different bytes is EQUAL, and the projection is
#    what the requirement names: type+name+version via the purl base, plus
#    the pull checksum; files and the OS component stay out of it.
fresh
out=$(run sha256:feedfeed "linux/amd64=$SB/loc.cdx.json"); rc=$?
[ "$rc" -eq 0 ] && pass "equal sets exit 0" || fail "equal sets exit 0" "$out"
[ "$(verdict verdict)" = "verdict=equal" ] && pass "verdict equal" || fail "verdict equal" "$(cat "$SB/verdict")" "$out"
grep -q "pkg:apk/alpine/alpine-baselayout-data@3.7.2-r0" <<<"$out" \
  && pass "the set is printed for the summary" || fail "the set is printed for the summary" "$out"

# 2: equal sets still measure reproducibility: the rebuilt index digest is
#    compared against the published one and reported, never gated on.
pubdigest="sha256:$(sha256sum "$SB/index.json" | cut -d' ' -f1)"
fresh
out=$(run "$pubdigest" "linux/amd64=$SB/loc.cdx.json")
[ "$(verdict digest_equal)" = "digest_equal=true" ] && pass "reproducible rebuild measured true" \
  || fail "reproducible rebuild measured true" "$(cat "$SB/verdict")"
fresh
out=$(run sha256:feedfeed "linux/amd64=$SB/loc.cdx.json")
[ "$(verdict digest_equal)" = "digest_equal=false" ] && pass "unreproducible rebuild measured false" \
  || fail "unreproducible rebuild measured false" "$(cat "$SB/verdict")"
fresh
out=$(run - "linux/amd64=$SB/loc.cdx.json")
[ "$(verdict digest_equal)" = "digest_equal=unmeasured" ] && pass "no local digest stays unmeasured" \
  || fail "no local digest stays unmeasured" "$(cat "$SB/verdict")"

# 3: a version bump is different, and the diff names both sides.
fresh
cdx "$SB/loc.cdx.json" "$APK_A_NEWVERSION" "$GO_STD"
out=$(run - "linux/amd64=$SB/loc.cdx.json"); rc=$?
[ "$rc" -eq 0 ] && pass "different sets still exit 0 (the workflow decides)" || fail "different sets still exit 0 (the workflow decides)" "$out"
[ "$(verdict verdict)" = "verdict=different" ] && pass "verdict different on version bump" || fail "verdict different on version bump" "$(cat "$SB/verdict")"
grep -q "3.7.2-r0" <<<"$out" && grep -q "3.7.3-r0" <<<"$out" \
  && pass "diff shows the old and the new version" || fail "diff shows the old and the new version" "$out"

# 4: a republished package, same version and new checksum, is different —
#    the CVE-2026-33634 shape, and the whole reason the checksum is in the set.
fresh
cdx "$SB/loc.cdx.json" "$APK_A_NEWCHECKSUM" "$GO_STD"
run - "linux/amd64=$SB/loc.cdx.json" >/dev/null
[ "$(verdict verdict)" = "verdict=different" ] && pass "checksum-only change is different" \
  || fail "checksum-only change is different" "$(cat "$SB/verdict")"

# 5: no published digest under the tag: nothing to be equal to, so publish.
fresh
export STUB_NO_TAG=1
out=$(run - "linux/amd64=$SB/loc.cdx.json"); rc=$?
[ "$rc" -eq 0 ] && [ "$(verdict verdict)" = "verdict=different" ] \
  && pass "missing tag is different, not an error" || fail "missing tag is different, not an error" "rc=$rc" "$(cat "$SB/verdict" 2>/dev/null)"
[ "$(verdict reason)" = "reason=no-published-digest" ] && pass "and says why" || fail "and says why" "$(cat "$SB/verdict")"

# 6: a published digest whose bundle has no CycloneDX attestation cannot
#    prove equality: different, naming the platform.
fresh
dsse "https://spdx.dev/Document" <(echo '{"spdxVersion":"SPDX-2.3"}') > "$SB/att/${AMD64_DIGEST#sha256:}.jsonl"
out=$(run - "linux/amd64=$SB/loc.cdx.json")
[ "$(verdict verdict)" = "verdict=different" ] && [ "$(verdict reason)" = "reason=attestation-unreadable" ] \
  && pass "missing cyclonedx attestation is different" || fail "missing cyclonedx attestation is different" "$(cat "$SB/verdict")" "$out"
grep -q "linux/amd64" <<<"$out" && pass "naming the platform" || fail "naming the platform" "$out"

# 7: so does a bundle cosign cannot fetch at all.
fresh
rm "$SB/att/${AMD64_DIGEST#sha256:}.jsonl"
out=$(run - "linux/amd64=$SB/loc.cdx.json")
[ "$(verdict verdict)" = "verdict=different" ] && [ "$(verdict reason)" = "reason=attestation-unreadable" ] \
  && pass "unfetchable attestation is different" || fail "unfetchable attestation is different" "$(cat "$SB/verdict")"

# 7b (review D2): a CycloneDX attestation signed by an identity the policy
#     does not admit is not read at all. Before this the comparator used
#     `cosign download attestation`, so anyone able to push an attestation
#     under the repository could make the nightly discard a rebuild.
fresh
export STUB_IDENTITY="https://github.com/someone-else/repo/.github/workflows/build.yml@refs/heads/main"
out=$(run - "linux/amd64=$SB/loc.cdx.json")
[ "$(verdict verdict)" = "verdict=different" ] && [ "$(verdict reason)" = "reason=attestation-unreadable" ] \
  && pass "an attestation from a non-admitted identity is different, not equal" || fail "an attestation from a non-admitted identity is different, not equal" "$(cat "$SB/verdict")" "$out"
grep -qi "admitted" <<<"$out" && pass "and the reason names the admission" || fail "and the reason names the admission" "$out"
grep -q "cosign download" "$SB/argv" && fail "cosign is never asked to download" "$(cat "$SB/argv")" || pass "cosign is never asked to download"

# 7c: a policy file naming no issuer or no role that attests cyclonedx is a
#     refusal (exit 2), never a verdict: without admitted identities nothing
#     can be verified, so nothing can be proven equal.
fresh
printf 'verification:\n  issuer: https://issuer.example/oidc\n  roles:\n    releaser:\n      identity: https://github.com/acme/repo/.github/workflows/build.yml@refs/heads/main\n      attests: [spdxjson, openvex]\n' > "$SB/catalogue-policy.yaml"
out=$(run - "linux/amd64=$SB/loc.cdx.json"); rc=$?
[ "$rc" -eq 2 ] && grep -q "cyclonedx" <<<"$out" && pass "no admitted cyclonedx identity is a refusal naming it" || fail "no admitted cyclonedx identity is a refusal naming it" "rc=$rc" "$out"

# 8: platform sets must match exactly, both directions.
fresh
out=$(run - "linux/amd64=$SB/loc.cdx.json" "linux/arm64=$SB/loc.cdx.json")
[ "$(verdict verdict)" = "verdict=different" ] && [ "$(verdict reason)" = "reason=platform-set-differs" ] \
  && pass "local platform the index lacks is different" || fail "local platform the index lacks is different" "$(cat "$SB/verdict")" "$out"
fresh
out=$(run -)  # published has amd64, local brings nothing
rc=$?
[ "$rc" -eq 2 ] && pass "no local platform at all is a usage refusal" || fail "no local platform at all is a usage refusal" "rc=$rc" "$out"

# 9: a malformed LOCAL SBOM is OUR build lying: hard refusal, no verdict.
fresh
echo '{ not json' > "$SB/loc.cdx.json"
out=$(run - "linux/amd64=$SB/loc.cdx.json"); rc=$?
[ "$rc" -eq 2 ] && pass "malformed local sbom refuses with exit 2" || fail "malformed local sbom refuses with exit 2" "rc=$rc" "$out"
[ ! -s "$SB/verdict" ] || ! grep -q "^verdict=" "$SB/verdict" \
  && pass "and writes no verdict" || fail "and writes no verdict" "$(cat "$SB/verdict")"

# 9b: a tool the comparator needs that is not on PATH is OUR environment
# broken, not an unreadable attestation: hard refusal, no verdict. Measured
# 2026-09-08: build.yml installed cosign only in the release part, after the
# comparator, and the runner image ships none, so every nightly rebuild from
# 2026-09-02 read its own missing binary as `attestation-unreadable` and
# published every definition every night (28 needless digests by 09-08).
for tool in cosign docker; do
  fresh
  rm "$SB/bin/$tool"
  # A PATH holding only the sandbox stubs plus the coreutils and jq the script
  # itself needs, linked into a second directory, so the real tool installed
  # on this machine cannot answer for the one the sandbox lacks.
  mkdir -p "$SB/essentials"
  for e in bash env jq sort sed awk cut grep cat mktemp rm mkdir sha256sum paste cmp tr head comm diff basename dirname printf; do
    src=$(command -v "$e" 2>/dev/null) && ln -sf "$src" "$SB/essentials/$e"
  done
  out=$(PATH="$SB/bin:$SB/essentials" "$PSD" hardened-app "$REF" - "$SB/verdict" "linux/amd64=$SB/loc.cdx.json" 2>&1); rc=$?
  [ "$rc" -eq 2 ] && pass "missing $tool refuses with exit 2" || fail "missing $tool refuses with exit 2" "rc=$rc" "$out"
  grep -q "package-set-diff: $tool is not on PATH" <<<"$out" && pass "missing $tool is named" || fail "missing $tool is named" "$out"
  [ ! -s "$SB/verdict" ] || ! grep -q "^verdict=" "$SB/verdict" \
    && pass "missing $tool writes no verdict" || fail "missing $tool writes no verdict" "$(cat "$SB/verdict")"
done

# 10: the invocations are the ones the design names: the raw index by tag
#     ref, the attestation bundle by repo@manifest-digest.
fresh
run - "linux/amd64=$SB/loc.cdx.json" >/dev/null
grep -qF "docker buildx imagetools inspect --raw $REF" "$SB/argv" \
  && pass "resolves the published index by ref" || fail "resolves the published index by ref" "$(cat "$SB/argv")"
grep -qF "cosign verify-attestation --type cyclonedx --certificate-oidc-issuer https://issuer.example/oidc --certificate-identity https://github.com/acme/repo/.github/workflows/build.yml@refs/heads/main ghcr.io/mm-weber/dhc/hardened-app@${AMD64_DIGEST}" "$SB/argv" \
  && pass "verifies the attestation by manifest digest against the admitted identity" || fail "verifies the attestation by manifest digest against the admitted identity" "$(cat "$SB/argv")"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all package-set-diff tests passed"
