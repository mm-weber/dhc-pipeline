# Primitives cross-review revision ledger, started 2026-08-25

**Purpose.** One place holding the state of the primitives pass: every
finding from the cross-review
(`2026-08-25-requirements-primitives-cross-review.md`, numbered 5.1 to
5.19) with its disposition and where it landed. The review analysed the
rulebook at PR #104's head; the owner set the lens (future product, no
legacy constraints) and encoding lands as PR #105.

**Disposition key.** Every row was adopted 2026-08-26 (the owner's call:
full package, per-item veto at PR review). The same day, a multi-angle
code review of the encoding (three angles completed, four cut short by a
session limit) found five defective encodings; rows marked *revised*
carry those repairs, and two adoptions were partly reversed on its
evidence: 2.4 restored in revised form (5.5) and the 6.44/6.45 pair
restored unmerged (5.12). Net result: 164 criteria become 147.

## Ledger

| # | Finding (short) | Where encoded |
|---|---|---|
| 5.1 | One daily-scan primitive stated four ways | Req 2.22 widened (revised: single-manifest bracketing restored); 2.6, 2.18, 6.2 retired; flows and tasks 8.3, 9.3, 9.5, 10.1 re-cited |
| 5.2 | Release-tag gate triple | Req 2.26 rewritten; *revised*: the unscanned-manifest predicate restored beside no-report (angle B: a report can exist for a manifest never scanned, the repo's own measured Trivy silent-downgrade case); 2.19 retired; design row re-worded |
| 5.3 | 1.7/1.8 spike fossil | Req 1.7 rewritten (*revised*: anchored to criterion 9.15's table, angle S ambiguity); 1.8 retired |
| 5.4 | Stale-pin bootstrap | 3.6 retired, no replacement |
| 5.5 | Private phase and its undeclared switch | *Partly reversed*: 2.4 restored as "WHILE its declared public-release state is disabled..." (angle B: deletion left the disabled branch with no obligation, exposing pre-release and internal-fork images); 7.7 declares the state either way |
| 5.6 | Second-opinion criterion superseded | 6.6 retired; *revised*: the open-finding half of its function is retired WITH it, stated in task 14.4's truth pass (angle B: 9.12 covers suppressed statements only; the CONVENTIONS sentence goes) |
| 5.7 | Badges are presentation | 6.48 retired; task 10.5 closed with the retirement note |
| 5.8 | Requirement 8 is owner-environment guidance | Group 8 tombstone (*revised*: its CONVENTIONS claim dropped, angle B measured CONVENTIONS never carried it; the dangling Req 8.2 citation fix rides task 14.4) |
| 5.9 | Exception field lists split | 6.7 and 6.11 absorb; 6.23, 6.24 retired |
| 5.10 | VEX shape lints mergeable | 6.17 absorbs 6.18; 6.20 absorbs 6.21 and 6.31 (*revised*: disjuncts made unambiguous, angle S: "beside status notes" garble); three retired |
| 5.11 | Compiler identifier rule split | 6.29 absorbs; 6.36 retired |
| 5.12 | Invariant and alarm as two criteria | *Reversed*: 6.44 and 6.45 restored as the original pair; the merge demoted the alarm to a modal-less participle with no SHALL (angles B and S), losing the daily red the ADR 0004 nondeterminism makes load-bearing |
| 5.13 | Definition validation in two groups | 7.2 absorbs (*revised*: trigger widened to "opens or gains commits", angle B: PR-open alone misses later pushes); 1.5 retired |
| 5.14 | Declared-values ledger incomplete | 7.7 extended: public-release state, every scheduled workflow's schedule |
| 5.15 | Test plane misses the active-set anchor | 5.2 anchored to chart adaptations deploying active definitions |
| 5.16 | Authoritative scanner data vs prose | 6.1 reads the declared authoritative consumer and the defined uncovered-finding term; terms pointer sentence dropped |
| 5.17 | Build-failure reporting bound to PR checks | 2.5 reworded to that run's checks |
| 5.18 | Actor vocabulary drift | 7.6 names THE Renovate Automation; 6.13/9.12 naming held as a note |
| 5.19 | Held observations | held, no encoding (issuer hardcode, epoch term, EPSS/KEV asymmetry, class none vocabulary, 6.46/9.1 density) |

## Working notes

- 2026-08-25: ledger created on receipt of the cross-review (one Fable
  subagent, owner-approved task). Headline: 164 criteria, 145 proposed,
  all 15 replacement texts EARS-validated, no removal candidate
  cross-referenced by a surviving criterion.
- 2026-08-26: owner chose (b), full package with per-item veto at PR
  review; encoded on branch `spec-primitives` under the stable-ID rule
  (retired numbers never reused, listed in the requirements
  introduction; contiguous renumbering once, at the successor cut, task
  12.1). Live citations updated only in forward-facing text; dated
  records keep their numbers, which the stable-ID rule keeps true.
- 2026-08-26, owner-requested multi-angle code review of the encoding
  (/code-review max on PR #105): angles B (removed behavior),
  efficiency/claims and simplification completed with 15 findings;
  angles C, D, E and altitude were cut short by a session limit after
  overlapping partial results (the rendering-drift observation was
  already covered by the stable-ID note). Encoded in revision: 2.4 and
  6.45 restored (see rows 5.5, 5.12), 2.26 gains the unscanned
  predicate, 6.20 and 1.7 and 7.2 repaired, the intro split into one
  source line per wave with its accounting corrected (the final cleanup
  added 1.13 to 1.19 and 5.8 and amended five more criteria than it
  said), live design prose re-cited (per-binary scope, versionless
  decision, platforms section, Development Process), task 10.5 closed
  in the 8.3 pattern, and this ledger's dead column filled. Validator:
  147 valid.
