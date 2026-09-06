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

# --- authenticity (Req 1.10, 1.11, 3.8; task 11.2) ---------------------------
# Each definition declares, beside its source url, how its upstream's
# authenticity is established:
#   # authenticity: signed-tag              an annotated tag GitHub verifies
#   # authenticity: signed-commit           a lightweight tag on a commit GitHub verifies
#   # authenticity: cross-origin-checksum   two origins state the same checksum
# A refresh appends what it verified and when, so the diff carries the
# evidence: "# authenticity: signed-tag, verified v1.21.2 (GitHub verification:
# valid), 2026-09-06". The class is the first word after the colon.
# shellcheck disable=SC2034  # read by lint-pins.sh, which sources this file
AUTHENTICITY_CLASSES="signed-tag signed-commit cross-origin-checksum"

authenticity_class() { # definition path -> the class (empty: no marker)
  local line
  line=$(grep -m1 -E '^[[:space:]]*#[[:space:]]*authenticity:' "$1" || true)
  [ -n "$line" ] || return 0
  line="${line#*authenticity:}"
  line="${line#"${line%%[![:space:]]*}"}"
  printf '%s' "${line%%[, ]*}"
}

authenticity_stamp() { # definition path, text -> the first marker line becomes "# authenticity: <text>"
  awk -v text="$2" '
    !done && /^[[:space:]]*#[[:space:]]*authenticity:/ {
      match($0, /^[[:space:]]*/); print substr($0, 1, RLENGTH) "# authenticity: " text; done = 1; next
    }
    { print }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# github_verification <tag|commit> <owner/repo> <sha> -> "true valid" or
# "false <reason>" on stdout; exit 1 when the statement could not be read.
# GitHub's verification statement is the signal: it checks the signature
# against the keys the signer registered. DHC_GITHUB_API overrides the API
# base (the tests hand it a file:// tree); a token is used when one is set.
github_verification() {
  local kind="$1" repo="$2" sha="$3" api="${DHC_GITHUB_API:-https://api.github.com}" url body
  local auth=() token="${GITHUB_TOKEN:-${RENOVATE_TOKEN:-}}"
  case "$kind" in
    tag) url="$api/repos/$repo/git/tags/$sha" ;;
    commit) url="$api/repos/$repo/commits/$sha" ;;
    *) return 2 ;;
  esac
  [ -n "$token" ] && auth=(-H "Authorization: Bearer ${token}")
  body=$(curl -fsSL --max-time 60 -H 'Accept: application/vnd.github+json' "${auth[@]}" "$url") || return 1
  # shellcheck disable=SC2016  # a JavaScript template literal, not shell expansion
  printf '%s' "$body" | node -e '
    let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", () => {
      const o = JSON.parse(s);
      const v = (o.verification ?? (o.commit && o.commit.verification)) || {};
      console.log(`${v.verified === true} ${v.reason || "unknown"}`);
    });'
}
