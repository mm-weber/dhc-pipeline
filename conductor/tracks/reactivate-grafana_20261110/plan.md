# Implementation plan: Grafana returns to the active set, the fix rung reopened

**Track ID:** reactivate-grafana_20261110
**Spec:** [spec.md](./spec.md)
**Created:** 2026-11-10
**Status:** [~] in progress (phase 1 opened 2026-11-10)

## Overview

Two phases, two pull requests. Phase 1 is the switch itself, test-first, with the record in the same change; the owner merges. Phase 2 reads the first active day, the rebuild and the bot's bump, into the entry's addendum and closes the track. The bump and the three findings' decisions are separate work and stay in the todo: this track restores the rung, it does not spend it.

## Phase 1: the switch (this pull request)

Worktree `reactivate-grafana` from main.

### Tasks

- [ ] **1.1 RED 1: the live-state case asserts seven by four** (FR-2): `scripts/lint-probes_test.sh` case 13 expects `7 active definition(s)`, `7 covered by 4 probe registration(s)` and `0 declared none`, and fails on the repository as it stands, which reports six by three; committed red
- [ ] **1.2 GREEN 1: the line back** (FR-1): `grafana` returns to `active_set` between `cert-manager-cainjector` and `valkey`, the deactivation comment is amended, `scripts/render-tracking.sh` re-renders the tracking block with no grafana glob, and `test/renovate/managers.test.mjs`'s tracking-scope expectations move with the behaviour; nothing under `image/grafana/` or `chart/grafana/` changes; case 13 green, the whole validate suite green locally
- [ ] **1.3 The record** (FR-3, FR-4, FR-5): the README's `image/` row and the manual's definitions row name the return and its date; the LOG entry is added; ledger rows 1.15 and 1.16 gain the dated sentence; the exception file is untouched
- [ ] **1.4 The pull request**: title `chore: grafana returns to the active set, the fix rung reopened (Req 1.13, 1.14, 3.2, 5.8, 7.11)`, a TL;DR; the owner merges (checkpoint)

### Verification (orchestrator)

- [ ] `scripts/lint-active-set.sh .`, `scripts/lint-probes.sh .`, `scripts/lint-probes_test.sh`, `scripts/render-tracking.sh --check .`, `node test/renovate/managers.test.mjs`, `scripts/lint-live-evidence.sh .`, `scripts/lint-log-anchors.sh all .` all green
- [ ] No em-dashes in the added lines; no closing keyword before an issue reference; the diff touches no definition or chart file

## Phase 2: the first active day (one pull request)

Dependency: phase 1 merged. The rebuild runs at 04:47 UTC on the active set; by the owner's rule a run that is wanted now is dispatched rather than waited for.

### Tasks

- [ ] **2.1 The rebuild read**: the build run for grafana, whether the package set differed, the digest it published, the three tags moved, the release-time scan's uncovered count and what the status issue carries for the three findings afterwards
- [ ] **2.2 The end-to-end suite read**: the grafana component in the matrix of the bump's pull request, since a pull request selects components by changed chart or definition, and the `http-health` probe's result on the installed chart
- [ ] **2.3 The bot's bump**: Renovate's pull request for the current 13.1.x release, its postUpgradeTask rewriting the URL and both checksums, and the finding set its gate reports; the numbers go to the owner, the decisions are their call and their own pull requests
- [ ] **2.4 The evidence pull request**: the addendum to the LOG entry, this plan and the registry closed

### Verification (orchestrator)

- [ ] Every claim in the addendum carries its run id; the ledger's counts unchanged by this track
