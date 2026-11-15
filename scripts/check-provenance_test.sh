#!/usr/bin/env bash
# Tests for scripts/check-provenance.sh: the release's self-check. Before a
# release applies any tag, each pushed digest is asked the way a consumer
# would ask it: does it carry a SLSA provenance statement that the catalogue's
# verification policy would admit (Req 2.28)? cosign verify-attestation says
# whether the build workflow signed a statement of the provenance type, under
# the issuer and the releaser identity catalogue-policy.yaml declares; the
# script then holds the verified statement against five expectations derived
# from that identity (ADR 0005, decisions 2 and 5). cosign is stubbed: it logs
# its arguments and answers what the case laid down, in the shape cosign 2.6.5
# prints it (measured on 2026-11-15).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-provenance.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

# every sandbox lives under this one directory, removed when the suite ends
TOP=$(mktemp -d)
trap 'rm -rf "$TOP"' EXIT

# The sandbox's policy file differs from this repository's in every value the
# script reads, so that nothing written into the script can pass: an issuer
# other than GitHub's, and an identity with another owner, repository,
# workflow file and ref. The re-attester is listed before the releaser, the
# other way round than in this repository's file, and both attest the same
# types; case 1 asks again with the releaser first and the other role named to
# sort after it. So of a role's name, what it attests and its place in the
# file or among the sorted names, only the name finds the releaser both times.
ISSUER="https://issuer.example.test"
RELEASER="https://github.com/acme/widgets/.github/workflows/release.yml@refs/heads/trunk"
RE_ATTESTER="https://github.com/acme/widgets/.github/workflows/rescan.yml@refs/heads/trunk"
# the reference the cases ask about
REF="ghcr.io/acme/widgets@sha256:5b0f2a9c4d7e1836a0c9e2f4b6d8173955ae0c1f3e7d9b2a4c6e8f0a1b3d5c7e"
# The five values a statement must carry, as that releaser identity gives
# them: the identity itself (the builder), GitHub's build type, and the
# identity's three parts: source repository, workflow path, ref
BUILD_TYPE="https://actions.github.io/buildtypes/workflow/v1"
SOURCE="https://github.com/acme/widgets"
WORKFLOW=".github/workflows/release.yml"
GIT_REF="refs/heads/trunk"

fresh() {
  SB=$(mktemp -d "$TOP/sandbox.XXXXXX"); mkdir -p "$SB/root" "$SB/bin"; : > "$SB/cosign.log"
  cat > "$SB/root/catalogue-policy.yaml" <<EOF
verification:
  issuer: $ISSUER
  roles:
    re-attester:
      identity: $RE_ATTESTER
      attests: [spdxjson, cyclonedx, vuln, openvex]
    releaser:
      identity: $RELEASER
      attests: [spdxjson, cyclonedx, vuln, openvex]
EOF
  # what cosign 2.6.5 writes on stderr when it accepts, begun with an empty
  # line: the reference, the signing certificate's subject and issuer, then
  # the certificate's GitHub fields
  cat > "$SB/accepting.stderr" <<EOF

Verification for $REF --
The following checks were performed on each of these signatures:
  - Existence of the claims in the transparency log was verified offline
  - The code-signing certificate was verified using trusted certificate authority certificates
Certificate subject: $RELEASER
Certificate issuer URL: $ISSUER
GitHub Workflow Trigger: push
GitHub Workflow SHA: 0123456789abcdef0123456789abcdef01234567
GitHub Workflow Name: release
GitHub Workflow Repository: acme/widgets
GitHub Workflow Ref: $GIT_REF
EOF
  # cosign as a script: every call is logged, one line per call, "cosign" and
  # its arguments, each argument a word of its own (printf %q: an argument
  # with a blank in it shows quoted and never reads as two). Then it accepts
  # the way cosign does: on stdout the lines the case laid down in
  # $SB/envelopes.jsonl, one envelope per verified attestation, on stderr its
  # report, exit 0
  cat > "$SB/bin/cosign" <<'STUB'
#!/usr/bin/env bash
SB="$(cd "$(dirname "$0")/.." && pwd)"
{ printf 'cosign'; [ $# -gt 0 ] && printf ' %q' "$@"; echo; } >> "$SB/cosign.log"
cat "$SB/envelopes.jsonl"
cat "$SB/accepting.stderr" >&2
exit 0
STUB
  chmod +x "$SB/bin/cosign"
}

# An in-toto statement in the shape GitHub's provenance service writes it (the
# statement of the measuring run of 2026-11-13 is the model), from the five
# values the self-check holds it against, in the order of their names: builder
# identity, build type, source repository, workflow path, ref. Its subject is
# the digest the cases ask about.
statement() {
  jq -nc --arg builder "$1" --arg type "$2" --arg repository "$3" --arg path "$4" --arg ref "$5" \
    --arg name "${REF%@*}" --arg hex "${REF##*:}" \
    '{_type: "https://in-toto.io/Statement/v1",
      subject: [{name: $name, digest: {sha256: $hex}}],
      predicateType: "https://slsa.dev/provenance/v1",
      predicate: {
        buildDefinition: {
          buildType: $type,
          externalParameters: {workflow: {ref: $ref, repository: $repository, path: $path}},
          internalParameters: {github: {event_name: "push", repository_id: "1", repository_owner_id: "2", runner_environment: "github-hosted"}},
          resolvedDependencies: [{uri: "git+\($repository)@\($ref)", digest: {gitCommit: "0123456789abcdef0123456789abcdef01234567"}}]},
        runDetails: {
          builder: {id: $builder},
          metadata: {invocationId: "\($repository)/actions/runs/1/attempts/1"}}}}'
}

# Statements the way cosign prints the attestations it verified: one compact
# envelope per line, the statement base64 in .payload, no line break inside
# the base64.
envelopes() {
  local each
  for each in "$@"; do
    jq -nc --arg payload "$(printf '%s' "$each" | base64 -w0)" \
      '{payload: $payload, payloadType: "application/vnd.in-toto+json", signatures: [{sig: "c3R1Yg=="}]}'
  done
}

# The script the way the release job calls it, in the case's sandbox: the stub
# first on PATH, no pause between attempts. stdout and stderr are kept apart:
# in the sandbox's files stdout and stderr and, for the cases, in $out and
# $err; the exit code in $rc. Called as a plain command, never in $( ).
run() {
  PATH="$SB/bin:$PATH" CHECK_PROVENANCE_RETRY_DELAY=0 "$CHECK" "$@" > "$SB/stdout" 2> "$SB/stderr"; rc=$?
  out=$(cat "$SB/stdout"); err=$(cat "$SB/stderr")
}

# One line of the stub's log (stdin) as what that call asked: its first
# argument on the first line, then the others one per line and sorted, each of
# the three flags that carry a value on one line with it ("--type
# slsaprovenance1", also when it was given as --type=slsaprovenance1). Two
# calls compare equal whatever the order of their flags, and unequal on any
# argument less or more: every word the stub logged ends up on a line.
asked() {
  local -a words=(); local word i=2
  read -ra words || true
  [ "${#words[@]}" -gt 1 ] && printf '%s\n' "${words[1]}"
  while [ "$i" -lt "${#words[@]}" ]; do
    word=${words[$i]}; i=$((i + 1))
    case "$word" in
      --type|--certificate-oidc-issuer|--certificate-identity) printf '%s %s\n' "$word" "${words[$i]:-}"; i=$((i + 1)) ;;
      --type=*|--certificate-oidc-issuer=*|--certificate-identity=*) printf '%s %s\n' "${word%%=*}" "${word#*=}" ;;
      *) printf '%s\n' "$word" ;;
    esac
  done | LC_ALL=C sort
}

# 1: a digest whose provenance meets all five passes (plan slice 2.5.1, the
#    tracer). cosign answers one envelope whose statement carries the five
#    values the releaser identity gives: the identity itself as the builder,
#    GitHub's build type, the identity's repository, workflow path and ref.
#    Wanted: exit 0; stdout is one line and no more (a whole line, ended by
#    its newline), begun "check-provenance: " and naming the reference in
#    full; nothing on stderr, cosign's own report is the script's to read and
#    not to pass on; cosign called once, as verify-attestation with --type
#    slsaprovenance1, the issuer and the releaser's identity of the sandbox's
#    policy file, and the reference. The arguments are compared as a whole
#    set: the order of the flags is free (and --flag=value is --flag value),
#    but an argument less fails and so does any argument more, so that no
#    flag that weakens the check rides along: --check-claims=false,
#    --insecure-ignore-tlog, an identity by pattern
#    (--certificate-identity-regexp) in place of the exact one, a second
#    reference.
#    The same question is then asked a second time, over a policy file that
#    differs in two things: the releaser is listed first, and the other role
#    is named "scanner", which sorts after "releaser". So the releaser's place
#    changes both in the file and among the sorted names. A script that takes
#    the role by a place in either (the first, the second, the last, the first
#    or the last that attests a type) asks with the other role's identity one
#    of the two times; a script that takes it by its name asks with the
#    releaser's both times. The second time holds what the roles' order and
#    names can change: the exit code, and the one call with the same arguments
fresh
envelopes "$(statement "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$GIT_REF")" > "$SB/envelopes.jsonl"
run verify "$SB/root" "$REF"
[ "$rc" -eq 0 ] \
  && pass "a digest whose provenance meets all five expectations: exit 0" \
  || fail "a digest whose provenance meets all five expectations: the exit code" "exit=$rc, wanted 0" "stdout:" "${out:-nothing}" "stderr:" "${err:-nothing}"
lines=$(grep -c '' "$SB/stdout"); ended=$(wc -l < "$SB/stdout")
[ "$lines" -eq 1 ] && [ "$ended" -eq 1 ] && [[ "$out" == "check-provenance: "* ]] && [[ "$out" == *"$REF"* ]] \
  && pass "stdout is one line, begun 'check-provenance: ' and naming the reference in full" \
  || fail "stdout: one line, begun 'check-provenance: ' and naming the reference in full" "lines on stdout: $lines, of them ended by a newline: $ended, wanted 1 and 1" "stdout:" "${out:-nothing}" \
       "wanted: one line begun 'check-provenance: ' that carries $REF"
[ ! -s "$SB/stderr" ] \
  && pass "nothing on stderr: cosign's own report is not passed on" \
  || fail "stderr: nothing, cosign's own report is the script's to read and not to pass on" "stderr:" "$(cat "$SB/stderr")" "wanted: nothing"
calls=$(grep -c '' "$SB/cosign.log")
[ "$calls" -eq 1 ] \
  && pass "cosign is called once" \
  || fail "the cosign calls the stub logged: one" "calls logged: $calls, wanted 1:" "$([ -s "$SB/cosign.log" ] && cat "$SB/cosign.log" || echo "cosign was never called")"
want=$(echo verify-attestation; printf '%s\n' "--type slsaprovenance1" "--certificate-oidc-issuer $ISSUER" "--certificate-identity $RELEASER" "$REF" | LC_ALL=C sort)
got=$(head -n 1 "$SB/cosign.log" | asked)
[ "$got" = "$want" ] \
  && pass "the call is verify-attestation with --type slsaprovenance1, the policy file's issuer, the releaser's identity and the reference, and not one argument more" \
  || fail "the cosign call's arguments as a whole set: verify-attestation, --type slsaprovenance1, the policy file's issuer, the releaser's identity, the reference, nothing else" \
       "the call as the stub logged it:" "$([ -s "$SB/cosign.log" ] && head -n 1 "$SB/cosign.log" || echo "cosign was never called")" \
       "what it asked (the first argument, then the others sorted, a flag on one line with its value):" "${got:-nothing}" \
       "wanted, the same way:" "$want"
# the second time: the releaser listed first, and the other role under a
# name that sorts after "releaser"
fresh
cat > "$SB/root/catalogue-policy.yaml" <<EOF
verification:
  issuer: $ISSUER
  roles:
    releaser:
      identity: $RELEASER
      attests: [spdxjson, cyclonedx, vuln, openvex]
    scanner:
      identity: $RE_ATTESTER
      attests: [spdxjson, cyclonedx, vuln, openvex]
EOF
envelopes "$(statement "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$GIT_REF")" > "$SB/envelopes.jsonl"
run verify "$SB/root" "$REF"
[ "$rc" -eq 0 ] \
  && pass "the releaser listed first and the other role named scanner: exit 0" \
  || fail "the releaser listed first and the other role named scanner: the exit code" "exit=$rc, wanted 0" "stdout:" "${out:-nothing}" "stderr:" "${err:-nothing}"
calls=$(grep -c '' "$SB/cosign.log")
[ "$calls" -eq 1 ] \
  && pass "the releaser listed first and the other role named scanner: cosign is called once" \
  || fail "the releaser listed first and the other role named scanner: the cosign calls the stub logged: one" "calls logged: $calls, wanted 1:" "$([ -s "$SB/cosign.log" ] && cat "$SB/cosign.log" || echo "cosign was never called")"
got=$(head -n 1 "$SB/cosign.log" | asked)
[ "$got" = "$want" ] \
  && pass "the releaser listed first and the other role named scanner: the same call, with the releaser's identity again" \
  || fail "the releaser listed first and the other role named scanner: the cosign call's arguments as a whole set, the same as before, the releaser's identity again" \
       "the call as the stub logged it:" "$([ -s "$SB/cosign.log" ] && head -n 1 "$SB/cosign.log" || echo "cosign was never called")" \
       "what it asked (the first argument, then the others sorted, a flag on one line with its value):" "${got:-nothing}" \
       "wanted, the same way:" "$want"

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all check-provenance tests passed"
