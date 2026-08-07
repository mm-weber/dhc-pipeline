#!/usr/bin/env bash
# Tests for scripts/govulncheck-report.sh — self-contained sandbox, no fixture
# files, no network, no Go, no docker.
#
# This report is the only thing in the pipeline that answers "is the vulnerable
# code actually called". Trivy and Grype answer "is this module linked", and Req
# 6.14 hangs a prohibition on the difference: a *reachable* symbol forbids a
# `not_affected` / `vulnerable_code_not_in_execute_path` statement for that
# image. So the cases below are organised around the two ways this report can do
# damage:
#
#   (a) FALSE EXONERATION — rendering silence as absence. A module-level finding
#       means govulncheck could not measure, which is also exactly what a
#       stripped binary looks like. Reported as "not reachable" it licenses the
#       suppression Req 6.14 exists to forbid.
#   (b) SILENT DISAPPEARANCE — a real finding that never reaches the table:
#       dropped by a failed advisory join, collapsed away by a duplicate at a
#       coarser granularity, attributed to the wrong binary, or hidden behind an
#       unrelated input error.
#
# Contract under test:
#     scripts/govulncheck-report.sh <label>=<file> [<label>=<file> ...]
# where <file> holds one binary's `govulncheck -mode=binary -format json`
# output and <label> is that binary's path inside the image. Output is markdown
# for a GitHub Actions job summary: one section per input, introduced by a line
# carrying the label verbatim, in argument order, followed by that binary's
# rows. Level vocabulary is fixed by the legend build.yml already prints
# alongside this table: `symbol`, `package`, `not measured`.
#
# It is a REPORTER, not a gate (design.md, "Reachability evidence"): findings —
# however reachable — must not change its exit status. Only broken *input* does.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPORT="$HERE/govulncheck-report.sh"
FAILURES=0
TOTAL=0
ARGS=()

# --- harness -----------------------------------------------------------------

# Every assertion re-runs the script, so a failure names one rule and nothing
# else. ARGS is empty for the no-argument case, hence the +expansion guard.
_run() {
  TOTAL=$((TOTAL+1))
  OUT=$("$REPORT" ${ARGS[@]+"${ARGS[@]}"} 2>&1); RC=$?
}

_fail() { # name, message, context
  echo "FAIL $1: $2"; echo "$3" | sed 's/^/    /'
  FAILURES=$((FAILURES+1))
}

# expected is a number, or the literal 'nonzero' — the error cases care that the
# script refuses, not which code it picks. 126/127 is never a refusal: an
# unfindable or non-executable script would otherwise satisfy every 'nonzero'
# case and report a green RED.
_check_rc() { # name, expected
  if [ "$RC" -eq 126 ] || [ "$RC" -eq 127 ]; then
    _fail "$1" "exit $RC — $REPORT is missing or not executable" "$OUT"; return 1
  fi
  if [ "$2" = "nonzero" ]; then
    if [ "$RC" -eq 0 ]; then _fail "$1" "exit 0, expected non-zero" "$OUT"; return 1; fi
  elif [ "$RC" -ne "$2" ]; then
    _fail "$1" "exit $RC, expected $2" "$OUT"; return 1
  fi
  return 0
}

run_case() { # name, expected_exit, expect_substring(optional)
  local name="$1" expected="$2" substr="${3:-}"
  _run
  _check_rc "$name" "$expected" || return
  if [ -n "$substr" ] && ! grep -qF -- "$substr" <<<"$OUT"; then
    _fail "$name" "output missing '$substr'" "$OUT"; return
  fi
  echo "ok   $name"
}

refute_case() { # name, expected_exit, forbidden_substring
  local name="$1" expected="$2" substr="$3"
  _run
  _check_rc "$name" "$expected" || return
  if grep -qF -- "$substr" <<<"$OUT"; then
    _fail "$name" "output must not contain '$substr'" "$OUT"; return
  fi
  echo "ok   $name"
}

# The level, the module and the aliases all belong to one finding, so they must
# be asserted on that finding's own line. "the word symbol appears somewhere in
# the report" is not the same claim as "THIS finding is reported as reachable".
_row() { grep -F -- "$1" <<<"$OUT"; }

row_case() { # name, osv_id, expect_substring
  local name="$1" id="$2" substr="$3" row
  _run
  _check_rc "$name" 0 || return
  row=$(_row "$id")
  if [ -z "$row" ]; then _fail "$name" "no row for $id" "$OUT"; return; fi
  if ! grep -qF -- "$substr" <<<"$row"; then
    _fail "$name" "row for $id missing '$substr'" "$row"; return
  fi
  echo "ok   $name"
}

# A missing row fails here too: a finding that vanished is not a finding that
# was correctly refused a label.
refute_row_case() { # name, osv_id, forbidden_substring
  local name="$1" id="$2" substr="$3" row
  _run
  _check_rc "$name" 0 || return
  row=$(_row "$id")
  if [ -z "$row" ]; then _fail "$name" "no row for $id" "$OUT"; return; fi
  if grep -qF -- "$substr" <<<"$row"; then
    _fail "$name" "row for $id must not contain '$substr'" "$row"; return
  fi
  echo "ok   $name"
}

count_case() { # name, substring, expected_line_count
  local name="$1" substr="$2" want="$3" got
  _run
  _check_rc "$name" 0 || return
  got=$(grep -cF -- "$substr" <<<"$OUT") || true
  if [ "$got" -ne "$want" ]; then
    _fail "$name" "$got line(s) contain '$substr', expected $want" "$OUT"; return
  fi
  echo "ok   $name"
}

# Lines strictly after the line carrying $1, up to (excluding) the line carrying
# $2. Empty $2 means "to the end of the report".
_section() { # start_marker, end_marker
  local sec
  sec=$(awk -v s="$1" 'f { print } index($0, s) { f = 1 }' <<<"$OUT")
  if [ -n "$2" ]; then sec=$(awk -v e="$2" 'index($0, e) { exit } { print }' <<<"$sec"); fi
  printf '%s\n' "$sec"
}

section_case() { # name, start_marker, end_marker, expect_substring
  local name="$1" sec
  _run
  _check_rc "$name" 0 || return
  sec=$(_section "$2" "$3")
  if ! grep -qF -- "$4" <<<"$sec"; then
    _fail "$name" "section after '$2' missing '$4'" "$sec"; return
  fi
  echo "ok   $name"
}

refute_section_case() { # name, start_marker, end_marker, forbidden_substring
  local name="$1" sec
  _run
  _check_rc "$name" 0 || return
  sec=$(_section "$2" "$3")
  if grep -qF -- "$4" <<<"$sec"; then
    _fail "$name" "section after '$2' must not contain '$4'" "$sec"; return
  fi
  echo "ok   $name"
}

order_case() { # name, must_come_first, must_come_after
  local name="$1" a b
  _run
  _check_rc "$name" 0 || return
  a=$(grep -nF -- "$2" <<<"$OUT" | head -n1 | cut -d: -f1)
  b=$(grep -nF -- "$3" <<<"$OUT" | head -n1 | cut -d: -f1)
  if [ -z "$a" ] || [ -z "$b" ]; then
    _fail "$name" "expected both '$2' and '$3' in the output" "$OUT"; return
  fi
  if [ "$a" -ge "$b" ]; then
    _fail "$name" "'$2' (line $a) must precede '$3' (line $b)" "$OUT"; return
  fi
  echo "ok   $name"
}

# --- fixtures ----------------------------------------------------------------

fresh() { SB=$(mktemp -d); ARGS=(); }
add_bin() { ARGS+=("$1=$SB/$2"); } # label, file name inside the sandbox

# govulncheck -format json is a stream of bare JSON objects, not an array, and
# every scan opens with config + progress noise that carries no finding.
hdr() {
  printf '%s\n' \
    '{"config":{"protocol_version":"v1.0.0","scanner_name":"govulncheck","scanner_version":"v1.1.4","db":"https://vuln.go.dev","db_last_modified":"2026-07-20T17:52:41Z","scan_level":"symbol","scan_mode":"binary"}}' \
    '{"progress":{"message":"Scanning your binary for known vulnerabilities..."}}'
}

osv() { # id, aliases_json_array
  printf '{"osv":{"schema_version":"1.3.1","id":"%s","modified":"2026-07-01T00:00:00Z","published":"2026-06-02T00:00:00Z","aliases":%s,"summary":"summary of %s"}}\n' \
    "$1" "$2" "$1"
}
osv_no_alias_key() { # id — govulncheck omits the field entirely when there are none
  printf '{"osv":{"schema_version":"1.3.1","id":"%s","summary":"summary of %s"}}\n' "$1" "$1"
}

# trace[0] is the vulnerable end; anything after it is the call path back to our
# own code. The three builders below differ only in how far trace[0] resolves,
# which is the entire discriminator this report rests on.
f_module() { # osv, module, version
  printf '{"finding":{"osv":"%s","trace":[{"module":"%s","version":"%s"}]}}\n' "$1" "$2" "$3"
}
f_package() { # osv, module, version, package
  printf '{"finding":{"osv":"%s","fixed_version":"v0.132.0","trace":[{"module":"%s","version":"%s","package":"%s"}]}}\n' \
    "$1" "$2" "$3" "$4"
}
f_symbol() { # osv, module, version, package, function, caller_function
  printf '{"finding":{"osv":"%s","fixed_version":"v0.132.0","trace":[{"module":"%s","version":"%s","package":"%s","function":"%s"},{"module":"github.com/mm-weber/app","package":"main","function":"%s"}]}}\n' \
    "$1" "$2" "$3" "$4" "$5" "$6"
}

KIN="github.com/getkin/kin-openapi"
KINV="v0.131.0"
KINPKG="github.com/getkin/kin-openapi/openapi3filter"
KINFN="ValidationHandler.ServeHTTP"
CALLER="AppEntrypointCallerFn"

OSV1="GO-2026-5037"
CVE1="CVE-2026-27145"
GHSA1="GHSA-7q2f-vxc3-9m2p"
OSV2="GO-2026-4144"
CVE2="CVE-2026-31337"
OSV3="GO-2026-3011"
OSV4="GO-2026-2002"

GRAFANA_BIN="usr/share/grafana/bin/grafana"

# =============================================================================
# 1. A reachable finding — the row Req 6.14 turns on
# =============================================================================

fresh
{ hdr
  osv "$OSV1" "[\"$GHSA1\",\"$CVE1\"]"
  f_symbol "$OSV1" "$KIN" "$KINV" "$KINPKG" "$KINFN" "$CALLER"
} > "$SB/a.json"
add_bin "$GRAFANA_BIN" a.json

# It is evidence, not a gate. Trivy is the only thing allowed to fail a build;
# a reporter that exits non-zero on findings is a second gate nobody designed.
run_case "findings do not fail the report" 0
run_case "the binary is named" 0 "$GRAFANA_BIN"
row_case "a resolved function is levelled 'symbol'" "$OSV1" "symbol"
# Req 6.15 wants the measurement citable in triage/LOG.md; a level with no
# symbol behind it is an assertion the reader cannot check.
row_case "the reachable symbol is named" "$OSV1" "$KINFN"
# Trivy reports CVE/GHSA, govulncheck reports GO ids. Without the alias on the
# row the two reports cannot be joined and the evidence is unusable.
row_case "the row carries the CVE alias" "$OSV1" "$CVE1"
row_case "the row carries the GHSA alias" "$OSV1" "$GHSA1"
row_case "the row names the module" "$OSV1" "$KIN"
# Which version is linked decides whether the published fix is already in.
row_case "the row names the linked version" "$OSV1" "$KINV"
run_case "rows render as a markdown table" 0 "|"
refute_case "a reachable finding is never called unreachable" 0 "unreachable"

# =============================================================================
# 2. The three levels, read off trace[0]
# =============================================================================

# package-level is undecided, not safe.
fresh
{ hdr; osv "$OSV1" "[\"$CVE1\"]"; f_package "$OSV1" "$KIN" "$KINV" "$KINPKG"; } > "$SB/a.json"
add_bin "$GRAFANA_BIN" a.json
row_case "an unresolved package is levelled 'package'" "$OSV1" "package"
refute_row_case "undecided is not promoted to reachable" "$OSV1" "symbol"

# module-level is silence: govulncheck could not measure. A stripped binary
# produces exactly this, so rendering it as absence is the false exoneration
# Req 6.14 exists to prevent.
fresh
{ hdr; osv "$OSV1" "[\"$CVE1\"]"; f_module "$OSV1" "$KIN" "$KINV"; } > "$SB/a.json"
add_bin "$GRAFANA_BIN" a.json
row_case "a module-only finding is levelled 'not measured'" "$OSV1" "not measured"
refute_case "silence is never rendered as 'not reachable'" 0 "not reachable"
refute_case "silence is never rendered as 'unreachable'" 0 "unreachable"
refute_row_case "silence is not promoted to reachable" "$OSV1" "symbol"

# The trace is ordered outward from the vulnerable end. Scanning the whole trace
# for a function finds OUR caller and reports it as the vulnerable symbol —
# reachability manufactured out of the fact that the module is linked at all.
fresh
{ hdr
  osv "$OSV1" "[\"$CVE1\"]"
  printf '{"finding":{"osv":"%s","trace":[{"module":"%s","version":"%s"},{"module":"github.com/mm-weber/app","package":"main","function":"%s"}]}}\n' \
    "$OSV1" "$KIN" "$KINV" "$CALLER"
} > "$SB/a.json"
add_bin "$GRAFANA_BIN" a.json
row_case "the level is read off trace[0], not the whole trace" "$OSV1" "not measured"
refute_row_case "a caller's function is not the vulnerable symbol" "$OSV1" "$CALLER"

# =============================================================================
# 3. Collapsing the several findings govulncheck emits per vulnerability
# =============================================================================

# govulncheck routinely emits one module-level and one symbol-level finding for
# the same vulnerability. Two rows means the reader can quote the "not measured"
# one; and whichever row wins must not depend on emission order.
fresh
{ hdr
  osv "$OSV1" "[\"$CVE1\"]"
  f_module "$OSV1" "$KIN" "$KINV"
  f_symbol "$OSV1" "$KIN" "$KINV" "$KINPKG" "$KINFN" "$CALLER"
} > "$SB/a.json"
add_bin "$GRAFANA_BIN" a.json
count_case "module-then-symbol collapses to one row" "$OSV1" 1
row_case "the resolved level wins over the coarse one" "$OSV1" "symbol"

fresh
{ hdr
  osv "$OSV1" "[\"$CVE1\"]"
  f_symbol "$OSV1" "$KIN" "$KINV" "$KINPKG" "$KINFN" "$CALLER"
  f_module "$OSV1" "$KIN" "$KINV"
} > "$SB/a.json"
add_bin "$GRAFANA_BIN" a.json
count_case "symbol-then-module collapses to one row" "$OSV1" 1
# The last-writer-wins bug: a trailing module-level finding demotes a proven
# reachable symbol to "not measured" and licenses the forbidden suppression.
row_case "a later coarse finding cannot demote a reachable one" "$OSV1" "symbol"
refute_row_case "the collapsed row is not 'not measured'" "$OSV1" "not measured"

fresh
{ hdr; osv "$OSV1" "[\"$CVE1\"]"
  f_module "$OSV1" "$KIN" "$KINV"
  f_package "$OSV1" "$KIN" "$KINV" "$KINPKG"
} > "$SB/a.json"
add_bin "$GRAFANA_BIN" a.json
row_case "package outranks module" "$OSV1" "package"
count_case "module+package collapse to one row" "$OSV1" 1

fresh
{ hdr; osv "$OSV1" "[\"$CVE1\"]"
  f_package "$OSV1" "$KIN" "$KINV" "$KINPKG"
  f_symbol "$OSV1" "$KIN" "$KINV" "$KINPKG" "$KINFN" "$CALLER"
} > "$SB/a.json"
add_bin "$GRAFANA_BIN" a.json
row_case "symbol outranks package" "$OSV1" "symbol"

# One finding per distinct call path is normal output, not four vulnerabilities.
fresh
{ hdr; osv "$OSV1" "[\"$CVE1\"]"
  f_symbol "$OSV1" "$KIN" "$KINV" "$KINPKG" "$KINFN" "${CALLER}A"
  f_symbol "$OSV1" "$KIN" "$KINV" "$KINPKG" "$KINFN" "${CALLER}B"
} > "$SB/a.json"
add_bin "$GRAFANA_BIN" a.json
count_case "repeated call paths collapse to one row" "$OSV1" 1

# =============================================================================
# 4. The advisory join — where findings silently disappear
# =============================================================================

# aliases:[] and a missing aliases key are both real govulncheck output. Either
# one dropping the row deletes a vulnerability from the evidence.
fresh
{ hdr; osv "$OSV3" "[]"; f_symbol "$OSV3" "$KIN" "$KINV" "$KINPKG" "$KINFN" "$CALLER"; } > "$SB/a.json"
add_bin "$GRAFANA_BIN" a.json
row_case "an advisory with no aliases still gets a row" "$OSV3" "symbol"

fresh
{ hdr; osv_no_alias_key "$OSV3"; f_symbol "$OSV3" "$KIN" "$KINV" "$KINPKG" "$KINFN" "$CALLER"; } > "$SB/a.json"
add_bin "$GRAFANA_BIN" a.json
row_case "a missing aliases field still gets a row" "$OSV3" "symbol"

# An inner-join implementation loses the finding entirely when the advisory
# object is absent — the worst silent-disappearance failure, because the report
# then looks clean.
fresh
{ hdr; f_symbol "$OSV4" "$KIN" "$KINV" "$KINPKG" "$KINFN" "$CALLER"; } > "$SB/a.json"
add_bin "$GRAFANA_BIN" a.json
run_case "a finding with no advisory object is still reported" 0 "$OSV4"
row_case "…and is still levelled from its own trace" "$OSV4" "symbol"

# The mirror image: rows come from findings, not from the advisory stream. An
# advisory with no finding is a vulnerability this binary does not have.
fresh
{ hdr
  osv "$OSV2" "[\"$CVE2\"]"
  osv "$OSV1" "[\"$CVE1\"]"
  f_symbol "$OSV1" "$KIN" "$KINV" "$KINPKG" "$KINFN" "$CALLER"
} > "$SB/a.json"
add_bin "$GRAFANA_BIN" a.json
refute_case "an advisory with no finding is not reported" 0 "$OSV2"
refute_case "…and neither is its alias" 0 "$CVE2"

# =============================================================================
# 5. Ordering and shape
# =============================================================================

# The row that forbids a suppression must not be buried below the rows that
# prove nothing. Emission order here is the reverse of the required order.
fresh
{ hdr
  osv "$OSV2" "[\"$CVE2\"]"; f_module "$OSV2" "golang.org/x/net" "v0.38.0"
  osv "$OSV1" "[\"$CVE1\"]"; f_symbol "$OSV1" "$KIN" "$KINV" "$KINPKG" "$KINFN" "$CALLER"
} > "$SB/a.json"
add_bin "$GRAFANA_BIN" a.json
run_case "an unmeasurable finding is still listed" 0 "$OSV2"
order_case "reachable rows come before unmeasured ones" "$OSV1" "$OSV2"

# govulncheck pretty-prints its JSON stream: bare objects spanning many lines,
# with no separators. Line-oriented parsing appears to work on compact fixtures
# and reports nothing at all against real output.
fresh
cat > "$SB/pretty.json" <<PRETTY
{
  "config": {
    "protocol_version": "v1.0.0",
    "scanner_name": "govulncheck",
    "scan_mode": "binary"
  }
}
{
  "osv": {
    "id": "$OSV1",
    "aliases": [
      "$GHSA1",
      "$CVE1"
    ],
    "summary": "fail-open ValidationHandler"
  }
}
{
  "finding": {
    "osv": "$OSV1",
    "fixed_version": "v0.132.0",
    "trace": [
      {
        "module": "$KIN",
        "version": "$KINV",
        "package": "$KINPKG",
        "function": "$KINFN"
      },
      {
        "module": "github.com/mm-weber/app",
        "package": "main",
        "function": "$CALLER"
      }
    ]
  }
}
PRETTY
add_bin "$GRAFANA_BIN" pretty.json
run_case "a pretty-printed stream is parsed" 0 "$CVE1"
row_case "a pretty-printed stream levels identically" "$OSV1" "symbol"

# =============================================================================
# 6. Several binaries — attribution is per image path, never global
# =============================================================================

fresh
{ hdr; osv "$OSV1" "[\"$CVE1\"]"; f_symbol "$OSV1" "$KIN" "$KINV" "$KINPKG" "$KINFN" "$CALLER"; } > "$SB/a.json"
{ hdr; osv "$OSV2" "[\"$CVE2\"]"; f_symbol "$OSV2" "golang.org/x/net" "v0.38.0" "golang.org/x/net/http2" "Server.ServeConn" "$CALLER"; } > "$SB/b.json"
add_bin "usr/bin/alpha" a.json
add_bin "usr/bin/beta"  b.json
run_case "the first binary is named" 0 "usr/bin/alpha"
run_case "the second binary is named" 0 "usr/bin/beta"
section_case "each finding sits under its own binary" "usr/bin/alpha" "usr/bin/beta" "$OSV1"
section_case "…and so does the second" "usr/bin/beta" "" "$OSV2"
# Cross-attribution sends triage at the wrong image, and clears the right one.
refute_section_case "a finding is not attributed to the other binary" "usr/bin/beta" "" "$OSV1"

# The same vulnerability can be reachable in one binary and unmeasurable in
# another. Collapsing on the OSV id alone, without the binary, makes one of the
# two answers overwrite the other — in one direction a false exoneration, in the
# other a false alarm.
fresh
{ hdr; osv "$OSV1" "[\"$CVE1\"]"; f_symbol "$OSV1" "$KIN" "$KINV" "$KINPKG" "$KINFN" "$CALLER"; } > "$SB/a.json"
{ hdr; osv "$OSV1" "[\"$CVE1\"]"; f_module "$OSV1" "$KIN" "$KINV"; } > "$SB/b.json"
add_bin "usr/bin/alpha" a.json
add_bin "usr/bin/beta"  b.json
section_case "reachable in the binary that resolved it" "usr/bin/alpha" "usr/bin/beta" "symbol"
section_case "unmeasured in the binary that did not" "usr/bin/beta" "" "not measured"
refute_section_case "an unmeasured sibling does not demote the reachable binary" \
  "usr/bin/alpha" "usr/bin/beta" "not measured"

# Sections follow the caller's argument order: build.yml walks the rootfs, and
# that walk order is what groups a component with its bundled plugins.
fresh
{ hdr; osv "$OSV1" "[\"$CVE1\"]"; f_symbol "$OSV1" "$KIN" "$KINV" "$KINPKG" "$KINFN" "$CALLER"; } > "$SB/a.json"
{ hdr; osv "$OSV2" "[\"$CVE2\"]"; f_module "$OSV2" "golang.org/x/net" "v0.38.0"; } > "$SB/b.json"
add_bin "usr/bin/beta"  b.json
add_bin "usr/bin/alpha" a.json
order_case "sections follow argument order" "usr/bin/beta" "usr/bin/alpha"

# A binary govulncheck cleared still has to appear: "we looked and found
# nothing" and "we never looked" are different claims, and only the first one is
# evidence.
fresh
hdr > "$SB/clean.json"
add_bin "usr/bin/clean" clean.json
run_case "a clean binary is still named" 0 "usr/bin/clean"
refute_case "a clean binary reports no findings" 0 "GO-"

# =============================================================================
# 7. Input handling — a report that cannot be produced must not look empty
# =============================================================================

fresh
run_case "no arguments fails" nonzero
run_case "no arguments explains the contract" nonzero "label"

fresh
{ hdr; f_module "$OSV1" "$KIN" "$KINV"; } > "$SB/a.json"
ARGS=("$SB/a.json")
run_case "an argument without '=' fails" nonzero
run_case "…and the bad argument is named" nonzero "$SB/a.json"

fresh
{ hdr; f_module "$OSV1" "$KIN" "$KINV"; } > "$SB/a.json"
ARGS=("=$SB/a.json")
run_case "an empty label fails" nonzero

fresh
ARGS=("usr/bin/alpha=")
run_case "an empty path fails" nonzero

# A scan output that is not there is not a clean scan.
fresh
ARGS=("usr/bin/alpha=$SB/missing.json")
run_case "a missing file fails" nonzero
run_case "…and the missing file is named" nonzero "$SB/missing.json"

# govulncheck always emits at least a config object; zero bytes means it never
# ran. Rendering that as an empty findings table is a false exoneration handed
# to the reader with no warning attached.
fresh
: > "$SB/empty.json"
ARGS=("usr/bin/alpha=$SB/empty.json")
run_case "an empty file fails" nonzero
run_case "…and the empty file's binary is named" nonzero "usr/bin/alpha"

# A truncated stream — killed scan, full disk — parses partially. Ignoring the
# parse error silently drops every finding after the cut.
fresh
{ hdr
  osv "$OSV1" "[\"$CVE1\"]"
  printf '{"finding":{"osv":"%s","trace":[{"module":' "$OSV1"
} > "$SB/trunc.json"
ARGS=("usr/bin/alpha=$SB/trunc.json")
run_case "a truncated stream fails" nonzero
run_case "…and the truncated stream's binary is named" nonzero "usr/bin/alpha"

# One unreadable input must not take the whole report down with it: the other
# binaries were measured, and their findings are the reason the step ran.
fresh
{ hdr; osv "$OSV1" "[\"$CVE1\"]"; f_symbol "$OSV1" "$KIN" "$KINV" "$KINPKG" "$KINFN" "$CALLER"; } > "$SB/a.json"
ARGS=("usr/bin/alpha=$SB/a.json" "usr/bin/beta=$SB/missing.json")
run_case "a broken input among good ones still fails" nonzero
run_case "…and does not hide the measured binary's findings" nonzero "$OSV1"
run_case "…and still names the good binary" nonzero "usr/bin/alpha"

# The label is a path out of the image and the file is a name the caller
# generated from it, so '=' can appear in either half. Splitting on the last '='
# opens the wrong file and reports a binary that was never scanned.
fresh
{ hdr; osv "$OSV1" "[\"$CVE1\"]"; f_symbol "$OSV1" "$KIN" "$KINV" "$KINPKG" "$KINFN" "$CALLER"; } > "$SB/plug=in.json"
add_bin "usr/bin/alpha" "plug=in.json"
run_case "a path containing '=' is opened, not mangled" 0 "$OSV1"

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "all $TOTAL govulncheck-report assertions passed"
else
  echo "$FAILURES of $TOTAL govulncheck-report assertions failed"
fi
exit $((FAILURES > 0))
