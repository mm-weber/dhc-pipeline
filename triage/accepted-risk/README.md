# `accepted-risk/` — time-boxed exceptions (Req 6.7–6.12)

One `<image>.yaml` per image definition, in Trivy's `.trivyignore.yaml` schema
plus the fields that make an entry reviewable. Consumed by `build.yml` and
`rescan.yml` as `--ignorefile`; enforced by `scripts/lint-accepted-risk.sh`.

**Starts empty, and that is the correct default** — nothing is accepted until
someone decides to accept it, names themselves, and puts a date on it.

Before adding an entry here, rule out the two stronger treatments: *avoid* (drop
the component from the definition) and *mitigate* (bump past it). The `blocked:`
field exists to record why neither was available.

An exception is **never** a VEX statement (Req 6.8). Full rationale, schema and
authoring notes: [`../README.md`](../README.md).
