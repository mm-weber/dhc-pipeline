# Implementation plan: Deliberate violations, one pull request, every lint refuses by name, live

**Track ID:** deliberate-violations_20261025
**Spec:** [spec.md](./spec.md)
**Created:** 2026-10-25
**Status:** [x] completed (phase 0 in #322, merged 2026-10-25 as c1c8aa6; phase 1 the drill pull request #323, 2026-10-26; phase 2 the evidence in #326, 2026-10-26)

## Overview

Three phases, three pull requests, no code. Phase 0 is this pull request: the track and the amendment of task 16.15's text; the owner confirms by merging. Phase 1 is the drill pull request: twenty-one commits on one branch, each carrying one violation and undoing the previous one, pushed as each run starts; every run red, every refusal read by the commit's sha. Phase 2 is the evidence pull request, opened once the last run is in. No clock is involved: the whole of phases 1 and 2 fits an afternoon (a validate run takes three to four minutes, a drill-app build six, a chart install about ten; the runs overlap).

## Phase 0: the track and the task text (this pull request)

### Tasks

- [x] **0.1 The amendment** (task 16.15): the bullet gains the dated sentence (the ledger's fifteen rows and the four re-observations, one violation per commit with the previous undone, the EARS validator item dropped because no validator exists)
- [x] **0.2 The track**: this folder, `conductor/tracks.md`, `conductor/index.md`, the todo's 16.15 item
- [x] **0.3 The pull request**: title `conductor: track deliberate-violations_20261025, every lint refuses by name on one pull request (Req 7.4, 7.11; task 16.15)`, a TL;DR; the owner merges (checkpoint: #322, c1c8aa6, 2026-10-25 20:20Z)

### Verification (orchestrator)

- [x] The three FR statements in EARS shape; `scripts/lint-live-evidence.sh .` green (no row changes here); no em-dashes in the added lines; no closing keyword before an issue number

## Phase 1: the drill pull request (never merged)

Dependency: phase 0 merged. Worktree `violations-drill` from main.

### Tasks

- [x] **1.1 The branch and the draft** (#323, commit b15aa92 at 13:23:40Z on 2026-10-26): commit 1 (row 1.6) pushed, the pull request opened as a draft with a TL;DR that says every run is meant to be red and lists the twenty-one rules
- [x] **1.2 Commits 2 to 21** (pushed 13:24 to 13:37Z; 13 to 21 pushed again as commits 22 to 30 between 13:45 and 13:51Z, see the deviations log): each commit undoes the previous violation and adds the next, in the spec's order; each pushed once the previous commit's validate run exists (its id noted); the commit message names the row, the file and the check expected to refuse
- [x] **1.3 The reading** (the LOG entry's table; `collect.py` over each sha's check runs): for every commit, the check runs by sha (`commits/<sha>/check-runs`), the refusing check's annotations, the run id and the line; a violation not refused noted at once

### Verification (orchestrator)

- [x] Twenty-one rules, thirty shas, every rule refused (two of them named in the log only, no defect); nothing merged; the pull request still a draft

## Phase 2: the evidence (one pull request)

Dependency: 1.3 complete. Worktree `violations-evidence` from main.

### Tasks

- [x] **2.1 The evidence** (#326): the LOG entry `## 2026-10-25: deliberate violations, every lint refuses by name (task 16.15)` with the table (row, commit, run, check, line); ledger rows 1.6, 1.11, 1.12, 1.18, 4.8, 5.8, 5.10, 6.11, 6.12, 6.19, 6.25, 6.39, 7.10, 9.6, 9.18 `exercised`, inducer `pull request`; rows 4.2, 4.3, 4.6, 7.9 with the re-observation added; the task table row for 16.15; `tasks.md` 16.15 ticked; `tasks/todo.md`; this plan's ticks; `conductor/tracks.md` to Completed; `metadata.json`; `conductor/index.md`; the owner merges
- [ ] **2.2 The closure** (after the evidence merges: the post-merge housekeeping): the drill pull request closed with a comment linking the LOG heading and the evidence pull request

### Verification (orchestrator)

- [x] `scripts/lint-live-evidence.sh .` (136 exercised, up by fifteen), `scripts/lint-log-anchors.sh all .` green; validate green on the evidence pull request

## Final verification

- [x] FR-1 to FR-3 each have their evidence in the LOG entry, the ledger or this plan
- [ ] Two pull requests merged by squash (phase 0, the evidence); the drill pull request closed unmerged (after the evidence merges)

## Deviations log

| Date | Task | Deviation | Reason | Resolution |
| --- | --- | --- | --- | --- |
| 2026-10-26 | 1.2 | Thirty commits, not twenty-one: 13 to 21 pushed twice | The drill's reset script checked the base's files out and cleaned untracked files, which never removes a committed file the base lacks; commit 10's `.trivyignore.yaml` stayed in commits 11 to 21 and masked 13 to 17 | The script corrected (`git rm --cached` before the checkout), the nine commits pushed again, the first attempt kept on the branch and told in the LOG |
| 2026-10-26 | 1.3 | Rules 18 to 21 refused without a named annotation | yamale and kyverno apply print to the log only | The step's failure recorded; a follow-up item in `tasks/todo.md` to wrap both in `::error::` lines |
| 2026-10-26 | 1.2 | Every drill-app build red at the scan gate | The drill's HIGH exception expired the same day (task 16.4) | Recorded in the LOG as 16.4's gate half seen six more times |
| 2026-10-26 | 2.1 | The LOG entry dated 2026-10-26, the spec drafted 2026-10-25 | The runs happened on the 26th | The observation date wins |

---
