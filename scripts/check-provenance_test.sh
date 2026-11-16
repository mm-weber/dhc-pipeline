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
# Every run of the script is also watched for what it leaves behind (plan
# slice 2.5.3b): run starts it in a working directory of its own, tells it
# where to keep its temporary files and takes down what the case's sandbox
# holds, before the run and after it, and the stub notes where each call's
# stdout and stderr go. Wanted after every run: the sandbox holds what it
# held before, with nothing new, changed or gone in the two directories, in
# the root the script is given or beside them, apart from the files a run is
# expected to write; no file that cosign wrote to is still there; and the
# stub's note is there from every cosign call, since a call that left none
# was not watched. The suite's last result line holds all the runs to that.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-provenance.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }

# Every sandbox lives under this one directory, removed when the suite ends.
# Without it the suite ends here: with $TOP empty the sandboxes would be made
# in /, where root may write, and would stay there, since the trap would have
# nothing to remove
TOP=$(mktemp -d) || { echo "FAIL the directory for the suite's sandboxes could not be made: the suite ends here"; exit 1; }
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
  # $SB/tmp is the sandbox's own directory for the script's temporary files,
  # $SB/cwd the working directory the script is started in, and
  # $SB/cosign.wrote-to the stub's note of where its calls wrote, all three
  # empty to begin with (see run). $SB is the sandbox by its full path, also
  # when TMPDIR is a relative one: run starts the script in $SB/cwd, and from
  # there a relative $SB leads nowhere, not to the script's root, not to the
  # stub on PATH, not to the files its output goes to. Without a sandbox the
  # suite ends here: run removes two directories below $SB, and with $SB
  # empty those would be /tmp and /cwd
  SB=$(mktemp -d "$TOP/sandbox.XXXXXX") && SB=$(cd "$SB" && pwd) \
    || { echo "FAIL a sandbox for the case could not be made under '$TOP': the suite ends here"; exit 1; }
  mkdir -p "$SB/root" "$SB/bin" "$SB/tmp" "$SB/cwd"; : > "$SB/cosign.log"; : > "$SB/cosign.wrote-to"
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
  # per verified attestation, on stderr its report, exit 0.
  # Whatever it answers, every call first notes where its stdout and its
  # stderr go, a line for each: what readlink says of its own descriptors 1
  # and 2 under /proc, a file by its path, a pipe as pipe:[...]. The note is
  # a file of its own, $SB/cosign.wrote-to, so that the log keeps its one
  # line per call; run reads it when the script has ended and wants both
  # lines of every call the log shows (plan slice 2.5.3b)
  cat > "$SB/bin/cosign" <<'STUB'
#!/usr/bin/env bash
SB="$(cd "$(dirname "$0")/.." && pwd)"
{ printf 'cosign'; [ $# -gt 0 ] && printf ' %q' "$@"; echo; } >> "$SB/cosign.log"
readlink "/proc/$$/fd/1" "/proc/$$/fd/2" >> "$SB/cosign.wrote-to" 2>/dev/null
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

# What a sandbox holds, for run to take down before a run of the script and
# after it (plan slice 2.5.3b): a line for every entry below $SB, its kind
# (d a directory, f a file, l a symbolic link) and its path from the
# sandbox's top, and for every file a second line that has the checksum of
# its content in the kind's place. Sorted, so that two lists of one sandbox
# differ only where the sandbox does.
# Left out are the files at the sandbox's top that a run is expected to
# write: the run's own stdout and stderr, the stub's log of its calls and
# its note of where they wrote, the number of calls to refuse, which the
# stub counts down, and the log that case 4b's stand-in for jq keeps of its
# calls. This list is the one place that says which they are: a later slice
# whose stand-in keeps a file of its own adds the name here.
WRITTEN=(stdout stderr cosign.log cosign.wrote-to refusals jq.log)
holds() {
  local name; local -a spared=()
  for name in "${WRITTEN[@]}"; do spared+=(! -path "./$name"); done
  ( cd "$SB" && find . -mindepth 1 "${spared[@]}" -printf '%y  %p\n' -type f -exec sha256sum {} + ) | LC_ALL=C sort
}

# What differs between two such lists, $1 taken before a run and $2 after
# it: a line for every path that only the second has (new), that only the
# first has (gone) or that both have with another kind or another checksum
# (changed). On each line the word, a tab and the path, without the ./ the
# lists begin it with; sorted by path.
differing() {
  awk '
    $0 == "" { next }
    { cut = index($0, "  "); state = substr($0, 1, cut - 1); path = substr($0, cut + 4) }
    NR == FNR { was[path] = was[path] " " state; next }
    { now[path] = now[path] " " state }
    END {
      for (path in was) {
        if (!(path in now)) print "gone\t" path
        else if (was[path] != now[path]) print "changed\t" path
      }
      for (path in now) if (!(path in was)) print "new\t" path
    }' <(printf '%s\n' "$1") <(printf '%s\n' "$2") | LC_ALL=C sort -t $'\t' -k 2
}

# The script the way the release job calls it, in the case's sandbox: the stub
# first on PATH, no pause between attempts. stdout and stderr are kept apart:
# in the sandbox's files stdout and stderr and, for the cases, in $out and
# $err; the exit code in $rc. Called as a plain command, never in $( ).
# Both files are removed before the start, so that a run that was not
# started (its working directory gone, a file for its output not to be
# opened) never shows the output of an earlier run in the same sandbox: $out
# and $err are empty then, and $rc is the shell's code, not the script's.
# Such a run gives its case nothing of the script to judge, and run says so
# in a FAIL line of its own, the only result line it ever prints.
# Every run is also watched for what it leaves behind (plan slice 2.5.3b).
# The script is started in $SB/cwd, the sandbox's own working directory for
# it (in a subshell, so that the suite stays where it is), and TMPDIR tells
# it to keep its temporary files in $SB/tmp. So a file it writes by a
# relative path lands in the one, not where the suite was started (on a
# runner the checkout), and a temporary file in the other. What the sandbox
# holds is taken down before the start and again when the script has ended
# (see holds), and every difference counts as left behind: an entry that is
# new, a file whose content has changed, an entry that is gone, be it in
# either directory, in the root the script is given (on a runner the
# checkout as well) or beside them; either directory being gone is one.
# Each is named with its place: by its path below the directory for
# temporary files, the working directory or the root, or else by its path
# from the sandbox's top. What a case lays down before a run is part of what
# the sandbox held, and is not counted against the run.
# Left behind as well is every file a cosign call wrote to (the stub's note,
# see fresh) that is still there, wherever it lies. A pipe cannot be left
# behind and neither can a device such as /dev/null, and the two files this
# run's own stdout and stderr went to are the caller's, not the script's.
# The note is held to the stub's log, so that no run is watched blind: every
# cosign call of this run, a line the log gained in it, must have left its
# two lines in the note, one for its stdout and one for its stderr. A run
# whose note holds fewer lines than that, or more, counts as one in which a
# cosign call did not note where its output went; a run without a cosign
# call wants no note.
# What a run left, and a note that does not match the calls, is kept for the
# suite's last result line (see nothing_left_behind). Both directories are
# made anew, empty, once they are compared (so a file cosign wrote to in one
# of them is named once, by its place), and the stub's note is begun anew, so
# that a second run in the same sandbox answers for what it left itself.
# What a run left or changed elsewhere in the sandbox is not undone: the next
# run's list of what the sandbox holds is taken anew, and so each run answers
# for what it did itself.
RUNS=0     # the runs watched
LEAVING=0  # of them, those that left something behind
LEFT=""    # of the first three of those: which run it was, and what it left
BLIND=0    # of the runs watched, those whose note does not match its calls
UNNOTED="" # of the first three of those: which run it was, its calls and note
run() {
  local was now how entry top rest place before logged noted left="" target words=""
  [ $# -gt 0 ] && words=$(printf ' %q' "$@")
  before=$(grep -c '' "$SB/cosign.log")
  rm -f "$SB/stdout" "$SB/stderr"
  was=$(holds)
  ( cd "$SB/cwd" && PATH="$SB/bin:$PATH" CHECK_PROVENANCE_RETRY_DELAY=0 TMPDIR="$SB/tmp" "$CHECK" "$@" > "$SB/stdout" 2> "$SB/stderr" ); rc=$?
  now=$(holds)
  RUNS=$((RUNS + 1))
  out=""; err=""
  if [ -e "$SB/stdout" ] && [ -e "$SB/stderr" ]; then
    out=$(cat "$SB/stdout"); err=$(cat "$SB/stderr")
  else
    fail "run $RUNS of the script is started: check-provenance.sh$words" \
         "it was not: in its sandbox $SB the working directory cwd could not be entered, or the files stdout and stderr could not be opened for its output; the shell said which on the suite's stderr" \
         "so \$out and \$err are empty, and \$rc is the shell's code, $rc, not the script's: the case has nothing of the script to judge"
  fi
  while IFS=$'\t' read -r how entry; do
    top=${entry%%/*}; rest=""; [ "$top" != "$entry" ] && rest=${entry#*/}
    case "$top" in
      tmp)  place="its directory for temporary files" ;;
      cwd)  place="its working directory" ;;
      root) place="the root it is given" ;;
      *)    place="its sandbox"; rest=$entry ;;
    esac
    if [ -z "$rest" ]; then left+="${left:+$'\n'}  $place is $how"
    elif [ "$how" = gone ]; then left+="${left:+$'\n'}  gone from $place: $rest"
    else left+="${left:+$'\n'}  $how in $place: $rest"
    fi
  done < <(differing "$was" "$now")
  rm -rf "${SB:?}/tmp" "${SB:?}/cwd"; mkdir "$SB/tmp" "$SB/cwd"
  while IFS= read -r target; do
    [[ "$target" == /* ]] && [ -e "$target" ] && [ ! -c "$target" ] && [ ! "$target" -ef "$SB/stdout" ] && [ ! "$target" -ef "$SB/stderr" ] \
      && left+="${left:+$'\n'}  a file cosign wrote to, still there: $target"
  done < <(LC_ALL=C sort -u "$SB/cosign.wrote-to")
  logged=$(( $(grep -c '' "$SB/cosign.log") - before )); noted=$(grep -c '' "$SB/cosign.wrote-to")
  : > "$SB/cosign.wrote-to"
  if [ -n "$left" ]; then
    LEAVING=$((LEAVING + 1))
    if [ "$LEAVING" -le 3 ]; then
      LEFT+="${LEFT:+$'\n'}run $RUNS (exit code $rc): check-provenance.sh$words"$'\n'"$left"
    fi
  fi
  if [ "$noted" -ne $((2 * logged)) ]; then
    BLIND=$((BLIND + 1))
    if [ "$BLIND" -le 3 ]; then
      UNNOTED+="${UNNOTED:+$'\n'}run $RUNS (exit code $rc): check-provenance.sh$words"$'\n'"  cosign calls the stub logged in this run: $logged; lines in its note of where they wrote: $noted, wanted $((2 * logged)), one for each call's stdout and one for its stderr"
    fi
  fi
}

# The suite's last result line (plan slice 2.5.3b), for all the runs of the
# script that the cases made: none of them left anything behind, neither in
# its sandbox (its directory for temporary files, its working directory, the
# root it is given and what lies beside them, all held to what they were
# before the run) nor where cosign wrote, and in each every cosign call noted
# where its output went.
# It is called once, after the last case, so a later slice adds its case
# above the call and leaves this alone. The line says how many runs were
# watched, and with none watched it fails: a check that has seen no run has
# checked nothing. A failure gives three counts: the runs watched, those that
# left something, those in which a cosign call did not note where its output
# went. Of the first three runs of either kind it says which run it was (its
# number among the runs, its exit code, the call) and what it left (what is
# new, changed or gone in its sandbox, and each file cosign wrote to that is
# still there), or how many cosign calls the stub logged in it and how many
# lines its note holds.
nothing_left_behind() {
  [ "$RUNS" -gt 0 ] && [ "$LEAVING" -eq 0 ] && [ "$BLIND" -eq 0 ] \
    && pass "none of the $RUNS runs of the script left anything behind: after each its sandbox (its directory for temporary files, its working directory, the root it was given and what lies beside them) held what it had held before, apart from the files a run is expected to write, no file that cosign wrote to was still there, and every cosign call had noted where its output went" \
    || fail "no run of the script leaves anything behind: after each its sandbox (its directory for temporary files, its working directory, the root it is given and what lies beside them) holds what it held before, apart from the files a run is expected to write, no file that cosign wrote to is still there, and every cosign call notes where its output goes" \
         "runs of the script that were watched: $RUNS, wanted 1 or more" \
         "of them, runs that left something behind: $LEAVING, wanted 0" \
         "the first of those, three at most, each with what it left, changed or removed:" "${LEFT:-none}" \
         "runs in which a cosign call did not note where its output went: $BLIND, wanted 0" \
         "the first of those, three at most, each with its cosign calls and its note:" "${UNNOTED:-none}"
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

# 3: nothing verified never passes (plan slice 2.5.3). cosign ends with 0 and
#    what it printed on stdout holds no provenance statement. Nine inputs:
#    nothing at all; one blank line and nothing else; one line of a
#    byte order mark and blanks and nothing else; one envelope of the
#    shape cosign prints whose payload is null, is the empty string, is
#    base64 of a byte order mark and blanks and nothing else, is not
#    base64, is base64 of a text that is not JSON, or is base64 of JSON that
#    is not an object (the array ["a"]). A self-check that passes when nothing
#    was verified is its worst failure, and the tools at hand make it easy:
#    with jq 1.6, `jq -e .payload` ends with 0 on no input and null decodes to
#    a string. The array is there because a script that counts every payload
#    that decodes to JSON would pass with nothing verified. The empty string
#    is there because it decodes to nothing, so a judge that pipes the decoded
#    payload to `jq -e` asks over no input: measured,
#    `printf '' | jq -e 'type == "object"'` ends with 0 on jq 1.6 (the
#    development machine's) and with 4 on jq 1.7.1 (the runners'). The blank
#    line is there because a judge that asks `jq -e` on each line of stdout
#    asks over no input as well: `printf '\n' | jq -e '.payload'` ends with 0
#    and with 4 likewise. The byte order mark with blanks is there twice, as a
#    line of stdout and as a decoded payload: jq reads it as no input, as it
#    reads nothing and a blank line, while the shell finds it neither empty
#    nor blank, so a judge that sets the empty and the blank aside and then
#    takes the exit code of `jq -e` still passes with nothing verified.
#    Measured: `printf '\xef\xbb\xbf \t\r\n' | jq -e '.payload'` ends with 0
#    on jq 1.6 and with 4 on jq 1.7.1.
#    Wanted on each of the nine: exit 1, not 0 and not the code jq or base64
#    ended with (2 is the script's own code for wrong usage); nothing on
#    stdout; stderr one line and no more, neither cosign's report nor a tool's
#    complaint passed on: the script's error line, which names the reference,
#    ends " (Req 2.28)", says "no provenance statement" and not "3 attempts";
#    cosign called once: what it printed with exit 0 is judged once and final.
# the question put over the sandbox as it is laid down, and the four things
# wanted; $1 names the input in every result line
nothing_verified() {
  run verify "$SB/root" "$REF"
  [ "$rc" -eq 1 ] \
    && pass "$1: exit 1" \
    || fail "$1: the exit code" "exit=$rc, wanted 1: nothing was verified, and the code is the script's own, not the one jq or base64 ended with" "stdout:" "${out:-nothing}" "stderr:" "${err:-nothing}"
  [ ! -s "$SB/stdout" ] \
    && pass "$1: nothing on stdout" \
    || fail "$1: stdout: nothing, no line says the digest passed" "stdout:" "$(cat "$SB/stdout")" "wanted: nothing"
  lines=$(grep -c '' "$SB/stderr"); ended=$(wc -l < "$SB/stderr")
  [ "$lines" -eq 1 ] && [ "$ended" -eq 1 ] && [[ "$err" == "::error::check-provenance: $REF: "*"no provenance statement"*" (Req 2.28)" ]] && [[ "$err" != *"3 attempts"* ]] \
    && pass "$1: stderr is one line, the script's error line, which names the reference, says 'no provenance statement' and does not say '3 attempts'" \
    || fail "$1: stderr: one line and no more, begun '::error::check-provenance: ' and the reference, ended ' (Req 2.28)', that says 'no provenance statement' and does not say '3 attempts'" \
         "lines on stderr: $lines, of them ended by a newline: $ended, wanted 1 and 1" "stderr:" "${err:-nothing}" \
         "wanted: ::error::check-provenance: $REF: <why, saying 'no provenance statement' and not '3 attempts'> (Req 2.28)"
  calls=$(grep -c '' "$SB/cosign.log")
  [ "$calls" -eq 1 ] \
    && pass "$1: cosign is called once and not asked again" \
    || fail "$1: the cosign calls the stub logged: one, what cosign printed with exit 0 is judged once" "calls logged: $calls, wanted 1"
}
# cosign prints nothing on stdout
fresh
: > "$SB/envelopes.jsonl"
nothing_verified "cosign accepting and printing nothing"
# cosign's stdout is one blank line and nothing else: one newline byte
fresh
printf '\n' > "$SB/envelopes.jsonl"
nothing_verified "cosign accepting and printing one blank line"
# cosign's stdout is one line of a byte order mark and blanks and nothing
# else: the bytes EF BB BF, a space, a tab, a carriage return, the newline
fresh
printf '\xef\xbb\xbf \t\r\n' > "$SB/envelopes.jsonl"
nothing_verified "cosign accepting and printing one line of a byte order mark and blanks"
# one envelope of the shape cosign prints, its payload null
fresh
envelopes "" | jq -c '.payload = null' > "$SB/envelopes.jsonl"
nothing_verified "cosign accepting, its one envelope's payload null"
# one envelope whose payload is the empty string, the base64 of nothing
fresh
envelopes "" > "$SB/envelopes.jsonl"
nothing_verified "cosign accepting, its one envelope's payload the empty string"
# one envelope whose payload is base64 of a byte order mark and blanks and
# nothing else: 77u/IAkNCg==, which decodes to EF BB BF 20 09 0D 0A
fresh
envelopes $'\xef\xbb\xbf \t\r\n' > "$SB/envelopes.jsonl"
nothing_verified "cosign accepting, its one envelope's payload base64 of a byte order mark and blanks"
# one envelope whose payload is a string that is not base64
fresh
envelopes "" | jq -c '.payload = "%%%"' > "$SB/envelopes.jsonl"
nothing_verified "cosign accepting, its one envelope's payload not base64"
# one envelope whose payload is base64 of a text that is not JSON
fresh
envelopes "not a statement" > "$SB/envelopes.jsonl"
nothing_verified "cosign accepting, its one envelope's payload base64 of a text that is not JSON"
# one envelope whose payload is base64 of JSON that is not an object: an array
fresh
envelopes '["a"]' > "$SB/envelopes.jsonl"
nothing_verified "cosign accepting, its one envelope's payload base64 of JSON that is not an object"

# 4: a builder identity other than the build workflow's fails, naming the
#    field, the value found and the value expected (plan slice 2.5.4). cosign
#    has checked who signed; whether the signed statement says the build
#    workflow built it is the script's own first check, and the policy rule a
#    consumer applies compares for equality: a check laxer than that admits
#    what the rule refuses. Twenty inputs, each one envelope whose statement
#    carries the other four expected values and, at
#    .predicate.runDetails.builder.id, not exactly the releaser's identity;
#    what an input is there for is said where it is laid down.
#    Wanted on each: exit 1; nothing on stdout; stderr one line and no more,
#    the script's error line; cosign called once, its answer with exit 0 is
#    judged once. The error line names the reference, ends " (Req 2.28)",
#    says neither "3 attempts" nor "no provenance statement" and holds the
#    clause "builder identity is <found>, expected <expected>", both values
#    as JSON text the way jq -c prints it, on one line: a string in double
#    quotes with JSON's escapes, null where the path holds no value. The
#    clause is fixed so that a line naming several missed expectations (later
#    slices) ties each value to its field and tells found from expected. An
#    input here misses one expectation, so its line holds the one clause and
#    no second one: ", expected " stands in it once.
# a statement that carries the other four expected values, its builder
# identity $1
built_by() { statement "$1" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$GIT_REF"; }
# the question put over a fresh sandbox whose one envelope holds the
# statement $2, and the four things wanted; $1 names the input in every
# result line, $3 is the JSON text the clause shows for the value found
other_builder() {
  local clause="builder identity is $3, expected \"$RELEASER\""
  fresh
  envelopes "$2" > "$SB/envelopes.jsonl"
  run verify "$SB/root" "$REF"
  [ "$rc" -eq 1 ] \
    && pass "$1: exit 1" \
    || fail "$1: the exit code" "exit=$rc, wanted 1: the statement's builder identity is not the releaser's" "stdout:" "${out:-nothing}" "stderr:" "${err:-nothing}"
  [ ! -s "$SB/stdout" ] \
    && pass "$1: nothing on stdout" \
    || fail "$1: stdout: nothing, no line says the digest passed" "stdout:" "$(cat "$SB/stdout")" "wanted: nothing"
  lines=$(grep -c '' "$SB/stderr"); ended=$(wc -l < "$SB/stderr")
  [ "$lines" -eq 1 ] && [ "$ended" -eq 1 ] && [[ "$err" == "::error::check-provenance: $REF: "*"$clause"*" (Req 2.28)" ]] \
    && [[ "$err" != *", expected "*", expected "* && "$err" != *"3 attempts"* && "$err" != *"no provenance statement"* ]] \
    && pass "$1: stderr is one line, the script's error line, which names the reference and holds the one clause: the value found, then the value expected" \
    || fail "$1: stderr: one line and no more, begun '::error::check-provenance: ' and the reference, ended ' (Req 2.28)', that holds the clause, holds ', expected ' once and says neither '3 attempts' nor 'no provenance statement'" \
         "lines on stderr: $lines, of them ended by a newline: $ended, wanted 1 and 1" "stderr:" "${err:-nothing}" \
         "wanted: ::error::check-provenance: $REF: <any words>$clause<any words> (Req 2.28)"
  calls=$(grep -c '' "$SB/cosign.log")
  [ "$calls" -eq 1 ] \
    && pass "$1: cosign is called once and not asked again" \
    || fail "$1: the cosign calls the stub logged: one, what cosign printed with exit 0 is judged once" "calls logged: $calls, wanted 1"
}
# another workflow of the same repository at the same ref
other_builder "a builder identity that is another workflow of the repository" "$(built_by "$RE_ATTESTER")" "\"$RE_ATTESTER\""
# the identity with something after it, and with something before it: a
# script that accepts a value that begins with the expected one, that ends
# with it or that contains it passes one of the two or both
other_builder "a builder identity with something after the releaser's" "$(built_by "${RELEASER}-next")" "\"${RELEASER}-next\""
other_builder "a builder identity with something before the releaser's" "$(built_by "next-${RELEASER}")" "\"next-${RELEASER}\""
# the identity cut short by its last character, and by its first, the other
# way round: the expected value begins with the found one, or ends with it
other_builder "a builder identity that is the releaser's cut short by its last character" "$(built_by "${RELEASER%?}")" "\"${RELEASER%?}\""
other_builder "a builder identity that is the releaser's cut short by its first character" "$(built_by "${RELEASER#?}")" "\"${RELEASER#?}\""
# the identity with the dot of release.yml replaced: a script that uses the
# expected value as a pattern, where a dot stands for any character, passes
# this statement
altered=${RELEASER/release.yml/release-yml}
other_builder "a builder identity with a hyphen for the dot of release.yml" "$(built_by "$altered")" "\"$altered\""
# the identity with one letter in the other case
altered=${RELEASER/release.yml/Release.yml}
other_builder "a builder identity with one letter in the other case" "$(built_by "$altered")" "\"$altered\""
# the identity with a blank, a line break or a NUL character after it, inside
# the JSON string: none of the three is the releaser's identity. A script
# that prints the value with jq and compares it in the shell passes what the
# shell drops on the way: read the NUL, what follows a line break and,
# without IFS=, the blank; $( ) the NUL and the line break at the end;
# read -d '' what follows the NUL. The NUL is written as its escape in jq's
# program, never as the character itself in an argument
other_builder "a builder identity that is the releaser's with a blank after it" "$(built_by "$RELEASER ")" "\"$RELEASER \""
other_builder "a builder identity that is the releaser's with a line break after it" "$(built_by "$RELEASER"$'\n')" "\"$RELEASER\\n\""
other_builder "a builder identity that is the releaser's with a NUL character after it" "$(built_by "$RELEASER" | jq -c '.predicate.runDetails.builder.id += "\u0000"')" "\"$RELEASER\\u0000\""
# the identity with a line break before it: of what jq prints raw for this
# value the first line is empty and the last is the releaser's identity. A
# script that takes the last line for the value found passes this statement,
# and so does one that reads the first line and takes an empty one for
# nothing missed
other_builder "a builder identity that is the releaser's with a line break before it" "$(built_by $'\n'"$RELEASER")" "\"\\n$RELEASER\""
# the identity with a line break in its middle, before the @: a value found
# never breaks the error line in two, the clause shows the break as \n
other_builder "a builder identity that is the releaser's with a line break in its middle" "$(built_by "${RELEASER%@*}"$'\n'"@${RELEASER#*@}")" "\"${RELEASER%@*}\\n@${RELEASER#*@}\""
# the identity with a double quote, a backslash and a tab in its middle,
# before the @, shown as \", \\ and \t: a value shown as JSON text never
# poses as the clause's own punctuation, and a script that escapes by hand
# only the characters it has met so far puts these three into the line as
# they are
other_builder "a builder identity that is the releaser's with a double quote, a backslash and a tab in its middle" "$(built_by "${RELEASER%@*}"$'"\\\t'"@${RELEASER#*@}")" "\"${RELEASER%@*}"'\"\\\t'"@${RELEASER#*@}\""
# the empty string, shown "": the one value here that jq prints raw as an
# empty line and nothing more. A script that has jq print the value raw
# where it is not the releaser's identity and takes nothing read for nothing
# missed passes this statement
other_builder "a builder identity that is the empty string" "$(built_by "")" '""'
# a value at the path that is not a string, shown as jq -c prints it. false:
# jq's // takes false for no value as it takes null, so a script that asks
# with "// null" shows null where the statement says false, and one that asks
# with "// empty" and compares only a value it found passes the statement.
# An array that holds the releaser's identity twice, shown on one line with
# no blank after its comma: plain jq, without -c, prints an array over
# several lines, and python's json.dumps puts a blank after the comma. No
# other input shows either, since the strings here, null and false print the
# same all three ways
other_builder "a statement whose builder identity is false" "$(built_by "$RELEASER" | jq -c '.predicate.runDetails.builder.id = false')" false
other_builder "a statement whose builder identity is an array that holds the releaser's twice" "$(built_by "$RELEASER" | jq -c '.predicate.runDetails.builder.id |= [., .]')" "[\"$RELEASER\",\"$RELEASER\"]"
# no value at the path, shown as null. The field absent: a script that
# compares only a value it found passes this statement. The path not to be
# walked, at its last step (builder is a string, the releaser's identity,
# where an object belongs) and at an earlier one (runDetails is that
# string): jq ends with an error there and prints nothing, so a script that
# asks jq for the misses and takes nothing printed for nothing missed passes
# both, and one that guards the last step alone (.id?) passes the second
other_builder "a statement without a builder identity" "$(built_by "$RELEASER" | jq -c 'del(.predicate.runDetails.builder.id)')" null
other_builder "a statement whose builder is a string where an object belongs" "$(built_by "$RELEASER" | jq -c '.predicate.runDetails.builder |= .id')" null
other_builder "a statement whose runDetails is a string where an object belongs" "$(built_by "$RELEASER" | jq -c '.predicate.runDetails |= .builder.id')" null
# the releaser's identity at other places than the path, while the builder
# identity at the path is another workflow's. Four decoys, each an object
# whose id is the releaser's identity: the first key (builder) and the last
# (decoy) of the statement, and the same two of its predicate. So the value
# at the path is neither the first nor the last id met in the statement or
# under predicate. A script that does not walk the path passes this
# statement, whether it looks for the identity anywhere in the statement,
# for a key id (any of them, the first or the last it meets, in the
# statement or under predicate), for .predicate.builder.id or for the text
# "builder":{"id":"<identity>" in the statement's compact text
other_builder "a statement with the releaser's identity in four decoys, the builder identity at the path another workflow's" "$(built_by "$RE_ATTESTER" | jq -c --arg r "$RELEASER" 'def decoys: {builder: {id: $r}} + . + {decoy: {id: $r}}; .predicate |= decoys | decoys')" "\"$RE_ATTESTER\""

# 4b: an unanswered jq never passes (plan slice 2.5.4b). The script holds two
#     texts that jq printed against each other, the value found and the value
#     expected. A jq that is killed, on a runner out of memory for one, prints
#     nothing, and two empty texts are equal: a check that takes them for
#     values passes unchecked, also for a statement another workflow built. So
#     a jq call that gives no answer (nothing printed, a non-zero exit code)
#     fails the check wherever in a run it is. A stand-in for jq, first on PATH
#     in a run, hands every call to the real jq but the ones the case names.
#     Two statements: one that meets all five, and one built by another
#     workflow, for the jq calls made only where an expectation is missed. For
#     each, a control run with every call answered counts a run's jq calls;
#     then each is named in turn, the k-th, in two families of runs: no answer
#     from the k-th call on, each killed for real (SIGKILL, 137: of a killed
#     child the shell may write a line of its own); none at the k-th call
#     alone, ended with 2 after two lines on stderr (a jq that ends so says why
#     there). Wanted in every such run: exit 1, not 0 and not the stand-in's
#     code; nothing on stdout; stderr one line and no more, the script's error
#     line, with no value in it that jq did not give (", expected " not in it,
#     or once, in the clause the second statement truly misses); cosign called
#     once; the named call reached. A result line covers every k.
# the stand-in, laid down after fresh: $SB/bin/jq logs its call in
# $SB/jq.log, one line per call the way the cosign stub does, and takes the
# number of lines for the call's number in the run. From the call whose
# number $SB/jq.no-answer-from holds, a call is killed for real: once logged,
# the stand-in sends itself SIGKILL, as a runner's kernel does to a jq out of
# memory. An exit with 137 would show the script the same code and no more: of
# a child that a signal killed, the shell may write a notice of its own on the
# script's stderr, and bash does so for a call made as a plain command and not
# for one inside $( ), so how a killed jq shows depends on the shape of the
# call. At the call whose number $SB/jq.no-answer-at holds, the stand-in ends
# with 2, jq's code for an error of the system, after two lines on its stderr:
# a jq that ends so says why there, and a stand-in without a word would fail
# more quietly than jq does. The two lines say that they are this stand-in's.
# The first begins jq: error: and the second does not, as with the lines of a
# real jq, so that a script which keeps back only what begins so still passes
# one on; and there are two, so that words passed on as they came break the
# script's line. Nothing on stdout either time. So the one line wanted on
# stderr also says that nothing jq writes, and nothing the shell writes of jq,
# is passed on as it is; what the script's own line tells of them is free.
# Every other call is the real jq's, arguments and stdin as they came: the jq
# the suite itself finds, by its full path ($SB/jq.real), never the stand-in
jq_stand_in() {
  command -v jq > "$SB/jq.real"; : > "$SB/jq.log"
  cat > "$SB/bin/jq" <<'STUB'
#!/usr/bin/env bash
SB="$(cd "$(dirname "$0")/.." && pwd)"
{ printf 'jq'; [ $# -gt 0 ] && printf ' %q' "$@"; echo; } >> "$SB/jq.log"
nth=$(grep -c '' "$SB/jq.log")
[ -f "$SB/jq.no-answer-from" ] && [ "$nth" -ge "$(cat "$SB/jq.no-answer-from")" ] && kill -KILL $$
if [ -f "$SB/jq.no-answer-at" ] && [ "$nth" -eq "$(cat "$SB/jq.no-answer-at")" ]; then
  echo "jq: error: this call gets no answer (the words of the stand-in for jq in case 4b of check-provenance_test.sh, not jq's)" >&2
  echo "The stand-in for jq in case 4b ends this call with 2, as jq does on an error of the system (its own words again, not jq's)" >&2
  exit 2
fi
exec "$(cat "$SB/jq.real")" "$@"
STUB
  chmod +x "$SB/bin/jq"
}
# whether the file $1 is one line and no more, ended by its newline
one_line() { [ "$(grep -c '' "$1")" -eq 1 ] && [ "$(wc -l < "$1")" -eq 1 ]; }
# the control run and the two families, each run over a fresh sandbox whose
# one envelope holds the statement $2; $1 names the statement in every result
# line, $3 is the clause its error line holds when every jq call is answered,
# empty for a statement that passes
jq_gives_no_answer() {
  local order family verdict control shows met=no n k i calls made claims
  local -a bad wanted=("" "exit 1" "nothing on stdout" "stderr is one line, the script's error line, which names the reference and shows no value that jq did not give" "cosign is called once and not asked again" "the named jq call is reached")
  fresh; jq_stand_in; envelopes "$2" > "$SB/envelopes.jsonl"
  run verify "$SB/root" "$REF"
  calls=$(grep -c '' "$SB/cosign.log"); n=$(grep -c '' "$SB/jq.log"); claims=$(occurs ", expected " <<<"$err")
  if [ -z "$3" ]; then
    verdict="the check passes as in case 1"; shows="', expected ' not in it, since this statement misses nothing"
    control="exit 0; stdout one line and no more, begun 'check-provenance: ' and naming the reference; nothing on stderr"
    [ "$rc" -eq 0 ] && one_line "$SB/stdout" && [[ "$out" == "check-provenance: "*"$REF"* ]] && [ ! -s "$SB/stderr" ] && [ "$calls" -eq 1 ] && met=yes
  else
    verdict="the check fails as in case 4, on the one clause"; shows="', expected ' not in it, or in it once and with it the clause '$3'"
    control="exit 1; nothing on stdout; stderr one line and no more, begun '::error::check-provenance: ' and the reference, ended ' (Req 2.28)', that holds the clause '$3' and ', expected ' once"
    [ "$rc" -eq 1 ] && [ ! -s "$SB/stdout" ] && one_line "$SB/stderr" && [[ "$err" == "::error::check-provenance: $REF: "*"$3"*" (Req 2.28)" ]] && [ "$claims" -eq 1 ] && [ "$calls" -eq 1 ] && met=yes
  fi
  [ "$met" = yes ] \
    && pass "$1, every jq call answered: $verdict" \
    || fail "$1, every jq call answered: $verdict" "exit=$rc; cosign calls logged: $calls; times ', expected ' is on stderr: $claims" "stdout:" "${out:-nothing}" "stderr:" "${err:-nothing}" "wanted: $control; cosign called once"
  # with no jq call in the control there is none to name: nothing was asked
  [ "$n" -ge 1 ] \
    && pass "$1, every jq call answered: the run makes one jq call or more" \
    || { fail "$1, every jq call answered: the run makes one jq call or more" "jq calls the stand-in logged: $n, wanted 1 or more: the runs without an answer were not made"; return; }
  for order in from at; do
    [ "$order" = from ] && family="no answer from the k-th jq call on" || family="no answer at the k-th jq call alone"
    bad=()
    for ((k = 1; k <= n; k++)); do
      fresh; jq_stand_in; envelopes "$2" > "$SB/envelopes.jsonl"; echo "$k" > "$SB/jq.no-answer-$order"
      run verify "$SB/root" "$REF"
      calls=$(grep -c '' "$SB/cosign.log"); made=$(grep -c '' "$SB/jq.log"); claims=$(occurs ", expected " <<<"$err")
      [ "$rc" -eq 1 ] || bad[1]+="k=$k: exit=$rc, wanted 1; stderr: ${err:-nothing}"$'\n'
      [ ! -s "$SB/stdout" ] || bad[2]+="k=$k: stdout: $out, wanted: nothing"$'\n'
      one_line "$SB/stderr" && [[ "$err" == "::error::check-provenance: $REF: "*" (Req 2.28)" ]] \
        && { [ "$claims" -eq 0 ] || { [ -n "$3" ] && [ "$claims" -eq 1 ] && [[ "$err" == *"$3"* ]]; }; } \
        || bad[3]+="k=$k: lines on stderr: $(grep -c '' "$SB/stderr"), of them ended by a newline: $(wc -l < "$SB/stderr"), wanted 1 and 1; times ', expected ' is there: $claims; stderr: ${err:-nothing}"$'\n'
      [ "$calls" -eq 1 ] || bad[4]+="k=$k: cosign calls logged: $calls, wanted 1"$'\n'
      [ "$made" -ge "$k" ] || bad[5]+="k=$k: jq calls the stand-in logged: $made, wanted $k or more: $(cat "$SB/jq.log")"$'\n'
    done
    [ -z "${bad[3]:-}" ] || bad[3]+="wanted at every k: ::error::check-provenance: $REF: <why> (Req 2.28), one line and no more, $shows"
    for i in 1 2 3 4 5; do
      [ -z "${bad[$i]:-}" ] && pass "$1, $family: ${wanted[$i]}" || fail "$1, $family: ${wanted[$i]}" "${bad[$i]%$'\n'}"
    done
  done
}
jq_gives_no_answer "a statement that meets all five" "$(built_by "$RELEASER")" ""
jq_gives_no_answer "a statement built by another workflow" "$(built_by "$RE_ATTESTER")" "builder identity is \"$RE_ATTESTER\", expected \"$RELEASER\""

# 5: a build type other than the expected one fails, naming the field, the
#    value found and the value expected (plan slice 2.5.5). The build type
#    says which kind of build wrote the statement, and with it what the
#    fields under externalParameters mean. The policy rule a consumer applies
#    compares it for equality, and a self-check laxer than the rule passes a
#    release that the rule then refuses in the cluster. Eighteen inputs, each
#    one envelope whose statement meets the other four expectations and
#    holds, at .predicate.buildDefinition.buildType, not exactly the expected
#    build type: the sixteen kinds every expectation is asked (every_kind)
#    and two laid down by hand. Wanted on each: exit 1; nothing on stdout;
#    stderr one line and no more, the script's error line, which holds the
#    one clause "build type is <found>, expected <expected>", both values as
#    JSON text the way jq -c prints it, and none of the values of the
#    expectations the statement meets; cosign called once.
# One input put to the script, whichever expectation it misses: a fresh
# sandbox whose one envelope holds the statement $2, one run, the four things
# wanted. $1 names the input in every result line, $3 is the expectation's
# name as the clause writes it, $4 and $5 are the JSON text the clause shows
# for the value found and for the value expected, the arguments after them
# the values of the expectations the statement meets. All that is wanted of
# stderr is one result line: against a script that passes the statement
# stderr is empty, and a line of its own for "none of those values" would be
# ok without having asked anything. Its detail says which part did not hold
misses_one() {
  local clause="$3 is $4, expected $5" lines ended claims calls met; local -a wrong=()
  fresh
  envelopes "$2" > "$SB/envelopes.jsonl"
  run verify "$SB/root" "$REF"
  [ "$rc" -eq 1 ] \
    && pass "$1: exit 1" \
    || fail "$1: the exit code" "exit=$rc, wanted 1: the statement's $3 is not the expected one" "stdout:" "${out:-nothing}" "stderr:" "${err:-nothing}"
  [ ! -s "$SB/stdout" ] \
    && pass "$1: nothing on stdout" \
    || fail "$1: stdout: nothing, no line says the digest passed" "stdout:" "$(cat "$SB/stdout")" "wanted: nothing"
  lines=$(grep -c '' "$SB/stderr"); ended=$(wc -l < "$SB/stderr"); claims=$(occurs ", expected " <<<"$err")
  { [ "$lines" -eq 1 ] && [ "$ended" -eq 1 ]; } || wrong+=("lines on stderr: $lines, of them ended by a newline: $ended, wanted 1 and 1")
  [[ "$err" == "::error::check-provenance: $REF: "*" (Req 2.28)" ]] || wrong+=("it is not begun '::error::check-provenance: ' and the reference and ended ' (Req 2.28)'")
  [[ "$err" == *"$clause"* ]] || wrong+=("the clause is not in it")
  [ "$claims" -eq 1 ] || wrong+=("times ', expected ' is in it: $claims, wanted 1")
  [[ "$err" != *"3 attempts"* && "$err" != *"no provenance statement"* ]] || wrong+=("it says '3 attempts' or 'no provenance statement', wanted neither")
  for met in "${@:6}"; do
    [[ "$err" != *"$met"* ]] || wrong+=("it holds a value of an expectation the statement meets, wanted none of them: $met")
  done
  [ "${#wrong[@]}" -eq 0 ] \
    && pass "$1: stderr is one line, the script's error line, which names the reference and holds the one clause and no value of an expectation the statement meets" \
    || fail "$1: stderr: one line and no more, begun '::error::check-provenance: ' and the reference, ended ' (Req 2.28)', that holds the clause, holds ', expected ' once, says neither '3 attempts' nor 'no provenance statement' and holds no value of an expectation the statement meets" \
         "${wrong[@]}" "stderr:" "${err:-nothing}" "wanted: ::error::check-provenance: $REF: <any words>$clause<any words> (Req 2.28)"
  calls=$(grep -c '' "$SB/cosign.log")
  [ "$calls" -eq 1 ] \
    && pass "$1: cosign is called once and not asked again" \
    || fail "$1: the cosign calls the stub logged: one, what cosign printed with exit 0 is judged once" "calls logged: $calls, wanted 1"
}
# The kinds every expectation is asked: $1 is the expectation's name, $2 its
# path in the statement, $3 its expected value, the arguments after them the
# values of the other four. Each kind takes the statement that meets all five
# and puts its own value at the path; the JSON text the clause is wanted to
# show for it is spelled by hand, never made by jq. So an expected value
# that cannot be spelled that way is refused before any kind is laid down,
# and the kinds of the dot and of the capital refuse one without a dot or
# without a small letter: their input would be the expected value itself.
# What each is there for, shortly (case 4 says it at length): a script that
# accepts a value which only begins or ends like the expected one, or which
# the expected one begins or ends with; one that reads the expected value as
# a pattern, a dot for any character, or without regard to case; one that
# has jq print the value raw and loses a blank, a line break or a NUL on the
# way through the shell, or reads an empty line or nothing at all as nothing
# missed; one whose error line a line break, a double quote, a backslash or
# a tab in the value breaks in two or forges; one that asks with // and so
# takes false for no value, or compares only a value it found; one that
# shows an array over several lines or with a blank after its comma
every_kind() {
  local name=$1 path=$2 v=$3 all a b low cap; shift 3
  local put="$path = \$v" want="\"$v\""
  if ( LC_ALL=C; [[ "$v" == *[!\ -~]* || "$v" == *[\"\\]* ]] ); then
    fail "the kinds of $name: the expected value can be spelled as JSON text by hand" "the expected value: $(printf '%q' "$v")" \
         "wanted: one that holds no double quote, no backslash, no control character and no character outside ASCII; no kind was laid down"
    return
  fi
  all=$(statement "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$GIT_REF")
  a=${v:0:${#v}/2}; b=${v:${#v}/2}; low=${v%%[[:lower:]]*}; cap=${v:${#low}}; cap="$low${cap^}"
  misses_one "a $name with something after the expected one" "$(jq -c --arg v "$v-next" "$put" <<<"$all")" "$name" "\"$v-next\"" "$want" "$@"
  misses_one "a $name with something before the expected one" "$(jq -c --arg v "next-$v" "$put" <<<"$all")" "$name" "\"next-$v\"" "$want" "$@"
  misses_one "a $name that is the expected one cut short by its last character" "$(jq -c --arg v "${v%?}" "$put" <<<"$all")" "$name" "\"${v%?}\"" "$want" "$@"
  misses_one "a $name that is the expected one cut short by its first character" "$(jq -c --arg v "${v#?}" "$put" <<<"$all")" "$name" "\"${v#?}\"" "$want" "$@"
  if [[ "$v" == *.* ]]; then
    misses_one "a $name with a hyphen for the expected one's first dot" "$(jq -c --arg v "${v/./-}" "$put" <<<"$all")" "$name" "\"${v/./-}\"" "$want" "$@"
  else
    fail "a $name with a hyphen for the expected one's first dot: the input can be laid down" "the expected value holds no dot: $v" "wanted: one that holds a dot; without one the input would be the expected value itself, so it was not laid down"
  fi
  if [ "$low" != "$v" ]; then
    misses_one "a $name with the expected one's first small letter as a capital" "$(jq -c --arg v "$cap" "$put" <<<"$all")" "$name" "\"$cap\"" "$want" "$@"
  else
    fail "a $name with the expected one's first small letter as a capital: the input can be laid down" "the expected value holds no small letter: $v" "wanted: one that holds a small letter; without one the input would be the expected value itself, so it was not laid down"
  fi
  misses_one "a $name that is the expected one with a blank after it" "$(jq -c --arg v "$v " "$put" <<<"$all")" "$name" "\"$v \"" "$want" "$@"
  misses_one "a $name that is the expected one with a line break after it" "$(jq -c --arg v "$v"$'\n' "$put" <<<"$all")" "$name" "\"$v\\n\"" "$want" "$@"
  misses_one "a $name that is the expected one with a NUL character after it" "$(jq -c --arg v "$v" "$put + \"\\u0000\"" <<<"$all")" "$name" "\"$v\\u0000\"" "$want" "$@"
  misses_one "a $name that is the expected one with a line break before it" "$(jq -c --arg v $'\n'"$v" "$put" <<<"$all")" "$name" "\"\\n$v\"" "$want" "$@"
  misses_one "a $name that is the expected one with a line break in its middle" "$(jq -c --arg v "$a"$'\n'"$b" "$put" <<<"$all")" "$name" "\"$a\\n$b\"" "$want" "$@"
  misses_one "a $name that is the expected one with a double quote, a backslash and a tab in its middle" "$(jq -c --arg v "$a"$'"\\\t'"$b" "$put" <<<"$all")" "$name" "\"$a"'\"\\\t'"$b\"" "$want" "$@"
  misses_one "a $name that is the empty string" "$(jq -c --arg v "" "$put" <<<"$all")" "$name" '""' "$want" "$@"
  misses_one "a statement whose $name is false" "$(jq -c "$path = false" <<<"$all")" "$name" false "$want" "$@"
  misses_one "a statement whose $name is an array that holds the expected one twice" "$(jq -c --arg v "$v" "$path = [\$v, \$v]" <<<"$all")" "$name" "[\"$v\",\"$v\"]" "$want" "$@"
  misses_one "a statement without a $name" "$(jq -c "del($path)" <<<"$all")" "$name" null "$want" "$@"
}
every_kind "build type" .predicate.buildDefinition.buildType "$BUILD_TYPE" "$RELEASER" "$SOURCE" "$WORKFLOW" "$GIT_REF"
# another build type as a whole, where the kinds above all vary the expected
# one
other_type="https://slsa-framework.github.io/github-actions-buildtypes/workflow/v1"
misses_one "a build type that is another one" "$(statement "$RELEASER" "$other_type" "$SOURCE" "$WORKFLOW" "$GIT_REF")" \
  "build type" "\"$other_type\"" "\"$BUILD_TYPE\"" "$RELEASER" "$SOURCE" "$WORKFLOW" "$GIT_REF"
# the expected build type at other places than the path, while the build type
# at the path is that other one. Four decoys, as in case 4: the statement's
# first key (buildDefinition, an object whose buildType it is) and its last
# (decoy, such an object too), the predicate's first key (buildType itself)
# and its last (decoy again). So the value at the path is neither the first
# nor the last buildType in the statement or under predicate, and a script
# that does not walk the path passes this statement
misses_one "a statement with the expected build type in four decoys, the build type at the path another one" \
  "$(statement "$RELEASER" "$other_type" "$SOURCE" "$WORKFLOW" "$GIT_REF" | jq -c --arg t "$BUILD_TYPE" '{buildDefinition: {buildType: $t}} + . + {decoy: {buildType: $t}} | .predicate |= {buildType: $t} + . + {decoy: {buildType: $t}}')" \
  "build type" "\"$other_type\"" "\"$BUILD_TYPE\"" "$RELEASER" "$SOURCE" "$WORKFLOW" "$GIT_REF"

# 6: a source repository other than the build workflow's fails, naming the
#    field, the value found and the value expected (plan slice 2.5.6). The
#    source repository says whose workflow file was run. cosign has checked
#    the identity in the signing certificate; the policy rule a consumer
#    applies also compares this field of the statement for equality, and a
#    self-check laxer than the rule passes a release that the rule then
#    refuses in the cluster. Twenty inputs, each one envelope whose statement
#    meets the other four expectations and holds, at the path below, not
#    exactly $SOURCE, the repository part of the releaser's identity: the
#    sixteen kinds (every_kind) and four laid down by hand. Wanted on each
#    what misses_one asks, the clause being "source repository is <found>,
#    expected <expected>". Every statement of the case holds the expected
#    repository at other places by itself, in resolvedDependencies[0].uri, in
#    runDetails.metadata.invocationId and as the beginning of the builder
#    identity (see statement): a script that searches its text passes them all.
source_path=.predicate.buildDefinition.externalParameters.workflow.repository
every_kind "source repository" "$source_path" "$SOURCE" "$RELEASER" "$BUILD_TYPE" "$WORKFLOW" "$GIT_REF"
# one input laid down by hand: $1 names it, $2 is the value at the path, put
# there in the statement that meets all five, $3 a jq filter for what else
# the statement is to hold (the decoys), . where there is nothing
other_source() {
  misses_one "$1" "$(statement "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$GIT_REF" | jq -c --arg v "$2" --arg s "$SOURCE" "$source_path = \$v | $3")" \
    "source repository" "\"$2\"" "\"$SOURCE\"" "$RELEASER" "$BUILD_TYPE" "$WORKFLOW" "$GIT_REF"
}
# a fork has the same repository name under another owner: a script that
# compares the name alone, the last part of the URL, passes this statement
fork="${SOURCE%/*/*}/umbrella/${SOURCE##*/}"
other_source "a source repository that is a fork: another owner, the same repository name" "$fork" .
# the two ways a URL gets tidied before it is compared: a script that drops
# a .git or a slash at the end of the value found passes these statements
other_source "a source repository that is the expected one with .git after it" "$SOURCE.git" .
other_source "a source repository that is the expected one with a slash after it" "$SOURCE/" .
# the expected repository at other places than the path, while the value at
# the path is the fork. Seven decoys: repository as the first key and
# decoy.workflow.repository as the last, of the statement and of its
# predicate; repository as the first key of buildDefinition and
# workflow.repository (the path without externalParameters) as its last;
# repository (the path without workflow) as the first key of
# externalParameters. So the value at the path is neither the first nor the
# last repository in the statement, and a script that does not walk the
# whole path passes this statement
other_source "a statement with the expected source repository in seven decoys, the source repository at the path the fork" "$fork" \
  'def decoys: {repository: $s} + . + {decoy: {workflow: {repository: $s}}}; .predicate.buildDefinition.externalParameters |= {repository: $s} + .
   | .predicate.buildDefinition |= {repository: $s} + . + {workflow: {repository: $s}} | .predicate |= decoys | decoys'

# 7: a workflow path other than the build workflow's fails, naming the field,
#    the value found and the value expected (plan slice 2.5.7). The workflow
#    path says which workflow file of the repository built the image: a
#    repository holds several, and the policy admits the release workflow
#    alone. The policy rule a consumer applies compares this field for
#    equality, and a self-check laxer than the rule passes a release that the
#    rule then refuses in the cluster. Twenty inputs, each one envelope whose
#    statement meets the other four expectations and holds, at the path
#    below, not exactly $WORKFLOW, the workflow path part of the releaser's
#    identity: the sixteen kinds (every_kind) and four laid down by hand.
#    Wanted on each what misses_one asks, the clause being "workflow path is
#    <found>, expected <expected>". Every statement of the case holds the
#    expected workflow path at another place by itself, inside the builder
#    identity: a script that searches its text passes all twenty.
workflow_path=.predicate.buildDefinition.externalParameters.workflow.path
every_kind "workflow path" "$workflow_path" "$WORKFLOW" "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$GIT_REF"
# one input laid down by hand: $1 names it, $2 is the value at the path, put
# there in the statement that meets all five, $3 a jq filter for what else
# the statement is to hold (the decoys), . where there is nothing
other_workflow() {
  misses_one "$1" "$(statement "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$GIT_REF" | jq -c --arg v "$2" --arg w "$WORKFLOW" "$workflow_path = \$v | $3")" \
    "workflow path" "\"$2\"" "\"$WORKFLOW\"" "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$GIT_REF"
}
# the re-attester's workflow lies in the same directory of the same
# repository: a script that compares the directory alone passes this statement
rescan="${WORKFLOW%/*}/rescan.yml"
other_workflow "a workflow path that is another workflow of the same repository" "$rescan" .
# two ways a path gets tidied before it is compared: a script that drops a
# slash at the beginning, or compares the file name alone, passes these
other_workflow "a workflow path that is the expected one with a slash before it" "/$WORKFLOW" .
other_workflow "a workflow path that is the file name alone" "${WORKFLOW##*/}" .
# the expected workflow path at other places than the path, while the value
# at the path is the other workflow's. Seven decoys, placed as case 6 places
# its own: path as the first key and decoy.workflow.path as the last, of the
# statement and of its predicate; path as the first key of buildDefinition
# and workflow.path (the path without externalParameters) as its last; path
# (the path without workflow) as the first key of externalParameters. So the
# value at the path is neither the first nor the last path in the statement
other_workflow "a statement with the expected workflow path in seven decoys, the workflow path at the path the other workflow's" "$rescan" \
  'def decoys: {path: $w} + . + {decoy: {workflow: {path: $w}}}; .predicate.buildDefinition.externalParameters |= {path: $w} + .
   | .predicate.buildDefinition |= {path: $w} + . + {workflow: {path: $w}} | .predicate |= decoys | decoys'

# 7b: the cut values come from the releaser identity (plan slice 2.5.7b, a
#     guard). The source repository and the workflow path the script expects
#     are the parts of the releaser identity in the policy file it is given,
#     whatever that identity is: not written into the script, not taken from
#     the image reference or from another role. The cases above have one
#     identity, and $REF shares its owner and repository name, so they cannot
#     tell. Three inputs under a second identity, every part of which differs
#     from the first one's and from $REF's, owner and repository with a hyphen
#     and a dot: a statement that meets its five values passes, and one from
#     the first identity's repository, or built by the first identity's
#     workflow path, misses by name. The inputs of slice 2.5.8 (the ref) run
#     under the same identity, through the same function.
first_source=$SOURCE; first_workflow=$WORKFLOW
# runs the command it is given with the second identity in the suite's
# values: fresh, statement and the helpers called below it read these
under_second_identity() {
  local SOURCE="https://github.com/acme-corp/widgets.io" WORKFLOW=".github/workflows/publish.yml" GIT_REF="refs/heads/release-1.x"
  local RELEASER="$SOURCE/$WORKFLOW@$GIT_REF" RE_ATTESTER="$SOURCE/.github/workflows/rescan.yml@$GIT_REF"
  "$@"
}
second_identity_inputs() {
  local name="under a second releaser identity, a statement that meets its five values" all lines ended calls want got
  all=$(statement "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$GIT_REF")
  fresh
  envelopes "$all" > "$SB/envelopes.jsonl"
  run verify "$SB/root" "$REF"
  [ "$rc" -eq 0 ] && pass "$name: exit 0" \
    || fail "$name: the exit code" "exit=$rc, wanted 0" "stdout:" "${out:-nothing}" "stderr:" "${err:-nothing}"
  lines=$(grep -c '' "$SB/stdout"); ended=$(wc -l < "$SB/stdout")
  [ "$lines" -eq 1 ] && [ "$ended" -eq 1 ] && [[ "$out" == "check-provenance: "* ]] && [[ "$out" == *"$REF"* ]] \
    && pass "$name: stdout is one line, begun 'check-provenance: ' and naming the reference in full" \
    || fail "$name: stdout: one line, begun 'check-provenance: ' and naming the reference in full" "lines on stdout: $lines, of them ended by a newline: $ended, wanted 1 and 1" "stdout:" "${out:-nothing}" "wanted: one line begun 'check-provenance: ' that carries $REF"
  [ ! -s "$SB/stderr" ] && pass "$name: nothing on stderr" \
    || fail "$name: stderr: nothing" "stderr:" "$(cat "$SB/stderr")" "wanted: nothing"
  calls=$(grep -c '' "$SB/cosign.log"); got=$(head -n 1 "$SB/cosign.log" | asked)
  want=$(echo verify-attestation; printf '%s\n' "--type slsaprovenance1" "--certificate-oidc-issuer $ISSUER" "--certificate-identity $RELEASER" "$REF" | LC_ALL=C sort)
  [ "$calls" -eq 1 ] && [ "$got" = "$want" ] \
    && pass "$name: cosign is called once, under the second identity and with not one argument more" \
    || fail "$name: the cosign calls the stub logged: one, asked under the second identity" "calls logged: $calls, wanted 1; what the first asked:" "${got:-nothing}" "wanted:" "$want"
  misses_one "under a second releaser identity, a statement from the first identity's repository" "$(jq -c --arg v "$first_source" "$source_path = \$v" <<<"$all")" \
    "source repository" "\"$first_source\"" "\"$SOURCE\"" "$RELEASER" "$BUILD_TYPE" "$WORKFLOW" "$GIT_REF"
  misses_one "under a second releaser identity, a statement built by the first identity's workflow path" "$(jq -c --arg v "$first_workflow" "$workflow_path = \$v" <<<"$all")" \
    "workflow path" "\"$first_workflow\"" "\"$WORKFLOW\"" "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$GIT_REF"
}
under_second_identity second_identity_inputs

# 8: a ref other than the build workflow's fails, naming the field, the value
#    found and the value expected (plan slice 2.5.8). The ref says from which
#    branch or tag the workflow file was taken: a release is admitted from
#    the release branch alone, and the same workflow file run from a feature
#    branch, where anyone with push rights can change it, must not pass. The
#    policy rule a consumer applies compares this field for equality.
#    Twenty-one inputs, all under the second releaser identity (its ref holds
#    a dot, which the dot kind needs; the first one's holds none), each one
#    envelope whose statement meets the other four expectations and holds, at
#    the path below, not exactly $GIT_REF, the ref part of the releaser's
#    identity: the sixteen kinds (every_kind) and five laid down by hand.
#    Wanted on each what misses_one asks, the clause being "ref is <found>,
#    expected <expected>". Every statement of the case holds the expected ref
#    at other places by itself, at the end of the builder identity and of
#    resolvedDependencies[0].uri: a script that searches its text passes them all.
first_ref=$GIT_REF
ref_path=.predicate.buildDefinition.externalParameters.workflow.ref
# one input laid down by hand: $1 names it, $2 is the value at the path, put
# there in the statement that meets all five, $3 a jq filter for what else
# the statement is to hold (the decoys), . where there is nothing
other_ref() {
  misses_one "$1" "$(statement "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$GIT_REF" | jq -c --arg v "$2" --arg r "$GIT_REF" "$ref_path = \$v | $3")" \
    "ref" "\"$2\"" "\"$GIT_REF\"" "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW"
}
ref_inputs() {
  every_kind "ref" "$ref_path" "$GIT_REF" "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW"
  # a feature branch of the same repository, the case the field is there for
  other_ref "a ref that is another branch" "refs/heads/feature" .
  # two ways a ref gets tidied before it is compared: a script that compares
  # the last segment alone, or drops the kind of ref, passes these
  other_ref "a ref that is the branch's name alone" "${GIT_REF##*/}" .
  other_ref "a ref that is the tag of the same name" "refs/tags/${GIT_REF#refs/heads/}" .
  # the expected ref is the ref of the identity in the policy file: a script
  # with the first identity's ref written into it passes this statement
  other_ref "a ref that is the first identity's" "$first_ref" .
  # the expected ref at other places than the path, while the value at the
  # path is the other branch. Seven decoys, placed as cases 6 and 7 place
  # theirs: ref as the first key and decoy.workflow.ref as the last, of the
  # statement and of its predicate; ref as the first key of buildDefinition
  # and workflow.ref (the path without externalParameters) as its last; ref
  # (the path without workflow) as the first key of externalParameters
  other_ref "a statement with the expected ref in seven decoys, the ref at the path the other branch" "refs/heads/feature" \
    'def decoys: {ref: $r} + . + {decoy: {workflow: {ref: $r}}}; .predicate.buildDefinition.externalParameters |= {ref: $r} + .
     | .predicate.buildDefinition |= {ref: $r} + . + {workflow: {ref: $r}} | .predicate |= decoys | decoys'
}
under_second_identity ref_inputs

# every run of the script above, held to what it left behind and to the
# stub's note of its cosign calls (plan slice 2.5.3b, see run); a later case
# goes above this call
nothing_left_behind

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all check-provenance tests passed"
