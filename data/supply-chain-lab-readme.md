# Container Supply-Chain Lab

A hands-on taste of four things, on a tiny Go HTTP service, ending with Kyverno
policies that *enforce* what you built. Runs on one machine in ~30–45 min.

1. **Image layering** — see what an image is actually made of
2. **Distroless** — shrink the image and the CVE count
3. **Multi-arch** — one tag, two architectures
4. **Reproducible builds** — same source in, bit-identical artifact out

Then the payoff: **Helm + Kyverno** — package the image and write policy that
rejects anything that *isn't* pinned by digest, from an allowed registry,
non-root, and (optionally) signed.

## Prerequisites

- Docker with Buildx (ships with modern Docker Engine / Docker Desktop)
- `go` (1.23+)
- Optional but recommended: [`dive`](https://github.com/wagoodman/dive),
  [`trivy`](https://github.com/aquasecurity/trivy), `helm`,
  [`kyverno` CLI](https://kyverno.io/docs/kyverno-cli/), `jq`, `cosign`

Every stage has a `make` target. Run `make help` to list them.

---

## Stage 0 — Image layering

**Goal:** internalize that an image is a *stack of read-only filesystem diffs*,
one per Dockerfile instruction, and see why images get fat.

```bash
make naive          # builds the deliberately-bad Dockerfile.naive
```

**Look at this:**

```bash
docker history hardened-app:naive     # every line is a LAYER; note the sizes
dive hardened-app:naive               # arrow-key through layers; watch the tree
```

In `dive`, walk down the layers on the left and watch the filesystem on the
right change. Notice:

- The `golang:1.23` base is ~800 MB of toolchain you do **not** need at runtime.
- `COPY app/ .` then `go build` bakes source *and* build cache into layers.
- Press `Tab` / follow the "wasted space" figure — `dive` shows bytes that are
  added in one layer and shadowed later. That is the additive-only rule in the
  flesh: **deleting a file in a later layer does not remove its bytes**, it just
  hides them.

**The lesson that pays off forever:** order instructions cheapest-cache-miss
last. `COPY go.mod && go mod download` **before** `COPY app/` means a source
edit doesn't re-download dependencies. Look at the main `Dockerfile` — that's
exactly why deps are a separate, earlier layer.

---

## Stage 1 — Distroless

**Goal:** move to a runtime image with no shell, no package manager, no libc
userland — only your static binary, CA certs, and a nonroot user.

```bash
make build          # multi-stage build -> gcr.io/distroless/static
make scan           # trivy CVE counts, naive vs distroless (if trivy installed)
docker images hardened-app     # compare sizes
```

**Look at this:** the distroless image is typically **~10 MB vs ~900 MB**, and
the CVE count collapses (a distroless/static image often scans clean because
there's no OS package layer to have CVEs). Try to get a shell:

```bash
docker run --rm -it hardened-app:distroless sh    # fails — there IS no shell
```

That "failure" *is* the security property: an attacker who lands RCE has no
`sh`, no `apt`, no `curl` to pivot with. The two-stage build is what makes this
possible — the fat toolchain lives only in the `build` stage and never ships.

Why it works: `CGO_ENABLED=0` produces a fully static binary, so it needs no
dynamic linker — hence `distroless/static` (the smallest distroless) is enough.

---

## Stage 2 — Multi-arch

**Goal:** publish one image tag that serves both `linux/amd64` and
`linux/arm64`, selected automatically by the puller's architecture.

You need somewhere to push a manifest list. Easiest is GHCR:

```bash
echo $GH_PAT | docker login ghcr.io -u YOUR_GH_USERNAME --password-stdin
make multiarch REGISTRY=ghcr.io/YOUR_GH_USERNAME
```

**Look at this:**

```bash
docker buildx imagetools inspect ghcr.io/YOUR_GH_USERNAME/hardened-app:0.1.0
```

You'll see an **OCI image index** (a "manifest list") with two child manifests,
one per platform. That index is the multi-arch magic: `docker pull` on an arm64
Mac and on an amd64 server resolve the *same tag* to *different* image digests.

How the Dockerfile does it cheaply: the build stage is
`FROM --platform=$BUILDPLATFORM golang ...` so it runs on your native arch and
Go **cross-compiles** to `$TARGETARCH`. No QEMU emulation of the compiler —
just `GOOS`/`GOARCH`. (Emulating a C toolchain across arches is slow; Go
sidesteps it.)

No registry handy? Build without pushing to prove it compiles for both:

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t hardened-app:multi .
```

---

## Stage 3 — Reproducible builds

**Goal:** same source → **bit-identical** output, so a third party can rebuild
and verify you shipped what the source says. The enemy is embedded
non-determinism: timestamps, build IDs, absolute paths, file ordering.

Start with the crisp version — the binary:

```bash
make reproduce-bin
```

**Look at this:** the two `sha256sum` lines are **identical**. The flags that
make that true (all in the Dockerfile too):

- `-trimpath` — removes `/home/you/...` build paths from the binary
- `-ldflags="-buildid="` — strips Go's random per-build ID
- `CGO_ENABLED=0` — no C toolchain nondeterminism

Now the image level. The remaining source of drift is layer **timestamps**.
BuildKit can normalize them:

```bash
make reproduce-img          # builds twice with SOURCE_DATE_EPOCH + rewrite-timestamp
```

The two `containerimage.config.digest` values should match. The knobs:

- `SOURCE_DATE_EPOCH=0` — a fixed "build time"
- `--output type=image,rewrite-timestamp=true` — BuildKit rewrites layer mtimes
- `--provenance=false` — provenance attestations embed build-time data; disable
  for a pure reproducibility comparison
- **and pin the base by digest** — `FROM gcr.io/distroless/static-debian12@sha256:...`
  so "the base" can't change between your two builds (this is literally the
  argo-workflows #15733 bug: an unpinned distroless base silently shifted
  Debian releases and broke a release)

**The lesson:** reproducibility isn't one flag, it's *removing every source of
entropy* — paths, IDs, timestamps, and floating base images.

---

## Stage 4 — Helm

**Goal:** ship the image the right way — pinned by **digest**, non-root.

```bash
make chart          # renders chart/ to stdout
```

Look at `chart/templates/_helpers.tpl`: when `image.digest` is set it renders
`repo@sha256:...` and the tag is ignored. Put the digest from Stage 2 into
`chart/values.yaml` and re-render — the Deployment now references an immutable
image. Digest-pinning is the single highest-leverage supply-chain habit: a tag
is a mutable pointer, a digest is content.

---

## Stage 5 — Kyverno (the payoff)

**Goal:** be the policy author, not just the image builder. Enforce the exact
properties you just produced. No cluster needed — the Kyverno CLI evaluates
policies against rendered manifests.

```bash
make policy-test    # helm template | kyverno apply policies/ --resource -
```

The four policies in `policies/`:

- `require-image-digest.yaml` — rejects tag-based images (`*@sha256:*` required)
- `restrict-registries.yaml` — only `ghcr.io/*`
- `require-nonroot.yaml` — `runAsNonRoot: true`
- `verify-images.yaml` — **keyless cosign** signature from your GitHub Actions
  workflow (advanced; needs the image actually signed — see below)

**Prove it both ways.** With the digest set in `values.yaml`, `make policy-test`
passes. Now blank the digest (falls back to a tag) and re-run — the digest
policy **fails**. That pass→fail flip is the whole point: you can see policy
doing its job.

### Optional: actually sign the image (keyless cosign)

In a GitHub Actions job with `permissions: id-token: write`, after building:

```bash
cosign sign --yes ghcr.io/YOUR_GH_USERNAME/hardened-app@sha256:<digest>
```

That produces a signature tied to your workflow identity via Fulcio/Rekor — no
private key to manage. `verify-images.yaml` is what checks it at admission time.

---

## What you can show for this

One repo that demonstrates, end to end: layering literacy (dive output),
distroless migration (size + CVE delta), a multi-arch manifest list, a
reproducible-build proof (matching digests), digest-pinned Helm packaging, and
Kyverno policy authorship enforcing all of it — with optional keyless signing.
That is the entire skill list, on your terms, nothing blocked on a maintainer.

Replace `YOUR_GH_USERNAME` throughout, push it public, and it doubles as a
portfolio artifact.
