# `/oss/release/` tarballs are overwritten ~20h after publication — is that intended?

## Summary

For the 2026-07-21 release batch, every `…/oss/release/grafana-<ver>.linux-<arch>.tar.gz`
object was **rewritten roughly twenty hours after the release went out**. The
new bytes differ from what the same URL served on release day, so a consumer
that pinned the digest published at release time breaks days later, with no
version change to explain it.

Everything Grafana publishes is internally consistent — each object matches the
`.sha256` beside it, and always has. The question is whether `/oss/release/` is
meant to be immutable, because tooling widely treats it that way.

## Evidence

### Object creation times

| | per-build object written | `/oss/release/` object written |
|---|---|---|
| 13.0.4 amd64 | 2026-07-21 09:56:03Z | **2026-07-22 05:36:05Z** |
| 13.0.4 arm64 | 2026-07-21 09:56:14Z | **2026-07-22 05:36:34Z** |
| 13.1.1 amd64 | 2026-07-21 08:53:04Z | **2026-07-22 05:42:05Z** |
| 13.1.1 arm64 | 2026-07-21 08:53:16Z | **2026-07-22 05:42:36Z** |

(from `last-modified` / `x-goog-generation`.) All four alias objects were
written within six minutes of each other, so this looks like a batch step
rather than a one-off correction.

### The same URL served different bytes before and after

We build container images from these tarballs, pinning the SHA-256 and
verifying at fetch time. The pin was taken from
`grafana-13.0.4.linux-<arch>.tar.gz.sha256`.

**2026-07-21 20:57Z** — a release build fetched both arches from `/oss/release/`
and verified them. SLSA provenance recorded:

| | uri | sha256 |
|---|---|---|
| amd64 | `…/oss/release/grafana-13.0.4.linux-amd64.tar.gz` | `cd8c8b31b0482f48f98018030c142919dab6debbe81f747f3521af6f6a6b4490` |
| arm64 | `…/oss/release/grafana-13.0.4.linux-arm64.tar.gz` | `bcf8b9fbfac00bece5bccdda44512b9f7ba81d3105db1a255e0efd37a2fbf6df` |

**2026-07-26** — same URL, same pin, same definition; two runs on separate
runners, both failing:

```
/src/grafana.tar.gz: FAILED
sha256sum: WARNING: 1 of 1 computed checksums did NOT match
```

**Today** — that URL serves
`54eceec74891dd49f992502eab506e0554c82903317fb50d82246946e46fe7ae`
(three verified downloads, byte count matching `Content-Length`), and its
`.sha256` agrees. The digest we recorded on release day is now only available
at the per-build path.

### The two paths are different artifacts, and stay that way

| | `/oss/release/` | `/grafana/release/<ver>/` | size delta |
|---|---|---|---|
| 13.0.4 amd64 | `54eceec7…` 337 697 955 B | `cd8c8b31…` 337 694 041 B | +3 914 |
| 13.0.4 arm64 | `591ac184…` 321 125 583 B | `bcf8b9fb…` 321 121 554 B | +4 029 |
| 13.1.1 amd64 | `0c071169…` 363 257 098 B | `e4744321…` 363 255 678 B | +1 420 |
| 13.1.1 arm64 | `8403dc0b…` 345 122 382 B | `28ef74a3…` 345 128 051 B | −5 669 |

Each side matches its own sidecar. The deltas are ~0.001% and change sign
between arches, which reads like repackaging (tar metadata, gzip framing)
rather than different content — but a consumer verifying a digest cannot tell
the difference, and neither can we from outside.

## Reproduction

```console
# what the two paths serve today
$ curl -fsSL https://dl.grafana.com/oss/release/grafana-13.0.4.linux-amd64.tar.gz.sha256
54eceec74891dd49f992502eab506e0554c82903317fb50d82246946e46fe7ae
$ curl -fsSL https://dl.grafana.com/grafana/release/13.0.4/grafana_13.0.4_29751385932_linux_amd64.tar.gz.sha256
cd8c8b31b0482f48f98018030c142919dab6debbe81f747f3521af6f6a6b4490

# when each object was written
$ curl -sSI https://dl.grafana.com/oss/release/grafana-13.0.4.linux-amd64.tar.gz \
    | grep -iE 'last-modified|content-length|x-goog-generation'
last-modified: Wed, 22 Jul 2026 05:36:05 GMT
content-length: 337697955
x-goog-generation: 1784698564953130

$ curl -sSI https://dl.grafana.com/grafana/release/13.0.4/grafana_13.0.4_29751385932_linux_amd64.tar.gz \
    | grep -iE 'last-modified|content-length|x-goog-generation'
last-modified: Tue, 21 Jul 2026 09:56:03 GMT
content-length: 337694041
x-goog-generation: 1784627763097984
```

Verify content by downloading to a file, not by piping: the objects are
~320–360 MiB, and `curl … | sha256sum` will hash a truncated body and print a
plausible, wrong digest. Check the byte count against `Content-Length` first.

## Why this matters downstream

- **Verifying consumers break** on a release that previously worked, with
  nothing in the version to explain it.
- **Non-verifying consumers silently receive different bytes** than the ones
  the release shipped with.
- **A reproducible build stops reproducing.** Ours did: the 13.0.4 image we
  published on 2026-07-21 was built from bytes that no longer exist at the URL
  it fetched them from.

We did not re-pin to the new digest, since that would mean tracking a path that
can move again. We moved to
`…/grafana/release/<ver>/grafana_<ver>_<build-id>_linux_<arch>.tar.gz`, which is
scoped to a single build and whose sidecar is written in the same job.

## Questions

1. **Is `/oss/release/<ver>` intended to be immutable?** If yes, these rewrites
   are a bug. If no, saying so in the download docs would help — it is the path
   most tooling has historically pinned.
2. **What is the 2026-07-22 batch step?** If it is a repackaging or promotion
   pass, could it run *before* the release is announced, so the first published
   bytes are the final ones?
3. **Should pinning consumers prefer the per-build URL?** It is what the
   download page emits and it is scoped to one build. If that is the
   recommendation, stating it in the install docs would settle it for everyone.
4. **Do all CDN edges serve the current generation?** On 2026-07-26 one build
   failed against a pin that five neighbouring builds accepted, and a sidecar
   read the same day returned the pre-rewrite value. Both are consistent with an
   edge still holding the old generation. We have not tested this per-edge and
   may be wrong about it.

## Suggestion

- **Treat published release objects as immutable**, or document `/oss/release/`
  as a mutable convenience path and point pinning consumers at the per-build URL.
- If a rewrite must happen, **publish the final bytes first** rather than
  replacing them after announcement.

Happy to re-run any of this, or to supply the full build logs and provenance for
the runs cited. The host-side scripts that produced these tables are in
[`checks/`](checks/).
