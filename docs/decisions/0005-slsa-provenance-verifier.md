# ADR 0005: What verifies the platform's SLSA provenance

Date: 2026-11-11 · Status: **accepted** (spike measured 2026-11-11, runs 43025700201 to 43033859220), **amended 2026-11-13** (the bundle is unpacked into cosign's attestation layout; decision 1 superseded, see the amendment below) · Requirements: Req 2.25, 2.27, 2.28, 2.29, 9.13; design Decision 15; task 18.2 · Leaves ADR 0003's cosign major gate untouched

## Context

Decision 15 (2026-10-28) has the release attest each index and platform
manifest with GitHub's provenance service (`actions/attest-build-provenance`),
because the provenance BuildKit attaches today is written by the job itself
and signed by nobody. That service writes a Sigstore bundle, not the
`sha256-<hex>.att` layout cosign v2 writes and every reader in this
repository expects. Decision 15 therefore left one question open before any
release step is built: which pinned tool verifies that bundle, for the policy
rule of criterion 2.28, for the consumer step of 2.25, for the release's
self-check, the daily coverage report of 2.29 and the smoke test of 9.13. If
the answer had been "only cosign v3", ADR 0003's major gate would have gone
to the owner.

## Spike evidence (GitHub Actions, 2026-11-11)

The full record, with every command, output and exit code, is
[`data/slsa-provenance-spike-2026-11-11.md`](../../data/slsa-provenance-spike-2026-11-11.md).
A scratch image outside `verification.registry`, attested by the action at
`4d101475d8b20a2381f78447822ac1eab6504dd8` (v4.2.2) on one index and one
platform manifest, read with the tools at this repository's pins. Six runs on
pull request #401, which is never merged; the last, 43033859220, carries the
deciding reads.

| Question | Measured |
|---|---|
| Where does the attestation sit? | ghcr.io answers `MANIFEST_UNKNOWN` on the OCI referrers API. The bundle is under the fallback tag `sha256-<subject hex>` in the subject's repository, artifact type `application/vnd.dev.sigstore.bundle.v0.3+json`, readable anonymously |
| Does the predicate carry the five expectations, from the platform's values? | Yes: `runDetails.builder.id`, `buildDefinition.buildType`, and `repository`, `path`, `ref` under `buildDefinition.externalParameters.workflow`; the builder identity equals the signing certificate's identity |
| cosign 2.6.5 `verify-attestation --type slsaprovenance1` | Verifies the index and the platform manifest (exit 0); refuses an identity that did not sign (exit 1). Finds the bundle without a flag. Checks signer and type, not the predicate's fields |
| The five expectations after cosign | One `jq -e` step on the decoded payload: exit 0 as emitted, exit 1 for a ref that was not built |
| Kyverno 1.19.2, `verifyImages` entry of `type: SigstoreBundle` | Admits with the exact signer and the five expectations as conditions; refuses a ref that was not built; refuses an identity that did not sign |
| Kyverno 1.19.2, `type: Cosign` (the published policy's shape) | `no matching attestations`: it does not find the bundle |
| `gh attestation verify --bundle-from-oci` | Exit 0 with a token. Without one it refuses to start inside Actions (exit 4), so whether it needs a login elsewhere is not measured |
| Trivy 0.76.1 | No verb verifies a provenance bundle |

Three of the six runs were detours caused by mistakes in the spike's own
policy (no transparency log named, a wildcard where Kyverno matches exactly,
a `predicate.` prefix on the condition keys). Each was traced to Kyverno's
source at v1.19.2 and is in the record; none changes the design.

## Decision

1. **The policy verifier for criterion 2.28 is the pinned Kyverno, through a
   second `verifyImages` entry of `type: SigstoreBundle`.** The entry names
   the attestation type `https://slsa.dev/provenance/v1`, a keyless attestor
   with the build workflow's exact identity in `subject`, the issuer and
   `rekor.url`, and the five expectations as `Equals` conditions whose keys
   start inside the predicate (`{{ runDetails.builder.id }}`, not
   `{{ predicate.runDetails.builder.id }}`). The existing entry, with the
   signature and the SPDX and OpenVEX attestations, stays as it is: its type
   cannot read the bundle, and the new type is not asked to read cosign's
   layout.
2. **The verifying command everywhere else is cosign 2.6.5 followed by one
   `jq -e` step.** The consumer step (2.25), the release's self-check before
   the tags (task 18.3), `check-provenance.sh` (2.29, task 18.4) and the
   smoke test (9.13) run

   ```sh
   cosign verify-attestation $ISSUER $BUILD --type slsaprovenance1 "$REF" \
     | jq -r .payload | base64 -d \
     | jq -e '<the five expectations, the filter in the record>'
   ```

   with `$ISSUER` and `$BUILD` as the README already defines them. cosign
   answers "signed by the build workflow, of the provenance type"; the `jq`
   step answers "and built from this repository, this workflow file, this
   ref". A step without the `jq` half verifies the signer only and is not the
   step criterion 2.25 asks for.
3. **cosign stays on v2.** The pinned 2.6.5 reads the bundle, so ADR 0003's
   major gate is not triggered and nothing goes to the owner on that account.
4. **`gh attestation verify` and Trivy are not the documented step.** The
   GitHub client would be a second tool beside cosign for one attestation
   type, it was measured with `--owner` only, never against the declared
   identity and expectations, and its behaviour without a login is not
   measured. Trivy cannot do it.
5. **The five expectations, as the policy file will declare them (task
   18.5).** The spike emitted its own workflow file and a pull request ref;
   the release values follow from the same fields and the declared `releaser`
   identity:

   | Expectation | Path in the predicate | Value for a release |
   |---|---|---|
   | builder identity | `runDetails.builder.id` | `https://github.com/mm-weber/dhc-pipeline/.github/workflows/build.yml@refs/heads/main` |
   | build type | `buildDefinition.buildType` | `https://actions.github.io/buildtypes/workflow/v1` |
   | source repository | `buildDefinition.externalParameters.workflow.repository` | `https://github.com/mm-weber/dhc-pipeline` |
   | workflow path | `buildDefinition.externalParameters.workflow.path` | `.github/workflows/build.yml` |
   | ref | `buildDefinition.externalParameters.workflow.ref` | `refs/heads/main` |

   The commit is `buildDefinition.resolvedDependencies[0].digest.gitCommit`;
   it differs per release and is reported, not expected.
6. **Subjects as Decision 15 has them: the index and each platform
   manifest.** Kyverno resolved the Pod's image to the index and admitted on
   the index's attestation; cosign verified the index and the platform
   manifest separately.

## Consequences

- **The rendering gains an entry, not a row.** `render-verification.sh`
  cannot add provenance to the existing `attestations` list; phase 4 renders
  a second `verifyImages` entry when the policy file's provenance mode is
  `required` and none otherwise (the mode of the 2026-11-11 amendment, Req
  2.30; first drafted as `required.attestations` naming SLSA provenance).
  The drift check and the suite hold every shape.
- **`subject` is exact for the bundle type.** The declared `releaser`
  identity is exact already, so nothing changes for this repository. A fork
  that wants a pattern uses `subjectRegExp`; a wildcard in `subject`, which
  the cosign type accepts, refuses everything here and says only "no matching
  signatures found".
- **Each attested digest gains one tag, `sha256-<hex>` without a suffix, in
  its repository.** `enumerate-catalogue.sh` already drops every `sha256-`
  tag, so the supported set and the daily scans are unchanged.
  `check-attestation-count.sh` and `reattest.sh` read `sha256-<hex>.att`
  only: the one-document-per-digest count of ADR 0004 does not see the
  bundle, and the rescan's replacing re-attestation cannot touch it, which
  is what criterion 2.27 wants (the rescan attests no provenance).
- **Verification depends on that tag while ghcr.io serves no referrers API.**
  Deleting it deletes the provenance as far as any verifier can tell. No
  script in this repository deletes tags today; a later retention step has to
  treat `sha256-<hex>` like the `.sig` and `.att` tags beside it.
- **Each attestation also lands in GitHub's attestation store for this
  repository and in Rekor**, as Decision 15 already states for Rekor.
- **The behaviour is measured at Kyverno 1.19.2 and cosign 2.6.5.** Phase 4's
  offline `kyverno apply` (must admit a post-track digest, must reject a
  pre-track one) and the release's self-check keep holding it when Renovate
  moves either pin.
- **Kyverno prints that `kyverno.io/v1` ClusterPolicy is deprecated.** That
  is true of the four published policies today, and the 2.28 rule was
  measured in that kind only. When to migrate is not this decision's to
  settle; it is an open item in `tasks/todo.md`.

## Amendment (2026-11-13): the bundle is unpacked into cosign's attestation layout

Task 18.3's exploration found on 2026-11-11 what this spike had not asked: a
Sigstore bundle beside a digest makes cosign 2.6.5 read bundles only, so that
digest's `.sig` and `.att` disappear for it
([`data/cosign-bundle-coexistence-2026-11-11.md`](../../data/cosign-bundle-coexistence-2026-11-11.md)).
The spike's scratch image carried nothing else, which is why it did not show.
The owner decided on 2026-11-13 (design Decision 15's amendment of that day):
the action runs with `push-to-registry: false`, and
`scripts/unpack-provenance.sh` stores its bundle's envelope, certificate, log
entry and certificate chain as one more layer of the digest's
`sha256-<hex>.att` manifest. Measured on ghcr.io with the tools at this
repository's pins, runs 43402932545 and 43404580566 on #401. What that
changes in this record:

| Above | Now |
|---|---|
| Decision 1: a second `verifyImages` entry of `type: SigstoreBundle` | Superseded. The existing `Cosign` entry reads the unpacked layer: where the mode is `required` it gains a third attestation, type `https://slsa.dev/provenance/v1`, with the build workflow's identity and the five expectations as conditions (the same keys). Measured: admitted alone and in the catalogue-shaped policy; a ref that was not built and an identity that did not sign are refused |
| Decision 2: cosign 2.6.5 and one `jq -e` step | Stands, the command unchanged. cosign now reads the layer from `.att`, with its subject check on |
| Decision 3: cosign stays on v2 | Stands |
| Decision 4: `gh attestation verify` is not the documented step | Stands. Measured in addition: against GitHub's attestation store it passes by owner and by repository and signer workflow; `--bundle-from-oci` finds nothing, as intended |
| Decision 6: subjects | The index and each platform manifest, as before. One statement names them all (the action's `subject-checksums`), measured end to end before the release step is written; one statement per subject is the measured fallback |
| Consequence "the rendering gains an entry, not a row" | Reversed: a row in the existing entry's attestations, rendered when the mode is `required` |
| Consequence "`subject` is exact for the bundle type" | Moot: the `Cosign` type is used. The declared identity stays exact |
| Consequences "each attested digest gains one tag, `sha256-<hex>`" and "verification depends on that tag" | No such tag exists. The provenance depends on the `.att` tag the other attestations depend on |
| Consequence "`check-attestation-count.sh` and `reattest.sh` cannot touch it" | They share the `.att` manifest with it and leave it alone: the count selects OpenVEX layers by predicate type, the re-attestation replaces by type. Measured for OpenVEX: `cosign attest --replace --type openvex` keeps the provenance layer; a second unpack replaces its own layer and adds none |

One finding is new. Kyverno 1.19.2 takes the certificates between the signing
certificate and the root only from the layer's `dev.sigstore.cosign/chain`
annotation: it sets the roots and never the intermediates (read in its source
and in cosign v3.1.2, which it links). Without the annotation it reports the
attestation as not found; with it, it admits. cosign 2.6.5 on the command
line does not need it. The unpack therefore writes it, copied from a layer
cosign wrote into the same manifest and checked to have issued the signing
certificate.

Limits of the route, accepted with the decision: the layer is written by this
repository's script, not by cosign; the route ends with a log that issues no
signed entry timestamp (Rekor v2, refused by name) or with a cosign major
that removes the old layout (announced for v4).

## Confirmed later, not by this spike

- The release values in the table above are derived, not observed: the spike
  ran on a pull request. The first release after task 18.3 confirms them,
  and its self-check fails before any tag if one is wrong.
- cosign was given the identity as a regular expression; the exact
  `--certificate-identity` form is confirmed by the same self-check.
- Whether `gh attestation verify` needs a login outside Actions stays open;
  nothing here depends on it.

## Left behind by the spike

The scratch package `ghcr.io/mm-weber/slsa-spike` (six image tags, twelve
bundle tags), twelve attestations for its digests in this repository's
attestation store, pull request #401 and branch `slsa-spike`. The workspace
token cannot delete package versions; the package is the owner's to delete
(plan task 1.3), and #401 is closed unmerged once this record is merged.
The two runs of 2026-11-13 added image, `.sig` and `.att` tags to the same
package and attestations to the store; #401 stays open, never merged, until
the measurement of plan task 2.1 is read.
