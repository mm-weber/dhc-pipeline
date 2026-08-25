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
F6: the release path and the published set) added Req 1.9, Req 2.7 to 2.26, Req 6.35 to 6.37 and Req 7.7 to 7.10, and amended Req 2.1 and 2.2. Cluster B (findings F5, F4 and the issue-closing half of F13: statuses and clocks) added Req 6.38 to 6.60 and amended Req 2.6, 2.8, 6.1, 6.3, 6.7, 6.8, 6.10, 6.11 and 6.35; its spikes are ADR 0003 and ADR 0004. Cluster C (findings F2, F10, F8, F13 ii and iii, F12 d: upstream trust) added Req 1.10 to 1.12, Req 3.7 to 3.12 and Req 4.8 to 4.9, and amended Req 1.3, 3.5 and 4.5; its spike record is the 2026-08-25 amendment to ADR 0002.

## Requirements

### Requirement 1: Image Definition Catalogue

**Objective:** As a catalogue maintainer, I want declarative definition files for four archetypal images, so that builds are reproducible, reviewable, and mechanically extensible.

#### Acceptance Criteria

1. THE Catalogue SHALL contain definition files for four components: hardened-app, cert-manager (controller, webhook, and cainjector images), grafana, and valkey.
2. THE Catalogue SHALL pin every base image reference by sha256 digest.
3. THE Catalogue SHALL pin every upstream source reference by an exact version reference plus content checksum: a git ref plus commit checksum for a compile-from-source archetype, and a versioned artifact URL plus per-architecture content checksum for a repackage archetype.
4. THE Catalogue SHALL define a non-root runtime account with UID 65532 for every runtime image.
5. WHEN a pull request modifies a definition file THE CI Pipeline SHALL validate schema conformance and pinning conventions before merge.
6. IF a definition references a floating tag THEN THE CI Pipeline SHALL fail validation with a message naming that reference.
7. WHERE Docker's dhi.io/build frontend produces working builds outside Docker infrastructure THE Catalogue SHALL author definitions in native DHI syntax.
8. IF a DHI frontend spike does not produce a working build within a three-hour timebox THEN THE Catalogue SHALL adopt DHI-style YAML definitions rendered to multi-stage Dockerfiles by thin glue tooling.
9. THE Catalogue SHALL record in CONVENTIONS.md that versions of packages installed from package repositories are not pinned in definitions and that each platform manifest's resolved package set is recorded in the SPDX and CycloneDX SBOMs attested to that manifest.
10. THE Catalogue SHALL declare in each definition an upstream authenticity class naming its verification signal: signed-tag, signed-commit, cross-origin-checksum, or none.
11. IF a definition declares authenticity class none or declares no class THEN THE CI Pipeline SHALL fail validation naming that definition.
12. IF a definition names a dhi.io package repository whose path is not of shape dhi.io/apk/(distro)/(release)/main or dhi.io/deb/(distro)/main THEN THE CI Pipeline SHALL fail validation naming that repository.

### Requirement 2: Image Build and Release

**Objective:** As a catalogue maintainer, I want merged definitions built and released automatically with supply-chain attestations, so that every published image is verifiable.

**Terms used below.** A *catalogue tag* is a tag derived from a definition under criterion 2.3; the `sha256-<digest>.sig` and `sha256-<digest>.att` tags that cosign stores beside an image are not catalogue tags. A *full release tag* is the catalogue tag carrying the complete upstream version (the third of a definition's three tags, for example `13.1.3-alpine3.23`). A *platform manifest* is a manifest that an image index lists with a platform other than `unknown/unknown` and without a `vnd.docker.reference.type` annotation; BuildKit's attestation manifests are therefore not platform manifests. The *decision aperture* is the set of severities that the catalogue policy file's triage section names as requiring a recorded decision (HIGH and CRITICAL in this catalogue; a fork widens it by editing the list). An *uncovered finding* is a finding within that decision aperture covered neither by a VEX statement recording status not_affected or fixed nor by an unexpired accepted-risk exception; it is what criterion 6.1 fails on. A *supported digest* is a digest referenced by a tag its definition currently lists in `tags:`; a tag-referenced digest outside that set is *superseded*: it keeps daily scans, attestations and verification, and sits outside the scope of issues, clocks and public counts, because a frozen digest's content never changes and its findings accrue by design (the industry-wide pattern recorded in `data/cve-finding-lifecycle-vs-immutable-tags-2026-08-24.md`).

#### Acceptance Criteria

1. WHEN a definition change merges to main THE CI Pipeline SHALL build affected images for every platform their definitions declare.
2. WHEN an image build succeeds THE CI Pipeline SHALL push its image to ghcr.io/mm-weber/dhc with BuildKit provenance attached and SHALL sign and attest it under criterion 2.9.
3. THE CI Pipeline SHALL derive image tags from upstream semantic versions following DHI naming convention (semver, base OS, and variant segments).
4. WHILE public release remains disabled THE Repository SHALL keep source and registry images private.
5. IF an image build fails THEN THE CI Pipeline SHALL publish no artifacts from that run and report each failing step in pull request checks.
6. WHILE an image for a platform remains published THE Catalogue SHALL scan that platform for findings within that decision aperture.
7. WHEN THE CI Pipeline builds an image on main for release, from a merged definition change, a declared schedule or a manual dispatch, THE CI Pipeline SHALL push that image to ghcr.io/mm-weber/dhc by digest only and SHALL apply no tag to it before that digest's release-time scan completes.
8. WHEN an image has been pushed by digest THE CI Pipeline SHALL scan that pushed digest for findings within that decision aperture, once per platform manifest it contains, applying every compiled VEX document and every unexpired accepted-risk exception that THE Scan Gate applies to pull requests.
9. WHEN a pushed digest's release-time scan completes with a report for every platform manifest and criterion 2.13 does not withhold that digest THE CI Pipeline SHALL sign that digest and every platform manifest it contains with a cosign keyless signature, attest an SPDX SBOM, a CycloneDX SBOM and that manifest's release-time scan report to each platform manifest, attest one compiled OpenVEX document carrying every applicable statement or none to that digest and to each platform manifest, and SHALL apply its definition-derived tags only after those signatures and attestations exist.
10. WHILE a digest is referenced by a catalogue tag and carries a cosign keyless signature, an SPDX SBOM attestation, an OpenVEX attestation and BuildKit provenance THE Catalogue SHALL treat that digest as published.
11. IF no catalogue tag references a digest THEN THE Catalogue SHALL treat that digest as frozen: not published, not rescanned, and not re-attested.
12. IF a declared fail-closed release setting is disabled AND a release-time scan reports an uncovered finding THEN THE VEX Compiler SHALL add to that digest's compiled document an OpenVEX statement recording status under_investigation for that finding, carrying that scan report's timestamp and derived from that report as criterion 2.9 attests it.
13. WHERE a declared fail-closed release setting is enabled THE CI Pipeline SHALL sign nothing, attest nothing and apply no tag for a digest whose release-time scan reports an uncovered finding, and SHALL report that finding in that run.
14. THE CI Pipeline SHALL rebuild every definition on a declared schedule at least once per day.
15. WHERE a declared publish policy is set to on-change THE CI Pipeline SHALL discard a scheduled rebuild whose canonicalised package set, taken as a sorted set of package type, name, version and package checksum per platform manifest, equals that recorded in the CycloneDX SBOMs attested to a published digest carrying its full release tag, pushing nothing, signing nothing and attesting nothing from it.
16. WHEN a scheduled rebuild produces an image whose resolved package set differs from that of a published digest carrying its full release tag, or for which no published digest carries that tag, THE CI Pipeline SHALL publish that image through criteria 2.7 to 2.9 and SHALL report in its job summary its package-set difference against any published digest carrying that tag.
17. WHERE a declared publish policy is set to always THE CI Pipeline SHALL publish every scheduled rebuild through criteria 2.7 to 2.9 regardless of package-set equality.
18. WHEN THE Scan Pipeline rescans a digest that a catalogue tag references THE Scan Pipeline SHALL scan every platform manifest of that digest, or, for a single image manifest, that digest itself.
19. IF a built index contains a platform manifest that its release-time scan did not scan THEN THE CI Pipeline SHALL apply no tag to that index.
20. THE Catalogue SHALL count toward criterion 2.10 only a signature and only attestations whose certificate identities criterion 2.23 admits for that signature or for that attestation type.
21. WHILE public release is enabled THE Scan Pipeline SHALL verify at least once per day that every catalogue repository under ghcr.io/mm-weber/dhc returns a pull token to an unauthenticated request and serves every catalogue tag's manifest to an unauthenticated request, and SHALL report every repository or tag that does not as a failure of that run.
22. THE Scan Pipeline SHALL enumerate at least once per day every catalogue tag in every catalogue repository together with each digest it references, and SHALL apply criteria 2.18, 2.21 and 2.24 to that enumeration.
23. THE Repository SHALL publish under policies/ a verification policy that admits an image from ghcr.io/mm-weber/dhc solely on a cosign keyless signature whose certificate issuer is https://token.actions.githubusercontent.com and whose certificate identity is exactly this repository's build workflow at refs/heads/main, together with an SPDX SBOM attestation from that same identity and an OpenVEX attestation from either that identity or this repository's rescan workflow at refs/heads/main.
24. WHEN a scheduled rescan runs THE Scan Pipeline SHALL apply that verification policy to every digest a catalogue tag references and to one unsigned control digest held under a catalogue repository, and SHALL report any tag-referenced digest that policy rejects or a control digest that policy admits as a failure of that run.
25. THE Repository SHALL state in its consumer verification instructions which certificate issuer and which exact certificate identities its verification policy admits for the signature and for each attestation type, each identity anchored to its workflow file and ref, and SHALL state that BuildKit provenance is attached at build time and is not verified by that policy.
26. IF a pushed digest's release-time scan produces no report for any platform manifest THEN THE CI Pipeline SHALL sign nothing, attest nothing and apply no tag for that digest, and SHALL report that failing scan in that run.

### Requirement 3: Upstream Version Tracking

**Objective:** As a catalogue maintainer, I want automated upstream release tracking, so that version bumps arrive as reviewable pull requests without manual watching.

#### Acceptance Criteria

1. THE Renovate Automation SHALL run self-hosted via GitHub Actions at least once every six hours.
2. WHEN an upstream release matches a definition's version policy THE Renovate Automation SHALL open a pull request updating pinned ref, checksum, and derived tags.
3. WHEN multiple images share one upstream monorepo THE Renovate Automation SHALL group their bumps into a single pull request.
4. WHEN an upstream release increments a major version THE Renovate Automation SHALL stage it behind Dependency Dashboard approval instead of opening an automatic pull request.
5. WHERE a pull request contains solely digest or patch updates of a compile-from-source upstream THE Renovate Automation SHALL enable automerge gated on green required checks.
6. WHEN THE Catalogue is initialized THE Catalogue SHALL pin each upstream at least one release behind its latest available version.
7. THE Renovate Automation SHALL withhold each pull request bumping a pinned third-party release version until that release has aged a declared minimum release age, at least three days in this catalogue, exempting only its docker datasource of catalogue-published digests and hand-reviewed build-layer pins.
8. WHEN a refresh task recomputes a checksum or resolves a commit for a definition's bump THE Refresh Tooling SHALL verify that definition's declared authenticity signal and SHALL write no field of a bump whose signal fails verification, reporting each such refusal naming its signal.
9. WHEN a pull request changes a repackage definition's per-architecture checksum THE CI Pipeline SHALL verify pinned value, bytes served by its download origin and its upstream's published version statement agree per architecture, failing on any disagreement naming each value.
10. THE Scan Pipeline SHALL re-verify at least once per day each definition's declared authenticity signal against its upstream origin, and SHALL report each mismatch as a failure of that run and file an issue naming it as a supply-chain signal.
11. THE Renovate Automation SHALL track each upstream chart version pinned under chart/ against its chart repository and SHALL open a pull request, never automerged, for each new chart release matching its version policy.
12. WHERE a pull request contains solely digest updates of catalogue image pins under chart/ THE Renovate Automation SHALL enable automerge gated on green required checks.

### Requirement 4: Helm Chart Adaptation

**Objective:** As a catalogue maintainer, I want upstream charts adapted to hardened images through overrides, so that upstream stays unmodified and every deviation is explicit and reviewable.

#### Acceptance Criteria

1. THE Chart Adaptation SHALL consume each upstream chart (cert-manager, grafana, valkey) at a pinned version without modifying upstream templates.
2. THE Chart Adaptation SHALL override image references to digest-pinned Catalogue images.
3. THE Chart Adaptation SHALL enforce restricted Pod Security Standard settings: runAsNonRoot true, UID and GID 65532, readOnlyRootFilesystem true, allowPrivilegeEscalation false, all capabilities dropped, and seccompProfile RuntimeDefault.
4. WHERE a workload requires writable filesystem paths THE Chart Adaptation SHALL mount emptyDir volumes at those paths.
5. IF an upstream chart assumes shell utilities absent from a runtime image THEN THE Chart Adaptation SHALL record a compat-variant decision as structured metadata carrying reason, upstream issue reference and review-by date, and SHALL document that decision in its chart's README.
6. WHEN a chart renders in CI THE Policy Gate SHALL evaluate rendered manifests against Kyverno policies requiring digest pinning, allowed registries, and non-root execution.
7. THE Chart Adaptation SHALL document every deviation from upstream defaults with its rationale in a per-chart README.
8. IF a compat decision's review-by date has passed THEN THE CI Pipeline SHALL fail validation until that decision carries a fresh review-by date from a dated re-decision.
9. THE Scan Pipeline SHALL report each lapsed compat review-by date in its daily run.

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

1. WHEN a pull request builds an image THE Scan Gate SHALL run Trivy and fail on every finding within that decision aperture covered neither by a VEX statement recording status not_affected or fixed nor by an unexpired exception under triage/accepted-risk/.
2. THE Scan Pipeline SHALL rescan published images at least once per day.
3. WHEN a rescan finds a new finding within that decision aperture in a supported digest THE Scan Pipeline SHALL open a GitHub issue containing severity, EPSS score, KEV status, and affected images.
4. WHEN a triage decision concludes not-affected THE Triage Process SHALL record an OpenVEX statement under triage/, which THE CI Pipeline and THE Scan Pipeline attach to affected images under criteria 2.9 and 6.43.
5. WHEN a triage decision concludes fix THE Triage Process SHALL produce a version-bump or rebuild pull request.
6. WHERE a CRITICAL finding exists THE Scan Pipeline SHALL obtain a second-opinion scan with Grype.
7. WHEN a triage decision concludes accepted risk or upstream transfer THE Triage Process SHALL record a time-boxed exception under triage/accepted-risk/ carrying a treatment, an owner, a decision date, a reference to its reasoning in triage/LOG.md, a justification for why avoidance and remediation were unavailable, and an expiry date.
8. THE Triage Process SHALL NOT record accepted risk or upstream transfer as a VEX statement recording status not_affected or fixed.
9. WHEN an accepted-risk exception has passed its expiry date THE Scan Gate SHALL count every finding it names as uncovered.
10. WHEN a daily rescan runs THE Scan Pipeline SHALL report every accepted-risk exception that has expired or that expires within that catalogue policy file's expiry warning window.
11. IF an accepted-risk exception omits its treatment, owner, decision date, reasoning reference, unavailability justification, or expiry date, or sets an expiry date later than its decision date plus that catalogue policy file's largest ceiling, THEN THE CI Pipeline SHALL fail validation.
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
35. THE Scan Gate SHALL NOT count a VEX statement recording status under_investigation or affected as coverage of a finding.
36. WHEN a VEX document is compiled for an image index THE VEX Compiler SHALL produce product identifiers covering that index's digest and every scanned platform manifest digest.
37. WHEN a VEX document is compiled THE VEX Compiler SHALL derive it from source statements under triage/vex/, exceptions under triage/accepted-risk/, scan reports attested to that document's digest, and any OpenVEX document previously attested to that digest, and from no other input.
38. WHEN a VEX document is compiled THE VEX Compiler SHALL add, for every unexpired accepted-risk exception naming a finding in that document's digest that no source statement under triage/vex/ covers, an OpenVEX statement recording status affected, whose timestamp is that finding's first-seen time, taken from a statement previously attested for it or, absent one, from that digest's attested scan report, whose action statement carries that exception's treatment, statement text, upstream issue for a transfer, binary paths and expiry date, and whose action statement timestamp is that exception's decision date.
39. IF a VEX source statement under triage/vex/ records a status other than not_affected or fixed THEN THE CI Pipeline SHALL fail validation naming that statement.
40. WHEN THE VEX Compiler carries a statement it wrote forward from a previously attested document THE VEX Compiler SHALL keep that statement's timestamp and SHALL set its last_updated to that compile's scan report timestamp on any change to its status or content.
41. IF an accepted-risk exception has passed its expiry date THEN THE VEX Compiler SHALL compile no affected statement from it and SHALL record status under_investigation for each finding it named that that digest's attested scan report lists, carrying that finding's first-seen time under criterion 6.38 and a status note naming that lapse.
42. WHEN a scheduled rescan runs THE Scan Pipeline SHALL attest each tag-referenced platform manifest's scan report to that manifest, replacing every scan report attestation of that predicate type on that manifest, before compiling VEX for that digest.
43. WHEN a compiled document for a tag-referenced digest differs in its set of statements from that digest's attested OpenVEX document, or a tag-referenced digest or any of its platform manifests carries a number of OpenVEX attestations other than one, THE Scan Pipeline SHALL attest that compiled document to that digest and to each of its platform manifests, replacing every existing OpenVEX attestation on each.
44. THE Catalogue SHALL keep exactly one OpenVEX attestation on every tag-referenced digest and on each of its platform manifests.
45. WHEN a scheduled rescan runs THE Scan Pipeline SHALL report any tag-referenced digest or platform manifest carrying more than one OpenVEX attestation as a failure of that run.
46. WHEN a scheduled rescan runs THE Scan Pipeline SHALL compute for every finding within that decision aperture on every supported digest its first-seen time from its statement's timestamp, its decision time from its statement's action statement timestamp for status affected and from its statement's timestamp for status not_affected or fixed, and its fix time as that finding's first day absent, reported and suppressed alike, from every supported digest of its repository, carried forward from previously published status data.
47. WHEN a scheduled rescan completes THE Scan Pipeline SHALL publish those times and, for every finding on a supported digest not yet decided or fixed, its age against that catalogue policy file's ceilings, to one status issue, as a table and as a fenced JSON block, and as a workflow artifact.
48. THE Repository SHALL display in README.md badges rendered from GitHub's public API for open issues carrying that cve label criteria 6.52 to 6.57 govern and for its build, rescan and e2e workflow status.
49. THE Repository SHALL declare in that catalogue policy file's triage section a decision aperture, an exception ceiling as a duration per severity in that aperture, a ceiling for findings listed in CISA KEV, an expiry warning window, and a support statement naming which tags define that supported set and recording that superseded tag-referenced digests keep scans and attestations and sit outside issue scope.
50. WHEN a pull request builds an image THE Scan Gate SHALL fail on every accepted-risk exception whose expiry date exceeds its decision date plus that catalogue policy file's ceiling for its finding's severity in that image's scan report or, for a KEV-listed finding, that KEV ceiling, naming that exception, and SHALL tier an exception matching no finding in that image by its largest applicable ceiling.
51. WHEN a scheduled rescan runs THE Scan Pipeline SHALL report every unexpired accepted-risk exception whose expiry date exceeds its decision date plus that catalogue policy file's ceiling for its finding's current severity and KEV status as a failure of that run.
52. WHEN a scheduled rescan finds that a finding an open cve issue names appears, as a reported or as a suppressed finding, in no supported digest's attested scan report THE Scan Pipeline SHALL close that issue with a comment naming every supported digest examined and those reports' scanner and database versions.
53. WHEN a scheduled rescan finds that every finding an open cve issue names is covered by a VEX statement recording status not_affected or fixed or by an unexpired accepted-risk exception on every supported digest whose attested scan report lists it THE Scan Pipeline SHALL close that issue with a comment naming each covering artifact.
54. THE Scan Pipeline SHALL close an issue only on evidence derived from attested scan reports, attested SBOMs and merged triage artifacts and SHALL NOT record a triage decision itself.
55. THE Catalogue SHALL include in every attested scan report every suppressed finding and that report's scanner and vulnerability database versions.
56. WHEN THE Scan Pipeline closes a cve issue THE Scan Pipeline SHALL grade its resolved label by its evidence: resolved:fixed solely on SBOMs attested to supported digests proving that finding's package version bumped or a fixed statement covering it, resolved:removed on that package leaving every supported digest's SBOM, resolved:not_affected or resolved:accepted on a covering statement or exception, and resolved:absent otherwise.
57. WHEN a scheduled rescan finds a finding named by a closed cve issue, as a reported finding, in a supported digest's attested scan report THE Scan Pipeline SHALL reopen that issue.
58. THE Scan Pipeline SHALL read a previously attested OpenVEX document and attested scan reports only through a verification admitting those identities criterion 2.23 admits for each attestation type.
59. IF that KEV feed is unavailable to a pull request scan THEN THE Scan Gate SHALL fail that pull request naming that outage.
60. IF that KEV feed is unavailable to a scheduled rescan THEN THE Scan Pipeline SHALL report that non-evaluation as a failure of that run.

### Requirement 7: Conventions and Review Enforcement

**Objective:** As a catalogue maintainer, I want conventions codified and enforced mechanically, so that drift is caught by tooling and review attention goes to substance.

#### Acceptance Criteria

1. THE Repository SHALL contain a CONVENTIONS.md defining naming, pinning, variant, and override rules.
2. WHEN a pull request opens THE CI Pipeline SHALL run yamllint and definition validation on changed YAML files.
3. THE Repository SHALL provide a pull request template prompting for requirement references and convention compliance.
4. IF a pull request violates a codified convention THEN THE CI Pipeline SHALL fail with a message identifying that convention.
5. WHEN a workflow installs a third-party executable THE CI Pipeline SHALL pin that executable to an exact version and SHALL verify its download against a checksum recorded in this repository.
6. IF a pinned third-party executable has a newer released version THEN THE Upstream Tracking SHALL open a pull request updating that pin.
7. THE Repository SHALL declare in one committed catalogue policy file every release setting that criteria 2.13, 2.14 and 2.17 name, every platform it admits for publishing, and every verification input that criterion 2.23 names.
8. THE CI Pipeline SHALL render that verification policy under policies/ and those consumer verification instructions from that catalogue policy file's verification section.
9. IF a rendered verification artifact differs from its committed copy THEN THE CI Pipeline SHALL fail validation naming that artifact.
10. IF a workflow's schedule trigger or a job's permissions differ from what that catalogue policy file declares THEN THE CI Pipeline SHALL fail validation naming that value.

### Requirement 8: Operating Environment Constraints

**Objective:** As the project owner, I want heavy operations to run where network access exists, so that development in a restricted devcontainer stays unblocked.

#### Acceptance Criteria

1. THE CI Pipeline SHALL execute image builds, kind clusters, registry pushes, and scans on GitHub Actions runners or on an operator host machine.
2. IF a task requires registry or internet access THEN THE Development Workflow SHALL delegate that task to GitHub Actions or an operator host instead of executing it inside a restricted devcontainer.
