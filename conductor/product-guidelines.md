# Product guidelines

## Voice and register

Two registers, never mixed:

- **In conversation with the owner:** plain words, one everyday example per concept (the SBOM is the ingredients list, VEX is the honest note on a known problem, the active set is the on/off switch list). Criterion numbers and paths appear only as small references.
- **In repository artifacts:** the formal register. Requirements in EARS with uppercase keywords (`THE ... SHALL`, `WHEN`, `WHILE`, `WHERE`, `IF ... THEN`); design decisions with context, options and decision; commit messages that name the criterion and the task.

No em-dashes anywhere, in prose, comments, commit messages or docs. Use commas, periods, colons or parentheses.

## Terminology

| Term | Meaning |
| --- | --- |
| definition | one `image/<name>/image.yaml` in native DHI syntax |
| active set | the list in `catalogue-policy.yaml` naming the definitions the catalogue builds, tracks, tests and publishes |
| chart adaptation | an upstream chart plus a values overlay under `chart/<name>/`, or the one owned chart |
| probe | the functional check the e2e suite runs once a chart's pods are Ready, declared in the chart's `chart.yaml` |
| proof kind | how an active definition is proved functional: `chart` (the probe), `none` (declared, dated), later `smoke` |
| exception | an accepted-risk record with an expiry, never a VEX `not_affected` |
| supported set | the digests each definition's current tags reference |
| drill | a deliberate, recorded exercise of a mechanism on the real catalogue (task group 16) |
| fork switch | a value in the policy file a fork changes instead of editing code |

## Words we avoid

- "placeholder": there is no placeholder shape for anything the catalogue checks
- "temporary fix", "should work": every change has its test and its named check
- "exempt": a declared `none` proof is a dated record with a reason, not an exemption

## Error-message shape

Every check fails by name, reports every failure (not just the first), and cites its criterion:

```
::error file=<path>::<check>: <what is wrong>; <the way out> (Req <n.m>)
```

Exit 1 is a violation (the input was read and found wrong). Exit 2 is a refusal (the input could not be read as what it claims to be, or a tool is missing); a refusal never reads as "nothing to do". A summary line on success says what was checked and how many.

## Documentation style

- `docs/user-manual.md` is the operator's reference; `docs/CONVENTIONS.md` is the rulebook the lints enforce; `docs/concepts.md` explains why.
- A doc states what is built, with the date, and never claims a mechanism that only exists in a plan.
