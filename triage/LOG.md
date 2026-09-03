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

### SUPPLY CHAIN — upstream overwrote a published release artifact

Not a CVE, and the most serious thing this pass found. Six diagnoses; this is
the one that survived every measurement we could make.

Grafana publishes each release tarball at **two** paths:

| Path | Shape |
|---|---|
| per-build | `…/grafana/release/<ver>/grafana_<ver>_<build-id>_linux_<arch>.tar.gz` |
| version alias | `…/oss/release/grafana-<ver>.linux-<arch>.tar.gz` |

**The alias objects are rewritten about a day after release.** Object creation
times, from GCS metadata (`last-modified` / `x-goog-generation`):

| | per-build written | alias written |
|---|---|---|
| 13.0.4 amd64 | 2026-07-21 09:56:03Z | **2026-07-22 05:36:05Z** |
| 13.0.4 arm64 | 2026-07-21 09:56:14Z | **2026-07-22 05:36:34Z** |
| 13.1.1 amd64 | 2026-07-21 08:53:04Z | **2026-07-22 05:42:05Z** |
| 13.1.1 arm64 | 2026-07-21 08:53:16Z | **2026-07-22 05:42:36Z** |

All four alias objects landed within six minutes of each other, ~20 hours after
their per-build counterparts. That is a batch job re-publishing a coordinated
release, not an incident.

We were caught across the rewrite:

| UTC | Evidence | Result |
|---|---|---|
| 07-21 20:57 | run `29867929092`, SLSA provenance | alias fetched, `cd8c8b31…` / `bcf8b9fb…`, **OK** |
| 07-22 05:36 | GCS object generation | alias **overwritten** |
| 07-26 19:01 | run `30215944820` | alias amd64, `did NOT match` `cd8c8b31…` |
| 07-26 20:49 | run `30219798190` | alias amd64, `did NOT match` `cd8c8b31…` |

The 13.0.4 release we published was built from bytes that no longer exist at
the URL it fetched them from. Nothing changed on our side — the artifact moved
under a correct pin.

**The two paths permanently serve different bytes.** Confirmed on all four
objects, three verified passes each, every one internally consistent with its
own sidecar:

| | alias | per-build | delta |
|---|---|---|---|
| 13.0.4 amd64 | `54eceec7…` 337 697 955 B | `cd8c8b31…` 337 694 041 B | +3 914 |
| 13.0.4 arm64 | `591ac184…` 321 125 583 B | `bcf8b9fb…` 321 121 554 B | +4 029 |
| 13.1.1 amd64 | `0c071169…` 363 257 098 B | `e4744321…` 363 255 678 B | +1 420 |
| 13.1.1 arm64 | `8403dc0b…` 345 122 382 B | `28ef74a3…` 345 128 051 B | −5 669 |

A ~0.001% delta that changes sign between arches is repackaging — tar metadata,
gzip framing — not different content.

**There is no stale sidecar.** The 13.0.4 amd64 alias object was written at
05:36:05Z and its `.sha256` at 05:36:08Z — three seconds apart. They have never
disagreed. The 07-26 workstation read that returned the pre-rewrite value came
from a stale cache, not from upstream publishing a contradiction.

**Every earlier conclusion in this log about this finding was wrong and is
retracted:**

- *"Our pin was bad."* No. It verified on both arches on 2026-07-21.
- *"Our arm64 pin never matched upstream."* No. Provenance records the alias
  arm64 content hashing to exactly `bcf8b9fb…`, the value we had pinned.
- *"We pinned the per-build artifact while downloading the alias."* No. The
  pins came from the alias sidecar (`79a2bde`) and CI verified them against
  alias content.
- *"The alias serves content its own sidecar disowns."* No. Written three
  seconds apart, consistent ever since.

**The flapping** — 13.1.1 alias pinned `0c07116…`, passing 21:06Z, failing
21:55Z, passing 22:16Z — is not upstream instability. That object has been
stable since 07-22 05:42. The likeliest cause is a CDN edge still serving the
pre-rewrite generation, which would also explain the stale sidecar read on the
same day. Untested: `curl --resolve` against individual edge IPs would settle
it.

**Fix: pin and download the per-build artifact.** The build id is not derivable
from the version, but it is recoverable — it appears in the GitHub release asset
names (`grafana_<ver>_<id>_linux_amd64.deb`), and GitHub is already this
definition's Renovate datasource. So the version stays the single knob Renovate
turns, `refresh-grafana.sh` resolves the id and rebuilds the url, and the
artifact we verify is the artifact we fetch. A re-cut release lands at a new
build-id URL rather than overwriting ours.

**Still worth reporting upstream**, but far narrower than the first draft: a
published release artifact was overwritten ~20 hours after publication,
breaking a consumer that pinned the digest served at release time. Not "your
checksum is broken" — everything upstream publishes is internally consistent.
Draft in
[`upstream/2026-07-26-grafana-oss-release-alias-overwritten.md`](upstream/2026-07-26-grafana-oss-release-alias-overwritten.md).

**Method note.** Six diagnoses: "bad pin" → "upstream replaced the artifact" →
"two paths, two artifacts" → "replaced, sidecar left stale" → and finally
"rewritten on a schedule, sidecar always fine, and the two paths really are two
artifacts." Diagnoses 2 and 3 were each partly right and each retracted in
error. The cost was a wrong rationale committed to the definition, a stale
comment left in `refresh-grafana.sh`, and two upstream drafts built on
mechanisms we could not support.

Three habits caused it, in increasing order of embarrassment:

1. **Measuring by hand.** Every number in the early diagnoses came from
   `curl -sSL <url> | sha256sum` — no `--fail`, no `-o`, no length check, on a
   ~322 MiB object. That command hashes a truncated body without complaint. It
   happened not to be wrong here, which is luck, not method.
2. **Ignoring our own build record.** Every build logs its `sha256sum -c` line;
   every release build records the source URL and digest in SLSA provenance.
   Both sat in GitHub Actions the whole time and nobody read them until the
   fourth pass.
3. **Never asking the object what it was.** This was settled by two HTTP
   headers — `last-modified` and `x-goog-generation` — on objects we had been
   arguing about for a week. Four `curl -I` calls at any point would have ended
   it.

**Ask the artifact, then ask your own pipeline, then measure by hand.** We did
it in exactly the wrong order. `scripts/verify-arch-pins.sh` closes the related
gap: every pinned arch is now fetched and checked in CI, not just the one the
PR gate happens to build. The host-side checks that produced the tables above
are kept in [`upstream/checks/`](upstream/checks/) so any of this can be
re-measured.

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

**Where these numbers come from, and what the second tool says.** The table
above is Trivy's, taken from the gate's job summary. Grype ran on the same image
as the CRITICAL second opinion (Req 6.6) and reports **six** HIGH/CRITICAL where
Trivy reports sixteen. The gap is stdlib ×6 and x/net ×4, which grype either
does not flag or rates lower: it sees a single x/net advisory
(`GHSA-5cv4-jp36-h3mw`) and calls it Medium, not four HIGH. That is not a
contradiction, since the two databases split advisories differently, but the
per-binary attribution above has exactly one source and should be read that way.

Grype did corroborate the central claim without being asked for it. Its output
lists `google.golang.org/grpc` at **three different versions in one image**:
v1.79.3, v1.80.0 and v1.81.1. A single Go binary links one version of a module,
so three versions means three binaries, compiled at different times. That is the
bundled-plugin thesis falling out of an independent tool that was only present
to double-check a CRITICAL.

**"New in 13.1.1" rests on absence of evidence.** There is no CI scan of grafana
at 13.0.4 to diff against: the scan gate landed 2026-07-22, after that image was
built, and every grafana PR build since has either failed before the scan or run
on 13.1.1. What stands in for a diff is the daily rescan, which still scans the
*published* 13.0.4 image and has filed no x/net issue across 07-27, 07-28 and
07-29 (7 distinct HIGH/CRITICAL over all images). Three passes with current
advisory data would have filed them if they were present. Good evidence, but not
a before/after diff, and the table above should not be read as one. Merging the
bump closes the gap for free: the rescan will then hold scans of both tags.

---

### Evidence gap, stated plainly — CLOSED 2026-07-30, see below

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

*The follow-up landed. It cost one of the two statements.*

---

## 2026-07-30 — the gate could not suppress, and what that hid

Two findings, and the second one only exists because of the first.

### The scan gate has never applied a VEX statement, and could not have

`triage/vex/` has been wired into the PR gate since 2026-07-22. It has
suppressed nothing in that entire time, on any run. The gate's own
"⚠️ statements exist but suppressed nothing here" warning fired correctly every
time and pointed at the product identifier — which the same summary printed as
`<unavailable>`, for the same underlying reason nobody connected.

**Cause.** Trivy builds the `pkg:oci/...` product purl a statement has to match
out of the image's **RepoDigest**. `docker/build-push-action` with
`load: true, push: false` produces an image that has none — never pushed, never
pulled — so Trivy's root component came out with a random UUID `bom-ref` and no
`purl` field at all. There was nothing for a product identifier to match.

This is not a defect in our statements' shape. With no root purl, **no** product
identifier matches in any form:

| Product `@id` | digest present | digest absent |
|---|---|---|
| `pkg:oci/grafana@sha256:…?arch&repository_url` | suppressed | 0 |
| `pkg:oci/grafana?repository_url=…` (ours) | suppressed | 0 |
| `pkg:oci/grafana` bare | suppressed | 0 |
| `ghcr.io/mm-weber/dhc/grafana:13-alpine3.23` | — | 0 |

Reproduced locally with `trivy image --input <docker-save tarball>`, which has
the same empty-`RepoDigests` shape, and confirmed against a digest-bearing copy
of the same image where every form suppresses. Upstream has this as
[trivy#9399](https://github.com/aquasecurity/trivy/issues/9399) — "null PURL for
local images breaks VEX matching" — agreed but unshipped as of 0.72.0, measured
rather than assumed.

**The asymmetry worth noticing:** the `accepted-risk` lane was never affected.
`--ignorefile` matches on *package* purls, not the OCI root, so it works with or
without a digest — verified. The weaker lane worked the whole time; the stronger
one silently did not.

**Fix.** A push is the only thing that mints a RepoDigest, so the PR path pushes
to a throwaway local registry and scans that. Because the registry host is no
longer ghcr.io, the gate scans copies with the purl qualifiers stripped;
published statements stay precisely scoped and are what `cosign attest` attaches.
That blinds the gate to exactly one field, which was measured, not assumed —
with qualifiers stripped it still catches a wrong image name, a near-miss name,
a wrong purl type and a wrong subcomponent. `scripts/lint-vex-product.sh`
(Req 6.17–6.19) covers the registry host by exact string comparison, which is a
stronger check than "did a finding disappear".

**Method note, and it is the same one as last time.** Both symptoms — the inert
statements and the `<unavailable>` identifier — were printed by our own job
summary for over a week. The summary was written to `$GITHUB_STEP_SUMMARY` only,
which needs a scope this repo's PAT does not have, so nobody could read it from
where the work happens. *Ask your own pipeline first* was the lesson recorded on
2026-07-26. It was recorded and then not applied.

### RETRACTED — CVE-2026-28377, `github.com/grafana/tempo` (#27)

The statement written on 2026-07-26 is **withdrawn**, and
`vex/CVE-2026-28377.openvex.json` is deleted.

It claimed `vulnerable_code_not_in_execute_path`. The govulncheck job that
landed the same day measures the opposite, on the shipped binary:

```
symbol | GO-2026-5359 | CVE-2026-28377, GHSA-ffqx-q65f-36jf
       | github.com/grafana/tempo v1.5.1-0.20260427112133-525d1bab07e0
       | github.com/grafana/tempo/pkg/tempopb/resource/v1 | MarshalTo
```

**Req 6.14 forbids that combination** — a reachable symbol may not be excused as
not-in-execute-path — and 6.14 was written the same week, by us, for exactly
this case.

There is an argument for the statement, and it is not good enough. `MarshalTo`
is protobuf codegen, reached because Grafana speaks tempopb as a **client**;
the advisory is about a Tempo *server's* `status/config` handler disclosing an
S3 key. So a symbol from the affected module is called, but plausibly not the
disclosing path. That is exactly the shape of reasoning the measurement exists
to discipline: upstream lists the symbol as affected, we do not get to
re-scope their advisory from the outside, and "plausibly not" is not evidence.

**Outcome: no treatment. The gate stays red on #27**, alongside #23. It is
triaged with the rest of the open findings rather than excused on its own.

Note what nearly happened. The statement was wrong from the day it was written,
and the broken gate hid that — a suppression that suppresses nothing is
indistinguishable from one that is right. Fixing the plumbing is what made it
falsifiable, and the first thing it did was falsify it.

### Still open

18 uncovered on grafana (1 CRITICAL, 17 HIGH), across three binaries:

| Binary | Findings |
|---|---|
| `bin/grafana` | kin-openapi **CRITICAL**, tempo (#23), x/text (#39), grpc (#28) |
| `data/plugins-bundled/elasticsearch/…` | stdlib ×3, x/text, grpc |
| `data/plugins-bundled/zipkin/…` | x/net ×4, stdlib ×3, x/text, grpc |

**govulncheck cannot answer #30.** Zero mentions of kin-openapi across all 37 of
its findings, and it does report module-level results when it cannot resolve
symbols — so the advisory is simply not in the Go vulnerability database. It is
GHSA-only. The tool built to settle our one CRITICAL cannot see it, and that
needs saying plainly rather than being read as a clean result.

govulncheck also found **8 findings Trivy missed** (x/net CVE-2026-46600,
-42506, -42502, -25680; otel; klauspost/compress; aws-sdk-go). Three scanners,
three different answers, and the union is larger than any one of them.

## 2026-08-03 — a fix that arrived on its own, and the lint rule it broke

### FIXED — CVE-2026-42151, `github.com/prometheus/prometheus` (#25)

The statement written on 2026-07-26 argued `vulnerable_code_not_in_execute_path`.
It is now **superseded** rather than withdrawn: the finding is gone, because the
13.0.4 → 13.1.1 bump carried a fixed Prometheus.

Four points, two of them independent of any scanner:

| | |
|---|---|
| Issue #25 | `prometheus/prometheus` **v0.305.3**, fixed in **0.311.3** |
| grafana **13.0.4** `go.mod` | `replace prometheus/prometheus => v0.305.3` — where the vulnerable version came from |
| grafana **13.1.1** `go.mod` | requires **v0.312.0**, replace directive gone |
| our 13.1.1 scan | reports CVE-2026-42151 nowhere — not uncovered, not suppressed |

The middle two are upstream source. They say the same thing the scanner says,
without depending on it.

**Outcome: `fixed`, scoped to `13.1.1-alpine3.23`.** The 2026-07-26
`not_affected` statement is **kept verbatim**, timestamp untouched, and the
`fixed` statement is appended with a later one; the document goes to `version: 2`
with `last_updated` set (Req 6.22). OpenVEX consumers take the latest statement
per (vulnerability, product), so nothing is lost and nothing is stale.

Deleting it would have left only the outcome. The argument we made in July — and
whether it was any good — is the part worth being able to re-read.

→ `vex/CVE-2026-42151.openvex.json`

### The lint forbade the only honest way to say it

Writing that statement failed `scripts/lint-vex-product.sh`, which rejected a
version on **every** product purl and reported it as Req 6.17 — a rule the spec
never actually stated.

The rule was half right, and had looked entirely right because until now every
statement in this repo had the same status:

- **`not_affected`** claims the vulnerable code cannot execute *in this image*.
  That holds across rebuilds, so the product must stay versionless. A pinned
  digest would suppress until the next build and then silently stop matching —
  the failure mode this whole lane exists to prevent.
- **`fixed`** claims that *particular versions* carry the remedy. Stated
  versionless it excuses the CVE on every image ever published under that name,
  including `13.0.4-alpine3.23`, which is still in the registry and still
  vulnerable. That is not a scoping detail; it is a false claim.

Now Req 6.20/6.21 split on the status, and the linter reads it. A `fixed` product
names the published **tag**, not a digest: every build of 13.1.1 carries the fix,
so a digest would be wrong by being narrower than the claim. `vexctl`'s own
examples do the same — versioned product for `fixed`, bare for `not_affected`.

Two gaps left open on purpose, so they are not mistaken for covered: nothing
checks that `status` is one of OpenVEX's four labels, so a `"Fixed"` typo lints
clean and suppresses nothing with any consumer; and nothing checks that a
superseding statement's timestamp is actually later than the one it supersedes.
The tests guard 6.22's shape, not its semantics.

### Measured, not predicted: 19 uncovered

The 2026-07-30 entry above projected 18 (1 CRITICAL, 17 HIGH). The run on
`ccae635` measured **1 CRITICAL + 18 HIGH**: retracting #27 returned tempo
`CVE-2026-28377` to `bin/grafana`, which now carries five findings, not four.

| Binary | Findings |
|---|---|
| `bin/grafana` | kin-openapi **CRITICAL** (#30), tempo ×2 (#23, #27), x/text (#39), grpc (#28) |
| `data/plugins-bundled/elasticsearch/…` | stdlib ×3, x/text, grpc |
| `data/plugins-bundled/zipkin/…` | x/net ×4, stdlib ×3, x/text, grpc |

**All 18 HIGH are `symbol`-level reachable**, so Req 6.14 forecloses
`not_affected` on every one of them. The remaining exits are fix, transfer,
accept and avoid. `fix` is spent at the image level — 13.1.1 is the newest
grafana release, nothing since 2026-07-21.

None of these are treated yet. They are triaged one at a time, from
`bin/grafana` down.

## 2026-08-04 — first treatment: CVE-2026-27145 (#22)

### TRANSFER — stdlib CVE-2026-27145, two bundled plugin binaries (#22)

`crypto/x509` quadratic complexity parsing DNS names in a certificate
(GO-2026-5037, CWE-407, HIGH). Fixed in Go 1.25.11 and 1.26.4. EPSS 0.0094 as of
2026-07-23, not on the CISA KEV catalogue. Neither number changes the treatment;
they order the queue.

**Where it is, after the bump.** The 2026-07-26 entry above classified this as
FIX and bumped 13.0.4 → 13.1.1. That worked for `bin/grafana`, which upstream
rebuilt on go1.26.5 and which no longer carries the finding. It did not work for
the two bundled plugin binaries, which upstream ships prebuilt into the release
tarball and which are still go1.26.3:

| Binary | Toolchain | Reachability |
|---|---|---|
| `usr/share/grafana/bin/grafana` | go1.26.5 | finding gone |
| `…/plugins-bundled/elasticsearch/gpx_…` | go1.26.3 | `symbol` |
| `…/plugins-bundled/zipkin/gpx_…` | go1.26.3 | `symbol` |

`symbol` level forecloses `not_affected` under Req 6.14, and correctly so: the
vulnerable function is not merely linked, govulncheck resolved a call path to
it.

**Why the four treatments land where they do.**

*Mitigate* is measured closed, not assumed closed. 13.1.1 is the newest Grafana
release. The newest plugin releases are elasticsearch v12.8.0 and zipkin
v12.4.5, and `go version -m` on the release assets themselves puts both on
go1.26.3, the same toolchain as the bundled copies. There is no version of
anything we could bump to that clears this today.

*Not affected* is foreclosed by the reachability above.

*Avoid* is genuinely available and is being declined, which is worth stating
plainly rather than dressing up as unavailability. The image definition could
exclude both `plugins-bundled/` directories. That would drop the Elasticsearch
and Zipkin datasources from the image, so it would no longer be a drop-in
Grafana, and the catalogue's premise is that these images substitute for the
upstream ones. Declining avoidance is a product judgement, not a technical
constraint, and it is the reason an acceptance is needed at all.

*Transfer* is where it lands. The fix belongs in the plugin repositories: they
resolve their own toolchain through `plugin-ci-workflows` rule 2, from the
`go.mod` in the plugin directory. Grafana's own `go.mod` is already `go 1.26.5`,
and `scripts/catalog-plugins-defaults` in `grafana/grafana` lists both plugins
unpinned, so nothing in the core repository can move them.

**Outcome: TRANSFER, per binary, expiring 2026-11-02.** Two entries rather than
one, because two upstreams on two release schedules own the two halves and
deciding one must not silently decide the other (Req 6.23). The elasticsearch
half waits on
[grafana/grafana-elasticsearch-datasource#410](https://github.com/grafana/grafana-elasticsearch-datasource/issues/410).
The zipkin half waits on
[grafana/grafana-zipkin-datasource#94](https://github.com/grafana/grafana-zipkin-datasource/issues/94),
whose ask is the narrower of the two: the go1.26.4 bump already landed there in
PR #79 on 2026-06-22 and simply has not been released.

Transfer is not absolution. We are still shipping the finding, so it is an
acceptance with an external owner: it lives in `accepted-risk/`, is never
attested (Req 6.8), and expires. The realistic clearing event is a Grafana
release that rebundles plugins built on go1.26.4 or newer, which is expected
inside the window; the daily rescan reports the entry from 14 days out either
way.

### Scope, not status — the July CVE-2026-42151 statement keeps its claim (#25)

Compiling per build made scope mean something, and the first thing it showed was
that our own oldest statement had none. Compiled for a hypothetical grafana
14.0.0, the `not_affected` written on 2026-07-26 about 13.0.4 still applied:

```
as-is    1 statement compiled   <- the July not_affected, on a release nobody examined
scoped   0 statements compiled  <- finding surfaces, forces a fresh call
```

Req 6.31 makes versionless an argument rather than a default. Which scope is
right turns on the kind of claim, not on the status: "this image never starts a
Prometheus server" is as true of 14.0 as of 13.0.4, while "this build does not
reach the symbol" rests on what the release links.

This one is the first kind, and its own `impact_statement` already said so. So
it stays versionless and its `status_notes` now records why, with the token the
lint checks for. **Nothing about the claim, its justification, its impact
statement or its timestamp changed** — Req 6.22 keeps the argument on the
record, and this adds the scope that was previously implicit rather than
restating what was argued.

The alternative was to scope it to `13.0.4-alpine3.23` and leave the text
untouched, which is more faithful to the letter of 6.22. It was not taken
because it narrows a structural claim to one release and would have to be
re-argued on every bump, which is the churn 6.31 exists to avoid. Recorded here
because editing a retained statement at all is a thing that should be visible.

A note on review finding 2.4's own example. It says suppressing on the
still-pullable 13.0.4 is wrong because that image "genuinely carries
prometheus/prometheus v0.305.3". Carrying a vulnerable version is not being
affected — separating the two is what VEX is for — and this statement was
argued about 13.0.4 and claims unreachability there. The defect is forward
coverage only, which 2.4's next paragraph states correctly.

## 2026-08-05 — CVE-2026-21728 is fixed in what we ship (#23)

### FIXED — `github.com/grafana/tempo`, scoped to 13.1.1-alpine3.23 (#23)

Tempo DoS via unbounded search result limits (GHSA-p4r4-xvrq-gvmc, CWE-400,
`AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H`, EPSS 0.0065, not KEV). One binary,
`usr/share/grafana/bin/grafana`.

**The scanner is comparing versions, not code.** `github.com/grafana/tempo` has
no `/v2` module path while its releases are v2.x and v3.x, so those tags are not
consumable through that path and Grafana tracks `main` by commit on the v1 line:

| | |
|---|---|
| grafana 13.1.1 `go.mod` | `github.com/grafana/tempo v1.5.1-0.20260427112133-525d1bab07e0` |
| advisory affected range | `>= 1.3.0, < 2.8.4` (plus the 2.9 and 2.10 branch ranges) |
| fix | `650eb1985a07`, PR #6525, 2026-02-20 |

Every `v1.5.1-0.<anything>` sorts below `2.8.4` by semver, permanently, however
recent the commit. So this reports on a build that carries the remedy, and will
keep reporting on every future one.

**The fix is in the tree we ship**, by ancestry rather than by version string.
GitHub's compare of the fix commit against grafana's pin: `ahead_by 337,
behind_by 0`. The pinned commit contains it.

**Why `symbol`-level reachability does not contradict that.** The fix changed a
*default value*, it did not remove a function, so the symbol is still linked and
still called. govulncheck draws its ranges from the same advisory data and
inherits the same mismatch. Req 6.14 forecloses `vulnerable_code_not_in_execute_path`
for a reachable symbol — this is a different claim with different evidence, and
6.14 does not reach it.

**Outcome: `fixed`, scoped to `13.1.1-alpine3.23`.** Not versionless, and the
scoping is the load-bearing part: the published `13.0.4-alpine3.23` pins
`cbe5f845dc7b`, which the same comparison puts `behind_by 483`. **That image is
genuinely affected**, and a versionless claim would have excused it.
→ `vex/CVE-2026-21728.openvex.json`

Verified in both directions before committing: compiled for a 13.1.1 build the
statement applies and its product becomes that build's digest; compiled for the
published 13.0.4 it is dropped, naming the tag and the build it did not match.

This is also the first statement that could not have worked before today. Until
Req 6.28-6.30 it would have carried a tag straight to Trivy and suppressed
nothing, silently — which is exactly how the CVE-2026-42151 `fixed` statement
sat inert for two days without anyone noticing.

**Not treated here: #27**, `CVE-2026-28377`, same module and the same artifact.
Its fix `bb8ca663` (2026-03-17) is also an ancestor of the same pin,
`behind_by 0`, so it resolves the same way. It needs its own statement rather
than a superseding one, because the 2026-07-26 document was *deleted* during
that retraction rather than retained — Req 6.22 postdates it.

### FIXED — CVE-2026-28377, `github.com/grafana/tempo`, scoped to 13.1.1-alpine3.23 (#27)

Information disclosure of an S3 SSE-C encryption key through Tempo's
`status/config` handler (GHSA-ffqx-q65f-36jf, CWE-326,
`AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N`, EPSS 0.0015, not KEV).

Mechanically this is #23 again — same module, same artifact. Advisory range
`< 2.10.3` sorts every v1-line pseudo-version below the fix by semver,
permanently, so the scanner reports on a build carrying the remedy:

| Comparison | Result |
|---|---|
| fix `bb8ca663` (PR #6711, 2026-03-17) → 13.1.1 pin `525d1bab07e0` | `ahead_by 218, behind_by 0` — fix present |
| fix `bb8ca663` → published 13.0.4 pin `cbe5f845dc7b` | `behind_by 602` — genuinely affected |

**Outcome: `fixed`, scoped to `13.1.1-alpine3.23`.**
→ `vex/CVE-2026-28377.openvex.json`

### This does not reopen the 2026-07-30 retraction

#27 is the finding whose `not_affected` was withdrawn, and the withdrawal was
firm: *"upstream lists the symbol as affected, we do not get to re-scope their
advisory from the outside, and 'plausibly not' is not evidence."* That stands.
The two claims are not the same claim:

| | Retracted 2026-07-30 | Written today |
|---|---|---|
| Says | the vulnerable code is here but cannot execute | the vulnerable code is not here |
| Rests on | an argument about which routes Grafana registers | commit ancestry against the pinned tree |
| Justification | `vulnerable_code_not_in_execute_path` | status `fixed`, no justification field |
| Measured? | no, and govulncheck contradicted it | yes, `behind_by 0` |

Req 6.14 is untouched: it forecloses `vulnerable_code_not_in_execute_path` for a
reachable symbol, and this is not that justification. The symbol is still linked
and still called — `bb8ca663` changed how a config value is *handled*, it did not
remove a function — which is precisely why a reachability tool cannot settle
this and ancestry can.

Hindsight makes the retraction look better, not worse. The July statement was
written while **13.0.4** was the shipped image, and 13.0.4 is `behind_by 602`.
It was wrong twice: wrong justification, and wrong about the very image it was
written for. Today's claim is true only of 13.1.1, which is why it carries that
tag rather than being stated for every release.

**Supersession does not apply here.** The 2026-07-26 document was *deleted*
during the retraction rather than retained, so there is no earlier statement to
carry a later timestamp against; Req 6.22 postdates that decision. This is a
fresh document, and the record of what was argued lives in this log rather than
in the artifact. Nothing was published and then withdrawn either: 13.0.4's
attestations were created 2026-07-21, five days before that statement was
written, and grafana has not been released since.

Verified both directions before committing. Compiled for a 13.1.1 build, all
four statements in the lane apply. Compiled for the published 13.0.4, both
tempo claims are dropped by name and only the structural `not_affected` for
CVE-2026-42151 survives — which is correct, since 13.0.4 genuinely carries both
tempo findings.

## 2026-08-05 — the other two stdlib findings (#24, #26)

Both sit in the same two bundled plugin binaries as #22, both at `symbol` level,
so Req 6.14 forecloses `not_affected` on each. Measured on the real release
assets rather than read off the earlier table:

| Binary | #22 CVE-2026-27145 | #24 CVE-2026-42504 | #26 CVE-2026-39822 |
|---|---|---|---|
| `plugins-bundled/elasticsearch/…` | ✓ | ✓ | ✓ |
| `plugins-bundled/zipkin/…` | ✓ | ✓ | ✓ |
| `bin/grafana` | — | — | — |

`bin/grafana` carries none of them: upstream rebuilt it on go1.26.5. Every one
of these is a property of the go1.26.3 toolchain the two plugin binaries were
built with, which is why one tracker per plugin covers all of them.

### TRANSFER — stdlib CVE-2026-42504, two bundled plugin binaries (#24)

`mime` DoS decoding a crafted header full of invalid encoded-words
(GHSA-h524-452v-82p9, CWE-407, `AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H`, EPSS
0.0056, not KEV). Fixed in go1.25.11 and 1.26.4 — the same fix line as #22.

**Outcome: TRANSFER, per binary, expiring 2026-11-02.** Identical to #22 in
every respect, including the trackers: both upstream issues were written about
the *toolchain* rather than about one advisory, so neither needs amending.

### TRANSFER — stdlib CVE-2026-39822, needs a toolchain nobody has landed (#26)

`os.Root` improperly follows symlinks out of the root on Unix
(GHSA-xcgv-8mv7-v8c7, CWE-61, `AV:L/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:H`, EPSS
0.0018, not KEV). Local vector, unlike the other two, and the only one of the
three whose exit is different.

**Fixed in go1.25.12 / 1.26.5 / 1.27.0-rc.2 — one step past the others.**
Checked against both upstreams' current `go.mod` rather than assumed:

| Repo | `go.mod` on `main` | Clears #22 / #24 | Clears #26 |
|---|---|---|---|
| grafana-zipkin-datasource | `go 1.26.4` | yes, on any release | **no** |
| grafana-elasticsearch-datasource | `go 1.26.3` | no, needs a bump first | **no** |

So a zipkin release cut from `main` today — exactly what issue #94 asks for —
would clear #22 and #24 and leave this one standing. No upstream has landed a
toolchain that fixes it.

**Outcome: TRANSFER, per binary, expiring 2026-10-04 — 60 days, not the 90 the
others carry.** The ceiling is for an acceptance that at least has a route out;
this one's exit is not yet visible in anyone's tree, which is closer to
indefinite and earns an earlier re-decision rather than a later one. The daily
rescan reports it from 14 days out, so the notice lands around 2026-09-20.

Worth saying plainly: a release from `main` will make #22 and #24 disappear and
this entry will still be there. That is the expiry doing its job rather than a
failure — but if the zipkin release lands and nobody re-reads this, it will look
like an entry that stopped mattering. It has not.

Verified before committing: 12 findings on the two-binary tree drop to 6, each
of the six exceptions suppressing in its own binary and none silent.

## 2026-08-07 — 13.1.2, and the index that had it all along

### The bump that could not be resolved, and why that was our defect

`refresh-grafana.sh` recovered the per-build id from GitHub release assets, and
v13.1.2 published with **zero**. So did v13.0.5, v13.1.3, and v13.0.3 / v12.4.5 /
v12.3.8 back in June. Adding `apt.grafana.com` as a second index fixed six of
those — it carries a build id for v13.0.3, and
`…/grafana/release/13.0.3/grafana_13.0.3_28022233908_linux_amd64.tar.gz` is
served, so the old resolver could never have bumped to a release that was
complete the whole time.

It did **not** fix 13.1.2, and the conclusion drawn from that — "upstream has
not published it, the release is not consumable" — was wrong. The artifact was
there:

```
grafana_13.1.2_30900078095_linux_amd64.tar.gz  → 200  2215a38a59b5…
grafana_13.1.2_30900078095_linux_arm64.tar.gz → 200  660cc31dbd15…
```

Grafana's own download page (`grafana.com/grafana/download/13.1.2`) carries that
build id. Three indexes were consulted — apt, rpm, GitHub releases — and none of
them was the one that had it. **An artifact absent from every index we happen to
read is not an artifact that does not exist**, and the distinction decides what
you do next: the first reading says "wait for upstream", the second says "widen
the search". Three days were lost to the first.

How long the download page has carried the id is not established here; it was
found because it was checked, which is the only claim this entry makes about it.

The pins were verified independently by `verify-arch-pins.sh` against upstream
before anything was committed, and both sidecars match what the alias serves —
so PR #36 had the right bytes all along, pinned to the path that gets rewritten.

### Re-scoped, not restated — the three version-scoped statements

13.1.2 does not publish `13.1.1-alpine3.23`, so `lint-vex-product.sh` failed the
three statements pinned to it (Req 6.20). Checked before moving them rather than
assumed: **both dependency pins the arguments rest on are byte-identical in
13.1.2** — `github.com/grafana/tempo v1.5.1-0.20260427112133-525d1bab07e0` and
`github.com/prometheus/prometheus v0.312.0`. The commit-ancestry evidence for
#23 and #27, and the replace-directive evidence for #25, carry over untouched.

| Statement | Scope | Change |
|---|---|---|
| CVE-2026-21728 (#23) | `13.1.2-alpine3.23` | product + the two sentences naming 13.1.1 |
| CVE-2026-28377 (#27) | `13.1.2-alpine3.23` | product + the two sentences naming 13.1.1 |
| CVE-2026-42151 (#25) `fixed` | `13.1.2-alpine3.23` | product + `status_notes` |
| CVE-2026-42151 (#25) `not_affected` | versionless | **untouched** |

The versionless one stays versionless: it is the structural claim, and Req 6.31
is about the kind of argument rather than the release. Timestamps are unchanged
throughout — they record when the argument was made, and Trivy orders
supersession by them.

Recorded because editing a retained statement is a thing that should be visible
(same reason as the 2026-08-04 entry above).

### What 13.1.2 is expected to settle

It bumps every module under the three findings still uncovered on `bin/grafana`,
onto exactly the first-patched version in each advisory:

| Module | 13.1.1 | 13.1.2 | First patched | Finding |
|---|---|---|---|---|
| `getkin/kin-openapi` | 0.140.0 | 0.144.0 | 0.144.0 | **#30 CRITICAL** |
| `google.golang.org/grpc` | 1.81.1 | 1.82.1 | 1.82.1 | #28 |
| `golang.org/x/text` | 0.37.0 | 0.40.0 | unconfirmed | #39 |

That is a prediction, not a measurement — the scan gate on this PR is what
settles it, and #30 is the one worth watching, since govulncheck cannot see the
advisory at all and Trivy is the only instrument that reports it. The bundled
plugin binaries are a separate question: their x/net, x/text and grpc findings
belong to two other upstreams, and whether a 13.1.2 tarball bundles newer plugin
builds is unmeasured.

### Measured on the real 13.1.2 tarball — 11 uncovered drop to 6

The prediction above is now a measurement. Trivy 0.72.0 over the extracted
release tarball, all three Go binaries:

| Binary | 13.1.1 | 13.1.2 |
|---|---|---|
| `bin/grafana` | kin-openapi **CRITICAL**, tempo ×2, x/text, grpc | tempo ×2 |
| `plugins-bundled/elasticsearch/…` | stdlib ×3, x/text, grpc | stdlib ×3 |
| `plugins-bundled/zipkin/…` | x/net ×4, stdlib ×3, x/text, grpc | x/net ×4, stdlib ×3, x/text, grpc |

**14 HIGH, 0 CRITICAL.** #30 is gone — kin-openapi appears nowhere, and the
catalogue's only CRITICAL closed by *fix* rather than by exception. #28 and #39
cleared from `bin/grafana` as predicted, and unpredicted, from the elasticsearch
plugin too: 13.1.2 rebuilt that binary with current dependencies. It did not
rebuild zipkin's, which is now the only stale binary in the image.

The six existing exceptions still matched after the version change — checked
rather than assumed, since a bump is exactly when a `paths:` glob or a purl
could quietly stop matching and Req 6.26 would report a dead entry.

### TRANSFER — the zipkin plugin's own dependencies, six findings (#28, #39)

Everything still uncovered is in one binary and belongs to one upstream, and it
is no longer about the toolchain: these are the plugin's own module versions.
Upstream's `main` already fixes all six, and has gone unreleased since
2026-05-18:

| Module | in the shipped binary | zipkin `main` | Clears |
|---|---|---|---|
| `golang.org/x/net` | v0.49.0 | **v0.56.0** | -25681, -27136, -33814, -39821 |
| `golang.org/x/text` | v0.33.0 | **v0.39.0** | CVE-2026-56852 (#39) |
| `google.golang.org/grpc` | v1.79.3 | **v1.82.1** | GHSA-hrxh-6v49-42gf (#28) |

So it is the same ask as the three stdlib entries already waiting: issue #94,
a release cut from `main`. One release clears these six *and* two of those
three. **Outcome: TRANSFER, six entries, expiring 2026-11-02** — aligned with
the existing zipkin entries rather than dated from today, so one upstream has
one re-decision date instead of two.

**Reachability is not claimed for any of the six, and that is deliberate.**
govulncheck could not be installed — `golang.org` and `proxy.golang.org` are
both unreachable from the devcontainer — so unlike the stdlib entries above,
no symbol-level measurement backs these. A transfer is the honest treatment for
an unmeasured finding: it asserts the finding is real and that someone else owns
the fix, which is the conservative reading. `not_affected` is what would require
the measurement, and it is not being claimed. The PR's own govulncheck step
(Req 6.13) produces this data in CI, where it can be read.

Worth saying plainly about the four x/net findings: **no issue tracks them.**
They were first seen in the 2026-07-30 scan and noted then as untracked; they
have been untriaged rather than merely untreated ever since. These entries are
the first decision anyone has recorded about them.

Verified before committing: 12 of 12 exceptions suppress, none silent, and the
only findings left standing are the two tempo ones the VEX statements cover.

## 2026-08-13 — the fifth x/net finding, and a bump that cannot fix it (#56)

### TRANSFER — CVE-2026-46600, the fifth finding in the zipkin plugin (#56)

`golang.org/x/net/dns/dnsmessage`: denial of service parsing an invalid DNS
record. HIGH, EPSS 0.0034 (26.7 pct), not in CISA KEV. Filed by the daily rescan
as #56, which is the first this lane has heard of it from Trivy — though it is
not new to us. The 2026-08-02 govulncheck run listed it among the eight findings
Trivy missed. Three months later Trivy has it too, which is the same
three-scanners-three-answers point recorded above, arriving in the other
direction.

**Measured, not inferred from the CVE list.** Scanned the published image
(`grafana:13-alpine3.23`, `sha256:6e391848…`) with the pinned trivy 0.73.0:

```
CVE-2026-46600  golang.org/x/net v0.49.0 -> fixed 0.56.0  HIGH
  usr/share/grafana/data/plugins-bundled/zipkin/gpx_grafana-zipkin-datasource_linux_amd64
```

One binary, and it is the binary four x/net findings already wait in. Same
module, same shipped version, same fix version. So this is the fifth of a set,
not a new problem: `main` carries x/net v0.56.0 and clears all five together.

**The interesting part is what it is not.** A fix exists upstream, which by
Req 6.5 would ordinarily point at a version bump rather than a transfer — and
there is an open bump PR (#36, grafana 13.1.3) sitting right there. It cannot
help. The plugin is bundled into the grafana tarball we repackage, so the only
path to a fixed binary is a plugin release, and there has not been one:

| | |
|---|---|
| newest zipkin release | **v12.4.5, 2026-05-18** — still, checked today |
| fix location | `main` only (x/net v0.56.0) |
| `main` moving? | yes — commits through 2026-08-10 |
| upstream ask | issue #94, open, last touched 2026-08-04 |

No grafana version can bundle what upstream has never released. 13.1.3 will not
clear this finding and neither will 13.1.4; the release is the gate, not the
grafana version. Recording that explicitly because "there is a fixed version"
reads like remediation is available, and here it is available to upstream only.

**Outcome: TRANSFER, one entry, expiring 2026-11-02** — the date its four
siblings already carry, not 90 days from today. One upstream, one re-decision.

Reachability is not claimed, for the same reason as the other five: no
symbol-level measurement backs it, and a transfer asserts the finding is real
and someone else owns the fix, which is the conservative reading of an
unmeasured finding. `not_affected` is what would need the measurement (Req 6.14,
6.15) and it is not being claimed — though it is worth noting a DNS message
parser is not obviously on a datasource plugin's path, which is exactly the kind
of guess Req 6.15 exists to stop anyone banking.

Verified before committing, against the real published image with the gate's own
inputs — compiled VEX plus the ignorefile: **1 uncovered before, 0 after**, and
the new entry suppresses the finding it names rather than matching nothing.

## 2026-08-13 — 13.1.3, a bump that changes no finding (#36)

### Re-scoped, not restated — the three version-scoped statements, again

13.1.3 does not publish `13.1.2-alpine3.23`, so `lint-vex-product.sh` failed the
three statements pinned to it (Req 6.20) — the same failure the 13.1.2 bump
produced on 2026-08-07, arriving the same way. Checked before moving them rather
than assumed: **both dependency pins the arguments rest on are byte-identical in
13.1.3**, read out of the shipped binary rather than out of a go.mod:

```
github.com/grafana/tempo        v1.5.1-0.20260427112133-525d1bab07e0
github.com/prometheus/prometheus v0.312.0
```

So the commit-ancestry evidence for #23 and #27 and the replace-directive
evidence for #25 carry over untouched, exactly as at 13.1.2.

| Statement | Scope | Change |
|---|---|---|
| CVE-2026-21728 (#23) | `13.1.3-alpine3.23` | product + the two sentences naming a version |
| CVE-2026-28377 (#27) | `13.1.3-alpine3.23` | product + the two sentences naming a version |
| CVE-2026-42151 (#25) `fixed` | `13.1.3-alpine3.23` | product + `status_notes` |
| CVE-2026-42151 (#25) `not_affected` | versionless | **untouched** |

The versionless one stays versionless for the reason recorded on 2026-08-04: it
is the structural claim, and Req 6.31 scopes by the kind of argument rather than
by the release. Timestamps unchanged throughout.

Worth stating because it was briefly proposed the other way: the `fixed`
statement is **not** a candidate for deletion just because Trivy no longer
reports the finding. It is the supersession Req 6.22 wants kept on the record,
and Req 6.21 forbids a `fixed` statement without a version — so re-scoping is
the only move that keeps both rules satisfied. "Suppresses nothing today" is not
the same property as "says nothing".

### Measured on the real 13.1.3 tarball — the finding set does not move

Downloaded the pinned artifact (sha256 `e0fd22aa…`, matching the definition),
extracted it, and ran trivy 0.73.0 over all three Go binaries:

| Binary | 13.1.2 | 13.1.3 |
|---|---|---|
| `bin/grafana` | tempo ×2 | tempo ×2 |
| `plugins-bundled/elasticsearch/…` | stdlib ×3 | stdlib ×3 |
| `plugins-bundled/zipkin/…` | x/net ×4, stdlib ×3, x/text, grpc | x/net ×**5**, stdlib ×3, x/text, grpc |

**15 HIGH, 0 CRITICAL**, against 14 at 13.1.2. The one added is CVE-2026-46600,
and it is not the bump's doing: x/net v0.49.0 was in that binary all along and
the advisory reached Trivy's database this week (#56, transferred today). Set
aside that arrival, and **13.1.3 changes nothing about this image's
vulnerability surface** — same modules, same versions, same findings, in the
same three binaries.

That is worth recording rather than glossing. A patch bump that clears nothing
is still worth landing — it is the release we would have to be on before any
future fix could reach us, and staying behind accrues nothing — but it should
not be described as a security improvement, and the zipkin binary remains the
one stale thing in the image, exactly as it was at 13.1.2.

Every accepted-risk entry still matched after the version change — checked
rather than assumed, since a bump is exactly when a `paths:` glob or a purl can
quietly stop matching and Req 6.26 would report a dead entry. Reproduced the
image layout (`usr/share/grafana/…`) over the extracted tarball so the globs
resolve: **15 findings without the ignorefile, 2 with it** — 13 suppressed by 13
entries, none silent. The two left standing are the tempo pair the re-scoped
statements cover; VEX cannot apply in a rootfs scan, which has no OCI root
component purl to match.

Verified the scope actually moved rather than the prose alone: compiled against
this build's tags gives 4 statements and 0 drops, and compiled against the old
13.1.2 tags drops all three re-scoped products and keeps only the versionless
claim.

---

## 2026-09-02 — FIX by fetch-phase module bump — CVE-2026-56854, `golang.org/x/crypto` v0.53.0 (#112, cert-manager half)

*Images: cert-manager-controller, cert-manager-webhook, cert-manager-cainjector.
Grafana's half of #112 is a repackaged upstream binary, cannot be patched, and
stays under_investigation in the nightly attestations; the issue remains open
for it.*

GO-2026-6303: `x/crypto/ssh` below 0.55.0 does not enforce the source-address
critical option for non-public-key auth callbacks. Upstream v1.21.1 pins
v0.53.0; the newest release, checked against the releases API, carries no fix.
The version-bump path is closed, exactly the GHSA-hrxh-6v49-42gf shape from
2026-07-26.

**The mechanism that entry asked for is now established.** The July attempt
patched via a `runs:` step and the sandbox refused it (no egress, by design).
The frontend's fetch phase is where dependency surgery belongs, and the action
is `go/bump@v2` — primary-verified this time, not secondary: Docker's own
catalog uses it 936 times, including etcd bumping `golang.org/x/crypto` and
`google.golang.org/grpc@v1.82.1` (the very version #28 wanted) with `deps:`,
`download: true`, `tidy: true`, per cmd-submodule `work-dir`. Bumped in each
`cmd/*` submodule because the binary resolves through *its* `go.mod`
(`replace … => ../../`), and minimal version selection makes the pin a floor:
a later upstream requirement wins, an accidental downgrade cannot happen.

**Decision: fix.** Chosen over a `not_affected` statement deliberately, to
exercise the remediation lane end to end (owner call, 2026-09-02). The
inapplicability evidence exists and is recorded as defence in depth, not as
the justification: the advisory's entry points (`ssh.NewServerConn`,
`connection.serverAuthenticate`) are absent from all three binaries' function
tables, measured 2026-09-01 with a positive control that finds those symbols
in a deliberately vulnerable build. None of the three serves SSH.

**Machine-readable form:** a `fixed` statement
(`triage/vex/CVE-2026-56854.openvex.json`) scoped to `1.21.1-alpine3.23`,
subcomponent `pkg:golang/golang.org/x/crypto`, per the CVE-2026-21728
precedent. Digests published before the bump genuinely carry v0.53.0 and are
outside its scope. Timing: the statement and the bump merge together, and the
merge itself publishes fixed digests through the release arm within minutes,
so the window in which the tag-scoped claim could meet an unfixed digest in a
rescan compile is practically zero; a failed merge build would announce
itself red.

**Also in this change:** the Go toolchain image moves 1.26.5 → 1.27.0 (the
#113 busybox fix, applied to these three definitions at last), which is what
lets them build at all; and the bump pin is tracked by a new Renovate manager
(marker comment above the `deps:` line, `go` datasource), because a security
pin must not go invisible (Req 7.6).

**Second finding, same pass — CVE-2026-84304, `google.golang.org/grpc`
v1.82.1 (controller and webhook; cainjector carries no grpc).** Surfaced by
this very PR's gate once the x/crypto CRITICAL and the eight go1.26.5 stdlib
HIGHs (cleared by the 1.27.0 toolchain) stopped drowning it, and named by the
gate's new failure annotation on its first day in service. Fixed in 1.83.1;
upstream pins 1.82.1 and no release carries it, so the same `go/bump` step
gains `google.golang.org/grpc@v1.83.1` in the two definitions that have the
module, with its own Renovate marker and a `fixed` statement
(`triage/vex/CVE-2026-84304.openvex.json`) scoped to the two products. This
is the direct descendant of the 2026-07-26 grpc entry: upstream's own move
to 1.82.1 retired that finding, a new advisory arrived on the version they
moved to, and the between-releases lane now exists to answer it same-day.

**Exit condition:** drop the `go/bump` step from all three definitions when
an upstream release pins `golang.org/x/crypto` at v0.55.0 or newer AND
`google.golang.org/grpc` at v1.83.1 or newer; the Renovate release PR for
those versions is the reminder, this entry is the record.

---

## 2026-09-02 — first full-enumeration rescan: the legacy tags scanned in place (task 9.5, Req 2.22)

Run 33624552846 (11:25 UTC, the first `rescan.yml` after task 9.3 merged) was
the first time the catalogue looked at everything it has ever published:
`enumerate-catalogue.sh` walked all 6 repositories into 50 platform-manifest
rows across 37 tags (16 supported, 21 superseded), the visibility invariant
(task 9.4) passed on every repository and tag, and every manifest was scanned
by its own digest — no `--platform`, nothing to downgrade. One issue came out
of it, #121, CVE-2026-84304 in grpc on the supported cert-manager-controller,
cert-manager-webhook and grafana digests; the cert-manager half was fixed the
same afternoon (the entry above, PR #122), grafana's stays open there.

**The ten legacy tags** (cert-manager-controller, -webhook and -cainjector
`1.20`, `1.20.3`, `1.21.0`; grafana `13.0`, `13.0.4`; valkey `9.0`, `9.0.5`)
kept their digests, as decided on 2026-08-22: cosign signed their indexes
only, so a re-point would have served an unsigned manifest. Their arm64
halves, never read by a scanner since they were published, were scanned for
the first time. Findings per tag and platform, reproduced locally the same
day with the same scanner, database and compiled VEX as the run (the run's
own reports are in its `rescan-33624552846` artifact):

| Tags (one digest) | Platform | Uncovered | Notable |
|---|---|---|---|
| cert-manager-controller `1.20`, `1.20.3` | amd64 / arm64 | 1 CRIT / 12 HIGH each | x/crypto CRITICAL; nine go1.26.x stdlib HIGHs; grpc GHSA-hrxh-6v49-42gf (the #28 grpc, upstream's later move retired it for 1.21.x) |
| cert-manager-controller `1.21.0` | amd64 / arm64 | 1 CRIT / 10 HIGH each | same set minus the two stdlib findings 1.21.0's toolchain already carried fixes for |
| cert-manager-webhook `1.20`, `1.20.3` / `1.21.0` | amd64 / arm64 | as controller | identical package graph for these findings |
| cert-manager-cainjector `1.20`, `1.20.3` / `1.21.0` | amd64 / arm64 | 1 CRIT / 11 HIGH, 1 CRIT / 9 HIGH | no grpc in its module, so no GHSA-hrxh |
| grafana `13.0`, `13.0.4` | amd64 / arm64 | 3 CRIT / 26 HIGH each | CVE-2026-21728 and -28377 reported: their `fixed` statements are scoped to 13.1.3 and correctly did NOT apply here (Req 6.30 doing its job; 13.0.4 is genuinely affected, as the statement's own impact text says); CVE-2026-76905, -77354 and GHSA-r277-6w6q-xmqw appear only on 13.0.x, fixed upstream by 13.1 |
| grafana `13.1.2` | amd64 | 2 CRIT / 26 HIGH | the current-line backlog, minus the 13.0-only trio |
| valkey `9.0`, `9.0.5` / `9.1.1`, `9.1.1-compat` | amd64 / arm64 | 0 CRIT / 2 HIGH each | CVE-2026-14456 only (#107) |

**What the arm64 halves showed:** on every legacy index the arm64 manifest
carries exactly the findings its amd64 sibling carries — same package set,
built from the same pins in the same run — so the fear the 2026-08-04
withdrawal encoded ("published, signed, never read") resolves to "nothing
architecture-specific was hiding". That could only be known by scanning;
now it is measured, and it will be re-measured every day.

**On issues.** Task 9.5 was written as "whatever those carry becomes
under_investigation and issues". The Terms adopted since (primitives pass,
2026-08-26) place a superseded digest outside the scope of issues and
clocks: its content never changes and its findings accrue by design, so an
issue per finding would be a daily restatement of "the past is old". The
enumeration honours the Terms: superseded manifests are scanned daily and
their reports kept in the run artifact under `trivy-superseded/`, issues
derive from supported digests only, and this entry is the one place the
first sweep's findings are written down. That is the standing
interpretation of 9.5, not a gap.

## 2026-09-03: 13.1.5, the grafana backlog session (grafana half of #112, #121)

*Image: grafana. Decisions taken one at a time in a per-group session
(owner calls, 2026-09-02 and 2026-09-03). Every number below was measured on
the published 13.1.5 release asset (`grafana_13.1.5_33098073184_linux_amd64.deb`,
sha256 `15c8ace2…a62e`), extracted and read with `go version -m` and scanned
with the same Trivy and the same ignorefile the gate uses; the CI gate on the
bump PR (#132) reported the identical thirteen findings.*

### FIX by upstream bump: x/crypto and the server's stdlib wave

13.1.5 (released 2026-09-02 08:12 UTC) rebuilt `bin/grafana` with **go1.26.6**
and **x/crypto v0.55.0**. That retires, on the server binary, the eight go1.26.4
stdlib findings and CVE-2026-56854 (GO-2026-6303). The `not_affected` statement
drafted for the grafana half of #112 on 2026-09-02 was therefore never
published: the finding it excused stopped existing before the statement
landed, and a statement that suppresses nothing says nothing (2026-07-26,
same reasoning). The bump is Renovate's own commit, carried on this branch
because the bump cannot merge alone (below).

### Re-scoped, not restated: the three version-scoped statements, a third time

Both pins the arguments rest on are byte-identical in 13.1.5, read out of the
shipped binary:

```
github.com/grafana/tempo         v1.5.1-0.20260427112133-525d1bab07e0
github.com/prometheus/prometheus v0.312.0
```

So CVE-2026-21728 (#23), CVE-2026-28377 (#27) and the `fixed` half of
CVE-2026-42151 (#25) move to `13.1.5-alpine3.23`: product plus the sentences
naming a version, timestamps unchanged, exactly as on 2026-08-13. The
versionless `not_affected` half of #25 stays untouched.

### TRANSFER: the zipkin plugin again, nine findings, one stale bundle

13.1.5 bundles zipkin **v12.4.6** (built 2026-08-13, go1.26.4, grpc v1.82.1).
On this build Trivy reports eight stdlib findings (CVE-2026-33818, -39821,
-46600, -56853, -56858, -56859, -56860, -56862; fixed go1.26.6) and
CVE-2026-84304 (grpc, fixed 1.83.1), plus CVE-2026-39822, which the existing
entry still covers. Two of the eight (39821, 46600) had entries already, keyed
to `x/net` because that is where 13.1.3's zipkin build carried them; the new
build fixed x/net and reintroduced the same CVEs through the toolchain, so the
purl moved and the entries went inert. Fail-closed, as designed: an entry that
matches nothing suppresses nothing.

The plugin's own **v12.4.7** (2026-08-27) is built with go1.26.7 and links
grpc v1.83.1, which clears all nine. The fix exists and is released; Grafana
bundled the older one. **Decision: transfer**, extending the existing #94
transfer to the nine, all on the 2026-11-02 re-decision date (the 39822 entry
joins it: its earlier 60-day window was for an exit nobody had landed, and
the exit has landed). Reachability is not claimed: the binary is stripped,
govulncheck stops at module level, Req 6.16 calls that unmeasured.

### TRANSFER: the server binary's own pins, thrift and grpc (grafana/grafana#131921)

`bin/grafana` 13.1.5 links `github.com/apache/thrift`
v0.23.1-0.20260429145742-d2acd3c49e58 (CVE-2026-43871, GHSA-8wv5-x4w7-5gww,
infinite loop in the Go binding, fixed 0.24.0) and `google.golang.org/grpc`
v1.82.1 (CVE-2026-84304, GHSA-vp52-pcj8-j9qc, heap exhaustion via HTTP/2 DATA
frame fragmentation, fixed 1.83.1).

- **Fix lane: closed.** A repackaged tarball has no fetch-phase bump (the lane
  that answered the same grpc advisory on cert-manager the day before), and
  Renovate is on the newest release. grafana `main` already pins thrift 0.24.0
  and grpc 1.83.0, so upstream is one bump and one backport away.
- **Applicability lane: closed by the rules.** Neither advisory has a
  golang/vulndb report (checked through GO-2026-6355), so govulncheck cannot
  see them; Req 6.15 requires a symbol- or package-level citation for
  `vulnerable_code_not_in_execute_path`, and Req 6.16 treats the absence as
  unmeasured. The thrift pin also predates every change to `lib/go` between it
  and the 0.24.0 tag, so the commit-ancestry route that works for tempo is
  closed too. Context recorded, not claimed: the default `[grpc_server]`
  binds `127.0.0.1:10000`, and the thrift readers are linked through the
  legacy `jaeger-client-go` tracing client, off unless configured.
- **Avoid: not available.** Both sit inside the server binary.

**Decision: transfer**, one upstream issue for both,
[grafana/grafana#131921](https://github.com/grafana/grafana/issues/131921),
drafted in `upstream/2026-09-03-grafana-server-thrift-and-grpc-below-fixed.md`
and filed unmodified. Expiry 2026-11-02, inside the 90-day HIGH ceiling and on
the zipkin re-decision date, so one review covers the whole image.

### Retired: ten entries that now match nothing

The elasticsearch plugin in 13.1.5 is built with go1.26.7, so its three
transfer entries (CVE-2026-27145, -42504, -39822) cover nothing. The zipkin
build fixed x/net (v0.56.0) and x/text and moved grpc to 1.82.1, so its
entries for CVE-2026-25681, -27136, -33814, -56852, GHSA-hrxh-6v49-42gf and
the x/net-keyed 39821 and 46600 cover nothing either, and 27145 and 42504 are
gone with go1.26.4. Deleted rather than kept: an ignorefile entry that matches
nothing is silent in Trivy, and a silent entry is a future false sense of
coverage. The elasticsearch issue (#410) can close on this evidence.

Measured after the rewrite: the extracted 13.1.5 filesystem, scanned with the
new ignorefile, leaves exactly the two tempo findings, which the re-scoped
`fixed` statements cover on the published image.

### The mechanism: why 13.1.5 arrived a day late

Renovate had computed the 13.1.5 update since the morning of 2026-09-02 and
opened nothing. Two configuration defects, both found by running the pinned
Renovate at debug level against the repository, fixed in #131: the repository
sat at exactly Renovate's default cap of ten open branches, so the patch
branch was skipped silently every run ("Reached branch limit"); and the
grafana post-upgrade task was keyed on the `github-releases` datasource, which
the pinned tools share, so a kyverno rebase ran `refresh-grafana.sh` against
`scripts/`, failed, and the failed-artifact status write (refused, the token
lacks `statuses: write`) aborted the run before the dashboard rewrite. #130
(separate patch and minor PRs for grafana) had been necessary but was not
sufficient. Owner-side follow-up: `statuses: write` on the Renovate token.
