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
  # keeps the layout it was given, every call is logged. A case that wants
  # pushes to fail writes their number to $SB/push-failures: while it is above
  # 0 a push fails the way crane does (a line on stderr, exit 1), keeps nothing
  # and counts it down by one; with no such file no push fails
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
    left=0; [ -f "$SB/push-failures" ] && left=$(cat "$SB/push-failures")
    if [ "$left" -gt 0 ]; then
      echo "$((left - 1))" > "$SB/push-failures"
      echo "Error: PUT https://${ref%%/*}/v2/.../manifests/$tag: unexpected status code 503 Service Unavailable" >&2; exit 1
    fi
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

lay_down() { # tag [predicateType...]: the attestation manifest cosign keeps there, in the shape crane 0.22.1 pulls it
  local dir="$SB/registry/$1" type payload lhex lsize chex csize mhex msize layers='[]'
  shift; [ $# -gt 0 ] || set -- "https://spdx.dev/Document" # no type given: the one SBOM layer
  mkdir -p "$dir"
  # one cosign-shaped layer per predicate type: a small DSSE envelope whose
  # statement names the type (so every layer is a blob of its own), the chain
  # in its annotation
  for type in "$@"; do
    payload=$(printf '{"_type":"https://in-toto.io/Statement/v0.1","predicateType":"%s","subject":[],"predicate":{}}' "$type" | base64 -w0)
    read -r lhex lsize < <(printf '{"payload":"%s","payloadType":"application/vnd.in-toto+json","signatures":[{"sig":""}]}' "$payload" | put_blob "$dir")
    layers=$(jq -c --rawfile chain "$DATA/chain.pem" --arg type "$type" --arg layer "sha256:$lhex" --argjson lsize "$lsize" \
      '. + [{mediaType:"application/vnd.dsse.envelope.v1+json",size:$lsize,digest:$layer,
        annotations:{predicateType:$type,"dev.cosignproject.cosign/signature":"","dev.sigstore.cosign/chain":$chain}}]' <<<"$layers")
  done
  # the config: the layers' digests in order, one history entry per layer
  read -r chex csize < <(jq -nc --argjson layers "$layers" \
    '{architecture:"",created:"0001-01-01T00:00:00Z",history:[$layers[] | {created:"0001-01-01T00:00:00Z"}],os:"",rootfs:{type:"layers",diff_ids:[$layers[].digest]},config:{}}' | put_blob "$dir")
  read -r mhex msize < <(jq -nc --arg config "sha256:$chex" --argjson csize "$csize" --argjson layers "$layers" \
    '{schemaVersion:2,mediaType:"application/vnd.oci.image.manifest.v1+json",
      config:{mediaType:"application/vnd.oci.image.config.v1+json",size:$csize,digest:$config},
      layers:$layers}' | put_blob "$dir")
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

# What every refusal shows, asserted the same way by each refusal case: exit 1;
# exactly one ::error:: line, begun ::error::unpack-provenance:, carrying the
# digest in full and the reason; crane push never called. Reads $rc and $out of
# the run before it and the stub's call log.
refused() { # digest reason-pattern [what]: the pattern is grep -Ei on the error line, what names the case in the result line
  local digest="$1" reason="$2" what="${3:-$2}" errors count pushes ok=1
  errors=$(grep '^::error::' <<<"$out"); count=$(grep -c '^::error::' <<<"$out")
  pushes=$(grep '^crane push' "$SB/crane.log")
  [ "$rc" -eq 1 ] || ok=0
  [ "$count" -eq 1 ] && [[ "$errors" == "::error::unpack-provenance:"* ]] && [[ "$errors" == *"$digest"* ]] \
    && grep -Eiq -- "$reason" <<<"$errors" || ok=0
  [ -z "$pushes" ] || ok=0
  [ "$ok" -eq 1 ] \
    && pass "refused, $what: exit 1, one ::error::unpack-provenance: line with the digest and the reason, crane push never called" \
    || fail "refused, $what: exit 1, one ::error:: line, no crane push" "exit=$rc, wanted 1" \
         "::error:: lines in the output: $count, wanted one, begun '::error::unpack-provenance:', carrying '$digest' and matching '$reason' (any case):" "${errors:-none}" \
         "crane push calls logged, wanted none:" "${pushes:-none}" "output:" "${out:-none}"
}

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

# 4: the layers that were there are untouched: laid down with an SBOM layer and
#    a vulnerability-report layer (two blobs), the manifest pushed carries both
#    descriptors as they were (digest, size, media type, every annotation), in
#    their order and before the new layer, and both blobs are still in the layout
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG" "https://spdx.dev/Document" "https://cosign.sigstore.dev/attestation/vuln/v1"
# key-sorted on both sides: the order of an object's keys is free, the order of
# the layers is not
want=$(manifest_of "$SB/registry/$TAG" | jq -S '.layers')
out=$(run store "$DATA/bundle.jsonl" "$REPO" "$INDEX"); rc=$?
pushed="$SB/pushed/$TAG"
# all but the last: with no layer added, or the new one put first, these are
# not the two laid down
got=$(manifest_of "$pushed" | jq -S '.layers[:-1]' 2>/dev/null)
[ "$(jq 'map(.digest) | unique | length' <<<"$want")" = 2 ] && [ -n "$got" ] && [ "$got" = "$want" ] \
  && pass "the layers before the new one are the two laid down, descriptor for descriptor and in their order" \
  || fail "the pushed manifest's layers except the last against the layers laid down" "pushed, all but the last:" "$([ -n "$got" ] && jq -c '.[]?' <<<"$got" | short || echo "nothing was pushed to the tag")" "laid down:" "$(jq -c '.[]' <<<"$want" | short)" "exit=$rc" "$out"
# the blobs the laid-down layers name: each a file of the pushed layout whose
# sha256 is its name
kept=0; lost=()
for hex in $(jq -r '.[].digest | ltrimstr("sha256:")' <<<"$want"); do
  sum="no such blob"; [ -f "$pushed/blobs/sha256/$hex" ] && sum=$(sha256sum < "$pushed/blobs/sha256/$hex" | cut -d' ' -f1)
  if [ "$sum" = "$hex" ]; then kept=$((kept + 1)); else lost+=("layer $hex: sha256 of the blob in the pushed layout '$sum', wanted its name"); fi
done
[ "$kept" -eq 2 ] \
  && pass "both earlier layers' blobs are still in the pushed layout, each one's sha256 its name" \
  || fail "the blobs of the layers laid down, in the pushed layout" "${lost[@]}" "intact: $kept, wanted 2"

# 5: the config lists the layers the way cosign writes it: rootfs.diff_ids is
#    the layers' digests in order and history has one entry per layer, so a
#    layer more means a config rewritten, a new blob the manifest names by its
#    digest and its byte size (a registry refuses a descriptor whose size is
#    wrong); everything else in the config stays as it was laid down
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG" "https://spdx.dev/Document" "https://cosign.sigstore.dev/attestation/vuln/v1"
config_of() { # layout: the config its manifest names, the blob as it lies there
  local d; d=$(manifest_of "$1" | jq -r '.config.digest | strings' 2>/dev/null); [ -n "$d" ] || return 1
  cat "$1/blobs/sha256/${d#sha256:}" 2>/dev/null
}
was=$(config_of "$SB/registry/$TAG")
provenance="sha256:$(jq -r '.verificationMaterial.tlogEntries[0].canonicalizedBody' "$DATA/bundle.jsonl" | base64 -d | jq -r '.spec.envelopeHash.value')"
out=$(run store "$DATA/bundle.jsonl" "$REPO" "$INDEX"); rc=$?
pushed="$SB/pushed/$TAG"; manifest=$(manifest_of "$pushed"); config=$(config_of "$pushed")
# the descriptor against the blob it names
chex=$(jq -r '.config.digest | strings | ltrimstr("sha256:")' <<<"$manifest" 2>/dev/null); csize=$(jq -r '.config.size' <<<"$manifest" 2>/dev/null)
sum="no such blob"; bytes="no such blob"
if [ -n "$chex" ] && [ -f "$pushed/blobs/sha256/$chex" ]; then
  sum=$(sha256sum < "$pushed/blobs/sha256/$chex" | cut -d' ' -f1); bytes=$(wc -c < "$pushed/blobs/sha256/$chex")
fi
[ -n "$chex" ] && [ "$sum" = "$chex" ] && [ "$bytes" = "$csize" ] \
  && pass "the config the pushed manifest names is a blob of the pushed layout: its sha256 is its name, its byte size is .config.size" \
  || fail "the pushed manifest's config descriptor against the blob in the pushed layout" ".config.digest '${chex:-none, nothing was pushed to the tag}', sha256 of the blob '$sum'" ".config.size '$csize', bytes in the blob '$bytes'" "exit=$rc" "$out"
# diff_ids against the manifest's own layers: the same digests in the same
# order, three of them, the last the envelope the log recorded
want=$(jq -c '[.layers[].digest]' <<<"$manifest" 2>/dev/null)
got=$(jq -c '.rootfs.diff_ids' <<<"$config" 2>/dev/null)
[ -n "$got" ] && [ "$got" = "$want" ] && [ "$(jq 'length' <<<"$want")" = 3 ] && [ "$(jq -r '.[-1]' <<<"$want")" = "$provenance" ] \
  && pass "rootfs.diff_ids is the pushed manifest's layers' digests in order: three, the last the provenance layer" \
  || fail "rootfs.diff_ids of the pushed config against the pushed manifest's layers" "diff_ids:        ${got:-no config to read}" "layers' digests: ${want:-nothing was pushed to the tag}" "wanted three, the last $provenance" "exit=$rc" "$out"
# history: as many entries as layers, the ones laid down first and as they were
# (key-sorted on both sides: the order of an entry's keys is free)
want=$(jq -cS '.history' <<<"$was")
got=$(jq -cS '.history' <<<"$config" 2>/dev/null)
[ -n "$got" ] && [ "$(jq 'length' <<<"$got" 2>/dev/null)" = 3 ] && [ "$(jq '.layers | length' <<<"$manifest" 2>/dev/null)" = 3 ] && [ "$(jq -c '.[:2]' <<<"$got" 2>/dev/null)" = "$want" ] \
  && pass "history has one entry per layer, three, and the two that were there are unchanged and first" \
  || fail "history of the pushed config: one entry per layer, the entries laid down first" "history:   ${got:-no config to read}" "laid down: $want" "wanted three entries (layers in the pushed manifest: $(jq '.layers | length' <<<"$manifest" 2>/dev/null)), the first two the ones laid down" "exit=$rc" "$out"
# everything but the two lists: architecture, os, created, config, rootfs.type
# and no field more (parsed and key-sorted on both sides)
want=$(jq -cS 'del(.history, .rootfs.diff_ids)' <<<"$was")
got=$(jq -cS 'del(.history, .rootfs.diff_ids)' <<<"$config" 2>/dev/null)
[ -n "$got" ] && [ "$got" = "$want" ] \
  && pass "everything else in the config is as it was laid down: architecture, os, created, config, rootfs.type" \
  || fail "the pushed config without history and diff_ids against the one laid down" "pushed:    ${got:-no config to read}" "laid down: $want"

# 6: a second unpack replaces its own layer: a re-run release never stacks
#    statements. cosign attest --replace replaces by predicate type and leaves
#    this layer alone (measured), so the unpack replaces its own. Laid down
#    with an earlier release's provenance layer (another blob than the
#    fixture's envelope) between an SBOM layer and a vulnerability-report
#    layer, the manifest pushed carries one provenance layer, the new one and
#    last, the two others as they were, and the config follows
slsa="https://slsa.dev/provenance/v1"
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG" "https://spdx.dev/Document" "$slsa" "https://cosign.sigstore.dev/attestation/vuln/v1"
laid=$(manifest_of "$SB/registry/$TAG")
stale=$(jq -r '.layers[1].digest' <<<"$laid") # the earlier release's statement, the layer in the middle
provenance="sha256:$(jq -r '.verificationMaterial.tlogEntries[0].canonicalizedBody' "$DATA/bundle.jsonl" | base64 -d | jq -r '.spec.envelopeHash.value')"
out=$(run store "$DATA/bundle.jsonl" "$REPO" "$INDEX"); rc=$?
pushed="$SB/pushed/$TAG"; manifest=$(manifest_of "$pushed"); config=$(config_of "$pushed")
layers_words() { jq -r '.layers | to_entries[] | "layer \(.key + 1): \(.value.annotations.predicateType) \(.value.digest)"' 2>/dev/null; } # a manifest's layers for detail lines
# the layers of the provenance type: one, the envelope the log recorded, and
# the manifest's last (put where the stale one was, it would be the second)
got=$(jq -c --arg type "$slsa" '[.layers[] | select(.annotations.predicateType == $type) | .digest]' <<<"$manifest" 2>/dev/null)
last=$(jq -r '.layers[-1].digest' <<<"$manifest" 2>/dev/null)
[ "$stale" != "$provenance" ] && [ "$got" = "[\"$provenance\"]" ] && [ "$last" = "$provenance" ] \
  && pass "one layer of the pushed manifest is SLSA provenance: the new one, the envelope the log recorded, and it is the last layer" \
  || fail "the pushed manifest's provenance layers: one, the new one, last" "provenance layers pushed: ${got:-none, nothing was pushed to the tag}" "wanted:                   [\"$provenance\"]" "last layer '${last:-none}', wanted the new one" "the stale layer laid down: $stale" "pushed:" "$(layers_words <<<"$manifest")" "exit=$rc" "$out"
# the layers of any other type against the ones laid down (key-sorted on both
# sides: the order of an object's keys is free, the order of the layers is not)
want=$(jq -S --arg type "$slsa" '[.layers[] | select(.annotations.predicateType != $type)]' <<<"$laid")
got=$(jq -S --arg type "$slsa" '[.layers[] | select(.annotations.predicateType != $type)]' <<<"$manifest" 2>/dev/null)
[ "$(jq 'map(.digest) | unique | length' <<<"$want")" = 2 ] && [ -n "$got" ] && [ "$got" = "$want" ] \
  && pass "the other layers are the two laid down around the stale one, descriptor for descriptor and in their order" \
  || fail "the pushed manifest's layers of any other type against the ones laid down" "pushed, without the provenance type:" "$([ -n "$got" ] && jq -c '.[]?' <<<"$got" | short || echo "nothing was pushed to the tag")" "laid down, without the provenance type:" "$(jq -c '.[]' <<<"$want" | short)"
# diff_ids against the manifest's own layers: the same digests in the same
# order, three of them, the stale layer's not among them
want=$(jq -c '[.layers[].digest]' <<<"$manifest" 2>/dev/null)
got=$(jq -c '.rootfs.diff_ids' <<<"$config" 2>/dev/null)
[ -n "$got" ] && [ "$got" = "$want" ] && [ "$(jq 'length' <<<"$got" 2>/dev/null)" = 3 ] && [ "$(jq --arg stale "$stale" 'any(.[]; . == $stale)' <<<"$got" 2>/dev/null)" = false ] \
  && pass "rootfs.diff_ids is the pushed manifest's layers' digests in order: three, the stale layer's digest gone" \
  || fail "rootfs.diff_ids of the pushed config against the pushed manifest's layers" "diff_ids:        ${got:-no config to read}" "layers' digests: ${want:-nothing was pushed to the tag}" "wanted three, without the stale layer's $stale"
# history: the stale layer's entry went with it
got=$(jq -c '.history' <<<"$config" 2>/dev/null)
[ -n "$got" ] && [ "$(jq 'length' <<<"$got" 2>/dev/null)" = 3 ] \
  && pass "history has three entries, one per layer: the stale layer's entry is gone" \
  || fail "history of the pushed config: one entry per layer" "history: ${got:-no config to read}" "entries: $(jq 'length' <<<"${got:-[]}" 2>/dev/null), wanted 3 (three were laid down, one of them the stale layer's, one is new)"

# 7: one statement serves every digest it names: the fixture's one statement
#    names the index and the amd64 manifest, and store called with both
#    digests writes the provenance beside both: one push per .att tag, the
#    same envelope the last layer of each manifest pushed
AMD64="sha256:ac78223352dc43ec63a57e63b45de5420722ada4f7db77f1305ab472a86d0d4e"
fresh; TAG=$(att_tag "$INDEX"); TAG2=$(att_tag "$AMD64"); lay_down "$TAG"; lay_down "$TAG2"
provenance="sha256:$(jq -r '.verificationMaterial.tlogEntries[0].canonicalizedBody' "$DATA/bundle.jsonl" | base64 -d | jq -r '.spec.envelopeHash.value')"
out=$(run store "$DATA/bundle.jsonl" "$REPO" "$INDEX" "$AMD64"); rc=$?
# the references crane push was given, sorted on both sides: the order of the
# two pushes is free, their number and their tags are not
want=$(printf '%s\n' "$REPO:$TAG" "$REPO:$TAG2" | sort)
got=$(sed -n 's/^crane push .* //p' "$SB/crane.log" | sort)
[ "$rc" -eq 0 ] && [ "$got" = "$want" ] \
  && pass "store with two digests exits 0 and pushes twice, once to each digest's .att tag" \
  || fail "one crane push per digest, each to its .att tag" "exit=$rc, wanted 0" "crane push went to:" "${got:-nowhere, no push at all}" "wanted, once each:" "$want" "$out"
# the last layer of each manifest pushed: its predicateType, and the blob it
# names against the envelope the log recorded. A tag nothing was pushed to is
# said so, never read
typed=0; stored=0; types=(); blobs=()
for tag in "$TAG" "$TAG2"; do
  pushed="$SB/pushed/$tag"; manifest=""
  [ -f "$pushed/index.json" ] && manifest=$(manifest_of "$pushed")
  if [ -z "$manifest" ]; then types+=("$tag: nothing pushed"); blobs+=("$tag: nothing pushed"); continue; fi
  type=$(jq -r '.layers[-1].annotations.predicateType' <<<"$manifest" 2>/dev/null)
  [ "$type" = "https://slsa.dev/provenance/v1" ] && typed=$((typed + 1))
  types+=("$tag: last layer's predicateType '$type'")
  layer=$(jq -r '.layers[-1].digest | strings' <<<"$manifest" 2>/dev/null); hex=${layer#sha256:}
  sum="no such blob"; [ -n "$hex" ] && [ -f "$pushed/blobs/sha256/$hex" ] && sum=$(sha256sum < "$pushed/blobs/sha256/$hex" | cut -d' ' -f1)
  [ "$layer" = "$provenance" ] && [ "$sum" = "$hex" ] && stored=$((stored + 1))
  blobs+=("$tag: last layer '$layer', sha256 of the blob in the pushed layout '$sum'")
done
[ "$typed" -eq 2 ] \
  && pass "each of the two manifests pushed ends in a layer annotated as SLSA provenance v1" \
  || fail "the last layer's predicateType in each of the two manifests pushed" "${types[@]}" "wanted 'https://slsa.dev/provenance/v1' at both tags"
[ "$stored" -eq 2 ] \
  && pass "both layers name one blob, the envelope the log recorded, and it lies in each pushed layout under its sha256" \
  || fail "the last layer's blob at each of the two tags against the log entry's envelopeHash" "${blobs[@]}" "wanted the layer $provenance at both tags, the blob's sha256 its name"

# 8: refused, no statement in the bundles file names the digest: a well-formed
#    digest that is no subject of any statement there gets no layer. The
#    attestation manifest is laid down at its .att tag, so the refusal can only
#    come from the bundles file, never from a manifest that is missing
UNKNOWN="sha256:0000000000000000000000000000000000000000000000000000000000000000"
fresh; TAG=$(att_tag "$UNKNOWN"); lay_down "$TAG"
out=$(run store "$DATA/bundle.jsonl" "$REPO" "$UNKNOWN"); rc=$?
refused "$UNKNOWN" 'no statement' "no statement in the bundles file names the digest"

# 9: refused, the statement naming the digest is of another predicate type: the
#    unpack stores SLSA provenance v1 and nothing else. The bundles file is the
#    fixture's bundle with its statement's predicateType set to the SBOM's (the
#    envelope then no longer matches its signature, which nothing reads before
#    the type); the digest is named, the manifest is there, so the refusal can
#    only come from the type, and the error line names the type found
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
jq -c '.dsseEnvelope.payload |= (@base64d | fromjson | .predicateType = "https://spdx.dev/Document" | tojson | @base64)' "$DATA/bundle.jsonl" > "$SB/bundle-spdx.jsonl"
out=$(run store "$SB/bundle-spdx.jsonl" "$REPO" "$INDEX"); rc=$?
refused "$INDEX" 'https://spdx\.dev/Document' "the statement naming the digest is of another predicate type, named on the error line"

# 10: refused, the log entry has no signed entry timestamp: cosign's old
#     attestation layout verifies the transparency-log entry by its signed
#     entry timestamp (inclusionPromise.signedEntryTimestamp in the bundle,
#     SignedEntryTimestamp in the layer's bundle annotation); the newer Rekor
#     log issues none, only an inclusion proof, and the layout has no place for
#     that. The bundles file is the fixture's bundle with the log entry's
#     inclusionPromise deleted and everything else as it is (the statement, its
#     type, the envelope, the entry's body); the digest is named, the manifest
#     is there, so the refusal can only come from the missing timestamp. The
#     same for a promise that is there with an empty timestamp
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
jq -c 'del(.verificationMaterial.tlogEntries[0].inclusionPromise)' "$DATA/bundle.jsonl" > "$SB/bundle-no-promise.jsonl"
out=$(run store "$SB/bundle-no-promise.jsonl" "$REPO" "$INDEX"); rc=$?
refused "$INDEX" 'signed entry timestamp' "the log entry has no signed entry timestamp (no inclusionPromise)"
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
jq -c '.verificationMaterial.tlogEntries[0].inclusionPromise.signedEntryTimestamp = ""' "$DATA/bundle.jsonl" > "$SB/bundle-empty-promise.jsonl"
out=$(run store "$SB/bundle-empty-promise.jsonl" "$REPO" "$INDEX"); rc=$?
refused "$INDEX" 'signed entry timestamp' "the log entry's signed entry timestamp is empty"

# 11: refused, the envelope does not hash to the value the log entry records:
#     the layer's blob is the envelope in the compact form, and its sha256 must
#     be spec.envelopeHash.value of the entry's decoded canonicalizedBody. That
#     hash is the one tie between the layer's bytes and the transparency log,
#     so an envelope that does not match is refused before anything is pulled
#     or pushed. The bundles file is the fixture's bundle with one character of
#     the signature swapped for another base64 character (same length, still
#     base64) and everything else as it is (the payload, so the statement, its
#     subjects and its type; the log entry with its timestamp); the digest is
#     named, the manifest is there, so the refusal can only come from the hash
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
jq -c '.dsseEnvelope.signatures[0].sig |= ((if .[0:1] == "A" then "B" else "A" end) + .[1:])' "$DATA/bundle.jsonl" > "$SB/bundle-other-sig.jsonl"
out=$(run store "$SB/bundle-other-sig.jsonl" "$REPO" "$INDEX"); rc=$?
refused "$INDEX" 'hash' "the envelope does not hash to the value the log entry records"

# 12: refused, more or fewer than one signature on the envelope: the layer's
#     envelope carries exactly one signature, the one the log entry recorded.
#     A bundle whose dsseEnvelope.signatures holds two entries, or none, is
#     refused, and the error line says so: it speaks of the signatures, not of
#     the envelope hash (such an envelope does not hash to the logged value
#     either, but the count is the reason and is named as the reason). The
#     bundles file is the fixture's bundle with its one signature doubled, then
#     with the list emptied, and everything else as it is (the payload, so the
#     statement, its subjects and its type; the log entry with its timestamp);
#     the digest is named, the manifest is there, so the refusal can only come
#     from the envelope's signatures
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
jq -c '.dsseEnvelope.signatures += .dsseEnvelope.signatures' "$DATA/bundle.jsonl" > "$SB/bundle-two-signatures.jsonl"
out=$(run store "$SB/bundle-two-signatures.jsonl" "$REPO" "$INDEX"); rc=$?
refused "$INDEX" 'signature' "the envelope carries two signatures, not exactly one"
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
jq -c '.dsseEnvelope.signatures = []' "$DATA/bundle.jsonl" > "$SB/bundle-no-signature.jsonl"
out=$(run store "$SB/bundle-no-signature.jsonl" "$REPO" "$INDEX"); rc=$?
refused "$INDEX" 'signature' "the envelope carries no signature, not exactly one"

# 13: refused, more or fewer than one log entry in the bundle: the layer's
#     bundle annotation carries exactly one log entry, so a bundle whose
#     verificationMaterial.tlogEntries holds two entries, or none, is refused,
#     and the error line says so: it speaks of the log entries and their
#     number, not of a signed entry timestamp (a bundle with no entry has no
#     timestamp either, but the count is the reason and is named as the
#     reason). For a bundle with none the line adds the likely cause: the
#     action signed with GitHub's own Sigstore instance, which keeps no
#     transparency log (the instance it chooses when the event does not say the
#     repository is public). The bundles file is the fixture's bundle with its
#     one log entry doubled, then with the list emptied, and everything else as
#     it is (the statement, its subjects and its type; the envelope with its
#     one signature); the digest is named, the manifest is there, so the
#     refusal can only come from the bundle's log entries. The patterns ask for
#     the entries as counted ("log entries", "one log entry", "no log entry"):
#     the timestamp's and the hash's error lines speak of "the log entry" and
#     match neither
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
jq -c '.verificationMaterial.tlogEntries += .verificationMaterial.tlogEntries' "$DATA/bundle.jsonl" > "$SB/bundle-two-entries.jsonl"
out=$(run store "$SB/bundle-two-entries.jsonl" "$REPO" "$INDEX"); rc=$?
refused "$INDEX" 'log entries|(one|no) log entry' "the bundle carries two log entries, not exactly one"
# the likely cause belongs to the bundle with no entry: named for two entries,
# it would send the reader looking in the wrong place
errors=$(grep '^::error::' <<<"$out")
[ -n "$errors" ] && ! grep -Eiq 'Sigstore instance' <<<"$errors" \
  && pass "the error line for two log entries does not name GitHub's own Sigstore instance, the cause of a bundle with none" \
  || fail "the error line for two log entries, without the cause of a bundle with none" "::error:: lines in the output, wanted one that does not match 'Sigstore instance' (any case):" "${errors:-none}" "exit=$rc" "output:" "${out:-none}"
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
jq -c '.verificationMaterial.tlogEntries = []' "$DATA/bundle.jsonl" > "$SB/bundle-no-entry.jsonl"
out=$(run store "$SB/bundle-no-entry.jsonl" "$REPO" "$INDEX"); rc=$?
refused "$INDEX" '(log entries|(one|no) log entry).*GitHub.*Sigstore instance' "the bundle carries no log entry, the likely cause named: GitHub's own Sigstore instance, which keeps no transparency log"

# 14: refused, no attestation manifest beside the digest: the unpack adds its
#     layer to the attestation manifest cosign wrote for the digest, at the tag
#     sha256-<hex>.att, and never begins a new one. Where the registry holds no
#     such manifest the pull fails, and the error line says what is missing and
#     what has to happen: it speaks of the attestation manifest and says that
#     the release's other attestations must exist first (crane's own words,
#     MANIFEST_UNKNOWN: manifest unknown, say neither). Nothing is laid down at
#     the digest's .att tag, so the stub's pull fails the way crane does on a
#     missing manifest, each time it is asked; the bundles file is the
#     fixture's bundle as it is and the digest is named there, so the refusal
#     can only come from the manifest that is missing. The pattern asks for the
#     attestation manifest and, after it, the attestations that must exist
#     first: the timestamp's error line speaks of "the attestation layout" and
#     does not match
fresh # no lay_down: the registry holds nothing at the digest's .att tag
out=$(run store "$DATA/bundle.jsonl" "$REPO" "$INDEX"); rc=$?
refused "$INDEX" 'attestation manifest.*attestations.*(first|exist)' "no attestation manifest beside the digest, the release's other attestations must exist first"

# 15: refused, no layer of the attestation manifest carries a chain: the
#     provenance layer's dev.sigstore.cosign/chain is copied from a layer
#     cosign wrote in the same manifest (case 3), and Kyverno reads the
#     intermediate certificate from that annotation and from nowhere else. A
#     manifest none of whose layers carries the annotation leaves nothing to
#     copy, and the error line says so: it speaks of the layers and the chain
#     none of them carries. The layout is the one lay_down writes for an SBOM
#     layer and a vulnerability-report layer, with its manifest rewritten: the
#     chain annotation deleted from both layers and everything else as it was
#     (the layers' other annotations, their blobs, the config), the new blob in
#     the place of the old one, index.json naming it by its digest and its byte
#     size. The bundles file is the fixture's bundle as it is and the digest is
#     named there, the manifest is there and is pulled, so the refusal can only
#     come from the chain that is missing. The pattern asks for the layers and,
#     after them, the chain ("no layer ... chain"): no other error line speaks
#     of a chain
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG" "https://spdx.dev/Document" "https://cosign.sigstore.dev/attestation/vuln/v1"
layout="$SB/registry/$TAG"
with_chain=$(jq -r '.manifests[0].digest | ltrimstr("sha256:")' "$layout/index.json") # the manifest as lay_down wrote it
read -r mhex msize < <(manifest_of "$layout" | jq -c 'del(.layers[].annotations."dev.sigstore.cosign/chain")' | put_blob "$layout")
rm "$layout/blobs/sha256/$with_chain"
jq -c --arg manifest "sha256:$mhex" --argjson msize "$msize" \
  '.manifests[0].digest = $manifest | .manifests[0].size = $msize' "$layout/index.json" > "$SB/index.json"
mv "$SB/index.json" "$layout/index.json"
out=$(run store "$DATA/bundle.jsonl" "$REPO" "$INDEX"); rc=$?
refused "$INDEX" 'no layer.*chain' "no layer of the attestation manifest carries a chain"

# 16: refused, the chain did not issue the provenance certificate: the chain
#     annotation is copied beside the bundle's certificate (case 3), and
#     Kyverno takes the intermediate certificate from it, so the chain must be
#     the one that issued that certificate. A chain that did not issue it is
#     never copied beside it, and the error line says so: it speaks of the
#     chain and of the certificate it did not issue. The chain here is a
#     certificate authority of the test's own, made with openssl in the
#     sandbox at each run (no key or certificate of it is kept in the
#     repository): a self-signed root and an intermediate it signs, one PEM
#     text in the order of the fixture's chain.pem, the intermediate first. It
#     bears the names of the fixture's chain (O=sigstore.dev, CN=sigstore and
#     CN=sigstore-intermediate) and is a certificate authority in every other
#     respect: CA certificates that may
#     sign certificates, the intermediate for code signing, both valid from
#     the day before the log entry's integrated time (the moment a provenance
#     certificate, which lives ten minutes, can be checked at) for ten years.
#     Only its keys tell it from the real chain, so the refusal can only come
#     from the chain not having issued the certificate, never from a name, a
#     date or a certificate that is no authority's. openssl ca makes the
#     certificates: of the commands OpenSSL 3.0 has, it alone takes a start
#     date. The layout is the one lay_down writes for an SBOM layer and a
#     vulnerability-report layer, with its manifest rewritten the way case 15
#     does it: that chain in the annotation of both layers and everything else
#     as it was. The bundles file is the fixture's bundle as it is and the
#     digest is named there, the manifest is there, is pulled and carries a
#     chain on every layer. The pattern asks for the chain, the issuing and
#     the certificate, in either order: case 15's error line speaks of a chain
#     but of no certificate and nothing issued, and does not match
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG" "https://spdx.dev/Document" "https://cosign.sigstore.dev/attestation/vuln/v1"
layout="$SB/registry/$TAG"; ca="$SB/ca"; mkdir "$ca"
at=$(jq -r '.verificationMaterial.tlogEntries[0].integratedTime' "$DATA/bundle.jsonl")
from=$(date -u -d "@$((at - 86400))" +%Y%m%d%H%M%SZ); till=$(date -u -d "@$((at + 315360000))" +%Y%m%d%H%M%SZ)
: > "$ca/index.txt"; echo 01 > "$ca/serial" # openssl ca's books: the certificates issued, the next serial number
cat > "$ca/openssl.cnf" <<CNF
[req]
distinguished_name = dn
[dn]
[ca]
default_ca = made
[made]
database = $ca/index.txt
serial = $ca/serial
new_certs_dir = $ca
default_md = sha256
policy = names
[names]
organizationName = supplied
commonName = supplied
[root]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
[intermediate]
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid
CNF
# a key and a request each, then the root signs itself and the intermediate;
# what openssl says while it works goes to a log, never to the suite's output
openssl req -config "$ca/openssl.cnf" -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -noenc \
  -keyout "$ca/root.key" -subj "/O=sigstore.dev/CN=sigstore" -out "$ca/root.csr" >> "$ca/log" 2>&1
openssl req -config "$ca/openssl.cnf" -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -noenc \
  -keyout "$ca/intermediate.key" -subj "/O=sigstore.dev/CN=sigstore-intermediate" -out "$ca/intermediate.csr" >> "$ca/log" 2>&1
openssl ca -config "$ca/openssl.cnf" -batch -notext -selfsign -keyfile "$ca/root.key" -extensions root \
  -startdate "$from" -enddate "$till" -in "$ca/root.csr" -out "$ca/root.pem" >> "$ca/log" 2>&1
openssl ca -config "$ca/openssl.cnf" -batch -notext -cert "$ca/root.pem" -keyfile "$ca/root.key" -extensions intermediate \
  -startdate "$from" -enddate "$till" -in "$ca/intermediate.csr" -out "$ca/intermediate.pem" >> "$ca/log" 2>&1
cat "$ca/intermediate.pem" "$ca/root.pem" > "$ca/chain.pem" 2>> "$ca/log"
# the authority holds on its own at the integrated time, or the refusal below
# would prove nothing; no result line when it does
sound=$(openssl verify -attime "$at" -no-CApath -no-CAstore -CAfile "$ca/root.pem" "$ca/intermediate.pem" 2>&1) \
  || fail "the certificate authority made for case 16: its intermediate verifies against its root at the integrated time" "openssl verify at $at: $sound" "wanted: OK" "openssl while making it:" "$(cat "$ca/log")"
with_fixture=$(jq -r '.manifests[0].digest | ltrimstr("sha256:")' "$layout/index.json") # the manifest as lay_down wrote it, the fixture's chain on its layers
read -r mhex msize < <(manifest_of "$layout" | jq -c --rawfile chain "$ca/chain.pem" '.layers[].annotations."dev.sigstore.cosign/chain" = $chain' | put_blob "$layout")
rm "$layout/blobs/sha256/$with_fixture"
jq -c --arg manifest "sha256:$mhex" --argjson msize "$msize" \
  '.manifests[0].digest = $manifest | .manifests[0].size = $msize' "$layout/index.json" > "$SB/index.json"
mv "$SB/index.json" "$layout/index.json"
out=$(run store "$DATA/bundle.jsonl" "$REPO" "$INDEX"); rc=$?
refused "$INDEX" 'chain.*issu.*certificate|certificate.*issu.*chain' "the chain did not issue the provenance certificate"

# 17: all or nothing across digests: a release carries its provenance beside
#     every digest (the index and each platform manifest) or beside none, so a
#     digest that is refused leaves every tag as it was, the tags of the
#     digests before it included. store is called with case 7's two digests,
#     the index first and the amd64 manifest second; the fixture's one
#     statement names both. The attestation manifest is laid down at the
#     index's .att tag and nothing at the amd64 manifest's: the first digest
#     lacks nothing and could be stored, the second is refused the way case
#     14's is, with the same pattern, and the error line carries the second
#     digest. crane push is never called, not for the first digest either:
#     refused reads the whole call log, a push to any tag counts
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG" # no lay_down for the second digest: the registry holds nothing at its .att tag
out=$(run store "$DATA/bundle.jsonl" "$REPO" "$INDEX" "$AMD64"); rc=$?
refused "$AMD64" 'attestation manifest.*attestations.*(first|exist)' "the second of two digests has no attestation manifest beside it, nothing is pushed for the first either"

# 18: a push that fails three times fails the run naming the digest: a crane
#     push that fails is tried again, up to three attempts,
#     UNPACK_PROVENANCE_RETRY_DELAY seconds apart (0 in this suite, see run),
#     the shape of fetch-sboms.sh. After the third failure the run ends with
#     exit 1 and one error line of the unpack's own, which carries the digest,
#     speaks of the push and names the number of attempts: crane's own words
#     name a tag and a status, neither the digest nor how often it was tried.
#     It is the shape of Req 2.26: nothing stored, the digest named, a red run.
#     The attestation manifest is laid down at the index's .att tag and the
#     bundles file is the fixture's bundle as it is, so the digest lacks
#     nothing and is prepared in full: the failure can only come from the
#     push. Every push fails: the stub's count of the pushes that fail is set
#     far above any number of attempts. This is no refusal and refused cannot
#     be used here: the push is called, three times and no more, each call in
#     the stub's log, and nothing is kept under pushed. The pattern asks for
#     the push and for the number beside its noun, as a figure or as a word
#     ("3 attempts", "three times"), before the push or after it: a 3 inside
#     the digest or the tag does not match
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
echo 99 > "$SB/push-failures" # every push fails
out=$(run store "$DATA/bundle.jsonl" "$REPO" "$INDEX"); rc=$?
errors=$(grep '^::error::' <<<"$out"); count=$(grep -c '^::error::' <<<"$out")
pushes=$(grep '^crane push' "$SB/crane.log"); calls=$(grep -c '^crane push' "$SB/crane.log")
kept=$(ls -A "$SB/pushed")
tried='\b(3|three) (attempts|times|tries)\b'
[ "$rc" -eq 1 ] && [ "$count" -eq 1 ] && [[ "$errors" == "::error::unpack-provenance:"* ]] && [[ "$errors" == *"$INDEX"* ]] \
  && grep -Eiq -- "push.*$tried|$tried.*push" <<<"$errors" && [ "$calls" -eq 3 ] && [ -z "$kept" ] \
  && pass "a push that fails three times: exit 1, one ::error::unpack-provenance: line with the digest, the push and the three attempts, crane push called three times, nothing pushed" \
  || fail "a push that fails three times: exit 1, one ::error:: line, three crane push calls, nothing pushed" "exit=$rc, wanted 1" \
       "::error:: lines in the output: $count, wanted one, begun '::error::unpack-provenance:', carrying '$INDEX', speaking of the push and of 3 or three attempts (or times, or tries; any case):" "${errors:-none}" \
       "crane push calls logged: $calls, wanted 3:" "${pushes:-none}" \
       "under pushed, wanted nothing: ${kept:-nothing}" "output:" "${out:-none}"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all unpack-provenance tests passed"
