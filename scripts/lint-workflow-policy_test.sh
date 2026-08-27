#!/usr/bin/env bash
# Tests for scripts/lint-workflow-policy.sh: sandboxed repo, no fixtures.
# Contract under test (Req 7.10): every workflow's schedule cron and every
# permissions block (workflow default and explicit per-job) must equal what
# catalogue-policy.yaml's `workflows:` section declares, each mismatch failing
# by name. GitHub reads workflow YAML literally, so the lint is what binds the
# literal values to the declared ones. A declared schedule not yet wired into
# its workflow passes (forward-only; task 9.2 wires build.yml's cron).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LINT="$HERE/lint-workflow-policy.sh"
FAILURES=0

pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

fresh() {
  SB=$(mktemp -d)
  mkdir -p "$SB/.github/workflows"
  cat > "$SB/catalogue-policy.yaml" <<'EOF'
workflows:
  cron.yml:
    schedule: "17 6 * * *"
    permissions:
      contents: read
      packages: read
    jobs:
      release:
        permissions:
          contents: read
          id-token: write
  plain.yml:
    schedule: null
    permissions:
      contents: read
  wired-later.yml:
    schedule: "47 4 * * *"
    permissions:
      contents: read
EOF
  cat > "$SB/.github/workflows/cron.yml" <<'EOF'
name: cron
on:
  schedule:
    - cron: "17 6 * * *"
permissions:
  contents: read
  packages: read
jobs:
  scan:
    runs-on: ubuntu-latest
    steps: [{run: "true"}]
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps: [{run: "true"}]
EOF
  cat > "$SB/.github/workflows/plain.yml" <<'EOF'
name: plain
on:
  pull_request:
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    steps: [{run: "true"}]
EOF
  cat > "$SB/.github/workflows/wired-later.yml" <<'EOF'
name: wired-later
on:
  pull_request:
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    steps: [{run: "true"}]
EOF
}

# 1: everything matching (including a declared-but-unwired schedule) passes
fresh
out=$("$LINT" "$SB" 2>&1); rc=$?
[ "$rc" -eq 0 ] && pass "matching tree passes" || fail "matching tree passes" "exit=$rc" "$out"

# 2: cron drift fails naming the workflow and both values
fresh
sed -i 's/17 6 \* \* \*/0 0 * * */' "$SB/.github/workflows/cron.yml"
out=$("$LINT" "$SB" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && grep -qF "cron.yml" <<<"$out" && grep -qF "0 0 * * *" <<<"$out" && grep -qF "17 6 * * *" <<<"$out"; then
  pass "cron drift fails naming workflow and values"
else
  fail "cron drift fails naming workflow and values" "exit=$rc" "$out"
fi

# 3: a cron in a workflow whose declaration has none fails
fresh
printf 'on:\n  schedule:\n    - cron: "1 2 3 4 5"\npermissions:\n  contents: read\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps: [{run: "true"}]\n' > "$SB/.github/workflows/plain.yml"
out=$("$LINT" "$SB" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && grep -qF "plain.yml" <<<"$out"; then
  pass "undeclared cron fails naming the workflow"
else
  fail "undeclared cron fails naming the workflow" "exit=$rc" "$out"
fi

# 4: workflow-default permissions drift fails naming workflow and key
fresh
sed -i '0,/packages: read/s//packages: write/' "$SB/.github/workflows/cron.yml"
out=$("$LINT" "$SB" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && grep -qF "cron.yml" <<<"$out" && grep -qF "packages" <<<"$out"; then
  pass "default-permissions drift fails naming workflow and key"
else
  fail "default-permissions drift fails naming workflow and key" "exit=$rc" "$out"
fi

# 5: explicit job permissions drift fails naming the job
fresh
sed -i 's/id-token: write/id-token: none/' "$SB/.github/workflows/cron.yml"
out=$("$LINT" "$SB" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && grep -qF "release" <<<"$out"; then
  pass "job-permissions drift fails naming the job"
else
  fail "job-permissions drift fails naming the job" "exit=$rc" "$out"
fi

# 6: an explicit job permissions block with no declaration fails naming the job
fresh
python3 - "$SB/.github/workflows/plain.yml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("  a:\n    runs-on: ubuntu-latest\n",
              "  a:\n    runs-on: ubuntu-latest\n    permissions:\n      contents: write\n")
open(p, "w").write(s)
PY
out=$("$LINT" "$SB" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && grep -qF "plain.yml" <<<"$out" && grep -qF "a" <<<"$out"; then
  pass "undeclared job permissions fail naming the job"
else
  fail "undeclared job permissions fail naming the job" "exit=$rc" "$out"
fi

# 7: a workflow file with no declaration at all fails naming it
fresh
printf 'on:\n  pull_request:\npermissions:\n  contents: read\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps: [{run: "true"}]\n' > "$SB/.github/workflows/rogue.yml"
out=$("$LINT" "$SB" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && grep -qF "rogue.yml" <<<"$out"; then
  pass "undeclared workflow fails naming it"
else
  fail "undeclared workflow fails naming it" "exit=$rc" "$out"
fi

# 8: an unparseable workflow fails naming the file, with no traceback. GitHub
# refuses to run a workflow whose YAML does not parse and reports it only on
# the run page, so the lint is the local place that catches it; a plain step
# name carrying a colon and a space is the shape that bit this repo (a sed
# over step names, 2026-08-26).
fresh
printf 'name: broken\non:\n  pull_request:\npermissions:\n  contents: read\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - name: lint: docs/CONVENTIONS.md\n        run: "true"\n' > "$SB/.github/workflows/plain.yml"
out=$("$LINT" "$SB" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && grep -qF "plain.yml" <<<"$out" && ! grep -qF "Traceback" <<<"$out"; then
  pass "unparseable workflow fails naming the file, no traceback"
else
  fail "unparseable workflow fails naming the file, no traceback" "exit=$rc" "$out"
fi

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all lint-workflow-policy tests passed"
