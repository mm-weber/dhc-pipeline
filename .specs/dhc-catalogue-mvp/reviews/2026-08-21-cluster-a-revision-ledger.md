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
| 1.1 | OpenVEX attestation is a condition of "published" but clean images never get one | **decided 2026-08-22: (a)** one compiled document per digest, empty when nothing applies, attestation unconditional; spike measured | ADR 0003 (PR #98); Req 2.9 reworded; tasks 9.1 (single document, cosign v2 pin) |
| 1.2 | Legacy-tag re-point would serve unsigned platform manifests (cosign signed the index only) | **decided 2026-08-22: (b)** scan in place via the daily enumeration; no re-point; critique F9 (a) amended | Req 2.22 replaced by the enumeration criterion; task 9.5 rewritten; design Decision 6 and platform section; critique 5.2 F9 amendment |
| 1.3 | "Published set" defined but nothing enumerates it; Req 2.6 and 6.2 unmet for older tags | **decided 2026-08-22** as the mechanism of 1.2 (b): daily enumeration of every catalogue tag and its digest, feeding 2.18, 2.21, 2.24 | Req 2.22 (new text), Req 2.18 reworded; task 9.3 |
| 1.4 | Req 2.24 tests "published" digests, which by definition cannot fail | **decided 2026-08-22**: the proof runs over every tag-referenced digest plus one unsigned control digest under a catalogue repository | Req 2.24 reworded; task 9.6 names the control |
| 1.5 | Switches contradict their default criteria (2.12 vs 2.13, 2.9 vs 2.13, 2.15 vs 2.17); 2.13 never forbids signing | **decided 2026-08-22**: 2.12 guarded on the fail-closed setting being disabled and reduced to the VEX Compiler's behaviour (the release completing is 2.9); 2.9 guarded on 2.13 not withholding; 2.13 signs nothing too; 2.15 guarded on the if-changed policy | Req 2.9, 2.12, 2.13, 2.15 |
| 1.6 | "Platform manifest" undefined; every index carries an `unknown/unknown` attestation manifest | **decided 2026-08-22**: terms paragraph under Req 2 (catalogue tag, full release tag, platform manifest); "more than one" dropped from 6.36; 2.18 covers single-manifest digests | Req 2 terms paragraph; Req 6.36; Req 2.18 |
| 1.7 | A failed release-time scan is unspecified | **decided 2026-08-22**: Req 2.26 (no report for any platform manifest: sign nothing, tag nothing, red run); 2.9 requires a report per platform manifest; error-table rows still to add (1.13) | Req 2.9, 2.26; task 9.1 |
| 1.8 | One SBOM per index versus per-platform comparison; attestations invisible to platform-digest pinners | **decided 2026-08-22: (a)** sign index and platform manifests recursively; one SBOM per platform manifest attested to it; the OpenVEX document attested to index and manifests; `cosign attest --recursive` measured in 9.1 | Req 1.9, 2.9, 2.15; design Decision 6 and flow; tasks 9.1, 9.2 |
| 1.9 | Flow diagram: compile after scan, discard after sign/attest | **decided 2026-08-22**: comparison before the push (nothing pushed, signed or attested for an unchanged rebuild), two compile passes drawn, both red-run shapes drawn | design Release flow; Req 2.15; task 9.2 |
| 1.10 | Schedule never reaches the matrix; Req 2.7's trigger excludes schedule and dispatch | **decided 2026-08-22**: 2.7 triggers on any release build (merge, schedule, dispatch); `changes` job gains a schedule branch | Req 2.7; task 9.2 |
| 1.11 | Policy admits the rescan identity for signatures | **decided 2026-08-22: (a)** two roles as extensible attestor lists: releaser (`build.yml`) signs, attests SBOM and the first OpenVEX; re-attester (`rescan.yml`, from cluster B) attests OpenVEX only; critique F6 amended | Req 2.20, 2.23, 2.25; design Decision 6 and security bullet; task 9.6 |
| 1.12 | Undefined terms: catalogue tag, full release tag, unsigned control image, signature identity in 2.10; 2.15/2.16 silent with no prior digest; which package set | **partly decided 2026-08-22**: catalogue tag, full release tag and platform manifest defined; the control digest named (grafana 13.0.4's amd64 child); still open: signature identity in 2.10, the no-prior-digest case, which package set | Req 2 terms paragraph; task 9.6 |
| 1.13 | Design asserts as built what is only specified; old diagrams; stale 8.3 pointers; contradictory visibility bullets | **mostly decided 2026-08-22**: security bullets marked as specified; architecture node, sequence diagram and platform header updated; 8.3 closed as superseded with its stale sentence annotated; visibility bullet corrected. Still open: the error-table rows for the new red-run shapes; the remaining "task 8.3" pointers in design.md | design.md, tasks.md |
| 1.14 | Req 2.1 and 2.20 coexist without a note; Req 2.2 dangling; provenance not required by 2.10/2.23; 2.20's WHILE untestable | **decided 2026-08-22**: 2.1 requires every declared platform (sequencing in task 9.3); 2.2 pushes with provenance and defers signing to 2.9; 2.10 requires provenance; 2.25 states provenance is attached, not policy-verified; 2.20's slot now holds the signature-identity rule for "published" | Req 2.1, 2.2, 2.10, 2.20, 2.25 |
| 1.15 | Req 2.21 measures a token, the design promises a pull; unconditional against Req 2.4's private phase | **decided 2026-08-22**: token plus an unauthenticated manifest GET of every catalogue tag, under WHILE public release is enabled | Req 2.21 reworded; task 9.4 |
| 1.16 | Two-actor criterion 2.12 | folded into 1.5 | |
| 1.17 | Task inaccuracies: buildx output needs `name=`, Kyverno predicate-type URIs, `kyverno apply --registry`, 8.3 open beside 9.3, todo wording | **decided 2026-08-22**: all five corrected | tasks 9.1, 9.6, 8.3, coverage table; tasks/todo.md |
| A1 | Reproducible builds never weighed against publish-if-changed | **decided 2026-08-22: (a)** content comparison stays the gate with four guardrails (canonicalised sorted set with checksums, CycloneDX attested beside SPDX as the checksum source, pinned inputs as the "base digest" check, reproducibility measured nightly as a side effect with the diffoci spike and its flip condition recorded); research input stored in `data/` | Req 1.9, 2.9, 2.15; Decision 6; tasks 9.1, 9.2; `data/reproducible-digests-vs-content-diff-2026-08-22.md` |
| A2 | `under_investigation` statements derive from an unpersisted scan report | open; proposed: persist the release-time report (artifact or attestation) so the compiled document is reproducible | |
| A3 | "Declared" switches have no declared location | open; candidate home: cluster B's `triage/policy.yaml` | |
| A4 | Scan each platform manifest by its own digest rather than `--platform` plus `--image-src remote` | **decided 2026-08-22**: scan by manifest digest | task 9.3 wording |
| A5 | Req 2.21 belongs to one daily-invariants mechanism | open; cluster D shape | |
| A6 | Req 6.35 implied by 6.1; coverage predicate copied three times; 2.19/2.20/2.22 are one invariant | **decided 2026-08-22**: "uncovered finding" defined once in the Req 2 terms and used by 2.12, 2.13, 2.26; 6.35 kept (reviewer's reasoning); 2.20 and 2.22 re-purposed, 2.19 kept as the per-release invariant | Req 2 terms; Req 2.12, 2.13, 2.26 |
| A7 | Req 2.24's "daily checks" is a third name for the run; Req 2.9 gates tagging on attestations but not the signature | **decided 2026-08-22**: 2.24 triggers on "a scheduled rescan"; 2.9 gates tagging on the signature and the attestations | Req 2.9, 2.24 |

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
- 2026-08-22, later: choice 2 decided as (b) and encoded together with 1.3,
  1.4, 1.6, 1.15, A4, A7 and the terms paragraph (revision commit 1). Next:
  the switch guards and the failed-scan rule (1.5, 1.7), then the mechanism
  questions that need the owner (1.8 recursive signing and per-platform SBOM,
  1.11 identity split, A1 reproducibility, A2 persisted scan report, A3 the
  declared-values home).
- 2026-08-22, revision commit 2: the pure corrections landed (1.5, 1.7, 1.9,
  1.10, 1.13 in part, 1.14, 1.17, A6). Open for the owner: 1.8, 1.11, A1, A2,
  A3; open mechanical: the rest of 1.12 (which package set is compared), the
  error-table rows and remaining 8.3 pointers in design.md (1.13), A5.
- 2026-08-22, revision commit 3: 1.11 decided as the two-role split. Open
  for the owner: 1.8, A1, A2, A3.
- 2026-08-22, revision commit 4: 1.8 decided as recursive signing and
  per-platform SBOMs. Open for the owner: A1, A2, A3.
- 2026-08-22, revision commit 5: A1 decided on the owner's research memo;
  CycloneDX attested beside SPDX; comparison key gains type and checksum.
  Open for the owner: A2, A3.
