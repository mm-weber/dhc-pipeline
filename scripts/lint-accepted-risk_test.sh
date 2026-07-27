#!/usr/bin/env bash
# Tests for scripts/lint-accepted-risk.sh — self-contained sandbox, no fixture files.
#
# The lint guards the one file in the repo whose whole purpose is to make the
# scan gate stay quiet (Req 6.11, 6.12). Everything it rejects is something that
# would otherwise turn a reviewed, time-boxed risk decision back into a silent
# suppression.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LINT="$HERE/lint-accepted-risk.sh"
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

refute_case() { # name, expected_exit, absent_substring
  local name="$1" expected="$2" substr="$3"
  local out rc
  out=$("$LINT" "$SB" 2>&1); rc=$?
  if [ "$rc" -ne "$expected" ]; then
    echo "FAIL $name: exit $rc, expected $expected"; echo "$out" | sed 's/^/    /'
    FAILURES=$((FAILURES+1)); return
  fi
  if grep -qF "$substr" <<<"$out"; then
    echo "FAIL $name: output should not contain '$substr'"; echo "$out" | sed 's/^/    /'
    FAILURES=$((FAILURES+1)); return
  fi
  echo "ok   $name"
}

fresh() {
  SB=$(mktemp -d)
  mkdir -p "$SB/image/grafana" "$SB/triage/accepted-risk"
  printf 'image: ghcr.io/mm-weber/dhc/grafana\n' > "$SB/image/grafana/image.yaml"
}

# Dates are computed relative to now: the rules under test are about *duration*,
# so a hardcoded date would silently start testing something else next quarter.
OK_DATE=$(date -u -d "+60 days" +%F)
SOON_DATE=$(date -u -d "+9 days" +%F)
PAST_DATE=$(date -u -d "-1 day" +%F)
FAR_DATE=$(date -u -d "+120 days" +%F)
EDGE_DATE=$(date -u -d "+89 days" +%F)

# A complete, valid entry. Cases below drop or corrupt exactly one field, so a
# failure names the rule under test and nothing else.
write_entry() { # $1 = target file, remaining = raw yaml body lines
  local f="$1"; shift
  { echo "vulnerabilities:"; printf '%s\n' "$@"; } > "$f"
}
valid_body() { # $1 = expiry
  cat <<YAML
  - id: CVE-2026-33186
    purls: ["pkg:golang/google.golang.org/grpc"]
    treatment: accept
    owner: mm-weber
    ref: "triage/LOG.md#2026-07-27-grpc"
    blocked: "no upstream release pins a fixed grpc; the pipeline sandbox has no egress"
    statement: "accept: grpc is reachable and no fix exists upstream"
    expired_at: $1
YAML
}

# 1: a complete entry passes
fresh
{ echo "vulnerabilities:"; valid_body "$OK_DATE"; } > "$SB/triage/accepted-risk/grafana.yaml"
run_case "complete entry passes" 0

# 2: no accepted-risk files at all is fine — nothing is being suppressed
fresh
run_case "empty lane passes" 0

# 3: an empty vulnerabilities list is fine
fresh
printf 'vulnerabilities: []\n' > "$SB/triage/accepted-risk/grafana.yaml"
run_case "empty list passes" 0

# --- Req 6.11: required fields ---------------------------------------------

for field in treatment owner ref blocked statement expired_at; do
  fresh
  { echo "vulnerabilities:"; valid_body "$OK_DATE" | grep -v "^    ${field}:"; } \
    > "$SB/triage/accepted-risk/grafana.yaml"
  run_case "missing '${field}' fails" 1 "$field"
done

# 4: a missing id is nameless — the entry cannot even be discussed
fresh
{ echo "vulnerabilities:"; valid_body "$OK_DATE" | sed 's/^  - id: .*/  - purls: ["pkg:golang\/x"]/'; } \
  > "$SB/triage/accepted-risk/grafana.yaml"
run_case "missing 'id' fails" 1 "id"

# 5: violations name the file and cite the requirement
fresh
{ echo "vulnerabilities:"; valid_body "$OK_DATE" | grep -v "^    owner:"; } \
  > "$SB/triage/accepted-risk/grafana.yaml"
run_case "violation names the file" 1 "triage/accepted-risk/grafana.yaml"
run_case "violation names the entry" 1 "CVE-2026-33186"
run_case "violation cites the requirement" 1 "Req 6.11"

# --- Req 6.11: treatment vocabulary ----------------------------------------

# 6: only accept|transfer. 'mitigate' is not an exception — it is a fix PR.
fresh
{ echo "vulnerabilities:"; valid_body "$OK_DATE" | sed 's/treatment: accept/treatment: mitigate/'; } \
  > "$SB/triage/accepted-risk/grafana.yaml"
run_case "unknown treatment fails" 1 "mitigate"

# 7: transfer is an acceptance with an external owner — it needs the tracker
fresh
{ echo "vulnerabilities:"; valid_body "$OK_DATE" | sed 's/treatment: accept/treatment: transfer/'; } \
  > "$SB/triage/accepted-risk/grafana.yaml"
run_case "transfer without issue fails" 1 "issue"

# 8: transfer with an issue passes
fresh
{ echo "vulnerabilities:"; valid_body "$OK_DATE" \
    | sed 's/treatment: accept/treatment: transfer/;s|^    owner:|    issue: 28\n    owner:|'; } \
  > "$SB/triage/accepted-risk/grafana.yaml"
run_case "transfer with issue passes" 0

# --- Req 6.11: the expiry ceiling ------------------------------------------

# 9: an expiry already in the past is a decision nobody re-made
fresh
{ echo "vulnerabilities:"; valid_body "$PAST_DATE"; } > "$SB/triage/accepted-risk/grafana.yaml"
run_case "past expiry fails" 1 "$PAST_DATE"
run_case "past expiry says so" 1 "past"

# 10: more than 90 days ahead is an indefinite acceptance wearing a date
fresh
{ echo "vulnerabilities:"; valid_body "$FAR_DATE"; } > "$SB/triage/accepted-risk/grafana.yaml"
run_case "expiry beyond 90 days fails" 1 "90 days"

# 11: the boundary is usable, not just theoretical
fresh
{ echo "vulnerabilities:"; valid_body "$EDGE_DATE"; } > "$SB/triage/accepted-risk/grafana.yaml"
run_case "expiry at 89 days passes" 0

# 12: a non-date is not an expiry
fresh
{ echo "vulnerabilities:"; valid_body "when-upstream-fixes-it"; } > "$SB/triage/accepted-risk/grafana.yaml"
run_case "non-date expiry fails" 1 "YYYY-MM-DD"

# 13: an expiry inside the notice window warns but does not fail — the PR that
# happens to run then is not the PR that should be forced to re-decide
fresh
{ echo "vulnerabilities:"; valid_body "$SOON_DATE"; } > "$SB/triage/accepted-risk/grafana.yaml"
run_case "near expiry warns, passes" 0 "expires in"
run_case "near-expiry warning names the owner" 0 "mm-weber"

# 14: a comfortable expiry produces no warning noise
fresh
{ echo "vulnerabilities:"; valid_body "$OK_DATE"; } > "$SB/triage/accepted-risk/grafana.yaml"
refute_case "distant expiry does not warn" 0 "expires in"

# --- Req 6.11: the filename is the scope -----------------------------------

# 15: the filename names the image the exceptions apply to; a typo would
# silently suppress nothing, or worse, nothing anyone reviewed
fresh
{ echo "vulnerabilities:"; valid_body "$OK_DATE"; } > "$SB/triage/accepted-risk/graphana.yaml"
run_case "filename without a definition fails" 1 "image/graphana"

# 16: non-yaml files in the lane are documentation, not exceptions
fresh
printf '# how to author an exception\n' > "$SB/triage/accepted-risk/README.md"
run_case "README in the lane ignored" 0

# --- Req 6.12: no suppression outside the lane -----------------------------

# 17: a root .trivyignore is Trivy's default pickup path — an unreviewed
# suppression channel that bypasses every rule above
fresh
printf 'CVE-2026-33186\n' > "$SB/.trivyignore"
run_case "root .trivyignore fails" 1 "Req 6.12"
run_case "root .trivyignore is named" 1 ".trivyignore"

# 18: the yaml form, anywhere in the tree
fresh
mkdir -p "$SB/image/grafana"
printf 'vulnerabilities: []\n' > "$SB/image/grafana/.trivyignore.yaml"
run_case "nested .trivyignore.yaml fails" 1 "Req 6.12"

# 19: the lane's own files are obviously exempt
fresh
{ echo "vulnerabilities:"; valid_body "$OK_DATE"; } > "$SB/triage/accepted-risk/grafana.yaml"
refute_case "lane files are not stray ignores" 0 "Req 6.12"

# 20: vendored trees are not ours to police
fresh
mkdir -p "$SB/node_modules/trivy-thing"
printf 'CVE-1\n' > "$SB/node_modules/trivy-thing/.trivyignore"
run_case "vendored .trivyignore ignored" 0

# --- multiple entries -------------------------------------------------------

# 21: one bad entry among good ones is found and named
fresh
{ echo "vulnerabilities:"; valid_body "$OK_DATE"
  valid_body "$OK_DATE" | sed 's/CVE-2026-33186/CVE-2026-99999/;s/^    owner: .*//'; } \
  > "$SB/triage/accepted-risk/grafana.yaml"
run_case "bad entry among good ones is caught" 1 "CVE-2026-99999"

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES test(s) failed"; exit 1; fi
echo "all tests passed"
