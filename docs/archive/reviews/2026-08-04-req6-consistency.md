# Requirement 6 — consistency review, 2026-08-04

**Scope:** acceptance criteria 6.1 – 6.22 of `.specs/dhc-catalogue-mvp/requirements.md`.

**Why now.** Task 7.3 is about to write treatments for 19 uncovered findings on
grafana. Every remaining treatment is `accept` or `transfer`, so the criteria
governing that lane are load-bearing for the next commit rather than
theoretical. Reviewing them first was the owner's call.

**Method.** A `spec-requirements` agent (Opus) reviewed the criteria
adversarially, then the findings that would change what we do next were
re-checked against the repository by hand. This is **review A**; the owner is
writing an independent **review B** by hand. The two are deliberately not
reconciled before both exist.

**`design.md` was excluded from this review, on purpose.** It is the author's own
justification of these criteria — the defence brief, not the contract. A
criterion that reads as coherent only once you know the rationale is exactly the
defect a review should surface, so admitting design.md would have hidden the
problem. `requirements.md` was treated as the sole normative text and the
criteria judged on what they literally say.

`triage/README.md`, `triage/accepted-risk/README.md` and the enforcing scripts
were consulted **only** to test enforceability. Where they disagree with the
requirements text, that disagreement is recorded as a finding rather than used to
repair a criterion.

**Diagnosis only.** No fixes are proposed here. Section 4 states what is blocked,
because that is a fact about sequencing rather than a proposed remedy.

**Verification legend**

| | |
|---|---|
| **[V]** | re-checked directly against the repository or the requirements text during this review |
| **[R]** | reported by the review agent, plausible, **not** independently verified |

---

## 1. Verified findings that block work in progress

### 1.1 **[V]** `6.1` cannot recognise the accepted-risk lane — `6.1` vs `6.7`–`6.11`

> 6.1 — *WHEN a pull request builds an image THE Scan Gate SHALL run Trivy and
> fail on HIGH or CRITICAL findings **not covered by a VEX statement**.*

6.8 forbids recording accepted risk or upstream transfer as a VEX statement. So a
finding treated under 6.7 is, by construction, not covered by a VEX statement,
and 6.1 requires the gate to fail on it regardless. Five criteria (6.7–6.11)
describe a lane that 6.1's only stated pass condition cannot see.

6.9 is the tell: it says an **expired** exception's findings count as uncovered,
which is only meaningful if an unexpired one counted as covered — a rule stated
nowhere. That missing converse is precisely what 6.1 lacks.

"Covered" also names two different things: excused by a VEX statement (6.1)
versus named by an exception (6.9, *"every finding it covers"*).

**Where it bites.** The next commit in task 7.3 writes
`triage/accepted-risk/grafana.yaml`. `build.yml` passes it as `--ignorefile`,
Trivy suppresses, the counters return zero and the gate goes green — while 6.1
as written says the pull request SHALL fail. The shipped gate is either
non-conformant with 6.1, or 6.7–6.11 are a dead letter. The text supports both
readings.

**Blocks:** every remaining treatment in task 7.3.

### 1.2 **[V]** `6.13`'s tool is installed unpinned, against `7.5`

`.github/workflows/build.yml:477` runs:

```
go install golang.org/x/vuln/cmd/govulncheck@latest
```

Req 7.5 requires that a workflow installing a third-party executable pin it to an
exact version and verify it against a checksum recorded in this repository.
`build.yml:201` in the same job runs `scripts/install-scanners.sh`, which does
exactly that for trivy and grype — added in task 1.3, three days earlier, after
CVE-2026-33634 repointed 76 of 77 `aquasecurity/trivy-action` tags at a
credential stealer.

Two scanners pinned and a third installed floating, in the same job, on a runner
holding registry tokens and cosign signing permissions.

Either 7.5 is violated on every PR run, or 6.13's tool is exempt and no criterion
says so.

### 1.3 **[V]** Nothing scans the artifact that ships — `6.1`, `6.2`, and Req 2

Every scan step in `build.yml` carries `if: github.event_name == 'pull_request'`
(lines 192, 218, 239, 469, 526, 543). Line 173 selects platforms:

```
platforms: ${{ github.ref == 'refs/heads/main' && 'linux/amd64,linux/arm64' || 'linux/amd64' }}
```

So the PR path scans amd64 only, and the main path — which builds both arches,
pushes, signs, attaches an SBOM and attests — scans nothing at all. 6.1 triggers
only *"WHEN a pull request builds an image"*. Req 6 has no criterion requiring
the released artifact to be scanned before it is published.

**Where it bites.** `image/grafana/image.yaml:33` pins **different bytes per
arch** (amd64 `e4744321…`, arm64 `28ef74a3…`). A HIGH present only in the arm64
tarball passes the amd64-only PR gate and is then signed, SBOM'd and attested,
having been scanned by nothing.

The only fallback is 6.2's daily rescan of *"published images"*, which collides
with Req 2.4 (*"WHILE public release remains disabled THE Repository SHALL keep
source and registry images private"*): on a literal reading nothing is published
and 6.2 is vacuously satisfied.

### 1.4 **[V]** `6.15` admits only inconclusive evidence — `6.14` / `6.15` / `6.16`

- 6.15 requires citing *"a govulncheck result for that binary at **symbol or
  package** level"* to support `vulnerable_code_not_in_execute_path`.
- 6.14 **forbids** that justification when the result is `symbol`.
- 6.16 **excludes** `module` as unmeasured.

That leaves `package` — the level govulncheck emits when it *cannot resolve* the
call. The only citable evidence for the claim is evidence that decides nothing.

The evidence that would actually support the claim — govulncheck reporting
nothing for that binary, or the advisory being absent from the Go vulnerability
database — is not a citable class under 6.15 at all.

**Where it bites.** GHSA-r277-6w6q-xmqw (kin-openapi, CRITICAL, #30). `LOG.md`
2026-07-30 records zero mentions of kin-openapi across all 37 govulncheck
findings: the advisory is GHSA-only. Even a reviewer who proves the vulnerable
handler is never wired cannot author the statement, because there is no
govulncheck result at any level to cite.

---

## 2. Verified findings bearing on the two open decisions

### 2.1 **[V]** `6.14` binds a justification string, not a claim

6.14 forbids exactly one justification — `vulnerable_code_not_in_execute_path` —
when a symbol is reachable. OpenVEX offers `component_not_present`,
`vulnerable_code_not_present`, `vulnerable_code_cannot_be_controlled_by_adversary`
and `inline_mitigations_already_exist`, and no criterion in Req 6 constrains any
of them or demands evidence for them.

The strongest measurement the pipeline can make forecloses one string.

**Where it bites.** CVE-2026-28377 (tempo) was retracted on 2026-07-30 because
govulncheck measured the symbol reachable. Re-authoring the same claim as
`vulnerable_code_cannot_be_controlled_by_adversary` passes 6.14, 6.15,
`lint-vex-product.sh` (which checks purl shape only) and the gate. The
retraction was voluntary; the criteria forbade only the wording that happened to
be used.

This matters for an idea raised in discussion on 2026-08-04 — that the tempo
findings might be defensible as *code runs, adversary cannot drive it*, since
govulncheck names `tempo/pkg/tempopb` (protobuf types) rather than Tempo's server
packages. That argument may be sound. **It cannot be made while 6.14 is this
narrow without being indistinguishable from using the loophole.** The test is
whether the evidence changed, not whether the wording did.

### 2.2 **[V]** `6.8` forbids the format's own answer to "what must the consumer do"

6.8 bans recording accepted risk or transfer *as a VEX statement*. OpenVEX
`affected` **requires** an `action_statement` — the format's designed expression
of "this applies to you, here is the compensating control." `affected` suppresses
nothing in any scanner.

Tested against 6.8's own recorded harm (commit `7f2708d`, PR #37): *"laundering a
business decision into a machine-readable claim of technical inapplicability that
every downstream consumer inherits."* An `affected` statement is not false, is
not inherited as an excuse, and does not suppress. None of the three harms apply.

The model was built around two questions and there are three:

| Question | Artifact today |
|---|---|
| Does this apply? | VEX `not_affected` / `fixed` |
| What are **we** doing about it? | `triage/accepted-risk/`, internal, expires |
| What must the **consumer** do about it? | **nothing** |

`triage/accepted-risk/` is never attested, so a consumer pulling a published
image learns nothing about any finding we accepted.

### 2.3 **[V]** No criterion requires a valid OpenVEX status

Req 6 constrains statuses only by reference — 6.20/6.21 split on `fixed`,
6.14/6.15 name `not_affected`. Nothing requires a `status` field to be present,
requires it to be one of OpenVEX's four labels, or requires an `action_statement`
on `affected`.

`"status": "wontfix"` with a versionless product passes 6.17–6.21 and
`lint-vex-product.sh` clean, while suppressing nothing with any consumer — a
statement that looks like a decision and is inert. Recorded as a known gap in
`LOG.md` 2026-08-03 and in commit `8ce4f48`; no criterion closes it.

### 2.4 **[V]** `not_affected` outlives the version it was argued about — `6.20` + `6.22`

6.20 forces every non-`fixed` product **versionless**; 6.21 forces every `fixed`
product **versioned**. OpenVEX supersession keys on (vulnerability, **product**),
so the superseding statement necessarily names a *different* product and
supersedes nothing. The earlier claim remains the latest statement for its own
product, permanently.

**Where it bites.** `triage/vex/CVE-2026-42151.openvex.json` as committed today
(`e2a2393`):

- statement 1 — `not_affected`, `pkg:oci/grafana?repository_url=…` (versionless)
- statement 2 — `fixed`, `pkg:oci/grafana@13.1.1-alpine3.23?repository_url=…`

A consumer scanning the still-pullable `13.0.4-alpine3.23` matches statement 1
and suppresses CVE-2026-42151 on an image that genuinely carries
`prometheus/prometheus` v0.305.3.

The deeper problem is the justification for versionless products. It was written
as *"survives rebuilds"* — but it also survives **version changes**, which is a
much stronger claim. A structural argument about 13.0.4's code is not
automatically true of 14.0's code, and the statement will suppress there too.
`triage/README.md` asserts *"consumers take the latest per (vulnerability,
product), so nothing is lost"* in the same paragraph that prescribes two
different products.

### 2.5 **[V]** `6.6` — Grype runs only on findings nobody excused

`build.yml:526` gates the second opinion on
`github.event_name == 'pull_request' && steps.trivy.outputs.crit != '0'`, i.e.
only on CRITICALs that survive suppression. 6.6's condition is unqualified
(*"WHERE a CRITICAL finding exists"*), and a suppressed CRITICAL still exists.
6.6 also requires only that a second opinion be *obtained* — no criterion says
what its result changes, so the obligation is discharged by running the tool and
ignoring the output.

The moment #30 is excused, `crit` becomes 0, Grype stops running, and the finding
we chose to live with is the one nothing double-checks.

### 2.6 **[V]** `6.4` names a directory nothing uses, and a duty unreachable on its own path

6.4 requires recording the statement *"under **triage/**"*. Every enforcer and
consumer globs `triage/vex/*.json` — `lint-vex-product.sh`, the gate's rewrite
step, and the attest step. A file committed at `triage/CVE-X.openvex.json`
satisfies 6.4 literally while being linted by nothing, handed to Trivy by
nothing, and attested by nothing.

6.4 also bundles two obligations — record, and attach as an attestation — whose
triggers differ. Attestation exists only on the main-branch release job, which is
gated on a diff touching `image/`. A pull request adding only a VEX statement
therefore never attests it.

---

## 3. Reported, not independently verified

Recorded for review B to confirm or reject. **[R]** throughout.

- **3.1 `6.14` / `6.22` — no duty to withdraw a false statement.** 6.14 binds
  *recording*; a statement authored before the evidence existed is never
  re-recorded, so nothing obliges withdrawal. 6.22 covers supersession only. Every
  criterion whose actor is THE Triage Process (6.4, 6.5, 6.8, 6.14, 6.15, 6.16,
  6.22) is enforced by no code: `govulncheck-report.sh` never reads `triage/vex/`,
  so the comparison that would enforce 6.14 is made by nobody.
- **3.2 `6.14` and `6.15` quantify differently.** 6.14 forecloses the
  justification *"for that image"* if a symbol is reachable in **a** binary; 6.15
  requires evidence *"for that binary"* — a phrase with no antecedent in 6.15.
  Grafana ships three Go binaries; CVE-2026-25681 affects only the zipkin plugin,
  yet 6.14 forecloses the claim for the whole image, and an author could satisfy
  6.15 by citing the clean `bin/grafana` result.
- **3.3 `6.7` / `6.11` vs `lint-accepted-risk.sh`.** The lint enforces five rules
  stated nowhere: `treatment ∈ {accept, transfer}`; `issue` mandatory on
  transfer; `id` and `statement` required; the filename must match an existing
  `image/<name>/image.yaml`; and a past expiry is a hard failure. `treatment:
  mitigate` satisfies 6.7 and 6.11 word for word and is rejected by the lint.
- **3.4 Req 3.5 collision.** A lapsed expiry fails `lint-accepted-risk.sh`
  repo-wide, so an unrelated Renovate digest-only PR is blocked by a grafana entry
  it never touched — against Req 3.5's automerge-on-CI-success.
- **3.5 `6.17`–`6.21` assume one product per statement.** All five say *"product
  identifier"*, singular; OpenVEX carries a `products` array and the lint
  correctly iterates it. With several products, 6.20 has no determinate truth
  value. Req 1.1 makes cert-manager three image definitions, so the natural
  statement for GHSA-hrxh-6v49-42gf names three products at once.
- **3.6 `6.17`–`6.19` — lint enforces three unstated rules.** Zero subcomponents
  is rejected as 6.19 (which speaks only of a subcomponent *carrying a version*);
  a missing `repository_url` is rejected as 6.18 (which speaks only of a
  repository *other than* the published one); an empty document is rejected as
  6.17. And the gate itself rewrites products to bare `pkg:oci/grafana`, which
  Trivy demonstrably matches — so the gate manufactures the artifact its own lint
  forbids.
- **3.7 `6.12` is enforced by filename.** The lint matches `.trivyignore*`; a
  Trivy ignore file has no required name, which is why the lane's own files are
  `<image>.yaml`. `hack/scan-ignores.yaml` referenced from a workflow violates
  6.12 in substance with the lint green.
- **3.8 No state for "triaged, real, not treated yet."** `triage/README.md` and
  `LOG.md` both describe prioritisation — real, low EPSS, not KEV, so it waits.
  Req 6 has no criterion for it: the gate is red, there is no record, no owner and
  no expiry, and nothing bounds how long an image stays un-mergeable. **The repo
  is in this state right now** — 1 CRITICAL and 18 HIGH, none treated.
- **3.9 Vocabulary.** Three undefined actors — THE Scan Gate (6.1, 6.9), THE Scan
  Pipeline (6.2, 6.3, 6.6, 6.10, 6.13), THE CI Pipeline (6.11, 6.12, 6.17–6.21) —
  with no definition or relationship stated. 6.13's govulncheck runs in the PR
  gate's job yet is attributed to the Pipeline whose other duty is the daily cron.
  Decision vocabulary drifts too: 6.4 "not-affected" vs `not_affected`; 6.5 "fix"
  vs `fixed`; 6.7 "accepted risk / upstream transfer" vs the lint's
  `accept`/`transfer`; 6.7's "remediation" appears nowhere else. Nothing states
  whether concluding "fix" (6.5) also obliges a `fixed` statement.
- **3.10 `6.9` boundary.** Assigned to the Scan Gate only, so an expired exception
  on the 6.2 rescan path is unaddressed; and the expiry day itself is undefined
  (the lint treats `days < 0` as expired and `days <= 14` as notice, so an
  exception expiring today is neither).
- **3.11 `6.3` "new" is undefined.** The implementation reads it as "no open `cve`
  issue", so a CVE whose issue was closed is new again and refiles daily. 6.3 also
  mandates EPSS and KEV in the issue while `triage/README.md` says feed failures
  soft-fail — an issue filed during a FIRST.org outage violates 6.3 as written.
- **3.12 `6.16` is unfalsifiable.** *"SHALL treat that result as unmeasured"*
  names no artifact a test could inspect; its enforceable half duplicates 6.15.
- **3.13 `6.7`'s `ref`** must point into `triage/LOG.md`; the lint checks only
  that the field is non-empty.
- **3.14 No revalidation duty.** Nothing bounds the life of a `not_affected`
  statement or requires re-examination when new evidence lands.
- **3.15 `6.13` is unsatisfiable as written.** *"every Go binary in that image"* —
  the implementation walks only executables over 1 MB. *"whether the vulnerable
  symbol is reachable"* demands a boolean; the reporter produces three values, and
  6.16 depends on the third existing. *"for each finding"* does not say whose:
  read as Trivy's it is unsatisfiable (kin-openapi is invisible to govulncheck);
  read as govulncheck's, it found 8 findings Trivy never raised and no criterion
  says what to do with them.

---

## 4. What this blocks

Not a proposed remedy — a statement of sequencing.

| Work | Blocked by |
|---|---|
| Writing any `accept` / `transfer` treatment (task 7.3, steps 2–4) | **1.1** — the gate would go green while 6.1 says it must fail |
| Arguing the tempo findings on a non-`execute_path` justification | **2.1** — indistinguishable from using the loophole |
| Claiming the published image is scanned | **1.3** |
| Claiming Req 7.5 holds across the pipeline | **1.2** |
| Relying on 6.22 supersession | **2.4** |

Findings **1.2** and **1.3** are code defects independent of any wording change.

---

## 5. Checked and found sound

Recorded so the coverage of this review is legible, and so review B can
concentrate elsewhere.

- **6.20 / 6.21 as a pair** — complementary and jointly exhaustive over the status
  axis; the no-status case falls correctly on 6.20's side. (Their interaction with
  6.22 is finding 2.4; the pair itself is well formed.)
- **6.19's stated rule** — unambiguous, and matched exactly by `check_subcomponent`
  including the `?`/`#` stripping, so a qualifier is never mistaken for a version.
- **6.11's 90-day ceiling** — precise, measurable, single-valued, matched by
  `MAX_DAYS=90`.
- **6.10's 14-day window** — matched by `NOTICE_DAYS=14`; reusing
  `lint-accepted-risk.sh` means the notice and the gate cannot disagree about
  "expired".
- **6.18's exact-string rule** — well formed; `published_repository()` implements
  exactly it. The defect is the *absent* case (3.6), not this rule.
- **6.12's direction** — a single suppression channel, stated the right way round
  and falsifiable in principle. The defect is the definition of the class (3.7).
- **6.8** — unambiguous and structurally consistent with the two-directory split.
  Nothing else in Req 6 requires what it forbids; its collision is with OpenVEX
  `affected` (2.2).
- **6.2's rate** — cleanly measurable; the only issue is the meaning of
  "published".
- **6.3's issue contents** — enumerated concretely enough to test field by field.
- **6.5** — trigger and artifact both concrete; consistent with Req 3.2.
- **Req 6 ↔ Req 2** — 6.4's attestation and 2.2's signature/SBOM/provenance
  compose without conflict, same cosign step family on the same digest.
- **Req 6 ↔ Req 8** — 6.1, 6.2, 6.6 and 6.13 all place work where 8.1 requires
  it; nothing in Req 6 requires scanning inside the devcontainer.
- **6.17–6.21 mutual consistency** — no two can fire contradictorily on the same
  well-formed statement.
- **6.9's mechanism** — counting an expired exception as uncovered, rather than
  deleting or rewriting it, is the right kind of rule. The defects are its missing
  converse (1.1) and its Scan-Gate-only scope (3.10).

---

## 6. Limits of this review

- Only Requirement 6 was reviewed in depth. Requirements 1–5, 7 and 8 were
  consulted only where a Req 6 criterion touches them.
- Section 3 is unverified. Several of those findings assert behaviour of
  `lint-accepted-risk.sh` and `rescan.yml` that was not re-read by hand.
- No fix is proposed anywhere in this document, and no criterion was changed while
  writing it.
- This is one of two reviews by design. Where review B disagrees, the
  disagreement is the finding.
