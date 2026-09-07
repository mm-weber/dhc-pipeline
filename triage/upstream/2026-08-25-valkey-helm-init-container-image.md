# The init container is rendered unconditionally from the main image: an `initContainer.image` value, defaulting to it, would let a shell-less runtime image run this chart

**Target repo:** `valkey-io/valkey-helm`
**Drafted:** 2026-08-25, measured again 2026-09-06 on chart 0.11.0 and 0.12.0
**Filed:** not yet. The issue body is this file from `## Summary` down,
unmodified. Measurements reproduce with
[`checks/valkey-helm-init-container.sh 0.11.0 chart/valkey/config/values-hardened.yaml`](checks/valkey-helm-init-container.sh).
When filed, the issue number goes into `chart/valkey/chart.yaml` (`compat.issue`)
and `../LOG.md`.

---

## Summary

Both workload templates (`templates/deploy_valkey.yaml` for the standalone
Deployment, `templates/statefulset.yaml` for the replica StatefulSet) render
an init container for every install, from the same image as the main
container, running `/scripts/init.sh`, a `/bin/sh` script. An image built without a shell, which is how a hardened
valkey image is naturally built (the server needs no shell), cannot start the
pod: the init container fails to exec, and nothing in `values.yaml` replaces
or disables it. The exporter already has an image of its own
(`metrics.image`); the ask is the same shape for the init container, defaulting
to the main image so nothing changes for anyone who does not set it.

## Measured

Chart 0.11.0 (appVersion 9.1.1) and 0.12.0 (appVersion 9.1.2), pulled from
`https://valkey-io.github.io/valkey-helm`; the numbers are the same in both.

| Fact | Where | Value |
|---|---|---|
| The init container sits inside no control block of its own | `templates/deploy_valkey.yaml` line 53 and `templates/statefulset.yaml` line 71, the `initContainers:` lines | the only open block at each is the file's own switch (`if not .Values.replica.enabled`, `if .Values.replica.enabled`), which renders the workload itself: whichever workload renders, the init container renders with it |
| Its image is the main container's | `image: {{ include "valkey.image" . }}` in both templates, the same helper the main container uses | one image for both |
| Its command | `command: [ "/scripts/init.sh" ]` | a script, not a binary |
| The script's interpreter | `templates/init_config.yaml`, first line | `#!/bin/sh` |
| Utilities the script calls | `templates/init_config.yaml` | `tee`, `cat`, `rm`, `mkdir`, `date` |
| A value that replaces or disables the init container | `values.yaml` | none; `extraInitContainers` appends after it, `templates/deploy_valkey.yaml` line 100 |
| A container in this chart with its own image value | `values.yaml` | the exporter: `metrics.image.repository` and `metrics.image.tag` |

Rendered with this catalogue's values (`helm template` with the overlay named
above), the init container and the main container carry the identical
`ghcr.io/mm-weber/dhc/valkey:9.1.2-alpine3.23-compat@sha256:…` reference.

## What this costs a consumer of a shell-less image

The catalogue's runtime valkey image ships `alpine-baselayout-data`,
`ca-certificates-bundle` and `libssl3` beside the server: no shell, no
coreutils, by design. With this chart that image cannot be deployed at all:
the init container cannot exec `/bin/sh`, the pod never leaves `Init:Error`.
Overriding the main container's `command` does not help, because the
configuration the server is started with (`/data/conf/valkey.conf`) is what
the init script generates.

The workaround in use is a second image variant, byte-identical to the
runtime image plus `busybox`, deployed only where this chart is involved. It
works, and it gives up the "no shell for an attacker" property for exactly
this workload, which is the property the hardened image exists to keep.

## Ask

1. An `initContainer.image` value (repository, tag, pull policy, the shape
   `metrics.image` already has), rendered by the init container in place of
   `include "valkey.image"`, and **defaulting to the main image** when unset,
   so no existing install changes. A consumer then points it at any small
   image with a shell (the chart's own `busybox`-class choice) and keeps the
   main container shell-less.
2. Second, and separable: an `initContainer.enabled` switch, default `true`,
   for consumers who provide `/data/conf/valkey.conf` by other means (a
   ConfigMap, an operator). The first ask is enough for this catalogue; the
   second is the general form.

We are happy to send a pull request for either shape if the maintainers say
which they prefer.
