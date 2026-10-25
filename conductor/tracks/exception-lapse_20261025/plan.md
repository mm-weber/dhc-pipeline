# Implementation plan: The drill's exception expires, the lapse seen on every plane, live

**Track ID:** exception-lapse_20261025
**Spec:** [spec.md](./spec.md)
**Created:** 2026-10-25
**Status:** [~] in progress (phase 0 opened 2026-10-25)

## Overview

Three phases, three pull requests, no code, no dispatch required. Phase 0 is this pull request: the track and the amendment of task 16.4's text; the owner confirms by merging. Phase 1 is the two days: the scheduled run of 2026-10-26 (Trivy counts the finding, the document recompiled and re-attested, the status undecided, the issue filed, the expiries step at 0 days), the drill pull request that day (the gate red by name), the scheduled run of 2026-10-27 (the lint's `is in the past`, the page's lapsed entry, the compiler's lapse note). Phase 2 is the evidence pull request on 2026-10-27, which also removes the lapsed entry so that validation is green again, and the hand-over to 16.5. In the owner's clock (PDT): the first day begins at 17:00 on 2026-10-25, the second at 17:00 on 2026-10-26; the scheduled runs land about 04:15 to 05:00 the next morning.

## Phase 0: the track and the task text (this pull request)

### Tasks

- [ ] **0.1 The amendment** (task 16.4): the bullet gains the dated sentence (the two clocks; the rescan's re-attestation recompile carries the lapse into the attested document, first seen carried, the note on the second day; the entry removed at the end for 16.5; validation red on the second day by design)
- [ ] **0.2 The track**: this folder, `conductor/tracks.md`, `conductor/index.md`, the todo's 16.4 item
- [ ] **0.3 The pull request**: title `conductor: track exception-lapse_20261025, the drill's exception expires, the lapse on every plane (Req 6.9, 6.10, 6.41; task 16.4)`, a TL;DR; the owner merges (checkpoint)

### Verification (orchestrator)

- [ ] The six FR statements in EARS shape; `scripts/lint-live-evidence.sh .` green (no row changes here); no em-dashes in the added lines; no closing keyword before an issue number

## Phase 1: the two days (no pull request merges)

Dependency: phase 0 merged. Worktree `exception-lapse-drill` for the drill pull request.

### Tasks

- [ ] **1.1 Day one, 2026-10-26** (FR-1, FR-2): the scheduled run read: its id, the expiries annotation (`0 days`), the re-attestation record for drill-app, the status issue's row (undecided, first seen 2026-10-18, the age), the new cve issue's number, the page's card; the owner's dispatch instead, if they choose it, told what it publishes (M17)
- [ ] **1.2 The gate** (FR-3): the drill pull request on `exception-lapse-drill`, one commit, one comment line in `image/drill-app/image.yaml` (`# Drill 16.4, the gate's half (Req 6.9): this line alone puts drill-app in the build matrix; never merged.`), opened as a draft with a TL;DR that says it is meant to be red; the build run red at the scan gate naming CVE-2025-30204; validate green (day one) or red (day two, the past expiry); the run id recorded
- [ ] **1.3 Day two, 2026-10-27** (FR-4): the scheduled run read: the expiries annotation (`is in the past`), the page's lapsed entry, the compiled document's lapse note (the re-attestation record, or the attested document read through verification), validate's red on any pull request of the day

### Verification (orchestrator)

- [ ] Every number in 1.1 to 1.3 read from the API or the owner's pasted log lines, none predicted

## Phase 2: the evidence and the hand-over (one pull request, 2026-10-27)

Dependency: 1.3 observed. Worktree `exception-lapse-evidence` from main.

### Tasks

- [ ] **2.1 The entry leaves** (FR-5): CVE-2025-30204's entry removed from `triage/accepted-risk/drill-app.yaml`, the header comment updated; `scripts/lint-accepted-risk.sh .` green
- [ ] **2.2 The evidence** (FR-6): the LOG entry `## 2026-10-26: the drill's exception expires, the lapse on every plane (task 16.4)` (day one, the gate, day two, the removal, the two clocks as observed); ledger rows 6.9, 6.10, 6.41 `exercised` with the run ids, inducer `drill definition`; the task table row for 16.4; `tasks.md` 16.4 ticked; `tasks/todo.md` to 16.5; this plan's ticks; `conductor/tracks.md` to Completed; `metadata.json`; `conductor/index.md`; the owner merges; the drill pull request closed with a comment
- [ ] **2.3 The hand-over to 16.5**: 16.5's track opened the day this merges (the HIGH ceiling lowered to one day for one rescan through a pull request, the finding undecided since 2026-10-18 reported over its ceiling)

### Verification (orchestrator)

- [ ] `scripts/lint-live-evidence.sh .` (124 exercised), `scripts/lint-log-anchors.sh all .`, `scripts/lint-accepted-risk.sh .` green; validate green on the evidence pull request (the lapsed entry gone)

## Final verification

- [ ] FR-1 to FR-6 each have their evidence in the LOG entry, the ledger or this plan
- [ ] Three pull requests: phase 0 and the evidence merged by squash, the drill pull request closed unmerged
- [ ] Task 16.5's track is next in `tasks/todo.md`

## Deviations log

| Date | Task | Deviation | Reason | Resolution |
| --- | --- | --- | --- | --- |

---
