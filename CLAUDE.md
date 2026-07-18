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

- This devcontainer has **no outbound internet** (github.com works). Do not
  attempt WebSearch/WebFetch — the user researches on their host and drops
  results into `data/`.
- Image builds, kind-based tests, and registry pushes run in **GitHub Actions**
  or on the user's host — not in this container.
