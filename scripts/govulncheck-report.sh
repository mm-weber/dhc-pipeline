#!/usr/bin/env bash
# govulncheck-report.sh <label>=<file> [<label>=<file> ...]
#
# Render the reachability table for the PR job summary (Req 6.13): one markdown
# section per scanned binary, in the order the caller walked the rootfs. <label>
# is the binary's path inside the image and <file> holds that binary's
# `govulncheck -mode=binary -format json` output.
#
# Why this exists. Trivy and Grype answer "is this module linked"; govulncheck
# reads the binary's symbol table and answers "is the vulnerable code called".
# Req 6.14 hangs a prohibition on the difference, so the level column is the
# whole point of the table, and it has exactly three values — read off trace[0],
# the vulnerable end of the call path, never the rest of the trace, which is our
# own code calling in:
#
#   symbol        trace[0] names a function: the vulnerable code is reachable,
#                 which forbids a not_affected / vulnerable_code_not_in_execute_path
#                 statement for this image (Req 6.14).
#   package       resolved to a package but no function: undecided, not safe.
#   not measured  module only: govulncheck could not measure. A stripped binary
#                 produces exactly this, so it is silence, not absence — Req 6.16
#                 forbids citing it as evidence of unreachability, and this
#                 report must never word it as one.
#
# It is a REPORTER, not a gate (design.md, "Reachability evidence"): Trivy is
# the only thing allowed to fail a build, so findings — however reachable —
# leave the exit status at 0. Only input we could not read does, and then the
# section says so where its table would have been: an unreadable scan must never
# render as a clean one.
set -uo pipefail

if [ "$#" -eq 0 ]; then
  cat >&2 <<'USAGE'
usage: govulncheck-report.sh <label>=<file> [<label>=<file> ...]
       <label> is the binary's path inside the image; <file> holds that binary's
       `govulncheck -mode=binary -format json` output.
USAGE
  exit 2
fi

# One jq pass per file. jq reads a concatenated stream of bare JSON values
# natively, which is what `-format json` emits — pretty-printed objects, many
# lines each, no separators. Anything line-oriented parses the compact fixtures
# in the tests and finds nothing at all in CI.
#
# -s slurps the stream into one array so the advisory objects (which carry the
# CVE/GHSA aliases) can be joined onto the findings that reference them. The join
# is left-outer on purpose: govulncheck emits a finding for a vulnerability whose
# advisory object we failed to see, and dropping it would delete a vulnerability
# from the evidence while leaving the report looking clean.
JQ=$(cat <<'JQ'
def cell: if . == null or . == "" then "—" else . end;
def level: if . == 3 then "symbol" elif . == 2 then "package" else "not measured" end;

([ .[] | .osv? // empty | { (.id // ""): ((.aliases // []) | join(", ")) } ] | add // {}) as $alias
| [ .[]
    | .finding? // empty
    | (.trace[0] // {}) as $t
    | { id:      (.osv // "(no advisory id)"),
        rank:    (if ($t.function // "") != "" then 3
                  elif ($t.package // "") != "" then 2
                  else 1 end),
        module:  $t.module,
        version: $t.version,
        package: $t.package,
        symbol:  $t.function }
  ]
# govulncheck emits several findings per vulnerability — one per call path, and
# routinely a module-level one beside a symbol-level one. Collapse to the most
# resolved answer rather than the last one seen: a trailing module-level finding
# demoting a proven symbol to "not measured" is precisely the false exoneration
# Req 6.14 exists to forbid.
| group_by(.id)
| map(max_by(.rank))
# Reachable first: the rows that forbid a suppression must not sit below rows
# that prove nothing. Ties break on the id so the table is reproducible.
| sort_by(-.rank, .id)
| .[]
| [ (.rank | level), .id, (($alias[.id] // "") | cell),
    (.module | cell), (.version | cell), (.package | cell), (.symbol | cell) ]
| "| " + join(" | ") + " |"
JQ
)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
rc=0

# Input errors go to both streams on purpose. stdout is the job summary, where
# the message has to appear exactly where the table would have been; stderr
# carries the ::error:: so the same fact lands as an annotation on the step.
# One broken input never aborts the walk: the other binaries were measured, and
# their findings are the reason the step ran at all.
report_error() { # message
  rc=1
  printf '> **input error** — %s\n\n' "$1"
  printf '::error::govulncheck-report: %s\n' "$1" >&2
}

for arg in "$@"; do
  case "$arg" in
    *=*) ;;
    *)
      report_error "argument \`${arg}\` is not <label>=<file>"
      continue
      ;;
  esac

  # Split on the FIRST '=': the label is a path out of the image and the file is
  # a name the caller derived from it, so either half can contain '='. Splitting
  # on the last one opens some other file and attributes it to a binary that was
  # never scanned.
  label=${arg%%=*}
  file=${arg#*=}
  if [ -z "$label" ]; then
    report_error "argument \`${arg}\` has an empty label — the label is the binary's path inside the image"
    continue
  fi
  if [ -z "$file" ]; then
    report_error "no govulncheck output given for \`${label}\`"
    continue
  fi

  printf "#### \`%s\`\n\n" "$label"

  if [ ! -e "$file" ]; then
    report_error "\`${label}\`: no such file \`${file}\` — this binary's scan output was never produced, so nothing here says it is clean"
    continue
  fi
  if [ ! -r "$file" ]; then
    report_error "\`${label}\`: cannot read \`${file}\`"
    continue
  fi
  # govulncheck always emits at least a config object, so zero bytes means it
  # never ran. Rendering that as an empty table hands the reader an exoneration
  # with no warning attached.
  if [ ! -s "$file" ]; then
    report_error "\`${label}\`: \`${file}\` is empty — govulncheck always emits a config object, so this scan did not run"
    continue
  fi

  # A truncated stream — killed scan, full disk — parses partially. Taking the
  # partial result silently drops every finding after the cut.
  if ! jq -rs "$JQ" "$file" >"$tmp/rows" 2>"$tmp/err"; then
    report_error "\`${label}\`: \`${file}\` is not a parseable govulncheck JSON stream — $(head -n1 "$tmp/err")"
    continue
  fi

  # "We looked and found nothing" and "we never looked" are different claims and
  # only the first is evidence, so a cleared binary still gets its section.
  if [ ! -s "$tmp/rows" ]; then
    printf '_no vulnerabilities reported for this binary._\n\n'
    continue
  fi

  printf '| Level | Advisory | Aliases | Module | Version | Package | Symbol |\n'
  printf '| --- | --- | --- | --- | --- | --- | --- |\n'
  cat "$tmp/rows"
  printf '\n'
done

exit "$rc"
