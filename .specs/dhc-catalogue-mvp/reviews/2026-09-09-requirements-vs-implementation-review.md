# Requirements versus implementation: full review, 2026-09-09

**Subject:** `main` at `0b31759` (task group 14 complete, PR #183 merged),
every live acceptance criterion of `.specs/dhc-catalogue-mvp/requirements.md`
(147 across groups 1 to 7 and 9; group 8 retired), the ticked tasks and
as-built notes of `tasks.md`, design Decisions 6 to 11 and the System Flows
of `design.md`, and the four documents that describe the catalogue to a
reader (README.md, SECURITY.md, docs/user-manual.md, docs/CONVENTIONS.md),
compared with what the working tree actually does.

**Method.** Criterion by criterion, from the files on disk: the mechanism
that implements each one is named with `file:line`, and the verdict is one
of HELD (implemented and enforced), PARTIAL (implemented with a stated gap),
NOT HELD (no mechanism found) or OWNER-SIDE (live GitHub or registry state
the files cannot show; the daily check that asserts it is named). Where a
lint's negative path mattered, it was probed by running the lint against a
mutated copy under a scratch directory, never against the tree. Nothing was
executed against CI, the registry or the API except the read-only
measurements in "Live state" below. Comments, ticked boxes and design prose
are claims; the code is the evidence. Eight readings were made, one per
requirement group (group 6 in two halves) and one for the layer above the
criteria; every PARTIAL or NOT HELD verdict was re-checked by hand before it
entered this document.

**Line numbers** cite the working tree at `0b31759`. Findings are numbered
group.finding: 2.9 is the ninth finding under Requirement 2; Requirements 3
and 4 share the prefix 3, Requirements 5 and 7 the prefix 5, and
Requirement 6's two halves number 1 to 8 and 9 to 16.

## Live state, measured today

- The first nightly rebuild after the cosign-order fix (#172, merged
  2026-09-08) ran on 2026-09-09 at 09:13 UTC (cron 04:47; the scheduler has
  fired it four to six hours late every day this week). Its comparator
  discarded all seven definitions: the push, sign and tag steps were skipped
  in every job. The week of needless publishing is over.
- The scheduled rescan of 2026-09-09 (11:31 UTC) completed green with no
  failing step, the first green scheduled rescan since the posture step
  landed: private vulnerability reporting is on and the weaker ruleset is
  gone (owner actions of 2026-09-08).
- The catalogue status issue (#151) was rewritten by the 2026-09-08 rescan:
  13 findings, 0 undecided, 0 over ceiling, 13 decided, 0 fixed; a table
  and a fenced JSON block, the same data as the `catalogue-status` artifact.
- Open pull requests: #184 and #185 (the chart-pin bumps that follow the
  builder-digest merge #181, digest-only, automerge candidates) and #89
  (grafana 13.2.1, a reviewed minor).
- README.md carries no badges. No Pages site, no dashboard, no rendered
  chart of the catalogue's state exists anywhere in the repository or its
  workflows; see "Deferred ledger" for how that came to be.

## Verdict

Of 147 live criteria, 114 are HELD, 26 PARTIAL, 3 NOT HELD and 4
OWNER-SIDE. The machinery the catalogue promises exists, is wired into
validate, build and the rescan, and is unit-tested; where a verdict is not
HELD, the gap is almost never a missing mechanism but a mechanism that
stops one step short of the sentence: a check that runs unless an earlier
step failed, a read that is unverified where its sibling is verified, a
result that reads as clean when the tool never ran, a criterion whose text
was written before the code settled its shape.

| Group | Live | HELD | PARTIAL | NOT HELD | OWNER-SIDE |
|---|---|---|---|---|---|
| 1 image definitions | 17 | 14 | 3 | 0 | 0 |
| 2 build and release | 23 | 17 | 5 | 0 | 1 |
| 3 upstream tracking | 11 | 10 | 1 | 0 | 0 |
| 4 chart adaptation | 9 | 6 | 3 | 0 | 0 |
| 5 integration tests | 8 | 8 | 0 | 0 | 0 |
| 6 CVE triage | 51 | 39 | 8 | 3 | 1 |
| 7 conventions | 10 | 8 | 2 | 0 | 0 |
| 9 posture | 18 | 12 | 4 | 0 | 2 |
| total | 147 | 114 | 26 | 3 | 4 |

The three NOT HELD are process criteria of Requirement 6 (6.14, 6.15, 6.22:
reachability forbids a not-in-execute-path claim; a reachability claim
cites a symbol-level result; superseded statements are retained with a
later timestamp) that the maintainer honours in practice and no mechanism
checks; the spec should say which it means. The four OWNER-SIDE are live
GitHub state (2.4 privacy while disabled, 6.44 attestation counts, 9.2
private reporting, 9.4 advisories), three of them asserted daily.

The findings cluster into seven themes, ranked by what they cost:

1. **The rescan's assertions depend on the order of its steps.** Five
   steps that each promise "at least once per day" (the invariants, the
   authenticity re-check, the posture checks, the smoke test, the status
   publication) run only if everything above them succeeded, and one of
   the steps above them fails by design for days at a time (an authenticity
   mismatch, register M18). A KEV outage or one moved upstream tag
   therefore silently suspends the visibility invariant, the admission
   proof, the ruleset comparison, the revoked-tag check and the status
   issue until a human clears it. The run is red, so it is not invisible,
   but the promises are not kept on those days, and the file's own header
   says the opposite. (Findings 2.9, 3.1, 3.9, 9.1.)
2. **Three reads trust what they should verify.** The publish-on-change
   comparator reads the published SBOM through `cosign download` with no
   identity check, while the same document is read verified two scripts
   away; the issue lifecycle closes on the run's raw scan report before the
   run attests it; the status tool is not handed the VEX-failure fence the
   lifecycle tool gets, so an over-reporting digest still feeds the clocks.
   (2.2, 6.11, 6.15.)
3. **Four places where "nothing happened" reads as "all clear".** A
   missing govulncheck prints "no Go binaries"; the fail-closed release gate
   reports a count, never the finding; the two release switches are matched
   as raw strings, so a typo takes the fail-open branch; a declared cron
   absent from its workflow passes with a notice. (6.1, 2.1, 2.10, 2.13,
   5.13.)
4. **The pin surface has holes the conventions say it does not have.**
   cosign has no checksum in the repository and no manager; the 25 Action
   pins are never bumped because the built-in manager is off; the probe
   image is a mutable tag with a comment claiming a digest; the test
   module's Go dependencies are untracked; CONVENTIONS asserts full
   coverage. (5.2 to 5.5, 5.9, 5.12.)
5. **Nine criteria say something other than what the code does, and the
   code is right.** The compiler has a fifth input the closure clause
   forbids; probes are declared per chart, not per definition; the gate
   runs Trivy by name, not "the declared authoritative consumer"; e2e
   installs the published image, not the PR's; the three process
   criteria; the design's two flow diagrams order steps the workflows do
   not. Spec amendments, not code changes. (1.1, 2.11, 2.8, 5.1, 5.6, 6.2,
   6.4, 6.5, 6.9, 6.12.)
6. **Documentation that describes an earlier catalogue.** The manual still
   says releases are amd64 only; three chart READMEs quote versions Renovate
   moved days ago and their reproduce commands render the wrong chart; the
   manual says every overlay hardens the same way and the rescan re-verifies
   every definition; retired criterion numbers survive in error messages,
   step names, task ledgers and the design; two script headers and a test
   comment describe code that no longer exists. Task 14.4's truth pass
   covered the two documents it named and missed the rest. (1.5 to 1.7,
   2.6, 2.7, 3.3 to 3.8, 3.10, 5.8 to 5.11, 6.6, 6.8, 6.14, 9.6.)
7. **Declared values nothing reads, and rules with no negative case.** The
   policy file's support statement; a compat decision required only where
   one already exists; the inactive branch of the build matrix never run
   in CI; a mislabelled test; the backend name unlinted. (6.13, 3.2, 1.8,
   1.6, 1.7, 1.2.)

None of this contradicts the catalogue's published promise. The signature
and attestation chain, the daily enumeration and scans, the VEX compilation
per digest, the exception clocks, the active set and its matrices, and the
governance checks all hold as written. What the review found is the
distance between "the mechanism exists" and "the mechanism cannot be
skipped, fooled or described wrongly", which is the distance the successor
is meant to close from its first commit.

## Requirement 1: image definition catalogue (17 live criteria)

All four validate-side lints pass on the tree today (`lint-pins.sh`,
`lint-active-set.sh`, `render-tracking.sh --check`, `lint-probes.sh`). The
gaps below were confirmed by running the lints against mutated copies.

| Criterion | Verdict | Mechanism (file:line) | Note |
|---|---|---|---|
| 1.1 self-contained subtrees, reference set | HELD | `image/{hardened-app, cert-manager-controller, cert-manager-webhook, cert-manager-cainjector, grafana, valkey, valkey-compat}/image.yaml`; `.github/workflows/build.yml:393-394` (`context: image/<name>`) | Seven directories match the named set; the BuildKit context confines each build to its own directory |
| 1.2 base images digest-pinned | HELD | `scripts/lint-pins.sh:25` (`DIGEST_RE`), `:66-69`, `:78-92`; `validate.yml:42-43` | Placeholder and truncated digests covered by `scripts/lint-pins_test.sh:532-543` |
| 1.3 source pinned by exact version plus checksum | PARTIAL | git half `scripts/lint-pins.sh:117-123`; tarball half `image/grafana/image.yaml:33,59,72-76` plus `scripts/verify-arch-pins.sh:53-61,102-121` (runs only in `build.yml:258-261`); daily `scripts/check-authenticity.sh:66-75,91` | Finding 1.2: the PR-time check is a line count; ref shape, checksum shape and tarball checksum presence are unchecked before merge |
| 1.4 non-root account UID 65532 | PARTIAL | On disk only: `image/*/image.yaml` `accounts: run-as: nonroot`, `uid: 65532` (7 of 7, e.g. `image/hardened-app/image.yaml:79-84`) | Finding 1.1: no lint, workflow step or test reads a definition's `accounts:` block |
| 1.6 floating tag fails naming it | HELD | `scripts/lint-pins.sh:66-69`, `:54-58`; `lint-pins_test.sh:53,60,70` | Scoped to `image:`, `base:`, `uses:` and `# syntax=`, the only image-bearing keys |
| 1.7 native syntax of the installed backend | PARTIAL | `image/*/image.yaml:1` (`# syntax=dhi.io/build:...`, 7 of 7); `docs/concepts.md` names backend and alternative; the compile in `build.yml:391-394` | Finding 1.3: the frontend name is not held to `dhi.io/build`, only its digest form is linted |
| 1.9 CONVENTIONS records unpinned packages and the SBOM record | HELD | `docs/CONVENTIONS.md:104-116` | Finding 1.4 flags one overstatement in that block |
| 1.10 authenticity class declared | HELD | `scripts/definition-lib.sh` (`authenticity_class`), `scripts/lint-pins.sh:131-154`; markers in every definition | 7 of 7 declare a class fitting the archetype |
| 1.11 none or no class fails naming it | HELD | `scripts/lint-pins.sh:145-150`; `lint-pins_test.sh:575-580` | Unknown classes also refused |
| 1.12 dhi.io repository shape | HELD | `scripts/lint-pins.sh:156-173`; `lint-pins_test.sh:593-604` | Only `repositories:` entries are judged; test label mismatch, finding 1.6 |
| 1.13 active set declared | HELD | `catalogue-policy.yaml:47-54` | Comment block documents the semantics |
| 1.14 active set the sole matrix and tracking source | HELD | build `build.yml:73-74,83,89,148-152`; e2e `e2e.yml:58` via `definition-lib.sh` `active_components`; tracking `scripts/render-tracking.sh` into `renovate.json5:35-37`, drift-checked `validate.yml:97-98`, Renovate's own filter measured in `test/renovate/managers.test.mjs:746-750`; daily re-check `check-authenticity.sh:42,62`; probe lint `scripts/lint-probes.sh:32` | A malformed set is a refusal, not an empty matrix |
| 1.15 inactive: no new digest, no new tag | HELD (preventive only) | `build.yml:76-83` (dispatch refused), `:144-152` (one filter point) | Finding 1.8: no detective check, and with seven of seven active the branch has never run in CI |
| 1.16 PR bumping an inactive definition or orphan chart fails | HELD | `validate.yml:80-92`, `scripts/lint-active-set.sh:114-133`; `lint-active-set_test.sh:79-94` | Broader than the text: any changed path under the directory; the manual says so |
| 1.17 builder contract documented | HELD | `docs/concepts.md` "The builder contract per archetype", linked from the trust-boundary table | Documentation criterion |
| 1.18 split group fails naming it | HELD | `scripts/lint-active-set.sh:67-90` (published repository and source repository keys); `lint-active-set_test.sh:56-64` | Real groups today: the valkey pair, the cert-manager trio |
| 1.19 entry without a directory fails naming it | HELD | `scripts/definition-lib.sh` (`active_definitions` refusal), surfaced by `lint-active-set.sh:50-55`; test `:66-69` | Duplicates and empty lists refused too |

### Findings, group 1

1. **Req 1.4 is unenforced.** Nothing under `scripts/`, `.github/workflows/`,
   `policies/` or `test/` reads a definition's `accounts:` block or the
   built image's user. Probed: `run-as: root`, `uid: 1000` and a deleted
   `accounts:` block all pass `lint-pins.sh`. The only UID 65532 assertion,
   `test/checks/securitycontext.go:56`, reads the pod's declared
   securityContext, which the charts set themselves, so it passes over an
   image with no nonroot account. `docs/CONVENTIONS.md:131-132` ("Rules, all
   enforced by `scripts/lint-pins.sh`") lists the accounts rule at `:160`
   among the enforced ones; that is not true, nor for `:149-157` (tarball
   pin) and `:161` ("Alpine variants only": `lint-pins.sh:161` accepts
   `dhi.io/deb/<distro>/main` by design).
2. **Req 1.3 is a line count at PR time.** `lint-pins.sh:117-123` requires
   only `count(url: git+) <= count(checksum:)` per file. Probed: `#main` as
   the ref, a git URL with no `#ref`, and a 7-hex `checksum:` all pass. The
   tarball half has no PR-time presence check: grafana with `GRAFANA_SHA256`
   and the `sha256sum -c` step removed passes, and `verify-arch-pins.sh:58-61`
   exits 0 with "nothing to verify" (it runs only in the build matrix). The
   exact-version and checksum properties are enforced post-merge and daily
   by `check-authenticity.sh:66-75,91`, for active definitions. Doc
   contradiction: `CONVENTIONS.md:50` says every upstream source is
   `git+https://...#<ref>` plus a `checksum:` line; `image/grafana/image.yaml:59-61`
   has none, as `CONVENTIONS.md:149-157` itself explains.
3. **Req 1.7's backend identity is not linted** (minor). `lint-pins.sh:78-92`
   checks line 1 is a digest-pinned `# syntax=`, not that it names
   `dhi.io/build`; `# syntax=docker/dockerfile:1@sha256:<digest>` passes and
   `build.yml:391-394` would compile with it.
4. **Doc overstatement on pull checksums.** `CONVENTIONS.md:112-114` says the
   resolved set "with apk pull checksums, is in the SPDX and CycloneDX
   SBOMs"; `build.yml:1025-1028` and `docs/concepts.md` say Syft's SPDX
   output drops them. Req 1.9's own text holds; the sentence overstates the
   SPDX side.
5. **Retired numbers cited as live.** `validate.yml:42` step name "(Req 1.5,
   1.6, 7.4)"; `design.md:82`, `:93` ("Req 1.7/1.8"), `:99` ("Req 1.5");
   `docs/concepts.md:16-17` ("Req 1.7/1.8's WHERE/IF pair"). Task 14.4
   re-anchored the manual and CONVENTIONS, not these.
6. **Mislabelled test.** `lint-pins_test.sh:602-604` is named "a
   non-repository dhi.io url outside repositories: is not judged", but its
   `sed` rewrites the second `repositories:` entry and expects a Req 1.12
   failure. It tests the opposite property; the keyring-is-not-judged
   behaviour of `lint-pins.sh:165-173` has no test.
7. **Stale script header.** `scripts/verify-arch-pins.sh:8-19` says "nothing
   builds arm64 any more" and "the release path just publishes one of
   them"; `build.yml:404` builds every declared platform on main and the
   policy admits arm64 (task 9.3).
8. **Req 1.15 has no detective control.** The single filter is inline
   workflow shell with no unit test, and nothing daily asserts "no new
   digest for an inactive definition" (`enumerate-catalogue.sh:57` walks
   every definition regardless of the set). The branch was rehearsed
   locally in task 14.2, never in CI.
9. **Req 1.10 reads only the first marker** (`definition-lib.sh` `grep -m1`);
   a definition with two sources, none today, would have only its first
   `# authenticity:` judged.

## Requirement 2: image build and release (23 live criteria)

| Criterion | Verdict | Mechanism (file:line) | Note |
|---|---|---|---|
| 2.1 build every declared platform of each affected active definition | HELD | `build.yml:140-152` (affected set, active filter), `:226-244` (declared platforms must be admitted), `:404` | |
| 2.2 push to the declared namespace with provenance; sign and attest | HELD | `build.yml:218-221` (refuses an image outside `verification.registry`), `:415` (push), `:421` (`provenance: mode=max` on main), `:1010-1047` | |
| 2.3 tags from upstream semver, DHI naming | HELD | `build.yml:245-249`; `lint-pins.sh:243-251`; `refresh-definition.sh:10` | Order and count (third tag = full release tag) unlinted, finding 2.12 |
| 2.4 keep private while public release is disabled | OWNER-SIDE | No mechanism: `build.yml:13-14` records the guard's removal; `check-visibility.sh:54-57` exits 0 when `public: false` | Vacuous today (`public: true`); finding 2.11 |
| 2.5 failed build publishes nothing, reports each failing step | HELD | release steps under `set -euo pipefail`, no `continue-on-error`; `fail-fast: false` `:169`; gate job `:1083-1099` | On main the digest is pushed at `:415` before the scan and stays untagged (frozen, 2.11) |
| 2.7 push by digest only, no tag before the scan | HELD | `:410` `push: false`, `:414-415` (`push-by-digest=true`), tags at `:1054-1077` after scan `:916` and sign `:1010` | `:1066-1076` re-reads each tag and fails if it resolves elsewhere |
| 2.8 scan the pushed digest per platform manifest with the gate's VEX and exceptions | HELD | `:886-909` (platform manifests, `unknown` and reference-type excluded), `:916-942`; `scripts/scan-image.sh:50,54,71-76`; the PR gate uses the same script `:532` | |
| 2.9 sign index and manifests; SPDX, CycloneDX, vuln per manifest; one OpenVEX on both; tags last | HELD | `:1023` (`cosign sign --recursive`), `:963-976`, `:1031-1035`, `:1043`, `:1047`, `:1054-1077` | Per-manifest signature coverage rests on `--recursive`; nothing reads a platform-manifest signature daily unless Kyverno rejects |
| 2.10 tag-referenced plus signature, SPDX, OpenVEX, provenance = published | PARTIAL | `scripts/verify-catalogue.sh:76-79,109` applies the policy (signature, SPDX, OpenVEX) daily | Finding 2.4: the provenance leg is never asserted |
| 2.11 untagged digest is frozen | HELD | `enumerate-catalogue.sh:74-81`; the rescan and `reattest.sh:5` read only the enumeration | Frozen by construction |
| 2.12 fail-closed off and uncovered: under_investigation with the report's timestamp | HELD | `compile-vex.sh:347-397`, `build.yml:982-998`; `compile-vex_test.sh:332-342` | |
| 2.13 fail-closed on: sign nothing, tag nothing, report the finding | PARTIAL | `build.yml:949-957` runs before vuln attest, compile, sign, tags | Finding 2.1: reports a count, never the finding; the branch has never run |
| 2.14 daily rebuild of the active set | HELD | `build.yml:31-32` cron, `:84-89`; `catalogue-policy.yaml:22`; `lint-workflow-policy.sh:57-58` | Nothing asserts the schedule fired; finding 2.13 |
| 2.15 on-change: discard an equal package set | PARTIAL | `build.yml:312-329`, `:331-382`; `package-set-diff.sh:74-80,129-155` | Finding 2.2: the published side is read unverified |
| 2.16 different or untagged: publish and report the diff | PARTIAL | `build.yml:376-382`, `:369-373`; `package-set-diff.sh:151-153,107-108` | Finding 2.3: the compared build and the pushed build are two builds |
| 2.17 always: publish regardless | HELD | `build.yml:377` | An unrecognised `publish_policy` behaves as `always`; finding 2.10 |
| 2.20 count only identities 2.23 admits | HELD | `policies/verify-catalogue-images.yaml:31-57`; `verify-catalogue.sh:109`; `reattest.sh:57-60`, `fetch-sboms.sh:51` | `check-attestation-count.sh` counts identity-blind, by design (Req 6.44) |
| 2.21 daily anonymous pull token per repository, manifest per tag | HELD | `check-visibility.sh:54-57,76-86,93-106,108-111`; `rescan.yml:307-310` | Registry state is owner-side (register M15) |
| 2.22 daily enumeration; every platform manifest scanned; 2.21 and 2.24 applied | PARTIAL | `enumerate-catalogue.sh:74-107`; `rescan.yml:86-90,124-158`; `:310,316` | Finding 2.5: a failed manifest scan is a warning |
| 2.23 verification policy under policies/ | HELD | `policies/verify-catalogue-images.yaml` rendered by `render-verification.sh`; drift `validate.yml:69` | |
| 2.24 daily proof: admit every tag-referenced digest, reject the control | HELD | `verify-catalogue.sh:76-111,197-215,225-227`; `rescan.yml:316` | Policy applied to the index digest; platform manifests only on rejection |
| 2.25 consumer instructions with issuer and exact identities; provenance not verified | HELD | `render-verification.sh:131-184` into README.md and the manual; recipe run daily `rescan.yml:431-446` | |
| 2.26 no report or unscanned manifest: sign nothing, tag nothing, report | HELD | `scan-image.sh:78-85`, `build.yml:903,926` | |

### Findings, group 2

1. **Req 2.13 reports a count, not the finding; the design promises a name.**
   `build.yml:956` says "N uncovered finding(s) in the release-time scan of
   <digest>"; `:940` logs counts per manifest; the report upload at
   `:864-872` is pull-request only. `design.md:1177` says "red run naming
   the finding". The PR gate names findings (#123); the release gate does
   not. The branch has never run (switch off, no workflow-level test).
2. **Req 2.15: the comparator reads the published SBOM unverified.**
   `package-set-diff.sh:133` uses `cosign download attestation` and takes
   the first CycloneDX layer; no certificate identity is checked, and
   "published" (2.10) is not checked, only that the full release tag
   resolves (`:107`). The verified read of the same document already exists
   in `scripts/fetch-sboms.sh:51`. A CycloneDX attestation from any identity
   can make the nightly discard a rebuild.
3. **Req 2.16: two builds.** The comparator reads the local OCI export
   (`build.yml:312-329`); a `different` verdict runs a second
   `build-push-action` (`:384-421`) whose equality with the first is assumed
   ("a replay on the gha cache"). Nothing asserts the pushed digest's package
   set equals the compared one, so the summary's diff describes the local
   build, not necessarily the digest that got the tag.
4. **Req 2.10: the provenance leg is never asserted.** The daily proof checks
   signature, SPDX and OpenVEX; provenance is attached at `build.yml:421` and
   only mentioned as unverified in the recipe. The smoke test's provenance
   step (`consumer-smoke.sh:96-101`) passes on exit 0, which
   `imagetools inspect --format '{{ json .Provenance }}'` returns for `null`.
5. **Req 2.22: per-manifest scan failures soft-fail.** `rescan.yml:150-156`
   turns a failed scan into `::warning` plus a count and the run stays
   green; `reattest.sh:21-23` then skips that digest whole. The SHALL is
   unconditional; the design's failure table licenses a soft-fail only for a
   Trivy database outage.
6. **The manual still says releases are amd64 only.** `docs/user-manual.md:151-155`:
   "releases are currently linux/amd64 only (Req 2.1). arm64 was deliberately
   withdrawn on 2026-08-04 ... returns only once the rescan covers it (spec
   task 8.3)". The policy admits arm64, every definition declares it,
   `build.yml:404` builds all declared platforms, and the manual contradicts
   itself at `:88` and `:159`. Task 14.4's truth pass re-anchored the
   citation in that paragraph and missed the paragraph.
7. **Retired citations in the spec.** `tasks.md:50-51` (task 3.3) in the
   present tense: "is now amd64 only ... (Req 2.6)"; `design.md:168`
   ("Req 2.18 to 2.20"), `:172` ("Req 2.18, 2.22 ... satisfying Req 2.6").
8. **The design's release-flow diagram orders the vuln attestation before
   the fail-closed gate** (`design.md:707-710`); the code gates first
   (`build.yml:949`) and attests after (`:963`), the 2.13-compliant order.
9. **The daily invariants depend on unrelated earlier steps.** `rescan.yml:307-336`
   (2.21, 2.24, 6.44) runs after the issue-lifecycle steps and re-attestation,
   none with `if: always()`. A `gh` outage or a Rekor failure after three
   attempts skips that day's visibility and admission proof; the run is red,
   so it is not silent, but the invariants were not verified that day.
10. **The two release switches are read without validation.** `build.yml:209-210`
    reads `fail_closed` and `publish_policy` as raw strings; `:950` matches
    `'true'` and `:377` matches `on-change`. `yes`, `True`, `on_change` or a
    typo takes the fail-open branch. No script schema-checks the `release:`
    section.
11. **Req 2.4 has no mechanism.** The restored criterion's active branch
    (keep private while disabled) is implemented by absence; nothing asserts
    privacy when `public` is false.
12. **The "third tag is the full release tag" convention is unlinted**
    (`build.yml:352` `tail -n 1`, `rescan.yml:436`); all seven comply today.
13. **`lint-workflow-policy.sh` is one-directional for crons** (`:61-62`): a
    declared schedule absent from the workflow passes with a notice, so
    deleting `build.yml:31-32` would not go red and Req 2.14 would silently
    stop.

## Requirements 3 and 4: upstream tracking, chart adaptation (11 and 9 criteria)

| Criterion | Verdict | Mechanism (file:line) | Note |
|---|---|---|---|
| 3.1 Renovate self-hosted, at most six hours apart | HELD | `renovate.yml:17` (`0 */4 * * *`), held equal to `catalogue-policy.yaml:173` by `lint-workflow-policy.sh` | Owner-side: the token secret and GitHub's scheduler; no check asserts a run occurred |
| 3.2 a PR updates ref, checksum and derived tags for an active definition | HELD | `renovate.json5:357-362,374-379`; `refresh-definition.sh:99-117`; `refresh-grafana.sh:220-269`; scope via `renovate.json5:36` rendered by `render-tracking.sh` | The alias-tag rewrites preserve the `-compat` suffix |
| 3.3 monorepo grouping | HELD | `renovate.json5:270-271,283-284,291-296` | Config only; no fixture asserts `groupName` |
| 3.4 majors staged | HELD | `renovate.json5:301-302` | Unscoped, reaches every datasource; no fixture |
| 3.5 automerge scope | HELD | `renovate.json5:347-349`; `managers.test.mjs:319-333` | "Green required checks" is `.github/rulesets/main_sec.json`, compared daily |
| 3.7 minimum release age | HELD | `renovate.json5:332-334`; `managers.test.mjs:290-313` (loads the pinned Renovate and asserts timestamp support per datasource) | docker exempt, matching the criterion |
| 3.8 refresh verifies the signal and refuses | HELD | `refresh-definition.sh:73-94`; `refresh-grafana.sh:207-216` | Both refuse before the first write and name the class |
| 3.9 per-arch checksum cross-check at PR time | HELD | `verify-arch-pins.sh:113-121`; `build.yml:261` | Names pinned, served and stated values |
| 3.10 daily re-verification of active definitions | PARTIAL | `check-authenticity.sh:59-112`, active filter `:42,62`; `rescan.yml:344-373` | Ordering exposure, finding 3.1 |
| 3.11 chart versions tracked, never automerged | HELD | `renovate.json5:257-263,390-391`; `managers.test.mjs:333,348-350` | |
| 3.12 chart digest pins automerge | HELD | `renovate.json5:401-404`; ordering asserted `managers.test.mjs:327-328` | |
| 4.1 upstream chart at its pinned version, unmodified | HELD | `chart/*/chart.yaml` `upstream:`; `render-chart.sh:17-23`; `test/install/install.go:86-93` | No adapted chart carries templates; the render path is the enforcement; READMEs quote stale versions, finding 3.3 |
| 4.2 digest-pinned images from the declared namespace | HELD | `policies/require-image-digest.yaml:39`, `policies/restrict-registries.yaml:28-33`; `chart.yml:48-52` | The rendered-manifest gate is the only enforcement for split repository/tag/digest keys (`lint-pins.sh:10-12` skips them by design) |
| 4.3 restricted pod security | HELD | values in all four charts; live `test/checks/securitycontext.go:53-73` via `assert_test.go:31-38` | Kyverno covers pod-level `runAsNonRoot` only; the rest is asserted when e2e runs for that component |
| 4.4 emptyDir at writable paths | HELD | `chart/grafana/config/values-hardened.yaml:45-53`; `chart/valkey/config/values-hardened.yaml:63-64` with the inventory in its README | No lint reads the inventory; the live probe under a read-only rootfs is the enforcement |
| 4.5 compat decision recorded | PARTIAL | `chart/valkey/chart.yaml:35-46`; schema `chart/chart.schema.yaml:29-34`; `chart/valkey/README.md:67-122` | Nothing binds the trigger to the record, finding 3.2 |
| 4.6 policy gate on rendered manifests | HELD | `chart.yml:41-58`; self-test `policies/tests/` at `validate.yml:48-51` | |
| 4.7 deviations documented per chart | PARTIAL | the four chart READMEs | Every override has a row; three literals drifted, finding 3.3 |
| 4.8 lapsed review-by fails validation | HELD | `lint-compat.sh:66-69`; `validate.yml:33` | A moved `review_by` alone satisfies it; "dated re-decision" is unenforced |
| 4.9 lapsed review-by reported daily | PARTIAL | `check-authenticity.sh:114-132`; `rescan.yml:354,675` | Same ordering exposure as 3.10 |

### Findings, groups 3 and 4

1. **Req 3.10 and 4.9 depend on every earlier step of one job.** The
   authenticity step sits at `rescan.yml:344`; the invariants step above
   it exits 1 on a KEV feed outage (`:322-325`), and the scan, visibility
   and admission steps can fail hard. On such a day the run is red, but no
   signal is re-verified and no lapsed date reported, which is what "at
   least once per day" asks for. The revocation check two lines earlier is
   written the other way (`:336`, verdict deferred to the posture step), so
   the decoupling pattern exists in the same file. Same class as findings
   2.9 and 9.1.
2. **Req 4.5 is enforced only for the decision that already exists.**
   `lint-compat.sh:44-46` skips a chart.yaml without a `compat:` block and
   the schema marks it optional. Nothing correlates "this chart's `deploys:`
   names a `-compat` definition" (the data is in `definition-lib.sh`) with
   "a `compat:` block exists". A second compat variant added without a
   recorded decision passes validate green.
3. **Three chart READMEs quote versions Renovate has since moved, and
   nothing holds them.** `chart/cert-manager/README.md:3,12` say v1.21.0
   (pin: v1.21.1, #167); `chart/valkey/README.md:3,12` say 0.11.0 (pin:
   0.12.0, #168); `chart/grafana/README.md:35` names the image pin
   13.1.3 (values: 13.1.5). The reproduce comments in
   `chart/cert-manager/chart.yaml:31` and `chart/valkey/chart.yaml:50` carry
   the same stale values, and `chart/valkey/chart.yaml:6` says "chart
   appVersion 9.1.1" while its README says 0.12.0 ships 9.1.2. Renovate
   edits the pins, not the prose, and no lint reads the READMEs, so the
   drift is structural: following the valkey README's own command renders
   0.11.0 while CI renders 0.12.0, which also makes Req 4.1's reproduce
   path wrong.
4. **`docs/user-manual.md:597` says the rescan "re-verifies every
   definition"**; the code re-verifies active ones (`check-authenticity.sh:62`),
   the pre-14.2 sentence.
5. **`rescan.yml:15-16` claims "scan/feed failures soft-fail (skip + warn)"**,
   which the same file contradicts at `:322-325` where a KEV outage is an
   explicit `exit 1`. The header comment misdescribes finding 3.1's
   mechanism.
6. **Req 3.6 is cited as live** in `renovate.yml:5-6`, `design.md:121` (a
   numbered decision) and `tasks.md:43,66,71,74`.
7. **`design.md:116-118` says automerge is "broader than Req 3.5's minimum"**;
   after the cluster C amendment 3.5 states exactly what
   `renovate.json5:347-349` implements.
8. **`docs/user-manual.md:242-246` says every overlay does the same three
   things**, including the full restricted profile and emptyDir mounts;
   `chart/cert-manager/config/values-hardened.yaml` does neither (UID, GID,
   fsGroup and the startup API check only), as its README says. The
   per-chart README is right; the manual over-generalises.
9. **An authenticity mismatch fails the rescan mid-job and skips the day's
   status.** `rescan.yml:373` ends the step with `exit "$rc"`; the three
   catalogue-status steps and the status upload (`:572-629`) carry no `if:`,
   so a supply-chain signal day publishes no status. The principle stated
   for revocations at `:331-336` ("after the day's issues and status are
   published, not instead of them") is not applied here.
10. **`docs/CONVENTIONS.md:234`** shows the tarball source shape as the
    legacy `…-X.Y.Z.linux-…` alias filename, the one shape the manager
    deliberately no longer accepts (`renovate.json5:89-93`).

## Requirements 5 and 7: integration tests, conventions and review (8 and 10 criteria)

| Criterion | Verdict | Mechanism (file:line) | Note |
|---|---|---|---|
| 5.1 Ginkgo v2, Gomega, e2e-framework, kind | HELD | `test/go.mod:7-12`; kind provider `test/e2e/e2e_suite_test.go:16,78-88` | Compiled and vetted on every PR (`validate.yml:241-275`) |
| 5.2 affected charts deploying an active definition install on kind | HELD | `e2e.yml:36-107`; `definition-lib.sh` `active_components` | The installed image is the published one, never the PR's build; finding 5.1 |
| 5.3 Ready within five minutes | HELD | `test/checks/wait.go:16` (`ReadyTimeout = 5 * time.Minute`); `assert_test.go:26,29` | Applied to the rollout wait and the pod-Ready wait |
| 5.4 live securityContext, UID 65532, read-only rootfs | HELD | `test/checks/securitycontext.go:17,56,62`; `assert_test.go:32-38` | Also GID, runAsNonRoot, drop ALL, seccomp; init containers included |
| 5.5 declared probe, shared once | HELD | registry `test/e2e/probes_test.go:37-42`, resolution `:47-65`, executed once per install `assert_test.go:45-48` | Declared by the chart, not the definition as the text says; finding 5.6 |
| 5.6 upgrade path on a bump | HELD | `e2e.yml:181-209`; `test/e2e/upgrade_test.go:43-53`; rollout gate `test/checks/rollout.go` | A definition-only bump PR does not trigger it; the follow-on chart-pin PR does (design.md:766-768) |
| 5.7 diagnostics preserved | HELD | `e2e_suite_test.go:103-114`, `test/checks/diagnostics.go:31-56`; workflow dump `e2e.yml:223-246` | |
| 5.8 validate fails an active definition without a probe | HELD | `scripts/lint-probes.sh:62-74`; `validate.yml:104` | Run on the tree: seven covered by four registrations |
| 7.1 CONVENTIONS defines naming, pinning, variant, override rules | HELD | `docs/CONVENTIONS.md:7,47,16-32,306` | |
| 7.2 yamllint on changed YAML; schema and pinning of changed definitions | HELD | `validate.yml:22-24` (`yamllint .`), `:43` (`lint-pins.sh`); schema is the frontend compile in `build.yml` | Whole tree, a superset; `.yamllint.yaml:17-21` ignores `data/`, `temp/`, `chart/*/templates/`; no in-repo schema for definitions, finding 5.7 |
| 7.3 PR template prompts for requirement references | HELD | `.github/PULL_REQUEST_TEMPLATE.md:9-20` | |
| 7.4 fail with a message identifying the convention | HELD | `lint-pins.sh:58,74,85` name `docs/CONVENTIONS.md`; sibling lints name their criterion instead | |
| 7.5 every third-party executable exact-pinned with a checksum in the repository | PARTIAL | `install-tool.sh:57-82,203-207` (seven tools), `install-scanners.sh:56-61,119-125`, `.github/requirements-ci.txt` with hashes, `registry:2@sha256` (`build.yml:453`) | Gaps: cosign (version only, no checksum in the repository), `curlimages/curl:8.11.1` (tag only), Actions pins unlinted; findings 5.2 to 5.5 |
| 7.6 Renovate tracks each pinned executable | PARTIAL | `renovate.json5:128-152,165-172,221-233,188-211,257-262` | Untracked: the 25 Action SHAs (the `github-actions` manager is disabled), cosign, `registry:2`, the probe image; findings 5.2 to 5.4 |
| 7.7 one committed policy file with every named value | HELD | `catalogue-policy.yaml:12,15,18,22,27-29,47-54,56-87,154-188` | All seven items present |
| 7.8 CI renders the policy and the consumer instructions | HELD | `render-verification.sh:186-260`; `validate.yml:69` | CI runs `--check`; the render is developer-invoked |
| 7.9 fail naming a drifted rendered artifact | HELD | `render-verification.sh:190-194`, `render-tracking.sh:82`; `validate.yml:69,98` | Both run clean on the tree |
| 7.10 fail on schedule or permissions differing from the policy file | HELD | `lint-workflow-policy.sh:52-86`; `validate.yml:72` | Globs `*.yml` only; finding 5.13 |

### Findings, groups 5 and 7

1. **The e2e suite never tests the image a pull request proposes.** The
   charts pin published digests (`chart/grafana/config/values-hardened.yaml:14`),
   `e2e.yml:139-151` makes pods pull from the registry by design (a loaded
   image cannot match an index digest), and the PR build does not push
   (`build.yml:323`). A PR changing a definition therefore installs and
   probes the previously published image; the new one is exercised after
   merge, through the follow-on chart-pin PR (design.md:766-768 says so).
   Req 5.2's "deploying an active definition's images" reads stronger than
   what runs. Not a defect in the code; a gap between the sentence and the
   mechanism worth stating in the spec.
2. **cosign is neither checksum-verified in the repository nor tracked.**
   `build.yml:289-299` and `rescan.yml:66-68` install it through
   `sigstore/cosign-installer` at an exact version with no recorded checksum;
   the `# renovate:` marker at `build.yml:298` cannot match the workflow
   manager's regex (`renovate.json5:170` requires `\w+_VERSION:`) and
   `rescan.yml:68` has no marker. Register row P1 records the tracking half;
   the checksum half is not recorded anywhere.
3. **The fixture suite locks the cosign gap in.** `test/renovate/managers.test.mjs:489`
   asserts that build.yml yields exactly one workflow-pin dependency, which
   holds only because the cosign marker is unmatched. No check requires every
   `# renovate:` marker in the repository to resolve to a manager, the class
   of miss Req 7.6 exists to prevent.
4. **GitHub Actions pins are unlinted and untracked.** All 25 `uses:` lines
   carry full commit SHAs, but `lint-pins.sh:27-29` scans only `image/` and
   `chart/`, so a tag-pinned action would pass, and `renovate.json5:9`
   enables only the regex managers, so a pinned action never receives a
   bump PR. The same holds for `registry:2@sha256` (`build.yml:453`) and the
   probe image.
5. **The probe image is tag-pinned, and its comment says otherwise.**
   `e2e.yml:110` sets `curlimages/curl:8.11.1`, pulled and loaded into kind
   (`:171-172`), a mutable tag with no digest, the re-publication shape
   `install-scanners.sh:14-19` cites CVE-2026-33634 for. `test/e2e/probes_test.go:70-73`
   claims the workflow sets "a digest-pinned reference". The comment is
   wrong.
6. **Spec text and mechanism disagree on who declares a probe.**
   `requirements.md:133,137` say "declared by an active definition"; the
   mechanism declares it on the chart (`chart/chart.schema.yaml`, resolved
   at `probes_test.go:47-65`), one probe per chart. Two definitions on one
   chart needing different probes is unrepresentable. Task 14.3's as-built
   note records the shape; the criterion text was never amended.
7. **Req 7.2 runs wider and elsewhere than the sentence says.** yamllint
   covers the whole tree, a superset, but skips `data/`, `temp/` and
   `chart/*/templates/`; definition schema conformance is the `dhi.io/build`
   compile in build.yml (no in-repo schema exists), as CONVENTIONS documents.
8. **Ledger contradiction on cosign.** `tasks.md:215` (task 9.1): "`cosign-release`
   pinned to an exact v2 version in build.yml with a Renovate manager over
   the pin (Req 7.5, 7.6)". `build.yml:295-297` says the opposite and the
   regex confirms build.yml.
9. **CONVENTIONS overstates 7.5 and 7.6 coverage.** `docs/CONVENTIONS.md:76-87`
   asserts every executable a workflow installs is pinned and verified
   against a checksum recorded in the repository and that every pin carries
   a manager; cosign and the probe image satisfy neither, and `vexctl`,
   installed by `install-tool.sh`, is missing from the enumeration.
10. **design.md's installer signature is stale.** `design.md:1120` writes
    `install-tool.sh <kind|kyverno|helm|ct>`; the script handles seven tools
    (`install-tool.sh:57-82,175`).
11. **Req 8.1 is cited as live** in `e2e.yml:3,14`, `build.yml:17`,
    `rescan.yml:13`, `tasks.md:52,102` and `docs/decisions/0002-grafana-upstream-tracking.md:118`.
    Task 14.4's re-anchoring covered CONVENTIONS and the manual only.
12. **The test module's Go dependencies are untracked.** `renovate.json5:8`
    still says "when phase 6 adds test/ as a Go module, enable gomod";
    `test/go.mod` exists and gomod is off, so the Kubernetes client
    libraries and the e2e framework never receive bump PRs. Outside 7.6's
    literal scope (not executables), the same silent-staleness the section
    argues against.
13. **`lint-workflow-policy.sh` globs `.yml` only** (`:36`); a workflow added
    as `.yaml` would carry an undeclared schedule and permissions and pass.
    Renovate's own pattern allows both spellings.

## Requirement 6, first half: criteria 6.1 to 6.30 (24 live criteria)

| Criterion | Verdict | Mechanism (file:line) | Note |
|---|---|---|---|
| 6.1 scan with the declared authoritative consumer; fail on every uncovered finding | PARTIAL | `build.yml:540,849-860`; `scan-image.sh:67` (aperture from the policy), `:71` | The scanner is a literal `trivy image`; the declared consumer is not consumed, finding 6.4 |
| 6.3 issue per new finding with severity, EPSS, KEV, affected images | HELD | `triage/rescan/report.go:266-269`; `rescan.yml:541-562` | Supported set only (`rescan.yml:143-144,162-168`) |
| 6.4 not_affected as OpenVEX under triage/, attached | HELD | `triage/vex/*.json`; `build.yml:1035,1047`; `reattest.sh:16-19` | Shape enforced by `lint-vex-product.sh` |
| 6.5 fix as a bump or rebuild PR | PARTIAL | `image/cert-manager-controller/image.yaml:69-79` (the go/bump lane); register M10 | The lane exists and is used; nothing links a recorded fix decision to a PR mechanically (a process criterion) |
| 6.7 exception fields, including the LOG reference | HELD | `lint-accepted-risk.sh:58,135,222`; `lint-log-anchors.sh:94-101` | |
| 6.8 accept and transfer never published as not_affected or fixed | HELD | `compile-vex.sh:434` (`"status": "affected"`); `lint-vex-product.sh:130-132` | Structural: two file formats, two lanes |
| 6.9 expired exception is uncovered | HELD | Trivy's `expired_at`; `lint-accepted-risk.sh:181-183` reddens validate first | No repository test asserts Trivy's expiry behaviour (third-party) |
| 6.10 rescan reports expired and expiring | HELD | `rescan.yml:456-479`; window from `catalogue-policy.yaml:108` | |
| 6.11 missing field or over ceiling fails | HELD | `lint-accepted-risk.sh:124-127,135,176-178`; `validate.yml:58` | Ceiling from the policy, measured from `decided_at` |
| 6.12 stray Trivy ignore file fails | HELD | `lint-accepted-risk.sh:36-42` | |
| 6.13 govulncheck in binary mode over every Go binary | PARTIAL | `build.yml:742-781`; `govulncheck-report.sh:53,79-81` | Finding 6.1: a heuristic walk, and a missing tool renders as "no Go binaries" |
| 6.14 a reachable symbol forbids not_in_execute_path | NOT HELD | rendered only (`govulncheck-report.sh:16-18`, `build.yml:799-800`) | No code compares govulncheck output with `triage/vex/`; the JSON is not uploaded; finding 6.5 |
| 6.15 cite a symbol- or package-level result | NOT HELD | `lint-log-anchors.sh:103-127` checks only that the citation resolves | The one live statement fails it; finding 6.2 |
| 6.16 module-level is unmeasured, never cited | PARTIAL | `govulncheck-report.sh:53,73-74` | Rendering right, practice follows; the "never cited" half unenforced |
| 6.17 product purl plus repository identity | HELD | `lint-vex-product.sh:96-99,119-122,153-157,203-207` | Error labelled with retired 6.18, finding 6.6 |
| 6.19 versioned subcomponent fails | HELD | `lint-vex-product.sh:218-220` | |
| 6.20 version rules | HELD | `lint-vex-product.sh:170-177,137-139,146-148` | Two clauses labelled with retired numbers |
| 6.22 retain superseded statements, add a later timestamp | NOT HELD | convention only (`triage/README.md:305-310`), practised in `CVE-2026-42151.openvex.json` | No lint, no test; finding 6.5 |
| 6.25 duplicate (id, path) in one file fails | HELD | `lint-accepted-risk.sh:140-146` | |
| 6.26 report exceptions that suppressed nothing | HELD | `accepted-risk-report.sh:79-91`; `build.yml:594` | |
| 6.27 identify the binary a suppression applied in | PARTIAL | `accepted-risk-report.sh:52-73` | Accepted-risk suppressions only; the VEX table at `build.yml:565` has no binary column; finding 6.3 |
| 6.28 scan compiled documents, never the source | HELD | `build.yml:525-532,933-937`; `rescan.yml:142-150` | `triage/vex/` is never handed to a scanner |
| 6.29 every product is a digest, index and platform manifests | HELD | `compile-vex.sh:104,264-267`; manifests supplied `build.yml:932`, `rescan.yml:141` | |
| 6.30 drop out-of-scope statements | HELD | `compile-vex.sh:249-258` | Tested (`validate.yml:154`) |

### Findings, group 6, first half

1. **Req 6.13's walk is a heuristic, and a missing tool reads as a clean
   result.** `build.yml:781` selects candidates with
   `find rootfs -type f -perm -u+x -size +1M`: a Go binary without the
   execute bit, or under 1 MiB, is never scanned. `:779` runs govulncheck
   with `2>/dev/null || true` under `continue-on-error: true`; if the
   `go install` at `:757` fails, every output is empty and `:795` prints
   "no Go binaries found in this image". "The tool never ran" and "this
   image has no Go binaries" are indistinguishable in the summary, the
   failure mode `govulncheck-report.sh:134-140` guards against one level
   down.
2. **The repository's one `vulnerable_code_not_in_execute_path` statement
   does not satisfy Req 6.15.** `triage/vex/CVE-2026-42151.openvex.json`
   cites `triage/LOG.md 2026-07-26`, whose heading (`LOG.md:96-106`) argues
   structurally ("does not start a Prometheus server") and cites no
   govulncheck result at symbol or package level; the statement's own notes
   say "architectural analysis". `lint-log-anchors.sh:118` checks that a
   heading is cited, not what it carries. Either the criterion needs a
   "WHERE reachability is the basis" qualifier, or the statement needs a
   measurement. Both readings are the owner's call.
3. **Req 6.27 names the binary for one lane only.** The accepted-risk
   report carries a Binary column; the VEX suppression table at
   `build.yml:565` (CVE, Status, Justification, Package) has none. PARTIAL
   under the literal "a suppressed finding"; HELD if scoped to the
   accepted-risk cluster. The text does not say.
4. **The gate does not consume the declared authoritative consumer.**
   `catalogue-policy.yaml:143-149` declares trivy authoritative and
   `triage-policy.sh:111-112` serves it, but `scan-image.sh:71` is a literal
   `trivy image`. A fork flipping the flag to grype gets a portability step
   that refuses (`vex-consumer.sh:66`) while the gate keeps scanning with
   trivy. Design Decision 10 states the Trivy coupling deliberately; the
   criterion's wording ("with its declared authoritative consumer") does
   not.
5. **Req 6.14 and 6.22 have no mechanism.** Every hit for
   `vulnerable_code_not_in_execute_path` in scripts, workflows and Go is a
   comment, fixture or summary note; nothing checks retention or timestamp
   ordering of superseded statements. Both are honoured in practice
   (`LOG.md:418-437` records a retraction; the 42151 document retains its
   superseded claim), by the maintainer, not by CI. Process criteria; the
   spec should say whether CI or the maintainer holds them.
6. **Retired numbers in error messages a reviewer reads.**
   `lint-vex-product.sh:3,6,9,11,206` (6.18), `:138` (6.21), `:147` (6.31);
   `lint-accepted-risk.sh:130,135` emit "Req 6.24"; `compile-vex.sh:424` and
   `triage/accepted-risk/grafana.yaml:1,12` say 6.23; `validate.yml:142`
   ("Req 6.17-6.21"), `build.yml:8,812`, `rescan.yml:4,9,528` (6.6, 6.2);
   `triage/README.md:107,126,161,281,283`; `docs/user-manual.md:330,816,1177`.
7. **Correct and worth knowing: `check-exceptions.sh` fails closed on a
   missing KEV feed** (`:57-61`, exit 2), and both callers turn that into a
   red run (`build.yml:835-838`, `rescan.yml:322-325`): an external outage
   is a build failure by design (Req 6.59, 6.60).
8. **`tasks.md` indexes retired numbers** as task requirements without a
   retirement note (`:107,110,130,137,144,157`).

## Requirement 6, second half: criteria 6.32 to 6.60 (27 live criteria)

| Criterion | Verdict | Mechanism (file:line) | Note |
|---|---|---|---|
| 6.32 compile report | HELD | `compile-vex.sh:474,218` | Drops recorded per product; a statement is omitted only when all its products drop |
| 6.33 report the drops in the run | HELD | `rescan.yml:691,705,716`; artifact `:742` | |
| 6.34 attest the document compiled for that digest | HELD | `reattest.sh:196,224`; `build.yml:998,1035,1047` | Products cover the index and every platform manifest |
| 6.35 the gate counts reported findings only | HELD | `build.yml:540`; `lint-vex-product.sh:132` | |
| 6.37 the compiler's declared inputs and no other | PARTIAL | `compile-vex.sh:109,120,277`; `reattest.sh:191-197` | A fifth, undeclared input, finding 6.9 |
| 6.38 exceptions published as affected with the action statement | HELD | `compile-vex.sh:413,434,441,326,184` | |
| 6.39 source statements limited to not_affected and fixed | HELD | `lint-vex-product.sh:132`; `validate.yml:143` | |
| 6.40 timestamp kept for life, last_updated on change | PARTIAL | `compile-vex.sh:189,193,198` | The change test is a four-field subset, finding 6.10 |
| 6.41 lapsed exception: under_investigation naming the lapse | HELD | `compile-vex.sh:376,384,413` | |
| 6.42 daily scan-report attestations | HELD | `reattest.sh:146,149`; `rescan.yml:292` | Attested before the compile, in order |
| 6.43 re-attest OpenVEX on change | HELD | `reattest.sh:205,216-218,224,227` | Also when any count is not one |
| 6.44 exactly one OpenVEX attestation per digest | OWNER-SIDE | `check-attestation-count.sh:44`; `rescan.yml:330` | Registry state; asserted daily, repaired the same run |
| 6.45 a deviation fails by name | HELD | `check-attestation-count.sh:47,58` | Fails on any count other than one |
| 6.46 the clocks | HELD | `triage/rescan/status.go:233,317-420`; `rescan.yml:601` | Supported set only through `inputs.LoadSupported` |
| 6.47 status issue with table, JSON, artifact | HELD | `status.go:541,651`; `rescan.yml:612,629` | Age against ceilings for undecided findings only |
| 6.49 aperture, ceilings, KEV ceiling, window, feed declared | HELD | `catalogue-policy.yaml:97,101,106,108,127`; `triage-policy.sh:56-88` | The support statement is read by nothing, finding 6.13 |
| 6.50 exception tiers by KEV then severity | HELD | `check-exceptions.sh:124-133`; `build.yml:839` | |
| 6.51 tiers re-evaluated daily | HELD | `check-exceptions.sh:112,135`; `rescan.yml:326` | |
| 6.52 close on absence with the evidence | HELD | `lifecycle.go:493,421,131` | The comment names every examined digest and the scanner version |
| 6.53 close on a covering statement or exception | HELD | `lifecycle.go:442,296-305` | |
| 6.54 close only on attested evidence, no recorded decision | PARTIAL | `lifecycle.go:479,500`; `fetch-sboms.sh:51` | The scan-report half is the run's own unattested report, finding 6.11 |
| 6.55 attested reports carry suppressed findings and versions | HELD | `scan-image.sh:74`; `reattest.sh:146`; `build.yml:973` | The database-version half is inferred from Trivy's writer, not asserted |
| 6.56 evidence-graded labels | HELD | `lifecycle.go:511,443-459,185`; `catalogue-policy.yaml:116-121` | `absent` whenever any manifest's SBOM is unread |
| 6.57 reopen on a returning finding | HELD | `lifecycle.go:396-419`; `rescan.yml:239` | Before the dedup step |
| 6.58 read attestations only through verification | HELD | `reattest.sh:63-71,170`; `fetch-sboms.sh:27-34,51` | The attested-scan-report half is vacuous: nothing reads one back |
| 6.59 KEV outage fails the PR gate by name | HELD | `build.yml:835-838`; `check-exceptions.sh:58-61` | |
| 6.60 KEV outage fails the rescan by name | HELD | `rescan.yml:322-325`; `:488` | |

### Findings, group 6, second half

9. **Req 6.37: the compiler has a fifth, undeclared input.** The criterion
   lists four inputs "and no other"; `compile-vex.sh:125` reads
   `COMPILE_VEX_ISSUES` and `:139` appends "tracked in <url>" to
   `status_notes`, fed by `reattest.sh:195` from the `gh issue list` map
   the rescan builds at `rescan.yml:271-276`. Live GitHub state alters
   published statement content. `tasks.md:275` states the behaviour
   openly; the criterion's closure clause was never amended. Either the
   text or the input is wrong.
10. **Req 6.40: two comparators disagree on what a change is.**
    `compile-vex.sh:193-197` sets `last_updated` when status, action
    statement, subcomponents or the issue URLs change, not on
    `status_notes` itself; `reattest.sh:205-213` decides whether to
    re-attest by comparing whole canonicalised statements. A notes-only
    change re-publishes the document with `last_updated` unchanged. Latent
    today (the embedded report basenames are stable), disagreeing by
    construction.
11. **Req 6.54: issues close on reports that are not yet attested.** The
    rescan's order is scan, lifecycle evidence, decide, apply closes and
    reopens (`:209`), then re-attest (`:286`). The lifecycle tool reads
    the run's raw Trivy JSON; nothing checks an attestation exists before
    a close. If re-attestation later fails for that digest (`reattest.sh:230`,
    three attempts then exit 1), the issue is already closed on a report
    that never became attested. The SBOM half is read through verification.
12. **design.md's rescan flow orders the lifecycle after re-attestation**
    (`design.md:722-735`); the workflow closes and reopens first, on purpose
    (`rescan.yml:172-178`: so the issue map the compiler stamps and the
    dedup see the same run's closes). `tasks.md:284` records only "before the
    dedup step". The design is the artifact that makes finding 6.11 look
    impossible.
13. **The support statement is declared and read by nothing.**
    `catalogue-policy.yaml:127-129` declares `triage.support`; `triage-policy.sh`,
    documented as the one reader of the section, has no query for it and
    validates it nowhere; the supported and superseded split is computed by
    `enumerate-catalogue.sh` from each definition's `tags:`. Decoration, by
    the aperture lesson's own standard.
14. **Retired 6.31 is a live label in `lint-vex-product.sh:3,11,141,147`**
    (findings are emitted as "6.31") and in `docs/user-manual.md:774,1177`;
    the rule was merged into 6.20 and the number is never reused.
15. **`rescan-status` is not given `--vex-reports`.** `rescan.yml:601-608`
    omits the flag the tool accepts (`cmd/rescan-status/main.go:40`) and
    the lifecycle tool receives (`rescan.yml:203`). A digest scanned without
    its VEX (over-reporting) therefore still feeds findings into the clocks
    and the status issue while the same digest correctly blocks every close.
    The same defect handled two ways.
16. **`package-set-diff.sh:133` reads an attestation body unverified**, the
    one such read in the repository; out of Req 6.58's scope (OpenVEX and
    scan reports only), in scope of finding 2.2.

## Requirement 9: catalogue posture and trust statement (18 criteria)

| Criterion | Verdict | Mechanism (file:line) | Note |
|---|---|---|---|
| 9.1 security policy contents | HELD | `SECURITY.md:13,35,45,60,69,77,92,109,124,130,141,160,172,192` | All required items present as named sections; no mechanical completeness check (prose) |
| 9.2 reports through GitHub private vulnerability reporting | OWNER-SIDE | `SECURITY.md:109`; asserted by `scripts/check-governance.sh:97` in `rescan.yml:646` | Enabled by the owner on 2026-09-08; the dispatched rescan of 22:03 and the scheduled one of 2026-09-09 passed the step |
| 9.3 daily assertion of private reporting | PARTIAL | `check-governance.sh:100` | Correct, including the fail-closed unreadable path; the daily clock is not guaranteed, finding 9.1 |
| 9.4 advisories as repository security advisories | OWNER-SIDE | `SECURITY.md:124`; register M14 | No check of any kind; none published yet; finding 9.4 |
| 9.5 revocation record | HELD | `triage/revocations.yaml:17`; `triage/revocations.schema.yaml:6,13` | Every field required by the schema; the list is empty today, so the mechanism has run only on fixtures (17 assertions) |
| 9.6 schema failure names the violation | HELD | `validate.yml:38` (yamale) | In the required lint battery |
| 9.7 a tag on a revoked digest fails the daily run | PARTIAL | `scripts/check-revocations.sh:58`; `rescan.yml:651` | Logic correct (index and per-platform hits); the step can be skipped, finding 9.1 |
| 9.8 committed ruleset, both gates required | HELD | `.github/rulesets/main_sec.json:57,61` | Contexts match the job display names in `e2e.yml:255` and `build.yml:1084` |
| 9.9 daily ruleset comparison, both directions | PARTIAL | `check-governance.sh:39,132,158`, anonymous (`:47`) | Both directions present; the weaker live ruleset was deleted on 2026-09-08 and the check passes since; daily clock not guaranteed, finding 9.1 |
| 9.10 CODEOWNERS per lane | HELD | `CODEOWNERS:6-10` | Five lanes |
| 9.11 declared consumers, one authoritative, one normalised shape | HELD | `catalogue-policy.yaml:143-149`; `triage-policy.sh:106-107`; `vex-consumer.sh:115,56` | |
| 9.12 portability block on PR scan and rescan | HELD | `build.yml:707`, `rescan.yml:385`; `vex-portability.sh:121-126` | Supported set only, verified: superseded reports are routed to a separate directory (`rescan.yml:147-148`) |
| 9.13 daily verbatim run of the published recipe | PARTIAL | `rescan.yml:431`; `consumer-smoke.sh:63,145,212` | A closed loop (finding 9.7); the daily clock is not guaranteed, finding 9.1 |
| 9.14 manual-controls register | HELD | `docs/CONVENTIONS.md:415,425` | M1 to M22 and P1, P2; the tasks.md ledger still says twenty rows, finding 9.6 |
| 9.15 trust-boundary table | HELD | `docs/concepts.md:219,229` | Three owner classes, authenticity class on upstream rows, a seam column on every row |
| 9.16 notice, licence text, SBOM statement | HELD | `NOTICE:4-6,21-23`; `LICENSES/Apache-2.0.txt` | |
| 9.17 README non-affiliation | HELD | `README.md:29`; restated `SECURITY.md:189`, `NOTICE:38` | |
| 9.18 LOG anchors both directions | HELD | `scripts/lint-log-anchors.sh:94,111`; wired `lint-accepted-risk.sh:222`, `validate.yml:148` | Run on the tree: 12 refs and 6 citations resolve; a decision without a citation fails too |

### Findings, group 9

1. **The posture and smoke steps can be skipped for an unbounded run of
   days.** In `rescan.yml`, `posture invariants` (`:646`) and `consumer
   smoke test` (`:431`) carry no `if: always()`; only `summary` (`:665`) and
   the artifact upload (`:741`) do. Every step above them can hard-fail:
   `invariants` (`:307`) exits 1 by design when the KEV feed is unreachable
   (`:322-324`), and `authenticity signals` (`:344`) ends `exit "$rc"` on any
   mismatch, a failure that register row M18 says persists daily until a
   human clears it. One unresolved supply-chain signal therefore suppresses
   the private-reporting check, the ruleset comparison, the revoked-tag
   assertion and the smoke test every day. The step comment reasons only
   about the forward direction ("a posture failure never starves the day's
   scans"). Same shape as finding 2.9 for the invariants step. The fix is
   `if: always()` on both steps plus a guard on the enumeration file.
2. **The live ruleset drift the files still record is resolved.**
   `data/rulesets-admin-view-2026-09-07.json` lists two active branch
   rulesets and `tasks.md:345` records the operator item; the owner deleted
   the weaker ruleset (id 19534405) and enabled private reporting on
   2026-09-08, and the rescans since pass the posture step. The data file
   is now a historical snapshot and says so in its `read` field.
3. **SECURITY.md's governance paragraph** (`:94`, "the ruleset on main,
   measured 2026-09-07") described one ruleset while two were live on that
   date; true today by deletion rather than by the paragraph. No edit needed
   unless the measurement date is refreshed.
4. **Req 9.4 has no assertion.** Every other GitHub-state criterion in the
   group has a daily check; advisory publication rests on the prose and
   register row M14. Defensible while no advisory exists; a knowing
   asymmetry rather than an oversight, and worth naming as such in the
   register's reason column.
5. **Req 9.1, 9.14 to 9.17 are prose criteria with no guard**; an edit that
   drops the epoch or the retention paragraph goes green. Consistent across
   the group, not a one-off; the register and the trust table are
   human-judged for completeness, and no mechanism could judge them.
6. **Ledger drift**: `tasks.md:361` (task 13.5's as-built) says "twenty
   deliberate rows (M1 to M20)"; the register carries M22 since task 14.4.
7. **Req 9.13 is a genuinely closed loop** (verified): the recipe is rendered
   from the policy file, spliced byte-identically into README.md and the
   manual (diffed), drift-checked on every PR, and executed verbatim with
   only the reference substituted; a declared consumer with no recipe step
   is refused at render time, and cosign is installed at `rescan.yml:66`,
   well before the smoke step.

## The layer above the criteria: tasks, design, documents

Thirty ticked tasks were sampled across groups 1 to 14, weighted toward
9 to 14, and every artifact they name was looked for. Twenty-six match.
Four do not:

| Task | Claim | Result | Evidence |
|---|---|---|---|
| 9.1 | "`cosign-release` pinned ... with a Renovate manager over the pin (Req 7.5, 7.6)" | differs | `renovate.json5` contains no "cosign"; `build.yml:296-298` says "not yet Renovate-tracked"; register row P1 records the gap |
| 9.1 | "Measure `cosign attest --recursive` on v2.6.0 first and fall back" | differs | `build.yml:1005-1009`: coverage of children "is unmeasured here"; the fallback shipped without the measurement |
| 10.3, 13.4 | `triage/upstream/checks/trivy-vex-oci-multiple-attestations.sh` "joins the daily consumer smoke test" | not found | the script is referenced by no workflow or script; the check exists as inline logic in `consumer-smoke.sh:147-169`, which `design.md:551-554` describes correctly |
| 13.5 | "twenty deliberate rows (M1 to M20)" | differs | the register carries M1 to M22 since task 14.4 |

Two ledger anomalies: `tasks.md:159` is `- [ ] 8. Wrap-up (Day 3)` while
8.1 to 8.7 are all ticked (the only genuinely open group is 12); task 8.7's
line still describes chart-version tracking as an open gap that task 11.4
closed.

### Design divergences

1. `design.md:253-260` (Decision 6): "the rescan gains a single `invariants`
   step that runs every daily assertion ... one step, one report shape".
   As built there are three (`rescan.yml:307,344,646`) plus the standalone
   smoke test (`:431`) and expiries (`:456`); tasks 13.2 and 13.3 record the
   split deliberately, Decision 6 was never brought along.
2. `design.md:728-732` (rescan flow) lists 9.3, 9.7, 9.9 and 9.13 inside the
   invariants step; the workflow runs the first three last and 9.13 on its
   own.
3. `design.md:707-710` (release flow) orders attest, compile, fail-closed;
   the code gates first (`build.yml:949`), so under fail-closed no scan
   report is attested either, a consequence the design does not state.
4. `design.md:733-735` (rescan flow) places the issue lifecycle after the
   clocks and status; the workflow runs it first (`rescan.yml:179-267`),
   and Decision 7's own as-built paragraph (`:361-363`) says so. The flow
   diagram contradicts its decision's as-built note.
5. `design.md:558`: "twenty deliberate rows"; `design.md:676-689` names M21
   and M22. The document disagrees with itself.
6. `design.md:599`: "rescan enumeration and badges stay tag-driven for
   inactive definitions". Badges were retired before they were built.

Decisions 6 to 11 otherwise check out: the recursive signing shape, the
per-manifest SPDX plus the index SPDX, `--replace` re-attestation, the
digest automerge ordered before the build-layer rule, `consumers.gating:
false`, the builder contract and the active set.

### Stale documentation not already listed under a group

1. `README.md:47`, "every image published to the namespace is signed", and
   `:10`, "existing digests stay pullable and verifiable": the policy file
   declares a deliberately unsigned digest under a catalogue repository as
   the must-reject control, and SECURITY.md records a legacy stratum whose
   platform manifests are unsigned. True of supported indexes, not of every
   published digest.
2. `README.md:40`, the `policies/` row, omits `verify-catalogue-images.yaml`,
   the admission policy the "Verify an image" section rests on.
3. `docs/user-manual.md:70` places `requirements-ci.txt` under
   `.github/workflows/`; it is `.github/requirements-ci.txt`.
4. `docs/user-manual.md:69,1171`, "every `x.sh` has an `x_test.sh`":
   `scripts/render-chart.sh` has none (35 of 36).
5. `docs/user-manual.md:1174-1195`, the Part VI scripts reference, omits 16
   of 36 scripts, all workflow-invoked: check-attestation-count,
   check-authenticity, check-governance, check-revocations, consumer-smoke,
   fetch-sboms, reattest, vex-consumer, vex-portability, lint-active-set,
   lint-compat, lint-log-anchors, lint-probes, lint-workflow-policy,
   render-tracking, render-verification. A task-9-era snapshot.
6. `docs/user-manual.md:1187` and `docs/CONVENTIONS.md:78-80` list six
   tools for `install-tool.sh`; it installs seven (`vexctl`, pinned with a
   checksum, `install-tool.sh:81-82`). The script's own header is stale the
   same way.
7. `docs/user-manual.md:223-235`, the deploy walkthrough's copy-paste
   commands, use `--version v1.21.0` and `0.11.0` against pinned v1.21.1 and
   0.12.0 (the same drift as finding 3.3).
8. `docs/user-manual.md:1227-1236`, the requirements map, has a Req 8 row
   (retired) and no Req 9 row (18 live criteria, the whole posture group).
9. `docs/CONVENTIONS.md:237` says chart image pins live in
   `config/values-hardened.yaml`; hardened-app's are in `values.yaml`, and
   both managers match both.
10. `SECURITY.md:66-67`, "this repository is archived intact", present
    tense while task 12.1 is open; `:8-11` uses the future tense.
11. `docs/user-manual.md:330,816,1177,1181` cite ranges that include the
    retired 6.18, 6.21, 6.24 and 6.31; `triage/README.md:107,126,161,281,283`
    and `triage/LOG.md:313,629,876,1042` likewise (the LOG entries are
    history and may stay).

SECURITY.md is otherwise clean against the code: identities, predicate
sets, the one-OpenVEX invariant, the aperture and ceilings, the digest
states, the five daily assertions, governance, the empty revocation record
and the seven authenticity classes all match.

### Test coverage

All 35 `scripts/*_test.sh` suites run as explicit validate steps, and the
every-suite check (`validate.yml:213-220`) does catch a missing one (it
loops the suites and greps the workflow for `run: <suite>`). The go job
runs gofmt, vet, build and the six Go test packages. Not guarded:

- The `test/` module's packages are enumerated by hand; a new package would
  build but never test, and nothing would go red. The script side has a
  completeness check; the Go side has none.
- `scripts/render-chart.sh` has no suite, and the check runs one way only.
- The completeness grep would be satisfied by a commented-out `run:` line.
- `triage/upstream/checks/*.sh` (seven reproduction scripts) are run by
  nobody, by design for most of them; two tasks claim one is wired into the
  smoke test.

## Deferred ledger, and where the catalogue's picture of itself went

The question "where is the visualisation of the catalogue state?" has a
short answer: it was decided against twice, and the data it would draw
from has existed since task 10.7. The trail:

| Item | Decided where | Reason given | Status today |
|---|---|---|---|
| README badges (shields.io over the public API: open `cve` issues, workflow status) | 2026-08-21 critique, F4/F5 dispositions ("Badges (decided 2026-08-21): (a) now, (b) when the metrics exist") | Presentation with no secrets; "only the rescan writes a badge's number" | Never added. Retired 2026-08-25 (primitives finding 5.7): Req 6.48 removed, task 10.5 closed, "README badges stay an optional hand-added cosmetic outside the rulebook". README carries none. |
| Self-rendered clock badges and a GitHub Pages publication of `metrics.json` | Same disposition, part (b) | The rescan renders with `badge-maker`, no third party in the view path | Never built; retired with 6.48. |
| A Pages dashboard over the status JSON | Design Decision 7: options list "a Pages dashboard", decision "status issue plus artifact ... Pages later", rejected "a Pages dashboard now (presentation before the data exists)"; `docs/user-manual.md:679-680` ("presentation over that JSON and nothing else") | Bot commits of a metrics file violate "everything enters as a pull request"; presentation before the data exists | The data exists daily since task 10.7 (status issue #151, fenced JSON, the `catalogue-status` artifact). No task, no criterion, no decision to build it; GitHub Pages is off (2026-08-21 critique). An open decision, not a gap against the spec. |
| Tombstone image for a revoked digest | Task 13.3, `docs/revocation-runbook.md` | GHCR refuses tag deletion for public packages past the download threshold; a tombstone was documented, not built | Runbook documents the manual path. |
| P1: a Renovate manager for the cosign pin | Register row P1 (2026-09-08) | No manager matches the `cosign-release:` line; ADR 0003 promised one | Pending automation. |
| P2: automatic re-scoping of version-scoped VEX statements on a grafana bump | Register row P2 | The mechanical half is scriptable; the changed-module half is a decision | Pending automation; the 13.2.1 minor (#89) waits on a triage session. |
| notation and policy-controller as alternative renderings of the verification policy | Trust-boundary table, `docs/concepts.md` | Declared renderings of one declared value, not built | Not built, by design. |
| The `.deb` route for a grafana cryptographic anchor | ADR 0002 | GitHub carries no linux tarball; the `.deb` path is unverified | Not built; grafana ships as a reference definition behind the active-set switch. |
| Running Renovate as a GitHub App (verified commits, bot identity, no PAT rotation) | Owner conversation 2026-09-09 ("another time") | Not spec-bound; a governance improvement | Open. |
| The successor repository: cut, seed, archive this one | Design Decision 9, task 12.1 | Executes after every implementation task | The one unticked task. |
| Requirement renumbering | `requirements.md:29`; `tasks.md:330` | The successor's seed renumbers contiguously once | Open; the retired-citation cluster in this review is the cost of leaving it |
| diffoci or reproducibility as a primary gate | `tasks.md:227`; `design.md:213-216` | A black-box frontend over apk is where reproducible flags fail; promotion needs two clean weeks | Deferred; the nightly digest-equality measurement is implemented (`package-set-diff.sh:25-26,164`) |
| arm64 e2e | `tasks.md:233` | The cost is the build, not the scan | Deferred; `e2e.yml` has no platform key |
| Re-pointing the ten legacy tags | `tasks.md:239` | cosign signed indexes only; a re-point would serve an unsigned manifest | Withdrawn 2026-08-22; scanned in place |
| `triage/ledger/`, a five-treatment vocabulary, committed compiler output | `tasks.md:148` | Not pulled forward from the v2 draft | Deferred; four treatments, compiled output ignored by git |
| Historical backfill of `decided_at` and pre-epoch statements | `tasks.md:258,265`; Decision 9 | The successor starts native | Honoured; all 13 entries carry 2026-09-03 |
| Gating the portability block | `tasks.md:354`; `design.md:534-535` | Informational first, a fork flips it | Honoured; `consumers.gating: false` |
| Docker Scout adapter | `design.md:509` | Credentials and a third pinned CLI; a fork's addition | Honoured; the adapter refuses scout by name |
| A Trivy-compatible VEX repository for frozen digests | 2026-08-21 critique | Deferred to the Pages layer | Deferred; no publisher exists |
| Second maintainer, protected release environment | `design.md:530-533` | Outside the one-person frame; nightly rebuilds must not wait for a human | Honoured; no `environment:` key anywhere |
| Bot-committed metrics file | `design.md:336` | Violates "everything enters as a pull request" | Honoured; the JSON is an artifact |

What exists as the catalogue's published picture of itself: the status issue
(summary line, one row per finding with its clocks, a fenced JSON block),
the same JSON as a daily artifact, the rescan's job summary (the VEX
compilation table, the portability block, the re-attestation table), the
Renovate Dependency Dashboard (bump state), and the security policy's
digest-state vocabulary. Everything a dashboard would show is in those; the
dashboard itself is a decision nobody has taken yet.

## Proposed dispositions

Every call below is the owner's. Each row is one pull request, framed so
that it can be accepted, changed or declined on its own; the order is the
order of what each gap costs.

| # | Theme | Proposal | Findings |
|---|---|---|---|
| D1 | The rescan's assertions run regardless of earlier steps | `if: always()` on the invariants, authenticity, portability, smoke, status, expiries and posture steps, each refusing by name when its input file is missing (the revocation check already has the pattern); the header comment rewritten to what the file does; a fixture run proving a failed authenticity step still publishes status | 2.9, 3.1, 3.5, 3.9, 9.1 |
| D2 | Verified reads | The comparator reads the published CycloneDX through `cosign verify-attestation` with the releaser identity, as `fetch-sboms.sh` does; `rescan-status` receives `--vex-reports`; and a decision on Req 6.54: either apply the issue closes after re-attestation (the compiler's issue map then lags one day) or amend the criterion to "attested by this run before it completes" with a failed re-attestation reopening what it closed | 2.2, 6.11, 6.15 |
| D3 | Silence reads as failure | govulncheck missing or failing to run fails the step by name instead of printing "no Go binaries"; the fail-closed gate names each uncovered finding from the per-manifest reports; the `release:` section is validated by a reader (`triage-policy.sh`'s shape) so a misspelt switch is a refusal; `lint-workflow-policy.sh` fails on a declared cron absent from its workflow and globs both spellings | 6.1, 2.1, 2.10, 2.13, 5.13 |
| D4 | The pin surface | cosign installed through `install-tool.sh` with a version and sha256, which also gives it the pin-script manager and closes P1; the built-in `github-actions` manager enabled under the three-day age rule so the 25 Action pins receive bumps; the probe image pinned by digest with its comment corrected; `gomod` enabled for `test/` and `triage/rescan`; CONVENTIONS' 7.5 paragraph rewritten to the truth | 5.2 to 5.5, 5.9, 5.12 |
| D5 | Spec amendments where the code is right | 6.37 declares the issue-map input; 5.5 and 5.8 say "declared by the chart that deploys it"; 6.1 either names Trivy with the coupling stated (Decision 10's position) or the gate consumes the declared consumer; 5.2 says the published image is installed and the proposed one after merge; 6.14, 6.15 and 6.22 say whether the maintainer or CI holds them, and the one reachability statement either gets a govulncheck measurement or a justification that does not claim one; 6.27's scope; 1.4 gets a lint over `accounts:` or is re-scoped to the chart's securityContext; 2.4's active branch stated as implemented by absence or given a check; Decision 6's text and both flow diagrams redrawn to the built order; the four task-ledger corrections (9.1 cosign, 10.3 and 13.4 script, 13.5 count, group 8 tick, 8.7 line) | 1.1, 2.11, 2.7, 2.8, 5.1, 5.6, 5.8, 6.2, 6.4, 6.5, 6.9, 6.12, design divergences 1 to 6 |
| D6 | Documentation truth pass, the rest | The manual's amd64 paragraph; the chart READMEs and the two reproduce comments stop quoting a version literal and point at the pin (or a lint holds them equal); the manual's "every overlay", "every definition", scripts reference, requirements map (Req 9 in, Req 8 out), `requirements-ci.txt` path, vexctl in both tool lists, deploy walkthrough versions; README's `policies/` row and "every image is signed"; SECURITY.md's tense; the retired ids in error messages, step names, script headers and the tasks and design ledgers, with the test strings that assert on them; the three stale headers and comments (`verify-arch-pins.sh`, `install-tool.sh`, `probes_test.go`, `rescan.yml`); CONVENTIONS' "all enforced", tarball shape and chart-pin path | 1.4 to 1.7, 2.6, 2.7, 3.3 to 3.8, 3.10, 5.8 to 5.11, 6.6, 6.8, 6.14, 9.6, stale documentation 1 to 11 |
| D7 | Decoration and missing negative cases | `triage-policy.sh` reads and validates the support statement or the declaration goes; `lint-compat.sh` requires a `compat:` block when a chart's `deploys:` names a `-compat` definition; the mislabelled `lint-pins` test corrected and the keyring case added; `go test ./...` in both modules; a `render-chart.sh` suite; a detective check that no inactive definition gained a digest (enumeration against the active set) | 6.13, 3.2, 1.6, 1.8, 1.7, test coverage |
| D8 | A picture of the catalogue | Not a gap against the spec: a Pages site rendered by the rescan from the status JSON (and, if wanted, the shields-style badges the 2026-08-21 disposition described) is a new decision, here or in the successor. The data exists daily; GitHub Pages is off; `pages: write` would join the rescan's permissions and the policy file's workflows section | deferred ledger |

Not proposed: anything that changes the catalogue's promise, the active set,
the treatments, or the successor's timing. The three NOT HELD criteria are
process criteria and belong in D5, not in code.

## Confidence notes

- Every verdict comes from the files; nothing was executed against CI, the
  registry or GitHub except the read-only live-state measurements at the
  top. Where a lint's negative path mattered, it was run against a mutated
  copy under a scratch directory (`lint-pins.sh` for 1.3, 1.4, 1.7;
  `verify-arch-pins.sh` for 1.3), never against the tree. `lint-log-anchors.sh`,
  `lint-probes.sh`, `render-verification.sh --check`, `render-tracking.sh --check`
  and `lint-workflow-policy.sh` were run on the tree and pass.
- Inferred, not measured: cosign's `--recursive` covering every platform
  manifest (2.9); Trivy honouring `expired_at` in the ignorefile (2.8, 6.9)
  and suppressing only not_affected and fixed (6.35, 6.53); the scanner
  database version reaching the attested report (6.55); Kyverno's exit
  semantics in the chart gate (4.6); Helm's deep merge behind the partial
  securityContext overlays (4.3); GitHub Actions' step-skipping on a failed
  step without `if:` (every ordering finding). Each is either recorded as
  measured elsewhere in the repository or standard behaviour; none was
  re-measured here.
- Renovate's runtime behaviour (grouping, major staging, automerge gating)
  is read from config and fixtures; only extraction, the age rule, the
  automerge rules and the ignore filter are exercised by the fixture suite.
- The two live findings the group 9 reading made from the dated files
  (private reporting off, a second ruleset) were resolved by the owner on
  2026-09-08 and are recorded here as resolved on the evidence of the two
  green rescans since.
- Task claims were sampled (30 of the ticked tasks), not exhausted; the
  as-built notes of groups 9 to 14 were read in full.
- Line numbers drift with every merge; the file and the mechanism are the
  durable part of each citation.

