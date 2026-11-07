# Implementation plan: A revocation, its advisory and the runbook, the drill digest withdrawn, live

**Track ID:** revocation_20261105
**Spec:** [spec.md](./spec.md)
**Created:** 2026-11-05
**Status:** [x] completed 2026-11-07 (phase 0 #371, the entry #374, the evidence #375)

## Overview

Two phases, three pull requests, three owner actions, two dispatched rescans. Phase 0 is this pull request: the track and the amendment of task 16.12's text; the owner confirms by merging. Phase 1 is the drill: the advisory drafted, the entry merged while the tags still reference the digest, the dispatched rescan red at the posture step, the version deleted, the second dispatched rescan green, the advisory published or kept, the evidence, and the hand-over to 16.16.

## Phase 0: the track and the task text (this pull request)

### Tasks

- [x] **0.1 The amendment** (task 16.12): the bullet gains the dated sentence (the schema admitting no entry before its move, so Move B1; the advisory drafted first; the runs dispatched; the deleted digest the one 16.13 and 16.14 cite; the republish at the next scheduled rebuild, 16.16 following at once)
- [x] **0.2 The track**: this folder, `conductor/tracks.md`, `conductor/index.md`, the todo's 16.12 item
- [x] **0.3 The pull request**: title `conductor: track revocation_20261105, a revocation, its advisory and the runbook, the drill digest withdrawn (Req 9.4, 9.5, 9.7; task 16.12)`, a TL;DR; the owner merges (checkpoint)

### Verification (orchestrator)

- [x] The five FR statements in EARS shape; `scripts/lint-live-evidence.sh .` green (no row changes here); no em-dashes in the added lines; no closing keyword before an issue number

## Phase 1: the advisory, the entry, the withdrawal, the evidence

Dependency: phase 0 merged. Worktrees `revocation-entry` and `revocation-evidence` from main.

### Tasks

- [x] **1.1 The advisory drafted** (FR-1): the owner opens it, titled as a drill, and gives its URL; read through the API if the token can, else from the owner's word
- [x] **1.2 The entry** (FR-2): one `withdrawn` entry in `triage/revocations.yaml`, the pull request green at the schema check; the owner merges while the three tags still reference the digest
- [x] **1.3 The tag reported** (FR-3): the dispatched rescan read: the run id, the three lines, the summary line, the run red with every later step run, the status issue's entry
- [x] **1.4 The withdrawal** (FR-4): the owner deletes the package version and names the time; the second dispatched rescan read: the summary line `1 recorded, 0 referenced`, the step green, the entry listed; the advisory published or kept at the owner's word
- [x] **1.5 The evidence** (FR-5): the LOG entry; rows 9.4, 9.5 and 9.7 `exercised`; the task table row for 16.12; `tasks.md` 16.12 ticked; `tasks/todo.md` to 16.16; this plan's ticks; `conductor/tracks.md` to Completed; `metadata.json`; `conductor/index.md`; the owner merges
- [x] **1.6 The hand-over to 16.16**: the retirement's track on the owner's word, at once, before a scheduled rebuild republishes the withdrawn definition

### Verification (orchestrator)

- [x] Every number in 1.1 to 1.4 read from the API or the owner's pasted record, none predicted; `scripts/lint-live-evidence.sh .`, `scripts/lint-log-anchors.sh all .` green; validate green on both pull requests

## Final verification

- [x] FR-1 to FR-5 each have their evidence in the LOG entry, the ledger or this plan
- [x] Three pull requests merged by squash (phase 0, the entry, the evidence)
- [x] Task 16.16's track is next in `tasks/todo.md`

## Deviations log

| Date | Task | Deviation | Reason | Resolution |
| --- | --- | --- | --- | --- |
| 2026-11-06 | 1.4 | A day passed between the first refusal and the deletion; the scheduled rescan of 2026-11-06 refused as well | The owner's pace | Recorded as the second refusal, the scheduler's own |

---
