#!/usr/bin/env bash
# grafana-server-pins.sh <version> <build-id>
#
# Reproduces the measurements behind
# ../2026-09-03-grafana-server-thrift-and-grpc-below-fixed.md: which module
# versions a published Grafana server binary links, read from the binary's own
# build info, and the fixed-in versions the advisories name. Every tool here is
# the real one (gh, dpkg-deb, go version -m); nothing is inferred from go.mod.
#
#   triage/upstream/checks/grafana-server-pins.sh 13.1.5 33098073184
set -euo pipefail
ver="${1:?version, e.g. 13.1.5}"; build="${2:?build id, e.g. 33098073184}"
deb="grafana_${ver}_${build}_linux_amd64.deb"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cd "$work"
gh release download "v${ver}" --repo grafana/grafana --pattern "$deb" --dir .
echo "sha256 $(sha256sum "$deb" | cut -c1-64)  $deb"
dpkg-deb -x "$deb" root
echo
echo "== build info: server binary =="
go version -m root/usr/share/grafana/bin/grafana \
  | grep -E "^root/|^\s+dep\s+(github.com/apache/thrift|google.golang.org/grpc|github.com/uber/jaeger-client-go)\s" \
  | sed 's#^root/usr/share/grafana/#/usr/share/grafana/#'
echo
echo "== build info: bundled zipkin plugin =="
go version -m root/usr/share/grafana/data/plugins-bundled/zipkin/gpx_grafana-zipkin-datasource_linux_amd64 \
  | grep -E "^root/|^\s+(mod|dep)\s+(github.com/grafana/grafana-zipkin-datasource|google.golang.org/grpc)\s" \
  | sed 's#^root/usr/share/grafana/#/usr/share/grafana/#'
echo
echo "== advisories: vulnerable range and first patched version =="
for ghsa in GHSA-8wv5-x4w7-5gww GHSA-vp52-pcj8-j9qc; do
  gh api "/advisories/${ghsa}" --jq '"\(.ghsa_id) \(.cve_id // "-") \(.severity): " + ([.vulnerabilities[] | select(.package.ecosystem=="go") | "\(.package.name) \(.vulnerable_version_range), fixed \(.first_patched_version)"] | join("; "))'
done
echo
echo "== what grafana/grafana main pins today =="
gh api "repos/grafana/grafana/contents/go.mod?ref=main" --jq .content | base64 -d \
  | grep -E "^\s+(github.com/apache/thrift|google.golang.org/grpc)\s"
