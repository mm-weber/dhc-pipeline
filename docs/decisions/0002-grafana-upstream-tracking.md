# ADR 0002: Grafana upstream tracking — keep the vendor tarball, move the datasource to GitHub

Date: 2026-07-26 · Status: **accepted** · Requirements: Req 3.1, Req 3.2

## Context

Req 3.2 says that when an upstream release matches a definition's version
policy, Renovate SHALL open a pull request updating pinned ref, checksum, and
derived tags. For `image/grafana/image.yaml` it opened nothing, and had never
opened anything.

The cause is archetype, not configuration. The catalogue holds two kinds of
image definition:

- **compile-from-source** (cert-manager ×3, hardened-app, valkey) — pinned by
  `url: git+https://github.com/<owner>/<repo>.git#vX.Y.Z`. The source manager
  captures owner/repo and version from that one line.
- **tarball-repackage** (grafana) — pinned by
  `url: https://dl.grafana.com/oss/release/grafana-13.0.4.linux-${target.arch}.tar.gz`,
  a prebuilt release extracted onto a minimal base with no compilation.

Neither custom manager matches the second shape. The Dependency Dashboard
listed only `dhi.io/build` for grafana — its build layer, not its contents. So
the pin sat at 13.0.4 while 13.1.1 shipped, invisibly. This is doubly bad
because grafana carries every open CVE in the catalogue: the one image whose
version we most need to see move was the one image nothing was watching.

The trigger for revisiting this was the obvious question — why not just point
at `https://github.com/grafana/grafana/releases` like everything else?

## Evidence

**GitHub publishes no linux tarball for grafana.** All 12 assets on the
v13.0.4 and v13.1.1 releases are `.deb` and `.rpm`:

```
grafana_13.0.4_29751385932_linux_amd64.deb   (266 MB)
grafana_13.0.4_29751385932_linux_amd64.rpm   (212 MB)
grafana-enterprise_13.0.4_..._linux_arm64.deb
…
```

Three blockers: the format is wrong (consuming a `.deb` means shipping `dpkg`
in the build or hand-unpacking with `ar`/`cpio`, against the point of a minimal
image); the filenames embed an opaque build id (`29751385932`) that cannot be
templated from a version variable; and enterprise variants are mixed in.

**The `archive/refs/tags/*.tar.gz` URL is a source archive, not a release
build.** Downloaded and inspected: 47 MB containing `go.mod`, `package.json`,
`yarn.lock`, `Makefile`, no `vendor/`, and no compiled anything — the only
`bin/grafana` is a bash wrapper script. Building it means running
`nx exec -- webpack --config webpack.prod.ts` under Node `>= 22 <25` in
addition to the Go build: a second language ecosystem and a second supply chain
to harden. Separately, GitHub's auto-generated archives are not byte-stable —
the January 2023 compression change silently altered every checksum and broke
Homebrew, Bazel and the Go checksum DB. Uploaded release assets are immutable;
these are not. Our definition pins a SHA-256 and verifies it in-pipeline, so
pinning against a regenerable artifact is precisely the fragility we design
out.

**Grafana releases across supported branches on one day.** v13.1.1, v13.0.4,
v12.4.6 and v12.3.9 all published 2026-07-21 — the signature of a coordinated
security release. 13.0.4 is therefore the newest patch on the 13.0.x line; the
only upgrade available is the 13.1.1 minor.

## Decision

**Keep `dl.grafana.com` as the download source. Track versions from GitHub
Releases.** Where an artifact is fetched from and where its version is
discovered are independent concerns, and conflating them is what made this look
like a dead end.

A third custom manager reads the version out of the tarball url, names the
dependency `grafana/grafana`, and resolves it against the `github-releases`
datasource, with `extractVersionTemplate` bridging upstream's `v` prefix to our
unprefixed pin.

`github-releases` rather than `github-tags` is load-bearing: it keeps grafana
out of the existing git-source `packageRules`, whose `postUpgradeTask` resolves
a commit sha grafana has none of, and out of the Req 3.5 patch automerge.
`scripts/refresh-grafana.sh` is the repackage counterpart to
`refresh-definition.sh` — it re-pins both per-arch SHA-256s from the `.sha256`
sidecar upstream publishes beside each tarball (the same source the current
pins came from) and regenerates every version-derived field.

Rejected: **converting grafana to compile-from-source.** It would make Renovate
work with zero new config — the existing `github-tags` manager already matches
`git+https://…#vX.Y.Z` — and would move grafana into the archetype that can
patch vendored dependencies ahead of upstream, which is the one thing it
currently cannot do. It was rejected on two grounds. The build cost is a full
Node/yarn/nx/webpack toolchain we would then own and harden. More importantly,
grafana is the catalogue's only tarball-repackage image: it is the worked
example of "you cannot fix this yourself, so you triage it instead," which is
what motivates the whole VEX and CVE-triage half of the pipeline (Req 6).
Converting it would leave every image from-source and delete the contrast.
Real hardened-image catalogues make this call per image on exactly these
grounds — tractable builds get built, monster frontends get repackaged and
triaged.

## Consequences

- Req 3.2 now holds for every image in the catalogue, not five of six.
- Renovate will open a **13.0.4 → 13.1.1** PR on its next run. That is a minor
  bump with chart/compat implications, and it is the first real test of whether
  a version bump clears any of the open CVE issues — an empirical question the
  rescan cron answers, not a judgement call.
- Grafana bumps are never automerged. A repackage bump swaps a binary artifact
  we did not build and re-pins its checksum, so it is always reviewed, even on
  a patch. From-source patches keep automerging (Req 3.5).
- Two refresh scripts now exist, split by archetype. They are deliberately not
  merged: one resolves a git tag to a commit sha, the other fetches a release
  artifact's checksum, and grafana has no git ref for the first to work from.
  A third repackage image would reuse `refresh-grafana.sh` only if it also
  published a `.sha256` sidecar; otherwise the fallback path hashes the tarball.
- `dl.grafana.com` is blocked by the devcontainer firewall, so the checksum
  fetch cannot be exercised locally. `REFRESH_GRAFANA_SHA256_AMD64/_ARM64`
  stub it for the unit tests; the live path first runs in GitHub Actions, which
  is the authoritative environment anyway (Req 8.1).
- `dates.release` is not regenerated — it is not derivable from the tarball url
  and would need a GitHub API call. It goes stale on a bump and is corrected by
  the reviewer. Worth automating if a second repackage image appears.

## Amendment, 2026-07-26: out-of-band security builds

Switching the datasource to GitHub Releases surfaced a release shape the
original decision did not account for. Grafana ships out-of-band fixes as
**semver build metadata** — `v13.0.1+security-01`, `v12.4.3+security-02`,
`v12.3.6+security-04`, `v12.2.8+security-04`, `v11.6.14+security-04`, five in a
single batch on the feed. The decision above stands; three implementation
defects had to be fixed for it to hold.

**They were invisible.** Semver ignores build metadata for precedence, so
`13.0.1+security-01` does not rank above `13.0.1`. Measured against renovate's
own versioning module rather than inferred from the docs:

```
semver          13.0.1+security-01 > 13.0.1 ? false
semver-coerced  13.0.1+security-01 > 13.0.1 ? false
loose           13.0.1+security-01 > 13.0.1 ? false
docker          isValid('13.0.1+security-01') = false
```

Compounding it, the original `extractVersionTemplate` anchored at the patch
digit and discarded those releases before any comparison happened. Net effect:
Renovate would have reported us up to date straight through a security
release — the precise failure this catalogue exists to prevent, in the one
image carrying every open CVE.

Fixed with an explicit `versioningTemplate` mapping the security counter onto a
fourth release component. The capture group must be `build`, not `revision`:
renovate's regex versioner only appends `revision` when `build` is also present
(`modules/versioning/regex/index.js`). That is not obvious from the
documentation, so the test asserts ordering against the module itself — a
renovate upgrade that changes the semantics fails CI instead of silently
restoring the bug.

**They were unrepresentable.** `+` is illegal in an OCI reference, confirmed
against the local daemon:

```
$ docker tag <id> probe:13.0.4+security-01-alpine3.23
error parsing reference: ... is not a valid repository/tag: invalid reference format
```

The full release tag now carries the build separator as `_` (the
eclipse-temurin convention) while every other field keeps the upstream version
verbatim, and `lint-pins.sh` validates the whole `tags:` block against the OCI
tag grammar so this class of error fails review rather than the registry push.

**They broke the refresh.** `+` is an ERE metacharacter, so `esc()` had to
escape it. More subtly, the global version pass rewrote a url Renovate had
already bumped, and because the old version is a *prefix* of the new one it
doubled the suffix (`grafana-13.0.4+security-01+security-01.linux-…`). The url
line is now excluded from that pass — Renovate owns it. This one was caught by
running the script against the real definition; the fixture had passed on an
unanchored assertion that matched the checksum-provenance comment instead of
the url. Both are now anchored on the `url:` key.

**They download from the same templatable path — checked, not assumed.** The
amendment first shipped on the opposite conclusion. Grafana's download page
advertises security builds under a longer per-build url that embeds an opaque
CI run id:

```
https://dl.grafana.com/grafana/release/13.0.1+security-01/grafana_13.0.1+security-01_25720641773_linux_amd64.tar.gz
                                                                                     ^^^^^^^^^^^
```

That id is not derivable from the version — the same class of token as the
`29751385932` in GitHub's `.deb` asset names — so the reasonable inference was
that a security bump could not be automated at all, and the refresh task was
built to refuse one and hand off to a human. The inference was wrong. The
advertised url is not the only one that resolves; the plain templatable form
does too:

```
https://dl.grafana.com/oss/release/grafana-13.0.1+security-01.linux-amd64.tar.gz   → 200
```

So security builds need no special download handling, the refusal path was
deleted, and nothing in the manager or the refresh task has to know that the
build-id form exists. What remains is purely a *version-shape* problem —
ordering, extraction, and the tag separator — which is what the rest of this
amendment covers.

The cost of not checking would have been a permanent manual step for exactly
the release class that most needs to be automatic. Worth generalising: an
upstream's documented download url is what it advertises, not necessarily the
only one it serves.

The two follow-up checks came back clean as well: for a security build the
`arm64` tarball and the `.sha256` sidecar both resolve. The whole per-arch
flow — url, sidecar checksum, both architectures — is therefore confirmed
against upstream, and an out-of-band security release needs no special handling
anywhere in the pipeline.

Nothing about that verification is load-bearing in the code: `fetch_sha` still
falls back to hashing the tarball when a sidecar is missing, still rejects
anything that is not 64 hex characters, and the definition still re-verifies
the checksum in-pipeline. A missing artifact turns the bump PR red rather than
producing a bad pin. The checks matter because they replaced three inferences
with three measurements — and the one inference that went unmeasured longest
(that the advertised url was the only one) was the one that was wrong.

## Amendment, 2026-08-07: the build id needs two sources, and 13.1.2 has none

Moving the pin to the per-build url (`f5d75b4`) made an opaque CI run id part of
every bump, and `refresh-grafana.sh` recovered it from one place: the GitHub
release assets. **That single source is not reliable**, which only became
visible when a bump needed it.

### Evidence

Asset counts on `grafana/grafana` releases, read from the API:

| Published | Tag | GitHub assets | build id in apt |
|---|---|---|---|
| 2026-06-23 | v13.0.3 | **0** | ✅ `28022233908` |
| 2026-07-21 | v13.1.1 | 12 | ✅ `29761037902` |
| 2026-08-04 | v12.4.7 | 12 | ✅ `30647961040` |
| 2026-08-04 | **v13.0.5** | **0** | ❌ |
| 2026-08-04 | **v13.1.2** | **0** | ❌ |
| 2026-08-07 | v13.0.6 | 12 | ❌ (indexed later) |
| 2026-08-07 | **v13.1.3** | **0** | ❌ |

Two independent gaps, in opposite directions. **v13.0.3 is the case against
GitHub-only**: it published with zero assets and is nevertheless a complete
release — `apt.grafana.com` carries its build id, and
`…/grafana/release/13.0.3/grafana_13.0.3_28022233908_linux_amd64.tar.gz`
returns 200. The old resolver could not have bumped to it. **v13.0.6 is the
case against apt-only**: 12 assets on GitHub at 03:06Z, still absent from an
apt index generated at 04:36Z.

`apt.grafana.com`'s `Packages` index names the `.deb` verbatim in `Filename:`,
which is also the only field carrying the version unmangled — apt rewrites
`13.0.1+security-01` to `13.0.1-01` in `Version:`. `rpm.grafana.com` was checked
too and is not usable: its filenames carry no build id.

### Decision

**Resolve the build id from both indexes and cross-check.** Whichever has it
wins; where both have it they must agree. A disagreement stops the refresh
rather than picking one — two independent indexes naming different builds for
one version is a supply-chain signal, and a checksum pinned against the wrong
build verifies against nothing. Resolution stays REQUIRED: no fallback to the
`/oss/release/` alias, whose objects are rewritten after release.

**And make `dl.grafana.com` the authority on what is fetchable.** An index and
an object store are different pipelines: a build id can be indexed for a build
the store does not serve, or for one arch and not the other. Both per-arch
tarballs are now confirmed served — a ranged single-byte GET, which costs the
same as a HEAD and exercises the path the build will take — *before* any field
is written. A miss names the host and leaves the definition untouched. Without
it the failure surfaced as a 350MB download that 404s, reported as a checksum
complaint about an artifact that was never there, against a file already half
rewritten.

### The split, stated deliberately

GitHub keeps exactly one job, and it is not an artifact job:

> **GitHub Releases answers "does version X exist?"** — a tag list. Complete:
> every release has an entry, including the six that published with no assets.
>
> **`dl.grafana.com` answers "can we have it, and what is its checksum?"** —
> the binary, the sidecar, and the existence check. Nothing is pinned that it
> does not serve.
>
> **`apt.grafana.com` answers "which build is version X?"** — the build id,
> corroborated by GitHub's assets when it has them.

This was reviewed against moving discovery to a Grafana-owned index too, and
rejected on measurement. `dl.grafana.com` publishes no index at all — every
listing path 404s, it is a pure object store. `apt.grafana.com` is missing four
of the last seven releases (13.0.5, 13.0.6, 13.1.2, 13.1.3) and mangles
`13.0.1+security-01` to `13.0.1-01` in `Version:`, so the pin and the datasource
would no longer share a version scheme. `rpm.grafana.com` has the same gaps and
carries no build id at all.

The inversion is the point: **GitHub is the more complete source for discovery,
and the unreliable one for artifacts.** Sourcing discovery from apt would trade
a bump that fails loudly for one that never opens — and a release apt has not
indexed yet is invisible, which is precisely the failure the amendment above
was written to prevent, on the one image carrying every open CVE. A version we
learn about but cannot yet build is the strictly safer error: it is visible.

### Consequences

- **13.1.2 is still not consumable, and that is upstream's state, not a gap in
  the tooling.** Three days after release it has no GitHub assets and no apt
  entry, so no public index carries its build id. Verified live: the resolver
  bumps 13.1.1, 13.0.3 and 13.0.6 and refuses 13.1.2 by name. The same holds
  for v13.0.5 and v13.1.3. Grafana's 13.x line has now published three releases
  this way while 12.x completed normally in the same batches — worth a
  `triage/upstream/` report, and worth knowing that **13.1.2 carries the fixes
  for #30 (CRITICAL), #28 and #39**, so the wait is not free.
- No artifact, checksum or existence claim comes from GitHub any more, which
  also removes `GITHUB_TOKEN` from the critical path for public releases. What
  remains is the version list, and a wrong answer there is a bump that does not
  open — not a bad pin.
- `dl.grafana.com` is **not** blocked by the devcontainer firewall — it is on
  the allowlist (`init-firewall.sh:118`), along with `apt.grafana.com` and
  `rpm.grafana.com`. The Consequences note above saying otherwise is stale; the
  live checksum path can be exercised locally after all. `grafana.com` itself
  is blocked, which is why the download page is not a usable source.
- Tests stub both indexes through `REFRESH_GRAFANA_APT_URL` and
  `REFRESH_GRAFANA_GH_URL` (`file://` fixtures), so the resolution logic — the
  two gaps, the conflict, the enterprise near-miss, the security-build shape —
  is covered without network.

## Amendment, 2026-08-11: the versions API is the third source

The 2026-08-07 amendment closed with 13.1.2 unresolvable by either index and
called the download page "not a usable source" because `grafana.com` was
firewall-blocked. Both halves of that aged badly within a week:

- 13.1.2's build id (`30900078095`) was read off the download page **by hand**
  and fed in via `REFRESH_GRAFANA_BUILD_ID` — the artifact had existed on
  `dl.grafana.com` the whole time. Only our indexes were blind.
- 13.1.3 repeated the shape exactly: released 2026-08-07, zero GitHub assets,
  apt still frozen at 13.1.1 four days later — while
  `grafana.com/api/grafana/versions/13.1.3` named build `31135815010`, and
  `dl.grafana.com` served both OSS arches under it, sidecars included.

`grafana.com` is on the firewall allowlist as of 2026-08-11, which removed the
only reason the source was off the table. And it is better than the page we
almost scraped: the versions API returns structured JSON — `packages[]` with
per-arch/os urls carrying the build id in the same
`grafana_<ver>_<id>_linux_<arch>.tar.gz` filename `dl.grafana.com` serves,
plus a `channels.stable` flag. No HTML parsing.

So `refresh-grafana.sh` now consults three sources — the versions API,
apt.grafana.com, the GitHub release assets — and requires every source that
answered to agree. Any disagreement refuses, naming all three. The API is not
*trusted* more than the indexes despite being more current: the id it yields
is only an address, the pin is still the per-arch sha256 from the
`dl.grafana.com` sidecar, and the existence check still gates before anything
is written. A wrong or hijacked API answer therefore produces either a refusal
(conflict, or artifact not served) or a pin against whatever `dl.grafana.com`
actually serves at that address — the same trust anchor as before.

The API also returns per-package `sha256` values. Deliberately **not** used as
the pin source: the sidecar sits beside the object it describes, written by
the same pipeline seconds apart, which is the property the alias incident made
us value. Cross-checking API sha against sidecar sha would be a fourth
consistency signal; deferred until a real incident argues for it.

Stub for tests and offline work: `REFRESH_GRAFANA_API_URL` (`file://`
fixtures), alongside the existing apt/GH/dl seams.

## Amendment, 2026-08-25: the API-sha cross-check is adopted (deferral reversed)

The 2026-08-11 amendment closed with the API-sha-versus-sidecar comparison
"deferred until a real incident argues for it". The 2026-08-21
production-readiness review is the argument (finding F2, checkpoint
placement decision): grafana's authenticity anchor is a checksum served by
the same origin as the artifact, and the versions API is the one
independent-enough origin already in the resolution path. The comparison
costs one field read from a response the refresh already fetches.

Adopted as review F2's checkpoint 1 (Req 3.8): before any field is written,
the per-architecture sha256 from the versions API must equal the
`dl.grafana.com` sidecar's value; a disagreement refuses the bump naming
both values. Checkpoint 2 repeats the comparison at PR time in
`verify-arch-pins.sh` against the bytes actually served (Req 3.9), and
checkpoint 3 repeats it daily in the rescan's invariants (Req 3.10). One
comparison function, three call sites. The pin source is unchanged: the
sidecar remains what is written, the API remains a witness. Measured basis,
2026-08-21: across 13.0.4, 13.0.6, 13.1.1, 13.1.2 and 13.1.3 on amd64,
arm64, armv6 and armv7, API and sidecar agree in all 20 cases.

The grafana authenticity class this witnesses is declared per definition as
`# authenticity: cross-origin-checksum` (Req 1.10); the `.deb` route via the
signed apt index stays the documented switch for a cryptographic bar, not
taken while the apt index measurably lags releases.
