# `accepted-risk/` — time-boxed exceptions (Req 6.7–6.12)

One `<image>.yaml` per image definition, in Trivy's `.trivyignore.yaml` schema
plus the fields that make an entry reviewable. Consumed by `build.yml` and
`rescan.yml` as `--ignorefile`; enforced by `scripts/lint-accepted-risk.sh`.

**Starts empty, and that is the correct default** — nothing is accepted until
someone decides to accept it, names themselves, and puts a date on it.

Before adding an entry here, rule out the two stronger treatments: *avoid* (drop
the component from the definition) and *mitigate* (bump past it). The `blocked:`
field exists to record why neither was available.

An exception is published in the image's OpenVEX document as an `affected`
statement, **never** as `not_affected` or `fixed` (Req 6.8, 6.38); it suppresses
nothing. Every entry carries `decided_at`, the clock the policy file's ceilings
run from (`catalogue-policy.yaml` `triage`: 30 days for a CRITICAL, 90 for a
HIGH, 14 for a finding CISA lists as exploited), and `expired_at` within that
ceiling; a lapsed entry publishes as `under_investigation` naming the lapse
(Req 6.41). Exceptions matter over the supported set: a superseded digest keeps
its attested document and holds no issues. Full rationale, schema and authoring
notes: [`../README.md`](../README.md).
