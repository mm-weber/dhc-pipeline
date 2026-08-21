# Implementation Plan

## Task List

- [x] 1. Repository skeleton and conventions (Day 1)
  - [x] 1.1 Scaffold layout, CONVENTIONS.md, and Kyverno policies
    - Create `image/`, `chart/`, `test/`, `triage/vex/`, `policies/`, `docs/decisions/`, `.github/workflows/`
    - Write `docs/CONVENTIONS.md`: naming (`<semver>-<os><osver>[-variant]`), pinning rules (digest/checksum everywhere, no floating tags), override style, PR conventions
    - Port lab Kyverno policies into `policies/` (require-image-digest, restrict-registries → `ghcr.io/mm-weber/dhc`, require-nonroot)
    - _Requirements: Req 7.1, Req 4.6_
  - [x] 1.2 Convention gate: `validate.yml`
    - yamllint config + workflow job on changed YAML
    - Floating-tag linter failing with the offending reference named
    - PR template prompting for requirement refs and convention compliance
    - _Requirements: Req 7.2, Req 7.3, Req 7.4, Req 1.6_

  - [x] 1.3 Pin and verify the scanners the gate runs on
    - `scripts/install-scanners.sh` (+ `_test.sh`): trivy and grype pinned to an exact version, downloads checksum-verified against values recorded in-repo; replaces `curl … main/install.sh | sudo sh` in `build.yml` and `rescan.yml`
    - Renovate manager over the pins so a pinned scanner cannot go stale (a stale scanner fails silently, which is why pinning without tracking is not an improvement)
    - Context: CVE-2026-33634 repointed 76 of 77 `aquasecurity/trivy-action` tags to a credential stealer in March 2026; our install path was the same class of exposure, on a runner holding registry tokens and cosign signing permissions
    - _Requirements: Req 7.5, Req 7.6_

- [x] 2. Build-layer decision (Day 1, 3h timebox) [OPERATOR: host + dhi.io login]
  - [x] 2.1 Spike the real `dhi.io/build` frontend on operator host
    - `docker login dhi.io` (Community tier), clone `docker-hardened-images/catalog`
    - Build one existing simple definition verbatim; record friction points
    - Attempt one minimal own definition in native syntax
    - Write decision as ADR `docs/decisions/0001-build-layer.md` (A: native / B: fallback)
    - _Requirements: Req 1.7, Req 1.8_
  - [x] 2.2 Wire the chosen build layer
    - If A: frontend syntax directive in definitions; definition validation via frontend dry-run in CI
    - If B: thin renderer (yq/gomplate first; small Go via TDD only if templating proves insufficient) rendering `image.yaml` → multi-stage Dockerfile + bake target, with golden-file tests
    - Author definition JSON Schema (B) or schema-check wiring (A) into `validate.yml`
    - _Requirements: Req 1.5, Req 1.8_

- [x] 3. First definitions building and releasing (Day 1)
  - [x] 3.1 hardened-app definition
    - Port lab Dockerfile semantics into a definition: digest-pinned distroless base, nonroot 65532, multi-arch
    - _Requirements: Req 1.1, Req 1.2, Req 1.3, Req 1.4_
  - [x] 3.2 cert-manager definition (monorepo → three images)
    - One version var driving controller/webhook/cainjector from one pinned source ref + checksum
    - Pin one minor release behind latest upstream (stale-pin bootstrap)
    - _Requirements: Req 1.1, Req 1.2, Req 1.3, Req 1.4, Req 3.6_
  - [x] 3.3 `build.yml`: PR build path and main release path
    - PR: build affected images (amd64 only, `type=gha` cache), no push
    - main: amd64 build → push to private `ghcr.io/mm-weber/dhc` + cosign keyless + Syft SPDX SBOM + BuildKit provenance
    - Verify GHCR packages are private; failure publishes nothing and reports failing step
    - CI-validated: PR path green on all four definitions (amd64+arm64) before the
      amd64-only/cache speed fix
    - Release path was multi-arch until 2026-08-04 and is now amd64 only, because
      nothing scanned the arm64 half (Req 2.6). Restoring it is task 8.3
    - _Requirements: Req 2.1, Req 2.2, Req 2.3, Req 2.4, Req 2.5, Req 8.1_

- [x] 4. Upstream tracking live (Day 2)
  - [x] 4.1 `renovate.json5` with regex managers and fixtures
    - Managers over definition pin fields (github-tags/github-releases/docker datasources); parse fixtures committed
    - cert-manager monorepo grouping; majors behind Dependency Dashboard approval; automerge for digest and patch updates on the github-tags datasource, gated on CI (broader than first written here — the config automerges real patch bumps, not only digest re-pins)
    - Validate with renovate-config-validator in `validate.yml`
    - _Requirements: Req 3.2, Req 3.3, Req 3.4, Req 3.5_
  - [x] 4.2 `renovate.yml` self-hosted cron [OPERATOR: repo secret]
    - `renovatebot/github-action` on ≤6h cron; `postUpgradeTasks` recompute source checksums
    - Operator adds the PAT as a repo secret; scope check documented
    - _Requirements: Req 3.1, Req 3.2_
  - [x] 4.3 Prove the operating loop
    - Confirm real bump PRs open from stale pins; grouped cert-manager PR; one real major staged on the dashboard
    - _Requirements: Req 3.2, Req 3.3, Req 3.4, Req 3.6_

- [x] 5. Remaining definitions and chart adaptations (Day 2)
  - [x] 5.1 grafana definition (tarball repackage archetype)
    - Official release tarball onto minimal digest-pinned base; nonroot 65532; writable-path inventory for chart work; stale pin
    - _Requirements: Req 1.1, Req 1.2, Req 1.3, Req 1.4, Req 3.6_
  - [x] 5.2 valkey definition (stateful archetype) [CUT 2nd-last if pressed]
    - Binary repackage, nonroot, stale pin
    - _Requirements: Req 1.1, Req 1.2, Req 1.3, Req 1.4, Req 3.6_
  - [x] 5.3 cert-manager chart adaptation
    - Pin upstream chart version; `config/values-hardened.yaml` (digest-pinned image swap, restricted PSS); README documenting every deviation + rationale
    - _Requirements: Req 4.1, Req 4.2, Req 4.3, Req 4.7_
  - [x] 5.4 grafana chart adaptation
    - As 5.3 plus emptyDir mounts for writable paths; compat-variant decision documented if chart assumes shell utilities
    - _Requirements: Req 4.1, Req 4.2, Req 4.3, Req 4.4, Req 4.5, Req 4.7_
  - [x] 5.5 Chart CI gate
    - `ct lint` + kyverno CLI over rendered manifests (digest, registry, nonroot), every chart on every PR — no changed-chart scoping, and no `ct install`: install-level verification is the kind e2e suite's job (`chart.yml` says so)
    - Carry `chart/hardened-app/` over from lab unchanged (owned chart, deploy path for e2e probe)
    - _Requirements: Req 4.6_

- [x] 6. Go integration test suite (Day 3)
  - [x] 6.1 Test module bootstrap
    - `test/` Go module: Ginkgo v2 + Gomega + e2e-framework; kind provisioning helpers (TDD on helpers)
    - _Requirements: Req 5.1_
  - [x] 6.2 Shared assertions
    - Ready ≤5min; live pod securityContext (UID 65532, RO rootfs, seccomp, caps); diagnostics dump to workflow artifacts on failure
    - _Requirements: Req 5.3, Req 5.4, Req 5.7_
  - [x] 6.3 Per-component specs with functional probes
    - cert-manager issues a Certificate; grafana HTTP health; valkey SET/GET; hardened-app HTTP 200
    - Checked off in phase 6 with three of the four probes written. valkey's SET/GET had no chart to run against until 8.1, and `componentSpecs` said so in a comment rather than here — so this box claimed a probe the suite did not have. Completed by 8.1; recorded because the checkbox, not the comment, is what this plan is read for
    - _Requirements: Req 5.5_
  - [x] 6.4 Upgrade-path spec [CUT 3rd if pressed: grafana depth only]
    - On bump PRs: install currently pinned version → upgrade to proposed → re-assert
    - _Requirements: Req 5.6_
  - [x] 6.5 `e2e.yml` workflow
    - Affected-component kind matrix on PRs
    - _Requirements: Req 5.2, Req 8.1_

- [x] 7. CVE triage lane (Day 3)
  - [x] 7.1 Scan gates
    - Trivy PR gate consuming `triage/vex/`; fail on uncovered HIGH/CRITICAL; Grype second opinion on CRITICAL
    - _Requirements: Req 6.1, Req 6.6_
  - [x] 7.2 `rescan.yml` daily cron
    - Rescan published images; new HIGH/CRITICAL → templated issue (severity, EPSS, KEV, affected images)
    - _Requirements: Req 6.2, Req 6.3_
  - [x] 7.3 First real triage decision
    - Author OpenVEX via vexctl for a real finding, attach with cosign attest, entry in `triage/LOG.md`; or fix-bump PR when a fix exists
    - _Requirements: Req 6.4, Req 6.5_
  - [x] 7.4 Risk treatment lane
    - `triage/accepted-risk/<image>.yaml` time-boxed exceptions (`accept` / `transfer`), consumed by the gate and the rescan as a Trivy `--ignorefile` so an expiry re-reds the gate on its own
    - `scripts/lint-accepted-risk.sh` (+ `_test.sh`, wired into `validate.yml`): required fields, 90-day ceiling, no ignore file outside `triage/accepted-risk/`
    - Job summary separates VEX suppression from risk acceptance and names expiring exceptions; `triage/README.md` gains the four-treatment model
    - _Requirements: Req 6.7, Req 6.8, Req 6.9, Req 6.10, Req 6.11, Req 6.12_
  - [x] 7.5 Reachability evidence (blocks 7.3)
    - `govulncheck -mode=binary` on the PR path over every Go binary in the built image; **non-gating** — evidence, not a second gate
    - `scripts/govulncheck-report.sh` (+ `_test.sh`, self-contained sandbox — no fixture files, no network; wired into `validate.yml`): govulncheck JSON → per-binary OSV / module / `symbol`-`package`-`module` level; module-level-only findings collapse to "unmeasured" (Req 6.16)
    - Unblocks #30 (kin-openapi CRITICAL) and re-grounds both existing `not_affected` statements on a measurement rather than an argument
    - _Requirements: Req 6.13, Req 6.14, Req 6.15, Req 6.16_

  - [x] 7.6 Make VEX suppression work on the PR gate (blocks 7.3)
    - Trivy derives the `pkg:oci/` product purl from the image's RepoDigest; a buildx `load:` image has none, so the root component carries no purl and **no** OpenVEX statement matches in any form. Measured across digest-pinned, registry-qualified and bare product ids. Upstream: trivy#9399
    - Push the built image to a throwaway local registry so it carries a digest; scan that ref
    - The gate scans copies with the purl qualifiers stripped (the local registry host differs), so published statements stay precisely scoped
    - `scripts/lint-vex-product.sh` (+ `_test.sh`) covers the one field stripping blinds the gate to: product names a real definition, `repository_url` equals its `image:`, subcomponents versionless
    - _Requirements: Req 6.17, Req 6.18, Req 6.19_

  - [x] 7.7 Status-dependent product versioning, so a superseded decision stays on the record
    - `lint-vex-product.sh` forbade a version on *every* product purl. Correct for `not_affected` — a claim about code structure, true across rebuilds, where a pinned digest would suppress until the next build and then silently stop. Wrong for `fixed` — a version-scoped claim that, stated versionless, asserts every published image under that name carries the remedy, which is false while an older tag remains in the registry
    - Surfaced by CVE-2026-42151 (#25): a `not_affected` statement written against grafana 13.0.4, superseded when the 13.1.1 bump moved prometheus past the fix. Deleting the statement would have lost the reasoning; keeping it unchanged would have described an image we no longer build
    - Lint reads each statement's `status`: `fixed` requires a versioned product, every other status forbids one
    - `triage/README.md` gains the convention with its reason; `triage/LOG.md` carries the transition
    - _Requirements: Req 6.20, Req 6.21, Req 6.22_

  - [x] 7.8 Per-binary scope for acceptances, so deciding one binary does not decide another
    - One file per image stops grafana covering cert-manager; nothing stopped one binary inside grafana covering another. CVE-2026-27145 (#22) sits in both `plugins-bundled/elasticsearch/` and `plugins-bundled/zipkin/`, built by different upstreams on different schedules and now tracked by two different issues — an entry keyed on `id` + `purls` alone matches `stdlib` in both, so deciding one silently decides the other
    - `lint-accepted-risk.sh`: `paths` joins the required set (6.24), and two entries sharing a vulnerability id may not name the same path (6.25)
    - `build.yml`: report any exception that suppressed nothing (6.26) and add the binary to the suppression table (6.27). A too-narrow path fails safe but reads as untriaged; a too-broad one fails green over a binary nobody argued. Report, never fail — an exception that suppresses nothing leaves nothing uncovered, so Req 6.1 is the wrong lever
    - Trivy 0.72.0 behaviour measured first, on a two-binary tree from the real plugin assets: `paths` scopes, globs work (needed — the arch suffix differs per build), a path matching nothing is silent. Recorded in `design.md` and re-runnable from `triage/upstream/checks/`
    - _Requirements: Req 6.23, Req 6.24, Req 6.25, Req 6.26, Req 6.27_

  - [x] 7.9 Compile VEX per build, so a statement's product is one Trivy matches
    - Measured on the published image, one real finding, one statement each: a tag-versioned product suppresses **nothing** (`pkg:oci/grafana@13.0.4-alpine3.23`, status `fixed` — reported 1, suppressed 0), while a digest-versioned one and a versionless one both work. Trivy builds the product identifier from the RepoDigest, so a tag never matches. Req 6.21 as written could not be satisfied by any statement that had to suppress, and `triage/vex/CVE-2026-42151.openvex.json` is inert today — unnoticed because its finding had already vanished from the scan
    - Pulls the compilation half of the v2 requirements draft forward, scoped: source stays hand-authored in `triage/vex/`, and `scripts/compile-vex.sh` renders it per build. Not pulled forward: the `triage/ledger/` record model, the five-treatment vocabulary, committed compiler output
    - `compile-vex.sh` drops statements whose product tag is not a tag of the image being scanned (6.30) and rewrites every surviving product to that image's digest (6.29). Dropping closes review finding 2.4 (a versionless claim outliving the release it was argued about); rewriting is what makes any of them match
    - Subsumes the inline `jq` qualifier-strip in `build.yml` (trivy#9399) — one tested transform from source to scan input rather than an expression in YAML. `rescan.yml` passes source documents straight to Trivy today and needs the same treatment
    - `lint-vex-product.sh`: 6.20 becomes "a source version must be a published tag" rather than "non-fixed carries no version", so a `not_affected` may be scoped to a release
    - Scope splits by the kind of argument, not by status (6.31). A structural claim ("this image never starts a Prometheus server") is version-independent and stays versionless; a dependency-graph claim ("this build does not reach the symbol") is scoped to its tag. Left to a default every statement drifts versionless, since that suppresses most and costs least to write — so versionless requires a `version-independent:` note in `status_notes` saying why it survives a version change. Demonstrated on the live lane: compiled for a hypothetical 14.0.0, the July 2026 `not_affected` still applied, having been argued about 13.0.4
    - Compilation reports itself (6.32, 6.33). Found by dispatching the rescan on the branch: it went green with an empty issue set, which is exactly what a *failed* digest lookup also produces — the unresolved case suppresses nothing, and the findings it should have excused are deduped away by their own already-open issues. `COMPILE_VEX_REPORT` emits JSON beside the prose and the rescan renders it as a summary table, so "compiled nothing" is distinguishable from "never compiled"
    - The summary earned itself on its first real run. It showed grafana at "2 applied, 0 dropped" against the published **13.0.4**, because `rescan.yml` passed the tags the *definition* declares (13.1.1) rather than the tags the scanned image has (13.0.4). A `fixed` claim written for 13.1.1 therefore suppressed the finding on the release that genuinely carries it — 6.30's exact failure, arriving through the caller. Fixed by resolving each declared tag against the registry and keeping those pointing at the scanned digest
    - Measured while fixing it: Trivy orders VEX statements by `timestamp`, not by array position and not "affected always wins" (later `not_affected` beats earlier `affected`; later `affected` beats earlier `not_affected`). So supersession is load-bearing — the wrong tag set did not merely over-suppress, it applied the *false* claim of the two
    - Attestation had the same defect and worse consequences (6.34): `build.yml` attested `triage/vex/*.json` raw, so every consumer verifying one of our images got products carrying a tag, which matches nothing. Compiling before `cosign attest` also replaces that step's hand-rolled `jq` image filter with the compiler's tested one
    - _Requirements: Req 6.20, Req 6.21, Req 6.28, Req 6.29, Req 6.30, Req 6.31, Req 6.32, Req 6.33, Req 6.34_

- [ ] 8. Wrap-up (Day 3)
  - [x] 8.1 valkey chart adaptation [CUT 1st if pressed]
    - As 5.3 for valkey (stateful: probes, persistence off-by-default rationale)
    - Upstream is the valkey project's own chart, `valkey-io/valkey-helm` 0.11.0, whose appVersion 9.1.1 is the version `image/valkey/` builds — no version skew to argue, unlike grafana. It also arrives harder by default (drop-ALL, `readOnlyRootFilesystem`, `runAsNonRoot`, seccomp), so the overlay moves the UID to 65532, states `runAsNonRoot` at **pod** level where `require-nonroot.yaml` reads it, turns on the opt-in readiness probe, and states persistence off
    - Forced a real Req 4.5 decision, the first in the catalogue: the chart renders an **unconditional** init container from the same image value as the main container and runs `/scripts/init.sh`, a `#!/bin/sh` script that generates the config the main container is started with. `extraInitContainers` appends rather than replaces and no flag disables it, so nothing in values reaches it. Answered with `image/valkey-compat/` — the runtime definition plus one package, busybox — and the cost (a shell in a deployed image, busybox on its CVE surface) is written down in `chart/valkey/README.md` rather than glossed
    - A compat image publishes no digest until it lands on main, so the chart branch carried the tag unpinned and the chart gate failed on `require-image-digest` until `image/valkey-compat/` shipped ahead of it in #53. Deliberate — a placeholder digest passes that gate (see 8.4), so unpinned was the only spelling that failed for the true reason. Now pinned to the digest of that build, `sha256:e9bca4f5…`, and the gate renders all four charts at `fail: 0`. Nothing bumps it automatically: no Renovate manager reads chart values (`enabledManagers: ["custom.regex"]` over `image/` and `scripts/`), so a rebuild moves the digest and this line follows by hand
    - `image/valkey-compat/` is the catalogue's first built variant, so it also introduces the directory convention for one: `image/<name>-<variant>/` publishing to its runtime sibling's repository, now written down in `docs/CONVENTIONS.md` ("Naming") with the byte-equal-source-pin rule that `scripts/lint-pins.sh` enforces over the pair. The consequence for the triage lane is 8.5
    - _Requirements: Req 1.1, Req 1.2, Req 1.3, Req 1.4, Req 4.1, Req 4.2, Req 4.3, Req 4.4, Req 4.5, Req 4.7_
  - [x] 8.2 README narrative and operating handoff
    - README: lab → catalogue arc, verification walkthrough (cosign verify, SBOM/provenance inspect), triage story
    - Confirm crons active (Renovate, rescan); `/spec-validate` + coverage check against this plan; repo stays private
    - 2026-08-13 partial: crons confirmed live via the API (Renovate 3 scheduled runs that day, rescan daily, all green); spec truth pass landed — design.md brought to as-built (ADR 0001 outcome, real definition schema, amd64 release path, chart.yml, no-retry e2e), coverage table corrected, 8.6/8.7 opened for the gaps the review found; MIT LICENSE added; "repo stays private" superseded by the go-live decision
    - 2026-08-13 done: README written against the published artifacts (walkthrough targets grafana 13.1.3-alpine3.23, whose .sig/.att objects were confirmed on GHCR) — deliberately small; the deep material stays in docs/, triage/ and this spec rather than being restated
    - _Requirements: Req 2.4, All (verification)_
  - [ ] 8.3 Restore `linux/arm64`, gated on scanning it first [DEFERRED 2026-08-04; absorbed by 9.3 on 2026-08-21, kept for its measurements]
    - Why it was dropped: arm64 was built, pushed, signed, SBOM'd and attested while every scan step in `build.yml` stayed `pull_request`-gated and the PR gate built amd64 only, and `rescan.yml` passed no `--platform` so Trivy resolved the published index to the runner's own arch. No gate ever read the arm64 image (review finding 1.3). Req 2.6 now forbids publishing a platform nothing scans, so that criterion is the gate this task has to satisfy before the platform returns
    - Scan first, ship second. `rescan.yml` loops platforms with `--platform` **and** `--image-src remote`; the second flag is not optional (measured: Trivy prefers the local docker daemon, where the image is single-arch, and silently ignores `--platform` there — `--platform linux/arm64` returned `architecture=amd64` in 0s). Write `${name}-${arch}.json`; `rescan-report` needs no change, since it globs `*.json` and dedupes images by `ArtifactName`, which is identical across platforms (measured). Cost measured at ~35s per platform per image
    - Then `build.yml`: `platforms: linux/amd64,linux/arm64` on main. A PR-side arm64 gate additionally needs `setup-qemu-action` and a multi-platform push to the local registry, because `load:` takes one platform. The cost there is the build, not the scan, and it falls on source-compiled archetypes (cert-manager) far harder than on tarball repackages (grafana)
    - Definitions kept `platforms:` and their per-arch pins throughout, and `verify-arch-pins.sh` kept fetching and verifying both, so this is a build-matrix change rather than archaeology
    - Already-published tags (`13.0.4-alpine3.23` and earlier) remain multi-arch indexes; they are private and pre-release, and are left as they are
    - Accepted-risk `paths:` globs already tolerate the arch suffix (7.8), and Req 6.26's dead-entry report is the instrument that would catch any entry that does not
    - _Requirements: Req 2.1, Req 2.6, Req 6.2_
  - [x] 8.4 A digest policy that reads the digest, not the word "sha256"
    - `policies/require-image-digest.yaml` matches `*@sha256:*`, so a reference ending in a placeholder passes the gate. Measured while writing 8.1: `ghcr.io/mm-weber/dhc/valkey:9.1.1-alpine3.23-compat@sha256:PENDING-FIRST-MAIN-BUILD` rendered **pass 3, fail 0** across all three policies. A pin that resolves to nothing is exactly what Req 4.2 exists to forbid, and it fails green
    - Kyverno `pattern:` has no character classes, so this wants a `foreach` + `deny` on `regex_match('^[^@]+@sha256:[a-f0-9]{64}$', …)` over containers and initContainers, with the rendered charts as the test corpus (all four must still pass once their digests are real)
    - 8.1 worked around it by leaving the tag unpinned until the image published, which failed the gate for the true reason, and now carries a real digest — but the hole stays open for anyone who reaches for a placeholder
    - Landed as the `foreach` + `deny` above, over one flattened list — `request.object.spec.[containers, initContainers, ephemeralContainers][]` — which drops the absent lists rather than erroring on null, and covers ephemeral containers the old `pattern:` never read. Reproduced first: the three new fixtures (placeholder, `@sha256:TODO` on an initContainer, hex-but-truncated) all scored **pass** against the old rule
    - The controller fixture is the load-bearing one. Charts render Deployments, so `autogen-check-image-digest` is the rule the gate actually runs, and a *passing* controller cannot distinguish an autogen-rewritten foreach list from one that resolved to empty — only a controller that must fail can. Added `placeholder-deployment`; 13/13 in `kyverno test`, and all four rendered charts still `fail: 0`
    - `scripts/lint-pins.sh` had the identical defect on the source side, twice (`*"@sha256:"*` for keyed refs and for the `# syntax=` frontend pin) — a placeholder would have passed review in a definition and only been caught, if at all, at the chart gate. Same reading applied there (`DIGEST_RE='@sha256:[a-f0-9]{64}'`), with three cases in `lint-pins_test.sh`. Anchoring the ref match also meant stripping trailing whitespace, which a substring test tolerated silently
    - `docs/CONVENTIONS.md` states the shape and the rule that follows from it: an unpinnable reference is left unpinned, never placeholdered, so it fails for the reason that is true
    - _Requirements: Req 1.2, Req 4.2, Req 4.6_
  - [x] 8.5 Resolve a VEX product name through `image:`, not through the directory
    - Found reviewing 8.1. Every definition's directory name equalled the last segment of its `image:` until `image/valkey-compat/`, which publishes to `ghcr.io/mm-weber/dhc/valkey`. `compile-vex.sh` took the build-matrix name — the directory — as the product name, so a compat build stamped `pkg:oci/valkey-compat@<digest>` into every statement. Trivy builds its root component from the RepoDigest and reads `valkey`, so nothing would ever have matched
    - Both directions were broken, and both failed green. `lint-vex-product.sh` resolved a purl name to `image/<name>/image.yaml`, so the only spelling Trivy matches (`pkg:oci/valkey@9.1.1-alpine3.23-compat`) scored a Req 6.20 violation — the compat tags are not in the runtime definition's `tags:` — while `pkg:oci/valkey-compat`, which compilation turns into a product that matches nothing, passed
    - Latent rather than live: no valkey statement exists yet, and 7.3 is what would have written the first one. Landing the fix before that is the point — the same inert-statement failure as 7.6 and 7.9, arriving through the repo's own layout instead of through Trivy
    - `compile-vex.sh` keeps the definition name as its reporting identity, because two definitions now share one repository and `rescan.yml` labels its VEX summary rows with it; the report gains a `product` field for the resolved name. `lint-vex-product.sh` resolves a name to every definition publishing that repository and unions their tags, so a variant's release tags are a valid scope and a tag neither publishes still fails. Req 6.20 was amended to say so — it scoped a version to "that image definition", singular, which stopped being a single definition here
    - The mapping is one reader, `scripts/definition-lib.sh`, shared by both lints, the compiler, and `build.yml`'s affected-definitions step — which was the third consumer of the directory-equals-image-name assumption and derived its matrix for a VEX-only change straight from a purl name. Copies rather than a shared reader is how that one was missed: a reader that misses resolves to the directory name and reports as a clean compile
    - _Requirements: Req 6.17, Req 6.20, Req 6.29, Req 6.30_
  - [x] 8.6 Pin the rest of the workflow-installed executables (found by the 2026-08-13 as-built review; tracked as #54 checksums, #55 Renovate managers, #63 govulncheck)
    - Req 7.5 says *every* third-party executable; only trivy/grype (`install-scanners.sh`) satisfy both halves. Still open: `govulncheck` installed via `go install …@latest` (`build.yml` — not even version-pinned; review A finding 1.2 queued this on 2026-08-04 and nothing closed it), kyverno CLI (`validate.yml`, `chart.yml`) and kind (`e2e.yml`) version-pinned but never checksum-verified, renovate npx pinned to a major only
    - None carry a Renovate manager (Req 7.6), so a fixed pin would silently stale — extend the `install-scanners.sh` pattern (checksum recorded in-repo + manager over the pin) rather than inventing a second one
    - `docs/CONVENTIONS.md` claimed all of this was already true; corrected to state the gap until this closes
    - 2026-08-13 partial (#63): govulncheck exact-pinned via `GOVULNCHECK_VERSION` in `build.yml` (Go sumdb is the checksum control for a module-proxy compile), renovate/json5 exact-pinned in `validate.yml`; both carry `# renovate:` comments shaped for the #55 manager. Remaining: kyverno/kind checksums (#54), manager coverage (#55)
    - 2026-08-13 done (#54, #55): kind and kyverno pinned by version + sha256 in `scripts/install-tool.sh` — a sibling of `install-scanners.sh`, not a generalisation, because that script's tested contract is "both scanners verified before either installs" and each workflow here needs exactly one tool. Digests cross-checked against upstream's published checksum files; the kyverno curl-into-tar pipe and kind's unverified curl + `sudo mv` are gone, installs run as the runner user. Deduplicates the twice-declared `KYVERNO_VERSION` (chart.yml + validate.yml) into the one script. Manager coverage: the install-scanners regex manager now reads both pin scripts, and a new workflow-env manager reads the `# renovate:`-marked `*_VERSION:` pins (govulncheck, renovate, json5) — all asserted both directions in `test/renovate/managers.test.mjs`, contract-tested in `scripts/install-tool_test.sh`
    - 2026-08-14 done (#74): the 2026-08-13 sweep missed four installs, found by the 2026-08-14 whole-codebase review. helm arrived via `azure/setup-helm` with **no version input** — latest, unverified, on runners holding GHCR credentials — and ct via `chart-testing-action`, version-pinned but checksum-unverified, pip-installing its own unpinned yamale/yamllint; validate.yml's yamllint was exact-pinned but hash-unverified and rescan.yml's pyyaml wholly unpinned. helm and ct joined `scripts/install-tool.sh` (helm pinned to the 4.2.4 the unpinned action was already resolving, sha256 from the helm release notes; ct's tarball digest cross-checked against upstream's `checksums.txt`, its `etc/` lint configs installed from the same verified bytes into `ct-etc/`), and every python package CI installs moved to `.github/requirements-ci.txt` — exact pins with full sha256 hash sets, installed `--require-hashes` in validate.yml, chart.yml and rescan.yml. Manager coverage: the pin-script manager reads the two new pin blocks as-is; a new pypi regex manager reads the requirements file, version-only bumps with the hash refresh left human, same friction as the sha256 pins. Both directions asserted in `test/renovate/managers.test.mjs`; install shapes (nested helm member, ct extras, mismatch refusals) contract-tested in `scripts/install-tool_test.sh`
    - _Requirements: Req 7.5, Req 7.6_
  - [x] 8.7 Chart image pins drift behind Renovate bumps; Req 5.6 never fires on an image bump (tracked as #64)
    - Renovate managers read only `image/` and `scripts/`, so a definition bump moves nothing under `chart/`: cert-manager chart pins 1.21.0 while the catalogue publishes 1.21.1, grafana chart pins 13.0.4 against a published 13.1.3, and `chart/hardened-app/README.md` claimed Renovate keeps its digest current (corrected — it never did)
    - The upgrade-path spec triggers only on a `chart/<c>/chart.yaml` upstream-version edit (`e2e.yml`), so the ordinary bump path has never exercised Req 5.6 — re-pinning the charts and giving the trigger an image-bump path are the same piece of work
    - 2026-08-13 done (#64): two chart-pin regex managers over `chart/**` values (docker datasource, ghcr.io anonymous since go-live) — digest-keyed spelling for cert-manager ×3 + hardened-app, tag@digest for grafana + valkey, both capturing tag AND digest so same-tag rebuilds reach the chart too; cert-manager trio grouped into one PR. grafana migrated OFF the chart's bare-hex `sha:` field onto tag@digest (Renovate writes `sha256:<hex>`, which would corrupt bare hex; upstream's `_helpers.tpl` strips `@sha…` from the tag for the version label, verified by local render + kyverno gate at `fail: 0`). Req 5.6 image path: `e2e.yml` snapshots the base branch's values file on any values diff and the suite installs it before upgrading (`DHC_UPGRADE_VALUES_FROM`; owned charts now take `-f`, lifting the old owned-skip — TDD'd in `test/install`). Re-pinned all four charts: cert-manager 1.21.1, grafana 13.1.3, and valkey + hardened-app digests which had BOTH silently drifted behind same-tag rebuilds (found re-pinning; the exact failure mode this task closes). Chart-VERSION tracking (chart.yaml) remains hand-pinned and untracked — separate gap, noted in cert-manager/chart.yaml
    - _Requirements: Req 4.2, Req 5.6_

- [ ] 9. Production readiness, cluster A: the release path and the published set (review 2026-08-21, findings F3, F9, F6; spec amendment landed before any of these)
  - [ ] 9.1 Release arm: push by digest, scan, sign, attest, then tag
    - `build.yml` main arm: `docker/build-push-action` outputs `type=image,push-by-digest=true,name-canonical=true,push=true` with no `tags:`; the release-time scan runs Trivy against the pushed digest per platform manifest (`--image-src remote`, `--platform`), with the same `--vex` (compiled) and `--ignorefile` inputs the PR gate uses, factored into one script both arms call rather than a second copy of the step; `compile-vex.sh` stamps the index digest and every scanned platform digest (Req 6.36) and adds `under_investigation` statements for anything uncovered (Req 2.12); cosign sign, SBOM attest, OpenVEX attest; then `docker buildx imagetools create -t <tag>…` applies the definition-derived tags (Req 2.7 to 2.9)
    - Fail-closed release setting as a declared workflow variable, default off (Req 2.13); the job's permissions stay `contents: read`, `packages: write`, `id-token: write`: the issue link for an `under_investigation` statement arrives with the next rescan (cluster B), not from the signing job
    - The local-registry step (trivy#9399 workaround) stays PR-only; on main the RepoDigest exists because the image was pushed
    - The rescan already compiles per digest; the release arm now produces the same report shape, so "compiled nothing" versus "never compiled" is visible at release too
    - _Requirements: Req 2.7, Req 2.8, Req 2.9, Req 2.10, Req 2.11, Req 2.12, Req 2.13, Req 6.35, Req 6.36_
  - [ ] 9.2 Daily scheduled rebuild with publish-if-changed
    - `schedule:` trigger on `build.yml` (daily, before the 06:17 UTC rescan so the rescan sees fresh digests) building every definition; `scripts/package-set-diff.sh` (+ `_test.sh`) compares the fresh SBOM's (name, version, platform) set with the attested SBOM of the digest the same full release tag points at; equal discards, different publishes through 9.1 and prints the diff in the summary (Req 2.14 to 2.16)
    - Publish policy as a declared variable, `if-changed` default, `always` for a fork (Req 2.17)
    - Consequence to accept: each real base change opens one non-automerged chart-pin PR per affected chart; same-tag digest automerge is cluster C (F13)
    - _Requirements: Req 2.14, Req 2.15, Req 2.16, Req 2.17_
  - [ ] 9.3 Per-platform scanning, then arm64 (absorbs 8.3)
    - `rescan.yml` loops platform manifests with `--platform` and `--image-src remote` (8.3's measurement: without `--image-src remote` Trivy prefers the single-arch daemon image and silently ignores `--platform`); 9.1's release-time scan does the same (Req 2.18, 2.19)
    - Only then `platforms: linux/amd64,linux/arm64` on main (Req 2.20, Req 2.1); the PR gate stays amd64 (cost is the build, not the scan, per 8.3); arm64 e2e out of scope
    - _Requirements: Req 2.1, Req 2.6, Req 2.18, Req 2.19, Req 2.20_
  - [ ] 9.4 Visibility invariant
    - `rescan.yml` step over every repository `definition-lib.sh` knows: `GET https://ghcr.io/token?scope=repository:mm-weber/dhc/<name>:pull` unauthenticated must return 200; any other answer fails the run naming the repository (Req 2.21). Measured 2026-08-21: `hardened-app` and `cert-manager-cainjector` were private; the owner flipped them by hand the same day
    - _Requirements: Req 2.21_
  - [ ] 9.5 Legacy tag sweep
    - Scripted and tested: for each catalogue tag whose index carries a platform manifest no scan ever read (ten measured 2026-08-21: cert-manager-controller and -webhook `1.20`, `1.20.3`, `1.21.0`; grafana `13.0`, `13.0.4`; valkey `9.0`, `9.0.5`), re-point the tag to the amd64 manifest digest already inside the index (`imagetools create`); old index digests stay pullable by digest; one dated `triage/LOG.md` entry lists tag, old digest, new digest (Req 2.22). Run once by the operator (host docker login, or a `workflow_dispatch` job with `packages: write`); the rescan's per-platform loop (9.3) is what keeps it from recurring
    - _Requirements: Req 2.22_
  - [ ] 9.6 Verification policy and its daily proof
    - Verification inputs in one declared place (issuer, identities `https://github.com/mm-weber/dhc-pipeline/.github/workflows/build.yml@refs/heads/main` and `…/rescan.yml@refs/heads/main`, required predicate types `spdxjson` and `openvex`); `policies/verify-catalogue-images.yaml` as the Kyverno `verifyImages` rendering (Req 2.23); a `policy-controller` `ClusterImagePolicy` rendering is a fork's addition, not shipped
    - `rescan.yml` applies the policy daily to a manifest listing every published digest (must admit) and to one unsigned control image (must reject) and fails the run otherwise (Req 2.24); `kyverno test` fixtures cannot reach a registry, which is why the proof lives in the cron
    - README and `docs/user-manual.md` verification snippets move from the substring regexp to the anchored identities and issuer (Req 2.25)
    - _Requirements: Req 2.23, Req 2.24, Req 2.25_
  - [ ] 9.7 Pinning contract and truth pass
    - `docs/CONVENTIONS.md` "Pinning": apk packages float by design, resolved set recorded per digest in the attested SBOM, published digest scanned before tagging, daily rebuild as the delivery mechanism for base fixes (Req 1.9); `docs/user-manual.md` release-path, platform and verification sections brought to the new shape; design.md Key Design Decision 6 marked as-built
    - _Requirements: Req 1.9, Req 7.1_

## Requirements Coverage

| Requirement | Covered By Tasks |
|-------------|------------------|
| Req 1: Image Definition Catalogue | 2.1, 2.2, 3.1, 3.2, 5.1, 5.2, 1.2, 8.1, 8.4, 9.7 |
| Req 2: Image Build and Release | 3.3, 8.2, 8.3, 9.1, 9.2, 9.3, 9.4, 9.5, 9.6 |
| Req 3: Upstream Version Tracking | 3.2, 4.1, 4.2, 4.3, 5.1, 5.2 |
| Req 4: Helm Chart Adaptation | 1.1, 5.3, 5.4, 5.5, 8.1, 8.4, 8.7 |
| Req 5: Go Integration Tests | 6.1, 6.2, 6.3, 6.4, 6.5, 8.7 |
| Req 6: CVE Triage | 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9, 8.3, 8.5, 9.1 |
| Req 7: Conventions and Review | 1.1, 1.2, 1.3, 8.6, 9.7 |
| Req 8: Operating Environment | 3.3, 6.5 |

Req 8.2 (delegate network-heavy work to CI/operator host) has no implementing task: it is an
operating convention practiced by every workflow rather than a deliverable. The Req 8 row
previously also listed 2.1, 4.2 and 7.2, none of which annotate a Req 8 criterion — corrected
in the 2026-08-13 as-built review.
