#!/usr/bin/env bash
# Tests for scripts/scan-image.sh: the one scan both arms call.
#
# Why one script rather than a step per arm (task 9.1): the pull request gate
# and the release-time scan must apply the SAME inputs, or the gate stops
# predicting what release does. Two copies of a long trivy invocation drift on
# the first flag either one gains, and the drift is invisible: a scan missing
# --vex reports findings that are covered, a scan missing --ignorefile fails on
# accepted risk, and both look like a real result.
#
# Trivy itself is stubbed here: what this suite pins is the invocation and the
# refusals, not Trivy's matching, which ADR 0003 and the compiler tests cover.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCAN="$HERE/scan-image.sh"
FAILURES=0

pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }
has()  { grep -qF -- "$2" "$SB/argv" && pass "$1" || fail "$1" "$(cat "$SB/argv")"; }
hasnt() { grep -qF -- "$2" "$SB/argv" && fail "$1" "$(cat "$SB/argv")" || pass "$1"; }

REF="ghcr.io/mm-weber/dhc/grafana@sha256:b6987eb3910fe3f4a05011f76f76c5d56728017a6db1afb491d7f4ba51ff182e"

fresh() { # sandbox with a compiled vex dir, an exception file and a stub trivy
  SB=$(mktemp -d)
  mkdir -p "$SB/vex" "$SB/triage/accepted-risk" "$SB/bin"
  printf '{"statements":[]}\n' > "$SB/vex/grafana.openvex.json"
  cat > "$SB/bin/trivy" <<'STUB'
#!/usr/bin/env bash
# Record the invocation, then write the report trivy would have written.
printf '%s\n' "$@" > "${STUB_ARGV}"
out=""
prev=""
for a in "$@"; do
  [ "$prev" = "--output" ] && out="$a"
  prev="$a"
done
[ -n "${STUB_NO_REPORT:-}" ] || printf '{"SchemaVersion":2,"CreatedAt":"2026-08-28T06:00:00Z","Results":[]}\n' > "$out"
exit "${STUB_RC:-0}"
STUB
  chmod +x "$SB/bin/trivy"
  export STUB_ARGV="$SB/argv"
}

run() { # extra args after the fixed four
  PATH="$SB/bin:$PATH" "$SCAN" "$REF" grafana "$SB/vex" "$SB/report.json" "$@" 2>&1
}

# 1: the compiled documents and the exception file are both applied, and the
#    report shape is the one both arms attest (Req 2.8, 6.55).
fresh
printf 'exceptions: []\n' > "$SB/triage/accepted-risk/grafana.yaml"
out=$(cd "$SB" && run); rc=$?
[ "$rc" -eq 0 ] && pass "a clean scan exits 0" || fail "a clean scan exits 0" "$out"
has "applies the compiled document"   "--vex"
has "by path"                          "$SB/vex/grafana.openvex.json"
has "applies the accepted-risk file"   "--ignorefile"
has "by path"                          "triage/accepted-risk/grafana.yaml"
has "keeps suppressed findings"        "--show-suppressed"
has "writes json"                      "--format"
has "to the named report"              "$SB/report.json"
has "within the decision aperture"     "HIGH,CRITICAL"
has "over os and library packages"     "os,library"
has "never fails on findings itself"   "--exit-code"
has "and names the ref last"           "$REF"
check_last=$(tail -1 "$SB/argv")
[ "$check_last" = "$REF" ] && pass "the ref is the final argument" || fail "the ref is the final argument" "$check_last"

# 2: no exception file is a normal state (most definitions have none), and it
#    must not silently turn into an empty --ignorefile.
fresh
out=$(cd "$SB" && run); rc=$?
[ "$rc" -eq 0 ] && pass "no exception file still scans" || fail "no exception file still scans" "$out"
hasnt "and passes no --ignorefile" "--ignorefile"

# 3: several compiled documents each arrive as their own --vex.
fresh
printf '{"statements":[]}\n' > "$SB/vex/second.json"
(cd "$SB" && run) >/dev/null
n=$(grep -cF -- "--vex" "$SB/argv")
[ "$n" = "2" ] && pass "one --vex per compiled document" || fail "one --vex per compiled document" "got $n"

# 4: an empty vex dir is not a failure: ADR 0003 says a digest can legitimately
#    have nothing to say, and the scan still has to run.
fresh
rm -f "$SB/vex"/*.json
out=$(cd "$SB" && run); rc=$?
[ "$rc" -eq 0 ] && pass "an empty vex dir still scans" || fail "an empty vex dir still scans" "$out"
hasnt "and passes no --vex" "--vex"

# 5: scanning a pushed digest reads the registry, not the local daemon, and
#    scans one named platform manifest (Req 2.8, 2.22).
fresh
(cd "$SB" && run --remote --platform linux/arm64) >/dev/null
has "reads the image from the registry" "--image-src"
has "remotely"                          "remote"
has "for the named platform"            "linux/arm64"

# 6: a trivy failure is a failing scan, named. Req 2.26 turns that into "sign
#    nothing, tag nothing" at the workflow level, which it can only do if the
#    script refuses rather than returning a half report.
fresh
out=$(cd "$SB" && STUB_RC=2 run); rc=$?
[ "$rc" -ne 0 ] && pass "a trivy failure fails the scan" || fail "a trivy failure fails the scan" "$out"
grep -qF "$REF" <<<"$out" && pass "naming the ref" || fail "naming the ref" "$out"

# 7: trivy exiting 0 while writing no report is the shape Req 2.26 is really
#    about: a manifest that ends up with no report at all.
fresh
out=$(cd "$SB" && STUB_NO_REPORT=1 run); rc=$?
[ "$rc" -ne 0 ] && pass "no report written fails the scan" || fail "no report written fails the scan" "$out"
grep -qF "no report" <<<"$out" && pass "saying no report was produced" || fail "saying no report was produced" "$out"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all scan-image tests passed"
