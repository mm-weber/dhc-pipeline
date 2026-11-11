# A provenance bundle beside a digest hides its signature and attestations from cosign (measured 2026-11-11)

Found in the exploration before task 18.3 (track slsa-build-l2_20261028), before
any release-path code was written. One question: when GitHub's provenance sits
beside a digest as a Sigstore bundle (Decision 15, criterion 2.27, the layout
[ADR 0005](../docs/decisions/0005-slsa-provenance-verifier.md) measured), do
the reads of that digest's cosign signature and SBOM/VEX attestations still
work. The spike of 18.2 could not see this: its scratch image carried a bundle
and nothing else.

## Answer

No, not with the pinned cosign 2.6.5. As soon as one bundle exists for a
digest, cosign reads bundles only for that digest: `cosign verify` verifies
the bundle instead of the `.sig` signature, and `cosign verify-attestation`
never opens the `.att` tag. cosign 2.6.5 has no way back; cosign 3.1.2 has
the same default and a working way back (`--new-bundle-format=false`).

## Where it comes from (cosign v2.6.5 source)

- `cmd/cosign/cli/verify/verify.go` lines 147 to 155 and
  `cmd/cosign/cli/verify/verify_attestation.go` lines 126 to 132: unless the
  bundle format was asked for already, call `cosign.GetBundles` and set
  `co.NewBundleFormat = true` when it returns at least one bundle.
- `pkg/cosign/verify.go` line 1029: with `co.NewBundleFormat` set,
  `VerifyImageAttestations` returns `verifyImageAttestationsSigstoreBundle`
  and the `.att` tag is never read; line 626 does the same for signatures.

## Measurement

- Registry: `crane registry serve` (crane 0.22.1) on `127.0.0.1:5005`, in
  memory. Image `localhost:5005/coex/img@sha256:5e69a8e1b20ea5206c0ff52cb657fdcdaa30f03fada9291aa6cd756ccc410a99`.
- Old layout, as the release path writes it today: `cosign sign` (tag
  `sha256-<hex>.sig`) and `cosign attest --type spdxjson` (tag
  `sha256-<hex>.att`), cosign 2.6.5.
- Then a provenance statement (`https://slsa.dev/provenance/v1`) attached
  with `cosign attest --new-bundle-format`, which writes the tag
  `sha256-<hex>` with no suffix, the place `actions/attest-build-provenance`
  writes to on ghcr.io.
- Signed with a local key pair, `--tlog-upload=false`; verified with
  `--key cosign.pub --insecure-ignore-tlog --allow-insecure-registry
  --trusted-root trusted_root.json`.

| Read | Only `.sig` and `.att` (control) | After the bundle is attached |
|---|---|---|
| cosign 2.6.5 `verify` | exit 0, type `cosign container image signature` | exit 0, but the output's type is `https://slsa.dev/provenance/v1`: it verified the bundle, not the signature |
| cosign 2.6.5 `verify-attestation --type spdxjson` | exit 0 | exit 1, `none of the attestations matched the predicate type: spdxjson, found: https://slsa.dev/provenance/v1` |
| cosign 2.6.5 `verify-attestation --type slsaprovenance1` | not run | exit 0 |
| cosign 2.6.5, both reads with `--new-bundle-format=false` | not run | unchanged: the bundle is read, spdxjson exit 1 |
| cosign 3.1.2, default | not run | same switch: `verify` reports the provenance type, spdxjson exit 1 |
| cosign 3.1.2 with `--new-bundle-format=false` | not run | old layout read again: `verify` exit 0 with type `cosign container image signature`, spdxjson exit 0 |
| cosign 2.6.5, second image `coex/all`, SBOM and provenance both written as bundles | not run | `--type spdxjson` exit 0, `--type slsaprovenance1` exit 0 |

## What it would break in this catalogue

On every digest released with a provenance bundle beside it, with cosign 2.6.5:

- `scripts/package-set-diff.sh` (line 166) cannot read the published
  CycloneDX attestation, answers `different attestation-unreadable`, and
  publish-on-change republishes every time.
- `scripts/fetch-sboms.sh` (line 51), the rescan's SBOM fetch, fails after
  its three attempts.
- `scripts/reattest.sh` (line 179) reads zero previous OpenVEX documents
  (the read ends in `|| true`), so carried-forward statements are lost
  without an error.
- The consumer commands rendered by `scripts/render-verification.sh` into
  `README.md` and `docs/user-manual.md`, and `consumer-smoke.sh` which runs
  them: `cosign verify` passes on the wrong object, the attestation reads
  fail.
- The cosign second opinion in `scripts/verify-catalogue.sh` (lines 165 to
  208).

Kyverno's `Cosign` attestor type is not affected: ADR 0005 measured that it
does not see bundles.

Decision 15's sentence "The comparator, the VEX planes and the re-attester
are untouched: none reads provenance" therefore does not hold with cosign 2.6
or later: none reads provenance, but each one's read of its own attestation
changes once provenance is there.

## Detour in the measurement

Every bundle read first failed with `trusted root is required when using new
bundle format`: the devcontainer's firewall blocks `tuf-repo-cdn.sigstore.dev`.
Cured with `--trusted-root` and `targets/trusted_root.json` from
`sigstore/root-signing`, fetched through the GitHub API. Not part of the
finding.

## Not measured

- Keyless signatures on ghcr.io with GitHub's real bundle (the measurement
  used a key pair and a local registry; the switch is in the reader and
  does not look at how the bundle was signed).
- Trivy's `--vex oci` read on such a digest.
- A bundle pushed to a sibling repository instead of beside the digest.
- Whether cosign upstream regards the switch as a bug.
