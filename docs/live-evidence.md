# Live evidence: every mechanism, exercised once on the real catalogue

One row per criterion the requirements name (`.specs/dhc-catalogue-mvp/requirements.md`),
saying when the mechanism behind it first ran for real, on the real catalogue, and what
proves it: a workflow run, an issue, a pull request, registry state or a LOG entry.
Req 7.11 (design Decision 13, task group 16) asks for exactly this, because a unit test
proves a mechanism in isolation and only a live run proves the wiring around it: the
cosign install order and the `GH_TOKEN` name, both of September 2026, were green in every
suite and failed only live.

Seeded on 2026-10-08 (task 16.1) from the audit of 2026-09-27: the per-step tallies over
1,028 workflow runs (`build.yml` and `rescan.yml` jobs, July 20 to September 27), the
run histories of `validate.yml`, `chart.yml`, `e2e.yml` and `renovate.yml`, the issue and
pull request history, the offline re-verification of the supported set (91 of 91 checks),
and the live events since (the grafana 13.1.7 release of 2026-10-06, which supplied the
first fix clock).

How to read a row:

- **Status** is one of four words. `exercised`: the mechanism ran live at least once and
  the evidence column says where. `defect`: it ran live and the run showed the claim false;
  the evidence names the defect. `drill 16.N`: never live yet, and task 16.N of the spec
  induces it; the evidence column says what has run so far and what the drill adds.
  `unexercised`: never live, no drill reaches it, and the evidence column carries the reason.
- **First live exercise** is the date of the earliest evidence; a static artifact (a file
  the criterion requires to exist) carries the date it was last measured present.
- **Induced by**: `nature` for the catalogue's own operation; `owner`, `pull request`,
  `drill definition`, `switch` and `drill input` for the ways Decision 13 allows a drill to
  induce an event. Drill rows name the way the drill will use.
- Run ids are GitHub Actions run ids of this repository; `#n` is an issue or pull request
  here; `LOG <date>` is a heading in `triage/LOG.md`.

The validate check `scripts/lint-live-evidence.sh` holds that every criterion number has
exactly one row, that no row names a retired number, and that every row carries a status,
a mechanism and evidence or a reason. A new criterion therefore arrives with its
evidence obligation, and a retired one cannot keep a row.

## Requirement 1: Image Definition Catalogue

| Criterion | Mechanism | Status | First live exercise | Evidence | Induced by |
|---|---|---|---|---|---|
| 1.1 | Definitions as self-contained subtrees under `image/`, the reference set | exercised | 2026-07-21 | The seven definitions build from `image/` on every push (first push build run 29867929092); the definition lint reads them on every validate run (first run 29867929083). | nature |
| 1.2 | Base images pinned by digest | exercised | 2026-07-21 | `lint-pins.sh` on every validate run; Renovate moves the build-layer digests through pull requests (#3 on 2026-07-21, #245 on 2026-10-05). | nature |
| 1.3 | Upstream sources pinned by version plus checksum | exercised | 2026-07-30 | The per-architecture checksum verification runs in every build (first run 30561386824) and refused a wrong artifact on 2026-08-07 (run 31181738110: the 13.1.3 bump pointed at 13.1.2 files). | nature |
| 1.4 | Runtime account UID 65532 | exercised | 2026-07-22 | `lint-accounts.sh` on every validate run; the e2e asserts the live pod's UID on every green run (first run 29954368216). | nature |
| 1.6 | A floating tag fails validation naming it | drill 16.15 | | The lint has refused nothing live: no pull request has carried a floating tag (none of the validate failures to date is in the pin lint). A 16.15 commit supplies one. | pull request |
| 1.7 | Definitions in the backend's native syntax | exercised | 2026-07-21 | Every definition builds through the `dhi.io/build` frontend (first push build run 29817266076); the builder contract in `docs/concepts.md`. | nature |
| 1.9 | CONVENTIONS records that repository packages are not pinned and the daily rebuild carries their updates | exercised | 2026-09-12 | `docs/CONVENTIONS.md` "Packages from package repositories are not pinned"; the scheduled rebuild of 2026-09-12 (run 34684357895) published two cert-manager images whose package sets had moved. | nature |
| 1.10 | Each definition declares an authenticity class | exercised | 2026-09-07 | Every `image.yaml` declares its class; the daily re-verification reads them (first run 34123366989). | nature |
| 1.11 | Class none or absent fails validation naming the definition | drill 16.15 | | Never refused live; the lint's unit tests cover it. A 16.15 commit adds a definition declaring no class. | pull request |
| 1.12 | A package repository path outside the declared shapes fails validation | drill 16.15 | | Never refused live. A 16.15 commit adds a definition naming an off-shape repository. | pull request |
| 1.13 | The policy file declares the active set | exercised | 2026-09-09 | `catalogue-policy.yaml` carries the active set; the rescan's inactive-digest check reads it daily (first run 34412914468) and the active-set lint on every validate run. | nature |
| 1.14 | Matrices and tracking scope read the active set alone | exercised | 2026-09-16 | `build.yml`'s affected-definitions job and `e2e.yml`'s affected-components job derive their matrices from the policy file; the tracking-scope rendering check runs on every validate run; the active-set lint refused pull request #203 on 2026-09-16 (run 35159377770). | nature |
| 1.15 | An inactive definition gets no digest and no tag | drill 16.11 | | The rescan's check has run daily since 2026-09-09 (run 34412914468) with nothing inactive to check. 16.11 gives it an inactive definition. | drill definition |
| 1.16 | A bump of an inactive definition fails validation naming it | drill 16.11 | | Never refused live, nothing being inactive. 16.11's drill branch bumps the deactivated definition. | pull request |
| 1.17 | A builder contract per archetype is documented | exercised | 2026-10-08 | `docs/concepts.md` "The builder contract per archetype" (present 2026-10-08). | nature |
| 1.18 | An active set splitting an enforced group fails validation | unexercised | | No change has split the cert-manager group; the lint's unit tests cover it (`lint-active-set_test.sh`). A 16.15 commit dropping one cert-manager definition from the active set can exercise it; recorded here as a candidate for that task. | pull request |
| 1.19 | An active-set entry without a directory fails validation | drill 16.11 | | Never refused live. 16.11's second drill branch removes a directory and keeps the entry. | pull request |

## Requirement 2: Image Build and Release

| Criterion | Mechanism | Status | First live exercise | Evidence | Induced by |
|---|---|---|---|---|---|
| 2.1 | A merged definition change builds each affected active definition for its platforms | exercised | 2026-07-21 | First push build run 29867929092; 179 push builds by 2026-09-27. | nature |
| 2.2 | A successful build pushes with provenance and signs | exercised | 2026-07-21 | Run 29817266076 pushed, signed keyless and attested the SPDX SBOM; signatures and provenance of the supported set verified offline on 2026-09-27 (91 of 91). | nature |
| 2.3 | Tags derived from upstream versions in DHI shape | exercised | 2026-07-21 | Every release build applies the three tags (the current step first ran in run 33556095726 on 2026-09-01); 13.1.7's tags applied on 2026-10-06 (run 37457046807). | nature |
| 2.4 | Private source and registry while public release is disabled | exercised | 2026-07-21 | The "verify package is private" step ran 37 times from run 29817266076 until the 2026-08-13 go-live ended the WHILE clause. The disabled branch is not re-exercised on the public catalogue, by Decision 13. | nature |
| 2.5 | A failed build publishes nothing and reports each failing step | exercised | 2026-07-21 | First failed build step on a pull request, run 29864322196; on main, the 2026-09-19 push run 35447653480 failed both valkey builds and published nothing. | nature |
| 2.7 | A release build on main pushes by digest before anything else | exercised | 2026-09-01 | Run 33556095726 (dispatch), then every push and scheduled publish. | nature |
| 2.8 | The pushed digest is scanned per platform manifest | exercised | 2026-09-01 | The release-time scan step, first in run 33556095726, in every publishing run since. | nature |
| 2.9 | Reports attested, signature and tags applied after the scan | exercised | 2026-09-01 | Run 33556095726; the attestations of every supported digest verified offline on 2026-09-27. | nature |
| 2.10 | Published means tagged, signed, attested, with provenance | exercised | 2026-09-04 | The rescan's admission proof applies the verification policy to every tag-referenced digest daily (first clean run 33867898868). | nature |
| 2.11 | A digest no tag references is frozen | drill 16.9 | | By construction no run touches an untagged digest, so nothing has ever been frozen deliberately. 16.9 withholds one through the fail-closed gate. | switch |
| 2.12 | With fail-closed off, an uncovered finding at release becomes an under_investigation statement | exercised | 2026-09-02 | LOG 2026-09-02: grafana's half of #112 stayed under_investigation in the nightly attestations; LOG 2026-09-06: valkey's server-binary finding. | nature |
| 2.13 | With fail-closed on, nothing is signed, attested or tagged for an uncovered digest | drill 16.9 | | The step has been skipped in every build job (710 by 2026-09-27): the switch is off. 16.9 turns it on for one release. | switch |
| 2.14 | Every active definition rebuilt daily | exercised | 2026-09-02 | First scheduled build run 33612224293 (failed on the cosign install order), green from run 33737657714 on 2026-09-03, daily since. | nature |
| 2.15 | On-change policy discards an unchanged rebuild | exercised | 2026-09-04 | LOG 2026-09-04, the first no-change day; a scheduled run that built seven and published none, run 34333520924 on 2026-09-09. | nature |
| 2.16 | A changed package set publishes | exercised | 2026-09-12 | Run 34684357895 published cert-manager-controller and cert-manager-webhook and discarded the other five. | nature |
| 2.17 | Always policy publishes every rebuild | drill 16.13 | | Never set. 16.13 sets it for one nightly. | switch |
| 2.20 | Only admitted identities count toward published | exercised | 2026-09-03 | The admission proof refused legacy digests whose attestations were unverified (run 33803244102: NOT ADMITTED, three digests named). | nature |
| 2.21 | Every catalogue repository anonymously pullable, verified daily | exercised | 2026-09-02 | The visibility invariant, first in run 33624552846, daily since. | nature |
| 2.22 | Every tag and digest enumerated daily | exercised | 2026-09-02 | Run 33624552846; LOG 2026-09-02, the first full-enumeration rescan. | nature |
| 2.23 | A verification policy published under `policies/` | exercised | 2026-09-03 | `policies/` rendered from the policy file; applied daily by 2.24. | nature |
| 2.24 | The policy applied daily to every tag-referenced digest and to an unsigned control | exercised | 2026-09-03 | Run 33803244102 refused three digests; run 33867898868 was the first clean day; the control image is rejected daily; an offline re-run on 2026-09-27 rejected the declared control. | nature |
| 2.25 | Consumer instructions name the issuer and exact identities | exercised | 2026-09-08 | README "Verify an image", rendered from the policy file; run verbatim daily by the consumer smoke test (first run 34228878140). | nature |
| 2.26 | A missing or unverified report at release signs nothing and tags nothing | unexercised | | No release-time scan has failed to produce a report. The refusal path is unit-tested (`scan-image_test.sh`). Inducing a scanner failure at release needs an input Decision 13 does not allow (only the KEV feed URL is substitutable); recorded as the owner's call. | drill input |

## Requirement 3: Upstream Version Tracking

| Criterion | Mechanism | Status | First live exercise | Evidence | Induced by |
|---|---|---|---|---|---|
| 3.1 | Renovate self-hosted at least every six hours | exercised | 2026-07-21 | 348 runs by 2026-09-27, first run 29869195082; first failure 2026-07-29 (run 30490709493, a docker error, the next run green). | nature |
| 3.2 | An upstream release opens a pull request with refreshed pins | exercised | 2026-07-21 | #4 (cert-manager, 2026-07-21), #14 (valkey 9.1.1, 2026-07-22); the refresh's own authenticity note in #225 and #246. | nature |
| 3.3 | Monorepo bumps grouped into one pull request | exercised | 2026-07-21 | #4 and #208 bump the three cert-manager images together. | nature |
| 3.4 | Majors staged behind Dependency Dashboard approval | exercised | 2026-09-10 | The dashboard (#5) holds eight majors pending approval on 2026-10-08 (grafana 13.2, cosign 3, renovate 44, four docker actions); grafana 13.2 was declined on evidence (LOG 2026-09-10). No major has been approved, by choice. | nature |
| 3.5 | Patch and digest updates of a compile-from-source upstream automerge on green | exercised | 2026-09-01 | #111 (valkey 9.1.2) merged at 13:19:42 UTC inside Renovate run 33512615078. | nature |
| 3.7 | A release is withheld until it has aged | exercised | 2026-10-08 | The dashboard's "Pending Status Checks" holds grype 0.120.1 and syft 1.54.1 until they age (measured 2026-10-08). | nature |
| 3.8 | A refresh verifies the authenticity signal before recomputing pins | exercised | 2026-09-18 | #225's `image.yaml` carries "verified 13.1.6 ... 2026-09-18" written by the refresh; #246 "verified 13.1.7 ... 2026-10-05". | nature |
| 3.9 | A changed per-architecture checksum is verified against the served bytes | exercised | 2026-08-07 | Run 31181738110 refused grafana's bump: the artifacts could not be fetched at the pinned URLs. | nature |
| 3.10 | Daily re-verification of every authenticity signal, a mismatch reported as a supply-chain issue | drill 16.10 | | The re-verification has run daily since 2026-09-07 (run 34123366989). Its report has fired only on unreadable reads (3.13); a true mismatch has never occurred. 16.10 moves the drill definition's tag. | owner |
| 3.11 | Pinned upstream charts tracked, bump pull requests opened | exercised | 2026-09-08 | #167 (cert-manager chart), #168 (valkey chart 0.12.0). | nature |
| 3.12 | Chart digest pins automerge on green | exercised | 2026-10-07 | #252 merged at 05:15:08 UTC inside Renovate run 37575287810; #253 inside run 37643271339. | nature |
| 3.13 | An unreadable origin is recorded as not measured, fails the run by name, files no issue | unexercised | | No origin has been unreadable since the criterion landed on 2026-09-17. The incident it corrects, run 35091969642 on 2026-09-16 reading a rate limit as six mismatches (#212 to #217), is what the criterion forbids. A rate limit cannot be induced without harming the day's run; nature supplies it. | nature |
| 3.14 | A vulnerability alert on the repository's own tooling opens a fix pull request | exercised | 2026-10-01 | #233 and #234 (LOG 2026-09-20 records the input). | nature |
| 3.15 | A dismissed alert opens no pull request | unexercised | | No alert has been dismissed. A dismissal is an owner action on a real alert; the next low alert can supply it (owner's call). | owner |

## Requirement 4: Helm Chart Adaptation

| Criterion | Mechanism | Status | First live exercise | Evidence | Induced by |
|---|---|---|---|---|---|
| 4.1 | Pinned upstream charts consumed at their pinned version | exercised | 2026-07-22 | `chart.yml` renders the pinned charts on every run (first green run 29950977951); Renovate tracks the pins (#168). | nature |
| 4.2 | Image references overridden to digest-pinned catalogue images | exercised | 2026-09-06 | Every overlay pins tag@digest; the placeholder hole (#64) was closed by task 8.4; Renovate's digest pull requests move the pins (#155 first, 2026-09-06). | nature |
| 4.3 | Restricted Pod Security Standard settings enforced | exercised | 2026-07-22 | The kyverno gate (4.6) on every render; the e2e's live securityContext assertions (5.4) on every green run. | nature |
| 4.4 | emptyDir volumes where a workload writes | exercised | 2026-08-12 | valkey's `/data` emptyDir (chart/valkey, #50) runs in every valkey e2e since the chart merged. | nature |
| 4.5 | A compat-variant decision recorded with a review-by date | exercised | 2026-09-06 | LOG 2026-09-06; `lint-compat.sh` on every validate run. | nature |
| 4.6 | Rendered manifests gated by Kyverno policies | exercised | 2026-08-11 | The gate blocked #50 (the valkey chart) on 2026-08-11 (run 31538146580) before the overlay was corrected; 458 green pull-request runs by 2026-10-08. | nature |
| 4.7 | Every deviation documented in a per-chart README | exercised | 2026-10-08 | `chart/*/README.md` (present 2026-10-08), the valkey README carrying the compat decision. | nature |
| 4.8 | A lapsed review-by date fails validation | unexercised | | The one decision's review-by date is 2026-11-24; the lapse path is unit-tested. Nature supplies it on 2026-11-24 unless the decision is renewed first; a 16.15 commit with a past date can induce it earlier. | pull request |
| 4.9 | A lapsed review-by date reported daily | unexercised | | Same event as 4.8; the daily step runs with nothing lapsed. | nature |

## Requirement 5: Go Integration Tests on Real Kubernetes

| Criterion | Mechanism | Status | First live exercise | Evidence | Induced by |
|---|---|---|---|---|---|
| 5.1 | Ginkgo, Gomega and e2e-framework on ephemeral kind clusters | exercised | 2026-07-22 | First green e2e run 29954368216; 703 green pull-request runs by 2026-09-27. | nature |
| 5.2 | Each affected chart installed with published images | exercised | 2026-07-22 | Same runs; the matrix from the affected-components job. | nature |
| 5.3 | Pods Ready within five minutes | exercised | 2026-07-22 | Same runs. | nature |
| 5.4 | Live securityContext matches the restricted profile | exercised | 2026-07-22 | Same runs (`test/e2e/assert_test.go`). | nature |
| 5.5 | The declared functional probe executed once | exercised | 2026-10-05 | Every green e2e run since the probes were declared; the e2e gate on #246 (2026-10-05). | nature |
| 5.6 | A version bump runs the upgrade path | exercised | 2026-09-02 | e2e run 33692479682 on the grafana bump branch (`test/e2e/upgrade_test.go`). | nature |
| 5.7 | A failed assertion fails the check and keeps diagnostics | exercised | 2026-07-22 | Run 29926193911 failed and kept the artifact `e2e-diagnostics-hardened-app`. | nature |
| 5.8 | An active definition with no probe-declaring chart fails validation | drill 16.15 | | The lint has refused nothing live. A 16.15 commit removes a probe declaration. | pull request |

## Requirement 6: CVE Triage With Recorded Decisions

| Criterion | Mechanism | Status | First live exercise | Evidence | Induced by |
|---|---|---|---|---|---|
| 6.1 | The pull request gate scans with Trivy and fails on uncovered findings by name | exercised | 2026-07-26 | Run 30220276310: "grafana: 1 CRITICAL / 15 HIGH not covered"; 96 gate failures by 2026-09-27. | nature |
| 6.3 | A new finding in a supported digest opens an issue | exercised | 2026-07-23 | Run 29998802723 filed #22 to #28. | nature |
| 6.4 | A not_affected decision is an OpenVEX statement the gate and the rescan apply | exercised | 2026-07-30 | LOG 2026-07-26 (the first statements); LOG 2026-07-30 (the gate could not match them until the image got an identity, suppressing since run 30588130246); attested on every supported digest daily. | nature |
| 6.5 | A fix decision produces a bump pull request | exercised | 2026-09-02 | LOG 2026-09-02 (#112, the x/crypto bump); the 13.1.7 bump closed twelve findings on 2026-10-06 (#246). | nature |
| 6.7 | Accepted risk or transfer is a time-boxed exception | exercised | 2026-08-04 | LOG 2026-08-04 (#22); the twelve entries of 2026-09-03 in `triage/accepted-risk/grafana.yaml`. | nature |
| 6.8 | Accepted risk never recorded as not_affected or fixed | exercised | 2026-09-03 | Every accepted risk sits in `triage/accepted-risk/` and compiles to an affected statement (status data of 2026-10-05: eleven affected rows); the lint of 6.39 guards the source statements. | nature |
| 6.9 | An expired exception counts as uncovered in the gate | drill 16.4 | | No exception has expired (the first expiries are 2026-11-02). 16.4 lets the drill's exception lapse. | drill definition |
| 6.10 | Expiring and expired exceptions reported daily | drill 16.4 | | The step has run daily since 2026-07-29 (run 30438758735) with nothing inside the 14-day window. 16.4 puts an exception inside it. | drill definition |
| 6.11 | An exception missing a required field fails validation | drill 16.15 | | Never refused live. A 16.15 commit omits a field. | pull request |
| 6.12 | A Trivy ignore file outside `triage/accepted-risk/` fails validation | drill 16.15 | | Never refused live. A 16.15 commit adds one. | pull request |
| 6.13 | govulncheck in binary mode on every Go binary of a pull request build | exercised | 2026-07-30 | Run 30564637064; cited in the statements since LOG 2026-07-26. | nature |
| 6.14 | A reachable symbol is never recorded as not_affected by execute path | exercised | 2026-07-26 | LOG 2026-07-26: the reachable findings were recorded affected (#28) or transferred (#22, #24, #26), none as not_affected. | nature |
| 6.15 | An execute-path claim cites its govulncheck result | exercised | 2026-07-26 | LOG 2026-07-26 and LOG 2026-09-18 (CVE-2026-84445) cite the measurement per binary. | nature |
| 6.16 | A module-level-only result is unmeasured, never evidence | exercised | 2026-07-26 | LOG 2026-07-26 and LOG 2026-09-18 state per binary what govulncheck could and could not measure before any claim. | nature |
| 6.17 | A statement naming a non-OCI or foreign product fails validation | exercised | 2026-08-11 | Run 31535132029 refused a grafana bump's statements. | nature |
| 6.19 | A subcomponent with a version fails validation | drill 16.15 | | Never refused live. A 16.15 commit adds one. | pull request |
| 6.20 | A product version that is not a published tag fails validation | exercised | 2026-08-11 | Runs 31535132029 (2026-08-11), 34412037504 (2026-09-09) and 37097344933 (#246, 2026-10-03) each refused statements whose tag a bump retired. | nature |
| 6.22 | A superseded statement is kept and the new one appended | exercised | 2026-08-03 | `triage/vex/CVE-2026-42151.openvex.json` carries the superseded statement and its successor (LOG 2026-08-03). | nature |
| 6.25 | Two exceptions naming one finding and one binary fail validation | drill 16.15 | | Never refused live. A 16.15 commit duplicates an entry. | pull request |
| 6.26 | Exceptions that suppressed nothing are reported | exercised | 2026-10-05 | The accepted-risk report runs in every pull request build with exceptions; in run 37346826858 (#246, 13.1.7) the twelve grafana entries suppressed nothing, the findings having left the image. | nature |
| 6.27 | A suppressing exception names the binary | exercised | 2026-09-03 | Every attested affected statement names its binary ("Binaries: usr/share/grafana/data/plugins-bundled/zipkin/*"); the gate's report on pull request builds. | nature |
| 6.28 | Compiled documents applied in place of sources | exercised | 2026-09-01 | The compile step in run 33556095726 and every release and rescan since. | nature |
| 6.29 | Every compiled product identifier is a digest being scanned | exercised | 2026-09-01 | The attested documents name sha256 products (verified 2026-09-27 over the supported set and 2026-10-08 on grafana 13.1.7's amd64 manifest). | nature |
| 6.30 | A statement scoped to another tag is omitted | exercised | 2026-09-01 | The compile step's drop records on every run (five products dropped for grafana 13.1.6 on 2026-10-05). | nature |
| 6.32 | Omitted statements and the digest used are recorded | exercised | 2026-09-01 | `COMPILE_VEX_REPORT` per compile, rendered as the Applied and Dropped table of every rescan summary. | nature |
| 6.33 | A scheduled rescan reports the omitted statements | exercised | 2026-09-03 | The Dropped column of every rescan summary (run 37786030952 on 2026-10-08 is the latest). | nature |
| 6.34 | The attested document is the one compiled for that digest | exercised | 2026-09-01 | Run 33556095726; the attested documents verified by digest on 2026-09-27 and 2026-10-08. | nature |
| 6.35 | under_investigation and affected are not coverage | exercised | 2026-09-02 | Run 33681977233: the gate failed on grafana's finding while its attested document carried an under_investigation statement for it. | nature |
| 6.37 | Compiled from sources, exceptions and scan reports | exercised | 2026-09-01 | Every compile since run 33556095726. | nature |
| 6.38 | An unexpired exception compiles to an affected statement | exercised | 2026-09-03 | The attested documents carry the exceptions as affected statements (status data of 2026-10-05, eleven rows). | nature |
| 6.39 | A source statement with a status other than not_affected or fixed fails validation | drill 16.15 | | Never refused live. A 16.15 commit adds one. | pull request |
| 6.40 | A carried-forward statement keeps its timestamp | exercised | 2026-09-04 | LOG 2026-09-04 (ADR 0004): the re-stamping found and fixed; CVE-2026-21728's statement still carries 2026-08-05 in the document attested on 2026-10-06. | nature |
| 6.41 | A lapsed exception compiles to under_investigation with its first-seen time | drill 16.4 | | No exception has lapsed. 16.4 lets the drill's exception lapse. | drill definition |
| 6.42 | Each platform manifest's scan report attested daily, replacing | exercised | 2026-09-03 | Run 33803244102; the replace failure of 2026-09-04 (run 33854524508) and its fix. | nature |
| 6.43 | A changed document is re-attested | exercised | 2026-10-06 | Run 37470485195 re-attested grafana's document after the statements moved to 13.1.7 (the 13.1.6 move of 2026-09-18 before it). | nature |
| 6.44 | Exactly one OpenVEX attestation per digest and manifest | exercised | 2026-09-04 | The invariants step, first clean in run 33867898868, daily since. | nature |
| 6.45 | More than one OpenVEX attestation is reported | exercised | 2026-09-04 | The multiple attestations that motivated ADR 0004 were measured on the live registry (`triage/upstream/2026-08-23-trivy-vex-oci-multiple-attestations.md`); the invariant has held since. | nature |
| 6.46 | Clocks computed daily: first seen, decided, fixed, age | exercised | 2026-09-06 | Run 34029152793; the fix clock first published on 2026-10-06 (run 37470485195: twelve fixed, median 30 days). | nature |
| 6.47 | Clocks and decisions published to the status issue and as an artifact | exercised | 2026-09-06 | #151 rewritten daily since 2026-09-06; the `catalogue-status` artifact on every run. | nature |
| 6.49 | The policy file declares the aperture, ceilings and support statement | exercised | 2026-09-03 | `catalogue-policy.yaml` triage section, read by every gate and rescan through `triage-policy.sh`. | nature |
| 6.50 | The gate fails an exception whose expiry exceeds its tier | drill 16.3 | | The tiering step runs on every pull request build (first run 33681977233) and has refused nothing: no exception has exceeded its tier. 16.3 writes one. | pull request |
| 6.51 | The rescan reports exceptions over their tier against today's KEV | drill 16.3 | | The invariants step evaluates daily with no breach to report. 16.3 supplies the KEV-listed finding. | drill definition |
| 6.52 | An open issue whose finding left every supported digest is closed | exercised | 2026-09-06 | #22, #24, #28, #39, #107 and #112 closed on 2026-09-06 (run 34029152793). | nature |
| 6.53 | An open issue whose findings are all covered is closed | exercised | 2026-09-06 | #26, #56, #72, #83 to #88 and #121 closed resolved:accepted on 2026-09-06; #186 resolved:not_affected on 2026-09-20. | nature |
| 6.54 | Issues close only on attested evidence | exercised | 2026-09-06 | The same closures, graded by the "issue lifecycle, the evidence" step from attested reports and SBOMs. | nature |
| 6.55 | Attested reports carry every suppressed finding and the scanner and database versions | defect | 2026-09-01 | Suppressed findings and the scanner version are present; `scanner.db.uri` and `scanner.db.version` are empty in every attested report: measured over 14 manifests on 2026-09-27 and on grafana 13.1.7's amd64 manifest on 2026-10-08 (trivy 0.75.0). Fix pending. | nature |
| 6.56 | Closures graded by evidence: fixed, removed, not_affected, accepted, absent | exercised | 2026-09-06 | resolved:fixed on SBOM evidence (#22, #24, #28, #39, #107, #112), resolved:accepted and resolved:not_affected used; resolved:removed and resolved:absent never, no finding having left that way. | nature |
| 6.57 | A closed issue's finding reappearing reopens it | drill 16.7 | | No fixed finding has returned. 16.7 pins the vulnerable module again. | drill definition |
| 6.58 | Previously attested documents read only through verification | exercised | 2026-09-12 | Since review D2 (2026-09-09) the comparator and `fetch-sboms.sh` read attestations through `cosign verify-attestation`; the first scheduled publish through it, run 34684357895. | nature |
| 6.59 | A KEV feed outage fails the pull request gate by name | drill 16.8 | | The feed has never been unavailable. 16.8 substitutes an unreachable URL on a drill branch. | drill input |
| 6.60 | A KEV feed outage fails the scheduled rescan | drill 16.8 | | Same; 16.8 dispatches the rescan with the `kev-outage` input. | drill input |
| 6.61 | The catalogue page rendered and deployed from the run's status data | exercised | 2026-09-09 | Run 34412914468; daily since. | nature |
| 6.62 | A disabled site, a failed deployment or stale served data fails the run | drill 16.13 | | The read-back check passes daily; its failure branch has never run. 16.13 turns the page off for one run. | switch |

## Requirement 7: Conventions and Review Enforcement

| Criterion | Mechanism | Status | First live exercise | Evidence | Induced by |
|---|---|---|---|---|---|
| 7.1 | A CONVENTIONS.md defining naming, pinning, variant and override rules | exercised | 2026-10-08 | `docs/CONVENTIONS.md` (present 2026-10-08). | nature |
| 7.2 | yamllint and schema and pinning checks on changed YAML | exercised | 2026-08-27 | yamllint refused run 33110774290; the pin lint runs on every pull request. | nature |
| 7.3 | A pull request template prompting for requirements and conventions | exercised | 2026-10-01 | `.github/PULL_REQUEST_TEMPLATE.md`, followed by #239 and #240. | nature |
| 7.4 | A convention violation fails with a message naming the convention | exercised | 2026-08-11 | The product lint (run 31535132029), the drift check (run 33110992171) and the active-set lint (run 35159377770) each refused a pull request by name. | nature |
| 7.5 | Every third-party executable pinned and verified against a checksum | exercised | 2026-08-07 | Every install step verifies a sha256; a bump without a recorded checksum is refused (runs 31217377481 on 2026-08-07 and 33270574881 on 2026-08-29). | nature |
| 7.6 | A newer tool release opens a pull request | exercised | 2026-08-11 | #44 (trivy), #45 (grype), #94 (kyverno), #110 (kind), #196 (cosign), #206 (helm), #231 (syft). | nature |
| 7.7 | One policy file declares every release setting | exercised | 2026-09-09 | `release-policy.sh check` on every validate run; the rescan's release-switches step (first run 34412914468). | nature |
| 7.8 | The verification policy and instructions rendered from the policy file | exercised | 2026-08-27 | `render-verification.sh` writes `policies/` and the README recipe; the drift check on every validate run. | nature |
| 7.9 | A rendered artifact differing from its committed copy fails validation | exercised | 2026-08-27 | Run 33110992171 refused a drifted rendering. | nature |
| 7.10 | A workflow schedule or permission differing from the policy file fails validation | drill 16.15 | | `lint-workflow-policy.sh` runs on every validate run and has refused nothing live. A 16.15 commit edits a cron in the workflow only. | pull request |
| 7.11 | A live-exercise ledger and LOG record for every mechanism | exercised | 2026-10-08 | This file and `scripts/lint-live-evidence.sh` (task 16.1). | owner |

## Requirement 9: Catalogue Posture and Trust Statement

| Criterion | Mechanism | Status | First live exercise | Evidence | Induced by |
|---|---|---|---|---|---|
| 9.1 | A security policy stating the published promise | exercised | 2026-10-08 | `SECURITY.md` (present 2026-10-08). | nature |
| 9.2 | Vulnerability reports accepted through private reporting | drill 16.14 | | The channel is enabled (9.3 checks it daily); no report has arrived. 16.14 files one. | owner |
| 9.3 | Private reporting verified daily, a disabled state reported | exercised | 2026-09-08 | Run 34220645771 reported "private vulnerability reporting is disabled (Req 9.3)"; the owner enabled it. | nature |
| 9.4 | Catalogue advisories as repository security advisories | drill 16.12 | | None published. 16.12 writes the drill advisory. | owner |
| 9.5 | Every revoked digest recorded in `triage/revocations.yaml` | drill 16.12 | | The record exists with no entry; its lint runs on every validate run. 16.12 records the drill digest. | pull request |
| 9.6 | A record violating its schema fails validation | drill 16.15 | | Never refused live. A 16.15 commit malforms an entry. | pull request |
| 9.7 | A tag referencing a revoked digest fails the daily run | drill 16.12 | | The posture step evaluates daily with an empty record. 16.12 revokes a tagged digest. | pull request |
| 9.8 | The intended ruleset committed in GitHub's export format | exercised | 2026-09-08 | `.github/rulesets/main_sec.json`, compared daily by 9.9. | nature |
| 9.9 | Committed rulesets compared daily with the live ones | exercised | 2026-09-08 | Run 34220645771: "live ruleset branch (id 19534405): no committed counterpart". | nature |
| 9.10 | A CODEOWNERS file naming a maintainer per lane | exercised | 2026-10-08 | `CODEOWNERS` (present 2026-10-08); its review routing has no live signal in a single-maintainer repository. | nature |
| 9.11 | VEX consumers declared, one authoritative, each an adapter | exercised | 2026-09-08 | The policy file's consumers list; the adapters run daily (run 34228878140). | nature |
| 9.12 | A portability block per scan and rescan | exercised | 2026-09-08 | Rescan run 34228878140; pull request build run 34226245142. | nature |
| 9.13 | The published verification instructions run verbatim daily | exercised | 2026-09-08 | The consumer smoke test, first run 34228878140, daily since. | nature |
| 9.14 | A manual-controls register | exercised | 2026-10-08 | `docs/CONVENTIONS.md` "Manual controls" (M1 to M23, present 2026-10-08). | nature |
| 9.15 | A trust-boundary table | exercised | 2026-10-08 | `docs/concepts.md` (present 2026-10-08), linked from the README and SECURITY.md. | nature |
| 9.16 | A notice file and the substrate's licence copy | exercised | 2026-10-08 | `NOTICE` and `LICENSES/Apache-2.0.txt` (present 2026-10-08). | nature |
| 9.17 | Non-affiliation stated in the README | exercised | 2026-10-08 | README line "affiliated with, sponsored by or endorsed by Docker, Inc." (present 2026-10-08), repeated in SECURITY.md. | nature |
| 9.18 | An exception reference or statement citation resolving to no LOG heading fails validation | drill 16.15 | | `lint-log-anchors.sh` resolves twelve references and seven citations on every validate run and has refused nothing live. A 16.15 commit breaks one. | pull request |

## Rows without evidence, by drill

| Drill | Rows | Induced by |
|---|---|---|
| Task 16.3 | 6.50, 6.51 | the drill definition's KEV-listed finding, a pull request |
| Task 16.4 | 6.9, 6.10, 6.41 | the drill definition's exception |
| Task 16.7 | 6.57 | the drill definition's regression |
| Task 16.8 | 6.59, 6.60 | the `drill` input substituting the KEV feed URL |
| Task 16.9 | 2.11, 2.13 | the fail-closed switch |
| Task 16.10 | 3.10 | the owner moving the drill definition's tag |
| Task 16.11 | 1.15, 1.16, 1.19 | the drill definition leaving the active set |
| Task 16.12 | 9.4, 9.5, 9.7 | the drill digest revoked |
| Task 16.13 | 2.17, 6.62 | the page and publish switches |
| Task 16.14 | 9.2 | the owner's drill report |
| Task 16.15 | 1.6, 1.11, 1.12, 5.8, 6.11, 6.12, 6.19, 6.25, 6.39, 7.10, 9.6, 9.18 | one pull request, never merged; the task's list grows by 1.11, 1.12, 5.8, 6.19 and 9.6 from this ledger, and 1.18 and 4.8 are candidates |

Rows no drill reaches, with their reason: 1.18 (no split group), 2.26 (no scanner failure at
release can be induced within Decision 13's rules), 3.13 (an unreadable origin cannot be
induced without harming the day's run), 3.15 (a dismissed alert waits for a real alert),
4.8 and 4.9 (the review-by date is 2026-11-24). The one `defect` row is 6.55: the
attested scan reports have carried empty database fields since the first release-time
scan; the ledger keeps it until the fix lands and a new attestation shows the fields.
