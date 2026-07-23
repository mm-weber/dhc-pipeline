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

## The daily rescan (Req 6.2, 6.3)

The scan gate only sees a CVE at PR time; new advisories land against already-
published images every day. `.github/workflows/rescan.yml` runs on a daily cron
(and on demand) and closes that gap:

1. **Trivy** re-scans every published `ghcr.io/mm-weber/dhc` image for
   `HIGH,CRITICAL`, honouring `triage/vex/` — so already-triaged CVEs stay quiet.
2. Findings **not already tracked** by an open `cve` issue are enriched with
   **EPSS** (FIRST.org) and **CISA KEV** status.
3. One **GitHub issue per CVE** is filed (Req 6.3) — severity, EPSS, KEV, and
   affected images — carrying a `<!-- rescan-cve: CVE-… -->` marker so the next
   run recognises it and doesn't duplicate.
4. A **Grype** second opinion runs on each CRITICAL being filed (Req 6.6).

The join / dedup / enrichment / templating is a small, unit-tested Go tool,
**`triage/rescan/`** (`cmd/rescan-report`): a pure `BuildIssues(inputs) → issues`
so the correctness of an unattended, issue-opening cron is covered by tests, not
trust. The workflow is the I/O around it (scan, fetch feeds, list/create issues).
Scan and feed failures soft-fail (skip + warn) so a transient outage never turns
the cron permanently red.

Each filed issue is a triage decision waiting to happen — resolved exactly as a
red gate is: an OpenVEX statement under `vex/` (+ a `LOG.md` entry) or a fix-bump
PR.

## `LOG.md`

Dated, human-readable decisions: *finding → EPSS / KEV → outcome → link*. Created
with the first real triage decision (task 7.3).
