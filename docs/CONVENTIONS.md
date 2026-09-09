# Conventions

Rules for every definition, chart, and PR in this catalogue. CI enforces what
it can (see `policies/` and `.github/workflows/validate.yml`); reviewers hold
the rest. Requirement references point at `.specs/dhc-catalogue-mvp/requirements.md`.

## Naming (Req 2.3)

- Images: `ghcr.io/mm-weber/dhc/<name>:<semver>-<os><osver>[-<variant>]`
  - Example: `ghcr.io/mm-weber/dhc/hardened-app:0.1.0-alpine3.23`
  - `<semver>` is the upstream version, without a `v` prefix
  - `<os><osver>` follows the upstream catalog's dotted form: `alpine3.23`
    (alpine-only for now — ADR 0001; the deb path is unverified)
  - Each release also carries major and major.minor alias tags
    (`0-alpine3.23`, `0.1-alpine3.23`), catalog-style
- Variants: no suffix = runtime (non-root, minimal). `-dev` = build-stage tooling,
  root permitted, never deployed. `-compat` = runtime plus shell/coreutils for
  charts that assume them; using it requires a documented decision (Req 4.5).
- Charts: directory `chart/<upstream-name>/`; adapted release name `dhc-<name>`.
- Definitions: directory `image/<name>/` containing `image.yaml`, one per
  emitted image (a definition's top-level `image:` names exactly one
  repository — upstream catalog structure). A monorepo producing several
  images (see cert-manager-{controller,webhook,cainjector}) keeps byte-equal
  source pins (`vars:`, `url:`, `checksum:`) across its definitions; Renovate
  groups their bumps into a single PR (Req 3.3) so one version moves all.
- A **variant** that has to be built rather than merely tagged gets its own
  directory, `image/<name>-<variant>/` (see valkey-compat). It publishes to the
  repository its runtime sibling names — the variant is a tag suffix, per
  Naming above — so this is the one case where two definitions emit to **one**
  repository and a definition's directory name is not its published image name.
  Same byte-equal-source-pins and single-PR rules as a monorepo; the pair is
  additionally checked for parity by `scripts/lint-pins.sh`, since a variant
  that drifts from its runtime sibling stops being that image plus a package.
  - Consequence worth knowing before writing one: Trivy builds a scanned
    image's product purl from its RepoDigest, so **both** valkey definitions
    are read as `valkey`, and a VEX product naming the directory matches
    nothing. `scripts/compile-vex.sh` and `scripts/lint-vex-product.sh`
    therefore resolve the product name through the definition's `image:`, and
    the published tag is what separates the two (Req 6.29, 6.30).
  - So a directory name is never an image name anywhere. Every reader of that
    mapping goes through `scripts/definition-lib.sh` — the two lints above, the
    compiler, and `build.yml`'s affected-definitions step, which derives its
    matrix from the product purls on a VEX-only change. Add a caller there
    rather than re-reading `image:` locally: the reader that misses a spelling
    does not fail, it resolves to the directory name and reports clean.

## Pinning (Req 1.2, 1.3, 1.6)

- Every base image reference carries `@sha256:<digest>`. No exceptions.
- Every upstream source is `git+https://...#<ref>` plus a `checksum:` line.
- Every definition declares, beside its source url, how its upstream's
  authenticity is established: `# authenticity: signed-tag` (an annotated tag
  GitHub verifies: cert-manager), `signed-commit` (a lightweight tag on a
  commit GitHub verifies: valkey, hardened-app) or `cross-origin-checksum`
  (two origins state the same per-architecture checksum: grafana). `none` or
  a missing marker fails `lint-pins.sh` (Req 1.10, 1.11); a refresh verifies
  the declared signal before writing any field of a bump and appends what it
  verified and when to the marker (Req 3.8). dhi.io package repositories are
  the `/main` lines only, `dhi.io/apk/<distro>/<release>/main` or
  `dhi.io/deb/<distro>/main`; the others are entitlement-gated (Req 1.12).
- Every upstream chart is pinned to an exact version in `chart/<name>/chart.yaml`,
  and Renovate tracks that version against the chart repository through the
  native helm datasource: a new chart release opens a PR that is never
  automerged and runs the e2e upgrade path, because a chart release can
  change what its values mean (Req 3.11, 5.6). The **image** pins in each
  chart's values are tracked with tag + digest (task 8.7), so a definition
  bump reaches the deployed chart and a same-tag rebuild moves the digest; a
  bump that moves only the digest automerges behind green required checks,
  a tag move waits for a human (Req 3.12).
- Floating tags (`latest`, bare majors like `:1`, digestless tags) fail CI.
- A digest is 64 lowercase hex characters, and both gates read them:
  `scripts/lint-pins.sh` over the sources and `policies/require-image-digest.yaml`
  over rendered manifests. `@sha256:PENDING` is a floating reference wearing the
  separator — never use a placeholder to get a pin past review; leave the
  reference unpinned, which fails for the reason that is actually true.
- Every GitHub Action is pinned to a full commit SHA, and **every third-party
  executable a workflow installs is pinned to an exact version and verified
  against a checksum recorded here** (Req 7.5). Trivy and grype
  (`scripts/install-scanners.sh`) and kind, kyverno, helm, ct, syft and crane
  (`scripts/install-tool.sh`) meet both halves with digests recorded in-repo;
  govulncheck is exact-pinned with the Go module sumdb as its checksum control
  (`build.yml`), the renovate/json5 test installs are exact-pinned with
  npm registry integrity verification (`validate.yml`), and the python
  packages CI installs (yamllint, yamale + their deps) are exact-pinned with
  their sha256 hashes recorded in `.github/requirements-ci.txt` and installed
  with `pip install --require-hashes`. Every one of these
  pins carries a Renovate manager (Req 7.6). `curl … | sh` from a branch is a
  floating tag with a shell attached: the tag can be repointed and the script
  re-published under the same URL. That is not hypothetical for this toolchain —
  CVE-2026-33634 (March 2026) repointed 76 of 77 `aquasecurity/trivy-action`
  tags to a credential stealer and published a malicious trivy release.
- Pinning a **scanner** is only safe if something bumps it, because a stale
  scanner is a silent failure. The pins carry a Renovate manager (Req 7.6); the
  advisory **database** still updates on every run. Version and DB are
  separately versioned, and only the version gets pinned.
- Humans never bump pins by hand when Renovate is able to; hand-bumps are reserved
  for CVE fix-forwards (Req 6.5) and say so in the PR description. A fix-forward
  on a compile-from-source image between upstream releases is a `go/bump@v2`
  step in the definition's fetch phase (the sandbox has no egress, so a `runs:`
  step cannot fetch a module; measured 2026-07-26, established 2026-09-02):
  each bumped module carries a `# renovate:` marker so the pin stays tracked,
  the pin is a floor a later upstream requirement wins over, and its LOG
  entry names the upstream version at which the step is dropped.
- **Packages from package repositories are not pinned in definitions, by
  design (Req 1.9).** A definition names its apk repositories and package
  names, never versions: the DHI model ships base fixes by rebuilding, no
  versioned apk syntax exists in any input, and pinning would reinvent a
  datasource and turn every base advisory into a bump PR. What floats is apk
  alone; everything else in a definition (frontend, builder, every upstream
  source) is digest- or checksum-pinned and moves through the merge path.
  Three mechanisms make the float safe rather than blind:
  - **The resolved set is recorded per digest.** Each platform manifest's
    resolved package set, with apk pull checksums, is in the SPDX and
    CycloneDX SBOMs attested to that manifest (and each platform's SPDX to
    the index, which is what a tag resolves to), so "what exactly is in
    this digest" is a signed answer, not a rebuild.
  - **The pushed digest is scanned before it is tagged.** The release arm
    scans every platform manifest of the digest it just pushed, by that
    manifest's own digest, with the same inputs as the PR gate; only then
    does it sign, attest and, last, tag (Req 2.7 to 2.9).
  - **The daily rebuild is the delivery mechanism for base fixes.** Every
    definition rebuilds daily (Req 2.14); a rebuild whose canonicalised
    package set equals the published one is discarded, and one that differs,
    which is how an apk fix arrives, publishes through the same release arm
    with the difference in the run summary (Req 2.15, 2.16; a fork sets the
    publish policy to `always` to publish every rebuild, Req 2.17).

## Definitions (Req 1.5, ADR 0001)

Definitions are native DHI syntax, built by the real `dhi.io/build` frontend.
One file per component at `image/<name>/image.yaml`. Rules, all enforced by
`scripts/lint-pins.sh` in CI:

- Line 1 is the frontend pin, **digest-pinned** — one step stricter than the
  upstream catalog (the frontend is the compiler AND the actions stdlib; its
  digest is their implementation hash — see docs/concepts.md):

  ```yaml
  # syntax=dhi.io/build:2-alpine3.22@sha256:<digest>
  ```

- Top-level `image:` is the publish name — a bare repository reference
  (`ghcr.io/mm-weber/dhc/<name>`): its digest cannot exist before the build,
  and release tags live under `tags:`.
- Builder images in `uses:` (e.g. `dhi.io/golang:*-dev`) are digest-pinned.
  Pipeline actions (`go/build@v1`, `go/bump@v2`) carry interface versions
  only — they resolve inside the pinned frontend, nothing to checksum.
- Every `git+` source line has a sibling `checksum:` (commit hash).
- **Prebuilt-tarball archetype** (grafana): the source is a versioned vendor
  URL (`https://…/<name>-<ver>.linux-${ARCH}.tar.gz`) pinned by version. A
  per-arch release has a different SHA-256 per arch, so it can't use one
  `checksum:` line — instead pin the arch's SHA-256 in `vars:` via the
  catalog's arch-select expression
  (`#{ target.arch == "amd64" ? "<amd64>" : "<arm64>" }`) and verify it in a
  pipeline `sha256sum -c` step. `${target.arch}` goes directly in the tarball
  URL. That pinned-and-verified hash is the content pin (Req 1.3) for this
  archetype.
- Version state lives in `vars:` with the catalog's names (`VERSION`,
  `SEMVER_*`, `COMMIT_SHA`) — that block is the Renovate bump surface.
- Runtime `accounts:` declare `nonroot` 65532 with `run-as` (Req 1.4).
- Alpine variants only for now; the deb path is unverified (ADR 0001).
- The linter is the fast gate; the **frontend itself is the authoritative
  validator** — it compiles every definition on each PR build (Req 1.5).

- **A definition copied or adapted from the DHI catalog carries a
  modification notice.** No definition here is one: each was authored in
  this repository against the frontend's documented syntax (the cert-manager
  definitions cross-checked one pin against the catalog, which is reading,
  not copying). A definition that starts from a file in
  `github.com/docker-hardened-images/catalog` opens with a prominent comment
  naming the source file and commit and stating that it was changed here
  (Apache-2.0 section 4(b)), and keeps every copyright and attribution
  notice the source carried (section 4(c)). `NOTICE` names the substrate's
  copyright and licence; `LICENSES/Apache-2.0.txt` is the licence text
  (Req 9.16).

## Runtime accounts (Req 1.4)

- Runtime images run as UID/GID **65532** (`nonroot`), declared in the definition's
  `accounts:` block. Only `-dev` variants run as root, and only at build time.

## Upstream tracking (Req 3, ADR 0002)

Renovate is driven entirely by custom regex managers, every built-in manager
disabled, so nothing opens a surprise PR. Over `image/*/image.yaml` there is
**one manager per archetype**, and adding an image means checking its source
shape is covered; the other pin surfaces (chart versions and chart image pins,
tool pins, workflow and CI dependency pins) carry one manager each:

| Archetype | Source shape | Datasource | postUpgradeTask |
|---|---|---|---|
| compile-from-source | `url: git+https://…#vX.Y.Z` | `github-tags` | `refresh-definition.sh` |
| tarball-repackage | `url: https://<vendor>/…-X.Y.Z.linux-…` | `github-releases` | `refresh-grafana.sh` |
| build layer | `syntax=` / `uses:` / `GOLANG_REFERENCE:` | `docker` | none (reviewed by hand) |
| upstream chart version | `upstream:` block in `chart/<name>/chart.yaml` | `helm` (the chart repository) | none (never automerged; a bump runs the e2e upgrade path, Req 3.11) |
| chart image pins | tag@digest or digest values in `chart/<name>/config/values-hardened.yaml` | `docker` (ghcr.io) | none (digest-only bumps automerge, Req 3.12) |

- **The download host and the version datasource are separate concerns.** A
  vendor that ships prebuilt tarballs off its own CDN can still be tracked
  against its GitHub releases; do not assume an untrackable download URL means
  an untrackable dependency (ADR 0002).
- A bump PR must leave the definition **coherent**: the postUpgradeTask
  regenerates every version-derived field (tags, `SEMVER_*`, checksums, purl,
  spdx version, annotations, the display name's `<major.minor>.x` suffix)
  from the one value Renovate changed. Anything the task cannot derive is
  called out in the ADR and fixed by the reviewer.
  Enforced by `scripts/lint-pins.sh` in `validate` (Req 7.4) for the fields
  it can read: release tags, `vars:` (`SEMVER_*` and any `*_VERSION`), the
  SPDX `version:` and `purl`, semver tokens in `url:` values, and the display
  `name:` version suffix — spelled in block style, which the lint enforces.
  The ldflags version stamp and dotted annotation keys stay with the
  reviewer. The reviewer is otherwise the fallback, not the mechanism — a
  postUpgradeTask that refuses still leaves Renovate free to open the PR
  carrying the manager's partial edit, and grafana 13.1.3 (#36) is what that
  costs when nothing checks.
- What automerges, exactly (Req 3.5, 3.12): patch and digest updates of a
  compile-from-source upstream, and digest-only updates of the catalogue's own
  image pins under `chart/`, both behind green required checks. Repackage bumps
  **never** (they swap a binary we did not build), chart versions never (a
  chart release can change what its values mean), tool pins never (their
  checksum half is human, Req 7.5), the build layer never, minors and majors
  of anything never. Every third-party release bump waits its minimum release
  age first, three days, and a release Renovate cannot date waits rather than
  passes (Req 3.7); only the docker datasource, the catalogue's own digests
  and the hand-reviewed build layer, is exempt.
- Age is one half of independence from a compromised release; the declared
  signal is the other. A refresh verifies the definition's `# authenticity:`
  class before it writes any field of a bump and refuses by name otherwise
  (Req 3.8); a repackage checksum change is re-verified at PR time against
  the bytes served and the upstream's version statement
  (`scripts/verify-arch-pins.sh`, Req 3.9); and the daily rescan re-verifies
  every active definition's signal, failing the run and filing a
  `supply-chain` issue on a mismatch (`scripts/check-authenticity.sh`,
  Req 3.10).
- **Check how the upstream versions its security releases before trusting the
  default versioning.** Grafana ships out-of-band fixes as semver build
  metadata (`v13.0.1+security-01`), and semver *ignores build metadata for
  precedence* — under the default scheme those releases rank equal to their
  base version and Renovate reports "up to date" straight through a security
  fix. Where an upstream does this, set an explicit `versioningTemplate` that
  maps the counter onto a comparable component (ADR 0002).
- **Release tags must be valid OCI references** —
  `[a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}`, enforced by `lint-pins.sh`. `+` is
  illegal, so a semver build separator becomes `_` in the tag
  (`13.0.1+security-01` → `13.0.1_security-01-alpine3.23`, the eclipse-temurin
  convention) while every other field keeps the upstream version verbatim.
- Every manager is covered by `test/renovate/managers.test.mjs`, which asserts
  both that it captures its own definitions and that it does **not** capture
  the others. `renovate-config-validator --strict` proves the config parses;
  only the fixtures prove the regexes still match.
- **The tracking scope is the active set** (`catalogue-policy.yaml`
  `active_set`, Req 1.14; task 14.2). Renovate reads no policy file, so
  `scripts/render-tracking.sh` renders the set into the delimited
  `ignorePaths` block of `renovate.json5`: one glob per inactive definition
  directory and per chart directory whose `deploys:` list names no active
  definition, so no bump opens for a frozen definition (Renovate skips every
  file under an ignored path before any manager reads it). validate fails on
  drift between the block and the set; edit the set or a chart's `deploys:`
  and re-render, never the block. The same mapping drives the build and e2e
  matrices: `scripts/definition-lib.sh` reads the set and each chart's
  `deploys:` list, and `scripts/lint-active-set.sh` holds the set coherent
  (a byte-equal pair or a source-grouped monorepo activates or deactivates
  whole, Req 1.18; every entry is a definition directory, Req 1.19).

## Chart override style (Req 4)

- Upstream chart templates are never edited, forked, or patched (Req 4.1).
- All deltas live in `chart/<name>/config/values-hardened.yaml`.
- Canonical securityContext block (Req 4.3) — pod level unless the chart only
  exposes container level:

  ```yaml
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    runAsGroup: 65532
    seccompProfile: {type: RuntimeDefault}
  containerSecurityContext:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities: {drop: [ALL]}
  ```

- Writable paths get named `emptyDir` mounts, one per path, commented with why
  the workload writes there (Req 4.4).
- Every deviation from upstream defaults appears in `chart/<name>/README.md`
  as: *what changed → why → requirement or upstream issue link* (Req 4.7).
- **Every chart declares what it deploys and how it is proved.**
  `chart/<c>/chart.yaml` names the definition directories the chart deploys
  (`deploys:`, the e2e matrix and the tracking scope read it, task 14.2) and
  the functional probe the e2e suite runs once its pods are Ready (`probe:`,
  a registration name in `test/e2e`'s `probes` map, task 14.3). One probe
  per chart, executed once per install for every definition it deploys
  (Req 5.5). validate fails an active definition whose chart names no probe
  (Req 5.8); a Go unit test holds declared names and registrations equal
  both ways. There is no placeholder: a chart with nothing to prove declares
  no probe, and its definitions stay inactive.

## Policy gate (Req 4.6)

Rendered manifests of every chart are evaluated by the Kyverno policies in
`policies/`: images referenced by digest, only from the declared registry
namespace (`catalogue-policy.yaml` `verification.registry`), workloads
non-root. The registry policy is rendered from that value by
`scripts/render-verification.sh` and drift-checked like the verification
policy (Req 7.8, 7.9; task 14.1), so a fork's gate admits the fork's
namespace by editing one line; `policies/tests/resources.yaml` names the
reference namespace literally and is the one fixture that edit touches.
Policy fixtures live in `policies/tests/` and run via `kyverno test` in CI
(no kyverno binary in the devcontainer — Req 8.2).

## Scanning & triage (Req 6)

Every image a PR builds is scanned by Trivy for `HIGH,CRITICAL` in
`build.yml`; the gate fails on any finding **not** excused by an OpenVEX
statement in `triage/vex/` or a time-boxed exception in
`triage/accepted-risk/<image>.yaml`, and a Grype second opinion runs on any
surviving `CRITICAL`. Red gates are cleared by a recorded decision — drop the
component, a fix-bump PR, an OpenVEX statement (`vexctl`, `cosign attest`), or an
accepted-risk entry — plus a `triage/LOG.md` entry, never by silencing the
scanner.

The two suppression lanes are **not** interchangeable. VEX states a vulnerability
does not apply (or that this release carries the remedy), is attested to the
image, and never expires; `triage/accepted-risk/` records that it *does* apply
and we ship anyway for a bounded time, and is published in the same attested
document as an `affected` statement, **never as `not_affected` or `fixed`**
(Req 6.8): that would launder a business decision into a machine-readable claim
of technical inapplicability, and every consumer would inherit it. An `affected`
statement suppresses nothing (Req 6.35); it tells a consumer the truth, with the
treatment, the upstream issue, the binaries and the expiry in its action
statement (Req 6.38). Exceptions carry a treatment
(`accept` / `transfer`), an owner, the reason avoidance and remediation were
unavailable, a `decided_at`, and an `expired_at` no later than that decision date plus the policy file's largest ceiling (`catalogue-policy.yaml` `triage.ceilings`; the gate and the rescan then hold each entry to the tier its finding earns: the KEV ceiling when CISA lists it, else its severity's ceiling, Req 6.50, 6.51);
`scripts/lint-accepted-risk.sh` enforces that and rejects any Trivy ignore file
living anywhere else (Req 6.11, 6.12).

A daily `rescan.yml` cron re-scans every platform manifest of every published
digest for CVEs that land after merge, attests today's reports and re-attests
the OpenVEX document when the decisions changed, replacing (exactly one
attestation per digest, Req 6.42 to 6.44). Over the supported set it files one
issue per new HIGH/CRITICAL finding, closes issues on evidence with graded
`resolved:*` labels and reopens them on recurrence (Req 6.52 to 6.57), and
rewrites the catalogue status issue with every finding's clocks (Req 6.46,
6.47), all through the unit-tested `triage/rescan/` Go tools. See
`triage/README.md`.

- **The VEX consumers are a declared list** (`catalogue-policy.yaml`
  `consumers.list`, Req 9.11): exactly one authoritative (Trivy, the gate's
  scanner), every other one an adapter case in `scripts/vex-consumer.sh`
  emitting the same shape (vulnerability, purl, suppressed). A statement is
  written for the authoritative matcher; whether it lands elsewhere is the
  VEX portability block's measurement in every scan summary (Req 9.12),
  informational unless `consumers.gating` is flipped. The README recipe
  carries one scan step per declared consumer, rendered from the list, and
  the rescan runs that recipe verbatim daily against one supported digest
  (Req 9.13): a step that fails or a suppression the authoritative consumer
  misses fails the run. Adding a consumer means: the list, an adapter case,
  a recipe step in `render-verification.sh`, a pinned install (Req 7.5).
- Reading a divergence and deciding whether it matters is register row M19
  below.
- **Every decision cites the LOG, and the citation resolves** (Req 9.18):
  an exception's `ref:` and a statement's `status_notes` name a
  `triage/LOG.md` heading as `LOG.md#<slug>` (the heading's GitHub anchor)
  or `LOG.md <date>` (a day heading); `scripts/lint-log-anchors.sh` fails
  validate on a citation that names no heading and on a decision without
  one, so renaming a heading is caught by the records that rest on it.

## Manual controls (Req 9.14)

Every step a human takes in operating this catalogue, in one place, so that
no human-per-item control is unlabelled toil (review F13). Two classes only:
**deliberate**, kept on purpose with the reason stated, or **pending
automation**, a gap with its intended mechanism named. A review date is a
column, not a class. The manual's operator paragraphs cite these rows by id;
a row that names no fork switch is one a fork keeps or changes by removing
the step altogether.

| Id | Step | Class | Reason | Fork switch | Review by |
|---|---|---|---|---|---|
| M1 | Complete a tool-pin bump: record the new sha256 in `scripts/install-scanners.sh` or `scripts/install-tool.sh` (and the hash in `.github/requirements-ci.txt`) after comparing the release's checksums with a second source (Req 7.5) | deliberate | A checksum that updates itself verifies nothing: CVE-2026-33634 republished bytes under already-adopted versions. The second source is a Sigstore bundle, SLSA provenance, or the binary's embedded source commit (measured 2026-09-08: trivy, grype, kyverno and crane sign or attest, kind does not) | A verifier over the published signature where one exists, leaving the unsigned tools human | none |
| M2 | Review and merge build-layer bumps (`dhi.io/build` frontend, `dhi.io/golang` builders) | deliberate | A toolchain change moves stdlib findings in every compiled image at once; the scan-gate delta is what the reviewer reads | `automerge: true` on the build-layer rule in `renovate.json5` | none |
| M3 | Decide a finding: write a VEX statement (`vexctl`, `triage/vex/`), an accepted-risk exception (`triage/accepted-risk/`), a fix bump, or a drop, and the LOG entry that argues it (Req 6.4, 6.5) | deliberate | Judgement is the human's; everything mechanical around it (compile, lint, ceilings, the issue lifecycle, expiries, the status clocks) is automated | none: a fork automates evidence, never the decision | per entry: the exception's `expired_at`, the statement's LOG citation |
| M4 | Sign hardened-app's release tags in its own repository (the `signed-commit` class needs a verified commit) | deliberate | The authenticity signal rests on a key only a person holds; the refresh refuses an unverified bump (Req 3.8) | The definition's class, or an upstream whose release workflow signs with a Sigstore identity | none |
| M5 | Bump cosign by hand and keep it on the v2 line (`cosign-release` in `build.yml` and `rescan.yml`, ADR 0003) | deliberate | cosign v3 writes a bundle layout Kyverno 1.18.2 and Trivy 0.72.0 could not find (measured 2026-08-22); a move happens only when both consumers are measured to read v3 bundles, and the daily smoke test is the control that would catch an unmeasured one | The pinned version | 2026-10-22: re-measure with kyverno 1.19.0 and trivy 0.74.0, both newer than the ADR's measurement and both pinned since 2026-09-08 |
| M6 | Re-verify the sources of the DHI redistribution memo (`data/dhi-terms-2026-08-21.md`) and re-decide the terms statement in `SECURITY.md` (F12 e) | deliberate | Docker revises the cited pages often; the memo says it holds for a few months, and the DSSA-versus-Apache tension is unresolved by any Docker document | A fork under different terms replaces the memo and the statement | 2026-11-21 |
| M7 | Review and merge upstream chart version bumps (`chart/<name>/chart.yaml`, the helm-datasource manager, Req 3.11) | deliberate | A chart release can change what the overlay's values mean; the upgrade e2e argues the rest | `automerge: true` on the helm rule | none |
| M8 | Review and merge grafana repackage bumps (the tarball, `refresh-grafana.sh`, ADR 0002) | deliberate | A repackage bump swaps a binary we did not build; the cross-origin checksum is agreement of origins, not a signature | Convert the definition to from-source, or automerge patch bumps of the repackage archetype | none |
| M9 | Approve Renovate majors on the Dependency Dashboard (Req 3.4) | deliberate | A major of anything is a review, not a bump | `dependencyDashboardApproval` off for a datasource | none |
| M10 | Fix-forward hand-bumps between upstream releases: a `go/bump@v2` step in a definition's fetch phase with a `# renovate:` marker and a LOG entry naming the version at which it is dropped (Req 6.5) | deliberate | The fix lane cannot wait for the next upstream release when a finding is KEV-listed or over its ceiling; the floor stays tracked | none: it is the fix treatment | per entry: the LOG names the drop version |
| M11 | Feed a grafana build id (`REFRESH_GRAFANA_BUILD_ID`) when no public index carries it yet | deliberate | The refresh refuses by name rather than guessing; the pin is still the sidecar checksum, so a wrong id can only refuse or verify | The `.deb` route (ADR 0002) makes the id unnecessary | none |
| M12 | File an upstream issue from a draft under `triage/upstream/` and record its number (a transfer's tracker, Req 6.5) | deliberate | An outward-facing report carries the owner's name and measurements; it is reviewed like code before it is sent | none | none |
| M13 | Re-decide a compat variant at its `review_by` date (`chart/<name>/chart.yaml` `compat:`, Req 4.8) | deliberate | A shell shipped for a chart's sake is a cost with an owner and an expiry; validate fails the day after the date until a dated re-decision lands | Whether compat is allowed at all | valkey: 2026-11-24 |
| M14 | Revoke a digest: the entry in `triage/revocations.yaml`, the advisory, the replacement release or the version deletion (`docs/revocation-runbook.md`, Req 9.5) | deliberate | The record drives the mechanics; the decision that a digest must not be pulled is not one a rescan makes | none | none |
| M15 | Repository settings only the administrator holds: private vulnerability reporting on, the ruleset kept equal to its committed export, the weaker ruleset retired, packages public on first publish (Req 9.2, 9.8, 2.21) | deliberate | GitHub exposes these as settings, not as files; the daily rescan asserts each and fails by name when one drifts (Req 9.3, 9.9, 2.21) | none: the GitHub coupling is accepted (design Decision 10) | none |
| M16 | Merge a pull request over the one-review rule, the recorded bypass (SECURITY.md, Governance) | deliberate | With one maintainer a review nobody else can give is theatre; the required checks are the gate | A second maintainer in `CODEOWNERS` and `require_code_owner_review: true` in the committed ruleset | none |
| M17 | Dispatch a build (a release) or a rescan by hand | deliberate | A human asking for a release gets one: the dispatch path never runs the publish-on-change comparator | none | none |
| M18 | Decide what a supply-chain signal means (the rescan's `supply-chain` issue: a tag that moved, a rotated key, a compromise, a changed origin; Req 3.10) | deliberate | The rescan can measure a mismatch, not its cause; it fails daily and keeps the issue open until someone decides | none | none |
| M19 | Read the VEX portability block and decide whether a divergence matters (Req 9.12) | deliberate | Matcher semantics differ across scanners; a divergence is information about portability, not a defect in the statement, until someone says otherwise | `consumers.gating: true` in `catalogue-policy.yaml` fails a run on a divergence | none |
| M20 | Review chart image-pin tag bumps (a new image release reaching a chart; digest-only bumps automerge, Req 3.12) | deliberate | A tag move is a release reaching the deployed chart; the upgrade e2e runs, a human reads its result | `matchUpdateTypes` on the digest automerge rule | none |
| P1 | Track the cosign pin with Renovate: no manager matches a `cosign-release:` line, so M5's bumps are not offered (found 2026-09-08 while moving the install step; ADR 0003 promised the manager) | pending automation | A pin nothing bumps is a stale scanner's failure mode with a signing tool in its place | none: the intended mechanism is a `matchStrings` entry on the workflow manager plus a fixture, and M5 stays the completion step | none |
| P2 | Re-scope version-scoped VEX statements on a grafana bump: the product lint demands re-scoped statements (Req 6.20), and today a person re-stamps each one in a triage session (2026-09-03 for 13.1.5) | pending automation | The mechanical half is scriptable: a statement whose module version is unchanged by the bump is carried forward under the new product; only a changed module version needs a person | none: the intended mechanism is a postUpgradeTask beside `refresh-grafana.sh` | none |

**Automated since the register was decided** (F13's three automations and
the ones cluster C added), kept here so the list of human steps reads
against what it used to be: closing and reopening `cve` issues on evidence
(task 10.6, Req 6.52 to 6.57); tracking upstream chart versions (task 11.4,
Req 3.11); automerging digest-only chart image pins (task 11.4, Req 3.12);
re-verifying every definition's authenticity signal daily (task 11.3,
Req 3.10); discarding an unchanged nightly rebuild (task 9.2, Req 2.15);
asserting the repository's governance and its revocation record daily
(tasks 13.2, 13.3, Req 9.3, 9.7, 9.9).

## Pull requests (Req 7)

- One logical change per PR; definition bumps and chart changes do not mix
  unless a bump forces the chart change (say so).
- PR description references the requirement IDs it serves.
- Green checks required; patch and digest bumps of a from-source upstream and
  digest-only bumps of catalogue image pins under `chart/` automerge on green
  required checks, nothing else does (Req 3.5, 3.12); majors
  wait behind Dependency Dashboard approval (Req 3.4); every third-party
  release bump has aged three days before its PR exists (Req 3.7).
- Review checklist: pins intact, conventions above, README deviations updated,
  test evidence for behavior claims.
- A definition outside the active set is frozen: a pull request changing a
  file under its directory, or under a chart deploying no active definition,
  fails validation naming it (Req 1.16). Activate the definition in the same
  pull request (`active_set` in `catalogue-policy.yaml`) or leave it; deleting
  the directory passes, since a deletion changes nothing frozen.
- The ruleset that enforces the gates is code: `.github/rulesets/main_sec.json`
  (GitHub's export format) is compared daily against the live ruleset
  through anonymous reads, both directions (Req 9.8, 9.9); `CODEOWNERS` names
  the maintainer per lane (Req 9.10), and `require_code_owner_review` in the
  export is the switch a second maintainer flips.
