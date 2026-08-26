# Requirements primitives cross-review (independent), 2026-08-25

**Subject:** `.specs/dhc-catalogue-mvp/requirements.md` on branch `spec-cleanup`
(PR #104), 164 EARS criteria in 9 groups, validator PASSED at 164.
**Lens, set by the owner:** find the right primitives for the future product of
this pipeline, a forkable one-person hardened-image catalogue: the promise
machinery as glue over standard tools, a declared active set, a builder
contract, seams declared not built (critique section 5.1 and its 2026-08-25
addendum; design Decisions 6 to 11). Legacy constraints are not preserved: a
criterion that exists only to serve this repository's history, instance quirks
or one-time transitions is a removal candidate even when internally consistent.
The target is the shortest rulebook that still keeps the published promise
(signed digests, complete honest machine-readable statuses, measured clocks)
and stays forkable. Findings here are numbered 5.1 onward; series 1.x to 4.x
belong to earlier reviews. Where a revision ledger shows a flagged shape was
chosen on purpose, the finding stands and is marked "possibly deliberate" with
the ledger row cited.

**Method note on proposals:** every proposed replacement criterion below was
validated with `node .claude/skills/ears-notation/scripts/ears-validator.js`
against a scratch file (15 proposals, all PASSED); the real requirements.md
validates at 164. Runs are recorded in the sibling
`2026-08-25-requirements-primitives-cross-review.measure.sh` and `.measure.out`.

## Verdict

The rulebook is internally consistent to an unusual degree: across all 45
group-by-group cells I found no hard contradiction, one genuine partial
contradiction (5.2 installs charts the active set forbids the test matrix to
admit, finding 5.15), and a handful of scope ambiguities. What the rulebook is
not, is minimal. Its growth pattern (each review cluster appending criteria
next to the ones it amended) left one primitive stated four ways (the daily
scan of everything tag-referenced: 2.6, 2.18, 2.22, 6.2), five record-and-lint
field lists split across pairs of criteria, two criteria that encode a spike
procedure ADR 0001 already resolved, a bootstrap device (3.6) that manufactures
history the future product does not need, a second-opinion criterion (6.6) that
cluster D's consumer machinery superseded, and one whole group (Req 8) that is
owner-environment guidance rather than catalogue promise. Nineteen criteria can
be removed or merged with zero loss of promise surface, taking 164 to an
estimated 145, and every replacement text below is EARS-validated. About a
third of these shapes are marked possibly deliberate with ledger citations; the
owner re-decides those, one at a time.

## Iteration 1: group-level cross-table (9 by 9, 45 cells)

Questions per cell: (a) contradict, (b) same thing, (c) any criterion no longer
necessary given all others, (d) simplifiable while staying EARS-valid.

| Cell | a | b | c | d | Verdict, one line |
|---|---|---|---|---|---|
| 1x1 | no | partly | yes | yes | HOT: 1.7/1.8 encode a finished spike (ADR 0001); 1.10 enumerates class `none` that 1.11 always refuses; active-set septet 1.13 to 1.19 coherent |
| 1x2 | no | no | no | no | clean: active set vs release path aligned by cleanup revision (ec569ea); 1.15 binds THE CI Pipeline, so Scan Pipeline re-attestation on inactive tags stays legal as Decision 11 intends |
| 1x3 | no | no | no | no | clean: authenticity chain 1.10/1.11 to 3.8/3.10 is declare, verify at bump, re-verify daily; no overlap, no gap |
| 1x4 | no | no | no | no | clean: 1.16 fails bumps of chartless-active adaptations, 4.1 anchors on active definitions; every-chart render gate divergence recorded (final-cleanup ledger 4.4) |
| 1x5 | partly | no | no | yes | HOT: 5.2 installs "each affected chart" while 1.14 admits only active definitions into the test matrix; 5.5/5.8 already anchored |
| 1x6 | no | no | no | no | clean: 6.17's "existing image definition" (not active) matches the deliberate keep-knowledge divergence for deactivated definitions |
| 1x7 | no | partly | yes | yes | HOT: 1.5 duplicates 7.2's definition validation; 1.13 and 7.7 both place the active set in the policy file |
| 1x8 | no | no | no | no | clean: no requirement-level interaction |
| 1x9 | no | no | no | no | clean: 1.10 classes restated in 9.1/9.15 as posture statements, complementary not duplicate |
| 2x2 | partly | partly | yes | yes | HOT: 2.4 is the pre-public phase; 2.19 sits inside 2.26 on the idiomatic reading of "no report for any"; 2.5 reports scheduled-build failures to "pull request checks" |
| 2x3 | no | no | no | no | clean: 3.7's docker-datasource exemption is exactly what lets 2.16's chart-pin digests flow same-day |
| 2x4 | no | no | no | no | clean: 4.2/4.6 consume 2.10's published digests; no tension |
| 2x5 | no | no | no | no | clean: test suite consumes built images; different planes |
| 2x6 | no | yes | yes | yes | HOT: 2.6, 2.18, 2.22 and 6.2 state one daily-scan primitive four ways; 2.12 vs 6.38/6.40/6.41 timestamp chain consistent; 6.34 kept as the universal guard behind 2.9 |
| 2x7 | partly | no | no | note | HOT (small): 2.23 fixes the issuer value in criterion text while 7.7 declares "every verification input that criterion 2.23 names"; possibly deliberate GitHub coupling |
| 2x8 | no | no | no | no | clean: 8.1 says where 2.x runs, nothing more |
| 2x9 | no | no | no | no | clean: 2.24's policy proof and 9.13's verbatim recipe are distinct daily assertions (rendered policy vs published instructions), both wanted |
| 3x3 | no | no | yes | yes | HOT: 3.6 is the stale-pin bootstrap device; 3.1's six-hour figure is an instance value with no declared home |
| 3x4 | no | no | no | no | clean: 3.11/3.12 track and automerge chart pins, 4.x consumes them; complementary |
| 3x5 | no | no | no | no | clean: 5.6's upgrade verification rides 3.x bump PRs |
| 3x6 | no | no | no | no | clean: 6.5's fix lane produces what 3.2 automates; 3.10's supply-chain issue is distinct from 6.3's cve issue |
| 3x7 | no | no | no | no | clean: tool pins deliberately ride 3.7's quarantine (cluster C ledger 1.3); 7.6's actor name drifts (finding 5.18); cadence homes under 5.14 |
| 3x8 | no | no | no | no | clean: Renovate on Actions, uncontested |
| 3x9 | no | no | no | no | clean: 3.10's daily re-verification is one member of the invariants family, same report shape |
| 4x4 | no | no | no | no | clean: 4.8 (gate) and 4.9 (daily report) are complementary arms over one lapse condition; a lapse with no open PR still surfaces |
| 4x5 | no | no | no | no | clean: 4.3 declares, 5.4 verifies live; the house declare-and-verify pair |
| 4x6 | no | no | no | no | clean: compat metadata (4.5) and exceptions (6.7) are parallel structures in different lanes |
| 4x7 | no | no | no | no | clean: 4.6 Kyverno gate separate from 7.x lints |
| 4x8 | no | no | no | no | clean |
| 4x9 | no | no | no | no | clean: compat decisions surface as register rows (9.14), complementary |
| 5x5 | no | no | no | no | clean: 5.5/5.8 follow the declare-and-lint pattern; 5.1's tool naming is house style (real tools named throughout) |
| 5x6 | no | no | no | no | clean: govulncheck (6.13 to 6.16) and e2e are different planes |
| 5x7 | no | no | no | no | clean |
| 5x8 | no | no | no | no | clean: kind-on-Actions is 8.1's only touch; dissolves with finding 5.8 |
| 5x9 | no | no | no | no | clean |
| 6x6 | no | partly | yes | yes | HOT: five internal splits (6.7/6.23, 6.11/6.24, 6.17/6.18, 6.20/6.21/6.31, 6.29/6.36, 6.44/6.45), plus 6.6 and 6.48 outside the promise surface; lifecycle 6.52 to 6.57 and clocks 6.46/6.47 coherent |
| 6x7 | no | partly | no | no | clean with note: 6.49 and 7.7 split the policy-file declaration by section; kept, triage numbers read best beside triage criteria |
| 6x8 | no | no | no | no | clean |
| 6x9 | partly | partly | yes | yes | HOT: 6.6 superseded by 9.11 to 9.13; 6.1/6.12 name Trivy in prose while 9.11 makes the authoritative consumer declared data |
| 7x7 | partly | no | no | yes | HOT: 7.10 lints workflow schedules against declarations 7.7 never requires; 7.3/7.4 soft but kept |
| 7x8 | no | no | no | no | clean |
| 7x9 | no | no | no | no | clean: 9.8/9.9 (rulesets) and 7.10 (workflows) are parallel drift guards over different surfaces |
| 8x8 | no | yes | yes | yes | HOT: both criteria are owner-environment guidance duplicating CLAUDE.md, not catalogue promise; group removal |
| 8x9 | no | no | no | no | clean |
| 9x9 | no | no | no | no | clean with notes: 9.1 references "its epoch", defined nowhere in requirements; 9.12's actor is Scan Pipeline at pull request time; otherwise one purpose per criterion |

Hot cells: 1x1, 1x5, 1x7, 2x2, 2x6, 2x7, 3x3, 6x6, 6x9, 7x7, 8x8 (11 of 45).

## Iteration 2: criterion-level zoom tables

Every finding below is already at the level of specific criteria; no iteration
3 is needed.

### Cell 2x6 (and the 2x2 overlap): the daily-scan primitive, stated four ways

| Criteria | a | b | c | d | Evidence |
|---|---|---|---|---|---|
| 2.6 vs 6.2 | no | yes | 2.6, 6.2 both unnecessary beside 2.22+2.18 | merge | 2.6: "WHILE an image for a platform remains published THE Catalogue SHALL scan that platform for findings within that decision aperture". 6.2: "THE Scan Pipeline SHALL rescan published images at least once per day". Both are implied by scanning every platform manifest of every tag-referenced digest daily (published digests are a subset of tag-referenced digests by 2.10) |
| 2.18 vs 2.22 | no | partly | 2.18 foldable into 2.22 | merge | 2.22: "SHALL enumerate at least once per day every catalogue tag ... and SHALL apply criteria 2.18, 2.21 and 2.24 to that enumeration"; 2.18: "SHALL scan every platform manifest of that digest, or, for a single image manifest, that digest itself". 2.18's only trigger in practice is 2.22's enumeration |
| 2.12 vs 6.38/6.40/6.41 | no | no | no | no | timestamp chain consistent: release writes under_investigation with the report timestamp (2.12), compiler preserves first seen (6.40), lapse re-emits with first-seen kept (6.41) |
| 2.9 vs 6.34 | no | partly | keep 6.34 | no | 6.34 is the universal compile-for-digest guard behind 2.9's release instance; kept |

Disposition: finding 5.1, proposal P1. Possibly deliberate: cluster A ledger
rows 1.2/1.3 kept 2.6 "as written" when the enumeration was introduced.

### Cell 2x2: release-path internals

| Criteria | a | b | c | d | Evidence |
|---|---|---|---|---|---|
| 2.19 vs 2.26 (with 2.9) | partly (ambiguity) | yes on idiomatic reading | 2.19 unnecessary | merge | 2.26: "produces no report for any platform manifest THEN ... sign nothing, attest nothing and apply no tag"; idiomatically "no report for any" means "at least one manifest lacks a report", which subsumes 2.19: "IF a built index contains a platform manifest that its release-time scan did not scan THEN ... apply no tag to that index". On the other reading (zero reports) the two split one failure mode across two criteria and 2.9's precondition ("a report for every platform manifest") already withholds the positive path |
| 2.4 vs 2.21 | no | no | 2.4 unnecessary | yes | 2.4: "WHILE public release remains disabled THE Repository SHALL keep source and registry images private" served the pre-2026-08-13 private phase; the guard state ("public release enabled/disabled") is read by 2.4 and 2.21 but declared by nothing (7.7's list omits it) |
| 2.5 | no | no | no | reword | "report each failing step in pull request checks" mislocates scheduled and dispatch builds (2.7 names all three triggers) |
| 2.15/2.16/2.17 | no | no | no | no | publish-policy trio consistent: 2.16 carries no policy guard and is compatible with both declared policies |
| 2.10/2.11/2.20 | no | no | no | no | published/frozen/identity definitions load-bearing, referenced across groups |

Dispositions: findings 5.2 (P2), 5.5 (removal of 2.4 plus P14), 5.17 (P16).
2.19's retention was deliberate: cluster A ledger row A6, "2.19 kept as the
per-release invariant".

### Cell 1x1: definition-catalogue internals

| Criteria | a | b | c | d | Evidence |
|---|---|---|---|---|---|
| 1.7 vs 1.8 | no | partly (two arms of one decision procedure) | 1.8 unnecessary, 1.7 reducible | replace both with one | 1.7: "WHERE Docker's dhi.io/build frontend produces working builds outside Docker infrastructure THE Catalogue SHALL author definitions in native DHI syntax"; 1.8: "IF a DHI frontend spike does not produce a working build within a three-hour timebox THEN THE Catalogue SHALL adopt DHI-style YAML definitions...". The spike ran, ADR 0001 accepted arm A, the fallback was retired (design Decision 1); both criteria now encode a finished one-time experiment |
| 1.10 vs 1.11 | no | no | no | note only | 1.10 enumerates "signed-tag, signed-commit, cross-origin-checksum, or none" while 1.11 refuses `none` unconditionally; `none` survives as vocabulary for a fork that removes the lint (cluster C ledger 1.13: "nothing is grandfathered", deliberate) |
| 1.13 to 1.19 | no | no | no | no | active-set septet coherent: declare (1.13), scope (1.14), freeze (1.15), refuse bumps (1.16), coherence (1.18), existence (1.19) |
| 1.5 vs 1.6/1.11/1.12/1.19 | no | partly | no | no | 1.5 is the umbrella the IF-lints instantiate; its overlap is with 7.2, handled in cell 1x7 |

Disposition: finding 5.3, proposal P3. Possibly deliberate as history (ADR
0001); as standing rulebook text it is a transition artifact.

### Cell 1x5: the test plane and the active set

| Criteria | a | b | c | d | Evidence |
|---|---|---|---|---|---|
| 5.2 vs 1.14, 1.16 | partly | no | no | reword 5.2 | 5.2: "THE Test Suite SHALL install each affected chart on a kind cluster in CI" vs 1.14: "SHALL admit no definition outside that active set into ... build and test matrices". A PR touching an inactive definition's chart without bumping it (README, values comment) obliges 5.2 to install what 1.14 forbids; 1.16 only catches bumps. The final cleanup gave 4.1 exactly this anchor ("deploying an active definition's images", ledger 4.2) and amended 5.5, but 5.2 is absent from the cleanup's amendment list (intro: "amended Req 1.1, 2.2, 2.7, 2.21, 2.23, 4.1, 5.5 and 7.7") |

Disposition: finding 5.15, proposal P15.

### Cell 1x7: validation duplication and the double-declared active set

| Criteria | a | b | c | d | Evidence |
|---|---|---|---|---|---|
| 1.5 vs 7.2 | no | yes | 1.5 unnecessary once 7.2 absorbs it | merge | 1.5: "WHEN a pull request modifies a definition file THE CI Pipeline SHALL validate schema conformance and pinning conventions before merge"; 7.2: "WHEN a pull request opens THE CI Pipeline SHALL run yamllint and definition validation on changed YAML files". Same actor, same trigger surface, same gate; two criteria in two groups |
| 1.13 vs 7.7 | no | partly | no | note | both place the active set in the policy file: 1.13 "declare in its catalogue policy file an active set" and 7.7 "...and its active set of definitions". 1.13 carries the definition of "active definition", 7.7 the master list; harmless double-declaration, folded into finding 5.14's rewrite of 7.7 |

Disposition: finding 5.13, proposal P13.

### Cell 3x3: tracking internals

| Criteria | a | b | c | d | Evidence |
|---|---|---|---|---|---|
| 3.6 | no | no | unnecessary for the future product | remove | "WHEN THE Catalogue is initialized THE Catalogue SHALL pin each upstream at least one release behind its latest available version": the stale-pin bootstrap existed to make Renovate open genuine PRs from day 1 of a three-day MVP (design Decision 3). A forkable base gains nothing from mandating stale pins at init; the bump flow is demonstrated by operation |
| 3.1 | no | no | no | note | "at least once every six hours" is an instance cadence fixed in criterion text; under finding 5.14 every scheduled workflow's schedule becomes a declared value with the criterion keeping only the floor |
| 3.5 vs 3.7 | no | no | no | no | automerge (3.5) and quarantine (3.7) compose: a PR opens only after aging, then automerges on green; deliberate scope (cluster C ledger 1.3) |

Disposition: finding 5.4 (remove 3.6, possibly deliberate: design Decision 3),
finding 5.14.

### Cell 6x6: triage-group internal splits

| Criteria | a | b | c | d | Evidence |
|---|---|---|---|---|---|
| 6.7 vs 6.23 | no | partly | 6.23 foldable | merge | 6.7 lists the exception's required fields; 6.23 appends one more required field in its own criterion: "SHALL record in that exception every binary path to which that exception applies" |
| 6.11 vs 6.24 | no | partly | 6.24 foldable | merge | 6.11 is the omission lint over 6.7's field list; 6.24 is the same lint for the field 6.23 added: "IF an accepted-risk exception records no binary path THEN ... fail validation" |
| 6.17 vs 6.18 | no | partly | 6.18 foldable | merge | two product-identifier shape lints, same actor, same consequence: not-an-OCI-purl (6.17) and wrong repository (6.18) |
| 6.20, 6.21, 6.31 | no | partly | 6.21, 6.31 foldable | merge | three product-version lints, same actor, same consequence: version not a published tag (6.20), fixed without version (6.21), versionless without a universal-claim note (6.31) |
| 6.29 vs 6.36 | no | partly | 6.36 foldable | merge | 6.29: "set every product identifier ... to a sha256 digest of an image being scanned"; 6.36 refines the same rule for indexes: "covering that index's digest and every scanned platform manifest digest" |
| 6.44 vs 6.45 | no | partly | 6.45 foldable | merge | 6.44 states the one-attestation invariant, 6.45 its daily alarm; 6.43 already repairs a count "other than one". Invariant and alarm fit one criterion |
| 6.48 | no | no | unnecessary | remove | badges are presentation over 6.47's status issue and the workflow runs; the promise says measured and published, which 6.47 delivers (table, fenced JSON, artifact). Possibly deliberate: critique F4 badges decision, "(a) native badges now" |
| 6.1 | no | no | no | compress | the coverage predicate 6.1 spells out is defined verbatim as "uncovered finding" in the Req 2 terms paragraph; 6.1 can read the term (and the term paragraph drops its pointer sentence "it is what criterion 6.1 fails on") |
| 6.3 vs 6.59/6.60 | no | no | no | note only | 6.3 requires an EPSS score in every issue but no outage rule exists for EPSS while KEV has two (6.59, 6.60); asymmetry held, adding a rule would lengthen the book |
| 6.9/6.35/6.41 | no | no | no | no | expiry, non-coverage and lapse-fallback compose without conflict |
| 6.52 to 6.57 | no | no | no | no | close, grade, reopen lifecycle: each criterion a distinct evidence path |
| 6.46/6.47 | no | no | no | no | the clocks: dense but single-purpose; splitting would grow the book |

Dispositions: findings 5.9 (P9a, P9b), 5.10 (P10a, P10b), 5.11 (P11), 5.12
(P12, possibly deliberate: design Decision 7 "proven daily", cluster B ledger
1.4), 5.7 (remove 6.48), 5.16 (P18, see cell 6x9), 5.19 notes.

### Cell 6x9: the consumer machinery vs its predecessors

| Criteria | a | b | c | d | Evidence |
|---|---|---|---|---|---|
| 6.6 vs 9.11/9.12/9.13 | no | partly | 6.6 unnecessary | remove | 6.6: "WHERE a CRITICAL finding exists THE Scan Pipeline SHALL obtain a second-opinion scan with Grype". 9.11 declares consumers as adapters (Grype among them), 9.12 reports every declared consumer's suppression result on every PR scan and rescan, 9.13 runs the published recipe (Grype included) daily. The standing machinery runs Grype far more often and more systematically than 6.6 asks; what 6.6 adds (an unrecorded "second opinion" with no stated consequence) is not a testable primitive |
| 6.1, 6.12 vs 9.11 | partly | no | no | reword 6.1 | 9.11: "exactly one consumer marked authoritative" makes the authoritative scanner declared data (cluster D ledger 3.10, "data not prose"), while 6.1 hardcodes "SHALL run Trivy" and 6.12 hardcodes the Trivy ignore-file format. The 5.1 addendum states the coupling deliberately ("the authoritative scanner stays Trivy with its coupling stated"), but the primitive-shaped criterion reads the declared authoritative consumer; 6.12 stays as a cheap scanner-specific tooth |

Dispositions: findings 5.6 (remove 6.6; possibly deliberate: critique F7
disposition row cites Req 6.6) and 5.16 (P18; possibly deliberate: 5.1
addendum).

### Cell 2x7: verification inputs

| Criteria | a | b | c | d | Evidence |
|---|---|---|---|---|---|
| 2.23 vs 7.7 | partly | no | no | note only | 2.23 fixes "whose certificate issuer is https://token.actions.githubusercontent.com" in criterion text while 7.7 declares "every verification input that criterion 2.23 names" as policy-file data. A platform fork edits a criterion, not a value. Held without proposal: the 5.1 addendum accepts GitHub as the deepest coupling deliberately, and hardening the issuer in normative text is defensible as promise anchoring |

Disposition: finding 5.19 (held observations).

### Cell 7x7: conventions internals

| Criteria | a | b | c | d | Evidence |
|---|---|---|---|---|---|
| 7.10 vs 7.7 | partly | no | no | extend 7.7 | 7.10 fails "IF a workflow's schedule trigger or a job's permissions differ from what that catalogue policy file declares", but 7.7 obliges the file to declare only the 2.14 rebuild schedule (via "every release setting that criteria 2.13, 2.14 and 2.17 name"); the rescan's and Renovate's schedules are linted against declarations nothing requires to exist. Design Decision 6 (finding A3) intended one declared home for switches |
| 7.3, 7.4 | no | no | kept | no | the PR template and the umbrella convention lint are process primitives, cheap, not history-serving |

Disposition: finding 5.14, proposal P14 (also absorbs the 2.21 guard state
from finding 5.5 and the 1.13/7.7 note from cell 1x7).

### Cell 8x8: the operating-environment group

| Criteria | a | b | c | d | Evidence |
|---|---|---|---|---|---|
| 8.1, 8.2 | no | yes (with each other and with CLAUDE.md) | both unnecessary | remove group | 8.1: "SHALL execute image builds, kind clusters, registry pushes, and scans on GitHub Actions runners or on an operator host machine"; 8.2: "...delegate that task to GitHub Actions or an operator host instead of executing it inside a restricted devcontainer". Both describe the owner's development environment (the allowlist-firewalled devcontainer), not the catalogue's promise; the same guidance lives in CLAUDE.md and design. A fork's development environment is not this rulebook's business |

Disposition: finding 5.8. Possibly deliberate: original MVP scope, Req 8 cited
by CLAUDE.md as the authority for CI-first operation.

## Consolidated findings

Severity: High (rulebook-shaping), Medium (real simplification or scope gap),
Low (compression), Note (held observation, no proposal).

### 5.1 One rescan primitive stated four ways (High)

- Contradict: no. Same thing: yes (2.6, 6.2 are consequences of 2.22 plus
  2.18). Necessary: 2.6, 6.2, and a separate 2.18 are not. Simplify: yes.
- Evidence: 2.6 "WHILE an image for a platform remains published THE Catalogue
  SHALL scan that platform"; 6.2 "THE Scan Pipeline SHALL rescan published
  images at least once per day"; 2.18 "SHALL scan every platform manifest of
  that digest, or, for a single image manifest, that digest itself"; 2.22
  "SHALL enumerate at least once per day every catalogue tag ... and SHALL
  apply criteria 2.18, 2.21 and 2.24". Published digests are tag-referenced by
  definition (2.10), so the enumeration covers them.
- Proposal P1, replacing 2.6, 2.18, 2.22 and 6.2 with one criterion (validated):
  "THE Scan Pipeline SHALL enumerate at least once per day every catalogue tag
  in every catalogue repository together with each digest it references, SHALL
  scan for findings within that decision aperture every platform manifest of
  each tag-referenced digest, or that digest itself for a single image
  manifest, and SHALL apply criteria 2.21 and 2.24 to that enumeration."
  Deletes 2.6, 2.18, 6.2; rewrites 2.22. Net minus 3.
- Possibly deliberate: cluster A ledger rows 1.2/1.3 chose to keep 2.6 "as
  written" so the enumeration would satisfy it; that reasoning served the
  legacy tags this branch's Decision 9 successor no longer carries.

### 5.2 The release-tag gate triple (Low)

- Contradict: partly (the ambiguity of "no report for any platform manifest").
  Same thing: yes on the idiomatic reading. Necessary: 2.19 is not. Simplify:
  yes.
- Evidence: 2.19 "IF a built index contains a platform manifest that its
  release-time scan did not scan THEN THE CI Pipeline SHALL apply no tag";
  2.26 "IF a pushed digest's release-time scan produces no report for any
  platform manifest THEN ... sign nothing, attest nothing and apply no tag";
  2.9 already conditions the positive path on "a report for every platform
  manifest".
- Proposal P2, rewriting 2.26 unambiguously and deleting 2.19 (validated):
  "IF a pushed digest's release-time scan produces no report for one or more
  of its platform manifests THEN THE CI Pipeline SHALL sign nothing, attest
  nothing and apply no tag for that digest, and SHALL report that failing scan
  in that run." Net minus 1.
- Possibly deliberate: cluster A ledger row A6, "2.19 kept as the per-release
  invariant".

### 5.3 The spike procedure fossil, 1.7 and 1.8 (Medium)

- Contradict: no. Same thing: partly (two arms of one finished decision).
  Necessary: no, ADR 0001 resolved the experiment. Simplify: yes.
- Evidence: 1.8's condition ("IF a DHI frontend spike does not produce a
  working build within a three-hour timebox") can never fire again; design
  Decision 1: "the timeboxed spike produced working builds in native DHI
  syntax, so fallback B was retired (ADR 0001, accepted)".
- Proposal P3, replacing 1.7 and 1.8 with one criterion that also names the
  builder seam the 5.1 addendum declares (validated):
  "THE Catalogue SHALL author every definition in native syntax of its
  archetype's installed build backend, that backend and its declared
  alternative being named in its trust-boundary table." Net minus 1.
- Possibly deliberate as history (ADR 0001); as standing text it is a
  transition artifact serving this repository's past.

### 5.4 The bootstrap stale pin, 3.6 (Medium)

- Contradict: no. Same thing: no. Necessary: not for the future product.
  Simplify: removal.
- Evidence: "WHEN THE Catalogue is initialized THE Catalogue SHALL pin each
  upstream at least one release behind its latest available version." Its
  purpose was manufacturing immediate real Renovate history inside a three-day
  MVP. A forkable base initialized a year from now should pin current secure
  releases; mandating staleness at init is history-serving and mildly
  security-negative.
- Proposal: delete 3.6, no replacement. Net minus 1.
- Possibly deliberate: design Decision 3 ("Stale-pin bootstrap for immediate
  real history").

### 5.5 The private phase and its undeclared switch, 2.4 and 2.21 (Medium)

- Contradict: no. Same thing: no. Necessary: 2.4 is not. Simplify: yes.
- Evidence: 2.4 "WHILE public release remains disabled THE Repository SHALL
  keep source and registry images private" encoded the pre-2026-08-13 phase;
  under Decision 9 the successor is public from first publish, and privacy
  before that is operator posture, not promise machinery. Meanwhile the state
  both 2.4 and 2.21 read ("public release enabled") is declared by nothing:
  7.7's list omits it, so the guard has no diffable home. Keeping 2.21's guard
  preserves the internal-catalogue fork (a fork that never enables public
  release keeps its registry private without violating the visibility
  invariant).
- Proposal: delete 2.4 (net minus 1) and declare the state via P14 (finding
  5.14), which adds "its public-release state that criterion 2.21 reads" to
  7.7's list.
- Possibly deliberate: 2.21's guard shape was set by cluster A ledger row 1.15
  ("under WHILE public release is enabled"); 2.4 predates every cluster.

### 5.6 The second-opinion criterion, 6.6 (Medium)

- Contradict: no. Same thing: partly. Necessary: no. Simplify: removal.
- Evidence: 6.6 "WHERE a CRITICAL finding exists THE Scan Pipeline SHALL
  obtain a second-opinion scan with Grype" predates cluster D. Now 9.11
  declares Grype as a consumer adapter, 9.12 reports its suppression results
  on every PR scan and rescan, and 9.13 runs it daily in the verbatim recipe.
  6.6's marginal content (an on-demand scan with no recorded output or
  consequence) is not testable machinery; systematic coverage replaced it.
- Proposal: delete 6.6, no replacement. Net minus 1.
- Possibly deliberate: critique F7 decision names Grype the measured second
  consumer and its disposition row cites Req 6.6 as prior spec surface.

### 5.7 The badge criterion, 6.48 (Low)

- Contradict: no. Same thing: no. Necessary: no. Simplify: removal.
- Evidence: "SHALL display in README.md badges rendered from GitHub's public
  API..." is presentation over 6.47's published status issue (table, fenced
  JSON, artifact) and the workflow runs. The promise is measured and
  published; 6.47 is the publication. A fork's README layout is not rulebook
  material.
- Proposal: delete 6.48, no replacement. Net minus 1.
- Possibly deliberate: critique F4 badges decision, "(a) native badges now,
  (b) when the metrics exist".

### 5.8 Requirement 8 is owner-environment guidance (Medium)

- Contradict: no. Same thing: yes (with CLAUDE.md and design). Necessary: no.
  Simplify: group removal.
- Evidence: 8.1 and 8.2 (quoted in the 8x8 table) bind "THE Development
  Workflow" and the choice of runner host, facts about the owner's restricted
  devcontainer. No other criterion depends on them; the catalogue's promise is
  indifferent to where its maintainer's laptop sits.
- Proposal: delete 8.1 and 8.2, moving the guidance to design or
  CONVENTIONS.md (CLAUDE.md already states it). Net minus 2.
- Possibly deliberate: original MVP scope (Req 8 cited from CLAUDE.md).

### 5.9 Exception field lists split across pairs (Low)

- Contradict: no. Same thing: partly. Necessary: 6.23 and 6.24 not as separate
  criteria. Simplify: yes.
- Evidence: 6.23 adds binary paths to the record 6.7 defines; 6.24 repeats
  6.11's omission lint for that one field.
- Proposal P9a, rewriting 6.7 to absorb 6.23 (validated):
  "WHEN a triage decision concludes accepted risk or upstream transfer THE
  Triage Process SHALL record a time-boxed exception under
  triage/accepted-risk/ carrying a treatment, an owner, a decision date, a
  reference to its reasoning in triage/LOG.md, a justification for why
  avoidance and remediation were unavailable, an expiry date, and every binary
  path to which that exception applies."
  Proposal P9b, rewriting 6.11 to absorb 6.24 (validated):
  "IF an accepted-risk exception omits its treatment, owner, decision date,
  reasoning reference, unavailability justification, expiry date, or binary
  paths, or sets an expiry date later than its decision date plus that
  catalogue policy file's largest ceiling, THEN THE CI Pipeline SHALL fail
  validation." Deletes 6.23 and 6.24. Net minus 2.

### 5.10 VEX shape lints, mergeable by actor and consequence (Low)

- Contradict: no. Same thing: partly (five lints, one actor, one consequence).
  Necessary: not as five criteria. Simplify: yes.
- Evidence: 6.17, 6.18 (product identifier shape); 6.20, 6.21, 6.31 (product
  version rules), all "THEN THE CI Pipeline SHALL fail validation".
- Proposal P10a, merging 6.17 and 6.18 (validated):
  "IF a VEX statement names a product that is not an OCI package URL for an
  existing image definition, or names a product identifier declaring a
  repository other than that image definition's published repository, THEN THE
  CI Pipeline SHALL fail validation."
  Proposal P10b, merging 6.20, 6.21 and 6.31 (validated):
  "IF a VEX source statement's product identifier carries a version that is
  not a published tag of any image definition publishing that product's
  repository, carries no version for a statement recording status fixed, or
  carries no version beside status notes recording no reason its claim holds
  for every release, THEN THE CI Pipeline SHALL fail validation."
  Deletes 6.18, 6.21, 6.31. Net minus 3.

### 5.11 The compiler's product-identifier rule, split in two (Low)

- Contradict: no. Same thing: partly (6.36 refines 6.29). Necessary: not
  separately. Simplify: yes.
- Proposal P11, merging 6.29 and 6.36 (validated):
  "WHEN a VEX document is compiled THE VEX Compiler SHALL set every product
  identifier in that document to a sha256 digest of an image being scanned,
  covering, for an image index, that index's digest and every scanned platform
  manifest digest." Deletes 6.36. Net minus 1.

### 5.12 The one-attestation invariant and its alarm (Low)

- Contradict: no. Same thing: partly. Necessary: not separately (6.43 already
  repairs any count "other than one"). Simplify: yes.
- Evidence: 6.44 (the invariant) and 6.45 (its daily report) quoted in the 6x6
  table.
- Proposal P12, merging 6.44 and 6.45 (validated):
  "THE Catalogue SHALL keep exactly one OpenVEX attestation on every
  tag-referenced digest and on each of its platform manifests, THE Scan
  Pipeline reporting each digest or platform manifest carrying more than one
  as a failure of each scheduled rescan run." Deletes 6.45. Net minus 1.
- Possibly deliberate: design Decision 7, "an invariant (Req 6.44) proven
  daily (Req 6.45)"; cluster B ledger 1.4.

### 5.13 Definition validation stated in two groups (Low)

- Contradict: no. Same thing: yes. Necessary: 1.5 not beside 7.2. Simplify:
  yes.
- Evidence: 1.5 and 7.2 quoted in the 1x7 table; same actor, same trigger,
  same gate.
- Proposal P13, rewriting 7.2 to absorb 1.5 (validated):
  "WHEN a pull request opens THE CI Pipeline SHALL run yamllint on changed
  YAML files and SHALL validate schema conformance and pinning conventions of
  every changed definition file before merge." Deletes 1.5. Net minus 1.

### 5.14 The declared-values ledger is incomplete against its own lint (Medium)

- Contradict: partly (7.10 lints against declarations 7.7 never requires).
  Same thing: no. Necessary: yes, both, once aligned. Simplify: yes.
- Evidence: 7.10 fails on schedule drift "from what that catalogue policy file
  declares"; 7.7 requires declaring only the 2.14 rebuild schedule; the rescan
  cadence ("at least once per day", stated in roughly ten criteria as a floor)
  and Renovate's "once every six hours" (3.1) have no declared home. Design
  Decision 6 (finding A3) made the policy file the single diffable home of
  switches. Also folds in: the guard state of 2.21 (finding 5.5) and the
  double declaration of the active set (1.13 and 7.7).
- Proposal P14, rewriting 7.7 (validated):
  "THE Repository SHALL declare in one committed catalogue policy file every
  release setting that criteria 2.13, 2.14 and 2.17 name, its public-release
  state that criterion 2.21 reads, every scheduled workflow's schedule, every
  platform it admits for publishing, every verification input that criterion
  2.23 names, its registry namespace, and its active set of definitions."
  No count change; cadence criteria keep their floors.

### 5.15 The test plane misses the active-set anchor (Medium)

- Contradict: partly (5.2 obliges installing what 1.14 excludes). Same thing:
  no. Necessary: yes, both, once anchored. Simplify: yes.
- Evidence: quoted in the 1x5 table; the final cleanup anchored 4.1 and 5.5
  but not 5.2 (intro amendment list).
- Proposal P15, rewriting 5.2 (validated):
  "WHEN a pull request affects an image or chart THE Test Suite SHALL install
  each affected chart adaptation deploying an active definition's images on a
  kind cluster in CI." No count change.

### 5.16 The authoritative scanner is data in 9.11 and prose in 6.1 (Medium)

- Contradict: partly (a fork that re-marks its authoritative consumer edits a
  criterion). Same thing: no. Necessary: yes, both. Simplify: yes.
- Evidence: 6.1 "SHALL run Trivy and fail on every finding..."; 9.11 "exactly
  one consumer marked authoritative"; the Req 2 terms paragraph already
  defines "uncovered finding" as exactly 6.1's predicate.
- Proposal P18, rewriting 6.1 to read the declared consumer and the defined
  term (validated):
  "WHEN a pull request builds an image THE Scan Gate SHALL scan that image
  with its declared authoritative consumer and SHALL fail on every uncovered
  finding in that scan's report."
  The terms paragraph then drops its pointer sentence "it is what criterion
  6.1 fails on". 6.12's Trivy-ignore lint stays as a scanner-specific tooth.
  No count change.
- Possibly deliberate: the 5.1 addendum keeps Trivy authoritative "with its
  coupling stated"; cluster D ledger 3.10 moved authoritativeness to data.
  P18 preserves both: Trivy stays the declared value, the criterion stops
  hardcoding it.

### 5.17 Build-failure reporting bound to pull request checks (Low)

- Contradict: no (wording gap). Same thing: no. Necessary: yes. Simplify: yes.
- Evidence: 2.5 "report each failing step in pull request checks" while 2.7
  names merge, schedule and dispatch as release triggers; a scheduled build
  failure has no pull request.
- Proposal P16, rewriting 2.5 (validated):
  "IF an image build fails THEN THE CI Pipeline SHALL publish no artifacts
  from that run and SHALL report each failing step in that run's checks."
  No count change.

### 5.18 Actor vocabulary drift (Low)

- Contradict: no. Same thing: no. Necessary: yes. Simplify: yes.
- Evidence: 7.6 binds "THE Upstream Tracking" where Req 3 calls the same
  subsystem "THE Renovate Automation"; 6.13 and 9.12 bind "THE Scan Pipeline"
  for pull-request-time work the rest of the book gives "THE Scan Gate".
- Proposal P19, rewriting 7.6 (validated):
  "IF a pinned third-party executable has a newer released version THEN THE
  Renovate Automation SHALL open a pull request updating that pin."
  The 6.13/9.12 actor naming is held as a note (both criteria are otherwise
  sound; renaming is cosmetic). No count change.

### 5.19 Held observations, no proposal (Note)

- 2.23 hardcodes the certificate issuer value in criterion text while 7.7
  declares 2.23's inputs; deliberate GitHub coupling per the 5.1 addendum,
  held.
- 9.1 requires SECURITY.md to state "its epoch", a term no requirements text
  defines (design Decision 9 defines it); a one-line addition to the Req 2
  terms paragraph would close it, at the cost of one sentence.
- 6.3 requires an EPSS score with no outage rule, while KEV has 6.59 and 6.60;
  asymmetry held (a new rule lengthens the book; the owner decided KEV
  fail-closed deliberately, cluster B ledger 1.8).
- 1.10 enumerates authenticity class `none` that 1.11 refuses unconditionally;
  held as vocabulary for forks (cluster C ledger 1.13, "nothing is
  grandfathered", deliberate).
- 6.46 and 9.1 are single criteria of unusual density; splitting either would
  grow the count without adding machinery, held.

## Proposed primitive set

The target shape after applying every proposal above, keeping the promise
surface (signed digests via 2.7 to 2.13 and 2.20 to 2.25; complete honest
statuses via the compiler, lint and lifecycle criteria; measured clocks via
6.46, 6.47 and 6.49 to 6.51; forkability via the policy file, active set,
builder contract and Req 9 posture) intact:

| Group | Now | After | Change |
|---|---|---|---|
| 1 Image definitions | 19 | 17 | 1.5 into 7.2; 1.7 and 1.8 into one authored-syntax criterion |
| 2 Build and release | 26 | 22 | 2.4, 2.6, 2.18, 2.19 removed; 2.22 becomes the single enumeration-and-scan primitive; 2.5, 2.26 reworded |
| 3 Upstream tracking | 12 | 11 | 3.6 removed |
| 4 Chart adaptation | 9 | 9 | unchanged |
| 5 Integration tests | 8 | 8 | 5.2 anchored to the active set |
| 6 CVE triage | 60 | 50 | 6.2, 6.6, 6.18, 6.21, 6.23, 6.24, 6.31, 6.36, 6.45, 6.48 removed by merge or deletion; 6.1, 6.7, 6.11, 6.17, 6.20, 6.29, 6.44 reworded |
| 7 Conventions and review | 10 | 10 | 7.2, 7.6, 7.7 reworded, absorbing 1.5 and the declared-values gaps |
| 8 Operating environment | 2 | 0 | group removed to design and CONVENTIONS.md |
| 9 Catalogue posture | 18 | 18 | unchanged |
| **Total** | **164** | **145** | net minus 19 |

The resulting rulebook has one criterion per primitive: one daily enumeration
that carries scans, visibility and verification; one release gate with one
unambiguous failure rule; one exception record with one omission lint; one
compiled-document identity rule; one attestation-count invariant; declared
values in one file that its own lint can actually check; and no criterion that
exists because of how this repository got here. Costs to plan: removals leave
number gaps or force renumbering, and design.md, tasks.md and earlier reviews
cite the old numbers, so the encoding commit needs the same cross-reference
sweep the earlier clusters ran. Two further merges were weighed and not
proposed: folding 6.49 into 7.7 (triage numbers read best beside the triage
criteria that consume them) and folding 1.6's named-message floating-tag lint
into 1.5/7.2 (a specific tooth worth its line).

## Method

Read in full: `requirements.md` (subject, 164 criteria); critique section 5.1
with the 2026-08-25 framing addendum, sections 5.2, 5.3 and 6 of
`2026-08-21-production-readiness-critique.md`; design.md Key Design Decisions
1 to 11 plus flows headings; all six revision ledgers under `reviews/`
(cluster A, cluster B, cluster C, cluster D, greenfield epoch, final cleanup);
the EARS validator source. Validated: the real `requirements.md` (PASSED, 164
valid) and all 15 proposed replacement texts in a `/tmp` scratch file (PASSED,
15 valid); a numeric sweep confirmed no removal candidate is cross-referenced
by number from a surviving criterion (the only references, criterion 2.18
inside 2.22 and criteria 6.52 to 6.57 inside 6.48, disappear with their
hosts). Iteration depth: iteration 2 reached specific criteria for every hot
cell; no iteration 3 was needed. Not judged, and why: implementability of the
merged criteria against the as-built workflows (this review read spec
artifacts, not `.github/workflows/`, `scripts/` or `renovate.json5`); whether
9.12's adapters in practice run full scans (the basis for removing 6.6 is the
criteria's own text plus the F7 decision, not measured adapter behavior);
Rekor, cosign and Trivy behaviors, taken from ADR 0003/0004 as recorded; and
the renumbering cost across design.md and tasks.md, noted but not mapped
row by row. No spec file was modified; this report and its two measure
siblings are the only files written.
