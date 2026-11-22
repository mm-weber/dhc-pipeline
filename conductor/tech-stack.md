# Technology stack

The authoritative table with rationale is `.specs/dhc-catalogue-mvp/design.md` ("Technology Stack") and its sixteen key design decisions plus ADR 0001 to 0005 under `docs/decisions/`. This file is the working summary; it states no tool versions, because each version is declared in one place (named below) and a copy here drifts.

## Languages

| Language | Where | Notes |
| --- | --- | --- |
| Bash | `scripts/*.sh`, every lint, check, reader and refresh tool | each script has a `<name>_test.sh` suite and validate runs every suite (the "every script has a test suite" step); YAML is read through python3 and PyYAML, never yq (two yq dialects between runner and devcontainer) |
| Go | `test/` (Ginkgo, Gomega, sigs.k8s.io/e2e-framework, k8s.io) and `triage/rescan` (stdlib only) | versions in `test/go.mod` and `triage/rescan/go.mod`, which `actions/setup-go` reads (`go-version-file`); gofmt, go vet, and go.mod held equal to what `go mod tidy` writes |
| Python 3 | glue inside shell scripts, CI helpers | PyYAML, yamllint, yamale, pinned with hashes in `.github/requirements-ci.txt` |
| Node | Renovate config validation and manager fixtures (`test/renovate/managers.test.mjs`) | renovate and json5, pinned in `validate.yml`'s env block (`RENOVATE_VERSION`, `JSON5_VERSION`) |
| YAML | definitions (`image/`), charts (`chart/`), the policy file, workflows | definitions compile with the `dhi.io/build` frontend, digest-pinned in each definition's `# syntax=` line |

## Build and release

- BuildKit with the Docker Hardened Images frontend; `docker/build-push-action` in GitHub Actions.
- Pull requests build amd64, load locally and push to a local registry for the scan gate; main pushes by digest, scans every platform manifest, signs and attests with cosign keyless, then applies tags.
- Registry: `ghcr.io/mm-weber/dhc` (public; the daily visibility invariant asserts it).

## Pinned tools

Each version and its sha256 are declared once: Trivy and Grype in `scripts/install-scanners.sh`, the others in `scripts/install-tool.sh`, each pin under a `# renovate:` comment that the custom manager in `renovate.json5` bumps. govulncheck is the exception, pinned in `build.yml`'s env block (`GOVULNCHECK_VERSION`).

| Tool | Role |
| --- | --- |
| Trivy | authoritative scanner, gate and rescan |
| Grype | second opinion on CRITICAL |
| Syft | SBOMs |
| cosign | signatures and attestations |
| kind | ephemeral clusters for the e2e |
| Helm | chart render and install |
| chart-testing | owned chart lint |
| Kyverno CLI | the policy gate on rendered charts |
| crane | registry reads |
| vexctl | OpenVEX |
| lychee | the offline link check in validate (Req 9.20) |

## Infrastructure

- **CI/CD:** GitHub Actions is the authoritative environment (builds, kind, pushes, scans). Workflows: `validate.yml` (lints and unit suites), `build.yml` (build gate and the release arm), `chart.yml` (render and policy gate), `e2e.yml` (kind suite), `rescan.yml` (daily), `renovate.yml` (at most every six hours by Req 3.1, configured every four hours in `catalogue-policy.yaml`).
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

Kept in `.specs/dhc-catalogue-mvp/design.md` (Decisions 1 to 16) and `docs/decisions/` (ADR 0001 build layer, 0002 grafana upstream tracking, 0003 and 0004 attestation shape, 0005 the SLSA provenance verifier). The most recent: Decision 16, the documentation map (2026-11-20).
