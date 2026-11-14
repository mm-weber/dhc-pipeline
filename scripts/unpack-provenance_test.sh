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

b64_hex() { base64 -d | od -An -vtx1 | tr -d ' \n'; } # stdin base64, stdout the bytes as lowercase hex
short() { jq -c 'walk(if type == "string" and length > 120 then "\(.[0:32])... (\(length) characters)" else . end)'; } # JSON for a detail line

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

# 2: the certificate and the log entry travel as cosign's annotations: the
#    certificate as PEM, the entry as the JSON text cosign reads back, the
#    signature annotation present and empty
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
out=$(run store "$DATA/bundle.jsonl" "$REPO" "$INDEX"); rc=$?
ann=$(manifest_of "$SB/pushed/$TAG" | jq -c '.layers[-1].annotations // {}' 2>/dev/null); [ -n "$ann" ] || ann='{}'
# DER against DER: PEM text may be wrapped one way or another, the bytes are the certificate
want=$(jq -r '.verificationMaterial.certificate.rawBytes' "$DATA/bundle.jsonl" | base64 -d | sha256sum | cut -d' ' -f1)
pem=$(jq -r '."dev.sigstore.cosign/certificate" | strings' <<<"$ann"); got=""
if [ -n "$pem" ]; then got=$(openssl x509 -inform PEM -outform DER <<<"$pem" 2>/dev/null | sha256sum | cut -d' ' -f1) || got="not a PEM certificate"; fi
[ "$got" = "$want" ] \
  && pass "dev.sigstore.cosign/certificate is the bundle's certificate as PEM" \
  || fail "dev.sigstore.cosign/certificate against the bundle's certificate" "sha256 of the annotation's DER '${got:-no such annotation}'" "sha256 of the bundle's rawBytes '$want'" "exit=$rc" "$out"
# logIndex is the entry's own, .verificationMaterial.tlogEntries[0].logIndex. The
# bundle also carries .verificationMaterial.tlogEntries[0].inclusionProof.logIndex,
# a different number (3862518718 versus 3740614456 in the fixture), and the
# signed entry timestamp covers the entry's own.
want=$(jq -S --arg logid "$(jq -r '.verificationMaterial.tlogEntries[0].logId.keyId' "$DATA/bundle.jsonl" | b64_hex)" \
  '{SignedEntryTimestamp: .verificationMaterial.tlogEntries[0].inclusionPromise.signedEntryTimestamp,
    Payload: {body: .verificationMaterial.tlogEntries[0].canonicalizedBody,
              integratedTime: (.verificationMaterial.tlogEntries[0].integratedTime | tonumber),
              logIndex: (.verificationMaterial.tlogEntries[0].logIndex | tonumber),
              logID: $logid}}' "$DATA/bundle.jsonl")
# parsed and key-sorted on both sides: the order of keys is free, the types are not
got=$(jq -r '."dev.sigstore.cosign/bundle" | strings' <<<"$ann" | jq -S . 2>/dev/null)
[ -n "$got" ] && [ "$got" = "$want" ] \
  && pass "dev.sigstore.cosign/bundle is the log entry: timestamp, body, integratedTime, the entry's own logIndex, logID in hex" \
  || fail "dev.sigstore.cosign/bundle against the bundle's log entry" "annotation, parsed: $([ -n "$got" ] && short <<<"$got" || echo "no JSON text there, the annotation is $(jq -c '."dev.sigstore.cosign/bundle"' <<<"$ann" | cut -c1-160) (null: no such annotation)")" "wanted:             $(short <<<"$want")"
sig=$(jq -c '."dev.cosignproject.cosign/signature"' <<<"$ann")
[ "$sig" = '""' ] \
  && pass "dev.cosignproject.cosign/signature is present and empty" \
  || fail "dev.cosignproject.cosign/signature, present and empty" "the annotation as JSON: $sig (null: no such annotation)" 'wanted:                 ""'

# 3: the chain annotation is copied from a layer cosign wrote: Kyverno 1.19.2
#    reads the intermediate certificate from dev.sigstore.cosign/chain and from
#    nowhere else, so the provenance layer carries the very string the layer
#    that was already there carries
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
# the annotation as a JSON string, so that a newline more or less at its end
# shows; nothing when it is absent or empty (null never equals null here)
chain_of() { jq -c "$1"' | .annotations."dev.sigstore.cosign/chain" | strings | select(length > 0)' 2>/dev/null; }
chain_words() { # a chain_of answer for a detail line
  [ -n "$1" ] || { echo "no such annotation, or an empty one"; return; }
  jq -r '"\(length) characters, \(split("-----BEGIN CERTIFICATE-----") | length - 1) certificate(s), ending in \(.[-27:] | tojson)"' <<<"$1"
}
# wanted: what the manifest's own first layer says, the one lay_down wrote
want=$(manifest_of "$SB/registry/$TAG" | chain_of '.layers[0]')
out=$(run store "$DATA/bundle.jsonl" "$REPO" "$INDEX"); rc=$?
# the last layer pushed, never the first: with no layer added there is nothing to read
got=$(manifest_of "$SB/pushed/$TAG" | chain_of '.layers[1:][-1]')
[ -n "$want" ] && [ -n "$got" ] && [ "$got" = "$want" ] \
  && pass "dev.sigstore.cosign/chain on the provenance layer is the string cosign's layer carries, character for character" \
  || fail "dev.sigstore.cosign/chain on the provenance layer against the layer that was already there" "on the provenance layer: $(chain_words "$got")" "on cosign's layer:       $(chain_words "$want")" "exit=$rc" "$out"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all unpack-provenance tests passed"
