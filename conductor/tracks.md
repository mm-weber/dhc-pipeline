# Track registry

| Symbol | Status |
| --- | --- |
| `[ ]` | pending |
| `[~]` | in progress |
| `[x]` | completed |

## Active tracks

<!-- No active track; the next drill is 16.8 (the KEV drill input), then 16.3 -->


## Completed tracks

### [x] drill-definition_20261017: The drill definition and its first findings (task 16.2)

**Description:** drill-app, the owner's purposely vulnerable copy of hardened-app, joins the catalogue as pull request 1 of the onboarding flow with the catalogue's first declared none proof; the scan gate names its two findings, the owner decides them one at a time, main publishes the first digest, and the evidence lands in the ledger and the LOG (spec task 16.2; Req 1.13, 1.14, 5.9, 6.1, 6.3, 6.13, 7.11, 9.11). The first track of the live-drill program; one track per drill from here.
**Priority:** high (the first live drill; unblocked by the proof-kinds track on 2026-10-17)
**Completed:** 2026-10-19 (#286 merged 2026-10-18 as 1b941ea with the definition and the two decisions; the evidence pull request closes the track)
**Folder:** [./tracks/drill-definition_20261017/](./tracks/drill-definition_20261017/)

---

### [x] proof-kinds_20261015: Proof kinds per definition

**Description:** The functional proof declared per definition in the policy file; the chart probe stays the default; a `none` with a reason is admitted, reported by name on every run and refused when malformed or when a chart deploys the definition (spec task group 17: 17.2 reader, 17.3 lint, 17.4 docs; the review-by date dropped 2026-10-16).
**Priority:** high (unblocks drill 16.2)
**Completed:** 2026-10-17 (#273 reader, #281 lint, #282 docs merged by squash; spec #271, context #272)
**Folder:** [./tracks/proof-kinds_20261015/](./tracks/proof-kinds_20261015/)

---

## Archived tracks

| Track ID | Type | Reason | Archived | Folder |
| --- | --- | --- | --- | --- |
