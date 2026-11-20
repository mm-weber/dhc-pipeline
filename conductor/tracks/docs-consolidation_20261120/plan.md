# Implementation plan: The documentation consolidated, every lane drawn with the decisions behind it

**Track ID:** docs-consolidation_20261120
**Spec:** [spec.md](./spec.md)
**Created:** 2026-11-20
**Status:** [~] in progress

## Overview

Seven phases, one pull request each. Phase 0 is this pull request: the track, Decision 16, requirements 9.20 and 9.21, task group 19; the owner confirms by merging. Phase 1 draws the SLSA lane and opens the lanes document, the pattern for the rest. Phase 2 puts the link check in the gate before anything moves. Phases 3 and 4 archive and merge. Phase 5 draws the other lanes and retires the stale diagrams. Phase 6 records the evidence. Documentation is not code: no RED and GREEN agents for prose; the link check of phase 2 is configuration of a pinned tool, measured by a deliberately broken link. Each prose phase ends with a read-only review by a separate agent, which holds every moved or merged sentence against its source, as phase 5 of the SLSA track did.

## Phase 0: the track (this pull request)

- [x] **0.1 The track**: this folder, `conductor/tracks.md`, `conductor/index.md`
- [x] **0.2 The spec amendment**: requirements 9.20 (relative links resolve) and 9.21 (every lane drawn) with the dated paragraph; design Decision 16 (the documentation map); task group 19 and the coverage row; ledger rows 9.20 and 9.21 unexercised, each with its reason
- [ ] **0.3 The pull request**; the owner merges

## Phase 1: the lanes document and the SLSA provenance lane (task 19.2)

- [ ] **1.1 `docs/lanes.md`**: what a lane is, how to read a graph (a box is a step, its label names the criterion and the decision, a click leads to the explanation), the lane map with every lane as a node (only SLSA expanded yet)
- [ ] **1.2 The SLSA provenance lane**: the release side (name the subjects, attest, store, verify, tag), the rescan side (coverage, the status line), the consumer side (the recipe step, the Kyverno rule under `required`), and the three modes as the branch points; each step naming Req 2.9, 2.27 to 2.30, 9.19 and Decision 15 or ADR 0005 where it rests on them
- [ ] **1.3 Rendered and read**: each graph rendered by the Mermaid command-line tool in a container before the push; the README links the document; a read-only review against `build.yml`, `rescan.yml` and the scripts

## Phase 2: the link check (task 19.3; Req 9.20)

- [ ] **2.1 The tool**: lychee, pinned with its checksum through `scripts/install-tool.sh` (Req 7.5) and its Renovate manager, offline, every tracked Markdown file, relative links and heading anchors; a validate step
- [ ] **2.2 Green on main**: the links broken today repaired in the same pull request, each named in it
- [ ] **2.3 The drill**: a commit with a broken link, validate red naming it, then reverted (Req 7.11)

## Phase 3: the archive (task 19.4)

- [ ] **3.1 `docs/archive/`** with its README; `reviews/` moved; the closed items of `tasks/todo.md` moved, the open ones kept; the working-notes half of `concepts.md` moved; every link updated, the link check green

## Phase 4: the merges and the contradictions (task 19.5)

- [ ] **4.1 `operating-loop.md`** into the manual (the operator's view) and the archive (the run of 2026-07-21)
- [ ] **4.2 `concepts.md`'s reference half** into the manual (the builder contract, the trust-boundary table, the variant taxonomy), the anchors that README, SECURITY.md, the ledger, a chart README and a definition comment use moved with it
- [ ] **4.3 `revocation-runbook.md`** into the manual, SECURITY.md naming the new location (Req 9.1)
- [ ] **4.4 The triage chapters and the stack facts** as Decision 16 places them; the cadence, the tool versions, the counts made consistent

## Phase 5: the other lanes (task 19.6)

- [ ] **5.1 One graph per lane** in the lane map, in the pattern of phase 1, one commit each, each reviewed against its workflow
- [ ] **5.2 The stale diagrams** in design.md and the manual replaced by links to their lane, or brought up to date

## Phase 6: the evidence (task 19.7)

- [ ] **6.1** Ledger rows 9.20 and 9.21, the LOG entry, task group 19 ticked, this track closed

## Final verification

- [ ] Every FR's acceptance criteria met
- [ ] The link check, `render-verification.sh --check`, `lint-live-evidence.sh`, `lint-log-anchors.sh` and every suite green
