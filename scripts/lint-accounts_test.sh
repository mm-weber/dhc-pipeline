#!/usr/bin/env bash
# Tests for scripts/lint-accounts.sh (Req 1.4; review D5, 2026-09-09): every
# definition under image/ declares a non-root runtime account with UID 65532
# in its accounts block, or validate fails naming the definition. Until this
# lint nothing read the block; a definition running as root, or as uid 1000,
# passed every gate, and the e2e assertion reads the chart's securityContext,
# not the image.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LINT="$HERE/lint-accounts.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }
expect() { local name="$1" want="$2" rc="$3" out="$4"; shift 4
  if [ "$rc" -ne "$want" ]; then fail "$name" "exit=$rc, wanted $want" "$out"; return; fi
  local n; for n in "$@"; do grep -qF -- "$n" <<<"$out" || { fail "$name" "missing '$n'" "$out"; return; }; done
  pass "$name"; }
fresh() { SB=$(mktemp -d); }
def() { # name, then the accounts block lines (or nothing)
  mkdir -p "$SB/image/$1"; local d="$1"; shift
  { printf '# syntax=dhi.io/build:2-alpine3.23@sha256:%064d\nimage: ghcr.io/acme/imgs/%s\nvariant: runtime\n' 0 "$d"; printf '%s\n' "$@"; } > "$SB/image/$d/image.yaml"
}
GOOD=('accounts:' '  run-as: nonroot' '  users:' '    - name: nonroot' '      uid: 65532' '      gid: 65532' '  groups:' '    - name: nonroot' '      gid: 65532' '      members: [nonroot]')

# 1: the catalogue's shape passes, counted
fresh; def app "${GOOD[@]}"; def db "${GOOD[@]}"
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "the nonroot 65532 shape passes" 0 "$rc" "$out" "2 definition(s)"

# 2: no accounts block at all fails naming the definition
fresh; def app
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "no accounts block fails naming the definition" 1 "$rc" "$out" "image/app/image.yaml" "Req 1.4"

# 3: running as root fails
fresh; def app 'accounts:' '  run-as: root' '  users:' '    - name: root' '      uid: 0' '      gid: 0'
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "run-as root fails" 1 "$rc" "$out" "image/app/image.yaml" "root"

# 4: a non-root account with the wrong uid fails naming the uid
fresh; def app 'accounts:' '  run-as: app' '  users:' '    - name: app' '      uid: 1000' '      gid: 1000'
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "uid 1000 fails naming it" 1 "$rc" "$out" "1000" "65532"

# 5: run-as names a user the users list does not define
fresh; def app 'accounts:' '  run-as: nonroot' '  users:' '    - name: other' '      uid: 65532' '      gid: 65532'
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "run-as naming an undefined user fails" 1 "$rc" "$out" "nonroot"

# 6: every definition is checked, each failure named; a dev variant is not exempt
fresh; def app "${GOOD[@]}"; def two; def three 'accounts:' '  run-as: root'
out=$("$LINT" "$SB" 2>&1); rc=$?
expect "every failing definition is named" 1 "$rc" "$out" "image/two/image.yaml" "image/three/image.yaml" "2 violation(s)"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all lint-accounts tests passed"
