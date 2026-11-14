#!/usr/bin/env bash
# unpack-provenance.sh store <bundles> <repository> <digest>...
#
# GitHub's provenance bundle (written by actions/attest-build-provenance)
# stored as one more layer of the attestation manifest cosign keeps beside an
# image digest, at the tag <repository>:sha256-<hex>.att, so that the
# verifiers reading that layout find the provenance next to the other
# attestations (Req 2.27). <bundles> is the file the action leaves at its
# bundle-path: one Sigstore bundle per line; the one whose statement names
# the digest is taken. One statement serves every digest it names: each
# digest given gets the layer in its own attestation manifest, one after the
# other, one pull and one push per digest. Nothing is signed here: the
# layer's blob is the bundle's DSSE envelope in the compact form whose sha256
# the transparency log recorded (payload, payloadType, the signature; no
# whitespace, no trailing newline), and its predicateType annotation is the
# statement's own.
# The certificate and the log entry travel as cosign's annotations: the
# bundle's certificate as PEM, the entry as the JSON text cosign reads back
# (the signed entry timestamp, the body, the integrated time, the entry's own
# log index, the log's id in hex), the signature annotation present and empty.
# The chain annotation (the Sigstore certificates that issued the bundle's
# certificate; Kyverno reads the intermediate from there and nowhere else) is
# copied character for character from the first layer of the pulled manifest
# that carries one, read before any layer is taken out.
# The manifest is pulled as an OCI layout with crane, gets the layer appended
# and is pushed back to the same tag. Its config is rewritten with the layer,
# the way cosign writes it: the layer's digest one more entry of
# rootfs.diff_ids, one more entry of history, every other field as it was; the
# manifest names the new config blob by its digest and its byte size.
# A second unpack replaces its own layer: every layer of the statement's
# predicate type that is already there is taken out before the new one is
# appended, with its digest in rootfs.diff_ids and its history entry, so a
# re-run release never stacks statements (cosign attest --replace leaves this
# layer alone). The layers of other predicate types stay as they were, in
# their order; the new layer goes last.
set -euo pipefail
USAGE="usage: unpack-provenance.sh store <bundles> <repository> <digest>..."
# $1 is the mode, store, the only one there is
BUNDLES="${2:?$USAGE}"
REPO="${3:?$USAGE}"
: "${4:?$USAGE}" # the digests: this one and every argument after it
shift 3

# the working directories, one per digest, all gone on exit
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for DIGEST in "$@"; do
  REF="${REPO}:sha256-${DIGEST#sha256:}.att"
  # a working directory of its own per digest: no layout sees another's blobs
  DIR=$(mktemp -d "$TMP/XXXXXX")
  BLOBS="$DIR/blobs/sha256"

  # the bundle whose statement names the digest
  bundle=$(jq -c --arg hex "${DIGEST#sha256:}" \
    'select(.dsseEnvelope.payload | @base64d | fromjson | any(.subject[]; .digest.sha256 == $hex))' "$BUNDLES")
  predicate=$(jq -r '.dsseEnvelope.payload | @base64d | fromjson | .predicateType' <<<"$bundle")

  # cosign's annotations: the certificate as PEM, the log entry as JSON text.
  # logIndex is the entry's own, the one the signed entry timestamp covers
  # (inclusionProof.logIndex is a different number); logID is the key id in hex
  certificate=$(jq -r '.verificationMaterial.certificate.rawBytes' <<<"$bundle" | base64 -d | openssl x509 -inform DER)
  logid=$(jq -r '.verificationMaterial.tlogEntries[0].logId.keyId' <<<"$bundle" | base64 -d | od -An -vtx1 | tr -d ' \n')
  entry=$(jq -c --arg logid "$logid" '.verificationMaterial.tlogEntries[0]
    | {SignedEntryTimestamp: .inclusionPromise.signedEntryTimestamp,
       Payload: {body: .canonicalizedBody, integratedTime: (.integratedTime | tonumber),
                 logIndex: (.logIndex | tonumber), logID: $logid}}' <<<"$bundle")

  crane pull --format oci "$REF" "$DIR"

  # the layer: the envelope byte for byte as the transparency log hashed it
  jq -cj '.dsseEnvelope | {payload, payloadType, signatures: [.signatures[] | {sig}]}' <<<"$bundle" > "$DIR/envelope"
  layer=$(sha256sum < "$DIR/envelope" | cut -d' ' -f1)
  lsize=$(wc -c < "$DIR/envelope")
  mv "$DIR/envelope" "$BLOBS/$layer"

  # the config with the layer listed, as a new blob: cosign keeps the layers'
  # digests in rootfs.diff_ids and one history entry per layer
  old=$(jq -r '.manifests[0].digest' "$DIR/index.json")
  oldconfig=$(jq -r '.config.digest' "$BLOBS/${old#sha256:}")
  # the layers of the statement's predicate type that are already there (an
  # earlier unpack's), as their positions in the manifest: they are taken out of
  # the manifest and the config by position, because the history entries are
  # all alike and cannot be told apart by value
  stale=$(jq -c --arg predicate "$predicate" \
    '[.layers | to_entries[] | select(.value.annotations.predicateType == $predicate) | .key]' "$BLOBS/${old#sha256:}")
  jq -c --arg digest "sha256:$layer" --argjson stale "$stale" \
    'del(.rootfs.diff_ids[$stale[]], .history[$stale[]])
     | .rootfs.diff_ids += [$digest] | .history += [{created: "0001-01-01T00:00:00Z"}]' "$BLOBS/${oldconfig#sha256:}" > "$DIR/config"
  config=$(sha256sum < "$DIR/config" | cut -d' ' -f1)
  csize=$(wc -c < "$DIR/config")
  mv "$DIR/config" "$BLOBS/$config"

  # the manifest without the stale layers, with the layer appended and the new
  # config named, as a new blob the index points at. The chain is copied inside
  # jq: through a shell variable it would lose its closing newline; and it is
  # read from the layers as they were pulled, a stale layer may be the only one
  # that carries it
  jq -c --arg digest "sha256:$layer" --argjson size "$lsize" --arg predicate "$predicate" \
    --arg certificate "$certificate" --arg entry "$entry" --arg config "sha256:$config" --argjson csize "$csize" \
    --argjson stale "$stale" \
    'first(.layers[].annotations."dev.sigstore.cosign/chain" | strings) as $chain
     | .config.digest = $config | .config.size = $csize
     | del(.layers[$stale[]])
     | .layers += [{mediaType: "application/vnd.dsse.envelope.v1+json", size: $size, digest: $digest,
                    annotations: {predicateType: $predicate, "dev.cosignproject.cosign/signature": "",
                                  "dev.sigstore.cosign/certificate": ($certificate + "\n"),
                                  "dev.sigstore.cosign/chain": $chain,
                                  "dev.sigstore.cosign/bundle": $entry}}]' "$BLOBS/${old#sha256:}" > "$DIR/manifest"
  manifest=$(sha256sum < "$DIR/manifest" | cut -d' ' -f1)
  msize=$(wc -c < "$DIR/manifest")
  mv "$DIR/manifest" "$BLOBS/$manifest"
  jq -c --arg digest "sha256:$manifest" --argjson size "$msize" \
    '.manifests[0].digest = $digest | .manifests[0].size = $size' "$DIR/index.json" > "$DIR/index.json.tmp"
  mv "$DIR/index.json.tmp" "$DIR/index.json"

  crane push "$DIR" "$REF"
  echo "unpack-provenance: ${REPO}@${DIGEST}: provenance stored as layer sha256:${layer} of ${REF}"
done
