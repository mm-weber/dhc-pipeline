# Implementation plan: A report through the private channel, handled as the policy promises, live

**Track ID:** private-report_20261031
**Spec:** [spec.md](./spec.md)
**Created:** 2026-10-31
**Status:** [~] in progress (phase 0 opened 2026-10-31)

## Overview

Two phases, two pull requests, one owner action. Phase 0 is this pull request: the track and the amendment of task 16.14's text; the owner confirms by merging and files the report. Phase 1 is the handling and the evidence, the same day.

## Phase 0: the track and the task text (this pull request)

### Tasks

- [ ] **0.1 The amendment** (task 16.14): the bullet gains the dated sentence (no response window is promised, the times are recorded as numbers; closed as a drill, an advisory being 16.12's)
- [ ] **0.2 The track**: this folder, `conductor/tracks.md`, `conductor/index.md`, the todo's 16.14 item
- [ ] **0.3 The pull request**: title `conductor: track private-report_20261031, a report through the private channel, handled as the policy promises (Req 9.2; task 16.14)`, a TL;DR; the owner merges (checkpoint)

### Verification (orchestrator)

- [ ] The three FR statements in EARS shape; `scripts/lint-live-evidence.sh .` green (no row changes here); no em-dashes in the added lines; no closing keyword before an issue number

## Phase 1: the report, the handling, the evidence (2026-10-31)

Dependency: phase 0 merged. Worktree `report-evidence` from main.

### Tasks

- [ ] **1.1 The report** (FR-1): the owner files it, titled as a drill, and names the filing time; the advisory id read
- [ ] **1.2 The handling** (FR-2): acknowledged in the thread, the subject examined against the records, answered, closed as a drill; the elapsed times recorded
- [ ] **1.3 The evidence** (FR-3): the LOG entry; row 9.2 `exercised`; the task table row for 16.14; `tasks.md` 16.14 ticked; `tasks/todo.md`; this plan's ticks; `conductor/tracks.md` to Completed; `metadata.json`; `conductor/index.md`; the owner merges

### Verification (orchestrator)

- [ ] `scripts/lint-live-evidence.sh .`, `scripts/lint-log-anchors.sh all .` green; validate green on the evidence pull request

## Final verification

- [ ] FR-1 to FR-3 each have their evidence in the LOG entry, the ledger or this plan
- [ ] Two pull requests merged by squash (phase 0, the evidence)

## Deviations log

| Date | Task | Deviation | Reason | Resolution |
| --- | --- | --- | --- | --- |

---
