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

## `accepted-risk/` — time-boxed exceptions (Req 6.7–6.12)

`accepted-risk/<image>.yaml` is where a finding that is **real, reachable, and
not fixable by us** goes. It is a native Trivy ignorefile, handed to the same
scan as `--ignorefile`.

It exists because risk has four treatments and VEX can express none of them:

| Treatment | What it means here | Mechanism |
|---|---|---|
| **Avoid** | Don't ship the vulnerable component at all | image definition change — the strongest move, and the one most often skipped |
| **Mitigate** | Patch or bump past it | version-bump PR (Req 6.5), or the frontend's Go bump action |
| **Transfer** | Upstream owns the fix; we wait | `accepted-risk/` with `treatment: transfer` + the issue |
| **Accept** | Real, reachable, shipping anyway | `accepted-risk/` with `treatment: accept` |

`not_affected` is absent from that table on purpose: it is not a treatment. It is
the claim that there was never any risk here to treat.

**The split is by question, and it is the whole point:**

> **VEX answers "does this apply?"** — a claim about the artifact. Evidence-backed,
> attested to the image, no expiry, and a service to whoever runs it.
>
> **`accepted-risk/` answers "what are we doing about it?"** — a decision about our
> exposure. Internal, **never attested** (Req 6.8), and it **expires**.

Publishing the first is useful. Publishing the second would tell every downstream
consumer that a vulnerability does not apply to them because *we* decided to live
with it. Transfer gets no separate file: while waiting on upstream we are still
carrying the risk, so it is an acceptance with an external owner.

### Why the expiry is load-bearing

An acceptance without one is indistinguishable from an unfixed bug. Trivy stops
honouring an entry the moment `expired_at` passes — silently, with nothing logged
— so the finding reappears, the gate goes red, and somebody has to decide again.
**Risk acceptance decays back to un-triaged on its own.** That is why the ceiling
is 90 days (`scripts/lint-accepted-risk.sh`) and why the daily rescan reports
anything within 14 days of lapsing (Req 6.10).

### Authoring an exception

```yaml
# triage/accepted-risk/grafana.yaml
vulnerabilities:
  - id: CVE-2026-33186
    purls: ["pkg:golang/google.golang.org/grpc"]   # versionless — survives rebuilds
    treatment: transfer                            # accept | transfer
    owner: mm-weber                                # who carries this
    issue: 28                                      # required when transfer
    ref: "LOG.md#2026-07-27-grpc"                  # where the reasoning lives
    blocked: "no upstream release pins a fixed grpc, and the pipeline sandbox has
              no egress, so a build-time patch is not available either"
    statement: "transfer: waiting on upstream to move off grpc v1.81.1"
    expired_at: 2026-10-25
```

- **The filename is the scope.** One file per image, so accepting a finding for
  `grafana` never silently covers `cert-manager` — whose exposure to the same
  module is a separate question nobody answered.
- **`blocked:` is the honesty field**: why *avoid* and *mitigate* were
  unavailable. Its presence is machine-enforced, its content is judged at review.
  It is what keeps this file from becoming the path of least resistance.
- **The reasoning stays in `LOG.md`.** This file carries only what the gate and a
  reviewer need.
- **Nowhere else may suppress.** Trivy reads `.trivyignore` from the working
  directory by default; a file by that name anywhere in the repo fails the lint
  (Req 6.12), because that path has no owner, no expiry and no review trail.

## The scan gate (Req 6.1, 6.6)

Lives in `.github/workflows/build.yml`, on the pull-request path. For every image
definition a PR builds, after the image is built and loaded into the docker
daemon:

1. **Trivy** scans it for `HIGH,CRITICAL`, consuming `triage/vex/` via `--vex` and
   `triage/accepted-risk/<image>.yaml` via `--ignorefile`, so a finding covered by
   either is suppressed. `--show-suppressed` keeps both in the report, and the
   summary lists them under **separate headings** — a suppression whose reason is
   "we decided to live with it" must never read as "it does not apply".
2. **Grype** runs as an independent **second opinion** — different DB and matcher
   — whenever a `CRITICAL` remains (Req 6.6).
3. The gate **fails the PR** if any `HIGH` or `CRITICAL` survives suppression
   (Req 6.1). Trivy and Grype reports are attached as workflow artifacts, and the
   counts are written to the job summary.

Clearing a red gate means making a triage decision, not silencing the scanner.
Four ways, in order of strength — the gate's error message names all four:

- **avoid** → drop the vulnerable component from the definition. Nothing to
  suppress afterwards, because nothing vulnerable ships.
- **fix exists** → a version-bump or rebuild PR (Renovate usually opens it).
- **not-affected** → author an OpenVEX statement under `vex/` (task 7.3) and
  record it in `LOG.md`; the next scan suppresses it.
- **real, and none of the above** → a time-boxed entry in `accepted-risk/`, with
  an owner, a reason the stronger treatments were unavailable, and an expiry.

Reaching for the last one before ruling out the first two is the failure mode
this lane is designed to make visible, which is what `blocked:` is for.

## The daily rescan (Req 6.2, 6.3)

The scan gate only sees a CVE at PR time; new advisories land against already-
published images every day. `.github/workflows/rescan.yml` runs on a daily cron
(and on demand) and closes that gap:

1. **Trivy** re-scans every published `ghcr.io/mm-weber/dhc` image for
   `HIGH,CRITICAL`, honouring `triage/vex/` and `triage/accepted-risk/` — so
   already-triaged CVEs stay quiet. Without the second one the cron would refile
   an accepted finding every day and drown the acceptance in noise; the expiry,
   not the silence, is what ends it.
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

The cron also **reports every accepted-risk exception that has expired or expires
within 14 days** (Req 6.10), reusing `scripts/lint-accepted-risk.sh` so there is
one implementation of "expired" and the notice can never disagree with the gate.
Expiry happens with *time*, not with a commit, so the cron is the right place to
raise it — reddening whichever PR happens to run that day would blame the wrong
change.

Each filed issue is a triage decision waiting to happen — resolved exactly as a
red gate is: avoid, fix, an OpenVEX statement under `vex/` (+ a `LOG.md` entry),
or a time-boxed entry in `accepted-risk/`.

## `LOG.md`

Dated, human-readable decisions: *finding → EPSS / KEV → outcome → link*. Created
with the first real triage decision (task 7.3).
