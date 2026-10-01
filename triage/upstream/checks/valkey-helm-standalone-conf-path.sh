#!/usr/bin/env bash
# valkey-helm-standalone-conf-path.sh <git-ref> [released-version] [image]
#
# Reproduces the render facts behind
# ../2026-09-30-valkey-helm-standalone-config-path.md: at the given commit of
# valkey-io/valkey-helm, the standalone Deployment's init script writes the
# configuration to a path no volume of that Deployment provides, while its
# server container reads a different path; the StatefulSet carries both the
# volume and the matching argument. The released chart agrees with itself.
# Everything is read from a real render of each chart; nothing is inferred
# from the README or the PR description. With a third argument, the rendered
# init.sh is also run in that image the way the pod runs it (read-only root
# filesystem, uid 1000, an empty /data), which shows the runtime error; the
# default image needs Docker Hub, an Alpine build with a shell works too.
#
#   triage/upstream/checks/valkey-helm-standalone-conf-path.sh 8d30231
#   triage/upstream/checks/valkey-helm-standalone-conf-path.sh main 0.12.0 docker.io/valkey/valkey:9.1.2
set -euo pipefail
ref="${1:?git ref of valkey-io/valkey-helm, e.g. 8d30231 or main}"
released="${2:-0.12.0}"
image="${3:-}"
repo="https://github.com/valkey-io/valkey-helm.git"
chartrepo="https://valkey-io.github.io/valkey-helm"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

git -c credential.helper= clone --quiet --no-checkout "$repo" "$work/src"
git -C "$work/src" checkout --quiet "$ref"
sha=$(git -C "$work/src" rev-parse --short HEAD)
helm pull valkey --repo "$chartrepo" --version "$released" --untar --untardir "$work/rel" >/dev/null

# For one workload kind: the init script's config path, the init container's
# mounts and env, whether anything is mounted at that path, the server's
# argument, and the root filesystem setting the init container runs under.
read_render() { # <chart dir> <kind> [--set args...]
  local chart="$1" kind="$2"; shift 2
  helm template t "$chart" "$@" | python3 "$work/read.py" "$kind"
}
cat > "$work/read.py" <<'PY'
import os, re, sys, yaml
kind = sys.argv[1]
docs = [d for d in yaml.safe_load_all(sys.stdin) if d]
cm = next(d for d in docs if d["kind"] == "ConfigMap" and d["metadata"]["name"].endswith("-init-scripts"))
conf = re.search(r"^VALKEY_CONFIG=\$\{VALKEY_CONFIG_PATH:-(.*)\}$", cm["data"]["init.sh"], re.M).group(1)
wl = next(d for d in docs if d["kind"] == kind and "sentinel" not in d["metadata"]["name"])
spec = wl["spec"]["template"]["spec"]
init = spec["initContainers"][0]
env = {e["name"]: e.get("value", "<from field>") for e in init.get("env", []) or []}
mounts = sorted(m["mountPath"] for m in init.get("volumeMounts", []))
server = spec["containers"][0]
ro = (init.get("securityContext") or {}).get("readOnlyRootFilesystem")
path = env.get("VALKEY_CONFIG_PATH") or conf
d = os.path.dirname(path)
mounted = any(mp == d or d.startswith(mp + "/") for mp in mounts)
same = path == (server.get("args") or [""])[0]
print("  init.sh writes:              " + conf)
print("  init env VALKEY_CONFIG_PATH: " + env.get("VALKEY_CONFIG_PATH", "(unset)"))
print("  init mounts:                 " + ", ".join(mounts))
print("  init root filesystem:        " + ("read-only" if ro else "writable"))
print("  server reads:                " + " ".join(server.get("args") or []))
print("  verdict:                     " + ("AGREES" if mounted and same else "MISMATCH")
      + " (a volume covers the path: %s; the server reads that file: %s)" % (mounted, same))
PY

echo "== valkey-io/valkey-helm at ${sha} (${ref}) =="
echo "Deployment (standalone, default values):"
read_render "$work/src/valkey" Deployment
echo "StatefulSet (replica.enabled=true):"
read_render "$work/src/valkey" StatefulSet --set replica.enabled=true --set replica.persistence.size=1Gi
echo
echo "== released chart ${released} (${chartrepo}) =="
echo "Deployment (standalone, default values):"
read_render "$work/rel/valkey" Deployment
echo
echo "== the commit that moved the path, and what it did to each workload =="
c=$(git -C "$work/src" log --format=%h -1 -S'VALKEY_CONFIG_PATH:-/valkey-conf' -- valkey/templates/init_config.yaml)
git -C "$work/src" log --format='%h %ci %s' -1 "$c" | cut -c1-120
for f in valkey/templates/deploy_valkey.yaml valkey/templates/statefulset.yaml; do
  printf '  %-40s %s line(s) mentioning valkey-conf added by %s\n' "$f" "$(git -C "$work/src" show "$c" -- "$f" | grep -c '^+.*valkey-conf' || true)" "$c"
done
echo
echo "== unit tests: cases that pin the Deployment's config path =="
printf '  deployment_test.yaml: %s line(s) mention /data/conf or /valkey-conf\n' "$(grep -cE '/data/conf|/valkey-conf' "$work/src/valkey/tests/deployment_test.yaml" || true)"
printf '  sentinel_test.yaml:   %s line(s) mention /valkey-conf (the StatefulSet)\n' "$(grep -c '/valkey-conf' "$work/src/valkey/tests/sentinel_test.yaml" || true)"

if [ -n "$image" ]; then
  echo
  echo "== the rendered init.sh at ${sha}, run in ${image} as the pod runs it =="
  helm template t "$work/src/valkey" --show-only templates/init_config.yaml \
    | python3 -c 'import sys, yaml; sys.stdout.write(yaml.safe_load(sys.stdin)["data"]["init.sh"] + "\n")' > "$work/init.sh"
  chmod 0555 "$work/init.sh"
  set +e
  docker run --rm --read-only --user 1000:1000 --cap-drop ALL --security-opt no-new-privileges \
    --tmpfs /data:uid=1000,gid=1000 -v "$work/init.sh":/scripts/init.sh:ro --entrypoint /scripts/init.sh "$image" 2>&1 | sed 's/^/  /'
  echo "  exit status: ${PIPESTATUS[0]}"
  set -e
fi
