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

## Task 11.5: truth pass for cluster C (2026-09-07)

Branch: `task-11.5-cluster-c-truth-pass`. Goal: every document that describes
upstream tracking says what 11.1 to 11.4 built (quarantine, declared
authenticity, tracked chart versions, digest-only chart automerge), the
cert-manager pin's "still-open gap" comment goes, the chart READMEs state
each image's authenticity class, the legacy grafana alias handler goes as
dead code, and design.md Decision 8 is marked as-built.

- [x] 1. Alias removal, test first: refresh-grafana_test.sh case 5b becomes "a definition on
      the legacy alias is refused, not migrated"; then the renovate.json5 matchString and the
      refresh script's alias parse go; suites, validator and fixtures green
- [x] 2. docs/CONVENTIONS.md: chart bullet (tracked, never automerged), the managers intro and
      table (chart-version row, chart image pins row), the automerge bullet states Req 3.12,
      the signal sentence (Req 3.8, 3.9, 3.10), the PR section's automerge sentence
- [x] 3. chart/cert-manager/chart.yaml comment; chart/valkey/chart.yaml and README version
      note (the image may run a patch ahead of the chart's appVersion); valkey README image
      row and the deployer-side features paragraph; every chart README states its images'
      authenticity class
- [x] 4. docs/user-manual.md: Renovate PR table (chart version row, chart pin automerge
      scope, the signal sentence), the managers reference, "Adapt a chart" step 1, the
      requirements map's Req 3 row
- [x] 5. design.md Decision 8 as-built; tasks.md tick; em-dash sweep of added lines

**Review (2026-09-07).** Test first on the only code change: case 5b of
`refresh-grafana_test.sh` now expects a definition on the legacy alias to be
refused by its url line and left untouched; it failed against the migrating
script, passed once the alias parse and the renovate matchString were gone.
The suite, shellcheck (pre-existing style notes only), the Renovate validator
and the manager fixtures are green; yamllint, yamale, lint-compat, lint-pins
and both chart renders pass on the edited pin files. Docs say what cluster C
built: chart versions tracked and never automerged, digest-only chart pin
bumps automerged, the three-day quarantine, and the signal verified at bump
time, PR time and daily. Each chart README states its images' authenticity
class in the reader's words (grafana's says plainly that it is agreement of
origins, not a signature). Cluster parents 10 and 11 are ticked, every child
being done. Only pre-existing table labels carry em dashes.

## Task 13.1: SECURITY.md, notice, attribution, trust-boundary table (2026-09-07)

Branch: `task-13.1-security-policy`. Goal: the catalogue's posture is stated
where a consumer looks (Req 9.1), the substrate's copyright and licence are
carried with the SBOM licence statement (Req 9.16), the README states
non-affiliation (Req 9.17), and every component's owner class and seam
alternative are tabled (Req 9.15).

- [x] 1. Measure what the policy states: reporting channel, advisories, live ruleset
      (bypass, required checks), in-image licence copies, the substrate licence text
- [x] 2. LICENSES/Apache-2.0.txt (the substrate's own copy) and NOTICE
- [x] 3. SECURITY.md with every Req 9.1 item, dated snapshots, homes named
- [x] 4. docs/concepts.md trust-boundary table (owner class, authenticity or pin, seam)
- [x] 5. README, CLAUDE.md, requirements and design intros: labels, attribution,
      non-affiliation; CONVENTIONS modification-notice rule; manual links
- [x] 6. tasks.md tick; em-dash sweep; table column counts

**Review (2026-09-07).** Measured first, then written: the reporting channel
is still disabled (the policy names it and says what its absence means; the
switch is the owner's, the daily assertion 13.2's), no advisory exists, the
live ruleset requires five checks and one review with an always-on
administrator bypass, the substrate's licence text equals SPDX's apart from
its filled-in appendix copyright, and the runtime images carry no licence
text of their own. SECURITY.md carries every Req 9.1 item in that order,
each number dated and its home named. The trust-boundary table has sixteen
rows in the three Req 9.15 classes with the framing addendum's seams. The
labels dropped from four intros; the attribution and non-affiliation
sentences sit in the README, the design overview and NOTICE. No em dashes in
added lines; the README's rendered verification block is untouched.

## Task 13.2: governance as code (2026-09-07)

Branch: `task-13.2-governance-as-code`. Goal: the intended ruleset is a
committed export compared daily against the live one through anonymous reads
(Req 9.8, 9.9), the reporting channel's enabled state is asserted daily
(Req 9.3), CODEOWNERS names the maintainer per lane (Req 9.10), and the
admin view with bypass actors lands in data/.

- [x] 1. Test first: scripts/check-governance_test.sh over a localhost fixture API
      (identical modulo server fields, bypass actors and order; a differing rule; a
      missing check; committed without live; live-only active branch ruleset; disabled
      or tag-target live-only ignored; reporting disabled; endpoint unreadable)
- [x] 2. scripts/check-governance.sh: anonymous reads, canonical comparison by name over
      name, target, enforcement, conditions, rules; both directions; JSON record
- [x] 3. .github/rulesets/main_sec.json (export shape, bypass_actors carried), its README
      (the second-maintainer switch), CODEOWNERS, data/ admin view
- [x] 4. rescan.yml step "governance invariants (Req 9.3, 9.9)" with outputs and the
      summary line; rehearsed locally against the live API
- [x] 5. SECURITY.md present tense; manual's branch-protection section; CONVENTIONS PR
      section; tasks.md tick; em-dash sweep; shellcheck, actionlint, lint-workflow-policy

**Review (2026-09-07).** Test first: ten cases over a localhost http.server
(the list endpoint as `index.html`, details as files) failed against the
missing script, then passed; shellcheck clean. The live rehearsal reproduced
the expected state exactly: the export equals the live `main_sec` after
canonicalisation (rule and check order differ live, no difference reported),
and the two failures are the owner items the task lists. The step runs last
in the rescan so those failures fail the run without skipping the issue
lifecycle and the status publish; the step block was extracted verbatim,
shellchecked and executed locally with the outputs file inspected. actionlint,
yamllint and lint-workflow-policy pass.

## Task 13.3: revocation record (2026-09-07)

Branch: `task-13.3-revocation-record`. Goal: every revoked digest is a
schema-checked entry in `triage/revocations.yaml` (Req 9.5, 9.6), the daily
rescan fails by name when a catalogue tag still references one (Req 9.7),
the status issue lists the record, and a short runbook names the moves GHCR
actually has.

- [x] 1. Test first: scripts/check-revocations_test.sh (empty record; a revoked index digest
      and a revoked platform manifest referenced by a tag; a frozen revoked digest; an
      unreadable file; schema fixtures through yamale) and a Go test for the status section
- [x] 2. triage/revocations.yaml (empty), triage/revocations.schema.yaml (replaced or
      withdrawn entry shapes), scripts/check-revocations.sh, the status tool's --revocations
- [x] 3. docs/revocation-runbook.md: replacement through the release path; withdrawal by
      version deletion or a tombstone, with what each costs and what the rescan then reports
- [x] 4. rescan.yml: the record read by the status step, the assertion in the posture step at
      the end; validate.yml: yamale on the record and the new suite
- [x] 5. SECURITY.md present tense; triage/README.md section; tasks.md tick; em-dash sweep;
      shellcheck, actionlint, lint-workflow-policy, go test, local rehearsal

**Review (2026-09-07).** Test first on both halves: the bash suite (six
behaviour cases plus five schema cases through yamale with the real schema)
failed on the missing script and passed once written; the Go test for the
status section failed to compile before the type existed and passes now, with
the JSON round trip. Rehearsed against the real enumeration (73 rows): the
empty record passes, and a real index digest recorded as revoked names all
three tags that reference it, one line each. The status tool rendered the
rehearsal entry in its table. The posture step block was extracted verbatim,
shellchecked and executed; actionlint, yamllint, lint-workflow-policy, go vet
and gofmt are clean. Deviation from the design's placement, recorded: the
verdict is asserted in the posture step at the end (the invariants step only
produces the record for the status issue), for the same reason 13.2 runs
last, so a failure never starves the day's issues and status.

## Task 13.4: consumers, declared list, portability block, daily smoke test (2026-09-08)

Branch: `task-13.4-vex-consumers`. Goal: the VEX consumers are a declared
list in the policy file with one authoritative (Req 9.11); every PR scan and
rescan reports a portability block naming each other consumer's suppression
result per statement the authoritative one suppressed, informational
(Req 9.12); the rescan runs the published recipe verbatim daily against one
published digest, failing only on a broken step or a suppression missing in
the authoritative consumer (Req 9.13); the recipe gains one scan step per
declared consumer, rendered from the list so the two cannot drift.

- [x] 1. catalogue-policy.yaml `consumers:`; triage-policy.sh `consumers` and
      `authoritative-consumer` queries, refusing a list without exactly one authoritative;
      tests first
- [x] 2. scripts/vex-consumer.sh: the adapter contract (trivy from a report or a scan, grype
      from a scan), one normalised JSONL shape; stubs in tests; canonical join key documented
- [x] 3. scripts/vex-portability.sh: the block (markdown + JSON) over an authoritative record
      and each other consumer's; agree / DIVERGENCE (reported) / absent; tests first
- [x] 4. scripts/consumer-smoke.sh: the README snippet extracted and run verbatim against one
      digest, the authoritative assertion, the --vex oci regression comparison, the other
      consumers into the block; tests with stubbed cosign/trivy/grype/jq
- [x] 5. render-verification.sh: the consumer scan steps rendered from the list; README and
      manual re-rendered; drift check
- [x] 6. build.yml (PR gate) and rescan.yml (supported set, daily smoke) steps; rehearsed
      verbatim locally where the registry allows; actionlint, lint-workflow-policy
- [x] 7. Docs: manual's consumer section and Reading job summaries; CONVENTIONS scanning
      section; design Decision 10 as-built; tasks tick; em-dash sweep

**Review (2026-09-08).** Four scripts, each with its suite written first
(policy reader queries; adapter; block; smoke test) and shellcheck clean.
Measured before writing: grype 0.118.0 builds product identifiers of exactly
the compiler's shape (`pkg:oci/<name>@sha256:<manifest>`, qualifier-free
first) and its JSON carries `ignoredMatches[].appliedIgnoreRules[].vex-status`;
trivy and syft spell one package two ways, hence the canonical key. The smoke
test's first run found the published recipe wrong (`a || b | jq > file`
grouping), fixed in the renderer. Both rescan step blocks were extracted
verbatim, shellchecked and run against the real reports (14 supported
manifests), the real enumeration and a compiled grafana document, with the
network-facing tools stubbed; the whole validate chain passes locally. Not
measured here: grype's real matching (its database is unreachable), which
the first rescan after the merge measures; the owner dispatches one.

## Task 13.5: manual-controls register (2026-09-08)

Branch: `task-13.5-manual-controls-register`. Goal: every human step in the
catalogue's operation is a row of one register in docs/CONVENTIONS.md
(step, class, reason, fork switch; class binary: deliberate or pending
automation; a review date is a column, not a class), and the manual's
operator steps cite their rows (Req 9.14).

- [x] 1. Inventory every human step across the manual, CONVENTIONS, SECURITY.md, the
      runbooks, the workflows and the reviews; decide each class and fork switch
- [x] 2. The register section in CONVENTIONS.md with stable row ids (M1..), review-date
      column, and the retired rows (the three automations F13 named) as history
- [x] 3. The manual's operator steps cite their rows; the revocation runbook and
      SECURITY.md governance cite theirs; the design Decision 10 as-built note; tasks tick
- [x] 4. Em-dash sweep; a lint-free rendering (yamllint untouched); no gate depends on prose

**Review (2026-09-08).** The inventory came from the manual's Part III, the
Renovate PR table, CONVENTIONS, SECURITY.md, the revocation runbook, the
workflows' dispatch paths, ADR 0002 and 0003, and the two reviews: twenty
deliberate rows, two pending automation, every row with a reason and a fork
switch or a stated "none". The class stays binary (review 3.13); review
dates are a column. Two dates are the spec's (terms 2026-11-21, valkey compat
2026-11-24); the cosign one (2026-10-22) is proposed with its reason and is
the owner's to adjust. The manual cites nine rows by id, the runbook one,
SECURITY.md one. Prose only: the drift check and the whole validate chain
pass locally; no em dashes in new text (four pre-existing table rows kept
theirs where only an id was appended).

## Task 13.6: LOG-anchor lint, F13's mechanical link (2026-09-08)

Branch: `task-13.6-log-anchor-lint`. Goal: every exception's `ref:` and every
VEX source statement's log citation resolves to a heading in
`triage/LOG.md`, both directions (a decision without a citation fails too),
one reader of the headings, unit-tested, in validate (Req 9.18).

- [x] 1. Tests first: scripts/lint-log-anchors_test.sh (slug refs, dated citations, a
      missing heading, a decision without a citation, both halves, the refs half alone)
- [x] 2. scripts/lint-log-anchors.sh [refs|statements|all] [root]: the resolver (GitHub's
      heading slug; a day heading for `LOG.md <date>`); lint-accepted-risk.sh calls the
      refs half; validate runs the statements half; every-suite check
- [x] 3. triage/README.md and CONVENTIONS state the two citation forms; design Decision 10
      as-built; tasks tick; em-dash sweep

**Review (2026-09-08).** Measured first: twelve exception refs, all
`LOG.md#<slug>` against colon-form headings, and six statement citations,
all `see triage/LOG.md <date>`, so the lint accepts both forms rather than
rewriting attested statements (a notes rewrite would re-attest every grafana
digest for no decision). GitHub's slug rule was checked against the manual's
own example (`transfer--stdlib`, double dash from a dash between spaces);
the markdown API strips anchors, so the rule is the documented one. Eight
fixture cases plus one in the accepted-risk suite, written before the
script; the two lints, shellcheck, actionlint and the every-suite check
pass; day one resolves 12 and 6. Cluster D's parent is ticked with 13.6.

## Task 14.1: the policy file declares the registry namespace and the active set (2026-09-08)

Branch: `task-14.1-active-set`. Goal: the two instance values a fork changes
first, the registry namespace and the set of definitions it activates, are
declared in `catalogue-policy.yaml` and read from there by every consumer
(Req 1.13, 2.2, 2.7, 2.21, 2.23, 7.7); the registry gate policy joins the
rendered, drift-checked artifacts.

- [x] 1. Tests first: definition-lib_test.sh cases for `active_definitions` (the list,
      a missing entry directory refused by name, a duplicate, an empty or missing
      section); render-verification_test.sh cases for policies/restrict-registries.yaml
      (rendered from `registry:`, no hardcode, drift named by --check)
- [x] 2. catalogue-policy.yaml: `active_set:` (all seven; comment: what it drives, what
      deactivation means, fork switch); the registry comment records the placement
- [x] 3. definition-lib.sh: `active_definitions <root>`, the one reader (python3 + PyYAML,
      the check-visibility precedent), refusing malformed input by name
- [x] 4. render-verification.sh renders policies/restrict-registries.yaml from `registry:`
      (second Kyverno artifact; validate's --check step covers it unchanged)
- [x] 5. Literals out of the workflows: rescan.yml's dead REGISTRY env and header comment;
      build.yml's local-registry path derives from the declared namespace; comments
- [x] 6. Docs: CONVENTIONS policy gate paragraph, manual (chart gate, Policies, the
      add-a-definition walkthrough gains "activate it"); design Decision 11 as-built;
      tasks tick; every-suite check, shellcheck, actionlint, yamllint, kyverno test,
      em-dash sweep

**Review (2026-09-08).** Measured before writing: the namespace was already
read from the policy file by build.yml's meta step and check-visibility.sh,
so the registry half of the task was the hand-written registry policy
(namespace in three places), rescan.yml's unused `REGISTRY` env, and the PR
gate's local-registry path. The active set went in as a top-level list with
one reader that refuses rather than returns empty (an empty matrix is
indistinguishable from nothing to do, the review 1.10 shape), with the
missing-directory check at the reader so 14.2's lint just calls it.
Thirteen new reader cases and eight render cases were red before the code
and green after; the reader returns all seven on the real tree; the rendered
policy differs from the hand-written one only in its header and description
(the em dash went); kyverno's 13 fixture results, every validate step in
CI's order, shellcheck and actionlint (findings identical to main's) pass
locally. Nothing reads the set until 14.2, said so in the policy comment,
the manual and the design as-built note.

## Task 14.2: every matrix and the tracking scope derive from the active set (2026-09-08)

Branch: `task-14.2-active-set-matrices`. Goal: the active set declared in 14.1
is the sole source of candidates for the build matrix, the e2e matrix and the
tracking scope (Req 1.14 to 1.16, 1.18, 1.19, 2.1, 2.14, 3.2, 3.10, 3.11);
the chart gate keeps looping every chart directory (review 4.4).

- [x] 1. Tests first: definition-lib_test.sh (`source_repository`, `chart_deploys`,
      `active_components`); lint-active-set_test.sh (1.18 split group, 1.19 via the
      reader, deploys coherence, 1.16 changed inactive definition and chart);
      render-tracking_test.sh (block rendered, empty when all active, drift named);
      check-authenticity_test.sh (an inactive definition is not re-verified);
      managers.test.mjs (the rendered block, an inactive fixture)
- [x] 2. `deploys:` in every chart's chart.yaml (hardened-app gains one; schema: deploys
      required, upstream optional for the owned chart); validate's yamale covers all four
- [x] 3. definition-lib.sh readers; scripts/lint-active-set.sh; scripts/render-tracking.sh
      rendering renovate.json5's delimited ignorePaths block; validate steps (lint with
      the PR diff, render --check, both suites in the every-suite check)
- [x] 4. build.yml changes job: every branch filters through active_definitions (schedule,
      dispatch refusal, PR, push, canary); e2e.yml affected job: components through
      deploys; check-authenticity.sh scoped to active definitions
- [x] 5. Rehearse the two workflow scripts locally (schedule, dispatch, PR, push shapes);
      renovate-config-validator --strict on the rendered file; every-suite check
- [x] 6. Docs (CONVENTIONS tracking scope + PR rule, manual renovate/e2e/build passages);
      design Decision 11 as-built; tasks tick; em-dash sweep; actionlint, shellcheck

**Review (2026-09-08).** Tests first in five suites (three new reader cases,
twelve lint cases, sixteen render cases, five authenticity cases, nine
Renovate cases), red before the code and green after. Measured rather than
assumed: Renovate 41.173.1's own file filter drops every file under the
rendered globs and its strict validator accepts both block shapes, so
`ignorePaths` alone carries the scope. The Req 1.18 groups are derived from
the definitions (published repository, source repository), never listed by
hand. Both matrix scripts were rehearsed locally in every event shape,
including a deactivated definition, an inactive canary and a malformed set
(the reader's refusal fails the job by name). One trap caught by the lints
before commit: a colon in a validate step name made the whole workflow
unparseable, the exact failure the workflow-policy lint exists for. The
deploys list on the valkey chart names both valkey definitions on purpose;
14.3's probe lint will lean on that. Every validate step in CI's order,
kyverno, actionlint (findings identical to main's), shellcheck pass; no em
dashes in added lines.

## Task 14.3: probes declared per definition (2026-09-09)

Branch: `task-14.3-probes`. Goal: each chart declares the functional probe
the e2e suite runs when its pods are Ready (`probe:` in chart.yaml), the
suite resolves it through a registry keyed by probe name, and validate
fails an active definition no chart-with-a-probe deploys (Req 5.5, 5.8),
never forcing a placeholder.

- [x] 1. Tests first: lint-probes_test.sh (covered, uncovered active definition named,
      inactive uncovered passes, a chart without a probe, a malformed set); Go: ParseDeclaration
      cases in install_test.go, TestProbeDeclarations (every declared probe registered,
      every registration declared) in the e2e package
- [x] 2. `probe:` in all four chart.yaml files (certificate-issuance, http-health, http-200,
      set-get); schema `probe: str(required=False)`
- [x] 3. Go: install.ParseDeclaration (deploys + probe); e2e registry `probes` keyed by
      name, probeFor(component) from the declaration; componentSpecs lose the hardcoded
      Probe; assertHealthy resolves it; validate's go test step adds ./e2e/
- [x] 4. scripts/lint-probes.sh (Req 5.8) in validate; every-suite check
- [x] 5. Docs (manual e2e assertions, add-a-definition step, Adapt a chart), CONVENTIONS
      chart section; design as-built; tasks tick; gofmt, shellcheck, actionlint, em-dash sweep;
      Go compiles in CI (proxy unreachable locally today)

**Review (2026-09-09).** The registry ended up keyed by probe name, not by
component, because that is what lets a YAML-only lint answer Req 5.8 and a
Go unit test bind the names to registrations both ways; the component side
of the mapping is the `deploys:` plus `probe:` pair in chart.yaml. Nine lint
cases red before the script and green after; the lint on the real tree
named all seven definitions until the four declarations landed, then
reported four registrations covering seven. Go could not compile here today
(the proxy's address left the firewall snapshot and sigs.k8s.io is not
reachable for a direct fetch), so the Go changes are gofmt-checked and
reviewed line by line, with CI's go job and the four-component e2e run as
the verdict. Every validate step in CI's order passes locally; the local
runner now sets the push-shape env so the active-set step stops reading as
a failure.

## Task 14.4: builder contract documented; truth pass (2026-09-09)

Branch: `task-14.4-builder-contract`. Goal: the docs say what the pipeline
now does. concepts.md states the per-archetype builder contract (Req 1.17)
and the trust-boundary table links to it; CONVENTIONS and the manual
describe the active set, the reference set and deactivation; the retired
criteria the docs still cite are re-anchored with the retirement stated;
the namespace literals a fork edits by hand become register rows (Req 9.14).

- [x] 1. concepts.md: "The builder contract per archetype" section (input, outputs,
      what differs per archetype, what consumes only outputs); table row links to it
- [x] 2. CONVENTIONS: Req 8.2 parenthetical re-anchored; the second-opinion sentence
      states 6.6's retirement; Req 1.5 citations re-anchored to 7.2; new section on the
      active set, reference set and deactivation; register rows M21, M22
- [x] 3. Manual: retired citations re-anchored (8.1, 8.2, 2.6, 1.5, 6.6, 6.2); a
      "Deactivate a definition" how-to; glossary entries; the 14.2 present tense
- [x] 4. Truth pass on comments: chart.schema.yaml, catalogue-policy.yaml; design
      as-built; tasks tick (14.4 and parent 14); em-dash sweep; validate chain locally

**Review (2026-09-09).** Documentation only, so the verification is a
reading one: every claim in the contract section was checked against
build.yml (the SBOM pair per platform manifest, the CycloneDX pull checksum
the comparator reads, provenance as attestation manifests at the push) and
against the definitions (valkey builds from toolchain packages, not a `-dev`
image, so the table says so). The retired numbers were mapped from the
primitives review's own dispositions (1.5 into 7.2, 2.6 into 2.8, 6.2 into
2.22, 6.6 removed for 9.11 to 9.13, group 8 removed), each citation now
naming its successor and the retirement date. Internal anchors checked by
script; the validate chain passes; the two em-dash hits in the diff are
pre-existing phrases carried through. Task group 14 is complete; 12.1 is
the last unticked task.

## Requirements versus implementation review (2026-09-09)

Branch: `review-2026-09-09`. Every live criterion (147) and the spec and
document layer above them compared with the working tree at `0b31759`;
`.specs/dhc-catalogue-mvp/reviews/2026-09-09-requirements-vs-implementation-review.md`.

- [x] Eight readings, one per group and one for tasks, design and documents;
      every PARTIAL or NOT HELD verdict re-checked by hand before it entered the document
- [x] Live state measured: first post-fix nightly discarded all seven; scheduled rescan green
- [x] Verdict, group tables, findings, the deferred ledger (the dashboard question),
      eight proposed dispositions, confidence notes; no em dashes

**Review.** 114 held, 26 partial, 3 not held (process criteria), 4 owner-side.
The themes: rescan assertions that depend on step order, three unverified
reads, four silent-success shapes, holes in the pin surface, nine criteria
whose text lags the code, documentation describing an earlier catalogue,
and declared values nothing reads. Each disposition is one PR the owner
picks or declines.

## D1: the rescan's assertions run regardless of earlier steps (2026-09-09)

Branch: `d1-rescan-always`. Review disposition D1 (theme 1 of the
2026-09-09 review; task 15.1). Goal: no daily assertion or the status issue
is suspended by an unrelated earlier failure.

- [x] 1. Spec first: design Decision 6's as-built correction (three assertion steps, the
      always() rule); task group 15 with 15.1 ticked
- [x] 2. Tests first: scripts/lint-rescan-steps_test.sh (six cases); the lint names each
      step after the scan without always(); it named 20 on the real workflow before the edit
- [x] 3. rescan.yml: ids on every producer, `if: always() && steps.<producer>.outcome ==
      'success'` on every step after the scan, refusals by name on missing inputs, the four
      invariants independent, the header comment true; validate runs the lint and its suite
- [x] 4. Rehearsal: an evaluator over the workflow's own conditions for five scenarios; the
      manual and register M18 describe the new behaviour; validate chain, actionlint,
      shellcheck; em-dash sweep

**Review (2026-09-09).** Actions cannot run here, so the rehearsal is an
evaluator over the file's conditions with GitHub's step semantics: an
authenticity mismatch skips nothing; a re-attestation failure withholds only
the status chain; a KEV outage withholds the tiers, the issue set and the
status by name; an enumeration failure skips everything data-dependent and
still runs the authenticity check, the expiries and the governance half of
the posture step. The live proof is the next rescan. yamllint's warning
count rose with the new long error lines (warnings, the file's style); no
new actionlint class.

## D2: verified reads (2026-09-09)

Branch: `d2-verified-reads`. Review disposition D2 (theme 2; task 15.2).
Goal: no read of the day's evidence trusts what a sibling verifies.

- [x] 1. Tests first: the comparator suite's cosign stub verifies issuer and identity;
      cases for a non-admitted signer, no admitted role, the verified invocation
- [x] 2. package-set-diff.sh reads the published CycloneDX through cosign verify-attestation
      against the policy file's cyclonedx roles (PACKAGE_SET_DIFF_ROOT seam)
- [x] 3. rescan.yml: the lifecycle's application moves after re-attestation and withholds
      every action, by the digests' names, on a day any digest's reports failed to attest;
      rescan-status gets --vex-reports and its guard; comments and summary line true
- [x] 4. Spec: Decisions 6 and 7 as-built corrections; task 15.2; the manual's issue
      paragraph; step-graph rehearsal; validate chain; em-dash sweep

**Review (2026-09-09).** The 6.54 question was decided by ordering rather
than by amending the criterion: closes and reopens now happen after the
reports they rest on are attested, and are withheld when that failed, so
the text holds literally; a skipped digest needs no rule because the tool
already treats a missing report as unscanned. The one cost, a day's lag in
the compiler's open-issue map, is written where it happens. The withholding
expression was rehearsed on a fixture record; the comparator's new read is
tested against a stub that behaves like Fulcio verification; Go was not
touched.

## D3: silence reads as failure (2026-09-09)

Branch: `d3-silence-fails`. Review disposition D3 (theme 3; task 15.3).
Goal: nothing happening never reads as all clear.

- [x] 1. Tests first: release-policy_test.sh (22 cases: exact tokens, YAML 1.1 spellings
      refused, missing keys, platforms, cron, check); two lint-workflow-policy cases
- [x] 2. scripts/release-policy.sh, the one reader of the release section; build.yml's meta
      step and check-visibility.sh read through it; validate runs `check`
- [x] 3. build.yml: the fail-closed gate names findings per manifest; the govulncheck step
      fails by name on a failed install or empty output, execute-bit filter dropped
- [x] 4. lint-workflow-policy.sh: a declared cron absent from its workflow fails; .yaml read
- [x] 5. Rehearsals with stubs (meta step, gate, govulncheck's three branches); design
      Decision 6 as-built; task 15.3; manual; validate chain; actionlint identical to main

**Review (2026-09-09).** The boolean switches are checked against the
file's own text rather than a parsed value, because the two YAML readers in
play disagree on `yes`; that is the whole point of the refusal. The
govulncheck step stays non-gating: the build continues, the step is red and
annotated, and the summary can no longer say "no Go binaries" about an
image the tool never read. The canary build on this PR runs the step live.

## D4: the pin surface (2026-09-09)

Branch: `d4-pin-surface`. Review disposition D4 (theme 4; task 15.4).
Goal: every pin the conventions claim is pinned and tracked, is.

- [x] 1. cosign: sha256 from the release's checksums file, second source the keyless
      signature verified by hand (openssl; Fulcio chain from sigstore/root-signing;
      release identity in the SAN); install-tool.sh case and tests; both workflows install
      through it; a real install verified locally (v2.6.0)
- [x] 2. renovate.json5: github-actions and gomod on (gomodTidy), Actions never automerged,
      a probe-image manager; strict validator green
- [x] 3. e2e.yml: the probe image is the curl project's GHCR multi-arch image pinned by
      digest, pulled by digest and loaded by tag (pull, tag and a run as 65532 rehearsed);
      the Go comment corrected
- [x] 4. managers.test.mjs: eighth tool pin, the probe manager, the built-ins and their
      rules, and a marker sweep (named cosign on main's tree)
- [x] 5. CONVENTIONS' 7.5 paragraph true; P1 closed into the automated paragraph; M5
      updated; the manual's tables; design as-built; task 15.4; validate chain

**Review (2026-09-09).** Docker Hub's address had left the firewall
snapshot, so the probe image's digest could not be resolved there; the
curl project's own image on GHCR resolved, runs curl 8.11.1 as UID 65532
and spares the runner Docker Hub's anonymous rate limit, so the pin moved
registries rather than waiting. cosign's Rekor entry is unreachable from
here, so the second source is the offline half of keyless verification:
the signature against the certificate's key and the certificate against
Fulcio's chain, identity read from the SAN. Go was not compiled here; the
comment change in the suite is prose.
