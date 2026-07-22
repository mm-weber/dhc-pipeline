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
#
# The commit sha is resolved from the tag via `git ls-remote`; set
# REFRESH_SHA_OVERRIDE to stub that (used by the test suite).
set -euo pipefail

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

# New commit sha the tag resolves to (peeled for annotated tags, else the tag).
if [ -n "${REFRESH_SHA_OVERRIDE:-}" ]; then
  new_sha="$REFRESH_SHA_OVERRIDE"
else
  new_sha=$(git ls-remote "$repo_url" "refs/tags/${new_tag}^{}" | awk '{print $1; exit}')
  [ -n "$new_sha" ] || new_sha=$(git ls-remote "$repo_url" "refs/tags/${new_tag}" | awk '{print $1; exit}')
fi
[ -n "$new_sha" ] || { echo "refresh: could not resolve sha for ${new_tag} at ${repo_url}" >&2; exit 1; }

ov=$(esc "$old_ver"); osha=$(esc "$old_sha")
omm=$(esc "$old_majmin"); omaj=$(esc "$old_maj")

# 1) full semver + sha wherever they literally appear (VERSION, SEMVER_VERSION,
#    full tag, ldflags version+commit, checksum, COMMIT_SHA).
sed -i -E \
  -e "s/${osha}/${new_sha}/g" \
  -e "s/${ov}/${new_ver}/g" \
  "$f"

# 2) truncated fields the full-semver pass can't reach: major.minor + major
#    vars, and their alias tags. Anchored so a patch bump is a no-op.
sed -i -E \
  -e "s/^([[:space:]]*SEMVER_MAJOR_MINOR_VERSION:[[:space:]]*).*/\1\"${new_majmin}\"/" \
  -e "s/^([[:space:]]*SEMVER_MAJOR_VERSION:[[:space:]]*).*/\1\"${new_maj}\"/" \
  -e "s/- ${omm}-alpine3\.23/- ${new_majmin}-alpine3.23/" \
  -e "s/- ${omaj}-alpine3\.23/- ${new_maj}-alpine3.23/" \
  "$f"

echo "refresh: $dir -> ${new_ver} (${new_sha})"
