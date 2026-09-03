#!/usr/bin/env bash
# lint-vex-product.sh [root] — check the product identifiers of every OpenVEX
# statement under triage/vex/ (Req 6.17-6.21, 6.31).
#
#   Req 6.17 — the product is an OCI purl naming an image this repo defines
#   Req 6.18 — its repository_url is that definition's published repository
#   Req 6.19 — the suppression is scoped by versionless subcomponent purls
#   Req 6.20 — a product version is a tag that definition publishes
#   Req 6.21 — a 'fixed' statement carries a version
#   Req 6.39 — a source statement records not_affected or fixed, nothing else
#   Req 6.31 — a versionless product says why its claim survives a bump
#
# A wrong product identifier produces no error of any kind. Trivy suppresses a
# finding only when the product AND the subcomponent match, and a statement that
# matches nothing is simply inert: the finding stays, and nothing anywhere says
# why. This repo lost a full day to exactly that.
#
# Nothing downstream closes the gap. The scan gate infers coverage from "did a
# finding disappear", which cannot tell a correct statement from an inert one,
# and scripts/compile-vex.sh strips the purl qualifiers while stamping in the
# build digest — the gate scans an image pushed to a throwaway local registry,
# because Trivy cannot build an OCI product purl without a RepoDigest (upstream
# #9399), and that registry's host is not ours. Measured: with the qualifiers
# stripped the gate still catches a wrong image name, a near-miss name, a wrong
# purl type and a wrong subcomponent — and nothing whatsoever about the registry
# host. This lint is the only check left on it, and it pays for that trade by
# comparing strings exactly rather than inferring from a disappearance.
#
# The recipes these rules enforce, and the Trivy behaviour behind them, are in
# triage/README.md (Authoring a statement).
set -euo pipefail

# published_repository() and definitions_publishing() — the directory-to-published-
# name mapping this shares with compile-vex.sh, lint-pins.sh and build.yml.
# shellcheck source=scripts/definition-lib.sh
. "$(cd "$(dirname "$0")" && pwd)/definition-lib.sh"

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
LANE="triage/vex"
violations=0
files=0
products=0
subcomponents=0

# A root that is not there is not a clean tree: reporting success for a path
# that holds nothing is the same invisible failure this lint exists to prevent,
# one level up.
if [ ! -d "$ROOT" ]; then
  echo "::error::VEX product identifier (Req 6.17): root '$ROOT' does not exist — no statement was checked"
  exit 1
fi

report() { # rel, requirement, message
  echo "::error file=$1::VEX product identifier (Req $2): $3"
  violations=$((violations + 1))
}

urldecode() { # percent-decode one purl qualifier value
  # Hex digits are case-insensitive (RFC 3986 §6.2.2.1), which %b honours, and
  # it stops after two of them — so a double-encoded value decodes to the
  # literal '%2F' text it really is rather than to a slash. Backslashes are
  # doubled first so %b cannot reinterpret one that was already in the value.
  local s="${1//\\/\\\\}"
  printf '%b' "${s//%/\\x}"
}

# The tags a definition publishes. A source product version has to be one of
# them (Req 6.20), because compile-vex.sh looks it up against the tags of the
# build and drops the statement when it does not match (Req 6.30).
published_tags() { # definition path
  awk '/^tags:[[:space:]]*$/ { intags = 1; next }
       intags && sub(/^[[:space:]]*-[[:space:]]*/, "") {
         sub(/[[:space:]]*#.*$/, ""); sub(/[[:space:]]+$/, "")
         gsub(/^["'\'']|["'\'']$/, "")
         print; next
       }
       intags && /^[^[:space:]]/ { intags = 0 }' "$1"
}

check_product() { # rel, cve, product purl, subcomponent count, status, status_notes
  local rel="$1" cve="$2" purl="$3" nsubs="$4" status="$5" notes="${6:-}"
  local rest type name version quals qrest q k v repo expected shown tags shown_defs d
  local -a defs

  # Rule 4 first, so a defect in the identifier cannot mask it: every recipe in
  # triage/README.md scopes the suppression to the one package that was
  # analysed, and an unscoped claim is a different, far broader statement.
  if [ "$nsubs" -eq 0 ]; then
    report "$rel" 6.19 "$cve product '$purl' lists no subcomponents — that excuses this CVE everywhere in the image rather than in the package actually analysed. Scope it with a versionless subcomponent purl (triage/README.md)"
  fi

  if [ -z "$purl" ]; then
    report "$rel" 6.17 "$cve carries a product with no '@id' — it names nothing and suppresses nothing"
    return
  fi
  if [ "${purl:0:4}" != "pkg:" ]; then
    report "$rel" 6.17 "$cve product '$purl' is not a package URL — Trivy matches its root component by purl, so a bare image reference matches nothing. Expected 'pkg:oci/<image>?repository_url=<published repository>'"
    return
  fi

  # purl grammar: pkg:type/namespace/name@version?qualifiers#subpath. Peel from
  # the right, because '/' and '@' both occur inside qualifier values (see the
  # unencoded repository_url below) and would otherwise be read as delimiters.
  rest="${purl#pkg:}"
  rest="${rest%%#*}"
  quals=""
  if [[ "$rest" == *\?* ]]; then
    quals="${rest#*\?}"
    rest="${rest%%\?*}"
  fi
  version=""
  if [[ "$rest" == *@* ]]; then
    version="${rest##*@}"
    rest="${rest%@*}"
  fi
  type="${rest%%/*}"; type="${type,,}"   # purl types are case-insensitive
  name="${rest##*/}"

  if [ "$type" != "oci" ]; then
    report "$rel" 6.17 "$cve product '$purl' has purl type '$type' — Trivy's root component for a container image is a 'pkg:oci/…' purl, so a '$type' purl is a valid identifier for something this scan never contains"
    return
  fi

  # Req 6.39. The hand-authored lane holds two answers to "does this apply?":
  # not_affected and fixed. Accepted risk and transfers are exceptions under
  # triage/accepted-risk/ (Req 6.8) that compile-vex.sh publishes as affected,
  # and under_investigation is what it derives from the attested report. Any
  # other status here is a decision written in the wrong lane, where nothing
  # time-boxes it and nothing publishes it with its reasoning, so it is named.
  case "$status" in
    not_affected|fixed) ;;
    *) report "$rel" 6.39 "$cve product '$purl' records status '${status:-<none>}': a source statement may only record not_affected or fixed. Accepted risk and transfers belong in triage/accepted-risk/ (Req 6.8) and are published as affected by the compiler; under_investigation is derived from the attested scan report" ;;
  esac
  # A remedy is always about particular versions, so a fixed claim has to name
  # one. Compared case-sensitively: OpenVEX status labels are a closed set of
  # lower-case strings, so no consumer reads 'Fixed' as the fixed label.
  if [ "$status" = "fixed" ] && [ -z "$version" ]; then
    report "$rel" 6.21 "$cve product '$purl' records status 'fixed' but carries no version — a fixed claim is about the versions that carry the remedy, and stated versionless it excuses this CVE on every image ever published under that name, including the older tag still pullable from the registry. Name the published tag the fix shipped in"
  fi

  # Req 6.31. Versionless claims every build of this image, including releases
  # nobody has examined yet, so a structural argument written about one release
  # keeps excusing the finding after a bump that changed what it links. Left to
  # a default every statement drifts here, because versionless suppresses most
  # and costs least to write — the note is what turns it back into a decision.
  if [ -z "$version" ] && [[ "$notes" != *"version-independent:"* ]]; then
    report "$rel" 6.31 "$cve product '$purl' carries no version, so it claims every build of this image — including releases nobody has examined yet — and its 'status_notes' does not say why the claim survives a version change. Either scope it to the published tag it was argued about, or write 'version-independent: <why>' into status_notes (triage/README.md)"
  fi

  # The purl name is the image; there is no "does this image exist" check
  # anywhere else, and a near-miss spelling reads correct while suppressing
  # nothing.
  mapfile -t defs < <(definitions_publishing "$ROOT" "$name")
  if [ "${#defs[@]}" -eq 0 ]; then
    report "$rel" 6.17 "$cve product '$purl' names image '$name', but no definition under image/ publishes a repository named '$name' — there is no 'image/$name/image.yaml', and no other definition's 'image:' ends in it. A variant publishes under its runtime sibling's name, so a definition's directory is never the product name"
    return
  fi
  shown_defs="$(printf '%s, ' "${defs[@]}")"; shown_defs="${shown_defs%, }"

  # A version in source is a scope, not an identifier: compile-vex.sh replaces
  # it with the digest of the image being scanned (6.29) and drops the statement
  # when the tag is not one of that build's (6.30). So a version that is not a
  # published tag is dropped on every build — it suppresses nothing and says
  # nothing, which is the inert case this lint exists to catch.
  # Unioned across every definition publishing this repository, because a
  # variant's release tags are as published as its runtime sibling's and both
  # arrive under the same product name. compile-vex.sh is what separates them:
  # it drops a statement whose tag is not one of the build's (Req 6.30), so the
  # tag stays the scope even though the name no longer distinguishes.
  if [ -n "$version" ]; then
    tags="$(for d in "${defs[@]}"; do published_tags "$ROOT/$d"; done | sort -u)"
    if [ -z "$tags" ]; then
      report "$rel" 6.20 "$cve product '$purl' pins version '$version', but '$shown_defs' declares no 'tags:' — there is no published tag this could scope to, so compilation drops it on every build"
    elif ! grep -qxF "$version" <<<"$tags"; then
      shown="$(tr '\n' ' ' <<<"$tags" | sed 's/ $//')"
      report "$rel" 6.20 "$cve product '$purl' pins version '$version', which '$shown_defs' does not publish — a source version is a published tag, and compilation looks it up against the build. A digest belongs in compiler output, never in source: it is unreviewable and goes stale at the next rebuild of the same release. Tags '$shown_defs' publishes: $shown"
    fi
  fi

  # Every definition in defs publishes the same repository by construction, so
  # the first is the comparison for all of them.
  expected="$(published_repository "$ROOT/${defs[0]}")"
  if [ -z "$expected" ]; then
    report "$rel" 6.18 "$cve product '$purl' resolves to '$shown_defs', which declares no 'image:' — there is no published repository to compare against"
    return
  fi

  # Qualifiers are an unordered set, so find repository_url by key rather than
  # by position, and compare decoded: an encoded value read against a decoded
  # one is what makes these mismatches hard to see by eye in the first place.
  repo=""
  qrest="$quals"
  while [ -n "$qrest" ]; do
    q="${qrest%%&*}"
    if [ "$q" = "$qrest" ]; then qrest=""; else qrest="${qrest#*&}"; fi
    case "$q" in
      *=*) k="${q%%=*}"; v="${q#*=}" ;;
      *) continue ;;
    esac
    if [ "${k,,}" = "repository_url" ]; then repo="$(urldecode "$v")"; fi
  done

  if [ -z "$repo" ]; then
    report "$rel" 6.18 "$cve product '$purl' carries no 'repository_url' value — Trivy's root component purl always has one, so a product without it matches nothing and the author gets no hint of that. Expected the repository '$shown_defs' publishes: '$expected' (slashes percent-encoded)"
  elif [ "$repo" != "$expected" ]; then
    report "$rel" 6.18 "$cve product '$purl' declares repository '$repo', but '$shown_defs' publishes '$expected' — Trivy compares this string exactly, so the statement is inert: the finding stays and nothing says why"
  fi
}

check_subcomponent() { # rel, cve, product purl, subcomponent purl
  local rel="$1" cve="$2" purl="$3" sub="$4" rest
  if [ "${sub:0:4}" != "pkg:" ]; then
    report "$rel" 6.19 "$cve subcomponent '$sub' of product '$purl' is not a package URL — Trivy matches subcomponents by purl, so a bare module path matches nothing. Expected 'pkg:golang/<module>'"
    return
  fi
  rest="${sub%%#*}"
  rest="${rest%%\?*}"
  if [[ "$rest" == *@* ]]; then
    report "$rel" 6.19 "$cve subcomponent '$sub' carries version '${rest##*@}' — module versions move on every upstream rebuild, so this stops matching at the next bump and says nothing when it does. A versionless purl still scopes the suppression to that one package (triage/README.md)"
  fi
}

# One \x1f-separated record per thing worth checking, so bash never parses JSON
# and an empty field stays an empty field (tab would collapse). Kinds:
#   D — the document declares no statements
#   N — a statement declares no products
#   P — a product, with its subcomponent count and its statement's status
#   S — one subcomponent of a product
# shellcheck disable=SC2016  # $e/$cve/$p/$subs/$st are jq bindings, not shell vars
JQ='
def vulnid:
  if (.vulnerability | type) == "string" then .vulnerability
  elif (.vulnerability | type) == "object" then (.vulnerability.name // .vulnerability["@id"] // "")
  else "" end;
def ident: if type == "object" then (.["@id"] // "") else tostring end;
# The status decides the product-version rule, and only the literal string
# "fixed" is that label: a missing status arrives as the empty string, and any
# other type arrives as its JSON rendering, which no shell comparison can
# mistake for a label the way a bare tostring of ["fixed"] might.
def statuslabel: if type == "string" then . elif . == null then "" else tojson end;
def rec: map(tostring) | join("\u001f");

if (.statements | type) != "array" or (.statements | length) == 0 then
  ["D", "", "", ""] | rec
else
  (.statements | to_entries[]) as $e
  | (if ($e.value | type) == "object" then ($e.value | vulnid) else "" end) as $v
  | (if $v == "" then "statement \($e.key)" else $v end) as $cve
  | if ($e.value | type) != "object"
       or ($e.value.products | type) != "array"
       or ($e.value.products | length) == 0 then
      ["N", $cve, "", ""] | rec
    else
      ($e.value.status | statuslabel) as $st
      | (($e.value.status_notes // "") | statuslabel
         | gsub("[\n\r]"; " ")) as $notes
      | ($e.value.products[]) as $p
      | ($p | ident) as $pid
      | (($p | if type == "object" then (.subcomponents // []) else [] end)
         | if type == "array" then . else [] end) as $subs
      | (["P", $cve, $pid, ($subs | length), $st, $notes] | rec),
        ($subs[] | ["S", $cve, $pid, ident] | rec)
    end
end
'

if [ -d "$ROOT/$LANE" ]; then
  while IFS= read -r -d '' f; do
    rel="${f#"$ROOT"/}"
    files=$((files + 1))

    # Unparseable JSON is loud, never skipped: skipping it would let a statement
    # stop being checked by breaking it, which is the one thing this lint cannot
    # allow. The other files are still checked.
    if ! records=$(jq -r "$JQ" "$f" 2>&1); then
      report "$rel" 6.17 "not readable as an OpenVEX document — $(printf '%s' "$records" | tr '\n\r\t' '   ')"
      continue
    fi

    file_products=0
    file_subs=0
    while IFS=$'\x1f' read -r kind cve pid sub status notes; do
      case "$kind" in
        D) report "$rel" 6.17 "document declares no 'statements' — committed weight that excuses nothing" ;;
        N) report "$rel" 6.17 "$cve declares no products — it names nothing, so it suppresses nothing" ;;
        P) file_products=$((file_products + 1)); check_product "$rel" "$cve" "$pid" "$sub" "$status" "$notes" ;;
        S) file_subs=$((file_subs + 1)); check_subcomponent "$rel" "$cve" "$pid" "$sub" ;;
      esac
    done <<<"$records"

    products=$((products + file_products))
    subcomponents=$((subcomponents + file_subs))
    # Name every file validated: a lint whose glob is wrong passes vacuously and
    # otherwise looks identical to a clean run.
    echo "lint-vex-product: $rel — $file_products product identifier(s), $file_subs subcomponent(s)"
  done < <(find "$ROOT/$LANE" -type f -name '*.json' -print0 | LC_ALL=C sort -z)
fi

if [ "$violations" -gt 0 ]; then
  echo "lint-vex-product: ${violations} violation(s) — see triage/README.md (Authoring a statement)"
  exit 1
fi
if [ "$files" -eq 0 ]; then
  echo "lint-vex-product: no statements under ${LANE}/ — nothing is excused yet"
  exit 0
fi
echo "lint-vex-product: ${products} product identifier(s) and ${subcomponents} subcomponent(s) in ${files} file(s) check out"
