#!/usr/bin/env bash
# plugin-release-toolchain.sh <plugin-id> <version> [advisory ...]
#
# What a published Grafana plugin release is built with, and whether the named
# advisories are reported against it. Reads the package the grafana.com plugin
# catalog serves (the same bytes Grafana bundles at build time), not go.mod.
# Used to close grafana-elasticsearch-datasource#410 on 2026-09-03:
#
#   triage/upstream/checks/plugin-release-toolchain.sh elasticsearch 12.8.1 \
#     CVE-2026-27145 CVE-2026-42504 CVE-2026-42507 CVE-2026-39822 CVE-2026-42505
set -euo pipefail
plugin="${1:?plugin id, e.g. elasticsearch}"; ver="${2:?version, e.g. 12.8.1}"; shift 2
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cd "$work"
zip="${plugin}-${ver}.linux_amd64.zip"
api="https://grafana.com/api/plugins/${plugin}/versions/${ver}"
# The catalog package is what Grafana bundles; when a version is not on the
# catalog (yet), fall back to the GitHub release asset and say so.
if curl -fsS --max-time 30 "$api" -o version.json 2>/dev/null; then
  echo "\$ curl -s ${api} | jq -c '{version, createdAt, status}'"
  jq -c '{version, createdAt, status}' version.json
  echo "\$ curl -sSL -o ${zip} '${api}/download?os=linux&arch=amd64'"
  curl -fsSL --max-time 300 -o "$zip" "${api}/download?os=linux&arch=amd64"
else
  repo="grafana/grafana-${plugin}-datasource"
  echo "# ${api} -> 404: version not on the plugin catalog; using the GitHub release asset"
  echo "\$ gh release download v${ver} -R ${repo} -p '${zip}'"
  gh release download "v${ver}" -R "$repo" -p "$zip" --dir .
fi
echo "\$ sha256sum ${zip}"
sha256sum "$zip"
echo "\$ unzip -q ${zip}"
unzip -q "$zip"
bin="$(find . -type f -name '*_linux_amd64' | head -1)"
echo "\$ go version -m ${bin#./} | head -3"
go version -m "$bin" | head -3 | sed 's#^\./##'
echo "\$ trivy --version | head -1; trivy rootfs --scanners vuln --format json -o scan.json ."
trivy --version | head -1
trivy rootfs --quiet --scanners vuln --format json -o scan.json . 2>/dev/null
for adv in "$@"; do
  n="$(jq -r --arg c "$adv" '[.Results[]? | (.Vulnerabilities // [])[] | select(.VulnerabilityID==$c)] | length' scan.json)"
  echo "${adv}: ${n} finding(s)"
done
echo "\$ HIGH/CRITICAL remaining:"
jq -r '[.Results[]? | (.Vulnerabilities // [])[] | select(.Severity=="HIGH" or .Severity=="CRITICAL") | "\(.VulnerabilityID) \(.PkgName)@\(.InstalledVersion)"] | if length==0 then "none" else .[] end' scan.json
