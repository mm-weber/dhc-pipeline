# Implementation plan: Deliberate violations, one pull request, every lint refuses by name, live

**Track ID:** deliberate-violations_20261025
**Spec:** [spec.md](./spec.md)
**Created:** 2026-10-25
**Status:** [~] in progress (phase 0 opened 2026-10-25)

## Overview

Three phases, three pull requests, no code. Phase 0 is this pull request: the track and the amendment of task 16.15's text; the owner confirms by merging. Phase 1 is the drill pull request: twenty-one commits on one branch, each carrying one violation and undoing the previous one, pushed as each run starts; every run red, every refusal read by the commit's sha. Phase 2 is the evidence pull request, opened once the last run is in. No clock is involved: the whole of phases 1 and 2 fits an afternoon (a validate run takes three to four minutes, a drill-app build six, a chart install about ten; the runs overlap).

## Phase 0: the track and the task text (this pull request)

### Tasks

- [ ] **0.1 The amendment** (task 16.15): the bullet gains the dated sentence (the ledger's fifteen rows and the four re-observations, one violation per commit with the previous undone, the EARS validator item dropped because no validator exists)
- [ ] **0.2 The track**: this folder, `conductor/tracks.md`, `conductor/index.md`, the todo's 16.15 item
- [ ] **0.3 The pull request**: title `conductor: track deliberate-violations_20261025, every lint refuses by name on one pull request (Req 7.4, 7.11; task 16.15)`, a TL;DR; the owner merges (checkpoint)

### Verification (orchestrator)

- [ ] The three FR statements in EARS shape; `scripts/lint-live-evidence.sh .` green (no row changes here); no em-dashes in the added lines; no closing keyword before an issue number

## Phase 1: the drill pull request (never merged)

Dependency: phase 0 merged. Worktree `violations-drill` from main.

### Tasks

- [ ] **1.1 The branch and the draft**: commit 1 (row 1.6) pushed, the pull request opened as a draft with a TL;DR that says every run is meant to be red and lists the twenty-one rules
- [ ] **1.2 Commits 2 to 21**: each commit undoes the previous violation and adds the next, in the spec's order; each pushed once the previous commit's validate run exists (its id noted); the commit message names the row, the file and the check expected to refuse
- [ ] **1.3 The reading**: for every commit, the check runs by sha (`commits/<sha>/check-runs`), the refusing check's annotations, the run id and the line; a violation not refused noted at once

### Verification (orchestrator)

- [ ] Twenty-one shas, twenty-one run ids, twenty-one refusals by name (or the defects named); nothing merged; the pull request still a draft

## Phase 2: the evidence (one pull request)

Dependency: 1.3 complete. Worktree `violations-evidence` from main.

### Tasks

- [ ] **2.1 The evidence**: the LOG entry `## 2026-10-25: deliberate violations, every lint refuses by name (task 16.15)` with the table (row, commit, run, check, line); ledger rows 1.6, 1.11, 1.12, 1.18, 4.8, 5.8, 5.10, 6.11, 6.12, 6.19, 6.25, 6.39, 7.10, 9.6, 9.18 `exercised`, inducer `pull request`; rows 4.2, 4.3, 4.6, 7.9 with the re-observation added; the task table row for 16.15; `tasks.md` 16.15 ticked; `tasks/todo.md`; this plan's ticks; `conductor/tracks.md` to Completed; `metadata.json`; `conductor/index.md`; the owner merges
- [ ] **2.2 The closure**: the drill pull request closed with a comment linking the LOG heading and the evidence pull request

### Verification (orchestrator)

- [ ] `scripts/lint-live-evidence.sh .` (the exercised count up by fifteen), `scripts/lint-log-anchors.sh all .` green; validate green on the evidence pull request

## Final verification

- [ ] FR-1 to FR-3 each have their evidence in the LOG entry, the ledger or this plan
- [ ] Two pull requests merged by squash (phase 0, the evidence); the drill pull request closed unmerged

## Deviations log

| Date | Task | Deviation | Reason | Resolution |
| --- | --- | --- | --- | --- |

---
