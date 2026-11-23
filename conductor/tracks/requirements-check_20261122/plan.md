# Implementation plan: The requirements checked against the code

**Track ID:** requirements-check_20261122
**Spec:** [spec.md](./spec.md)
**Created:** 2026-11-22
**Status:** [~] in progress

## Overview

Four phases. Phase 0 is this pull request: the track and task group 20; the owner confirms by merging. Phase 1 reads every criterion against the code and writes the review; it changes nothing else. Phase 2 puts each finding to the owner and records the dispositions. Phase 3 fixes what the owner decides, one pull request per cluster, code test-first with separate RED and GREEN agents. Phase 4 records the evidence and closes the track. Each phase ends with a read-only review by a separate agent.

## Phase 0: the track (this pull request)

- [ ] **0.1 The track**: this folder, `conductor/tracks.md`, `conductor/index.md`
- [ ] **0.2 Task group 20** in `tasks.md` and its coverage note; the open item in `tasks/todo.md` points here
- [ ] **0.3 The pull request**; the owner merges

## Phase 1: the reading (task 20.1)

- [x] **1.1 Nine readings**, one read-only agent each, at one commit of `main`: Requirements 1, 2, 3, 4, 5, 6 (criteria 1 to 30), 6 (31 onward), 7, 9. Each gives per criterion the mechanism (`file:line`) and the verdict, and per reader document of its group the statements the code does not bear out
- [x] **1.2 The re-check**: every PARTIAL, NOT HELD and document finding read again by a second agent that has not seen the first one's reasoning, only its claim; what does not survive is dropped with its reason
- [x] **1.3 The phase-5 findings** confirmed or refuted, each by a run where one can be read (the Renovate run's log for the Actions bumps; a scratch copy of the recipe for `pipefail`)
- [x] **1.4 `review.md`** in this folder: the method, the counts against 2026-09-09, the findings numbered by requirement group; a pull request with the review alone
  - Done 2026-11-23 at commit b8f1844: nine readers and seven re-checks, every output saved raw in `readings/` with its checksum (the owner's call of 2026-11-23). 162 criteria: 93 held, 63 partial, 2 not held, 4 owner-side. 131 reader findings, 124 confirmed, 6 narrowed, 1 refuted; merged into 94 (4 high, 34 medium, 56 low); three claims no re-checker saw held out. The Renovate run's log could not be read from this machine (its storage host is outside the firewall's list), so that finding rests on the code, a reproduction on a copy, and git history. A read-only review held the synthesis against the raw files: eight tracing fixes, all taken

## Phase 2: the dispositions (task 20.2)

- [ ] **2.1 Each finding put to the owner** with what it is, today's behaviour, who is affected, the options with cost and risk, and a recommendation; the owner's call recorded in `review.md` with its date
- [ ] **2.2 The fix clusters**: the dispositions grouped into pull requests and ordered, consumer and release exposure first; this plan's phase 3 written out from them

## Phase 3: the fixes (task 20.3)

- [ ] **3.x One cluster per pull request**, written out by 2.2: code test-first (one behaviour per slice, a failing test by one agent committed before the code by another), the documents and `docs/lanes.md` in the same pull request, the ledger rows whose mechanism changed brought up to date; each ends with a read-only review

## Phase 4: the evidence (task 20.4)

- [ ] **4.1** The LOG entry, the ledger, task group 20 ticked, this track closed

## Final verification

- [ ] Every FR's acceptance criteria met
- [ ] The link check, `render-verification.sh --check`, `lint-live-evidence.sh`, `lint-log-anchors.sh` and every suite green
