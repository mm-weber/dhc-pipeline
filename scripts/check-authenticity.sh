#!/usr/bin/env bash
# check-authenticity.sh <root> <out.jsonl>
#
# Checkpoint 3 (task 11.3; Req 3.10): every ACTIVE definition's declared
# authenticity signal, re-verified against its upstream origin once a day
# (task 14.2 scoped it to catalogue-policy.yaml's active set: an inactive
# definition is outside the tracking scope, so a tag that moves under it is
# nobody's signal; the count of definitions skipped for that reason is in the
# summary line):
#
#   signed-tag       the pinned tag still points at the pinned commit, is an
#                    annotated tag, and GitHub's verification statement for
#                    the tag object says verified
#   signed-commit    the pinned tag still points at the pinned commit, and
#                    GitHub's verification statement for that commit says
#                    verified
#   cross-origin-    per architecture, the pinned sha256, the download origin's
#   checksum         sidecar and the publisher's version statement agree
#
# A tag that moved, a signature that no longer verifies, an origin that
# stopped agreeing: each is a mismatch, reported by name as a failure of the
# run (exit 1), and the record written to <out.jsonl> is what the workflow
# files a supply-chain issue from. There is no grandfather state: every
# definition is asserted from day one (independent review 1.1).
#
# Req 4.9 rides along: a compat decision (chart/<name>/chart.yaml, `compat:`
# with `review_by`) whose review-by date has passed is reported here daily,
# as a warning; the validate gate is what fails it (Req 4.8, task 11.4).
#
# Seams for the tests: DHC_GITHUB_API (a file:// tree), DHC_VERSIONS_API, a
# `git` on PATH answering ls-remote, DHC_TODAY.
set -uo pipefail

# shellcheck source=scripts/definition-lib.sh
. "$(cd "$(dirname "$0")" && pwd)/definition-lib.sh"

ROOT="${1:?usage: check-authenticity.sh <root> <out.jsonl>}"
OUT="${2:?usage: check-authenticity.sh <root> <out.jsonl>}"
today="${DHC_TODAY:-$(date -u +%F)}"
: > "$OUT"
failures=0; verified=0; lapsed=0; inactive=0
active=$(active_definitions "$ROOT") || exit $? # the reader's refusal, with its own message

record() { # definition class ref ok detail
  jq -cn --arg d "$1" --arg class "$2" --arg ref "$3" --argjson ok "$4" --arg detail "$5" \
    '{definition:$d, class:$class, ref:$ref, ok:$ok, detail:$detail}' >> "$OUT"
}
fail() { # definition class ref detail
  echo "::error::check-authenticity: ${1} (${2}, ${3}): ${4} (Req 3.10)"
  record "$1" "$2" "$3" false "$4"
  failures=$((failures + 1))
}
pass() { # definition class ref detail
  echo "check-authenticity: ${1} (${2}, ${3}): ${4}"
  record "$1" "$2" "$3" true "$4"
  verified=$((verified + 1))
}

for f in "$ROOT"/image/*/image.yaml; do
  [ -f "$f" ] || continue
  name=$(basename "$(dirname "$f")")
  if ! printf '%s\n' "$active" | grep -qxF -- "$name"; then inactive=$((inactive + 1)); continue; fi
  class=$(authenticity_class "$f")
  case "$class" in
    signed-tag|signed-commit)
      ref_line=$(grep -oE 'git\+https://[^#"]+#v?[0-9][^ "'"'"']*' "$f" | head -1 || true)
      if [ -z "$ref_line" ]; then fail "$name" "$class" "?" "no git+ source ref to verify"; continue; fi
      repo_url="${ref_line%#*}"; repo_url="${repo_url#git+}"; tag="${ref_line#*#}"
      owner_repo=$(printf '%s' "$repo_url" | sed -E 's#^https://github\.com/##; s#\.git$##')
      pinned=$(awk -F': *' '/^[[:space:]]*checksum:/{print $2; exit}' "$f" | tr -d '"[:space:]')
      peeled=$(git ls-remote "$repo_url" "refs/tags/${tag}^{}" 2>/dev/null | awk '{print $1; exit}' || true)
      unpeeled=$(git ls-remote "$repo_url" "refs/tags/${tag}" 2>/dev/null | awk '{print $1; exit}' || true)
      commit="${peeled:-$unpeeled}"
      if [ -z "$commit" ]; then fail "$name" "$class" "$tag" "tag ${tag} no longer exists at ${repo_url}"; continue; fi
      if [ "$commit" != "$pinned" ]; then fail "$name" "$class" "$tag" "tag ${tag} now points at ${commit:0:12}, the definition pins ${pinned:0:12}: the tag moved"; continue; fi
      if [ "$class" = signed-tag ]; then
        if [ -z "$peeled" ] || [ "$unpeeled" = "$peeled" ]; then fail "$name" "$class" "$tag" "declared signed-tag, but ${tag} is a lightweight tag with no tag object to verify"; continue; fi
        if ! v=$(github_verification tag "$owner_repo" "$unpeeled"); then fail "$name" "$class" "$tag" "GitHub's verification statement for tag ${tag} (${unpeeled:0:12}) could not be read"; continue; fi
        if [ "${v%% *}" != "true" ]; then fail "$name" "$class" "$tag" "GitHub reports tag ${tag} as not verified (${v#* })"; continue; fi
        pass "$name" "$class" "$tag" "tag object ${unpeeled:0:12} on commit ${pinned:0:12}, GitHub verification: ${v#* }"
      else
        if ! v=$(github_verification commit "$owner_repo" "$pinned"); then fail "$name" "$class" "$tag" "GitHub's verification statement for commit ${pinned:0:12} could not be read"; continue; fi
        if [ "${v%% *}" != "true" ]; then fail "$name" "$class" "$tag" "GitHub reports commit ${pinned:0:12} (${tag}) as not verified (${v#* })"; continue; fi
        pass "$name" "$class" "$tag" "commit ${pinned:0:12}, GitHub verification: ${v#* }"
      fi ;;
    cross-origin-checksum)
      # shellcheck disable=SC2016  # ${target.arch} is the frontend's token
      url_tmpl=$(sed -nE 's#^[[:space:]]*-?[[:space:]]*url:[[:space:]]*([a-zA-Z][a-zA-Z0-9+.-]*://[^[:space:]"'"'"']+).*#\1#p' "$f" | grep -F '${target.arch}' | head -1 || true)
      pins=$(sed -nE 's/.*target\.arch[[:space:]]*==[[:space:]]*"amd64"[[:space:]]*\?[[:space:]]*"([0-9a-f]{64})"[[:space:]]*:[[:space:]]*"([0-9a-f]{64})".*/\1 \2/p' "$f" | head -1 || true)
      version=$(awk -F': *' '/^[[:space:]]*SEMVER_VERSION:/{print $2; exit}' "$f" | tr -d '"[:space:]')
      if [ -z "$url_tmpl" ] || [ -z "$pins" ] || [ -z "$version" ]; then fail "$name" "$class" "${version:-?}" "no per-architecture pinned tarball to cross-check"; continue; fi
      host=$(printf '%s' "$url_tmpl" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://([^/]*)/.*#\1#')
      stmt_url=$(version_statement_url "$host" "$version")
      if [ -z "$stmt_url" ]; then fail "$name" "$class" "$version" "no version statement origin is known for ${host}"; continue; fi
      if ! statement=$(curl -fsSL --max-time 60 "$stmt_url"); then fail "$name" "$class" "$version" "could not read the version statement at ${stmt_url}"; continue; fi
      ok=true; detail=""
      for arch in amd64 arm64; do
        if [ "$arch" = amd64 ]; then pinned="${pins%% *}"; else pinned="${pins##* }"; fi
        url="${url_tmpl//\$\{target.arch\}/$arch}"
        sidecar=$(curl -fsSL --max-time 60 "${url}.sha256" 2>/dev/null | tr -d '[:space:]' | cut -c1-64 || true)
        stated=$(versions_api_sha "$statement" "$arch")
        if msg=$(shas_agree "${arch}" "pinned=${pinned}" "${host:-origin} sidecar=${sidecar}" "version statement=${stated}"); then
          detail="${detail:+${detail}; }${arch} ${pinned:0:12}… agreed by the ${host:-origin} sidecar and the version statement"
        else
          ok=false; detail="${detail:+${detail}; }${msg}"
        fi
      done
      if [ "$ok" = true ]; then pass "$name" "$class" "$version" "$detail"; else fail "$name" "$class" "$version" "$detail"; fi ;;
    *)
      fail "$name" "${class:-none}" "?" "no verifiable authenticity class declared" ;;
  esac
done

# Req 4.9: lapsed compat review-by dates, reported, not failed here.
for c in "$ROOT"/chart/*/chart.yaml; do
  [ -f "$c" ] || continue
  chart=$(basename "$(dirname "$c")")
  review_by=$(python3 -c '
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1])) or {}
compat = doc.get("compat") or {}
v = compat.get("review_by") if isinstance(compat, dict) else None
print(v if v else "")' "$c")
  [ -n "$review_by" ] || continue
  if [[ "$review_by" < "$today" ]]; then
    echo "::warning::check-authenticity: chart ${chart}: the compat decision's review-by date ${review_by} has passed (today ${today}); a dated re-decision is due (Req 4.9)"
    record "chart/${chart}" "compat" "$review_by" false "review-by date ${review_by} has passed"
    lapsed=$((lapsed + 1))
  else
    record "chart/${chart}" "compat" "$review_by" true "review-by date ${review_by} ahead"
  fi
done

echo "check-authenticity: ${verified} signal(s) verified, ${failures} mismatch(es), ${lapsed} lapsed compat review-by date(s), ${inactive} inactive definition(s) not re-verified"
[ "$failures" -eq 0 ] || exit 1
