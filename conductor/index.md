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
| proof-kinds_20261015 | completed | high | [spec](./tracks/proof-kinds_20261015/spec.md) | [plan](./tracks/proof-kinds_20261015/plan.md) |
| drill-definition_20261017 | completed | high | [spec](./tracks/drill-definition_20261017/spec.md) | [plan](./tracks/drill-definition_20261017/plan.md) |
| retire-grafana_20261019 | completed | high | [spec](./tracks/retire-grafana_20261019/spec.md) | [plan](./tracks/retire-grafana_20261019/plan.md) |
| kev-drill-input_20261023 | completed | high | [spec](./tracks/kev-drill-input_20261023/spec.md) | [plan](./tracks/kev-drill-input_20261023/plan.md) |
| kev-ceiling_20261024 | completed | high | [spec](./tracks/kev-ceiling_20261024/spec.md) | [plan](./tracks/kev-ceiling_20261024/plan.md) |
| drill-fix_20261028 | in progress | high | [spec](./tracks/drill-fix_20261028/spec.md) | [plan](./tracks/drill-fix_20261028/plan.md) |
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
