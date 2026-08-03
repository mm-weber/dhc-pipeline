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
