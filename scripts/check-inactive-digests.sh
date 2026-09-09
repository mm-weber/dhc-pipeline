#!/usr/bin/env bash
# check-inactive-digests.sh <root> <enumeration.tsv> <previous-status.md> <out.json>
#
# The detective half of Req 1.15 (review D7). Deactivating a definition
# (removing its line from catalogue-policy.yaml's active_set) must push no
# new digest and apply no new tag for it; build.yml's changes job is the
# preventive control (one filter point over the active set), and with every
# reference definition active that branch has never run in CI. This check
# asserts the outcome daily, whatever the path: for every inactive
# definition, each of its declared tags references today (the rescan's
# enumeration) the same digest it referenced at the last published status,
# and no tag it declares appeared since. The baseline is the status issue's
# fenced JSON block (repositories[].digests[].{digest, tags}, rewritten by
# every rescan), the one record that persists from one day to the next.
#
# The comparison is per tag, never per repository: a runtime definition and
# its compat variant publish one repository, so the active sibling moving is
# not the inactive one's gain.
#
# Outcomes, each named:
# - no inactive definition: nothing to assert, exit 0;
# - no previous status (first run, or the issue is gone): a warning naming
#   the inactive definitions, exit 0, asserted 0 in the record;
# - a tag moved to a digest the last status did not list, or a declared tag
#   the last status did not know: ::error per gain, exit 1;
# - a malformed active set: the reader's refusal (exit 2), passed through.
# <out.json> records active, inactive, asserted (tags compared) and gains.
set -euo pipefail

ROOT="${1:?usage: check-inactive-digests.sh <root> <enumeration.tsv> <previous-status.md> <out.json>}"
ENUM="${2:?enumeration.tsv}"; PREVIOUS="${3:?previous-status.md}"; OUT="${4:?out.json}"
# shellcheck source=scripts/definition-lib.sh
. "$(cd "$(dirname "$0")" && pwd)/definition-lib.sh"
err() { printf '::error::check-inactive-digests: %s\n' "$1" >&2; }
[ -f "$ENUM" ] || { err "no enumeration at ${ENUM}; nothing can be asserted (Req 1.15)"; exit 1; }
[ -f "$PREVIOUS" ] || { err "no previous status file at ${PREVIOUS} (the step that fetches it reports why)"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

active_definitions "$ROOT" > "$WORK/active" || exit $?
: > "$WORK/inactive"
for f in "$ROOT"/image/*/image.yaml; do
  [ -f "$f" ] || continue
  name=$(basename "$(dirname "$f")")
  grep -qxF "$name" "$WORK/active" || echo "$name" >> "$WORK/inactive"
done
n_active=$(wc -l < "$WORK/active"); n_inactive=$(wc -l < "$WORK/inactive")
inactive_json=$(jq -R . "$WORK/inactive" | jq -sc .)
inactive_names=$(paste -sd, "$WORK/inactive" | sed 's/,/, /g')

if [ "$n_inactive" -eq 0 ]; then
  jq -n --argjson active "$n_active" --argjson inactive "$inactive_json" \
    '{active: $active, inactive: $inactive, asserted: 0, gains: []}' > "$OUT"
  echo "check-inactive-digests: ${n_active} active, 0 inactive; nothing to assert today (Req 1.15)"
  exit 0
fi

# The baseline: the last fenced json block of the previous status body, the
# same block the status tool reads (ExtractFencedJSON); empty when there is
# no previous status.
awk '/^```json$/ { inblock = 1; cur = ""; next }
     /^```$/ { if (inblock) { last = cur; inblock = 0 }; next }
     inblock { cur = cur $0 "\n" }
     END { printf "%s", last }' "$PREVIOUS" > "$WORK/baseline.json"
if ! [ -s "$WORK/baseline.json" ] || ! jq -e '.repositories | type == "array"' "$WORK/baseline.json" > /dev/null 2>&1; then
  jq -n --argjson active "$n_active" --argjson inactive "$inactive_json" \
    '{active: $active, inactive: $inactive, asserted: 0, gains: []}' > "$OUT"
  echo "::warning::check-inactive-digests: no previous status to compare against; nothing asserted today for ${inactive_names} (Req 1.15)"
  exit 0
fi

# Today's tag -> digest per inactive definition, from the enumeration
# (repository, tag, tag-digest, ...), one row per tag whatever its platforms.
: > "$WORK/gains"
asserted=0
while IFS= read -r name; do
  def="$ROOT/image/$name/image.yaml"
  repo=$(published_repository "$def")
  [ -n "$repo" ] || { err "no image: value in image/${name}/image.yaml"; exit 1; }
  python3 - "$def" <<'PY' > "$WORK/tags"
import sys, yaml
for t in (yaml.safe_load(open(sys.argv[1])) or {}).get("tags") or []:
    print(t)
PY
  while IFS= read -r tag; do
    [ -n "$tag" ] || continue
    digest=$(awk -F'\t' -v r="$repo" -v t="$tag" '$1 == r && $2 == t { print $3; exit }' "$ENUM")
    [ -n "$digest" ] || continue # not published today: nothing to hold
    asserted=$((asserted + 1))
    previous=$(jq -r --arg r "$repo" --arg t "$tag" \
      '[.repositories[] | select(.repository == $r) | .digests[] | select(.tags | index($t)) | .digest] | first // ""' "$WORK/baseline.json")
    if [ -z "$previous" ]; then
      err "inactive definition ${name} gained a tag: ${tag} now references ${digest:0:18} (not published at the last status); deactivation pushes no digest and applies no tag (Req 1.15)"
      jq -nc --arg d "$name" --arg t "$tag" --arg n "$digest" '{definition: $d, tag: $t, digest: $n, previous: null}' >> "$WORK/gains"
    elif [ "$previous" != "$digest" ]; then
      err "inactive definition ${name} gained a digest: ${tag} now references ${digest:0:18} (was ${previous:0:18} at the last status); deactivation pushes no digest and applies no tag (Req 1.15)"
      jq -nc --arg d "$name" --arg t "$tag" --arg n "$digest" --arg p "$previous" '{definition: $d, tag: $t, digest: $n, previous: $p}' >> "$WORK/gains"
    fi
  done < "$WORK/tags"
done < "$WORK/inactive"

gains=$(jq -sc . "$WORK/gains")
jq -n --argjson active "$n_active" --argjson inactive "$inactive_json" --argjson asserted "$asserted" --argjson gains "$gains" \
  '{active: $active, inactive: $inactive, asserted: $asserted, gains: $gains}' > "$OUT"
n_gains=$(jq length <<<"$gains")
if [ "$n_gains" -gt 0 ]; then
  err "${n_gains} gain(s) under inactive definitions since the last status; a deactivated definition is being published (Req 1.15)"
  exit 1
fi
echo "check-inactive-digests: ${asserted} tag(s) of ${n_inactive} inactive definition(s) (${inactive_names}) unchanged since the last status (Req 1.15)"
