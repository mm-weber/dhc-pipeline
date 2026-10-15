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
| proof-kinds_20261015 | pending | high | [spec](./tracks/proof-kinds_20261015/spec.md) | [plan](./tracks/proof-kinds_20261015/plan.md) |

## Recent activity

| Date | Track | Action |
| --- | --- | --- |
| 2026-10-15 | proof-kinds_20261015 | Track created from spec task group 17 (pull request #271) |
