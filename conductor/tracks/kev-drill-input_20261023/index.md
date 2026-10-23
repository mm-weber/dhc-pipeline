# Track: The KEV drill input, a feed outage fails closed in both arms, live

- [Specification](./spec.md): ten EARS requirements mapped to Req 6.59, 6.60, 7.7, 7.10 and 7.11; the `drill` input as a declared value substituted for one run, never a different code path
- [Plan](./plan.md): three phases, three pull requests (the spec amendment and the track; the input, the declarations, the lint and the reader by TDD; the drill and its evidence) and one drill branch that never merges
- [Metadata](./metadata.json)

Spec source: `.specs/dhc-catalogue-mvp/tasks.md` task 16.8; Req 6.59, 6.60, 7.7, 7.10, 7.11; design Decision 13; the ledger's rows 6.59 and 6.60.
