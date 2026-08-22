#!/usr/bin/env bash
# Anonymous, read-only measurement of ghcr.io/mm-weber/dhc for the PR #97 review.
set -uo pipefail
R=mm-weber/dhc
ACC='application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'
tok() { curl -fsS --max-time 20 "https://ghcr.io/token?scope=repository:${R}/$1:pull" | jq -r .token; }
hdr_digest() { curl -fsSI --max-time 20 -H "Authorization: Bearer $2" -H "Accept: $ACC" "https://ghcr.io/v2/${R}/$1/manifests/$3" | tr -d '\r' | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}'; }
manifest() { curl -fsS --max-time 20 -H "Authorization: Bearer $2" -H "Accept: $ACC" "https://ghcr.io/v2/${R}/$1/manifests/$3"; }
code() { curl -s -o /dev/null --max-time 20 -w '%{http_code}' -I -H "Authorization: Bearer $2" -H "Accept: $ACC" "https://ghcr.io/v2/${R}/$1/manifests/$3"; }

echo "### visibility: anonymous token endpoint per repository"
for n in hardened-app cert-manager-controller cert-manager-webhook cert-manager-cainjector grafana valkey; do
  printf '  %-26s HTTP %s\n' "$n" "$(curl -s -o /dev/null --max-time 20 -w '%{http_code}' "https://ghcr.io/token?scope=repository:${R}/${n}:pull")"
done

for spec in hardened-app:0.1.0-alpine3.23 cert-manager-controller:1.21.1-alpine3.23 cert-manager-webhook:1.21.1-alpine3.23 cert-manager-cainjector:1.21.1-alpine3.23 grafana:13.1.3-alpine3.23 valkey:9.1.1-alpine3.23 valkey:9.1.1-alpine3.23-compat grafana:13.0.4-alpine3.23 valkey:9.0.5-alpine3.23 cert-manager-controller:1.20.3-alpine3.23; do
  name=${spec%%:*}; tag=${spec#*:}
  t=$(tok "$name") || { echo "== $name: no token"; continue; }
  d=$(hdr_digest "$name" "$t" "$tag")
  echo "== ${name}:${tag} -> ${d}"
  m=$(manifest "$name" "$t" "$tag") || { echo "  manifest fetch failed"; continue; }
  echo "  mediaType: $(jq -r '.mediaType // "?"' <<<"$m")"
  jq -r '.manifests[]? | "  child \(.digest) \(.platform.os // "-")/\(.platform.architecture // "-") \(.annotations["vnd.docker.reference.type"] // "")"' <<<"$m"
  sd=${d/:/-}
  echo "  on index digest: .sig HTTP $(code "$name" "$t" "${sd}.sig")  .att HTTP $(code "$name" "$t" "${sd}.att")"
  if att=$(manifest "$name" "$t" "${sd}.att" 2>/dev/null); then
    jq -r '.layers[]? | .annotations.predicateType // "?"' <<<"$att" | sort | uniq -c | sed 's/^/    att predicateType: /'
  fi
  for cd in $(jq -r '.manifests[]? | select((.platform.os // "") != "unknown") | .digest' <<<"$m"); do
    scd=${cd/:/-}
    echo "  on platform manifest ${cd:0:19}...: .sig HTTP $(code "$name" "$t" "${scd}.sig")  .att HTTP $(code "$name" "$t" "${scd}.att")"
  done
done
