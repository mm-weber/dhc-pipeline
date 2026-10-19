# Track specification: Grafana deactivated, the documented switch exercised live

## Overview

**Track ID:** retire-grafana_20261019
**Type:** chore
**Priority:** high
**Created:** 2026-10-19
**Author:** the owner, drafted by the agent
**Spec source:** `.specs/dhc-catalogue-mvp/requirements.md` Req 1.13 to 1.16 (the active set, the matrices, no digest or tag for an inactive definition, a bump of one refused), 3.2 (the tracking scope), 6.7 and 6.11 (the risk-treatment lane), 7.11 (the ledger); `docs/CONVENTIONS.md` "Deactivating a definition means removing its line, and only that"; `docs/user-manual.md` "Deactivate a definition"; `SECURITY.md` "Digest states, the epoch, retention"

### Description

The owner's call of 2026-10-19: the catalogue stops standing behind new grafana builds, by the documented switch and nothing more, so that the switch, never exercised live, is exercised on a real definition. Grafana's line leaves the active set; its directory and its chart stay, as the convention keeps them to demonstrate the switch. From the merge on, the nightly builds no grafana, no tag moves, Renovate opens no bump (the tracking block ignores `image/grafana/**` and `chart/grafana/**`), the e2e installs no grafana chart, and a pull request touching the directory fails validation by name. Everything published stays: the tags pullable, the signatures and attestations in place, the daily enumeration, scans, re-attestation and visibility invariant over them, the supported digest's issues and clocks. In the same pull request the twelve exceptions of 2026-09-03, whose findings left the image with 13.1.7 on 2026-10-06, are retired with their evidence, so the daily expiry warnings stop.

### Background: the four levels of retiring an image

Kept here at the owner's request, as decided on 2026-10-19.

| | 1. Deactivate (this track) | 2. Remove from the catalogue | 3. Revoke a digest | 4. End of life with deletion |
|---|---|---|---|---|
| What changes | one line: the definition leaves the active set | the line, plus `image/<n>/` and `chart/<n>/` deleted (task 16.16's shape) | a record in `triage/revocations.yaml`, an advisory, the runbook | nothing exists for it today |
| New builds, tags, bumps, e2e | stop | stop | unchanged for the rest | |
| Published images | pullable forever | pullable forever | the tag re-pointed or the version deleted | deleted after a grace period |
| Daily scans and re-attestation | continue | stop: the enumeration reads repositories from the definitions | continue | stop |
| Findings in the published digest | in scope: filed, clocked, each decided one at a time; nothing auto-accepts; the fix treatment is gone | out of scope: nobody looks | per the revocation | gone with the image |
| Exceptions and their warnings | unchanged until retired or expired | the lint still reads the file | unchanged | gone with the file |
| Spec coverage | Req 1.13 to 1.16 | Req 1.19; 16.16's wording assumes the scans continue, the code says they stop | Req 9.4 to 9.7 | none: a spec amendment and a change to SECURITY.md's "nothing is deleted" |

SLSA grades how an artifact was built and whether that is provable (Build L1 provenance exists, L2 a hosted platform signs it, L3 a hardened platform makes it unforgeable); this catalogue is L2 and `design.md` leaves L3 hermeticity out of scope. SLSA says nothing about retirement; its one implication is that whatever stays pullable stays verifiable, so levels 1 and 2 honour it and level 4 would only with the attestations retired together with the image after an announced grace.

### Grafana's state on 2026-10-19

Supported digest sha256:89c5680a868b under `13-alpine3.23`, `13.1-alpine3.23` and `13.1.7-alpine3.23` (status issue #151). Twenty-one exception entries: twelve decided 2026-09-03 and expiring 2026-11-02, whose findings the status records as fixed on 2026-10-06 after thirty days (moot, warning daily since 2026-10-19); nine decided 2026-10-13 and expiring 2026-12-12 (the Go HTTP/2 wave, real, transfers waiting on a 13.1.8 that this track makes impossible, so their re-decision on 2026-12-12 is "accept, no build will fix this image" or level 2). Five undecided HIGH findings in the same digest, outside this track and the owner's to decide one at a time: CVE-2026-100351 to CVE-2026-100354 (#274 to #277, first seen 2026-10-16) and CVE-2026-100349 (#287, first seen 2026-10-18), all five in one module, `github.com/getkin/kin-openapi` v0.144.0, fixed upstream in 0.146.0 to 0.149.0, on a ninety-day ceiling. Deactivation changes none of these; it removes the fix treatment from their rungs.

## Functional requirements (EARS)

Each requirement is one EARS statement that passes the repository's validator; the notes beneath carry the detail.

### FR-1: The switch (Req 1.13)

THE Repository SHALL remove `grafana` from `active_set` in `catalogue-policy.yaml` and change nothing else under `image/grafana/` or `chart/grafana/`.

Notes, measured in a scratch copy on 2026-10-19: `scripts/lint-active-set.sh .` reports `7 active definition(s), 1 inactive, 4 chart director(ies) with a deploys list; no group split`; `scripts/lint-probes.sh .` reports `7 active definition(s): 6 covered by 3 probe registration(s), each executed once per install, 1 declared none`; the e2e components become cert-manager, hardened-app and valkey; the policy file's comment that the reference activates everything, grafana included, is amended.

**Acceptance criteria:**

- [ ] The lints above print those lines; `scripts/lint-compat.sh`, `scripts/release-policy.sh . check` and `scripts/lint-workflow-policy.sh` are unchanged
- [ ] `git diff --stat` touches no file under `image/grafana/` or `chart/grafana/`

### FR-2: The tracking scope (Req 1.14, 3.2)

THE Repository SHALL re-render `renovate.json5`'s tracking block with `scripts/render-tracking.sh` so it ignores `image/grafana/**` and `chart/grafana/**`, and THE CI Pipeline SHALL fail validation on any drift between that block and its active set.

Notes: the rendered block reads `"image/grafana/**", // inactive definition (catalogue-policy.yaml active_set)` and `"chart/grafana/**", // chart adaptation deploying no active definition`; `scripts/render-tracking.sh --check .` then reports `2 ignored path(s)`.

**Acceptance criteria:**

- [ ] `scripts/render-tracking.sh --check .` green with two ignored paths; `node test/renovate/managers.test.mjs` green, its tracking-scope checks asserting the new block and its fork fixture deactivating hardened-app (the manager fixtures still read the grafana definition, which stays)

### FR-3: The live-state guard (Req 1.13)

THE Repository SHALL assert in `scripts/lint-probes_test.sh` case 13 that this repository reports seven active definitions, six covered by three probe registrations and one declared none, as this track's first red test.

**Acceptance criteria:**

- [ ] Case 13 fails on main with `missing '7 active definition(s)'` and passes once FR-1 lands

### FR-4: Named inactive where a reader meets it (Req 7.11)

THE Repository SHALL mark grafana inactive in `README.md`'s `image/` row and in `docs/user-manual.md`'s definitions row, naming its last published version and its deactivation date.

**Acceptance criteria:**

- [ ] Both rows read "grafana (inactive since 2026-10-19, last published 13.1.7)" or equivalent; no other hand-written list of definitions exists (`grep` of 2026-10-19)

### FR-5: The moot exceptions retired (Req 6.7, 6.11)

THE Repository SHALL remove from `triage/accepted-risk/grafana.yaml` its twelve entries decided on 2026-09-03, each of whose findings left its supported digest with 13.1.7 on 2026-10-06, and SHALL keep its nine entries decided on 2026-10-13.

Notes: the evidence is the status issue's rows (fixed 2026-10-06, thirty days) and LOG 2026-10-13's measured paragraph; the retirement follows the shape the 2026-09-18 entry set. The nine transfers stay with their re-decision date.

**Acceptance criteria:**

- [ ] `scripts/lint-accepted-risk.sh .` green with no expiry warning; nine entries remain, all `decided_at: 2026-10-13`

### FR-6: The LOG (Req 7.11)

THE Repository SHALL add one `triage/LOG.md` entry for this deactivation, naming its reason, its evidence and its exit conditions, and SHALL keep every remaining exception reference anchored to an existing heading.

**Acceptance criteria:**

- [ ] `scripts/lint-log-anchors.sh all .` green; the entry carries the retired twelve by id with their fix date

### FR-7: No new digest and no new tag (Req 1.15)

WHEN a nightly or a push build runs after that merge THE CI Pipeline SHALL build no grafana image and apply no grafana tag, and THE Scan Pipeline SHALL report on its next rescan that every grafana tag still references its last recorded digest.

**Acceptance criteria:**

- [ ] The first build run after the merge: no `build grafana` job; the first rescan: the inactive-digest check names one inactive definition and passes (the ledger's 1.15 evidence)

### FR-8: A bump of an inactive definition refused (Req 1.16)

IF a pull request changes a file under `image/grafana/` without activating it THEN THE CI Pipeline SHALL fail validation naming that file and Req 1.16.

Notes: the error reads `image/grafana/image.yaml: image/grafana/ is not in the active set, so this change cannot be built, tested or published; activate the definition in this pull request (active_set in catalogue-policy.yaml) or leave it frozen (Req 1.16)` (measured in the scratch copy on 2026-10-19). The track first expected Renovate's open #279 (grafana 13.1.8) to supply the case on its next rebase. Amended 2026-10-19 after the merge: FR-2's rendered ignore paths take `image/grafana/**` out of Renovate's extraction, so the bot drops the 13.1.x branch instead of rebasing it (its stale-branch pruning closes #279 and the dashboard stops listing grafana, the tracking-scope evidence of Req 1.14 and 3.2). The case therefore comes the way task 16.11 words it: a drill pull request bumping the inactive definition, never merged. Drill #291 replays Renovate's commit f6f89f8 (the real 13.1.8 bump) unchanged onto main after #290, as a draft.

**Acceptance criteria:**

- [x] The drill's validate run red with that line (run 39289979209, 2026-10-19 16:57Z; the ledger's 1.16 evidence); its build run leaves grafana out of the matrix by name with the gate green (run 39289978981, Req 1.15's preventive branch, first run live); #291 closed, never merged, once the evidence is merged
- [ ] Renovate's next successful run closes #279 and the dashboard (#5) stops listing grafana (observed, not assumed)

### FR-9: The evidence (Req 7.11)

THE Repository SHALL flip ledger rows 1.15 and 1.16 to exercised with their run ids, SHALL record in its LOG entry what its first inactive day showed, and SHALL amend task 16.11's wording in `.specs/dhc-catalogue-mvp/tasks.md` that claims a first time.

**Acceptance criteria:**

- [ ] `scripts/lint-live-evidence.sh .` green; 16.11's text says the mechanism was exercised by grafana's deactivation and keeps its own twist (the proofs entry, 1.19)

## Non-functional requirements

- **Nothing deleted, nothing hidden:** the registry is untouched; every published grafana digest keeps its signatures, attestations and daily planes (SECURITY.md).
- **Reversible:** adding the line back reactivates; the directory and the chart are kept for that.
- **The owner decides findings, not this track:** the five undecided HIGHs and the nine transfers are triage calls taken one at a time, outside this track.

## Scope

### In scope

- The switch, the tracking block, the live-state test, the two rows, the twelve moot exceptions, the LOG entry
- The observation of the first inactive day and the ledger rows 1.15 and 1.16

### Out of scope

- Levels 2 to 4 (removal, revocation, end of life with deletion)
- The five undecided findings and the nine transfers (the owner's calls; the LOG entry names them)
- Task 16.11's own drill (drill-app's deactivation with its proofs entry and the 1.19 branch)

## Dependencies

| Dependency | Type | Status | Notes |
| --- | --- | --- | --- |
| Renovate's #279 (grafana 13.1.8) | pull request | open | becomes the 1.16 case on its next rebase; closed by the owner afterwards |
| The next scheduled build and rescan | CI | daily | the 1.15 evidence |
| The status issue #151 | data | live | the fixed rows of 2026-10-06 are the evidence for FR-5 |

## Risks

| Risk | Probability | Impact | Mitigation |
| --- | --- | --- | --- |
| The frozen 13.1.7 digest keeps accruing findings nobody will fix | certain | decisions forever, or level 2 later | stated in the LOG entry; the 2026-12-12 re-decision is the checkpoint |
| Renovate keeps #279 open after the paths are ignored | medium | a red pull request lingers | the owner closes it; the dashboard stops listing grafana |
| A hand-written list of definitions is missed | low | a stale row | the grep of FR-4 |

## Open questions

- [x] Retire the twelve moot exceptions in the same pull request? Yes, the owner's call of 2026-10-19.

## References

- `docs/CONVENTIONS.md` (deactivation), `docs/user-manual.md` (Deactivate a definition), `SECURITY.md` (retention), `docs/concepts.md` (SLSA)
- `scripts/lint-active-set.sh`, `scripts/render-tracking.sh`, `scripts/check-inactive-digests.sh`, `scripts/lint-probes_test.sh`
- `triage/accepted-risk/grafana.yaml`, `triage/LOG.md` 2026-09-03, 2026-09-18, 2026-10-13; status issue #151

---

**Approved by:** pending the owner's confirmation
**Approval date:** pending
