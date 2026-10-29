# Track registry

| Symbol | Status |
| --- | --- |
| `[ ]` | pending |
| `[~]` | in progress |
| `[x]` | completed |

## Active tracks

_No active track._

## Completed tracks

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
