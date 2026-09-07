# Revocation runbook (Req 9.5 to 9.7)

A revocation is the decision that a published digest must not be pulled any
more: a compromised input, a build that shipped what it should not have, a
published status that was wrong in a way a replacement cannot express. The
record, `triage/revocations.yaml`, drives the mechanics, which is why this
page is short: the daily rescan fails by name while any catalogue tag still
references a recorded digest, the status issue lists every entry, and
validate refuses an entry that does not fit the schema.

## What GHCR can and cannot do

Measured for the cluster D review (2026-08-25) and unchanged since:

- **There is no tag deletion.** The packages API deletes packages and package
  versions only; a version is the digest with every tag on it. A tag is
  therefore removed either by deleting the whole version or by pushing
  another manifest under the tag, which re-points it.
- **Deleting a public version is refused past 5,000 downloads.**
- **A digest no catalogue tag references is frozen** (Req 2.11): pullable by
  digest, not rescanned, not re-attested, its last attestations left as they
  were. Frozen is the state a revoked digest should be in the day after.

## Move A: replacement through the release path

The normal case, and the only one that needs no hand on the registry.

1. Fix the definition in a pull request: an upstream bump, a fetch-phase
   module bump, a dropped package. The scan gate scans it like any change.
2. Merge. The release arm pushes the new digest, scans it, signs and attests
   it, and moves the definition's three tags to it (Req 2.7 to 2.9). The
   revoked digest is now untagged: frozen.
3. Draft the advisory (below), then add the entry with shape `replaced`,
   naming the revoked digest, the reason, the replacement digest, the
   advisory link and the date, and merge it. Publish the advisory.
4. The next rescan asserts no tag references the revoked digest and lists
   the entry in the status issue.

## Move B: withdrawal, nothing replaces it

When no fixed upstream exists and the definition cannot ship at all. Record
`replacement: none` and the move taken in `withdrawal`.

- **B1, delete the package version** (`withdrawal: delete-version`). Find the
  version id with `gh api /user/packages/container/<name>/versions`, then
  `gh api -X DELETE /user/packages/container/<name>/versions/<id>`. Every tag
  on that digest goes with it, and so does the digest: consumers pinned to it
  by digest break. That is the one deliberate exception to "nothing is
  deleted" (SECURITY.md, retention), and GitHub refuses it for a public
  version past 5,000 downloads.
- **B2, park the tags on a tombstone** (`withdrawal: tombstone`, `tombstone:`
  the manifest digest). A tombstone is a minimal image whose only content is
  a `REVOKED` file naming the advisory, pushed under each of the digest's
  tags so a pull by tag returns something that cannot run instead of the
  revoked bytes; the revoked digest itself stays pullable and frozen. Not
  built: the rescan's verification invariant (Req 2.24) applies the policy to
  every tag-referenced digest, and a tombstone signed by anything but the
  releaser identity is reported every day as a rejected tag. Parking a tag
  therefore needs a signed tombstone, which means a tombstone definition
  released through `build.yml`. Until one exists, B1 or Move A; if B2 is ever
  needed, that definition is the first step and the entry records its digest.

## Then, whichever move

- **The advisory** is a GitHub repository security advisory on this
  repository (Security tab, Advisories, New draft advisory): the affected
  package is the catalogue repository (`ghcr.io/mm-weber/dhc/<name>`), the
  affected version the revoked digest, the patched version the replacement
  digest or "withdrawn", the description the reason. Its URL goes into the
  entry; publish it when the entry merges. GHSA is the catalogue's advisory
  channel (Req 9.4, SECURITY.md).
- **The entry** is one item of `triage/revocations.yaml`; the schema
  (`triage/revocations.schema.yaml`) decides its shape in validate (Req 9.6),
  and nothing is ever removed from the list.
- **The LOG** gets a dated entry saying what was found, what was decided and
  what moved, in that order.
- **The daily rescan** reports any catalogue tag still referencing the
  digest as a failure by name (Req 9.7) and lists the entry in the status
  issue, so a revocation that was only half executed does not stay quiet.
