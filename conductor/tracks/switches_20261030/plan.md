# Implementation plan: The switches, one run each: the page off, every rebuild published, live

**Track ID:** switches_20261030
**Spec:** [spec.md](./spec.md)
**Created:** 2026-10-30
**Status:** [~] in progress (phase 0 opened 2026-10-30)

## Overview

Three phases, four pull requests, no code, no dispatch. Phase 0 is this pull request: the track and the amendment of task 16.13's text; the owner confirms by merging. Phase 1 is the day of the switches: the flip pull request merged tonight, the scheduled rebuild of 2026-10-31 publishing every active definition, the scheduled rescan of that day skipping the page, both read, and the revert pull request merged the same day. Phase 2 is the chart's digest pull request read as it merges, the owner's Pages action if chosen, and the evidence pull request, with the hand-over to 16.12.

## Phase 0: the track and the task text (this pull request)

### Tasks

- [ ] **0.1 The amendment** (task 16.13): the bullet gains the dated sentence (both switches in one pull request for one day; the costs; 6.62's failure branch as the owner's Pages action)
- [ ] **0.2 The track**: this folder, `conductor/tracks.md`, `conductor/index.md`, the todo's 16.13 item
- [ ] **0.3 The pull request**: title `conductor: track switches_20261030, the switches, one run each: the page off, every rebuild published (Req 2.17, 6.61, 6.62; task 16.13)`, a TL;DR; the owner merges (checkpoint)

### Verification (orchestrator)

- [ ] The five FR statements in EARS shape; `scripts/lint-live-evidence.sh .` green (no row changes here); no em-dashes in the added lines; no closing keyword before an issue number

## Phase 1: the day of the switches (2026-10-30 evening to 2026-10-31)

Dependency: phase 0 merged. Worktrees `switches-flip` and `switches-revert` from main.

### Tasks

- [ ] **1.1 The flip** (FR-1): `publish_policy: always` and `page: false` with their comments; `release-policy.sh . check` prints both; the pull request with a TL;DR naming the costs; the owner merges tonight
- [ ] **1.2 The rebuild** (FR-2): the scheduled build of 2026-10-31 read: the run id, the seven jobs, the verdicts, the digests and tags (registry read), drill-app's document
- [ ] **1.3 The rescan** (FR-3): the scheduled rescan of 2026-10-31 read: the page job skipped, the run green, the served page's generation date of 2026-10-30
- [ ] **1.4 The revert** (FR-5, first half): both switches back, the comments recording the runs; the owner merges the same day

### Verification (orchestrator)

- [ ] Every number in 1.1 to 1.4 read from the API, the registry or the served page, none predicted

## Phase 2: the digest pull request, the deployment refused, the evidence

Dependency: 1.4 merged. Worktree `switches-evidence` from main.

### Tasks

- [ ] **2.1 The chart digest pull request** (Req 3.12): Renovate's digest-only update of the hardened-app chart read: its number, its checks, its automerge
- [ ] **2.2 The deployment refused** (FR-4, the owner's call): Pages disabled before one scheduled rescan, the run red at the page job by name, Pages enabled again, the next run deploying; or the owner's word that the branch stays unexercised
- [ ] **2.3 The evidence** (FR-5): the LOG entry; rows 2.17 (and 6.62) `exercised`, rows 2.15, 3.12 and 6.61 appended; the task table row for 16.13; `tasks.md` 16.13 ticked; `tasks/todo.md` to 16.12; this plan's ticks; `conductor/tracks.md` to Completed; `metadata.json`; `conductor/index.md`; the owner merges
- [ ] **2.4 The hand-over to 16.12**: 16.12's track on the owner's word (a revocation of a tagged drill digest, its advisory and the runbook)

### Verification (orchestrator)

- [ ] `scripts/lint-live-evidence.sh .`, `scripts/lint-log-anchors.sh all .` green; validate green on the evidence pull request

## Final verification

- [ ] FR-1 to FR-5 each have their evidence in the LOG entry, the ledger or this plan
- [ ] Four pull requests merged by squash (phase 0, the flip, the revert, the evidence)
- [ ] Task 16.12's track is next in `tasks/todo.md`

## Deviations log

| Date | Task | Deviation | Reason | Resolution |
| --- | --- | --- | --- | --- |

---
