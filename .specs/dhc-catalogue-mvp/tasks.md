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
    - main: multi-arch build → push to private `ghcr.io/mm-weber/dhc` + cosign keyless + Syft SPDX SBOM + BuildKit provenance
    - Verify GHCR packages are private; failure publishes nothing and reports failing step
    - CI-validated: PR path green on all four definitions (amd64+arm64) before the
      amd64-only/cache speed fix; arm64 only on release keeps PR feedback fast
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
  - [ ] 6.5 `e2e.yml` workflow
    - Affected-component kind matrix on PRs
    - _Requirements: Req 5.2, Req 8.1_

- [ ] 7. CVE triage lane (Day 3)
  - [ ] 7.1 Scan gates
    - Trivy PR gate consuming `triage/vex/`; fail on uncovered HIGH/CRITICAL; Grype second opinion on CRITICAL
    - _Requirements: Req 6.1, Req 6.6_
  - [ ] 7.2 `rescan.yml` daily cron
    - Rescan published images; new HIGH/CRITICAL → templated issue (severity, EPSS, KEV, affected images)
    - _Requirements: Req 6.2, Req 6.3_
  - [ ] 7.3 First real triage decision
    - Author OpenVEX via vexctl for a real finding, attach with cosign attest, entry in `triage/LOG.md`; or fix-bump PR when a fix exists
    - _Requirements: Req 6.4, Req 6.5_

- [ ] 8. Wrap-up (Day 3)
  - [ ] 8.1 valkey chart adaptation [CUT 1st if pressed]
    - As 5.3 for valkey (stateful: probes, persistence off-by-default rationale)
    - _Requirements: Req 4.1, Req 4.2, Req 4.3, Req 4.4, Req 4.7_
  - [ ] 8.2 README narrative and operating handoff
    - README: lab → catalogue arc, verification walkthrough (cosign verify, SBOM/provenance inspect), triage story
    - Confirm crons active (Renovate, rescan); `/spec-validate` + coverage check against this plan; repo stays private
    - _Requirements: Req 2.4, All (verification)_

## Requirements Coverage

| Requirement | Covered By Tasks |
|-------------|------------------|
| Req 1: Image Definition Catalogue | 2.1, 2.2, 3.1, 3.2, 5.1, 5.2, 1.2 |
| Req 2: Image Build and Private Release | 3.3, 8.2 |
| Req 3: Upstream Version Tracking | 3.2, 4.1, 4.2, 4.3, 5.1, 5.2 |
| Req 4: Helm Chart Adaptation | 1.1, 5.3, 5.4, 5.5, 8.1 |
| Req 5: Go Integration Tests | 6.1, 6.2, 6.3, 6.4, 6.5 |
| Req 6: CVE Triage | 7.1, 7.2, 7.3 |
| Req 7: Conventions and Review | 1.1, 1.2 |
| Req 8: Operating Environment | 2.1, 3.3, 4.2, 6.5, 7.2 |
