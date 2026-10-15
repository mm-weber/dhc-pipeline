# Technology stack

The authoritative table with rationale is `.specs/dhc-catalogue-mvp/design.md` ("Technology Stack") and its fourteen key design decisions plus ADR 0001 to 0004 under `docs/decisions/`. This file is the working summary.

## Languages

| Language | Where | Notes |
| --- | --- | --- |
| Bash | `scripts/*.sh`, every lint, check, reader and refresh tool | each script has a `<name>_test.sh` suite and validate runs every suite (the "every script has a test suite" step); YAML is read through python3 and PyYAML, never yq (two yq dialects between runner and devcontainer) |
| Go 1.25.7 | `test/` (Ginkgo v2.33.0, Gomega 1.44.0, sigs.k8s.io/e2e-framework 0.7.0, k8s.io 0.35.3) and `triage/rescan` (stdlib only) | gofmt, go vet, and go.mod held equal to what `go mod tidy` writes |
| Python 3 | glue inside shell scripts, CI helpers | PyYAML 6.0.3, yamllint 1.38.0, yamale 6.1.0, pinned with hashes in `.github/requirements-ci.txt` |
| Node | Renovate config validation and manager fixtures (`test/renovate/managers.test.mjs`) | renovate 41.173.1 |
| YAML | definitions (`image/`), charts (`chart/`), the policy file, workflows | definitions compile with the pinned `dhi.io/build:2-alpine3.23` frontend |

## Build and release

- BuildKit with the Docker Hardened Images frontend; `docker/build-push-action` in GitHub Actions.
- Pull requests build amd64, load locally and push to a local registry for the scan gate; main pushes by digest, scans every platform manifest, signs and attests with cosign 2.6.5 keyless, then applies tags.
- Registry: `ghcr.io/mm-weber/dhc` (public; the daily visibility invariant asserts it).

## Pinned tools (`scripts/install-*.sh`, checksums recorded)

| Tool | Version | Role |
| --- | --- | --- |
| Trivy | 0.75.0 | authoritative scanner, gate and rescan |
| Grype | 0.120.1 | second opinion on CRITICAL |
| Syft | 1.54.1 | SBOMs |
| cosign | 2.6.5 | signatures and attestations |
| kind | 0.33.0 | ephemeral clusters for the e2e |
| Helm | 4.3.0 | chart render and install |
| chart-testing | 3.15.0 | owned chart lint |
| Kyverno CLI | 1.19.1 | the policy gate on rendered charts |
| crane | 0.22.1 | registry reads |
| vexctl | 0.4.4 | OpenVEX |

## Infrastructure

- **CI/CD:** GitHub Actions is the authoritative environment (builds, kind, pushes, scans). Workflows: `validate.yml` (lints and unit suites), `build.yml` (build gate and the release arm), `chart.yml` (render and policy gate), `e2e.yml` (kind suite), `rescan.yml` (daily), `renovate.yml` (every four hours).
- **Tracking:** Renovate self-hosted through `renovatebot/github-action`, regex managers with fixture tests, postUpgradeTasks that recompute checksums.
- **Monitoring:** the daily rescan files and closes issues, publishes the status issue and the catalogue page on GitHub Pages; the live-evidence ledger records what has run for real.
- **Development environment:** an allowlist-firewalled devcontainer (GitHub, Docker Hub, PyPI, npm, the Go proxy reachable); heavy operations run in Actions.

## Testing

| Type | Tool | Gate |
| --- | --- | --- |
| Unit (shell) | hand-rolled `expect`/`check` harnesses in `*_test.sh`, sandboxes under `mktemp -d` | every suite runs in validate |
| Unit (Go) | `go test ./...` in `test/` and `triage/rescan` | validate |
| Policy | `kyverno test` fixtures | validate |
| Integration | Ginkgo on kind, one component per matrix leg | e2e gate |
| Live | drills recorded in `docs/live-evidence.md` | task group 16 |

No numeric coverage gate: the rule is one suite per script, every suite in CI, and one failing test before every change.

## Linting and formatting

yamllint (`.yamllint`), gofmt and go vet, yamale schemas for chart pin manifests, the house lints under `scripts/lint-*.sh`, shellcheck directives kept in scripts.

## Decision log

Kept in `.specs/dhc-catalogue-mvp/design.md` (Decisions 1 to 14) and `docs/decisions/` (ADR 0001 build layer, 0002 grafana upstream tracking, 0003 and 0004 attestation shape). The most recent: Decision 14, proof kinds per definition (2026-10-15).
