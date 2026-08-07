# Implementation Plan

## Task List

- [ ] 1. Repository skeleton and conventions (Day 1)
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

  - [ ] 1.3 Pin and verify the scanners the gate runs on
    - `scripts/install-scanners.sh` (+ `_test.sh`): trivy and grype pinned to an exact version, downloads checksum-verified against values recorded in-repo; replaces `curl … main/install.sh | sudo sh` in `build.yml` and `rescan.yml`
    - Renovate manager over the pins so a pinned scanner cannot go stale (a stale scanner fails silently, which is why pinning without tracking is not an improvement)
    - Context: CVE-2026-33634 repointed 76 of 77 `aquasecurity/trivy-action` tags to a credential stealer in March 2026; our install path was the same class of exposure, on a runner holding registry tokens and cosign signing permissions
    - _Requirements: Req 7.5, Req 7.6_

- [ ] 2. Build-layer decision (Day 1, 3h timebox) [OPERATOR: host + dhi.io login]
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

- [ ] 3. First definitions building and releasing (Day 1)
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

- [ ] 4. Upstream tracking live (Day 2)
  - [x] 4.1 `renovate.json5` with regex managers and fixtures
    - Managers over definition pin fields (github-tags/github-releases/docker datasources); parse fixtures committed
    - cert-manager monorepo grouping; majors behind Dependency Dashboard approval; automerge only digest-only patch updates
    - Validate with renovate-config-validator in `validate.yml`
    - _Requirements: Req 3.2, Req 3.3, Req 3.4, Req 3.5_
  - [x] 4.2 `renovate.yml` self-hosted cron [OPERATOR: repo secret]
    - `renovatebot/github-action` on ≤6h cron; `postUpgradeTasks` recompute source checksums
    - Operator adds the PAT as a repo secret; scope check documented
    - _Requirements: Req 3.1, Req 3.2_
  - [x] 4.3 Prove the operating loop
    - Confirm real bump PRs open from stale pins; grouped cert-manager PR; one real major staged on the dashboard
    - _Requirements: Req 3.2, Req 3.3, Req 3.4, Req 3.6_

- [ ] 5. Remaining definitions and chart adaptations (Day 2)
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
    - `ct lint`/`ct install` on changed charts; kyverno CLI over rendered manifests (digest, registry, nonroot)
    - Carry `chart/hardened-app/` over from lab unchanged (owned chart, deploy path for e2e probe)
    - _Requirements: Req 4.6_

- [ ] 6. Go integration test suite (Day 3)
  - [x] 6.1 Test module bootstrap
    - `test/` Go module: Ginkgo v2 + Gomega + e2e-framework; kind provisioning helpers (TDD on helpers)
    - _Requirements: Req 5.1_
  - [x] 6.2 Shared assertions
    - Ready ≤5min; live pod securityContext (UID 65532, RO rootfs, seccomp, caps); diagnostics dump to workflow artifacts on failure
    - _Requirements: Req 5.3, Req 5.4, Req 5.7_
  - [x] 6.3 Per-component specs with functional probes
    - cert-manager issues a Certificate; grafana HTTP health; valkey SET/GET; hardened-app HTTP 200
    - _Requirements: Req 5.5_
  - [x] 6.4 Upgrade-path spec [CUT 3rd if pressed: grafana depth only]
    - On bump PRs: install currently pinned version → upgrade to proposed → re-assert
    - _Requirements: Req 5.6_
  - [x] 6.5 `e2e.yml` workflow
    - Affected-component kind matrix on PRs
    - _Requirements: Req 5.2, Req 8.1_

- [ ] 7. CVE triage lane (Day 3)
  - [x] 7.1 Scan gates
    - Trivy PR gate consuming `triage/vex/`; fail on uncovered HIGH/CRITICAL; Grype second opinion on CRITICAL
    - _Requirements: Req 6.1, Req 6.6_
  - [x] 7.2 `rescan.yml` daily cron
    - Rescan published images; new HIGH/CRITICAL → templated issue (severity, EPSS, KEV, affected images)
    - _Requirements: Req 6.2, Req 6.3_
  - [ ] 7.3 First real triage decision
    - Author OpenVEX via vexctl for a real finding, attach with cosign attest, entry in `triage/LOG.md`; or fix-bump PR when a fix exists
    - _Requirements: Req 6.4, Req 6.5_
  - [x] 7.4 Risk treatment lane
    - `triage/accepted-risk/<image>.yaml` time-boxed exceptions (`accept` / `transfer`), consumed by the gate and the rescan as a Trivy `--ignorefile` so an expiry re-reds the gate on its own
    - `scripts/lint-accepted-risk.sh` (+ `_test.sh`, wired into `validate.yml`): required fields, 90-day ceiling, no ignore file outside `triage/accepted-risk/`
    - Job summary separates VEX suppression from risk acceptance and names expiring exceptions; `triage/README.md` gains the four-treatment model
    - _Requirements: Req 6.7, Req 6.8, Req 6.9, Req 6.10, Req 6.11, Req 6.12_
  - [ ] 7.5 Reachability evidence (blocks 7.3)
    - `govulncheck -mode=binary` on the PR path over every Go binary in the built image; **non-gating** — evidence, not a second gate
    - `scripts/govulncheck-report.sh` (+ `_test.sh` on committed fixture JSON, wired into `validate.yml`): govulncheck JSON → per-binary OSV / module / `symbol`-`package`-`module` level
    - Unblocks #30 (kin-openapi CRITICAL) and re-grounds both existing `not_affected` statements on a measurement rather than an argument
    - _Requirements: Req 6.13, Req 6.14, Req 6.15_

  - [ ] 7.6 Make VEX suppression work on the PR gate (blocks 7.3)
    - Trivy derives the `pkg:oci/` product purl from the image's RepoDigest; a buildx `load:` image has none, so the root component carries no purl and **no** OpenVEX statement matches in any form. Measured across digest-pinned, registry-qualified and bare product ids. Upstream: trivy#9399
    - Push the built image to a throwaway local registry so it carries a digest; scan that ref
    - The gate scans copies with the purl qualifiers stripped (the local registry host differs), so published statements stay precisely scoped
    - `scripts/lint-vex-product.sh` (+ `_test.sh`) covers the one field stripping blinds the gate to: product names a real definition, `repository_url` equals its `image:`, subcomponents versionless
    - _Requirements: Req 6.17, Req 6.18, Req 6.19_

  - [ ] 7.7 Status-dependent product versioning, so a superseded decision stays on the record
    - `lint-vex-product.sh` forbade a version on *every* product purl. Correct for `not_affected` — a claim about code structure, true across rebuilds, where a pinned digest would suppress until the next build and then silently stop. Wrong for `fixed` — a version-scoped claim that, stated versionless, asserts every published image under that name carries the remedy, which is false while an older tag remains in the registry
    - Surfaced by CVE-2026-42151 (#25): a `not_affected` statement written against grafana 13.0.4, superseded when the 13.1.1 bump moved prometheus past the fix. Deleting the statement would have lost the reasoning; keeping it unchanged would have described an image we no longer build
    - Lint reads each statement's `status`: `fixed` requires a versioned product, every other status forbids one
    - `triage/README.md` gains the convention with its reason; `triage/LOG.md` carries the transition
    - _Requirements: Req 6.20, Req 6.21, Req 6.22_

  - [ ] 7.8 Per-binary scope for acceptances, so deciding one binary does not decide another
    - One file per image stops grafana covering cert-manager; nothing stopped one binary inside grafana covering another. CVE-2026-27145 (#22) sits in both `plugins-bundled/elasticsearch/` and `plugins-bundled/zipkin/`, built by different upstreams on different schedules and now tracked by two different issues — an entry keyed on `id` + `purls` alone matches `stdlib` in both, so deciding one silently decides the other
    - `lint-accepted-risk.sh`: `paths` joins the required set (6.24), and two entries sharing a vulnerability id may not name the same path (6.25)
    - `build.yml`: report any exception that suppressed nothing (6.26) and add the binary to the suppression table (6.27). A too-narrow path fails safe but reads as untriaged; a too-broad one fails green over a binary nobody argued. Report, never fail — an exception that suppresses nothing leaves nothing uncovered, so Req 6.1 is the wrong lever
    - Trivy 0.72.0 behaviour measured first, on a two-binary tree from the real plugin assets: `paths` scopes, globs work (needed — the arch suffix differs per build), a path matching nothing is silent. Recorded in `design.md` and re-runnable from `triage/upstream/checks/`
    - _Requirements: Req 6.23, Req 6.24, Req 6.25, Req 6.26, Req 6.27_

  - [ ] 7.9 Compile VEX per build, so a statement's product is one Trivy matches
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
  - [ ] 8.1 valkey chart adaptation [CUT 1st if pressed]
    - As 5.3 for valkey (stateful: probes, persistence off-by-default rationale)
    - _Requirements: Req 4.1, Req 4.2, Req 4.3, Req 4.4, Req 4.7_
  - [ ] 8.2 README narrative and operating handoff
    - README: lab → catalogue arc, verification walkthrough (cosign verify, SBOM/provenance inspect), triage story
    - Confirm crons active (Renovate, rescan); `/spec-validate` + coverage check against this plan; repo stays private
    - _Requirements: Req 2.4, All (verification)_
  - [ ] 8.3 Restore `linux/arm64`, gated on scanning it first [DEFERRED 2026-08-04]
    - Why it was dropped: arm64 was built, pushed, signed, SBOM'd and attested while every scan step in `build.yml` stayed `pull_request`-gated and the PR gate built amd64 only, and `rescan.yml` passed no `--platform` so Trivy resolved the published index to the runner's own arch. No gate ever read the arm64 image (review finding 1.3). Req 2.6 now forbids publishing a platform nothing scans, so that criterion is the gate this task has to satisfy before the platform returns
    - Scan first, ship second. `rescan.yml` loops platforms with `--platform` **and** `--image-src remote`; the second flag is not optional (measured: Trivy prefers the local docker daemon, where the image is single-arch, and silently ignores `--platform` there — `--platform linux/arm64` returned `architecture=amd64` in 0s). Write `${name}-${arch}.json`; `rescan-report` needs no change, since it globs `*.json` and dedupes images by `ArtifactName`, which is identical across platforms (measured). Cost measured at ~35s per platform per image
    - Then `build.yml`: `platforms: linux/amd64,linux/arm64` on main. A PR-side arm64 gate additionally needs `setup-qemu-action` and a multi-platform push to the local registry, because `load:` takes one platform. The cost there is the build, not the scan, and it falls on source-compiled archetypes (cert-manager) far harder than on tarball repackages (grafana)
    - Definitions kept `platforms:` and their per-arch pins throughout, and `verify-arch-pins.sh` kept fetching and verifying both, so this is a build-matrix change rather than archaeology
    - Already-published tags (`13.0.4-alpine3.23` and earlier) remain multi-arch indexes; they are private and pre-release, and are left as they are
    - Accepted-risk `paths:` globs already tolerate the arch suffix (7.8), and Req 6.26's dead-entry report is the instrument that would catch any entry that does not
    - _Requirements: Req 2.1, Req 2.6, Req 6.2_

## Requirements Coverage

| Requirement | Covered By Tasks |
|-------------|------------------|
| Req 1: Image Definition Catalogue | 2.1, 2.2, 3.1, 3.2, 5.1, 5.2, 1.2 |
| Req 2: Image Build and Private Release | 3.3, 8.2, 8.3 |
| Req 3: Upstream Version Tracking | 3.2, 4.1, 4.2, 4.3, 5.1, 5.2 |
| Req 4: Helm Chart Adaptation | 1.1, 5.3, 5.4, 5.5, 8.1 |
| Req 5: Go Integration Tests | 6.1, 6.2, 6.3, 6.4, 6.5 |
| Req 6: CVE Triage | 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9 |
| Req 7: Conventions and Review | 1.1, 1.2, 1.3 |
| Req 8: Operating Environment | 2.1, 3.3, 4.2, 6.5, 7.2 |
