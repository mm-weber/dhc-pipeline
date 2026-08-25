# Cluster C revision ledger (PR #101), started 2026-08-25

**Purpose.** One place holding the state of the cluster C revision so the
work can be picked up at any time without the authoring conversation: every
finding from the independent review
(`2026-08-25-cluster-c-independent-review.md`, numbered 1.1 to 1.13), each
with its current disposition. Decisions are the owner's, taken one at a
time; a row moves from `open` to a decision with the commit that encodes it.
Where a revision changes a decision recorded in
`2026-08-21-production-readiness-critique.md`, both documents change in the
same commit (the amend-first rule).

**Order of work.** The findings that need the owner (1.1 daily
re-verification semantics for a pin that never verified, 1.3 quarantine
scope and the tool-pin sweep), then the pure corrections with the
reviewer's rewordings (1.2, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10, 1.11,
1.12, 1.13).

## Ledger

| # | Finding (short) | Disposition | Where encoded |
|---|---|---|---|
| 1.1 | Req 3.10's daily re-verification contradicts the F10 amendment's "standing pin stays valid": hardened-app's pinned commit is measured unsigned and cannot become signed | **decided 2026-08-25: universal (b)**, no grandfather logic for one transitional pin: Req 3.10 stays as written; a signed hardened-app release through Req 3.8 is sequenced before task 11.3; F10 note reworded; the owner rejected regression-only (a) as one-time code accommodating removable legacy | critique F10 note; tasks 11.2, 11.3 |
| 1.2 | Task 11.1's quarantine placement "on the github-tags and github-releases rules" under-implements Req 3.7: literal placement quarantines only patch and digest, exempting minors | **decided 2026-08-25**: subsumed by 1.3's rule: one datasource-scoped packageRule, no matchUpdateTypes, so minors age too; explicitly not the update-type-scoped Req 3.5 rule | task 11.1 |
| 1.3 | Req 3.7's universal quantifier matches the delivered scope in neither direction: chart, npm, go, pypi bumps outside the design; github-releases rule sweeps in the six tool pins unstated | **decided 2026-08-25 (2')**: every third-party version datasource ages three days (github-tags, github-releases, npm, pypi, helm, go); docker exempt by name (catalogue-published digests flow same-day, build layer hand-reviewed); rationale recorded: npm incident density and its 72-hour unpublish window, renovate as highest-privilege pin, quarantine catches fast-burn not slow-burn (xz stated) | Req 3.7; Decision 8 a and trade-offs; F2 revision note; task 11.1 |
| 1.4 | "Signer identity into the bump PR body via the refresh output" names a mechanism Renovate does not have: postUpgradeTask stdout goes to debug logs only | **decided 2026-08-25**: reviewer's swap taken: a dated verification comment beside the pin, carried by the diff; F2 note revised in the same commit | task 11.2; F2 revision note |
| 1.5 | yamale day() constraints are static literals: no schema fails "past the review-by date" | **decided 2026-08-25**: reviewer's split taken: yamale validates shape, a validate-lint date test reuses lint-accepted-risk.sh's expired_at pattern | task 11.4; Decision 8 d |
| 1.6 | Req 1.12's deb shape (release segment) contradicts the terms memo's dhi.io/deb/debian/main example | **decided 2026-08-25**: reviewer's rewording taken, deb arm is dhi.io/deb/(distro)/main | Req 1.12 |
| 1.7 | Task 11.1 promises a timestamp assertion the offline fixture harness cannot measure; default timestamp-optional behaviour silently waives the quarantine | **decided 2026-08-25**: reviewer's swap taken: releaseTimestampSupport asserted against the pinned renovate/dist; timestamp-required on the age rule, so a missing timestamp is pending, never a silent pass | task 11.1 |
| 1.8 | Chart-version manager needs upstream.repository captured as registryUrl; helm datasource's default registry is a frozen decoy; first run opens a real cert-manager chart bump | **decided 2026-08-25**: reviewer's addition taken: registryUrl capture named, fixtures extended, valkey redirect and first-run cert-manager bump recorded | task 11.4 |
| 1.9 | F13 amendment misdates the chart-pin managers: landed 2026-08-13 (f3b5f87), not 2026-08-14 | **decided 2026-08-25**: corrected | critique F13 note |
| 1.10 | Req 3.8's "that definition's" has no antecedent | **decided 2026-08-25**: reviewer's rewording taken, "for a definition's bump" | Req 3.8 |
| 1.11 | Req 3.12's "its e2e upgrade path among them" is unbound; required-check membership is out-of-tree state with no cluster C guard (holds live today, measured) | **decided 2026-08-25**: clause dropped; e2e membership stays informational in task 11.4; a normative Repository criterion arrives with cluster D's ruleset-as-code, its natural drift guard | Req 3.12 |
| 1.12 | Requirements introduction's amendment record stops at cluster B | **decided 2026-08-25**: reviewer's sentence appended | requirements introduction |
| 1.13 | `none` refused everywhere while the decision text says "for new definitions"; widening unrecorded | **decided 2026-08-25**: clause appended to the F10 note: nothing is grandfathered | critique F10 note |

## Working notes

- 2026-08-25: ledger created on receipt of the independent review; no
  dispositions yet. The review's Checked-and-held section confirms the
  measured bases (both signature claims, the 20-for-20 grafana agreement,
  live required checks including `e2e gate`), coverage completeness, and
  EARS validity (138 valid). No merge-order constraint like cluster B's
  ADR 0004 exists for this PR; the ADR 0002 amendment rides the branch.
- 2026-08-25, revision commit 1: every row decided and encoded. Owner
  decisions: 1.1 universal daily re-verification, no grandfather logic,
  signed hardened-app release sequenced before task 11.3 (the owner
  rejected one-time accommodation code for removable legacy); 1.3 (2'),
  every third-party version datasource ages three days, docker exempt by
  name. Corrections 1.2, 1.4 to 1.13 encoded with the reviewer's
  rewordings. Related decision, recorded in the same conversation and
  landing separately: a **greenfield epoch** (wipe of pre-epoch registry
  state, migration accommodations stripped) gets its own PR after #101
  merges and before cluster D drafting; it re-decides F9's "never
  delete" and is not part of this PR's scope.
