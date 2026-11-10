# Track specification: A revocation, its advisory and the runbook, the drill digest withdrawn, live

## Overview

**Track ID:** revocation_20261105
**Type:** chore
**Priority:** high (the live program; the last three drill rows)
**Created:** 2026-11-05
**Author:** the owner, drafted by the agent
**Spec source:** `.specs/dhc-catalogue-mvp/tasks.md` task 16.12 (task group 16, the live drills), its text amended by this track's pull request; Req 9.4 (catalogue advisories as repository security advisories), 9.5 (every revoked digest recorded), 9.7 (a tag referencing a recorded digest fails the daily run), 7.11 (the ledger); register row M14 (revoking a digest); `docs/revocation-runbook.md`

### Description

A revocation is the decision that a published digest must not be pulled any more (register row M14). The record, `triage/revocations.yaml`, drives the mechanics: validate checks each entry's shape (Req 9.6, exercised by 16.15), the daily rescan's posture step fails by name while any catalogue tag still references a recorded digest (Req 9.7), the status issue lists every entry, and the advisory is a GitHub repository security advisory on this repository (Req 9.4). The record is empty and no advisory has been published, so rows 9.4, 9.5 and 9.7 wait for this drill. This track records the drill definition's current digest as revoked, with reason "drill", while its three tags still reference it, reads the posture step refusing by name, executes the runbook's withdrawal as written, and records the advisory.

### The mechanism, as read on 2026-11-05

- The record admits two shapes: `replaced` (image, digest, reason, replacement digest, advisory URL, date) and `withdrawn` (replacement `none`, `withdrawal` delete-version or tombstone, advisory URL, date). There is no shape for an entry whose move has not happened yet.
- The runbook's Move A publishes the replacement through the release path, and the release that produces it moves the definition's three tags in the same run, so the revoked digest is untagged before an entry naming the replacement can exist; Move A never leaves a tag on a recorded digest. Move B2 (a tombstone) is not built. Move B1 deletes the package version: every tag on the digest goes with it, and the digest itself; GitHub refuses it for a public version past 5,000 downloads.
- So the one entry that can be recorded while the tags still reference the digest is a withdrawal, which the task text names as well ("the version deleted"): the drill takes Move B1. The advisory is drafted first, since the entry's `advisory` field must carry its URL.
- `scripts/check-revocations.sh` reads the record against the run's enumeration and prints one line per referencing tag, `::error::<image>:<tag> references revoked digest <digest> <index or platform> ...`, a summary `revocations: N recorded, M referenced by a catalogue tag`, exit 1 when any tag references. The posture step runs last and regardless of what failed above it (D1); the status issue lists the entries.
- The drill digest today: sha256:cf147012fad2c088997e4142b5c21abc386a716501f6440efb05efb0d0a8792f, the tags 0-alpine3.23, 0.1-alpine3.23 and 0.1.0-alpine3.23 all on it, the digest the switches drill published on 2026-11-01 and the private report of 16.14 named.
- The next scheduled rebuild republishes a withdrawn definition: under on-change the comparator finds no published package set to equal, so drill-app returns on a new digest with its tags until the definition is retired (task 16.16) or deactivated.
- By the owner's rule of 2026-11-03 the runs are dispatched; each a release of attestations (register row M17). The pipeline's token cannot list or delete package versions (403); the deletion is the owner's, in the package's web page or with a token that may delete packages.

## Functional requirements (EARS)

The subject names follow design.md: the owner, the Repository (its maintainer), the Scan Pipeline, the CI Pipeline.

### FR-1: The advisory drafted (Req 9.4)

THE owner SHALL open a draft repository security advisory on this repository titled `Drill 16.12: <subject>`, the affected package `ghcr.io/mm-weber/dhc/drill-app`, the affected version the digest above, the patched version "withdrawn", the description the reason, and SHALL give the maintainer its URL.

**Acceptance criteria:**

- [ ] The advisory's URL (GHSA id), its state draft

### FR-2: The entry recorded (Req 9.5, 9.6)

THE Repository SHALL add one `withdrawn` entry to `triage/revocations.yaml` in a pull request (image, digest, reason naming the drill, `replacement: none`, `withdrawal: delete-version`, the advisory URL, the date), validate's schema check green, and the owner SHALL merge it while the three tags still reference the digest.

**Acceptance criteria:**

- [ ] The pull request's number and squash; validate green at the step "revocation record (Req 9.6)"

### FR-3: The tag reported (Req 9.7)

WHEN the rescan runs with the entry merged and the tags in place THE Scan Pipeline SHALL fail the posture step naming each referencing tag with the digest and the advisory, fail the run, keep every other daily assertion and the status issue running (D1), and list the entry in the status issue.

**Acceptance criteria:**

- [ ] The dispatched run's id, the three lines, the summary line `1 recorded, 3 referenced`, the status issue's revocation entry

### FR-4: The withdrawal executed (register row M14)

THE owner SHALL delete the package version carrying the digest (Move B1) and tell the maintainer the time, and WHEN the rescan runs again THE Scan Pipeline SHALL report no referencing tag, the posture step green, the entry listed; THE owner SHALL publish the advisory once the entry has merged, or keep it a draft, and the ledger SHALL say which.

**Acceptance criteria:**

- [ ] The deletion's time; the second dispatched run's id and its summary line `1 recorded, 0 referenced`; the advisory's final state

### FR-5: The evidence (Req 7.11)

THE Repository SHALL flip ledger rows 9.4, 9.5 and 9.7 to `exercised` (inducers `owner`, `pull request`, `pull request`), add the task table row for 16.12, add the LOG entry `## 2026-11-05: the drill digest withdrawn, the posture step red by name, the runbook executed as written (task 16.12)` dated by the event, tick task 16.12, move `tasks/todo.md` to 16.16 and close this track, in one evidence pull request.

**Acceptance criteria:**

- [ ] `scripts/lint-live-evidence.sh .` green with three more exercised rows (150); `scripts/lint-log-anchors.sh all .` green; the tick `[done <date>, #nnn; conductor track revocation_20261105]`; `conductor/tracks.md` lists the track under Completed; 16.16 next in `tasks/todo.md`

## Scope

### In scope

- The owner's draft advisory (FR-1), one entry pull request (FR-2), two dispatched rescans (FR-3, FR-4), the owner's deletion (FR-4), one evidence pull request (FR-5)
- The amendment of task 16.12's text in this pull request

### Out of scope

- Move A and Move B2: the first cannot show Req 9.7 (the release moves the tags), the second needs a tombstone definition that does not exist
- A third record shape for an entry recorded before its move: a finding of this drill, a follow-up candidate, not a change here
- The retirement of the definition (task 16.16), which follows this track at once

## Dependencies

| Dependency | Type | Status | Notes |
| --- | --- | --- | --- |
| The owner may delete the package version | permission | the owner's (the pipeline's token cannot: 403) | the package's web page, or `gh api -X DELETE /user/packages/container/dhc%2Fdrill-app/versions/<id>` with a token that may delete packages |
| The advisory's URL before the entry | order | FR-1 before FR-2 | the entry's `advisory` field is required by the schema |
| The rescan's dispatch | mechanism | available | each a release of attestations (M17) |

## Risks

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The deleted digest is the one 16.13 and 16.14 cite | certain | its bytes and attestations leave the registry; the records stay as written | The LOG entry says so; the records describe what was, and the deletion is the runbook's one deliberate exception to "nothing is deleted" |
| The next scheduled rebuild republishes drill-app on a new digest | likely, if a scheduled build falls before the retirement | the definition returns with its open HIGH, the entry's digest stays withdrawn | Named in the entry as a finding; task 16.16 follows this track at once |
| A published drill advisory on the public advisory list | the owner's call | none beyond the list carrying a drill, named in its title | The runbook says publish when the entry merges; a draft kept instead is recorded as such |

## Open questions (the owner's calls)

- [ ] The advisory published when the entry merges, or kept a draft (drafted: published; the runbook's word, and the title names the drill)
- [ ] The deletion in the package's web page or by API (drafted: the web page; the version is the one carrying the three tags)

## References

- `docs/revocation-runbook.md`; `triage/revocations.yaml`, `triage/revocations.schema.yaml`; `scripts/check-revocations.sh`; `.github/workflows/rescan.yml` (the posture step); `docs/CONVENTIONS.md` register row M14; `.specs/dhc-catalogue-mvp/requirements.md` Req 9.4 to 9.7, 7.11; `tasks.md` 16.12, 16.16
- LOG 2026-11-01 (the digest's release), LOG 2026-11-05 (the private report naming it)
