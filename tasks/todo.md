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
- [ ] 6. docs: user manual (rescan row, verification), tasks.md tick; SC2154 sweep, actionlint,
      yamllint, every suite; first run dispatched after merge is the measurement, recorded in LOG
