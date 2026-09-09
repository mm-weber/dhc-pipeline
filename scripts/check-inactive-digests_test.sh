#!/usr/bin/env bash
# Tests for scripts/check-inactive-digests.sh: the detective half of Req 1.15
# (review D7). Fixtures: a policy file with an active set, definitions with
# their tags, today's enumeration.tsv, and the previous status issue body
# whose fenced JSON block is the baseline.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-inactive-digests.sh"
FAILURES=0
D1=sha256:1111111111111111111111111111111111111111111111111111111111111111
D2=sha256:2222222222222222222222222222222222222222222222222222222222222222
D3=sha256:3333333333333333333333333333333333333333333333333333333333333333
D9=sha256:9999999999999999999999999999999999999999999999999999999999999999

definition() { # name published-name tags...
  local name="$1" pub="$2"; shift 2
  mkdir -p "$SB/image/$name"
  { printf 'image: ghcr.io/x/dhc/%s\ntags:\n' "$pub"; printf '  - %s\n' "$@"; } > "$SB/image/$name/image.yaml"
}
policy() { # active names...
  { printf 'active_set:\n'; printf '  - %s\n' "$@"; } > "$SB/catalogue-policy.yaml"
}
row() { # repo tag digest -> one enumeration row (index digest, one platform)
  printf '%s\t%s\t%s\tlinux/amd64\t%s\tsupported\n' "ghcr.io/x/dhc/$1" "$2" "$3" "$3" >> "$SB/enumeration.tsv"
}
baseline() { # json -> previous.md with the fenced block the status tool writes
  printf '<!-- catalogue-status -->\n## Catalogue status\n\ntext\n\n```json\n%s\n```\n' "$1" > "$SB/previous.md"
}
repo_json() { # published-name "tag digest" pairs... -> one repositories[] entry, one digest per pair
  local pub="$1"; shift
  local entries=""
  for pair in "$@"; do entries="${entries:+$entries,}{\"digest\":\"${pair#* }\",\"tags\":[\"${pair% *}\"]}"; done
  printf '{"repository":"ghcr.io/x/dhc/%s","digests":[%s]}' "$pub" "$entries"
}
fresh() {
  SB=$(mktemp -d)
  definition grafana grafana 13-alpine3.23 13.1.5-alpine3.23
  definition valkey valkey 9-alpine3.23
  definition valkey-compat valkey 9-alpine3.23-compat
  : > "$SB/enumeration.tsv"
  row grafana 13-alpine3.23 "$D1"; row grafana 13.1.5-alpine3.23 "$D1"
  row valkey 9-alpine3.23 "$D2"; row valkey 9-alpine3.23-compat "$D3"
  baseline "{\"repositories\":[$(repo_json grafana "13-alpine3.23 $D1" "13.1.5-alpine3.23 $D1"),$(repo_json valkey "9-alpine3.23 $D2" "9-alpine3.23-compat $D3")]}"
}
run_case() { # name expected_exit [substring]
  local name="$1" expected="$2" substr="${3:-}" out rc
  out=$("$CHECK" "$SB" "$SB/enumeration.tsv" "$SB/previous.md" "$SB/out.json" 2>&1); rc=$?
  if [ "$rc" -ne "$expected" ]; then echo "FAIL $name: exit $rc, expected $expected"; echo "$out" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); return; fi
  if [ -n "$substr" ] && ! grep -qF "$substr" <<<"$out"; then echo "FAIL $name: output missing '$substr'"; echo "$out" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); return; fi
  echo "ok   $name"
}
out_is() { # name jq-filter expected
  local got; got=$(jq -r "$2" "$SB/out.json")
  [ "$got" = "$3" ] && echo "ok   $1" || { echo "FAIL $1: out.json $2 = $got, expected $3"; FAILURES=$((FAILURES+1)); }
}

# 1: every definition active: nothing to assert, said so
fresh; policy grafana valkey valkey-compat
run_case "all active: nothing to assert, named" 0 "check-inactive-digests: 3 active, 0 inactive; nothing to assert today (Req 1.15)"
out_is "all active: the record says so" '.inactive | length' 0

# 2: an inactive definition whose tags reference the same digests as the
#    last status passes, and the record carries what was asserted
fresh; policy grafana valkey
run_case "inactive and unchanged: passes, counting the tags held" 0 "check-inactive-digests: 1 tag(s) of 1 inactive definition(s) (valkey-compat) unchanged since the last status (Req 1.15)"
out_is "unchanged: no gains recorded" '.gains | length' 0
out_is "unchanged: the tags asserted" '.asserted' 1

# 3: a tag of an inactive definition moved to a new digest: a gain, named
fresh; policy grafana valkey
sed -i "s|9-alpine3.23-compat\t$D3\tlinux/amd64\t$D3|9-alpine3.23-compat\t$D9\tlinux/amd64\t$D9|" "$SB/enumeration.tsv"
run_case "inactive tag moved to a new digest: fails by name" 1 "::error::check-inactive-digests: inactive definition valkey-compat gained a digest: 9-alpine3.23-compat now references sha256:99999999999 (was sha256:33333333333 at the last status); deactivation pushes no digest and applies no tag (Req 1.15)"
out_is "moved: the gain is recorded with both digests" '.gains[0] | "\(.definition) \(.tag) \(.digest) \(.previous)"' "valkey-compat 9-alpine3.23-compat $D9 $D3"

# 4: a tag the last status did not know under an inactive definition: a gain
fresh; policy grafana valkey
row valkey 9.1-alpine3.23-compat "$D3"
sed -i 's|^  - 9-alpine3.23-compat$|  - 9-alpine3.23-compat\n  - 9.1-alpine3.23-compat|' "$SB/image/valkey-compat/image.yaml"
run_case "a new tag under an inactive definition: fails by name" 1 "inactive definition valkey-compat gained a tag: 9.1-alpine3.23-compat now references sha256:33333333333 (not published at the last status)"

# 5: the shared repository: the active valkey moving is not the inactive
#    valkey-compat's gain (the comparison is per tag, not per repository)
fresh; policy grafana valkey
sed -i "s|9-alpine3.23\t$D2\tlinux/amd64\t$D2|9-alpine3.23\t$D9\tlinux/amd64\t$D9|" "$SB/enumeration.tsv"
run_case "an active sibling in the same repository may move" 0 "unchanged since the last status"

# 6: an inactive definition's tag with no repository entry at the last status
fresh; policy grafana valkey
baseline "{\"repositories\":[$(repo_json grafana "13-alpine3.23 $D1")]}"
run_case "no baseline entry for the repository at all: the tag counts as gained" 1 "gained a tag: 9-alpine3.23-compat now references sha256:33333333333 (not published at the last status)"

# 7: no previous status: nothing can be asserted, said so, not a failure
fresh; policy grafana valkey
: > "$SB/previous.md"
run_case "no previous status: a warning naming the inactive definitions, exit 0" 0 "::warning::check-inactive-digests: no previous status to compare against; nothing asserted today for valkey-compat (Req 1.15)"
out_is "no baseline: recorded as not asserted" '.asserted' 0

# 8: a malformed active set is the reader's refusal, passed through
fresh; printf 'active_set: []\n' > "$SB/catalogue-policy.yaml"
run_case "a malformed active set refuses with the reader's exit code" 2 "active_set must be a non-empty list"

# 9: an inactive definition whose tags are absent today (retired) holds nothing and gains nothing
fresh; policy grafana valkey
sed -i "/9-alpine3.23-compat/d" "$SB/enumeration.tsv"
run_case "an inactive definition with no tag published today: nothing gained" 0 "0 tag(s) of 1 inactive definition(s) (valkey-compat) unchanged"

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES test(s) failed"; exit 1; fi
echo "all check-inactive-digests tests passed"
