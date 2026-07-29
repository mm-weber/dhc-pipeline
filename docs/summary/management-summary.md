# dhc-pipeline — a hardened-image catalogue, built and left running

*A miniature Docker Hardened Images catalogue — six images, four Helm adaptations
and a CVE triage lane — built on the real DHI toolchain in three workdays, then
left operating unattended so its maintainer history accumulates on its own.*

## What it is

dhc-pipeline reproduces the working surface of a DHI engineering role end to end:
declarative image definitions, automated builds with supply-chain attestations,
upstream release tracking, Helm chart adaptation onto non-root images, Go
integration tests against real Kubernetes, and CVE triage recorded as portable,
machine-readable decisions.

Nothing is simulated. Images are authored in **native DHI syntax** and built by
Docker's own `dhi.io/build` BuildKit frontend — a three-hour spike established
that the frontend works outside Docker's infrastructure on the Community tier,
which retired the planned fallback of a bespoke YAML-to-Dockerfile renderer
(ADR 0001). Every other layer is equally standard: Renovate, Trivy + Grype,
OpenVEX/vexctl, cosign, Syft, Kyverno, Ginkgo v2 on kind.

> **[FIGURE 1 — the pipeline]**

## Delivered

| | |
|---|---|
| **6 images, 4 archetypes** | from-source · monorepo → 3 images · tarball repackage · C-source stateful |
| **4 chart adaptations** | upstream charts consumed unmodified; every deviation documented with its rationale |
| **6 CI workflows** | validate · build + release · chart gate · kind e2e · Renovate cron (≤6h) · daily rescan |
| **~2,600 lines of tested Go** | the kind e2e harness and the rescan reporter, both written test-first |
| **28 PRs, 109 commits** | against 8 EARS-notated requirements, 2 ADRs and a dated triage log |

Every published image carries a cosign keyless signature, an SPDX SBOM, SLSA
provenance and — where a triage decision exists — an OpenVEX attestation.
Kyverno gates rendered manifests on digest pinning, allowed registries and
non-root execution; the e2e suite then asserts the *live* pods run as UID 65532
with a read-only root filesystem and all capabilities dropped, and probes them
functionally: cert-manager issues a Certificate, Grafana answers health, Valkey
serves SET/GET.

## The part that isn't scaffolding

**Archetype decides what you are even allowed to do about a CVE.** An image built
from source can patch a transitive dependency ahead of upstream; a tarball
repackage inherits whatever upstream compiled. That asymmetry — not severity —
drove every triage decision in this catalogue. Keeping Grafana as a repackage was
therefore deliberate (ADR 0002): it is the worked example of *you cannot fix this
yourself, so you triage it instead*, which is what the entire VEX half of the
pipeline exists to handle.

**Suppression is split by question, not by convenience.** VEX answers *does this
apply?* — evidence-backed, attested to the image, no expiry. `accepted-risk/`
answers *what are we doing about it?* — internal, never attested, and it expires,
under a machine-enforced 90-day ceiling. Writing "low risk" into a VEX is
VEX-washing: it launders a business decision into a machine-readable claim of
technical inapplicability that every downstream consumer then inherits.

> **[FIGURE 2 — the triage decision model]**

## What running it for real turned up

- **An upstream artifact that moves.** Grafana rewrites its `/oss/release/`
  tarballs about twenty hours after a release — routine automation, not a
  one-off. A digest pinned on release day silently stops matching. It was
  provable only because our own build record from five days earlier showed the
  original pin verifying on both architectures. Fixed by pinning the build-scoped
  artifact, which has not moved since release day, and by adding a CI check that
  fetches every pinned architecture; report to upstream drafted.
- **An invisible class of security release.** Grafana ships out-of-band fixes as
  semver build metadata (`13.0.1+security-01`), which semver ranks *below* the
  plain release — the tracker would have reported us up to date straight through a
  security release, on the one image carrying every open CVE.
- **Bumping is not monotonic.** The 13.0.4 → 13.1.1 fix bump cleared three stdlib
  findings from the main binary and introduced four new ones inside a bundled
  plugin. Recorded as such, because a version bump swaps a dependency graph rather
  than shrinking it.

**Status: operating.** Renovate opens bump PRs on a six-hour cron, the daily
rescan has filed eleven EPSS/KEV-enriched CVE issues without supervision, and the
gate stays red on the one CRITICAL where the honest answer is still *we don't
know yet* — which is the correct pressure.

---

<!-- Everything below is production notes for the two figures, not page copy.
     Delete before exporting to a one-page PDF. -->

## Figure briefs

### Figure 1 — the pipeline

Left-to-right flow, sized for a half-page-wide band.

```
image.yaml (native DHI) ──► dhi.io/build frontend ──┬─► PR path:   amd64 build ─► Trivy (+VEX, +accepted-risk)
                                                    │              ─► Grype on CRITICAL ─► kind e2e ─► chart/Kyverno gate
                                                    └─► main path: multi-arch build ─► GHCR (private)
                                                                   ─► cosign · SBOM · provenance · VEX attestation
        ▲                                                                                          │
        └────── Renovate ≤6h (bump PR + checksum refresh) ◄── daily rescan (CVE issue, EPSS/KEV) ◄──┘
```

**Caption:** "One definition file; two paths. Everything published is signed,
inventoried and attested — and two crons keep pushing new work back into the
front of the loop."

### Figure 2 — the triage decision model

Funnel or 2×2. A finding enters at the top and leaves through one of five outlets.

`not_affected` sits **outside** the treatment set — it is the claim there was
never any risk here to treat (→ OpenVEX, attested to the image, no expiry).

Below it, the four real treatments in order of strength:

| | Treatment | Produces |
|---|---|---|
| 1 | **avoid** | definition change — the vulnerable component stops shipping |
| 2 | **mitigate** | version-bump or rebuild PR |
| 3 | **transfer** | `accepted-risk/` entry, upstream owns the fix |
| 4 | **accept** | `accepted-risk/` entry, real and reachable, shipping anyway |

3 and 4 are time-boxed: owner, a stated reason the stronger treatments were
unavailable, expiry ≤ 90 days, and **never attested**.

**Caption:** "Two different questions. VEX says *does this apply to the
artifact?*; accepted-risk says *what are we doing about our exposure?*
Conflating them is VEX-washing — so the pipeline keeps them in separate files
with separate lifetimes."
