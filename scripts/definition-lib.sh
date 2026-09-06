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

# --- the cross-origin checksum, shared by three checkpoints (Req 3.8 to 3.10) --
# A repackaged tarball's checksum is stated by two origins that do not share a
# pipeline: the object store's sidecar (dl.grafana.com) and the publisher's
# version statement (grafana.com's versions API). refresh-grafana.sh compares
# them before a bump is written (checkpoint 1), verify-arch-pins.sh at PR time
# with the served bytes as a third value (checkpoint 2), check-authenticity.sh
# daily (checkpoint 3). One comparison, one reader of the statement.

# version_statement_url <download host> <version> -> the publisher's version
# statement for that release; empty when no origin is known for the host.
# DHC_VERSIONS_API overrides the base for any host (the tests serve file:// trees).
version_statement_url() {
  case "$1" in
    dl.grafana.com) printf '%s/%s' "${DHC_VERSIONS_API:-https://grafana.com/api/grafana/versions}" "$2" ;;
    *) [ -n "${DHC_VERSIONS_API:-}" ] && printf '%s/%s' "$DHC_VERSIONS_API" "$2" ;;
  esac
  return 0
}

# versions_api_sha <statement json> <arch> -> the sha256 the statement gives
# for the linux <arch> tarball, or empty. Read with node, the one runtime the
# Renovate container, the runners and the devcontainer all have.
versions_api_sha() {
  # shellcheck disable=SC2016  # a JavaScript template, not shell expansion
  printf '%s' "$1" | node -e '
    let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", () => {
      let o; try { o = JSON.parse(s); } catch { return; }
      const suffix = "_linux_" + process.argv[1] + ".tar.gz";
      for (const p of o.packages || []) {
        if (typeof p.url === "string" && p.url.endsWith(suffix)) { process.stdout.write(String(p.sha256 || "")); return; }
      }
    });' "$2" 2>/dev/null || true
}

# shas_agree <what> <label>=<sha>... -> 0 when every value is the same 64-hex
# digest; otherwise prints one line naming every value and returns 1. Both
# numbers, always: a mismatch without them is the message that once sent this
# repository looking in the wrong place for a week.
shas_agree() {
  local what="$1"; shift
  local first="" bad=false line="" kv label val
  for kv in "$@"; do
    label="${kv%%=*}"; val="${kv#*=}"
    [ -n "$line" ] && line="${line}, "
    if [ "${#val}" -ne 64 ] || [ -n "${val//[0-9a-f]/}" ]; then
      bad=true; line="${line}${label} ${val:-none}"; continue
    fi
    line="${line}${label} ${val:0:12}…"
    if [ -z "$first" ]; then first="$val"; elif [ "$val" != "$first" ]; then bad=true; fi
  done
  if [ "$bad" = true ]; then printf '%s: %s do not agree\n' "$what" "$line"; return 1; fi
  return 0
}
