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
assumption. Encode both outcomes as requirements up front (Req 1.7/1.8's
WHERE/IF pair) and a spike cannot fail — either result is a decision.

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
