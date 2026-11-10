# Implementation plan: An undecided finding past its ceiling, the alarm raised and cleared, live

**Track ID:** over-ceiling_20261027
**Spec:** [spec.md](./spec.md)
**Created:** 2026-10-27
**Status:** [x] completed (phase 0 in #330, merged 2026-10-27 as 0d3eae5; phase 1 on 2026-10-27: #331 16727ab, the dispatch 40578319282, #332 ebd0f65; phase 2 the evidence in #339, 2026-10-28)

## Overview

Three phases, four pull requests, one dispatch, no code. Phase 0 is this pull request: the track and the amendment of task 16.5's text; the owner confirms by merging. Phase 1 is the breach, all on 2026-10-27: the one-line pull request lowering `triage.kev_ceiling` to one day, the owner's dispatch of the rescan with `drill: kev-synthetic`, the status and the page read with the finding over its ceiling, and the one-line revert merged the same day. Phase 2 is the clear on the next scheduled run (2026-10-28, about 04:15 to 06:30 PDT by the last five days' delays) and the evidence pull request that day, with the hand-over to 16.6.

## Phase 0: the track and the task text (this pull request)

### Tasks

- [x] **0.1 The amendment** (in #330) (task 16.5): the bullet gains the dated sentence (the KEV ceiling in place of the HIGH ceiling and the three readers of `triage.ceilings` that forbid lowering it; the dispatch; the revert the same day; the clear on the scheduled run); 6.47 added to its requirements
- [x] **0.2 The track** (in #330): this folder, `conductor/tracks.md`, `conductor/index.md`, the todo's 16.5 item
- [x] **0.3 The pull request** (#330, merged 2026-10-27 13:27:18Z as 0d3eae5): title `conductor: track over-ceiling_20261027, an undecided finding past its ceiling, the alarm raised and cleared (Req 6.46, 6.47, 6.49; task 16.5)`, a TL;DR; the owner merges (checkpoint)

### Verification (orchestrator)

- [x] The five FR statements in EARS shape; `scripts/lint-live-evidence.sh .` green (no row changes here); no em-dashes in the added lines; no closing keyword before an issue number

## Phase 1: the breach (2026-10-27)

Dependency: phase 0 merged. Worktrees `over-ceiling-change` and `over-ceiling-revert` from main.

### Tasks

- [x] **1.1 The change** (FR-1): done, #331 (commit 9e49b2c, squash 16727ab, merged 20:27:46Z), validate green, the reader printing `1`. As planned: `triage.kev_ceiling: 1d` with a comment naming the drill and the revert; `scripts/triage-policy.sh . kev-ceiling` prints `1`; the pull request with a TL;DR; the owner merges
- [x] **1.2 The dispatch** (FR-2): done, run 40578319282 (20:28:12Z to 20:45:00Z, job 122450634752): the invariants step green at 20:40:09Z with the substitution warning, the status published at 20:44:30Z with `**9 / 1**`, KEV yes, `over ceiling: 1`, the page at 20:44:57Z with `KEV 1 days`, the card `over ceiling 1` and the row marked. As planned: the owner dispatches `rescan.yml` on main with `drill: kev-synthetic`, told what it publishes (M17, M26); the run read: its id, the invariants step green with the substitution warning, the status issue's row and aggregates, the summary line, the page's lead, card and row
- [x] **1.3 The revert** (FR-3): done, #332 (commit 6a73642, squash ebd0f65, merged 20:52:45Z); no scheduled run between the two merges. As planned: `triage.kev_ceiling: 14d`, the comment recording the drill's run; the pull request; the owner merges the same day; any scheduled run between the two merges listed

### Verification (orchestrator)

- [x] Every number in 1.1 to 1.3 read from the API, the published page or the registry, none predicted

## Phase 2: the clear and the evidence (2026-10-28)

Dependency: 1.3 merged. Worktree `over-ceiling-evidence` from main.

### Tasks

- [x] **2.1 The clear** (FR-4): done on the scheduled run 40693681245 (job 122834693772): `10 / 90`, KEV no, `over ceiling: 0` at 13:35:20Z, the page unmarked at 13:35:50Z. As planned: the scheduled run read: its id, the status row (`age / 90`, KEV no), `over ceiling: 0`, the page unmarked
- [x] **2.2 The evidence** (FR-5): #339. As planned: the LOG entry; ledger rows 6.46, 6.47 and 6.49 appended with the drill's observation; the task table row for 16.5; `tasks.md` 16.5 ticked; `tasks/todo.md` to 16.6, the follow-up item on the three readers of `triage.ceilings`; this plan's ticks; `conductor/tracks.md` to Completed; `metadata.json`; `conductor/index.md`; the open boxes of track `exception-lapse_20261025` ticked; the owner merges
- [ ] **2.3 The hand-over to 16.6** (asked of the owner on 2026-10-28 with #339; opened on their word): 16.6's track opened on the owner's word (drill-app bumps the vulnerable modules; the issues close resolved:fixed on the attested SBOMs; the fix clock)

### Verification (orchestrator)

- [x] `scripts/lint-live-evidence.sh .` (139 exercised), `scripts/lint-log-anchors.sh all .` green; validate green on the evidence pull request

## Final verification

- [x] FR-1 to FR-5 each have their evidence in the LOG entry, the ledger or this plan
- [x] Four pull requests merged by squash (phase 0 0d3eae5, the change 16727ab, the revert ebd0f65, the evidence #339); one dispatch (40578319282)
- [x] Task 16.6's track is next in `tasks/todo.md`

## Deviations log

| Date | Task | Deviation | Reason | Resolution |
| --- | --- | --- | --- | --- |
| 2026-10-27 | 1.2 | The dispatch re-attested drill-app's document, the lapse note of 2026-10-27 12:34Z replaced by the generic uncovered note | The lapsed entry had left the exception file with #329 at 13:01Z, so the recompile found no expired exception naming the finding; a dispatch re-attests every changed document (M17) | Recorded in the LOG; the clocks unchanged (`last_updated` records status, action statement, packages and issue links, not a note's wording) |
| 2026-10-27 | 1.2 | The dispatch landed after the day's scheduled run, as the spec's risk table expected | The owner merged #331 at 20:27Z | The status and the page read KEV yes until the scheduled run of 2026-10-28, which cleared them |

---
