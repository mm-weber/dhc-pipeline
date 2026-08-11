#!/usr/bin/env bash
# Tests for scripts/lint-pins.sh — self-contained sandbox, no fixture files.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LINT="$HERE/lint-pins.sh"
FAILURES=0

run_case() { # name, expected_exit, expect_substring(optional) — sandbox in $SB
  local name="$1" expected="$2" substr="${3:-}"
  local out rc
  out=$("$LINT" "$SB" 2>&1); rc=$?
  if [ "$rc" -ne "$expected" ]; then
    echo "FAIL $name: exit $rc, expected $expected"; echo "$out" | sed 's/^/    /'
    FAILURES=$((FAILURES+1)); return
  fi
  if [ -n "$substr" ] && ! grep -qF "$substr" <<<"$out"; then
    echo "FAIL $name: output missing '$substr'"; echo "$out" | sed 's/^/    /'
    FAILURES=$((FAILURES+1)); return
  fi
  echo "ok   $name"
}

fresh() { SB=$(mktemp -d); mkdir -p "$SB/image/app" "$SB/chart/app/config" "$SB/policies/tests"; }
DIGEST="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SYNTAX="# syntax=dhi.io/build:2-alpine3.22@${DIGEST}"

# 1: digest-pinned definition + chart values pass
fresh
printf '%s\nbase: ghcr.io/mm-weber/dhc/base@%s\n' "$SYNTAX" "$DIGEST" > "$SB/image/app/image.yaml"
printf 'image: ghcr.io/mm-weber/dhc/app@%s\n' "$DIGEST" > "$SB/chart/app/config/values.yaml"
run_case "digest-pinned passes" 0

# 2: tag-only reference fails, names the ref and the file
fresh
printf 'image: ghcr.io/mm-weber/dhc/app:1.0.0\n' > "$SB/chart/app/config/values.yaml"
run_case "tag-only fails naming ref" 1 "ghcr.io/mm-weber/dhc/app:1.0.0"
run_case "tag-only fails naming file" 1 "chart/app/config/values.yaml"
run_case "failure cites convention" 1 "CONVENTIONS.md"

# 3: :latest fails
fresh
printf 'image: ghcr.io/mm-weber/dhc/app:latest\n' > "$SB/chart/app/config/values.yaml"
run_case ":latest fails" 1 ":latest"

# 4: tag plus digest passes
fresh
printf 'image: ghcr.io/mm-weber/dhc/app:1.0.0@%s\n' "$DIGEST" > "$SB/chart/app/config/values.yaml"
run_case "tag+digest passes" 0

# 5: bare reference without tag or digest fails (implicit latest)
fresh
printf 'image: ghcr.io/mm-weber/dhc/app\n' > "$SB/chart/app/config/values.yaml"
run_case "bare ref fails" 1 "ghcr.io/mm-weber/dhc/app"

# 6: only image/ and chart/ are scanned (policy fixtures may hold bad refs)
fresh
printf 'image: ghcr.io/mm-weber/dhc/app:1.0.0\n' > "$SB/policies/tests/resources.yaml"
run_case "policies/ not scanned" 0

# 7: nested keys with indentation are caught
fresh
printf 'spec:\n  template:\n    image: docker.io/library/nginx:1.27\n' > "$SB/chart/app/config/values.yaml"
run_case "indented key caught" 1 "nginx:1.27"

# --- definition rules (decision A, ADR 0001) ---

# 8: full valid definition passes (pinned syntax, pinned uses, git+checksum)
fresh
cat > "$SB/image/app/image.yaml" <<EOF
$SYNTAX
vars:
  VERSION: 1.0.0
contents:
  builds:
    - name: app
      uses: dhi.io/golang:1.26.4-alpine3.23-dev@$DIGEST
      contents:
        files:
          - url: git+https://github.com/mm-weber/app.git#v1.0.0
            checksum: 73f83dfd5f84221455606ad7c3813d4f0ec1330d
      pipeline:
        - name: build
          uses: go/build@v1
EOF
run_case "valid definition passes" 0

# 9: syntax line without digest fails
fresh
printf '# syntax=dhi.io/build:2-alpine3.22\nvars: {VERSION: 1.0.0}\n' > "$SB/image/app/image.yaml"
run_case "unpinned syntax line fails" 1 "syntax"

# 10: definition file without any syntax line fails
fresh
printf 'vars: {VERSION: 1.0.0}\n' > "$SB/image/app/image.yaml"
run_case "missing syntax line fails" 1 "syntax"

# 11: uses with registry host but no digest fails
fresh
printf '%s\ncontents:\n  builds:\n    - uses: dhi.io/golang:1.26-alpine3.23-dev\n' "$SYNTAX" > "$SB/image/app/image.yaml"
run_case "unpinned builder uses fails" 1 "dhi.io/golang:1.26-alpine3.23-dev"

# 12: action uses (no registry host) is NOT an image ref, passes
fresh
printf '%s\ncontents:\n  builds:\n    - pipeline:\n        - uses: go/bump@v2\n' "$SYNTAX" > "$SB/image/app/image.yaml"
run_case "action uses not flagged" 0

# 13: git+ source without checksum fails
fresh
printf '%s\nfiles:\n  - url: git+https://github.com/x/y.git#v1\n    path: /src\n' "$SYNTAX" > "$SB/image/app/image.yaml"
run_case "git source without checksum fails" 1 "checksum"

# 14: definition top-level image: is the PUBLISH name — bare ref passes
fresh
printf '%s\nimage: ghcr.io/mm-weber/dhc/app\ntags:\n  - 1.0.0-alpine3.23\n' "$SYNTAX" > "$SB/image/app/image.yaml"
run_case "definition publish name passes" 0

# 15: definition publish name must NOT carry a tag (tags live under tags:)
fresh
printf '%s\nimage: ghcr.io/mm-weber/dhc/app:1.0.0\n' "$SYNTAX" > "$SB/image/app/image.yaml"
run_case "tagged publish name fails" 1 "publish name"

# 16: indented image: inside a definition still needs a digest
fresh
printf '%s\nspec:\n  image: docker.io/library/nginx:1.27\n' "$SYNTAX" > "$SB/image/app/image.yaml"
run_case "indented image in definition caught" 1 "nginx:1.27"

# 17: Helm-template image ref in an owned chart is not a literal pin — passes
# (the digest lives in values.yaml; kyverno gates the rendered manifests)
fresh
mkdir -p "$SB/chart/app/templates"
printf 'image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}@{{ .Values.image.digest }}"\n' > "$SB/chart/app/templates/deployment.yaml"
run_case "helm-template image ref not flagged" 0

# 18: release tags must be valid OCI references. An upstream that versions with
# semver build metadata (grafana ships v13.0.1+security-01) yields a tag docker
# refuses with "invalid reference format" — the build separator has to be '_'.
fresh
printf '%s\nimage: ghcr.io/mm-weber/dhc/app\ntags:\n  - 13.0.1+security-01-alpine3.23\n' "$SYNTAX" > "$SB/image/app/image.yaml"
run_case "tag with '+' fails" 1 "13.0.1+security-01-alpine3.23"
run_case "tag with '+' cites OCI validity" 1 "not a valid OCI tag"

# 19: the '_' form of the same tag is valid and passes
fresh
printf '%s\nimage: ghcr.io/mm-weber/dhc/app\ntags:\n  - 13.0.1_security-01-alpine3.23\n' "$SYNTAX" > "$SB/image/app/image.yaml"
run_case "tag with '_' passes" 0

# 20: a tag may not start with '.' or '-' (OCI: first char is alnum or '_')
fresh
printf '%s\nimage: ghcr.io/mm-weber/dhc/app\ntags:\n  - .1.0.0-alpine3.23\n' "$SYNTAX" > "$SB/image/app/image.yaml"
run_case "tag starting with '.' fails" 1 "not a valid OCI tag"

# 21: the tag check is scoped to the definition's own top-level tags: block —
# a nested tags: (e.g. chart values) is not a release tag list
fresh
printf 'tags:\n  - not+a+release+tag\n' > "$SB/chart/app/config/values.yaml"
run_case "chart-side tags: not treated as OCI tags" 0

# --- version coherence (docs/CONVENTIONS.md "A bump PR must leave the
#     definition coherent", Req 7.4) ---
#
# A definition states its upstream version in eight places: three release tags,
# three SEMVER_* vars, the source url (twice, for a repackage), the SPDX
# version, the purl, and an environment var. The Renovate regex managers turn
# exactly ONE of them; scripts/refresh-{definition,grafana}.sh regenerate the
# rest as a postUpgradeTask. When that task refuses — grafana 13.1.3 had no
# resolvable build id, so refresh-grafana.sh exited 1 rather than invent a pin —
# Renovate still opens the PR carrying the manager's partial edit. PR #36 is
# what that looks like:
#
#     url: …/grafana/release/13.1.3/grafana_13.1.2_30900078095_linux_amd64.tar.gz
#                            ^^^^^^          ^^^^^^
#
# with all seven other fields left on 13.1.2. Nothing caught it until `build`
# fetched the tarball and its checksum did not match, which reads as a checksum
# defect and costs a full image build to learn. Req 7.4 asks for the opposite:
# a convention violation fails with a message identifying the convention.
#
# So: every version a definition states must be the version it declares.

# A definition coherent at $1 — every version-bearing field agreeing. The cases
# below each break exactly one, so a failure names the field that drifted.
coherent_defn() { # version -> definition on stdout
  local v="$1" tag="${1//+/_}" major minor
  major="${v%%.*}"; minor="$(printf '%s' "$v" | cut -d. -f1,2)"
  cat <<EOF
$SYNTAX
image: ghcr.io/mm-weber/dhc/app
tags:
  - ${major}-alpine3.23
  - $(printf '%s' "$tag" | cut -d. -f1,2)-alpine3.23
  - ${tag}-alpine3.23
vars:
  SEMVER_MAJOR_VERSION: "${major}"
  SEMVER_MAJOR_MINOR_VERSION: "${minor}"
  SEMVER_VERSION: ${v}
  VERSION: ${v}
contents:
  builds:
    - name: app
      contents:
        files:
          - url: https://dl.example.com/app/release/${v}/app_${v}_30900078095_linux_amd64.tar.gz
            spdx:
              name: app
              version: ${v}
              packages:
                - name: app
                  purl: pkg:generic/app@${v}
environment:
  APP_VERSION: ${v}
EOF
}

# 22: a coherent definition passes
fresh
coherent_defn 13.1.2 > "$SB/image/app/image.yaml"
run_case "coherent definition passes" 0

# 23: PR #36 exactly — the url path moved, its filename did not
fresh
coherent_defn 13.1.2 > "$SB/image/app/image.yaml"
sed -i 's#release/13.1.2/#release/13.1.3/#' "$SB/image/app/image.yaml"
run_case "partial url bump fails" 1 "13.1.3"
run_case "partial url bump names the declared version" 1 "13.1.2"
run_case "partial url bump cites the convention" 1 "CONVENTIONS.md"
run_case "partial url bump names the file" 1 "image/app/image.yaml"

# 24: the inverse — filename moved, path did not. Same defect, other half.
fresh
coherent_defn 13.1.2 > "$SB/image/app/image.yaml"
sed -i 's#app_13.1.2_#app_13.1.3_#' "$SB/image/app/image.yaml"
run_case "partial url filename bump fails" 1 "13.1.3"

# 25: a release tag left behind
fresh
coherent_defn 13.1.2 > "$SB/image/app/image.yaml"
sed -i 's#^  - 13.1.2-alpine3.23#  - 13.1.1-alpine3.23#' "$SB/image/app/image.yaml"
run_case "stale release tag fails" 1 "13.1.1"

# 26: SEMVER_VERSION left behind
fresh
coherent_defn 13.1.2 > "$SB/image/app/image.yaml"
sed -i 's#^  SEMVER_VERSION: 13.1.2#  SEMVER_VERSION: 13.1.1#' "$SB/image/app/image.yaml"
run_case "stale SEMVER_VERSION fails" 1 "SEMVER_VERSION"

# 27: the SPDX version — what lands in the SBOM of a published image
fresh
coherent_defn 13.1.2 > "$SB/image/app/image.yaml"
sed -i 's#^              version: 13.1.2#              version: 13.1.1#' "$SB/image/app/image.yaml"
run_case "stale spdx version fails" 1 "13.1.1"

# 28: the purl — what a VEX statement's subcomponent is matched against, so a
# stale one silently re-scopes every triage decision written about this image
fresh
coherent_defn 13.1.2 > "$SB/image/app/image.yaml"
sed -i 's#pkg:generic/app@13.1.2#pkg:generic/app@13.1.1#' "$SB/image/app/image.yaml"
run_case "stale purl fails" 1 "13.1.1"

# 29: an environment version var (grafana ships GRAFANA_VERSION)
fresh
coherent_defn 13.1.2 > "$SB/image/app/image.yaml"
sed -i 's#^  APP_VERSION: 13.1.2#  APP_VERSION: 13.1.1#' "$SB/image/app/image.yaml"
run_case "stale environment version fails" 1 "APP_VERSION"

# 30: SEMVER_MAJOR_* are truncations, not disagreements — "13" and "13.1"
# against VERSION 13.1.2 are correct, and a check that reads every dotted
# number as a version would reject every definition in the catalogue.
fresh
coherent_defn 13.1.2 > "$SB/image/app/image.yaml"
run_case "SEMVER_MAJOR_* truncations not flagged" 0

# 31: a truncation that is genuinely wrong is still caught
fresh
coherent_defn 13.1.2 > "$SB/image/app/image.yaml"
sed -i 's#^  SEMVER_MAJOR_MINOR_VERSION: "13.1"#  SEMVER_MAJOR_MINOR_VERSION: "13.0"#' "$SB/image/app/image.yaml"
run_case "wrong SEMVER_MAJOR_MINOR fails" 1 "SEMVER_MAJOR_MINOR_VERSION"

# 32: the variant segment is not a version. Every tag carries alpine3.23 and
# every definition names v3.23 apk repositories; reading those as versions
# would fail the whole catalogue.
fresh
coherent_defn 13.1.2 > "$SB/image/app/image.yaml"
cat >> "$SB/image/app/image.yaml" <<'EOF'
  repositories:
    - https://dl-cdn.alpinelinux.org/alpine/v3.23/main
os-release:
  version-id: "3.23"
ports:
  - 3000/tcp
EOF
run_case "variant and unrelated numbers not flagged" 0

# 33: git+ sources tag with and without a leading 'v' — cert-manager pins
# '#v1.21.1', valkey pins '#9.1.1'. Both are the declared version.
fresh
coherent_defn 1.21.1 > "$SB/image/app/image.yaml"
sed -i 's#^          - url: https://.*#          - url: git+https://github.com/x/app.git\#v1.21.1\n            checksum: 24e33194fb39488eff2bbf10c6dc640f407cad44#' "$SB/image/app/image.yaml"
run_case "git+ source with 'v' prefix passes" 0

fresh
coherent_defn 9.1.1 > "$SB/image/app/image.yaml"
sed -i 's#^          - url: https://.*#          - url: git+https://github.com/x/app.git\#9.1.1\n            checksum: d27f9ba65a04e80d9c417112a7621fc98a56f70d#' "$SB/image/app/image.yaml"
run_case "git+ source without 'v' prefix passes" 0

# 34: a git+ source pinning a version we do not declare is the same defect
fresh
coherent_defn 1.21.1 > "$SB/image/app/image.yaml"
sed -i 's#^          - url: https://.*#          - url: git+https://github.com/x/app.git\#v1.21.0\n            checksum: 24e33194fb39488eff2bbf10c6dc640f407cad44#' "$SB/image/app/image.yaml"
run_case "git+ source on another version fails" 1 "1.21.0"

# 35: semver build metadata. grafana ships 13.0.1+security-01; the release tag
# spells it 13.0.1_security-01 (case 18), the url keeps the '+'. Both state the
# declared version, and the tag transform is not a disagreement.
fresh
coherent_defn '13.0.1+security-01' > "$SB/image/app/image.yaml"
run_case "'+security' build metadata passes" 0

# 35b: the closing summary counts violations of several conventions, so it may
# not describe them all as floating references — a coherence failure sends the
# reader looking for an unpinned digest that is not there.
fresh
coherent_defn 13.1.2 > "$SB/image/app/image.yaml"
sed -i 's#release/13.1.2/#release/13.1.3/#' "$SB/image/app/image.yaml"
run_case "summary does not call a coherence failure a floating reference" 1 "1 violation"

# 36: only definitions are checked. Chart values carry their own versions
# (appVersion, dependency pins) and answer to their chart, not to a definition.
fresh
printf 'appVersion: 9.9.9\nversion: 1.2.3\n' > "$SB/chart/app/config/values.yaml"
run_case "chart values not version-checked" 0

# 37: a definition with no VERSION declared has nothing to be coherent with —
# skipped rather than failed, so the rule cannot block an archetype that does
# not version this way.
fresh
printf '%s\nimage: ghcr.io/mm-weber/dhc/app\n' "$SYNTAX" > "$SB/image/app/image.yaml"
run_case "definition without VERSION skipped" 0

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES test(s) failed"; exit 1; fi
echo "all tests passed"
