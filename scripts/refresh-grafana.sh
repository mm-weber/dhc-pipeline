#!/usr/bin/env bash
# refresh-grafana.sh <definition-dir> — Renovate postUpgradeTask for the
# tarball-repackage archetype (ADR 0002).
#
# Sibling of refresh-definition.sh, which serves the compile-from-source
# archetype. The split is the archetype: a from-source definition is re-pinned
# by resolving a git tag to a commit sha, a repackage definition by re-pinning
# the checksum of a prebuilt release artifact. Grafana has no git source ref at
# all, so the two cannot share an implementation.
#
# Renovate bumps only the version inside the tarball url. Every other
# version-derived field is then stale; this recomputes them so the bumped
# definition is internally coherent:
#   - GRAFANA_SHA256, both arches           ← fetched for the new version
#   - vars VERSION / SEMVER_VERSION         ← new semver
#   - vars SEMVER_MAJOR_MINOR_VERSION / SEMVER_MAJOR_VERSION
#   - tags (full, major.minor alias, major alias)
#   - display name, spdx version, purl, GRAFANA_VERSION annotation
#
# Checksums come from dl.grafana.com; set REFRESH_GRAFANA_SHA256_AMD64 and
# REFRESH_GRAFANA_SHA256_ARM64 to stub that (used by the test suite, and by
# anyone iterating inside the devcontainer, whose firewall blocks that host).
set -euo pipefail

dir="${1:?usage: refresh-grafana.sh <definition-dir>}"
f="$dir/image.yaml"
[ -f "$f" ] || { echo "refresh-grafana: no image.yaml in $dir" >&2; exit 1; }

esc() { printf '%s' "$1" | sed 's/[.[\*^$/]/\\&/g'; }   # escape regex metachars

# New version from the (already bumped) tarball url. Anchored on the `url:` key
# so the checksum-provenance comment, which names the same host, cannot match.
new_ver=$(grep -oE '^[[:space:]]*-?[[:space:]]*url:[[:space:]]*https://dl\.grafana\.com/oss/release/grafana-[0-9][^[:space:]]*\.linux-' "$f" \
  | head -1 | sed -E 's#.*grafana-##; s#\.linux-$##')
[ -n "$new_ver" ] || { echo "refresh-grafana: no dl.grafana.com tarball url in $f" >&2; exit 1; }

new_maj="${new_ver%%.*}"
new_rest="${new_ver#*.}"
new_majmin="${new_maj}.${new_rest%%.*}"

# Old version still present in the file at task time.
old_ver=$(awk -F': *' '/^[[:space:]]*SEMVER_VERSION:/{print $2; exit}' "$f" | tr -d '"[:space:]')
[ -n "$old_ver" ] || { echo "refresh-grafana: no SEMVER_VERSION in $f" >&2; exit 1; }
old_maj="${old_ver%%.*}"
old_rest="${old_ver#*.}"
old_majmin="${old_maj}.${old_rest%%.*}"

# Per-arch tarball checksum for the new version.
fetch_sha() { # arch -> 64-hex on stdout
  local arch="$1" base sha
  base="https://dl.grafana.com/oss/release/grafana-${new_ver}.linux-${arch}.tar.gz"
  # Fast path: upstream publishes a .sha256 sidecar beside each tarball — that
  # is where the current pins came from. Fall back to hashing the tarball
  # itself if a release ever ships without one.
  sha=$(curl -fsSL --max-time 60 "${base}.sha256" 2>/dev/null | tr -d '[:space:]' | cut -c1-64) || sha=""
  if [ "${#sha}" -ne 64 ]; then
    sha=$(curl -fsSL --max-time 900 "$base" | sha256sum | cut -d' ' -f1)
  fi
  if [ "${#sha}" -ne 64 ] || [ -n "${sha//[0-9a-f]/}" ]; then
    echo "refresh-grafana: bad checksum for ${arch} at ${base}: '${sha}'" >&2
    return 1
  fi
  printf '%s' "$sha"
}

amd64_sha="${REFRESH_GRAFANA_SHA256_AMD64:-}"
[ -n "$amd64_sha" ] || amd64_sha=$(fetch_sha amd64)
arm64_sha="${REFRESH_GRAFANA_SHA256_ARM64:-}"
[ -n "$arm64_sha" ] || arm64_sha=$(fetch_sha arm64)

ov=$(esc "$old_ver")
omm=$(esc "$old_majmin"); omaj=$(esc "$old_maj")

# 1) full semver wherever it literally appears (VERSION, SEMVER_VERSION, full
#    tag, spdx version, purl, annotation, checksum-provenance comment).
sed -i -E "s/${ov}/${new_ver}/g" "$f"

# 2) truncated fields the full-semver pass cannot reach: major.minor + major
#    vars, their alias tags, and the display name. Anchored so a patch bump is
#    a no-op.
sed -i -E \
  -e "s/^([[:space:]]*SEMVER_MAJOR_MINOR_VERSION:[[:space:]]*).*/\1\"${new_majmin}\"/" \
  -e "s/^([[:space:]]*SEMVER_MAJOR_VERSION:[[:space:]]*).*/\1\"${new_maj}\"/" \
  -e "s/- ${omm}-alpine3\.23/- ${new_majmin}-alpine3.23/" \
  -e "s/- ${omaj}-alpine3\.23/- ${new_maj}-alpine3.23/" \
  -e "s/^(name:[[:space:]]*Grafana[[:space:]]+)${omm}\.x/\1${new_majmin}.x/" \
  "$f"

# 3) re-pin both arch checksums. Rebuilt whole rather than substituted, so the
#    expression shape stays exactly as authored.
sed -i -E \
  "s|^([[:space:]]*GRAFANA_SHA256:[[:space:]]*).*|\1'#{ target.arch == \"amd64\" ? \"${amd64_sha}\" : \"${arm64_sha}\" }'|" \
  "$f"

echo "refresh-grafana: $dir -> ${new_ver} (amd64 ${amd64_sha:0:12}…, arm64 ${arm64_sha:0:12}…)"
