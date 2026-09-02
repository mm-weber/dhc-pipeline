#!/usr/bin/env bash
# Tests for scripts/check-visibility.sh: the first daily invariant (task 9.4,
# Req 2.21).
#
# The requirement, in one breath: WHILE public release is enabled, every
# catalogue repository must hand a pull token to an UNAUTHENTICATED request
# and serve every catalogue tag's manifest to one, and every repository or
# tag that does not is a failure of that run, by name. A token is not a pull
# (a public repository whose tags were deleted still issues one), which is
# why both probes exist.
#
# curl is stubbed; what the suite pins is the probes (anonymous, correct
# URLs), the verdicts and the naming. Measured context: on 2026-08-21 two
# repositories were quietly private and nothing said so until a human looked.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-visibility.sh"
FAILURES=0

pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

fresh() { # fixture: policy + two definitions (one shared repo), enumeration
  SB=$(mktemp -d)
  mkdir -p "$SB/root/image/solo" "$SB/root/image/valkey" "$SB/root/image/valkey-compat" "$SB/bin"
  cat > "$SB/root/catalogue-policy.yaml" <<'EOF'
release:
  public: true
verification:
  registry: ghcr.io/acme/dhc
EOF
  printf 'image: ghcr.io/acme/dhc/solo\n'   > "$SB/root/image/solo/image.yaml"
  printf 'image: ghcr.io/acme/dhc/valkey\n' > "$SB/root/image/valkey/image.yaml"
  printf 'image: ghcr.io/acme/dhc/valkey\n' > "$SB/root/image/valkey-compat/image.yaml"
  # Enumeration rows (9.3's shape); two platform rows share one tag, which
  # must become ONE manifest probe, and the digest columns are noise here.
  cat > "$SB/enum.tsv" <<'EOF'
ghcr.io/acme/dhc/solo	1-alpine3.23	sha256:11	linux/amd64	sha256:12	supported
ghcr.io/acme/dhc/valkey	9-alpine3.23	sha256:21	linux/amd64	sha256:22	supported
ghcr.io/acme/dhc/valkey	9-alpine3.23	sha256:21	linux/arm64	sha256:23	supported
ghcr.io/acme/dhc/valkey	9.0.5-alpine3.23	sha256:31	linux/amd64	sha256:32	superseded
EOF

  cat > "$SB/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "curl $*" >> "${STUB_ARGV}"
url="${@: -1}"
case "$url" in
  *"/token?"*)
    case "$url" in *"${STUB_TOKEN_FAIL:-@@none@@}"*) echo 403; exit 0 ;; esac
    # -w '%{http_code}' with -o: the body goes to the file, the code to stdout.
    for a in "$@"; do prev="${prev:-}"; [ "${prev:-}" = "-o" ] && printf '{"token":"anon-fixture-token"}' > "$a"; prev="$a"; done
    echo 200; exit 0 ;;
  *"/manifests/"*)
    case "$url" in *"${STUB_MANIFEST_FAIL:-@@none@@}"*) echo 404; exit 0 ;; esac
    echo 200; exit 0 ;;
esac
echo "curl stub: unexpected url $url" >&2; exit 64
STUB
  chmod +x "$SB/bin/curl"
  export STUB_ARGV="$SB/argv"
  unset STUB_TOKEN_FAIL STUB_MANIFEST_FAIL
  : > "$SB/argv"
}

run() { PATH="$SB/bin:$PATH" "$CHECK" "$SB/root" "$SB/enum.tsv" 2>&1; }

# 1: everything public: exit 0, and the probe set is exactly two token
#    probes (repos are a SET: valkey twice-defined probes once) plus three
#    manifest probes (platform rows dedup to tags).
fresh
out=$(run); rc=$?
[ "$rc" -eq 0 ] && pass "all public exits 0" || fail "all public exits 0" "$out"
n_tok=$(grep -c "/token?" "$SB/argv"); n_man=$(grep -c "/manifests/" "$SB/argv")
[ "$n_tok" = "2" ] && pass "one token probe per repository" || fail "one token probe per repository" "got $n_tok" "$(cat "$SB/argv")"
[ "$n_man" = "3" ] && pass "one manifest probe per tag" || fail "one manifest probe per tag" "got $n_man" "$(cat "$SB/argv")"

# 2: the probes are the design's: anonymous token by pull scope, manifest by
#    v2 URL with the anonymous token, and no ambient credentials anywhere.
grep -qF "https://ghcr.io/token?scope=repository:acme/dhc/solo:pull" "$SB/argv" \
  && pass "token probe carries the pull scope" || fail "token probe carries the pull scope" "$(cat "$SB/argv")"
grep -qF "https://ghcr.io/v2/acme/dhc/valkey/manifests/9-alpine3.23" "$SB/argv" \
  && pass "manifest probe uses the v2 endpoint" || fail "manifest probe uses the v2 endpoint" "$(cat "$SB/argv")"
grep -q -- "-u \|--user \|--netrc" "$SB/argv" \
  && fail "no credentials are ever sent" "$(cat "$SB/argv")" || pass "no credentials are ever sent"
grep -qF "Authorization: Bearer anon-fixture-token" "$SB/argv" \
  && pass "the manifest probe uses the anonymous token" || fail "the manifest probe uses the anonymous token" "$(cat "$SB/argv")"

# 3: a repository that answers the token probe with anything but 200 fails
#    the run and is named.
fresh
export STUB_TOKEN_FAIL="acme/dhc/solo"
out=$(run); rc=$?
[ "$rc" -ne 0 ] && pass "a private repository fails the run" || fail "a private repository fails the run" "$out"
grep -q "solo" <<<"$out" && pass "naming the repository" || fail "naming the repository" "$out"

# 4: a tag whose manifest is not served fails the run and is named — the
#    token alone proves nothing (a public repo with deleted tags still
#    issues one).
fresh
export STUB_MANIFEST_FAIL="valkey/manifests/9.0.5-alpine3.23"
out=$(run); rc=$?
[ "$rc" -ne 0 ] && pass "an unservable tag fails the run" || fail "an unservable tag fails the run" "$out"
grep -q "valkey:9.0.5-alpine3.23" <<<"$out" && pass "naming repository:tag" || fail "naming repository:tag" "$out"

# 5: every failure is reported, not just the first (the run fails once, the
#    operator reads the whole list).
fresh
export STUB_TOKEN_FAIL="acme/dhc/solo" STUB_MANIFEST_FAIL="9.0.5-alpine3.23"
out=$(run)
grep -q "solo" <<<"$out" && grep -q "9.0.5-alpine3.23" <<<"$out" \
  && pass "all failures are listed" || fail "all failures are listed" "$out"

# 6: WHILE public release is enabled — disabled means the invariant does not
#    apply, and no probe is sent at all.
fresh
cat > "$SB/root/catalogue-policy.yaml" <<'EOF'
release:
  public: false
verification:
  registry: ghcr.io/acme/dhc
EOF
out=$(run); rc=$?
[ "$rc" -eq 0 ] && pass "disabled public release exits 0" || fail "disabled public release exits 0" "$out"
[ ! -s "$SB/argv" ] && pass "and probes nothing" || fail "and probes nothing" "$(cat "$SB/argv")"
grep -qi "disabled" <<<"$out" && pass "saying why" || fail "saying why" "$out"

# 7: a missing enumeration is a refusal, not a vacuous pass — an invariant
#    verified against nothing has verified nothing.
fresh
rm "$SB/enum.tsv"
out=$(run); rc=$?
[ "$rc" -eq 2 ] && pass "a missing enumeration refuses with exit 2" || fail "a missing enumeration refuses with exit 2" "rc=$rc" "$out"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all check-visibility tests passed"
