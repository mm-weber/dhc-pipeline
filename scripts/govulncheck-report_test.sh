#!/usr/bin/env bash
# Tests for scripts/govulncheck-report.sh — self-contained sandbox, no network.
#
# The reporter turns govulncheck's JSON stream into the one distinction Trivy
# and Grype cannot make: is the vulnerable SYMBOL reachable, or is the module
# merely linked (Req 6.13). Req 6.14 hangs a prohibition off that answer, so
# every way the answer can be computed wrong is a way a not_affected statement
# can be written that the spec forbids.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPORT="$HERE/govulncheck-report.sh"
FAILURES=0

expect() { # name, expected_exit, expect_substring(optional), args...
  local name="$1" expected="$2" substr="$3"; shift 3
  local out rc
  out=$("$REPORT" "$@" 2>&1); rc=$?
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

refute() { # name, expected_exit, absent_substring, args...
  local name="$1" expected="$2" substr="$3"; shift 3
  local out rc
  out=$("$REPORT" "$@" 2>&1); rc=$?
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

SB=$(mktemp -d)
trap 'rm -rf "$SB"' EXIT

# govulncheck -format json emits a STREAM of bare objects, not an array. Every
# fixture below is written that way on purpose: a reporter that only works after
# someone wraps the stream in brackets does not work on real output.

# A symbol-level finding. govulncheck emits BOTH a module-level finding and a
# symbol-level one for the same OSV — the module row is not a weaker second
# opinion, it is the same vulnerability reported at another granularity.
cat > "$SB/symbol.json" <<'EOF'
{"config":{"scanner_name":"govulncheck","scan_level":"symbol","scan_mode":"binary"}}
{"osv":{"id":"GO-2026-5037","aliases":["CVE-2026-27145"],"summary":"crypto/x509 DoS"}}
{"finding":{"osv":"GO-2026-5037","fixed_version":"v1.26.4","trace":[{"module":"stdlib","version":"v1.26.3"}]}}
{"finding":{"osv":"GO-2026-5037","fixed_version":"v1.26.4","trace":[{"module":"stdlib","version":"v1.26.3","package":"crypto/x509","function":"parseSAN"}]}}
EOF

# Package-level: a package named, no function. Neither reachable nor ruled out.
cat > "$SB/package.json" <<'EOF'
{"osv":{"id":"GO-2026-5039","aliases":["CVE-2026-39822"],"summary":"os.Root traversal"}}
{"finding":{"osv":"GO-2026-5039","trace":[{"module":"stdlib","version":"v1.26.3","package":"os"}]}}
EOF

# Module only — what a stripped binary looks like, and what govulncheck falls
# back to. This must NOT read as "not reachable": it is "not measured".
cat > "$SB/module.json" <<'EOF'
{"osv":{"id":"GO-2026-5970","aliases":["CVE-2026-56852"],"summary":"x/text norm.Iter loop"}}
{"finding":{"osv":"GO-2026-5970","trace":[{"module":"golang.org/x/text","version":"v0.37.0"}]}}
EOF

# A finding whose OSV record never arrived — the alias column has to degrade,
# not drop the row. A dropped row is a vulnerability that silently vanished.
cat > "$SB/no-osv-record.json" <<'EOF'
{"finding":{"osv":"GO-2026-9999","trace":[{"module":"example.com/x","version":"v1.0.0","package":"x","function":"Boom"}]}}
EOF

# Clean binary: config and progress only, no findings at all.
cat > "$SB/clean.json" <<'EOF'
{"config":{"scanner_name":"govulncheck","scan_mode":"binary"}}
{"progress":{"message":"Scanning your binary for known vulnerabilities..."}}
EOF

cat > "$SB/notjson.json" <<'EOF'
this is not json
EOF

echo "== usage and input handling =="
expect "no arguments is a usage error"           2 "usage"
expect "missing file is an error naming it"      1 "nope.json" "bin/x=$SB/nope.json"
expect "malformed json is an error, not silence" 1 "notjson.json" "bin/x=$SB/notjson.json"
expect "argument without = is a usage error"     2 "usage" "$SB/symbol.json"

echo
echo "== reachability level =="
expect "symbol-level finding reports symbol"     0 "symbol"      "bin/grafana=$SB/symbol.json"
expect "package-level finding reports package"   0 "package"     "bin/pkg=$SB/package.json"
expect "module-only finding says NOT measured"   0 "not measured" "bin/mod=$SB/module.json"
refute "module-only must not claim unreachable"  0 "not reachable" "bin/mod=$SB/module.json"

echo
echo "== the strongest level wins per module =="
# Both rows are the same vulnerability in the same module. Reporting the
# module-level row as a separate finding would let a reader answer "is it
# reachable" with the wrong one of two rows that disagree.
expect "one row per osv+module"    0 "1 finding"  "bin/grafana=$SB/symbol.json"
refute "the weaker row is dropped" 0 "not measured" "bin/grafana=$SB/symbol.json"

echo
echo "== identity =="
expect "GO id is shown"              0 "GO-2026-5037"  "bin/grafana=$SB/symbol.json"
expect "CVE alias is shown"          0 "CVE-2026-27145" "bin/grafana=$SB/symbol.json"
expect "module and version shown"    0 "stdlib"        "bin/grafana=$SB/symbol.json"
expect "the reached function is named" 0 "parseSAN"    "bin/grafana=$SB/symbol.json"
expect "a finding with no osv record survives" 0 "GO-2026-9999" "bin/x=$SB/no-osv-record.json"

echo
echo "== multiple binaries =="
expect "first binary labelled"  0 "bin/grafana" "bin/grafana=$SB/symbol.json" "plugins/zipkin=$SB/module.json"
expect "second binary labelled" 0 "plugins/zipkin" "bin/grafana=$SB/symbol.json" "plugins/zipkin=$SB/module.json"

echo
echo "== clean binary =="
expect "no findings is reported, not empty output" 0 "no findings" "bin/clean=$SB/clean.json"
expect "a clean binary still exits 0"              0 ""            "bin/clean=$SB/clean.json"

echo
echo "== reachable findings sort first =="
# The actionable ones. A reader scanning the top of the table must see the
# findings that FORBID a not_affected statement (Req 6.14), not the unmeasured
# ones.
out=$("$REPORT" "z-mod=$SB/module.json" "a-sym=$SB/symbol.json" 2>&1)
if [ "$(grep -n 'symbol' <<<"$out" | head -1 | cut -d: -f1)" -lt \
     "$(grep -n 'not measured' <<<"$out" | head -1 | cut -d: -f1)" ]; then
  echo "ok   reachable rows come before unmeasured ones"
else
  echo "FAIL reachable rows come before unmeasured ones"; echo "$out" | sed 's/^/    /'
  FAILURES=$((FAILURES+1))
fi

echo
if [ "$FAILURES" -eq 0 ]; then echo "govulncheck-report: all assertions passed"; exit 0; fi
echo "govulncheck-report: ${FAILURES} failure(s)"; exit 1
