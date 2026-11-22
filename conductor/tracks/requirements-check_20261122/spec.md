# Track specification: The requirements checked against the code

## Overview

**Track ID:** requirements-check_20261122
**Type:** chore
**Priority:** high (the successor is seeded from this repository, task 12.1; what it inherits should do what the requirements say)
**Created:** 2026-11-22
**Author:** the owner, drafted by the agent
**Spec source:** the owner's call of 2026-11-21 (the requirements kept as written, and checked against the code in a track of its own, right after the documentation track); the open item in `tasks/todo.md`; the method of the review of 2026-09-09 (`docs/archive/reviews/2026-09-09-requirements-vs-implementation-review.md`), which task group 15 disposed of

### Description

`.specs/dhc-catalogue-mvp/requirements.md` holds 162 live criteria (Requirements 1 to 7 and 9; 8 retired). The last full check of them against the code was the review of 2026-09-09, at 147 criteria; since then task groups 16 to 19 added or amended about twenty, and the code moved under every lane. The ledger (`docs/live-evidence.md`) records that each criterion was once seen working; it does not say that the code still does what the sentence says today.

Drawing the lanes from the code (the documentation track, phase 5, 2026-11-22) already found places where it does not: among them a Renovate rule that keeps GitHub Actions bumps from ever opening, a published verify recipe whose failed checks exit 0, a tag step that moves every tag before it checks any, and a switch step in the rescan that cannot fail. They are listed under the open item in `tasks/todo.md`, read in the code but not yet in a run.

This track reads every criterion against the code once more, lists what it finds with the evidence, puts each finding to the owner as a decision, and fixes what the owner decides, one pull request per fix, code test-first. It changes no requirement unless the owner decides a sentence is what is wrong.

## Functional requirements (EARS)

The subject names follow design.md: the Repository (its maintainer), the CI Pipeline.

### FR-1: Every criterion read against the code

THE Repository SHALL hold a review, in this track's folder, that gives for every live criterion of `requirements.md` the mechanism that implements it (`file:line` at a named commit) and one verdict: HELD (implemented and enforced), PARTIAL (implemented with a stated gap), NOT HELD (no mechanism found) or OWNER-SIDE (live GitHub or registry state the files cannot show, with the daily check that asserts it named); WHERE a reader document (README, SECURITY.md, the manual, CONVENTIONS.md, `triage/README.md`, design.md, `docs/lanes.md`) states a behaviour the code does not have, THE review SHALL list it as a document finding beside the criterion it touches.

**Acceptance criteria:**

- [ ] One reading per requirement group (Requirement 6 in two halves), each by a separate read-only agent, from the files on disk: comments, ticked boxes and design prose are claims, the code is the evidence; a lint's or script's negative path probed against a mutated copy in a scratch directory, never against the tree
- [ ] Every PARTIAL and NOT HELD verdict, and every document finding, re-checked by a second, independent reader before it enters the review; a verdict that does not survive is dropped with its reason
- [ ] The findings of the documentation track's phase 5 (the open item in `tasks/todo.md`) each confirmed or refuted in the review, by a run where one can be read
- [ ] The review states its counts (HELD, PARTIAL, NOT HELD, OWNER-SIDE; document findings) and compares them with the review of 2026-09-09

### FR-2: Each finding a decision of the owner

WHEN the review lists a finding THE Repository SHALL record the owner's disposition of it: fix the code, fix the document, amend the requirement (with the dated paragraph requirements.md uses), or keep it as it is with the reason; a finding is put to the owner with what it is, what happens today, who is affected, the options with their cost and risk, and a recommendation.

**Acceptance criteria:**

- [ ] Every finding in the review carries its disposition and the date of the owner's call
- [ ] The dispositions grouped into fix clusters, each cluster one pull request, ordered by what a consumer or a release is exposed to first

### FR-3: The fixes

WHEN a disposition is to fix the code THE Repository SHALL fix it test-first, a failing test by one agent and the code by another, one behaviour per slice, in the pull request of its cluster; WHEN a disposition is to fix a document or amend a requirement THE Repository SHALL do it in the same pull request as the code it describes, or in a documentation pull request of its own when no code changes.

**Acceptance criteria:**

- [ ] Each cluster merged by the owner, its pull request naming the findings it closes (never with a closing keyword before an issue number)
- [ ] `docs/lanes.md` changed in the pull request that changes a lane (Req 9.21); its "open item" notes removed as their code is fixed
- [ ] A ledger row whose mechanism changed brought up to date in the same pull request

### FR-4: The evidence (Req 7.11)

THE Repository SHALL record the reading and its outcome in `triage/LOG.md` and the ledger, and close this track before task 12.1 seeds the successor.

**Acceptance criteria:**

- [ ] The LOG entry: the counts, the clusters and their pull requests, what was kept and why
- [ ] `scripts/lint-live-evidence.sh .` green; the track listed under Completed

## Scope

**In scope:** every live criterion; the reader documents' statements of behaviour; the phase-5 findings; the fixes the owner decides.

**Out of scope:** new requirements beyond an amendment the owner decides; `data/` (the owner's research drop); `triage/LOG.md` history (new entries only); image definitions, except where a disposition requires a definition change (it republishes the image, so it is named in the cluster's pull request); the open tracks (grafana's reactivation) and the carried reads of the SLSA track.

## Risks

- **Scale.** 162 criteria and their documents in nine readings and a re-check: about fifteen agent runs for the review alone. The readings run one requirement group at a time, so a reading that goes wrong is redone alone.
- **Verdicts that are claims.** A reader can mistake a comment for a mechanism. Mitigation: the second reader, and `file:line` for every mechanism.
- **Fix scope creep.** A finding can tempt a redesign. Mitigation: each fix is the owner's decision with its cost stated; a redesign is a track of its own.
- **Definition changes republish.** Any fix that touches `image/*/image.yaml` rebuilds and republishes that image on merge; it is named before the owner decides.
