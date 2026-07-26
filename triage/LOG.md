# Triage log

Dated triage decisions: finding → evidence → outcome. One entry per triage pass.
This file is the *reasoning*; `vex/*.openvex.json` is the machine-readable form
of the `not_affected` subset, and a fix-bump PR is the machine-readable form of
the `fix` subset. Everything else lives here and nowhere else — which is the
point: the findings we did **not** excuse are as much a part of the record as
the ones we did.

## Rules this log holds itself to

Only *inapplicability* justifies `not_affected`. Three outcomes get confused and
must not be:

| Outcome | Means | Where it goes |
|---|---|---|
| `not_affected` | The vulnerable code cannot execute here | OpenVEX statement + this log |
| **prioritisation** | It is real, but low EPSS / not KEV, so it waits | this log only |
| **accepted risk** | It is real and reachable; we ship anyway | this log only, with an owner |

Writing "low risk" or "we accept it" into a VEX is **VEX-washing**: it launders a
business decision into a machine-readable claim of technical inapplicability,
and every downstream consumer inherits the lie. EPSS and KEV order the queue;
they never justify a status.

---

## 2026-07-26 — first triage pass (task 7.3, Req 6.4 / 6.5)

Eight open findings from the daily rescan (issues #22–#28, #30). Sorted by what
we can actually *do*, which is a property of the image's archetype:

- **cert-manager-\*** compile from source in our own pipeline → in principle we
  can patch a vulnerable transitive dependency ahead of upstream. In practice
  that needs the frontend's bump action, not a shell step; see #28 below.
- **grafana** is a tarball repackage of upstream's prebuilt binary → its
  dependency graph is fixed at upstream's build time. We can bump the whole
  release or we can reason about reachability. We cannot patch a single module.

That asymmetry, not severity, drove every decision below.

### AFFECTED, no fix mechanism — GHSA-hrxh-6v49-42gf, `google.golang.org/grpc` v1.81.1 (#28)

*Images: cert-manager-controller, cert-manager-webhook, grafana.*

This was triaged as a **fix** and attempted as one. Both assumptions behind that
were wrong, and the build proved it — recorded here because the failed attempt
is the useful part.

**There is no upstream release to bump to.** cert-manager v1.21.0 is the newest
release (2026-07-08, checked against the releases API), and its root `go.mod`
carries `google.golang.org/grpc v1.81.1 // indirect`. Renovate is already on the
newest tag; the version-bump path is closed.

**And the dependency cannot be patched from a pipeline step.** The obvious move
for a compile-from-source image — `go get google.golang.org/grpc@v1.82.1` before
`go/build` — fails in the sandbox:

```
+ go get google.golang.org/grpc@v1.82.1
go: cel.dev/expr@v0.25.1: Get "https://proxy.golang.org/…":
   dial tcp: lookup proxy.golang.org … network is unreachable
```

**The DHI pipeline sandbox has no egress.** That is a hardening property, not a
misconfiguration: a build step cannot reach out and fetch something the
definition did not declare. Which means dependency surgery has to happen in the
frontend's *fetch* phase, and that is precisely why the catalog ships a Go bump
action instead of leaving this to `runs:`. `runs:` is not an alternative to it.

**Outcome: affected, accepted for now, tracked.** No VEX statement — grpc is
reachable in all three images (cert-manager serves gRPC APIs; Grafana's plugin
transport runs over gRPC via go-plugin), and the "we do not use xDS" argument
covers only part of the advisory. A partial-inapplicability argument is not a
`not_affected` status.

**Next mechanism to try:** the frontend's Go bump action in the fetch phase. Its
parameter schema is not primary-verified in our research notes
(`data/docker_internal_build.md` lists `go/build`, `helm/rudder`, `helm/cmd`,
`helm/package` as primary-verified; a Go bump action appears only via a
secondary source), so establishing it costs a CI round trip against the
frontend's error output. Worth doing — it is the mechanism that unblocks every
future between-releases CVE on a from-source image.

### NOT AFFECTED — CVE-2026-28377, `github.com/grafana/tempo` (#27)

Tempo's HTTP `status/config` handler discloses the S3 encryption key from a
running Tempo server's configuration. This image runs Grafana's dashboard server
(`/usr/share/grafana/bin/grafana`), which vendors Tempo as a **query-side client
library** for the Tempo datasource. It does not start a Tempo server, does not
register Tempo's status routes, and holds no S3 configuration to disclose.

**Outcome: `not_affected`, `vulnerable_code_not_in_execute_path`.**
→ `vex/CVE-2026-28377.openvex.json`

### NOT AFFECTED — CVE-2026-42151, `github.com/prometheus/prometheus` (#25)

The Prometheus server's config API (`/api/v1/status/config`) echoes an Azure
OAuth client secret from a running Prometheus server's scrape configuration.
Grafana vendors these packages for PromQL parsing and its Prometheus datasource
client. It does not start a Prometheus server, does not serve the Prometheus
HTTP API, and carries no scrape configuration — so there is no Azure OAuth
client secret in this image to leak.

**Outcome: `not_affected`, `vulnerable_code_not_in_execute_path`.**
→ `vex/CVE-2026-42151.openvex.json`

### FIX — stdlib CVE-2026-27145 / -42504 / -39822 (#22, #24, #26)

`crypto/x509` DoS via DNS SAN processing, `mime` DoS via crafted headers, and
`os.Root` symlink traversal, all in the Go **1.26.3** standard library that
upstream built Grafana 13.0.4 with.

These are not excusable. `crypto/x509` and `mime` are on the path of any TLS
handshake and any multipart request a dashboard server handles; the vulnerable
code is linked and reachable. Nor are they fixable by us: the toolchain is
upstream's build-time choice, and a repackage image inherits it. (Our own images
are unaffected — they compile with `dhi.io/golang:1.26.5`, which is exactly why
these three appear on grafana and nowhere else in the catalogue.)

**Outcome: FIX — bumped 13.0.4 → 13.1.1 in this pass (Req 6.5).** The only
lever on a repackage image is the whole release, and 13.1.1 is the first one
past 13.0.x. Whether it actually clears these three is an empirical question,
not a judgement call: the gate re-scans the rebuilt image on this PR and the
daily rescan closes the issues that disappear. Any that survive come back here
as accepted risk with an owner, not as a VEX.

The bump was forced anyway — see the integrity entry below — but it is the
right fix on its own merits.

### UNDER INVESTIGATION — GHSA-r277-6w6q-xmqw, `github.com/getkin/kin-openapi` (#30)

CRITICAL, and the one finding where the honest answer is "we do not know yet".
The advisory is a fail-open authentication bypass in `ValidationHandler.Load()`
when it defaults to `NoopAuthenticationFunc` — a *middleware misuse* pattern, so
whether it applies depends entirely on whether Grafana wires that handler as an
authenticating middleware, or merely vendors kin-openapi for OpenAPI schema
handling.

That is a symbol-level reachability question, and it deserves a symbol-level
answer. The tool is `govulncheck -mode=binary` against the shipped Grafana
binary, which distinguishes "module is linked" (all Trivy and Grype can see)
from "vulnerable symbol is called".

**Outcome: none yet.** No VEX statement, because "probably not exploitable" is
not a justification. Gate stays red on this finding until it is answered, which
is the correct pressure. See the follow-up below.

### SUPPLY CHAIN — we pinned one artifact and downloaded another

Not a CVE, and the most serious thing this pass found. The first two diagnoses
were wrong; the measurements that corrected them are below.

Grafana publishes each release tarball at **two** paths:

| Path | Shape |
|---|---|
| per-build | `…/grafana/release/<ver>/grafana_<ver>_<build-id>_linux_<arch>.tar.gz` |
| version alias | `…/oss/release/grafana-<ver>.linux-<arch>.tar.gz` |

They are **not the same bytes**. For 13.0.4:

| | amd64 | arm64 |
|---|---|---|
| per-build `.sha256` | `cd8c8b31…` | `bcf8b9fb…` |
| alias `.sha256` | `cd8c8b31…` | `591ac184…` |
| alias **actual content** | `54eceec7…` | `591ac184…` |

Read the first column carefully. **Our original pins — `cd8c8b31…` and
`bcf8b9fb…` — are exactly the per-build values.** They were correct when
written and are still correct. What broke is that the definition *pinned* the
per-build artifact while *downloading* the alias. Those agreed at authoring
time and have since diverged.

On amd64 the alias content was replaced and its sidecar was not regenerated, so
the alias now contradicts itself. On arm64 both moved together, so the alias is
self-consistent but is a different build from the one we pinned. 13.1.1 splits
the same way (`e4744321…` per-build vs `0c071169…` alias).

That also explains the flapping. Pinned to the alias' value, the same URL and
digest **passed at 21:06Z, failed at 21:54Z, and passed again** on the next run
— the alias does not serve stable bytes.

**Two earlier conclusions in this log were wrong and are retracted:**

- *"Upstream silently replaced the artifact and our pin caught it."* Partly. The
  alias changed, but our pin was never describing the alias.
- *"Our arm64 pin never matched upstream."* Wrong. It matches the per-build
  artifact precisely. It only looked wrong when compared against the alias.

**Fix: pin and download the per-build artifact.** The build id is not derivable
from the version, but it is recoverable — it appears in the GitHub release asset
names (`grafana_<ver>_<id>_linux_amd64.deb`), and GitHub is already this
definition's Renovate datasource. So the version stays the single knob Renovate
turns, `refresh-grafana.sh` resolves the id and rebuilds the url, and the
artifact we verify is the artifact we fetch. A re-cut release lands at a new
build-id URL rather than overwriting ours.

**Still worth reporting upstream**, and the report is now much sharper than
"a checksum is wrong": a version alias serving different bytes than the
per-build artifact of the same release, with a stale sidecar on one arch. Draft
in [`upstream/2026-07-26-grafana-13.0.4-checksum-drift.md`](upstream/2026-07-26-grafana-13.0.4-checksum-drift.md).

**Method note.** Three diagnoses in a row, each overturned by the next
measurement: "bad pin", then "upstream replaced the artifact", then "two paths,
two artifacts". Each was consistent with the evidence available at the time.
The one that survived came from asking what *else* upstream publishes rather
than re-reasoning about the numbers already in hand.

### Post-bump rescan — what 13.1.1 actually changed

The empirical answer to "does bumping fix it", from the gate's scan of the
rebuilt image. 16 findings (1 CRITICAL, 15 HIGH), and the shape matters more
than the count:

| Binary | Findings |
|---|---|
| `bin/grafana` (main) | kin-openapi **CRITICAL**, tempo ×2, grpc |
| `plugins-bundled/elasticsearch/…` | grpc, stdlib ×3 |
| `plugins-bundled/zipkin/…` | x/net ×4, grpc, stdlib ×3 |

**The bump worked for the main binary.** The three stdlib findings
(#22/#24/#26) are gone from `bin/grafana` — 13.1.1 was built with a patched Go
toolchain, exactly the lever we predicted. Prometheus (#25) disappeared
entirely; 13.1.1 carries a fixed version.

**The residue is in bundled plugin binaries.** Grafana ships prebuilt datasource
plugins, and those were *not* rebuilt with the new toolchain — they still report
`stdlib v1.26.3` and older grpc (v1.80.0, v1.79.3 — older than the main
binary's v1.81.1). Two consequences:

- The stdlib findings are no longer a whole-image property. They are confined to
  plugins that only execute when the matching datasource is configured, which is
  a materially different exposure from "on the path of every TLS handshake".
  That is a **reachability** distinction, and the right way to settle it is
  govulncheck per binary, not an assertion.
- **New findings appeared that no issue tracks**: `golang.org/x/net` ×4 in the
  zipkin plugin (CVE-2026-25681, -27136, -33814, -39821). Bumping a repackage
  image does not monotonically reduce findings — it swaps one dependency graph
  for another. The daily rescan will file these; they are recorded here first so
  the swap is not mistaken for a regression in the gate.

**#25 (prometheus) — outcome corrected: fixed by the bump, not `not_affected`.**
The statement in `vex/CVE-2026-42151.openvex.json` is retained because its
reasoning is version-independent and would hold again if the module returned,
but it is currently **inert**: the finding it excuses no longer exists. Logging
this because "the VEX worked" and "the finding went away" look identical from a
count, and only one of them is true here.

---

### Evidence gap, stated plainly

The two `not_affected` statements rest on **architectural** analysis — what the
shipped entrypoint is, and what the advisory's affected component is — not on
symbol-level proof. That reasoning is sound and checkable, and it is written
into each statement's `impact_statement` so a reader can disagree with it. But
it is weaker than a measurement.

Closing that gap needs `govulncheck -mode=binary` in CI, which is not yet wired.
Two constraints shaped this: the devcontainer cannot reach `vuln.go.dev` or pull
the private image (so it cannot be done locally), and our own binaries build with
`-w -s`, which may degrade govulncheck to module-level precision on them.
Grafana's binary is upstream's build and may fare differently.

**Follow-up:** add a govulncheck reachability job to the PR scan path, and
revisit #30 and both `not_affected` statements with it. Until then this
paragraph is the honest caveat on the two statements above.
