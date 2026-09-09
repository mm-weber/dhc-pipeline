#!/usr/bin/env bash
# lint-active-set.sh [--changed <file>|-] [root]
#
# The validate-side lint of catalogue-policy.yaml's active set (task 14.2;
# Req 1.16, 1.18, 1.19). Four checks, each a violation by name:
#
#   1. The set is well-formed: read through definition-lib's
#      active_definitions, whose refusal (no or empty section, a duplicate,
#      an entry with no image/<name>/image.yaml, Req 1.19) is surfaced here.
#   2. The set splits no group (Req 1.18). A group is two definitions
#      publishing one repository (the runtime/variant pair lint-pins.sh holds
#      byte-equal) or several definitions bumped from one source repository
#      (Renovate groups them under Req 3.3): a bump moves all of them, so
#      activating some and not others leaves a bump nothing can merge.
#   3. Every chart directory declares the definitions it deploys
#      (chart/<c>/chart.yaml `deploys:`), each an existing definition; the
#      e2e matrix and the probe lint (14.3) map through this list.
#   4. With --changed, the pull request's changed paths (one per line, `-`
#      for stdin): a path under an inactive definition's directory or under a
#      chart deploying no active definition fails naming it (Req 1.16). Only
#      paths that exist in the tree count, so deleting a retired directory
#      passes; activating the definition in the same pull request passes too,
#      because the set is read from the tree under test.
#
# Nothing here reads Renovate's config: the tracking scope it renders
# (scripts/render-tracking.sh) is drift-checked separately. Exit 1 on any
# violation, 2 on a usage error.
set -euo pipefail

CHANGED=""
if [ "${1:-}" = "--changed" ]; then
  [ $# -ge 2 ] || { echo "usage: lint-active-set.sh [--changed <file>|-] [root]" >&2; exit 2; }
  CHANGED="$2"; shift 2
fi
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ROOT="${ROOT%/}"

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/definition-lib.sh
. "$HERE/definition-lib.sh"

violations=0
err() { echo "::error file=catalogue-policy.yaml::lint-active-set: $1"; violations=$((violations + 1)); }

if [ ! -f "$ROOT/catalogue-policy.yaml" ]; then
  echo "::error::lint-active-set: no catalogue-policy.yaml under ${ROOT} (Req 1.13)"
  exit 1
fi

# 1: the reader's refusal is the first violation
if ! active=$(active_definitions "$ROOT" 2>&1); then
  printf '%s\n' "$active"
  echo "lint-active-set: the active set is malformed (Req 1.19); nothing else checked"
  exit 1
fi
is_active() { printf '%s\n' "$active" | grep -qxF -- "$1"; }

all=""
for f in "$ROOT"/image/*/image.yaml; do
  [ -f "$f" ] || continue
  n="${f%/image.yaml}"; n="${n##*/}"
  all="${all:+$all
}$n"
done
inactive=$(printf '%s\n' "$all" | grep -vxF -f <(printf '%s\n' "$active") || true)

# 2: groups (Req 1.18), keyed on the published repository and on the source
# repository; a group with members on both sides of the set is a split
check_groups() { # label, key-function
  local label="$1" keyfn="$2" f n key
  declare -A members=()
  for f in "$ROOT"/image/*/image.yaml; do
    [ -f "$f" ] || continue
    n="${f%/image.yaml}"; n="${n##*/}"
    key=$("$keyfn" "$f")
    [ -n "$key" ] || continue
    members[$key]="${members[$key]:+${members[$key]} }$n"
  done
  for key in "${!members[@]}"; do
    local on="" off="" m
    for m in ${members[$key]}; do
      if is_active "$m"; then on="${on:+$on, }image/$m/"; else off="${off:+$off, }image/$m/"; fi
    done
    if [ -n "$on" ] && [ -n "$off" ]; then
      err "the active set splits the ${label} group '${key}': active ${on}; inactive ${off}. A bump moves the whole group, so activate or deactivate all of them (Req 1.18)"
    fi
  done
}
check_groups "published repository" published_repository
check_groups "source repository" source_repository

# 3: every chart directory declares what it deploys, each an existing definition
charts=0
declare -A chart_active=()
for d in "$ROOT"/chart/*/; do
  [ -d "$d" ] || continue
  c="${d%/}"; c="${c##*/}"
  charts=$((charts + 1))
  if [ ! -f "$d/chart.yaml" ] || [ -z "$(chart_deploys "$d/chart.yaml")" ]; then
    err "chart/${c}/ declares no deploys list in chart.yaml; every chart directory names the definitions it deploys (task 14.2, Req 5.2)"
    continue
  fi
  chart_active[$c]=0
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    if [ ! -f "$ROOT/image/$n/image.yaml" ]; then
      err "chart/${c}/chart.yaml deploys '${n}', but image/${n}/image.yaml does not exist"
      continue
    fi
    is_active "$n" && chart_active[$c]=1
  done < <(chart_deploys "$d/chart.yaml")
done

# 4: the pull request's changed paths against the frozen set (Req 1.16)
if [ -n "$CHANGED" ]; then
  if [ "$CHANGED" = "-" ]; then paths=$(cat); else paths=$(cat "$CHANGED"); fi
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -e "$ROOT/$p" ] || continue # a deletion is not a change to a frozen thing
    case "$p" in
      image/*/*)
        n="${p#image/}"; n="${n%%/*}"
        if printf '%s\n' "$inactive" | grep -qxF -- "$n"; then
          err "${p}: image/${n}/ is not in the active set, so this change cannot be built, tested or published; activate the definition in this pull request (active_set in catalogue-policy.yaml) or leave it frozen (Req 1.16)"
        fi ;;
      chart/*/*)
        c="${p#chart/}"; c="${c%%/*}"
        if [ "${chart_active[$c]:-0}" = "0" ]; then
          err "${p}: chart/${c}/ deploys no active definition, so this change has nothing to install; activate a definition it deploys or leave it frozen (Req 1.16)"
        fi ;;
    esac
  done <<<"$paths"
fi

if [ "$violations" -gt 0 ]; then
  echo "lint-active-set: ${violations} violation(s)"
  exit 1
fi
echo "lint-active-set: $(printf '%s\n' "$active" | grep -c .) active definition(s), $(printf '%s\n' "$inactive" | grep -c . || true) inactive, ${charts} chart director(ies) with a deploys list; no group split (Req 1.16, 1.18, 1.19)"
