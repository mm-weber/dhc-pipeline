# Production-readiness critique (external security-leader lens), 2026-08-21

**Subject:** the catalogue as it presents itself in `docs/user-manual.md` at
`73a5af5`, read the way a technical security leader at a hardened-image vendor
would read it when it crosses their feed: first as a pitch, then as a system.

**Why now.** The owner wants the project production-ready within the limits of
a one-person operation, with the primitives and judgement calls in place so a
fork can scale it to an organisation without re-architecting. Every finding
below is therefore asked two questions: what does it cost one maintainer to
close, and what does a fork need to find already in place.

**Method.** A persona review of the manual (Claude, role-play requested by the
owner; no real person or vendor is quoted or represented), followed by an
independent read-only verification pass over the workflows, scripts,
definitions, charts, triage lane and specs. Every claim carries the lines it
rests on. `design.md` was *not* excluded this time, unlike review A: the
question here is the built system, not whether the criteria read coherently
on their own. The three 2026-08-04 reviews were consulted for prior art, and
where a finding was already raised there it says so, because a point raised
twice and argued never is itself a finding. Branch-protection, ruleset,
collaborator and registry settings live outside the tree and could not be
read from the devcontainer (no `gh` auth); they are marked unverified.

**Verification legend**

| | |
|---|---|
| **[V]** | verified directly against the repository during this review, with `path:line` |
| **[U]** | unverifiable from the devcontainer; needs the operator host |
| **[P]** | prior art: raised in a 2026-08-04 review, with its recorded fate |

**How to read a finding.** Claim, evidence, prior art, a scale note (what the
point means at one maintainer versus at org scale), and a *Disposition* line.
Dispositions start `open` and are filled in one at a time by the owner during
the dialogue this document exists to anchor; section 5 is the ledger.

---

## 1. Verdict

The reflex on seeing "I built a hardened-image supply chain" is to scroll
past: keyless signing bolted onto an unexamined pipeline is the genre. Two
things stop the scroll here. The writing is failure-mode oriented ("an inert
statement is otherwise indistinguishable from a correct one", "silence, not
absence", dead suppression entries reported rather than swallowed, a
local-registry step justified by a measured scanner behaviour rather than
folklore), which is the tell of someone who has watched the thing fail. And
it is transparently an audition aimed at a DHI-class team: it builds on the
`dhi.io` toolchain and mirrors its conventions.

Read as a system, the catalogue is a strong *operating model* wrapped around
someone else's *hardening substrate*, with one account as its entire trust
root. The controls that are genuinely ahead of common practice (per-binary
exception scoping, inert-VEX visibility, human-completed tool checksums,
egress-less build stages) sit next to gaps that a vendor's due diligence
finds in an afternoon: the artifact that is signed is never the artifact that
was scanned; package versions float; a patch-level upstream release merges
and ships signed with no human in the loop; the consumer-facing verification
snippet is the loosest check in the repo; the one question a consumer most
needs answered ("this applies, what do I do?") has no artifact by design; and
there is no security policy, advisory channel or revocation story for the
catalogue itself.

The gap between this and a product is not more YAML. It is an organisation:
second reviewers, severity-tiered clocks, an advisory feed, incident response,
and controls that survive two hundred images instead of six. The useful
output of this review is to sort every finding into "missing engineering"
(closable by one person, cheaply) and "missing organisation" (needs a
primitive today and a second human later), and to make the catalogue *say
which is which* instead of implying parity.

---

## 2. Findings

### F1 **[V]** The trust root is one GitHub account, and every review is a self-review

**Claim.** Signatures are keyless against a workflow identity in a repository
one person owns and administers. The manual says exception content is
"judged at review" (`docs/user-manual.md:529`, `:622`); the author, the
reviewer and the branch-protection admin are the same person.

**Evidence.** `.github/` holds only `PULL_REQUEST_TEMPLATE.md`,
`requirements-ci.txt` and the six workflows: no `CODEOWNERS`. No workflow
declares a deployment `environment:`, so no release step can require a
reviewer. The PR template is a self-attestation checklist
(`.github/PULL_REQUEST_TEMPLATE.md:14-20`). Ownership is stamped into the
artifacts themselves: `triage/vex/CVE-2026-28377.openvex.json:4`
(`"author": "dhc-pipeline triage (mm-weber)"`), `triage/accepted-risk/grafana.yaml`
(`owner: mm-weber`). The signing surface is at least narrow: `id-token: write`
appears exactly once in the repository, in the `release` job of `build.yml`
(`.github/workflows/build.yml:113-116`), under a workflow default of
`contents: read` (`:31-32`).

**Measured 2026-08-21, anonymous reads of the public rulesets API
(`/repos/mm-weber/dhc-pipeline/rulesets`, `/rules/branches/main`).** Two
active rulesets target the default branch. `main_sec` (id 20716271, updated
2026-08-13) requires a pull request with **one approving review**, thread
resolution, squash merges only, linear history, signed commits, a CodeQL
result, and three required status checks: `yamllint, pin lint, policy
tests`, `go modules (e2e + rescan tool)`, `render + policy gate`. An older
ruleset `branch` (id 19534405) overlaps it with weaker settings. Two
consequences. First, the two fan-in jobs the manual says to require,
**`build gate` and `e2e gate`, are not required checks**
(`docs/user-manual.md:414-423`, `:884-886` describe a configuration the
repository does not have): as far as the ruleset is concerned a pull
request can merge with a red scan gate or a failed kind suite. Second, a
one-approval rule cannot be satisfied by a sole author, so every merge on
`main` (including Renovate's automerges, which act with the owner's PAT)
happens through a bypass; GitHub records each bypass in the pull request
timeline, and the repository says nothing about it anywhere. The bypass
actor list is not exposed to anonymous reads and stays **[U]**.

The primitive a second maintainer needs is therefore already declared and
already binding on everyone but the owner; what is missing is the honest
statement of that, the two gates, and any record in the tree of what the
live settings are supposed to be.

**Scale note.** One person cannot satisfy a two-person rule, but can
*declare* it: a `CODEOWNERS`, a protected `release` environment on the
signing job, and a ruleset that requires non-author review are free to
commit and cheap to document as "satisfied by exception until a second
maintainer exists". A fork then flips a switch instead of designing a review
model. What the signature attests should also be stated in writing: today it
proves "this repository's release workflow ran on `main`", nothing about a
human having looked.

**Disposition.** decided 2026-08-21; mechanism in section 5.2, ledger in 5.3.

### F2 **[V]** Automerge lets the attacker choose their level of scrutiny, and the source checksum updates itself

**Claim.** From-source patch and digest bumps automerge on green CI
(`renovate.json5:250-256`); minors are reviewed; majors wait for dashboard
approval (`:244-249`). The adversary who publishes a malicious upstream
release also chooses its version number, and therefore chooses whether a
human reads the diff. The repository states the principle that forbids
self-updating trust anchors for tool binaries, and then applies the opposite
rule to the application source it compiles and signs.

**Evidence.** `scripts/refresh-definition.sh:41-48` resolves the new commit
from the tag Renovate just moved (`git ls-remote … refs/tags/${new_tag}^{}`)
and `:53-58` rewrites `checksum:` and `COMMIT_SHA` with it; the header says
so (`:7`). It runs as a Renovate `postUpgradeTask` (`renovate.json5:263-268`).
The tool pins take the opposite stance on purpose: `renovate.json5:120-134`
("an auto-recomputed checksum is whatever upstream serves at that instant,
which is a hash of the thing rather than a decision about it"),
`scripts/install-tool.sh:36-40`, `scripts/install-scanners.sh:17-19`, citing
CVE-2026-33634. `.specs/dhc-catalogue-mvp/tasks.md:57` concedes the automerge
scope is broader than Req 3.5 was written ("the config automerges real patch
bumps, not only digest re-pins"). No `platformAutomerge`, `ignoreTests` or
`requiredStatusChecks` key exists in `renovate.json5`; the "green CI" gate is
Renovate's default plus whatever branch protection enforces **[U]**.

**Nuance.** The recomputed commit sha is not worthless: it pins the bump to
the commit the tag pointed at *that moment*, so a later tag rewrite is caught.
What it cannot catch is a release that was malicious when published, which is
exactly the case where the human review was the only control, and automerge
removes it for the version class the attacker controls. xz-utils shipped as
two routine-looking releases.

**Scale note.** The fix is not "no automerge"; at org scale automerge is how
a catalogue keeps up. The primitive is a *quarantine* between "upstream
published" and "we signed": Renovate's `minimumReleaseAge` (a release must
survive N days in the open before a bump opens), plus wherever an upstream
offers one, a second independent signal (release signature, sigstore bundle,
provenance) verified before the checksum is accepted. Both are declarative
and cost one person nothing once written.

**Disposition.** decided 2026-08-21; mechanism in section 5.2, ledger in 5.3.

### F3 **[V][P]** The artifact that is signed is never the artifact that was scanned; package versions float; nothing rebuilds on a schedule

**Claim.** The scan gate runs on the pull-request build. Merge to `main`
triggers a *rebuild* that is pushed, signed and attested without any scan.
Runtime apk packages carry no version pins, so the resolved package set can
differ between the gated build and the released one. No workflow rebuilds
on a schedule, so a fixed base package reaches consumers only after the
daily rescan files an issue and a human pushes a change through.

**Evidence.** Every scan step is `if: github.event_name == 'pull_request'`:
`.github/workflows/build.yml:208` (scanner install), `:234` (local registry),
`:260` (Trivy), `:491` (govulncheck), `:553` (Grype), `:570` (the gate).
Every release step is `main`-gated with nothing between: `:190` push, `:599`
cosign sign, `:605` Syft, `:614` SBOM attest, `:620`–`:654` OpenVEX attest;
no `trivy`/`grype` invocation exists after line 592. The workflow's own
comment records the consequence for arm64 ("signed, SBOM'd and attested
unread", `:182-188`). Package lists are bare names in all seven definitions
(`image/*/image.yaml`, e.g. `image/valkey/image.yaml:30-33`:
`alpine-baselayout-data`, `ca-certificates-bundle`, `libssl3`); no lockfile
mechanism exists in `image/` or `docs/`; the pinning contract in
`docs/CONVENTIONS.md:47-83` enumerates base images, git sources, chart
versions, actions and workflow executables, and omits apk packages. `on:`
blocks: only `renovate.yml:15-28` and `rescan.yml:17-20` carry a `schedule:`;
`build.yml:20-29` is `pull_request` / `push: main` / `workflow_dispatch`.

**Prior art.** Review A finding 1.3, "nothing scans the artifact that ships",
recorded as **Unaddressed** in the v2 adversarial review
(`reviews/2026-08-04-v2-draft-adversarial-review.md:80`). Seventeen days and
one user manual later it is still open.

**Nuance.** Packages are signature-verified against the DHI keyring at build
time (`image/valkey/image.yaml:26-27`) and captured after the fact in the
SBOM, so they are authenticated and recorded, just not pinned. The PR gate
does scan a functionally equivalent amd64 build of the same commit; this is a
re-scan gap with a window of up to one rescan cycle, not an unscanned
definition.

**Scale note.** The industry answer is boring and fully automatable: scan the
pushed digest before signing (or sign, then gate the *tag* move on the scan),
and rebuild on a schedule so base fixes flow without a human noticing them.
Both are one-person changes. Pinning apk versions is a separate decision
with a real cost (every Alpine advisory becomes a bump PR); the org-scale
primitive is to make the choice explicit in the pinning contract either way.

**Disposition.** decided 2026-08-21; mechanism in section 5.2, ledger in 5.3.

### F4 **[V]** There is no remediation clock, the gate stops at HIGH, and the exception ceiling is flat

**Claim.** "A daily rescan files an issue" is a queue, not a commitment. The
gate and the rescan see only HIGH and CRITICAL, so a green run tolerates any
number of MEDIUMs. The accepted-risk ceiling is 90 days regardless of
severity or KEV status, and no clock runs on an open CVE issue.

**Evidence.** `--severity HIGH,CRITICAL` at `.github/workflows/build.yml:321-323`
and `.github/workflows/rescan.yml:137-138`; the reporter ranks only those two
(`triage/rescan/report.go:170`). `MAX_DAYS=90` at
`scripts/lint-accepted-risk.sh:23`, enforced at `:157-162`; the script
contains no `severity` or `kev` token. Req 6.11 is flat by construction
(`.specs/dhc-catalogue-mvp/requirements.md:102`). The rescan reads open `cve`
issues only to dedupe on the hidden marker (`rescan.yml:201-216`);
`triage/rescan/report.go` carries no date or age field. The manual says EPSS
and KEV "order the queue; they never justify a status"
(`docs/user-manual.md:487-488`), which is correct and is also the only place
they act.

**Nuance.** The HIGH/CRITICAL aperture is Req 6.1/6.3 verbatim: a designed
scope, not drift. The critique is that the scope is undeclared to consumers
and that "accepted for 90 days" applies identically to a KEV-listed CRITICAL
and to a HIGH with an EPSS of 0.01.

**Scale note.** One person cannot honestly promise a 7-day CRITICAL fix. One
person *can* make the clock visible: a published severity-tiered ceiling
(e.g. CRITICAL 14 days, HIGH 90, KEV shorter still), an age on every open
issue, and time-to-decision measured and published rather than promised. A
fork with staff changes the numbers, not the machinery. Widening the
aperture to MEDIUM is a separate cost decision; declaring the aperture is
free.

**Disposition.** decided 2026-08-21; mechanism in section 5.2, ledger in 5.3.

### F5 **[V][P]** The consumer's third question has no artifact, by an unargued decision

**Claim.** The two-lane model answers "does this apply?" (VEX) and "what are
*we* doing?" (internal exceptions). OpenVEX has a third verb for "this
applies to you; here is what we are doing and by when": status `affected`
with an `action_statement`. The catalogue never uses it, and a consumer whose
scanner lights up is told to read the issue tracker.

**Evidence.** Statements in tree: one `not_affected`
(`triage/vex/CVE-2026-42151.openvex.json:21`), three `fixed` (`:41`,
`CVE-2026-28377.openvex.json:21`, `CVE-2026-21728.openvex.json:21`); no
`action_statement` anywhere. The linter does **not** forbid `affected`; its
own tests assert it passes (`scripts/lint-vex-product_test.sh:518-521`), and
`compile-vex.sh` is status-agnostic. Req 6.8 forbids recording *accept or
transfer* as VEX (`.specs/dhc-catalogue-mvp/requirements.md:99`); Req 6.1
counts only `not_affected`/`fixed` as coverage (`:92`), which is right. The
stated rationale is `triage/README.md:36-47`: publishing the exception
"would tell every downstream consumer that a vulnerability does not apply to
them". That is true of a `not_affected` statement and false of an `affected`
one, which suppresses nothing in any scanner.

**Prior art.** Review A 2.2 made exactly this argument
(`reviews/2026-08-04-req6-consistency.md:161-182`: "the model was built
around two questions and there are three"). The v2 draft's fate: "**Silently
decided** … siding with `triage/README.md` against review A's
`affected`+`action_statement` rebuttal, without stating or arguing the
decision" (`reviews/2026-08-04-v2-draft-adversarial-review.md:83`).

**Correction to the persona's phrasing.** The manual reads as if publishing
anything but `not_affected`/`fixed` were prohibited; the mechanism permits
`affected`. The finding is that the option was raised, never argued, and
never taken.

**Scale note.** This is the cheapest high-value change in the list: the
accepted-risk file already holds everything an `action_statement` needs
(treatment, owner, expiry, upstream issue); the compiler can emit `affected`
statements from it per digest. Enterprise consumers run VEX-aware scanners
and expect the vendor's knowledge in-band. The VEX-washing prohibition stays
intact because `affected` is not an excuse.

**Disposition.** decided 2026-08-21; mechanism in section 5.2, ledger in 5.3.

### F6 **[V]** The verification snippet consumers are handed is the loosest check in the repository

**Claim.** `--certificate-identity-regexp github.com/mm-weber/dhc-pipeline`
is unanchored substring matching that pins neither the workflow file nor the
ref. Any Fulcio identity *containing* that string verifies: another
repository under the same account whose name begins with `dhc-pipeline`, any
workflow in this one, any branch.

**Evidence.** `README.md:33-34` and `docs/user-manual.md:153-154`, the only
two occurrences, both driving `cosign verify` and both `verify-attestation`
calls. The manual's framing, "verification pins the workflow identity, not a
key" (`docs/user-manual.md:148-149`), overstates what the regexp does. The
signing side is narrow (F1), which limits the blast radius today and is
irrelevant to what a consumer is taught.

**Scale note.** Anchor it to the full identity
(`^https://github.com/mm-weber/dhc-pipeline/.github/workflows/build.yml@refs/heads/main$`)
and make the expected identity a published artifact rather than prose: a
verification policy file shipped with the catalogue (a Kyverno
`verifyImages` rule or a cosign policy), tested in CI against a real
published digest. A fork edits one file; consumers import it.

**Disposition.** decided 2026-08-21; mechanism in section 5.2, ledger in 5.3.

### F7 **[V][P]** VEX is tuned to one scanner's matching semantics and proven in no other

**Claim.** The whole product-identifier apparatus (RepoDigest purls, the
local-registry workaround for trivy#9399, the compiler) is shaped by Trivy.
Nothing checks that the attested OpenVEX suppresses anything in Grype, Docker
Scout, or any other consumer.

**Evidence.** Every `--vex` consumer is Trivy (`build.yml:310,321`,
`rescan.yml:128,137`, `docs/user-manual.md:178,309`, `triage/README.md:93`);
`design.md:215` records "Verified against Trivy 0.72.0". Grype is always
invoked bare (`build.yml:561`, `rescan.yml:238`): no `--vex`, no `GRYPE_VEX`
env. Docker Scout is an explicit non-goal (`design.md:28`). No test under
`test/` touches VEX consumption.

**Prior art.** Review A 2.5 (Grype result unconsumed), recorded
**Half-resolved** (`reviews/2026-08-04-v2-draft-adversarial-review.md:86`).

**Nuance.** The per-digest compilation exists precisely so that third-party
scanners can consume the predicate (Req 6.34); the claim is simply
unverified. The repo's own lesson applies: inert and correct look identical
until measured.

**Scale note.** A second consumer in CI (Grype with the compiled predicate,
asserting the same suppression set) is a one-person change and turns "should
work" into "measured on two matchers". Scout stays a non-goal unless the
owner wants it; the primitive is "N consumers, compared", not a specific N.

**Disposition.** decided 2026-08-21; mechanism in section 5.2, ledger in 5.3.

### F8 **[V]** The valkey compat decision ranks chart purity above runtime hardening, and upstream was never asked

**Claim.** The only stateful workload ships with a shell because the upstream
chart renders an unconditional `/bin/sh` init container and "never modify
upstream" outranked "no shell in production". The transfer discipline built
for CVEs (measured evidence, upstream issue, re-runnable check) was not
applied to the chart defect that caused the hardening regression.

**Evidence.** `chart/valkey/README.md:54-76` (measured: unconditional init
container, `init.sh` opens `#!/bin/sh`, no value reaches it,
`extraInitContainers` appends rather than replaces), cost stated `:83-90`,
fork rejected `:92-95`; `chart/valkey/config/values-hardened.yaml:10,30,53-54`;
`image/valkey-compat/image.yaml:9`. `triage/upstream/README.md:43-47` lists
three drafts, all against grafana repositories; no `valkey-helm` issue or
draft exists anywhere in the tree; `triage/LOG.md` has no valkey entry. The
README weighs "fork" against "compat" and never lists "ask upstream to make
the init container optional".

**Measured 2026-08-21 against upstream `main`** (latest tag `valkey-0.11.0`,
the version we pin, so no newer release changes this):
`valkey/templates/deploy_valkey.yaml:53-61` renders the init container
unconditionally with `image: {{ include "valkey.image" . }}`, the same
helper as the main container (`:105`); `valkey/values.yaml:106-107` offers
`initResources`, `:146-147` an appending `extraInitContainers`, and nothing
that disables the init container or changes its image. Upstream already
carries a second image helper for the metrics exporter
(`deploy_valkey.yaml:154`, `valkey.metrics.exporter.image`), so a
per-init-container image value follows an accepted pattern.

**Scale note.** The honest ranking is: upstream change first (it removes the
shell for everyone and costs a PR), compat as the time-boxed fallback while
it lands, fork last. A compat decision that carries an upstream issue and an
expiry is the same shape as a transfer exception, and the lane for that
already exists.

**Disposition.** decided 2026-08-21; mechanism in section 5.2, ledger in 5.3.

### F9 **[V]** amd64 only, and the unscanned arm64 manifests published before 2026-08-04 are still pullable

**Claim.** Half the fleet is arm64. Withdrawing the platform because nothing
scanned it was the right call; the legacy multi-arch indexes violate the
rule that justified it.

**Evidence.** `build.yml:189` (`platforms: linux/amd64`), rationale `:182-188`;
task 8.3 deferred since 2026-08-04 (`.specs/dhc-catalogue-mvp/tasks.md:173-180`);
`:178` notes pre-withdrawal tags "remain multi-arch indexes … left as they
are". Definitions still declare both platforms (`image/*/image.yaml:10-12`).
`scripts/verify-arch-pins.sh:7-22` keeps the arm64 pins honest without
building them.

**Measured 2026-08-21, anonymous reads against `ghcr.io`.** Ten catalogue
tags still resolve to multi-arch indexes whose arm64 manifest was never
scanned: `cert-manager-controller` and `cert-manager-webhook` at
`1.20-alpine3.23`, `1.20.3-alpine3.23`, `1.21.0-alpine3.23`; `grafana` at
`13.0-alpine3.23`, `13.0.4-alpine3.23`; `valkey` at `9.0-alpine3.23`,
`9.0.5-alpine3.23`. Every tag published since the withdrawal is amd64-only.
Separately, and not previously known: **two of the six image repositories
are not publicly readable.** The anonymous token endpoint returns 401 and
the package pages return 404 for `hardened-app` and
`cert-manager-cainjector`, while `cert-manager-controller`,
`cert-manager-webhook`, `grafana` and `valkey` return 200. `README.md:29-30`
("Every image published to `ghcr.io/mm-weber/dhc` is signed …") and
`docs/user-manual.md:830` ("images public on ghcr") describe a published
set the registry does not serve; the e2e suite masks it because kubelet
pulls with credentials (`docs/user-manual.md:346-349`). The likely cause is
a per-package visibility setting flipped by hand at go-live and missed
twice, which is F13's pattern in miniature.

**Scale note.** Restoring arm64 is gated on scanning it (Req 2.6), which is
the right gate; F3's "scan the pushed digest, per platform" closes both at
once. The legacy indexes need a decision now: rescan them, retag them
amd64-only, or state publicly that tags before a given date are unsupported.
The visibility gap needs an operator fix today and an invariant afterwards:
"every catalogue repository is anonymously pullable" is a one-line check
the rescan can run daily, turning a hand-flipped setting into a monitored
fact.

**Disposition.** decided 2026-08-21; mechanism in section 5.2, ledger in 5.3.

### F10 **[V]** Grafana's authenticity anchor is a checksum served by the same origin as the artifact

**Claim.** The three-source build-id resolution authenticates *which build*,
not *the bytes*. The bytes are trusted because a `.sha256` sidecar on
`dl.grafana.com` agrees with a tarball on `dl.grafana.com`. That is
integrity in transit, not authenticity, and the catalogue then signs it.

**Evidence.** `scripts/refresh-grafana.sh:175-181` fetches `${base}.sha256`
where `base` is the tarball URL (`:165`, `:197`); the pin lands in
`image/grafana/image.yaml:33` and is re-verified in-build (`:62-66`). No
`gpg`, `pgp` or `cosign verify` in `refresh-grafana.sh` or
`verify-arch-pins.sh`; the latter re-downloads and re-hashes from the same
origin (`:62-73`, `:82-95`). The cross-check (`refresh-grafana.sh:31-35`,
`:107`, `:117`, `:124`) compares build ids across the versions API, the apt
index and GitHub assets. The definition already concedes the limit:
"upstream stays self-consistent throughout … nothing is detectably wrong at
any single moment. It just moves" (`image/grafana/image.yaml:26-28`). Manual
override seams exist (`refresh-grafana.sh:189-192`), and one pin entered
through them unverified (`verify-arch-pins.sh:10-14`).

**Nuance.** If upstream publishes no signature for the tarballs, there is no
stronger anchor to reach for, and the build-id immutability work is the best
available mitigation. The defect is presentational as much as technical: the
provenance story implies verification where the truth is "TLS to the
vendor's CDN plus multi-index agreement".

**Scale note.** Record an *upstream authenticity class* per definition
(signed release / checksum sidecar same-origin / none) and surface it in the
chart README and the SBOM-adjacent docs. At org scale that field is what
decides which archetype an image is allowed to be.

**Disposition.** decided 2026-08-21; mechanism in section 5.2, ledger in 5.3.

### F11 **[V][P]** No security policy, no disclosure path, no advisory feed, no revocation or incident procedure

**Claim.** A catalogue that asks consumers to trust its signatures owes them
a way to report a problem with the catalogue, a way to learn that a published
digest is bad, and a statement of what happens then.

**Evidence.** No `SECURITY.md` anywhere (`find -iname 'SECURITY*'` returns
only `test/checks/securitycontext*.go`); `.github/` has no issue templates or
policy. Zero hits for `disclosure`, `security@`, `revoke`, `revocation`,
`incident`, `yank` outside the reviews archive. The only inbound channel is
the per-definition `bug-report-url` pointing at the public issue tracker
(`image/grafana/image.yaml:117`). `rekor` appears only in the reviews and lab
notes; the v2 adversarial review flagged the Rekor disclosure exception as
"documented nowhere in the repo" (`…v2-draft-adversarial-review.md:67`).

**Measured 2026-08-21, public API.** GitHub private vulnerability
reporting is **disabled** on the repository
(`/repos/mm-weber/dhc-pipeline/private-vulnerability-reporting` returns
`enabled: false`); no repository security advisory has ever been published;
GitHub Pages is off. So the only way to report a vulnerability *in the
catalogue* today is a public issue, which is the one channel a responsible
reporter should not use.

**Prior art.** Review A 3.14, "no revalidation duty … published attestations
on old digests are never revisited", recorded **Unaddressed**
(`…v2-draft-adversarial-review.md:90`); the re-attestation half is closed
by F5 (ii).

**Scale note.** The one-person version is a `SECURITY.md` (contact, scope,
what is and is not supported, the Rekor disclosure fact), a documented
revocation mechanic (what gets deleted, what gets re-attested, where the
notice goes), and a machine-readable advisory location even if it starts
empty. A fork inherits a place to put things instead of inventing one during
an incident.

**Disposition.** decided 2026-08-21; mechanism in section 5.2, ledger in 5.3.

### F12 **[V][U]** The hardening substrate is DHI's; the catalogue's own contribution is the operating model, and the redistribution terms are undiscussed

**Claim.** Distroless runtime, non-root defaults, hardened apk repositories,
the build frontend and the Go builder all come from `dhi.io`. What this
repository adds is the pipeline, the triage lane, the chart adaptations and
the tests. The README implies more hardening authorship than that, and says
nothing about whether publishing DHI-derived layers to a public registry
under a personal namespace is within the terms the free tier grants.

**Evidence.** `image/cert-manager-cainjector/image.yaml:1`
(`# syntax=dhi.io/build:2-alpine3.23@sha256:…`), `:35`
(`uses: dhi.io/golang:…-dev@sha256:…`), `:24` (`https://dhi.io/apk/alpine/v3.23/main`)
with keyring `:28`; the same three across all seven definitions. Licensing
text covers the repackaged upstream software only (`README.md:62-65`,
per-definition `license:` fields). No occurrence of `redistribut`, `terms`,
`EULA` or `subscription` in `README.md`, `docs/` or `.specs/`; the only
commercial reference is an access note (`docs/decisions/0001-build-layer.md:16-18`).
**[U]** The actual terms are open-web research the owner prefers to do on
the host.

**Scale note.** Saying plainly "hardening by DHI, operation by this
catalogue" is a stronger pitch than the current framing, and it is the truth
a vendor's lawyer will establish in minutes anyway. The terms question needs
an answer before "production-ready" is claimed publicly, whichever way it
comes out.

**Disposition.** decided 2026-08-21; mechanism in section 5.2, ledger in 5.3.

### F13 **[V]** Six controls cost one human action per item; only some of them are meant to

**Claim.** The manual's operating model scales as (humans × items). Some of
that friction is deliberate and should stay; some is accidental toil that an
org-scale fork would hit first.

**Evidence.** (a) Tool sha256 completion is deliberate friction
(`renovate.json5:120-125`, `scripts/install-tool.sh:38-40`, runbook
`docs/user-manual.md:450,459-465`). (b) VEX is hand-authored per CVE with
`vexctl` (`triage/README.md:172-185`); nothing generates it. (c) The rescan
opens issues and never closes them (`rescan.yml:242-259`; `gh issue close`
appears nowhere; `docs/user-manual.md:486-488`). (d) `triage/LOG.md` is
~1,080 lines of hand-maintained prose whose anchors nothing validates
(`triage/accepted-risk/grafana.yaml:27` references a hand-typed slug). (e)
Chart versions are hand-pinned with no tracker (`docs/CONVENTIONS.md:51-52`).
(f) Build-layer bumps are reviewed by hand with no automation
(`docs/user-manual.md:926`).

**Scale note.** The interview question is "which of these would you delete
at two hundred images, and which would you defend?" A defensible answer
marks (a) as a keep, turns (b) and (d) into structured records the compiler
reads (the v2 draft's ledger idea, landed incrementally rather than as a
rewrite), lets the rescan close issues whose CVE no longer appears, and gives
(e) a Renovate manager. Each is a separate PR; the primitive is that every
manual step is *labelled* deliberate or pending automation.

**Disposition.** decided 2026-08-21; mechanism in section 5.2, ledger in 5.3.

---

## 3. Keep: controls a revision must not regress

Recorded so the dialogue is read as aimed at the gaps, not the design.

- **Per-binary exception scoping** (Req 6.23–6.27): the same CVE in two
  bundled binaries is two decisions. Ahead of most enterprise programmes.
- **Inert suppression made visible** (Req 6.26, 6.32, 6.33): dead exception
  entries reported, "compiled nothing" distinguished from "never compiled".
- **The VEX-washing prohibition** (Req 6.8's intent): a business decision is
  never published as a technical inapplicability claim. F5 adds a verb; it
  does not loosen this.
- **Human-completed tool checksums with the stated rationale**
  (`renovate.json5:120-134`): the pattern F2 asks to extend, not remove.
- **Egress-less build stages; acquisition only in the declared fetch phase.**
- **Refusal over guessing** in the grafana refresh; "measured, not inferred"
  comments throughout `build.yml`.
- **arm64 withdrawn because nothing scanned it** (Req 2.6): the rule is
  right; F9 is about the tags that predate it.
- **Fan-in gates** for matrix branch protection.
- **The reviews archive itself**: three adversarial reviews in `.specs/`
  with recorded fates. F3 and F5 are only findable as "raised and left" because
  that archive exists.

---

## 4. Open verification items

| Item | Why it matters | How to close |
|---|---|---|
| Ruleset bypass actors on `main` (rulesets themselves now measured, see F1: one approving review required, `build gate` and `e2e gate` not required) | F1, F2: who can merge without the review, and whether Renovate's PAT is among them | `gh api repos/mm-weber/dhc-pipeline/rulesets/20716271` on the host (admin view shows `bypass_actors`); drop the JSON into `data/` |
| Collaborators and their roles | F1: bus factor as fact, not assumption | `gh api repos/mm-weber/dhc-pipeline/collaborators` |
| GHCR package settings: who can push, tag mutability (visibility now measured: two of six repositories private, see F9) | F9, F11: whether a bad tag can be moved or deleted, and by whom | GHCR package settings page |
| DHI terms on public redistribution of derived images (answered 2026-08-21: `data/dhi-terms-2026-08-21.md`, permitted under Apache-2.0 with conditions, DSSA tension flagged) | F12 | closed; sources re-verified by 2026-11-21 (F13 register) |

---

## 5. Decisions

### 5.1 Framing: the promise (decided 2026-08-21)

Three shapes were weighed before any finding was dispositioned, because F1,
F4, F5 and F11 all derive from which promise the catalogue makes:

- **A. Transparency catalogue.** The promise is about knowledge, not speed.
  Every published digest is signed by a pinned identity; every known HIGH or
  CRITICAL finding against a published digest carries a published,
  machine-readable status (`not_affected`, `fixed`, or `affected` with an
  action statement and a date); time-to-decision and time-to-fix are
  measured and published as numbers, not promised as service levels.
- **B. Supported catalogue.** Committed remediation windows and an on-call
  shaped duty. Honest only with two or more maintainers.
- **C. Reference implementation.** Images labelled not for production; the
  pipeline is the product.

**Decided: A.** One maintainer can keep A unconditionally because automation
produces the status and the human supplies only decisions; a fork with staff
reaches B by changing numbers, not machinery. Every disposition below is
judged against A: does the change make a promise one person can keep, and
does it leave the switch a fork needs.

### 5.2 Decisions per finding

**F3 (i), release path (decided 2026-08-21): publish with status.** On
`main` the image is pushed by digest only, that pushed digest is scanned
with the same VEX and exception inputs the PR gate uses, VEX is compiled for
exactly that digest, the image is signed and attested, and only then are
tags applied. "Published" now means tagged, signed and attested; an untagged
digest is not published. Any HIGH or CRITICAL finding uncovered at release
time is written into the attested VEX as `under_investigation` with the
triage issue reference and a timestamp, and the release proceeds. Rejected:
fail-closed on `main` (speed-shaped, blocks unrelated fix-forward releases
for one maintainer) and scan-after-publish as information only (violates A).
Fork switch: "uncovered on `main` fails closed" becomes a single declared
setting. Parts (ii) packages and (iii) rebuild cadence decided separately.

**F3 (ii), apk packages (decided 2026-08-21): float by design, declared
and compensated.** apk packages enter the pinning contract in
`docs/CONVENTIONS.md` as the explicit exception: resolution floats, the
resolved set is recorded per digest in the attested SBOM, the published
digest is scanned (i), and a scheduled rebuild (iii) is the delivery
mechanism for base fixes. Measured basis: no versioned apk syntax exists in
any research input, the DHI catalog notes, or our definitions
(`data/docker_internal_build.md:81`: DHI ships base fixes by rebuilding);
frontend support for `name=version` is unmeasured and, under A, need not be.
Rejected: hand-pinned versions (needs a spike plus a bespoke Renovate
datasource over `APKINDEX`, and one bump PR per base advisory for one
person) and a committed lock compared on `main` (adds no knowledge once (i)
scans the published digest; only converts drift into a blocked release).
Optional refinement at implementation: the release summary prints the
package diff against the previous release of the same tag. Fork switch: the
contract row itself; an org that wants pins changes the row and adds the
datasource.

**F3 (iii), rebuild cadence (decided 2026-08-21): daily scheduled rebuild
of every definition, publish only when content changed.** A cron builds all
definitions, compares the fresh SBOM's package set against the SBOM of the
currently published digest for the same full tag, and publishes through the
(i) path only when they differ; identical content is discarded, so
provenance timestamps alone never mint a digest or open a chart-pin PR. The
comparison is thin glue with its own `_test.sh`. Accepted consequence: each
real base change opens one non-automerged chart-pin PR per affected chart
(same-tag rebuild automerge is a separate knob, F13). Rejected:
rescan-triggered rebuilds only (ships nothing below HIGH, depends on the
scanner database noticing the fix, and turns the rescan from reporter into
actor) and the hybrid (two mechanisms for hours of gain). Fork switches,
both declared values: the cron expression, and the publish policy
`if-changed` versus `always` (spelled `on-change` in the criteria, since the
EARS validator reserves the word "if").

**F5 (i), the third verb (decided 2026-08-21): compiler-generated
`affected` statements from the exception file.** `compile-vex.sh` reads
`triage/accepted-risk/<image>.yaml` and emits one OpenVEX `affected`
statement per entry into the compiled document for that digest, with the
`action_statement` assembled from the existing fields (treatment,
`statement:`, upstream issue, binary paths as text since OpenVEX has no path
field, expiry) and the decision date as its timestamp. One source of truth,
no extra human step per decision. Spec consequences: Req 6.8 is rewritten
from "never record accept or transfer as a VEX statement" to "never record
them with a status that suppresses; publish them as `affected` with an
action statement"; Req 6.1 coverage is untouched (`affected` and
`under_investigation` never count); `lint-vex-product.sh` gains "`affected`
requires `action_statement`" and "hand-authored `affected` under
`triage/vex/` is forbidden, the exception file owns that status". A lapsed
exception stops compiling and the finding falls back to
`under_investigation` at the next release or rescan. Rejected: hand-authored
`affected` beside the exception (two artifacts, drift) and a human-readable
advisory page instead (invisible to scanner-driven consumers). Prior art
closed: review A 2.2.

**F5 (ii), re-attestation (decided 2026-08-21): the daily rescan
re-attests when the compiled document changes.** For every digest in the
published set (digests currently referenced by any catalogue tag, alias fan
included) the rescan fetches the most recently attested OpenVEX, compares
statement sets with the freshly compiled document, and attests the new
document when they differ. Attestations append, so each digest carries a
dated history and OpenVEX's latest-statement-wins rule resolves it for
consumers; the manual's verification recipe changes from "read the
predicate" to "merge the predicates" (`vexctl merge`). Accepted costs:
`rescan.yml` gains `id-token: write`, widening the signing surface from one
job to two (F6 pins both identities); digests no longer referenced by a tag
are frozen, and what that means for someone still running one belongs to
F9 and F11. Rejected: attest at release only (stale by construction) and an
out-of-band VEX repository as the replacement (unbound from the digest, and
it is F11's advisory-feed question, where it is weighed as a complement).
Prior art closed: review A 3.14.

**F4 (i), ceilings and aperture (decided 2026-08-21): one policy file,
every number a variable.** `triage/policy.yaml` declares the decision
aperture (the severities that require a recorded decision), a per-severity
exception ceiling, a KEV override, and the expiry warning window. Ceilings
are durations, not day counts, so the schema serves both this catalogue
(`CRITICAL: 30d`, `HIGH: 90d`, KEV-listed `14d`, warning `14d`; aperture
`CRITICAL, HIGH`) and a staffed fork that widens the aperture and tightens
the clocks (for example `CRITICAL: 24h`, `HIGH: 48h`, `MEDIUM: 7d`,
`LOW: 30d`). Enforcement splits by knowledge: `validate`'s lint has no scan
and enforces the largest ceiling as the outer bound; the scan gate holds
the Trivy report, fetches the same KEV feed the rescan already uses
(`rescan.yml:42,190`), and enforces the tier per finding; the rescan reads
the same file for warnings and metrics. A ceiling is a re-decision
interval, not a fix deadline: each lapse forces a dated re-decision that
refreshes the published action statement. The aperture line is also the
first written statement that MEDIUM and LOW are outside the decision scope
here. Rejected: hand-recorded `severity:`/`kev:` per exception (facts the
scanner already knows, drift, and the gate must cross-check anyway) and a
flat published 90 (indefensible for a KEV-listed CRITICAL).

*Amended 2026-08-22 (PR #97 revision, finding A3):* the file is the `triage`
section of `catalogue-policy.yaml` at the repository root, which also holds
the release switches and the verification inputs (Req 7.7). The decision,
every number a variable in one committed place, is unchanged; only the path.

**F4 (ii), the clocks (decided 2026-08-21): measured by the rescan tool,
published to a pinned status issue plus a workflow artifact; GitHub Pages
later as pure presentation.** Measurement: *first seen* is the earliest of
the release-time `under_investigation` timestamp and the rescan issue's
creation; *decided* is the first attested statement for that vulnerability
and product with any other status; *fixed* is the first published digest on
the same tag line where the finding is absent or `fixed`. Derived:
time-to-decision, time-to-fix, and the live table of open findings by age
against the F4 (i) ceilings. The rescan's Go tool computes all of it from
attestation history and the issue timeline, with tests. Sink: one
"Catalogue status" issue maintained the way Renovate maintains the
Dependency Dashboard (human table plus a fenced `metrics.json` block), and
the same JSON as a workflow artifact; `SECURITY.md` (F11) links to it as
where the promise is audited. The sink is a declared value. Rejected: bot
commits of a metrics file to `main` (contradicts "everything enters as a
pull request"). Deferred by design: a Pages dashboard, with the JSON schema
written so Pages is presentation only.

*Badges (decided 2026-08-21): (a) now, (b) when the metrics exist.*
(a) Native GitHub badges rendered by shields.io from the public API: open
issues carrying the `cve` label (findings awaiting decision) and workflow
status for `build`, `rescan` and `e2e`; no secrets, no settings. (b) Once
`metrics.json` exists, the rescan publishes it to GitHub Pages
(`pages: write` plus the `id-token: write` it gains in F5 (ii)) and renders
the clock badges itself with `badge-maker` (shields' own library), so no
third party sits in the view path; this is the first deliberate slice of
the deferred Pages layer. Rejected: a gist endpoint (one more long-lived
secret for what OIDC already covers). Rule for any route: only the rescan
writes a badge's number.

**F9, platforms and the published set (decided 2026-08-21): re-point the
legacy tags, keep the digests, publish nothing unscanned, make visibility
an invariant.** (a) The ten multi-arch tags measured above are re-pointed
by a scripted, tested sweep to the amd64 manifest digest already inside
each index, so every tag serves what was scanned; the old index digests
stay pullable by digest (cosign's `.sig`/`.att` tags still reference them)
but leave the published set, and the sweep is recorded in `triage/LOG.md`
with every digest moved. Rejected: deleting the indexes (breaks every digest
pin, irreversibly, for a hazard that is "unscanned" not "known bad";
deletion is F11's revocation tool) and declaring only (leaves Req 2.6
violated under live tags). (b) Forced by Req 2.6 plus F3 (i): arm64 returns
when the release path builds both platforms, pushes the index by digest,
scans each platform manifest, compiles and attests VEX per platform digest,
and the rescan scans every platform; sequenced after F3 (i). arm64 e2e
stays out of scope. (c) Forced by A: `hardened-app` and
`cert-manager-cainjector` are made public by hand now, and the rescan gains
the daily invariant "every catalogue repository answers an anonymous pull".

*Amended 2026-08-22 (PR #97 revision, choice 2):* **(a) is withdrawn.** The
independent review of the cluster A amendment measured that cosign signed only
the index digests (`.sig`/`.att` on every platform manifest return 404), so a
re-pointed tag would have served an unsigned, unattested manifest. The legacy
tags are scanned in place instead: the rescan enumerates every catalogue tag
daily and scans every platform manifest of every tag-referenced digest
(Req 2.18, 2.22), which satisfies Req 2.6 as written and keeps every existing
signature valid. The digests, and the "never delete" reasoning, are unchanged.

**F6, verification identity (decided 2026-08-21): anchor the prose and
ship a tested verification policy, with the engine rendering separable.**
README and manual move to the exact form: issuer pinned, identity anchored
to `https://github.com/mm-weber/dhc-pipeline/.github/workflows/(build|rescan).yml@refs/heads/main`.
The verification *inputs* (issuer, identity list, required attestation
predicate types) live in one declared place; `policies/verify-catalogue-images.yaml`
is the Kyverno `verifyImages` rendering of those values, admitting
`ghcr.io/mm-weber/dhc/*` only with a keyless signature from those identities
and with SBOM and OpenVEX attestations present. A Sigstore
`policy-controller` `ClusterImagePolicy` can be rendered from the same
values on demand or by a fork; not shipped until asked for. Proof lives
where the network is: the rescan applies every rendering that exists daily
to each published digest (must admit) and to one unsigned control image
(must reject), and reports both. `SECURITY.md` (F11) states what a
signature means: the release workflow on `main` produced this digest; it
does not assert human review. Rejected: prose only (transcription exercise,
silently wrong after a workflow rename).

*Amended 2026-08-22 (PR #97 revision, finding 1.11):* the identity list is
split by role. `build.yml` at `refs/heads/main` is the sole signer and sole
SBOM attestor; `rescan.yml` at `refs/heads/main` may attest OpenVEX only, from
cluster B on, and never signs. Roles are attestor lists a fork extends by
adding entries; no role is widened.

**F1, trust root and review (decided 2026-08-21): ruleset as code, honest
bypass, gates required.** The intended ruleset is committed as JSON under
`.github/rulesets/` (GitHub's native export/import format); because the
rulesets API is anonymously readable, the rescan's daily invariants compare
live against committed and report drift with no extra permission. The
committed ruleset adds `build gate` and `e2e gate` to the required checks
and retires the overlapping weaker `branch` ruleset. A `CODEOWNERS` names
the maintainer per lane (`triage/`, `image/`, `chart/`, `policies/`,
`.github/`); `require_code_owner_review` is carried in the committed ruleset
as the documented switch for a second owner. `SECURITY.md` (F11) states:
one maintainer; merges are recorded bypasses of a one-review rule kept
deliberately in force; a signature means the release workflow ran on
`main`, not that a second human looked. Deliberately not added: a protected
release environment with required reviewers, because F3 (iii) publishes
nightly and a human approval point on rebuilds is what a catalogue must not
have; merge-time review is the gate. Rejected: a second maintainer now
(correct at org scale, outside the one-person frame; option 1 makes it a
one-line change) and status quo plus a sentence.

**F2, automerge and the self-updating source checksum (decided
2026-08-21): keep automerge, add a quarantine and a refusal signal, both
declared per authenticity class.** (a) `minimumReleaseAge` of three days
on the `github-tags` and `github-releases` managers: a bump PR opens only
once the release has survived that long in the open; that `github-tags`
supplies the timestamps Renovate needs is measured in the manager
fixtures. (b) The refresh scripts refuse to write a checksum unless the
upstream's declared authenticity signal checks out, the way the grafana
refresh already refuses by name: for the git archetype, GitHub reports the
resolved tag or commit signature as verified (measured 2026-08-21:
cert-manager `v1.21.1` is a GPG-signed annotated tag, valkey `9.1.1` a
lightweight tag on a signed commit, both `verified`; `hardened-app` tags
get SSH-signed to meet the same bar); for the repackage archetype,
independent origins must agree on the checksum (measured 2026-08-21: for
13.0.4, 13.0.6, 13.1.1, 13.1.2 and 13.1.3 across amd64, arm64, armv6 and
armv7, the `grafana.com` versions API sha256 equals the `dl.grafana.com`
sidecar in all 20 cases, and both equal the pins in
`image/grafana/image.yaml:33`; ADR 0002 had deferred this cross-check
"until a real incident argues for it", and this review is the argument).
The class each definition declares (`signed-tag`, `signed-commit`,
`cross-origin-checksum`, `none`, the last refused for new definitions) is
F10's artifact; the signer or agreeing origins go into the bump PR body.
(c) `renovate.json5` and `CONVENTIONS.md` state that the commit sha is
pin-at-bump-time, protecting against later tag rewrites, and that
independence comes from age, signal and gates. Residual risk, stated: a
compromised upstream maintainer with valid keys defeats (b) and patience
defeats (a); the scan gate and e2e remain the behavioural checks and
automerge still requires them green. Grafana bumps stay never-automerged
(ADR 0002). The `.deb`-via-signed-apt-index route (Grafana's GPG key,
signed `InRelease`, package sha256) is recorded in ADR 0002 as the switch
for a stricter bar, not taken now: the apt index measurably lags releases
and grafana carries every open CVE. Rejected: disabling automerge (a queue
for one person that worsens the published clocks) and age without the
signal (forfeits what both upstreams already provide). Fork switches: the
age value, the automerge update types, the per-definition class.

*Checkpoint placement for the repackage comparison (decided 2026-08-21):
all three.* (1) Bump time in `refresh-grafana.sh`: API and sidecar must
agree per architecture before any field is written; refuse by name
otherwise. (2) PR time in `verify-arch-pins.sh`: pinned value, bytes
served, and the API statement must all agree, closing the
`REFRESH_GRAFANA_SHA256_*` hand-feed seam. (3) Daily in the rescan's
invariants: the currently pinned version is re-compared against sidecar
and API, catching republication under the same build id; a mismatch files
an issue labelled as a supply-chain signal. One comparison function,
shared code, one test suite, three call sites; checkpoint 3 generalises to
"every pinned upstream artifact still matches what its origin states
today" once every definition carries a class.

**F10, upstream authenticity (decided 2026-08-21 by consequence of F2):
accept.** Each definition declares its class in a `# authenticity:`
comment marker, following the existing `# renovate:` convention for
tool-facing metadata in frontend-owned files: `signed-tag` (cert-manager),
`signed-commit` (valkey, and `hardened-app` once its tags are signed),
`cross-origin-checksum` (grafana), `none` (lint refuses it for new
definitions). The refresh scripts enforce the declared class at bump time,
`verify-arch-pins.sh` at PR time, the rescan daily. Consumer-facing: the
chart README and `SECURITY.md` state the class per image, so "verified" is
never read where the truth is "independent origins agree". The `.deb`
route for real cryptographic authenticity on grafana is the documented
switch in ADR 0002.

**F7, scanner monoculture (decided 2026-08-21): Grype as a measured second
consumer, a daily consumer smoke test, consumers as a declared list.**
The VEX consumers are a declared list, each a small adapter with the same
contract: install pinned and verified (Req 7.5), scan a digest with the
compiled per-digest VEX, emit findings in one normalised shape
(vulnerability, purl, suppressed or not). The gate's scanner stays
authoritative; every other listed consumer feeds a *VEX portability* block
in the PR and rescan summaries: for each statement that suppressed in the
authoritative scanner, whether the equivalent finding was suppressed in
each other consumer, divergences named. Informational first, like
govulncheck; a fork flips it to gating. Shipped list: Trivy
(authoritative), Grype (measured 2026-08-21: grype 0.116.0 accepts
`--vex`). Docker Scout is an adapter a fork adds to the list, not shipped
(credentials, a third pinned CLI). Separately, the rescan runs the manual's
consumer recipe verbatim against one published digest daily (`cosign
verify-attestation` with the F6 identity, `vexctl merge`, `trivy --vex`,
`grype --vex`) and asserts the suppressions land, turning the README's
verification section into a tested contract. Rejected: Trivy only with the
limitation documented (leaves Req 6.34's purpose unverified). Prior art
closed: review A 2.5.

**F8, valkey compat (decided 2026-08-21): a transfer-shaped compat
decision plus the upstream PR.** The upstream change is drafted in
`triage/upstream/` with the measured evidence (unconditional init
container, same image helper as the main container, metrics-exporter image
helper as precedent) and filed against `valkey-helm`: an
`initContainer.image` value defaulting to the main image, and
`initContainer.enabled` if accepted. The compat decision moves from prose
into structured metadata in `chart/valkey/chart.yaml` (`compat:` with
reason, upstream reference, review-by date), lint-checked; Req 4.5 is
amended so every compat decision carries an upstream reference and a
review date and is re-decided when the date lapses. When upstream ships
the knob, the overlay splits images: runtime variant for `valkey-server`,
`-compat` for the init container only (both ours, so `restrict-registries`
holds); the compat build continues with its blast radius reduced to
seconds at start. Rejected: vendoring a patched chart (violates Req 4.1,
rebase cost on every bump) and documenting only. Fork switches: the
review-by field, and whether a chart may use compat at all.

**F11, security posture of the catalogue itself (decided 2026-08-21):
`SECURITY.md`, private reporting, repository advisories, a
machine-readable revocation record.** `SECURITY.md` states the promise in
A's words; the aperture and ceilings by reference to `triage/policy.yaml`;
what "published" and "frozen" mean (F3 i, F9); what a signature means and
the one-maintainer bypass (F1, F6); the authenticity class per image
(F10); the Rekor disclosure fact; and links to the status issue (F4 ii).
GitHub private vulnerability reporting is enabled (measured 2026-08-21:
currently disabled) and the rescan's invariants assert it stays enabled.
Repository security advisories (GHSA) are the catalogue-level advisory
channel. `triage/revocations.yaml` (digest, reason, replacement digest,
advisory link, date) is the lint-checked record that drives the mechanics:
the F9 sweep script re-points or removes tags, the status issue lists the
revocation, and a daily invariant asserts no catalogue tag points at a
revoked digest; the runbook in `docs/` is therefore short. Deferred to the
Pages layer: a Trivy-compatible VEX repository publishing compiled VEX for
every digest ever published, frozen ones included, as the complement to
F5 (ii). Rejected: policy and advisories without the record (revocation
improvised under pressure, never re-asserted) and standing up the VEX
repository before Pages exists for other reasons.

**F12, attribution and terms (decided 2026-08-21): attribution rewrite
and a trust-boundary table now; terms research by the owner; the public
claim gated on it.** README and design Overview state: hardening substrate
by Docker Hardened Images (frontend, builders, apk repositories and their
signing key); this catalogue contributes the operating model (definitions,
triage lanes, chart adaptations, tests, the published promise and its
invariants). A trust-boundary table in `docs/concepts.md` and `SECURITY.md`
lists every component with its owner: inherited from DHI, inherited from
an upstream (with its F10 class), or ours; it doubles as the fork's
substrate switch. The DHI terms and Community-tier conditions are pulled
by the owner on the host into `data/` (research inputs cover tiers and the
Apache-2.0 catalog, `data/docker_internal_build.md:12`, but not
redistribution); the disposition is recorded afterwards, and until then
the README does not use the words "production-ready". Rejected:
attribution without the terms answer; changing substrate (removes the
learning objective; a fork's option, which the table supports).

*Terms answered (2026-08-21): `data/dhi-terms-2026-08-21.md`.* Building
derived images on the Community tier and redistributing them publicly is
permitted, with the permission flowing from the Apache-2.0 licence on the
catalog and not from the Docker Subscription Service Agreement, whose
§2.1 "not on a standalone basis" clause is not reconciled with that grant
in any Docker document. The memo's two routes: "Stage 1", ship runtime
layers free of DHI-origin content; "Stage 2", ship them and carry the
obligations. **This catalogue is Stage 2 by design**: every runtime image
installs packages from `dhi.io/apk`, and the substrate is the learning
objective; Stage 1 is rejected for the same reason changing substrate was.
Obligations adopted, all into cluster D unless noted:
(a) Apache-2.0 §4(a)/(c): a notice file in the repository naming Docker
Hardened Images (Copyright 2025 Docker Inc., Apache-2.0) and stating that
third-party packages carry the upstream licences enumerated in the attested
SBOM; the same notice inside each image if the frontend can add a file
(measured at implementation). The SBOM attestation already satisfies "ship
or link the SBOM".
(b) Apache-2.0 §4(b): no definition is a copy of a catalog file (measured
2026-08-21: own-authored, kept close to exemplars, `docs/decisions/0001-build-layer.md:57`),
so no modification notices are due; `CONVENTIONS.md` records that a
definition copied from the catalog must carry one.
(c) Trademark (§6 and Docker's guidelines): descriptive use only. README and
`CLAUDE.md` drop "DHI-style" as a label in favour of "built with Docker
Hardened Images tooling and packages", with an explicit sentence that the
project is not affiliated with or endorsed by Docker, Inc.; no logos; the
`dhc` names stay.
(d) Memo Q4: a lint admits only `dhi.io/apk/<distro>/<version>/main` (and
the `dhi.io/deb/…/main` shape) as package repositories in definitions and
refuses the entitlement-gated `security` and `els` paths (measured
2026-08-21: all seven definitions use `/main`). Lands with cluster C's
definition lints. Fork switch: an entitled fork extends the allowlist.
(e) The residual DSSA-versus-Apache ambiguity is stated in `SECURITY.md`
with the dated memo as evidence; the memo's sources are re-verified by
2026-11-21, tracked as a deliberate human item in the F13 register.
(f) "production-ready" wording is unblocked once (a), (c) and (d) land; the
claim carries the sentence from (e).
Owner-side and optional: seek an explicit statement from Docker on
free-tier standalone redistribution (memo Stage 3, item 6); save the cited
pages as accessed into `data/`.

**F13, human-per-item controls (decided 2026-08-21): a manual-controls
register, three automations, one mechanical link.** The register lives in
`docs/CONVENTIONS.md` (step, class, why, fork switch). *Deliberate, keep*:
tool sha256 completion (F2's principle), build-layer bumps reviewed by
hand (a toolchain change moves stdlib CVEs in every compiled image), the
VEX and exception decisions themselves (`vexctl` stays the authoring tool;
judgement is the human's). *Automate*: (i) evidence-based issue closing
(F4 iii): the rescan closes a `cve` issue when the finding no longer
appears in any published digest the issue named, or when a merged VEX
statement or exception now covers it, commenting digest, date and artifact
and applying a `resolved:*` label; it acts on derived state only, never on
judgement. (ii) Chart version tracking: a regex manager over
`chart/<name>/chart.yaml` (`upstream.name`, `upstream.repository`,
`upstream.version` are already the shape the native `helm` datasource
needs), never automerged because a chart bump runs the e2e upgrade path.
(iii) Same-tag digest bumps of chart image pins automerge on green e2e
(the knob deferred from F3 iii); tag bumps stay human. *Mechanically
linked*: `triage/LOG.md` stays prose; the lint validates that every `ref:`
in an exception and every LOG citation in a VEX statement resolves to a
real heading and that every decision has one. Rejected: register only
(open issues never close, the status board inflates, chart pins lag as in
task 8.7) and the unified ledger now (right direction per the 2026-08-04
review, wrong size for one person; option 1 is the incremental path a fork
can finish).

---

## 6. Amendment sequence

Two operator actions need no spec and should not wait: make
`hardened-app` and `cert-manager-cainjector` public on GHCR (F9 c), and
add `build gate` and `e2e gate` to the live `main_sec` ruleset's required
checks (F1), since today a pull request can merge over a red scan gate.

The spec amendments land in dependency order, one pull request per
cluster, each carrying EARS criteria in `requirements.md`, rationale in
`design.md` and tasks in `tasks.md` before any implementation pull
request (the repo's amend-first rule). Requirement numbering continues
each group (next free: 1.9, 2.7, 3.7, 4.8, 5.8, 6.35, 7.7, 8.3); new
groups start at Req 9.

| Cluster | Findings | Spec surface |
|---|---|---|
| A. Release path and the published set | F3 (i–iii), F9, F6 | Req 2 (push by digest, scan before tag, `under_investigation`, scheduled rebuild, publish-if-changed, per-platform scanning, visibility invariant), Req 1 (apk float in the pinning contract), verification policy artifact |
| B. Statuses and clocks | F5 (i–ii), F4 (i–ii), F13 (i) | Req 6 (`affected` from exceptions, Req 6.8 rewrite, re-attestation, `triage/policy.yaml`, metrics and status issue, evidence-based issue closing) |
| C. Upstream trust | F2, F10, F8, F13 (ii–iii) | Req 3 (quarantine, automerge types, chart version manager, same-tag digest automerge), Req 1.3 (authenticity class and refusal), Req 4.5 (compat as transfer with review date), ADR 0002 amendment |
| D. Catalogue posture | F1, F11, F12, F7, F13 register | New Req 9 (trust statement, ruleset as code and drift invariant, CODEOWNERS, `SECURITY.md`, private reporting, advisories, revocation record, consumer list and smoke test, manual-controls register, trust-boundary table) |

Deferred by design, recorded where each decision lives: the Pages layer
(metrics dashboard, self-rendered badges, the VEX repository for frozen
digests), the Docker Scout adapter, the policy-controller rendering, the
`.deb` route for grafana, the unified ledger, arm64 e2e. Each is a switch
or an adapter a fork adds, not a redesign.

### 5.3 Disposition ledger

Filled in during the dialogue, one row per decision. Dispositions: `accept`,
`accept with modification`, `reject` (with the reason recorded in the
finding), `defer` (with the primitive that is put in place now).

| # | Finding | Disposition | Spec impact (candidate) | PR |
|---|---|---|---|---|
| F1 | One account, self-review; `build gate`/`e2e gate` not required checks | accept (5.2): ruleset as code with drift invariant, gates required, CODEOWNERS, honest bypass statement | Req 7 (review enforcement), new trust statement in design, SECURITY.md | |
| F2 | Automerge scrutiny, self-updating source checksum | accept (5.2): 3-day quarantine, refusal on the declared authenticity signal, residual risk stated; comparison at bump, PR and daily | Req 3.5, Req 1.3, ADR 0002 amendment | |
| F3 | Signed ≠ scanned; floating packages; no scheduled rebuild | accept, three parts (5.2): (i) publish with status; (ii) float by design, declared; (iii) daily rebuild, publish if changed | Req 2.2, Req 2.6, Req 6.1, CONVENTIONS pinning | |
| F4 | No clock; HIGH-only aperture; flat ceiling | (i) accept: policy file, tiered durations, declared aperture (5.2); (ii) accept: rescan-computed clocks, status issue + artifact, Pages later (5.2); badges: native now, self-rendered on Pages later; (iii) issue closing folded into F13 | Req 6.3, Req 6.11 | |
| F5 | No `affected` + `action_statement` artifact | accept, two parts (5.2): (i) compiler-generated `affected` from exceptions; (ii) rescan re-attests on change | Req 6.4, Req 6.8, compiler | |
| F6 | Unanchored verification identity | accept (5.2): anchored identities, Kyverno verifyImages from declared values, daily admit/reject proof; policy-controller rendering on demand | Req 2.2, README + manual, policy artifact | |
| F7 | Single-scanner VEX validation | accept (5.2): consumers as a declared list, Grype portability block, daily consumer smoke test; Scout as a fork's adapter | Req 6.6, Req 6.34 | |
| F8 | valkey compat ranking; upstream not asked | accept (5.2): upstream PR for `initContainer.image`, compat as structured transfer with review date, image split on merge | Req 4.5, chart.yaml schema | |
| F9 | amd64 only; legacy arm64 manifests; two repositories private | accept (5.2): re-point legacy tags, arm64 back only per-platform-scanned, visibility invariant | Req 2.1, Req 2.6, task 8.3, new visibility criterion | |
| F10 | Grafana same-origin checksum anchor | accept by consequence of F2 (5.2): `# authenticity:` class per definition, enforced at bump, PR and daily; `.deb` route documented as switch | Req 1.3, definition metadata, ADR 0002 | |
| F11 | No SECURITY.md / advisories / revocation; private reporting disabled | accept (5.2): SECURITY.md, private reporting + invariant, GHSA channel, `triage/revocations.yaml` driving sweep + invariant; VEX repository deferred to Pages | new Req group (catalogue security posture) | |
| F12 | Substrate attribution; redistribution terms | accept (5.2): attribution rewrite + trust-boundary table; terms answered in `data/dhi-terms-2026-08-21.md`: Stage 2 by design, Apache-2.0 notice, descriptive-use wording, `/main`-only repository lint, residual DSSA ambiguity stated | README, design Overview, concepts.md, SECURITY.md, definition lint | |
| F13 | Human-per-item controls, labelled or not | accept (5.2): manual-controls register; automate issue closing, chart version tracking, same-tag digest automerge; LOG anchors lint-linked | Req 3, Req 6, CONVENTIONS | |
