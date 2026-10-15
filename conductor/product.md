# Product vision

## Product overview

**Name:** dhc-pipeline

**Tagline:** A miniature hardened-image catalogue that runs the whole job of a Docker Hardened Images engineer, for real, unattended.

**Description:**
A small catalogue of hardened container images (seven definitions in the reference set: a Go service, the three cert-manager images, grafana, valkey and its compat variant) built with the Docker Hardened Images build layer and packages, adapted upstream Helm charts, Go integration tests on real Kubernetes, automated upstream tracking, and CVE triage recorded as portable VEX. It is a skill-building project that mirrors the responsibilities of a DHI engineering role and then keeps operating so that genuine maintainer history accumulates. It is not affiliated with Docker, Inc.

## Problem statement

### The problem

Hardened-image work is judged on operating discipline, not on a demo: pinning every input, tracking upstreams, proving hardening on live clusters, deciding every finding and publishing the decision, and keeping a promise consumers can verify. None of that can be learned from reading; it needs a catalogue that is really built, scanned, published and maintained over months.

### Current solutions

Vendor catalogues (Docker Hardened Images, Chainguard, Bitnami) do this at scale with internal build systems. Public examples show the artifacts, rarely the operating model and never the triage history.

### Why they fall short

A candidate cannot practise on a vendor's pipeline. A toy pipeline that never runs unattended never exercises the failure shapes (a rate-limited API, a moved tag, an expired exception) that make up the job.

## Target users

### Primary users

The project owner, as catalogue maintainer and job candidate.

- **Who:** one maintainer, learning the domain while operating it
- **Goals:** every decision explainable and defensible in an interview; the catalogue green and honest without daily attention
- **Pain points:** dense spec language; mechanisms that were only ever unit-tested; a single person holding every switch
- **Technical proficiency:** strong in infrastructure and automation, new to hardened-image catalogue concepts

### Secondary users

Reviewers of the repository: interviewers and anyone evaluating maintainer craft.

- **Who:** readers who open the repository cold
- **Goals:** see a real operating model with its history, not a tutorial
- **Relationship to primary:** they read what the primary user operated

## Core value proposition

### Key benefits

1. A transparency promise with teeth: every published digest signed by a pinned identity, every known HIGH or CRITICAL finding carrying a published machine-readable status, time-to-decision and time-to-fix measured and published.
2. Every rule enforced by a named check that fails by name, with its criterion number, and a live-evidence ledger that says when each mechanism last ran for real.
3. Real tools only (BuildKit and the DHI frontend, Renovate, Ginkgo and kind, Trivy, Grype, Syft, cosign, Kyverno, OpenVEX), custom code only as thin glue.

### Differentiators

- The spec is executable discipline: requirements in EARS, each with a mechanism and a ledger row.
- The catalogue keeps operating unattended, so its history is genuine.

### Value statement

> A catalogue small enough to understand completely and real enough to be judged on.

## Success metrics

| Metric | Target | Measurement method |
| --- | --- | --- |
| Live-evidence coverage | every criterion with evidence or a stated reason by 2026-11-21 | `docs/live-evidence.md`, `scripts/lint-live-evidence.sh` |
| Time to decision on a new finding | within the declared ceilings (30 days CRITICAL, 90 days HIGH, 14 days KEV) | the daily status issue and the catalogue page |
| Green operation | the nightly build and the daily rescan green without hands | GitHub Actions history |

### North star metric

Every mechanism the requirements name exercised live at least once, with its evidence recorded, before the successor repository is cut.

## Out of scope

### Explicitly not included

- FIPS or STIG variants, extended lifecycle support, registry mirroring, Docker Scout wiring, full SLSA L3 hermeticity
- A custom build engine
- Images beyond the reference set (mongodb, kyverno, istio) until the pattern exists for them

### Future considerations

- Image-level smoke proofs on the candidate build (design Decision 14's `smoke` kind), which would let base and dev images join without a chart
- The greenfield successor repository (design Decision 9, task group 12)

### Non-goals

- Competing with a vendor catalogue on breadth
- Suppressing findings to look clean; the catalogue shows unfixed findings with their status
