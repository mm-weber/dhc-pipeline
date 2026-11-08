# Implementation plan: The drill definition retired, the drill program closed, the ledger complete

**Track ID:** retirement_20261107
**Spec:** [spec.md](./spec.md)
**Created:** 2026-11-07
**Status:** [~] in progress (phase 0 opened 2026-11-07)

## Overview

Three phases, three pull requests, one owner action, one dispatched rescan. Phase 0 is this pull request: the track and the amendment of task 16.16's text; the owner confirms by merging. Phase 1 is the retirement pull request, test-first for the live-state case, with the record completed in the same change; the owner merges and archives the upstream. Phase 2 is the dispatched rescan read and the evidence pull request that closes this track and task group 16.

## Phase 0: the track and the task text (this pull request)

### Tasks

- [ ] **0.1 The amendment** (task 16.16): the bullet gains the dated sentence (the scans stop with the directory, what stays published, the issues closing as absent at the first rescan after, the eight paragraphs, the upstream archived)
- [ ] **0.2 The track**: this folder, `conductor/tracks.md`, `conductor/index.md`, the todo's 16.16 item
- [ ] **0.3 The pull request**: title `conductor: track retirement_20261107, the drill definition retired, the drill program closed, the ledger complete (Req 1.19, 7.11; task 16.16)`, a TL;DR; the owner merges (checkpoint)

### Verification (orchestrator)

- [ ] The five FR statements in EARS shape; `scripts/lint-live-evidence.sh .` green (no row changes here); no em-dashes in the added lines; no closing keyword before an issue number

## Phase 1: the retirement (one pull request)

Dependency: phase 0 merged. Worktree `retirement` from main.

### Tasks

- [ ] **1.1 RED: the live-state case asserts six** (FR-1): `scripts/lint-probes_test.sh` case 13 expects `6 active definition(s)`, `6 covered by 3 probe registration(s)` and no declared none, and fails on the repository as it stands; committed red
- [ ] **1.2 GREEN: the removal** (FR-1): the active-set line and the proofs entry out of `catalogue-policy.yaml`, `image/drill-app/` and `triage/accepted-risk/drill-app.yaml` removed, the revocation entry kept; the case green, `scripts/render-tracking.sh --check` unchanged, the repository lints green
- [ ] **1.3 The record** (FR-2): the LOG entry; the eight "What the drill found" paragraphs, each written from its entry's text; the README's and the manual's rows; the ledger's completeness stated in the entry
- [ ] **1.4 The pull request**: title `chore: the drill definition retired, the drill program closed, the ledger complete (Req 1.19, 6.52, 7.11; task 16.16)`, a TL;DR; the owner merges
- [ ] **1.5 The upstream archived** (FR-3): the owner archives `mm-weber/drill-app` and names the time; the flag read from the API

### Verification (orchestrator)

- [ ] `scripts/lint-probes_test.sh`, `scripts/lint-live-evidence.sh .`, `scripts/lint-log-anchors.sh all .` green; validate green on the pull request; the e2e's affected-components job unchanged (the fixture had no chart)

## Phase 2: the first rescan after, the evidence

Dependency: phase 1 merged. Worktree `retirement-evidence` from main.

### Tasks

- [ ] **2.1 The rescan** (FR-4): dispatched by the owner after the merge; read: the enumeration without the definition, #325 closed `resolved:absent` with its comment, #300's affected set, the posture summary, the status issue and the page without the definition
- [ ] **2.2 The evidence** (FR-5): the run in the LOG entry; the task table row for 16.16; `tasks.md` 16.16 ticked; `tasks/todo.md` task group 16 complete with the ledger's counts; this plan's ticks; `conductor/tracks.md` to Completed; `metadata.json`; `conductor/index.md`; the owner merges

### Verification (orchestrator)

- [ ] Every number in 2.1 read from the API, none predicted; `scripts/lint-live-evidence.sh .`, `scripts/lint-log-anchors.sh all .` green; validate green on the evidence pull request

## Final verification

- [ ] FR-1 to FR-5 each have their evidence in the LOG entry, the ledger or this plan
- [ ] Three pull requests merged by squash (phase 0, the retirement, the evidence)
- [ ] No row of the ledger reads `drill`; task group 16 complete in `tasks/todo.md`

## Deviations log

| Date | Task | Deviation | Reason | Resolution |
| --- | --- | --- | --- | --- |

---
