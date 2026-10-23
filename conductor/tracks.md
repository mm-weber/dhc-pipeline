# Track registry

| Symbol | Status |
| --- | --- |
| `[ ]` | pending |
| `[~]` | in progress |
| `[x]` | completed |

## Active tracks

### [ ] kev-drill-input_20261023: The KEV drill input, a feed outage fails closed in both arms, live

**Description:** A `drill` input on `rescan.yml`'s dispatch substitutes a declared value for the KEV feed for one run (`kev-outage`: an address under `.invalid` that never resolves; `kev-synthetic`: a feed of this repository naming the drill definition's HIGH, for task 16.3), the policy lint holds the input's allowed values beside the crons and the permissions, and both fail-closed branches run live for the first time: the gate on a drill branch never merged, the rescan on a dispatched run that is red by name and publishes attestations only; the ledger rows 6.59 and 6.60 filled (Req 6.59, 6.60, 7.7, 7.10, 7.11; task 16.8).
**Priority:** high (the next drill of the live program; 16.3 depends on it)
**Folder:** [./tracks/kev-drill-input_20261023/](./tracks/kev-drill-input_20261023/)

---


## Completed tracks

### [x] retire-grafana_20261019: Grafana deactivated, the documented switch exercised live

**Description:** Grafana's line leaves the active set and nothing else changes under its directory or chart: no new build, tag, bump or e2e install, everything published kept with its attestations and daily planes; the switch, never exercised live, flips the ledger's 1.15 and 1.16 rows by nature; the twelve moot exceptions of 2026-09-03 retired with their evidence in the same pull request (Req 1.13 to 1.16, 3.2, 6.7, 6.11, 7.11). The four levels of retiring an image are kept in the spec.
**Priority:** high (the owner's call of 2026-10-19)
**Completed:** 2026-10-20 (#290 merged 2026-10-19 as 04c6eeb, the switch and the twelve exceptions retired; the first inactive day observed in #292 and #295: no grafana job in four builds, the rescan's first non-empty inactive check, run 39417467219; rows 1.15 and 1.16 exercised)
**Folder:** [./tracks/retire-grafana_20261019/](./tracks/retire-grafana_20261019/)

---

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
