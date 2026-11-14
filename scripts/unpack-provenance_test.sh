#!/usr/bin/env bash
# Tests for scripts/unpack-provenance.sh: GitHub's provenance bundle (written
# by actions/attest-build-provenance) is stored as one more layer of the
# attestation manifest cosign keeps beside an image digest, at the tag
# sha256-<hex>.att (Req 2.27). Nothing is signed here: the layer's blob is the
# envelope the transparency log recorded, byte for byte. crane is stubbed, a
# directory stands in for the registry; the bundle and the chain are the real
# ones of the measuring run of 2026-11-13 (scripts/testdata/provenance).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
UNPACK="$HERE/unpack-provenance.sh"
DATA="$HERE/testdata/provenance"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

# the repository and the index digest the fixture's statement names
REPO="ghcr.io/mm-weber/slsa-spike"
INDEX="sha256:c47ac86f0e7100538371e5836d2608bbb9abec15c5589d5bbc34bc9cad3619b2"
att_tag() { printf 'sha256-%s.att' "${1#sha256:}"; } # cosign's attestation tag for a digest

fresh() {
  SB=$(mktemp -d); mkdir -p "$SB/bin" "$SB/registry" "$SB/pushed"; : > "$SB/crane.log"
  # crane as a directory: pull copies the layout laid down for the tag, push
  # keeps the layout it was given, every call is logged
  cat > "$SB/bin/crane" <<'STUB'
#!/usr/bin/env bash
SB="$(cd "$(dirname "$0")/.." && pwd)"
printf 'crane %s\n' "$*" >> "$SB/crane.log"
case "$1" in
  pull) # crane pull --format oci <ref> <dir>
    ref="${*: -2:1}"; dir="${*: -1}"; tag="${ref##*:}"
    if [ ! -d "$SB/registry/$tag" ]; then
      echo "Error: GET https://${ref%%/*}/v2/.../manifests/$tag: MANIFEST_UNKNOWN: manifest unknown" >&2; exit 1
    fi
    mkdir -p "$dir" && cp -R "$SB/registry/$tag/." "$dir/" ;;
  push) # crane push <dir> <ref>
    dir="${*: -2:1}"; ref="${*: -1}"; tag="${ref##*:}"
    rm -rf "$SB/pushed/$tag"; mkdir -p "$SB/pushed/$tag" && cp -R "$dir/." "$SB/pushed/$tag/" ;;
  *) echo "stub: unexpected $1" >&2; exit 2 ;;
esac
STUB
  chmod +x "$SB/bin/crane"
}

put_blob() { # layout: stdin becomes a blob named by its sha256; prints "<hex> <size>"
  local dir="$1/blobs/sha256" tmp hex
  mkdir -p "$dir"; tmp=$(mktemp "$dir/tmp.XXXXXX"); cat > "$tmp"
  hex=$(sha256sum < "$tmp" | cut -d' ' -f1); mv "$tmp" "$dir/$hex"
  printf '%s %s\n' "$hex" "$(wc -c < "$dir/$hex")"
}

lay_down() { # tag: the attestation manifest cosign keeps there, in the shape crane 0.22.1 pulls it
  local dir="$SB/registry/$1" payload lhex lsize chex csize mhex msize
  mkdir -p "$dir"
  # one cosign-shaped layer: a small DSSE envelope, the chain in its annotation
  payload=$(printf '{"_type":"https://in-toto.io/Statement/v0.1","predicateType":"https://spdx.dev/Document","subject":[],"predicate":{}}' | base64 -w0)
  read -r lhex lsize < <(printf '{"payload":"%s","payloadType":"application/vnd.in-toto+json","signatures":[{"sig":""}]}' "$payload" | put_blob "$dir")
  # the config: the layers' digests in order, one history entry per layer
  read -r chex csize < <(jq -nc --arg layer "sha256:$lhex" \
    '{architecture:"",created:"0001-01-01T00:00:00Z",history:[{created:"0001-01-01T00:00:00Z"}],os:"",rootfs:{type:"layers",diff_ids:[$layer]},config:{}}' | put_blob "$dir")
  read -r mhex msize < <(jq -nc --rawfile chain "$DATA/chain.pem" \
    --arg config "sha256:$chex" --argjson csize "$csize" --arg layer "sha256:$lhex" --argjson lsize "$lsize" \
    '{schemaVersion:2,mediaType:"application/vnd.oci.image.manifest.v1+json",
      config:{mediaType:"application/vnd.oci.image.config.v1+json",size:$csize,digest:$config},
      layers:[{mediaType:"application/vnd.dsse.envelope.v1+json",size:$lsize,digest:$layer,
        annotations:{predicateType:"https://spdx.dev/Document","dev.cosignproject.cosign/signature":"","dev.sigstore.cosign/chain":$chain}}]}' | put_blob "$dir")
  jq -nc --arg manifest "sha256:$mhex" --argjson msize "$msize" \
    '{schemaVersion:2,mediaType:"application/vnd.oci.image.index.v1+json",
      manifests:[{mediaType:"application/vnd.oci.image.manifest.v1+json",size:$msize,digest:$manifest,artifactType:"application/vnd.oci.image.config.v1+json"}]}' > "$dir/index.json"
  printf '{"imageLayoutVersion": "1.0.0"}' > "$dir/oci-layout"
}

manifest_of() { # layout: its manifest, found the real way: index.json names the blob
  local d; d=$(jq -r '.manifests[0].digest' "$1/index.json" 2>/dev/null) || return 1
  cat "$1/blobs/sha256/${d#sha256:}" 2>/dev/null
}

run() { PATH="$SB/bin:$PATH" UNPACK_PROVENANCE_RETRY_DELAY=0 "$UNPACK" "$@" 2>&1; }

# 1: the provenance becomes one more layer, the envelope byte for byte: its
#    sha256 is the envelopeHash the bundle's log entry carries
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
before=$(manifest_of "$SB/registry/$TAG" | jq '.layers | length')
want=$(jq -r '.verificationMaterial.tlogEntries[0].canonicalizedBody' "$DATA/bundle.jsonl" | base64 -d | jq -r '.spec.envelopeHash.value')
out=$(run store "$DATA/bundle.jsonl" "$REPO" "$INDEX"); rc=$?
pushed="$SB/pushed/$TAG"; manifest=$(manifest_of "$pushed")
after=$(jq '.layers | length' <<<"$manifest")
[ "$rc" -eq 0 ] && [ "$after" = "$((before + 1))" ] \
  && pass "store exits 0 and the manifest pushed to the .att tag has one layer more" \
  || fail "one layer more at $TAG" "exit=$rc, wanted 0" "layers pushed: ${after:-none, nothing was pushed to the tag}, wanted $((before + 1))" "crane calls: $(cat "$SB/crane.log")" "$out"
type=$(jq -r '.layers[-1].mediaType' <<<"$manifest"); predicate=$(jq -r '.layers[-1].annotations.predicateType' <<<"$manifest")
[ "$type" = "application/vnd.dsse.envelope.v1+json" ] && [ "$predicate" = "https://slsa.dev/provenance/v1" ] \
  && pass "the new layer is a DSSE envelope annotated as SLSA provenance v1" \
  || fail "the new layer's media type and predicateType" "mediaType '$type', wanted 'application/vnd.dsse.envelope.v1+json'" "predicateType '$predicate', wanted 'https://slsa.dev/provenance/v1'"
hex=$(jq -r '.layers[-1].digest' <<<"$manifest"); hex=${hex#sha256:}
sum=""; [ -n "$hex" ] && [ -f "$pushed/blobs/sha256/$hex" ] && sum=$(sha256sum < "$pushed/blobs/sha256/$hex" | cut -d' ' -f1)
[ -n "$sum" ] && [ "$sum" = "$hex" ] && [ "$hex" = "$want" ] \
  && pass "the layer's blob is the envelope the log recorded: its sha256 is its name and the entry's envelopeHash" \
  || fail "the layer's blob against the log entry's envelopeHash" "layer digest '$hex'" "sha256 of the blob in the pushed layout '${sum:-no such blob}'" "envelopeHash  '$want'"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all unpack-provenance tests passed"
