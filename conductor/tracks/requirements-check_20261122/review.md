# The requirements checked against the code: review, 2026-11-23

**Subject:** `main` at `b8f18441f873115a7c43f720a2b27989e3bc7e84`, the 162 live criteria of `.specs/dhc-catalogue-mvp/requirements.md` (Requirements 1 to 7 and 9; 8 retired), and the reader documents that describe them (README.md, SECURITY.md, docs/user-manual.md, docs/CONVENTIONS.md, triage/README.md, design.md, docs/lanes.md). Track `requirements-check_20261122`, phase 1 (task 20.1).

**Method, as done.** The method of the review of 2026-09-09: criterion by criterion, from the files on disk; the mechanism named with `file:line`; one verdict each: HELD (implemented and enforced), PARTIAL (implemented with a stated gap), NOT HELD (no mechanism found) or OWNER-SIDE (live GitHub or registry state the files cannot show, with the daily check named). Comments, ticked boxes and design prose are claims; the code is the evidence.

1. Nine readers, one read-only agent each, read the commit above: Requirements 1, 2, 3, 4, 5, 6 (criteria 1 to 30), 6 (31 onward), 7 and 9. Each gave a Criteria table, numbered findings (r1.1, r2.1, ...) and a Counts section.
2. Six re-checkers, each a second agent, verified every finding of one or more readings from the code. They saw only each finding's title, not the first reader's reasoning. A seventh re-check, of r6a.4 alone, came after the others; its re-checker saw the finding's first line, not only the title. Each left a finding CONFIRMED, NARROWED or REFUTED, with its own severity.
3. Every negative path was probed on a scratch copy (under /tmp), never on the tree.
4. The raw readings and re-checks are kept unedited in [`readings/`](./readings/README.md), with their checksums in `readings/SHA256SUMS`. Every claim and `file:line` below comes from them.

This review takes each finding as its re-check left it, merges the same problem found by several readers into one finding, and keeps the reader ids so each finding traces to the raw files.

**What could not be read.** The Renovate run's log is kept on a storage host this machine cannot reach. So the GitHub Actions finding (F12) rests on three things: the code (renovate.json5 and Renovate 41.173.1's own source), a reproduction of the failing refresh on a scratch copy, and the Dependency Dashboard listing (ten Actions updates under "Other Branches"), which is unconfirmed input from the documentation track: no reader or re-checker could read it from the files. What the files do show: no Actions bump has reached main (git log, re-check). Other live state the files cannot show (the live ruleset, registry contents, token scopes) is named where it matters and is not counted as read.

**Line numbers** cite the commit above. Paths are relative to the repository root unless a reader cited a tool's own source ("Renovate dist").

## Verdict

Of 162 live criteria, **93 are HELD, 63 PARTIAL, 2 NOT HELD and 4 OWNER-SIDE**. No re-check changed a criterion's verdict.

| Group | Live | HELD | PARTIAL | NOT HELD | OWNER-SIDE | 2026-09-09 (live: H / P / NH / OS) |
|---|---|---|---|---|---|---|
| 1 image definitions | 17 | 9 | 8 | 0 | 0 | 17: 14 / 3 / 0 / 0 |
| 2 build and release | 27 | 19 | 7 | 0 | 1 | 23: 17 / 5 / 0 / 1 |
| 3 upstream tracking | 14 | 11 | 3 | 0 | 0 | 11: 10 / 1 / 0 / 0 |
| 4 chart adaptation | 9 | 3 | 6 | 0 | 0 | 9: 6 / 3 / 0 / 0 |
| 5 integration tests | 10 | 6 | 4 | 0 | 0 | 8: 8 / 0 / 0 / 0 |
| 6 CVE triage, 6.1 to 6.30 | 24 | 14 | 8 | 2 | 0 | 51 (whole group): 39 / 8 / 3 / 1 |
| 6 CVE triage, 6.31 onward | 29 | 16 | 12 | 0 | 1 | (in the line above) |
| 7 conventions | 11 | 4 | 7 | 0 | 0 | 10: 8 / 2 / 0 / 0 |
| 9 posture | 21 | 11 | 8 | 0 | 2 | 18: 12 / 4 / 0 / 2 |
| **total** | **162** | **93** | **63** | **2** | **4** | **147: 114 / 26 / 3 / 4** |

**Against 2026-09-09.**

- HELD fell from 114 of 147 to 93 of 162; PARTIAL rose from 26 to 63. The readings do not explain the shift criterion by criterion; the appendix gives each verdict and its gap.
- One pattern accounts for part of it. Three Requirement 1 criteria (1.11, 1.16, 1.18) and 5.10 are PARTIAL only because a later validate step is skipped when an earlier one fails (F39); the 2026-09-09 review's verdict named the same shape ("a check that runs unless an earlier step failed").
- NOT HELD fell from 3 to 2. 6.14 and 6.22 remain NOT HELD. 6.15 is now PARTIAL: lint-log-anchors.sh checks that a citation resolves, not what it cites (F66); same mechanism as 2026-09-09; the verdict call differs.
- The four OWNER-SIDE are 2.4, 6.44, 9.2 and 9.4, the same four as on 2026-09-09.

**Findings.**

- **Before merging:** 131 findings in the nine readings (code and document findings together).
- **Re-checked:** 131 (all). 124 CONFIRMED, 6 NARROWED (r3.3, r3.8, r6a.12, r6b.9, r9.11, r9.15), 1 REFUTED (r4.10, see "Dropped"). r6a.4 was re-checked after the others; its re-checker saw the finding's first line, not only the title.
- **Held out, unconfirmed:** 3 claims inside confirmed findings that no re-checker verified (r7.18's lanes.md:190 point; r9.5's M5 date; r9.6's kind node image). See "Held out, unconfirmed".
- **After merging:** **94 findings, F1 to F94**: 4 high, 34 medium, 56 low. 88 rest on confirmed findings only; 6 carry a narrowed statement (F14, F34, F55, F69, F74, F91).
- **By kind:** CODE 35, DOC 31, BOTH 28. So 59 findings carry a document finding (a document states what the code does not do). Before merging, the readers classed 62 findings as document findings; 61 survived the re-check.
- One reader finding (r6a.1) had four separate cases; each case went to the finding it belongs to (F9, F18, F19, F70).

## Time-bound items

1. **The valkey compat decision lapses on 2026-11-24.** chart/valkey/chart.yaml:50 sets `review_by: 2026-11-24`. lint-compat.sh:105-107 fails from 2026-11-25 (probed by r4 and the re-check). From then:
   - every pull request's validate stops at the chart pins and compat step (validate.yml:29-33), and no later lint runs (F39);
   - the daily rescan reports the lapse (check-authenticity.sh:150-168).

   The register asks for a dated re-decision (M13, docs/CONVENTIONS.md:485). Note F17: the lint accepts a review_by change alone, without a new decided_at.
2. **The terms memo's re-verification date, 2026-11-21, has passed** (SECURITY.md:251-252; register row M6, CONVENTIONS.md:478; tasks/todo.md:219 still open). F92.
3. **Req 7.11's obligation is due at task 12.1** (tasks.md:333, still open). Five ledger rows are unexercised (2.26, 2.28, 3.13, 3.15, 4.9), and three give a reason the sentence does not admit (F31).

## Findings

Kinds: **CODE**, the code falls short of the sentence; **DOC**, a document states what the code does not do; **BOTH**. Where a criterion's mechanism is itself a document (9.14, 9.15, 9.19, 9.21), a shortfall is marked CODE: the implementing artifact falls short of the sentence. Severities are the re-checker's; where the readers differ, the first reader's is noted. A "smallest fix" line appears only where a reader gave one.

### High

#### F1. A VEX statement for one package hides every other package's finding under the same CVE id

- **Kind:** BOTH
- **Criterion or document:** Req 2.12, 6.38, 6.41 (status: 6.46); SECURITY.md:23-27 (promise 2)
- **What the sentence says:** 2.12: under fail-closed off, every uncovered finding in the release-time scan gets an `under_investigation` statement with the report's timestamp. 6.38: an `affected` statement for every unexpired exception that no source statement covers. 6.41: `under_investigation` for each lapsed finding the attested report lists. SECURITY.md promise 2: every known finding within the aperture against a supported digest carries a published status.
- **What the code does:** compile-vex.sh:272-273 adds the CVE id to `covered` for any `not_affected` or `fixed` source statement, whatever its subcomponents. compile-vex.sh:364 then skips every reported finding with that id, and :409 every exception-suppressed finding with that id. status.go:309-353 reads the decision by CVE id, so the uncovered package shows as "decided (not_affected)". The release (build.yml:1060-1076) and the daily re-attestation (reattest.sh:201-207) use the same compiler. Probed by r2, r6b and both re-checkers: a statement scoped to package a, a finding on package b, and the output holds only the statement for a.
- **Who or what is affected:** Consumers reading the attested OpenVEX document, and the status clocks. A consumer's Trivy still reports package b, so no scanner is misled; the document is silent. The cve issue is still filed from the report. Latent: it needs one CVE id on two packages of one image.
- **Severity:** high (latent), per re-check of r6b.1; the re-check of r2.1 and r2.16 and the r2 reader gave medium.
- **Sources:** r2.1, r2.16, r6b.1; re-check: confirmed (all three).

#### F2. A chart in the harness but missing from the spec list passes e2e with nothing installed

- **Kind:** BOTH
- **Criterion or document:** Req 5.2; docs/user-manual.md:1225-1227 and :1326-1332, design.md:990 and :1272 (the onboarding steps)
- **What the sentence says:** Each affected chart that deploys an active definition is installed on kind. The onboarding steps say "register the component in the e2e harness (`test/harness`)".
- **What the code does:** The matrix comes from chart/*/chart.yaml `deploys:` (e2e.yml:58, definition-lib.sh:156-170). TestMain only checks that the name is in harness.Components (e2e_suite_test.go:63-67; test/harness/harness.go:21-26). The specs iterate a second, hand-kept list, componentSpecs (test/e2e/components_test.go:25-48), and skip every name that is not selected (components_test.go:58-59, upgrade_test.go:33-34). A name in the harness but not in componentSpecs runs zero specs; Ginkgo exits 0, the leg and the e2e gate (e2e.yml:291-293) are green. No test ties the two lists (harness_test.go checks the registry alone). No document names componentSpecs.
- **Who or what is affected:** The owner and a fork. The first chart PR of an onboarding is the image's first live proof (Decision 14); it would merge on a green gate that installed nothing. Not reachable on today's four charts (both lists hold the same four). The re-checker made no cluster run; the verdict rests on the code.
- **Severity:** high (latent); r5.4 is "high in effect, low as wording" in both readings.
- **Sources:** r5.1, r5.4; re-check: confirmed (both).

#### F3. A failed read of yesterday's OpenVEX document resets every first-seen time, and the run stays green

- **Kind:** CODE
- **Criterion or document:** Req 6.40 (and the first-seen clauses of 6.38, 6.41)
- **What the sentence says:** The compile keeps each statement's timestamp and stamps `last_updated` only on a change.
- **What the code does:** reattest.sh:178-181 runs `cosign verify-attestation ... || true` with no retry (unlike fetch-sboms.sh:48-61). A Sigstore or registry blip gives previous_n=0 and an empty previous document (:184-187), so COMPILE_VEX_PREVIOUS is unset (:203). compile-vex.sh:189-190 then stamps today's report time as first seen. "differs" is true when no previous document is given (reattest.sh:214-222), so the document is re-attested with `--replace` (:229-236) and counts as a success (:276). The next day reads the reset document, so the loss is permanent. The status survives through status.go:474-479. No probe; reasoned from the code path.
- **Who or what is affected:** Every consumer of the attested document's timestamps.
- **Severity:** high (both readers).
- **Sources:** r6b.2; re-check: confirmed.

#### F4. A GitHub error in the status lookup loses the clock history and opens a second status issue

- **Kind:** CODE
- **Criterion or document:** Req 6.46, 6.47
- **What the sentence says:** The status persists first seen, decided and fixed dates from day to day, in one status issue.
- **What the code does:** rescan.yml:752-753 runs `number=$(gh issue list ... || true)`. On an API error the number is empty, previous.md is empty (:757-758), and rescan-status only warns (main.go:173-175). Fixed rows and their days-to-fix need the previous data (status.go:489-505) and drop out. status_publish then creates a new "Catalogue status" issue (rescan.yml:874-880). From then on the lookup takes the first of two open matches (:753), so which history continues depends on search order.
- **Who or what is affected:** The published status and page, and the owner's view. Nothing fails.
- **Severity:** high (both readers).
- **Sources:** r6b.3; re-check: confirmed.

### Medium

#### F5. Floating builder references outside the lint's keys pass validation

- **Kind:** BOTH
- **Criterion or document:** Req 1.2, 1.6; docs/CONVENTIONS.md:72, docs/user-manual.md:324-326 and :1646, design.md:1749
- **What the sentence says:** Every base image reference is pinned by sha256 (1.2); a floating tag fails validation naming it (1.6). The documents say "Floating tags ... fail CI" and "every image reference digest-pinned".
- **What the code does:** lint-pins.sh:39-76 reads only lines keyed `image:`, `base:` or `uses:` in block style, and :61-65 skips a `uses:` whose first segment has no dot. Probes (exit 0): `uses: golang:1.25-alpine`, `uses: library/golang:1.25-alpine`, `GOLANG_REFERENCE: dhi.io/golang:1.27` (r1); flow-style `- {name: ..., uses: "dhi.io/golang:..."}` (re-check). Control: block-style `uses: dhi.io/golang:1.27` exits 1. What keeps it safe today is Renovate's docker manager (renovate.json5:84-88), which matches only pinned `dhi.io/...@sha256`.
- **Who or what is affected:** A release built from a mutable builder tag after an unreviewed slip; its content can change between builds with no red check.
- **Severity:** medium (code); the document half r1.6 is low.
- **Sources:** r1.1, r1.6; re-check: confirmed (both).

#### F6. The shape of a source pin is not checked before merge

- **Kind:** BOTH
- **Criterion or document:** Req 1.3; docs/CONVENTIONS.md:143-145, :159-171
- **What the sentence says:** A git ref plus a commit checksum, or a versioned URL plus a per-arch checksum. CONVENTIONS.md says each rule is held by lint-pins.sh unless another gate is named, and that every `git+` line has a sibling `checksum:` (commit hash).
- **What the code does:** lint-pins.sh:117-123 only compares the number of `git+` lines with the number of `checksum:` lines. Probes (exit 0): a `git+` url with no `#ref`; `checksum: main` or `abc` (not a hash); grafana with `GRAFANA_SHA256` and the `sha256sum -c` step removed, after which verify-arch-pins.sh:59-62 prints "nothing to verify" and exits 0. Caught only by the daily check-authenticity.sh (:98, :122), after main has built, signed and tagged, and only for active definitions. The re-check adds that the PR build would probably fail a wrong git checksum on fetch, but a branch ref and a missing tarball pin get through. Second error in the same rule: CONVENTIONS.md:164 gives the tarball URL as `<name>-<ver>.linux-${ARCH}.tar.gz`, the alias shape the grafana definition rejects (image/grafana/image.yaml:22-32, :59).
- **Who or what is affected:** A release can ship before the rescan flags it.
- **Severity:** medium (code); the document half r1.7 is low.
- **Sources:** r1.2, r1.7; re-check: confirmed (both).

#### F7. A flow-style package repository list skips the /main check

- **Kind:** BOTH
- **Criterion or document:** Req 1.12; the anatomy sketches docs/user-manual.md:1150-1183 (:1155, :1163, :1175), design.md:1677
- **What the sentence says:** Only the /main package repository is admitted.
- **What the code does:** The awk at lint-pins.sh:160-173 reads repositories only after a line that is exactly `repositories:`. `repositories: [https://dhi.io/apk/alpine/v3.23/security, ...]` exits 0 (probed by both readers; PyYAML reads the /security entry). lint-pins.sh:193-196 refuses flow style for `vars:` and `tags:` but not `repositories:`. The manual's anatomy is written in flow style: `tags: [...]` is refused loudly, `repositories: [...]` is not checked, and the flow-style `uses:` (:1175) is not seen by the pin check (F5).
- **Who or what is affected:** An entitlement-gated repository could enter a definition silently; a reader copying the anatomy gets a red lint for tags and unchecked repositories and builder refs.
- **Severity:** medium (code); the document half r1.11 is low.
- **Sources:** r1.3, r1.11; re-check: confirmed (both).

#### F8. The daily checks only see repositories that still have a definition on disk

- **Kind:** BOTH
- **Criterion or document:** Req 2.21, 2.22, 2.24, 9.7; README.md:72-74
- **What the sentence says:** 2.21: every catalogue repository under its declared namespace. 2.22: every catalogue tag in every catalogue repository. 2.24: every digest a catalogue tag references. 9.7: a tag that references a recorded (revoked) digest is reported.
- **What the code does:** enumerate-catalogue.sh:57-67 builds the repository list from image/*/image.yaml; check-visibility.sh:100-103 does the same; verify-catalogue.sh:76-78 and check-revocations.sh:37-51 read only the enumeration. Nothing lists the registry namespace. Deleting a definition directory is allowed (lint-active-set.sh:20-21; CONVENTIONS.md:534-535) and has happened: drill-app left in b90900f (#378); triage/LOG.md:4260 records "no drill-app tag enumerated". The only revocation record entry (revocations.yaml:24) is drill-app. Whether drill-app tags still resolve is registry state the files cannot show; the ledger says the version was deleted.
- **Who or what is affected:** A consumer pulling a tag in such a repository gets a digest no longer scanned, re-attested, visibility-checked, admission-proved or revocation-checked, with a green rescan.
- **Severity:** medium (both readers, both re-checks). Latent per the re-check of r2.2: design keeps directories on deactivation (catalogue-policy.yaml:76-82).
- **Sources:** r2.2, r9.1; re-check: confirmed (both).

#### F9. A failed scan of a platform manifest leaves the daily rescan green

- **Kind:** BOTH
- **Criterion or document:** Req 2.22, 6.3, 6.42 (6.51); rescan.yml:321-324 (comment), design.md:1229-1230, design.md:1697 (error table), user-manual.md:620
- **What the sentence says:** 2.22: the rescan scans every platform manifest. 6.3: an issue for every new finding in a supported digest. 6.42: the day's scan report re-attested. The comment says "The run is red by the digest's name either way"; design.md:1697 says a Trivy DB outage means the rescan "soft-fails with issue".
- **What the code does:** rescan.yml:145-149 has no `set -e`; a failed scan is a `::warning::`, counted (:200-206), and the step exits 0 (:210-218). reattest.sh:134-140 records the digest as `skipped`, and :276 fails only on `failed`. Only the summary reads `steps.scan.outputs.failed` (:954). check-exceptions.sh then finds no report and tiers that image by the largest ceiling (:101, :125-126). No issue is filed for a scan or DB failure (issues only for findings, :667-689, and supply-chain, :452-484). The lifecycle keeps issues open for the unscanned digest (lifecycle.go:257-274), and the run may go red through the smoke test's own trivy run (consumer-smoke.sh:151), not through the scan step. rescan.yml:18-20 and docs/lanes.md:731, :757 describe skip-and-count correctly.
- **Who or what is affected:** The owner's view: a green rescan on a day a manifest was not scanned; that digest's attested report and OpenVEX stay at the last successful day; its new findings get no issue that day.
- **Severity:** medium (code findings); the error-table document findings r6a.20 and r6b.16 are low (r6a reader: medium).
- **Sources:** r2.3, r6a.1 (case 3), r6b.4, r6a.20, r6b.16; re-check: confirmed (all).

#### F10. One definition's failed build does not stop the others in the same run from publishing

- **Kind:** BOTH
- **Criterion or document:** Req 2.5; build.yml:13-14 (comment), docs/user-manual.md:506
- **What the sentence says:** When a build fails, publish no artifacts from that run. The comment and the manual say "Any failure publishes nothing".
- **What the code does:** build.yml:182-185 sets `fail-fast: false` over the definitions matrix. Each leg pushes, signs, attests and tags on its own (build.yml:941-1241), so the healthy legs release while the run is red (gate :1247-1250). Within one leg the code holds: a later failure leaves the digest untagged (user-manual.md:657-658 says this correctly). docs/lanes.md:557 calls the per-leg reading intended.
- **Who or what is affected:** A merge touching two definitions, or the nightly over seven. Whether the sentence means "from that leg" is a wording question; as written the code does not do it.
- **Severity:** medium.
- **Sources:** r2.4; re-check: confirmed.

#### F11. The published verify recipe has no pipefail, so failed SBOM and OpenVEX checks exit 0

- **Kind:** BOTH
- **Criterion or document:** Req 2.25, 9.13; README.md:80-106 and the manual's copy (user-manual.md:161-187)
- **What the sentence says:** The published recipe verifies the artifacts (2.25), and the daily smoke test runs it verbatim (9.13).
- **What the code does:** render-verification.sh:191-213 writes `cosign verify-attestation ... | jq ...` with no `set -o pipefail` (README.md:89-93). Measured: `false | jq -r .x` exits 0, and the OpenVEX step writes an empty openvex.json. Not affected: the signature step (not piped) and the provenance step (`jq -es any(...)` exits 1 on empty input, measured). consumer-smoke.sh:98 runs each step under `bash -o pipefail` in its own shell, and the run is logged in to ghcr.io (rescan.yml:106-111), so the daily test proves a stricter recipe than the one published. docs/lanes.md:1092, :1107-1108, :1143 record it as an open item.
- **Who or what is affected:** A consumer scripting the recipe gets exit 0 on a failed SBOM or VEX verification; the daily proof does not cover what the consumer runs.
- **Severity:** medium (re-checks); the r9 reader gave high.
- **Sources:** r2.8, r9.4; re-check: confirmed (both).

#### F12. Every GitHub Actions bump runs the definition refresh script, which fails there

- **Kind:** BOTH
- **Criterion or document:** Req 3.2, 7.6 (also 3.1, 3.14); docs/user-manual.md:1707, docs/lanes.md:80-118 (:106), docs/CONVENTIONS.md:92-94
- **What the sentence says:** 3.2: a matching upstream release opens a PR with ref, checksum and tags updated. 7.6: every pinned executable carries a manager that opens a PR. The manual's Actions row says postUpgradeTask "none"; lanes.md routes "any other pin" to no task.
- **What the code does:** The `postUpgradeTasks` rule is keyed on `matchDatasources: ["github-tags"]` (renovate.json5:414-422). The built-in github-actions manager (enabled at :12) resolves every `uses:` through github-tags (Renovate 41.173.1 manager/github-actions/extract.js:71); the Actions rule (:465-474) sets only automerge false. The allowlist (renovate.yml:57) admits the command. `scripts/refresh-definition.sh .github/workflows` exits 1, "refresh: no image.yaml in .github/workflows" (refresh-definition.sh:36; reproduced on copies by r3 and the re-checker). Renovate then records an artifact error; a release younger than 2 h opens no PR, an older one opens with a failed renovate/artifacts status (branch/index.js:458-471, :755-790). triage/LOG.md:1312-1320 and renovate.json5:428-431 record the same failure shape aborting a whole run. No fixture checks which rules carry a postUpgradeTask (managers.test.mjs:890-895). No Actions bump has ever reached main (git log, re-check).
- **Who or what is affected:** Actions bumps (7.6), Actions security fixes, and possibly definition bumps queued in the same run. The files cannot show which outcome occurs live.
- **Severity:** medium (code); the document halves r3.5 and r7.13 are low.
- **Smallest fix (a reader's):** The precedent for the same collision (grafana, keyed by name, renovate.json5:426-433) was never applied to the github-tags rule (r3.1).
- **Sources:** r3.1, r7.7, r3.5, r7.13; re-check: confirmed (all four).

#### F13. More updates skip the three-day release age than the requirement allows

- **Kind:** BOTH
- **Criterion or document:** Req 3.7; docs/user-manual.md:757-758, :1720-1721, design.md:491-493 (Decision 8 (a)), docs/CONVENTIONS.md:306-310
- **What the sentence says:** Every PR bumping a pinned third-party version waits three days, exempting only the docker datasource of catalogue digests and the hand-reviewed build layer.
- **What the code does:** The age rule lists six datasources (renovate.json5:374-394). Outside it: (1) the third-party probe image PROBE_IMAGE (e2e.yml:124; docker datasource, renovate.json5:198-210); (2) every vulnerability-alert PR, by Renovate's default `minimumReleaseAge: null` applied with force (config/options/index.js:2046-2056; init/vulnerability.js:163-165), not overridden at renovate.json5:46-48; (3) the `go` directives in test/go.mod:3 and triage/rescan/go.mod:3 (golang-version datasource); (4) versioned runners such as `ubuntu-24.04` (e2e.yml:110, github-runners datasource; found by the re-check). (3) and (4) are latent. docs/lanes.md:73 alone names the probe image.
- **Who or what is affected:** The owner's claim that every third-party bump is aged. The alert case is an unrecorded settlement of a conflict between 3.7 and 3.14. A consumer is not directly affected.
- **Severity:** medium (code); the document half r3.6 is low.
- **Sources:** r3.2, r3.6; re-check: confirmed (both).

#### F14. Security alerts on GitHub Actions open no fix pull request, and a failed alert read does not fail the run

- **Kind:** BOTH
- **Criterion or document:** Req 3.14; CONVENTIONS.md:497 (M25), docs/user-manual.md:1418 (RENOVATE_TOKEN row)
- **What the sentence says:** A security alert opens a fix PR whatever the dependency's update scope. M25 names "the CI pins" among them. The manual lists the token's scopes as "contents + pull-requests + issues write".
- **What the code does:** Narrowed by the re-check. Holds: Renovate maps alert ecosystems composer, go, maven, npm, nuget, pip, rubygems and rust only (init/vulnerability.js:70-79), so an `actions` alert matches nothing and opens no PR. The alert read needs RENOVATE_TOKEN's "Dependabot alerts: read" scope (renovate.yml:13-17; renovate.json5:34-35), which no daily check asserts and the manual's row omits (it also omits `statuses: write`, triage/LOG.md:1317-1320). Does not hold as "silently": a failed read logs a WARN that Renovate writes to the Dependency Dashboard under "Repository problems" (dependency-dashboard.js:207-216); the run stays green and no issue is filed.
- **Who or what is affected:** The repository's own tooling security fixes, which the owner believes are automatic; a token rotated by the manual loses 3.14 with nothing red.
- **Severity:** medium (code); the document half r3.7 is low.
- **Sources:** r3.3 (narrowed), r3.7; re-check: r3.3 narrowed, r3.7 confirmed.

#### F15. A chart pin can be a version range

- **Kind:** CODE
- **Criterion or document:** Req 4.1
- **What the sentence says:** The upstream chart is consumed at its pinned version.
- **What the code does:** chart/chart.schema.yaml:31 types `upstream.version` as `str()`. It is passed verbatim to `helm template --version` (render-chart.sh:19-23) and `helm install --version` (install.go:86-93); install.go:43 checks only that it is non-empty. Helm reads the flag as a constraint. The Renovate regex (renovate.json5:298) captures any token. Probe (re-check): `version: ">=0.0.0"` passes yamale and lint-compat, and render-chart.sh resolved a newer chart. No digest or `--verify` is recorded, so a republished version also goes unseen. Today every pin is exact.
- **Who or what is affected:** A release's deployed chart could move without a diff.
- **Severity:** medium (re-check); the r4 reader gave low.
- **Sources:** r4.1; re-check: confirmed.

#### F16. The non-root policy checks the pod only, not its containers

- **Kind:** BOTH
- **Criterion or document:** Req 4.6; docs/CONVENTIONS.md:388-391, docs/lanes.md:398, docs/user-manual.md:412-415, .github/PULL_REQUEST_TEMPLATE.md:27, design.md:1748
- **What the sentence says:** The Kyverno gate requires non-root execution. The documents say it holds "workloads non-root".
- **What the code does:** policies/require-nonroot.yaml:16-28 checks only `spec.securityContext.runAsNonRoot: true`. Probe (kyverno 1.18.2, both readers): pod runAsNonRoot true with a container `runAsNonRoot: false, runAsUser: 0` (r4 also `privileged: true`) passes, exit 0. The e2e check (test/checks/securitycontext.go:53-73) would catch it on a live pod, on PRs only. user-manual.md:1299-1302 and chart/valkey/README.md:43 state the pod-level limit correctly.
- **Who or what is affected:** The chart gate is weaker than stated; a release is protected only through the e2e.
- **Severity:** medium (code); the document half r4.9 is low.
- **Sources:** r4.3, r4.9; re-check: confirmed (both).

#### F17. Moving the review-by date alone clears a lapsed compat decision

- **Kind:** BOTH
- **Criterion or document:** Req 4.8; docs/CONVENTIONS.md:485 (M13), chart/valkey/README.md:124-125, chart/valkey/chart.yaml:33-35, lint-compat.sh:15-16 and :106
- **What the sentence says:** Validation fails until the decision carries a fresh review-by date from a dated re-decision.
- **What the code does:** lint-compat.sh:91-108 fails only if review_by is missing, before decided_at, or before today. It never requires decided_at to move and sets no upper bound. Probes: review_by 2099 with decided_at 2026-08-25 passes (DHC_TODAY 2026-11-25 by r4, 2026-12-01 by the re-check); the real block fails.
- **Who or what is affected:** The owner's view: a lapse can be cleared without a dated re-decision. It bears on the valkey date of 2026-11-24 (see "Time-bound items").
- **Severity:** medium (code); the document half r4.8 is low (re-check; r4 reader: medium).
- **Sources:** r4.5, r4.8; re-check: confirmed (both).

#### F18. A failed EPSS fetch files issues with "n/a" for good

- **Kind:** CODE
- **Criterion or document:** Req 6.3
- **What the sentence says:** An issue for every new finding with severity, EPSS score, KEV status and affected images.
- **What the code does:** rescan.yml:612-613 replaces a failed EPSS fetch with `{"data":[]}`; report.go:251-254 then writes "n/a". The step stays green, and dedup (rescan.yml:630-634) means the issue is never re-enriched. GHSA ids always get "n/a" (only `^CVE-` ids are sent, rescan.yml:216-217, :602).
- **Who or what is affected:** The owner's triage queue and anyone reading the issue.
- **Severity:** medium (r6a.1 as a whole).
- **Sources:** r6a.1 (case 1); re-check: confirmed.

#### F19. A KEV file that does not parse still files the day's issues with "KEV: no"

- **Kind:** BOTH
- **Criterion or document:** Req 6.3, 6.60; docs/lanes.md:877, docs/user-manual.md:575-577, rescan.yml:603-606 (comment)
- **What the sentence says:** 6.60: a KEV failure fails the run. The documents say "no issue set is built on a KEV status nobody evaluated".
- **What the code does:** The run does go red: check-exceptions.sh:57-61 exits 2, rc=1 at rescan.yml:423, and rescan-status refuses (main.go:145-149). But enrich and report test only that the file is non-empty (rescan.yml:607, :642-644), and rescan-report warns and continues with an empty KEV map (cmd/rescan-report/main.go:62-67). file_issues (:667-689) files the issues with "KEV | no" (report.go:268). Probed by r6b (three issues with "KEV | no", exit 0), by r6a, and by the re-check of r6a (`<html>`: the issue says KEV `no`, exit 0). The KEV field is fixed at filing.
- **Who or what is affected:** Anyone reading the issues; the content is wrong for good.
- **Severity:** medium.
- **Sources:** r6a.1 (case 2), r6a.21, r6b.7; re-check: confirmed (all).

#### F20. The daily expiry report cannot fail, and prints "none" when its lint did not run

- **Kind:** CODE
- **Criterion or document:** Req 6.10
- **What the sentence says:** The daily run reports every exception within the warning window of its expiry.
- **What the code does:** rescan.yml:580 runs `lint-accepted-risk.sh ... || true` and greps for `expires in|is in the past` (:581); the step has no `-e` and ends on printf. Probes (r6a and re-check): with the policy's `expiry_warning` removed or PyYAML unimportable, the step printed "_none_" and exited 0. The status step only checks that accepted-risk.txt exists (rescan.yml:809), so the page shows no lapsing exceptions either. Two more silent skips are blocked by validate on a PR (lint-accepted-risk.sh:167-170, :201-205).
- **Who or what is affected:** The owner's view, and the page (rescan.yml:855).
- **Severity:** medium.
- **Sources:** r6a.3; re-check: confirmed.

#### F21. govulncheck can fail to run with the pull request green, and some Go binaries are never looked at

- **Kind:** BOTH
- **Criterion or document:** Req 6.13; triage/README.md:154, docs/lanes.md:350, design.md:1395, the manual's step 6
- **What the sentence says:** govulncheck runs over every Go binary in the image and reports per finding.
- **What the code does:** build.yml:775 `continue-on-error: true`: the step's own `exit 1` (:792-796, :854-857) leaves the leg and the required build gate green; nothing reads its outcome. Only files over 1 MiB are tried (:824). `docker export ... || true` (:804-805) lets a partial filesystem through. PR builds are linux/amd64 only (:434), so arm64 binaries are never measured (re-check).
- **Who or what is affected:** A reviewer relying on the evidence for 6.14 and 6.15.
- **Severity:** medium (code); the document half r6a.18 is low.
- **Sources:** r6a.5, r6a.18; re-check: confirmed (both).

#### F22. Nothing stops a "not in execute path" statement on code govulncheck found reachable

- **Kind:** CODE
- **Criterion or document:** Req 6.14 (NOT HELD)
- **What the sentence says:** No not_affected / vulnerable_code_not_in_execute_path statement for a binary whose symbol govulncheck reports reachable.
- **What the code does:** The prohibition is only printed (govulncheck-report.sh:16-18, build.yml:849-850). The govulncheck JSON is not uploaded (build.yml:919-927), and nothing reads it against triage/vex/. Probe (re-check): every statement rewritten to that justification passes lint-vex-product.sh and lint-log-anchors.sh. Design Decision 7 (design.md:447-451) assigns it to the maintainer at review.
- **Who or what is affected:** A consumer, whose scanner would suppress a reachable finding. It takes a reviewer's error, but nothing else catches it.
- **Severity:** medium.
- **Sources:** r6a.6; re-check: confirmed.

#### F23. Nothing keeps a superseded VEX statement, though the documents call the rule lint-enforced

- **Kind:** BOTH
- **Criterion or document:** Req 6.22 (NOT HELD); triage/README.md:361 and :370, docs/user-manual.md:1004
- **What the sentence says:** A superseded statement is kept and the new one is appended with a later timestamp. The documents list the rule among those "all lint-enforced".
- **What the code does:** No lint, test or compiler rule checks retention or order. lint-vex-product.sh has no timestamp or supersession rule (its header lists 6.17, 6.19, 6.20, 6.39); compile-vex.sh:235-275 merges every surviving statement with no order check. Probe (re-check): statements rewritten in place pass.
- **Who or what is affected:** A consumer reading the attested history, and Trivy's choice between conflicting statements.
- **Severity:** medium.
- **Sources:** r6a.9, r6a.13; re-check: confirmed (both).

#### F24. A failed read of the open-issue map is replaced by an empty map

- **Kind:** CODE
- **Criterion or document:** Req 6.37 (6.40)
- **What the sentence says:** The compile is given the open issue map, among its inputs.
- **What the code does:** rescan.yml:280-282: `gh issue list ... > issues.json || echo '{}' > issues.json`. The reattest guard checks only that the file is non-empty (:300-302). compile-vex.sh:127-133 reads `{}` as "no open issues". Issue links are part of the change shape (compile-vex.sh:193-199), so every statement that had a link gets last_updated today and is re-attested without links, and again the next day when the links return. The same pattern in the dedup step (rescan.yml:630) would re-file every open finding on a gh failure.
- **Who or what is affected:** Consumers of the document's links and timestamps.
- **Severity:** medium.
- **Sources:** r6b.5; re-check: confirmed.

#### F25. The rescan keys exceptions and reports by the repository name, not the definition

- **Kind:** CODE
- **Criterion or document:** Req 6.38, 6.41, 6.51
- **What the sentence says:** Exceptions apply to the definition's digests and are tiered against its reports.
- **What the code does:** rescan.yml:176 and reattest.sh:118 set `name="${repo##*/}"` and pass it as the definition to compile-vex.sh (rescan.yml:192, reattest.sh:205) and scan-image.sh (:200). valkey-compat publishes to .../valkey (image/valkey-compat/image.yaml:18), so its digests would be compiled against valkey.yaml, while the release path uses valkey-compat.yaml (build.yml:555, :562, :1076). check-exceptions.sh looks for valkey-compat__*.json (:99-101), which never exists, so tiers fall to the largest ceiling.
- **Who or what is affected:** Latent: triage/accepted-risk/ holds only grafana.yaml today. Once a valkey-compat file exists, the release document's affected statements are dropped by the next rescan.
- **Severity:** medium (latent).
- **Sources:** r6b.10; re-check: confirmed.

#### F26. A KEV response that parses but holds no list reads as "nothing is KEV-listed"

- **Kind:** CODE
- **Criterion or document:** Req 6.59, 6.60 (6.50)
- **What the sentence says:** A KEV feed that cannot be read fails the gate (6.59) and the rescan (6.60).
- **What the code does:** check-exceptions.sh:58 reads `.get("vulnerabilities") or []`; ParseKEV (report.go:367-377) returns an empty map too. The fetch checks only HTTP success (build.yml:889-890, rescan.yml:422). Probes (r6b and re-check): `{}` and `{"message":"rate limited"}` give exit 0 in gate and rescan modes, every exception tiered by severity or the largest ceiling; the re-check of r6a found the whole run green on `{}`. Non-JSON is refused.
- **Who or what is affected:** Tiers, issue KEV fields and the status's KEV ceilings all silently read "not listed".
- **Severity:** medium.
- **Sources:** r6b.6, r6a.1 (re-check, the {} case); re-check: confirmed.

#### F27. The page read-back checks the date, not the run

- **Kind:** BOTH
- **Criterion or document:** Req 6.62; docs/user-manual.md:942-943
- **What the sentence says:** The run confirms the deployed page is its own. The manual says "until its generated_at is the run's".
- **What the code does:** generated_at is a YYYY-MM-DD date (status.go:364, :546-548; rescan.yml:864). The read-back compares only that (rescan.yml:1066-1069). A second run the same day (a dispatch or kev-synthetic drill) whose deployment did not take passes on the earlier run's page.
- **Who or what is affected:** The owner's confidence that the page is current.
- **Severity:** medium.
- **Smallest fix (a reader's):** The data already carries `run` (status.go:137, set at :549), which would identify the run (r6b.8).
- **Sources:** r6b.8; re-check: confirmed.

#### F28. Some codified conventions have no CI check

- **Kind:** CODE
- **Criterion or document:** Req 7.4
- **What the sentence says:** A PR that violates a codified convention fails CI, naming it.
- **What the code does:** CONVENTIONS.md says of itself "reviewers hold the rest" (:3-4) and "a rule naming none is a convention held at review" (:144-145). With no CI step: alpine only (:176-179); the modification notice on catalog-derived definitions (:184-196); the ldflags stamp and dotted annotation keys (:296-298); upstream templates never edited (:352); chart deltas only in values-hardened.yaml and deviations in the README (:353-373); one emptyDir per path with a comment (:369-370); one change per PR, the TL;DR and requirement ids (:516-524); the hand-bump PR description (:107-108); the Grype second opinion (:410); the full release tag shape (:9-15; lint-pins.sh:101-115, :242-252 check only OCI form and the version).
- **Who or what is affected:** The owner's view: these violations reach review only.
- **Severity:** medium.
- **Sources:** r7.2; re-check: confirmed.

#### F29. The Renovate validator's npm dependency tree is not pinned

- **Kind:** CODE
- **Criterion or document:** Req 7.5
- **What the sentence says:** Every third-party executable a workflow installs is pinned to an exact version with a checksum recorded here.
- **What the code does:** validate.yml:332-340: `npm install --no-save renovate@41.173.1 json5@2.2.3`, with no lockfile or shrinkwrap. The top two are exact; renovate pins its 118 direct deps, but their own dependencies use ranges (measured by the re-check), so the tree resolves at install time and npm checks only the registry's integrity field.
- **Who or what is affected:** Every validate run: a required check executes several hundred third-party packages no pin here names. The job holds only `contents: read`.
- **Severity:** medium.
- **Sources:** r7.5; re-check: confirmed.

#### F30. Executables picked by action defaults carry no version or checksum here

- **Kind:** BOTH
- **Criterion or document:** Req 7.5; docs/user-manual.md:315-318, docs/CONVENTIONS.md:78-80 (qualified at :85-90), docs/live-evidence.md:206 (row 7.5)
- **What the sentence says:** Every executable is pinned with a checksum recorded here. The ledger says "Every install step verifies a sha256".
- **What the code does:** docker/setup-qemu-action (build.yml:193, no `with:`; default tonistiigi/binfmt:latest); docker/setup-buildx-action (build.yml:194; default moby/buildkit:buildx-stable-1, which runs every release build); actions/setup-go (validate.yml:350-353, e2e.yml:131-134, rescan.yml:92-95); renovatebot/github-action (renovate.yml:46-48, no renovate-version). The action SHAs are pinned; the defaults are moving tags, read from the actions' documentation, not re-measured. CONVENTIONS.md:85-90 admits govulncheck (F84) and npm (F29) but not these.
- **Who or what is affected:** A release: a substituted BuildKit image would build what gets signed, with no check here able to notice.
- **Severity:** medium (code); the document half r7.12 is low.
- **Sources:** r7.6, r7.12; re-check: confirmed (both).

#### F31. The ledger lint checks rows, not the LOG half or the reasons

- **Kind:** BOTH
- **Criterion or document:** Req 7.11; docs/live-evidence.md:212 (row 7.11), :211 (row 7.10)
- **What the sentence says:** Every criterion's live evidence is recorded in the ledger and in triage/LOG.md; a criterion may stay unexercised only where a live exercise harms consumers.
- **What the code does:** lint-live-evidence.sh:45-97 (validate.yml:202-203) reads only docs/live-evidence.md: one row per criterion, six cells, a status word, non-empty text. It never reads triage/LOG.md, and any non-empty reason passes for `unexercised` (:88-89). Rows 2.26, 3.15 and 4.9 give other reasons; 2.28 waits on the successor. Row 7.11 is marked exercised on "This file and scripts/lint-live-evidence.sh"; row 7.10 lists no exercise of the dispatch-input half.
- **Who or what is affected:** The owner, at the cut of task 12.1: the lint will be green whether or not the obligation is met. The deadline is still open (tasks.md:333).
- **Severity:** medium (code); the document half r7.17 is low.
- **Sources:** r7.10, r7.17; re-check: confirmed (both).

#### F32. Nothing checks that the committed ruleset keeps requiring the gates

- **Kind:** CODE
- **Criterion or document:** Req 9.8 (HELD today)
- **What the sentence says:** The ruleset export in the repository requires the gate checks.
- **What the code does:** main_sec.json lists "build gate" and "e2e gate" today. Its only reader, check-governance.sh:154-161, compares the committed file with the live ruleset for equality. No step in validate.yml or scripts asserts the export contains the gates (only check-governance_test.sh fixtures name them). An edit that drops a gate from both sides (UI edit, export over the file, .github/rulesets/README.md:30-32) is green everywhere. docs/lanes.md:960 says "a person keeps it in line".
- **Who or what is affected:** Governance could weaken with every check green, while SECURITY.md:157-160 still states five checks.
- **Severity:** medium.
- **Sources:** r9.10; re-check: confirmed.

#### F33. A portability block can be missing, or counted without existing, on a green run

- **Kind:** BOTH
- **Criterion or document:** Req 9.12; docs/user-manual.md:290-291, CONVENTIONS.md:445, design.md:641
- **What the sentence says:** Every PR scan and every rescan publishes a VEX portability block.
- **What the code does:** PR: build.yml:737-759 runs under `set -uo pipefail` without `-e` and `continue-on-error: true` (:739). The authoritative normalisation's exit (:747) is unchecked; vex-portability.sh exits 2 without writing the block (:67-69, probed); `cat .portability/block.md` (:759) fails; the job stays green. Rescan: rescan.yml:513 skips a manifest whose authoritative normalisation fails (counted only as unmeasured); :524 pipes vex-portability.sh into `grep -c ... || true`, losing its exit, and :525 still increments `blocks`. Probe (re-check): a crashing vex-portability with no section written still gave blocks=1, so the summary (rescan.yml:960) can say "n compared" for blocks that do not exist. The rescan step also runs only when the scan succeeded (:498), and the release and nightly arms have no block (build.yml:738). docs/lanes.md:380 lists the PR half as open.
- **Who or what is affected:** The owner's view of a PR or a day: no block and no red; statements on that digest get no portability result.
- **Severity:** medium (code); the document half r9.18 is low. The re-check calls the r9.3 path narrow.
- **Sources:** r9.2, r9.3, r9.18; re-check: confirmed (all three).

#### F34. consumers.gating is documented as failing a run on a divergence; no run can fail on it

- **Kind:** DOC
- **Criterion or document:** Req 9.12; catalogue-policy.yaml:230-232, user-manual.md:294-295, CONVENTIONS.md:446 and :491 (M19), design.md:666-668, lanes.md:822, vex-portability.sh:20-22
- **What the sentence says:** A fork flips `consumers.gating` to fail a run on a divergence.
- **What the code does:** Narrowed by the re-check. vex-portability.sh:149-154 does exit 1 under gating, but every caller discards it: build.yml:739 (continue-on-error), rescan.yml:499 (continue-on-error) plus `|| true` at :524, consumer-smoke.sh:203 (`|| true`). Probe: pipe rc 1, swallowed. What does not hold of "changes nothing": on the PR leg the switch turns lines into `::error::` annotations and marks the step failed-but-continued; in the rescan they are eaten by `grep -c`. lanes.md:1170 records this for the smoke test only.
- **Who or what is affected:** A fork that relies on the switch.
- **Severity:** medium.
- **Sources:** r9.11 (narrowed); re-check: narrowed.

#### F35. The manual-steps register leaves out human steps

- **Kind:** CODE (the mechanism is a document)
- **Criterion or document:** Req 9.14 (the register, docs/CONVENTIONS.md:461-499)
- **What the sentence says:** The register lists every step a human takes (CONVENTIONS.md:463).
- **What the code does:** Steps described elsewhere with no row: keeping main_sec.json's required checks on the gates (lanes.md:960); redrawing a lane in its PR (design.md:1202-1203) (r9 reader); merging and watching an attest-build-provenance bump by hand (user-manual.md:727-746); re-storing a lost provenance statement by hand (:715-725); activating or deactivating a definition (:1253-1288); reviewing from-source minors (:766; M9 covers majors only); renewing RENOVATE_TOKEN and DHI_TOKEN (:1417-1419) (re-check). user-manual.md:749-752 itself calls a step with no row "a row missing". Register row M6's review-by date, 2026-11-21 (:478), has passed (see F92).
- **Who or what is affected:** The owner and a fork reading the register as complete.
- **Severity:** medium (re-check); the r9 reader gave low.
- **Sources:** r9.5; re-check: confirmed.

#### F36. The trust-boundary table leaves out feeds, scanner databases and tools

- **Kind:** CODE (the mechanism is a document)
- **Criterion or document:** Req 9.15 (docs/user-manual.md:1621-1636, r9; :1611-1636, re-check of r9.6)
- **What the sentence says:** A row for every component the catalogue depends on.
- **What the code does:** No row for: the CISA KEV feed (rescan.yml:410-428 and build.yml:889-893, r9; rescan.yml:7-10, re-check); the FIRST EPSS API (rescan.yml:612, r9; :7-10, re-check); the Trivy DB ghcr.io/aquasecurity/trivy-db (rescan.yml:54, r9; :53, re-check) and Grype's database (both); third-party Actions (docker/login-action at rescan.yml:107 and upload-pages-artifact at :898, r9; docker/build-push-action, login-action, setup-buildx-action, setup-qemu-action and renovatebot/github-action, re-check); lychee and vexctl (install-tool.sh and rescan.yml:128, r9; install-tool.sh:179, :206, re-check); yamllint, yamale and PyYAML (.github/requirements-ci.txt, both).
- **Who or what is affected:** A consumer judging trust from the table. The two feeds and the scanner database decide what is "known" and how exceptions are tiered.
- **Severity:** medium.
- **Sources:** r9.6; re-check: confirmed.

#### F37. SECURITY.md claims SLSA Build L1 while the verification policy demands no provenance

- **Kind:** CODE (the mechanism is a document)
- **Criterion or document:** Req 9.19 (SECURITY.md:103-153)
- **What the sentence says:** Claim no level above the one the verification policy demands, and state how to verify it.
- **What the code does:** SECURITY.md:107-110 claims L1 on BuildKit provenance (build.yml:451). The policy (policies/verify-catalogue-images.yaml:36-45) demands only signature, SPDX and OpenVEX under `release.provenance: report` (catalogue-policy.yaml:55); SECURITY.md:152 and README.md:102 say no policy verifies BuildKit provenance. "How to verify it" (SECURITY.md:137-142) covers only the L2-grade statement. Decision 15 (design.md:1018-1022) reads L1 as producer-side existence; the r9 reader calls that defensible, but the sentence is not met.
- **Who or what is affected:** A consumer reading the trust statement.
- **Severity:** medium (re-check); the r9 reader gave low.
- **Sources:** r9.8; re-check: confirmed.

#### F38. Many lane steps name no design decision, and nothing ties a lane change to its diagram

- **Kind:** CODE (the mechanism is a document)
- **Criterion or document:** Req 9.21 (docs/lanes.md)
- **What the sentence says:** Every step names the criterion and the design decision it rests on; the diagram changes in the PR that changes the lane.
- **What the code does:** r9 reader: 52 of 147 step-table rows name no decision (e.g. lanes.md:70, :255, :964), 2 name no criterion (:118, :959). Re-check: 205 of 291 labelled graph nodes carry no Decision or ADR. No validate step or script reads lanes.md, and the PR template has no item for it; design.md:1202-1203 accepts review as the control. The ledger (live-evidence.md:238) softens the sentence to "where it rests on one".
- **Who or what is affected:** The owner's view.
- **Severity:** medium (re-check); the r9 reader gave low.
- **Sources:** r9.9; re-check: confirmed.

### Low

#### F39. Later validate lints do not run when an earlier step fails

- **Kind:** CODE
- **Criterion or document:** Req 1.6, 1.11, 1.12, 1.16, 1.18, 5.8, 5.10
- **What the sentence says:** A violation fails validation naming the reference, class, repository, bump, group, definition or entry.
- **What the code does:** The conventions job (validate.yml:12-342) is one sequential job with no `if:` on any step. lint-pins.sh is step 5 (:42-43), after yamllint (:22-25), chart pins and compat (:29-33) and the revocation schema (:37-38); lint-active-set.sh is :122-134; lint-probes.sh is :147-148. Any earlier red step leaves these violations unnamed; the job is still red, so the required check (main_sec.json:45) blocks the merge. Seen live: triage/LOG.md:3844, PR #354. From 2026-11-25 the valkey date makes step 3 fail on every PR (see "Time-bound items").
- **Who or what is affected:** The owner: a red run whose named cause is one step removed. No release or consumer is affected.
- **Severity:** low (re-check); the r1 reader gave medium.
- **Smallest fix (a reader's):** The rescan already enforces `always()` on its steps (lint-rescan-steps.sh) (r1.4).
- **Sources:** r1.4, r5.3; re-check: confirmed (both).

#### F40. The lint does not check which build frontend a definition names

- **Kind:** CODE
- **Criterion or document:** Req 1.7
- **What the sentence says:** Definitions are built with the DHI frontend and backend the 9.15 table names (user-manual.md:1623).
- **What the code does:** lint-pins.sh:78-92 checks only that a digest-pinned `# syntax=` line exists on line 1. Probe (re-check): `# syntax=docker/dockerfile:1@sha256:<64hex>` passes. Renovate tracks only `dhi.io/...` (renovate.json5:85). A foreign frontend that cannot parse the definition fails the build by accident; a re-hosted one under another name would pass.
- **Who or what is affected:** Held by review only.
- **Severity:** low.
- **Sources:** r1.5; re-check: confirmed.

#### F41. CONVENTIONS.md still says the drill definition declares a none proof

- **Kind:** DOC
- **Criterion or document:** docs/CONVENTIONS.md:222-226 (Req 5.9 context)
- **What the sentence says:** "The reference instance declares one: the drill definition of task 16.2".
- **What the code does:** catalogue-policy.yaml:111 is `proofs: {}`; its comment (:107-110) says the drill definition was retired (task 16.16), and image/drill-app/ no longer exists. CONVENTIONS.md:202 agrees with the policy file.
- **Who or what is affected:** The owner's view of the active-set section.
- **Severity:** low.
- **Sources:** r1.8; re-check: confirmed.

#### F42. The builder contract says downstream never reads a definition; several planes do

- **Kind:** DOC
- **Criterion or document:** Req 1.17; docs/user-manual.md:1601-1609
- **What the sentence says:** "Downstream reads outputs only ... None of them reads a definition to learn about an image."
- **What the code does:** compile-vex.sh:79-81 (VEX product name from `image:`); enumerate-catalogue.sh:10-11, :25-26, :57-64 (repositories and supported tags); scan-image.sh:53 (exception file keyed by definition); rescan.yml:814-824 (the page's definition list); check-inactive-digests.sh:78-79; check-authenticity.sh:90+.
- **Who or what is affected:** A fork swapping the backend: the contract's input must keep `image:` and `tags:` readable to those planes, and the contract does not say so.
- **Severity:** low.
- **Sources:** r1.9; re-check: confirmed.

#### F43. The manual's list of validate checks is incomplete and out of order

- **Kind:** DOC
- **Criterion or document:** docs/user-manual.md:321-337 (battery), :1727 (Req 1 map), :1375-1379 (local block)
- **What the sentence says:** The conventions job "runs, in order" seven or eight items; Req 1 maps to lint-pins.sh, the frontend compile and verify-arch-pins.sh.
- **What the code does:** validate.yml also runs chart pins and compat (:29), the revocation schema (:37), lint-accounts (:63-64), render-verification --check (:89), lint-workflow-policy (:92), release-policy check (:98), the step-condition lints (:106, :113), lint-active-set (:122-134), render-tracking --check (:139-140), lint-probes (:147), the VEX LOG citations (:197), the live-evidence lint (:202) and the provenance suite (:296-303). lint-vex-product runs at :192, after the 7.8 to 7.10 steps. The scripts table (:1666-1678) does list them.
- **Who or what is affected:** A reader reproducing validate locally.
- **Severity:** low.
- **Sources:** r1.10, r7.15; re-check: confirmed (both).

#### F44. Only the version part of a tag is checked

- **Kind:** CODE
- **Criterion or document:** Req 2.3
- **What the sentence says:** Tags derive from the upstream version, base OS and variant.
- **What the code does:** lint-pins.sh:241-252 passes a tag equal to the major, minor or full version, or starting with one of them and "-". The OS segment is a literal `alpine3.23` in refresh-definition.sh:119-120, compared with nothing; the variant is compared with nothing; count and order are unchecked, while build.yml:380-382 takes the last tag as the full release tag. Probe (re-check): `13-debian12-totally-wrong` passes.
- **Who or what is affected:** A base bump or a reordered list would publish tags whose OS segment lies, or point the comparator at an alias tag.
- **Severity:** low.
- **Sources:** r2.5; re-check: confirmed.

#### F45. The package-set difference is not reported for two of the publish reasons

- **Kind:** CODE
- **Criterion or document:** Req 2.16
- **What the sentence says:** When a rebuild publishes, report its package-set difference.
- **What the code does:** package-set-diff.sh:152-155 (`platform-set-differs`) and :174-177 (`attestation-unreadable`) call `different()` and exit (:128-133) before any diff; the diff is printed only for `package-set-differs` (:185-187). With several platforms the loop stops at the first unreadable one. The digest pushed comes from a second build (build.yml:414-451, :419), not from the compared archive.
- **Who or what is affected:** The owner reading a publish summary.
- **Severity:** low.
- **Smallest fix (a reader's):** A platform-set mismatch could still diff the shared platforms (re-check of r2.6).
- **Sources:** r2.6; re-check: confirmed.

#### F46. The tag step moves every tag before it checks any

- **Kind:** BOTH
- **Criterion or document:** Req 2.9; docs/user-manual.md:502-504
- **What the sentence says:** Tags move last, onto the signed digest. The manual says "any mismatch is a red run with the tags untouched".
- **What the code does:** build.yml:1229-1230 writes every tag in one `imagetools create`; :1231-1238 reads them back and exits at the first mismatch, after the tags have moved. docs/lanes.md:575-579 and :602 draw it correctly. A single-source create copies the index unchanged, so the case is not expected.
- **Who or what is affected:** In the mismatch case consumers would pull an unsigned digest under the tag until the next release.
- **Severity:** low.
- **Sources:** r2.7; re-check: confirmed.

#### F47. The rescan's switch step cannot fail on a malformed switch

- **Kind:** BOTH
- **Criterion or document:** Req 2.29, 2.30, 6.61 (WHERE clause), 7.7; rescan.yml:96-98 (comment)
- **What the sentence says:** The comment says "a malformed switch fails here by name".
- **What the code does:** rescan.yml:102-104 runs `echo "page=$(scripts/release-policy.sh . page)"` under `set -euo pipefail`; the substitution's exit is lost to echo. Probes (r2, r6b, both re-checks): the step exits 0 and writes `page=`. Then the page job is skipped (:1043) with the run green; an empty `provenance` runs `check=report` (:711-716) and fails the status step (main.go:202-203), not the switches step. validate.yml:99 refuses a malformed value on every PR, so it is reached only by a change that skips validate (the admin bypass). docs/lanes.md:755 records it.
- **Who or what is affected:** The owner: the page silently off.
- **Severity:** low.
- **Sources:** r2.9, r6b.11; re-check: confirmed (both).

#### F48. The release-step lint does not see continue-on-error

- **Kind:** CODE
- **Criterion or document:** Req 2.26
- **What the sentence says:** No release step may escape a failed scan.
- **What the code does:** lint-release-steps.sh:45-55 reads only each later step's `if:`. Probes (r2 and re-check): `continue-on-error: true` on relscan passes. The release would still stop at the next step (`trivy convert` of a missing report, build.yml:1048), so the property holds by data dependency, not by the lint.
- **Who or what is affected:** Nobody today; the lint is weaker than its rule.
- **Severity:** low.
- **Sources:** r2.10; re-check: confirmed.

#### F49. The manual's cron table names one publish reason of several

- **Kind:** DOC
- **Criterion or document:** docs/user-manual.md:619 (r2), :309 (re-check of r2.11)
- **What the sentence says:** "Fresh digests for every definition whose package set changed" / "publishes on change".
- **What the code does:** The code publishes for `package-set-differs`, `no-published-digest`, `attestation-unreadable`, `platform-set-differs` (package-set-diff.sh:38-43, r2; :137-139 for no-published-digest, re-check) and the `always` policy (build.yml:406-411, both). The manual states them correctly at user-manual.md:517-518 (r2) and from :509 (re-check).
- **Who or what is affected:** A reader of the cron table.
- **Severity:** low.
- **Sources:** r2.11; re-check: confirmed.

#### F50. Decision 6 says attestations use --recursive, and cites retired criteria

- **Kind:** DOC
- **Criterion or document:** design.md:143, :161, :163-167, :180
- **What the sentence says:** "sign the index and every platform manifest and attest to each (`--recursive`; ...)".
- **What the code does:** `--recursive` is on `cosign sign` only (build.yml:1101); attestations are explicit per reference (:1083-1125; docs/lanes.md:600 is correct). Retired Req 6.36 is cited at design.md:143 and :161; Req 2.20 at :180 is today the identity-counting criterion.
- **Who or what is affected:** A reader of the design.
- **Severity:** low.
- **Sources:** r2.12; re-check: confirmed.

#### F51. Decision 6 still says workflows read the switches with yq

- **Kind:** DOC
- **Criterion or document:** design.md:256
- **What the sentence says:** "Workflows read the switches at run time with `yq`".
- **What the code does:** The code reads them through release-policy.sh (build.yml:226-231, :252; rescan.yml:103-104); yq remains for registry, image, platforms and tags. The D3 correction in the same decision (design.md:317-322) says so.
- **Who or what is affected:** A reader of the design.
- **Severity:** low.
- **Sources:** r2.13; re-check: confirmed.

#### F52. The manual's artifact list presents BuildKit provenance as the verifiable link and omits the SLSA statement

- **Kind:** DOC
- **Criterion or document:** Req 2.25; docs/user-manual.md:206-209 (also :34)
- **What the sentence says:** "Provenance (BuildKit, mode=max) ... This is what connects the SBOM's claims to verifiable materials".
- **What the code does:** The same page (:156-158, :183), README.md:102-103 and SECURITY.md:151-153 say no policy verifies it. The SLSA statement (build.yml:1169-1187) is not in the list; the trust-chain section (:1508-1545) does describe it.
- **Who or what is affected:** A consumer choosing what to verify.
- **Severity:** low.
- **Sources:** r2.14; re-check: confirmed.

#### F53. Decision 10 names the manual's recipe as the one run daily; the README's copy runs

- **Kind:** DOC
- **Criterion or document:** design.md:642-643
- **What the sentence says:** "the manual's consumer recipe runs verbatim daily".
- **What the code does:** rescan.yml:552-553 runs `consumer-smoke.sh --readme README.md`. The two copies are rendered from one source and held equal by the drift check (render-verification.sh:14-16, :50; validate.yml:89-90); byte-identical today. "Verbatim" is F90 and F11.
- **Who or what is affected:** Nobody in behaviour; wording only.
- **Severity:** low.
- **Sources:** r2.15, r9.13; re-check: confirmed (both).

#### F54. The documents say every built-in Renovate manager is disabled; two are on

- **Kind:** DOC
- **Criterion or document:** design.md:112-113 (Decision 2), docs/CONVENTIONS.md:269-270, docs/user-manual.md:754 (also :73, :312)
- **What the sentence says:** "custom regex managers only (every built-in manager disabled ...)".
- **What the code does:** renovate.json5:12 is `enabledManagers: ["custom.regex", "github-actions", "gomod"]`, and its comment (:6-11) says two built-ins are on. The same documents say so elsewhere: design.md:130, CONVENTIONS.md:92-94, user-manual.md:1692-1694.
- **Who or what is affected:** A reader of the design and conventions.
- **Severity:** low.
- **Sources:** r3.4, r7.11; re-check: confirmed (both).

#### F55. lanes.md draws a refused refresh as a dead end; Renovate still opens the pull request

- **Kind:** DOC
- **Criterion or document:** docs/lanes.md:80, :98-99
- **What the sentence says:** "a failed check writes nothing"; "Refused by name, nothing written".
- **What the code does:** Narrowed by the re-check. Holds for the script: refresh-definition.sh refuses at :74-93 before its first write (:106). Misleading for the lane: Renovate's own version edit is already on the branch, and Renovate commits it and opens the PR once the release is over 2 h old (branch/index.js:458-470, :755-790). CONVENTIONS.md:296-299 admits this. lint-pins.sh coherence then fails the PR, so nothing reaches a consumer.
- **Who or what is affected:** A reader of the lane.
- **Severity:** low.
- **Sources:** r3.8 (narrowed); re-check: narrowed.

#### F56. The README half of the compat decision is unchecked

- **Kind:** CODE
- **Criterion or document:** Req 4.5
- **What the sentence says:** The decision is recorded as chart metadata and documented in the chart's README.
- **What the code does:** lint-compat.sh:43-109 reads chart.yaml and the definitions only; the schema (chart.schema.yaml:35) takes any string for `issue`. Probes: README deleted or emptied, `issue: "n/a"`, lint-compat and yamale pass. The decision is in the README today (chart/valkey/README.md:71-127).
- **Who or what is affected:** The owner: a second compat variant could ship with no written reasoning.
- **Severity:** low.
- **Sources:** r4.2; re-check: confirmed.

#### F57. cert-manager's CRD install flag is a deviation the README does not list

- **Kind:** BOTH
- **Criterion or document:** Req 4.7; chart/cert-manager/README.md:5-7, :11-16, :25-31; chart/grafana/README.md:5, chart/valkey/README.md:5, docs/CONVENTIONS.md:353; docs/user-manual.md:223-228
- **What the sentence says:** Every deviation from upstream defaults is documented with its rationale in the README. "All deltas live in config/values-hardened.yaml".
- **What the code does:** test/e2e/components_test.go:30-31 installs cert-manager with `--set crds.enabled=true` (passed as Extra, install_test.go:39). The overlay does not set it, the deviations table does not list it, and the README's and the manual's recipes leave it out.
- **Who or what is affected:** A consumer following the README installs without the CRDs, which the e2e never tests.
- **Severity:** low (re-check); the r4 reader gave medium for both halves.
- **Sources:** r4.4, r4.7; re-check: confirmed (both).

#### F58. Two cases skip the daily compat-lapse report

- **Kind:** CODE
- **Criterion or document:** Req 4.9
- **What the sentence says:** The daily run reports each lapsed compat review-by date.
- **What the code does:** (1) check-authenticity.sh:53 exits before the compat loop (:150-168) when the active-set read refuses; probe (re-check): rc=2, an empty jsonl, and the summary counts "0 lapsed" (rescan.yml:464, :956). (2) A chart.yaml that does not parse gives an empty review_by and `continue` (:154-160) with no message. validate refuses both inputs on any PR, so they reach main only by a direct push.
- **Who or what is affected:** The owner's daily view for that day.
- **Severity:** low.
- **Sources:** r4.6; re-check: confirmed.

#### F59. CONVENTIONS.md says there is no kyverno binary in the devcontainer

- **Kind:** DOC
- **Criterion or document:** docs/CONVENTIONS.md:396-399
- **What the sentence says:** "no kyverno binary in the devcontainer ... recorded in the repository's CLAUDE.md".
- **What the code does:** /usr/local/bin/kyverno exists (1.18.2, not the pinned 1.19.2, install-tool.sh:62), installed by the devcontainer Dockerfile (:141-152); the repository's CLAUDE.md:31 says kyverno installs fine from GitHub releases.
- **Who or what is affected:** A contributor.
- **Severity:** low.
- **Sources:** r4.11; re-check: confirmed.

#### F60. The hardened-app README says the image is private

- **Kind:** DOC
- **Criterion or document:** chart/hardened-app/README.md:22
- **What the sentence says:** "deploy (needs the private image)".
- **What the code does:** The packages have been public since 2026-08-13 (e2e.yml:161-165; requirements.md:14). Live visibility is owner-side (check-visibility.sh).
- **Who or what is affected:** A consumer.
- **Severity:** low.
- **Sources:** r4.12; re-check: confirmed.

#### F61. The none-proof report is not printed on every validation run

- **Kind:** BOTH
- **Criterion or document:** Req 5.9; design.md:980, :1000, :1277, :1706; docs/user-manual.md:451, :1208-1209, :1668; docs/CONVENTIONS.md:213-214; validate.yml:142-146 and lint-probes.sh:25-26 (comments)
- **What the sentence says:** Each kind-none declaration is reported by name with its reason in every validation run.
- **What the code does:** The line is lint-probes.sh:99, step 17 of the conventions job (validate.yml:147-148). It is not printed when an earlier step fails (F39), or when the active set or proofs map is refused (lint-probes.sh:48-57). The r5 reader also probed a multi-line reason, printed only to its first line (definition-lib.sh:220-221, lint-probes.sh:61-64). Vacuous today: `proofs: {}` (catalogue-policy.yaml:111), and every run that skips the line is already red.
- **Who or what is affected:** The owner's view of declared gaps, at the next onboarding.
- **Severity:** low (re-check); the r5 reader gave medium.
- **Sources:** r5.2, r5.7; re-check: confirmed (both).

#### F62. A pull request changing only test/go.mod runs no e2e leg, though the documents say a harness change smoke-tests

- **Kind:** DOC
- **Criterion or document:** docs/user-manual.md:421-423, docs/lanes.md:427, e2e.yml:87 (comment)
- **What the sentence says:** "a change to the harness itself smoke-tests on hardened-app".
- **What the code does:** e2e.yml:89 matches `^\.github/workflows/e2e\.yml$|^test/(e2e|checks|install|harness)/`, which test/go.mod and test/go.sum do not match; such a PR gets names=[] and the gate passes on "skipped" (e2e.yml:94-96, :102, :291-292). Only compile, vet and unit tests run (validate.yml:360-397). Req 5.2 binds image and chart changes only.
- **Who or what is affected:** The suite's own dependencies (e2e-framework, Ginkgo, client-go) can change on main without a live run; this also leaves 4.3's live check unrun on such a bump (r4 known input).
- **Severity:** low.
- **Sources:** r5.5; re-check: confirmed.

#### F63. design.md says e2e-framework provisions kind; in CI the workflow does

- **Kind:** DOC
- **Criterion or document:** design.md:1300
- **What the sentence says:** "e2e-framework provisions kind".
- **What the code does:** In CI e2e.yml:147-151 creates the cluster with the kind CLI and the suite attaches through E2E_KUBECONFIG (e2e_suite_test.go:70-74); e2e-framework provisions only on the local path (:75-89).
- **Who or what is affected:** A reader of the design.
- **Severity:** low.
- **Sources:** r5.6; re-check: confirmed.

#### F64. Nothing links a fix decision to a pull request

- **Kind:** CODE
- **Criterion or document:** Req 6.5
- **What the sentence says:** A "fix" decision is carried out through a version-bump or rebuild PR.
- **What the code does:** No artifact records a fix decision; the issue body has only an unchecked box (report.go:292); closure is graded on attested SBOMs (rescan.yml:231-262); the lane is Renovate configuration only (renovate.json5:342-354); only the gate's error text names it (build.yml:914).
- **Who or what is affected:** The owner's audit trail. A process criterion.
- **Severity:** low.
- **Sources:** r6a.2; re-check: confirmed.

#### F65. Only files named .trivyignore* count as Trivy ignore files, and temp/ and node_modules/ are skipped at any depth

- **Kind:** BOTH
- **Criterion or document:** Req 6.12; triage/README.md:109-111, docs/CONVENTIONS.md:427-428
- **What the sentence says:** IF a Trivy ignore file exists outside triage/accepted-risk/ THEN validation fails (requirements.md:172). triage/README.md says "a file by that name anywhere in the repo fails the lint"; CONVENTIONS.md says the lint "rejects any Trivy ignore file living anywhere else".
- **What the code does:** The only check is lint-accepted-risk.sh:40-42 (run by validate.yml:79-80): a `find` that matches the name `.trivyignore*` and prunes every directory named `temp` or `node_modules` at any depth. Probes (r6a and the re-check, on copies): `image/grafana/temp/.trivyignore`, `docs/x/node_modules/.trivyignore.yaml`, a Trivy-YAML-shaped `docs/suppress.yaml` and a root `trivy.yaml` naming `ignorefile: docs/ignore.txt` all pass, exit 0; `image/.trivyignore` (r6a) and `image/.trivyignore.yaml` (re-check) fail, exit 1. .gitignore ignores temp/ and node_modules/, so such a file is committed only with `git add -f`. The gap was raised before in docs/archive/reviews/2026-08-04-req6-consistency.md:286-289 (finding 3.7) and never closed.
- **Who or what is affected:** Latent: no workflow or script hands Trivy an ignore file from outside the lane today (scan-image.sh:54 passes only the lane file as `--ignorefile`).
- **Severity:** low.
- **Sources:** r6a.4; re-check: confirmed (recheck-r6a-4.md, done after the others; its re-checker saw the finding's first line, not only the title).

#### F66. The LOG citation is checked for existence, not for its evidence

- **Kind:** CODE
- **Criterion or document:** Req 6.15
- **What the sentence says:** A reachability claim cites a symbol- or package-level govulncheck result or an entrypoint argument.
- **What the code does:** lint-log-anchors.sh:103-129 checks only that some `LOG.md#slug` or `LOG.md <date>` citation resolves (:63-71). Probe (re-check): a statement citing an unrelated heading passes. Six statements carry `vulnerable_code_not_in_execute_path` (triage/vex/CVE-2026-100349, 100351, 100352, 100353, 42151, 84445).
- **Who or what is affected:** A reviewer relying on the citation.
- **Severity:** low.
- **Sources:** r6a.7; re-check: confirmed.

#### F67. "Never cite a module-level result" is not enforced

- **Kind:** CODE
- **Criterion or document:** Req 6.16
- **What the sentence says:** A module-level result is treated as unmeasured and never cited.
- **What the code does:** The rendering is right (govulncheck-report.sh:19-23, :53, :60-62, :73-74). Nothing reads a statement against govulncheck levels. Probe (re-check): a statement whose own text says "module level only" with that justification passes both lints.
- **Who or what is affected:** A reviewer.
- **Severity:** low.
- **Sources:** r6a.8; re-check: confirmed.

#### F68. A dead exception is not reported when a live sibling shares its id and statement

- **Kind:** CODE
- **Criterion or document:** Req 6.26
- **What the sentence says:** Report every exception that suppressed nothing.
- **What the code does:** accepted-risk-report.sh:75-91 treats an entry as live if any suppression carries its (id, statement) pair; paths are not compared. Probes (r6a and re-check): two CVE-1 entries with one statement, one path gone, nothing reported. Latent: grafana.yaml has no duplicate pair today, and lint 6.25 does not prevent one.
- **Who or what is affected:** The owner's view of stale exceptions.
- **Severity:** low.
- **Sources:** r6a.10; re-check: confirmed.

#### F69. "Attested" on the page means a document was compiled, though a failed attest withholds the page, so it never shows "attested" for one

- **Kind:** CODE
- **Criterion or document:** Req 6.61 (6.47 "as attested"); docs/user-manual.md:851-852
- **What the sentence says:** The page shows each digest's attested state; the manual says "Only the attested document is read".
- **What the code does:** Narrowed by the re-check. True in the code: page.html.tmpl:55 prints "attested" for d.Document (status.go:403), loaded from the compiled out/*.openvex.json (inputs.go:69-83), written before and regardless of the attest. Does not hold in effect for a failed attest: reattest.sh exits 1 (:241, :276), which withholds status and page (rescan.yml:744, :792, :1043). The residual mismatch is the other way: a skipped digest (failed scan) is drawn "not attested" although yesterday's attestation stands.
- **Who or what is affected:** A reader of the page.
- **Severity:** low.
- **Sources:** r6b.9 (narrowed); re-check: narrowed.

#### F70. The "scanned without its VEX" fence can never trigger

- **Kind:** BOTH
- **Criterion or document:** Req 6.3 (lifecycle and status fences); rescan.yml:189-190 (comment), triage/README.md:193, docs/user-manual.md:564, :825, :1748
- **What the sentence says:** "every path writes a report"; a digest scanned without its VEX blocks every close and shows as "unresolved, no VEX applied".
- **What the code does:** VEXUnresolved is set only when a compile report exists with an empty digest (inputs.go:97-106, findings.go:50-53). The scan step always passes the enumeration's digest (rescan.yml:161, :191-192), and a failed compile writes no report (compile-vex.sh:474-483; probe: none written). `|| true` (rescan.yml:192) then lets the scan run without `--vex`, and nothing marks the digest. The reporter is not fenced either (rescan.yml:645-648), so findings a not_affected statement covers can be filed as new issues (r6a.1 case 4). The guard at :804 and the summary row at :976-977 are unreachable.
- **Who or what is affected:** The owner; low because the validate lints make a failing compile unlikely.
- **Severity:** low (r6b.12; r6a.1 as a whole is medium).
- **Sources:** r6b.12, r6a.1 (case 4); re-check: confirmed (both).

#### F71. One failed re-attestation withholds the whole day's status, issue and page

- **Kind:** CODE
- **Criterion or document:** Req 6.46, 6.47, 6.61
- **What the sentence says:** The status, the status issue and the page are produced every day.
- **What the code does:** reattest.sh:276 exits 1 when any digest failed; status_previous runs only on `steps.reattest.outcome == success` (rescan.yml:744), and status (:792), status_publish (:868), the uploads (:886, :897) and the page job (:1043) chain from it. The choice is stated in design.md:305-306 and named in the run.
- **Who or what is affected:** The owner and page readers, for all definitions that day.
- **Severity:** low.
- **Sources:** r6b.13; re-check: confirmed.

#### F72. The status issue body grows without limit

- **Kind:** CODE
- **Criterion or document:** Req 6.47
- **What the sentence says:** One status issue, updated daily.
- **What the code does:** Fixed findings are carried forward for ever (status.go:489-505), and the body embeds every fixed row (:744-753) plus the full JSON (:756-759). Past GitHub's 65,536-character body limit, `gh issue edit` (rescan.yml:875) fails every day, by name, and the persisted record stops advancing.
- **Who or what is affected:** Latent: the owner, once the body is large.
- **Severity:** low (latent).
- **Sources:** r6b.14; re-check: confirmed.

#### F73. The triage READMEs say the directories start empty

- **Kind:** DOC
- **Criterion or document:** triage/README.md:15-16, triage/accepted-risk/README.md:7-8
- **What the sentence says:** "It starts empty"; "Starts empty, and that is the correct default".
- **What the code does:** triage/vex/ holds 12 documents and triage/accepted-risk/grafana.yaml 16 entries; a fork inherits them.
- **Who or what is affected:** A fork.
- **Severity:** low.
- **Sources:** r6a.11; re-check: confirmed.

#### F74. triage/README.md says the Trivy gate consumes triage/vex/

- **Kind:** DOC
- **Criterion or document:** triage/README.md:15, :119-121, :172
- **What the sentence says:** "The directory is consumed by the Trivy scan gate"; "consuming triage/vex/ via --vex".
- **What the code does:** Narrowed by the re-check. True: the gate step reads triage/vex/ through compile-vex.sh (build.yml:555). False: Trivy never reads the directory (build.yml:531; Req 6.28; scan-image.sh:50). Omitted: the release arm (build.yml:988, :1076) and the rescan (rescan.yml:191-192) consume it too. The README says it right at :298. The re-check's conclusion: the sentence is imprecise, not wrong about who reads the files.
- **Who or what is affected:** A reader of the README.
- **Severity:** low.
- **Sources:** r6a.12 (narrowed); re-check: narrowed.

#### F75. triage/README.md says scan and feed failures soft-fail; a KEV failure fails the run

- **Kind:** DOC
- **Criterion or document:** triage/README.md:214-216
- **What the sentence says:** "Scan and feed failures soft-fail (skip + warn)".
- **What the code does:** Scans (rescan.yml:200-206) and EPSS (:612-613) soft-fail. A KEV failure fails the run by name and withholds the issue set and status (rescan.yml:422-428, :607, :800-801; Req 6.60). The enumeration hard-fails too (:131-140). The README says the KEV case right at :67-70.
- **Who or what is affected:** A reader of the README.
- **Severity:** low.
- **Sources:** r6a.14, r6b.15; re-check: confirmed (both).

#### F76. "One issue per CVE" is one issue per scanner id

- **Kind:** DOC
- **Criterion or document:** triage/README.md:195-197, docs/user-manual.md:799
- **What the sentence says:** "filed one issue per CVE".
- **What the code does:** The reporter aggregates by the scanner's id (report.go:131) and the dedup marker carries GHSA ids too (rescan.yml:625-629). Dedup reads only open issues, capped at `--limit 500` (:630); when the lifecycle withholds reopens (:327-331), a finding whose issue is closed gets a second issue (re-check). docs/lanes.md:864 is right.
- **Who or what is affected:** A reader of the README.
- **Severity:** low.
- **Sources:** r6a.15; re-check: confirmed.

#### F77. The documents say an expiry reddens only the affected pull request; it reddens every one

- **Kind:** DOC
- **Criterion or document:** triage/README.md:220-223, rescan.yml:562-566 (comment), docs/user-manual.md:1057-1058
- **What the sentence says:** The rescan raises expiry because reddening whichever PR runs that day would blame the wrong change; "the next affected PR goes red".
- **What the code does:** validate runs on every pull_request with no paths filter (validate.yml:3-4) and runs lint-accepted-risk.sh (:79-80), which exits 1 on any past expired_at (lint-accepted-risk.sh:180-188); the job is a required check (main_sec.json:45). Probe (re-check): rc=1. Seen live: validate run 40500526721 (docs/live-evidence.md:150); tasks.md:454.
- **Who or what is affected:** The owner's reading of a red validate. Louder than the sentence, not silent.
- **Severity:** low (re-check); the r6a reader gave medium.
- **Sources:** r6a.16; re-check: confirmed.

#### F78. "One implementation of expired" is at least four

- **Kind:** DOC
- **Criterion or document:** triage/README.md:218-220, docs/lanes.md:849, rescan.yml:568-569 (comment)
- **What the sentence says:** "one implementation of expired, the notice can never disagree with the gate".
- **What the code does:** Trivy's own pruning (the gate's rule, from midnight UTC of the expiry day), the lint (lint-accepted-risk.sh:180-186), compile-vex.sh `expired()` (:312-316) and check-exceptions.sh (:114). They disagreed in the live drill (triage/LOG.md:3473-3489; tasks.md:454; docs/live-evidence.md:176).
- **Who or what is affected:** The owner on the expiry day.
- **Severity:** low.
- **Sources:** r6a.17; re-check: confirmed.

#### F79. The manual's scan-gate steps omit the KEV exception-tier step

- **Kind:** DOC
- **Criterion or document:** docs/user-manual.md:342-399 (steps 1 to 8)
- **What the sentence says:** The steps of "build: the scan gate".
- **What the code does:** build.yml:877-894 runs "exception tiers against KEV (Req 6.50)" with the fail-closed KEV fetch (Req 6.59) before the gate; the manual names check-exceptions.sh only in the script table (:1650) and the rescan (:631). The list also writes the aperture as a fixed HIGH,CRITICAL (:380). docs/lanes.md:355, :383 draw it.
- **Who or what is affected:** A reader of the manual: that step can fail a PR.
- **Severity:** low.
- **Sources:** r6a.19, r6b.18; re-check: confirmed (both).

#### F80. design.md says a drill run publishes attestations only

- **Kind:** DOC
- **Criterion or document:** design.md:1744
- **What the sentence says:** "A drill run is red by name and publishes attestations only: the issue set, the status and the page wait for the next scheduled run".
- **What the code does:** With kev-synthetic the feed is fetched like the real one (rescan.yml:415-423), and enrich, report, file, status and page all run (:597-689, :790-882, :1040-1078). With kev-outage the issue set and status are withheld, but lifecycle closes and supply-chain issues still apply. docs/user-manual.md:626-632 is correct.
- **Who or what is affected:** A reader of the design.
- **Severity:** low.
- **Sources:** r6b.17; re-check: confirmed.

#### F81. The manual says a Pages dashboard does not exist yet

- **Kind:** DOC
- **Criterion or document:** docs/user-manual.md:859-860
- **What the sentence says:** "A Pages dashboard, if one is ever wanted, is presentation over that JSON".
- **What the code does:** The page exists and is deployed daily (rescan.yml:892-900, :1040-1078); the same manual describes it at :917-947.
- **Who or what is affected:** A reader of the manual.
- **Severity:** low (wording).
- **Sources:** r6b.19; re-check: confirmed.

#### F82. yamllint skips three paths

- **Kind:** CODE
- **Criterion or document:** Req 7.2
- **What the sentence says:** yamllint runs on changed YAML files.
- **What the code does:** .yamllint.yaml:17-20 ignores data/, temp/ and chart/*/templates/; validate.yml:22-25 runs `yamllint .`. The templates are Go templates covered by chart.yml's render. data/ holds no YAML today; temp/ does not exist.
- **Who or what is affected:** Nobody today; a future research input could merge malformed.
- **Severity:** low.
- **Sources:** r7.1; re-check: confirmed.

#### F83. A string permissions block crashes the workflow lint instead of naming the value

- **Kind:** BOTH
- **Criterion or document:** Req 7.4, 7.10; docs/lanes.md:176
- **What the sentence says:** The lint fails naming the value that differs. lanes.md:176 says "Each fails naming the value, file or entry that differs".
- **What the code does:** lint-workflow-policy.sh:101-110 calls `.get` on the permissions value. Probes (r7 and re-check): `permissions: write-all` or `read-all` gives `AttributeError: 'str' object has no attribute 'get'`, exit 1, no `::error` line. No workflow uses the string form today. The re-check of r7.18 also found a drill-substitutes point; it is under F86.
- **Who or what is affected:** The owner: a red run by traceback, not by name.
- **Severity:** low.
- **Sources:** r7.3, r7.18; re-check: confirmed (both; r7.18 for lanes.md:176 only. Its lanes.md:190 point is held out, see "Held out, unconfirmed").

#### F84. govulncheck's checksum is not recorded here

- **Kind:** CODE
- **Criterion or document:** Req 7.5
- **What the sentence says:** Every executable has a checksum recorded in this repository.
- **What the code does:** build.yml:778-792 runs `go install golang.org/x/vuln/cmd/govulncheck@v1.6.0`; the checksum control is the public Go sumdb, as the comment and CONVENTIONS.md:85-86 say. No go.sum for it is tracked.
- **Who or what is affected:** Little: the step is non-gating.
- **Severity:** low.
- **Sources:** r7.4; re-check: confirmed.

#### F85. A newer major of a pinned tool waits for dashboard approval

- **Kind:** CODE
- **Criterion or document:** Req 7.6 (against 3.4)
- **What the sentence says:** Every pinned executable's manager opens a PR for a newer version.
- **What the code does:** renovate.json5:336-341 puts every major behind Dependency Dashboard approval (Req 3.4), with no manager scope. cosign v3 is the live case (install-tool.sh:85-92). Deliberate per the workflow-pin manager's comment.
- **Who or what is affected:** The owner: the conflict is between 7.6 and 3.4 as written.
- **Severity:** low (deliberate).
- **Smallest fix (a reader's):** Either 7.6 is worded to except majors, or it stays read as "offered" (r7.8).
- **Sources:** r7.8; re-check: confirmed.

#### F86. Two dispatch inputs have no allowed values, and drill substitutes are not beside their input

- **Kind:** CODE
- **Criterion or document:** Req 7.7
- **What the sentence says:** Each dispatch input is declared with its allowed values, a drill's substitutes beside it.
- **What the code does:** build.yml `image` and e2e.yml `component` are `type: string` with no allowed values (catalogue-policy.yaml:254-256, :306-308; build.yml:36-40, e2e.yml:19-23); they are enforced at run time (build.yml:89-94). The substitutes sit in `triage.drills` (:197-199), cross-referenced by comment from the input at :269-272; only triage-policy.sh:87-99 binds them at dispatch. Cross-reference (re-check of r7.18, see F83): no validate step checks the declared drill substitutes, so an input option without a substitute is refused only at dispatch (triage-policy.sh:95-96).
- **Who or what is affected:** Wording: the values are declared and held.
- **Severity:** low.
- **Sources:** r7.9; re-check: confirmed.

#### F87. CONVENTIONS.md says the frontend compiles every definition on each PR build

- **Kind:** DOC
- **Criterion or document:** docs/CONVENTIONS.md:180-182
- **What the sentence says:** "it compiles every definition on each PR build".
- **What the code does:** build.yml:103-145 and :161-165 build only changed active definitions plus VEX, accepted-risk and canary additions; a PR touching no definition compiles none. lanes.md:257 and :334 are correct.
- **Who or what is affected:** A reader of the conventions.
- **Severity:** low.
- **Sources:** r7.14; re-check: confirmed.

#### F88. The manual's line for the workflow-policy lint omits dispatch inputs

- **Kind:** DOC
- **Criterion or document:** docs/user-manual.md:1672 (also the step name, validate.yml:92)
- **What the sentence says:** "Every workflow's cron and permissions equal the policy file's declarations".
- **What the code does:** lint-workflow-policy.sh:76-99 (header :15-20) also holds every workflow_dispatch input (Req 7.10 as amended 2026-10-23).
- **Who or what is affected:** A reader of the manual.
- **Severity:** low.
- **Sources:** r7.16; re-check: confirmed.

#### F89. A LOG citation can resolve to a heading inside a code fence

- **Kind:** CODE
- **Criterion or document:** Req 9.18
- **What the sentence says:** Every exception ref and statement citation resolves to a LOG heading.
- **What the code does:** lint-log-anchors.sh:47-55 takes every line matching `^#{1,6}\s` as a heading without tracking fences. Probes (r9 and re-check): a fenced `## fake ...` line cited from a statement or an exception passes, exit 0. GitHub renders no anchor for it. No fenced `#` line exists in today's LOG.md.
- **Who or what is affected:** Latent.
- **Severity:** low.
- **Sources:** r9.7; re-check: confirmed.

#### F90. The documents say the smoke test runs the recipe verbatim and reports every step's exit code

- **Kind:** DOC
- **Criterion or document:** docs/user-manual.md:313, :553-555, :880, :1688; CONVENTIONS.md:448; docs/live-evidence.md:230
- **What the sentence says:** "run verbatim ... every step's exit code".
- **What the code does:** consumer-smoke.sh:72-83 splits the recipe, :78 replaces REF, and :98 runs each step in its own shell with pipefail added (F11). :99 and :184 record only ok or failed; the code appears only in a failed step's `::error::` line (:102). lanes.md:1143 states the truth.
- **Who or what is affected:** A reader of the manual.
- **Severity:** low.
- **Sources:** r9.12; re-check: confirmed.

#### F91. SECURITY.md says no digest has been revoked and no advisory published

- **Kind:** DOC
- **Criterion or document:** SECURITY.md:191, :203
- **What the sentence says:** "No digest has been revoked." "None has been published as of 2026-09-07."
- **What the code does:** triage/revocations.yaml:23-31 records drill-app sha256:cf147012..., withdrawn 2026-11-05 (ledger :222, :224). GHSA-mxcv-w9jx-vj6j was published 2026-11-07 (revocations.yaml:29-30; the re-check read it from the anonymous API; ledger :221). The advisory line is narrowed by the re-check: dated, so true for its date and stale, not false; a reader would still take it as current.
- **Who or what is affected:** A consumer reading the trust statement.
- **Severity:** low (re-checks); the r9 reader gave medium and "low to medium".
- **Sources:** r9.14, r9.15 (narrowed); re-check: r9.14 confirmed, r9.15 narrowed.

#### F92. The terms memo's re-verification date has passed

- **Kind:** DOC
- **Criterion or document:** SECURITY.md:251-252; CONVENTIONS.md:478 (M6)
- **What the sentence says:** The memo's sources are "re-verified by 2026-11-21".
- **What the code does:** data/ holds only dhi-terms-2026-08-21.md; tasks/todo.md:219 still lists it open; SECURITY.md's last change (af56ccf, 2026-11-22) did not touch the date.
- **Who or what is affected:** A consumer relying on the terms statement.
- **Severity:** low.
- **Sources:** r9.16; re-check: confirmed.

#### F93. Decision 10 says the daily checks are all anonymous

- **Kind:** DOC
- **Criterion or document:** design.md:650-651 (r9), :653-654 (re-check of r9.17)
- **What the sentence says:** The daily invariants are "all anonymous reads or pulls, no new permissions".
- **What the code does:** The rescan job logs in to ghcr.io at the start (rescan.yml:106-111, r9; :113-118, re-check) and never logs out (re-check). The smoke test and the portability scans pull through that login; lanes.md:1116 says so (r9). The revoked-tags verdict rests on `crane ls` (enumerate-catalogue.sh:71) under the same login (re-check). Only check-governance.sh and check-visibility.sh read anonymously (r9; re-check: check-governance.sh:10-11, :71-75). Anonymous pullability is asserted separately by 2.21.
- **Who or what is affected:** A reader of the design.
- **Severity:** low.
- **Sources:** r9.17; re-check: confirmed.

#### F94. The revocation schema does not require the tombstone digest

- **Kind:** DOC
- **Criterion or document:** triage/revocations.yaml:11-13, docs/user-manual.md:1111-1121
- **What the sentence says:** A `tombstone` withdrawal records the tombstone manifest digest.
- **What the code does:** triage/revocations.schema.yaml:18-19 makes `tombstone` `required=False` whatever `withdrawal` is. Probes (r9 and re-check): an entry with `withdrawal: tombstone` and no `tombstone` passes yamale. Move B2 is not built, so no entry is exposed.
- **Who or what is affected:** Latent.
- **Severity:** low.
- **Sources:** r9.19; re-check: confirmed.

## The documentation track's phase-5 findings

The open item in `tasks/todo.md` listed what the documentation track found while drawing the lanes (2026-11-22). Each reader's "Known input" section ruled on the items in its scope. No item was confirmed by reading a run; each rests on the code, and where shown on a probe of a scratch copy.

| Phase-5 finding | Outcome | Finding |
|---|---|---|
| The refresh-definition.sh task keyed on github-tags (renovate.json5:416) also runs on GitHub Actions bumps and fails | CONFIRMED from the code and a reproduction on a copy (r3, r7; noted by r1). The live half (no Actions PR ever opened, ten Actions updates under "Other Branches" on the Dashboard) is not in the files and its run log could not be read; see "Method". | F12 |
| The published verify recipe has no pipefail, so a failed cosign | jq pipe exits 0 | CONFIRMED for the SBOM and OpenVEX steps (measured on a scratch shell); REFUTED for the provenance step (`jq -es any(...)` exits 1 on empty input) and the signature step (not piped) (r2, r7, r9). | F11 |
| The tag step writes every tag before it checks any (build.yml:1229-1238) | CONFIRMED (r2). | F46 |
| The manual's tag line says a mismatch leaves the tags untouched | CONFIRMED (r2). | F46 |
| rescan.yml:102-104 cannot fail on a malformed switch | CONFIRMED, probed (r2, r6b, r7). | F47 |
| A KEV file that downloads but does not parse still yields an issue set (Req 6.60) | CONFIRMED, probed (r6a, r6b). Wider than reported: a file that parses as `{}` passes everything (r6b). | F19; the `{}` case F26 |
| The build portability step and `consumers.gating` stay green on a failed consumer | CONFIRMED with a precision: a failed other consumer is "not measured" by design; a failed authoritative normalisation leaves no block and a green job; gating cannot fail any run (r9). | F33, F34 |
| No workflow step checks that main_sec.json requires the gates (Req 9.8) | CONFIRMED (r7, r9; r4 for the chart gate). | F32 |
| A pull request changing only the gate's scripts builds nothing | CONFIRMED for the build lane (r6a: build.yml:103-151 adds no leg), REFUTED for the chart gate (r4: chart.yml:8-11 has no paths filter). Not a breach of 6.1, whose WHEN is "a pull request builds an image". | no finding |
| A pull request changing only test/go.mod runs no e2e leg | CONFIRMED (r4, r5). | F62 |
| Req 2.5 ("no artifacts from that run") against `fail-fast: false` | CONFIRMED (r2). | F10 |
| Decision 2 and CONVENTIONS.md say every built-in Renovate manager is off (two are on) | CONFIRMED (r1, r3, r7), also user-manual.md:754. | F54 |
| Decision 6: `--recursive` attestations and retired Req citations | CONFIRMED (r2). | F50 |
| Decision 10 names the manual's recipe (the README's runs) | CONFIRMED (r2, r9). | F53 |
| The manual's scan-gate list lacks the KEV tiers step | CONFIRMED (r6a, r6b). | F79 |
| The manual's cron table names one publish reason | CONFIRMED (r2). | F49 |
| The manual's smoke summary claims exit codes | CONFIRMED (r9). | F90 |
| design.md's error table files an issue on a Trivy outage (none is filed) | CONFIRMED (r2, r6a, r6b); the run also stays green (r2). | F9 |
| triage/README.md: feed failures soft-fail (KEV fails the run) | CONFIRMED (r6a, r6b). | F75 |
| triage/README.md: one issue per CVE (GHSA ids too) | CONFIRMED (r6a). | F76 |
| triage/README.md: vex/ and accepted-risk/ start empty | CONFIRMED (r6a): 12 documents, 16 entries. | F73 |
| SECURITY.md says no digest has been revoked | CONFIRMED (r9). | F91 |
| SECURITY.md dates its advisory line 2026-09-07 | CONFIRMED by r9; NARROWED by the re-check: stale, not false. | F91 |

## Dropped

- **r4.10 (REFUTED):** the documents say "one named emptyDir per writable path, each commented" (docs/CONVENTIONS.md:369-370, docs/user-manual.md:1315-1316). The re-checker found the rule holds in every rendered chart: grafana's `tmp` and `log` emptyDirs are named in its overlay (chart/grafana/config/values-hardened.yaml:45-54) with the chart's own `storage` and `search` named in the comment at :40-44; valkey has one emptyDir, `valkey-data`, explained at chart/valkey/config/values-hardened.yaml:59-62; cert-manager and hardened-app need none. No lint enforces the rule, but the document does not claim one does.

## Held out, unconfirmed

One rule: a claim no re-checker verified does not enter the review, even inside a finding that was confirmed. These are listed here with the reason.

- **r7.18, the lanes.md:190 point:** the r7 reader wrote that lanes.md:190 names "the Kyverno policies and README block" while the drift check also covers the manual's block (render-verification.sh:50). Its re-checker saw only the title and wrote "The first reader's exact point was not visible"; it verified two other points instead (lanes.md:176, in F83; the drill substitutes, in F86). Reason: no re-checker verified it.
- **Register row M5's review-by date, 2026-10-22 (CONVENTIONS.md:477):** only the r9 reader named it, under r9.5. The re-check of r9.5 confirmed the missing register rows but did not mention M5. Reason: no re-checker verified it. (M6's date is verified through r9.16, F92.)
- **r9.6, the kind node image:** the r9 reader listed the kind node image among the components with no row in the trust-boundary table (user-manual.md:1621-1636). The re-check of r9.6 confirmed the other missing rows (F36) but did not list the kind node image. Reason: no re-checker verified it.

## Appendix: verdict per criterion

Copied from each reading's Criteria table. No re-check changed a verdict; where a re-check touched a row, the note is marked **Re-check:**. Finding ids in the tables (r1.1, ...) are the readers'; the index below maps them to F numbers.

### Requirement 1 (r1.md)

| # | Verdict | Mechanism (file:line) | Gap or note |
|---|---|---|---|
| 1.1 | HELD | image/{hardened-app,cert-manager-controller,cert-manager-webhook,cert-manager-cainjector,grafana,valkey,valkey-compat}/image.yaml; build context is the directory alone (build.yml:347-348, 423-424) | The seven directories are the reference set; each build reads only its own directory plus remote pinned sources. |
| 1.2 | PARTIAL | lint-pins.sh:39-76 (keys image:, base:, uses:), :78-92 (`# syntax=` line); every current reference is digest-pinned (image/*/image.yaml:1, uses: and GOLANG_REFERENCE lines) | State holds today. The lint reads only image:/base:/uses: keys, so GOLANG_REFERENCE (a builder reference present in hardened-app and the three cert-manager definitions) is unchecked, and a builds-level `uses:` in Docker Hub short form is skipped. r1.1. |
| 1.3 | PARTIAL | lint-pins.sh:117-123 (git+ count vs checksum-line count); verify-arch-pins.sh in build.yml:280-283; check-authenticity.sh:97-106, 119-122 daily, after merge | State holds today. At PR time nothing checks that a git+ url carries a ref, that `checksum:` is a commit hash, or that a repackage tarball has any per-arch pin. Caught only by the daily rescan, after a release. r1.2. |
| 1.4 | HELD | lint-accounts.sh:30-49 in validate.yml:63-64 | run-as must name a user with uid 65532, root refused. All seven comply. |
| 1.6 | PARTIAL | lint-pins.sh:61-69 names the reference in the error | Floating refs outside the read keys pass (probes: `uses: golang:1.25-alpine`, `uses: library/golang:1.25-alpine`, `GOLANG_REFERENCE: dhi.io/golang:1.27` all exit 0). Also skipped when an earlier validate step fails. r1.1, r1.4. |
| 1.7 | PARTIAL | lint-pins.sh:86-92 requires a digest-pinned `# syntax=` on line 1; build.yml:421-424 compiles through it; user-manual.md:1623 (9.15 table) names dhi.io/build and apko plus Wolfi | All seven use `dhi.io/build`. Nothing checks *which* frontend the line names, so a definition for any other BuildKit frontend passes lint and builds. Held by review only. r1.5. |
| 1.9 | HELD | docs/CONVENTIONS.md:115-128; code agrees: build.yml:1110-1112 attests SPDX and CycloneDX per platform manifest | Documentation criterion. The record matches the code. |
| 1.10 | HELD | `# authenticity:` marker in every definition (hardened-app:43, cert-manager-*:44, grafana:60, valkey:52, valkey-compat:72); definition-lib.sh:250-259; lint-pins.sh:131-154 maps class to archetype | Unknown class refused by name (lint-pins.sh:151-153). |
| 1.11 | PARTIAL | lint-pins.sh:145-150 (probed: `none` and a missing marker both exit 1, naming the file) | The check itself holds. It sits behind three earlier validate steps and is skipped when any of them fails. r1.4. |
| 1.12 | PARTIAL | lint-pins.sh:160-173 (probed: a block-style `/security` line exits 1 naming it) | A flow-style `repositories: [https://dhi.io/apk/alpine/v3.23/security, ...]` is never read and exits 0. Also the step-order skip. r1.3, r1.4. |
| 1.13 | HELD | catalogue-policy.yaml:87-94 `active_set:`; one reader definition-lib.sh:59-87 | |
| 1.14 | HELD | build.yml:86-165 (every branch filtered at :161-165); e2e.yml:58-92 through active_components (definition-lib.sh:156-170); renovate.json5:59-61 rendered by render-tracking.sh, drift-checked validate.yml:139-140; check-authenticity.sh:53,93 | Note: chart.yml:45-57 renders and gates every chart/*/ including a chart deploying only inactive definitions. That is a policy gate rather than a matrix, and CONVENTIONS.md:251-252 states it as intended. |
| 1.15 | HELD | Preventive: build.yml:89-95 (refused dispatch), :161-165 (single filter). Detective: check-inactive-digests.sh, rescan.yml:770-788 | Notes: (a) the detective check covers declared tags only and passes with a warning when no previous status exists (check-inactive-digests.sh:66-71); (b) the rescan's `cosign attest --replace` (reattest.sh:158, 233) pushes new .att manifests for inactive definitions' tag-referenced digests by design (CONVENTIONS.md:240-243). Terms (requirements.md:70) exclude .att tags from catalogue tags, so this reads as in-design. |
| 1.16 | PARTIAL | validate.yml:122-134 → lint-active-set.sh:115-133 (probed: inactive grafana with image/ and chart/ paths changed exits 1, both named) | The check holds. It runs as the 14th step of one sequential job, so it is skipped whenever any earlier step fails. r1.4. |
| 1.17 | HELD | docs/user-manual.md:1557-1609 "The builder contract per archetype": input one directory, outputs image by digest plus per-platform SBOMs carrying pull checksums, per-archetype table | Documentation criterion. One sentence of it overstates the seam. r1.9. |
| 1.18 | PARTIAL | lint-active-set.sh:67-90, groups keyed on published repository and git source repository, matching renovate.json5:305-323 groupings (probed: dropping valkey-compat names both groups) | Same step-order skip as 1.16. r1.4. |
| 1.19 | HELD | definition-lib.sh:82-83 refusal; surfaced by lint-active-set.sh:51-55, build.yml:86, e2e.yml:58 | The build and e2e jobs name the entry independently of validate's step order (live: triage/LOG.md:3844, PR #354). |

### Requirement 2 (r2.md)

| # | Verdict | Mechanism (file:line) | Gap or note |
|---|---|---|---|
| 2.1 | HELD | build.yml:153-154 (push: changed `image/*/image.yaml` in BEFORE...SHA), :157-165 (active filter), :248-266 (every declared platform, refused if not admitted), :434 (main builds `steps.meta.outputs.platforms`) | A definition is one file (`find image -type f`: one image.yaml per directory), so the image.yaml filter covers every definition change. Note: activating a definition (an active_set line only) is not a definition change and releases at the next schedule, not at the merge. |
| 2.2 | HELD | build.yml:239-242 (namespace refusal), :445 (push-by-digest to `steps.meta.outputs.image`), :451 (`provenance: mode=max` on main), :1038-1210 (sign and attest under 2.9) | |
| 2.3 | PARTIAL | tags read from the definition (build.yml:267-271); written by Renovate's refresh (refresh-definition.sh:112-120, refresh-grafana.sh:237-257); checked by lint-pins.sh:94-115 (OCI form) and :242-252 (each tag starts with the declared major, minor or full version) | Only the version segment is checked. The base-OS segment is a literal `alpine3.23` in the refresh scripts (refresh-definition.sh:119-120), checked against nothing (not the definition's os-release `version-id`); the variant segment (`-compat`) is checked against nothing; the count and order of tags are unchecked, although the comparator takes the third tag as the full release tag (build.yml:382). r2.5. |
| 2.4 | OWNER-SIDE | catalogue-policy.yaml `release.public: true` (the WHILE clause is not live); the disabled branch: check-visibility.sh:57-90 (no tag may answer an anonymous manifest request) | The source repository's visibility is the owner's setting, not probed (check-visibility.sh:63-64, register M15). The registry half has a daily check that would run under `public: false`. |
| 2.5 | PARTIAL | step failure skips later steps (default `success()`), the matrix leg goes red, GitHub reports the failing step; push happens inside the build step only (build.yml:414-451) | `strategy.fail-fast: false` (build.yml:183): when one definition's build fails, the other legs of the same run still push, sign, attest and tag. "No artifacts from that run" holds per leg, not per run. r2.4. |
| 2.7 | HELD | build.yml:440-445 (`push: false`, image exporter `push-by-digest=true`), :1218-1241 (tags only in the last step, after relscan :971-997) | Schedule and dispatch take the same steps; a dispatch off main pushes nothing (:445). |
| 2.8 | HELD | build.yml:941-964 (platform manifests per the Terms), :971-997 (compile-vex then scan-image.sh `--remote` per manifest digest); scan-image.sh:46-76 (same `--vex`, `--ignorefile`, `--severity` aperture as the PR gate, build.yml:555-562) | Expired exceptions are not applied: Trivy drops ignorefile entries past `expired_at`. |
| 2.9 | HELD | build.yml:1038-1054 (scan report per manifest), :1060-1081 (one compiled document), :1088-1125 (`cosign sign --recursive`; SPDX, CycloneDX, OpenVEX per manifest; OpenVEX on the index), :1146-1210 (provenance unless off, self-check), :1218-1241 (tags last); every step after relscan keeps the default `success()` | The tag step writes every tag in one call before reading any back (:1230 then :1231-1238), so a mismatch, if it ever happened, would leave tags already moved onto a digest nothing signed. Single-source `imagetools create` copies the index unchanged, so the case is not expected; the guard is after the fact. r2.7. |
| 2.10 | HELD | enumeration treats every tag-referenced digest as in scope (enumerate-catalogue.sh:80-104); verify-catalogue.sh holds signature, SPDX, OpenVEX daily | Note: nothing anywhere asserts that a tagged digest carries BuildKit provenance (no daily check, no policy rule; 2.25 says no policy verifies it), so the BuildKit leg of "published" is assumed from the release path only. Not a gap in the sentence, which defines rather than demands. |
| 2.11 | HELD | enumerate-catalogue.sh:70-104 (rows only from catalogue tags); reattest.sh and the rescan scan read only the enumeration (rescan.yml:160-209, :304) | An untagged digest is neither scanned nor re-attested. |
| 2.12 | PARTIAL | build.yml:1060-1076 (second compile with `COMPILE_VEX_SCAN_REPORTS`); compile-vex.sh:347-397 (every reported finding becomes `under_investigation` with the report's `CreatedAt`) | compile-vex.sh:232, :272-273, :364: the set `covered` is keyed by vulnerability id alone, while a source statement can be scoped by subcomponent to one package. A finding reported in another package under the same id gets no statement. Probed: one `not_affected` statement for CVE-2026-1 scoped to `pkg:golang/a.example/a`, a report listing CVE-2026-1 in `pkg:golang/b.example/b` and CVE-2026-2 in `c`: output has the not_affected and one under_investigation (CVE-2026-2) only. r2.1. |
| 2.13 | HELD | build.yml:1004-1032 (runs when `fail_closed == 'true'` and uncovered != 0, names each finding per manifest, exits 1); later steps keep `success()` | Switch read through release-policy.sh (build.yml:226, release-policy.sh:59-65). Drilled live per catalogue-policy.yaml comment (run 40691384018). |
| 2.14 | HELD | build.yml:33-34 (`47 4 * * *`), :97-102 (`names=$active` on schedule); lint-workflow-policy.sh holds the cron equal to `release.schedule` (validate.yml:93) | |
| 2.15 | HELD | build.yml:342-359 (local build, every declared platform, not pushed), :361-412 (discard on `on-change` + `equal`), :420 (every later step gated on `publish == 'true'`); package-set-diff.sh:101-110 (purl base plus pull checksum, sorted, per platform), :159-178 (published side read through `cosign verify-attestation` against admitted identities) | Equality must be proven: any unreadable side publishes (package-set-diff.sh:135-177). |
| 2.16 | PARTIAL | package-set-diff.sh:135-195 (verdict `different` publishes), build.yml:394-403 (summary via tee) | The package-set difference reaches the summary only for `package-set-differs`. For `attestation-unreadable` and `platform-set-differs` a published digest carries the tag, yet only a reason line is written (package-set-diff.sh:152-155, :174-177), and with several platforms the loop stops at the first unreadable one. Also the image published is a second build (build.yml:414-451), not the archive whose set was compared. r2.6. |
| 2.17 | HELD | build.yml:406-412 (`publish=true` unless on-change and equal) | Drilled live per catalogue-policy.yaml comment (run 41302227631). |
| 2.20 | HELD | policies/verify-catalogue-images.yaml:29-58 (signature, SPDX, OpenVEX by declared identities); verify-catalogue.sh:108-227; package-set-diff.sh:75-91, :165-173 (CycloneDX read only under admitted identities) | |
| 2.21 | PARTIAL | rescan.yml:391-398 (invariants step, fails the run); check-visibility.sh:99-141 (anonymous token per repository, anonymous manifest per tag) | The repository set is the `image:` values of the definitions on disk (check-visibility.sh:100-103) and the tag set comes from the same enumeration, not from the registry namespace. A repository under `ghcr.io/mm-weber/dhc` whose definition directory was removed is not probed. r2.2. |
| 2.22 | PARTIAL | rescan.yml:31 (daily), :135-140 (enumeration, hard-fail), :142-218 (every platform manifest of every tag-referenced digest by its own digest, aperture via scan-image.sh), :391-404 (2.21 and 2.24 over the enumeration) | Two gaps: (a) enumeration covers only repositories named by definitions on disk (enumerate-catalogue.sh:57-67), r2.2; (b) a manifest whose scan fails is a `::warning::` and the step exits 0 (rescan.yml:200-206), reattest.sh skips that digest without failing (reattest.sh:134-140, :276), and no later step fails on `steps.scan.outputs.failed` (only the summary reads it, rescan.yml:954): a day with unscanned manifests can be green. r2.3. |
| 2.23 | HELD | render-verification.sh:110-180 renders policies/verify-catalogue-images.yaml:26-58 from catalogue-policy.yaml verification (issuer, releaser identity exact as keyless `subject`, SPDX from releaser, OpenVEX `count: 1` of releaser or re-attester); drift-checked on every PR (validate.yml:90) | Provenance rule absent because the mode is `report` (see 2.28). |
| 2.24 | PARTIAL | rescan.yml:404; verify-catalogue.sh:76-227 (one `kyverno apply` per tag-referenced digest plus the declared control, catalogue-policy.yaml:161; control admitted or any digest not admitted fails the run) | Same repository-set limit as 2.21: a tag-referenced digest in a repository with no definition on disk is never applied. r2.2. |
| 2.25 | HELD | render-verification.sh:182-262 renders the recipe into README.md:80-106 and docs/user-manual.md:161-187 (issuer, BUILD and RESCAN identities with workflow file and ref; provenance step with the five expectations under report and required; "attest none" line under off, :240; BuildKit supplementary line, :258-260); drift check validate.yml:90 | The recipe's SBOM and OpenVEX steps can fail silently for a consumer (no pipefail): r2.8. |
| 2.26 | HELD | scan-image.sh:69-85 (non-zero trivy or empty report exits 1), build.yml:958 (no platform manifest exits 1), :990-996 (`set -e`, jq on each report); later steps keep `success()`; lint-release-steps.sh holds the no-escape rule (validate.yml:114) | The lint does not look at `continue-on-error`: probed, adding `continue-on-error: true` to relscan passes it (rc 0). The release would still stop at the scan-report attestation (`trivy convert` of a missing report), so the property holds by data dependency, not by the lint. r2.10. |
| 2.27 | HELD | build.yml:1146-1157 (subjects), :1169-1175 (`actions/attest-build-provenance` pinned, `push-to-registry: false`, predicate built by the action from the OIDC token, signed keyless as the calling workflow), :1177-1187 + unpack-provenance.sh:291-486 (envelope stored byte for byte as a layer of the `.att` manifest, hash checked against the log entry, :376-381), :1194-1210 (self-check) | No bundle written beside the digest (push-to-registry false). The "from the token's claims" half rests on the action's documented behaviour; nothing in the tree generates the predicate. |
| 2.28 | HELD | render-verification.sh:168-179 (under `required`, a provenance attestation with the releaser keyless entry and five Equals conditions from `verification.provenance.expectations`); check-provenance.sh:450-507 | Mode is `report` (catalogue-policy.yaml), so the rule is not rendered today; the branch is exercised by render-verification_test.sh only. |
| 2.29 | HELD | rescan.yml:703-732 (`check-provenance.sh report` over every supported digest and its platform manifests; uncovered never fails under report, check-provenance.sh:615-632), :838-847 (coverage into the status) | A reference whose check fails three times for a transport reason is reported `uncovered`, not "not measured" (check-provenance.sh:550-551, :621-629). The switch read at rescan.yml:102-104 cannot fail: r2.9. |
| 2.30 | HELD | build.yml:1147, :1171, :1178, :1195 (provenance steps skipped when `off`, nothing else changes); rescan.yml:711-713 (states off, verifies none), :843-844 (status gets `--provenance-mode off`); render-verification.sh:240 (recipe line) | Live-drilled per catalogue-policy.yaml comment (build run 44763409487, rescan run 44764641823). |

### Requirement 3 (r3.md)

| # | Verdict | Mechanism (file:line) | Gap or note |
|---|---|---|---|
| 3.1 | HELD | .github/workflows/renovate.yml:21-22 (`cron: "0 */4 * * *"`), :46 renovatebot/github-action pinned by sha; cron held equal to its declaration by scripts/lint-workflow-policy.sh (validate) | Every 4 h, inside the 6 h bound. Whether a run completes is live state (see r3.1 for a run-level risk). |
| 3.2 | PARTIAL | renovate.json5:63-76 (from-source manager, github-tags), :91-136 (grafana, github-releases), :410-422 and :423-443 (postUpgradeTasks); scripts/refresh-definition.sh:96-125, scripts/refresh-grafana.sh:220-272 (ref, checksum/COMMIT_SHA, vars, three tags, stamp); scope: renovate.json5:59-61 rendered by scripts/render-tracking.sh, drift-checked at validate.yml:140 | The github-tags-keyed task also fires on every github-actions bump and fails there (r3.1). Note, latent: alias-tag rewrite is hard-coded to the `-alpine3.23` suffix (refresh-definition.sh:119-120, refresh-grafana.sh:243-244); every current definition uses it, and lint-pins.sh would fail a stale alias. "Version policy" is nowhere declared per definition; it is the Renovate rules themselves (majors staged, grafana minors staged). |
| 3.3 | HELD | renovate.json5:305-310 (cert-manager monorepo), :311-323 (valkey runtime and compat), :324-335 (cert-manager chart pins) | Keyed on depName, so a new definition from the same source joins the group without a rule change. |
| 3.4 | HELD | renovate.json5:336-341 (`matchUpdateTypes: ["major"]`, `dependencyDashboardApproval: true`), no later rule resets it | Vulnerability-alert PRs (3.14) are forced to `dependencyDashboardApproval: false` by Renovate's default (Renovate dist config/options/index.js:2046-2056); that applies to tooling dependencies, not to definition upstreams. |
| 3.5 | HELD | renovate.json5:395-409 (github-tags, patch+digest, automerge), :465-474 takes Actions back out; grouped PR automerges only if every upgrade does (Renovate dist workers/repository/updates/generate.js:365); gates: build.yml:1247-1263, e2e.yml gate, required by .github/rulesets/main_sec.json:38-65, compared daily with the live ruleset by scripts/check-governance.sh (Req 9.9) | Note: main_sec.json:23 requires one approving review, so an automerge lands only through the token holder's admin bypass (main_sec.json:86-92); the platform then does not enforce the required checks, and the gating is Renovate's own wait for a green branch status (stricter: every check). Which actor RENOVATE_TOKEN is cannot be read from the files; triage/LOG.md:1731 records an automerge (#111). |
| 3.7 | PARTIAL | renovate.json5:374-394 (`minimumReleaseAge: "3 days"`, `timestamp-required`, over github-tags, github-releases, npm, pypi, helm, go) | Exemptions wider than "only": the third-party e2e probe image (docker, renovate.json5:198-210), every vulnerability-alert PR (Renovate default `minimumReleaseAge: null`), and the golang-version datasource of the `go` directives in test/go.mod:3 and triage/rescan/go.mod:3 (r3.2). |
| 3.8 | HELD | scripts/refresh-definition.sh:73-94 (verify before the first write at :106), :74 `refuse` names the signal; scripts/refresh-grafana.sh:202-216 (class and per-arch API-versus-sidecar agreement before the first write at :224); both under `set -euo pipefail` | Note: the refusal leaves Renovate's own edit of the version on the branch; Renovate (dist update/branch/index.js:458-475, :756-790) opens the PR once the release is older than 2 h (always, after the 3-day age), sets a failed artifacts status and posts the task's stderr, which names the signal. The Refresh Tooling itself writes nothing. |
| 3.9 | HELD | scripts/verify-arch-pins.sh:70-125 (pinned, served bytes, version statement, per arch; names each value at :120; no known statement origin or unreadable statement fails closed at :75-82); wired at build.yml:280-283 for every PR-changed active definition (build.yml:103-106, active-set filter :157-164) | An inactive definition is not built, but Req 1.16 fails such a PR in validate. |
| 3.10 | HELD | rescan.yml:31 (daily cron), :452-484 (step under `if: always()`), scripts/check-authenticity.sh:90-148 (active set only, :53, :93), exit 1 on any mismatch (:171); issue per mismatched definition with label `supply-chain` and marker (rescan.yml:470-483) | Note: a failed `gh issue create` is not checked (rescan.yml:482, no `-e`), but the run is already red from the mismatch and the next day retries. |
| 3.11 | HELD | renovate.json5:280-301 (helm manager over `upstream:` in chart/*/chart.yaml, registryUrl captured), :444-451 (`automerge: false`), :336-341 (majors staged); chart/cert-manager/chart.yaml:9-12, chart/grafana/chart.yaml:3-6, chart/valkey/chart.yaml:3-6; scope via render-tracking.sh:54-64 | |
| 3.12 | HELD | renovate.json5:211-249 (two chart-pin managers capture tag and digest), :452-464 (docker, `ghcr.io/mm-weber/dhc/**`, digest, automerge), build-layer rule ordered after (:492-500); same gating as 3.5 | |
| 3.13 | HELD | scripts/definition-lib.sh:279-333 (`read_origin`: four attempts resting 10/30/90 s, HTTP status and message or curl error, primary rate limit asked once), :354-371; scripts/check-authenticity.sh:64-68 (`ok: null`), :77-88 (tag listing with git's error), :102-103, :109, :113, :126, :131, :143; exit 2 (:172); rescan.yml:483 files only `ok == false` | Note: a statement answered 200 but not JSON makes `github_verification` exit 1 with no text (definition-lib.sh:365-370), recorded as not measured without an origin detail. Edge only. |
| 3.14 | PARTIAL | renovate.json5:46-48 (`vulnerabilityAlerts: { enabled: true }`), Renovate default `vulnerabilityFixStrategy: "lowest"` and the force rule (Renovate dist init/vulnerability.js:149-167) | Alerts on GitHub Actions open no fix PR (Renovate maps no `actions` ecosystem); the alert read depends on the token's "Dependabot alerts: read" scope, live state no daily check asserts, and a failed read only warns on the Dashboard (r3.3).  **Re-check:** r3.3 NARROWED (a failed alert read is shown on the Dependency Dashboard under "Repository problems", not silent); verdict unchanged, PARTIAL. |
| 3.15 | HELD | Renovate reads `dependabot/alerts?state=open` only (Renovate dist platform/github/index.js:1552) and skips any alert with `dismissed_reason` (init/vulnerability.js:63-65); the record is CONVENTIONS.md:497 (M25) | A behaviour of Renovate, not of a file here. Holds as long as the Renovate version does. |

### Requirement 4 (r4.md)

| # | Verdict | Mechanism (file:line) | Gap or note |
|---|---|---|---|
| 4.1 | PARTIAL | scripts/render-chart.sh:17-23 (helm template --repo --version from chart.yaml upstream.version, -f overlay, no post-renderer); test/install/install.go:85-95 (the e2e install uses the same pin, no post-renderer); no vendored templates in chart/cert-manager, chart/grafana, chart/valkey (only chart.yaml, README.md, config/) | "at its pinned version" is not enforced as an exact version: chart/chart.schema.yaml:31 types it `str()`, helm's --version accepts a range, and the Renovate regex (renovate.json5:298) captures any token. A range would render, gate and install whatever the repository serves. r4.1 |
| 4.2 | HELD | chart.yml:41-58 runs on every pull_request and push to main (chart.yml:8-11), no paths filter; policies/require-image-digest.yaml:34-41 (64-hex digest, containers, initContainers, ephemeralContainers); policies/restrict-registries.yaml:28-33 (ghcr.io/mm-weber/dhc/*, rendered from catalogue-policy.yaml); the check is listed as required in .github/rulesets/main_sec.json ("render + policy gate") | The gate checks digest shape and namespace, not that the digest was published; a changed pin changes chart/<c>/, which puts the chart on the e2e matrix (e2e.yml:78-85), whose pull fails on an unpublished digest. restrict-registries does not list ephemeralContainers (helm charts do not render them). Probed: grafana 10.5.15 + overlay passes 3/3, a tag-only docker.io Deployment fails with exit 1. |
| 4.3 | HELD | Overlays: chart/cert-manager/config/values-hardened.yaml:14-39 (UID trio; rest upstream default, verified in the v1.21.0 render: readOnlyRootFilesystem true on all three), chart/grafana/config/values-hardened.yaml:18-27, chart/valkey/config/values-hardened.yaml:37-49, chart/hardened-app/values.yaml:25-37. Enforcement on live pods: test/checks/securitycontext.go:53-73 (all seven clauses, effective container-over-pod values, init containers too), called for every pod of the release by test/e2e/assert_test.go:31-38 | The render gate holds only pod-level runAsNonRoot (see 4.6); the full profile is held by the e2e, which runs per affected component on pull requests (e2e.yml:78-92), not on main or a schedule. Every chart is active today (catalogue-policy.yaml active_set), so every chart change reaches it. |
| 4.4 | HELD | grafana: chart/grafana/config/values-hardened.yaml:45-54 plus the chart's own emptyDirs (render: four emptyDir at /var/lib/grafana, /var/lib/grafana-search, /tmp, /var/log/grafana); valkey: dataStorage.enabled false (values-hardened.yaml:63-64), the chart falls back to emptyDir at /data (0.11.0 render: emptyDir {} under valkey-data); cert-manager and hardened-app write nothing (READMEs) | No check binds a definition's writable-path inventory (image/grafana/image.yaml:123) to the chart's volumes or asserts the volume type; the e2e shows only that the workload reaches Ready and passes its probe under readOnlyRootFilesystem. Note, not a gap in the sentence.  **Re-check:** r4.10 (the emptyDir wording) REFUTED; verdict unchanged, HELD. |
| 4.5 | PARTIAL | chart/valkey/chart.yaml:39-50 (variant, reason, issue, decided_at, review_by); shape by yamale, chart/chart.schema.yaml:32-37, run in validate.yml:29-33; trigger binding by scripts/lint-compat.sh:52-90 (a chart deploying a `variant: compat` definition must carry a block naming it); README section chart/valkey/README.md:71-126 | The README clause has no check: lint-compat.sh never reads a README. Probed: with chart/valkey/README.md deleted and `issue: "n/a"`, lint-compat and yamale both pass (exit 0). The "upstream issue reference" is any string. r4.2 |
| 4.6 | PARTIAL | chart.yml:41-58: every chart/*/ rendered by render-chart.sh, `kyverno apply` with the three policies, rc=1 on a render failure or a policy failure, exit $rc; kyverno apply exits 1 on a failed rule (probed); self-tests validate.yml:69-72 (kyverno test policies/tests/) | "non-root execution" is checked only as pod-level spec.securityContext.runAsNonRoot: true (policies/require-nonroot.yaml:25-28). Probed: a Deployment with pod runAsNonRoot true and a container with runAsNonRoot false, runAsUser 0 and privileged true passes all three policies, exit 0. r4.3 |
| 4.7 | PARTIAL | Deviation tables: chart/cert-manager/README.md:25-31, chart/grafana/README.md:35-44, chart/valkey/README.md:37-46; hardened-app is owned (no upstream defaults) | No mechanism compares an overlay's keys with its README. One deviation is undocumented: the e2e installs cert-manager with `--set crds.enabled=true` (test/e2e/components_test.go:31), absent from the cert-manager README, whose recipe (README.md:11-16) omits it. r4.4 |
| 4.8 | PARTIAL | scripts/lint-compat.sh:91-108 (review_by missing, before decided_at, or before today fails), run on every pull_request and push to main (validate.yml:3-6, 29-33); a required check ("yamllint, pin lint, policy tests" in main_sec.json) | "until that decision carries a fresh review-by date from a dated re-decision": the lint does not require decided_at to move. Probed with DHC_TODAY=2026-11-25: the real block fails (exit 1); with only review_by changed to 2099-02-24 and decided_at left at 2026-08-25, it passes (exit 0). r4.5 |
| 4.9 | PARTIAL | rescan.yml:452-484 (`if: always()`), scripts/check-authenticity.sh:150-168 (each chart's lapsed review_by: a ::warning naming the chart, a record with ok false); summary count rescan.yml:956 | The compat loop sits after `active=$(active_definitions "$ROOT") || exit $?` (check-authenticity.sh:53): when the active-set read refuses, the run fails by that name and no lapse is reported that day. A chart.yaml that does not parse is skipped silently (python error to stderr, empty review_by, `continue`, :154-160). r4.6 |

### Requirement 5 (r5.md)

| # | Verdict | Mechanism (file:line) | Gap or note |
|---|---|---|---|
| 5.1 | HELD | test/go.mod:6-7,10 (ginkgo/v2 v2.34.0, gomega v1.44.0, e2e-framework v0.7.0); Ginkgo entry test/e2e/e2e_suite_test.go:94-97; e2e-framework env/klient e2e_suite_test.go:70-90, test/checks/wait.go:23-37; ephemeral cluster e2e.yml:147-151 (create) and :274-276 (delete, if: always()); local mode creates and destroys through e2e-framework's kind provider e2e_suite_test.go:75-89 | In CI the cluster is made by the kind CLI and e2e-framework attaches by kubeconfig (e2e_suite_test.go:70-74); still ephemeral and still e2e-framework. Compiled, vetted and unit-tested on every PR: validate.yml:381-397. See r5.6 for design.md's wording |
| 5.2 | PARTIAL | e2e.yml:16-18 (every pull_request, no path filter); detection e2e.yml:47-97 through active_components (scripts/definition-lib.sh:156-170) and each chart's deploys: list; one leg per component e2e.yml:99-114; install test/e2e/components_test.go:66-73, install_test.go:29-78; images pulled from ghcr by the pinned published digest e2e.yml:166-181 | The suite installs only components listed in the hand-kept componentSpecs (test/e2e/components_test.go:25-48). Nothing checks that list against chart/*/chart.yaml or harness.Components (test/harness/harness.go:21-26). A chart that is in the harness but not in componentSpecs gets a leg in which every spec skips (components_test.go:58-59, upgrade_test.go:33-34), so the leg and the e2e gate are green without an install. Not reachable on today's four charts; reachable by the documented onboarding steps (r5.1, r5.4) |
| 5.3 | HELD | assertReadyHardened test/e2e/assert_test.go:23-30; ReadyTimeout = 5 min test/checks/wait.go:16; rollout wait test/checks/rollout.go:57-110 (zero matching workloads stay pending, :75-78); pod Ready predicate test/checks/podready.go:6-13 | Rollout completion (AvailableReplicas == desired) already implies Ready within its 5-minute bound, and the pod wait then adds a second 5-minute bound. Both wait from the moment helm returns. Applied to both the install and the upgrade spec (upgrade_test.go:48,52) |
| 5.4 | HELD | test/checks/securitycontext.go:27-75 (UID 65532 :56, GID :59, runAsNonRoot :53, readOnlyRootFilesystem :62, allowPrivilegeEscalation :65, drop ALL :68, seccomp RuntimeDefault :71; init containers included :33-35); applied to every live pod matching the selector, not-empty asserted, assert_test.go:31-38 | Pods outside the component's label selector (componentSpecs[*].Selector) are not checked. All three upstream charts put app.kubernetes.io/instance=<release> on their pods, so no gap today |
| 5.5 | HELD | Declared probe resolved by name test/e2e/probes_test.go:37-65; run once after the Ready checks assert_test.go:42-49; once per install (install spec components_test.go:72; upgrade spec only after the upgrade, upgrade_test.go:48 runs no probe on the base state, :52 does); declarations held equal to registrations TestProbeDeclarations probes_registry_test.go:17-52 (validate.yml:395-397) | "Standing for every active definition that chart deploys" is by declaration (chart/*/chart.yaml deploys:). Note: the valkey chart runs only the -compat image (chart/valkey/chart.yaml:14-18). The runtime valkey definition is never started on kind; its proof is the byte-equal pair rule. The criterion's "standing for" sanctions this |
| 5.6 | HELD | Bump detection e2e.yml:207-235 (chart: upstream.version vs base :215-223; image: deployed values file vs base, base copy snapshotted :228-235); upgrade spec test/e2e/upgrade_test.go:24-56 (install base, assert, helm upgrade, rollout-gated re-assert and probe); mutual exclusion with the install spec components_test.go:61-63 | A definition-only bump PR (image/<d>/ moved by Renovate) installs the published, unbumped image as a plain install. The upgrade to the new image runs on the chart-pin PR that follows the release. This matches the 2026-09-09 reading (review row 5.6, "component" = chart). Consequence stated in lanes.md:420: a bumped image is released before any kind run |
| 5.7 | HELD | go test exits non-zero on a failed assertion → leg red → gate red e2e.yml:280-294; suite dump on every failed spec e2e_suite_test.go:103-114, test/checks/diagnostics.go:31-61; workflow dump (cluster-wide describes, per-pod logs, kind export logs) e2e.yml:249-264; upload as artifact e2e.yml:266-272 (if: failure()) | The suite's own dump omits StatefulSets and logs; the workflow step adds logs and kind export logs, so the clause holds |
| 5.8 | PARTIAL | scripts/lint-probes.sh:103-115 (no chart, or no chart with a probe → ::error naming the definition, exit 1 :118-121); validate.yml:147-148; unregistered probe names: TestProbeDeclarations probes_registry_test.go:42-44 | (a) The lint is step 17 of the conventions job (validate.yml:147). Any of the 16 steps before it failing skips it, so that run fails without naming the definition. (b) A chart naming an unregistered probe counts as "declaring a functional probe" for the lint (lint-probes.sh:77-79,108-109). The Go test fails, naming the chart and the probe, not the definition. r5.3 |
| 5.9 | PARTIAL | proof_entries scripts/definition-lib.sh:193-223 (none needs a reason :216-219); printed lint-probes.sh:99 | "Report ... with its reason in every validation run" fails in three cases. The skipped-step case (as 5.8 a). A malformed proofs map or active set prints no entry (lint-probes.sh:48-57). A multi-line reason prints only its first line (probed). Vacuous today: proofs: {} (catalogue-policy.yaml:111). r5.2 |
| 5.10 | PARTIAL | Unknown kind, entry outside the active set, none without reason: proof_entries definition-lib.sh:206-219 (exit 2 naming the entry; lint-probes.sh:53-57 exit 1); none for a chart-deployed definition: lint-probes.sh:92-98 naming chart and definition | All four refusals probed and red, naming the entry. Only gap: the same skipped-step case as 5.8 (a). r5.3. The none-for-chart-deployed refusal is stricter than the sentence: it refuses even when the deploying chart declares no probe. This is harmless, because 5.8 fails that case anyway |

### Requirement 6, criteria 1 to 30 (r6a.md)

| # | Verdict | Mechanism (file:line) | Gap or note |
|---|---|---|---|
| 6.1 | HELD | `build.yml:503-562` (compile, then `scan-image.sh`), `scan-image.sh:67-76` (`--severity` from the declared aperture, `--exit-code 0`), `build.yml:569-571` (count), `build.yml:896-916` (fails naming each finding) | Both SHALLs hold: Trivy scans, every reported finding (the report holds the aperture only) fails the leg. Note: the "Trivy is the declared authoritative consumer" refusal (`triage-policy.sh:142-143`) runs on a pull request only inside the `continue-on-error` portability step (`build.yml:737-747`); validate never asks, the rescan smoke test does (`consumer-smoke.sh:55`). A PR changing only the gate's scripts or the policy builds nothing (`build.yml:103-151`), so the gate is not exercised on its own change; outside this criterion's WHEN |
| 6.3 | PARTIAL | `rescan.yml:142-218` (scan, supported set into `$OUT/trivy`), `:597-616` (enrich), `:618-635` (dedup), `:637-651` (reporter), `:667-689` (file); `report.go:248-301` (severity, EPSS, KEV, affected images) | EPSS outage is swallowed and the issue is filed with "n/a"; a KEV file that downloads but does not parse files every issue as "KEV: no"; a failed supported-manifest scan files nothing and leaves the run green; the reporter has no VEX-unresolved fence. r6a.1 |
| 6.4 | HELD | `triage/vex/*.openvex.json`; attached on release `build.yml:1060-1076,1113,1125`; re-attested by the rescan `rescan.yml:293` with `reattest.sh` | Shape held by `lint-vex-product.sh`; the "WHEN a decision concludes" half is the maintainer's |
| 6.5 | PARTIAL | the bump lanes (Renovate, `renovate.json5`); the gate's error text names it (`build.yml:914`) | Process criterion: nothing links a recorded fix decision to a pull request. r6a.2 |
| 6.7 | HELD | `lint-accepted-risk.sh:58-69,124-136` (treatment, owner, ref, blocked, decided_at, expired_at, paths), `:152-154` (transfer names an issue), `:221-225` with `lint-log-anchors.sh:79-101` (ref resolves to a LOG heading); `validate.yml:79-80` | |
| 6.8 | HELD | `compile-vex.sh:431-438` (an exception compiles only to `affected`), `lint-vex-product.sh:130-133` (source lane admits only not_affected/fixed) | Structural: two lanes, two formats. A human could still write an acceptance as not_affected in triage/vex/; that is review |
| 6.9 | HELD | Trivy's `expired_at` on `--ignorefile` (`scan-image.sh:53-54`), counted at `build.yml:570-571,904`; `lint-accepted-risk.sh:180-183` also reddens validate | Trivy drops the entry from midnight UTC of the expiry day, a day earlier than the lint and compiler (LOG.md:3473-3489, live-evidence.md:150); conservative for this criterion. Third-party behaviour, no repository test |
| 6.10 | PARTIAL | `rescan.yml:570-595` reusing `lint-accepted-risk.sh:180-186`; window from `triage-policy.sh . expiry-warning` | The step cannot fail: a lint that cannot run prints "_none_ ✓" and exits 0 (probed). r6a.3 |
| 6.11 | HELD | `lint-accepted-risk.sh:124-136` (each field, paths), `:171-178` (span over the largest ceiling from `decided_at`), ceiling from `triage-policy.sh:76-77`; `validate.yml:79-80` | |
| 6.12 | PARTIAL | `lint-accepted-risk.sh:36-42` | Detection is by the name `.trivyignore*` only, and any directory named `temp` or `node_modules` is pruned at any depth (probed). r6a.4  **Re-check:** r6a.4 CONFIRMED, low (recheck-r6a-4.md; its re-checker saw the finding's first line, not only the title); verdict unchanged, PARTIAL. Finding F65. |
| 6.13 | PARTIAL | `build.yml:772-857`, `govulncheck-report.sh:51-81` | `continue-on-error: true`: a tool that did not run leaves the PR green; files under 1 MiB are never candidates; `docker export ... \|\| true` hides a partial filesystem. r6a.5 |
| 6.14 | NOT HELD | rendered only: `govulncheck-report.sh:16-18`, `build.yml:849-850` | No code compares a govulncheck result with `triage/vex/`; the govulncheck JSON is not uploaded (`build.yml:919-927` uploads trivy.json and grype.txt). Design Decision 7 (`design.md:447-451`) assigns it to the maintainer at review. r6a.6 |
| 6.15 | PARTIAL | `lint-log-anchors.sh:103-127` (every statement cites a LOG heading that exists) | The lint checks that a citation resolves, not that the cited entry holds a symbol/package-level govulncheck result or an entrypoint argument; six statements carry `vulnerable_code_not_in_execute_path`. r6a.7 |
| 6.16 | PARTIAL | `govulncheck-report.sh:53,60-62,73-74` (module level renders "not measured", most-resolved finding wins) | The "treat as unmeasured" half is rendered; "SHALL NOT cite it" is unchecked. r6a.8 |
| 6.17 | HELD | `lint-vex-product.sh:92-122` (purl, type oci), `:153-157` (a definition publishes that name), `:182-207` (repository_url equals the published repository); `validate.yml:192-193` | |
| 6.19 | HELD | `lint-vex-product.sh:210-221` | |
| 6.20 | HELD | `lint-vex-product.sh:170-178` (version is a declared tag of a definition publishing the name), `:137-139` (fixed needs a version), `:146-148` (versionless needs `version-independent:` in status_notes) | |
| 6.22 | NOT HELD | none; convention only (`triage/README.md:352-357`) | No lint, test or compiler rule checks that an earlier statement was retained or that the superseding one is later. r6a.9 |
| 6.25 | HELD | `lint-accepted-risk.sh:111-146` (per file, (id, path) seen twice fails) | |
| 6.26 | PARTIAL | `accepted-risk-report.sh:76-91`, called at `build.yml:624` | An entry counts as live when any suppression carries its id and its statement text; two entries with one id and one statement mask a dead one (probed). r6a.10 |
| 6.27 | HELD | `accepted-risk-report.sh:52-74` (Target per suppression), `build.yml:616-624` | PR gate only, which is the criterion's subject |
| 6.28 | HELD | `build.yml:555,562` (`.vexscan`), `:987-992` (`.vexrelease`); `rescan.yml:191-200`; `scan-image.sh:46-51` reads only the directory it is given | `triage/vex/` is never handed to a scanner |
| 6.29 | HELD | `compile-vex.sh:104,264-267,387,433`; manifests supplied `build.yml:987,1073`, `rescan.yml:191`; PR digest `build.yml:498-500` | |
| 6.30 | HELD | `compile-vex.sh:249-258` | Dropped per product: a statement with one in-scope and one out-of-scope product keeps the in-scope one. Tested (`validate.yml:211-212`) |

### Requirement 6, criteria 31 onward (r6b.md)

| # | Verdict | Mechanism (file:line) | Gap or note |
|---|---|---|---|
| 6.32 | HELD | scripts/compile-vex.sh:218-229 (every drop recorded with kind, cve, product, reason), :474-483 (report: digest, digests, tags, drops) when COMPILE_VEX_REPORT is set; every caller sets it (rescan.yml:191, reattest.sh:202, build.yml:1075) | A compile that fails writes no report (compile-vex.sh:474 is reached only on success), which breaks a rescan claim (r6b.12), not this criterion: nothing was compiled. |
| 6.33 | HELD | rescan.yml:971-1003 (per-image counts; tag-scoped drops listed by statement), rescan.yml:1023-1029 uploads rescan-out/, which holds every vex/*.report.json with all drops | The summary lists by name only kind "tag" drops. "malformed" drops are counted under "belonging to other images" (rescan.yml:999-1000), which is a wording slip. |
| 6.34 | HELD | Release: build.yml:1060-1076 compiles for DIGEST and every manifest, then build.yml:1099,1113,1125 attests that file. Rescan: reattest.sh:201-205,233-236 | |
| 6.35 | HELD | The gate counts only .Vulnerabilities (build.yml:570-571), and Trivy suppresses only not_affected and fixed. Source statements can be only not_affected or fixed (lint-vex-product.sh:130-132), and the gate's compile gets no scan reports, so it emits no affected or under_investigation (build.yml:555). | |
| 6.37 | PARTIAL | reattest.sh:201-205 gives the compile the source, the exceptions (default path), today's reports (attested in step 1), the verified previous document and the issue map | When the issue-map read fails, an empty map {} is used in its place (rescan.yml:280-282), and the compile runs as if no issue were open (r6b.5). |
| 6.38 | PARTIAL | compile-vex.sh:398-446 (affected per suppressed finding with a live entry; action statement :325-337; action_statement_timestamp from decided_at :439-441; first seen via carry_forward :184-191) | "No source statement covers" is decided per CVE id, not per finding and package (:272-273, :409). A not_affected statement for package A suppresses the affected statement for an exception on package B (r6b.1, probe). Latent: for valkey-compat digests the rescan reads valkey.yaml (r6b.10). |
| 6.39 | HELD | lint-vex-product.sh:130-132 names the file, CVE, product and status; run by validate.yml:193 | A statement with no products is never status-checked, but it compiles to nothing (compile-vex.sh:268). |
| 6.40 | PARTIAL | compile-vex.sh:145-201 (keeps timestamp; last_updated on a change of status, action statement, subcomponents or issue links) | When the verified read of the previous document fails, the run treats it as "no previous document": first seen resets to today's report time and the replaced document is re-attested, with the run green (reattest.sh:178-187,231; r6b.2). |
| 6.41 | PARTIAL | compile-vex.sh:312-315 (expired), :413-414 (no affected from an expired entry), :376-384 (under_investigation with the lapse note, first seen carried) | Same per-CVE skip as 6.38: if any source statement covers the CVE for another package, the lapsed finding gets no statement (:364; r6b.1). Latent valkey-compat keying (r6b.10). |
| 6.42 | PARTIAL | reattest.sh:142-163 (cosign attest --type vuln --replace per manifest, before the compile at :205) | A digest whose scan failed is skipped whole (reattest.sh:134-140) and does not fail the step (:276 counts only "failed"). The scan step itself exits 0 (rescan.yml:200-218). The run is green while that digest's attested report stays the last successful one (r6b.4). |
| 6.43 | HELD | reattest.sh:214-244 (statement-set comparison against the verified document; count read from .att for the index and each manifest; --replace on the digest and each manifest; a failure is counted and exits 1) | |
| 6.44 | OWNER-SIDE | Registry state. Asserted daily by check-attestation-count.sh (rescan.yml:432) after the repair in reattest.sh:225-236 | The release attests OpenVEX without --replace (build.yml:1113,1125). A second release attest on one digest would leave two until the next rescan repairs it. |
| 6.45 | HELD | check-attestation-count.sh:35-59 (n != 1 fails, named) feeding rc in rescan.yml:432,439 | A crane read failure counts as 0 (:26-27). That fails closed but under the wrong name. |
| 6.46 | PARTIAL | status.go:309-353 (first seen and decided from the statement), :474-479 (first seen never later than published), :489-505 (fixed = first day absent when the repository was fully scanned), previous body rescan.yml:742-761 | The previous-status lookup swallows a GitHub failure (rescan.yml:752-753, "or true"). The clocks then start fresh, dropping fixed rows and the earlier first-seen times, silently (r6b.3). The step is skipped when any re-attestation fails (rescan.yml:744; r6b.13). A finding's decision can come from a statement about another package (r6b.1). |
| 6.47 | PARTIAL | status.go:624-761 (table and fenced JSON), decision.go:44-76 (status, justification, statement, notes, links), rescan.yml:866-890 (issue and catalogue-status artifact), page via rescan.yml:895-900 | "One status issue": the same swallowed lookup creates a second "Catalogue status" issue (rescan.yml:874-880; r6b.3). Skipped on any re-attestation failure (r6b.13). The body grows without bound toward GitHub's body limit (r6b.14). |
| 6.49 | HELD | catalogue-policy.yaml:167-220 (aperture, ceilings, kev_ceiling, expiry_warning, support statement with both sentences); triage-policy.sh:62-119 refuses holes | |
| 6.50 | HELD | build.yml:883-894 to check-exceptions.sh gate, :109-130 (KEV tier, else the severity in the report, else the largest ceiling; names file, id, span and tier) | Depends on a valid KEV set. A well-formed but empty feed is r6b.6 (6.59). |
| 6.51 | PARTIAL | rescan.yml:422-423 to check-exceptions.sh rescan, :97-101,114-130 | Reports are found by "exception file name + __*.json" (:101), but rescan reports are named by repository (rescan.yml:176,198). An image with no reports today (failed scan, r6b.4) or a definition publishing under another name (valkey-compat, r6b.10) is tiered by the largest ceiling, and a severity breach passes silently. |
| 6.52 | HELD | lifecycle.go:345-386 (close when no in-aperture report, no incomplete digest, at least one examined), closeAbsent :495-515 names every examined digest and the scanner and DB versions (rescan.yml:246); applied after re-attestation rescan.yml:311-355 | |
| 6.53 | HELD | lifecycle.go:374-386, closeCovered :442-487 (coverage = ignored, not_affected or fixed in the report; each covering artifact named) | |
| 6.54 | HELD | Inputs are today's reports (attested before the apply, rescan.yml:325-332), SBOMs read through verification (fetch-sboms.sh:51-55) and triage/vex. Lifecycle writes no triage artifact. | |
| 6.55 | HELD | scan-image.sh:74 --show-suppressed; fill-scanner-db.sh:35-87 (DB origin and UpdatedAt, refusing when absent) in both arms (build.yml:1051, reattest.sh:155-157); TRIVY_DB_REPOSITORY set (build.yml:51, rescan.yml:54) | |
| 6.56 | HELD | lifecycle.go:442-456 (accepted, then not_affected, else fixed), :495-623 (SBOMs of the named images' repositories only; removed; absent; no image means all) | Packages are matched by name only (lifecycle.go:589). Not probed against live SBOMs. |
| 6.57 | HELD | lifecycle.go:389-412 (lowest-numbered closed issue, no open twin, reported in aperture), rescan.yml:356-365 | Closed issues past --limit 2000 only raise a warning (rescan.yml:240-243). |
| 6.58 | HELD | reattest.sh:178-183 (cosign verify-attestation --type openvex per declared role identity and issuer); SBOMs via fetch-sboms.sh:49-55. Scan reports are never read back from the registry. | |
| 6.59 | PARTIAL | build.yml:889-894 (a failed fetch is named, exit 1); check-exceptions.sh:57-61 (an unparseable file exits 2) | A response that parses as JSON but holds no "vulnerabilities" key ({}) is evaluated as an empty KEV set and passes (check-exceptions.sh:58; probe rc=0). r6b.6. |
| 6.60 | PARTIAL | rescan.yml:422-428 (fetch failure gives rc=1, named), :423 (unparseable file exits 2, so rc=1), rescan.yml:607, rescan-status main.go:142-150 | {} passes as in 6.59 (r6b.6). An unparseable file fails the run, but the issue set is still built and filed with "KEV: no" (rescan.yml:607 checks only -s; rescan-report main.go:62-67 warns and continues; probe). r6b.7. |
| 6.61 | PARTIAL | rescan.yml:805-858 (status data, enumeration, admission proof, expiry report into --out-html), page.go:72-168, page.html.tmpl:39-89, upload rescan.yml:895-900, deploy :1040-1054 | "Attested that day" is drawn from whether a compiled document exists (page.html.tmpl:55, status.go:207,403, inputs.go:69-83), not whether the attestation succeeded (reattest.sh:205-241; r6b.9). A malformed page switch leaves the page off without a failure (r6b.11).  **Re-check:** r6b.9 NARROWED (a failed attest withholds the page, so the page never says "attested" for it); verdict unchanged, PARTIAL, on r6b.11 (confirmed). |
| 6.62 | PARTIAL | rescan.yml:1043 (the job runs only when status produced a date), deploy failure (Pages off) fails the job, read-back rescan.yml:1059-1078 | The read-back compares generated_at, a calendar date (status.go:548), not a run identity. A second run the same day whose deployment did not take passes on the first run's data (r6b.8). |

### Requirement 7 (r7.md)

| # | Verdict | Mechanism (file:line) | Gap or note |
|---|---|---|---|
| 7.1 | HELD | docs/CONVENTIONS.md: Naming :7-45 (variants :16-33), Pinning :47-138, Chart override style :350-385 | The file lives under docs/, not at the root; the sentence says only "contain". |
| 7.2 | PARTIAL | validate.yml:3-6 (`on: pull_request` with no paths filter, so every open and every push runs it), :22-25 (`yamllint .`), :42-43 (lint-pins.sh over every file under image/ and chart/); the schema half is the frontend compile of each changed active definition, build.yml:103-106 and the `id: build` step, fanned into the required "build gate", build.yml:1247-1263; "before merge" rests on .github/rulesets/main_sec.json (all five checks required) | yamllint skips everything under data/, temp/ and chart/*/templates/ (.yamllint.yaml `ignore`), so a changed YAML file there is never linted (r7.1). The chart templates are covered by chart.yml's render instead; data/ holds no YAML today. "Before merge" holds only while the live ruleset equals main_sec.json, which the daily check-governance.sh asserts (Req 9.9). Nothing asserts that main_sec.json itself requires the gates (the known 9.8 item, confirmed below). |
| 7.3 | HELD | .github/PULL_REQUEST_TEMPLATE.md:17-28 ("Requirement references", "Convention compliance" checklist) | |
| 7.4 | PARTIAL | lint-pins.sh (every message carries "pinning/authenticity/coherence convention (docs/CONVENTIONS.md)", e.g. :56, :67, :121, :146), lint-accounts.sh, lint-active-set.sh, lint-compat.sh, lint-probes.sh, Kyverno tests, yamllint rule names | Some conventions CONVENTIONS.md codifies have no CI check at all; the file says so itself (r7.2). lint-workflow-policy.sh crashes without naming the value on a string-valued permissions block (r7.3). |
| 7.5 | PARTIAL | install-tool.sh:57-99 and install-scanners.sh:55-61 (exact version plus sha256 recorded, fetched to a file, refused on mismatch or a missing pin); requirements-ci.txt with `pip --require-hashes` (validate.yml:24, chart.yml:38, rescan.yml:579); e2e.yml:124 probe image by digest | Executables a workflow installs or runs without a checksum recorded here: govulncheck (build.yml:778-792, Go sumdb) (r7.4); renovate and json5 plus their whole transitive npm tree (validate.yml:332-340: no lockfile, integrity taken from the registry, transitive versions resolved at install time) (r7.5); the binfmt/QEMU image and the BuildKit daemon image, chosen by the actions' defaults (build.yml:193-194, no `with:`), the Go toolchain from actions/setup-go (validate.yml:350-353, e2e.yml:131-134, rescan.yml:92-95), and the Renovate container the renovatebot action runs (renovate.yml:46) (r7.6). |
| 7.6 | PARTIAL | renovate.json5:137-177 (pin-script manager over install-*.sh), :178-197 (workflow env pins: govulncheck, renovate, json5), :250-264 (pypi), :502-509 (lychee tag shape), :12 (github-actions, gomod); fixture sweep test/renovate/managers.test.mjs:939-958 (every marker resolves) | An Actions bump runs refresh-definition.sh on `.github/workflows`, which exits 1 with "no image.yaml" (renovate.json5:416-421; refresh-definition.sh, line `[ -f "$f" ] || ... exit 1`), and no fixture checks the scope of that rule (r7.7). A newer major of any pinned executable (cosign v3, for example) opens no pull request until the dashboard approves it (renovate.json5:336-341, Req 3.4, deliberate) (r7.8). The unpinned executables of r7.6 have no manager at all. |
| 7.7 | PARTIAL | catalogue-policy.yaml: release :9-66 (public :12, fail_closed :19, publish_policy :25, provenance :55, schedule :59, platforms :64-66); active_set :87-94; proofs :111; verification :113-161 (registry :122, issuer, roles, required, provenance expectations); triage.drills :197-199; workflows :250-311 (schedules, permissions, dispatch inputs) | The two free-text dispatch inputs, build.yml `image` and e2e.yml `component`, are declared by type only (catalogue-policy.yaml:254-256, :306-308), with no allowed values. The drill substitutes sit in triage.drills (:197-199), not beside the `drill` input at :269-272 (r7.9). |
| 7.8 | HELD | render-verification.sh:123-180 (verify-catalogue-images.yaml), :289-323 (restrict-registries.yaml), :184-262 (the consumer recipe spliced into README.md and docs/user-manual.md, :325-337) | The renderer also reads release.provenance, consumers.list and triage.aperture (:57-64, :86), not only the verification section; harmless. The recipe sets no pipefail (known input, confirmed below), which is a 2.25 / 9.13 correctness question, not a rendering one. |
| 7.9 | HELD | validate.yml:89-90 runs `render-verification.sh --check`; :265-280 compare each artifact and fail naming it (`::error file=<path>`) | Only the first begin/end block in each document is compared. Probe: a second, hand-edited copy of the block appended to README.md passed `--check` with exit 0. Such a block is not a rendered artifact under the sentence, so this is a note, not a gap. consumer-smoke.sh runs the first block too. |
| 7.10 | PARTIAL | validate.yml:92-93 runs lint-workflow-policy.sh: cron :60-74, dispatch inputs :76-99, workflow and job permissions :101-123, both directions | A string-valued permissions block (`permissions: write-all` or `read-all`, at workflow or job level) crashes the lint with a Python AttributeError traceback. The step does fail (exit 1), but it does not name the value (probe below) (r7.3). |
| 7.11 | PARTIAL | docs/live-evidence.md (one row per criterion), held by lint-live-evidence.sh:45-97 on every validate run (validate.yml:202-203); today 162 criteria: 156 exercised, 1 defect (6.56), 5 unexercised (2.26, 2.28, 3.13, 3.15, 4.9) | Nothing checks the triage/LOG.md half. The lint counts criteria, not mechanisms. It accepts any non-empty reason for `unexercised`, while the sentence admits only "a live exercise harms consumers". Three of the five reasons are something else (2.26: a drill input Decision 13 does not allow; 3.15: no alert dismissed yet; 4.9: nothing lapsed). The deadline is task 12.1, still open (tasks.md:333), so these are open items, not breaches yet (r7.10). |

### Requirement 9 (r9.md)

| # | Verdict | Mechanism (file:line) | Gap or note |
|---|---|---|---|
| 9.1 | HELD | SECURITY.md:13-29 (promise), :44-52 (aperture, ceilings by reference to catalogue-policy.yaml `triage`), :54-78 (published, supported, superseded, frozen, epoch), :80-86 (retention), :88-101 (what a signature attests and does not), :155-170 (bypass posture), :172-185 (reporting channel), :187-191 (advisory channel), :193-203 (revocation record and runbook), :205-222 (authenticity class for all seven definitions under image/), :224-234 (Rekor fact), :236-254 (terms with dated evidence data/dhi-terms-2026-08-21.md), :256-266 (status issue link) | Every element present. No mechanism keeps it current; three stale facts are document findings r9.14 to r9.16. |
| 9.2 | OWNER-SIDE | Live repository setting. Daily check: scripts/check-governance.sh:141-150, run by rescan.yml:914-937 (step "posture invariants") | Ledger docs/live-evidence.md:219 records a drill report (GHSA-6xgw-5wvx-p8xx, 2026-11-05). |
| 9.3 | HELD | rescan.yml:29-31 (daily cron), :914-919 (`if: always()`, `rc` from check-governance.sh), :937 (`exit "$rc"`); check-governance.sh:142-150 (disabled and unreadable both `error()`), :213 (exit 1 on any failure) | Anonymous read; a rate limit waits up to 3900 s twice, then fails by name (:76-99). |
| 9.4 | OWNER-SIDE | Live GitHub advisories. No daily check. Partial file evidence: triage/revocations.schema.yaml:12,21 force each revocation's `advisory` to a GitHub GHSA URL shape (any owner/repo, not pinned to this repository) | Ledger :221 records GHSA-mxcv-w9jx-vj6j published 2026-11-07. |
| 9.5 | HELD | triage/revocations.yaml:16-31 (one entry, drill 16.12); schema triage/revocations.schema.yaml:4-21 requires image, digest, reason, replacement digest or `none` plus `withdrawal`, advisory, date | Completeness of the record (every revoked digest) is by hand (register M14). `tombstone` digest not required when `withdrawal: tombstone` (r9.19, outside the criterion's field list). |
| 9.6 | HELD | validate.yml:37-38 `yamale -s triage/revocations.schema.yaml triage/revocations.yaml`; probe: advisory `none` and date `soon` fail with `revocations.0.advisory: 'none' is not a regex match`, `revocations.0.date: 'soon' is not a day`, exit 1; missing reason fails `Required field missing` | Names land in the step log, not as annotations (ledger :223 says so). The step is skipped when an earlier step of the job fails, but the job is red either way. |
| 9.7 | PARTIAL | rescan.yml:920-926 (posture step; refuses by name without an enumeration), check-revocations.sh:40-66 (index and platform-manifest match, one ::error:: per tag, exit 1) | The enumeration reads only repositories of definitions present under image/ (enumerate-catalogue.sh:57); a tag in the repository of a definition since deleted is never compared, though the record names that repository (`image:`). r9.1. |
| 9.8 | HELD | .github/rulesets/main_sec.json:1-95, GitHub export shape (id, source, bypass_actors), target branch, `required_status_checks` containing "build gate" (build.yml:1247-1263) and "e2e gate" (e2e.yml:280-294) | Holds today; nothing checks that the committed file keeps requiring the gates (r9.10). |
| 9.9 | HELD | check-governance.sh:63 (compared fields), :152-204 (by name, both directions, active branch live-only), :101-128 (canonicalisation), :70-75 anonymous request; rescan.yml:914-937 | `GET repos/{repo}/rulesets` is read without `per_page`/pagination (:161), so a live ruleset past the first page (30) would be missed; not reachable with today's one ruleset. |
| 9.10 | HELD | CODEOWNERS:6-10 (triage/, image/, chart/, policies/, .github/) | Static file. |
| 9.11 | HELD | catalogue-policy.yaml:238-244; triage-policy.sh:120-155 refuses a list without exactly one authoritative (:136), non-boolean flags, duplicates; scripts/vex-consumer.sh:10-13, :111-148 one normalised shape (vulnerability, purl/key, suppressed) per consumer | Exactly-one is enforced when a workflow reads the list (build, rescan), not by a validate step over the committed file. |
| 9.12 | PARTIAL | PR: build.yml:737-759; rescan: rescan.yml:496-533; block: vex-portability.sh:74-147 | A PR whose authoritative normalisation fails gets no block and a green job; the rescan drops a manifest from the block when the authoritative normalisation fails and masks a failed vex-portability.sh. r9.2, r9.3. |
| 9.13 | PARTIAL | rescan.yml:543-560 (daily, one supported full-release digest), consumer-smoke.sh:61-105 (extract and run), :107-176 (authoritative suppressions; missing fails), :194-204 (other consumers into a portability block), :218 (exit 1 on failed step, missing suppression, unmeasured) | Not verbatim: each step runs under `bash -o pipefail` (consumer-smoke.sh:98) in its own shell, logged in to ghcr.io (rescan.yml:106-111). The published recipe a consumer runs exits 0 when the SBOM or VEX check fails. r9.4. |
| 9.14 | PARTIAL | docs/CONVENTIONS.md:461-499, every row with step, class, reason, fork switch | Two human steps the repository itself names are not rows: keeping main_sec.json's required checks right (docs/lanes.md:960, "a person keeps it in line") and redrawing a lane in its pull request (design.md:1202-1203, "review hold it, not a lint"). r9.5. |
| 9.15 | PARTIAL | docs/user-manual.md:1611-1636 | "Every component": the CISA KEV feed, the FIRST EPSS API, the Trivy and Grype vulnerability databases, third-party Actions, lychee, vexctl, yamllint/yamale and the kind node image have no row. r9.6. |
| 9.16 | HELD | NOTICE:4-11 (DHI copyright and Apache-2.0), LICENSES/Apache-2.0.txt, NOTICE:21-28 (third-party licences in attested SBOMs) | Static. |
| 9.17 | HELD | README.md:29-30 | Static. |
| 9.18 | PARTIAL | Exceptions: validate.yml:79-80 → lint-accepted-risk.sh:222-225 → lint-log-anchors.sh refs; statements: validate.yml:197-198 → lint-log-anchors.sh:103-127. Probes: a bad `ref` and a bad statement citation both exit 1 naming file and citation | lint-log-anchors.sh:47-55 reads every `#` line of LOG.md as a heading, including lines inside fenced code blocks; probe: a citation to `## fake fenced heading` inside a fence passes (exit 0). No such line in today's LOG. r9.7. |
| 9.19 | PARTIAL | SECURITY.md:103-153: level L1, SLSA v1.2, digests since 2026-09-01, verification by the recipe's provenance step | The claimed L1 rests on BuildKit provenance that the verification policy does not demand (policies/verify-catalogue-images.yaml:36-45 demand SPDX and OpenVEX only). The verification steps described are for the L2-grade statement, not for the claimed L1. r9.8. |
| 9.20 | HELD | validate.yml:53-59, lychee offline with `--include-fragments` over `git ls-files '*.md'`, `set -euo pipefail` | Not run here (lychee absent locally); ledger :237 records drill run 44803253992. No absolute self-URLs to repository files in tracked Markdown, so offline mode skips no in-repo link. |
| 9.21 | PARTIAL | docs/lanes.md (31 Mermaid graphs, lane map :9-24), linked from README.md:40 | 52 of 147 step-table rows name no design decision (e.g. lanes.md:70, :255, :964) and 2 name no criterion (:118, :959). The "change the diagram in the pull request that changes the lane" clause has no mechanism (design.md:1202-1203). r9.9. |

### Index: reader finding to F number

r1.1: F5; r1.2: F6; r1.3: F7; r1.4: F39; r1.5: F40; r1.6: F5; r1.7: F6; r1.8: F41; r1.9: F42; r1.10: F43; r1.11: F7; r2.1: F1; r2.2: F8; r2.3: F9; r2.4: F10; r2.5: F44; r2.6: F45; r2.7: F46; r2.8: F11; r2.9: F47; r2.10: F48; r2.11: F49; r2.12: F50; r2.13: F51; r2.14: F52; r2.15: F53; r2.16: F1; r3.1: F12; r3.2: F13; r3.3: F14; r3.4: F54; r3.5: F12; r3.6: F13; r3.7: F14; r3.8: F55; r4.1: F15; r4.2: F56; r4.3: F16; r4.4: F57; r4.5: F17; r4.6: F58; r4.7: F57; r4.8: F17; r4.9: F16; r4.10: dropped (refuted); r4.11: F59; r4.12: F60; r5.1: F2; r5.2: F61; r5.3: F39; r5.4: F2; r5.5: F62; r5.6: F63; r5.7: F61; r6a.1: F9, F18, F19, F26, F70; r6a.2: F64; r6a.3: F20; r6a.4: F65; r6a.5: F21; r6a.6: F22; r6a.7: F66; r6a.8: F67; r6a.9: F23; r6a.10: F68; r6a.11: F73; r6a.12: F74; r6a.13: F23; r6a.14: F75; r6a.15: F76; r6a.16: F77; r6a.17: F78; r6a.18: F21; r6a.19: F79; r6a.20: F9; r6a.21: F19; r6b.1: F1; r6b.2: F3; r6b.3: F4; r6b.4: F9; r6b.5: F24; r6b.6: F26; r6b.7: F19; r6b.8: F27; r6b.9: F69; r6b.10: F25; r6b.11: F47; r6b.12: F70; r6b.13: F71; r6b.14: F72; r6b.15: F75; r6b.16: F9; r6b.17: F80; r6b.18: F79; r6b.19: F81; r7.1: F82; r7.2: F28; r7.3: F83; r7.4: F84; r7.5: F29; r7.6: F30; r7.7: F12; r7.8: F85; r7.9: F86; r7.10: F31; r7.11: F54; r7.12: F30; r7.13: F12; r7.14: F87; r7.15: F43; r7.16: F88; r7.17: F31; r7.18: F83; r9.1: F8; r9.2: F33; r9.3: F33; r9.4: F11; r9.5: F35; r9.6: F36; r9.7: F89; r9.8: F37; r9.9: F38; r9.10: F32; r9.11: F34; r9.12: F90; r9.13: F53; r9.14: F91; r9.15: F91; r9.16: F92; r9.17: F93; r9.18: F33; r9.19: F94.
