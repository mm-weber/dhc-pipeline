# The operating loop (upstream tracking)

How dhc-pipeline keeps its pins current, and the evidence it works end-to-end.

## The loop

```
Renovate cron (≤6h, self-hosted GHA)          renovate.yml
  → detects a newer upstream tag               custom regex managers (renovate.json5)
  → bumps only the source ref in image.yaml
  → postUpgradeTask recomputes the rest        scripts/refresh-definition.sh
      (checksum + COMMIT_SHA + ldflags commit; VERSION/SEMVER_* vars;
       full / major.minor / major alias tags; ldflags version stamp)
  → opens a PR (cert-manager grouped; majors staged on the dashboard)
  → CI builds the bumped definition            build.yml (PR path)
  → merge (patch/digest automerge on green; else human review)
```

## Live-run evidence (2026-07-21, `renovate.yml` workflow_dispatch, non-dry-run)

**Req 3.2 / 3.3 / 3.6 — grouped bump PR with a fully regenerated definition.**
From the stale cert-manager pin (`1.20.3`, one minor behind), Renovate opened
**one PR for all three images** (`renovate/cert-manager-monorepo`, PR #4):

```diff
-          - url: git+https://github.com/cert-manager/cert-manager.git#v1.20.3
-            checksum: 1e1d16d1744e6d9c80e464e58e8d9ab1caed222b
+          - url: git+https://github.com/cert-manager/cert-manager.git#v1.21.0
+            checksum: b8f325e36f49626ba72d7efbe138c01a5e661d96      # ← postUpgradeTask recomputed
-  SEMVER_MAJOR_MINOR_VERSION: "1.20"        →  "1.21"
-  VERSION: 1.20.3                            →  1.21.0
-  - 1.20-alpine3.23 / 1.20.3-alpine3.23      →  1.21-alpine3.23 / 1.21.0-alpine3.23
-  ...util.AppVersion=v1.20.3                 →  v1.21.0
-  ...util.AppGitCommit=1e1d16d1...           →  b8f325e3...
```

The recomputed checksum matches the real `v1.21.0` commit — the postUpgradeTask
resolved it via `git ls-remote` and rewrote every derived field in lockstep,
identically across all three images.

**Bonus — the docker datasource + dhi.io credentials work.** A second grouped PR
(`renovate/dhi.io-build-layer`, PR #3) bumped the builder
`dhi.io/golang:1.26.4-alpine3.23-dev → 1.26.5` (tag **and** digest, in both the
`uses:` and `GOLANG_REFERENCE` spots), with the checksum correctly left untouched
— the postUpgradeTask is scoped to `github-tags`, so a builder bump doesn't
disturb the app source.

**Req 3.1** — the run executed self-hosted on GitHub Actions.
**hardened-app** correctly got no PR: `v0.1.0` is its latest tag.

**Dependency Dashboard** (issue #5) tracks both open bump PRs and, under
"Detected dependencies", lists every manager extraction across all four
definitions (`cert-manager/cert-manager`, `dhi.io/build`, `dhi.io/golang`,
`mm-weber/hardened-app`) — confirming the regex managers see the whole pin
surface.

## Honest gaps

- **Req 3.4 (major staged on the dashboard)** has no real candidate right now —
  cert-manager's latest is `1.21.0`, no `2.x` exists upstream. The staging rule
  is in `renovate.json5` and passes `renovate-config-validator`; the dashboard
  (issue #5) confirms it by showing no "Pending Approval" section — there is
  simply nothing to stage. It will produce one for real when an upstream major
  lands.

## What the live run caught (and we fixed)

Running the loop for real surfaced a defect config-validation alone missed:
`test/renovate/managers.test.mjs` asserted the *exact current pins*
(`v1.20.3`, `1.26.4`, specific digests) against the live definitions, so **every
bump PR failed `validate`** — a loop that opens PRs nobody can merge is not
operating. The test now asserts *structure* (correct depName + a well-formed
tag/digest) instead of the frozen version, so bumps stay green while extraction
is still proven. This is the payoff of proving the loop live rather than on paper.
