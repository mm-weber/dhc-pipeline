#!/usr/bin/env bash
# check-visibility.sh <root> <enumeration.tsv>
#
# The first daily invariant (task 9.4, Req 2.21): WHILE public release is
# enabled, every catalogue repository must hand a pull token to an
# UNAUTHENTICATED request, and every catalogue tag's manifest must be served
# to one. Two probes on purpose: a token is not a pull, a public repository
# whose tags were deleted still issues one. Measured 2026-08-21: two
# repositories were quietly private and nothing said so until a human looked;
# this makes the registry's actual answer a daily assertion.
#
# Probes are curl with NO credentials, deliberately not crane or docker: the
# rescan job logs into ghcr for its scans, and any tool that reads ambient
# credentials would verify the wrong question ("can WE pull?" instead of
# "can ANYONE?"). The manifest probe carries only the anonymous token the
# registry itself just issued.
#
# Repositories come from the definitions (every repository definition-lib
# knows, so a repository whose tags all vanished is still probed); tags come
# from the enumeration the rescan just produced (9.3), so the two invariants
# share one view of the world. Every failing repository or tag is reported by
# name and any failure fails the run (Req 2.21); a missing enumeration is a
# refusal, because an invariant verified against nothing has verified
# nothing.
set -euo pipefail

err() { printf '::error::check-visibility: %s\n' "$1" >&2; }

if [ "$#" -ne 2 ]; then
  err "usage: check-visibility.sh <root> <enumeration.tsv>"
  exit 2
fi
ROOT="$1"; ENUM="$2"

if [ ! -f "$ENUM" ]; then
  err "enumeration ${ENUM} does not exist; refusing a vacuous pass (Req 2.21 binds to the enumeration)"
  exit 2
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=definition-lib.sh
. "$HERE/definition-lib.sh"

# python3, not yq: the runner and the devcontainer ship different yq dialects
# (compile-vex.sh precedent).
read -r PUBLIC REGISTRY < <(python3 - "$ROOT/catalogue-policy.yaml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
public = str((doc.get("release") or {}).get("public", False)).lower()
print(public, (doc.get("verification") or {}).get("registry", ""))
PY
)

if [ "$PUBLIC" != "true" ]; then
  echo "check-visibility: public release is disabled (catalogue-policy.yaml release.public); the visibility invariant does not apply (Req 2.21's WHILE clause)"
  exit 0
fi
if [ -z "$REGISTRY" ]; then
  err "catalogue-policy.yaml declares no verification.registry"
  exit 2
fi
HOST="${REGISTRY%%/*}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

failures=0
declare -A token_of=()

# Probe 1, per repository: an anonymous pull token.
for f in "$ROOT"/image/*/image.yaml; do
  [ -f "$f" ] || continue
  published_repository "$f"
done | LC_ALL=C sort -u > "$WORK/repos"

while IFS= read -r repo; do
  path="${repo#"${HOST}"/}"
  code=$(curl -s -o "$WORK/token.json" -w '%{http_code}' \
    "https://${HOST}/token?scope=repository:${path}:pull" || echo 000)
  if [ "$code" != "200" ]; then
    err "repository ${repo} answered ${code} to an unauthenticated pull-token request; a consumer without credentials cannot pull it (Req 2.21)"
    failures=$((failures + 1))
  else
    token_of[$repo]=$(jq -r '.token // empty' "$WORK/token.json" 2>/dev/null || true)
  fi
done < "$WORK/repos"

# Probe 2, per catalogue tag: the manifest itself, with only the anonymous
# token. Platform rows collapse to tags; the digest columns are 9.3's
# business, not this invariant's.
cut -f1,2 "$ENUM" | LC_ALL=C sort -u > "$WORK/tags"
tags=0
while IFS=$'\t' read -r repo tag; do
  [ -n "$repo" ] || continue
  tags=$((tags + 1))
  path="${repo#"${HOST}"/}"
  auth=()
  [ -n "${token_of[$repo]:-}" ] && auth=(-H "Authorization: Bearer ${token_of[$repo]}")
  code=$(curl -s -o /dev/null -w '%{http_code}' "${auth[@]}" \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json' \
    "https://${HOST}/v2/${path}/manifests/${tag}" || echo 000)
  if [ "$code" != "200" ]; then
    err "${repo}:${tag} answered ${code} to an unauthenticated manifest request; the tag is not being served (Req 2.21)"
    failures=$((failures + 1))
  fi
done < "$WORK/tags"

if [ "$failures" -gt 0 ]; then
  err "${failures} visibility failure(s); the catalogue is promising public images it is not serving"
  exit 1
fi
echo "check-visibility: $(wc -l < "$WORK/repos") repositories and ${tags} tags all answer an unauthenticated request (Req 2.21)"
