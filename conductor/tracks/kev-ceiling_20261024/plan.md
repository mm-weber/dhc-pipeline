# Implementation plan: The KEV ceiling on a standing exception, both arms refuse by name, live

**Track ID:** kev-ceiling_20261024
**Spec:** [spec.md](./spec.md)
**Created:** 2026-10-24
**Status:** [x] completed (phase 0 in #318, merged 2026-10-25 as a764a23; phase 1 in #319, merged 2026-10-25 as 714614f; phase 2 the evidence in #320, 2026-10-25)

## Overview

Three phases, three pull requests, two dispatches, no code. Phase 0 is this pull request: the track and the amendment of task 16.3's text (the order, the gate's branch, the one-day expiry); the owner confirms by merging. Phase 1 is the drill: the owner dispatches the rescan with `drill: kev-synthetic` while the standing 90-day exception runs (the rescan's refusal, Req 6.51, the run publishing with KEV yes), then one pull request whose first commit makes the gate refuse the same exception (Req 6.50) and whose second commit re-decides it to one day from its decision date D, flips ledger rows 6.50 and 6.51 and drops the drill lines; the owner merges it. Phase 2 is a second dispatch for the pass and the evidence pull request, a draft until that run is in. The whole of phases 1 and 2 fits one day: a dispatch takes twenty minutes, a drill-app build six, validate three. Trivy counts the finding again from 00:00 UTC of D plus one and the compiler can name the lapse from D plus two, task 16.4's second half; 16.4's track opens on D, the day phase 1 merges.

The owner's calls: 2026-10-24, keep the total expiry short, no waiting on an arbitrary timeline; 2026-10-25, shorter than the four days drafted from 16.4's text. One day, not zero: the spec's FR-3 notes say why (Trivy's midnight rule). Revised in this pull request before the owner confirmed it.

## Phase 0: the track and the task text (this pull request)

### Tasks

- [x] **0.1 The amendment** (task 16.3, a note on 16.4): 16.3's bullet gains the dated sentence (the finding listed by the `kev-synthetic` input, the rescan's half first on the standing exception, the gate's half on the drill pull request's first commit, the correction's one day (four until 2026-10-25) as 16.4's re-decision, the second dispatch for the pass); 16.4's bullet notes that the re-decision is 16.3's correction and names Trivy's midnight rule
- [x] **0.2 The track**: this folder, `conductor/tracks.md`, `conductor/index.md`, the todo's 16.3 and 16.4 items
- [x] **0.3 The pull request**: title `conductor: track kev-ceiling_20261024, the KEV ceiling on the drill's standing exception (Req 6.50, 6.51; task 16.3)`, a TL;DR; the owner merges (checkpoint: #318, squash a764a23, 2026-10-25 11:09Z; revised to one day before the merge)

### Verification (orchestrator)

- [x] The six FR statements in EARS shape (WHEN/THE ... SHALL); `scripts/lint-live-evidence.sh .` green (no row changes here); no em-dashes in the added lines; no closing keyword before an issue number

## Phase 1: the listing, the refusals, the re-decision (one dispatch, one pull request)

Dependency: phase 0 merged. Worktree `kev-ceiling-drill` from main.

### Tasks

- [x] **1.1 The listing run** (FR-1): done 2026-10-25, run 40187973579 (job 121152713348; the invariants step red at 11:24:49Z with the breach line, the status published at 11:30:36Z with KEV yes, the page at 11:31:01Z); the owner dispatched at 11:13:41Z, before the day's scheduled run, which had not started by then. As planned: the owner dispatches `rescan.yml` with `drill: kev-synthetic` after the day's scheduled run, told beforehand what the dispatch publishes (today's reports attested with replace, register row M17; the status issue and the page reading KEV yes on the drill definition until the next scheduled run); the run watched: the invariants step red with `triage/accepted-risk/drill-app.yaml: CVE-2025-30204 runs 90 days from 2026-10-18 to 2027-01-16, over its 14-day ceiling (listed in CISA KEV)` and the `1 exception(s) over their tier ... (Req 6.50/6.51)` line, the enrich step and the issue set run (nothing filed), the status published with KEV yes for CVE-2025-30204, the page job green, the summary's drill line; the run id, the job id and the step times recorded (the step's log as the owner reads it, on request)
- [x] **1.2 The gate's refusal** (FR-2): done 2026-10-25, #319 commit ee48046, build run 40188092683 red at step 19 at 11:20:15Z (job 121153084106), validate run 40188092562 green. As planned: the first commit on `kev-ceiling-drill`: `triage.kev_feed` set to `https://raw.githubusercontent.com/mm-weber/dhc-pipeline/main/triage/drills/kev-synthetic.json`, one comment line in `image/drill-app/image.yaml` (`# Drill 16.3, the gate's half (Req 6.50): this line alone puts drill-app in the build matrix; removed before the merge.`); the pull request opened with a TL;DR that says its first run is meant to be red; the build run red at step 19 `exception tiers against KEV (Req 6.50)` with the breach line and the `(Req 6.50/6.51)` annotation after the build and the scan; validate green; the run id recorded
- [x] **1.3 The re-decision** (FR-3): done 2026-10-25, #319 commit 1c72e48, merged 11:55:37Z as 714614f (the squash touches the exception file, the LOG, the ledger, the plan and the spec; neither drill line). As planned: the second commit: `decided_at: D`, `expired_at: D plus one day`, the statement `accept: live-drill fixture, never installed; the finding is the drill (task 16.2), re-decided against the KEV ceiling by drill 16.3 (one day; drill 16.4 watches the lapse), fixed by drill 16.6`, `ref` anchored to the new LOG heading; the LOG entry `## <D>: the drill's HIGH listed as exploited by the synthetic feed, the standing exception refused in both arms, re-decided to one day (task 16.3)` with part one (the listing run, the gate's refusal, the re-decision argued: accept stays the treatment for the reasons of 2026-10-18, one day is within the KEV tier and is 16.4's window, the lapse from D plus one is intended) and the subsection heading the `ref` cites; ledger rows 6.50 and 6.51 `exercised`, dated, with the run ids, inducer `drill input`, the task table row for 16.3 naming the inducers; the feed line and the comment line removed; `scripts/lint-accepted-risk.sh .` green with its one expiry warning; the pull request's build matrix empty on this commit, validate green; the TL;DR updated; the owner merges (checkpoint: the squash sha)

### Verification (orchestrator)

- [x] `scripts/lint-accepted-risk.sh .` (one warning, CVE-2025-30204, `expires in 1 days`), `scripts/lint-log-anchors.sh all .` (the new `ref` resolves), `scripts/lint-live-evidence.sh .` (121 exercised) green; the pull request's diff is the exception file, the LOG and the ledger (and the plan's and the spec's ticks); no em-dashes; no closing keyword before an issue number; the merge rebuilds and releases nothing (main's push build names no definition). Deviation: the second commit's own build named drill-app (see the log below)

## Phase 2: the pass and the evidence (one dispatch, a draft pull request until the pass is in)

Dependency: phase 1 merged. Worktree `kev-ceiling-evidence` from main.

### Tasks

- [x] **2.1 The pass** (FR-4): done 2026-10-25, run 40191153604 (job 121162258991; the invariants step green at 12:08:34Z, the status published at 12:14:23Z with KEV yes, the page at 12:14:46Z). As planned: the owner dispatches `rescan.yml` with `drill: kev-synthetic` after the merge, told what the dispatch publishes (M17); the invariants step green (`check-exceptions: ok drill-app CVE-2025-30204: 1 days within the 14-day ceiling (listed in CISA KEV)` as the owner reads it, or the step green with no breach annotation), the run green, the status published with KEV yes; the run id recorded
- [x] **2.2 The evidence** (FR-5, FR-6): #320. As planned: LOG part two (the pass; the next scheduled run named as the one that reads CISA's feed again and warns of the expiry, its id recorded here if it lands before this merges, else in 16.4's track's first entry); register row M26 and the manual's paragraph name both values' behaviour; `tasks.md` 16.3 ticked `[done <date>, #nnn; conductor track kev-ceiling_20261024]`; `tasks/todo.md` to 16.4 with D plus one and D plus two named; this plan's ticks; `conductor/tracks.md` to Completed; `metadata.json`; `conductor/index.md`
- [x] **2.3 The hand-over to 16.4**: 16.4's track opened 2026-10-25 after this pull request. As planned: 16.4's track opened on D, the day phase 1 merges (its first observations are this track's second dispatch and the first scheduled run after D: the expiries step's warning, the page's lapsing entry, and from 00:00 UTC of D plus one the scan counting the finding again; its second the first run of D plus two: `under_investigation` naming the lapse, the re-attestation, the gate no longer counting the entry)

### Verification (orchestrator)

- [x] `scripts/lint-live-evidence.sh .`, `scripts/lint-log-anchors.sh all .` green; the pull request opened once 2.1 was in; the owner merges (track complete)

## Final verification

- [x] FR-1 to FR-6 each have their evidence in the LOG entry, the ledger or this plan (the spec's acceptance boxes carry the run ids)
- [x] Three pull requests merged by squash (phase 0 a764a23, the drill pull request 714614f, the evidence #320); two dispatches recorded (40187973579, 40191153604)
- [x] Task 16.4's track is next in `tasks/todo.md`, its dates D plus one and D plus two named (2026-10-26, 2026-10-27)

## Deviations log

| Date | Task | Deviation | Reason | Resolution |
| --- | --- | --- | --- | --- |
| 2026-10-25 | 1.3 | The drill pull request's second commit built drill-app (run 40189524943, green); the plan and FR-3 expected an empty matrix | `build.yml` names the image a changed `triage/accepted-risk/<name>.yaml` belongs to on pull requests, so that the gate re-runs against the exception; the plan had read the image-path rule alone | Recorded here and in FR-3's acceptance; the gate's green against CISA's feed is extra evidence, the merge built nothing (main's push build reads image paths alone) |
| 2026-10-25 | 1.1 | The owner dispatched before the day's scheduled run, which had not started by 11:33Z | The scheduled run started at 11:42Z, between the two dispatches | Recorded in the LOG: it read the standing entry and CISA's feed on a764a23, before the merge; the first scheduled run to read the re-decided entry is 2026-10-26's, drill 16.4's |

---
