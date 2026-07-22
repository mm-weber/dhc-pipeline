#!/usr/bin/env bash
# render-chart.sh <chart-dir> — render a chart's manifests to stdout so the
# policy gate (Req 4.6) can evaluate them. Two shapes:
#   - owned chart   (has Chart.yaml):  helm template <dir>
#   - adapted chart (has chart.yaml pin manifest + config/values-hardened.yaml):
#       helm template <name> <upstream> --repo <repo> --version <ver> -f overlay
# tr strips quotes so this works under either yq (mikefarah on CI, python-yq
# locally).
set -euo pipefail

dir="${1:?usage: render-chart.sh <chart-dir>}"
dir="${dir%/}"
name="$(basename "$dir")"

if [ -f "$dir/Chart.yaml" ]; then
  helm template "$name" "$dir"
elif [ -f "$dir/chart.yaml" ]; then
  repo=$(yq '.upstream.repository' "$dir/chart.yaml" | tr -d '"')
  ver=$(yq '.upstream.version' "$dir/chart.yaml" | tr -d '"')
  uname=$(yq '.upstream.name' "$dir/chart.yaml" | tr -d '"')
  helm template "dhc-${name}" "$uname" \
    --repo "$repo" --version "$ver" \
    -f "$dir/config/values-hardened.yaml"
else
  echo "render-chart: $dir has neither Chart.yaml (owned) nor chart.yaml (adapted pin)" >&2
  exit 1
fi
