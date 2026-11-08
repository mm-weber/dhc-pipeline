# Track specification: The drill definition retired, the drill program closed, the ledger complete

## Overview

**Track ID:** retirement_20261107
**Type:** chore
**Priority:** high (the live program's last task; a scheduled rebuild republishes the withdrawn definition every day until this merges)
**Created:** 2026-11-07
**Author:** the owner, drafted by the agent
**Spec source:** `.specs/dhc-catalogue-mvp/tasks.md` task 16.16 (task group 16, the live drills), its text amended by this track's pull request; Req 1.19 (an active-set entry without a directory fails validation), 6.49 (the support statement), 6.52 (an issue closes on evidence), 7.11 (the ledger); the retirement table of track `retire-grafana_20261019`

### Description

The drill definition, `image/drill-app/`, joined the catalogue on 2026-10-18 to carry findings on purpose (task 16.2) and has been the fixture of every drill since: thirteen of task group 16's fourteen drills are done, every row of the ledger that waited for a drill is exercised, and the fixture's last published digest was withdrawn on 2026-11-07 (task 16.12), after which the scheduled rebuild of the same day republished it on sha256:daeef9400b83, because a withdrawn definition returns at the next rebuild until it is retired. This track retires it: level 2 of the retirement table, the line, the directory and the lane gone in one pull request, the record complete, the upstream repository archived, and the first rescan after read for what the catalogue does with the digests it no longer stands behind.

### The mechanism, as read on 2026-11-07

- Level 2 of the retirement table (track `retire-grafana_20261019`): the active-set line and `image/<name>/` removed together, which is the shape Req 1.19 demands (an entry without a directory fails validation; a directory without an entry is level 1). drill-app has no chart; its accepted-risk lane, `triage/accepted-risk/drill-app.yaml`, has been empty since task 16.7 and is kept only for this retirement; its proofs entry in `catalogue-policy.yaml` is `kind: none` with the fixture's reason.
- The daily enumeration reads repositories from the definitions, so a removed definition's tags are not enumerated, scanned or re-attested any more; the table of 2026-10-19 said so and noted that task 16.16's wording assumed otherwise. What is published stays as it is: the digests and tags pullable, the last attestations in place, the withdrawn digest's entry in `triage/revocations.yaml` with no tag to reference it, cosign's signature and attestation manifests under the package. Nothing is deleted by this track.
- The lifecycle closes an open issue when its finding is absent from every supported digest's report (Req 6.52); with the definition gone from the supported set, #325 (CVE-2025-30204, the fixture's HIGH, undecided for 20 days) closes as `resolved:absent` at the first rescan after the merge, by name, and the fixture's digests leave #300's affected list. The status issue and the page drop the definition.
- `scripts/lint-probes.sh`'s live-state case in `scripts/lint-probes_test.sh` asserts the repository's own counts (seven active definitions, six chart-proved, one declared none); the retirement moves them to six and none, test-first. `scripts/render-tracking.sh` renders no ignore glob for a removed directory, so the tracking block does not change. Renovate's open #346 (gorilla/handlers for the fixture's fetch phase) loses its file and closes on its own.
- The README's `image/` row and the manual's definitions row name drill-app; the retirement names it retired there. The LOG's drill entries: eight of fourteen carry no "What the drill found" paragraph (16.2, 16.3, 16.4, 16.6, 16.7, 16.8, 16.9, 16.15); the task asks that every one names what it found.
- By the owner's rule of 2026-11-03 the rescan after the merge is dispatched (a release of attestations, register row M17).

## Functional requirements (EARS)

The subject names follow design.md: the owner, the Repository (its maintainer), the Scan Pipeline, the CI Pipeline.

### FR-1: The removal (Req 1.19, 1.13)

THE Repository SHALL remove, in one pull request, drill-app's active-set line and proofs entry from `catalogue-policy.yaml`, the directory `image/drill-app/` and the lane `triage/accepted-risk/drill-app.yaml`, keeping the revocation entry, with the live-state case of `scripts/lint-probes_test.sh` moved to six active definitions and none declared, test-first; validate green.

**Acceptance criteria:**

- [ ] The pull request's number and squash; validate green at the active-set, probe, accepted-risk and schema steps; `scripts/render-tracking.sh --check` unchanged

### FR-2: The record complete (Req 7.11)

THE Repository SHALL add, in the same pull request, the LOG entry `## 2026-11-07: the drill definition retired, the drill program closed (task 16.16)` naming what leaves, what stays published, what stops and what the first rescan after is expected to do; SHALL give each of the eight drill entries without one a "What the drill found" paragraph written from that entry's own text; SHALL name drill-app retired in the README and the manual; and SHALL state the ledger's completeness, every row exercised or carrying its reason.

**Acceptance criteria:**

- [ ] `scripts/lint-live-evidence.sh .` green (150 exercised, 1 defect, 4 unexercised, each with its reason); `scripts/lint-log-anchors.sh all .` green; fourteen drill entries each with a "What the drill found" paragraph

### FR-3: The upstream archived

THE owner SHALL archive the repository `mm-weber/drill-app` once the removal has merged and SHALL tell the maintainer the time.

**Acceptance criteria:**

- [ ] The repository's archived flag read from the API, the time

### FR-4: The first rescan after (Req 6.52, 1.15)

WHEN the rescan runs after the merge THE Scan Pipeline SHALL enumerate no tag of the retired definition, SHALL close the fixture's open issue, #325, on evidence as `resolved:absent` with the comment naming every supported digest, SHALL drop the definition's digests from #300's affected set, SHALL list the revocation entry with no referenced tag, and SHALL publish the status issue and the page without the definition; the run dispatched by the owner.

**Acceptance criteria:**

- [ ] The run's id, the enumeration's count, the closing comment on #325 with its label, the posture summary `1 recorded, 0 referenced`, the status issue's definition list

### FR-5: The evidence and the close (Req 7.11)

THE Repository SHALL add the observed run to the LOG entry, add the task table row for 16.16, tick task 16.16, mark task group 16 complete in `tasks/todo.md` with the ledger's final counts, and close this track, in one evidence pull request.

**Acceptance criteria:**

- [ ] The tick `[done <date>, #nnn; conductor track retirement_20261107]`; `conductor/tracks.md` lists the track under Completed; the todo's task group 16 marked complete

## Scope

### In scope

- One retirement pull request (FR-1, FR-2), the owner's archive (FR-3), one dispatched rescan (FR-4), one evidence pull request (FR-5)
- The amendment of task 16.16's text in this pull request: the scans stop with the directory

### Out of scope

- Deleting anything published: the digests, tags, attestations and cosign manifests stay (SECURITY.md, retention); the withdrawn digest's deletion was task 16.12's
- The defect row 6.55 and the four unexercised rows: each carries its reason, and the task asks for evidence or its reason
- The drill input `triage/drills/kev-synthetic.json`: scaffolding of the KEV drill mechanism (Req 7.7, 7.10), kept

## Dependencies

| Dependency | Type | Status | Notes |
| --- | --- | --- | --- |
| Task 16.12 done | spec | 2026-11-07 (#376) | the withdrawn digest's entry stays; the definition republished on 2026-11-07 until retired |
| The owner archives the upstream | permission | the owner's | the pipeline's token is not asked to |
| The rescan's dispatch | mechanism | available | a release of attestations (M17) |

## Risks

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| A scheduled rebuild republishes the definition before the merge | likely while the pull request waits | one more digest under the tags, nothing else | Harmless; the retirement stops the next one |
| The lifecycle keeps #325 open for a reason not foreseen | low | the issue closed by hand with the reason | Read, not predicted; the entry records what happened |
| The README's or the manual's row goes stale elsewhere | low | a reader counts seven | Both rows named in FR-2 |

## Open questions (the owner's calls)

- [ ] Level 2 as the task says, the directory removed and the scans stopped (drafted: yes; level 1 would keep scanning a fixture nobody installs)
- [ ] The upstream repository archived rather than deleted (drafted: archived; its tag and commits are cited by the LOG)

## References

- `conductor/tracks/retire-grafana_20261019/spec.md` (the retirement table); `docs/user-manual.md` "Deactivate a definition"; `triage/rescan/lifecycle.go` (Req 6.52); `scripts/lint-probes_test.sh` (the live-state case); `.specs/dhc-catalogue-mvp/requirements.md` Req 1.13, 1.19, 6.49, 6.52, 7.11; `tasks.md` 16.16
- LOG 2026-10-18 (the fixture's arrival), LOG 2026-11-05 (its withdrawal)
