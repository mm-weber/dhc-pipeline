#!/usr/bin/env bash
# Measurements for the 2026-08-25 greenfield-epoch independent review.
# Anonymous network reads only (ghcr.io token endpoint and registry API,
# api.github.com without a token, docs.github.com pages), plus local tree
# counts. Re-run from anywhere: paths resolve from this script's location.
# Output is captured in the sibling .measure.out file.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

section() { echo; echo "===== $1 ====="; }

section "1. ghcr repositories under mm-weber/dhc: anonymous token + tag lists"
# The seven definition directories map to how many registry repositories?
for name in hardened-app cert-manager-controller cert-manager-webhook \
            cert-manager-cainjector grafana valkey valkey-compat; do
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://ghcr.io/token?scope=repository:mm-weber/dhc/${name}:pull")
  tok=$(curl -s "https://ghcr.io/token?scope=repository:mm-weber/dhc/${name}:pull" \
    | jq -r '.token // empty')
  body=$(curl -s -H "Authorization: Bearer ${tok}" \
    "https://ghcr.io/v2/mm-weber/dhc/${name}/tags/list")
  if echo "$body" | jq -e '.tags' >/dev/null 2>&1; then
    total=$(echo "$body" | jq '.tags | length')
    catalogue=$(echo "$body" | jq '[.tags[] | select(startswith("sha256-") | not)] | length')
    echo "repo ${name}: token_http=${code} tags_total=${total} catalogue_tags=${catalogue}"
    echo "$body" | jq -r --arg n "$name" \
      '[.tags[] | select(startswith("sha256-") | not)] | "  catalogue tags: " + (join(" "))'
  else
    echo "repo ${name}: token_http=${code} error=$(echo "$body" | jq -c '.errors[0].code' 2>/dev/null)"
  fi
done

section "2. the ten legacy multi-arch tags named by critique F9 still resolve"
for ref in cert-manager-controller:1.20-alpine3.23 cert-manager-controller:1.20.3-alpine3.23 \
           cert-manager-controller:1.21.0-alpine3.23 cert-manager-webhook:1.20-alpine3.23 \
           cert-manager-webhook:1.20.3-alpine3.23 cert-manager-webhook:1.21.0-alpine3.23 \
           grafana:13.0-alpine3.23 grafana:13.0.4-alpine3.23 \
           valkey:9.0-alpine3.23 valkey:9.0.5-alpine3.23; do
  repo="${ref%%:*}"; tag="${ref##*:}"
  tok=$(curl -s "https://ghcr.io/token?scope=repository:mm-weber/dhc/${repo}:pull" | jq -r .token)
  code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${tok}" \
    -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json" \
    "https://ghcr.io/v2/mm-weber/dhc/${repo}/manifests/${tag}")
  echo "${ref}: manifest_http=${code}"
done

section "3. grafana 13.0.4-alpine3.23 index children (task 9.6's control digest)"
tok=$(curl -s "https://ghcr.io/token?scope=repository:mm-weber/dhc/grafana:pull" | jq -r .token)
curl -s -H "Authorization: Bearer ${tok}" \
  -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json" \
  "https://ghcr.io/v2/mm-weber/dhc/grafana/manifests/13.0.4-alpine3.23" \
  | jq -c '[.manifests[] | {digest: .digest[0:19], platform: ((.platform.os // "?") + "/" + (.platform.architecture // "?"))}]'

section "4. grafana 13.1.3-alpine3.23: digest and OpenVEX attestation count"
digest=$(curl -s -o /dev/null -D - -H "Authorization: Bearer ${tok}" \
  -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json" \
  "https://ghcr.io/v2/mm-weber/dhc/grafana/manifests/13.1.3-alpine3.23" \
  | tr -d '\r' | awk 'tolower($1)=="docker-content-digest:" {print $2}')
echo "13.1.3-alpine3.23 index digest: ${digest}"
att_tag="sha256-${digest#sha256:}.att"
echo "predicateType counts on ${att_tag}:"
curl -s -H "Authorization: Bearer ${tok}" -H "Accept: application/vnd.oci.image.manifest.v1+json" \
  "https://ghcr.io/v2/mm-weber/dhc/grafana/manifests/${att_tag}" \
  | jq -r '.layers[] | .annotations["predicateType"]' | sort | uniq -c

section "5. GitHub packages API needs authentication (anonymous probe)"
curl -s -o /dev/null -w "GET /users/mm-weber/packages/container/dhc%%2Fgrafana -> %{http_code}\n" \
  "https://api.github.com/users/mm-weber/packages/container/dhc%2Fgrafana"

section "6. live rulesets: required checks and bypass actors (anonymous)"
curl -s "https://api.github.com/repos/mm-weber/dhc-pipeline/rulesets" \
  | jq -c '.[] | {id, name, enforcement}'
curl -s "https://api.github.com/repos/mm-weber/dhc-pipeline/rulesets/20716271" \
  | jq -c '{name, bypass_actors, required_checks: [.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context]}'

section "7. documented deletion and visibility semantics (docs.github.com)"
curl -s "https://docs.github.com/en/packages/learn-github-packages/deleting-and-restoring-a-package" -o "$TMP/del.html"
curl -s "https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility" -o "$TMP/vis.html"
python3 - "$TMP" <<'EOF'
import re, html, sys
tmp = sys.argv[1]
def text(fn):
    t = open(fn, encoding='utf-8', errors='ignore').read()
    t = re.sub(r'<script.*?</script>', ' ', t, flags=re.S)
    t = re.sub(r'<style.*?</style>', ' ', t, flags=re.S)
    t = re.sub(r'<[^>]+>', ' ', t)
    t = html.unescape(t)
    return re.sub(r'\s+', ' ', t)
d = text(tmp + '/del.html')
v = text(tmp + '/vis.html')
pats = [
    (d, r'You cannot delete a public package if any version of the package has more than 5,000 downloads[^.]*\.'),
    (d, r'A specific version of a public package, if the package version doesn\'t have more than 5,000 downloads'),
    (d, r'You restore the package within 30 days of its deletion\.'),
    (d, r'The same package namespace is still available and not used for a new package\.'),
    (d, r'GitHub Packages only supports authentication using a personal access token \(classic\)\.'),
    (v, r'When you first publish a package that is scoped to your personal account, the default visibility is private[^.]*\.'),
]
for t, p in pats:
    m = re.search(p, t)
    print(('FOUND: ' + m.group(0)) if m else ('NOT FOUND: /' + p + '/'))
print('last-version phrasing on either page:',
      bool(re.search(r'last version', d, re.I) or re.search(r'last version', v, re.I)))
EOF

section "8. local tree counts (worktree state, no prose quoted)"
echo "accepted-risk entries in triage/accepted-risk/grafana.yaml: $(grep -c '^  - id:' "$ROOT/triage/accepted-risk/grafana.yaml")"
echo "entries expiring 2026-10-04: $(grep -c 'expired_at: 2026-10-04' "$ROOT/triage/accepted-risk/grafana.yaml")"
echo "entries expiring 2026-11-02: $(grep -c 'expired_at: 2026-11-02' "$ROOT/triage/accepted-risk/grafana.yaml")"
echo "oss/release matchString lines in renovate.json5: $(grep -c 'oss/release' "$ROOT/renovate.json5")"
echo "oss/release alias handling in scripts/refresh-grafana.sh at lines: $(grep -n 'oss/release' "$ROOT/scripts/refresh-grafana.sh" | cut -d: -f1 | tr '\n' ' ')"
echo "oss/release alias tests in scripts/refresh-grafana_test.sh at lines: $(grep -n 'oss/release' "$ROOT/scripts/refresh-grafana_test.sh" | cut -d: -f1 | tr '\n' ' ')"
echo "rescan dedup searches open issues only, rescan.yml line: $(grep -n 'state open' "$ROOT/.github/workflows/rescan.yml" | cut -d: -f1)"
echo "closed-state dedup specified only in task 10.6, tasks.md line: $(grep -n 'state closed' "$ROOT/.specs/dhc-catalogue-mvp/tasks.md" | cut -d: -f1)"
echo "digest pins in chart values files:"
grep -c 'sha256:' "$ROOT"/chart/*/config/values-hardened.yaml "$ROOT/chart/hardened-app/values.yaml"
echo "definitions and their published repositories (image: field):"
grep -h '^image:' "$ROOT"/image/*/image.yaml | sort | uniq -c
