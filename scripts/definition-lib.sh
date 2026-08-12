#!/usr/bin/env bash
# definition-lib.sh — reading a definition's published identity. Sourced, not run.
#
# One fact, four readers. A definition's directory name equalled the last segment
# of its `image:` for every definition until image/valkey-compat/, which publishes
# to its runtime sibling's repository as a `-compat` tag (docs/CONVENTIONS.md,
# "Naming"). Everything that has to map between a directory and a published image
# name goes through here: scripts/compile-vex.sh, scripts/lint-pins.sh,
# scripts/lint-vex-product.sh, and build.yml's affected-definitions step.
#
# Shared rather than copied because of the failure mode, not the line count. The
# reader that misses a spelling does not error — it resolves to the directory
# name, which Trivy never produces, and a statement that suppresses nothing
# reports as a clean compile. Four copies of this awk is four places a quoting
# fix has to land and three chances to leave one of them inert.

# The repository a definition publishes, verbatim from its top-level `image:`.
# Tolerates a trailing comment and surrounding quotes; first match wins, because
# `image:` is a single top-level scalar.
published_repository() { # definition path
  awk 'sub(/^image:[[:space:]]*/, "") {
         sub(/[[:space:]]*#.*$/, ""); sub(/[[:space:]]+$/, "")
         gsub(/^["'\'']|["'\'']$/, "")
         print; exit
       }' "$1"
}

# Every definition under <root>/image whose published repository ends in <name>,
# as paths relative to <root>. Two results is the runtime/variant case and is
# normal; callers that need one comparison value can take the first, since all
# of them publish the same repository by construction.
#
# Keyed on the published repository rather than on a `-<variant>` name suffix, so
# the three cert-manager definitions — one monorepo, three repositories — are
# correctly not a set.
definitions_publishing() { # root, image name
  local f repo
  for f in "$1"/image/*/image.yaml; do
    [ -f "$f" ] || continue
    repo="$(published_repository "$f")"
    [ "${repo##*/}" = "$2" ] && printf '%s\n' "${f#"$1"/}"
  done
  return 0 # a non-matching last iteration is not a failure
}
