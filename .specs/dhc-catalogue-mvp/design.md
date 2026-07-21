# Technical Design Document

## Overview

**Purpose**: A miniature DHI-style hardened-image catalogue ("dhc") that exercises, with real
industry tooling, every responsibility of a Docker Hardened Images engineering role: definition
authoring, chart adaptation, upstream tracking, Go-based integration testing, and CVE triage.

**Users**: The project owner (as catalogue maintainer and job candidate); later, reviewers of the
repository evaluating maintainer craft.

**Impact**: New repository built from empty in three workdays, then left operating (Renovate cron,
daily rescans) so genuine maintainer history accumulates unattended. Private until explicitly
released (Req 2.4).

### Goals

- Author four archetypal image definitions with DHI-grade pinning discipline (Req 1)
- Operate real automation: Renovate bump PRs, CI gates, daily scans (Req 3, 6)
- Adapt three upstream charts to hardened non-root images via overrides only (Req 4)
- Prove hardening on live Kubernetes with Go integration tests (Req 5)
- Keep every decision explainable — the owner must be able to defend each one in an interview

### Non-Goals

- mongodb / kyverno / istio images or charts (post-MVP additions once the pattern exists)
- FIPS/STIG variants, ELS, registry mirroring, Docker Scout wiring, full SLSA L3 hermeticity
- Any custom build engine beyond the thin fallback renderer (no wheel-reinvention)
- Public release ceremony — deferred until the owner flips visibility

## Architecture

### High-Level Architecture

```mermaid
graph TB
    subgraph Upstreams
        UP1[cert-manager monorepo]
        UP2[grafana releases]
        UP3[valkey releases]
    end

    subgraph Repository
        DEF[image/*/image.yaml definitions]
        CHT[chart/*/ pinned upstream + config/ overrides]
        TST[test/ Go module: Ginkgo + kind]
        TRI[triage/ OpenVEX + decisions]
        POL[policies/ Kyverno]
        CON[docs/CONVENTIONS.md + schema]
    end

    subgraph Automation["GitHub Actions"]
        REN[Renovate cron ≤6h]
        CI[PR gates: schema, build, ct, kind e2e, trivy+VEX, kyverno]
        REL[main: build, sign, SBOM, provenance, push]
        SCAN[daily rescan → issues]
    end

    GHCR[(ghcr.io/mm-weber/dhc — private)]

    UP1 & UP2 & UP3 --> REN --> DEF
    DEF --> CI --> REL --> GHCR
    CHT --> CI
    TST --> CI
    POL --> CI
    GHCR --> SCAN --> TRI
    TRI --> CI
```

### Technology Stack

| Layer | Technology | Rationale |
|-------|------------|-----------|
| Definitions | Real `dhi.io/build` syntax (spike A) or DHI-style YAML + thin renderer (fallback B) | Req 1.7/1.8; literal job practice first, transparent fallback second |
| Build | BuildKit / buildx bake, GitHub Actions | Docker-native, no bespoke engine |
| Tracking | Renovate self-hosted (`renovatebot/github-action`) | Industry standard for monorepo/fleet tracking; `postUpgradeTasks` recomputes source checksums (hosted app forbids them) |
| Charts | Upstream charts + values overrides (rudder-style `config/`) | Upstream untouched; deviations reviewable (Req 4) |
| Tests | Go, Ginkgo v2 + Gomega, sigs.k8s.io/e2e-framework, kind, chart-testing (`ct`) | Req 5.1; the JD's Go lives here |
| Policy gate | Kyverno CLI against rendered charts | Reuses owner's lab policies; admission-shaped CI gate |
| Scanning/VEX | Trivy (gate + cron), Grype (second opinion), Syft (SBOM), OpenVEX/`vexctl` | Req 6; DHI's own triage model |
| Signing | cosign keyless (GitHub OIDC) + buildx provenance | Req 2.2 |

### Key Design Decisions

1. **Real DHI frontend first, thin renderer fallback (Req 1.7/1.8)**
   - **Context**: The JD's first bullet is authoring definition files; DHI's catalog is open source.
   - **Options**: (A) build with Docker's `# syntax=dhi.io/build` frontend; (B) DHI-style YAML rendered to Dockerfiles; (C) plain Dockerfiles FROM dhi.io bases.
   - **Decision**: Spike A on the owner's host, timeboxed 3h; fall back to B. C rejected (abandons definition authoring).
   - **Trade-offs**: A risks entitlement/black-box friction; B adds ~small glue we maintain.

2. **Renovate self-hosted, not custom tracker, not hosted app**
   - **Context**: "No wheel-reinvention"; source pins carry checksums Renovate cannot natively recompute.
   - **Decision**: `renovatebot/github-action` on cron with regex managers, monorepo grouping, Dependency Dashboard for majors, automerge for digest-only patches (Req 3).
   - **Trade-offs**: We own the runner config; slower than hosted app to first PR.

3. **Stale-pin bootstrap for immediate real history (Req 3.6)**
   - **Decision**: Initial pins sit ≥1 release behind latest so Renovate opens genuine PRs (including one real major staged in the dashboard) from day 1; cron keeps history growing after the 3 days.
   - **Trade-offs**: First builds are of slightly-old versions; acceptable, honest, and itself demonstrates the bump flow.

4. **Hardening via overrides, never forked charts (Req 4)**
   - **Decision**: Pin upstream chart version; all changes live in `config/values-hardened.yaml` + per-chart README rationale; compat decisions documented when a chart assumes a shell.

5. **VEX-gated scanning (Req 6)**
   - **Decision**: Trivy PR gate fails only on findings not covered by our OpenVEX; triage outcomes are commits (VEX statement or bump PR), giving auditable history.

## System Flows

### Upstream bump flow (the operating heart)

```mermaid
sequenceDiagram
    participant U as Upstream release
    participant R as Renovate (cron)
    participant PR as Pull Request
    participant CI as CI gates
    participant M as main / release job
    participant G as GHCR (private)

    U->>R: new tag matches version policy
    R->>PR: bump pin+checksum (grouped; majors → dashboard)
    PR->>CI: schema+conventions → build → ct → kind e2e → trivy+VEX → kyverno
    CI-->>PR: checks green (digest-only patch: automerge)
    PR->>M: merge (human review otherwise)
    M->>G: multi-arch build, cosign sign, SBOM, provenance, push
    G->>CI: daily rescan → new CVE? issue → VEX or fix-bump PR
```

## Components and Interfaces

### image/<name>/ — definitions (Req 1, 2)
One directory per component; `image.yaml` in DHI schema shapes: `vars` (upstream version + regex
extraction), `files` (git+https source, `checksum:`), `contents`/`builds` (stages), `outputs`
(uid/gid/mode), `accounts` (nonroot 65532), `platforms` (amd64/arm64). cert-manager is one
definition producing three images (controller/webhook/cainjector) from one version var.
Consumed by: CI build workflow; watched by: Renovate regex managers.

### chart/<name>/ — adaptations (Req 4)
`chart.yaml` (pinned upstream chart source+version), `config/values-hardened.yaml` (image swap to
digest-pinned refs + restricted-PSS securityContext + emptyDir mounts), `README.md` (every
deviation + rationale + compat decision). Consumed by: ct, kind e2e, kyverno gate.
Additionally `chart/hardened-app/` carries the owner's lab chart over unchanged — an owned chart,
not an upstream adaptation (outside Req 4.1), giving Req 5.5's hardened-app probe a deploy path.

### test/ — Go module (Req 5)
Ginkgo v2 suites per component under `test/e2e/`; e2e-framework provisions kind; shared helpers
for install/upgrade, readiness, live securityContext assertion, functional probes. Entry:
`go test ./test/e2e/... -args --chart <name>`; CI matrix runs affected components only.

### triage/ — decisions (Req 6)
`triage/vex/*.openvex.json` (authored via vexctl, attached with cosign attest),
`triage/LOG.md` (dated decisions: finding → EPSS/KEV → outcome → link). Consumed by Trivy gate.

### .github/workflows/
`validate.yml` (schema/yamllint/conventions), `build.yml` (PR build + gates; main: release),
`e2e.yml` (kind matrix), `renovate.yml` (cron ≤6h), `rescan.yml` (daily; opens issues).

**Build cost split (validated on the first CI run):** the PR gate builds
`linux/amd64` only — fast proof a definition compiles — while the release path
(main) builds both arches per Req 2.1. arm64 through the frontend runs cross-
compiled or QEMU-emulated on an amd64 runner; paying that once at merge, not on
every PR, keeps PR feedback fast. Both paths use `type=gha` build cache
(per-image scope) so repeat builds of a large upstream (cert-manager, ~30–40 min
cold multi-arch) reuse the Go module + compile layers.

## Data Models

Definition schema (fallback-B shape, mirroring real DHI fields; JSON Schema enforced in CI):

```yaml
name: grafana
vars:
  version: "11.3.0"            # Renovate-managed; regex-extracted tag segments
files:
  - url: git+https://github.com/grafana/grafana.git#v${version}
    checksum: sha256:...       # postUpgradeTasks recompute
contents:
  base: gcr.io/distroless/static-debian12@sha256:...   # digest-pinned always
builds:
  - stage: fetch|build|runtime steps (pipeline: runs/uses)
outputs:
  - source: ...; target: /usr/share/grafana; uid: 65532; gid: 65532
accounts:
  runtime: {user: nonroot, uid: 65532}
platforms: [linux/amd64, linux/arm64]
```

## Error Handling

| Failure | Response | Requirement |
|---------|----------|-------------|
| Definition violates schema/pinning | validate.yml fails naming the rule and reference | 1.5, 1.6, 7.4 |
| Upstream bump breaks build | PR stays red; failure is the triage/fix work, documented in CONVENTIONS | 2.5 |
| Renovate mis-parses a pin | regex managers carry unit fixtures in repo; dashboard shows detection state | 3 |
| kind flake / timeout | one retry per suite; diagnostic logs uploaded as artifacts | 5.7 |
| Trivy DB outage | PR gate hard-fails (retryable); daily rescan soft-fails with issue | 6 |
| New CVE on published image | issue with severity/EPSS/KEV → VEX statement or fix-bump PR | 6.3–6.5 |

## Testing Strategy

### Unit Tests
- Renovate regex-manager fixtures (does this pin string parse?); schema negative cases; TDD on any fallback-renderer glue (per repo CLAUDE.md).

### Integration Tests
- Req 5 suite: per-chart install on kind → Ready ≤5min → live securityContext assertions → functional probes (Certificate issued; grafana HTTP health; valkey SET/GET; hardened-app 200) → upgrade path on bump PRs.

### E2E / Pipeline
- ct lint+install per changed chart; kyverno CLI over rendered manifests (digest, registry, nonroot); trivy gate with VEX; full bump-flow rehearsal via one deliberately stale pin per component.

## Security Considerations

- Non-root 65532 everywhere; restricted PSS enforced twice (chart overrides + kyverno gate)
- Everything digest/checksum-pinned; floating tags fail CI (Req 1.6)
- cosign keyless via GitHub OIDC — no long-lived signing keys; PAT stays in `.keys/` (gitignored)
- Private repo + private GHCR until owner flips (Req 2.4); no secrets in definitions

## Delivery Plan (3 workdays, cut line explicit)

- **Day 1**: skeleton, CONVENTIONS, validate.yml; host spike of `dhi.io/build` (3h box → decision A/B); hardened-app + cert-manager definitions building, signed, pushed; stale pins set.
- **Day 2**: Renovate live (first real bump PRs incl. staged major); grafana + valkey definitions; cert-manager + grafana chart adaptations + kyverno gate.
- **Day 3**: Ginkgo/kind suite across all four; triage lane + first real VEX; valkey chart; README narrative (lab → catalogue arc); cron left running.
- **Cut from tail**: valkey chart → valkey image → grafana upgrade-test depth. **Never cut**: operating Renovate, one full chart adaptation, one real VEX decision.

## Development Process

Per repo CLAUDE.md: requirements writing in EARS (this spec), progress managed in scalable bits
with the agent-orchestration plugin, TDD wherever coding applies (renderer glue, test helpers).
Heavy operations (builds, kind, pushes) run in GitHub Actions or on the operator host — never in
the restricted devcontainer (Req 8).
