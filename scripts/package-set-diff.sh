#!/usr/bin/env bash
# package-set-diff.sh <definition> <published-ref> <local-index-digest|-> \
#                     <verdict-out> <platform>=<local-cdx.json> [...]
#
# The publish-on-change comparator (task 9.2, Req 2.15-2.17): decides whether
# a scheduled rebuild changed anything a consumer could receive, by comparing
# the canonicalised package set of the local build against the one recorded in
# the CycloneDX SBOMs attested to the digest the full release tag points at.
#
# The published side is READ THROUGH VERIFICATION (review disposition D2,
# 2026-09-09): `cosign verify-attestation --type cyclonedx` against the
# issuer and the identities catalogue-policy.yaml admits for cyclonedx, the
# same read scripts/fetch-sboms.sh makes for the issue lifecycle (Req 6.58).
# Until then this script used `cosign download attestation`, which reads any
# attestation under the repository regardless of who signed it, so an
# attestation from any identity could have made the nightly discard a
# rebuild. The policy file is found under PACKAGE_SET_DIFF_ROOT, defaulting
# to this script's parent directory; no admitted identity is a refusal.
#
# The projection is exactly what Req 2.15 names and nothing else: package
# type, name and version (the purl with its qualifiers dropped) plus the
# package pull checksum (syft's `syft:metadata:pullChecksum` property; apk
# carries one, Go binaries none), sorted, per platform manifest. Never raw
# SBOM bytes: syft's ordering, CPE enumeration and package-id qualifiers are
# not stable across runs (anchore/syft #331, #2967; measured 2026-09-01, the
# first 9.1 release and its local rebuild canonicalise equal while their
# bytes differ). The checksum is in the set so a package republished under an
# unchanged version, the CVE-2026-33634 shape, still reads as a change.
#
# Verdicts, written GITHUB_OUTPUT-style to <verdict-out>; the DECISION stays
# with the workflow, like scan-image.sh before it:
#
#   verdict=equal        every platform's set matches; also digest_equal=
#                        true|false|unmeasured, the free nightly
#                        reproducibility measurement (Decision 6): whether
#                        the rebuilt index digest equals the published one.
#                        Measured, never gated on.
#   verdict=different    plus reason=package-set-differs | no-published-digest
#                        | attestation-unreadable | platform-set-differs.
#                        Equality is the only thing that suppresses a publish,
#                        so equality must be PROVEN: an unresolvable tag, a
#                        missing CycloneDX attestation or mismatched platform
#                        sets all publish (Req 2.16), with the reason named.
#
# Exit 0 for either verdict. Exit 2 refuses: bad usage, a local SBOM that
# does not parse, a policy file naming no issuer or no role that attests
# cyclonedx, or a tool this script needs (docker, cosign, jq) missing
# from PATH, because each of those means our own build or environment is
# broken and no comparison can be trusted. A missing tool is NOT an
# unreadable attestation: measured 2026-09-08, build.yml installed cosign
# only in the release part, after this comparator, so "cosign: command not
# found" read as attestation-unreadable and every nightly rebuild published
# every definition from 2026-09-02 on.
set -euo pipefail

err() { printf '::error::package-set-diff: %s\n' "$1" >&2; }

if [ "$#" -lt 5 ]; then
  err "usage: package-set-diff.sh <definition> <published-ref> <local-index-digest|-> <verdict-out> <platform>=<cdx.json> [...]"
  exit 2
fi
NAME="$1"; REF="$2"; LOCAL_DIGEST="$3"; OUT="$4"; shift 4
ROOT="${PACKAGE_SET_DIFF_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# The environment is checked before anything is read: a tool that is not
# there is a refusal, never a verdict, so a broken runner can neither publish
# nor discard.
for tool in docker cosign jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    err "$tool is not on PATH; the comparator cannot read the published side, and a tool that is missing is our environment broken, not a difference (install it before this step)"
    exit 2
  fi
done

# The identities the published side is read through (Req 2.23's declared
# inputs): the issuer and every role that attests cyclonedx. None is a
# refusal, since nothing could then be verified and nothing proven equal.
[ -f "$ROOT/catalogue-policy.yaml" ] || { err "no catalogue-policy.yaml under ${ROOT}; the admitted identities are declared there (Req 2.23)"; exit 2; }
ISSUER=$(python3 -c 'import sys,yaml; print((yaml.safe_load(open(sys.argv[1])) or {}).get("verification",{}).get("issuer",""))' "$ROOT/catalogue-policy.yaml")
mapfile -t IDS < <(python3 - "$ROOT/catalogue-policy.yaml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1])) or {}
for role in ((doc.get("verification") or {}).get("roles") or {}).values():
    if "cyclonedx" in (role.get("attests") or []) and role.get("identity"):
        print(role["identity"])
PY
)
if [ -z "$ISSUER" ] || [ "${#IDS[@]}" -eq 0 ]; then
  err "catalogue-policy.yaml names no issuer or no role that attests cyclonedx; the published SBOM cannot be read through verification, so equality cannot be proven (Req 2.15, 2.23)"
  exit 2
fi

declare -A local_cdx=()
for pair in "$@"; do
  case "$pair" in
    *=*) local_cdx["${pair%%=*}"]="${pair#*=}" ;;
    *) err "'${pair}' is not <platform>=<cdx.json>"; exit 2 ;;
  esac
done

# The requirement's projection: purl base (type/name/version) plus pull
# checksum where one exists. Only components with a purl are packages; files
# and the operating-system entry are content, not packages.
project() { # <cdx.json> -> sorted canonical lines on stdout
  jq -r '.components[]
         | select((.purl // "") != "")
         | (.purl | split("?")[0]) + "\t"
           + (([.properties[]? | select(.name == "syft:metadata:pullChecksum") | .value] | first) // "-")' \
    "$1" | LC_ALL=C sort -u
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Local SBOMs are validated before anything else, network included: a local
# document that does not parse is a broken build, not a difference.
for p in "${!local_cdx[@]}"; do
  f="${local_cdx[$p]}"
  if ! jq -e '.components | type == "array"' "$f" >/dev/null 2>&1; then
    err "${NAME}: local CycloneDX for ${p} (${f}) does not parse as a component list; the rebuild output is broken, refusing to compare"
    exit 2
  fi
  project "$f" > "$WORK/local-${p//\//-}.set"
done

: > "$OUT"
emit() { printf '%s=%s\n' "$1" "$2" >> "$OUT"; }
different() { # <reason> <message>
  emit verdict different
  emit reason "$1"
  echo "package-set-diff: ${NAME}: DIFFERENT (${1}): ${2}"
  exit 0
}

# The published side, resolved from the registry. No tag means nothing to be
# equal to (first scheduled run after a definition lands): publish.
if ! docker buildx imagetools inspect --raw "$REF" > "$WORK/index.json" 2>"$WORK/inspect.err"; then
  different no-published-digest "no published digest carries ${REF} ($(tr -d '\n' < "$WORK/inspect.err"))"
fi
pub_digest="sha256:$(sha256sum "$WORK/index.json" | cut -d' ' -f1)"

# Platform manifests exactly as Req 2 defines the term: unknown/unknown and
# BuildKit's reference-type annotation excluded.
jq -r '.manifests[]
       | select(((.platform.os // "unknown") + "/" + (.platform.architecture // "unknown")) != "unknown/unknown")
       | select((.annotations["vnd.docker.reference.type"] // "") == "")
       | (.platform.os + "/" + .platform.architecture) + "\t" + .digest' \
  "$WORK/index.json" > "$WORK/pub-manifests"

printf '%s\n' "${!local_cdx[@]}" | LC_ALL=C sort > "$WORK/local-platforms"
cut -f1 "$WORK/pub-manifests" | LC_ALL=C sort > "$WORK/pub-platforms"
if ! cmp -s "$WORK/local-platforms" "$WORK/pub-platforms"; then
  different platform-set-differs \
    "rebuilt [$(paste -sd, "$WORK/local-platforms")] vs published [$(paste -sd, "$WORK/pub-platforms")]"
fi

repo="${REF%:*}"
any_diff=""
while IFS=$'\t' read -r platform digest; do
  # The attested CycloneDX document for this platform manifest, read only
  # through verification against an admitted identity (D2, the fetch-sboms
  # read): the first role whose signature verifies wins; equality that cannot
  # be read this way is equality that cannot be claimed.
  : > "$WORK/pub.cdx.json"; : > "$WORK/cosign.err"
  for id in "${IDS[@]}"; do
    if cosign verify-attestation --type cyclonedx --certificate-oidc-issuer "$ISSUER" --certificate-identity "$id" "${repo}@${digest}" </dev/null 2>>"$WORK/cosign.err" \
         | jq -cn 'first(inputs | .payload | @base64d | fromjson
                         | select(.predicateType == "https://cyclonedx.org/bom") | .predicate)' > "$WORK/pub.cdx.json" 2>/dev/null \
       && [ -s "$WORK/pub.cdx.json" ]; then
      break
    fi
    : > "$WORK/pub.cdx.json"
  done
  if [ ! -s "$WORK/pub.cdx.json" ]; then
    different attestation-unreadable \
      "no CycloneDX attestation on ${platform} (${repo}@${digest}) verifies against an admitted identity ($(printf '%s, ' "${IDS[@]}" | sed 's/, $//')): $(grep -v '^$' "$WORK/cosign.err" | tail -n1 | tr -d '\n')"
  fi
  project "$WORK/pub.cdx.json" > "$WORK/pub-${platform//\//-}.set"

  if cmp -s "$WORK/pub-${platform//\//-}.set" "$WORK/local-${platform//\//-}.set"; then
    echo "package-set-diff: ${NAME} ${platform}: equal ($(wc -l < "$WORK/local-${platform//\//-}.set") packages)"
    sed 's/^/  = /' "$WORK/local-${platform//\//-}.set"
  else
    any_diff=1
    echo "package-set-diff: ${NAME} ${platform}: package set differs (published vs rebuilt):"
    diff --label published --label rebuilt -u \
      "$WORK/pub-${platform//\//-}.set" "$WORK/local-${platform//\//-}.set" || true
  fi
done < "$WORK/pub-manifests"

if [ -n "$any_diff" ]; then
  emit verdict different
  emit reason package-set-differs
  exit 0
fi

emit verdict equal
# The free nightly reproducibility measurement (Decision 6,
# data/reproducible-digests-vs-content-diff-2026-08-22.md): with the sets
# equal, did the rebuild also mint the same index digest? Logged, never
# gated on; the condition that would promote this to the gate lives in the
# memo.
if [ "$LOCAL_DIGEST" = "-" ]; then
  emit digest_equal unmeasured
  echo "package-set-diff: ${NAME}: sets equal; index digest not measured"
elif [ "$LOCAL_DIGEST" = "$pub_digest" ]; then
  emit digest_equal true
  echo "package-set-diff: ${NAME}: sets equal and the rebuild reproduced the published index digest (${pub_digest})"
else
  emit digest_equal false
  echo "package-set-diff: ${NAME}: sets equal; rebuilt index ${LOCAL_DIGEST} != published ${pub_digest} (expected while provenance carries timestamps)"
fi
exit 0
