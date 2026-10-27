# Implementation plan: The drill's exception expires, the lapse seen on every plane, live

**Track ID:** exception-lapse_20261025
**Spec:** [spec.md](./spec.md)
**Created:** 2026-10-25
**Status:** [x] completed (phase 0 in #321, merged 2026-10-25 as a9c55bb; phase 1 the two days, 2026-10-26 and 2026-10-27, and the drill pull request #324; phase 2 the evidence in #329, 2026-10-27)

## Overview

Three phases, three pull requests, no code, no dispatch required. Phase 0 is this pull request: the track and the amendment of task 16.4's text; the owner confirms by merging. Phase 1 is the two days: the scheduled run of 2026-10-26 (Trivy counts the finding, the document recompiled and re-attested, the status undecided, the issue filed, the expiries step at 0 days), the drill pull request that day (the gate red by name), the scheduled run of 2026-10-27 (the lint's `is in the past`, the page's lapsed entry, the compiler's lapse note). Phase 2 is the evidence pull request on 2026-10-27, which also removes the lapsed entry so that validation is green again, and the hand-over to 16.5. In the owner's clock (PDT): the first day begins at 17:00 on 2026-10-25, the second at 17:00 on 2026-10-26; the scheduled runs land about 04:15 to 05:00 the next morning.

## Phase 0: the track and the task text (this pull request)

### Tasks

- [x] **0.1 The amendment** (in #321) (task 16.4): the bullet gains the dated sentence (the two clocks; the rescan's re-attestation recompile carries the lapse into the attested document, first seen carried, the note on the second day; the entry removed at the end for 16.5; validation red on the second day by design)
- [x] **0.2 The track** (in #321): this folder, `conductor/tracks.md`, `conductor/index.md`, the todo's 16.4 item
- [x] **0.3 The pull request** (#321, merged 2026-10-25 20:38:58Z as a9c55bb): title `conductor: track exception-lapse_20261025, the drill's exception expires, the lapse on every plane (Req 6.9, 6.10, 6.41; task 16.4)`, a TL;DR; the owner merges (checkpoint)

### Verification (orchestrator)

- [x] The six FR statements in EARS shape; `scripts/lint-live-evidence.sh .` green (no row changes here); no em-dashes in the added lines; no closing keyword before an issue number

## Phase 1: the two days (no pull request merges)

Dependency: phase 0 merged. Worktree `exception-lapse-drill` for the drill pull request.

### Tasks

- [x] **1.1 Day one, 2026-10-26** (FR-1, FR-2): done on the scheduled run 40328859055 (job 121592610063): the expiries warning `0 days` at 13:37:06Z, the document re-attested under_investigation (the generic note, the statement's timestamp carried from the digest's release time 2026-10-23T14:12:33Z, read back with cosign on 2026-10-27), the status row undecided with first seen 2026-10-18 and 8 / 90 at 13:37:14Z, issue #325 at 13:37:10Z, the page's card lapsing at 13:37:41Z. As planned: the scheduled run read: its id, the expiries annotation (`0 days`), the re-attestation record for drill-app, the status issue's row (undecided, first seen 2026-10-18, the age), the new cve issue's number, the page's card; the owner's dispatch instead, if they choose it, told what it publishes (M17)
- [x] **1.2 The gate** (FR-3): done, #324 (commit 2fac0b0, 2026-10-26): build run 40330306412 red at the scan gate (13:29:25Z) naming CVE-2025-30204 with `An expired exception counts as uncovered`, the tier step green, validate 40330306541 green; rebased on 2026-10-27 (83b8fb3): build 40500526734 red at the same step, validate 40500526721 red at the accepted-risk lint with `expired_at 2026-10-26 is in the past`. As planned: the drill pull request on `exception-lapse-drill`, one commit, one comment line in `image/drill-app/image.yaml` (`# Drill 16.4, the gate's half (Req 6.9): this line alone puts drill-app in the build matrix; never merged.`), opened as a draft with a TL;DR that says it is meant to be red; the build run red at the scan gate naming CVE-2025-30204; validate green (day one) or red (day two, the past expiry); the run id recorded
- [x] **1.3 Day two, 2026-10-27** (FR-4): done on the scheduled run 40503212074 (job 122185846822): the expiries line `is in the past` at 12:41:25Z, the page's lapsed entry at 12:42:09Z, the compiler's lapse note in the attested document (`last_updated` 2026-10-27T12:23:46Z; the document was re-attested on the note alone (6.43)), validate red on #324's rebased commit. As planned: the scheduled run read: the expiries annotation (`is in the past`), the page's lapsed entry, the compiled document's lapse note (the re-attestation record, or the attested document read through verification), validate's red on any pull request of the day

### Verification (orchestrator)

- [x] Every number in 1.1 to 1.3 read from the API, the published page or the registry, none predicted

## Phase 2: the evidence and the hand-over (one pull request, 2026-10-27)

Dependency: 1.3 observed. Worktree `exception-lapse-evidence` from main.

### Tasks

- [x] **2.1 The entry leaves** (FR-5): done in #329, the lint green with ten refs resolving. As planned: CVE-2025-30204's entry removed from `triage/accepted-risk/drill-app.yaml`, the header comment updated; `scripts/lint-accepted-risk.sh .` green
- [x] **2.2 The evidence** (FR-6): #329; the drill pull request's closure after the merge is the box below. As planned: the LOG entry `## 2026-10-26: the drill's exception expires, the lapse on every plane (task 16.4)` (day one, the gate, day two, the removal, the two clocks as observed); ledger rows 6.9, 6.10, 6.41 `exercised` with the run ids, inducer `drill definition`; the task table row for 16.4; `tasks.md` 16.4 ticked; `tasks/todo.md` to 16.5; this plan's ticks; `conductor/tracks.md` to Completed; `metadata.json`; `conductor/index.md`; the owner merges; the drill pull request closed with a comment
- [ ] **2.2b The closure** (after the evidence merges): the drill pull request #324 closed unmerged with a comment naming the LOG heading and #329
- [ ] **2.3 The hand-over to 16.5** (asked of the owner on 2026-10-27 with #329; opened on their word): 16.5's track opened the day this merges (the HIGH ceiling lowered to one day for one rescan through a pull request, the finding undecided since 2026-10-18 reported over its ceiling)

### Verification (orchestrator)

- [x] `scripts/lint-live-evidence.sh .` (139 exercised, not 124: the count moved with 16.15's fifteen rows), `scripts/lint-log-anchors.sh all .`, `scripts/lint-accepted-risk.sh .` green; validate green on the evidence pull request (the lapsed entry gone); its build gate red by design, see the deviations log

## Final verification

- [x] FR-1 to FR-6 each have their evidence in the LOG entry, the ledger or this plan
- [ ] Three pull requests: phase 0 (a9c55bb) and the evidence (#329) merged by squash, the drill pull request closed unmerged (after the evidence merges)
- [x] Task 16.5's track is next in `tasks/todo.md`

## Deviations log

| Date | Task | Deviation | Reason | Resolution |
| --- | --- | --- | --- | --- |
| 2026-10-26 | 1.1 | The compiled document's first-seen time is 2026-10-23T14:12:33Z, not the 2026-10-18 the spec's FR-2 named | A document is per digest and carries the previous statement's timestamp (Req 6.38, 6.40); this digest was released on 2026-10-23 (#266); the 2026-10-18 date is the status tool's, carried across the definition's digests | Both clocks recorded as observed in the LOG and the ledger; FR-2's box ticked with the distinction |
| 2026-10-26 | 1.2 | Six drill-app builds of #323 (task 16.15) were refused by the same gate line that day | Both drills ran on the same expired entry; every #323 commit that put drill-app in the matrix was uncovered on it | Recorded in the LOG and row 6.9 as further observations, not evidence of 16.15 |
| 2026-10-27 | 1.3 | The scheduled run landed at 12:22 UTC, not in the 04:15 to 05:00 PDT window the plan estimated | GitHub's schedule delay (the cron is 06:17 UTC; the runs of 2026-10-23 to 2026-10-26 started between 11:12 and 13:14 UTC) | The evidence pull request opened once the run was read; validate red on no other pull request that day until then: the Renovate pull requests of 2026-10-26 evening had run on day one |
| 2026-10-27 | 2.1 | The evidence pull request's own build gate is red: a changed exception file puts drill-app in the matrix (Req 6.9) and nothing covers the finding once the entry is gone (build run 40506336848, the scan gate at 12:51:09Z) | The spec's FR-5 asked for validation green and did not see the build matrix rule; re-deciding would end 16.5's premise | Recorded in the LOG and row 6.9; the owner merges over the red gate by the ruleset's admin bypass (the first bypass of the program), their call; 16.5's pull requests build nothing |
| 2026-10-27 | 1.2 | The drill pull request was rebased onto main on day two to run validate | FR-4 names validate's red on a pull request of the day as evidence if one runs; none had | Validate and the build ran on the rebased commit 83b8fb3, both red by name |

---
