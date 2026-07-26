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

**They are not downloadable from the templatable path.** This was left open
above as unverifiable from the devcontainer; the operator resolved it from the
host. Upstream publishes security builds under a different path *and* embeds an
opaque CI run id in the filename:

```
regular   https://dl.grafana.com/oss/release/grafana-13.0.4.linux-amd64.tar.gz
security  https://dl.grafana.com/grafana/release/13.0.1+security-01/grafana_13.0.1+security-01_25720641773_linux_amd64.tar.gz
                                                                                              ^^^^^^^^^^^
```

That build id is not derivable from the version — the same class of token as
the `29751385932` in GitHub's `.deb` asset names. For a security build neither
the download url nor its checksum can be constructed, so the automatic refresh
is impossible in principle, not merely unimplemented.

`refresh-grafana.sh` therefore **refuses** a security target and prints the url
shape, the build-id problem, and the exact fields to hand-write — the
alternative being a confusing 404 from a fabricated url. A security build is a
**hand fix-forward (Req 6.5)**, and that is now a documented path rather than a
surprise.

Two consequences worth stating, because the naive version of this fix would
reintroduce the blindness the ADR set out to remove:

- The manager matches **both** url shapes. A definition sitting on a
  hand-pinned security build would otherwise stop matching and drop out of
  tracking — silent again, in exactly the state where visibility matters most.
  Reading the version out of the path segment keeps the next release visible.
- The refresh **canonicalises** the url back onto `/oss/release/` whenever the
  target is a regular release, so a build-id url never outlives the security
  build it belongs to. Grafana's real pattern — `v13.0.1+security-01` followed
  by `v13.0.2` — makes that the common exit path, and it is covered by a test.

Still unverified: whether
`/oss/release/grafana-13.0.1+security-01.linux-amd64.tar.gz` *also* resolves.
If it does, refuse-and-guide could be replaced by full automation. One
`curl -I` from a host with egress settles it; the firewall blocks
`dl.grafana.com` from the devcontainer.
