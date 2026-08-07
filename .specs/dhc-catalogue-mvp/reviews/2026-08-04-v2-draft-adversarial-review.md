# Requirements v2 draft — adversarial review of the fix, 2026-08-04

**Subject:** `reviews/2026-08-04-dhc-requirements-v2_draft.md` — the untracked full rewrite
of `requirements.md` around a unified Triage Ledger + Ledger Compiler, written ten minutes
after review A was committed.

**This is not review B.** Review B — the owner's independent hand-written review of the v1
criteria — exists nowhere in the repository (searched all four worktrees, tracked and
untracked). This document reviews the *proposed fix*, on the questions: is it the right fix
for review A's findings; how does it hold against the software as built; how much would
change; can it be split.

**Method.** The three documents, `build.yml`, `tasks.md`, `triage/README.md`, `triage/LOG.md`
and `triage/vex/CVE-2026-42151.openvex.json` were read directly; the repo's EARS validator was
run against the draft. Two pairs of sub-agents were then dispatched with *identical* prompts —
two independently mapping every v2 criterion against the implementation, two independently
sweeping project state — and their reports cross-checked against each other and against the
first-hand reads. The two conformance maps agree on every finding; so do the two sweeps.
`design.md` was excluded, as in review A.

**Verification legend**

| | |
|---|---|
| **[V]** | verified directly against the repository or the draft text during this review |
| **[A²]** | reported identically by both independent mapping agents, citations spot-checked |

---

## 1. Verdict

**Right direction, wrong artifact.** The draft's core move — one decision record the gate can
see, compiled scanner inputs, supersession at decision level, a components table — targets
review A's root cause (finding 1.1: two lanes, two vocabularies, a gate blind to one) and
resolves it structurally. But the draft as written cannot be landed: it contains internal
contradictions of exactly the class review A punishes, its evidence model is unsatisfiable for
the one image that has findings, its treatment taxonomy cannot represent the repository's two
current live states, it silently drops safeguards the repo paid for in incidents, it leaves
review A's verified code-level findings open, and it preempts the two-review protocol it was
supposed to serve. Applying review A's own method to the draft fails the draft.

The decisive fact is in `triage/LOG.md` (2026-08-03, measured on `ccae635`): **all 18 HIGH
findings are symbol-level reachable**, so `not_affected` is foreclosed for every one of them —
under v1 6.14 and v2 6.16 alike — and the 1 CRITICAL (kin-openapi, #30) is GHSA-only,
invisible to govulncheck in any mode. Every one of the 19 pending decisions is therefore
accept / transfer / avoid: the lane whose validation (`scripts/lint-accepted-risk.sh`) and
gate mechanics (`--ignorefile`, silent expiry, 90-day ceiling) already exist and already work.
**The only thing blocking task 7.3 is the 6.1 coverage sentence. The draft's centerpiece
machinery — ledger compiler, dual-mode evidence — serves zero of the 19 pending decisions.**

## 2. What the draft gets right

Recorded first, so the critique below is read as aimed at the artifact, not the direction.

- **The unification itself.** Review A 1.1's deepest form was vocabulary: "covered" naming two
  different relations. One decision model the gate can read dissolves that class of defect
  rather than patching an instance. v2 6.11's coverage clause (VEX `not_affected`/`fixed` or
  unexpired accept/transfer; `affected`/`under_investigation` never count) is the correct
  semantics — it is what the shipped gate already does.
- **Supersession at decision level (6.3)** dissolves review A 2.4's paradox (6.20/6.22:
  supersession keyed on products that the versioning rules force to differ).
- **Generated artifacts (6.9's intent)** dissolve review A 2.3 structurally: if only the
  compiler writes VEX, a hand-authored `wontfix` document cannot exist to lint clean.
- **The components table** answers review A 3.9 (three undefined actors) in the right way.
- Several cheap, correct paper fixes that need no ledger: 4.2 (the hardened-app chart already
  exists and conforms — `chart/hardened-app/`, rendered and Kyverno-gated in `chart.yml`,
  in the e2e matrix), 2.4's Rekor exception (currently documented nowhere in the repo — the
  only hit for "transparency log" outside the draft is imported lab notes), 6.19's "new = no
  record" definition (review A 3.11), 6.20's Grype consumer (review A 2.5), 6.22's
  renewal-as-new-record discipline.

## 3. Resolution matrix — review A's findings against the draft

Review A's verified findings, and what the draft actually does to each.

| Review A | Status in v2 | Basis |
|---|---|---|
| 1.1 gate cannot see the accepted-risk lane | **Resolved** (6.11) | [V] |
| 1.2 govulncheck installed `@latest` against 7.5 | **Unaddressed** — `build.yml:477` unchanged; 6.14/6.15 *expand* the unpinned tool's role from evidence to validation input | [V] |
| 1.3 nothing scans the artifact that ships | **Unaddressed** — no criterion added; every scan step remains `if: pull_request` (`build.yml:192,218,239,469,526,543`); PR path amd64-only; arm64 hole intact | [V] |
| 1.4 6.15 admits only inconclusive evidence | **Partial** — source-mode-at-symbol-level fixes the package-level paradox, but the GHSA-only case (kin-openapi) still has no citable evidence class, and §4.5 below shows the cure is unsatisfiable where it is needed | [V] |
| 2.1 6.14 binds a justification string, not a claim | **Unaddressed** — v2 6.6 requires evidence only for `vulnerable_code_not_in_execute_path`; the other four OpenVEX justifications remain evidence-free; the tempo re-authoring loophole survives verbatim | [V] |
| 2.2 no consumer-facing artifact for accepted findings | **Silently decided** — accept/transfer stay internal (suppression set, never attested), siding with `triage/README.md` against review A's `affected`+`action_statement` rebuttal, without stating or arguing the decision | [V] |
| 2.3 no criterion requires a valid OpenVEX status | **Resolved structurally** (6.7/6.9), *if* the compiler exists; the `status` string itself remains unvalidated (LOG.md 2026-08-03 known gap) | [A²] |
| 2.4 `not_affected` outlives the version it was argued about | **Resolved in principle** (6.3 + per-build rendering) — but the rendering mechanism is the part that does not work as written (§4.1) | [V] |
| 2.5 Grype runs only on unexcused findings, result unconsumed | **Half-resolved** — 6.20 records confirmation on the issue and files Grype-only issues; the "WHERE a CRITICAL finding exists" ambiguity survives, and today's rescan renders `issues.json` *before* Grype runs (`rescan.yml:162-184`) | [A²] |
| 2.6 6.4's directory nothing uses; attestation unreachable on VEX-only PRs | **Half-resolved** — generated artifacts end the path confusion; the trigger mismatch survives (attestation and compilation fire on build success; no criterion makes a ledger-only PR build anything — see §4.8) | [A²] |
| 3.8 no state for "triaged, real, not treated yet" | **Unaddressed** — see §4.6; the draft's intro promises "queues them visibly" and no criterion delivers it | [V] |
| 3.9 undefined actors | **Resolved in form, violated in content** — see §4.4 | [V] |
| 3.14 no revalidation duty | **Unaddressed** — 6.16 fails records at re-validation time, but nothing re-runs validation absent a PR, and published attestations on old digests are never revisited | [A²] |

The draft's own "Revision notes (v1 → v2)" appendix maps fourteen findings to resolutions —
and several rows (Rekor metadata, bootstrap deadlock, hardened-app chart, stripped binaries)
correspond to **no finding in review A**. Those came from somewhere that has not been through
the adversarial process, and review A's verified blockers 1.2 and 1.3 have no row at all. The
fix document and the findings document do not describe the same list. **[V]**

## 4. Verified defects internal to the draft

### 4.1 **[V]** 6.7 and 6.9 cannot both hold, and "that build's digest" is three values

6.7 requires the compiled OpenVEX product to carry "that build's sha256 digest" — a value that
exists only after the build. 6.9 requires the compiled documents to be committed and to
byte-match a regeneration "from the ledger". A committed artifact cannot contain a digest that
does not exist until build time, and OpenVEX documents carry generation-time fields with no
ledger source: a content-hashed `@id`, `last_updated`, a monotonic `version`
(`triage/vex/CVE-2026-42151.openvex.json:3,5,47`).

Worse, the digest is not one value. The PR gate mints a **single-arch manifest digest** by
pushing to a throwaway `localhost:5000` registry (`build.yml:216-235` — the trivy#9399
workaround, commits `2dbd432`/`533c6ce`); the main path's `steps.build.outputs.digest` is the
**multi-arch index digest** of the ghcr push (`build.yml:173-174`, consumed by every cosign
step); per-arch manifests are a third set. The repo already documents that index ≠ manifest
bites in practice (`e2e.yml:116-117`: *"the charts pin the multi-arch INDEX digest … but a
loaded image carries a single-arch manifest digest, so containerd never matches"*). A document
stamped with the published digest is inert at PR time; one stamped with the PR digest is inert
against the published image. The gate's own rewrite makes it concrete: `build.yml:282` strips
only qualifiers (`split("?")[0]`) and **retains `@version`**, and the measured matching table
(`triage/LOG.md:382-394`) shows a digest-versioned purl suppresses only when the digest is the
scanned artifact's own. The daily rescan, meanwhile, scans a floating major tag
(`rescan.yml:68-76`), matching neither.

At most two of the three criteria can hold: ephemeral per-build documents (vacating 6.9 — the
attested predicate becomes unreviewable in git), or committed digestless documents — which is
what the repo does today, and what `scripts/lint-vex-product.sh:119-126` enforces *because the
alternative's failure mode was measured* ("a pinned product suppresses until the next rebuild
and then silently stops matching").

### 4.2 **[V]** 6.8 is unimplementable, four ways

6.8 wants a `fixed` product to carry "the digest of the first build in which the finding is
absent."

1. That is **build/scan history**, which the 6.1 record schema has no field for and nothing
   persists — scan output is a workflow artifact, not a commit; the PR digest is "dropped with
   the runner" (`build.yml:214-215`).
2. "Absent" is not a property of a digest; it is a property of (digest, scanner version,
   advisory-DB date). `install-scanners.sh` pins Trivy 0.72.0 while `docs/CONVENTIONS.md`
   states the DB "still updates on every run."
3. The repo has already failed to answer this exact question: `triage/LOG.md:327-335` — *"There
   is no CI scan of grafana at 13.0.4 to diff against: the scan gate landed 2026-07-22, after
   that image was built."* The one real `fixed` was established from upstream `go.mod` diffs
   plus a single scan, not from build history.
4. It reverses a convention that was measured and argued in writing: a `fixed` product names
   the published **tag** — *"every build of 13.1.1 carries the fix, so a digest would be wrong
   by being narrower than the claim"* (`triage/LOG.md:521-524`, `triage/README.md:195-198`,
   shipped in `CVE-2026-42151.openvex.json:33`). The draft overrules this without mentioning it.

### 4.3 **[V]** 6.4 forbids what 6.10 requires, and would have failed the repo's history

6.4 fails any PR that "modifies or deletes an existing ledger record." 6.10 requires records
"marked as retired" — a marking is a modification, and the draft names no other mechanism.
6.4 as stated would also have failed both decision-changing commits in the current history:
`e2a2393` (modified the CVE-2026-42151 document to append the `fixed` statement) and `ccae635`
(deleted the tempo document — the retraction `triage/LOG.md:446-450` describes as the system
*working*: "Fixing the plumbing is what made it falsifiable, and the first thing it did was
falsify it"). An append-only regime needs tombstone/marker *records* and a stated distinction
between records and generated artifacts; the draft has neither.

### 4.4 **[V]** The actor table commits the defect it was written to fix

The components table defines the Scan Pipeline as "Scheduled (daily) rescans, second-opinion
scans, issue creation, expiry reporting" — and then 6.15 hands it PR-time govulncheck and 6.20
second opinions "WHERE a CRITICAL finding exists," which includes PR time. That is review A
3.9's exact finding against v1 6.13, reproduced in the document that cites 3.9 as resolved.
The new **Ledger Compiler** appears in the components table and in no criterion of
Requirement 8 — the one requirement that says where things run.

### 4.5 **[V]** The evidence model is calibrated to the archetype that has no findings

6.14(a) requires source-mode govulncheck "at the pinned upstream ref, run with the build flags
and tags recorded in the definition (1.9)."

- **grafana cannot satisfy it, structurally.** It is the tarball-repackage archetype
  (`image/grafana/image.yaml:50-51`: "fetch the official prebuilt release … no compilation").
  There is **no pinned git ref anywhere** — `renovate.json5` and ADR 0002 document that grafana
  has no `git+…#ref` shape at all — no build flags, and no single build to reproduce: the
  bundled plugin binaries were compiled by upstream at different times (Grype observed three
  grpc versions in one image, `triage/LOG.md`). 1.9's trigger ("WHERE a definition builds Go
  binaries") correctly never fires for grafana, which makes 6.14(a)'s cross-reference
  unsatisfiable rather than merely unmet. grafana holds **100% of the open findings and 100% of
  the `not_affected` history** — including the flagship CVE-2026-42151 statement, which could
  not be re-recorded under the draft's own validation.
- **Our own from-source images are doubtful.** All four build with `-w -s`
  (`image/hardened-app/image.yaml:63-64` and the three cert-manager definitions), and
  `triage/LOG.md:348-350` already warns stripping "may degrade govulncheck to module-level
  precision" — which 6.16 then classifies as unmeasured and turns into a CI failure for any
  record citing it. 1.9 as drafted also collides with the existing schema: no build *tags* are
  recorded anywhere, and the key `tags:` is already taken by the release-tag list.
- **The only CRITICAL is permanently unmeasurable.** kin-openapi (#30) is GHSA-only, absent
  from the Go vulnerability database (`triage/LOG.md:462-466`); no mode of govulncheck will
  ever produce the citation 6.14 demands.
- **6.16 re-genres a lane on purpose kept non-gating.** `build.yml:463-466`: *"continue-on-error
  is the declaration that this is EVIDENCE, NOT A GATE … A reachability tool that can also
  break CI is a second gate nobody designed."* 6.16 makes CI validation depend on govulncheck
  output — the second gate, through a different door, built on the tool 1.2 says is installed
  unpinned.

### 4.6 **[V]** The taxonomy cannot record the repository's two live states

6.2 admits exactly five treatments. The repository currently holds two decision states that
fit none of them: **under investigation** (kin-openapi #30 — "the one finding where the honest
answer is 'we do not know yet'", `triage/LOG.md:131-147`) and **retracted, no treatment, gate
red** (tempo #27, `triage/LOG.md:418-450`). v2 6.11 rightly excludes `under_investigation`
from coverage — and provides no way to *record* it. The intro's promise that the system
"queues them visibly rather than making them" has no criterion behind it. Review A 3.8 — no
state for "triaged, real, not treated yet", *"the repo is in this state right now"* — survives
the rewrite untouched.

### 4.7 **[V]** Subcomponent scoping silently leaves the data model

The 6.1 record schema (id, image, vulnerability, treatment, timestamp, owner, rationale)
carries no package/subcomponent field. Today a product with zero subcomponents **fails CI**
(`scripts/lint-vex-product.sh:79`: "that excuses this CVE everywhere in the image rather than
in the package actually analysed"), and versionless subcomponent purls are a documented,
Trivy-verified convention (`triage/README.md:199-201`). The draft's appendix claims per-digest
rendering resolves "versionless product + subcomponent = eternal blanket suppression" — but
per-digest rendering narrows the *product* axis while the schema deletes the *package* axis.
On a repackage image where the same module appears in three binaries with three different
exposures (`build.yml`'s own "Still uncovered" table carries the per-binary Target for exactly
this reason), that is a net loss of precision the appendix presents as a gain.

### 4.8 **[A²]** Safeguards dropped without a stated successor

- **The registry-host check.** `scripts/lint-vex-product.sh` implements v1 6.17–6.21 and is
  orphaned wholesale; its header records that after the gate's qualifier-stripping it is "the
  only check left" on `repository_url`, and that "this repo lost a full day to exactly that."
- **The VEX-washing prohibition as a stated rule.** v1 6.8 — "an exception is never a VEX
  statement" — appears in `triage/README.md`, `triage/accepted-risk/README.md:14`,
  `docs/CONVENTIONS.md:171-176` and commit `7f2708d`'s harm statement. v2 deletes the criterion;
  the property survives only as an emergent behavior of a compiler that does not exist yet.
  Nothing in v2 *forbids* compiling an `accept` into a VEX statement.
- **`triage/LOG.md` loses normative status.** v1 6.7 requires `ref:` into it; v1 6.15 cites
  evidence in it. v2 mentions LOG.md nowhere — 550 lines of retractions, measurements and
  method notes, the project's actual audit trail, with no requirement asserting it exists.
  The `ref` and `statement` fields (required today, `scripts/lint-accepted-risk.sh:51`) have
  no v2 counterpart; `statement` is the text Trivy renders in the gate's suppressed-findings
  table.
- **transfer-requires-issue is loosened.** Today `transfer` without an `issue` fails
  (`lint-accepted-risk.sh:123-126` — "the tracker it waits on is what makes it one"); v2 6.5
  asks only for "a reference to the upstream report or advisory."
- **A ledger-only PR builds nothing.** The changes-detection derives rebuild targets from
  `triage/vex/*.json` product purls and `accepted-risk/` filenames (`build.yml:72-86`); both
  paths vanish, and no v2 criterion preserves the property `triage/README.md:214-217` states:
  "a PR touching `vex/` builds and rescans exactly the images its statements name, which is
  how a statement is proved to suppress what it claims."
- **The two-lane job summary** (`build.yml:314-366`) — built so "a suppression whose reason is
  'we decided to live with it' must never read as 'it does not apply'" — keys on source paths
  that cease to exist; no v2 criterion preserves the reporting distinction.
- **6.21 reverses a reasoned design silently.** The rescan soft-fails by decision
  (`rescan.yml:14-15`, exit status discarded at `:112`) so "a transient outage never turns the
  cron permanently red"; 6.21 mandates the run fail while any expired record lacks
  supersession. Possibly the right change — but it is a reversal of recorded reasoning, made
  without acknowledging it.
- **6.12's evaluation point moves.** Today expiry is enforced by Trivy at scan time (verified,
  silent — `lint-accepted-risk.sh:6-8`); a compiled suppression set fixes "unexpired" at
  compile time, opening a staleness window between compile and scan that no criterion covers.

### 4.9 **[V]** The draft fails the repo's own tooling and breaks every existing citation

`node .claude/skills/ears-notation/scripts/ears-validator.js` on the draft: **"No acceptance
criteria found"** — the draft's `### Acceptance Criteria` headings and `6.1 THE …` paragraph
numbering are not the format the validator (and the spec workflow) parses. The current
`requirements.md` passes with 63 valid statements. Nobody ran the spec tooling against the
draft. Independently: the renumbering (6.4→6.23-style moves across all of Req 6) breaks every
citation in `tasks.md`, `docs/CONVENTIONS.md` (§"Scanning & triage" cites 6.2/6.3/6.5/6.8 —
`:44-45` cites Req 6.5 by number), `triage/README.md`, LOG.md, closed PRs #25/#27/#37, and
review A itself, with no v1→v2 crosswalk. For a project whose stated objective is that
decisions be auditable, renumbering without a concordance damages the audit trail. Smaller but
of the same kind: 6.17's bootstrap is counterfactual (the catalogue is initialized; the gate
landed 2026-07-22, after the images; 19 findings are untreated *now* — the state 6.17 asserts
has never held); 3.6's "one release behind" no longer holds (grafana 13.1.1 and cert-manager
v1.21.0 are both latest); 5.2's naming of valkey converts open task 8.1 (no valkey chart, no
SET/GET probe) from deferred work into a standing violation.

### 4.10 **[A²]** Migration is unspecified, and it is the risky step

In-tree machine-readable decisions: **one document, two statements, zero accepted-risk
entries.** Plus roughly six LOG-only decision classes (grpc "affected, accepted for now"
across three images; three stdlib remediations; kin-openapi and tempo — the two
unrepresentable states; four untreated x/net findings; the 19 owed records). Conversion
breaks five ways: no per-record owner exists in VEX (`author` is document-level); LOG-only
timestamps are date-granular, making 6.3's latest-timestamp supersession undecidable for
same-day decisions; the one supersession chain deliberately names *different products* — a
distinction the (image, vulnerability) key collapses; subcomponent scope has nowhere to land
(§4.7); and the flagship `not_affected` record fails v2's own 6.6+6.14 validation on arrival
(§4.5). The draft contains no migration or grandfathering requirement at all. The v1→v2
transition — the step where an auditable history is most easily destroyed — is the one thing
the draft does not specify.

## 5. Against the implementation, in numbers

From the two independent conformance maps (full agreement): of the draft's Requirement 6 plus
its deltas elsewhere, **~8 criteria already conform in substance** (6.5 — the accepted-risk
lint's rules transfer intact; 6.12; 6.18; 6.23; 7.6; 8.1; 4.2; most of 2.2; 6.11 in outline —
the shipped gate already composes both lanes and fails on survivors), **~9 conflict with
enforced rules or measured conventions** (6.2, 6.3, 6.19, 6.20, 6.21, 7.1, 5.2, 1.9, 3.6),
**~10 require new construction** (ledger, schema — none exists in the repo today, compiler
plus tests, append-only checker needing `fetch-depth: 0`, reproducibility checker, source-mode
runner, Grype differ, renewal-issue opener, Rekor documentation, valkey chart), and **4 are
unimplementable as written** (6.7+6.9 jointly, 6.8, 6.14-for-grafana, 6.17).

Blast radius: ~12 file creations; ~15–20 modifications (the cores of `build.yml` and
`rescan.yml` — change detection, VEX assembly, summary, gate message, attestation loop;
`validate.yml`; the three lint scripts; four to six `image.yaml`s; `docs/CONVENTIONS.md`;
both triage READMEs; the PR template; `tasks.md`); ~5 deletions including both lint script
pairs (~1,100 lines of tests) and the only committed VEX document. A multi-day rebuild of the
repository's most tested and best-reasoned lane, before a single treatment lands.

## 6. Process

Review A's protocol was explicit: the owner writes review B by hand; the two reviews are
deliberately not reconciled before both exist; "where review B disagrees, the disagreement is
the finding." The draft — a full rewrite, not a review — was produced before B exists,
answers a findings list that partly matches neither review, and decides at least one
contested question (review A 2.2, the consumer-facing answer for accepted findings) silently.
Writing the fix before the second review inverts the design: review B, if written now, reviews
v1 while the author's intent has already moved to v2. The protocol's value — two independent
looks at the same normative text — is spent the moment the fix is drafted against private
findings. That is a process defect of the endeavour, independent of every technical finding
above.

## 7. Decision and path (owner, 2026-08-04)

The owner chose: **minimal fix now, ledger later.** Sequenced as one decision per change:

1. **Coverage-semantics amendment** (same commit series as this review): rewrite v1 6.1 to
   state the coverage the shipped gate already implements — a HIGH/CRITICAL is covered by a
   VEX statement recording status `not_affected` or `fixed`, or by an unexpired exception
   under `triage/accepted-risk/`; 6.9 rephrased so "names" (the exception's list) and
   "covered" (the gate relation) stop being the same word. Zero behavior change; resolves
   review A 1.1; **unblocks task 7.3** in the existing, working format. The 19 treatment
   decisions remain the owner's, one finding at a time.
2. **Queued, each its own PR:** pin govulncheck per 7.5 (review A 1.2; the sweep found
   kyverno/helm/ct/kind installs pinned-but-unchecksummed too); a scan-what-ships criterion +
   main-path scan of both arch manifests before sign/attest (review A 1.3); the Grype-consumer
   fix; the expiry-fail-vs-soft-fail decision; status-vocabulary validation (2.3); the
   justification-evidence rule (2.1); an explicit decision memo on 2.2 either way.
3. **The ledger (v2), only after review B exists and A+B are reconciled.** If adopted then,
   the draft needs before landing: 6.9 split into committed-deterministic (suppression set,
   digest-free) versus rendered-at-release (VEX with digest, attested not committed); 6.8
   re-based on tags; retirement via tombstone records compatible with 6.4; a recorded
   parked/under-investigation state; a subcomponent field; the VEX-washing prohibition,
   transfer-requires-issue and LOG.md's role restated; migration and grandfathering
   requirements; the actor table fixed and the compiler assigned in 8.1; the EARS format the
   validator parses; a v1→v2 criterion crosswalk. Implementation, if it comes, in compatible
   stages: compiler emits the *current* formats first, then the gate input flips, then
   attestation, then the hand-authored files retire — every stage green.

The v2 draft stays uncommitted, as a design input to that future decision.

## 8. Limits of this review

- The conformance classifications in §5 rest on the two mapping agents' file:line citations;
  the load-bearing ones were re-verified by hand, the long tail was not.
- GitHub state (issues, CI runs) was unreachable from this container (`gh` unauthenticated);
  `triage/LOG.md` and review A were treated as ground truth for the red gate and the finding
  counts.
- This review inherits review A's scope bias: Requirements 1–5, 7, 8 were examined only where
  the draft changes them.
- The judgment that the ledger should wait is the owner's decision, recorded here with its
  grounds; the technical findings above stand independently of it.
