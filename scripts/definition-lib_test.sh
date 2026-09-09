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

# --- the active set (Req 1.13, 1.19; task 14.1) ------------------------------
# catalogue-policy.yaml's `active_set:` names each definition the catalogue
# builds, tracks, tests and publishes; this is its one reader. Malformed input
# is a refusal by name rather than an empty answer, because an empty matrix
# looks exactly like a catalogue with nothing to do.
policy() { printf '%s\n' "$@" > "$SB/catalogue-policy.yaml"; }

# 13: the declared list, in declared order, one per line
fresh
def app 'image: ghcr.io/acme/imgs/app'
def db 'image: ghcr.io/acme/imgs/db'
def db-compat 'image: ghcr.io/acme/imgs/db'
policy 'release:' '  public: true' 'active_set:' '  - db' '  - app' '  - db-compat'
check "active_definitions: the declared names in declared order" "$(printf 'db\napp\ndb-compat')" "$(active_definitions "$SB")"
check "active_definitions: exit 0 on a well-formed set" "0" "$(active_definitions "$SB" >/dev/null 2>&1; echo $?)"

# 14: a definition directory the set does not name is simply not active;
#     the reader neither adds it nor complains (deactivation is the switch)
fresh
def app 'image: ghcr.io/acme/imgs/app'
def old 'image: ghcr.io/acme/imgs/old'
policy 'active_set:' '  - app'
check "active_definitions: an unlisted directory is inactive, not an error" "app" "$(active_definitions "$SB" 2>/dev/null)"

# 15: an entry with no image/<name>/image.yaml is refused naming the entry
#     (Req 1.19), not passed on as a matrix row that fails somewhere else
fresh
def app 'image: ghcr.io/acme/imgs/app'
policy 'active_set:' '  - app' '  - typo'
out=$(active_definitions "$SB" 2>&1); rc=$?
check "active_definitions: a name with no definition directory is refused (exit 2)" "2" "$rc"
case "$out" in *"typo"*"image/typo/image.yaml"*) check "active_definitions: the refusal names the entry and the missing file" "ok" "ok" ;;
  *) check "active_definitions: the refusal names the entry and the missing file" "names typo and image/typo/image.yaml" "$out" ;; esac

# 16: a duplicate entry is refused, so a matrix never builds one twice
fresh
def app 'image: ghcr.io/acme/imgs/app'
policy 'active_set:' '  - app' '  - app'
out=$(active_definitions "$SB" 2>&1); rc=$?
check "active_definitions: a duplicate entry is refused (exit 2)" "2" "$rc"
case "$out" in *"app"*"twice"*|*"app"*"duplicate"*) check "active_definitions: the refusal names the duplicate" "ok" "ok" ;;
  *) check "active_definitions: the refusal names the duplicate" "names app as duplicate" "$out" ;; esac

# 17: no active_set, or an empty one, is a refusal: Req 1.14 makes the set the
#     SOLE source of candidates, so "nothing declared" must not read as
#     "nothing to build" (the schedule branch would silently rebuild nothing,
#     the review 1.10 failure shape again)
fresh
def app 'image: ghcr.io/acme/imgs/app'
policy 'release:' '  public: true'
out=$(active_definitions "$SB" 2>&1); rc=$?
check "active_definitions: a policy file without active_set is refused (exit 2)" "2" "$rc"
case "$out" in *active_set*) check "active_definitions: the refusal names active_set" "ok" "ok" ;;
  *) check "active_definitions: the refusal names active_set" "names active_set" "$out" ;; esac
policy 'active_set: []'
check "active_definitions: an empty active_set is refused (exit 2)" "2" "$(active_definitions "$SB" >/dev/null 2>&1; echo $?)"
policy 'active_set: grafana'
check "active_definitions: a scalar active_set is refused (exit 2)" "2" "$(active_definitions "$SB" >/dev/null 2>&1; echo $?)"

# 18: no policy file at all is a refusal too, by path
fresh
def app 'image: ghcr.io/acme/imgs/app'
out=$(active_definitions "$SB" 2>&1); rc=$?
check "active_definitions: no catalogue-policy.yaml is refused (exit 2)" "2" "$rc"
case "$out" in *catalogue-policy.yaml*) check "active_definitions: the refusal names the policy file" "ok" "ok" ;;
  *) check "active_definitions: the refusal names the policy file" "names catalogue-policy.yaml" "$out" ;; esac

# --- the mapping the matrices need (Req 1.14, 1.18, 5.2; task 14.2) ----------

# 19: source_repository: the GitHub owner/repo of the first git+ source, the
#     name Renovate groups bumps under (Req 3.3); a tarball has none
fresh
def cm 'image: ghcr.io/acme/imgs/cm' 'contents:' '  builds:' '    - contents:' '        files:' '          - url: git+https://github.com/cert-manager/cert-manager.git#v1.21.1' '            checksum: abc'
def app 'image: ghcr.io/acme/imgs/app' '          - url: "git+https://github.com/acme/app#v0.1.0"'
def tarball 'image: ghcr.io/acme/imgs/tarball' '          - url: https://dl.example.com/release/1.0/app_linux_amd64.tar.gz'
check "source_repository: .git suffix and ref stripped" "cert-manager/cert-manager" "$(source_repository "$SB/image/cm/image.yaml")"
check "source_repository: quoted url without .git" "acme/app" "$(source_repository "$SB/image/app/image.yaml")"
check "source_repository: a tarball has no source repository" "" "$(source_repository "$SB/image/tarball/image.yaml")"

# 20: chart_deploys: the definitions a chart's chart.yaml declares it deploys,
#     in declared order; a chart.yaml without the list yields nothing
fresh
mkdir -p "$SB/chart/cm" "$SB/chart/bare"
printf 'upstream:\n  name: cert-manager\n  repository: https://charts.example\n  version: v1\ndeploys:\n  - cm-controller\n  - cm-webhook\n' > "$SB/chart/cm/chart.yaml"
printf 'upstream:\n  name: x\n  repository: https://charts.example\n  version: v1\n' > "$SB/chart/bare/chart.yaml"
check "chart_deploys: the declared list in order" "$(printf 'cm-controller\ncm-webhook')" "$(chart_deploys "$SB/chart/cm/chart.yaml")"
check "chart_deploys: no deploys list yields nothing" "" "$(chart_deploys "$SB/chart/bare/chart.yaml")"

# 21: active_components: each chart directory whose deploys list meets the
#     active set, as "<chart>\t<active definitions it deploys>"; a chart
#     deploying only inactive definitions is not a component today, and one
#     deploying a mix keeps only its active definitions
fresh
def app 'image: ghcr.io/acme/imgs/app'
def cm-a 'image: ghcr.io/acme/imgs/cm-a'
def cm-b 'image: ghcr.io/acme/imgs/cm-b'
def old 'image: ghcr.io/acme/imgs/old'
mkdir -p "$SB/chart/app" "$SB/chart/cm" "$SB/chart/old"
printf 'deploys: [app]\n' > "$SB/chart/app/chart.yaml"
printf 'deploys: [cm-b, cm-a, old]\n' > "$SB/chart/cm/chart.yaml"
printf 'deploys: [old]\n' > "$SB/chart/old/chart.yaml"
policy 'active_set: [app, cm-a, cm-b]'
check "active_components: charts meeting the active set, with their active definitions" "$(printf 'app\tapp\ncm\tcm-b cm-a')" "$(active_components "$SB")"
check "active_components: exit 0" "0" "$(active_components "$SB" >/dev/null 2>&1; echo $?)"
policy 'active_set: [app, typo]'
check "active_components: a malformed active set is the reader's refusal (exit 2)" "2" "$(active_components "$SB" >/dev/null 2>&1; echo $?)"

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES test(s) failed"; exit 1; fi
echo "all tests passed"
