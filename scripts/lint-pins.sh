#!/usr/bin/env bash
# lint-pins.sh [root] — enforce the pinning convention (docs/CONVENTIONS.md):
# every `image:` / `base:` reference under image/ and chart/ carries an
# @sha256 digest. Tag-only, :latest, and bare (implicit latest) references
# fail with a GitHub error annotation naming the reference (Req 1.6, 7.4).
#
# Scope note: only whole-reference keys are checked. Split repository/tag/
# digest keys in chart values are validated by their chart's own config
# conventions once definitions exist; extend here when that lands.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
violations=0

scan_dirs=()
[ -d "$ROOT/image" ] && scan_dirs+=("$ROOT/image")
[ -d "$ROOT/chart" ] && scan_dirs+=("$ROOT/chart")
[ ${#scan_dirs[@]} -eq 0 ] && { echo "lint-pins: nothing to scan"; exit 0; }

while IFS= read -r -d '' file; do
  rel="${file#"$ROOT"/}"
  while IFS=$'\t' read -r line_no ref; do
    # strip surrounding quotes and trailing comments
    ref="${ref%%[[:space:]]#*}"
    ref="${ref%\"}"; ref="${ref#\"}"
    ref="${ref%\'}"; ref="${ref#\'}"
    [ -z "$ref" ] && continue
    if [[ "$ref" != *"@sha256:"* ]]; then
      echo "::error file=${rel},line=${line_no}::pinning convention (docs/CONVENTIONS.md): floating reference '${ref}' — pin by @sha256 digest"
      violations=$((violations + 1))
    fi
  done < <(awk 'match($0, /^[[:space:]]*(-[[:space:]]+)?(image|base):[[:space:]]*/) {
                  val = substr($0, RSTART + RLENGTH)
                  if (val != "") printf "%d\t%s\n", NR, val
                }' "$file")
done < <(find "${scan_dirs[@]}" -type f -name '*.yaml' -print0)

if [ "$violations" -gt 0 ]; then
  echo "lint-pins: ${violations} floating reference(s) — see docs/CONVENTIONS.md (Pinning)"
  exit 1
fi
echo "lint-pins: all image/base references digest-pinned"
