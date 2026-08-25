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
- [ ] 3. Spec amendments per accepted point: EARS criteria in
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
- [ ] 4. Only then: implementation PRs via /spec-implement, TDD where code

## Review

(to fill when done)
