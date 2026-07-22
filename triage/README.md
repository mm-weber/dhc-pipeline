# triage/ — CVE triage lane (Req 6)

Scan findings become **recorded, portable decisions** here, so vulnerability
handling is auditable instead of anecdotal. Two mechanisms feed it: the PR scan
gate (below) and the daily rescan cron (task 7.2).

## `vex/` — OpenVEX statements

`vex/*.openvex.json` are [OpenVEX](https://github.com/openvex) documents authored
with `vexctl` (task 7.3) and attached to the affected images as attestations via
`cosign attest`. Each says a specific CVE is (typically) `not_affected` for a
specific product, with a justification — the portable, machine-readable form of
"we looked at this and here's why it doesn't apply."

The directory is consumed by the **Trivy scan gate**. It starts empty: nothing
is excused until a triage decision is made.

## The scan gate (Req 6.1, 6.6)

Lives in `.github/workflows/build.yml`, on the pull-request path. For every image
definition a PR builds, after the image is built and loaded into the docker
daemon:

1. **Trivy** scans it for `HIGH,CRITICAL`, consuming `triage/vex/` via `--vex` so
   any finding covered by an OpenVEX statement is suppressed.
2. **Grype** runs as an independent **second opinion** — different DB and matcher
   — whenever a `CRITICAL` remains after VEX (Req 6.6).
3. The gate **fails the PR** if any `HIGH` or `CRITICAL` survives VEX suppression
   (Req 6.1). Trivy and Grype reports are attached as workflow artifacts, and the
   counts are written to the job summary.

Clearing a red gate means making a triage decision, not silencing the scanner:

- **not-affected / won't-fix** → author an OpenVEX statement under `vex/`
  (task 7.3) and record it in `LOG.md`; the next scan suppresses it.
- **fix exists** → a version-bump or rebuild PR (Renovate usually opens it).

## `LOG.md`

Dated, human-readable decisions: *finding → EPSS / KEV → outcome → link*. Created
with the first real triage decision (task 7.3).
