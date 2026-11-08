# Track registry

| Symbol | Status |
| --- | --- |
| `[ ]` | pending |
| `[~]` | in progress |
| `[x]` | completed |

## Active tracks

_No active track._

## Completed tracks

### [x] retirement_20261107: The drill definition retired, the drill program closed, the ledger complete

**Description:** The drill definition retired at level 2 of the retirement table: its active-set line, proofs entry, directory and empty lane removed in one pull request with the live-state case moved to six, test-first; the record completed (the LOG entry, the eight drill entries given their findings paragraph, the README and manual rows, the ledger complete); the upstream repository archived by the owner; the first dispatched rescan after read for the issues closing on evidence and the definition leaving the status; task group 16 closed.
**Priority:** high (the live program's last task; a scheduled rebuild republishes the withdrawn definition every day until this merges)
**Completed:** 2026-11-08 (#377 merged as ea59ee1, the track; #378 the retirement, merged as b90900f; the upstream archived 08:07Z; the dispatched rescan after read; the evidence in #379; task group 16 complete)
**Folder:** [./tracks/retirement_20261107/](./tracks/retirement_20261107/)

### [x] revocation_20261105: A revocation, its advisory and the runbook, the drill digest withdrawn, live

**Description:** The drill definition's current digest recorded as revoked with reason drill while its three tags still reference it (a withdrawal, Move B1, the one entry the schema admits before the move), the advisory drafted first, the dispatched rescan red at the posture step naming the three tags, the package version deleted by the owner, the next dispatched rescan green with the entry listed, the advisory published or kept at the owner's call; ledger rows 9.4, 9.5 and 9.7 exercised.
**Priority:** high (the live program; the last three drill rows)
**Completed:** 2026-11-07 (#371 merged as 62918cf, the track; the advisory GHSA-mxcv-w9jx-vj6j drafted; #374 the entry, merged while the three tags still referenced the digest; the dispatched rescan 42130207670 and the scheduled rescan 42233459314 red at the posture step by name; the version deleted by the owner on 2026-11-07; the dispatched rescan 42362729195 green with the entry listed; the evidence in #376: rows 9.4, 9.5 and 9.7 exercised)
**Folder:** [./tracks/revocation_20261105/](./tracks/revocation_20261105/)

### [x] private-report_20261031: A report through the private channel, handled as the policy promises, live

**Description:** One private vulnerability report filed by the owner, titled as a drill, received through the channel SECURITY.md names, acknowledged, examined against the catalogue's records, answered and closed as a drill, the elapsed times recorded against no promised window; ledger row 9.2 exercised.
**Priority:** high (the live program; runs beside the switches drill, no scheduled run involved)
**Completed:** 2026-11-05 (#358 merged as dcda06f, the track; the owner's own attempt refused with 403 on 2026-11-02; the report GHSA-6xgw-5wvx-p8xx filed from a non-collaborator account at 13:29Z, acknowledged 13:55Z, answered and closed as a drill 13:59Z, nothing published; the evidence in #370: row 9.2 exercised)
**Folder:** [./tracks/private-report_20261031/](./tracks/private-report_20261031/)

### [x] auth-mismatch_20261105: A true authenticity mismatch, the drill definition's tag moved by its maintainer, live

**Description:** The drill definition's pinned tag moved by its maintainer to an unsigned commit, the daily re-verification reporting the first true mismatch by name and filing the supply-chain issue, the owner deciding what the signal means (M18) and restoring the original tag object, the rescan verifying again, the issue closed with the reason; ledger row 3.10 exercised, 3.13 kept with its reason.
**Priority:** high (the live program; the one row that needs an upstream signal to move)
**Completed:** 2026-11-05 (#367 merged as ec04bfd, the track; the owner's tag move at 10:29Z and restore at 10:54Z; the dispatched rescans 42011386908, red at the authenticity step and filing #368, and 42014582733, green; #368 closed by the owner with the decision; the evidence in #369: row 3.10 exercised, 3.13 kept)
**Folder:** [./tracks/auth-mismatch_20261105/](./tracks/auth-mismatch_20261105/)

### [x] switches_20261030: The switches, one run each: the page off, every rebuild published, live

**Description:** Two declared switches flipped for one day through one pull request and flipped back through another: `release.publish_policy` always, so the scheduled rebuild publishes every active definition whatever the comparator says (seven releases, the chart digest pull request following), and `release.page` false, so the scheduled rescan skips the page and the served page keeps the previous day's data; Req 6.62's failure branch by the owner disabling Pages for one run, their call.
**Priority:** high (the live program; two rows no other drill reaches)
**Completed:** 2026-11-03 (#356 merged as c0177f6, the track; #357 the flip, 438d456; the scheduled rebuild 41302227631 of 2026-11-01 publishing all seven active definitions and the scheduled rescan 41311884446 skipping the page; #359 the revert, 2338535; Renovate's digest pull requests #360, #361 and #362 automerged on 2026-11-03 once the e2e gate was repaired; the evidence in #365: rows 2.17 and 6.62 exercised, the latter by the owner's Pages action around two dispatched rescans of 2026-11-04; 2.15, 3.12 and 6.61 appended)
**Folder:** [./tracks/switches_20261030/](./tracks/switches_20261030/)

### [x] active-set-entry_20261030: The drill definition's directory removed, its active-set entry refused by name, live

**Description:** The drill definition's directory removed on a drill branch never merged while its active-set entry stays: validation refuses the entry by name (Req 1.19, the one refusal of task 16.11 nobody had seen live), read in two commits so that the lane's own guard and the active-set line are both recorded; ledger row 1.19 exercised.
**Priority:** high (the live program; no clock, no switch)
**Completed:** 2026-10-30 (#353 merged as af626ea, the track; the drill pull request #354, never merged, two commits refused by name, the first by the accepted-risk lint on the missing definition, the second at the active-set step with the Req 1.19 line; the evidence in #355: row 1.19 exercised)
**Folder:** [./tracks/active-set-entry_20261030/](./tracks/active-set-entry_20261030/)

---

### [x] drill-regression_20261029: The drill's HIGH brought back, the closed issue reopened on the lapse, live

**Description:** The drill definition's HIGH brought back by removing its bump, accepted for one day rather than merged over the red gate, released with an `affected` statement; from midnight UTC Trivy drops the entry, the scheduled rescan lists the finding as reported again and reopens its closed issue #325 by name, the status carrying first seen 2026-10-18; the lapsed entry removed the same day, the finding undecided until the definition retires.
**Priority:** high (the live program; the last drill on the drill definition's findings)
**Completed:** 2026-10-30 (#347 merged as c0c8850, the track; #348 as ec90a95, the regression under a one-day acceptance, released 2026-10-29 23:55Z with an `affected` statement; the scheduled run 41060449312 of 2026-10-30 reopening #325 by name once Trivy dropped the lapsed entry, first seen 2026-10-18 carried; the evidence in #351 with the entry removed, the finding undecided until 16.16)
**Folder:** [./tracks/drill-regression_20261029/](./tracks/drill-regression_20261029/)

---

### [x] drill-fix_20261028: The drill's findings fixed, the issue closed on the attested SBOMs, the fix clock, live

**Description:** The drill definition's two findings fixed by a `go/bump@v2` step in its fetch phase (the catalogue's fix lane, M10): the pull request green at the gate by the fix, the release on main, the next scheduled rescan closing issue #325 as `resolved:fixed` on the attested SBOMs and publishing both findings as fixed with their fix times, the CRITICAL's exception retired as moot. The way out the fail-closed gate named, and the fixed finding drill 16.7 brings back.
**Priority:** high (the live program; 16.7 needs a fixed finding)
**Completed:** 2026-10-28 (#341 merged as a403884, the track; #342 as 57ebed4, the bump, green at the gate by the fix; main's release 40769247657 to `sha256:5cacd03bc770...` with no statement and the fixed versions in the SBOMs; the owner's dispatch 40788144199 closing #325 `resolved:fixed` and publishing both findings fixed 10 days after first seen; the evidence in #344 with the CRITICAL's exception retired as moot)
**Folder:** [./tracks/drill-fix_20261028/](./tracks/drill-fix_20261028/)

---

### [x] fail-closed-release_20261027: The fail-closed release gate refuses a release, the digest frozen, live

**Description:** The fail-closed release switch turned on for one dispatched build of the drill definition, whose HIGH is uncovered since task 16.4: the release-time scan names the finding per platform manifest, the gate signs, attests and tags nothing, the pushed digest stays frozen and pullable by digest, the next scheduled rescan neither enumerates nor re-attests it; the switch back off the same day unless the owner keeps it; the way out is drill 16.6's fix.
**Priority:** high (the live program; possible today, before 16.6 fixes the finding)
**Completed:** 2026-10-28 (#333 merged as 06c9b6e, the track and the task text's amendment; #334 as 8ea59f4, the switch on; the owner's dispatch 40691384018 refused at the fail-closed release gate by name, the digest `sha256:925dd22c2ead...` frozen, pullable by digest, unsigned, unattested, untagged; #335 the switch off the same day; the evidence in #336: rows 2.11 and 2.13 exercised; a first dispatch before the switch released the definition instead, recorded)
**Folder:** [./tracks/fail-closed-release_20261027/](./tracks/fail-closed-release_20261027/)

---

### [x] over-ceiling_20261027: An undecided finding past its ceiling, the alarm raised and cleared, live

**Description:** The drill definition's undecided HIGH, ten days old, put over its ceiling for one rescan: `triage.kev_ceiling` lowered to one day in one pull request, the owner's dispatch with `drill: kev-synthetic` listing the finding, the status issue and the page publishing over ceiling: 1 with the row marked (the first live over-ceiling flag), the value restored the same day, the next scheduled run clearing the alarm on the declared feed. The HIGH ceiling the task text named cannot go under 60 days: `triage.ceilings` also tiers every standing exception and bounds the lint, and grafana's nine transfers run 60 days.
**Priority:** high (the next drill of the live program; 16.6 fixes the finding after it)
**Completed:** 2026-10-28 (#330 merged 2026-10-27 as 0d3eae5, the track and the task text's amendment; #331 as 16727ab, `kev_ceiling` to one day; the owner's dispatch 40578319282 with `drill: kev-synthetic`: the finding listed, `9 / 1`, `over ceiling: 1` on the status issue and the page, the row and the card marked, the run green; #332 as ebd0f65, the value restored the same day; the scheduled run 40693681245 of 2026-10-28 clearing it on CISA's feed; the evidence in #339: rows 6.46, 6.47 and 6.49 re-observed, the follow-up item on the three readers of `triage.ceilings`)
**Folder:** [./tracks/over-ceiling_20261027/](./tracks/over-ceiling_20261027/)

---

### [x] exception-lapse_20261025: The drill's exception expires, the lapse seen on every plane, live

**Description:** The drill definition's HIGH exception, re-decided to one day by task 16.3, expires on 2026-10-26: Trivy counts the finding again from midnight UTC, the rescan recompiles and re-attests the document with the finding `under_investigation` and its first-seen time carried, the status shows it undecided, a cve issue is filed, the gate on a drill pull request refuses the finding as uncovered, and on the second day the lint reports the entry as past and the compiler names the lapse; the entry is then removed for task 16.5; ledger rows 6.9, 6.10 and 6.41 filled (Req 6.9, 6.10, 6.41, 7.11; task 16.4).
**Priority:** high (the next drill of the live program; 16.5 needs the finding undecided)
**Completed:** 2026-10-27 (#321 merged 2026-10-25 as a9c55bb, the track and the task text's amendment; the scheduled run 40328859055 of 2026-10-26: Trivy counting the finding again, the document re-attested under_investigation, the status undecided, issue #325 filed, the expiries step at 0 days, the page lapsing; the drill pull request #324, red at the scan gate by name, never merged, validate red on it from day two; the scheduled run 40503212074 of 2026-10-27: the lint's `is in the past`, the page lapsed, the compiler's lapse note in the attested document; the evidence in #329: rows 6.9, 6.10 and 6.41 exercised, the lapsed entry removed, the finding undecided for 16.5)
**Folder:** [./tracks/exception-lapse_20261025/](./tracks/exception-lapse_20261025/)

---

### [x] deliberate-violations_20261025: Deliberate violations, one pull request, every lint refuses by name, live

**Description:** One drill pull request, never merged, twenty-one commits each carrying one deliberate violation of a codified convention and undoing the previous one, so that every lint and gate that has never refused anything live refuses by name: the pin lint, the active set, the compat clock, the proof lint, the accepted-risk lane, the VEX product lint, the LOG anchors, the rendering drift check, the workflow policy, the revocation schema, the kyverno gate; fifteen ledger rows filled, four re-observed (Req 7.4, 7.11; task 16.15).
**Priority:** high (the owner's call of 2026-10-25; no clock involved)
**Completed:** 2026-10-26 (#322 merged 2026-10-25 as c1c8aa6, the track; the drill pull request #323, thirty commits, every one red by name, never merged; the evidence in #326: rows 1.6, 1.11, 1.12, 1.18, 4.8, 5.8, 5.10, 6.11, 6.12, 6.19, 6.25, 6.39, 7.10, 9.6 and 9.18 exercised, 4.2, 4.3, 4.6 and 7.9 re-observed)
**Folder:** [./tracks/deliberate-violations_20261025/](./tracks/deliberate-violations_20261025/)

---

### [x] kev-ceiling_20261024: The KEV ceiling on a standing exception, both arms refuse by name, live

**Description:** The drill definition's HIGH enters the KEV set through the `kev-synthetic` drill input and its standing 90-day exception is refused by both arms by name: the rescan on a dispatch (Req 6.51, the run red and publishing with KEV yes), the gate on the drill pull request's first commit (Req 6.50); the same pull request re-decides the exception to one day from its decision date, within the KEV tier and the window drill 16.4 watches lapse, and merges; a second dispatch shows the pass; ledger rows 6.50 and 6.51 filled (Req 6.46, 6.50, 6.51, 7.11; task 16.3)
**Priority:** high (the next drill of the live program; 16.4 and 16.5 build on its exception)
**Completed:** 2026-10-25 (#318 merged as a764a23, the track and the amendment, revised to one day before the merge; #319 merged as 714614f, the drill: the owner's dispatch 40187973579 red by name on the standing exception and publishing with KEV yes, build run 40188092683 red by name at the gate, the re-decision to one day; the pass on the owner's dispatch 40191153604 and the closure in #320; rows 6.50 and 6.51 exercised)
**Folder:** [./tracks/kev-ceiling_20261024/](./tracks/kev-ceiling_20261024/)

---

### [x] kev-drill-input_20261023: The KEV drill input, a feed outage fails closed in both arms, live

**Description:** A `drill` input on `rescan.yml`'s dispatch substitutes a declared value for the KEV feed for one run (`kev-outage`: an address under `.invalid` that never resolves; `kev-synthetic`: a feed of this repository naming the drill definition's HIGH, for task 16.3), the policy lint holds the input's allowed values beside the crons and the permissions, and both fail-closed branches run live for the first time: the gate on a drill branch never merged, the rescan on a dispatched run that is red by name and publishes attestations only; the ledger rows 6.59 and 6.60 filled (Req 6.59, 6.60, 7.7, 7.10, 7.11; task 16.8).
**Priority:** high (the next drill of the live program; 16.3 depends on it)
**Completed:** 2026-10-24 (#308 merged 2026-10-23 as a5decb6, the spec amendment and the track; #310 merged 2026-10-23 as 9e62294, the input, the declarations, the lint, the reader; the drill observed in #314: the gate's half red on #313, never merged, build runs 40021724071 and 40021765400; the dispatched run 40024066594 red by name, the status and the page withheld; the scheduled run 40088952931 green with the status and the page published; rows 6.59 and 6.60 exercised)
**Folder:** [./tracks/kev-drill-input_20261023/](./tracks/kev-drill-input_20261023/)

---

### [x] retire-grafana_20261019: Grafana deactivated, the documented switch exercised live

**Description:** Grafana's line leaves the active set and nothing else changes under its directory or chart: no new build, tag, bump or e2e install, everything published kept with its attestations and daily planes; the switch, never exercised live, flips the ledger's 1.15 and 1.16 rows by nature; the twelve moot exceptions of 2026-09-03 retired with their evidence in the same pull request (Req 1.13 to 1.16, 3.2, 6.7, 6.11, 7.11). The four levels of retiring an image are kept in the spec.
**Priority:** high (the owner's call of 2026-10-19)
**Completed:** 2026-10-20 (#290 merged 2026-10-19 as 04c6eeb, the switch and the twelve exceptions retired; the first inactive day observed in #292 and #295: no grafana job in four builds, the rescan's first non-empty inactive check, run 39417467219; rows 1.15 and 1.16 exercised)
**Folder:** [./tracks/retire-grafana_20261019/](./tracks/retire-grafana_20261019/)

---

### [x] drill-definition_20261017: The drill definition and its first findings (task 16.2)

**Description:** drill-app, the owner's purposely vulnerable copy of hardened-app, joins the catalogue as pull request 1 of the onboarding flow with the catalogue's first declared none proof; the scan gate names its two findings, the owner decides them one at a time, main publishes the first digest, and the evidence lands in the ledger and the LOG (spec task 16.2; Req 1.13, 1.14, 5.9, 6.1, 6.3, 6.13, 7.11, 9.11). The first track of the live-drill program; one track per drill from here.
**Priority:** high (the first live drill; unblocked by the proof-kinds track on 2026-10-17)
**Completed:** 2026-10-19 (#286 merged 2026-10-18 as 1b941ea with the definition and the two decisions; the evidence pull request closes the track)
**Folder:** [./tracks/drill-definition_20261017/](./tracks/drill-definition_20261017/)

---

### [x] proof-kinds_20261015: Proof kinds per definition

**Description:** The functional proof declared per definition in the policy file; the chart probe stays the default; a `none` with a reason is admitted, reported by name on every run and refused when malformed or when a chart deploys the definition (spec task group 17: 17.2 reader, 17.3 lint, 17.4 docs; the review-by date dropped 2026-10-16).
**Priority:** high (unblocks drill 16.2)
**Completed:** 2026-10-17 (#273 reader, #281 lint, #282 docs merged by squash; spec #271, context #272)
**Folder:** [./tracks/proof-kinds_20261015/](./tracks/proof-kinds_20261015/)

---

## Archived tracks

| Track ID | Type | Reason | Archived | Folder |
| --- | --- | --- | --- | --- |
