# Track specification: The drill definition and its first findings

## Overview

**Track ID:** drill-definition_20261017
**Type:** feature
**Priority:** high
**Created:** 2026-10-17
**Author:** the owner, drafted by the agent
**Spec source:** `.specs/dhc-catalogue-mvp/tasks.md` task 16.2 (task group 16, the live drills); Req 1.13, 1.14, 5.9, 6.1, 6.3, 6.13, 9.11 and 7.11; design Decision 13 (live drills) and Decision 14 (onboarding in two pull requests, of which this is the first)

### Description

The live-drill program (Req 7.11, Decision 13) needs a definition whose findings are known, intended and owned: `drill-app`, the owner's copy of hardened-app whose `go.mod` pins `github.com/gorilla/handlers v1.2.1` (CVE-2017-20146, CRITICAL 9.8, `cors.ServeHTTP`, fixed in 1.3.0) and `github.com/golang-jwt/jwt/v5 v5.2.1` (CVE-2025-30204, HIGH 7.5, `Parser.ParseUnverified`, fixed in 5.2.2). The repository `mm-weber/drill-app` exists since 2026-10-15 (public, MIT, rulesets as hardened-app); its tag `v0.1.0` points at commit b7868d7a6f41a8dc2181bd874776cf4976d11591, GitHub-verified as signed, re-read on 2026-10-17. Each module yields exactly one finding in trivy 0.75.0, and both symbols were reachable in source-mode govulncheck on 2026-10-15.

This track onboards it as pull request 1 of Decision 14's flow: the definition in native DHI syntax, its active-set entry, and the catalogue's first proof of kind `none`, declared with its reason and printed by name on every validation run. No chart deploys it, ever: the drill is never installed, and task 16.16 retires it. On the pull request the scan gate names both findings and govulncheck reports their reachability in the built binary; the owner decides each finding one at a time in reach order; the pull request merges green; main publishes the first digest; the next rescan and the status page show the drill as it is. The evidence lands in the ledger and in `triage/LOG.md`.

### Background

Task 16.2 was blocked by the onboarding cycle (a new definition had to be active, chart-proved and digest-pinned in one pull request) until the proof-kinds track (task group 17, pull requests #271 to #283, all merged 2026-10-17) admitted a declared `none` proof with a reason and no date. The working plan for the whole drill program, written on the branch `plan-live-drills` on 2026-10-12, is folded into `tasks/todo.md` by the pull request that opens this track, revisited for what has merged since; from here, each drill runs as its own conductor track.

## Functional requirements (EARS)

Each requirement is one EARS statement that passes the repository's validator (`node .claude/skills/ears-notation/scripts/ears-validator.js`); the notes beneath it carry the detail the statement binds.

### FR-1: The definition (Req 1.13, 1.14)

THE Repository SHALL carry `image/drill-app/image.yaml` in native DHI syntax, copied from `image/hardened-app/image.yaml` and pinned to drill-app v0.1.0 at commit b7868d7a6f41a8dc2181bd874776cf4976d11591 with its authenticity marker, and THE Repository SHALL list `drill-app` in its policy file's `active_set`.

Notes: the same frontend line, golang builder reference and Alpine inputs as hardened-app at the time of the commit; `name: Drill App 0.1.x (live-drill fixture)`; `image: ghcr.io/mm-weber/dhc/drill-app`; tags `0-alpine3.23`, `0.1-alpine3.23`, `0.1.0-alpine3.23`; both platforms; `dates.release: "2026-10-15"`; the source `git+https://github.com/mm-weber/drill-app.git#v0.1.0` with the checksum above and the marker `# authenticity: signed-commit, verified v0.1.0 at b7868d7a6f41 (GitHub verification: valid), 2026-10-17`; the spdx block with purl `pkg:golang/github.com/mm-weber/drill-app@0.1.0`, license MIT; the build with `ldflags: [-w, -X main.version=0.1.0]` and the binary at `/usr/local/bin/drill-app`; the accounts, os-release and annotations of the archetype, the description naming the drill. The symbol table stays (no `-s`): the drill exists to be measured, and govulncheck in binary mode answers at symbol level only when the table is present (Req 6.13, 6.16; the grafana plugins of LOG 2026-10-13 had to be read by hand because theirs was stripped).

**Acceptance criteria:**

- [ ] `scripts/lint-pins.sh`, `scripts/lint-accounts.sh`, `scripts/lint-compat.sh` and `yamllint` pass; `scripts/lint-active-set.sh .` reports `8 active definition(s), 0 inactive, 4 chart director(ies)`
- [ ] `scripts/render-tracking.sh --check` is unchanged (everything active, `ignorePaths: []`); `node test/renovate/managers.test.mjs` passes (the source shape is hardened-app's, so the existing manager captures the pin)
- [ ] On the pull request, `build.yml`'s affected-definitions job names `drill-app`; `e2e.yml`'s affected-components job names nothing new

### FR-2: The proof declaration (Req 5.9)

THE Repository SHALL declare in `catalogue-policy.yaml` one proofs entry `drill-app: {kind: none, reason: "live-drill fixture, never installed by design (task 16.2)"}`, and THE CI Pipeline SHALL print that entry by name with its reason and count it in its summary on every validation run.

Notes: the printed line is `lint-probes: drill-app: proof none, live-drill fixture, never installed by design (task 16.2) (Req 5.9)`; the summary is `8 active definition(s): 7 covered by 4 probe registration(s), each executed once per install, 1 declared none (Req 5.5, 5.8, 5.9)`.

**Acceptance criteria:**

- [ ] `scripts/lint-probes_test.sh` case 13 (the live-state guard) asserts the new counts and the drill's line; it is the track's first red test
- [ ] The validate run of the pull request shows the line: the ledger's 5.9 evidence

### FR-3: Named a drill wherever a reader meets it (Req 7.11)

THE Repository SHALL name drill-app a drill in its definition's `name:`, in its OCI description annotation, in `README.md`'s `image/` row and in `docs/user-manual.md`'s definitions row.

Notes: the status page's card is named `drill-app` from the image reference, so the reference itself says drill; nothing presents it as a product.

**Acceptance criteria:**

- [ ] `grep -n drill README.md docs/user-manual.md image/drill-app/image.yaml` finds each of the four places

### FR-4: The gate's first run (Req 6.1, 6.13, 9.11)

WHEN a pull request builds drill-app THE Scan Gate SHALL fail naming CVE-2017-20146 and CVE-2025-30204 as uncovered within its aperture, THE Scan Pipeline SHALL report govulncheck's reachability for each finding in `/usr/local/bin/drill-app`, and THE Scan Pipeline SHALL run its Grype second opinion because a CRITICAL is present.

Notes: CVE-2017-20146 is CRITICAL in github.com/gorilla/handlers@v1.2.1, fixed in 1.3.0; CVE-2025-30204 is HIGH in github.com/golang-jwt/jwt/v5@v5.2.1, fixed in 5.2.2. Expected, not asserted: both symbols reachable (the 2026-10-15 source-mode measurement); the binary-mode result is what the LOG cites.

**Acceptance criteria:**

- [ ] The run id, the gate's error annotation and the govulncheck table are captured verbatim for the LOG entry before any decision is drafted

### FR-5: The decisions (Req 6.7, 6.11, 6.13)

WHEN that gate's evidence is in THE Owner SHALL decide each finding one at a time in reach order, and WHERE a decision keeps a finding THE Repository SHALL record it as one accept entry in `triage/accepted-risk/drill-app.yaml` with `decided_at`, an `expired_at` within that finding's ceiling, `paths`, its purl, `ref` and `blocked`, and THE Scan Gate SHALL pass afterwards with nothing uncovered within its aperture.

Notes: reach order is mitigate, not_affected, transfer, accept. For the drill, mitigation and avoidance are available and declined by design (the findings are the drill's purpose; task 16.6 is the fix drill), not_affected is unavailable for a reachable symbol, and transfer has no owner but the owner. The ceilings are 30 days for the CRITICAL and 90 for the HIGH while CISA lists neither; `paths: ["usr/local/bin/drill-app"]`; `ref` points at the LOG entry; `blocked` says why the stronger treatments were declined. See the open question: the spec's 16.2 text leaves the HIGH undecided, which the gate cannot admit.

**Acceptance criteria:**

- [ ] `scripts/lint-accepted-risk.sh` and `scripts/lint-log-anchors.sh statements` pass locally; on the pull request the exception tiers step (Req 6.50) and the scan gate pass, and the VEX portability block lists the two as `affected`

### FR-6: The merge and the first publish (Req 1.14, 2.7 to 2.12)

WHEN that pull request merges THE CI Pipeline SHALL build, scan, sign, attest and tag `ghcr.io/mm-weber/dhc/drill-app` from main, and THE Repository SHALL verify by an anonymous pull token that this package is public before its next rescan; IF it is private THEN THE Owner SHALL set it public and record it in `triage/LOG.md`.

Notes: new ghcr packages are not guaranteed public; `scripts/check-visibility.sh` is the daily check and its method is the verification.

**Acceptance criteria:**

- [ ] The main run id, the three tags and the platform manifest digests recorded
- [ ] The next rescan enumerates the drill's tags and its visibility invariant passes

### FR-7: After the publish (Req 6.3, 9.11)

WHEN its first rescan after that merge runs THE Repository SHALL record what that rescan did with both findings on drill-app's supported digest, as observed in that run, never as predicted.

Notes: the data model says what to expect (an issue per finding, closed with `resolved:accepted` while an unexpired exception covers it, or a status row under the exceptions); the run says what happened (lesson 2026-10-08).

**Acceptance criteria:**

- [ ] The rescan run id, the issue numbers and the status row quoted in the LOG entry's addendum

### FR-8: The evidence (Req 7.11)

THE Repository SHALL flip ledger row 5.9 to exercised with its validate run id, SHALL add one `triage/LOG.md` entry for this drill, and SHALL tick task 16.2 in `.specs/dhc-catalogue-mvp/tasks.md` with its date and pull request.

Notes: the LOG entry carries the definition, the gate's evidence, the decisions in the LOG's rung format, then the publish and rescan facts as an addendum; the conductor track closes with the ticks, as the proof-kinds track did (#283).

**Acceptance criteria:**

- [ ] `scripts/lint-live-evidence.sh` and `scripts/lint-log-anchors.sh statements` pass; every exception's `ref` resolves to the entry's heading

## Non-functional requirements

- **No new tools:** the archetype's pins, the existing lints and the existing managers; no new script.
- **Nothing hidden from consumers:** the exceptions publish as `affected` statements in the drill's OpenVEX document; the name, the annotation and the README say drill; the upstream README says DO NOT USE.
- **The drill never gets a chart:** its `none` entry stays until 16.16 removes it with the active-set line (Req 5.10).
- **One decision at a time:** the agent drafts from evidence; the owner decides; nothing is written into the lane before the decision.

## Scope

### In scope

- Task 16.2 whole: the definition, the active-set entry, the proofs entry, the README and manual rows, the live-state test, the decisions and the LOG entry, the ledger row, the post-publish observation and the track's closing bookkeeping

### Out of scope

- Tasks 16.3 to 16.16 (each its own track; 16.3 re-decides the HIGH's exception against the KEV ceiling under 16.8's substituted feed, since trivy attributes no KEV entry to it)
- A chart for drill-app (never)
- The fix (16.6) and the regression (16.7)
- The status page's dashboard amendment (parked 2026-10-08)

### Future considerations

- When 17.5 (the `smoke` kind) exists, the drill is the natural first smoke-proved definition; until then its `none` entry is printed on every run

## Dependencies

### Upstream

| Dependency | Type | Status | Notes |
| --- | --- | --- | --- |
| `mm-weber/drill-app` v0.1.0 | upstream source | available | commit b7868d7a6f41a8dc2181bd874776cf4976d11591, signed, verified 2026-10-17 |
| Req 5.9 in the probe lint (#281) | code | merged 2026-10-17 | the `none` entry is admitted and printed |
| The CISA KEV feed on the pull request | external | live | the exception tiers step fails closed without it (Req 6.59); an outage only delays the merge |
| The owner's decisions | owner | pending | one finding at a time, after the gate's first run |
| The agent's PAT | environment | expires 2026-10-19 | rotation before phase 2's pushes |

### Downstream impacts

| Component | Impact | Mitigation |
| --- | --- | --- |
| Build matrix and nightly | one more image built and scanned daily | the drill's findings are under decided exceptions; the nightly publishes on change only |
| Status issue and page | a card and two findings under exceptions | named a drill; 16.16 retires it |
| Ledger | 5.9 flips to exercised | the row cites the validate run |
| Task 16.3 | needs the HIGH's exception to re-decide | the entry's `decided_at` and `expired_at` are the inputs it changes |

## Risks

| Risk | Probability | Impact | Mitigation |
| --- | --- | --- | --- |
| The gate cannot admit an undecided HIGH, so the spec's 16.2 text cannot publish | certain | the pull request stays red | the open question below: amend 16.2 so both findings are decided within their ceilings |
| A stripped binary gives module-level evidence only | certain if `-s` stays | no symbol-level 6.13 evidence | `-w` only; the symbol table stays |
| Someone pulls the drill image | low | a vulnerable image in use | the name, the annotation, the README and the OpenVEX `affected` statements all say so |
| The new ghcr package is private after the first publish | medium | the visibility invariant fails on the next rescan | FR-6: verified right after the publish; the owner flips it |

## Open questions

- [ ] **The HIGH.** Task 16.2's text leaves CVE-2025-30204 undecided for 16.3 and then publishes; the scan gate fails on every uncovered finding within the aperture (Req 6.1, `build.yml`), so that pull request cannot merge. Proposed amendment, the owner's call: in 16.2 both findings are decided within their ceilings (the HIGH under a 90-day accept, CISA listing neither), and 16.3 re-decides the HIGH's exception against the 14-day KEV ceiling under 16.8's substituted feed on a drill branch. The pull request opening this track carries the amendment as its own commit, to drop if the owner decides otherwise.
- [x] Keep the symbol table? Yes (FR-1): the drill exists to be measured; the owner may veto at confirmation.

## References

- `.specs/dhc-catalogue-mvp/tasks.md` task group 16, 16.2
- `.specs/dhc-catalogue-mvp/requirements.md` Req 1.13, 1.14, 5.8 to 5.10, 6.1, 6.3, 6.7, 6.11, 6.13, 7.11, 9.11
- `.specs/dhc-catalogue-mvp/design.md` Decision 13 (live drills), Decision 14 and the onboarding flow
- `image/hardened-app/image.yaml` (the archetype), `catalogue-policy.yaml`, `triage/accepted-risk/README.md`, `triage/README.md`
- `scripts/lint-probes.sh`, `scripts/lint-probes_test.sh`, `scripts/lint-accepted-risk.sh`, `scripts/check-exceptions.sh`, `.github/workflows/build.yml`
- `docs/live-evidence.md` row 5.9; `triage/LOG.md` 2026-10-13 (the reading of stripped binaries)

---

**Approved by:** pending the owner's confirmation
**Approval date:** pending
