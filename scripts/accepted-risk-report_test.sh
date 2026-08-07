#!/usr/bin/env bash
# Tests for scripts/accepted-risk-report.sh — Req 6.26, 6.27.
#
# The gate's suppression table is the only place a reviewer sees what an
# acceptance actually covered. Req 6.27 puts the binary in it, because an entry
# scoped too broadly and one scoped correctly produce the same count. Req 6.26
# reports an entry that suppressed nothing, which is what a typo'd path looks
# like — Trivy accepts it, matches nothing, warns nobody and exits 0.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPORT="$HERE/accepted-risk-report.sh"
FAILURES=0
SB=""

fresh() { SB=$(mktemp -d); }

# A Trivy report carrying one suppression, attributed the way Trivy 0.72.0
# attributes it: Target names the binary, Statement names the entry.
trivy_with() { # $1 = target, $2 = cve, $3 = statement
  cat > "$SB/trivy.json" <<JSON
{"Results":[{"Target":"$1","ExperimentalModifiedFindings":[
  {"Type":"vulnerability","Status":"ignored","Source":"triage/accepted-risk/grafana.yaml",
   "Statement":"$3","Finding":{"VulnerabilityID":"$2","PkgName":"stdlib"}}]}]}
JSON
}
trivy_empty() { printf '{"Results":[]}\n' > "$SB/trivy.json"; }

entry() { # $1 = cve, $2 = path, $3 = statement
  cat > "$SB/accepted.yaml" <<YAML
vulnerabilities:
  - id: $1
    paths: ["$2"]
    statement: "$3"
YAML
}

expect() { # name, substring that must appear
  local name="$1" want="$2" out
  out=$("$REPORT" "$SB/trivy.json" "$SB/accepted.yaml" 2>&1)
  if grep -qF "$want" <<<"$out"; then echo "ok   $name"
  else echo "FAIL $name: missing '$want'"; echo "$out" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); fi
}
refute() { # name, substring that must NOT appear
  local name="$1" bad="$2" out
  out=$("$REPORT" "$SB/trivy.json" "$SB/accepted.yaml" 2>&1)
  if grep -qF "$bad" <<<"$out"; then
    echo "FAIL $name: should not contain '$bad'"; echo "$out" | sed 's/^/    /'; FAILURES=$((FAILURES+1))
  else echo "ok   $name"; fi
}

# --- Req 6.27: the table names the binary -----------------------------------

# 1: two entries scoped to different binaries and one scoped to both produce
#    identical counts. The binary is what tells them apart.
fresh
trivy_with "usr/share/grafana/data/plugins-bundled/zipkin/gpx_x_linux_amd64" "CVE-2026-27145" "transfer: waiting on the zipkin release"
entry "CVE-2026-27145" "usr/share/grafana/data/plugins-bundled/zipkin/*" "transfer: waiting on the zipkin release"
expect "suppression names its binary" "plugins-bundled/zipkin"
expect "suppression names its CVE" "CVE-2026-27145"

# --- Req 6.26: an entry that suppressed nothing is reported ------------------

# 2: the typo case. Trivy matched nothing and said nothing; only a comparison
#    against the file can notice.
fresh
trivy_empty
entry "CVE-2026-27145" "usr/share/grafana/data/plugins-bundled/elasticsaerch/*" "transfer: typo'd path"
expect "dead entry is reported" "CVE-2026-27145"
expect "dead entry cites the requirement" "Req 6.26"

# 3: an entry that did its job is not reported as dead
fresh
trivy_with "usr/share/grafana/data/plugins-bundled/zipkin/gpx_x_linux_amd64" "CVE-2026-27145" "transfer: waiting on the zipkin release"
entry "CVE-2026-27145" "usr/share/grafana/data/plugins-bundled/zipkin/*" "transfer: waiting on the zipkin release"
# Anchored first: without this the refute below passes on empty output.
expect "live entry still renders its row" "plugins-bundled/zipkin"
refute "live entry is not called dead" "Req 6.26"

# 4: one live and one dead entry — the dead one is named, the live one is not
fresh
trivy_with "usr/share/grafana/data/plugins-bundled/zipkin/gpx_x_linux_amd64" "CVE-2026-27145" "transfer: zipkin"
cat > "$SB/accepted.yaml" <<'YAML'
vulnerabilities:
  - id: CVE-2026-27145
    paths: ["usr/share/grafana/data/plugins-bundled/zipkin/*"]
    statement: "transfer: zipkin"
  - id: CVE-2026-42504
    paths: ["usr/share/grafana/data/plugins-bundled/elasticsearch/*"]
    statement: "transfer: elasticsearch"
YAML
expect "the dead one of two is named" "CVE-2026-42504"

# 5: no accepted-risk file is not an error — nothing is being suppressed
fresh
trivy_empty
out=$("$REPORT" "$SB/trivy.json" "$SB/missing.yaml" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then echo "ok   absent lane file exits 0"
else echo "FAIL absent lane file: exit $rc"; echo "$out" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); fi

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES test(s) failed"; exit 1; fi
echo "all tests passed"
