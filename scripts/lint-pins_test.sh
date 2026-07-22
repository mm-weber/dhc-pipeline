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

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES test(s) failed"; exit 1; fi
echo "all tests passed"
