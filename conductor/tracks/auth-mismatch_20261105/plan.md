# Implementation plan: A true authenticity mismatch, the drill definition's tag moved by its maintainer, live

**Track ID:** auth-mismatch_20261105
**Spec:** [spec.md](./spec.md)
**Created:** 2026-11-05
**Status:** [~] in progress (phase 0 opened 2026-11-05; the owner's first action taken 10:29Z, before it)

## Overview

Two phases, two pull requests, two owner actions, two dispatched rescans. Phase 0 is this pull request: the track and the amendment of task 16.10's text; the owner confirms by merging. Phase 1 is the day of the drill, 2026-11-05: the tag moved (already done when this plan was written), the dispatched rescan filing the first true mismatch, the owner's decision and the restore, the second dispatched rescan, the issue closed, the evidence.

## Phase 0: the track and the task text (this pull request)

### Tasks

- [ ] **0.1 The amendment** (task 16.10): the bullet gains the dated sentence (the unsigned commit covering both of the check's conditions; the runs dispatched by the owner's rule; the original tag object restored; the issue closed by the owner with the reason; 3.13 kept with its reason)
- [ ] **0.2 The track**: this folder, `conductor/tracks.md`, `conductor/index.md`, the todo's 16.10 item
- [ ] **0.3 The pull request**: title `conductor: track auth-mismatch_20261105, a true authenticity mismatch, the drill definition's tag moved by its maintainer (Req 3.10; task 16.10)`, a TL;DR; the owner merges (checkpoint)

### Verification (orchestrator)

- [ ] The four FR statements in EARS shape; `scripts/lint-live-evidence.sh .` green (no row changes here); no em-dashes in the added lines; no closing keyword before an issue number

## Phase 1: the mismatch, the decision, the evidence (2026-11-05)

Dependency: phase 0 merged for 1.4. Worktree `auth-mismatch-evidence` from main.

### Tasks

- [ ] **1.1 The tag moved** (FR-1): the owner's push read from the API: tag object 726afc2, unsigned, at commit d273710, unsigned, 10:29Z
- [ ] **1.2 The mismatch reported** (FR-2): the dispatched rescan read: the run id, the authenticity step's line, the run red with every later step run, the `supply-chain` issue's number and time, the status issue of the day
- [ ] **1.3 The decision and the restore** (FR-3): the owner's decision (a drill), the original tag object ca6144e6 pushed back, the second dispatched rescan read with the step green and nothing filed, the issue closed by the owner with the reason
- [ ] **1.4 The evidence** (FR-4): the LOG entry; row 3.10 `exercised`, row 3.13 kept; the task table row for 16.10; `tasks.md` 16.10 ticked; `tasks/todo.md`; this plan's ticks; `conductor/tracks.md` to Completed; `metadata.json`; `conductor/index.md`; the owner merges

### Verification (orchestrator)

- [ ] Every number in 1.1 to 1.3 read from the API, none predicted; `scripts/lint-live-evidence.sh .`, `scripts/lint-log-anchors.sh all .` green; validate green on the evidence pull request

## Final verification

- [ ] FR-1 to FR-4 each have their evidence in the LOG entry, the ledger or this plan
- [ ] Two pull requests merged by squash (phase 0, the evidence)
- [ ] The tag `v0.1.0` at its original object; no `supply-chain` issue open

## Deviations log

| Date | Task | Deviation | Reason | Resolution |
| --- | --- | --- | --- | --- |
| 2026-11-05 | 1.1 | The tag moved at 10:29Z, before phase 0 existed | The owner's pace; the steps had been given in the conversation | The time and the objects recorded here and in the spec; phase 0 opened the same hour |

---
