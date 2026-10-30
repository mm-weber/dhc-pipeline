# Track specification: The drill's HIGH brought back, the closed issue reopened on the lapse, live

## Overview

**Track ID:** drill-regression_20261029
**Type:** chore
**Priority:** high (the live program; the last drill on the drill definition's findings before its retirement)
**Created:** 2026-10-29
**Author:** the owner, drafted by the agent
**Spec source:** `.specs/dhc-catalogue-mvp/tasks.md` task 16.7 (task group 16, the live drills), its text amended by this track's pull request; Req 6.57 (a closed cve issue whose finding is reported again on a supported digest is reopened), 6.46 (the clocks, first seen carried forward), 7.11 (the ledger); design Decision 13

### Description

Task 16.6 fixed the drill definition's two findings in the fetch phase and the rescan closed CVE-2025-30204's issue #325 as `resolved:fixed` on the attested SBOMs (#344, 2026-10-29). No fixed finding has ever returned to this catalogue, so the lifecycle's reopen (Req 6.57) has never run: ledger row 6.57 waits for this drill. The task text brings the vulnerable module back "as a new release" and watches the issue reopen with its original first-seen date.

The way back matters. A regression is a pull request that builds the definition with the vulnerable module again, and the pull request gate refuses an uncovered finding by name (Req 6.1); merging over it would be a second bypass of the program, and no maintainer regresses a catalogue that way. The maintainer's move when a vulnerable module must ship for a while is a bounded acceptance (Req 6.7), so this drill takes it: the regression pull request removes `github.com/golang-jwt/jwt/v5` from the bump step (the CRITICAL's bump stays) and accepts CVE-2025-30204 for one day, decided 2026-10-29 and expiring 2026-10-30, the entry's reasoning in the LOG as every decision. The gate is green by the exception, main releases the regressed digest with an `affected` statement, and from midnight UTC on 2026-10-30 Trivy drops the entry (the first clock of task 16.4): the scheduled rescan of that day lists the finding as reported in the supported digest's attested report, and the lifecycle reopens #325 by name (Req 6.57), the status carrying first seen 2026-10-18 (Req 6.46). The evidence pull request removes the lapsed entry the same day, before the lint's second clock turns validation red; the finding stays undecided and leaves with the definition in task 16.16.

### The mechanism, as read on 2026-10-29

`lifecycle.go` (Req 6.52 to 6.57): a closed cve issue reopens when its finding is reported again, within the aperture, on a supported digest; the comment reads `Reopened by the rescan (Req 6.57): <id> is reported again on a supported digest.`, names where and the scanner, and the stale resolved label is removed; a reopen needs only the positive evidence. `status.go`: a finding present today takes the earlier of today's first-seen time and the previously published one, so the row returns as undecided with first seen 2026-10-18 and its age counted from there, the fixed date gone from that row. Trivy drops an ignore entry once its `expired_at`, read as midnight UTC, is before now (`pkg/result/ignore.go`, `Prune`); this repository's lint and compiler keep it live through the expiry day, so on 2026-10-30 validation still warns (`0 days`) and the compiler's recompile publishes `under_investigation` with the generic note, as on task 16.4's first day; on 2026-10-31 the lint would refuse every pull request, which the evidence pull request pre-empts by removing the entry on 2026-10-30. `lint-accepted-risk.sh` holds the entry to the lane's shape (treatment, owner, ref to a LOG heading, blocked, statement, dates within the largest ceiling) and `lint-log-anchors.sh refs` holds its `ref` to a real heading, so the LOG decision lands in the regression pull request itself (the shape of #319).

## Functional requirements (EARS)

The subject names follow design.md: the Repository, the CI Pipeline (`build.yml`), the Scan Pipeline (`rescan.yml`), the owner.

### FR-1: The regression, accepted for a day (Req 6.5, 6.7)

THE Repository SHALL remove `github.com/golang-jwt/jwt/v5` from the drill definition's bump step (the `gorilla/handlers` bump kept), add an accepted-risk entry for CVE-2025-30204 to `triage/accepted-risk/drill-app.yaml` (treatment accept, owner, `ref` to this entry's LOG heading, blocked, statement, `decided_at` 2026-10-29, `expired_at` 2026-10-30) and the LOG entry's decision, in one pull request whose build of drill-app is green at the scan gate by the exception, with govulncheck reaching `ParseUnverified` again; the owner SHALL merge it.

**Acceptance criteria:**

- [x] #348, squash ec90a95; build run 40974710663 green at the gate, the tier step green, govulncheck naming `ParseUnverified`; validate green with the `expires in 1 days` warning

### FR-2: The release (Req 2.9, 6.38)

WHEN the regression merges THE CI Pipeline SHALL release a new drill-app digest whose attested OpenVEX document carries an `affected` statement for CVE-2025-30204 from the exception and no statement for CVE-2017-20146, the SBOMs listing `github.com/golang-jwt/jwt/v5 v5.2.1` and `github.com/gorilla/handlers v1.3.0`, the tags moved.

**Acceptance criteria:**

- [x] Run 40975473407; `sha256:d5d9bb51146f8dc60bc0c5fc44166a2b266484c75c2b3363dfc44e7dad771fa4`, the three tags on it; one `affected` statement (action statement timestamp 2026-10-29); the SBOMs with v5.2.1 and v1.3.0

### FR-3: The reopen (Req 6.57, 6.46)

WHEN the scheduled rescan runs on 2026-10-30 THE Scan Pipeline SHALL list CVE-2025-30204 as a reported finding in the supported digest's attested report (the entry dropped by Trivy at midnight UTC), SHALL reopen #325 with the comment naming the digest and the scanner, removing `resolved:fixed`, and SHALL publish the status with the finding undecided, first seen 2026-10-18, age counted from there.

Notes: the first clock of task 16.4; a dispatch after midnight UTC would do the same earlier (register row M17, the owner's call). The lifecycle runs before the issue reporter, so no second issue is filed.

**Acceptance criteria:**

- [x] Run 41060449312; `Reopened by the rescan (Req 6.57): CVE-2025-30204 is reported again on a supported digest.`; `resolved:fixed` removed; `drill-app | CVE-2025-30204 | HIGH | no | undecided | 2026-10-18 | n/a | 12 / 90 | undecided, awaiting a triage decision`; the card `CRITICAL 0 · HIGH 1; undecided 1, over ceiling 0; fixed 2`

### FR-4: The entry leaves (Req 6.11)

THE Repository SHALL remove the lapsed entry from `triage/accepted-risk/drill-app.yaml` in the evidence pull request on 2026-10-30, the lane left empty for task 16.16, validation green; the finding SHALL stay undecided.

**Acceptance criteria:**

- [x] `scripts/lint-accepted-risk.sh .` green with no warning; `scripts/lint-log-anchors.sh all .` green, nine refs. Not foreseen here: the pull request builds drill-app (a changed exception file names its image, Req 6.9) and its scan gate is red on the uncovered finding (run 41063600623); the merge is the owner's bypass, as for #329

### FR-5: The evidence (Req 7.11)

THE Repository SHALL flip ledger row 6.57 to `exercised` with the run id (inducer `drill definition`), append the drill's observation to row 6.46, add the task table row for 16.7, add the LOG entry's second part under `## 2026-10-29: the drill's HIGH brought back for a day, the issue reopened on the lapse (task 16.7)`, tick task 16.7, move `tasks/todo.md` to 16.11 and close this track, in the evidence pull request opened once FR-3's run is read.

**Acceptance criteria:**

- [x] `scripts/lint-live-evidence.sh .` green with 142 exercised; `scripts/lint-log-anchors.sh all .` green; the tick `[done 2026-10-30, #351; conductor track drill-regression_20261029]`; `conductor/tracks.md` lists the track under Completed; 16.11 next in `tasks/todo.md`

## Scope

### In scope

- One regression pull request (FR-1) with the decision; the release it triggers (FR-2); the scheduled rescan of 2026-10-30 (FR-3)
- One evidence pull request (FR-4, FR-5)
- The amendment of task 16.7's text in this pull request

### Out of scope

- Any change to the lifecycle, the status tool, the compiler or the workflows: the drill reads what they do; a defect found is recorded with a follow-up task, not fixed here
- The CRITICAL: it stays fixed; one finding comes back, one issue reopens
- A second fix: the finding stays undecided and leaves with the definition (task 16.16)

## Dependencies

| Dependency | Type | Status | Notes |
| --- | --- | --- | --- |
| The fix and the closed issue (task 16.6) | track | done 2026-10-29 (#344, 7926a01) | #325 closed `resolved:fixed` |
| The lapse mechanism (task 16.4) | track | done 2026-10-27 (#329) | Trivy's midnight clock, the lint's day after |
| The task text amended (16.7) | spec | in this pull request | One module, a one-day acceptance instead of a bypass, the reopen on the lapse day |

## Risks

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The scheduled run of 2026-10-30 lands late in the day | expected (11:00 to 13:30 UTC these last days) | the evidence pull request opens that afternoon | The entry is removed the same day either way; validation is red only from 2026-10-31 |
| The lifecycle files a new issue instead of reopening | low (the marker identity matches #325; the reopen branch is tested) | a second issue for the same finding | Read and recorded; the follow-up would be a defect row |
| The status row carries no first-seen date from the fixed row | low (`earlier` keeps the published one) | the age restarts | Read and recorded; a defect row if so |

## Open questions (the owner's calls)

- [x] The acceptance (the owner's call by merging #347 and #348)
- [x] The scheduled run (41060449312), which started at 13:06Z before any dispatch
- [x] Left undecided, its issue open, until 16.16

## References

- `.specs/dhc-catalogue-mvp/requirements.md` Req 2.9, 6.1, 6.5, 6.7, 6.11, 6.38, 6.46, 6.52, 6.57, 7.11; `tasks.md` 16.7, 16.16
- `triage/rescan/lifecycle.go` (the reopen), `triage/rescan/status.go` (first seen carried), `scripts/lint-accepted-risk.sh`, `scripts/lint-log-anchors.sh`, `image/drill-app/image.yaml` (the bump step), `triage/accepted-risk/drill-app.yaml`
- LOG 2026-10-18 (the drill's findings decided), 2026-10-26 (the lapse on every plane), 2026-10-28 (the fix); tracks `exception-lapse_20261025`, `drill-fix_20261028`
