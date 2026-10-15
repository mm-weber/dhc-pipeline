# Implementation plan: Proof kinds per definition

**Track ID:** proof-kinds_20261015
**Spec:** [spec.md](./spec.md)
**Created:** 2026-10-15
**Status:** pending

## Overview

Three phases, one pull request each, matching spec tasks 17.2, 17.3 and 17.4. Every code slice is one failing test followed by the smallest change that passes it. The orchestrator never implements: for each slice it dispatches a RED agent (writes exactly one test in the suite, runs it, reports the failure reason), then a GREEN agent (the minimum change, the whole suite green), then reviews the diff, runs the suite and the real-repository checks itself, and commits. Work happens in a worktree per phase (`scripts/worktree-create.sh dhc-pipeline <branch>`), branched from main after the previous phase merged.

| Phase | Pull request | Status | Progress |
| --- | --- | --- | --- |
| Phase 1: the declaration and its reader (17.2) | `feat: a per-definition proof declaration and its reader (Req 5.11, 7.7; task 17.2)` | in review (draft pull request opened 2026-10-15, merges after #271 and #272) | 100% |
| Phase 2: the probe lint honours the declaration (17.3) | `feat: the probe lint honours a declared none proof (Req 5.8 to 5.10; task 17.3)` | built 2026-10-15 on branch proof-lint (on top of phase 1); pull request opens after #273 merges | 100% |
| Phase 3: documentation and the walkthrough (17.4) | `docs: onboarding in two pull requests, the proof declaration (task 17.4)` | pending | 0% |

Dependency: pull request #271 (the spec) merged before phase 1 opens its pull request.

## Phase 1: the declaration and its reader (task 17.2)

**Objective:** `proof_entries` and `proof_of` in `scripts/definition-lib.sh`, refusing by name; `proofs: {}` in the policy file.
**Worktree:** `proof-reader`
**Suite:** `scripts/definition-lib_test.sh`; its `fresh` and `def` helpers build the sandbox, and slice 1.1 adds a `policy` helper that writes `catalogue-policy.yaml` with an active set and an optional `proofs:` block.

### Tasks (one slice each: RED agent, GREEN agent, orchestrator commit)

- [x] **1.1 No `proofs:` key prints nothing** (FR-2) (built second, as a guard: eaea528)
  - RED: a sandbox whose policy file has an active set and no `proofs:`; `proof_entries "$SB"` exits 0 with empty output. Fails because the function does not exist.
  - GREEN: the function, reading the policy file through PyYAML, printing nothing for an absent map.
- [x] **1.2 `proofs: {}` prints nothing** (FR-2) (in the same guard case: eaea528)
- [x] **1.3 A none entry prints its line, quoted date** (FR-2) (built first, the tracer bullet: red 9888b5f, green 0e6ffa9)
  - `proofs: {app: {kind: none, reason: "drill fixture", review_by: "2026-11-28"}}` with `app` active; output `app<TAB>none<TAB>drill fixture<TAB>2026-11-28`.
- [x] **1.4 A none entry with a bare date prints the same line** (FR-2, the PyYAML date object) (guard: ccafb46)
- [x] **1.5 A chart entry prints `app<TAB>chart<TAB><TAB>`** (FR-2) (guard: c75dc71)
- [x] **1.6 An unknown kind is refused** (FR-3): `kind: smoke` exits 2, names `app`, cites `Req 5.11`, prints no entry line (red 1257c35, green fdafbdb)
- [x] **1.7 A none entry without reason is refused** (FR-3) (red a090a62, green 9a52eec)
- [x] **1.8 A none entry without review_by is refused** (FR-3) (red 8be09a6, green 75fe8f5)
- [x] **1.9 A review_by that is not a date is refused** (FR-3): `review_by: soon` (red 3e4aba3, green 2c527de)
- [x] **1.10 An entry naming an inactive definition is refused** (FR-3): the directory exists, the active set does not list it (red 43cb259, green 1b8e9ff)
- [x] **1.11 `proofs:` that is a list is refused** (FR-3), and an entry that is a scalar (red 8319072, green 6bafe93)
- [x] **1.12 `proof_of` prints `chart` for an undeclared active definition** (FR-2) (red fc78027, green 02b4d40)
- [x] **1.13 `proof_of` prints the declared line and propagates a refusal** (FR-2, FR-3) (guards against 1.12's implementation: 335dcab, 0ad66df)
- [x] **1.14 The policy file gains `proofs: {}` and its comment block** (FR-1; no test: a documentation edit of a YAML file by hand, then yamllint) (4c930d0, built before the slices)

### Verification (orchestrator)

- [x] `scripts/definition-lib_test.sh` green, every existing case untouched (34 cases; 41 suites under scripts/ green)
- [x] `yamllint catalogue-policy.yaml`; `scripts/lint-active-set.sh .`; `scripts/release-policy.sh . check`; `scripts/lint-probes.sh .` (unchanged lint, still green)
- [x] `source scripts/definition-lib.sh; proof_entries .` prints nothing and exits 0 on this repository; `proof_of . hardened-app` prints chart
- [x] validate's twelve repository-level lint steps rehearsed locally after the refactor commit (7b3bf44)
- [ ] Pull request opened as a draft 2026-10-15; the owner merges after #271 and #272 (checkpoint)

## Phase 2: the probe lint honours the declaration (task 17.3)

**Objective:** `scripts/lint-probes.sh` reads the declaration through the reader, skips and reports a none, fails a lapsed date, refuses a contradiction, surfaces reader refusals, counts declared nones; validate.yml's step name cites 5.8 to 5.11.
**Worktree:** `proof-lint`
**Suite:** `scripts/lint-probes_test.sh`; its `fresh`, `chart` and `policy` helpers gain a `proofs` writer.

### Tasks (one slice each: RED agent, GREEN agent, orchestrator commit)

- [x] **2.1 A none entry covers an active definition with no chart** (FR-4) (red 018401b, green a1814f3): exit 0 and the line `lonely: proof none, drill fixture, review by 2026-11-28 (Req 5.9)`
- [x] **2.2 The summary counts declared nones** (FR-9) (red 7adcdc7, green 2c0cb81): `1 declared none`
- [x] **2.3 A lapsed date fails by name** (FR-5) (red 8a95dae, green c01ab70): `DHC_TODAY=2026-12-01`, exit 1, `lonely`, `2026-11-28`, `Req 5.10`
- [x] **2.4 A date equal to today passes** (FR-5) (guard against 2.3's green: a3f876a): `DHC_TODAY=2026-11-28`, exit 0
- [x] **2.5 The undeclared, uncovered message names the none way out** (FR-6) (red f89d604, green 7b735af): the existing case 4 output also contains `proof of kind none`
- [x] **2.6 A none entry for a chart-deployed definition fails naming both** (FR-7) (red 3970e37, green fc79764): `app` deployed by `chart/app` with a probe and declared none; exit 1, `app`, `chart/app/chart.yaml`
- [x] **2.7 A reader refusal surfaces** (FR-8) (red e9a7889, green 5b203ed): `kind: smoke`; exit 1, `Req 5.11` in the output, nothing else checked
- [x] **2.8 The real repository passes with zero declared nones** (FR-9) (guard: f39e99c): a case running the lint on the repository root, asserting `0 declared none` (the suite already runs one such case for the ledger lint; mirror it)
- [x] **2.9 validate.yml step renamed** (FR-10; no test beyond `scripts/lint-workflow-policy.sh .` and a yamllint of the workflow) (c372d02, done between slices)

### Verification (orchestrator)

- [x] `scripts/lint-probes_test.sh` green, the seven pre-existing cases untouched (15 cases)
- [x] `scripts/lint-probes.sh .` on this repository: green, `7 active definition(s)`, `0 declared none`
- [x] `yamllint .github/workflows/validate.yml`; `scripts/lint-workflow-policy.sh .`
- [x] The validate chain rehearsed locally end to end after the refactor commit (cf7139e)
- [ ] Pull request opens after #273 merges (the branch is rebased onto main then); the owner merges (checkpoint)

## Phase 3: documentation and the walkthrough (task 17.4)

**Objective:** the docs say what is built; the walkthrough shows two pull requests.
**Worktree:** `proof-docs`

### Tasks

- [ ] **3.1 `docs/CONVENTIONS.md`**: the active-set section gains the proof declaration; the probe sentence (the one citing Req 5.8) says "or a declared none proof with a reason and a review-by date"
- [ ] **3.2 `docs/user-manual.md`**: steps 4 to 6 of "Add an image definition" become pull request 1 and pull request 2 as in design.md's onboarding flow; the e2e section's probe paragraph names the declaration; the scripts table's `definition-lib.sh` row (Part VI) names the proof readers beside the mapping
- [ ] **3.3 `tasks/todo.md`**: 16.2 waits for 17.3; the 16.11 note (remove the entry when deactivating)
- [ ] **3.4 Cross-check**: every path and criterion cited in the touched text exists; no em-dashes in the added text

### Verification (orchestrator)

- [ ] `scripts/lint-live-evidence.sh .` (unchanged, still green); `scripts/lint-log-anchors.sh .` if the LOG was touched
- [ ] A read-through of the rendered walkthrough against the flow diagram
- [ ] Pull request opened; the owner merges (track complete)

## Final verification

- [ ] All three pull requests merged by squash
- [ ] `conductor/tracks.md` marks the track completed; `.specs/dhc-catalogue-mvp/tasks.md` ticks 17.2 to 17.4 with their dates
- [ ] 16.2 can proceed: drill-app's entry is the first `none`

## Deviations log

| Date | Task | Deviation | Reason | Resolution |
| --- | --- | --- | --- | --- |
| 2026-10-15 | 1.1 to 1.5 | Slice order changed: the declared-entry line (1.3) was built first as the tracer bullet; 1.1, 1.2, 1.4 and 1.5 followed as guards that passed against it | A stub that prints nothing satisfies "nothing declared prints nothing", so that test cannot be red first | Guards committed with "passes against GREEN 1" in the message; no green step for them |
| 2026-10-15 | 1.11 | The wrong-shape case also covers a scalar entry (`app: none`) | One behaviour, two inputs; the second raised a traceback as well | One numbered case, two inputs |
| 2026-10-15 | 1.13 | The declared-line and refusal-propagation tests passed against 1.12's implementation | The minimal lookup already printed the matching line and used `\|\| return $?` | Committed as guards |
| 2026-10-15 | 1.9 | `date.fromisoformat` accepts the basic form `"20261128"`; a bare impossible date fails in the YAML loader with a traceback | Python's parser; PyYAML resolves bare dates before the reader runs, as for every reader of the policy file | Noted in the pull request; no guard added |
| 2026-10-15 | 1.6 to 1.13 | Red tests for slices 12 and 13 were written in parallel with slice 11's green | Tests only, in scratch copies; applied in order after the green commit | None |
| 2026-10-15 | phase 2 | Built on top of the phase 1 branch instead of main | Phase 1 was still in review; the lint needs the reader | The pull request opens after #273 merges, rebased onto main so it carries only phase 2 |
| 2026-10-15 | 2.4, 2.8 | Both passed against the previous green | A boundary guard and a live-state guard | Committed as guards |
| 2026-10-15 | 2.8 | The planned `Req 5.9` needle does not match the summary, which cites `Req 5.5, 5.8, 5.9` | A substring match | The case asserts the counts only, as cases 1, 5 and 9 do |
| 2026-10-15 | 2.9 | The validate step was renamed between slices 2 and 3 | No test depends on it | None |
| 2026-10-15 | refactor | The lint reads the proofs map once up front and looks definitions up in it; the violations footer cites Req 5.8 to 5.11 | One reader invocation instead of one per definition | Behaviour unchanged, suite green |

---

**Plan created:** 2026-10-15
**Last updated:** 2026-10-15 (phases 1 and 2 built)
