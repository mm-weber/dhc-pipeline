# ADR 0001: Build layer — native DHI frontend (decision A)

Date: 2026-07-18 · Status: **accepted** · Requirements: Req 1.7, Req 1.8

## Context

The catalogue's first responsibility is authoring image definition files. Two
candidate build layers: (A) Docker's real `dhi.io/build` BuildKit frontend in
native DHI syntax, or (B) DHI-style YAML rendered to Dockerfiles by thin glue.
Whether A works outside Docker's infrastructure was undocumented, so Req 1.8
timeboxed a 3-hour spike on the operator host (the devcontainer firewall blocks
dhi.io), with B as the defined fallback.

## Spike evidence (operator host, Docker Community tier)

- **C0 — access**: `docker login dhi.io` with Docker ID + PAT succeeds; both
  catalog images (`alpine-base:3.24-alpine3.24-dev`) and the frontend image
  (`dhi.io/build:2-alpine3.22`) pull on the free tier. First attempt failed on
  a wrong registry address + password-instead-of-PAT; the `anonymous token`
  401 named the missing per-repo scope, not a network problem.
- **C1 — verbatim build**: `image/static/alpine-3.22/static.yaml` built in
  5.8s/40 steps via `docker buildx build -f <yaml>`. Packages fetched from the
  public Alpine CDN; SPDX SBOM steps and an attestation manifest are part of
  the normal build; resulting image runs as 65532 with no shell.
- **C2 — authorship**: a modified copy (renamed image, retagged, tzdata
  dropped) built cleanly. The frontend accepts arbitrary `image:` names (so we
  can target ghcr.io); step-level BuildKit caching works across definition
  files; image shrank 2.12MB → 474kB confirming the content edit took effect.
- **C3a — full Go pipeline**: `image/netdata-agent-sd/alpine-3.23/0.yaml`
  built in 104s/90 steps: build stage pulled as `dhi.io/golang:1.26.4-
  alpine3.23-dev` (dev-variant catalog image), source cloned as
  `git+https://...#v0.2.10` with checksum, pipeline ran `go/bump` (dependency
  updates), upstream **tests**, and `go/build`, SBOM assembled under
  `/opt/docker/sbom/`. Notably the 3.23 variant fetched packages from
  **`dhi.io/apk/...`** with the DHI apk signing key — Docker's hardened
  package repo is accessible on the Community tier (the Enterprise-wall
  concern from research applied to the deb repo and remains untested, C3b
  skipped: alpine covers all four planned images).

## Decision

**A** — author our definitions in native DHI syntax, built by the real
`dhi.io/build` frontend. Req 1.7's WHERE clause is satisfied; fallback B is
retired.

## Consequences

- Literal job mirroring: our `image/` directory speaks the exact schema the
  DHI team maintains; SBOM + attestations come from the toolchain for free.
- New dependency: every build environment needs dhi.io auth — operator host
  (done), GitHub Actions (registry secret, task 3.3), devcontainer (dhi.io
  added to the firewall allowlist; takes effect + needs `docker login` in DinD
  after next rebuild).
- Base and builder pins reference dhi.io images by digest; Renovate's docker
  datasource must authenticate to dhi.io to track them (task 4.1).
- The frontend is a black box; its error messages are our only debugging
  surface. Mitigation: keep definitions close to catalog exemplars
  (static.yaml, netdata-agent-sd) and diff against upstream patterns first.
- Alpine variants only until a need arises; the deb path (dhi.io/deb) is
  unverified on this tier.
