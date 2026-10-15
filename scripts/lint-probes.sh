#!/usr/bin/env bash
# lint-probes.sh [root]
#
# Req 5.8 to 5.11 (tasks 14.3, 17.3): every active definition declares a
# functional proof, a chart's probe or a declared none, or validate fails
# naming the definition. A definition declares its probe
# through the chart that deploys it: chart/<c>/chart.yaml names the
# definitions it deploys (`deploys:`, task 14.2) and the probe the e2e suite
# runs once its pods are Ready (`probe:`, a registration name the suite's
# `probes` registry resolves, Req 5.5). One chart, one probe, however many
# definitions it deploys: the three cert-manager images are proved by one
# Certificate issuance, and the valkey pair by one SET and GET, executed once
# per install (Req 5.5's "shared" clause).
#
# YAML only: whether a declared name has a registration is the Go side's
# unit test (test/e2e, TestProbeDeclarations), so the two cannot drift
# without one of them going red. No placeholder exists on purpose: the
# answer to an uncovered active definition is a real probe or deactivation,
# never a probe that passes by doing nothing (the task 6.3 lesson: a box
# ticked for a probe the suite did not have). An inactive definition without
# a probe is not a violation; nothing installs it.
#
# A definition no chart deploys may instead declare, in catalogue-policy.yaml's
# `proofs:` map, a `none` proof with a reason and a review_by date, read through
# proof_entries (definition-lib.sh). A none proof is printed by name, with its reason
# and review date, and the definition passes (Req 5.9); the summary counts the
# none proofs beside the probe registrations. A none proof whose review_by date
# is strictly before today has lapsed and is a violation naming the definition
# and the date (Req 5.10); DHC_TODAY is the clock seam the tests set. A none
# proof is only for a definition no chart deploys: declaring one for a
# chart-deployed definition is a violation reported against that chart, since
# one proof per definition means the chart's probe is the proof (Req 5.9).
# The proofs map is read whole, up front, through proof_entries: its refusal
# (an unknown kind, a none proof without its reason or review_by, an entry
# naming a definition outside the active set) is the lint's failure by name
# and nothing is checked, as for a malformed active set (Req 5.11).
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ROOT="${ROOT%/}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/definition-lib.sh
. "$HERE/definition-lib.sh"
today="${DHC_TODAY:-$(date -u +%F)}"

violations=0
err() { echo "::error file=$1::lint-probes: $2"; violations=$((violations + 1)); }

if ! active=$(active_definitions "$ROOT" 2>&1); then
  printf '%s\n' "$active"
  echo "lint-probes: the active set is malformed; nothing checked (Req 5.8 binds to the active set)"
  exit 1
fi
if ! proofs=$(proof_entries "$ROOT" 2>&1); then
  printf '%s\n' "$proofs"
  echo "lint-probes: the proofs declaration is malformed; nothing checked (Req 5.11)"
  exit 1
fi
# The declaration per definition, keyed by name, from the one read above;
# a name with no entry is proved by a chart (the proof_of default).
declare -A proof_line=()
while IFS= read -r line; do
  [ -n "$line" ] || continue
  proof_line["${line%%$'\t'*}"]="$line"
done <<<"$proofs"

# Per chart: its probe (or empty) and the definitions it deploys.
declare -A probe_of=() charts_of=()
for d in "$ROOT"/chart/*/; do
  [ -d "$d" ] || continue
  c="${d%/}"; c="${c##*/}"
  f="$ROOT/chart/$c/chart.yaml"
  [ -f "$f" ] || continue
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    charts_of[$n]="${charts_of[$n]:+${charts_of[$n]} }$c"
  done < <(chart_deploys "$f")
  if p=$(chart_probe "$f" 2>/dev/null); then
    probe_of[$c]="$p"
  else
    err "chart/${c}/chart.yaml" "probe must be a registration name (a string) the e2e suite resolves; there is no placeholder shape (Req 5.5)"
    probe_of[$c]=""
  fi
done

count=0 nones=0
declare -A probes_used=()
while IFS= read -r n; do
  [ -n "$n" ] || continue
  count=$((count + 1))
  proof="${proof_line[$n]:-chart}"
  IFS=$'\t' read -r _ pkind preason preview <<<"$proof"
  if [ "$pkind" = none ]; then
    if [ -n "${charts_of[$n]:-}" ]; then
      for c in ${charts_of[$n]}; do
        err "chart/${c}/chart.yaml" "active definition '${n}' declares a proof of kind none, but chart/${c}/ deploys it; one proof per definition: the chart's probe proves it, so remove the stale proofs entry (Req 5.9)"
      done
      continue
    fi
    if [[ "$preview" < "$today" ]]; then
      err "catalogue-policy.yaml" "none proof for '${n}' lapsed on ${preview}; re-decide it with a fresh review-by date, or give the definition a chart with a probe (Req 5.10)"
      continue
    fi
    echo "lint-probes: ${n}: proof none, ${preason}, review by ${preview} (Req 5.9)"
    nones=$((nones + 1))
    continue
  fi
  if [ -z "${charts_of[$n]:-}" ]; then
    err "catalogue-policy.yaml" "active definition '${n}' is deployed by no chart, so no functional probe covers it; give it a chart with a probe, declare a proof of kind none for it with a reason and a review-by date, or deactivate it (Req 5.8)"
    continue
  fi
  covered=false
  for c in ${charts_of[$n]}; do
    if [ -n "${probe_of[$c]:-}" ]; then covered=true; probes_used["${c}:${probe_of[$c]}"]=1; fi
  done
  if [ "$covered" = false ]; then
    for c in ${charts_of[$n]}; do
      err "chart/${c}/chart.yaml" "active definition '${n}' is deployed by chart/${c}/ which declares no functional probe (probe:); declare one the e2e suite registers, or deactivate the definition (Req 5.8)"
    done
  fi
done <<<"$active"

if [ "$violations" -gt 0 ]; then
  echo "lint-probes: ${violations} violation(s) (Req 5.8 to 5.11)"
  exit 1
fi
echo "lint-probes: ${count} active definition(s): $((count - nones)) covered by ${#probes_used[@]} probe registration(s), each executed once per install, ${nones} declared none (Req 5.5, 5.8, 5.9)"
