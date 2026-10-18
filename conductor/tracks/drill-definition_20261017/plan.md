# Implementation plan: The drill definition and its first findings

**Track ID:** drill-definition_20261017
**Spec:** [spec.md](./spec.md)
**Created:** 2026-10-17
**Status:** [~] in progress (phase 1 started 2026-10-18)

## Overview

Three phases. Phase 1 builds the definition and the declaration by TDD and opens the drill's pull request, whose first CI run is red by design: the gate names the two findings and govulncheck measures them. Phase 2 is the decisions, one finding at a time, the owner's calls on that evidence, written into the lane with the LOG entry; the gate turns green and the owner merges. Phase 3 observes the publish and the first rescan, records the evidence in the ledger and the LOG, ticks 16.2 and closes the track in its own small pull request. The working rules are `conductor/workflow.md`'s: one test per slice, RED and GREEN as separate agents, the orchestrator commits, signed commits, a `## TL;DR` at the top of every pull request body.

Dependency: the spec amendment of the open question (the HIGH decided in 16.2) is the owner's call before phase 2 writes anything into the lane; phase 1 does not depend on it.

## Phase 1: the definition and the declaration (one pull request, red by design)

The definition is data; the one behaviour the repository can test is its own live state. The slice is the probe lint's live-state guard: it asserts the counts of this repository, so it is the red test that the definition and its entries turn green.

### Tasks (one slice: RED agent, GREEN agent, orchestrator commit)

- [x] **1.1 RED: the live-state guard asserts the drill** (FR-2) (39dd8b8): `scripts/lint-probes_test.sh` case 13 expects `8 active definition(s)`, `1 declared none` and `drill-app: proof none` on this repository; fails on main's seven and zero
- [x] **1.2 GREEN: the definition, the active-set entry, the proofs entry** (FR-1, FR-2) (7790601): `image/drill-app/image.yaml` copied from hardened-app and adapted as FR-1 lists (name, image, tags, release date, source, checksum, authenticity marker, spdx, `-w` only, outputs, entrypoint, annotation); `drill-app` in `active_set`; the `proofs` entry with its reason; case 13 green, every suite green
- [x] **1.3 Named a drill in the tables** (FR-3) (the docs commit; docs/CONVENTIONS.md's proofs paragraph updated too): the README's `image/` row and the manual's definitions row (no test; two sentences)
- [ ] **1.4 The pull request**: title `feat: the drill definition joins the catalogue with the first declared none proof (Req 1.13, 1.14, 5.9; task 16.2)`, body with a TL;DR that says the gate is red by design until the decisions land, and the evidence section filled from the first run

### Verification (orchestrator)

- [ ] `scripts/lint-probes_test.sh` green (13 cases); all 41 suites green
- [ ] The fourteen repository lints green, among them `scripts/lint-probes.sh .` printing the drill's line and `8 active definition(s)`, `scripts/lint-active-set.sh .` printing `8 active, 0 inactive`, `scripts/render-tracking.sh --check` unchanged; `yamllint`; `node test/renovate/managers.test.mjs`
- [ ] The pull request's first run: validate green with the line (5.9 evidence: run id noted); build gate red naming CVE-2017-20146 and CVE-2025-30204 (6.1); the govulncheck table (6.13); the Grype step ran; the error annotation and the table copied verbatim into the scratchpad for the LOG entry (checkpoint: the evidence is in)

## Phase 2: the decisions (the same pull request)

No behaviour is added, so there is no red test: the lane's lints are the tests. The agent drafts the entries and the LOG text from the run's evidence; the owner decides each finding, one at a time, in reach order; nothing is written into the lane before the decision (the owner's standing rule).

### Tasks

- [ ] **2.1 The spec amendment of the open question** merged, or re-decided by the owner (the HIGH decided in 16.2); the plan's 2.3 follows the decision
- [ ] **2.2 CVE-2017-20146 (CRITICAL)**: the rungs walked with the evidence (fix 1.3.0 available and declined, avoidance available and declined, not_affected unavailable for a reachable symbol, transfer has no owner but the owner): `accept`, `decided_at` the decision date, `expired_at` within 30 days, `paths: ["usr/local/bin/drill-app"]`, the purl, `issue` the drill-app repository, `ref` the LOG anchor, `blocked` and `statement` one line each
- [ ] **2.3 CVE-2025-30204 (HIGH)**: the same rungs; `accept` within 90 days (the entry 16.3 will re-decide), or as the owner re-decides the open question
- [ ] **2.4 The LOG entry** `## <date>: the drill definition joins the catalogue, two findings decided (task 16.2)`: the definition, the gate's run and annotation, the govulncheck table, the decisions in the LOG's rung format, the ceilings, the exit conditions (16.6 fixes, 16.16 retires); the entries' `ref` anchors point at it
- [ ] **2.5 The second run**: the exception tiers step green (Req 6.50), the scan gate `nothing uncovered within the aperture`, the VEX portability block listing both as affected; the pull request body's TL;DR rewritten with the decisions; the owner merges (checkpoint)

### Verification (orchestrator)

- [ ] `scripts/lint-accepted-risk.sh`, `scripts/lint-log-anchors.sh statements`, `scripts/lint-live-evidence.sh` green locally; `yamllint triage/accepted-risk/drill-app.yaml`
- [ ] `scripts/check-exceptions.sh gate` rehearsed locally against the run's `trivy.json` artifact and a KEV snapshot from `github.com/cisagov/kev-data` (the cisa.gov feed is unreachable from the container), expecting no breach
- [ ] The run ids of both pull request runs noted for the ledger and the LOG

## Phase 3: the publish, the first rescan, the evidence (a small pull request)

### Tasks

- [ ] **3.1 The publish observed** (FR-6): main's build run, the three tags and the platform manifest digests; the package's visibility checked anonymously the way `check-visibility.sh` does; the owner sets it public if the first publish left it private (OPERATOR)
- [ ] **3.2 The first rescan observed** (FR-7): the enumeration lists the drill's tags, the visibility invariant passes, what happened to the two findings (issues filed and closed with `resolved:accepted`, or the status row under the exceptions) quoted as the run shows it
- [ ] **3.3 The ledger** (FR-8): row 5.9 to `exercised` with the validate run id and the date; the induced-by column `drill definition`
- [ ] **3.4 The LOG addendum**: the publish and rescan facts under the phase 2 entry
- [ ] **3.5 The ticks**: 16.2 `[done <date>, #<pull request>]` in `tasks.md`; this plan's checkpoints; `conductor/tracks.md` to Completed; `metadata.json`; `conductor/index.md`

### Verification (orchestrator)

- [ ] `scripts/lint-live-evidence.sh`, `scripts/lint-log-anchors.sh statements` green; the fourteen repository lints green
- [ ] The pull request merged (track complete)

## Final verification

- [ ] FR-1 to FR-8 each have their evidence in the LOG entry or the ledger
- [ ] Both pull requests merged by squash
- [ ] `tasks/todo.md`'s program section says 16.2 is done and names 16.3 as next (16.8's drill input first, since the KEV attribution needs it)

## Deviations log

| Date | Task | Deviation | Reason | Resolution |
| --- | --- | --- | --- | --- |
| 2026-10-17 | phase 2 | No red test: the decisions are data in the lane | The lane's lints already specify the shape; a test that asserts a decision would decide it | The lints run locally before every push; the gate's second run is the verification |

---

**Plan created:** 2026-10-17
**Last updated:** 2026-10-17 (drafted with the track; pending the owner's confirmation and the open question)
