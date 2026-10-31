# Track specification: A report through the private channel, handled as the policy promises, live

## Overview

**Track ID:** private-report_20261031
**Type:** chore
**Priority:** high (the live program; the one row that needs a report to arrive)
**Created:** 2026-10-31
**Author:** the owner, drafted by the agent
**Spec source:** `.specs/dhc-catalogue-mvp/tasks.md` task 16.14 (task group 16, the live drills), its text amended by this track's pull request; Req 9.2 (vulnerability reports accepted through GitHub private vulnerability reporting), 9.3 (the channel verified daily, exercised), 7.11 (the ledger); SECURITY.md "Reporting a vulnerability"

### Description

SECURITY.md names one channel for vulnerability reports, GitHub private vulnerability reporting on this repository, and promises that the daily rescan keeps the channel enabled and fails by name when it is not (Req 9.3, exercised on 2026-09-08 when the run reported the channel disabled and the owner enabled it). No report has ever arrived, so the channel's receiving half (Req 9.2) and the handling the policy implies have never run: ledger row 9.2 waits for this drill. This track has the owner file one report, titled as a drill, and has the maintainer handle it the way the policy says: read it, answer it in the report's thread, decide whether it names a vulnerability of the catalogue's machinery, definitions or images, and close it with the reason, here as a drill, with the elapsed times recorded. The policy promises no response window ("Not promised: remediation windows, an on-call duty"); the ledger records the times as numbers against no promised bound, the status issue's way.

### The mechanism, as read on 2026-10-31

A private vulnerability report is a draft security advisory the reporter opens on the repository through the Security tab; the maintainer sees it under Security, Advisories, as a draft of state "triage", can comment in its thread, accept it (it becomes a draft advisory the maintainer edits and may publish) or close it (no advisory published, the report kept with its thread). The REST API lists them under the repository's security advisories for a token with the `security_events` scope; the thread is readable there too. Nothing in the workflows reads reports: the rescan checks only that the channel is enabled.

## Functional requirements (EARS)

The subject names follow design.md: the owner, the Repository (its maintainer), the Scan Pipeline.

### FR-1: The report (Req 9.2)

THE owner SHALL file one private vulnerability report on the repository through the Security tab, titled `Drill 16.14: <subject>`, naming a plausible subject (a published status the reporter believes wrong, the shape SECURITY.md names as reportable), and SHALL tell the maintainer the time of filing.

**Acceptance criteria:**

- [ ] The report's identifier (the advisory id) and the filing time

### FR-2: The handling

WHEN the report is filed THE Repository SHALL acknowledge it in its thread, examine the subject against the catalogue's records (the status issue, the attested documents, the LOG), answer with what was found, and close the report as a drill with that answer, nothing published; the elapsed time from filing to acknowledgement and from filing to closure SHALL be recorded.

Notes: the drill names no real vulnerability, so the outcome is a closure with the examination recorded; a real report would follow the same path to a decision in the LOG and, where a digest must be withdrawn, the revocation runbook (task 16.12).

**Acceptance criteria:**

- [ ] The thread's acknowledgement and answer, the closure, the two elapsed times

### FR-3: The evidence (Req 7.11)

THE Repository SHALL flip ledger row 9.2 to `exercised` with the advisory id and the elapsed times (inducer `owner`), add the task table row for 16.14, add the LOG entry `## 2026-10-31: a report through the private channel, handled and closed as a drill (task 16.14)`, tick task 16.14 and close this track, in one evidence pull request.

**Acceptance criteria:**

- [ ] `scripts/lint-live-evidence.sh .` green with one more exercised row; the tick `[done <date>, #nnn; conductor track private-report_20261031]`; `conductor/tracks.md` lists the track under Completed

## Scope

### In scope

- One report filed by the owner (FR-1), its handling by the maintainer (FR-2), one evidence pull request (FR-3)
- The amendment of task 16.14's text in this pull request

### Out of scope

- A published advisory: that is task 16.12's, for a revoked digest
- Any change to SECURITY.md or the workflows

## Dependencies

| Dependency | Type | Status | Notes |
| --- | --- | --- | --- |
| The channel enabled (Req 9.3) | nature | verified daily since 2026-09-08 | The Security tab shows "Report a vulnerability" |
| The task text amended (16.14) | spec | in this pull request | No response window is promised; the times are recorded as numbers |

## Risks

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The maintainer's token cannot read the report's thread through the API | possible (the scope) | the owner pastes the thread, or the maintainer reads it in the browser | The evidence quotes what the owner pastes, marked as such |
| The report is mistaken for a real vulnerability by a reader of the advisory list | low (the title says drill; nothing is published) | none | Named in the title and the closing comment |

## Open questions (the owner's calls)

- [ ] The report's subject (drafted: a published status the reporter believes wrong, for instance the drill definition's HIGH shown undecided while its issue was closed, SECURITY.md's own example of what to report)
- [ ] Closed as a drill rather than accepted into a draft advisory (drafted: closed; an advisory is 16.12's)

## References

- `SECURITY.md` "Reporting a vulnerability", "Advisories"; `.specs/dhc-catalogue-mvp/requirements.md` Req 9.2, 9.3, 9.4, 7.11; `tasks.md` 16.14, 16.12
- LOG 2026-09-08 (the channel found disabled and enabled); `.github/workflows/rescan.yml` (the Req 9.3 check)
