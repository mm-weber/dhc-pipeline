# dhc-pipeline

> [!WARNING]
> **Work in progress; this repository will be archived soon.** It is the
> proving ground for a hardened-image operating model that restarts as a
> fresh successor repository once the remaining implementation tasks land
> (see `.specs/dhc-catalogue-mvp/tasks.md`, task 12). When that happens this
> repository is archived intact, history and all, and the catalogue it
> publishes under `ghcr.io/mm-weber/dhc` is archived with it: existing
> digests stay pullable and verifiable, but no new digests, tags, scans or
> statements will follow here. Do not build anything on this catalogue that
> expects continuity; wait for the successor.

A miniature hardened-image catalogue built with
[Docker Hardened Images](https://docs.docker.com/dhi/) tooling and packages,
made as a skill-building project and then **operated**: image
definitions in native `dhi.io/build` syntax, upstream Helm charts adapted to
hardened non-root images, Renovate tracking upstream releases, Go integration
tests on real Kubernetes, and CVE triage recorded as portable OpenVEX. It grew
out of a one-image supply-chain lab (a hardened Go service plus Kyverno
admission policies — both carried over) into the full maintainer loop, and the
automation has been running unattended since 2026-07: real bump PRs, real scan
findings, real triage decisions, all in this repo's history.

The hardening substrate is Docker Hardened Images': the build frontend, the
builder images, the apk repositories and their signing key. This catalogue
contributes the operating model: the definitions, the triage lanes, the chart
adaptations, the tests, the published promise and its invariants. It is not
affiliated with, sponsored by or endorsed by Docker, Inc.; the names are used
to describe where the substrate comes from.

## Layout

| Path | What |
|---|---|
| `image/` | Definitions: hardened-app, cert-manager ×3, grafana, valkey (+`valkey-compat` variant) |
| `chart/` | Upstream charts pinned + hardened via overrides only; one owned chart |
| `test/` | Ginkgo/kind e2e: readiness, live securityContext, functional probes, upgrades |
| `triage/` | OpenVEX source, accepted-risk exceptions, decision log, upstream investigations |
| `policies/` | Kyverno gate: digest pins, allowed registry, non-root |
| `scripts/` | Tested glue: pin lints, VEX compiler, scanner installs |
| `.specs/` | EARS requirements, design, task ledger (the honest one — open gaps included) |
| `docs/` | [User manual](docs/user-manual.md), conventions, ADRs, operating-loop evidence |

## Verify an image

Every image published to `ghcr.io/mm-weber/dhc` is signed (cosign keyless via
GitHub OIDC) and carries an SPDX SBOM, OpenVEX, and BuildKit provenance:

<!-- render-verification:begin -->
```sh
# rendered by scripts/render-verification.sh from catalogue-policy.yaml; do not edit
REF=ghcr.io/mm-weber/dhc/IMAGE:TAG        # any catalogue tag, e.g. grafana:13.1.3-alpine3.23
ISSUER='--certificate-oidc-issuer https://token.actions.githubusercontent.com'
BUILD='--certificate-identity https://github.com/mm-weber/dhc-pipeline/.github/workflows/build.yml@refs/heads/main'
RESCAN='--certificate-identity https://github.com/mm-weber/dhc-pipeline/.github/workflows/rescan.yml@refs/heads/main'

cosign verify $ISSUER $BUILD "$REF"                          # signature: the release workflow on main
cosign verify-attestation $ISSUER $BUILD --type spdxjson "$REF" \
  | jq -r '.payload | @base64d | fromjson | .predicate'      # SBOM
{ cosign verify-attestation $ISSUER $BUILD --type openvex "$REF" 2>/dev/null \
  || cosign verify-attestation $ISSUER $RESCAN --type openvex "$REF"; } \
  | jq -r '.payload | @base64d | fromjson | .predicate' > openvex.json   # VEX: releaser or re-attester
trivy image --vex openvex.json --show-suppressed --severity CRITICAL,HIGH "$REF"   # authoritative consumer
grype "$REF" --vex openvex.json                                                    # declared consumer, informational
# BuildKit provenance is attached at build time and is not verified by the
# policy above (Req 2.25); inspect it with the buildx CLI plugin:
docker buildx imagetools inspect "$REF" --format '{{ json .Provenance }}'
```
<!-- render-verification:end -->

## Triage, recorded

The PR scan gate (Trivy, the authoritative VEX consumer; Grype as a declared
second consumer, its results in the VEX portability block) fails on any
HIGH/CRITICAL not covered by a VEX statement (`not_affected`/`fixed`, with
`govulncheck` reachability evidence) or a time-boxed accepted-risk exception
that decays back to un-triaged on expiry. Every decision is a commit:
[`triage/README.md`](triage/README.md) has the model,
[`triage/LOG.md`](triage/LOG.md) the history — including the retractions.

## Operating loop

Self-hosted Renovate (≤6h cron) opens pinned, checksum-recomputed bump PRs;
CI rebuilds, re-scans, and e2e-tests them; a daily rescan of published images
opens issues with severity/EPSS/KEV. See
[`docs/operating-loop.md`](docs/operating-loop.md) for a live trace.

## Security and trust

[`SECURITY.md`](SECURITY.md) states the promise, what a signature attests and
does not, the governance (one maintainer, the bypass kept in force), the
reporting and advisory channels, the revocation record, each definition's
upstream authenticity class, the transparency-log disclosure and the
substrate terms. The trust-boundary table in
[`docs/concepts.md`](docs/concepts.md#trust-boundary-who-owns-what-and-where-the-seams-are)
lists every component with its owner class and declared seam alternative.

## License

[MIT](LICENSE) for this repository. The images are built with Docker Hardened
Images tooling and packages, Copyright 2025 Docker Inc., Apache-2.0
([`NOTICE`](NOTICE), [`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt)),
and repackage upstream software under upstream licenses (noted per
definition, enumerated per package in the attested SBOMs).
