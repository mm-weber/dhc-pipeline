# Implementation plan: The fail-closed release gate refuses a release, the digest frozen, live

**Track ID:** fail-closed-release_20261027
**Spec:** [spec.md](./spec.md)
**Created:** 2026-10-27
**Status:** [~] in progress (phase 0 opened 2026-10-27)

## Overview

Three phases, four pull requests, one dispatch, no code. Phase 0 is this pull request: the track and the amendment of task 16.9's text; the owner confirms by merging. Phase 1 is the refusal, on 2026-10-27: the one-line pull request turning `release.fail_closed` on, the owner's dispatch of `build.yml` for drill-app, the run and the registry read, and the one-line pull request turning the switch off the same day (or the owner's word to keep it). Phase 2 is the evidence: a draft pull request the same evening, made ready on 2026-10-28 once the scheduled rescan has shown the frozen digest neither enumerated nor re-attested, and the hand-over: 16.6 fixes the finding, which is this gate's way out.

## Phase 0: the track and the task text (this pull request)

### Tasks

- [ ] **0.1 The amendment** (task 16.9): the bullet gains the dated sentence (the exception's expiry is 16.4's, done; the switch on for one dispatched build; the frozen half read on the next scheduled run; the way out 16.6; the switch off the same day unless kept)
- [ ] **0.2 The track**: this folder, `conductor/tracks.md`, `conductor/index.md`, the todo's 16.9 item
- [ ] **0.3 The pull request**: title `conductor: track fail-closed-release_20261027, the fail-closed release gate refuses a release, the digest frozen (Req 2.11, 2.13; task 16.9)`, a TL;DR; the owner merges (checkpoint)

### Verification (orchestrator)

- [ ] The five FR statements in EARS shape; `scripts/lint-live-evidence.sh .` green (no row changes here); no em-dashes in the added lines; no closing keyword before an issue number

## Phase 1: the refusal (2026-10-27)

Dependency: phase 0 merged. Worktrees `fail-closed-switch` and `fail-closed-revert` from main.

### Tasks

- [ ] **1.1 The switch on** (FR-1): `release.fail_closed: true` with a comment naming the drill and the revert; `scripts/release-policy.sh . fail-closed` prints `true`; the pull request with a TL;DR; the owner merges
- [ ] **1.2 The dispatch** (FR-2): the owner dispatches `build.yml` on main with `image: drill-app`, told what it publishes (M17: a release attempt; here the push of a digest that is then refused); the run read: its id, the pushed digest, the scan step's per-manifest lines, the gate's error line, the skipped steps, the build gate red
- [ ] **1.3 The registry read** (FR-3, first half): the manifest fetched by digest, `cosign download signature` and `cosign download attestation` returning nothing, the tag list still referencing the published digest
- [ ] **1.4 The switch off** (FR-4): `release.fail_closed: false`, the comment recording the run; the pull request; the owner merges the same day, or says the switch stays on

### Verification (orchestrator)

- [ ] Every number in 1.1 to 1.4 read from the API or the registry, none predicted

## Phase 2: the evidence (2026-10-27 draft, 2026-10-28 ready)

Dependency: 1.3 read. Worktree `fail-closed-evidence` from main.

### Tasks

- [ ] **2.1 The draft** (FR-5): the LOG entry (the switch, the refusal, the registry, the switch back), ledger rows 2.11 and 2.13 `exercised` with the run id, inducer `switch`; the task table row for 16.9; `tasks.md` 16.9 ticked naming 16.6 as the way out; `tasks/todo.md`; this plan's ticks; `conductor/tracks.md` to Completed; `metadata.json`; `conductor/index.md`; opened as a draft
- [ ] **2.2 The frozen half** (FR-3, second half): the scheduled run of 2026-10-28 read, the status data listing drill-app's tagged digest only; the LOG entry's last paragraph; the pull request made ready; the owner merges
- [ ] **2.3 The hand-over**: 16.6's track after 16.5's evidence merges, on the owner's word; the frozen digest left in place for 16.12 if that drill wants it

### Verification (orchestrator)

- [ ] `scripts/lint-live-evidence.sh .` (141 exercised), `scripts/lint-log-anchors.sh all .` green; validate green on the evidence pull request

## Final verification

- [ ] FR-1 to FR-5 each have their evidence in the LOG entry, the ledger or this plan
- [ ] Four pull requests merged by squash (phase 0, the switch, the revert or the owner's word, the evidence); one dispatch
- [ ] 16.6 named as the way out in `tasks.md` and `tasks/todo.md`

## Deviations log

| Date | Task | Deviation | Reason | Resolution |
| --- | --- | --- | --- | --- |

---
