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
# prints it (measured on 2026-11-15), or crashes with what a Go program that
# panics writes (measured too, see case 2's input with the trace).
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
  # with a blank in it shows quoted and never reads as two). A case that
  # wants cosign to refuse writes the number of calls to refuse to
  # $SB/refusals: while it is above 0 a call refuses the way cosign 2.6.5
  # does and counts it down by one; with no such file no call refuses. A
  # refusal leaves stdout empty, writes cosign's message twice on stderr,
  # first under the prefix "Error: " and then under "error during command
  # execution: ", and exits 1. The message of the n-th call, 1 for the first
  # (the calls are counted in the log), is the case's file $SB/refusal.<n>,
  # in cosign's words: one line, or more, each after the first begun with
  # one blank. A case that wants the n-th call to fail the way a Go program
  # that panics does lays down $SB/crash.<n>: that call leaves stdout empty,
  # writes the file on stderr as it is and exits 2, the countdown left alone.
  # A call that neither crashes nor refuses accepts the way cosign does: on
  # stdout the lines the case laid down in $SB/envelopes.jsonl, one envelope
  # per verified attestation, on stderr its report, exit 0
  cat > "$SB/bin/cosign" <<'STUB'
#!/usr/bin/env bash
SB="$(cd "$(dirname "$0")/.." && pwd)"
{ printf 'cosign'; [ $# -gt 0 ] && printf ' %q' "$@"; echo; } >> "$SB/cosign.log"
nth=$(grep -c '' "$SB/cosign.log")
if [ -f "$SB/crash.$nth" ]; then cat "$SB/crash.$nth" >&2; exit 2; fi
left=0; [ -f "$SB/refusals" ] && left=$(cat "$SB/refusals")
if [ "$left" -gt 0 ]; then
  echo "$((left - 1))" > "$SB/refusals"
  { printf 'Error: '; cat "$SB/refusal.$nth"; printf 'error during command execution: '; cat "$SB/refusal.$nth"; } >&2
  exit 1
fi
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

# 2: cosign refusing on every attempt fails the check naming the digest (plan
#    slice 2.5.2). cosign can fail for a cause that goes away by itself, a
#    registry that does not answer for a moment, so the script asks up to
#    three times; when all three attempts have failed, the check fails. The
#    stub is told to fail five calls in a row and would accept a sixth: a
#    script that asks more than three times, or until cosign accepts, comes
#    to its end and is seen in the number of calls.
#    Wanted: exit 1, whatever code cosign ended with; nothing on stdout, no
#    line there says the digest passed; on stderr one line begun
#    "::error::check-provenance: ", which names the reference next, ends
#    " (Req 2.28)", says "3 attempts" and carries what cosign said on its
#    third attempt, the last; every line on stderr the script's own, begun
#    "::error::check-provenance: " or "::warning::check-provenance: " and
#    ended by its newline, cosign's lines not passed on (the warning after a
#    failed attempt that another follows comes with slice 2.5.11: here it is
#    neither wanted nor refused); cosign called three times and no more, each
#    time with the whole argument set case 1 holds, so that no attempt asks a
#    weaker question than the first.
#    What cosign said: when cosign 2.6.5 refuses it prints its message twice,
#    under two prefixes, a message of several lines with one blank before
#    every line after the first (see fresh). The error line is wanted to
#    carry one of the two, the message itself: every line of it and none
#    twice, joined on one line, neither prefix, no two blanks in a row.
#    The question is put seven times, each time with other words of cosign's
#    or with none: what an input is there for is said where it is laid down.
# how many times the text is in what stdin gives
occurs() { grep -oF -- "$1" | grep -c ''; }
# cosign's words for a registry, asked by its name, that does not answer; the
# address the name led to ends in $1
unanswered() { printf 'Get "https://ghcr.io/v2/": dial tcp 192.0.2.%s:443: connect: connection refused\n' "$1"; }
# cosign's words for a registry that answers and refuses the request: ghcr.io
# asked without a login for a package that is not public. The address in them
# is written with percent signs
denied='GET https://ghcr.io/token?scope=repository%3Aacme%2Fwidgets%3Apull&service=ghcr.io: DENIED: requested access to the resource is denied'
# After a run, the lines on stderr begun "::error::check-provenance: ": the
# lines in $errors and their number in $count; $shaped says whether it is one
# line that names the reference next, ends " (Req 2.28)" and says
# "3 attempts"; $framed whether one of cosign's two prefixes is in it;
# $doubled whether two blanks in a row are
error_line() {
  errors=$(grep '^::error::check-provenance: ' "$SB/stderr"); count=$(grep -c '^::error::check-provenance: ' "$SB/stderr")
  shaped=no; [ "$count" -eq 1 ] && [[ "$errors" == "::error::check-provenance: $REF: "* ]] && [[ "$errors" == *" (Req 2.28)" ]] && [[ "$errors" == *"3 attempts"* ]] && shaped=yes
  framed=no; [[ "$errors" == *"Error: "* || "$errors" == *"error during command execution"* ]] && framed=yes
  doubled=no; [[ "$errors" == *"  "* ]] && doubled=yes
}
# a message of two lines on every call, a reason for each of two attestations
# beside the digest, the second reason the certificate's identity where
# another was asked for. Each of the five calls names another workflow file
# in it: the error line must carry the third call's and none of the other four
fresh
envelopes "$(statement "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$GIT_REF")" > "$SB/envelopes.jsonl" # what a sixth call is answered
echo 5 > "$SB/refusals"
lead="no matching attestations: offline verification failed"
mismatch="none of the expected identities matched what was in the certificate"
declare -a reasons=()
nth=0
for file in first second third fourth fifth; do
  nth=$((nth + 1))
  reasons[$nth]="$mismatch, got subjects [$SOURCE/.github/workflows/$file.yml@$GIT_REF] with issuer $ISSUER"
  printf '%s\n' "$lead" " ${reasons[$nth]}" > "$SB/refusal.$nth"
done
run verify "$SB/root" "$REF"
what="cosign refusing on every attempt"
[ "$rc" -eq 1 ] \
  && pass "$what: exit 1" \
  || fail "$what: the exit code" "exit=$rc, wanted 1" "stdout:" "${out:-nothing}" "stderr:" "${err:-nothing}"
[ ! -s "$SB/stdout" ] \
  && pass "$what: nothing on stdout" \
  || fail "$what: stdout: nothing, no line says the digest passed" "stdout:" "$(cat "$SB/stdout")" "wanted: nothing"
error_line
[ "$shaped" = yes ] \
  && pass "$what: one error line on stderr, begun '::error::check-provenance: ' and the reference, ended ' (Req 2.28)', that says '3 attempts'" \
  || fail "$what: stderr: one line begun '::error::check-provenance: ', and it names the reference next, ends ' (Req 2.28)' and says '3 attempts'" \
       "lines on stderr begun '::error::check-provenance: ': $count, wanted 1" "stderr:" "${err:-nothing}" \
       "wanted: ::error::check-provenance: $REF: <why, saying '3 attempts'> (Req 2.28)"
carried=""
for nth in 1 2 3 4 5; do [[ "$errors" == *"${reasons[$nth]}"* ]] && carried="$carried $nth"; done
[ "$carried" = " 3" ] \
  && pass "$what: the error line carries what cosign said on its third attempt, and on no other" \
  || fail "$what: the error line carries the identity cosign named on its third attempt, and that of no other attempt" \
       "attempts whose identity is in the error line:${carried:- none}, wanted: 3" "the error line:" "${errors:-none}" \
       "what cosign named on its third attempt:" "${reasons[3]}"
leads=$(occurs "$lead" <<<"$errors"); mismatches=$(occurs "$mismatch" <<<"$errors")
[ "$leads" -eq 1 ] && [ "$mismatches" -eq 1 ] && [ "$framed" = no ] && [ "$doubled" = no ] \
  && pass "$what: the error line carries cosign's message, both lines and each once, without cosign's prefixes and without two blanks in a row" \
  || fail "$what: the error line carries cosign's message itself: both its lines, each once, neither of cosign's two prefixes, no two blanks in a row" \
       "times the message's first line is in the error line: $leads, wanted 1 ('$lead')" \
       "times its second line is: $mismatches, wanted 1 ('$mismatch ...')" \
       "one of the prefixes 'Error: ' and 'error during command execution' in it: $framed, wanted no" \
       "two blanks in a row in it: $doubled, wanted no" \
       "the error line:" "${errors:-none}"
other=$(grep -vc -e '^::error::check-provenance: ' -e '^::warning::check-provenance: ' "$SB/stderr")
lines=$(grep -c '' "$SB/stderr"); ended=$(wc -l < "$SB/stderr")
[ "$other" -eq 0 ] && [ "$lines" -eq "$ended" ] \
  && pass "$what: every line on stderr is the script's own and a whole line, cosign's lines are not passed on" \
  || fail "$what: stderr: every line begun '::error::check-provenance: ' or '::warning::check-provenance: ' and ended by its newline, cosign's own lines are not passed on" \
       "lines begun otherwise: $other, wanted 0" "lines on stderr: $lines, of them ended by a newline: $ended, wanted the same number" "stderr:" "${err:-nothing}"
calls=$(grep -c '' "$SB/cosign.log")
[ "$calls" -eq 3 ] \
  && pass "$what: cosign is called three times and no more" \
  || fail "$what: the cosign calls the stub logged: three" "calls logged: $calls, wanted 3:" "$([ -s "$SB/cosign.log" ] && cat "$SB/cosign.log" || echo "cosign was never called")"
# $want is still case 1's: the call's whole argument set
same=0
for nth in 1 2 3; do [ "$(sed -n "${nth}p" "$SB/cosign.log" | asked)" = "$want" ] && same=$((same + 1)); done
[ "$same" -eq 3 ] \
  && pass "$what: each of the three calls asks what case 1's call asks, not one argument less or more" \
  || fail "$what: each of the first three cosign calls has the argument set case 1 holds, as a whole set" \
       "of the first three calls, those that have it: $same, wanted 3" \
       "the calls as the stub logged them:" "$([ -s "$SB/cosign.log" ] && cat "$SB/cosign.log" || echo "cosign was never called")" \
       "wanted of each (the first argument, then the others sorted, a flag on one line with its value):" "$want"
# a message of one line that ends in a blank, on the third call: what cosign
# says when no attestation is stored beside the digest. The other four calls
# are told that the registry does not answer, in cosign's words for a
# registry asked by its name, each time under another address
fresh
envelopes "$(statement "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$GIT_REF")" > "$SB/envelopes.jsonl"
echo 5 > "$SB/refusals"
for nth in 1 2 4 5; do unanswered "$nth" > "$SB/refusal.$nth"; done
printf '%s\n' "no matching attestations: " > "$SB/refusal.3"
run verify "$SB/root" "$REF"
what="cosign refusing, its message one line that ends in a blank"
[ "$rc" -eq 1 ] \
  && pass "$what: exit 1" \
  || fail "$what: the exit code" "exit=$rc, wanted 1" "stdout:" "${out:-nothing}" "stderr:" "${err:-nothing}"
error_line
said=$(occurs "no matching attestations:" <<<"$errors")
[[ "$errors" == *"connection refused"* ]] && unreachable=yes || unreachable=no
[ "$shaped" = yes ] && [ "$said" -eq 1 ] && [ "$unreachable" = no ] && [ "$framed" = no ] && [ "$doubled" = no ] \
  && pass "$what: the one error line names the reference, says '3 attempts' and carries the third attempt's message once, its blank not doubling the next" \
  || fail "$what: the error line on stderr" \
       "one line begun '::error::check-provenance: ' and the reference, ended ' (Req 2.28)', that says '3 attempts': $shaped, wanted yes (lines begun '::error::check-provenance: ': $count)" \
       "times 'no matching attestations:', the third attempt's message, is in it: $said, wanted 1" \
       "'connection refused', what the other four attempts were told, in it: $unreachable, wanted no" \
       "one of the prefixes 'Error: ' and 'error during command execution' in it: $framed, wanted no" \
       "two blanks in a row in it, as the message's own blank before ' (Req 2.28)' would make them: $doubled, wanted no" \
       "stderr:" "${err:-nothing}"
calls=$(grep -c '' "$SB/cosign.log")
[ "$calls" -eq 3 ] \
  && pass "$what: cosign is called three times and no more" \
  || fail "$what: the cosign calls the stub logged: three" "calls logged: $calls, wanted 3"
# a message of four lines on the third call, a reason for each of four
# attestations, the same reason in its first three, its second and third line
# alike. The first call is told that nothing is stored beside the digest, the
# second that the registry refuses the request: the script asks again after
# either as after any other refusal. The fourth and the fifth call are told
# that the registry does not answer
fresh
envelopes "$(statement "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$GIT_REF")" > "$SB/envelopes.jsonl"
echo 5 > "$SB/refusals"
printf '%s\n' "no matching attestations: " > "$SB/refusal.1"
printf '%s\n' "$denied" > "$SB/refusal.2"
for nth in 4 5; do unanswered "$nth" > "$SB/refusal.$nth"; done
printf '%s\n' "$lead" " offline verification failed" " offline verification failed" " ${reasons[3]}" > "$SB/refusal.3"
run verify "$SB/root" "$REF"
what="cosign refusing, its message four lines, two of them alike"
[ "$rc" -eq 1 ] \
  && pass "$what: exit 1" \
  || fail "$what: the exit code" "exit=$rc, wanted 1" "stdout:" "${out:-nothing}" "stderr:" "${err:-nothing}"
error_line
offline=$(occurs "offline verification failed" <<<"$errors"); named=$(occurs "${reasons[3]}" <<<"$errors")
[[ "$errors" == *"DENIED"* || "$errors" == *"connection refused"* ]] && others=yes || others=no
[ "$shaped" = yes ] && [ "$offline" -eq 3 ] && [ "$named" -eq 1 ] && [ "$others" = no ] && [ "$framed" = no ] && [ "$doubled" = no ] \
  && pass "$what: the one error line names the reference, says '3 attempts' and carries all four lines of the third attempt's message, none left out, doubled or dropped for being like another" \
  || fail "$what: the error line on stderr" \
       "one line begun '::error::check-provenance: ' and the reference, ended ' (Req 2.28)', that says '3 attempts': $shaped, wanted yes (lines begun '::error::check-provenance: ': $count)" \
       "times 'offline verification failed', the reason of the message's first three lines, is in it: $offline, wanted 3" \
       "times the fourth line is: $named, wanted 1 ('${reasons[3]}')" \
       "'DENIED' or 'connection refused', what the second, the fourth and the fifth attempt were told, in it: $others, wanted no" \
       "one of the prefixes 'Error: ' and 'error during command execution' in it: $framed, wanted no" \
       "two blanks in a row in it: $doubled, wanted no" \
       "stderr:" "${err:-nothing}"
calls=$(grep -c '' "$SB/cosign.log")
[ "$calls" -eq 3 ] \
  && pass "$what: cosign is called three times and no more" \
  || fail "$what: the cosign calls the stub logged: three" "calls logged: $calls, wanted 3"
# the registry not answering on any call, the cause the three attempts are
# there for, each call under another address; the message has quotation marks
# in it
fresh
envelopes "$(statement "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$GIT_REF")" > "$SB/envelopes.jsonl"
echo 5 > "$SB/refusals"
for nth in 1 2 3 4 5; do unanswered "$nth" > "$SB/refusal.$nth"; done
run verify "$SB/root" "$REF"
what="cosign refusing because the registry does not answer"
[ "$rc" -eq 1 ] \
  && pass "$what: exit 1" \
  || fail "$what: the exit code" "exit=$rc, wanted 1" "stdout:" "${out:-nothing}" "stderr:" "${err:-nothing}"
error_line
third=$(unanswered 3)
whole=$(occurs "$third" <<<"$errors"); refused=$(occurs "connection refused" <<<"$errors")
[ "$shaped" = yes ] && [ "$whole" -eq 1 ] && [ "$refused" -eq 1 ] && [ "$framed" = no ] && [ "$doubled" = no ] \
  && pass "$what: the one error line names the reference, says '3 attempts' and carries the third attempt's message to the letter, its quotation marks too, and no other attempt's" \
  || fail "$what: the error line on stderr" \
       "one line begun '::error::check-provenance: ' and the reference, ended ' (Req 2.28)', that says '3 attempts': $shaped, wanted yes (lines begun '::error::check-provenance: ': $count)" \
       "times the third attempt's message is in it, to the letter: $whole, wanted 1 ('$third')" \
       "times 'connection refused' is in it, once for each attempt it reports: $refused, wanted 1" \
       "one of the prefixes 'Error: ' and 'error during command execution' in it: $framed, wanted no" \
       "two blanks in a row in it: $doubled, wanted no" \
       "stderr:" "${err:-nothing}"
calls=$(grep -c '' "$SB/cosign.log")
[ "$calls" -eq 3 ] \
  && pass "$what: cosign is called three times and no more" \
  || fail "$what: the cosign calls the stub logged: three" "calls logged: $calls, wanted 3"
# the registry refusing the request on the third call, in cosign's words for
# ghcr.io asked without a login for a package that is not public, the address
# in them written with percent signs; the other four calls are told that the
# registry does not answer
fresh
envelopes "$(statement "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$GIT_REF")" > "$SB/envelopes.jsonl"
echo 5 > "$SB/refusals"
for nth in 1 2 4 5; do unanswered "$nth" > "$SB/refusal.$nth"; done
printf '%s\n' "$denied" > "$SB/refusal.3"
run verify "$SB/root" "$REF"
what="cosign refusing because the registry refuses the request"
[ "$rc" -eq 1 ] \
  && pass "$what: exit 1" \
  || fail "$what: the exit code" "exit=$rc, wanted 1" "stdout:" "${out:-nothing}" "stderr:" "${err:-nothing}"
error_line
whole=$(occurs "$denied" <<<"$errors")
[[ "$errors" == *"connection refused"* ]] && unreachable=yes || unreachable=no
[ "$shaped" = yes ] && [ "$whole" -eq 1 ] && [ "$unreachable" = no ] && [ "$framed" = no ] && [ "$doubled" = no ] \
  && pass "$what: the one error line names the reference, says '3 attempts' and carries the third attempt's message to the letter, its percent signs as cosign printed them" \
  || fail "$what: the error line on stderr" \
       "one line begun '::error::check-provenance: ' and the reference, ended ' (Req 2.28)', that says '3 attempts': $shaped, wanted yes (lines begun '::error::check-provenance: ': $count)" \
       "times the third attempt's message is in it, to the letter, each percent sign as cosign printed it: $whole, wanted 1 ('$denied')" \
       "'connection refused', what the other four attempts were told, in it: $unreachable, wanted no" \
       "one of the prefixes 'Error: ' and 'error during command execution' in it: $framed, wanted no" \
       "two blanks in a row in it: $doubled, wanted no" \
       "stderr:" "${err:-nothing}"
calls=$(grep -c '' "$SB/cosign.log")
[ "$calls" -eq 3 ] \
  && pass "$what: cosign is called three times and no more" \
  || fail "$what: the cosign calls the stub logged: three" "calls logged: $calls, wanted 3"
# cosign failing other than by refusing: crashing, the way a Go program that
# panics does, and cosign is a Go program. On each of the five calls nothing
# on stdout, on stderr a trace, in which neither of cosign's two prefixes is,
# and exit code 2. The trace is to the byte what a Go program of a few lines
# wrote in which main calls verify, verify calls subject and subject follows
# a nil pointer: built by go1.25.7 linux/amd64 with -trimpath as the module
# example.test/crash and run on 2026-11-15, it left stdout empty and ended
# with 2.
# Any exit code of cosign's but 0 is a failed attempt, and three failed
# attempts are exit 1: 2 is the self-check's own code for wrong usage, and a
# crash of cosign is not the caller's mistake. And with no prefix to find the
# message by, the error line still carries what cosign wrote: the trace's
# first line is wanted in it, once. What becomes of the trace's other lines
# is the script's to choose, as long as none is passed on to stderr as it is
fresh
envelopes "$(statement "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$GIT_REF")" > "$SB/envelopes.jsonl"
panic="panic: runtime error: invalid memory address or nil pointer dereference"
for nth in 1 2 3 4 5; do
  {
    printf '%s\n' "$panic" "[signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x46fb80]" "" "goroutine 1 [running]:"
    # a frame is two lines: the function, and after a tab the place in its file
    printf '%s\n\t%s\n' "main.subject(0x0?)" "example.test/crash/main.go:9" "main.verify(0x475f00?)" "example.test/crash/main.go:12 +0x13" "main.main()" "example.test/crash/main.go:14 +0x15"
  } > "$SB/crash.$nth"
done
run verify "$SB/root" "$REF"
what="cosign crashing on every attempt"
[ "$rc" -eq 1 ] \
  && pass "$what: exit 1" \
  || fail "$what: the exit code" "exit=$rc, wanted 1: cosign ended with 2 on every call, and 2 is the self-check's own code for wrong usage; three failed attempts are exit 1 whatever cosign ended with" "stdout:" "${out:-nothing}" "stderr:" "${err:-nothing}"
error_line
whole=$(occurs "$panic" <<<"$errors")
other=$(grep -vc -e '^::error::check-provenance: ' -e '^::warning::check-provenance: ' "$SB/stderr")
[ "$shaped" = yes ] && [ "$whole" -eq 1 ] && [ "$other" -eq 0 ] \
  && pass "$what: the one error line names the reference, says '3 attempts' and carries the first line of what cosign wrote, and no line of the trace is passed on as it is" \
  || fail "$what: the error line on stderr" \
       "one line begun '::error::check-provenance: ' and the reference, ended ' (Req 2.28)', that says '3 attempts': $shaped, wanted yes (lines begun '::error::check-provenance: ': $count)" \
       "times the first line of what cosign wrote is in it: $whole, wanted 1 ('$panic')" \
       "lines on stderr begun otherwise than '::error::check-provenance: ' or '::warning::check-provenance: ', the trace's own lines passed on: $other, wanted 0" \
       "stderr:" "${err:-nothing}"
calls=$(grep -c '' "$SB/cosign.log")
[ "$calls" -eq 3 ] \
  && pass "$what: cosign is called three times and no more" \
  || fail "$what: the cosign calls the stub logged: three" "calls logged: $calls, wanted 3"
# cosign failing without a word: on each of the five calls nothing on stdout
# and nothing on stderr, the call's crash file being empty. It stands for a
# process that ends before it has written anything, as one the kernel kills
# does. That one ends with 137 and the stub's crash with 2: the code is not
# what this input is about, the input before holds the code.
# With no word of cosign's to carry, the check fails as on every other input:
# on the script's own error line, after three attempts, and with no other
# line on stderr. It must not end on the shell's complaint in place of that
# line, as a script under set -u does that reads the first line of what
# cosign wrote out of an array with nothing in it. How the error line reads
# where the message would be is the script's to choose
fresh
envelopes "$(statement "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$GIT_REF")" > "$SB/envelopes.jsonl"
for nth in 1 2 3 4 5; do : > "$SB/crash.$nth"; done
run verify "$SB/root" "$REF"
what="cosign failing without a word on every attempt"
[ "$rc" -eq 1 ] \
  && pass "$what: exit 1" \
  || fail "$what: the exit code" "exit=$rc, wanted 1" "stdout:" "${out:-nothing}" "stderr:" "${err:-nothing}"
error_line
other=$(grep -vc -e '^::error::check-provenance: ' -e '^::warning::check-provenance: ' "$SB/stderr")
[ "$shaped" = yes ] && [ "$other" -eq 0 ] \
  && pass "$what: the one error line names the reference and says '3 attempts', and no line on stderr is other than the script's own" \
  || fail "$what: the error line on stderr" \
       "one line begun '::error::check-provenance: ' and the reference, ended ' (Req 2.28)', that says '3 attempts': $shaped, wanted yes (lines begun '::error::check-provenance: ': $count)" \
       "lines on stderr begun otherwise than '::error::check-provenance: ' or '::warning::check-provenance: ', a complaint of the shell's for one: $other, wanted 0" \
       "stderr:" "${err:-nothing}"
calls=$(grep -c '' "$SB/cosign.log")
[ "$calls" -eq 3 ] \
  && pass "$what: cosign is called three times and no more" \
  || fail "$what: the cosign calls the stub logged: three" "calls logged: $calls, wanted 3"

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all check-provenance tests passed"
