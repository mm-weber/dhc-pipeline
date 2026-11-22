# Requirements Document — dhc-pipeline (v2)

## Introduction

dhc-pipeline is a miniature DHI-style hardened-image catalogue that mirrors the day-to-day responsibilities of a Docker Hardened Images engineering role: authoring declarative image definitions, adapting upstream Helm charts to hardened non-root images, tracking upstream releases automatically, validating behavior with Go-based integration tests on real Kubernetes, and recording vulnerability decisions in a unified triage ledger compiled into portable VEX artifacts. It is built in three workdays as a skill-building project using real industry tooling (BuildKit, Renovate, Ginkgo/kind, Trivy, Grype, govulncheck, OpenVEX, Kyverno), then left operating so that automated activity — Renovate pull requests, scheduled rescans, expiry and CVE issues — accumulates unattended. Triage decisions themselves remain a human responsibility; the system queues them visibly rather than making them. Repository and registry images remain private until explicitly released; metadata disclosed by keyless signing to the public transparency log is an accepted exception (see Requirement 2).

### Components

| Component | Responsibility |
|---|---|
| Catalogue | The set of declarative image definition files |
| CI Pipeline | All pull-request-triggered checks: schema validation, lint, convention checks, ledger validation |
| Build Pipeline | Post-merge and PR image builds, signing, attestation, registry pushes |
| Scan Gate | PR-time vulnerability check that blocks merge on uncovered findings |
| Scan Pipeline | Scheduled (daily) rescans, second-opinion scans, issue creation, expiry reporting |
| Triage Ledger | Append-only decision records under `triage/ledger/` |
| Ledger Compiler | Tooling that renders ledger records into per-image OpenVEX documents and the Scan Gate suppression set |
| Triage Process | The human activity of deciding and recording treatments |
| Renovate Automation | Self-hosted upstream version tracking |
| Chart Adaptation | Overrides and first-party charts adapting workloads to hardened images |
| Test Suite | Ginkgo-based integration tests on kind |
| Repository | The GitHub repository and its settings |

### Risk-treatment model

Every HIGH or CRITICAL finding must end in exactly one recorded outcome. The five ledger treatments map to the four classical risk treatments plus the factual case:

| Ledger treatment | Risk treatment | Effect |
|---|---|---|
| `not_affected` | — (no risk exists) | Compiled to an OpenVEX `not_affected` statement; suppresses the finding |
| `remediate` | Mitigate (remove) | Version-bump or rebuild PR; compiled to `fixed` once the fix ships |
| `avoid` | Avoid | Definition change eliminating the exposure; never suppresses — the finding must vanish from scans |
| `accept` | Accept | Time-boxed suppression with owner and expiry |
| `transfer` | Transfer | Time-boxed suppression referencing an upstream report |

A mitigation is recorded as `remediate` where a fix version or rebuild removes the finding; as `not_affected` with justification `inline_mitigations_already_exist` where an in-image control eliminates exploitability; and as `accept` (with the mitigation described) where residual exploitability remains.

---

## Requirement 1: Image Definition Catalogue

**Objective:** As a catalogue maintainer, I want declarative definition files for four archetypal images, so that builds are reproducible, reviewable, and mechanically extensible.

### Acceptance Criteria

1.1 THE Catalogue SHALL contain definition files for four components: hardened-app, cert-manager (controller, webhook, and cainjector images), grafana, and valkey.
1.2 THE Catalogue SHALL pin every base image reference by sha256 digest.
1.3 THE Catalogue SHALL pin every upstream source reference by git ref plus content checksum.
1.4 THE Catalogue SHALL define a non-root runtime account with UID 65532 for every runtime image.
1.5 WHEN a pull request modifies a definition file THE CI Pipeline SHALL validate schema conformance and pinning conventions before merge.
1.6 IF a definition references a floating tag THEN THE CI Pipeline SHALL fail validation with a message naming that reference.
1.7 WHERE Docker's dhi.io/build frontend produces working builds outside Docker infrastructure THE Catalogue SHALL author definitions in native DHI syntax.
1.8 IF a DHI frontend spike does not produce a working build within a three-hour timebox THEN THE Catalogue SHALL adopt DHI-style YAML definitions rendered to multi-stage Dockerfiles by thin glue tooling.
1.9 WHERE a definition builds Go binaries THE Catalogue SHALL record the build flags and tags used, so that govulncheck source-mode analysis (Requirement 6) can reproduce the build configuration.

## Requirement 2: Image Build and Private Release

**Objective:** As a catalogue maintainer, I want merged definitions built and released automatically with supply-chain attestations, so that every published image is verifiable.

### Acceptance Criteria

2.1 WHEN a definition change merges to main THE Build Pipeline SHALL build affected images for linux/amd64 and linux/arm64.
2.2 WHEN an image build succeeds THE Build Pipeline SHALL push resulting images to ghcr.io/mm-weber/dhc with a cosign keyless signature, an SPDX SBOM, BuildKit provenance, and the compiled OpenVEX document for that image (Requirement 6) attached.
2.3 THE Build Pipeline SHALL derive image tags from upstream semantic versions following DHI naming convention (semver, base OS, and variant segments).
2.4 WHILE public release remains disabled THE Repository SHALL keep source code and registry image content private. The metadata disclosed to the public Rekor transparency log by keyless signing — repository name, image digest, and signing identity — is an accepted and documented exception to this privacy posture.
2.5 IF an image build fails THEN THE Build Pipeline SHALL publish no artifacts from that run and report each failing step in pull request checks.

## Requirement 3: Upstream Version Tracking

**Objective:** As a catalogue maintainer, I want automated upstream release tracking, so that version bumps arrive as reviewable pull requests without manual watching.

### Acceptance Criteria

3.1 THE Renovate Automation SHALL run self-hosted via GitHub Actions at least once every six hours.
3.2 WHEN an upstream release matches a definition's version policy THE Renovate Automation SHALL open a pull request updating pinned ref, checksum, and derived tags.
3.3 WHEN multiple images share one upstream monorepo THE Renovate Automation SHALL group their bumps into a single pull request.
3.4 WHEN an upstream release increments a major version THE Renovate Automation SHALL stage it behind Dependency Dashboard approval instead of opening an automatic pull request.
3.5 WHERE a pull request contains only digest updates within a patch release THE Renovate Automation SHALL enable automerge gated on CI success.
3.6 WHEN THE Catalogue is initialized THE Catalogue SHALL pin each upstream at least one release behind its latest available version. The resulting known findings are handled by the bootstrap procedure in Requirement 6 (6.17) before the first merge, so that the Scan Gate is enforcing from the first commit.

## Requirement 4: Helm Chart Adaptation

**Objective:** As a catalogue maintainer, I want all workloads deployed through charts adapted to hardened images through overrides, so that upstream stays unmodified, every deviation is explicit, and all four components share one deployment and test path.

### Acceptance Criteria

4.1 THE Chart Adaptation SHALL consume each upstream chart (cert-manager, grafana, valkey) at a pinned version without modifying upstream templates.
4.2 THE Repository SHALL provide a minimal first-party Helm chart for hardened-app, subject to the same adaptation, policy, and test requirements as the adapted upstream charts.
4.3 THE Chart Adaptation SHALL override image references to digest-pinned Catalogue images.
4.4 THE Chart Adaptation SHALL enforce restricted Pod Security Standard settings: runAsNonRoot true, UID and GID 65532, readOnlyRootFilesystem true, allowPrivilegeEscalation false, all capabilities dropped, and seccompProfile RuntimeDefault.
4.5 WHERE a workload requires writable filesystem paths THE Chart Adaptation SHALL mount emptyDir volumes at those paths.
4.6 IF an upstream chart assumes shell utilities absent from a runtime image THEN THE Chart Adaptation SHALL document a compat-variant decision in that chart's README.
4.7 WHEN a chart renders in CI THE CI Pipeline SHALL evaluate rendered manifests against Kyverno policies requiring digest pinning, allowed registries, and non-root execution.
4.8 THE Chart Adaptation SHALL document every deviation from upstream defaults with its rationale in a per-chart README.

## Requirement 5: Go Integration Tests on Real Kubernetes

**Objective:** As a catalogue maintainer, I want Go-based integration tests against a real cluster, so that hardening claims are verified on live workloads rather than rendered YAML alone.

### Acceptance Criteria

5.1 THE Test Suite SHALL use Ginkgo v2 with Gomega and sigs.k8s.io/e2e-framework against ephemeral kind clusters.
5.2 WHEN a pull request affects an image or chart THE Test Suite SHALL install each affected chart — cert-manager, grafana, valkey, or the first-party hardened-app chart — on a kind cluster in CI.
5.3 WHEN a chart install completes THE Test Suite SHALL assert workload pods reach Ready within five minutes.
5.4 WHEN pods are Ready THE Test Suite SHALL assert live pod securityContext matches restricted profile settings, including UID 65532 and read-only root filesystem.
5.5 WHEN pods are Ready THE Test Suite SHALL execute a per-component functional probe: cert-manager issues a Certificate, grafana answers HTTP health checks, valkey serves SET and GET operations, and hardened-app returns HTTP 200.
5.6 WHEN a pull request bumps a component version THE Test Suite SHALL verify an upgrade from currently pinned version to proposed version.
5.7 IF any assertion fails THEN THE Test Suite SHALL fail its CI check and preserve cluster diagnostic logs as workflow artifacts.

## Requirement 6: CVE Triage With a Unified Decision Ledger

**Objective:** As a catalogue maintainer, I want every vulnerability decision recorded once in an append-only ledger and compiled into scanner-consumable artifacts, so that all four risk treatments — accept, avoid, transfer, mitigate — plus factual not-affected determinations are auditable, portable, and mechanically enforced.

### The ledger

6.1 THE Triage Ledger SHALL consist of schema-validated YAML records under `triage/ledger/`, one record per decision, each carrying: a unique identifier, the target image, the vulnerability identifier, a treatment, a decision timestamp, an owner, and a rationale.
6.2 THE Triage Ledger SHALL admit exactly five treatments: `not_affected`, `remediate`, `avoid`, `accept`, and `transfer`.
6.3 THE Triage Ledger SHALL be append-only: WHEN a decision changes THE Triage Process SHALL add a new record for the same (image, vulnerability) pair, and the record with the latest decision timestamp SHALL supersede earlier records for compilation purposes.
6.4 IF a pull request modifies or deletes an existing ledger record THEN THE CI Pipeline SHALL fail validation.
6.5 WHERE a treatment is `accept` or `transfer` THE record SHALL additionally carry: a justification for why avoidance and remediation were unavailable, an expiry date no more than 90 days after the decision timestamp, and — for `transfer` — a reference to the upstream report or advisory. IF any of these fields is missing or the expiry exceeds 90 days THEN THE CI Pipeline SHALL fail validation.
6.6 WHERE a treatment is `not_affected` THE record SHALL carry an OpenVEX justification and, where that justification is `vulnerable_code_not_in_execute_path`, the evidence required by 6.14.

### Compilation

6.7 WHEN an image build succeeds THE Ledger Compiler SHALL render, from the unsuperseded records for that image: (a) an OpenVEX document containing all `not_affected` statements and all `fixed` statements, with each product identified by a pkg:oci package URL whose repository matches the published repository and whose version is that build's sha256 digest; and (b) a suppression set derived from unexpired `accept` and `transfer` records for consumption by the Scan Gate.
6.8 THE Ledger Compiler SHALL emit a `fixed` statement for a vulnerability WHEN a `remediate` record exists for it AND the current build no longer contains the finding; the `fixed` statement's product SHALL carry the digest of the first build in which the finding is absent.
6.9 THE compiled OpenVEX documents and suppression set SHALL be generated artifacts. IF a scanner ignore file or VEX document exists in the repository that is not compiler output, or IF regenerating the compiler output from the ledger produces a result that differs from the committed output, THEN THE CI Pipeline SHALL fail validation.
6.10 WHEN an image definition is removed from the Catalogue THE Repository SHALL retain that image's ledger records marked as retired; THE Ledger Compiler SHALL exclude retired records from compilation; and THE CI Pipeline SHALL NOT fail validation on retired records referencing the removed definition.

### The gate

6.11 WHEN a pull request builds an image THE Scan Gate SHALL run Trivy against the built image with the compiled OpenVEX document and suppression set applied, and SHALL fail on any HIGH or CRITICAL finding not covered by a `not_affected` statement, a `fixed` statement, or an unexpired `accept` or `transfer` record. VEX statements with status `affected` or `under_investigation` SHALL NOT count as coverage.
6.12 WHEN an `accept` or `transfer` record passes its expiry date without a superseding record THE Scan Gate SHALL count every finding it covers as uncovered.
6.13 WHERE a treatment is `avoid` THE Triage Process SHALL produce a definition-change pull request eliminating the exposure, and THE Scan Gate SHALL verify the finding is absent from the rebuilt image. `avoid` records SHALL NOT enter the suppression set.

### Reachability evidence (govulncheck)

6.14 WHERE a `not_affected` record uses justification `vulnerable_code_not_in_execute_path` THE record SHALL cite: (a) a govulncheck source-mode analysis at the pinned upstream ref, run with the build flags and tags recorded in the definition (1.9), reporting the vulnerable symbol unreachable at symbol level; and (b) a govulncheck binary-mode confirmation that the module versions present in the shipped binary match those analyzed in (a).
6.15 WHEN a pull request builds an image containing Go binaries THE Scan Pipeline SHALL run govulncheck in binary mode against each Go binary in that image and SHALL run govulncheck in source mode at the pinned ref for each finding under triage.
6.16 IF source-mode analysis reports a vulnerable symbol as reachable THEN THE Triage Process SHALL NOT record `not_affected` with justification `vulnerable_code_not_in_execute_path` for that finding. IF a cited analysis reports at module level only, or IF the binary-mode module set diverges from the source-mode analysis, THEN THE CI Pipeline SHALL treat the evidence as unmeasured and fail validation of any record citing it.

### Bootstrap

6.17 WHEN THE Catalogue is initialized THE Triage Process SHALL, before the first definition merge, scan the upstream images at the versions pinned per 3.6 and record a ledger decision for every HIGH and CRITICAL finding; the first merge SHALL include this baseline ledger; and THE Scan Gate SHALL be enforcing from the first merge with no warn-only period.

### Scheduled operations

6.18 THE Scan Pipeline SHALL rescan published images at least once per day.
6.19 WHEN a rescan finds a new HIGH or CRITICAL finding with no ledger record THE Scan Pipeline SHALL open a GitHub issue containing severity, EPSS score, KEV status, and affected images.
6.20 WHERE a CRITICAL finding exists THE Scan Pipeline SHALL obtain a second-opinion scan with Grype and SHALL record in the finding's issue whether Grype confirms it. IF Grype reports a HIGH or CRITICAL finding that Trivy does not THEN THE Scan Pipeline SHALL open an issue for it; Grype-only findings SHALL NOT block merges.
6.21 WHEN a scheduled rescan runs THE Scan Pipeline SHALL open or update a renewal issue for every `accept` or `transfer` record expiring within 14 days, and SHALL fail its own workflow run WHILE any expired `accept` or `transfer` record lacks a superseding record.
6.22 A renewal SHALL be recorded as a new ledger record with fresh rationale and expiry per 6.3; expiry dates SHALL NOT be extended by editing an existing record.
6.23 WHEN a triage decision concludes `remediate` THE Triage Process SHALL produce a version-bump or rebuild pull request.

## Requirement 7: Conventions and Review Enforcement

**Objective:** As a catalogue maintainer, I want conventions codified and enforced mechanically, so that drift is caught by tooling and review attention goes to substance.

### Acceptance Criteria

7.1 THE Repository SHALL contain a CONVENTIONS.md defining naming, pinning, variant, override, and ledger-record rules, including the treatment taxonomy of 6.2.
7.2 WHEN a pull request opens THE CI Pipeline SHALL run yamllint, definition validation, and ledger schema validation on changed YAML files.
7.3 THE Repository SHALL provide a pull request template prompting for requirement references and convention compliance.
7.4 IF a pull request violates a codified convention THEN THE CI Pipeline SHALL fail with a message identifying that convention.
7.5 WHEN a workflow installs a third-party executable THE CI Pipeline SHALL pin that executable to an exact version and SHALL verify its download against a checksum recorded in this repository.
7.6 IF a pinned third-party executable has a newer released version THEN THE Renovate Automation SHALL open a pull request updating that pin.

## Requirement 8: Operating Environment Constraints

**Objective:** As the project owner, I want heavy operations to run where network access exists, so that development in a restricted devcontainer stays unblocked.

### Acceptance Criteria

8.1 THE Build Pipeline, Scan Gate, Scan Pipeline, and Test Suite SHALL execute image builds, kind clusters, registry pushes, and scans on GitHub Actions runners or on an operator host machine.
8.2 IF a task requires registry or internet access THEN THE Development Workflow SHALL delegate that task to GitHub Actions or an operator host instead of executing it inside a restricted devcontainer.

---

## Appendix: Revision notes (v1 → v2)

| v1 finding | Resolution |
|---|---|
| 6.1 vs 6.8 — accepted risk could never satisfy the VEX-only gate | Unified ledger; gate honors compiled VEX **or** unexpired accept/transfer records (6.11) |
| "Covered by a VEX statement" included status `affected` | Coverage restricted to `not_affected` and `fixed`; `affected`/`under_investigation` explicitly excluded (6.11) |
| Versionless product purls broke pkg:oci conformance, Trivy matching, and supersession | Products digest-pinned per build, re-rendered by the compiler; supersession moved to ledger level per (image, vulnerability) (6.3, 6.7) |
| Versionless product + subcomponent = eternal blanket suppression | Per-digest rendering means every rebuild re-derives coverage from current, unsuperseded records |
| 6.17 vs 6.22 — retiring an image destroyed or broke triage history | Retired-record mechanism (6.10) |
| No cleanup duty when reachability flipped | Divergence and reachability invalidate cited evidence and fail CI (6.16); append-only supersession replaces the decision |
| govulncheck vs stripped binaries; GO-ID/CVE mapping | Dual-mode evidence model: source-mode reachability + binary-mode module confirmation (6.14–6.16); build config recorded in definitions (1.9) |
| Grype second opinion had no consumer | Confirmation recorded on issues; Grype-only findings raise issues, never block (6.20) |
| Expiry only enforced at PR time | Daily workflow fails while expired records lack supersession; renewal issues at T−14 (6.21) |
| "Unattended" intro vs manual triage with ≤90-day expiries | Intro amended: automation accumulates unattended; decisions queue for the maintainer |
| Keyless signing leaked metadata to public Rekor, contradicting 2.4 | Disclosure accepted and documented (2.4) |
| Bootstrap deadlock: stale initial pins vs hard gate | Ledger-before-build: baseline triage lands with the first merge; gate enforcing from commit one (3.6, 6.17) |
| hardened-app had no chart but required chart tests | Minimal first-party chart under the same rules (4.2, 5.2) |
| Actor-name drift | Components table; every SHALL assigned to one component |