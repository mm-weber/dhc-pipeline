# Track specification: Grafana returns to the active set, the fix rung reopened

## Overview

**Track ID:** reactivate-grafana_20261110
**Type:** chore
**Priority:** high (three undecided HIGH findings on the frozen digest are waiting on this decision; the oldest has been undecided for 20 days)
**Created:** 2026-11-10
**Author:** the owner, drafted by the agent
**Spec source:** `.specs/dhc-catalogue-mvp/requirements.md` Req 1.13 to 1.16 (the active set, the matrices, no digest or tag for an inactive definition, a bump of one refused), 3.2 (the tracking scope), 5.8 to 5.10 (the functional proof), 6.7 and 6.11 (the risk-treatment lane), 7.11 (the ledger); the retirement table of track `retire-grafana_20261019`; `docs/CONVENTIONS.md` "Deactivating a definition means removing its line, and only that"

### Description

The owner's call of 2026-11-10: grafana returns to `active_set`, by the same switch that removed it on 2026-10-19 and nothing more. The deactivation did what it was opened to do, exercise the switch live on a real definition, and the ledger holds that evidence. What it also did was close the fix rung on a digest the catalogue keeps scanning and clocking every day, which left three undecided HIGH findings with no treatment but a bounded acceptance and no exit but a second one. Reactivation reopens the rung: the released 13.1.x line now carries the fixed toolchain the oldest finding needs, the module behind five not-affected statements has moved past its fixed range, and a frozen image's Alpine base cannot receive a fix at all while it stays frozen.

### What the evidence says, as measured on 2026-11-10

Measured on the frozen digest sha256:89c5680a868b, pulled and extracted, and against upstream's own dependency manifests at the relevant tags.

| Finding | Needs | Frozen 13.1.7 | Released 13.1.9 |
|---|---|---|---|
| CVE-2026-111943 (issue 300, undecided, 19 of 90 days) | Go 1.26.10 | go1.26.6 | go 1.26.10 |
| the nine transfers of 2026-10-13 (expiry 2026-12-12) | Go 1.26.9, x/net 0.60.0 | go1.26.6, v0.58.0 | go 1.26.10, v0.60.0 |
| the five kin-openapi findings (not affected, statements scoped to 13.1.7) | 0.146.0 | v0.144.0 | v0.151.0 |
| CVE-2026-116587 (issue 338, undecided, 12 of 90 days) | go-jose 4.1.6 | v4.1.4 | v4.1.4 |
| CVE-2026-78661 (issue 375, undecided, 2 of 90 days) | x/net 0.62.0 | v0.58.0 | v0.60.0 |

The server binary's build information was read again for this track: go1.26.6, `golang.org/x/net` v0.58.0, `github.com/go-jose/go-jose/v4` v4.1.4. Upstream's main branch carries Go 1.27.3, x/net v0.62.0 and go-jose v4.1.8, so the two newest findings have a real exit in a release grafana has not cut yet. The two bundled plugin binaries, measured at go1.26.7 in the round of 2026-10-13 and dated 2026-09-10 and 2026-09-16, are prebuilt artifacts of their own repositories: what a 13.1.9 tarball bundles is unmeasured here, because `dl.grafana.com` is outside this environment's allowlist. The pull request gate answers that question with evidence as soon as a bump is proposed.

### The mechanism, as read on 2026-11-10

- The switch is the line. `active_set` in `catalogue-policy.yaml` gains `grafana` back between `cert-manager-cainjector` and `valkey`, and the comment that says the reference activates everything but grafana is amended. Nothing under `image/grafana/` or `chart/grafana/` moves: the directory, the chart and the `http-health` probe registration all stayed through the deactivation, as the convention keeps them.
- This pull request builds nothing. `build.yml`'s affected-definitions job derives a pull request's matrix from changed `image/<name>/image.yaml` paths and from the images a changed statement names, so a change to the policy file alone leaves the matrix empty and the scan gate scans nothing. The first scan of a rebuilt grafana is the next scheduled build.
- The open findings do not block the return. `release.fail_closed` is false, so an uncovered finding in the release-time scan is published as under investigation rather than stalling the release (Req 2.12, 2.13). `release.publish_policy` is on-change, so the first scheduled rebuild publishes only if its package set differs from the published digest's, which three weeks of Alpine updates make near certain.
- Renovate resumes. `scripts/render-tracking.sh` re-renders the tracking block without the two grafana ignore globs, so the bot extracts the definition again; `scripts/refresh-grafana.sh`, the postUpgradeTask of ADR 0002, is what rewrites the per-build tarball URL and both per-arch checksums on a version bump, as it did for the 13.1.8 bump of #279. The bump to the current 13.1.x release is the bot's to propose and the owner's to merge, and its gate is where the remaining findings are decided.
- The end-to-end suite can install the grafana chart again. `e2e.yml`'s affected-components job reads the active set to know which charts may run, then selects on a pull request those whose chart or active definition changed: this track's change touches neither, so the suite runs for grafana first on the bump that moves the definition, and on a dispatch of every component. `test/e2e/probes_test.go` has kept its `http-health` registration, an in-cluster request for `/api/health`.
- The ledger keeps what it measured. Rows 1.15 and 1.16 were exercised on 2026-10-19 and that evidence is history; each gains a dated sentence saying the definition returned, so no reader takes the row for a statement about today. The rescan's inactive-digest check reports nothing to assert when no definition is inactive, which is its own tested case.
- The five not-affected statements stay in scope for a rebuild at 13.1.7, which keeps the `13.1.7-alpine3.23` tag, and become moot at a 13.1.9 build, where the module they excuse has moved past its fixed range.

## Functional requirements (EARS)

The subject names follow design.md: the owner, the Repository (its maintainer), the Scan Pipeline, the CI Pipeline.

### FR-1: The switch back (Req 1.13, 1.14, 3.2)

THE Repository SHALL add `grafana` to `active_set` in `catalogue-policy.yaml`, amend the comment that records the deactivation, and re-render `renovate.json5`'s tracking block with `scripts/render-tracking.sh` so that no grafana path is ignored, changing nothing under `image/grafana/` or `chart/grafana/`.

**Acceptance criteria:**

- [ ] `scripts/lint-active-set.sh .` reports seven active definitions, none inactive, four chart directories with a deploys list
- [ ] `scripts/render-tracking.sh --check .` reports no ignored path; `node test/renovate/managers.test.mjs` green with its tracking-scope checks asserting the empty block
- [ ] `git diff --stat` touches no file under `image/grafana/` or `chart/grafana/`

### FR-2: The live-state guard (Req 5.8 to 5.10, 1.13)

THE Repository SHALL assert in `scripts/lint-probes_test.sh` case 13 that this repository reports seven active definitions, seven covered by four probe registrations and none declared, as this track's first red test.

**Acceptance criteria:**

- [ ] Case 13 fails on main's six by three and passes once FR-1 lands

### FR-3: Named active where a reader meets it (Req 7.11)

THE Repository SHALL name grafana active again in `README.md`'s `image/` row and in `docs/user-manual.md`'s definitions row, with the date of its return and the release it is frozen at until a bump lands.

**Acceptance criteria:**

- [ ] Both rows carry the return and its date; no other hand-written list of definitions names it inactive

### FR-4: The record (Req 7.11, 6.7)

THE Repository SHALL add the LOG entry `## 2026-11-10: grafana returns to the active set, the fix rung reopened` naming the decision, the measurement behind it, what the first scheduled rebuild and the first bump are expected to do, and what becomes of the three undecided findings and the nine transfers; and SHALL add the dated sentence to ledger rows 1.15 and 1.16.

**Acceptance criteria:**

- [ ] `scripts/lint-live-evidence.sh .` green with its counts unchanged; `scripts/lint-log-anchors.sh all .` green; no em-dashes in the added lines; no closing keyword before an issue reference

### FR-5: The findings' treatment (Req 6.7, 6.11)

WHEN the definition is active again, THE Repository SHALL leave the three undecided findings undecided inside their ninety-day ceilings, with the fix rung as their first option and the gate of the first bump as their evidence, and SHALL NOT file an acceptance for any of them in this track.

**Acceptance criteria:**

- [ ] `triage/accepted-risk/grafana.yaml` unchanged by this track; the nine entries of 2026-10-13 keep their 2026-12-12 expiry; the LOG entry says what each finding now waits on
