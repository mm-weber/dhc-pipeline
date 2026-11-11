# SLSA provenance from GitHub's provenance service: what verifies it (spike, 2026-11-11)

Task 18.2, phase 1 of track slsa-build-l2_20261028, the input to
[ADR 0005](../docs/decisions/0005-slsa-provenance-verifier.md). One question:
when `actions/attest-build-provenance` attests an image, which of this
repository's pinned tools can verify that attestation against the signer and
against the five expectations of criterion 2.28, and where does the
attestation sit.

## Setup

- Workflow `.github/workflows/slsa-spike.yml` on branch `slsa-spike`, pull
  request #401, never merged. A `workflow_dispatch` is only offered for a
  workflow on the default branch, so the runs fired on the pull request
  (`refs/pull/401/merge`).
- Image: `FROM scratch` plus one text file, `linux/amd64` and `linux/arm64`,
  pushed to `ghcr.io/mm-weber/slsa-spike:run-<run id>`, outside
  `verification.registry` (`ghcr.io/mm-weber/dhc`); the workflow refuses to
  run against a repository inside it. BuildKit's own provenance and SBOM off,
  so the reads see the platform's attestation and nothing else.
- Attested with `actions/attest-build-provenance` at
  `4d101475d8b20a2381f78447822ac1eab6504dd8` (v4.2.2), `push-to-registry:
  true`, two subjects per run: the index and the amd64 platform manifest.
  Job permissions `contents: read`, `packages: write`, `id-token: write`,
  `attestations: write`.
- Verifiers installed by `scripts/install-tool.sh` and
  `scripts/install-scanners.sh` at this repository's pins: cosign 2.6.5,
  Kyverno 1.19.2, Trivy 0.76.1 (the track was drafted against Kyverno 1.19.1
  and Trivy 0.72.0; the pins moved with #393 and #280). `gh` as preinstalled on
  `ubuntu-24.04`.
- No catalogue repository was touched.

## The runs

| Run | Head | Result | What it settled |
|---|---|---|---|
| 43024995655 | 4c5f8fb | failed in the reads | detour: the step died on the referrers API's "manifest unknown" (`jq` exit 5 on a null); the image and both attestations exist |
| 43025700201 | 51a6328 | success | where the bundle sits, the predicate as emitted, cosign, `gh attestation verify`, Trivy; Kyverno skipped the policy (detour 1) |
| 43031222803 | 89731ce | success | Kyverno refused all four reads (detour 2) |
| 43033051369 | 8aab8e5 | success | Kyverno, signer only: the bundle shape admits the signer and refuses a non-signer; the cosign shape finds nothing |
| 43033444043 | ce6aa73 | success | Kyverno, conditions added: every condition failed to resolve (detour 3) |
| 43033859220 | 6a53715 | success | Kyverno, signer and the five expectations, with a control for each; cosign on the platform manifest and with a non-signing identity |

Digests: run 43025700201 index `sha256:e402973b15701611c8fb40f780f34b3bfe43542d65dbf3eaac211b72413ca8eb`,
amd64 `sha256:59bfa0a82b86fa652e8f437bf1f03e399049c82bd3b4c0e1d0dc3d8db914f5ac`,
attestations 66281853 and 66281890 in GitHub's store; run 43033859220 index
`sha256:c62e6089cb26dfbdbc98e678166ace6b6580ce2a6aba28a2af95fb2d8edc3d10`,
amd64 `sha256:36a127b7f0a1bf09c62fa7bffa814a23bf34d3fba677ee884e8e16761de7762d`.

The job log is served from a host the devcontainer's firewall does not reach,
and a job summary is not served by the REST API. Run 43025700201 was read from
the summary page the owner pasted; the later runs say each deciding read as a
workflow notice, read through `GET check-runs/<id>/annotations`.

## Where the attestation sits

ghcr.io does not serve the OCI referrers API. For both subjects:

```json
{ "errors": [ { "code": "MANIFEST_UNKNOWN", "message": "manifest unknown" } ] }
```

The action also pushes the referrers fallback tag, `sha256-<subject hex>`
(no suffix), in the subject's repository. It is an OCI index with one entry
per attestation, read anonymously:

```json
{
  "mediaType": "application/vnd.oci.image.index.v1+json",
  "manifests": [
    {
      "artifactType": "application/vnd.dev.sigstore.bundle.v0.3+json",
      "digest": "sha256:1366cd7daabddae83e262de19d01214c9a6c37f3b7823c416a622dff8d276f18",
      "annotations": {
        "org.opencontainers.image.created": "2026-11-11T13:03:59.213Z",
        "dev.sigstore.bundle.content": "dsse-envelope",
        "dev.sigstore.bundle.predicateType": "https://slsa.dev/provenance/v1"
      }
    }
  ]
}
```

That manifest's one layer is the Sigstore bundle; its DSSE envelope's payload
is the in-toto statement. This is not cosign v2's layout: the catalogue's
signatures and attestations sit under `sha256-<hex>.sig` and
`sha256-<hex>.att`, and nothing was written there. After six runs the scratch
repository holds six `run-*` tags and twelve `sha256-<hex>` tags, one per
subject. Each attestation is also held in GitHub's attestation store for this
repository (`GET /repos/mm-weber/dhc-pipeline/attestations/<subject digest>`
returns it) and in Rekor.

## The predicate as emitted

Statement of run 43025700201's index, decoded from the bundle, complete:

```json
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [
    {
      "name": "ghcr.io/mm-weber/slsa-spike",
      "digest": { "sha256": "e402973b15701611c8fb40f780f34b3bfe43542d65dbf3eaac211b72413ca8eb" }
    }
  ],
  "predicateType": "https://slsa.dev/provenance/v1",
  "predicate": {
    "buildDefinition": {
      "buildType": "https://actions.github.io/buildtypes/workflow/v1",
      "externalParameters": {
        "workflow": {
          "ref": "refs/pull/401/merge",
          "repository": "https://github.com/mm-weber/dhc-pipeline",
          "path": ".github/workflows/slsa-spike.yml"
        }
      },
      "internalParameters": {
        "github": {
          "event_name": "pull_request",
          "repository_id": "1305041404",
          "repository_owner_id": "112621871",
          "runner_environment": "github-hosted"
        }
      },
      "resolvedDependencies": [
        {
          "uri": "git+https://github.com/mm-weber/dhc-pipeline@refs/pull/401/merge",
          "digest": { "gitCommit": "f71429f8d9aa29acaca5ee929a65b1f34777a118" }
        }
      ]
    },
    "runDetails": {
      "builder": {
        "id": "https://github.com/mm-weber/dhc-pipeline/.github/workflows/slsa-spike.yml@refs/pull/401/merge"
      },
      "metadata": {
        "invocationId": "https://github.com/mm-weber/dhc-pipeline/actions/runs/43025700201/attempts/1"
      }
    }
  }
}
```

Criterion 2.28's five expectations, where each one sits and what the spike
emitted:

| Expectation | Path in the predicate | Emitted |
|---|---|---|
| builder identity | `runDetails.builder.id` | `https://github.com/mm-weber/dhc-pipeline/.github/workflows/slsa-spike.yml@refs/pull/401/merge` |
| build type | `buildDefinition.buildType` | `https://actions.github.io/buildtypes/workflow/v1` |
| source repository | `buildDefinition.externalParameters.workflow.repository` | `https://github.com/mm-weber/dhc-pipeline` |
| workflow path | `buildDefinition.externalParameters.workflow.path` | `.github/workflows/slsa-spike.yml` |
| ref | `buildDefinition.externalParameters.workflow.ref` | `refs/pull/401/merge` |

The commit criterion 2.27 names is `buildDefinition.resolvedDependencies[0].digest.gitCommit`.
The builder identity equals the signing certificate's identity
(`https://github.com/<GITHUB_WORKFLOW_REF>`). No field carries a value a step
of the job wrote.

## cosign 2.6.5

```
$ cosign verify-attestation --type slsaprovenance1 \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    --certificate-identity-regexp ^https://github.com/mm-weber/dhc-pipeline/ \
    ghcr.io/mm-weber/slsa-spike@sha256:e402973b…
Verification for ghcr.io/mm-weber/slsa-spike@sha256:e402973b… --
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - Existence of the claims in the transparency log was verified offline
  - The code-signing certificate was verified using trusted certificate authority certificates
{"payload":"<the statement, base64>","payloadType":"application/vnd.in-toto+json","signatures":[…]}
(exit 0)
```

| Read | Run | Exit | Output |
|---|---|---|---|
| the index, the signing repository's identities | 43025700201 | 0 | as above |
| the amd64 platform manifest, same identities | 43033859220 | 0 | the same three checks |
| the index, an identity that did not sign (`…/dhc-pipeline-not/`) | 43033859220 | 1 | `no matching attestations: failed to verify certificate identity: no matching CertificateIdentity found` |

No flag for the bundle format was passed. cosign v2.6.5's
`cmd/cosign/cli/verify/verify_attestation.go` asks the registry for bundles
first (`cosign.GetBundles`) and switches to the bundle format when it finds
one. cosign checks the signer and the predicate type and prints the statement;
it does not compare the predicate's fields. The five expectations take one
`jq -e` step on the decoded payload. The filter, run on the statement above:

```
jq -e --arg id … --arg repo … --arg path … --arg ref … '
  .predicateType == "https://slsa.dev/provenance/v1" and (.predicate
  | .runDetails.builder.id == $id
    and .buildDefinition.buildType == "https://actions.github.io/buildtypes/workflow/v1"
    and (.buildDefinition.externalParameters.workflow
         | .repository == $repo and .path == $path and .ref == $ref))'
```

`true`, exit 0 with the values as emitted; `false`, exit 1 with
`refs/heads/main` as the ref (a ref that was not built). The filter was run in
the devcontainer on the decoded statement, not in the workflow. The spike
passed the identity as a regular expression; the exact form
(`--certificate-identity`) that the README uses for the other attestation
types was not run against a bundle and is confirmed by phase 2's release
self-check.

## Kyverno 1.19.2

`kyverno apply <policy> --resource <pod>` offline, the Pod naming the image by
its index digest. One `kyverno.io/v1` ClusterPolicy with one `verifyImages`
entry; the reads differ in the entry's `type`, the attestor's identity field
and the expected ref:

```yaml
verifyImages:
  - type: SigstoreBundle
    imageReferences: ["ghcr.io/mm-weber/slsa-spike*"]
    attestations:
      - type: https://slsa.dev/provenance/v1
        attestors:
          - entries:
              - keyless:
                  subject: "https://github.com/mm-weber/dhc-pipeline/.github/workflows/slsa-spike.yml@refs/pull/401/merge"
                  issuer: https://token.actions.githubusercontent.com
                  rekor:
                    url: https://rekor.sigstore.dev
        conditions:
          - all:
              - key: "{{ runDetails.builder.id }}"
                operator: Equals
                value: "https://github.com/mm-weber/dhc-pipeline/.github/workflows/slsa-spike.yml@refs/pull/401/merge"
              - key: "{{ buildDefinition.buildType }}"
                operator: Equals
                value: "https://actions.github.io/buildtypes/workflow/v1"
              - key: "{{ buildDefinition.externalParameters.workflow.repository }}"
                operator: Equals
                value: "https://github.com/mm-weber/dhc-pipeline"
              - key: "{{ buildDefinition.externalParameters.workflow.path }}"
                operator: Equals
                value: ".github/workflows/slsa-spike.yml"
              - key: "{{ buildDefinition.externalParameters.workflow.ref }}"
                operator: Equals
                value: "refs/pull/401/merge"
```

Run 43033859220, index `sha256:c62e6089…`:

| Read | `type` | Identity | Expected ref | Exit | Output |
|---|---|---|---|---|---|
| the signer and the five expectations | `SigstoreBundle` | `subject`, exact | as built | 0 | `pass: 2, fail: 0` |
| a ref that was not built | `SigstoreBundle` | `subject`, exact | `refs/heads/main` | 1 | `attestation checks failed for ghcr.io/mm-weber/slsa-spike@sha256:c62e6089… and predicate https://slsa.dev/provenance/v1` |
| a pattern for the identity | `SigstoreBundle` | `subjectRegExp: ^https://github.com/mm-weber/dhc-pipeline/.*` | as built | 0 | `pass: 2, fail: 0` |
| an identity that did not sign | `SigstoreBundle` | `subject`, exact, `…-not` | as built | 1 | `sigstore bundle verification failed: no matching signatures found` |
| today's rendered shape | `Cosign` | `subject`, exact | as built | 1 | `no matching attestations` |

So the `SigstoreBundle` type reads the bundle, holds the signer and holds the
five expectations, and each refusal has a passing counterpart. The `Cosign`
type, which the published policy uses for the signature and the SBOM and
OpenVEX attestations, does not find the bundle at all.

Every read also printed Kyverno's notice that `kyverno.io/v1` ClusterPolicy is
deprecated in favour of its newer policy kinds. The four published policies
are of that kind already and the newer kinds were not measured; it is an open
item in `tasks/todo.md`.

### Three detours, all mistakes in the spike's policy, none in the design

1. **No transparency log named** (run 43025700201). Kyverno skipped the policy:
   `Either Rekor URL or roots are required`. A keyless attestor has to name
   one; `scripts/render-verification.sh` already renders `rekor.url`.
2. **A wildcard in `subject`** (run 43031222803). All four reads refused. The
   `SigstoreBundle` type matches `subject` exactly: Kyverno v1.19.2's
   `pkg/image/verifiers/cpol/cosign/sigstore.go` builds the identity with
   `verify.NewShortCertificateIdentity(opts.Issuer, opts.IssuerRegExp,
   opts.Subject, opts.SubjectRegExp)`. A pattern belongs in `subjectRegExp`.
   An identity mismatch surfaces only as "no matching signatures found".
3. **A `predicate.` prefix on the condition keys** (run 43033444043). Every
   condition failed: `failed to resolve predicate.runDetails.builder.id`.
   `EvaluateConditions` in `pkg/engine/internal/utils.go` puts the predicate
   itself into the context, so a key starts inside it.

## gh attestation verify

```
$ gh attestation verify oci://ghcr.io/mm-weber/slsa-spike@sha256:e402973b… --owner mm-weber --bundle-from-oci
(exit 0)
```

with the job's token. With `GH_TOKEN` emptied the client did not start:

```
gh: To use GitHub CLI in a GitHub Actions workflow, set the GH_TOKEN environment variable.
(exit 4)
```

That is the client's guard inside Actions, not an answer from the registry or
the attestation store. Whether it verifies without a login outside Actions was
not measured.

## Trivy 0.76.1

No verb verifies a provenance bundle. Its attestation-related subcommands are
`sbom` (scan an SBOM) and `vex`.

## What is left behind

- Package `ghcr.io/mm-weber/slsa-spike`: six `run-*` tags and twelve
  `sha256-<hex>` tags. The workspace token cannot list or delete package
  versions (`403 Resource not accessible by personal access token`); the
  deletion is the owner's (plan task 1.3).
- Twelve attestations in this repository's attestation store, two per run,
  for digests of the scratch image only. They name no catalogue digest.
- Twelve Rekor entries, permanent by design (Req 9.1's disclosure covers
  keyless signing).
- Pull request #401 and branch `slsa-spike`, closed and deleted unmerged once
  ADR 0005 is merged.
