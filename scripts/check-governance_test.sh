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

# 11: the rate-limited read. Anonymous reads share 60 an hour per network
# address, and a runner's address is shared, so a read can be answered "rate
# limit exceeded" through no fault of this repository. The script waits for
# the reset and reads again, anonymously (Req 9.9). The static server cannot
# answer 403 with headers and then 200, so these inputs go to a second
# localhost server that answers per path from a script of answers: each file
# $SB/rl/script/<path, / as __>/<n> is one answer, used up lowest number
# first; a path with no answer left is served from the same fixture tree as
# above. It logs every read with whether it carried a token. The waiting is
# the external command sleep, so a stand-in on PATH logs its argument and
# returns at once; every run is under timeout, a real wait fails the line.
mkdir -p "$SB/rl/bin" "$SB/rl/script"
cat > "$SB/rl/server.py" <<'PY'
import http.server, json, os, sys, time
root, script, reads, portfile = sys.argv[1:5]

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        path = self.path.split("?")[0].strip("/")
        with open(reads, "a") as f:
            f.write(f"{path} auth={'present' if self.headers.get('Authorization') else 'none'}\n")
        queue = os.path.join(script, path.replace("/", "__"))
        left = sorted(os.listdir(queue), key=int) if os.path.isdir(queue) else []
        headers = {}
        if left:
            with open(os.path.join(queue, left[0])) as f:
                answer = json.load(f)
            os.remove(os.path.join(queue, left[0]))
            status = answer["status"]
            headers = dict(answer.get("headers", {}))
            if "reset_in" in answer:  # the epoch second the limit resets, counted from this answer
                headers["x-ratelimit-reset"] = int(time.time()) + answer["reset_in"]
            body = json.dumps({"message": answer.get("message", "")}).encode()
        else:
            target = os.path.join(root, path)
            if os.path.isdir(target):
                target = os.path.join(target, "index.html")
            if os.path.isfile(target):
                status = 200
                with open(target, "rb") as f:
                    body = f.read()
            else:
                status, body = 404, b'{"message": "Not Found"}'
        self.send_response(status)
        for k, v in headers.items():
            self.send_header(k, str(v))
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(portfile, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
PY
python3 "$SB/rl/server.py" "$SB/api" "$SB/rl/script" "$SB/rl/reads.log" "$SB/rl/port" >"$SB/rl/server.log" 2>&1 &
RL_SERVER=$!
trap 'kill "$SERVER" "$RL_SERVER" 2>/dev/null' EXIT
for _ in $(seq 50); do [ -s "$SB/rl/port" ] && break; sleep 0.1; done
RL_API="http://127.0.0.1:$(cat "$SB/rl/port")"
printf '#!/bin/sh\necho "$*" >> "%s"\n' "$SB/rl/sleep.log" > "$SB/rl/bin/sleep"; chmod +x "$SB/rl/bin/sleep"

RL_LIST="repos/acme/cat/rulesets"
RL_DETAIL="repos/acme/cat/rulesets/20716271"
RL_REPORTING="repos/acme/cat/private-vulnerability-reporting"
rl_reset() { # the fixture of case 1, no answer scripted, both logs empty
  reset; reporting true
  ruleset "$SB/committed/main_sec.json" 1 main_sec active branch 1 "build gate,e2e gate" committed
  ruleset "$API/rulesets/20716271" 20716271 main_sec active branch 1 "build gate,e2e gate" live shuffle
  live_list
  rm -rf "$SB/rl/script"; mkdir -p "$SB/rl/script"; : > "$SB/rl/sleep.log"; : > "$SB/rl/reads.log"
}
answer() { # path n json: the n-th answer to that path
  local queue; queue="$SB/rl/script/$(sed 's#/#__#g' <<<"$1")"
  mkdir -p "$queue"; printf '%s\n' "$3" > "$queue/$2"
}
limited() { # reset_in: GitHub's primary rate limit answer, the reset that many seconds away
  printf '{"status": 403, "headers": {"x-ratelimit-limit": 60, "x-ratelimit-remaining": 0, "x-ratelimit-used": 60, "x-ratelimit-resource": "core"}, "reset_in": %s, "message": "API rate limit exceeded for 203.0.113.7."}' "$1"
}
rl_run() { # [VAR=value ...]: the stand-in sleep first on PATH, the scripted server as the API
  rm -f "$SB/out.json"
  OUT=$(env PATH="$SB/rl/bin:$PATH" DHC_GITHUB_API="$RL_API" "$@" timeout 10 "$CHECK" "$SB/committed" acme/cat "$SB/out.json" 2>&1); RC=$?
}
in_ranges() { # "n1 n2 ..." [lo hi]...: as many whole numbers as ranges, each inside its range, in order
  local nums n; nums=($1); shift
  [ "${#nums[@]}" -eq $(( $# / 2 )) ] || return 1
  for n in "${nums[@]}"; do
    [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge "$1" ] && [ "$n" -le "$2" ] || return 1
    shift 2
  done
}
rl_waits() { # label path [lo hi]...: warning lines, the stand-in's log and the record show exactly these waits
  local label=$1 path=$2 wanted="none" warned slept recorded; shift 2
  [ $# -gt 0 ] && wanted="one in each of $(printf '%s..%s ' "$@")second(s), in this order"
  warned=$(grep '^::warning::' <<<"$OUT" | sed -E "s#^::warning::governance: $path: GitHub's anonymous rate limit is spent, waiting ([0-9]+) seconds for its reset \(Req 9\.9\)\$#\1#")
  in_ranges "$warned" "$@" && pass "$label: warning line(s)" \
    || fail "$label: warning line(s): wanted $wanted; a warning line is '::warning::governance: $path: GitHub's anonymous rate limit is spent, waiting <n> seconds for its reset (Req 9.9)'" "actual output:" "$OUT"
  slept=$(cat "$SB/rl/sleep.log")
  in_ranges "$slept" "$@" && pass "$label: sleep calls" \
    || fail "$label: sleep calls: wanted $wanted" "actual arguments, one call a line: ${slept:-no call}"
  recorded=$(jq -r --arg p "$path" 'if (.rate_limit_waits | type) != "array" then "rate_limit_waits is \(.rate_limit_waits | type), not a list" elif all(.rate_limit_waits[]; .path == $p and (.seconds | type) == "number") then .rate_limit_waits[].seconds else "an entry without this path or a number of seconds" end' "$SB/out.json" 2>&1)
  in_ranges "$recorded" "$@" && pass "$label: record's rate_limit_waits" \
    || fail "$label: record's rate_limit_waits: wanted $wanted (an entry is {\"path\": \"$path\", \"seconds\": n})" "actual: ${recorded:-an empty list}" "$(cat "$SB/out.json" 2>&1)"
  [ $# -eq 0 ] && return
  [ -n "$warned" ] && [ "$warned" = "$slept" ] && [ "$warned" = "$recorded" ] && pass "$label: warning, sleep and record carry the same seconds" \
    || fail "$label: warning, sleep and record carry the same seconds" "warned: $(echo $warned)" "slept: $(echo $slept)" "recorded: $(echo $recorded)"
}
rl_reads() { # label path n: that read made n time(s), no read of the run with a token
  local got; got=$(grep -cxF -- "$2 auth=none" "$SB/rl/reads.log")
  [ "$got" -eq "$3" ] && ! grep -q 'auth=present' "$SB/rl/reads.log" && pass "$1: read $3 time(s), anonymously" \
    || fail "$1: wanted $3 anonymous read(s) of $2, got $got" "all reads of the run:" "$(cat "$SB/rl/reads.log")"
}
rl_readable() { # label: the comparison made as in case 1
  [ "$RC" -eq 0 ] && pass "$1: exit 0" || fail "$1: wanted exit 0, got rc=$RC" "$OUT"
  expect_in "$1: summary counts one compared, no difference" "1 committed ruleset(s) compared, 0 difference(s), 0 live-only"
  jq -e '.reporting.enabled == true and .reporting.ok == true and (.rulesets | length) == 1 and .rulesets[0].name == "main_sec" and .rulesets[0].ok == true and .rulesets[0].live_id == 20716271 and (.live_only | length) == 0' "$SB/out.json" >/dev/null 2>&1 \
    && pass "$1: record's existing keys as in case 1" || fail "$1: record's existing keys: wanted reporting enabled and ok, main_sec ok with live_id 20716271, no live_only" "$(cat "$SB/out.json" 2>&1)"
}
rl_unreadable() { # label "<the read's existing error line start>" limit|other [bound]: exit non-zero, the cause named or not
  local label=$1 line
  [ "$RC" -ne 0 ] && [ "$RC" -ne 124 ] && pass "$label: exit non-zero" || fail "$label: wanted the script's own non-zero exit, got rc=$RC (124 is the timeout)" "$OUT"
  line=$(grep -F -- "::error::$2: unreadable" <<<"$OUT")
  if [ "$3" = limit ]; then
    grep -qi 'rate limit' <<<"$line" && pass "$label: unreadable, the rate limit named as the cause" \
      || fail "$label: wanted a line '::error::$2: unreadable (...)' naming the rate limit" "actual output:" "$OUT"
    [ $# -lt 4 ] || { grep -i 'rate limit' <<<"$line" | grep -qE "(^|[^0-9])$4([^0-9]|\$)" && pass "$label: the bound of $4 seconds named" \
      || fail "$label: wanted the same line to name the bound, $4" "actual output:" "$OUT"; }
  else
    [ -n "$line" ] && ! grep -qi 'rate limit' <<<"$OUT" && pass "$label: unreadable as today, no rate limit named" \
      || fail "$label: wanted a line '::error::$2: unreadable (...)' and the rate limit named nowhere" "actual output:" "$OUT"
  fi
}

# 11a: the rulesets list rate-limited once (403, remaining 0, reset 90 seconds away), then readable
rl_reset; answer "$RL_LIST" 1 "$(limited 90)"; rl_run
rl_readable "rate limit, list once"
rl_waits "rate limit, list once" "$RL_LIST" 93 97
rl_reads "rate limit, list once" "$RL_LIST" 2

# 11b: the same for the reporting endpoint
rl_reset; answer "$RL_REPORTING" 1 "$(limited 90)"; rl_run
rl_readable "rate limit, reporting once"
rl_waits "rate limit, reporting once" "$RL_REPORTING" 93 97
rl_reads "rate limit, reporting once" "$RL_REPORTING" 2

# 11c: the same for a ruleset's detail read
rl_reset; answer "$RL_DETAIL" 1 "$(limited 90)"; rl_run
rl_readable "rate limit, detail once"
rl_waits "rate limit, detail once" "$RL_DETAIL" 93 97
rl_reads "rate limit, detail once" "$RL_DETAIL" 2

# 11d: 429 with retry-after: 30 (seconds, not an epoch): one wait of 35
rl_reset; answer "$RL_LIST" 1 '{"status": 429, "headers": {"retry-after": 30}, "message": "You have exceeded a secondary rate limit."}'; rl_run
rl_readable "rate limit, 429 retry-after"
rl_waits "rate limit, 429 retry-after" "$RL_LIST" 35 35
rl_reads "rate limit, 429 retry-after" "$RL_LIST" 2

# 11e: rate-limited twice (resets 90, then 40 seconds away), then readable: two waits
rl_reset; answer "$RL_LIST" 1 "$(limited 90)"; answer "$RL_LIST" 2 "$(limited 40)"; rl_run
rl_readable "rate limit, twice"
rl_waits "rate limit, twice" "$RL_LIST" 93 97 43 47
rl_reads "rate limit, twice" "$RL_LIST" 3

# 11f: rate-limited three times: two waits, then unreadable, the fourth answer never asked for
rl_reset; answer "$RL_LIST" 1 "$(limited 90)"; answer "$RL_LIST" 2 "$(limited 40)"; answer "$RL_LIST" 3 "$(limited 20)"; rl_run
rl_unreadable "rate limit, three times" "rulesets" limit
rl_waits "rate limit, three times" "$RL_LIST" 93 97 43 47
rl_reads "rate limit, three times" "$RL_LIST" 3

# 11g: the reset further away than the bound: no wait at all
rl_reset; answer "$RL_LIST" 1 "$(limited 600)"; rl_run DHC_GOVERNANCE_MAX_WAIT=60
rl_unreadable "rate limit, reset beyond the bound" "rulesets" limit 60
rl_waits "rate limit, reset beyond the bound" "$RL_LIST"
rl_reads "rate limit, reset beyond the bound" "$RL_LIST" 1

# 11h: 403 with remaining 0 that names no reset and no retry-after: nothing to wait for
rl_reset; answer "$RL_DETAIL" 1 '{"status": 403, "headers": {"x-ratelimit-limit": 60, "x-ratelimit-remaining": 0}, "message": "API rate limit exceeded for 203.0.113.7."}'; rl_run
rl_unreadable "rate limit, no reset named" "ruleset main_sec (id 20716271)" limit
rl_waits "rate limit, no reset named" "$RL_DETAIL"
rl_reads "rate limit, no reset named" "$RL_DETAIL" 1

# 11i: failures that are no rate limit are unreadable at once: a 403 with reads
# left, a 500, and a 404 that happens to be the last read of the hour
rl_reset; answer "$RL_LIST" 1 '{"status": 403, "headers": {"x-ratelimit-limit": 60, "x-ratelimit-remaining": 37}, "reset_in": 90, "message": "Forbidden"}'; rl_run
rl_unreadable "403 with reads left" "rulesets" other
rl_waits "403 with reads left" "$RL_LIST"
rl_reads "403 with reads left" "$RL_LIST" 1
rl_reset; answer "$RL_REPORTING" 1 '{"status": 500, "message": "Server Error"}'; rl_run
rl_unreadable "500" "private vulnerability reporting" other
rl_waits "500" "$RL_REPORTING"
rl_reads "500" "$RL_REPORTING" 1
rl_reset; answer "$RL_DETAIL" 1 '{"status": 404, "headers": {"x-ratelimit-limit": 60, "x-ratelimit-remaining": 0}, "reset_in": 90, "message": "Not Found"}'; rl_run
rl_unreadable "404 on the hour's last read" "ruleset main_sec (id 20716271)" other
rl_waits "404 on the hour's last read" "$RL_DETAIL"
rl_reads "404 on the hour's last read" "$RL_DETAIL" 1

# 11j: no rate limit at all: an empty list in the record, sleep never called
rl_reset; rl_run
rl_readable "no rate limit"
rl_waits "no rate limit" "$RL_LIST"
rl_reads "no rate limit" "$RL_LIST" 1

echo
if [ "$FAILURES" -eq 0 ]; then echo "all check-governance tests passed"; else echo "$FAILURES test(s) failed"; exit 1; fi
