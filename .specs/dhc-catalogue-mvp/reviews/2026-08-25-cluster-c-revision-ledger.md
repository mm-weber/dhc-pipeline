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
| 1.1 | Req 3.10's daily re-verification contradicts the F10 amendment's "standing pin stays valid": hardened-app's pinned commit is measured unsigned and cannot become signed | open; owner's call between regression-only re-verification (reviewer's rewording) and universal verification with hardened-app red daily until a signed release | |
| 1.2 | Task 11.1's quarantine placement "on the github-tags and github-releases rules" under-implements Req 3.7: literal placement quarantines only patch and digest, exempting minors | open; reviewer's rewording: two datasource-scoped packageRules, matchDatasources alone | |
| 1.3 | Req 3.7's universal quantifier matches the delivered scope in neither direction: chart, npm, go, pypi bumps outside the design; github-releases rule sweeps in the six tool pins unstated | open; owner's call between binding to the two datasources with the sweep stated, and widening the config | |
| 1.4 | "Signer identity into the bump PR body via the refresh output" names a mechanism Renovate does not have: postUpgradeTask stdout goes to debug logs only | open; reviewer's swap: evidence written as a comment line beside the pin, carried by the diff | |
| 1.5 | yamale day() constraints are static literals: no schema fails "past the review-by date" | open; reviewer's split: yamale validates shape, a validate lint does the date comparison like lint-accepted-risk.sh | |
| 1.6 | Req 1.12's deb shape (release segment) contradicts the terms memo's dhi.io/deb/debian/main example | open; reviewer's rewording drops the release segment on the deb arm | |
| 1.7 | Task 11.1 promises a timestamp assertion the offline fixture harness cannot measure; default timestamp-optional behaviour silently waives the quarantine | open; reviewer's swap: assert releaseTimestampSupport against renovate/dist, set minimumReleaseAgeBehaviour timestamp-required | |
| 1.8 | Chart-version manager needs upstream.repository captured as registryUrl; helm datasource's default registry is a frozen decoy; first run opens a real cert-manager chart bump | open; reviewer's addition to task 11.4 | |
| 1.9 | F13 amendment misdates the chart-pin managers: landed 2026-08-13 (f3b5f87), not 2026-08-14 | open | |
| 1.10 | Req 3.8's "that definition's" has no antecedent | open; reviewer's rewording | |
| 1.11 | Req 3.12's "its e2e upgrade path among them" is unbound; required-check membership is out-of-tree state with no cluster C guard (holds live today, measured) | open; reviewer's split: drop the clause, optionally add an actor-correct Repository criterion | |
| 1.12 | Requirements introduction's amendment record stops at cluster B | open; reviewer's sentence | |
| 1.13 | `none` refused everywhere while the decision text says "for new definitions"; widening unrecorded | open; one clause in the F10 amendment note | |

## Working notes

- 2026-08-25: ledger created on receipt of the independent review; no
  dispositions yet. The review's Checked-and-held section confirms the
  measured bases (both signature claims, the 20-for-20 grafana agreement,
  live required checks including `e2e gate`), coverage completeness, and
  EARS validity (138 valid). No merge-order constraint like cluster B's
  ADR 0004 exists for this PR; the ADR 0002 amendment rides the branch.
