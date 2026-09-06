#!/usr/bin/env bash
# refresh-definition.sh <definition-dir> — Renovate postUpgradeTask (Req 3.2).
#
# Renovate bumps only the upstream source ref (`url: git+https://…#vX.Y.Z`) in a
# definition. Every other version-derived field is then stale. This recomputes
# them from the new ref so the bumped definition is internally coherent:
#   - checksum + COMMIT_SHA + ldflags AppGitCommit  ← commit the new tag points at
#   - vars VERSION / SEMVER_VERSION                  ← new semver
#   - vars SEMVER_MAJOR_MINOR_VERSION / SEMVER_MAJOR_VERSION
#   - tags (full, major.minor alias, major alias)
#   - ldflags version stamp (AppVersion=vX.Y.Z or main.version=X.Y.Z)
#   - display name (`name: … <major.minor>.x`)
#
# The commit sha is resolved from the tag via `git ls-remote`; set
# REFRESH_SHA_OVERRIDE to stub that (used by the test suite), and
# REFRESH_TAG_SHA_OVERRIDE for the annotated tag object's sha (unset: the tag
# is lightweight).
#
# Req 3.8 (task 11.2): before any field is written, the definition's declared
# authenticity signal is verified against GitHub's verification statement:
# signed-tag needs an annotated tag whose tag object GitHub verifies,
# signed-commit needs the commit the tag points at verified. A signal that
# fails, or a class that does not fit, refuses by name and writes nothing.
# What was verified, and when, is written beside the pin
# ("# authenticity: signed-tag, verified v1.21.2 (GitHub verification:
# valid), 2026-09-06"): the diff carries the evidence, since a
# postUpgradeTask's stdout never reaches a PR (review F2 b). DHC_GITHUB_API
# and REFRESH_TODAY are the test seams.
set -euo pipefail

# shellcheck source=scripts/definition-lib.sh
. "$(cd "$(dirname "$0")" && pwd)/definition-lib.sh"

dir="${1:?usage: refresh-definition.sh <definition-dir>}"
f="$dir/image.yaml"
[ -f "$f" ] || { echo "refresh: no image.yaml in $dir" >&2; exit 1; }

esc() { printf '%s' "$1" | sed 's/[.[\*^$/]/\\&/g'; }   # escape regex metachars

# New ref/version from the (already bumped) source url line.
ref_line=$(grep -oE 'git\+https://[^#"]+#v?[0-9][^ "'\'']*' "$f" | head -1)
[ -n "$ref_line" ] || { echo "refresh: no git+ source ref in $f" >&2; exit 1; }
repo_url="${ref_line%#*}"; repo_url="${repo_url#git+}"
new_tag="${ref_line#*#}"          # vX.Y.Z or X.Y.Z (valkey has no leading v)
new_ver="${new_tag#v}"            # X.Y.Z
new_maj="${new_ver%%.*}"
new_rest="${new_ver#*.}"
new_majmin="${new_maj}.${new_rest%%.*}"

# Old version/sha still present in the file at task time.
old_ver=$(awk -F': *' '/^[[:space:]]*SEMVER_VERSION:/{print $2; exit}' "$f" | tr -d '"[:space:]')
old_sha=$(awk -F': *' '/^[[:space:]]*COMMIT_SHA:/{print $2; exit}' "$f" | tr -d '"[:space:]')
old_maj="${old_ver%%.*}"
old_rest="${old_ver#*.}"
old_majmin="${old_maj}.${old_rest%%.*}"

# New commit sha the tag resolves to (peeled for annotated tags, else the tag),
# and the tag object's own sha when the tag is annotated.
tag_obj=""
if [ -n "${REFRESH_SHA_OVERRIDE:-}" ]; then
  new_sha="$REFRESH_SHA_OVERRIDE"
  tag_obj="${REFRESH_TAG_SHA_OVERRIDE:-}"
else
  new_sha=$(git ls-remote "$repo_url" "refs/tags/${new_tag}^{}" | awk '{print $1; exit}')
  if [ -n "$new_sha" ]; then
    tag_obj=$(git ls-remote "$repo_url" "refs/tags/${new_tag}" | awk '{print $1; exit}')
  else
    new_sha=$(git ls-remote "$repo_url" "refs/tags/${new_tag}" | awk '{print $1; exit}')
  fi
fi
[ -n "$new_sha" ] || { echo "refresh: could not resolve sha for ${new_tag} at ${repo_url}" >&2; exit 1; }

# Req 3.8: the declared signal, verified before anything is written.
refuse() { echo "refresh: refusing to write ${f}: $1 (Req 3.8)" >&2; exit 1; }
owner_repo=$(printf '%s' "$repo_url" | sed -E 's#^https://github\.com/##; s#\.git$##')
today="${REFRESH_TODAY:-$(date -u +%F)}"
class=$(authenticity_class "$f")
case "$class" in
  signed-tag)
    [ -n "$tag_obj" ] || refuse "authenticity signed-tag declared, but ${new_tag} is a lightweight tag with no tag object to verify"
    v=$(github_verification tag "$owner_repo" "$tag_obj") || refuse "authenticity signed-tag declared, but GitHub's verification statement for tag ${new_tag} (${tag_obj:0:12}) could not be read"
    [ "${v%% *}" = "true" ] || refuse "authenticity signed-tag declared, but GitHub reports tag ${new_tag} as not verified (${v#* })"
    stamp="signed-tag, verified ${new_tag} (GitHub verification: ${v#* }), ${today}" ;;
  signed-commit)
    v=$(github_verification commit "$owner_repo" "$new_sha") || refuse "authenticity signed-commit declared, but GitHub's verification statement for commit ${new_sha:0:12} (${new_tag}) could not be read"
    [ "${v%% *}" = "true" ] || refuse "authenticity signed-commit declared, but GitHub reports commit ${new_sha:0:12} (${new_tag}) as not verified (${v#* })"
    stamp="signed-commit, verified ${new_tag} at ${new_sha:0:12} (GitHub verification: ${v#* }), ${today}" ;;
  cross-origin-checksum)
    refuse "authenticity cross-origin-checksum declared on a git source; that class belongs to a repackaged tarball" ;;
  none|"")
    refuse "no authenticity signal declared (a '# authenticity: signed-tag|signed-commit' marker beside the source url, Req 1.10)" ;;
  *)
    refuse "unknown authenticity class '${class}'" ;;
esac

ov=$(esc "$old_ver"); osha=$(esc "$old_sha")
omm=$(esc "$old_majmin"); omaj=$(esc "$old_maj")

# 1) full semver + sha wherever they literally appear (VERSION, SEMVER_VERSION,
#    full tag, ldflags version+commit, checksum, COMMIT_SHA).
sed -i -E \
  -e "s/${osha}/${new_sha}/g" \
  -e "s/${ov}/${new_ver}/g" \
  "$f"

# 2) truncated fields the full-semver pass can't reach: major.minor + major
#    vars, their alias tags, and the display name. Vars and tags are anchored
#    so a patch bump is a no-op; the name rule matches the version SHAPE
#    (<digits>.<digits>.x at end of line), so it also heals a name that had
#    already drifted before the bump.
sed -i -E \
  -e "s/^([[:space:]]*SEMVER_MAJOR_MINOR_VERSION:[[:space:]]*).*/\1\"${new_majmin}\"/" \
  -e "s/^([[:space:]]*SEMVER_MAJOR_VERSION:[[:space:]]*).*/\1\"${new_maj}\"/" \
  -e "s/- ${omm}-alpine3\.23/- ${new_majmin}-alpine3.23/" \
  -e "s/- ${omaj}-alpine3\.23/- ${new_maj}-alpine3.23/" \
  -e "s/^(name:[[:space:]]+.*[[:space:]])[0-9]+\.[0-9]+\.x[[:space:]]*$/\1${new_majmin}.x/" \
  "$f"

# 3) the evidence beside the pin (Req 3.8).
authenticity_stamp "$f" "$stamp"

echo "refresh: $dir -> ${new_ver} (${new_sha}); ${stamp}"
