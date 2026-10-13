# zipkin 12.4.8, bundled in Grafana 13.1.7, is built with go1.26.7 and x/net v0.58.0; round four on #94

**Target repo:** `grafana/grafana-zipkin-datasource`
**Form:** two comments. One extends the owner's own issue
[#94](https://github.com/grafana/grafana-zipkin-datasource/issues/94) (rounds
one to three of the same stale-bundle problem; #100 is a parallel report); one
seconds Renovate's [#109](https://github.com/grafana/grafana-zipkin-datasource/pull/109),
which carries x/net v0.60.0 with every check green and no review since
2026-09-25.
**Drafted:** 2026-10-13
**Posted:** 2026-10-13, on #94
([link](https://github.com/grafana/grafana-zipkin-datasource/issues/94#issuecomment-6143037023))
and on #109
([link](https://github.com/grafana/grafana-zipkin-datasource/pull/109#issuecomment-6143060939)).
Measurements reproduce with
[`checks/grafana-go-wave-symbols.sh`](checks/grafana-go-wave-symbols.sh).
Downstream record: mm-weber/dhc-pipeline#258, #259, #263 and `../LOG.md`
2026-10-13.

---

## Comment on #94

Round four, 2026-10-13. Grafana 13.1.7 bundles v12.4.8 (built 2026-09-10, go1.26.7, golang.org/x/net v0.58.0). The 2026-10-09 Go security batch applies to it: CVE-2026-78667 (GO-2026-6609), CVE-2026-97031 (GO-2026-6607) and CVE-2026-78669 (GO-2026-6611), fixed in Go 1.26.9 and x/net 0.60.0. v12.4.9 (2026-09-28) predates the fixes; main still pins go 1.26.7 and x/net v0.59.0.

#109 (Renovate) already carries x/net v0.60.0 with green CI and is waiting for a review. Ask: merge #109, bump go.mod to go 1.26.9 (or add toolchain go1.26.9), cut a release, and let the next Grafana patch bundle it (grafana/grafana#131863).

From the binary's function table: the Range-parsing path and the x/net/http2 flow-control symbols are not linked in this plugin; the stdlib HTTP/2 and crypto/tls ones are, so the Go bump is the part that matters most. Our tracking, with the per-binary measurements: mm-weber/dhc-pipeline#258, #259, #263.

## Comment on #109

Seconding a merge: this carries golang.org/x/net v0.60.0, the fix for GO-2026-6611 (CVE-2026-78669) and the other x/net advisories on the dependency dashboard; every check is green and it only needs a review. A release after it lets Grafana rebundle (grafana/grafana#131863). Details and the Go 1.26.9 ask in #94; our tracking in mm-weber/dhc-pipeline#263.
