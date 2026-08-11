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

  # Keyed references: image:/base: always need a digest; uses: only when it
  # names a registry image (first path segment contains a dot). Bare actions
  # like go/build@v1 resolve inside the pinned frontend — nothing to fetch,
  # nothing to pin (see docs/concepts.md).
  while IFS=$'\t' read -r key line_no top ref; do
    # strip surrounding quotes and trailing comments
    ref="${ref%%[[:space:]]#*}"
    ref="${ref%\"}"; ref="${ref#\"}"
    ref="${ref%\'}"; ref="${ref#\'}"
    [ -z "$ref" ] && continue
    # Helm-template refs (chart templates) render to a digest at deploy time and
    # are gated by kyverno over the rendered manifests — the literal pin lives in
    # the chart's values, not here.
    [[ "$ref" == *'{{'* ]] && continue
    # In a definition, top-level image: is the PUBLISH name (what we build):
    # a bare repository reference — its digest cannot exist before the build,
    # and release tags live under tags:.
    if [ "$key" = "image" ] && [ "$top" = "1" ] && [[ "$file" == "$ROOT"/image/*/image.yaml ]]; then
      if [[ "$ref" == *:* ]]; then
        echo "::error file=${rel},line=${line_no}::pinning convention (docs/CONVENTIONS.md): definition 'image:' is the publish name — bare reference only, got '${ref}' (tags live under 'tags:')"
        violations=$((violations + 1))
      fi
      continue
    fi
    if [ "$key" = "uses" ]; then
      [[ "$ref" != */* ]] && continue
      first="${ref%%/*}"
      [[ "$first" != *.* ]] && continue
    fi
    if [[ "$ref" != *"@sha256:"* ]]; then
      echo "::error file=${rel},line=${line_no}::pinning convention (docs/CONVENTIONS.md): floating reference '${ref}' — pin by @sha256 digest"
      violations=$((violations + 1))
    fi
  done < <(awk 'match($0, /^[[:space:]]*(-[[:space:]]+)?(image|base|uses):[[:space:]]*/) {
                  key = substr($0, RSTART, RLENGTH)
                  gsub(/[^a-z]/, "", key)
                  top = ($0 ~ /^image:/) ? 1 : 0
                  val = substr($0, RSTART + RLENGTH)
                  if (val != "") printf "%s\t%d\t%d\t%s\n", key, NR, top, val
                }' "$file")

  # Frontend pin (ADR 0001): any '# syntax=' line carries a digest
  while IFS=: read -r line_no rest; do
    if [[ "$rest" != *"@sha256:"* ]]; then
      echo "::error file=${rel},line=${line_no}::pinning convention (docs/CONVENTIONS.md): '# syntax=' must pin the frontend by @sha256 digest"
      violations=$((violations + 1))
    fi
  done < <(grep -n '^#[[:space:]]*syntax=' "$file" || true)

  # Definitions declare the frontend on line 1
  if [[ "$file" == "$ROOT"/image/*/image.yaml ]]; then
    if ! head -1 "$file" | grep -q '^#[[:space:]]*syntax='; then
      echo "::error file=${rel},line=1::pinning convention (docs/CONVENTIONS.md): definition missing digest-pinned '# syntax=' frontend line"
      violations=$((violations + 1))
    fi
  fi

  # Release tags must be valid OCI references: [a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}.
  # An upstream that versions with semver build metadata (grafana ships
  # v13.0.1+security-01) otherwise yields a tag the daemon rejects outright —
  # "invalid reference format" — at push time rather than at review time. The
  # build separator becomes '_' (docs/CONVENTIONS.md, Upstream tracking).
  # Scoped to a definition's own top-level tags: block; a nested tags: elsewhere
  # is not a release tag list.
  if [[ "$file" == "$ROOT"/image/*/image.yaml ]]; then
    while IFS=$'\t' read -r line_no tag; do
      if ! [[ "$tag" =~ ^[a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}$ ]]; then
        echo "::error file=${rel},line=${line_no}::pinning convention (docs/CONVENTIONS.md): release tag '${tag}' is not a valid OCI tag — must match [a-zA-Z0-9_][a-zA-Z0-9._-]{0,127} (a semver '+' build separator becomes '_')"
        violations=$((violations + 1))
      fi
    done < <(awk '/^tags:/ { intags = 1; next }
                  intags && /^[^[:space:]]/ { intags = 0 }
                  intags && match($0, /^[[:space:]]*-[[:space:]]*/) {
                    val = substr($0, RSTART + RLENGTH)
                    sub(/[[:space:]]*#.*$/, "", val); sub(/[[:space:]]+$/, "", val)
                    gsub(/^["'\'']|["'\'']$/, "", val)
                    if (val != "") printf "%d\t%s\n", NR, val
                  }' "$file")
  fi

  # Every git+ source pins a commit checksum (Req 1.3)
  c_git=$(grep -cE 'url:[[:space:]]*["'\'']?git\+' "$file" || true)
  c_sum=$(grep -cE '^[[:space:]]*checksum:' "$file" || true)
  if [ "$c_git" -gt "$c_sum" ]; then
    echo "::error file=${rel}::pinning convention (docs/CONVENTIONS.md): ${c_git} git+ source(s) but ${c_sum} checksum line(s) — every git source pins a commit checksum"
    violations=$((violations + 1))
  fi

  # A bump PR must leave the definition coherent (docs/CONVENTIONS.md, Req 7.4).
  # A definition states its upstream version in eight places; the Renovate regex
  # managers turn exactly one and refresh-{definition,grafana}.sh regenerate the
  # rest. When that postUpgradeTask refuses — grafana 13.1.3 had no resolvable
  # build id — Renovate opens the PR anyway carrying the partial edit, and the
  # only thing that noticed was `build` fetching a tarball whose checksum did
  # not match. That reads as a checksum defect and costs an image build to
  # learn. Here it is one version comparison, in validate, naming the field.
  #
  # Scope note: the declared version is `vars: VERSION`, and a definition
  # without one is skipped rather than failed — an archetype that does not
  # version this way has nothing to be incoherent with. Numbers outside the
  # version-bearing keys below are not read as versions, which is what keeps
  # alpine3.23, v3.23 apk repositories and 3000/tcp out of it.
  if [[ "$file" == "$ROOT"/image/*/image.yaml ]]; then
    declared=$(awk 'match($0, /^[[:space:]]+VERSION:[[:space:]]*/) {
                      v = substr($0, RSTART + RLENGTH)
                      sub(/[[:space:]]*#.*$/, "", v); sub(/[[:space:]]+$/, "", v)
                      gsub(/^["'\'']|["'\'']$/, "", v)
                      if (v != "") { print v; exit }
                    }' "$file")
    if [ -n "$declared" ]; then
      incoherent=$(awk -v want="$declared" -v rel="$rel" '
        function report(line, msg) {
          printf "::error file=%s,line=%d::coherence convention (docs/CONVENTIONS.md): %s — the definition declares VERSION %s\n", rel, line, msg, want
        }
        # A YAML comment needs whitespace before its "#". Stripping on a bare
        # "#" would eat the ref off every git+ source we have —
        # git+https://…/cert-manager.git#v1.21.1 would arrive here as a url
        # stating no version at all, and the check would pass by finding
        # nothing to compare.
        function clean(s) {
          sub(/[[:space:]]+#.*$/, "", s); sub(/[[:space:]]+$/, "", s)
          gsub(/^["'\'']|["'\'']$/, "", s)
          return s
        }
        BEGIN {
          # A release tag spells semver build metadata with "_" (case 18 above),
          # so the tag forms are derived from the transformed version, and the
          # SEMVER_* vars from the untransformed one.
          tagfull = want; gsub(/\+/, "_", tagfull)
          split(want, p, "."); major = p[1]; minor = p[1] "." p[2]
          split(tagfull, q, "."); tagmajor = q[1]; tagminor = q[1] "." q[2]
        }
        /^tags:/ { intags = 1; next }
        intags && /^[^[:space:]]/ { intags = 0 }
        intags && match($0, /^[[:space:]]*-[[:space:]]*/) {
          t = clean(substr($0, RSTART + RLENGTH))
          if (t != "" \
              && index(t, tagmajor "-") != 1 \
              && index(t, tagminor "-") != 1 \
              && index(t, tagfull "-") != 1)
            report(NR, sprintf("release tag \"%s\" states another version", t))
          next
        }
        match($0, /^[[:space:]]*(-[[:space:]]+)?[A-Za-z_][A-Za-z0-9_-]*:[[:space:]]*/) {
          head = substr($0, RSTART, RLENGTH)
          key = head; gsub(/[^A-Za-z0-9_]/, "", key)
          val = clean(substr($0, RSTART + RLENGTH))
          if (val == "") next

          if (key == "VERSION") next
          if (key == "SEMVER_VERSION") {
            if (val != want) report(NR, sprintf("SEMVER_VERSION is %s", val))
          } else if (key == "SEMVER_MAJOR_VERSION") {
            if (val != major) report(NR, sprintf("SEMVER_MAJOR_VERSION is %s, not %s", val, major))
          } else if (key == "SEMVER_MAJOR_MINOR_VERSION") {
            if (val != minor) report(NR, sprintf("SEMVER_MAJOR_MINOR_VERSION is %s, not %s", val, minor))
          } else if (key ~ /_VERSION$/) {
            if (val != want) report(NR, sprintf("%s is %s", key, val))
          } else if (key == "version") {
            # The SPDX version — what lands in the SBOM of a published image.
            if (val != want) report(NR, sprintf("SPDX version is %s", val))
          } else if (key == "purl") {
            if (match(val, /@[^@[:space:]]+$/)) {
              pv = substr(val, RSTART + 1, RLENGTH - 1)
              if (pv != want) report(NR, sprintf("purl \"%s\" states %s", val, pv))
            }
          } else if (key == "url") {
            # Every full semver the url states, wherever it sits in the path —
            # the repackage archetype names the version twice (directory and
            # filename) and PR #36 moved only the first. A leading "v" is the
            # git-ref spelling (cert-manager pins #v1.21.1, valkey pins #9.1.1)
            # and not a disagreement.
            s = val
            while (match(s, /[0-9]+\.[0-9]+\.[0-9]+(\+[A-Za-z0-9.-]+)?/)) {
              tok = substr(s, RSTART, RLENGTH)
              s = substr(s, RSTART + RLENGTH)
              if (tok != want) report(NR, sprintf("source url states %s", tok))
            }
          }
        }' "$file")
      if [ -n "$incoherent" ]; then
        printf '%s\n' "$incoherent"
        violations=$((violations + $(printf '%s\n' "$incoherent" | wc -l)))
      fi
    fi
  fi
done < <(find "${scan_dirs[@]}" -type f -name '*.yaml' -print0)

if [ "$violations" -gt 0 ]; then
  echo "lint-pins: ${violations} violation(s) — see docs/CONVENTIONS.md (Pinning, Upstream tracking)"
  exit 1
fi
echo "lint-pins: all pinning conventions satisfied"
