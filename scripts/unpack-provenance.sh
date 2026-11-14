#!/usr/bin/env bash
# unpack-provenance.sh store <bundles> <repository> <digest>
#
# GitHub's provenance bundle (written by actions/attest-build-provenance)
# stored as one more layer of the attestation manifest cosign keeps beside an
# image digest, at the tag <repository>:sha256-<hex>.att, so that the
# verifiers reading that layout find the provenance next to the other
# attestations (Req 2.27). <bundles> is the file the action leaves at its
# bundle-path: one Sigstore bundle per line; the one whose statement names
# the digest is taken. Nothing is signed here: the layer's blob is the
# bundle's DSSE envelope in the compact form whose sha256 the transparency
# log recorded (payload, payloadType, the signature; no whitespace, no
# trailing newline), and its predicateType annotation is the statement's own.
# The manifest is pulled as an OCI layout with crane, gets the layer appended
# and is pushed back to the same tag.
set -euo pipefail
USAGE="usage: unpack-provenance.sh store <bundles> <repository> <digest>"
# $1 is the mode, store, the only one there is
BUNDLES="${2:?$USAGE}"
REPO="${3:?$USAGE}"
DIGEST="${4:?$USAGE}"

REF="${REPO}:sha256-${DIGEST#sha256:}.att"
DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT
BLOBS="$DIR/blobs/sha256"

# the bundle whose statement names the digest
bundle=$(jq -c --arg hex "${DIGEST#sha256:}" \
  'select(.dsseEnvelope.payload | @base64d | fromjson | any(.subject[]; .digest.sha256 == $hex))' "$BUNDLES")
predicate=$(jq -r '.dsseEnvelope.payload | @base64d | fromjson | .predicateType' <<<"$bundle")

crane pull --format oci "$REF" "$DIR"

# the layer: the envelope byte for byte as the transparency log hashed it
jq -cj '.dsseEnvelope | {payload, payloadType, signatures: [.signatures[] | {sig}]}' <<<"$bundle" > "$DIR/envelope"
layer=$(sha256sum < "$DIR/envelope" | cut -d' ' -f1)
lsize=$(wc -c < "$DIR/envelope")
mv "$DIR/envelope" "$BLOBS/$layer"

# the manifest with the layer appended, as a new blob the index points at
old=$(jq -r '.manifests[0].digest' "$DIR/index.json")
jq -c --arg digest "sha256:$layer" --argjson size "$lsize" --arg predicate "$predicate" \
  '.layers += [{mediaType: "application/vnd.dsse.envelope.v1+json", size: $size, digest: $digest,
                annotations: {predicateType: $predicate}}]' "$BLOBS/${old#sha256:}" > "$DIR/manifest"
manifest=$(sha256sum < "$DIR/manifest" | cut -d' ' -f1)
msize=$(wc -c < "$DIR/manifest")
mv "$DIR/manifest" "$BLOBS/$manifest"
jq -c --arg digest "sha256:$manifest" --argjson size "$msize" \
  '.manifests[0].digest = $digest | .manifests[0].size = $size' "$DIR/index.json" > "$DIR/index.json.tmp"
mv "$DIR/index.json.tmp" "$DIR/index.json"

crane push "$DIR" "$REF"
echo "unpack-provenance: ${REPO}@${DIGEST}: provenance stored as layer sha256:${layer} of ${REF}"
