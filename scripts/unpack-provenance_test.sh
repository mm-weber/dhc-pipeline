#!/usr/bin/env bash
# Tests for scripts/unpack-provenance.sh, both its modes. store (cases 1 to
# 26 and case 29): GitHub's provenance bundle (written by
# actions/attest-build-provenance)
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
  # where no layout is laid down for the tag. digest prints the digest of the
  # manifest at the tag as crane does (.manifests[0].digest of the layout laid
  # down for it, sha256:<hex>, on stdout), fails like a pull where no layout is
  # laid down (the MANIFEST_UNKNOWN line on stderr, exit 1), and fails with 503
  # for a case that writes a number to $SB/digest-failures, counted down like
  # the two others. Another writer between a pull and what follows it: a case
  # that puts a layout at $SB/rewrite/<tag> has it moved over the layout at
  # $SB/registry/<tag> right after a pull of that tag is served, once (the
  # pull got the manifest as it was, the tag holds the other writer's from
  # then on); a case that puts layouts at $SB/rewrite/<tag>.1,
  # $SB/rewrite/<tag>.2, ... has them moved over the tag's layout in turn,
  # the lowest number first, one right after each pull of that tag is served,
  # until none is left (a writer that writes again after every pull; the
  # single layout at $SB/rewrite/<tag> goes first where both are there); a
  # case that makes a file $SB/remove/<tag> has the tag's layout
  # removed right after a pull of it is served, once (the tag has vanished).
  # A pull into a directory that already holds a layout does what crane does
  # there: the manifest pulled is appended to the index.json that is there,
  # after the entries it has, its blobs put beside the others
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
    mkdir -p "$dir" || exit 1
    if [ -f "$dir/index.json" ]; then
      jq -c --slurpfile pulled "$SB/registry/$tag/index.json" '.manifests += $pulled[0].manifests' "$dir/index.json" > "$dir/index.json.pulled" \
        && mv "$dir/index.json.pulled" "$dir/index.json" && cp -R "$SB/registry/$tag/blobs/." "$dir/blobs/" || exit 1
    else
      cp -R "$SB/registry/$tag/." "$dir/" || exit 1
    fi
    # the other writer, after the pull is served: the tag rewritten, or gone
    if [ -d "$SB/rewrite/$tag" ]; then rm -rf "$SB/registry/$tag"; mv "$SB/rewrite/$tag" "$SB/registry/$tag"
    else
      # several writes in turn: of the layouts at rewrite/<tag>.<n> the one
      # with the lowest number is the next
      next=""
      for queued in "$SB/rewrite/$tag".*; do
        [ -d "$queued" ] || continue
        [ -n "$next" ] && [ "${queued##*.}" -ge "${next##*.}" ] || next="$queued"
      done
      if [ -n "$next" ]; then rm -rf "$SB/registry/$tag"; mv "$next" "$SB/registry/$tag"; fi
    fi
    if [ -e "$SB/remove/$tag" ]; then rm -rf "$SB/registry/$tag" "$SB/remove/$tag"; fi
    exit 0 ;;
  digest) # crane digest <ref>
    ref="${*: -1}"; tag="${ref##*:}"
    left=0; [ -f "$SB/digest-failures" ] && left=$(cat "$SB/digest-failures")
    if [ "$left" -gt 0 ]; then
      echo "$((left - 1))" > "$SB/digest-failures"
      echo "Error: HEAD https://${ref%%/*}/v2/.../manifests/$tag: unexpected status code 503 Service Unavailable" >&2; exit 1
    fi
    if [ ! -d "$SB/registry/$tag" ]; then
      echo "Error: GET https://${ref%%/*}/v2/.../manifests/$tag: MANIFEST_UNKNOWN: manifest unknown" >&2; exit 1
    fi
    jq -r '.manifests[0].digest' "$SB/registry/$tag/index.json" ;;
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
#     no part of this case: there case 34's refusal speaks. One result line;
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

# 29: between two attempts of a registry call lies a pause (plan slice
#     2.4.30): a pull or a push that failed and is tried again (cases 24 and
#     25) is tried again after a wait, because a registry asked again at once
#     mostly meets the same blip, and then the three attempts are worth one.
#     After each failure that is tried again sleep is called once, with the
#     seconds UNPACK_PROVENANCE_RETRY_DELAY holds, and with 10 where the
#     variable is not set; after the third failure no pause follows, the run
#     ends with its refusal; a run in which no call fails never calls sleep.
#     sleep is a stand-in of this case's own, put into the sandbox's bin
#     after fresh: it writes the word sleep and its arguments to
#     $SB/sleep.log, one line per call, and ends with 0, so no input waits.
#     run fixes the variable to 0, so the script is run by this case's
#     pause_run: run's PATH and its folding of stderr into the output, the
#     variable set to the value the input names or taken out of the
#     environment. Every input has a sandbox of its own, the attestation
#     manifest laid down at the index's .att tag and the fixture's bundle as
#     it is, so the digest lacks nothing; the stub's counts make the pulls
#     and the pushes fail. The five inputs:
#     a pull that fails once and then goes through, the variable 7: exit 0,
#     one call, sleep 7;
#     a push that fails once and then goes through, the variable 7: the same;
#     a pull that fails twice and then goes through, the variable not set:
#     exit 0, two calls, each sleep 10;
#     a pull that fails three times, the variable 7: exit 1 (the refusal is
#     case 34's, its words are not asserted again), two calls,
#     each sleep 7, none after the third failure;
#     no call fails, the variable 7: exit 0, sleep never called.
#     The log is compared as a whole file, byte for byte, against the lines
#     wanted (cmp), never by a pattern or a count. One result line per input,
#     named by the input and what is wanted; on a failure its detail shows
#     the exit code, the sleep calls logged, the calls wanted and the output
pause_run() { # the seconds for the variable ("" takes it out of the environment), then the script's arguments
  local delay="$1"; shift
  if [ -n "$delay" ]; then PATH="$SB/bin:$PATH" UNPACK_PROVENANCE_RETRY_DELAY="$delay" "$UNPACK" "$@" 2>&1
  else PATH="$SB/bin:$PATH" env -u UNPACK_PROVENANCE_RETRY_DELAY "$UNPACK" "$@" 2>&1; fi
}
pause_input() { # what, the variable ("" not set), the pulls that fail, the pushes that fail, the exit code wanted, the sleep calls wanted in words, then one argument per sleep line wanted
  local what="$1" delay="$2" pulls="$3" pushes="$4" code="$5" said="$6"; shift 6
  fresh; TAG=$(att_tag "$INDEX"); lay_down "$TAG"
  # sleep as a log: the word and its arguments, one line per call, no wait
  cat > "$SB/bin/sleep" <<'STUB'
#!/usr/bin/env bash
SB="$(cd "$(dirname "$0")/.." && pwd)"
{ printf 'sleep'; [ "$#" -eq 0 ] || printf ' %s' "$@"; echo; } >> "$SB/sleep.log"
exit 0
STUB
  chmod +x "$SB/bin/sleep"; : > "$SB/sleep.log"
  echo "$pulls" > "$SB/pull-failures"; echo "$pushes" > "$SB/push-failures"
  # the lines wanted, as a file: none wanted is an empty file
  : > "$SB/sleep.want"; [ "$#" -eq 0 ] || printf '%s\n' "$@" > "$SB/sleep.want"
  out=$(pause_run "$delay" store "$DATA/bundle.jsonl" "$REPO" "$INDEX"); rc=$?
  [ "$rc" -eq "$code" ] && cmp -s "$SB/sleep.log" "$SB/sleep.want" \
    && pass "the pause between two attempts, $what: exit $code, $said" \
    || fail "the pause between two attempts, $what: exit $code, $said" "exit=$rc, wanted $code" \
         "sleep calls logged (through cat -A, \$ ends a line):" "$([ -s "$SB/sleep.log" ] && cat -A "$SB/sleep.log" || echo "none")" \
         "sleep calls wanted:" "$([ -s "$SB/sleep.want" ] && cat -A "$SB/sleep.want" || echo "none")" \
         "output:" "${out:-none}"
}
pause_input "a pull that fails once and then goes through, UNPACK_PROVENANCE_RETRY_DELAY=7" 7 1 0 0 "sleep called exactly once, as sleep 7" "sleep 7"
pause_input "a push that fails once and then goes through, UNPACK_PROVENANCE_RETRY_DELAY=7" 7 0 1 0 "sleep called exactly once, as sleep 7" "sleep 7"
pause_input "a pull that fails twice and then goes through, UNPACK_PROVENANCE_RETRY_DELAY not set" "" 2 0 0 "sleep called exactly twice, each time as sleep 10" "sleep 10" "sleep 10"
pause_input "a pull that fails three times, UNPACK_PROVENANCE_RETRY_DELAY=7" 7 3 0 1 "sleep called exactly twice, each time as sleep 7, no pause after the third failure" "sleep 7" "sleep 7"
pause_input "no call fails, UNPACK_PROVENANCE_RETRY_DELAY=7" 7 0 0 0 "sleep never called"

# 30: the provenance statement is chosen among provenance statements (plan
#     slice 2.9.1; spec FR-1, the clause of 2026-11-18 on more than one
#     statement naming a digest): GitHub's attestation store keeps every
#     statement made about a digest, an SBOM attested there as well as the
#     provenance, and the bundles file may then hold several statements that
#     name one digest and are not all provenance. Of those only the
#     statements of the predicate type https://slsa.dev/provenance/v1 are
#     candidates, and among the candidates the one whose log entry is the
#     latest is stored (integrated time, then log index, case 21). A
#     statement of another predicate type that names the same digest decides
#     nothing, however late its log entry is and wherever it stands in the
#     file: it neither hides the provenance statement nor becomes a layer,
#     and no layer cosign wrote gives way to it. Cases 8 and 9 hold what
#     stays: no statement naming the digest, and none of the provenance type
#     naming it, are refused.
#     The other statement is built here from the fixture's bundle with jq:
#     the same two subjects (the index and the amd64 manifest), the predicate
#     type https://spdx.dev/Document, and a log entry later than every entry
#     of the fixtures: an hour after the newer entry of store-two.json by its
#     integrated time and a thousand above it by its log index. It is no
#     consistent signed bundle (its envelope no longer matches its signature
#     or the hash its entry records) and need not be: it is never stored.
#     Six inputs, each in a sandbox of its own, the attestation manifest laid
#     down at the digest's .att tag with its one SBOM layer:
#     as bundle lines, for the index: the fixture's statement, then the
#     other; and the other first;
#     as the attestation store's answer ({"attestations":[{"bundle":...}]},
#     one JSON object over many lines), for the amd64 manifest: the same two
#     orders;
#     as bundle lines, for the index, with the two provenance statements of
#     store-two.json: the other, the newer, the older; and the older, the
#     newer, the other. Here the newer provenance statement is wanted, so a
#     choice that leaves the other type out and then takes the first or the
#     last candidate of the file stores the older one in one of the two.
#     stderr is kept apart (case 27's run_apart). Wanted of each input: exit
#     0; no ::error:: line on stderr or stdout; the manifest pushed has one
#     layer more than was laid down, the layers laid down are still its
#     first ones, unchanged, and exactly one layer is of the provenance type:
#     its digest is the envelope hash the wanted statement's log entry
#     records (for the fixture's statement what case 1 asserts), and its blob
#     lies in the pushed layout under that sha256. One result line per input;
#     on a failure its detail shows what was found against what was wanted
other_type="https://spdx.dev/Document"
late_time=$(jq -r '[.attestations[].bundle.verificationMaterial.tlogEntries[0].integratedTime | tonumber] | max + 3600 | tostring' "$DATA/store-two.json")
late_index=$(jq -r '[.attestations[].bundle.verificationMaterial.tlogEntries[0].logIndex | tonumber] | max + 1000 | tostring' "$DATA/store-two.json")
# the statements as bundle lines: the fixture's, the other built from it, and
# the two of store-two.json (the older of them is the fixture's statement)
stmt_fixture=$(jq -c . "$DATA/bundle.jsonl")
stmt_other=$(jq -c --arg type "$other_type" --arg time "$late_time" --arg index "$late_index" \
  '.dsseEnvelope.payload |= (@base64d | fromjson | .predicateType = $type | tojson | @base64)
   | .verificationMaterial.tlogEntries[0].integratedTime = $time | .verificationMaterial.tlogEntries[0].logIndex = $index' "$DATA/bundle.jsonl")
stmt_newer=$(jq -c '[.attestations[].bundle] | max_by(.verificationMaterial.tlogEntries[0].integratedTime | tonumber)' "$DATA/store-two.json")
stmt_older=$(jq -c '[.attestations[].bundle] | min_by(.verificationMaterial.tlogEntries[0].integratedTime | tonumber)' "$DATA/store-two.json")
envelope_logged() { jq -r '.verificationMaterial.tlogEntries[0].canonicalizedBody | @base64d | fromjson | .spec.envelopeHash.value'; } # stdin a bundle: the envelope hash its log entry records
want_fixture="sha256:$(logged_hash)"
want_newer="sha256:$(envelope_logged <<<"$stmt_newer")"
# what the inputs rest on, asked once: the other statement is of the other
# type, names both digests and carries the latest log entry; the two
# provenance statements of store-two.json are two, and the older is the
# fixture's
built=$(jq -r --arg index "${INDEX#sha256:}" --arg amd64 "${AMD64#sha256:}" \
  '(.dsseEnvelope.payload | @base64d | fromjson) as $s | .verificationMaterial.tlogEntries[0] as $e
   | "\($s.predicateType) \([$s.subject[].digest.sha256] | (index($index) != null) and (index($amd64) != null)) \($e.integratedTime) \($e.logIndex)"' <<<"$stmt_other" 2>&1)
built_want="$other_type true $late_time $late_index"
older_is="sha256:$(envelope_logged <<<"$stmt_older")"
[ "$built" = "$built_want" ] && [ "$want_newer" != "$want_fixture" ] && [ "$older_is" = "$want_fixture" ] \
  && pass "the inputs of the choice among provenance statements: the other statement is of the type $other_type, names the index and the amd64 manifest and carries the latest log entry (integrated time $late_time, log index $late_index); store-two.json holds two provenance statements, the older the fixture's" \
  || fail "the inputs of the choice among provenance statements" "the other statement (type, names both digests, integrated time, log index): '$built'" "wanted:                                                                    '$built_want'" \
       "the newer provenance statement's envelope: $want_newer, wanted another than the fixture's" "the older provenance statement's envelope: $older_is" "the fixture's envelope, wanted the older:  $want_fixture"
chosen_input() { # what, the digest, the envelope wanted as the one provenance layer (sha256:<hex>), lines or answer (the file's shape), then the bundles in the file's order
  local what="$1" digest="$2" want="$3" shape="$4" laid before pushed manifest after kept got hex sum errors; shift 4
  fresh; TAG=$(att_tag "$digest"); lay_down "$TAG"
  laid=$(manifest_of "$SB/registry/$TAG" | jq -c '.layers'); before=$(jq 'length' <<<"$laid")
  if [ "$shape" = answer ]; then printf '%s\n' "$@" | jq -s '{attestations: [.[] | {bundle: .}]}' > "$SB/bundles"
  else printf '%s\n' "$@" > "$SB/bundles"; fi
  out=$(run_apart store "$SB/bundles" "$REPO" "$digest"); rc=$?
  errors=$(printf '%s\n' "$out" | cat - "$SB/stderr" | grep '::error::')
  # a tag nothing was pushed to is said so, never read
  pushed="$SB/pushed/$TAG"; manifest=""; [ -f "$pushed/index.json" ] && manifest=$(manifest_of "$pushed")
  after=$(jq '.layers | length' <<<"$manifest" 2>/dev/null)
  kept=$(jq -r --argjson laid "$laid" 'if .layers[0:($laid | length)] == $laid then "yes" else "no" end' <<<"$manifest" 2>/dev/null)
  got=$(jq -c --arg type "$slsa" '[.layers[] | select(.annotations.predicateType == $type) | .digest]' <<<"$manifest" 2>/dev/null)
  hex=${want#sha256:}; sum="no such blob"; [ -f "$pushed/blobs/sha256/$hex" ] && sum=$(sha256sum < "$pushed/blobs/sha256/$hex" | cut -d' ' -f1)
  [ "$rc" -eq 0 ] && [ -z "$errors" ] && [ "$after" = "$((before + 1))" ] && [ "$kept" = yes ] && [ "$got" = "[\"$want\"]" ] && [ "$sum" = "$hex" ] \
    && pass "a statement of another predicate type decides nothing, $what: exit 0, no ::error:: line, one layer more, the layers laid down kept, one provenance layer, the envelope of the provenance statement wanted" \
    || fail "a statement of another predicate type decides nothing, $what: exit 0, no ::error:: line, one provenance layer, the envelope of the provenance statement wanted" \
         "exit=$rc, wanted 0" "::error:: lines on stderr or stdout, wanted none:" "${errors:-none}" \
         "layers pushed: ${after:-none, nothing was pushed to the tag}, wanted $((before + 1))" \
         "the layers laid down are the first layers pushed, unchanged: ${kept:-nothing was pushed to the tag}, wanted yes" \
         "provenance layers pushed: ${got:-none}, wanted [\"$want\"]" \
         "sha256 of the wanted envelope's blob in the pushed layout: '$sum', wanted its name, '$hex'" \
         "layers pushed:" "$([ -n "$manifest" ] && layers_words <<<"$manifest" || echo "none")" \
         "crane calls:" "$([ -s "$SB/crane.log" ] && cat "$SB/crane.log" || echo "crane never")" \
         "stdout:" "${out:-none}" "stderr:" "$([ -s "$SB/stderr" ] && cat "$SB/stderr" || echo "none")"
}
chosen_input "bundle lines, the provenance statement and then the other" "$INDEX" "$want_fixture" lines "$stmt_fixture" "$stmt_other"
chosen_input "bundle lines, the other statement and then the provenance statement" "$INDEX" "$want_fixture" lines "$stmt_other" "$stmt_fixture"
chosen_input "the attestation store's answer for the amd64 manifest, the provenance statement and then the other" "$AMD64" "$want_fixture" answer "$stmt_fixture" "$stmt_other"
chosen_input "the attestation store's answer for the amd64 manifest, the other statement and then the provenance statement" "$AMD64" "$want_fixture" answer "$stmt_other" "$stmt_fixture"
chosen_input "bundle lines with two provenance statements: the other, the newer, the older; the newer wanted" "$INDEX" "$want_newer" lines "$stmt_other" "$stmt_newer" "$stmt_older"
chosen_input "bundle lines with two provenance statements: the older, the newer, the other; the newer wanted" "$INDEX" "$want_newer" lines "$stmt_older" "$stmt_newer" "$stmt_other"

# 31: a bundles file that cannot be read is refused by name (plan slice
#     2.9.2; spec FR-1, the clause of 2026-11-18 on a bundles file that
#     cannot be read as JSON or holds an entry that is no Sigstore bundle
#     with a signed envelope whose statement can be read). store reads its
#     bundles file with jq. A file jq cannot read as what it must be ends the
#     run as a refusal of content like the others, in the script's own words
#     and not in those of the tool that failed on it, and before anything is
#     asked of the registry. An entry that cannot be read refuses the run
#     even when another entry of the file is the valid provenance bundle that
#     names the digest: a file the script cannot read in full is not one it
#     picks from. A bundle that can be read but lacks its certificate, its
#     integrated time, its log index or its log's id is the next slice's
#     (2.9.3) and no input here.
#     Every input is run for two digests, the index and the amd64 manifest
#     (the fixture's statement names both), in a sandbox of its own with the
#     attestation manifest laid down at both .att tags, so that a run that
#     gets as far as the registry shows in the stub's call log. The first
#     digest given is the index, in two inputs the amd64 manifest. stderr is
#     kept apart (case 27's run_apart). The inputs:
#     (a) no JSON at all: plain text; an empty file;
#     (b) the fixture's bundle line and one line that is no JSON, before it
#         and after it;
#     (c) an entry that is no bundle: the attestation store's answer with one
#         entry whose bundle is null, before the fixture's bundle and after
#         it; a line that is an object without dsseEnvelope, before the
#         fixture's bundle line and after it; a line that is JSON but no
#         object, after the fixture's bundle line: a number, a string, an
#         array (the array holds the fixture's bundle);
#     (d) an envelope whose payload is no statement, the entry built from the
#         fixture's bundle and standing after its line: a payload that is not
#         base64; base64 of text that is no JSON; a statement without
#         subject, after the fixture's bundle line and before it.
#     Wanted of each input: exit 1; nothing on stdout; on stderr exactly one
#     line, begun ::error::unpack-provenance: <repository>@<the first digest
#     given>: , ended (Req 2.27), holding the words "bundles file" and not
#     the reason of case 8 (no statement in the bundles file names the
#     digest: the file was not read, so nothing is known of what it names),
#     and none of jq's own words (jq: , parse error, Cannot index, Cannot
#     iterate, cannot be parsed, is not valid base64); crane never called,
#     neither pull nor push, for either digest. One result line per input; on
#     a failure its detail shows what was found against what was wanted
unreadable=$(mktemp -d "$TOP/unreadable.XXXXXX") \
  || { echo "FAIL the directory for the bundles files that cannot be read could not be made under '$TOP': the suite ends here"; exit 1; }
entry_valid=$(jq -c . "$DATA/bundle.jsonl")
entry_no_envelope=$(jq -c 'del(.dsseEnvelope)' "$DATA/bundle.jsonl")
entry_not_base64=$(jq -c '.dsseEnvelope.payload = "%%% this is not base64 %%%"' "$DATA/bundle.jsonl")
entry_no_json=$(jq -c '.dsseEnvelope.payload = ("this is no statement" | @base64)' "$DATA/bundle.jsonl")
entry_no_subject=$(jq -c '.dsseEnvelope.payload |= (@base64d | fromjson | del(.subject) | tojson | @base64)' "$DATA/bundle.jsonl")
# what the inputs rest on, asked once: the entry without an envelope is an
# object that has none and keeps its verification material; the payload that
# is no JSON is base64 of the text; the statement without subject is the
# fixture's statement, of the provenance type, with every other key
rest=$(jq -rn --argjson valid "$entry_valid" --argjson envelope "$entry_no_envelope" --argjson text "$entry_no_json" --argjson subject "$entry_no_subject" \
  '($valid.dsseEnvelope.payload | @base64d | fromjson) as $s | ($subject.dsseEnvelope.payload | @base64d | fromjson) as $t
   | "\($envelope | type) \($envelope | has("dsseEnvelope")) \($envelope | has("verificationMaterial")) \($text.dsseEnvelope.payload | @base64d) \($t | has("subject")) \($t == ($s | del(.subject))) \($t.predicateType)"' 2>&1)
rest_want="object false true this is no statement false true $slsa"
[ "$rest" = "$rest_want" ] \
  && pass "the inputs of the bundles file that cannot be read: the entry without an envelope is an object with its verification material, the payload that is no JSON is base64 of plain text, the statement without subject is the fixture's provenance statement less its subject" \
  || fail "the inputs of the bundles file that cannot be read" "found:  '$rest'" "wanted: '$rest_want'"
printf 'this is no JSON\n' > "$unreadable/text"
: > "$unreadable/empty"
printf '%s\n' 'this line is no JSON' "$entry_valid" > "$unreadable/line-before"
printf '%s\n' "$entry_valid" 'this line is no JSON' > "$unreadable/line-after"
jq -n --argjson valid "$entry_valid" '{attestations: [{bundle: null}, {bundle: $valid}]}' > "$unreadable/null-before"
jq -n --argjson valid "$entry_valid" '{attestations: [{bundle: $valid}, {bundle: null}]}' > "$unreadable/null-after"
printf '%s\n' "$entry_no_envelope" "$entry_valid" > "$unreadable/envelope-before"
printf '%s\n' "$entry_valid" "$entry_no_envelope" > "$unreadable/envelope-after"
printf '%s\n' "$entry_valid" '42' > "$unreadable/number"
printf '%s\n' "$entry_valid" '"a bundle"' > "$unreadable/string"
printf '%s\n' "$entry_valid" "[$entry_valid]" > "$unreadable/array"
printf '%s\n' "$entry_valid" "$entry_not_base64" > "$unreadable/not-base64"
printf '%s\n' "$entry_valid" "$entry_no_json" > "$unreadable/no-json"
printf '%s\n' "$entry_valid" "$entry_no_subject" > "$unreadable/subject-after"
printf '%s\n' "$entry_no_subject" "$entry_valid" > "$unreadable/subject-before"
short_lines() { cut -c1-300; } # stdin lines for a detail line, each cut to 300 characters
unreadable_input() { # what, the bundles file, the first digest given, the second
  local what="$1" bundles="$2" first="$3" second="$4" count line named=no words=none
  fresh; lay_down "$(att_tag "$first")"; lay_down "$(att_tag "$second")"
  out=$(run_apart store "$bundles" "$REPO" "$first" "$second"); rc=$?
  count=$(grep -c '' "$SB/stderr"); line=$(cat "$SB/stderr")
  [[ "$line" == "::error::unpack-provenance: ${REPO}@${first}: "*"bundles file"*" (Req 2.27)" ]] \
    && [[ "$line" != *"no statement in the bundles file names the digest"* ]] && named=yes
  grep -Eq 'jq: |parse error|Cannot index|Cannot iterate|cannot be parsed|is not valid base64' "$SB/stderr" && words=some
  [ "$rc" -eq 1 ] && [ -z "$out" ] && [ "$count" -eq 1 ] && [ "$named" = yes ] && [ "$words" = none ] && [ ! -s "$SB/crane.log" ] \
    && pass "a bundles file that cannot be read, $what: exit 1, nothing on stdout, one ::error:: line on stderr naming the first digest given and the bundles file, none of jq's words, crane never called" \
    || fail "a bundles file that cannot be read, $what: exit 1, nothing on stdout, one ::error:: line on stderr naming the first digest given and the bundles file, none of jq's words, crane never called" \
         "exit=$rc, wanted 1" "lines on stderr: $count, wanted 1" \
         "the one line begins '::error::unpack-provenance: ${REPO}@${first}: ', ends ' (Req 2.27)', holds 'bundles file' and is not case 8's reason: $named, wanted yes" \
         "jq's own words on stderr: $words, wanted none" \
         "stderr:" "$([ -s "$SB/stderr" ] && short_lines < "$SB/stderr" || echo "none")" \
         "stdout, wanted none:" "$([ -n "$out" ] && short_lines <<<"$out" || echo "none")" \
         "crane calls, wanted crane never:" "$([ -s "$SB/crane.log" ] && cat "$SB/crane.log" || echo "crane never")"
}
unreadable_input "(a) plain text, no JSON at all" "$unreadable/text" "$INDEX" "$AMD64"
unreadable_input "(a) plain text, no JSON at all, the amd64 manifest given first" "$unreadable/text" "$AMD64" "$INDEX"
unreadable_input "(a) an empty file" "$unreadable/empty" "$INDEX" "$AMD64"
unreadable_input "(b) a line that is no JSON, then the valid bundle line" "$unreadable/line-before" "$INDEX" "$AMD64"
unreadable_input "(b) the valid bundle line, then a line that is no JSON" "$unreadable/line-after" "$INDEX" "$AMD64"
unreadable_input "(c) the attestation store's answer, an entry whose bundle is null, then the valid bundle" "$unreadable/null-before" "$INDEX" "$AMD64"
unreadable_input "(c) the attestation store's answer, the valid bundle, then an entry whose bundle is null, the amd64 manifest given first" "$unreadable/null-after" "$AMD64" "$INDEX"
unreadable_input "(c) an object without dsseEnvelope, then the valid bundle line" "$unreadable/envelope-before" "$INDEX" "$AMD64"
unreadable_input "(c) the valid bundle line, then an object without dsseEnvelope" "$unreadable/envelope-after" "$INDEX" "$AMD64"
unreadable_input "(c) the valid bundle line, then a line that is a number" "$unreadable/number" "$INDEX" "$AMD64"
unreadable_input "(c) the valid bundle line, then a line that is a string" "$unreadable/string" "$INDEX" "$AMD64"
unreadable_input "(c) the valid bundle line, then a line that is an array holding the valid bundle" "$unreadable/array" "$INDEX" "$AMD64"
unreadable_input "(d) the valid bundle line, then an envelope whose payload is not base64" "$unreadable/not-base64" "$INDEX" "$AMD64"
unreadable_input "(d) the valid bundle line, then an envelope whose payload is base64 of text that is no JSON" "$unreadable/no-json" "$INDEX" "$AMD64"
unreadable_input "(d) the valid bundle line, then an envelope whose statement has no subject" "$unreadable/subject-after" "$INDEX" "$AMD64"
unreadable_input "(d) an envelope whose statement has no subject, then the valid bundle line" "$unreadable/subject-before" "$INDEX" "$AMD64"

# 32: a bundle that lacks a part the layer needs is refused by name (plan
#     slice 2.9.3; spec FR-1, the clause of 2026-11-18 on the bundle chosen
#     for a digest that lacks its signing certificate, or whose log entry
#     lacks its integrated time, its log index or its log's id, or holds one
#     of the first two as something other than a whole number). The bundle
#     chosen for a digest has passed the refusals of cases 9, 13, 10 and 20:
#     it is of the provenance type, holds exactly one log entry, that entry
#     has its signed entry timestamp and is of the kind dsse. The layer's
#     annotations then need four more parts of it: the signing certificate
#     (.verificationMaterial.certificate.rawBytes, base64 of DER) and, of the
#     log entry, its integrated time (.integratedTime), its own log index
#     (.logIndex) and the log's id (.logId.keyId, base64). A bundle without
#     one of them is refused like the others, in the script's own words and
#     not in those of jq, openssl, base64 or bash, and before anything is
#     pulled for that digest. A bundle with no log entry at all keeps the
#     refusal of case 13 and is no input here.
#     Every input is the fixture's bundle with one part changed by jq, alone
#     in the bundles file, run in a sandbox of its own with the attestation
#     manifest laid down at the .att tag of every digest given, so that a run
#     that gets as far as the registry shows in the stub's call log. stderr
#     is kept apart (case 27's run_apart). The inputs:
#     (a) the certificate: verificationMaterial.certificate removed and a
#         x509CertificateChain in its place (the older bundle form); rawBytes
#         null; rawBytes that is not base64; rawBytes that is base64 of bytes
#         that are no certificate;
#     (b) the integrated time: removed; null; a text that is no number
#         ("soon"); a number with a fraction ("1794604098.5");
#     (c) the log index: removed; a text that is no number ("many");
#     (d) the log's id: logId removed; keyId null; keyId that is not base64;
#     (e) the order of things, the bundle without its certificate of (a):
#         two digests given, the index first and then the amd64 manifest
#         first (the statement names both), the line names the first given;
#         and the two digests with a bundles file whose first line is the
#         newer provenance statement of store-two.json, complete and naming
#         the index alone: the index is in order, the amd64 manifest is the
#         digest refused, and nothing is pushed for the index either.
#     Wanted of each input: exit 1; nothing on stdout; on stderr exactly one
#     line, begun ::error::unpack-provenance: <repository>@<the digest
#     refused>: , ended (Req 2.27), holding the part that is missing in
#     words (certificate, integrated time, log index or log id, in any case)
#     and none of the other three; no word of a tool on stderr (jq, openssl,
#     base64: , bash's line numbers, Could not, invalid input and their
#     like); crane never called for push, for any digest, and never called
#     at all with the .att tag of the digest refused. One result line per
#     input; on a failure its detail shows what was found against what was
#     wanted
lacking=$(mktemp -d "$TOP/lacking.XXXXXX") \
  || { echo "FAIL the directory for the bundles that lack a part could not be made under '$TOP': the suite ends here"; exit 1; }
jq -c '.verificationMaterial |= (del(.certificate) + {x509CertificateChain: {certificates: [{rawBytes: .certificate.rawBytes}]}})' "$DATA/bundle.jsonl" > "$lacking/certificate-chain"
jq -c '.verificationMaterial.certificate.rawBytes = null' "$DATA/bundle.jsonl" > "$lacking/certificate-null"
jq -c '.verificationMaterial.certificate.rawBytes = "%%% this is not base64 %%%"' "$DATA/bundle.jsonl" > "$lacking/certificate-not-base64"
jq -c '.verificationMaterial.certificate.rawBytes = ("these bytes are no certificate" | @base64)' "$DATA/bundle.jsonl" > "$lacking/certificate-other-bytes"
jq -c 'del(.verificationMaterial.tlogEntries[0].integratedTime)' "$DATA/bundle.jsonl" > "$lacking/time-removed"
jq -c '.verificationMaterial.tlogEntries[0].integratedTime = null' "$DATA/bundle.jsonl" > "$lacking/time-null"
jq -c '.verificationMaterial.tlogEntries[0].integratedTime = "soon"' "$DATA/bundle.jsonl" > "$lacking/time-text"
jq -c '.verificationMaterial.tlogEntries[0].integratedTime = "1794604098.5"' "$DATA/bundle.jsonl" > "$lacking/time-fraction"
jq -c 'del(.verificationMaterial.tlogEntries[0].logIndex)' "$DATA/bundle.jsonl" > "$lacking/index-removed"
jq -c '.verificationMaterial.tlogEntries[0].logIndex = "many"' "$DATA/bundle.jsonl" > "$lacking/index-text"
jq -c 'del(.verificationMaterial.tlogEntries[0].logId)' "$DATA/bundle.jsonl" > "$lacking/id-removed"
jq -c '.verificationMaterial.tlogEntries[0].logId.keyId = null' "$DATA/bundle.jsonl" > "$lacking/id-null"
jq -c '.verificationMaterial.tlogEntries[0].logId.keyId = "%%% this is not base64 %%%"' "$DATA/bundle.jsonl" > "$lacking/id-not-base64"
cat <(printf '%s\n' "$stmt_newer") "$lacking/certificate-chain" > "$lacking/newer-then-certificate-chain"
# what the inputs rest on, asked once: each of the thirteen is one line, a
# bundle that differs from the fixture's in the one part named and in nothing
# else (the envelope, the entry's signed entry timestamp, body and kind and
# the three other parts are the fixture's); the bundle with the chain in the
# certificate's place has no certificate and carries the chain, the
# certificate's bytes in it; the newer statement of the last input is another
# than the fixture's
lacking_rest=$(for f in certificate-chain certificate-null certificate-not-base64 certificate-other-bytes time-removed time-null time-text time-fraction index-removed index-text id-removed id-null id-not-base64; do
  jq -rs --slurpfile valid "$DATA/bundle.jsonl" --arg f "$f" \
    '[["verificationMaterial", "certificate"], ["verificationMaterial", "tlogEntries", 0, "integratedTime"], ["verificationMaterial", "tlogEntries", 0, "logIndex"], ["verificationMaterial", "tlogEntries", 0, "logId"]] as $parts
     | {certificate: 0, time: 1, index: 2, id: 3}[$f | split("-")[0]] as $n
     | if length == 1 and (.[0] | delpaths([$parts[$n], ["verificationMaterial", "x509CertificateChain"]])) == ($valid[0] | delpaths([$parts[$n]]))
          and (.[0] | getpath($parts[$n])) != ($valid[0] | getpath($parts[$n]))
       then "\($f) yes" else "\($f) no" end' "$lacking/$f" 2>&1
done | tr '\n' ' ')
lacking_rest="$lacking_rest$(jq -rs --slurpfile valid "$DATA/bundle.jsonl" '.[0].verificationMaterial | "chain \(has("certificate") | not) \(.x509CertificateChain.certificates | length) \(.x509CertificateChain.certificates[0].rawBytes == $valid[0].verificationMaterial.certificate.rawBytes)"' "$lacking/certificate-chain" 2>&1) newer $([ "$want_newer" != "$want_fixture" ] && echo other || echo same)"
lacking_want="certificate-chain yes certificate-null yes certificate-not-base64 yes certificate-other-bytes yes time-removed yes time-null yes time-text yes time-fraction yes index-removed yes index-text yes id-removed yes id-null yes id-not-base64 yes chain true 1 true newer other"
[ "$lacking_rest" = "$lacking_want" ] \
  && pass "the inputs of the bundle that lacks a part: thirteen bundles, each the fixture's with the one part named changed and nothing else; the bundle with a certificate chain has no certificate; the newer statement of store-two.json is another than the fixture's" \
  || fail "the inputs of the bundle that lacks a part" "found:  '$lacking_rest'" "wanted: '$lacking_want'"
lacking_input() { # what, the part wanted on the line (certificate, integrated time, log index or log id), the bundles file, the digest refused, then the digests given
  local what="$1" part="$2" bundles="$3" refused="$4" digest count line named=no other others="" words=none calls
  shift 4
  fresh; for digest in "$@"; do lay_down "$(att_tag "$digest")"; done
  out=$(run_apart store "$bundles" "$REPO" "$@"); rc=$?
  count=$(grep -c '' "$SB/stderr"); line=$(cat "$SB/stderr")
  [[ "$line" == "::error::unpack-provenance: ${REPO}@${refused}: "*" (Req 2.27)" ]] && grep -Fiq -- "$part" <<<"$line" && named=yes
  for other in "certificate" "integrated time" "log index" "log id"; do
    [ "$other" = "$part" ] || ! grep -Fiq -- "$other" "$SB/stderr" || others="$others '$other'"
  done
  grep -Eq '(^|[^[:alnum:]])jq([^[:alnum:]]|$)|parse error|Cannot |cannot be parsed|openssl|Could not|[Uu]nable to load|base64: |invalid input|unbound variable|line [0-9]+: |error:[0-9A-Fa-f]{6,}' "$SB/stderr" && words=some
  calls=$(grep -E "^crane push|$(att_tag "$refused")" "$SB/crane.log")
  [ "$rc" -eq 1 ] && [ -z "$out" ] && [ "$count" -eq 1 ] && [ "$named" = yes ] && [ -z "$others" ] && [ "$words" = none ] && [ -z "$calls" ] \
    && pass "a bundle that lacks a part, $what: exit 1, nothing on stdout, one ::error:: line on stderr naming the digest and the $part and none of the other parts, no word of a tool, no crane push, no crane call for the digest refused" \
    || fail "a bundle that lacks a part, $what: exit 1, nothing on stdout, one ::error:: line on stderr naming the digest and the $part and none of the other parts, no word of a tool, no crane push, no crane call for the digest refused" \
         "exit=$rc, wanted 1" "lines on stderr: $count, wanted 1" \
         "the one line begins '::error::unpack-provenance: ${REPO}@${refused}: ', ends ' (Req 2.27)' and holds '$part' (any case): $named, wanted yes" \
         "the other parts named on stderr:${others:- none}, wanted none" \
         "a tool's own words on stderr: $words, wanted none" \
         "stderr:" "$([ -s "$SB/stderr" ] && short_lines < "$SB/stderr" || echo "none")" \
         "stdout, wanted none:" "$([ -n "$out" ] && short_lines <<<"$out" || echo "none")" \
         "crane push calls and crane calls with the tag of the digest refused, wanted none:" "${calls:-none}" \
         "crane calls:" "$([ -s "$SB/crane.log" ] && cat "$SB/crane.log" || echo "crane never")"
}
lacking_input "(a) no certificate, a certificate chain in its place" "certificate" "$lacking/certificate-chain" "$INDEX" "$INDEX"
lacking_input "(a) the certificate's rawBytes null" "certificate" "$lacking/certificate-null" "$INDEX" "$INDEX"
lacking_input "(a) the certificate's rawBytes not base64" "certificate" "$lacking/certificate-not-base64" "$INDEX" "$INDEX"
lacking_input "(a) the certificate's rawBytes base64 of bytes that are no certificate" "certificate" "$lacking/certificate-other-bytes" "$INDEX" "$INDEX"
lacking_input "(b) the integrated time removed" "integrated time" "$lacking/time-removed" "$INDEX" "$INDEX"
lacking_input "(b) the integrated time null" "integrated time" "$lacking/time-null" "$INDEX" "$INDEX"
lacking_input "(b) the integrated time a text that is no number" "integrated time" "$lacking/time-text" "$INDEX" "$INDEX"
lacking_input "(b) the integrated time a number with a fraction" "integrated time" "$lacking/time-fraction" "$INDEX" "$INDEX"
lacking_input "(c) the log index removed" "log index" "$lacking/index-removed" "$INDEX" "$INDEX"
lacking_input "(c) the log index a text that is no number" "log index" "$lacking/index-text" "$INDEX" "$INDEX"
lacking_input "(d) the log's id removed (logId)" "log id" "$lacking/id-removed" "$INDEX" "$INDEX"
lacking_input "(d) the log's id null (keyId)" "log id" "$lacking/id-null" "$INDEX" "$INDEX"
lacking_input "(d) the log's id not base64 (keyId)" "log id" "$lacking/id-not-base64" "$INDEX" "$INDEX"
lacking_input "(e) no certificate, two digests given, the index first: the index is named" "certificate" "$lacking/certificate-chain" "$INDEX" "$INDEX" "$AMD64"
lacking_input "(e) no certificate, two digests given, the amd64 manifest first: the amd64 manifest is named" "certificate" "$lacking/certificate-chain" "$AMD64" "$AMD64" "$INDEX"
lacking_input "(e) no certificate in the bundle chosen for the amd64 manifest, the index in order before it: the amd64 manifest is named, nothing is pushed for the index" "certificate" "$lacking/newer-then-certificate-chain" "$AMD64" "$INDEX" "$AMD64"

# 33: a manifest that is not there is refused at the first answer (plan slice
#     2.9.4; spec FR-1, the clause of 2026-11-18 on the registry answering
#     that no attestation manifest exists beside a digest). A pull that fails
#     is tried again (cases 25 and 29) because a registry that falters may
#     answer the next time. A registry that answers that the manifest is not
#     there has answered: its error code MANIFEST_UNKNOWN (the code of the OCI
#     distribution API for a manifest or a tag that is not there) is on the
#     line crane prints on stderr, and asking again brings the same answer two
#     attempts and two pauses later. So a failed pull whose stderr holds that
#     code ends the digest at once: no further pull of that tag, no
#     ::warning:: line for that failure, no pause after it, the refusal of
#     case 14 (no attestation manifest at the tag, the release's other
#     attestations must exist first). The code decides, not the words the
#     registry puts after it, which differ from registry to registry. A pull
#     that fails for another cause (the stub's 503) keeps its attempts, its
#     warnings and its pauses, and a pull answered MANIFEST_UNKNOWN after one
#     or two such failures is refused at that answer, with the warnings said
#     and the pauses made so far. What crane said passes to stderr as before,
#     every failed pull's line, the registry's answer above the error line.
#     Every input has a sandbox of its own, the fixture's bundle as it is (it
#     names both digests) and nothing laid down at the .att tag of the digest
#     refused; the stub's count of pulls that fail holds the 503s that come
#     first. sleep is case 29's stand-in, a log of its calls, and the variable
#     is 7, so a pause shows as the line sleep 7. stdout is the output, stderr
#     is kept apart in the sandbox. The inputs:
#     (a) nothing at the tag, the first answer is MANIFEST_UNKNOWN: one pull,
#         no warning, no pause;
#     (b) the same with the words another registry puts after the code
#         (MANIFEST_UNKNOWN: Failed to fetch <tag>): the same;
#     (c) two digests, the manifest laid down for the index and nothing for
#         the amd64 manifest: one pull for each tag, the amd64 manifest is
#         the digest refused, no warning, no pause, nothing pushed for the
#         index either;
#     (d) one 503, then MANIFEST_UNKNOWN: two pulls, one warning (the first
#         attempt), one pause;
#     (e) two 503s, then MANIFEST_UNKNOWN: three pulls, two warnings, two
#         pauses, the refusal that of the manifest that is not there;
#     (f) three 503s and nothing at the tag, the other cause alone: three
#         pulls, two warnings, two pauses as today, no MANIFEST_UNKNOWN
#         anywhere; of its error line only the frame and the digest are
#         asked here, its words are case 34's.
#     Wanted of each input: exit 1; nothing on stdout; crane pull called for
#     the tag of the digest refused as often as named and crane push never,
#     for any digest; the sleep log byte for byte the lines named (cmp); on
#     stderr one line of crane's per failed pull (begun Error:, the 503s
#     first, then, except in (f), the one that holds MANIFEST_UNKNOWN), one
#     ::warning::unpack-provenance: line per 503 that is tried again, carrying
#     the digest, speaking of the pull and naming its attempt (case 24's
#     patterns), exactly one ::error:: line, the last line of stderr and so
#     below the registry's answer, and no other line; the error line begins
#     ::error::unpack-provenance: <repository>@<the digest refused>: , ends
#     (Req 2.27) and, except in (f), holds the tag and the words no
#     attestation manifest and says that the attestations must exist first
#     (case 14's pattern for that part). One result line per input; on a
#     failure its detail shows what was found against what was wanted
absent_run() { PATH="$SB/bin:$PATH" UNPACK_PROVENANCE_RETRY_DELAY=7 "$UNPACK" "$@" 2> "$SB/stderr"; } # run's PATH, the pause 7 seconds, stdout the output, stderr to a file in the sandbox
absent_input() { # what, the 503s that come first, the words after the code ("" the stub's own), the digest refused, the digests with a manifest laid down (one word, "" none), then the digests given
  local what="$1" fails="$2" words="$3" refused="$4" laid="$5" digest tag tries warns unknown=yes n line which
  local pulls allpulls allwant pushes lines cranes busy busywant answers warned named=0 errors last framed=no reason=no above=no ok=1
  shift 5
  fresh; tag=$(att_tag "$refused")
  for digest in $laid; do lay_down "$(att_tag "$digest")"; done
  # sleep as a log, as in case 29: the word and its arguments, no wait
  cat > "$SB/bin/sleep" <<'STUB'
#!/usr/bin/env bash
SB="$(cd "$(dirname "$0")/.." && pwd)"
{ printf 'sleep'; [ "$#" -eq 0 ] || printf ' %s' "$@"; echo; } >> "$SB/sleep.log"
exit 0
STUB
  chmod +x "$SB/bin/sleep"; : > "$SB/sleep.log"
  # the words another registry puts after the code, in the stub's one line
  [ -z "$words" ] || sed -i "s|MANIFEST_UNKNOWN: manifest unknown|MANIFEST_UNKNOWN: $words|" "$SB/bin/crane"
  echo "$fails" > "$SB/pull-failures"
  # what is wanted: a pull per 503 and one for the registry's answer, three at
  # most; a warning and a pause per failure that is tried again
  tries=$((fails + 1)); busywant="$fails"; [ "$tries" -le 3 ] || { tries=3; busywant=3; unknown=no; }
  warns=$((tries - 1)); allwant=$((tries + $(wc -w <<<"$laid")))
  : > "$SB/sleep.want"; for ((n = 0; n < warns; n++)); do echo "sleep 7" >> "$SB/sleep.want"; done
  out=$(absent_run store "$DATA/bundle.jsonl" "$REPO" "$@"); rc=$?
  pulls=$(grep -c "^crane pull .*:$tag " "$SB/crane.log"); allpulls=$(grep -c '^crane pull' "$SB/crane.log")
  pushes=$(grep -c '^crane push' "$SB/crane.log")
  lines=$(grep -c '' "$SB/stderr"); cranes=$(grep -c '^Error: ' "$SB/stderr")
  busy=$(grep -c '^Error: .*503' "$SB/stderr"); answers=$(grep -c '^Error: .*MANIFEST_UNKNOWN' "$SB/stderr")
  warned=$(grep -c '^::warning::' "$SB/stderr"); errors=$(grep -c '^::error::' "$SB/stderr")
  last=$(tail -n 1 "$SB/stderr")
  # the warning lines in their order, counted as case 24's named_attempts
  # counts them: the unpack's own, the digest, the pull, the attempt
  for ((n = 1; n <= warns; n++)); do
    line=$(grep '^::warning::' "$SB/stderr" | sed -n "${n}p"); which="$first"; [ "$n" -eq 2 ] && which="$second"
    [[ "$line" == "::warning::unpack-provenance: ${REPO}@${refused}: "* ]] \
      && grep -iq -- "pull" <<<"$line" && grep -Eiq -- "$which" <<<"$line" && named=$((named + 1))
  done
  [[ "$last" == "::error::unpack-provenance: ${REPO}@${refused}: "*" (Req 2.27)" ]] && framed=yes
  # the reason and the registry's answer above it; three 503s have neither
  if [ "$unknown" = yes ]; then
    grep -Fq -- "$tag" <<<"$last" && grep -Fiq -- "no attestation manifest" <<<"$last" \
      && grep -Eiq -- 'attestations.*(first|exist)' <<<"$last" && reason=yes
    [ "$answers" -eq 1 ] && [ "$busy" -eq "$busywant" ] && [ "$cranes" -eq "$tries" ] \
      && [ "$(grep '^Error: ' "$SB/stderr" | tail -n 1 | grep -c 'MANIFEST_UNKNOWN')" -eq 1 ] \
      && { [ -z "$words" ] || grep -Fq -- "MANIFEST_UNKNOWN: $words" "$SB/stderr"; } && above=yes
  else
    reason="not asked"
    [ "$answers" -eq 0 ] && [ "$busy" -eq "$busywant" ] && [ "$cranes" -eq "$tries" ] && above=yes
  fi
  [ "$rc" -eq 1 ] && [ -z "$out" ] && [ "$pulls" -eq "$tries" ] && [ "$allpulls" -eq "$allwant" ] && [ "$pushes" -eq 0 ] \
    && cmp -s "$SB/sleep.log" "$SB/sleep.want" && [ "$warned" -eq "$warns" ] && [ "$named" -eq "$warns" ] \
    && [ "$errors" -eq 1 ] && [ "$framed" = yes ] && [ "$reason" != no ] && [ "$above" = yes ] \
    && [ "$lines" -eq "$((tries + warns + 1))" ] || ok=0
  [ "$ok" -eq 1 ] \
    && pass "a manifest that is not there, $what: exit 1, nothing on stdout, $tries crane pull(s) of the tag and no crane push, $warns ::warning:: line(s), $warns pause(s), crane's line of every failed pull on stderr, one ::error::unpack-provenance: line with the digest as the last line" \
    || fail "a manifest that is not there, $what: exit 1, nothing on stdout, $tries crane pull(s) of the tag and no crane push, $warns ::warning:: line(s), $warns pause(s), crane's line of every failed pull on stderr, one ::error:: line as the last line" \
         "exit=$rc, wanted 1" \
         "crane pull calls for the tag $tag: $pulls, wanted $tries; crane pull calls in all: $allpulls, wanted $allwant; crane push calls: $pushes, wanted 0:" "$([ -s "$SB/crane.log" ] && cat "$SB/crane.log" || echo "crane never called")" \
         "sleep calls logged (through cat -A, \$ ends a line):" "$([ -s "$SB/sleep.log" ] && cat -A "$SB/sleep.log" || echo "none")" \
         "sleep calls wanted:" "$([ -s "$SB/sleep.want" ] && cat -A "$SB/sleep.want" || echo "none")" \
         "::warning:: lines on stderr: $warned, wanted $warns, each begun '::warning::unpack-provenance: ${REPO}@${refused}: ', speaking of the pull and naming its attempt (case 24's patterns); lines that do, in their place: $named, wanted $warns" \
         "::error:: lines on stderr: $errors, wanted 1; the last line of stderr begins '::error::unpack-provenance: ${REPO}@${refused}: ' and ends ' (Req 2.27)': $framed, wanted yes" \
         "that line holds the tag '$tag', the words 'no attestation manifest' (any case) and matches 'attestations.*(first|exist)' (any case): $reason, wanted $([ "$unknown" = yes ] && echo yes || echo "not asked")" \
         "crane's lines on stderr (begun 'Error: '): $cranes, wanted $tries; of them with 503: $busy, wanted $busywant; with MANIFEST_UNKNOWN: $answers, wanted $([ "$unknown" = yes ] && echo "1, the last of crane's lines${words:+, holding 'MANIFEST_UNKNOWN: $words'}" || echo 0); as wanted: $above, wanted yes" \
         "lines on stderr in all: $lines, wanted $((tries + warns + 1)) (crane's, the warnings, the error line)" \
         "stderr:" "$([ -s "$SB/stderr" ] && short_lines < "$SB/stderr" || echo "none")" \
         "stdout, wanted none:" "$([ -n "$out" ] && short_lines <<<"$out" || echo "none")"
}
absent_input "(a) nothing at the tag, the first answer is MANIFEST_UNKNOWN" 0 "" "$INDEX" "" "$INDEX"
absent_input "(b) the first answer is MANIFEST_UNKNOWN in another registry's words" 0 "Failed to fetch $(att_tag "$INDEX")" "$INDEX" "" "$INDEX"
absent_input "(c) two digests, the manifest there for the index and not for the amd64 manifest" 0 "" "$AMD64" "$INDEX" "$INDEX" "$AMD64"
absent_input "(d) one 503, then MANIFEST_UNKNOWN" 1 "" "$INDEX" "" "$INDEX"
absent_input "(e) two 503s, then MANIFEST_UNKNOWN" 2 "" "$INDEX" "" "$INDEX"
absent_input "(f) three 503s, the other cause alone" 3 "" "$INDEX" "" "$INDEX"

# 34: a pull that fails three times for another cause says so (plan slice
#     2.9.5; spec FR-1, the clause of 2026-11-18 on a pull that fails three
#     times for any other cause). Case 33 ends a digest at the registry's
#     answer MANIFEST_UNKNOWN with the words that there is no attestation
#     manifest and that the release's other attestations must exist first. A
#     pull that fails three times for another cause (the stub's 503; a refused
#     login and a network failure are the same to the script) has had no such
#     answer: the manifest may well be there, so those words would state
#     something the script does not know. After the third such failure the
#     digest is refused with one ::error:: line that says what is known: it
#     names the digest and the tag and says that the pull failed three times.
#     It does not say that there is no attestation manifest and does not say
#     that the other attestations must exist first. Everything else is as in
#     cases 25, 29 and 33: three pulls of the tag, a warning line and a pause
#     after the first failure and after the second, none after the third,
#     crane's own line of every failed pull passed on, exit 1, nothing on
#     stdout and no push for any digest. The refusal at MANIFEST_UNKNOWN keeps
#     its words, also after one or two 503s: case 33 holds them, inputs (d)
#     and (e). Every input has a sandbox of its own and the fixture's bundle
#     as it is (it names both digests). sleep is case 29's stand-in and the
#     variable is 7, as in case 33, whose absent_run runs the script: stdout
#     is the output, stderr is kept apart in the sandbox. The inputs:
#     (a) nothing at the tag, the first three pulls of the run answered 503
#         (the stub's count): whether a manifest is there was never answered;
#     (b) the manifest laid down at the tag, the same three 503s: the
#         manifest IS there, and today's words say that it is not;
#     (c) two digests, a manifest laid down for each; the pull for the index
#         goes through and every pull of the amd64 manifest's tag is answered
#         503 (a stand-in of this case's own before the stub, which answers
#         503 for that one tag, logs the call like the stub and hands every
#         other call on to the stub): the amd64 manifest is the digest
#         refused, one pull for the index, three for the amd64 manifest,
#         nothing pushed for the index either.
#     Wanted of each input: exit 1; nothing on stdout; crane pull called
#     three times for the tag of the digest refused, in all as often as
#     named, and crane push never; the sleep log byte for byte two lines
#     sleep 7 (cmp); on stderr three lines of crane's (begun Error:, each
#     with 503, none with MANIFEST_UNKNOWN), two ::warning::unpack-provenance:
#     lines carrying the digest, speaking of the pull and naming the first
#     attempt and the second (case 24's patterns), exactly one ::error::
#     line, the last line of stderr, and no other line. The error line begins
#     ::error::unpack-provenance: <repository>@<the digest refused>: and ends
#     (Req 2.27); it holds the tag; what is left of it without that frame and
#     without the tag (the digest and the tag are hex and hold the digit 3)
#     holds the word pull, says that it failed (fail, any case) and holds the
#     number of the attempts as a word of its own (3 or three, any case); the
#     line holds neither no attestation manifest nor must exist first (any
#     case). One result line per input; on a failure its detail shows what
#     was found against what was wanted
busy_input() { # what, the digest refused, the digests with a manifest laid down (one word, "" none), which pulls are answered 503 (count: the first three of the run, by the stub's count; tag: every pull of the refused digest's tag), then the digests given
  local what="$1" refused="$2" laid="$3" how="$4" digest tag n line which rest before=0
  local pulls allpulls allwant pushes lines cranes busy answers warned named=0 errors last framed=no ok=1
  local hastag=no haspull=no hasfail=no hasthree=no absent=no mustfirst=no
  shift 4
  fresh; tag=$(att_tag "$refused")
  for digest in $laid; do lay_down "$(att_tag "$digest")"; done
  # sleep as a log, as in case 29: the word and its arguments, no wait
  cat > "$SB/bin/sleep" <<'STUB'
#!/usr/bin/env bash
SB="$(cd "$(dirname "$0")/.." && pwd)"
{ printf 'sleep'; [ "$#" -eq 0 ] || printf ' %s' "$@"; echo; } >> "$SB/sleep.log"
exit 0
STUB
  chmod +x "$SB/bin/sleep"; : > "$SB/sleep.log"
  if [ "$how" = tag ]; then
    # 503 for one tag alone, each time it is pulled: the stub's line and its
    # log; every other call is the stub's
    mv "$SB/bin/crane" "$SB/bin/crane.stub"
    cat > "$SB/bin/crane" <<'STUB'
#!/usr/bin/env bash
SB="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$1" = pull ]; then
  ref="${*: -2:1}"; tag="${ref##*:}"
  if [ "$tag" = "$(cat "$SB/busy-tag")" ]; then
    printf 'crane %s\n' "$*" >> "$SB/crane.log"
    echo "Error: GET https://${ref%%/*}/v2/.../manifests/$tag: unexpected status code 503 Service Unavailable" >&2; exit 1
  fi
fi
exec "$SB/bin/crane.stub" "$@"
STUB
    chmod +x "$SB/bin/crane"; echo "$tag" > "$SB/busy-tag"
  else
    echo 3 > "$SB/pull-failures"
  fi
  # the pulls wanted in all: three for the digest refused and one for each
  # digest given before it
  for digest in "$@"; do [ "$digest" = "$refused" ] && break; before=$((before + 1)); done
  allwant=$((3 + before))
  printf 'sleep 7\nsleep 7\n' > "$SB/sleep.want"
  out=$(absent_run store "$DATA/bundle.jsonl" "$REPO" "$@"); rc=$?
  pulls=$(grep -c "^crane pull .*:$tag " "$SB/crane.log"); allpulls=$(grep -c '^crane pull' "$SB/crane.log")
  pushes=$(grep -c '^crane push' "$SB/crane.log")
  lines=$(grep -c '' "$SB/stderr"); cranes=$(grep -c '^Error: ' "$SB/stderr")
  busy=$(grep -c '^Error: .*503' "$SB/stderr"); answers=$(grep -c 'MANIFEST_UNKNOWN' "$SB/stderr")
  warned=$(grep -c '^::warning::' "$SB/stderr"); errors=$(grep -c '^::error::' "$SB/stderr")
  last=$(tail -n 1 "$SB/stderr")
  # the two warning lines in their order, counted as in case 33
  for ((n = 1; n <= 2; n++)); do
    line=$(grep '^::warning::' "$SB/stderr" | sed -n "${n}p"); which="$first"; [ "$n" -eq 2 ] && which="$second"
    [[ "$line" == "::warning::unpack-provenance: ${REPO}@${refused}: "* ]] \
      && grep -iq -- "pull" <<<"$line" && grep -Eiq -- "$which" <<<"$line" && named=$((named + 1))
  done
  [[ "$last" == "::error::unpack-provenance: ${REPO}@${refused}: "*" (Req 2.27)" ]] && framed=yes
  # the reason: the tag on the line; the pull, its failing and the three
  # attempts in what is left without the frame and the tag, whose hex digits
  # would stand in for the 3
  grep -Fq -- "$tag" <<<"$last" && hastag=yes
  rest="${last#"::error::unpack-provenance: ${REPO}@${refused}: "}"; rest="${rest%" (Req 2.27)"}"; rest="${rest//"$tag"/}"
  [ "$framed" = yes ] || rest=""
  grep -Eiq -- '(^|[^[:alnum:]])pull([^[:alnum:]]|$)' <<<"$rest" && haspull=yes
  grep -Fiq -- "fail" <<<"$rest" && hasfail=yes
  grep -Eiq -- '(^|[^[:alnum:]])(3|three)([^[:alnum:]]|$)' <<<"$rest" && hasthree=yes
  grep -Fiq -- "no attestation manifest" <<<"$last" && absent=yes
  grep -Fiq -- "must exist first" <<<"$last" && mustfirst=yes
  [ "$rc" -eq 1 ] && [ -z "$out" ] && [ "$pulls" -eq 3 ] && [ "$allpulls" -eq "$allwant" ] && [ "$pushes" -eq 0 ] \
    && cmp -s "$SB/sleep.log" "$SB/sleep.want" && [ "$warned" -eq 2 ] && [ "$named" -eq 2 ] \
    && [ "$cranes" -eq 3 ] && [ "$busy" -eq 3 ] && [ "$answers" -eq 0 ] \
    && [ "$errors" -eq 1 ] && [ "$framed" = yes ] && [ "$lines" -eq 6 ] \
    && [ "$hastag" = yes ] && [ "$haspull" = yes ] && [ "$hasfail" = yes ] && [ "$hasthree" = yes ] \
    && [ "$absent" = no ] && [ "$mustfirst" = no ] || ok=0
  [ "$ok" -eq 1 ] \
    && pass "a pull that fails three times for another cause, $what: exit 1, nothing on stdout, 3 crane pulls of the tag and no crane push, 2 ::warning:: lines, 2 pauses, one ::error::unpack-provenance: line with the digest as the last line, which holds the tag and says that the pull failed 3 times, and says neither that there is no attestation manifest nor that the other attestations must exist first" \
    || fail "a pull that fails three times for another cause, $what: exit 1, one ::error:: line that holds the tag and says that the pull failed 3 times, not that there is no attestation manifest, not that the other attestations must exist first" \
         "exit=$rc, wanted 1" \
         "the last line of stderr: ${last:-none}" \
         "it begins '::error::unpack-provenance: ${REPO}@${refused}: ' and ends ' (Req 2.27)': $framed, wanted yes; ::error:: lines on stderr: $errors, wanted 1" \
         "it holds the tag '$tag': $hastag, wanted yes" \
         "without that frame and the tag it holds the word 'pull' (any case): $haspull, wanted yes; 'fail' (any case): $hasfail, wanted yes; the attempts as a word of its own, '3' or 'three' (any case): $hasthree, wanted yes" \
         "it holds 'no attestation manifest' (any case): $absent, wanted no; it holds 'must exist first' (any case): $mustfirst, wanted no" \
         "crane pull calls for the tag $tag: $pulls, wanted 3; crane pull calls in all: $allpulls, wanted $allwant; crane push calls: $pushes, wanted 0:" "$([ -s "$SB/crane.log" ] && cat "$SB/crane.log" || echo "crane never called")" \
         "sleep calls logged (through cat -A, \$ ends a line):" "$([ -s "$SB/sleep.log" ] && cat -A "$SB/sleep.log" || echo "none")" \
         "sleep calls wanted:" "$(cat -A "$SB/sleep.want")" \
         "::warning:: lines on stderr: $warned, wanted 2, each begun '::warning::unpack-provenance: ${REPO}@${refused}: ', speaking of the pull and naming its attempt (case 24's patterns); lines that do, in their place: $named, wanted 2" \
         "crane's lines on stderr (begun 'Error: '): $cranes, wanted 3; of them with 503: $busy, wanted 3; lines of stderr with MANIFEST_UNKNOWN: $answers, wanted 0" \
         "lines on stderr in all: $lines, wanted 6 (crane's three, the two warnings, the error line)" \
         "stderr:" "$([ -s "$SB/stderr" ] && short_lines < "$SB/stderr" || echo "none")" \
         "stdout, wanted none:" "$([ -n "$out" ] && short_lines <<<"$out" || echo "none")"
}
busy_input "(a) three 503s, nothing at the tag" "$INDEX" "" count "$INDEX"
busy_input "(b) three 503s, the manifest laid down at the tag" "$INDEX" "$INDEX" count "$INDEX"
busy_input "(c) two digests with their manifests laid down, every pull for the amd64 manifest answered 503" "$AMD64" "$INDEX $AMD64" tag "$INDEX" "$AMD64"

# 35: a manifest rewritten since the pull is not overwritten (plan slice
#     2.9.6; spec FR-1, the clause of 2026-11-18 on a second writer). store
#     pulls the attestation manifest of a digest, rewrites it in a working
#     directory with the provenance layer appended and pushes the result back
#     to the same tag. Another writer (the rescan's cosign attest --replace, a
#     second release run) can write that tag between the pull and the push:
#     the push then puts back a manifest built from the old one and the other
#     writer's layer is gone. The registry has no conditional write, so the
#     script closes what it can: immediately before the push of each digest it
#     asks the registry for the digest the tag points at now, with
#     crane digest <repository>:sha256-<hex>.att and nothing else on that
#     line, and compares the answer with the digest of the manifest it
#     pulled. Equal: the push goes ahead. Not equal: the prepared layout is
#     not pushed; one ::warning::unpack-provenance: <repository>@<digest>: ...
#     line says that the attestation manifest at the tag has changed since it
#     was read and that it is prepared again; the digest is prepared again
#     from the manifest now at the tag (pulled anew, the provenance layer
#     appended to that manifest, a stale provenance layer in it taken out as
#     always), the tag is asked again, and when the answer is the manifest
#     just pulled, that layout is pushed. No pause lies before a repeated
#     preparation: the other writer is done, a pause only widens the window.
#     A question that fails is treated like a pull that fails: tried again up
#     to three attempts, a warning line and the pause after each failure that
#     is tried again, and the answer MANIFEST_UNKNOWN (the tag has vanished)
#     refuses the digest at once in case 33's words. What happens when the
#     manifest has changed again at every attempt is the next slice's (2.9.7)
#     and no input here reaches it: the other writer writes once.
#     The stub stands in for the other writer (see fresh): a layout put at
#     rewrite/<tag> is moved over the tag's layout right after a pull of that
#     tag is served, a file remove/<tag> has the tag's layout removed at that
#     moment, and digest-failures counts the questions answered 503. The
#     other writer's layout is lay_down's, with the SBOM layer the first
#     layout has and a CycloneDX layer after it, so its manifest is another
#     one. Every input has a sandbox of its own, the fixture's bundle as it
#     is (it names both digests), the one SBOM layer laid down at the tag of
#     every digest given, sleep as case 29's stand-in and the variable 7
#     (case 33's absent_run: stdout is the output, stderr is kept apart).
#     The order of the crane calls is held as a whole, each call reduced to
#     its subcommand and the digest whose tag it names:
#     (a) one digest, nothing else writes: pull, digest, push;
#     (b) one digest, rewritten once between the pull and the question:
#         pull, digest, pull, digest, push;
#     (c) two digests, the index and the amd64 manifest, of which only the
#         second is rewritten: pull index, pull amd64, digest index, push
#         index, digest amd64, pull amd64, digest amd64, push amd64. This
#         order and no other, because every digest is prepared before the
#         first push (cases 19 and 20, all or nothing), the question stands
#         immediately before the push it guards (asked for both digests ahead
#         of the first push, the second answer would be older than it need
#         be), and a digest whose manifest did not change is pushed from its
#         first preparation: one pull of the index's tag, no more;
#     (d) as (b), the other writer's manifest holding a provenance layer of
#         an earlier run between its two layers: that layer is taken out,
#         exactly one provenance layer is pushed;
#     (e) the first question answered 503, the second answered: pull, digest,
#         digest, push, one warning line that names the first attempt, one
#         pause;
#     (f) the tag gone after the pull, the question answered
#         MANIFEST_UNKNOWN: pull, digest, and the digest is refused at once;
#     (g) the question answered 503 three times: pull, digest, digest,
#         digest, two warning lines, two pauses, and the digest is refused.
#     Wanted of each input: the exit code (0, and 1 in (f) and (g)); the
#     crane calls in the order named and every digest call the line
#     crane digest <repository>:<tag> and nothing else; stdout the usual line
#     of every digest stored, in the order given, and nothing else; the sleep
#     log byte for byte one line sleep 7 per 503 that is tried again (cmp),
#     so none for a repeated preparation; on stderr one line of crane's per
#     failed question, one ::warning::unpack-provenance: line per 503 that is
#     tried again (begun with the repository and the digest, holding the tag,
#     naming its attempt by case 24's patterns), for a rewritten digest
#     exactly one ::warning::unpack-provenance: line begun with the
#     repository and that digest which speaks of the manifest, says that it
#     changed (chang, rewritten, no longer or differ, any case) and that it
#     is prepared again (again or anew, any case), no other warning line, and
#     no ::error:: line where the run ends 0. A digest refused has exactly
#     one ::error:: line, the last line of stderr, begun
#     ::error::unpack-provenance: <repository>@<digest>: and ended
#     (Req 2.27), holding the tag; in (f) it holds the words no attestation
#     manifest and says that the attestations must exist first (case 33's
#     patterns); in (g) what is left of it without that frame and the tag
#     says that something failed (fail, any case) and holds the three
#     attempts as a word of its own (3 or three), as case 34 asks of a pull,
#     and the line does not say no attestation manifest; nothing is pushed
#     for it. At the tag of every digest stored the manifest pushed holds,
#     before its last layer, the layers of the manifest that was at the tag
#     when it was last pulled, descriptor for descriptor and in their order
#     (the other writer's where it wrote, without a provenance layer of an
#     earlier run; the layers laid down elsewhere), its last layer is the
#     envelope the log recorded, exactly one layer is of the provenance type,
#     and the config pushed lists these layers: rootfs.diff_ids their digests
#     in order, history one entry per layer. One result line per input; on a
#     failure its detail shows what was found against what was wanted
rewritten_name() { case "$1" in "$INDEX") echo index ;; "$AMD64") echo amd64 ;; *) echo "$1" ;; esac; } # a digest's short name for the order of the calls
rewritten_input() { # what, the digest whose manifest is rewritten right after its pull ("" none), the predicate types of the other writer's layers (one word), the digest whose tag is gone right after its pull ("" none), the questions answered 503 before one is answered, then the digests given
  local what="$1" rewritten="$2" types="$3" vanished="$4" fails="$5" digest tag name n line which rest sub ref
  local code=0 busywant warns denied="" provenance moved=yes calls odd only=() stdoutwant
  local lines cranes craneswant busy answers answerswant=0 warned warnedwant named=0 changed=0 changedwant=0 errors errorswant=0 last framed="not asked" reason="not asked"
  local pushed manifest want got lastlayer typed listed layersd entries stored=0 storedwant=0 tags=() ok=1
  shift 5
  fresh; mkdir -p "$SB/rewrite" "$SB/remove"
  # sleep as a log, as in case 29: the word and its arguments, no wait
  cat > "$SB/bin/sleep" <<'STUB'
#!/usr/bin/env bash
SB="$(cd "$(dirname "$0")/.." && pwd)"
{ printf 'sleep'; [ "$#" -eq 0 ] || printf ' %s' "$@"; echo; } >> "$SB/sleep.log"
exit 0
STUB
  chmod +x "$SB/bin/sleep"; : > "$SB/sleep.log"
  provenance="sha256:$(logged_hash)"
  # the questions that are answered 503, three at most, and the warnings and
  # pauses for those of them that are tried again
  busywant="$fails"; [ "$fails" -lt 3 ] || busywant=3
  warns="$fails"; [ "$fails" -lt 3 ] || warns=2
  : > "$SB/sleep.want"; for ((n = 0; n < warns; n++)); do echo "sleep 7" >> "$SB/sleep.want"; done
  # laid down per digest: the one SBOM layer at its tag; for the digest that
  # is rewritten the other writer's layout first, put aside for the stub. The
  # layers wanted before the provenance layer are kept per digest as a file:
  # those of the manifest that is at the tag when it is last pulled
  for digest in "$@"; do
    tag=$(att_tag "$digest"); name=$(rewritten_name "$digest")
    if [ "$digest" = "$rewritten" ]; then
      # shellcheck disable=SC2086 # the types are words on purpose
      lay_down "$tag" $types; mv "$SB/registry/$tag" "$SB/rewrite/$tag"
      manifest_of "$SB/rewrite/$tag" | jq -S --arg type "$slsa" '[.layers[] | select(.annotations.predicateType != $type)]' > "$SB/layers.want.$name"
    fi
    lay_down "$tag"
    [ "$digest" = "$rewritten" ] || manifest_of "$SB/registry/$tag" | jq -S '.layers' > "$SB/layers.want.$name"
    [ "$digest" != "$vanished" ] || : > "$SB/remove/$tag"
    only+=(-e "crane digest $REPO:$tag")
  done
  echo "$fails" > "$SB/digest-failures"
  # the calls wanted, in their order: every pull first, then per digest its
  # question (the 503s come to the first digest asked) and its push, and for
  # the digest rewritten a second pull and a second question between the two.
  # A digest refused ends the list, and stdout holds the digests before it
  : > "$SB/calls.want"; : > "$SB/stdout.want"
  for digest in "$@"; do echo "pull $(rewritten_name "$digest")" >> "$SB/calls.want"; done
  n=0
  for digest in "$@"; do
    tag=$(att_tag "$digest"); name=$(rewritten_name "$digest")
    if [ "$n" -eq 0 ]; then
      for ((n = 0; n < busywant; n++)); do echo "digest $name" >> "$SB/calls.want"; done
      n=1
      [ "$fails" -lt 3 ] || { denied="$digest"; break; }
    fi
    echo "digest $name" >> "$SB/calls.want"
    [ "$digest" != "$vanished" ] || { denied="$digest"; answerswant=1; break; }
    [ "$digest" != "$rewritten" ] || { printf 'pull %s\ndigest %s\n' "$name" "$name" >> "$SB/calls.want"; changedwant=1; }
    echo "push $name" >> "$SB/calls.want"
    echo "unpack-provenance: ${REPO}@${digest}: provenance stored as layer $provenance of ${REPO}:${tag}" >> "$SB/stdout.want"
    storedwant=$((storedwant + 1))
  done
  [ -z "$denied" ] || { code=1; errorswant=1; }
  stdoutwant=$(cat "$SB/stdout.want")
  warnedwant=$((warns + changedwant)); craneswant=$((busywant + answerswant))

  out=$(absent_run store "$DATA/bundle.jsonl" "$REPO" "$@"); rc=$?

  # the other writer has written: the stub moved its layout to the tag
  [ -z "$rewritten" ] || [ ! -e "$SB/rewrite/$(att_tag "$rewritten")" ] || moved=no
  [ -z "$vanished" ] || [ ! -e "$SB/remove/$(att_tag "$vanished")" ] || moved=no
  # the calls as logged, each reduced to its subcommand and the digest whose
  # tag it names; the digest calls also as whole lines
  calls=$(while read -r _ sub rest; do
    ref=$(tr ' ' '\n' <<<"$rest" | grep -F -- "$REPO:" | head -n 1); name="${ref#"$REPO:"}"
    for digest in "$@"; do [ "$name" != "$(att_tag "$digest")" ] || name=$(rewritten_name "$digest"); done
    echo "$sub ${name:-no reference}"
  done < "$SB/crane.log")
  odd=$(grep '^crane digest' "$SB/crane.log" | grep -vxF "${only[@]}")
  lines=$(grep -c '' "$SB/stderr"); cranes=$(grep -c '^Error: ' "$SB/stderr")
  busy=$(grep -c '^Error: .*503' "$SB/stderr"); answers=$(grep -c '^Error: .*MANIFEST_UNKNOWN' "$SB/stderr")
  warned=$(grep -c '^::warning::' "$SB/stderr"); errors=$(grep -c '^::error::' "$SB/stderr")
  last=$(tail -n 1 "$SB/stderr")
  # the warning lines of the questions answered 503, the first lines begun
  # ::warning:: in their order: the first digest given, its tag, the attempt
  for ((n = 1; n <= warns; n++)); do
    line=$(grep '^::warning::' "$SB/stderr" | sed -n "${n}p"); which="$first"; [ "$n" -eq 2 ] && which="$second"
    [[ "$line" == "::warning::unpack-provenance: ${REPO}@$1: "* ]] \
      && grep -Fq -- "$(att_tag "$1")" <<<"$line" && grep -Eiq -- "$which" <<<"$line" && named=$((named + 1))
  done
  # the warning line of a manifest that has changed: the digest rewritten,
  # the manifest, that it changed, that it is prepared again
  [ -z "$rewritten" ] || changed=$(grep -F -- "::warning::unpack-provenance: ${REPO}@${rewritten}: " "$SB/stderr" \
    | grep -i -- 'manifest' | grep -Ei -- 'chang|rewritten|no longer|differ' | grep -Eic -- 'again|anew')
  # the error line of a digest refused: framed, the tag, and the reason
  if [ -n "$denied" ]; then
    tag=$(att_tag "$denied"); framed=no; reason=no
    [[ "$last" == "::error::unpack-provenance: ${REPO}@${denied}: "*" (Req 2.27)" ]] && grep -Fq -- "$tag" <<<"$last" && framed=yes
    if [ "$denied" = "$vanished" ]; then
      grep -Fiq -- "no attestation manifest" <<<"$last" && grep -Eiq -- 'attestations.*(first|exist)' <<<"$last" && reason=yes
    else
      rest="${last#"::error::unpack-provenance: ${REPO}@${denied}: "}"; rest="${rest%" (Req 2.27)"}"; rest="${rest//"$tag"/}"
      [ "$framed" = yes ] && grep -Fiq -- "fail" <<<"$rest" && grep -Eiq -- '(^|[^[:alnum:]])(3|three)([^[:alnum:]]|$)' <<<"$rest" \
        && ! grep -Fiq -- "no attestation manifest" <<<"$last" && reason=yes
    fi
  fi
  # what was pushed, per digest: a digest refused, and every digest after it,
  # has nothing at its tag; a digest stored has the layers wanted, then the
  # one provenance layer, and a config that lists them
  n=0
  for digest in "$@"; do
    tag=$(att_tag "$digest"); name=$(rewritten_name "$digest"); pushed="$SB/pushed/$tag"
    [ "$digest" != "$denied" ] || n=1
    if [ "$n" -eq 1 ]; then
      [ ! -e "$pushed" ] || { ok=0; tags+=("$name: something was pushed to $tag, wanted nothing: the digest is refused or stands after the one refused"); }
      continue
    fi
    manifest=""; [ -f "$pushed/index.json" ] && manifest=$(manifest_of "$pushed")
    want=$(cat "$SB/layers.want.$name")
    got=$(jq -S '.layers[:-1]' <<<"$manifest" 2>/dev/null)
    lastlayer=$(jq -r '.layers[-1].digest' <<<"$manifest" 2>/dev/null)
    typed=$(jq -c --arg type "$slsa" '[.layers[] | select(.annotations.predicateType == $type) | .digest]' <<<"$manifest" 2>/dev/null)
    layersd=$(jq -c '[.layers[].digest]' <<<"$manifest" 2>/dev/null)
    listed=$(config_of "$pushed" | jq -c '.rootfs.diff_ids' 2>/dev/null)
    entries=$(config_of "$pushed" | jq '.history | length' 2>/dev/null)
    if [ -n "$manifest" ] && [ -n "$got" ] && [ "$got" = "$want" ] && [ "$lastlayer" = "$provenance" ] && [ "$typed" = "[\"$provenance\"]" ] \
      && [ -n "$listed" ] && [ "$listed" = "$layersd" ] && [ "$entries" = "$(jq 'length' <<<"$layersd")" ]; then
      stored=$((stored + 1)); continue
    fi
    tags+=("$name, pushed to $tag, not as wanted:" \
           "  layers before the last:" "$([ -n "$manifest" ] && jq -c '.layers[:-1][] | "    \(.annotations.predicateType) \(.digest)"' -r <<<"$manifest" || echo "    nothing was pushed to the tag")" \
           "  wanted, descriptor for descriptor:" "$(jq -r '.[] | "    \(.annotations.predicateType) \(.digest)"' <<<"$want")" \
           "  last layer: ${lastlayer:-none}, wanted $provenance; layers of the provenance type: ${typed:-none}, wanted [\"$provenance\"]" \
           "  rootfs.diff_ids of the config pushed: ${listed:-no config to read}" "  the manifest's layers' digests:       ${layersd:-none}" \
           "  history entries: ${entries:-none}, wanted one per layer")
  done
  [ "$moved" = yes ] && [ "$rc" -eq "$code" ] && [ "$calls" = "$(cat "$SB/calls.want")" ] && [ -z "$odd" ] && [ "$out" = "$stdoutwant" ] \
    && cmp -s "$SB/sleep.log" "$SB/sleep.want" && [ "$cranes" -eq "$craneswant" ] && [ "$busy" -eq "$busywant" ] && [ "$answers" -eq "$answerswant" ] \
    && [ "$warned" -eq "$warnedwant" ] && [ "$named" -eq "$warns" ] && [ "$changed" -eq "$changedwant" ] \
    && [ "$errors" -eq "$errorswant" ] && [ "$framed" != no ] && [ "$reason" != no ] \
    && [ "$lines" -eq "$((craneswant + warnedwant + errorswant))" ] && [ "$stored" -eq "$storedwant" ] || ok=0
  [ "$ok" -eq 1 ] \
    && pass "a manifest rewritten since the pull is not overwritten, $what: exit $code, the crane calls in their order ($(tr '\n' ',' < "$SB/calls.want" | sed 's/,$//; s/,/, /g')), $warnedwant ::warning:: line(s), $warns pause(s), $errorswant ::error:: line(s), $storedwant digest(s) stored, each with the layers of the manifest last pulled and one provenance layer, the last" \
    || fail "a manifest rewritten since the pull is not overwritten, $what: exit $code, the crane calls in their order, $warnedwant ::warning:: line(s), $warns pause(s), $errorswant ::error:: line(s), $storedwant digest(s) stored with the layers of the manifest last pulled and one provenance layer" \
         "exit=$rc, wanted $code" \
         "crane calls, each as its subcommand and the digest whose tag it names:" "$([ -n "$calls" ] && sed 's/^/  /' <<<"$calls" || echo "  crane never called")" \
         "wanted, in this order:" "$(sed 's/^/  /' "$SB/calls.want")" \
         "crane digest calls that are not the line 'crane digest $REPO:<the tag of a digest given>', wanted none:" "${odd:-none}" \
         "the calls as logged:" "$([ -s "$SB/crane.log" ] && short_lines < "$SB/crane.log" || echo "crane never called")" \
         "stdout:" "$([ -n "$out" ] && short_lines <<<"$out" || echo "nothing")" "wanted:" "${stdoutwant:-nothing}" \
         "sleep calls logged (through cat -A, \$ ends a line):" "$([ -s "$SB/sleep.log" ] && cat -A "$SB/sleep.log" || echo "none")" \
         "sleep calls wanted (one per 503 that is tried again, none for a repeated preparation):" "$([ -s "$SB/sleep.want" ] && cat -A "$SB/sleep.want" || echo "none")" \
         "::warning:: lines on stderr: $warned, wanted $warnedwant" \
         "of them for a question that failed, begun '::warning::unpack-provenance: ${REPO}@$1: ', holding the tag and naming the attempt (case 24's patterns), in their place: $named, wanted $warns" \
         "lines begun '::warning::unpack-provenance: ${REPO}@${rewritten:-<no digest is rewritten>}: ' that speak of the manifest, say that it changed ('chang', 'rewritten', 'no longer' or 'differ', any case) and that it is prepared again ('again' or 'anew', any case): $changed, wanted $changedwant" \
         "::error:: lines on stderr: $errors, wanted $errorswant; the last line of stderr begins '::error::unpack-provenance: ${REPO}@${denied:-<no digest is refused>}: ', ends ' (Req 2.27)' and holds the tag: $framed, wanted $([ -n "$denied" ] && echo yes || echo "not asked")" \
         "its reason ($([ "$denied" = "$vanished" ] && echo "'no attestation manifest' and 'attestations.*(first|exist)', any case" || echo "without the frame and the tag 'fail' and '3' or 'three' as a word of its own, any case, and not 'no attestation manifest'")): $reason, wanted $([ -n "$denied" ] && echo yes || echo "not asked")" \
         "crane's lines on stderr (begun 'Error: '): $cranes, wanted $craneswant; of them with 503: $busy, wanted $busywant; with MANIFEST_UNKNOWN: $answers, wanted $answerswant" \
         "lines on stderr in all: $lines, wanted $((craneswant + warnedwant + errorswant)) (crane's, the warnings, the error line)" \
         "the other writer wrote (the stub moved the layout at rewrite/, or removed the tag): $moved, wanted yes" \
         "digests stored as wanted: $stored, wanted $storedwant" "${tags[@]}" \
         "stderr:" "$([ -s "$SB/stderr" ] && short_lines < "$SB/stderr" || echo "none")"
}
cyclonedx="https://cyclonedx.org/bom"
rewritten_input "(a) one digest, nothing else writes" "" "" "" 0 "$INDEX"
rewritten_input "(b) one digest, rewritten once between the pull and the question" "$INDEX" "https://spdx.dev/Document $cyclonedx" "" 0 "$INDEX"
rewritten_input "(c) two digests, only the second rewritten" "$AMD64" "https://spdx.dev/Document $cyclonedx" "" 0 "$INDEX" "$AMD64"
rewritten_input "(d) the manifest rewritten holds a provenance layer of an earlier run" "$INDEX" "https://spdx.dev/Document $slsa $cyclonedx" "" 0 "$INDEX"
rewritten_input "(e) the question answered 503 once, then answered" "" "" "" 1 "$INDEX"
rewritten_input "(f) the tag gone after the pull, the question answered MANIFEST_UNKNOWN" "" "" "$INDEX" 0 "$INDEX"
rewritten_input "(g) the question answered 503 three times" "" "" "" 3 "$INDEX"

# 36: a manifest that keeps changing is refused by name (plan slice 2.9.7;
#     spec FR-1, the clause of 2026-11-18 on a second writer, its second
#     half). Since case 35 store asks the tag for its digest right before
#     each push, and a manifest that is no longer the one pulled is said with
#     one warning line, the digest prepared again from the manifest now there
#     and the tag asked again. That must end: a manifest that has changed at
#     THREE questions in a row for one digest (the first preparation and two
#     repeated ones, each found stale) is not prepared a fourth time. The
#     digest is refused: exit 1; exactly one ::error:: line, the last line of
#     stderr, begun ::error::unpack-provenance: <repository>@<digest>: and
#     ended (Req 2.27), holding the tag; what is left of it without that
#     frame and the tag says that the manifest changed (chang, rewritten, no
#     longer or differ, any case) and holds the number of questions as a word
#     of its own (3 or three). Before it stand exactly two warning lines of
#     case 35's kind, one per repeated preparation, and no third one: the
#     third stale answer is the refusal, nothing is prepared after it. The
#     crane calls for that tag are pull, digest, pull, digest, pull, digest
#     and no push: the layout of the third preparation is as stale as the two
#     before it. No pause anywhere (sleep is never called: the other writer
#     is done each time, a pause only widens the window), and stdout says
#     nothing of that digest.
#     The stub stands in for the other writer (see fresh): the layouts put at
#     rewrite/<tag>.1, rewrite/<tag>.2, ... are moved over the tag's layout
#     in turn, one right after each pull of that tag is served, until none is
#     left. Writer n's layout is lay_down's with the SBOM layer and a layer
#     of a type of its own (https://example.test/writer/<digest>/<n>, the
#     digest by its short name), so every write
#     is another manifest and the layers pushed tell whose manifest the
#     layout was prepared from. Every input has a sandbox of its own, the
#     fixture's bundle as it is, the one SBOM layer laid down at the tag of
#     every digest given, sleep as case 29's stand-in and the variable 7
#     (case 33's absent_run). The inputs:
#     (a) one digest, the other writer writes after every pull (five layouts
#         wait, more than the script may use: three are taken): refused as
#         above;
#     (b) one digest, the manifest changes twice and then holds still: it is
#         stored. pull, digest, pull, digest, pull, digest, push; two warning
#         lines, no error line, exit 0, the usual line on stdout, and what is
#         pushed holds the last writer's layers before the provenance layer;
#     (c) two digests, the index in order and the amd64 manifest changing
#         after every pull: pull index, pull amd64, digest index, push index,
#         digest amd64, pull amd64, digest amd64, pull amd64, digest amd64.
#         The index IS pushed and its line stands on stdout before the amd64
#         manifest is refused, because each tag is asked right before its own
#         push (case 35, (c)): all or nothing across the digests (cases 19
#         and 20) holds for the first preparation only, a refusal at a
#         question or at a repeated preparation comes when the digests before
#         it are stored. Nothing is pushed to the amd64 manifest's tag;
#     (d) one digest, the manifest changes three times and would hold still
#         at a fourth question: refused as in (a), the fourth question is
#         never asked (exactly three layouts wait, all three are taken);
#     (e) two digests, the manifest of each changes twice and then holds
#         still: both are stored, with four warning lines, two per digest.
#         The three questions are counted per digest and in a row: the
#         changes at one digest's tag take nothing from the next digest's
#         attempts.
#     Wanted of each input besides: every digest call the line
#     crane digest <repository>:<tag> and nothing else; stderr holds the
#     warning lines and the error line and no other line; the other writer
#     wrote as often as the tag was pulled, three times at most. At the tag
#     of every digest stored the manifest pushed holds, before its last
#     layer, the layers of the manifest that was at the tag when it was last
#     pulled, descriptor for descriptor, its last layer is the envelope the
#     log recorded, exactly one layer is of the provenance type and the
#     config pushed lists these layers. One result line per input; on a
#     failure its detail shows what was found against what was wanted
changing_input() { # what, the digests whose manifests the other writer keeps writing (one word), how many layouts that writer has waiting for each of them (one word, in their order; one is written right after each pull of the tag), then the digests given
  local what="$1" changing="$2" writes="$3" digest tag name n sub rest ref w cd cw
  local -A queue=()
  local code=0 stale warns warnswant=0 denied="" provenance calls odd only=() stdoutwant left wrote writers=() writersok=yes
  local lines warned changed changes=() changedok=yes errors errorswant=0 last framed="not asked" reason="not asked" pushes
  local pushed manifest want got lastlayer typed listed layersd entries stored=0 storedwant=0 tags=() ok=1
  shift 3
  fresh; mkdir -p "$SB/rewrite"
  # sleep as a log, as in case 29: the word and its arguments, no wait
  cat > "$SB/bin/sleep" <<'STUB'
#!/usr/bin/env bash
SB="$(cd "$(dirname "$0")/.." && pwd)"
{ printf 'sleep'; [ "$#" -eq 0 ] || printf ' %s' "$@"; echo; } >> "$SB/sleep.log"
exit 0
STUB
  chmod +x "$SB/bin/sleep"; : > "$SB/sleep.log"
  provenance="sha256:$(logged_hash)"
  read -ra cd <<<"$changing"; read -ra cw <<<"$writes"
  for n in "${!cd[@]}"; do queue[${cd[$n]}]="${cw[$n]}"; done
  # laid down per digest: the one SBOM layer at its tag; for the digest that
  # keeps changing the other writer's layouts first, numbered, put aside for
  # the stub. The layers wanted before the provenance layer are kept per
  # digest as a file: those of the manifest at the tag when it is last pulled
  for digest in "$@"; do
    tag=$(att_tag "$digest"); name=$(rewritten_name "$digest")
    # per digest the questions that find its manifest changed, three at most
    w="${queue[$digest]:-0}"; stale="$w"; [ "$w" -lt 3 ] || stale=3
    for ((n = 1; n <= w; n++)); do
      lay_down "$tag" "https://spdx.dev/Document" "https://example.test/writer/$name/$n"; mv "$SB/registry/$tag" "$SB/rewrite/$tag.$n"
    done
    lay_down "$tag"
    if [ "$w" -gt 0 ]; then
      manifest_of "$SB/rewrite/$tag.$stale" | jq -S '.layers' > "$SB/layers.want.$name"
    else
      manifest_of "$SB/registry/$tag" | jq -S '.layers' > "$SB/layers.want.$name"
    fi
    only+=(-e "crane digest $REPO:$tag")
  done
  # the calls wanted, in their order: every pull first, then per digest its
  # question and its push, and for a digest that keeps changing a pull and a
  # question more per repeated preparation (two at most, each with its
  # warning line); at the third question that finds the manifest changed the
  # list ends, with no push for that digest
  : > "$SB/calls.want"; : > "$SB/stdout.want"
  for digest in "$@"; do echo "pull $(rewritten_name "$digest")" >> "$SB/calls.want"; done
  for digest in "$@"; do
    tag=$(att_tag "$digest"); name=$(rewritten_name "$digest")
    echo "digest $name" >> "$SB/calls.want"
    w="${queue[$digest]:-0}"; warns="$w"; [ "$w" -lt 2 ] || warns=2
    for ((n = 0; n < warns; n++)); do printf 'pull %s\ndigest %s\n' "$name" "$name" >> "$SB/calls.want"; done
    warnswant=$((warnswant + warns))
    [ "$w" -lt 3 ] || { denied="$digest"; break; }
    echo "push $name" >> "$SB/calls.want"
    echo "unpack-provenance: ${REPO}@${digest}: provenance stored as layer $provenance of ${REPO}:${tag}" >> "$SB/stdout.want"
    storedwant=$((storedwant + 1))
  done
  [ -z "$denied" ] || { code=1; errorswant=1; }
  stdoutwant=$(cat "$SB/stdout.want")

  out=$(absent_run store "$DATA/bundle.jsonl" "$REPO" "$@"); rc=$?

  # per digest whose manifest keeps changing: the other writer's writes (the
  # layouts the stub took from the queue: one per pull of the tag, three at
  # most, and one for a digest that stands after the one refused), and its
  # warning lines, case 35's: the digest, the manifest, that it changed, that
  # it is prepared again (two at most, none after the digest refused)
  n=0
  for digest in "$@"; do
    w="${queue[$digest]:-0}"; [ "$w" -gt 0 ] || continue
    tag=$(att_tag "$digest"); name=$(rewritten_name "$digest")
    stale="$w"; [ "$w" -lt 3 ] || stale=3
    warns="$w"; [ "$w" -lt 2 ] || warns=2
    [ "$n" -eq 0 ] || { stale=1; warns=0; }
    left=$(find "$SB/rewrite" -mindepth 1 -maxdepth 1 -name "$tag.*" | grep -c '')
    wrote=$((w - left)); [ "$wrote" -eq "$stale" ] || writersok=no
    writers+=("  $name: $wrote, wanted $stale")
    changed=$(grep -F -- "::warning::unpack-provenance: ${REPO}@${digest}: " "$SB/stderr" \
      | grep -i -- 'manifest' | grep -Ei -- 'chang|rewritten|no longer|differ' | grep -Eic -- 'again|anew')
    [ "$changed" -eq "$warns" ] || changedok=no
    changes+=("  $name: $changed, wanted $warns")
    [ "$digest" != "$denied" ] || n=1
  done
  # the calls as logged, each reduced to its subcommand and the digest whose
  # tag it names; the digest calls also as whole lines
  calls=$(while read -r _ sub rest; do
    ref=$(tr ' ' '\n' <<<"$rest" | grep -F -- "$REPO:" | head -n 1); name="${ref#"$REPO:"}"
    for digest in "$@"; do [ "$name" != "$(att_tag "$digest")" ] || name=$(rewritten_name "$digest"); done
    echo "$sub ${name:-no reference}"
  done < "$SB/crane.log")
  odd=$(grep '^crane digest' "$SB/crane.log" | grep -vxF "${only[@]}")
  pushes=$(grep '^crane push' "$SB/crane.log" | grep -F -- "$(att_tag "${denied:-no digest is refused}")")
  lines=$(grep -c '' "$SB/stderr")
  warned=$(grep -c '^::warning::' "$SB/stderr"); errors=$(grep -c '^::error::' "$SB/stderr")
  last=$(tail -n 1 "$SB/stderr")
  # the error line of the digest refused: the last line, framed, the tag, and
  # in what is left that the manifest changed and the three questions
  if [ -n "$denied" ]; then
    tag=$(att_tag "$denied"); framed=no; reason=no
    [[ "$last" == "::error::unpack-provenance: ${REPO}@${denied}: "*" (Req 2.27)" ]] && grep -Fq -- "$tag" <<<"$last" && framed=yes
    rest="${last#"::error::unpack-provenance: ${REPO}@${denied}: "}"; rest="${rest%" (Req 2.27)"}"; rest="${rest//"$tag"/}"
    [ "$framed" = yes ] && grep -Eiq -- 'chang|rewritten|no longer|differ' <<<"$rest" \
      && grep -Eiq -- '(^|[^[:alnum:]])(3|three)([^[:alnum:]]|$)' <<<"$rest" && reason=yes
  fi
  # what was pushed, per digest: the digest refused, and every digest after
  # it, has nothing at its tag; a digest stored has the layers wanted, then
  # the one provenance layer, and a config that lists them
  n=0
  for digest in "$@"; do
    tag=$(att_tag "$digest"); name=$(rewritten_name "$digest"); pushed="$SB/pushed/$tag"
    [ "$digest" != "$denied" ] || n=1
    if [ "$n" -eq 1 ]; then
      [ ! -e "$pushed" ] || { ok=0; tags+=("$name: something was pushed to $tag, wanted nothing: the digest is refused or stands after the one refused"); }
      continue
    fi
    manifest=""; [ -f "$pushed/index.json" ] && manifest=$(manifest_of "$pushed")
    want=$(cat "$SB/layers.want.$name")
    got=$(jq -S '.layers[:-1]' <<<"$manifest" 2>/dev/null)
    lastlayer=$(jq -r '.layers[-1].digest' <<<"$manifest" 2>/dev/null)
    typed=$(jq -c --arg type "$slsa" '[.layers[] | select(.annotations.predicateType == $type) | .digest]' <<<"$manifest" 2>/dev/null)
    layersd=$(jq -c '[.layers[].digest]' <<<"$manifest" 2>/dev/null)
    listed=$(config_of "$pushed" | jq -c '.rootfs.diff_ids' 2>/dev/null)
    entries=$(config_of "$pushed" | jq '.history | length' 2>/dev/null)
    if [ -n "$manifest" ] && [ -n "$got" ] && [ "$got" = "$want" ] && [ "$lastlayer" = "$provenance" ] && [ "$typed" = "[\"$provenance\"]" ] \
      && [ -n "$listed" ] && [ "$listed" = "$layersd" ] && [ "$entries" = "$(jq 'length' <<<"$layersd")" ]; then
      stored=$((stored + 1)); continue
    fi
    tags+=("$name, pushed to $tag, not as wanted:" \
           "  layers before the last:" "$([ -n "$manifest" ] && jq -c '.layers[:-1][] | "    \(.annotations.predicateType) \(.digest)"' -r <<<"$manifest" || echo "    nothing was pushed to the tag")" \
           "  wanted, descriptor for descriptor (the manifest at the tag when it was last pulled):" "$(jq -r '.[] | "    \(.annotations.predicateType) \(.digest)"' <<<"$want")" \
           "  last layer: ${lastlayer:-none}, wanted $provenance; layers of the provenance type: ${typed:-none}, wanted [\"$provenance\"]" \
           "  rootfs.diff_ids of the config pushed: ${listed:-no config to read}" "  the manifest's layers' digests:       ${layersd:-none}" \
           "  history entries: ${entries:-none}, wanted one per layer")
  done
  [ "$rc" -eq "$code" ] && [ "$calls" = "$(cat "$SB/calls.want")" ] && [ -z "$odd" ] && [ -z "$pushes" ] && [ "$out" = "$stdoutwant" ] \
    && [ ! -s "$SB/sleep.log" ] && [ "$warned" -eq "$warnswant" ] && [ "$changedok" = yes ] \
    && [ "$errors" -eq "$errorswant" ] && [ "$framed" != no ] && [ "$reason" != no ] \
    && [ "$lines" -eq "$((warnswant + errorswant))" ] && [ "$writersok" = yes ] && [ "$stored" -eq "$storedwant" ] || ok=0
  [ "$ok" -eq 1 ] \
    && pass "a manifest that keeps changing is refused by name, $what: exit $code, the crane calls in their order ($(tr '\n' ',' < "$SB/calls.want" | sed 's/,$//; s/,/, /g')), $warnswant ::warning:: line(s) of a manifest changed, $errorswant ::error:: line(s), no pause, $storedwant digest(s) stored, each with the layers of the manifest last pulled and one provenance layer, the last" \
    || fail "a manifest that keeps changing is refused by name, $what: exit $code, the crane calls in their order, $warnswant ::warning:: line(s) of a manifest changed, $errorswant ::error:: line(s), no pause, $storedwant digest(s) stored with the layers of the manifest last pulled and one provenance layer" \
         "exit=$rc, wanted $code" \
         "crane calls, each as its subcommand and the digest whose tag it names:" "$([ -n "$calls" ] && sed 's/^/  /' <<<"$calls" || echo "  crane never called")" \
         "wanted, in this order:" "$(sed 's/^/  /' "$SB/calls.want")" \
         "crane digest calls that are not the line 'crane digest $REPO:<the tag of a digest given>', wanted none:" "${odd:-none}" \
         "crane push calls for the tag of the digest refused, wanted none:" "${pushes:-none}" \
         "the calls as logged:" "$([ -s "$SB/crane.log" ] && short_lines < "$SB/crane.log" || echo "crane never called")" \
         "stdout:" "$([ -n "$out" ] && short_lines <<<"$out" || echo "nothing")" "wanted:" "${stdoutwant:-nothing}" \
         "sleep calls logged, wanted none (no pause before a repeated preparation or before the refusal):" "$([ -s "$SB/sleep.log" ] && cat -A "$SB/sleep.log" || echo "none")" \
         "::warning:: lines on stderr: $warned, wanted $warnswant (one per repeated preparation, none for the question that ends in the refusal)" \
         "of them, per digest that keeps changing, begun '::warning::unpack-provenance: ${REPO}@<that digest>: ', speaking of the manifest, saying that it changed ('chang', 'rewritten', 'no longer' or 'differ', any case) and that it is prepared again ('again' or 'anew', any case):" "${changes[@]}" \
         "::error:: lines on stderr: $errors, wanted $errorswant; the last line of stderr begins '::error::unpack-provenance: ${REPO}@${denied:-<no digest is refused>}: ', ends ' (Req 2.27)' and holds the tag: $framed, wanted $([ -n "$denied" ] && echo yes || echo "not asked")" \
         "its reason (without the frame and the tag: 'chang', 'rewritten', 'no longer' or 'differ', and '3' or 'three' as a word of its own, any case): $reason, wanted $([ -n "$denied" ] && echo yes || echo "not asked")" \
         "lines on stderr in all: $lines, wanted $((warnswant + errorswant)) (the warnings and the error line, nothing else)" \
         "the other writer's writes per digest (layouts the stub took from rewrite/<tag>.<n>, one right after each pull of the tag):" "${writers[@]}" \
         "digests stored as wanted: $stored, wanted $storedwant" "${tags[@]}" \
         "stderr:" "$([ -s "$SB/stderr" ] && short_lines < "$SB/stderr" || echo "none")"
}
changing_input "(a) one digest, the manifest changed after every pull" "$INDEX" 5 "$INDEX"
changing_input "(b) one digest, the manifest changed twice and then holds still" "$INDEX" 2 "$INDEX"
changing_input "(c) two digests, the first in order and pushed, the second changed after every pull" "$AMD64" 5 "$INDEX" "$AMD64"
changing_input "(d) one digest, the manifest changed three times, a fourth question would find it still" "$INDEX" 3 "$INDEX"
changing_input "(e) two digests, each changed twice and then holds still" "$INDEX $AMD64" "2 2" "$INDEX" "$AMD64"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all unpack-provenance tests passed"
