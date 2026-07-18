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

# 1: digest-pinned image + base pass
fresh
printf 'base: ghcr.io/mm-weber/dhc/base@%s\n' "$DIGEST" > "$SB/image/app/image.yaml"
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
printf 'image: ghcr.io/mm-weber/dhc/app:latest\n' > "$SB/image/app/image.yaml"
run_case ":latest fails" 1 ":latest"

# 4: tag plus digest passes
fresh
printf 'image: ghcr.io/mm-weber/dhc/app:1.0.0@%s\n' "$DIGEST" > "$SB/chart/app/config/values.yaml"
run_case "tag+digest passes" 0

# 5: bare reference without tag or digest fails (implicit latest)
fresh
printf 'image: ghcr.io/mm-weber/dhc/app\n' > "$SB/image/app/image.yaml"
run_case "bare ref fails" 1 "ghcr.io/mm-weber/dhc/app"

# 6: only image/ and chart/ are scanned (policy fixtures may hold bad refs)
fresh
printf 'image: ghcr.io/mm-weber/dhc/app:1.0.0\n' > "$SB/policies/tests/resources.yaml"
run_case "policies/ not scanned" 0

# 7: nested keys with indentation are caught
fresh
printf 'spec:\n  template:\n    image: docker.io/library/nginx:1.27\n' > "$SB/chart/app/config/values.yaml"
run_case "indented key caught" 1 "nginx:1.27"

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES test(s) failed"; exit 1; fi
echo "all tests passed"
