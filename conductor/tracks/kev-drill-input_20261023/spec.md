# Track specification: The KEV drill input, a feed outage fails closed in both arms, live

## Overview

**Track ID:** kev-drill-input_20261023
**Type:** feature
**Priority:** high (the next drill of the live program; 16.3 depends on it)
**Created:** 2026-10-23
**Author:** the owner, drafted by the agent
**Spec source:** `.specs/dhc-catalogue-mvp/tasks.md` task 16.8 (task group 16, the live drills); Req 6.59 and 6.60 (a KEV feed outage fails the pull request gate and the scheduled rescan by name), 7.7 and 7.10 as amended by this track's pull request (a dispatch input is a declared value the policy lint holds), 7.11 (the ledger); design Decision 13 (live drills, the `drill input` as one of the five ways to induce an event)

### Description

Both arms of the catalogue fetch CISA's Known Exploited Vulnerabilities catalogue before they evaluate exception tiers: `build.yml`'s `exception tiers against KEV` step on every pull request build, and `rescan.yml`'s invariants step on every daily run. Both fail closed when the feed cannot be fetched (Req 6.59, 6.60), because evaluating with an empty KEV set would hand every exploited finding the widest tier. Neither branch has ever run live: the feed has never been unavailable in 1,028 runs, and the ledger rows 6.59 and 6.60 wait for this drill.

This track induces the outage on both arms without changing a code path. `rescan.yml`'s `workflow_dispatch` gains one input, `drill`, a choice among `none`, `kev-outage` and `kev-synthetic`; when it is not `none`, the invariants step reads the substitute address the policy file declares for that name and fetches it exactly as it fetches the declared feed. `kev-outage` names an address under the reserved `.invalid` top-level domain, which no resolver answers, so the fetch fails at once and the run takes its outage branch: the invariants step red naming the address and Req 6.60, the issue set, the status issue and the catalogue page withheld by name, the drill printed in the run summary; the next scheduled run reads the declared feed and publishes. `kev-synthetic` names a feed of this repository with one entry, the drill definition's HIGH, for task 16.3's use. The gate's half is a drill branch, never merged: the policy file's `kev_feed` set to the outage address, so the pull request build fails closed at its tiering step naming the address and Req 6.59.

The input's shape is a declared value like the crons and the permissions blocks: `catalogue-policy.yaml` declares every dispatch input a workflow accepts with its allowed values, `lint-workflow-policy.sh` holds the workflow literal equal to the declaration, and the substitutes live in the policy file's `triage` section, read through `triage-policy.sh`, the one reader of that section. A drill therefore substitutes a declared value for one run and never takes a different code path (task 16.8's rule).

### Background

Decision 13 (2026-10-01) names five ways a drill may induce an event: the owner, a pull request, the drill definition, a switch and a drill input. The first four have run (16.2 built the drill definition, the retire-grafana track flipped a switch and refused a pull request); this is the first drill input. The ledger's row 6.59 says "16.8 substitutes an unreachable URL on a drill branch", row 6.60 "16.8 dispatches the rescan with the `kev-outage` input", both induced by `drill input`.

The dispatch path of `rescan.yml` is a release of attestations (register row M17): a dispatched run attests today's scan reports to every published digest with replace and re-attests the OpenVEX document where the statement set changed, under the re-attester role; the owner dispatched it on 2026-10-22 (run 39770244509) and on 2026-10-23 (run 39959263177) to close decided findings on evidence. The drill run keeps that behaviour: the scan, the attestation and the issue lifecycle (which reads attested reports and documents, never the KEV set) run as on any dispatch, and the outage withholds what rests on the KEV set.

Task 16.3 (a KEV-listed finding under an exception) needs a feed that names CVE-2025-30204, which CISA's catalogue does not list (measured 2026-10-15); task 16.8's text supplies that feed as the second drill value, so this track ships it and 16.3 exercises it.

### The state on 2026-10-23

`rescan.yml` has `workflow_dispatch:` with no inputs; `build.yml` has one dispatch input, `image` (a string, the name of one definition). `lint-workflow-policy.sh` compares schedule crons and permissions blocks only (nine suite cases). `triage-policy.sh` answers thirteen queries over the `triage` and `consumers` sections, `kev-feed` among them. `check-exceptions.sh`, `rescan-report` and the status tool read `vulnerabilities[].cveID` from the KEV file and nothing else. The drill definition's HIGH, CVE-2025-30204, is covered by an accept exception until 2027-01-16 (LOG 2026-10-18). The scheduled rescan of 2026-10-23 ran at 11:47Z (run 39948543838).

## Functional requirements (EARS)

Each requirement is one EARS statement that passes the repository's validator (`node .claude/skills/ears-notation/scripts/ears-validator.js`, run over the statements extracted into its acceptance-criteria shape); the notes beneath it carry the detail the statement binds.

### FR-1: The input (Req 6.60, 7.11)

THE Repository SHALL add to `rescan.yml`'s `workflow_dispatch` one input named `drill` of type choice with the options `none`, `kev-outage` and `kev-synthetic` and the default `none`, and THE Scan Pipeline SHALL read it as `none` on a scheduled run.

Notes: the job's `env` gains `DRILL: ${{ github.event.inputs.drill || 'none' }}`; a scheduled run carries no inputs, so the expression yields `none`. The input's description names task 16.8 and says the substitution lasts one run. GitHub offers the options in the "Run workflow" form and refuses a dispatch with a value outside them, so the reader's refusal (FR-4) is the second wall, not the first.

**Acceptance criteria:**

- [ ] `yamllint .github/workflows/rescan.yml` and `scripts/lint-rescan-steps.sh` green; `scripts/lint-workflow-policy.sh .` green with FR-5's declaration
- [ ] The "Run workflow" form shows the three options (observed by the owner at the drill, phase 2)

### FR-2: The substitution, one declared value, the same code path (Req 6.60, 7.7)

WHEN `DRILL` is not `none` THE Scan Pipeline SHALL fetch, in its invariants step and in place of its declared KEV feed address, whatever substitute `scripts/triage-policy.sh . drill-feed <name>` prints, through that step's same fetch, same outage branch and same non-evaluation.

Notes: the step's diff is the lookup, one `::warning::` annotation naming the drill and the address, the drill's name in the outage branch's error line, and two outputs (`drill`, `feed`) for the summary; nothing else in the step or after it changes. The enrich step, the issue set and the status already refuse by name when the KEV file is absent (Req 6.60, review D1); the page job keys on the status step's output and skips.

**Acceptance criteria:**

- [ ] The pull request's diff of the invariants step shows the lookup and the annotation and no second branch (reviewed)
- [ ] The kev-outage run's invariants step is red with the Req 6.60 line naming `https://kev-feed.invalid/known_exploited_vulnerabilities.json` and the drill

### FR-3: The run says so (Req 6.60, 7.11)

THE Scan Pipeline SHALL print in every run summary one line `- drill: <name>`, with its fetched feed address appended for any name other than `none`.

Notes: `- drill: none` on the schedule; `- drill: kev-outage (the KEV feed substituted with https://kev-feed.invalid/known_exploited_vulnerabilities.json, this run only; task 16.8)` on the drill. The annotation of FR-2 is the second place a reader meets it, on the run page.

**Acceptance criteria:**

- [ ] The drill run's summary carries the line with the address; the next scheduled run's carries `- drill: none`

### FR-4: The declared substitutes and their reader (Req 7.7)

THE Repository SHALL declare in `catalogue-policy.yaml`'s `triage` section a `drills` map naming `kev-outage` as `https://kev-feed.invalid/known_exploited_vulnerabilities.json` and `kev-synthetic` as `https://raw.githubusercontent.com/mm-weber/dhc-pipeline/main/triage/drills/kev-synthetic.json`, and THE Repository SHALL read that map through `scripts/triage-policy.sh <root> drill-feed <name>` alone, a reader that refuses with exit 2 naming a `none` or undeclared name and naming a missing map.

Notes: `.invalid` is reserved by RFC 2606 and never resolves, so the outage is deterministic and immediate (a resolver answer, not the 60-second timeout); `curl` exits 6, "Could not resolve host". The raw address reads `main`, reachable from a runner, so the synthetic feed ships before any drill reads it. The reader's header and usage line gain the query.

**Acceptance criteria:**

- [ ] `scripts/triage-policy_test.sh`: `drill-feed kev-outage` prints the declared address; `drill-feed none`, an undeclared name and a missing `drills` map each refuse with exit 2 naming the name or the hole
- [ ] `scripts/triage-policy.sh . drill-feed kev-outage` prints the `.invalid` address on this repository

### FR-5: The lint holds the inputs (Req 7.10 as amended)

IF a workflow's `workflow_dispatch` inputs differ from its declaration's `inputs` map in `catalogue-policy.yaml`, in an input's presence, its `type`, its `options`, its `default` or its `required`, THEN THE CI Pipeline SHALL fail validation naming that workflow, that input and that differing value.

Notes: `lint-workflow-policy.sh` compares, per workflow, each dispatch input's map with `description` dropped (prose) against `workflows.<wf>.inputs.<name>`, both directions, the schedule precedent of review D3: an input the declaration lacks, a declared input the workflow lacks, and a differing key each fail by name; a workflow with no dispatch inputs and no `inputs` declaration passes as today. The declarations this track adds are literal mirrors of the existing inputs, found on the real-repository run of slice 1.1 (the draft counted build.yml alone): `build.yml` `image` (`required: false`, `type: string`), `renovate.yml` `logLevel` (choice, `info` and `debug`, default `info`) and `dryRun` (boolean, default false), `e2e.yml` `component` (`required: false`, `type: string`), plus `rescan.yml` `inputs: {drill: {type: choice, options: [none, kev-outage, kev-synthetic], default: none}}`. Both directions mean every existing input is declared in the same pull request as the lint change, or validation turns red on main.

**Acceptance criteria:**

- [ ] `scripts/lint-workflow-policy_test.sh` cases 9 to 11: an undeclared input fails naming the workflow and the input; a declared input absent from its workflow fails naming it; a differing `options` list fails naming the input and both lists; the matching fixture passes with an input on both sides
- [ ] `scripts/lint-workflow-policy.sh .` prints its all-green line on this repository with both declarations

### FR-6: The synthetic feed, for task 16.3 (Req 6.51, 7.11)

THE Repository SHALL carry `triage/drills/kev-synthetic.json` in CISA's catalogue shape, titled as a drill of this repository, with exactly one entry whose `cveID` is `CVE-2025-30204`, drill-app's HIGH.

Notes: the entry carries the fields CISA's entries carry (`vendorProject` golang-jwt, `product` jwt, `vulnerabilityName`, `dateAdded` the file's date, `shortDescription` naming the drill, `requiredAction`, `dueDate`, `knownRansomwareCampaignUse` Unknown, `notes` naming task 16.3 and this track); `check-exceptions.sh`, `rescan-report` and the status tool read `vulnerabilities[].cveID` and nothing else. Its live use is 16.3's: the rescan dispatched with `drill: kev-synthetic` reports the HIGH's exception over the KEV tier (Req 6.51) and the status shows KEV: yes; the gate's half of 16.3 points a drill branch's `kev_feed` at the same file.

**Acceptance criteria:**

- [ ] `python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' triage/drills/kev-synthetic.json` succeeds; `jq -r '.vulnerabilities[].cveID'` prints `CVE-2025-30204` and nothing else; the title's first word is DRILL

### FR-7: The gate's drill branch (Req 6.59)

THE Repository SHALL carry, on a branch opened as a draft pull request and never merged, `triage.kev_feed` set to its declared `kev-outage` address and one comment line in `image/drill-app/image.yaml` naming that drill, so that its build names drill-app and that build's `exception tiers against KEV` step fails closed naming that address and Req 6.59.

Notes: the build matrix derives from changed paths under `image/`, so the policy edit alone builds nothing; the comment line is the smallest change that puts drill-app in the matrix (the active-set lint admits a change to an active definition). The build and the scan run before the tiering step, as on every drill-app pull request. The branch closes with a comment after the evidence merges (#291's precedent).

**Acceptance criteria:**

- [ ] The drill pull request's build run is red at the tiering step with the Req 6.59 line naming the address; validate green; the run id recorded in the ledger's row 6.59
- [ ] The pull request is closed unmerged after the evidence merges

### FR-8: The outage run (Req 6.60)

WHEN a dispatch of `rescan.yml` carries `drill: kev-outage` THE Scan Pipeline SHALL fail that run at its invariants step naming that substituted address and Req 6.60, SHALL withhold that run's issue set, status issue and catalogue page by name, SHALL print that drill in that run's summary, and SHALL read its declared feed again and publish on its next scheduled run.

Notes, what the dispatch does beside the outage (register row M17): the scan runs, today's reports are attested with replace and the OpenVEX document re-attested where it changed, the issue lifecycle applies closes and reopens on attested evidence, the authenticity, governance, smoke, portability, expiry and inactive-definition steps run under `always()`. Withheld by name: the enrich step (no KEV catalogue on disk), the issue set, the status (its KEV input missing), the page (the status output empty, the page job skipped). The status issue and the page keep the previous run's data until the next scheduled run; the run is red by the invariants step and by each refusal. The owner dispatches; nothing upstream without the owner's word.

**Acceptance criteria:**

- [ ] The drill run's id, its invariants line, the three refusals and the summary line recorded; the status issue's body unchanged that day
- [ ] The next scheduled run green with `- drill: none` and the status published (its id recorded)

### FR-9: The evidence (Req 7.11)

THE Repository SHALL set ledger rows 6.59 and 6.60 to `exercised` with their run ids and `drill input` as their inducer, add one `triage/LOG.md` entry for this drill, tick task 16.8 in `.specs/dhc-catalogue-mvp/tasks.md`, and close this track, in a pull request opened as a draft until its last run is in.

Notes: the LOG heading `## <date>: the KEV feed outage drill, both arms fail closed by name (task 16.8)`, naming the two runs, the address, what each arm withheld and what the dispatch published; the tick in the house shape `[done <date>, #nnn; conductor track kev-drill-input_20261023]`; `tasks/todo.md`'s program state moves to 16.3. A draft until the next scheduled run is in (tasks/lessons.md, 2026-10-19).

**Acceptance criteria:**

- [ ] `scripts/lint-live-evidence.sh .` and `scripts/lint-log-anchors.sh all .` green; the rows, the entry and the tick present; `conductor/tracks.md` lists the track under Completed

### FR-10: Named where a reader meets it (Req 7.1, 7.11)

THE Repository SHALL name its drill input in `docs/user-manual.md`'s rows for `rescan.yml` and SHALL add to `docs/CONVENTIONS.md`'s manual-controls register one row for dispatching a rescan with a drill input, stating that such a run is red by name and publishes attestations only.

Notes: row M20 (M19 is the last); the manual's workflow table (the `rescan.yml` row) and the cron table's rescan row, plus a sentence under "Both are dispatchable on demand". The policy file's comments name the two new keys and what reads them.

**Acceptance criteria:**

- [ ] Both rows and the sentence present; `grep -c 'M20' docs/CONVENTIONS.md` is 1; no em-dashes added

## Scope

### In scope

- The `drill` input on `rescan.yml`, its substitution in the invariants step, the summary line (FR-1 to FR-3)
- The `triage.drills` map and the `drill-feed` query (FR-4); the `inputs` declarations for `build.yml` and `rescan.yml` and the lint that holds them (FR-5)
- The synthetic feed file (FR-6)
- The gate's drill branch, the outage run, the next scheduled run (FR-7, FR-8)
- The ledger rows 6.59 and 6.60, the LOG entry, the tick, the docs (FR-9, FR-10)

### Out of scope

- A drill input on `build.yml`: a pull request carries no dispatch inputs, so the gate's drill is a branch
- Any change to `check-exceptions.sh`, `rescan-report` or the status tool: they read the file they are given
- The live use of `kev-synthetic`: task 16.3, its own track
- Automating the dispatch: the owner dispatches, as every manual control
- A drill value for anything but the KEV feed: a later drill adds its own option, and the lint holds it

## Dependencies

| Dependency | Type | Status | Notes |
| --- | --- | --- | --- |
| The spec amendment of 7.7 and 7.10 | spec | in this pull request | A dispatch input is a declared value the policy lint holds |
| drill-app published (task 16.2) | track | done 2026-10-18 | The gate's drill builds drill-app; the synthetic feed names its HIGH |
| The rescan dispatched 2026-10-23 (run 39959263177) | none | running at drafting time | Gives #275 and #277 their close on evidence; independent of this track |

## Risks

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The drill run's day has no status update and no page update | certain, by design | the consumers read the previous run's data for one day | Stated by the task text; the next scheduled run repairs it; the drill is dispatched after the day's scheduled run |
| The drill dispatch re-attests today's reports | certain (M17) | none: the day's reports, replaced by the day's reports | Named in the request to the owner before the dispatch |
| `raw.githubusercontent.com` serves a cached copy of the synthetic feed | low | a stale feed for up to five minutes after an edit | The file ships days before 16.3 reads it |
| A resolver answers for `.invalid` | none (RFC 2606) | the drill would fetch something | `curl` exits 6 on the name; the run's error line carries the address, so a surprise is visible |
| Both-directions lint turns main red | low | validate fails after the merge | `build.yml`'s `image` input is declared in the same pull request; `scripts/lint-workflow-policy.sh .` run on the branch before the push |

## Open questions (the owner's calls)

- [ ] The value names `kev-outage` and `kev-synthetic` and the address `https://kev-feed.invalid/known_exploited_vulnerabilities.json` (drafted; rename or strike by review)
- [ ] `kev-synthetic` ships in this track as task 16.8's text says, or waits for 16.3's track (drafted: ships here, unused until 16.3)

## References

- `.specs/dhc-catalogue-mvp/tasks.md` task 16.8; `.specs/dhc-catalogue-mvp/requirements.md` Req 6.59, 6.60, 7.7, 7.10, 7.11; `.specs/dhc-catalogue-mvp/design.md` Decision 13 and "Live drills"
- `docs/live-evidence.md` rows 6.59 and 6.60; `docs/CONVENTIONS.md` register row M17
- `.github/workflows/rescan.yml` invariants step; `.github/workflows/build.yml` `exception tiers against KEV`; `scripts/lint-workflow-policy.sh`; `scripts/triage-policy.sh`; `scripts/check-exceptions.sh`
- RFC 2606, reserved top-level DNS names
