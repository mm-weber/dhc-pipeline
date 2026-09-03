# 13.1.5 links `apache/thrift` and `grpc-go` below their fixed versions (CVE-2026-43871, CVE-2026-84304); `main` already has thrift 0.24.0

**Target repo:** `grafana/grafana`
**Drafted:** 2026-09-03
**Filed:** 2026-09-03 as
[grafana/grafana#131921](https://github.com/grafana/grafana/issues/131921).
The issue body is this file from `## Summary` down, unmodified. Measurements
reproduce with
[`checks/grafana-server-pins.sh 13.1.5 33098073184`](checks/grafana-server-pins.sh).

---

## Summary

The published **13.1.5** server binary links two Go modules below the versions
their advisories name as fixed:

| Module linked by `bin/grafana` 13.1.5 | Advisory | Fixed in |
|---|---|---|
| `github.com/apache/thrift` v0.23.1-0.20260429145742-d2acd3c49e58 | CVE-2026-43871 (GHSA-8wv5-x4w7-5gww, high): infinite loop in the Go binding | 0.24.0 (2026-07-11) |
| `google.golang.org/grpc` v1.82.1 | CVE-2026-84304 (GHSA-vp52-pcj8-j9qc, high): heap exhaustion via HTTP/2 DATA frame fragmentation | 1.83.1 |

Half of this is already done on `main`: its `go.mod` pins `github.com/apache/thrift v0.24.0`
(indirect) today, so the thrift fix is in the repository and has not reached the
13.1 line. `main` pins `google.golang.org/grpc v1.83.0`, one patch release short
of the grpc fix.

We ship a hardened repackage of the release tarball, so we cannot move either pin
ourselves; only a release can.

## Evidence

### What the published artifact links

Read from the binary's own build info, not from `go.mod`. The artifact is the
release asset `grafana_13.1.5_33098073184_linux_amd64.deb` from the v13.1.5
GitHub release (sha256
`15c8ace2a6a5dad26f65fed574aeef90da54dd443cc9687e5c696b726944a62e`), extracted
with `dpkg-deb -x`:

```
$ go version -m /usr/share/grafana/bin/grafana
/usr/share/grafana/bin/grafana: go1.26.6
	dep	github.com/apache/thrift	v0.23.1-0.20260429145742-d2acd3c49e58	h1:rDLE+tSW60VzRD7v5I+DU22Mjhmm+mfLc5Xl5dHkx6w=
	dep	github.com/uber/jaeger-client-go	v2.30.0+incompatible	h1:D6wyKGCecFaSRUpo8lCVbaOOb6ThwMmTEbhRwtKR97o=
	dep	google.golang.org/grpc	v1.82.1	h1:NnAxzGRA0677vCa4BUkOAnO5+FfQqVl9iUXeD0IqcGE=
```

The thrift pin is a pseudo-version of a 2026-04-29 commit. The advisory names
no fixing commit, so we could not check ancestry directly; what we can say is
that every change to `lib/go` between that commit and the 0.24.0 tag (the
container-size prechecks of 2026-06-17/18, THRIFT-6044's recursion limit of
2026-06-03, the TZlibTransport size limit of 2026-05-21) is dated after the
pinned commit, so the pin predates all of them.

### What the advisories say

From the GitHub Advisory Database, Go ecosystem entries only:

```
GHSA-8wv5-x4w7-5gww CVE-2026-43871 high: github.com/apache/thrift < 0.24.0, fixed 0.24.0
GHSA-vp52-pcj8-j9qc CVE-2026-84304 high: google.golang.org/grpc <= 1.83.0, fixed 1.83.1
```

### What `main` pins today (2026-09-03)

```
	github.com/apache/thrift v0.24.0 // indirect
	google.golang.org/grpc v1.83.0 // @grafana/grafana-catalog
```

## What we measured and what we did not

- **Linked, as shown above.** Both modules are in the binary's build info, and
  `go tool nm` on the (unstripped) server binary lists grpc's server-side HTTP/2
  transport (`internal/transport.(*http2Server)`) and thrift's
  `TCompactProtocol` and `TBinaryProtocol` readers, the latter reached through
  `github.com/uber/jaeger-client-go`.
- **Not measured: reachability.** Neither advisory has a `golang/vulndb`
  report (checked through GO-2026-6355), so `govulncheck` cannot say whether the
  vulnerable functions are on a call path. We therefore make no claim that
  either is or is not exploitable in a default deployment; the defaults we
  read (`[grpc_server]` bound to `127.0.0.1:10000`, Jaeger tracing off unless
  configured) are context, not a measurement.

## Ask

1. Move `google.golang.org/grpc` to **v1.83.1** on `main` (currently v1.83.0).
2. Carry **thrift 0.24.0** (already on `main`) and **grpc 1.83.1** into the next
   13.1.x and 13.2.x patch releases, so that a published server binary stops
   linking both below their fixed versions.

## Related, not part of this ask

13.1.5 bundles the Zipkin datasource plugin **v12.4.6** (`go1.26.4`,
`google.golang.org/grpc v1.82.1`) under `data/plugins-bundled/zipkin/`, while
the plugin's own **v12.4.7** (2026-08-27) is built with `go1.26.7` and grpc
1.83.1 and clears every advisory the bundled copy carries. Whatever selects the
bundled version at release time picked the older one. Tracked separately on the
plugin's tracker (grafana/grafana-zipkin-datasource#94).
