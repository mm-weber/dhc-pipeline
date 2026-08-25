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
| 3.1 | "bypass_actors is null" is unmeasurable anonymously (field withheld without write access), behaviorally refuted (PR #102 merged with zero approvals), and 9.9's anonymous comparison cannot see the field | open; reviewer's fix: correct both prose passages, scope 9.9 to named visible fields both directions, bypass_actors explicitly outside the compared set | |
| 3.2 | 9.13 gates the run on suppressions in every consumer: the divergence gating Decision 10's Rejected list disclaims; "expected suppression" undefined; failure row describes a different criterion | open; reviewer's recommended alignment: gate on recipe and authoritative consumer, rest to the portability block | |
| 3.3 | The verbatim instructions contain no consumer step, no task adds one, and 13.4 carries the vexctl merge ADR 0003 retired | open; reviewer's fix: manual and README gain per-consumer scan steps rendered from the policy file's list; merge step dropped | |
| 3.4 | F13's LOG-anchor lint delivered by no criterion or task in any cluster, and D is the last cluster | open; reviewer's fix: new criterion 9.18 plus task 13.6 extending the existing lints | |
| 3.5 | F12 (a) under-delivered: the memo requires shipping the Apache-2.0 licence text; 9.16 only names it | open; reviewer's rewording plus a LICENSES/Apache-2.0.txt commit in 13.1 | |
| 3.6 | F12 (c) under-delivered: README:3 still opens with the "-style" label; "last remaining occurrence" is false; attribution sentence untasked | open; reviewer's fix: README, CLAUDE.md and both spec intros drop the label; attribution sentence added | |
| 3.7 | 9.12 spans the whole rescan; trade-offs claim one digest per day (35 catalogue tags measured) | open; reviewer's narrower EARS (supported-set scoping, the house pattern) plus an honest trade-off sentence | |
| 3.8 | "Remove that tag by hand" names no GHCR mechanic; 9.5's mandatory replacement digest blocks withdrawals | open; reviewer's fix: runbook names the real moves (replace through the release path; version deletion or tombstone for withdrawals, recorded); 9.5 allows a recorded absence | |
| 3.9 | 9.9 one-directional (a retired ruleset can return unnoticed); field set undefined; task names the wrong API | open; covered by 3.1's replacement plus canonicalisation sentence and rulesets-API wording in 13.2 | |
| 3.10 | "Its authoritative scanner" never declared as data | open; reviewer's 9.11 rewording: exactly one consumer marked authoritative | |
| 3.11 | 9.6 "that entry" has no antecedent for a file-level condition | open; reviewer's rewording: naming each violation | |
| 3.12 | 9.1's list omits the reporting channel, advisory channel and record locations F11 opens with | open; reviewer's three-item insertion | |
| 3.13 | Task 13.5 invents a third register class against 9.14's binary labelling | open; reviewer's rewording: deliberate rows carrying review dates | |
| 3.14 | Truth-pass nits: rescan-flow header, trust-boundary table location divergence unrecorded, "sets" versus "definitions" | open; reviewer's three fixes | |

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
