#!/usr/bin/env bash
# Tests for scripts/lint-active-set.sh, the validate-side coherence and scope
# lint of catalogue-policy.yaml's active set (Req 1.16, 1.18, 1.19; task 14.2).
# Contract: the set reads through definition-lib's reader (a malformed set is
# its refusal, surfaced here by name, Req 1.19); a set that splits a group
# (two definitions publishing one repository, or several bumped from one
# source repository) fails naming the group (Req 1.18); every chart
# directory declares the definitions it deploys, each an existing definition;
# and, given the pull request's changed paths, a change under an inactive
# definition or under a chart adaptation deploying no active definition fails
# naming it (Req 1.16). Deletions are not changes to a frozen thing.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LINT="$HERE/lint-active-set.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }
expect() { # name, expected rc, actual rc, output, needles...
  local name="$1" want="$2" rc="$3" out="$4"; shift 4
  if [ "$rc" -ne "$want" ]; then fail "$name" "exit=$rc, wanted $want" "$out"; return; fi
  local n; for n in "$@"; do
    if ! grep -qF -- "$n" <<<"$out"; then fail "$name" "missing '$n'" "$out"; return; fi
  done
  pass "$name"
}

fresh() {
  SB=$(mktemp -d)
  def app acme/app
  def db acme/db db
  def db-compat acme/db db     # the byte-equal pair: one published repository
  def cm-a cert-manager/cert-manager
  def cm-b cert-manager/cert-manager  # the grouped monorepo: one source
  def old acme/old
  chart app app
  chart db db db-compat
  chart cm cm-a cm-b
  chart old old
  policy app db db-compat cm-a cm-b
}
def() { # name source-repo [published-name]
  mkdir -p "$SB/image/$1"
  printf 'image: ghcr.io/acme/imgs/%s\ncontents:\n  builds:\n    - contents:\n        files:\n          - url: git+https://github.com/%s.git#v1.0.0\n            checksum: abc\n' "${3:-$1}" "$2" > "$SB/image/$1/image.yaml"
}
chart() { # dir deploys...
  mkdir -p "$SB/chart/$1"; local d="$1"; shift
  { printf 'deploys:\n'; printf '  - %s\n' "$@"; } > "$SB/chart/$d/chart.yaml"
}
policy() { { printf 'active_set:\n'; printf '  - %s\n' "$@"; } > "$SB/catalogue-policy.yaml"; }

# 1: a coherent set: exit 0, the summary names the counts
fresh
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "coherent set passes, naming what it checked" 0 "$rc" "$out" "5 active" "1 inactive" "4 chart"

# 2: Req 1.18, the byte-equal pair: db active, db-compat not
fresh; policy app db cm-a cm-b
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "splitting a runtime/variant pair fails naming the group" 1 "$rc" "$out" "Req 1.18" "ghcr.io/acme/imgs/db" "db-compat" "image/db/"

# 3: Req 1.18, the grouped monorepo: cm-a active, cm-b not
fresh; policy app db db-compat cm-a
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "splitting a source-grouped monorepo fails naming the group" 1 "$rc" "$out" "Req 1.18" "cert-manager/cert-manager" "cm-b"

# 4: Req 1.19 is the reader's refusal, surfaced here
fresh; policy app typo
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "an entry naming no definition directory fails naming it" 1 "$rc" "$out" "typo" "Req 1.19"

# 5: every chart directory declares what it deploys, and each entry exists
fresh; rm "$SB/chart/old/chart.yaml"
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "a chart directory without a deploys list fails naming it" 1 "$rc" "$out" "chart/old" "deploys"
fresh; chart app app ghost
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "a deploys entry naming no definition fails naming chart and entry" 1 "$rc" "$out" "chart/app" "ghost"

# 6: Req 1.16 over the pull request's changed paths
fresh
out=$(printf 'image/app/image.yaml\nchart/app/values.yaml\ndocs/x.md\n' | "$LINT" --changed - "$SB" 2>&1); rc=$?
expect "changes under active definitions and their charts pass" 0 "$rc" "$out"
out=$(printf 'image/old/image.yaml\n' | "$LINT" --changed - "$SB" 2>&1); rc=$?
expect "a change under an inactive definition fails naming it (Req 1.16)" 1 "$rc" "$out" "image/old" "Req 1.16" "active_set"
mkdir -p "$SB/chart/old/config"; : > "$SB/chart/old/config/values-hardened.yaml"
out=$(printf 'chart/old/config/values-hardened.yaml\n' | "$LINT" --changed - "$SB" 2>&1); rc=$?
expect "a change under a chart deploying no active definition fails naming it" 1 "$rc" "$out" "chart/old" "Req 1.16"
# a deletion (the path no longer exists) is not a bump of a frozen thing
out=$(printf 'image/old/README.md\n' | "$LINT" --changed - "$SB" 2>&1); rc=$?
expect "a deleted path under an inactive definition is not a violation" 0 "$rc" "$out"
# activating in the same PR is the sanctioned way to touch a frozen definition
fresh; policy app db db-compat cm-a cm-b old
out=$(printf 'image/old/image.yaml\n' | "$LINT" --changed - "$SB" 2>&1); rc=$?
expect "a change under a definition the PR activates passes" 0 "$rc" "$out"

# 7: no policy file is a refusal by path
fresh; rm "$SB/catalogue-policy.yaml"
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "no catalogue-policy.yaml is refused naming the path" 1 "$rc" "$out" "catalogue-policy.yaml"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all lint-active-set tests passed"
