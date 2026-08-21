# Requirements Document

## Introduction

dhc-pipeline is a miniature DHI-style hardened-image catalogue that mirrors the day-to-day
responsibilities of a Docker Hardened Images engineering role: authoring declarative image
definitions, adapting upstream Helm charts to hardened non-root images, tracking upstream
releases automatically, validating behavior with Go-based integration tests on real Kubernetes,
and recording CVE triage decisions as portable VEX artifacts. It was built in an initial
three-workday MVP as a skill-building project using real industry tooling (BuildKit, Renovate,
Ginkgo/kind, Trivy, OpenVEX), then left operating so maintainer history accumulates unattended —
the operating period (2026-07-21 → 2026-08-13) is what grew Req 6.7–6.34 and the tasks-8 series.
Repository and registry images remained private until the public release on 2026-08-13 (MIT).

A production-readiness review on 2026-08-21
(`reviews/2026-08-21-production-readiness-critique.md`) dispositioned thirteen findings under
one promise, a transparency catalogue: every published digest is signed by a pinned identity,
every known HIGH or CRITICAL finding against a published digest carries a published
machine-readable status, and time-to-decision and time-to-fix are measured and published rather
than promised. Its amendments land in dependency clusters A to D. Cluster A (findings F3, F9,
F6: the release path and the published set) added Req 1.9, Req 2.7 to 2.25 and Req 6.35 to 6.36.

## Requirements

### Requirement 1: Image Definition Catalogue

**Objective:** As a catalogue maintainer, I want declarative definition files for four archetypal images, so that builds are reproducible, reviewable, and mechanically extensible.

#### Acceptance Criteria

1. THE Catalogue SHALL contain definition files for four components: hardened-app, cert-manager (controller, webhook, and cainjector images), grafana, and valkey.
2. THE Catalogue SHALL pin every base image reference by sha256 digest.
3. THE Catalogue SHALL pin every upstream source reference by git ref plus content checksum.
4. THE Catalogue SHALL define a non-root runtime account with UID 65532 for every runtime image.
5. WHEN a pull request modifies a definition file THE CI Pipeline SHALL validate schema conformance and pinning conventions before merge.
6. IF a definition references a floating tag THEN THE CI Pipeline SHALL fail validation with a message naming that reference.
7. WHERE Docker's dhi.io/build frontend produces working builds outside Docker infrastructure THE Catalogue SHALL author definitions in native DHI syntax.
8. IF a DHI frontend spike does not produce a working build within a three-hour timebox THEN THE Catalogue SHALL adopt DHI-style YAML definitions rendered to multi-stage Dockerfiles by thin glue tooling.
9. THE Catalogue SHALL record in CONVENTIONS.md that versions of packages installed from package repositories are not pinned in definitions and that each published digest's resolved package set is recorded in its attested SPDX SBOM.

### Requirement 2: Image Build and Release

**Objective:** As a catalogue maintainer, I want merged definitions built and released automatically with supply-chain attestations, so that every published image is verifiable.

#### Acceptance Criteria

1. WHEN a definition change merges to main THE CI Pipeline SHALL build affected images for linux/amd64.
2. WHEN an image build succeeds THE CI Pipeline SHALL push resulting images to ghcr.io/mm-weber/dhc with a cosign keyless signature, an SPDX SBOM, and BuildKit provenance attached.
3. THE CI Pipeline SHALL derive image tags from upstream semantic versions following DHI naming convention (semver, base OS, and variant segments).
4. WHILE public release remains disabled THE Repository SHALL keep source and registry images private.
5. IF an image build fails THEN THE CI Pipeline SHALL publish no artifacts from that run and report each failing step in pull request checks.
6. WHILE an image for a platform remains published THE Catalogue SHALL scan that platform for HIGH and CRITICAL vulnerabilities.
7. WHEN a definition change merges to main THE CI Pipeline SHALL push each built image to ghcr.io/mm-weber/dhc by digest only and SHALL apply no tag to it before that digest's release-time scan completes.
8. WHEN an image has been pushed by digest THE CI Pipeline SHALL scan that pushed digest for HIGH and CRITICAL vulnerabilities, once per platform manifest it contains, applying every compiled VEX document and every unexpired accepted-risk exception that THE Scan Gate applies to pull requests.
9. WHEN a pushed digest's release-time scan completes THE CI Pipeline SHALL sign that digest with a cosign keyless signature, attest its SPDX SBOM and its compiled OpenVEX documents to it, and SHALL apply its definition-derived tags only after those attestations exist.
10. WHILE a digest is referenced by a catalogue tag and carries a cosign signature, an SPDX SBOM attestation and an OpenVEX attestation THE Catalogue SHALL treat that digest as published.
11. IF no catalogue tag references a digest THEN THE Catalogue SHALL treat that digest as frozen: not published, not rescanned, and not re-attested.
12. IF a release-time scan reports a HIGH or CRITICAL finding covered neither by a VEX statement recording status not_affected or fixed nor by an unexpired accepted-risk exception THEN THE VEX Compiler SHALL add to that digest's compiled document an OpenVEX statement recording status under_investigation for that finding with a timestamp, and THE CI Pipeline SHALL complete that release.
13. WHERE a declared fail-closed release setting is enabled THE CI Pipeline SHALL apply no tag to, and attest nothing for, a digest whose release-time scan reports a finding covered neither by a VEX statement recording status not_affected or fixed nor by an unexpired accepted-risk exception.
14. THE CI Pipeline SHALL rebuild every definition on a declared schedule at least once per day.
15. WHEN a scheduled rebuild produces an image whose resolved package set, taken as package name and version per platform, equals that of a published digest carrying that image's full release tag THE CI Pipeline SHALL discard that image and publish nothing from it.
16. WHEN a scheduled rebuild produces an image whose resolved package set differs from that of a published digest carrying that image's full release tag THE CI Pipeline SHALL publish that image through criteria 2.7 to 2.9 and SHALL report both digests' package-set difference in its job summary.
17. WHERE a declared publish policy is set to always THE CI Pipeline SHALL publish every scheduled rebuild through criteria 2.7 to 2.9 regardless of package-set equality.
18. WHEN THE Scan Pipeline rescans a published digest THE Scan Pipeline SHALL scan every platform manifest that digest's index contains.
19. IF a built index contains a platform manifest that its release-time scan did not scan THEN THE CI Pipeline SHALL apply no tag to that index.
20. WHILE release-time scans and scheduled rescans cover every platform manifest of every published index THE CI Pipeline SHALL build affected images for every platform their definitions declare.
21. THE Scan Pipeline SHALL verify at least once per day that every catalogue repository under ghcr.io/mm-weber/dhc returns a pull token to an unauthenticated request and SHALL report every repository that does not as a failure of that run.
22. WHEN a catalogue tag references an index containing a platform manifest that neither a release-time scan nor a scheduled rescan has scanned THE Catalogue SHALL re-point that tag to its scanned manifest digest and SHALL record that tag, its previous index digest and its new digest in triage/LOG.md.
23. THE Repository SHALL publish under policies/ a verification policy that admits an image from ghcr.io/mm-weber/dhc solely on a cosign keyless signature whose certificate issuer is https://token.actions.githubusercontent.com and whose certificate identity is exactly this repository's build workflow or rescan workflow at refs/heads/main, together with an SPDX SBOM attestation and an OpenVEX attestation from those identities.
24. WHEN THE Scan Pipeline runs its daily checks THE Scan Pipeline SHALL apply that verification policy to every published digest and to one unsigned control image, and SHALL report any published digest that policy rejects or any control image that policy admits as a failure of that run.
25. THE Repository SHALL state in its consumer verification instructions which certificate issuer and which exact certificate identities its verification policy admits, each identity anchored to its workflow file and ref.

### Requirement 3: Upstream Version Tracking

**Objective:** As a catalogue maintainer, I want automated upstream release tracking, so that version bumps arrive as reviewable pull requests without manual watching.

#### Acceptance Criteria

1. THE Renovate Automation SHALL run self-hosted via GitHub Actions at least once every six hours.
2. WHEN an upstream release matches a definition's version policy THE Renovate Automation SHALL open a pull request updating pinned ref, checksum, and derived tags.
3. WHEN multiple images share one upstream monorepo THE Renovate Automation SHALL group their bumps into a single pull request.
4. WHEN an upstream release increments a major version THE Renovate Automation SHALL stage it behind Dependency Dashboard approval instead of opening an automatic pull request.
5. WHERE a pull request contains only digest updates within a patch release THE Renovate Automation SHALL enable automerge gated on CI success.
6. WHEN THE Catalogue is initialized THE Catalogue SHALL pin each upstream at least one release behind its latest available version.

### Requirement 4: Helm Chart Adaptation

**Objective:** As a catalogue maintainer, I want upstream charts adapted to hardened images through overrides, so that upstream stays unmodified and every deviation is explicit and reviewable.

#### Acceptance Criteria

1. THE Chart Adaptation SHALL consume each upstream chart (cert-manager, grafana, valkey) at a pinned version without modifying upstream templates.
2. THE Chart Adaptation SHALL override image references to digest-pinned Catalogue images.
3. THE Chart Adaptation SHALL enforce restricted Pod Security Standard settings: runAsNonRoot true, UID and GID 65532, readOnlyRootFilesystem true, allowPrivilegeEscalation false, all capabilities dropped, and seccompProfile RuntimeDefault.
4. WHERE a workload requires writable filesystem paths THE Chart Adaptation SHALL mount emptyDir volumes at those paths.
5. IF an upstream chart assumes shell utilities absent from a runtime image THEN THE Chart Adaptation SHALL document a compat-variant decision in that chart's README.
6. WHEN a chart renders in CI THE Policy Gate SHALL evaluate rendered manifests against Kyverno policies requiring digest pinning, allowed registries, and non-root execution.
7. THE Chart Adaptation SHALL document every deviation from upstream defaults with its rationale in a per-chart README.

### Requirement 5: Go Integration Tests on Real Kubernetes

**Objective:** As a catalogue maintainer, I want Go-based integration tests against a real cluster, so that hardening claims are verified on live workloads rather than rendered YAML alone.

#### Acceptance Criteria

1. THE Test Suite SHALL use Ginkgo v2 with Gomega and sigs.k8s.io/e2e-framework against ephemeral kind clusters.
2. WHEN a pull request affects an image or chart THE Test Suite SHALL install each affected chart on a kind cluster in CI.
3. WHEN a chart install completes THE Test Suite SHALL assert workload pods reach Ready within five minutes.
4. WHEN pods are Ready THE Test Suite SHALL assert live pod securityContext matches restricted profile settings, including UID 65532 and read-only root filesystem.
5. WHEN pods are Ready THE Test Suite SHALL execute a per-component functional probe: cert-manager issues a Certificate, grafana answers HTTP health checks, valkey serves SET and GET operations, and hardened-app returns HTTP 200.
6. WHEN a pull request bumps a component version THE Test Suite SHALL verify an upgrade from currently pinned version to proposed version.
7. IF any assertion fails THEN THE Test Suite SHALL fail its CI check and preserve cluster diagnostic logs as workflow artifacts.

### Requirement 6: CVE Triage With Recorded Decisions

**Objective:** As a catalogue maintainer, I want scan findings turned into recorded, portable decisions, so that vulnerability handling is auditable instead of anecdotal.

#### Acceptance Criteria

1. WHEN a pull request builds an image THE Scan Gate SHALL run Trivy and fail on every HIGH or CRITICAL finding covered neither by a VEX statement recording status not_affected or fixed nor by an unexpired exception under triage/accepted-risk/.
2. THE Scan Pipeline SHALL rescan published images at least once per day.
3. WHEN a rescan finds a new HIGH or CRITICAL CVE THE Scan Pipeline SHALL open a GitHub issue containing severity, EPSS score, KEV status, and affected images.
4. WHEN a triage decision concludes not-affected THE Triage Process SHALL record an OpenVEX statement under triage/ and attach it to affected images as an attestation.
5. WHEN a triage decision concludes fix THE Triage Process SHALL produce a version-bump or rebuild pull request.
6. WHERE a CRITICAL finding exists THE Scan Pipeline SHALL obtain a second-opinion scan with Grype.
7. WHEN a triage decision concludes accepted risk or upstream transfer THE Triage Process SHALL record a time-boxed exception under triage/accepted-risk/ carrying a treatment, an owner, a reference to its reasoning in triage/LOG.md, a justification for why avoidance and remediation were unavailable, and an expiry date.
8. THE Triage Process SHALL NOT record accepted risk or upstream transfer as a VEX statement.
9. WHEN an accepted-risk exception has passed its expiry date THE Scan Gate SHALL count every finding it names as uncovered.
10. WHEN a daily rescan runs THE Scan Pipeline SHALL report every accepted-risk exception that has expired or that expires within 14 days.
11. IF an accepted-risk exception omits its treatment, owner, reasoning reference, unavailability justification, or expiry date, or sets an expiry date more than 90 days ahead, THEN THE CI Pipeline SHALL fail validation.
12. IF a Trivy ignore file exists outside triage/accepted-risk/ THEN THE CI Pipeline SHALL fail validation.
13. WHEN a pull request builds an image THE Scan Pipeline SHALL run govulncheck in binary mode against every Go binary in that image and SHALL report, for each finding, whether the vulnerable symbol is reachable.
14. IF govulncheck reports a vulnerable symbol as reachable in a binary THEN THE Triage Process SHALL NOT record that finding as not_affected with justification vulnerable_code_not_in_execute_path for that image.
15. WHERE a triage decision records not_affected with justification vulnerable_code_not_in_execute_path THE Triage Process SHALL cite in triage/LOG.md a govulncheck result for that binary at symbol or package level.
16. IF govulncheck reports a finding at module level only THEN THE Triage Process SHALL treat that result as unmeasured and SHALL NOT cite it as evidence of unreachability.
17. IF a VEX statement names a product that is not an OCI package URL for an existing image definition THEN THE CI Pipeline SHALL fail validation.
18. IF a VEX statement's product identifier declares a repository other than that image definition's published repository THEN THE CI Pipeline SHALL fail validation.
19. IF a VEX statement's subcomponent identifier carries a version THEN THE CI Pipeline SHALL fail validation.
20. IF a VEX source statement's product identifier carries a version that is not a published tag of any image definition publishing that product's repository THEN THE CI Pipeline SHALL fail validation.
21. IF a VEX source statement records status fixed AND its product identifier carries no version THEN THE CI Pipeline SHALL fail validation.
22. WHEN a triage decision supersedes an earlier VEX statement THE Triage Process SHALL retain that earlier statement in its document and SHALL add a superseding statement carrying a later timestamp.
23. WHEN a triage decision records an accepted-risk exception THE Triage Process SHALL record in that exception every binary path to which that exception applies.
24. IF an accepted-risk exception records no binary path THEN THE CI Pipeline SHALL fail validation.
25. IF two accepted-risk exceptions in one file record an identical vulnerability identifier AND name an identical binary path THEN THE CI Pipeline SHALL fail validation.
26. WHEN a scan applies accepted-risk exceptions THE Scan Gate SHALL report every exception that suppressed no finding.
27. WHEN a scan reports a suppressed finding THE Scan Gate SHALL identify which binary that finding was suppressed in.
28. WHEN a scan applies VEX statements THE Scan Gate SHALL apply compiled documents in place of source documents.
29. WHEN a VEX document is compiled THE VEX Compiler SHALL set every product identifier in that document to a sha256 digest of an image being scanned.
30. IF a VEX source statement's product identifier carries a version that is not a tag of an image being scanned THEN THE VEX Compiler SHALL omit that statement from compiled output.
31. IF a VEX source statement's product identifier carries no version AND that statement's status notes record no reason its claim holds for every release THEN THE CI Pipeline SHALL fail validation.
32. WHEN a VEX document is compiled THE VEX Compiler SHALL record every statement omitted from that document and a digest that compilation used.
33. WHEN a scheduled rescan applies VEX statements THE Scan Pipeline SHALL report every statement that compilation omitted.
34. WHEN a VEX document is attested to an image THE CI Pipeline SHALL attest a document compiled for that image's digest.
35. THE Scan Gate SHALL NOT count a VEX statement recording status under_investigation as coverage of a finding.
36. WHEN a VEX document is compiled for an image index containing more than one platform manifest THE VEX Compiler SHALL produce product identifiers covering that index's digest and every scanned platform manifest digest.

### Requirement 7: Conventions and Review Enforcement

**Objective:** As a catalogue maintainer, I want conventions codified and enforced mechanically, so that drift is caught by tooling and review attention goes to substance.

#### Acceptance Criteria

1. THE Repository SHALL contain a CONVENTIONS.md defining naming, pinning, variant, and override rules.
2. WHEN a pull request opens THE CI Pipeline SHALL run yamllint and definition validation on changed YAML files.
3. THE Repository SHALL provide a pull request template prompting for requirement references and convention compliance.
4. IF a pull request violates a codified convention THEN THE CI Pipeline SHALL fail with a message identifying that convention.
5. WHEN a workflow installs a third-party executable THE CI Pipeline SHALL pin that executable to an exact version and SHALL verify its download against a checksum recorded in this repository.
6. IF a pinned third-party executable has a newer released version THEN THE Upstream Tracking SHALL open a pull request updating that pin.

### Requirement 8: Operating Environment Constraints

**Objective:** As the project owner, I want heavy operations to run where network access exists, so that development in a restricted devcontainer stays unblocked.

#### Acceptance Criteria

1. THE CI Pipeline SHALL execute image builds, kind clusters, registry pushes, and scans on GitHub Actions runners or on an operator host machine.
2. IF a task requires registry or internet access THEN THE Development Workflow SHALL delegate that task to GitHub Actions or an operator host instead of executing it inside a restricted devcontainer.
