# ADR 0003: One OpenVEX document per published digest, empty when nothing applies

Date: 2026-08-22 · Status: **accepted** (spike measured) · Requirements: Req 2.9, 2.10, 2.23, 6.34 · Review: 2026-08-21 production-readiness critique F3 (i); independent review of PR #97, finding 1.1

## Context

The cluster A amendment (PR #97) makes an OpenVEX attestation a condition of a
digest being published (Req 2.10) and of admission by the verification policy
(Req 2.23, proven daily by Req 2.24). The independent review measured that five
of six catalogue repositories have never carried one: `scripts/compile-vex.sh`
deliberately never writes an emptied document ("a file a scanner reads and
learns nothing from", `compile-vex.sh:153`), and every statement in
`triage/vex/` names grafana, so `build.yml` attests zero OpenVEX documents for
hardened-app, cert-manager and valkey. Under the amendment as drafted a clean
image could never be published and the shipped policy would reject it.

The owner chose, on 2026-08-22, to attest exactly one compiled OpenVEX document
per published digest, with zero statements when nothing applies, over the
alternative of making the OpenVEX clause conditional. A spike was required
first because the OpenVEX specification describes a document as "a data
structure grouping one or more VEX statements" (`OPENVEX-SPEC.md:38`, `:77`)
and marks `statements` as required (`:164`) without a normative minimum, so
whether the tools we depend on accept an empty list was unmeasured.

## Spike evidence (devcontainer, 2026-08-22)

Tool versions: trivy 0.72.0 (vulnerability DB pulled from
`ghcr.io/aquasecurity/trivy-db:2`; the default mirror `mirror.gcr.io` is not on
the firewall allowlist), vexctl v0.4.4, kyverno 1.18.2, cosign v3.1.2 (the
local install) and cosign v2.6.0 (downloaded from the GitHub release and
verified against `cosign_checksums.txt`; it is the version
`sigstore/cosign-installer@d7543c9` installs by default, which is what
`build.yml` runs). grype 0.116.0 is present but its database host
`grype.anchore.io` is not allowlisted, so grype is unmeasured here. Local
registry: `ghcr.io/distribution/distribution:3.0.0` on `localhost:5000`
(Docker Hub's blob CDN was unreachable). Control image: the published
`ghcr.io/mm-weber/dhc/hardened-app:0.1.0-alpine3.23`, re-pushed as
`localhost:5000/spike/hardened-app@sha256:8eee1329…`. Baseline: Trivy reports
39 HIGH/CRITICAL findings on `ghcr.io/mm-weber/dhc/grafana:13.1.3-alpine3.23`
(RepoDigest `sha256:bea44d40…`) and 8 on the control image.

Fixture `empty.openvex.json`: `@context` `https://openvex.dev/ns/v0.2.0`, an
`@id`, `author`, `timestamp`, `version: 1`, `"statements": []`. A second
fixture omits the `statements` key entirely.

| Question | Command | Result |
|---|---|---|
| Does vexctl accept an empty document? | `vexctl merge empty.openvex.json` | exit 0; emits a document with `"statements": []` |
| A document with no `statements` key? | `vexctl merge no-statements-key.openvex.json` | exit 0; emits `"statements": []` |
| Can vexctl merge our source documents into one? | `vexctl merge triage/vex/*.openvex.json` | 3 documents in, 1 out with 4 statements; both CVE-2026-42151 statements kept, so supersession (Req 6.22) survives the merge |
| Does Trivy accept an empty document as `--vex` input? | `trivy image --vex empty.openvex.json grafana:13.1.3-alpine3.23` | exit 0, no error or warning; 39 findings, 0 suppressed, identical to baseline |
| And the keyless fixture? | same with `no-statements-key.openvex.json` | identical |
| Control: the merged source document (tag-scoped products) | `trivy image --vex merged-grafana.json …` | 39 findings, 0 suppressed: tag products match nothing, as `compile-vex.sh:11-12` documents |
| Does cosign v3 attest an empty predicate? | `cosign attest --key … --type openvex --predicate empty.openvex.json --signing-config <no tlog, no TSA>` | attests; `verify-attestation --type openvex` returns predicateType `https://openvex.dev/ns`, 0 statements; stored as a new-format bundle under the tag `sha256-<digest>` (no `.att` suffix) |
| Does Kyverno find the cosign v3 bundle? | `kyverno apply policy-openvex.yaml --resource pod-control.yaml --registry` | **fail**: "no matching attestations" |
| Does Trivy find the cosign v3 bundle? | `trivy image --vex oci …` | "No VEX attestations found" |
| Does cosign v2.6.0 attest an empty predicate? | `cosign attest --key … --type openvex --predicate empty.openvex.json --tlog-upload=false` | attests; tag `sha256-<digest>.att` appears; `verify-attestation` returns predicateType `https://openvex.dev/ns`, 0 statements |
| Does Kyverno admit on an empty OpenVEX attestation? | policy requiring `attestations[].type: https://openvex.dev/ns`, key attestor with `rekor.ignoreTlog` and `ctlog.ignoreSCT` | **pass 2, fail 0** |
| Is the Kyverno check live (negative)? | same policy requiring `https://spdx.dev/Document` | **fail**: "unverified image" |
| Does Trivy consume the empty attestation from the registry? | `trivy image --debug --vex oci …` | `[vex] VEX attestation found, taking the first one`; 8 findings, 0 suppressed, identical to baseline |

Two things were measured that the question did not ask for:

- **cosign v3's default bundle layout is invisible to both consumers we ship
  for.** Kyverno 1.18.2 and Trivy 0.72.0 found nothing until the same
  predicate was attested with cosign v2.6.0 in the legacy `.att` layout. CI
  produces the legacy layout only because `cosign-installer`'s default is
  still v2.6.0; a bump of that default, or of the action's `cosign-release`
  input, would silently detach every consumer from every attestation while
  `cosign verify-attestation` kept passing.
- **Trivy takes the first OpenVEX attestation only** ("taking the first one").
  `grafana:13.1.3-alpine3.23` carries three OpenVEX attestations today, one
  per compiled source file (`build.yml:652-656`), so a `--vex oci` consumer
  sees one of the three documents. Appending a further attestation later
  changes nothing for such a consumer.

## Decision

1. **The compiler emits exactly one OpenVEX document per digest it compiles
   for**, merging every applicable compiled statement from every source
   document, and emits it with `"statements": []` when nothing applies. The
   "never write an emptied document" contract in `compile-vex.sh` is reversed:
   the empty document is itself the machine-readable statement "no known
   finding against this digest has a recorded status", and it is what makes
   "every published digest carries an OpenVEX attestation" a checkable
   invariant rather than a claim that is false for five repositories.
2. **Attestation of that one document is unconditional** (Req 2.9 as revised
   in PR #97): one `cosign attest --type openvex` per digest, no loop over
   files. The rescan's per-digest compile produces the same single document.
3. **Document identity**: `@id` derived from the image and the digest,
   `author` as today, `timestamp` the compile time, `version` 1 at release.
   Supersession between statements stays inside the one document and keeps
   working, since Trivy orders statements by timestamp (design.md, task 7.9
   measurement) and the merge preserves both statements of a superseded pair.
4. **cosign stays on the v2 line, pinned explicitly**: `build.yml` (and
   `rescan.yml` once it attests) set `cosign-release` to an exact v2 version
   with a Renovate manager over the pin (Req 7.5, 7.6), instead of relying on
   the installer's default. A move to v3 bundles happens only when Kyverno and
   Trivy are measured to consume them, and the daily consumer smoke test
   (review F7) is the control that would catch an unmeasured move.

## Consequences

- PR #97, Req 2.9: "... attest its SPDX SBOM and one compiled OpenVEX document,
  carrying every applicable statement or none, to it ...". Req 2.10 and 2.23
  stand as drafted; the independent review's finding 1.1 closes.
- `scripts/compile-vex.sh` and `compile-vex_test.sh`: output becomes one
  document per compile; the test "an emptied document is not written" becomes
  "a document with zero statements is written"; the compile report keeps its
  `compiled` and `dropped` counts, so the gate summary's "statements exist but
  suppressed nothing" logic (Req 6.26 analogue for VEX) is unaffected.
- `build.yml` OpenVEX attest step (`:650-657`): one attestation per digest;
  the step summary counts statements, not files.
- Input to cluster B (review F5 ii): re-attestation by appending is invisible
  to `trivy --vex oci`, which reads the first attestation. Re-attestation has
  to replace (`cosign clean --type attestation` then attest the new single
  document) or the consumer recipe has to merge via `cosign verify-attestation`
  and `vexctl merge`, which the manual already describes. Decide there, not
  here.
- Unmeasured locally, to be measured in CI by the tasks that implement this:
  grype with an empty `--vex` document (database host blocked here); the
  Kyverno keyless attestor against the real `build.yml` identity (no OIDC
  locally; the key attestor measured above exercises the same predicate-type
  match). cosign keyless with v2.6.0 is what CI runs today and is unchanged.

## Amendment, 2026-08-23: "taking the first one" is not "the first one wins"

The evidence section above reads Trivy's log line as a rule: the first
OpenVEX attestation on a digest is applied and later ones are ignored. That
was an inference from a log message, not a measurement, and ADR 0004 measured
it: with several OpenVEX attestations on one digest, `trivy --vex oci` applies
one chosen **nondeterministically**. The same unchanged layer set scanned four
times returned different findings counts (`7 8 7 7`, `8 8 8 7`, `7 7 8 7`),
and no ordering (first, last, newest timestamp) predicts the pick.

The decision here stands and is strengthened: one document per digest is the
only shape under which a consumer's result does not depend on chance. The
consequence bullet "Input to cluster B" is superseded by ADR 0004: the
mechanism is `cosign attest --replace` (which replaces only attestations of
the same predicate type, measured), not `cosign clean --type attestation`,
which would also remove the SBOM and scan-report attestations; and the
consumer recipe needs no merge step once one document is the invariant.
