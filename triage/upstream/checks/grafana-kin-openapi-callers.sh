#!/usr/bin/env bash
# grafana-kin-openapi-callers.sh <image ref or digest> | --rootfs <dir>
#
# The measurement behind the triage/LOG.md entries of 2026-10-23 on the two
# kin-openapi findings that sit in code the grafana 13.1.7 server does link,
# the openapi3 schema package (CVE-2026-100352, #275; CVE-2026-100354, #277).
# The sibling grafana-kin-openapi-symbols.sh answers "is the function in the
# binary"; this one answers "who calls it". It disassembles the whole server
# binary with `go tool objdump` (the ELF symbol table is kept, so every call
# target has its name) and keeps three kinds of direct CALL instruction:
#
#   into      every call into the kin-openapi module from a function outside
#             it: the module's entry points as this build uses them
#   jsonschema every call into santhosh-tekuri/jsonschema from a function
#             outside both that module and kin-openapi: whether anything but
#             kin-openapi reaches the validator that panics in 100352
#   entry     every caller of the functions the two advisories name and of
#             the functions that select the vulnerable path, wherever the
#             caller sits, kin-openapi included
#
# A direct CALL is what the linker resolved by name. Calls through a function
# value or an interface show as `CALL AX` and the like and are not attributed;
# the option closures that select kin-openapi's JSON Schema 2020-12 path are
# such values, which is why the symbol table is read as well: a closure the
# compiler inlined into its caller is named after that caller
# (`validateExampleValue.EnableJSONSchema2020.func4`), so the symbol table
# says which functions can switch the path on at all.
#
# Only the server is read: the sibling script showed the bundled plugins link
# no kin-openapi package. The whole-binary pass takes a few minutes.
set -euo pipefail
if [ "${1:-}" = "--rootfs" ]; then
  ROOT="${2:?rootfs dir}"
else
  REF="${1:?image ref or digest}"
  ROOT="$(mktemp -d)"
  cid="$(docker create --platform linux/amd64 "$REF" true)"
  docker export "$cid" | tar -x -C "$ROOT" usr/share/grafana/bin
  docker rm "$cid" >/dev/null
fi
BIN="$ROOT/usr/share/grafana/bin/grafana"
KIN='github.com/getkin/kin-openapi/'
JSC='github.com/santhosh-tekuri/jsonschema/'
# The functions the advisories name, and the ones that select the path.
ENTRY=(
  # CVE-2026-100352 (GHSA-rj39-cv6w-8wv7, #275): the JSON Schema 2020-12 path
  # hands NaN and Inf to jsonschema/v6 v6.0.2 unguarded; numValidate panics.
  'github.com/getkin/kin-openapi/openapi3.(*Schema).VisitJSON'                 # the public entry point
  'github.com/getkin/kin-openapi/openapi3.(*Schema).useJSONSchema2020'         # the 3.1 path, taken under the option
  'github.com/getkin/kin-openapi/openapi3.newJSONSchemaValidator'              # builds the 2020-12 validator
  'github.com/getkin/kin-openapi/openapi3.(*jsonSchemaValidator).validate'     # hands the value to jsonschema
  'github.com/santhosh-tekuri/jsonschema/v6.(*validator).numValidate'          # where the nil *big.Rat is dereferenced
  'github.com/getkin/kin-openapi/openapi3.validateExampleValue'                # the one in-library user of the option
  'github.com/getkin/kin-openapi/openapi3.(*T).Validate'                       # spec-time validation, which reaches it
  'github.com/getkin/kin-openapi/openapi3.(*Schema).Validate'
  # CVE-2026-100354 (GHSA-g8cf-rcjf-c8cf, #277): the built-in visitor recurses
  # without a cycle check through allOf, anyOf and oneOf.
  'github.com/getkin/kin-openapi/openapi3.(*Schema).visitJSON'                 # the built-in visitor
  'github.com/getkin/kin-openapi/openapi3.(*Schema).visitXOFOperations'        # the combinator walk
  # Where the schema comes from.
  'github.com/getkin/kin-openapi/openapi3.(*Loader).LoadFromData'
)
echo "== ${BIN#$ROOT/} =="
go version -m "$BIN" | grep -E '^\S|kin-openapi|santhosh-tekuri/jsonschema|grafana-app-sdk ' | sed 's/^/  /'
echo "  symbol table: $(go tool nm "$BIN" | wc -l) symbols"
echo "  closures that can switch the 2020-12 path on (EnableJSONSchema2020, by inlining caller):"
go tool nm "$BIN" | awk '$2=="T" && $3 ~ /EnableJSONSchema2020/ {print "    " $3}'
echo "  option closures handed to VisitJSON by callers outside kin-openapi:"
go tool nm "$BIN" | awk '$2=="T" && $3 !~ /^github.com\/getkin\/kin-openapi\// && $3 ~ /\.(MultiErrors|EnableJSONSchema2020|VisitAsRequest|VisitAsResponse|SetRegexCompiler|EnableFormatValidation|DisableFormatValidation|DisablePatternValidation|DisableReadOnlyValidation|DisableWriteOnlyValidation|FailFast|EnableFormatValidationForUint|DefaultsSet)\.func[0-9]+$/ {print "    " $3}'
echo "  disassembly:"
OUT="$(mktemp)"
go tool objdump "$BIN" | awk -v kin="$KIN" -v jsc="$JSC" -v entries="$(printf '%s\n' "${ENTRY[@]}")" '
BEGIN { n = split(entries, e, "\n"); for (i = 1; i <= n; i++) entry[e[i]] = 1 }
/^TEXT / { fn = $2; sub(/\(SB\)$/, "", fn); next }
$0 ~ /\tCALL / {
  callee = $NF; sub(/\(SB\)$/, "", callee)
  if (index(callee, kin) == 1 && index(fn, kin) != 1) print "into", fn, "->", callee
  if (index(callee, jsc) == 1 && index(fn, jsc) != 1 && index(fn, kin) != 1) print "jsonschema", fn, "->", callee
  if (callee in entry) print "entry", fn, "->", callee
}' | sort | uniq -c > "$OUT"
for kind in into jsonschema entry; do
  printf '  %s: %s direct call sites\n' "$kind" "$(awk -v k="$kind" '$2==k {n+=$1} END {print n+0}' "$OUT")"
  awk -v k="$kind" '$2==k {printf "    %s  %s -> %s\n", $1, $3, $5}' "$OUT"
done
rm -f "$OUT"
