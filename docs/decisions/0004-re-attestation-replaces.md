# ADR 0004: Re-attestation replaces; exactly one OpenVEX attestation per digest

Date: 2026-08-23 · Status: **accepted** (spike measured 2026-08-23, CI measured 2026-09-04) · Requirements: Req 2.9, 6.34, 6.37; cluster B of the 2026-08-21 review (F5 ii) · Supersedes one inference in ADR 0003

## Context

Cluster A (PR #97) specified one compiled OpenVEX document per published
digest (ADR 0003) and a compiler whose inputs include the document previously
attested to that digest (Req 6.37). Cluster B's recorded decision, F5 (ii),
has the daily rescan re-attest that document whenever a fresh compile differs
from the attested one, and it was recorded on 2026-08-21 as "attestations
append, OpenVEX's latest-statement-wins rule resolves it, consumers merge with
`vexctl merge`". ADR 0003 then read Trivy's log line `[vex] VEX attestation
found, taking the first one` as "the first attestation wins", which would
have made an appended re-attestation invisible to `trivy --vex oci`. Before
cluster B was drafted, the behaviour was measured directly instead of being
inferred from a log line.

## Spike evidence (devcontainer, 2026-08-23)

Tools: trivy 0.72.0 (database from `ghcr.io/aquasecurity/trivy-db:2`), cosign
v2.6.0 (checksum-verified release binary; the version CI's pinned installer
runs), local registry `ghcr.io/distribution/distribution:3.0.0`, control
image `ghcr.io/mm-weber/dhc/hardened-app:0.1.0-alpine3.23` re-pushed as
`localhost:5000/spike/hardened-app@sha256:8eee1329…` (8 HIGH/CRITICAL
findings at baseline). Two OpenVEX documents: **A** is empty; **B** carries
one `not_affected` statement for `CVE-2026-33818` in `pkg:golang/stdlib`,
product `pkg:oci/hardened-app@sha256:8eee1329…`. With B applied, Trivy
reports 7 findings and 1 suppressed; with A or nothing, 8 and 0. Attestations
were made with a local key and `--tlog-upload=false`; the `.att` manifest's
layer list was read from the registry after each step. The check script
`triage/upstream/checks/trivy-vex-oci-multiple-attestations.sh` re-runs all
of it.

**Which document Trivy applies when several are attached.** Findings reported
by `trivy image --vex oci`, four consecutive runs per layer set, nothing
changed between runs:

| `.att` layers, in manifest order | Run 1 | Run 2 | Run 3 | Run 4 | Document applied |
|---|---|---|---|---|---|
| [A] | 8 | 8 | 8 | 8 | A, stable |
| [B] | 7 | 7 | 7 | 7 | B, stable |
| [B, A] | 8 | 8 | 8 | 8 | A in this session; A in an earlier session too |
| [A, B] | 7 | 7 | 7 | 7 | B (earlier session: B) |
| [A, B, A] | 8 | 8 | 8 | 8 | A in this session; **B in an earlier session** (7) |
| [A, A, B] | 7 | 8 | 7 | 7 | **varies within the session** |
| [B, C, A] (C is B under another id) | 8 | 8 | 8 | 7 | **varies within the session** |
| [A, A, A, B] | 7 | 7 | 8 | 7 | **varies within the session** |

The selection is not the first layer (`[B, A]` applied A), not the last
(`[A, B, A]` applied B in one session), not the newest document timestamp
(`[B, A]` ignored B), and not stable across runs of an unchanged registry.
Read as written, "taking the first one" means the first of an unordered
collection.

**What cosign offers to keep one document.**

| Question | Result |
|---|---|
| Does `cosign attest --replace` (v2.6.0) reduce several OpenVEX layers to one? | Yes: `[A, B]` then `attest --replace B` leaves one layer; `attest --replace A` afterwards leaves one layer carrying A; Trivy then reports 7 and 8 respectively, stable |
| Does `--replace` touch other predicate types? | No: with an SPDX attestation present, `attest --type openvex --replace` left the layer list at `[openvex, spdx]` |
| Can `cosign clean` remove only OpenVEX? | No: `--type` accepts `signature`, `attestation`, `sbom` or `all`; `attestation` removes every attestation including the SBOMs and scan reports |
| Does cosign v3.1.2 offer `--replace`? | No flag in `attest --help`; v3 writes bundles that neither Trivy 0.72 nor Kyverno 1.18 read (ADR 0003) |

## Decision

1. **Exactly one OpenVEX attestation per digest, at all times.** The release
   job attests the single compiled document once (ADR 0003). The rescan, when
   its freshly compiled document differs from the attested one, runs
   `cosign attest --type openvex --replace`; it never appends. The same holds
   for the scan-report attestation (cosign `vuln` predicate): the rescan
   replaces yesterday's report with today's.
2. **History is Rekor plus recompute, not stacked layers.** Every attestation
   ever made is logged in the public transparency log whether or not it was
   later replaced, and the compiled document is recomputable from its named
   inputs (Req 6.37: source statements, exceptions, the attested scan reports,
   the previously attested document). Nothing a consumer can read from the
   digest depends on chance.
3. **The consumer recipe is one `cosign verify-attestation --type openvex`.**
   No merge step; the "merge the predicates" wording recorded under F5 (ii)
   on 2026-08-21 is withdrawn.
4. **cosign stays on the v2 line** (ADR 0003's pin), now for two measured
   reasons: the bundle layout and the missing `--replace`.
5. **The check script is a regression test.** It runs after any Trivy or
   cosign bump and inside the daily consumer smoke test (review F7), because
   a Trivy release that starts merging or ordering attestations would change
   what consumers see without any error.
6. **Upstream gets a report.** The nondeterminism is Trivy's, not ours, and
   the repo's transfer discipline applies: a draft under `triage/upstream/`
   with this evidence and the re-runnable check, filed deliberately.

## Consequences

- Cluster B's specification: re-attestation is a replace; the rescan gains
  `packages: write` beside `id-token: write` (rewriting the `.att` manifest
  is a push), with the daily verification proof over every tag-referenced
  digest (Req 2.24) as the compensating control in the same run.
- **Today's published grafana digest carries three OpenVEX attestations**
  (one per compiled source file, `build.yml` as it stands), so a `--vex oci`
  consumer gets one of three documents at random until task 9.1's first
  release replaces them with one. Until then the README recipe that reads the
  predicate should merge what `verify-attestation` returns; the recipe is
  rewritten by task 9.6 anyway.
- ADR 0003 is amended: its "Trivy takes the first OpenVEX attestation only"
  is corrected to the measured behaviour. Its decision stands and is
  strengthened, since a random choice is worse than a stale one.
- Two questions were left unmeasured here for the implementing task and
  are answered under "Measured in CI" below: `--replace` under keyless
  signing, and Rekor's retention of a replaced entry.

## Measured in CI (task 10.3, 2026-09-03 and 2026-09-04)

The rescan re-attests with the workflow's keyless identity (`rescan.yml` on
`main`), replacing (Req 6.42, 6.43), and records every write with the `.att`
layer lists and Rekor log indexes before and after (`reattest.jsonl`). The
two open questions, answered from those records and from the registry:

| Left open on 2026-08-23 | Measured | Evidence |
|---|---|---|
| `--replace` under keyless signing behaves as with a key | Yes. Run 33803244102 (2026-09-03, the first rescan after task 10.3 merged) replaced the releaser's document with the re-attester's on 13 of 19 tag-referenced digests, one layer each. On 2026-09-04 all 54 targets (19 indexes, 35 platform manifests) carried exactly one OpenVEX attestation, written by four different runs of both roles, counted from the `.att` manifests; `check-attestation-count.sh` has proven the count daily since | the run's summary; `crane manifest <repo>:sha256-<hex>.att` on 2026-09-04 |
| Rekor retains the replaced entry | Yes. Run 33867898868 (2026-09-04) replaced three documents; the log index of every replaced layer still answered from Rekor after the replace (`rekor_retained: yes`, 3 of 3) | the run's re-attestation table |

Two things the first days taught, both fixed the same day:

- **Sigstore blips.** Run 33854524508 failed one write of about ninety:
  Rekor answered "already exists" to an upload cosign's client had retried,
  then 404 for that entry by UUID from a lagging replica. A new attempt signs
  with fresh keys and lands a new entry, so `reattest.sh` tries a failed
  attest up to three times, each failure named (#145). The cost is the first
  entry staying in the log unused, which decision 2 already accepts.
- **A document must not differ from itself.** The compiler paired last
  time's statements by finding and package, and a package that is excepted in
  one binary and uncovered in another carries two statements, so one was
  re-stamped on every compile and grafana 13.1.2 and 13.1.3 were re-attested
  daily with no input change. Pairing is by finding, status and package now
  (#144). A replace that changes nothing is a Rekor entry for nothing, and the
  differs test only means something if the compiler is stable.

One expected replace stays: the release job compiles without the open-issue
map, so the first rescan after a build adds the issue links and replaces that
document once (grafana 13.1.5 on 2026-09-04, rebuilt that morning).
