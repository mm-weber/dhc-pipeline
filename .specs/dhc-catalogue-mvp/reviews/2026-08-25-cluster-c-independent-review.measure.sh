#!/usr/bin/env bash
# Measurements behind the PR #101 (cluster C) independent review, 2026-08-25.
# Run from the worktree root. Network sections need the devcontainer allowlist
# (api.github.com, grafana.com, dl.grafana.com, charts.jetstack.io,
# grafana.github.io, valkey-io.github.io -> valkey.io, npm, PyPI).
# Sections:
#   S1  EARS validator over the amended requirements
#   S2  live GitHub rulesets: required status checks on main (Req 3.5/3.12 "green required checks")
#   S3  upstream signature statements: cert-manager v1.21.1, valkey 9.1.1, hardened-app v0.1.0
#   S4  grafana versions-API sha256 vs dl.grafana.com sidecar, 5 versions x 4 arches (the "20 cases")
#   S5  renovate 41.173.1 (the version validate.yml pins) installed from npm; source facts:
#       releaseTimestamp support per datasource, minimumReleaseAge filtering and its
#       timestamp-optional default, packageRules ordering, regex-manager registryUrl field,
#       postUpgradeTasks stdout handling, platformAutomerge default
#   S6  renovate-config-validator --strict on the repo config and on a cluster-C-shaped variant
#       (datasource-scoped minimumReleaseAge rules, helm regex manager with registryUrl capture,
#       chart digest automerge rule), plus offline extraction emulation against the chart.yaml files
#   S7  yamale 6.1.0 (the version requirements-ci.txt pins): day() constraint semantics
#   S8  chart repository indexes: version spellings and created timestamps
#   S9  tree facts: dhi.io repository paths, chart-pin manager landing date
set -uo pipefail
SCRATCH="${SCRATCH:-$(mktemp -d)}"
echo "scratch: $SCRATCH"

echo "== S1: EARS validator"
node .claude/skills/ears-notation/scripts/ears-validator.js .specs/dhc-catalogue-mvp/requirements.md; echo "exit=$?"

echo "== S2: live rulesets and required checks (anonymous)"
curl -sf --max-time 30 https://api.github.com/repos/mm-weber/dhc-pipeline/rulesets -o "$SCRATCH/rulesets.json" \
  && jq -r '.[] | "\(.id) \(.name) \(.enforcement)"' "$SCRATCH/rulesets.json"
curl -sf --max-time 30 https://api.github.com/repos/mm-weber/dhc-pipeline/rules/branches/main -o "$SCRATCH/branch-rules.json" \
  && jq -r '.[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context' "$SCRATCH/branch-rules.json"

echo "== S3: upstream signature statements (anonymous GitHub API)"
curl -sf --max-time 30 https://api.github.com/repos/cert-manager/cert-manager/git/ref/tags/v1.21.1 -o "$SCRATCH/cm-ref.json"
jq -r '.object | "\(.type) \(.sha)"' "$SCRATCH/cm-ref.json"
cm_sha=$(jq -r .object.sha "$SCRATCH/cm-ref.json")
curl -sf --max-time 30 "https://api.github.com/repos/cert-manager/cert-manager/git/tags/$cm_sha" \
  | jq '{tag: .tag, verified: .verification.verified, reason: .verification.reason}'
curl -sf --max-time 30 https://api.github.com/repos/valkey-io/valkey/git/ref/tags/9.1.1 -o "$SCRATCH/vk-ref.json"
jq -r '.object | "\(.type) \(.sha)"' "$SCRATCH/vk-ref.json"
vk_sha=$(jq -r .object.sha "$SCRATCH/vk-ref.json")
curl -sf --max-time 30 "https://api.github.com/repos/valkey-io/valkey/commits/$vk_sha" \
  | jq '{sha: .sha, verified: .commit.verification.verified, reason: .commit.verification.reason}'
curl -sf --max-time 30 https://api.github.com/repos/mm-weber/hardened-app/git/ref/tags/v0.1.0 -o "$SCRATCH/ha-ref.json"
jq -r '.object | "\(.type) \(.sha)"' "$SCRATCH/ha-ref.json"
ha_sha=$(jq -r .object.sha "$SCRATCH/ha-ref.json")
curl -sf --max-time 30 "https://api.github.com/repos/mm-weber/hardened-app/commits/$ha_sha" \
  | jq '{sha: .sha, verified: .commit.verification.verified, reason: .commit.verification.reason}'
grep -n 'COMMIT_SHA\|checksum:' image/hardened-app/image.yaml image/valkey/image.yaml | head -8

echo "== S4: grafana API sha256 vs sidecar, 5 versions x 4 arches"
SC="$SCRATCH/sc.txt"
for v in 13.0.4 13.0.6 13.1.1 13.1.2 13.1.3; do
  curl -sf --max-time 60 "https://grafana.com/api/grafana/versions/$v" -o "$SCRATCH/gf-api-$v.json" || { echo "$v API FAIL"; continue; }
  jq -r '.packages[] | select(.url | test("linux_(amd64|arm64|arm-6|arm-7)\\.tar\\.gz$")) | "\(.url) \(.sha256)"' "$SCRATCH/gf-api-$v.json" \
  | while read -r url api; do
      code=$(curl -s -o "$SC" -w '%{http_code}' --max-time 60 "${url}.sha256")
      side=$(tr -d '[:space:]' < "$SC" 2>/dev/null | cut -c1-64)
      arch=$(sed -E 's/.*linux_([a-z0-9-]+)\.tar\.gz.*/\1/' <<<"$url")
      if [ "$code" = 200 ] && [ "$side" = "$api" ]; then echo "$v $arch AGREE (sidecar==api)"
      elif [ "$code" = 200 ]; then echo "$v $arch DISAGREE api=$api sidecar=$side"
      else echo "$v $arch sidecar HTTP $code (api=$api)"; fi
    done
done
echo "pinned values (image/grafana/image.yaml):"; grep -n 'GRAFANA_SHA256' image/grafana/image.yaml

echo "== S5: renovate 41.173.1 source facts"
mkdir -p "$SCRATCH/renovate-install" && cd "$SCRATCH/renovate-install"
npm install --no-save --no-audit --no-fund renovate@41.173.1 json5@2.2.3 > npm-install.log 2>&1; echo "npm exit=$?"
R="$SCRATCH/renovate-install/node_modules/renovate/dist"
grep -n "releaseTimestampSupport" "$R/modules/datasource/github-tags/index.js" | head -2
grep -n "releaseTimestamp: committedDate" "$R/../renovate/dist/util/github/graphql/query-adapters/tags-query-adapter.js" 2>/dev/null \
  || grep -n "committedDate" "$R/util/github/graphql/query-adapters/tags-query-adapter.js" | head -2
grep -n "releaseTimestampSupport" "$R/modules/datasource/github-releases/index.js" | head -2
grep -n "releaseTimestampSupport\|defaultRegistryUrls" "$R/modules/datasource/helm/index.js" | head -3
grep -n -A5 "name: 'minimumReleaseAge'," "$R/config/options/index.js" | head -7
grep -n -A6 "name: 'minimumReleaseAgeBehaviour'" "$R/config/options/index.js" | head -8
sed -n '45,71p' "$R/workers/repository/process/lookup/filter-checks.js"
sed -n '26,30p' "$R/util/package-rules/index.js"
grep -n -A4 "name: 'platformAutomerge'" "$R/config/options/index.js" | head -6
sed -n '95,103p' "$R/workers/repository/update/branch/execute-post-upgrade-commands.js"
grep -n "'registryUrl'" "$R/modules/manager/custom/regex/utils.js" | head -2
cd - >/dev/null

echo "== S6: config validator, baseline and cluster-C variant, plus helm-manager emulation"
cp renovate.json5 "$SCRATCH/baseline.json5"
NODE_PATH="$SCRATCH/renovate-install/node_modules" node - <<EOF
const { readFileSync, writeFileSync } = require("node:fs");
const scratch = "$SCRATCH";
const JSON5 = require("json5");
const cfg = JSON5.parse(readFileSync(scratch + "/baseline.json5", "utf8"));
const helmMgr = {
  customType: "regex",
  managerFilePatterns: ["/^chart/[^/]+/chart\\\\.yaml\$/"],
  matchStrings: [
    "upstream:\\\\s*\\\\n\\\\s*name:\\\\s*(?<depName>[^\\\\s\\"']+)\\\\s*\\\\n\\\\s*repository:\\\\s*(?<registryUrl>[^\\\\s\\"']+)\\\\s*\\\\n\\\\s*version:\\\\s*(?<currentValue>[^\\\\s\\"']+)",
  ],
  datasourceTemplate: "helm",
};
cfg.customManagers.push(helmMgr);
const dhiRule = cfg.packageRules.pop();
cfg.packageRules.push(
  { matchDatasources: ["github-tags"], minimumReleaseAge: "3 days", minimumReleaseAgeBehaviour: "timestamp-required" },
  { matchDatasources: ["github-releases"], minimumReleaseAge: "3 days", minimumReleaseAgeBehaviour: "timestamp-required" },
  { matchDatasources: ["docker"], matchFileNames: ["chart/**"], matchUpdateTypes: ["digest"], automerge: true },
  dhiRule,
);
writeFileSync(scratch + "/variant.json5", JSON5.stringify(cfg, null, 2));
function fpm(mgr, p) { return mgr.managerFilePatterns.some((s) => { const m = /^\/(.*)\/\$/.exec(s); return m ? new RegExp(m[1]).test(p) : s === p; }); }
for (const f of ["chart/cert-manager/chart.yaml", "chart/grafana/chart.yaml", "chart/valkey/chart.yaml", "chart/hardened-app/Chart.yaml", "chart/hardened-app/values.yaml"]) {
  const matches = fpm(helmMgr, f);
  let deps = [];
  if (matches) {
    const content = readFileSync(f, "utf8");
    for (const p of helmMgr.matchStrings) { const re = new RegExp(p, "g"); let m; while ((m = re.exec(content)) !== null) deps.push(m.groups); }
  }
  console.log(f, "pattern-match:", matches, "deps:", JSON.stringify(deps));
}
const { GithubTagsDatasource } = require("renovate/dist/modules/datasource/github-tags");
const { GithubReleasesDatasource } = require("renovate/dist/modules/datasource/github-releases");
const { HelmDatasource } = require("renovate/dist/modules/datasource/helm");
console.log("github-tags releaseTimestampSupport:", new GithubTagsDatasource().releaseTimestampSupport);
console.log("github-releases releaseTimestampSupport:", new GithubReleasesDatasource().releaseTimestampSupport);
const h = new HelmDatasource();
console.log("helm releaseTimestampSupport:", h.releaseTimestampSupport, "defaultRegistryUrls:", h.defaultRegistryUrls);
EOF
NODE_PATH="$SCRATCH/renovate-install/node_modules" "$SCRATCH/renovate-install/node_modules/.bin/renovate-config-validator" --strict "$SCRATCH/baseline.json5" 2>&1 | tail -2
NODE_PATH="$SCRATCH/renovate-install/node_modules" "$SCRATCH/renovate-install/node_modules/.bin/renovate-config-validator" --strict "$SCRATCH/variant.json5" 2>&1 | tail -2

echo "== S7: yamale 6.1.0 day() semantics"
pip install --quiet --break-system-packages yamale==6.1.0
python3 - <<'EOF'
import inspect
from yamale.validators import validators as V
print(inspect.getsource(V.Day))
EOF
mkdir -p "$SCRATCH/yamale-test" && cd "$SCRATCH/yamale-test"
printf 'compat: include("compat")\n---\ncompat:\n  reason: str()\n  upstream_issue: str()\n  review_by: day(max="2026-08-24")\n' > schema.yaml
printf 'compat:\n  reason: r\n  upstream_issue: u\n  review_by: 2026-08-01\n' > good.yaml
printf 'compat:\n  reason: r\n  upstream_issue: u\n  review_by: 2026-09-30\n' > lapsed.yaml
yamale -s schema.yaml good.yaml; echo "good exit=$?"
yamale -s schema.yaml lapsed.yaml; echo "lapsed exit=$?"
grep -rn "today\|date.today\|now()" "$(python3 -c 'import yamale,os;print(os.path.dirname(yamale.__file__))')"/validators/*.py | head -3
echo "(no hits above: no dynamic-today constraint exists)"
cd - >/dev/null

echo "== S8: chart repository indexes"
curl -sf --max-time 30 https://charts.jetstack.io/index.yaml -o "$SCRATCH/jetstack-index.yaml" && python3 -c "
import yaml
idx = yaml.safe_load(open('$SCRATCH/jetstack-index.yaml'))
print('jetstack cert-manager newest:', [e['version'] for e in idx['entries']['cert-manager'][:3]])
"
curl -sf --max-time 30 https://grafana.github.io/helm-charts/index.yaml -o "$SCRATCH/grafana-index.yaml" && python3 -c "
import yaml
idx = yaml.safe_load(open('$SCRATCH/grafana-index.yaml'))
print('grafana chart newest:', [e['version'] for e in idx['entries']['grafana'][:3]])
"
curl -sL --max-time 30 -w 'HTTP %{http_code} final=%{url_effective}\n' https://valkey-io.github.io/valkey-helm/index.yaml -o "$SCRATCH/valkey-index.yaml" && python3 -c "
import yaml
idx = yaml.safe_load(open('$SCRATCH/valkey-index.yaml'))
e = idx['entries']['valkey']
print('valkey chart newest:', [x['version'] for x in e[:3]], 'created present:', 'created' in e[0])
"

echo "== S9: tree facts"
grep -n 'dhi\.io/apk\|dhi\.io/deb' image/*/image.yaml
git log --date=short --format='%h %ad %s' -S 'values-hardened' -- renovate.json5 | head -3
grep -n '2026-08-13 done (#64)' .specs/dhc-catalogue-mvp/tasks.md | head -1
grep -n 'datasource=github-releases' scripts/install-scanners.sh scripts/install-tool.sh
grep -n 'deb/debian/main' data/dhi-terms-2026-08-21.md | head -2
