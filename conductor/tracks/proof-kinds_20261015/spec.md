# Track specification: Proof kinds per definition

## Overview

**Track ID:** proof-kinds_20261015
**Type:** feature
**Priority:** high
**Created:** 2026-10-15
**Author:** the owner, drafted by the agent
**Spec source:** `.specs/dhc-catalogue-mvp/requirements.md` Req 5.8 to 5.10 and 7.7 as amended by pull request #271 (the review-by date dropped 2026-10-16); design Decision 14; task group 17 (17.2, 17.3, 17.4)

### Description

Every active definition must be proved functional. Today the only proof is a chart's probe, run by the e2e suite on the published image, and the probe lint fails validation for any active definition no chart deploys. This track lets the catalogue policy file declare the proof per definition: `chart` stays the default and needs no entry; `none` is a declared gap with a reason, printed by name on every validation run and refused when stale (an inactive name, a chart-deployed definition). The first draft gave it a review-by date and a lapse; the 2026-10-16 review of #271 and the owner's call removed them, because the chart pull request follows the first publish within the workflow and a second clock guarded a window closed in minutes. It is the first increment of design Decision 14 (proof kinds), and it makes adding an image a two-pull-request operation: the image with its `none` entry first, the chart after the first publish.

### Background

The drill definition of task 16.2 cannot join the catalogue under the current rules: a new definition must be activated in its first pull request, activation needs a chart with a probe, a chart must pin a published digest, and a digest is published only after that merge. The research memo `data/image-onboarding-practices-2026-10-15.md` found that every surveyed catalogue binds functional tests to the image and onboards in two stages. The declaration breaks the cycle at the declaration level and changes nothing in the build, release or e2e flows.

## Functional requirements (EARS)

### FR-1: The declaration (Req 7.7, 5.10)

THE Repository SHALL declare functional proofs in `catalogue-policy.yaml` under one top-level `proofs:` map from a definition directory name to an entry carrying `kind` (one of `chart`, `none`) and, for kind `none`, a non-empty `reason`; an absent or empty map means every active definition is proved by a chart.

**Acceptance criteria:**

- [ ] The reference instance's policy file carries `proofs: {}` with a comment block naming the fork switch, the reader and the criteria
- [ ] `yamllint catalogue-policy.yaml` passes; `scripts/lint-active-set.sh .` and `scripts/release-policy.sh . check` are unchanged

### FR-2: The reader (Req 5.10)

THE Reader (`proof_entries <root>` in `scripts/definition-lib.sh`) SHALL print one line per entry in declared order, tab-separated as name, kind, reason (reason empty for kind chart), and nothing when the map is absent or empty; and `proof_of <root> <definition>` SHALL print that definition's line, or `chart` alone when no entry names it.

**Acceptance criteria:**

- [ ] No `proofs:` key: no output, exit 0
- [ ] `proofs: {}`: no output, exit 0
- [ ] A none entry for an active definition prints `name<TAB>none<TAB>reason`
- [ ] A chart entry prints `name<TAB>chart<TAB>`
- [ ] `proof_of` prints `chart` for an active definition with no entry and the entry's line otherwise

### FR-3: Refusals (Req 5.10)

IF `proofs:` is not a map, an entry is not a map, an entry's `kind` is missing or not one of chart or none, a none entry lacks a non-empty `reason`, or an entry names a definition outside the active set THEN THE Reader SHALL refuse with exit 2 and one `::error file=catalogue-policy.yaml::proof_entries: <problem> (Req 5.10)` line naming the entry, before printing any line.

**Acceptance criteria:**

- [ ] One test per refusal shape (five since 2026-10-16), each asserting exit 2, the entry's name in the message and `Req 5.10`
- [ ] `proof_of` propagates the refusal unchanged

### FR-4: The lint skips and reports a declared none (Req 5.9)

WHILE an active definition carries a proof of kind none THE Probe Lint (`scripts/lint-probes.sh`) SHALL skip that definition's chart check and SHALL print `lint-probes: <name>: proof none, <reason> (Req 5.9)`.

**Acceptance criteria:**

- [ ] An active definition with no chart and a valid none entry: exit 0, the line printed

### FR-5: withdrawn 2026-10-16 (a lapsed date failed validation)

The review-by date and its lapse were dropped by the owner's call on the 2026-10-16 review of #271 (plan.md, deviations log). The number is kept so the plan's references stand.

### FR-6: The amended refusal of an undeclared, uncovered definition (Req 5.8)

IF an active definition is deployed by no chart declaring a probe and carries no none entry THEN THE Probe Lint SHALL fail naming it, the message naming the three ways out: a chart with a probe, a none entry with a reason, or deactivation.

**Acceptance criteria:**

- [ ] The existing case (an active definition deployed by no chart) still fails with `Req 5.8` and now mentions the none entry

### FR-7: A contradictory declaration (Req 5.8, 5.10)

IF a definition carries a none entry and a chart with a probe deploys it THEN THE Probe Lint SHALL fail naming the definition and the chart, because one proof is declared per definition and the stale entry must go.

**Acceptance criteria:**

- [ ] A none entry for a chart-deployed active definition: exit 1, both names in the message

### FR-8: A reader refusal surfaces (Req 5.10)

IF the reader refuses THEN THE Probe Lint SHALL print the refusal and exit 1 before checking any definition, as it does for a malformed active set.

**Acceptance criteria:**

- [ ] A none entry with an unknown kind: exit 1, the reader's line with `Req 5.10` in the output

### FR-9: The summary (Req 5.9)

WHEN the lint passes THE Probe Lint SHALL print one summary line counting active definitions, probe registrations and declared none proofs.

**Acceptance criteria:**

- [ ] The existing summary assertions pass and the line carries `<n> declared none`
- [ ] `scripts/lint-probes.sh .` on this repository passes with `0 declared none`

### FR-10: The validate step (Req 5.8 to 5.10)

THE CI Pipeline SHALL run the probe lint in `validate.yml` under a step name citing Req 5.8 to 5.10.

**Acceptance criteria:**

- [ ] The step name reads `every active definition declares a functional proof (Req 5.8 to 5.10)`; `scripts/lint-workflow-policy.sh .` still passes

### FR-11: Documentation (Req 5.9, 7.7)

THE Repository SHALL document the declaration and the two-pull-request onboarding in `docs/CONVENTIONS.md` (the active-set section and the probe sentence), `docs/user-manual.md` (the add-a-definition walkthrough and the e2e section's probe paragraph) and the policy file's comment block, and SHALL amend the plan's 16.2 entry in `tasks/todo.md` to wait for 17.3.

**Acceptance criteria:**

- [ ] The walkthrough shows pull request 1 (image, active entry, none entry) and pull request 2 (chart, harness entry, entry removed) as in design.md's onboarding flow
- [ ] No em-dashes in the touched text; every path and criterion cited exists

## Non-functional requirements

- **No new tools:** python3 with PyYAML as the other readers; no new script, so the "every script has a test suite" step is unaffected.
- **No behaviour change for current definitions:** with `proofs: {}` the lint's counts on this repository stay as they are.
- **Fail closed:** a kind the lint does not implement (`smoke` included) is a refusal, never a pass.

## Scope

### In scope

- Task 17.2: the policy file section and the two reader functions with their tests
- Task 17.3: the lint changes with their tests and the validate step name
- Task 17.4: the documentation and the plan entry

### Out of scope

- The drill definition's own `none` entry (task 16.2 adds it)
- The `smoke` kind (task 17.5, needs its own criterion)
- Any change to the e2e suite, the harness, build.yml or e2e.yml
- Unknown extra keys in an entry (not refused; the criteria do not ask for it)

### Future considerations

- `smoke`: the frontend's `tests:` block or a `docker run` step on the candidate
- A ledger row per proof kind once `smoke` exists

## Dependencies

### Upstream

| Dependency | Type | Status | Notes |
| --- | --- | --- | --- |
| Pull request #271 (spec amendment) | spec | open | the criteria this track implements; merge before phase 1's pull request |
| `scripts/definition-lib.sh` `active_definitions` | code | merged | the reader checks membership through it |

### Downstream impacts

| Component | Impact | Mitigation |
| --- | --- | --- |
| Task 16.2 | first user of a none entry | the entry's reason names the drill; the entry leaves with the active-set line at 16.11 |
| Task 16.11 (deactivation) | a none entry for a name outside the active set is refused | remove the entry in the same pull request that deactivates |
| Task 16.15 (deliberate violations) | two new commits: an unknown kind, a none for a chart-deployed definition | listed there already |
| `docs/user-manual.md` | the one-pull-request walkthrough is replaced | task 17.4 |

## Risks

| Risk | Probability | Impact | Mitigation |
| --- | --- | --- | --- |
| A lint exit code read as "nothing to check" | low | a refusal must fail the run | FR-8 test; exit 1 on refusal as for a malformed active set |
| A contradictory entry silently ignored | medium | a stale record survives | FR-7 fails by name |

## Open questions

- [x] Fail or warn on a none entry for a chart-deployed definition? Fail (FR-7); the owner may veto at confirmation.
- [x] Date boundary and key spelling? Superseded 2026-10-16: the entry carries no date (the owner's call on the review of #271).

## References

- `.specs/dhc-catalogue-mvp/requirements.md` Req 5.8 to 5.10, 7.7 (pull request #271)
- `.specs/dhc-catalogue-mvp/design.md` Decision 14 and the onboarding flow
- `.specs/dhc-catalogue-mvp/tasks.md` task group 17
- `data/image-onboarding-practices-2026-10-15.md`
- `scripts/lint-probes.sh`, `scripts/lint-probes_test.sh`, `scripts/definition-lib.sh`, `scripts/definition-lib_test.sh`

---

**Approved by:** pending the owner's confirmation
**Approval date:** pending
