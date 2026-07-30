#!/usr/bin/env bash
# govulncheck-report.sh — turn govulncheck JSON into the reachability answer
# Trivy and Grype cannot give (Req 6.13).
#
#   govulncheck-report.sh <label>=<govulncheck.json> [<label>=<file> ...]
#
# Both scanners answer "is this module linked". govulncheck -mode=binary reads
# the binary's symbol table and answers "is the vulnerable code called", which
# is the only thing that can settle an advisory whose applicability turns on one
# wired-in symbol. Req 6.14 makes a reachable symbol FORBID a not_affected
# statement, so this output is load-bearing and its failure modes matter more
# than its formatting.
#
# The three levels are NOT a confidence scale:
#   symbol       the vulnerable function is in the call graph — reachable
#   package      the package is, the function is not named — undecided
#   not measured govulncheck saw only the module. A stripped binary looks
#                exactly like this, so it is silence, never absence.
#
# Evidence, not a gate: this exits 0 whatever it finds. Trivy is the only thing
# that fails a build.
set -uo pipefail

die() { echo "govulncheck-report: $*" >&2; exit 1; }
usage() {
  echo "usage: govulncheck-report.sh <label>=<govulncheck.json> [<label>=<file> ...]" >&2
  exit 2
}

[ "$#" -gt 0 ] || usage

rows=""
for arg in "$@"; do
  case "$arg" in
    *=*) ;;
    *) usage ;;
  esac
  label="${arg%%=*}"
  file="${arg#*=}"
  [ -n "$label" ] || usage
  [ -f "$file" ] || die "no such file: ${file}"
  # govulncheck emits a stream of bare objects, so slurp rather than assume an
  # array. A parse failure is an error: a reporter that shrugs at unreadable
  # input reports "no findings" for a binary it never read.
  jq -e -s . "$file" >/dev/null 2>&1 || die "not valid govulncheck JSON: ${file}"

  # One row per (osv, module) at the strongest level seen. govulncheck reports
  # the SAME vulnerability at several granularities; keeping every row would
  # leave a reader two rows that disagree about the only question being asked.
  file_rows=$(jq -r --arg bin "$label" -s '
    ( [ .[] | select(has("osv")) | {key: .osv.id, value: ((.osv.aliases // []) | join(", "))} ] | from_entries ) as $alias
    | [ .[] | select(has("finding")) | .finding
        | (.trace[0] // {}) as $t
        | { osv: .osv,
            module:  ($t.module  // "-"),
            version: ($t.version // "-"),
            fn:      ($t.function // ""),
            rank:    (if $t.function then 3 elif $t.package then 2 else 1 end) } ]
    | group_by([.osv, .module])
    | map(max_by(.rank))
    | .[]
    | [ (.rank|tostring), $bin, .osv, ($alias[.osv] // ""), .module, .version, .fn ]
    | @tsv' "$file") || die "failed to parse: ${file}"
  rows+="${file_rows}"$'\n'
done

rows=$(printf '%s' "$rows" | sed '/^$/d')

if [ -z "$rows" ]; then
  echo "govulncheck: no findings across $# binary(ies)"
  exit 0
fi

n=$(printf '%s\n' "$rows" | wc -l | tr -d ' ')
reachable=$(printf '%s\n' "$rows" | awk -F'\t' '$1==3' | wc -l | tr -d ' ')
noun="findings"; [ "$n" -eq 1 ] && noun="finding"
echo "govulncheck: ${n} ${noun}, ${reachable} with a reachable symbol"
echo
echo "| Binary | Vulnerability | Module | Version | Reachable | Reached function |"
echo "|---|---|---|---|---|---|"
# Reachable first: those are the rows that forbid a not_affected statement
# (Req 6.14), and they are what a reader needs off the top of the table.
printf '%s\n' "$rows" | sort -t$'\t' -k1,1nr -k2,2 -k3,3 | while IFS=$'\t' read -r rank label osv alias module version fn; do
  case "$rank" in
    3) level="symbol" ;;
    2) level="package" ;;
    *) level="not measured" ;;
  esac
  id="$osv"
  [ -n "$alias" ] && id="${osv} (${alias})"
  echo "| ${label} | ${id} | ${module} | ${version} | ${level} | ${fn:--} |"
done
exit 0
