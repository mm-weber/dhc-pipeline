# 13.1.7 bundles zipkin 12.4.8 and elasticsearch 12.9.0 built with go1.26.7 and x/net v0.58.0; the server's 13.1.8 fix needs rebuilt bundles beside it

**Target repo:** `grafana/grafana`
**Form:** a comment seconding the existing packaging issue
[grafana/grafana#131863](https://github.com/grafana/grafana/issues/131863)
(2026-08-31, labelled security and build-packaging, maintainer-acknowledged
2026-09-23), not a new issue.
**Drafted:** 2026-10-13
**Posted:** 2026-10-13
([link](https://github.com/grafana/grafana/issues/131863#issuecomment-6143011777)).
The comment body is this file from `## Comment` down, unmodified. Measurements
reproduce with
[`checks/grafana-go-wave-symbols.sh ghcr.io/mm-weber/dhc/grafana@sha256:6656a754f9ac091d59908db13811fd6d136f17f6bd6bb7e4088f85c4919cd0cb`](checks/grafana-go-wave-symbols.sh).
Downstream record: mm-weber/dhc-pipeline#258, #259, #263 (labelled
`transfer-upstream`, decision comments of 2026-10-13) and `../LOG.md`
2026-10-13.

---

## Comment

Seconding this from a downstream hardened-image catalogue, with 13.1.7 numbers. The 13.1.7 linux/amd64 release tarball bundles zipkin 12.4.8 (go1.26.7, golang.org/x/net v0.58.0) and elasticsearch 12.9.0 (go1.26.7, x/net v0.58.0). Both carry CVE-2026-78667, CVE-2026-97031 and CVE-2026-78669 (GO-2026-6609, GO-2026-6607, GO-2026-6611), fixed in Go 1.26.9 and x/net 0.60.0 on 2026-10-09. grafana-server itself is fixed on release-13.1.8 (#134622, #134613), so 13.1.8 is clean only if the bundled plugin binaries are rebuilt and rebundled as well.

preinstall_auto_update does not reach immutable or air-gapped images, which ship exactly what the tarball holds. Could 13.1.8 and 13.2.4 pick up plugin builds on Go 1.26.9 or newer?

Measured with go version -m and the binaries' function tables: in the two plugins the Range-parsing path and the x/net/http2 flow-control code are not linked, the stdlib HTTP/2 and crypto/tls code is. Our tracking, with the per-binary measurements: mm-weber/dhc-pipeline#258, #259, #263.
