#!/usr/bin/env bash
# Reproduce the Trivy 0.72.0 measurements behind Req 6.23-6.27.
#
# Everything the per-binary scoping design assumes was measured with this, not
# read from documentation. Run it before trusting any of it again, especially
# after a Trivy bump: `paths:` is not a stable public contract, and the failure
# mode if it stops working is silent.
#
#   ./trivy-paths-scoping.sh            # downloads both plugin assets, ~22 MB
#
# Needs: trivy, gh (authenticated), unzip, jq.
set -euo pipefail

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
DB="${TRIVY_DB_REPOSITORY:-ghcr.io/aquasecurity/trivy-db:2}"
BUNDLED="$WORK/rootfs/usr/share/grafana/data/plugins-bundled"
ES="usr/share/grafana/data/plugins-bundled/elasticsearch"

mkdir -p "$BUNDLED/elasticsearch" "$BUNDLED/zipkin"

echo "== fetching the real plugin release assets"
gh release download v12.8.0 -R grafana/grafana-elasticsearch-datasource \
  -p 'elasticsearch-12.8.0.linux_amd64.zip' -D "$WORK" --clobber
gh release download v12.4.5 -R grafana/grafana-zipkin-datasource \
  -p 'zipkin-12.4.5.linux_amd64.zip' -D "$WORK" --clobber
unzip -q "$WORK/elasticsearch-12.8.0.linux_amd64.zip" -d "$WORK/xe"
unzip -q "$WORK/zipkin-12.4.5.linux_amd64.zip" -d "$WORK/xz"
cp "$WORK"/xe/elasticsearch/gpx_* "$BUNDLED/elasticsearch/"
cp "$WORK"/xz/zipkin/gpx_* "$BUNDLED/zipkin/"

# The toolchain claim in the two upstream drafts, straight from the binaries.
echo "== toolchain each asset was built with"
for b in "$BUNDLED"/*/gpx_*; do printf '   %s\n' "$(go version -m "$b" | head -1)"; done

scan() { # $1 = label, $2 = ignorefile ("" for none)
  local args=(rootfs --scanners vuln --severity HIGH,CRITICAL --db-repository "$DB"
              --format json -o "$WORK/out.json" --quiet)
  [ -n "$2" ] && args+=(--ignorefile "$2" --show-suppressed)
  trivy "${args[@]}" "$WORK/rootfs"
  printf '   %-34s total=%-3s suppressed_in=%s\n' "$1" \
    "$(jq '[.Results[]?|(.Vulnerabilities//[])[]]|length' "$WORK/out.json")" \
    "$(jq -r '[.Results[]?|select(.ExperimentalModifiedFindings)|.Target|split("/")|.[-2]]|join(",")|if .=="" then "-" else . end' "$WORK/out.json")"
}

ignore() { # $1 = paths line, "" for none. The newline is emitted HERE: a
           # caller-written "\n" inside double quotes is two literal characters,
           # and %s does not expand escapes — the garbled one-line YAML of #76.
  local paths=""
  if [ -n "$1" ]; then paths="$1"$'\n'; fi
  printf 'vulnerabilities:\n  - id: CVE-2026-27145\n%s    statement: "measurement"\n' "$paths" \
    > "$WORK/ig.yaml"
  echo "$WORK/ig.yaml"
}

echo "== baseline, no ignorefile"
scan "baseline" ""

echo "== no paths: key suppresses every instance"
scan "no paths" "$(ignore '')"

echo "== paths: scopes to one binary (exact, then globs)"
for p in "$ES/gpx_grafana_elasticsearch_datasource_linux_amd64" "$ES/*" "**/plugins-bundled/elasticsearch/**" "$ES/gpx_*"; do
  scan "$p" "$(ignore "    paths: [\"$p\"]")"
done

echo "== a path matching nothing is silent: no warning, exit 0, nothing suppressed"
scan "typo'd path" "$(ignore "    paths: [\"$ES aerch/*\"]")"

cat <<'NOTE'

Expected, as measured on 2026-08-04 with trivy 0.72.0:

  baseline                           total=12  suppressed_in=-
  no paths                           total=10  suppressed_in=elasticsearch,zipkin
  every paths: form above            total=11  suppressed_in=elasticsearch
  typo'd path                        total=12  suppressed_in=-

Re-measured 2026-08-20 with trivy 0.73.0, fixing #76 (the generated ignore
file was garbled by a literal \n, so the four paths: cases and the typo'd
case had never actually run from this script as committed). Absolute totals
had grown 12→29 as new advisories landed against these go1.26.3 binaries;
what must hold is the DELTAS, and every one did: no paths −2 (both binaries),
each paths: form −1 (elasticsearch only), typo'd path −0 and silent.

The last line is the whole reason Req 6.26 exists. Trivy accepts a path that
matches nothing, suppresses nothing, warns nobody and exits 0, which is
indistinguishable from an untriaged finding unless the lane file is compared
against the report. scripts/accepted-risk-report.sh is that comparison.

Globs are load-bearing, not cosmetic. Measured on the published index
ghcr.io/mm-weber/dhc/grafana:13-alpine3.23, the same finding sits at
  .../elasticsearch/gpx_grafana_elasticsearch_datasource_linux_amd64  on amd64
  .../elasticsearch/gpx_grafana_elasticsearch_datasource_linux_arm64  on arm64
The catalogue publishes amd64 only (Req 2.1), so an exact path is correct for
every scan that runs today and goes silently wrong when arm64 returns (task 8.3)
or when a consumer scans an arm64 image themselves. A glob costs nothing now and
removes that as a future discovery.

Measuring per-platform yourself needs --image-src remote, not just --platform.
Trivy's default source order is docker,containerd,podman,remote, and a daemon
copy is single-arch, so --platform is silently ignored against it:
`--platform linux/arm64` returned architecture=amd64 in 0s until the daemon was
bypassed. Same silent-failure family as the typo'd path above.
NOTE
