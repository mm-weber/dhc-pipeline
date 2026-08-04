# v12.4.5 ships a Go 1.26.3 binary; the 1.26.4 bump has been on `main` since June

**Target repo:** `grafana/grafana-zipkin-datasource`
**Drafted:** 2026-08-04, not filed

---

## Summary

The newest published release, **v12.4.5** (2026-05-18), ships a backend binary
built with **go1.26.3**, which carries five Go standard-library advisories.

`go.mod` on `main` has declared `go 1.26.4` since
[#79](https://github.com/grafana/grafana-zipkin-datasource/pull/79)
(2026-06-22), so three of the five are already fixed in the repository. They
have simply never reached a published artifact: there has been no release in the
two and a half months since.

This reaches Grafana itself. `scripts/catalog-plugins-defaults` in
`grafana/grafana` lists `zipkin` **with no version pin**, so every Grafana build
bundles whatever the catalog serves as latest, currently the v12.4.5 binary,
into `data/plugins-bundled/zipkin/`. Grafana 13.1.1's own `bin/grafana` is built
with go1.26.5 and is clean; the bundled plugin beside it is not.

## Evidence

### What the published artifact is built with

Downloading the release asset and reading its embedded build info:

```
$ gh release download v12.4.5 -R grafana/grafana-zipkin-datasource \
    -p 'zipkin-12.4.5.linux_amd64.zip*'
$ sha1sum zipkin-12.4.5.linux_amd64.zip
ac54e1f77c6ac441cd4c0c929fcafde65d53c6c6        # matches the published .sha1 sidecar
$ sha256sum zipkin-12.4.5.linux_amd64.zip
e98e9f9ad67fa54f5b88a6d192ba3e018d7bf1f8d5eba59b94a223f5b3c47e54
$ unzip -q zipkin-12.4.5.linux_amd64.zip
$ go version -m zipkin/gpx_grafana-zipkin-datasource_linux_amd64
zipkin/gpx_grafana-zipkin-datasource_linux_amd64: go1.26.3
	mod github.com/grafana/grafana-zipkin-datasource v0.0.0-20260518152343-daafdfe11421
```

(The sha256 is our own record of the bytes we read; the sidecar published beside
the asset is `.sha1`, and it matches.)

### Which advisories follow from go1.26.3

These are a property of the toolchain version, so they apply to any binary built
with it. Fixed-in versions are from the `golang/vulndb` reports:

| Advisory | Package | Summary | Fixed in |
|---|---|---|---|
| CVE-2026-27145 | `crypto/x509` | Inefficient candidate hostname parsing | 1.25.11, **1.26.4** |
| CVE-2026-42504 | `mime` | Quadratic complexity in `WordDecoder.DecodeHeader` | 1.25.11, **1.26.4** |
| CVE-2026-42507 | `net/textproto` | Unescaped inputs included in errors | 1.25.11, **1.26.4** |
| CVE-2026-39822 | `os` | Root escape via symlink plus trailing slash | 1.25.12, **1.26.5** |
| CVE-2026-42505 | `crypto/tls` | Encrypted Client Hello privacy leak | 1.25.12, **1.26.5** |

### They are reachable, not merely linked

`govulncheck -mode=binary` reports all five at **symbol** level, meaning it
resolved a call path to a function, not merely a linked module. Package and
symbol columns are reproduced as the tool emitted them:

| Level | Advisory | Alias | Module | Version | Package | Symbol |
|---|---|---|---|---|---|---|
| symbol | GO-2026-4970 | CVE-2026-39822 | stdlib | v1.26.3 | `os` | `ReadFile` |
| symbol | GO-2026-5037 | CVE-2026-27145 | stdlib | v1.26.3 | `crypto/x509` | `Verify` |
| symbol | GO-2026-5038 | CVE-2026-42504 | stdlib | v1.26.3 | `mime` | `DecodeHeader` |
| symbol | GO-2026-5039 | CVE-2026-42507 | stdlib | v1.26.3 | `net/textproto` | `ReadResponse` |
| symbol | GO-2026-5856 | CVE-2026-42505 | stdlib | v1.26.3 | `crypto/tls` | `DialContext` |

**Provenance:** this run was made against the copy bundled in
`grafana/grafana:13.1.1` rather than against the release zip directly. Its build
info records `golang.org/x/net` v0.49.0, `golang.org/x/text` v0.33.0 and
`google.golang.org/grpc` v1.79.3, matching the v12.4.5 asset above exactly,
which is what identifies the two as the same build.

### The fix is already merged, just unreleased

| | `go` directive |
|---|---|
| `go.mod` at tag `v12.4.5` | `go 1.26.3` |
| `go.mod` on `main` today | **`go 1.26.4`** |

Bumped by #79, *"Chore: Bump go v1.26.4 and workflows to v9.0.0"*, 2026-06-22.

This matters because of how the release toolchain is chosen.
`.github/workflows/publish.yaml` calls
`grafana/plugin-ci-workflows/.github/workflows/cd.yml@ci-cd-workflows/v10.1.0`
without a `go-version` input, and that workflow resolves the version as:

> 1. If explicitly provided as input, use that
> 2. If a version file (`.nvmrc`/`go.mod`) exists in the plugin directory, use that
> 3. Otherwise, use the workflow-level default version

So this repo lands on rule 2: the `go` directive in `go.mod` *is* the release
toolchain. A release cut from `main` today would therefore build with 1.26.4 and
clear three of the five with no code change at all.

(For completeness: rule 3's `DEFAULT_GO_VERSION` in that shared workflow is also
`"1.26.3"` on `main` today. It does not apply to this repo, since `go.mod` sits
in the plugin directory and rule 2 wins.)

### How it reaches Grafana users

`grafana/grafana`, `scripts/catalog-plugins-defaults` at tag `v13.1.1`:

```
# Catalog plugin IDs to bundle under data/plugins-bundled (one per line).
# Optional pin: id:version.
elasticsearch
zipkin
```

No pin, so `scripts/download-catalog-plugins.sh` fetches the current catalog
release at Grafana build time. Scanning `grafana/grafana:13.1.1` shows the
resulting binary at
`usr/share/grafana/data/plugins-bundled/zipkin/gpx_grafana-zipkin-datasource_linux_amd64`
reporting `stdlib v1.26.3`, alongside a clean `bin/grafana`.

## Why this matters downstream

We publish hardened Grafana images and gate them on a HIGH/CRITICAL scan. A
consumer on the newest Grafana, running the newest published version of this
plugin, has no remediation path: there is no artifact anywhere that carries the
fix. The only options left are to strip the plugin from the image, which removes
the datasource, or to accept the finding on a timer.

Rebuilding the plugin ourselves is possible but forfeits the Grafana plugin
signature, which is a poor trade for standard-library advisories.

## The ask

1. **Cut a release from `main`.** No code change required; the 1.26.4 bump is
   already there. This clears CVE-2026-27145, CVE-2026-42504 and CVE-2026-42507.
2. **Optionally bump the `go` directive to 1.26.5 first**, which additionally
   clears CVE-2026-39822 and CVE-2026-42505, so all five.
   `grafana/grafana`'s own `go.mod` is already on 1.26.5.

## Question

**Is there a release cadence for bundled catalog plugins?** Because Grafana
bundles this plugin unpinned, its release schedule silently becomes part of
Grafana's image security posture, and a plugin can go months without a release
while the Grafana releases beside it keep shipping.

## Related

- `grafana/sentry-datasource#736`, the same shape on a different plugin: fixes
  merged on `main`, publishing is manual, nothing released.
- `grafana/grafana#124023`, the broad "CVEs in Grafana Docker images" thread. A
  comment there (2026-05-15) names bundled plugin binaries as a source; this
  draft is the specific, measured case.

---

Happy to re-run any of the above, or to supply the full `govulncheck` JSON.
