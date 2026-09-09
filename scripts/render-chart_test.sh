#!/usr/bin/env bash
# Tests for scripts/render-chart.sh: the one command the policy gate renders a
# chart through (Req 4.6). A stub helm records its argv; the real yq reads
# the pin so the quote-stripping that keeps both yq dialects equal is under
# test. Added by review D7: the one script without a suite.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
RENDER="$HERE/render-chart.sh"
FAILURES=0
SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/bin"
cat > "$SB/bin/helm" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${STUB_ARGV:?}"
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$SB/bin/helm"
export PATH="$SB/bin:$PATH" STUB_ARGV="$SB/argv"

run_case() { # name expected_exit dir [substring]
  local name="$1" expected="$2" dir="$3" substr="${4:-}" out rc
  : > "$STUB_ARGV"
  out=$("$RENDER" "$dir" 2>&1); rc=$?
  if [ "$rc" -ne "$expected" ]; then echo "FAIL $name: exit $rc, expected $expected"; echo "$out" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); return; fi
  if [ -n "$substr" ] && ! grep -qF "$substr" <<<"$out"; then echo "FAIL $name: output missing '$substr'"; echo "$out" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); return; fi
  echo "ok   $name"
}
argv_is() { # name expected-argv-lines
  if [ "$(cat "$STUB_ARGV")" != "$2" ]; then echo "FAIL $1: helm argv was"; sed 's/^/    /' "$STUB_ARGV"; echo "  expected"; sed 's/^/    /' <<<"$2"; FAILURES=$((FAILURES+1)); return; fi
  echo "ok   $1"
}

# 1: an owned chart (Chart.yaml) renders from its directory under its own name
mkdir -p "$SB/chart/hardened-app"; printf 'apiVersion: v2\nname: hardened-app\nversion: 0.1.0\n' > "$SB/chart/hardened-app/Chart.yaml"
run_case "owned chart: helm template <name> <dir>" 0 "$SB/chart/hardened-app"
argv_is "owned chart: the argv" "$(printf 'template\nhardened-app\n%s/chart/hardened-app' "$SB")"

# 2: an adapted chart (chart.yaml pin) renders upstream at the pinned version
#    under the dhc- prefix with the hardened overlay, quotes stripped whatever
#    yq dialect printed them
mkdir -p "$SB/chart/valkey/config"
printf 'upstream:\n  name: "valkey"\n  repository: https://valkey-io.github.io/valkey-helm\n  version: "0.12.0"\ndeploys: [valkey]\n' > "$SB/chart/valkey/chart.yaml"
: > "$SB/chart/valkey/config/values-hardened.yaml"
run_case "adapted chart: helm template dhc-<name> <upstream> --repo --version -f overlay" 0 "$SB/chart/valkey/"
argv_is "adapted chart: the argv, from the pin, trailing slash dropped" "$(printf 'template\ndhc-valkey\nvalkey\n--repo\nhttps://valkey-io.github.io/valkey-helm\n--version\n0.12.0\n-f\n%s/chart/valkey/config/values-hardened.yaml' "$SB")"

# 3: a directory with neither file is refused by name, helm never runs
mkdir -p "$SB/chart/empty"
run_case "neither Chart.yaml nor chart.yaml: refused, naming the directory" 1 "$SB/chart/empty" "render-chart: $SB/chart/empty has neither Chart.yaml (owned) nor chart.yaml (adapted pin)"
[ ! -s "$STUB_ARGV" ] && echo "ok   neither: helm was not invoked" || { echo "FAIL neither: helm was invoked"; FAILURES=$((FAILURES+1)); }

# 4: helm's failure is the script's failure
STUB_EXIT=3 run_case "helm failing propagates its exit code" 3 "$SB/chart/hardened-app"

# 5: no argument is a usage error
out=$("$RENDER" 2>&1); rc=$?
if [ "$rc" -ne 0 ] && grep -q "usage: render-chart.sh <chart-dir>" <<<"$out"; then echo "ok   no argument: usage, non-zero"; else echo "FAIL no argument: exit $rc: $out"; FAILURES=$((FAILURES+1)); fi

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES test(s) failed"; exit 1; fi
echo "all render-chart tests passed"
