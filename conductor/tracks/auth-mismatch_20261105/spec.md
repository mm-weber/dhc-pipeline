# Track specification: A true authenticity mismatch, the drill definition's tag moved by its maintainer, live

## Overview

**Track ID:** auth-mismatch_20261105
**Type:** chore
**Priority:** high (the live program; the one row that needs an upstream signal to move)
**Created:** 2026-11-05
**Author:** the owner, drafted by the agent
**Spec source:** `.specs/dhc-catalogue-mvp/tasks.md` task 16.10 (task group 16, the live drills), its text amended by this track's pull request; Req 3.10 (every authenticity signal re-verified daily, a mismatch reported as a supply-chain issue), 3.13 (an unreadable origin recorded as not measured, no issue), 7.11 (the ledger); register row M18 (deciding what a supply-chain signal means)

### Description

Every active definition declares an authenticity signal, and `scripts/check-authenticity.sh` re-verifies it against its upstream origin once a day inside the rescan: a tag that moved, a signature that no longer verifies or two checksum origins that stopped agreeing is a mismatch, reported by name, failing the run and filing one `supply-chain` issue where a human decides what the signal meant (Req 3.10, register M18). The check has run daily since 2026-09-07 and its report has fired only on unreadable reads (2026-09-16, a rate-limited API read as six mismatches, #212 to #217, the incident Req 3.13 corrects); a true mismatch has never occurred, so ledger row 3.10 waits for this drill. The drill definition's signal is `signed-commit`: its pinned tag `v0.1.0` points at commit b7868d7a, whose signature GitHub reports as valid. This track has the owner move that tag to a commit signed by no key, the rescan file the first true mismatch, the owner decide and restore, the rescan verify again, and the issue close with the reason.

The owner moved the tag on 2026-11-05 at 10:29Z, before this track's pull request existed, at their own pace; the deviation is logged in the plan and the time is on record.

### The mechanism, as read on 2026-11-05

- The check reads, for the class `signed-commit`, the tag's object and target through the GitHub API and the commit's verification statement; `ok: false` when the tag no longer points at the pinned commit or the statement is not `verified`. An origin the check cannot read is `ok: null`, exit 2, no issue (Req 3.13).
- The rescan's step "authenticity signals (Req 3.10, 3.13, 4.9)" exits with the check's code: a mismatch fails the run, and by review disposition D1 every later step still runs, the status issue included. The step files one issue per definition with `ok: false`, label `supply-chain`, title `Supply-chain signal: <definition> (<class>, <ref>) failed re-verification`, body marked `<!-- rescan-signal: <definition> -->`; a second run with the mismatch still present files nothing more (the marker is read first). Nothing closes the issue: the decision and the closure are a human's (M18).
- The drill definition's build fetches the source as `git+https://github.com/mm-weber/drill-app.git#v0.1.0` with the pinned commit as its checksum, so a build of drill-app while the tag is moved refuses the fetch by name; under on-change nothing publishes, and the scheduled rebuild of 2026-11-05 had not run when the tag moved.
- drill-app's rulesets protect branches only; tags are free to move. The tag as moved: object 726afc2, annotated, unsigned, tagger 10:29:12Z, pointing at commit d273710 (unsigned, 10:29:00Z, empty, off `main`). The original tag object ca6144e6, signed and valid, at b7868d7a, is what the restore pushes back.
- By the owner's rule of 2026-11-03 a drill dispatches its runs; the scheduler is exercised daily. A rescan dispatch is a release of attestations (register row M17).

## Functional requirements (EARS)

The subject names follow design.md: the owner, the Repository (its maintainer), the Scan Pipeline.

### FR-1: The tag moved (Req 3.10)

THE owner SHALL move the drill definition's pinned tag `v0.1.0` in `mm-weber/drill-app` to a commit signed by no key, the tag kept annotated and unsigned, and SHALL tell the maintainer the time of the push.

**Acceptance criteria:**

- [ ] The tag's object and target read from the API after the push, with the tagger's time and both verification statements

### FR-2: The mismatch reported (Req 3.10)

WHEN the rescan runs with the tag moved THE Scan Pipeline SHALL report the mismatch by name in the authenticity step and fail the run, SHALL keep every other daily assertion and the status issue running (D1), and SHALL file one `supply-chain` issue naming the definition, the class and the origin, the record `ok: false` in the run's `authenticity.jsonl`.

**Acceptance criteria:**

- [ ] The dispatched run's id, the step's failing line, the issue's number and time, the status issue of the day produced by the same run

### FR-3: The decision and the restoration (register M18)

THE owner SHALL decide what the signal means (a drill: the tag moved by its maintainer, no key rotated, no compromise) and SHALL restore the original tag object at the pinned commit, and WHEN the rescan runs again THE Scan Pipeline SHALL verify the signal and file nothing; THE owner SHALL close the issue with the decision as its reason.

**Acceptance criteria:**

- [ ] The restore's time; the second dispatched run's id and its green step; the issue's closing comment and time

### FR-4: The evidence (Req 7.11)

THE Repository SHALL flip ledger row 3.10 to `exercised` (inducer `owner`) with the two runs and the issue, SHALL keep row 3.13 `unexercised` with its reason, add the task table row for 16.10, add the LOG entry `## 2026-11-05: the drill definition's tag moved by its maintainer, the first true mismatch, decided and restored (task 16.10)`, tick task 16.10 and close this track, in one evidence pull request.

**Acceptance criteria:**

- [ ] `scripts/lint-live-evidence.sh .` green with one more exercised row (146); `scripts/lint-log-anchors.sh all .` green; the tick `[done <date>, #nnn; conductor track auth-mismatch_20261105]`; `conductor/tracks.md` lists the track under Completed

## Scope

### In scope

- The owner's two tag pushes (FR-1, FR-3), two dispatched rescans (FR-2, FR-3), the issue and its closure, one evidence pull request (FR-4)
- The amendment of task 16.10's text in this pull request

### Out of scope

- Row 3.13: an unreadable origin cannot be staged without harming the day's run; the row keeps its reason
- The task's second variant, the tag re-signed with another key: the unsigned commit covers "a tag that moved" and "a signature that no longer verifies" in one push
- Any change to the check, the workflows or the definition

## Dependencies

| Dependency | Type | Status | Notes |
| --- | --- | --- | --- |
| drill-app's tags unprotected | nature | read 2026-11-05 | three rulesets, all `branch`; no tag protection |
| The rescan's dispatch | mechanism | available | each dispatch a release of attestations (M17) |
| The task text amended (16.10) | spec | in this pull request | the dispatches and the owner's pace recorded |

## Risks

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The scheduled rebuild of 2026-11-05 runs inside the window | likely (its cron is 04:47Z, delayed daily) | drill-app's build job refuses the fetch by name on the checksum; the build gate red for that run; on-change, nothing published | Recorded in the entry as the build's own guard on a moved tag; the window closed by the restore |
| A reader of the issue list takes the supply-chain issue for a compromise | low (the issue is closed with the reason the same day) | none | The closing comment names the drill and the restored object |
| The moved tag is left in place | low (the restore is one push of a known object) | the mismatch reported daily, the issue kept open, the build refusing drill-app | The original tag object's sha is in this spec |

## Open questions (the owner's calls)

- [ ] The second variant (a key rotation) skipped (drafted: skipped; the one push covers both of the check's conditions)
- [ ] The issue closed by the owner with the decision as a comment (drafted: the owner; the rescan never closes a supply-chain issue)

## References

- `scripts/check-authenticity.sh` (the contract), `.github/workflows/rescan.yml` "authenticity signals (Req 3.10, 3.13, 4.9)"; `docs/CONVENTIONS.md` register row M18; `.specs/dhc-catalogue-mvp/requirements.md` Req 3.10, 3.13, 7.11; `tasks.md` 16.10
- LOG 2026-09-16 (the six unreadable reads); `image/drill-app/image.yaml` (the pinned tag and checksum)
