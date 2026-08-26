# Primitives cross-review revision ledger, started 2026-08-25

**Purpose.** One place holding the state of the primitives pass: every
finding from the cross-review
(`2026-08-25-requirements-primitives-cross-review.md`, numbered 5.1 to
5.19) with its disposition. The review analysed the rulebook at PR #104's
head; the owner set the lens (future product, no legacy constraints).
Encoding happens in its own PR after #104 merges, because removals force
renumbering that ripples through design.md and tasks.md.

**Owner-flagged rows** (reverse an earlier deliberate choice, so each is
the owner's call): 5.1 (cluster A kept 2.6), 5.2 (2.19 kept as
per-release invariant), 5.3 (ADR 0001 history), 5.4 (stale-pin
bootstrap, design Decision 3), 5.5 (2.4 private phase), 5.6 (6.6 second
opinion, F7), 5.7 (6.48 badges, F4), 5.8 (Req 8 group), 5.12
(invariant/alarm split, Decision 7).
**Correction-shaped rows** (compression or gap-alignment inside decided
semantics): 5.9, 5.10, 5.11, 5.13, 5.14, 5.15, 5.16, 5.17, 5.18.
**Held notes, no proposal**: 5.19.

## Ledger

| # | Finding (short) | Disposition | Where encoded |
|---|---|---|---|
| 5.1 | One daily-scan primitive stated four ways (2.6, 2.18, 2.22, 6.2) | open; P1 merges into one enumeration-and-scan criterion, net minus 3 | |
| 5.2 | Release-tag gate triple (2.19 inside 2.26's idiomatic reading) | open; P2 rewrites 2.26 unambiguously, deletes 2.19 | |
| 5.3 | 1.7/1.8 encode ADR 0001's finished spike | open; P3 replaces both with one authored-syntax criterion naming the builder seam | |
| 5.4 | 3.6 stale-pin bootstrap serves MVP history, mildly security-negative for a fork | open; delete, no replacement | |
| 5.5 | 2.4 private phase over; its guard state declared nowhere | open; delete 2.4, declare the public-release state via P14 | |
| 5.6 | 6.6 second-opinion scan superseded by 9.11 to 9.13 | open; delete, no replacement | |
| 5.7 | 6.48 badges are presentation over 6.47's publication | open; delete, no replacement | |
| 5.8 | Req 8 is owner-environment guidance, not catalogue promise | open; remove group, guidance to design/CONVENTIONS | |
| 5.9 | Exception field lists split (6.7/6.23, 6.11/6.24) | open; P9a, P9b merge, net minus 2 | |
| 5.10 | Five VEX shape lints mergeable by actor and consequence | open; P10a, P10b, net minus 3 | |
| 5.11 | Compiler identifier rule split (6.29/6.36) | open; P11, net minus 1 | |
| 5.12 | One-attestation invariant and its alarm as two criteria (6.44/6.45) | open; P12 merges, net minus 1 | |
| 5.13 | Definition validation in two groups (1.5/7.2) | open; P13, net minus 1 | |
| 5.14 | 7.10 lints against declarations 7.7 never requires; guard states homeless | open; P14 completes 7.7's declared-values list | |
| 5.15 | 5.2 installs charts 1.14 excludes (the one partial contradiction) | open; P15 anchors 5.2 to active-definition chart adaptations | |
| 5.16 | Authoritative scanner data in 9.11, prose in 6.1 | open; P18 has 6.1 read the declared authoritative consumer and the defined term | |
| 5.17 | 2.5 reports scheduled-build failures to pull request checks | open; P16 rewords to that run's checks | |
| 5.18 | Actor vocabulary drift (7.6 "Upstream Tracking") | open; P19 renames to Renovate Automation; 6.13/9.12 note held | |
| 5.19 | Held notes: 2.23 issuer hardcode (deliberate coupling), "epoch" undefined in requirements, EPSS/KEV asymmetry, class none vocabulary, 6.46/9.1 density | open; note-only unless owner asks | |

## Working notes

- 2026-08-25: ledger created on receipt of the cross-review (one Fable
  subagent, owner-approved task). Headline: 164 criteria now, 145
  proposed, all 15 replacement texts EARS-validated, no removal
  candidate cross-referenced by a surviving criterion. Encoding waits
  for #104's merge and lands as its own PR with the renumbering sweep
  across design.md and tasks.md.
