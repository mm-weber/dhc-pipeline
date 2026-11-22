# Track specification: The documentation consolidated, every lane drawn with the decisions behind it

## Overview

**Track ID:** docs-consolidation_20261120
**Type:** chore
**Priority:** high (the successor is seeded from this repository's cleaned tree, task 12.1; what is cut and drawn here is what it inherits)
**Created:** 2026-11-20
**Author:** the owner, drafted by the agent
**Spec source:** the owner's four calls of 2026-11-20 (lane graphs in Mermaid inside the Markdown; working notes moved to one archive folder; overlapping documents merged into fewer; the SLSA provenance lane drawn first); design Decision 16 and task group 19, added by this track's pull request; Req 9.20 and 9.21, added by it

### Description

The repository explains itself in about 30 reader documents and 33 review files, and several topics are explained more than once: the release and rescan steps in four places, upstream tracking in five, the triage treatments in four. Some of the copies have drifted apart: the Renovate cadence reads "at most six hours" in four documents and "every four hours" in four others (both true: the first is Req 3.1, the second the configured cron, but no document says so); `conductor/tech-stack.md` lists four tool versions that the install scripts moved past and calls fourteen design decisions what are now fifteen; `docs/operating-loop.md` counts four definitions where there are seven. Every diagram the repository holds predates the provenance steps.

This track does three things, in this order. It draws each lane of the pipeline as one Mermaid graph in which every step names the decision it rests on, so a reader sees what runs and why on one page, starting with the SLSA provenance lane. It puts the working notes, which record how the repository got here and are not reader documentation, into one archive folder. And it merges overlapping documents into fewer, so each topic is explained once, fixing the contradictions on the way. A link check in the pull request gate guards the moves.

### The documents, as read on 2026-11-20

- **Fixed in place by code or requirement** (do not move): `README.md` and `docs/user-manual.md` (`render-verification.sh` rewrites the block between their markers; the smoke test reads the README), `triage/LOG.md` (Req 6.7, 6.15, 9.18; `lint-log-anchors.sh`; links written by the rescan tool), `docs/live-evidence.md` (`lint-live-evidence.sh`), `.specs/dhc-catalogue-mvp/{requirements,design,tasks}.md` (the spec tooling), the six core files of `conductor/` (the conductor plugin's `setup_state.json`), `docs/CONVENTIONS.md` (Req 1.9, 7.1, 9.14; named in about 22 lint messages), `triage/README.md` (named in two lints' messages), `SECURITY.md` (Req 9.1, 9.19), `data/` (named in `CLAUDE.md` as the owner's research drop)
- **Working notes**: `.specs/dhc-catalogue-mvp/reviews/` (34 files of dated review rounds, with their measuring scripts), the closed items of `tasks/todo.md` (1,910 lines on 2026-11-21; the open items are the live task list `CLAUDE.md` asks for), the working-notes half of `docs/concepts.md` (spikes, BuildKit internals, Actions as macros)
- **Merge candidates**: `docs/operating-loop.md` (the Renovate loop, already in the manual and CONVENTIONS, plus the dated evidence of one run of 2026-07-21); the reference half of `docs/concepts.md` (the builder contract, Req 1.17; the trust-boundary table, Req 9.15; the variant taxonomy); `docs/revocation-runbook.md` (the one procedure, summarised in SECURITY.md and triage/README.md); the triage chapters of the manual against `triage/README.md`; the stack facts of design.md against `conductor/tech-stack.md`
- **Diagrams**: two Mermaid graphs in design.md (the architecture, the upstream bump sequence), ASCII flows of the release, the rescan and onboarding in design.md, of the two loops, the four treatments and the purl rewriting in the manual, of the Renovate loop in `operating-loop.md`, of BuildKit in `concepts.md`; the release, rescan, architecture and loop flows lack the provenance steps

## Functional requirements (EARS)

The subject names follow design.md: the Repository (its maintainer), the CI Pipeline.

### FR-1: Every lane drawn, the decisions named (Req 9.21)

THE Repository SHALL give, in one document linked from its README, one Mermaid graph per lane of the pipeline, each step of which names the criterion and the design decision or ADR it rests on and links to where the step is explained, and one graph that shows how the lanes connect; WHEN a lane's steps change THE Repository SHALL change its graph in the same pull request.

**Acceptance criteria:**

- [x] The lanes document exists, the README links it near the top, and each graph renders on GitHub (rendered locally first by the Mermaid command-line tool, in a container)
- [x] The SLSA provenance lane first, as the pattern the others follow (phase 1)
- [x] Every lane named in the lane map has its graph; the stale diagrams in design.md and the manual are replaced by a link to the lane, or brought up to date where they show something no lane graph shows

### FR-2: Relative links resolve (Req 9.20)

IF a Markdown document of the Repository links to a path or a heading inside the Repository that does not exist THEN THE CI Pipeline SHALL fail validation naming the document and the link.

**Acceptance criteria:**

- [x] A link checker (an established tool, pinned like every other tool, Req 7.5) runs in validate over every tracked Markdown file, offline, relative links and heading anchors
- [x] Green on main before the first move; a pull request with a broken link red, naming it (the drill that exercises 9.20)

### FR-3: Working notes in one archive folder

THE Repository SHALL keep its working notes under `docs/archive/`, each moved file's history intact (`git mv`), every link to it updated, and SHALL keep in `tasks/todo.md` only the items still open.

**Acceptance criteria:**

- [x] `.specs/dhc-catalogue-mvp/reviews/` under `docs/archive/reviews/`; the closed items of `tasks/todo.md` under `docs/archive/`; the working-notes half of `docs/concepts.md` under `docs/archive/`
- [x] `docs/archive/README.md` says what each file is and that nothing there is current
- [x] The link check green

### FR-4: Each topic explained once

THE Repository SHALL explain each topic in one document, SHALL merge a document whose content another holds or should hold into that one and remove it, SHALL reduce every other mention to a sentence and a link, and SHALL state each value that two documents stated differently once, from where the value is declared.

**Acceptance criteria:**

- [x] `docs/operating-loop.md`, `docs/concepts.md` and `docs/revocation-runbook.md` merged into the documents named in design Decision 16 and removed; every link to them, and every comment that names them, updated (except the comment on line 4 of `image/valkey-compat/image.yaml`, carried: a definition change republishes its image)
- [x] The Renovate cadence stated the same way everywhere: at most six hours (Req 3.1), configured every four (`catalogue-policy.yaml`); `conductor/tech-stack.md` names the install scripts as the home of tool versions instead of repeating them; the decision and ADR counts and the definition counts current
- [x] The manual's triage chapters reduced to what an operator does and a link to `triage/README.md` for the rest; design.md's stack table reduced to the reasons, the versions living in one place
- [x] The link check green; `render-verification.sh --check`, `lint-live-evidence.sh`, `lint-log-anchors.sh` green

### FR-5: The evidence (Req 7.11)

THE Repository SHALL record ledger rows 9.20 and 9.21 and a LOG entry naming what moved, merged and was drawn.

**Acceptance criteria:**

- [x] `scripts/lint-live-evidence.sh .` green; the track listed under Completed

## Scope

### In scope

- The lanes document and every lane graph; the link check; the archive; the merges named in Decision 16; the contradictions found on 2026-11-20
- `README.md`, `SECURITY.md`, `docs/`, `conductor/` (content, not the core file set), `.specs/` (design.md's diagrams and Decision 16, tasks.md's group 19, requirements 9.20 and 9.21), `tasks/todo.md`, comments in scripts and definitions that name a moved file

### Out of scope

- Changing what any script, workflow or policy does (only comments that name a moved file, and the one new validate step of FR-2)
- Moving the files the overview lists as fixed in place
- `data/` (the owner's research drop, `CLAUDE.md`)
- Renumbering the requirements (task 12.1's cleanup, in the successor)

## Risks

- **Broken links.** About 75 places name `tasks/todo.md`, about 40 name `docs/concepts.md` or its anchors. The link check lands before the first move for this reason.
- **Lint messages that name a document.** `lint-pins.sh` names CONVENTIONS.md and a test asserts it; two lints name `triage/README.md`. Both documents stay where they are.
- **A graph that lies.** A graph is only as good as its last update; FR-1's second clause asks for it to change with the lane, and review holds that, not a lint.
