# PR #100, cluster B spec amendment: independent adversarial review, 2026-08-24

**Subject:** `spec-cluster-b` at `38e3a42` against `main` at `00fbe79`: five files,
216 insertions, 14 deletions (`.specs/dhc-catalogue-mvp/requirements.md`, `design.md`,
`tasks.md`, `reviews/2026-08-21-production-readiness-critique.md`, `tasks/todo.md`).
The PR claims to encode the cluster B decisions (critique F5, F4, and the issue-closing
half of F13, as amended on this branch on 2026-08-23) as Req 6.38 to 6.54, amendments to
Req 2.6, 2.8, 6.1, 6.3, 6.7, 6.8, 6.10, 6.11 and 6.35, a *decision aperture* term under
Req 2, Key Design Decision 7, a rescan flow, five error-table rows, and task group 10.
Three earlier commits on the branch amend the critique's cluster B entries (`6fde05b`,
`64462b6`, `6e72720`); the spec commit is `38e3a42`. No workflow, script, policy or
triage changes.

**Method.** Read with no prior involvement: `CLAUDE.md`, `docs/CONVENTIONS.md`, the full
PR-side `requirements.md`, `design.md`, `tasks.md` and `tasks/todo.md`, the critique
(F4, F5, F13, section 5.2 with the 2026-08-23 amendments, section 6, the ledger), the two
spikes (ADR 0003 on `main`; ADR 0004 with its ADR 0003 amendment, the upstream draft and
the check script in the `spike-replace-attestation` worktree, not yet on `main`), then the
real pipeline the criteria have to run on: `.github/workflows/rescan.yml`, `build.yml`,
`validate.yml`, `scripts/compile-vex.sh`, `lint-accepted-risk.sh`, `lint-vex-product.sh`,
`triage/rescan/report.go`, `triage/accepted-risk/grafana.yaml`, `triage/vex/*.json`,
`triage/LOG.md`, `README.md`, `docs/user-manual.md`, `triage/README.md`. Tool runs: the
repo's EARS validator on both branches; the `spec-validate` procedure applied by hand; the
`ears-notation` skill's rules for section 1; the `code-review` skill launched against the
branch, cut short by a session usage limit before it consolidated anything (section 4).
Where a finding turned on tool behaviour or registry state, it was measured
(2026-08-23/24): trivy 0.72.0 with the 2026-08-22 DB snapshot and vexctl v0.4.4 in the
devcontainer against the published `hardened-app` digest, and anonymous reads against
`ghcr.io/mm-weber/dhc` (script and output beside this file:
`2026-08-24-cluster-b-independent-review.measure.sh` / `.measure.out`). Spec citations are PR-branch
line numbers; workflow, script and doc citations are `main`, which the PR does not touch.
The PR is judged on its own text; the critique is used only to check faithfulness.

**Verification legend**

| | |
|---|---|
| **[V]** | verified directly against the tree or the git history, with `path:line` |
| **[M]** | measured 2026-08-23/24: trivy/vexctl in the devcontainer, anonymous reads against `ghcr.io` and `api.github.com` |
| **[R]** | reasoned from documented tool behaviour (cosign, Trivy, go-vex, Kyverno, GHCR), not measured here; the implementing task should measure first |

**How to read.** Findings are ordered by severity. Each carries a diagnosis and, where a
criterion is defective, a concrete rewording. Section 3 lists what was checked and found
sound, so the findings read as aimed at the gaps, not at the decisions.

---

## 1. Findings

### 1.1 **[M][V]** Req 6.46, 6.52 and 6.53 read "the attested scan report", and that report omits every suppressed finding: an accepted finding clocks as fixed and closes as gone

**Claim.** Req 6.46 (`requirements.md:168`) computes fix time from the first digest
"whose attested scan report omits it"; Req 6.52 (`:174`) closes an issue when its finding
"appears in no tag-referenced digest's attested scan report"; Req 6.53 (`:175`) closes,
separately, when every finding is *covered*. The attested report is the rescan's own scan
(Req 6.42, `:164`), and Req 2.8/2.18 make that scan apply "every compiled VEX document and
every unexpired accepted-risk exception".

**Evidence.** A Trivy scan given `--vex` and `--ignorefile` drops suppressed findings from
the JSON entirely unless `--show-suppressed` is passed; measured **[M]** on
`hardened-app@sha256:8eee1329…`: with a `not_affected` statement applied and no
`--show-suppressed`, `.Results[].Vulnerabilities` holds 7 of 8 and
`ExperimentalModifiedFindings` is `[]`; with the flag, the suppressed finding appears
under `ExperimentalModifiedFindings` (never back in `.Vulnerabilities`) and survives
`trivy convert --format cosign-vuln` into the predicate. The PR gate passes the flag
(`build.yml:324`); the rescan does not (`rescan.yml:137-138`), and the rescan is the arm
Req 6.42 attests from. `rescan.yml:86-88` applies the exception file to every grafana
scan, with no tag scope.

**Consequence.** Under the criteria as written, every finding suppressed by an unexpired
exception is absent from every attested report: Req 6.46 assigns it a fix time, and
Req 6.52's WHEN clause is satisfied at the same time as Req 6.53's, two contradictory
mandatory closes for the same issue (one labelled as gone with digests as evidence, one as
covered with the exception as evidence; task 10.6 maps the first to `resolved:fixed`,
which is false). Whether it fires on day one for #22/#24/#26/#56 depends only on whether
the same CVE id still shows in some other image's report; the structural collapse of the
gone/covered distinction is unconditional. The same shape makes the headline promise
("time-to-fix measured rather than promised") report an accepted finding as fixed.

**Diagnosis.** Make the report shape part of the criterion and define "appears".
Rewordings:

- Req 6.42: "... SHALL attest each tag-referenced platform manifest's scan report,
  recording suppressed findings, to that manifest, ...".
- Req 6.52: "... names appears, as a reported or as a suppressed finding, in no
  tag-referenced digest's attested scan report ...", and the matching clause in Req 6.46:
  "whose attested scan report lists it neither as a reported nor as a suppressed
  finding".

Task 10.3 should name the `--show-suppressed` change to `rescan.yml` (today only
`build.yml` carries it), and the release-time scan of task 9.1 needs the same flag for
the same reason, or the two arms attest reports of different shapes.

### 1.2 **[V]** Req 6.46's decision and fix clocks cannot be computed from the inputs the spec names

**Claim.** Req 6.46 (`requirements.md:168`): first seen "from its statement's timestamp",
decision time "from that statement's last_updated at its first status other than
under_investigation", fix time "from that release line's first tag-referenced digest
whose attested scan report omits it".

**Evidence, three independent gaps.**

- *Decision time.* Only a carried-forward statement ever receives a `last_updated`
  (Req 6.40, `:162`, on change during carry-forward). A finding covered at release by a
  source `not_affected` or `fixed` statement compiles from `triage/vex/`, whose statements
  carry no statement-level `last_updated` (all three files, e.g.
  `triage/vex/CVE-2026-21728.openvex.json`); a finding covered at its first appearance by
  an exception gets a fresh `affected` statement for which no criterion sets
  `last_updated` at all. In both cases "last_updated at its first status other than
  under_investigation" reads a field that does not exist. And where it does exist, "at its
  *first* status other than under_investigation" needs the value the field held at that
  past compile: the attested document holds only the latest `last_updated`, so a finding
  that lapsed and was re-decided (Req 6.41's cycle) has lost the first decision's date
  everywhere except the transparency log, whose retention of replaced entries is itself
  unmeasured (see 1.5). Even in the one clean case (decided exactly once, after
  under_investigation), the value is the compile time of the rescan run after the decision
  merged, not the decision date the exception records in `decided_at`; the spec measures
  time-to-publication and calls it time-to-decision.
- *Release line.* The term occurs once in the whole document (`:168`), is defined nowhere,
  and the Req 2 terms (`:45`) define tags, not lines. grafana's tag-referenced set today is
  `13`, `13.0`, `13.0.4`, `13.1`, `13.1.2`, `13.1.3` **[M]**; whether `13.0.4` and `13.1.3`
  share a line decides whether a finding fixed in 13.1.x gets a fix time while `13.0.4`
  still serves it.
- *Fix date.* "That release line's first tag-referenced digest whose attested scan report
  omits it" yields a digest, not a time, and no named input carries the ordering: the
  enumeration (Req 2.22) is tags to digests with no dates, and the attested report's
  timestamp is replaced daily (Req 6.42), so every digest's report is dated today.

**Diagnosis.** The defect is inherited faithfully from the critique's own 2026-08-23
amendment (`critique:790-805`), so per the amend-first rule the correction is a critique
amendment plus the criterion in one commit. Suggested shape:

- Decision time: "its decision time from that statement's action statement timestamp
  where its status is affected, and from that statement's timestamp where its status is
  not_affected or fixed". That is computable from the current document alone, equals
  `decided_at` for exceptions (Req 6.38) and the author's dated decision for source
  statements (house style stamps the LOG date, e.g.
  `triage/vex/CVE-2026-42151.openvex.json` `timestamp: 2026-07-26`), and frees
  `last_updated` to be provenance rather than a clock.
- Define *release line* in the Req 2 terms (the natural reading: the digests a
  repository's full release tags reference, ordered by release; say so), and name the
  date source for "fixed": the release signature or first scan-report attestation for
  that digest as logged (needs 1.5's Rekor measurement), or the rescan's own
  `metrics.json` history carried in the status issue, which needs no external log.

### 1.3 **[V][M]** Req 6.38 adds an `affected` statement unconditionally and never says what `timestamp` it carries; both halves contradict the recorded timestamp semantics

**Claim.** Req 6.38 (`requirements.md:160`): "for every unexpired accepted-risk exception
naming a finding in that document's digest" the compiler SHALL add an `affected`
statement; the only timestamp it names is the action statement timestamp (`decided_at`).
The critique decided (`critique:802-805`): one catalogue statement per finding per
document, a later `not_affected` or `fixed` source statement *replaces* the catalogue
statement, and (`:790-793`) a catalogue statement's `timestamp` is first seen.

**Evidence.** Nothing in Req 6.38 to 6.41 carries the replacement rule: as written, a
finding holding both a source statement and an unexpired exception (nothing lints that
combination; `lint-accepted-risk.sh` and `lint-vex-product.sh` never cross-read) compiles
to two competing statements. Measured **[M]**: Trivy orders by statement `timestamp` and
ignores `last_updated` (a `not_affected` at 2026-08-01 beside an `affected` with
timestamp 2026-07-01 and last_updated 2026-08-20 stays suppressed; move the `affected`
timestamp to 2026-08-15 and the finding is reported). So whichever statement's
*first-seen-or-author* date is later silently decides what every consumer's scanner
shows, exactly the coin flip the one-statement rule was decided to prevent. And because
no criterion sets the `affected` statement's `timestamp` at all, an implementer
reasonably reaches for `decided_at`, which breaks first seen (Req 6.46 reads first seen
from that same field), or for compile time, which breaks it worse. For the twelve
existing grafana entries there is no previously attested statement to inherit from, so
first seen has no defined value on day one; the recorded candidate (the issue creation
date as cross-check, `critique:787-789`) is named nowhere in the spec.

**Diagnosis.** Two additions to Req 6.38: "... for every unexpired accepted-risk
exception naming a finding in that document's digest that no source statement under
triage/vex/ covers, an OpenVEX statement recording status affected, whose timestamp is
that finding's first-seen time (the timestamp of the statement previously attested for
it, or, where none exists, that digest's attested scan report timestamp), whose action
statement carries ...". And a migration sentence in task 10.2 naming where the twelve
existing exceptions' first-seen values come from (the `cve` issue creation dates,
2026-07-23 onward **[M]**, are the only recorded candidates).

### 1.4 **[V]** Req 6.43's trigger is wrong in both directions: the document timestamp makes "differs" true every day, and a violated one-attestation invariant is never repaired

**Claim.** Req 6.43 (`requirements.md:165`) re-attests "WHEN a compiled document for a
tag-referenced digest differs from that digest's attested OpenVEX document". Req 6.44
(`:166`) declares exactly one OpenVEX attestation as an invariant; Req 6.45 (`:167`)
reports violations as run failures. The error table promises "the next re-attestation
replaces" (`design.md:784`).

**Evidence.**

- *Fires always.* ADR 0003 fixed the document identity as "`timestamp` the compile time"
  (`docs/decisions/0003-…:91`), so a freshly compiled document differs from yesterday's
  byte-wise on every run even when no statement changed. The original decision compared
  "statement sets" (`critique:697-699`); the criterion dropped that qualifier. Cost: a
  keyless re-attestation of every tag-referenced digest and platform manifest daily,
  which is exactly the append-era churn the on-change design exists to avoid.
- *Never repairs.* If a digest carries more than one OpenVEX attestation while the
  compiled document equals the chosen "attested document", 6.43's WHEN clause is false
  and nothing replaces; 6.45 then fails the run every day forever. The state is
  reachable inside the spec: under the declared publish policy `always` (Req 2.17,
  `:65`), a scheduled rebuild that reproduces the published index digest (the
  reproducibility measurement Decision 6 logs nightly, `design.md:207-211`, is the
  catalogue's own instrument for this becoming common) publishes "through criteria 2.7
  to 2.9", and Req 2.9's release attestation appends (`build.yml:654` today; task 9.1
  keeps plain `cosign attest`). It is also the transitional state: grafana's current
  digest carries three OpenVEX layers right now, re-confirmed **[M]**, and task 10.3's
  "first run replaces" (`tasks.md:270`) holds only while the fresh compile happens to
  differ from whichever of the three the comparison picked, which is itself undefined
  ("that digest's attested OpenVEX document", singular, when three exist).
- *Zero is invisible.* Req 6.45 reports "more than one"; 6.44 says exactly one. A
  platform manifest with zero is caught by nothing: Req 2.24 (`:72`) applies the policy
  to digests catalogue tags reference, which are the indexes.

**Diagnosis.** One rewording closes all three: "WHEN a compiled document for a
tag-referenced digest differs in its set of statements from that digest's attested
OpenVEX document, or WHEN that digest or any of its platform manifests carries a number
of OpenVEX attestations other than one, THE Scan Pipeline SHALL attest that compiled
document to that digest and to each of its platform manifests, replacing every existing
OpenVEX attestation on each." Say in task 10.3 how the comparison canonicalises (ignore
document `@id`/`timestamp`/`version`, compare statements), and, when several are
attested, that the carry-forward input is their merge (`vexctl merge` preserves the
timestamp fields, measured **[M]**).

### 1.5 **[V]** Req 6.42's "replacing any scan report attestation it previously made" understates the mechanism, and the branch claims a Rekor measurement the ADR lists as unmeasured

**Claim.** Req 6.42 (`requirements.md:164`) has the rescan replace "any scan report
attestation *it* previously made". Req 2.12 (`:60`) derives `under_investigation`
statements from the release-time report "as criterion 2.9 attests it"; Decision 7 and
ADR 0004 rest history on "Rekor plus recompute".

**Evidence.** cosign v2.6.0's `--replace` removes every existing attestation of the same
predicate type regardless of author (ADR 0004, measured: the evidence table and
`critique:718-720`). The rescan and the release job both use the `vuln` predicate
(task 9.1 `tasks.md:217`, task 10.3 `:267`), so the first rescan after any release
destroys the release-time report attestation that Req 2.12 anchors; from then on it
exists only in Rekor. The critique's F5 (ii) amendment states the spike "measures, on
v2.6.0, ... that the old entry remains in Rekor" (`critique:735-737`), while ADR 0004
itself lists exactly that as "Unmeasured here" because the spike ran with
`--tlog-upload=false` (`spike worktree docs/decisions/0004-…:107-110`), alongside
"`--replace` under keyless signing behaves as with a key". Task 10.3 orders neither
measurement first, unlike task 9.1's precedent for `--recursive` (`tasks.md:216`).

**Consequence.** The criterion's wording invites an implementation that tries to
distinguish "its own" attestation (impossible with `--replace`), and the history story
that 1.2's clocks and the recompute guarantee lean on rests on two unmeasured claims,
one of them presented in the critique as measured.

**Diagnosis.** Reword Req 6.42: "... replacing every scan report attestation of that
predicate type on that manifest, ...". Correct `critique:735-737` to match ADR 0004's
unmeasured list (one of the two texts is wrong today). Add to task 10.3: measure first,
in CI, that a keyless `--replace` behaves as the key-based spike did and that a replaced
entry remains retrievable from Rekor; state in Decision 7 that the release-time report
attestation is superseded by the first rescan and Rekor is its only retention.

### 1.6 **[V]** The aperture is declared, but no task makes anything read it: the amended Req 2.6, 2.8, 6.1 and 6.3 have no implementing task

**Claim.** The PR amends Req 2.6, 2.8, 6.1, 6.3 (`requirements.md:54`, `:56`, `:123`,
`:125`) from "HIGH and CRITICAL" to "findings within that decision aperture", and
Req 6.49/task 10.1 declare the aperture in the policy file.

**Evidence.** The aperture is hard-coded in three places the criteria now govern:
`build.yml:322` (`--severity HIGH,CRITICAL`, the Scan Gate of 6.1),
`rescan.yml:137` (the Scan Pipeline of 2.6/6.2/6.3), and
`triage/rescan/report.go:170-180` (`sevRank` returns 0 for everything but CRITICAL and
HIGH, the filter behind 6.3). Task 10.1 (`tasks.md:255-259`) covers only the ceilings,
KEV and warning-window halves; no 10.x or 9.x bullet names the `--severity` values or
`sevRank` becoming policy-file reads, and no task is annotated with Req 2.6, 2.8, 6.1 or
6.3 for the aperture (6.1 is annotated on completed task 7.1, which implemented the old
text; the Req 2 coverage row is unchanged). Req 6.50/6.51's "its finding's severity"
likewise assumes the gate and rescan know severities outside the current hard-coding.

**Consequence.** A fork editing the declared list (`aperture: [CRITICAL, HIGH, MEDIUM]`,
the fork switch Decision 7 advertises, `design.md:304-305`) changes nothing anywhere;
the amended criteria are unimplementable from the task list as written, which is the
input `/spec-implement` reads.

**Diagnosis.** Add to task 10.1: `build.yml`, `rescan.yml` and the release-time scan
read `--severity` from the policy file's `triage.aperture` (they already read release
switches with `yq` per 9.8); `triage/rescan` takes the aperture as an input instead of
hard-coding `sevRank`. Annotate Req 2.6, 2.8, 6.1, 6.3 on it and add 10.1 to the Req 2
coverage row.

### 1.7 **[V][M]** Evidence-based closing meets the enumerated published set: issues over legacy digests never close, the reopening story is false to the code, and absence is labelled as fixed

**Claim.** Req 6.52/6.53 close on evidence over "every tag-referenced digest"; task 10.6
says the dedup marker "still keys reopening if the finding returns" (`tasks.md:280`);
task 10.6 maps the gone case to `resolved:fixed`.

**Evidence.** The tag-referenced set is permanent: 16 digests today across six
repositories, including cert-manager `1.20.3`/`1.21.0`, grafana `13.0.4`/`13.1.2` and
valkey `9.0.5` **[M]**, none of which is ever rebuilt. An issue like #28
(GHSA-hrxh-6v49-42gf, named images include cert-manager-controller and webhook, open
since 2026-07-23 **[M]**) closes under 6.52 only when the finding leaves every one of
those frozen-in-content reports (never, short of a DB change) and under 6.53 only when
covered on the digests where it appears, and no cert-manager exception or statement
exists. So the `cve` badge Req 6.48 puts in the README counts a floor of never-closable
issues that grows with every superseded release, and the promise "the rescan closes
issues" holds mostly for the newest digests. Nothing in the PR says this; the tag
retention question belongs to cluster D, but the interaction is created here. On
reopening: the dedup reads open issues only (`rescan.yml:211`, `--state open`), so a
finding that returns after a close files a duplicate new issue rather than reopening;
no criterion covers either behaviour, and the task's sentence describes code that does
not exist. On labels: `resolved:fixed` for "appears in no report" asserts a reason for
the absence that the run does not know (package dropped, tag retired, DB regression,
scanner change all look identical), sitting oddly beside Req 6.54's "SHALL NOT record a
triage decision itself"; a DB regression that empties a report would mass-close with
"fixed" as the label.

**Diagnosis.** Three small changes: (a) state the consequence in design Decision 7 and
the PR body, and either scope 6.52/6.53's quantifier to digests whose reports list the
finding (for 6.53) plus an explicit note that 6.52 is expected to be rare while legacy
tags stand, or record that tag retention moves to cluster D with this dependency named;
(b) either add a reopening criterion ("WHEN a scheduled rescan finds a finding named by
a closed cve issue in a tag-referenced digest's attested scan report THE Scan Pipeline
SHALL reopen that issue or open a new one referencing it") or fix task 10.6's sentence;
(c) label the 6.52 case by what is known (`resolved:absent` or the comment naming
scanner and DB versions), keeping `resolved:fixed` for 6.53's fixed-statement case.

### 1.8 **[V]** Req 6.50's gate tier check: no failure mode for the KEV fetch, no severity source, and an over-ceiling exception merged past the gate is only ever "reported"

**Claim.** Req 6.50 (`requirements.md:172`) fails a pull request on any exception whose
expiry exceeds its severity or KEV tier; task 10.1 has the gate fetch "the rescan's
`KEV_URL`".

**Evidence.** The rescan's own KEV fetch is best-effort and degrades to "nothing marked
KEV" (`rescan.yml:190`). Transplanted, that shape silently applies the looser
severity ceiling to a KEV-listed finding on the day CISA is unreachable; failing closed
instead reddens every image PR on a feed outage. The spec chooses neither, and the
error table's new row (`design.md:785`) does not say. Severity: the criterion says "its
finding's severity" without a source; the gate holds the Trivy report for the image it
built, but an exception whose entry no longer matches any finding (the dead entry
Req 6.26 deliberately only reports) has no severity to tier against. Scope: 6.50 runs
"WHEN a pull request builds an image", so an over-tier exception that merges through a
docs-only PR, or that becomes over-tier when KEV status changes, is caught only by
Req 6.51, which "SHALL report", not fail; nothing red ever stands behind the tier for an
image no PR touches.

**Diagnosis.** Add the outage rule as its own criterion (suggest fail-open with a named
warning, matching the rescan's soft-fail philosophy, but say it: "IF the KEV feed is
unavailable to a pull request scan THEN THE Scan Gate SHALL apply the severity ceilings
alone and SHALL report that the KEV ceiling was not evaluated"). Say the severity source
("that image's scan report's severity for that finding; an exception matching no finding
is tiered by its largest applicable ceiling") and whether 6.51's report should escalate
(the daily invariants step failing the run is the house lever, `design.md:248-255`).

### 1.9 **[R]** The carry-forward input is not required to be verified: an unverified read re-signs whatever is sitting on the digest

**Claim.** Req 6.37 (cluster A, `requirements.md:159`) names "any OpenVEX document
previously attested to that digest" as a compiler input; Req 6.40 carries its statements
forward; Req 6.43 attests the result under the re-attester identity.

**Evidence/Consequence.** Neither criterion nor task 10.3 says the previous document is
read through `cosign verify-attestation` against the identities Req 2.23 admits. A
`cosign download attestation` read accepts any attestation anyone with package write
access ever pushed (the threat Decision 7's own trade-off names,
`design.md:295-299`); the rescan would then launder injected statements, timestamps
included, into a document signed by the trusted identity. The compensating control the
design names (Req 2.24's daily policy proof) checks that valid attestations exist, not
that the compiler ignored invalid ones **[R]**.

**Diagnosis.** One clause, in Req 6.43 or as 6.43a: "THE Scan Pipeline SHALL read a
previously attested OpenVEX document and attested scan reports only through a
verification that admits the identities criterion 2.23 admits for that attestation
type." Name it in task 10.3.

### 1.10 **[V]** Amended Req 6.8 binds the wrong actor and restates Req 6.38 with less precision

**Claim.** Req 6.8 (`requirements.md:130`): "THE Triage Process SHALL NOT record ... as a
VEX statement with a status that suppresses a finding, and SHALL publish each as an
OpenVEX affected statement carrying an action statement."

**Evidence.** The publisher is THE VEX Compiler (Req 6.38), and THE Triage Process is
forbidden from authoring `affected` at all (Req 6.39 fails any source status other than
not_affected or fixed). So the second SHALL commands an actor to do something another
criterion forbids it from doing itself and a third assigns to someone else. "A status
that suppresses a finding" is also an indirect spelling of a two-element closed set.
This is the one two-actor-shaped criterion in the PR (the cluster A review's 1.16
precedent).

**Rewording.** "THE Triage Process SHALL NOT record accepted risk or upstream transfer
as a VEX statement recording status not_affected or fixed." Publication is already
Req 6.38's sentence; if a pointer is wanted, "criterion 6.38 publishes each as an
affected statement" belongs in the design, not in a SHALL.

### 1.11 **[V]** Req 6.41 fires for findings the scan no longer lists and reads an "original timestamp" that pre-cluster-B exceptions do not have

**Claim.** Req 6.41 (`requirements.md:163`): a lapsed exception compiles to
`under_investigation` "for each finding it named, carrying each finding's original
timestamp".

**Evidence.** "Each finding it named" is unconditional on the finding still appearing in
the digest's attested report, so a lapse after the finding left the image (rebuild,
upstream fix) would emit an `under_investigation` statement for a finding no scanner
reports, on every digest, forever (Decision 6's carry-forward is "never drop",
`design.md:225-228`). And "original timestamp" presupposes a previously attested
statement; the twelve existing entries (all twelve in
`triage/accepted-risk/grafana.yaml`) predate any attested statement, the same migration
gap as 1.3. Also worth stating beside it: an expired entry cannot rest in the tree,
because the lint hard-fails on a past `expired_at` (`lint-accepted-risk.sh:158-160`),
so 6.41's compiled lapse state exists only in the window before a human re-decides or
deletes; after deletion, the finding follows the plain uncovered path. That is coherent,
but an implementer of 6.41 should know the state is transitional by design.

**Rewording.** "IF an accepted-risk exception has passed its expiry date THEN THE VEX
Compiler SHALL compile no affected statement from it and SHALL record status
under_investigation for each finding it named that that digest's attested scan report
lists, carrying that finding's first-seen time under criterion 6.38 and a status note
naming that lapse." (With 1.3's first-seen definition, the migration gap closes here
too.)

### 1.12 **[V]** Design text the PR leaves standing contradicts Decision 7, and two cluster A promises about cluster B are not delivered

- `design.md:172-174` (Decision 6): the re-attester "may attest OpenVEX only, never
  sign, never tag". Req 6.42 and tasks 9.6/10.3 have it attest the `vuln` predicate
  daily. Amend the sentence ("may attest OpenVEX and scan reports only").
- The release flow (`design.md:317`, `:322`) has pass 1 as "not_affected / fixed from
  triage/vex/" and pass 2 as "append under_investigation"; Req 6.38's `affected`
  statements fit in neither as drawn (they need the scan report, so they belong in
  pass 2). The rescan flow (`:336-339`) got this right; the release flow was not
  updated.
- `design.md:154-155` and task 9.1 (`tasks.md:218`) promise "the issue link arrives
  with the next rescan and cluster B's re-attestation"; no cluster B criterion or task
  puts an issue reference into any statement. Either add it (a status-notes issue URL
  on carry-forward is a content change under 6.40, so say it does not count as one) or
  strike the promise in both places; today it dangles.
- As-built text contradicted in the same file with no supersession note (the house
  pattern the cluster A review's 1.13 established): `design.md:428-430` ("accepted-risk
  ... internal, never attested"), `:440-441` ("the 90-day ceiling"), `:626-627` ("an
  emptied document is never written", already superseded by ADR 0003). Mark them
  "as specified (Decision 7, tasks 10.1/10.2)" or reword.

### 1.13 **[V]** The truth pass misses the two documents that state the old model most bluntly, and Req 6.4 is left un-amended although the ledger names it

Task 10.7 (`tasks.md:282-284`) lists `docs/user-manual.md`, `README.md`,
`triage/README.md`, `triage/accepted-risk/README.md`. Missing:

- `docs/CONVENTIONS.md:219-228`: "must never be written as a VEX (Req 6.8)" and
  "an `expired_at` no more than 90 days out", both false after 10.1/10.2; Req 7.1 is
  annotated on 10.7, so the file is in scope but unnamed.
- `triage/accepted-risk/grafana.yaml:6`: "Nothing here is ever attested (Req 6.8)" in
  the header of the very file 10.1 edits for `decided_at`.
- `build.yml:276-277` carries the same sentence as a comment; 9.1 rewrites that step,
  but nothing in 9.1's text flags the sentence, so it will survive verbatim unless
  named somewhere.
- `docs/user-manual.md:487` ("the cron opens issues, it never closes them") is in the
  rescan section 10.7 does touch, but the bullet names only "replace-not-append and the
  status issue"; add issue closing to the list (also `:237`, `:511`, `:607`, `:623`,
  `:988` for the two-lane table and the 90-day spellings, which the bullet does cover).
- Req 6.4 (`requirements.md:126`) still has THE Triage Process attach statements to
  images "as an attestation"; attaching is the release job's and rescan's under
  Req 2.9/6.43. The disposition ledger names Req 6.4 as F5's spec impact
  (`critique:1146`); the PR neither amends it nor declares the leave-as-is, the exact
  dangling-pointer shape the cluster A review flagged for Req 2.2 (its 1.14).

### 1.14 **[M][R]** The daily cost and growth of Req 6.42/6.43 are never stated

Measured today **[M]**: 16 tag-referenced digests, 24 platform manifests across the six
repositories. Req 6.42 makes that 24 scans (about 35 s each per task 8.3's measurement,
`tasks.md:175`, so roughly 15 minutes) plus 24 keyless `vuln` attestations per day, every
day, each a Fulcio certificate and Rekor entry and a `.att` manifest rewrite; the set
only grows, since releases add tags and nothing retires them (cluster D). The cosign-vuln
predicate embeds the full report (38 KB for hardened-app's 8 findings **[M]**; grafana's
is a multiple), re-uploaded daily; each replaced `.att` manifest strands its predecessor's
blobs on GHCR **[R]**. None of this is prohibitive at today's size, and the OpenVEX side
is correctly on-change (once 1.4 lands), but the PR text nowhere says "about 25 scans and
25 transparency-log entries per day, growing with every release", which is the number the
owner accepts by merging and a reviewer of `rescan.yml`'s runtime will want written down.
Add it to Decision 7's trade-offs with the measured baseline.

### 1.15 Smaller defects, one line each

- Req 6.40 (`requirements.md:162`): "its change time" is unbound; say "the timestamp of
  the scan report that compilation used" or "the compile time", and scope the criterion
  to catalogue-written statements ("carries a statement it wrote forward"), else an
  edited source statement must keep its old timestamp, which collides with Req 6.22's
  supersede-by-later-timestamp model.
- Req 6.48 (`:170`): "that cve label" has no antecedent (the label first appears in
  6.52); write "the cve label that criteria 6.52 to 6.54 close".
- Req 6.49 (`:171`): "an exception ceiling per severity" should be "per severity in that
  decision aperture", or task 10.1's fork sentence ("a fork widens the aperture") creates
  apertures with no ceiling and an unlintable 6.11.
- F4 (i)'s example ceilings include `CRITICAL: 24h` (`critique:745-748`); `decided_at`
  is specified as an ISO date and `expired_at` is a date Trivy expires at midnight
  (`design.md:435-436`), so sub-day durations are unexpressible; either constrain the
  schema to whole days or specify datetimes.
- Req 6.52/6.53's "a resolved label" leaves the label set to task text; since Decision 7
  declares `resolved:*` a fork switch, write "one of that catalogue policy file's
  resolved labels" or accept the task as the only source.
- Task 10.2 (`tasks.md:263`): "gate coverage ignores affected and under_investigation
  ..., which Trivy does anyway (ADR 0003)": ADR 0003 measured no such thing; the
  measurement is design.md's supersession table (`design.md:648-661`) plus this review's
  d4/d5 **[M]**. Cite those.
- `requirements.md:21` cites ADR 0004 as a cluster B spike, but ADR 0004 exists only on
  the `spike-replace-attestation` worktree (PR #99); merge order matters or the intro
  cites a document `main` does not hold.
- Req 6.47 (`:169`): "every open finding" is undefined (open issue? statement with a
  non-terminal status?); one clause fixes it, and note the ceilings it ages against are
  re-decision intervals by the critique's own definition (`critique:751-753`), so the
  table compares an undecided finding's age to a decided finding's re-decision clock;
  faithful to F4 (ii), but say which clock a reader is looking at.
- House-style note, not a defect: Req 6.40, 6.41, 6.42, 6.43, 6.50, 6.54 each carry two
  SHALLs or two behaviours; consistent with existing criteria (cluster A review 1.16),
  and only 6.8 binds two actors (finding 1.10).

---

## 2. Faithfulness to the recorded decisions, and scope

**F5 (i) with the 2026-08-23 amendment (`critique:663-693`).** Encoded in Req 6.38,
6.39, 6.7, 6.11, and the 6.8 rewrite. The action-statement field list matches the
decision (treatment, statement, upstream issue, paths as text, expiry; timestamp of the
action from `decided_at`). The decision's "lint-vex-product gains affected requires
action_statement" is subsumed by 6.39 forbidding `affected` in source entirely, a
faithful strengthening. Deviations found: the missing replacement rule and statement
timestamp (finding 1.3), which the amendment's own timestamp decision requires.

**F5 (ii) with the amendment (`critique:695-737`).** Encoded in Req 6.42 to 6.45,
task 10.3; the consumer recipe moves to 10.7; permissions and the compensating controls
match the amendment word for word (`design.md:295-299`). Deviations found: the
"statement sets" comparison dropped from the criterion (1.4), the replace-scope wording
(1.5), and the amendment's Rekor sentence overstating the spike (1.5).

**F4 (i) with the A3 path amendment (`critique:739-761`).** Encoded in Req 6.49, 6.50,
6.51, 6.10, 6.11 and the aperture amendments to 2.6, 2.8, 6.1, 6.3. Extending the
aperture variable into the gate and rescan criteria is faithful (the aperture is defined
as "the severities that require a recorded decision", which is exactly what those
criteria scan for). The enforcement split (lint outer bound, gate tier, rescan daily)
lands as decided. Gap: nothing implements the reads (1.6); edge rules unspecified (1.8).

**F4 (ii) with the amendments (`critique:763-820`).** Encoded in Req 6.46 to 6.48 and
tasks 10.4/10.5. First seen as a signed value, the status issue in Renovate-dashboard
shape, JSON as artifact, native badges now and Pages later: all as decided, including
the badge rule "only the rescan and GitHub write a badge's number" surviving into
task 10.5. The computability defects (1.2) are inherited from the amended decision text
itself; the PR is faithful to a decision that does not compute, and the fix passes
through the critique first.

**F13 (i) with the amendment (`critique:1069-1102`).** Encoded in Req 6.52 to 6.54 and
task 10.6. Reading "gone" against the full enumeration rather than one tag per
definition is the amendment, verbatim. The 6.54 evidence-only rule is the decision's
"acts on derived state only, never on judgement". Deviations found: the report-shape
hole (1.1), the lifecycle consequences and label semantics (1.7).

**Section 6 (`critique:1105-1131`).** Numbering continues at 6.38 exactly as
instructed. The cluster B surface in the table is "Req 6 (...)"; the PR also edits
Req 2.6/2.8 and the Req 2 terms paragraph, justified by the aperture and declared in the
PR body, so no silent surface widening. One PR per cluster, critique amendments
committed before the spec commit, spike measured before drafting: the process the
repo's rules require is visibly followed.

**Scope against clusters C and D.** No criterion reaches into upstream trust or
catalogue posture. Task 10.3's mention of the cluster D consumer smoke test and the F13
amendment's register line are forward pointers, not content. The one real interaction
created now and left unstated is 1.7's (issue lifecycle versus tag retention). No
over-specification found beyond 6.47's "as a table and as a fenced JSON block", which
is the decided sink's shape and therefore deliberate.

---

## 3. Checked and found sound

- EARS validity: 121 valid, 0 invalid on the PR branch; 104 on `main`; the difference
  is exactly the 17 new criteria. Patterns fit their content (IF for 6.39/6.41
  unwanted-state handling, WHEN for the rescan events, ubiquitous for the invariants
  6.44/6.48/6.49/6.54); keywords uppercase; no should/must/will.
- Actors: every new criterion uses an existing actor; none invented. Numbering 6.38 to
  6.54 is contiguous, no collisions; cross-references (criteria 6.1, 2.13, 2.18, 2.21,
  2.24, the terms paragraph) resolve, with the two antecedent nits in 1.15.
- Coverage: every new criterion is annotated on exactly one task (6.7/6.10/6.11/6.49 to
  6.51 on 10.1; 6.8/6.35/6.37 to 6.41 on 10.2; 6.42 to 6.45 on 10.3; 6.46/6.47 on 10.4;
  6.48 on 10.5; 6.3/6.52 to 6.54 on 10.6; 6.8/7.1 on 10.7), and the Req 6 and Req 7
  coverage rows list 10.1 to 10.7 (`tasks.md:295-296`). The gap is the amended criteria
  (1.6), not the new ones.
- The `decided_at` outer-ceiling lint (Req 6.11) is computable without a scan: two dates
  and a declared duration. Day-one safety checked **[V][M]**: the twelve grafana entries'
  LOG decision dates (2026-08-04, 05, 07, 13; `triage/LOG.md:552`, `:766`, `:923`,
  `:959`) against expiries 2026-10-04/2026-11-02 all sit at or under 90 days (the
  2026-08-04 pair lands on exactly 90, and the current lint's strictly-greater
  comparison, `lint-accepted-risk.sh:161`, keeps that passing); all are HIGH
  (`triage/LOG.md:1063` "15 HIGH, 0 CRITICAL"; issue labels **[M]**) and not KEV-listed
  (issue #22's KEV cell "no" **[M]**), so the {CRITICAL: 30d, KEV: 14d} tiers bite no
  existing entry.
- The timestamp-semantics foundation holds where measured **[M]**: Trivy 0.72.0
  tolerates statement-level `last_updated`, `action_statement_timestamp` and
  `status_notes` without error; it orders competing statements by `timestamp` and
  ignores `last_updated`, so the one-statement-per-finding rule, once actually written
  into 6.38 (finding 1.3), gives deterministic consumer behaviour; `affected` and
  `under_investigation` never suppress (Req 6.35 amendment costs the gate nothing);
  vexctl merges documents carrying all three fields intact. go-vex requires an action
  statement on `affected` and 6.38 always supplies one **[R]**.
- ADR 0004's core measurements re-confirmed where cheap **[M]**: grafana's current
  release digest carries three `https://openvex.dev/ns` layers beside one SPDX, so the
  replace decision addresses a real, live state.
- The rescan flow's ordering (attest reports, then compile, then re-attest on change,
  then invariants, clocks, issues; `design.md:329-346`) makes Req 6.37's inputs complete
  before compilation, as Decision 7 claims; the error-table rows added
  (`design.md:784-788`) cite the right criteria.
- The permissions widening is honestly stated with its compensating controls
  (`design.md:295-299`), matches the critique amendment, and the re-attester role stays
  predicate-scoped in 9.6/10.3 (the stale Decision 6 sentence is 1.12's first bullet).
- Req 6.53's "covered by ... unexpired accepted-risk exception" is consistent with
  Req 6.9/6.35: coverage semantics are untouched, gate behaviour unchanged.
- `tasks/todo.md` is updated consistently with the critique's section 6 and names the
  independent review as the next step; the PR body's claims check out: the EARS numbers
  (121/0), the untouched surfaces (`git diff --stat`: nothing under `.github/`,
  `scripts/`, `policies/`, `triage/`), the three critique amendment commits, and the
  design-reviewed-before-drafting sequence visible in the commit order.

---

## 4. Tool runs

**EARS validator** (`ears-validator.js`): PR branch PASSED, 121 valid statements;
`main` 104. Difference 17 = Req 6.38 to 6.54, as the PR states.

**spec-validate** (procedure applied by hand against the PR worktree):

| Check | Result |
|---|---|
| EARS syntax, every criterion | PASSED (121/0) |
| Requirements structure: numbered titles, objectives, criteria | PASSED (8 requirements) |
| Task coverage: every requirement referenced by a `_Requirements:_` line | PASSED (Req 8.2 convention note pre-existing) |
| Design completeness: Overview, Architecture with Mermaid, Components, Data Models | PASSED |

The procedure checks syntax and presence; it does not see section 1.

**code-review skill** (`/code-review spec-cluster-b medium`): launched against the
branch target; the session's usage limit terminated its angle agents before any
consolidated report existed, and per the coordinator nothing further will arrive. One
interim coordinator note reached this session before the cut: that Req 6.46/6.52's
"attested scan report" phrasing is shape-dependent on `--show-suppressed`. That matches
finding 1.1, which was established here independently by measurement first; nothing else
from that run is folded in.

**Measurements** (script and output beside this file:
`review-pr100-independent.measure.sh` / `review-pr100-independent.measure.out`):
trivy 0.72.0 (DB snapshot 2026-08-22) and vexctl v0.4.4 against
`ghcr.io/mm-weber/dhc/hardened-app:0.1.0-alpine3.23` by digest, `--image-src remote`:
baseline 8, suppression/ordering runs d1 to d5, `--show-suppressed` representation and
its carry-through into `trivy convert --format cosign-vuln`; anonymous `ghcr.io` reads:
per-repository tag lists, distinct digest and platform-manifest counts (16/24), and the
`.att` layer census on grafana's release digest; anonymous `api.github.com` reads: the
13 open and 9 closed `cve` issues with labels, dates and issue #22's KEV/EPSS cells.
