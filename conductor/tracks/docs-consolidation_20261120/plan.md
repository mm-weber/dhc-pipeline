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
- [x] **0.3 The pull request**; the owner merges (#428, 2026-11-20)

## Phase 1: the lanes document and the SLSA provenance lane (task 19.2)

- [x] **1.1 `docs/lanes.md`**: what a lane is, how to read a graph (a box is a step, its label names the criterion and the decision, a click leads to the explanation), the lane map with every lane as a node (only SLSA expanded yet)
- [x] **1.2 The SLSA provenance lane**: the release side (name the subjects, attest, store, verify, tag), the rescan side (coverage, the status line), the consumer side (the recipe step, the Kyverno rule under `required`), and the three modes as the branch points; each step naming Req 2.9, 2.27 to 2.30, 9.19 and Decision 15 or ADR 0005 where it rests on them
- [x] **1.3 Rendered and read**: each graph rendered by the Mermaid command-line tool in a container before the push; the README links the document; a read-only review against `build.yml`, `rescan.yml` and the scripts
  - Done 2026-11-20: four graphs (the lane map and the SLSA lane at release, in the daily rescan, for a consumer), each rendered with the Mermaid command-line tool (`ghcr.io/mermaid-js/mermaid-cli`, in a container) and looked at before the push. The first draft drew the lane as one graph; the lines from the policy file to every part made it unreadable, so it is three. A separate read-only agent held the page against the workflows, the scripts, the requirements and the ADR and found ten points, all taken: among them the page's "every release since 2026-11-18 carries one", which the deliberate `off` release of 2026-11-20 disproves and which `SECURITY.md`, design.md and `concepts.md` said as well (all four now say "while the mode is not off"); a failing first step drawn without its stop; the steps' entry condition (only on main, only a scheduled rebuild that publishes); the scan reports attested before "sign and attest", not in it; the rescan's check that cannot be made; the consumer step absent under `off`; a label citing Req 2.28 where the source is the SLSA track's FR-3; the gate's Req 7 and the dispatch entry missing from the map; the smoke test linked to the wrong section

## Phase 2: the link check (task 19.3; Req 9.20)

- [x] **2.1 The tool**: lychee, pinned with its checksum through `scripts/install-tool.sh` (Req 7.5) and its Renovate manager, offline, every tracked Markdown file, relative links and heading anchors; a validate step
  - Done 2026-11-20: lychee 0.24.2, the static musl asset (the gnu build needs glibc 2.39), sha256 `73657a11...fc5`; lychee signs and attests nothing, so like kind it has no independent second source: the release's `.sha256` file and GitHub's own asset digest agree with the download but change with the asset (register M1). Two slices, each a failing test by one agent and the code by another: `install-tool.sh lychee` (the binary from the archive's subdirectory only), and a Renovate packageRule, because lychee tags its releases `lychee-v<ver>` (its library `lychee-lib-v<ver>`) and the shared `^v<ver>$` template would have seen no version and never offered a bump. The validate step runs `lychee --offline --include-fragments` over `git ls-files '*.md'`
- [x] **2.2 Green on main**: the links broken today repaired in the same pull request, each named in it
  - Done 2026-11-20: one, measured over 134 files and 306 links: the review of 2026-08-25 quoted the README as `[Docker Hardened Images](...)`, a link to the path `...`; the quote is now a code span
- [x] **2.3 The drill**: a commit with a broken link, validate red naming it, then reverted (Req 7.11)
  - Done 2026-11-20 on #430: commit 17be278 added a link to a missing file and one to a missing heading in `docs/lanes.md`; validate went red at the link step alone (run 44803253992, every other check green); the same lychee over the same tree named both with file, line and column (the job log itself is out of this machine's reach, its storage host is not on the firewall's list); 18a4dfc took them out and validate went green (run 44803406409). Ledger row 9.20 is written in phase 6

## Phase 3: the archive (task 19.4)

- [x] **3.1 `docs/archive/`** with its README; `reviews/` moved; the closed items of `tasks/todo.md` moved, the open ones kept; the working-notes half of `concepts.md` moved; every link updated, the link check green
  - Done 2026-11-21: the 34 review files by `git mv`; `tasks/todo.md` moved whole to `docs/archive/todo-until-2026-11-21.md` and a new one holding the open items word for word (five carried from the SLSA track, two of them one item now; sixteen open; the calendar, the working rules, the ledger recipes) and one new item, the requirements checked against the code, a track of its own after this one (the owner's call of 2026-11-21); Spikes, BuildKit and Actions from `concepts.md` to `docs/archive/concepts-working-notes.md`. The link check green over 320 links. A read-only review found no lost or altered sentence; four points taken, two not (stale `reviews/` paths in `data/`, the owner's research drop; an ambiguous "FR-3" under a heading that names its track)

## Phase 4: the merges and the contradictions (task 19.5)

- [x] **4.1 `operating-loop.md`** into the manual (the operator's view) and the archive (the run of 2026-07-21)
- [x] **4.2 `concepts.md`'s reference half** into the manual (the builder contract, the trust-boundary table, the variant taxonomy), the anchors that README, SECURITY.md, the ledger, a chart README and a definition comment use moved with it
- [x] **4.3 `revocation-runbook.md`** into the manual, SECURITY.md naming the new location (Req 9.1)
- [x] **4.4 The triage chapters and the stack facts** as Decision 16 places them; the cadence, the tool versions, the counts made consistent
- [x] **4.5 Back from the archive** (found by the review of phase 3): the reason the `# syntax=` line is digest-pinned (the frontend's digest is the actions' implementation hash) and what a frontend is, today explained only in `docs/archive/concepts-working-notes.md`, which `CONVENTIONS.md`, `lint-pins.sh` and `concepts.md` point to; two sentences into the manual's reference part, the pointers moved with them
  - Done 2026-11-22: `concepts.md` became the first sections of the manual's Part VI (headings kept, so their anchors did not move), with "The frontend and its actions" brought back from the archive (4.5); `revocation-runbook.md` became "Revoke a digest" in Part III, SECURITY.md naming it (Req 9.1); `operating-loop.md` moved whole to the archive, the manual already explaining the loop. The manual's triage chapters keep what an operator does and link to `triage/README.md`, which took the explanation the manual alone had. Stated once from the declaration: four retired criterion numbers, the example exception (now a live entry, the old one long retired), Req 6.9 beside 6.41, the Renovate cadence (at most six hours, configured every four), and `tech-stack.md` without versions (five were stale), sixteen decisions and five ADRs. Not repointed: the comment in `image/valkey-compat/image.yaml`, since a definition change republishes the image. A read-only review found nothing lost; three points taken, two not (the variant taxonomy in Part I and Part VI, linked; the identifier rules as bullets and as a table in `triage/README.md`)

## Phase 5: the other lanes (task 19.6)

- [x] **5.1 One graph per lane** in the lane map, in the pattern of phase 1, one commit each, each reviewed against its workflow
- [x] **5.2 The stale diagrams** in design.md and the manual replaced by links to their lane, or brought up to date
  - Done 2026-11-22: six lanes drawn, one commit each (upstream tracking, the pull-request gate, the release with its three entries, the daily rescan and triage, posture, the consumer), 31 graphs on the page, each with its table of exact step names, explaining sections and criteria, each rendered with the Mermaid command-line tool and looked at. Where a lane passes through the SLSA lane it links it instead of drawing it twice. Of the seven diagrams in design.md and the manual, four flows became links to their lane (their design reasoning kept as prose), the architecture graph was brought up to date, the onboarding flow and the four treatments kept. A separate read-only review held every lane against its workflow and scripts: every box and step name exists, but failure edges and "fails" claims were wrong in each lane; all taken, the page now draws what the code does today. The code problems the drawing and the review found (among them a Renovate rule that keeps GitHub Actions bumps from ever opening, and a published verify recipe without pipefail) are input to the requirements-vs-code track, listed in `tasks/todo.md`; none is fixed here

## Phase 6: the evidence (task 19.7)

- [x] **6.1** Ledger rows 9.20 and 9.21, the LOG entry, task group 19 ticked, this track closed
  - Done 2026-11-22: row 9.20 exercised by the drill of #430, row 9.21 measured present after #435; the LOG entry of 2026-11-22; task group 19 ticked (19.2 had been left open when #429 merged); the track under Completed

## Final verification

- [x] Every FR's acceptance criteria met
- [x] The link check, `render-verification.sh --check`, `lint-live-evidence.sh`, `lint-log-anchors.sh` and every suite green
