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
| 2.1 | Cluster A still specifies the pre-epoch registry (tasks 9.3, 9.5, 9.6; design Decision 6); the wipe destroys Req 2.24's unsigned control digest with no replacement | **decided 2026-08-25**: dissolved by the successor mechanism for cluster A's standing texts: nothing is deleted here, so the ten tags stay scanned in place through implementation and 9.3, 9.5, 9.6 and Decision 6 remain true; the successor-side control mint is encoded in 12.1 | task 12.1 |
| 2.2 | Task 12.1's operator instruction cannot be executed or verified as written; whole-package deletion silently re-privatises the catalogue (fresh packages default private, measured) and forecloses the 30-day restore | **decided 2026-08-25**: dissolved: no wipe exists under the successor mechanism; the measured default-private fact survives as 12.1's public-flip step, asserted daily by task 9.4's invariant | task 12.1; Decision 9 |
| 2.3 | Kickoff window deadlocks: chart re-pin PRs cannot pass the required e2e gate because the upgrade path installs the just-deleted base digests (ruleset measured, bypass_actors null) | **decided 2026-08-25**: dissolved: the owner chose a third mechanism over both offered orderings, a successor repository with this one archived intact; no digest is ever deleted, so no gate installs a vanished base | Decision 9 |
| 2.4 | "Seven catalogue repositories" is six (valkey-compat publishes into dhc/valkey; token endpoint 403 DENIED, measured) | **decided 2026-08-25**: corrected in the standing first note (six repositories, seven definitions, valkey-compat into dhc/valkey); the rewritten Decision 9 and task 12.1 carry no count | critique F9 note |
| 2.5 | Issue-reset bullet promises reactivation semantics (Req 6.57) no running code has at epoch time: rescan dedups open issues only until task 10.6 | **decided 2026-08-25**: dissolved: no issue reset exists; the successor starts a fresh issue space, and 10.6's closed-state dedup lands as specified for this repository's operation | Decision 9; task 12.1 |
| 2.6 | "Twelve exceptions" is thirteen (13 entries counted; the 13th landed 2026-08-13, before cluster B wrote twelve) | **decided 2026-08-25**: thirteen, in the rewritten Decision 9; task 10.1 adjusted to "the thirteen standing entries" | Decision 9; task 10.1 |
| 2.7 | /oss alias bullet mis-attributes the removal to the epoch (its reason ended at migration) and removes only one of two alias readers (refresh-grafana.sh branch and test 5b stay) | **decided 2026-08-25**: both, per the reviewer: moved to cluster C's truth pass (11.5) with the honest reason, both halves named (matchString, refresh alias branch, test 5b) | task 11.5 |
| 2.8 | "Exercises F11's revocation mechanics" overstates 12.1: no revocations.yaml entry, and no consumer-facing notice exists until cluster D's SECURITY.md, a whole implementation period later | **decided 2026-08-25**: dissolved: nothing is withdrawn by force under the successor mechanism, the archived repository keeps everything resolvable; F11's record format waits for a real revocation | Decision 9 |
| 2.9 | Cluster B ledger rows 1.3 and 1.11 still record the reversed migration as standing; task 12.1's Req 7.1 citation matches no bullet | **decided 2026-08-25**: strike-notes on cluster B ledger rows 1.3 and 1.11; group 12's citations are now Req 2.11 and 2.24, matching its bullets | cluster B ledger; task 12 |

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
- 2026-08-25, revision commit 1: on receipt of the review the owner
  redirected the mechanism entirely: a **successor repository** (new, not
  a fork) seeded from the cleaned tree after implementation completes
  here, with this repository and its registry archived read-only, nothing
  deleted anywhere. Findings 2.2, 2.3, 2.5 and 2.8 dissolve with the
  wipe; 2.1 reduces to the successor-side control mint; 2.4, 2.6, 2.7 and
  2.9 encoded as corrections. Every row is decided. Sequencing the owner
  set: cluster D next, then the final requirements cleanup (owner,
  repository and registry names parameterized; Req 1.1's list restated as
  a reference set for a modular image catalogue), then implementation
  task by task in this repository, then the cut.
