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
| 1.1 | Attested reports omit suppressed findings: accepted clocks as fixed, closes as gone; 6.52/6.53 both fire | open; reviewer's rewording: reports record suppressed findings (`--show-suppressed` in rescan and release scans); "appears" means reported or suppressed | |
| 1.2 | Decision and fix clocks not computable from named inputs; "release line" undefined; fix date has no source | open; reviewer's shape: decision time from action statement timestamp (affected) or statement timestamp (not_affected/fixed); define release line in the Req 2 terms; name the fixed-date source; critique amendment in the same commit | |
| 1.3 | 6.38 unconditional (competes with source statements; Trivy picks by timestamp) and never sets the affected statement's timestamp; no day-one first-seen for existing exceptions | open; reviewer's rewording: "that no source statement covers", timestamp = first seen with a defined fallback; migration sentence for the twelve grafana entries | |
| 1.4 | 6.43 fires every day (document timestamp differs) and never repairs a violated one-attestation invariant; zero attestations invisible | open; reviewer's rewording: differs in its set of statements, or attestation count differs from one; canonical comparison; merge as carry-forward input when several exist | |
| 1.5 | 6.42's replace scope understated; critique claims a Rekor measurement ADR 0004 lists as unmeasured | open; reword to "every scan report attestation of that predicate type"; correct the critique sentence; task 10.3 measures keyless --replace and Rekor retention first | |
| 1.6 | Amended 2.6, 2.8, 6.1, 6.3 have no implementing task; aperture is declared but nothing reads it | open; add the reads to task 10.1 (workflow --severity from the policy file, sevRank takes the aperture) and annotate | |
| 1.7 | Issues over legacy digests never close; reopening claim false to the code; resolved:fixed asserts an unknown reason | open; owner's call on scope, reopening criterion, and label semantics | |
| 1.8 | 6.50: no KEV-outage rule, no severity source, over-ceiling exceptions past the gate only ever "reported" | open; owner's call on fail-open versus fail-closed; severity source and escalation per the reviewer's suggestion | |
| 1.9 | Carry-forward input not required to be verified: an unverified read re-signs whatever sits on the digest | open; reviewer's clause: read previous documents and reports only through verification against the 2.23 identities | |
| 1.10 | Amended 6.8 binds the wrong actor and restates 6.38 | open; reviewer's rewording | |
| 1.11 | 6.41 fires for findings the scan no longer lists; "original timestamp" has no day-one value | open; reviewer's rewording plus 1.3's first-seen definition | |
| 1.12 | Standing design text contradicts Decision 7; release flow not updated for affected; dangling issue-link promise | open | |
| 1.13 | Truth pass misses CONVENTIONS.md, the exception file header, a build.yml comment, the manual's "never closes" line; Req 6.4 left dangling | open | |
| 1.14 | Daily cost and growth of 6.42/6.43 never stated (~25 scans and log entries per day, growing) | open; owner accepts the number or changes the cadence | |
| 1.15 | Small defects: 6.40 "change time" unbound and unscoped; 6.48 antecedent; 6.49 per-aperture ceilings; sub-day durations unexpressible; resolved-label source; a task cites ADR 0003 for a design.md measurement; intro cites ADR 0004 before its merge; 6.47 "open finding" undefined | open | |

## Working notes

- 2026-08-24: ledger created on receipt of the independent review; no
  dispositions yet. ADR 0004 (PR #99) must merge before or with this PR, or
  the requirements introduction cites a document `main` does not hold
  (finding 1.15).
