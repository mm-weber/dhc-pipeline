# The archive

How this repository got here. Nothing in this folder is current: the files are
kept as they were written, for the record, and are not updated when the
pipeline changes. For how things work today, start at the
[README](../../README.md), the [lanes](../lanes.md) and the
[user manual](../user-manual.md).

| What | Where | What it is |
|---|---|---|
| The review rounds | [reviews/](reviews/) | The dated reviews of the requirements and the design, August and September 2026: each round's findings, its revision ledger (what was changed for each finding) and, for most, the script that measured the claims and its output. The requirements' header names the rounds that changed them. One file is still read: task 15 of `.specs/dhc-catalogue-mvp/tasks.md` picks its next pull request from the "Proposed dispositions" table of `2026-09-09-requirements-vs-implementation-review.md`. |
| The task list until 2026-11-21 | [todo-until-2026-11-21.md](todo-until-2026-11-21.md) | `tasks/todo.md` as it stood that day: the live-drills program, every older plan and its review notes, closed and open items together. The open items continue in [tasks/todo.md](../../tasks/todo.md). |
| The working notes of concepts.md | [concepts-working-notes.md](concepts-working-notes.md) | Spikes, BuildKit's frontends and LLB, and Actions as compile-time macros: the ideas behind the tools, written down while building. The reference half stays in [docs/concepts.md](../concepts.md). |

Each file's history before its move: `git log --follow` on the review rounds,
`git log -- tasks/todo.md` and `git log -- docs/concepts.md` on the other two.
Moved by the documentation track `docs-consolidation_20261120` (plan 3.1,
design Decision 16).
