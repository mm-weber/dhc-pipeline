# `/oss/release/` version alias serves different bytes than the per-build artifact, and its amd64 `.sha256` is stale

## Summary

Each release tarball appears at two paths on `dl.grafana.com`:

| | |
|---|---|
| per-build | `…/grafana/release/<ver>/grafana_<ver>_<build-id>_linux_<arch>.tar.gz` |
| version alias | `…/oss/release/grafana-<ver>.linux-<arch>.tar.gz` |

For **13.0.4** these are not the same bytes, and on **amd64** the alias also
contradicts its own published checksum.

| | amd64 | arm64 |
|---|---|---|
| per-build `.sha256` | `cd8c8b31b0482f48f98018030c142919dab6debbe81f747f3521af6f6a6b4490` | `bcf8b9fbfac00bece5bccdda44512b9f7ba81d3105db1a255e0efd37a2fbf6df` |
| alias `.sha256` | `cd8c8b31…` *(same as per-build)* | `591ac184f85e17455d3251f617cdadd9403811add395c5245bf81d658d49bb1e` |
| alias **actual bytes** | `54eceec74891dd49f992502eab506e0554c82903317fb50d82246946e46fe7ae` | `591ac184…` |

Two distinct issues:

1. **amd64: the alias serves content that its own `.sha256` disowns.** Anyone
   verifying that download against the checksum published beside it gets a hard
   failure.
2. **Both arches: the alias is a different build from the per-build artifact of
   the same release.** On arm64 the alias and its sidecar agree with each other,
   but neither matches `…/grafana/release/13.0.4/…`.

13.1.1 splits the same way — per-build
`e47443214da0de041ffb29633d0977ce31ba7c8c569f09974ef5294a8ce32f08` vs alias
`0c07116968aea49768af8babd3c3f162d19012655a1a220cd7a9d97efe91da6c` on amd64 —
so this is not specific to 13.0.4.

## Reproduction

```console
$ curl -sSL https://dl.grafana.com/oss/release/grafana-13.0.4.linux-amd64.tar.gz | sha256sum
54eceec74891dd49f992502eab506e0554c82903317fb50d82246946e46fe7ae  -

$ curl -sSL https://dl.grafana.com/oss/release/grafana-13.0.4.linux-amd64.tar.gz.sha256
cd8c8b31b0482f48f98018030c142919dab6debbe81f747f3521af6f6a6b4490

$ curl -sSL https://dl.grafana.com/grafana/release/13.0.4/grafana_13.0.4_29751385932_linux_amd64.tar.gz.sha256
cd8c8b31b0482f48f98018030c142919dab6debbe81f747f3521af6f6a6b4490
```

Response headers for the alias object:

```
last-modified: Wed, 22 Jul 2026 05:36:05 GMT
etag: "597107c3e6188cba8f7342dd0999f42c"
content-length: 337697955
x-goog-stored-content-length: 337697955
x-goog-metageneration: 1
```

v13.0.4 was published 2026-07-21 12:25 UTC as part of a coordinated release
alongside v13.1.1, v12.4.6 and v12.3.9. The alias object was last modified the
following day.

## The alias also does not serve stable bytes

Pinned to the alias' published digest, the *same URL* verified, then failed
within one hour, then verified again:

| Time (UTC) | Result |
|---|---|
| 2026-07-26 21:06 | ✅ digest matched |
| 2026-07-26 21:54 | ❌ digest mismatched |
| 2026-07-26 22:3x | ✅ digest matched |

We cannot tell from outside whether that is edges holding different copies, an
in-progress re-sync, or transport corruption on our side. It is included
because it is consistent with the alias being rewritten, and because it is what
made the problem intermittent rather than obvious. The digests in the tables
above were all measured from a workstation with plain `curl`, not in CI.

## Why this matters downstream

We build container images that pin upstream artifacts by SHA-256 and verify at
fetch time. Our pins were taken from the **per-build** `.sha256` and are still
correct for that artifact — but the definition downloaded from the **alias**,
and the two silently diverged after publication. A build that had been
reproducible stopped being so, with no version change to explain it.

More generally:

- **Verifying consumers break** on a version that previously worked.
- **Non-verifying consumers silently receive a different build** than the
  release advertised.
- **Two consumers pinning "13.0.4" can end up with different bytes**, depending
  only on which documented path they used.

We deliberately did not re-pin to the alias' current digest, since that would
mean shipping bytes that fail the checksum published beside them. We moved to
the per-build URL instead.

## Questions

1. **Is the version alias intended to be immutable?** If so, the amd64 object
   for 13.0.4 has drifted and its sidecar is stale. If not, saying so in the
   download docs would help — it is the path most tooling has historically
   pinned.
2. **Which build is authoritative for 13.0.4** — the one at
   `/grafana/release/13.0.4/…` (`cd8c8b31…` / `bcf8b9fb…`), or the one currently
   behind the alias (`54eceec7…` / `591ac184…`)?
3. **Were other releases affected?** 13.1.1 shows the same split, so a sweep
   comparing alias digests against per-build digests across recent releases
   would establish the blast radius.
4. **Do all CDN edges serve identical bytes** for a given alias object?

## Suggestion

- **Regenerate the alias sidecars**, so that at minimum each alias object agrees
  with the checksum published next to it.
- **Point the alias at the same bytes as the per-build artifact**, or document
  it as a moving pointer and recommend the per-build URL for anything that pins.
- **Write artifact and sidecar in one operation**, so they cannot drift apart if
  a replacement does happen.

Happy to re-run any of these checks. The digest comparisons reproduce with the
commands above; the intermittency, by nature, does not.
