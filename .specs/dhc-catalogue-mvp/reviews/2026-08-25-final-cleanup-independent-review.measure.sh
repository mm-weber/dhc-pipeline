#!/usr/bin/env bash
# Measurements behind the PR #104 (final cleanup, base-repo contract) independent
# review, 2026-08-25. Run from the worktree root. Network sections need the
# devcontainer allowlist (api.github.com).
# Sections:
#   S1  EARS validator over the amended requirements.md (expected: PASSED, 161),
#       and over the review's fifteen proposed replacement criteria
#   S2  instance-literal sweep of requirements.md: registry and owner literals
#       (expected zero), component names inside numbered criteria (expected 1.1 only)
#   S3  universal-quantifier inventory: the standing criteria that still range over
#       every definition or every chart against the new active-set criteria
#   S4  tree facts: definition and chart counts; matrix mechanisms (build.yml job-output
#       plus fromJSON, e2e.yml hardcoded component list and prefix-regex mapping,
#       chart.yml for-loop with no matrix); componentSpecs keyed by component (4);
#       no definition declares a chart; chart.yaml declares upstream chart-side;
#       valkey-compat is the init-container image; lint-pins.sh variant parity;
#       restrict-registries and renovate.json5 namespace literals; validate.yml
#       renovate pin and Go steps; tasks.md 9.1/9.2/9.4 literals
#   S5  network: renovate 41.173.1 options source (ignorePaths, matchFileNames,
#       enabled, ignoreDeps present); renovatebot/github-action v43.0.9 default
#       renovate-version
#   S6  subject facts: merge base, diff stat
set -uo pipefail
REQ=.specs/dhc-catalogue-mvp/requirements.md
SCRATCH="${SCRATCH:-$(mktemp -d)}"
echo "scratch: $SCRATCH"

echo
echo "== S1: EARS validator, amended requirements"
node .claude/skills/ears-notation/scripts/ears-validator.js "$REQ" | grep -E "Valid Statements|PASSED|FAILED"

echo
echo "== S1b: EARS validator, proposed replacement criteria"
cat > "$SCRATCH/proposals.md" <<'EOF'
# Requirements Document

### Requirement X: Proposals

#### Acceptance Criteria

1. THE CI Pipeline SHALL rebuild every definition in its declared active set on a declared schedule at least once per day.
2. THE Repository SHALL declare in its catalogue policy file an active set naming each definition it builds, tracks, tests and publishes, a definition so named being an active definition.
3. THE CI Pipeline SHALL read that active set as its sole source of candidate definitions for its build matrix, its chart and test matrices and its upstream tracking scope, and SHALL admit no definition outside that active set into any of them.
4. WHERE a chart adaptation deploying an active definition's images pins an upstream chart THE Chart Adaptation SHALL consume that chart at its pinned version without modifying upstream templates.
5. WHEN an upstream release matches an active definition's version policy THE Renovate Automation SHALL open a pull request updating pinned ref, checksum, and derived tags.
6. THE Scan Pipeline SHALL re-verify at least once per day each active definition's declared authenticity signal against its upstream origin, and SHALL report each mismatch as a failure of that run and file an issue naming it as a supply-chain signal.
7. THE Renovate Automation SHALL track each upstream chart version pinned under chart/ for an active definition against its chart repository and SHALL open a pull request, never automerged, for each new chart release matching its version policy.
8. WHEN a definition change merges to main THE CI Pipeline SHALL build each affected active definition's images for every platform its definition declares.
9. WHILE a definition sits outside that active set THE CI Pipeline SHALL push no new digest for it and SHALL apply no new tag for it.
10. IF a pull request bumps a definition outside that active set or a chart adaptation deploying no active definition THEN THE CI Pipeline SHALL fail validation naming that definition or that chart adaptation.
11. IF that active set splits a definition group whose source pins are enforced byte-equal or whose bumps are grouped under criterion 3.3 THEN THE CI Pipeline SHALL fail validation naming that group.
12. IF an active definition declares no functional probe THEN THE CI Pipeline SHALL fail validation naming that definition.
13. IF that active set names a definition with no definition directory under image/ THEN THE CI Pipeline SHALL fail validation naming that entry.
14. WHEN pods are Ready THE Test Suite SHALL execute each functional probe declared by an active definition that installed chart deploys, executing a probe shared by several definitions once.
15. WHEN a pull request affects an active definition's image or chart THE Test Suite SHALL install each such affected chart on a kind cluster in CI.
EOF
node .claude/skills/ears-notation/scripts/ears-validator.js "$SCRATCH/proposals.md" | grep -E "Valid Statements|PASSED|FAILED"

echo
echo "== S2: instance literals in requirements.md"
echo "-- registry and owner literals (expect no output):"
grep -n "mm-weber\|ghcr\.io" "$REQ" || echo "(none)"
echo "-- component names inside numbered criteria (expect line 31, Req 1.1 reference set, only):"
grep -n "^[0-9]*\. .*\(hardened-app\|cert-manager\|grafana\|valkey\)" "$REQ" || echo "(none)"

echo
echo "== S3: universal quantifiers vs the active set"
grep -n "^14\. THE CI Pipeline SHALL rebuild every definition" "$REQ"
grep -n "^15\. WHERE a declared publish policy" "$REQ" | head -1
grep -n "^16\. WHEN a scheduled rebuild produces" "$REQ"
grep -n "^1\. WHEN a definition change merges" "$REQ"
grep -n "^2\. WHEN an upstream release matches a definition's" "$REQ"
grep -n "^3\. WHEN multiple images share one upstream monorepo" "$REQ"
grep -n "^10\. THE Scan Pipeline SHALL re-verify" "$REQ"
grep -n "^11\. THE Renovate Automation SHALL track each upstream chart" "$REQ"
grep -n "^2\. WHEN a pull request affects an image or chart" "$REQ"
grep -n "^13\.\|^14\.\|^15\.\|^16\.\|^17\." "$REQ" | sed -n 1,5p
grep -n "^1\. WHERE an active definition declares" "$REQ"
grep -n "^5\. WHEN pods are Ready THE Test Suite SHALL execute each active" "$REQ"

echo
echo "== S4: tree facts"
echo "-- definition directories (expect 7):"
ls image/
ls image/ | wc -l
echo "-- chart directories (expect 4):"
ls chart/ | wc -l
echo "-- build.yml matrix mechanism (job output feeding fromJSON):"
grep -n "names: \${{ steps.detect.outputs.names }}\|name: \${{ fromJSON(needs.changes.outputs.names) }}" .github/workflows/build.yml
echo "-- build.yml all-definitions source (disk listing, not a declared set):"
grep -n "all_defs()" .github/workflows/build.yml
echo "-- e2e.yml hardcoded component list and definition-to-component prefix regex:"
grep -n 'ALL="cert-manager grafana hardened-app valkey"' .github/workflows/e2e.yml
grep -n 'image/\${c}(-|/)' .github/workflows/e2e.yml || grep -n "image/.{c}" .github/workflows/e2e.yml
echo "-- chart.yml has no matrix, loops every chart directory:"
grep -n "matrix" .github/workflows/chart.yml || echo "(no matrix key in chart.yml)"
grep -n "for d in chart/\*/" .github/workflows/chart.yml
echo "-- componentSpecs: probes keyed by chart-backed component (expect 4 Probe: lines):"
grep -cn "Probe:" test/e2e/components_test.go
grep -n "componentSpecs are the four components" test/e2e/components_test.go
echo "-- no definition declares a chart (expect: no chart: key in any definition):"
grep -nE "^\s*chart\s*:" image/*/image.yaml || echo "(no chart: key in any definition)"
echo "-- every 'chart' mention in definitions is a comment or a label value:"
grep -n "chart" image/*/image.yaml | grep -v "#" || echo "(only the valkey-compat description label value)"
echo "-- upstream chart is declared chart-side (chart.yaml upstream block):"
grep -n "^upstream:" chart/cert-manager/chart.yaml chart/grafana/chart.yaml chart/valkey/chart.yaml
echo "-- valkey-compat is the init-container image in the deployed chart (comment lines elided):"
grep -n "compat" chart/valkey/config/values-hardened.yaml | grep -v "by-hand era" | head -4
echo "-- lint-pins.sh variant parity: byte-equal source pins across one published repository:"
grep -n "variant parity" scripts/lint-pins.sh
echo "-- renovate grouping rules (monorepo trio, valkey pair, chart-pin trio):"
grep -n "groupName" renovate.json5
echo "-- restrict-registries hardcodes the namespace (enforcing lines; comments elided):"
grep -n "image:.*ghcr.io/mm-weber/dhc\|Only images from" policies/restrict-registries.yaml
echo "-- renovate.json5 namespace literals (matchStrings and matchDepNames; comments elided):"
grep -n "mm-weber" renovate.json5 | grep -v "//"
echo "-- validate.yml: pinned renovate for config validation, Go steps for a probe lint:"
grep -n "RENOVATE_VERSION:" .github/workflows/validate.yml
grep -n "go test ./harness" .github/workflows/validate.yml
echo "-- tasks.md: 9.1 and 9.4 step text still hardcodes the namespace; 9.2 lists every definition:"
grep -n "name=ghcr.io/mm-weber/dhc" .specs/dhc-catalogue-mvp/tasks.md
grep -n "scope=repository:mm-weber/dhc" .specs/dhc-catalogue-mvp/tasks.md
grep -n "building every definition\|lists every definition" .specs/dhc-catalogue-mvp/tasks.md

echo
echo "== S5: renovate ignore mechanisms at the pinned version (network)"
curl -s -H "Accept: application/vnd.github.raw" \
  "https://api.github.com/repos/renovatebot/renovate/contents/lib/config/options/index.ts?ref=41.173.1" \
  -o "$SCRATCH/renovate-options.ts"
wc -l "$SCRATCH/renovate-options.ts"
grep -n "name: 'ignorePaths'" "$SCRATCH/renovate-options.ts"
grep -n "name: 'matchFileNames'" "$SCRATCH/renovate-options.ts"
grep -n "name: 'enabled'" "$SCRATCH/renovate-options.ts"
grep -n "name: 'ignoreDeps'" "$SCRATCH/renovate-options.ts"
echo "-- renovatebot/github-action v43.0.9 default renovate version:"
curl -s -H "Accept: application/vnd.github.raw" \
  "https://api.github.com/repos/renovatebot/github-action/contents/action.yml?ref=v43.0.9" \
  | grep -A 4 "renovate-version:"

echo
echo "== S6: subject facts"
git merge-base main spec-cleanup
git log --oneline -1 spec-cleanup
git diff main...spec-cleanup --shortstat
