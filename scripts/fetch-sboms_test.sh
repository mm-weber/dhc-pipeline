#!/usr/bin/env bash
# Tests for scripts/fetch-sboms.sh: the supported set's CycloneDX SBOMs are read
# only through cosign verify-attestation against the roles that attest them
# (Req 6.58), one file per platform manifest, superseded rows untouched, a
# manifest without one named and skipped (task 10.6). cosign is stubbed.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FETCH="$HERE/fetch-sboms.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

BUILD_ID="https://github.com/acme/dhc/.github/workflows/build.yml@refs/heads/main"
RESCAN_ID="https://github.com/acme/dhc/.github/workflows/rescan.yml@refs/heads/main"
M1="sha256:1111111111111111111111111111111111111111111111111111111111111111"
M2="sha256:2222222222222222222222222222222222222222222222222222222222222222"
M3="sha256:3333333333333333333333333333333333333333333333333333333333333333"
INDEX="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
OLD="sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

fresh() {
  SB=$(mktemp -d); mkdir -p "$SB/root" "$SB/bin" "$SB/out"
  cat > "$SB/root/catalogue-policy.yaml" <<EOF2
verification:
  issuer: https://token.actions.githubusercontent.com
  roles:
    releaser:
      identity: $BUILD_ID
      attests: [spdxjson, cyclonedx, vuln, openvex]
    re-attester:
      identity: $RESCAN_ID
      attests: [openvex, vuln]
EOF2
  printf 'ghcr.io/acme/dhc/grafana\t13.1.5-alpine3.23\t%s\tlinux/amd64\t%s\tsupported\n' "$INDEX" "$M1" > "$SB/enum.tsv"
  printf 'ghcr.io/acme/dhc/grafana\t13-alpine3.23\t%s\tlinux/amd64\t%s\tsupported\n' "$INDEX" "$M1" >> "$SB/enum.tsv"
  printf 'ghcr.io/acme/dhc/grafana\t13.1.5-alpine3.23\t%s\tlinux/arm64\t%s\tsupported\n' "$INDEX" "$M2" >> "$SB/enum.tsv"
  printf 'ghcr.io/acme/dhc/grafana\t13.1.2-alpine3.23\t%s\tlinux/amd64\t%s\tsuperseded\n' "$OLD" "$M3" >> "$SB/enum.tsv"
  # one DSSE envelope whose payload is an in-toto statement carrying a CycloneDX predicate
  payload=$(printf '{"_type":"https://in-toto.io/Statement/v0.1","predicateType":"https://cyclonedx.org/bom","subject":[{"name":"ghcr.io/acme/dhc/grafana"}],"predicate":{"bomFormat":"CycloneDX","components":[{"name":"stdlib","version":"go1.26.4","purl":"pkg:golang/stdlib@1.26.4"}]}}' | base64 -w0)
  printf '{"payloadType":"application/vnd.in-toto+json","payload":"%s","signatures":[]}\n' "$payload" > "$SB/envelope.jsonl"
  cat > "$SB/bin/cosign" <<'STUB'
#!/usr/bin/env bash
printf 'cosign %s\n' "$*" >> "${STUB_ARGV}"
[ "$1" = "verify-attestation" ] || { echo "stub: unexpected $1" >&2; exit 2; }
ref="${@: -1}"; id=""
while [ $# -gt 0 ]; do case "$1" in --certificate-identity) id="$2"; shift ;; esac; shift; done
case "$id|$ref" in
  *build.yml*"|"*1111*) cat "${STUB_DIR}/envelope.jsonl"; exit 0 ;;
  *) echo "Error: no matching attestations" >&2; exit 1 ;;
esac
STUB
  chmod +x "$SB/bin/cosign"
  export STUB_ARGV="$SB/argv" STUB_DIR="$SB"; : > "$STUB_ARGV"
}
run() { PATH="$SB/bin:$PATH" "$FETCH" "$SB/root" "$SB/enum.tsv" "$SB/out" 2>&1; }

# 1: the supported manifest's SBOM is read through verification with the role that attests cyclonedx
fresh
out=$(run); rc=$?
[ "$rc" -eq 0 ] && pass "a missing SBOM on one manifest is not a failure of the run" || fail "rc=$rc" "$out"
grep -q "cosign verify-attestation --type cyclonedx --certificate-oidc-issuer https://token.actions.githubusercontent.com --certificate-identity ${BUILD_ID} ghcr.io/acme/dhc/grafana@${M1}" "$STUB_ARGV" \
  && pass "verify-attestation --type cyclonedx against the releaser identity (Req 6.58)" || fail "verify call" "$(cat "$STUB_ARGV")"
! grep -q "certificate-identity ${RESCAN_ID}" "$STUB_ARGV" && pass "a role that does not attest cyclonedx is not asked" || fail "re-attester asked" "$(cat "$STUB_ARGV")"
[ "$(jq -r '.components[0].version' "$SB/out/sha256-${M1#sha256:}.cdx.json" 2>/dev/null)" = "go1.26.4" ] \
  && pass "the bare CycloneDX predicate is written under the manifest's digest" || fail "output file" "$(ls "$SB/out")"
[ "$(grep -c "grafana@${M1}" "$STUB_ARGV")" -eq 1 ] && pass "a manifest listed under two tags is read once" || fail "dedup" "$(cat "$STUB_ARGV")"

# 2: a manifest without a verifiable SBOM is named as a warning, and nothing is written for it
[ ! -e "$SB/out/sha256-${M2#sha256:}.cdx.json" ] && pass "no file for a manifest without a verifiable SBOM" || fail "invented SBOM" "$(ls "$SB/out")"
grep -q "::warning::fetch-sboms: no verifiable CycloneDX SBOM on ghcr.io/acme/dhc/grafana@${M2} (linux/arm64): Error: no matching attestations" <<<"$out" \
  && pass "the miss is named with cosign's last line" || fail "warning" "$out"
grep -q "fetch-sboms: 1 of 2 supported platform manifest(s) read through verification, 1 without" <<<"$out" && pass "counted in the summary line" || fail "summary" "$out"

# 3: superseded rows are not read
! grep -q "$M3" "$STUB_ARGV" && pass "a superseded manifest is not read: it holds no issues" || fail "superseded read" "$(cat "$STUB_ARGV")"

# 4: a policy without a cyclonedx-attesting role refuses by name
fresh
printf 'verification:\n  issuer: https://token.actions.githubusercontent.com\n  roles:\n    re-attester:\n      identity: %s\n      attests: [openvex]\n' "$RESCAN_ID" > "$SB/root/catalogue-policy.yaml"
out=$(run); rc=$?
[ "$rc" -eq 2 ] && grep -q "no role that attests cyclonedx" <<<"$out" && pass "no attesting role: refused by name (exit 2)" || fail "policy hole" "rc=$rc" "$out"

# 5: the loop reads the enumeration on stdin; a cosign that drains stdin (measured
#    with a stub on 2026-09-05) must not eat the rows behind the first one
fresh
sed -i '2a cat >/dev/null' "$SB/bin/cosign"
out=$(run); rc=$?
[ "$(grep -c 'cosign verify-attestation' "$STUB_ARGV")" -eq 2 ] && pass "every supported manifest is still visited when cosign drains stdin" || fail "rows eaten" "$(cat "$STUB_ARGV")" "$out"

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES test(s) failed"; exit 1; fi
echo "all fetch-sboms tests passed"
