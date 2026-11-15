#!/usr/bin/env bash
# Tests of the provenance scripts against the real tools: the pinned crane
# and the pinned cosign, a throwaway registry on 127.0.0.1 (Req 2.27).
#
# Why this suite exists beside scripts/unpack-provenance_test.sh: there crane
# is a stub and no verifier reads what the script writes, so every case there
# holds the script to what the suite's author believes the tools want. What
# the stubs accept must also be what the real tools accept. A defect the
# stand-ins share with the script shows only here: the wrong logIndex, a
# certificate PEM cosign cannot parse, a log entry annotation whose signed
# entry timestamp does not verify, a layer that is not the envelope the
# transparency log recorded.
#
# Run it with the two pinned tools first on PATH (scripts/install-tool.sh
# installs them, and holds the two versions this suite asks for):
#
#     scripts/install-tool.sh crane && scripts/install-tool.sh cosign
#     bash scripts/provenance-real_test.sh
#
# With another crane or cosign on PATH, or with one of them missing, the suite
# refuses to run: one line on stderr, exit 2, nothing started. A verdict from
# another version is no verdict on the pinned one.
#
# No network beyond 127.0.0.1: the registry is `crane registry serve` in
# memory on a free port, the image and the attestation manifest are laid down
# by hand, the bundle and the chain are the real ones of the measuring run of
# 2026-11-13 (scripts/testdata/provenance), and cosign verifies offline with
# the public Sigstore trust root handed over as files
# (scripts/testdata/provenance/roots: Fulcio's two root certificates, the key
# of the first Rekor log, the key of the certificate transparency log that
# logged the fixture's certificate; taken from the public trusted_root.json)
# and with TUF_ROOT at an empty directory, so that a trust root cached on the
# machine cannot help a run.
#
# The Fulcio file holds the roots only, not the intermediate certificate that
# issued the fixture's certificate: cosign therefore takes the intermediate
# from the layer's dev.sigstore.cosign/chain annotation. That is wanted: a
# verifier configured with the roots alone must be able to build the path
# from what the script wrote, and the stub suite can only check that the
# annotation is there. Case 2 holds it with a control: the same layer without
# its chain is refused. With the intermediate back in the file, case 2 fails.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
UNPACK="$HERE/unpack-provenance.sh"
DATA="$HERE/testdata/provenance"
ROOTS="$DATA/roots"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

# The version gate, before anything else: the pins live in install-tool.sh and
# nowhere else, and what is on PATH must be exactly those two versions.
want_crane=$(sed -n 's/^CRANE_VERSION="\([^"]*\)"$/\1/p' "$HERE/install-tool.sh")
want_cosign=$(sed -n 's/^COSIGN_VERSION="\([^"]*\)"$/\1/p' "$HERE/install-tool.sh")
have_crane=$(crane version 2>/dev/null | head -n 1) || have_crane=""
have_cosign=$(cosign version 2>/dev/null | sed -n 's/^GitVersion:[[:space:]]*v//p') || have_cosign=""
if [ -z "$want_crane" ] || [ -z "$want_cosign" ] || [ "$have_crane" != "$want_crane" ] || [ "$have_cosign" != "$want_cosign" ]; then
  echo "provenance-real_test: crane ${want_crane:-(no pin read)} and cosign ${want_cosign:-(no pin read)} are needed on PATH, the versions scripts/install-tool.sh pins and installs; found crane ${have_crane:-none} and cosign ${have_cosign:-none}. Nothing was started, no case was run." >&2
  exit 2
fi

# the index digest the fixture's statement names
INDEX="sha256:c47ac86f0e7100538371e5836d2608bbb9abec15c5589d5bbc34bc9cad3619b2"
att_tag() { printf 'sha256-%s.att' "${1#sha256:}"; } # cosign's attestation tag for a digest

put_blob() { # layout: stdin becomes a blob named by its sha256; prints "<hex> <size>"
  local dir="$1/blobs/sha256" tmp hex
  mkdir -p "$dir"; tmp=$(mktemp "$dir/tmp.XXXXXX"); cat > "$tmp"
  hex=$(sha256sum < "$tmp" | cut -d' ' -f1); mv "$tmp" "$dir/$hex"
  printf '%s %s\n' "$hex" "$(wc -c < "$dir/$hex")"
}

close_layout() { # layout config-hex config-size layers: the manifest, index.json and oci-layout in the shape crane 0.22.1 reads
  local dir="$1" mhex msize
  read -r mhex msize < <(jq -nc --arg config "sha256:$2" --argjson csize "$3" --argjson layers "$4" \
    '{schemaVersion:2,mediaType:"application/vnd.oci.image.manifest.v1+json",
      config:{mediaType:"application/vnd.oci.image.config.v1+json",size:$csize,digest:$config},
      layers:$layers}' | put_blob "$dir")
  jq -nc --arg manifest "sha256:$mhex" --argjson msize "$msize" \
    '{schemaVersion:2,mediaType:"application/vnd.oci.image.index.v1+json",
      manifests:[{mediaType:"application/vnd.oci.image.manifest.v1+json",size:$msize,digest:$manifest}]}' > "$dir/index.json"
  printf '{"imageLayoutVersion": "1.0.0"}' > "$dir/oci-layout"
}

image_layout() { # layout name: a stand-in image built with no network, a config that carries the name and no layer
  local dir="$1" chex csize
  mkdir -p "$dir"
  read -r chex csize < <(jq -nc --arg name "$2" \
    '{architecture:"amd64",os:"linux",rootfs:{type:"layers",diff_ids:[]},config:{Labels:{"stand-in":$name}}}' | put_blob "$dir")
  close_layout "$dir" "$chex" "$csize" '[]'
}

att_layout() { # layout: the attestation manifest cosign keeps beside a digest, one cosign-shaped layer that carries the chain
  local dir="$1" type="https://spdx.dev/Document" payload lhex lsize chex csize layers
  mkdir -p "$dir"
  # a small DSSE envelope that nobody signed: the layer cosign wrote stands
  # here only as the layer that was already there and that carries the chain
  payload=$(printf '{"_type":"https://in-toto.io/Statement/v0.1","predicateType":"%s","subject":[],"predicate":{}}' "$type" | base64 -w0)
  read -r lhex lsize < <(printf '{"payload":"%s","payloadType":"application/vnd.in-toto+json","signatures":[{"sig":""}]}' "$payload" | put_blob "$dir")
  layers=$(jq -nc --rawfile chain "$DATA/chain.pem" --arg type "$type" --arg layer "sha256:$lhex" --argjson lsize "$lsize" \
    '[{mediaType:"application/vnd.dsse.envelope.v1+json",size:$lsize,digest:$layer,
       annotations:{predicateType:$type,"dev.cosignproject.cosign/signature":"","dev.sigstore.cosign/chain":$chain}}]')
  # the config: the layers' digests in order, one history entry per layer
  read -r chex csize < <(jq -nc --argjson layers "$layers" \
    '{architecture:"",created:"0001-01-01T00:00:00Z",history:[$layers[] | {created:"0001-01-01T00:00:00Z"}],os:"",rootfs:{type:"layers",diff_ids:[$layers[].digest]},config:{}}' | put_blob "$dir")
  close_layout "$dir" "$chex" "$csize" "$layers"
}

short() { jq -c 'walk(if type == "string" and length > 120 then "\(.[0:32])... (\(length) characters)" else . end)' 2>/dev/null; } # JSON for a detail line

# The setup every case shares: a sandbox, and the registry, the real
# `crane registry serve` in memory on 127.0.0.1 on a port the kernel chooses
# (--address 127.0.0.1:0; crane 0.22.1 says the port on stderr, "serving on
# port N"). ONE trap stops the registry and removes the sandbox, on every way
# out of the suite: the end of the run, an early exit, and a signal, which is
# turned into an exit so that it leaves through the same trap (bash 5.2 ended
# by a signal sent to its whole process group does not always run an EXIT trap
# by itself, measured with HUP and TERM).
SB=$(mktemp -d)
REGISTRY_PID=""
cleanup() {
  if [ -n "$REGISTRY_PID" ]; then kill "$REGISTRY_PID" 2>/dev/null; wait "$REGISTRY_PID" 2>/dev/null; fi
  rm -rf "$SB"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
crane registry serve --address 127.0.0.1:0 > "$SB/registry.log" 2>&1 &
REGISTRY_PID=$!
# waited for until it answers, ten seconds at most
REGISTRY=""
for _ in $(seq 1 100); do
  port=$(sed -n 's/.*serving on port \([0-9][0-9]*\).*/\1/p' "$SB/registry.log" | head -n 1)
  if [ -n "$port" ] && crane catalog "127.0.0.1:$port" > /dev/null 2>&1; then REGISTRY="127.0.0.1:$port"; break; fi
  sleep 0.1
done
if [ -z "$REGISTRY" ]; then
  fail "the throwaway registry (crane registry serve --address 127.0.0.1:0) answers within ten seconds" \
    "no answer; what it said:" "$(cat "$SB/registry.log")"
  echo "$FAILURES failure(s)"; exit 1
fi

# cosign 2.6.5 on the old attestation layout, keyless and offline: the
# certificate against Fulcio's roots, its certificate transparency timestamp,
# the log entry's signed entry timestamp, the envelope's signature and the
# signer's identity, all from the three files and the layer's annotations.
# fulcio.pem holds the two roots only, so the intermediate certificate between
# a root and the signing certificate is the one in the layer's
# dev.sigstore.cosign/chain annotation: the chain the script wrote there is
# what the path is built from. Case 2 holds that with a control: the same
# layer without its chain is refused.
# --check-claims=false: the image asked about need not be the statement's
# subject. The accepted envelopes go to stdout, one per line.
verify_provenance() { # reference
  TUF_ROOT="$SB/tuf" SIGSTORE_ROOT_FILE="$ROOTS/fulcio.pem" SIGSTORE_REKOR_PUBLIC_KEY="$ROOTS/rekor0.pem" \
    SIGSTORE_CT_LOG_PUBLIC_KEY_FILE="$ROOTS/ctfe1.pem" \
    cosign verify-attestation --allow-insecure-registry --offline --check-claims=false --type slsaprovenance1 \
      --certificate-identity-regexp '^https://github.com/mm-weber/dhc-pipeline/' \
      --certificate-oidc-issuer https://token.actions.githubusercontent.com "$1"
}
mkdir "$SB/tuf"

# 1: the real tools accept what the script writes. A stand-in image in the
#    registry; beside the digest the statement names (the index) an attestation
#    manifest with one cosign-shaped layer that carries the chain; store adds
#    the provenance layer there with the real crane; crane reads both layers
#    back; and with that manifest copied to the stand-in image's own .att tag
#    cosign 2.6.5 verifies it as SLSA provenance v1 under the fixture
#    certificate's identity and issuer. The stand-in image is not the
#    statement's subject (hence --check-claims=false), so the subject is
#    asserted from the statement cosign accepted.
REPO="$REGISTRY/mm-weber/slsa-spike"
TAG=$(att_tag "$INDEX")
image_layout "$SB/image" "provenance-real case 1"; att_layout "$SB/att"
laid=$({ crane push "$SB/image" "$REPO:stand-in" && crane push "$SB/att" "$REPO:$TAG"; } 2>&1) && laid=""
IMAGE=$(crane digest "$REPO:stand-in" 2>/dev/null)
own=$(jq -r '.manifests[0].digest' "$SB/att/index.json"); own=$(jq -r '.layers[0].digest' "$SB/att/blobs/sha256/${own#sha256:}")
out=$(UNPACK_PROVENANCE_RETRY_DELAY=0 "$UNPACK" store "$DATA/bundle.jsonl" "$REPO" "$INDEX" 2>&1); rc=$?
[ "$rc" -eq 0 ] \
  && pass "store against the registry, with the real crane, exits 0" \
  || fail "store against the registry, with the real crane" "exit=$rc, wanted 0" "its output:" "${out:-none}" \
       "the stand-in image's digest: ${IMAGE:-none, it was not pushed}" "what a failed push of the suite's own two layouts said:" "${laid:-nothing, both went through}"
manifest=$(crane manifest "$REPO:$TAG" 2>&1)
count=$(jq '.layers | length' <<<"$manifest" 2>/dev/null)
first=$(jq -r '.layers[0].digest' <<<"$manifest" 2>/dev/null)
second=$(jq -r '.layers[1].annotations.predicateType' <<<"$manifest" 2>/dev/null)
[ "$count" = "2" ] && [ "$first" = "$own" ] && [ "$second" = "https://slsa.dev/provenance/v1" ] \
  && pass "crane manifest reads two layers back from the .att tag: the suite's own layer unchanged, then the SLSA provenance v1 layer" \
  || fail "the manifest read back with crane manifest from $REPO:$TAG" "layers: ${count:-none}, wanted 2" \
       "first layer's digest '${first:-none}', wanted the suite's own '$own'" \
       "second layer's predicateType '${second:-none}', wanted 'https://slsa.dev/provenance/v1'" \
       "the manifest read back:" "$(short <<<"$manifest" || echo "$manifest")"
copied=$(crane copy "$REPO:$TAG" "$REPO:$(att_tag "${IMAGE:-sha256:none}")" 2>&1) && copied=""
accepted=$(verify_provenance "$REPO@$IMAGE" 2> "$SB/cosign.err"); rc=$?
[ "$rc" -eq 0 ] \
  && pass "cosign verify-attestation --type slsaprovenance1 --offline, the trust root from files, exits 0 on the stand-in image" \
  || fail "cosign verify-attestation --type slsaprovenance1 --offline on $REPO@${IMAGE:-none}" "exit=$rc, wanted 0" \
       "the end of what cosign said:" "$(tail -n 8 "$SB/cosign.err" | cut -c1-400)" "what a failed crane copy to the stand-in image's .att tag said:" "${copied:-nothing, the copy went through}"
hex="${INDEX#sha256:}"
statements=$(jq -c '.payload | @base64d | fromjson | {predicateType, subject: [.subject[]? | .digest.sha256]}' <<<"$accepted" 2>/dev/null)
[ -n "$accepted" ] && jq -e -s --arg hex "$hex" \
  'length == 1 and (.[0].payload | @base64d | fromjson
     | .predicateType == "https://slsa.dev/provenance/v1" and any(.subject[]?; .digest.sha256 == $hex))' <<<"$accepted" > /dev/null 2>&1 \
  && pass "the one envelope cosign accepted is the provenance statement: predicateType SLSA provenance v1, the index digest among its subjects" \
  || fail "the envelope cosign accepted, decoded" "accepted, as predicateType and subject digests, one line each:" "${statements:-none}" \
       "wanted exactly one, of predicateType 'https://slsa.dev/provenance/v1', its subjects holding '$hex'"

# 2: the control on case 1: the real cosign refuses the provenance layer
#    without its chain. Case 1's manifest is pulled back with the real crane,
#    the dev.sigstore.cosign/chain annotation is taken off the provenance
#    layer alone (the suite's own layer keeps its chain; every other
#    annotation, both layer blobs and the config stay as they are), and that
#    copy is pushed to the .att tag of a second stand-in image. The same
#    repository: cosign finds the manifest by the image's digest in the tag,
#    and the blobs are already there. cosign 2.6.5, asked as in case 1, must
#    exit non-zero and name the certificate authority. Case 1's third line
#    shows the unchanged manifest accepted under a stand-in image's tag, so
#    the control differs from an accepted manifest in the one annotation (and
#    in the image whose tag it sits under). If cosign accepts the control, the
#    intermediate certificate reaches it from somewhere other than the chain
#    the script wrote, and case 1 no longer shows what it is there to show.
image_layout "$SB/control-image" "provenance-real case 2, the control"
staged=$({ crane push "$SB/control-image" "$REPO:control" && crane pull --format oci "$REPO:$TAG" "$SB/control"; } 2>&1) && staged=""
IMAGE2=$(crane digest "$REPO:control" 2>/dev/null)
TAG2=$(att_tag "${IMAGE2:-sha256:none}")
pulled=$(jq -r '.manifests[0].digest' "$SB/control/index.json" 2>/dev/null)
read -r mhex msize < <(jq -c 'del(.layers[] | select(.annotations.predicateType == "https://slsa.dev/provenance/v1") | .annotations."dev.sigstore.cosign/chain")' \
  "$SB/control/blobs/sha256/${pulled#sha256:}" 2>/dev/null | put_blob "$SB/control")
jq -c --arg digest "sha256:$mhex" --argjson size "${msize:-0}" '.manifests[0].digest = $digest | .manifests[0].size = $size' \
  "$SB/control/index.json" > "$SB/control/index.json.new" 2>/dev/null && mv "$SB/control/index.json.new" "$SB/control/index.json"
[ -n "$staged" ] || { staged=$(crane push "$SB/control" "$REPO:$TAG2" 2>&1) && staged=""; }
# the control is read back from the registry and held to what it claims to be:
# two layers, the suite's own first and with its chain, the provenance layer
# second and without one, and with case 1's chain put back there it is case
# 1's manifest again
control=$(crane manifest "$REPO:$TAG2" 2>&1)
exact=$(jq --argjson whole "$manifest" --arg own "$own" \
  '(.layers | length) == 2
   and .layers[0].digest == $own and (.layers[0].annotations | has("dev.sigstore.cosign/chain"))
   and .layers[1].annotations.predicateType == "https://slsa.dev/provenance/v1"
   and (.layers[1].annotations | has("dev.sigstore.cosign/chain") | not)
   and (.layers[1].annotations."dev.sigstore.cosign/chain" = $whole.layers[1].annotations."dev.sigstore.cosign/chain") == $whole' <<<"$control" 2>/dev/null)
verify_provenance "$REPO@$IMAGE2" > /dev/null 2> "$SB/control.err"; rc=$?
grep -q 'certificate signed by unknown authority' "$SB/control.err" && named="yes" || named="no"
why=("the control read back from $REPO:$TAG2 is case 1's manifest with the chain off the provenance layer alone: ${exact:-no}, wanted true"
     "cosign's exit on $REPO@${IMAGE2:-none}: $rc, wanted non-zero"
     "cosign names the certificate authority ('certificate signed by unknown authority'): $named, wanted yes")
if [ "$exact" != "true" ]; then
  why+=("the control is not the control it claims to be, so what cosign said of it says nothing about the chain"
        "its layers as read back, predicateType and chain, one line each:"
        "$(jq -r '.layers[] | "  \(.annotations.predicateType): \(.annotations."dev.sigstore.cosign/chain" | if . == null then "no chain" else "a chain of \(length) characters" end)"' <<<"$control" 2>/dev/null || echo "  none, no manifest was read back")"
        "the control as read back, then case 1's manifest:" "$(short <<<"$control" || echo "$control")" "$(short <<<"$manifest" || echo "$manifest")"
        "what a failed push or pull of the control's two layouts said:" "${staged:-nothing, all went through}")
elif [ "$rc" -eq 0 ]; then
  why+=("cosign ACCEPTED the provenance layer without its chain. What that means:"
        "the chain the script writes on the provenance layer is no longer read."
        "The intermediate certificate reaches cosign from somewhere else, most likely $ROOTS/fulcio.pem holds it again: it holds $(grep -c 'BEGIN CERTIFICATE' "$ROOTS/fulcio.pem") certificates, Fulcio's two roots alone are 2."
        "With that, case 1 no longer shows that a verifier configured with the roots alone can build the path from what the script wrote.")
else
  why+=("cosign refused the control, but not for the certificate authority; the end of what it said:" "$(tail -n 8 "$SB/control.err" | cut -c1-400)")
fi
[ "$exact" = "true" ] && [ "$rc" -ne 0 ] && [ "$named" = "yes" ] \
  && pass "the control: cosign refuses the same manifest with the chain off the provenance layer alone, and names the certificate authority" \
  || fail "the control: the manifest of case 1 with the chain off the provenance layer alone, under a second stand-in image, asked of cosign as in case 1" "${why[@]}"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all provenance-real tests passed"
