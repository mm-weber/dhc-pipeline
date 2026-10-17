# Adding and removing an image: the onboarding cycle, how it grew, what others do, and the options

Research memo, collected 2026-10-15 by the agent from GitHub-hosted primary sources (the only
open-web egress the devcontainer allows) and from this repository's own history. Hosts outside
GitHub (docs.docker.com, slsa.dev, sre.google) were not reachable; where a claim rests on the
owner's earlier host research in `data/` or on general knowledge, it says so. Raw copies of every
fetched document sit in the session scratchpad under `research/raw/`; the URLs below are the
citations.

## 1. The question

Removing an image from the catalogue is a declared, tested operation (Req 1.13 to 1.16, 1.19;
drill 16.11). Adding an image that a chart deploys is not, because four rules that are each
correct on their own form a cycle:

| # | Rule | Where | Effect on a first pull request |
|---|------|-------|--------------------------------|
| 1 | A pull request that touches files under an inactive definition fails validation (Req 1.16, `scripts/lint-active-set.sh` check 4) | validate | the new directory must be activated in the same pull request |
| 2 | An active definition deployed by no chart declaring a probe fails validation (Req 5.8, `scripts/lint-probes.sh`) | validate | activation needs a chart with a probe, now |
| 3 | A chart pins its image by digest (Kyverno `require-image-digest`, no placeholder), and the e2e installs the chart with that digest pulled from ghcr.io (Req 5.2 as amended) | chart gate, e2e | the chart needs a published digest |
| 4 | A digest is published only from main, after the merge, and an inactive definition is never published (Req 1.15, `build.yml`) | main | the digest exists only after the pull request merges |

Chart needs publish, publish needs merge, merge needs chart. A one-pull-request onboarding of a
chart-backed image cannot go green. The drill-app pull request (16.2) is the first time the
catalogue meets this, because every one of today's seven definitions was already present in the
repository's first commit (2026-09-08, the greenfield seed); none was ever added through the
gates.

## 2. How the cycle grew in this repository

| Rule | Entered | Why it exists | Source |
|------|---------|---------------|--------|
| Req 5.8 (every active definition deployed by a chart with a probe) | 2026-08-25, final cleanup of the requirements | the "declare-and-lint pattern" (2026-08-25 cross-review, cell 5x5); reaction to the 6.3 lesson, where a plan checkbox claimed a probe the suite did not have | requirements.md header; `reviews/2026-08-25-requirements-primitives-cross-review.md`; tasks.md 6.3 |
| `scripts/lint-probes.sh` | 2026-09-09, PR #182, task 14.3 | review 4.8 found three of seven definitions have no standalone workload, so probes moved to the chart with a `deploys:` list; the lint refuses an uncovered active definition and deliberately offers no placeholder | tasks.md 14.3 |
| Active set, Req 1.13 to 1.19, `lint-active-set.sh` | 2026-08-25 specified, 2026-09-09 built, PR #180, task 14.2 | one declared list as the sole source of every matrix; an inactive definition frozen, its directory untouchable without activation (1.16) | tasks.md 14.2 |
| Req 5.2 "published images" | 2026-09-09, review disposition D5 (task 15.5), "spec amendments where the code is right" | the e2e had been built to pull the published digest with kubelet credentials, because a kind-loaded image carries a single-arch manifest digest and can never match the index digest a chart pins | tasks.md 15.5; docs/user-manual.md "Image access" |
| Publish from main by digest, then scan, sign, attest, tag; pull requests build to a local registry only | task 9 (August 2026) and task 7 (VEX identity) | release-time gating on the pushed digest; PR builds need an identity VEX can match but must never reach the public namespace | tasks.md 9.x; build.yml |
| Manual walkthrough "Add an image definition", step 6 "Open the PR, one logical change" | present at the first commit, updated for 14.3 (it cites Req 5.8) | written as the intended path, never run | docs/user-manual.md |
| Task 16.2 text "the chart gate and e2e get no chart for it, by design" | 2026-10-01, PR #240 | the drill wants the triage mechanisms, not the chart path | tasks.md 16.2 |

Reading: nothing here is an accident, but the four rules came from four different reviews over
six weeks, and the one place that should have joined them end to end (the walkthrough) was
written, not exercised. The 16.2 sentence of 2026-10-01 contradicts the lint of 2026-09-09 and
nobody noticed until the drill was about to run. That is the "historically grown" part: not the
rules, the missing onboarding path between them.

A second, deeper observation. The catalogue's only functional proof of an image is the chart
probe (Req 5.5 and 5.8). Every other catalogue surveyed binds its functional test to the image
itself, before publishing, and treats charts as downstream consumers. Coupling the proof to the
consumer is what makes "artifact first, consumer second" impossible here.

## 3. What others do

### Docker Hardened Images (the catalogue this project mirrors)

Source: https://github.com/docker-hardened-images/catalog (README.md, CONTRIBUTING.md,
`.spec.json`, `chart/cert-manager/helm/1.21.yaml`, `chart/cert-manager/config/values.yaml`),
fetched 2026-10-15, 658 image directories, 102 chart directories.

- The definition schema (`.spec.json`) has a top-level `tests:` array: each entry `name`,
  `directory`, `commands`, `exit-code` (required), `timeout`, `output`. The README lists
  "Tests: automated validation and compliance checks" as part of every definition file. So the
  build layer this catalogue already uses defines an image-level test, run on the built image.
  A code search of the public catalogue for `exit-code` returns two hits, both a patch
  filename, so no public definition uses the block today; whether the frontend executes it
  during `docker buildx build` is unverified from here (dhi.io login is needed to build
  locally; CI has the credentials).
- Charts are separate definitions (`chart/<name>/helm/<version>.yaml`, frontend
  `dhi.io/build:2-helm3`) whose `vars:` pin the images they deploy by tag and digest, for
  example `dhi/cert-manager-controller:1.21.2-debian13@sha256:5eb716ea…`, injected by
  `helm/rudder prepare`. A chart definition can only exist after the image digests it pins are
  published. Image first, chart second, by construction.
- Builds run in Docker's event-driven system, not in GitHub Actions; the public repository has
  no workflows, only CODEOWNERS and templates. The PR template asks "I have tested these
  changes locally" and "I have added new tests".

### Chainguard Images

Source: https://github.com/chainguard-images/images (README.md, BEST_PRACTICES.md,
WITHDRAWING_IMAGES.md, main.tf, tflib/publisher/main.tf, tflib/tagger/main.tf), fetched
2026-10-15.

- "Each image has end-to-end tests verifying the basic functionality works. Tests live under
  `images/<name>/tests/`. Base images are tested by running something on top of them" (the
  static image is tested by building and running a smoke container per language). The public
  mirror ships `locked_config.json`, README, examples and metadata; the tests directories are
  not mirrored.
- Release order in `main.tf` and `tflib/publisher`: build with apko, publish by digest, run
  `check-reproducibility` and a structure test against the pushed digest, and only then does
  the tagger apply tags to the tested reference. Tests gate tags, not pushes.
- Removal is a list file plus a workflow (`withdrawn-images.txt`, `withdraw-images.yaml`) "so
  that these operations are only done using the Chainguard identity with permission, and not by
  any human user directly", with an audit trail. Consumers follow new digests through
  digestabot, a bot that opens a pull request when a tag's digest moves.

### Docker Official Images

Source: https://github.com/docker-library/official-images (README.md, NEW-IMAGE-CHECKLIST.md,
test/README.md), fetched 2026-10-15.

- A new image is one library file in a pull request; maintainers run a shared test suite
  (`test/run.sh image:tag`) against the candidate build, and the new-image checklist asks
  "passes current tests? any simple new tests that might be appropriate to add". Tests are
  per image, selected by a config that says which images each test applies to.
- The "Repeatability" review guideline: rebuilding the same Dockerfile must yield the same
  version or fail outright.

### Bitnami

Source: https://github.com/bitnami/containers CONTRIBUTING.md, https://github.com/bitnami/charts
CONTRIBUTING.md, fetched 2026-10-15.

- "Once the changes are accepted, the PR is tested (if needed) in the internal Bitnami CI
  pipeline. This may include testing both the container and any associated Helm Chart. The PR
  is merged … Then our CI/CD system is going to push the container image to the different
  registries." Candidate tested before merge in a private pipeline; the public registry
  receives the image after merge; charts live in a second repository and reference published
  images.

### Kubernetes image promotion

Source: https://github.com/kubernetes/k8s.io registry.k8s.io/README.md,
https://github.com/kubernetes-sigs/promo-tools README.md, fetched 2026-10-15.

- Every subproject builds into a staging registry with a 90-day retention policy ("Please
  don't serve images to end users from there"). Promotion to the production registry is a pull
  request that adds digests to `images/k8s-staging-<project>/images.yaml`; the promoter copies
  by digest. The canonical "build once, promote by digest" pattern, with human review on the
  promotion manifest rather than on a rebuild.

### Konflux (Red Hat)

Source: https://github.com/konflux-ci/docs (`modules/testing/pages/integration/adding.adoc`,
`modules/patterns/pages/maintaining-references-before-release.adoc`,
`modules/releasing/pages/index.adoc`), fetched 2026-10-15.

- A build produces a Snapshot of candidate images; "Konflux runs these integration tests on
  the container images of components before their release"; a failing mandatory test marks
  the snapshot failed and blocks release; a release pipeline then copies the images to the
  target repository.
- Our exact problem has a page: "Maintaining valid image references before a release". When a
  component carries references to images that will only exist after release, Konflux rewrites
  them through "nudges", and admits that "once this change is merged, the nudged component will
  contain invalid references until all referenced images are released", recommending a
  registry mirror set to test in the meantime. Even a full promotion system lives with a
  declared, temporary invalid state for consumers of not-yet-released images.

### Helm chart-testing, distroless, Argo CD Image Updater

- `ct install` (https://github.com/helm/chart-testing doc/ct_install.md) installs changed
  charts and, with `--upgrade`, tests previous chart revision to current. Charts under test
  reference images that already exist; the tool has no notion of a candidate image.
- distroless (RELEASES.md): "Images are automatically built and pushed every commit" with a
  reproducible Bazel build; tests run in the build graph before push.
- Argo CD Image Updater and Renovate's digest pinning are the standard way deployed references
  follow a newly published digest: a bot writes the new digest into the deployment source
  after publish. This is the model the catalogue already runs (chart-pin bumps, Req 5.6).

### The three invariants that recur

1. Functional tests bind to the image candidate and run before the artifact is tagged or
   released (DHI schema, Chainguard, Official Images, Bitnami, Konflux, distroless).
2. Charts and deployments reference published digests and follow them through bots
   (Chainguard digestabot, Renovate, Argo CD Image Updater, Konflux nudges, DHI chart
   definitions pinning published digests).
3. Adding an image is therefore two stages everywhere: artifact first, consumers second.

This catalogue has invariants 2 and 3 for *changes* to an image (publish, then the chart-pin
bump exercises it). It lacks invariant 1, so stage one of an onboarding has no proof of its
own, and 5.8 forbids stage one without stage two.

## 4. The options

| Option | Mechanism | Spec delta | Code delta | Posture effect | Verdict |
|--------|-----------|------------|------------|----------------|---------|
| A. Chart in the first pull request | as today | none | chart + harness entry | impossible: the chart cannot pin a digest that does not exist; the e2e cannot pull it | out |
| A1. Same, merge over a red e2e | administrator bypass of a required check | none | same as A | a recorded bypass in the posture register for every onboarding | out as a standard operation |
| A2. Same, e2e defers a first install | harness skips a component whose chart is new on the branch and whose digest is not in the registry | 5.2/5.6 gain a first-install rule | e2e workflow and suite | the chart still needs a digest value to satisfy Kyverno; only a placeholder fits, which the manual forbids | out |
| B. Drill-only exemption | hard-coded skip for drill-app | 5.8 caveat | lint | a special case in a rulebook that has none | superseded by C |
| C. Declared "undeployed" state with reason and review-by | policy file entry; lint skips and names it; lapse fails validation (the compat review-by shape) | 5.8 gains "unless declared", one new criterion for reason, date, lapse | definition-lib reader, lint-probes, tests, docs | no silent gap; onboarding becomes two pull requests | minimal correct step |
| D. Proof kinds per definition | `proof:` declaration: `chart` (today, default), `none` (C, dated), later `smoke` (an image-level test on the candidate in the PR build, the frontend's `tests:` block or a `docker run` step) | 5.8 restated over proof kinds; 5.9 for `none`; a later criterion for `smoke` | C now; `smoke` is a new runner later | restores invariant 1 when `smoke` lands; base and dev images become possible without charts | the modular model; C is its first increment |
| E. Candidate digests in the production repository | PR builds push by digest, untagged; merge promotes by tagging the same digest; no rebuild on main | 2.x release flow, 1.15, provenance statements | build.yml rewrite, retention for untagged digests, attestations at PR time | unreviewed digests become pullable by anyone who knows them; builder identity becomes the pull_request run; "every digest attested" promises need rewording | later milestone at most |
| F. Staging namespace plus promotion | PR builds push to a second namespace; e2e installs from it with a repository override; merge copies by digest to production (Kubernetes, Konflux shape) | as E plus the namespace in 2.21, Kyverno restrict-registries | as E plus kubelet credentials, policy exception for e2e, cleanup | the full industry pattern, the largest change | later milestone at most |
| G. 5.8 as a daily report instead of a gate | status page lists uncovered active definitions | 5.8 weakened | lint becomes a reporter | reintroduces the 6.3 gap as a warning nobody must read | out |
| H. Reproducible builds as an enabler | if a rebuild on main reproduced the PR digest, the chart could pin it before merge | none | none | Decision 6 (2026-08-22) measured the frontend as non-reproducible and set a 95 percent over two weeks condition that is not met; and the e2e still could not pull before merge | not available |
| I. e2e as a release gate on main | Chainguard order: push digest, install and probe it, then tag | 5.2 moves from pull request to release | release arm gains a kind run per definition | first install proven on the real digest; the chart pin still needs a declared first-release state before that | a refinement of D or E, not a fix on its own |

## 5. Recommendation

Adopt D as the model and build C as its first increment. Concretely:

1. Spec pull request: Req 5.8 reads over a per-definition proof declaration; the default
   proof is the chart probe as today; `none` is allowed with a reason and a review-by date and
   fails validation by name when the date passes; `smoke` is named as a future kind, not built.
   Task 16.2's sentence changes from "stated in the definition" to "declared in the policy
   file"; the manual's walkthrough becomes two pull requests (image with `proof: none` and a
   due date; chart, harness entry and removal of the declaration after the first publish).
2. Implementation by TDD: one reader in `scripts/definition-lib.sh`, `lint-probes.sh` and its
   suite, docs.
3. Drill-app is the first user with `proof: none`, reason "live-drill fixture, never installed
   by design", review-by at its retirement (16.16).
4. Record E and F in design.md as the known long-term direction if candidate-level e2e is ever
   wanted, and the DHI `tests:` block as the first thing to try for `smoke` (verify in CI
   whether the frontend runs it).

Why not E or F now: they solve the cycle structurally but change the release flow, the
provenance story and the public namespace for a problem that the two-stage model handles with
one declaration, and no surveyed catalogue proves a chart against a candidate image inside the
image's own pull request; they prove the image, then let consumers follow.

## 6. Sources

- https://github.com/docker-hardened-images/catalog (README.md, CONTRIBUTING.md, .spec.json, .github/pull_request_template.md, chart/cert-manager/helm/1.21.yaml, chart/cert-manager/config/values.yaml, image/valkey/debian-13/9.1.yaml, image/nginx/alpine-3.23/mainline.yaml, image/python/alpine-3.23/3.13.yaml, image/postgres/debian-13/17.yaml, image/alpine-base/alpine-3.23/3.23.yaml; code search "exit-code" in image/)
- https://github.com/chainguard-images/images (README.md, BEST_PRACTICES.md, WITHDRAWING_IMAGES.md, BUILDING.md, main.tf, tflib/publisher/main.tf, tflib/tagger/main.tf, .github/workflows listing)
- https://github.com/docker-library/official-images (README.md, NEW-IMAGE-CHECKLIST.md, test/README.md)
- https://github.com/bitnami/containers (CONTRIBUTING.md, README.md); https://github.com/bitnami/charts (CONTRIBUTING.md)
- https://github.com/kubernetes/k8s.io (registry.k8s.io/README.md); https://github.com/kubernetes-sigs/promo-tools (README.md)
- https://github.com/konflux-ci/docs (modules/testing/pages/integration/adding.adoc, modules/patterns/pages/maintaining-references-before-release.adoc, modules/patterns/pages/testing-releasing-single-component.adoc, modules/releasing/pages/index.adoc)
- https://github.com/helm/chart-testing (README.md, doc/ct_install.md)
- https://github.com/GoogleContainerTools/distroless (README.md, CONTRIBUTING.md, RELEASES.md)
- https://github.com/chainguard-dev/apko (README.md); https://github.com/argoproj-labs/argocd-image-updater (README.md)
- This repository: .specs/dhc-catalogue-mvp/requirements.md, tasks.md (6.3, 14.2, 14.3, 15.5, 16.2), design.md (Decision 6), reviews/2026-08-25-requirements-primitives-cross-review.md, docs/user-manual.md, scripts/lint-probes.sh, scripts/lint-active-set.sh, .github/workflows/build.yml and e2e.yml, triage/LOG.md (2026-09-0x reproducibility record), data/reproducible-digests-vs-content-diff-2026-08-22.md, data/docker_internal_build.md
- Not reachable from the devcontainer, cited from the owner's `data/` notes or general knowledge only: docs.docker.com (DHI documentation), slsa.dev, sre.google
