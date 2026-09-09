#!/usr/bin/env bash
# render-tracking.sh [--check] [root]: render the tracking scope into
# renovate.json5 (task 14.2; Req 1.14, 3.2, 3.11).
#
# Renovate cannot read catalogue-policy.yaml, so the active set reaches it as
# an `ignorePaths` block between the `// render-tracking:begin` and
# `// render-tracking:end` markers: one glob per inactive definition
# directory (image/<name>/**) and one per chart directory deploying no active
# definition (chart/<c>/**), each with the reason as a trailing comment.
# Renovate skips every package file under an ignored path before any manager
# reads it (measured on 41.173.1), so no bump opens for a frozen definition or
# for the chart that would deploy it; validate's lint-active-set.sh is the
# backstop for a bump that arrives anyway (Req 1.16). With everything active,
# the reference instance's state, the block is `ignorePaths: [],`, and the
# managers' own file patterns keep node_modules and the like out regardless
# (every one is anchored to a repository path), so Renovate's default
# ignores are not missed.
#
# Line-based splicing between the markers, never a JSON5 round trip: the file
# carries load-bearing comments a parser would drop. --check re-renders and
# fails naming the file when the committed block differs (Req 7.9 pattern);
# validate.yml runs it on every pull request. The active set and each
# chart's deploys list are read through scripts/definition-lib.sh, so a
# malformed set is that reader's refusal, never a rendered guess.
set -euo pipefail

MODE=render
if [ "${1:-}" = "--check" ]; then MODE=check; shift; fi
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ROOT="${ROOT%/}"
FILE="$ROOT/renovate.json5"
BEGIN='// render-tracking:begin'
END='// render-tracking:end'

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/definition-lib.sh
. "$HERE/definition-lib.sh"

[ -f "$FILE" ] || { echo "::error::render-tracking: no renovate.json5 under ${ROOT}" >&2; exit 1; }
if ! grep -qF "$BEGIN" "$FILE" || ! grep -qF "$END" "$FILE"; then
  echo "::error file=renovate.json5::render-tracking: renovate.json5 lacks the ${BEGIN} / ${END} markers" >&2
  exit 1
fi

active=$(active_definitions "$ROOT") # a refusal exits here, under set -e, with its own message
is_active() { printf '%s\n' "$active" | grep -qxF -- "$1"; }

entries=()
for f in "$ROOT"/image/*/image.yaml; do
  [ -f "$f" ] || continue
  n="${f%/image.yaml}"; n="${n##*/}"
  is_active "$n" || entries+=("    \"image/${n}/**\", // inactive definition (catalogue-policy.yaml active_set)")
done
for d in "$ROOT"/chart/*/; do
  [ -d "$d" ] || continue
  c="${d%/}"; c="${c##*/}"
  [ -f "$d/chart.yaml" ] || continue
  any=false
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    is_active "$n" && any=true
  done < <(chart_deploys "$d/chart.yaml")
  [ "$any" = true ] || entries+=("    \"chart/${c}/**\", // chart adaptation deploying no active definition")
done

WORK=$(mktemp)
trap 'rm -f "$WORK"' EXIT
{
  sed -n "1,/$(printf '%s' "$BEGIN" | sed 's#[/]#\\/#g')/p" "$FILE"
  if [ "${#entries[@]}" -eq 0 ]; then
    echo "  ignorePaths: [],"
  else
    echo "  ignorePaths: ["
    printf '%s\n' "${entries[@]}"
    echo "  ],"
  fi
  sed -n "/$(printf '%s' "$END" | sed 's#[/]#\\/#g')/,\$p" "$FILE"
} > "$WORK"

if [ "$MODE" = check ]; then
  if ! cmp -s "$WORK" "$FILE"; then
    echo "::error file=renovate.json5::render-tracking: renovate.json5's tracking-scope block differs from its rendered form (Req 7.9); edit catalogue-policy.yaml's active_set or a chart's deploys list and re-run scripts/render-tracking.sh"
    exit 1
  fi
  echo "render-tracking: renovate.json5's tracking-scope block matches the active set (${#entries[@]} ignored path(s))"
else
  cp "$WORK" "$FILE"
  echo "render-tracking: rendered ${#entries[@]} ignored path(s) into renovate.json5 from catalogue-policy.yaml's active set"
fi
