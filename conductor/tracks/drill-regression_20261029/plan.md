# Implementation plan: The drill's HIGH brought back, the closed issue reopened on the lapse, live

**Track ID:** drill-regression_20261029
**Spec:** [spec.md](./spec.md)
**Created:** 2026-10-29
**Status:** [x] completed (phase 0 in #347, merged 2026-10-29 as c0c8850; phase 1 #348 as ec90a95 and the release 40975473407; phase 2 the reopen on run 41060449312 and the evidence in #351, 2026-10-30)

## Overview

Three phases, three pull requests, no code. Phase 0 is this pull request: the track and the amendment of task 16.7's text; the owner confirms by merging. Phase 1 is the regression, today: the pull request removing the HIGH's bump and accepting the finding for one day with its LOG decision, green at the gate by the exception; its merge and the release read. Phase 2 is the reopen on the scheduled rescan of 2026-10-30 (about 04:00 to 06:30 PDT) and the evidence pull request that day, which removes the lapsed entry, with the hand-over to 16.11.

## Phase 0: the track and the task text (this pull request)

### Tasks

- [x] **0.1 The amendment** (in #347) (task 16.7): the bullet gains the dated sentence (one module, a one-day acceptance rather than a bypass, the reopen on the lapse day, the entry removed, the finding undecided for 16.16)
- [x] **0.2 The track** (in #347): this folder, `conductor/tracks.md`, `conductor/index.md`, the todo's 16.7 item
- [x] **0.3 The pull request** (#347, merged 2026-10-29 23:39:21Z as c0c8850): title `conductor: track drill-regression_20261029, the drill's HIGH brought back, the closed issue reopened on the lapse (Req 6.57, 6.46; task 16.7)`, a TL;DR; the owner merges (checkpoint)

### Verification (orchestrator)

- [x] The five FR statements in EARS shape; `scripts/lint-live-evidence.sh .` green (no row changes here); no em-dashes in the added lines; no closing keyword before an issue number

## Phase 1: the regression (2026-10-29)

Dependency: phase 0 merged. Worktree `drill-regression` from main.

### Tasks

- [x] **1.1 The regression** (FR-1): done, #348 (db12bd7, squash ec90a95, merged 23:47:14Z); build run 40974710663 green at the gate by the exception, govulncheck naming the symbol; validate green with the `1 days` warning. As planned: the jwt dep removed from the bump step (the comment updated), the exception entry with `decided_at` 2026-10-29 and `expired_at` 2026-10-30, the LOG entry's first part with the decision heading the entry cites; the pull request with a TL;DR; the build of drill-app green at the gate by the exception, govulncheck naming `ParseUnverified`; the owner merges
- [x] **1.2 The release** (FR-2): done, run 40975473407 (23:47 to 23:55Z, the scan at 23:53:38Z before midnight): tags on `sha256:d5d9bb51146f...`, one `affected` statement, the SBOMs with v5.2.1 and v1.3.0. As planned: main's push build read: the run id, the new digest, the tags, the OpenVEX with the `affected` statement, the SBOMs with v5.2.1 and v1.3.0

### Verification (orchestrator)

- [x] Every number in 1.1 and 1.2 read from the API or the registry, none predicted

## Phase 2: the reopen and the evidence (2026-10-30)

Dependency: 1.2 read. Worktree `drill-regression-evidence` from main.

### Tasks

- [x] **2.1 The reopen** (FR-3): done on the scheduled run 41060449312: #325 reopened at 13:19:27Z, `resolved:fixed` removed, the status row undecided with first seen 2026-10-18 at 13:26:29Z. As planned: the scheduled run read: #325's reopen comment and labels, the status row, the page
- [x] **2.2 The entry leaves** (FR-4): done in #351, the lane empty, the lints green. As planned: the lapsed entry removed, the lane empty; the lints green
- [x] **2.3 The evidence** (FR-5): #351. As planned: the LOG entry's second part; row 6.57 `exercised`, row 6.46 appended; the task table row for 16.7; `tasks.md` 16.7 ticked; `tasks/todo.md` to 16.11; this plan's ticks; `conductor/tracks.md` to Completed; `metadata.json`; `conductor/index.md`; the owner merges
- [ ] **2.4 The hand-over to 16.11** (asked of the owner with #351; opened on their word): 16.11's track on the owner's word (a never-merged pull request removing the drill definition's directory with its active-set entry kept, Req 1.19)

### Verification (orchestrator)

- [x] `scripts/lint-live-evidence.sh .` (142 exercised), `scripts/lint-log-anchors.sh all .`, `scripts/lint-accepted-risk.sh .` green; validate green on the evidence pull request, its build gate red by design (the deviations log)

## Final verification

- [x] FR-1 to FR-5 each have their evidence in the LOG entry, the ledger or this plan
- [x] Three pull requests merged by squash (phase 0 c0c8850, the regression ec90a95, the evidence #351)
- [x] Task 16.11's track is next in `tasks/todo.md`

## Deviations log

| Date | Task | Deviation | Reason | Resolution |
| --- | --- | --- | --- | --- |
| 2026-10-30 | 2.2 | The evidence pull request's own build gate is red: a changed exception file puts drill-app in the matrix and nothing covers the finding once the entry is gone (run 41063600623, the scan gate at 13:33:42Z) | The plan's verification named validation only, though task 16.4's evidence (#329) had met the same gate | Recorded in the LOG; the owner merges over the red gate by the ruleset's admin bypass, the second of the program |

---
