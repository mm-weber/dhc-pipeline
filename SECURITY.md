# Security policy

What the catalogue at `ghcr.io/mm-weber/dhc` promises, what its signatures
mean, how it is governed, where to report a vulnerability, and where its
records live. Every number below is a dated snapshot of a value whose home is
elsewhere; the home wins.

> This repository is a proving ground that will be archived intact once its
> implementation tasks complete; the catalogue restarts as a successor
> repository (README, top). Everything below holds for the digests this
> repository has published and keeps holding after archival.

## The promise

A transparency catalogue. One maintainer can keep it unconditionally because
automation produces the status and the human supplies only decisions:

1. **Every published digest is signed by a pinned identity**: this
   repository's release workflow on `main`, through GitHub's OIDC issuer.
   The identities live in `catalogue-policy.yaml` (`verification`) and are
   rendered, unedited, into the verification policy under `policies/` and the
   consumer recipe in the README ("Verify an image").
2. **Every known finding within the decision aperture against a supported
   digest carries a published, machine-readable status**: an OpenVEX
   statement (`not_affected`, `fixed`, `affected` with an action statement,
   or `under_investigation` with the scan's timestamp) attested to the
   digest, exactly one OpenVEX attestation per digest.
3. **Time to decision and time to fix are measured and published** as
   numbers in the status issue, not promised as service levels.

Not promised: remediation windows, an on-call duty, a second reviewer. A fork
with staff reaches those by changing numbers and the committed ruleset, not
the machinery.

## Decision aperture and ceilings

Declared in `catalogue-policy.yaml`, section `triage`, the only home of these
values; the scan gate, the exception lint, the issue filer and the status
clocks all read them there. Snapshot 2026-09-07: the aperture is CRITICAL and
HIGH; an accepted-risk exception runs at most 30 days (CRITICAL) or 90 days
(HIGH) from its decision date, and 14 days for anything CISA's KEV catalogue
lists; the rescan warns 14 days before an exception lapses. A finding outside
the aperture gets no issue and no clock.

## Digest states, the epoch, retention

- A **catalogue tag** is a tag derived from a definition
  (`<version>-<base>[-<variant>]`). cosign's `.sig` and `.att` tags are not.
- **Published**: a digest a catalogue tag references that carries a keyless
  signature, an SPDX SBOM attestation, an OpenVEX attestation and BuildKit
  provenance.
- **Supported**: a digest referenced by a tag its definition currently lists
  in `tags:`. Only supported digests hold issues, clocks and public counts.
- **Superseded**: a tag-referenced digest outside the supported set. It keeps
  its daily scans, attestations and verification and holds no issues, because
  a frozen digest's content never changes and its findings accrue by design.
- **Frozen**: a digest no catalogue tag references. Pullable by digest, not
  rescanned, not re-attested, its last attestations left as they were.

**Epoch.** This repository has none of its own. Its promise machinery has run
in full since 2026-09-01 (release by digest, scanned before it is signed and
tagged) and 2026-09-02 (every platform manifest of every tag-referenced digest
scanned daily). Digests published before those dates form a legacy stratum:
signed at the index only, their platform manifests unsigned, enumerated and
scanned daily since 2026-09-02 but never re-signed. The epoch the promise
attaches to is the successor repository's first release; this repository is
archived intact.

**Retention from the epoch: nothing is deleted.** A catalogue tag is never
removed except through a recorded revocation; it moves forward as its
definition releases, and the digest it leaves becomes frozen and stays
pullable. Package versions are not deleted (GitHub refuses it for a public
version past 5,000 downloads in any case). The industry's two poles, a
180-day grace after end of life and a paid five-year extended support, are
both stronger promises than this one and are a fork's numbers to set.

## What a signature attests, and what it does not

A signature attests exactly this: this repository's release workflow
(`build.yml` on `main`; `rescan.yml` on `main` for re-attestations) produced
or re-attested this digest, and, since 2026-09-01, that the pushed digest was
scanned with the same VEX and exception inputs the pull-request gate uses
before it was signed and tagged. The SBOM, scan-report and OpenVEX
attestations are that run's outputs, bound to the digest.

It does not attest that a second human reviewed the change (there is one
maintainer, below), that the image is free of vulnerabilities (the OpenVEX
attestation says which are known and what was decided), that upstream's
release is authentic beyond the declared class below, or that the build is
reproducible (BuildKit provenance is attached, not verified by the policy).

## Governance: one maintainer, the bypass kept in force

One maintainer. The ruleset on `main` (measured 2026-09-07) requires five
status checks (the lint battery, the Go modules, the render and policy gate,
the build gate, the e2e gate) and one approving review, and grants the
repository administrator an always-on bypass. Every merge is therefore a
recorded bypass of the one-review rule. The bypass is kept deliberately: with
one person, a review nobody else can give would be theatre, and a protected
release environment with required reviewers would put a human approval point
on nightly rebuilds, which a catalogue must not have. The required checks are
the gate. A second maintainer flips `require_code_owner_review` in the
committed ruleset, and the bypass becomes an exception instead of the rule.
The intended ruleset is committed as `.github/rulesets/main_sec.json` in
GitHub's export format and compared daily against the live one through
anonymous reads, both directions, so a retired ruleset that returns is caught;
`CODEOWNERS` names the maintainer per lane.

## Reporting a vulnerability

Report vulnerabilities in the catalogue's machinery, its definitions or its
published images through GitHub private vulnerability reporting on this
repository (Security tab, "Report a vulnerability"). Do not open a public
issue for an undisclosed vulnerability. The daily rescan asserts that the
channel stays enabled and fails by name when it is not; if the Security tab shows no
"Report a vulnerability" button, the channel is off and this policy is not
being kept.

Vulnerabilities in the upstream software the images ship are not this
catalogue's to fix; they enter through the scanners and receive a recorded
status. A published status you believe is wrong is a report for this channel
too.

## Advisories

Catalogue-level advisories (a revoked digest, a wrong published status, a
compromised input) are published as GitHub repository security advisories on
this repository. None has been published as of 2026-09-07.

## Revocation

The record is [`triage/revocations.yaml`](triage/revocations.yaml): one entry
per revoked digest with the digest, the reason, the replacement digest or a
recorded absence of one (and then the move taken, version deletion or a
tombstone), the advisory link and the date, schema-checked in CI. The runbook
is [`docs/revocation-runbook.md`](docs/revocation-runbook.md); it names the
moves GHCR actually has. The daily rescan fails by name while any catalogue
tag still references a recorded digest, and the status issue lists every
entry. No digest has been revoked.

## Upstream authenticity, per definition

Each definition declares beside its source how its upstream's authenticity is
established. The refresh verifies the declared signal before it writes any
field of a bump, the pull-request gate re-verifies repackage checksums, and
the daily rescan re-verifies every definition and files a `supply-chain`
issue on a mismatch.

| Definition | Class | What it means |
|---|---|---|
| cert-manager-controller, cert-manager-webhook, cert-manager-cainjector | `signed-tag` | an annotated tag GitHub reports as verified |
| valkey, valkey-compat | `signed-commit` | a lightweight tag on a commit GitHub reports as verified |
| hardened-app | `signed-commit` | the same, since v0.1.1 (2026-09-06) |
| grafana | `cross-origin-checksum` | grafana.com's versions API and the dl.grafana.com sidecars state the same per-architecture checksum; grafana publishes no signature for its tarballs, so this is agreement of independent origins, not a signature |

The trust-boundary table in [`docs/concepts.md`](docs/concepts.md#trust-boundary-who-owns-what-and-where-the-seams-are)
lists every other component with its owner class and its declared seam
alternative.

## Transparency-log disclosure

Signing is keyless: every signature and attestation is recorded in the public
Sigstore transparency log (Rekor) and stays there whether or not it is later
replaced (measured 2026-09-04: the entries of replaced OpenVEX attestations
still answered from the log). Each entry discloses the signed digest, the
signing identity (this repository, the workflow file and its ref) and the
time. Which digests exist, when they were built and when their statements
changed is therefore public information, independent of registry visibility.
The attestation bodies (SBOMs, scan reports, OpenVEX) are served by the
registry, public since 2026-08-13.

## Substrate redistribution terms

Every runtime image is built with Docker Hardened Images tooling and packages
and contains DHI-origin content, licensed under the Apache License 2.0
(Copyright 2025 Docker Inc.). The catalogue meets that licence's conditions:
[`NOTICE`](NOTICE) names the copyright and licence,
[`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt) is the licence text, and
third-party packages carry their own upstream licences, enumerated in the
SBOMs attested to each platform manifest. The evidence is
[`data/dhi-terms-2026-08-21.md`](data/dhi-terms-2026-08-21.md), a
documentation and licensing analysis dated 2026-08-21, not legal advice. Its
residual ambiguity, stated as it states it: the Docker Subscription Service
Agreement's section 2.1 "not on a standalone basis" restriction and the
Apache-2.0 standalone-redistribution grant are not reconciled in any single
Docker document; the memo takes the position that Apache-2.0 governs the
Community images and flags the point as unresolved. Its sources are
re-verified by 2026-11-21. "Docker" and "Docker Hardened Images" are Docker,
Inc.'s names, used here descriptively; this catalogue is not affiliated with,
sponsored by or endorsed by Docker, Inc.

## Status

The catalogue status issue, rewritten in place by every rescan, carries the
clocks and the current counts:
https://github.com/mm-weber/dhc-pipeline/issues/151.
