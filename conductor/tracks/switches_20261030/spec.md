# Track specification: The switches, one run each: the page off, every rebuild published, live

## Overview

**Track ID:** switches_20261030
**Type:** chore
**Priority:** high (the live program; two rows no other drill reaches)
**Created:** 2026-10-30
**Author:** the owner, drafted by the agent
**Spec source:** `.specs/dhc-catalogue-mvp/tasks.md` task 16.13 (task group 16, the live drills), its text amended by this track's pull request; Req 2.17 (the always policy publishes every scheduled rebuild), 3.12 (a chart's digest-only update automerges on green), 6.61 (the page rendered and published where the policy enables it), 6.62 (a disabled site, a failed deployment or stale served data fails the run), 7.11 (the ledger); design Decision 12 (the page) and 13 (the drills)

### Description

Two declared switches have never been flipped live. `release.publish_policy` has been `on-change` since the daily rebuild landed: the comparator discards a scheduled rebuild whose package set equals the published one (Req 2.15, exercised nightly) and publishes on a difference (2.16, exercised); the `always` policy (2.17), which publishes every rebuild whatever the verdict, has run in no job. `release.page` has been `true` since the page went live on 2026-09-09: the rescan renders the page and deploys it daily (6.61), and the read-back check holds the served data to the run's (6.62, its pass branch daily, its failure branch never). This track flips both switches for one day through one pull request, reads the two scheduled runs of that day, and flips them back through a second. The design names exactly this: switches flip for one run each through a normal pull request and flip back (Decision 13).

What the always policy costs is stated here so that the owner confirms it by merging: the nightly rebuild publishes every active definition, seven images (hardened-app, the three cert-manager images, valkey, valkey-compat, drill-app), each a full release of about five to ten minutes, seven new digests with the tags moved and the previous digests left frozen (Req 2.11), drill-app's release carrying its undecided HIGH as `under_investigation` (the fail-closed switch is off), and, for every chart pinning one of these images by digest, a Renovate digest-only pull request that automerges on green (Req 3.12): today that is the hardened-app chart alone. The page switch costs nothing: the rescan skips its page job by the switch and stays green, and the served page keeps the previous day's data, its own generation date saying so.

Req 6.62's failure branch is not reachable by a switch: the policy switch off skips the page job, it does not fail it. The branch runs when Pages is disabled on the repository while the policy is on (the deployment is refused and the run fails by name), an owner action in the repository settings, reversible, with no data lost. The track drafts it as the owner's call: with it, row 6.62 flips to `exercised`; without it, the row records the skip observed and its failure branch unexercised with that reason.

### The mechanism, as read on 2026-10-30

`scripts/release-policy.sh . publish-policy` and `. page` read the two switches as the exact tokens the criteria name (`on-change` or `always`; `true` or `false`) and `release-policy.sh . check` holds the file on every validate run. In `build.yml`'s scheduled path the comparator step computes its verdict for every active definition and sets `publish=false` only under `on-change` with an equal package set; under `always` every definition proceeds to the push, the release-time scan, the attestations, the signature and the tags, as a push would (the verdict still printed in the summary). In `rescan.yml` the rescan job reads the page switch into an output; the page artifact upload and the page job (`publish the catalogue page`) are keyed on it, so with the switch off the job is skipped and the run's conclusion does not include it; the read-back step inside the page job (`the served status data is this run's (Req 6.62)`) polls the served `metrics.json` for the run's generation date and fails the run by name when it never appears, and the deployment step fails when Pages is disabled. The rescan's nightly schedule (`17 6 * * *`) and the build's (`47 4 * * *`) have been landing between 10:00 and 13:30 UTC these last days.

## Functional requirements (EARS)

The subject names follow design.md: the Repository, the CI Pipeline (`build.yml`), the Scan Pipeline (`rescan.yml`), the Renovate Automation, the owner.

### FR-1: The switches flipped (Req 2.17, 6.61)

THE Repository SHALL set `release.publish_policy` to `always` and `release.page` to `false` in `catalogue-policy.yaml` in one pull request, each line's comment naming the drill and the revert, and the owner SHALL merge it before the next scheduled rebuild; validation green.

**Acceptance criteria:**

- [ ] The pull request's number and squash; `scripts/release-policy.sh . check` printing both values on that commit; validate green

### FR-2: Every rebuild published (Req 2.17)

WHEN the scheduled rebuild runs with the always policy THE CI Pipeline SHALL publish every active definition through the release path whatever the comparator's verdict: seven releases, each signed, attested and tagged, the summaries naming the verdicts and the policy.

**Acceptance criteria:**

- [ ] The run's id, the seven build jobs with their verdicts and outcomes, the new digests the tags reference (registry read); drill-app's document carrying `under_investigation` for its HIGH

### FR-3: The page skipped (Req 6.61)

WHEN the scheduled rescan runs with the page switch off THE Scan Pipeline SHALL skip the page artifact upload and the page job, SHALL stay green, and the served page SHALL keep the previous run's data, its generation date naming that day.

**Acceptance criteria:**

- [ ] The run's id, the page job absent or skipped, the run green; the served page read with the previous day's generation date

### FR-4: The deployment refused (Req 6.62), the owner's call

WHERE the owner disables Pages on the repository for one scheduled rescan after the switch is back on THE Scan Pipeline SHALL fail that run naming the refused deployment, and WHEN Pages is enabled again THE Scan Pipeline SHALL deploy on the next run.

Notes: the owner's action, in the repository's Pages settings, reversible; without it the row's failure branch stays unexercised with that reason and this track closes on FR-1 to FR-3 and FR-5.

**Acceptance criteria:**

- [ ] The run's id and the page job's failing step and line; the next run's deployment; or the owner's word that the branch stays unexercised

### FR-5: The revert and the evidence (Req 7.11)

THE Repository SHALL set both switches back in one pull request the day both runs are read, and SHALL flip ledger row 2.17 to `exercised` (inducer `switch`) and row 6.62 to `exercised` or leave it with its reason, append the observation to rows 2.15, 3.12 and 6.61, add the task table row for 16.13, add the LOG entry `## 2026-10-31: the switches, one run each: every rebuild published, the page off, the deployment refused (task 16.13)`, tick task 16.13, move `tasks/todo.md` to 16.12 and close this track, in the evidence pull request opened once the chart's digest pull request has merged.

**Acceptance criteria:**

- [ ] `scripts/lint-live-evidence.sh .` green (144 or 145 exercised); `scripts/lint-log-anchors.sh all .` green; the tick `[done <date>, #nnn; conductor track switches_20261030]`; `conductor/tracks.md` lists the track under Completed; 16.12 next in `tasks/todo.md`

## Scope

### In scope

- Two one-line policy pull requests (FR-1, FR-5) and the two scheduled runs between them
- The chart digest pull request the republish triggers, read as it merges (Req 3.12)
- The owner's Pages action, if chosen (FR-4)
- One evidence pull request (FR-5)
- The amendment of task 16.13's text in this pull request

### Out of scope

- `release.public`: its disabled branch harms consumers and is recorded as exercised in the private era
- Any change to the workflows or the policy reader: the drill reads what they do; a defect found is recorded with a follow-up task, not fixed here
- The frozen digests the republish leaves: they stay, as Req 2.11 says

## Dependencies

| Dependency | Type | Status | Notes |
| --- | --- | --- | --- |
| The scheduled rebuild and rescan of 2026-10-31 | nature | the day after the merge | Both read main at their start |
| Renovate's digest tracking of chart pins | nature | runs about every five hours | The hardened-app chart pins by digest; the cert-manager and valkey charts do not |
| The task text amended (16.13) | spec | in this pull request | One pull request for both switches, the costs, 6.62's failure branch as the owner's action |

## Risks

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| A rebuild fails for one definition under the always policy | low (every nightly has been green) | one definition unpublished, the run red by name | Read and recorded; the policy is not the cause |
| The revert lands after a second night | low | a second republish of everything | The revert pull request is prepared in advance and opened the moment both runs are read |
| The page switch off hides a real finding for a day | none: the status issue is published regardless; the page is the picture | none | Named |

## Open questions (the owner's calls)

- [ ] Both switches in one pull request for one day (drafted: yes)
- [ ] Pages disabled for one run to reach Req 6.62's failure branch (drafted: the owner's call; the track closes either way)
- [ ] The evidence opened after the chart's digest pull request has merged (drafted: yes, so that Req 3.12 is read in the same entry)

## References

- `.specs/dhc-catalogue-mvp/requirements.md` Req 2.11, 2.14 to 2.17, 3.12, 6.61, 6.62, 7.11; `tasks.md` 16.13
- `catalogue-policy.yaml` `release`; `scripts/release-policy.sh`; `.github/workflows/build.yml` (the comparator, the publish guard); `.github/workflows/rescan.yml` (the page output, the upload, the page job, the read-back); `docs/CONVENTIONS.md` row M23
- LOG 2026-09-09 (the page), the entries of 2026-10-28 and 2026-10-29 (the drill's releases)
