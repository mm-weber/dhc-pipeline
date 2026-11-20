# The lanes: what runs, and why

The catalogue is a set of lanes: each is one path work takes through the repository, from a trigger to a published result. This page draws each lane once. A box is a step; its label names the requirement it fulfils (`Req n.m`, in [requirements.md](../.specs/dhc-catalogue-mvp/requirements.md)) and the design decision or ADR it rests on (`Decision n` in [design.md](../.specs/dhc-catalogue-mvp/design.md#key-design-decisions), ADRs in [docs/decisions/](decisions/)). A slanted box is a value declared in `catalogue-policy.yaml`, a diamond a branch on such a value, a rounded box an outcome. The table under each graph says where each step runs and where it is explained. GitHub draws the graphs; their text is in this file and changes in the pull request that changes the lane (Req 9.21).

Drill (Req 9.20, removed in the next commit): [a file that does not exist](./drill-no-such-file.md), [a heading that does not exist](#drill-no-such-heading).

## The lane map

How the lanes connect. The lanes not yet drawn below are drawn in the next steps of the documentation track; until then the [manual](user-manual.md#part-ii-the-pipeline) explains them.

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart LR
    U["Upstream tracking<br/>Renovate, at most every 6 h (Req 3.1),<br/>configured every 4 h"] --> G["Pull-request gate<br/>validate, build, scan, chart, e2e<br/>Req 1, 4, 5, 6.1, 7"]
    G -->|merge to main| R["Release<br/>build, scan, sign, attest<br/>Req 2"]
    S["Daily rebuild<br/>04:47 UTC, published on change<br/>Req 2.14 to 2.17"] --> R
    DSP["Dispatch by the owner<br/>one image or all"] --> R
    R --> P["SLSA provenance<br/>Req 2.27 to 2.30<br/>Decision 15"]
    P --> T(["Tags move<br/>Req 2.7"])
    T --> D["Daily rescan and triage<br/>06:17 UTC<br/>Req 6"]
    D --> ST(["Status issue and catalogue page<br/>Req 6.46, 6.61"])
    D --> GOV(["Posture: rulesets, reporting,<br/>revocations · Req 9"])
    T --> C(["Consumer: verify recipe,<br/>Kyverno policy · Req 2.23, 2.25"])
    classDef drawn fill:#d7ecff,stroke:#1f6feb,stroke-width:2px
    class P drawn
```

## SLSA provenance

A provenance statement says who built a digest, from which repository, workflow file, branch and commit. Since 2026-11-18 every release made while the provenance mode is not `off` carries one beside the index and each platform manifest, generated and signed by GitHub's provenance service rather than written by the job, and the release checks it before any tag moves. These steps run only on `main`, after a push, a dispatch, or a scheduled rebuild that found a change and publishes; a pull request and a scheduled rebuild that publishes nothing never reach them. What it is for and the level claimed: [SECURITY.md](../SECURITY.md#slsa-build-level). The choice of service, verifier and storage: Decision 15 and [ADR 0005](decisions/0005-slsa-provenance-verifier.md). One switch, `release.provenance`, decides how much of the lane runs: `report` here, `required` in the successor, `off` for a repository GitHub offers no attestations to.

### At release

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    MODE[/"release.provenance<br/>off · report · required · Req 2.30"/]
    EXP[/"verification.provenance: five expectations<br/>Req 2.28 · ADR 0005, decision 5"/]
    IN(["On main: a push, a dispatch, or a scheduled<br/>rebuild that publishes · Req 2.14 to 2.17"])
    SIGN["Sign and attest<br/>the signature, the SBOMs, the VEX document<br/>the scan reports attested just before · Req 2.9"]
    M1{"Mode?"}
    SUBJ["Name the subjects<br/>the index and every platform manifest<br/>Req 2.27 · Decision 15"]
    ATT["Attest<br/>GitHub's provenance service signs a statement<br/>built from the job's signed identity token<br/>Req 2.27 · ADR 0005"]
    STORE["Store beside each digest<br/>one more layer of its attestation manifest<br/>Req 2.27 · ADR 0005, amendment"]
    VER["Self-check every digest<br/>cosign for the signer, then the five expectations<br/>Req 2.9, 2.28"]
    TAG(["Apply the tags · Req 2.7, 2.9"])
    STOP(["No tag, the digest named · Req 2.9"])
    IN --> SIGN
    MODE --> M1
    SIGN --> M1
    M1 -->|report or required| SUBJ --> ATT --> STORE --> VER
    EXP --> VER
    VER -->|every digest passes| TAG
    M1 -->|off| TAG
    SUBJ -.->|fails| STOP
    ATT -.->|fails| STOP
    STORE -.->|fails| STOP
    VER -.->|fails| STOP
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| Name the subjects | [`build.yml`](../.github/workflows/build.yml), step "name the provenance subjects"; [`unpack-provenance.sh subjects`](../scripts/unpack-provenance.sh) | [the release path](user-manual.md#the-release-path-merge-to-main-the-nightly-or-a-dispatch) | Req 2.27; Decision 15 |
| Attest | `build.yml`, step "attest provenance for the index and every platform manifest"; `actions/attest-build-provenance`, pinned by commit | [ADR 0005](decisions/0005-slsa-provenance-verifier.md) | Req 2.27; Decision 15, option B |
| Store | `build.yml`, step "store the provenance beside each digest"; [`unpack-provenance.sh store`](../scripts/unpack-provenance.sh) | [a release stopped at the provenance steps](user-manual.md#a-release-stopped-at-the-provenance-steps) | Req 2.27; ADR 0005, amendment of 2026-11-13: no bundle beside a digest, it hid the other attestations from cosign |
| Self-check | `build.yml`, step "verify the provenance of each digest"; [`check-provenance.sh verify`](../scripts/check-provenance.sh) | [what a provenance statement has to say](user-manual.md#what-a-provenance-statement-has-to-say) | Req 2.9, 2.28; ADR 0005, decisions 2 and 5 |
| Tags, or none | `build.yml`, step "apply definition-derived tags" | [the release path](user-manual.md#the-release-path-merge-to-main-the-nightly-or-a-dispatch) | Req 2.7, 2.9: any failure above moves no tag, consumers keep the previous digest |

### In the daily rescan

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    MODE[/"release.provenance · Req 2.30"/]
    EXP[/"verification.provenance · Req 2.28"/]
    M2{"Mode?"}
    COV["Ask every supported digest<br/>and each platform manifest under it<br/>the self-check's question · Req 2.29"]
    LINE(["Status issue: covered n of m,<br/>each one not covered named · Req 2.29"])
    FAIL(["Step fails after the last one asked<br/>the successor's position · SLSA track, FR-3"])
    CANT(["The check cannot be made: the step fails by name,<br/>the status goes out without the line · SLSA track, FR-3"])
    OFFL(["Status issue: provenance is off,<br/>nothing verified · Req 2.30"])
    MODE --> M2
    EXP --> COV
    M2 -->|report or required| COV --> LINE
    COV -.->|required, and one not covered| FAIL
    COV -.->|a tool or the policy file cannot serve| CANT
    M2 -->|off| OFFL
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| Ask every reference | [`rescan.yml`](../.github/workflows/rescan.yml), step "provenance coverage over the supported set"; `check-provenance.sh report` or `require` | [provenance coverage in the status](user-manual.md#provenance-coverage-in-the-status) | Req 2.29; an absent statement never fails the run under `report`; what `require` and a check that cannot be made do is the SLSA track's FR-3 ([spec](../conductor/tracks/slsa-build-l2_20261028/spec.md)), the owner's call of 2026-11-19 |
| The status line | `rescan.yml`, step "catalogue status, the clocks over the supported set"; the status tool in [`triage/rescan`](../triage/rescan/) | [the catalogue status issue](user-manual.md#the-catalogue-status-issue) | Req 2.29, 2.30, 6.46, 6.47 |

### For a consumer

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    EXP[/"verification.provenance · Req 2.28"/]
    MODE[/"release.provenance · Req 2.30"/]
    M3{"Mode is off?"}
    STEP["Recipe step in the README<br/>cosign for the signer, jq for the five<br/>Req 2.25 · ADR 0005, decision 2"]
    NOSTEP(["The README says releases attest none,<br/>no step · Req 2.25, 2.30"])
    SMOKE(["The smoke test runs it every day<br/>an empty result fails · Req 9.13"])
    KYV{"Mode is required?"}
    RULE(["Kyverno admits no image without it<br/>Req 2.28 · the successor"])
    NORULE(["The policy asks for no provenance<br/>this repository, mode report"])
    CLAIM(["SECURITY.md: Build L1 claimed here,<br/>Build L2 from the successor · Req 9.19"])
    MODE --> M3
    M3 -->|no| STEP
    M3 -->|yes| NOSTEP
    EXP --> STEP --> SMOKE
    EXP --> KYV
    MODE --> KYV
    KYV -->|yes| RULE
    KYV -->|no| NORULE
    MODE --> CLAIM
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| The recipe step | the README's block, rendered by [`render-verification.sh`](../scripts/render-verification.sh) from the declaration | [verify an image](../README.md#verify-an-image) | Req 2.25; ADR 0005, decision 2: a step without the jq half verifies the signer only |
| The smoke test | `rescan.yml`, step "consumer smoke test"; [`consumer-smoke.sh`](../scripts/consumer-smoke.sh) | [reading job summaries](user-manual.md#reading-job-summaries) | Req 9.13; the review of 2026-09-09, finding 2.4: an empty result passed |
| The Kyverno rule | [`policies/verify-catalogue-images.yaml`](../policies/verify-catalogue-images.yaml), rendered only under `required` | [what a provenance statement has to say](user-manual.md#what-a-provenance-statement-has-to-say) | Req 2.28; ADR 0005, amendment: one more attestation of the existing entry |
| The claim | [SECURITY.md](../SECURITY.md#slsa-build-level) | the same | Req 9.19: no level above what the policy demands |
