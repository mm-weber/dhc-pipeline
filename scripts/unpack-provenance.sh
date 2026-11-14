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
# The certificate and the log entry travel as cosign's annotations: the
# bundle's certificate as PEM, the entry as the JSON text cosign reads back
# (the signed entry timestamp, the body, the integrated time, the entry's own
# log index, the log's id in hex), the signature annotation present and empty.
# The chain annotation (the Sigstore certificates that issued the bundle's
# certificate; Kyverno reads the intermediate from there and nowhere else) is
# copied character for character from the first layer of the pulled manifest
# that carries one.
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

# the manifest with the layer appended, as a new blob the index points at.
# The chain is copied inside jq: through a shell variable it would lose its
# closing newline
old=$(jq -r '.manifests[0].digest' "$DIR/index.json")
jq -c --arg digest "sha256:$layer" --argjson size "$lsize" --arg predicate "$predicate" \
  --arg certificate "$certificate" --arg entry "$entry" \
  '.layers += [{mediaType: "application/vnd.dsse.envelope.v1+json", size: $size, digest: $digest,
                annotations: {predicateType: $predicate, "dev.cosignproject.cosign/signature": "",
                              "dev.sigstore.cosign/certificate": ($certificate + "\n"),
                              "dev.sigstore.cosign/chain": first(.layers[].annotations."dev.sigstore.cosign/chain" | strings),
                              "dev.sigstore.cosign/bundle": $entry}}]' "$BLOBS/${old#sha256:}" > "$DIR/manifest"
manifest=$(sha256sum < "$DIR/manifest" | cut -d' ' -f1)
msize=$(wc -c < "$DIR/manifest")
mv "$DIR/manifest" "$BLOBS/$manifest"
jq -c --arg digest "sha256:$manifest" --argjson size "$msize" \
  '.manifests[0].digest = $digest | .manifests[0].size = $size' "$DIR/index.json" > "$DIR/index.json.tmp"
mv "$DIR/index.json.tmp" "$DIR/index.json"

crane push "$DIR" "$REF"
echo "unpack-provenance: ${REPO}@${DIGEST}: provenance stored as layer sha256:${layer} of ${REF}"
