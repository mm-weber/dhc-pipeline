# dhc-pipeline

A miniature [Docker Hardened Images](https://docs.docker.com/dhi/)-style
catalogue, built as a skill-building project and then **operated**: image
definitions in native `dhi.io/build` syntax, upstream Helm charts adapted to
hardened non-root images, Renovate tracking upstream releases, Go integration
tests on real Kubernetes, and CVE triage recorded as portable OpenVEX. It grew
out of a one-image supply-chain lab (a hardened Go service plus Kyverno
admission policies — both carried over) into the full maintainer loop, and the
automation has been running unattended since 2026-07: real bump PRs, real scan
findings, real triage decisions, all in this repo's history.

## The pipeline

```mermaid
flowchart TD
    subgraph track["Upstream tracking · every 4h"]
        UP([upstream release]) --> RV["Renovate<br/>self-hosted, custom regex managers"]
        RV --> BUMP["bump PR<br/>postUpgradeTask re-pins checksum,<br/>commit, tags, purl — coherence linted"]
    end

    subgraph gate["PR gate · holds no push credential"]
        BUILD["BuildKit build<br/>dhi.io frontend, digest-pinned"] --> TREG["throwaway local registry<br/>mints the RepoDigest"]
        TREG --> SCAN{"Trivy + compiled VEX<br/>+ accepted-risk:<br/>HIGH/CRITICAL uncovered?"}
        KYV["Kyverno gate on rendered charts<br/>digest pins · our registry · non-root"]
        E2E["kind e2e<br/>ready · hardened · functional probe · upgrade"]
    end

    subgraph rel["Release · main only"]
        PUSH["build + push ghcr.io"] --> SIGN["cosign keyless sign + attest<br/>SPDX SBOM · SLSA provenance · OpenVEX"]
    end

    subgraph op["Operate · daily"]
        RESCAN["rescan every published image"] -->|new finding| QUEUE["one issue per finding<br/>EPSS/KEV-ordered queue"]
    end

    BUMP --> BUILD
    BUMP --> KYV
    BUMP --> E2E
    SCAN -->|yes| TRIAGE["triage decision<br/>(model below)"]
    SCAN -->|no| MERGE([merge])
    KYV --> MERGE
    E2E --> MERGE
    MERGE --> PUSH
    SIGN --> RESCAN
    QUEUE --> TRIAGE
    TRIAGE -->|"fix ⇒ version bump"| UP
```

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
| `docs/` | Conventions, ADRs, operating-loop evidence |

## Verify an image

Every image published to `ghcr.io/mm-weber/dhc` is signed (cosign keyless via
GitHub OIDC) and carries an SPDX SBOM, OpenVEX, and BuildKit provenance:

```sh
REF=ghcr.io/mm-weber/dhc/grafana:13.1.3-alpine3.23
ID='--certificate-identity-regexp github.com/mm-weber/dhc-pipeline
    --certificate-oidc-issuer https://token.actions.githubusercontent.com'

cosign verify $ID "$REF"                                  # signature
cosign verify-attestation $ID --type spdxjson "$REF" \
  | jq -r '.payload | @base64d | fromjson | .predicate'   # SBOM
cosign verify-attestation $ID --type openvex "$REF" \
  | jq -r '.payload | @base64d | fromjson | .predicate'   # VEX, compiled per digest
# needs the buildx CLI plugin — without it docker mis-parses --format and
# prints its top-level usage (Debian/Ubuntu: apt install docker-buildx-plugin)
docker buildx imagetools inspect "$REF" --format '{{ json .Provenance }}'
```

## Triage, recorded

The PR scan gate (Trivy, Grype second opinion on CRITICALs) fails on any
HIGH/CRITICAL not covered by a VEX statement (`not_affected`/`fixed`, with
`govulncheck` reachability evidence) or a time-boxed accepted-risk exception
that decays back to un-triaged on expiry. Every decision is a commit:
[`triage/README.md`](triage/README.md) has the model,
[`triage/LOG.md`](triage/LOG.md) the history — including the retractions.

```mermaid
flowchart TD
    F["HIGH/CRITICAL finding<br/>PR gate or daily rescan"] --> ORDER["queue ordered by EPSS + KEV<br/>ordering only — never a justification"]
    ORDER --> QA{"can the vulnerable<br/>component be removed?"}
    QA -->|yes| AVOID["AVOID<br/>drop it from the image"]
    QA -->|no| QF{"fix available?<br/>upstream release, or go/bump<br/>for from-source images"}
    QF -->|yes| FIX["FIX<br/>version-bump PR,<br/>back through the pipeline"]
    QF -->|no| QN{"provably not applicable?<br/>evidence required — a reachable<br/>symbol forbids the claim"}
    QN -->|yes| VEX["VEX not_affected / fixed<br/>technical claim only, signed and<br/>published with the image;<br/>superseded, never deleted"]
    QN -->|no| ACC["ACCEPT or TRANSFER<br/>time-boxed ≤ 90 days · blocked: rationale<br/>required · transfer needs a named issue<br/>(never written into VEX)"]
    ACC -->|"expiry — acceptance<br/>decays on its own"| F
```

## Operating loop

Self-hosted Renovate (≤6h cron) opens pinned, checksum-recomputed bump PRs;
CI rebuilds, re-scans, and e2e-tests them; a daily rescan of published images
opens issues with severity/EPSS/KEV. See
[`docs/operating-loop.md`](docs/operating-loop.md) for a live trace.

## License

[MIT](LICENSE). Images repackage upstream software under upstream licenses
(noted per definition).
