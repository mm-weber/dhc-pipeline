# Implementation plan: The KEV drill input, a feed outage fails closed in both arms, live

**Track ID:** kev-drill-input_20261023
**Spec:** [spec.md](./spec.md)
**Created:** 2026-10-23
**Status:** [~] in progress (phase 0 merged 2026-10-23 as a5decb6, #308; phase 1 merged 2026-10-23 as 9e62294, #310; phase 2 started 2026-10-23)

## Overview

Three phases. Phase 0 is this pull request: the spec amendment (7.7 and 7.10, a dispatch input is a declared value the policy lint holds) and the track; the owner confirms by merging. Phase 1 is one pull request built by TDD: five slices (three on the workflow-policy lint, two on the triage-policy reader), then the declarations, the workflow change, the synthetic feed and the docs, whose tests are the lints. Phase 2 is the drill: the gate's drill branch, the dispatched outage run, the next scheduled run, and the evidence pull request, opened as a draft until the last run is in. The rules are `conductor/workflow.md`'s: one test per slice, RED and GREEN as separate agents, the orchestrator commits, signed commits, a `## TL;DR` at the top of every pull request body, no closing keyword before an issue number.

## Phase 0: the spec amendment and the track (this pull request)

### Tasks

- [x] **0.1 The amendment** (Req 7.7, 7.10): 7.7 lists each dispatch input a workflow accepts with its allowed values, a drill's substitute values beside it; 7.10 names a workflow's dispatch inputs beside the schedule trigger and the permissions; the amendment log sentence; design.md's policy-file paragraph, its error-handling row and the "Live drills" section name the drill input
- [x] **0.2 The track**: this folder, `conductor/tracks.md`, `conductor/index.md`, the todo's program state
- [x] **0.3 The pull request**: title `conductor: track kev-drill-input_20261023, the KEV drill input (Req 6.59, 6.60, 7.7, 7.10; task 16.8)`, a TL;DR; the owner merges (checkpoint)

### Verification (orchestrator)

- [x] (2026-10-23, #308 merged as a5decb6) The ten FR statements pass the EARS validator in its acceptance-criteria shape; `scripts/lint-live-evidence.sh .` green after the requirements change; no em-dashes in the added lines; no closing keyword before an issue number

## Phase 1: the input, the declarations, the lint, the reader (one pull request)

Dependency: phase 0 merged. Worktree `kev-drill-input` from main.

### Tasks (slices 1.1 to 1.5: RED agent, GREEN agent, orchestrator commit)

- [x] **1.1 RED and GREEN: an undeclared dispatch input fails naming the workflow and the input** (FR-5) (red e36aa16, green 4a845bf): `scripts/lint-workflow-policy_test.sh` case 9 gives the fixture's `cron.yml` a `workflow_dispatch` input `drill` (choice, options `[none, kev-outage]`, default `none`) with no `inputs` declaration; expects exit 1, `cron.yml` and `drill` in the output. GREEN: the lint reads `on.workflow_dispatch.inputs` (a bare `workflow_dispatch:` is empty) and compares each input against `decl.inputs`
- [x] **1.2 RED and GREEN: a declared input absent from its workflow fails naming it** (FR-5) (red d9341b0, green 1ec4572): case 10 declares `inputs: {drill: ...}` for `plain.yml`, which carries none; expects exit 1 naming `plain.yml` and `drill`
- [x] **1.3 RED and GREEN: a differing value fails naming the input and both values; a matching pair passes** (FR-5) (red d24ec69, green 20baab5): case 11 declares options `[none, kev-outage]` and the workflow carries `[none, kev-synthetic]`; expects exit 1 naming `drill` and both lists. The fixture's `fresh` gains the input on `cron.yml` and its declaration from this slice on, so case 1 proves the match (`description` dropped before the comparison)
- [x] **1.4 RED and GREEN: `drill-feed <name>` prints the declared substitute** (FR-4) (red 81cb0de, green e8a7d1e): `scripts/triage-policy_test.sh` gives the fixture `drills: {kev-outage: https://kev-feed.invalid/kev.json}`; `q drill-feed kev-outage` prints it
- [x] **1.5 RED and GREEN: `drill-feed` refuses `none`, an undeclared name and a missing map** (FR-4) (red 72e6b9b, green 956695f): exit 2 and the name or the hole in the message, one test per behaviour in the suite's style (three assertions, one slice: they are one refusal shape)
- [x] **1.6 The declarations and the workflow** (72bab3f) (FR-1, FR-2, FR-3; orchestrator, the lints are the test): `catalogue-policy.yaml` gains `triage.drills` (both addresses, a comment naming what reads them and why `.invalid`), `workflows.build.yml.inputs.image` (`required: false`, `type: string`) and `workflows.rescan.yml.inputs.drill` (choice, the three options, default `none`); `rescan.yml` gains the input, the job env `DRILL`, the lookup with its `::warning::` annotation, the drill's name in the outage error line, the `drill` and `feed` outputs, and the summary line; the reader's header and usage line name `drill-feed`
- [x] **1.7 The synthetic feed** (6ba42ea) (FR-6): `triage/drills/kev-synthetic.json`, one entry, CVE-2025-30204, titled DRILL
- [x] **1.8 The docs** (6c802de, the row renumbered in 1da95af) (FR-10): the manual's two rescan rows and the dispatch sentence; register row M20; the policy file's comments
- [x] **1.9 The pull request** (#310, merged 2026-10-23 as 9e62294): title `feat: the KEV drill input on the rescan's dispatch, a declared value substituted for one run (Req 6.59, 6.60, 7.7, 7.10; task 16.8)`, a TL;DR naming what the drill run publishes and withholds; the owner merges (checkpoint)

### Verification (orchestrator)

- [x] (2026-10-23) `scripts/lint-workflow-policy_test.sh` (13 cases, two more than planned: both directions and the value comparison each got their own) and `scripts/triage-policy_test.sh` (34 assertions) green; all 41 suites green
- [x] (2026-10-23, locally; the substitution rehearsed with DRILL=kev-outage: curl exit 6, could not resolve host, the Req 6.60 line naming the drill and the address) On this repository: `scripts/lint-workflow-policy.sh .` prints its all-green line; `scripts/lint-rescan-steps.sh`; `yamllint .github/workflows/rescan.yml catalogue-policy.yaml`; `scripts/release-policy.sh . check`; `scripts/triage-policy.sh . drill-feed kev-outage` prints the address, `drill-feed none` refuses; `jq -r '.vulnerabilities[].cveID' triage/drills/kev-synthetic.json` prints the CVE; the fourteen repository lints
- [x] (2026-10-23, #310 on 0ee1e95: seven jobs green, the build and e2e matrices skipped, no definition changed) The pull request's validate run green; its build run names nothing (no definition changed)

## Phase 2: the drill (a draft pull request, ready when the last run is in)

Dependency: phase 1 merged. Worktree `kev-drill-evidence` from main for the evidence; branch `drill-kev-outage-gate` from main for the gate's drill, a draft pull request that never merges.

### Tasks

- [x] **2.1 The gate's drill branch** (FR-7) (draft #313, commit 1b221d8; build run 40021724071 red at step 19 `exception tiers against KEV (Req 6.50)` at 20:50:49Z, job 120647720657, after the build and the scan; validate run 40021724024 green): `triage.kev_feed` set to the outage address, one comment line in `image/drill-app/image.yaml`; draft pull request; the build run red at `exception tiers against KEV` with the Req 6.59 line naming the address; validate green; the run id recorded
- [x] **2.2 The outage run** (FR-8) (run 40024066594, the owner's dispatch 21:04:35Z on 2f53e31, job 120655680352: the invariants step red 21:19:07Z naming the address and Req 6.60, the enrich (21:23:59Z) and status (21:24:00Z) refusals by name, the page job skipped, #151 unchanged; the summary's drill line is the workflow's): the owner dispatches `rescan.yml` with `drill: kev-outage` after the day's scheduled run, told beforehand what the dispatch publishes (today's reports attested with replace, the document re-attested where changed, the lifecycle applied on attested evidence) and withholds (the issue set, the status, the page); observed: the invariants step red naming the address and Req 6.60, the enrich, issue-set and status refusals by name, the page job skipped, the summary's drill line; the run id and the lines recorded
- [ ] **2.3 The next scheduled run** (FR-8): green, `- drill: none`, the status issue and the page published; the run id recorded
- [ ] **2.4 The evidence** (FR-9): ledger rows 6.59 and 6.60 to `exercised`, induced by `drill input`, with the run ids; the LOG entry `## <date>: the KEV feed outage drill, both arms fail closed by name (task 16.8)`; `tasks.md` 16.8 ticked `[done <date>, #nnn; conductor track kev-drill-input_20261023]`; `tasks/todo.md`'s program state to 16.3
- [ ] **2.5 The ticks**: this plan's checkpoints; `conductor/tracks.md` to Completed; `metadata.json`; `conductor/index.md`; the drill pull request closed unmerged with a comment once the evidence merges

### Verification (orchestrator)

- [ ] `scripts/lint-live-evidence.sh .`, `scripts/lint-log-anchors.sh all .` green; the fourteen repository lints green; the pull request a draft until 2.3 is in, then ready; the owner merges (track complete)

## Final verification

- [ ] FR-1 to FR-10 each have their evidence in the LOG entry, the ledger or this plan (the spec's acceptance boxes carry the run ids)
- [ ] Three pull requests merged by squash (phase 0, phase 1, the evidence); the drill pull request closed unmerged
- [ ] Task 16.3's track is next in `tasks/todo.md`, its spec citing the `kev-synthetic` value

## Deviations log

| Date | Task | Deviation | Reason | Resolution |
| --- | --- | --- | --- | --- |
| 2026-10-23 | 1.8 | The register's next free row is M26, not M20 | The draft read the table's first rows only, and two corrections repeated the mistake on partial reads (M20, M21, M22 all exist); the rows were counted at 1.8, after a commit with a duplicate M22 | FR-10's note and acceptance say M26; the row placed last; the duplicate corrected in a follow-up commit |
| 2026-10-23 | 1.1 | Three workflows carry dispatch inputs, not one: build.yml `image`, renovate.yml `logLevel` and `dryRun`, e2e.yml `component` | The spec's FR-5 note counted build.yml alone, from a read of build.yml and rescan.yml only | GREEN-1 declared all four inputs as literal mirrors (the GREEN agent found the two others on the real-repository run); FR-5's note corrected |

---
