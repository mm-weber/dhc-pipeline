# Cluster D revision ledger (PR #103), started 2026-08-25

**Purpose.** One place holding the state of the cluster D revision so the
work can be picked up at any time without the authoring conversation:
every finding from the independent review
(`2026-08-25-cluster-d-independent-review.md`, numbered 3.1 to 3.14),
each with its current disposition. A row moves from `open` to a decision
with the commit that encodes it.

**Order of work.** No finding needs a new owner decision: every one is a
correction inside already-decided semantics (informational-first from
Decision 10's own Rejected list, record honesty, decided obligations
delivered in full), with the reviewer's validator-checked rewordings.
Encoded as one revision commit.

## Ledger

| # | Finding (short) | Disposition | Where encoded |
|---|---|---|---|
| 3.1 | "bypass_actors is null" is unmeasurable anonymously (field withheld without write access), behaviorally refuted (PR #102 merged with zero approvals), and 9.9's anonymous comparison cannot see the field | **decided 2026-08-25**: both prose passages corrected naming the misreading's origin (a jq null on a withheld field); 9.9 scoped to name, target, enforcement, conditions and rules, both directions; bypass_actors explicitly outside the compared set, admin-view JSON into data/ via 13.2's operator bracket | Req 9.9; Decision 10; F11 note; task 13.2 |
| 3.2 | 9.13 gates the run on suppressions in every consumer: the divergence gating Decision 10's Rejected list disclaims; "expected suppression" undefined; failure row describes a different criterion | **decided 2026-08-25**: reviewer's recommended alignment taken (Decision 10's informational-first rejection already decided it): 9.13 gates on a failed step or a missing authoritative suppression, remaining consumers to the block; failure row aligned | Req 9.13; design failure row; task 13.4 |
| 3.3 | The verbatim instructions contain no consumer step, no task adds one, and 13.4 carries the vexctl merge ADR 0003 retired | **decided 2026-08-25**: reviewer's fix taken: instructions gain per-consumer steps rendered from the policy file's list via task 9.8's rendering, on 10.7's baseline; vexctl merge dropped per ADR 0003 | task 13.4 |
| 3.4 | F13's LOG-anchor lint delivered by no criterion or task in any cluster, and D is the last cluster | **decided 2026-08-25**: reviewer's criterion taken verbatim as Req 9.18; task 13.6 extends the existing lints, unit-tested | Req 9.18; task 13.6; coverage row |
| 3.5 | F12 (a) under-delivered: the memo requires shipping the Apache-2.0 licence text; 9.16 only names it | **decided 2026-08-25**: reviewer's rewording taken; LICENSES/Apache-2.0.txt committed and referenced from NOTICE | Req 9.16; task 13.1 |
| 3.6 | F12 (c) under-delivered: README:3 still opens with the "-style" label; "last remaining occurrence" is false; attribution sentence untasked | **decided 2026-08-25**: README.md:3, CLAUDE.md:3 and both spec intros drop the label; attribution and non-affiliation sentences added; dated decision uses stand as history | task 13.1 |
| 3.7 | 9.12 spans the whole rescan; trade-offs claim one digest per day (35 catalogue tags measured) | **decided 2026-08-25**: reviewer's supported-set scoping taken (the house pattern for issues and clocks) and the trade-off owns the multiplier plainly | Req 9.12; Decision 10 trade-offs |
| 3.8 | "Remove that tag by hand" names no GHCR mechanic; 9.5's mandatory replacement digest blocks withdrawals | **decided 2026-08-25**: reviewer's fix taken: runbook names the realizable moves with the 5,000-download refusal risk stated; 9.5 allows a recorded absence of a replacement | Req 9.5; task 13.3 |
| 3.9 | 9.9 one-directional (a retired ruleset can return unnoticed); field set undefined; task names the wrong API | **decided 2026-08-25**: covered by 3.1's replacement (both directions, named fields); 13.2 names the rulesets API and the canonicalisation | Req 9.9; task 13.2 |
| 3.10 | "Its authoritative scanner" never declared as data | **decided 2026-08-25**: reviewer's rewording taken: exactly one consumer marked authoritative in the policy file, data not prose | Req 9.11 |
| 3.11 | 9.6 "that entry" has no antecedent for a file-level condition | **decided 2026-08-25**: reviewer's rewording taken; design row aligned | Req 9.6; design row |
| 3.12 | 9.1's list omits the reporting channel, advisory channel and record locations F11 opens with | **decided 2026-08-25**: reviewer's three items inserted into 9.1's list; 13.1's item list follows | Req 9.1; task 13.1 |
| 3.13 | Task 13.5 invents a third register class against 9.14's binary labelling | **decided 2026-08-25**: reviewer's rewording taken; classes stay binary, a review date is a column | task 13.5 |
| 3.14 | Truth-pass nits: rescan-flow header, trust-boundary table location divergence unrecorded, "sets" versus "definitions" | **decided 2026-08-25**: reviewer's three fixes taken: flow header extended, table location recorded in the F11 note, "definitions of" wording | design flow header; F11 note |

## Working notes

- 2026-08-25: ledger created on receipt of the independent review. The
  review's Checked-and-held equivalents: validator 155 valid and all
  eight proposed replacements validate; full criterion-to-task coverage
  confirmed; private-reporting and advisories endpoints answer anonymous
  reads; the ruleset export format carries bypass_actors; grype's
  OpenVEX matcher speaks the compiled documents' purl dialect and
  filters only not_affected and fixed. The bypass_actors misreading
  originated in the epoch review's S6 (a jq null on a withheld field)
  and was propagated by the authoring session, not by that reviewer's
  prose; both records get the correction. Critique open item 583 (the
  admin-view bypass_actors JSON into data/) becomes part of task 13.2's
  operator bracket.
- 2026-08-25, revision commit 1: every row decided and encoded with the
  reviewer's validator-checked texts; no owner decision was required,
  every fix lands inside already-decided semantics. New criterion 9.18
  and task 13.6 deliver F13's mechanical link; 9.1, 9.5, 9.6, 9.9,
  9.11, 9.12, 9.13 and 9.16 reworded; the bypass_actors record
  corrected in critique and design; tasks 13.1 to 13.5 adjusted.
  Validator expected at 156 valid.
