#!/usr/bin/env bash
# grafana-go-wave-symbols.sh <image ref or digest> | --rootfs <dir>
#
# The measurement behind triage/LOG.md 2026-10-13: for each Go binary in the
# grafana image, the toolchain and golang.org/x/net version (`go version -m`)
# and whether the functions the Go vulnerability reports name are linked.
# The server keeps its ELF symbol table, so `go tool nm` reads it; the bundled
# plugins are stripped (-s -w), so their names come from the pclntab, read
# with the standard library's debug/gosym (no symbol table needed). A present
# name counts as reachable (Req 6.14); a stripped binary allows nothing finer
# (Req 6.16). govulncheck -mode=binary is NOT a substitute on the plugins: with
# no symbol table it substitutes every known vulnerable symbol (go.mod-level
# precision, golang/go#57764) and prints that under "Symbol Results".
#
# With an image ref the binaries are read out of a `docker create` container;
# with --rootfs the directory must hold usr/share/grafana as extracted.
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

# The symbols the reports name (golang/vulndb data/reports): one representative
# per report plus the full x/net list for GO-2026-6611.
SYMS=(
  'net/http.parseRange'                                   # GO-2026-6609 / CVE-2026-78667
  'net/http.ServeContent'                                 # its caller
  'crypto/tls.decodeInnerClientHello'                     # GO-2026-6607 / CVE-2026-97031
  'net/http.(*http2Transport).newClientConn'              # GO-2026-6611 / CVE-2026-78669, stdlib copy
  'net/http.(*http2serverConn).newStream'
  'golang.org/x/net/http2.(*Transport).newClientConn'     # GO-2026-6611, x/net copy
  'golang.org/x/net/http2.(*serverConn).newStream'
  'golang.org/x/net/http2.(*outflow).add'
  'golang.org/x/net/http2.(*Framer).ReadFrame'            # control: the frame layer gRPC links
  'github.com/hashicorp/go-plugin.generateCert'           # context: go-plugin automatic mTLS
)

PCLN="$(mktemp -d)"
cat > "$PCLN/main.go" <<'GO'
package main

import (
	"debug/elf"
	"debug/gosym"
	"fmt"
	"os"
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
	fmt.Printf("  symtab=%v funcs=%d\n", f.Section(".symtab") != nil, len(tab.Funcs))
	for _, want := range os.Args[2:] {
		n := 0
		for _, fn := range tab.Funcs {
			if fn.Name == want || strings.HasPrefix(fn.Name, want+".") { n++ }
		}
		fmt.Printf("  %-55s %d\n", want, n)
	}
}
GO
printf 'module pcln\ngo 1.22\n' > "$PCLN/go.mod"
(cd "$PCLN" && GOFLAGS=-mod=mod GOPROXY=off go build -o pcln . )

for b in "${BINS[@]}"; do
  echo "== ${b#$G/} =="
  go version -m "$b" | grep -E '^\S|^\s+path|golang.org/x/net\b|^\s+build\s+(GOARCH|-ldflags|vcs.time)' | sed 's/^/  /'
  "$PCLN/pcln" "$b" "${SYMS[@]}"
done
