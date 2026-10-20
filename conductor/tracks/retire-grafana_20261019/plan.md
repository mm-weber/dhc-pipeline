# Implementation plan: Grafana deactivated, the documented switch exercised live

**Track ID:** retire-grafana_20261019
**Spec:** [spec.md](./spec.md)
**Created:** 2026-10-19
**Status:** [x] completed (phase 1 in #290, merged 2026-10-19; phase 2 the evidence in #292 and #295, 2026-10-20)

## Overview

Two phases. Phase 1 is one pull request: the switch by TDD (the probe lint's live-state guard turns red at seven active definitions and green when grafana's line is gone and the tracking block re-rendered), the two rows, the twelve moot exceptions retired, the LOG entry. Phase 2 observes the first inactive day (no build, the rescan's inactive check, Renovate's bump refused) and closes the track with the ledger rows. The rules are `conductor/workflow.md`'s: one test per slice, RED and GREEN as separate agents, the orchestrator commits, signed commits, a `## TL;DR` at the top of every pull request body.

## Phase 1: the switch (one pull request)

### Tasks (one slice: RED agent, GREEN agent, orchestrator commit)

- [x] **1.1 RED: the live-state guard asserts seven** (FR-3) (89af8b5): `scripts/lint-probes_test.sh` case 13 expects `7 active definition(s)`, `6 covered by 3 probe registration(s)` and `1 declared none`; fails on main's eight
- [x] **1.2 RED 2 and GREEN: the tracking-scope checks, the line and the tracking block** (FR-1, FR-2) (red 1233ab6, green 90d9dc2): `test/renovate/managers.test.mjs`'s tracking-scope checks assert the new block (red first, slice 2); then `grafana` removed from `active_set`, the policy file's comment amended, `scripts/render-tracking.sh .` re-renders `renovate.json5`; case 13 and the fixture test green, every suite green
- [x] **1.3 Named inactive in the tables** (FR-4) (the data commit): the README's `image/` row and the manual's definitions row (orchestrator; no test)
- [x] **1.4 The twelve moot exceptions retired** (FR-5) (the data commit): the entries decided 2026-09-03 removed from `triage/accepted-risk/grafana.yaml`, the nine of 2026-10-13 kept (orchestrator; the lane's lints are the test)
- [x] **1.5 The LOG entry** (FR-6) (2026-10-19, the data commit): `## 2026-10-19: grafana deactivated, the switch exercised live; twelve moot exceptions retired`: the reason, the four levels in one paragraph, the measured effects, the twelve by id with their fix date, the nine transfers' new exit condition, the five undecided findings named as the owner's next calls
- [x] **1.6 The pull request** (#290, opened 2026-10-19): title `chore: grafana leaves the active set, the documented switch exercised live; twelve moot exceptions retired (Req 1.13 to 1.16, 6.11; task 16.11 by nature)`, a TL;DR, the verification section from the runs

### Verification (orchestrator)

- [x] `scripts/lint-probes_test.sh` green; all 41 suites green (2026-10-19, slices 1 and 2)
- [x] (2026-10-19; the lines quoted in LOG 2026-10-19; validate run 39288882400 on the squash) The fourteen repository lints green with the lines FR-1 and FR-2 name; `scripts/lint-accepted-risk.sh .` with no expiry warning; `scripts/lint-log-anchors.sh all .`; `yamllint`; `node test/renovate/managers.test.mjs` green with its tracking-scope checks rewritten (slice 2)
- [x] (#290 merged 2026-10-19 as 04c6eeb; the e2e components cert-manager, hardened-app and valkey) The pull request's CI green; the e2e's affected-components job without grafana; the owner merges (checkpoint)

## Phase 2: the first inactive day (a small pull request)

### Tasks

- [x] **2.1 No build, no tag** (FR-7) (push build 39288882482 on the squash 04c6eeb, 2026-10-19 16:50Z: the affected-definitions job named nothing, the matrix job skipped, the gate green; the drill's build 39289978981 the same with `image/grafana/image.yaml` changed; the owner's blank dispatch of 21:49Z, run 39330433276, a release by design (register row M17, the comparator runs only on the schedule): seven definitions rebuilt and republished, 21 tags moved to new digests, grafana absent from the matrix; the registry's three grafana tags on sha256:89c5680a868b, read anonymously 16:56Z and again 06:45Z on 2026-10-20; the scheduled nightly of 2026-10-20 09:40Z, run 39402331027, named the same seven definitions with grafana absent and failed at every one's dhi.io login step (`unauthorized`, the DHI_TOKEN secret lapsed) before any build or push, so no digest moved): the first push and nightly builds after the merge carry no grafana job; the registry's grafana tags unchanged (anonymous read)
- [x] **2.2 The rescan's inactive check** (FR-7) (run 39417467219, scheduled, 2026-10-20 11:47Z to 12:12Z, the first rescan after the merge: the inactive-digest check passed with grafana the one inactive definition and its three tags; the status issue re-rendered 12:12Z with grafana's three tags on sha256:89c5680a868b and 130 grafana lines as before, while the six other repositories moved to the dispatch release's digests; the registry read anonymously 12:17Z the same): the first rescan after the merge names one inactive definition and passes; the status issue's grafana rows unchanged (the ledger's 1.15 evidence)
- [x] **2.3 The bump refused** (FR-8) (drill #291, head 3e7cb45 = Renovate's f6f89f8 replayed onto main; validate run 39289979209 red at step 14 in twelve seconds with the Req 1.16 line naming `image/grafana/image.yaml`; see the deviations log): the validate run red naming `image/grafana/image.yaml` and Req 1.16 (the ledger's 1.16 evidence); #291 closed after the evidence merges, never merged; Renovate's handling of #279 observed 2026-10-19 21:19Z (run 39323363043 attempt 2, the first with the regenerated token: #279 autoclosed, #5 without grafana)
- [x] **2.4 The ledger and the spec** (FR-9) (row 1.16 in #292, induced by `pull request`, the drill being one; row 1.15 here, induced by `switch`; 16.11's wording; the LOG addendum in two parts, #292 and here): rows 1.15 and 1.16 to exercised with their run ids, induced by `switch`; task 16.11's wording amended; the LOG addendum
- [x] **2.5 The ticks** (2026-10-20; the todo item and the calendar line were done in #290 and #292): this plan's checkpoints; `conductor/tracks.md` to Completed; `metadata.json`; `conductor/index.md`; `tasks/todo.md`'s open item on the grafana exceptions closed and its 2026-11-02 calendar line removed

### Verification (orchestrator)

- [x] `scripts/lint-live-evidence.sh .`, `scripts/lint-log-anchors.sh all .` green; the fourteen repository lints green (2026-10-20 locally; this pull request's validate run)
- [ ] The pull request merged (track complete)

## Final verification

- [x] FR-1 to FR-9 each have their evidence in the LOG entry or the ledger (2026-10-20; the spec's acceptance boxes carry the run ids)
- [x] Both pull requests merged by squash (#290 as 04c6eeb on 2026-10-19; phase 2 in two, #292 as c089d33 on 2026-10-19 and #295, this one)
- [x] The five undecided findings and the nine transfers are named in `tasks/todo.md` as the owner's open calls, with 2026-12-12 on the calendar (the frozen-image item and the calendar line, since #290)

## Deviations log

| Date | Task | Deviation | Reason | Resolution |
| --- | --- | --- | --- | --- |
| 2026-10-19 | 2.3 | The Req 1.16 case came from drill #291, not from a rebase of Renovate's #279 | FR-2's rendered ignore paths take `image/grafana/**` out of Renovate's extraction, so the bot prunes the 13.1.x branch instead of rebasing it; its 15:23Z and 20:55Z runs (39277512324, 39323363043) had failed at startup, the token having expired that day; regenerated by the owner, the re-run of 21:17Z was green | The drill task 16.11 words: Renovate's commit f6f89f8 replayed unchanged onto main as draft #291, refused live on 39289979209; FR-8's note and acceptance amended; #279's autoclose by Renovate observed as the tracking-scope evidence instead of a refusal |
| 2026-10-19 | phase 2 | The evidence landed in two pull requests, #292 and #295, not one | #292 said part two was to come before the merge and was merged at 21:44Z; arriving evidence goes in a draft (tasks/lessons.md, 2026-10-19) | #295 opened as a draft and marked ready once the rescan had run |
| 2026-10-20 | 2.1 | The first nightly after the merge failed at every dhi.io login (run 39402331027) | The `DHI_TOKEN` secret was no longer accepted on 2026-10-20, the day after `RENOVATE_TOKEN` expired; unrelated to the switch | The matrix (seven, grafana absent) stands as evidence; the owner rotates the token; the owner's dispatch of 2026-10-19 21:49Z had supplied the publish-side evidence, a release by design (tasks/lessons.md, 2026-10-20) |
| 2026-10-19 | 1.2 | A second test pinned the live state: `test/renovate/managers.test.mjs`'s tracking-scope checks asserted that the reference ignores no path and built the fork fixture by removing grafana's line | Found by the GREEN agent running the fixture test (166 of 168 checks); the track's spec and plan had called the test unchanged | Slice 2, red first: the checks assert the new block (grafana's two paths) and the fixture deactivates hardened-app, expecting four paths; the spec's FR-2 note corrected |

---

**Plan created:** 2026-10-19
**Last updated:** 2026-10-20 (phase 2 complete; the track closes with #295)
