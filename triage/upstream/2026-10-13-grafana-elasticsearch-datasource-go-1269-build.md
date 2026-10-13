# elasticsearch 12.9.0, bundled in Grafana 13.1.7, is built with go1.26.7; 12.9.3 brings x/net v0.60.0 but no Go bump

**Target repo:** `grafana/grafana-elasticsearch-datasource`
**Form:** one new issue (the Go 1.26.9 build has no tracker: the dependency
dashboard shows `go 1.26.7` with no update offered) and one comment seconding
the release-please pull request
[#448](https://github.com/grafana/grafana-elasticsearch-datasource/pull/448)
(12.9.3, shipping #447's x/net v0.60.0).
**Drafted:** 2026-10-13
**Filed:** 2026-10-13 as
[grafana/grafana-elasticsearch-datasource#450](https://github.com/grafana/grafana-elasticsearch-datasource/issues/450);
the comment on #448 posted the same day
([link](https://github.com/grafana/grafana-elasticsearch-datasource/pull/448#issuecomment-6143074369)).
#450 is the `issue:` of the three elasticsearch entries in
`../accepted-risk/grafana.yaml`.
Measurements reproduce with
[`checks/grafana-go-wave-symbols.sh`](checks/grafana-go-wave-symbols.sh).
Downstream record: mm-weber/dhc-pipeline#258, #259, #263 and `../LOG.md`
2026-10-13.

---

## Issue

Title: Build with Go 1.26.9+: stdlib advisories GO-2026-6607, GO-2026-6609, GO-2026-6611 in the shipped backend

The backend bundled in Grafana 13.1.7 (gpx_grafana_elasticsearch_datasource_linux_amd64, plugin 12.9.0, built 2026-09-16) reports go1.26.7 via go version -m. Go 1.26.9 (2026-10-09) fixes CVE-2026-78667 (GO-2026-6609, net/http Range parsing), CVE-2026-97031 (GO-2026-6607, crypto/tls ECH) and CVE-2026-78669 (GO-2026-6611, HTTP/2 SETTINGS flood). #447 moved x/net to v0.60.0 and #448 will release it as 12.9.3, but go.mod still says go 1.26.7, so the standard-library copies stay.

Ask: bump go.mod to go 1.26.9 (or add toolchain go1.26.9) with or right after 12.9.3, and release, so the next Grafana patch can bundle a clean build (grafana/grafana#131863).

From the binary's function table: the Range-parsing path and the x/net/http2 flow-control symbols are not linked in this plugin; the stdlib HTTP/2 and crypto/tls ones are. Our tracking, with the per-binary measurements: mm-weber/dhc-pipeline#258, #259, #263.

## Comment on #448

Seconding the cut: 12.9.3 carries #447 (golang.org/x/net v0.60.0, the fix for GO-2026-6611 / CVE-2026-78669), and the 12.9.0 bundled in Grafana 13.1.7 is still on v0.58.0. The remaining stdlib advisories (GO-2026-6607, GO-2026-6609, GO-2026-6611) need a Go 1.26.9 build, filed separately. Our tracking: mm-weber/dhc-pipeline#263.
