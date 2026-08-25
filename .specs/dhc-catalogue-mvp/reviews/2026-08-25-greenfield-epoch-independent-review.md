# Independent review: greenfield epoch amendment (PR #102, commit 423dabb)

Adversarial review of the spec-only amendment recording the greenfield epoch
(critique F9 re-decision note, design.md Decision 9 plus one Decision 7
sentence, tasks.md edits to 10.1 to 10.3, new task group 12, coverage note).
Reviewer had no authoring context. Findings are numbered from 2.1 to avoid
colliding with the cluster C review's 1.x series. Commands and raw outputs:
sibling files `2026-08-25-greenfield-epoch-independent-review.measure.sh`
and `.measure.out`.

## Verdict

The decision itself is coherent and well recorded where it touches clusters B
and D: framing A's promise attaching at the epoch is a defensible re-reading
of F9's "never delete" reasoning, the critique is amended in place per the
amend-first rule, and the removed migration sentences in 10.1 to 10.3 are
cleanly replaced. But the amendment fails its own completeness claim and its
own executability in three load-bearing places: it strands cluster A's legacy
accommodations (tasks 9.3, 9.5, 9.6 and design Decision 6 still specify the
pre-epoch registry, and the wipe destroys the unsigned control digest that
Req 2.24's daily must-reject proof is pinned to); the operator instruction at
the center of task 12.1 cannot be executed or verified as written and, as
forced onto the whole-package deletion path, silently re-privatises the
catalogue, recreating F9(c); and the kickoff-window ordering deadlocks, since
chart re-pin PRs cannot pass the required e2e gate whose upgrade path installs
the just-deleted base digests. One reordering (wipe pre-epoch versions after
the first fresh release and the chart re-pins, not before) dissolves most of
2.2 and all of 2.3. Revise before merge; the fixes are the same size as the
diff under review.

## Findings

### 2.1 (High) Cluster A still specifies the registry the epoch deletes; the Req 2.24 control digest is destroyed with no replacement

**Claim.** The amendment's consequence inventory names only tasks 10.1 to
10.3 (critique lines 875 to 879), but cluster A's standing text contradicts
the epoch in four places, and one of them breaks a daily invariant's fixture
rather than just its prose.

**Evidence.**
- `tasks.md:231` (task 9.3): "The ten pre-2026-08-04 tags are covered in
  place by this enumeration". Post-wipe those tags do not exist.
- `tasks.md:237-239` (task 9.5, in full): the ten legacy tags "keep their
  digests", are "scanned in place, never re-pointed", and a dated LOG entry
  records "that first full-enumeration rescan and its findings per tag".
  Every sentence of this task is about registry state task 12.1 deletes
  before 9.3 or 9.5 can run.
- `tasks.md:242` (task 9.6): the daily must-reject control for Req 2.24
  (`requirements.md:75`) is "the amd64 child manifest of the
  `grafana:13.0.4-alpine3.23` index (`sha256:46607ae2...`)", chosen because
  it "persists as long as its index does". Measured: that child exists today
  (index children: sha256:46607ae25051 linux/amd64, sha256:8a99c349bdb6
  linux/arm64; .measure.out section 3) and its index is version one of the
  wipe. Post-epoch every digest in the registry meets Req 2.9 uniformly
  (that is the point of the epoch, design.md:403-405), so no unsigned
  control digest exists under any catalogue repository, and nothing in task
  12.1 or 9.6 says who mints a new one.
- `design.md:163-168` (Decision 6): "The ten legacy tags are not re-pointed
  ... the rescan enumerates every catalogue tag daily ... critique F9 (a)
  amended 2026-08-22", and `design.md:182-183`: deleting the legacy indexes
  "would break every digest pin" stands as the recorded rejection of
  deletion. Decision 9 (design.md:396-419) reverses this with no annotation
  on Decision 6, although the same commit annotates the critique in place
  (the amend-first pattern applied to one of the two standing records).
- `design.md:251-252`, `design.md:457`, `design.md:906`: the invariants
  bullet, the rescan flow, and the failure-modes table all carry the control
  digest with no epoch note.

**Why it matters.** Task group 12 executes before 9.3/9.5/9.6 are
implemented (tasks.md:322: "at implementation kickoff, immediately before
task 9.1's first release"). Whoever implements cluster A after the epoch
finds a task (9.5) that cannot be executed, a sentence (9.3) that describes
nothing, and a daily invariant (9.6, Req 2.24) whose must-reject arm, the
only proof the verification policy rejects anything, silently loses its
input. A must-reject control that no longer exists does not fail the run; it
just stops proving. The amendment claims to be the complete inventory of
legacy accommodations ("tasks 10.1 to 10.3 lose their migration sentences",
critique:877-879) and is not.

**Proposed fix.** In the same amendment: drop the ten-tags sentence from
9.3; delete task 9.5 or reduce it to "the epoch's LOG entry (12.1) is the
record; nothing is scanned in place"; respecify 9.6's control (for example:
the epoch, or the release job, pushes one unsigned manifest by digest into a
catalogue repository, untagged so it is frozen under Req 2.11, recorded in
12.1's LOG entry); add a dated supersession note to design Decision 6 and to
the invariants bullet, the way the critique F9 note was amended in place.

### 2.2 (High) Task 12.1's operator instruction cannot be executed or verified as written, and the forced deletion path silently re-privatises the catalogue

**Claim.** "[OPERATOR: delete every version of the seven packages under
ghcr.io/mm-weber/dhc via the packages API; verify each repository lists zero
versions]" (tasks.md:324) fails on its count (see 2.4), on its mechanics, on
its postcondition, and on an unstated consequence that recreates F9(c).

**Evidence.**
- Mechanics: GitHub's documented deletion objects are a package version or
  an entire package. Documented restriction, measured from
  docs.github.com (.measure.out section 7): "You cannot delete a public
  package if any version of the package has more than 5,000 downloads", and
  the per-version form of the same rule. Download counts are not readable
  anonymously (the package page renders client-side; .measure.out section
  5 shows the versions API needs authentication), and the rescan plus e2e
  pull these packages daily, so counts grow toward kickoff; the task names
  no contingency (GitHub Support is the documented one).
- A widely reported API behaviour, not verifiable anonymously and not
  present on the fetched docs pages (marked inferred): deleting a package's
  last remaining version is refused; the whole package must be deleted
  instead. Either way the version-by-version path ends in whole-package
  deletion or in a package that still has one version.
- Postcondition: "each repository lists zero versions" is not a state
  GitHub represents. A package with zero versions does not exist; after
  whole-package deletion the package is gone (404), and the documented
  restore conditions ("You restore the package within 30 days of its
  deletion", "The same package namespace is still available and not used
  for a new package", .measure.out section 7) confirm deletion vacates the
  namespace rather than emptying it. The verification step as written can
  never report success.
- Visibility: documented, measured (.measure.out section 7): "When you
  first publish a package that is scoped to your personal account, the
  default visibility is private". Whole-package deletion discards the
  public visibility flipped by hand on 2026-08-21 (critique F9 c); the
  first fresh release recreates all six packages private. Req 2.21
  (`requirements.md:72`) and the README's public-registry claims go false
  across the whole catalogue at the exact moment the epoch mints it, the
  invariant that would catch it (task 9.4) may not be running yet, and the
  e2e suite is deliberately blind to it (`.github/workflows/e2e.yml:127`:
  the credentials step keeps the suite "independent of package
  visibility"). Task 12.1 has no re-publicise step. This is F9's
  "hand-flipped setting missed twice" pattern, reinstalled six times over
  by the epoch itself.
- Reversibility: the first fresh push into each namespace forecloses the
  documented 30-day restore of the deleted package (restore requires the
  namespace unused). The wipe is irreversible from the moment the epoch
  succeeds; nothing in 12.1 or the LOG-entry requirement says so.

**Why it matters.** This bullet is the epoch. An operator following it
either stalls (blocked deletion, unverifiable postcondition) or completes it
and unknowingly publishes the fresh catalogue private, breaking the
transparency promise the epoch exists to make uniform.

**Proposed fix.** Reorder (also fixes 2.3): run task 9.1's first release
first, re-pin charts, then delete every pre-epoch version; the packages then
never hit zero versions, survive with visibility intact, and the last-version
refusal never triggers. Rewrite the bullet: six packages; delete pre-epoch
versions via the versions API (authenticated with a classic PAT carrying
read:packages and delete:packages, the only auth the packages API accepts per
the fetched docs); verify with the anonymous probes F9 used (token endpoint
200 per repository, tags list contains only post-epoch tags, every catalogue
tag's manifest anonymously pullable); state the more-than-5,000-downloads
contingency and the irreversibility once fresh pushes land.

### 2.3 (High) The kickoff window deadlocks: chart re-pin PRs cannot pass the required e2e gate because the upgrade path installs the just-deleted base digests

**Claim.** "Chart image pins re-pin to the first fresh digests through the
chart-pin managers in the same kickoff window, so charts reference deleted
digests for at most one release cycle" (tasks.md:328; same claim in
design.md:414-416) assumes those re-pin PRs can go green. They cannot.

**Evidence.**
- All four charts pin catalogue digests in their values files
  (`chart/grafana/config/values-hardened.yaml:14`,
  `chart/cert-manager/config/values-hardened.yaml:13,24,35`,
  `chart/valkey/config/values-hardened.yaml:30`,
  `chart/hardened-app/values.yaml:8`); those digests are pre-epoch and die
  in the wipe.
- A chart-pin PR is a values diff, so `e2e.yml:159-185` snapshots the base
  branch's values and exports `DHC_UPGRADE_VALUES_FROM` (e2e.yml:196); the
  upgrade spec then installs the base state first and asserts readiness on
  it before upgrading (`test/e2e/upgrade_test.go:43-48`:
  helmDeploy("install", ..., fromValues) then assertReadyHardened). The
  base values pin deleted digests, kubelet can never pull them, the pods
  never go Ready, the leg fails, and the `e2e gate` fan-in
  (`e2e.yml:232-233`) goes red.
- `e2e gate` and `build gate` are required status checks on the live
  `main_sec` ruleset with `bypass_actors: null`, measured anonymously
  (.measure.out section 6). Nothing merges over the red gate, human or
  automerged (Req 3.12, `requirements.md:96`, gates automerge on green
  required checks; tasks.md:311 records e2e gate among them since
  2026-08-21), without editing the ruleset itself.
- So the sequencing is circular: the charts reference deleted digests until
  the re-pin PRs merge, and the re-pin PRs cannot merge because their gate
  installs the deleted digests.

**Why it matters.** "At most one kickoff cycle" is presented as a
self-healing bound; in fact the healing PR is the one the wipe breaks. The
same deadlock reappears for every future revocation that deletes a digest a
chart pins, so F11's revocation tool inherits it; the epoch is the cheap
moment to specify the answer.

**Proposed fix.** Preferred: the 2.2 reordering (release, re-pin through a
green gate while pre-epoch digests still exist, then wipe), which makes the
deadlock unreachable. If the wipe-first order is kept, specify the escape in
12.1: the upgrade-from step skips the base install when the base values pin
a digest the registry no longer serves (treating it as a fresh install, the
same shape e2e.yml already has for "chart is new on this PR"), or an
operator-documented ruleset edit recorded in the LOG entry. Any of these is
spec surface, not implementation detail, because Req 3.12 and the F11
mechanics depend on it.

### 2.4 (Medium) "Seven catalogue repositories" is six, in all three amended documents

**Claim.** The wipe inventory names seven packages; six exist, and the
critique's own measurement said six.

**Evidence.** design.md:403 ("the seven catalogue repositories"), the
critique amendment ("the seven catalogue repositories", line 865), and
tasks.md:324 ("the seven packages under ghcr.io/mm-weber/dhc"). Against:
seven definitions publish six repositories, because
`image/valkey-compat/image.yaml:18` publishes to `ghcr.io/mm-weber/dhc/valkey`
(`docs/CONVENTIONS.md:26-33` records the variant rule: it "publishes to the
repository its runtime sibling names"). Critique F9 measured "two of the six
image repositories" on 2026-08-21 (critique:403-404). Measured live
(.measure.out section 1): the six repositories answer the anonymous token
endpoint and list tags; `dhc/valkey-compat` is refused at the token
endpoint (403, DENIED): no such repository. The likely
source of the error is the critique's own "all seven definitions" (F12 d),
a count of definitions, not repositories.

**Why it matters.** This is the operator's deletion checklist. A wrong
count in an inventory whose whole value is completeness either sends the
operator hunting for a seventh package or teaches them to shrug at count
mismatches, and the same sentence is the epoch's public record in three
documents.

**Proposed fix.** "the six catalogue repositories (seven definitions;
valkey-compat publishes into dhc/valkey)" in tasks.md:324, design.md:403 and
the critique amendment.

### 2.5 (Medium) The issue-reset bullet promises reactivation semantics the running code will not have at epoch time

**Claim.** "closed issues keep their durable markers so a returning finding
reactivates rather than duplicates (Req 6.57)" (tasks.md:325) describes task
10.6's behaviour, which is implemented after the epoch executes; the rescan
that actually runs at epoch time dedups against open issues only and will
refile duplicates.

**Evidence.** `.github/workflows/rescan.yml:211`: the dedup reads markers
from `gh issue list --state open --label cve`. The closed-state extension is
specified only in task 10.6 (`tasks.md:286`: "the dedup search extends to
closed issues"), and group 12 executes "immediately before task 9.1's first
release" (tasks.md:322), before cluster B's tasks. Req 6.57
(`requirements.md:190`) is correctly cited as the target semantics, but no
code implements it when the reset happens. Concretely: findings covered by
unexpired exceptions stay suppressed by the ignorefile and do not refile,
but any uncovered finding whose issue the epoch closes (the
under-investigation class), and every finding whose exception lapses before
its promised at-first-release re-decision (two entries expire 2026-10-04,
the other eleven 2026-11-02; .measure.out section 8, against a kickoff that
waits for cluster D's spec), reappears in the first post-epoch rescans and is
filed as a new issue. When 10.6 later lands, the durable marker matches two
issues per finding, the exact duplication 6.57 exists to prevent, now
seeded by the epoch itself.

**Why it matters.** The bullet cites a requirement as if it were a
mechanism. The epoch's history story ("reactivates rather than duplicates")
is the part of the record a future reader will trust most and it will be
false for the interval between the epoch and task 10.6.

**Proposed fix.** Either sequence the issue reset with task 10.6 (close the
open issues when the closed-state dedup is live), or state in 12.1 that
until 10.6 lands, refiled duplicates are expected and are hand-merged into
their originals, or land the one-line dedup extension (drop `--state open`)
ahead of the epoch as part of group 12.

### 2.6 (Low) "Twelve exceptions" is thirteen

**Claim.** Decision 9's context inventory ("twelve exceptions predating
`decided_at`", design.md:398) repeats a count that was already stale when
cluster B wrote it.

**Evidence.** `triage/accepted-risk/grafana.yaml` holds 13 entries
(.measure.out section 8). Git history: the 13th entry (CVE-2026-46600, #56)
landed 2026-08-13 in commit 0919d12, ten days before cluster B's task text
said "the twelve existing grafana exceptions" and twelve days before
Decision 9 copied the number forward on 2026-08-25.

**Why it matters.** Small, but this is the record of what the epoch
discards, written by the amendment that argues records should be exact; and
an operator re-deciding "the twelve" at first release leaves one entry
undecided.

**Proposed fix.** "thirteen exceptions" in design.md:398, or drop the count
("every standing exception predates `decided_at`").

### 2.7 (Low) The /oss alias bullet mis-attributes the removal and removes only half of the accommodation

**Claim.** "The `/oss/release/` legacy alias matchString leaves
renovate.json5: every definition is migrated, and the epoch removes its
reason to exist" (tasks.md:327) is wrong about the reason and incomplete
about the accommodation.

**Evidence.** The matchString (`renovate.json5:71-76`) exists "so a
definition not yet migrated stays tracked": its subject is definition state
in git, which the registry wipe does not touch. Its reason to exist ended
when the last definition migrated to the per-build URL
(`image/grafana/image.yaml:22,59`), which was true before the epoch was
decided; the bullet's own first clause concedes this. Meanwhile the same
alias accommodation lives on in `scripts/refresh-grafana.sh:69-72` and
`:196` (parses the alias and migrates a definition still on it) and its
tests (`scripts/refresh-grafana_test.sh:196-209`, case 5b), which the
inventory does not mention.

**Why it matters.** The epoch's stated standard is removing accommodations
for state nobody was promised. Claiming the registry wipe as the reason a
git-side matchString dies muddies the record, and removing one of the two
alias readers while the sibling stays (untested against a config that no
longer matches the alias) is the half-removal pattern this repo's own
reviews keep catching.

**Proposed fix.** Either remove both halves (matchString, the refresh
script's alias branch, test 5b) with the honest reason ("every definition
migrated; the alias handler is dead code"), or take the item out of the
epoch task and put it in cluster C's renovate truth pass (11.1/11.5) where
config-hygiene lives.

### 2.8 (Low) "Exercises F11's revocation mechanics once" overstates what 12.1 does, and the consumer-facing notice postdates the wipe by the whole implementation period

**Claim.** Decision 9 and the critique amendment say the wipe "exercises
F11's revocation mechanics once, deliberately" (design.md:406-408,
critique:871-875). It exercises deletion; F11's decided mechanics are a
record and its invariants, none of which 12.1 invokes.

**Evidence.** F11's decision (critique:1088-1092): `triage/revocations.yaml`
(digest, reason, replacement digest, advisory link, date) "is the
lint-checked record that drives the mechanics", plus the status-issue
listing and a daily no-tag-on-revoked invariant. Task 12.1 records the wipe
in `triage/LOG.md` and defers the withdrawal statement to cluster D's
`SECURITY.md` (tasks.md:324,329). The wipe executes "after cluster D's
spec" but before its implementation (tasks.md:322), so for the entire 9.x
to 11.x implementation period the digests are gone while no SECURITY.md, no
advisory and no revocation record exists anywhere a consumer looks.

**Why it matters.** The promise framing covers the deleted pins ("nothing
was promised before it") but not the claim that F11 was exercised: a future
incident responder reading Decision 9 will look for the revocation record
the sentence implies and find prose in LOG.md. The one deliberate rehearsal
of the revocation lane is exactly when its record format should be used.

**Proposed fix.** Either soften to "anticipates F11's revocation tool" or
have 12.1 produce the record it claims: a `triage/revocations.yaml` entry
per removed published digest (reason: greenfield epoch; replacement: the
first fresh digest) written at epoch time, migrating under cluster D's lint
when it lands, plus a dated withdrawal note in README until SECURITY.md
exists.

### 2.9 (Low) The reversal is not annotated in the cluster B ledger, and task 12.1's Req 7.1 citation does not match its bullets

**Claim.** Record hygiene: two dispositions the epoch reverses still read as
standing in the cluster B revision ledger, and group 12's requirement
citation points at a criterion its bullets never touch.

**Evidence.** `reviews/2026-08-24-cluster-b-revision-ledger.md:25` (row 1.3:
"migration from the `cve` issues' creation dates in task 10.2") and `:33`
(row 1.11: "first-seen defined via 6.38, migration via task 10.2") record
the first-seen migration as decided and name task text this diff deleted;
the ledger's own header (lines 9-11) states the amend-in-the-same-commit
rule the epoch applied to the critique but not here. Separately,
tasks.md:330 cites Req 7.1, which is the CONVENTIONS.md criterion
(`requirements.md:201`), while 12.1's bullets touch LOG.md, README,
user-manual, renovate.json5 and SECURITY.md, never CONVENTIONS.md (contrast
10.7 and 11.5, which cite 7.1 and do edit CONVENTIONS.md). The coverage
note (tasks.md:350-352) then repeats "Req 6.57 and 7.1 are the criteria it
touches".

**Why it matters.** The ledgers exist so the state of a revision is
readable without the authoring conversation; a reversed row with no note
sends a reader to deleted text. The 7.1 citation either points at the wrong
criterion or reveals a missing bullet: CONVENTIONS.md's pinning and naming
contract is a natural place for the epoch date, and if that is intended it
is unwritten.

**Proposed fix.** Dated strike-notes on ledger rows 1.3 and 1.11
("reversed 2026-08-25, greenfield epoch, task 12.1"); either add the
CONVENTIONS.md epoch sentence to 12.1 or replace the 7.1 citation with none
(6.57 alone) and adjust the coverage note.

## Method

**Measured (network, anonymous; commands and raw output in the sibling
.measure.sh / .measure.out).** ghcr token endpoint and tags lists for all
seven candidate repositories (six exist, valkey-compat refused as unknown;
the ten F9 legacy tags all still resolve); grafana 13.0.4-alpine3.23 index children
(amd64 child sha256:46607ae25051, task 9.6's control digest, confirmed
present today and therefore confirmed deleted by the wipe);
grafana 13.1.3-alpine3.23 digest and its .att manifest layer counts (exactly
3 openvex layers plus 1 spdx: Decision 9's "three stacked OpenVEX
attestations on one digest" is true); the packages REST endpoint
anonymously (401, authentication required); the live rulesets (main_sec
requires e2e gate and build gate, bypass_actors null); docs.github.com
pages for deletion, restore and visibility semantics (the more-than-5,000-
downloads restrictions, the 30-day restore conditions, PAT-classic-only
packages API auth, private-by-default first publish).

**Read (worktree).** The full diff (git diff main...greenfield-epoch);
requirements.md in full (every cited criterion: 2.9, 2.11, 2.21, 2.23, 2.24,
3.12, 6.20, 6.57, 7.1); tasks groups 8 to 12 and the coverage table; design
Decisions 6 to 9, the rescan flow and failure-modes table; critique findings
F9 to F13, decisions F9, F11, F13 and their amendment trails, the amendment
sequence; both cluster revision ledgers; docs/CONVENTIONS.md;
triage/accepted-risk/grafana.yaml (13 entries, counted); all three
triage/vex documents (verified: no digest appears in any source product; the
two fixed statements are tag-scoped as Req 6.21 requires, so the
digest-independence claim in 12.1 is true as stated);
scripts/lint-vex-product.sh (verified registry-blind: "published tag"
resolves against definition `tags:`, so standing statements survive the
wipe without lint breakage); rescan.yml (verified soft-fail on unpublished
images, so the empty-registry window does not permanently redden the cron);
e2e.yml and test/e2e/upgrade_test.go; renovate.json5; refresh-grafana.sh
and its tests; triage/LOG.md headings and rules.

**Not measurable here, marked inferred.** The API's refusal to delete a
package's last remaining version (widely reported behaviour; not on the
fetched docs pages; deleting requires authentication, and this review holds
no token by design). Package download counts (the package web page renders
client-side; the counts API needs authentication), so whether any package is
past the 5,000-download deletion bar at kickoff is unknown in both
directions. Whether GitHub blocks deleting a version a tag references: no
such restriction appears on the fetched docs pages; not probed, since
probing means deleting. Renovate's exact behaviour against an empty docker
datasource during the wipe window (expected: failed lookups degrade to
dashboard warnings; not exercised).

**Run note.** This review's session hit a usage limit after the findings were
written and the 2.4 and 2.5 wording corrections applied; the dash audit and
this note were completed by the coordinating session, following the fallback
recorded for the cluster A and B reviews.
