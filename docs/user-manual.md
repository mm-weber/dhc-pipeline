# dhc-pipeline — User Manual

How to consume, operate, and extend this catalogue: declarative image
definitions built by the real `dhi.io/build` frontend, upstream Helm charts
hardened through overrides, automated upstream tracking, Go integration tests
on real Kubernetes, and CVE triage recorded as portable OpenVEX.

This manual integrates the deeper documents — [CONVENTIONS.md](CONVENTIONS.md),
[concepts.md](concepts.md), [operating-loop.md](operating-loop.md), the ADRs in
[decisions/](decisions/), and [triage/README.md](../triage/README.md) — it does
not replace them. Requirement references like `(Req 6.20)` point at
[`.specs/dhc-catalogue-mvp/requirements.md`](../.specs/dhc-catalogue-mvp/requirements.md),
so every rule here traces to the criterion that demands it. Where this manual
and the repository disagree, the repository is right — and the fix is a PR to
whichever of the two drifted.

**Contents** ·
[Orientation](#orientation) ·
[Part I: Consuming](#part-i-consuming-the-catalogue) ·
[Part II: The pipeline](#part-ii-the-pipeline) ·
[Part III: Operating](#part-iii-operating-the-catalogue) ·
[Part IV: Extending](#part-iv-extending-the-catalogue) ·
[Part V: Local development and setup](#part-v-local-development-and-setup) ·
[Part VI: Reference](#part-vi-reference)

## Orientation

### What this is

dhc-pipeline publishes hardened, non-root, digest-pinned container images to
`ghcr.io/mm-weber/dhc`, plus Helm chart adaptations that deploy them under a
restricted Pod Security profile. Every image is built from a reviewable YAML
definition, signed with cosign (keyless, GitHub OIDC), and shipped with an
SPDX SBOM, BuildKit provenance, and OpenVEX vulnerability statements attached
as attestations.

The repository is also the *operation* of that catalogue. Two unattended loops
keep it honest: self-hosted Renovate opens version-bump pull requests every few
hours, and a daily rescan of the published images files a GitHub issue for
every new HIGH or CRITICAL CVE. A pull-request scan gate refuses to merge
anything carrying an unexcused finding, and the only ways to excuse one are
recorded, reviewable decisions — an OpenVEX statement or a time-boxed risk
exception.

### Who this is for

| You are…            | You want to…                                              | Start at |
|---------------------|-----------------------------------------------------------|----------|
| A consumer          | pull an image, verify it, deploy a chart                  | [Part I](#part-i-consuming-the-catalogue) |
| The maintainer      | handle bump PRs, triage findings, keep the loops green    | [Part III](#part-iii-operating-the-catalogue), with [Part II](#part-ii-the-pipeline) as the reference under it |
| A contributor       | add a definition, adapt a chart, extend a policy          | [Part IV](#part-iv-extending-the-catalogue) |
| Setting up from zero| wire secrets, branch protection, local tooling            | [Part V](#part-v-local-development-and-setup) |

### Repository map

| Path                          | What lives there |
|-------------------------------|------------------|
| `image/<name>/image.yaml`     | One definition per emitted image, native DHI syntax: hardened-app, cert-manager-{controller, webhook, cainjector}, grafana, valkey, valkey-compat |
| `chart/<name>/`               | Chart adaptations: `chart.yaml` pin manifest + `config/values-hardened.yaml` overlay + README; `hardened-app/` is the one owned chart (real `Chart.yaml`) |
| `test/`                       | Go module: Ginkgo v2 + Gomega + e2e-framework suite (`e2e/`), reusable assertions (`checks/`), install/harness helpers, Renovate manager fixtures (`renovate/`) |
| `triage/`                     | The CVE lane: `vex/` (OpenVEX source), `accepted-risk/` (time-boxed exceptions), `LOG.md` (every decision), `upstream/` (drafts for other trackers), `rescan/` (the unit-tested issue-filing Go tool) |
| `policies/`                   | Kyverno policies: digest pins, allowed registry, non-root — plus `tests/` fixtures |
| `scripts/`                    | Tested glue; every `x.sh` has an `x_test.sh` |
| `.github/workflows/`          | The six workflows + `requirements-ci.txt` (hash-pinned Python deps) |
| `.specs/dhc-catalogue-mvp/`   | EARS requirements, design, task ledger |
| `docs/`                       | This manual, conventions, concepts, ADRs, operating-loop evidence |
| `renovate.json5`              | All upstream tracking: custom regex managers only |

### The two loops

Every change — human-authored or machine-opened — enters as a pull request and
passes the same four gates. Merging to main triggers the release path. Two
crons then feed published state back into new pull requests, and the triage
directory sits in the middle: every scan, PR-side or scheduled, consumes it.

```
change (human or machine) ─► pull request
  ─► gates: validate · build + scan gate · chart policy · e2e on kind
  ─► merge ─► release: push by digest (amd64 + arm64) · scan every platform manifest · sign · SBOMs · VEX · tag last
              · VEX attest (compiled per digest)
  ─► published: ghcr.io/mm-weber/dhc

published ─► daily rescan (06:17 UTC, VEX- and exception-aware)
  ─► one issue per new HIGH/CRITICAL (severity · EPSS · KEV)
  ─► triage decision (VEX / exception / fix bump) ─► pull request  ↻

upstream release ─► Renovate cron (every 4h)
  ─► bump PR (postUpgradeTask recomputes derived fields) ─► pull request  ↻

triage/ (vex/ + accepted-risk/) is consumed by every scan, PR-side and
scheduled.
```

Ground rule: GitHub Actions is the **authoritative** environment for builds,
kind clusters, registry pushes, and scans (Req 8.1). Local runs are for
iteration speed; CI results are what count. The devcontainer is
egress-allowlisted, so anything needing `dhi.io` or arbitrary registries
delegates to CI or the operator host (Req 8.2).

## Part I: Consuming the catalogue

### Images and naming

All images publish under `ghcr.io/mm-weber/dhc`. References follow the DHI
naming convention (Req 2.3):

```
ghcr.io/mm-weber/dhc/<name>:<semver>-<os><osver>[-<variant>]
# e.g.  ghcr.io/mm-weber/dhc/grafana:13.1.3-alpine3.23
```

Each release also carries **major** and **major.minor** alias tags
(`13-alpine3.23`, `13.1-alpine3.23`) so consumers pick their update
granularity. An upstream out-of-band security build (`13.0.1+security-01`)
becomes `13.0.1_security-01-alpine3.23` — `+` is illegal in an OCI tag, so the
build separator is spelled `_`.

| Repository                                                                | Contents                                            | Archetype           |
|---------------------------------------------------------------------------|-----------------------------------------------------|---------------------|
| `…/hardened-app`                                                          | The supply-chain lab's Go HTTP service              | compile-from-source |
| `…/cert-manager-controller`, `…/cert-manager-webhook`, `…/cert-manager-cainjector` | cert-manager, three images from one pinned monorepo source | compile-from-source |
| `…/grafana`                                                               | Grafana OSS, official release tarball repackaged    | tarball-repackage   |
| `…/valkey`                                                                | Valkey server (also receives the `-compat` variant tags) | compile-from-source |

The variant taxonomy:

| Variant       | What it is                                                            | Deploy it? |
|---------------|-----------------------------------------------------------------------|------------|
| *(none)* runtime | Binary + deps + certs, non-root 65532, **no shell, no package manager** | Yes — the default |
| `-dev`        | Build-stage toolchain, root permitted                                 | Never — it is the `uses:` stage inside builds |
| `-compat`     | Runtime plus a minimal shell userland (busybox)                       | Only where a documented decision requires it (Req 4.5) |

The rule, from [concepts.md](concepts.md): *deploy the least capable variant
that works, and write down why when you can't.* The one existing compat build
is `valkey:<ver>-alpine3.23-compat`, required because the upstream valkey
chart runs an unconditional `/bin/sh` init container; the cost is documented
in [chart/valkey/README.md](../chart/valkey/README.md).

Platform note: releases are currently **linux/amd64 only** (Req 2.1). arm64
was deliberately withdrawn on 2026-08-04 because nothing scanned it; it
returns only once the rescan covers it (spec task 8.3), per the rule that no
platform is published unscanned (Req 2.6).

### Verify what you pull

Every published image is signed recursively (the index and each platform
manifest) and carries attestations bound to its digests: on every platform
manifest an SPDX SBOM, a CycloneDX SBOM, the release-time scan report and
the OpenVEX document; on the index each platform's SPDX SBOM and the same
OpenVEX document (Req 2.9, 6.4; the index is what a tag resolves to, so
admission is checked there). BuildKit SLSA provenance is attached by the
build itself (Req 2.2). All signing is cosign keyless via GitHub OIDC —
verification pins the workflow identity, not a key:

<!-- render-verification:begin -->
```sh
# rendered by scripts/render-verification.sh from catalogue-policy.yaml; do not edit
REF=ghcr.io/mm-weber/dhc/IMAGE:TAG        # any catalogue tag, e.g. grafana:13.1.3-alpine3.23
ISSUER='--certificate-oidc-issuer https://token.actions.githubusercontent.com'
BUILD='--certificate-identity https://github.com/mm-weber/dhc-pipeline/.github/workflows/build.yml@refs/heads/main'
RESCAN='--certificate-identity https://github.com/mm-weber/dhc-pipeline/.github/workflows/rescan.yml@refs/heads/main'

cosign verify $ISSUER $BUILD "$REF"                          # signature: the release workflow on main
cosign verify-attestation $ISSUER $BUILD --type spdxjson "$REF" \
  | jq -r '.payload | @base64d | fromjson | .predicate'      # SBOM
cosign verify-attestation $ISSUER $BUILD --type openvex "$REF" 2>/dev/null \
  || cosign verify-attestation $ISSUER $RESCAN --type openvex "$REF" \
  | jq -r '.payload | @base64d | fromjson | .predicate'      # VEX: releaser or re-attester
# BuildKit provenance is attached at build time and is not verified by the
# policy above (Req 2.25); inspect it with the buildx CLI plugin:
docker buildx imagetools inspect "$REF" --format '{{ json .Provenance }}'
```
<!-- render-verification:end -->

What each artifact gives you:

- **Signature** — the image was pushed by this repository's release workflow,
  not by anyone holding a long-lived key.
- **SBOM** (Syft; SPDX on the index and each platform manifest, CycloneDX on
  each platform manifest) — a signed inventory of contents, joinable to
  advisory databases via purls. The CycloneDX copy carries the apk pull
  checksums the nightly publish-on-change comparison reads (Req 2.15).
- **Scan report** (Trivy, cosign `vuln` predicate) — the release-time scan of
  exactly this platform manifest, suppressed findings included, the input the
  VEX document's `under_investigation` and `affected` statements derive from
  (Req 2.12, 6.38).
- **Provenance** (BuildKit, `mode=max`) — the builder, the invocation, and
  every input with its *resolved* digest. This is what connects the SBOM's
  claims to verifiable materials (see [concepts.md](concepts.md), "The trust
  chain").
- **OpenVEX** — the maintainer's applicability decisions for known CVEs,
  *compiled for exactly this digest* (Req 6.34), so your own scanner can
  consume it directly (e.g. `trivy image --vex <predicate>.json "$REF"`).

### Deploy the charts

Adapted charts consume the upstream chart **unmodified** at a pinned version
and apply one overlay file (Req 4.1). Rendering locally is one command per
chart — these are the pins at the time of writing; `chart/<name>/chart.yaml`
is authoritative:

```sh
# cert-manager — upstream chart v1.21.0 (jetstack)
helm template dhc-cert-manager cert-manager \
  --repo https://charts.jetstack.io --version v1.21.0 \
  -f chart/cert-manager/config/values-hardened.yaml

# grafana — upstream chart 10.5.15 (grafana community)
helm template dhc-grafana grafana \
  --repo https://grafana.github.io/helm-charts --version 10.5.15 \
  -f chart/grafana/config/values-hardened.yaml

# valkey — upstream chart 0.11.0 (valkey project's own)
helm template dhc-valkey valkey \
  --repo https://valkey-io.github.io/valkey-helm --version 0.11.0 \
  -f chart/valkey/config/values-hardened.yaml

# hardened-app — owned chart, hardening baked into defaults
helm template hardened-app chart/hardened-app
```

Every overlay does the same three things: swap images to **digest-pinned**
catalogue builds (Req 4.2), enforce the restricted profile — `runAsNonRoot`,
UID/GID 65532, read-only root filesystem, no privilege escalation, drop-ALL
capabilities, seccomp `RuntimeDefault` (Req 4.3) — and mount `emptyDir`
volumes at each path the workload genuinely writes (Req 4.4). Every deviation
from upstream defaults is tabled in that chart's README with its reason
(Req 4.7).

Per-chart notes worth knowing before you deploy:

- **cert-manager** — `startupapicheck` is disabled: it would run a Job from an
  image this catalogue does not build, which the registry policy forbids.
- **grafana** — the upstream chart lags the app (newest chart targets 12.x);
  the templates are version-stable, so the overlay deploys the hardened 13.x
  build on them. The digest rides on the `tag` value; the chart's bare-hex
  `sha:` field is deliberately unused.
- **valkey** — deploys the `-compat` variant (see the taxonomy above);
  persistence is off by default and stated explicitly — `/data` is an
  emptyDir until you opt into a PVC.
- **hardened-app** — owned chart, no overlay; restricted profile is the
  default.

### What VEX means for you

The catalogue splits vulnerability handling into two lanes, and only one of
them is published:

| Lane              | Claim                                                                                   | You see it as                                          | Expires? |
|-------------------|-----------------------------------------------------------------------------------------|--------------------------------------------------------|----------|
| **VEX**           | "This CVE does not apply here" (`not_affected`) or "this release carries the remedy" (`fixed`) — a claim about the artifact, evidence-backed | An `openvex` attestation on the image, consumable by your scanner | No |
| **Accepted risk** | "It applies, and the maintainer ships anyway for a bounded time" — a decision about *their* exposure | You don't. It is internal and never attested (Req 6.8) | Yes, ≤ 90 days |

The consequence for a consumer: a HIGH finding your scanner reports against a
catalogue image, which the VEX attestation does not excuse, may still be a
*known and tracked* risk on the maintainer side — check the repo's open
`cve`-labeled issues and `triage/accepted-risk/`. What you will never get is a
published claim that a vulnerability doesn't apply merely because someone
decided to live with it: writing a risk acceptance as VEX is prohibited by
requirement, precisely because every downstream consumer would inherit it.

## Part II: The pipeline

### The six workflows

| Workflow       | Trigger                    | Job |
|----------------|----------------------------|-----|
| `validate.yml` | every PR + main            | yamllint, pin/definition lints, policy self-tests, every script's unit tests, Renovate config + manager fixtures, Go module vet/build/unit tests |
| `build.yml`    | every PR + main + dispatch + daily 04:47 UTC | Build affected definitions; PR path runs the CVE **scan gate**; main path releases (push by digest, scan every platform manifest, sign, SBOMs, VEX, tag last); the nightly rebuilds everything and publishes on change |
| `chart.yml`    | every PR + main            | Render *every* chart, evaluate with the Kyverno policies; `ct lint` on owned charts |
| `e2e.yml`      | PR + dispatch              | Per affected component: kind cluster, install the hardened chart, run the Ginkgo suite |
| `renovate.yml` | cron every 4h + dispatch   | Self-hosted Renovate over the custom managers; postUpgradeTasks recompute derived fields |
| `rescan.yml`   | daily 06:17 UTC + dispatch | Enumerate every catalogue tag; visibility invariant and admission proof; scan every platform manifest by digest; file new-CVE issues for the supported set; expiry warnings |

Every GitHub Action is pinned to a full commit SHA, and every third-party
executable a workflow installs is exact-version-pinned and checksum-verified
against values recorded in this repository (Req 7.5) — see
[`install-scanners.sh`](../scripts/install-scanners.sh) /
[`install-tool.sh`](../scripts/install-tool.sh).

### validate — the lint battery

Fast, deterministic, no Docker. The `conventions` job runs, in order: yamllint
(hash-pinned install, Req 7.2); `lint-pins.sh` — every image reference
digest-pinned with a real 64-hex digest, no floating tags (failing output
names the offending reference, Req 1.6, Req 7.4), plus version-coherence
across a definition's derived fields; the Kyverno policy self-tests;
`lint-accepted-risk.sh` (Req 6.11, 6.12); `lint-vex-product.sh`
(Req 6.17–6.21); and the unit tests of every script in `scripts/`. Then
`renovate-config-validator --strict` plus the manager fixtures
(`test/renovate/managers.test.mjs`), which prove each regex manager still
extracts its dependencies — and does not capture anyone else's.

The `go-unit` job gofmt/vets/builds the e2e module and runs its pure helper
tests, and does the same for the `triage/rescan` reporter — so a broken helper
or a broken issue-filing tool can never merge.

### build — the scan gate

The heart of the PR path. For each affected definition (matrix), the job:

1. **Detects what's affected.** Changed `image/*/image.yaml` files map
   directly. Three deliberate extras: a change under `triage/vex/` builds
   every image the *changed* statements name, on both sides of the diff
   (resolved through product purls and `definition-lib.sh`, because a
   variant publishes under its sibling's name; since the compiler produces
   each image's gate input from statements naming it alone, an untouched
   image's input cannot change);
   a changed `triage/accepted-risk/<image>.yaml` rebuilds exactly that image,
   so "the exception suppresses what it claims" is re-proved (Req 6.9); and a
   change to `build.yml` itself builds hardened-app as a canary.
2. **Verifies per-arch pins.** `verify-arch-pins.sh` fetches every per-arch
   pinned artifact and checks the recorded checksums against the bytes
   upstream actually serves, so a pin the PR gate never builds (arm64: the
   gate is amd64-only) is still checked before it can reach a release
   (Req 1.3).
3. **Builds** linux/amd64 through the real `dhi.io/build` frontend (the
   frontend compiling the definition *is* the authoritative schema validation,
   Req 1.5), with a per-image GHA cache. PRs `load:` the image into the
   daemon; main builds every platform the definition declares and the policy
   admits (`catalogue-policy.yaml` `release.platforms`), and pushes by digest
   instead.
4. **Pushes to a throwaway local registry.** Trivy constructs the `pkg:oci/…`
   product purl a VEX statement must match from the image's *RepoDigest*. A
   buildx-loaded image has none, so no statement could ever match (upstream
   trivy#9399). A push to `localhost:5000` mints one.
5. **Compiles VEX and scans.** `compile-vex.sh` renders `triage/vex/` for this
   build (digest stamped in, out-of-scope statements dropped — see
   [Writing a VEX statement](#writing-a-vex-statement)), then one Trivy run
   over `HIGH,CRITICAL` consumes both suppression inputs: `--vex` (compiled
   applicability claims) and `--ignorefile triage/accepted-risk/<image>.yaml`
   (time-boxed risk decisions). `--show-suppressed` keeps both visible.
6. **Collects reachability evidence.** govulncheck in binary mode over every
   Go binary found in the exported image filesystem — *evidence, not a second
   gate* (`continue-on-error`); see
   [Reachability evidence](#reachability-evidence-govulncheck) (Req 6.13).
7. **Grype second opinion** whenever a CRITICAL survives — different DB,
   different matcher, informational (Req 6.6).
8. **Gate.** Any surviving HIGH or CRITICAL fails the job (Req 6.1), with an
   error message that names each finding (id, package, installed and fixed
   version) and the four ways out, strongest first: avoid · fix · prove it
   does not apply · accept/transfer for a bounded time. Scan reports upload
   as artifacts either way.

Measured, not inferred: the local-registry step exists because it was
measured — with no RepoDigest, *every* OpenVEX product form (digest-pinned,
registry-qualified, bare) matched nothing, silently. Most of this pipeline's
odd-looking moves carry a comment like that in the workflow source; when in
doubt, read `build.yml` — it is deliberately over-commented.

### chart — render + policy gate

*Every* chart is rendered on *every* PR (`render-chart.sh` handles both
shapes — owned `Chart.yaml` charts via `helm template <dir>`, adapted charts
via `--repo/--version` + overlay) and the manifests are evaluated by all three
Kyverno policies: `require-image-digest` (a real 64-hex digest — placeholders
fail), `restrict-registries` (only `ghcr.io/mm-weber/dhc`), and
`require-nonroot` (Req 4.6). Owned charts additionally get `ct lint`.
Install-level verification is deliberately *not* here — that is the e2e
suite's job.

### e2e — the kind suite

For each component a PR touches (chart *or* any of its image definitions; a
change to the harness itself smoke-tests on hardened-app), the workflow
provisions an ephemeral kind cluster and runs the Ginkgo suite (Req 5.2):

- **Image access:** kubelet on each kind node gets a ghcr `config.json`,
  because charts pin the multi-arch *index* digest and a `kind load`-ed image
  carries a single-arch manifest digest — containerd would never match it.
  Pods therefore pull the exact pinned digest, authenticated.
- **Assertions:** workload pods Ready within 5 minutes (Req 5.3); live pod
  securityContext matches the restricted profile — UID/GID 65532,
  RunAsNonRoot, read-only rootfs, seccomp RuntimeDefault (Req 5.4); then the
  per-component functional probe (Req 5.5): cert-manager issues a Certificate
  to Ready, grafana answers its HTTP health endpoint, valkey completes a
  SET/GET round-trip through the Service (via a Job using the live
  Deployment's own image), hardened-app returns HTTP 200.
- **Upgrade path on bumps** (Req 5.6): two bump shapes are detected — a
  chart-version bump (`chart/<c>/chart.yaml` `upstream.version` changed vs the
  base branch) and an image/values bump (the deployed values file changed; the
  base branch's copy is snapshotted). The suite then installs the base state
  first, upgrades to the proposed one, waits for *rollout completion* (so old
  pods can't pass the assertions), and re-asserts everything.
- **Diagnostics on failure** (Req 5.7): the suite dumps
  pods/events/deployments per spec failure, and the workflow adds
  cluster-wide describes, per-pod logs, and `kind export logs` — all uploaded
  as artifacts.

### The release path (merge to main, the nightly, or a dispatch)

The same build job, different arm. On main the affected images are rebuilt
for every declared platform and released in this order, and the order is the
design (Req 2.7 to 2.13; "look first, sign what you looked at, label last"):

1. **Push by digest, no tag.** The image lands in the registry addressed by
   content only; nobody pulling a tag sees a change yet.
2. **Enumerate the platform manifests** of the pushed index (BuildKit's
   attestation manifests excluded).
3. **Scan the pushed digest itself**, one platform manifest at a time by its
   own digest, through `scan-image.sh`, the same script and inputs the PR
   gate uses (compiled VEX + accepted-risk file). No report for any manifest
   means nothing is signed and nothing is tagged (Req 2.26).
4. **Fail-closed switch** (`catalogue-policy.yaml` `release.fail_closed`):
   when on, an uncovered finding stops here, unsigned and untagged (Req 2.13).
   Off by default: the finding becomes an `under_investigation` statement and
   the release completes (Req 2.12).
5. **Attest each manifest's scan report** (`trivy convert --format
   cosign-vuln`, `cosign attest --type vuln`).
6. **Compile the OpenVEX document a second time**, folding in what the scan
   still reports as `under_investigation` with that report's timestamp.
7. **Sign and attest**: `cosign sign --recursive` (index and every platform
   manifest); per manifest, Syft's SPDX and CycloneDX SBOMs and the one
   OpenVEX document; on the index, each platform's SPDX and the same OpenVEX
   document (ADR 0003: exactly one VEX document per digest).
8. **Tags last.** The definition-derived tags move to the new digest, and the
   run re-reads each tag and asserts it resolves to the digest that was
   signed; any mismatch is a red run with the tags untouched.

A failed step publishes nothing and reports itself (Req 2.5). BuildKit
provenance (`mode=max`) is attached by the build itself.

**The nightly** (`build.yml` on the `47 4 * * *` cron, Req 2.14) runs the
same arm for every definition, but builds locally first and asks
`package-set-diff.sh` whether anything changed: the canonicalised package set
(purl plus apk pull checksum, per platform manifest) of the local build is
compared with the one in the CycloneDX SBOM attested to the digest the full
release tag points at. Equal, under the default `on-change` publish policy:
the run stops before the push, publishes nothing, stays green, and logs
whether the digests happened to match (a free reproducibility measurement).
Different, or nothing published yet, or the `always` policy: the release
arm above runs and the summary shows the difference (Req 2.15 to 2.17). A
manual dispatch never compares: a human asking for a release gets one.

### Reading job summaries

The scan gate writes its whole story to the job summary (and mirrors it to
the log, which — unlike summaries — is API-readable). The blocks, top to
bottom:

- **Uncovered counts + "Still uncovered" table** — the findings you must act
  on: CVE, severity (CRITICAL first), package, installed/fixed versions, and
  **Binary** — the target inside the image, which on a repackage image is the
  whole triage question.
- **"Not affected — VEX" table** — what the compiled statements suppressed. If
  statements exist but suppressed nothing, the summary says so explicitly —
  an inert statement is otherwise indistinguishable from a correct one.
- **"Accepted risk" table** — what the exception file suppressed, *per binary*
  (Req 6.27), the file itself inlined (owner + expiry visible without leaving
  the page), and a call-out of every entry that suppressed nothing
  (Req 6.26) — a `paths:` matching no file is silently accepted by Trivy, so
  dead entries are reported, never failed.
- **"Product identifier for this image"** — the purl a VEX statement's
  `products[].@id` must match, taken from the same report the gate used. Copy
  it when authoring the next statement (drop the `@sha256:…` digest — the
  compiler adds the right one per build). Below it, "what Trivy matched
  against" and the versionless **subcomponent** purls for the uncovered
  findings — the other half of a statement, so neither half is ever
  hand-guessed.
- **govulncheck table** — per binary, per finding: `symbol` / `package` /
  `module → not measured`.

The daily rescan's summary adds the **VEX compilation report** (Req 6.33):
per image, the scanned digest, statements applied, statements dropped — with
"digest unresolved, no VEX applied" called out. This is what distinguishes
"compiled nothing" from "never compiled"; both otherwise produce an identical
green run.

### Branch protection

Matrix legs are named dynamically (`build grafana`, `e2e valkey`), so no leg
can be a required check — a PR not touching that image would wait forever.
Each matrix workflow therefore ends in a static **fan-in job** (`build gate`,
`e2e gate`) that fails if any leg failed and passes when legs were skipped
("nothing affected" is a pass) — but only if the detection job itself
succeeded, because a failed detection that skips everything gated nothing.
Require the fan-in jobs plus `validate`'s two jobs and `chart`'s gate in
branch protection.

## Part III: Operating the catalogue

### Crons and cadence

| Cron                      | Schedule                 | Produces                                          | Watch it at |
|---------------------------|--------------------------|---------------------------------------------------|-------------|
| Renovate (`renovate.yml`) | every 4h (Req 3.1)       | Bump PRs; the Dependency Dashboard issue          | Actions tab · issue #5 |
| Rebuild (`build.yml`)     | daily 04:47 UTC (Req 2.14)| Fresh digests for every definition whose package set changed; a discard line for the rest | Actions tab · the run summary per image |
| Rescan (`rescan.yml`)     | daily 06:17 UTC (Req 6.2, 2.22)| Enumeration of every catalogue tag; the visibility invariant and the admission proof (Req 2.21, 2.24); every platform manifest scanned by digest; new-CVE issues for the supported set; expiry warnings; VEX compile report | Actions tab · `cve`-labeled issues |

Both are dispatchable on demand (Renovate with dry-run and debug knobs). A
healthy quiet day is: Renovate runs green and opens nothing; rescan runs
green, files nothing, and its compile report shows every statement applied.

### Handling Renovate PRs

All tracking is custom regex managers — every built-in manager is disabled, so
nothing opens a surprise PR. Each PR shape comes with different automation and
a different reviewer job:

| PR shape | What automation did | Automerge | Your job |
|----------|---------------------|-----------|----------|
| **From-source bump** (cert-manager ×3 grouped, hardened-app, valkey+compat grouped) | `refresh-definition.sh` recomputed checksum, `COMMIT_SHA`, VERSION/SEMVER vars, all three tags, ldflags stamps — from the one ref Renovate moved (Req 3.2) | patch + digest, on green CI (Req 3.5); majors staged behind Dependency Dashboard approval (Req 3.4) | For minors/majors: review the diff coherence, let the gates argue the rest |
| **grafana repackage bump** | `refresh-grafana.sh` resolved the opaque build id from three sources (versions API, apt index, GitHub assets — all answering sources must agree), confirmed both arch tarballs are actually served, re-pinned both per-arch SHA-256s from the `dl.grafana.com` sidecars (ADR 0002) | **Never** — it swaps a binary we did not build | Review version sanity + chart implications; expect the VEX product lint to demand re-scoped statements on a version bump |
| **Build-layer bump** (`syntax=` frontend, `dhi.io/golang` builder) | Tag + digest moved in every definition; source checksums untouched by design | No | Review; expect scan-gate deltas — a newer Go toolchain moves stdlib CVEs in every compiled image |
| **Chart pin bump** | Tag and/or digest moved in chart values (same-tag rebuilds reach charts too); triggers the e2e *upgrade* path (Req 5.6) | No | Review the upgrade e2e result |
| **Tool pin bump** (trivy/grype/kind/kyverno/helm/ct) | Bumped the `_VERSION` in the install script — **and left the recorded sha256 stale on purpose** | No | Complete the pin by hand — below |

**Operator action — completing a tool-pin bump.** A scanner/tool bump PR
fails `validate` with, e.g., *"trivy: no sha256 pinned for
trivy_0.74.0_Linux-64bit.tar.gz"*. That failure is the design: the hash
refresh is deliberately human (Req 7.5), because a checksum that updates
itself verifies nothing (CVE-2026-33634 re-published bytes under
already-adopted versions). To complete it:

1. Fetch the release's official checksums file from the upstream project's
   release page and pick the artifact the script names.
2. Cross-check it against a second statement where one exists (release notes,
   sigstore bundle).
3. Edit the pin block in `scripts/install-scanners.sh` /
   `scripts/install-tool.sh` on the PR branch, push, and let the unit tests
   re-verify the install shape.

Grafana corner case: when no public index carries a new release's build id
yet (it has happened for several 13.x releases), the refresh *refuses by
name* rather than guessing. Wait, or feed the id via
`REFRESH_GRAFANA_BUILD_ID` once you've confirmed it — the pin is still the
sidecar checksum, so a wrong id can only produce a refusal or a verified
artifact.

### Rescan CVE issues

The daily rescan files **one issue per new CVE** (Req 6.3), labeled `cve` /
`security` / `severity:*`, carrying: a severity table with **EPSS** score and
percentile, **CISA KEV** status, and the affected images; the package(s) with
installed → fixed versions; and an embedded triage checklist. A hidden marker
(`<!-- rescan-cve: <ID> -->`) makes the dedup exact — the next run skips any
ID with an open issue. CRITICALs get a Grype corroboration in the run log
before filing.

An issue is a triage decision waiting to happen. Work it exactly like a red
gate (next section); when the decision lands (merged VEX statement,
exception, or fix-bump), close the issue by hand with a pointer to the
commit — the cron opens issues, it never closes them. EPSS and KEV order the
queue; they never justify a status.

### Clearing a red gate — the four treatments

The gate's own error message names the ways out, strongest first. Work them
in order; the lane you end in determines what gets published:

```
HIGH/CRITICAL survives suppression — the gate is red
  │
  ├─ 1. avoid — can we drop the component? ────► definition change;
  │                                              nothing vulnerable ships
  ├─ 2. fix — does a remedy exist? ────────────► version-bump / rebuild PR
  │                                              (Renovate usually has it open)
  └─ 3. does it apply here at all?
       (evidence first: govulncheck, structure)
       │
       ├─ "it never applied" ────────► NOT_AFFECTED            [VEX lane]
       │     OpenVEX in triage/vex/ + LOG.md
       │     attested to the image · published · no expiry
       │
       └─ "it applies; we ship anyway" ─► ACCEPT / TRANSFER    [risk lane]
             triage/accepted-risk/<image>.yaml + LOG.md
             internal · never attested · expires within its tier's ceiling
             └─ expiry lapses ──► finding re-reds the gate  ↻
```

The two lanes answer different questions. **VEX** answers "does this apply?"
— a claim about the artifact, published forever. **Accepted risk** answers
"what are we doing about it?" — a decision about exposure, internal, and it
*decays back to un-triaged on its own*: Trivy silently stops honouring a
lapsed entry, the finding reappears, and someone must decide again.

Ground rules that hold across all four:

- Clearing a red gate means **making a decision, not silencing the scanner**.
  The only sanctioned suppression inputs are `triage/vex/` and
  `triage/accepted-risk/`; a `.trivyignore` anywhere else fails validation
  (Req 6.12).
- Reaching for accept/transfer before ruling out avoid and fix is the failure
  mode the lane is designed to expose — the `blocked:` field must say why the
  stronger treatments were unavailable, and its content is judged at review.
- Every decision gets a dated `triage/LOG.md` entry: finding → evidence →
  outcome → link.
- One finding at a time. Deciding one binary must not silently decide another
  (per-binary scoping, below), and deciding one image never covers another
  (one exception file per image).

### Writing a VEX statement

Author with `vexctl` into `triage/vex/CVE-….openvex.json`:

```sh
vexctl create \
  --product="pkg:oci/<image>?repository_url=ghcr.io%2Fmm-weber%2Fdhc%2F<image>" \
  --subcomponents="pkg:golang/<vulnerable/module>" \
  --vuln="CVE-…" --status="not_affected" \
  --justification="vulnerable_code_not_in_execute_path" \
  --impact-statement="why the code cannot execute here" \
  --file=triage/vex/CVE-….openvex.json
```

**What you write is source — a scanner never sees it.** Trivy builds the
product identifier it matches from the image's **RepoDigest**, so a statement
carrying a tag suppresses nothing — measured, not inferred. `compile-vex.sh`
renders your source per build: it stamps in the digest of the image being
scanned (Req 6.29) and drops any statement scoped to a tag that build is not
(Req 6.30). **You write the tag; the compiler writes the digest.**

```
triage/vex/ (source)          compile-vex.sh (per build)      what the scanner gets
pkg:oci/grafana@13.1.3-…  ──► drop out-of-scope tags (6.30) ─► pkg:oci/grafana@sha256:…
reviewable · stable in git    rewrite product → digest (6.29)  the only form Trivy matches

every drop is recorded and reported (6.32/6.33) — inert must never look correct
```

The product-identifier rules, all lint-enforced:

| Rule | Why | Req |
|------|-----|-----|
| Product is an OCI purl naming an image this repo defines, with `repository_url` equal to that definition's published repository | A wrong product produces *no error of any kind* — the statement is simply inert | 6.17, 6.18 |
| A product version, when present, is a **published tag** of that repository (a variant's tags count) | Scopes the claim to a release the compiler can look up against the build; digests never belong in source | 6.20 |
| `fixed` must carry a version | A remedy is always about particular releases; stated versionless it would claim every published tag carries the fix | 6.21 |
| A **versionless** product requires a `version-independent:` note in `status_notes` saying why the claim survives a version change | Versionless claims every build ever, including releases nobody examined — that scope must be argued, not defaulted into | 6.31 |
| Subcomponent purls carry **no version** | Go module versions move every rebuild; versionless still scopes to the one package | 6.19 |
| A superseded statement is **kept**; the new one is appended with a later timestamp and a bumped document version | Consumers take the latest per (vuln, product); the document then carries what was argued, when, and what replaced it. Trivy orders by timestamp — supersession is load-bearing | 6.22 |

Choosing the scope is about the *kind of argument*, not the status: a
structural claim ("this image never starts a Prometheus server") is
version-independent — versionless plus the note. A dependency-graph claim
("this build does not reach the symbol") rests on what this release links —
scope it to the published tag.

Practical flow: copy the product purl from the failed gate's job summary
(drop the digest), copy a subcomponent purl from the same summary, write the
statement, add the `LOG.md` entry, open the PR. The PR will automatically
**rebuild the images the statement names** and prove it suppresses what it
claims — that is the affected-detection rule, not a coincidence.

### Writing an accepted-risk exception

`triage/accepted-risk/<image>.yaml` is a native Trivy ignorefile plus the
fields that make an entry reviewable. Real shape (abbreviated from the live
grafana file):

```yaml
vulnerabilities:
  - id: CVE-2026-27145
    purls: ["pkg:golang/stdlib"]                    # versionless — survives rebuilds
    paths: ["usr/share/grafana/…/elasticsearch/*"]  # THE binary this decision covers
    treatment: transfer                             # accept | transfer
    owner: mm-weber
    issue: "https://github.com/grafana/…/issues/410"  # required for transfer
    ref: "LOG.md#transfer--stdlib-cve-2026-27145-…"   # where the reasoning lives
    blocked: "avoidance is available and declined, not unavailable: dropping
              the plugin would remove the datasource … remediation is measured
              closed — the newest release is itself built with go1.26.3"
    statement: "transfer: waiting on a release built with go1.26.4+"
    decided_at: 2026-09-02                          # the clock starts here (Req 6.7)
    expired_at: 2026-11-02                          # ≤ decided_at + the tier's ceiling — enforced
```

The rules, all machine-enforced by `lint-accepted-risk.sh` (Req 6.11, 6.24,
6.25):

- **The filename is the image scope.** One file per image — accepting a
  finding for grafana never silently covers cert-manager.
- **`paths:` is the binary scope, and it is required.** The same CVE in two
  bundled binaries is two exposures, owned by different upstreams — so it is
  two entries, and two entries sharing an id may not name the same path.
  Globs work and are needed (the arch suffix differs per build); a path
  matching nothing is silent, which is why the gate reports dead entries
  (Req 6.26).
- **`blocked:` is the honesty field** — why avoid *and* fix were unavailable.
  Presence machine-checked, content judged at review.
- **`expired_at` within the ceiling from `decided_at`.** The policy file
  (`catalogue-policy.yaml` `triage`) declares the clocks: 90 days for a HIGH
  finding, 30 for a CRITICAL, 14 for anything CISA lists as actively
  exploited, whatever its severity. `validate` bounds every entry by the
  largest ceiling; the PR gate and the daily rescan hold each entry to the
  tier its finding actually earns in the scan report, re-checking KEV every
  day, and fail on a breach by name (Req 6.50, 6.51). If the KEV feed is
  unreachable the check does not run and the PR or rescan fails closed
  (Req 6.59, 6.60). Trivy stops honouring a lapsed entry silently;
  the finding then re-reds the gate on its own (Req 6.9). The daily rescan
  warns inside the policy's warning window, 14 days as declared (Req 6.10).
- **Transfer = acceptance with an external owner.** It requires an upstream
  issue to point at — draft it in `triage/upstream/` first (measured
  evidence, re-runnable checks), file it deliberately, then reference it.
- **Never a VEX.** An exception is a business decision about our exposure;
  publishing it would tell every consumer the vulnerability doesn't apply to
  *them* (Req 6.8).

### Reachability evidence (govulncheck)

Trivy and Grype answer "is this module linked?". `govulncheck -mode=binary`
reads the symbol table and answers "is the vulnerable code *called*?" — the
only question that can settle an advisory whose applicability turns on one
symbol. It runs on every PR build over every Go binary in the image,
**non-gating** — evidence, never a second gate (Req 6.13). The table's level
column carries the rules:

| Level         | Meaning                                          | Consequence |
|---------------|--------------------------------------------------|-------------|
| `symbol`      | The vulnerable function is reachable in this binary | **Forbids** `not_affected` / `vulnerable_code_not_in_execute_path` for this image (Req 6.14) |
| `package`     | The package is imported; the symbol is not reached | Citable evidence for a `not_affected` statement (Req 6.15) |
| `module` only | Rendered as *not measured*                        | Never citable as evidence of unreachability (Req 6.16) — silence, not absence (a stripped binary looks the same) |

Every `not_affected` with the execute-path justification must cite a symbol-
or package-level govulncheck result for that binary in its `LOG.md` entry.

### The triage log

`triage/LOG.md` records *every* outcome as dated entries — finding → evidence
→ outcome → link — including retractions, because the three things people
conflate must stay apart:

| Outcome                  | Means                                          | Where it goes |
|--------------------------|------------------------------------------------|---------------|
| `not_affected`           | The vulnerable code cannot execute here        | OpenVEX statement + LOG.md |
| prioritisation           | Real, but low EPSS / not KEV — it waits        | LOG.md only |
| accepted risk / transfer | Real and reachable; shipping anyway, bounded   | LOG.md + `accepted-risk/`, with an owner |

Failure mode — **VEX-washing**: writing "low risk" or "we accept it" into a
VEX statement launders a business decision into a machine-readable claim of
technical inapplicability — and every downstream consumer inherits it. EPSS
and KEV order the queue; they never justify a status.

### Expiries

Expiry happens with time, not with a commit — so the daily rescan is what
raises it, listing every exception already lapsed or lapsing within the policy's warning window
(Req 6.10). Each one needs a fresh decision: fix (has a remedy shipped
since?), avoid, prove it does not apply, or re-accept with a new expiry *and
a reason it is still the right call*. Doing nothing is also a decision — the
lapsed entry stops suppressing and the next affected PR goes red, blaming a
change that isn't at fault. Handle the warning when it appears, not when it
detonates.

## Part IV: Extending the catalogue

### Add an image definition

A definition is one file: `image/<name>/image.yaml`, in native DHI syntax,
built by the pinned `dhi.io/build` frontend
([ADR 0001](decisions/0001-build-layer.md)). The anatomy, using hardened-app
as the skeleton:

```yaml
# syntax=dhi.io/build:2-alpine3.23@sha256:<digest>   ← frontend pin, digest-pinned
name: Hardened App 0.1.x        # display name carries <major.minor>.x
image: ghcr.io/mm-weber/dhc/hardened-app   # publish repo — bare, no digest
variant: runtime
tags: [0-alpine3.23, 0.1-alpine3.23, 0.1.0-alpine3.23]   # the alias fan
platforms: [linux/amd64, linux/arm64]      # declared; main builds every declared platform the policy admits
vars:                           # THE BUMP SURFACE — Renovate rewrites this block
  COMMIT_SHA: 90a8da0c…
  GOLANG_REFERENCE: dhi.io/golang:1.26.5-alpine3.23-dev@sha256:…  # builder, pinned
  SEMVER_MAJOR_MINOR_VERSION: "0.1"
  VERSION: 0.1.0
contents:
  repositories: [https://dhi.io/apk/…]     # hardened repo first, Alpine fallback
  packages: [alpine-baselayout-data, ca-certificates-bundle]   # deliberately tiny
  builds:
    - name: hardened-app
      uses: dhi.io/golang:…-dev@sha256:…   # toolchain stage, digest-pinned
      contents:
        files:
          - url: git+https://github.com/….git#v0.1.0
            checksum: 90a8da0c…            # the trust anchor beside every git+ source
            spdx: {…}                      # feeds the SBOM: name, version, purl
      pipeline:
        - {name: test,  runs: "go test ./..."}       # runs: = computation, never acquisition
        - {name: build, uses: go/build@v1, with: {…}} # actions are frontend macros
      outputs: [{source: …, target: /usr/local/bin/…}] # the ONLY bridge to runtime
accounts:                       # nonroot 65532 — Req 1.4, every runtime image
  run-as: nonroot
  users:  [{name: nonroot, uid: 65532, gid: 65532}]
  groups: [{name: nonroot, gid: 65532, members: [nonroot]}]
os-release: {…}                 # scanners read this to pick the advisory DB
entrypoint: [hardened-app]
```

The walkthrough:

1. **Pick the archetype** and copy the closest existing definition:
   compile-from-source (hardened-app, cert-manager, valkey) or
   tarball-repackage (grafana — versioned vendor URL, per-arch SHA-256 pins in
   `vars:` verified by an in-pipeline `sha256sum -c` step). Prefer from-source
   where the build is tractable; repackage when the upstream toolchain is a
   monster you'd rather triage than own (that split is deliberate —
   [ADR 0002](decisions/0002-grafana-upstream-tracking.md)).
2. **Pin everything**: frontend line, builder `uses:`, every `git+` source
   with its `checksum:`. Never a placeholder digest — an unpinnable reference
   is left unpinned so it fails for the true reason.
3. **Check Renovate coverage.** One manager per archetype reads the pin
   surface; if your source shape is new, add a manager *and* fixture
   assertions in `test/renovate/managers.test.mjs` — both directions: it
   captures yours, it does not capture the others (Req 3.2, Req 7.6). A
   postUpgradeTask must leave the definition coherent (see
   `refresh-definition.sh` / `refresh-grafana.sh`).
4. **Wire e2e** if the image deploys via a chart: register the component in
   `test/harness`, add its probe (next sections).
5. **Open the PR** — one logical change. The gates do the rest: lints,
   frontend compile, scan gate (expect to triage real findings on a new
   image), chart render, e2e.

### Add a variant

A variant that must be *built* (not merely tagged) gets its own directory
`image/<name>-<variant>/` — but publishes to its runtime sibling's
repository; the variant is a tag suffix. Rules that follow, all enforced:

- **Byte-equal source pins** with the runtime sibling (`vars:`, `url:`,
  `checksum:`) — checked by `lint-pins.sh`; a variant that drifts stops being
  "that image plus a package".
- Renovate groups the pair into **one bump PR**, like a monorepo.
- **A directory name is never an image name.** Everything mapping directories
  to published repositories goes through `scripts/definition-lib.sh` — the
  two VEX lints, the compiler, and build.yml's affected-detection all read
  it. Add a new consumer there, never a local re-read: a reader that misses
  resolves to the directory name and *reports clean* while matching nothing.
- Justify the capability increase in the consuming chart's README (the compat
  decision protocol, below).

### Adapt a chart

1. **Pin the upstream chart** in `chart/<name>/chart.yaml` (upstream name,
   repo URL, exact version — hand-pinned; chart *versions* are deliberately
   untracked, image pins are not). Upstream templates are never edited,
   forked, or patched (Req 4.1).
2. **Write the overlay**, `config/values-hardened.yaml`: digest-pinned
   catalogue image (Req 4.2), the canonical restricted block (Req 4.3) — pod
   level unless the chart only exposes container level, and note
   `require-nonroot` reads `runAsNonRoot` at *pod* level:

   ```yaml
   securityContext:
     runAsNonRoot: true
     runAsUser: 65532
     runAsGroup: 65532
     seccompProfile: {type: RuntimeDefault}
   containerSecurityContext:
     allowPrivilegeEscalation: false
     readOnlyRootFilesystem: true
     capabilities: {drop: [ALL]}
   ```

   One named `emptyDir` per writable path, each commented with why the
   workload writes there (Req 4.4). State load-bearing upstream defaults
   explicitly (persistence off, probes on) so a silent upstream flip becomes
   a visible diff.
3. **Document every deviation** in `chart/<name>/README.md` as *what changed →
   why → requirement or upstream link* (Req 4.7).
4. **If the chart assumes a shell** the runtime image doesn't have: measure it
   (render the chart, read the init containers/scripts), then make the compat
   decision — deploy the `-compat` variant and write down what it costs, or
   rule it out (Req 4.5). Forking the chart to remove the offending piece is
   the rejected option: unmodified-upstream is the stronger constraint.
5. **Prove it**: `render-chart.sh` + `kyverno apply` must come back `fail: 0`;
   register the component in the e2e harness (`test/harness`, plus the `ALL`
   list in `e2e.yml` — the affected-regex `image/<c>(-|/)` already catches
   variant directories) and give it a functional probe that exercises real
   behavior, not liveness (valkey's probe SETs and GETs; "answers PING but
   stores nothing" fails).

### Policies

Three Kyverno policies gate every rendered chart: `require-image-digest`
(foreach + regex over containers, initContainers, *and* ephemeralContainers —
a full 64-hex digest, so `@sha256:PENDING` fails), `restrict-registries`,
`require-nonroot`. Fixtures live in `policies/tests/` and run via
`kyverno test` in validate.

Fixture discipline: when you change a policy, the load-bearing fixture is the
one that must *fail* — and for Deployment-shaped workloads that means a
failing fixture against the **autogen** rule (charts render Deployments, so
`autogen-*` is what the gate actually runs). A passing fixture cannot
distinguish a working rule from one that resolved to empty. This is how a
placeholder digest passed the old pattern-based rule — reproduce the hole
first, then close it.

## Part V: Local development and setup

### What runs where

| Task | Devcontainer | Operator host | GitHub Actions |
|------|--------------|---------------|----------------|
| Lints, script unit tests, Go unit tests, chart render + policy | ✓ | ✓ | ✓ authoritative |
| Renovate manager fixtures | ✓ (npm reachable) | ✓ | ✓ |
| e2e on kind | ✓ feasible (DinD; images public on ghcr) | ✓ | ✓ authoritative |
| Image builds (`dhi.io` frontend) | needs dhi.io in firewall + `docker login` | ✓ (login once) | ✓ authoritative |
| Registry pushes, scans of published images, rescan feeds (EPSS/KEV) | ✗ | — | ✓ only |

The devcontainer's egress is allowlist-firewalled: GitHub (incl. releases +
ghcr.io), Docker Hub, PyPI, npm, the Go proxy, and the grafana download/index
hosts are reachable; everything else is blocked (Req 8.2). Extending the
allowlist means editing `/workspace/.devcontainer/init-firewall.sh` and
rebuilding.

### Local commands

```sh
# The full lint battery, exactly as validate runs it
scripts/lint-pins.sh
scripts/lint-accepted-risk.sh
scripts/lint-vex-product.sh
for t in scripts/*_test.sh; do "$t"; done

# Chart render + policy gate (kyverno via the pinned installer)
scripts/install-tool.sh kyverno ~/.local/bin
scripts/render-chart.sh chart/grafana/ > /tmp/rendered.yaml
kyverno apply policies/require-image-digest.yaml policies/restrict-registries.yaml \
  policies/require-nonroot.yaml --resource /tmp/rendered.yaml
kyverno test policies/tests/

# Go unit layers (fast, no cluster, no Docker)
( cd test && go vet ./... && go test ./harness/... ./checks/... ./install/... )
( cd triage/rescan && go test ./... )

# Renovate config + manager fixtures (pins: validate.yml env block)
npm install --no-save renovate@<pinned> json5@<pinned>
./node_modules/.bin/renovate-config-validator --strict renovate.json5
NODE_PATH="$PWD/node_modules" node test/renovate/managers.test.mjs

# e2e locally — creates and destroys its own kind cluster.
# Without DHC_E2E=1 the suite is a cluster-free no-op, so plain
# `go test ./...` stays fast; KIND_NODE_IMAGE pins the node image if needed.
cd test
DHC_E2E=1 go test ./e2e/ -v -timeout 25m -args --chart hardened-app

# Build a definition (operator host, or a container with dhi.io egress)
docker login dhi.io          # Docker ID + PAT with DHI access
docker buildx build -f image/hardened-app/image.yaml image/hardened-app/
```

### Operator setup

| Secret | Used by | Scope |
|--------|---------|-------|
| `DHI_USERNAME` / `DHI_TOKEN` | build.yml (frontend + builder pulls), renovate.yml (docker datasource for dhi.io pins) | Docker Hub credentials with DHI access (Community tier suffices) |
| `RENOVATE_TOKEN` | renovate.yml | PAT with **contents + pull-requests + issues** write — issues write is load-bearing: the Dependency Dashboard is an issue, and major-staging breaks without it |
| *(built-in)* `GITHUB_TOKEN` | ghcr push/pull, issue filing | Per-workflow `permissions:` blocks — least privilege, declared per job |

- **Branch protection:** require `build gate`, `e2e gate`, the `chart` gate,
  and both `validate` jobs (see
  [Branch protection](#branch-protection) for why the fan-ins exist).
- **Labels** (`cve`, `security`, `severity:*`) are created idempotently by
  the rescan — nothing to pre-create.
- **Renovate self-hosting notes:** postUpgradeTask commands must be
  allowlisted (`RENOVATE_ALLOWED_POST_UPGRADE_COMMANDS` already lists the two
  refresh scripts); the cron runs under a concurrency group so runs never
  overlap.

## Part VI: Reference

### Scripts

Every script has a sibling `_test.sh` run by validate. Headers are
documentation — each states what it enforces and why it exists.

| Script | Invocation | Role |
|--------|------------|------|
| `lint-pins.sh` | `[root]` | Digest pins everywhere (64-hex, anchored), no floating tags, definition version-coherence, variant source parity (Req 1.2, 1.6) |
| `lint-vex-product.sh` | `[root]` | VEX product identity + status/version rules (Req 6.17–6.21, 6.31) |
| `lint-accepted-risk.sh` | `[root]` | Exception fields incl. `decided_at`, the policy's largest ceiling from the decision date, per-binary paths, no stray ignore files; doubles as the expiry reporter (Req 6.7, 6.10–6.12) |
| `triage-policy.sh` | `<root> <query>` | The one reader of the policy's `triage` section: aperture, ceilings, KEV ceiling, warning window, feed URL; refuses a section with holes (Req 6.49) |
| `check-exceptions.sh` | `gate <root> <image> <trivy.json> <kev.json>` / `rescan <root> <reports-dir> <kev.json>` | Exception ceilings tiered by the finding's severity and KEV status; no KEV set is a refusal, never a pass (Req 6.50, 6.51, 6.59, 6.60) |
| `compile-vex.sh` | `<src> <out> <definition> <digest> [tag…]` | Render VEX source per build: stamp digest, drop out-of-scope, record every drop via `COMPILE_VEX_REPORT` (Req 6.28–6.32) |
| `definition-lib.sh` | *sourced* | The one directory-↔-published-name mapping; every consumer goes through it |
| `refresh-definition.sh` | `<dir>` | postUpgradeTask, from-source archetype: recompute checksum/vars/tags/ldflags from the bumped ref |
| `refresh-grafana.sh` | `<dir>` | postUpgradeTask, repackage archetype: three-source build-id resolution, per-arch sha re-pin, existence-gated (ADR 0002) |
| `verify-arch-pins.sh` | `<dir>` | Fetch + verify every per-arch pin against upstream's actual bytes (Req 1.3) |
| `install-scanners.sh` | `[destdir]` | trivy + grype, exact version + recorded sha256, both verified before either installs (Req 7.5) |
| `install-tool.sh` | `<kind\|kyverno\|helm\|ct\|syft\|crane> [destdir]` | One pinned, verified tool per call (deliberate sibling, not a generalisation) |
| `scan-image.sh` | `<ref> <definition> <vex-dir> <out.json> [--remote] [--platform P]` | The one Trivy invocation both arms call: compiled VEX + accepted-risk file, `--show-suppressed`, refuses on a failed scan or a missing report (Req 2.8, 2.26) |
| `package-set-diff.sh` | `<definition> <published-ref> <local-index-digest\|-> <verdict-out> <platform>=<cdx.json>…` | Publish-on-change comparator: canonical package set (purl + pull checksum) of the local build vs the attested CycloneDX; `equal` or `different` with a named reason, never raw bytes (Req 2.15–2.17) |
| `enumerate-catalogue.sh` | `<root> <out.tsv>` | Every catalogue tag in every repository via crane, resolved to platform manifests, classified supported or superseded; refuses a partial world (Req 2.22) |
| `check-visibility.sh` | `<root> <enumeration.tsv>` | Daily invariant: anonymous pull token per repository and anonymous manifest GET per tag, bare curl, every failure named (Req 2.21) |
| `verify-catalogue.sh` | `<root> <enumeration.tsv> <report.json>` | Daily admission proof: the rendered policy through the kyverno CLI against the live registry over every tag-referenced digest (must admit) and the declared control (must reject) (Req 2.24) |
| `render-chart.sh` | `<chart-dir>` | Render either chart shape to stdout for the policy gate |
| `accepted-risk-report.sh` | `<trivy.json> <file>` | Per-binary suppression table + dead-entry report (Req 6.26, 6.27) |
| `govulncheck-report.sh` | `label=file …` | Reachability table; module-level collapses to "not measured" (Req 6.16) |

### Renovate managers

`renovate.json5` — `enabledManagers: ["custom.regex"]` only. One manager per
pin surface; every one is fixture-tested in both directions:

| Surface | Shape | Datasource | postUpgradeTask |
|---------|-------|------------|-----------------|
| From-source definitions | `url: git+https://…#vX.Y.Z` | github-tags | `refresh-definition.sh` |
| grafana repackage | versioned tarball URL (custom `versioningTemplate` — semver build metadata ordered as a 4th component, so `+security-NN` releases rank) | github-releases | `refresh-grafana.sh` |
| Build layer | `syntax=` / `uses:` / `GOLANG_REFERENCE` tag@digest | docker (dhi.io, authenticated) | none — reviewed by hand |
| Chart image pins | digest-keyed values (cert-manager ×3, hardened-app) and tag@digest values (grafana, valkey) — capturing tag *and* digest so same-tag rebuilds propagate | docker (ghcr.io) | none |
| Tool pins | `*_VERSION=` blocks in the two install scripts | github-releases | none — sha256 refresh is human |
| Workflow env pins | `# renovate:`-marked `*_VERSION:` (govulncheck, renovate, json5) | go / npm | none |
| Python CI deps | `.github/requirements-ci.txt` | pypi | none — hash refresh is human |

Grouping: cert-manager's three definitions move as one PR; valkey runtime +
compat move as one PR. Majors wait behind Dependency Dashboard approval;
automerge is limited to from-source patch/digest bumps on green CI.

### Requirements map

| Requirement | Enforced / implemented by |
|-------------|---------------------------|
| **Req 1** — Image definition catalogue | `image/*/image.yaml` · `lint-pins.sh` · frontend compile in build.yml · `verify-arch-pins.sh` · ADR 0001 |
| **Req 2** — Build & release | build.yml release arm: push + cosign + Syft SBOM + provenance; tags from definitions; fail publishes nothing |
| **Req 3** — Upstream tracking | renovate.yml (4h cron) · renovate.json5 managers · refresh tasks · manager fixtures · Dependency Dashboard |
| **Req 4** — Chart adaptation | `chart/*/` overlays + READMEs · chart.yml render + Kyverno gate · compat decision protocol |
| **Req 5** — Integration tests | `test/` Ginkgo suite · e2e.yml kind matrix · upgrade path on both bump shapes · diagnostics artifacts |
| **Req 6** — CVE triage | Scan gate + rescan cron · `triage/` two-lane model · compile-vex + both lints · govulncheck evidence · issue filing tool |
| **Req 7** — Conventions & enforcement | `docs/CONVENTIONS.md` · validate.yml battery · PR template · pinned + verified tool installs with managers over the pins |
| **Req 8** — Operating environment | All heavy operations on Actions; devcontainer delegates (operating convention) |

### Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Gate summary: *"Statements exist but suppressed nothing here"* | Inert VEX — wrong product purl, or a statement scoped to a tag this build is not | Copy the product identifier printed in the same summary; check the compile report's drop reasons |
| `validate` fails on a scanner/tool bump PR: *"no sha256 pinned for …"* | By design — the hash refresh is the human half of the pin | Complete the pin from upstream's checksums file ([Handling Renovate PRs](#handling-renovate-prs)) |
| VEX product lint fails after a version bump: *"pins version X, which the definition does not publish"* | A tag-scoped statement outlived its release — Req 6.20 firing correctly | Re-decide for the new release: append a superseding statement (keep the old one), or retire the document |
| Scan gate red on a PR that changed nothing related | An accepted-risk exception expired — the finding decayed back to un-triaged | Make the fresh decision; the rescan had been warning for 14 days |
| Rescan summary: *"unresolved — no VEX applied"* for an image | The registry digest lookup failed; the scan ran unsuppressed (safe direction — may refile issues) | Check the image/tag exists on ghcr; re-dispatch rescan |
| Kyverno gate fails `require-image-digest` on a new chart | Tag-only or placeholder image reference | Pin the real digest; if the image hasn't published yet, leave it unpinned and land the image first (never placeholder) |
| e2e pods stuck `ImagePullBackOff` locally | Chart pins the index digest; a `kind load`-ed image can't match it | Let pods pull from ghcr (public), or mirror the workflow's kubelet-credential step |
| grafana bump PR never opens for a release you can see | No public index carries its build id yet (recurring upstream gap on 13.x) | Wait, or confirm the id and pass `REFRESH_GRAFANA_BUILD_ID`; the refresh refuses rather than guesses |
| Build-layer bump green everywhere except one image's scan gate | Toolchain bump fixed compiled images' stdlib CVEs; a repackage image's prebuilt binaries keep theirs | Triage the repackage image separately — usually the transfer lane |
| `go get` / network call inside a definition's `runs:` fails: *network is unreachable* | Build stages have no egress — by design; acquisition happens only in the declared fetch phase | Declare the source in `files:`, or use the frontend's bump action for dependency surgery |

### Glossary

- **Definition** — the YAML file (`image/<name>/image.yaml`) a hardened image
  is built from, compiled by the `dhi.io/build` BuildKit frontend.
- **Frontend** — BuildKit's pluggable compiler: a container image that
  translates a definition into LLB. Pinned by digest on line 1 of every
  definition.
- **Archetype** — how a definition acquires its payload: *compile-from-source*
  (git ref + commit checksum) or *tarball-repackage* (versioned vendor
  artifact + per-arch SHA-256). Determines the Renovate manager and refresh
  task.
- **Variant** — capability tier of one image family: runtime (default),
  `-dev` (build stage), `-compat` (runtime + minimal shell, by documented
  decision).
- **Scan gate** — the PR-side Trivy run in build.yml that fails on any
  HIGH/CRITICAL not excused by VEX or an unexpired exception (Req 6.1).
- **VEX / OpenVEX** — machine-readable statements about whether a
  vulnerability applies to a product. Here: hand-authored source in
  `triage/vex/`, compiled per build, attested to images.
- **Product / subcomponent purl** — the two halves of a VEX match: the image
  (`pkg:oci/…`, matched via RepoDigest) and the vulnerable package inside it
  (`pkg:golang/…`, versionless).
- **Accepted-risk exception** — a time-boxed, owner-carrying, per-image +
  per-binary entry recording that a real finding ships anyway (`accept`) or
  waits on upstream (`transfer`). Internal; expires within its tier's ceiling.
- **Treatment** — one of the four responses to real risk: avoid, mitigate
  (fix), transfer, accept. `not_affected` is deliberately not a treatment —
  it claims there was never a risk to treat.
- **Reachability** — whether the vulnerable *code* is actually called —
  govulncheck's symbol-level answer, versus a scanner's "the module is
  linked".
- **RepoDigest** — the registry-minted content digest of a pushed image; the
  identity Trivy builds its product purl from — which is why
  loaded-but-never-pushed images match no VEX.
- **EPSS / KEV** — Exploit Prediction Scoring System (FIRST.org) and CISA's
  Known Exploited Vulnerabilities catalogue — queue-ordering signals on
  rescan issues; never a justification for a status.
- **Provenance (SLSA)** — signed in-toto attestation recording builder,
  invocation, and resolved materials for a build — the bridge between SBOM
  claims and verifiable inputs.
- **postUpgradeTask** — a script Renovate runs after bumping a pin so every
  derived field (checksums, vars, tags, ldflags) moves in lockstep and the PR
  is coherent.
- **Fan-in gate** — the static job at the end of a matrix workflow that
  branch protection requires, since dynamic matrix legs can't be.
- **EARS** — Easy Approach to Requirements Syntax: the
  WHEN/WHILE/WHERE/IF-THEN/SHALL pattern every requirement in `.specs/` is
  written in.

---

Written against commit `cdc90e9` (2026-08-19) after a full requirements
review of the working tree and live CI state. Numbers that move (chart
versions, current pins, cron times) were correct at that commit;
`chart/*/chart.yaml`, `image/*/image.yaml`, and the workflow files are always
authoritative.
