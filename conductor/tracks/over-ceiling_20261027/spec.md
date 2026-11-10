# Track specification: An undecided finding past its ceiling, the alarm raised and cleared, live

## Overview

**Track ID:** over-ceiling_20261027
**Type:** chore
**Priority:** high (the next drill of the live program; 16.6 fixes the finding after it)
**Created:** 2026-10-27
**Author:** the owner, drafted by the agent
**Spec source:** `.specs/dhc-catalogue-mvp/tasks.md` task 16.5 (task group 16, the live drills), its text amended by this track's pull request; Req 6.46 (the clocks), 6.47 (every undecided finding's age against the policy file's ceilings, published to the status issue), 6.49 (the ceilings declared in the policy file, the KEV ceiling among them), 7.11 (the ledger); design Decision 13

### Description

The drill definition's HIGH, CVE-2025-30204 on drill-app, has been undecided since task 16.4 removed its lapsed exception (#329, 2026-10-27): the status counts its age from 2026-10-18 against the HIGH ceiling of 90 days, `9 / 90` on 2026-10-27, over ceiling 0. No finding has ever been over its ceiling on a published status: the `over ceiling` count has read 0 on every run since the clocks were first published (2026-09-06), and the page has never marked a row. This track puts one finding over its ceiling for one rescan, reads what the status issue, the summary and the page do with it, and clears it the next day.

Task 16.5's text lowers the HIGH ceiling to one day. That value cannot move far: `triage.ceilings` is read by three mechanisms, not one. The status measures undecided ages against it (Req 6.47); the tier check (`scripts/check-exceptions.sh`, Req 6.50, 6.51) holds every unexpired exception's span to the ceiling of its finding's severity, and grafana's nine standing transfers run 60 days each (decided 2026-10-13, expiring 2026-12-12), so any HIGH ceiling under 60 days fails the daily rescan's invariants step on all nine by name; and the lint (`scripts/lint-accepted-risk.sh`, Req 6.11) bounds every entry by the largest ceiling, which with HIGH under 30 days becomes the CRITICAL's 30, so the same nine entries fail validation on every pull request, the ceiling pull request included. A 60-day ceiling puts nothing over: the finding is ten days old.

The policy file declares a second ceiling (Req 6.49): `triage.kev_ceiling`, 14 days, for a finding listed in CISA KEV, and the status applies it in place of the severity's to a KEV-listed undecided finding (`status.go`, `ceilingFor`). CISA does not list the finding, but the `kev-synthetic` drill input of task 16.8 does (`triage/drills/kev-synthetic.json`, one entry), and a dispatch carrying it publishes the status and the page with the KEV column read from that feed (register row M26, observed 2026-10-25). So the one value this drill changes is `kev_ceiling`, to one day, for one dispatched rescan: the finding, ten days old and listed by the substituted feed, is over a one-day ceiling. The tiers stay green, because no exception covers a finding either feed lists. The value is restored the same day; the next scheduled run reads CISA's feed, the finding is not listed, its ceiling is the HIGH's 90 days again, and the alarm clears.

### The mechanism, as read on 2026-10-27

`scripts/triage-policy.sh . kev-ceiling` reads `triage.kev_ceiling` as whole days and refuses a malformed duration; the rescan hands it to `rescan-status` with the severity ceilings. For each undecided finding on a supported digest the status computes `age = today - first seen` in whole UTC days and `ceiling = kev_ceiling if the finding is in the day's KEV set, else the severity's`, and flags `over_ceiling = age > ceiling`; the aggregates count the flagged rows (`over ceiling: N`), the status issue's table sorts them first and prints `age / ceiling`, the summary line names the count, and the page marks the row (`class="over"`) and the definition's card (`over ceiling N` in red) and prints the ceilings in its lead (`KEV N days`). Nothing fails on the count: the alarm is the published number and the marked row. The KEV set of a dispatched run with `drill: kev-synthetic` is the synthetic feed, the warning annotation naming the substitution; the invariants step evaluates every unexpired exception against that set (Req 6.51) and is green when none is listed. The change and the revert are one line each in `catalogue-policy.yaml`; `validate.yml` reads the file through the same reader and builds nothing for it.

## Functional requirements (EARS)

The subject names follow design.md: the Scan Pipeline (`rescan.yml`), the Repository, the owner.

### FR-1: The one-day KEV ceiling (Req 6.49)

THE Repository SHALL set `triage.kev_ceiling` to `1d` in `catalogue-policy.yaml` in one pull request, with a comment naming the drill and the revert, and the owner SHALL merge it; validation green (the reader accepts a whole day; no lint reads the KEV ceiling against the exceptions).

**Acceptance criteria:**

- [x] #331, squash 16727ab (merged 2026-10-27 20:27:46Z); the reader printed `1` on 9e49b2c; validate green

### FR-2: The breach (Req 6.46, 6.47)

WHEN the owner dispatches `rescan.yml` on main with `drill: kev-synthetic` after FR-1 merges THE Scan Pipeline SHALL publish the status with CVE-2025-30204 on drill-app listed in the day's KEV set, its age against a one-day ceiling and the row flagged over ceiling, `over ceiling: 1` in the aggregates and the summary, and SHALL deploy the page with the row and drill-app's card marked and the lead reading `KEV 1 days`; the invariants step SHALL pass (no unexpired exception covers a listed finding) and the run SHALL be green.

Notes: a dispatch attests the day's reports and re-attests changed documents as every dispatch does (register row M17), named here so the owner chooses it knowingly; the status and the page read KEV yes on the drill definition until the next scheduled run reads CISA's feed (M26). The age on 2026-10-27 is 9 days, on 2026-10-28 10 days; both are over a one-day ceiling.

**Acceptance criteria:**

- [x] Run 40578319282 (20:28:12Z to 20:45:00Z); the row `**9 / 1**`, KEV yes, `over_ceiling: true`; `undecided: 2 (over ceiling: 1, oldest: 9 days)`; the summary line is in the job summary (not readable through the API; the status outputs carry the same count); the page's lead `KEV 1 days`, the card `over ceiling 1`, the row `class="over"`; the invariants step green at 20:40:09Z, the run green

### FR-3: The revert (Req 6.49)

THE Repository SHALL restore `triage.kev_ceiling` to `14d` in one pull request the same day, the comment recording the drill's run, and the owner SHALL merge it; no scheduled run SHALL read the one-day value.

Notes: a scheduled run reads CISA's feed; a one-day KEV ceiling would re-tier any exception covering a finding CISA listed overnight, which none does today. The revert the same day bounds that window.

**Acceptance criteria:**

- [x] #332, squash ebd0f65 (merged 20:52:45Z); no scheduled run between 20:27:46Z and 20:52:45Z

### FR-4: The clear (Req 6.47)

WHEN the next scheduled rescan runs after FR-3 merges THE Scan Pipeline SHALL publish the status with the finding not listed in KEV, its age against the HIGH ceiling of 90 days, `over ceiling: 0`, and the page unmarked.

Notes: the clear is read on the scheduled run, the declared feed. A second dispatch with `drill: kev-synthetic` after the revert would show the finding listed and under the restored 14-day ceiling, the same alarm cleared by the value alone; it is the owner's call and not required.

**Acceptance criteria:**

- [x] Run 40693681245; `10 / 90`, KEV no; `over ceiling: 0`; the page unmarked, `KEV 14 days`

### FR-5: The evidence (Req 7.11)

THE Repository SHALL add the LOG entry `## 2026-10-27: the drill's finding over its ceiling, the alarm raised by a one-day KEV ceiling and cleared (task 16.5)`, append the drill's observation to ledger rows 6.46, 6.47 and 6.49 (exercised by nature since September; the over-ceiling flag true for the first time), add the task table row for 16.5, tick task 16.5, move `tasks/todo.md` to 16.6 and close this track, in the evidence pull request opened once FR-4's run is in; it SHALL also tick the closure boxes left open in track `exception-lapse_20261025`'s plan (the drill pull request #324 closed 2026-10-27 13:02:28Z, the hand-over to this track).

**Acceptance criteria:**

- [x] `scripts/lint-live-evidence.sh .` green (139 exercised); `scripts/lint-log-anchors.sh all .` green; the tick `[done 2026-10-28, #339; conductor track over-ceiling_20261027]`; `conductor/tracks.md` lists the track under Completed; 16.6 next in `tasks/todo.md`

## Scope

### In scope

- Two one-line policy pull requests (FR-1, FR-3) and the owner's one dispatch (FR-2)
- The observations on that dispatch and on the next scheduled run
- One evidence pull request (FR-5)
- The amendment of task 16.5's text in this pull request (the KEV ceiling, not the HIGH ceiling, and why)

### Out of scope

- Any change to the status tool, the page, the tier check or the lint: the drill reads what they do; a defect found is recorded with a follow-up task, not fixed here
- A decision on the finding: it stays undecided for 16.6, which fixes it
- Separating the three uses of `triage.ceilings` (the decision clock, the exception tier, the lint's bound): a follow-up item in `tasks/todo.md` if the owner wants it

## Dependencies

| Dependency | Type | Status | Notes |
| --- | --- | --- | --- |
| The finding undecided (task 16.4) | track | done 2026-10-27 (#329, 1a43a5a) | First seen 2026-10-18 as the status counts it |
| The `kev-synthetic` drill input (task 16.8) | track | done 2026-10-23 (#310) | The feed lists CVE-2025-30204 |
| The task text amended (16.5) | spec | in this pull request | The KEV ceiling in place of the HIGH ceiling; 6.47 added |

## Risks

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| CISA lists a CVE one of the catalogue's exceptions covers while the KEV ceiling is one day | low | the next scheduled run's invariants step fails on that exception by name (Req 6.51) | The revert merges the same day as the dispatch; a breach, if any, is read and recorded, the revert clears it |
| The dispatch lands after the day's scheduled run has published | certain on 2026-10-27 (the scheduled run published at 12:41Z) | the dispatch rewrites the status and the page with KEV yes for the rest of the day | Named here; the next scheduled run restores the declared feed's reading (M26) |
| The lowered value is read by a pull request's gate | none: the gate's tier check reads `kev_ceiling` only for a KEV-listed exception, and no pull request builds an image with one | none | Recorded |

## Open questions (the owner's calls)

- [x] The KEV ceiling (the owner's call by merging #330 and #331)
- [x] No second dispatch; the clear read on the scheduled run of 2026-10-28
- [x] The follow-up item added to `tasks/todo.md` in #339

## References

- `.specs/dhc-catalogue-mvp/requirements.md` Req 6.46, 6.47, 6.49, 6.50, 6.51, 7.11; `tasks.md` 16.5, 16.6
- `catalogue-policy.yaml` `triage.ceilings`, `triage.kev_ceiling`, `triage.drills`; `scripts/triage-policy.sh`; `triage/rescan/status.go` (`ceilingFor`, `aggregate`); `triage/rescan/page.html.tmpl`; `scripts/check-exceptions.sh`; `scripts/lint-accepted-risk.sh`
- `docs/CONVENTIONS.md` rows M17, M26; LOG 2026-10-25 (the synthetic feed), LOG 2026-10-26 (the finding undecided)
- Tracks `kev-ceiling_20261024` (#318 to #320), `exception-lapse_20261025` (#321, #324, #329)
