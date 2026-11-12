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
- Whether cosign upstream regards the switch as a bug.
- Whether `actions/attest-build-provenance` can push its bundle to a
  repository that does not hold the subject manifest, and whether Kyverno's
  `repository` field finds a bundle there (see the sibling rows below).

## Follow-up measurements (2026-11-12, at the owner's request)

Same local registry and key pair. Test images carry one Python package
(PyYAML 5.3; the pinned Trivy 0.76.1, vulnerability DB of 2026-10-15,
reports CVE-2020-14343 and CVE-2020-1747, both CRITICAL). VEX document A
marks the first `not_affected`, document B the second, so which document a
reader got is visible in what stays reported.

### Does `cosign attest --replace` work on bundles (ADR 0004's exactly-one rule)

| Case | Sequence | Result |
|---|---|---|
| A0, control: cosign 2.6.5, old layout | attest A, attest SBOM, attest `--replace` B | prints `Replacing attestation predicate: https://openvex.dev/ns`; `.att` holds one OpenVEX layer and the SBOM; read back: B only |
| A1: cosign 2.6.5, `--new-bundle-format` | same | exit 0, no "Replacing" line; the bundle tag lists three bundles; read back: B **and** A |
| A3: cosign 3.1.2, its default layout | attest A, attest `--replace` B | prints `Flag --replace has been deprecated, not needed when OCI referrers become the default behavior`; read back: B **and** A |
| A4: cosign 3.1.2 with `--new-bundle-format=false` | attest A, attest SBOM, attest `--replace` B | prints `Flag --new-bundle-format has been deprecated, this will be the only supported format in future versions`; writes `.att`; replace works; read back: B only; Trivy suppresses per B |

On bundles `--replace` is accepted and does nothing, in both versions: every
re-attestation adds a document.

### Does Trivy 0.76.1 read VEX from the registry (`--vex oci`) when it is a bundle

| Case | Layout | Result |
|---|---|---|
| B0, control | VEX A in `.att` | `VEX attestation found`; CVE-2020-14343 suppressed, CVE-2020-1747 reported |
| B1 | VEX A as a bundle only | `No VEX attestations found`, `VEX filtering is disabled`; both reported, exit 0 |
| B3, the mixed case of this record | VEX A in `.att`, a provenance bundle beside it | `VEX attestation found`; suppression as in B0: Trivy is not affected by the mixed layout |

ADR 0003 measured the same for Trivy 0.72.0 on 2026-08-22; four minor
versions later nothing has changed.

### A provenance bundle in a sibling repository (`COSIGN_REPOSITORY`)

| Writer | Result |
|---|---|
| cosign 2.6.5 `attest --new-bundle-format` with `COSIGN_REPOSITORY` set | the variable is ignored: the bundle lands beside the digest (the mixed case again) |
| cosign 3.1.2 `attest` with `COSIGN_REPOSITORY` set | the bundle lands in the sibling repository; the image's repository keeps `.sig` and `.att` only |

With the bundle in the sibling repository: `cosign verify` and
`verify-attestation --type spdxjson` on the image are unchanged in 2.6.5 and
in 3.1.2 (exit 0, type `cosign container image signature`).
`COSIGN_REPOSITORY=<sibling> cosign verify-attestation --type slsaprovenance1`
exits 0 in 3.1.2 and 1 in 2.6.5 (`no matching attestations`).

## Unpacking the bundle into the old layout (measured 2026-11-12, the owner's question)

Question: instead of storing GitHub's provenance as a bundle beside the
digest, can its parts be written into the `.att` manifest that every reader of
this catalogue already uses?

Answer: yes. With GitHub's real bundle for the spike image (fetched from the
attestation store, `GET /repos/mm-weber/dhc-pipeline/attestations/sha256:59bfa0a8...`,
attestation of run 43025700201) cosign 2.6.5 verifies the unpacked copy
keyless, every other read is unchanged, and no bundle tag exists.

### What a bundle holds and where each part goes

| Part of the bundle (`application/vnd.dev.sigstore.bundle.v0.3+json`) | Place in the old layout |
|---|---|
| `dsseEnvelope` (the signed statement) | the layer's content, media type `application/vnd.dsse.envelope.v1+json`, written as `{"payload":…,"payloadType":…,"signatures":[{"sig":…}]}` without whitespace |
| the statement's `predicateType` (`https://slsa.dev/provenance/v1`) | layer annotation `predicateType` |
| `verificationMaterial.certificate.rawBytes` | layer annotation `dev.sigstore.cosign/certificate` (PEM) |
| `verificationMaterial.tlogEntries[0]`: `canonicalizedBody`, `integratedTime`, `logIndex`, `logId.keyId` (as hex), `inclusionPromise.signedEntryTimestamp` | layer annotation `dev.sigstore.cosign/bundle` (`{"SignedEntryTimestamp":…,"Payload":{"body":…,"integratedTime":…,"logIndex":…,"logID":…}}`) |

The log entry is of kind `dsse` 0.0.1 in the first Rekor log
(`rekor.sigstore.dev`) and carries an inclusion promise (the log's signed
entry timestamp) and an inclusion proof; `timestampVerificationData` is
empty. cosign 2.6.5 compares the entry's `envelopeHash` with the SHA-256 of
the layer (`pkg/cosign/verify.go`, `VerifyBundle` and `bundleHash`), so the
layer must be byte for byte what GitHub's signer sent to the log: the
serialisation above reproduces the logged hash for both spike attestations.

### Measurement

Local registry, a test image signed and attested (SBOM, VEX A) with a key pair
in the old layout, then the unpacked provenance added as a third layer of the
same `.att` manifest.

| Read | Result |
|---|---|
| tags beside the digest | `.sig` and `.att` only |
| cosign 2.6.5 `verify`, `verify-attestation --type spdxjson`, `--type openvex` (key) | exit 0, VEX A read back |
| cosign 2.6.5 `verify-attestation --type slsaprovenance1 --certificate-identity-regexp ^https://github.com/mm-weber/dhc-pipeline/ --certificate-oidc-issuer https://token.actions.githubusercontent.com --offline --check-claims=false` | exit 0; certificate, log entry and signer checked; builder `…/slsa-spike.yml@refs/pull/401/merge`, subject `59bfa0a8…` read back |
| the same with the subject check on | exit 1, `no matching subject digest found` (expected: the local test image is not the spike image) |
| control: another signer demanded | exit 1, `none of the expected identities matched` |
| control: the envelope with the certificate and log entry of the other spike attestation | exit 1, `matching bundle to payload` |
| `cosign attest --replace --type openvex` with VEX B | `Replacing attestation predicate: https://openvex.dev/ns`, `Not replacing attestation predicate: https://slsa.dev/provenance/v1`; VEX B only read back; the provenance still verifies; one OpenVEX layer (the count of `check-attestation-count.sh`) |
| Trivy 0.76.1 `--vex oci` | `VEX attestation found`, suppression per VEX B |
| cosign 3.1.2, its defaults | `verify` exit 0, the provenance exit 0 (with no bundle beside the digest it reads the old layout) |

### Limits

- `cosign attach attestation` cannot do the unpack: it rewrites the envelope
  (other key order, an added `keyid`), the layer no longer hashes to the logged
  value, and it writes neither certificate nor log entry. The manifest is
  written by a script of this repository.
- The old layout carries the log's signed entry timestamp. The public trusted
  root already lists a second log (`log2025-1.rekor.sigstore.dev`, Rekor v2),
  which issues none. When GitHub's signer moves there the unpack stops; the
  script must refuse a bundle without an inclusion promise by name.
- cosign v4 is announced to remove the old layout; then the whole catalogue
  moves to bundles and the provenance is stored as the bundle it is.

### Detour and not measured

- Detour, local only: cosign 2.6.5 refuses `--trusted-root` for the old layout
  (`trusted root path currently only supported with --new-bundle-format`) and
  the devcontainer cannot reach Sigstore's TUF host, so the public roots were
  handed over as files (`SIGSTORE_ROOT_FILE`, `SIGSTORE_REKOR_PUBLIC_KEY`,
  `SIGSTORE_CT_LOG_PUBLIC_KEY_FILE`, taken from the public `trusted_root.json`).
  A runner fetches them itself.
- Not measured: the subject check passing (the spike package is private and
  cannot be pulled here; only the refusal of a different image is measured);
  the unpack on ghcr.io; Kyverno 1.19.2 admitting on the unpacked copy through
  the policy's existing `Cosign` attestation entries with the five
  expectations; `gh attestation verify` against the store with
  `push-to-registry: false`.
