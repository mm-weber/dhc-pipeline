# Cluster B revision ledger (PR #100), started 2026-08-24

**Purpose.** One place that holds the state of the cluster B revision so the
work can be picked up at any time without the authoring conversation: every
finding from the independent review
(`2026-08-24-cluster-b-independent-review.md`, numbered 1.1 to 1.15), each
with its current disposition. Decisions are the owner's, taken one at a
time; a row moves from `open` to a decision with the commit that encodes it.
Where a revision reverses a decision recorded in
`2026-08-21-production-readiness-critique.md`, both documents change in the
same commit (the amend-first rule; finding 1.2 is explicitly that shape).

**Order of work.** The findings that need the owner (1.7 issue lifecycle,
1.8 KEV outage rule, 1.2's release-line and fixed-date definitions, 1.14's
cost acceptance), then the pure corrections with the reviewer's rewordings
(1.1, 1.3, 1.4, 1.5, 1.6, 1.9, 1.10, 1.11, 1.15), then the consistency and
truth-pass items (1.12, 1.13).

## Ledger

| # | Finding (short) | Disposition | Where encoded |
|---|---|---|---|
| 1.1 | Attested reports omit suppressed findings: accepted clocks as fixed, closes as gone; 6.52/6.53 both fire | **decided 2026-08-24**: reports record suppressed findings and scanner/database versions (Req 6.55); "appears" means reported or suppressed (6.52, 6.46); both scan arms attest one report shape | Req 6.46, 6.52, 6.55; tasks 9.1, 10.3 |
| 1.2 | Decision and fix clocks not computable from named inputs; "release line" undefined; fix date has no source | **decided 2026-08-24** per the reviewer's shape: decision time from `action_statement_timestamp` (affected) or the statement `timestamp` (not_affected/fixed); fix time as the first day absent from every supported digest of its repository, carried forward from the prior status issue's fenced JSON; "release line" replaced by the supported set; critique F4 (ii) amended in the same commit | Req 6.46, 6.47; critique amendment; task 10.4 |
| 1.3 | 6.38 unconditional (competes with source statements; Trivy picks by timestamp) and never sets the affected statement's timestamp; no day-one first-seen for existing exceptions | **decided 2026-08-24**: reviewer's rewording taken verbatim; migration from the `cve` issues' creation dates in task 10.2. *Migration reversed 2026-08-25 (greenfield successor, Decision 9): first seen starts at first attested appearance; task 10.2 adjusted* | Req 6.38; task 10.2 |
| 1.4 | 6.43 fires every day (document timestamp differs) and never repairs a violated one-attestation invariant; zero attestations invisible | **decided 2026-08-24**: reviewer's rewording taken (statement-set difference, or a count other than one, on digest or manifest); canonical comparison and merge-as-input in task 10.3 | Req 6.43; task 10.3 |
| 1.5 | 6.42's replace scope understated; critique claims a Rekor measurement ADR 0004 lists as unmeasured | **decided 2026-08-24**: 6.42 reworded to "every scan report attestation of that predicate type"; the critique's Rekor sentence corrected with the overstatement named; keyless `--replace` and Rekor retention still to be measured first, in task 10.3 (to add with 1.9's verification clause) | Req 6.42; critique F5 (ii) correction |
| 1.6 | Amended 2.6, 2.8, 6.1, 6.3 have no implementing task; aperture is declared but nothing reads it | **decided 2026-08-24**: task 10.1 gains the reads (`--severity` from `triage.aperture` in both workflows, `sevRank` takes the aperture) and the four criteria annotations; Req 2 coverage row gains 10.1 | task 10.1; coverage table |
| 1.7 | Issues over legacy digests never close; reopening claim false to the code; resolved:fixed asserts an unknown reason | **decided 2026-08-24** on the owner's research memo (`data/cve-finding-lifecycle-vs-immutable-tags-2026-08-24.md`): issues, clocks and the badge run over the *supported set* (each definition's current tags); superseded digests keep every knowledge artifact and hold no issues; reopening reactivates the same issue via the marker over closed issues (6.57); labels evidence-graded, `resolved:fixed` only on SBOM proof, `resolved:absent` names scanner and database (6.56); tag retention stays cluster D with the industry poles recorded | Req 2 terms; Req 6.3, 6.46, 6.47, 6.49, 6.52, 6.53, 6.56, 6.57; critique F13 amendment; Decision 7; tasks 10.1, 10.4, 10.6 |
| 1.8 | 6.50: no KEV-outage rule, no severity source, over-ceiling exceptions past the gate only ever "reported" | **decided 2026-08-24: fail closed** (the owner's call over the recommended fail-open): a KEV feed outage fails the pull request by name (Req 6.59) and fails the rescan run as a non-evaluation (Req 6.60); severity from the image's scan report, dead entries tiered by the largest ceiling (6.50); a daily breach fails the run through the invariants step (6.51) | Req 6.50, 6.51, 6.59, 6.60; task 10.1 |
| 1.9 | Carry-forward input not required to be verified: an unverified read re-signs whatever sits on the digest | **decided 2026-08-24**: reviewer's clause as Req 6.58; task 10.3 names the verified read and the measure-first items (keyless `--replace`, Rekor retention) | Req 6.58; task 10.3 |
| 1.10 | Amended 6.8 binds the wrong actor and restates 6.38 | **decided 2026-08-24**: reviewer's rewording taken verbatim | Req 6.8 |
| 1.11 | 6.41 fires for findings the scan no longer lists; "original timestamp" has no day-one value | **decided 2026-08-24**: reviewer's rewording taken; first-seen defined via 6.38, migration via task 10.2. *Migration reversed 2026-08-25 (greenfield successor, Decision 9); task 10.2 adjusted* | Req 6.41; task 10.2 |
| 1.12 | Standing design text contradicts Decision 7; release flow not updated for affected; dangling issue-link promise | **decided 2026-08-24**: Decision 6's re-attester sentence now includes scan reports; release-flow pass 2 gains affected-from-exceptions; three as-built sentences reworded ("internal, never attested", flat 90-day ceiling, "an emptied document is never written"); Decision 7's context bullet keeps them as history; issue link delivered by task 10.3's carry-forward bullet | design.md Decisions 6, 7, release flow, accepted-risk and attestation sections; task 10.3 |
| 1.13 | Truth pass misses CONVENTIONS.md, the exception file header, a build.yml comment, the manual's "never closes" line; Req 6.4 left dangling | **decided 2026-08-24**: all four named in task 10.7 (the build.yml comment flagged for 9.1); Req 6.4 amended to point attachment at criteria 2.9 and 6.43 | Req 6.4; task 10.7 |
| 1.14 | Daily cost and growth of 6.42/6.43 never stated (~25 scans and log entries per day, growing) | **decided 2026-08-24**: the measured baseline (16 digests, 24 platform manifests, ~24 scans and attestations daily, growing until cluster D's retention decision) is stated in Decision 7's trade-offs; owner accepts by PR review | Decision 7 trade-offs |
| 1.15 | Small defects: 6.40 "change time" unbound and unscoped; 6.48 antecedent; 6.49 per-aperture ceilings; sub-day durations unexpressible; resolved-label source; a task cites ADR 0003 for a design.md measurement; intro cites ADR 0004 before its merge; 6.47 "open finding" undefined | **decided 2026-08-24**: 6.40 scoped to statements the compiler wrote, with the scan report timestamp as the change time; 6.48 antecedent bound; 6.49 ceilings per severity in the aperture; whole-day durations stated with the datetime fork note; labels enumerated in 6.56; the mis-citation corrected; the merge-order note stands in this ledger; 6.47 reworded in revision 1 | Req 6.40, 6.47, 6.48, 6.49, 6.56; tasks 10.1, 10.2 |

## Working notes

- 2026-08-24: ledger created on receipt of the independent review; no
  dispositions yet. ADR 0004 (PR #99) must merge before or with this PR, or
  the requirements introduction cites a document `main` does not hold
  (finding 1.15).
- 2026-08-24, revision commit 1: the owner's lifecycle research memo landed
  in `data/` and the modified bundle was adopted: 1.1, 1.2, 1.5, 1.7 and
  1.14 decided and encoded, plus 1.15's "open finding" and per-aperture
  ceiling items (Req 6.47, 6.49). New criteria 6.55 to 6.57. Open for the
  owner: 1.8 (KEV outage rule). Open corrections: 1.3, 1.4, 1.6, 1.9, 1.10,
  1.11, 1.12, 1.13, remaining 1.15 items.
- 2026-08-24, revision commit 2: 1.8 decided fail-closed (Req 6.59, 6.60)
  and every remaining correction encoded (1.3, 1.4, 1.6, 1.9, 1.10, 1.11,
  1.12, 1.13, 1.15); new criteria 6.58 to 6.60; Req 6.4 and 6.8 amended.
  Every row is decided and encoded; PR #100 is ready for the owner's
  review. Merge order: #99 (ADR 0004) before or with #100.
