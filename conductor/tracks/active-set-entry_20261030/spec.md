# Track specification: The drill definition's directory removed, its active-set entry refused by name, live

## Overview

**Track ID:** active-set-entry_20261030
**Type:** chore
**Priority:** high (the live program; the one row of task 16.11 still waiting)
**Created:** 2026-10-30
**Author:** the owner, drafted by the agent
**Spec source:** `.specs/dhc-catalogue-mvp/tasks.md` task 16.11 (task group 16, the live drills), its text amended by this track's pull request; Req 1.19 (an active-set entry naming a definition with no directory under `image/` fails validation naming that entry), 7.11 (the ledger); design Decision 13

### Description

Task 16.11's deactivation half ran for real on 2026-10-19, when grafana left the active set by the documented switch (#290, track `retire-grafana_20261019`): the matrices and the tracking scope excluded it (Req 1.14), no digest or tag followed (1.15), and the replayed bump was refused by name (1.16, drill #291). What the task keeps for the drill definition is the one refusal nobody has seen live: an active-set entry whose definition directory is gone (Req 1.19, ledger row 1.19, `drill 16.11`). This track removes `image/drill-app/` on a drill branch and leaves the policy entry in place; validation refuses the entry by name; nothing merges but this track and the evidence, and the drill pull request is closed unmerged with a comment, the shape of #313, #319, #323 and #324.

Two readers meet a removed directory before the active-set step does. The accepted-risk lint holds every exception file to a definition that exists (`risk treatment (Req 6.11): no image definition 'image/<name>/image.yaml'`), and the drill definition's lane file exists, empty since task 16.7. The pin and definition lint reads the definitions that exist and may or may not read the active set through the same reader. So the drill is two commits: the first removes the directory alone and records which step refuses first and with what line; the second removes the lane file as well, so that the active-set step's own refusal, the Req 1.19 line, is reached and read. The build matrix on a pull request names an image whose `image.yaml` changed, deleted included, and reads the active set through the same reader: what its affected-definitions job does with a malformed set is read, not predicted.

### The mechanism, as read on 2026-10-30

`scripts/definition-lib.sh` `active_definitions` reads `catalogue-policy.yaml`'s active set and refuses an entry with no `image/<name>/image.yaml`: `active_set entry '<name>' has no definition: image/<name>/image.yaml does not exist (Req 1.19)`. `scripts/lint-active-set.sh` (validate step `active-set coherence and scope (Req 1.16, 1.18, 1.19)`) surfaces that refusal as its first check, `lint-active-set: the active set is malformed (Req 1.19); nothing else checked`, exit 1. The validate job runs its steps in order and stops at the first failure, so an earlier step that refuses the same tree is the one annotated: the accepted-risk lint (step `accepted-risk lint for the risk treatment lane (Req 6.11, 6.12)`) refuses a lane file whose definition is missing, by name. `build.yml`'s affected-definitions job lists the images whose `image.yaml` changed against main, a deletion among them, and filters by the active set through `definition-lib`.

## Functional requirements (EARS)

The subject names follow design.md: the CI Pipeline (`validate.yml`, `build.yml`), the Repository, the owner.

### FR-1: The directory removed, the entry kept (Req 1.19)

WHEN a pull request removes `image/drill-app/` and keeps `drill-app` in the active set THE CI Pipeline SHALL fail validation naming the entry; the first commit removes the directory alone and the second the lane file `triage/accepted-risk/drill-app.yaml` as well, so that the step and the line refusing each commit are read and recorded, the Req 1.19 line among them.

Notes: the pull request is opened as a draft, meant to be red, never merged, and closed with a comment after the evidence merges. The proofs entry for drill-app (`catalogue-policy.yaml`, kind none) stays: the probe lint runs after the active-set step and is not reached.

**Acceptance criteria:**

- [x] Commit 1 (e1e5808): validate run 41135094891 red at step 9, the accepted-risk lint with `risk treatment (Req 6.11): no image definition 'image/drill-app/image.yaml'`; commit 2 (5ed2421): validate run 41135329824 red at the active-set step with `active_definitions: active_set entry 'drill-app' has no definition: image/drill-app/image.yaml does not exist (Req 1.19) (Req 1.13)`; the builds: the build and e2e matrix jobs red on both commits with the Req 1.19 line from the shared reader

### FR-2: The evidence (Req 7.11)

THE Repository SHALL flip ledger row 1.19 to `exercised` with the run id and the line (inducer `pull request`), add the task table row for 16.11, add the LOG entry `## 2026-10-30: the drill definition's directory removed, its active-set entry refused by name (task 16.11)`, tick task 16.11 citing grafana's deactivation for its other criteria, move `tasks/todo.md` to 16.13 and close this track, in one evidence pull request; the drill pull request is closed with a comment after it merges.

**Acceptance criteria:**

- [x] `scripts/lint-live-evidence.sh .` green with 143 exercised; `scripts/lint-log-anchors.sh all .` green; the tick `[done 2026-10-30, #355; conductor track active-set-entry_20261030]`; `conductor/tracks.md` lists the track under Completed; 16.13 next in `tasks/todo.md`

## Scope

### In scope

- One drill pull request of two commits, never merged (FR-1)
- One evidence pull request (FR-2); the drill pull request's closure after it
- The amendment of task 16.11's text in this pull request

### Out of scope

- Any change to the lints or the workflows: the drill reads what they do; a defect found is recorded with a follow-up task, not fixed here
- The retirement itself (task 16.16): there the directory and the entry leave together, through the switch, and the lane and proofs entries with them

## Dependencies

| Dependency | Type | Status | Notes |
| --- | --- | --- | --- |
| The deactivation half (grafana, 2026-10-19) | track | done (#290, #291, #295) | Rows 1.13 to 1.16 exercised |
| The lane file empty (task 16.7) | track | done 2026-10-30 (#351) | The second commit removes it |
| The task text amended (16.11) | spec | in this pull request | Two commits, the first step's refusal and the 1.19 line both read |

## Risks

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| An earlier step than the accepted-risk lint refuses the first commit | possible (the pin and definition lint, if it reads the active set) | the first commit's refusal is another lint's, by name | Read and recorded; the second commit removes the lane file either way |
| The second commit is refused before the active-set step | low (nothing else reads the lane file; the probe lint comes after) | the Req 1.19 line is not reached | A third commit would remove what refused first; recorded |
| The affected-definitions job of the build fails on the malformed set | expected | the build gate red on a drill never merged | Recorded as observed |

## Open questions (the owner's calls)

- [x] Two commits (the owner's call by merging #353)
- [ ] The drill pull request #354 closed after the evidence merges, the branch kept on origin (the post-merge housekeeping)

## References

- `.specs/dhc-catalogue-mvp/requirements.md` Req 1.13 to 1.16, 1.19, 5.10, 6.11, 7.11; `tasks.md` 16.11, 16.16
- `scripts/definition-lib.sh` (`active_definitions`), `scripts/lint-active-set.sh`, `scripts/lint-accepted-risk.sh`, `.github/workflows/validate.yml` (the step order), `.github/workflows/build.yml` (the affected-definitions job)
- LOG 2026-10-19 (grafana deactivated), 2026-10-26 (task 16.15, the lints refusing by name); tracks `retire-grafana_20261019`, `deliberate-violations_20261025`
