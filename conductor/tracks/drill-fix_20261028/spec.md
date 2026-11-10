# Track specification: The drill's findings fixed, the issue closed on the attested SBOMs, the fix clock, live

## Overview

**Track ID:** drill-fix_20261028
**Type:** chore
**Priority:** high (the live program; the way out the gate named for the drill definition; 16.7 needs a fixed finding to bring back)
**Created:** 2026-10-28
**Author:** the owner, drafted by the agent
**Spec source:** `.specs/dhc-catalogue-mvp/tasks.md` task 16.6 (task group 16, the live drills), its text amended by this track's pull request; Req 6.5 (the fix treatment), 6.46 (the clocks, the fix time among them), 6.52 (an open issue whose finding left every supported digest is closed, naming the digests and the scanner versions), 6.56 (the closure graded by its evidence, `resolved:fixed` solely on attested SBOMs), 7.11 (the ledger); design Decision 13; register row M10 (fix-forward hand-bumps)

### Description

The drill definition carries two findings on purpose (LOG 2026-10-18): CVE-2017-20146, CRITICAL, `github.com/gorilla/handlers` v1.2.1 (fixed in 1.3.0), accepted under an exception until 2026-11-17; and CVE-2025-30204, HIGH, `github.com/golang-jwt/jwt/v5` v5.2.1 (fixed in 5.2.2), undecided since task 16.4 removed its lapsed exception, with cve issue #325 open since 2026-10-26 and the fail-closed gate's refusal of 2026-10-28 (task 16.9) naming the fix as one of its four ways out. The catalogue's fix lane for a compile-from-source image between upstream releases is a `go/bump@v2` step in the definition's fetch phase, with a Renovate marker and a LOG entry naming when the step is dropped (M10, the cert-manager episodes of 2026-09-02 and 2026-10-12). This track takes that lane on the drill definition: both modules bumped to their fixed versions in one pull request, the release that follows the merge, the next scheduled rescan closing #325 as `resolved:fixed` on the attested SBOMs and publishing both findings as fixed with their fix times, the CRITICAL's exception retired as moot. The issue closures and the fix clock have run by nature since September (ledger rows 6.46, 6.52, 6.56); what is new is a fix watched end to end on a definition whose first-seen dates are known to the day, and a fixed finding that 16.7 can bring back.

### The mechanism, as read on 2026-10-28

On the pull request, `build.yml` builds drill-app (its `image.yaml` changed), the bump step runs before `go/build@v1` and the scan gate sees nothing uncovered; govulncheck reaches no vulnerable symbol. After the merge, main's push build releases a new digest through the release path: the release-time scan reports nothing within the aperture, the compiled OpenVEX document carries no statement for either finding (the CRITICAL's unexpired exception publishes an `affected` statement only when the report lists the finding as suppressed; it will not), the digest is signed, attested and tagged, and the three catalogue tags move to it, leaving the digest of 2026-10-28 11:45Z untagged and frozen (Req 2.11). The next scheduled rescan scans the new supported digest, finds CVE-2025-30204 in no supported digest's attested report, and the lifecycle closes the issue, #325, with a comment naming every supported digest examined and the reports' scanner and database versions (Req 6.52), the label `resolved:fixed` if the SBOMs attested to the supported digests prove the package version bumped past the fixed version, else `resolved:absent` (Req 6.56, read, not predicted). The status computes the fix time as the first day a finding is absent, reported and suppressed alike, from every supported digest of the repository (Req 6.46): both findings fixed that day, days to fix counted from the status's first-seen dates (2026-10-18 for both), the median days to fix recomputed; the page's card shows the definition with no finding within the aperture and the fixed count. The CRITICAL's exception then suppresses nothing (`accepted-risk-report.sh` says so on the next drill-app build) and is retired in the evidence pull request as moot, the shape of the grafana retirements of 2026-10-19.

## Functional requirements (EARS)

The subject names follow design.md: the CI Pipeline (`build.yml`), the Scan Pipeline (`rescan.yml`), the Repository, the owner.

### FR-1: The bump (Req 6.5; M10)

THE Repository SHALL add to `image/drill-app/image.yaml` one `go/bump@v2` step before the build step, in the drill's work directory, bumping `github.com/gorilla/handlers` to v1.3.0 and `github.com/golang-jwt/jwt/v5` to v5.2.2 with Renovate markers, in one pull request whose build of drill-app is green at the scan gate with nothing uncovered and whose govulncheck step reaches no vulnerable symbol; the owner SHALL merge it.

Notes: the drill's source repository keeps its go.mod on purpose; the bump happens in the fetch phase, the cert-manager shape. The step is dropped by drill 16.7, the regression, which the LOG entry names as the drop.

**Acceptance criteria:**

- [x] #342, squash 57ebed4; build run 40766991968 green at the scan gate with no annotation, govulncheck clean, the tier step green; validate 40766992134 green

### FR-2: The release (Req 2.7, 2.9)

WHEN the bump merges THE CI Pipeline SHALL release a new drill-app digest on main: the release-time scan reporting nothing within the aperture, the digest signed, its SBOMs and OpenVEX attested, the three tags moved to it; the OpenVEX document SHALL carry no statement for CVE-2017-20146 or CVE-2025-30204.

**Acceptance criteria:**

- [x] Run 40769247657; `sha256:5cacd03bc770fd5374674ce3c8b0e7fd4d4342a66438668f78d1cbe7dcb00d77`, the three tags on it; the OpenVEX attestation with no statement at all; the SBOMs listing v5.2.2 and v1.3.0

### FR-3: The closure (Req 6.52, 6.56)

WHEN the next scheduled rescan runs after FR-2 THE Scan Pipeline SHALL close the issue, #325, with a comment naming every supported digest examined and the reports' scanner and database versions, labelled by its evidence: `resolved:fixed` on the attested SBOMs proving `github.com/golang-jwt/jwt/v5` bumped past 5.2.2, `resolved:absent` otherwise, as observed.

Notes: the CRITICAL has no issue; it was decided at onboarding. A dispatch after the release would close the issue the same day (register row M17, a release of attestations); drafted: the scheduled run.

**Acceptance criteria:**

- [x] Run 40788144199 (the owner's dispatch); the comment quoted in the LOG; `resolved:fixed`; no annotation on the job

### FR-4: The fix clock (Req 6.46)

WHEN that rescan publishes the status THE Scan Pipeline SHALL list both findings as fixed with the fix day, their days to fix counted from 2026-10-18, and SHALL recompute the median days to fix; the page SHALL show drill-app's card with no finding within the aperture and the fixed count.

**Acceptance criteria:**

- [x] `findings: 45; undecided: 4 (over ceiling: 0, oldest: 7 days); decided: 10; fixed: 31`, median days to fix unchanged at 4 (two tens among thirty-one fixed findings); both findings `fixed` 2026-10-28 with `days_to_fix` 10; the page's card `CRITICAL 0 · HIGH 0; undecided 0, over ceiling 0; fixed 3`, the three fixed findings listed beneath (the drill's two and CVE-2026-111943, fixed by the rebuild of 2026-10-24)

### FR-5: The exception retired (Req 6.11)

THE Repository SHALL remove CVE-2017-20146's entry from `triage/accepted-risk/drill-app.yaml` in the evidence pull request, the file kept with its header, the LOG naming the retirement as moot; `scripts/lint-accepted-risk.sh .` and `scripts/lint-log-anchors.sh all .` green.

Notes: the file stays (empty `vulnerabilities:`) so that the gate's exception report and 16.7's re-decision have their place; whether an empty file lints clean is read, not predicted.

**Acceptance criteria:**

- [x] The entry gone (`vulnerabilities: []`), the lints green with nine refs, the header saying so

### FR-6: The evidence (Req 7.11)

THE Repository SHALL append the drill's observation to ledger rows 6.46, 6.52 and 6.56, add the task table row for 16.6, add the LOG entry `## 2026-10-28: the drill's findings fixed, the issue closed on the attested SBOMs, the fix clock (task 16.6)`, tick task 16.6, move `tasks/todo.md` to 16.7 and close this track, in the evidence pull request opened once FR-3's run is read.

**Acceptance criteria:**

- [x] `scripts/lint-live-evidence.sh .` green (141 exercised); `scripts/lint-log-anchors.sh all .` green; the tick `[done 2026-10-28, #344; conductor track drill-fix_20261028]`; `conductor/tracks.md` lists the track under Completed; 16.7 next in `tasks/todo.md`

## Scope

### In scope

- One pull request bumping the two modules (FR-1); the release it triggers (FR-2); the next scheduled rescan (FR-3, FR-4)
- One evidence pull request (FR-5, FR-6)
- The amendment of task 16.6's text in this pull request

### Out of scope

- Any change to the lifecycle, the status tool, the compiler or the workflows: the drill reads what they do; a defect found is recorded with a follow-up task, not fixed here
- The regression (16.7): its own track, which drops the bump step and brings the findings back
- The frozen digests of 2026-10-28: they stay frozen (Req 2.11)

## Dependencies

| Dependency | Type | Status | Notes |
| --- | --- | --- | --- |
| The finding undecided with an open issue (tasks 16.4, 16.5) | track | done (#329, #339) | #325 open since 2026-10-26 |
| The fail-closed drill (task 16.9) | track | done (#336) | The gate named the fix as the way out; the switch is off again |
| The task text amended (16.6) | spec | in this pull request | The hand bump in the fetch phase, not a Renovate bump; the exception retired |

## Risks

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The SBOM grader cannot prove the bump and the issue closes `resolved:absent` | low (the cert-manager fixes closed `resolved:fixed` on SBOM evidence) | the label differs from the task text | Read and recorded as observed; row 6.56 says which |
| Renovate opens a pull request against the bump step's markers | expected over time | one more bump pull request | M10's intent; the drill's drop is 16.7's |
| The nightly rebuild republishes drill-app before the scheduled rescan | low | a second fixed digest, the tags moved again | Harmless; the rescan reads whatever the tags reference |

## Open questions (the owner's calls)

- [x] The owner's dispatch the same evening (run 40788144199)
- [x] Retired in #344
- [x] Markers on both deps

## References

- `.specs/dhc-catalogue-mvp/requirements.md` Req 2.7, 2.9, 2.11, 6.5, 6.11, 6.46, 6.52, 6.54, 6.56, 6.57, 7.11; `tasks.md` 16.6, 16.7
- `image/drill-app/image.yaml`, `image/cert-manager-controller/image.yaml` (the `go/bump@v2` shape), `triage/accepted-risk/drill-app.yaml`, `triage/rescan/lifecycle.go`, `triage/rescan/status.go`; `docs/CONVENTIONS.md` rows M10, M17
- LOG 2026-10-18 (the drill onboarded, two decisions), 2026-10-26 (the lapse), 2026-10-27 (tasks 16.5 and 16.9), 2026-09-02 and 2026-10-12 (the fix lane on cert-manager), 2026-10-19 (exceptions retired as moot)
