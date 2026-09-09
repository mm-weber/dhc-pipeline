# cert-manager (hardened adaptation)

Upstream chart `cert-manager` from https://charts.jetstack.io, at the version
[`chart.yaml`](chart.yaml) pins (Renovate moves it, so it is not quoted here),
consumed unmodified (Req 4.1). All deltas live in
[`config/values-hardened.yaml`](config/values-hardened.yaml) and are applied
with `-f`; no upstream template is edited, forked, or patched.

Render / install:

```bash
helm template dhc-cert-manager cert-manager \
  --repo https://charts.jetstack.io \
  --version "$(yq '.upstream.version' chart/cert-manager/chart.yaml)" \
  -f chart/cert-manager/config/values-hardened.yaml
```

(`scripts/render-chart.sh chart/cert-manager` is the same command, the way CI runs it.)

**Upstream authenticity:** the three images come from
`image/cert-manager-{controller,webhook,cainjector}/`, whose source is
declared `signed-tag` (an annotated tag GitHub verifies), checked before any
bump is written and daily by the rescan (Req 3.8, 3.10).

## Deviations from upstream defaults

| Change | Why | Requirement |
|---|---|---|
| `image` / `webhook.image` / `cainjector.image` → digest-pinned `ghcr.io/mm-weber/dhc/cert-manager-*:1.21.x-alpine3.23@sha256:…` | Deploy the hardened catalogue builds, not upstream `quay.io/jetstack` images; digest-pinned so the reference is immutable. Kept current by Renovate's chart-pin manager (task 8.7); the image pins may run a patch ahead of the chart-template pin above | Req 4.2 |
| `securityContext.runAsUser` / `runAsGroup` / `fsGroup: 65532` on all three components | The chart defaults `runAsNonRoot: true` but pins no UID; our runtime images run as 65532, so set it explicitly | Req 4.3 |
| `startupapicheck.enabled: false` | It runs a post-install **Job** from `cert-manager-startupapicheck`, an image this catalogue does not build. Disabling the optional API-readiness check is preferable to pulling a non-catalogue image, which the registry policy forbids | Req 4.2, Req 4.6 |

## Already hardened upstream — no override needed

cert-manager's chart is unusually well-hardened out of the box; these Req 4.3
settings are upstream **defaults**, so `values-hardened.yaml` does not touch them
(verified in the rendered manifests):

- `readOnlyRootFilesystem: true`
- `allowPrivilegeEscalation: false`
- `capabilities.drop: [ALL]`
- `seccompProfile.type: RuntimeDefault`

## Notes

- **acmesolver is not overridden.** `cert-manager-acmesolver` is spawned by the
  controller at runtime to solve ACME HTTP01 challenges — it is not a workload in
  the rendered chart, so it does not appear in the policy-gated manifests and no
  catalogue image exists for it. If an ACME issuer is ever used, build that
  definition and set `acmesolver.image` accordingly.
- **No compat variant needed** (Req 4.5): the cert-manager binaries are static
  and assume no shell/coreutils, so the runtime images work as-is.
- No writable-path `emptyDir` mounts are needed: with `readOnlyRootFilesystem`,
  cert-manager writes only to its API-served state, not the container filesystem.
