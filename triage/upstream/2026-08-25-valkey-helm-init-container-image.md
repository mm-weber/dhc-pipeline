# Let the init container run from its own image (`initContainer.image`, defaulting to the main image)

Target: `valkey-io/valkey-helm` · Status: **filed** as [#247](https://github.com/valkey-io/valkey-helm/issues/247) on 2026-09-07 · Drafted 2026-08-25, re-checked 2026-09-06

The issue body is this file from `## Summary` down, unmodified. The facts
reproduce with
[`checks/valkey-helm-init-container.sh 0.11.0 chart/valkey/config/values-hardened.yaml`](checks/valkey-helm-init-container.sh).
The number is recorded in `chart/valkey/chart.yaml` (`compat.issue`) and
`../LOG.md`.

---

## Summary

Both workloads (`templates/deploy_valkey.yaml` and `templates/statefulset.yaml`)
always render an init container from the main container's image. It runs
`/scripts/init.sh`, a `/bin/sh` script that needs nothing beyond a shell and
standard utilities such as `cat`, `tee`, `mkdir` and `sha256sum`; it never
calls valkey itself. An image without a shell therefore cannot start the pod:
the init container fails on exec, and no value replaces or disables it
(`extraInitContainers` only appends more). Seen on chart 0.11.0 and 0.12.0.
#163 already took the shell out of the probes so a distroless main image
can be used; the init container is the one place that still needs one.

This rules out shell-less valkey images, which are the natural hardened build
because the server itself needs no shell. We work around it with a second
image that adds busybox, which gives up the no-shell property for exactly this
chart.

## Ask

An `initContainer.image` value, the shape `metrics.exporter.image` already
has, used by the init container in place of `include "valkey.image"` and
**defaulting to the main image**, so existing installs are unchanged. Users
of a shell-less image can then point it at any small image with a shell. The
separation #14 introduced stays as it is (the server container never sees
the plain-text passwords); only the image that renders the file changes.

Optional and separable: `initContainer.enabled` (default `true`) for users who
provide `/data/conf/valkey.conf` some other way.

Happy to send a PR for whichever shape you prefer.
