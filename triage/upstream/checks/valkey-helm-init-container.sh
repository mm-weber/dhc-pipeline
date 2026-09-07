#!/usr/bin/env bash
# valkey-helm-init-container.sh <chart-version> [values-overlay]
#
# Reproduces the measurement behind
# ../2026-08-25-valkey-helm-init-container-image.md: the valkey chart renders
# an init container unconditionally, from the same image as the main
# container, running a /bin/sh script, and no value replaces or disables it;
# the metrics exporter, by contrast, has an image value of its own. Everything
# is read from the published chart (helm pull) and from a real render (helm
# template) with this catalogue's values overlay; nothing is inferred from the
# README.
#
#   triage/upstream/checks/valkey-helm-init-container.sh 0.11.0
#   triage/upstream/checks/valkey-helm-init-container.sh 0.12.0 chart/valkey/config/values-hardened.yaml
set -euo pipefail
ver="${1:?chart version, e.g. 0.11.0}"
overlay="${2:-}"
repo="https://valkey-io.github.io/valkey-helm"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

helm pull valkey --repo "$repo" --version "$ver" --untar --untardir "$work" >/dev/null
chart="$work/valkey"
echo "== valkey chart ${ver} (appVersion $(awk '/^appVersion:/{print $2}' "$chart/Chart.yaml")), pulled from ${repo} =="
echo
echo "== the init container, templates/deploy_valkey.yaml (standalone) =="
awk '/initContainers:/{f=1} f{print NR": "$0} f&&/command:/{exit}' "$chart/templates/deploy_valkey.yaml"
echo
echo "== every template rendering an init container, and the control blocks open at that line =="
# Every if/with/range opened before the line and not yet closed by its end:
# the blocks the line sits inside, each named. A block that renders the whole
# workload (the standalone-vs-replica switch) is not a switch for the init
# container: whichever workload renders, the init container renders with it.
for t in "$chart"/templates/*.yaml; do
  grep -q 'initContainers:' "$t" || continue
  awk -v f="$(basename "$t")" '/\{\{-?[[:space:]]*(if|with|range)[[:space:]]/{stack[++n]=$0} /\{\{-?[[:space:]]*end[[:space:]]*-?\}\}/{if(n>0)n--} /initContainers:/{printf "%s: line %d, %d open block(s)", f, NR, n; for(i=1;i<=n;i++) printf ": %s", stack[i]; print ""; exit}' "$t"
  grep -n -A2 'initContainers:' "$t" | grep 'image:' | head -1 | sed 's/^/  /'
done
echo
echo "== the image helper it shares with the main container =="
awk '/define "valkey.image"/{f=1} f{print NR": "$0} f&&/end/{exit}' "$chart/templates/_helpers.tpl"
echo
echo "== init.sh: interpreter and the utilities it calls (templates/init_config.yaml) =="
grep -n '#!/bin/sh' "$chart/templates/init_config.yaml" | head -1
for u in date tee cat rm mkdir chmod touch sha256sum cut valkey-cli valkey-server; do printf '%-13s on %s line(s)\n' "$u" "$(grep -cw -- "$u" "$chart/templates/init_config.yaml" || true)"; done
echo
echo "== values that carry an image, values.yaml (the exporter's own image is the precedent) =="
grep -nE '^(image|metrics):|^\s+image:|repository:|^\s+tag:' "$chart/values.yaml" | head -12
echo
echo "== any value naming the init container? =="
echo "$(grep -ciE 'init' "$chart/values.yaml") line(s) mention init; extraInitContainers appends, nothing replaces:"
grep -nE 'extraInitContainers|initContainer' "$chart/values.yaml" "$chart/templates/deploy_valkey.yaml" | head -6
if [ -n "$overlay" ]; then
  echo
  echo "== rendered with ${overlay}: the init container's image is the main container's =="
  helm template dhc-valkey "$chart" -f "$overlay" 2>/dev/null \
    | python3 -c '
import sys, yaml
for doc in yaml.safe_load_all(sys.stdin):
    if not doc or doc.get("kind") not in ("Deployment", "StatefulSet"):
        continue
    spec = doc["spec"]["template"]["spec"]
    for c in spec.get("initContainers", []):
        print("init     ", c["name"], c["image"], c.get("command"))
    for c in spec.get("containers", []):
        print("container", c["name"], c["image"])'
fi
