# Greenfield epoch revision ledger (PR #102), started 2026-08-25

**Purpose.** One place holding the state of the epoch amendment's revision
so the work can be picked up at any time without the authoring
conversation: every finding from the independent review
(`2026-08-25-greenfield-epoch-independent-review.md`, numbered 2.1 to 2.9),
each with its current disposition. Decisions are the owner's, taken one at
a time; a row moves from `open` to a decision with the commit that encodes
it.

**Order of work.** The finding that needs the owner (2.2 and 2.3 together:
the kickoff-window ordering, wipe-first versus release-first), then the
corrections with the reviewer's fixes (2.1, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9).

## Ledger

| # | Finding (short) | Disposition | Where encoded |
|---|---|---|---|
| 2.1 | Cluster A still specifies the pre-epoch registry (tasks 9.3, 9.5, 9.6; design Decision 6); the wipe destroys Req 2.24's unsigned control digest with no replacement | open; reviewer's fix: drop the 9.3 sentence, reduce 9.5 to the epoch record, respecify 9.6's control (an unsigned untagged manifest minted at epoch), annotate Decision 6 in place | |
| 2.2 | Task 12.1's operator instruction cannot be executed or verified as written; whole-package deletion silently re-privatises the catalogue (fresh packages default private, measured) and forecloses the 30-day restore | open; owner's call on the kickoff ordering (see 2.3); reviewer's preferred reorder dissolves most of this row | |
| 2.3 | Kickoff window deadlocks: chart re-pin PRs cannot pass the required e2e gate because the upgrade path installs the just-deleted base digests (ruleset measured, bypass_actors null) | open; owner's call: reorder (first fresh release, chart re-pins through green gates, then delete pre-epoch versions) versus wipe-first with a specified escape | |
| 2.4 | "Seven catalogue repositories" is six (valkey-compat publishes into dhc/valkey; token endpoint 403 DENIED, measured) | open; reviewer's rewording in all three documents | |
| 2.5 | Issue-reset bullet promises reactivation semantics (Req 6.57) no running code has at epoch time: rescan dedups open issues only until task 10.6 | open; reviewer's options: sequence the reset with 10.6, expect and hand-merge duplicates, or land the one-line dedup extension (drop --state open) with group 12 | |
| 2.6 | "Twelve exceptions" is thirteen (13 entries counted; the 13th landed 2026-08-13, before cluster B wrote twelve) | open; drop the count or write thirteen | |
| 2.7 | /oss alias bullet mis-attributes the removal to the epoch (its reason ended at migration) and removes only one of two alias readers (refresh-grafana.sh branch and test 5b stay) | open; reviewer's options: remove both halves with the honest reason, or move the item to cluster C's truth pass | |
| 2.8 | "Exercises F11's revocation mechanics" overstates 12.1: no revocations.yaml entry, and no consumer-facing notice exists until cluster D's SECURITY.md, a whole implementation period later | open; reviewer's options: soften, or produce the record (revocations.yaml entries at epoch, README withdrawal note until SECURITY.md) | |
| 2.9 | Cluster B ledger rows 1.3 and 1.11 still record the reversed migration as standing; task 12.1's Req 7.1 citation matches no bullet | open; strike-notes on both rows; add the CONVENTIONS.md epoch sentence or drop the 7.1 citation | |

## Working notes

- 2026-08-25: ledger created on receipt of the independent review. The
  review's session hit a usage limit at the very end; its two final wording
  corrections were already applied, and the dash audit plus run note were
  completed by the coordinating session (recorded in the review's Method).
  Measured highlights the dispositions rest on: six repositories exist, all
  ten legacy tags still resolve, the 13.0.4 control child digest exists
  today, grafana 13.1.3 carries exactly 3 OpenVEX plus 1 SPDX attestation
  layers, `main_sec` requires both gates with no bypass actors, fresh
  personal-scope packages default private, and the packages API accepts
  only classic PATs.
