# Production-readiness critique and spec revision (one-man-show scope)

Goal: turn the 2026-08-21 security-leader critique of the catalogue into a
revised spec that (a) a single maintainer can keep honest in production and
(b) leaves the primitives in place for a fork to scale to org level without
re-architecting. Every critique point gets an explicit disposition before
anything is implemented (amend the spec first, then /spec-implement).

- [x] 1. Record the critique with repo evidence per point in
      `.specs/dhc-catalogue-mvp/reviews/2026-08-21-production-readiness-critique.md`
      (same shape as the 2026-08-04 reviews: method, verification legend,
      numbered findings, prior-art column, disposition ledger)
- [x] 2. Dialogue, one point at a time: state the goal, weigh options, record
      the disposition (accept / accept with modification / reject with reason /
      defer with primitive in place) in the review doc's ledger
      (done 2026-08-21: framing A, F1–F13 all accepted with mechanisms;
      amendment sequence A–D in the review's section 6; F12 terms memo
      landed as `data/dhi-terms-2026-08-21.md`, obligations folded into
      clusters C and D)
- [x] 3. Spec amendments per accepted point: EARS criteria in
      `requirements.md`, rationale in `design.md`, task entries in `tasks.md`,
      one PR per cluster (the review's section 6 overrode the one-PR-per-decision
      rule for spec amendments; implementation stays one PR per task)
      - [x] A. release path and published set (F3, F9, F6): Req 1.9,
            2.7–2.26, 6.35–6.37, 7.7–7.10, Req 2.1/2.2 amended; design decision 6
            + release flow; tasks 9.1–9.8. Drafted, independently reviewed
            (17 findings + 7 angle points, all dispositioned, revision ledger
            in reviews/), revised in eight commits; PR #97 awaiting the
            owner's review; ADR 0003 (PR #98) is its spike
      - [ ] B. statuses and clocks (F5, F4, issue closing): Req 6.38–6.54,
            amendments to 2.6, 2.8, 6.1, 6.3, 6.7, 6.8, 6.10, 6.11, 6.35; design
            decision 7 + rescan flow; tasks 10.1–10.7. Design reviewed against
            the cluster A decisions first (critique 5.2 amended 2026-08-23;
            ADR 0004 spike, PR #99); drafted 2026-08-23, independent review
            next
      - [ ] C. upstream trust (F2, F10, F8, chart tracking, `/main` lint)
      - [ ] D. catalogue posture (F1, F11, F12, F7, register; new Req 9)
- [x] 4. Only then: implementation PRs via /spec-implement, TDD where code

## Review

(to fill when done)

## Task 10.2: compiler emits `affected` from exceptions, carry-forward, lapses (2026-09-03)

Goal: every known finding carries a published status. An accepted or
transferred finding is visible to a consumer as `affected` with the decision
attached, a lapsed exception is visible as `under_investigation` naming the
lapse, and a re-compile keeps first-seen and records change (Req 6.8, 6.35,
6.37 to 6.41). TDD: tests first, red, then the compiler and the lint.

- [x] 1. compile-vex_test.sh: cases for affected (fields, products, subcomponents,
      first seen), covered-by-source suppression, expired exception (no affected,
      under_investigation with lapse note), carry-forward (timestamp kept,
      last_updated on change, not on no-change), inert entry (no statement), report counts
- [x] 2. lint-vex-product_test.sh: hand-authored affected / under_investigation / missing
      status fail naming the statement (Req 6.39); existing "other status" cases inverted
- [x] 3. compile-vex.sh: read triage/accepted-risk/<definition>.yaml (COMPILE_VEX_EXCEPTIONS
      seam), attribute suppressed findings to entries, emit affected, lapses, carry-forward
- [x] 4. lint-vex-product.sh: Req 6.39 rule
- [x] 5. build.yml summary line counts affected and lapsed; docs (triage/README.md statuses,
      user-manual compiler paragraph); tasks.md tick 10.2
- [ ] 6. Run the whole validate chain locally as CI runs it; rehearse pass 2 against a real
      report (the 13.1.5 rootfs scan) before pushing

## Task 10.3: rescan re-attestation, replacing (2026-09-03)

Goal: the published digest carries today's scan reports and one OpenVEX
document that reflects today's decisions, and a consumer never gets one of
several documents at random. Re-attestation replaces (ADR 0004); exactly one
OpenVEX attestation per tag-referenced digest and platform manifest is an
invariant proven daily (Req 6.42 to 6.45, 6.55, 6.58). TDD, stubs for the
tools, the first CI run is the keyless measurement ADR 0004 left open.

- [x] 1. compile-vex.sh: COMPILE_VEX_ISSUES map, carried-forward statements name their open issue
- [x] 2. check-attestation-count.sh (+ test): exactly one OpenVEX attestation per tag-referenced
      digest and manifest, from the .att manifests, names every deviation, fails the run
- [x] 3. reattest.sh (+ test): per digest attest each report --replace, read the previous document
      through cosign verify-attestation (both roles), vexctl merge when several, compile, differs
      test on canonical statement sets or wrong count, attest --replace on digest and manifests,
      JSONL record with the before/after layer lists and Rekor indexes (the measurement)
- [x] 4. install-tool.sh: vexctl v0.4.4 pinned (+ test fixture)
- [x] 5. rescan.yml: permissions, cosign + vexctl, issues map before the compile, the re-attest step,
      the count invariant, the summary table; catalogue-policy.yaml permissions
- [x] 6. docs: user manual (rescan row, verification), tasks.md tick; SC2154 sweep, actionlint,
      yamllint, every suite; first run dispatched after merge is the measurement, recorded in LOG
      (ADR 0004 "Measured in CI" and the LOG entry of 2026-09-04)

## Fix: carry-forward pairs a statement with its own kind (2026-09-04)

Goal: a rescan that changes nothing re-attests nothing. The first no-change
day after task 10.3 (run 33867898868) replaced the OpenVEX document on three
grafana digests; for 13.1.2 and 13.1.3 no input had changed. Cause: the
compiler keyed last time's statements by finding and package only, and a
package can carry an `affected` (excepted in one binary) and an
`under_investigation` (uncovered in another) at once, so the second paired
with the first, its shape differed, and it was re-stamped on every compile.

- [x] 1. Failing case first (compile-vex_test.sh 40): both statuses published, a recompile from
      the same inputs re-stamps nothing and yields the previous statement set; 40b keeps the
      transition (under_investigation before the decision pairs with the new affected)
- [x] 2. compile-vex.sh: previous statements keyed by finding, status and package; own kind
      first, the other kind for the same package second, unscoped third
- [x] 3. Measured on real data: today's scan of grafana 13.1.2 compiled against today's attested
      document differs before the fix (10 statements re-stamped) and is identical after it
- [x] 4. compile-vex and reattest suites green; the next rescan is the live confirmation
## Fix: a Sigstore blip is retried, not failed (2026-09-04)

Goal: one failed write out of ninety must not fail the day. Run 33854524508
(manual, 08:39 UTC) failed at the re-attest step on a single
`cosign attest --type vuln --replace`: Rekor answered "already exists" to an
upload cosign's client had retried, then 404 for that entry by UUID from a
lagging replica. The scheduled run three hours later wrote all 35 manifests.
A new attempt signs with fresh keys and lands a new entry, so trying again
is the mitigation; three failures are still a failure.

- [x] 1. Failing cases first (reattest_test.sh 8 and 10): one stubbed blip is retried, named as a
      warning and counted in the record; a refusal fails after exactly three attempts
- [x] 2. reattest.sh: `attest` wraps both call sites, REATTEST_RETRY_DELAY (15 s, tests 0), the
      summary line counts retried writes
- [x] 3. user manual: the warning in the troubleshooting table; suites and shellcheck green

## Task 10.4: clocks and the status issue (2026-09-05)

Branch: `task-10.4-clocks-status-issue`. Goal: every finding on a supported
digest gets a stopwatch read from attestations (first seen, decided, fixed),
and one issue plus one artifact show them against the policy's ceilings
(Req 6.46, 6.47). The tool is pure data in the tested `rescan` package; I/O
stays in a thin command and the workflow, like `rescan-report`.

- [x] 1. `status.go` (+ `status_test.go`, TDD): per (repository, finding) over the supported set:
      first seen from the statement timestamp (never later than previously published), decided
      from `action_statement_timestamp` (affected) or the statement timestamp (not_affected,
      fixed), undecided while any supported digest carries it under_investigation or without a
      statement; fixed as the first day absent, reported and suppressed alike, from every supported
      digest of its repository, carried forward from the previous status JSON; a repository with no
      report today invents no absence; age and ceiling (KEV ceiling first, then severity) for
      undecided findings; medians and counts; issue body with marker, table and fenced
      `metrics.json` that round-trips
- [x] 2. `cmd/rescan-status`: reads enumeration.tsv, `reattest/<name>__<12hex>/out/*.openvex.json`,
      `trivy/<name>__<12hex>__<platform>.json`, kev.json, the policy numbers via triage-policy.sh
      values passed as flags, the previous JSON; writes metrics.json and the issue body
- [x] 3. rescan.yml: read the previous fenced JSON from the open "Catalogue status" issue (marker
      `<!-- catalogue-status -->`), run the tool, create or edit the issue, upload the JSON as the
      `catalogue-status` artifact, one summary line; SC2154 sweep, actionlint, yamllint,
      lint-workflow-policy, local rehearsal of the shell with a stub gh
- [x] 4. tasks.md tick; user manual: the rescan row and a short "Catalogue status" paragraph
      (rehearsed 2026-09-05 on the real supported set with a stub gh: 13 findings over 7 digests,
      create then edit, carry-forward identical across two passes)

## Task 10.6: evidence-based issue lifecycle over the supported set (2026-09-05)

Branch: `task-10.6-issue-lifecycle`. Goal: a cve issue closes when the evidence
says so and reopens when the finding returns, and the label says which evidence
(Req 6.52 to 6.57); the tool records no decision (Req 6.54). Pure decision in
the tested `rescan` package, I/O in a thin command, a verified SBOM read, and
three workflow steps placed before the dedup so a reopened issue is open when
the filer runs.

- [x] 1. `lifecycle.go` (+ tests, TDD): parse our own issue template (marker, images, packages);
      per finding over the supported set: reported, covered (exception, not_affected, fixed, with
      the covering artifact) or absent; an open issue closes on "absent everywhere" (label from
      the attested SBOMs: fixed when every occurrence of the package bumped, removed when it left
      every SBOM, absent otherwise with scanner and database versions) or on "covered wherever
      listed" (accepted over not_affected over fixed, the weakest grade wins); a supported digest
      without a report today blocks every close; a closed issue reopens when its finding is
      reported on a supported digest, resolved labels removed, the latest closed issue per finding
- [x] 2. `scripts/fetch-sboms.sh` (+ test with a cosign stub): the CycloneDX SBOM of every supported
      platform manifest through `cosign verify-attestation --type cyclonedx` against the roles that
      attest it (Req 6.58); a manifest without one is named and skipped
- [x] 3. `cmd/rescan-lifecycle`: reads issues.json (gh), the enumeration, reports, SBOMs, scanner
      version, triage/vex sources; writes actions.json; shared input loading with rescan-status
- [x] 4. rescan.yml: evidence, decision, apply (labels created idempotently) before the dedup step;
      summary line; SC2154 sweep, actionlint, yamllint, lint-workflow-policy; rehearsal with a stub gh
- [x] 5. Rehearsal on the real supported set: what today's evidence would do to the open issues
- [x] 6. tasks.md tick; user manual: the lifecycle paragraph replaces "it never closes them"
- [x] 7. Review round: see below
      (rehearsed 2026-09-05: 25 issues, 7 digests, 14 SBOMs; 16 closes, 6 fixed on SBOM proof and 10
      accepted on the grafana exceptions, 0 reopened, 0 kept; the rehearsal caught the loop's stdin
      being the enumeration, fixed with a regression case)

### Review (2026-09-05, /code-review of #148, 23 correctness and 14 cleanup candidates)

Confirmed and fixed in the same PR, each with a test: the OpenVEX source
directory was a relative path under `go -C` (never found; now absolute, and
the command warns when it finds nothing); a digest with one platform
manifest unscanned counted as examined (now every manifest needs a report,
in the status tool too); a reopen of a hand-closed issue serialised
`remove_labels` as null and would have broken the apply loop on the first
reopen (lists are lists, and jq guards); "bumped" was any different version
(now at or above the fix on the installed version's release line); a
statement without components read as an empty SBOM and graded `removed`
(no components is no evidence, in the script and the tool); an empty
installed version dropped the package line; the "absent from" list was
keyed by repository, not digest; the reopen picked the newest closed issue,
not the original; an open issue could keep a stale resolved label (a
relabel pass, and close-then-label order); a digest scanned without its VEX
was evidence (now it blocks closes and reopens); a suppressed finding
outside the aperture read as absent; the issue list's page limit was
silent; the summary counted decided, not applied; the labels were
hard-coded in two places (now `triage.resolved_labels` in the policy
file, read through triage-policy.sh); the lifecycle ran after the
compiler's issue map (now right after the scan). Left as designed, noted
in the manual: no "keep closed" switch. Left for later: one policy reader
for the verification section, a machine-readable block in the cve issue
template.

## Task 10.7: truth pass over cluster B (2026-09-06)

Branch: `task-10.7-truth-pass`. Goal: every sentence that still describes the
pre-cluster-B world says what is built (Req 6.8 as amended, Req 7.1): an
exception is published as `affected` and never as `not_affected` or `fixed`,
re-attestation replaces, the rescan closes and reopens issues on evidence,
the status issue carries the clocks, ceilings are per tier from `decided_at`,
and clocks and issues run over the supported set.

- [x] 1. docs/user-manual.md: the lanes table gains the third verb (`affected`) and an
      `under_investigation` row, the decision tree and lane prose stop saying "internal, never
      attested", the workflows and crons rows and the Req 6 map name the lifecycle and the
      status issue, the glossary gains supported set, status issue and resolved labels
- [x] 2. docs/CONVENTIONS.md: "must never be written as a VEX" becomes "published as affected,
      never as not_affected or fixed"; the rescan paragraph gains replace, lifecycle, status
- [x] 3. triage/README.md and triage/accepted-risk/README.md: the lane quote, the publishing
      paragraph, the expiry paragraph (lapse to under_investigation), the daily rescan section
      rewritten as built, decided_at and the ceilings, the supported set
- [x] 4. triage/accepted-risk/grafana.yaml header and build.yml's attest-step comment: the
      "never attested" sentence goes
- [x] 5. design.md decision 7 marked as built, its two stale phrases (badges, cve badge) fixed,
      an as-built note with the deviations; tasks.md tick
- [x] 6. README consumer recipe: already the rendered one-verify-attestation-per-type block
      (task 10.3); verified unchanged, no edit

### Review

Every flagged sentence located by grep before editing, every edit anchored on
the exact old text; lint-pins (reads CONVENTIONS.md), lint-accepted-risk
(reads grafana.yaml), yamllint and actionlint on build.yml (nine notes, the
same nine as main), the render drift check, all clean.

## Task 11.1: quarantine and automerge truth in renovate.json5 (2026-09-06)

Branch: `task-11.1-renovate-quarantine`. Goal: a third-party release is not
offered until it has aged three days, a release without a timestamp waits
rather than passes, and the automerge wording says exactly what automerges
(Req 3.5, 3.7). Renovate reads only its own config, so the value is one line.

- [x] 1. renovate.json5: one datasource-scoped rule (github-tags, github-releases, npm, pypi,
      helm, go; no matchUpdateTypes) with `minimumReleaseAge: "3 days"` and
      `minimumReleaseAgeBehaviour: "timestamp-required"`; docker deliberately absent; the comment
      states independence from age, signal and gates, pin-at-bump-time, npm's unpublish window
- [x] 2. The Req 3.5 rule's comment and CONVENTIONS' automerge rows state the decided scope: patch
      and digest updates of a from-source upstream automerge behind green required checks;
      repackage and tool bumps never
- [x] 3. test/renovate/managers.test.mjs: the age rule's shape, `releaseTimestampSupport === true`
      on every aged datasource against the pinned renovate/dist, docker exempt, automerge scope
- [x] 4. `renovate-config-validator --strict` on the pinned version; the manual's Renovate section
      gains the pending-release sentence and a troubleshooting row; tasks.md tick

### Review

Validated with the pinned renovate 41.173.1 (`renovate-config-validator --strict`),
which knows `minimumReleaseAgeBehaviour` and its two values; every aged
datasource reports `releaseTimestampSupport === true` in that dist. The new
checks fail four ways against the previous config and pass against this one.

## Task 11.2: authenticity classes, declared and enforced at bump time (2026-09-06)

Branch: `task-11.2-authenticity`. Goal: every definition says how its upstream's
authenticity is established, lint refuses a definition that says nothing, and
a refresh writes no field of a bump whose signal fails verification, naming
the signal (Req 1.10 to 1.12, 3.8). Measured 2026-09-06: cert-manager v1.21.1
is an annotated tag GitHub verifies, valkey 9.1.2 a lightweight tag on a
verified commit, hardened-app v0.1.0 an unsigned commit (the owner's item).

- [x] 1. definition-lib.sh: `authenticity_class`, `authenticity_stamp`, `github_verification`
      (GitHub's verification statement for a tag object or a commit, JSON read with node, the
      one runtime every environment here has)
- [x] 2. lint-pins.sh (+ tests): a marker on every definition, `none` and a missing marker refused
      by name, the class coherent with the archetype, dhi.io package repositories restricted to
      apk/<distro>/<release>/main and deb/<distro>/main
- [x] 3. refresh-definition.sh (+ tests): signed-tag needs an annotated tag whose object GitHub
      verifies, signed-commit a verified commit; refusal before any write, naming the signal; the
      dated verification stamp written beside the pin
- [x] 4. refresh-grafana.sh (+ tests): the versions API's per-architecture sha256 must equal the
      dl.grafana.com sidecar before anything is written, refusing on disagreement naming both;
      the stamp
- [x] 5. The seven definitions carry their marker; tasks.md tick; the owner's item restated

### Review

Rehearsed against the real upstreams on 2026-09-06 with the code that will run:
cert-manager v1.21.1 (annotated tag, GitHub verification valid) and valkey 9.1.2
(lightweight tag, verified commit) refreshed and stamped; hardened-app v0.1.0
refused as unsigned with nothing written; grafana 13.1.5 rebuilt byte for byte
from the live versions API and dl.grafana.com sidecars, plus the stamp. Four
suites green (definition-lib, lint-pins, refresh-definition, refresh-grafana),
shellcheck and yamllint clean, the Renovate manager fixtures still match the
marked definitions.

## Task 11.3: checkpoints 2 and 3, PR time and daily (2026-09-06)

Branch: `task-11.3-checkpoints`. Goal: a repackage pin is cross-checked at PR
time against the bytes served and the publisher's version statement (Req 3.9),
and every definition's declared signal is re-verified daily, a mismatch failing
the run and filing a supply-chain issue (Req 3.10), with lapsed compat
review-by dates reported in the same step (Req 4.9). One comparison function
shared by the three checkpoints. Day one asserts every definition: hardened-app
0.1.1 landed signed through #153.

- [x] 1. definition-lib.sh: `version_statement_url`, `versions_api_sha`, `shas_agree` (+ tests);
      refresh-grafana.sh (checkpoint 1) uses them
- [x] 2. verify-arch-pins.sh (+ tests): pinned, served and version statement agree per architecture,
      each named on failure; an unknown statement origin fails closed
- [x] 3. check-authenticity.sh (+ tests): signed-tag, signed-commit and cross-origin-checksum
      re-verified against the origin, a moved tag is a mismatch, records in JSONL; lapsed compat
      review-by dates reported
- [x] 4. rescan.yml: the step after the invariants, supply-chain issues filed from the records
      (marker `<!-- rescan-signal: <definition> -->`, label `supply-chain`, no duplicates), summary
      line; validate.yml runs the new suite; lints and the SC2154 sweep
- [x] 5. Rehearsal against the real upstreams; tasks.md tick

### Review

Rehearsed 2026-09-06: the daily check against the real upstreams verified all
seven signals (three signed tags, three signed commits, grafana's two origins
agreeing on both architectures), the workflow step run verbatim with a stub gh
filed nothing on real data and one correctly formed supply-chain issue on a
fabricated moved tag. Five suites green (definition-lib, refresh-grafana,
verify-arch-pins, check-authenticity, plus the lint battery), shellcheck,
yamllint, actionlint, lint-workflow-policy and the SC2154 sweep clean.

## Task 11.4: chart versions tracked, same-tag chart automerge, valkey compat as transfer (2026-09-06)

Branch: `task-11.4-charts-compat`. Goal: Renovate tracks the three upstream
chart versions (Req 3.11, never automerged), digest-only bumps of the
catalogue's own image pins under chart/ automerge on green (Req 3.12), and the
valkey compat decision is structured metadata with a review-by date that
validate fails once past (Req 4.5, 4.8), with the upstream ask drafted from a
re-runnable measurement.

- [x] 1. renovate.json5: a helm-datasource manager over chart/<name>/chart.yaml capturing
      upstream.repository as registryUrl; a helm automerge:false rule; a docker digest-only
      automerge rule for ghcr.io/mm-weber/dhc/** ordered before the build-layer rule; fixtures
      in managers.test.mjs for the three captures, the non-capture and the registryUrl;
      renovate-config-validator --strict
- [x] 2. chart/valkey/chart.yaml `compat:` block; chart/chart.schema.yaml (yamale) validated in
      validate.yml; scripts/lint-compat.sh (+ tests) failing a past review_by (Req 4.8); the
      README cites the block
- [x] 3. triage/upstream/2026-08-25-valkey-helm-init-container-image.md with
      checks/valkey-helm-init-container.sh re-running the render measurement; the owner files
      it and records the number in the compat block and LOG.md
- [x] 4. tasks.md tick; suites, validator, yamllint
