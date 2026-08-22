# Cluster A revision ledger (PR #97), started 2026-08-22

**Purpose.** One place that holds the state of the cluster A revision so the
work can be picked up at any time without this conversation: every finding
from the independent review (`2026-08-21-cluster-a-independent-review.md`,
numbered 1.1 to 1.17) and every distinct point from the angle reports the
reviewer never saw (`2026-08-21-cluster-a-independent-review-angles.md`,
listed as A1 to A7), each with its current disposition. Decisions are the
owner's, taken one at a time; a row moves from `open` to a decision with the
commit that encodes it. The original review of the catalogue
(`2026-08-21-production-readiness-critique.md`, on `main`) keeps its own
ledger in its section 5; where a revision here reverses one of its recorded
decisions, both documents change in the same commit.

**Order of work.** Blocking findings first (1.1, 1.2), then the structural
ones that change criteria (1.3 to 1.12), then consistency and task fixes
(1.13 to 1.17), then the angle points. Spec text changes land on this branch;
spikes land on their own branch as ADRs, as the repo's spike convention has
it (ADR 0001, ADR 0003).

## Ledger

| # | Finding (short) | Disposition | Where encoded |
|---|---|---|---|
| 1.1 | OpenVEX attestation is a condition of "published" but clean images never get one | **decided 2026-08-22: (a)** one compiled document per digest, empty when nothing applies, attestation unconditional; spike measured | ADR 0003 (PR #98); Req 2.9 rewording pending on this branch |
| 1.2 | Legacy-tag re-point would serve unsigned platform manifests (cosign signed the index only) | open; options: (a) re-publish the ten through the release path, (b) rescan per platform instead of re-pointing (reviewer's and assistant's recommendation; removes Req 2.22 and task 9.5, amends review F9 a), (c) declare unsupported | |
| 1.3 | "Published set" defined but nothing enumerates it; Req 2.6 and 6.2 unmet for older tags | open; proposed Req 2.26: daily enumeration of every catalogue tag and its digest, excluding cosign tags, used by 2.18, 2.22, 2.24 | |
| 1.4 | Req 2.24 tests "published" digests, which by definition cannot fail | open; proposed: test every tag-referenced digest | |
| 1.5 | Switches contradict their default criteria (2.12 vs 2.13, 2.9 vs 2.13, 2.15 vs 2.17); 2.13 never forbids signing | open; proposed WHILE guards on the defaults, 2.12 split by actor, "sign nothing" added to 2.13 | |
| 1.6 | "Platform manifest" undefined; every index carries an `unknown/unknown` attestation manifest | open; proposed definition line under Req 2; drop "more than one" from 6.36 | |
| 1.7 | A failed release-time scan is unspecified | open; proposed Req 2.9a (no report, no sign, no tag, red run) plus error-table rows | |
| 1.8 | One SBOM per index versus per-platform comparison; attestations invisible to platform-digest pinners | open; proposed per-platform SBOM attestation; measure `cosign sign --recursive` in 9.1 | |
| 1.9 | Flow diagram: compile after scan, discard after sign/attest | open; proposed: comparison before push, two compile passes drawn | |
| 1.10 | Schedule never reaches the matrix; Req 2.7's trigger excludes schedule and dispatch | open; proposed Req 2.7 trigger rewording plus `changes`-job change in task 9.2 | |
| 1.11 | Policy admits the rescan identity for signatures | open; proposed: split identities by role (build signs; build or rescan attests) | |
| 1.12 | Undefined terms: catalogue tag, full release tag, unsigned control image, signature identity in 2.10; 2.15/2.16 silent with no prior digest; which package set | open | |
| 1.13 | Design asserts as built what is only specified; old diagrams; stale 8.3 pointers; contradictory visibility bullets | open | |
| 1.14 | Req 2.1 and 2.20 coexist without a note; Req 2.2 dangling; provenance not required by 2.10/2.23; 2.20's WHILE untestable | open | |
| 1.15 | Req 2.21 measures a token, the design promises a pull; unconditional against Req 2.4's private phase | open; proposed manifest GET plus WHILE public release is enabled | |
| 1.16 | Two-actor criterion 2.12 | folded into 1.5 | |
| 1.17 | Task inaccuracies: buildx output needs `name=`, Kyverno predicate-type URIs, `kyverno apply --registry`, 8.3 open beside 9.3, todo wording | open | |
| A1 | Reproducible builds never weighed against publish-if-changed | open; proposed: measure `SOURCE_DATE_EPOCH` against the DHI frontend or record as rejected in Decision 6 | |
| A2 | `under_investigation` statements derive from an unpersisted scan report | open; proposed: persist the release-time report (artifact or attestation) so the compiled document is reproducible | |
| A3 | "Declared" switches have no declared location | open; candidate home: cluster B's `triage/policy.yaml` | |
| A4 | Scan each platform manifest by its own digest rather than `--platform` plus `--image-src remote` | open; task 9.1/9.3 wording | |
| A5 | Req 2.21 belongs to one daily-invariants mechanism | open; cluster D shape | |
| A6 | Req 6.35 implied by 6.1; coverage predicate copied three times; 2.19/2.20/2.22 are one invariant | open; reviewer keeps 6.35; "uncovered finding" defined once is the candidate | |
| A7 | Req 2.24's "daily checks" is a third name for the run; Req 2.9 gates tagging on attestations but not the signature | open; fold into 1.5 and 1.12 wording | |

## Spike results to carry (ADR 0003, 2026-08-22)

- Empty `statements` lists are accepted by vexctl v0.4.4, trivy 0.72.0 (file
  and `--vex oci`), cosign v2.6.0 and v3.1.2, kyverno 1.18.2; Trivy findings
  unchanged; Kyverno admits, and rejects a missing predicate type.
- cosign v3's default bundle layout is invisible to Kyverno 1.18.2 and Trivy
  0.72.0; CI is on cosign v2.6.0 only by the installer's default. Pin it
  (Req 7.5/7.6) and let the F7 consumer smoke test guard the format.
- Trivy `--vex oci` reads the first OpenVEX attestation only; grafana carries
  three today. One document per digest is required; cluster B's
  re-attestation must replace, not append.
- Unmeasured locally: grype with an empty document; Kyverno keyless attestor.

## Working notes

- 2026-08-22: ledger created; choice 1 decided; choice 2 (finding 1.2) is the
  open question.
