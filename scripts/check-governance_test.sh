#!/usr/bin/env bash
# Tests for scripts/check-governance.sh: the daily governance invariants
# (task 13.2). The live GitHub API is a localhost http.server over a fixture
# tree: `repos/<o>/<r>/rulesets/index.html` is the list, each ruleset detail a
# file beside it, `private-vulnerability-reporting` a file. Every read the
# script makes is anonymous, so the fixture needs no auth either.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-governance.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

SB=$(mktemp -d)
API="$SB/api/repos/acme/cat"
mkdir -p "$API/rulesets" "$SB/committed"
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
python3 -m http.server --bind 127.0.0.1 "$PORT" --directory "$SB/api" >"$SB/server.log" 2>&1 &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null' EXIT
for _ in $(seq 50); do curl -fsS "http://127.0.0.1:$PORT/" >/dev/null 2>&1 && break; sleep 0.1; done
export DHC_GITHUB_API="http://127.0.0.1:$PORT"

reporting() { printf '{"enabled": %s}\n' "$1" > "$API/private-vulnerability-reporting"; }
ruleset() { # path id name enforcement target reviews "ctx1,ctx2" live|committed [shuffle]
  python3 - "$@" <<'PY'
import json, sys
path, rid, name, enforcement, target, reviews, ctxs, kind = sys.argv[1:9]
shuffle = len(sys.argv) > 9 and sys.argv[9] == "shuffle"
checks = [{"context": c, "integration_id": 15368} for c in ctxs.split(",") if c]
rules = [
  {"type": "non_fast_forward"},
  {"type": "pull_request", "parameters": {"required_approving_review_count": int(reviews),
    "dismiss_stale_reviews_on_push": False, "required_reviewers": [], "require_code_owner_review": False,
    "require_last_push_approval": False, "required_review_thread_resolution": True,
    "require_extra_approval_for_unattributed_changes": True, "allowed_merge_methods": ["squash"]}},
  {"type": "required_status_checks", "parameters": {"strict_required_status_checks_policy": True,
    "do_not_enforce_on_create": False, "required_status_checks": checks}},
  {"type": "deletion"},
]
if shuffle:
    rules = rules[::-1]
    for r in rules:
        p = r.get("parameters", {})
        if "required_status_checks" in p:
            p["required_status_checks"] = p["required_status_checks"][::-1]
doc = {"id": int(rid), "name": name, "target": target, "source_type": "Repository", "source": "acme/cat",
       "enforcement": enforcement, "conditions": {"ref_name": {"exclude": [], "include": ["~DEFAULT_BRANCH"]}},
       "rules": rules}
if kind == "live":
    doc.update({"node_id": "RRS_" + rid, "created_at": "2026-08-11T13:05:06.876-07:00",
                "updated_at": "2026-08-21T07:13:40.970-07:00",
                "_links": {"self": {"href": "https://api.github.com/repos/acme/cat/rulesets/" + rid},
                           "html": {"href": "https://github.com/acme/cat/rules/" + rid}}})
else:
    doc["bypass_actors"] = [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}]
json.dump(doc, open(path, "w"), indent=1)
PY
}
live_list() { # the list endpoint carries no rules or conditions, only the summary fields
  python3 - "$API/rulesets" <<'PY'
import json, os, sys
d = sys.argv[1]; out = []
for f in sorted(os.listdir(d)):
    if f == "index.html": continue
    r = json.load(open(os.path.join(d, f)))
    out.append({k: r[k] for k in ("id", "name", "target", "enforcement", "source", "source_type", "node_id", "created_at", "updated_at", "_links") if k in r})
json.dump(out, open(os.path.join(d, "index.html"), "w"))
PY
}
reset() { rm -rf "$SB/committed" "$API/rulesets"; mkdir -p "$SB/committed" "$API/rulesets"; }
run() { OUT=$("$CHECK" "$SB/committed" acme/cat "$SB/out.json" 2>&1); RC=$?; }
expect_in() { grep -qF -- "$2" <<<"$OUT" && pass "$1" || fail "$1: expected '$2' in output" "$OUT"; }
expect_not_in() { grep -qF -- "$2" <<<"$OUT" && fail "$1: did NOT expect '$2' in output" "$OUT" || pass "$1"; }

# 1: identical modulo server-assigned fields, bypass_actors, a different id, and list order
reset; reporting true
ruleset "$SB/committed/main_sec.json" 1 main_sec active branch 1 "build gate,e2e gate" committed
ruleset "$API/rulesets/20716271" 20716271 main_sec active branch 1 "build gate,e2e gate" live shuffle
live_list; run
[ "$RC" -eq 0 ] && pass "identical: exit 0" || fail "identical: rc=$RC" "$OUT"
expect_in "identical: summary counts one compared, no difference" "1 committed ruleset(s) compared, 0 difference(s), 0 live-only"
expect_in "identical: reporting reported enabled" "private vulnerability reporting enabled"
jq -e '.reporting.enabled == true and (.rulesets | length) == 1 and .rulesets[0].name == "main_sec" and .rulesets[0].ok == true and (.live_only | length) == 0' "$SB/out.json" >/dev/null \
  && pass "identical: record written" || fail "identical: record" "$(cat "$SB/out.json")"

# 2: a rule parameter differs live (the one-review rule dropped to zero)
reset; reporting true
ruleset "$SB/committed/main_sec.json" 1 main_sec active branch 1 "build gate,e2e gate" committed
ruleset "$API/rulesets/20716271" 20716271 main_sec active branch 0 "build gate,e2e gate" live
live_list; run
[ "$RC" -ne 0 ] && pass "rule differs: exit non-zero" || fail "rule differs: rc=0" "$OUT"
expect_in "rule differs: names the ruleset and the field" "main_sec: rules.pull_request.required_approving_review_count"
expect_in "rule differs: shows both values" "committed 1, live 0"
jq -e '.rulesets[0].ok == false and (.rulesets[0].differences | length) == 1' "$SB/out.json" >/dev/null && pass "rule differs: recorded" || fail "rule differs: record" "$(cat "$SB/out.json")"

# 3: a required check missing live
reset; reporting true
ruleset "$SB/committed/main_sec.json" 1 main_sec active branch 1 "build gate,e2e gate" committed
ruleset "$API/rulesets/20716271" 20716271 main_sec active branch 1 "build gate" live
live_list; run
[ "$RC" -ne 0 ] && pass "check missing: exit non-zero" || fail "check missing: rc=0" "$OUT"
expect_in "check missing: names the checks field" "main_sec: rules.required_status_checks.required_status_checks"
expect_in "check missing: names the missing context" "e2e gate"

# 4: a committed ruleset with no live counterpart
reset; reporting true
ruleset "$SB/committed/main_sec.json" 1 main_sec active branch 1 "build gate,e2e gate" committed
live_list; run
[ "$RC" -ne 0 ] && pass "no live counterpart: exit non-zero" || fail "no live counterpart: rc=0" "$OUT"
expect_in "no live counterpart: named" "committed ruleset main_sec: no active live counterpart"

# 5: a live active branch ruleset with no committed counterpart (the retired one returning)
reset; reporting true
ruleset "$SB/committed/main_sec.json" 1 main_sec active branch 1 "build gate,e2e gate" committed
ruleset "$API/rulesets/20716271" 20716271 main_sec active branch 1 "build gate,e2e gate" live
ruleset "$API/rulesets/19534405" 19534405 branch active branch 0 "" live
live_list; run
[ "$RC" -ne 0 ] && pass "live-only: exit non-zero" || fail "live-only: rc=0" "$OUT"
expect_in "live-only: named with its id" "live ruleset branch (id 19534405): no committed counterpart"
expect_in "live-only: counted" "1 live-only"
jq -e '.live_only == [{"name": "branch", "id": 19534405}]' "$SB/out.json" >/dev/null && pass "live-only: recorded" || fail "live-only: record" "$(cat "$SB/out.json")"

# 6: live-only rulesets that are disabled, evaluate-only, or target tags are not failures
reset; reporting true
ruleset "$SB/committed/main_sec.json" 1 main_sec active branch 1 "build gate,e2e gate" committed
ruleset "$API/rulesets/20716271" 20716271 main_sec active branch 1 "build gate,e2e gate" live
ruleset "$API/rulesets/30000001" 30000001 old disabled branch 0 "" live
ruleset "$API/rulesets/30000002" 30000002 trial evaluate branch 0 "" live
ruleset "$API/rulesets/30000003" 30000003 tags active tag 0 "" live
live_list; run
[ "$RC" -eq 0 ] && pass "inactive or tag live-only: exit 0" || fail "inactive or tag live-only: rc=$RC" "$OUT"
expect_in "inactive or tag live-only: not counted" "0 live-only"

# 7: a committed ruleset whose live counterpart is no longer active
reset; reporting true
ruleset "$SB/committed/main_sec.json" 1 main_sec active branch 1 "build gate,e2e gate" committed
ruleset "$API/rulesets/20716271" 20716271 main_sec disabled branch 1 "build gate,e2e gate" live
live_list; run
[ "$RC" -ne 0 ] && pass "live disabled: exit non-zero" || fail "live disabled: rc=0" "$OUT"
expect_in "live disabled: enforcement named" "main_sec: enforcement: committed active, live disabled"

# 8: private vulnerability reporting disabled
reset; reporting false
ruleset "$SB/committed/main_sec.json" 1 main_sec active branch 1 "build gate,e2e gate" committed
ruleset "$API/rulesets/20716271" 20716271 main_sec active branch 1 "build gate,e2e gate" live
live_list; run
[ "$RC" -ne 0 ] && pass "reporting disabled: exit non-zero" || fail "reporting disabled: rc=0" "$OUT"
expect_in "reporting disabled: named" "private vulnerability reporting is disabled (Req 9.3)"
jq -e '.reporting.enabled == false and .reporting.ok == false and .rulesets[0].ok == true' "$SB/out.json" >/dev/null && pass "reporting disabled: recorded, rulesets still compared" || fail "reporting disabled: record" "$(cat "$SB/out.json")"

# 9: the reporting endpoint unreadable
reset; rm -f "$API/private-vulnerability-reporting"
ruleset "$SB/committed/main_sec.json" 1 main_sec active branch 1 "build gate,e2e gate" committed
ruleset "$API/rulesets/20716271" 20716271 main_sec active branch 1 "build gate,e2e gate" live
live_list; run
[ "$RC" -ne 0 ] && pass "reporting unreadable: exit non-zero" || fail "reporting unreadable: rc=0" "$OUT"
expect_in "reporting unreadable: named" "private vulnerability reporting: unreadable"

# 10: the rulesets list unreadable
reset; reporting true; rm -rf "$API/rulesets"
ruleset "$SB/committed/main_sec.json" 1 main_sec active branch 1 "build gate,e2e gate" committed
run
[ "$RC" -ne 0 ] && pass "rulesets unreadable: exit non-zero" || fail "rulesets unreadable: rc=0" "$OUT"
expect_in "rulesets unreadable: named" "rulesets: unreadable"

echo
if [ "$FAILURES" -eq 0 ]; then echo "all check-governance tests passed"; else echo "$FAILURES test(s) failed"; exit 1; fi
