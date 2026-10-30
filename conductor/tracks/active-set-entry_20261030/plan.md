# Implementation plan: The drill definition's directory removed, its active-set entry refused by name, live

**Track ID:** active-set-entry_20261030
**Spec:** [spec.md](./spec.md)
**Created:** 2026-10-30
**Status:** [x] completed (phase 0 in #353, merged 2026-10-30 as af626ea; phase 1 the drill pull request #354, 2026-10-30; phase 2 the evidence in #355, 2026-10-30)

## Overview

Three phases, three pull requests of which one never merges, no code, no clock. Phase 0 is this pull request: the track and the amendment of task 16.11's text; the owner confirms by merging. Phase 1 is the drill pull request: two commits on a draft never merged, each read. Phase 2 is the evidence pull request the same day and the closure of the drill pull request after it merges, with the hand-over to 16.13.

## Phase 0: the track and the task text (this pull request)

### Tasks

- [x] **0.1 The amendment** (in #353) (task 16.11): the bullet gains the dated sentence (two commits, the first step's refusal and the Req 1.19 line both read; the proofs entry stays; the drill never merged)
- [x] **0.2 The track** (in #353): this folder, `conductor/tracks.md`, `conductor/index.md`, the todo's 16.11 item
- [x] **0.3 The pull request** (#353, merged 2026-10-30 21:43:58Z as af626ea): title `conductor: track active-set-entry_20261030, the drill definition's directory removed, its active-set entry refused by name (Req 1.19; task 16.11)`, a TL;DR; the owner merges (checkpoint)

### Verification (orchestrator)

- [x] The two FR statements in EARS shape; `scripts/lint-live-evidence.sh .` green (no row changes here); no em-dashes in the added lines; no closing keyword before an issue number

## Phase 1: the drill pull request (2026-10-30, never merged)

Dependency: phase 0 merged. Worktree `active-set-drill` from main.

### Tasks

- [x] **1.1 Commit 1** (e1e5808): validate run 41135094891 red at step 9, the accepted-risk lint with `risk treatment (Req 6.11): no image definition 'image/drill-app/image.yaml'`; the build red at the affected-definitions job with the Req 1.19 line, the e2e gate likewise. As planned: `image/drill-app/` removed, nothing else; the draft pull request opened with a TL;DR saying it is meant to be red; validate read: the first failing step and its annotation; the build gate read
- [x] **1.2 Commit 2** (5ed2421): validate run 41135329824 red at the active-set step with `active_definitions: active_set entry 'drill-app' has no definition: image/drill-app/image.yaml does not exist (Req 1.19) (Req 1.13)`; the build red at the affected-definitions job with the same line, the e2e gate likewise. As planned: `triage/accepted-risk/drill-app.yaml` removed as well; validate read: the active-set step red with the Req 1.19 line; the build gate read

### Verification (orchestrator)

- [x] Every line in 1.1 and 1.2 read from the API, none predicted

## Phase 2: the evidence and the closure (2026-10-30)

Dependency: 1.2 read. Worktree `active-set-evidence` from main.

### Tasks

- [x] **2.1 The evidence** (FR-2): #355. As planned: the LOG entry; row 1.19 `exercised` with the run id and the line; the task table row for 16.11; `tasks.md` 16.11 ticked; `tasks/todo.md` to 16.13; this plan's ticks; `conductor/tracks.md` to Completed; `metadata.json`; `conductor/index.md`; the owner merges
- [ ] **2.2 The closure** (after the evidence merges): the drill pull request closed unmerged with a comment naming the LOG heading and the evidence pull request, the branch kept on origin
- [ ] **2.3 The hand-over to 16.13** (asked of the owner with #355; opened on their word): 16.13's track on the owner's word (the page switch off for one rescan, the always-publish policy for one nightly)

### Verification (orchestrator)

- [x] `scripts/lint-live-evidence.sh .` (143 exercised), `scripts/lint-log-anchors.sh all .` green; validate green on the evidence pull request

## Final verification

- [x] FR-1 and FR-2 each have their evidence in the LOG entry, the ledger or this plan
- [ ] Two pull requests merged by squash (phase 0 af626ea, the evidence #355); the drill pull request #354 closed unmerged (after the evidence merges)
- [x] Task 16.13's track is next in `tasks/todo.md`

## Deviations log

| Date | Task | Deviation | Reason | Resolution |
| --- | --- | --- | --- | --- |
| 2026-10-30 | 1.1 | The Req 1.19 line appeared on the first commit already, in the build's and the e2e's matrix jobs, which read the active set through the same reader and run in parallel with validation | The spec expected the line on the second commit, from the validate step; it had not counted the matrix jobs as readers of the set | Recorded: three workflows refuse by name; the second commit still shows the validate step's own refusal |

---
