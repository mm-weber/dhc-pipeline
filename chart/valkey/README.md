# valkey (hardened adaptation)

Upstream chart `valkey` **0.11.0** from https://valkey-io.github.io/valkey-helm,
consumed unmodified (Req 4.1). All deltas live in
[`config/values-hardened.yaml`](config/values-hardened.yaml) and are applied
with `-f`; no upstream template is edited, forked, or patched.

Render / install:

```bash
helm template dhc-valkey valkey \
  --repo https://valkey-io.github.io/valkey-helm --version 0.11.0 \
  -f chart/valkey/config/values-hardened.yaml
```

**Version note:** this is the valkey project's own chart and 0.11.0 ships
appVersion `9.1.1` — the exact version `image/valkey/` builds. No version skew
to reason about, unlike [`chart/grafana`](../grafana/README.md).

## Deviations from upstream defaults

| Change | Why | Requirement |
|---|---|---|
| `image` → digest-pinned `ghcr.io/mm-weber/dhc/valkey:9.1.1-alpine3.23-compat@sha256:…` | Deploy the hardened catalogue build, not upstream `docker.io/valkey/valkey`; digest-pinned. The chart composes `registry/repository:tag` and strips a trailing `@sha` for its version label, so the digest rides on `tag` | Req 4.2 |
| `podSecurityContext.runAsUser/runAsGroup/fsGroup: 65532` | The chart defaults to **1000**, an account no catalogue image has | Req 4.3 |
| `podSecurityContext.runAsNonRoot: true` | Not a chart default at pod level, and `policies/require-nonroot.yaml` reads it exactly there. The container context already sets it; the policy gate does not look at the container | Req 4.3, Req 4.6 |
| `securityContext.runAsUser/runAsGroup: 65532` | Same UID move for the containers. The rest of the container-level restricted set (drop-ALL caps, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `runAsNonRoot: true`) is already upstream default and merges in — this chart arrives harder-by-default than grafana's. `seccompProfile: RuntimeDefault` is upstream default too, but at **pod** level only, and covers both containers from there | Req 4.3 |
| `readinessProbe.enabled: true` | Readiness is opt-in upstream (the container had none before 0.11.0), so the Service would route to a pod that has not answered yet. The handler is the chart's `valkey-cli ping` exec | Req 4.3 |
| `dataStorage.enabled: false` | Stated, not inherited — see below | Req 4.4 |

## Persistence off by default (Req 4.4)

`dataStorage.enabled: false` is also the upstream default; it is written down
anyway, for two reasons.

It **is** the writable-path answer. Under `readOnlyRootFilesystem: true` the one
path this workload writes — `/data`, holding the generated `valkey.conf`, the
init log, and any RDB/AOF — is backed by the chart's `valkey-data` volume, which
falls back to an `emptyDir` exactly when persistence is off. Turning persistence
on does not add a writable path; it changes what backs the same one.

And it is a decision, not an absence. A catalogue image ships the deployable
default, and durable storage is a deployment-time choice: a PVC binds the pod to
a node's storage class, changes the failure and upgrade story, and outlives
`helm uninstall` unless `keepPvc` says otherwise. A cache that survives eviction
is worth opting into deliberately. Stating the value means an upstream default
flip shows up as a diff here rather than as a silently provisioned volume.

| Path | Backed by |
|---|---|
| `/data` (generated config, init log, RDB/AOF) | chart `valkey-data` emptyDir (persistence off) |
| `/scripts` | init-scripts ConfigMap, read-only |

## Compat-variant decision (Req 4.5)

**This chart deploys the `-compat` variant, and that is the one place the
hardened baseline gives ground.** Measured, not assumed:

The chart renders an **unconditional** init container (`templates/deploy_valkey.yaml`)
whose image is the *same* `valkey.image` value as the main container, running:

```yaml
command: [ "/scripts/init.sh" ]
```

`init.sh` (`templates/init_config.yaml`) opens `#!/bin/sh` and calls `date`,
`tee`, `mkdir`, `rm` and `cat` to generate `/data/conf/valkey.conf` — the file
the main container is then started with (`valkey-server /data/conf/valkey.conf`).
`image/valkey/` ships `alpine-baselayout-data`, `ca-certificates-bundle` and
`libssl3`: no shell, no coreutils. The init container fails to exec, and the pod
never starts.

No value reaches it. `extraInitContainers` **appends** to the built-in one
rather than replacing it, and there is no flag to disable it. Overriding the
main container's `command` would not help either — the config it needs would
still be missing.

So the decision is `image/valkey-compat/`: byte-identical to the runtime
definition plus one package, `busybox` — `/bin/sh` and every applet the script
calls, in one binary of symlinks. Not `coreutils`, not `bash`: nothing in the
script needs more than busybox provides.

What it costs, stated plainly: the deployed valkey has a shell, so this
workload gives up the "no interactive shell for an attacker" property that the
rest of the catalogue keeps, and `busybox` joins its CVE surface (scanned and
triaged like any other package — `triage/accepted-risk/valkey-compat.yaml` when
it comes to that). The runtime image remains the published default and the one
to deploy anywhere this chart is not involved, per the taxonomy rule in
[`docs/concepts.md`](../../docs/concepts.md): *deploy the least capable variant
that works.*

The alternative — a fork of the chart with the init container removed — was
rejected because Req 4.1 is the stronger constraint: consuming upstream
unmodified is the property this repo is demonstrating, and a fork trades a
recurring merge burden for a one-package image.

## e2e probe (Req 5.5)

`probeValkey` (`test/e2e/probes_test.go`) runs a Job that writes a key and
asserts that reading it back returns what was written — a server that answers
`PING` but stores nothing fails it. The Job takes its image from the live
Deployment, so it can only ever exercise the image actually running, and it uses
`sh -c` so that `test` decides the exit code rather than `valkey-cli`'s exit
status for an error reply. The shell is free here for the same reason it is
required above.
