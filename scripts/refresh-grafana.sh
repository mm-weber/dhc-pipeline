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
#   - the url itself                        ← rebuilt with the new build id
#   - GRAFANA_SHA256, both arches           ← fetched for the new version
#   - vars VERSION / SEMVER_VERSION         ← new semver
#   - vars SEMVER_MAJOR_MINOR_VERSION / SEMVER_MAJOR_VERSION
#   - tags (full, major.minor alias, major alias)
#   - display name, spdx version, purl, GRAFANA_VERSION annotation
#
# We pin the PER-BUILD artifact, not the /oss/release/ version alias:
#
#   .../grafana/release/<ver>/grafana_<ver>_<build-id>_linux_<arch>.tar.gz
#
# The alias was observed serving content that differs from the per-build
# artifact of the same release, and on amd64 differing from its own published
# .sha256 — a pin against it verifies or fails depending on when you fetch.
# The build-id path is scoped to a single build, so a re-cut lands at a new URL
# instead of overwriting this one (triage/LOG.md, 2026-07-26).
#
# The build id is not derivable from the version, but it is recoverable: it
# appears in the GitHub release asset names (grafana_<ver>_<id>_linux_amd64.deb),
# and GitHub is already this definition's Renovate datasource. So the version
# stays the single knob Renovate turns, and this task resolves the id.
#
# Network stubs for the test suite and for iterating inside the devcontainer,
# whose firewall blocks both hosts: REFRESH_GRAFANA_BUILD_ID,
# REFRESH_GRAFANA_SHA256_AMD64, REFRESH_GRAFANA_SHA256_ARM64.
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
# Out-of-band security builds (13.0.1+security-01) are served from the same
# templatable path, verified against upstream.
#
# The per-build url — .../grafana/release/<ver>/grafana_<ver>_<buildid>_linux_<arch>.tar.gz,
# carrying an opaque CI run id — is now the shape we pin, so this script has to
# know about it. The build id is not derivable from the version, so it is
# resolved from the GitHub release assets below, and that resolution is
# REQUIRED: it exits non-zero rather than falling back to a version-only url.
url_line=$(grep -E '^[[:space:]]*-?[[:space:]]*url:[[:space:]]*https://dl\.grafana\.com/' "$f" | head -1)
[ -n "$url_line" ] || { echo "refresh-grafana: no dl.grafana.com tarball url in $f" >&2; exit 1; }
# Per-build shape (what we pin) first, then the legacy /oss/release/ alias so a
# definition that has not been migrated yet is still refreshable.
new_ver=$(sed -nE 's#.*/grafana/release/([^/[:space:]]+)/.*#\1#p' <<<"$url_line")
[ -n "$new_ver" ] || new_ver=$(sed -nE 's#.*/oss/release/grafana-([^[:space:]]+)\.linux-.*#\1#p' <<<"$url_line")
[ -n "$new_ver" ] || { echo "refresh-grafana: could not read a version from: ${url_line}" >&2; exit 1; }

# Build id for this version, from two independent indexes.
#
# GitHub release assets alone are not a reliable source: v13.0.3, v12.4.5 and
# v12.3.8 (2026-06-23) each published with ZERO assets, as did v13.0.5, v13.1.2
# (2026-08-04) and v13.1.3 (2026-08-07) — while apt.grafana.com carries a build
# id for v13.0.3 all the same. The reverse also happens: v13.0.6 had its 12
# assets on GitHub hours before the apt index caught up. Neither index is
# complete, and which one is ahead varies per release.
#
# So both are consulted. Where they disagree the refresh stops: two independent
# indexes naming different builds for one version is a supply-chain signal, and
# a checksum pinned against the wrong build verifies against nothing. Resolution
# is REQUIRED either way — it exits non-zero rather than falling back to the
# /oss/release/ alias, whose objects are rewritten after release.
build_id="${REFRESH_GRAFANA_BUILD_ID:-}"
if [ -z "$build_id" ]; then
  # '.' and '+' are ERE metacharacters and grafana ships '+security-NN' builds.
  ver_re=$(printf '%s' "$new_ver" | sed 's/[.+]/\\&/g')

  # apt.grafana.com. The Packages index names the .deb verbatim in `Filename:`,
  # which is the only field carrying the upstream version unmangled — apt
  # rewrites 13.0.1+security-01 to 13.0.1-01 in `Version:`. Anchoring on
  # `/grafana_` keeps grafana-enterprise, which ships the same version from a
  # sibling pool dir, from satisfying the lookup.
  apt_url="${REFRESH_GRAFANA_APT_URL:-https://apt.grafana.com/dists/stable/main/binary-amd64/Packages.gz}"
  apt_id=$(curl -fsSL --max-time 120 "$apt_url" 2>/dev/null | gunzip -c 2>/dev/null \
    | grep -oE '(^|/)grafana_'"$ver_re"'_[0-9]+_linux_amd64\.deb' \
    | head -1 | sed -E 's/.*_([0-9]+)_linux_amd64\.deb$/\1/') || apt_id=""

  gh_url="${REFRESH_GRAFANA_GH_URL:-https://api.github.com/repos/grafana/grafana/releases/tags}"
  auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  gh_id=$(curl -fsSL --max-time 60 "${auth[@]}" "${gh_url}/v${new_ver}" 2>/dev/null \
    | grep -oE '"grafana_'"$ver_re"'_[0-9]+_linux_amd64\.deb"' \
    | head -1 | sed -E 's/.*_([0-9]+)_linux_amd64\.deb"/\1/') || gh_id=""

  if [ -n "$apt_id" ] && [ -n "$gh_id" ] && [ "$apt_id" != "$gh_id" ]; then
    echo "refresh-grafana: build id conflict for v${new_ver} — apt.grafana.com says ${apt_id}, the GitHub release assets say ${gh_id}. Refusing to pick one." >&2
    exit 1
  fi
  build_id="${apt_id:-$gh_id}"
fi
[ -n "$build_id" ] || { echo "refresh-grafana: could not resolve a build id for v${new_ver} from apt.grafana.com or the GitHub release assets. Upstream has published neither; the release is not consumable through the per-build url yet." >&2; exit 1; }

new_maj="${new_ver%%.*}"
new_rest="${new_ver#*.}"
new_majmin="${new_maj}.${new_rest%%.*}"

# Old version still present in the file at task time.
old_ver=$(awk -F': *' '/^[[:space:]]*SEMVER_VERSION:/{print $2; exit}' "$f" | tr -d '"[:space:]')
[ -n "$old_ver" ] || { echo "refresh-grafana: no SEMVER_VERSION in $f" >&2; exit 1; }
old_maj="${old_ver%%.*}"
old_rest="${old_ver#*.}"
old_majmin="${old_maj}.${old_rest%%.*}"

# dl.grafana.com is where the artifact and its sidecar come from, and it is the
# authority on whether a build exists at all. The indexes that resolve a build
# id — apt, GitHub releases — are populated by different pipelines than the
# object store, so an id can name a build dl.grafana.com does not serve.
# Overridable for the tests; the url written into the definition is always the
# real host.
dl_base="${REFRESH_GRAFANA_DL_BASE:-https://dl.grafana.com}"

tarball_url() { # arch -> fetch url on stdout
  printf '%s/grafana/release/%s/grafana_%s_%s_linux_%s.tar.gz' \
    "$dl_base" "$new_ver" "$new_ver" "$build_id" "$1"
}

# Per-arch tarball checksum for the new version. Both arches are resolved before
# anything is written, so a miss on either leaves the definition untouched.
fetch_sha() { # arch -> 64-hex on stdout
  local arch="$1" base sha
  base="$(tarball_url "$arch")"
  # Confirm the build is actually served before trusting the id that named it.
  # A single-byte ranged GET rather than HEAD: it is as cheap and it exercises
  # the same path the build will take. Failing here names the host, where the
  # alternative is a 350MB download that 404s and surfaces as a checksum
  # complaint about an artifact that was never there.
  curl -fsSL -o /dev/null --max-time 60 -r 0-0 "$base" 2>/dev/null || {
    echo "refresh-grafana: dl.grafana.com does not serve ${base} — build id ${build_id} resolved for v${new_ver}, but no ${arch} artifact is published under it. Nothing written." >&2
    return 1
  }
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

# 0) the url. Renovate only changed the version in the path segment; the build
#    id in the filename still belongs to the old release, so rebuild the whole
#    line. Also migrates a definition still on the /oss/release/ alias.
new_url="https://dl.grafana.com/grafana/release/${new_ver}/grafana_${new_ver}_${build_id}_linux_\${target.arch}.tar.gz"
sed -i -E "s@^([[:space:]]*-?[[:space:]]*url:[[:space:]]*)https://dl\.grafana\.com/[^[:space:]]*@\1${new_url}@" "$f"

ov=$(esc "$old_ver")
omm=$(esc "$old_majmin"); omaj=$(esc "$old_maj")

# 1) full semver wherever it literally appears (VERSION, SEMVER_VERSION, full
#    tag, spdx version, purl, annotation, checksum-provenance comment).
#    The tarball url is EXCLUDED: it was rebuilt whole in step 0, and a blind
#    substitution would corrupt it anyway when the old version is a prefix of
#    the new one (13.0.4 inside 13.0.4+security-01 doubles the suffix).
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
