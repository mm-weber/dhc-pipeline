# Track specification: The fail-closed release gate refuses a release, the digest frozen, live

## Overview

**Track ID:** fail-closed-release_20261027
**Type:** chore
**Priority:** high (the live program; the drill definition's uncovered finding makes it possible today, before 16.6 fixes it)
**Created:** 2026-10-27
**Author:** the owner, drafted by the agent
**Spec source:** `.specs/dhc-catalogue-mvp/tasks.md` task 16.9 (task group 16, the live drills), its text amended by this track's pull request; Req 2.8 (the pushed digest scanned per platform manifest), 2.11 (a digest no tag references is frozen), 2.13 (with fail-closed on, nothing signed, attested or tagged for an uncovered digest, the finding reported in the run), 7.11 (the ledger); design Decision 13

### Description

The release path pushes an image by digest, scans every platform manifest of the pushed digest with the compiled VEX documents and the unexpired exceptions (Req 2.8), and only then signs, attests and tags (Req 2.9). With the declared switch `release.fail_closed` off, an uncovered finding releases as an `under_investigation` statement (Req 2.12); with it on, the gate step `fail-closed release gate (Req 2.13)` names the finding per platform manifest in the job summary and in an error line, exits 1, and the steps that sign, attest and tag never run: the digest exists in the registry, pullable by its digest, referenced by no tag, and a digest no tag references is frozen (Req 2.11): not published, not rescanned, not re-attested. The switch has been off since the criteria landed; the gate step has been skipped in every build job (710 by 2026-09-27), and no digest has ever been frozen on purpose.

The drill definition supplies the uncovered finding: CVE-2025-30204 on drill-app has had no exception since task 16.4 removed the lapsed entry (#329, 2026-10-27) and no decision, and the pull request gate refuses it on every build of the definition (#324, #329). This track turns the switch on in one pull request, has the owner dispatch `build.yml` for drill-app (a dispatch is a release attempt and never runs the publish-on-change comparator, register row M17), reads the refusal from the run and the frozen digest from the registry, and turns the switch off again the same day. The way out the gate offers is taken by drill 16.6, which fixes the finding; nothing is decided here.

### The mechanism, as read on 2026-10-27

`scripts/release-policy.sh . fail-closed` reads `release.fail_closed` from `catalogue-policy.yaml` as the exact text `true` or `false` and refuses anything else (`release-policy.sh . check` on every validate run); `build.yml` reads it once into `steps.meta.outputs.fail_closed`. On a dispatch on main with `image: drill-app` the matrix is that one active definition; the build pushes by digest and applies no tag (Req 2.7); the steps `enumerate platform manifests`, `release-time scan of the pushed digest (Req 2.8)` (one Trivy report per platform manifest, `uncovered` summed over them) and, when the switch is on and the count is not zero, `fail-closed release gate (Req 2.13)` follow. The gate writes a table (platform manifest, finding, severity, package, fixed) to the job summary and the error line `<name>: <n> uncovered finding(s) in the release-time scan of <digest>: <findings>. The declared fail-closed setting is enabled, so this digest is signed by nothing, attested by nothing and carries no tag (Req 2.13). It stays frozen and pullable by digest; the ways out are the same four the gate offers.`, then exits 1, so `attest each platform manifest's scan report`, `compile the digest's OpenVEX document`, `sign and attest` and `apply definition-derived tags` do not run and the build gate is red. The daily rescan enumerates catalogue tags and the digests they reference (`enumerate-catalogue.sh`, Req 2.22): a digest no tag references is not enumerated, so it is neither scanned nor re-attested, and the admission proof (Req 2.24) examines tag-referenced digests and the one declared control digest only.

## Functional requirements (EARS)

The subject names follow design.md: the CI Pipeline (`build.yml`), the Catalogue (the registry state), the Scan Pipeline (`rescan.yml`), the Repository, the owner.

### FR-1: The switch on (Req 2.13)

THE Repository SHALL set `release.fail_closed` to `true` in `catalogue-policy.yaml` in one pull request, the comment naming the drill and the revert, and the owner SHALL merge it; validation green (`release-policy.sh . check` accepts the text).

**Acceptance criteria:**

- [x] #334, squash 8ea59f4 (merged 2026-10-28 12:47:50Z); the reader printed `true` on 10b79de; validate green

### FR-2: The release refused (Req 2.8, 2.13)

WHEN the owner dispatches `build.yml` on main with `image: drill-app` after FR-1 merges THE CI Pipeline SHALL push the image by digest, scan each platform manifest of that digest and report CVE-2025-30204 uncovered on each, and SHALL fail at the fail-closed release gate naming the finding per platform manifest in the job summary and in the error line, with the attestation, compilation, signing and tagging steps not run and the build gate red.

Notes: the drill definition builds for the declared platforms (two platform manifests); a dispatch never runs the comparator (M17). Should the release-time scan report nothing uncovered (a database drift), the dispatch would publish a full release of drill-app, the tags moving to the new digest and the finding carried with its first-seen time: named here, not expected.

**Acceptance criteria:**

- [x] Run 40691384018; `sha256:925dd22c2ead334b193b82447e994142be241714883d0c99e832700869ba1736`; the scan step's lines are in the log (the gate's error line carries the count, two, one per platform manifest); the error line quoted in row 2.13; the four steps after it skipped; the build gate red at 13:00:54Z

### FR-3: Frozen (Req 2.11)

THE Catalogue SHALL hold that digest pullable by digest with no signature, no attestation and no catalogue tag referencing it (read from the registry the same day), and WHEN the next scheduled rescan runs THE Scan Pipeline SHALL enumerate drill-app's tag-referenced digest only, scanning and attesting nothing for the frozen one (read on 2026-10-28).

Notes: the registry reads are a manifest fetch by digest, `cosign download signature` and `cosign download attestation` returning nothing, and the repository's tag list not referencing the digest. The status data lists drill-app's digests with their tags; the frozen digest is absent from it.

**Acceptance criteria:**

- [x] The manifest fetched by digest (HTTP 200, an OCI index); no signature (`no signatures associated`), no attestation; the tag list unchanged, the three tags on `sha256:bfe9a515ce9a...` (not `0c61394798b5`: the first dispatch had moved them that morning); the scheduled run 40693681245 of 2026-10-28 listing drill-app's tagged digest only

### FR-4: The switch off (Req 2.13)

THE Repository SHALL restore `release.fail_closed` to `false` the same day in one pull request, the comment recording the drill's run, and the owner SHALL merge it; the owner MAY instead keep the switch on, and the evidence SHALL record which.

Notes: kept on, the switch refuses every scheduled rebuild that publishes on change with an uncovered finding (today only drill-app has one) and would let 16.6's fix release under it, a clean pass of the gate; it would have to go off before 16.7, whose regression release must publish. Drafted: off the same day, one release, the shape of the ceiling drills.

**Acceptance criteria:**

- [x] #335, squash 46353ef (merged 13:52Z): the switch off the same day

### FR-5: The evidence (Req 7.11)

THE Repository SHALL flip ledger rows 2.11 and 2.13 to `exercised` with the run id and the registry reads, add the LOG entry `## 2026-10-27: the fail-closed release gate refuses the drill's release, the digest frozen (task 16.9)`, add the task table row for 16.9, tick task 16.9 naming drill 16.6 as the way out, and close this track, in an evidence pull request opened as a draft the day of the dispatch and made ready once FR-3's scheduled run is read.

**Acceptance criteria:**

- [x] `scripts/lint-live-evidence.sh .` green with 141 exercised; `scripts/lint-log-anchors.sh all .` green; the tick `[done 2026-10-28, #336; conductor track fail-closed-release_20261027]`; `conductor/tracks.md` lists the track under Completed

## Scope

### In scope

- Two one-line policy pull requests (FR-1, FR-4) and the owner's one dispatch of `build.yml` (FR-2)
- The reads of the run, the registry and the next scheduled rescan
- One evidence pull request (FR-5), a draft until the last read is in
- The amendment of task 16.9's text in this pull request

### Out of scope

- Any change to `build.yml`, the scripts or the policy reader: the drill reads what they do; a defect found is recorded with a follow-up task, not fixed here
- The way out: drill 16.6 fixes the finding in its own track; no decision is written here
- Revoking or deleting the frozen digest: it stays, frozen, as Req 2.11 describes; drill 16.12 may use it

## Dependencies

| Dependency | Type | Status | Notes |
| --- | --- | --- | --- |
| The finding uncovered (task 16.4) | track | done 2026-10-27 (#329, 1a43a5a) | No exception, no decision; the pull request gate refuses every build of drill-app |
| Task 16.5's clear | track | the scheduled run of 2026-10-28 | This drill touches no tag and no supported digest, so the clear is unaffected; both evidence pull requests go up that day |
| The task text amended (16.9) | spec | in this pull request | The exception's expiry is 16.4's, done; the frozen half read on the next scheduled run; the way out 16.6 |

## Risks

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The release-time scan reports nothing uncovered | low (the database would have to drop the finding) | a full release of drill-app: new digest, tags moved, the finding carried | Named in FR-2; the run is read either way and the drill records what happened |
| The scheduled build of 2026-10-28 publishes on change while the switch is on | low (it published nothing on 2026-10-27) and only if the switch is kept on | drill-app refused again, a second frozen digest | The switch goes off the same day (FR-4) unless the owner keeps it, in which case the refusal is the switch working |
| An unsigned, untagged digest under a catalogue repository trips a daily check | none: the admission proof reads tag-referenced digests and the declared control digest; the inactive-digest check reads inactive definitions; the posture step reads the revocation record | none | Recorded; read on 2026-10-28 |

## Open questions (the owner's calls)

- [x] Off the same day (#335)
- [x] A draft until the scheduled run of 2026-10-28 was read, then ready

## References

- `.specs/dhc-catalogue-mvp/requirements.md` Req 2.7, 2.8, 2.9, 2.11, 2.12, 2.13, 2.22, 2.24, 7.11; `tasks.md` 16.9, 16.6, 16.7, 16.12
- `.github/workflows/build.yml` (the dispatch input `image`, the release steps, the gate step), `scripts/release-policy.sh`, `scripts/enumerate-catalogue.sh`, `catalogue-policy.yaml` `release.fail_closed`; `docs/user-manual.md` (the fail-closed switch); `docs/CONVENTIONS.md` row M17
- LOG 2026-10-26 (the finding uncovered), LOG 2026-10-27 (task 16.5); tracks `exception-lapse_20261025`, `over-ceiling_20261027`
