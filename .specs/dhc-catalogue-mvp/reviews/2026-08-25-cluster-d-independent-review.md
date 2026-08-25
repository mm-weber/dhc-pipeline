# PR #103, cluster D spec amendment: independent adversarial review, 2026-08-25

**Subject:** branch `spec-cluster-d` at `57fad56` against `main` (merge base
`5574256`, clusters A to C and the greenfield decision merged): four files,
123 insertions, 2 deletions (`.specs/dhc-catalogue-mvp/requirements.md`,
`design.md`, `tasks.md`, `reviews/2026-08-21-production-readiness-critique.md`).
The PR encodes the cluster D decisions (critique F1, F11, F12 obligations, F7,
F13 register) as Req 9.1 to 9.17, Key Design Decision 10, four rescan-flow
invariant lines plus a retro-added 3.10 line, five error-table rows, task group
13, an intro sentence, and a dated amendment note under the F11 decision.

## Verdict

The skeleton is sound: the EARS validator passes all 155 statements, every 9.x
criterion has an implementing task and a design anchor, the coverage row is
correct, both operator actions are flagged as such, and the load-bearing
mechanics mostly measure true (the private-vulnerability-reporting endpoint and
repository security advisories answer anonymous reads, GitHub's ruleset export
format is importable and grype's OpenVEX matcher speaks the compiled documents'
purl dialect). The defects concentrate in two places. First, the amendment
writes a false measurement into the record: "bypass_actors is null on
main_sec" is a value the anonymous rulesets API never returns (the response
omits the field; GitHub's docs say it is returned only with write access), the
critique's own F1 and open-verification-items table said exactly that, and live
behavior refutes the null reading (PR #102 merged with zero approving reviews
under a one-approval rule, so a bypass actor exists); the same gap caps Req
9.9's promise to compare committed against live "through anonymous reads",
because the one field whose drift is the F1 story cannot be compared. Second,
Req 9.13's daily smoke test gates the run on suppressions landing in every
declared consumer, which is the divergence gating Decision 10's own Rejected
list disclaims and the design's failure-mode row mischaracterises, on
instructions that contain no consumer scan step and that no task updates.
Around those two sit under-delivered obligations (F12 a's licence text, F12 c's
README label, F13's LOG-anchor lint), a cost trade-off that understates Req
9.12 by the size of the enumeration, and revocation runbook mechanics GHCR
does not have. All are fixable by rewording, task additions and two prose
corrections before implementation starts.

**Verification legend**

| | |
|---|---|
| **[V]** | verified directly against the tree or git history, with `path:line` |
| **[M]** | measured 2026-08-25: anonymous GitHub REST API, docs.github.com, raw.githubusercontent.com (grype source, ruleset-recipes), ghcr.io token and tag lists, EARS validator (script and output beside this file: `.measure.sh` / `.measure.out`) |
| **[I]** | inferred, stated as such |
| **[U]** | not measurable from this environment |

---

## Findings

### 3.1 (High) **[M][V]** "bypass_actors is null on main_sec" is not a measurement an anonymous read can make, live behavior refutes it, and Req 9.9's committed-versus-live comparison cannot see the field at all

**Claim.** The F11 amendment note (critique:1172-1174, "Live state re-measured
2026-08-25 in the epoch review: `build gate` and `e2e gate` are required checks
and `bypass_actors` is null on `main_sec`") and Decision 10's context
(design.md:438, "both gates now required with bypass_actors null") state as a
measured fact something the anonymous API cannot report, contradicting the
critique's own F1 ("The bypass actor list is not exposed to anonymous reads and
stays [U]", critique:112-113) and its open-verification-items row
(critique:583: reading `bypass_actors` needs the admin view, result to be
dropped into `data/`; no such file exists in `data/`, verified). The same
omission bounds Req 9.9 (requirements.md:235): the committed export format
carries `bypass_actors`, the anonymous live read does not, so "compare each
committed ruleset against its live counterpart through anonymous reads and
report each difference" cannot cover the one field whose silent drift is F1's
attack surface.

**Evidence.** Measured (measure.out S2): anonymous
`GET /repos/mm-weber/dhc-pipeline/rulesets/20716271` returns top-level keys
`_links, conditions, created_at, enforcement, id, name, node_id, rules, source,
source_type, target, updated_at`; `bypass_actors` and `current_user_can_bypass`
are absent as keys, so a jq `.bypass_actors` prints `null` for present and
withheld alike (which is how the epoch review's S6 produced the claim).
Measured (S3): docs.github.com, Get a repository ruleset: "To prevent leaking
sensitive information, the bypass_actors property is only returned if the user
making the API request has write access to the ruleset." Measured (S7): a real
export in github/ruleset-recipes carries `bypass_actors` (with actor_id,
actor_type, bypass_mode), so the committed file per Req 9.8 will hold the
field. Behavioral refutation (S2, S4): the live `main_sec` pull_request rule
still has `required_approving_review_count: 1`, and PR #102 (author mm-weber)
merged 2026-08-25T15:20:58Z with zero APPROVED reviews; under an empty bypass
list that merge is impossible, so a bypass actor exists on the live ruleset
right now and is invisible to anonymous reads.

**Why it matters.** The record now contains a measurement that is wrong twice
over (unmeasurable as claimed, and false per observable behavior), in the
exact decision whose theme is honest bypass statements; and an implementer of
9.9 must either fail every daily run (the committed field never matches an
absent one) or silently skip `bypass_actors`, narrowing "each difference"
without any text saying so. A drift that adds a bypass actor, the cheapest way
to hollow out the committed governance, passes the daily invariant by design.

**Proposed fix.** (i) Correct both prose passages: design.md:438 and
critique:1172-1176 restate F1's truth (bypass actors are withheld from
anonymous reads and stay [U]; a bypass actor demonstrably exists because
merges land over the one-review rule; the honest-bypass sentence in
SECURITY.md already covers the posture). (ii) Scope the criterion to what the
mechanism can see and make the residue explicit. Replacement for 9.9:

> 9. THE Scan Pipeline SHALL compare at least once per day each committed ruleset's name, target, enforcement, conditions and rules against its live counterpart through anonymous reads, and SHALL report each difference, each committed ruleset lacking an active live counterpart and each active branch ruleset lacking a committed counterpart as a failure of that run.

(validated against the EARS checker, measure.out S1), plus one sentence in
Decision 10's trade-offs and in task 13.2 naming `bypass_actors` as outside
the compared set (anonymous reads withhold it; the SECURITY.md bypass
statement and the operator's admin view carry it, closing critique:583's open
item into `data/`).

### 3.2 (High) **[V]** Req 9.13 gates the daily run on suppressions landing in every declared consumer: the divergence gating Decision 10's Rejected list disclaims, with "expected suppression" defined nowhere, and the design's failure row describing a different criterion

**Claim.** Req 9.13 (requirements.md:239) reads "asserting each expected
suppression in each declared consumer, and SHALL report a failing assertion as
a failure of that run". Decision 10 rejects "gating on consumer divergence
(informational first, like govulncheck; a fork flips it)" (design.md:473-474),
and the new failure-mode row says the smoke test "fails the run on a broken
recipe" (design.md:981) while the portability block merely "names the
divergence". Those three texts describe three different criteria: a missing
suppression in grype is not a broken recipe, and failing the run on it is
divergence gating on that digest.

**Evidence.** requirements.md:239; design.md:473-474, :981; F7 decision:
"Informational first, like govulncheck; a fork flips it to gating"
(critique:1110-1111) beside "asserts the suppressions land"
(critique:1117), the same tension imported verbatim. No document defines
where the expectation set lives: not the criterion, not Decision 10
(design.md:455-458), not task 13.4 (tasks.md:351, "asserting each suppression
lands").

**Why it matters.** F7's whole premise is that matcher semantics diverge. If
Trivy suppresses a statement grype cannot match on the smoke-test digest, the
daily rescan goes permanently red with no fix available: the consumer cannot
be patched, and no artifact exists in which a known divergence could be
recorded as expected. The failure-mode table then tells the operator the red
run means a broken recipe, which it does not. This is the exact
permanent-red-cron failure the informational-first principle was adopted to
avoid.

**Proposed fix.** Pick one of the two readings and align all three texts.
Recommended: gate on the recipe and the authoritative consumer, report the
rest into the block. Replacement for 9.13 (validated, measure.out S1):

> 13. THE Scan Pipeline SHALL run at least once per day its published consumer verification instructions verbatim against one published digest, SHALL report a failed instruction step or a suppression missing in its authoritative consumer as a failure of that run, and SHALL report each remaining declared consumer's suppression result and each divergence in that run's portability block.

Alternatively, keep full gating: then delete "gating on consumer divergence"
from Decision 10's Rejected list, define the expectation source (the
authoritative scanner's suppression set on that digest, or a curated list in
the catalogue policy file where a known divergence is recorded), and rewrite
the failure row to say a divergence on the smoke digest fails the run.

### 3.3 (Medium) **[M][V]** Req 9.13's verbatim instructions contain no consumer scan step, no task adds one, and task 13.4's step list carries the vexctl merge that ADR 0003 retired

**Claim.** The artifact 9.13 runs "verbatim" is the published consumer
verification recipe. Measured today it contains no grype step and no vexctl
step (the only scanner mention is a `trivy image --vex` aside), and no task in
any group updates it to name the declared consumers: task 9.6 anchors its
identities (tasks.md:243), task 10.7 rewrites it to one verify-attestation per
predicate type (tasks.md:289), and 13.x touches SECURITY.md, README's
non-affiliation sentence and register citations only. Meanwhile task 13.4
specifies the smoke test as "(`cosign verify-attestation` against the role
identities, `vexctl merge`, `trivy --vex`, `grype --vex`)" (tasks.md:351),
copying the F7 decision text of 2026-08-21 (critique:1115-1117) from before
ADR 0003 decided exactly one OpenVEX attestation per digest.

**Evidence.** Measured (measure.out S11): no grype or vexctl occurrence inside
the manual's consumer sections (docs/user-manual.md:144-246) or README's
verify section (README.md:27-45); the four hits in the manual are
maintainer-side (tool pin table :450, VEX authoring :538, :541, scripts
reference :911). ADR 0003: "consumer recipe needs no merge step once one
document is the invariant" (docs/decisions/0003:142) and the explicit
instruction to decide the merge question in the manual, not here (:117-118).
Req 6.44 (requirements.md:177) makes one attestation the standing invariant.

**Why it matters.** As specified, 13.4 builds a smoke test that either does
not exercise the consumers (if it truly runs today's recipe verbatim) or does
not run the published instructions (if it adds steps the manual lacks),
forfeiting the "tested contract" point of the decision; and it re-introduces a
merge step the spec's own ADR retired, which a reader will implement.

**Proposed fix.** Add a bullet to task 13.4: `docs/user-manual.md` "Verify
what you pull" and README's verify section gain one scan step per declared
consumer (`trivy image --vex` and `grype --vex` against the extracted
predicate), rendered from the catalogue policy file's consumer list through
`scripts/render-verification.sh` (task 9.8, Req 7.8) so the instructions and
the list cannot drift; drop `vexctl merge` from the step list (ADR 0003:142);
note the recipe baseline is task 10.7's per-predicate-type form.

### 3.4 (Medium) **[V]** F13's fourth mechanism, the LOG-anchor lint, is delivered by no criterion and no task in any cluster, and cluster D is the last cluster

**Claim.** The F13 decision has four parts: the register, three automations,
and "*Mechanically linked*: `triage/LOG.md` stays prose; the lint validates
that every `ref:` in an exception and every LOG citation in a VEX statement
resolves to a real heading and that every decision has one"
(critique:1251-1254). The disposition ledger carries it ("LOG anchors
lint-linked", critique:1348). Clusters B and C took automations i to iii;
cluster D takes the register (Req 9.14, task 13.5) and closes F13. The
mechanical link lands nowhere: no 9.x criterion, no 13.x task, and grep
confirms no other task group carries it (measure.out S11: the only "anchor"
matches in tasks.md and requirements.md are identity anchoring and SBOM
canonicalisation).

**Evidence.** critique:1251-1254, :1348; tasks.md:353-355 (13.5 covers the
register only); requirements.md:140 (Req 6.7 requires the exception to carry a
reference to its reasoning in triage/LOG.md, nothing validates resolution;
the critique's F13 evidence item d names the hand-typed slug at
`triage/accepted-risk/grafana.yaml:27`).

**Why it matters.** The one mechanism binding 1,080 lines of hand-maintained
prose to the machine-read records is the piece F13 called out as accidental
toil waiting to rot; accepting the decision and shipping every part but the
lint silently reopens item d.

**Proposed fix.** Add a criterion under Req 9 (renumbering the rest or
appending as 9.18) and a task 13.6. Validated EARS text (measure.out S1):

> IF an accepted-risk exception's reasoning reference or a VEX source statement's log citation resolves to no heading in triage/LOG.md THEN THE CI Pipeline SHALL fail validation naming that reference.

Task: extend `lint-accepted-risk.sh` (the `ref:` half) and
`lint-vex-product.sh` or a sibling (the statement-citation half) plus the
"every decision has one" direction, unit-tested like the other lints. If the
owner instead re-decides to drop the mechanism, the F13 decision needs a dated
amendment note saying so; silence is the one option the amend-first rule does
not allow.

### 3.5 (Medium) **[V]** F12 obligation (a) is under-delivered: the memo requires shipping the Apache-2.0 licence text, Req 9.16 and task 13.1 only name it

**Claim.** Obligation (a) adopts Apache-2.0 §4(a)/(c) (critique:1206-1211).
§4(a) requires giving recipients "a copy of this License", and the memo's
Stage 2 instruction is explicit: "include the Apache-2.0 LICENSE text"
(data/dhi-terms-2026-08-21.md:61, :115). Req 9.16 (requirements.md:242) and
task 13.1's NOTICE bullet (tasks.md:335) deliver a notice file *naming*
"Copyright 2025 Docker Inc., Apache-2.0"; nothing commits or ships the licence
text itself, and the repository's LICENSE is MIT (LICENSE:1).

**Evidence.** requirements.md:242; tasks.md:335; data/dhi-terms-2026-08-21.md:61
(§4(a) quote), :115 (Stage 2 item 3), :12 ("ship the license text" in the
TL;DR); README.md:62-64 (MIT plus upstream-licence sentence, the state F12's
evidence measured).

**Why it matters.** F12 (f) unblocks the "production-ready" wording on (a)
landing (critique:1229-1230); as specified, (a) lands incompletely and the
claim would rest on a notice that does not satisfy the clause it cites. This
is the compliance surface the whole terms memo exists to close.

**Proposed fix.** Replacement for 9.16 (validated, measure.out S1):

> 16. THE Repository SHALL carry a notice file naming its hardening substrate's copyright and licence, SHALL carry a copy of its hardening substrate's licence text, and SHALL state beside them that third-party packages carry upstream licences enumerated in attested SBOMs.

Task 13.1: commit the Apache-2.0 text (for example `LICENSES/Apache-2.0.txt`
referenced from `NOTICE`), keep the in-image copy conditional on the frontend
measurement as already written.

### 3.6 (Medium) **[V]** F12 (c) is under-delivered and task 13.1's "last remaining occurrence" claim is false: the README still opens with the "-style" label and the attribution rewrite has no task

**Claim.** F12 (c) has README and CLAUDE.md drop "DHI-style" as a label
(critique:1216-1220), and the base F12 decision has README and the design
Overview state the substrate attribution ("hardening substrate by Docker
Hardened Images...; this catalogue contributes the operating model",
critique:1180-1184). Task 13.1 changes CLAUDE.md and calls it "the last
remaining occurrence" (tasks.md:336). Measured: README.md:3 opens with "A
miniature [Docker Hardened Images](...)-style" (the same label construct,
spelled out, in the document (c) names first), design.md:5 and
requirements.md:5 both carry "miniature DHI-style hardened-image catalogue",
and no task rewrites any of them or adds the attribution sentence; grep shows
no "substrate" statement in README.

**Evidence.** measure.out S11 (all occurrences listed); tasks.md:336;
critique:1180-1184, :1216-1220. Distinguish: requirements.md:38 (Req 1.8),
design.md:90 and ADR 0001:9 use "DHI-style YAML" as the name of the rejected
fallback format inside dated decisions, a different sense that may stand.

**Why it matters.** Same gate as 3.5: (f) keys "production-ready" on (c), and
the task's false factual claim means an implementer following it verbatim
ships the most visible label (README line 3) untouched while recording the
obligation as closed.

**Proposed fix.** Rewrite the 13.1 bullet: README.md:3 and CLAUDE.md:3 drop
the "-style" label for "built with Docker Hardened Images tooling and
packages"; the intro sentences of requirements.md:5 and design.md:5 follow in
the same pass (or a dated note records why spec intros keep the historical
phrase); the README and design-Overview attribution sentence from the F12
decision is added explicitly. No criterion change needed: 9.17 stays, the
label drop is (c)'s task-level obligation.

### 3.7 (Medium) **[M][V]** Req 9.12's portability block covers every digest the rescan scans, but Decision 10's trade-offs claim the added cost is one digest per day

**Claim.** Req 9.12 (requirements.md:238) requires, on every scheduled rescan,
each declared consumer's suppression result for each statement the
authoritative scanner suppressed, which means every declared consumer scans
every tag-referenced digest the rescan scans (and every PR-built image on PR
scans). Decision 10's trade-offs account only "the consumer smoke test doubles
scan cost on exactly one digest per day" (design.md:468) and say nothing about
9.12's multiplier.

**Evidence.** requirements.md:238; design.md:464-468; the criterion is
decision-true (F7: the block sits "in the PR and rescan summaries",
critique:1107-1110), so the trade-off text is the defective side. Scale
measured (measure.out S9): 35 catalogue tags across six repositories today,
multi-arch digests scanned per platform manifest (Req 2.18), so the daily
grype-with-VEX addition is on the order of the whole enumeration, not one
digest.

**Why it matters.** The trade-offs section is where the cost of a decision is
supposed to be owned; hiding the dominant term invites the discovery at
implementation time, which is the F13 pattern this cluster exists to end.

**Proposed fix.** Either own the cost: rewrite design.md:468 to "the
portability block runs every declared consumer over everything the
authoritative scanner scans, roughly multiplying scan time by the consumer
count, and the smoke test adds one digest on top". Or scope the criterion and
say so in Decision 10; validated narrower EARS (measure.out S1):

> 12. WHEN a pull request scan or a scheduled rescan completes THE Scan Pipeline SHALL report a VEX portability block naming, for each statement its authoritative scanner suppressed on that pull request's images or on a supported digest, each declared consumer's suppression result and each divergence.

(supported-set scoping, consistent with where issues and clocks already live).

### 3.8 (Medium) **[M][V]** "Remove that tag by hand" names no mechanic GHCR has, and Req 9.5's mandatory replacement digest blocks recording a withdrawal

**Claim.** The revocation runbook (task 13.3, tasks.md:345) and the F11
amendment ("a real revocation in the live repository removes a tag by hand",
critique:1169-1171) rest on a tag-removal primitive GHCR does not offer: the
packages API deletes packages and package versions only (a version is the
digest with its tags), so the two realizable moves are re-pointing the tag
(pushing another manifest under it, which the release path already does for
every replacement) or deleting the version, which deletes the digest,
contradicting frozen-digest semantics (Req 2.11) and Decision 9's "nothing is
deleted... consumers' digest pins never break", and which GitHub refuses for
a public package version past 5,000 downloads. Separately, Req 9.5
(requirements.md:231) makes every entry carry a replacement digest, so a pure
withdrawal (revoked, nothing to replace it) cannot be recorded without
violating the 9.6 schema.

**Evidence.** Measured (measure.out S10): the packages REST docs list delete
endpoints for packages and package versions only, zero tag-scoped deletion
endpoints; the epoch review's measured docs lines (its measure.out section 7)
carry the 5,000-download refusal. tasks.md:345; critique:1169-1171;
requirements.md:62 (Req 2.11), :231 (9.5); design.md:407-415 (Decision 9).
[I] that a re-pushed tag re-points rather than duplicates is standard OCI
registry behavior, inferred, not probed (probing means publishing).

**Why it matters.** The runbook is the artifact that must be right during an
incident; as written its first verb has no implementation, and the natural
fallback (delete the version) can be refused by GitHub mid-incident or can
destroy the digest the advisory needs to reference.

**Proposed fix.** 13.3's runbook bullet names the real moves: publish the
replacement through the release path (tags move to the replacement digest;
the revoked digest becomes untagged and frozen), and for a withdrawal with no
replacement either delete that package version (recording that its digest
leaves the frozen set, and noting the 5,000-download refusal risk) or park the
tag on a documented tombstone manifest; the choice is recorded in the entry.
For 9.5, validated EARS (measure.out S1):

> 5. THE Repository SHALL record every revoked digest in triage/revocations.yaml, each entry carrying digest, reason, replacement digest or a recorded absence of one, advisory link and date.

### 3.9 (Low) **[M][V]** Req 9.9's comparison is one-directional and its field set undefined: the retired `branch` ruleset can return unnoticed, and server-assigned fields make a naive diff fail always

**Claim.** 9.9 iterates over committed rulesets ("each committed ruleset
against its live counterpart"), so a live ruleset with no committed
counterpart is never a difference: after the operator retires the weaker
`branch` ruleset (task 13.2's [OPERATOR] item; F1 decision, critique:980,
"retires the overlapping weaker `branch` ruleset"), its resurrection or any
new live-only ruleset passes the invariant forever. And no text defines the
compared field set: the anonymous live read carries `_links`, `node_id`,
`created_at`, `updated_at` (absent from the export), the export carries `id`
and `source` (which change in the successor repository by construction,
Decision 9), so a byte-shaped comparison fails on day one and every
implementer must invent a canonicalisation the spec does not name (task
10.3's differs-test canonicalisation is the house pattern, unreferenced
here).

**Evidence.** requirements.md:235; tasks.md:340, :342 ("compared against the
live rules API": the rules API, `/rules/branches/main`, returns the merged
rules of all active rulesets without conditions, enforcement or name, a
different endpoint from the rulesets API the comparison needs; measured S2
against critique:96-97); measure.out S2 (live key inventory), S7 (export key
inventory: id and source present); design.md:407-410.

**Why it matters.** Rule layering means a live-only ruleset cannot weaken
`main_sec`, so this is hygiene rather than a hole, but the F1 decision made
retirement part of the mechanism and 9.9 as written cannot keep it retired;
and the undefined field set is a guaranteed day-one implementation surprise.

**Proposed fix.** The 9.9 replacement in finding 3.1 fixes both (named field
set; both directions). Task 13.2's "live rules API" becomes "live rulesets
API", and gains one sentence: the comparison canonicalises by ruleset name and
ignores server-assigned fields (id, source, node_id, _links, timestamps).

### 3.10 (Low) **[V]** "Its authoritative scanner" is used but never declared: no criterion marks a consumer authoritative

**Claim.** 9.12 and 9.13 pivot on "its authoritative scanner" and (in the
finding 3.2 rewrite) "its authoritative consumer", but 9.11
(requirements.md:237) declares only "a list" of consumers with an adapter
shape; nothing in Req 9 or the standing criteria requires the list to
designate the authoritative one. The divergence relation is undefined without
it.

**Evidence.** requirements.md:237-238; the designation lives only in prose:
F7 "The gate's scanner stays authoritative" (critique:1106-1107), design
"Trivy authoritative, Grype measured second" (design.md:453-454), task 13.4
"(trivy authoritative, grype second)" (tasks.md:349).

**Why it matters.** The policy file is the fork's switch surface; a fork
swapping the authoritative scanner (the framing addendum's declared seam,
critique:638-639) needs the marker to be data, not prose, and 9.12's "each
divergence" is untestable until the reference point is declared.

**Proposed fix.** Replacement for 9.11 (validated, measure.out S1):

> 11. THE Repository SHALL declare its VEX consumers as a list in its catalogue policy file, exactly one consumer marked authoritative, each consumer an adapter emitting findings in one normalised shape: vulnerability identifier, package url and suppression state.

### 3.11 (Low) **[V]** Req 9.6 names "that entry" for a file-level condition

**Claim.** 9.6 (requirements.md:232) conditions on "triage/revocations.yaml
violates its schema" and responds "naming that entry": no entry has been
introduced, and a file-level violation (top-level shape, duplicate keys) has
no entry to name. The design row states the entry-level reading
("revocations.yaml entry violates its schema", design.md:982), the criterion
the file-level one.

**Evidence.** requirements.md:232; design.md:982; contrast the house pattern
of entry-level antecedents in Req 6.11 (requirements.md:144).

**Why it matters.** Pure antecedent hygiene, but this cluster's own theme is
records driving mechanics; the lint's error contract should not depend on
which of two documents the implementer read.

**Proposed fix.** Validated EARS (measure.out S1):

> 6. IF triage/revocations.yaml violates its schema THEN THE CI Pipeline SHALL fail validation naming each violation.

(or condition on "an entry of triage/revocations.yaml" and keep "that entry";
either way the two documents then agree).

### 3.12 (Low) **[V]** Req 9.1's security policy list omits the disclosure and advisory pointers F11's claim opens with

**Claim.** F11's claim: a catalogue owes consumers "a way to report a problem
with the catalogue, a way to learn that a published digest is bad, and a
statement of what happens then" (critique:461-463). Req 9.1's eleven-item
content list (requirements.md:227) contains none of the three pointers: not
the reporting channel (9.2's private vulnerability reporting), not the
advisory channel (9.4's GHSA), not the revocation record's location. Task
13.3 patches the second by fiat ("GHSA named as the advisory channel in
SECURITY.md (Req 9.4)", tasks.md:346) against a criterion that says nothing
about SECURITY.md; the first has no home at all: a SECURITY.md that never
says where to report.

**Evidence.** requirements.md:227-231; tasks.md:346; critique:461-463,
:487-489 (the scale note's "contact, scope").

**Why it matters.** SECURITY.md's one conventional job is the reporting
pointer; every listed fact serves the trust decision, but the file would fail
its primary GitHub convention while satisfying 9.1 to the letter.

**Proposed fix.** Extend 9.1's list (the criterion stays a valid ubiquitous
pattern): after "its single-maintainer bypass posture;" insert "its
vulnerability reporting channel; its advisory channel; its revocation record
and runbook locations;". Task 13.1's item list gains the same three.

### 3.13 (Low) **[V]** Task 13.5 invents a third register class, "dated rows", against Req 9.14's two-class labelling

**Claim.** 9.14 (requirements.md:240) defines exactly two labels, "deliberate
or pending automation". Task 13.5 (tasks.md:354) lists "deliberate rows: ...;
dated rows: the cosign v2 pin ..., terms sources re-verified by 2026-11-21".
The F13 amendment classifies the cosign pin as a deliberate item
(critique:1265-1267) and F12 (e) the terms re-verification as "a deliberate
human item" (critique:1227-1228); "dated" is a property (carries a review
date), not a class, and an implementer following 13.5 builds a three-class
register that violates 9.14's labelling.

**Evidence.** requirements.md:240; tasks.md:354; critique:1227-1228,
:1265-1267.

**Why it matters.** The register is the F13 artifact; its first two rows
should not already need interpretation against the criterion that mandates
it.

**Proposed fix.** Reword 13.5: "deliberate rows carrying review dates: the
cosign v2 pin (ADR 0003) completed the way sha256 pins are; terms sources
re-verified by 2026-11-21 (F12 e)", keeping the class binary and the date a
column (or part of "reason").

### 3.14 (Low) **[V]** Truth-pass nits: the rescan-flow header omits the new invariants' requirements and tasks, and the trust-boundary table's location quietly diverges from the F12 decision

**Claim.** (i) The rescan-flow header still reads "(Req 2.18 to 2.24, 6.42 to
6.54; as specified 2026-08-23, implementation task 10)" (design.md:501) while
the flow body now carries 3.10, 9.3, 9.7, 9.9 and 9.13 (design.md:515-517),
implemented by tasks 11.3 and 13.2 to 13.4. (ii) The F12 decision puts the
trust-boundary table "in `docs/concepts.md` and `SECURITY.md`"
(critique:1184-1185); task 13.1 puts it in concepts.md "linked from
SECURITY.md" (tasks.md:337), a reasonable de-duplication that no dated note
records, against the house amend-first habit the F11 note itself demonstrates.
(iii) In the F11 amendment, "SECURITY.md additionally states the epoch, the
supported and superseded sets" (critique:1163-1164) overstates Req 9.1, which
asks for the *definitions* of those states (requirements.md:227), the only
maintainable reading since membership changes daily.

**Evidence.** design.md:501, :515-517; critique:1163-1164, :1184-1185;
tasks.md:337; requirements.md:227.

**Why it matters.** Each is small; together they are the difference between a
record a fresh reader can trust verbatim and one that needs oral tradition.

**Proposed fix.** (i) Header becomes "(Req 2.18 to 2.24, 3.10, 6.42 to 6.54,
9.3, 9.7, 9.9, 9.13; as specified 2026-08-23, amended 2026-08-25;
implementation tasks 10, 11.3, 13)". (ii) One sentence in the F11 amendment
note (or a dated line under F12): the table lives in concepts.md, SECURITY.md
links it. (iii) "the supported and superseded sets" becomes "the definitions
of the supported and superseded sets".

---

## Method

**Measured (network, anonymous; commands and raw output in the sibling
`.measure.sh` / `.measure.out`).** The rulesets API: list plus single-ruleset
field inventory (bypass_actors and current_user_can_bypass absent from the
anonymous response; pull_request parameters with
required_approving_review_count 1; both gates in required checks; both
rulesets still active). docs.github.com: the bypass_actors write-access note,
the without-authentication notes on the rules endpoints, the ruleset import
flow ("Open the exported JSON file"), the packages API's deletion endpoint
families (packages and versions only, no tag endpoint). Behavioral bypass
proof: PR #102 author, merged_at and review states (zero APPROVED). The
private-vulnerability-reporting endpoint (HTTP 200, enabled false, anonymous:
Req 9.3's mechanism works and the amendment's "stays to be enabled by hand"
is still true). Repository security advisories anonymously (HTTP 200, empty
for this repo; grafana/grafana control lists published GHSAs: Req 9.4's
channel is anonymously consumable). The ruleset export format via a real
export in github/ruleset-recipes (carries bypass_actors, id, source).
grype main-branch source: product identifiers built from RepoDigests as raw
reference, pkg:oci purl with repository_url qualifier and bare hex digest,
and filtering restricted to not_affected and fixed, matching Trivy's
semantics and the compiled documents' product shapes (supports 9.11 to 9.13's
premise). ghcr token plus tags/list per repository (35 catalogue tags, the
9.12 scale). The EARS validator over the amended requirements.md (PASSED, 155
valid statements, as expected) and over all eight proposed replacement
criteria (PASSED, 8 valid).

**Read (worktree).** The full diff (git diff main...spec-cluster-d);
requirements.md in full (Req 9 against Req 2.7 to 2.26, 6.35 to 6.60, 7.5 to
7.10); design Decisions 6 to 10, the release and rescan flows, the
failure-modes table; tasks groups 9 to 13 and the coverage table; critique
findings F1, F7, F11, F12, F13 with their 5.2 decision blocks and amendment
trails, the 5.1 framing and its 2026-08-25 addendum, sections 4 and 6, the
disposition ledger; data/dhi-terms-2026-08-21.md in full (obligations a to f
traced to criteria and tasks); docs/CONVENTIONS.md; docs/user-manual.md's
verification, branch-protection and runbook sections; ADR 0003 and ADR 0004;
.github/workflows/rescan.yml and validate.yml; the cluster C and greenfield
epoch independent reviews with their measure files (S6 of the latter is where
the bypass_actors misreading originates); README.md, CLAUDE.md, LICENSE.
Coverage was checked criterion by criterion: 9.1 to 9.17 each have an
implementing task (13.1 to 13.5) and a design anchor in Decision 10; the
coverage row is correct; both operator actions in 13.2 are bracketed as
[OPERATOR]; the artifacts promised without criteria (the F12 b modification
notice sentence, CLAUDE.md wording) ride named tasks.

**Not measurable here, and why.** The actual bypass_actors value: reading it
requires write access to the ruleset (docs note, S3); this review holds no
token by design, and the critique's open item (critique:583, admin-view JSON
into data/) remains undone, so the value stays [U] even as its non-emptiness
is proven behaviorally (S4). The GitHub UI's "Export ruleset" download for
this repository: requires an authenticated browser session; approximated by
the import docs plus a real export in github/ruleset-recipes (S7). End-to-end
grype --vex suppression against the catalogue's compiled attested documents:
needs scanner installs and image pulls, out of scope for a spec review;
verified at source level instead (S8). Whether GitHub would refuse deleting
any current package version over the 5,000-download bar: download counts need
authentication (per the epoch review); the restriction itself is documented
(its measure.out section 7). Tag re-pointing on ghcr (that a re-pushed tag
moves rather than duplicates): standard OCI behavior, marked [I], not probed
because probing means publishing to the live registry.
