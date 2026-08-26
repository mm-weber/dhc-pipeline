# PR #104, final cleanup spec amendment: independent adversarial review, 2026-08-25

**Subject:** branch `spec-cleanup` at `53907ea` against `main` (merge base
`da5621e`, clusters A to D and the greenfield decision merged): four files,
73 insertions, 13 deletions (`.specs/dhc-catalogue-mvp/requirements.md`,
`design.md`, `tasks.md`, `reviews/2026-08-21-production-readiness-critique.md`).
The PR encodes the 5.1 framing addendum's three commitments as Req 1.13 to
1.17, amendments to Req 1.1, 2.2, 2.7, 2.21, 2.23, 4.1, 5.5 and 7.7, Key
Design Decision 11, two error-table rows, task group 14, an intro sentence,
and a dated "encoded" note under the addendum. It is stated to be the last
spec amendment before implementation.

## Verdict

The parameterization itself lands clean: the EARS validator passes all 161
statements, no registry or owner literal survives in any criterion (measured:
zero matches for the namespace in requirements.md; component names appear
only in Req 1.1's intended reference set), each of the five new criteria has
an implementing task and a design anchor, and task 14.2's three mechanisms
measure implementable (matrices from a policy file via the job-output plus
fromJSON pattern build.yml and e2e.yml already use; the pinned Renovate
41.173.1 carries `ignorePaths`, `packageRules` with `matchFileNames` plus
`enabled`, and `ignoreDeps` for a rendered, drift-checked ignore list). The
defects concentrate in one place: the deactivation semantics are encoded
against a spec whose standing criteria still quantify over every definition
and every chart. Req 2.14 rebuilds every definition daily and Req 2.16 then
mandates publishing the first drifted rebuild, so deactivating one definition
puts two unconditioned SHALLs into mandatory violation within days; Req 3.2,
3.3 and 3.11 mandate opening the bump PRs Req 1.16 mandates failing, and the
mandated monorepo grouping plus the variant-parity lint wedge every active
sibling of an inactive one; amended Req 4.1 predicates on a declaration
("an active definition declares an upstream chart") that no artifact makes
and no task creates, detaching the never-modify-upstream rule from all three
adapted charts; the merge path still tags an inactive definition's image
through the 2.1 chain because 1.16 blocks bumps only; and the probe and
matrix planes are keyed by chart-backed component (four) while the active
set is keyed by definition (seven), with no declared mapping and three
definitions that have no standalone workload to probe. All of it is fixable
by rewording before implementation: fifteen replacement criteria are
proposed below and all validate.

**Verification legend**

| | |
|---|---|
| **[V]** | verified directly against the tree, with `path:line` |
| **[M]** | measured 2026-08-25: EARS validator runs; anonymous api.github.com reads of renovate 41.173.1 source and renovatebot/github-action v43.0.9 (script and output beside this file: `.measure.sh` / `.measure.out`) |
| **[I]** | inferred, stated as such |
| **[U]** | not measurable from this environment |

---

## Findings

### 4.1 (High) **[V]** The daily rebuild chain mandates publishing what the active set forbids: Req 2.14 rebuilds every definition, Req 2.16 then publishes the first drifted rebuild, against Req 1.14 and 1.15, and task 9.2 still lists every definition

**Claim.** Req 2.14 (requirements.md:70) reads "rebuild every definition on a
declared schedule at least once per day"; Req 1.14 (requirements.md:44)
derives the build matrix solely from the active set. The moment the active
set is a proper subset of the definitions on disk, the two cannot both hold:
a schedule matrix containing an inactive definition violates 1.14, one
excluding it violates 2.14. Neither wins as written, both are unconditioned
ubiquitous criteria. Nor is there a rebuild-and-discard escape: if 2.14 is
read as prevailing and the inactive definition rebuilds anyway, Req 2.15
(requirements.md:71) discards only the equal-package-set case, and Req 2.16
(requirements.md:72) mandates publishing through criteria 2.7 to 2.9 the
first time the resolved package set drifts, which apk's declared float
(Req 1.9, requirements.md:39) makes a matter of days. That publication is
exactly what Req 1.15 (requirements.md:45) forbids. So a deactivation does
not merely waste a daily build; it manufactures a mandatory violation of
1.15 (or of 2.14, or of 1.14) on a short fuse.

**Evidence.** requirements.md:44, 45, 70, 71, 72, 39. Design intent:
design.md:496-500, "a definition outside the active set gets no new digest
(1.15)". Task ledger: tasks.md:224 (task 9.2) still specifies "building
every definition" and "The `changes` job gains a schedule branch that lists
every definition", unamended by this PR, while tasks.md:366 (task 14.2)
derives the same matrix solely from `active_set`; an implementer executing
the groups in order builds the every-definition schedule branch under 9.2
and contradicts it under 14.2. The conflict is invisible in the reference
instance because task 14.1 activates all seven definitions (tasks.md:363);
it manifests on the first fork or first deactivation, which is the case the
amendment exists for.

**Why it matters.** Deactivation is the amendment's headline mechanism and
2.14 is one of the three criteria Req 7.7 names as the source of declared
release settings; leaving them in contradiction means the first deactivated
definition either keeps minting published digests (1.15 broken) or silently
drops out of a criterion the policy file's own schedule section cites.

**Proposed fix.** Amend 2.14 to: "THE CI Pipeline SHALL rebuild every
definition in its declared active set on a declared schedule at least once
per day." (validates; 7.7's reference to 2.14's release settings is
unaffected). Amend task 9.2's two "every definition" phrases to "every
active definition", or add one line noting 14.2 narrows them.

### 4.2 (High) **[V]** Amended Req 4.1 predicates on a declaration no artifact makes: definitions never declare charts, so the WHERE clause is vacuously false everywhere and the never-modify-upstream rule binds nothing

**Claim.** Amended 4.1 (requirements.md:109) reads "WHERE an active
definition declares an upstream chart THE Chart Adaptation SHALL consume
that chart at a pinned version without modifying upstream templates". No
definition declares a chart: measured, no `chart:` key exists in any
`image/*/image.yaml` (every occurrence of the word is a comment or the
valkey-compat description label value), and the upstream-chart declaration
lives on the other side, in `chart/<name>/chart.yaml`'s `upstream:` block,
owned by the Chart Adaptation (chart/cert-manager/chart.yaml:7-10,
chart/grafana/chart.yaml:3, chart/valkey/chart.yaml:3; design.md:620). No
task in group 14 adds a chart field to definitions (tasks.md:361-373 read in
full). A WHERE criterion whose feature can never be present binds nothing:
as amended, the pinned-version rule and the upstream-templates-never-modified
rule detach from all three adapted charts. The old wording named the three
charts and bound them; the amendment replaced an over-specific antecedent
with a nonexistent one.

**Evidence.** requirements.md:109; measure.out S4 (no `chart:` key in any
definition); chart/cert-manager/chart.yaml:7-10; design.md:619-624 (the
chart adaptation holds the pinned upstream; hardened-app's owned chart is
explicitly outside Req 4.1).

**Why it matters.** Req 4.1 is the anti-fork guardrail the design itself
leans on: Decision 8's Rejected list dismisses "vendoring a patched valkey
chart" as a violation of Req 4.1 (design.md:391). A vacuous 4.1 deletes the
criterion that rejection cites, and Req 3.11's chart tracking loses the
criterion that defines what an upstream chart is.

**Proposed fix.** Anchor the clause on the artifact that really declares:
"WHERE a chart adaptation deploying an active definition's images pins an
upstream chart THE Chart Adaptation SHALL consume that chart at its pinned
version without modifying upstream templates." (validates). hardened-app's
owned chart pins no upstream chart and stays correctly outside; the three
adapted charts are bound again, now scoped to active definitions as
intended. The alternative, adding a chart declaration to the definition
schema, is motivated by no recorded decision and would put a chart fact in
an artifact the builder contract (Req 1.17) says takes only a definition
directory.

### 4.3 (High) **[V]** Upstream tracking is mandated to open pull requests validation is mandated to fail: Req 3.2, 3.3 and 3.11 still quantify over all definitions and charts, and the mandated monorepo grouping plus the variant-parity lint wedge every active sibling of an inactive one

**Claim.** Three standing criteria collide with the new ones. (i) Req 3.2
(requirements.md:91) mandates a bump PR "WHEN an upstream release matches a
definition's version policy", any definition; for an inactive one, Req 1.14
removed it from the tracking scope and Req 1.16 (requirements.md:46)
mandates failing exactly that PR. (ii) Req 3.11 (requirements.md:100)
tracks "each upstream chart version pinned under chart/"; an inactive
component's chart directory remains (Decision 11 rejects deleting inactive
directories, design.md:514-517), so 3.11 mandates chart-bump PRs that 1.14
descopes, that 1.16 does not catch (it covers definitions, not charts), and
whose Req 5.6 upgrade run the active-set test matrix no longer contains.
(iii) The wedge: Req 3.3 (requirements.md:92) mandates grouping monorepo
bumps into a single PR, so with cert-manager-webhook inactive, the mandated
grouped PR bumps an inactive definition and 1.16 mandates failing it:
controller and cainjector can never bump again. The valkey pair is wedged
the same way by the variant-parity lint, which requires byte-equal source
pins across the two definitions publishing one repository
(scripts/lint-pins.sh:273-311): bump valkey alone and parity fails the
convention gate (Req 7.4); bump both and 1.16 fails the PR. No criterion,
design line or task requires the active set to be closed under monorepo
groups or runtime/variant pairs, so these wedge states are reachable by one
edit to the policy file. (A side note for the record: design.md:612-613
credits lint-pins.sh with byte-equal enforcement across the cert-manager
trio, but the script keys parity on a shared published repository and its
own comment says the trio is "correctly not a pair"; the trio's lockstep is
actually carried by Req 3.3's grouping plus the shared depName,
renovate.json5:217.)

**Evidence.** requirements.md:91, 92, 100, 44, 46, 130;
scripts/lint-pins.sh:273-311; renovate.json5:217 (monorepo group), 230
(valkey pair group), 242 (chart-pin trio group); design.md:514-517. A
further consequence worth one documentation line: Req 6.5's fix lane
(requirements.md:143) produces a version-bump PR, which 1.16 fails for an
inactive definition, while Decision 11 keeps issues running over its
published tags; a deactivated definition's findings therefore have no fix
path, only not_affected, acceptance, transfer, or retention. That is
defensible (deactivation is the avoid treatment writ large) but nowhere
stated; task 14.4's deactivation-semantics text should say it.

**Why it matters.** The design's own trade-off note concedes Renovate
cannot read the policy file and accepts validation as the backstop, but as
specified the backstop and the tracker are both mandatory and opposed: a
fork that deactivates one cert-manager image bricks the other two's bumps,
and every renovate run re-opens PRs whose only fate is a red check.

**Proposed fix.** Scope the tracking criteria: 3.2 becomes "WHEN an
upstream release matches an active definition's version policy THE Renovate
Automation SHALL open a pull request updating pinned ref, checksum, and
derived tags."; 3.11 becomes "THE Renovate Automation SHALL track each
upstream chart version pinned under chart/ for an active definition against
its chart repository and SHALL open a pull request, never automerged, for
each new chart release matching its version policy." (both validate). Add a
coherence criterion with a 14.2 lint line: "IF that active set splits a
definition group whose source pins are enforced byte-equal or whose bumps
are grouped under criterion 3.3 THEN THE CI Pipeline SHALL fail validation
naming that group." (validates). Extend 1.16 to inactive charts or state
chart-bump handling in 14.2, for example: "IF a pull request bumps a
definition outside that active set or a chart adaptation deploying no
active definition THEN THE CI Pipeline SHALL fail validation naming that
definition or that chart adaptation." (validates).

### 4.4 (Medium) **[V]** Req 1.14's "solely" is satisfiable by no standing matrix: every matrix is change-scoped by criteria 2.1 and 5.2 and by the measured workflows, and chart.yml has no matrix at all, its every-chart gating a recorded decision task 14.2 silently reverses

**Claim.** "Derive its build matrix, its chart and test matrices and its
upstream tracking scope solely from that active set" (requirements.md:44)
has two readings. The strict one, the matrix as a function of the active
set alone, contradicts Req 2.1's "affected images" (requirements.md:57),
Req 5.2's "each affected chart" (requirements.md:126), and the measured
mechanics: build.yml computes its matrix from the git diff
(build.yml:57-101) and e2e.yml from a changed-paths scan (e2e.yml:53-70),
both feeding fromJSON matrices (build.yml:117-120, e2e.yml:82-85). The
intended reading, the active set as the sole source of candidate
definitions with change detection narrowing it, is not what the sentence
says, and the design elevates the word to load-bearing status ("a switch
nothing reads is decoration, so 'solely' in 1.14 is the criterion",
design.md:508-510), so its testability matters more than average.
Separately, chart.yml has no matrix to derive: it loops `chart/*/`
(chart.yml:45, 63) on every PR, a recorded deliberate decision ("every
chart on every PR, no changed-chart scoping", tasks.md:82); task 14.2
asserts "chart.yml and e2e.yml's chart matrices" derive from the active set
(tasks.md:366), reversing that recorded decision without noting it, and
leaving open whether an inactive component's chart keeps its render-and-
policy gate (cheap validation that stops the reference tree rotting) or
loses it (deactivation means untested).

**Evidence.** requirements.md:44, 57, 126; build.yml:38-120; e2e.yml:33-85;
chart.yml:41-72; design.md:508-510; tasks.md:82, 366.

**Why it matters.** The criterion the design calls the whole point of the
active set cannot be checked as written without failing the affected-
scoping that three other criteria mandate; an implementer must privately
choose a reading, which is the drift the aperture lesson is about.

**Proposed fix.** Reword 1.14 to the membership form: "THE CI Pipeline
SHALL read that active set as its sole source of candidate definitions for
its build matrix, its chart and test matrices and its upstream tracking
scope, and SHALL admit no definition outside that active set into any of
them." (validates). Add one line to 14.2 deciding the chart-gate question
either way (gate every chart directory as validation, or scope it with the
matrices) so the reversal of task 5.5's recorded decision is itself
recorded.

### 4.5 (Medium) **[V]** The merge path still publishes an inactive definition: Req 1.16 blocks bumps only, a non-bump change merges, Req 2.1 builds it and 2.7 to 2.9 chain to a mandated tag, and 1.15's "publish no new digest" reads two ways against Req 2's defined vocabulary

**Claim.** Req 1.16 fails a PR that "bumps" an inactive definition; a
non-bump change (an authenticity marker, a schema migration, a comment or
repo-wide refactor, the exact class task 11.2 lands on every definition)
merges freely. Req 2.1 (requirements.md:57) then mandates building the
affected image, Req 2.7 (requirements.md:63) fires "from a merged
definition change" and pushes by digest, and Req 2.9 (requirements.md:65)
mandates signing and applying the definition-derived tags once the scan
completes and 2.13 does not withhold: a published digest under Req 2.10,
directly against Req 1.15. And 1.15's own verb is loose against Req 2's
defined vocabulary: "publish no new digest" (requirements.md:45), read with
2.10/2.11 (requirements.md:66-67), permits pushing new untagged digests
forever, since an untagged push is frozen, not published; Decision 11's
intent is stronger, "gets no new digest" (design.md:497-498). Under that
loose reading a deactivated definition could keep accreting frozen strata
daily, the exact babysitting Decision 9 restarted the registry to shed.

**Evidence.** requirements.md:46, 57, 63, 65, 66-67, 45; design.md:497-498;
tasks.md 11.2 (marker rollout as a non-bump definition edit).

**Why it matters.** The deactivation contract should hold against ordinary
maintenance commits, not only against Renovate; as written one housekeeping
sweep re-publishes every inactive definition.

**Proposed fix.** Scope 2.1: "WHEN a definition change merges to main THE
CI Pipeline SHALL build each affected active definition's images for every
platform its definition declares." (validates; 2.7 and 2.9 are conditioned
on a build or a push and need no change once nothing builds). Tighten 1.15
to the design's intent: "WHILE a definition sits outside that active set
THE CI Pipeline SHALL push no new digest for it and SHALL apply no new tag
for it." (validates).

### 4.6 (Medium) **[V]** Req 3.10's daily authenticity re-verification keeps running against inactive definitions' upstreams: the compromised-or-vanished upstream case, a primary reason to deactivate, becomes a permanent red daily run whose remedial bump 1.16 forbids

**Claim.** Req 3.10 (requirements.md:99) re-verifies "each definition's
declared authenticity signal against its upstream origin" daily, all
definitions. Decision 11 enumerates what an inactive definition keeps, and
it is tag-driven planes only: "enumeration 2.22, daily scans, issues over
its current tags" (design.md:497-500); authenticity re-verification is
upstream-driven, and Req 1.13's verbs (builds, tracks, tests, publishes)
exclude an inactive definition from tracking. The concrete trap: an
upstream that rewrites tags, deletes releases, or dies is a headline reason
to deactivate its definition; after deactivating, 3.10 still fails the run
and files a supply-chain issue every day, and every exit is forbidden
elsewhere: the corrective bump by 1.16, deleting the directory by Decision
11's Rejected list (design.md:514-517), reactivation by the decision that
was just taken.

**Evidence.** requirements.md:99, 43, 46; design.md:497-500, 514-517.

**Why it matters.** The daily invariants are the catalogue's credibility
instrument; a permanently red run for a definition the catalogue has
deliberately stopped shipping trains the operator to ignore red, which is
the failure mode invariants exist to prevent.

**Proposed fix.** Scope 3.10 to active definitions: "THE Scan Pipeline
SHALL re-verify at least once per day each active definition's declared
authenticity signal against its upstream origin, and SHALL report each
mismatch as a failure of that run and file an issue naming it as a
supply-chain signal." (validates). Published tags of inactive definitions
keep their daily scans, attestations and verification through the
tag-driven planes regardless, so no knowledge is lost.

### 4.7 (Medium) **[V][M]** The registry namespace still has unparameterized enforcement readers: the chart gate's restrict-registries policy hardcodes it with no rendering task, Req 7.8 names a rendering source section the registry does not live in, and renovate.json5 embeds it in match strings

**Claim.** Three readers of the namespace sit outside the parameterization.
(i) `policies/restrict-registries.yaml` admits only `ghcr.io/mm-weber/dhc/*`
(policies/restrict-registries.yaml:28-30) and chart.yml applies it to every
rendered chart on every PR (chart.yml:48-52); it is the "allowed
registries" half of Req 4.6, and no task renders or re-derives it from the
policy file (tasks 9.6 and 9.8 render `verify-catalogue-images.yaml` only;
group 14 adds nothing for it). A fork that flips `registry:` in the policy
file gets a chart gate that still admits the reference namespace and
rejects the fork's own image references, which is the aperture lesson
Decision 11 itself cites (a switch nothing reads is decoration,
design.md:508-510). (ii) Task 14.1 places `registry:` "beside the
verification section" (tasks.md:363), while Req 7.8 (requirements.md:213)
renders the verification policy "from that catalogue policy file's
verification section"; the rendered Kyverno policy needs the namespace for
its imageReferences glob, so either the value moves inside the section or
7.8's source claim is wrong from day one. (iii) renovate.json5 embeds the
namespace in the two chart-pin matchStrings (renovate.json5:174, 190) and
the cert-manager chart-pin grouping matchDepNames (renovate.json5:238-240);
the design already concedes Renovate cannot read the policy file, but these
literals are listed as a fork switch nowhere, and docs/CONVENTIONS.md:204
documents the policy literal as the standing rule.

**Evidence.** policies/restrict-registries.yaml:28-30; chart.yml:48-52;
requirements.md:213, 212; tasks.md:363; renovate.json5:174, 190, 238-240;
docs/CONVENTIONS.md:204; design.md:508-510.

**Why it matters.** Decision 11's claim is "instance values move behind the
catalogue policy file"; the one enforcement gate that would actively break
a fork's first chart PR is not behind it, and the criterion-level rendering
promise (7.8, 7.9) points at a section that will not contain the value the
rendering needs.

**Proposed fix.** Add `restrict-registries.yaml` to the rendered artifacts
(one line in task 14.1 or 14.2, drift-checked under Req 7.9's existing
pattern). Move `registry:` into the verification section, or amend 7.7/7.8
so the rendering's declared inputs include the registry namespace. List the
renovate.json5 namespace literals as fork-switch rows in the
manual-controls register (Req 9.14), or render that block the way the
ignore list is rendered.

### 4.8 (Medium) **[V]** Per-definition probes collide with a component-keyed suite: three of seven definitions have no standalone workload to probe, valkey-compat's container has exited before pods are Ready, and no declared definition-to-component mapping exists for the chart and test matrices

**Claim.** Amended Req 5.5 (requirements.md:129) executes "each active
definition's declared functional probe" and task 14.3 requires "each active
definition" to register one (tasks.md:369). The suite is keyed by
chart-backed component: `componentSpecs` holds four entries with four
probes (test/e2e/components_test.go:23-51), and the four components map to
seven definitions. cert-manager-webhook and cert-manager-cainjector have no
probe surface separate from Certificate issuance, and valkey-compat is the
chart's init-container image (chart/valkey/config/values-hardened.yaml:30,
54): when pods are Ready its process has exited, so a "declared functional
probe" for it can only restate valkey's SET and GET. The lint as specified
forces three placeholder registrations, recreating the checked-off-but-
unreal probe state task 6.3 recorded as a lesson (tasks.md:95). Underneath
sits the mapping gap: e2e.yml's matrix and chart.yml's loop are
component-keyed while the active set is definition-keyed, and the only
definition-to-component mapping in the repository is e2e.yml's name-prefix
regex (e2e.yml:61) plus directory convention, declared nowhere; 14.2's
"chart and test matrices derive solely from active_set" names no function
from a definition set to a component matrix (which chart does a set naming
only cert-manager-controller activate?). Adjacent count fact: Req 1.1's
reference set names six images (requirements.md:31) while task 14.1's
active set lists "all seven definitions" (tasks.md:363); valkey-compat is
the seventh, unnamed in the reference set it is supposed to be a member of.

**Evidence.** requirements.md:129, 31; tasks.md:369, 363, 95;
test/e2e/components_test.go:23-51; chart/valkey/config/values-hardened.yaml:30,
54; e2e.yml:51, 61; measure.out S4.

**Why it matters.** 14.3 calls this "a refactor of an implemented suite";
as specified it is a granularity change that cannot be implemented honestly,
and the matrices 14.2 promises have no defined domain-to-range rule.

**Proposed fix.** Either key registrations by chart-backed component with
declared member definitions (extend task 14.3 and record the mapping, for
example in each chart's chart.yaml or in the policy file beside the active
set), or keep definition keying and permit shared registrations explicitly,
amending 5.5 to: "WHEN pods are Ready THE Test Suite SHALL execute each
functional probe declared by an active definition that installed chart
deploys, executing a probe shared by several definitions once." (validates).
Name the variant in the reference set (Req 1.1: "and valkey (runtime and
compat images)") or in CONVENTIONS beside the naming rule, so the
seven-definition count is derivable from the spec. The coherence criterion
from finding 4.3 closes the half-active component states.

### 4.9 (Low) **[V]** "Active definition" is used in two requirements with no defined antecedent

**Claim.** Req 4.1 and Req 5.5 (requirements.md:109, 129) use "an active
definition" and "each active definition"; Req 1.13 defines an active set
but never the adjective, and Req 2's terms paragraph (requirements.md:53),
the spec's one definitions home, does not carry it. Every other
cross-requirement term either lives in that paragraph (decision aperture,
supported digest) or expands to a criterion reference ("that catalogue
policy file's ceilings"). Every fix proposed above leans on the term, so
the gap is worth closing precisely.

**Evidence.** requirements.md:43, 53, 109, 129.

**Proposed fix.** Amend 1.13 to define it in passing: "THE Repository SHALL
declare in its catalogue policy file an active set naming each definition
it builds, tracks, tests and publishes, a definition so named being an
active definition." (validates). Alternatively add one sentence to Req 2's
terms paragraph.

### 4.10 (Low) **[V]** The design's probe-lint failure row cites a criterion that requires no validation, and nothing validates the active set itself

**Claim.** The new error-table row "An active definition lacks a declared
functional probe: validate.yml fails naming that definition" cites Req 5.5
(design.md:1028), but 5.5 mandates executing declared probes, not failing
validation on a missing declaration; the sibling row added beside it
anchors on an explicit IF criterion (1.16, design.md:1027), and that is the
table's standing shape. The lint task 14.3 promises therefore has no
criterion. The set itself has the same gap: an `active_set` entry naming no
definition directory fails nothing by criterion; it would surface as a
build-matrix explosion at run time rather than a named validation failure,
against the spec's own drift-lint pattern (Req 7.10).

**Evidence.** design.md:1027-1028; requirements.md:129; tasks.md:369, 363.

**Proposed fix.** Add two criteria and cite them from the row: "IF an
active definition declares no functional probe THEN THE CI Pipeline SHALL
fail validation naming that definition." and "IF that active set names a
definition with no definition directory under image/ THEN THE CI Pipeline
SHALL fail validation naming that entry." (both validate). Or re-anchor the
row on Req 7.4's codified-convention catch-all and say so in the row.

### 4.11 (Low) **[V]** Coverage and truth-pass gaps: the four amended registry criteria and amended 4.1 gained no implementing task, tasks 9.1 and 9.4 still hardcode the namespace in their step text, three prose surfaces keep the fixed four-component frame, and the addendum's "every plane" commitment is encoded narrower than written

**Claim.** (i) The coverage rows for Req 2 and Req 4 are unchanged
(tasks.md:380, 382): no 14.x task owns rebinding 2.2, 2.7, 2.21, 2.23 or
4.1, and 14.1's requirements list is Req 1.13 and 7.7 only (tasks.md:364),
its "every reader treat both as declared inputs" the sole implementing
sentence. Meanwhile task 9.1's step text pins the literal
(`name=ghcr.io/mm-weber/dhc/<image>`, tasks.md:213) and task 9.4's
visibility invariant pins `scope=repository:mm-weber/dhc/<name>`
(tasks.md:235); implemented as written, both re-hardcode what the amendment
just parameterized. (ii) Prose kept the retired frame: Req 1's Objective
still wants "definition files for four archetypal images"
(requirements.md:27), design Goals still say "Author four archetypal image
definitions" and "Adapt three upstream charts" (design.md:19, 21) with no
historical marker (the Delivery Plan has one, the Goals do not), and the
design's Integration Tests bullet still enumerates the four named probes as
the Req 5 suite (design.md:1036) after 5.5 made them reference
registrations. (iii) The addendum's commitment (1) says the active set is
"read by every plane (build matrix, rescan enumeration, e2e matrix, badges,
lint)" (critique:626-628); the encoding deliberately keeps rescan
enumeration and badges tag-driven for inactive definitions ("nothing about
Decision 7 changes", design.md:500-501), the right call, and the "Encoded"
note (critique:648-651) records no divergence from the addendum's letter,
so a reader of the addendum expects the rescan to skip inactive definitions
and the spec correctly does the opposite.

**Evidence.** tasks.md:364, 380, 382, 213, 235; requirements.md:27;
design.md:19-21, 1036, 500-501; critique:626-628, 648-651.

**Proposed fix.** Add the amended criteria to 14.1's and 14.2's
requirements lists and the Req 2 and Req 4 coverage rows; one clause in
tasks 9.1 and 9.4 reading the namespace from the policy file (or a note
deferring to 14.1); sweep the three prose surfaces in 14.4's truth pass;
one sentence in Decision 11 or the encoded note naming the rescan-and-
badges divergence from the addendum as intended.

---

## Method

**Measured (commands and raw output in the sibling `.measure.sh` /
`.measure.out`).** The EARS validator over the amended requirements.md
(PASSED, 161 valid statements, as expected) and over all fifteen proposed
replacement criteria (PASSED, 15 valid). The instance-literal sweep of
requirements.md: zero matches for the registry or owner literal in any
line; component names inside numbered criteria confined to Req 1.1's
reference set. The universal-quantifier inventory (2.1, 2.14, 2.15, 2.16,
3.2, 3.3, 3.10, 3.11, 5.2 against 1.13 to 1.17, 4.1, 5.5). Tree facts:
seven definition directories, four chart directories; build.yml's matrix
produced by a job-output feeding fromJSON, with all-definitions sourced
from a disk listing; e2e.yml's hardcoded four-component list and its
name-prefix definition-to-component regex; chart.yml carrying no matrix and
looping every chart directory twice; componentSpecs with exactly four
probes keyed by component; no `chart:` key in any definition, the upstream
chart declared in chart-side chart.yaml; valkey-compat pinned as the
chart's init-container image; lint-pins.sh's variant parity keyed on a
shared published repository; the four renovate.json5 groupName rules; the
namespace literals in policies/restrict-registries.yaml and renovate.json5;
validate.yml's pinned renovate 41.173.1 and its Go test steps (a
validate-side Go-adjacent probe lint is implementable); tasks.md 9.1, 9.2
and 9.4 literals. Network (anonymous api.github.com): renovate 41.173.1's
options source carries `ignorePaths`, `matchFileNames`, `enabled` and
`ignoreDeps` (lib/config/options/index.ts lines 1197, 1628, 407, 1329), and
renovatebot/github-action v43.0.9 defaults to the renovate 41 line, so the
rendered ignore list task 14.2 names has native mechanisms at the pinned
versions, with one implementation caveat: renovate.json5 is JSON5 with
load-bearing comments, so the renderer wants a delimited block, the same
shape as the README fenced snippets under task 9.8.

**Read (worktree).** The full diff (git diff main...spec-cleanup, one
commit, 4 files, +73/-13); requirements.md in full, criterion by criterion,
hunting fixed-list and literal survivals and orphaned dependents of 1.1's
rewording (Req 2's terms paragraph, 2.3's tag derivation, 3.3's monorepo
grouping, 6.17 to 6.30's product identity chain, which correctly binds to
definition existence and published tags rather than to the active set, and
Req 9, all clean); design Decisions 6 to 11, both flow diagrams, the
components sections, the failure-modes table; tasks groups 9 to 14 and the
coverage table, including the cross-check that 1.13 to 1.17, amended 5.5
and 7.7 each have an implementing task (they do: 14.1 to 14.4) and that the
amended Req 2 and Req 4 criteria do not (finding 4.11); the critique's 5.1
framing, its 2026-08-25 addendum and encoded note, and the F3, F9 and F13
decision blocks; docs/CONVENTIONS.md; the cluster C, greenfield and cluster
D independent reviews for series numbering and standing findings;
.github/workflows/build.yml, chart.yml, e2e.yml, renovate.yml, validate.yml;
renovate.json5 in full; test/e2e's components, probes and suite wiring;
test/renovate/managers.test.mjs's extraction emulation; scripts/lint-pins.sh's
variant-parity block; policies/restrict-registries.yaml;
chart/*/chart.yaml and chart/valkey's hardened values.

**Not measurable from here, and why.** A live Renovate run against a
rendered ignore list (no Renovate execution in this environment; asserted
from the pinned version's options source plus the config-validator path
validate.yml already runs). A GitHub Actions run reading
catalogue-policy.yaml into a matrix (the file does not exist yet, task 9.8
creates it; asserted implementable from the identical job-output pattern
already live in build.yml and e2e.yml). Probe behavior on a kind cluster,
including the valkey-compat init-container claim's runtime half (no cluster
here; asserted from the chart values pin and the suite source). Whether the
owner intends inactive charts to keep the render-and-policy gate (finding
4.4 leaves that decision to the owner; both answers are implementable).
