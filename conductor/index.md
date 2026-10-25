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
