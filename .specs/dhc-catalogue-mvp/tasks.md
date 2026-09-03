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
      nothing scanned the arm64 half (Req 2.6). Restoring it is task 9.3 (formerly 8.3)
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
  - [x] 8.3 Restore `linux/arm64`, gated on scanning it first [DEFERRED 2026-08-04; closed 2026-08-22 as superseded by 9.3, which carries its measurements and its criteria]
    - Why it was dropped: arm64 was built, pushed, signed, SBOM'd and attested while every scan step in `build.yml` stayed `pull_request`-gated and the PR gate built amd64 only, and `rescan.yml` passed no `--platform` so Trivy resolved the published index to the runner's own arch. No gate ever read the arm64 image (review finding 1.3). Req 2.22's enumeration scan (2.6 retired into it, primitives pass) forbids publishing a platform nothing scans, so that criterion is the gate this task has to satisfy before the platform returns
    - Scan first, ship second. `rescan.yml` loops platforms with `--platform` **and** `--image-src remote`; the second flag is not optional (measured: Trivy prefers the local docker daemon, where the image is single-arch, and silently ignores `--platform` there — `--platform linux/arm64` returned `architecture=amd64` in 0s). Write `${name}-${arch}.json`; `rescan-report` needs no change, since it globs `*.json` and dedupes images by `ArtifactName`, which is identical across platforms (measured). Cost measured at ~35s per platform per image
    - Then `build.yml`: `platforms: linux/amd64,linux/arm64` on main. A PR-side arm64 gate additionally needs `setup-qemu-action` and a multi-platform push to the local registry, because `load:` takes one platform. The cost there is the build, not the scan, and it falls on source-compiled archetypes (cert-manager) far harder than on tarball repackages (grafana)
    - Definitions kept `platforms:` and their per-arch pins throughout, and `verify-arch-pins.sh` kept fetching and verifying both, so this is a build-matrix change rather than archaeology
    - Already-published tags (`13.0.4-alpine3.23` and earlier) remain multi-arch indexes; they are private and pre-release, and are left as they are [2026-08-22: public since the 2026-08-13 go-live, and scanned in place by 9.3's enumeration rather than left unread; see 9.5]
    - Accepted-risk `paths:` globs already tolerate the arch suffix (7.8), and Req 6.26's dead-entry report is the instrument that would catch any entry that does not
    - _Requirements: Req 2.1, Req 2.22_
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

- [x] 9. Production readiness, cluster A: the release path and the published set (review 2026-08-21, findings F3, F9, F6; spec amendment landed before any of these)
  - [x] 9.1 Release arm: push by digest, scan, sign, attest, then tag
    - `build.yml` main arm: `docker/build-push-action` outputs `type=image,name=<registry>/<image>,push-by-digest=true,name-canonical=true,push=true` with no `tags:` (namespace read from the policy file's `registry:`, task 14.1; review 4.11); the release-time scan runs Trivy against the pushed digest per platform manifest (`--image-src remote`, `--platform`), with the same `--vex` (compiled) and `--ignorefile` inputs the PR gate uses, factored into one script both arms call rather than a second copy of the step; `compile-vex.sh` stamps the index digest and every scanned platform digest (Req 6.29) and adds `under_investigation` statements for anything uncovered (Req 2.12); cosign sign, SBOM attest, OpenVEX attest; then `docker buildx imagetools create -t <tag>…` applies the definition-derived tags (Req 2.7 to 2.9)
    - One compiled OpenVEX document per digest, empty when nothing applies (ADR 0003): `compile-vex.sh` merges every applicable statement from every source file into one document and writes it even with zero statements (its "never write an emptied document" test flips); one `cosign attest --type openvex` per digest instead of a loop over files. Measured 2026-08-22: vexctl, Trivy (file and `--vex oci`), cosign v2.6.0/v3.1.2 and Kyverno 1.18.2 all accept the empty list, and Trivy `--vex oci` reads the first OpenVEX attestation only, which is why one document is required rather than tidy
    - `cosign-release` pinned to an exact v2 version in `build.yml` with a Renovate manager over the pin (Req 7.5, 7.6): CI is on v2.6.0 only by the installer's default, and cosign v3's bundle layout is invisible to Kyverno 1.18.2 and Trivy 0.72.0 (measured, ADR 0003)
    - Recursive: `cosign sign --recursive` signs the index and every platform manifest; Syft runs once per platform manifest digest and both its SPDX and its CycloneDX output are attested to that manifest (`cosign attest --type spdxjson`, `--type cyclonedx`; CycloneDX carries the apk pull checksum that Syft's SPDX output drops, measured 2026-08-22), and each platform's SPDX document is attested to the index as well, because the index is the digest a tag resolves to and the admission condition (signature, SPDX, OpenVEX; task 9.6) is checked at the reference a consumer pins, not one level down (amended 2026-09-02: the first 9.1 releases carried SPDX on platform manifests only, so no post-9.1 index satisfied the policy); the single OpenVEX document is attested to the index and to each platform manifest. Measure `cosign attest --recursive` on v2.6.0 first and fall back to one `cosign attest` per manifest digest if it does not cover the children. A consumer pinning either the index or a platform digest then verifies signature, SBOM and VEX (independent review 1.8)
    - Scan reports attested: each platform manifest's release-time Trivy JSON report is converted with `trivy convert --format cosign-vuln` and attested with `cosign attest --type vuln` to that manifest, so the compiled document's `under_investigation` statements derive from a persisted, verifiable input and carry that report's timestamp (Req 2.12, 6.37); no second scan runs. The release-time scan passes `--show-suppressed` and its attested report records the scanner and database versions (Req 6.55), so the release and rescan arms attest reports of one shape. `compile-vex.sh` gains the attested reports and the previously attested OpenVEX document as inputs, the latter so statements carry forward with their original timestamps (cluster B's re-attestation rule)
    - Fail-closed release setting as a declared workflow variable, default off (Req 2.13); the job's permissions stay `contents: read`, `packages: write`, `id-token: write`: the issue link for an `under_investigation` statement arrives with the next rescan (cluster B), not from the signing job
    - The local-registry step (trivy#9399 workaround) stays PR-only; on main the RepoDigest exists because the image was pushed
    - The rescan already compiles per digest; the release arm now produces the same report shape, so "compiled nothing" versus "never compiled" is visible at release too
    - The scan has two failure shapes with two different answers, both red runs: no report for a platform manifest (registry or database failure) signs nothing and tags nothing (Req 2.26); an uncovered finding under the fail-closed setting signs nothing and tags nothing (Req 2.13); an uncovered finding under the default setting is stated as `under_investigation` and the release completes (Req 2.12)
    - _Requirements: Req 2.2, Req 2.7, Req 2.8, Req 2.9, Req 2.10, Req 2.11, Req 2.12, Req 2.13, Req 2.26, Req 6.29, Req 6.35, Req 6.37_
  - [x] 9.2 Daily scheduled rebuild with publish-on-change [done 2026-09-01]
    - `schedule:` trigger on `build.yml` (daily, before the 06:17 UTC rescan so the rescan sees fresh digests) building every active definition. The `changes` job gains a schedule branch that lists every active definition, read from the policy file per 14.2 (Req 2.14 as amended) (its `workflow_dispatch` branch already has that shape): `github.event.before` is empty on a schedule, so the current fallback would diff `HEAD~1` and skip the release job (independent review 1.10)
    - `scripts/package-set-diff.sh` (+ `_test.sh`) runs before 9.1's push: it takes Syft's CycloneDX output of the local build per platform manifest, canonicalises it to a sorted set of (type, name, version, pull checksum) and compares it with the same projection of the CycloneDX SBOM attested to the matching platform manifest of the digest the same full release tag points at; never raw SBOM bytes (Syft ordering and CPE output are not stable, anchore/syft #331 and #2967); equal stops the run with nothing pushed, signed or attested; different, or no published digest under that tag, publishes through 9.1 and prints the diff in the summary (Req 2.14 to 2.16)
    - Publish policy as a declared variable, `on-change` default, `always` for a fork (Req 2.17); the value is spelled `on-change` because the EARS validator reserves the word "if"
    - When the sets are equal the comparator also logs whether the rebuilt index digest equals the published one, so reproducibility is measured every night at no cost (`data/reproducible-digests-vs-content-diff-2026-08-22.md`, Decision 6); a `diffoci` spike on its own branch is the later step, and Decision 6 records the condition that would promote digest equality to the primary gate
    - Consequence to accept: each real base change opens one non-automerged chart-pin PR per affected chart; same-tag digest automerge is cluster C (F13)
    - _Requirements: Req 2.14, Req 2.15, Req 2.16, Req 2.17_
  - [x] 9.3 Per-platform scanning, then arm64 (absorbs 8.3) [done 2026-09-01]
    - `rescan.yml` enumerates every catalogue tag per repository from the registry tag list (cosign's `sha256-*` tags excluded, Req 2.22) and scans every platform manifest of every tag-referenced digest by the manifest's own digest (`<repo>@sha256:<manifest>`), which needs no `--platform`, cannot be silently downgraded (8.3's measurement: `--platform` without `--image-src remote` is ignored) and yields a RepoDigest equal to the digest the compiler stamps; 9.1's release-time scan does the same over the freshly pushed index (Req 2.8, 2.26). The ten pre-2026-08-04 tags are covered in place by this enumeration
    - Only then `platforms: linux/amd64,linux/arm64` on main (Req 2.1 as amended); the PR gate stays amd64 (cost is the build, not the scan, per 8.3); arm64 e2e out of scope. Until this task lands the release path stays amd64-only against an amended Req 2.1, which is the spec-ahead-of-implementation state every open task in this ledger is in
    - _Requirements: Req 2.1, Req 2.22_
  - [x] 9.4 Visibility invariant [done 2026-09-01]
    - An `invariants` step in `rescan.yml`, the single home for every daily assertion the catalogue makes about its own state (2.21 here, 2.24 in 9.6; cluster C adds the upstream-checksum re-check, cluster D the ruleset-drift, private-reporting and revoked-digest checks), each reported by name, any failure failing the run. First assertion, over every repository `definition-lib.sh` knows: `GET https://<registry host>/token?scope=repository:<namespace>/<name>:pull` unauthenticated must return 200 (namespace from the policy file, task 14.1; review 4.11), and an unauthenticated manifest GET of every catalogue tag from 9.3's enumeration must return 200 (a token is not a pull: a public repository whose tags were deleted still issues one); any other answer fails the run naming the repository or tag (Req 2.21). Measured 2026-08-21: `hardened-app` and `cert-manager-cainjector` were private; the owner flipped them by hand the same day
    - _Requirements: Req 2.21_
  - [x] 9.5 Legacy tags: scanned in place, never re-pointed [done 2026-09-02]
    - The ten tags whose indexes carry a never-scanned arm64 manifest (measured 2026-08-21: cert-manager-controller and -webhook `1.20`, `1.20.3`, `1.21.0`; grafana `13.0`, `13.0.4`; valkey `9.0`, `9.0.5`) keep their digests. A re-point was specified first and withdrawn on 2026-08-22: cosign signed the index digests only (`.sig`/`.att` on every platform manifest return 404, measured in the independent review), so a re-pointed tag would have served an unsigned, unattested manifest. 9.3's enumeration scans their arm64 manifests on its first run; whatever those carry becomes `under_investigation` and issues, which is the promise working. One dated `triage/LOG.md` entry records that first full-enumeration rescan and its findings per tag (Req 2.22)
    - _Requirements: Req 2.22_
  - [x] 9.6 Verification policy and its daily proof [done 2026-09-02]
    - Verification inputs in the `verification` section of `catalogue-policy.yaml` (task 9.8) as roles, issuer `https://token.actions.githubusercontent.com`: `releaser` (identity `https://github.com/mm-weber/dhc-pipeline/.github/workflows/build.yml@refs/heads/main`; may sign, attest `https://spdx.dev/Document`, `https://cyclonedx.org/bom`, `https://cosign.sigstore.dev/attestation/vuln/v1` and `https://openvex.dev/ns`) and `re-attester` (`…/rescan.yml@refs/heads/main`; may attest `https://openvex.dev/ns` and the vulnerability predicate only; active from cluster B); cosign names these predicate types `spdxjson`, `cyclonedx`, `vuln` and `openvex`. The policy's admission condition stays signature plus SPDX plus OpenVEX; CycloneDX and the scan report are attested for consumers and for the comparator, not required for admission. `policies/verify-catalogue-images.yaml` is rendered from that section (9.8), each role an attestor list: signature attestors are the releaser alone, and each attestation type lists the roles allowed for it (Req 2.20, 2.23). A fork adds a role as one more list entry (a dedicated signing workflow behind a protected environment, a revocation job holding `packages: write` and no `id-token`) and never widens an existing one; a `policy-controller` `ClusterImagePolicy` rendering is a fork's addition, not shipped
    - `rescan.yml` applies the policy daily to a manifest listing every digest 9.3's enumeration found under a catalogue tag (must admit; the tag-referenced index digest, which is what a consumer's tag resolves to and where 9.1 now attests signature, SPDX and OpenVEX) and to one unsigned control digest (must reject) and fails the run otherwise (Req 2.24). The control is the amd64 child manifest of the `grafana:13.0.4-alpine3.23` index (`sha256:46607ae2…`): it lives under a catalogue repository so the policy's `imageReferences` match it, carries no signature, and persists as long as its index does. The proof lives in the cron rather than in `kyverno test` fixtures because the set of digests it must admit changes daily (the CLI can reach a registry with `--registry`)
    - README and `docs/user-manual.md` verification snippets move from the substring regexp to the anchored identities per role: `cosign verify` pins the releaser alone, `cosign verify-attestation --type spdxjson` the releaser alone, `cosign verify-attestation --type openvex` releaser or re-attester; the text also says that BuildKit provenance is attached at build time and not policy-verified (Req 2.25)
    - _Requirements: Req 2.20, Req 2.23, Req 2.24, Req 2.25_
  - [x] 9.7 Pinning contract and truth pass [done 2026-09-02]
    - `docs/CONVENTIONS.md` "Pinning": apk packages float by design, resolved set recorded per digest in the attested SBOM, published digest scanned before tagging, daily rebuild as the delivery mechanism for base fixes (Req 1.9); `docs/user-manual.md` release-path, platform and verification sections brought to the new shape; design.md Key Design Decision 6 marked as-built
    - _Requirements: Req 1.9, Req 7.1_
  - [x] 9.8 Catalogue policy file and its renderings [done 2026-08-26]
    - `catalogue-policy.yaml` at the repository root: `release` (fail-closed setting, publish policy, cron expression, admitted platforms), `verification` (issuer, roles and identities, required predicate types), and a `triage` section left for cluster B (aperture, ceilings, warning window; F4 (i)'s `triage/policy.yaml` becomes this section). `build.yml` and `rescan.yml` read the switches at run time with `yq` (Req 7.7)
    - `scripts/render-verification.sh` (+ `_test.sh`) renders `policies/verify-catalogue-images.yaml` and the fenced verification snippets in `README.md` and `docs/user-manual.md` from the `verification` section; `validate.yml` re-renders and fails on any diff against the committed copies, naming the artifact (Req 7.8, 7.9)
    - `validate.yml` lints the `schedule:` cron of `build.yml` and `rescan.yml` and each job's `permissions:` block against the policy file, since GitHub reads those only as literal workflow YAML (Req 7.10)
    - _Requirements: Req 7.7, Req 7.8, Req 7.9, Req 7.10_

- [ ] 10. Production readiness, cluster B: statuses and clocks (review F5, F4, F13 i; ADR 0003, ADR 0004; spec amendment landed before any of these)
  - [x] 10.1 Policy triage section and the exception schema [done 2026-09-02]
    - `catalogue-policy.yaml` `triage` section: `aperture: [CRITICAL, HIGH]`, `ceilings: {CRITICAL: 30d, HIGH: 90d}`, `kev_ceiling: 14d`, `expiry_warning: 14d`, and the support statement: the supported set is each definition's current `tags:`; superseded tag-referenced digests keep scans and attestations and hold no issues (Req 6.49); every value a variable, a fork widens the aperture, tightens the clocks or widens the supported set
    - `triage/accepted-risk/<image>.yaml` entries gain `decided_at` (ISO date); `lint-accepted-risk.sh` requires it and checks `expired_at` minus `decided_at` against the largest ceiling, replacing the "more than 90 days from today" rule (Req 6.7, 6.11); the thirteen standing entries gain `decided_at` as re-decisions dated when this task lands, no historical backfill; the successor starts with `decided_at` native (Decision 9)
    - The PR gate fetches the KEV feed (the rescan's `KEV_URL`) and fails on any exception over its tier, tiering an exception matching no finding by its largest applicable ceiling (Req 6.50); a KEV feed outage fails the pull request by name, and fails the rescan run as a non-evaluation (fail-closed, the owner's call over fail-open; Req 6.59, 6.60); the rescan re-evaluates every unexpired exception against current severity and KEV status, and a breach fails the run through the invariants step (Req 6.51); expiry warnings read the window from the policy file (Req 6.10). Ceiling durations are whole days: the exception schema carries dates, and a fork wanting sub-day ceilings (the 24h example in F4 i) switches `decided_at` and `expired_at` to datetimes
    - `build.yml` (both scan arms) and `rescan.yml` read `--severity` from the policy file's `triage.aperture` the way the release switches are read (9.8), and `triage/rescan`'s `sevRank` takes the aperture as an input instead of hard-coding CRITICAL and HIGH, so a fork's wider aperture reaches every scanner invocation and the issue filer (Req 2.8, 2.22, 6.1, 6.3; independent review 1.6)
    - _Requirements: Req 2.8, Req 2.22, Req 6.1, Req 6.3, Req 6.7, Req 6.10, Req 6.11, Req 6.49, Req 6.50, Req 6.51, Req 6.59, Req 6.60_
  - [x] 10.2 Compiler: `affected` from exceptions, carry-forward, lapses
    - `compile-vex.sh` reads `triage/accepted-risk/<image>.yaml` and emits one `affected` statement per unexpired entry into the single document: `action_statement` assembled from treatment, `statement:`, `issue:` for a transfer, `paths:` and `expired_at`; `action_statement_timestamp` from `decided_at` (Req 6.38). Products as in 6.29 and 6.36
    - `lint-vex-product.sh`: a source statement with any status other than `not_affected` or `fixed` fails, naming it (Req 6.39); closes review A 2.3's `wontfix` gap
    - Carry-forward from the previously attested document (Req 6.37): `timestamp` kept, `last_updated` set on change (Req 6.40); a lapsed exception compiles to `under_investigation` with the original first-seen timestamp and a `status_notes` line naming the lapse, for findings the digest's report still lists (Req 6.41); no historical migration: first seen starts at each finding's first attested appearance under this path, and the successor carries no pre-epoch statements at all (Decision 9); gate coverage ignores `affected` and `under_investigation` (Req 6.35); Trivy suppresses only `not_affected` and `fixed`, measured in design.md's supersession table and re-confirmed by the 2026-08-24 review's ordering runs
    - Measured basis for the timestamp fields: OpenVEX defines statement-level `timestamp`, `last_updated` and `action_statement_timestamp` (spec lines 199, 200, 208)
    - _Requirements: Req 6.8, Req 6.35, Req 6.37, Req 6.38, Req 6.39, Req 6.40, Req 6.41_
  - [ ] 10.3 Rescan re-attestation, replacing
    - Per tag-referenced digest from 9.3's enumeration: `trivy convert --format cosign-vuln` of each platform manifest's report, taken with `--show-suppressed` so covered findings stay visible in the attested report, with the scanner and database versions recorded in it (Req 6.42, 6.55), and `cosign attest --type vuln --replace` to that manifest; compile with the attested reports and the previously attested OpenVEX document as inputs; on difference, `cosign attest --type openvex --replace` on the digest and each platform manifest (Req 6.43). ADR 0004 measured on cosign v2.6.0 that `--replace` swaps only the same predicate type and leaves SBOM and scan-report layers alone; `cosign clean` is all-or-nothing and is not used
    - `rescan.yml` permissions: `packages: write`, `id-token: write` added beside `issues: write`; the identity joins the re-attester role in `catalogue-policy.yaml` (attests `openvex` and `vuln` only, 9.6)
    - Invariants step gains "exactly one OpenVEX attestation per tag-referenced digest and platform manifest" (Req 6.44, 6.45); `triage/upstream/checks/trivy-vex-oci-multiple-attestations.sh` joins the daily consumer smoke test (cluster D, F7) as the regression check for the Trivy behaviour
    - First run in this repository replaces the three OpenVEX attestations grafana's current digest carries with one (until then `--vex oci` consumers get one of three at random, ADR 0004); the successor never carries the case, and the count-repair path stays as the standing guard (Req 6.43, 6.44; Decision 9)
    - Measured first, in CI, before anything relies on them: keyless `cosign attest --replace` behaves as ADR 0004's key-based spike did, and a replaced entry remains retrievable from Rekor (both listed unmeasured there); the previously attested document and the attested reports are read only through `cosign verify-attestation` against the role identities, never through an unverified download (Req 6.58; independent review 1.9)
    - The differs test canonicalises: document `@id`, `timestamp` and `version` are ignored and statement sets are compared; when a digest carries several OpenVEX attestations, the carry-forward input is their `vexctl merge` (field-preserving, measured in ADR 0003) and the replace repairs the count in the same run (Req 6.43, 6.44; independent review 1.4)
    - When an open `cve` issue exists for a finding, the carried-forward statement's status notes gain the issue URL, delivering task 9.1's promised issue link; that is a content change and triggers the one re-attestation that publishes it (Req 6.40)
    - _Requirements: Req 6.42, Req 6.43, Req 6.44, Req 6.45, Req 6.55, Req 6.58_
  - [ ] 10.4 Clocks and the status issue
    - `triage/rescan` Go tool, over the supported set: per finding, first seen from the statement `timestamp`; decided from `action_statement_timestamp` for `affected` and from the statement `timestamp` for `not_affected`/`fixed` (equal to `decided_at` and the author's dated decision respectively, computable from the current document alone); fixed as the first day the finding is absent, reported and suppressed alike, from every supported digest of its repository, carried forward from the previous status issue's fenced JSON, which is a named input so the date survives report replacement (Req 6.46); aggregates (medians, undecided findings by age against the ceilings); unit-tested on fixture attestations and a fixture prior-status JSON
    - One "Catalogue status" issue maintained the way Renovate maintains the Dependency Dashboard: table plus a fenced `metrics.json` block, same JSON uploaded as a workflow artifact (Req 6.47); the JSON schema is written so a Pages dashboard can be added later as presentation only
    - _Requirements: Req 6.46, Req 6.47_
  - [x] 10.5 Badges [closed 2026-08-26 as retired: primitives pass 5.7; Req 6.48 removed, criterion 6.47's status issue is the publication, README badges stay an optional hand-added cosmetic outside the rulebook]
  - [ ] 10.6 Evidence-based issue lifecycle over the supported set
    - The rescan closes an open `cve` issue when its finding appears, reported or suppressed, in no supported digest's attested scan report, or when every finding it names is covered on every supported digest whose report lists it (Req 6.52, 6.53); superseded tag-referenced digests hold no issues, so a fix shipped in the current release closes its issue while the frozen digests' VEX attestations keep stating their own truth
    - Labels are graded by evidence (Req 6.56): `resolved:fixed` only when a diff of the attested CycloneDX SBOMs proves the package version bumped, or a `fixed` statement covers it; `resolved:removed` when the package left every supported digest's SBOM; `resolved:not_affected` / `resolved:accepted` naming the covering artifact; `resolved:absent` otherwise, with the reports' scanner and database versions in the comment so a database regression reads as one
    - Reopening reactivates, never duplicates (Req 6.57): the dedup search extends to closed issues (`--state closed`, same hidden marker as durable finding identity); a finding that returns as a reported finding on a supported digest reopens its original issue with its history intact. The tool acts on derived state only and never records a decision (Req 6.54)
    - _Requirements: Req 6.3, Req 6.52, Req 6.53, Req 6.54, Req 6.56, Req 6.57_
  - [ ] 10.7 Truth pass
    - `docs/user-manual.md` and README: the consumer recipe becomes one `verify-attestation` per predicate type (exactly one OpenVEX attestation per digest), the two-lane table gains the third verb, the rescan section describes replace-not-append, the status issue and the issue lifecycle with its evidence-graded labels and reopening (the manual's "the cron opens issues, it never closes them" sentence goes); `docs/CONVENTIONS.md`'s "must never be written as a VEX" and 90-day sentences; the header comment of `triage/accepted-risk/grafana.yaml` and the same "never attested" sentence in `build.yml`'s attest step comment (flagged for task 9.1's rewrite of that step); `triage/README.md` and `triage/accepted-risk/README.md`: `decided_at`, the policy file's ceilings, the supported set, `affected` as the published form of an exception; design.md Decision 7 marked as-built
    - _Requirements: Req 6.8, Req 7.1_

- [ ] 11. Production readiness, cluster C: upstream trust (review F2, F10, F8, F13 ii and iii, F12 d; spec amendment landed before any of these)
  - [ ] 11.1 Quarantine and automerge truth in renovate.json5
    - One datasource-scoped packageRule (matchDatasources: github-tags, github-releases, npm, pypi, helm, go; no matchUpdateTypes, so minors age too) carrying `minimumReleaseAge: "3 days"` and `minimumReleaseAgeBehaviour: "timestamp-required"`, so a release without a timestamp is pending, never a silent pass; docker is deliberately absent: catalogue-published digests and the hand-reviewed build layer flow same-day (Req 3.7; independent review 1.2, 1.3, 1.7). Not the update-type-scoped Req 3.5 automerge rule
    - A comment states independence comes from age, signal and gates, the commit sha is pin-at-bump-time protecting against later tag rewrites (F2 c), and three days is npm's unpublish window
    - The Req 3.5 packageRule comment and CONVENTIONS' automerge rows state the decided scope truthfully: patch and digest updates of a from-source upstream automerge behind green required checks; repackage bumps never (Req 3.5)
    - `test/renovate/managers.test.mjs` asserts `releaseTimestampSupport === true` on the aged datasource classes against the pinned renovate/dist (the offline harness cannot observe network timestamps, independent review 1.7) and `renovate-config-validator --strict` accepts the age rule
    - _Requirements: Req 3.5, Req 3.7_
  - [ ] 11.2 Authenticity classes, declared and enforced at bump time
    - `# authenticity: <class>` beside each definition's source url: signed-tag (cert-manager trio), signed-commit (valkey, hardened-app), cross-origin-checksum (grafana); `lint-pins.sh` requires a marker on every definition and refuses `none` or a missing one (Req 1.10, 1.11); the same lint restricts dhi.io repository paths to /main (Req 1.12; F12 d, memo Q4: `security` and `els` are entitlement-gated)
    - `refresh-definition.sh` verifies before writing: GitHub's verification statement for the resolved annotated tag (signed-tag) or for the commit a lightweight tag points at (signed-commit), refusing by name on anything but verified (Req 3.8); measured basis in the critique, cert-manager v1.21.1 and valkey 9.1.1 both verified. [OPERATOR: SSH-sign hardened-app tags and cut a signed release; its bump must land through Req 3.8 before task 11.3 does (independent review 1.1, decided universal over grandfather logic)]
    - `refresh-grafana.sh` checkpoint 1: per-arch sha256 from the versions API compared against the dl.grafana.com sidecar before any field is written, refusing on disagreement naming both (Req 3.8; reverses ADR 0002's dated deferral, amendment landed with this spec PR)
    - The refresh writes the evidence where the diff carries it: a dated verification comment beside the pin in image.yaml, for example `# authenticity: signed-tag, verified v1.21.1 (GitHub verification: valid), 2026-08-25`; postUpgradeTask stdout never reaches a PR body, measured against the pinned renovate dist (F2 b as revised; independent review 1.4)
    - _Requirements: Req 1.10, Req 1.11, Req 1.12, Req 3.8_
  - [ ] 11.3 Checkpoints 2 and 3: PR time and daily
    - `verify-arch-pins.sh` gains the API statement: pinned value, bytes served and the versions-API sha256 must agree per architecture, closing the `REFRESH_GRAFANA_SHA256_*` hand-feed seam (Req 3.9); one comparison function shared with checkpoint 1, one test suite, three call sites
    - Rescan invariants: re-verify each active definition's declared signal daily (Req 3.10 as amended; git archetype: GitHub's verification statement for the pinned ref reports verified; repackage: pinned sha equals sidecar and API), a mismatch fails the run and files an issue labelled as a supply-chain signal (Req 3.10); no grandfather state exists: 11.2's operator prerequisite (a signed hardened-app release bumped through Req 3.8) lands before this task, so day one asserts every definition (independent review 1.1); lapsed compat review-by dates reported in the same step (Req 4.9)
    - _Requirements: Req 3.9, Req 3.10, Req 4.9_
  - [ ] 11.4 Chart versions tracked, same-tag chart automerge, valkey compat as transfer
    - renovate.json5: a helm-datasource manager over `chart/<name>/chart.yaml` `upstream.name`/`upstream.repository`/`upstream.version`, with `upstream.repository` captured as `registryUrl` (the helm datasource's default registry is charts.helm.sh/stable, a frozen decoy; independent review 1.8), covering the three upstream charts (hardened-app's own Chart.yaml differs by case and is not captured), never automerged because a chart bump runs the e2e upgrade path (Req 3.11); grafana's version-skew note governs its bump review; valkey's index URL 301-redirects and the datasource follows it; jetstack already lists v1.21.1, so the manager's first run opens a real cert-manager chart bump through the e2e upgrade path; fixtures in managers.test.mjs assert the three captures, the non-capture and the captured registryUrl
    - An automerge packageRule scoped to digest-only updates from the two chart-pin managers (Req 3.12), gated on the required checks (e2e gate among them since 2026-08-21); the dhi.io build-layer rule stays ordered after it so its automerge:false wins
    - `chart/valkey/chart.yaml` gains `compat:` (reason, upstream issue reference, review-by date); a yamale schema validates its shape in validate.yml (yamale is already pinned in requirements-ci.txt), and a date test in a validate lint fails a past review-by date, reusing lint-accepted-risk.sh's expired_at pattern, since yamale day() constraints are static literals with no dynamic today (measured; independent review 1.5) (Req 4.5, 4.8); the chart README keeps the prose, now citing the block
    - `triage/upstream/2026-08-25-valkey-helm-init-container-image.md`: the measured evidence (unconditional init container, same image helper as the main container, metrics-exporter image value as upstream's own precedent) with a checks/ script re-running the render measurement; asks for an init-container image value defaulting to the main image, and an enable switch second. [OPERATOR: file against valkey-io/valkey-helm; record the issue number in the compat block and triage/LOG.md]
    - _Requirements: Req 3.11, Req 3.12, Req 4.5, Req 4.8_
  - [ ] 11.5 Truth pass
    - docs/CONVENTIONS.md: the pinning contract gains the authenticity-class row and the dhi.io /main rule; "hand-pinned; nothing tracks chart versions yet" goes; the upstream-tracking table gains the chart-version manager row and the quarantine and signal sentences; the automerge rows state the 3.5 scope
    - `chart/cert-manager/chart.yaml`'s "still-open gap" comment goes; chart READMEs state each image's authenticity class (F10 consumer half; SECURITY.md's copy arrives with cluster D)
    - `docs/user-manual.md`: the upstream-tracking section gains quarantine, signal and chart-version tracking
    - The `/oss/release/` legacy alias handling goes as dead code with the honest reason, every definition migrated long since: the renovate.json5 matchString, refresh-grafana.sh's alias branch and its test case 5b (epoch review 2.7)
    - design.md Decision 8 marked as-built when implemented
    - _Requirements: Req 7.1_

- [ ] 12. Greenfield successor (owner decided 2026-08-25, F9 re-decision revised on PR #102's independent review; executes after every implementation task in this repository completes)
  - [ ] 12.1 Cut the successor, archive this repository
    - [OPERATOR: create the successor repository (new, not a fork), seed it from this repository's cleaned tree at a chosen commit; publish its first release through the task 9 path; flip each fresh GHCR package public on first publish (fresh personal-scope packages default private, measured in the 2026-08-25 review), asserted daily thereafter by task 9.4's visibility invariant; then archive this repository read-only with a README pointer to the successor]
    - Nothing is deleted: every pre-epoch digest, attestation, issue and LOG entry stays resolvable in the archived repository and its registry; consumers' digest pins never break; no issue reset, no wipe, no transition revocation record (review findings 2.2, 2.3, 2.5 and 2.8 dissolve with the mechanism)
    - Req 2.24's must-reject control is minted in the successor's registry: one unsigned manifest pushed by digest, untagged so it is frozen under Req 2.11, recorded in the successor's LOG (review 2.1; this repository's control, the 13.0.4 amd64 child, stays valid here through implementation)
    - The successor's epoch date is its first release; its README, `docs/user-manual.md` and `SECURITY.md` (cluster D) state it, and the archived repository's README names the successor
    - Depends on the final requirements cleanup: owner, repository and registry names parameterized as declared values; Req 1.1's four-component list restated as a reference set, so an adopter carries only the definitions it wants
    - The successor's seed renumbers the rulebook contiguously once, with a recorded old-to-new mapping in its first commit, retiring this repository's stable-ID gaps (primitives pass, 2026-08-26)
    - _Requirements: Req 2.11, Req 2.24_

- [ ] 13. Production readiness, cluster D: catalogue posture (review F1, F11, F12, F7, F13 register; spec amendment landed before any of these)
  - [ ] 13.1 SECURITY.md, notice, attribution, trust-boundary table
    - `SECURITY.md` with every Req 9.1 item: the promise, aperture and ceilings by reference to `catalogue-policy.yaml`, published/supported/superseded/frozen digests and the epoch, retention from the epoch, what a signature attests and does not (this repository's release workflow on main produced this digest; no human review asserted), the single-maintainer bypass kept deliberately in force, authenticity classes per definition, the Rekor disclosure fact, the terms statement citing `data/dhi-terms-2026-08-21.md` with its DSSA ambiguity sentence (F12 e), and the status issue link
    - `NOTICE` naming Docker Hardened Images (Copyright 2025 Docker Inc., Apache-2.0) and the SBOM licence statement, with the Apache-2.0 licence text committed as `LICENSES/Apache-2.0.txt` and referenced from NOTICE (Req 9.16; F12 a, the memo's explicit ship-the-licence-text instruction, review 3.5); an in-image copy is measured at implementation per the memo; CONVENTIONS records that a definition copied from the catalog must carry a modification notice (F12 b)
    - README.md line 3 and CLAUDE.md line 3 drop their "-style" labels for "built with Docker Hardened Images tooling and packages", and the intro sentences of requirements.md and design.md follow in the same pass (F12 c; review 3.6 measured README still opens with the spelled-out label; the dated "DHI-style YAML" uses inside decisions stand as history); README and the design Overview gain the F12 attribution sentence (hardening substrate by Docker Hardened Images; this catalogue contributes the operating model) and the non-affiliation sentence (Req 9.17); the "production-ready" wording is unblocked once this task and 11.2's /main lint land (F12 f)
    - Trust-boundary table in `docs/concepts.md`, linked from SECURITY.md: every component with owner class and seam alternative (5.1 framing addendum: DHI backend with apko plus Wolfi named, Trivy authoritative with the consumer smoke test as migration insurance, GitHub coupling declared; Req 9.15)
    - _Requirements: Req 9.1, Req 9.15, Req 9.16, Req 9.17_
  - [ ] 13.2 Governance as code
    - `.github/rulesets/main_sec.json`: the live ruleset exported and committed, both gates required, `require_code_owner_review` carried as the documented second-maintainer switch; [OPERATOR: retire the overlapping weaker `branch` ruleset (id 19534405, still active, measured 2026-08-25); enable private vulnerability reporting; drop the admin-view ruleset JSON, bypass_actors visible, into data/, closing the critique's open-items row] (Req 9.2, 9.8)
    - `CODEOWNERS` naming the maintainer per lane: triage/, image/, chart/, policies/, .github/ (Req 9.10)
    - Rescan invariants: each committed ruleset compared against the live rulesets API and the reporting-enabled check, both anonymous reads (Req 9.3, 9.9); the comparison canonicalises by ruleset name over name, target, enforcement, conditions and rules, ignoring server-assigned fields (id, source, node_id, _links, timestamps), runs both directions so a retired ruleset's return is a difference, and `bypass_actors` is outside the compared set, anonymous reads withhold it (review 3.1, 3.9)
    - _Requirements: Req 9.2, Req 9.3, Req 9.8, Req 9.9, Req 9.10_
  - [ ] 13.3 Revocation record
    - `triage/revocations.yaml` (digest, reason, replacement digest, advisory link, date), yamale schema validated in validate.yml (Req 9.5, 9.6), starting empty; a short runbook in docs/ naming moves GHCR actually has (review 3.8: no tag-scoped deletion exists): publish the replacement through the release path, tags move to the replacement digest and the revoked digest becomes untagged and frozen, or, for a withdrawal with no replacement, delete that package version or park the tag on a documented tombstone manifest, the choice recorded in the entry (a public version past 5,000 downloads refuses deletion); record the entry, publish a GHSA advisory, the status issue lists it
    - Rescan invariant: no catalogue tag references a recorded digest (Req 9.7); GHSA named as the advisory channel in SECURITY.md (Req 9.4)
    - _Requirements: Req 9.4, Req 9.5, Req 9.6, Req 9.7_
  - [ ] 13.4 Consumers: declared list, portability block, daily smoke test
    - `catalogue-policy.yaml` gains the consumer list (trivy authoritative, grype second; Req 9.11); one adapter contract: scan a digest with the compiled per-digest VEX, emit vulnerability, purl and suppression state normalised; measured basis: grype 0.116.0 accepts `--vex` (critique F7, 2026-08-21)
    - PR and rescan summaries gain the VEX portability block: per statement the authoritative scanner suppressed, each consumer's result, divergences named; informational, a fork flips it to gating (Req 9.12)
    - Daily consumer smoke test: the published instructions run verbatim against one published digest, failing only on a broken instruction step or a suppression missing in the authoritative consumer, remaining consumers reported into the portability block (Req 9.13; review 3.2, aligned to Decision 10's informational-first rejection)
    - `docs/user-manual.md`'s consumer section and README's verify section gain one scan step per declared consumer, rendered from the policy file's consumer list through task 9.8's rendering so instructions and list cannot drift, on task 10.7's per-predicate-type baseline; no `vexctl merge` step, ADR 0003 retired it (review 3.3); `triage/upstream/checks/trivy-vex-oci-multiple-attestations.sh` joins as the Trivy regression check (task 10.3's hand-off)
    - _Requirements: Req 9.11, Req 9.12, Req 9.13_
  - [ ] 13.5 Manual-controls register
    - `docs/CONVENTIONS.md` register (step, class, why, fork switch): deliberate rows: tool sha256 completion, build-layer bumps reviewed by hand, VEX and exception decisions, hardened-app tag signing; deliberate rows carrying review dates: the cosign v2 pin (ADR 0003) completed the way sha256 pins are, terms sources re-verified by 2026-11-21 (F12 e; classes stay binary per Req 9.14, a review date is a column, not a class, review 3.13); every remaining human step labelled deliberate or pending automation, and the manual's runbook steps cite their register rows (Req 9.14)
    - _Requirements: Req 9.14_
  - [ ] 13.6 LOG-anchor lint, F13's mechanical link
    - `lint-accepted-risk.sh` validates each exception's `ref:` resolves to a real `triage/LOG.md` heading; `lint-vex-product.sh` or a sibling validates each source statement's log citation likewise; both directions checked, every decision has a heading (Req 9.18; F13 "mechanically linked", delivered by no earlier cluster, review 3.4); unit-tested like the other lints
    - _Requirements: Req 9.18_

- [ ] 14. Final cleanup: the base-repo contract (5.1 framing addendum encoded; spec amendment landed before any of these; the last amendment before implementation)
  - [ ] 14.1 Policy file: registry namespace and active set
    - `catalogue-policy.yaml` gains `registry: ghcr.io/mm-weber/dhc` inside the verification section, so task 9.8's rendering source claim (Req 7.8) holds for the imageReferences glob, and an `active_set:` listing all seven definitions (the reference instance activates everything, grafana's tarball included); every reader treats both as declared inputs (Req 1.13, 7.7); the four registry criteria bind through this value (Req 2.2, 2.7, 2.21, 2.23), and tasks 9.1 and 9.4 read the namespace from here rather than their step-text literals (review 4.7, 4.11)
    - `policies/restrict-registries.yaml` joins the rendered, drift-checked artifacts (Req 7.9 pattern): its allowed-registries glob renders from `registry:`, so a fork's chart gate admits the fork's namespace (review 4.7)
    - _Requirements: Req 1.13, Req 2.2, Req 2.7, Req 2.21, Req 2.23, Req 7.7_
  - [ ] 14.2 Every matrix derives from the active set
    - `build.yml`'s definition matrix (schedule branch included, narrowing task 9.2's "every definition" to every active definition, Req 2.14) and `e2e.yml`'s install matrix read the active set from the policy file at plan time (the job-output plus fromJSON pattern both workflows already use); the render-and-policy gate in `chart.yml` deliberately keeps looping every chart directory as validation, so the reference tree cannot rot and task 5.5's recorded every-chart decision stands (review 4.4); the e2e matrix maps definitions to components through each chart's `deploys:` list (14.3)
    - Tracking scope: a rendered Renovate ignore block (delimited, since renovate.json5 carries load-bearing comments; the task 9.8 fenced-snippet shape), drift-checked (Req 7.9 pattern), using the measured native mechanisms (`ignorePaths`, `matchFileNames` plus `enabled`, `ignoreDeps` on renovate 41.173.1); a bump PR touching an inactive definition or a chart adaptation deploying no active definition fails validation naming it (Req 1.16); the coherence lint fails an active set splitting a byte-equal pair or a grouped monorepo (Req 1.18) and an entry naming no definition directory (Req 1.19); managers.test.mjs fixtures cover the rendered block
    - _Requirements: Req 1.14, Req 1.15, Req 1.16, Req 1.18, Req 1.19, Req 2.1, Req 2.14, Req 3.2, Req 3.10, Req 3.11_
  - [ ] 14.3 Probes declared per definition
    - `test/e2e`'s probe registry keyed by chart-backed component, with the definition-to-component mapping declared as a `deploys:` list in each chart's chart.yaml (review 4.8: three of seven definitions have no standalone workload, and valkey-compat's init container has exited before pods are Ready, so shared registrations execute once per Req 5.5); a validate-side lint fails an active definition covered by no registration (Req 5.8), never forcing placeholder probes (the task 6.3 lesson); today's probes (Certificate issuance, HTTP health, SET and GET, HTTP 200) become the reference registrations
    - _Requirements: Req 5.5, Req 5.8_
  - [ ] 14.4 Builder contract documented; truth pass
    - `docs/concepts.md` gains the per-archetype builder contract (input: one definition directory; outputs: an image pushed by digest, per-platform SBOM material carrying pull checksums), cross-linked from the trust-boundary table's backend column (Req 1.17); CONVENTIONS' kyverno parenthetical citing retired Req 8.2 is re-anchored, and its Grype-second-opinion sentence goes with retired 6.6, that retirement stated rather than silent (code review, angle B); docs/CONVENTIONS.md and the manual describe the active set, the reference set and deactivation semantics: published tags keep the tag-driven planes until retention retires them, and a deactivated definition's findings keep every status lane except the fix bump, deactivation as the avoid treatment writ large (review 4.3); the renovate.json5 namespace literals become fork-switch rows in the manual-controls register (Req 9.14; review 4.7); README's positioning sentence (5.1 addendum) lands with task 12.1
    - _Requirements: Req 1.17, Req 4.1_

## Requirements Coverage

| Requirement | Covered By Tasks |
|-------------|------------------|
| Req 1: Image Definition Catalogue | 2.1, 2.2, 3.1, 3.2, 5.1, 5.2, 1.2, 8.1, 8.4, 9.7, 11.2, 14.1, 14.2, 14.4 |
| Req 2: Image Build and Release | 3.3, 8.2, 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 10.1, 14.1, 14.2 |
| Req 3: Upstream Version Tracking | 3.2, 4.1, 4.2, 4.3, 5.1, 5.2, 11.1, 11.2, 11.3, 11.4, 14.2 |
| Req 4: Helm Chart Adaptation | 1.1, 5.3, 5.4, 5.5, 8.1, 8.4, 8.7, 11.3, 11.4, 14.4 |
| Req 5: Go Integration Tests | 6.1, 6.2, 6.3, 6.4, 6.5, 8.7, 14.3 |
| Req 6: CVE Triage | 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9, 8.5, 9.1, 9.3, 10.1, 10.2, 10.3, 10.4, 10.6, 10.7 |
| Req 7: Conventions and Review | 1.1, 1.2, 1.3, 8.6, 9.7, 9.8, 10.7, 11.5, 14.1 |
| Req 9: Catalogue Posture | 13.1, 13.2, 13.3, 13.4, 13.5, 13.6 |

Requirement 8 was retired whole on 2026-08-26 (primitives pass, finding 5.8): its guidance
lives in CLAUDE.md, design.md and CONVENTIONS.md, and its coverage row went with it.

Task group 12 (greenfield successor) adds no new criterion: it executes the dated F9
re-decision of 2026-08-25 (revised the same day to the successor mechanism) rather than
adding standing behaviour; Req 2.11 and 2.24 are the criteria it touches.
