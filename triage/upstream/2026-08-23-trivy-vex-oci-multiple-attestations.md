# `--vex oci` applies a nondeterministically chosen attestation when an image carries more than one OpenVEX attestation

Target: `aquasecurity/trivy` · Status: draft, under review · Drafted 2026-08-23

## Summary

When an image digest carries several OpenVEX attestations (several layers in
the cosign `sha256-<digest>.att` manifest), `trivy image --vex oci` applies
**one** of them, and which one is not stable: scanning the same unchanged
image repeatedly returns different results. The debug log says
`[vex] VEX attestation found, taking the first one`, but "first" is not the
manifest's first layer, not its last, and not the newest document. A consumer
whose image has been re-attested over time gets a different VEX document on
different runs, with no warning.

We hit this while specifying re-attestation for a small hardened-image
catalogue; our own fix is to keep exactly one OpenVEX attestation per digest
(`cosign attest --replace`). This report is about the consumer side: every
image that has ever been attested twice is affected, and nothing tells the
user.

## Evidence

Measured 2026-08-23 with trivy 0.72.0 (database `ghcr.io/aquasecurity/trivy-db:2`),
cosign v2.6.0, a local `ghcr.io/distribution/distribution:3.0.0` registry, and
`ghcr.io/mm-weber/dhc/hardened-app:0.1.0-alpine3.23` re-pushed as
`localhost:5000/spike/hardened-app@sha256:8eee1329…` (8 HIGH/CRITICAL
findings at baseline). Two documents: **A** has an empty `statements` list;
**B** carries one `not_affected` statement for `CVE-2026-33818` in
`pkg:golang/stdlib` against `pkg:oci/hardened-app@sha256:8eee1329…`. Applied
alone, A leaves 8 findings and B leaves 7 (1 suppressed), stable across runs.
Attestations were made with a local key, `--tlog-upload=false`; the `.att`
manifest's layer order was read back from the registry after each step.

Findings reported by `trivy image --image-src remote --severity HIGH,CRITICAL --vex oci <ref>`,
four consecutive runs, nothing changed between them:

| `.att` layers (manifest order) | Run 1 | Run 2 | Run 3 | Run 4 |
|---|---|---|---|---|
| [A] | 8 | 8 | 8 | 8 |
| [B] | 7 | 7 | 7 | 7 |
| [B, A] | 8 | 8 | 8 | 8 |
| [A, B] | 7 | 7 | 7 | 7 |
| [A, B, A] | 8 | 8 | 8 | 8 (an earlier session: 7) |
| [A, A, B] | 7 | **8** | 7 | 7 |
| [B, C, A] (C is B under another `@id`) | 8 | 8 | 8 | **7** |
| [A, A, A, B] | 7 | 7 | **8** | 7 |

`[B, A]` applied A, so it is not the first layer; `[A, B, A]` applied B in one
session, so it is not the last; `[B, A]` ignored B although B's document
`timestamp` is newer, so it is not the newest. Three of the layer sets changed
answers between runs of an identical registry state.

The script `checks/trivy-vex-oci-multiple-attestations.sh` in this directory
reproduces the table end to end (local registry, control image, key-based
attestations, N scans per layer set).

## What we measured and what we infer

Measured: the behaviour above, on one image and one Trivy version.

Inferred, not measured: the attestations are collected into an unordered
structure before "the first one" is taken, which would explain both the
order independence and the run-to-run variation. We did not read the source
for this report.

## Why it matters to users

Re-attestation is the documented way to update VEX on an already published
digest (a triage decision lands after release, a finding gets fixed upstream),
and `cosign attest` appends by default. Any registry where that has happened
at least once is in the state measured above. The result a user sees then
depends on a coin flip, and the failure is silent: no warning, no hint that
more than one document exists.

## Ask

One of:

- apply **all** OpenVEX attestations on the digest, merged by OpenVEX's own
  rule (latest statement per vulnerability and product wins, by `timestamp`),
  which is what `vexctl merge` does; or
- apply a **deterministic** choice (for example the newest attestation by
  document `timestamp`) and log which one was taken and how many were seen;
- and, in either case, warn when more than one OpenVEX attestation is present.

We are happy to turn the check script into a regression test in whatever
shape the project prefers.
