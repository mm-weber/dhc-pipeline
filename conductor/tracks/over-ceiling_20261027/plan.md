# Implementation plan: An undecided finding past its ceiling, the alarm raised and cleared, live

**Track ID:** over-ceiling_20261027
**Spec:** [spec.md](./spec.md)
**Created:** 2026-10-27
**Status:** [~] in progress (phase 0 opened 2026-10-27)

## Overview

Three phases, four pull requests, one dispatch, no code. Phase 0 is this pull request: the track and the amendment of task 16.5's text; the owner confirms by merging. Phase 1 is the breach, all on 2026-10-27: the one-line pull request lowering `triage.kev_ceiling` to one day, the owner's dispatch of the rescan with `drill: kev-synthetic`, the status and the page read with the finding over its ceiling, and the one-line revert merged the same day. Phase 2 is the clear on the next scheduled run (2026-10-28, about 04:15 to 06:30 PDT by the last five days' delays) and the evidence pull request that day, with the hand-over to 16.6.

## Phase 0: the track and the task text (this pull request)

### Tasks

- [ ] **0.1 The amendment** (task 16.5): the bullet gains the dated sentence (the KEV ceiling in place of the HIGH ceiling and the three readers of `triage.ceilings` that forbid lowering it; the dispatch; the revert the same day; the clear on the scheduled run); 6.47 added to its requirements
- [ ] **0.2 The track**: this folder, `conductor/tracks.md`, `conductor/index.md`, the todo's 16.5 item
- [ ] **0.3 The pull request**: title `conductor: track over-ceiling_20261027, an undecided finding past its ceiling, the alarm raised and cleared (Req 6.46, 6.47, 6.49; task 16.5)`, a TL;DR; the owner merges (checkpoint)

### Verification (orchestrator)

- [ ] The five FR statements in EARS shape; `scripts/lint-live-evidence.sh .` green (no row changes here); no em-dashes in the added lines; no closing keyword before an issue number

## Phase 1: the breach (2026-10-27)

Dependency: phase 0 merged. Worktrees `over-ceiling-change` and `over-ceiling-revert` from main.

### Tasks

- [ ] **1.1 The change** (FR-1): `triage.kev_ceiling: 1d` with a comment naming the drill and the revert; `scripts/triage-policy.sh . kev-ceiling` prints `1`; the pull request with a TL;DR; the owner merges
- [ ] **1.2 The dispatch** (FR-2): the owner dispatches `rescan.yml` on main with `drill: kev-synthetic`, told what it publishes (M17, M26); the run read: its id, the invariants step green with the substitution warning, the status issue's row and aggregates, the summary line, the page's lead, card and row
- [ ] **1.3 The revert** (FR-3): `triage.kev_ceiling: 14d`, the comment recording the drill's run; the pull request; the owner merges the same day; any scheduled run between the two merges listed

### Verification (orchestrator)

- [ ] Every number in 1.1 to 1.3 read from the API or the published page, none predicted

## Phase 2: the clear and the evidence (2026-10-28)

Dependency: 1.3 merged. Worktree `over-ceiling-evidence` from main.

### Tasks

- [ ] **2.1 The clear** (FR-4): the scheduled run read: its id, the status row (`age / 90`, KEV no), `over ceiling: 0`, the page unmarked
- [ ] **2.2 The evidence** (FR-5): the LOG entry; ledger rows 6.46, 6.47 and 6.49 appended with the drill's observation; the task table row for 16.5; `tasks.md` 16.5 ticked; `tasks/todo.md` to 16.6, the follow-up item on the three readers of `triage.ceilings`; this plan's ticks; `conductor/tracks.md` to Completed; `metadata.json`; `conductor/index.md`; the open boxes of track `exception-lapse_20261025` ticked; the owner merges
- [ ] **2.3 The hand-over to 16.6**: 16.6's track opened on the owner's word (drill-app bumps the vulnerable modules; the issues close resolved:fixed on the attested SBOMs; the fix clock)

### Verification (orchestrator)

- [ ] `scripts/lint-live-evidence.sh .` (139 exercised), `scripts/lint-log-anchors.sh all .` green; validate green on the evidence pull request

## Final verification

- [ ] FR-1 to FR-5 each have their evidence in the LOG entry, the ledger or this plan
- [ ] Four pull requests merged by squash (phase 0, the change, the revert, the evidence); one dispatch
- [ ] Task 16.6's track is next in `tasks/todo.md`

## Deviations log

| Date | Task | Deviation | Reason | Resolution |
| --- | --- | --- | --- | --- |

---
