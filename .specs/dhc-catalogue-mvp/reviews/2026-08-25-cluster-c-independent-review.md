# PR #101, cluster C spec amendment: independent adversarial review, 2026-08-25

**Subject:** branch `spec-cluster-c` at `917d7e3` against `main` (merge base `0579656`,
clusters A and B merged): five files, 176 insertions, 11 deletions
(`.specs/dhc-catalogue-mvp/requirements.md`, `design.md`, `tasks.md`,
`reviews/2026-08-21-production-readiness-critique.md`,
`docs/decisions/0002-grafana-upstream-tracking.md`). The PR encodes the cluster C
decisions (critique F2, F10, F8, F13 ii and iii, F12 d) as Req 1.10 to 1.12,
Req 3.7 to 3.12 and Req 4.8 to 4.9, amendments to Req 1.3, 3.5 and 4.5, Key Design
Decision 8, five error-table rows, task group 11, dated amendment notes in the
critique, and a dated ADR 0002 amendment reversing the API-sha deferral.

## Verdict

The decision encoding is faithful and the central measured claims reproduce: the
EARS validator passes all 138 statements, every new criterion has an implementing
task and a design anchor, both git-archetype signature claims verify against the
GitHub API exactly as stated, and the grafana API-versus-sidecar "20 cases" claim
reproduces 20 for 20. The defects found concentrate elsewhere: one real internal
contradiction (the daily authenticity re-verification of Req 3.10 collides with the
F10 amendment's "standing pin stays valid" for hardened-app, whose pinned commit is
measured unsigned and cannot become signed), two scope-binding problems in Req 3.7
and the quarantine placement instruction, and four task-level mechanisms that name
tools for behaviour those tools do not have (a PR body fed by postUpgradeTask
output, a yamale schema failing on a past date, an offline fixture test asserting a
datasource's network behaviour, a helm manager description that omits the
registryUrl capture the datasource requires). None of the findings invalidates a
decision; all are fixable by rewording, one sequencing constraint, and two
mechanism swaps, before implementation starts.

**Verification legend**

| | |
|---|---|
| **[V]** | verified directly against the tree or git history, with `path:line` |
| **[M]** | measured 2026-08-25: anonymous GitHub API, grafana.com and dl.grafana.com, chart indexes, renovate 41.173.1 source and config validator, yamale 6.1.0 (script and output beside this file: `.measure.sh` / `.measure.out`) |
| **[I]** | inferred, stated as such |
| **[U]** | not measurable from this environment |

---

## 1. Findings

### 1.1 **[M][V]** Req 3.10's daily re-verification contradicts the F10 amendment's "the standing pin stays valid": hardened-app's pinned commit is unsigned and cannot become signed

**Claim.** The F10 amendment (critique:983-988) and task 11.2's operator note
(tasks.md:300) state that enforcement is at bump time and "the standing pin stays
valid" while hardened-app declares `signed-commit` now. Req 3.10
(requirements.md:94) and task 11.3 (tasks.md:306) have the rescan re-verify "each
definition's declared authenticity signal" daily, fail the run on mismatch and file
a supply-chain issue; design 8(b) repeats it (design.md:355-357). Those two
statements cannot both hold for hardened-app.

**Evidence.** Measured: `v0.1.0` on `mm-weber/hardened-app` is a lightweight tag on
commit `90a8da0c...`, whose GitHub verification statement is
`verified: false, reason: unsigned` (measure.out S3). That commit is exactly the
standing pin (`image/hardened-app/image.yaml:16,42-43`). Signing future tags (the
operator action in tasks.md:300) does not change an existing commit's verification;
only the next release, a new signed commit bumped through Req 3.8, can produce a
pin that verifies. Task 11.3's wording "verification statement still verified for
the pinned ref" presumes a verified-at-bump-time state that hardened-app's pin
never had.

**Why it matters.** The day task 11.3 lands before hardened-app's first
post-signing bump, the rescan reds daily and files supply-chain issues for a state
the same PR declares valid. A supply-chain label that cries wolf on day one
devalues the exact signal checkpoint 3 exists to carry. Alternatively, an
implementer reads "still verified" as quietly exempting hardened-app, and then
Req 3.10 overpromises what runs. Both readings are defects.

**Proposed fix.** Primary (tasks only): add a sequencing constraint to task 11.3,
"the git-archetype daily re-verification activates per definition on its first
bump whose signal verified (hardened-app: after its first bump onto a signed
commit)", and mirror one sentence in the F10 amendment note. Alternative
(criterion): reword Req 3.10 so the daily check detects regression of a verified
signal rather than asserting universal verification:

> THE Scan Pipeline SHALL re-verify at least once per day each definition's
> declared authenticity signal against its upstream origin, SHALL treat as a
> mismatch each signal that verified at bump time and no longer verifies, and
> SHALL report each mismatch as a failure of that run and file an issue naming it
> as a supply-chain signal.

(Ubiquitous pattern, no lowercase reserved keywords; passes the validator's rules.)

### 1.2 **[V][M]** Task 11.1's quarantine placement, "on the github-tags and github-releases rules", under-implements Req 3.7 on its most literal reading

**Claim.** Task 11.1 (tasks.md:294) says to put `minimumReleaseAge: "3 days"` "on
the github-tags and github-releases rules". `renovate.json5` has two github-tags
rules, and the one its Req 3.5 comment marks (renovate.json5:250-256) is scoped
`matchUpdateTypes: ["patch", "digest"]`. An age key placed there quarantines only
patch and digest updates: minor bumps of cert-manager, valkey and hardened-app
would open immediately, while Req 3.7 (requirements.md:91) withholds "each upstream
version bump pull request".

**Evidence.** renovate.json5:250-256 (the Req 3.5 automerge rule, update-type
scoped), :262-269 (the github-tags postUpgradeTasks rule, datasource-wide),
:270-286 (the github-releases rule). Measured: packageRules are applied in array
order with later matches overriding
(dist `util/package-rules/index.js:28`, measure.out S5), and a variant config
carrying two datasource-scoped rules
(`matchDatasources` only, `minimumReleaseAge: "3 days"`) passes
`renovate-config-validator --strict` (measure.out S6). So the correct placement is
trivially available; the task text just does not select it.

**Why it matters.** xz-utils shipped as routine-looking releases; the minor is a
version class an attacker also controls, and it is the class the ambiguous
placement exempts. A reviewer of the implementation PR would have to re-derive the
intent from Req 3.7 against a task that reads as satisfied.

**Proposed fix.** Reword the 11.1 bullet: "two datasource-scoped packageRules
(matchDatasources alone, no matchUpdateTypes), one per version datasource, each
carrying minimumReleaseAge \"3 days\"; not the update-type-scoped Req 3.5 automerge
rule".

### 1.3 **[V][M]** Req 3.7's scope term matches the delivered scope in neither direction: chart, npm, go and pypi bumps are outside the design, and the github-releases rule sweeps in the six tool pins unstated

**Claim.** Req 3.7 withholds "each upstream version bump pull request". Design 8(a)
(design.md:345-347) ages exactly two datasources, github-tags and github-releases.
Read broadly, the criterion also covers chart-version bumps (Req 3.11's helm
datasource, which supplies `created` timestamps, measured), the renovate and json5
npm pins, govulncheck's go pin and the four pypi pins: none of them aged by the
design. Read narrowly (definition source bumps only), the github-releases rule
still quarantines the six workflow tool pins, trivy, grype, kind, kyverno, helm
and ct, whose `# renovate:` markers declare `datasource=github-releases`
(scripts/install-scanners.sh:55,59; scripts/install-tool.sh:56-68), and neither
the design's trade-offs (design.md:368-371 names only "every from-source patch")
nor CONVENTIONS' planned rows state that three-day scanner delay.

**Evidence.** File lines above; helm datasource `releaseTimestampSupport = true`
and per-entry `created` present in all three live indexes (measure.out S5, S8);
the workflow-env manager's npm and go pins at validate.yml:92-94 and
build.yml:498-499.

**Why it matters.** A criterion whose universal quantifier does not match the
mechanism invites both false confidence (chart and toolchain bumps assumed
quarantined) and surprise cost (a malicious-release window argument, CVE-2026-33634
was a malicious trivy release under adopted version numbers, actually supports
aging the scanners, but the spec should say it is doing so). This catalogue's own
standard is that scope is declared, not implied.

**Proposed fix.** Bind the criterion to the delivered scope and state the sweep in
the design. EARS rewording of Req 3.7:

> THE Renovate Automation SHALL withhold each pull request bumping a pinned
> upstream release resolved from a GitHub tags or GitHub releases datasource until
> that release has aged a declared minimum release age, at least three days in
> this catalogue.

Add one design trade-off sentence: the github-releases age also delays the six
tool-pin bumps three days (named as intended, with the CVE-2026-33634 rationale),
and chart-version bumps are exempt because they are never automerged and always
reviewed. Alternatively widen the config (helm, npm, go, pypi rules) and keep
Req 3.7 as written; the helm side is one rule since the datasource supplies
timestamps.

### 1.4 **[M]** "The signer identity or agreeing origins from the check go into the bump PR body via the refresh output" names a mechanism Renovate does not have

**Claim.** Task 11.2's fourth bullet (tasks.md:302) routes the verification
evidence into the PR body "via the refresh output". Measured against the pinned
renovate 41.173.1: a postUpgradeTask's exec result goes to `logger.debug` only
(dist `workers/repository/update/branch/execute-post-upgrade-commands.js:95-96`);
only a FAILING command's stderr reaches the PR, as an artifact-error block
(:99-103). No succeeding command's stdout reaches the PR body, and `prBodyNotes`
is a static template that cannot carry run output.

**Evidence.** measure.out S5; the F2(b) decision text the task encodes
(critique:926, "the signer or agreeing origins go into the bump PR body").

**Why it matters.** The one consumer-visible artifact of the whole signal check,
the reviewer-facing evidence line, silently never appears, and nothing fails: the
exact inert-versus-correct failure mode this repo documents elsewhere.

**Proposed fix.** Have the refresh write the evidence into a file the diff carries,
which `fileFilters` already covers: a checksum-provenance comment line the refresh
rewrites beside the pin in `image.yaml` (both refresh scripts already rewrite that
file), for example `# authenticity: signed-tag, verified v1.21.1 tag object
99224164 (GitHub verification: valid), 2026-08-25`. The PR diff then carries the
signer statement, which reviewers see where they look, and task 11.2's bullet
should say so instead of "PR body".

### 1.5 **[M]** A yamale schema cannot fail "past the review-by date": day() constraints are static literals

**Claim.** Task 11.4 (tasks.md:311) and design 8(d) (design.md:361-364) say a
yamale schema validates the `compat:` block "and fails validation past the
review-by date". Measured on the pinned yamale 6.1.0: the `day` validator's only
constraints are Min and Max with values baked into the schema text as literals
(and the literal must be quoted; an unquoted ISO date is a schema syntax error).
No validator compares against the current date; grep for today/now across the
validator sources returns nothing (measure.out S7).

**Evidence.** measure.out S7: `day(max="2026-08-24")` correctly fails a 2026-09-30
value and passes 2026-08-01, proving the static form works and only the static
form exists.

**Why it matters.** Req 4.8's mechanism, the criterion that forces re-decision, is
attributed to a tool that cannot provide it; an implementer discovers this
mid-task and improvises placement.

**Proposed fix.** Split the sentence in 11.4 and design 8(d): yamale validates the
block's shape (reason, upstream issue reference, review-by as `day()`); the
past-date comparison is one date test in the validate lint, reusing the pattern
`lint-accepted-risk.sh` already implements for `expired_at` (one implementation of
"lapsed", the same argument that script's comment makes). The custom-validator
route exists only through yamale's Python API, not its CLI.

### 1.6 **[V]** Req 1.12's deb shape contradicts the repo's own terms memo

**Claim.** Req 1.12 (requirements.md:42) mandates
`dhi.io/deb/(distro)/(release)/main`. The memo the rule encodes records Docker's
parallel Debian example as `https://dhi.io/deb/debian/main`, with no release
segment (data/dhi-terms-2026-08-21.md:87).

**Evidence.** File lines above; all seven definitions are apk `/main` (measured
grep, measure.out S9), so the deb arm is latent; ADR 0001 and CONVENTIONS record
the deb path as unverified.

**Why it matters.** A lint implementing 1.12 as written would reject the one deb
path the memo documents as legitimate, on the day a deb definition first lands,
which is exactly when nobody will remember why the shape was guessed.

**Proposed fix.** Match the memo or drop the unmeasured arm:

> IF a definition names a dhi.io package repository whose path is not of shape
> dhi.io/apk/(distro)/(release)/main or dhi.io/deb/(distro)/main THEN THE CI
> Pipeline SHALL fail validation naming that repository.

(Error-handling pattern preserved; no lowercase reserved keywords.)

### 1.7 **[M]** Task 11.1's test promise cannot be measured by that harness, and the quarantine silently waives itself without timestamps under the default behaviour

**Claim.** Task 11.1 (tasks.md:296) promises "managers.test.mjs asserts
github-tags supplies release timestamps". That file is an offline regex-extraction
emulation (test/renovate/managers.test.mjs:1-11); a datasource's timestamps are a
network behaviour it cannot observe. Separately, measured in filter-checks.js: with
the default `minimumReleaseAgeBehaviour: "timestamp-optional"`, a release without
a releaseTimestamp bypasses the age check with only a once-per-run warning
(dist `workers/repository/process/lookup/filter-checks.js:66-70`).

**Evidence.** measure.out S5: `GithubTagsDatasource` maps tag `committedDate` to
`releaseTimestamp` and declares `releaseTimestampSupport = true` (github-releases
likewise from `publishedAt`); `timestamp-required` is an allowed value and a config
carrying it validates (S6).

**Why it matters.** As written, the task's assertion is either dropped at
implementation or faked; and the default behaviour means the quarantine's failure
mode is silence, the property this repo repeatedly designs out.

**Proposed fix.** Two concrete swaps in 11.1: assert the pinned renovate's own
datasource classes offline, `new GithubTagsDatasource().releaseTimestampSupport
=== true` (same pattern as the existing versioning assertions against
renovate/dist, which the file already justifies at managers.test.mjs:243), and set
`minimumReleaseAgeBehaviour: "timestamp-required"` on the two age rules so a
missing timestamp is pending, not a silent pass.

### 1.8 **[M][V]** The chart-version manager needs `upstream.repository` captured as registryUrl; the task lists the key but not the mechanism, and the helm default registry is a decoy

**Claim.** Task 11.4 (tasks.md:309) and the F13 amendment (critique:1161-1164)
name `upstream.name`/`upstream.repository`/`upstream.version` but never say the
repository must become the dependency's `registryUrl`. The helm datasource's
default registry is `https://charts.helm.sh/stable` (dist
`modules/datasource/helm/index.js:16`), a frozen legacy index, so a manager that
captures only depName and currentValue resolves against the wrong registry and
reports nothing, the silent-nothing failure the repo's own manager tests exist to
catch.

**Evidence.** Measured: regex managers support a `registryUrl` capture field (dist
`modules/manager/custom/regex/utils.js:16`); one matchString over the `upstream:`
block captures all three fields from the three real chart.yaml files, does not
match `chart/hardened-app/Chart.yaml` (capital C, so the own-authored chart is
excluded by case alone), and the resulting config validates (measure.out S6).
Index spellings compare natively: jetstack lists `v1.21.0`/`v1.21.1` (v-prefixed,
as pinned), grafana and valkey bare (S8). Two operational notes worth carrying into
the task: valkey's index URL 301-redirects to `valkey.io/valkey-helm` (the
datasource follows it), and jetstack already lists `v1.21.1`, so the manager opens
a real cert-manager chart bump, running the e2e upgrade path, on its first run.

**Why it matters.** The one omitted word (registryUrl) is the difference between a
working manager and one that "runs" while tracking nothing against a graveyard
registry.

**Proposed fix.** In 11.4: "upstream.repository captured as `registryUrl` (the
helm datasource's default registry is charts.helm.sh/stable, a decoy); fixtures
assert the three captures, the Chart.yaml non-capture, and that the captured
registryUrl is the chart's repository".

### 1.9 **[V]** The F13 amendment misdates the chart-pin managers: they landed 2026-08-13, not 2026-08-14

**Claim.** The amendment (critique:1159-1160) says "The task 8.7 chart-pin
managers landed 2026-08-14".

**Evidence.** `git log -S 'values-hardened' -- renovate.json5` shows exactly one
commit introducing the chart-pin manager patterns: `f3b5f87`, 2026-08-13
(measure.out S9), and tasks.md:208 itself records "2026-08-13 done (#64)". The
2026-08-14 commit (`5eb21cc`) added the pip manager and helm/ct pins.

**Why it matters.** Small, but this document is the decision record, and its value
is dated precision; the tree already carries the correct date twice.

**Proposed fix.** "landed 2026-08-13".

### 1.10 **[V]** Req 3.8's "that definition's" has no antecedent

**Claim.** Req 3.8 (requirements.md:92) opens "WHEN a refresh task recomputes a
checksum or resolves a commit for a bump" and then binds "that definition's
declared authenticity signal": no definition was introduced.

**Evidence.** The criterion's own text; every other "that X" in the amended
criteria resolves to a noun in its sentence.

**Why it matters.** The binding rule is what keeps EARS criteria testable; this one
currently leans on the reader knowing bumps happen to definitions.

**Proposed fix.**

> WHEN a refresh task recomputes a checksum or resolves a commit for a
> definition's bump THE Refresh Tooling SHALL verify that definition's declared
> authenticity signal and SHALL write no field of a bump whose signal fails
> verification, reporting each such refusal naming its signal.

(One word group changed; validator-clean.) Optionally, name THE Refresh Tooling in
design Components (the two refresh scripts) since this criterion introduces the
actor.

### 1.11 **[V][M]** Req 3.12's "its e2e upgrade path among them" is unbound, and required-check membership is out-of-tree state with no cluster C guard

**Claim.** Req 3.12 (requirements.md:96) ends "gated on green required checks, its
e2e upgrade path among them": no antecedent resolves "its" (the pull request's?
the catalogue's?), and which checks are required is a live GitHub ruleset no
cluster C task creates or lints (ruleset-as-code is cluster D, F1).

**Evidence.** Measured today: the `main_sec` ruleset's required checks now include
`e2e gate` and `build gate` (anonymous rules API, measure.out S2), so the
criterion currently holds and tasks.md:310's "(e2e gate among them since
2026-08-21)" is confirmed; the section 6 operator action was done. Until cluster D
lands there is nothing in the tree that notices the setting reverting.

**Why it matters.** A criterion that asserts a hand-flipped setting is the F13
pattern this review cycle exists to retire; at minimum the dependence should be
explicit.

**Proposed fix.** Split actor and setting:

> WHERE a pull request contains solely digest updates of catalogue image pins
> under chart/ THE Renovate Automation SHALL enable automerge gated on green
> required checks.

and, if the e2e membership must be normative now, add an actor-correct criterion
(noting its drift guard arrives with cluster D's ruleset-as-code):

> THE Repository SHALL require its build gate and its e2e gate as status checks on
> its default branch.

### 1.12 **[V]** The requirements Introduction's amendment record stops at cluster B

**Claim.** The introduction (requirements.md:20-21) enumerates what clusters A and
B added and amended; this PR adds cluster C's criteria without extending that
record, breaking the established per-cluster pattern.

**Evidence.** The diff touches requirements.md only inside Req 1, 3 and 4.

**Why it matters.** The intro is how a reader dates a criterion without git; the
pattern is only useful while it is complete.

**Proposed fix.** Append: "Cluster C (findings F2, F10, F8, F13 ii and iii, F12 d:
upstream trust) added Req 1.10 to 1.12, Req 3.7 to 3.12 and Req 4.8 to 4.9, and
amended Req 1.3, 3.5 and 4.5; its spike record is the 2026-08-25 amendment to
ADR 0002."

### 1.13 **[V]** `none` is refused everywhere, but the standing decision text says "for new definitions", and the widening is unrecorded

**Claim.** The critique's F2(b) and F10 decision texts (critique:924-925, 975) say
`none` is "refused for new definitions". Req 1.11 and design 8(b) fail every
definition declaring `none` or nothing. The strengthening is right (all seven
definitions get real classes in task 11.2), but the 2026-08-25 amendment notes do
not record it, so critique and criteria disagree for a reader reconciling them.

**Evidence.** File lines above; requirements.md:41; design.md:349.

**Why it matters.** The critique's amendment notes exist precisely to keep the
decision record equal to the criteria.

**Proposed fix.** One clause in the F10 amendment note: "`none` is refused for
every definition, not only new ones; every current definition carries a real
class, so nothing is grandfathered."

---

## 2. Checked and held

Recorded so the findings read as aimed at the gaps.

- **EARS validity**: `node .claude/skills/ears-notation/scripts/ears-validator.js
  .specs/dhc-catalogue-mvp/requirements.md` passes, 138 valid statements, exit 0.
- **The measured-basis claims reproduce.** cert-manager `v1.21.1` is an annotated
  tag whose GitHub verification statement is `verified: true` ; valkey `9.1.1` is a
  lightweight tag on commit `d27f9ba...`, `verified: true`, and that commit equals
  the pinned `COMMIT_SHA`; grafana versions-API sha256 equals the dl.grafana.com
  sidecar in all 20 cases (five versions, four arches; armv6/armv7 are the
  `linux_arm-6`/`linux_arm-7` filenames) and the 13.1.3 amd64/arm64 values equal
  the pins at image/grafana/image.yaml:33.
- **Coverage is complete.** Req 1.10/1.11/1.12 and 3.8 to task 11.2; 3.5/3.7 to
  11.1; 3.9/3.10/4.9 to 11.3; 3.11/3.12/4.5/4.8 to 11.4; 7.1 to 11.5; the
  coverage table rows gained exactly those tasks; error-table rows exist for
  3.8, 3.9, 3.10, 4.8/4.9 and 1.12; the ADR 0002 amendment and the valkey
  upstream-ask draft are both delivered by the diff or task 11.4. No artifact is
  promised without a task (SECURITY.md's copy is explicitly deferred to cluster D).
- **The as-built claims in the amendment notes are true** (except 1.9): the
  refresh cross-checks three build-id sources and refuses on conflict
  (refresh-grafana.sh:128-133); the API sha is fetched today and unused as a pin
  (:178-186), so checkpoint 1 adds exactly the comparison the note says; the
  commit sha is resolved at bump time (refresh-definition.sh:45), matching the
  F2(c) comment claim; the hand-feed seam is real (refresh-grafana.sh:189-192);
  chart versions are hand-pinned with the gap comment the design cites
  (chart/cert-manager/chart.yaml:3-6); `hardened-app`'s chart is own-authored
  helm-native `Chart.yaml`, correctly excluded by the lowercase pattern; grafana's
  version-skew note exists as cited (chart/grafana/chart.yaml:6-14).
- **The error-table row for Req 3.8/7.4 is mechanically true**: a refused refresh
  leaves Renovate's one-line edit, and `lint-pins.sh`'s coherence pass compares
  every three-part version token in `url:` values against the declared VERSION
  (lint-pins.sh:249-263), so both archetypes' partial edits go red in validate.
- **"Gated on green required checks" is the accurate phrase**: platformAutomerge
  defaults true (GitHub auto-merge, which waits on required checks), and the
  required checks on `main` now include `build gate` and `e2e gate` (measured),
  confirming tasks.md:310's "since 2026-08-21" parenthetical.
- **yamale is already pinned in CI** (requirements-ci.txt:22-25, installed in
  validate.yml:21-23), as task 11.4 states; memo Q4 matches design 8(e) for the
  apk path; all seven definitions use `dhi.io/apk/alpine/v3.23/main`.
- **packageRules ordering** behaves as the F13 amendment and task 11.4 assume:
  rules apply in array order, later matching rules override, so the dhi.io
  `automerge: false` rule kept last wins over an earlier chart automerge rule.
- **Requirement numbering** continues each group exactly as section 6 planned
  (next free was 1.10, 3.7, 4.8).

## 3. Method

**Read** (worktree `spec-cluster-c` at 917d7e3): the full diff against main; the
amended `requirements.md`, `design.md`, `tasks.md`; the critique's F1, F2, F8,
F10, F12, F13, sections 5.2, 5.3 and 6 with the 2026-08-25 amendment notes; ADR
0002 end to end; `docs/CONVENTIONS.md`; `renovate.json5`;
`test/renovate/managers.test.mjs`; `scripts/refresh-definition.sh`,
`refresh-grafana.sh`, `verify-arch-pins.sh`, `lint-pins.sh`; the four chart.yaml
files and the grafana/valkey chart READMEs; `image/{grafana,hardened-app,valkey,
cert-manager-controller}/image.yaml` plus a dhi.io-path grep over all seven;
`.github/workflows/{renovate,validate,rescan,e2e}.yml` and build.yml's gate and
pin lines; `.github/requirements-ci.txt`; `data/dhi-terms-2026-08-21.md`; the
cluster A and B independent reviews for house conventions.

**Measured** (2026-08-25, commands and outputs in `.measure.sh` / `.measure.out`
beside this file): the EARS validator; anonymous GitHub API reads (repo rulesets
and required checks; tag object and commit verification statements for
cert-manager v1.21.1, valkey 9.1.1, hardened-app v0.1.0); grafana.com versions API
against dl.grafana.com sidecars for 13.0.4, 13.0.6, 13.1.1, 13.1.2, 13.1.3 on
amd64, arm64, armv6, armv7 (20 comparisons); renovate 41.173.1 (the version
validate.yml pins) installed from npm, its dist read for releaseTimestamp support
per datasource (github-tags, github-releases, helm), minimumReleaseAge filtering
and the timestamp-optional default, packageRules ordering, the regex manager's
registryUrl field, postUpgradeTask output handling, the platformAutomerge default;
`renovate-config-validator --strict` on the repo config and on a
cluster-C-shaped variant (datasource-scoped age rules, helm regex manager,
chart digest automerge rule), plus offline extraction emulation of that helm
manager against the three real chart.yaml files; yamale 6.1.0's day() semantics
(static min/max, quoted literals, no dynamic today); the three chart indexes'
version spellings, `created` fields and the valkey 301 redirect; git history for
the chart-pin manager landing date.

**Not measured, and why.** Whether GitHub's tag/commit `verified` statement
regresses when a signer's key is later removed or expires (needs a controlled repo
and key rotation; relevant to the Req 3.10 rewording in 1.1, marked inferred that
revocation detection is the intent). The 2026-08-21 state of dl.grafana.com
(historical; today's 20 for 20 agreement is what is reproducible). Ruleset bypass
actors (not anonymously readable, already [U] in the critique). A live end-to-end
Renovate run with minimumReleaseAge against this repository (needs the operator
PAT; the config validation plus source reading above is the strongest measurement
available here). Whether GitHub Actions runners resolve the valkey.io redirect
identically (assumed; no firewall there).
