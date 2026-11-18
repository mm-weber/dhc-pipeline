#!/usr/bin/env bash
# unpack-provenance.sh store <bundles> <repository> <digest>...
# unpack-provenance.sh subjects <repository> <digest>...
#
# The two ends of a release's provenance, which GitHub signs (the action
# actions/attest-build-provenance): subjects names the digests to the action,
# store puts the bundle the action wrote beside each of them.
#
# A call that is wrong is no refusal of content: a mode that is missing or is
# neither store nor subjects; for store no bundles file, repository or digest,
# a digest that is not sha256: and 64 lowercase hex digits, or a bundles file
# that is not there; for subjects no repository or no digest, or a digest that
# is not sha256: and 64 lowercase hex digits, checked before the first line is
# written: a file half written is a file the action signs for. Each ends with
# the usage lines on stderr and exit 2, before anything is read or pulled.
#
# subjects writes to stdout what the release job hands to
# actions/attest-build-provenance as its subject-checksums file: one line per
# digest, in the order the digests were given, the digest without its sha256:
# (the 64 hex digits), one space, the repository, and nothing else. The shape
# is the action's: it skips a line without a space in silence and throws out a
# digest that keeps its sha256:. A digest named more than once is written
# once, at its first naming: two lines for one digest are one subject named
# twice to the action. The mode reads no bundles file and asks nothing of the
# registry.
#
# store takes GitHub's provenance bundle and stores it as one more layer of
# the attestation manifest cosign keeps beside an image digest, at the tag
# <repository>:sha256-<hex>.att, so that the verifiers reading that layout
# find the provenance next to the other attestations (Req 2.27). One statement
# serves every digest it names: each digest given gets the layer in its own
# attestation manifest, pulled and pushed for that digest alone; a digest
# named more than once is handled once, at its first naming.
#
# <bundles> is the file the action leaves at its bundle-path: one Sigstore
# bundle per line, or the answer of GitHub's attestation store, read like that
# file: one JSON object, the bundles under .attestations[].bundle. The bundle
# whose statement names the digest is taken. Of several that name it, the
# statements of SLSA provenance v1, the one predicate type stored here, come
# before those of every other type: a statement of another type (the
# attestation store keeps an SBOM attested there beside the provenance)
# decides nothing while a provenance statement names the digest, however late
# its log entry is. Among the provenance statements (a release run twice
# leaves two) the one whose log entry is the later is taken: by the entry's
# integrated time, then by its log index, both compared as numbers, their
# order in the file deciding nothing. An integrated time or a log index that
# is missing or is no whole number written in digits counts as 0 there, the
# earliest: its statement is refused below if it is the one taken.
#
# A refusal of content is one ::error:: line naming the digest and the reason,
# and exit 1. The first refusal is of the bundles file as a whole, before
# anything is pulled for any digest, on a line naming the first digest given:
# a bundles file that cannot be read in full. That is a file that is not JSON
# or holds none, and a file with an entry that is no bundle with an envelope
# whose payload is base64 of a JSON statement with its list of subjects, even
# where another entry is the bundle that names the digest: a file the script
# cannot read in full is not one it picks from, and the words of the refusal
# are the script's, never jq's. The attestation store's answer with no
# attestation in it is read in full and names no digest.
#
# Refused then, before anything is pulled or pushed for it, in this
# order, is a digest no statement in the bundles file names; one that no
# statement of SLSA provenance v1 names, with the predicate type found on the
# error line (of several statements of other types that of the latest log
# entry); one whose bundle holds more or fewer than one log entry (the layer's
# bundle annotation carries exactly one; for none the error line adds the
# likely cause, the action having signed with GitHub's own Sigstore instance,
# which keeps no transparency log); one whose log entry carries no signed entry
# timestamp: cosign verifies the entry in this layout by that timestamp, and
# the layout has no place for the inclusion proof the newer log issues in its
# stead; one whose log entry is of another kind than dsse, with the kind found
# on the error line: the kind is read from the entry's body, which the log
# signed (the bundle's kindVersion only repeats it), and only an entry of the
# kind dsse records the envelope hash that ties the layer to the log; one
# whose bundle lacks a part the layer's annotations need, with the part named
# on the error line and never in the words of the tool that would fail on it,
# asked in this order: the signing certificate (base64 of DER that openssl
# reads as a certificate), the log entry's integrated time, its own log index
# (each a whole number written in digits) and the log's id (base64); one
# whose envelope carries more or fewer than one signature (the layer holds
# exactly one, the one the log entry recorded); and then one whose envelope's
# sha256 is not the envelope hash the log entry records: that hash is the one
# tie between the layer's bytes and the transparency log.
#
# Nothing is signed here: the layer's blob is the bundle's DSSE envelope in
# the compact form whose sha256 the transparency log recorded (payload,
# payloadType, the signature; no whitespace, no trailing newline), and its
# predicateType annotation is the statement's own. The certificate and the log
# entry travel as cosign's annotations: the bundle's certificate as PEM, the
# entry as the JSON text cosign reads back (the signed entry timestamp, the
# body, the integrated time, the entry's own log index, the log's id in hex),
# the signature annotation present and empty.
#
# The manifest is pulled as an OCI layout with crane, gets the layer appended
# and is pushed back to the same tag. Each of the two registry calls, the pull
# and the push, is tried again when it fails, up to three attempts,
# UNPACK_PROVENANCE_RETRY_DELAY seconds apart (default 10; the tests set 0): a
# registry that falters once is no missing manifest. Every failure that is
# tried again is said with one ::warning:: line naming the digest, the tag
# whose pull or push failed and the attempt that failed: a call that goes
# through at the second or third attempt leaves a green run, and crane's own
# words name a tag and a status and are no annotation. What crane says on
# stderr passes to stderr as it is, at every attempt.
#
# A pull the registry answers with its error code MANIFEST_UNKNOWN (the code
# of the OCI distribution API for a manifest or a tag that is not there, on
# the line crane prints; the code decides, not the words after it) is not
# tried again, at whichever attempt the answer comes: the registry has
# answered, and asking again brings the same answer. The digest is refused at
# once, like the others, as one with no attestation manifest to pull, with no
# warning line and no pause for that answer: the layer is added to the
# manifest cosign wrote and never begins a new one, so the release's other
# attestations must exist first. After the third failure of its pull for
# another cause a digest is refused in other words, those of a push that
# failed: the pull of the tag failed three times and the provenance is not
# stored beside the digest. Whether a manifest is there was never answered,
# so the line does not say that there is none.
#
# The chain annotation (the Sigstore certificates that issued the bundle's
# certificate; Kyverno reads the intermediate from there and nowhere else) is
# copied character for character from the first layer of the pulled manifest
# that carries one, read before any layer is taken out; a manifest none of
# whose layers carries one is refused like the others, once it is pulled and
# before anything of it is rewritten: there is no chain to copy. That chain
# must have issued the bundle's certificate: openssl verify checks the
# certificate against the chain alone (the system's trust store is kept out),
# at the log entry's integrated time, because the certificate lives ten
# minutes. A chain that did not issue it is refused in the same way, with what
# openssl says as plain lines before the error line: beside that certificate
# it would lead no verifier to it.
#
# The manifest's config is rewritten with the layer, the way cosign writes it:
# the layer's digest one more entry of rootfs.diff_ids, one more entry of
# history, every other field as it was; the manifest names the new config blob
# by its digest and its byte size. A second unpack replaces its own layer:
# every layer of the statement's predicate type that is already there is taken
# out before the new one is appended, with its digest in rootfs.diff_ids and
# its history entry, so a re-run release never stacks statements (cosign
# attest --replace leaves this layer alone). The layers of other predicate
# types stay as they were, in their order; the new layer goes last.
#
# All or nothing across the digests: every digest is prepared and checked
# (pulled, its layout rewritten, every refusal above passed) before the first
# push, so a digest that is refused leaves every tag as it was, the tags of
# the digests before it included: a release carries its provenance beside
# every digest or beside none.
#
# Then the pushes, in the order the digests were given, each one that is
# through said with one line on stdout. After the third failure of a push the
# run ends with one ::error:: line naming the digest and the three attempts,
# and exit 1: nothing more is pushed, and the digests pushed before it keep
# their layer, which a re-run replaces.
set -euo pipefail

# the attempts a pull or a push gets
ATTEMPTS=3
# the one predicate type stored here: SLSA provenance v1
PROVENANCE="https://slsa.dev/provenance/v1"

# wrong usage: the usage lines, one per mode, and exit 2
usage() {
  echo "usage: unpack-provenance.sh store <bundles> <repository> <digest>..." >&2
  echo "       unpack-provenance.sh subjects <repository> <digest>..." >&2
  exit 2
}

# wrong usage unless every digest given is one: sha256: and 64 lowercase hex
# digits
check_digests() {
  local digest
  for digest in "$@"; do
    [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || usage
  done
}

# true at the first naming of the digest $1, false once DIGESTS, the digests
# handled so far, holds it: a digest named more than once is handled once
first_naming() { [[ " ${DIGESTS[*]} " != *" $1 "* ]]; }

# a refusal: one ::error:: line naming the digest and the reason, exit 1
refuse() {
  echo "::error::unpack-provenance: ${REPO}@${DIGEST}: $1 (Req 2.27)" >&2
  exit 1
}

# a call of crane for the digest, tried again when it fails, up to ATTEMPTS
# attempts, UNPACK_PROVENANCE_RETRY_DELAY seconds apart (default 10). Every
# failure that is tried again is said with a warning line naming the digest,
# the call ($1, with its tag) and the attempt that failed; the last failure
# is the refusal $2. $3 is the registry's error code that is its answer and
# no faltering ("" for none): a failure whose stderr holds it is the refusal
# $4 at once, not tried again. What crane says on stderr is kept for that
# reading and passes to stderr as it is. What follows the four is crane's
# arguments
registry() {
  local what="$1" refusal="$2" answer="$3" answered="$4" attempt failed
  shift 4
  for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
    failed=0
    crane "$@" 2> "$TMP/crane.stderr" || failed=1
    cat "$TMP/crane.stderr" >&2
    [ "$failed" -eq 1 ] || return 0
    [ -z "$answer" ] || ! grep -Fq -- "$answer" "$TMP/crane.stderr" || refuse "$answered"
    [ "$attempt" -lt "$ATTEMPTS" ] || refuse "$refusal"
    echo "::warning::unpack-provenance: ${REPO}@${DIGEST}: ${what} failed, attempt ${attempt} of ${ATTEMPTS}, it is tried again" >&2
    sleep "${UNPACK_PROVENANCE_RETRY_DELAY:-10}"
  done
}

# $1 is the mode, store or subjects (asked as ${1:-}: a call with no argument
# is wrong usage, not bash's complaint about an unset parameter)
case "${1:-}" in
  # after it the bundles file, the repository and the digests, at least one;
  # the rest of the script is this mode's
  store)
    [ "$#" -ge 4 ] || usage
    [ -n "$3" ] || usage
    ;;
  # after it the repository and the digests, at least one: a line per digest
  # in the order given, a digest named again left out, the digest without its
  # sha256:, one space, the repository; nothing is read and nothing is pulled
  subjects)
    [ "$#" -ge 3 ] || usage
    [ -n "$2" ] || usage
    REPO="$2"
    shift 2
    # checked before the first line is written: every digest is one
    check_digests "$@"
    DIGESTS=()
    for DIGEST in "$@"; do
      first_naming "$DIGEST" || continue
      printf '%s %s\n' "${DIGEST#sha256:}" "$REPO"
      DIGESTS+=("$DIGEST")
    done
    exit 0 ;;
  *) usage ;;
esac
BUNDLES="$2"
REPO="$3"
shift 3
# checked before anything is read or pulled: the bundles file is there, and
# every digest is one
[ -f "$BUNDLES" ] || usage
check_digests "$@"

# the bundles file is read in full or not at all, before anything is pulled:
# it is JSON, at least one value, and every entry of it (the file's lines or,
# in the attestation store's answer, what is under .attestations[].bundle) is
# a bundle whose envelope's payload is base64 of a statement with its list of
# subjects. The file is read as one input (-s) and an entry that fails is
# caught as false, so the verdict hangs on no exit code jq gives over several
# inputs (jq 1.6 takes it from the last input alone); jq's own words are kept
# off stderr, the refusal names the first digest given
DIGEST="$1"
jq -es 'length > 0
        and all(.[] | if type == "object" and has("attestations") then .attestations[].bundle else . end;
                try (.dsseEnvelope.payload | @base64d | fromjson | .subject | type == "array") catch false)' \
  "$BUNDLES" > /dev/null 2>&1 \
  || refuse "the bundles file cannot be read: it is not JSON, or holds an entry that is no bundle with an envelope whose statement can be read"

# the working directories, one per digest, all gone on exit
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# every digest is prepared and checked here, nothing is pushed yet: what the
# pushes below need per digest, in the order the digests were given
DIGESTS=() REFS=() DIRS=() LAYERS=()
for DIGEST in "$@"; do
  first_naming "$DIGEST" || continue
  REF="${REPO}:sha256-${DIGEST#sha256:}.att"
  # a working directory of its own per digest: no layout sees another's blobs
  DIR=$(mktemp -d "$TMP/XXXXXX")
  BLOBS="$DIR/blobs/sha256"

  # the bundle whose statement names the digest; of several a provenance
  # statement before one of any other type (false sorts before true), and
  # then the one whose log entry is the later, by its integrated time, then
  # by its log index, as numbers (a bundle with no log entry, and a time or
  # an index that is no whole number in digits, counts as 0 here, it is
  # refused below). The bundles are the file's lines or, in the attestation
  # store's answer, what is under .attestations[].bundle
  bundle=$(jq -c --arg hex "${DIGEST#sha256:}" \
    '(if type == "object" and has("attestations") then .attestations[].bundle else . end)
     | select(.dsseEnvelope.payload | @base64d | fromjson | any(.subject[]; .digest.sha256 == $hex))' "$BUNDLES" \
    | jq -sc --arg provenance "$PROVENANCE" \
      'def whole: tostring | if test("^[0-9]+$") then tonumber else 0 end;
       max_by([(.dsseEnvelope.payload | @base64d | fromjson | .predicateType == $provenance)]
              + (.verificationMaterial.tlogEntries[0] | [(.integratedTime | whole), (.logIndex | whole)])) // empty')
  [ -n "$bundle" ] || refuse "no statement in the bundles file names the digest"
  predicate=$(jq -r '.dsseEnvelope.payload | @base64d | fromjson | .predicateType' <<<"$bundle")
  # SLSA provenance v1 and nothing else is stored here: the statement taken
  # is of another type only where no provenance statement names the digest
  [ "$predicate" = "$PROVENANCE" ] \
    || refuse "the statement naming the digest is of predicate type ${predicate}, not ${PROVENANCE}"
  # exactly one log entry in the bundle, the one the bundle annotation
  # carries; none is what the action leaves when it signs with GitHub's own
  # Sigstore instance, and only then is that cause named
  entries=$(jq -r '.verificationMaterial.tlogEntries | length' <<<"$bundle")
  cause=""
  [ "$entries" -ne 0 ] \
    || cause=": the action has likely signed with GitHub's own Sigstore instance, which keeps no transparency log, the one it chooses when the event does not say the repository is public"
  [ "$entries" -eq 1 ] \
    || refuse "the bundle carries ${entries} log entries, not exactly one${cause}"
  # the layout verifies the log entry by its signed entry timestamp: an entry
  # without one (the newer log issues an inclusion proof only) cannot be
  # stored
  timestamp=$(jq -r '.verificationMaterial.tlogEntries[0].inclusionPromise.signedEntryTimestamp // ""' <<<"$bundle")
  [ -n "$timestamp" ] \
    || refuse "the log entry carries no signed entry timestamp, the attestation layout cannot carry such an entry"
  # the entry's kind, read from its body, which the log signed (kindVersion is
  # the bundle's repetition of it): only the kind dsse records the envelope
  # hash compared below
  kind=$(jq -r '.verificationMaterial.tlogEntries[0].canonicalizedBody | @base64d | fromjson | .kind' <<<"$bundle")
  [ "$kind" = "dsse" ] \
    || refuse "the log entry is of the kind ${kind}, not dsse, the one kind that records the envelope's hash"

  # cosign's annotations: the certificate as PEM, the log entry as JSON text.
  # logIndex is the entry's own, the one the signed entry timestamp covers
  # (inclusionProof.logIndex is a different number); logID is the key id in
  # hex. A bundle that lacks one of the four parts read here is refused with
  # the part named: what base64 and openssl say of it is kept off stderr
  certificate=$(jq -r '.verificationMaterial.certificate.rawBytes // ""' <<<"$bundle" | base64 -d 2> /dev/null | openssl x509 -inform DER 2> /dev/null) \
    || refuse "the bundle carries no signing certificate that can be read (verificationMaterial.certificate.rawBytes, base64 of DER)"
  at=$(jq -r '.verificationMaterial.tlogEntries[0].integratedTime // ""' <<<"$bundle")
  [[ "$at" =~ ^[0-9]+$ ]] \
    || refuse "the log entry carries no integrated time that is a whole number written in digits (integratedTime)"
  logindex=$(jq -r '.verificationMaterial.tlogEntries[0].logIndex // ""' <<<"$bundle")
  [[ "$logindex" =~ ^[0-9]+$ ]] \
    || refuse "the log entry carries no log index that is a whole number written in digits (logIndex)"
  logid=$(jq -r '.verificationMaterial.tlogEntries[0].logId.keyId // ""' <<<"$bundle" | base64 -d 2> /dev/null | od -An -vtx1 | tr -d ' \n') \
    || logid=""
  [ -n "$logid" ] \
    || refuse "the log entry carries no log id that can be read (logId.keyId, base64)"
  entry=$(jq -c --arg logid "$logid" '.verificationMaterial.tlogEntries[0]
    | {SignedEntryTimestamp: .inclusionPromise.signedEntryTimestamp,
       Payload: {body: .canonicalizedBody, integratedTime: (.integratedTime | tonumber),
                 logIndex: (.logIndex | tonumber), logID: $logid}}' <<<"$bundle")

  # exactly one signature on the envelope, the one the log entry recorded
  signatures=$(jq -r '.dsseEnvelope.signatures | length' <<<"$bundle")
  [ "$signatures" -eq 1 ] \
    || refuse "the envelope carries ${signatures} signatures, not exactly one"

  # the layer: the envelope byte for byte as the transparency log hashed it,
  # built beside the working directory until the layout is there; its sha256
  # is the envelope hash the log entry records, or nothing is stored
  jq -cj '.dsseEnvelope | {payload, payloadType, signatures: [.signatures[] | {sig}]}' <<<"$bundle" > "$DIR.envelope"
  layer=$(sha256sum < "$DIR.envelope" | cut -d' ' -f1)
  lsize=$(wc -c < "$DIR.envelope")
  logged=$(jq -r '.verificationMaterial.tlogEntries[0].canonicalizedBody | @base64d | fromjson | .spec.envelopeHash.value' <<<"$bundle")
  [ "$layer" = "$logged" ] \
    || refuse "the envelope's sha256 ${layer} is not the envelope hash the log entry records, ${logged}"

  # the layer is added to the attestation manifest cosign wrote for the digest
  # and never begins a new one: no manifest to pull, nothing is stored. The
  # pull has its attempts; the last one's failure is a refusal that says so,
  # and the registry's answer that the manifest is not there is, at once, the
  # refusal that says that
  registry "the pull of ${REF}" \
    "the pull of ${REF} failed ${ATTEMPTS} times, the provenance is not stored beside the digest" \
    MANIFEST_UNKNOWN \
    "no attestation manifest could be pulled from ${REF}, the release's other attestations must exist first" \
    pull --format oci "$REF" "$DIR"
  # the chain is copied from a layer cosign wrote in that manifest: no layer
  # that carries one, nothing is stored
  old=$(jq -r '.manifests[0].digest' "$DIR/index.json")
  jq -e 'any(.layers[].annotations."dev.sigstore.cosign/chain"; type == "string")' "$BLOBS/${old#sha256:}" > /dev/null \
    || refuse "no layer of the attestation manifest ${REF} carries a chain (the annotation dev.sigstore.cosign/chain), there is none to copy to the provenance layer"
  # the chain to copy (the first one, as below) must have issued the bundle's
  # certificate: verified against the chain alone, at the log entry's
  # integrated time (the certificate lives ten minutes); what openssl says of
  # a failure passes to stderr as it is
  jq -rj 'first(.layers[].annotations."dev.sigstore.cosign/chain" | strings)' "$BLOBS/${old#sha256:}" > "$DIR.chain"
  openssl verify -attime "$at" -no-CApath -no-CAstore -CAfile "$DIR.chain" <<<"$certificate" > /dev/null \
    || refuse "the chain of the attestation manifest ${REF} (the annotation dev.sigstore.cosign/chain) did not issue the provenance certificate, openssl verify fails at the log entry's integrated time ${at}"
  mv "$DIR.envelope" "$BLOBS/$layer"

  # the config with the layer listed, as a new blob: cosign keeps the layers'
  # digests in rootfs.diff_ids and one history entry per layer
  oldconfig=$(jq -r '.config.digest' "$BLOBS/${old#sha256:}")
  # the layers of the statement's predicate type that are already there (an
  # earlier unpack's), as their positions in the manifest: they are taken out
  # of the manifest and the config by position, because the history entries
  # are all alike and cannot be told apart by value
  stale=$(jq -c --arg predicate "$predicate" \
    '[.layers | to_entries[] | select(.value.annotations.predicateType == $predicate) | .key]' "$BLOBS/${old#sha256:}")
  jq -c --arg digest "sha256:$layer" --argjson stale "$stale" \
    'del(.rootfs.diff_ids[$stale[]], .history[$stale[]])
     | .rootfs.diff_ids += [$digest] | .history += [{created: "0001-01-01T00:00:00Z"}]' "$BLOBS/${oldconfig#sha256:}" > "$DIR/config"
  config=$(sha256sum < "$DIR/config" | cut -d' ' -f1)
  csize=$(wc -c < "$DIR/config")
  mv "$DIR/config" "$BLOBS/$config"

  # the manifest without the stale layers, with the layer appended and the new
  # config named, as a new blob the index points at. The chain is copied
  # inside jq: through a shell variable it would lose its closing newline; and
  # it is read from the layers as they were pulled, a stale layer may be the
  # only one that carries it
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

  DIGESTS+=("$DIGEST"); REFS+=("$REF"); DIRS+=("$DIR"); LAYERS+=("$layer")
done

# no digest was refused: the prepared layouts are pushed, each to its own tag,
# and a digest is said to be stored once its push is through. The push has
# its attempts; the last one's failure ends the run with the error line of a
# refusal, naming the digest whose push it was
for i in "${!DIGESTS[@]}"; do
  DIGEST="${DIGESTS[$i]}" REF="${REFS[$i]}"
  registry "the push to ${REF}" \
    "the push to ${REF} failed ${ATTEMPTS} times, the provenance is not stored beside the digest" \
    "" "" push "${DIRS[$i]}" "$REF"
  echo "unpack-provenance: ${REPO}@${DIGEST}: provenance stored as layer sha256:${LAYERS[$i]} of ${REF}"
done
