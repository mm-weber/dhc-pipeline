#!/usr/bin/env bash
# grafana-kin-openapi-symbols.sh <image ref or digest> | --rootfs <dir>
#
# The measurement behind the triage/LOG.md entries of 2026-10-21 on the
# kin-openapi findings in grafana 13.1.7: for each Go binary in the image, the
# kin-openapi version it links (`go version -m`), how many functions of each
# kin-openapi package the linker kept, which source files of the module sit in
# the pclntab's file table, and whether the functions the kin-openapi
# advisories name are present. The server keeps its ELF symbol table, so
# `go tool nm` reads it; the bundled plugins are stripped (-s -w), so every
# name comes from the pclntab, read with the standard library's debug/gosym
# (no symbol table needed). A present name counts as reachable (Req 6.14); a
# stripped binary allows nothing finer (Req 6.16).
#
# The package counts are the finding's shape: Trivy matches the module version
# in the build info (go.mod-level), so a module can be named for a binary that
# links one of its packages and none of the vulnerable one. A package the
# linker dropped whole leaves no function, no type symbol and no file in the
# pclntab's file table, which an inlined copy of any of its functions would
# leave behind. The file table is read directly (debug/gosym fills it from the
# pclntab); `strings` stays as the cross-check, and its patterns must be
# spelled as the table spells a module's files, version included:
# `github.com/getkin/kin-openapi@v0.144.0/openapi3/schema.go`.
#
# With an image ref the binaries are read out of a `docker create` container;
# with --rootfs the directory must hold usr/share/grafana as extracted.
# Sibling: grafana-go-wave-symbols.sh (2026-10-13), the same instrument.
set -euo pipefail
if [ "${1:-}" = "--rootfs" ]; then
  ROOT="${2:?rootfs dir}"
else
  REF="${1:?image ref or digest}"
  ROOT="$(mktemp -d)"
  cid="$(docker create --platform linux/amd64 "$REF" true)"
  docker export "$cid" | tar -x -C "$ROOT" usr/share/grafana/bin usr/share/grafana/data/plugins-bundled
  docker rm "$cid" >/dev/null
fi
G="$ROOT/usr/share/grafana"
mapfile -t BINS < <(find "$G/bin" "$G/data/plugins-bundled" -type f -exec sh -c 'head -c4 "$1" | grep -q ELF' _ {} \; -print | sort)

# The package footprint, counted per kin-openapi package and for gorilla/mux.
PREFIXES=(
  'github.com/getkin/kin-openapi/'
  'github.com/gorilla/mux.'
)
# The source files a linked or inlined copy of a package leaves in the file
# table, grouped by the directory after the pattern; the module's own files
# are the control.
FILES=(
  'kin-openapi@'
  'openapi3filter'
  'req_resp_decoder.go'
  'validate_response.go'
  'gorilla/mux@'
)
# The functions the advisories name.
SYMS=(
  # CVE-2026-100351 (GHSA-23vg-4cjm-66q5, #274): ValidationHandler.Middleware
  # validates with the legacy router on the decoded path while a downstream
  # gorilla/mux router with UseEncodedPath dispatches on the encoded one; the
  # fix (kin-openapi eda80e2, 0.147.0) adds checkEncodedPathSeparator to
  # validateRequest.
  'github.com/getkin/kin-openapi/openapi3filter.(*ValidationHandler).Middleware'      # the vulnerable entry point
  'github.com/getkin/kin-openapi/openapi3filter.(*ValidationHandler).ServeHTTP'       # its sibling entry point
  'github.com/getkin/kin-openapi/openapi3filter.(*ValidationHandler).Load'            # builds the legacy router
  'github.com/getkin/kin-openapi/openapi3filter.(*ValidationHandler).validateRequest' # where the fix lands
  'github.com/getkin/kin-openapi/openapi3filter.NewValidator'
  'github.com/getkin/kin-openapi/routers/legacy.NewRouter'                            # the router that decodes
  'github.com/getkin/kin-openapi/routers/legacy.(*Router).FindRoute'
  'github.com/getkin/kin-openapi/routers/gorillamux.NewRouter'                        # the router that does not
  'github.com/gorilla/mux.(*Router).UseEncodedPath'                                   # the downstream precondition
  # CVE-2026-100353 (GHSA-vrcc-3ch7-hppw, #276): three nil-items panic paths in
  # the request decoder, left open by the fix for GHSA-p6wj-qrr4-pgh5; the fix
  # (kin-openapi 9814d1f, 0.149.0) guards (*urlValuesDecoder).parseArray and
  # buildResObj. CVE-2026-100349 (GHSA-74vm-87hj-r66f, #287): a response
  # header declared with content reaches decodeValue with a nil schema from
  # validateResponseHeader; the fix (f5441d6, 0.146.0) guards decodeValue.
  'github.com/getkin/kin-openapi/openapi3filter.(*urlValuesDecoder).parseArray'       # fix site, 100353
  'github.com/getkin/kin-openapi/openapi3filter.buildResObj'                          # fix site, 100353
  'github.com/getkin/kin-openapi/openapi3filter.(*urlValuesDecoder).parseValue'       # where the nil is dereferenced
  'github.com/getkin/kin-openapi/openapi3filter.(*urlValuesDecoder).DecodeArray'      # the chain down to parseArray
  'github.com/getkin/kin-openapi/openapi3filter.makeObject'                           # the chain down to buildResObj
  'github.com/getkin/kin-openapi/openapi3filter.decodeProperty'
  'github.com/getkin/kin-openapi/openapi3filter.decodeSchemaConstructs'               # the allOf walker
  'github.com/getkin/kin-openapi/openapi3filter.UrlencodedBodyDecoder'
  'github.com/getkin/kin-openapi/openapi3filter.MultipartBodyDecoder'
  'github.com/getkin/kin-openapi/openapi3filter.parseArray'                           # the guarded sibling
  'github.com/getkin/kin-openapi/openapi3filter.decodeValue'                          # fix site, 100349
  'github.com/getkin/kin-openapi/openapi3filter.validateResponseHeader'               # its caller
  'github.com/getkin/kin-openapi/openapi3filter.ValidateParameter'                    # the package's entry points
  'github.com/getkin/kin-openapi/openapi3filter.ValidateRequestBody'
  'github.com/getkin/kin-openapi/openapi3filter.ValidateRequest'
  'github.com/getkin/kin-openapi/openapi3filter.ValidateResponse'
  'github.com/getkin/kin-openapi/openapi3filter.RegisterBodyDecoder'
  # Controls: what grafana does link of kin-openapi.
  'github.com/getkin/kin-openapi/openapi3.(*Schema).VisitJSON'                        # control: what grafana calls
  'github.com/getkin/kin-openapi/openapi3.(*Schema).visitXOFOperations'               # control: allOf/anyOf/oneOf
  'github.com/getkin/kin-openapi/openapi3.(*Schema).visitJSONArray'                   # control: the schema package's own array walk
  'github.com/getkin/kin-openapi/openapi3.(*Schema).Validate'
)
# Strings that a linked or inlined copy of the vulnerable package would leave,
# and the linked package's files as the control, spelled with the version.
STRINGS=(
  'openapi3filter'
  'kin-openapi/routers'
  'kin-openapi/openapi3.'
  'kin-openapi@v0.144.0/openapi3/'
)

PCLN="$(mktemp -d)"
cat > "$PCLN/main.go" <<'GO'
package main

import (
	"debug/elf"
	"debug/gosym"
	"fmt"
	"os"
	"sort"
	"strings"
)

func main() {
	f, err := elf.Open(os.Args[1])
	if err != nil { fmt.Println("elf:", err); os.Exit(1) }
	sec := f.Section(".gopclntab")
	if sec == nil { fmt.Println("no .gopclntab"); os.Exit(1) }
	data, err := sec.Data()
	if err != nil { fmt.Println("pclntab:", err); os.Exit(1) }
	tab, err := gosym.NewTable(nil, gosym.NewLineTable(data, f.Section(".text").Addr))
	if err != nil { fmt.Println("gosym:", err); os.Exit(1) }
	fmt.Printf("  symtab=%v funcs=%d files=%d\n", f.Section(".symtab") != nil, len(tab.Funcs), len(tab.Files))
	args := os.Args[2:]
	for i := 0; i < len(args); i++ {
		if args[i] == "--prefix" && i+1 < len(args) {
			i++
			pfx := args[i]
			n := 0
			sub := map[string]int{}
			for _, fn := range tab.Funcs {
				if strings.HasPrefix(fn.Name, pfx) {
					n++
					rest := strings.TrimPrefix(fn.Name, pfx)
					if j := strings.Index(rest, "."); j >= 0 { rest = rest[:j] }
					sub[rest]++
				}
			}
			keys := make([]string, 0, len(sub))
			for k := range sub { keys = append(keys, k) }
			sort.Strings(keys)
			fmt.Printf("  prefix %-70s %d\n", pfx, n)
			for _, k := range keys { fmt.Printf("    %-72s %d\n", k, sub[k]) }
			continue
		}
		if args[i] == "--files" && i+1 < len(args) {
			i++
			pat := args[i]
			n := 0
			dirs := map[string]int{}
			for name := range tab.Files {
				if j := strings.Index(name, pat); j >= 0 {
					n++
					rest := name[j+len(pat):]
					if k := strings.LastIndex(rest, "/"); k >= 0 { rest = rest[:k] } else { rest = "" }
					dirs[rest]++
				}
			}
			keys := make([]string, 0, len(dirs))
			for k := range dirs { keys = append(keys, k) }
			sort.Strings(keys)
			fmt.Printf("  files containing %-60s %d\n", pat, n)
			for _, k := range keys { fmt.Printf("    %-72s %d\n", k, dirs[k]) }
			continue
		}
		want := args[i]
		n := 0
		for _, fn := range tab.Funcs {
			if fn.Name == want || strings.HasPrefix(fn.Name, want+".") { n++ }
		}
		fmt.Printf("  %-85s %d\n", want, n)
	}
}
GO
printf 'module pcln\ngo 1.22\n' > "$PCLN/go.mod"
(cd "$PCLN" && GOFLAGS=-mod=mod GOPROXY=off go build -o pcln . )

for b in "${BINS[@]}"; do
  echo "== ${b#$G/} =="
  go version -m "$b" | grep -E '^\S|^\s+path|kin-openapi|gorilla/mux|^\s+build\s+(GOARCH|-ldflags|vcs.time)' | sed 's/^/  /'
  args=()
  for p in "${PREFIXES[@]}"; do args+=(--prefix "$p"); done
  for p in "${FILES[@]}"; do args+=(--files "$p"); done
  "$PCLN/pcln" "$b" "${args[@]}" "${SYMS[@]}"
  if [ -n "$(go tool nm "$b" 2>/dev/null | head -1)" ]; then
    echo "  go tool nm: $(go tool nm "$b" | wc -l) symbols; openapi3filter in any kind: $(go tool nm "$b" | grep -c 'kin-openapi/openapi3filter' || true)"
  else
    echo "  go tool nm: no symbol table"
  fi
  for s in "${STRINGS[@]}"; do
    printf '  strings -n 12 | grep -cF %-34s %s\n' "'$s'" "$(strings -n 12 "$b" | grep -cF "$s" || true)"
  done
done
