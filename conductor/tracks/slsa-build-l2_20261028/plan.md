# Implementation plan: SLSA Build L2, provenance from the platform's signed claims, verifiable, demanded from the successor's epoch

**Track ID:** slsa-build-l2_20261028
**Spec:** [spec.md](./spec.md)
**Created:** 2026-10-28
**Status:** [ ] pending (phase 0 drafted 2026-10-28)

## Overview

Six phases, one pull request each, spec task group 18. Phase 0 is this pull request: the spec amendment and the track, together, the #308 precedent; the owner confirms by merging. Phase 1 measures what verifies the provenance service's bundle and records it in ADR 0005, no catalogue change. Phases 2 to 4 build by TDD (RED agent, GREEN agent, orchestrator commits per slice): the release step, the coverage report, the declaration with its renderings and the smoke-test assertion. Phase 5 states the claim. Phase 6 is the evidence. Nothing here demands provenance in this repository's policy; the successor does from its first release (task 12.1).

## Phase 0: the spec amendment and the track (this pull request; task 18.1)

### Tasks

- [ ] **0.1 The amendment**: requirements.md 2.9, 2.10, 2.23, 2.25, 7.7 amended, 2.27 to 2.29 and 9.19 added; design.md Decision 15; tasks.md group 18, 12.1's SLSA bullet, the coverage rows; ledger rows 2.27, 2.28, 2.29, 9.19 and the notes on 2.10 and 2.25
- [ ] **0.2 The track**: this folder, `conductor/tracks.md`, `conductor/index.md`, the todo's open item
- [ ] **0.3 The pull request**: title `spec: SLSA Build L2, provenance from the platform's signed claims, demanded from the successor's epoch (Req 2.27 to 2.29, 9.19; task 18.1)`, a TL;DR; the owner merges (checkpoint)

### Verification (orchestrator)

- [ ] Every added or amended criterion in EARS shape; `scripts/lint-live-evidence.sh .` green (159 criteria); no em-dashes in the added lines; no closing keyword before an issue number

## Phase 1: the verifier, measured (task 18.2)

Dependency: phase 0 merged. Worktree `slsa-spike`. [OPERATOR: one dispatch on the branch.]

### Tasks

- [ ] **1.1 The spike workflow** on a branch only, never merged: build a scratch image, push it to the scratch repository outside `verification.registry`, attest it with `actions/attest-build-provenance` pinned by commit, `push-to-registry: true`, subjects one index and one platform manifest
- [ ] **1.2 The reads**: the predicate as emitted (builder id, build type, external parameters, resolved dependencies), the bundle's location and artifact type, an anonymous read; verification by Kyverno 1.19.1, cosign 2.6.5, `gh attestation verify --bundle-from-oci` (with and without a login), Trivy 0.72.0 if it reads it
- [ ] **1.3 The record**: `data/slsa-provenance-spike-<date>.md` and `docs/decisions/0005-slsa-provenance-verifier.md` naming the policy verifier, the consumer command and the five expectations' exact values; the scratch package deleted; if only cosign v3 reads the bundle, the owner's call on ADR 0003 before phase 2

### Verification

- [ ] The ADR cites the run id and the measured outputs; no catalogue repository touched (the registry listing unchanged)

## Phase 2: provenance in the release path (task 18.3)

Dependency: phase 1 merged.

### Tasks

- [ ] **2.1 Permissions**: RED/GREEN in `lint-workflow-policy_test.sh` for `attestations: write` declared in the policy file's workflows section and held on `build.yml`'s release job
- [ ] **2.2 The step**: after 2.9's attestations, before the tags, one attestation per index and per platform manifest; the PR path unchanged; the rescan attests none
- [ ] **2.3 The self-check**: the release verifies each attestation with ADR 0005's verifier before tagging; a failure applies no tag and names the digest (the 2.26 shape), with a suite case in the script that carries the check
- [ ] **2.4 Renovate**: the action's pin tracked by the github-actions manager under the three-day age rule

### Verification

- [ ] Every touched suite green; `lint-workflow-policy.sh .` and yamllint green; the first release on main after the merge carrying the attestation on the index and on each platform manifest

## Phase 3: coverage reported daily (task 18.4)

### Tasks

- [ ] **3.1 `check-provenance.sh` report mode**: one digest verified against the declared identity and expectations, one line per supported digest, exit 0 on absent (Req 2.29); suite first, one test per slice
- [ ] **3.2 Require mode**: absent or mismatched fails by name (for the successor); suite cases
- [ ] **3.3 Wiring**: the rescan runs report mode over the supported set; the status data and issue gain the coverage line

### Verification

- [ ] Suites green; a scheduled rescan after the merge carrying the coverage line

## Phase 4: the declaration and its renderings (task 18.5)

### Tasks

- [ ] **4.1 The declaration**: `verification.provenance` (expectations, predicate type) in `catalogue-policy.yaml`, read by `render-verification.sh`; refused by name when malformed
- [ ] **4.2 The rule**: SLSA provenance named in `required.attestations` renders the 2.28 rule; not named renders none; both shapes in the suite and in the drift check
- [ ] **4.3 The consumer step**: the README and manual blocks gain the provenance step and the coverage sentence; BuildKit's inspect line kept, labelled supplementary
- [ ] **4.4 The smoke test**: `consumer-smoke.sh` targets a digest carrying provenance and fails on a null or unverified result (finding 2.4)

### Verification

- [ ] `render-verification.sh --check`, `consumer-smoke_test.sh`, `lint-workflow-policy.sh .` green; an offline `kyverno apply` of the required shape rejecting a pre-track digest and admitting a post-track one (recorded for phase 6)

## Phase 5: the claim, stated (task 18.6)

### Tasks

- [ ] **5.1 `SECURITY.md`**: the SLSA section (level claimed, v1.2, covered digests, the verification step, L2 from the successor's epoch)
- [ ] **5.2 `docs/concepts.md`**: the "L2-ish" sentence replaced by the measured state; the trust-boundary GitHub row names the provenance service, option D as the L3 path, option A as the other-forge seam
- [ ] **5.3 `docs/user-manual.md`** and design.md's Security Considerations

### Verification

- [ ] No sentence claims Build L2 for this repository's digests; render drift check green

## Phase 6: the evidence (task 18.7)

### Tasks

- [ ] **6.1 The reads**: the first release after phase 2 and the first rescan after phase 3, with run ids; the offline must-reject and must-admit from phase 4
- [ ] **6.2 The ledger and the LOG**: rows 2.27 and 2.29 exercised, 9.19 measured present, 2.28 left to 12.1; the LOG entry; group 18 ticked; this track closed

### Verification

- [ ] `scripts/lint-live-evidence.sh .` and `scripts/lint-log-anchors.sh all .` green

## Final verification

- [ ] Every FR's acceptance criteria met
- [ ] Every touched suite and real-repository lint green
- [ ] Documentation updated (README, manual, SECURITY.md, concepts.md)
- [ ] The successor's 12.1 bullet carries the switch-on
