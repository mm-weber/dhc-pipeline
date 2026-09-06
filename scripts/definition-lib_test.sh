#!/usr/bin/env bash
# Tests for scripts/definition-lib.sh — the directory-to-published-name mapping.
#
# Worth its own suite because four readers share it and the failure mode is
# silent: a spelling this misses resolves to the directory name, which Trivy
# never produces, so the statement suppresses nothing and the compile reports
# clean. Each caller's own suite covers what it does with the answer; this covers
# the answer.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/definition-lib.sh
. "$HERE/definition-lib.sh"
FAILURES=0
SB=""

check() { # name, expected, actual
  if [ "$2" = "$3" ]; then echo "ok   $1"
  else echo "FAIL $1: expected '$2', got '$3'"; FAILURES=$((FAILURES+1)); fi
}
fresh() { SB=$(mktemp -d); }
def() { # $1 = directory under image/, $2.. = image.yaml lines
  mkdir -p "$SB/image/$1"
  local d="$1"; shift
  printf '%s\n' "$@" > "$SB/image/$d/image.yaml"
}

# --- published_repository ---------------------------------------------------

# 1: the shape every definition in the catalogue actually uses
fresh
def app 'image: ghcr.io/mm-weber/dhc/app' 'tags:' '  - 1.0.0-alpine3.23'
check "bare publish name" "ghcr.io/mm-weber/dhc/app" "$(published_repository "$SB/image/app/image.yaml")"

# 2: a trailing comment is annotation, not part of the name. Silent truncation
#    here would compare against a repository carrying '# note' and never match.
fresh
def app 'image: ghcr.io/mm-weber/dhc/app  # published private'
check "trailing comment stripped" "ghcr.io/mm-weber/dhc/app" "$(published_repository "$SB/image/app/image.yaml")"

# 3: quotes are YAML syntax, and Trivy's repository_url carries neither
fresh
def app "image: 'ghcr.io/mm-weber/dhc/app'"
check "single quotes stripped" "ghcr.io/mm-weber/dhc/app" "$(published_repository "$SB/image/app/image.yaml")"
fresh
def app 'image: "ghcr.io/mm-weber/dhc/app"'
check "double quotes stripped" "ghcr.io/mm-weber/dhc/app" "$(published_repository "$SB/image/app/image.yaml")"

# 4: `image:` is top-level. An indented one belongs to a build stage or a
#    container spec and is a different image entirely — matching it would resolve
#    a definition to something it merely consumes.
fresh
def app 'contents:' '  image: ghcr.io/other/thing' 'image: ghcr.io/mm-weber/dhc/app'
check "indented image: is not the publish name" "ghcr.io/mm-weber/dhc/app" "$(published_repository "$SB/image/app/image.yaml")"

# 5: no `image:` at all yields empty, so a caller can tell "nothing declared"
#    from a name. Every caller branches on that.
fresh
def app 'name: App 1.x'
check "no image: yields empty" "" "$(published_repository "$SB/image/app/image.yaml")"

# --- definitions_publishing ------------------------------------------------

# 6: one definition, one repository — the pre-variant case
fresh
def app 'image: ghcr.io/mm-weber/dhc/app'
def other 'image: ghcr.io/mm-weber/dhc/other'
check "resolves to the one definition" "image/app/image.yaml" "$(definitions_publishing "$SB" app)"

# 7: the runtime/variant pair. Both publish one repository, so the name resolves
#    to both and the tag is what separates them (Req 6.30).
fresh
def valkey 'image: ghcr.io/mm-weber/dhc/valkey'
def valkey-compat 'image: ghcr.io/mm-weber/dhc/valkey'
check "a variant pair resolves to both" \
  "image/valkey-compat/image.yaml
image/valkey/image.yaml" "$(definitions_publishing "$SB" valkey)"

# 8: and the variant's DIRECTORY name resolves to nothing. It names a real
#    directory, which is why keying on directories accepted it, and Trivy never
#    produces it — the statement would pass review and suppress nothing.
fresh
def valkey 'image: ghcr.io/mm-weber/dhc/valkey'
def valkey-compat 'image: ghcr.io/mm-weber/dhc/valkey'
check "a directory name is not a published name" "" "$(definitions_publishing "$SB" valkey-compat)"

# 9: keyed on the repository, not on a `-<variant>` suffix — the three
#    cert-manager definitions are one monorepo and three repositories, so they
#    are correctly not a set.
fresh
def cert-manager-controller 'image: ghcr.io/mm-weber/dhc/cert-manager-controller'
def cert-manager-webhook 'image: ghcr.io/mm-weber/dhc/cert-manager-webhook'
check "monorepo siblings are not a set" \
  "image/cert-manager-controller/image.yaml" "$(definitions_publishing "$SB" cert-manager-controller)"

# 10: a repository that ends in the name but under a different registry path is
#     still a match — the purl name is the last segment, which is all Trivy has.
fresh
def app 'image: ghcr.io/somebody/else/app'
check "match is on the last segment" "image/app/image.yaml" "$(definitions_publishing "$SB" app)"

# 11: no image/ tree is not an error. lint-vex-product.sh turns the empty result
#     into its Req 6.17 violation; a non-zero exit here would abort the caller
#     under `set -e` before it could say which statement was wrong.
fresh
definitions_publishing "$SB" app >/dev/null; rc=$?
check "no image tree exits 0" "0" "$rc"
check "no image tree yields nothing" "" "$(definitions_publishing "$SB" app)"

# 12: nor is a name nothing publishes, for the same reason — and this is the
#     path every Req 6.17 violation arrives through.
fresh
def app 'image: ghcr.io/mm-weber/dhc/app'
definitions_publishing "$SB" nope >/dev/null; rc=$?
check "unknown name exits 0" "0" "$rc"

# --- the cross-origin checksum helpers (Req 3.8 to 3.10; task 11.3) ----------

A=$(printf 'a%.0s' $(seq 64)); B=$(printf 'b%.0s' $(seq 64))
check "shas_agree: three equal digests agree" "0" "$(shas_agree x "pinned=$A" "served=$A" "statement=$A" >/dev/null; echo $?)"
check "shas_agree: a differing value is named" "grafana arm64: pinned ${A:0:12}…, served ${B:0:12}… do not agree" "$(shas_agree "grafana arm64" "pinned=$A" "served=$B"; true)"
check "shas_agree: a missing value is named as none" "x: pinned ${A:0:12}…, statement none do not agree" "$(shas_agree x "pinned=$A" "statement="; true)"
check "shas_agree: a non-digest is not a match" "1" "$(shas_agree x "pinned=$A" "served=oops" >/dev/null; echo $?)"
stmt='{"packages":[{"os":"linux","arch":"amd64","url":"https://dl.grafana.com/grafana/release/13.1.5/grafana_13.1.5_1_linux_amd64.tar.gz","sha256":"'"$A"'","links":[{"rel":"self"}]},{"arch":"arm64","url":"https://dl.grafana.com/grafana/release/13.1.5/grafana_13.1.5_1_linux_arm64.tar.gz","sha256":"'"$B"'"}]}'
check "versions_api_sha: the linux amd64 tarball's sha256" "$A" "$(versions_api_sha "$stmt" amd64)"
check "versions_api_sha: arm64" "$B" "$(versions_api_sha "$stmt" arm64)"
check "versions_api_sha: no such package yields empty" "" "$(versions_api_sha "$stmt" riscv64)"
check "versions_api_sha: not JSON yields empty" "" "$(versions_api_sha "<html>" amd64)"
check "version_statement_url: grafana's known origin" "https://grafana.com/api/grafana/versions/13.1.5" "$(version_statement_url dl.grafana.com 13.1.5)"
check "version_statement_url: unknown host, no override: empty" "" "$(version_statement_url dl.example.com 1.0)"
check "version_statement_url: the override serves any host" "file:///tmp/api/1.0" "$(DHC_VERSIONS_API=file:///tmp/api version_statement_url dl.example.com 1.0)"

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES test(s) failed"; exit 1; fi
echo "all tests passed"
