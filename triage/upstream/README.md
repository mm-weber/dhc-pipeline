# `upstream/`: drafts of outward-facing reports

Issues we intend to file **on someone else's tracker**, drafted here first and
reviewed before anything is posted.

Nothing in this directory has been sent. A draft becomes a filed issue only by a
deliberate act, and the entry in `../LOG.md` records the resulting issue number.

## Why drafts live in the repo

- **A transfer needs a tracker to point at.** `treatment: transfer` in
  `../accepted-risk/<image>.yaml` requires an `issue:`. A transfer is an
  acceptance with an external owner, so the thing we are waiting on has to exist
  and be nameable. The draft is what turns "upstream should fix this" into a
  number.
- **Outward-facing claims get reviewed like code.** A report filed on a public
  tracker carries our name and our measurements. Drafting in the repo means the
  evidence is diffable, the numbers are re-runnable, and a wrong claim is caught
  before it is published rather than retracted afterwards.
- **The reasoning survives the issue.** Upstream trackers get closed, migrated
  and mass-triaged. What we measured, and when, stays here.

## Conventions

- **Filename**: `YYYY-MM-DD-<target-repo>-<slug>.md`, dated when drafted.
- **Every number is measured, not inferred**, and the draft says how it was
  obtained. Commands that produced a table go in [`checks/`](checks/) so anyone
  can re-run them.
- **Name the artifact each measurement was made against.** Where a number comes
  from a different build than the one the report is about, say so in the draft
  rather than letting the surrounding text imply otherwise.
- **Report the mechanism, not the symptom.** "Your image has CVEs" is a scan
  result. "This artifact is built from a toolchain that predates the fix, and
  here is the line that selects it" is a report someone can act on.
- **Separate what we measured from what we inferred.** Upstream knows their
  build better than we do, and a draft that overstates gets discounted whole.
- **One target repo per draft.** If the fix lands in two places, that is two
  drafts, because it is two asks.
- **No em dashes.**

## Drafts

| Draft | Target | Status |
|---|---|---|
| [2026-07-26, `/oss/release/` tarballs overwritten](2026-07-26-grafana-oss-release-alias-overwritten.md) | `grafana/grafana` | not filed |
| [2026-08-04, zipkin datasource: unreleased Go bump](2026-08-04-grafana-zipkin-datasource-unreleased-go-bump.md) | `grafana/grafana-zipkin-datasource` | draft, under review |
| [2026-08-04, elasticsearch datasource: `go.mod` pins 1.26.3](2026-08-04-grafana-elasticsearch-datasource-go-mod-pins-1263.md) | `grafana/grafana-elasticsearch-datasource` | **filed** as [#410](https://github.com/grafana/grafana-elasticsearch-datasource/issues/410) |
| [2026-08-23, `--vex oci` picks one of several OpenVEX attestations at random](2026-08-23-trivy-vex-oci-multiple-attestations.md) | `aquasecurity/trivy` | draft, under review (ADR 0004) |
