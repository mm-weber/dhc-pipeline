# hardened-app (owned chart)

The catalogue's **owned** Helm chart (not an upstream adaptation): a minimal
Deployment + Service for the supply-chain lab's Go HTTP service. It is the
deploy path for the phase-6 e2e HTTP-200 probe.

Hardening is baked into the defaults (no overlay needed — we own it):

- Image digest-pinned to `ghcr.io/mm-weber/dhc/hardened-app` (Req 4.2).
  Renovate's chart-pin manager tracks tag and digest against ghcr.io
  (task 8.7); a bump PR runs the e2e upgrade path (Req 5.6).
- Restricted PSS (Req 4.3): `runAsNonRoot`, UID/GID **65532**, RO rootfs,
  drop-ALL caps, `allowPrivilegeEscalation: false`, seccomp RuntimeDefault.
- `/healthz` readiness + liveness probes on `:8080`. No writable paths — the
  service is stateless and logs to stdout, so RO rootfs needs no `emptyDir`.

```bash
helm template hardened-app chart/hardened-app        # render
helm install  hardened-app chart/hardened-app        # deploy (needs the private image)
```

> Authored fresh rather than carried from the lab: the lab's chart wasn't
> reachable from the build container, and since we own the app a clean
> already-hardened chart is preferable. Swap in the lab chart if the lab→catalogue
> narrative calls for it — the gate treats any `Chart.yaml` chart the same.

The chart gate (`.github/workflows/chart.yml`) renders this alongside the
adapted charts and runs the Kyverno policies over the manifests (Req 4.6), plus
`ct lint` for owned charts.
