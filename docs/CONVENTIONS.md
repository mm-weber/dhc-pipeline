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

## Pinning (Req 1.2, 1.3, 1.6)

- Every base image reference carries `@sha256:<digest>`. No exceptions.
- Every upstream source is `git+https://...#<ref>` plus a `checksum:` line.
- Every upstream chart is pinned to an exact version in `chart/<name>/chart.yaml`.
- Floating tags (`latest`, bare majors like `:1`, digestless tags) fail CI.
- Humans never bump pins by hand when Renovate is able to; hand-bumps are reserved
  for CVE fix-forwards (Req 6.5) and say so in the PR description.

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
  `checksum:` line — instead pin each arch's SHA-256 in `vars:`
  (`*_SHA256_AMD64` / `*_SHA256_ARM64`) and verify it in a pipeline
  `sha256sum -c` step. That pinned-and-verified hash is the content pin
  (Req 1.3) for this archetype.
- Version state lives in `vars:` with the catalog's names (`VERSION`,
  `SEMVER_*`, `COMMIT_SHA`) — that block is the Renovate bump surface.
- Runtime `accounts:` declare `nonroot` 65532 with `run-as` (Req 1.4).
- Alpine variants only for now; the deb path is unverified (ADR 0001).
- The linter is the fast gate; the **frontend itself is the authoritative
  validator** — it compiles every definition on each PR build (Req 1.5).

## Runtime accounts (Req 1.4)

- Runtime images run as UID/GID **65532** (`nonroot`), declared in the definition's
  `accounts:` block. Only `-dev` variants run as root, and only at build time.

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

## Pull requests (Req 7)

- One logical change per PR; definition bumps and chart changes do not mix
  unless a bump forces the chart change (say so).
- PR description references the requirement IDs it serves.
- Green checks required; digest-only patch bumps automerge (Req 3.5); majors
  wait behind Dependency Dashboard approval (Req 3.4).
- Review checklist: pins intact, conventions above, README deviations updated,
  test evidence for behavior claims.
