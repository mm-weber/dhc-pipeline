# grafana (hardened adaptation)

Upstream chart `grafana` **10.5.15** from https://grafana.github.io/helm-charts,
consumed unmodified (Req 4.1). All deltas live in
[`config/values-hardened.yaml`](config/values-hardened.yaml) and are applied
with `-f`; no upstream template is edited, forked, or patched.

Render / install:

```bash
helm template dhc-grafana grafana \
  --repo https://grafana.github.io/helm-charts --version 10.5.15 \
  -f chart/grafana/config/values-hardened.yaml
```

**Version note:** the grafana Helm chart lags the app. The newest chart (10.5.15)
ships appVersion `12.3.1`, and no chart targets grafana 13.x. We pin the latest
chart for its templates and override the image to our hardened grafana **13.x**
build (the exact pin lives in `config/values-hardened.yaml`, kept current by
Renovate's chart-pin manager). Grafana's `grafana.ini` and `grafana server` CLI
are stable across 12→13, so the templates deploy 13.x unchanged; the phase-6
e2e HTTP-health probe validates the running deployment.

## Deviations from upstream defaults

| Change | Why | Requirement |
|---|---|---|
| `image` → digest-pinned `ghcr.io/mm-weber/dhc/grafana:13.1.3-alpine3.23@sha256:…` (registry/repository/tag; the digest rides on `tag`) | Deploy the hardened catalogue build, not upstream `docker.io/grafana/grafana`; digest-pinned. The chart's bare-hex `sha:` field is deliberately unused: Renovate's chart-pin manager (task 8.7) writes digests as `sha256:<hex>`, and the chart strips a trailing `@sha…` from the tag for its version label (`_helpers.tpl`), so the tag carries the digest the same way valkey's does | Req 4.2 |
| `securityContext.runAsUser/runAsGroup/fsGroup: 65532` | The chart defaults to grafana's UID **472**; our runtime image runs as 65532 | Req 4.3 |
| `containerSecurityContext.readOnlyRootFilesystem: true` | The chart omits it; the rest (drop-ALL caps, `allowPrivilegeEscalation: false`, seccomp RuntimeDefault) are chart defaults and merge in | Req 4.3 |
| `initChownData.enabled: false` | It chowns the data dir via a **busybox shell** init container; with an emptyDir data volume + `fsGroup`, the kubelet sets ownership, so it's unnecessary — and our images ship no shell (see compat note) | Req 4.5, Req 4.6 |
| `testFramework.enabled: false` | Renders a Helm-test Pod from a non-catalogue `bats` image; disabled so the policy gate only sees catalogue images | Req 4.6 |
| `extraVolumes`/`extraVolumeMounts`: emptyDir at `/tmp` and `/var/log/grafana` | Writable paths grafana needs under `readOnlyRootFilesystem`; from the definition's writable-path inventory | Req 4.4 |

## Writable-path inventory → volumes (Req 4.4)

Under `readOnlyRootFilesystem: true`, every path the runtime writes to is backed
by a volume (verified in the rendered manifests):

| Path | Backed by |
|---|---|
| `/var/lib/grafana` (data, plugins) | chart `storage` emptyDir (persistence off) |
| `/var/lib/grafana-search` (search index) | chart `search` emptyDir |
| `/tmp` | overlay emptyDir |
| `/var/log/grafana` (file logger) | overlay emptyDir |
| `/etc/grafana/grafana.ini`, `provisioning/` | read-only config mounts / baked-in dirs — grafana reads, never writes |

## Compat-variant decision (Req 4.5)

**No `-compat` variant is needed.** The upstream chart's shell dependencies are
confined to *optional helper containers* — `initChownData` (busybox chown),
`testFramework` (bats), and `downloadDashboards` (curl/sh) — all of which this
overlay disables or leaves off. The **main grafana container runs our shell-less
image's entrypoint (`grafana server …`) directly**: the chart does not override
`command`/`args`, so it does not wrap grafana in `/run.sh` or a shell the way a
naive adaptation might assume. A shell-bearing `-compat` grafana image would only
be warranted if we needed those helpers (e.g. sidecar-provisioned dashboards),
which the hardened baseline does not.

Verified: `kyverno apply` over the rendered manifests passes 3/3 (digest,
registry, nonroot), with no non-catalogue images and no shell init containers.
