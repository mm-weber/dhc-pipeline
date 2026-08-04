# `go.mod` pins Go 1.26.3, so every release, including v12.8.0, ships five stdlib advisories

**Target repo:** `grafana/grafana-elasticsearch-datasource`
**Drafted:** 2026-08-04
**Filed:** 2026-08-04 as
[grafana/grafana-elasticsearch-datasource#410](https://github.com/grafana/grafana-elasticsearch-datasource/issues/410)
(label `type/bug`). The issue body is this file from `## Summary` down,
unmodified.

---

## Summary

The newest published release, **v12.8.0** (2026-07-30), ships a backend binary
built with **go1.26.3**, which carries five Go standard-library advisories.

Unlike a stale-release case, this one reproduces on every future release too.
`go.mod` declares `go 1.26.3` on `main`, and the shared plugin CD workflow
derives the release toolchain from that file, so cutting another release today
would produce another go1.26.3 binary. The `go` directive has to move first.

This reaches Grafana itself. `scripts/catalog-plugins-defaults` in
`grafana/grafana` lists `elasticsearch` **with no version pin**, so every
Grafana build bundles the current catalog release into
`data/plugins-bundled/elasticsearch/`. Grafana 13.1.1's own `bin/grafana` is
built with go1.26.5 and is clean; the bundled plugin beside it is not.

## Evidence

### What the published artifact is built with

Downloading the newest release asset and reading its embedded build info:

```
$ gh release download v12.8.0 -R grafana/grafana-elasticsearch-datasource \
    -p 'elasticsearch-12.8.0.linux_amd64.zip*'
$ sha1sum elasticsearch-12.8.0.linux_amd64.zip
ff5d3c19d5fc06be16c9e4e16f735f29c3815759        # matches the published .sha1 sidecar
$ sha256sum elasticsearch-12.8.0.linux_amd64.zip
dcd23e727c513d40b87c59df0c3e07f6f16e7eb2628ae80acb9dc94c9d81f4fd
$ unzip -q elasticsearch-12.8.0.linux_amd64.zip
$ go version -m elasticsearch/gpx_grafana_elasticsearch_datasource_linux_amd64
elasticsearch/gpx_grafana_elasticsearch_datasource_linux_amd64: go1.26.3
	mod github.com/grafana/grafana-elasticsearch-datasource v0.0.0-20260730210458-344dbb84588b
```

(The sha256 is our own record of the bytes we read; the sidecar published beside
the asset is `.sha1`, and it matches.)

The module dependencies in that binary are current: `golang.org/x/net` v0.56.0,
`golang.org/x/text` v0.39.0, `google.golang.org/grpc` v1.82.1, all at or past
their fixed versions. Dependency automation is plainly active and working here,
with roughly seventy modules in flight in #399 at the time of writing. The Go
toolchain is the one input that has not moved with them, because it is selected
by the `go` directive at build time rather than by a module requirement.

The Dependency Dashboard (#32) shows why that distinction bites. Its
Vulnerabilities section lists **one** CVE for `gomod`, `GO-2026-5932` against
`golang.org/x/crypto`, noting `0`/`1` have Renovate fixes. None of the five
below appear there, because `stdlib` is not a module dependency and so is not
in scope for that check. The dashboard does detect `go 1.26.3` under
`gomod → go.mod`, but it is listed without an update proposal, while the modules
beneath it each carry one.

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

`govulncheck -mode=binary` against the v12.8.0 release asset above, unpacked
from the zip. All five are reported at **symbol** level, meaning govulncheck
resolved a call path to a function, not merely a linked module. Package and
symbol columns are reproduced as the tool emitted them:

| Level | Advisory | Alias | Module | Version | Package | Symbol |
|---|---|---|---|---|---|---|
| symbol | GO-2026-4970 | CVE-2026-39822 | stdlib | v1.26.3 | `os` | `ReadFile` |
| symbol | GO-2026-5037 | CVE-2026-27145 | stdlib | v1.26.3 | `crypto/x509` | `Error` |
| symbol | GO-2026-5038 | CVE-2026-42504 | stdlib | v1.26.3 | `mime` | `DecodeHeader` |
| symbol | GO-2026-5039 | CVE-2026-42507 | stdlib | v1.26.3 | `net/textproto` | `ReadMIMEHeader` |
| symbol | GO-2026-5856 | CVE-2026-42505 | stdlib | v1.26.3 | `crypto/tls` | `Dial` |

The `Version` column is govulncheck reading the toolchain out of the binary
independently of the `go version -m` output above, so the two agree on v1.26.3
by separate routes.

One further finding in the same run is not a toolchain issue and is listed here
so the table is not read as selective: GO-2026-5932, `golang.org/x/crypto`
v0.53.0, at symbol level in `openpgp/elgamal`. That advisory has **no fixed
version**, because it records that `x/crypto/openpgp` is unmaintained and unsafe
by design rather than a defect to patch. v0.53.0 is current.

### Why the next release would repeat it

`.github/workflows/publish.yml` calls
`grafana/plugin-ci-workflows/.github/workflows/cd.yml@ci-cd-workflows/v10.1.0`
without a `go-version` input. That workflow resolves the version as:

> 1. If explicitly provided as input, use that
> 2. If a version file (`.nvmrc`/`go.mod`) exists in the plugin directory, use that
> 3. Otherwise, use the workflow-level default version

No input is passed and `go.mod` exists, so rule 2 applies: the `go` directive
**is** the release toolchain. At `go 1.26.3` on `main` today, the next release
inherits all five advisories again.

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
`usr/share/grafana/data/plugins-bundled/elasticsearch/gpx_grafana_elasticsearch_datasource_linux_amd64`
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

1. **Bump the `go` directive in `go.mod` to `1.26.5`**, the version that clears
   all five. `grafana/grafana`'s own `go.mod` is already there.
2. **Cut a release.** v12.8.0 is six days old, so the code is current; it is
   only the toolchain that is behind.

Passing `go-version: "1.26.5"` explicitly to the CD workflow would also work
(rule 1 above), but moving `go.mod` keeps CI, dev and release on one number.

## Question

**Should the toolchain be covered by dependency automation here?** Renovate
detects `go 1.26.3` in #32 but proposes no update for it, and its vulnerability
check does not cover `stdlib` at all. So the repo can be fully green on
dependencies, as it very nearly is, while every released binary carries five
advisories. Whether the shared preset this repo extends is meant to bump the
`go` directive we could not tell, since `grafana/grafana-renovate-config` is not
public.

## Related

- `grafana/sentry-datasource#736`, the same five stdlib advisories on another
  plugin, reached by a different route (stale release rather than a pinned
  directive).
- `grafana/grafana#124023`, the broad "CVEs in Grafana Docker images" thread. A
  comment there (2026-05-15) names bundled plugin binaries as a source; this
  draft is the specific, measured case.

---

Happy to re-run any of the above, or to supply the full `govulncheck` JSON.
