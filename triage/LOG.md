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

## 2026-09-04: the first no-change day, and what it measured (task 10.3, ADR 0004)

Two rescans ran on the same commit. The manual one (run 33854524508, 08:39
UTC) failed at the re-attest step on one write of about ninety: `cosign
attest --type vuln --replace` on valkey's compat 9.1.2 platform manifest,
where Rekor answered "already exists" to an upload cosign's client had
retried, then 404 for that entry by UUID from a lagging replica. The registry
showed the write never landed, nothing else was writing, and the scheduled
run three hours later (33867898868, 11:25 UTC) wrote all 35 manifests. A
Sigstore race, met with a bounded retry (#145): three attempts, each failure
named, three failures still a failure.

The scheduled run is the measurement ADR 0004 waited for:

| Measured | Result |
|---|---|
| platform manifests scanned by digest | 35 of 35, no failures, no new issue |
| digests re-attested / unchanged | 3 / 16 |
| previous documents per digest, OpenVEX count before | 1 and 1 on all 19 |
| Rekor entry of the replaced layer retrievable after the replace | yes, 3 of 3 |
| OpenVEX attestations per target, counted from the registry | exactly 1 on all 54 |

The three re-attested digests are all grafana. 13.1.5 had been rebuilt that
morning, and the release job compiles without the open-issue map, so its
first rescan adds the issue links: a one-time change, by design. 13.1.2 and
13.1.3 had no input change at all. Their documents carry, for one finding
and one package, an `affected` statement (excepted in the zipkin binary) and
an `under_investigation` statement (uncovered in the server binary); the
compiler paired last time's statements by finding and package only, so the
second always looked changed and was re-stamped on every compile. Measured
by recompiling 13.1.2 against its own attested document: ten statements
re-stamped before the fix, none after (#144). A replace that changes nothing
is a Rekor entry for nothing.

The daily rebuild of the same morning (run 33856617294) published new digests
for six of seven components and failed cert-manager-cainjector in the base
package install, a definition identical to its two siblings that built in
the same minute; tonight's run retries. The Renovate tool-bump PRs failing
`validate` are by design: the checksum half of a pin is manual.

## 2026-09-06: the valkey compat variant, recorded as a transfer (task 11.4, Req 4.5)

The decision that `chart/valkey/` deploys the `-compat` image (busybox beside
the server, a shell for the chart's init script) was made on 2026-08-25 and
lived in the chart README's prose. It is now structured metadata in
`chart/valkey/chart.yaml` (`compat:`), validated by `chart/chart.schema.yaml`
and clocked by `scripts/lint-compat.sh`: decided 2026-08-25, review by
2026-11-24, after which validate fails until a dated re-decision lands
(Req 4.8), and the rescan reports the lapse daily (Req 4.9).

It is a transfer. The ask is drafted in
`triage/upstream/2026-08-25-valkey-helm-init-container-image.md`: an
`initContainer.image` value defaulting to the main image, the shape the chart's
exporter already has. Measured again on 2026-09-06 with
`triage/upstream/checks/valkey-helm-init-container.sh`: on chart 0.11.0 and
0.12.0 alike, in the standalone Deployment and the replica StatefulSet, the
init container renders whenever the workload does (no block of its own, only
the mode switch that renders the workload), from the main image helper,
running a `/bin/sh` script that calls tee, cat, rm, mkdir and date; no value
replaces or disables it. Owner item: file it against
valkey-io/valkey-helm and record the number in `compat.issue` and here. When
upstream ships the value, the runtime image can carry this chart and the
variant retires.

Same day, mechanism: Renovate now tracks the three upstream chart versions
(a helm-datasource manager over `chart/<name>/chart.yaml`, never automerged,
Req 3.11) and automerges digest-only bumps of the catalogue's own image pins
under `chart/` behind the required checks (Req 3.12). The valkey index
already lists 0.12.0, so the manager's first run offers a real chart bump
through the e2e upgrade path.

## 2026-09-07: the valkey-helm ask is filed (#247)

The transfer recorded on 2026-09-06 now has its tracker: the owner filed
[valkey-io/valkey-helm#247](https://github.com/valkey-io/valkey-helm/issues/247), open, body the draft from `## Summary`
down. `chart/valkey/chart.yaml` (`compat.issue`) points at it, and the draft
and the `triage/upstream/README.md` table say filed.

Before filing, the draft was cut to the problem and the ask (#157) and put
through two reviews, one for prior art and one briefed to argue against
filing. The ask held (right repo, active, no existing knob, no design reason
for the init container to share the main image: it appeared on the chart's
second day as a refactor of an inline `sh -c` wrapper, and the one stated
reason for a separate container, secret isolation in upstream PR #14, is
kept by a different image). Two claims were corrected: the exporter's value
is `metrics.exporter.image`, and the init script also calls chmod, touch,
sha256sum and cut on the ACL path, so the 2026-09-06 entry's list of five
utilities was incomplete; `compat.reason` now says "standard utilities".
`initResources`, an init-container-only value present since 0.11.0, went
into the ask as precedent.

Next check: an answer on #247, or the `review_by` date 2026-11-24, whichever
comes first.

## 2026-09-08: a week of nightly publishes that changed nothing (task 9.2, Req 2.15)

Found while explaining a digest-only chart-pin PR (#163): the grafana digest
published by the 09:08 rebuild and the one it replaced project to the same
654 package entries under the comparator's own projection, and the last four
nightly runs had published all seven definitions each. Cause: build.yml
installed cosign in the release part, after the publish-on-change comparator,
and the runner image ships no cosign, so `cosign download attestation` failed
with "command not found", which the comparator read as an unreadable
attestation, which by design publishes. Every night from 2026-09-02 (the
first scheduled run after task 9.2) published every definition: 28 needless
digests through 2026-09-08, each scanned, signed, attested and tagged in
order, each then rescanned daily as a superseded digest, each opening a
digest-only chart-pin PR. The 09-04 entry above recorded "published new
digests for six of seven" without asking why.

Fix: cosign installs before the comparator, and the comparator refuses (exit
2, the run fails naming the tool) when docker, cosign or jq is missing,
instead of returning a verdict; the suite gained the case. The 28 digests
stay, superseded, under the no-deletion rule; nothing about them is wrong
except that they were unnecessary. First proof: the next nightly should
discard all seven and log the reproducibility measurement instead.

## 2026-09-10: grafana 13.2.1 declined; the definition rides the stable maintenance track (PR #89)

Renovate's minor PR (#89) had been red for a week on two gates: three
hand-written statements pinned to the 13.1.5 tag, and the scan gate naming
162 uncovered pairs on the 13.2.1 image, against 14 findings on 13.1.5. The
gate's message is cut at 4,000 characters, so the two releases were fetched
as GitHub release packages, their `usr/share/grafana` trees (the same tree
the image ships) scanned with the gate's scanner and aperture, and every Go
binary read with `go version -m`.

What 13.2 changed: eleven core datasources (Prometheus, Loki, Tempo, Jaeger,
InfluxDB, MySQL, MSSQL, PostgreSQL, OpenTSDB, Pyroscope, Cloud Monitoring)
left the server for bundled plugin binaries. 13.1.5 ships 3 Go binaries
(server, elasticsearch, zipkin); 13.2.1 ships 14. Each plugin is built on
its own, with toolchains from go1.25.7 (OpenTSDB, with x/net 0.51.0) to
go1.26.7 and library pins behind the server's: 32 CVEs over 174 binary and
finding pairs, one CRITICAL (CVE-2026-56854, golang.org/x/crypto below
0.55.0, in the Loki, MSSQL and Cloud Monitoring plugins). The server binary
itself improved (thrift and the two grpc findings, all known; the tempo pair
left it). The tempo pair moved into the tempo plugin, which pins a tempo
commit from 2025-05-29, before the 2026-02-20 fix commit the 13.1.5 `fixed`
statement rests on (that server pins a commit from 2026-04-27): on 13.2.1
those two are real, not a scanner artefact. Zipkin is the same stale 12.4.6
build in both, so its eleven transfers carry unchanged.

Grafana keeps two tracks: the newest minor with features, the previous minor
with fixes, and both ship patches on the same days (13.1.3, 13.1.4 and
13.1.5 beside 13.2.0 and 13.2.1). The decision: this definition rides the
stable maintenance track. 13.2.1 is declined, not deferred: a minor is not an
update to apply but a decision to take when its stream becomes the stable
one, that is, when 13.3 ships. Avoidance was not available (dropping the
bundled binaries removes the core datasources), and taking 13.2.1 would have
meant about thirty transfers with a 30-day clock on the CRITICAL for a
release whose server is no safer than the one published.

Mechanism, so the decision does not depend on remembering it: Renovate keeps
patches on the adopted line flowing as their own PRs, opens one PR per minor
stream (so 13.2.x stays offered after 13.3 exists), and holds every grafana
minor behind Dependency Dashboard approval (register row M24). #89 is closed
with this entry as its reason. Open on the stable line: CVE-2026-84445 in
grpc 1.83.1 (issue #186), the next decision.

## 2026-09-17: six supply-chain issues from a rate-limited read (task 11.6, Req 3.13)

Found while checking the state of the repository on 2026-09-16: the daily
rescan (run 35091969642) had failed its authenticity step and filed six
`supply-chain` issues, #212 to #217, one for every git-sourced definition
(cert-manager's three, hardened-app, valkey and valkey-compat), each saying
GitHub's verification statement "could not be read". Cause: the step handed
the workflow token to the shell as `GH_TOKEN`, the name gh reads, while
`github_verification` in `scripts/definition-lib.sh` read `GITHUB_TOKEN`, so
every statement was requested anonymously, on the sixty-an-hour budget of a
hosted runner's shared address. On the previous six days that budget held;
on 2026-09-16 it was gone (the governance step, later in the same job,
recorded "HTTP Error 403: rate limit exceeded" from its own reads, which are
anonymous by design and were reported unreadable rather than filed). The
check read "could not ask" as "the answer was bad". Re-run locally the same
day with a token, all seven signals verify: the pinned content moved nowhere
and no key changed.

Fix: the helper reads `GH_TOKEN` too, and the check gains a third outcome
beside verified and mismatch. An origin it cannot read (the tag listing,
GitHub's statement, grafana's version statement, a checksum sidecar) is
recorded as not measured, named with the origin and the HTTP status or
transport error, and fails the run without filing an issue; a mismatch is
reserved for an origin that answered (Req 3.13). The six issues are closed
with a comment pointing here once the fix is on main: the mismatch they
claim was never measured. First proof: the next scheduled rescan should
report seven verified and none not measured, and file nothing.

Retries, added the same day: a read that fails is tried again three times,
resting 10, 30 and 90 seconds (a Retry-After header sets the rest, capped
at two minutes), so a blip costs seconds, not a red day. A primary rate
limit is the one thing not retried: its budget resets on the hour, so three
tries over two minutes would only have added two minutes per definition to
the 09-16 run; the message names the reset time instead.

## 2026-09-18: the fetch-phase bumps retired with cert-manager 1.21.2 (#208; CVE-2026-56854, CVE-2026-84304)

The 2026-09-02 entry set the exit condition for the `go/bump@v2` step in the
three cert-manager definitions: drop it when an upstream release pins
`golang.org/x/crypto` at v0.55.0 or newer and `google.golang.org/grpc` at
v1.83.1 or newer, the release PR being the reminder. v1.21.2 (released
2026-09-11, Renovate's #208) is that release: its go.mod moves x/crypto
v0.53.0 to v0.56.0 and grpc v1.82.1 to v1.83.2, and the release notes name
both as security bumps (#9265; #9255, #9317). Both halves of the condition
hold, so the step goes from all three definitions in the same PR, and #204's
bump of the pin to v0.57.0 earlier today is moot the moment it lands.

The two `fixed` statements move with the release, as the grafana 13.1.x
statements did: product version `1.21.2-alpine3.23`, the notes and impact
statements now saying fixed upstream rather than fixed by the catalogue's
bump, document version 2, the first-seen timestamps kept. The 1.21.1 digests
keep the OpenVEX attested to them, so the record of how those builds were
fixed travels with the artifacts it describes. The Renovate manager test that
asserted the markers in the live definitions now proves the capture on a
fixture in the definition's shape and holds the live definitions pin-free.

One more thing the retirement takes with it: on #208's first build the
controller job failed inside the `go/bump` action's own package step
(`grep sed yq`), a failure mode that belonged to the step, not to the
definition. The proof is the PR's scan gate: three 1.21.2 builds, the
statements applied to the tag they name, nothing uncovered.

## 2026-09-18: not affected: CVE-2026-84445, no binary in the grafana image builds an xDS server (#186, #225)

Grafana 13.1.6 (Renovate's #225, released 2026-09-15) was the fix-forward
hoped for in #186, and it does half of it: the server binary moves
`google.golang.org/grpc` from v1.82.1 to v1.83.2 and the bundled
elasticsearch datasource's v1.83.1 copy is gone too. One copy remains, the
bundled zipkin datasource at v1.82.1: the same stale v12.4.6 build that
already carries nine transfers to grafana-zipkin-datasource#94, and whose
upstream fixed this very thing on 2026-09-10 (v12.4.8 links grpc v1.83.2)
without a grafana release bundling it yet. So the finding is not closed by
the bump, and the PR's scan gate said so: CVE-2026-84445 uncovered, beside
the two tempo statements it dropped for being scoped to 13.1.5.

**What the vulnerability is.** GHSA-2v4p-qf9q-27wj: a server built with
`xds.NewGRPCServer()` installs an xDS routing interceptor on every RPC; on a
request carrying neither `:authority` nor `Host`, that interceptor indexes
an empty authority list and the process panics. The vulnerable code is the
interceptor, and only an xDS server installs it.

**Decision: not affected, vulnerable code not in the execute path,
version-independent.** No binary in this image builds an xDS server, and
that is a property of what the image runs, not of which grpc it vendors.
Measured on the published 13.1.5 binaries (index digest 9228cff90ec4,
linux/amd64), pulled from ghcr.io and read in place:

| binary | grpc | method | `grpc/internal/transport` (control) | `grpc/xds*` | `NewGRPCServer` | xDS server package |
|---|---|---|---|---|---|---|
| `bin/grafana` | v1.82.1 | `go tool nm`, 497,941 symbols | 459 | 77: `xds/googledirectpath` 36, `xds/bootstrap` 23, `xds/csds` 9, `xds` 9 | 0 | 0 |
| `plugins-bundled/zipkin/gpx_…_linux_amd64` | v1.82.1 | package paths (`strings`; the binary is stripped) | 444 | 0 | 0 | 0 |
| `plugins-bundled/elasticsearch/gpx_…_linux_amd64` | v1.83.1 | package paths (stripped) | 447 | 0 | 0 | 0 |

The server's `grpc/xds` linkage is the client-side google-c2p resolver the
Google Cloud SDKs bring in (`cloud.google.com/go/storage` and `monitoring`
in 13.1.6's go.mod); it references the plain `grpc.NewServer` once and
`NewGRPCServer` never. The plugins serve the host through the plugin SDK's
plain gRPC server and link no `grpc/xds` package. GitHub code search finds
no import of `google.golang.org/grpc/xds` and no `xds.NewGRPCServer` in
grafana/grafana, the zipkin and elasticsearch datasource repositories or
grafana-plugin-sdk-go. The zipkin binary downloaded from its own v12.4.6
release (sha1 as published) is byte-identical to the bundled one, so the
measurement does not depend on this image's packaging. No positive control
for an xDS server was buildable here (the devcontainer cannot reach the Go
proxy); the control is the same method finding the sibling packages in every
binary, and the symbol table of the server naming the one plain server
constructor it does use.

**Machine-readable form:** `triage/vex/CVE-2026-84445.openvex.json`, a
versionless `not_affected` statement with the `version-independent:` note
(the README's structural case), subcomponent `pkg:golang/google.golang.org/grpc`,
so it covers every copy in every build, the superseded 13.1.5 digests
included, each of which was measured. The two tempo `fixed` statements move
to `13.1.6-alpine3.23`: the pin is byte-identical to 13.1.5's
(`v1.5.1-0.20260427112133-525d1bab07e0`), so the commit-ancestry argument of
2026-08-05 carries unchanged. The CVE-2026-42151 `fixed` statement moves too: 13.1.6
requires prometheus/prometheus v0.312.0 with no replace directive, as 13.1.1
through 13.1.5 did, past the 0.311.3 fix; its note now says so. The 2026-09-03 transfer of CVE-2026-84304 on
the server binary becomes moot with 13.1.6 (grpc v1.83.2) and is left to
expire with its siblings; the zipkin transfers stand until a grafana release
bundles v12.4.8 or newer. #186 closes on evidence once the rescan reads the
statement from the attested 13.1.6 digest; #203 unblocks with it.

## 2026-09-20: the repository's own dependencies join the loop: Dependabot alerts as a Renovate input (CVE-2026-35469, CVE-2026-29181)

GitHub had two high alerts open on `test/go.mod`, the e2e harness:
`github.com/moby/spdystream` v0.5.0 (CVE-2026-35469, an unvalidated frame
parser, fixed 0.5.1) and `go.opentelemetry.io/otel` v1.36.0 (CVE-2026-29181,
baggage-header amplification, fixed 1.41.0), both indirect, through
client-go's SPDY transport and the framework's featuregate package. Nothing
read them: Renovate's dashboard had warned "Cannot access vulnerability
alerts" since July, and a token that can read them still leaves indirect Go
modules disabled in the gomod manager. Reconstructed here from the manifests
against GitHub's advisory database because the maintainer's own PAT cannot
read alerts either; the count matched GitHub's.

Exposure: none to anything published. Both live only in the harness, which
never calls exec or port-forward (the SPDY parser never runs) and never
serves HTTP (the baggage propagator never runs), measured over `test/`. A
hygiene gap, not a security one, but a channel nobody reads is how the next
real one hides.

Decision, the owner's on 2026-09-19 and 2026-09-20: the channel becomes an
input to the loop rather than a page someone remembers to open. The Renovate
PAT gained "Dependabot alerts: read" (the 22:14Z run rewrote the dashboard
without the WARN, and raised nothing: the indirect rule), and
`renovate.json5` gains `vulnerabilityAlerts: { enabled: true }`, the setting
Renovate's own `security:only-security-updates` preset rests on: applied
with `force` to the vulnerable dependency, so a reported alert opens a fix
PR to the lowest fixed version, `[SECURITY]`, outside the limits, whatever
the dependency's scope. Declining a fix is a dismissal in GitHub with its
reason, the not-affected record for repository dependencies (register M25);
a dismissed alert opens nothing. For these two the fixes are taken, a
CI-proven bump costing less than a defended analysis: spdystream's is a
parser hardening; otel's may need its sibling modules to move with it, and
the Go job will say. A `k8s.io` alert would likewise arrive as a PR, red if
the family must move together, visible where it used to be silent.

## 2026-10-01: the valkey chart's standalone breakage is filed (#264), found on the way to #247's fix

The owner filed
[valkey-io/valkey-helm#264](https://github.com/valkey-io/valkey-helm/issues/264), open, body the draft
`upstream/2026-09-30-valkey-helm-standalone-config-path.md` from `## Summary`
down. Their Sentinel change (upstream PR 234, merged 2026-09-24, unreleased)
moved `init.sh`'s configuration to `/valkey-conf` and gave only the
StatefulSet the volume; the standalone Deployment's init container dies on
`mkdir` under the default read-only root filesystem and its server still
reads `/data/conf/valkey.conf`. Released 0.12.0, the chart this catalogue
pins, agrees with itself; the bug ships with their next version bump.

Measured, never inferred: `upstream/checks/valkey-helm-standalone-conf-path.sh`
renders the chart at 8d30231 and 0.12.0 from a fresh clone (Deployment:
MISMATCH; StatefulSet and 0.12.0: AGREES) and, given an image, runs the
rendered script as the pod does; a k3s v1.37.0 cluster showed the pod in
`Init:Error` on 2026-09-30. A second review briefed to argue against filing
corrected two sentences before it went out (as uid 1000 a writable root
filesystem gives `Permission denied`, not a stray write; the transcript now
names the Alpine image behind busybox's wording of the error) and found no
duplicate, no fix in flight and no documented step that makes it intended.

Why it matters here: the owner's fix for #247 is upstream PR 263
(`initContainer.image`, defaulting to the Valkey image). Its standalone
e2e cannot pass on their `main` until #264 is fixed, so the PR's cluster
evidence is replica mode. Held back for a day at the owner's call, then
filed once a reviewer testing standalone mode would have hit it.

Next check: an answer on #264 or #263; the compat `review_by` date stays
2026-11-24.

## 2026-10-05: grafana 13.1.7, the three tag-scoped statements move with the release (#246)

Grafana 13.1.7 (Renovate's #246, released 2026-09-29) is a security
release: its changelog names CVE-2026-13719, CVE-2026-13720 and
CVE-2026-81841 as fixed. None of the three ever appeared in a scan of this
image (no mention anywhere under `triage/`), so there is nothing to close
here. Renovate's post-upgrade check re-verified the tarball checksums across
the two origins and dated the authenticity comment in `image/grafana/image.yaml`
2026-10-05.

The bump PR went red for the reason the 13.1.6 bump did (2026-09-18): the
two tempo `fixed` statements and the CVE-2026-42151 `fixed` statement are
scoped to the published tag, `13.1.6-alpine3.23`, which the bump stops
publishing. The VEX product lint refused the three files, and the PR's scan
gate on the 13.1.7 build listed exactly two uncovered findings, CVE-2026-21728
and CVE-2026-28377 on `github.com/grafana/tempo`, the pair those statements
cover. Nothing else was uncovered within the aperture, so 13.1.7 brings no
new finding to decide on.

Measured before moving them: `go.mod` at tag v13.1.7 pins
`github.com/grafana/tempo` at `v1.5.1-0.20260427112133-525d1bab07e0` (line
123) and `github.com/prometheus/prometheus` at `v0.312.0` (line 169), with
no `replace` directive for either; both lines are byte-identical to v13.1.6's.
So the commit-ancestry argument of 2026-08-05 carries unchanged, and the
prometheus fix statement of 2026-08-03 holds as it did for 13.1.1 through
13.1.6. The three statements now name `13.1.7-alpine3.23`, and the
CVE-2026-42151 note says so. The twelve exceptions of 2026-09-03 are not tied
to a tag and stand untouched until their 2026-11-02 review; whether 13.1.7
bundles a newer zipkin datasource was not measured here.

Next check: the gate on the rebuilt 13.1.7 reads the moved statements; the
first nightly after the merge attests them against the new digest.

## 2026-10-08: the live-evidence ledger, seeded from the audit (task 16.1, Req 7.11)

`docs/live-evidence.md` now carries one row per criterion, 153 rows, each
naming the mechanism, its first live exercise, the evidence and how it was
induced. The seed is the audit of 2026-09-27 (the per-step tallies over
1,028 `build.yml` and `rescan.yml` runs, the offline re-verification of the
supported set) extended by what that audit's job data did not cover: the
pull-request histories of `validate.yml`, `chart.yml` and `e2e.yml`, read
back to July for the first time each gate refused something, the issue and
pull request history, and the events since the audit.

What the seed measured, beyond the eleven mechanisms Decision 13 already
named: 114 criteria are exercised, 32 wait for a drill (tasks 16.3 to 16.15),
6 are unexercised with a reason no drill removes (1.18, 2.26, 3.13, 3.15,
4.8, 4.9), and 1 is a defect: 6.55's attested scan reports carry empty
database fields, measured on 2026-09-27 over fourteen manifests and again on
2026-10-08 on the 13.1.7 attestation written by trivy 0.75.0. The ledger
keeps that row as `defect` until an attestation shows the fields filled.

Nature supplied one drill before the drills began: grafana 13.1.7 (#246,
published 2026-10-06 by the scheduled build, run 37457046807) bundled the
zipkin datasource at v12.4.8 and apache/thrift 0.24.0, so twelve findings
left the supported digest and the rescan of 2026-10-06 (run 37470485195)
published the first fix clock: twelve fixed, median 30 days to fix. 16.6's
fix clock is therefore exercised; its issue-closure half is not, those
issues having closed at decision time in September.

Two live exercises were found only by placing timestamps side by side: the
automerges. #111 (valkey 9.1.2) merged at 13:19:42 UTC inside Renovate run
33512615078, #252 and #253 inside runs 37575287810 and 37643271339; the
merge record names the token's owner either way, so the run window is the
evidence (3.5, 3.12). The lint-refusal criteria the ledger found never
exercised live (1.11, 1.12, 5.8, 6.19, 9.6, beside those task 16.15 already
lists) join that task's one pull request.

The check: `scripts/lint-live-evidence.sh` in validate.yml holds one row per
criterion, no row for a retired number, a status among the four, a mechanism
and evidence or a reason (thirteen cases in its suite, the last over the real
ledger). Next: task 16.2, the drill definition, which needs the owner's
`drill-app` repository first.

## 2026-10-12: fix by fetch-phase module bump, CVE-2026-78669, golang.org/x/net v0.58.0 (#263, the cert-manager half, on #256)

*Images: cert-manager-controller, cert-manager-webhook, cert-manager-cainjector.
hardened-app's half of #263 is fixed by the toolchain alone (its gate job on
#256 passes); grafana's half is a repackaged upstream binary and is decided
separately; #263 stays open until every repository on it is fixed or
covered.*

GO-2026-6611, created by the Go security team on 2026-10-08: a malicious
HTTP/2 peer opens many streams and sends many small SETTINGS frames carrying
SETTINGS_INITIAL_WINDOW_SIZE, and the client or server spends its CPU
reprocessing them. Fixed in Go 1.26.9 and 1.27.2 and in golang.org/x/net
v0.60.0. HIGH, EPSS 0.0023 (12th percentile), not in CISA KEV. First seen by
the rescan on 2026-10-10 and filed as #263, a day after the stdlib pair of
#258 and #259 (CVE-2026-78667, CVE-2026-97031, same fix versions).

The three cert-manager images carry the vulnerable code twice. The standard
library's bundled HTTP/2 moves with the toolchain: Renovate's #256 (dhi.io
build layer, golang 1.27.1 to 1.27.2) clears it, and the gate on that pull
request's run 38059338277 shows the delta register row M2 asks the reviewer
to read: hardened-app passes outright, and each cert-manager build names
exactly one finding left, `golang.org/x/net@v0.58.0, fixed: 0.60.0`. That
copy is the module v1.21.2's go.mod pins (indirect; each cmd submodule's
go.mod repeats the pin, at lines 163, 82 and 72), so only a pin move retires
it. Upstream has made the move: golang.org/x/net v0.60.0 on master (ceb7b0f)
and on release-1.21 (#9451), both 2026-10-09, beside the Go 1.26.9 toolchain
bump (#9444); no release carries them, and no release issue for v1.21.3
exists today (v1.21.2's, #9237, preceded its release by ten days).

**Decision: fix** (owner's call, 2026-10-12: "most prudent", and it "shows
the usefulness of this product"). The reach order's first rung, through the
lane the 2026-09-02 entry established and the 2026-09-18 entry retired: a
`go/bump@v2` step in each definition's fetch phase, work-dir the cmd
submodule the binary resolves through, `golang.org/x/net@v0.60.0` with its
`# renovate:` marker (Req 7.6), `download: true`, `tidy: true`. Minimal
version selection makes the pin a floor: a later upstream requirement wins,
an accidental downgrade cannot happen. x/net v0.60.0's own go.mod requires
Go 1.26 and x/crypto v0.57.0, x/sys v0.48.0, x/term v0.46.0, x/text v0.42.0,
which the bump carries along. The Renovate manager suite now holds each live
cert-manager definition to exactly that one marked pin, watched red before
the step went in; the step itself cannot be rehearsed from this environment
(no module proxy, no dhi.io), so the pull request's scan gate is its test,
as it was on 2026-09-02.

Why not the other rungs. Not affected: the vulnerable symbols are the HTTP/2
client and server flow-control paths (GO-2026-6611 lists
`Transport.newClientConn`, `Server.serveConn` and the `outflow` functions
among them); nobody measured them unreachable, a reachable symbol forbids
the statement (Req 6.14) and a module-level result is unmeasured (Req 6.16).
Transfer under an exception would have been honest but ships the copy until
v1.21.3. Waiting undecided was within the ceiling (3 of 90 days) and kept
the gate red on #256 and on every cert-manager rebuild.

**Exit condition:** drop the step from all three definitions when an
upstream release pins `golang.org/x/net` at v0.60.0 or newer (release-1.21
already does, so v1.21.3 is the expected release); the Renovate release PR
for that version is the reminder, this entry is the record.

**Machine-readable form:** a `fixed` statement scoped to `1.21.2-alpine3.23`
with subcomponent `pkg:golang/golang.org/x/net`, per the CVE-2026-56854
precedent, added once this pull request's gate shows the finding gone from
the three builds (the run is recorded here when it does); digests published
before the bump genuinely carry v0.58.0 and are outside its scope.

**Measured, 2026-10-12:** on the pull request's run 38277598545 (head
85a6d32) the scan gate passed on all three cert-manager builds with nothing
uncovered within the aperture, where run 38059338277 had named the x/net
finding on each; hardened-app passed as before and grafana failed on its
twelve, which are the next decision. validate, chart and e2e were green,
the Renovate suite holding the three new markers (20 in all). The `fixed`
statement `triage/vex/CVE-2026-78669.openvex.json` is in the same pull
request. Next check: the first nightly after the merge attests SBOMs that
list golang.org/x/net v0.60.0, and the rescan's status rows for the three
repositories flip to fixed while #263 stays open for grafana.

## 2026-10-13: 13.1.7, the twelve findings of the Go 1.26.9 wave (grafana half of #258, #259, #263; on #256)

*Image: grafana. Decisions taken one at a time on 2026-10-13 (owner's calls
through the session's decision page, then in chat). Every number below was
measured on the published 13.1.7 amd64 image (tag 13.1.7-alpine3.23, platform
manifest sha256:6656a754…, the grafana layer sha256:1b5c2431…), pulled by
digest and read in place: `go version -m` for toolchain and module versions,
`go tool nm` for the server, which keeps its symbol table (503,143 symbols),
and the pclntab read with Go's own `debug/gosym` for the two stripped plugins
(36,903 functions in zipkin, 47,222 in elasticsearch), with `strings` as the
second reader. The gate on #256 reported the identical twelve on run
38278927825 (head cff09fa) and again on run 38366092741 (head 375f846).*

**What the three are.** All from the Go security team's 2026-10-08 batch,
fixed in Go 1.26.9 and 1.27.2, none listed by CISA:

| CVE | Report | Where | Vulnerable symbol | Fixed |
|---|---|---|---|---|
| CVE-2026-78667 | GO-2026-6609 | `net/http` | `parseRange`, reached through `ServeContent`, `ServeFile`, `ServeFileFS`, `fileHandler.ServeHTTP`, `fileTransport.RoundTrip`: a Range header with thousands of pieces burns CPU | go1.26.9 |
| CVE-2026-97031 | GO-2026-6607 | `crypto/tls` | `decodeInnerClientHello`: repeated ECH outer extension references exhaust a TLS server's memory | go1.26.9 |
| CVE-2026-78669 | GO-2026-6611 | `net/http` and `golang.org/x/net/http2` | seventeen flow-control symbols (`outflow`, `serverConn`, `Transport.newClientConn`, `clientConnReadLoop`, ...): many small SETTINGS frames burn CPU on either side | go1.26.9, x/net v0.60.0 |

HIGH all three; 78667 and 97031 carry CVSS 7.5 (GHSA-f4xw-m386-m277,
GHSA-hq7w-2xrq-wp2j), no EPSS score yet; 78669 has EPSS 0.0023 (12th
percentile). Denial of service each, no data access. 78669's cert-manager half
was fixed by the fetch-phase bump in the 2026-10-12 entry; the lane does not
exist for grafana, which repackages the official release tarball and compiles
nothing (`image/grafana/image.yaml`).

**Where they sit.** Three Go binaries, each carrying the three stdlib
findings and the x/net one, which is the gate's twelve:

| Binary | Built with | x/net | 78667 `parseRange` (+5 callers) | 97031 `decodeInnerClientHello` | 78669 stdlib (17) | 78669 x/net (17) |
|---|---|---|---|---|---|---|
| `bin/grafana` (13.1.7) | go1.26.6 | v0.58.0 | present (2, 3, 2, 1) | present | 13 of 17 | 13 of 17 |
| `plugins-bundled/zipkin/gpx_…` (v12.4.8, built 2026-09-10, stripped) | go1.26.7 | v0.58.0 | absent, all six | present | 17 of 17 | 0 of 17 |
| `plugins-bundled/elasticsearch/gpx_…` (v12.9.0, built 2026-09-16, stripped) | go1.26.7 | v0.58.0 | absent, all six | present | 17 of 17 | 0 of 17 |

The four flow-control symbols absent from the server (`outflow.available`,
`outflow.setConnFlow`, `outflow.take`, `ClientConn.addStreamLocked`) are
small enough to be folded into their callers; the thirteen present settle
the question. In the plugins the `x/net/http2` package is linked for its
`Framer` and `hpack` types, which gRPC uses, and for nothing of the server,
client or flow-control kind: no `serverConn`, `ClientConn`, `Transport` or
`outflow` receiver appears at all, so inlining cannot hide an absent call
chain there either.

**The rungs, once for all twelve.** Fix: closed, no build to bump; a
from-source grafana definition would be a new archetype and is its own
decision, not a same-day route. Avoid: impossible for the server, available
and declined for the plugins for the 2026-09-03 reason (a drop-in Grafana
keeps its datasources). Not affected: decided per binary below. Accept would
deny that upstream is fixing every one of these; it is, so every entry is a
transfer. One re-decision date for the round, 2026-12-12, sixty days from
the decisions, inside the ninety-day HIGH ceiling, as the 2026-09-03 round
did. The owner's standing rule, stated with the decisions: a transfer is only
complete with an actionable item upstream, a ticket the owner opens from a
drafted text; nothing goes upstream without that approval.

### TRANSFER: the server binary, four findings, waiting on 13.1.8

`bin/grafana` carries all three CVEs and the HTTP/2 one twice. Every
vulnerable symbol is present in its symbol table: `parseRange` with
`serveContent`, `ServeContent` and `ServeFile` above it; `decodeInnerClientHello`
beside `(*Conn).processECHClientHello` and the server handshake; thirteen of
the seventeen flow-control symbols in each copy. Present forbids
`not_affected` (Req 6.14), and nothing was measured finer than presence.

Upstream has done the work: Grafana merged Go 1.26.9 (#134622) and
`golang.org/x/net` v0.60.0 (#134613) on `release-13.1.8` on 2026-10-09,
beside the same bumps on main and the other maintained lines. No 13.1.8 has
been cut; 13.1.7 is from 2026-09-29, and the two previous patch releases came
a fortnight apart.

**Decision: transfer** (owner's call, 2026-10-13, expiry 2026-12-12). Three
entries on path `usr/share/grafana/bin/grafana`: CVE-2026-78667 and
CVE-2026-97031 on `pkg:golang/stdlib`, CVE-2026-78669 on both
`pkg:golang/stdlib` and `pkg:golang/golang.org/x/net` (one entry per id and
path, Req 6.25). Tracker: the merged release-branch pull requests; no timing ticket is
opened, the cut is the only step left. The bundling half of the same release
is grafana/grafana#131863, seconded below.

**Exit condition:** the Renovate pull request for grafana 13.1.8 drops the
three entries; its gate shows the four server findings gone.

### TRANSFER: the two plugins and the Range-header CVE, absent code and no way to say so yet

In both plugin binaries `net/http.parseRange` is absent, and so is every
function that reaches it: `ServeContent`, `ServeFile`, `ServeFileFS`,
`(*fileHandler).ServeHTTP`, `(*fileTransport).RoundTrip`, all 0 in the pclntab
and in `strings`. A datasource backend answers the host over gRPC and serves no
files; the compiler dropped the whole path. This is the structural case the
2026-09-18 xDS decision made, one level finer: function names rather than
package paths.

The statement cannot be written today. A `not_affected` statement scopes by
package, never by binary: Req 6.19 keeps the subcomponent purl versionless,
and `compile-vex.sh` merges every decision about one (finding, package) across
binaries into a single statement. `pkg:golang/stdlib` is also the server's
package, where `parseRange` is present, so a statement for the plugins would
silence the server's finding and be false there. Two routes were put to the
owner: transfer now and a tag-scoped statement once 13.1.8 moves the server
past the bug and the plugins are the only carriers left, or amend Req 6.19 to
admit a versioned subcomponent when two binaries carry one package at two
versions (the plugins' 1.26.7 against the server's 1.26.6), a spec, lint,
compiler and measurement change.

**Decision: transfer, the first route** (owner's call, 2026-10-13: "Transfer
as suggested as option 1"; expiry 2026-12-12). Two entries on
`pkg:golang/stdlib`, paths `usr/share/grafana/data/plugins-bundled/zipkin/*`
and `…/elasticsearch/*`, each saying in its `blocked` that the code is absent
and why the statement waits. A transfer of nothing is the honest record the
lane can hold for it today.

**Exit condition:** at 13.1.8, if the bundled plugins are still built below
go1.26.9, replace the two entries with one `not_affected` statement scoped to
the 13.1.8 tag, `vulnerable_code_not_in_execute_path`, subcomponent
`pkg:golang/stdlib`, citing this entry's measurement; if the bundles have moved
too, drop them.

### TRANSFER: the two plugins and the x/net copy of CVE-2026-78669, absent flow control

The plugins link `golang.org/x/net` v0.58.0, and Trivy names the module. What
they link of `x/net/http2` is the frame layer: `(*Framer).ReadFrame`, the
frame types and `hpack`, which gRPC uses underneath its own transport. None of
the seventeen symbols GO-2026-6611 names is present, and no method of
`serverConn`, `ClientConn`, `Transport` or `outflow` appears, so no caller
could carry an inlined copy.

The same scoping bar applies, with less to lean on: the server carries the
same module at the same version with thirteen of the seventeen present, so a
package-scoped statement cannot separate the two, and there is no version
difference to scope by. The entry for this finding shares the stdlib copy's
entry on each plugin path (both purls on one entry, Req 6.25), and this
sub-entry is the record of the x/net half.

**Decision: transfer** (owner's call, 2026-10-13, expiry 2026-12-12), the
absence on record.

**Exit condition:** at 13.1.8 the server moves to x/net v0.60.0 and the
plugins become the only carriers of v0.58.0; a `not_affected` statement scoped
to that tag, subcomponent `pkg:golang/golang.org/x/net`, becomes writable on
this measurement. The elasticsearch upstream already carries v0.60.0 on main
(#447, 2026-10-09); a release and a bundle retire its half outright.

### TRANSFER: the two plugins, stdlib HTTP/2 and the ECH parser, four findings

Both plugins carry all seventeen flow-control symbols of the standard
library's bundled HTTP/2 and `crypto/tls.decodeInnerClientHello`, with
`(*Conn).serverHandshake` and `hashicorp/go-plugin.generateCert` beside it:
go-plugin's certificate generation for its automatic mTLS is linked, so a TLS
server handshake inside the plugin is a live path, not a dead one. Whether
the HTTP/2 server or client code ever runs in a plugin is not measurable in
a stripped binary (Req 6.16), and a present symbol forbids the statement
anyway (Req 6.14). Reachability is not claimed.

Upstream state. zipkin: the shipped v12.4.8 was built 2026-09-10 with
go1.26.7; the newest release, v12.4.9 (2026-09-28), predates the Go fix;
`main` still says `go 1.26.7` and pins x/net v0.59.0; #94 is open from the
first round and #100 (2026-08-31) names the same stale-bundle problem.
Renovate's #109 (2026-09-25, refreshed 2026-10-13) carries x/net v0.60.0
with every check green and no review, so the x/net half has a live pull
request; the Go bump has none.
elasticsearch: the shipped v12.9.0 was built 2026-09-16 with go1.26.7; the
newest release, v12.9.2 (2026-10-06), predates the fix; `main` moved x/net to
v0.60.0 on 2026-10-09 (#447) but still says `go 1.26.7`; the release-please
pull request #448 (2026-10-09) would ship #447 as 12.9.3; no tracker existed
for the Go bump. On the Grafana side, grafana/grafana#131863 (2026-08-31,
labelled security and build-packaging) already names the bundling lag, with
a maintainer's acknowledgement on 2026-09-23 that bundled versions resolve
at build time; it is the item to second for the rebundle, not a new ticket. A fix needs two steps nobody here controls: each plugin
rebuilt with go1.26.9 or newer and released, then a grafana release that
bundles that build.

**Decision: transfer** (owner's call, 2026-10-13, expiry 2026-12-12). Four
findings, carried by four entries: CVE-2026-97031 on `pkg:golang/stdlib` and
CVE-2026-78669 on both purls, per plugin path. Trackers: zipkin stays on #94,
which the owner extends with this round, #109 carrying the x/net half;
elasticsearch gets the owner's new issue for the Go bump,
grafana-elasticsearch-datasource#450 (filed 2026-10-13 from the draft), the
`issue:` of its three entries, #448 carrying the x/net half.

**Exit condition:** a grafana release whose bundled plugin reports go1.26.9
or newer in `go version -m`; the Renovate pull request for that release is the
reminder, this entry the record.

### Measured, and what govulncheck says about a stripped binary

govulncheck was asked for, as the tool of record (Req 6.13), and it could not
be installed the usual way: `proxy.golang.org`, `golang.org` and the vulnerability
database host are all outside the devcontainer's allowlist. It was built from
the module cache instead (`golang.org/x/vuln@v1.4.0`, x/tools v0.45.0 and a
cached telemetry pseudo-version swapped in by `replace`), and fed a local
database assembled from the three reports in `golang/vulndb` (`data/osv/`,
plus the three index files), `-mode=binary -db file://…`.

On the server its symbol results agree with the symbol table: three
vulnerabilities, every trace a present symbol. On the two plugins it printed
symbol results that name `net/http.ServeContent`, `ServeFile`, `ServeFileFS`
and the x/net `ClientConn` methods as found, in binaries whose function tables
contain none of them. Its own source explains it: when the ELF symbol table is
missing, `internal/vulncheck/binary.go` substitutes every known vulnerable
symbol of each affected package ("we report vulnerabilities at the go.mod-level
precision", golang/go#57764) and renders that under `=== Symbol Results ===`.
That is the "not measured" row `scripts/govulncheck-report.sh` already
reserves for a stripped binary, and this round confirms the reading: a
govulncheck symbol hit on a stripped plugin is silence, not absence, and not
presence either. The pclntab read is the finer instrument, and it is the Go
toolchain's own (`debug/gosym` over `.gopclntab`, no symbol table needed).
Controls: the stdlib HTTP/2 names were found in all three binaries, so the
reader does find names in the stripped ones; in the plugins the x/net frame
names were found while the flow-control names were not.

Trivy could not be rerun locally: its database refresh is blocked the same
way, and the cached database (2026-09-10) predates the three reports. The
count of twelve is the gate's own, from both runs named above; the split per
binary is this entry's, from the binaries.

**Downstream record, 2026-10-13:** #258, #259 and #263 carry the
`transfer-upstream` label and a decision comment each with the per-binary
table, so every upstream text can point at them; the texts are drafted under
`triage/upstream/2026-10-13-*` with the measurement script
`checks/grafana-go-wave-symbols.sh`.

**Posted upstream, 2026-10-13:** the comments on grafana/grafana#131863,
zipkin #94 and #109 and elasticsearch #448, and the new issue
grafana-elasticsearch-datasource#450, all from the drafts, each pointing back
at #258, #259 and #263. With that the nine entries are complete and the round
is committed on #256, whose gate should then have nothing uncovered on
grafana; the run is recorded here when it does. At 13.1.8: drop the three server entries, write the two
tag-scoped statements if the bundles still lag. Housekeeping for a later
commit: the twelve zipkin entries and the two server entries of 2026-09-03
have matched nothing since 13.1.7 (the 2026-10-08 entry's fix clock) and are
due for the retirement the 2026-09-03 round modelled.

**Measured, 2026-10-13:** on the pull request's run 38380831106 (head 47bb9b0) the
scan gate passed on grafana with nothing uncovered within the aperture, where
runs 38278927825 and 38366092741 had named the twelve; cert-manager and
hardened-app passed as before, and the build gate, the e2e gate, the render
and policy gate and the lint battery were green. The nine entries suppress
what they claim and nothing else: the twelve were the only uncovered findings
on grafana before them.

## 2026-10-18: the drill definition joins the catalogue, two findings decided (task 16.2)

*Image: drill-app, the live-drill fixture: `mm-weber/drill-app` v0.1.0 at
b7868d7a6f41a8dc2181bd874776cf4976d11591, a copy of hardened-app whose go.mod
pins `github.com/gorilla/handlers v1.2.1` and `github.com/golang-jwt/jwt/v5
v5.2.1` on purpose. Pull request #286, conductor track
`drill-definition_20261017`, design Decision 14's pull request 1: the
definition, the active-set entry and the catalogue's first proof of kind none
(`catalogue-policy.yaml`, reason "live-drill fixture, never installed by design
(task 16.2)"), printed by the probe lint on every validation run (Req 5.9; run
39107650952). No chart deploys it and none ever will; task 16.16 retires it.
Decisions taken one at a time on 2026-10-18, the owner's calls in chat on the
evidence below.*

**Two runs.** The first (39106821681, head 7787f95) failed in the frontend's
test step before any scan: build-stage `runs:` steps have no egress
(docs/CONVENTIONS.md, measured 2026-07-26), so the archetype's `go test ./...`
could not fetch the drill's two modules; the step was dropped with a comment,
the cert-manager precedent (`go/build@v1` fetches the modules itself), commit
5d6beff. The second (39107650953, job 117616899700) built the image, ran the
Trivy scan, the VEX portability block, govulncheck, the Grype second opinion and
the exception tiers against KEV (the feed reachable, no exception yet), and the
scan gate failed by name:

> drill-app: 2 uncovered within the aperture (1 CRITICAL, 1 HIGH; Req 6.1):
> CVE-2017-20146 (CRITICAL github.com/gorilla/handlers@v1.2.1, fixed: 1.3.0);
> CVE-2025-30204 (HIGH github.com/golang-jwt/jwt/v5@v5.2.1, fixed: 5.2.2). Four
> ways out, strongest first: avoid (drop the component) · fix (version bump,
> Req 6.5) · prove it does not apply (OpenVEX in triage/vex/, Req 6.4) · accept
> or transfer for a bounded time (triage/accepted-risk/drill-app.yaml, Req 6.7).
> An expired exception counts as uncovered.

**Reachability (Req 6.13).** govulncheck v1.6.0 in binary mode on
`usr/local/bin/drill-app`, whose symbol table the definition keeps (`-w` only,
no `-s`), from the run's step summary:

| Level | Advisory | Aliases | Module | Version | Package | Symbol |
| --- | --- | --- | --- | --- | --- | --- |
| symbol | GO-2020-0020 | CVE-2017-20146, GHSA-jcr6-mmjj-pchw | github.com/gorilla/handlers | v1.2.1 | github.com/gorilla/handlers | ServeHTTP |
| symbol | GO-2025-3553 | CVE-2025-30204, GHSA-mh63-6h87-95cp | github.com/golang-jwt/jwt/v5 | v5.2.1 | github.com/golang-jwt/jwt/v5 | ParseUnverified |

Both at symbol level, and the source says why: `handlers.CORS(...)` wraps the
drill's mux, so `ServeHTTP` is on every request's path; `/whoami` calls
`jwt.Parse`, which reaches `ParseUnverified`. Symbol level forbids a
`not_affected` statement (Req 6.14).

**The rungs, once for both.** Mitigate: a fixed release exists for each
module (handlers 1.3.0, jwt 5.2.2) and is declined on purpose; the findings are
the drill's reason to exist, and their removal is drill 16.6. Avoid: dropping
the CORS middleware or the token parser is possible and declined for the same
reason. Not affected: forbidden, see above. Transfer: there is no upstream but
the owner's own repository. What is left is accept, time-boxed within each
finding's ceiling (`catalogue-policy.yaml` triage: 30 days for a CRITICAL, 90
for a HIGH, 14 for anything CISA lists; CISA lists neither on 2026-10-18, the
gate's tiering step having passed against the live feed).

### ACCEPT: the drill's CRITICAL, gorilla/handlers CORS ServeHTTP, reachable by design

CVE-2017-20146 (GO-2020-0020, GHSA-jcr6-mmjj-pchw; CRITICAL, CVSS 9.8 in the
advisory database as read on 2026-10-15 when the module was chosen) sits in
`handlers.CORS`'s `ServeHTTP`, the middleware the drill wraps every request
in. Reachable, by construction.

**Decision: accept** (owner's call, 2026-10-18, expiry 2026-11-17, the CRITICAL
ceiling in full). One entry on path `usr/local/bin/drill-app`, purl
`pkg:golang/github.com/gorilla/handlers` (versionless, as the lane's entries
are), published in the drill's OpenVEX document as `affected`; the status page
shows the finding under the exception; nothing installs the image.

**Exit condition:** drill 16.6 bumps the module to 1.3.0 and the finding
leaves the supported digest. Before that, 16.4 re-decides the expiry to four
days out and lets it lapse on purpose, and 16.9 lets an exception expire for
the fail-closed release gate; each re-decision is its own entry here.

### ACCEPT: the drill's HIGH, golang-jwt ParseUnverified, reachable by design

CVE-2025-30204 (GO-2025-3553, GHSA-mh63-6h87-95cp; HIGH, CVSS 7.5 in the
advisory database as read on 2026-10-15 when the module was chosen) sits in
`jwt.Parser.ParseUnverified`, which `/whoami` reaches through `jwt.Parse` on
every bearer token it is handed. Reachable, by construction. CISA does not list
it on 2026-10-18 (the gate's tiering step passed against the live feed), so its
ceiling is the HIGH's ninety days; drill 16.3 re-decides this entry against the
fourteen-day KEV ceiling under the substituted feed of drill 16.8, the
attribution trivy cannot supply on its own (measured 2026-10-15).

**Decision: accept** (owner's call, 2026-10-18, expiry 2027-01-16, the HIGH
ceiling in full). One entry on path `usr/local/bin/drill-app`, purl
`pkg:golang/github.com/golang-jwt/jwt/v5`, published as `affected` beside the
first; with both entries in place the gate's third run has nothing uncovered
within the aperture, and the pull request can merge.

**Exit condition:** drill 16.6 bumps the module to 5.2.2 and the finding leaves
the supported digest; 16.3's re-decision replaces this entry's dates first,
its own entry here.

**Published, 2026-10-18 22:40Z** (main's run 39172583475 on the squash
1b941ea, job 117808588141): the release-time scan of the pushed digest passed
(Req 2.8), the fail-closed gate stayed off by the switch, the platform
manifests' scan reports were attested, the OpenVEX document compiled with the
two `affected` statements, everything signed, the three tags applied (Req 2.9,
2.12). The index sha256:53e0c498140406834754957dd5782279201a5529cda6f00f6cacc5b4685dad83
under `0-alpine3.23`, `0.1-alpine3.23` and `0.1.0-alpine3.23`; platform
manifests linux/amd64 sha256:7d59e3a23bfcd915ed4f4f9183b0914c4524bb357be280b88d14e48bb507bc71
and linux/arm64 sha256:2e19dfd9cdb0e12d2344c85a50717d8ab8ce2da5d7caa85dff8aac6c062352d2,
each with its `.sig` and `.att` beside the index's. Read anonymously on
2026-10-19 with a pull token, the visibility invariant's own method: the
package came out public on its first publish, nothing for the owner to flip.
Renovate's dashboard listed `image/drill-app/image.yaml` with `mm-weber/drill-app
v0.1.0` by the next morning (the tracking scope, Req 1.14). The first rescan
after the publish had not run when this was written; what it does with the two
findings on the supported digest is recorded below once observed, never
predicted.

**The first rescan after the publish, 2026-10-19 08:28 to 08:48Z** (run
39223026946, dispatched by the owner; job 117962583384): the enumeration
listed the drill's three tags, every platform manifest was scanned, the
invariants held with the new package public (Req 2.21, 2.24), today's reports
were attested, the authenticity signals, the VEX portability block and the
consumer smoke test passed over the supported set, and the posture invariants
held. No issue was filed for drill-app: both findings arrived already decided,
and the issue set had nothing new, so the filing step did not run (Req 6.3's
mechanism stays exercised by nature, not by this drill). The status issue
(#151) shows two rows for drill-app: CVE-2017-20146, CRITICAL, KEV no,
`decided (affected)`, first seen 2026-10-18, "accept, accepted risk until
2026-11-17"; CVE-2025-30204, HIGH, KEV no, `decided (affected)`, first seen
2026-10-18, "accept, accepted risk until 2027-01-16"; the published status data
carries each exception's statement with its binary and expiry. The same run
opened the fourteen-day expiry warnings for the grafana exceptions of
2026-09-03 (ten annotations, expiring 2026-11-02), as the calendar foresaw;
nothing to do with the drill. Task 16.2 ends here; 16.4 is the first drill
that moves these two entries.

## 2026-10-19: grafana deactivated, the switch exercised live; twelve moot exceptions retired

*Image: grafana. The owner's call of 2026-10-19, pull request #290, conductor
track `retire-grafana_20261019`: the catalogue stops standing behind new grafana
builds, by the documented switch and nothing more (docs/CONVENTIONS.md,
"Deactivating a definition means removing its line, and only that"). The
switch had never been exercised live; a real definition exercises it for the
ledger's rows 1.15 and 1.16.*

**Four levels, one chosen.** Deactivate: the line leaves the active set, the
directory and the chart stay, everything published keeps its tags, signatures,
attestations and daily planes, and the supported digest keeps its issues and
clocks. Remove from the catalogue (task 16.16's shape): directory and chart
deleted too, the daily enumeration no longer sees the repository. Revoke: a
digest that must not be used, the runbook. End of life with deletion: not in
the spec, SECURITY.md promises that nothing is deleted. Level one, this entry.
The four are tabled in the track's spec.

**What changed on the merge.** `grafana` left `active_set` in
`catalogue-policy.yaml`; nothing under `image/grafana/` or `chart/grafana/`
moved. The tracking block of `renovate.json5` re-rendered to ignore
`image/grafana/**` and `chart/grafana/**` (`scripts/render-tracking.sh`,
Req 1.14, 3.2). The lints on the merge: `7 active definition(s), 1 inactive, 4
chart director(ies) with a deploys list` and `7 active definition(s): 6 covered
by 3 probe registration(s), each executed once per install, 1 declared none`;
the e2e components cert-manager, hardened-app and valkey. A change under
`image/grafana/` without the line back now fails validation by name (Req 1.16,
measured in a scratch copy on 2026-10-19: `image/grafana/image.yaml:
image/grafana/ is not in the active set, so this change cannot be built,
tested or published; activate the definition in this pull request (active_set
in catalogue-policy.yaml) or leave it frozen (Req 1.16)`).

**What did not change.** The supported digest sha256:89c5680a868b (13.1.7)
under `13-alpine3.23`, `13.1-alpine3.23` and `13.1.7-alpine3.23` stays
pullable with its signatures and attestations; the daily enumeration, scans,
re-attestation, admission proof and visibility invariant keep running over it;
its findings keep every status lane except the fix, because no release will
move its tags again. Reactivation is the line added back.

**The twelve moot exceptions, retired.** The 2026-09-03 round's entries
(zipkin plugin: CVE-2026-39822, CVE-2026-33818, CVE-2026-39821,
CVE-2026-46600, CVE-2026-56853, CVE-2026-56858, CVE-2026-56859,
CVE-2026-56860, CVE-2026-56862, CVE-2026-84304; the server binary:
CVE-2026-43871, CVE-2026-84304) had matched nothing since 13.1.7 (the
2026-10-08 entry's fix clock; the 2026-10-13 entry's measured paragraph).
The status issue (#151) records each as fixed on 2026-10-06, thirty days from
the decision, and they had entered their fourteen-day expiry window on
2026-10-19 (ten annotations on run 39223026946). Removed from
`triage/accepted-risk/grafana.yaml` with their comment blocks, the shape the
2026-09-18 entry set; the file's header says so.

**What stays open, named here so it is not forgotten.** The nine transfers of
2026-10-13 (CVE-2026-78667, CVE-2026-97031, CVE-2026-78669 across the server
and the two plugins, expiry 2026-12-12) lose their planned exit, a grafana
13.1.8 build; on 2026-12-12 the honest re-decision is accept, no build will
fix this image, or level two. Five undecided HIGH findings in the same digest,
all in `github.com/getkin/kin-openapi` v0.144.0 (CVE-2026-100351 to
CVE-2026-100354, #274 to #277, first seen 2026-10-16; CVE-2026-100349, #287,
first seen 2026-10-18; fixed upstream in 0.146.0 to 0.149.0), on their
ninety-day clocks: the owner's calls, one at a time, outside this track.

**Exit conditions.** The first inactive day's evidence (no grafana build job,
the rescan's inactive-digest check naming one definition, Renovate's #279
refused by the lint and closed) goes into this entry's addendum and the
ledger's rows 1.15 and 1.16; task 16.11's drill keeps its own twist, the
proofs entry and the 1.19 branch.

**The first inactive day, part one (2026-10-19, 16:50 to 17:00Z).** The squash
04c6eeb merged at 16:50:10Z. Main's push build (run 39288882482) ran the
affected-definitions job, named nothing to build, skipped the matrix job and
passed its gate in nineteen seconds; the chart run (39288882379) and the
validate run (39288882400, the fourteen lints over the inactive state) green.
The registry, read anonymously at 16:56Z: `13-alpine3.23`, `13.1-alpine3.23`
and `13.1.7-alpine3.23` on sha256:89c5680a868b, the digest the status issue's
baseline lists for them; nine plain tags and 181 attestation planes, none new.
The bump refused: the rendered ignore paths now take `image/grafana/**` out of
Renovate's extraction, so the bot will prune #279 rather than rebase it (its
15:23Z run, 39277512324, had already failed before the merge on a docker exit
1, cause unread). The case came the way task 16.11 words it: drill #291 (a
draft, never merged) replayed Renovate's commit f6f89f8, the real 13.1.8 bump,
unchanged onto main; validate run 39289979209 failed at the active-set step in
twelve seconds with `lint-active-set: image/grafana/image.yaml: image/grafana/
is not in the active set, so this change cannot be built, tested or published;
activate the definition in this pull request (active_set in
catalogue-policy.yaml) or leave it frozen (Req 1.16)`, and its build run
39289978981 left grafana out of the matrix by name with the gate green: the
preventive branch of build.yml's affected-definitions job, never run while
every definition was active (Req 1.15). Ledger row 1.16 flips to exercised on
this. Part two, the nightly, the rescan's inactive-digest check and Renovate's
handling of #279, follows.

**The first inactive day, part two (2026-10-19 21:19Z to 2026-10-20 12:17Z).**
Renovate's two failed runs had one cause, its token: `RENOVATE_TOKEN` had
expired on 2026-10-19; the owner regenerated it and re-ran 39323363043 at
21:17Z (attempt 2, green). #279 autoclosed as a stale branch under the
rendered ignore paths, the dependency dashboard (#5) lists nothing of
grafana, and the scheduled run of 04:14Z (39368498446) was green again. At
21:49Z the owner dispatched build.yml blank (run 39330433276): the dispatch
path never runs the publish-on-change comparator (register row M17), so this
was a release, seven definitions rebuilt and republished, 21 tags moved to
new digests, grafana absent from the matrix and its three tags where they
were. The nightly of 2026-10-20 09:40Z (run 39402331027) named the same seven
and failed at every definition's dhi.io login, `unauthorized`, before any
build: the `DHI_TOKEN` secret was no longer accepted where the same step had
passed at 21:49Z, the registry answering; nothing built, nothing moved. The
rescan of 11:47Z (run 39417467219, the first after the merge) passed its
inactive-digest check with grafana the one inactive definition and its three
tags the comparison against the previous status (the branch for a missing
previous status annotates the run with a warning; none did), the first run
of that check with something to check since it began on 2026-09-09. The
status issue (#151), re-rendered at 12:12Z, carries grafana on
sha256:89c5680a868b under `13-alpine3.23`, `13.1-alpine3.23` and
`13.1.7-alpine3.23` while the six other repositories moved to the release's
digests; its grafana findings as before, five undecided and the transfers to
2026-12-12; the fixed table keeps the twelve retired exceptions' last
decision as history. The registry, read anonymously at 12:17Z: the same three
tags on the same digest, nine plain tags and 181 planes, none new. Ledger row
1.15 flips to exercised on this, induced by the switch. The track closes.

**The token, closed (2026-10-20 20:45Z to 21:43Z).** The owner rotated
`DHI_TOKEN` and re-ran the nightly's failed jobs (run 39402331027, attempt
2): every dhi.io login green, grafana absent from the matrix as before. The
re-run kept the schedule event, so the comparator ran, found the package set
changed in all seven, `ca-certificates-bundle` 20260909-r0 to 20261020-r0
from the live apk repository, and published all seven (Req 2.16): 21 tags to
new digests again. Verified here by diffing the attested CycloneDX SBOMs of
the amd64 manifests: the dispatch of 2026-10-19 had republished package sets
equal to the digests before it, and the re-run's differ from the dispatch's
by that one package. The nightlies of 2026-10-11 to 2026-10-19 had all ended
equal. Renovate followed with the chart digest pins (#296, #297, #298).

## 2026-10-21: not affected: CVE-2026-100351, the grafana server links no request-validation middleware (#274)

*Image: grafana, inactive since 2026-10-19 and frozen at 13.1.7 (index
sha256:89c5680a868b under `13-alpine3.23`, `13.1-alpine3.23` and
`13.1.7-alpine3.23`: the digest the #256 base bump built on 2026-10-13, run
38383243337, hours after that day's measurement on its predecessor
sha256:6656a754…). Decision taken on 2026-10-21, the owner's call in chat on
the evidence below: the first of the five kin-openapi findings (#274 to #277,
#287) and the first decision on the frozen image. Every number was measured
on the published linux/amd64 manifest sha256:e4f626e9…, pulled by digest and
read in place with the instrument of the 2026-10-13 round: `go version -m`
for the module versions, the pclntab function table read with Go's own
`debug/gosym` for every binary, `go tool nm` on the server, which keeps its
symbol table, and `strings` as the reader for the file table; the script is
`triage/upstream/checks/grafana-kin-openapi-symbols.sh`.*

**What the vulnerability is.** GHSA-23vg-4cjm-66q5, CVSS 7.4 (network, high
attack complexity, no privileges, confidentiality and integrity high), EPSS
0.49 percent (41st percentile), not in CISA's KEV; CWE-289 and CWE-436.
kin-openapi's request-validation middleware, `openapi3filter.ValidationHandler`,
validates a request, its security requirements included, against the
operation its legacy router selects from the decoded `URL.Path`; a downstream
gorilla/mux router configured with `UseEncodedPath()` dispatches on the
encoded `URL.RawPath`. A request such as `/public%2Fstatus` is validated as
the public `/public/status` and dispatched to the protected `/{id}`, and the
rejecting `AuthenticationFunc` is never invoked. Five preconditions, all on
the application: `ValidationHandler.Middleware` as the security gate, an
encoded-path router behind it, a public exact route overlapping a protected
parameterised one after decoding, the same method on both, and a protected
handler relying on the validation layer's decision. Fixed in 0.147.0
(2026-08-18, commit eda80e2): `validateRequest` gains
`checkEncodedPathSeparator`, which routes the escaped path a second time and
refuses when the two operations differ. Trivy names the module at v0.144.0
from the server's build info, fix version 0.147.0, on
`usr/share/grafana/bin/grafana` and on no other binary.

**Where it sits, and where it does not.**

| Binary | Built with | kin-openapi | Functions (pclntab) | kin-openapi functions linked | `openapi3filter` | `routers/legacy` | `routers/gorillamux` | `mux.(*Router).UseEncodedPath` |
|---|---|---|---|---|---|---|---|---|
| `bin/grafana` (symbol table kept, 503,143 symbols) | go1.26.6 | v0.144.0 | 418,865 | 1,126 | 0 functions, 0 symbols of any kind, 0 strings | 0 | 1: `init`, with its three package variables; `NewRouter` absent | present |
| `plugins-bundled/elasticsearch/gpx_…` (v12.9.0, stripped) | go1.26.7 | none | 47,222 | 0 | 0 | 0 | 0 | absent |
| `plugins-bundled/zipkin/gpx_…` (v12.4.8, stripped) | go1.26.7 | none | 36,903 | 0 | 0 | 0 | 0 | absent |

The 1,126 are 1,125 functions of `openapi3`, the schema package, and the
`init` of `routers/gorillamux`. Every entry point of the vulnerable component
is absent from the server: `(*ValidationHandler).Middleware`, `.ServeHTTP`,
`.Load` and `.validateRequest`, the package's `ValidateRequest` and
`NewValidator`, the legacy router's `NewRouter` and `(*Router).FindRoute`, and
`gorillamux.NewRouter`. The symbol table holds no symbol of any kind under
`kin-openapi/openapi3filter`, type descriptors included, and the binary holds
no string containing `openapi3filter`: the pclntab's file table names every
source file the compiler emitted code from, inlined bodies included, so an
inlined copy of any function of the package would have left its file path
behind. The controls hold: `openapi3.(*Schema).VisitJSON` and
`visitXOFOperations` are present in the server and the 2,688
`kin-openapi/openapi3.` strings are its function names; nothing of the kind
appears in the plugins, which link no kin-openapi package, as Trivy's report
also says. `UseEncodedPath` is present in the server because gorilla/mux is
linked for other purposes; the precondition it belongs to is moot without
the middleware in front of it.

Why the module is there: Grafana imports kin-openapi's `openapi3` for the
schema validation of alerting rules
(`apps/alerting/rules/pkg/app/validation/openapi.go` at v13.1.7,
`schema.VisitJSON`) and `openapi2conv` in a build script that is not
shipped; GitHub code search finds no import of `openapi3filter` anywhere in
grafana/grafana or the grafana organisation. The `routers/gorillamux` import
reaches the server through grafana-plugin-sdk-go's experimental e2e storage
package, whose router construction the linker dropped with everything else
of the package but its `init`.

**What govulncheck could measure: nothing.** The Go vulnerability database
has no report for this CVE: golang/vulndb#6769, filed 2026-10-15, is open and
triaged. govulncheck in binary mode applies reports, and the pull request
gate's run (Req 6.13) never fires for an inactive definition. The symbol
table is the instrument, as it was on 2026-10-13, and this time it is the
stronger case: not a present symbol with an absent caller, but an absent
package.

**The rungs.** Fix: closed. The image is frozen, and no 13.1 release carries
the fix anyway: Grafana 13.1.8, released 2026-10-13, still pins kin-openapi
v0.144.0 (its `release-13.1.8` go.mod), and only `main` has moved, to
v0.149.0. Avoid: nothing to drop; the schema package is in use. Not affected:
writable in the strong direction. The server is unstripped and every entry
point of the vulnerable component is absent, so Req 6.14 is satisfied, and
Req 6.15's structural basis holds: the image's entrypoint, `bin/grafana`,
never starts kin-openapi's request-validation middleware, which it does not
link. Transfer: nothing to wait for. Accept: not needed.

**Decision: not affected, vulnerable code not in the execute path, scoped to
the release** (owner's call, 2026-10-21).
`triage/vex/CVE-2026-100351.openvex.json`: product
`pkg:oci/grafana@13.1.7-alpine3.23`, subcomponent
`pkg:golang/github.com/getkin/kin-openapi`, a tag-scoped statement because
the claim rests on what this build links (the README's second row), and the
tag is the whole story for a frozen image. No version-independent note: a
future Grafana may import the middleware, and no future Grafana will be
built here.

**How it is proved.** The pull request gate builds nothing for this change:
grafana leaves the matrix as inactive (Req 1.15), so no scan on the pull
request applies the statement. Proved locally instead, before the merge: the
statement compiled for the supported digest with its three tags and both
platform manifests (`scripts/compile-vex.sh`, Req 6.28 to 6.30: six
statements compiled for grafana, eight products of other images dropped),
then `scripts/scan-image.sh` on the pulled linux/amd64 manifest with Trivy
0.72.0 and the vulnerability database of 2026-10-21 07:13Z. With the
compiled document CVE-2026-100351 is suppressed as `not_affected` from
`grafana.openvex.json` and the other four kin-openapi findings stay
reported; with an empty document directory all five are reported. The
statement suppresses what it claims and nothing else. The first rescan after
the merge then compiles it for the supported digest, scans the two platform
manifests, re-attests the changed document (Req 6.43), and closes #274 on
evidence with the `resolved:not_affected` grade (Req 6.53, 6.56); the status
issue's row moves from undecided to decided.

**The run.** Rescan run 39770244509, dispatched by the owner on 2026-10-22 at
11:23Z on cbf4042 and the first run carrying all three kin-openapi statements,
compiled eight statements for the supported digest, re-attested the document
on the index and both platform manifests, and closed the issue at 11:38Z with
`resolved:not_affected`, naming the statement as the covering artifact on both
manifests; the status row reads decided (not_affected). One detour on the way:
the #299 merge had closed the issue by itself on 2026-10-21 at 12:03Z, through
the word "closes" before the issue number in the pull request description,
which GitHub reads as a closing keyword, and the rescan of that day (run
39596066546, checked out before the merge) saw the finding still reported and
reopened it at 12:19Z (Req 6.57), as specified. Descriptions and commit
messages in this repository therefore never place a closing keyword before an
issue number: the rescan closes cve issues on evidence, and a merge must not
pre-empt it.

**The other four.** By their advisories, CVE-2026-100349 (#287, a nil-pointer
panic in `openapi3filter.ValidateResponse`) and CVE-2026-100353 (#276, three
nil-items panic paths in `openapi3filter`) sit in the absent package, and
CVE-2026-100352 (#275, NaN and Inf through the OAS 3.1 validation path) and
CVE-2026-100354 (#277, recursion on circular `allOf`, `anyOf` and `oneOf`
schemas) in the linked `openapi3` schema code, where `visitXOFOperations` is
present. Each gets its own measurement and its own decision, one at a time.

## 2026-10-21: not affected: CVE-2026-100353, the grafana server links no request decoder (#276)

*Image: grafana, inactive since 2026-10-19 and frozen at 13.1.7 (index
sha256:89c5680a868b, the digest the #256 base bump built on 2026-10-13). The
second of the five kin-openapi findings, decided on 2026-10-21, the owner's
call in chat on the evidence below, the same day as #274 and on the same
binaries: the published linux/amd64 manifest sha256:e4f626e9…, read in place
with the instrument of the entry above, `go version -m`, the pclntab read with
Go's own `debug/gosym`, `go tool nm` on the server and `strings`, extended by
one reader: the pclntab's file table, read directly with `debug/gosym` rather
than through `strings`. The script is
`triage/upstream/checks/grafana-kin-openapi-symbols.sh`, which now names the
functions of this finding and of #287 as well.*

**What the vulnerability is.** GHSA-vrcc-3ch7-hppw, CVSS 7.5 (network, low
attack complexity, no privileges, availability high), EPSS 0.34 percent (25th
percentile), not in CISA's KEV (catalogue 2026.10.16); CWE-476. The fix for
GHSA-p6wj-qrr4-pgh5 (CVE-2026-97394, 0.143.0) guarded three places where
kin-openapi's request decoder dereferences the `items` schema of an array
that OpenAPI 3.1 lets a document omit; this advisory names three it missed,
all in `openapi3filter`: a query parameter declared `type: array` without
`items`, the same inside a `deepObject` parameter, and a form-encoded body
whose array sits in an `allOf`, `anyOf` or `oneOf` sub-schema, which walks
past the guard the earlier fix put on top-level properties. The first and
third reach `(*urlValuesDecoder).parseArray`, the second `buildResObj`, both
in `openapi3filter/req_resp_decoder.go`, and both hand a nil schema to code
that dereferences it. One request from an unauthenticated client, against an
application that validates requests with `openapi3filter` against such a
document, panics the validating goroutine; under `net/http` the connection
drops, elsewhere the process. Fixed in 0.149.0 (commit 9814d1f of
2026-08-28): a nil guard in each of the two functions, six lines in one file.
Trivy names the module at v0.144.0 from the server's build info, fix version
0.149.0, on `usr/share/grafana/bin/grafana` and on no other binary.

**Where it sits, and where it does not.**

| Binary | Built with | kin-openapi | Functions (pclntab) | kin-openapi functions linked | kin-openapi files in the file table | `openapi3filter` | The seventeen named functions |
|---|---|---|---|---|---|---|---|
| `bin/grafana` (symbol table kept, 503,143 symbols) | go1.26.6 | v0.144.0 | 418,865 | 1,126 | 51 of 17,747: 50 under `openapi3/`, 1 under `routers/gorillamux/` | 0 functions, 0 symbols of any kind, 0 files, 0 strings | all absent |
| `plugins-bundled/elasticsearch/gpx_…` (v12.9.0, stripped) | go1.26.7 | none | 47,222 | 0 | 0 of 2,612 | 0 | all absent |
| `plugins-bundled/zipkin/gpx_…` (v12.4.8, stripped) | go1.26.7 | none | 36,903 | 0 | 0 of 2,087 | 0 | all absent |

The seventeen are the two fix sites, `(*urlValuesDecoder).parseArray` and
`buildResObj`; the function that dereferences,
`(*urlValuesDecoder).parseValue`; the chain that reaches them,
`(*urlValuesDecoder).DecodeArray`, `makeObject`, `decodeProperty`,
`decodeSchemaConstructs`, `UrlencodedBodyDecoder` and `MultipartBodyDecoder`;
the standalone `parseArray` and `decodeValue`; and the package's entry points
`ValidateParameter`, `ValidateRequestBody`, `ValidateRequest`,
`ValidateResponse`, `validateResponseHeader` and `RegisterBodyDecoder`. Each
is absent from every binary. The server's symbol table holds no symbol of any
kind under `kin-openapi/openapi3filter`, and its file table, the pclntab's
list of every source file the compiler emitted code from, inlined bodies
included, holds 17,747 files, of which 51 come from kin-openapi: 50 under
`openapi3/` and one under `routers/gorillamux/`, none under
`openapi3filter/`, `req_resp_decoder.go` included. The controls hold:
`openapi3.(*Schema).visitJSONArray`, the schema package's own walk over an
array value, `VisitJSON` and `Validate` are present in the server, as are its
50 `openapi3/` files; nothing of the kind appears in the plugins, which link no
kin-openapi package, as Trivy's report also says. On the file table: the entry
above read it through `strings`, whose patterns must be spelled as the table
spells a module's files, with the version in the path
(`kin-openapi@v0.144.0/openapi3/schema.go`); the direct reader counts the
same 50 and 1, and `strings` with the spelled-out path agrees.

Why the module is there is as recorded for #274: the schema validation of
alerting rules (`apps/alerting/rules/pkg/app/validation/openapi.go`,
`Schema.VisitJSON`), an `openapi2conv` build script that is not shipped, and
`routers/gorillamux` through grafana-plugin-sdk-go's experimental e2e storage
package, of which the linker kept the `init` alone. GitHub code search finds
no import of `openapi3filter` in grafana/grafana.

**What govulncheck could measure: nothing.** The Go vulnerability database
has no report for this CVE: golang/vulndb#6800, filed 2026-10-16, is open.
The pull request gate's run (Req 6.13) never fires for an inactive
definition. The symbol and file tables are the instrument, and the case is
the strong one again: an absent package.

**The rungs.** Fix: closed. The image is frozen, and no 13.1 release carries
the fix: Grafana 13.1.8 (2026-10-13) still pins kin-openapi v0.144.0, and
only `main` has moved, to v0.149.0. Avoid: nothing to drop; the schema
package is in use. Not affected: writable in the strong direction. Req 6.14
is satisfied because every named function is absent from the unstripped
server, and Req 6.15's structural basis holds: the image's entrypoint,
`bin/grafana`, never decodes a request through kin-openapi, which it does
not link. Transfer: nothing to wait for. Accept: not needed.

**Decision: not affected, vulnerable code not in the execute path, scoped to
the release** (owner's call, 2026-10-21).
`triage/vex/CVE-2026-100353.openvex.json`: product
`pkg:oci/grafana@13.1.7-alpine3.23`, subcomponent
`pkg:golang/github.com/getkin/kin-openapi`, tag-scoped for the reason given
for #274: the claim rests on what this build links, and the tag is the whole
story for a frozen image. No version-independent note.

**How it is proved.** As for #274: the gate builds nothing for an inactive
definition (Req 1.15), so the statement was proved locally before the merge,
compiled for the supported digest with its three tags and both platform
manifests (`scripts/compile-vex.sh`: seven statements compiled for grafana,
eight products of other images dropped), then `scripts/scan-image.sh` on the
pulled linux/amd64 manifest with Trivy 0.72.0 and the vulnerability database
of 2026-10-21 07:13Z. With the compiled document CVE-2026-100353 is
suppressed as `not_affected` from `grafana.openvex.json`, next to
CVE-2026-100351, and the other three kin-openapi findings stay reported; with
an empty document directory all five are reported. The first rescan after
the merge compiles it for the supported digest, re-attests the changed
document (Req 6.43), and closes #276 on evidence with the
`resolved:not_affected` grade (Req 6.53, 6.56).

**The run.** Rescan run 39770244509 (2026-10-22, 11:23Z, dispatched by the
owner on cbf4042) re-attested the document on the index and both platform
manifests and closed the issue at 11:38Z with `resolved:not_affected`, naming
the statement as the covering artifact on both manifests; the status row reads
decided (not_affected). The #301 merge had already closed the issue by itself
on 2026-10-21 at 21:20Z, through the word "closes" before the issue number in
the pull request description, a GitHub closing keyword that pre-empts the
rescan; the issue was reopened by hand on 2026-10-22 at 11:21Z, before the
run, so that the close carries the evidence and the graded label (Req 6.53,
6.56).

**The other three.** CVE-2026-100349 (#287) names `decodeValue`,
`validateResponseHeader` and `ValidateResponse`, three of the seventeen
counted above, in the same absent package: its measurement is this one, its
decision is still its own. CVE-2026-100352 (#275) and CVE-2026-100354 (#277)
sit in the linked `openapi3` schema code, where `visitXOFOperations` and
`visitJSONArray` are present, and each needs a finer read.

## 2026-10-21: not affected: CVE-2026-100349, the grafana server links no response validator (#287)

*Image: grafana, inactive since 2026-10-19 and frozen at 13.1.7 (index
sha256:89c5680a868b, the digest the #256 base bump built on 2026-10-13). The
third of the five kin-openapi findings, decided on 2026-10-21, the owner's
call in chat on the evidence below, the same day as #274 and #276 and on the
same binaries: the published linux/amd64 manifest sha256:e4f626e9…, read in
place with the instrument of the two entries above, `go version -m`, the
pclntab's function table and file table read with Go's own `debug/gosym`,
`go tool nm` on the server and `strings`, re-run for this entry rather than
quoted from the entry above. The script is
`triage/upstream/checks/grafana-kin-openapi-symbols.sh`, which has named this
finding's three functions since the entry above and now reads its source
file as well.*

**What the vulnerability is.** GHSA-74vm-87hj-r66f, CVSS 4.0 8.2 (network,
low attack complexity, attack requirements present, no privileges, no user
interaction, availability high; the advisory carries no 3.1 score), EPSS
0.37 percent (30th percentile), not in CISA's KEV (the rescan's check of
2026-10-18); CWE-476. An OpenAPI document may declare a response header with
`content` instead of `schema`, and `openapi3` accepts such a document as
valid. When `openapi3filter.ValidateResponse` validates a response of that
operation, `validateResponseHeader` hands the header's nil schema to
`decodeValue` in `openapi3filter/req_resp_decoder.go`, which dereferences
it. The response need not carry the header: declaring it is enough, so every
validated response of that operation panics the validating goroutine, under
`net/http` the connection, elsewhere the process. The document is the
trigger, not a request, which is why the advisory scores attack requirements
as present: an application validating responses against a document it did
not write crosses a trust boundary, one validating its own crashes on the
first call of the route. The same class as GHSA-jpcw-4wr7-c3vq, which
covered the request-parameter side in 0.144.0. Fixed in 0.146.0 (commit
f5441d67 of 2026-08-03, released the same day): a four-line nil guard at
the top of `decodeValue`. Trivy names the module at v0.144.0 from the
server's build info, fix version 0.146.0, on `usr/share/grafana/bin/grafana`
and on no other binary.

**Where it sits, and where it does not.** The panic path is three functions
of `openapi3filter`: `ValidateResponse`, `validateResponseHeader` and
`decodeValue`, the first two in `validate_response.go`, the third in
`req_resp_decoder.go`. All three are among the seventeen the entry above
counted; the measurement was re-run for this entry, with the two source
files read from the file table as well.

| Binary | Built with | kin-openapi | Functions (pclntab) | kin-openapi functions linked | kin-openapi files in the file table | `openapi3filter` | `ValidateResponse`, `validateResponseHeader`, `decodeValue` | `validate_response.go`, `req_resp_decoder.go` |
|---|---|---|---|---|---|---|---|---|
| `bin/grafana` (symbol table kept, 503,143 symbols) | go1.26.6 | v0.144.0 | 418,865 | 1,126 | 51 of 17,747: 50 under `openapi3/`, 1 under `routers/gorillamux/` | 0 functions, 0 symbols of any kind, 0 files, 0 strings | absent | absent |
| `plugins-bundled/elasticsearch/gpx_…` (v12.9.0, stripped) | go1.26.7 | none | 47,222 | 0 | 0 of 2,612 | 0 | absent | absent |
| `plugins-bundled/zipkin/gpx_…` (v12.4.8, stripped) | go1.26.7 | none | 36,903 | 0 | 0 of 2,087 | 0 | absent | absent |

The numbers are those of the entry above, measured again: the server links
1,126 functions of kin-openapi, 1,125 of them in the `openapi3` schema
package and one, the `init`, in `routers/gorillamux`; its file table holds
51 kin-openapi files, 50 under `openapi3/` and one under
`routers/gorillamux/`, none under `openapi3filter/`; its symbol table holds
no symbol of any kind under `kin-openapi/openapi3filter`; `strings` finds
neither the package name nor either file name. The controls hold:
`openapi3.(*Schema).VisitJSON`, `visitXOFOperations`, `visitJSONArray` and
`Validate` are present in the server, as are its 50 `openapi3/` files. The
plugins link no kin-openapi package, as Trivy's report also says.

Why the module is there is as recorded for #274: the schema validation of
alerting rules (`apps/alerting/rules/pkg/app/validation/openapi.go`,
`Schema.VisitJSON`), which validates a JSON value against a schema and is
not response validation; an `openapi2conv` build script that is not
shipped; and `routers/gorillamux` through grafana-plugin-sdk-go's
experimental e2e storage package, of which the linker kept the `init`
alone. GitHub code search finds no import of `openapi3filter` in
grafana/grafana. Nothing in the image validates an HTTP response against an
OpenAPI document, its own or another's, so the document that triggers the
panic has nothing to reach.

**What govulncheck could measure: nothing.** The Go vulnerability database
has no report for this CVE: golang/vulndb#6804, filed 2026-10-16, is open,
with two change lists of 2026-10-19 and 2026-10-21 mentioning it, so a
report is in review and not yet published. The pull request gate's run
(Req 6.13) never fires for an inactive definition. The symbol and file
tables are the instrument, and the case is the strong one for the third
time: an absent package.

**The rungs.** Fix: closed. The image is frozen, and no 13.1 release carries
the fix: Grafana 13.1.8 (2026-10-13) still pins kin-openapi v0.144.0, no
13.1 release has followed it, and only `main` has moved, to v0.149.0. Avoid:
nothing to drop; the schema package is in use. Not affected: writable in the
strong direction. Req 6.14 is satisfied because every named function is
absent from the unstripped server, and Req 6.15's structural basis holds:
the image's entrypoint, `bin/grafana`, never validates a response through
kin-openapi, which it does not link. Transfer: nothing to wait for. Accept:
not needed.

**Decision: not affected, vulnerable code not in the execute path, scoped to
the release** (owner's call, 2026-10-21).
`triage/vex/CVE-2026-100349.openvex.json`: product
`pkg:oci/grafana@13.1.7-alpine3.23`, subcomponent
`pkg:golang/github.com/getkin/kin-openapi`, tag-scoped for the reason given
for #274: the claim rests on what this build links, and the tag is the whole
story for a frozen image. No version-independent note.

**How it is proved.** As for #274 and #276: the gate builds nothing for an
inactive definition (Req 1.15), so the statement was proved locally before
the merge, compiled for the supported digest with its three tags and both
platform manifests (`scripts/compile-vex.sh`: eight statements compiled for
grafana, eight products of other images dropped), then
`scripts/scan-image.sh` on the pulled linux/amd64 manifest with Trivy 0.72.0
and the vulnerability database of 2026-10-21 07:13Z. With the compiled
document CVE-2026-100349 is suppressed as `not_affected` from
`grafana.openvex.json`, next to CVE-2026-100351 and CVE-2026-100353, and the
two remaining kin-openapi findings stay reported; with an empty document
directory all five are reported. The first rescan after the merge compiles
it for the supported digest, re-attests the changed document (Req 6.43), and
closes #287 on evidence with the `resolved:not_affected` grade (Req 6.53,
6.56).

**The run.** Rescan run 39770244509 (2026-10-22, 11:23Z, dispatched by the
owner on cbf4042) re-attested the document on the index and both platform
manifests and closed the issue at 11:38Z with `resolved:not_affected`, naming
the statement as the covering artifact on both manifests; the status row reads
decided (not_affected). The #302 merge had already closed the issue by itself
at 07:45Z the same day, through the word "closes" before the issue number in
the pull request description, a GitHub closing keyword that pre-empts the
rescan; the issue was reopened by hand at 11:21Z, before the run, so that the
close carries the evidence and the graded label (Req 6.53, 6.56).

**The other two.** CVE-2026-100352 (#275) and CVE-2026-100354 (#277) sit in
the linked `openapi3` schema code, where `visitXOFOperations` and
`visitJSONArray` are present, and each needs a finer read than an absent
package allows.

## 2026-10-23: not affected: CVE-2026-100352, the grafana server never selects kin-openapi's JSON Schema 2020-12 validator (#275)

*Image: grafana, inactive since 2026-10-19 and frozen at 13.1.7 (index
sha256:89c5680a868b, the digest the #256 base bump built on 2026-10-13). The
fourth of the five kin-openapi findings and the first that sits in code the
server does link, the `openapi3` schema package the three entries of
2026-10-21 counted at 1,125 functions. The evidence pass is of 2026-10-22,
the owner's call in chat on it, recorded here on 2026-10-23 together with
#277 below, one pull request for both. The binaries are the ones of the
entries above, the published linux/amd64 manifest sha256:e4f626e9…, read in
place: `go version -m`, the pclntab readers and `go tool nm` of
`triage/upstream/checks/grafana-kin-openapi-symbols.sh`, which now names this
finding's functions and files and the jsonschema module, and a new
instrument, a disassembly of the whole server binary with `go tool objdump`
that lists every direct call into kin-openapi and into the validator it
hands values to: `triage/upstream/checks/grafana-kin-openapi-callers.sh`.*

**What the vulnerability is.** GHSA-rj39-cv6w-8wv7, CVSS 3.1 7.5 (network,
low complexity, no privileges, no user interaction, availability high), EPSS
0.43 percent (36th percentile), not in CISA's KEV (the rescan's check of
2026-10-22); CWE-754. kin-openapi's built-in schema visitor, `visitJSON`,
refuses a NaN or infinite float before it compares anything
(`ErrSchemaInputNaN`, `ErrSchemaInputInf`, `openapi3/schema.go:1960`). Its
JSON Schema 2020-12 path does not: when `Schema.VisitJSON` is called with the
`EnableJSONSchema2020()` option, the option the library documents for
OpenAPI 3.1 documents, it dispatches to `useJSONSchema2020`
(`schema.go:1945`), which builds a validator from
`santhosh-tekuri/jsonschema/v6` and hands the value straight through
(`schema_jsonschema_validator.go:204`). In jsonschema v6.0.2, `numValidate`
turns the number into a `*big.Rat` by parsing its printed form; for NaN and
Inf the parse fails silently and returns nil, which `Rat.Cmp` dereferences.
The advisory's delivery is a YAML request body (`.nan`, `.inf`, `-.inf`,
which `openapi3filter.YamlBodyDecoder` turns into the Go values) validated
against a 3.1 document with a numeric constraint; the panic takes the
validating goroutine, under `net/http` the connection. Fixed in 0.148.0
(commit 4487f198 of 2026-08-27, released the same day) by bumping
jsonschema to v6.0.3, which guards the parse. Trivy names the module at
v0.144.0 from the server's build info, fix version 0.148.0, on
`usr/share/grafana/bin/grafana` and on no other binary.

**Where it sits.** Unlike the three findings above, the functions are in
the binary: `useJSONSchema2020`, `newJSONSchemaValidator`,
`(*jsonSchemaValidator).validate` and jsonschema's `numValidate` are present
(one symbol each in `go tool nm`), and so is jsonschema/v6 v6.0.2 itself
(284 functions, 383 symbols). Presence is not reachability, and Req 6.14
speaks of a reachable symbol; the measurement for this entry is who calls
them. `go tool objdump` on the whole server (418,865 functions in the
pclntab; every call the linker resolved by name, 33 sites among the named
functions) gives the call graph below; `go tool nm` adds the closures, which
a disassembly cannot attribute because an option is passed as a function
value.

| Measured on `bin/grafana` | Result |
|---|---|
| Direct calls into kin-openapi from outside the module | 2: `grafana-app-sdk/app.(*VersionSchema).AsOpenAPI3` to `openapi3.(*Loader).LoadFromData`; `grafana/apps/alerting/rules/pkg/app/validation.(*SpecValidator).ValidateOpenAPISpec` to `openapi3.(*Schema).VisitJSON` |
| Direct calls into jsonschema/v6 from outside jsonschema and kin-openapi | 0 |
| Callers of `useJSONSchema2020` | 1, `VisitJSON`, under the setting |
| Callers of `newJSONSchemaValidator` and of `(*jsonSchemaValidator).validate` | 1 each, `useJSONSchema2020` |
| Callers of jsonschema's `numValidate` | 1, jsonschema's own `(*validator).validate` |
| Callers of `validateExampleValue` | 3, all in kin-openapi: `(*MediaType).Validate`, `(*Parameter).Validate`, `(*Schema).validate` |
| Callers of `(*T).Validate`, the spec-time entry point | 0 |
| Closures that can set the 2020-12 setting (`EnableJSONSchema2020`, named after the caller it was inlined into) | 1: `validateExampleValue.EnableJSONSchema2020.func4` |
| Option closures handed to `VisitJSON` by callers outside kin-openapi | 1: `ValidateOpenAPISpec.MultiErrors.func1` |
| Method values taken of any `openapi3` `Validate` method (`-fm` wrappers) | 0 |
| `openapi3filter`, `YamlBodyDecoder` | 0 symbols (the entries above) |

**What the calls mean.** The two entry points are the whole of grafana's
use of kin-openapi. The first loads grafana's own kind schema at app start:
`AsOpenAPI3` (grafana-app-sdk v0.56.2, `app/manifest.go:693-711`) wraps the
generated schemas in a document declared `openapi: 3.0.0` and hands it to
`LoadFromData`, which parses and resolves references and validates nothing;
no function in the binary calls `(*T).Validate`. The second runs on every
create and update of an alerting rule, recording rule and rule sequence
(`validation/builder.go:50-58` and `app.go:76-94` at v13.1.7; the app
installs whenever unified alerting is on, `register.go:56`):
`ValidateOpenAPISpec` (`validation/openapi.go:38-50`) marshals the typed
spec with `encoding/json`, decodes it back into `any`, and calls
`VisitJSON(decoded, openapi3.MultiErrors())`. That option list is the
measurement. `VisitJSON` takes the 2020-12 path only when
`settings.useJSONSchema2020` is true (`schema.go:1945`); the field is set
only by the closure `EnableJSONSchema2020` returns
(`schema_validation_settings.go:158-160`); the symbol table holds one copy
of that closure in the whole binary, the one the compiler inlined into
kin-openapi's own `validateExampleValue` (`example_validation.go:15-16`),
which validates a document's examples under `(*T).Validate`, which nothing
calls; and the grafana caller's only option closure is `MultiErrors`. So
every value the server ever validates goes through `visitJSON`, the visitor
with the guard, and the validator that panics is never constructed. Source
agrees with the binary: at v0.144.0 the option is passed in four places,
example validation and three sites in `openapi3filter`'s request and
response validators (`validate_request.go:248` and `:360`,
`validate_response.go:77`), the package the entries above showed absent.

**The second wall.** The guarded visitor never sees the values the advisory
needs either. A rule arrives as JSON through the Kubernetes-style API (the
binary holds no YAML body decoder), is decoded into the typed spec, and is
marshalled and decoded once more before the visit. `encoding/json` refuses
NaN and both infinities on the way out (`json: unsupported value: NaN`) and
refuses the literals and an overflowing number on the way in (`cannot
unmarshal number 1e400 into Go value of type float64`), measured with a
four-line program on go1.25.7. The numeric constraints that would make the
2020-12 validator compare at all exist in two places of the generated
schemas, AlertRule's `PanelRef.panelID` (`minimum: 0`, exclusive) and
`spec.missingSeriesEvalsToResolve` (`minimum: 0`), and neither can be handed
a NaN.

**What govulncheck could measure: nothing.** The Go vulnerability database
has no report for this CVE: golang/vulndb#6795, filed 2026-10-15, is open.
The pull request gate's run (Req 6.13) never fires for an inactive
definition. The disassembly and the symbol table are the instrument, and the
basis is structural (Req 6.15): the image's entrypoint, `bin/grafana`,
constructs the JSON Schema 2020-12 validator in no code path it starts.

**The rungs.** Fix: closed. The image is frozen, and no 13.1 release carries
the fix: Grafana 13.1.8 (2026-10-13) still pins kin-openapi v0.144.0, no
13.1 release has followed it, and only `main` has moved, to v0.149.0. Avoid:
nothing to drop; the schema package is in use. Not affected: writable. Req
6.14 is satisfied because govulncheck reports no symbol for this CVE,
reachable or not, and the structural basis of Req 6.15 is the one stated.
Transfer: nothing to wait for. Accept: not needed.

**Decision: not affected, vulnerable code not in the execute path, scoped to
the release** (owner's call in chat on the evidence pass of 2026-10-22).
`triage/vex/CVE-2026-100352.openvex.json`: product
`pkg:oci/grafana@13.1.7-alpine3.23`, subcomponent
`pkg:golang/github.com/getkin/kin-openapi`, tag-scoped for the reason given
for #274: the claim rests on what this build links and calls, and the tag is
the whole story for a frozen image. No version-independent note: a future
Grafana may validate a 3.1 document with examples, and no future Grafana
will be built here.

**How it is proved.** As for the three entries above: the gate builds
nothing for an inactive definition (Req 1.15), so the statement was proved
locally before the merge, compiled for the supported digest with its three
tags and both platform manifests (`scripts/compile-vex.sh`: ten statements
compiled for grafana, eight products of other images dropped), then
`scripts/scan-image.sh` on the pulled linux/amd64 manifest with Trivy 0.72.0
and the vulnerability database of 2026-10-21 07:13Z. With the compiled
document all five kin-openapi findings are suppressed as `not_affected` from
`grafana.openvex.json` and one finding stays reported, CVE-2026-111943
(#300, Go's `crypto/x509`); with an empty document directory all five are
reported, eight in all. The first rescan after the merge compiles it for the
supported digest, re-attests the changed document (Req 6.43), and gives
#275 its close on evidence with the `resolved:not_affected` grade (Req 6.53,
6.56); the run is recorded here when it does.

**The run.** Rescan run 39959263177, dispatched by the owner on 2026-10-23 at
13:12Z on db23c0f, the squash of #307 and the first run carrying this
statement: the day's scheduled run (39948543838, 11:47Z) had checked out
203c230, before the merge. It attested today's reports and re-attested
grafana's document at 13:24Z (the document on the index digest, read back
from the registry at 13:40Z, carries nineteen statements with the timestamp
2026-10-23, CVE-2026-100352 among them) and closed the issue at 13:24Z with
`resolved:not_affected`, naming this statement, applied from
`grafana.openvex.json` with the justification
`vulnerable_code_not_in_execute_path`, as the covering artifact on both
platform manifests, e4f626e99435 and f26298a61be4; the status issue and the
page followed at 13:33Z, the row reading decided (not_affected), decided
2026-10-23, "not affected: vulnerable code not in execute path". No detour
this time: the squash message and the pull request description carried no
closing keyword before an issue number, and the issue stayed open from the
merge at 13:08Z until the evidence closed it (Req 6.53, 6.54).

## 2026-10-23: not affected: CVE-2026-100354, the grafana server validates only its own acyclic schema (#277)

*Image: grafana, frozen at 13.1.7 as above. The last of the five kin-openapi
findings, the same evidence pass, binaries and instruments as the entry
above, the same pull request. This one needs the finest read of the five:
the vulnerable functions are present, and they run.*

**What the vulnerability is.** GHSA-g8cf-rcjf-c8cf, CVSS 3.1 7.5 (the same
vector), EPSS 0.44 percent (37th percentile), not in CISA's KEV (the
rescan's check of 2026-10-22); CWE-674. kin-openapi's spec-time `Validate`
walks a schema with a stack and tolerates a combinator chain that refers
back to itself (`schema.go:1396`), and its loader resolves circular
references on purpose, to allow recursive data. The runtime visitor has no
such check: `visitJSON` calls `visitXOFOperations` (`schema.go:2189`), which
calls `visitJSON` on every member of `oneOf`, `anyOf` and `allOf` (five call
sites in the disassembly), and on a schema whose chain comes back to itself
the recursion is unbounded on the first value visited. In Go that is a fatal
stack overflow, not a panic: `recover` does not catch it, `net/http`'s
per-connection recovery does not help, and the process ends with every
goroutine in it. The advisory names a second site of the same shape,
`decodeValue` in `openapi3filter`'s request decoder, with `parseValue` and
`buildResObj`. Fixed in 0.149.0 (commit 9245cef6 of 2026-08-28, released
the same day): a set of visited schemas carried through `visitJSON`, and a
guarded `decodeValue`. Trivy names the module at v0.144.0, fix version
0.149.0, on `bin/grafana` alone.

**Where it sits, and what runs.** `visitJSON` and `visitXOFOperations` are
present (the controls of the three entries above); `decodeValue` and the
rest of `openapi3filter` are absent (0 functions, 0 symbols, 0 files, 0
strings, the entries of 2026-10-21). The visitor runs: `ValidateOpenAPISpec`
calls `VisitJSON` on every create and update of the three alerting kinds,
and `VisitJSON` without the 2020-12 option is `visitJSON`. What decides this
finding is not whether the function runs but what it is given. The
recursion needs a schema with a cycle; the value is only walked along it.

**Whose schema.** There is one schema, and the server builds it from itself.
The three kind schemas are generated into the binary at build time
(`apps/alerting/rules/pkg/apis/manifestdata/alerting_manifest.go` at
v13.1.7, three embedded OpenAPI component sets), and a parse of them (a walk
over the JSON, counting keys, and a depth-first search over the component
reference graph) gives:

| Kind | Components | `$ref` | `oneOf` | `allOf` | `anyOf` | `not` | Reference cycles |
|---|---|---|---|---|---|---|---|
| AlertRule | 20 | 26 | 1 (`NotificationSettings`: `SimplifiedRouting` or `NamedRoutingTree`, no discriminator) | 0 | 0 | 1 (a pattern under `PromDuration`) | none |
| RecordingRule | 13 | 14 | 0 | 0 | 0 | 1 (the same) | none |
| RuleSequence | 8 | 8 | 0 | 0 | 0 | 1 (the same) | none |

The visitor never sees even these as written. `NewSpecValidator`
(`validation/openapi.go:23-36`) takes the kind's `spec` schema from
`AsCRDOpenAPI3`, which loads the document (`AsOpenAPI3`, the entry above)
and rebuilds the kind's schema with `GetCRDOpenAPISchema` and
`resolveSchema` (grafana-app-sdk v0.56.2, `app/manifest.go:1069-1320`):
every `$ref` is replaced by a fresh copy of the referenced schema, with a
visited set per branch, and a reference met again on the same branch becomes
`{type: object, x-kubernetes-preserve-unknown-fields: true}` (lines
1109-1115); properties, items and additional properties are resolved the
same way into new nodes; and the combinators are rewritten for Kubernetes'
structural schemas, each `allOf` and `anyOf` member into a leaf of required
fields while its fields merge into the parent (1236-1251, 1306-1320), each
`oneOf` member into a leaf of required fields with a `not` of `anyOf`
required leaves excluding the other branches, or the `oneOf` cleared when no
branch has required fields (1255-1300). The output is a tree built by a
terminating recursion out of new nodes: no node points back to an ancestor,
and no combinator member is anything but a leaf. The visitor is handed
`crd.Properties["spec"]` of that tree, once, for the life of the process.

**What a client controls.** The value: a rule's `spec`, as JSON through the
Kubernetes-style API, marshalled and decoded again before the visit (the
entry above). `VisitJSON` takes the value as data and the schema as its
receiver; no field of the value selects, loads or alters a schema (the one
`oneOf` has no discriminator, so `resolveDiscriminatorRef` reads nothing
from the value, `schema.go:2149-2152`). A request can make the visitor
reject a rule; it cannot make the visitor recurse through a chain the server
did not build, and the only recursion the generated schemas allow is the
data's own (an `ExpressionMap` of `Expression`s, arrays of
`TimeIntervalRef`), which the JSON decoder bounds first. No other code in
the binary gives kin-openapi a schema: the two entry points of the table
above are all there is, and nothing links the request decoder.

**What govulncheck could measure: nothing.** golang/vulndb#6785, filed
2026-10-15, is open, so there is no report; the gate never runs for an
inactive definition.

**The rungs.** Fix: closed, as above (13.1.8 pins v0.144.0; v0.149.0 is on
`main` only). Avoid: the schema validation of rules is the feature; nothing
to drop. Not affected: writable, but not in the direction of the entries
above. The vulnerable code is in the execute path, it runs on every rule
write, so `vulnerable_code_not_in_execute_path` would be false, and Req 6.14
and 6.15 do not apply. OpenVEX's
`vulnerable_code_cannot_be_controlled_by_adversary` says what the evidence
says: the input that triggers the flaw is the schema, the schema is the
server's own, built from a generated document by a resolver that produces an
acyclic tree, and no request reaches it. The first use of this justification
in the repo; the rescan's status renderer prints any justification as words
(`triage/rescan/decision.go:92`), so the status row reads "not affected:
vulnerable code cannot be controlled by adversary", and Trivy applied the
statement in the local proof below. Transfer: nothing to wait for. Accept:
not needed.

**Decision: not affected, vulnerable code cannot be controlled by an
adversary, scoped to the release** (owner's call in chat on the evidence
pass of 2026-10-22). `triage/vex/CVE-2026-100354.openvex.json`: product
`pkg:oci/grafana@13.1.7-alpine3.23`, subcomponent
`pkg:golang/github.com/getkin/kin-openapi`, tag-scoped: the claim rests on
the schemas this build generates and the resolver and callers this build
links. No version-independent note: a future Grafana may hand kin-openapi a
schema from elsewhere, and no future Grafana will be built here.

**How it is proved.** The same local run as the entry above (ten statements
compiled, Trivy 0.72.0, the database of 2026-10-21 07:13Z): with the
compiled document CVE-2026-100354 is suppressed as `not_affected` with this
justification, next to the four others, and CVE-2026-111943 alone stays
reported; with an empty document directory all five are reported. The first
rescan after the merge re-attests the changed document and gives #277 its
close on evidence with the `resolved:not_affected` grade (Req 6.43, 6.53,
6.56); the run is recorded here when it does. With it the five kin-openapi findings of
the frozen image are decided, and #300 is the image's last open finding.

**The run.** The same run, 39959263177 (2026-10-23, 13:12Z, dispatched by the
owner on db23c0f after the day's scheduled run had checked out 203c230),
re-attested the document at 13:24Z with this statement in it (nineteen
statements, timestamp 2026-10-23, read back from the index digest at 13:40Z)
and closed the issue at 13:24Z with `resolved:not_affected`, naming the
statement, applied from `grafana.openvex.json` with the justification
`vulnerable_code_cannot_be_controlled_by_adversary`, as the covering
artifact on both platform manifests. The closing comment quotes the
justification as written; the status row of 13:33Z renders it as words,
"not affected: vulnerable code cannot be controlled by adversary", the
generic rendering noted above, so the first use of this justification
reached the published status without a code change. With it the five
kin-openapi findings of the frozen image are closed on evidence: #274, #276
and #287 by run 39770244509 on 2026-10-22, #275 and #277 by this run.

## 2026-10-23: the KEV feed outage drill, both arms fail closed by name (task 16.8)

*Image: drill-app. Task 16.8, conductor track `kev-drill-input_20261023`:
#308 amended Req 7.7 and 7.10 so that a dispatch input is a declared value
the policy lint holds, #310 added the `drill` input to `rescan.yml`'s
dispatch with its substitutes under `triage.drills` in
`catalogue-policy.yaml`. Both arms fetch CISA's KEV catalogue before
evaluating the exception tiers and fail closed when the fetch fails (Req
6.59, 6.60); neither outage branch had run live (ledger rows 6.59 and 6.60,
status `drill 16.8`). The drill induces the outage without a second code
path: the declared `kev-outage` address,
`https://kev-feed.invalid/known_exploited_vulnerabilities.json`, under a
top-level domain RFC 2606 reserves so that no resolver answers, substituted
for the feed, on the gate by a branch and on the rescan by the input.*

**Why an address under `.invalid`.** The outage has to be certain and
harmless: `curl` fails at name resolution (exit 6, could not resolve host)
before any connection, every time, on every runner, with nothing reached;
the error line each arm prints carries the address, so a resolver that
answered would show as a fetch that succeeded. The alternative, a reachable
address serving an error, exercises the same `curl -f` branch but depends
on a server.

**The gate's half (2026-10-23, 20:45 to 20:51Z).** A pull request carries
no dispatch inputs, so the gate's half is a branch: drill #313, a draft
never merged, commit 1b221d8 on 9e62294, sets `triage.kev_feed` to that
address and adds one comment line to `image/drill-app/image.yaml`, the
smallest change that puts drill-app in the build matrix (the matrix
derives from changed paths under `image/`, so the policy edit alone builds
nothing; the active-set lint admits a change to an active definition).
Build run 40021724071: the affected-definitions job named drill-app; the
matrix job built the image (20:49:01Z), gave it a local identity, scanned
it (Trivy, 20:49:11Z) and ran the portability and reachability steps as on
every drill-app pull request; then step 19, `exception tiers against KEV
(Req 6.50)`, read the policy file's feed through `scripts/triage-policy.sh
. kev-feed` and failed in one second (20:50:48Z to 20:50:49Z) with
`drill-app: the CISA KEV feed
(https://kev-feed.invalid/known_exploited_vulnerabilities.json) is
unavailable, so the exception tiers cannot be evaluated; this pull request
fails closed (Req 6.59)`. Behind it the scan gate and every release step
were skipped (only the scan-report upload, which runs regardless, ran), and
the build gate went red at 20:51:05Z (job 120647720657): the tiers were not
evaluated against an empty KEV set, which would have handed every exploited
finding the widest tier. Validate run 40021724024 green, the fourteen lints
over the drilled state; e2e run 40021724069 with nothing to test; the chart
run 40021724130 green. The owner's update of the branch with main at
20:46:07Z (merge commit 8127bd0, the branch's tip since) ran the gate a
second time: build run 40021765400 red at the same step at 20:51:14Z (job
120647848842) with the same line, the build gate red at 20:51:31Z;
validate run 40021765479, e2e run 40021765460 and chart run 40021765405
green. Rehearsed in the worktree before the push with the
step's shell verbatim: `curl: (6) Could not resolve host: kev-feed.invalid`,
the same line, exit 1. Ledger row 6.59 flips to exercised on this.

**The rescan's half (2026-10-23, 21:04 to 21:24Z).** The owner dispatched
`rescan.yml` on main (2f53e31) with `drill: kev-outage` at 21:04:35Z, after
the day's scheduled run (39948543838, 11:47Z) and the 13:12Z dispatch
(39959263177, the close on evidence of #275 and #277): run 40024066594, job
120655680352. Up to the invariants step the run did what every dispatch
does: enumerated the catalogue, scanned every platform manifest (21:07:50Z),
read the lifecycle's evidence and decided on it, attested today's reports
with replace (21:08:11Z to 21:17:40Z, the day's reports replaced by the
day's reports) and applied the lifecycle on the attested evidence
(21:17:42Z; #300, the one open cve issue, untouched). Then the invariants
step (21:19:07Z) read the substitute through `scripts/triage-policy.sh .
drill-feed kev-outage`, annotated `drill kev-outage: the KEV feed is
substituted with https://kev-feed.invalid/known_exploited_vulnerabilities.json
for this run only (task 16.8); the scheduled run reads the declared feed`,
fetched it through the same `curl` the declared feed goes through and
failed with `the substituted KEV feed (drill kev-outage)
(https://kev-feed.invalid/known_exploited_vulnerabilities.json) is
unavailable: the exception tiers were not evaluated today, which is a
failure of this run, not a pass (Req 6.60)`; the
step's other checks passed in the same step, its log (read by the owner on
the run page; the API exposes the annotations only) showing
`check-visibility: 7 repositories and 47 tags all answer an unauthenticated
request (Req 2.21)` and `verify-catalogue: 26 admitted, control rejected;
the admission policy holds over every tag-referenced digest (Req 2.24)`
before the warning, the fetch's own `curl: (6) Could not resolve host:
kev-feed.invalid` between the warning and the error line, and
`check-attestation-count: every one of 75 tag-referenced digest(s) and
platform manifest(s) carries exactly one OpenVEX attestation` and
`revocations: 0 recorded, 0 referenced by a catalogue tag` after it, exit 1
after one minute and twenty-five seconds. The authenticity, portability, smoke-test and expiry steps
ran under `always()` (21:19:16Z to 21:23:59Z). The refusals by name: the
enrich step (21:23:59Z), `enrich: no KEV catalogue on disk (the invariants
step reports why); today's issue set and status are not built (Req 6.60)`
(the step's log, read by the owner, shows `DRILL: kev-outage` in its env),
behind it the dedup, the issue set, the Grype second opinion and the
new-CVE filing skipped; the status step (21:24:00Z), `catalogue status:
/home/runner/work/dhc-pipeline/dhc-pipeline/rescan-out/kev.json is missing
(the step that produces it reports why); no status published today (Req
6.46, 6.47)`, behind it the status publish, the status upload and the page
upload skipped, and the page job skipped for want of a generation date.
The posture invariants, the summary and the artifact upload ran; the
summary's first line is the workflow's `- drill: kev-outage (the KEV feed
substituted with https://kev-feed.invalid/known_exploited_vulnerabilities.json,
this run only; task 16.8)` (the job summary is not readable through the API
from the devcontainer; the warning annotation above carries the same input
and address). The status issue (#151) kept its 13:33Z body and the page its
13:33Z data. The run red by the invariants step and by each refusal, as Req
6.60 asks: a feed outage is a non-evaluation, never an evaluation against an
empty KEV set. Ledger row 6.60 flips to exercised on this.

**The recovery (2026-10-24, 11:12 to 11:30Z).** The next scheduled run,
40088952931 on main at ec0692e, carried no input, so `DRILL` fell back to
`none` (the workflow's `inputs.drill || 'none'`): the invariants step read
the declared feed and passed (11:21:32Z to 11:23:05Z, no drill annotation
on the job), the enrich step ran (11:29:20Z), the issue set was built with
nothing new to file (the Grype second opinion and the filing step skipped;
#300 the one open cve issue, untouched), the status was published to #151
at 11:29:24Z (`generated: 2026-10-24`, 42 findings, 1 undecided within its
ceiling, 12 decided, 29 fixed), the status data and the page were uploaded,
and the page job deployed the page at 11:29:47Z with its check that the
served data is this run's (Req 6.62) green. The summary's drill line on a
schedule event is the workflow's `- drill: none` (the summary is not
readable through the API from the devcontainer; the absence of the
substitution's warning annotation on the job says the same). The status
issue and the page carried the 13:33Z data of 2026-10-23 until 11:29Z, as
the task text and the track's risk table say. Task 16.8 is done on these
runs; 16.3, the KEV-listed finding under an exception, is next, and its
drill reads the `kev-synthetic` value this track shipped.

## 2026-10-25: the drill's HIGH listed as exploited by the synthetic feed, the standing exception refused in both arms, re-decided to one day (task 16.3)

*Image: drill-app. Task 16.3, conductor track `kev-ceiling_20261024` (#318,
squash a764a23). Every exception's span, decision date to expiry, is held to
a tier: the severity's ceiling (90 days for a HIGH, 30 for a CRITICAL), or
14 days once CISA lists the finding as exploited (`triage.kev_ceiling`;
Req 6.50 on the gate, 6.51 on the rescan). Neither refusal had run live
(ledger rows 6.50 and 6.51, status `drill 16.3`): no exception had exceeded
its tier in any run. The drill's object is the standing exception on
CVE-2025-30204 (golang-jwt `ParseUnverified`, decided 2026-10-18, expiring
2027-01-16: 90 days, the HIGH tier in full). CISA does not list that CVE, so
the drill reads the `kev-synthetic` feed task 16.8 shipped,
`triage/drills/kev-synthetic.json`, one entry naming it: the case of a list
that grew after the decision was made. Nothing in the code changed, and no
exception was written over its tier.*

**The rescan's half (2026-10-25, 11:13 to 11:31Z).** The owner
dispatched `rescan.yml` on main at a764a23 with `drill: kev-synthetic` (run
40187973579, job 121152713348) at 11:13:41Z, before the day's scheduled run,
which had not started by then, nor by the time this was written (11:33Z). As on every dispatch, the run
attested the day's reports and re-attested the OpenVEX documents where they
changed (register row M17). The invariants step fetched the synthetic feed
in place of CISA's, the warning annotation naming the substitution, and
failed at 11:24:49Z (step 14) with `check-exceptions:
triage/accepted-risk/drill-app.yaml: CVE-2025-30204 runs 90 days from
2026-10-18 to 2027-01-16, over its 14-day ceiling (listed in CISA KEV)` and
`check-exceptions: 1 exception(s) over their tier across 11 checked (Req
6.50/6.51)`, every unexpired exception of the catalogue evaluated: the
standing exception, 76 days over the KEV tier, refused by name as a failure
of the run (Req 6.51). The KEV set stayed on disk, so the
steps behind it ran: the enrich step (11:30:32Z), the issue set with nothing to file (the filing step skipped), the status published to
#151 at 11:30:36Z with CVE-2025-30204's KEV column reading yes for the
first time (Req 6.46), the page deployed at 11:31:01Z. The status and
the page read yes on a drill definition until the next scheduled run reads
CISA's feed again.

**The gate's half (2026-10-25, 11:15 to 11:20Z).** Pull request #319's first
commit (ee48046) pointed `triage.kev_feed` at the synthetic feed's address
and put drill-app in the build matrix with one comment line, the shape of
#313 (task 16.8). Build run 40188092683 built and scanned drill-app as on
any drill-app pull request (the Trivy scan green at 11:18:29Z), then step 19
`exception tiers against KEV (Req 6.50)` failed at 11:20:15Z (job
121153084106) with the same breach line and `1 exception(s) over their tier across 2
checked`, the one image's file, the build gate red at 11:20:30Z;
validate run 40188092562, the render gate and the e2e gate green. Both
lines leave with the second commit; neither merges.

### RE-DECIDED: the drill's HIGH against the KEV ceiling, one day

The finding, the module and the reachability are those of 2026-10-18, and
so is the treatment: accept, for the reasons argued there (the finding is
the drill's reason to exist, its removal is drill 16.6, not_affected is
forbidden by govulncheck's reach into `ParseUnverified`, transfer has no
owner but the owner). What changes is the clock: under a feed that lists
the CVE, the entry's span must sit within the 14-day KEV tier, and the
standing 90 days do not.

**Decision: accept, re-decided** (owner's call, 2026-10-25; `decided_at`
2026-10-25, `expired_at` 2026-10-26: one day). The owner's call of
2026-10-24 was a short expiry with no waiting on an arbitrary timeline; of
2026-10-25, shorter than the four days task 16.4's text had drafted. One
day, not zero: Trivy drops an ignore entry once its `expired_at`, read as
midnight UTC of that date, is before now (`pkg/result/ignore.go`, `Prune`,
the same line in the pinned 0.75.0), while `lint-accepted-risk.sh` and
`compile-vex.sh` keep an entry live through its expiry day; with zero days
the pass dispatch of this drill would also have counted the finding again.
The lint passes with its one warning, `expires in 1 days (2026-10-26)`.

**Exit condition:** the lapse is intended. From 00:00 UTC on 2026-10-26
Trivy counts the finding again; from 2026-10-27 the compiler can name the
lapse in an `under_investigation` statement with the first-seen time
carried; drill 16.4 observes both days, its track opened today. Drill 16.6
fixes the finding. The pass of this re-decided entry against the synthetic
feed, on a second dispatch after this merges, is recorded below once
observed, never predicted.

**Merged, 2026-10-25 11:55:37Z** (#319, squash 714614f): the re-decided
entry, the LOG entry above, the ledger rows; neither drill line. The second
commit's build had named drill-app again, by design: `build.yml` rebuilds the
image a changed exception file names so that the gate re-runs against the
exception (run 40189524943, green: the Trivy scan, govulncheck, the tier step
against CISA's feed and the scan gate), which the track's plan had not
expected; main's push build reads image paths alone and built nothing.

**Between the two dispatches (11:42 to 11:58Z).** The day's scheduled run,
40189980851, started at 11:42:20Z on a764a23, before the merge, so it read
the standing entry and CISA's feed: the invariants step green at 11:51:28Z
with nothing to report, no expiry warning, the status published to #151 at
11:57:19Z with CVE-2025-30204's KEV column back to no, the page at
11:57:43Z. The first run to read the re-decided entry on the declared feed is
the scheduled run of 2026-10-26, drill 16.4's.

**The pass (2026-10-25, 11:59 to 12:15Z).** The owner's second dispatch
with `drill: kev-synthetic` (run 40191153604, main at 714614f, job
121162258991): the invariants step evaluated the re-decided entry against the
synthetic feed and passed at 12:08:34Z, `check-exceptions: ok drill-app
CVE-2025-30204: 1 days within the 14-day ceiling (listed in CISA KEV)`
being the line the step prints on a pass, the step green with no breach annotation; the expiries step warned `CVE-2025-30204 expires in 1 days
(2026-10-26)` (the warning annotation on `triage/accepted-risk/drill-app.yaml` at 12:14:20Z), 16.4's first observation; the status published
to #151 at 12:14:23Z with KEV yes once more and "accepted risk until
2026-10-26"; the page at 12:14:46Z; the run green. Task 16.3 is done on
these runs: both arms refused the standing exception by name on the feed
that listed the finding, and passed the re-decided one. Drill 16.4 follows
from midnight UTC.

## 2026-10-26: deliberate violations, every lint refuses by name (task 16.15)

*Task 16.15, conductor track `deliberate-violations_20261025` (#322, squash
c1c8aa6, the owner's call of 2026-10-25). Fifteen conventions of this
repository were held by lints and gates that had refused nothing live;
their ledger rows read `drill 16.15`. The drill pull request #323, a draft
from its opening and never merged, supplied the violations one per commit,
each commit undoing the previous one so that each run refused one thing and
named it; every refusal below was read from the commit's own check runs and
annotations, by its sha. Nothing in the code changed.*

**The first pass, and the nine commits done again.** Twenty-one commits
went up between 13:23 and 13:37Z. Commit 10 added `.trivyignore.yaml` and
the drill's own reset script, which checked the base's files out and
cleaned untracked ones, never removed a file the base lacked: commits 11 to
21 all carried the ignore file, and since the accepted-risk lint runs early
in the validate job, which stops at its first failing step, commits 13 to 17
were refused for the stray file and not for their own violation, while 18
to 21 were refused twice. Commits 13 to 21 were pushed again with the script
corrected, between 13:45 and 13:51Z, each carrying its one violation; the
first attempt's commits stay on the branch. Thirty commits in all.

**What else was red.** The expiry of the drill's HIGH exception fell on the
same day (task 16.4, the entry expired on 2026-10-26), so every commit that
built drill-app (the definition commits 1 to 3 and the exception-file
commits 9, 11 and 12: runs 40330192598, 40330289146, 40330379034,
40330936640, 40331123924, 40331224851) was also red at the build's scan gate
with `drill-app: 1 uncovered within the aperture (0 CRITICAL, 1 HIGH; Req
6.1): CVE-2025-30204 ... An expired exception counts as uncovered.`: task
16.4's gate half, seen six more times. The chart commits ran the e2e suite,
red where the chart could not be proved or installed. None of this touched
the refusals below.

**Two refusals name their cause in the log only.** The revocation record's
schema check (yamale) and the chart gate (kyverno apply) fail the step and
print what they refused to the job's log, with no GitHub annotation; the
step's failure is the evidence here, the lines are the owner's to read.
Noted as a follow-up in `tasks/todo.md`. The pin lint, as its scope note
says, does not read a chart's split `repository`/`tag`/`digest` values; the
Renovate manager fixture step does, and refused the two malformed chart
pins beside the gate.

| # | Row | Commit | The violation | Refused by | The line |
| --- | --- | --- | --- | --- | --- |
| 1 | 1.6 | b15aa92 | the builder image reference without its digest | validate 40330192365, the pin lint | `floating reference 'dhi.io/golang:1.27.3-alpine3.23-dev'`, pin by digest |
| 2 | 1.11 | e078b9c | the source's authenticity class none | validate 40330289237, the pin lint | `class 'none' declares that nothing verifies this upstream ... (Req 1.11)` |
| 3 | 1.12 | 3c27e14 | a dhi.io package repository ending in /community | validate 40330379027, the pin lint | `... is not of shape dhi.io/apk/<distro>/<release>/main or dhi.io/deb/<distro>/main (Req 1.12)` |
| 4 | 1.18 | cd8e24f | valkey-compat out of the active set, valkey in | validate 40330473877, the active-set lint | `the active set splits the source repository group 'valkey-io/valkey' ... (Req 1.18)`, and the published group |
| 5 | 4.8 | 1e1e194 | the compat decision's review-by in the past | validate 40330564462, the compat lint | `review_by 2026-10-01 has passed (today 2026-10-26); record a dated re-decision ... or retire the variant` |
| 6 | 5.8 | d2a9f65 | the hardened-app chart's probe line removed | validate 40330655430, the proof lint | `active definition 'hardened-app' is deployed by chart/hardened-app/ which declares no functional probe (probe:) ... (Req 5.8)` |
| 7 | 5.10 | 12e31ad | a proof of kind smoke for hardened-app | validate 40330753122, the proof lint | `proofs entry 'hardened-app' declares kind 'smoke', which this catalogue does not implement; the kinds are chart and none ... (Req 5.10)` |
| 8 | 5.10 | 4eccb73 | a none proof for hardened-app | validate 40330843742, the proof lint | `declares a proof of kind none, but chart/hardened-app/ deploys it; one proof per definition ... (Req 5.10)` |
| 9 | 6.11 | b240b45 | the CRITICAL entry without its owner | validate 40330936728, the accepted-risk lint | `risk treatment (Req 6.11): CVE-2017-20146 is missing 'owner' (who carries this risk)` |
| 10 | 6.12 | 7f9db6c | `.trivyignore.yaml` at the root | validate 40331030587, the accepted-risk lint | `risk treatment (Req 6.12): Trivy ignore file outside triage/accepted-risk/` |
| 11 | 6.25 | cab977d | the CRITICAL entry duplicated | validate 40331124035, the accepted-risk lint | `risk treatment (Req 6.25): CVE-2017-20146 claims path 'usr/local/bin/drill-app', already claimed by entry 0` (and the stray file's line) |
| 12 | 9.18 | 587a249 | the CRITICAL's ref to no heading | validate 40331224975, the accepted-risk lint | `LOG anchor (Req 9.18): CVE-2017-20146 ref 'LOG.md#a-heading-the-log-does-not-carry-drill-1615' resolves to no heading in triage/LOG.md` (and the stray file's line) |
| 13 | 6.19 | 294c615 | the kin-openapi subcomponent with a version | validate 40333428725, the VEX product lint | `subcomponent 'pkg:golang/github.com/getkin/kin-openapi@v0.133.0' carries version 'v0.133.0'` |
| 14 | 6.39 | 198ccf6 | the statement's status under_investigation | validate 40333530634, the VEX product lint | `records status 'under_investigation': a source statement may only record not_affected or fixed` |
| 15 | 9.18 | 6d83606 | the statement's citation to no heading | validate 40333622975, the citations step | `statement CVE-2026-100351 (not_affected) cites 'triage/LOG.md#a-heading-the-log-does-not-carry-drill-1615.', which resolves to no heading` |
| 16 | 7.9 | f070e46 | `policies/restrict-registries.yaml` edited by hand | validate 40333716431, the renderings drift check | `policies/restrict-registries.yaml differs from its rendered form (Req 7.9); edit catalogue-policy.yaml and re-run scripts/render-verification.sh` |
| 17 | 7.10 | dff743a | renovate.yml's cron changed, the policy not | validate 40333818457, the workflow policy lint | `renovate.yml: schedule trigger '5 */4 * * *' differs from declared '0 */4 * * *' (Req 7.10)` |
| 18 | 9.6 | e966e58 | a withdrawn record without its advisory | validate 40333916232, step 5 `revocation record (Req 9.6)` | the step red; yamale's naming of the entry and the field in the log |
| 19 | 4.2, 4.6 | 06e5fad | the chart image pinned by tag alone | chart gate 40334006281 (require-image-digest); validate 40334006248, the Renovate fixture step | kyverno's lines in the log; the fixture step red |
| 20 | 4.3, 4.6 | 87c5e88 | the pod's runAsNonRoot false | chart gate 40334100881 (require-nonroot) | kyverno's line in the log; validate green |
| 21 | 4.2, 4.6 | f1523da | the chart image from docker.io | chart gate 40334200141 (restrict-registries); validate 40334200122, the Renovate fixture step | kyverno's lines in the log; the fixture step red |

Rows 1.6, 1.11, 1.12, 1.18, 4.8, 5.8, 5.10, 6.11, 6.12, 6.19, 6.25, 6.39,
7.10, 9.6 and 9.18 are `exercised` on these runs; 4.2, 4.3, 4.6 and 7.9
carry the re-observation. The pull request is closed with a comment once
this evidence merges. Task 16.15 is done.

## 2026-10-26: the drill's exception expires, the lapse on every plane (task 16.4)

*Image: drill-app. Task 16.4, conductor track `exception-lapse_20261025`
(#321, squash a9c55bb). Task 16.3 re-decided the drill's HIGH,
CVE-2025-30204 (golang-jwt `ParseUnverified`), to one day: decided
2026-10-25, expiring 2026-10-26 (#319, squash 714614f). This entry records
what every plane did with that lapse on the two days it took, each number
read as it happened: the expiry warning (Req 6.10), Trivy counting the
finding again from midnight UTC of the expiry day while this repository's
lint and compiler kept the entry live through that day (the two clocks
named in the entry of 2026-10-25), the gate refusing the finding as
uncovered (Req 6.9, first time live), and on the day after, the lint's `is
in the past`, the page's lapsed entry and the compiler's note naming the
lapse (Req 6.41, first time live). Nothing in the code changed and no new
decision was written; the lapsed entry leaves the exception file with this
entry so that the finding stays undecided for task 16.5.*

**Day one, Trivy's (2026-10-26, 13:14 to 13:37Z).** The scheduled run
40328859055 (main at a9c55bb, job 121592610063) scanned every supported
digest with the exception file as Trivy's ignorefile. The entry's
`expired_at`, 2026-10-26, read as midnight UTC of that date, was before now,
so Trivy dropped it (`pkg/result/ignore.go`, `Prune`, the pinned 0.75.0)
and the scan step reported CVE-2025-30204 on drill-app again (13:18:38Z).
The re-attestation step (Req 6.42, 6.43; 13:28:41Z) recompiled drill-app's
document from the day's reports. For the compiler the entry was still live
(`expired` means an expiry before today, and today was the expiry day), but
the report listed the finding plain, so the statement moved from `affected`
to `under_investigation` with the compiler's generic note, `uncovered at
release time in this digest's attested release-time scan report
(drill-app__0c61394798b5__linux-amd64.json); awaiting a triage decision`,
not the lapse note; its `timestamp` was carried from the previous document,
2026-10-23T14:12:33Z, the digest's release time (run 39966412724, the dhi.io
build-layer update #266; Req 6.38, 6.40), and `last_updated` became
2026-10-26T13:16:34Z, the day's report time. The statement set differed, so
the document was re-attested on the index and on both platform manifests
(read back from the registry with `cosign download attestation` on
2026-10-27, the index `drill-app@sha256:0c61394798b5...`, the manifests
`c45b99fafdfe...` and `e93535e38c24...`). The expiries step (13:37:06Z)
warned `risk treatment: CVE-2025-30204 expires in 0 days (2026-10-26)` on
`triage/accepted-risk/drill-app.yaml` line 29, the second observation of
Req 6.10 after 16.3's `1 days`. The issue step filed #325, `CVE-2025-30204:
HIGH in drill-app@sha256`, at 13:37:10Z (Req 6.3): no cve issue had existed,
the finding having arrived decided with task 16.2. The status, published to
#151 at 13:37:14Z, read the re-attested document and showed the finding
undecided, `drill-app | CVE-2025-30204 | HIGH | no | undecided | 2026-10-18 |
n/a | 8 / 90 | undecided, awaiting a triage decision`, with `undecided: 2
(oldest 8 days); decided: 11`; the first-seen date is the status's own,
carried from its previous data across the definition's digests, where the
document's `timestamp` is this digest's. The page (job 121604249709,
13:37:41Z) listed the entry on drill-app's card as lapsing, `exception
lapsing: CVE-2025-30204 expires in 0 days (2026-10-26)`, next to `undecided
1, over ceiling 0`, read on the published page that day.

**The gate (2026-10-26, 13:24 to 13:29Z).** Pull request #324 (commit
2fac0b0) put drill-app in the build matrix with one comment line in
`image/drill-app/image.yaml`, the shape of #313 and #319's first commit, and
was opened as a draft, meant to be red and never merged. Build run
40330306412 (job 121597733598) built and scanned drill-app with the same
ignorefile: the Trivy scan green at 13:27:44Z (a scan step fails on nothing),
govulncheck green, step 19 `exception tiers against KEV (Req 6.50)` green
at 13:29:25Z (the entry's one-day span within its tier), then step 20, the
scan gate, failed at 13:29:25Z with `drill-app: 1 uncovered within the
aperture (0 CRITICAL, 1 HIGH; Req 6.1): CVE-2025-30204 (HIGH
github.com/golang-jwt/jwt/v5@v5.2.1, fixed: 5.2.2). Four ways out,
strongest first: avoid (drop the component) · fix (version bump, Req 6.5) ·
prove it does not apply (OpenVEX in triage/vex/, Req 6.4) · accept or
transfer for a bounded time (triage/accepted-risk/drill-app.yaml, Req 6.7).
An expired exception counts as uncovered.`, the build gate red; validate run
40330306541 green, the lint's warning at 0 days. Req 6.9, first time live.
The same line refused the six drill-app builds of #323 that day (task 16.15,
runs 40330192598, 40330289146, 40330379034, 40330936640, 40331123924 and
40331224851): every commit of that drill that put drill-app in the matrix
was uncovered on this expired entry, alongside the violation it carried.

**Day two, the lint's and the compiler's (2026-10-27, 12:22 to 12:42Z).**
The scheduled run 40503212074 (main at 037b428, job 122185846822) started
at 12:22:14Z, six hours after its cron (GitHub's delay: the four runs before
it had started between 11:12 and 13:14Z). The scan reported the finding as
on day one (12:25:18Z). The re-attestation step (12:34:03Z) recompiled the
document with the entry now expired for the compiler too: the statement
stayed `under_investigation`, its `timestamp` unchanged at
2026-10-23T14:12:33Z, and its note became `accepted-risk exception (accept,
decided 2026-10-25) expired on 2026-10-26; the finding is still listed in
this digest's attested scan report
(drill-app__0c61394798b5__linux-amd64.json); awaiting a new decision;
tracked in https://github.com/mm-weber/dhc-pipeline/issues/325`, the issue
link appended because #325 existed by then (day one had filed it after its
own re-attestation step, which runs before the issue step). The statement
set differed by that note alone, so the document was re-attested with
`last_updated` 2026-10-27T12:23:46Z, the day's report time, on the index
and on both platform manifests, one OpenVEX attestation on each (read back
with `cosign download attestation` at 12:44Z): Req 6.41 first time live,
and Req 6.43 on a change of note alone. The expiries step (12:41:25Z)
reported `risk treatment (Req 6.11): CVE-2025-30204 expired_at 2026-10-26
is in the past` as an error annotation on line 29 of the exception file;
the step hands the lint's lines to the summary and the page and does not
fail the run, which stayed green. The status published to #151 at
12:41:31Z counted on: `drill-app | CVE-2025-30204 | HIGH | no | undecided |
2026-10-18 | n/a | 9 / 90 | undecided, awaiting a triage decision
(dhc-pipeline#325)`, `undecided: 2 (over ceiling: 0, oldest: 9 days)`. The
page (job 122194608341, 12:42:09Z) listed the entry on drill-app's card as
lapsed, `exception lapsed: CVE-2025-30204 expired_at 2026-10-26 is in the
past`, above the finding's row with its issue, read on the published page
at 12:44Z.

**The gate on day two (12:01 to 12:07Z).** The drill pull request's commit
was rebased onto main that morning (83b8fb3) so that validation ran on the
lapse day: validate run 40500526721 failed at step 9, the accepted-risk lint
(12:01:36Z), with the same `is in the past` line on line 29, Req 6.11
refusing a past expiry on a pull request for the first time; build run
40500526734 (job 122176816331) built and scanned drill-app again, the tier
step green, the scan gate red at 12:07:10Z with the line of day one. Until
the entry leaves, every pull request's validation is red on it, by design;
the Renovate pull requests of the evening before (#327, #328) had run on
day one and did not meet it.

**The entry leaves (2026-10-27).** The evidence pull request (#329)
removes CVE-2025-30204's entry from `triage/accepted-risk/drill-app.yaml`
and leaves the CRITICAL's (CVE-2017-20146, expiring 2026-11-17); the file's
header says where the HIGH went. No new decision is written: re-deciding
would end task 16.5's premise, an undecided finding carried past a lowered
ceiling. `lint-accepted-risk.sh` is green with no warning, ten refs resolve
where eleven did, validation is green again on every pull request. The next
scheduled run reads no expired entry for the finding, so its recompile
carries the generic uncovered note once more, the statement's timestamp
unchanged; the status keeps the finding undecided with its first-seen date
of 2026-10-18 and counts its age on. The drill pull request #324 is closed
unmerged with a comment after this merges; issue #325 stays open as the
finding's issue until drill 16.6 fixes it or the owner decides it.

**The gate on this pull request (2026-10-27, 12:48 to 12:51Z).** A changed
exception file names its image in the build matrix so that the gate
re-runs against it (Req 6.9), and this pull request changes drill-app's:
build run 40506336848 (job 122196521100) built and scanned drill-app with the
entry gone and its scan gate failed at 12:51:09Z with the line of day one,
the finding uncovered by nothing now rather than by an expired entry;
validate run 40506336887 green, the lint satisfied. The track's spec had not
seen this: an undecided HIGH in the drill definition refuses every pull
request that builds the definition, this one included, until drill 16.6
fixes the finding or the owner decides it, and a pull request that only
removes the lapsed entry cannot be green at that gate without deciding the
finding, which would end task 16.5's premise. The owner merges this pull
request over the red gate by the ruleset's bypass for the repository's
admin role, the one bypass this program has needed, recorded here as the
reason; the pull requests that follow (16.5's track and its policy change)
build nothing and stay green.

**The two clocks, as observed.** The entry of 2026-10-25 named the
difference from the sources; these two days showed it on every plane. On
the expiry day Trivy no longer honoured the entry: the gate refused the
finding as uncovered, the scan counted it, the document was re-attested
`under_investigation`, the status showed it undecided and an issue was
filed, while the lint warned `0 days`, the page said lapsing, the tier check
still evaluated the entry and the compiler's note did not name the lapse.
On the day after, the lint said `is in the past`, the page said lapsed and
the note named the lapse. Every component did what its own source says;
what differs is the meaning of `expired_at`: for Trivy the first day
without coverage, for this repository's three scripts the last day with it.
The difference is recorded here as the documented one, not as a defect row:
the day it costs is one of mismatched notes, not of coverage, since the
gate and the scan read Trivy's clock, the stricter. A follow-up item in
`tasks/todo.md` leaves the owner the call between aligning the three
scripts to Trivy's reading and documenting the expiry day as the first day
without coverage.
