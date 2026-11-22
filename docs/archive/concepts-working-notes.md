# Concepts: the working notes

> **Archived 2026-11-21** (documentation track, plan 3.1). These sections were the working-notes half of `docs/concepts.md`: the ideas behind the tools, written down while building the catalogue. They are kept as written and are not maintained; the reference half (the definition anatomy, the trust chain, the builder contract, the trust boundary) stayed in `docs/concepts.md` and is now the user manual's [Part VI: Reference](../user-manual.md#part-vi-reference) (plan 4.2). Their history before this date is `git log -- docs/concepts.md`.

Running example: the DHI catalog's
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
