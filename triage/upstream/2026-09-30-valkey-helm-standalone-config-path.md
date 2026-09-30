# valkey: standalone Deployment cannot start on `main` since #234 (`init.sh` writes `/valkey-conf`, only the StatefulSet mounts it)

Target: `valkey-io/valkey-helm` · Status: **draft**, approved for filing by the owner on 2026-09-30 · Drafted 2026-09-30, adversarially reviewed the same day

The issue body is this file from `## Summary` down, unmodified. The render
facts reproduce with
[`checks/valkey-helm-standalone-conf-path.sh 8d30231 0.12.0`](checks/valkey-helm-standalone-conf-path.sh)
(a render of the chart at that commit and of the released chart; with a
third argument it also runs the rendered `init.sh` in a container the way
the pod runs it). The cluster transcript below was taken on 2026-09-30 on
k3s v1.37.0 with the chart at 8d30231. Found while testing the change behind
#263; that change does not touch any of this. The number is recorded in
`../LOG.md` once filed.

---

## Summary

On `main` (8d30231) a default `helm install` of the chart never starts. The
init container exits 1:

```
Creating configuration in /valkey-conf...
mkdir: can't create directory '/valkey-conf': Read-only file system
```

and the pod stays in `Init:Error`, restarting that container. The released
0.12.0 is not affected: its tag predates #234, and `Chart.yaml` on `main`
still reads 0.12.0, so this ships with the next version bump.

## Cause

#234 moved the configuration onto a memory-backed volume: `init.sh` now
defaults `VALKEY_CONFIG` to `/valkey-conf/valkey.conf`
(`templates/init_config.yaml`), and `templates/statefulset.yaml` got a
`valkey-conf` emptyDir mounted at `/valkey-conf` in both containers plus
`args: ["/valkey-conf/valkey.conf"]`. `templates/deploy_valkey.yaml` got
none of that: no volume at `/valkey-conf`, no `VALKEY_CONFIG_PATH`, and its
server container still runs `valkey-server /data/conf/valkey.conf`.

With the default `securityContext` (`readOnlyRootFilesystem: true`) the
`mkdir -p /valkey-conf` fails, which is the error above. Relaxing it does
not help: as uid 1000 the `mkdir` fails with `Permission denied`, and as
root the file lands on the init container's own filesystem, which the
server, reading `/data/conf/valkey.conf`, never sees.

`helm unittest` stays green because no case ties the Deployment's init
container to the path its server reads; `tests/sentinel_test.yaml` pins
that for the StatefulSet only.

## Reproduction

```
helm template t ./valkey | grep -nE 'VALKEY_CONFIG=|mountPath: /valkey-conf|args: \[ "/'
```

shows `VALKEY_CONFIG_PATH:-/valkey-conf/valkey.conf` in the script, the
server's `/data/conf/valkey.conf`, and no `/valkey-conf` mount for the
Deployment. On a cluster (k3s v1.37.0), with `image` pointed at an
Alpine-based 9.1.2 build with a shell, hence busybox's wording of the
`mkdir` error; the default Debian image prints `cannot create directory`,
and the failure does not depend on the image:

```
$ helm install t ./valkey --set image.registry=ghcr.io --set image.repository=mm-weber/dhc/valkey --set image.tag=9.1.2-alpine3.23-compat
$ kubectl get pod -l app.kubernetes.io/instance=t
NAME                        READY   STATUS       RESTARTS      AGE
t-valkey-6689577f9f-tp684   0/1     Init:Error   3 (29s ago)   45s
$ kubectl logs deploy/t-valkey -c t-valkey-init
Wed Sep 30 23:41:12 UTC 2026 Creating configuration in /valkey-conf...
mkdir: can't create directory '/valkey-conf': Read-only file system
```

## Suggested fix, two shapes

1. Keep standalone on `/data/conf`, as 0.12.0 does: set
   `VALKEY_CONFIG_PATH=/data/conf/valkey.conf` on the Deployment's init
   container. Smallest change; standalone's `valkey.conf` carries no
   replication credentials, which is what the memory-backed volume was
   introduced for.
2. Align standalone with the StatefulSet: the same `valkey-conf`
   memory-backed emptyDir mounted at `/valkey-conf` in both containers, and
   `args: ["/valkey-conf/valkey.conf"]`. This is also what the README's
   "Credentials on disk" paragraph and the comment above `VALKEY_CONFIG` in
   `init.sh` describe, without a standalone exception.

Either way, a unit test that the Deployment's init container and server
container agree on the configuration path would have caught this. Happy to
send a PR for whichever shape you prefer.
