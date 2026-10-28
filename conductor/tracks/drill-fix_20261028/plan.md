# Implementation plan: The drill's findings fixed, the issue closed on the attested SBOMs, the fix clock, live

**Track ID:** drill-fix_20261028
**Spec:** [spec.md](./spec.md)
**Created:** 2026-10-28
**Status:** [~] in progress (phase 0 opened 2026-10-28)

## Overview

Three phases, three pull requests, no code. Phase 0 is this pull request: the track and the amendment of task 16.6's text; the owner confirms by merging. Phase 1 is the fix: the bump pull request (green at the gate by the fix), its merge, the release on main read from the run and the registry. Phase 2 is the closure and the clock on the next scheduled rescan (2026-10-29, about 04:00 to 06:30 PDT) and the evidence pull request that day, which also retires the moot exception, with the hand-over to 16.7.

## Phase 0: the track and the task text (this pull request)

### Tasks

- [ ] **0.1 The amendment** (task 16.6): the bullet gains the dated sentence (the hand bump in the fetch phase rather than a Renovate bump; the exception retired as moot; the fix clock from the status's first-seen dates)
- [ ] **0.2 The track**: this folder, `conductor/tracks.md`, `conductor/index.md`, the todo's 16.6 item
- [ ] **0.3 The pull request**: title `conductor: track drill-fix_20261028, the drill's findings fixed, the issue closed on the attested SBOMs, the fix clock (Req 6.46, 6.52, 6.56; task 16.6)`, a TL;DR; the owner merges (checkpoint)

### Verification (orchestrator)

- [ ] The six FR statements in EARS shape; `scripts/lint-live-evidence.sh .` green (no row changes here); no em-dashes in the added lines; no closing keyword before an issue number

## Phase 1: the fix (2026-10-28)

Dependency: phase 0 merged. Worktree `drill-fix` from main.

### Tasks

- [ ] **1.1 The bump** (FR-1): the `go/bump@v2` step with the two deps and their Renovate markers, a comment naming the drill and the drop (16.7); the pull request with a TL;DR; the build of drill-app green at the gate, govulncheck clean; the owner merges
- [ ] **1.2 The release** (FR-2): main's push build read: the run id, the new digest, the tags moved (registry read), the attested OpenVEX with no statement for either finding

### Verification (orchestrator)

- [ ] Every number in 1.1 and 1.2 read from the API or the registry, none predicted

## Phase 2: the closure, the clock, the evidence (2026-10-29)

Dependency: 1.2 read. Worktree `drill-fix-evidence` from main.

### Tasks

- [ ] **2.1 The closure and the clock** (FR-3, FR-4): the scheduled run read: #325's closing comment and label, the status rows and aggregates, the JSON block's fix times, the page
- [ ] **2.2 The exception retired** (FR-5): CVE-2017-20146's entry removed as moot, the header updated; the lints green
- [ ] **2.3 The evidence** (FR-6): the LOG entry; ledger rows 6.46, 6.52 and 6.56 appended; the task table row for 16.6; `tasks.md` 16.6 ticked; `tasks/todo.md` to 16.7; this plan's ticks; `conductor/tracks.md` to Completed; `metadata.json`; `conductor/index.md`; the owner merges
- [ ] **2.4 The hand-over to 16.7**: 16.7's track on the owner's word (the bump step dropped, a new release, the findings back in the supported digest's report, #325 reopened with its original first-seen date)

### Verification (orchestrator)

- [ ] `scripts/lint-live-evidence.sh .` (141 exercised), `scripts/lint-log-anchors.sh all .`, `scripts/lint-accepted-risk.sh .` green; validate green on the evidence pull request

## Final verification

- [ ] FR-1 to FR-6 each have their evidence in the LOG entry, the ledger or this plan
- [ ] Three pull requests merged by squash (phase 0, the bump, the evidence)
- [ ] Task 16.7's track is next in `tasks/todo.md`

## Deviations log

| Date | Task | Deviation | Reason | Resolution |
| --- | --- | --- | --- | --- |

---
