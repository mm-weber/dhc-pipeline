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

`triage/accepted-risk/<image>.yaml` (Req 6.7–6.12) covers the two treatments VEX
must never express. Risk has four treatments — avoid (drop the component),
mitigate (bump/patch, Req 6.5), transfer (upstream owns the fix), accept (ship
knowingly) — and before this the gate had machinery only for the first two plus
`not_affected`, so a real-and-unfixable finding could block an image forever with
VEX as the only pressure valve. That is VEX-washing, which Req 6.8 forbids.

The split is by *question*: **VEX answers "does this apply?"** — a claim about the
artifact, evidence-backed, attested, no expiry. **accepted-risk answers "what are
we doing about it?"** — a decision about our exposure, internal, never attested,
and it expires. Transfer gets no separate file: while waiting on upstream we are
still carrying the risk, so it is an acceptance with an external owner.

Mechanically these are native Trivy ignorefiles (`--ignorefile`, one per image so
an acceptance for grafana never silently covers cert-manager), composed with
`--vex` in the same scan. Verified against Trivy 0.72.0: a future `expired_at`
suppresses, a past one is silently counted again, versionless `purls:` scope to
one package, and suppressions surface in `ExperimentalModifiedFindings` with a
`Source` that distinguishes VEX from acceptance. So **acceptance decays back to
un-triaged on its own** (Req 6.9) — the property that makes it safe. Our glue is
only what Trivy lacks: `scripts/lint-accepted-risk.sh` enforcing required fields,
the 90-day ceiling, and that no ignorefile lives anywhere else (Req 6.11–6.12),
plus expiry reporting (Req 6.10), since Trivy logs nothing when an entry lapses.

Each entry carries a `blocked:` field stating why avoid and mitigate were
unavailable — presence machine-enforced, content judged at review. It is what
keeps the file from becoming the path of least resistance.

**Per-binary scope (Req 6.23–6.27).** One file per image stops an acceptance for
grafana covering cert-manager. It does not stop an acceptance for *one binary
inside* grafana covering another, and a repackage image is exactly where that
bites: CVE-2026-27145 is in both `plugins-bundled/elasticsearch/` and
`plugins-bundled/zipkin/`, compiled at different times, fixed by different
upstreams, on different schedules. An entry keyed only on `id` + `purls` matches
`stdlib` wherever it appears, so deciding elasticsearch silently decides zipkin
— the same failure the per-image filename was introduced to prevent, one level
down. Req 6.23/6.24 push the scope into the entry via Trivy's `paths:`, so an
exception names the binary whose exposure was actually argued.

Verified against Trivy 0.72.0 rather than inferred, on a two-binary tree built
from the real plugin release assets:

| Behaviour | Result |
|---|---|
| `paths:` scoping one binary | 12 findings → 11; only that binary suppressed |
| no `paths:` key | 12 → 10; **every** instance suppressed |
| globs `dir/*`, `**/dir/**`, `dir/gpx_*` | all scope correctly |
| a path matching nothing | suppresses nothing, no warning, exit 0 |
| suppression record | `Target` = binary, `Statement` = entry, `Source` = file |

Globs matter because the binaries carry an arch suffix. Measured on the
published index, the same finding sits at
`.../elasticsearch/gpx_..._linux_amd64` on amd64 and at `..._linux_arm64` on
arm64. The catalogue publishes amd64 only (Req 2.1), so an exact path is correct
for every scan that runs today and goes silently wrong the moment arm64 returns
(task 8.3) or a consumer scans an arm64 image themselves. A path matching
nothing is completely silent, per the row above, so a glob is what keeps that
from becoming a discovery.

The last two rows are why Req 6.26/6.27 exist. The two failure modes are not
symmetric: a *too narrow* path fails safe (nothing is suppressed, the gate stays
red) but is indistinguishable from an untriaged finding, while a *too broad* or
absent path fails dangerous (the gate goes green over a binary nobody decided
about). Req 6.26 catches the first by reporting any exception that suppressed
nothing, which is also the instrument that would catch Trivy ceasing to honour
`paths:` at all. Req 6.27 catches the second by naming the binary in the
suppression table, so over-broad scope is visible in review rather than inferred
from a count. Neither fails the build: an exception that suppresses nothing
leaves nothing uncovered, so Req 6.1 is not the right lever, and the precedent is
the VEX canary warning — make it visible, do not redden an unrelated PR.

**Reachability evidence (Req 6.13–6.15).** Trivy and Grype answer "is this
module linked", never "is the vulnerable code called". Every `not_affected`
statement in this catalogue rested on architectural argument instead — sound and
checkable, but weaker than a measurement, and useless against an advisory like
kin-openapi's fail-open `ValidationHandler`, where applicability turns entirely
on whether one symbol is wired in. `govulncheck -mode=binary` reads the Go
binary's symbol table and distinguishes the two, so it runs on the PR path
against every Go binary in the built image.

It is **evidence, not a gate** — Trivy remains the only thing that fails a
build. A reachability tool that can also break CI is a second gate nobody
designed, and its false negatives would then silently pass images.

Split like `triage/rescan/`: `scripts/govulncheck-report.sh` is the pure,
unit-tested part (govulncheck JSON → per-binary table of OSV, module and
`symbol` / `package` / `module` level) and the workflow is the I/O around it
(export the container rootfs, find Go binaries, run govulncheck, print). The
level is the discriminator: a finding whose trace names a function is reachable;
one reported at module level only proves nothing either way — which is also what
a stripped binary looks like, so the report says which it was.

Req 6.14 makes the direction one-way on purpose. A reachable symbol *forbids*
`not_affected`; an unreachable one does not compel it, because govulncheck sees
only Go call graphs and not reflection, plugins or `exec`.

**Statement identity (Req 6.17–6.22).** A VEX statement that matches nothing is
indistinguishable from one that worked, so `scripts/lint-vex-product.sh` checks
the identifiers Trivy compares: the product is a `pkg:oci/` purl naming a real
definition (6.17), its `repository_url` equals that definition's `image:` (6.18),
and subcomponents are versionless so they survive an upstream bump (6.19).

**Source is not what a scanner sees (Req 6.28-6.30).** `triage/vex/` holds
hand-authored *source*, and `scripts/compile-vex.sh` renders it per build into
what Trivy is actually given. The split exists because the two have
irreconcilable requirements: source has to be reviewable by a human and stable
in git, while a product identifier has to be a string Trivy matches, and Trivy
builds that string from the image's **RepoDigest**.

Measured on `grafana:13-alpine3.23`, one real finding, one statement each:

| Product identifier | Status | Suppressed |
|---|---|---|
| `pkg:oci/grafana@13.0.4-alpine3.23` (tag) | `fixed` | **no** |
| `pkg:oci/grafana@sha256:b6987eb…` (digest) | `fixed` | yes |
| `pkg:oci/grafana` (versionless) | `fixed` | yes |
| `pkg:oci/grafana` (versionless) | `not_affected` | yes |

So the tag form the earlier design prescribed matched nothing, silently. That
went unnoticed because the one `fixed` statement written under it covers a
finding that had already vanished from the scan, so it never had to suppress
anything. Compilation is what makes the two requirements compatible: the author
writes a tag, the compiler emits the digest.

Version in *source* is therefore a scope, not an identifier:

- **a published tag** means the claim is about that release. `fixed` must carry
  one (6.21), because a remedy is always about particular versions.
- **no version** means the claim holds for every build of that image.

Only tags are admissible in source (6.20). A digest in source would be a claim
nobody can review and would go stale at the next rebuild of the same release.

**Versionless is a decision, not a default (Req 6.31).** The two scopes answer
different questions and neither is right for both kinds of `not_affected`:

- *structural* claims do not depend on a version. "This image runs Grafana's
  dashboard server, which never starts a Prometheus server, so the disclosing
  handler is not routed" is as true of 14.0 as of 13.0.4. Re-arguing it every
  release is churn that teaches nothing.
- *dependency-graph* claims do. "This build does not reach the vulnerable
  symbol" rests on what this release happens to link, and 14.0 may link
  something else entirely.

Left to a default, every statement drifts to versionless, because that is what
suppresses most and costs least to write. So a versionless product must say in
`status_notes` why its claim survives a version change, marked with the literal
token `version-independent:` so the rule is checkable rather than a matter of
taste. It is written into `status_notes` rather than a custom field because it
stays inside standard OpenVEX and because a consumer reading the statement
wants that sentence too.

What this rejects is a versionless claim nobody defended. A tag-scoped claim
needs no such note: its scope already says what it covers.

The compiler then does two things per build: it drops any statement whose tag is
not a tag of the image being scanned (6.30), and it rewrites every surviving
product to that image's digest (6.29). Dropping is what stops a claim outliving
the release it was argued about, which is review finding 2.4: under the old rules
a versionless `not_affected` stayed the latest statement for its own product
forever and suppressed on versions nobody had examined. Rewriting is what makes
the statement match at all.

It also subsumes the qualifier-stripping the gate did inline for trivy#9399,
since the compiler already rewrites the identifier — one tested transform from
source to scan input instead of a `jq` expression in YAML.

Req 6.22 keeps a superseded claim on the record. OpenVEX documents hold multiple
timestamped statements and consumers take the latest per (vulnerability,
product), so a superseded claim is retained rather than deleted: the artifact
carries what we argued, when, and what replaced it. Compilation is also what
makes that work, because both statements now compile to the *same* product
identity — the build's digest — so the later timestamp actually supersedes.
Under the old split they named different products and superseded nothing.

### .github/workflows/
`validate.yml` (schema/yamllint/conventions), `build.yml` (PR build + gates; main: release),
`e2e.yml` (kind matrix), `renovate.yml` (cron ≤6h), `rescan.yml` (daily; opens issues).

**Platforms: `linux/amd64` only (Req 2.1, Req 2.6).** The catalogue built and
published both arches until 2026-08-04, when measurement showed nothing ever
scanned the arm64 half. Every scan step in `build.yml` is `pull_request`-gated
and the PR gate builds amd64 only, while `rescan.yml` passes no `--platform`, so
Trivy resolves the published index to the runner's own architecture. arm64 was
therefore built, pushed, signed, SBOM'd and attested with no gate ever reading
it, which is the concrete case in review finding 1.3. Shipping one platform is
the cheap correction; scanning two is the larger change, deferred to task 8.3.

Measured on the published `grafana:13-alpine3.23` index, both platforms carry an
identical HIGH/CRITICAL set (11 each, same CVE, package and version), so nothing
is known to be hiding in the arm64 image. That is one observation on one day
rather than a property: apk metadata is per-arch and a fix can land on one arch
before the other.

Definitions keep `platforms: [linux/amd64, linux/arm64]` and their per-arch
pins, and `verify-arch-pins.sh` keeps verifying both. The definitions do support
arm64; the release path publishes one platform. Keeping the pins exercised is
what makes task 8.3 a build-matrix change rather than archaeology.

Both paths use `type=gha` build cache (per-image scope) so repeat builds of a
large upstream (cert-manager) reuse the Go module + compile layers.

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
