# Final cleanup revision ledger (PR #104), started 2026-08-25

**Purpose.** One place holding the state of the final cleanup's revision:
every finding from the independent review
(`2026-08-25-final-cleanup-independent-review.md`, numbered 4.1 to 4.11)
with its disposition. No finding needed a new owner decision; every fix
lands inside Decision 11's decided semantics with the reviewer's
validator-checked texts. Two shaping calls taken inside that scope, both
flagged to the owner in the session report: the render-and-policy chart
gate keeps checking every chart directory (validation, so the reference
tree cannot rot; the active set scopes the build, test and tracking
planes), and probes key by chart-backed component with the
definition-to-component mapping declared as a `deploys:` list in each
chart's chart.yaml.

## Ledger

| # | Finding (short) | Disposition | Where encoded |
|---|---|---|---|
| 4.1 | 2.14 rebuilds every definition and 2.16 then publishes the first drift, against 1.14/1.15; task 9.2 still lists every definition | **decided 2026-08-25**: 2.14 scoped to active definitions; task 9.2's two phrases narrowed | Req 2.14; task 9.2 |
| 4.2 | Amended 4.1's WHERE clause predicates on a declaration no artifact makes; never-modify-upstream binds nothing | **decided 2026-08-25**: reviewer's anchor taken: chart adaptations deploying an active definition's images | Req 4.1 |
| 4.3 | 3.2/3.3/3.11 mandate bump PRs 1.16 fails; monorepo grouping and variant parity wedge active siblings; deactivated findings lose their fix lane silently | **decided 2026-08-25**: 3.2 and 3.11 scoped to active definitions; 1.16 extended to chart adaptations deploying no active definition; coherence criterion 1.18 (active set closed under byte-equal pairs and 3.3 groups); fix-lane consequence stated in 14.4's deactivation semantics | Req 3.2, 3.11, 1.16, 1.18; tasks 14.2, 14.4 |
| 4.4 | 1.14's "solely" satisfiable by no standing matrix; chart.yml has no matrix and 14.2 silently reversed a recorded every-chart decision | **decided 2026-08-25**: 1.14 reworded to the membership form over build and test matrices plus tracking; the render-and-policy gate deliberately keeps every chart directory (recorded in 14.2, so task 5.5's decision is not silently reversed) | Req 1.14; task 14.2 |
| 4.5 | Non-bump merges still publish inactive definitions through the 2.1 chain; 1.15's verb loose against Req 2's vocabulary (frozen strata loophole) | **decided 2026-08-25**: 2.1 scoped to affected active definitions; 1.15 tightened to push no new digest and apply no new tag | Req 2.1, 1.15 |
| 4.6 | 3.10's daily authenticity check keeps failing on deactivated upstreams with every exit forbidden | **decided 2026-08-25**: 3.10 scoped to active definitions; tag-driven planes keep the knowledge | Req 3.10 |
| 4.7 | Unparameterized registry readers: restrict-registries.yaml unrendered, registry outside 7.8's rendering source section, renovate.json5 literals unlisted | **decided 2026-08-25**: restrict-registries.yaml joins the rendered drift-checked artifacts; `registry:` moves inside the verification section so 7.8's source claim holds; renovate.json5 namespace literals become fork-switch register rows | task 14.1; task 13.5 note in 14.4 |
| 4.8 | Per-definition probes vs a component-keyed suite: three definitions unprobeable standalone; no definition-to-component mapping; reference set names six of seven | **decided 2026-08-25**: reviewer's shared-probe 5.5 taken; mapping declared as `deploys:` in each chart's chart.yaml; Req 1.1 names valkey's runtime and compat images | Req 5.5, 1.1; task 14.3 |
| 4.9 | "Active definition" has no defined antecedent | **decided 2026-08-25**: reviewer's 1.13 rewording defines it in passing | Req 1.13 |
| 4.10 | Probe-lint failure row cites a criterion requiring no validation; nothing validates the active set's entries | **decided 2026-08-25**: probe lint as Req 5.8, dangling active-set entry as Req 1.19; rows re-anchored | Req 5.8, 1.19; design rows |
| 4.11 | Coverage gaps (amended 2.x/4.1 own no task), tasks 9.1/9.4 re-hardcode the namespace, three prose surfaces keep the four-component frame, addendum divergence unrecorded | **decided 2026-08-25**: coverage rows and 14.1/14.2 requirements lists extended; 9.1/9.4 gain policy-file-namespace clauses; Req 1 Objective, design Goals and the Integration Tests bullet reworded now; the rescan-and-badges divergence recorded in the encoded note as intended | tasks; requirements Objective; design Goals; critique note |

## Working notes

- 2026-08-25: ledger created on receipt of the review; dispositions taken
  in the same sitting (all corrections inside Decision 11's semantics)
  and encoded in revision commit 1. The review measured the
  implementability claims that survive: matrices from a policy file via
  the job-output plus fromJSON pattern already live in build.yml and
  e2e.yml; renovate 41.173.1 carries ignorePaths, matchFileNames plus
  enabled, and ignoreDeps; renovate.json5 is JSON5 with load-bearing
  comments, so the rendered ignore list uses a delimited block, the task
  9.8 fenced-snippet shape. Validator expected at 164 valid after the
  revision: 161 plus the three new criteria (1.18, 1.19, 5.8), amendments
  keeping their counts.
