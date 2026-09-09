# Concepts

Working notes from building this catalogue — the ideas behind the tools, in
the order they came up. Running example: the DHI catalog's
[netdata-agent-sd definition](https://github.com/docker-hardened-images/catalog/blob/main/image/netdata-agent-sd/alpine-3.23/0.yaml)
(local copy under `temp/catalog/`, gitignored), built during the ADR 0001 spike.

## Spikes

A *spike* (from Extreme Programming) is a timeboxed, throwaway experiment that
answers one question before the architecture commits to an assumption. Four
properties: it answers a **question** (not builds a feature); it's
**timeboxed** (the answer has a price cap); its output is **knowledge, not
code** (the code is disposable — ours lives in gitignored `temp/`, the
knowledge in ADR 0001); it runs **before the risky decision**, on the riskiest
assumption. Encode both outcomes as requirements up front (Req 1.7 and the
since-retired 1.8 were that WHERE/IF pair; ADR 0001 records the outcome) and
a spike cannot fail — either result is a decision.

## BuildKit: frontends, LLB, and the content-addressed DAG

```
definition file ─► FRONTEND (compiler) ─► LLB (IR) ─► executor ─► OCI image
```

- **IR**: like LLVM IR or JVM bytecode — N source formats and M executors
  meet in one intermediate language. BuildKit applies compiler architecture
  to builds.
- **LLB** is that IR: a small vocabulary of primitives — *SourceOp* (fetch
  git ref / URL / image), *ExecOp* (run process in filesystem state with
  mounts), *FileOp* (mkdir/copy/symlink/chown).
- **DAG**: ops form a directed acyclic graph; edges are data dependencies.
  Branches without a path between them run in parallel (the interleaved
  build-log lines). 90 "steps" in 104s with ~50s in three nodes = a wide
  graph, not a script.
- **Content-addressed**: a node's identity is the hash of its definition plus
  its inputs' hashes (Merkle structure — same idea as git, Bazel, Nix).
  Consequences: caching is a provable lookup, not a heuristic (`CACHED` hits
  across *different* definition files when subgraphs hash the same);
  invalidation recomputes exactly the downstream cone; and the model itself
  pressures toward digest-pinning — a hash over "whatever `latest` is" would
  mean nothing.
- A **frontend** is the compiler, and it ships *as a container image*. The
  first line `# syntax=dhi.io/build:2-alpine3.23` is a shebang with a version
  pin: BuildKit pulls that image and runs it — sandboxed, **no network** —
  to translate YAML into LLB. The Dockerfile is not special; its parser
  (`docker/dockerfile:1`) is just another frontend.
- **Everything runs locally.** Docker's servers act purely as a *registry*
  (compiler image, builder images, packages) — never as a build service.
  Your BuildKit runs the compiler, fetches sources with your credentials,
  executes stages in local sandboxes, assembles layers + attestations.

## Anatomy of a DHI definition

- `image` / `variant` / `tags` — identity; tags form a semver aliasing fan
  (`0-`, `0.2-`, `0.2.10-alpine3.23`) so consumers pick update granularity.
- `vars` — **the bump surface**: VERSION, semver splits, COMMIT_SHA, builder
  reference. Version state in named variables is what makes definitions
  mechanically updatable (Renovate rewrites exactly this block).
- `contents` (top level) — the *runtime* image's package manifest:
  repositories in priority order (hardened `dhi.io/apk` first, public Alpine
  as fallback), the DHI signing key, and a deliberately tiny package list.
- `contents.builds[]` — build stages: declarative multi-stage builds.
  `uses:` pins a `-dev` catalog image by digest as the toolchain;
  `files:` acquires source (`git+https://…#tag` **plus commit checksum** —
  the tag is readable, the hash is the trust anchor); `caches:` are BuildKit
  cache mounts (module cache survives rebuilds).
- `pipeline` — ordered steps inside the stage; see Actions below.
- `outputs` — the **only bridge** from build stage to runtime image
  (binary + SBOM, explicit uid/gid). Toolchain, sources, caches die with the
  stage. Multi-stage as an enforced contract, not a convention.
- `accounts` / `os-release` / `paths` / `entrypoint` — runtime config as
  data. `os-release` matters: scanners read it to select the advisory DB.

### The variant taxonomy

One image family, several capability tiers per version:
**runtime** (deploy this: binary + deps + certs + nonroot 65532, no shell/pm/
compiler) · **`-dev`** (build with this: toolchain + shell, root, never
deployed — it's the `uses:` stage) · **`-compat`** (runtime + minimal shell
userland, for charts/entrypoints that need one — choosing it is a documented
decision, Req 4.5). Also `-fips`, `-helm`, `-source`. Rule: deploy the least
capable variant that works; write down why when you can't.

## Actions (`uses:`) are compile-time macros, not GitHub Actions

`uses: go/bump@v2` borrows GitHub Actions' *syntax* because everyone reads it
fluently — but the execution model differs completely. A GH Action fetches
third-party code onto a CI VM at run time. A DHI action is a **named,
versioned template inside the frontend**, macro-expanded at compile time into
LLB nodes that run in the sandboxed stage (closer to a Rust/Lisp macro than a
library call). `runs:` is the escape hatch — inline shell for what the
"standard library" doesn't cover (e.g. running upstream's tests).

**Why `@v2` and not a checksum**: nothing is fetched, so there is nothing to
checksum. The action's implementation hash *is* the frontend image digest;
`@vN` is interface versioning (which behavior contract), not supply-chain
pinning. Shared logic used by hundreds of definitions gets change control:
upgrading an action is a reviewable one-line diff per definition.
The residual gap is the syntax line itself — a floating tag in the catalog.
BuildKit accepts digests there, so **this repo's convention is to digest-pin
the `# syntax=` line too** (provenance records the resolved digest either
way; we pin it up front).

**Why `go/bump` exists** — CVE surgery between upstream releases. Upstream's
tag pins vulnerable transitive modules (x/crypto, x/net). Forking upstream is
maintenance hell; waiting kills remediation SLAs. So the definition overlays
dependency updates at build time: the shipped artifact is "upstream v0.2.10
with patched deps," declared in reviewable YAML, reflected in the SBOM.
Two complementary layers of currency in this repo: **Renovate** rewrites *our
definition pins* via PRs (repo level, tracking releases); **go/bump** patches
*upstream's dependency graph* inside the build (build level, patching between
releases).

**Why an action and not a shell step** — verified the hard way, 2026-07-26.
Patching a dependency with `runs: go get …` looks equivalent and is not: the
pipeline sandbox has **no egress**, so it fails outright.

```
+ go get google.golang.org/grpc@v1.82.1
go: cel.dev/expr@v0.25.1: Get "https://proxy.golang.org/…":
   dial tcp: lookup proxy.golang.org … network is unreachable
```

That is the hardening property, not an obstacle to route around: a build step
cannot reach out and pull something the definition never declared, so what
lands in the image is exactly what was reviewed. Everything fetched — sources,
packages, the module graph — is declared up front and resolved in the
frontend's **fetch** phase, the only phase with network. Dependency surgery has
to happen there, which is what the bump action is for. `runs:` is the escape
hatch for *computation*, never for *acquisition*. (See `triage/LOG.md`,
2026-07-26, GHSA-hrxh-6v49-42gf.)

## The trust chain: checksum → purl → SBOM → provenance → signature

- **Checksums are verified facts** — enforced at fetch time (mismatch fails
  the build), but the verification is an *event* that leaves no trace in the
  artifact by itself.
- **purl** (`pkg:golang/github.com/netdata/sd@0.2.10`) is a cross-ecosystem
  *coordinate* — the join key between SBOM entries and advisory databases.
  It is **not** mechanically linked to the source checksum: the checksum is
  integrity (machine-verified), the purl is identity (an authored claim).
  Consistency between them is editorial — `vars` feeds both, one bump PR
  moves both, review catches drift.
- **SBOMs are signed claims** about contents, bound to the image digest as an
  attestation subject. Accountable, but still assertions.
- **Provenance is what connects them**: an in-toto attestation (SLSA
  predicate) whose subject is the output digest and whose body records the
  builder, the invocation, and the **materials** — every input with its
  *resolved* digest (the frontend tag as resolved, the builder image, the git
  commit). It carries the ephemeral fetch-time facts forward into a durable
  signed record. That enables: **audit** (SBOM claims vs provenance
  materials), **identity** (who signed), and **reproduction** — rebuild from
  the recorded inputs and compare digests. Reproducibility is what upgrades
  provenance from trusted claim to recomputable fact.
- **SLSA levels grade the bridge**: exists ≈ L1 · signed by the build
  platform ≈ L2 · non-forgeable builder identity (hardened CI + OIDC keyless
  signing) ≈ L3. A local `--load` build carries unsigned self-attested
  provenance (L1-ish); this repo's CI cosigns what it publishes (L2-ish);
  full L3 hermeticity is explicitly out of scope (see design doc, Non-Goals).

Verification, when images are in a registry: `docker buildx imagetools
inspect <ref>` (see the attestation manifests), `cosign verify-attestation
--type slsaprovenance <ref>`, `docker scout attest list <ref>`.

## The builder contract per archetype

Req 1.17, the seam design Decision 11 declared and did not build: what the
build backend takes in and what it must hand out, so that everything after
it (scan gate, rescan, publish-on-change, VEX compilation, charts, status)
depends on the outputs alone and a fork can swap the backend without
touching a downstream plane. Today the backend is the `dhi.io/build`
frontend for both archetypes; the declared alternative is apko plus Wolfi
through the same contract.

**Input: one definition directory.** `image/<name>/` holds `image.yaml` in
the backend's native syntax and nothing the build reads from elsewhere.
Every plane that touches an image reads that directory: the build compiles
it, the frontend being the authoritative validator; Renovate rewrites its
`vars:` block and source url and the refresh tooling regenerates the derived
fields; the lints read its pins and its `# authenticity:` marker; the
active set names it by directory (Req 1.13). A variant that must be built
(`-compat`) is one more directory under the same contract, byte-equal in
source to its runtime sibling plus a package, publishing to the sibling's
repository as a tag suffix.

**Outputs, identical for every archetype.**

1. *An image pushed by digest* to the declared registry namespace: an index
   with one platform manifest per declared platform, pushed by digest only
   and tagged last, after the release-time scan, the signature and the
   attestations exist (Req 2.7 to 2.9). BuildKit provenance is attached at
   the push, as attestation manifests inside the index (Req 2.2).
2. *Per-platform SBOM material carrying package pull checksums*: for every
   platform manifest, an SPDX and a CycloneDX SBOM generated from the pushed
   digest and attested to it, the CycloneDX one carrying each apk package's
   pull checksum (syft's `pullChecksum` property, which the SPDX output
   drops). That checksum is what makes the resolved package set a fact
   rather than a name list: the publish-on-change comparison canonicalises
   type, name, version and checksum per platform manifest (Req 1.9, 2.15),
   so a package republished under an unchanged version still moves the set.

**What differs per archetype is the input's source stanza, and only that.**

| Archetype | Source stanza | Authenticity class | Refresh on a bump |
|---|---|---|---|
| compile-from-source (hardened-app, cert-manager, valkey) | `files: url: git+https://…#<tag>` with the commit `checksum:` beside it, built in a build stage whose toolchain is a digest-pinned `-dev` image (`uses:`, the Go ones) or toolchain packages from the pinned repositories (valkey) | `signed-tag` or `signed-commit`, GitHub's verification statement | `refresh-definition.sh` regenerates the checksum and every version-derived field |
| tarball-repackage (grafana) | `files: url: https://<vendor>/…<version>…tar.gz` with per-architecture sha256 pins in `vars:`, verified by an in-pipeline `sha256sum -c` step | `cross-origin-checksum`, the publisher's version statement and the object store's sidecar agreeing | `refresh-grafana.sh` re-pins both checksums from two origins |

**Downstream reads outputs only, already true by construction.** The scan
gate and the rescan scan the pushed digest's platform manifests; the
comparator reads the CycloneDX attestations; the VEX compiler stamps the
digest and its platform digests; the charts pin the digest; the admission
proof verifies the signature and attestations; the status planes read what
is attested. None of them reads a definition to learn about an image. That
is the whole seam: a backend that produces these two outputs from that one
input is a drop-in, and the trust-boundary table below names the declared
alternative per row.

## Trust boundary: who owns what, and where the seams are

Every component the catalogue depends on, with its owner class (Req 9.15):
**substrate-inherited** (Docker Hardened Images), **upstream-inherited** with
the authenticity class or pin that stands behind it, or **own**. The last
column is the seam the framing addendum declared and deliberately did not
build (design Decision 11): a fork changes the row, the operating model
stays. `SECURITY.md` links here; the per-definition classes are also stated
there.

| Component | Owner class | Authenticity or pin | Declared seam alternative |
|---|---|---|---|
| Build frontend `dhi.io/build` | substrate-inherited | digest-pinned `# syntax=` line; docker datasource, bumps reviewed by hand | apko plus Wolfi, the documented backend a fork targets; [the builder contract per archetype](#the-builder-contract-per-archetype) (Req 1.17: definition directory in, image by digest plus SBOM material out) is the seam |
| Builder images `dhi.io/golang:*-dev` | substrate-inherited | digest-pinned `uses:`; reviewed by hand | Wolfi toolchain images through [the same contract](#the-builder-contract-per-archetype) |
| Package repositories `dhi.io/apk/<distro>/<release>/main` and their keyring | substrate-inherited | `/main` lines only, enforced by `lint-pins.sh`; packages float by design (Req 1.9), the resolved set is recorded per digest in the attested SBOMs | Wolfi apk repositories; the `dhi.io` login the build step needs is an adoption constraint, stated, not hidden |
| Runtime base layers (baselayout, certificates, libc) | substrate-inherited | from the repositories above; rebuilt daily, published on change (Req 2.14 to 2.16) | comes with the backend |
| cert-manager sources (controller, webhook, cainjector) | upstream-inherited, `signed-tag` | GitHub's verification statement for the annotated tag, at bump time and daily | none needed; the class is per definition |
| valkey sources (runtime and compat) | upstream-inherited, `signed-commit` | GitHub's verification statement for the commit the tag points at, at bump time and daily | none needed |
| hardened-app source (the owner's own upstream) | upstream-inherited, `signed-commit` | the same, since v0.1.1 | none needed |
| grafana tarball | upstream-inherited, `cross-origin-checksum` | grafana.com versions API and dl.grafana.com sidecars agree per architecture, at bump time, PR time and daily; no upstream signature exists | the `.deb` route for a cryptographic anchor (ADR 0002); the definition ships as a reference behind the active-set switch |
| Upstream charts (jetstack cert-manager, grafana community, valkey project) | upstream-inherited, none declared | exact version pinned in `chart.yaml`, tracked by the helm datasource, never automerged; templates never edited | a fork's chart source; the overlay is the only delta |
| Definitions, overlays, Kyverno policies, triage records (VEX, exceptions, LOG), scripts, workflows, the rescan tool, tests | own | git history under the committed ruleset; every change a pull request | the operating model is the product; forks change declared values in `catalogue-policy.yaml` |
| Trivy (authoritative scanner and VEX consumer) | upstream-inherited, exact version plus recorded sha256 (Req 7.5) | the PR gate and the rescan | Grype as the measured second consumer and the daily consumer smoke test as migration insurance (task 13.4); a fork flips the authoritative consumer in the policy file |
| Grype, syft, govulncheck, kind, kyverno, helm, ct, crane, cosign, renovate | upstream-inherited, exact version plus recorded sha256, Go sumdb or npm integrity (Req 7.5, 7.6) | tool pins with Renovate managers; the checksum half is human | each is a rendering of a declared value: cosign to notation and Kyverno to policy-controller are declared renderings, not built |
| Sigstore public-good instance (Fulcio, Rekor) | upstream-inherited, service | identities pinned in the verification policy; keyless signing | a private Sigstore or a key with notation; the transparency-log disclosure fact changes with it |
| GitHub: Actions (builds, OIDC identities), GHCR (registry), Issues (lifecycle, status), Pages (the catalogue page, an artifact deployment), rulesets (governance) | upstream-inherited, platform coupling accepted deliberately | owner, repository and registry names are declared values (Req 1.13 to 1.19); the OIDC issuer is pinned | another forge with OIDC, a registry and an issue tracker; the coupling is listed, not abstracted |
