# CLAUDE.md — dhc-pipeline

Mini DHI-style hardened-image catalogue: a skill-building repo mirroring the
responsibilities of a DHI-flavored role (image definitions, chart adaptation,
upstream tracking, Go integration tests, CVE triage). Research inputs live in
`data/`; formal spec artifacts in `.specs/` (spec-driven-workflow); design docs
in `docs/`.

## Process tooling (required in this repo)

- **agent-orchestration plugin** — manage progress and split implementation
  work into scalable bits
- **ears-notation skill** — all requirements / acceptance-criteria writing is
  formatted in EARS notation
- **TDD** (`superpowers:test-driven-development`, aka /tdd) — for coding tasks
  whenever applicable

## Working principles

- Use real, industry-standard tools over bespoke code — no wheel-reinvention.
  Custom code only as thin glue or when it is itself the learning objective.
- Optimize for the user's understanding: decisions must be explainable and
  defensible in an interview setting.

## Environment constraints

- Devcontainer egress is **allowlist-firewalled** (`/workspace/.devcontainer/init-firewall.sh`),
  not offline: GitHub (git/SSH, API, release binaries, ghcr.io), Docker Hub,
  PyPI, npm, and the Go proxy are reachable; everything else is blocked.
  Tools like kyverno/kind/trivy install fine from GitHub releases.
- For open-web research, the user prefers doing it on their host and dropping
  results into `data/` — ask rather than reaching for WebSearch/WebFetch.
- **GitHub Actions is the authoritative environment** for image builds, kind
  e2e, registry pushes, and scans (Req 8). Local kind runs are feasible
  (kindest/node via Docker Hub, our images via ghcr.io) and welcome for
  iteration speed — CI results are what count.
