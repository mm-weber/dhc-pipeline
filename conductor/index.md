# Conductor hub: dhc-pipeline

Navigation for the project context and the work tracks. Context first, then spec and plan, then implementation (the conductor plugin's workflow). The formal spec stays in `.specs/dhc-catalogue-mvp/` (requirements in EARS, design decisions, tasks); the files here are the working context the plugin reads and the per-track specs and plans.

## Core documents

| Document | Purpose |
| --- | --- |
| [Product](./product.md) | What the catalogue is, for whom, and what done looks like |
| [Product guidelines](./product-guidelines.md) | Voice, register, terminology, error-message shape |
| [Tech stack](./tech-stack.md) | Languages, pinned tools, infrastructure, where decisions live |
| [Workflow](./workflow.md) | TDD by slices, worktrees, pull requests, verification |
| [Tracks](./tracks.md) | The registry of work tracks |

## Style guides

| Guide | Scope |
| --- | --- |
| [General](./code_styleguides/general.md) | Rules that hold everywhere, and where the house conventions live |
| [Shell](./code_styleguides/shell.md) | The `scripts/*.sh` family and their `_test.sh` suites |
| [Go](./code_styleguides/go.md) | `test/` (Ginkgo e2e) and `triage/rescan` (stdlib tool) |

## Active tracks

| Track | Status | Priority | Spec | Plan |
| --- | --- | --- | --- | --- |
| slsa-build-l2_20261028 | in progress | high | [spec](./tracks/slsa-build-l2_20261028/spec.md) | [plan](./tracks/slsa-build-l2_20261028/plan.md) |
| reactivate-grafana_20261110 | in progress | high | [spec](./tracks/reactivate-grafana_20261110/spec.md) | [plan](./tracks/reactivate-grafana_20261110/plan.md) |
| proof-kinds_20261015 | completed | high | [spec](./tracks/proof-kinds_20261015/spec.md) | [plan](./tracks/proof-kinds_20261015/plan.md) |
| drill-definition_20261017 | completed | high | [spec](./tracks/drill-definition_20261017/spec.md) | [plan](./tracks/drill-definition_20261017/plan.md) |
| retire-grafana_20261019 | completed | high | [spec](./tracks/retire-grafana_20261019/spec.md) | [plan](./tracks/retire-grafana_20261019/plan.md) |
| kev-drill-input_20261023 | completed | high | [spec](./tracks/kev-drill-input_20261023/spec.md) | [plan](./tracks/kev-drill-input_20261023/plan.md) |
| kev-ceiling_20261024 | completed | high | [spec](./tracks/kev-ceiling_20261024/spec.md) | [plan](./tracks/kev-ceiling_20261024/plan.md) |
| private-report_20261031 | completed | high | [spec](./tracks/private-report_20261031/spec.md) | [plan](./tracks/private-report_20261031/plan.md) |
| revocation_20261105 | completed | high | [spec](./tracks/revocation_20261105/spec.md) | [plan](./tracks/revocation_20261105/plan.md) |
| retirement_20261107 | completed | high | [spec](./tracks/retirement_20261107/spec.md) | [plan](./tracks/retirement_20261107/plan.md) |
| auth-mismatch_20261105 | completed | high | [spec](./tracks/auth-mismatch_20261105/spec.md) | [plan](./tracks/auth-mismatch_20261105/plan.md) |
| switches_20261030 | completed | high | [spec](./tracks/switches_20261030/spec.md) | [plan](./tracks/switches_20261030/plan.md) |
| active-set-entry_20261030 | completed | high | [spec](./tracks/active-set-entry_20261030/spec.md) | [plan](./tracks/active-set-entry_20261030/plan.md) |
| drill-regression_20261029 | completed | high | [spec](./tracks/drill-regression_20261029/spec.md) | [plan](./tracks/drill-regression_20261029/plan.md) |
| drill-fix_20261028 | completed | high | [spec](./tracks/drill-fix_20261028/spec.md) | [plan](./tracks/drill-fix_20261028/plan.md) |
| fail-closed-release_20261027 | completed | high | [spec](./tracks/fail-closed-release_20261027/spec.md) | [plan](./tracks/fail-closed-release_20261027/plan.md) |
| over-ceiling_20261027 | completed | high | [spec](./tracks/over-ceiling_20261027/spec.md) | [plan](./tracks/over-ceiling_20261027/plan.md) |
| exception-lapse_20261025 | completed | high | [spec](./tracks/exception-lapse_20261025/spec.md) | [plan](./tracks/exception-lapse_20261025/plan.md) |
| deliberate-violations_20261025 | completed | high | [spec](./tracks/deliberate-violations_20261025/spec.md) | [plan](./tracks/deliberate-violations_20261025/plan.md) |

## Recent activity

| Date | Track | Action |
| --- | --- | --- |
| 2026-10-15 | proof-kinds_20261015 | Track created from spec task group 17 (pull request #271) |
| 2026-10-17 | proof-kinds_20261015 | Track completed: phases 17.2, 17.3 and 17.4 merged by squash (#273, #281, #282) after the spec (#271) and the context (#272); the spec ticks and the registry closed in their own pull request |
| 2026-10-17 | drill-definition_20261017 | Track created from spec task 16.2, the first live drill; the live-drills working plan of 2026-10-12 (branch plan-live-drills) folded into `tasks/todo.md`, revisited |
| 2026-10-19 | drill-definition_20261017 | Track completed: #286 merged 2026-10-18 (the definition, the first declared none proof, the owner's two accept decisions); the first publish and the first rescan observed in the evidence pull request |
| 2026-10-19 | retire-grafana_20261019 | Track created from the owner's call to deactivate grafana by the documented switch (level 1 of four, kept in the spec); the twelve moot exceptions retired with it |
| 2026-10-20 | retire-grafana_20261019 | Track completed: #290 merged 2026-10-19 (the switch, the twelve exceptions retired); the first inactive day observed in #292 and #295 (no grafana job in the push build, the drill's build, the owner's dispatch release and the nightly; the rescan's first non-empty inactive check, run 39417467219; Renovate autoclosed #279); rows 1.15 and 1.16 exercised |
| 2026-10-23 | kev-drill-input_20261023 | Track created from spec task 16.8, the first drill input: the `drill` choice on `rescan.yml`'s dispatch substitutes a declared KEV feed address for one run, the policy lint holds its allowed values (Req 7.7 and 7.10 amended in the same pull request), both fail-closed branches to run live |
| 2026-10-24 | kev-drill-input_20261023 | Track completed: #308 and #310 merged 2026-10-23 (the spec amendment of 7.7 and 7.10 and the track; the input, the declarations, the lint, the reader); the drill observed in #314: the gate's half red on the drill branch #313 (never merged), the dispatched `kev-outage` run 40024066594 red by name with the issue set, the status and the page withheld, the scheduled run 40088952931 of 2026-10-24 green with `- drill: none` and the status and the page published; ledger rows 6.59 and 6.60 exercised |
| 2026-10-24 | kev-ceiling_20261024 | Track created from spec task 16.3, the KEV ceiling on the drill's standing exception: the `kev-synthetic` drill input lists the HIGH, the rescan reports the 90-day exception over the 14-day tier (Req 6.51) while publishing with KEV yes, the gate refuses it on the drill pull request's first commit (Req 6.50), the re-decision to one day merges and feeds drill 16.4's lapse; the task text amended in the same pull request |
| 2026-10-25 | kev-ceiling_20261024 | Track revised before confirmation at the owner's call: the re-decision shortened from four days to one; Trivy's midnight reading of the expiry day noted for drill 16.4 |
| 2026-10-25 | kev-ceiling_20261024 | Track completed: #318 (a764a23) the track; #319 (714614f) the drill, both refusals live by name (dispatch 40187973579, build 40188092683) and the re-decision to one day; the pass on dispatch 40191153604; the evidence and the closure in #320; rows 6.50 and 6.51 exercised |
| 2026-10-25 | exception-lapse_20261025 | Track created from spec task 16.4, the drill's exception expiring on 2026-10-26: the two clocks (Trivy at midnight UTC, the lint and the compiler a day later), the rescan's recompile carrying the lapse into the attested document, the gate refusing the finding as uncovered, the entry removed at the end for 16.5; the task text amended in the same pull request |
| 2026-10-25 | deliberate-violations_20261025 | Track created from spec task 16.15 at the owner's call: one drill pull request, never merged, twenty-one commits each carrying one violation, every lint and gate refusing by name; fifteen ledger rows to fill; the EARS validator item dropped from the task text, no validator exists |
| 2026-10-26 | deliberate-violations_20261025 | Track completed: drill pull request #323, thirty commits (nine redone), every lint and gate refusing by name; fifteen ledger rows exercised, four re-observed; the evidence in #326 |
| 2026-10-27 | exception-lapse_20261025 | Track completed: the drill's exception expired on both clocks, Trivy's at midnight UTC of 2026-10-26 (the finding counted again, the document re-attested under_investigation, the status undecided, issue #325, the gate on #324 red by name) and the lint's and compiler's on 2026-10-27 (`is in the past`, the page lapsed, the lapse note attested); rows 6.9, 6.10 and 6.41 exercised; the lapsed entry removed in #329, the finding undecided for 16.5 |
| 2026-10-27 | over-ceiling_20261027 | Track created from spec task 16.5 at the owner's call: the drill's undecided HIGH over its ceiling for one dispatched rescan by a one-day KEV ceiling (the HIGH ceiling cannot go under 60 days without re-tiering grafana's transfers), the alarm read on the status issue and the page, the value restored the same day, the clear on the next scheduled run |
| 2026-10-28 | over-ceiling_20261027 | Track completed: the drill's undecided HIGH over a one-day KEV ceiling on the owner's dispatch with the synthetic feed (`9 / 1`, `over ceiling: 1`, the row and the card marked, the first over-ceiling flag live), the value restored the same day, the alarm cleared on the next scheduled run; the HIGH ceiling found to be three things at once, a follow-up item; the evidence in #339 |
| 2026-10-27 | fail-closed-release_20261027 | Track created from spec task 16.9 at the owner's call: the fail-closed switch on for one dispatched build of drill-app, whose HIGH is uncovered since 16.4; the gate refuses the release by name, the digest frozen, the switch off the same day; the way out is 16.6's fix |
| 2026-10-28 | fail-closed-release_20261027 | Track completed: the switch on, the owner's dispatch refused at the fail-closed release gate by name (the first live refusal), the digest frozen in the registry, the switch off the same day; the evidence in #336; a first dispatch before the switch released the definition instead |
| 2026-10-28 | drill-fix_20261028 | Track created from spec task 16.6 at the owner's call: the drill's two modules bumped in the definition's fetch phase, the release, the next scheduled rescan closing issue #325 as fixed on the attested SBOMs and publishing the fix clock, the moot exception retired |
| 2026-10-28 | drill-fix_20261028 | Track completed: the drill's two modules bumped in the fetch phase, the gate green by the fix, the release, the owner's dispatch closing #325 `resolved:fixed` on the attested SBOMs and publishing both findings fixed 10 days after first seen; the moot exception retired; the evidence in #344 |
| 2026-10-29 | drill-regression_20261029 | Track created from spec task 16.7 at the owner's call: the drill's HIGH brought back by removing its bump, accepted for one day instead of a bypass of the gate, the scheduled rescan of 2026-10-30 reopening its closed issue on the lapse with first seen carried, the entry removed the same day |
| 2026-10-30 | drill-regression_20261029 | Track completed: the HIGH brought back under a one-day acceptance, released with an `affected` statement, the issue reopened by name on the lapse with first seen carried (the first reopen live); the entry removed; the evidence in #351 |
| 2026-10-30 | active-set-entry_20261030 | Track created from spec task 16.11 at the owner's call: the drill definition's directory removed on a never-merged branch with its active-set entry kept, validation refusing the entry by name in two commits (the lane's guard, then the Req 1.19 line) |
| 2026-10-30 | active-set-entry_20261030 | Track completed: drill pull request #354, never merged, the drill definition's directory removed with its entry kept, refused by name twice, the Req 1.19 line on the second commit (the first live); row 1.19 exercised; the evidence in #355 |
| 2026-10-30 | switches_20261030 | Track created from spec task 16.13 at the owner's call: the always publish policy and the page switch off for one day through one pull request, the nightly republishing every definition and the rescan skipping the page, both switches back the same day; Req 6.62's failure branch by the owner's Pages action, their call |
| 2026-10-28 | slsa-build-l2_20261028 | Track created with spec task group 18 at the owner's call: SLSA Build L2 measured against v1.2; GitHub's provenance service at release, the policy rule, the consumer step and a daily coverage report; required from the successor's first release; the spec amendment (2.9, 2.10, 2.23, 2.25, 7.7 amended; 2.27 to 2.29, 9.19 added; Decision 15) in the same pull request |
| 2026-11-11 | slsa-build-l2_20261028 | Spec amended at the owner's call: one provenance mode in the policy file's release section, `off`, `report` or `required`, in place of the trigger "required attestations name SLSA provenance"; Req 2.30 added (the `off` position, for a repository GitHub offers no artifact attestations to); built with phase 2 |
| 2026-11-10 | reactivate-grafana_20261110 | Track created at the owner's call: grafana returns to the active set, the fix rung reopened on the frozen digest; measured that the released 13.1.x line carries the fixed toolchain the oldest undecided finding needs and the module behind the five not-affected statements past its fixed range |
| 2026-11-08 | retirement_20261107 | Track completed: the drill definition retired at level 2 (#378), the live-state case to six test-first, the record complete with the eight findings paragraphs, the upstream archived, the dispatched rescan after read for the definition leaving the supported set and its issue closing on evidence; task group 16 complete; the evidence in #379 |
| 2026-11-07 | retirement_20261107 | Track created from spec task 16.16 at the owner's call: the drill definition retired at level 2 (the line, the proofs entry, the directory and the lane out in one pull request, the live-state case to six test-first), the record completed with the eight findings paragraphs, the upstream archived by the owner, the first dispatched rescan after read for the issues closing as absent; task group 16 closed |
| 2026-11-07 | revocation_20261105 | Track completed: the drill digest withdrawn (Move B1), the entry merged while the tags still referenced it, the posture step red by name on a dispatched and a scheduled rescan, the version deleted by the owner, the next dispatched rescan green with the entry listed; rows 9.4, 9.5, 9.7 exercised; the evidence in #376; 16.16 next at once |
| 2026-11-05 | revocation_20261105 | Track created from spec task 16.12 at the owner's call: the drill digest recorded as withdrawn while its tags still reference it (the schema admits no entry before its move, so Move B1), the advisory drafted first, the dispatched rescan red at the posture step, the version deleted by the owner, the second dispatched rescan green, the advisory published or kept; rows 9.4, 9.5, 9.7; the last drill before the retirement |
| 2026-11-05 | private-report_20261031 | Track completed: the drill report GHSA-6xgw-5wvx-p8xx filed from a non-collaborator account (the admin's own attempt refused with 403), acknowledged in 26 minutes, examined against the records, answered and closed as a drill in 30, nothing published; row 9.2 exercised; the evidence in #370 |
| 2026-11-05 | auth-mismatch_20261105 | Track completed: the tag moved and restored by its maintainer, the first true mismatch reported by name and filed as #368 by the dispatched rescan 42011386908, every later step running; the second dispatched rescan 42014582733 green; the issue closed by the owner with the decision (M18); row 3.10 exercised, 3.13 kept; the evidence in #369 |
| 2026-11-05 | auth-mismatch_20261105 | Track created from spec task 16.10 at the owner's call: the drill definition's tag moved by its maintainer to an unsigned commit (done 10:29Z, before the track), the dispatched rescan filing the first true supply-chain issue, the owner's decision (M18) and the restore, the second dispatched rescan green, the issue closed with the reason; row 3.10 exercised, 3.13 kept |
| 2026-11-03 | switches_20261030 | Track completed: the always policy and the page switch off for one day (#357, #359), the scheduled rebuild of 2026-11-01 publishing all seven active definitions on new digests and the rescan skipping the page; Renovate's digest pull requests #360, #361 and #362 automerged 2026-11-03 once the e2e gate was repaired (#363, #364); rows 2.17 and 6.62 exercised (the latter by the owner's Pages action around two dispatched rescans of 2026-11-04), 2.15, 3.12 and 6.61 appended; the evidence in #365 |
| 2026-10-31 | private-report_20261031 | Track created from spec task 16.14 at the owner's call: one private vulnerability report filed by the owner as a drill, handled and closed as SECURITY.md promises, the elapsed times recorded; beside the switches drill, which waits on the scheduled runs of 2026-11-01 |
