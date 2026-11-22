# PR #97, cluster A spec amendment: independent adversarial review, 2026-08-21

**Subject:** `spec-cluster-a` at `822f6b1` against `main` at `12a19e9`: four files,
153 insertions, 7 deletions (`.specs/dhc-catalogue-mvp/requirements.md`, `design.md`,
`tasks.md`, `tasks/todo.md`). The PR claims to encode the cluster A decisions of
`reviews/2026-08-21-production-readiness-critique.md` (F3 i to iii, F9, F6) as Req 1.9,
Req 2.7 to 2.25 and Req 6.35 to 6.36, with Key Design Decision 6, a release-flow
diagram, task group 9 and a coverage-table update. No workflow, script or policy changes.

**Method.** Read with no prior involvement: `CLAUDE.md`, `docs/CONVENTIONS.md`, the full
PR-side `requirements.md`, `design.md` and `tasks.md`, the review document (sections 2,
5.2, 6 and the ledger), then the real pipeline the criteria have to run on:
`.github/workflows/build.yml`, `rescan.yml`, `scripts/compile-vex.sh`,
`definition-lib.sh`, `verify-arch-pins.sh`, `policies/`, `triage/vex/`, the seven
definitions, `README.md` and `docs/user-manual.md`. Tool runs: the repo's EARS validator
on the PR branch (98 valid, 0 invalid; main has 76, so exactly the 22 new criteria were
added); the `spec-validate` procedure followed by hand (results in section 4); the
`code-review` skill launched against the branch (see section 4 for what it returned); the
`ears-notation` skill's rules and pattern reference used for section 1. Where a finding
turned on what the registry actually holds, it was measured with anonymous reads against
`ghcr.io` (allowlisted; script and output kept beside this file as
`2026-08-21-cluster-a-independent-review.measure.sh` / `.measure.out`): token endpoint per repository, the index of
every current release tag and of three legacy tags, and the existence and predicate
types of cosign `.sig` / `.att` objects on index and platform digests. The PR is judged
on its own text; the review document is used only to check faithfulness.

**Verification legend**

| | |
|---|---|
| **[V]** | verified directly against the tree or the git history, with `path:line` |
| **[M]** | measured 2026-08-21 by anonymous reads against `ghcr.io/mm-weber/dhc` |
| **[R]** | reasoned from documented tool behaviour (buildx, cosign, Trivy, Syft, Kyverno, OpenVEX), not measured here; the task that implements it should measure first |

**How to read.** Findings are ordered by severity. Each carries a diagnosis and, where a
criterion is defective, a concrete rewording. Section 3 lists what was checked and found
sound, so the findings are read as aimed at the gaps, not at the decision.

---

## 1. Findings

### 1.1 **[V][M]** Req 2.10, 2.23 and 2.24 make an OpenVEX attestation a condition of "published", and five of six repositories never receive one

**Claim.** Req 2.10 (`requirements.md:56`) defines a published digest as one that is
tagged and "carries a cosign signature, an SPDX SBOM attestation and an OpenVEX
attestation". Req 2.23 (`:69`) requires the verification policy to admit an image only
"together with an SPDX SBOM attestation and an OpenVEX attestation". Req 2.24 (`:70`)
fails the daily run on any published digest the policy rejects.

**Evidence.** The release arm attests OpenVEX only for documents the compiler wrote:
`build.yml:650-657` loops `"$VEXATTEST"/*.json` under `nullglob` and reports
`${n} OpenVEX statement(s) attested` with `n` allowed to be 0. `compile-vex.sh:153-158`
never writes an emptied document, by design ("a file a scanner reads and learns nothing
from"). Every statement in `triage/vex/` names `pkg:oci/grafana` (three files, four
statements, all grafana). So every release of `hardened-app`, `cert-manager-controller`,
`cert-manager-webhook`, `cert-manager-cainjector` and `valkey` (both definitions) has
carried no OpenVEX attestation at all. Measured **[M]**: the `.att` object on each current
release's index digest carries predicate types `https://spdx.dev/Document` ×1 and nothing
else for `hardened-app:0.1.0-alpine3.23`, all three `cert-manager-*:1.21.1-alpine3.23`,
`valkey:9.1.1-alpine3.23` and `valkey:9.1.1-alpine3.23-compat`; only
`grafana:13.1.3-alpine3.23` carries `https://openvex.dev/ns` (×3) beside it.
`README.md:28-29` and `docs/user-manual.md:146-148` already overstate this ("carries an
SPDX SBOM, OpenVEX, and BuildKit provenance"); the PR turns the overstatement into a
definition.

**Consequence.** On the day the definition merges, most of the registry is "not
published" by Req 2.10 while still tagged (neither published nor frozen: see 1.3). The
moment task 9.6 lands, the Kyverno policy rejects every clean image and Req 2.24 turns
the rescan permanently red. A clean image (no finding, no applicable statement) has
nothing to say in OpenVEX, and Req 2.12 only adds `under_investigation` statements for
uncovered findings, so clean images stay attestation-less under the PR's own rules.

**Diagnosis.** The criteria need a rule for "nothing to state". Two shapes are possible;
the PR must pick one and say so, because a Kyverno `verifyImages` rule cannot express
"OpenVEX required only when findings exist":

- (a) Always attest exactly one compiled OpenVEX document per release, possibly carrying
  zero statements. Trivy and go-vex accept an empty `statements` list **[R]**; the OpenVEX
  specification describes `statements` as a list of one or more **[R]**, so this is a
  tension to measure (does `vexctl`/Trivy accept it, does Kyverno's predicate-type match
  still pass) before Req 2.9 relies on it. Rewording of Req 2.9: "... attest its SPDX SBOM
  and one compiled OpenVEX document, carrying every applicable statement or none, to it,
  and SHALL apply its definition-derived tags only after those attestations exist."
- (b) Drop the OpenVEX clause from Req 2.10 and Req 2.23 and carry it as a separate,
  conditional check: "IF any compiled statement applies to a digest THEN THE Catalogue
  SHALL treat that digest as published only while it carries an OpenVEX attestation."
  This keeps the policy honest but loses the in-band guarantee that every consumer finds
  a VEX predicate.

(a) is the one that keeps promise A ("every known finding against a published digest
carries a published machine-readable status"), since a document with zero statements is
itself the status "nothing known". Either way `compile-vex.sh`'s "never write an emptied
document" contract and its tests change, and task 9.1 should name that.

### 1.2 **[V][M]** Req 2.22 and task 9.5 re-point ten tags to digests that carry no signature, no attestation and no provenance

**Claim.** Req 2.22 (`requirements.md:68`) re-points a legacy tag "to its scanned
manifest digest"; task 9.5 (`tasks.md:231`) spells it out: "re-point the tag to the amd64
manifest digest already inside the index (`imagetools create`)". The review decided the
same (F9 a, review `:749-758`). Nobody, including the review, checked where the signature
lives.

**Evidence.** `cosign sign --yes "$REF"` has never carried `--recursive`:
`build.yml:598-602` today, and `git log -S'--recursive' -- .github/workflows/build.yml` is
empty back to the step's introduction in `fb9f5d7` (2026-07-20). Without `--recursive`,
cosign signs the digest it is given, the index; the platform manifests inside it are
unsigned. Measured **[M]** on the three legacy indexes named in task 9.5
(`grafana:13.0.4-alpine3.23` → `b6987eb3…`, `valkey:9.0.5-alpine3.23` → `b75aa680…`,
`cert-manager-controller:1.20.3-alpine3.23` → `44be33e5…`): `sha256-<index>.sig` and
`.att` answer HTTP 200; `sha256-<amd64 manifest>.sig` and `.att` answer HTTP 404, and so do
the arm64 ones. The same holds for every current amd64-only release (platform manifest
`.sig`/`.att` 404 on all seven). The SBOM and OpenVEX attestations are attached to the
index digest (`build.yml:617`, `:654`), and the legacy `.att` objects carry only
`https://spdx.dev/Document`. BuildKit provenance lives in the index's two
`unknown/unknown` attestation manifests (measured: each legacy index lists amd64, arm64
and two `attestation-manifest` children), which reference the platform manifests but are
not part of them. The review's own sentence concedes the location: "the old index digests
stay pullable by digest (cosign's `.sig`/`.att` tags still reference them)" (review
`:753-754`).

`docker buildx imagetools create -t <tag> <repo>@<amd64 manifest digest>` produces one
of two things **[R]**: with the default `--prefer-index`, a new single-entry index (a new
digest nobody signed); with `--prefer-index=false`, a carbon copy of the bare amd64
manifest (the digest task 9.5 names, also unsigned). In both cases the consumer who pulls
`grafana:13.0.4-alpine3.23` afterwards gets an image that fails `cosign verify`, has no
SBOM or VEX predicate and no provenance, where before the sweep it had all four on the
index.

**Consequence.** The sweep creates the third state the PR's definitions do not name:
tagged, but not signed or attested (not published by Req 2.10, not frozen by Req 2.11).
Req 2.24 would not catch it, because it iterates "every published digest" and these are
not published by definition (see 1.4). `README.md:28` ("Every image published to
`ghcr.io/mm-weber/dhc` is signed") becomes false for ten tags on the day the operator runs
the script.

**Diagnosis.** Three consistent options; the PR should choose in the spec, not leave it to
task 9.5:

- (a) The sweep signs and attests what it tags. That needs `id-token: write` under the
  `build.yml` identity the verification policy admits, so it is a `workflow_dispatch` job
  in `build.yml` (scan the amd64 manifest per Req 2.8, compile VEX for the new digest, SBOM
  it, sign, attest, then tag), not a host-side `docker login` as task 9.5 offers.
  Rewording of Req 2.22: "... THE Catalogue SHALL publish that tag's scanned platform
  manifest through criteria 2.8 and 2.9 and re-point that tag to the resulting digest,
  and SHALL record ...". Provenance cannot be recreated for a 2026-07 build; the LOG entry
  should say the re-pointed digests carry none.
- (b) Take the review's rejected-by-omission option, "rescan them": once the rescan scans
  every platform manifest of every tagged digest (Req 2.18 applied to the whole published
  set, see 1.4), the legacy arm64 manifests are scanned, the WHEN clause of Req 2.22 is
  false, nothing is re-pointed, signatures and provenance stay intact, and Req 2.6 is
  satisfied as written. This is the smallest change and the most faithful to Req 2.6's
  text; it costs ~35 s per platform per image per day (`tasks.md:175`). The review's
  objection to arm64 was "nothing scanned it", not "it is known bad" (review `:756-757`).
- (c) Keep the re-point but declare those ten tags unsupported and unsigned in the LOG and
  README. Weakest, but honest.

Whichever is chosen, Req 2.24 must test tagged digests, not published ones (1.4), or this
class of defect is invisible to the daily proof by construction.

### 1.3 **[V]** "Published set" is defined but nothing enumerates it; Req 2.6 and 6.2 are now knowingly unmet for every non-current tag

**Claim.** Req 2.10 makes every tagged, signed, attested digest published, alias fan
included (a definition's three tags, `image/grafana/image.yaml`: `13-`, `13.1-`,
`13.1.3-alpine3.23`, plus every older full tag still in the registry). Req 2.6
(`requirements.md:52`, unchanged) says a published platform is scanned; Req 6.2 (`:121`)
says published images are rescanned daily; Req 2.18, 2.22 and 2.24 all quantify over
published digests or catalogue tags.

**Evidence.** `rescan.yml:75-81` iterates `image/*/` and scans `yq '.tags[0]'` only: one
tag per definition, the current major alias, resolving to the latest digest. Nothing reads
the registry's tag list. So `grafana:13.0.4-alpine3.23`, `cert-manager-*:1.20.3-alpine3.23`
and every other superseded full tag is published by Req 2.10 and rescanned by nobody, on
either platform. Task 9.6 (`tasks.md:235`) applies the policy "to a manifest listing every
published digest" without saying where that list comes from; no task builds it. The review
planned the enumeration for cluster B's re-attestation ("for every digest in the published
set (digests currently referenced by any catalogue tag, alias fan included)", review
`:683-685`), but cluster A is where "published" is defined and where Req 2.24 needs it.

**Diagnosis.** Either add the enumeration to cluster A or scope the definition down; the
PR currently does neither and leaves Req 2.6 contradicted by its own definition.
Suggested criterion (Req 2.26, Scan Pipeline): "THE Scan Pipeline SHALL enumerate at least
once per day every catalogue tag in every catalogue repository and the digest each
references, excluding cosign signature and attestation tags, and SHALL use that list for
criteria 2.18, 2.22 and 2.24." Then Req 6.2's "published images" reads against that list,
and Req 2.22's detection becomes automatic (the rescan reports any tagged index holding an
unscanned platform manifest) with the re-point as the operator's response rather than a
criterion satisfied by a one-off manual run. If the owner prefers to keep the rescan's
current scope, Req 2.10 must say "referenced by a current release tag of a definition",
which contradicts the review's "alias fan included"; say which.

### 1.4 **[V]** Req 2.24 tests "published" digests, which by Req 2.10 cannot fail the policy

**Claim.** Req 2.24 (`requirements.md:70`): apply the policy "to every published digest
... and SHALL report any published digest that policy rejects". A digest the policy
rejects lacks a valid signature or attestation, so by Req 2.10 it is not published; the
reportable set is empty by definition. The check the decision wanted (review `:777-780`)
is "every digest a tag serves admits".

**Rewording.** "WHEN THE Scan Pipeline runs its daily checks THE Scan Pipeline SHALL apply
that verification policy to every digest a catalogue tag references and to one unsigned
control image, and SHALL report any tag-referenced digest that policy rejects or any
control image that policy admits as a failure of that run." This is also what would have
caught 1.2. The control image needs a declared identity (see 1.12).

### 1.5 **[V]** The two declared switches contradict their default criteria; EARS WHERE carries no precedence

**Claim.** Req 2.12 (`requirements.md:58`) is an unconditional IF/THEN: an uncovered
finding at release time means the compiler adds `under_investigation` and "THE CI
Pipeline SHALL complete that release". Req 2.13 (`:59`), WHERE fail-closed is enabled,
says apply no tag and attest nothing. With the setting on, both are mandatory and
contradict. Same shape between Req 2.9 (`:55`, sign and tag WHEN the scan completes, no
condition on its outcome) and Req 2.13, and between Req 2.15 (`:61`, discard on equality,
unconditional) and Req 2.17 (`:63`, WHERE policy is `always`, publish regardless).

**Diagnosis.** The ears-notation rules have no "unless" clause; the default criterion has
to carry its own condition. Rewordings (all validate against the repo's patterns):

- Req 2.9: "WHEN a pushed digest's release-time scan completes and criterion 2.13 does
  not withhold that digest THE CI Pipeline SHALL sign ..." (cross-references to criteria
  are already house style: Req 2.16, 2.17).
- Req 2.12: "WHILE the declared fail-closed release setting is disabled IF a release-time
  scan reports a HIGH or CRITICAL finding covered neither ... THEN THE VEX Compiler SHALL
  add to that digest's compiled document an OpenVEX statement recording status
  under_investigation for that finding with a timestamp." and a separate Req 2.12a for
  the pipeline half: "WHILE the declared fail-closed release setting is disabled WHEN a
  release-time scan reports an uncovered HIGH or CRITICAL finding THE CI Pipeline SHALL
  complete that release." (This also fixes the two-actor, two-behaviour criterion.)
- Req 2.15: "WHILE the declared publish policy is set to if-changed WHEN a scheduled
  rebuild produces an image whose resolved package set ... equals ... THE CI Pipeline
  SHALL discard that image and publish nothing from it."
- Req 2.13 says "attest nothing" but not "sign nothing"; the flow diagram
  (`design.md:185`) says "no attestation, no tag"; add the signature to both, since a
  signed, untagged, unscanned-clean digest is exactly what the setting exists to prevent.

### 1.6 **[M]** "Platform manifest" is undefined, and every pushed digest is already an index with a non-platform manifest in it

**Claim.** Req 2.8 (`requirements.md:54`) scans "once per platform manifest it contains";
Req 2.18 (`:64`) and 2.19 (`:65`) quantify over "every platform manifest that digest's
index contains"; Req 6.36 (`:155`) triggers on "an image index containing more than one
platform manifest".

**Evidence.** `build.yml:201` pushes with `provenance: mode=max`. Measured **[M]**: every
one of the seven current release tags resolves to an
`application/vnd.oci.image.index.v1+json` whose children are one `linux/amd64` manifest
and one `unknown/unknown` manifest annotated
`vnd.docker.reference.type=attestation-manifest`; the legacy multi-arch indexes carry
two platform manifests and two attestation manifests. `steps.build.outputs.digest`
(`build.yml:601`) is therefore already an index digest today, which is also why
`imagetools inspect --format '{{json .Provenance}}'` (`README.md:43`) works. The tree
knows the attestation manifest exists (`docs/decisions/0001-build-layer.md:23`,
`docs/concepts.md:162`) but has never written down its platform value, which is the
detail the loop has to filter on. A loop over `manifests[]` that does not exclude that entry would
run Trivy with `--platform unknown/unknown` (fails), and Req 2.19 would then block every
tag for an unscanned "platform manifest".

**Diagnosis.** Add a definition line under Req 2 (house style permits prose between the
objective and the criteria, as Req 6's design section does for "compiled"): "A platform
manifest is a manifest an image index lists with a platform other than unknown/unknown
and without a `vnd.docker.reference.type` annotation." Drop the restriction in Req 6.36:
an index with one platform manifest still has a platform digest a consumer can pin, and
"covering that index's digest and every scanned platform manifest digest" is correct and
simpler without "containing more than one platform manifest". Task 9.1 and 9.3 should
name the filter.

### 1.7 **[V]** A release-time scan that fails is unspecified, and "completes" admits it

**Claim.** Req 2.9 fires "WHEN a pushed digest's release-time scan completes". A Trivy DB
outage, a registry 5xx or a `--platform` resolution error completes the step with no
report. Nothing says the release then stops. The design's error table
(`design.md:604-611`) has a row for the PR gate and the rescan ("Trivy DB outage: PR gate
hard-fails (retryable); daily rescan soft-fails") and none for the release arm, which is
the arm this cluster creates. Without a rule, the simplest implementation (Trivy with
`--exit-code 0`, as both existing call sites use: `build.yml:326`, `rescan.yml:138`)
signs an unscanned digest and re-opens review A finding 1.3 on the path that was meant to
close it.

**Rewording.** Add Req 2.9a: "IF a pushed digest's release-time scan produces no report
for any platform manifest THEN THE CI Pipeline SHALL sign nothing, attest nothing and
apply no tag to that digest, and SHALL report the failing scan in that run." Then Req 2.9
reads "completes with a report for every platform manifest". Add the row to the error
table, and (from Angle B, B7) the other outcomes this cluster introduces and the table
never names: fail-closed withholding (2.13), a discarded scheduled rebuild (2.15), an
unscanned platform manifest blocking a tag (2.19), a repository failing the visibility
check (2.21) and a tagged digest the policy rejects (2.24). Each is a response an
implementer would otherwise invent.

### 1.8 **[R]** One SBOM per index cannot satisfy "per platform", and attestations on the index are invisible to a consumer who pins a platform digest

**Claim.** Req 2.9 attests "its SPDX SBOM" (one); Req 1.9 (`requirements.md:39`) says
"each published digest's resolved package set is recorded in its attested SPDX SBOM";
Req 2.15 and 2.16 compare package sets "per platform". Syft given an index digest
describes the platform matching the runner unless told otherwise **[R]**
(`anchore/sbom-action`, `build.yml:604-611`, passes no platform). Once 9.3 publishes
two platforms, the attested SBOM describes amd64 only, the arm64 package set is recorded
nowhere, and the per-platform comparison has no attested side to compare against.

Separately, `cosign sign`, `cosign attest` and task 9.1 all act on the index digest. A
consumer or admission controller that pins a platform manifest digest and runs
`cosign verify-attestation <repo>@<platform digest>` finds nothing **[R]**. Req 6.36
covers this for VEX *identifiers* but not for where the attestation hangs; the review's
wording was "compiles and attests VEX per platform digest" (review `:760-761`), and the PR
narrowed it to identifiers without saying so.

**Rewording.** Req 2.9: "... attest an SPDX SBOM for each platform manifest and its
compiled OpenVEX documents to it ..."; add to the design, or to Req 2.25, the statement
of what consumers must verify (the index digest) or sign and attest recursively so both
forms verify. Measure `cosign sign --recursive` and the attestation equivalent in task 9.1
before choosing.

### 1.9 **[V]** The release-flow diagram contradicts Req 2.8 and task 9.2 on ordering, and "discard" is undefined for a digest already pushed

**Claim.** `design.md:176-183` orders: push by digest, scan, compile VEX, sign and attest,
then "scheduled run only: package set equal ...? discard", then tag. Two problems.

- The scan needs the compiled VEX as input (Req 2.8: "applying every compiled VEX
  document"), so compilation precedes the scan; what follows the scan is the *append* of
  `under_investigation` statements (Req 2.12), a second compiler pass that task 9.1
  (`tasks.md:213`) folds into one sentence. The diagram elides the first pass and makes
  the second look like the whole.
- The discard decision sits after sign and attest. Task 9.2 (`tasks.md:219`) has the
  comparison first ("equal discards, different publishes through 9.1"). Req 2.15 says
  "discard that image and publish nothing from it", but by then (per the diagram) the
  image is pushed by digest, signed and attested. An untagged digest cannot be
  "discarded" from GHCR without a package-version delete (a permission the job does not
  hold), so the diagram's order leaves one signed frozen digest per definition per day in
  the registry. The ledger's reason for publish-if-changed was precisely that "provenance
  timestamps alone never mint a digest" (review `:651-652`).

**Diagnosis.** Put the comparison before the push: build, SBOM the build output locally
(or push by digest and compare before anything is signed), compare, stop if equal; then
compile, scan, append, sign, attest, tag. Define "discard" in Req 2.15: "apply no tag,
sign nothing and attest nothing for that image, and delete its pushed digest where one
exists" or "push nothing from it", whichever the implementation can keep. Redraw
`design.md:176-183` to match, and say in task 9.2 that `package-set-diff.sh` runs before
9.1's push.

### 1.10 **[V]** The scheduled rebuild does not reach the matrix as `build.yml` stands, and Req 2.7's trigger excludes two of the three events that publish

**Evidence.** `build.yml:20-29` has no `schedule:`; adding one lands the event in the
`changes` job's final branch (`build.yml:98-101`): `github.event.before` is empty on a
schedule, so the range becomes `HEAD~1...HEAD`, the name list is whatever the last commit
touched under `image/` (normally nothing), `any=false`, and `release` is skipped
(`build.yml:111`). Task 9.2 says "building every definition" without naming the `changes`
change it needs (the `workflow_dispatch` branch at `:59-61` already has the "all
definitions" shape to reuse). Also `workflow_dispatch` on `main` pushes and signs today
(`build.yml:140`, `:190`, `:595`), and the schedule will; Req 2.7's WHEN clause ("a
definition change merges to main") covers neither, while Req 2.16 and 2.17 route the
schedule "through criteria 2.7 to 2.9", whose trigger then does not hold.

**Rewording.** Req 2.7: "WHEN THE CI Pipeline builds an image on main for release,
whether from a merged definition change, the declared schedule or a manual dispatch, THE
CI Pipeline SHALL push ..." Add the `changes`-job change to task 9.2.

### 1.11 **[V]** The verification policy admits the rescan identity for the *signature*, which nothing needs yet and which pre-empts cluster B

**Claim.** Req 2.23 (`requirements.md:69`) admits an image on a signature "whose
certificate identity is exactly this repository's build workflow or rescan workflow".
`rescan.yml:22-25` holds `contents: read`, `packages: read`, `issues: write` and cannot
sign; the review gives it `id-token: write` only in cluster B, for re-*attestation*
(review `:691-693`), and F6's "(build|rescan).yml" phrasing (review `:770`) was about
the identity list as a whole, not about which identity may sign. Admitting the rescan as a
signer widens the trust root today to a workflow that runs `go run` on the in-repo tool
(`rescan.yml:222`), `pip install` (`:167`) and `curl` to two third-party feeds
(`:190-195`), for no current benefit.

**Rewording.** Split the identities by role: "... solely on a cosign keyless signature
whose certificate issuer is https://token.actions.githubusercontent.com and whose
certificate identity is exactly this repository's build workflow at refs/heads/main,
together with an SPDX SBOM attestation and an OpenVEX attestation whose certificate
identity is exactly that build workflow or this repository's rescan workflow at
refs/heads/main." Task 9.6's single "identities" list becomes two lists. Cluster B then
adds nothing to the policy.

### 1.12 **[V]** Terms the criteria lean on are undefined: "catalogue tag", "full release tag", "unsigned control image", and the signature's identity in Req 2.10

- "Catalogue tag" (Req 2.10, 2.11, 2.22, 2.24) is never defined. cosign stores signatures
  and attestations as tags named `sha256-<digest>.sig` / `.att` in the same repository
  **[R]**, so "no catalogue tag references a digest" needs "catalogue tag: a tag derived
  from a definition per Req 2.3" to exclude them, and the enumeration in 1.3 needs the
  same filter.
- "Full release tag" (Req 2.15, 2.16) is the third of each definition's three tags
  (`image/*/image.yaml`, e.g. `13.1.3-alpine3.23`); `docs/CONVENTIONS.md:14-15` calls
  the other two aliases but never names the third. One clause fixes it.
- Req 2.10 counts "a cosign signature" from anyone. Say "a cosign keyless signature from
  an identity criterion 2.23 admits", else a digest signed by an unrelated identity is
  published.
- Req 2.24's "one unsigned control image" must exist permanently under
  `ghcr.io/mm-weber/dhc/*` for the policy's `imageReferences` to match it, which
  contradicts `README.md:28` unless it is named, documented as a control and excluded from
  catalogue tags and from Req 2.21's repository list. Task 9.6 does not say where it comes
  from. The bare amd64 manifests of the legacy indexes (1.2) are the only unsigned digests
  the registry holds today; if 1.2 goes route (b), one of them is the natural control,
  and the spec should name it.
- Req 2.15 and 2.16 are silent when no published digest carries the full release tag
  (first schedule after a failed merge release): neither criterion applies. Add "or when
  no published digest carries that tag" to Req 2.16's trigger. Also say which package set
  is compared (OS packages only, or every SPDX package including Go modules): a Syft bump
  by Renovate (`anchore/sbom-action` is action-pinned) can change the package
  representation and publish every image in one night under the broader reading.

### 1.13 **[V]** Design text asserts as built what this PR only specifies, and two diagrams still draw the old release order

- `design.md:629-633` (Security Considerations): "the substring pattern the README
  carried until cluster A admitted any identity containing the repository path". After
  this merge `README.md:33-34` and `docs/user-manual.md:153-154` still carry it, until
  task 9.6. `design.md:636-637`: "every catalogue repository is checked daily to answer an
  anonymous pull", while nothing checks until 9.4. The flow diagram is correctly labelled
  "as specified 2026-08-21, implementation task 9" (`design.md:173`); these bullets are
  not. The repo's own 2026-08-13 truth pass (`tasks.md:170`) set the precedent that
  design.md states the as-built. Mark the bullets "as specified (tasks 9.4, 9.6)" or move
  them into Decision 6.
- The architecture diagram (`design.md:57`: "main: build, sign, SBOM, provenance, push")
  and the upstream-bump sequence diagram (`design.md:204`: "amd64 build, cosign sign,
  SBOM, compiled-VEX attest, provenance, push"; `:197`: "GHCR (private)") still show push
  last and no scan. Decision 6 and the release flow now contradict them in the same file.
- `docs/user-manual.md:79-81`, `:139-142`, `:146-149`, `:153-154`, `:254`, `:372-378` and
  `README.md:28-29`, `:33-34` all become wrong as tasks 9.1 to 9.6 land. Tasks 9.6 and 9.7
  do account for them (`tasks.md:236`, `:239`), which is correct for a spec-only PR. The
  manual's `:141` still points arm64's return at "spec task 8.3"; 9.7 should name that
  line too.
- (From Angle B, B4.) `design.md:638-641` keeps the pre-existing bullet "the GHCR packages
  anonymously pullable since then (measured 2026-08-19: unauthenticated manifest fetch
  returns 200)" two lines under the new bullet that says "two of six were private on
  2026-08-21". Both cannot be true of the same registry; the 2026-08-19 measurement was of
  one package, not of "the packages". Reword the old bullet to what was measured.
- (From Angle B, B3.) Task 8.3's body survives verbatim: `tasks.md:178` still says the
  legacy tags "are private and pre-release, and are left as they are", which Req 2.22
  and task 9.5 now contradict, and "private" has been false since 2026-08-13. The
  "task 8.3" pointers the absorption should have re-aimed still stand at `tasks.md:51`,
  `design.md:315`, `:515`, `:526` and `:585` (the Data Models comment "release path
  currently ships amd64 (task 8.3)"), while `design.md:157` and `:534` say 8.3 is absorbed
  by 9.3. Five readers of the same file are sent to a task the file declares closed.

### 1.14 **[V]** Req 2.1 and 2.20 coexist without a supersession note, Req 2.2 is left as the ledger found it, and Req 2.20's WHILE is a sequencing constraint rather than a testable state

- Req 2.1 (`requirements.md:47`) still says "for linux/amd64"; Req 2.20 (`:66`) says
  "for every platform their definitions declare". Not a contradiction, since 2.1 does not
  say "only", but the as-built note for Req 2.4 (`design.md:638-639`, "its WHILE clause
  ended") is the house pattern for a superseded criterion and 2.1 gets none. Either amend
  2.1 now ("for every platform its definition declares, see Req 2.20") or add the note.
  (From Angle B, B8.) The ledger named Req 2.1 as F9's spec impact (review `:1053`), and
  the design still states "amd64 only (Req 2.1)" twice (`design.md:313`, `:508`), so the
  criterion is cited both as the amd64 restriction and, by task 9.3 (`tasks.md:225`), as
  authority for the multi-platform build.
- The ledger named Req 2.2 as F3's and F6's spec impact (review `:1047`, `:1050`). Req 2.2
  (`:48`) still reads "WHEN an image build succeeds THE CI Pipeline SHALL push resulting
  images ... with a cosign keyless signature, an SPDX SBOM, and BuildKit provenance
  attached", which under 2.7 to 2.9 is no longer the event that attaches a signature. Not
  wrong, but the PR should say why 2.2 is left (provenance is still attached by the
  build; the signature moved to 2.9) rather than leave the ledger's pointer dangling.
  (From Angle B, B1.) One consequence is substantive: Req 2.2 is the only criterion that
  mentions BuildKit provenance, and neither the definition of "published" (Req 2.10,
  `:56`) nor the verification policy (Req 2.23, `:69`) requires it, while `README.md:28-29`
  and `docs/user-manual.md:146-147` promise it on every image. A digest that lost its
  provenance (the re-pointed tags of 1.2 are the live case) is fully "published" and
  policy-admitted under the PR's text. Either add provenance to 2.10 and 2.23 or state
  in 2.25 that provenance is attached but not verified.
- Req 2.20's WHILE condition ("release-time scans and scheduled rescans cover every
  platform manifest of every published index") is a property of the pipeline's own
  implementation of 2.8 and 2.18, permanently true once they land. A tester cannot
  toggle it. Write it ubiquitous, gated in tasks: "THE CI Pipeline SHALL build affected
  images for every platform their definitions declare", with task 9.3's ordering ("only
  then") carrying the sequencing, which is where it already lives (`tasks.md:225`).

### 1.15 **[V]** Req 2.21 measures a token, the design promises a pull

Req 2.21 (`requirements.md:67`): "returns a pull token to an unauthenticated request";
`design.md:636-637`: "checked daily to answer an anonymous pull". The token endpoint is
the measurement the review made (review `:403-407`) and a fair proxy, but a token can be
issued for a repository whose manifests then 403 **[R]**. Make the criterion and the
design agree, preferably on the stronger form: "... returns a pull token to an
unauthenticated request and serves the manifest of that repository's current release tag
to an unauthenticated request bearing it". Also say in the task that the repository list
comes from `definitions_publishing` (`scripts/definition-lib.sh:36-44`), which task 9.4
implies but does not name, so a new definition joins the invariant on its first release.

(From Angle B, B6.) Req 2.21 is also unconditional while Req 2.4 (`requirements.md:50`,
"WHILE public release remains disabled THE Repository SHALL keep source and registry
images private") still stands and is what a fork in its build phase lives under. With
release disabled, 2.4 requires the repositories to refuse the anonymous token and 2.21
requires the run to fail when they do: the daily run is red by design for as long as the
fork stays private, and no declared switch turns it off. Make 2.21 carry 2.4's state:
"WHILE public release is enabled THE Scan Pipeline SHALL verify at least once per day
...".

### 1.16 Style: seven criteria carry two SHALLs, one of them two actors

Req 2.7, 2.9, 2.12, 2.16, 2.21, 2.22, 2.24 each state two behaviours (the ears-notation
reference lists this under anti-patterns: "Multiple Behaviors"). The repo's existing
criteria do it too (Req 6.13, 6.22, 7.5), so this is house style rather than a defect,
with one exception: Req 2.12 binds two actors (THE VEX Compiler, THE CI Pipeline) in one
sentence, and 1.5 already splits it. The rest can stand.

### 1.17 Task-level inaccuracies to fix before `/spec-implement` reads them

- Task 9.1 (`tasks.md:213`): the push-by-digest recipe "outputs
  `type=image,push-by-digest=true,name-canonical=true,push=true` with no `tags:`" names
  no repository; buildx needs either `name=<repo>` in the output or a bare repository in
  `tags:` **[R]**. Minor, but it is the line an implementer will paste.
- Task 9.6 (`tasks.md:234`): "required predicate types `spdxjson` and `openvex`" are
  cosign's short names; a Kyverno `attestations[].type` needs the predicate-type URIs,
  which the registry shows as `https://spdx.dev/Document` and `https://openvex.dev/ns`
  (no version suffix) **[M]**. Also
  "`kyverno test` fixtures cannot reach a registry" is inexact: the CLI can, with
  `--registry` **[R]**; the real reason the proof lives in the cron is that the digests it
  must admit change daily, which is a better sentence.
- Task 8.3 (`tasks.md:173`) stays open "kept for its measurements" beside 9.3, and both
  sit in the coverage table for Req 2 and Req 6 (`tasks.md:247`, `:251`). Two open tasks
  for one piece of work is what the 2026-08-13 pass corrected elsewhere; mark 8.3 done-by
  -absorption or strike it from the table and keep the measurements in 9.3. (From
  Angle B, B3.) If 8.3 is struck, note that it was the only task annotating Req 6.2 for
  the per-platform rescan (`tasks.md:180`) and 9.3's list (`:226`) does not carry 6.2;
  add it there so the absorption loses no coverage.
- `tasks/todo.md:20-22` changes "one PR per decision" to "one PR per cluster" to match
  review section 6 (review `:1017-1018`). Fine, but the memory rule the owner recorded is
  one decision at a time framed as PRs; the todo should say the review's section 6
  overrode it, so the next reader does not see a silent change.

---

## 2. Faithfulness to the recorded decisions, and scope

**F3 (i), release path (review `:616-627`).** Req 2.7 to 2.13 encode it. One declared
deviation: the `under_investigation` statement carries a timestamp but no issue
reference, so the signing job gains no `issues: write` (`design.md:147-151`,
`tasks.md:214`, PR body). The reasoning is sound for least privilege, and cluster B's
clock defines *first seen* as the earlier of the statement's timestamp and the issue
(review `:722-723`), so nothing measurable is lost. One alternative is not weighed and
should be, since it keeps both properties: a separate job with `issues: write` and no
`id-token`, between the scan and the attestation job, files the issue and passes its URL
as a job output. It costs a job split; the PR should say it was considered, or take it.

**F3 (ii), apk float (review `:629-645`).** Req 1.9 carries two of the contract row's
four clauses (not pinned; recorded in the SBOM); task 9.7 carries all four. Acceptable,
since the other two are Req 2.8 and 2.14, but a reader of Req 1.9 alone does not learn
that the float is *compensated*; "... and that criteria 2.8 and 2.14 are the compensating
controls" would close it in one clause.

**F3 (iii), cadence (review `:647-660`).** Req 2.14 to 2.17 encode it, with "per
platform" added and the review's optional package-diff summary made mandatory for
scheduled publishes (Req 2.16). Both are improvements. The enumeration and ordering
problems are 1.9 and 1.10.

**F9 (review `:749-765`).** (a) encoded as Req 2.22, inheriting the signature-location
gap (1.2). (b) encoded as Req 2.18 to 2.20 and 6.36; "attests VEX per platform digest"
narrowed to identifiers (1.8). (c) encoded as Req 2.21 with the token proxy (1.15).

**F6 (review `:767-783`).** Req 2.23 to 2.25 encode it; the identity list is wider than
the decision needs (1.11). "SECURITY.md states what a signature means" is correctly left
to cluster D; the PR puts the same sentence into design's Security Considerations
(`design.md:629-631`), which is harmless but is D's content.

**Section 6 (review `:1010-1035`).** Numbering continues exactly as instructed (1.9, 2.7,
6.35). Req 6.35 and 6.36 are outside the table's cluster A surface; 6.35 is pulled from
B's F5 (i) sentence because Req 2.12 introduces the status, and 6.36 comes from F9 (b).
Both justified. Req 2.11's "not re-attested" names B's mechanism before B exists; harmless,
it is the review's own phrase (review `:693`).

**Scope.** No criterion touches upstream trust (C) or catalogue posture (D). The one real
pre-emption is 1.11. No over-specification found beyond the "more than one platform
manifest" clause (1.6), which is a restriction rather than an addition.

---

## 3. Checked and found sound

- EARS validity: 98 valid, 0 invalid on the PR branch; all 22 new criteria match a
  pattern; keywords uppercase; no "should/must/will". Negative criterion 6.35 ("SHALL
  NOT") follows the precedent of 6.8, 6.14, 6.16.
- Numbering: 1.9, 2.7 to 2.25, 6.35, 6.36; no collision, no gap; cross-references
  ("criteria 2.7 to 2.9") resolve.
- Actors: every new criterion uses an existing actor (THE Catalogue, THE CI Pipeline,
  THE Scan Gate, THE Scan Pipeline, THE VEX Compiler, THE Repository). None invented.
- Coverage: every new criterion is annotated on exactly one task (2.7 to 2.13, 6.35,
  6.36 on 9.1; 2.14 to 2.17 on 9.2; 2.18 to 2.20 on 9.3; 2.21 on 9.4; 2.22 on 9.5; 2.23
  to 2.25 on 9.6; 1.9 on 9.7), and the coverage table rows for Req 1, 2, 6, 7 list the
  new tasks (`tasks.md:246-252`).
- Req 6.35 is consistent with Req 6.1 as written and with Trivy's OpenVEX handling, which
  filters on `not_affected` and `fixed` only **[R]**; it costs nothing and guards the
  gate against a future scanner that treats the status differently.
- Req 6.29 ("a sha256 digest of an image being scanned") tolerates 6.36's multiple
  products per statement; 6.22's supersession still works because every product carries
  the same digest set.
- Trivy `--platform` with `--image-src remote` is measured, not assumed (`tasks.md:175`),
  and task 9.3 carries the measurement forward. Trivy's RepoDigest for a tag or index
  reference is the index digest: `design.md:385` records that
  `pkg:oci/grafana@sha256:b6987eb…` suppressed on `grafana:13.0.4`, and `b6987eb3…` is
  that tag's *index* digest in the registry **[M]**. So a compiled product stamped with
  the index digest matches on every platform scan, which is what Req 2.8 and 6.36 need;
  products for platform digests (6.36) serve only a consumer who scans a platform
  manifest by its own digest.
- Visibility today: all six repositories answer the anonymous token endpoint with
  HTTP 200 **[M]**, consistent with task 9.4's note that the owner flipped the two
  private ones on 2026-08-21. Req 2.21 is therefore satisfiable on day one.
- Push by digest followed by `imagetools create -t` on the *index* is buildx's documented
  multi-platform pattern, and a single index source is copied byte-for-byte so the tagged
  digest equals the signed one **[R]**. (The same command on a bare manifest is 1.2.)
- Permissions for the release job (`contents: read`, `packages: write`,
  `id-token: write`, `build.yml:113-116`) suffice for push, scan (pull with the same
  token), sign, attest and tag. The rescan's additions (2.21, 2.24) need no new
  permission: both are anonymous reads. Only the sweep's re-signing (1.2 a) would need
  `id-token: write` somewhere other than `build.yml`'s release job.
- Req 2's title change and the unchanged Req 2.4 are consistent with the design's
  existing "WHILE clause ended" note.
- The PR body's claim "Nothing in `.github/`, `scripts/` or `policies/` changes" is true
  (`git diff --stat`).

---

## 4. Tool runs

**EARS validator** (`ears-validator.js` on the PR branch): PASSED, 98 valid statements.
On `main`: 76. Difference 22 = 1 + 19 + 2, as the PR states.

**spec-validate procedure** (followed by hand against the PR worktree):

| Check | Result |
|---|---|
| EARS syntax, every criterion | PASSED (98/0) |
| Requirements structure: numbered titles, "As a ... I want ... so that ..." objectives, criteria under each | PASSED (8 requirements) |
| Task coverage: every requirement referenced by at least one `_Requirements:_` line | PASSED (Req 8.2 noted as convention, pre-existing) |
| Design completeness: Overview with Purpose/Users/Impact, Architecture with a Mermaid diagram, Components and Interfaces, Data Models | PASSED |

The procedure checks syntax and presence; it does not see the contradictions in section 1.

**code-review skill** (`/code-review spec-cluster-a high`): launched twice against the
branch target; both runs were cut short by session usage limits before the skill
consolidated a report. What reached this review is the second run's shared scratchpad:
its finder context, its verifier brief, and the running candidate log of one angle,
"B, removed behaviour", with eight candidates (B1 to B8). The coordinator reports that
the EARS-pitfalls, simplification, line-by-line and altitude angles also completed, but
none of their output is on disk or in this conversation, so nothing from them is folded
in; the remaining angles were terminated. Of Angle B's eight, B2 and B5 duplicate
findings 1.2 and 1.13 (reached independently here first); B1, B3, B4, B6, B7 and B8 add
something and are folded into 1.7, 1.13, 1.14, 1.15 and 1.17 after re-reading every line
they cite (each is marked "from Angle B"). Every other finding is first-hand, with the tree
line, the git history or the registry measurement it rests on.
