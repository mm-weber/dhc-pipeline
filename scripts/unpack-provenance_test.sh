#!/usr/bin/env bash
# Tests for scripts/unpack-provenance.sh, both its modes. store (cases 1 to
# 26): GitHub's provenance bundle (written by actions/attest-build-provenance)
# is stored as one more layer of the attestation manifest cosign keeps beside
# an image digest, at the tag sha256-<hex>.att (Req 2.27). Nothing is signed
# here: the layer's blob is the envelope the transparency log recorded, byte
# for byte. subjects (cases 27 and 28): the digests of an image are written
# to stdout as the lines the action reads as its subject-checksums file.
# crane is stubbed, a directory stands in for the registry; the bundle and the
# chain are the real ones of the measuring run of 2026-11-13
# (scripts/testdata/provenance).
# The cases are numbered as they were built. Cases 1 to 24 are the plan's
# slices 2.4.1 to 2.4.24; from case 25 on a case's number is one above its
# slice's, because a slice 2.4.24b was added (case 25), and each of those
# cases names its slice.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
UNPACK="$HERE/unpack-provenance.sh"
DATA="$HERE/testdata/provenance"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

# Every sandbox lives under this one directory, removed when the suite ends:
# the trap takes nothing from the suite's exit code. Without the directory
# the suite ends here: with $TOP empty the sandboxes would be made in /, where
# root may write, and would stay there, since the trap would have nothing to
# remove
TOP=$(mktemp -d) || { echo "FAIL the directory for the suite's sandboxes could not be made: the suite ends here"; exit 1; }
trap 'rm -rf "$TOP"' EXIT

# the repository and the index digest the fixture's statement names
REPO="ghcr.io/mm-weber/slsa-spike"
INDEX="sha256:c47ac86f0e7100538371e5836d2608bbb9abec15c5589d5bbc34bc9cad3619b2"
att_tag() { printf 'sha256-%s.att' "${1#sha256:}"; } # cosign's attestation tag for a digest

fresh() {
  # the one place where a sandbox is made, under $TOP. Without a sandbox the
  # suite ends here: with $SB empty the stub, the registry and what is pushed
  # would be laid down in /bin, /registry and /pushed
  SB=$(mktemp -d "$TOP/sandbox.XXXXXX") \
    || { echo "FAIL a sandbox for the case could not be made under '$TOP': the suite ends here"; exit 1; }
  mkdir -p "$SB/bin" "$SB/registry" "$SB/pushed"; : > "$SB/crane.log"
  # crane as a directory: pull copies the layout laid down for the tag, push
  # keeps the layout it was given, every call is logged. A case that wants
  # pushes to fail writes their number to $SB/push-failures: while it is above
  # 0 a push fails the way crane does (a line on stderr, exit 1), keeps nothing
  # and counts it down by one; with no such file no push fails. Pulls fail in
  # the same way for a case that writes their number to $SB/pull-failures:
  # while it is above 0 a pull fails the way crane does when the registry
  # answers 503 (a line on stderr, exit 1), writes nothing to the target
  # directory and counts it down by one; with no such file a pull fails only
  # where no layout is laid down for the tag
  cat > "$SB/bin/crane" <<'STUB'
#!/usr/bin/env bash
SB="$(cd "$(dirname "$0")/.." && pwd)"
printf 'crane %s\n' "$*" >> "$SB/crane.log"
case "$1" in
  pull) # crane pull --format oci <ref> <dir>
    ref="${*: -2:1}"; dir="${*: -1}"; tag="${ref##*:}"
    left=0; [ -f "$SB/pull-failures" ] && left=$(cat "$SB/pull-failures")
    if [ "$left" -gt 0 ]; then
      echo "$((left - 1))" > "$SB/pull-failures"
      echo "Error: GET https://${ref%%/*}/v2/.../manifests/$tag: unexpected status code 503 Service Unavailable" >&2; exit 1
    fi
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
# the envelope hash the log entry of the fixture's bundle records, the bare
# hex: what the layer stored for that bundle must be named by
logged_hash() { jq -r '.verificationMaterial.tlogEntries[0].canonicalizedBody' "$DATA/bundle.jsonl" | base64 -d | jq -r '.spec.envelopeHash.value'; }
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
want=$(logged_hash)
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
provenance="sha256:$(logged_hash)"
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
provenance="sha256:$(logged_hash)"
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
provenance="sha256:$(logged_hash)"
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
# a layout's manifest rewritten, for this case and for the cases 16 and 26:
# the manifest as lay_down wrote it is put through jq, the new blob takes the
# place of the old one and index.json names it by its digest and its byte
# size; the layers' blobs and the config stay as they were
rewrite_manifest() { # layout, then jq's arguments: the filter that rewrites the manifest, with the options it needs
  local layout="$1" was mhex msize; shift
  was=$(jq -r '.manifests[0].digest | ltrimstr("sha256:")' "$layout/index.json") # the manifest as lay_down wrote it
  read -r mhex msize < <(manifest_of "$layout" | jq -c "$@" | put_blob "$layout")
  rm "$layout/blobs/sha256/$was"
  jq -c --arg manifest "sha256:$mhex" --argjson msize "$msize" \
    '.manifests[0].digest = $manifest | .manifests[0].size = $msize' "$layout/index.json" > "$SB/index.json"
  mv "$SB/index.json" "$layout/index.json"
}
rewrite_manifest "$SB/registry/$TAG" 'del(.layers[].annotations."dev.sigstore.cosign/chain")'
out=$(run store "$DATA/bundle.jsonl" "$REPO" "$INDEX"); rc=$?
refused "$INDEX" 'no layer.*chain' "no layer of the attestation manifest carries a chain"

# 16: refused, the chain did not issue the provenance certificate: the chain
#     annotation is copied beside the bundle's certificate (case 3), and
#     Kyverno takes the intermediate certificate from it, so the chain must be
#     the one that issued that certificate. A chain that did not issue it is
#     never copied beside it, and the error line says so: it speaks of the
#     chain and of the certificate it did not issue. The chain here is a
#     certificate authority of the test's own, made by make_authority below
#     (what it is made of, how and why stands there): it bears the names of
#     the fixture's chain, is valid at the log entry's integrated time and is
#     a certificate authority in every other respect. Only its keys tell it
#     from the real chain, so the refusal can only come from the chain not
#     having issued the certificate, never from a name, a date or a
#     certificate that is no authority's. The layout is the one lay_down
#     writes for an SBOM layer and a vulnerability-report layer, with its
#     manifest rewritten the way case 15 does it (rewrite_manifest): that
#     chain in the annotation of both layers and everything else as it was.
#     The bundles file is the fixture's bundle as it is and the
#     digest is named there, the manifest is there, is pulled and carries a
#     chain on every layer. The pattern asks for the chain, the issuing and
#     the certificate, in either order: case 15's error line speaks of a chain
#     but of no certificate and nothing issued, and does not match
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG" "https://spdx.dev/Document" "https://cosign.sigstore.dev/attestation/vuln/v1"
# A certificate authority of the test's own, made with openssl in the sandbox
# at each run (no key or certificate of it is kept in the repository): a
# self-signed root and an intermediate it signs, one PEM text in the order of
# the fixture's chain.pem, the intermediate first ($ca/chain.pem). It bears
# the names of the fixture's chain (O=sigstore.dev, CN=sigstore and
# CN=sigstore-intermediate) and is a certificate authority in every other
# respect: CA certificates that may sign certificates, the intermediate for
# code signing, both valid from the day before the log entry's integrated
# time (the moment a provenance certificate, which lives ten minutes, can be
# checked at) for ten years. openssl ca makes the certificates: of the
# commands OpenSSL 3.0 has, it alone takes a start date. This case and case
# 26 use it, each in the sandbox made before the call. It sets ca (the
# authority's directory, $SB/ca), at (the integrated time), and sound and
# said: whether the authority holds on its own at the integrated time, its
# intermediate verified against its root (yes or no), and what openssl verify
# said of it. Each of the two cases asks for sound in its own way: with an
# authority that does not hold, the refusal would prove nothing
make_authority() {
  local from till
  ca="$SB/ca"; mkdir "$ca"
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
  # a key and a request each, then the root signs itself and the
  # intermediate; what openssl says while it works goes to a log, never to
  # the suite's output
  openssl req -config "$ca/openssl.cnf" -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -noenc \
    -keyout "$ca/root.key" -subj "/O=sigstore.dev/CN=sigstore" -out "$ca/root.csr" >> "$ca/log" 2>&1
  openssl req -config "$ca/openssl.cnf" -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -noenc \
    -keyout "$ca/intermediate.key" -subj "/O=sigstore.dev/CN=sigstore-intermediate" -out "$ca/intermediate.csr" >> "$ca/log" 2>&1
  openssl ca -config "$ca/openssl.cnf" -batch -notext -selfsign -keyfile "$ca/root.key" -extensions root \
    -startdate "$from" -enddate "$till" -in "$ca/root.csr" -out "$ca/root.pem" >> "$ca/log" 2>&1
  openssl ca -config "$ca/openssl.cnf" -batch -notext -cert "$ca/root.pem" -keyfile "$ca/root.key" -extensions intermediate \
    -startdate "$from" -enddate "$till" -in "$ca/intermediate.csr" -out "$ca/intermediate.pem" >> "$ca/log" 2>&1
  cat "$ca/intermediate.pem" "$ca/root.pem" > "$ca/chain.pem" 2>> "$ca/log"
  # the authority against itself at the integrated time: noted here, asked by
  # the case
  sound=yes; said=$(openssl verify -attime "$at" -no-CApath -no-CAstore -CAfile "$ca/root.pem" "$ca/intermediate.pem" 2>&1) || sound=no
}
make_authority
# the authority holds on its own at the integrated time, or the refusal below
# would prove nothing; no result line when it does
[ "$sound" = yes ] \
  || fail "the certificate authority made for case 16: its intermediate verifies against its root at the integrated time" "openssl verify at $at: $said" "wanted: OK" "openssl while making it:" "$(cat "$ca/log")"
rewrite_manifest "$SB/registry/$TAG" --rawfile chain "$ca/chain.pem" '.layers[].annotations."dev.sigstore.cosign/chain" = $chain'
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

# 19: wrong usage is refused: a call that is wrong ends with exit 2 and the
#     usage line, the family's code for it (exit 1 is a refusal of content, the
#     cases 8 to 17), before crane is asked for anything. The script has two
#     modes, store and subjects; the five wrong calls here are those of a call
#     with no mode and of store (the wrong calls of subjects are case 28's):
#     no argument at all; a mode that is neither store nor subjects (frob in
#     the place of store, the other arguments right); store with the bundles
#     file and the repository but no digest; a digest without sha256: (the
#     index digest's 64 hex digits alone); a bundles file that is not there (a
#     path in the sandbox nothing was written to). Each runs in a sandbox of
#     its own with the attestation manifest laid down at the index digest's
#     .att tag, so that only the call is wrong: whatever is right in it could
#     be stored. Wanted of each: exit 2; a line of the output begun "usage:
#     unpack-provenance.sh" (its beginning only, the modes and their arguments
#     follow it; a line begun with it, so bash's own complaint about an unset
#     parameter, which carries the text after the script's path and a line
#     number, is not one); no crane call in the stub's log, neither a pull nor
#     a push. This is no refusal of content and refused cannot be used here:
#     the exit code is another and there is no ::error:: line with a digest to
#     ask for. One result line for the five; on a failure its detail names
#     each call with what was found
seen=(); unrefused=0
misused() { # what, then the call's arguments: runs it in the sandbox made before it and notes whether it was refused as wrong usage
  local what="$1" usage="not found" crane; shift
  out=$(run "$@"); rc=$?
  grep -q '^usage: unpack-provenance\.sh' <<<"$out" && usage="found"
  crane=$(cat "$SB/crane.log")
  if [ "$rc" -eq 2 ] && [ "$usage" = "found" ] && [ -z "$crane" ]; then seen+=("refused, $what: exit 2, the usage line, no crane call"); return; fi
  unrefused=$((unrefused + 1))
  seen+=("NOT refused, $what: exit=$rc, wanted 2; a line begun 'usage: unpack-provenance.sh': $usage; crane calls: $(grep -c '' "$SB/crane.log"), wanted none")
  [ -z "$crane" ] || seen+=("$(sed 's/^/  called: /' <<<"$crane")")
  seen+=("$(sed 's/^/  output: /' <<<"${out:-none}")")
}
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
misused "no argument"
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
misused "an unknown mode (frob in the place of store)" frob "$DATA/bundle.jsonl" "$REPO" "$INDEX"
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
misused "no digest" store "$DATA/bundle.jsonl" "$REPO"
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
misused "a digest without sha256: (${INDEX#sha256:})" store "$DATA/bundle.jsonl" "$REPO" "${INDEX#sha256:}"
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
misused "a bundles file that is missing" store "$SB/no-such-bundles.jsonl" "$REPO" "$INDEX"
[ "$unrefused" -eq 0 ] \
  && pass "wrong usage is refused (no argument, an unknown mode, no digest, a digest without sha256:, a bundles file that is missing): each exit 2 with a line begun 'usage: unpack-provenance.sh', crane never called" \
  || fail "wrong usage is refused: exit 2, a line begun 'usage: unpack-provenance.sh', no crane call" "wrong calls not refused that way: $unrefused of 5" "${seen[@]}"

# 20: refused, the log entry is of another kind than dsse: the layer's blob is
#     the envelope, and what ties it to the transparency log is the envelope
#     hash a log entry of the kind dsse records (case 11). An entry of the
#     older kind intoto records something else, the layer could not be tied to
#     it, and the error line says so: it names the kind found. The bundles
#     file is the fixture's bundle with the entry's kind set to intoto in both
#     places that carry it: .kind of the decoded canonicalizedBody (the rest
#     of the body as it is, encoded back as base64 without line breaks, so the
#     envelope hash still stands there and the envelope still hashes to it)
#     and the entry's kindVersion.kind, so the bundle says the same whichever
#     of the two is read. Everything else is as it is (the statement, its
#     subjects and its type; the envelope with its one signature; the entry's
#     timestamp); the digest is named, the manifest is there, so the refusal
#     can only come from the kind. The pattern asks for the kind found,
#     intoto, and beside it the word kind or the kind wanted, dsse, in either
#     order: no other error line carries intoto
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
jq -c '.verificationMaterial.tlogEntries[0] |= (.canonicalizedBody |= (@base64d | fromjson | .kind = "intoto" | tojson | @base64) | .kindVersion.kind = "intoto")' "$DATA/bundle.jsonl" > "$SB/bundle-intoto.jsonl"
out=$(run store "$SB/bundle-intoto.jsonl" "$REPO" "$INDEX"); rc=$?
refused "$INDEX" '(kind|dsse).*intoto|intoto.*(kind|dsse)' "the log entry is of the kind intoto, not dsse, the kind found named on the error line"

# 21: several statements naming one digest, the newest is stored: a release
#     run twice on one digest leaves two statements in GitHub's attestation
#     store, each naming the digest and each valid, and the bundles file then
#     holds both. One of them becomes the layer, never both (case 6: a
#     manifest carries one provenance layer): the one whose log entry is the
#     later, by the entry's integrated time and, were the times the same, by
#     its log index. Which of the two comes first in the file decides nothing.
#     The fixture store-two.json is the store's answer for the index digest
#     after the measuring run attested it twice, the newer statement first:
#     log index 3862535824, integrated time 1794604165, naming the index
#     alone; then the statement of bundle.jsonl, log index 3862518718,
#     integrated time 1794604098. The script reads bundle lines, the action's
#     file (reading the store's answer as it is belongs to the next case), so
#     the two bundles are taken out of the answer with jq as two lines, once
#     in the fixture's order and once reversed, and store runs with each file
#     in a sandbox of its own, the attestation manifest laid down at the index
#     digest's .att tag. Each statement alone passes every refusal above (SLSA
#     provenance v1, one log entry of the kind dsse with its timestamp, one
#     signature, the envelope hash, the fixture's chain issuing its
#     certificate), so nothing but the choice between the two is asked. Two
#     more runs ask for the log index: the same two files, the older entry's
#     integrated time raised to the newer's on the line taken out (the fixture
#     stays as it is), so the times are the same and the log index alone tells
#     the two apart; the statement of the greater log index is wanted, the
#     newer one as before. The tie is made by raising the older entry's time,
#     never by lowering the newer's: the chain is verified at the integrated
#     time, the older certificate is still valid 67 seconds later and the
#     newer is not yet valid at the older time. The script does not verify the
#     signed entry timestamp, which covers the integrated time, so the changed
#     time breaks nothing the script checks. Both orders are run with the tie
#     as well: a choice by the integrated time alone stores the older
#     statement in one of them, with the newer on the first line if it keeps
#     the last of equals (as jq's max_by does), with the older there if it
#     keeps the first. Wanted of each run: exit 0; the manifest pushed has one
#     layer more than was laid down and exactly one of the provenance type;
#     that layer's digest is the newer statement's envelope hash, read here
#     from the fixture's entry of the greater integrated time (the entry of
#     the greater log index is read as well and must be the same one), and its
#     blob lies in the pushed layout under that sha256. One result line for
#     the four runs; on a failure its detail names each run with what was
#     found
entries='[.attestations[].bundle.verificationMaterial.tlogEntries[0]]' # the fixture's two log entries
logged='.canonicalizedBody | @base64d | fromjson | .spec.envelopeHash.value' # a log entry's envelope hash
newer="sha256:$(jq -r "$entries | max_by(.integratedTime | tonumber) | $logged" "$DATA/store-two.json")"
older="sha256:$(jq -r "$entries | min_by(.integratedTime | tonumber) | $logged" "$DATA/store-two.json")"
indexed="sha256:$(jq -r "$entries | max_by(.logIndex | tonumber) | $logged" "$DATA/store-two.json")"
tied=$(jq -r "$entries | max_by(.integratedTime | tonumber) | .integratedTime" "$DATA/store-two.json") # the newer entry's integrated time, as the bundle carries it
found=(); unstored=0
for order in "the newer statement on the first line, the fixture's order" "the older statement on the first line, the fixture's order reversed" \
             "the newer statement on the first line, the fixture's order, both entries at the integrated time $tied and the log index alone telling them apart" \
             "the older statement on the first line, the fixture's order reversed, both entries at the integrated time $tied and the log index alone telling them apart"; do
  fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
  before=$(manifest_of "$SB/registry/$TAG" | jq '.layers | length')
  lines='.attestations[].bundle'; [[ "$order" == *reversed* ]] && lines='.attestations | reverse | .[].bundle'
  [[ "$order" == *apart ]] && lines="$lines | .verificationMaterial.tlogEntries[0].integratedTime = \$tied"
  jq -c --arg tied "$tied" "$lines" "$DATA/store-two.json" > "$SB/bundles-two.jsonl"
  out=$(run store "$SB/bundles-two.jsonl" "$REPO" "$INDEX"); rc=$?
  # a tag nothing was pushed to is said so, never read
  pushed="$SB/pushed/$TAG"; manifest=""; [ -f "$pushed/index.json" ] && manifest=$(manifest_of "$pushed")
  after=$(jq '.layers | length' <<<"$manifest" 2>/dev/null)
  got=$(jq -c --arg type "$slsa" '[.layers[] | select(.annotations.predicateType == $type) | .digest]' <<<"$manifest" 2>/dev/null)
  hex=${newer#sha256:}; sum="no such blob"; [ -f "$pushed/blobs/sha256/$hex" ] && sum=$(sha256sum < "$pushed/blobs/sha256/$hex" | cut -d' ' -f1)
  if [ "$rc" -eq 0 ] && [ "$after" = "$((before + 1))" ] && [ "$got" = "[\"$newer\"]" ] && [ "$sum" = "$hex" ]; then
    found+=("stored, $order: exit 0, one layer more, one provenance layer, the newer statement's envelope"); continue
  fi
  unstored=$((unstored + 1))
  found+=("NOT stored, $order: exit=$rc, wanted 0; layers pushed: ${after:-none, nothing was pushed to the tag}, wanted $((before + 1)); provenance layers pushed: ${got:-none}, wanted [\"$newer\"]; sha256 of the newer envelope's blob in the pushed layout: '$sum', wanted its name")
  [ -z "$manifest" ] || found+=("$(layers_words <<<"$manifest" | sed 's/^/  pushed: /')")
  [ -s "$SB/crane.log" ] && found+=("$(sed 's/^/  called: /' "$SB/crane.log")") || found+=("  called: crane never")
  found+=("$(sed 's/^/  output: /' <<<"${out:-none}")")
done
[ "$newer" != "$older" ] && [ "$indexed" = "$newer" ] && [ "$unstored" -eq 0 ] \
  && pass "two statements naming one digest, the newest is stored (the newer on the first line of the bundles file, the older there, and both again with the two at one integrated time): each exit 0, one layer more, one provenance layer, the envelope of the later log entry, by its integrated time, then its log index" \
  || fail "two statements naming one digest: exit 0, one provenance layer, the envelope of the later log entry (integrated time, then log index), whichever statement comes first in the bundles file" "runs that did not store it that way: $unstored of 4" \
       "the newer statement's envelope, wanted as the one provenance layer: $newer" "the older statement's envelope:                                      $older" \
       "the envelope of the entry of the greater log index, wanted the newer: $indexed" "${found[@]}"

# 22: the attestation store's answer is read like the action's file: the
#     bundles file is the file the attest action leaves, one bundle per line.
#     The repair path reads the same bundles from GitHub's attestation store
#     instead, and the store answers with one JSON object over many lines,
#     the bundles inside it:
#     {"attestations":[{"repository_id":...,"bundle_url":...,"initiator":...,"bundle":{...}}]}.
#     store given that answer as its bundles file does exactly what it does
#     with the action's file. The fixture store.json is the store's answer
#     for the amd64 manifest after the measuring run, as the store gave it
#     but for the query string of its bundle_url, which is cut (a signed
#     storage link): one attestation, and its bundle is the bundle of
#     bundle.jsonl. That is asked here as well, both written compact by the
#     same jq: were they two bundles, the layouts would differ for the
#     fixtures' reasons. store runs twice, each run in a sandbox of its own,
#     once with bundle.jsonl and once with store.json, with case 7's two
#     digests, which the one statement names, and the attestation manifest
#     laid down the same way at both .att tags. Wanted: both runs exit 0, the
#     run with the action's file pushes something, and the run with the
#     store's answer pushes the same, byte for byte: every file under pushed
#     (both tags' layouts: oci-layout, index.json, every blob) is listed with
#     its sha256 and its path, sorted by path, and the two listings are the
#     same, so the same set of paths and the same contents. What the layout
#     must hold is asked by the cases above; here only that the two files
#     lead to one layout. One result line for the two runs; on a failure its
#     detail names each run with what was found
same=no; [ "$(jq -c '.attestations[].bundle' "$DATA/store.json")" = "$(jq -c . "$DATA/bundle.jsonl")" ] && same=yes
ran=(); codes=(); layouts=()
for bundles in "$DATA/bundle.jsonl" "$DATA/store.json"; do
  fresh; TAG=$(att_tag "$INDEX"); TAG2=$(att_tag "$AMD64"); lay_down "$TAG"; lay_down "$TAG2"
  out=$(run store "$bundles" "$REPO" "$INDEX" "$AMD64"); rc=$?
  # every file pushed, as "<sha256>  <its path under pushed>", sorted by path;
  # nothing when nothing was pushed
  layout=$(cd "$SB/pushed" && find . -type f -exec sha256sum {} + | LC_ALL=C sort -k2)
  files=0; [ -z "$layout" ] || files=$(grep -c '' <<<"$layout")
  codes+=("$rc"); layouts+=("$layout")
  ran+=("with ${bundles##*/}: exit=$rc, wanted 0; files pushed: $files$([ "$files" -gt 0 ] || echo ", nothing was pushed to any tag")")
  [ -s "$SB/crane.log" ] && ran+=("$(sed 's/^/  called: /' "$SB/crane.log")") || ran+=("  called: crane never")
  ran+=("$(sed 's/^/  output: /' <<<"${out:-none}")")
done
# the two listings against each other, for the detail lines: only where both
# runs pushed something
differ="nothing to compare, a run pushed nothing"
[ -n "${layouts[0]}" ] && [ -n "${layouts[1]}" ] && differ=$(diff <(printf '%s\n' "${layouts[0]}") <(printf '%s\n' "${layouts[1]}"))
[ "$same" = yes ] && [ "${codes[0]}" -eq 0 ] && [ "${codes[1]}" -eq 0 ] && [ -n "${layouts[0]}" ] && [ "${layouts[1]}" = "${layouts[0]}" ] \
  && pass "the attestation store's answer is read like the action's file: store with store.json and with bundle.jsonl, the same two digests, each exit 0, and the layouts pushed are the same, byte for byte (every file under pushed: the same paths, the same sha256)" \
  || fail "the attestation store's answer is read like the action's file: both runs exit 0, the layouts pushed the same, byte for byte" \
       "the bundle in store.json is the bundle of bundle.jsonl: $same, wanted yes" "${ran[@]}" \
       "the listing with bundle.jsonl against the one with store.json (sha256 and path of every file pushed), wanted no difference:" "${differ:-none}"

# 23: a digest named twice is stored once: the release job hands store the
#     digests of an image, and its list can name one digest twice (an index of
#     one platform whose digest reaches the call from two places, or a
#     caller's slip). Stored twice, the digest costs two pulls and two pushes
#     for one result, and every push more is one more that can fail (case 18).
#     store is called with case 7's two digests, which the fixture's one
#     statement names, as a list of three: the index, the amd64 manifest, the
#     index again. The other digest stands between the two namings on purpose:
#     a de-duplication that compares only neighbours (uniq without a sort)
#     takes out a naming that follows its like at once and would pass two
#     namings side by side; these two it leaves both. The bundles file is the
#     fixture's bundle as it is and the attestation manifest is laid down at
#     both .att tags, so neither digest lacks anything and nothing is refused:
#     only the list is unusual. Wanted: exit 0; two crane pulls and two crane
#     pushes in the stub's log, and of them one pull and one push for the
#     index digest's tag, one of each for the amd64 manifest's (the calls are
#     counted per tag as well, by the reference they carry: two and two in all
#     could be one digest handled twice and the other never); at each tag the
#     manifest pushed has one layer more than was laid down and exactly one of
#     the provenance type, as for a digest named once (cases 1 and 7). The
#     pushed layout alone cannot tell one push from two: the stub's push
#     replaces what an earlier push left at the tag, so two pushes of one
#     layout leave what one leaves, and the calls are counted in the log. One
#     result line; on a failure its detail shows the exit code, the crane
#     calls, each tag with its calls and the layers pushed, and the output
fresh; TAG=$(att_tag "$INDEX"); TAG2=$(att_tag "$AMD64"); lay_down "$TAG"; lay_down "$TAG2"
out=$(run store "$DATA/bundle.jsonl" "$REPO" "$INDEX" "$AMD64" "$INDEX"); rc=$?
pulls=$(grep -c '^crane pull' "$SB/crane.log"); pushes=$(grep -c '^crane push' "$SB/crane.log")
once=0; tags=()
for tag in "$TAG" "$TAG2"; do
  before=$(manifest_of "$SB/registry/$tag" | jq '.layers | length')
  # the calls that carry this tag's reference, wherever it stands among their arguments
  pulled=$(grep '^crane pull' "$SB/crane.log" | grep -cF -- "$REPO:$tag"); sent=$(grep '^crane push' "$SB/crane.log" | grep -cF -- "$REPO:$tag")
  # a tag nothing was pushed to is said so, never read
  pushed="$SB/pushed/$tag"; manifest=""; [ -f "$pushed/index.json" ] && manifest=$(manifest_of "$pushed")
  after=$(jq '.layers | length' <<<"$manifest" 2>/dev/null)
  typed=$(jq --arg type "$slsa" '[.layers[] | select(.annotations.predicateType == $type)] | length' <<<"$manifest" 2>/dev/null)
  [ "$pulled" -eq 1 ] && [ "$sent" -eq 1 ] && [ "$after" = "$((before + 1))" ] && [ "$typed" = 1 ] && once=$((once + 1))
  tags+=("$tag: crane pull calls $pulled, wanted 1; crane push calls $sent, wanted 1; layers pushed: ${after:-none, nothing was pushed to the tag}, wanted $((before + 1)); of the provenance type: ${typed:-none}, wanted 1")
  [ -z "$manifest" ] || tags+=("$(layers_words <<<"$manifest" | sed 's/^/  pushed: /')")
done
[ "$rc" -eq 0 ] && [ "$pulls" -eq 2 ] && [ "$pushes" -eq 2 ] && [ "$once" -eq 2 ] \
  && pass "a digest named twice is stored once: store with the index digest, the amd64 manifest's and the index digest again exits 0, two crane pulls and two crane pushes, one of each per .att tag, each manifest pushed has one layer more and one provenance layer" \
  || fail "a digest named twice is stored once: exit 0, one crane pull and one crane push per distinct digest, at each tag one layer more and one provenance layer" "exit=$rc, wanted 0" \
       "crane pull calls logged: $pulls, wanted 2; crane push calls logged: $pushes, wanted 2:" "$([ -s "$SB/crane.log" ] && cat "$SB/crane.log" || echo "crane never called")" \
       "tags stored once (one pull, one push, one layer more, one provenance layer): $once, wanted 2:" "${tags[@]}" \
       "output:" "${out:-none}"

# 24: a push that fails and is tried again is said: a registry answers 5xx now
#     and then, and the unpack tries a push up to three times (case 18, where
#     every attempt fails and the run ends red). A push that needed a second
#     or a third attempt goes through, the run is green, and then nothing of
#     the unpack's own says that the registry faltered: crane's words name a
#     tag and a status, and GitHub shows them as no annotation. Each failed
#     attempt that is tried again is said with one warning line in the shape
#     of the error lines, ::warning::unpack-provenance: <repository>@<digest>:
#     ..., which carries the digest, speaks of the push and names the attempt
#     that failed. The attestation manifest is laid down at the index's .att
#     tag and the bundles file is the fixture's bundle as it is, so the digest
#     lacks nothing and is prepared in full; the stub's count of the pushes
#     that fail is set to 2, so the first push and the second fail the way
#     crane does and the third goes through. Wanted: exit 0; one crane pull
#     and three crane pushes in the stub's log; exactly two lines of the
#     output begun ::warning::, each begun ::warning::unpack-provenance:, each
#     carrying the digest in full and speaking of the push, the first naming
#     the first attempt and the second the second; no ::error:: line, the run
#     did not fail; the manifest pushed has one layer more than was laid down
#     and exactly one of the provenance type, as for a push that goes through
#     at once (case 1). run folds stderr into the output, so the warning lines
#     are found on whichever of the two the script writes them. The patterns
#     ask for the number of the failed attempt beside its noun, attempt or
#     try: after the noun as a figure ("attempt 1", "try 2 of 3"), or before
#     it as a figure, an ordinal or a word ("1st attempt", "second try"). A 1
#     or a 2 inside the digest or the tag does not match, nor does a count of
#     the attempts ("2 attempts left"). The third and last failure of case
#     18's run is no part of this case: there the error line speaks. One
#     result line; on a failure its detail shows the exit code, the crane
#     calls, the warning lines found, the layers pushed and the output
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
before=$(manifest_of "$SB/registry/$TAG" | jq '.layers | length')
echo 2 > "$SB/push-failures" # the first two pushes fail, the third goes through
out=$(run store "$DATA/bundle.jsonl" "$REPO" "$INDEX"); rc=$?
warnings=$(grep '^::warning::' <<<"$out"); count=$(grep -c '^::warning::' <<<"$out")
errors=$(grep '^::error::' <<<"$out")
pulls=$(grep -c '^crane pull' "$SB/crane.log"); pushes=$(grep -c '^crane push' "$SB/crane.log")
# a tag nothing was pushed to is said so, never read
pushed="$SB/pushed/$TAG"; manifest=""; [ -f "$pushed/index.json" ] && manifest=$(manifest_of "$pushed")
after=$(jq '.layers | length' <<<"$manifest" 2>/dev/null)
typed=$(jq --arg type "$slsa" '[.layers[] | select(.annotations.predicateType == $type)] | length' <<<"$manifest" 2>/dev/null)
# the warning lines in their order, the first against the first attempt and
# the second against the second: each is counted when it is the unpack's own,
# carries the digest, speaks of the push and names its attempt
first='\b(attempt|try) 1\b|\b(1|1st|first) (attempt|try)\b'
second='\b(attempt|try) 2\b|\b(2|2nd|second) (attempt|try)\b'
named_attempts() { # push or pull, the call the lines must speak of: prints how many of the first two lines of $warnings are counted, each in its place
  local call="$1" nth line which named=0
  for nth in 1 2; do
    line=$(sed -n "${nth}p" <<<"$warnings"); which="$first"; [ "$nth" -eq 2 ] && which="$second"
    [[ "$line" == "::warning::unpack-provenance:"* ]] && [[ "$line" == *"$INDEX"* ]] \
      && grep -iq -- "$call" <<<"$line" && grep -Eiq -- "$which" <<<"$line" && named=$((named + 1))
  done
  echo "$named"
}
named=$(named_attempts push)
[ "$rc" -eq 0 ] && [ "$pulls" -eq 1 ] && [ "$pushes" -eq 3 ] && [ "$count" -eq 2 ] && [ "$named" -eq 2 ] && [ -z "$errors" ] \
  && [ "$after" = "$((before + 1))" ] && [ "$typed" = 1 ] \
  && pass "a push that fails twice and then goes through: exit 0, one crane pull and three crane pushes, two ::warning::unpack-provenance: lines with the digest and the push, the first naming the first attempt and the second the second, no ::error:: line, the manifest pushed has one layer more and one provenance layer" \
  || fail "a push that fails twice and then goes through: exit 0, three crane push calls, one ::warning:: line per failed attempt, no ::error:: line, the layer pushed" "exit=$rc, wanted 0" \
       "crane pull calls logged: $pulls, wanted 1; crane push calls logged: $pushes, wanted 3:" "$([ -s "$SB/crane.log" ] && cat "$SB/crane.log" || echo "crane never called")" \
       "::warning:: lines in the output: $count, wanted two, each begun '::warning::unpack-provenance:', carrying '$INDEX' and speaking of the push, the first naming attempt 1 (or try 1, or the 1st or first attempt or try; any case), the second attempt 2 in the same way; lines that do, in their place: $named, wanted 2:" "${warnings:-none}" \
       "::error:: lines in the output, wanted none:" "${errors:-none}" \
       "layers pushed: ${after:-none, nothing was pushed to the tag}, wanted $((before + 1)); of the provenance type: ${typed:-none}, wanted 1:" "$([ -n "$manifest" ] && layers_words <<<"$manifest" || echo "nothing was pushed to the tag")" \
       "output:" "${out:-none}"

# 25: a pull that fails is tried again (plan slice 2.4.24b): a registry
#     answers 5xx to a pull as it does to a push (cases 18 and 24), and with
#     one attempt a registry that falters once ends the run with case 14's
#     refusal, which speaks of an attestation manifest that is missing where
#     one is there. The pull is tried up to three times like the push,
#     UNPACK_PROVENANCE_RETRY_DELAY seconds apart, and each failed attempt
#     that is tried again is said with one warning line in case 24's shape,
#     ::warning::unpack-provenance: <repository>@<digest>: ..., which carries
#     the digest, speaks of the pull and names the attempt that failed. The
#     attestation manifest is laid down at the index's .att tag and the
#     bundles file is the fixture's bundle as it is, so the digest lacks
#     nothing; the stub's count of the pulls that fail is set to 2, so the
#     first pull and the second fail the way crane does on a 503 and the third
#     copies the layout. Wanted: exit 0; three crane pulls and one crane push
#     in the stub's log; exactly two lines of the output begun ::warning::,
#     each begun ::warning::unpack-provenance:, each carrying the digest in
#     full and speaking of the pull, the first naming the first attempt and
#     the second the second (case 24's patterns, $first and $second); no
#     ::error:: line, the run did not fail; the manifest pushed has one layer
#     more than was laid down and exactly one of the provenance type, as for a
#     pull that goes through at once (case 1). The third and last failure is
#     no part of this case: there case 14's refusal speaks. One result line;
#     on a failure its detail shows the exit code, the crane calls, the
#     warning lines found, the error lines found, the layers pushed and the
#     output
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
before=$(manifest_of "$SB/registry/$TAG" | jq '.layers | length')
echo 2 > "$SB/pull-failures" # the first two pulls fail, the third goes through
out=$(run store "$DATA/bundle.jsonl" "$REPO" "$INDEX"); rc=$?
warnings=$(grep '^::warning::' <<<"$out"); count=$(grep -c '^::warning::' <<<"$out")
errors=$(grep '^::error::' <<<"$out")
pulls=$(grep -c '^crane pull' "$SB/crane.log"); pushes=$(grep -c '^crane push' "$SB/crane.log")
# a tag nothing was pushed to is said so, never read
pushed="$SB/pushed/$TAG"; manifest=""; [ -f "$pushed/index.json" ] && manifest=$(manifest_of "$pushed")
after=$(jq '.layers | length' <<<"$manifest" 2>/dev/null)
typed=$(jq --arg type "$slsa" '[.layers[] | select(.annotations.predicateType == $type)] | length' <<<"$manifest" 2>/dev/null)
# the warning lines in their order, as in case 24 and by its named_attempts:
# each is counted when it is the unpack's own, carries the digest, speaks of
# the pull and names its attempt
named=$(named_attempts pull)
[ "$rc" -eq 0 ] && [ "$pulls" -eq 3 ] && [ "$pushes" -eq 1 ] && [ "$count" -eq 2 ] && [ "$named" -eq 2 ] && [ -z "$errors" ] \
  && [ "$after" = "$((before + 1))" ] && [ "$typed" = 1 ] \
  && pass "a pull that fails twice and then goes through: exit 0, three crane pulls and one crane push, two ::warning::unpack-provenance: lines with the digest and the pull, the first naming the first attempt and the second the second, no ::error:: line, the manifest pushed has one layer more and one provenance layer" \
  || fail "a pull that fails twice and then goes through: exit 0, three crane pull calls, one ::warning:: line per failed attempt, no ::error:: line, the layer pushed" "exit=$rc, wanted 0" \
       "crane pull calls logged: $pulls, wanted 3; crane push calls logged: $pushes, wanted 1:" "$([ -s "$SB/crane.log" ] && cat "$SB/crane.log" || echo "crane never called")" \
       "::warning:: lines in the output: $count, wanted two, each begun '::warning::unpack-provenance:', carrying '$INDEX' and speaking of the pull, the first naming attempt 1 (or try 1, or the 1st or first attempt or try; any case), the second attempt 2 in the same way; lines that do, in their place: $named, wanted 2:" "${warnings:-none}" \
       "::error:: lines in the output, wanted none:" "${errors:-none}" \
       "layers pushed: ${after:-none, nothing was pushed to the tag}, wanted $((before + 1)); of the provenance type: ${typed:-none}, wanted 1:" "$([ -n "$manifest" ] && layers_words <<<"$manifest" || echo "nothing was pushed to the tag")" \
       "output:" "${out:-none}"

# 26: a refusal from the bundle's content is not tried again (plan slice
#     2.4.25): the push and the pull are each tried up to three times (cases
#     18, 24 and 25), because a registry that falters once may answer the next
#     time. A refusal that comes from content is no such failure: the bundle
#     and the manifest pulled are the same at every attempt, so the refusal is
#     final at once. Nothing is asked of the registry a second time and
#     nothing is said of an attempt. The refusal here is case 16's, a refusal
#     of content that falls after the pull, where a loop of attempts laid
#     around too much would reach it: the chain of the manifest pulled did not
#     issue the provenance certificate. The setup is case 16's, made by the
#     same two helpers (make_authority, rewrite_manifest): a certificate
#     authority of the test's own, made with openssl in the sandbox, a root
#     and an intermediate that bear the names of the fixture's chain and are
#     valid at the log entry's integrated time; the
#     layout lay_down writes for an SBOM layer and a vulnerability-report
#     layer, with that chain in the annotation of both layers and everything
#     else as it was. The bundles file is the fixture's bundle as it is and
#     the digest is named there, the manifest is there and is pulled at the
#     first attempt (the stub lets no pull and no push fail here), so the
#     registry gives no reason for a second attempt. Wanted: exit 1; exactly
#     one crane pull and no crane push in the stub's log; exactly one line of
#     the output begun ::error::, begun ::error::unpack-provenance:, carrying
#     the digest in full and matching case 16's pattern (the chain, the
#     issuing and the certificate, in either order); no line begun
#     ::warning:: at all, neither of a pull nor of anything else; nothing
#     under pushed. The authority must hold on its own at the integrated time
#     as in case 16, or the refusal would prove nothing: here that is part of
#     the one result line. One result line; on a failure its detail shows the
#     exit code, the crane calls, the warning lines found, the error lines
#     found and the output, and the line about the authority only where the
#     authority does not hold
fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG" "https://spdx.dev/Document" "https://cosign.sigstore.dev/attestation/vuln/v1"
make_authority # whether the authority holds on its own (sound) is asked with the result line below
rewrite_manifest "$SB/registry/$TAG" --rawfile chain "$ca/chain.pem" '.layers[].annotations."dev.sigstore.cosign/chain" = $chain'
out=$(run store "$DATA/bundle.jsonl" "$REPO" "$INDEX"); rc=$?
warnings=$(grep '^::warning::' <<<"$out"); warned=$(grep -c '^::warning::' <<<"$out")
errors=$(grep '^::error::' <<<"$out"); count=$(grep -c '^::error::' <<<"$out")
pulls=$(grep -c '^crane pull' "$SB/crane.log"); pushes=$(grep -c '^crane push' "$SB/crane.log")
kept=$(ls -A "$SB/pushed")
issued='chain.*issu.*certificate|certificate.*issu.*chain' # case 16's pattern
# the detail's line about the authority: there only when it does not hold
unsound=()
[ "$sound" = yes ] \
  || unsound=("the certificate authority made for this case, its intermediate against its root at the integrated time $at: $sound, wanted yes${said:+ (openssl verify: $said)}")
[ "$sound" = yes ] && [ "$rc" -eq 1 ] && [ "$pulls" -eq 1 ] && [ "$pushes" -eq 0 ] \
  && [ "$count" -eq 1 ] && [[ "$errors" == "::error::unpack-provenance:"* ]] && [[ "$errors" == *"$INDEX"* ]] \
  && grep -Eiq -- "$issued" <<<"$errors" && [ "$warned" -eq 0 ] && [ -z "$kept" ] \
  && pass "a refusal from content is not tried again (the chain that did not issue the provenance certificate): exit 1, one crane pull and no crane push, one ::error::unpack-provenance: line with the digest and the reason, no ::warning:: line, nothing pushed" \
  || fail "a refusal from content is not tried again: exit 1, one crane pull call, no crane push call, one ::error:: line, no ::warning:: line, nothing pushed" "exit=$rc, wanted 1" \
       "crane pull calls logged: $pulls, wanted 1; crane push calls logged: $pushes, wanted 0:" "$([ -s "$SB/crane.log" ] && cat "$SB/crane.log" || echo "crane never called")" \
       "::warning:: lines in the output: $warned, wanted none:" "${warnings:-none}" \
       "::error:: lines in the output: $count, wanted one, begun '::error::unpack-provenance:', carrying '$INDEX' and matching '$issued' (any case):" "${errors:-none}" \
       "under pushed, wanted nothing: ${kept:-nothing}" "${unsound[@]}" \
       "output:" "${out:-none}"

# 27: subjects writes one line per digest in the shape the action reads (plan
#     slice 2.4.26): the release job hands the digests of an image to
#     actions/attest-build-provenance as its subject-checksums file, and the
#     script's second mode writes that file's lines to stdout:
#     subjects <repository> <digest>... One line per digest: the digest's 64
#     hex digits without sha256:, one space, the repository, the lines in the
#     order the digests were given. The shape is asked to the character,
#     because the action says nothing where it is missed (attest v4.2.1,
#     src/subject.ts): a line without a space is skipped silently, and a
#     digest with its sha256: prefix is thrown out as invalid. subjects is
#     called with the repository and case 7's two digests, the index first and
#     the amd64 manifest second: the index's hex begins c4 and the amd64
#     manifest's ac, so the order given is not the sorted one and lines that
#     were sorted would show (asked with the result line: the wanted lines are
#     not in sorted order). The mode asks nothing of the registry and reads no
#     bundles file: nothing is laid down in the sandbox and no file is given.
#     run folds stderr into the output and cannot be used here, stdout is the
#     file the action reads and must hold the lines and nothing else: the
#     script is called with run's environment (the stub first on PATH, the
#     delay 0), stdout taken as the output and stderr written to a file in the
#     sandbox (run_apart). Wanted: exit 0; stdout is exactly the two lines,
#     compared as a whole; nothing on stderr; no crane call in the stub's
#     log, neither a pull nor a push. One result line; on a failure its detail
#     shows the exit code, stdout as found and as wanted (both through cat -A,
#     so a tab, a trailing space or a carriage return shows), stderr and the
#     crane calls
run_apart() { PATH="$SB/bin:$PATH" UNPACK_PROVENANCE_RETRY_DELAY=0 "$UNPACK" "$@" 2> "$SB/stderr"; } # run's environment, stdout the output, stderr to a file in the sandbox
fresh
want=$(printf '%s %s\n' "${INDEX#sha256:}" "$REPO" "${AMD64#sha256:}" "$REPO")
out=$(run_apart subjects "$REPO" "$INDEX" "$AMD64"); rc=$?
err=$(cat "$SB/stderr"); crane=$(cat "$SB/crane.log" 2>/dev/null)
[ "$want" != "$(LC_ALL=C sort <<<"$want")" ] && [ "$rc" -eq 0 ] && [ "$out" = "$want" ] && [ -z "$err" ] && [ -z "$crane" ] \
  && pass "subjects with the index digest and the amd64 manifest's: exit 0, stdout is one line per digest in the order given, the bare hex, one space, the repository, nothing on stderr, crane never called" \
  || fail "subjects: exit 0, stdout one line per digest in the order given (the bare hex, one space, the repository), nothing on stderr, no crane call" "exit=$rc, wanted 0" \
       "stdout (through cat -A: a line's end as \$, a tab as ^I):" "$([ -n "$out" ] && cat -A <<<"$out" || echo "nothing")" \
       "wanted, the same way (not in sorted order, or sorted lines would not show):" "$(cat -A <<<"$want")" \
       "stderr, wanted nothing:" "${err:-nothing}" \
       "crane calls logged, wanted none:" "${crane:-none}"

# 28: subjects names a digest once and refuses what is not a digest (plan
#     slice 2.4.27): the lines subjects writes are the file the action reads
#     (case 27), and the mode gets the list of digests store gets, so it treats
#     that list as store does. A digest named more than once is written once,
#     at its first naming (case 23 for store): two lines for one digest are one
#     subject named twice to the action. An argument that is not sha256: and 64
#     lowercase hex digits makes the call a wrong call (case 19 for store): the
#     usage on stderr, exit 2, and nothing on stdout, the lines of the
#     well-formed digests before it included: the check comes before the first
#     line, because a file half written is a file the action signs for. The
#     six calls, each with the repository first:
#     the index digest, the amd64 manifest's, the index digest again (the other
#     digest between the two namings, as in case 23: a de-duplication of
#     neighbours only would leave both): exit 0, stdout exactly case 27's two
#     lines, the index's first (c4 before ac, so lines put through sort -u
#     show), nothing on stderr;
#     the index digest, then sha256:xyz (the prefix alone makes no digest; the
#     well-formed digest stands before it, so a line written before the check
#     shows on stdout);
#     a bare tag, v1.2.3, alone;
#     the index digest's 64 hex digits without sha256:, alone (what store
#     refuses in case 19: a check made after the prefix is stripped, as the
#     line is written, would let it through);
#     the amd64 manifest's digest, then the index digest with its hex in
#     uppercase (a registry's digest is lowercase, and a check by [[:xdigit:]]
#     or without regard to case would write a subject no verifier finds);
#     the index digest cut short, sha256: and its first 12 hex digits, alone (a
#     short form copied from a log: lowercase hex after the prefix, so a check
#     that asks for hex digits of any length would let it through).
#     Wanted of each of the five wrong calls: exit 2; stdout empty; on stderr
#     one line begun "usage: unpack-provenance.sh" (case 19's line). Each call
#     is made in case 27's way, by its run_apart: run's environment, stdout
#     taken as the output, stderr written to a file in the sandbox. Nothing
#     is laid down and no call may reach crane: the stub's log is read once,
#     after the six. One result line for the six; on a failure its detail
#     names each call with its exit code, its stdout as found and as wanted
#     (through cat -A), its stderr, and whether it was as wanted
calls=(); amiss=0
subjects_call() { # what, the exit code wanted, the stdout wanted, then subjects' arguments: runs the call in the case's sandbox and notes what was found and whether it is as wanted
  local what="$1" code="$2" lines="$3" err usage verdict="as wanted"; shift 3
  out=$(run_apart subjects "$@"); rc=$?
  err=$(cat "$SB/stderr"); usage=$(grep -c '^usage: unpack-provenance\.sh' <<<"$err")
  [ "$rc" -eq "$code" ] && [ "$out" = "$lines" ] || verdict="NOT as wanted"
  # stderr: nothing from a call that is right, the usage from a wrong one, its first line once
  if [ "$code" -eq 0 ]; then [ -z "$err" ] || verdict="NOT as wanted"; else [ "$usage" -eq 1 ] || verdict="NOT as wanted"; fi
  [ "$verdict" = "as wanted" ] || amiss=$((amiss + 1))
  calls+=("$verdict, $what: exit=$rc, wanted $code"
    "$( { [ -n "$out" ] && cat -A <<<"$out" || echo "nothing"; } | sed 's/^/  stdout: /')"
    "$( { [ -n "$lines" ] && cat -A <<<"$lines" || echo "nothing"; } | sed 's/^/  wanted: /')"
    "$(sed 's/^/  stderr: /' <<<"${err:-nothing}")"
    "  wanted: $([ "$code" -eq 0 ] && echo "nothing" || echo "the usage, one line begun 'usage: unpack-provenance.sh' (found: $usage)")")
}
fresh
want=$(printf '%s %s\n' "${INDEX#sha256:}" "$REPO" "${AMD64#sha256:}" "$REPO")
upper="sha256:$(tr a-f A-F <<<"${INDEX#sha256:}")"
subjects_call "a digest named twice (the index digest, the amd64 manifest's, the index digest again)" 0 "$want" "$REPO" "$INDEX" "$AMD64" "$INDEX"
subjects_call "sha256:xyz after the index digest" 2 "" "$REPO" "$INDEX" sha256:xyz
subjects_call "a bare tag (v1.2.3)" 2 "" "$REPO" v1.2.3
subjects_call "a digest without sha256: (${INDEX#sha256:})" 2 "" "$REPO" "${INDEX#sha256:}"
subjects_call "a digest in uppercase hex after the amd64 manifest's ($upper)" 2 "" "$REPO" "$AMD64" "$upper"
subjects_call "a digest of 12 hex digits (${INDEX:0:19})" 2 "" "$REPO" "${INDEX:0:19}"
crane=$(cat "$SB/crane.log")
[ "$amiss" -eq 0 ] && [ -z "$crane" ] \
  && pass "subjects names a digest once and refuses what is not a digest: a digest named twice is one line, at its first naming, exit 0, nothing on stderr; sha256:xyz, a bare tag, a digest without sha256:, one in uppercase hex and one of 12 hex digits are each exit 2 with nothing on stdout and one line begun 'usage: unpack-provenance.sh' on stderr; crane never called" \
  || fail "subjects names a digest once (one line, at its first naming, exit 0) and refuses what is not a digest (exit 2, nothing on stdout, the usage on stderr), no crane call" \
       "calls not as wanted: $amiss of 6" "${calls[@]}" \
       "crane calls logged over the six calls, wanted none:" "${crane:-none}"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all unpack-provenance tests passed"
