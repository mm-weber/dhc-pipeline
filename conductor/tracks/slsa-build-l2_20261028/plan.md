# Implementation plan: SLSA Build L2, provenance from the platform's signed claims, verifiable, demanded from the successor's epoch

**Track ID:** slsa-build-l2_20261028
**Spec:** [spec.md](./spec.md)
**Created:** 2026-10-28
**Status:** [~] in progress (phase 0 merged 2026-11-10 as #337, 09dcfdf; phase 1 measured 2026-11-11, runs 43025700201 to 43033859220 on #401, recorded in ADR 0005; spec amended 2026-11-11, one provenance mode, Req 2.30; phase 2 held 2026-11-11 on the bundle finding, re-planned 2026-11-13 at the owner's call: the provenance is unpacked into the attestation layout, task 0.5; phase 2 revised the same day after a critical review of the design, the changes listed under phase 2; 0.5 merged 2026-11-13 as #408, ff115e1; 2.1 measured the same day, run 43507882508 on #401: one statement for both subjects is accepted on both digests by all three verifiers; next 2.2, the owner's go)

## Overview

Six phases, one pull request each, spec task group 18. Phase 0 is this pull request: the spec amendment and the track, together, the #308 precedent; the owner confirms by merging. Phase 1 measures what verifies the provenance service's bundle and records it in ADR 0005, no catalogue change. Phases 2 to 4 build by TDD (RED agent, GREEN agent, orchestrator commits per slice): the release step, the coverage report, the declaration with its renderings and the smoke-test assertion. Phase 5 states the claim. Phase 6 is the evidence. Nothing here demands provenance in this repository's policy; the successor does from its first release (task 12.1). Amended 2026-11-13 (task 0.5): the bundle the provenance service returns is never pushed beside a digest, because there it hides the digest's signature and attestations from cosign 2.6.5; phase 2 unpacks it into the attestation layout the other attestations use.

## Phase 0: the spec amendment and the track (this pull request; task 18.1)

### Tasks

- [x] **0.1 The amendment**: requirements.md 2.9, 2.10, 2.23, 2.25, 7.7 amended, 2.27 to 2.29 and 9.19 added; design.md Decision 15; tasks.md group 18, 12.1's SLSA bullet, the coverage rows; ledger rows 2.27, 2.28, 2.29, 9.19 and the notes on 2.10 and 2.25
- [x] **0.2 The track**: this folder, `conductor/tracks.md`, `conductor/index.md`, the todo's open item
- [x] **0.4 The amendment of 2026-11-11** (its own pull request, the owner's call of that day): one provenance mode in the policy file's release section, `off`, `report` or `required`; requirements.md 2.9, 2.10, 2.23, 2.25, 2.27 to 2.29 and 7.7 reworded, 2.30 added; Decision 15's amendment; tasks.md 18.1, 18.3 to 18.7 and 12.1's bullet; ledger row 2.30; FR-7 and phases 2 to 6 here; `scripts/lint-live-evidence.sh .` green (160 criteria)
- [x] **0.5 The amendment of 2026-11-13** (its own pull request with the four measurement records, the owner's call of that day): the provenance is stored in cosign's attestation layout and no Sigstore bundle sits beside a digest; requirements.md 2.27's storage clause and the header's amendment line; Decision 15's amendment; ADR 0005's amendment (decision 1 superseded: no second policy entry); tasks.md 18.1 and 18.3 to 18.5; FR-1, the risks and phase 2 here; `data/cosign-bundle-coexistence-2026-11-11.md`; no criterion added, `scripts/lint-live-evidence.sh .` green (160 criteria); the owner merges (checkpoint). Merged 2026-11-13 as #408, ff115e1.
- [x] **0.3 The pull request**: title `spec: SLSA Build L2, provenance from the platform's signed claims, demanded from the successor's epoch (Req 2.27 to 2.29, 9.19; task 18.1)`, a TL;DR; the owner merges (checkpoint)

### Verification (orchestrator)

- [x] Every added or amended criterion in EARS shape; `scripts/lint-live-evidence.sh .` green (159 criteria); no em-dashes in the added lines; no closing keyword before an issue number

## Phase 1: the verifier, measured (task 18.2)

Dependency: phase 0 merged. Worktree `slsa-spike`. [OPERATOR: one dispatch on the branch.]

### Tasks

- [x] **1.1 The spike workflow** on a branch only, never merged: build a scratch image, push it to the scratch repository outside `verification.registry`, attest it with `actions/attest-build-provenance` pinned by commit, `push-to-registry: true`, subjects one index and one platform manifest
- [x] **1.2 The reads**: the predicate as emitted (builder id, build type, external parameters, resolved dependencies), the bundle's location and artifact type, an anonymous read; verification by Kyverno 1.19.1, cosign 2.6.5, `gh attestation verify --bundle-from-oci` (with and without a login), Trivy 0.72.0 if it reads it (measured at the pins of the day, Kyverno 1.19.2 and Trivy 0.76.1; without a login the GitHub client refused to start inside Actions, so that half stays unmeasured)
- [ ] **1.3 The record**: `data/slsa-provenance-spike-<date>.md` and `docs/decisions/0005-slsa-provenance-verifier.md` naming the policy verifier, the consumer command and the five expectations' exact values; the scratch package deleted; if only cosign v3 reads the bundle, the owner's call on ADR 0003 before phase 2
  - Written 2026-11-11: `data/slsa-provenance-spike-2026-11-11.md`, ADR 0005; the pinned cosign 2.6.5 reads the bundle, so ADR 0003's gate is not triggered. Open: the scratch package `ghcr.io/mm-weber/slsa-spike` (six image tags, twelve bundle tags) is the owner's to delete, the workspace token cannot; #401 closed unmerged after this record merges

### Verification

- [x] The ADR cites the run id and the measured outputs; no catalogue repository touched (every push and attestation of the six runs names `ghcr.io/mm-weber/slsa-spike`; the workflow refuses a target inside `verification.registry`)

## Phase 2: provenance in the release path (task 18.3)

**Objective:** unless the provenance mode is `off`, every release carries one provenance statement from GitHub's provenance service, stored beside the index and beside each platform manifest as one more layer of the `.att` manifest cosign 2.6.5 already reads, verified by the release itself before any tag is applied; no Sigstore bundle beside a digest (Req 2.9, 2.27, 2.30, 7.7; FR-1, FR-7; Decision 15 and ADR 0005 as amended 2026-11-13).

**Dependency:** 0.5 merged. The owner's go for 2.1's run, and again for the first slice.

**Worktrees:** 2.1 on `slsa-spike` (#401, never merges). 2.2 onwards in a new worktree `provenance-step` (`scripts/worktree-create.sh dhc-pipeline provenance-step`), one pull request.

**Suites:** `scripts/release-policy_test.sh` (extended); `scripts/unpack-provenance_test.sh` and `scripts/check-provenance_test.sh` (new): crane and cosign are stubbed on `PATH`, the convention of `check-attestation-count_test.sh` and `fetch-sboms_test.sh`. `scripts/provenance-real_test.sh` (new): the two scripts against the pinned crane 0.22.1 and cosign 2.6.5 themselves, a throwaway registry on 127.0.0.1 (`crane registry serve`) and Sigstore's public trust root from fixture files, so that what the stubs accept is also what the real tools accept (slices 2.4.28 and 2.5.13). No network beyond 127.0.0.1 in any of them. Each suite has its own step in `validate.yml`.

**Revised 2026-11-13 after the critical review** (one read-only reviewer against the design, the owner's request; its sources under the session's scratch directory, its findings in the handover):

- The scripts were tested against stand-ins only, and the first real verifier to read a layer written by the production script would have been a release on main. Now: the real-tool suite above, and Kyverno 1.19.2 on the first release (verification list).
- The real bundle carries two `logIndex` numbers; slice 2.4.2 names the one cosign's layout wants.
- Only a `pull_request` event was measured, and the action chooses its Sigstore instance from the event's `repository.visibility`: the first pushed, the first scheduled and the first dispatched release are each read (verification list), and the refusal of 2.4.13 names that cause.
- Nothing can exercise a bump of the action before main: the rule of 2.7.1.
- The mode `report` withholds a release whose provenance cannot be produced (Req 2.9; the owner's call of 2026-11-13: it stays so). Made cheap: both scripts try a failed registry or verification call again (2.4.24, 2.5.11), and the way out is written down (2.6.5).
- A provenance layer lost on a tagged digest had no way back: the unpack also reads the attestation store's answer (2.4.22).
- Slices added for a log entry of another kind, several statements naming one digest, the subject lines, a digest named twice; three sentences corrected (where the platform manifests come from, what happens to the envelope, how the releaser identity is read).

**How every slice runs** (one test per slice, never two):

1. RED agent (general-purpose, `isolation: worktree`): writes the one test named in the slice, plus a stub that does nothing where the script does not exist yet, runs the suite and reports the failing assertion with found and expected.
2. The orchestrator applies the test to `provenance-step`, runs it, confirms it fails on the assertion (never on a missing file or a syntax error) and commits `test: <behaviour> (RED 2.x.y)`.
3. GREEN agent (general-purpose, in `provenance-step`): the least code that passes this test; no new test; the whole suite green.
4. The orchestrator reads the diff, runs the suite and every other suite under `scripts/`, commits `feat: <behaviour> (GREEN 2.x.y)`, and re-reads the remaining slices before the next one.

A test that comes up green at once (the earlier slice's code already covers it) is committed as a guard and named so, the proof-kinds 1.1 precedent.

### Tasks

- [x] **2.1 One statement for every subject, measured** (no catalogue change; one dispatch on #401, the owner's go) [OPERATOR]
  - Why first: a `uses:` step cannot loop, and the platform manifests are read from the pushed index at run time (the step `manifests`), their number following the definition's platforms, so one statement naming the index and every platform manifest (`subject-checksums`) is the only shape with a fixed number of steps. Read in the action's and cosign's sources (cosign 2.6.5 and 3.1.2 pass when any subject of the statement matches), not yet measured end to end.
  - The run: the spike workflow attests once with `subject-checksums` (the scratch index and its amd64 manifest), `push-to-registry: false`; the spike's unpack stores that one statement beside both digests; then, on each of the two digests: cosign 2.6.5 `verify-attestation --type slsaprovenance1` with the subject check on, Kyverno 1.19.2 `kyverno apply` through the `Cosign` entry with the five expectations, `gh attestation verify` against the attestation store.
  - Recorded in `data/cosign-bundle-coexistence-2026-11-11.md` with the run id. A later step of the same run attests the index alone a second time, so that the attestation store holds two statements for the index and one for the platform manifest. The store's answers, as the API gave them, become the suites' fixtures (2.4): the platform manifest's (one statement) and the index's (two, for slice 2.4.21); `gh attestation verify` on the index is read with two statements present.
  - IF any of the three verifiers refuses the two-subject statement on either digest THEN stop and bring the fallback to the owner before any slice: one statement per subject, which needs one attest step per admitted platform or a job per digest.
  - Result (2026-11-13, run 43507882508, spike commit 7e74982; index `sha256:c47ac86f0e71…`, amd64 `sha256:ac78223352dc…`): no verifier refused. cosign 2.6.5 exit 0 on both digests with the subject check on; Kyverno 1.19.2 pass on both, and in the catalogue-shaped policy on the index, each control exit 1; `gh attestation verify` exit 0 on both, by owner and by repository plus signer workflow. After the second attest the store holds two statements for the index, the newer first, and one for the amd64 manifest; `gh attestation verify` on the index returns both. The fallback is not needed. Record: `data/cosign-bundle-coexistence-2026-11-11.md`, the section "One statement for every subject".

#### 2.2 The mode (`scripts/release-policy.sh`, suite `scripts/release-policy_test.sh`)

The suite's `policy` helper gains `provenance: report` with slice 2.2.1 (the RED agent's one fixture change).

- [ ] **2.2.1 The query `provenance` returns the declared mode** (tracer; FR-7)
  - RED: `release-policy.sh "$SB" provenance` prints exactly `report`, exit 0. Fails because the query is unknown (exit 2).
  - GREEN: the query, reading `release.provenance`.
- [ ] **2.2.2 The policy file declares `release.provenance: report`** (by hand, no test: a YAML edit with its comment block naming Req 2.30 and the three positions; then `yamllint catalogue-policy.yaml` and `scripts/release-policy.sh . provenance` printing `report`). Placed here so that the real file never fails the `check` of 2.2.5.
- [ ] **2.2.3 `off` and `required` come back as written**
  - RED: `provenance: off` prints `off`; `provenance: required` prints `required`. Fails if the reader hands back PyYAML's value: a bare `off` is the boolean False there and the string `off` in mikefarah's yq, the disagreement the two booleans already guard against.
  - GREEN: the raw token as written (`raw_token`), the way `boolean()` reads.
- [ ] **2.2.4 A missing mode is refused, never defaulted**
  - RED: the `provenance:` line deleted; exit 2; the message names `provenance` and `off, report or required`.
- [ ] **2.2.5 A value outside the three is refused by name**
  - RED: one loop, the shape of the suite's case 2, over `on`, `true`, `enforce`, `Report`, `"report"`; each exit 2 naming `provenance`, the value and `off, report or required`.
- [ ] **2.2.6 `check` prints the mode and refuses its hole**
  - RED: `check` on the well-formed section contains `provenance=report`; with the line deleted, exit 2 naming `provenance`.
- [ ] **2.2.7 The unknown-query refusal and the usage line name the new query**
  - RED: `release-policy.sh "$SB" colour` and a call with one argument both contain `provenance`.

#### 2.3 Permissions (by hand; no new test)

- [ ] **2.3.1 `attestations: write` on the release job, both sides.** The existing lint already holds every job's permissions equal to the policy file in both directions (cases 5 and 6 of `lint-workflow-policy_test.sh`), so a new test would repeat them. Shown instead on the real files: `catalogue-policy.yaml` `workflows.build.yml.jobs.release.permissions` gains the line, `scripts/lint-workflow-policy.sh .` red by name; `build.yml`'s release job gains it, green. One commit carrying both.

#### 2.4 The unpack (`scripts/unpack-provenance.sh store <bundles> <repository> <digest>...` and `scripts/unpack-provenance.sh subjects <repository> <digest>...`, suite `scripts/unpack-provenance_test.sh`)

bash, jq and openssl on an OCI layout directory; crane 0.22.1 for the registry (`crane pull --format oci`, `crane push`, measured 2026-11-13 to carry a hand-edited attestation manifest byte for byte). Nothing is signed here. The envelope is written in the compact form whose sha256 the transparency log recorded, and an envelope that does not hash to that value is refused (2.4.11), so what a verifier reads is what the log holds. `<bundles>` is the file the action leaves at its `bundle-path` (one bundle per line) or the attestation store's answer for a digest (`{"attestations": [{"bundle": ...}]}`, slice 2.4.22). `subjects` writes the lines the action's `subject-checksums` input takes, so that the script which later looks every subject up is the one that named them.

Retries: a `crane pull` or `crane push` that fails is tried again, up to three attempts, `UNPACK_PROVENANCE_RETRY_DELAY` seconds apart (default 10, 0 in the suite), the shape of `fetch-sboms.sh`. A refusal that comes from the bundle's content is final at once.

Fixtures under `scripts/testdata/provenance/`: `store.json`, the attestation store's answer for the platform manifest of 2.1's run (one statement naming both digests; public data: the statement, the certificate, the log entry); `bundle.jsonl`, the same bundle one per line (`jq -c '.attestations[].bundle'`, the action's file shape); `store-two.json`, the answer for the index, which that run attested twice; `chain.pem`, the two Sigstore certificates every cosign-written layer of the catalogue carries; `roots/`, Sigstore's public trust root as files (Fulcio's certificates, Rekor's and the certificate log's public keys), read by the real-tool suite only. The suite builds the attestation layout itself (one cosign-shaped layer with its chain annotation, the config with its `diff_ids`). The crane stub is a directory: `pull` copies the layout the test laid down for that tag and fails like crane on a missing one, `push` keeps the layout it was given and logs its arguments.

- [ ] **2.4.1 The provenance becomes one more layer, the envelope byte for byte** (tracer; FR-1)
  - RED: `store` for the index digest exits 0; the layout pushed to `sha256-<hex>.att` has one layer more than before; that layer has media type `application/vnd.dsse.envelope.v1+json` and the annotation `predicateType: https://slsa.dev/provenance/v1`; its blob is in the layout and its sha256 equals the `envelopeHash` in the bundle's log entry. Fails because the stub writes nothing.
  - GREEN: select the statement, write the compact envelope, append the layer, push.
- [ ] **2.4.2 The certificate and the log entry travel as cosign's annotations**
  - RED: `dev.sigstore.cosign/certificate` is a PEM whose DER equals the bundle's `verificationMaterial.certificate.rawBytes`; `dev.sigstore.cosign/bundle` equals `{"SignedEntryTimestamp", "Payload": {"body", "integratedTime", "logIndex", "logID"}}` built by the test from the bundle (numbers as numbers, the log id in hex); `logIndex` is the log entry's own, never `inclusionProof.logIndex` (a real bundle carries two different numbers there, 3851076632 and 3729172370 in the bundle of 2026-11-12, and the signed entry timestamp covers the entry's own; the test names the field by its full path so that test and code cannot agree on the wrong one); `dev.cosignproject.cosign/signature` is present and empty.
- [ ] **2.4.3 The chain annotation is copied from a layer cosign wrote and checked against the certificate**
  - RED: the new layer's `dev.sigstore.cosign/chain` equals the existing layer's.
  - GREEN: the first chain found on a layer of the same manifest; `openssl verify` of the provenance certificate against it at the log entry's integrated time (the certificate lives ten minutes). Kyverno 1.19.2 reads the intermediate from this annotation and from nowhere else (run 43404580566).
- [ ] **2.4.4 The layers that were there are untouched**
  - RED: every earlier layer's descriptor (digest, size, media type, annotations) is identical and in the same order; its blob is still in the layout.
- [ ] **2.4.5 The config lists the layers the way cosign writes it**
  - RED: the pushed manifest's config has `rootfs.diff_ids` equal to the layers' digests in order and one history entry per layer.
- [ ] **2.4.6 A second unpack replaces its own layer**
  - RED: a layout that already holds a provenance layer; after the unpack exactly one layer has the provenance predicate type and the other layers are as before (a re-run release never stacks statements; `cosign attest --replace` by type leaves this layer alone, measured).
- [ ] **2.4.7 One statement serves every digest it names**
  - RED: two digests in one call; two pushes, `sha256-<a>.att` and `sha256-<b>.att`, each carrying the same envelope blob.
- [ ] **2.4.8 Refused: no statement in the file names the digest.** Every refusal slice asserts the same three things: exit 1; one `::error::` line naming the digest and the reason; `crane push` never called.
- [ ] **2.4.9 Refused: the statement naming the digest is of another predicate type** (the message names the type found)
- [ ] **2.4.10 Refused: the log entry has no signed entry timestamp** (the second Rekor log issues none; the message says the attestation layout cannot carry such an entry)
- [ ] **2.4.11 Refused: the envelope does not hash to the value the log entry records** (one byte of the signature changed in the fixture)
- [ ] **2.4.12 Refused: more or fewer than one signature on the envelope** (the layer's envelope carries exactly one)
- [ ] **2.4.13 Refused: more or fewer than one log entry in the bundle** (the log-entry annotation carries exactly one; for a bundle with none the message adds the likely cause: the action signed with GitHub's own Sigstore instance, which keeps no transparency log, chosen when the event does not say the repository is public)
- [ ] **2.4.14 Refused: no attestation manifest beside the digest** (the stub's pull fails on every attempt; the message says the release's other attestations must exist first)
- [ ] **2.4.15 Refused: no layer of that manifest carries a chain**
- [ ] **2.4.16 Refused: the chain did not issue the provenance certificate** (a certificate authority made with openssl inside the test)
- [ ] **2.4.17 All or nothing across digests**
  - RED: two digests, the second refused (no manifest beside it); `crane push` is never called, not for the first either.
  - GREEN: every digest prepared and checked before the first push.
- [ ] **2.4.18 A push that fails three times fails the run naming the digest** (the stub's push exits 1 every time; exit 1, the digest and the number of attempts in the message, three push calls logged; the 2.26 shape)
- [ ] **2.4.19 Wrong usage is refused** (no mode or an unknown one, no digest, a digest without `sha256:`, a bundle file that is missing: exit 2 with the usage line)
- [ ] **2.4.20 Refused: the log entry is of another kind than `dsse`** (the fixture's entry body rewritten to `intoto`; the message names the kind found; the spike refused it by name)
- [ ] **2.4.21 Several statements naming one digest: the newest is stored**
  - RED: `store-two.json`; exit 0; one provenance layer, and its envelope is the one whose log entry is the later (integrated time, then log index). (A release run twice on one digest leaves two statements in the attestation store; either is valid, the choice must not depend on their order in the file.)
- [ ] **2.4.22 The attestation store's answer is read like the action's file** (the way back for a tagged digest whose provenance layer was lost: `gh api repos/<owner>/<repo>/attestations/<digest>` into a file, then `store`)
  - RED: `store` with `store.json` pushes the same layout, byte for byte, as with `bundle.jsonl`.
- [ ] **2.4.23 A digest named twice is stored once** (a single-platform image's index digest is its platform manifest's digest, `build.yml`'s `manifests` step)
  - RED: the same digest given twice; one pull and one push logged; one provenance layer.
- [ ] **2.4.24 A registry call that fails is tried again**
  - RED: the stub's push fails twice and then succeeds; exit 0; three push calls logged; one `::warning::` line per failed attempt naming the digest.
  - GREEN: the three attempts around `crane pull` and `crane push`, the delay from `UNPACK_PROVENANCE_RETRY_DELAY`.
- [ ] **2.4.25 A refusal from the bundle's content is not tried again** (the chain that did not issue the certificate, 2.4.16's case: one pull logged, no second attempt; a guard if 2.4.24's code already holds it)
- [ ] **2.4.26 `subjects` writes one line per digest in the shape the action reads**
  - RED: `subjects ghcr.io/o/r sha256:<a> sha256:<b>` prints exactly `<a> ghcr.io/o/r` and `<b> ghcr.io/o/r`: the bare hex, one space, the repository. (attest v4.2.1 `src/subject.ts`: a line without a space is skipped silently, a digest with its `sha256:` prefix is thrown out as invalid.)
- [ ] **2.4.27 `subjects` names a digest once and refuses what is not a digest** (the same digest twice prints one line; `sha256:xyz` or a bare tag: exit 2, nothing printed)
- [ ] **2.4.28 The real tools accept what the script writes** (suite `scripts/provenance-real_test.sh`; the pinned crane and cosign on `PATH`, the suite refusing to run on other versions)
  - RED: a throwaway registry (`crane registry serve` on 127.0.0.1, stopped by the suite's trap); a stand-in image pushed; beside the statement's subject digest an attestation manifest with one cosign-shaped layer carrying `chain.pem`, laid down by the suite; `store` against that registry exits 0; the manifest read back with `crane manifest` holds both layers; with the manifest copied to the stand-in image's own `.att` tag, cosign 2.6.5 `verify-attestation --type slsaprovenance1 --offline --check-claims=false` under the fixture certificate's identity and issuer, the trust root from `roots/` (`SIGSTORE_ROOT_FILE`, `SIGSTORE_REKOR_PUBLIC_KEY`, `SIGSTORE_CT_LOG_PUBLIC_KEY_FILE`), exits 0. The route measured by hand on 2026-11-12 with the spike's script (the data record's local table). `--check-claims=false` because the stand-in image is not the statement's subject; the subject is asserted from the decoded statement instead.
  - This slice is where a defect that the stand-ins share with the script shows: the wrong `logIndex`, a certificate PEM cosign cannot parse, a log entry annotation whose signed entry timestamp does not verify.

#### 2.5 The self-check (`scripts/check-provenance.sh verify <root> <image@digest>`, suite `scripts/check-provenance_test.sh`)

The core phase 3 builds its `report` and `require` modes on. ADR 0005's command: `cosign verify-attestation --type slsaprovenance1` under the declared issuer and the build workflow's identity (`verification.issuer`, read from the policy file the way `fetch-sboms.sh` reads it, and `verification.roles.releaser.identity`, the role by its name: `fetch-sboms.sh` selects roles by the attestation type they list, and the role's `attests` list names cosign's types, not the provenance), then the five expectations on the decoded statement. In this phase the five are the declared identity itself (builder), its three parts (repository, workflow path, ref) and GitHub's build type; phase 4.1 moves them into `verification.provenance`. cosign is stubbed: it logs its arguments and prints what the test laid down.

Retries: a cosign call that fails is tried again, up to three attempts, `CHECK_PROVENANCE_RETRY_DELAY` seconds apart (default 10, 0 in the suite), the shape of `fetch-sboms.sh` (Sigstore blips, the class measured on 2026-09-04). A statement that verified and misses an expectation is final at once. Phase 3's report over the supported set inherits these attempts from `verify`.

- [ ] **2.5.1 A digest whose provenance meets all five passes** (tracer)
  - RED: the stub prints one envelope whose statement carries the five expected values; exit 0; one line naming the digest; cosign was called with `verify-attestation`, `--type slsaprovenance1`, the policy file's issuer and releaser identity, and the reference. Fails because the stub script prints nothing.
- [ ] **2.5.2 cosign refusing three times fails the check naming the digest** (stub exit 1 every time; exit 1; the digest, the number of attempts and cosign's last message in the output; three calls logged)
- [ ] **2.5.3 Nothing verified never passes** (finding 2.4 of the 2026-09-09 review)
  - RED: the stub exits 0 printing nothing, and printing an envelope whose payload is null; both exit 1.
- [ ] **2.5.4 A builder identity other than the build workflow's fails naming the field, found and expected**
- [ ] **2.5.5 Another build type fails by name**
- [ ] **2.5.6 Another source repository fails by name**
- [ ] **2.5.7 Another workflow path fails by name**
- [ ] **2.5.8 Another ref fails by name** (`refs/heads/feature`, the case ADR 0005 measured as exit 1)
- [ ] **2.5.9 One admitted statement among several passes** (two envelopes, the first with another ref: exit 0; the policy rule admits on any statement that meets the conditions, and the self-check must not be stricter or laxer than the rule)
- [ ] **2.5.10 A policy file without the issuer or the releaser identity is refused** (exit 2 naming the missing key)
- [ ] **2.5.11 A cosign call that fails is tried again**
  - RED: the stub fails twice and then prints an envelope meeting all five; exit 0; three calls logged; one `::warning::` line per failed attempt.
  - GREEN: the three attempts around the cosign call, the delay from `CHECK_PROVENANCE_RETRY_DELAY`.
- [ ] **2.5.12 A missed expectation is not tried again** (2.5.8's case: one cosign call logged; a guard if 2.5.11's code already holds it)
- [ ] **2.5.13 What real cosign prints passes the self-check** (suite `scripts/provenance-real_test.sh`, on 2.4.28's registry)
  - RED: a sandbox policy file whose issuer and releaser identity are the fixture certificate's (the spike workflow at its pull-request ref, so the five expectations derived from that identity are the fixture statement's own values); on `PATH` a wrapper that hands every argument to the real cosign 2.6.5 and adds `--offline --check-claims=false --allow-insecure-registry` with the trust root from `roots/`; `check-provenance.sh verify <sandbox> <stand-in image@digest>` exits 0 naming the digest; with the sandbox identity's ref changed to `refs/heads/main`, exit 1 (cosign refuses the certificate's identity).
  - This slice is where the stub's picture of cosign's output is held against the real output: one JSON line per verified attestation, the statement base64 in `.payload`.

#### 2.6 The release steps (`build.yml` by hand; a workflow has no unit to test, so it is held by the lints and read on the first release)

- [ ] **2.6.1 The tools and the mode**: `scripts/install-tool.sh crane "${RUNNER_TEMP}/bin"` in the release job; the `meta` step writes `provenance=$(scripts/release-policy.sh . provenance)` to its outputs.
- [ ] **2.6.2 Three steps between "sign and attest" and the tags**, each under the release condition and `steps.meta.outputs.provenance != 'off'`:
  1. `uses: actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8 # v4.2.2` with `subject-checksums` (the file `scripts/unpack-provenance.sh subjects` wrote in the step before it: the index and every platform manifest) and `push-to-registry: false`;
  2. `scripts/unpack-provenance.sh store` with the action's `bundle-path`, the image and those digests;
  3. `scripts/check-provenance.sh verify . "${IMAGE}@<digest>"` for each of them.
  A failure in any of the three stops the job before the tags (no step after `relscan` may carry `always()`, held by `lint-release-steps.sh`).
- [ ] **2.6.3 The three new suites get their steps in `validate.yml`**; the real-tool suite's step installs the pinned crane and cosign first (`scripts/install-tool.sh`, the way the release job does).
- [ ] **2.6.4 No new lint rule for the order or the mode condition**: both are read in review and exercised live, the order by the first release, the `off` position by phase 6's flip.
- [ ] **2.6.5 The way out, written down** (`docs/user-manual.md`, Part III, by hand): what a release stopped at one of the three steps looks like (the digest pushed, signed and attested, no tag moved, the run red, the previous digest still served, the next scheduled rebuild trying again by itself); that `report` withholds such a release like `required` does (Req 2.9) and only `off` releases without provenance; the way out when the cause lasts: `release.provenance: off` through a pull request, the next release unchanged in everything else (2.30), and back the same way; the way back for a tagged digest whose provenance layer was lost (2.4.22).

#### 2.7 The action's pin (no code)

- [ ] **2.7.1** `test/renovate/managers.test.mjs` green with the new `uses:` line (full commit SHA and version comment); the pin is picked up by Renovate's github-actions manager, the three-day age rule applies through its `github-tags` datasource, automerge stays off.
- [ ] **2.7.2 A bump of the action is merged by hand and watched** (a comment at the `uses:` line and one paragraph beside 2.6.5's): the suites read a bundle recorded with v4.2.2, and every release step runs on main only, so a green pull request says nothing about what a new version emits (the bundle's media type, the number of log entries, the signed entry timestamp, the log it writes to). The rule: read the action's release notes for those four, merge, read the next release's three steps; a release stopped by the new version is answered by reverting the bump, never by loosening a refusal.

#### 2.8 REFACTOR (mandatory, its own commit, every suite green before and after)

- [ ] **2.8.1** Likely targets: the two new suites' shared helpers (the stub writers, the layout and envelope builders) folded where they repeat; the jq filter of the five expectations in one function, so that phases 3 and 4 call it and never copy it; refusal messages in one helper with one wording; the three-attempts loop once per script, not once per call; names; anything left of the RED stubs; `release-policy.sh`'s header comment and usage listing the mode.

### Verification (orchestrator)

- [ ] Every suite under `scripts/` green; `yamllint`, `scripts/lint-workflow-policy.sh .`, `scripts/lint-release-steps.sh`, `scripts/release-policy.sh . check` (printing `provenance=report`) and `node test/renovate/managers.test.mjs` green; validate's chain rehearsed locally after the refactor commit
- [ ] The pull request opens with a TL;DR; the owner merges (checkpoint)
- [ ] The first release on main after the merge, read through its check-run notes and the registry: the provenance layer on the index's and on each platform manifest's `.att` manifest; `cosign verify` and `cosign verify-attestation` for SPDX and OpenVEX still pass on that digest with cosign 2.6.5; no suffix-less `sha256-<hex>` tag in the repository; the tags applied after the self-check
- [ ] Kyverno 1.19.2 `kyverno apply` through the `Cosign` entry with the five expectations admits that released digest, index and platform manifest (in Actions, where Sigstore's trust root is reachable: one run of the spike workflow pointed at the released digest, read-only on the catalogue's package, the owner's go). cosign fetches the certificates between the signing certificate and the root itself, Kyverno reads them from the layer's chain annotation alone, so the self-check passing does not show this
- [ ] The first scheduled release and the first dispatched release after the merge, each read the same way as the first pushed one: only a `pull_request` event was measured, and the action signs with the public Sigstore instance only when the event says the repository is public (attest v4.2.1 `src/main.ts`)
- [ ] The next scheduled rescan green on that digest (the re-attestation by type leaves the provenance layer in place, the OpenVEX count stays one)

## Phase 3: coverage reported daily (task 18.4)

### Tasks

- [ ] **3.1 `check-provenance.sh` report mode**: on phase 2's `verify` (one digest against the declared identity and expectations), one line per supported digest, exit 0 on absent (Req 2.29), a failed verify already tried again by `verify` itself (phase 2, slice 2.5.11); suite first, one test per slice
- [ ] **3.2 Require mode**: absent or mismatched fails by name (for the successor); suite cases
- [ ] **3.3 Wiring**: the rescan runs what the declared mode asks: with `report`, report mode over the supported set, the status data and issue gaining the coverage line; with `off`, one line stating that provenance is off, nothing verified (2.30)

### Verification

- [ ] Suites green; a scheduled rescan after the merge carrying the coverage line

## Phase 4: the declaration and its renderings (task 18.5)

### Tasks

- [ ] **4.1 The declaration**: `verification.provenance` (expectations, predicate type) in `catalogue-policy.yaml`, read by `render-verification.sh` and, in place of phase 2's derivation from the build identity, by `check-provenance.sh`; refused by name when malformed
- [ ] **4.2 The rule**: the mode `required` renders the 2.28 rule as one more attestation of the existing `Cosign` entry (ADR 0005 as amended 2026-11-13); `report` and `off` render none; every shape in the suite and in the drift check
- [ ] **4.3 The consumer step**: the README and manual blocks gain the provenance step and the coverage sentence; BuildKit's inspect line kept, labelled supplementary; with the mode `off`, the sentence that releases attest none and no step
- [ ] **4.4 The smoke test**: `consumer-smoke.sh` targets a digest carrying provenance and fails on a null or unverified result (finding 2.4); with the mode `off` it runs no provenance step

### Verification

- [ ] `render-verification.sh --check`, `consumer-smoke_test.sh`, `lint-workflow-policy.sh .` green; an offline `kyverno apply` of the required shape rejecting a pre-track digest and admitting a post-track one (recorded for phase 6)

## Phase 5: the claim, stated (task 18.6)

### Tasks

- [ ] **5.1 `SECURITY.md`**: the SLSA section (level claimed, v1.2, covered digests, the verification step, L2 from the successor's epoch); the statement follows the declared mode (`off`: Build L1, no SLSA provenance attested while it stands)
- [ ] **5.2 `docs/concepts.md`**: the "L2-ish" sentence replaced by the measured state; the trust-boundary GitHub row names the provenance service, option D as the L3 path, option A as the other-forge seam
- [ ] **5.3 `docs/user-manual.md`** and design.md's Security Considerations

### Verification

- [ ] No sentence claims Build L2 for this repository's digests; render drift check green

## Phase 6: the evidence (task 18.7)

### Tasks

- [ ] **6.1 The reads**: the first release after phase 2 and the first rescan after phase 3, with run ids; the offline must-reject and must-admit from phase 4; the `off` flip: one release with the mode `off` through a normal pull request and back the same day, read for every other attestation present, no provenance attestation and the rescan's line
- [ ] **6.2 The ledger and the LOG**: rows 2.27, 2.29 and 2.30 exercised, 9.19 measured present, 2.28 left to 12.1; the LOG entry; group 18 ticked; this track closed

### Verification

- [ ] `scripts/lint-live-evidence.sh .` and `scripts/lint-log-anchors.sh all .` green

## Final verification

- [ ] Every FR's acceptance criteria met
- [ ] Every touched suite and real-repository lint green
- [ ] Documentation updated (README, manual, SECURITY.md, concepts.md)
- [ ] The successor's 12.1 bullet carries the switch-on
