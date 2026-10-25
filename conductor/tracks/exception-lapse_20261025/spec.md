# Track specification: The drill's exception expires, the lapse seen on every plane, live

## Overview

**Track ID:** exception-lapse_20261025
**Type:** chore
**Priority:** high (the next drill of the live program; 16.5 needs the finding undecided)
**Created:** 2026-10-25
**Author:** the owner, drafted by the agent
**Spec source:** `.specs/dhc-catalogue-mvp/tasks.md` task 16.4 (task group 16, the live drills), its text amended by this track's pull request; Req 6.9 (an expired exception counts as uncovered in the gate), 6.10 (expiring and expired exceptions reported daily), 6.41 (a lapsed exception compiles to under_investigation with its first-seen time and a note naming the lapse), 6.35 and 6.43 (cited, exercised by nature), 6.11 (a past expiry fails validation), 7.11 (the ledger); design Decision 13

### Description

Task 16.3 re-decided the drill definition's HIGH, CVE-2025-30204 on drill-app, to one day: `decided_at` 2026-10-25, `expired_at` 2026-10-26 (#319, squash 714614f). This track watches that entry expire and records what every plane does with the lapse, on the days it happens. Nothing in the code changes and no new decision is written; the lapsed entry is removed at the end so that validation is green again and the finding stays undecided for task 16.5.

Two clocks read the expiry day differently, found by task 16.3 and named in its LOG entry. Trivy drops an ignore entry once its `expired_at`, read as midnight UTC of that date, is before now (`pkg/result/ignore.go`, `Prune`; the pinned 0.75.0), so every scan from 2026-10-26 00:00 UTC reports the finding again. This repository's lint and compiler keep an entry live through its expiry day (`lint-accepted-risk.sh`: a warning at 0 days, an error only once the date is past; `compile-vex.sh`: `expired` means expiry before today), so the lint's `is in the past` and the compiler's note naming the lapse come on 2026-10-27. The day between is this drill's first finding: the gate and the rescan count the finding while the lint still says it expires today.

### The mechanism, as read on 2026-10-25

The rescan scans every supported digest through `scan-image.sh`, which hands Trivy the exception file as `--ignorefile`; the day's CVE set is the union of what those scans still report. The re-attestation step (`scripts/reattest.sh`, Req 6.42, 6.43) recompiles each digest's OpenVEX document daily from the hand-authored source, the exception file, that day's scan reports, the previously attested document and the open-issue map, and attests it when its set of statements differs from the attested one. The compiler publishes an unexpired exception that the report lists as suppressed as `affected`; a finding the report lists plain becomes `under_investigation`, its first-seen time carried from the previous document (Req 6.38), with a note naming the lapse when an expired exception named it (Req 6.41). The status reads the attested document: a statement `affected` is a decision, `under_investigation` or no statement is undecided. The issue reporter reads the day's reports and the open issues, nothing else; no cve issue exists for CVE-2025-30204, which arrived decided (task 16.2). The expiries step runs the lint and hands its `expires in` and `is in the past` lines to the page, which lists them on the definition's card, lapsed or lapsing. On a pull request, the build gate's scan runs the same `--ignorefile`, and the scan gate fails on anything uncovered within the aperture, naming it and saying that an expired exception counts as uncovered. `validate.yml` runs `lint-accepted-risk.sh`, so a past expiry fails every pull request's validation until the entry is re-decided or dropped (Req 6.11).

## Functional requirements (EARS)

The subject names follow design.md: the Scan Pipeline (`rescan.yml`), the Scan Gate (`build.yml` on a pull request), the VEX Compiler (`compile-vex.sh`), the Repository.

### FR-1: The warning (Req 6.10)

WHEN the rescan runs on 2026-10-25 and on 2026-10-26 THE Scan Pipeline SHALL report the entry in its expiries step as expiring in 1 and then 0 days, and the catalogue page SHALL list it on drill-app's card.

Notes: the first half is observed already: task 16.3's second dispatch (run 40191153604) warned `CVE-2025-30204 expires in 1 days (2026-10-26)` at 12:14:20Z; the page's card is read the same day. The scheduled run of 2026-10-26 warns `0 days`.

**Acceptance criteria:**

- [ ] The two runs' ids with their expiries-step annotations recorded in ledger row 6.10; the page's card read on both days

### FR-2: Trivy's day, the finding reported again (Req 6.38, 6.43, 6.46, 6.3)

WHEN the rescan runs on or after 2026-10-26 00:00 UTC THE Scan Pipeline SHALL report CVE-2025-30204 on drill-app in the day's scan (the ignore entry dropped by Trivy), SHALL recompile drill-app's document with that finding as `under_investigation` carrying its first-seen time of 2026-10-18 and re-attest the changed document, SHALL show the finding undecided in the status with that first-seen time, and SHALL file a cve issue for it.

Notes: on 2026-10-26 the compiler's note is the plain uncovered note, not the lapse note: the entry is live for the compiler through its expiry day. The lifecycle step runs before the issue set, so the new issue is filed by the reporter (no open issue exists), and the next run's lifecycle meets it. The scheduled run (about 11:15 to 12:00 UTC) suffices; a dispatch is a release of attestations (register row M17) and is the owner's call.

**Acceptance criteria:**

- [ ] The run's id; the re-attestation record for drill-app (`reattested: true`); the status issue's row for CVE-2025-30204 undecided with first seen 2026-10-18 and its age over the 90-day ceiling as the status counts it; the new issue's number and title
- [ ] What the status and the issue plane show on the day between the two clocks, recorded as observed (the first finding)

### FR-3: The gate counts the expired exception as uncovered (Req 6.9, 6.35)

WHEN a pull request names drill-app in the build matrix on or after 2026-10-26 00:00 UTC THE Scan Gate SHALL report CVE-2025-30204 as uncovered within the aperture and fail by name, its message saying that an expired exception counts as uncovered.

Notes: the drill pull request carries one comment line in `image/drill-app/image.yaml` (the shape of #313 and #319's first commit), is opened as a draft, is never merged and is closed with a comment after the evidence merges. The tier step before the gate evaluates the entry's one-day span as within its tier; the scan gate is the step that refuses.

**Acceptance criteria:**

- [ ] The build run red at the scan gate step (`Scan gate`, the step that fails on uncovered findings within the aperture) with the line naming drill-app, CVE-2025-30204 and the aperture; the run id in ledger row 6.9; validate green on that commit (the entry not yet past on 2026-10-26)

### FR-4: The lapse day (Req 6.10, 6.11, 6.41)

WHEN the rescan runs on or after 2026-10-27 00:00 UTC THE Scan Pipeline SHALL report the entry in its expiries step as `is in the past`, the page SHALL list it as lapsed, and THE VEX Compiler SHALL record for CVE-2025-30204 the `under_investigation` statement with the note naming the lapse (the exception's treatment, decision date and expiry, the finding still listed in the report).

Notes: whether a change of the note alone re-attests the document (Req 6.43 compares the set of statements) is observed, not predicted. From this day `validate.yml` fails every pull request on the past expiry (Req 6.11, by design) until FR-5 merges: named here so that the day's Renovate pull requests are read correctly.

**Acceptance criteria:**

- [ ] The run's id; the expiries-step annotation `expired_at 2026-10-26 is in the past`; the page's lapsed entry; the compiled document's note as the re-attestation record or the attested document shows it; validate red by name on a pull request of that day, if one runs before FR-5 merges

### FR-5: The entry leaves, the finding stays undecided (Req 6.11; task 16.5's premise)

THE Repository SHALL remove the lapsed entry for CVE-2025-30204 from `triage/accepted-risk/drill-app.yaml` in the evidence pull request on 2026-10-27, with the LOG naming the removal, so that validation is green and the finding stays undecided with its first-seen time carried, for task 16.5.

Notes: re-deciding would end 16.5's premise (an undecided finding past its ceiling). The CRITICAL's entry (CVE-2017-20146, expiring 2026-11-17) stays. The file's header comment is updated.

**Acceptance criteria:**

- [ ] `scripts/lint-accepted-risk.sh .` green with no warning for drill-app; `scripts/lint-log-anchors.sh all .` green (the removed entry's `ref` no longer counted)

### FR-6: The evidence (Req 7.11)

THE Repository SHALL flip ledger rows 6.9, 6.10 and 6.41 to `exercised` with the run ids, add the LOG entry `## 2026-10-26: the drill's exception expires, the lapse on every plane (task 16.4)` with its parts dated as observed, tick task 16.4, move `tasks/todo.md` to 16.5 and close this track, in the evidence pull request opened once FR-4's run is in; the drill pull request is closed unmerged after the evidence merges.

**Acceptance criteria:**

- [ ] `scripts/lint-live-evidence.sh .` green with 124 exercised; `scripts/lint-log-anchors.sh all .` green; the tick `[done <date>, #nnn; conductor track exception-lapse_20261025]`; `conductor/tracks.md` lists the track under Completed; 16.5 next in `tasks/todo.md`

## Scope

### In scope

- The observations of 2026-10-26 and 2026-10-27 (UTC) on the scheduled runs, or on the owner's dispatches
- One drill pull request for the gate (FR-3), never merged
- One evidence pull request (FR-5, FR-6)
- The amendment of task 16.4's text in this pull request

### Out of scope

- Any change to the lint, the compiler, the status tool or the workflows: the drill reads what they do; a defect found is recorded with a follow-up task, not fixed here
- A re-decision of the drill's HIGH: the finding stays undecided for 16.5
- The fail-closed release gate (16.9) and the fix (16.6): their own tracks

## Dependencies

| Dependency | Type | Status | Notes |
| --- | --- | --- | --- |
| The re-decided entry (task 16.3) | track | done 2026-10-25 (#319, 714614f) | Decided 2026-10-25, expiring 2026-10-26 |
| The task text amended (16.4) | spec | in this pull request | The two clocks, the recompile on the rescan, the entry removed at the end |

## Risks

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Validation red for every pull request on 2026-10-27 until FR-5 merges | certain, by design (Req 6.11) | Renovate's pull requests of that day show a red validate | Named here; the evidence pull request merges early that day; the red is itself FR-4's evidence |
| A cve issue filed for the drill definition | expected (Req 6.3) | one more open issue, named a drill by its image | Closed on evidence when 16.6 fixes the finding, or by the owner's decision; recorded |
| The two clocks disagree on 2026-10-26 | certain | the gate and the scan count the finding while the lint says it expires today and the compiler's note does not name the lapse | Recorded as observed; the owner decides whether it is a defect row (ledger status `defect`) with a follow-up task, or the documented difference |
| The lapse happens before this track is confirmed | low | the mechanism runs regardless | The scheduled run of 2026-10-26 is the first observation either way; its evidence is readable afterwards |

## Open questions (the owner's calls)

- [ ] A rescan dispatch on the evening of 2026-10-25 (from 00:00 UTC on 2026-10-26) for FR-2, or the scheduled run (drafted: the scheduled run; a dispatch is a release of attestations, M17)
- [ ] The lapsed entry removed in the evidence pull request rather than re-decided (drafted: removed; 16.5 needs the finding undecided)
- [ ] The day between the two clocks recorded as a defect row or as the documented difference (drafted: the owner's call after reading FR-2's observation)

## References

- `.specs/dhc-catalogue-mvp/requirements.md` Req 6.3, 6.9, 6.10, 6.11, 6.35, 6.38, 6.41, 6.43, 6.46, 7.11; `tasks.md` 16.4, 16.5
- `scripts/lint-accepted-risk.sh`, `scripts/compile-vex.sh` (`expired`, the lapse note), `scripts/reattest.sh`, `scripts/scan-image.sh`, `triage/rescan/status.go` (`readDigest`), `triage/rescan/cmd/internal/inputs/inputs.go` (lapsed, lapsing)
- `triage/accepted-risk/drill-app.yaml`; LOG 2026-10-25 (the re-decision and the two clocks)
- Track `kev-ceiling_20261024` (#318, #319, #320); `docs/CONVENTIONS.md` rows M3, M17
