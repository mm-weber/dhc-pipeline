#!/usr/bin/env bash
# Tests for scripts/check-authenticity.sh: the daily re-verification of every
# definition's declared authenticity signal (Req 3.10; task 11.3) and the
# lapsed compat review-by report (Req 4.9). git ls-remote is stubbed, GitHub's
# verification statement and the publisher's version statement are served
# from file:// trees, the sidecars are files beside the "tarballs".
# The reads that fail (Req 3.13; task 11.6) run against a localhost HTTP
# server, so a 403 and the arriving token can be observed.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-authenticity.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

COMMIT="4a12e725a55a520476eac1a4c123e8461024bbef"
TAGOBJ="5076ef4694884edd1d0c12ae890bf96bec08d528"
OTHER="1111111111111111111111111111111111111111"
A=$(printf 'a%.0s' $(seq 64)); B=$(printf 'b%.0s' $(seq 64)); C=$(printf 'c%.0s' $(seq 64))

fresh() {
  SB=$(mktemp -d); mkdir -p "$SB/root/image" "$SB/root/chart" "$SB/bin" "$SB/api" "$SB/dist" "$SB/versions"
  # git ls-remote: "<sha>\t<ref>" for the refs the stub is told about
  cat > "$SB/bin/git" <<'STUB'
#!/usr/bin/env bash
[ "$1" = ls-remote ] || { echo "stub git: unexpected $1" >&2; exit 2; }
printf 'git %s\n' "$*" >> "${STUB_DIR}/git.log"
ref="$3"
while IFS='|' read -r r sha; do
  if [ "$r" = "$ref" ]; then [ -n "$sha" ] && printf '%s\t%s\n' "$sha" "$ref"; exit 0; fi
done < "${STUB_DIR}/refs"
exit 0
STUB
  chmod +x "$SB/bin/git"
  : > "$SB/refs"
  export STUB_DIR="$SB" DHC_GITHUB_API="file://$SB/api" DHC_VERSIONS_API="file://$SB/versions" DHC_TODAY="2026-09-06" DHC_RETRY_RESTS="0 0 0" DHC_RETRY_AFTER_CAP="2"
}
git_def() { # name class repo tag checksum
  mkdir -p "$SB/root/image/$1"
  cat > "$SB/root/image/$1/image.yaml" <<DEF
image: ghcr.io/acme/dhc/$1
vars:
  VERSION: 1.0.0
contents:
  builds:
    - contents:
        files:
          - url: git+https://github.com/$3.git#$4
            # authenticity: $2
            checksum: $5
DEF
}
tarball_def() { # name amd64_sha arm64_sha version
  mkdir -p "$SB/root/image/$1"
  cat > "$SB/root/image/$1/image.yaml" <<DEF
image: ghcr.io/acme/dhc/$1
vars:
  APP_SHA256: '#{ target.arch == "amd64" ? "$2" : "$3" }'
  SEMVER_VERSION: $4
  VERSION: $4
contents:
  builds:
    - contents:
        files:
          - url: file://$SB/dist/app_\${target.arch}.tar.gz
            # authenticity: cross-origin-checksum
DEF
}
verification() { # tag|commit owner/repo sha verified reason
  local dir="$SB/api/repos/$2"
  if [ "$1" = tag ]; then mkdir -p "$dir/git/tags"; printf '{"object":{"sha":"x"},"verification":{"verified":%s,"reason":"%s"}}\n' "$4" "$5" > "$dir/git/tags/$3"
  else mkdir -p "$dir/commits"; printf '{"commit":{"verification":{"verified":%s,"reason":"%s"}}}\n' "$4" "$5" > "$dir/commits/$3"; fi
}
refs() { printf '%s\n' "$@" >> "$SB/refs"; } # "refs/tags/v1|<sha>" lines; an empty sha means absent
statement() { # version amd64 arm64
  printf '{"packages":[{"os":"linux","arch":"amd64","url":"https://x/app_%s_linux_amd64.tar.gz","sha256":"%s"},{"os":"linux","arch":"arm64","url":"https://x/app_%s_linux_arm64.tar.gz","sha256":"%s"}]}\n' "$1" "$2" "$1" "$3" > "$SB/versions/$1"
}
sidecars() { printf '%s\n' "$1" > "$SB/dist/app_amd64.tar.gz.sha256"; printf '%s\n' "$2" > "$SB/dist/app_arm64.tar.gz.sha256"; }
# The check re-verifies ACTIVE definitions (Req 3.10 as amended; task 14.2):
# a case that writes no policy file gets every definition it created listed,
# the pre-14.2 behaviour; a case about deactivation writes its own.
policy() { { printf 'active_set:\n'; printf '  - %s\n' "$@"; } > "$SB/root/catalogue-policy.yaml"; }
run() {
  [ -f "$SB/root/catalogue-policy.yaml" ] || policy $(ls "$SB/root/image")
  PATH="$SB/bin:$PATH" "$CHECK" "$SB/root" "$SB/out.jsonl" 2>&1
}
rec() { jq -r "$1" "$SB/out.jsonl"; }

# 1: every class verifies: exit 0, one record per definition, all ok
fresh
git_def cm signed-tag cert-manager/cert-manager v1.21.1 "$COMMIT"; refs "refs/tags/v1.21.1^{}|$COMMIT" "refs/tags/v1.21.1|$TAGOBJ"; verification tag cert-manager/cert-manager "$TAGOBJ" true valid
git_def valkey signed-commit valkey-io/valkey 9.1.2 "$COMMIT"; refs "refs/tags/9.1.2^{}|" "refs/tags/9.1.2|$COMMIT"; verification commit valkey-io/valkey "$COMMIT" true valid
tarball_def grafana "$A" "$B" 13.1.5; statement 13.1.5 "$A" "$B"; sidecars "$A" "$B"
out=$(run); rc=$?
[ "$rc" -eq 0 ] && pass "every declared signal verifies: exit 0" || fail "rc=$rc" "$out"
[ "$(rec 'select(.ok) | .definition' | sort | tr '\n' ' ')" = "cm grafana valkey " ] && pass "one ok record per definition" || fail "records" "$(cat "$SB/out.jsonl")"
grep -q "3 signal(s) verified, 0 mismatch(es)" <<<"$out" && pass "the summary line counts" || fail "summary" "$out"
grep -q "cm (signed-tag, v1.21.1): tag object 5076ef469488 on commit 4a12e725a55a, GitHub verification: valid" <<<"$out" && pass "signed-tag names the tag object and the commit" || fail "signed-tag detail" "$out"
grep -q "grafana (cross-origin-checksum, 13.1.5): amd64 aaaaaaaaaaaa… agreed by the" <<<"$out" && pass "cross-origin names both origins per architecture" || fail "cross-origin detail" "$out"

# 2: a tag that moved is a mismatch, named, and fails the run
fresh
git_def cm signed-tag cert-manager/cert-manager v1.21.1 "$COMMIT"; refs "refs/tags/v1.21.1^{}|$OTHER" "refs/tags/v1.21.1|$TAGOBJ"; verification tag cert-manager/cert-manager "$TAGOBJ" true valid
out=$(run); rc=$?
[ "$rc" -eq 1 ] && grep -q "::error::check-authenticity: cm (signed-tag, v1.21.1): tag v1.21.1 now points at 111111111111, the definition pins 4a12e725a55a: the tag moved (Req 3.10)" <<<"$out" && pass "a moved tag is a mismatch, by name" || fail "moved tag" "rc=$rc" "$out"
[ "$(rec 'select(.ok | not) | .definition')" = "cm" ] && pass "the record says which definition" || fail "record" "$(cat "$SB/out.jsonl")"

# 3: a signature that no longer verifies, a lightweight tag under signed-tag, a vanished tag
fresh
git_def app signed-commit acme/app v0.1.0 "$COMMIT"; refs "refs/tags/v0.1.0^{}|" "refs/tags/v0.1.0|$COMMIT"; verification commit acme/app "$COMMIT" false unsigned
git_def lw signed-tag acme/lw v1.0.0 "$COMMIT"; refs "refs/tags/v1.0.0^{}|" "refs/tags/v1.0.0|$COMMIT"
git_def gone signed-commit acme/gone v2.0.0 "$COMMIT"; refs "refs/tags/v2.0.0^{}|" "refs/tags/v2.0.0|"
out=$(run); rc=$?
[ "$rc" -eq 1 ] && pass "mismatches fail the run" || fail "rc=$rc" "$out"
grep -q "app (signed-commit, v0.1.0): GitHub reports commit 4a12e725a55a (v0.1.0) as not verified (unsigned)" <<<"$out" && pass "an unverified commit is named with GitHub's reason" || fail "unsigned" "$out"
grep -q "lw (signed-tag, v1.0.0): declared signed-tag, but v1.0.0 is a lightweight tag" <<<"$out" && pass "a lightweight tag under signed-tag is a mismatch" || fail "lightweight" "$out"
grep -q "gone (signed-commit, v2.0.0): tag v2.0.0 no longer exists" <<<"$out" && pass "a vanished tag is a mismatch" || fail "vanished" "$out"
[ "$(rec 'select(.ok | not) | .definition' | wc -l)" -eq 3 ] && pass "three records, all not ok" || fail "records" "$(cat "$SB/out.jsonl")"

# 4: the cross-origin checksum: a sidecar that changed, a statement that disagrees, a statement that is missing
fresh
tarball_def grafana "$A" "$B" 13.1.5; statement 13.1.5 "$A" "$B"; sidecars "$A" "$C"
out=$(run); rc=$?
[ "$rc" -eq 1 ] && grep -q "arm64: pinned bbbbbbbbbbbb…, origin sidecar cccccccccccc…, version statement bbbbbbbbbbbb… do not agree" <<<"$out" && pass "a sidecar that changed is named with every value" || fail "sidecar" "rc=$rc" "$out"
fresh
tarball_def grafana "$A" "$B" 13.1.5; statement 13.1.5 "$A" "$C"; sidecars "$A" "$B"
out=$(run); rc=$?
[ "$rc" -eq 1 ] && grep -q "version statement cccccccccccc… do not agree" <<<"$out" && pass "a disagreeing statement is named" || fail "statement" "rc=$rc" "$out"
fresh
tarball_def grafana "$A" "$B" 13.1.5; sidecars "$A" "$B"
out=$(run); rc=$?
[ "$rc" -eq 2 ] && grep -q "::error::check-authenticity: grafana (cross-origin-checksum, 13.1.5): not measured: version statement at file://$SB/versions/13.1.5: curl: (37)" <<<"$out" && grep -q "(Req 3.13)" <<<"$out" && pass "a missing statement is not measured: neither a pass nor a mismatch (Req 3.13)" || fail "missing statement" "rc=$rc" "$out"
[ "$(rec 'select(.ok == null) | .definition')" = "grafana" ] && [ -z "$(rec 'select(.ok == false) | .definition')" ] && pass "the record carries no verdict" || fail "record" "$(cat "$SB/out.jsonl")"
# 4d: a sidecar that cannot be read is not measured either; the other architecture agreeing does not make it a pass
fresh
tarball_def grafana "$A" "$B" 13.1.5; statement 13.1.5 "$A" "$B"; sidecars "$A" "$B"; rm "$SB/dist/app_arm64.tar.gz.sha256"
out=$(run); rc=$?
[ "$rc" -eq 2 ] && grep -q "grafana (cross-origin-checksum, 13.1.5): not measured: checksum sidecar for arm64 at file://$SB/dist/app_arm64.tar.gz.sha256: curl: (37)" <<<"$out" && pass "an unreadable sidecar is not measured, by architecture and url" || fail "sidecar unreadable" "rc=$rc" "$out"

# 5: a definition without a verifiable class fails by name
fresh
mkdir -p "$SB/root/image/bare"; printf 'image: ghcr.io/acme/dhc/bare\nvars:\n  VERSION: 1.0.0\n' > "$SB/root/image/bare/image.yaml"
out=$(run); rc=$?
[ "$rc" -eq 1 ] && grep -q "bare (none, ?): no verifiable authenticity class declared" <<<"$out" && pass "no class: a mismatch, by name" || fail "no class" "rc=$rc" "$out"

# 6: Req 4.9: a lapsed compat review-by date is reported, a future one is not, and neither fails the run
fresh
git_def valkey signed-commit valkey-io/valkey 9.1.2 "$COMMIT"; refs "refs/tags/9.1.2^{}|" "refs/tags/9.1.2|$COMMIT"; verification commit valkey-io/valkey "$COMMIT" true valid
mkdir -p "$SB/root/chart/valkey" "$SB/root/chart/grafana"
printf 'upstream:\n  name: valkey\ncompat:\n  reason: the chart assumes a shell\n  issue: https://github.com/valkey-io/valkey-helm/issues/1\n  review_by: 2026-09-01\n' > "$SB/root/chart/valkey/chart.yaml"
printf 'upstream:\n  name: grafana\ncompat:\n  reason: x\n  review_by: 2026-12-01\n' > "$SB/root/chart/grafana/chart.yaml"
out=$(run); rc=$?
[ "$rc" -eq 0 ] && pass "a lapsed review-by date does not fail the run" || fail "rc=$rc" "$out"
grep -q "::warning::check-authenticity: chart valkey: the compat decision's review-by date 2026-09-01 has passed (today 2026-09-06)" <<<"$out" && pass "the lapse is reported by name" || fail "lapse" "$out"
grep -q "1 lapsed compat review-by date(s)" <<<"$out" && pass "and counted" || fail "count" "$out"
[ "$(rec 'select(.class == "compat" and .ok) | .definition')" = "chart/grafana" ] && pass "a future date is recorded as ahead" || fail "future" "$(cat "$SB/out.jsonl")"

# 7: Req 3.10 (task 14.2): an inactive definition is outside the tracking
#    scope, so its signal is not re-verified: a tag that moved under it does
#    not fail the run, no record is written for it, and the summary says so
fresh
git_def cm signed-tag cert-manager/cert-manager v1.21.1 "$COMMIT"; refs "refs/tags/v1.21.1^{}|$COMMIT" "refs/tags/v1.21.1|$TAGOBJ"; verification tag cert-manager/cert-manager "$TAGOBJ" true valid
git_def old signed-tag acme/old v1.0.0 "$COMMIT"; refs "refs/tags/v1.0.0^{}|$OTHER" "refs/tags/v1.0.0|$TAGOBJ"
policy cm
out=$(run); rc=$?
[ "$rc" -eq 0 ] && pass "an inactive definition's moved tag does not fail the run" || fail "inactive" "rc=$rc" "$out"
[ "$(rec '.definition' | sort | tr '\n' ' ')" = "cm " ] && pass "no record for the inactive definition" || fail "records" "$(cat "$SB/out.jsonl")"
grep -q "1 inactive definition(s) not re-verified" <<<"$out" && pass "the summary counts the inactive definition" || fail "summary" "$out"
grep -q "old" <<<"$(rec '.definition')" && fail "inactive not recorded" || pass "the inactive definition is named nowhere in the records"
# and a malformed set is the reader's refusal, not a silent empty scope
policy cm typo
out=$(run); rc=$?
[ "$rc" -eq 2 ] && grep -q "typo" <<<"$out" && pass "a malformed active set refuses naming the entry" || fail "malformed" "rc=$rc" "$out"

# A localhost GitHub API for the reads that fail (Req 3.13; task 11.6): a
# file:// tree cannot answer 403, and the token has to be seen arriving. It
# serves the same $SB/api tree the file:// cases write; a sibling
# `<file>.status` sets the status, a missing file answers 404 with GitHub's
# body, and every request appends its path and Authorization header to
# $SB/auth.log (the check-governance_test.sh shape).
serve_api() {
  PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
  python3 - "$PORT" "$SB/api" "$SB/auth.log" <<'PY' >"$SB/server.log" 2>&1 &
import http.server, os, sys
port, root, log = int(sys.argv[1]), sys.argv[2], sys.argv[3]
class H(http.server.BaseHTTPRequestHandler):
    served = {}
    def do_GET(self):
        with open(log, "a") as f:
            f.write(self.path + " " + self.headers.get("Authorization", "-") + "\n")
        p = os.path.join(root, self.path.lstrip("/"))
        headers = []
        if os.path.isfile(p):
            # `<file>.status` lists one status per request, the last repeating;
            # `<file>.headers` adds "Name: value" lines to every answer
            seq = open(p + ".status").read().split() if os.path.isfile(p + ".status") else ["200"]
            n = H.served.get(self.path, 0); H.served[self.path] = n + 1
            status = int(seq[min(n, len(seq) - 1)])
            body = open(p, "rb").read()
            if os.path.isfile(p + ".headers"):
                headers = [l.split(":", 1) for l in open(p + ".headers").read().splitlines() if ":" in l]
        else:
            status, body = 404, b'{"message":"Not Found"}'
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        for k, v in headers:
            self.send_header(k.strip(), v.strip())
        self.end_headers()
        self.wfile.write(body)
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
  SERVER_PID=$!
  for _ in $(seq 50); do curl -sS -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null && break; sleep 0.1; done
  export DHC_GITHUB_API="http://127.0.0.1:$PORT"
}
stop_api() { if [ -n "${SERVER_PID:-}" ]; then kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; SERVER_PID=""; fi; }
trap stop_api EXIT
rate_limited() { # tag|commit owner/repo sha: GitHub's primary rate-limit answer for that statement
  local f
  if [ "$1" = tag ]; then f="$SB/api/repos/$2/git/tags/$3"; else f="$SB/api/repos/$2/commits/$3"; fi
  mkdir -p "$(dirname "$f")"
  printf '{"message":"API rate limit exceeded for 1.2.3.4. (But here'"'"'s the good news: Authenticated requests get a higher rate limit. Check out the documentation for more details.)","documentation_url":"https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting"}\n' > "$f"
  printf '403' > "$f.status"
  printf 'x-ratelimit-remaining: 0\nx-ratelimit-reset: %s\n' "$RESET" > "$f.headers"
}
RESET=1789000000; RESET_HM=$(date -u -d "@$RESET" +%H:%MZ)
git_unreachable() { # the stub git fails the way ls-remote does without a network
  cat > "$SB/bin/git" <<'STUB'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "${STUB_DIR}/git.log"
echo "fatal: unable to access 'https://github.com/cert-manager/cert-manager.git/': Could not resolve host: github.com" >&2
exit 128
STUB
  chmod +x "$SB/bin/git"
}

# 8: Req 3.13 (task 11.6): a statement GitHub will not serve is not measured:
#    the run fails naming the origin and the status, the record carries no
#    verdict (ok: null), and nothing is written that the workflow would file
#    an issue from. The 2026-09-16 rescan read a rate-limited API as six
#    mismatches, so the answer here is GitHub's own.
fresh; serve_api
git_def valkey signed-commit valkey-io/valkey 9.1.2 "$COMMIT"; refs "refs/tags/9.1.2^{}|" "refs/tags/9.1.2|$COMMIT"; rate_limited commit valkey-io/valkey "$COMMIT"
out=$(run); rc=$?
[ "$rc" -eq 2 ] && pass "an unreadable statement fails the run with the refusal code, not the mismatch code" || fail "rc=$rc" "$out"
grep -q "::error::check-authenticity: valkey (signed-commit, 9.1.2): not measured: GitHub's verification statement for commit 4a12e725a55a at http://127.0.0.1:$PORT/repos/valkey-io/valkey/commits/$COMMIT: HTTP 403: API rate limit exceeded for 1.2.3.4; hourly budget resets at ${RESET_HM}, not retried (Req 3.13)" <<<"$out" && pass "named with the origin, the status, GitHub's message and the reset" || fail "not measured message" "$out"
[ "$(rec 'select(.ok == null) | .definition')" = "valkey" ] && pass "the record is ok: null, a third state" || fail "record" "$(cat "$SB/out.jsonl")"
[ -z "$(rec 'select(.ok == false) | .definition')" ] && pass "no record says mismatch" || fail "a mismatch record was written" "$(cat "$SB/out.jsonl")"
grep -q "0 signal(s) verified, 0 mismatch(es), 1 not measured" <<<"$out" && pass "the summary line counts it apart" || fail "summary" "$out"
[ "$(grep -c "^/repos/valkey-io/valkey/commits/$COMMIT " "$SB/auth.log")" -eq 1 ] && pass "a primary rate limit is asked once, not retried" || fail "rate-limit requests" "$(cat "$SB/auth.log")"
# and the token the workflow sets reaches the request (GH_TOKEN, gh's name, beside GITHUB_TOKEN)
out=$(GH_TOKEN=t0k3n run)
grep -q "/repos/valkey-io/valkey/commits/$COMMIT Bearer t0k3n" "$SB/auth.log" && pass "GH_TOKEN is sent as the bearer token" || fail "token" "$(cat "$SB/auth.log")"
stop_api
# a server that does not answer at all is a transport error, named the same way
fresh
git_def valkey signed-commit valkey-io/valkey 9.1.2 "$COMMIT"; refs "refs/tags/9.1.2^{}|" "refs/tags/9.1.2|$COMMIT"
export DHC_GITHUB_API="http://127.0.0.1:9"
out=$(run); rc=$?
[ "$rc" -eq 2 ] && grep -q "valkey (signed-commit, 9.1.2): not measured: GitHub's verification statement for commit 4a12e725a55a at http://127.0.0.1:9/repos/valkey-io/valkey/commits/$COMMIT: curl: (7)" <<<"$out" && grep -q ", after 4 attempts (Req 3.13)" <<<"$out" && pass "a connection failure is retried, then not measured with curl's error and the count" || fail "transport" "rc=$rc" "$out"

# 9: a tag listing that cannot be read is not measured; an empty listing stays a mismatch (case 3, "gone")
fresh; git_unreachable
git_def cm signed-tag cert-manager/cert-manager v1.21.1 "$COMMIT"
out=$(run); rc=$?
[ "$rc" -eq 2 ] && grep -q "cm (signed-tag, v1.21.1): not measured: tag listing at https://github.com/cert-manager/cert-manager.git: fatal: unable to access" <<<"$out" && grep -q "cert-manager.git: fatal: unable to access .*, after 4 attempts (Req 3.13)" <<<"$out" && pass "a failing ls-remote is retried, then not measured with git's error and the count" || fail "ls-remote" "rc=$rc" "$out"
[ "$(grep -c "ls-remote" "$SB/git.log")" -eq 4 ] && pass "four listings were attempted" || fail "ls-remote count" "$(cat "$SB/git.log")"

# 10: a mismatch and a not-measured in one run: the mismatch code wins, both are named, and only the mismatch is a verdict
fresh; serve_api
git_def cm signed-tag cert-manager/cert-manager v1.21.1 "$COMMIT"; refs "refs/tags/v1.21.1^{}|$OTHER" "refs/tags/v1.21.1|$TAGOBJ"
git_def valkey signed-commit valkey-io/valkey 9.1.2 "$COMMIT"; refs "refs/tags/9.1.2^{}|" "refs/tags/9.1.2|$COMMIT"; rate_limited commit valkey-io/valkey "$COMMIT"
out=$(run); rc=$?
[ "$rc" -eq 1 ] && pass "a real mismatch beside a not-measured fails with the mismatch code" || fail "rc=$rc" "$out"
grep -q "cm (signed-tag, v1.21.1): tag v1.21.1 now points at" <<<"$out" && grep -q "valkey (signed-commit, 9.1.2): not measured" <<<"$out" && pass "both are named" || fail "names" "$out"
[ "$(rec 'select(.ok == false) | .definition')" = "cm" ] && [ "$(rec 'select(.ok == null) | .definition')" = "valkey" ] && pass "one verdict, one non-measurement" || fail "records" "$(cat "$SB/out.jsonl")"
grep -q "0 signal(s) verified, 1 mismatch(es), 1 not measured" <<<"$out" && pass "the summary counts both" || fail "summary" "$out"
stop_api

# 11: retries (task 11.6, the same day): a read that fails is tried again three
#     times, resting between attempts (10s, 30s, 90s in production; the
#     DHC_RETRY_RESTS seam makes them 0 here). A primary rate limit is not
#     retried (case 8 above). A Retry-After header sets the rest instead,
#     capped (DHC_RETRY_AFTER_CAP, 2s here, 120s in production).
fresh; serve_api
git_def valkey signed-commit valkey-io/valkey 9.1.2 "$COMMIT"; refs "refs/tags/9.1.2^{}|" "refs/tags/9.1.2|$COMMIT"; verification commit valkey-io/valkey "$COMMIT" true valid
printf '404 200' > "$SB/api/repos/valkey-io/valkey/commits/$COMMIT.status"
out=$(run); rc=$?
[ "$rc" -eq 0 ] && grep -q "valkey (signed-commit, 9.1.2): commit 4a12e725a55a, GitHub verification: valid" <<<"$out" && pass "a 404 answered 200 on the second attempt verifies" || fail "404 then 200" "rc=$rc" "$out"
grep -q "retrying http://127.0.0.1:$PORT/repos/valkey-io/valkey/commits/$COMMIT in 0s (attempt 2 of 4): HTTP 404" <<<"$out" && pass "the retry is logged with the rest, the attempt and the reason" || fail "retry log" "$out"
[ "$(grep -c "^/repos/valkey-io/valkey/commits/$COMMIT " "$SB/auth.log")" -eq 2 ] && pass "two requests were made, no more" || fail "request count" "$(cat "$SB/auth.log")"
stop_api
# four 502s: not measured after the last attempt, the count named, three retries logged
fresh; serve_api
git_def valkey signed-commit valkey-io/valkey 9.1.2 "$COMMIT"; refs "refs/tags/9.1.2^{}|" "refs/tags/9.1.2|$COMMIT"
mkdir -p "$SB/api/repos/valkey-io/valkey/commits"; printf '{"message":"Server Error"}\n' > "$SB/api/repos/valkey-io/valkey/commits/$COMMIT"; printf '502' > "$SB/api/repos/valkey-io/valkey/commits/$COMMIT.status"
out=$(run); rc=$?
[ "$rc" -eq 2 ] && grep -q "valkey (signed-commit, 9.1.2): not measured: GitHub's verification statement for commit 4a12e725a55a at http://127.0.0.1:$PORT/repos/valkey-io/valkey/commits/$COMMIT: HTTP 502: Server Error, after 4 attempts (Req 3.13)" <<<"$out" && pass "a persistent 502 is not measured after four attempts" || fail "502" "rc=$rc" "$out"
[ "$(grep -c "^/repos/valkey-io/valkey/commits/$COMMIT " "$SB/auth.log")" -eq 4 ] && pass "four requests, no more" || fail "request count" "$(cat "$SB/auth.log")"
[ "$(grep -c "^retrying " <<<"$out")" -eq 3 ] && pass "three retries logged" || fail "retry lines" "$out"
stop_api
# Retry-After sets the rest (1s here, observed in the log), and is capped by DHC_RETRY_AFTER_CAP
fresh; serve_api
git_def valkey signed-commit valkey-io/valkey 9.1.2 "$COMMIT"; refs "refs/tags/9.1.2^{}|" "refs/tags/9.1.2|$COMMIT"; verification commit valkey-io/valkey "$COMMIT" true valid
printf '429 200' > "$SB/api/repos/valkey-io/valkey/commits/$COMMIT.status"; printf 'Retry-After: 1\n' > "$SB/api/repos/valkey-io/valkey/commits/$COMMIT.headers"
out=$(run); rc=$?
[ "$rc" -eq 0 ] && grep -q "retrying http://127.0.0.1:$PORT/repos/valkey-io/valkey/commits/$COMMIT in 1s, as Retry-After asks (attempt 2 of 4): HTTP 429" <<<"$out" && pass "a Retry-After header sets the rest" || fail "retry-after" "rc=$rc" "$out"
printf 'Retry-After: 500\n' > "$SB/api/repos/valkey-io/valkey/commits/$COMMIT.headers"; printf '429 200' > "$SB/api/repos/valkey-io/valkey/commits/$COMMIT.status"
stop_api; serve_api # a fresh server, so the status sequence starts over
out=$(run); rc=$?
[ "$rc" -eq 0 ] && grep -q "in 2s, Retry-After asked 500s (attempt 2 of 4): HTTP 429" <<<"$out" && pass "a long Retry-After is capped, both numbers named" || fail "retry-after cap" "rc=$rc" "$out"
stop_api

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES test(s) failed"; exit 1; fi
echo "all check-authenticity tests passed"
