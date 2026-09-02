#!/usr/bin/env bash
# enumerate-catalogue.sh <root> <out-tsv>
#
# The daily enumeration Req 2.22 hangs everything on (task 9.3): every
# catalogue tag in every catalogue repository, resolved to the platform
# manifests a scan must cover. One row per scannable manifest:
#
#   repository \t tag \t tag-digest \t platform \t manifest-digest \t supported|superseded
#
# - Repositories are the distinct `image:` values across <root>/image/*/
#   definitions (definition-lib's published_repository): the variant case
#   makes this a set, valkey and valkey-compat are ONE repository.
# - Tags come from the registry itself (`crane ls`), because the registry
#   holds tags no current definition lists; cosign's sha256-* bookkeeping
#   tags are not catalogue tags (requirements.md, Terms) and are dropped.
# - The tag's digest is sha256 over the raw manifest bytes
#   (`imagetools inspect --raw`), the same digest a pull pins.
# - An index contributes its platform manifests, with unknown/unknown and
#   BuildKit's vnd.docker.reference.type annotation excluded (the Req 2
#   platform-manifest definition); a bare image manifest contributes itself,
#   platform `-` (Req 2.22's "or, for a single image manifest, that digest
#   itself"). Scanning BY MANIFEST DIGEST is the point: task 8.3 measured
#   that `--platform` without `--image-src remote` is silently ignored, and a
#   digest ref has nothing left to downgrade.
# - supported: some CURRENT definition of this repository lists the tag;
#   everything else is superseded — still scanned daily, outside the scope
#   of issues and clocks (Terms; task 9.5 records the first such sweep).
#
# Refusals, not warnings: a repository that cannot be listed or a manifest
# that cannot be read makes the enumeration partial while looking complete,
# and Req 2.22 promises the enumeration itself. The caller decides what a
# failed SCAN means; this script only ever lies by omission, so it refuses
# to omit.
set -euo pipefail

err() { printf '::error::enumerate-catalogue: %s\n' "$1" >&2; }

if [ "$#" -ne 2 ]; then
  err "usage: enumerate-catalogue.sh <root> <out-tsv>"
  exit 2
fi
ROOT="$1"; OUT="$2"

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=definition-lib.sh
. "$HERE/definition-lib.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# repository -> its supported tags, one "repo tag" line per pair. python3
# rather than yq: the runner ships mikefarah yq, the devcontainer a python
# wrapper, and their dialects disagree (build.yml's tr-strip comment); the
# stdlib parser reads both worlds identically. compile-vex.sh precedent.
: > "$WORK/supported"
: > "$WORK/repos"
for f in "$ROOT"/image/*/image.yaml; do
  [ -f "$f" ] || continue
  repo=$(published_repository "$f")
  [ -n "$repo" ] || { err "no image: value in ${f}"; exit 1; }
  echo "$repo" >> "$WORK/repos"
  python3 - "$f" "$repo" <<'PY' >> "$WORK/supported"
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
for t in doc.get("tags") or []:
    print(f"{sys.argv[2]}\t{t}")
PY
done
LC_ALL=C sort -u "$WORK/repos" -o "$WORK/repos"
LC_ALL=C sort -u "$WORK/supported" -o "$WORK/supported"

: > "$WORK/rows"
while IFS= read -r repo; do
  if ! crane ls "$repo" > "$WORK/tags" 2>"$WORK/crane.err"; then
    err "cannot list tags of ${repo}: $(tr -d '\n' < "$WORK/crane.err") — the enumeration would be partial, refusing (Req 2.22)"
    exit 1
  fi
  # Catalogue tags only: cosign stores signatures and attestations under
  # sha256-<digest>.sig/.att tags beside the image, and those are artifacts
  # ABOUT digests, not references to scan.
  grep -vE '^sha256-' "$WORK/tags" | LC_ALL=C sort > "$WORK/tags.catalogue" || true

  while IFS= read -r tag; do
    [ -n "$tag" ] || continue
    ref="${repo}:${tag}"
    if ! docker buildx imagetools inspect --raw "$ref" > "$WORK/raw" 2>"$WORK/raw.err"; then
      err "cannot read the manifest of ${ref}: $(tr -d '\n' < "$WORK/raw.err") — refusing a partial enumeration (Req 2.22)"
      exit 1
    fi
    digest="sha256:$(sha256sum "$WORK/raw" | cut -d' ' -f1)"
    if ! jq -e . "$WORK/raw" >/dev/null 2>&1; then
      err "${ref} served bytes that do not parse as a manifest"
      exit 1
    fi
    status=superseded
    if grep -qxF "$(printf '%s\t%s' "$repo" "$tag")" "$WORK/supported"; then status=supported; fi
    if jq -e '.manifests | type == "array"' "$WORK/raw" >/dev/null 2>&1; then
      jq -r --arg repo "$repo" --arg tag "$tag" --arg digest "$digest" --arg status "$status" '
        .manifests[]
        | select(((.platform.os // "unknown") + "/" + (.platform.architecture // "unknown")) != "unknown/unknown")
        | select((.annotations["vnd.docker.reference.type"] // "") == "")
        | [$repo, $tag, $digest, (.platform.os + "/" + .platform.architecture), .digest, $status]
        | @tsv' "$WORK/raw" >> "$WORK/rows"
    else
      printf '%s\t%s\t%s\t-\t%s\t%s\n' "$repo" "$tag" "$digest" "$digest" "$status" >> "$WORK/rows"
    fi
  done < "$WORK/tags.catalogue"
done < "$WORK/repos"

LC_ALL=C sort "$WORK/rows" > "$OUT"
echo "enumerate-catalogue: $(wc -l < "$OUT") platform manifest(s) across $(wc -l < "$WORK/repos") repositories -> ${OUT}"
