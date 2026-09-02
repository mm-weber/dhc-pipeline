#!/usr/bin/env bash
# Tests for scripts/enumerate-catalogue.sh: the daily enumeration Req 2.22
# hangs everything on (task 9.3).
#
# What the suite pins is the enumeration contract, not any registry: crane and
# docker are stubbed. The contract, in one breath: every catalogue repository
# (the distinct `image:` values across definitions), every tag in it except
# cosign's sha256-* bookkeeping tags, each tag's digest taken as sha256 of the
# raw manifest bytes, every platform manifest of an index (unknown/unknown and
# BuildKit's reference-type annotation excluded, the Req 2 definition), a bare
# manifest standing for itself, and each row classified supported or
# superseded by whether a CURRENT definition lists the tag (requirements.md,
# Terms). Failures refuse loudly: a repository that cannot be listed or a
# manifest that cannot be read makes the enumeration a lie, and Req 2.22
# promises the enumeration itself.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ENUM="$HERE/enumerate-catalogue.sh"
FAILURES=0

pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

AMD="sha256:aaaa000000000000000000000000000000000000000000000000000000000000"
ARM="sha256:bbbb000000000000000000000000000000000000000000000000000000000000"

fresh() { # fixture tree: two definitions sharing one repo, plus one solo repo
  SB=$(mktemp -d)
  mkdir -p "$SB/root/image/valkey" "$SB/root/image/valkey-compat" "$SB/root/image/solo" "$SB/bin" "$SB/raw"

  cat > "$SB/root/image/valkey/image.yaml" <<'EOF'
name: Valkey 9.1.x
image: ghcr.io/acme/dhc/valkey
tags:
  - 9-alpine3.23
  - 9.1-alpine3.23
  - 9.1.2-alpine3.23
EOF
  # The variant publishes the SAME repository under its own tags — one repo,
  # two definitions, five supported tags (docs/CONVENTIONS.md "Naming").
  cat > "$SB/root/image/valkey-compat/image.yaml" <<'EOF'
name: Valkey compat
image: ghcr.io/acme/dhc/valkey
tags:
  - 9.1.2-compat-alpine3.23
  - 9-compat-alpine3.23
EOF
  cat > "$SB/root/image/solo/image.yaml" <<'EOF'
name: Solo
image: ghcr.io/acme/dhc/solo
tags:
  - 1-alpine3.23
EOF

  # Registry fixtures. valkey: a current tag (index, two platforms + one
  # attestation manifest) and a superseded one (bare manifest, the pre-buildx
  # shape). solo: one current tag.
  cat > "$SB/raw/valkey__9.1.2-alpine3.23" <<EOF
{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[
 {"mediaType":"application/vnd.oci.image.manifest.v1+json","digest":"${AMD}","size":1,"platform":{"architecture":"amd64","os":"linux"}},
 {"mediaType":"application/vnd.oci.image.manifest.v1+json","digest":"${ARM}","size":1,"platform":{"architecture":"arm64","os":"linux"}},
 {"mediaType":"application/vnd.oci.image.manifest.v1+json","digest":"sha256:cccc000000000000000000000000000000000000000000000000000000000000","size":1,"platform":{"architecture":"unknown","os":"unknown"},"annotations":{"vnd.docker.reference.type":"attestation-manifest"}}]}
EOF
  printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","config":{"digest":"sha256:dddd"},"layers":[]}' \
    > "$SB/raw/valkey__9.0.5-alpine3.23"
  cp "$SB/raw/valkey__9.1.2-alpine3.23" "$SB/raw/solo__1-alpine3.23"

  cat > "$SB/bin/crane" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "crane $*" >> "${STUB_ARGV}"
if [ "$1" = "ls" ]; then
  repo="${2##*/}"
  [ -n "${STUB_LS_FAIL:-}" ] && { echo "UNAUTHORIZED: listing $2" >&2; exit 1; }
  case "$repo" in
    valkey) printf '%s\n' 9.1.2-alpine3.23 9.0.5-alpine3.23 \
              sha256-9999999999999999999999999999999999999999999999999999999999999999.sig \
              sha256-9999999999999999999999999999999999999999999999999999999999999999.att ;;
    solo)   printf '%s\n' 1-alpine3.23 ;;
  esac
  exit 0
fi
echo "crane stub: unexpected args $*" >&2; exit 64
STUB

  cat > "$SB/bin/docker" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "docker $*" >> "${STUB_ARGV}"
if [ "$1 $2 $3 $4" = "buildx imagetools inspect --raw" ]; then
  ref="$5"; repo="${ref%%:*}"; repo="${ref%:*}"; tag="${ref##*:}"; repo="${repo##*/}"
  [ -n "${STUB_RAW_FAIL:-}" ] && { echo "no such manifest: $ref" >&2; exit 1; }
  f="${STUB_RAW_DIR}/${repo}__${tag}"
  [ -f "$f" ] || { echo "no such manifest: $ref" >&2; exit 1; }
  cat "$f"; exit 0
fi
echo "docker stub: unexpected args $*" >&2; exit 64
STUB
  chmod +x "$SB/bin/crane" "$SB/bin/docker"
  export STUB_ARGV="$SB/argv" STUB_RAW_DIR="$SB/raw"
  unset STUB_LS_FAIL STUB_RAW_FAIL
  : > "$SB/argv"
}

run() { PATH="$SB/bin:$PATH" "$ENUM" "$SB/root" "$SB/out.tsv" 2>&1; }

# 1: the full enumeration, shape and classification in one table.
fresh
out=$(run); rc=$?
[ "$rc" -eq 0 ] && pass "enumeration exits 0" || fail "enumeration exits 0" "$out"
idx_digest="sha256:$(sha256sum "$SB/raw/valkey__9.1.2-alpine3.23" | cut -d' ' -f1)"
bare_digest="sha256:$(sha256sum "$SB/raw/valkey__9.0.5-alpine3.23" | cut -d' ' -f1)"
want=$(cat <<EOF
ghcr.io/acme/dhc/solo	1-alpine3.23	${idx_digest}	linux/amd64	${AMD}	supported
ghcr.io/acme/dhc/solo	1-alpine3.23	${idx_digest}	linux/arm64	${ARM}	supported
ghcr.io/acme/dhc/valkey	9.0.5-alpine3.23	${bare_digest}	-	${bare_digest}	superseded
ghcr.io/acme/dhc/valkey	9.1.2-alpine3.23	${idx_digest}	linux/amd64	${AMD}	supported
ghcr.io/acme/dhc/valkey	9.1.2-alpine3.23	${idx_digest}	linux/arm64	${ARM}	supported
EOF
)
if [ "$(cat "$SB/out.tsv")" = "$want" ]; then pass "rows, digests and classification"; else
  fail "rows, digests and classification" "--- got ---" "$(cat "$SB/out.tsv")" "--- want ---" "$want"; fi

# 2: cosign's bookkeeping tags never become rows.
grep -q "sha256-9999" "$SB/out.tsv" && fail "cosign tags are excluded" "$(cat "$SB/out.tsv")" || pass "cosign tags are excluded"

# 3: the attestation manifest is not a platform manifest (Req 2 Terms).
grep -q "cccc0000" "$SB/out.tsv" && fail "attestation manifests are excluded" "$(cat "$SB/out.tsv")" || pass "attestation manifests are excluded"

# 4: a bare manifest stands for itself: its row carries its own digest twice.
n=$(awk -F'\t' '$2=="9.0.5-alpine3.23" && $3==$5 && $4=="-"' "$SB/out.tsv" | wc -l)
[ "$n" = "1" ] && pass "a bare manifest is one row for its own digest" || fail "a bare manifest is one row for its own digest" "$(cat "$SB/out.tsv")"

# 5: a compat tag is supported through its OWN definition, same repository.
fresh
printf '%s\n' 9.1.2-compat-alpine3.23 > /dev/null # (documenting intent)
cat > "$SB/bin/crane" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "crane $*" >> "${STUB_ARGV}"
case "${2##*/}" in
  valkey) printf '%s\n' 9.1.2-compat-alpine3.23 ;;
  solo)   printf '%s\n' 1-alpine3.23 ;;
esac
STUB
chmod +x "$SB/bin/crane"
cp "$SB/raw/valkey__9.1.2-alpine3.23" "$SB/raw/valkey__9.1.2-compat-alpine3.23"
run >/dev/null
grep -q "9.1.2-compat-alpine3.23	${idx_digest}	linux/amd64	${AMD}	supported" "$SB/out.tsv" \
  && pass "variant tags classify supported via their own definition" \
  || fail "variant tags classify supported via their own definition" "$(cat "$SB/out.tsv")"

# 6: an unlistable repository fails the enumeration by name — Req 2.22
#    promises the enumeration, so a partial one must not look complete.
fresh
export STUB_LS_FAIL=1
out=$(run); rc=$?
[ "$rc" -ne 0 ] && pass "an unlistable repository refuses" || fail "an unlistable repository refuses" "$out"
grep -q "ghcr.io/acme/dhc" <<<"$out" && pass "naming the repository" || fail "naming the repository" "$out"

# 7: an unreadable manifest refuses too, naming the ref.
fresh
export STUB_RAW_FAIL=1
out=$(run); rc=$?
[ "$rc" -ne 0 ] && pass "an unreadable manifest refuses" || fail "an unreadable manifest refuses" "$out"
grep -qE "valkey:9|solo:1" <<<"$out" && pass "naming the ref" || fail "naming the ref" "$out"

# 8: the invocations are the design's: crane lists, imagetools reads raw.
fresh
run >/dev/null
grep -qF "crane ls ghcr.io/acme/dhc/valkey" "$SB/argv" \
  && pass "lists tags with crane" || fail "lists tags with crane" "$(cat "$SB/argv")"
grep -qF "docker buildx imagetools inspect --raw ghcr.io/acme/dhc/valkey:9.1.2-alpine3.23" "$SB/argv" \
  && pass "reads the raw manifest by ref" || fail "reads the raw manifest by ref" "$(cat "$SB/argv")"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all enumerate-catalogue tests passed"
