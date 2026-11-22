# The lanes: what runs, and why

The catalogue is a set of lanes: each is one path work takes through the repository, from a trigger to a published result. This page draws each lane once. A box is a step; its label names the requirement it fulfils (`Req n.m`, in [requirements.md](../.specs/dhc-catalogue-mvp/requirements.md)) and the design decision or ADR it rests on (`Decision n` in [design.md](../.specs/dhc-catalogue-mvp/design.md#key-design-decisions), ADRs in [docs/decisions/](decisions/)). A slanted box is a value declared in `catalogue-policy.yaml`, a diamond a branch on such a value, a rounded box an outcome. The table under each graph says where each step runs and where it is explained. GitHub draws the graphs; their text is in this file and changes in the pull request that changes the lane (Req 9.21).

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
    class U,G,R,S,DSP,P,D,GOV drawn
```

## Upstream tracking

This lane turns a new upstream release into a pull request, so nobody has to watch upstream by hand. Renovate (a bot that reads version pins and proposes updates) runs self-hosted in GitHub Actions every 4 hours, or when the owner dispatches it. It reads every pin in the repository, holds back what is too young or too big to offer, makes each bumped definition consistent again with a refresh script, and opens a pull request. That pull request then enters the [pull-request gate](user-manual.md#part-ii-the-pipeline) like any other change. Why Renovate and not a custom tracker: Decision 2. How much to trust an upstream release: Decision 8 and, for grafana, [ADR 0002](decisions/0002-grafana-upstream-tracking.md). Renovate cannot read `catalogue-policy.yaml`, so the two policy values it depends on reach it through a lint and a rendered block in `renovate.json5`.

### What is offered

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    SCHED[/"workflows: renovate.yml, schedule<br/>every 4 h · Req 3.1, 7.10"/]
    SET[/"active_set<br/>the definitions tracked · Req 1.13, 1.14"/]
    RT["Render the tracking scope into renovate.json5<br/>one ignored path per inactive definition<br/>and per chart deploying none · Req 1.14 · Decision 11"]
    IN(["The cron, or the owner's dispatch<br/>with dry run and log level"])
    RUN["Renovate runs, self-hosted<br/>one manager per pin surface · Req 3.1 · Decision 2"]
    DS{"Datasource?"}
    AGE{"At least three days old,<br/>and Renovate can date it?<br/>Req 3.7 · Decision 8"}
    WAIT(["Pending on the Dependency Dashboard,<br/>offered once it has aged"])
    MAJ{"A major,<br/>or a grafana minor?"}
    DASH(["Waits for the owner's approval<br/>on the Dependency Dashboard · Req 3.4"])
    GRP["One branch per upstream<br/>cert-manager x3, valkey and compat,<br/>the cert-manager chart pins · Req 3.3"]
    BR(["A bump branch: one version moved,<br/>refreshed in the next graph"])
    ALERT(["GitHub reports a vulnerability alert<br/>on the repository's own tooling"])
    DIS{"Dismissed with a reason?"}
    SEC(["A SECURITY fix pull request<br/>to the lowest fixed version · Req 3.14"])
    NOPR(["No pull request · Req 3.15"])
    LINT(["validate fails by name"])
    SCHED --> IN
    SET --> RT --> RUN
    IN --> RUN --> DS
    DS -->|third-party version| AGE
    DS -->|docker: own digests, build layer| MAJ
    AGE -->|no| WAIT
    AGE -->|yes| MAJ
    MAJ -->|yes| DASH
    MAJ -->|no| GRP --> BR
    ALERT --> DIS
    DIS -->|no| SEC
    DIS -->|yes| NOPR
    SCHED -.->|cron differs from the declaration| LINT
    RT -.->|rendered block differs| LINT
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| The schedule | [`renovate.yml`](../.github/workflows/renovate.yml), `cron: "0 */4 * * *"`; held equal to the declaration by [`validate.yml`](../.github/workflows/validate.yml), step "workflow schedule + permissions vs policy file (Req 7.10)", [`lint-workflow-policy.sh`](../scripts/lint-workflow-policy.sh) | [crons and cadence](user-manual.md#crons-and-cadence) | Req 3.1 (at most 6 h; 4 h leaves margin for GitHub's scheduler delay), 7.10 |
| The tracking scope | [`render-tracking.sh`](../scripts/render-tracking.sh), run by whoever edits the active set; `validate.yml`, step "tracking scope rendering drift check (Req 1.14)" | [deactivate a definition](user-manual.md#deactivate-a-definition), [Renovate managers](user-manual.md#renovate-managers) | Req 1.13, 1.14; Decision 11 |
| Renovate runs | `renovate.yml`, its one step, which has no `name:`: `renovatebot/github-action` v43.0.9, pinned by commit; the managers in [`renovate.json5`](../renovate.json5) | [Renovate managers](user-manual.md#renovate-managers) | Req 3.1; Decision 2 |
| The age | `renovate.json5`, the rule with `minimumReleaseAge: "3 days"` and `timestamp-required` over github-tags, github-releases, npm, pypi, helm and go | [handling Renovate PRs](user-manual.md#handling-renovate-prs) | Req 3.7; Decision 8 (a): docker is exempt, it carries the catalogue's own digests and the hand-reviewed build layer |
| The dashboard | `renovate.json5`, the rules with `dependencyDashboardApproval: true`: every major, and every grafana minor | [handling Renovate PRs](user-manual.md#handling-renovate-prs) | Req 3.4; Decision 2: grafana rides the stable maintenance line, a minor is the owner's call (register row M24) |
| The grouping | `renovate.json5`, the three rules with a `groupName` naming one upstream | [Renovate managers](user-manual.md#renovate-managers) | Req 3.3 |
| The vulnerability alert | `renovate.json5`, `vulnerabilityAlerts: { enabled: true }` | [Renovate managers](user-manual.md#renovate-managers) | Req 3.14, 3.15: a dismissal in GitHub is the not-affected record for the repository's own dependencies |

### A bump made consistent

Renovate moves one value, the version. Every field derived from it (commit, checksum, tags, name) is then stale, so a script Renovate runs after the bump (a `postUpgradeTask`) rewrites them. Before it writes anything it checks the authenticity signal the definition declares in its `# authenticity:` comment, and a failed check writes nothing.

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    BR(["A bump branch from the graph above"])
    K{"Which pin moved?"}
    DEF["refresh-definition.sh<br/>resolve the new tag to its commit<br/>with git ls-remote · Req 3.2 · Decision 2"]
    C1{"Declared class?"}
    VT["GitHub's verification statement<br/>for the tag object · Req 3.8 · Decision 8"]
    VC["GitHub's verification statement<br/>for the commit · Req 3.8 · Decision 8"]
    W1["Rewrite commit, checksum, versions,<br/>alias tags, name; stamp the evidence<br/>beside the pin · Req 3.2, 3.8"]
    GRA["refresh-grafana.sh<br/>the build id from the versions API,<br/>the apt index and the GitHub release · ADR 0002"]
    SRV["dl.grafana.com serves both tarballs;<br/>read each sha256 sidecar · ADR 0002"]
    XO["Class is cross-origin-checksum, and the<br/>versions API sha256 equals the sidecar,<br/>per architecture · Req 3.8 · Decision 8"]
    W2["Rebuild the url; rewrite versions, tags,<br/>both checksums; stamp the evidence · Req 3.2, 3.8"]
    NOTASK["No task: tool and CI Python pins<br/>keep their old hash on purpose · Req 7.5"]
    PR(["Pull request opened, into the gate"])
    REF1(["Refused by name, nothing written · Req 3.8"])
    REF2(["Refused by name, nothing written · Req 3.8"])
    BR --> K
    K -->|a from-source definition| DEF --> C1
    C1 -->|signed-tag| VT --> W1
    C1 -->|signed-commit| VC --> W1
    W1 --> PR
    K -->|grafana| GRA --> SRV --> XO --> W2 --> PR
    K -->|any other pin| NOTASK --> PR
    C1 -.->|none, missing, or cross-origin-checksum| REF1
    VT -.->|lightweight tag, not verified, unreadable| REF1
    VC -.->|not verified, unreadable| REF1
    GRA -.->|no id, or the sources disagree| REF2
    SRV -.->|not served, bad checksum| REF2
    XO -.->|another class, or a mismatch| REF2
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| Which pin moved | `renovate.json5`, the two `postUpgradeTasks` rules: one keyed on the github-tags datasource, one on the name `grafana/grafana`; both commands allowlisted in `renovate.yml` (`RENOVATE_ALLOWED_POST_UPGRADE_COMMANDS`) | [Renovate managers](user-manual.md#renovate-managers) | Decision 2: the two definition archetypes, compile-from-source and tarball-repackage |
| From-source refresh | [`refresh-definition.sh`](../scripts/refresh-definition.sh), inside the Renovate run; its tests: `validate.yml`, step "refresh-definition unit tests (postUpgradeTask, Req 3.2)" | [handling Renovate PRs](user-manual.md#handling-renovate-prs) | Req 3.2, 3.8; Decision 8 (b) |
| Grafana refresh | [`refresh-grafana.sh`](../scripts/refresh-grafana.sh), inside the Renovate run; its tests: `validate.yml`, step "refresh-grafana unit tests (postUpgradeTask, ADR 0002)" | [handling Renovate PRs](user-manual.md#handling-renovate-prs) (with the corner case of a build id no index carries yet, register M11) | Req 3.2, 3.8; ADR 0002 and its amendments of 2026-08-07, 2026-08-11 and 2026-08-25 |
| No task | the pin-script, Python and workflow-pin managers in `renovate.json5` | [handling Renovate PRs](user-manual.md#handling-renovate-prs): completing a tool-pin bump (register M1) | Req 7.5: a checksum that updates itself verifies nothing |

### Merged by a machine, or by the owner

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    PR(["A bump pull request, its checks run<br/>in the pull-request gate"])
    A1{"From-source definition,<br/>patch or digest?"}
    A2{"The catalogue's own image<br/>in a chart, digest only?"}
    AUTO(["Automerged once the required checks are green<br/>Req 3.5, 3.12 · Decision 8 (c)"])
    REV(["Reviewed and merged by the owner: grafana,<br/>chart versions, build layer, Actions,<br/>tool pins, every minor and major<br/>Req 3.5, 3.11 · Decision 2"])
    PR --> A1
    A1 -->|yes| AUTO
    A1 -->|no| A2
    A2 -->|yes| AUTO
    A2 -->|no| REV
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| From-source automerge | `renovate.json5`, the rule `matchDatasources: ["github-tags"]` with `matchUpdateTypes: ["patch", "digest"]`; the later rule `matchManagers: ["github-actions"]` takes Actions back out | [handling Renovate PRs](user-manual.md#handling-renovate-prs) | Req 3.5; Decision 2: Actions are third-party code holding the workflow's token (review D4) |
| Chart digest automerge | `renovate.json5`, the rule over `ghcr.io/mm-weber/dhc/**` with `matchUpdateTypes: ["digest"]`, ordered before the build-layer rule | [handling Renovate PRs](user-manual.md#handling-renovate-prs) | Req 3.12; Decision 8 (c) |
| Reviewed | `renovate.json5`, `automerge: false` on grafana, the helm datasource, the build layer and the Actions manager; no automerge rule reaches the rest | [handling Renovate PRs](user-manual.md#handling-renovate-prs) | Req 3.11; Decision 2: a repackage bump swaps a binary this repository did not build |

## The pull-request gate

This lane decides whether a change may reach `main`. Every pull request starts it, whether a person or Renovate opened it, and so does every push to an open pull request. Four workflows run side by side: `validate` checks conventions and declared values and runs every test suite, `build` builds and scans each definition the change touches, `chart` renders every chart and checks it against the Kyverno policies, and `e2e` installs each touched chart on a throwaway Kubernetes cluster. It produces no image and no tag: its result is five check results, and the branch ruleset admits the merge only when all five are green. The merge then starts the [release](user-manual.md#the-release-path-merge-to-main-the-nightly-or-a-dispatch) on `main`. Two step names in `build.yml` contain a long dash; the tables below print it as a colon.

### What must be green

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    PR(["A pull request opened or updated,<br/>by a person or by Renovate"])
    V["validate.yml, two jobs<br/>conventions, declared values, every test suite<br/>Req 1, 5.8 to 5.10, 7 · Decision 1"]
    B["build.yml<br/>one build and scan per affected definition<br/>Req 1.14, 6.1 · Decision 5"]
    C["chart.yml<br/>every chart rendered and checked by Kyverno<br/>Req 4.6 · Decision 4"]
    E["e2e.yml<br/>one kind cluster per affected chart<br/>Req 5.2 · Decision 11"]
    REQ{"All five required checks green?<br/>the two validate jobs, build gate,<br/>render + policy gate, e2e gate · Req 9.8"}
    OK(["Mergeable; the merge starts the release"])
    RED(["Blocked; the red check names its cause<br/>Req 7.4"])
    PR --> V & B & C & E
    V & B & C & E --> REQ
    REQ -->|yes| OK
    REQ -.->|no| RED
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| The four workflows | [`validate.yml`](../.github/workflows/validate.yml), [`build.yml`](../.github/workflows/build.yml), [`chart.yml`](../.github/workflows/chart.yml), [`e2e.yml`](../.github/workflows/e2e.yml), each `on: pull_request` | [the six workflows](user-manual.md#the-six-workflows) | Req 7.2, 7.4 |
| The required checks | [`.github/rulesets/main_sec.json`](../.github/rulesets/main_sec.json), `required_status_checks`: the job names "yamllint, pin lint, policy tests", "go modules (e2e + rescan tool)", "build gate", "render + policy gate", "e2e gate" | [branch protection](user-manual.md#branch-protection) | Req 9.8: a matrix leg has a name per image, so only the fan-in jobs can be required |

### validate: the declared values

These steps hold the repository to what `catalogue-policy.yaml` declares. Each fails naming the value, file or entry that differs.

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart LR
    SET[/"active_set<br/>Req 1.13"/]
    PRF[/"proofs<br/>Req 5.9"/]
    VER[/"verification<br/>Req 7.8"/]
    WFS[/"workflows<br/>Req 7.10"/]
    REL[/"release<br/>Req 7.7"/]
    TRI[/"triage<br/>Req 6.49"/]
    AS["Active set well formed, no group split;<br/>the pull request touches no inactive definition<br/>and no chart deploying none<br/>Req 1.16, 1.18, 1.19 · Decision 11"]
    TS["Renovate's rendered tracking scope<br/>equals a fresh render<br/>Req 1.14 · Decision 11"]
    PB["Every active definition has a chart probe<br/>or a proof of kind none with a reason<br/>Req 5.8 to 5.10 · Decision 14"]
    VR["The Kyverno policies and README block<br/>equal a fresh render<br/>Req 7.8, 7.9 · Decision 6"]
    WP["Every cron, permissions block and<br/>dispatch input equals the declaration<br/>Req 7.10 · Decision 6"]
    RW["Release switches well formed<br/>Req 2.13, 2.14, 2.17, 7.7"]
    AR["Accepted-risk files complete, no expiry<br/>past the largest ceiling, no ignore file elsewhere<br/>Req 6.11, 6.12 · Decision 7"]
    FAIL(["validate fails, naming the value or entry"])
    SET --> AS
    SET --> TS
    SET --> PB
    PRF --> PB
    VER --> VR
    WFS --> WP
    REL --> RW
    TRI --> AR
    AS -.->|refused| FAIL
    TS -.->|differs| FAIL
    PB -.->|differs| FAIL
    VR -.->|differs| FAIL
    WP -.->|differs| FAIL
    RW -.->|refused| FAIL
    AR -.->|refused| FAIL
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| Active set | `validate.yml`, step "active-set coherence and scope (Req 1.16, 1.18, 1.19)"; [`lint-active-set.sh`](../scripts/lint-active-set.sh) with `--changed`, the files the pull request changes against its base | [deactivate a definition](user-manual.md#deactivate-a-definition) | Req 1.16, 1.18, 1.19; Decision 11 |
| Tracking scope | `validate.yml`, step "tracking scope rendering drift check (Req 1.14)"; [`render-tracking.sh --check`](../scripts/render-tracking.sh) | [Renovate managers](user-manual.md#renovate-managers) | Req 1.14; Decision 11 |
| Functional proofs | `validate.yml`, step "every active definition declares a functional proof (Req 5.8 to 5.10)"; [`lint-probes.sh`](../scripts/lint-probes.sh), which also prints each kind none entry by name | [e2e, the kind suite](user-manual.md#e2e--the-kind-suite) | Req 5.8 to 5.10; Decision 14 |
| Verification renderings | `validate.yml`, step "verification renderings drift check (Req 7.8, 7.9)"; [`render-verification.sh --check`](../scripts/render-verification.sh) | [policies](user-manual.md#policies) | Req 7.8, 7.9; Decision 6 |
| Workflow values | `validate.yml`, step "workflow schedule + permissions vs policy file (Req 7.10)"; [`lint-workflow-policy.sh`](../scripts/lint-workflow-policy.sh) | [crons and cadence](user-manual.md#crons-and-cadence) | Req 7.10; Decision 6 |
| Release switches | `validate.yml`, step "release switches well-formed (Req 2.13, 2.14, 2.17, 7.7)"; [`release-policy.sh check`](../scripts/release-policy.sh), the reader `build.yml` uses too | [the release path](user-manual.md#the-release-path-merge-to-main-the-nightly-or-a-dispatch) | Req 7.7; review D3: a misspelt value is refused, not read as the fail-open branch |
| Accepted-risk lint | `validate.yml`, step "accepted-risk lint for the risk treatment lane (Req 6.11, 6.12)"; [`lint-accepted-risk.sh`](../scripts/lint-accepted-risk.sh) | [writing an accepted-risk exception](user-manual.md#writing-an-accepted-risk-exception) | Req 6.11, 6.12; Decision 7 |

### validate: conventions and suites

The rest of `validate` reads no policy value. It runs in two jobs, and each is one required check.

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    PR(["A pull request"])
    J1["job: yamllint, pin lint, policy tests<br/>a required check · Req 9.8"]
    Y["yamllint · Req 7.2"]
    CP["Chart pins and compat decisions:<br/>shape and review-by date<br/>Req 4.5, 4.8 · Decision 8"]
    PL["Definition lint: digest pins, checksums,<br/>authenticity class, package repositories<br/>Req 1.3, 1.6, 1.10 to 1.12, 7.4 · Decision 8"]
    AC["Runtime account uid 65532 · Req 1.4"]
    KT["Kyverno policy self-tests · Req 4.6"]
    VX["VEX product identity and LOG citations<br/>Req 6.17, 6.19, 6.20, 9.18"]
    RC["Records: revocations schema, links and<br/>anchors, live-evidence ledger<br/>Req 9.6, 9.20, 7.11"]
    SL["Workflow step conditions: rescan steps<br/>always run, release steps stop on a failed scan<br/>Req 2.26 · review D1"]
    UT["Every script's unit tests, the provenance<br/>scripts against the real tools, and every<br/>script has a suite that runs · Req 7.4"]
    RN["Renovate config and manager fixtures<br/>Req 3.2 · Decision 2"]
    J2["job: go modules (e2e + rescan tool)<br/>a required check · Req 9.8"]
    GO["gofmt, go mod tidy, go vet, go build, go test<br/>for the e2e suite and the rescan tool<br/>Req 5.1, 5.5"]
    GREEN(["Two required checks green"])
    FAIL(["The job fails, the step naming the<br/>file, line or convention · Req 7.4"])
    PR --> J1 --> Y --> CP --> PL --> AC --> KT --> VX --> RC --> SL --> UT --> RN --> GREEN
    PR --> J2 --> GO --> GREEN
    J1 -.->|any step fails| FAIL
    J2 -.->|any step fails| FAIL
```

The boxes group the job's steps by subject; in the workflow they run in a slightly different order, the declared-value checks above among them.

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| yamllint | `validate.yml`, step "yamllint (Req 7.2)", over every YAML file, not only changed ones | [validate, the lint battery](user-manual.md#validate--the-lint-battery) | Req 7.2 |
| Chart pins and compat | `validate.yml`, step "chart pins and compat decisions (Req 4.5, 4.8)"; `yamale` and [`lint-compat.sh`](../scripts/lint-compat.sh) | [adapt a chart](user-manual.md#adapt-a-chart) | Req 4.5, 4.8; Decision 8 |
| Definition lint | `validate.yml`, step "pin + definition lint against docs/CONVENTIONS.md (Req 1.6, 7.2, 7.4)"; [`lint-pins.sh`](../scripts/lint-pins.sh) | [validate, the lint battery](user-manual.md#validate--the-lint-battery), [CONVENTIONS.md](CONVENTIONS.md) | Req 1.3, 1.6, 1.10 to 1.12, 7.4; Decision 8. The schema half of Req 7.2 is the frontend compiling the definition in `build.yml` (Decision 1) |
| Runtime account | `validate.yml`, step "runtime account lint (Req 1.4)"; [`lint-accounts.sh`](../scripts/lint-accounts.sh) | [add an image definition](user-manual.md#add-an-image-definition) | Req 1.4 |
| Kyverno self-tests | `validate.yml`, step "kyverno policy tests (Req 4.6 gate self-test)" | [policies](user-manual.md#policies) | Req 4.6 |
| VEX lints | `validate.yml`, steps "VEX product identity lint (Req 6.17, 6.19, 6.20)" and "VEX statement LOG citations (Req 9.18)"; [`lint-vex-product.sh`](../scripts/lint-vex-product.sh), [`lint-log-anchors.sh`](../scripts/lint-log-anchors.sh) | [writing a VEX statement](user-manual.md#writing-a-vex-statement) | Req 6.17, 6.19, 6.20, 9.18 |
| Records | `validate.yml`, steps "revocation record (Req 9.6)", "relative links and heading anchors resolve (Req 9.20)", "live-evidence ledger covers every criterion (Req 7.11)" | [revoke a digest](user-manual.md#revoke-a-digest), [validate, the lint battery](user-manual.md#validate--the-lint-battery), [live-evidence.md](live-evidence.md) | Req 9.6, 9.20, 7.11 |
| Step conditions | `validate.yml`, steps "rescan steps run regardless of earlier failures (D1)" and "release steps stay stopped by a failed scan (Req 2.26)" | [reading job summaries](user-manual.md#reading-job-summaries) | Req 2.26; review D1 of 2026-09-09 |
| Suites | `validate.yml`, one step per `scripts/*_test.sh`, then "install the pinned crane and cosign for the real-tool suite (Req 7.5)", "provenance scripts against the real crane and cosign (Req 2.27, 2.28)" and "every script has a test suite, and every suite runs here" | [scripts](user-manual.md#scripts) | Req 7.4; review D7: a suite that never runs in CI proves nothing |
| Renovate fixtures | `validate.yml`, step "renovate config + manager fixtures" | [Renovate managers](user-manual.md#renovate-managers) | Req 3.2; Decision 2 |
| Go modules | `validate.yml`, job "go modules (e2e + rescan tool)": steps "gofmt", "go.mod and go.sum are what go mod tidy would write", "go vet", "go build (compiles suite + helpers)", "helper unit tests", and the four "rescan tool" steps | [validate, the lint battery](user-manual.md#validate--the-lint-battery) | Req 5.1; Req 5.5 and 5.8 through `TestProbeDeclarations`, every declared probe registered |

### build: which definitions

`build.yml` first works out which definitions the pull request touches, and builds only those. The `changes` job does this; the `build gate` job at the end is the one check branch protection can require.

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    SET[/"active_set<br/>Req 1.13"/]
    PR(["A pull request, diffed against its base"])
    K{"Which paths changed?<br/>every rule that matches adds"}
    D1["A definition file under image/:<br/>that definition"]
    D2["triage/vex/: the definitions publishing each<br/>product a changed statement names,<br/>before and after the change · Req 6.4"]
    D3["An image's file in triage/accepted-risk/:<br/>that image · Req 6.9"]
    D4["build.yml itself: hardened-app as a canary,<br/>else the first active definition"]
    FIL["Keep only active definitions;<br/>each one dropped is named in the log<br/>Req 1.14, 1.15 · Decision 11"]
    ANY{"Any left?"}
    LEG(["One build leg per definition,<br/>drawn in the next two graphs"])
    NONE(["No leg runs"])
    GATE{"build gate: detection succeeded,<br/>and every leg passed or none ran?"}
    GREEN(["build gate green"])
    RED(["build gate red"])
    PR --> K
    K --> D1 & D2 & D3 & D4
    D1 & D2 & D3 & D4 --> FIL
    SET --> FIL
    FIL --> ANY
    ANY -->|yes| LEG
    ANY -->|no| NONE
    LEG --> GATE
    NONE --> GATE
    GATE -->|yes| GREEN
    GATE -.->|no| RED
    FIL -.->|active set unreadable| RED
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| Which paths changed | [`build.yml`](../.github/workflows/build.yml), job "affected definitions", its one step (`id: detect`, no `name:`), the `pull_request` branch | [build, the scan gate](user-manual.md#build--the-scan-gate), item 1 | Req 6.4, 6.9: a statement or exception change re-proves itself on the images it names |
| Keep only active ones | the same step, after the branches; `active_definitions` in [`definition-lib.sh`](../scripts/definition-lib.sh) | [deactivate a definition](user-manual.md#deactivate-a-definition) | Req 1.14, 1.15; Decision 11. `validate` fails such a pull request separately (Req 1.16) |
| The fan-in | `build.yml`, job "build gate", its one step (no `name:`) | [branch protection](user-manual.md#branch-protection) | Req 9.8: "skipped" passes only when detection itself succeeded |

### build: one definition on a pull request

Each leg builds one definition for linux/amd64 only and loads it into the runner's Docker daemon. Nothing reaches the catalogue registry: the only push goes to a registry that lives on the runner for the length of the job.

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    NS[/"verification.registry,<br/>release.platforms · Req 7.7"/]
    LEG(["One leg, one definition"])
    META["Read the definition: its image inside the<br/>declared namespace, every platform admitted<br/>Req 2.1, 2.2, 7.7 · Decision 11"]
    ARCH["Verify every per-architecture checksum<br/>against the bytes upstream serves · Req 1.3"]
    BLD["Build linux/amd64 through the<br/>dhi.io/build frontend, load, no push<br/>Req 7.2 · Decision 1, ADR 0001"]
    LR["Push to a throwaway registry on the runner,<br/>so the image has a digest VEX can match<br/>Req 6.29"]
    NEXT(["An image with a digest,<br/>scanned in the next graph"])
    STOP(["Leg red, the cause named"])
    LEG --> META
    NS --> META
    META --> ARCH --> BLD --> LR --> NEXT
    META -.->|outside the namespace,<br/>a platform not admitted| STOP
    ARCH -.->|checksum differs| STOP
    BLD -.->|does not compile| STOP
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| Read the definition | [`build.yml`](../.github/workflows/build.yml), job "build ${{ matrix.name }}", the step `id: meta` (no `name:`); [`release-policy.sh`](../scripts/release-policy.sh) | [build, the scan gate](user-manual.md#build--the-scan-gate), item 3 | Req 2.1, 2.2, 7.7; Decision 11. It runs on every event, so a pull request is refused the same way a release would be |
| Build | `build.yml`, the step `id: build` (no `name:`), `docker/build-push-action` with `platforms: linux/amd64` and `load: true` on a pull request | [anatomy of a DHI definition](user-manual.md#anatomy-of-a-dhi-definition) | Req 7.2 (the frontend is the schema check); Decision 1, [ADR 0001](decisions/0001-build-layer.md) |
| Local registry | `build.yml`, step "local registry: give the image an identity VEX can match" | [build, the scan gate](user-manual.md#build--the-scan-gate), item 4 | Req 6.29; Trivy builds the product identifier from the digest a push mints (upstream trivy#9399) |

### build: the scan and the decision

Only the last step fails the leg on a finding; the one before it fails on an exception that outlives its ceiling. An expired exception covers nothing, so its finding counts. Two earlier steps are evidence: when they fail, the step shows red and the leg goes on.

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    AP[/"triage.aperture<br/>CRITICAL, HIGH · Req 6.49"/]
    CO[/"consumers: trivy authoritative,<br/>grype informational · Req 9.11"/]
    CE[/"triage ceilings, kev_ceiling,<br/>kev_feed · Req 6.49"/]
    IMG(["The image from the graph above"])
    SC["Compile VEX for its digest, then one<br/>Trivy scan with it and the accepted-risk file<br/>Req 6.1, 6.28 to 6.30 · Decision 5"]
    PT["VEX portability: Grype reads the same image<br/>Req 9.12 · Decision 10"]
    GV["govulncheck over every Go binary<br/>Req 6.13"]
    EV(["Step red, the leg goes on:<br/>evidence, not a gate"])
    CR{"An uncovered CRITICAL?"}
    GR["Grype second opinion, informational<br/>a convention, its criterion retired"]
    TI["Exception tiers: each exception within<br/>its severity or KEV ceiling<br/>Req 6.50, 6.59 · Decision 7"]
    GA{"Anything uncovered<br/>within the aperture?<br/>Req 6.1, 6.9"}
    OK(["Leg green; scan reports uploaded"])
    RED(["Leg red, each finding named with<br/>the four ways out; reports uploaded · Req 6.1"])
    STOP(["Leg red, the cause named"])
    IMG --> SC
    AP --> SC
    SC --> PT --> GV --> CR
    CO --> PT
    PT -.->|a consumer failed| EV
    GV -.->|a tool or a binary gave no output| EV
    CR -->|yes| GR --> TI
    CR -->|no| TI
    CE --> TI
    TI --> GA
    GA -->|no| OK
    GA -.->|yes| RED
    SC -.->|no report| STOP
    TI -.->|KEV feed unavailable,<br/>or a ceiling breached| STOP
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| Compile and scan | `build.yml`, step "Trivy scan (VEX + accepted risk)"; [`compile-vex.sh`](../scripts/compile-vex.sh), [`scan-image.sh`](../scripts/scan-image.sh), the same script the release scan uses | [writing a VEX statement](user-manual.md#writing-a-vex-statement), [reading job summaries](user-manual.md#reading-job-summaries) | Req 6.1, 6.26 to 6.30; Decision 5, [ADR 0003](decisions/0003-one-openvex-document-per-digest.md) |
| VEX portability | `build.yml`, step "VEX portability (Req 9.12)", `continue-on-error: true`; [`vex-consumer.sh`](../scripts/vex-consumer.sh), [`vex-portability.sh`](../scripts/vex-portability.sh) | [reading job summaries](user-manual.md#reading-job-summaries) | Req 9.11, 9.12; Decision 10: `consumers.gating` is off, so a divergence is reported, never failed |
| govulncheck | `build.yml`, step "govulncheck reachability (Req 6.13)", `continue-on-error: true`; [`govulncheck-report.sh`](../scripts/govulncheck-report.sh) | [reachability evidence](user-manual.md#reachability-evidence-govulncheck) | Req 6.13; review D3: a tool that gave no output fails the step by name |
| Grype | `build.yml`, step "Grype second opinion (CRITICAL present)", run only when Trivy left a CRITICAL uncovered | [build, the scan gate](user-manual.md#build--the-scan-gate), item 7 | A convention: its criterion, Req 6.6, is retired |
| Exception tiers | `build.yml`, step "exception tiers against KEV (Req 6.50)"; [`check-exceptions.sh gate`](../scripts/check-exceptions.sh) with the KEV feed fetched fresh | [writing an accepted-risk exception](user-manual.md#writing-an-accepted-risk-exception) | Req 6.50, 6.59; Decision 7: an unavailable feed fails closed, by name |
| The scan gate | `build.yml`, step "Scan gate: fail on uncovered findings within the aperture" | [clearing a red gate](user-manual.md#clearing-a-red-gate--the-four-treatments) | Req 6.1, 6.9 (Trivy drops an expired ignore entry, so its finding counts); Decision 5 |
| Reports | `build.yml`, step "upload scan reports", `if: always()` | [reading job summaries](user-manual.md#reading-job-summaries) | Req 6.26, 6.27: the summary names what each exception suppressed |

### chart: every chart, every time

`chart.yml` does not ask what changed: every directory under `chart/` is rendered and checked on every pull request. Installing a chart on a cluster is the next graph's job.

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    NS[/"verification.registry<br/>rendered into restrict-registries · Req 7.8"/]
    PR(["A pull request"])
    TL["Install helm, ct and kyverno,<br/>each pinned and checksum-verified · Req 7.5"]
    RD["Render each chart: an owned chart from its<br/>own directory, an adapted one from its pinned<br/>upstream plus the overlay · Req 4.1, 4.2 · Decision 4"]
    KY["Kyverno: digest pinned, allowed registry,<br/>non-root · Req 4.6 · Decision 4"]
    OW{"An owned chart,<br/>with a Chart.yaml?"}
    CT["ct lint<br/>no criterion of its own"]
    OK(["render + policy gate green"])
    RED(["render + policy gate red,<br/>the chart and the rule named"])
    PR --> TL --> RD --> KY --> OW
    NS --> KY
    OW -->|yes| CT --> OK
    OW -->|no| OK
    RD -.->|does not render| RED
    KY -.->|a policy rejects| RED
    CT -.->|fails| RED
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| Tools | [`chart.yml`](../.github/workflows/chart.yml), job "render + policy gate", step "install helm + ct + kyverno"; [`install-tool.sh`](../scripts/install-tool.sh) | [the six workflows](user-manual.md#the-six-workflows) | Req 7.5 |
| Render and check | `chart.yml`, step "render every chart and gate with kyverno (Req 4.6)"; [`render-chart.sh`](../scripts/render-chart.sh), the three policies `require-image-digest`, `restrict-registries`, `require-nonroot` under [`policies/`](../policies/) | [chart, render + policy gate](user-manual.md#chart--render--policy-gate) | Req 4.1, 4.2, 4.6; Decision 4 |
| ct lint | `chart.yml`, step "ct lint owned charts" | [chart, render + policy gate](user-manual.md#chart--render--policy-gate) | No criterion of its own: the chart-testing tool's lint, for the charts this repository owns |

### e2e: the touched charts on a real cluster

`e2e.yml` installs each touched chart on a fresh kind cluster (Kubernetes running inside Docker on the runner). The pods pull the catalogue images the chart pins, which are published digests: a pull request that changes a definition tests its chart with the image already released, and the new image is tested when the chart-pin bump after its release comes through this lane.

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    SET[/"active_set, through each chart's<br/>deploys: list · Req 1.13"/]
    PR(["A pull request, diffed against its base"])
    AF["Affected components: a chart whose directory<br/>changed, or that deploys an active definition<br/>that changed; a harness change adds the<br/>simplest one · Req 1.14, 5.2 · Decision 11"]
    ANY{"Any?"}
    NONE(["No leg runs"])
    KC["A kind cluster, its nodes given<br/>ghcr pull credentials · Req 5.1, 5.2"]
    IS["Runner image store checked, the probe<br/>image loaded by digest · Req 5.5"]
    UP{"A bump: the chart version or the<br/>deployed values file changed? · Req 5.6"}
    IN["Install the proposed chart"]
    UG["Install the base state, upgrade to<br/>the proposed one, wait for the rollout<br/>Req 5.6"]
    AS["Pods Ready within five minutes; restricted<br/>securityContext on live pods; the chart's probe,<br/>once · Req 5.3 to 5.5 · Decision 14"]
    OK(["Leg green"])
    DG(["Leg red; diagnostics uploaded · Req 5.7"])
    GATE{"e2e gate: detection succeeded,<br/>and every leg passed or none ran?"}
    GREEN(["e2e gate green"])
    RED(["e2e gate red"])
    SET --> AF
    PR --> AF --> ANY
    ANY -->|no| NONE
    ANY -->|yes, one leg each| KC --> IS --> UP
    UP -->|no| IN --> AS
    UP -->|yes| UG --> AS
    AS --> OK
    AS -.->|an assertion fails| DG
    IS -.->|containerd image store| DG
    OK --> GATE
    DG --> GATE
    NONE --> GATE
    GATE -->|yes| GREEN
    GATE -.->|no| RED
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| Affected components | [`e2e.yml`](../.github/workflows/e2e.yml), job "affected components", its one step (`id: detect`, no `name:`); `active_components` in [`definition-lib.sh`](../scripts/definition-lib.sh) | [e2e, the kind suite](user-manual.md#e2e--the-kind-suite) | Req 1.14, 5.2; Decision 11: a definition reaches its chart through `deploys:`, never a name prefix |
| Cluster | `e2e.yml`, job "e2e ${{ matrix.component }}", steps "install helm + kind", "create kind cluster", "give kind nodes ghcr pull credentials" | [e2e, the kind suite](user-manual.md#e2e--the-kind-suite) | Req 5.1, 5.2: the charts pin the index digest, which a loaded image cannot match |
| Image store and probe image | `e2e.yml`, steps "runner image and image store (kind issue 3795)", [`check-runner-image-store.sh`](../scripts/check-runner-image-store.sh), and "load probe image into kind" | [e2e, the kind suite](user-manual.md#e2e--the-kind-suite) | Req 5.5 (the probe's image); the job is pinned to `ubuntu-24.04` until kind can load from the containerd store |
| Bump or not | `e2e.yml`, step "compute upgrade-from on a bump" | [e2e, the kind suite](user-manual.md#e2e--the-kind-suite) | Req 5.6 |
| The suite | `e2e.yml`, step "run e2e suite", `go test ./e2e/` with `DHC_E2E=1`; the Ginkgo specs under [`test/e2e/`](../test/e2e/) | [e2e, the kind suite](user-manual.md#e2e--the-kind-suite) | Req 5.3 to 5.6; Decision 14: one probe per chart, standing for every definition it deploys |
| Diagnostics | `e2e.yml`, steps "collect diagnostics on failure", "upload diagnostics", then "delete kind cluster" | [e2e, the kind suite](user-manual.md#e2e--the-kind-suite) | Req 5.7 |
| The fan-in | `e2e.yml`, job "e2e gate", its one step (no `name:`) | [branch protection](user-manual.md#branch-protection) | Req 9.8 |

## The release

This lane turns a definition into a published image: one that carries tags, a signature, SBOMs, a VEX document and scan reports. It runs in `build.yml` on `main` and has three entries: a merge to `main` that changes a definition, the daily rebuild at 04:47 UTC, and a dispatch by the owner naming one image or none (none means every active definition). The daily rebuild first builds locally and publishes only when the packages inside changed. Every release pushes the image by digest (its content address) with no tag, scans exactly that digest, signs and attests it, and moves the tags last. Why this order: Decision 6, "publish with status". The provenance steps between the attestations and the tags are drawn once, in the [SLSA provenance](#slsa-provenance) lane.

### Which definitions

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    CRON[/"release.schedule<br/>47 4 * * * · Req 2.14, 7.10"/]
    SET[/"active_set<br/>Req 1.13"/]
    PUSH(["A merge to main"])
    SCH(["The daily rebuild, 04:47 UTC"])
    DSP(["A dispatch by the owner,<br/>an image name or blank"])
    PD["The definitions whose image.yaml<br/>the push changed · Req 2.1"]
    ALL["Every active definition<br/>Req 2.14"]
    DQ{"An image named?"}
    DA{"Is it active?"}
    ONE["That one definition"]
    FIL["Keep only active definitions;<br/>each one dropped is named in the log<br/>Req 1.14, 1.15 · Decision 11"]
    ANY{"Any left?"}
    LEG(["One leg per definition,<br/>drawn in the next two graphs"])
    NONE(["No leg runs, nothing released"])
    RED(["The run fails, the name given · Req 1.15"])
    CRON --> SCH
    PUSH --> PD --> FIL
    SCH --> ALL --> FIL
    DSP --> DQ
    DQ -->|yes| DA
    DQ -->|no| ALL
    DA -->|yes| ONE --> FIL
    DA -.->|no| RED
    SET --> FIL
    FIL --> ANY
    ANY -->|yes| LEG
    ANY -->|no| NONE
    FIL -.->|active set unreadable| RED
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| The three entries | [`build.yml`](../.github/workflows/build.yml), `on: push: branches: [main]`, `schedule: cron: "47 4 * * *"` and `workflow_dispatch` with the free-text input `image`; cron and input held equal to `catalogue-policy.yaml` by `validate.yml`, step "workflow schedule + permissions vs policy file (Req 7.10)" | [crons and cadence](user-manual.md#crons-and-cadence), [the release path](user-manual.md#the-release-path-merge-to-main-the-nightly-or-a-dispatch) | Req 2.1, 2.14, 7.10; Decision 6 |
| Which definitions | `build.yml`, job "affected definitions", its one step (`id: detect`, no `name:`): on a push, the `image/*/image.yaml` files changed between the previous and the new head; on the schedule, the whole active set; on a dispatch, the named image or the whole active set | [the release path](user-manual.md#the-release-path-merge-to-main-the-nightly-or-a-dispatch) | Req 2.1, 2.14. A merge that changes only a VEX statement, an exception or a chart releases nothing; the daily rescan carries a VEX change to the published digests |
| Keep only active ones | the same step, after the branches; `active_definitions` in [`definition-lib.sh`](../scripts/definition-lib.sh) | [deactivate a definition](user-manual.md#deactivate-a-definition) | Req 1.14, 1.15; Decision 11 |

### One definition: built, or discarded by the nightly

Each leg runs the job "build ${{ matrix.name }}". The scheduled rebuild builds locally first and asks whether anything a consumer could receive has changed; a merge and a dispatch never ask.

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    NS[/"verification.registry,<br/>release.platforms · Req 7.7"/]
    POL[/"release.publish_policy<br/>on-change · always · Req 2.15, 2.17"/]
    LEG(["One leg, one definition"])
    META["Read the definition: its image inside the<br/>declared namespace, every platform admitted,<br/>tags from the definition<br/>Req 2.1, 2.3, 7.7 · Decision 11"]
    ARCH["Verify every per-architecture checksum<br/>against the bytes upstream serves · Req 1.3"]
    EV{"Which entry?"}
    LOC["Build every declared platform locally<br/>into an archive, nothing pushed<br/>Req 2.14 · Decision 6"]
    CMP["Compare the package set per platform<br/>with the CycloneDX SBOMs attested to<br/>the full release tag's digest<br/>Req 2.15, 2.16 · Decision 6"]
    EQ{"Equal, and the policy<br/>is on-change?"}
    DISC(["Discarded: nothing pushed, signed,<br/>attested or tagged; the leg is green · Req 2.15"])
    BLD["Build every declared platform,<br/>with BuildKit provenance on main<br/>Req 2.1, 2.2"]
    MAIN{"On main?"}
    PUSHD(["Pushed by digest, no tag,<br/>released in the next graph · Req 2.7"])
    ONLY(["A dispatch from another branch:<br/>built, nothing pushed"])
    STOP(["Leg red, the cause named;<br/>nothing published from it · Req 2.5"])
    LEG --> META
    NS --> META
    META --> ARCH --> EV
    EV -->|the daily rebuild| LOC --> CMP --> EQ
    POL --> EQ
    EQ -->|yes| DISC
    EQ -->|no: the difference in the<br/>summary · Req 2.16, 2.17| BLD
    EV -->|a merge or a dispatch| BLD
    BLD --> MAIN
    MAIN -->|yes| PUSHD
    MAIN -->|no| ONLY
    META -.->|outside the namespace,<br/>a platform not admitted| STOP
    ARCH -.->|checksum differs| STOP
    CMP -.->|a tool missing, no admitted identity| STOP
    BLD -.->|does not build or push| STOP
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| Read the definition | [`build.yml`](../.github/workflows/build.yml), the step `id: meta` (no `name:`); [`release-policy.sh`](../scripts/release-policy.sh) reads the switches and the admitted platforms | [the release path](user-manual.md#the-release-path-merge-to-main-the-nightly-or-a-dispatch), item 4 | Req 2.1, 2.3, 7.7; Decision 11 |
| Checksums | `build.yml`, step "verify per-arch pinned checksums"; [`verify-arch-pins.sh`](../scripts/verify-arch-pins.sh) | [build, the scan gate](user-manual.md#build--the-scan-gate) | Req 1.3: the pull request builds amd64 only, so an arm64 pin is first exercised here |
| Local build | `build.yml`, step "scheduled rebuild, local only (Req 2.14)", `if: github.event_name == 'schedule'` | [the release path](user-manual.md#the-release-path-merge-to-main-the-nightly-or-a-dispatch), "The nightly" | Req 2.14; Decision 6 |
| The comparison | `build.yml`, step "publish-on-change comparator (Req 2.15-2.17)"; [`package-set-diff.sh`](../scripts/package-set-diff.sh), read through `cosign verify-attestation` against the admitted identities; verdict `equal` or `different` with a reason, each of which publishes (`package-set-differs`, `no-published-digest`, `attestation-unreadable`, `platform-set-differs`); cosign is installed before it by step "install cosign and crane" | [the release path](user-manual.md#the-release-path-merge-to-main-the-nightly-or-a-dispatch), "The nightly" | Req 2.15 to 2.17; Decision 6, its reproducibility paragraph: package type, name, version and pull checksum, never SBOM bytes. Only proven equality discards; a missing tool is a refusal, not a difference |
| Build and push | `build.yml`, the step `id: build` (no `name:`), `docker/build-push-action` with `provenance: mode=max` and, on `main` only, `push-by-digest=true`; skipped when the comparator discarded | [the release path](user-manual.md#the-release-path-merge-to-main-the-nightly-or-a-dispatch), item 1 | Req 2.1, 2.2, 2.7; Decision 6. A failure in one leg leaves the other legs running (`fail-fast: false`) |

### One definition: scanned, signed, tagged

Every step here runs only on `main`, and on the schedule only when the comparator said publish. A failed step skips every step after it, so a digest stopped here stays pushed but untagged: frozen, pullable by digest only.

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    FC[/"release.fail_closed<br/>false here · Req 2.13"/]
    DIG(["A digest pushed, no tag"])
    MAN["List the platform manifests,<br/>BuildKit's attestation manifests left out<br/>Req 2.8, 2.26"]
    SCAN["Scan each platform manifest by its own digest<br/>with the gate's VEX and accepted-risk inputs<br/>Req 2.8 · Decision 6"]
    FCD{"Fail-closed on,<br/>and anything uncovered?"}
    ATTR["Attest each manifest's scan report,<br/>the scanner's database written in<br/>Req 2.9, 6.55 · Decision 6"]
    VEX["Compile the digest's one OpenVEX document<br/>an uncovered finding: under_investigation,<br/>with the report's timestamp<br/>Req 2.12, 6.37 · ADR 0003"]
    SIGN["Sign the index and every manifest<br/>each manifest: SPDX, CycloneDX, OpenVEX<br/>the index: each SPDX, the same OpenVEX<br/>Req 2.9 · Decision 6 · ADR 0003"]
    PROV["SLSA provenance, unless its mode is off<br/>drawn in the SLSA provenance lane<br/>Req 2.27 to 2.30 · Decision 15"]
    TAG["Apply the definition's tags, then read each tag<br/>back and check it resolves to the signed digest<br/>Req 2.7, 2.9"]
    PUB(["Published: tagged, signed, attested<br/>Req 2.10; the daily rescan takes over"])
    WITH(["Withheld: each finding named, nothing<br/>signed or attested, no tag · Req 2.13"])
    STOP(["No tag moves; the digest stays<br/>frozen, the step named · Req 2.11, 2.26"])
    MOVED(["Run red; that tag has already moved,<br/>the error names where it points"])
    DIG --> MAN --> SCAN --> FCD
    FC --> FCD
    FCD -->|no| ATTR --> VEX --> SIGN --> PROV --> TAG --> PUB
    FCD -.->|yes| WITH
    MAN -.->|no platform manifest| STOP
    SCAN -.->|a manifest without a report| STOP
    ATTR -.->|fails| STOP
    VEX -.->|fails| STOP
    SIGN -.->|fails| STOP
    PROV -.->|fails| STOP
    TAG -.->|a tag resolves elsewhere| MOVED
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| Platform manifests | [`build.yml`](../.github/workflows/build.yml), step "enumerate platform manifests" | [the release path](user-manual.md#the-release-path-merge-to-main-the-nightly-or-a-dispatch), item 2 | Req 2.8, 2.26 and the Terms of Req 2: a manifest under `unknown/unknown` or with a reference-type annotation is BuildKit's, not a platform |
| Release-time scan | `build.yml`, step "release-time scan of the pushed digest (Req 2.8)"; [`compile-vex.sh`](../scripts/compile-vex.sh) for the source statements, then [`scan-image.sh`](../scripts/scan-image.sh) `--remote`, the script the gate uses | [the release path](user-manual.md#the-release-path-merge-to-main-the-nightly-or-a-dispatch), item 3 | Req 2.8, 2.26; Decision 6: scan what you sign. That later steps stay skipped after a failed scan is checked by `validate.yml`, step "release steps stay stopped by a failed scan (Req 2.26)" |
| Fail-closed | `build.yml`, step "fail-closed release gate (Req 2.13)", run only when the switch is on and the scan left a finding uncovered | [the release path](user-manual.md#the-release-path-merge-to-main-the-nightly-or-a-dispatch), item 4 | Req 2.13; Decision 6: off by default, option B of that decision was rejected |
| Scan reports | `build.yml`, step "attest each platform manifest's scan report (Req 2.9)": `trivy convert --format cosign-vuln`, [`fill-scanner-db.sh`](../scripts/fill-scanner-db.sh), `cosign attest --type vuln` | [the release path](user-manual.md#the-release-path-merge-to-main-the-nightly-or-a-dispatch), item 5 | Req 2.9, 6.55; Decision 6, "scan reports are attested" |
| The OpenVEX document | `build.yml`, step "compile the digest's OpenVEX document (Req 2.12, 6.37)"; `compile-vex.sh` a second time, with the scan reports | [writing a VEX statement](user-manual.md#writing-a-vex-statement) | Req 2.12, 6.37; [ADR 0003](decisions/0003-one-openvex-document-per-digest.md): one document per digest, empty when nothing applies. The rescan later replaces it, never adds a second ([ADR 0004](decisions/0004-re-attestation-replaces.md)) |
| Sign and attest | `build.yml`, step "sign and attest (Req 2.9)": `cosign sign --recursive` on the index; Syft's SBOMs and each `cosign attest` made per target, not by `--recursive` | [the release path](user-manual.md#the-release-path-merge-to-main-the-nightly-or-a-dispatch), item 7 | Req 2.9; Decision 6; ADR 0003 |
| Provenance | the four steps from "name the provenance subjects (Req 2.27)" to "verify the provenance of each digest (Req 2.9, 2.28)" | [SLSA provenance](#slsa-provenance), the graph "At release" | Req 2.27 to 2.30; Decision 15 |
| Tags | `build.yml`, step "apply definition-derived tags (Req 2.7, 2.9)": `docker buildx imagetools create` with every tag, then `imagetools inspect` per tag | [the release path](user-manual.md#the-release-path-merge-to-main-the-nightly-or-a-dispatch), item 9 | Req 2.7, 2.9, 2.10. The check runs after the tags are written, so a mismatch leaves that tag moved, not untouched |
| The fan-in | `build.yml`, job "build gate", its one step (no `name:`), on `main` as on a pull request | [branch protection](user-manual.md#branch-protection) | Req 9.8: a red leg makes the run's build gate red |

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

## The daily rescan and triage

This lane keeps watching what is already published. New advisories land against images every day, long after their pull request passed the gate, so once a day at 06:17 UTC, or when the owner dispatches it, `rescan.yml` lists every tag the catalogue serves, scans every platform manifest behind it, and acts on what it finds. It produces four things: today's scan reports and VEX document attested to each digest; `cve` issues opened, closed on evidence and reopened; the "Catalogue status" issue with its clocks, and the catalogue page; and a set of daily checks that fail the run by name when a promise is not kept. It decides nothing itself. A triage decision is a pull request a person writes (an OpenVEX statement, an accepted-risk exception, or a fix), and the next rescan reads it. Issues and clocks cover the supported set, the digests a definition's current tags point to; an older digest a tag still reaches keeps its scans and attestations but holds no issues (Req 6.49). Every step after the scan runs whatever failed above it and refuses by name when its own input is missing (review disposition D1, Decision 6), so a red run names every promise not kept that day. Why the rescan works this way: [the daily rescan](../triage/README.md#the-daily-rescan-req-222-63-642-to-657) in the triage README. Two step names in `rescan.yml` contain a long dash; the tables below print it as a colon.

### Scan, attest, and the issue lifecycle

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    SCHED[/"workflows: rescan.yml, schedule<br/>daily 06:17 UTC · Req 2.22, 7.10"/]
    AP[/"triage.aperture<br/>CRITICAL, HIGH · Req 6.49"/]
    ROLES[/"verification.roles<br/>who may attest what · Req 2.23, 6.58"/]
    LBL[/"triage.resolved_labels<br/>Req 6.56"/]
    IN(["The cron, or the owner's dispatch<br/>with its drill input · Req 7.10"])
    TRI(["Merged triage records: triage/vex/,<br/>triage/accepted-risk/ · Req 6.4, 6.7"])
    SW["Read the release switches<br/>page and provenance · Req 7.7"]
    ENUM["Enumerate every catalogue tag<br/>to its digest and platform manifests<br/>Req 2.22 · Decision 6"]
    SCAN["Per digest: compile its VEX, then scan each<br/>platform manifest by its own digest,<br/>statements and exceptions applied<br/>Req 2.22, 6.28 to 6.30, 6.55 · Decision 5"]
    EV["Lifecycle evidence: every cve issue, the scanner,<br/>the SBOMs read through verification<br/>Req 6.52 to 6.58 · Decision 7"]
    DEC["Lifecycle decided by the tested tool:<br/>close, reopen, relabel, keep open<br/>Req 6.52 to 6.57 · Decision 7"]
    MAP["Map each open cve issue, finding to link,<br/>for the statements' tracking links · Req 6.37"]
    ATT["Per digest: attest today's reports, replacing;<br/>compile the document again; re-attest it,<br/>replacing, when it differs · Req 6.42, 6.43<br/>ADR 0003, ADR 0004"]
    APPLY["Lifecycle applied: close with a graded label,<br/>reopen, shed labels · Req 6.52, 6.53, 6.56, 6.57"]
    VEXR(["VEX compile report in the summary:<br/>every statement applied or dropped · Req 6.33"])
    ISS(["cve issues closed and reopened on evidence,<br/>each comment naming what it examined<br/>Req 6.54"])
    ENFAIL(["Run fails by name; nothing is scanned,<br/>only the checks that need no enumeration run"])
    SKIP(["Manifest skipped, warned, counted;<br/>its digest blocks every close, is not re-attested"])
    HOLD(["Closes and reopens withheld today,<br/>the unattested digests named · Req 6.54"])
    SCHED --> IN --> SW --> ENUM --> SCAN
    AP --> SCAN
    TRI --> SCAN
    SCAN --> VEXR
    SCAN --> EV --> DEC
    ROLES --> EV
    LBL --> DEC
    SCAN --> MAP --> ATT
    ROLES --> ATT
    TRI --> ATT
    DEC --> APPLY
    ATT --> APPLY --> ISS
    ENUM -.->|registry unreadable| ENFAIL
    SCAN -.->|one scan fails| SKIP
    APPLY -.->|a digest's reports not attested| HOLD
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| The schedule | [`rescan.yml`](../.github/workflows/rescan.yml), `cron: "17 6 * * *"`, and the dispatch input `drill`; held equal to the declaration by `validate.yml`, step "workflow schedule + permissions vs policy file (Req 7.10)" | [crons and cadence](user-manual.md#crons-and-cadence) | Req 2.22 (at least once a day), 7.10 |
| Release switches | `rescan.yml`, step "release switches (Req 7.7)"; [`release-policy.sh`](../scripts/release-policy.sh) | [the catalogue page](user-manual.md#the-catalogue-page) | Req 7.7; review D3: a malformed switch fails here by name |
| Enumerate | `rescan.yml`, step "enumerate the catalogue (Req 2.22)"; [`enumerate-catalogue.sh`](../scripts/enumerate-catalogue.sh) | [crons and cadence](user-manual.md#crons-and-cadence) | Req 2.22; Decision 6: the one step that fails hard, a partial list would shrink what is watched |
| Compile and scan | `rescan.yml`, step "scan every platform manifest of every tag-referenced digest"; [`compile-vex.sh`](../scripts/compile-vex.sh), [`scan-image.sh`](../scripts/scan-image.sh) with `--remote` | [what VEX means for you](user-manual.md#what-vex-means-for-you), [reading job summaries](user-manual.md#reading-job-summaries) | Req 2.22, 6.28 to 6.30, 6.55; Decision 5; a failed scan skips one manifest and does not fail the step |
| Lifecycle evidence | `rescan.yml`, step "issue lifecycle, the evidence (Req 6.52 to 6.57)"; [`fetch-sboms.sh`](../scripts/fetch-sboms.sh), [`triage-policy.sh`](../scripts/triage-policy.sh) `resolved-labels` | [rescan CVE issues](user-manual.md#rescan-cve-issues) | Req 6.52 to 6.58; Decision 7 |
| Lifecycle decided | `rescan.yml`, step "issue lifecycle, decided on evidence (tested)"; `cmd/rescan-lifecycle` in [`triage/rescan`](../triage/rescan/) | [rescan CVE issues](user-manual.md#rescan-cve-issues) | Req 6.52 to 6.57; Decision 7 |
| Issue map | `rescan.yml`, step "open cve issues (finding -> issue)" | [rescan CVE issues](user-manual.md#rescan-cve-issues) | Req 6.37: the open issue map is the compiler's fifth input |
| Attest and re-attest | `rescan.yml`, step "attest today's reports, re-attest OpenVEX on change (Req 6.42, 6.43)"; [`reattest.sh`](../scripts/reattest.sh) | [triage README, the daily rescan](../triage/README.md#the-daily-rescan-req-222-63-642-to-657) | Req 6.42, 6.43, 6.58; [ADR 0003](decisions/0003-one-openvex-document-per-digest.md), [ADR 0004](decisions/0004-re-attestation-replaces.md): one document per digest, replaced, never appended |
| Lifecycle applied | `rescan.yml`, step "issue lifecycle, applied (Req 6.52, 6.53, 6.56, 6.57)" | [rescan CVE issues](user-manual.md#rescan-cve-issues) | Req 6.52 to 6.57; Decision 7, review D2: it runs after re-attestation because closes rest on attested reports |
| Compile report | `rescan.yml`, step "summary", the block "VEX compilation (Req 6.28-6.30)"; the step "upload rescan artifacts" keeps every file the run wrote | [reading job summaries](user-manual.md#reading-job-summaries) | Req 6.32, 6.33: "compiled nothing" and "never compiled" stay apart |

### The daily checks

Each check reports by name. A check that does not hold fails the run, but never stops the next one from being made.

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    IN(["Today's enumeration and reports,<br/>from the graph above"])
    FEED[/"triage.kev_feed, triage.drills<br/>Req 6.60, 7.7"/]
    TIERS[/"triage.ceilings, triage.kev_ceiling<br/>Req 6.49, 6.51"/]
    CONS[/"consumers<br/>trivy authoritative, grype · Req 9.11"/]
    WIN[/"triage.expiry_warning<br/>Req 6.10, 6.49"/]
    VIS["Every repository and tag pulls anonymously<br/>Req 2.21 · Decision 6"]
    ADM["The admission policy admits every<br/>tagged digest, rejects the unsigned control<br/>Req 2.24 · Decision 6"]
    DR{"Drill input?"}
    KEV["Fetch the KEV feed, or the drill's substitute<br/>Req 6.60 · Decision 13"]
    TIER["Each unexpired exception against today's<br/>severity and KEV status · Req 6.51 · Decision 7"]
    CNT["Exactly one OpenVEX attestation on every<br/>digest and platform manifest · Req 6.44, 6.45<br/>ADR 0004"]
    AUTH["Each definition's authenticity signal against<br/>its origin; lapsed compat review dates<br/>Req 3.10, 3.13, 4.9 · Decision 8"]
    PORT["VEX portability: each other consumer scans<br/>what Trivy suppressed · Req 9.12 · Decision 10"]
    SMOKE["Consumer smoke test: the README recipe<br/>run verbatim on one supported digest<br/>Req 9.13 · Decision 10"]
    EXP["Accepted-risk expiries: lapsed,<br/>or lapsing within the window · Req 6.10"]
    PROV["Provenance coverage, drawn in<br/>the SLSA provenance lane<br/>Req 2.29, 2.30 · Decision 15"]
    POST["Posture: rulesets equal the live ones,<br/>private reporting on, no tag<br/>on a revoked digest<br/>Req 9.3, 9.7, 9.9 · Decision 10"]
    SCI(["One supply-chain issue per definition,<br/>kept open while the mismatch lasts · Req 3.10"])
    PB(["Portability block in the summary,<br/>never fails the run · Req 9.12"])
    EXPL(["Listed in the summary,<br/>never fails the run · Req 6.10"])
    NOEVAL(["Not evaluated: the run fails by name;<br/>no issue set, status or page today · Req 6.60"])
    RED(["The run fails, naming each check<br/>that did not hold"])
    IN --> VIS & ADM & CNT & PORT & SMOKE & PROV & POST
    IN --> DR
    FEED --> DR
    DR -->|none: the declared feed| KEV
    DR -->|kev-outage or kev-synthetic| KEV
    KEV --> TIER
    TIERS --> TIER
    CONS --> PORT --> PB
    WIN --> EXP --> EXPL
    KEV -.->|unreachable| NOEVAL
    VIS -.-> RED
    ADM -.-> RED
    TIER -.->|over its tier| RED
    CNT -.-> RED
    AUTH -.->|mismatch| SCI
    AUTH -.->|mismatch, or origin not measured| RED
    SMOKE -.->|a step fails, or a suppression is missing| RED
    POST -.-> RED
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| Visibility, admission, tiers, count | `rescan.yml`, step "invariants (Req 2.21, 2.24, 6.44, 6.51)"; [`check-visibility.sh`](../scripts/check-visibility.sh), [`verify-catalogue.sh`](../scripts/verify-catalogue.sh), [`check-exceptions.sh`](../scripts/check-exceptions.sh) `rescan`, [`check-attestation-count.sh`](../scripts/check-attestation-count.sh); the four run independently and fail the step together | [reading job summaries](user-manual.md#reading-job-summaries), [policies](user-manual.md#policies) | Req 2.21, 2.24, 6.44, 6.45, 6.51; Decision 6, review D1 |
| The KEV feed and drills | the same step; `triage-policy.sh kev-feed`, or `drill-feed` when the dispatch's `drill` input is not `none` | [crons and cadence](user-manual.md#crons-and-cadence) | Req 6.60: an outage is a failure, not a pass; Decision 13 (live drills, task 16.8) |
| Authenticity | `rescan.yml`, step "authenticity signals (Req 3.10, 3.13, 4.9)"; [`check-authenticity.sh`](../scripts/check-authenticity.sh) | [SECURITY.md, upstream authenticity](../SECURITY.md#upstream-authenticity-per-definition), [handling Renovate PRs](user-manual.md#handling-renovate-prs) | Req 3.10, 3.13, 4.9; Decision 8: an origin that did not answer files no issue |
| Portability | `rescan.yml`, step "VEX portability over the supported set (Req 9.12)", `continue-on-error: true`; [`vex-consumer.sh`](../scripts/vex-consumer.sh), [`vex-portability.sh`](../scripts/vex-portability.sh) | [reading job summaries](user-manual.md#reading-job-summaries) | Req 9.11, 9.12; Decision 10: informational while `consumers.gating` is false |
| Smoke test | `rescan.yml`, step "consumer smoke test (Req 9.13)"; [`consumer-smoke.sh`](../scripts/consumer-smoke.sh) | [reading job summaries](user-manual.md#reading-job-summaries), [verify what you pull](user-manual.md#verify-what-you-pull) | Req 9.13; Decision 10, ADR 0004's `--vex oci` check rides inside it |
| Expiries | `rescan.yml`, step "accepted-risk expiries (Req 6.10)"; [`lint-accepted-risk.sh`](../scripts/lint-accepted-risk.sh) | [expiries](user-manual.md#expiries) | Req 6.10: one implementation of "expired" for the gate and the notice |
| Provenance coverage | `rescan.yml`, step "provenance coverage over the supported set (Req 2.29, 2.30)" | drawn in [SLSA provenance, in the daily rescan](#in-the-daily-rescan) | Req 2.29, 2.30; Decision 15 |
| Posture | `rescan.yml`, step "posture invariants (Req 9.3, 9.7, 9.9)"; [`check-governance.sh`](../scripts/check-governance.sh), [`check-revocations.sh`](../scripts/check-revocations.sh) | [branch protection](user-manual.md#branch-protection), [revoke a digest](user-manual.md#revoke-a-digest) | Req 9.3, 9.7, 9.9; Decision 10: it runs last so a governance failure never starves the issues and status |

### New issues

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    IN(["Today's supported reports and the KEV feed,<br/>from the graphs above"])
    AP[/"triage.aperture<br/>Req 6.49"/]
    ENR["Enrich: EPSS for each CVE, best effort;<br/>KEV from the feed fetched above<br/>Req 6.3, 6.60"]
    DED["Dedup: the ids open cve issues carry<br/>in their hidden marker · Req 6.3"]
    REP["Build the issue set, the tested reporter:<br/>new findings within the aperture<br/>Req 6.3 · Decision 7"]
    ANY{"Any new finding?"}
    GRY["Grype second opinion on each CRITICAL,<br/>in the log · a convention, Req 9.11 to 9.13"]
    FILE["File one issue per new finding: severity,<br/>EPSS, KEV, affected images · Req 6.3"]
    NEW(["New cve issues: a person decides<br/>by pull request, a statement,<br/>an exception or a fix · Req 6.4, 6.5, 6.7"])
    NONE(["Nothing filed"])
    NOSET(["No issue set today, named · Req 6.60"])
    IN --> ENR --> DED --> REP --> ANY
    AP --> REP
    ANY -->|yes| GRY --> FILE --> NEW
    ANY -->|no| NONE
    ENR -.->|no KEV file| NOSET
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| Enrich | `rescan.yml`, step "enrich: EPSS + CISA KEV"; the EPSS API of FIRST.org, the KEV file the invariants step fetched | [rescan CVE issues](user-manual.md#rescan-cve-issues) | Req 6.3, 6.60: no issue set is built on a KEV status nobody evaluated |
| Dedup | `rescan.yml`, step "dedup: already-open CVE issues" | [rescan CVE issues](user-manual.md#rescan-cve-issues) | Req 6.3; the marker carries the scanner's id, a CVE or a GHSA advisory, never the title |
| Issue set | `rescan.yml`, step "build issue set (tested reporter)"; `cmd/rescan-report` in [`triage/rescan`](../triage/rescan/), reading the supported reports only | [rescan CVE issues](user-manual.md#rescan-cve-issues) | Req 6.3, 6.49; Decision 7: the supported set only |
| Grype | `rescan.yml`, step "Grype second opinion on CRITICAL (convention; Req 9.11 to 9.13)" | [rescan CVE issues](user-manual.md#rescan-cve-issues) | A convention beside the declared consumers of Req 9.11 to 9.13: a second scanner's reading of what is about to be filed, never a gate |
| File | `rescan.yml`, step "file new-CVE issues (Req 6.3)" | [rescan CVE issues](user-manual.md#rescan-cve-issues), [the four treatments](user-manual.md#clearing-a-red-gate--the-four-treatments) | Req 6.3; the decision after it is Req 6.4, 6.5, 6.7 |

### The status issue and the page

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    IN(["Today's attested documents, reports,<br/>KEV feed and checks, from the graphs above"])
    TRI[/"triage: aperture, ceilings, kev_ceiling,<br/>support statement · Req 6.49"/]
    PG[/"release.page<br/>Req 6.61"/]
    PREV["Read the last status issue,<br/>found by its hidden marker · Req 6.46"]
    INACT["No inactive definition gained a digest<br/>or a tag since that status<br/>Req 1.15 · Decision 11"]
    CLK["The clocks over the supported set: first seen,<br/>decided, fixed, age against the ceilings;<br/>the page drawn from the same data<br/>Req 6.46, 6.47, 6.61 · Decision 7, 12"]
    PUB(["The Catalogue status issue, edited in place,<br/>and the catalogue-status artifact · Req 6.47"])
    PON{"Page on?"}
    UP["Upload the page and its data<br/>as a Pages artifact · Req 6.61 · Decision 12"]
    DEP["Job publish the catalogue page:<br/>deploy, then read the data back<br/>until it is this run's · Req 6.61, 6.62"]
    LIVE(["The catalogue page is live"])
    OFF(["No page; the run stays green"])
    NOSTAT(["No status and no page today,<br/>the missing input named · Req 6.46, 6.47"])
    PFAIL(["The page job fails by name · Req 6.62"])
    GAIN(["The run fails, the definition<br/>and tag named · Req 1.15"])
    IN --> PREV --> CLK --> PUB
    PREV --> INACT
    TRI --> CLK
    CLK --> PON
    PG --> PON
    PON -->|yes| UP --> DEP --> LIVE
    PON -->|no| OFF
    PREV -.->|re-attestation failed above| NOSTAT
    CLK -.->|an input missing| NOSTAT
    INACT -.->|a gain| GAIN
    DEP -.->|deploy fails, or old data still served| PFAIL
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| Last status | `rescan.yml`, step "catalogue status, the previously published data (Req 6.46)"; runs only when re-attestation succeeded | [the catalogue status issue](user-manual.md#the-catalogue-status-issue) | Req 6.46: its fenced JSON carries the fix dates forward |
| Inactive definitions | `rescan.yml`, step "no inactive definition gained a digest or a tag (Req 1.15)"; [`check-inactive-digests.sh`](../scripts/check-inactive-digests.sh) | [deactivate a definition](user-manual.md#deactivate-a-definition) | Req 1.15; Decision 11, review D7: the detective half, `build.yml` holds the preventive one |
| The clocks | `rescan.yml`, step "catalogue status, the clocks over the supported set (Req 6.46)"; `cmd/rescan-status` in [`triage/rescan`](../triage/rescan/); it needs the KEV file, the revocation record, the admission proof and the expiry report, and adds the provenance line when one was measured | [the catalogue status issue](user-manual.md#the-catalogue-status-issue), [the catalogue page](user-manual.md#the-catalogue-page) | Req 6.46, 6.47, 6.49, 6.61, and the provenance line of Req 2.29, 2.30; Decision 7, 12 |
| Publish | `rescan.yml`, steps "catalogue status, published to the status issue (Req 6.47)" and "upload the status data (Req 6.47)" | [the catalogue status issue](user-manual.md#the-catalogue-status-issue) | Req 6.47 |
| Page | `rescan.yml`, step "upload the catalogue page (Req 6.61)"; the job "publish the catalogue page", steps "deploy the catalogue page (Req 6.61)" and "the served status data is this run's (Req 6.62)" | [the catalogue page](user-manual.md#the-catalogue-page) | Req 6.61, 6.62; Decision 12: an artifact, never a commit, and that job alone holds `pages: write` |

## Posture: rulesets, reporting, revocations

This lane keeps the catalogue's trust statement, [SECURITY.md](../SECURITY.md), true after it was written. Three promises in it can quietly stop being kept: the ruleset on `main` can be changed in GitHub's settings, private vulnerability reporting can be switched off, and a revoked digest can still sit under a tag. So the daily rescan checks all three in one step, "posture invariants", the last check of the run; it runs whatever failed above it, so a governance failure never keeps the day's issues and status from going out (Decision 6, review disposition D1). Its reads are anonymous, with no token, so it sees what any consumer sees. The revocation record itself is written by hand when the owner revokes a digest, and `validate` checks its shape on every pull request. The lane produces summary lines, entries in the status issue, and a failed run naming each promise not kept. It reads no value from `catalogue-policy.yaml`, so its graphs have no slanted boxes; its inputs are records committed in the repository, drawn as rounded boxes. Why this lane exists: Decision 10.

### Rulesets and private reporting

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    IN(["The daily rescan, 06:17 UTC or dispatched;<br/>this step runs last, whatever failed above"])
    RS(["The committed ruleset export<br/>.github/rulesets/main_sec.json · Req 9.8"])
    REP["Read whether private vulnerability<br/>reporting is on, anonymously;<br/>a rate-limited read waits for the reset<br/>Req 9.2, 9.3 · Decision 10"]
    ON{"Enabled?"}
    LIVE["Read the live rulesets, anonymously;<br/>a rate-limited read waits for the reset;<br/>match each committed one by name<br/>Req 9.9 · Decision 10"]
    CMP["Compare name, target, enforcement,<br/>conditions and rules, in both directions;<br/>bypass actors left out, anonymous reads<br/>withhold them · Req 9.9 · Decision 10"]
    DIFF{"A difference, a committed ruleset<br/>with no live one, or an active live<br/>branch ruleset not committed?"}
    DIS(["The run fails: reporting disabled<br/>or unreadable, named · Req 9.3"])
    RED(["The run fails, each ruleset<br/>failure named · Req 9.9"])
    OK(["Summary: reporting enabled, n rulesets<br/>compared, 0 differences, 0 live-only;<br/>the step passes when both hold"])
    IN --> REP & LIVE
    REP --> ON
    RS --> CMP
    LIVE --> CMP --> DIFF
    ON -->|yes| OK
    DIFF -->|no| OK
    ON -.->|no| DIS
    REP -.->|unreadable, or still rate limited| DIS
    LIVE -.->|unreadable, or still rate limited| RED
    DIFF -.->|yes| RED
```

The two reads do not depend on each other: a failed or disabled first read does not stop the second, and the step names every failure of the day. A rate-limited read waits for the reset GitHub names (at most 3900 seconds, twice per read) and is made again, still anonymously; a read that stays limited, or fails for any other reason, fails the run, named "unreadable".

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| The trigger | [`rescan.yml`](../.github/workflows/rescan.yml), step "posture invariants (Req 9.3, 9.7, 9.9)", `if: always()` | [the daily rescan and triage](#the-daily-rescan-and-triage) | Decision 6, the D1 correction: placed last so it never starves the issues and status |
| The committed export | [`.github/rulesets/main_sec.json`](../.github/rulesets/main_sec.json), GitHub's own export format; no workflow step checks which checks it requires, a person keeps it in line | [branch protection](user-manual.md#branch-protection) | Req 9.8; Decision 10 |
| Private reporting | the same step; [`check-governance.sh`](../scripts/check-governance.sh), the read of `private-vulnerability-reporting` | [SECURITY.md, reporting a vulnerability](../SECURITY.md#reporting-a-vulnerability) | Req 9.2, 9.3; Decision 10 |
| Live rulesets and the comparison | the same step and script, the reads of `rulesets` and of each matched ruleset by id; its tests: [`validate.yml`](../.github/workflows/validate.yml), step "check-governance unit tests (Req 9.3, 9.9)" | [branch protection](user-manual.md#branch-protection), [SECURITY.md, governance](../SECURITY.md#governance-one-maintainer-the-bypass-kept-in-force) | Req 9.9; Decision 10: bypass actors are carried by the export and stated in SECURITY.md instead |
| The rate-limit wait | the same script, `DHC_GOVERNANCE_MAX_WAIT` (3900 seconds by default) | [branch protection](user-manual.md#branch-protection) | Req 9.9 says "through anonymous reads", so the token is not used as a fallback; on such a day the rescan can take about an hour longer |
| The summary line | `rescan.yml`, step "summary", the line "governance:" | [reading job summaries](user-manual.md#reading-job-summaries) | Req 9.3, 9.9 |

### A revocation, by hand

A revocation is the owner's decision that a published digest must not be pulled any more. The registry (GHCR) has no way to delete one tag: a tag goes either with its whole package version or when another image is pushed under it. So there are two moves, and both end in one entry in [`triage/revocations.yaml`](../triage/revocations.yaml).

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    DEC(["The owner decides a published digest<br/>must not be pulled · register row M14"])
    CAN{"Can a fixed definition ship?"}
    MA["Move A: fix the definition by pull request;<br/>the release moves its three tags<br/>to the new digest · Req 2.7 to 2.9"]
    MB["Move B1: the owner deletes<br/>the package version, and every<br/>tag on it goes too · Req 9.5 · Decision 10"]
    ADV["Draft the advisory, a GitHub repository<br/>security advisory · Req 9.4 · Decision 10"]
    ENT["Add one entry by pull request: replaced,<br/>or withdrawn with the move taken;<br/>nothing is ever removed · Req 9.5 · Decision 10"]
    SCH["validate: the record fits its schema<br/>Req 9.6"]
    DONE(["Entry merged, advisory published;<br/>the daily rescan checks it from now on"])
    SFAIL(["validate fails, naming the entry and the field<br/>Req 9.6"])
    DEC --> CAN
    CAN -->|yes| MA --> ADV
    CAN -->|no| MB --> ADV
    ADV --> ENT --> SCH --> DONE
    SCH -.->|does not fit| SFAIL
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| The decision | by hand, the owner | [revoke a digest](user-manual.md#revoke-a-digest), [what GHCR can and cannot do](user-manual.md#what-ghcr-can-and-cannot-do) | Req 9.5; the manual-controls register in [CONVENTIONS.md](CONVENTIONS.md), row M14 |
| Move A | the [release](#the-release): `build.yml`, step "apply definition-derived tags" | [move A](user-manual.md#move-a-replacement-through-the-release-path) | Req 2.7 to 2.9: the revoked digest is left untagged, which is frozen (Req 2.11) |
| Move B1 | by hand: `gh api -X DELETE` on the package version; GitHub refuses it for a public version past 5,000 downloads | [move B](user-manual.md#move-b-withdrawal-nothing-replaces-it) | Req 9.5; Decision 10. Move B2, parking the tags on a signed "tombstone" image, is described in the manual and not built |
| The advisory | by hand, on the repository's Security tab | [then, whichever move](user-manual.md#then-whichever-move), [SECURITY.md, advisories](../SECURITY.md#advisories) | Req 9.4; Decision 10 |
| The entry | a pull request to `triage/revocations.yaml` | [SECURITY.md, revocation](../SECURITY.md#revocation) | Req 9.5; Decision 10: the record drives the mechanics, so the runbook stays short |
| The schema | `validate.yml`, step "revocation record (Req 9.6)": `yamale` against [`revocations.schema.yaml`](../triage/revocations.schema.yaml) | [then, whichever move](user-manual.md#then-whichever-move) | Req 9.6 |

### The daily revocation check

The rescan reads the record twice. The invariants step reads it into the list the status issue shows, and ignores the verdict there; the posture step, last, reads it again and gives the verdict, so a revocation that was only half done fails the run after the day's issues and status are out, not instead of them.

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 340}}}%%
flowchart TB
    REC(["The merged record<br/>triage/revocations.yaml · Req 9.5"])
    ENUM(["Today's enumeration: every catalogue tag,<br/>its digest and platform manifests · Req 2.22"])
    READ["invariants step: read the record<br/>into the status list, verdict ignored<br/>Req 9.5 · Decision 10"]
    LIST(["The status issue lists every entry<br/>Req 6.46"])
    HAS{"Enumeration present?"}
    VERD["posture step: match every recorded digest<br/>against each tag's index and platform manifests<br/>Req 9.7 · Decision 10"]
    REF{"A tag still on a revoked digest?"}
    OK(["Summary: n recorded,<br/>0 still referenced"])
    TAGRED(["The run fails, one line per tag: the digest,<br/>the platform, the date, the advisory · Req 9.7"])
    NOENUM(["The run fails by name:<br/>the verdict not asserted today · Req 9.7"])
    UNREAD(["Record unreadable or no list:<br/>the run fails by name"])
    ENUM --> READ --> LIST
    REC --> READ
    ENUM --> HAS
    HAS -->|yes| VERD --> REF
    REC --> VERD
    REF -->|no| OK
    REF -.->|yes| TAGRED
    HAS -.->|no| NOENUM
    VERD -.-> UNREAD
```

| Step | Runs in | Explained in | Rests on |
|---|---|---|---|
| The enumeration | `rescan.yml`, step "enumerate the catalogue (Req 2.22)" | [the daily rescan and triage](#scan-attest-and-the-issue-lifecycle) | Req 2.22; Decision 6 |
| The status list | `rescan.yml`, step "invariants (Req 2.21, 2.24, 6.44, 6.51)", [`check-revocations.sh`](../scripts/check-revocations.sh) with `\|\| true`; then step "catalogue status, the clocks over the supported set (Req 6.46)", which publishes no status when the list is missing | [the catalogue status issue](user-manual.md#the-catalogue-status-issue) | Req 9.5, 6.46; Decision 10 |
| The verdict | `rescan.yml`, step "posture invariants (Req 9.3, 9.7, 9.9)", `check-revocations.sh` again; its tests: `validate.yml`, step "check-revocations unit tests (Req 9.5 to 9.7)" | [revoke a digest](user-manual.md#revoke-a-digest) | Req 9.7; Decision 10, as built: in the posture step rather than the invariants step |
| The summary line | `rescan.yml`, step "summary", the line "revocations:" | [reading job summaries](user-manual.md#reading-job-summaries) | Req 9.7 |
