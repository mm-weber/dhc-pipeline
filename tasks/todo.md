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
      amendment sequence A–D in the review's section 6)
- [ ] 3. Spec amendments per accepted point: EARS criteria in
      `requirements.md`, rationale in `design.md`, task entries in `tasks.md`,
      one PR per decision
- [ ] 4. Only then: implementation PRs via /spec-implement, TDD where code

## Review

(to fill when done)
