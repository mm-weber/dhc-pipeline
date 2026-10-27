# Track specification: Deliberate violations, one pull request, every lint refuses by name, live

## Overview

**Track ID:** deliberate-violations_20261025
**Type:** chore
**Priority:** high (the owner's call of 2026-10-25: the next drill, with no clock involved)
**Created:** 2026-10-25
**Author:** the owner, drafted by the agent
**Spec source:** `.specs/dhc-catalogue-mvp/tasks.md` task 16.15 (task group 16, the live drills), its text amended by this track's pull request; the ledger rows with status `drill 16.15` (1.6, 1.11, 1.12, 5.8, 5.10, 6.11, 6.12, 6.19, 6.25, 6.39, 7.10, 9.6, 9.18) and the two candidates the ledger's task table names (1.18, 4.8); Req 4.2, 4.3, 4.6, 7.2, 7.4, 7.9 cited; Req 7.11 (the ledger); design Decision 13

### Description

Every convention this repository codifies is held by a lint or a gate that fails validation by name. Fifteen of those refusals have never run live: no pull request has ever carried the violation, and the unit tests are the only evidence. This track supplies the violations, one per commit, on one pull request that is never merged, and records each refusal as the pull request's checks show it. Nothing in the code changes; nothing merges but the track and the evidence.

Each commit carries exactly one violation and undoes the previous one, so that every run refuses one thing and names it. A job stops at its first failing step, so two violations in one commit would hide the second; and a violation left in place would mask the next run's result. The order follows the ledger's numbering, the checks named per rule below. The pull request opens as a draft with a TL;DR that says every run is meant to be red, and is closed with a comment after the evidence merges (#313 and #319's shape).

### The rules, the violations and the checks (as read on 2026-10-25)

| # | Ledger row | The violation (one commit) | The check that refuses |
| --- | --- | --- | --- |
| 1 | 1.6 | `image/drill-app/image.yaml`: the builder image `uses:` reference without its `@sha256` digest | validate, `pin + definition lint against docs/CONVENTIONS.md (Req 1.6, 7.2, 7.4)` (`lint-pins.sh`) |
| 2 | 1.11 | `image/drill-app/image.yaml`: the source's `# authenticity:` marker set to `none` | validate, the pin lint (the authenticity class rule) |
| 3 | 1.12 | `image/drill-app/image.yaml`: a dhi.io package repository of a shape other than `dhi.io/apk/<dist>/<ver>/main` | validate, the pin lint (Req 1.12) |
| 4 | 1.18 | `catalogue-policy.yaml`: valkey-compat removed from the active set while valkey stays, splitting the group | validate, `active-set coherence and scope (Req 1.16, 1.18, 1.19)` (`lint-active-set.sh`) |
| 5 | 4.8 | `chart/valkey/chart.yaml`: the compat decision's `review_by` moved to a past date | validate, `chart pins and compat decisions (Req 4.5, 4.8)` (`lint-compat.sh`) |
| 6 | 5.8 | `chart/hardened-app/chart.yaml`: the `probe:` line removed; hardened-app is active and declares no none proof | validate, `every active definition declares a functional proof (Req 5.8 to 5.10)` (`lint-probes.sh`) |
| 7 | 5.10 | `catalogue-policy.yaml` `proofs:`: a proof of a kind the lint does not implement, for hardened-app | validate, the probe lint |
| 8 | 5.10 | `catalogue-policy.yaml` `proofs:`: a proof of kind none, with a reason, for hardened-app, which its chart deploys and proves | validate, the probe lint |
| 9 | 6.11 | `triage/accepted-risk/drill-app.yaml`: the CRITICAL's entry without its `owner` field | validate, `accepted-risk lint for the risk treatment lane (Req 6.11, 6.12)` (`lint-accepted-risk.sh`) |
| 10 | 6.12 | `.trivyignore.yaml` added at the repository root, one entry | validate, the accepted-risk lint (Req 6.12) |
| 11 | 6.25 | `triage/accepted-risk/drill-app.yaml`: the CRITICAL's entry duplicated, same finding, same binary | validate, the accepted-risk lint (Req 6.25) |
| 12 | 9.18 | `triage/accepted-risk/drill-app.yaml`: the CRITICAL's `ref` pointing at a heading the LOG does not carry | validate, the accepted-risk lint (`lint-log-anchors.sh` inside it, Req 9.18) |
| 13 | 6.19 | `triage/vex/CVE-2026-100351.openvex.json`: the subcomponent purl given a version | validate, `VEX product identity lint (Req 6.17, 6.19, 6.20)` (`lint-vex-product.sh`) |
| 14 | 6.39 | the same statement's status set to `under_investigation` | validate, the VEX product identity lint (Req 6.39) |
| 15 | 9.18 | the same statement's log citation pointing at a heading the LOG does not carry | validate, `VEX statement LOG citations (Req 9.18)` (`lint-log-anchors.sh statements`) |
| 16 | 7.9 (exercised; re-observed) | `policies/restrict-registries.yaml`, a rendered artifact, edited by hand | validate, `verification renderings drift check (Req 7.8, 7.9)` (`render-verification.sh --check`) |
| 17 | 7.10 | `.github/workflows/renovate.yml`: its cron changed, the policy file not | validate, `workflow schedule + permissions vs policy file (Req 7.10)` (`lint-workflow-policy.sh`) |
| 18 | 9.6 | `triage/revocations.yaml`: one record missing its `advisory` field | validate, `revocation record (Req 9.6)` (yamale) |
| 19 | 4.2, 4.6 (exercised; re-observed), 1.6 | `chart/hardened-app/values.yaml`: the image pinned by tag alone, the digest removed | the chart gate (`render every chart and gate with kyverno`, `require-image-digest`); the pin lint, if it reads split values (observed) |
| 20 | 4.3, 4.6 (exercised; re-observed) | `chart/hardened-app/values.yaml`: `runAsNonRoot: false` | the chart gate, `require-nonroot` |
| 21 | 4.2, 4.6 (exercised; re-observed) | `chart/hardened-app/values.yaml`: the image repository outside `ghcr.io/mm-weber/dhc` | the chart gate, `restrict-registries` |

Task 16.15's text named one more rule, an EARS-invalid criterion refused by "the validator". No such validator exists in the repository (nothing under `scripts/` or `.github/workflows/` reads the requirements file); the EARS shape is a review convention (`CLAUDE.md`, the ears-notation skill). The amendment drops it and says so.

Commits 1 to 3 change a definition, so `build.yml` builds drill-app on each (the matrix follows changed image paths); commits 9, 11 and 12 change its exception file, which builds it too (the gate re-runs against the exception). Commits 5, 6 and 19 to 21 change a chart, so `chart.yml` and `e2e.yml` run on each. These runs are the cost of the drill, stated in the plan; none publishes anything (a pull request build pushes to a throwaway registry).

## Functional requirements (EARS)

The subject names follow design.md: the CI Pipeline (`validate.yml`, `chart.yml`, `build.yml` on a pull request), the Repository.

### FR-1: One violation per commit, each refused by name (Req 7.4; the rows above)

WHEN a commit of the drill pull request carries one of the twenty-one violations THE CI Pipeline SHALL fail the check named for it in the table above with a message naming the file and the convention, and THE Repository SHALL record that run's id, the step and the message line for the row, as the check's annotation shows it.

Notes: the message lines are recorded as observed, never predicted; where a run refuses more than the one thing (a chart commit meeting both the pin lint and the gate), every refusal is recorded and attributed. A violation that is not refused is a finding of its own: recorded as a ledger `defect` with a follow-up task, the commit kept on the branch.

**Acceptance criteria:**

- [x] Twenty-one commits, each with its run id, the refusing check and the line, in the LOG entry's table (thirty shas: nine commits pushed twice, the plan's deviations log; the line for rules 18 to 21 is in the log, the step's failure recorded)
- [x] Rows 1.6, 1.11, 1.12, 1.18, 4.8, 5.8, 5.10, 6.11, 6.12, 6.19, 6.25, 6.39, 7.10, 9.6 and 9.18 `exercised` with their run ids, inducer `pull request`; rows 4.2, 4.3, 4.6 and 7.9 gain the re-observation in their evidence text (#326)

### FR-2: Never merged, closed with the evidence (Req 7.11)

THE Repository SHALL keep the drill pull request a draft from its opening to its closing, and SHALL close it with a comment linking the LOG entry after the evidence pull request merges.

**Acceptance criteria:**

- [x] The pull request closed unmerged, its closing comment naming the LOG heading and the evidence pull request (#323, closed 2026-10-26 16:59:03Z on #326's merge by a closing keyword in that body, the comment added 17:02:07Z)

### FR-3: The evidence (Req 7.11)

THE Repository SHALL add the LOG entry `## 2026-10-25: deliberate violations, every lint refuses by name (task 16.15)` with the table of twenty-one, flip the rows, tick task 16.15 in `.specs/dhc-catalogue-mvp/tasks.md`, update `tasks/todo.md` and close this track, in an evidence pull request opened once the last run is in.

**Acceptance criteria:**

- [x] `scripts/lint-live-evidence.sh .` green with the exercised count up by fifteen (136); `scripts/lint-log-anchors.sh all .` green; the tick `[done 2026-10-26, #326; conductor track deliberate-violations_20261025]`; `conductor/tracks.md` lists the track under Completed

## Scope

### In scope

- One drill pull request, twenty-one commits, never merged
- The evidence pull request and the amendment of task 16.15's text

### Out of scope

- Any change to a lint, a policy or a workflow: the drill reads what they do; a lint that does not refuse becomes a `defect` row and a follow-up task
- An EARS validator: none exists; not built here
- The drill definition's own proof entry (`proofs: drill-app`): untouched, as the task text says

## Dependencies

| Dependency | Type | Status | Notes |
| --- | --- | --- | --- |
| The task text amended (16.15) | spec | in this pull request | The ledger's list, the EARS item dropped, one violation per commit |
| The drill definition and its exception file (task 16.2) | track | done 2026-10-18 | The fixture for the definition and exception rules |

## Risks

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| A commit's violation is not refused | low per rule, plausible over twenty-one | a convention held by nothing live | Recorded as a `defect` row with a follow-up task; the drill's purpose |
| Runs overlap when commits are pushed in sequence | certain | no run cancels another (no concurrency group); the checks shown on the pull request are the head's | Evidence is read per commit by its sha, never from the pull request's check list |
| Builds and e2e installs on the drill commits | certain | runner minutes; drill-app built up to six times, the hardened-app chart installed up to five times | Named here; nothing publishes from a pull request |
| The drill pull request is merged by mistake | low | the violations enter main | A draft from opening to closing; every run red |

## Open questions (the owner's calls)

- [x] The two candidates 1.18 and 4.8 included: yes, the owner's call by merging #322; both refused
- [x] 7.9 and the three chart-gate rules re-observed although their rows are already exercised: yes, by the same merge; all four refused
- [x] Commits pushed as each run starts rather than as each run ends: as each starts; thirty commits in twenty-eight minutes of pushing, no run cancelled

## References

- `.specs/dhc-catalogue-mvp/requirements.md` Req 1.6, 1.11, 1.12, 1.18, 4.2, 4.3, 4.6, 4.8, 5.8, 5.10, 6.11, 6.12, 6.19, 6.25, 6.39, 7.2, 7.4, 7.9, 7.10, 9.6, 9.18, 7.11; `tasks.md` 16.15
- `.github/workflows/validate.yml`, `chart.yml`; `scripts/lint-pins.sh`, `lint-active-set.sh`, `lint-compat.sh`, `lint-probes.sh`, `lint-accepted-risk.sh`, `lint-vex-product.sh`, `lint-log-anchors.sh`, `render-verification.sh`, `lint-workflow-policy.sh`; `triage/revocations.schema.yaml`; `policies/`
- `docs/live-evidence.md` (the rows above and the task table's 16.15 row); tracks `kev-drill-input_20261023` and `kev-ceiling_20261024` (#313 and #319, the never-merged drill pull request's shape)
