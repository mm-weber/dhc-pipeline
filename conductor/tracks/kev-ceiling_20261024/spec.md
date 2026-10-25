# Track specification: The KEV ceiling on a standing exception, both arms refuse by name, live

## Overview

**Track ID:** kev-ceiling_20261024
**Type:** chore
**Priority:** high (the next drill of the live program; 16.4 and 16.5 build on its exception)
**Created:** 2026-10-24
**Author:** the owner, drafted by the agent
**Spec source:** `.specs/dhc-catalogue-mvp/tasks.md` task 16.3 (task group 16, the live drills), its text amended by this track's pull request; Req 6.50 (the gate fails an exception whose expiry exceeds its tier, naming it), 6.51 (the rescan reports every unexpired exception over its tier against today's KEV as a failure of the run), 6.46 (the status's KEV column), 7.11 (the ledger); design Decision 13 (live drills; the `drill input` as one of the five ways to induce an event)

### Description

Every accepted-risk exception carries a decision date and an expiry, and both arms hold the span between them to a tier: the ceiling for the finding's severity (90 days for a HIGH, 30 for a CRITICAL), or 14 days when CISA lists the finding as exploited, whatever its severity (`catalogue-policy.yaml` `triage.kev_ceiling`; `scripts/check-exceptions.sh`). The gate evaluates the one image's exceptions on every pull request build (Req 6.50); the rescan evaluates every unexpired exception daily against today's KEV, because KEV lists grow after decisions are made (Req 6.51). Neither refusal has ever run live: no exception has exceeded its tier in 1,028 runs, and ledger rows 6.50 and 6.51 wait for this drill.

The drill definition's HIGH, CVE-2025-30204 (`github.com/golang-jwt/jwt/v5` v5.2.1, `ParseUnverified` reachable by design), is covered by an accept exception decided on 2026-10-18 and expiring on 2027-01-16: 90 days, the HIGH tier exactly. CISA's catalogue does not list that CVE (measured 2026-10-15), so task 16.8 shipped a feed of this repository that does, `triage/drills/kev-synthetic.json`, and the `drill: kev-synthetic` dispatch value that substitutes it for one run (#310). The moment the feed lists the CVE, the standing 90-day exception is 76 days over the 14-day KEV tier. This track lets both arms meet that exception: the rescan first, on a dispatch with `drill: kev-synthetic`, the realistic case of a list that grew after the decision, reported as a failure of the run while the run publishes its status with the KEV column reading yes; then the gate, on the drill pull request's first commit, which points `triage.kev_feed` at the synthetic feed and names drill-app in the build matrix. The same pull request then re-decides the exception to one day from its decision date (the owner's call of 2026-10-25: the shortest window that keeps the pass day clean), within the KEV tier, drops the drill lines, and merges; task 16.4's lapse drill follows from the next day. A second dispatch shows the re-decided exception passing the tier against the synthetic feed, with the status reading KEV yes once more; the next scheduled run reads CISA's feed again.

Nothing in the code changes. The drill substitutes declared values (the `kev-synthetic` address, by input and by the policy line) and makes one decision in the exception lane, the owner's, argued in the LOG as every decision is (register row M3).

### Background

Task 16.3's text (2026-10-01) planned a re-decision beyond the ceiling to make the gate fail, then a correction. With the synthetic feed in hand the standing exception already breaches the KEV tier, so the gate's refusal needs no exception written over its tier: the drill pull request's first commit substitutes the feed, as #313 substituted the outage address (task 16.8, Req 6.59), and the standing entry is refused. The task text is amended by this track to say so, to name the order (the rescan's half first, on the standing exception), and to tie the correction's expiry to 16.4: the correction is 16.4's re-decision, so 16.4 needs no re-decision of its own and its first half (the expiry warning inside the 14-day window, Req 6.10) is observed by this track's second dispatch and by the first scheduled run after the correction merges. The owner's calls: 2026-10-24, keep the total expiry short, no waiting on an arbitrary timeline; 2026-10-25, shorter than the four days drafted from 16.4's text, nothing waits four days. The window is one day: zero days would have Trivy count the finding on the pass day itself (FR-3's notes), one day keeps the pass clean and lets Trivy count the finding again from 00:00 UTC of the next day.

The dispatch path of `rescan.yml` is a release of attestations (register row M17): a dispatched run attests today's scan reports with replace and re-attests the OpenVEX document where it changed. Both dispatches of this track keep that behaviour. Unlike the `kev-outage` drill, a `kev-synthetic` run has its KEV set on disk, so the enrich step, the issue set, the status issue and the page all publish; the run is red only when an exception breaches its tier, by name. Register row M26 and the manual say today that a drill run publishes no issue set, status or page; that sentence is true of `kev-outage` alone and this track corrects it once the behaviour is observed.

### The state on 2026-10-24

`triage/accepted-risk/drill-app.yaml` holds two entries: CVE-2017-20146 (CRITICAL, accept, 2026-10-18 to 2026-11-17) and CVE-2025-30204 (HIGH, accept, 2026-10-18 to 2027-01-16, its statement already naming drill 16.3's re-decision). The policy's tiers: HIGH 90, CRITICAL 30, KEV 14, the largest 90, the expiry warning window 14. `check-exceptions.sh` reports a breach as `<file>: <cve> runs <span> days from <decided> to <expiry>, over its <tier>-day ceiling (listed in CISA KEV)` and ends with `<n> exception(s) over their tier across <m> checked (Req 6.50/6.51)`; a pass prints `check-exceptions: ok <image> <cve>: <span> days within the <tier>-day ceiling (listed in CISA KEV)`. The rescan's invariants step keeps `kev.json` on disk after a breach (it removes the file only when the fetch fails), so the steps behind it run; `rescan-status` reads the same file for its KEV column. The build matrix derives from changed `image/<name>/image.yaml` paths alone, so a change to the exception file builds nothing. The status issue #151 showed CVE-2025-30204 with KEV no on every run so far. Task 16.8 closed on 2026-10-24 (#314, squash 1ef1bb8); the scheduled rescan runs once a day (cron 06:17 UTC, started between 11:12Z and 12:01Z of late).

## Functional requirements (EARS)

The subject names follow design.md: the Scan Pipeline (`rescan.yml`), the Scan Gate (`build.yml` on a pull request), the Repository (files under version control).

### FR-1: The list grows after the decision, the rescan reports it (Req 6.51, 6.46)

WHEN a dispatch of `rescan.yml` carries `drill: kev-synthetic` while the drill definition's HIGH is covered by its 90-day exception THE Scan Pipeline SHALL report that exception as over the 14-day KEV tier, naming the file, the finding, the span and the tier, as a failure of that run, and SHALL publish that run's issue set, status issue and catalogue page with that finding's KEV column reading yes.

Notes: the invariants step fetches the synthetic feed in place of the declared one (the warning annotation names the drill and the address), `check-exceptions.sh rescan` prints the breach line and the `1 exception(s) over their tier` line, the step exits 1 and the run is red; `kev.json` stays, so the enrich step, the issue set (nothing new to file: the drill's findings are suppressed by their exceptions), the status (`rescan-status` reads `kev.json`: the row for CVE-2025-30204 flips to yes) and the page publish. The owner dispatches after the day's scheduled run, told beforehand what the dispatch publishes (M17) and that the status issue and the page will read KEV yes on a drill definition until the next scheduled run.

**Acceptance criteria:**

- [x] The run's id recorded; its invariants step red with `triage/accepted-risk/drill-app.yaml: CVE-2025-30204 runs 90 days from 2026-10-18 to 2027-01-16, over its 14-day ceiling (listed in CISA KEV)` and the `(Req 6.50/6.51)` line; the summary's `- drill: kev-synthetic (...)` line (run 40187973579, 2026-10-25 11:13Z, job 121152713348, step 14 red at 11:24:49Z; the summary is the owner's to read)
- [x] The status issue's body of that run shows CVE-2025-30204 with KEV yes; the page job green; the issue set filed nothing (#151 updated 11:30:36Z: drill-app CVE-2025-30204 HIGH, KEV yes, decided (affected); page job 121156288850 green at 11:31:01Z; the filing step skipped, nothing to file)

### FR-2: The gate refuses the standing exception (Req 6.50)

THE Repository SHALL carry, on the drill pull request's first commit, `triage.kev_feed` set to the declared `kev-synthetic` address and one comment line in `image/drill-app/image.yaml` naming this drill, so that the build names drill-app and its `exception tiers against KEV` step fails naming the standing exception, its 90-day span and the 14-day tier, and Req 6.50.

Notes: the same shape as #313 (task 16.8): the policy edit alone builds nothing, the comment line is the smallest change that puts drill-app in the matrix, the build and the scan run before the tiering step as on every drill-app pull request. The feed line and the comment line never merge: the second commit removes both. The breach line is the one of FR-1, in the gate's mode (the one image's file); the gate step's annotation is the `exception(s) over their tier` line.

**Acceptance criteria:**

- [x] The build run red at `exception tiers against KEV (Req 6.50)` with the breach line and the `(Req 6.50/6.51)` line; validate green; the run id recorded in ledger row 6.50 (#319 commit ee48046: build run 40188092683, job 121153084106, step 19 red at 11:20:15Z; validate run 40188092562 green)
- [x] The merged diff carries neither the feed line nor the comment line (squash 714614f: the exception file, the LOG, the ledger, the plan, the spec)

### FR-3: The re-decision, one day (Req 6.7, 6.50; task 16.4's premise)

THE Repository SHALL re-decide the drill's HIGH on the same pull request's second commit: `decided_at` the decision date D, `expired_at` D plus one day, the statement naming this drill and the lapse drill 16.4 watches, `ref` anchored to a LOG heading that argues the re-decision (register row M3), and THE Repository SHALL flip ledger rows 6.50 and 6.51 to `exercised` in that commit with the run ids of FR-1 and FR-2.

Notes: one day is within the 14-day KEV tier and is 16.4's re-decision (its text said four days out; amended to one on 2026-10-25), so 16.4 re-decides nothing: its warning half (Req 6.10, the expiries step inside the 14-day window, the page listing the entry as lapsing) is observed by this track's second dispatch (`expires in 1 days`) and by the first scheduled run after the merge (`expires in 0 days`); `lint-accepted-risk.sh` passes with that warning (the window is 14 days). The lapse half runs on two clocks, both 16.4's to observe: Trivy drops an ignore entry once its `expired_at`, read as midnight UTC of that date, is before now (`pkg/result/ignore.go`, `Prune`: `ExpiredAt.Before(clock.Now(ctx))`, the same line in the pinned 0.75.0), so the scan counts the finding again from 00:00 UTC of D plus one; this repository's lint and compiler keep the entry live through its expiry day (`expired` in `compile-vex.sh`: `exp < today`), so the compiler's `under_investigation` naming the lapse, with the first-seen time carried, can come no earlier than D plus two. Zero days was considered and refused: Trivy would count the finding on the pass day itself, and FR-4's run would show the lapse and the pass at once. The pull request's final build matrix is empty (no image path changed), so nothing is rebuilt or released by the merge. The LOG entry is the drill's entry, part one: the listing, the two refusals, the re-decision; part two (FR-4) follows in the evidence pull request. The ledger's task table row for 16.3 names the inducers as observed.

**Acceptance criteria:**

- [x] `scripts/lint-accepted-risk.sh .` green with the one warning naming CVE-2025-30204 and D plus one (`expires in 1 days`); `scripts/lint-log-anchors.sh all .` resolves the new `ref`; `scripts/lint-live-evidence.sh .` green with rows 6.50 and 6.51 `exercised`, inducer `drill input` (#319 commit 1c72e48, 2026-10-25)
- [x] The pull request's validate green and its build matrix empty on the second commit; the owner merges (the squash sha recorded): validate 40189524905 green; the matrix was not empty, `build.yml` names the image a changed exception file belongs to and build run 40189524943 passed (the plan's deviations log); merged 2026-10-25 11:55:37Z as 714614f

### FR-4: The re-decided exception passes the tier (Req 6.51, 6.46)

WHEN a dispatch of `rescan.yml` carries `drill: kev-synthetic` after FR-3 merges THE Scan Pipeline SHALL evaluate the re-decided exception against the synthetic feed and pass it, the invariants step green with `1 days within the 14-day ceiling (listed in CISA KEV)`, the run green, and SHALL publish the status with that finding's KEV column reading yes.

Notes: the pass is observable on this path alone; the merged pull request's gate reads CISA's feed, where the CVE is not listed, so its green says nothing about the KEV tier. The next scheduled run reads the declared feed again (KEV no); its expiries step warns `expires in 0 days` and its scan counts the finding again (Trivy's midnight rule, FR-3's notes): 16.4's observations, recorded in 16.4's track. The owner dispatches after the merge, told what the dispatch publishes (M17).

**Acceptance criteria:**

- [x] The run's id recorded; the invariants step green (the ok line as the owner reads it, or the step's green with no breach annotation); the status issue's row for CVE-2025-30204 reads KEV yes; the summary's drill line (run 40191153604, 2026-10-25 11:59Z, job 121162258991, the invariants step green at 12:08:34Z with no breach annotation; #151 at 12:14:23Z: KEV yes, accepted risk until 2026-10-26)
- [x] The next scheduled run's status reads KEV no again (its id recorded in the LOG; the expiry warning belongs to 16.4): the day's scheduled run 40189980851 ran between the two dispatches (11:42Z to 11:58Z, before the merge) and read CISA's feed, KEV no at 11:57:19Z; the first scheduled run after the pass is 2026-10-26's, drill 16.4's

### FR-5: Named where a reader meets it (Req 7.1, 7.11)

THE Repository SHALL state in `docs/CONVENTIONS.md`'s register row M26 and in `docs/user-manual.md`'s drill paragraph that a `kev-outage` run publishes attestations only while a `kev-synthetic` run publishes its issue set, status and page and is red only when an exception breaches the KEV tier, as observed by this track.

Notes: the register's sentence today ("the run is red by name ... and publishes no issue set, status or page") was written for the outage value; the first `kev-synthetic` run shows the other half. One sentence each, no new row.

**Acceptance criteria:**

- [x] `grep -c '^| M26 ' docs/CONVENTIONS.md` is 1 and the row names both values' behaviour; the manual's paragraph the same; no em-dashes added (#320)

### FR-6: The evidence (Req 7.11)

THE Repository SHALL add the LOG entry's second part (FR-4's run, the next scheduled run's KEV no), tick task 16.3 in `.specs/dhc-catalogue-mvp/tasks.md`, move `tasks/todo.md`'s program state to 16.4, and close this track, in a pull request opened as a draft until FR-4's run is in.

Notes: the LOG heading `## <D>: the drill's HIGH listed as exploited by the synthetic feed, the standing exception refused in both arms, re-decided to one day (task 16.3)`, part one in FR-3's pull request, part two here; the tick in the house shape `[done <date>, #nnn; conductor track kev-ceiling_20261024]`; the todo names 16.4's dates, D plus one and D plus two, and its track opens on D.

**Acceptance criteria:**

- [x] `scripts/lint-live-evidence.sh .` and `scripts/lint-log-anchors.sh all .` green; the tick present; `conductor/tracks.md` lists the track under Completed; 16.4 next in `tasks/todo.md` with D plus one and D plus two named (#320)

## Scope

### In scope

- Two dispatches with `drill: kev-synthetic` (FR-1, FR-4), the owner's
- One drill pull request: the gate's refusal on its first commit, the re-decision and the ledger rows on its second, merged (FR-2, FR-3)
- The register and manual sentences (FR-5); the LOG entry, the tick, the track's closure (FR-6)
- The amendment of task 16.3's text, and the note on 16.4's, in this pull request

### Out of scope

- Any change to `check-exceptions.sh`, `rescan.yml`, `build.yml` or the status tool: the drill reads what they do
- An exception written over its tier: the standing entry already breaches the KEV tier once the feed lists the finding
- The lapse (task 16.4): its own track, opened on D, the day FR-3 merges; the ceiling lowered (16.5) after it
- A listing in CISA's catalogue: the synthetic feed stands in, recorded as such on every run that reads it

## Dependencies

| Dependency | Type | Status | Notes |
| --- | --- | --- | --- |
| The `drill` input and `kev-synthetic` (task 16.8) | track | done 2026-10-24 (#310, #314) | The feed file, the declared address, the reader |
| drill-app published with its two exceptions (task 16.2) | track | done 2026-10-18 (#286) | The standing 90-day exception is the drill's object |
| The task text amended (16.3, a note on 16.4) | spec | in this pull request | The order, the gate's branch, the one-day expiry (four days until 2026-10-25) |

## Risks

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The status issue and the page read KEV yes on a finding CISA does not list | certain, by design, twice | a reader of #151 sees yes on the drill definition for part of a day | The definition is named a drill in every place it appears; the run's summary and annotation name the substitution; the next scheduled run reads CISA's feed |
| The drill pull request's first commit merges with the feed line | low | the scheduled rescan would evaluate against the synthetic feed | FR-2's acceptance checks the merged diff; the second commit removes both lines before the owner is asked to merge |
| The lapse begins before 16.4's track is open | medium | the lapse happens unobserved by a plan (the mechanism runs regardless: Trivy counts the finding again from 00:00 UTC of D plus one, `under_investigation`, re-attestation, the gate no longer counts the entry) | 16.4's track opens on D, the day FR-3 merges, before midnight UTC |
| Trivy and this repository read the expiry day differently | certain | on D plus one the scan counts the finding while the lint says `expires in 0 days` and the compiler keeps the entry live; the lapse note can follow on D plus two at the earliest | Named in FR-3's notes and in 16.4's task text; 16.4 observes both days and records whether the gap is a defect (Req 6.9, 6.41) |
| Both dispatches re-attest today's reports | certain (M17) | none: the day's reports, replaced by the day's reports | Named in each request to the owner |
| `raw.githubusercontent.com` serves a stale copy of the feed | none in practice | the file has not changed since #310 | Noted; the warning annotation carries the address |

## Open questions (the owner's calls)

- [x] Four days (16.4's number) or shorter: the owner's call of 2026-10-25, shorter; one day from the decision date (zero would put Trivy's un-suppression on the pass day; FR-3's notes)
- [x] The second dispatch for the pass (FR-4), or the gate's green and the lint alone: the dispatch, the owner's call by merging #318 and dispatching run 40191153604
- [x] Rows 6.50 and 6.51 flipped in the drill pull request rather than in the evidence pull request: in the drill pull request, the owner's call by merging #319

## References

- `.specs/dhc-catalogue-mvp/requirements.md` Req 6.7, 6.10, 6.46, 6.50, 6.51, 7.11; `design.md` Decision 13; `tasks.md` 16.3, 16.4
- `scripts/check-exceptions.sh`, `scripts/lint-accepted-risk.sh`, `scripts/triage-policy.sh` (`kev-ceiling`, `expiry-warning`, `drill-feed`)
- `triage/accepted-risk/drill-app.yaml`; `triage/drills/kev-synthetic.json`; LOG 2026-10-18 (the standing decision), LOG 2026-10-23 (the outage drill)
- Tracks `drill-definition_20261017` (the fixture), `kev-drill-input_20261023` (the input and the feed; #313's shape for the gate's branch)
- `docs/CONVENTIONS.md` rows M3, M17, M26; `docs/user-manual.md`, the dispatch paragraph
