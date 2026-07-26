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

# Escape ERE metachars. '+' is in the set because grafana ships out-of-band
# fixes as semver build metadata (13.0.1+security-01) — unescaped it is a
# quantifier and the substitution silently matches nothing.
esc() { printf '%s' "$1" | sed 's/[.[\*^$/+]/\\&/g'; }

# '+' is illegal in an OCI reference (docker: "invalid reference format"), so
# the full release tag carries the build separator as '_', the way
# eclipse-temurin does. Every other field keeps the upstream version verbatim.
tagver() { printf '%s' "${1//+/_}"; }

# New version from the (already bumped) tarball url. Anchored on the `url:` key
# so the checksum-provenance comment, which names the same host, cannot match.
# Upstream publishes two url shapes and only one of them is templatable:
#   regular   .../oss/release/grafana-<ver>.linux-<arch>.tar.gz
#   security  .../grafana/release/<ver>/grafana_<ver>_<buildid>_linux_<arch>.tar.gz
# Both are read here so a definition sitting on a hand-pinned security build is
# still refreshable when the next regular release supersedes it.
url_line=$(grep -E '^[[:space:]]*-?[[:space:]]*url:[[:space:]]*https://dl\.grafana\.com/' "$f" | head -1)
[ -n "$url_line" ] || { echo "refresh-grafana: no dl.grafana.com tarball url in $f" >&2; exit 1; }
new_ver=$(sed -nE 's#.*/oss/release/grafana-([^[:space:]]+)\.linux-.*#\1#p' <<<"$url_line")
[ -n "$new_ver" ] || new_ver=$(sed -nE 's#.*/grafana/release/([^/[:space:]]+)/.*#\1#p' <<<"$url_line")
[ -n "$new_ver" ] || { echo "refresh-grafana: could not read a version from: ${url_line}" >&2; exit 1; }

# An out-of-band security build cannot be refreshed automatically. Upstream
# publishes it under a different path AND embeds an opaque CI run id in the
# filename that is not derivable from the version, so neither the download url
# nor its checksum can be constructed here. Fail with the shape a human needs.
case "$new_ver" in
  *+*)
    cat >&2 <<MSG
refresh-grafana: ${new_ver} is an out-of-band security build — no automatic refresh.

Upstream does not publish these under the templatable /oss/release/ path. They
live at, e.g.:

  https://dl.grafana.com/grafana/release/13.0.1+security-01/grafana_13.0.1+security-01_25720641773_linux_amd64.tar.gz
                                                                                       ^^^^^^^^^^^
an opaque build id that cannot be derived from the version.

Fix forward by hand (Req 6.5) in ${dir}/image.yaml:
  - url:            the full per-arch url including the build id
  - GRAFANA_SHA256: both arch checksums, from upstream's download page
  - tags:           full tag with '+' written as '_' (${new_ver//+/_}-alpine3.23)
  - vars:           VERSION / SEMVER_VERSION = ${new_ver}
MSG
    exit 1 ;;
esac

# Canonicalise the url onto the templatable shape. Normally a no-op; it matters
# when superseding a hand-pinned security build, whose build-id url must not
# survive into a regular release.
sed -i -E "s@^([[:space:]]*-?[[:space:]]*url:[[:space:]]*)https://dl\.grafana\.com/[^[:space:]]*@\1https://dl.grafana.com/oss/release/grafana-${new_ver}.linux-\${target.arch}.tar.gz@" "$f"

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
#    The tarball url is EXCLUDED: Renovate already wrote the new version there,
#    and when the old version is a prefix of the new one — 13.0.4 inside
#    13.0.4+security-01 — substituting again doubles the suffix.
sed -i -E "\@url:[[:space:]]*https://dl\.grafana\.com@! s/${ov}/${new_ver}/g" "$f"

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

# 3) the full release tag. It differs from the version by the build separator
#    ('+' in the version, '_' in the tag) so no single substitution reaches it
#    in both directions — 13.0.4 -> 13.0.4+security-01 and back. Rewritten from
#    the known new version instead: inside the top-level tags: block, any entry
#    that is not one of the two alias tags IS the full tag.
full_tag="$(tagver "$new_ver")-alpine3.23"
awk -v maj="${new_maj}-alpine3.23" -v mm="${new_majmin}-alpine3.23" -v full="$full_tag" '
  /^tags:/ { intags = 1; print; next }
  intags && /^[^[:space:]]/ { intags = 0 }
  intags && match($0, /^[[:space:]]*-[[:space:]]*/) {
    pre = substr($0, RSTART, RLENGTH); val = substr($0, RSTART + RLENGTH)
    sub(/[[:space:]]+$/, "", val)
    if (val != maj && val != mm) { $0 = pre full }
  }
  { print }
' "$f" > "$f.tmp" && mv "$f.tmp" "$f"

# 4) re-pin both arch checksums. Rebuilt whole rather than substituted, so the
#    expression shape stays exactly as authored.
sed -i -E \
  "s|^([[:space:]]*GRAFANA_SHA256:[[:space:]]*).*|\1'#{ target.arch == \"amd64\" ? \"${amd64_sha}\" : \"${arm64_sha}\" }'|" \
  "$f"

echo "refresh-grafana: $dir -> ${new_ver} (amd64 ${amd64_sha:0:12}…, arm64 ${arm64_sha:0:12}…)"
