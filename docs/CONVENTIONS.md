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
- Every upstream chart is pinned to an exact version in `chart/<name>/chart.yaml`
  (hand-pinned; nothing tracks chart versions yet). The **image** pins in each
  chart's values are Renovate-tracked with tag + digest (task 8.7), so a
  definition bump reaches the deployed chart and a same-tag rebuild moves the
  digest; a chart-pin bump PR runs the e2e upgrade path (Req 5.6).
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

## Runtime accounts (Req 1.4)

- Runtime images run as UID/GID **65532** (`nonroot`), declared in the definition's
  `accounts:` block. Only `-dev` variants run as root, and only at build time.

## Upstream tracking (Req 3, ADR 0002)

Renovate is driven entirely by custom regex managers over `image/*/image.yaml`
— every built-in manager is disabled, so nothing opens a surprise PR. There is
**one manager per archetype**, and adding an image means checking its source
shape is covered:

| Archetype | Source shape | Datasource | postUpgradeTask |
|---|---|---|---|
| compile-from-source | `url: git+https://…#vX.Y.Z` | `github-tags` | `refresh-definition.sh` |
| tarball-repackage | `url: https://<vendor>/…-X.Y.Z.linux-…` | `github-releases` | `refresh-grafana.sh` |
| build layer | `syntax=` / `uses:` / `GOLANG_REFERENCE:` | `docker` | none (reviewed by hand) |

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
- Repackage bumps are **never automerged** — they swap a binary we did not
  build. From-source patch/digest bumps automerge on green CI (Req 3.5).
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

## Policy gate (Req 4.6)

Rendered manifests of every chart are evaluated by the Kyverno policies in
`policies/`: images referenced by digest, only from `ghcr.io/mm-weber/dhc`,
workloads non-root. Policy fixtures live in `policies/tests/` and run via
`kyverno test` in CI (no kyverno binary in the devcontainer — Req 8.2).

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
does not apply, is attested to the image, and never expires;
`triage/accepted-risk/` records that it *does* apply and we ship anyway for a
bounded time, stays internal, and **must never be written as a VEX** (Req 6.8) —
that would launder a business decision into a machine-readable claim of technical
inapplicability, and every consumer would inherit it. Exceptions carry a treatment
(`accept` / `transfer`), an owner, the reason avoidance and remediation were
unavailable, a `decided_at`, and an `expired_at` no later than that decision date plus the policy file's largest ceiling (`catalogue-policy.yaml` `triage.ceilings`; the gate and the rescan then hold each entry to the tier its finding earns: the KEV ceiling when CISA lists it, else its severity's ceiling, Req 6.50, 6.51);
`scripts/lint-accepted-risk.sh` enforces that and rejects any Trivy ignore file
living anywhere else (Req 6.11, 6.12).

A daily `rescan.yml` cron re-scans the published images for CVEs that land after
merge; new HIGH/CRITICAL findings (not already tracked, VEX-aware) are enriched
with EPSS + CISA KEV and filed as one issue per CVE by the unit-tested
`triage/rescan/` Go tool. See `triage/README.md`.

## Pull requests (Req 7)

- One logical change per PR; definition bumps and chart changes do not mix
  unless a bump forces the chart change (say so).
- PR description references the requirement IDs it serves.
- Green checks required; digest-only patch bumps automerge (Req 3.5); majors
  wait behind Dependency Dashboard approval (Req 3.4).
- Review checklist: pins intact, conventions above, README deviations updated,
  test evidence for behavior claims.
