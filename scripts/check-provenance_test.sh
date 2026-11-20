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

# The policy file's text, with $1 for the issuer's line and $2 for the line
# of the releaser's identity (either can be several lines, or empty: the key
# is absent). fresh writes it with both lines as they belong; cases 10 and
# 14 write it with a fault in one of them
# Between the issuer and the roles stands the declaration of the five expected
# values (plan slice 4.1.1), see declared: in every policy file written here
# it holds the values the suite's identity gives at the time of the call
policy_with() {
  printf 'verification:\n%s%s\n  roles:\n    re-attester:\n      identity: %s\n      attests: [spdxjson, cyclonedx, vuln, openvex]\n    releaser:\n%s      attests: [spdxjson, cyclonedx, vuln, openvex]\n' \
    "${1:+$1$'\n'}" "$(declared)" "$RE_ATTESTER" "${2:+$2$'\n'}"
}

# The declaration under verification.provenance, as the standing sandbox's
# policy file holds it (plan slice 4.1.1): the predicate type and the five
# expected values, each exactly what the releaser identity's parts and
# GitHub's build type give, so that every case written while the script
# derived the five keeps its meaning under a script that reads them. The
# values are read when it is called, so under another identity (cases 7b and
# 10c) it declares that identity's five. Case 23 alone declares other values
declared() {
  printf '  provenance:\n    predicate_type: https://slsa.dev/provenance/v1\n    expectations:\n      builder_identity: "%s"\n      build_type: "%s"\n      source_repository: "%s"\n      workflow_path: "%s"\n      ref: "%s"\n' \
    "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$GIT_REF"
}

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
  policy_with "  issuer: $ISSUER" "      identity: $RELEASER" > "$SB/root/catalogue-policy.yaml"
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
  # A refusing call prints on its stdout, before it ends, the case's file
  # $SB/refused.stdout.<n> where the case laid one down for that n-th call.
  # For a run over several references (report, case 17), whose calls are not
  # all answered alike, two files more name one call each: the n-th call
  # refuses, whatever the countdown says and leaving it alone, where the case
  # laid down $SB/refuses.<n> (its message is $SB/refusal.<n> as ever), and an
  # accepting n-th call prints $SB/envelopes.jsonl.<n> in the place of
  # $SB/envelopes.jsonl where the case laid that down, be it empty.
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
if [ "$left" -gt 0 ] || [ -f "$SB/refuses.$nth" ]; then
  [ "$left" -gt 0 ] && echo "$((left - 1))" > "$SB/refusals"
  [ -f "$SB/refused.stdout.$nth" ] && cat "$SB/refused.stdout.$nth"
  { printf 'Error: '; cat "$SB/refusal.$nth"; printf 'error during command execution: '; cat "$SB/refusal.$nth"; } >&2
  exit 1
fi
if [ -f "$SB/envelopes.jsonl.$nth" ]; then cat "$SB/envelopes.jsonl.$nth"; else cat "$SB/envelopes.jsonl"; fi
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

# The statement that meets all five: each value as the releaser identity
# gives it. The values are read when it is called, so under a second identity
# (case 7b) it is the statement that meets that identity's five
all_five() { statement "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$GIT_REF"; }

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
# stub counts down, and the logs that the stand-ins for jq (case 4b) and for
# sleep (case 11) keep of their calls. This list is the one place that says
# which they are: a stand-in that keeps a file of its own has its name here.
WRITTEN=(stdout stderr cosign.log cosign.wrote-to refusals jq.log sleep.log)
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
  local was now how entry top rest place before logged noted left="" target words="" dirs=$PATH
  [ $# -gt 0 ] && words=$(printf ' %q' "$@")
  before=$(grep -c '' "$SB/cosign.log")
  rm -f "$SB/stdout" "$SB/stderr"
  was=$(holds)
  # the pause between attempts is $PAUSE seconds where a case sets it, 0
  # otherwise; with the word unset the script is started without the
  # variable, with the word empty with the variable set to the empty string.
  # The tool a case names in $HIDE is on none of the directories after the
  # stub's (see path_without, at case 14); with none named, the suite's PATH
  [ -z "${HIDE:-}" ] || dirs=$(path_without "$HIDE")
  ( cd "$SB/cwd" && export CHECK_PROVENANCE_RETRY_DELAY="${PAUSE:-0}" && { [ "${PAUSE:-}" != unset ] || unset CHECK_PROVENANCE_RETRY_DELAY; } && { [ "${PAUSE:-}" != empty ] || CHECK_PROVENANCE_RETRY_DELAY=""; } && PATH="$SB/bin:$dirs" TMPDIR="$SB/tmp" "$CHECK" "$@" > "$SB/stdout" 2> "$SB/stderr" ); rc=$?
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

# What many cases ask of a run in the same words, each a result line of its
# own; $1 names the input in the line.
# The exit code is $2; $3, where it is given, is why that code is wanted,
# for the FAIL line's detail
exit_is() {
  [ "$rc" -eq "$2" ] && pass "$1: exit $2" \
    || fail "$1: the exit code" "exit=$rc, wanted $2${3:+: $3}" "stdout:" "${out:-nothing}" "stderr:" "${err:-nothing}"
}
# nothing on stdout: no line there says the digest passed
no_stdout() {
  [ ! -s "$SB/stdout" ] && pass "$1: nothing on stdout" \
    || fail "$1: stdout: nothing, no line says the digest passed" "stdout:" "$(cat "$SB/stdout")" "wanted: nothing"
}
# the cosign calls the stub logged are $2; $3 is how the ok line says it,
# $4 how the FAIL line does
cosign_calls() {
  local calls; calls=$(grep -c '' "$SB/cosign.log")
  [ "$calls" -eq "$2" ] && pass "$1: $3" \
    || fail "$1: the cosign calls the stub logged: $4" "calls logged: $calls, wanted $2"
}
# one call and no second: what cosign printed with exit 0 is its answer
judged_once() { cosign_calls "$1" 1 "cosign is called once and not asked again" "one, what cosign printed with exit 0 is judged once"; }
# no call at all; $2 is why none is wanted, and the FAIL line shows the calls
never_asked() {
  local calls; calls=$(grep -c '' "$SB/cosign.log")
  [ "$calls" -eq 0 ] && pass "$1: cosign is never called" \
    || fail "$1: the cosign calls the stub logged: none, $2" "calls logged: $calls, wanted 0:" "$(cat "$SB/cosign.log")"
}
# For the helpers that gather in their list wrong what stderr's one line
# lacks and say it in one result line, each adds its line to that list.
# The frame of the error line of a check that failed: the reference after
# the script's name, the requirement at the end
in_frame() { [[ "$err" == "::error::check-provenance: $REF: "*" (Req 2.28)" ]] || wrong+=("it is not begun '::error::check-provenance: ' and the reference and ended ' (Req 2.28)'"); }
# the line of a statement that misses an expectation is neither the line of
# three failed attempts nor that of no statement
no_other_failure() { [[ "$err" != *"3 attempts"* && "$err" != *"no provenance statement"* ]] || wrong+=("it says '3 attempts' or 'no provenance statement', wanted neither"); }
# the beginning of the error line of a refusal, which names no reference
begun_error() { [[ "$err" == "::error::check-provenance: "* ]] || wrong+=("it is not begun '::error::check-provenance: '"); }

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
envelopes "$(all_five)" > "$SB/envelopes.jsonl"
run verify "$SB/root" "$REF"
exit_is "a digest whose provenance meets all five expectations" 0
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
$(declared)
  roles:
    releaser:
      identity: $RELEASER
      attests: [spdxjson, cyclonedx, vuln, openvex]
    scanner:
      identity: $RE_ATTESTER
      attests: [spdxjson, cyclonedx, vuln, openvex]
EOF
envelopes "$(all_five)" > "$SB/envelopes.jsonl"
run verify "$SB/root" "$REF"
exit_is "the releaser listed first and the other role named scanner" 0
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
#    failed attempt that another follows is case 11's to hold: here it is
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
envelopes "$(all_five)" > "$SB/envelopes.jsonl" # what a sixth call is answered
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
exit_is "$what" 1
no_stdout "$what"
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
envelopes "$(all_five)" > "$SB/envelopes.jsonl"
echo 5 > "$SB/refusals"
for nth in 1 2 4 5; do unanswered "$nth" > "$SB/refusal.$nth"; done
printf '%s\n' "no matching attestations: " > "$SB/refusal.3"
run verify "$SB/root" "$REF"
what="cosign refusing, its message one line that ends in a blank"
exit_is "$what" 1
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
cosign_calls "$what" 3 "cosign is called three times and no more" three
# a message of four lines on the third call, a reason for each of four
# attestations, the same reason in its first three, its second and third line
# alike. The first call is told that nothing is stored beside the digest, the
# second that the registry refuses the request: the script asks again after
# either as after any other refusal. The fourth and the fifth call are told
# that the registry does not answer
fresh
envelopes "$(all_five)" > "$SB/envelopes.jsonl"
echo 5 > "$SB/refusals"
printf '%s\n' "no matching attestations: " > "$SB/refusal.1"
printf '%s\n' "$denied" > "$SB/refusal.2"
for nth in 4 5; do unanswered "$nth" > "$SB/refusal.$nth"; done
printf '%s\n' "$lead" " offline verification failed" " offline verification failed" " ${reasons[3]}" > "$SB/refusal.3"
run verify "$SB/root" "$REF"
what="cosign refusing, its message four lines, two of them alike"
exit_is "$what" 1
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
cosign_calls "$what" 3 "cosign is called three times and no more" three
# the registry not answering on any call, the cause the three attempts are
# there for, each call under another address; the message has quotation marks
# in it
fresh
envelopes "$(all_five)" > "$SB/envelopes.jsonl"
echo 5 > "$SB/refusals"
for nth in 1 2 3 4 5; do unanswered "$nth" > "$SB/refusal.$nth"; done
run verify "$SB/root" "$REF"
what="cosign refusing because the registry does not answer"
exit_is "$what" 1
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
cosign_calls "$what" 3 "cosign is called three times and no more" three
# the registry refusing the request on the third call, in cosign's words for
# ghcr.io asked without a login for a package that is not public, the address
# in them written with percent signs; the other four calls are told that the
# registry does not answer
fresh
envelopes "$(all_five)" > "$SB/envelopes.jsonl"
echo 5 > "$SB/refusals"
for nth in 1 2 4 5; do unanswered "$nth" > "$SB/refusal.$nth"; done
printf '%s\n' "$denied" > "$SB/refusal.3"
run verify "$SB/root" "$REF"
what="cosign refusing because the registry refuses the request"
exit_is "$what" 1
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
cosign_calls "$what" 3 "cosign is called three times and no more" three
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
envelopes "$(all_five)" > "$SB/envelopes.jsonl"
panic="panic: runtime error: invalid memory address or nil pointer dereference"
# the trace as a whole, on stdout; case 11 lays it down once more
go_trace() {
  printf '%s\n' "$panic" "[signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x46fb80]" "" "goroutine 1 [running]:"
  # a frame is two lines: the function, and after a tab the place in its file
  printf '%s\n\t%s\n' "main.subject(0x0?)" "example.test/crash/main.go:9" "main.verify(0x475f00?)" "example.test/crash/main.go:12 +0x13" "main.main()" "example.test/crash/main.go:14 +0x15"
}
for nth in 1 2 3 4 5; do go_trace > "$SB/crash.$nth"; done
run verify "$SB/root" "$REF"
what="cosign crashing on every attempt"
exit_is "$what" 1 "cosign ended with 2 on every call, and 2 is the self-check's own code for wrong usage; three failed attempts are exit 1 whatever cosign ended with"
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
cosign_calls "$what" 3 "cosign is called three times and no more" three
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
envelopes "$(all_five)" > "$SB/envelopes.jsonl"
for nth in 1 2 3 4 5; do : > "$SB/crash.$nth"; done
run verify "$SB/root" "$REF"
what="cosign failing without a word on every attempt"
exit_is "$what" 1
error_line
other=$(grep -vc -e '^::error::check-provenance: ' -e '^::warning::check-provenance: ' "$SB/stderr")
[ "$shaped" = yes ] && [ "$other" -eq 0 ] \
  && pass "$what: the one error line names the reference and says '3 attempts', and no line on stderr is other than the script's own" \
  || fail "$what: the error line on stderr" \
       "one line begun '::error::check-provenance: ' and the reference, ended ' (Req 2.28)', that says '3 attempts': $shaped, wanted yes (lines begun '::error::check-provenance: ': $count)" \
       "lines on stderr begun otherwise than '::error::check-provenance: ' or '::warning::check-provenance: ', a complaint of the shell's for one: $other, wanted 0" \
       "stderr:" "${err:-nothing}"
cosign_calls "$what" 3 "cosign is called three times and no more" three

# 3: nothing verified never passes (plan slice 2.5.3). cosign ends with 0 and
#    what it printed on stdout holds no provenance statement. Nine inputs:
#    nothing at all; one blank line and nothing else; one line of a byte order
#    mark and blanks and nothing else; one envelope of the shape cosign prints
#    whose payload is null, is the empty string, is base64 of a byte order
#    mark and blanks and nothing else, is not base64, is base64 of a text that
#    is not JSON, or is base64 of JSON that is not an object (the array
#    ["a"]). A self-check that passes when nothing was verified is its worst
#    failure, and the tools at hand make it easy: with jq 1.6,
#    `jq -e .payload` ends with 0 on no input and null decodes to a string.
#    The array is there because a script that counts every payload that
#    decodes to JSON would pass with nothing verified. The empty string is
#    there because it decodes to nothing, so a judge that pipes the decoded
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
  exit_is "$1" 1 "nothing was verified, and the code is the script's own, not the one jq or base64 ended with"
  no_stdout "$1"
  lines=$(grep -c '' "$SB/stderr"); ended=$(wc -l < "$SB/stderr")
  [ "$lines" -eq 1 ] && [ "$ended" -eq 1 ] && [[ "$err" == "::error::check-provenance: $REF: "*"no provenance statement"*" (Req 2.28)" ]] && [[ "$err" != *"3 attempts"* ]] \
    && pass "$1: stderr is one line, the script's error line, which names the reference, says 'no provenance statement' and does not say '3 attempts'" \
    || fail "$1: stderr: one line and no more, begun '::error::check-provenance: ' and the reference, ended ' (Req 2.28)', that says 'no provenance statement' and does not say '3 attempts'" \
         "lines on stderr: $lines, of them ended by a newline: $ended, wanted 1 and 1" "stderr:" "${err:-nothing}" \
         "wanted: ::error::check-provenance: $REF: <why, saying 'no provenance statement' and not '3 attempts'> (Req 2.28)"
  judged_once "$1"
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
#    clause is fixed so that a line naming several missed expectations (cases
#    8b and 9) ties each value to its field and tells found from expected. An
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
  exit_is "$1" 1 "the statement's builder identity is not the releaser's"
  no_stdout "$1"
  lines=$(grep -c '' "$SB/stderr"); ended=$(wc -l < "$SB/stderr")
  [ "$lines" -eq 1 ] && [ "$ended" -eq 1 ] && [[ "$err" == "::error::check-provenance: $REF: "*"$clause"*" (Req 2.28)" ]] \
    && [[ "$err" != *", expected "*", expected "* && "$err" != *"3 attempts"* && "$err" != *"no provenance statement"* ]] \
    && pass "$1: stderr is one line, the script's error line, which names the reference and holds the one clause: the value found, then the value expected" \
    || fail "$1: stderr: one line and no more, begun '::error::check-provenance: ' and the reference, ended ' (Req 2.28)', that holds the clause, holds ', expected ' once and says neither '3 attempts' nor 'no provenance statement'" \
         "lines on stderr: $lines, of them ended by a newline: $ended, wanted 1 and 1" "stderr:" "${err:-nothing}" \
         "wanted: ::error::check-provenance: $REF: <any words>$clause<any words> (Req 2.28)"
  judged_once "$1"
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
  local clause="$3 is $4, expected $5" lines ended claims met; local -a wrong=()
  fresh
  envelopes "$2" > "$SB/envelopes.jsonl"
  run verify "$SB/root" "$REF"
  exit_is "$1" 1 "the statement's $3 is not the expected one"
  no_stdout "$1"
  lines=$(grep -c '' "$SB/stderr"); ended=$(wc -l < "$SB/stderr"); claims=$(occurs ", expected " <<<"$err")
  { [ "$lines" -eq 1 ] && [ "$ended" -eq 1 ]; } || wrong+=("lines on stderr: $lines, of them ended by a newline: $ended, wanted 1 and 1")
  in_frame
  [[ "$err" == *"$clause"* ]] || wrong+=("the clause is not in it")
  [ "$claims" -eq 1 ] || wrong+=("times ', expected ' is in it: $claims, wanted 1")
  no_other_failure
  for met in "${@:6}"; do
    [[ "$err" != *"$met"* ]] || wrong+=("it holds a value of an expectation the statement meets, wanted none of them: $met")
  done
  [ "${#wrong[@]}" -eq 0 ] \
    && pass "$1: stderr is one line, the script's error line, which names the reference and holds the one clause and no value of an expectation the statement meets" \
    || fail "$1: stderr: one line and no more, begun '::error::check-provenance: ' and the reference, ended ' (Req 2.28)', that holds the clause, holds ', expected ' once, says neither '3 attempts' nor 'no provenance statement' and holds no value of an expectation the statement meets" \
         "${wrong[@]}" "stderr:" "${err:-nothing}" "wanted: ::error::check-provenance: $REF: <any words>$clause<any words> (Req 2.28)"
  judged_once "$1"
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
  all=$(all_five)
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
# One input laid down by hand, whichever expectation it misses: $1 is the
# expectation's name, $2 its path, $3 its expected value, $4 to $7 are the
# values of the other four. Then $8 names the input, $9 is the value at the
# path, put there in the statement that meets all five, and ${10} is a jq
# filter for what else the statement is to hold (the decoys, which read the
# expected value as $e), . where there is nothing
other_value() {
  misses_one "$8" "$(all_five | jq -c --arg v "$9" --arg e "$3" "$2 = \$v | ${10}")" "$1" "\"$9\"" "\"$3\"" "${@:4:4}"
}
type_path=.predicate.buildDefinition.buildType
every_kind "build type" "$type_path" "$BUILD_TYPE" "$RELEASER" "$SOURCE" "$WORKFLOW" "$GIT_REF"
# the hand-laid inputs of this case: $1 names one, $2 is the value at the
# path, $3 the filter for what else the statement holds
other_build_type() { other_value "build type" "$type_path" "$BUILD_TYPE" "$RELEASER" "$SOURCE" "$WORKFLOW" "$GIT_REF" "$@"; }
# another build type as a whole, where the kinds above all vary the expected
# one
other_type="https://slsa-framework.github.io/github-actions-buildtypes/workflow/v1"
other_build_type "a build type that is another one" "$other_type" .
# the expected build type at other places than the path, while the build type
# at the path is that other one. Four decoys, as in case 4: the statement's
# first key (buildDefinition, an object whose buildType it is) and its last
# (decoy, such an object too), the predicate's first key (buildType itself)
# and its last (decoy again). So the value at the path is neither the first
# nor the last buildType in the statement or under predicate, and a script
# that does not walk the path passes this statement
other_build_type "a statement with the expected build type in four decoys, the build type at the path another one" "$other_type" \
  '{buildDefinition: {buildType: $e}} + . + {decoy: {buildType: $e}} | .predicate |= {buildType: $e} + . + {decoy: {buildType: $e}}'

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
# the hand-laid inputs of this case: $1 names one, $2 is the value at the
# path, $3 the filter for what else the statement holds (see other_value)
other_source() { other_value "source repository" "$source_path" "$SOURCE" "$RELEASER" "$BUILD_TYPE" "$WORKFLOW" "$GIT_REF" "$@"; }
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
  'def decoys: {repository: $e} + . + {decoy: {workflow: {repository: $e}}}; .predicate.buildDefinition.externalParameters |= {repository: $e} + .
   | .predicate.buildDefinition |= {repository: $e} + . + {workflow: {repository: $e}} | .predicate |= decoys | decoys'

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
# the hand-laid inputs of this case: $1 names one, $2 is the value at the
# path, $3 the filter for what else the statement holds (see other_value)
other_workflow() { other_value "workflow path" "$workflow_path" "$WORKFLOW" "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$GIT_REF" "$@"; }
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
  'def decoys: {path: $e} + . + {decoy: {workflow: {path: $e}}}; .predicate.buildDefinition.externalParameters |= {path: $e} + .
   | .predicate.buildDefinition |= {path: $e} + . + {workflow: {path: $e}} | .predicate |= decoys | decoys'

# 7b: under a second policy file the declared values of that file are the ones
#     compared (plan slice 2.5.7b, a guard; reworded with plan slice 4.1.2,
#     the values being declared since slice 4.1.1 and no longer cut from the
#     releaser identity). The source repository and the workflow path the
#     script expects are the ones the policy file it is given declares,
#     whatever they are: not written into the script, not taken from the image
#     reference or from another role. The cases above have one policy file,
#     and $REF shares its owner and repository name, so they cannot tell.
#     Three inputs under a second policy file, whose releaser identity and
#     declared values (see declared) all differ from the first one's and from
#     $REF's, owner and repository with a hyphen and a dot: a statement that
#     meets its five declared values passes, and one from the first file's
#     source repository, or built by the first file's workflow path, misses
#     by name. The inputs of slice 2.5.8 (the ref) run under the same second
#     file, through the same function.
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
  all=$(all_five)
  fresh
  envelopes "$all" > "$SB/envelopes.jsonl"
  run verify "$SB/root" "$REF"
  exit_is "$name" 0
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
  other_source "under a second releaser identity, a statement from the first identity's repository" "$first_source" .
  other_workflow "under a second releaser identity, a statement built by the first identity's workflow path" "$first_workflow" .
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
# the hand-laid inputs of this case: $1 names one, $2 is the value at the
# path, $3 the filter for what else the statement holds (see other_value)
other_ref() { other_value "ref" "$ref_path" "$GIT_REF" "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$@"; }
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
    'def decoys: {ref: $e} + . + {decoy: {workflow: {ref: $e}}}; .predicate.buildDefinition.externalParameters |= {ref: $e} + .
     | .predicate.buildDefinition |= {ref: $e} + . + {workflow: {ref: $e}} | .predicate |= decoys | decoys'
}
under_second_identity ref_inputs

# 8b: a statement that misses several expectations names each (plan slice
#     2.5.8b). A release run is expensive: one failed check has to show all
#     that is wrong with the statement, not the first thing, so that one fix
#     and one more run are enough. Seven inputs under the first identity,
#     each one envelope whose statement misses more than one expectation: by
#     other values, or by a string where an object belongs on the way to
#     several fields. There is no value at a path that cannot be walked, so
#     each field below that place shows null as found, and the line never
#     ends in a jq error. Wanted on each: exit 1; nothing on stdout; stderr
#     one line and no more, the script's error line, which holds one clause
#     "<name> is <found>, expected <expected>" for each expectation missed,
#     each once, ", expected " as many times as there are clauses, and
#     "<name> is " of no expectation the statement meets; cosign called once.
#     The order of the clauses and the words around them are free, but for
#     this: no clause is followed at once by another, something stands
#     between two of them, or the line cannot be read.
# One input: $1 names it, $2 is the statement, the arguments up to -- are the
# clauses wanted, those after it the names of the expectations it meets. A
# met one's value may stand in the line: the builder identity holds three
misses_several() {
  local name=$1 held=$2 lines ended claims each other n; local -a clauses=() wrong=()
  shift 2
  while [ $# -gt 0 ] && [ "$1" != -- ]; do clauses+=("$1"); shift; done
  shift
  fresh
  envelopes "$held" > "$SB/envelopes.jsonl"
  run verify "$SB/root" "$REF"
  exit_is "$name" 1 "the statement misses ${#clauses[@]} expectations"
  no_stdout "$name"
  lines=$(grep -c '' "$SB/stderr"); ended=$(wc -l < "$SB/stderr"); claims=$(occurs ", expected " <<<"$err")
  { [ "$lines" -eq 1 ] && [ "$ended" -eq 1 ]; } || wrong+=("lines on stderr: $lines, of them ended by a newline: $ended, wanted 1 and 1")
  in_frame
  for each in "${clauses[@]}"; do
    n=$(occurs "$each" <<<"$err"); [ "$n" -eq 1 ] || wrong+=("times this clause is in it: $n, wanted 1: $each")
  done
  [ "$claims" -eq "${#clauses[@]}" ] || wrong+=("times ', expected ' is in it: $claims, wanted ${#clauses[@]}, one for each clause")
  # whatever the order, each clause against each other one: what stands
  # between two is free, that something stands there is not
  for each in "${clauses[@]}"; do
    for other in "${clauses[@]}"; do
      [ "$each" != "$other" ] || continue
      [[ "$err" != *"$each$other"* ]] || wrong+=("a clause is followed at once by another, wanted something between the two: $each" "and at once after it: $other")
    done
  done
  no_other_failure
  for each in "$@"; do
    [[ "$err" != *"$each is "* ]] || wrong+=("it holds '$each is ', of an expectation the statement meets, wanted nothing of it")
  done
  [ "${#wrong[@]}" -eq 0 ] \
    && pass "$name: stderr is one line, the script's error line, which names the reference and holds one clause for each expectation missed and none for one the statement meets" \
    || fail "$name: stderr: one line and no more, begun '::error::check-provenance: ' and the reference, ended ' (Req 2.28)', that holds each of the ${#clauses[@]} clauses once, holds ', expected ' ${#clauses[@]} times, lets no clause be followed at once by another, says neither '3 attempts' nor 'no provenance statement' and holds '<name> is ' of no expectation the statement meets" \
         "${wrong[@]}" "stderr:" "${err:-nothing}" "wanted, in any order and with any words around them, the clauses:" "${clauses[@]}"
  judged_once "$name"
}
several_inputs() {
  local met type="https://slsa-framework.github.io/github-actions-buildtypes/workflow/v1" fork="${SOURCE%/*/*}/umbrella/${SOURCE##*/}" rescan="${WORKFLOW%/*}/rescan.yml"
  local b="builder identity is" t="build type is" s="source repository is" w="workflow path is" r="ref is"
  local eb=", expected \"$RELEASER\"" et=", expected \"$BUILD_TYPE\"" es=", expected \"$SOURCE\"" ew=", expected \"$WORKFLOW\"" er=", expected \"$GIT_REF\""
  met=$(all_five)
  # other values at the paths: all five, two that the script does not read one
  # after the other, and two more with one it meets between them
  misses_several "a statement that misses all five" "$(statement "$RE_ATTESTER" "$type" "$fork" "$rescan" "refs/heads/feature")" \
    "$b \"$RE_ATTESTER\"$eb" "$t \"$type\"$et" "$s \"$fork\"$es" "$w \"$rescan\"$ew" "$r \"refs/heads/feature\"$er" --
  misses_several "a statement that misses the build type and the ref" "$(statement "$RELEASER" "$type" "$SOURCE" "$WORKFLOW" "refs/heads/feature")" \
    "$t \"$type\"$et" "$r \"refs/heads/feature\"$er" -- "builder identity" "source repository" "workflow path"
  misses_several "a statement that misses the builder identity and the source repository" "$(statement "$RE_ATTESTER" "$BUILD_TYPE" "$fork" "$WORKFLOW" "$GIT_REF")" \
    "$b \"$RE_ATTESTER\"$eb" "$s \"$fork\"$es" -- "build type" "workflow path" "ref"
  # a string where an object belongs, ever further down the statement that
  # meets all five: every field below it has no value, null in its clause
  misses_several "a statement whose predicate is a string" "$(jq -c '.predicate = "a string"' <<<"$met")" \
    "$b null$eb" "$t null$et" "$s null$es" "$w null$ew" "$r null$er" --
  misses_several "a statement whose buildDefinition is a string" "$(jq -c '.predicate.buildDefinition = "a string"' <<<"$met")" \
    "$t null$et" "$s null$es" "$w null$ew" "$r null$er" -- "builder identity"
  misses_several "a statement whose externalParameters is a string" "$(jq -c '.predicate.buildDefinition.externalParameters = "a string"' <<<"$met")" \
    "$s null$es" "$w null$ew" "$r null$er" -- "builder identity" "build type"
  misses_several "a statement whose workflow is a string" "$(jq -c '.predicate.buildDefinition.externalParameters.workflow = "a string"' <<<"$met")" \
    "$s null$es" "$w null$ew" "$r null$er" -- "builder identity" "build type"
}
several_inputs

# 9: several statements are judged one by one (plan slice 2.5.9). cosign
#    prints one envelope per attestation it verified, and a digest can carry
#    more than one provenance statement. The policy rule a consumer applies
#    admits on any statement that meets the conditions, and the self-check is
#    neither stricter nor laxer than the rule: it passes when at least one
#    statement meets all five, wherever it stands among the others, and fails
#    when none does, also when the five are met between two statements and by
#    neither. Five inputs under the first identity. Wanted on the three that
#    pass: exit 0; stdout the one passing line; nothing on stderr; cosign
#    called once. On the two that fail: exit 1; nothing on stdout; stderr the
#    one error line, in which each statement's clauses stand together behind
#    "statement <i>: ", <i> counted from 1 in the order cosign printed them:
#    each such text once and in rising order, and from it to the next one
#    each clause of statement i once and ", expected " once per clause;
#    cosign called once.
# One input that passes: $1 names it, the arguments after it are the statements
one_of_several() {
  local name=$1; shift
  fresh
  envelopes "$@" > "$SB/envelopes.jsonl"
  run verify "$SB/root" "$REF"
  exit_is "$name" 0 "one of the $# statements meets all five"
  one_line "$SB/stdout" && [[ "$out" == "check-provenance: "* ]] && [[ "$out" == *"$REF"* ]] \
    && pass "$name: stdout is one line, begun 'check-provenance: ' and naming the reference in full" \
    || fail "$name: stdout: one line and no more, begun 'check-provenance: ' and naming the reference in full" "stdout:" "${out:-nothing}" "wanted: one line, ended by its newline, begun 'check-provenance: ' that carries $REF"
  [ ! -s "$SB/stderr" ] && pass "$name: nothing on stderr" \
    || fail "$name: stderr: nothing, a statement that misses an expectation is not told of when another meets all five" "stderr:" "$(cat "$SB/stderr")" "wanted: nothing"
  cosign_calls "$name" 1 "cosign is called once" one
}
# One input that fails: $1 names it; then for each statement, in cosign's
# order, the statement, the clauses wanted of it and --. A statement's part of
# the line: from its "statement <i>: " to the next one's, or to the line's end
none_of_several() {
  local name=$1 i k rest part each; local -a held=() wanted=() wrong=(); shift
  while [ $# -gt 0 ]; do
    held+=("$1"); shift; each=""
    while [ $# -gt 0 ] && [ "$1" != -- ]; do each+="$1"$'\n'; shift; done
    wanted+=("$each"); shift
  done
  local n=${#held[@]}
  fresh
  envelopes "${held[@]}" > "$SB/envelopes.jsonl"
  run verify "$SB/root" "$REF"
  exit_is "$name" 1 "none of the $n statements meets all five"
  no_stdout "$name"
  one_line "$SB/stderr" || wrong+=("stderr is not exactly one line, ended by its newline: lines on it: $(grep -c '' "$SB/stderr")")
  in_frame
  no_other_failure
  [[ "$err" != *"statement $((n + 1)): "* ]] || wrong+=("it holds 'statement $((n + 1)): ', and cosign printed $n statements")
  for ((i = 1; i <= n; i++)); do
    k=$(occurs "statement $i: " <<<"$err"); [ "$k" -eq 1 ] || { wrong+=("times 'statement $i: ' is in it: $k, wanted 1; its part was not read"); continue; }
    rest=${err#*"statement $i: "}; part=$rest
    [ "$i" -eq "$n" ] || part=${rest%%"statement $((i + 1)): "*}
    [ "$i" -eq "$n" ] || [ "$part" != "$rest" ] || wrong+=("'statement $((i + 1)): ' does not stand behind 'statement $i: ', wanted the statements in rising order")
    k=0
    while IFS= read -r each; do
      [ -n "$each" ] || continue; k=$((k + 1))
      [ "$(occurs "$each" <<<"$part")" -eq 1 ] || wrong+=("times this clause is in the part of statement $i: $(occurs "$each" <<<"$part"), wanted 1: $each")
    done <<<"${wanted[i - 1]}"
    [ "$(occurs ", expected " <<<"$part")" -eq "$k" ] || wrong+=("times ', expected ' is in the part of statement $i: $(occurs ", expected " <<<"$part"), wanted $k, one for each of its clauses")
  done
  [ "${#wrong[@]}" -eq 0 ] \
    && pass "$name: stderr is one line, the script's error line, which names the reference and holds behind 'statement <i>: ', for each of the $n statements in turn, the clauses of what that statement misses and no others" \
    || fail "$name: stderr: one line and no more, begun '::error::check-provenance: ' and the reference, ended ' (Req 2.28)', that says neither '3 attempts' nor 'no provenance statement' and holds 'statement <i>: ' once for each of the $n statements, in rising order, each followed up to the next one by that statement's clauses, each once, and by ', expected ' once per clause" \
         "${wrong[@]}" "stderr:" "${err:-nothing}" "wanted, the clauses of each statement in any order and with any words around them:" \
         "$(for ((i = 1; i <= n; i++)); do printf 'statement %s: %s\n' "$i" "$(printf '%s' "${wanted[i - 1]}" | paste -sd '|')"; done)"
  judged_once "$name"
}
several_statements() {
  local met feature type="https://slsa-framework.github.io/github-actions-buildtypes/workflow/v1"
  local eb=", expected \"$RELEASER\"" et=", expected \"$BUILD_TYPE\"" es=", expected \"$SOURCE\"" ew=", expected \"$WORKFLOW\"" er=", expected \"$GIT_REF\""
  met=$(all_five)
  feature=$(statement "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "refs/heads/feature")
  one_of_several "two statements, the first with another ref, the second meets all five" "$feature" "$met"
  one_of_several "two statements, the first meets all five, the second's predicate is a string" "$met" "$(jq -c '.predicate = "a string"' <<<"$met")"
  one_of_several "three statements, the one in the middle meets all five" "$(built_by "$RE_ATTESTER")" "$met" "$(statement "$RELEASER" "$type" "$SOURCE" "$WORKFLOW" "$GIT_REF")"
  none_of_several "two statements that meet the five between them and neither alone" \
    "$feature" "ref is \"refs/heads/feature\"$er" -- \
    "$(built_by "$RE_ATTESTER")" "builder identity is \"$RE_ATTESTER\"$eb" --
  none_of_several "three statements, none meets all five" \
    "$(statement "$RELEASER" "$type" "$SOURCE" "$WORKFLOW" "refs/heads/feature")" "build type is \"$type\"$et" "ref is \"refs/heads/feature\"$er" -- \
    "$(jq -c '.predicate.buildDefinition = "a string"' <<<"$met")" "build type is null$et" "source repository is null$es" "workflow path is null$ew" "ref is null$er" -- \
    "$feature" "ref is \"refs/heads/feature\"$er" --
}
several_statements

# 9b: a line that is no JSON hides no statement (plan slice 2.5.9b). cosign's
#    stdout is one envelope per line today; should a later cosign, or a wrapper
#    around it, ever write a line of words there, every line is still judged by
#    itself. A line that is no JSON counts for nothing: it is no statement, and
#    it takes nothing from the lines before it or after it. A self-check that
#    stops reading at such a line fails a good release, and one that reads past
#    it must still never pass without a statement. Two such lines: one of plain
#    words, and the first half of a real envelope line, which begins like JSON
#    and does not end. Five inputs under the first identity. Wanted where a
#    statement meets all five: exit 0; stdout the one passing line; nothing on
#    stderr, of what jq says of the line neither. Of the line alone: exit 1;
#    nothing on stdout; stderr the one error line, saying "no provenance
#    statement". Before a statement that misses the ref: the same, the line
#    holding the ref's clause as a lone statement's does. cosign called once.
# One input: $1 names it, $2 says what is wanted (passes, none: no statement,
# ref: the ref's clause), the arguments after them are the lines of cosign's
# stdout as they are laid down
beside_no_json() {
  local name=$1 want=$2 code=1 says clause="ref is \"refs/heads/feature\", expected \"$GIT_REF\""; local -a wrong=(); shift 2
  [ "$want" = passes ] && code=0
  fresh
  printf '%s\n' "$@" > "$SB/envelopes.jsonl"
  run verify "$SB/root" "$REF"
  exit_is "$name" "$code"
  if [ "$want" = passes ]; then
    one_line "$SB/stdout" && [[ "$out" == "check-provenance: "* ]] && [[ "$out" == *"$REF"* ]] \
      && pass "$name: stdout is one line, begun 'check-provenance: ' and naming the reference in full" \
      || fail "$name: stdout: one line and no more, begun 'check-provenance: ' and naming the reference in full" "stdout:" "${out:-nothing}" "wanted: one line, ended by its newline, begun 'check-provenance: ' that carries $REF"
    [ ! -s "$SB/stderr" ] && pass "$name: nothing on stderr" \
      || fail "$name: stderr: nothing, neither of the line that is no JSON nor of what jq says of it" "stderr:" "$(cat "$SB/stderr")" "wanted: nothing"
  else
    no_stdout "$name"
    one_line "$SB/stderr" || wrong+=("stderr is not exactly one line, ended by its newline: lines on it: $(grep -c '' "$SB/stderr")")
    in_frame
    if [ "$want" = none ]; then
      says="says 'no provenance statement'"
      [[ "$err" == *"no provenance statement"* ]] || wrong+=("it does not say 'no provenance statement'")
    else
      says="holds the clause '$clause', holds ', expected ' once and says neither 'no provenance statement' nor '3 attempts'"
      [[ "$err" == *"$clause"* ]] || wrong+=("the clause is not in it")
      [ "$(occurs ", expected " <<<"$err")" -eq 1 ] || wrong+=("times ', expected ' is in it: $(occurs ", expected " <<<"$err"), wanted 1")
      no_other_failure
    fi
    [ "${#wrong[@]}" -eq 0 ] && pass "$name: stderr is one line, the script's error line, which names the reference and $says" \
      || fail "$name: stderr: one line and no more, begun '::error::check-provenance: ' and the reference, ended ' (Req 2.28)', that $says" \
           "${wrong[@]}" "stderr:" "${err:-nothing}" "wanted: ::error::check-provenance: $REF: <a reason that $says> (Req 2.28)"
  fi
  cosign_calls "$name" 1 "cosign is called once" one
}
lines_no_json() {
  local words="cosign: this line is no JSON" met feature cut
  met=$(envelopes "$(all_five)")
  feature=$(envelopes "$(statement "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "refs/heads/feature")")
  cut=${met:0:${#met}/2}
  beside_no_json "a line of words alone" none "$words"
  beside_no_json "a line of words before a statement that meets all five" passes "$words" "$met"
  beside_no_json "an envelope cut in its middle before a statement that meets all five" passes "$cut" "$met"
  beside_no_json "a line of words after a statement that meets all five" passes "$met" "$words"
  beside_no_json "a line of words before a statement that misses the ref" ref "$words" "$feature"
}
lines_no_json

# 9c: the self-check reads the five and nothing else (plan slice 2.5.9c, a
#    guard). The policy rule a consumer applies admits on the five conditions,
#    and a self-check that asks more than the rule fails a release the rule
#    would admit. One input under the first identity: the statement that
#    meets all five, in which all that statement writes beside the five
#    values is another thing (the subjects, the resolved dependency, the
#    invocation id, GitHub's internal parameters) and which holds a key of no
#    name known today at six places. The five values and the paths to them
#    are as they were. Wanted: exit 0; stdout the one passing line; nothing
#    on stderr; cosign called once.
all_else=$(all_five | jq -c '
  .subject = [{name: "ghcr.io/other/gadgets", digest: .subject[0].digest},
              {name: "ghcr.io/other/gizmos", digest: {sha256: "7c5d3b1a0f8e6c4a2b9d7e3f1c0eae559371d8b6f4e2c9a0e6381e7d4c9a2f0b"}}]
  | .predicate.buildDefinition.resolvedDependencies = [{uri: "git+https://github.com/other/gadgets@refs/tags/v9", digest: {gitCommit: "fedcba9876543210fedcba9876543210fedcba98"}}]
  | .predicate.runDetails.metadata.invocationId = "https://github.com/other/gadgets/actions/runs/77/attempts/3"
  | .predicate.buildDefinition.internalParameters.github = {event_name: "pull_request", repository_id: "901", repository_owner_id: "902", runner_environment: "self-hosted"}
  | .unknownToday = "top"
  | .predicate.unknownToday = {under: "predicate"}
  | .predicate.buildDefinition.unknownToday = ["under buildDefinition"]
  | .predicate.buildDefinition.externalParameters.unknownToday = "under externalParameters"
  | .predicate.buildDefinition.externalParameters.workflow.unknownToday = "under workflow"
  | .predicate.runDetails.unknownToday = "under runDetails"')
one_of_several "a statement that meets all five and differs in all else" "$all_else"

# 10: a policy file that does not give the issuer or the releaser identity is
#    refused (plan slice 2.5.10). cosign is asked under verification.issuer
#    and verification.roles.releaser.identity of the root's policy file, and
#    each has to be there as a string that is not empty. An empty one handed
#    to cosign is a question about nobody, the word None as identity one about
#    a signer of that name: a release must not go on with a self-check that
#    asked the wrong question, and whoever broke the file must be told which
#    key, not shown a python trace or a statement blamed for the file's fault.
#    22 inputs under the first identity, each over a policy file with the one
#    fault and all else as fresh writes it, and one envelope whose statement
#    meets all five, so that a script that asks cosign anyway gets an answer
#    that passes. Wanted: exit 2; nothing on stdout; stderr one line, begun
#    '::error::check-provenance: ', naming the file and the key by its dotted
#    path, with nothing of python's; cosign never called.
# One input: $1 names it, $2 is the policy file's text (empty: an empty file),
# the arguments after them are the keys of which the line names one or more
# (none: the line names the file alone)
policy_gives_nothing() {
  local name=$1 policy=$2 key named=no; local -a wrong=(); shift 2
  fresh
  printf '%s' "${policy:+$policy$'\n'}" > "$SB/root/catalogue-policy.yaml"
  envelopes "$(all_five)" > "$SB/envelopes.jsonl"
  run verify "$SB/root" "$REF"
  exit_is "$name" 2
  no_stdout "$name"
  one_line "$SB/stderr" || wrong+=("stderr is not exactly one line, ended by its newline: lines on it: $(grep -c '' "$SB/stderr")")
  begun_error
  [[ "$err" == *"catalogue-policy.yaml"* ]] || wrong+=("it does not name the file catalogue-policy.yaml")
  [ $# -eq 0 ] && named=yes
  for key in "$@"; do [[ "$err" == *"$key"* ]] && named=yes; done
  [ "$named" = yes ] || wrong+=("it names no key by its dotted path, wanted: $(printf '%s' "$*" | sed 's/ / or /g')")
  [[ "$err" != *"Traceback"* && "$err" != *'File "'* ]] || wrong+=("it holds 'Traceback' or 'File \"', python's own words")
  [ "${#wrong[@]}" -eq 0 ] && pass "$name: stderr is one line, the script's error line, which names catalogue-policy.yaml${1:+ and the key} and holds nothing of python's" \
    || fail "$name: stderr: one line and no more, begun '::error::check-provenance: ', that names catalogue-policy.yaml${1:+ and the key by its dotted path} and holds neither 'Traceback' nor 'File \"'" \
         "${wrong[@]}" "stderr:" "${err:-nothing}" "wanted: ::error::check-provenance: <a reason that names catalogue-policy.yaml${1:+ and $(printf '%s' "$*" | sed 's/ / or /g')}>"
  never_asked "$name" "the script cannot ask under a value the file does not give"
}
policy_faults() {
  local ki=verification.issuer kr=verification.roles.releaser.identity key pad good at line n
  local i="  issuer: $ISSUER" r="      identity: $RELEASER"
  local -a faults=("a mapping" "a list" "a number" "null, written ~" "null, written as nothing after the colon" "the empty string, written \"\"" "absent")
  for key in "$ki" "$kr"; do
    pad="  "; good=$ISSUER; [ "$key" = "$kr" ] && { pad="      "; good=$RELEASER; }
    at="$pad${key##*.}:"
    for n in 0 1 2 3 4 5 6; do
      case $n in
        0) line="$at"$'\n'"$pad  url: $good" ;;
        1) line="$at"$'\n'"$pad  - $good" ;;
        2) line="$at 7" ;;
        3) line="$at ~" ;;
        4) line="$at" ;;
        5) line="$at \"\"" ;;
        6) line="" ;;
      esac
      if [ "$key" = "$ki" ]; then policy_gives_nothing "$key is ${faults[n]}" "$(policy_with "$line" "$r")" "$key"
      else policy_gives_nothing "$key is ${faults[n]}" "$(policy_with "$i" "$line")" "$key"; fi
    done
  done
  policy_gives_nothing "verification is a string" "verification: a string" "$ki" "$kr"
  policy_gives_nothing "verification.roles is a string, so no $kr" "verification:"$'\n'"$i"$'\n'"  roles: a string" "$kr"
  policy_gives_nothing "verification.roles.releaser is a string, so no $kr" "$(policy_with "$i" "$r" | sed '/^    releaser:/,$d'; echo "    releaser: a string")" "$kr"
  policy_gives_nothing "verification.roles.releaser is absent beside the re-attester's role, so no $kr" "$(policy_with "$i" "$r" | sed '/^    releaser:/,$d')" "$kr"
  policy_gives_nothing "the policy file is empty" "" "$ki" "$kr"
  policy_gives_nothing "the policy file is no YAML, a bracket not closed" "verification: [not closed"
  policy_gives_nothing "the policy file's top is a list, no mapping" "- verification" "$ki" "$kr"
  # the byte 0xFF, which no UTF-8 text holds, before the file as fresh writes it
  policy_gives_nothing "the policy file is not UTF-8, a byte 0xFF at its beginning" $'\xff'"$(policy_with "$i" "$r")"
}
policy_faults

# 10b: anything but 'verify <root> <image@sha256:digest>' over a policy file is
#    refused as usage (plan slice 2.5.10b). The script has one mode, verify,
#    and takes exactly two arguments after it: a root, a directory that holds
#    catalogue-policy.yaml, and a reference that names an image by a sha256
#    digest of 64 lower-case hex characters. By a tag cosign would verify
#    whatever the tag points at, not the digest the release pushed; a mistyped
#    digest would cost three cosign attempts; and a caller's mistake has to
#    read as that, not as the shell's "unbound variable" or as a statement
#    that fails the check. 20 inputs under the first identity, each over a
#    fresh sandbox and one envelope whose statement meets all five, so that a
#    script that asks cosign anyway gets an answer that passes. Wanted: exit
#    2; nothing on stdout; stderr one line, begun '::error::check-provenance: ',
#    that holds what was wrong (the reference as given, the usage form, or
#    catalogue-policy.yaml) and nothing of the shell's or python's own words;
#    cosign never called.
# One input: $1 names it, $2 is what its line holds (empty: nothing is asked
# of it), $3 says what the root is (dir: as fresh writes it; no-policy: the
# policy file removed; absent: a path never made; file: a file), the arguments
# after them go to the script as they are, the word ROOT standing for the root.
# Where the root is no dir the line must not hold 'verification.' either: with
# no policy file there to be read, no key of it is at fault
refused_as_usage() {
  local name=$1 held=$2 kind=$3 root each shows; local -a args=() wrong=(); shift 3
  fresh; root="$SB/root"
  case "$kind" in
    no-policy) rm "$SB/root/catalogue-policy.yaml" ;;
    absent)    root="$SB/root/never-made" ;;
    file)      root="$SB/root/a-file"; echo "a file, no directory" > "$root" ;;
  esac
  for each in "$@"; do [ "$each" = ROOT ] && each=$root; args+=("$each"); done
  envelopes "$(all_five)" > "$SB/envelopes.jsonl"
  run ${args[@]+"${args[@]}"}
  exit_is "$name" 2
  no_stdout "$name"
  one_line "$SB/stderr" || wrong+=("stderr is not exactly one line, ended by its newline: lines on it: $(grep -c '' "$SB/stderr"), of them ended by a newline: $(wc -l < "$SB/stderr")")
  begun_error
  [ -z "$held" ] || [[ "$err" == *"$held"* ]] || wrong+=("it does not hold '$held'")
  [ "$kind" = dir ] || [[ "$err" != *"verification."* ]] || wrong+=("it holds 'verification.': it names a key of a file that is not there")
  for each in "unbound variable" "Traceback" "No such file"; do
    [[ "$err" != *"$each"* ]] || wrong+=("it holds '$each', the shell's or python's own words")
  done
  shows="${held:+holds '$held' and }"; [ "$kind" = dir ] || shows+="names no key of it by 'verification.' and "
  [ "${#wrong[@]}" -eq 0 ] && pass "$name: stderr is one line, the script's error line, which ${shows}holds nothing of the shell's or python's" \
    || fail "$name: stderr: one line and no more, begun '::error::check-provenance: ', that ${shows}holds neither 'unbound variable' nor 'Traceback' nor 'No such file'" \
         "${wrong[@]}" "stderr:" "${err:-nothing}" "wanted: ::error::check-provenance: <a reason${held:+ that holds $held}>"
  never_asked "$name" "what is no usage is refused before cosign is asked"
}
# a reference ($2) that names no image by a sha256 digest; its line holds it
no_reference() { refused_as_usage "the reference is $1" "$2" dir verify ROOT "$2"; }
usage_inputs() {
  local image=${REF%@*} hex=${REF##*:} form='verify <root> <image@sha256:digest>' policy=catalogue-policy.yaml
  no_reference "by tag, the image's name, a colon and a tag, no digest" "$image:1.2.3"
  no_reference "the image's name alone" "$image"
  no_reference "a digest of 63 hex characters" "${REF%?}"
  no_reference "a digest of 65 hex characters" "${REF}0"
  no_reference "a digest with a g in its middle, no hex digit" "$image@sha256:${hex:0:32}g${hex:33}"
  no_reference "the digest's letters as capitals" "$image@sha256:${hex^^}"
  no_reference "by another algorithm, @sha512: and 128 hex characters" "$image@sha512:$hex$hex"
  no_reference "the reference, a blank and a second reference, in the one argument" "$REF ghcr.io/acme/gadgets@sha256:$hex"
  no_reference "@sha256: and the 64 characters, no image name before the @" "@sha256:$hex"
  no_reference "the empty string" ""
  refused_as_usage "the mode word is check, the root and the reference after it" "$form" dir check ROOT "$REF"
  refused_as_usage "the mode word is in capitals, VERIFY" "$form" dir VERIFY ROOT "$REF"
  refused_as_usage "no mode word, the root and the reference alone" "$form" dir ROOT "$REF"
  refused_as_usage "no argument at all" "$form" dir
  refused_as_usage "verify alone, no root and no reference" "$form" dir verify
  refused_as_usage "verify and the root, no reference" "$form" dir verify ROOT
  refused_as_usage "a fourth argument, the reference given twice" "$form" dir verify ROOT "$REF" "$REF"
  refused_as_usage "the root holds no $policy" "$policy" no-policy verify ROOT "$REF"
  refused_as_usage "the root does not exist" "$policy" absent verify ROOT "$REF"
  refused_as_usage "the root is a file, no directory" "$policy" file verify ROOT "$REF"
}
usage_inputs

# 10c: an identity that cannot be cut into its parts is refused (plan slice
#    2.5.10c). The releaser identity reads <scheme>://<host>/<owner>/<repo>/
#    <workflow path>@<ref>, each of the six parts not empty: the source
#    repository expected is the identity up to the repository, the workflow
#    path what stands between the repository's slash and the first @, the ref
#    all after that first @. An identity of another form gives no such parts:
#    cut all the same it gives nonsense, cosign is asked, and the line blames
#    the statement for the policy file's fault. Eight such identities, each
#    with one envelope whose statement carries it as builder and the first
#    identity's repository, path and ref. Wanted: exit 2; nothing on stdout;
#    stderr one line, begun '::error::check-provenance: ', that holds the key,
#    catalogue-policy.yaml and the identity as given; cosign never called.
#    Two identities that have the form, where a cut that looks right goes
#    wrong (at the last @, at /.github/), pass on the statement of their parts.
# One identity without the form: $1 says what it is, $2 is the identity
identity_without_form() {
  local name="the releaser identity $1" RELEASER=$2 each; local -a wrong=()
  fresh
  envelopes "$(statement "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$GIT_REF")" > "$SB/envelopes.jsonl"
  run verify "$SB/root" "$REF"
  exit_is "$name" 2
  no_stdout "$name"
  one_line "$SB/stderr" || wrong+=("stderr is not exactly one line, ended by its newline: lines on it: $(grep -c '' "$SB/stderr"), of them ended by a newline: $(wc -l < "$SB/stderr")")
  begun_error
  for each in verification.roles.releaser.identity catalogue-policy.yaml "$RELEASER"; do
    [[ "$err" == *"$each"* ]] || wrong+=("it does not hold '$each'")
  done
  for each in "Traceback" "unbound variable"; do
    [[ "$err" != *"$each"* ]] || wrong+=("it holds '$each', python's or the shell's own words")
  done
  [ "${#wrong[@]}" -eq 0 ] && pass "$name: stderr is one line, the script's error line, which names the key, catalogue-policy.yaml and the identity as given" \
    || fail "$name: stderr: one line and no more, begun '::error::check-provenance: ', that holds verification.roles.releaser.identity, catalogue-policy.yaml and the identity, and neither 'Traceback' nor 'unbound variable'" \
         "${wrong[@]}" "stderr:" "${err:-nothing}" "wanted: ::error::check-provenance: <a reason that names catalogue-policy.yaml and verification.roles.releaser.identity and holds $RELEASER>"
  never_asked "$name" "an identity that gives no parts is refused before cosign is asked"
}
# One identity with the form: $1 names it, then its repository, workflow path
# and ref as the rule above cuts them; its one statement carries these
identity_with_form() {
  local name=$1 SOURCE=$2 WORKFLOW=$3 GIT_REF=$4; local RELEASER="$SOURCE/$WORKFLOW@$GIT_REF"
  one_of_several "$name, $RELEASER" "$(all_five)"
}
identity_forms() {
  local owner=${SOURCE%/*}; local host=${owner%/*}
  identity_without_form "has no @ and no ref, it ends with the workflow path" "$SOURCE/$WORKFLOW"
  identity_without_form "has nothing after the @, no ref" "$SOURCE/$WORKFLOW@"
  identity_without_form "has nothing between the repository's slash and the @, no workflow path" "$SOURCE/@$GIT_REF"
  identity_without_form "has no slash and no workflow path after the repository" "$SOURCE@$GIT_REF"
  identity_without_form "has the owner alone before the @, no repository and no workflow path" "$owner@$GIT_REF"
  identity_without_form "has an empty owner, two slashes after the host" "$host//${SOURCE##*/}/$WORKFLOW@$GIT_REF"
  identity_without_form "has an empty repository, two slashes after the owner" "$owner//$WORKFLOW@$GIT_REF"
  identity_without_form "has no scheme, it begins with the host" "${RELEASER#*://}"
  identity_with_form "an identity whose ref holds an @" "$SOURCE" "$WORKFLOW" "refs/tags/@acme/widgets@1.2.3"
  identity_with_form "an identity whose repository is named .github" "$owner/.github" "$WORKFLOW" "$GIT_REF"
}
identity_forms

# 11: a cosign call that fails is tried again, after a pause and with a warning
#    (plan slice 2.5.11). What makes cosign fail can go away by itself (a
#    registry or Sigstore that does not answer for a moment), and asking again
#    at once mostly meets the same blip; the warning is what shows in the
#    release's log that an attempt was lost, and why. Wanted after a failed
#    attempt that another follows: ONE line on stderr, begun
#    "::warning::check-provenance: " and the reference, that carries what
#    cosign said in that attempt and neither of cosign's prefixes; then a
#    pause of CHECK_PROVENANCE_RETRY_DELAY seconds, 10 with the variable not
#    set; then the next attempt, three at most. An attempt that succeeds is
#    judged as always, and stderr holds the warnings before it and no more.
#    After the third failed attempt neither warning nor pause: case 2's error
#    line follows. Seven inputs, said where they are run. sleep is a stand-in,
#    so no test waits: it logs its call in $SB/sleep.log and ends with 0
sleep_stand_in() {
  : > "$SB/sleep.log"
  cat > "$SB/bin/sleep" <<'STUB'
#!/usr/bin/env bash
SB="$(cd "$(dirname "$0")/.." && pwd)"
{ printf 'sleep'; [ $# -gt 0 ] && printf ' %q' "$@"; echo; } >> "$SB/sleep.log"
exit 0
STUB
  chmod +x "$SB/bin/sleep"
}
# A fresh sandbox with the stand-in and one envelope whose statement meets all
# five, what an accepting call answers. The first $1 cosign calls refuse, each
# with a message of two lines naming another workflow file, NAMED[n] the n-th's
declare -a NAMED=() HOLD=() LACK=()
retry_sandbox() {
  local nth=0 file
  fresh; sleep_stand_in
  envelopes "$(all_five)" > "$SB/envelopes.jsonl"
  [ "$1" -gt 0 ] && echo "$1" > "$SB/refusals"
  for file in first second third fourth fifth; do
    nth=$((nth + 1)); NAMED[$nth]="$SOURCE/.github/workflows/$file.yml@$GIT_REF"
    printf '%s\n' "no matching attestations: offline verification failed" " none of the expected identities matched what was in the certificate, got subjects [${NAMED[$nth]}] with issuer $ISSUER" > "$SB/refusal.$nth"
  done
}
# the stand-in's log after a run: $2 calls, each as "sleep $3"
pauses() {
  local wanted="" i
  for ((i = 0; i < $2; i++)); do wanted+="${wanted:+$'\n'}sleep $3"; done
  [ "$(cat "$SB/sleep.log")" = "$wanted" ] && pass "$1: sleep is called $2 times${wanted:+, each time as 'sleep $3'}" \
    || fail "$1: the calls of sleep the stand-in logged: $2${wanted:+, each as 'sleep $3'}" "calls logged:" "$([ -s "$SB/sleep.log" ] && cat "$SB/sleep.log" || echo "sleep was never called")" "wanted:" "${wanted:-no call}"
}
# The five result lines of a run named $1: exit code $2; stdout the passing
# line, or nothing where $2 is 1; stderr exactly $3 warnings, each a whole line
# begun "::warning::check-provenance: $REF: " without a prefix of cosign's,
# and where $2 is 1 the error line after them; line k holds every text of
# HOLD[k] and none of LACK[k] (a | between texts); cosign called $4 times,
# each with case 1's argument set; sleep called $3 times as "sleep 0". Of
# the error line the ok line says what this call held it to carry, the texts
# of its HOLD: after an attempt that succeeded it is the answer's line, with
# a clause or with no statement, and not the third attempt's
tried() {
  local name=$1 warnings=$3 total=$3 k line each begun lines ended calls same=0 held="" last=""; local -a wrong=() on=() texts=()
  [ "$2" -eq 1 ] && total=$((warnings + 1))
  exit_is "$name" "$2"
  if [ "$2" -eq 1 ]; then
    no_stdout "$name"
  else
    one_line "$SB/stdout" && [[ "$out" == "check-provenance: "* ]] && [[ "$out" == *"$REF"* ]] \
      && pass "$name: stdout is one line, begun 'check-provenance: ' and naming the reference in full" \
      || fail "$name: stdout: one line, ended by its newline, begun 'check-provenance: ' and naming the reference in full" "stdout:" "${out:-nothing}" "wanted: one line begun 'check-provenance: ' that carries $REF"
  fi
  lines=$(grep -c '' "$SB/stderr"); ended=$(wc -l < "$SB/stderr"); mapfile -t on < "$SB/stderr"
  [ "$lines" -eq "$total" ] && [ "$ended" -eq "$total" ] || wrong+=("lines on stderr: $lines, of them ended by a newline: $ended, wanted $total and $total")
  for ((k = 1; k <= total; k++)); do
    line=${on[$((k - 1))]:-}; begun="::warning::check-provenance: $REF: "; [ "$k" -gt "$warnings" ] && begun="::error::check-provenance: $REF: "
    [[ "$line" == "$begun"* ]] || wrong+=("line $k is not begun '$begun'")
    IFS='|' read -ra texts <<<"${HOLD[$k]:-}"
    for each in "${texts[@]}"; do [[ "$line" == *"$each"* ]] || wrong+=("line $k does not carry '$each'"); done
    IFS='|' read -ra texts <<<"${LACK[$k]:-}"
    for each in "${texts[@]}"; do [[ "$line" != *"$each"* ]] || wrong+=("line $k carries '$each', which is another attempt's"); done
    [ "$k" -le "$warnings" ] && [[ "$line" == *"Error: "* || "$line" == *"error during command execution"* ]] && wrong+=("line $k holds one of cosign's prefixes 'Error: ' and 'error during command execution'")
  done
  # what the ok line says of the error line: the texts it was held to carry
  if [ "$total" -gt "$warnings" ]; then
    IFS='|' read -ra texts <<<"${HOLD[$total]:-}"
    for each in "${texts[@]}"; do held+="${held:+ and }'$each'"; done
    last=", then the error line${held:+, which carries $held}"
  fi
  [ "${#wrong[@]}" -eq 0 ] && pass "$name: stderr is exactly $total lines: $warnings warnings, each carrying what cosign said in its attempt$last" \
    || fail "$name: stderr: exactly $total lines, each ended by its newline: $warnings begun '::warning::check-provenance: $REF: ' that carry what cosign said in their attempt and no prefix of cosign's$([ "$total" -gt "$warnings" ] && echo ", then one begun '::error::check-provenance: $REF: ' that says '3 attempts' and carries the third attempt's words")" \
         "${wrong[@]}" "stderr:" "${err:-nothing}"
  calls=$(grep -c '' "$SB/cosign.log")
  for ((k = 1; k <= $4; k++)); do [ "$(sed -n "${k}p" "$SB/cosign.log" | asked)" = "$want" ] && same=$((same + 1)); done
  [ "$calls" -eq "$4" ] && [ "$same" -eq "$4" ] && pass "$name: cosign is called $4 times, each time with the whole argument set case 1 holds" \
    || fail "$name: the cosign calls the stub logged: $4, each with the argument set case 1 holds" "calls logged: $calls, wanted $4; of the first $4, those with that set: $same, wanted $4" "$([ -s "$SB/cosign.log" ] && cat "$SB/cosign.log" || echo "cosign was never called")"
  pauses "$name" "$warnings" 0
}
# the first two calls refuse, each naming its own workflow file; the third accepts
retry_sandbox 2; HOLD=("" "${NAMED[1]}" "${NAMED[2]}"); LACK=("" "${NAMED[2]}" "${NAMED[1]}")
run verify "$SB/root" "$REF"; tried "cosign refusing twice, then accepting" 0 2 3
retry_sandbox 1; HOLD=("" "${NAMED[1]}"); LACK=("" "${NAMED[2]}")
run verify "$SB/root" "$REF"; tried "cosign refusing once, then accepting" 0 1 2
# the first call ends as a Go program that panics does (case 2's go_trace,
# exit 2): the one warning carries a word of the trace's first line and one
# of its last
retry_sandbox 0; HOLD=("" "dereference|main.go:14"); LACK=()
go_trace > "$SB/crash.1"
run verify "$SB/root" "$REF"; tried "cosign crashing once, then accepting" 0 1 2
# five calls would refuse: two warnings, the error line, no pause after the third
retry_sandbox 5; HOLD=("" "${NAMED[1]}" "${NAMED[2]}" "3 attempts|${NAMED[3]}"); LACK=("" "${NAMED[2]}" "${NAMED[1]}")
run verify "$SB/root" "$REF"; tried "cosign refusing on every attempt" 1 2 3
# the first input again, started with the variable 7, then with it not set
retry_sandbox 2; PAUSE=7 run verify "$SB/root" "$REF"
exit_is "the pause is CHECK_PROVENANCE_RETRY_DELAY seconds" 0; pauses "the pause is CHECK_PROVENANCE_RETRY_DELAY seconds" 2 7
retry_sandbox 2; PAUSE=unset run verify "$SB/root" "$REF"
exit_is "the pause is 10 seconds with the variable not set" 0; pauses "the pause is 10 seconds with the variable not set" 2 10
retry_sandbox 0; run verify "$SB/root" "$REF"; pauses "cosign accepting at once" 0 0

# 12: only a cosign call that fails is tried again, and what a failed attempt
#    printed is never read (plan slice 2.5.12, a guard). What cosign printed
#    with exit 0 is its answer and is judged once: a statement that misses an
#    expectation, and an answer with no statement in it, are final at once,
#    also when an attempt failed before. Asking again does not change a
#    statement that was signed and stored, it only costs the release two
#    pauses; and a statement left over from an attempt cosign itself gave up
#    on was never verified. Five inputs, each through case 11's retry_sandbox
#    and judged by tried. For the last two the first call, which refuses,
#    prints on its stdout an envelope whose statement meets all five (the
#    stub's refused.stdout.<n>, see fresh).
# the clause of a statement built from another branch
off='ref is "refs/heads/feature", expected "'"$GIT_REF"'"'
# an accepting call answers with that statement and no other
off_branch() { envelopes "$(statement "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" refs/heads/feature)" > "$SB/envelopes.jsonl"; }
# the first call, refusing, prints the envelope retry_sandbox laid down, whose
# statement meets all five
printed_by_refused() { cp "$SB/envelopes.jsonl" "$SB/refused.stdout.1"; }
# beside tried, and heard only when it fails: stderr's last line, the error
# line, holds ', expected ' once, so one clause and no more
one_clause() {
  local claims; claims=$(tail -n 1 "$SB/stderr" | occurs ", expected ")
  [ "$claims" -eq 1 ] || fail "$1: the error line holds one clause and no more" "times ', expected ' is in the last line of stderr: $claims, wanted 1" "stderr:" "${err:-nothing}"
}
# cosign accepts at once: no warning, no pause, no second call
retry_sandbox 0; off_branch; HOLD=("" "$off"); LACK=()
run verify "$SB/root" "$REF"; tried "an answer that misses the ref, at the first attempt" 1 0 1
# the first call refuses, the second accepts: no third call, one pause
retry_sandbox 1; off_branch; HOLD=("" "${NAMED[1]}" "$off"); LACK=("" "${NAMED[2]}")
run verify "$SB/root" "$REF"; tried "one refusal, then an answer that misses the ref" 1 1 2
retry_sandbox 1; : > "$SB/envelopes.jsonl"; HOLD=("" "${NAMED[1]}" "no provenance statement"); LACK=("" "${NAMED[2]}")
run verify "$SB/root" "$REF"; tried "one refusal, then an answer with no statement" 1 1 2
# a script that reads what the failed attempt printed passes this digest
retry_sandbox 1; printed_by_refused; : > "$SB/envelopes.jsonl"; HOLD=("" "${NAMED[1]}" "no provenance statement"); LACK=("" "${NAMED[2]}")
run verify "$SB/root" "$REF"; tried "a refused attempt that printed a statement which meets all five, then an accepting attempt that prints nothing" 1 1 2
retry_sandbox 1; printed_by_refused; off_branch; HOLD=("" "${NAMED[1]}" "$off"); LACK=("" "${NAMED[2]}")
run verify "$SB/root" "$REF"; tried "a refused attempt that printed a statement which meets all five, then an answer that misses the ref" 1 1 2
one_clause "a refused attempt that printed a statement which meets all five, then an answer that misses the ref"

# 14: what cannot serve is told by its cause (plan slice 2.5.14, FR-1). When
#    the self-check cannot be made, because the policy file cannot be read or
#    a tool it needs is missing or fails, the line has to name that cause and
#    no other: a file that is no YAML and a python without its yaml module
#    both read "gives no verification.issuer" otherwise, a missing jq "no
#    provenance statement", a missing cosign costs three attempts, and whoever
#    repairs the release looks in the wrong place. Eight inputs under the
#    first identity, each over a fresh sandbox and one envelope whose
#    statement meets all five, so that a script that goes on gets an answer
#    that passes. Wanted: exit 2; nothing on stdout; stderr one line, begun
#    '::error::check-provenance: ', that holds the two phrases of its cause,
#    no phrase of another cause or of another failure and nothing of a tool's
#    own words; cosign never called.
# The suite's PATH with the tool $1 on none of its directories and every other
# program as before: for each directory that holds the tool stands one made
# under $TOP, outside any sandbox, with a link to each of its other entries.
# Made once per tool and kept in $TOP/without.<tool>/path; printed on stdout
path_without() {
  local at="$TOP/without.$1" dir n=0 path=""
  if [ ! -f "$at/path" ]; then
    mkdir -p "$at"
    while IFS= read -r -d : dir; do
      if [ -n "$dir" ] && { [ -e "$dir/$1" ] || [ -L "$dir/$1" ]; }; then
        n=$((n + 1)); mkdir "$at/$n"
        find "$(cd "$dir" && pwd -P)" -mindepth 1 -maxdepth 1 ! -name "$1" -exec ln -s -t "$at/$n" {} +
        dir="$at/$n"
      fi
      path+="$dir:"
    done <<<"$PATH:"
    printf '%s' "${path%:}" > "$at/path"
  fi
  cat "$at/path"
}
# a fresh sandbox with the one envelope; the input's fault is laid down after
cause_sandbox() {
  fresh
  envelopes "$(all_five)" > "$SB/envelopes.jsonl"
}
# the second phrase of each cause; the first is the file's or the tool's name
CAUSES=("cannot be opened" "cannot be read as YAML" "yaml module" "not found on PATH" "no directory for temporary files")
# after an input's run: $1 names the input, $2 and $3 are its cause's phrases
told_by_cause() {
  local name=$1 each; local -a wrong=()
  exit_is "$name" 2
  no_stdout "$name"
  one_line "$SB/stderr" || wrong+=("stderr is not exactly one line, ended by its newline: lines on it: $(grep -c '' "$SB/stderr"), of them ended by a newline: $(wc -l < "$SB/stderr")")
  begun_error
  for each in "$2" "$3"; do [[ "$err" == *"$each"* ]] || wrong+=("it does not hold '$each'"); done
  for each in "${CAUSES[@]}"; do
    [ "$each" = "$3" ] || [[ "$err" != *"$each"* ]] || wrong+=("it holds '$each', the phrase of another cause")
  done
  for each in "gives no verification." "no provenance statement" "gave no answer" "3 attempts"; do
    [[ "$err" != *"$each"* ]] || wrong+=("it holds '$each', the line of another failure")
  done
  for each in "Traceback" "ModuleNotFoundError" "command not found" "No such file" "Permission denied" "failed to create"; do
    [[ "$err" != *"$each"* ]] || wrong+=("it holds '$each', a tool's own words")
  done
  [ "${#wrong[@]}" -eq 0 ] && pass "$name: stderr is one line, the script's error line, which holds '$2' and '$3', no phrase of another cause or failure and nothing of a tool's own words" \
    || fail "$name: stderr: one line and no more, begun '::error::check-provenance: ', that holds '$2' and '$3', no phrase of another cause or failure and nothing of a tool's own words" \
         "${wrong[@]}" "stderr:" "${err:-nothing}" "wanted: ::error::check-provenance: <a reason that holds $2 and $3>"
  never_asked "$name" "what cannot be made ends before cosign is asked"
}
cause_sandbox; echo "verification: [not closed" > "$SB/root/catalogue-policy.yaml"
run verify "$SB/root" "$REF"; told_by_cause "the policy file is no YAML, a bracket not closed" catalogue-policy.yaml "cannot be read as YAML"
# the byte 0xFF, which no UTF-8 text holds, before the file as fresh writes it
cause_sandbox; { printf '\xff'; policy_with "  issuer: $ISSUER" "      identity: $RELEASER"; } > "$SB/root/catalogue-policy.yaml"
run verify "$SB/root" "$REF"; told_by_cause "the policy file is not UTF-8" catalogue-policy.yaml "cannot be read as YAML"
# the file as fresh writes it, its mode taken off for the run and put back
# after it. The watch inside run cannot read it either: it holds the file by
# its kind and its path in this run, not by its checksum, and its sha256sum
# says so on stderr, once before the run and once after it. Those two lines
# are kept back by the redirection on this one call of run, so that the
# suite's own stderr stays empty; on this call alone, since on every other
# what the watch or the shell writes there is a fault to be seen. As root no
# file mode keeps a file from being read: the input cannot be laid down
# there, is not run, and one line says so in the place of its four
if [ "$(id -u)" -eq 0 ]; then
  pass "the policy file cannot be opened: not asked here, the suite runs as root and no file mode keeps root from reading"
else
  cause_sandbox; mode=$(stat -c %a "$SB/root/catalogue-policy.yaml"); chmod 000 "$SB/root/catalogue-policy.yaml"
  run verify "$SB/root" "$REF" 2>/dev/null; chmod "$mode" "$SB/root/catalogue-policy.yaml"
  told_by_cause "the policy file cannot be opened" catalogue-policy.yaml "cannot be opened"
fi
# a stand-in that starts the real python3, arguments as they came, with a
# directory first among its modules' whose yaml.py raises what a python
# without the module raises; python is told to write no cache beside it
cause_sandbox; mkdir "$SB/no-yaml"; echo "raise ModuleNotFoundError(\"No module named 'yaml'\")" > "$SB/no-yaml/yaml.py"
printf '#!/usr/bin/env bash\nPYTHONDONTWRITEBYTECODE=1 PYTHONPATH=%q exec %q "$@"\n' "$SB/no-yaml" "$(command -v python3)" > "$SB/bin/python3"; chmod +x "$SB/bin/python3"
run verify "$SB/root" "$REF"; told_by_cause "python3 has no yaml module" python3 "yaml module"
cause_sandbox; HIDE=python3 run verify "$SB/root" "$REF"; told_by_cause "python3 is not on PATH" python3 "not found on PATH"
cause_sandbox; HIDE=jq run verify "$SB/root" "$REF"; told_by_cause "jq is not on PATH" jq "not found on PATH"
# the stub is no cosign on PATH either: it is taken out of the sandbox
cause_sandbox; rm "$SB/bin/cosign"
HIDE=cosign run verify "$SB/root" "$REF"; told_by_cause "cosign is not on PATH" cosign "not found on PATH"
# a stand-in that fails in GNU mktemp's words
cause_sandbox; printf '%s\n' '#!/usr/bin/env bash' "echo \"mktemp: failed to create directory via template '/tmp/tmp.XXXXXXXXXX': No such file or directory\" >&2" 'exit 1' > "$SB/bin/mktemp"; chmod +x "$SB/bin/mktemp"
run verify "$SB/root" "$REF"; told_by_cause "mktemp fails" mktemp "no directory for temporary files"

# 15: a value the script cannot use is refused before cosign is asked (plan
#    slice 2.5.15, FR-1 as amended 2026-11-17). Three values pass the cases
#    above and end elsewhere: an identity with an empty scheme is asked of
#    cosign and refused there three times; a reference whose image name holds
#    an @ reaches cosign as one it cannot read; a pause of 'soon' makes sleep
#    fail, the attempts follow each other at once and nobody is told. Ten
#    inputs under the first identity. The identity is refused as in case 10c,
#    the two references as in case 10b. The pause, CHECK_PROVENANCE_RETRY_DELAY,
#    is 10 seconds where it is not set or set and empty; otherwise it has to be
#    a whole number of seconds, digits alone. Six that are not, each with
#    cosign accepting at once, so that no attempt fails and the refusal has to
#    come at the start. Wanted: exit 2; nothing on stdout; stderr one line,
#    begun '::error::check-provenance: ', that names the variable and holds
#    the value and nothing of the shell's or sleep's own words; neither cosign
#    nor sleep called. Set and empty, the pause stays 10 seconds.
# One pause that cannot be used: $1 says what it is, $2 is the value
pause_refused() {
  local name="the pause is $1" value=$2 each calls; local -a wrong=()
  retry_sandbox 0; PAUSE=$value run verify "$SB/root" "$REF"
  exit_is "$name" 2
  no_stdout "$name"
  one_line "$SB/stderr" || wrong+=("stderr is not exactly one line, ended by its newline: lines on it: $(grep -c '' "$SB/stderr"), of them ended by a newline: $(wc -l < "$SB/stderr")")
  begun_error
  for each in CHECK_PROVENANCE_RETRY_DELAY "$value"; do
    [[ "$err" == *"$each"* ]] || wrong+=("it does not hold '$each'")
  done
  for each in "invalid time interval" "unbound variable"; do
    [[ "$err" != *"$each"* ]] || wrong+=("it holds '$each', sleep's or the shell's own words")
  done
  [ "${#wrong[@]}" -eq 0 ] && pass "$name: stderr is one line, the script's error line, which names CHECK_PROVENANCE_RETRY_DELAY and holds the value as given" \
    || fail "$name: stderr: one line and no more, begun '::error::check-provenance: ', that holds CHECK_PROVENANCE_RETRY_DELAY and '$value', and neither 'invalid time interval' nor 'unbound variable'" \
         "${wrong[@]}" "stderr:" "${err:-nothing}" "wanted: ::error::check-provenance: <a reason that names CHECK_PROVENANCE_RETRY_DELAY and holds '$value'>"
  calls=$(cat "$SB/cosign.log" "$SB/sleep.log" | grep -c '')
  [ "$calls" -eq 0 ] && pass "$name: cosign is never called and sleep is never called" \
    || fail "$name: the calls of cosign and of sleep the stand-ins logged: none, a pause that cannot be used is refused at the start" "calls logged: $calls, wanted 0:" "$(cat "$SB/cosign.log" "$SB/sleep.log")"
}
unusable_values() {
  local image=${REF%@*} hex=${REF##*:}
  identity_without_form "has an empty scheme, it begins with ://" "://${RELEASER#*://}"
  no_reference "an image name that itself holds @sha256: and a digest, then @sha256: and the digest" "$REF@sha256:$hex"
  no_reference "an image name with an @ in it" "${image%/*}@${image##*/}@sha256:$hex"
  pause_refused "soon" soon
  pause_refused "1.5" 1.5
  pause_refused "-1" -1
  pause_refused "10s" 10s
  pause_refused "a blank" " "
  pause_refused "3 and 4, two numbers with a blank between them" "3 4"
  # case 11's first input, the variable set to the empty string: still 10 seconds
  retry_sandbox 2; PAUSE=empty run verify "$SB/root" "$REF"
  exit_is "the pause is set and empty" 0; pauses "the pause is set and empty" 2 10
}
unusable_values

# 16: report over references that are all covered says so of each (plan slice
#    3.1.1, FR-3 as amended 2026-11-19, Req 2.29). The mode report takes the
#    root and then one or more references, and asks of each, in the order
#    given, the question verify asks of one. Three references that differ in
#    their image names and in their digests, none of them the suite's, given
#    in an order that is neither that of their names nor that of their digests
#    sorted either way; cosign answers each call with one envelope whose
#    statement meets all five. Wanted: exit 0; stdout exactly one line per
#    reference, 'covered', ONE tab and the reference, in the order given, each
#    line ended by its newline, and not a byte more: no heading, no count, and
#    not the line verify prints of a digest that passed; nothing on stderr,
#    cosign's own report is not passed on under report either; cosign called
#    three times, once per reference in the order given, each call with the
#    arguments verify hands it for that reference, compared as a whole set as
#    in case 1 (so no call carries two references, and none a flag more).
#    Then one reference alone, the second of the three: one line, exit 0, one
#    call.
# One input: $1 names it, the references follow in the order they are given.
# The mode word is report unless the caller names another in MODE (case 19)
all_covered() {
  local name=$1 each want got calls nth=0; local -a wrong=()
  shift
  fresh; envelopes "$(all_five)" > "$SB/envelopes.jsonl"
  run "${MODE:-report}" "$SB/root" "$@"
  exit_is "$name" 0 "every reference was asked, and each of them is covered"
  # byte for byte: a word after each text keeps the newlines at its end, which
  # $( ) would drop, so a last line without its newline differs, and so does
  # an empty line more
  want=$(printf 'covered\t%s\n' "$@"; echo end); got=$(cat "$SB/stdout" 2>/dev/null; echo end)
  [ "$got" = "$want" ] && pass "$name: stdout is exactly one line per reference, 'covered', a tab and the reference, in the order given" \
    || fail "$name: stdout: exactly one line per reference, 'covered', one tab and the reference, in the order given, each ended by a newline, and nothing else" \
         "stdout (as cat -A shows it: a tab reads ^I, a line's end \$):" "$(cat -A "$SB/stdout" 2>/dev/null | grep '' || echo nothing)" \
         "wanted, the same way:" "$(printf 'covered\t%s\n' "$@" | cat -A)"
  [ ! -s "$SB/stderr" ] && pass "$name: nothing on stderr" \
    || fail "$name: stderr: nothing, every reference is covered and cosign's own report is not passed on" "stderr:" "$(cat "$SB/stderr")" "wanted: nothing"
  calls=$(grep -c '' "$SB/cosign.log")
  [ "$calls" -eq "$#" ] && pass "$name: cosign is called $# time(s), once per reference" \
    || fail "$name: the cosign calls the stub logged: $#, one per reference" "calls logged: $calls, wanted $#:" "$([ -s "$SB/cosign.log" ] && cat "$SB/cosign.log" || echo "cosign was never called")"
  for each in "$@"; do
    nth=$((nth + 1))
    want=$(echo verify-attestation; printf '%s\n' "--type slsaprovenance1" "--certificate-oidc-issuer $ISSUER" "--certificate-identity $RELEASER" "$each" | LC_ALL=C sort)
    got=$(sed -n "${nth}p" "$SB/cosign.log" | asked)
    [ "$got" = "$want" ] || wrong+=("call $nth, as the stub logged it: $(sed -n "${nth}p" "$SB/cosign.log" | grep '' || echo "there is no such call")" \
      "  what it asked (the first argument, then the others sorted, a flag on one line with its value):" "${got:-nothing}" \
      "  wanted, the same way, the call verify makes for reference $nth:" "$want")
  done
  [ "${#wrong[@]}" -eq 0 ] && pass "$name: each call, in the order the references were given, is the call verify makes for that reference, and not one argument more" \
    || fail "$name: the cosign calls in their order: the first about the first reference and so on, each verify-attestation with --type slsaprovenance1, the policy file's issuer, the releaser's identity and that one reference, nothing else" \
         "${wrong[@]}"
}
covered_references() {
  local first="registry.example.test/tools/sprocket@sha256:7c1e9a3b5d2f4a6c8e0b1d3f5a7c9e2b4d6f8a0c1e3b5d7f9a2c4e6b8d0f1a3c"
  local second="ghcr.io/acme/anvil@sha256:e4a1c8f2b6d09e3a7c5b1f8d2e6a4c0b9f7d3e1a5c8b2f6d0e4a9c7b3f1d5e8a"
  local third="ghcr.io/acme/gadgets-server@sha256:0d9b7f5e3c1a8e6c4b2f0d9a7e5c3b1f8d6a4e2c0b9f7d5a3e1c8b6f4d2a0e9c"
  all_covered "report over three covered references" "$first" "$second" "$third"
  all_covered "report over one covered reference" "$second"
}
covered_references

# 17: an uncovered reference neither fails nor stops report (plan slice 3.1.2,
#    FR-3 as amended 2026-11-19, Req 2.29: an absent attestation never fails
#    the run). report asks every reference it is given, covered or not, and
#    says of one that is not covered what verify would say of it: on stdout
#    the line 'uncovered', ONE tab, the reference, ONE tab and the reason,
#    which is byte for byte the one ::error:: line verify ends on for that
#    reference, without its leading '::error::' (so it begins
#    'check-provenance: ' and ends '(Req 2.28)'). Four ways a reference is not
#    covered: cosign refuses it at all three attempts (twice the registry does
#    not answer, the third time 'no matching attestations: ', nothing beside
#    the digest); cosign verifies for it a statement built from another ref;
#    cosign ends with 0 for it and prints nothing; jq gives no answer when
#    asked for the first value of its statement (case 4b's stand-in, the one
#    call alone). Seven inputs over references that differ in name and digest:
#    each of the four ways with the uncovered reference between two covered
#    ones; then it stands first, then last, then two of four are uncovered and
#    stand next to each other. Every other reference is answered with a
#    statement that meets all five.
#    Wanted of each input: exit 0; stdout exactly one line per reference in
#    the order given, 'covered', a tab and the reference, or the uncovered
#    line above, and not a byte more; stderr without any line begun
#    '::error::': for a refused reference exactly the two ::warning:: lines
#    verify writes of its first two attempts, for the other three ways nothing;
#    every reference asked, also those after the uncovered one: three cosign
#    calls for a refused reference and one for each other, each the call
#    verify makes for that reference.
#    The wanted reason and warnings are not written out here: before report is
#    run, verify is asked about each uncovered reference by itself, in a
#    sandbox of its own under the same answers, and what it wrote is held to
#    what the cases above hold of verify's lines (exit 1, nothing on stdout,
#    one error line in its frame that tells the way, two warnings before it
#    for a refusal and none otherwise). That run is heard only when it fails:
#    the input cannot be judged then, and one FAIL line says so.
# a fresh sandbox for one run: the stand-in for sleep as in case 11, the one
# for jq where $1 is yes, and one envelope whose statement meets all five,
# what every cosign call answers that the input does not name
report_sandbox() {
  fresh; sleep_stand_in
  [ "$1" = yes ] && jq_stand_in
  envelopes "$(all_five)" > "$SB/envelopes.jsonl"
}
# The answers that leave one reference uncovered in the way $1, laid down for
# the reference whose first cosign call is the run's $2-th and before whose
# first jq call the run has made $3 jq calls; covered lays down nothing. A
# refused reference takes three cosign calls, any other takes one
not_covered() {
  local i
  case "$1" in
    refused)
      for i in 0 1 2; do : > "$SB/refuses.$(($2 + i))"; done
      unanswered 1 > "$SB/refusal.$2"; unanswered 2 > "$SB/refusal.$(($2 + 1))"
      echo "no matching attestations: " > "$SB/refusal.$(($2 + 2))" ;;
    "another ref") envelopes "$(statement "$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" refs/heads/feature)" > "$SB/envelopes.jsonl.$2" ;;
    "no statement") : > "$SB/envelopes.jsonl.$2" ;;
    # the second jq call about the reference: the first reads the statements
    # (unanswered, it is the line of no statement), the second a value
    "no answer from jq") echo "$(($3 + 2))" > "$SB/jq.no-answer-at" ;;
  esac
}
# whether verify's error line $2 tells the way $1, in the words the cases
# above hold: case 2's and case 11's for a refusal, with the third attempt's
# message and neither of the first two; case 8's clause; case 3's words; and
# for a jq without an answer, whose words are free (case 4b), none of the
# other three and no clause
tells() {
  case "$1" in
    refused) [[ "$2" == *"3 attempts"*"no matching attestations:"* && "$2" != *"connection refused"* ]] ;;
    "another ref") [[ "$2" == *"ref is \"refs/heads/feature\", expected \"$GIT_REF\""* ]] ;;
    "no statement") [[ "$2" == *"no provenance statement"* ]] ;;
    "no answer from jq") [[ "$2" != *"3 attempts"* && "$2" != *"no provenance statement"* && "$2" != *", expected "* ]] ;;
  esac
}
# One input: $1 names it; then for each reference, in the order report is
# given them, a way (covered, or one of not_covered's four) and the reference.
# A reference jq gives no answer about stands after covered ones only: the
# number of its jq call is counted from theirs, $per_reference each.
# The mode word is report unless the caller names another in MODE (case 20).
# Under another word, require, two things are wanted otherwise: exit 1, and on
# stderr, after the warnings of each uncovered reference, the ::error:: line
# verify ends on for it, so for each such reference all that verify wrote on
# stderr when asked about it alone, the references in the order given
some_uncovered() {
  local name=$1 mode=${MODE:-report} i k kind each line rest errors lines ended warned want got calls total nth=0 call=1 asked_jq=0 with_jq=no want_out="" want_err=""
  local -a kinds=() given=() takes=() wrong=()
  shift
  while [ $# -gt 0 ]; do kinds+=("$1"); given+=("$2"); shift 2; done
  for kind in "${kinds[@]}"; do [ "$kind" = "no answer from jq" ] && with_jq=yes; done
  # what verify writes of each uncovered reference, asked about it alone
  for i in "${!given[@]}"; do
    kind=${kinds[i]}; each=${given[i]}
    if [ "$kind" = covered ]; then want_out+="covered"$'\t'"$each"$'\n'; continue; fi
    report_sandbox "$with_jq"; not_covered "$kind" 1 0
    run verify "$SB/root" "$each"
    warned=0; [ "$kind" = refused ] && warned=2
    errors=$(grep -c '^::error::' "$SB/stderr"); lines=$(grep -c '' "$SB/stderr"); ended=$(wc -l < "$SB/stderr"); line=$(tail -n 1 "$SB/stderr")
    # a word after the text keeps the newline at its end, which $( ) would drop
    rest=$(grep -v '^::error::' "$SB/stderr"; echo end); rest=${rest%end}
    if [ "$rc" -ne 1 ] || [ -s "$SB/stdout" ] || [ "$errors" -ne 1 ] || [ "$lines" -ne $((warned + 1)) ] || [ "$ended" -ne "$lines" ] \
      || [ "$(grep -c "^::warning::check-provenance: $each: " "$SB/stderr")" -ne "$warned" ] \
      || [[ "$line" != "::error::check-provenance: $each: "*" (Req 2.28)" ]] || ! tells "$kind" "$line"; then
      fail "$name: verify asked about reference $((i + 1)) alone, under the same answers ($kind), ends as the cases above hold it to; without that the input is not judged" \
           "exit=$rc; lines on stderr: $lines, of them ended by a newline: $ended, begun '::error::': $errors" "stdout:" "${out:-nothing}" "stderr:" "${err:-nothing}" \
           "wanted: exit 1; nothing on stdout; stderr $warned line(s) begun '::warning::check-provenance: $each: ' and then one line '::error::check-provenance: $each: <a reason that tells the way: $kind> (Req 2.28)', each ended by its newline"
      return
    fi
    want_out+="uncovered"$'\t'"$each"$'\t'"${line#::error::}"$'\n'; want_err+=$rest
    [ "$mode" = report ] || want_err+=$line$'\n'
  done
  # report over all of them, the answers laid down call by call
  report_sandbox "$with_jq"
  for i in "${!given[@]}"; do
    not_covered "${kinds[i]}" "$call" "$asked_jq"
    takes[i]=1; [ "${kinds[i]}" = refused ] && takes[i]=3
    call=$((call + takes[i])); asked_jq=$((asked_jq + per_reference))
  done
  total=$((call - 1))
  run "$mode" "$SB/root" "${given[@]}"
  if [ "$mode" = report ]; then
    exit_is "$name" 0 "every reference was asked, and a reference that is not covered does not fail report (Req 2.29)"
  else
    exit_is "$name" 1 "one or more references are not covered, which fails $mode, whatever their number and wherever they stand among the others"
  fi
  got=$(cat "$SB/stdout" 2>/dev/null; echo end)
  [ "$got" = "${want_out}end" ] && pass "$name: stdout is exactly one line per reference in the order given, 'covered', a tab and the reference, or 'uncovered', a tab, the reference, a tab and verify's error line for it without '::error::'" \
    || fail "$name: stdout: exactly one line per reference in the order given, 'covered', one tab and the reference, or 'uncovered', one tab, the reference, one tab and the line verify ends on for that reference without its leading '::error::', each ended by a newline, and nothing else" \
         "stdout (as cat -A shows it: a tab reads ^I, a line's end \$):" "$(cat -A "$SB/stdout" 2>/dev/null | grep '' || echo nothing)" \
         "wanted, the same way:" "$(printf '%s' "$want_out" | cat -A)"
  errors=$(grep -c '^::error::' "$SB/stderr"); got=$(cat "$SB/stderr" 2>/dev/null; echo end)
  if [ "$mode" != report ]; then
    [ "$got" = "${want_err}end" ] && pass "$name: stderr is, for each uncovered reference in the order given, exactly what verify writes of it: the warnings of its failed attempts and then its one '::error::' line, and nothing else" \
      || fail "$name: stderr: for each uncovered reference, in the order given, the ::warning:: lines verify writes of its failed attempts that another follows and then the one ::error:: line verify ends on for it, byte for byte and once, the lines of one reference together, each ended by a newline, and nothing else" \
           "lines on stderr begun '::error::': $errors, wanted $(printf '%s' "$want_err" | grep -c '^::error::'), one per uncovered reference" \
           "stderr (as cat -A shows it: a line's end reads \$):" "$(cat -A "$SB/stderr" 2>/dev/null | grep '' || echo nothing)" "wanted, the same way:" "$(printf '%s' "$want_err" | cat -A)"
  else
  [ "$got" = "${want_err}end" ] && pass "$name: stderr holds no line begun '::error::', and is $([ -n "$want_err" ] && echo "exactly the two warnings verify writes of each refused reference's first two attempts" || echo "empty")" \
    || fail "$name: stderr: no line begun '::error::', and $([ -n "$want_err" ] && echo "exactly the ::warning:: lines verify writes of the failed attempts that another follows, in the order of the references" || echo "nothing at all")" \
         "lines on stderr begun '::error::': $errors, wanted 0" "stderr:" "${err:-nothing}" "wanted:" "$(printf '%s' "$want_err" | grep '' || echo nothing)"
  fi
  calls=$(grep -c '' "$SB/cosign.log")
  [ "$calls" -eq "$total" ] || wrong+=("calls logged: $calls, wanted $total")
  for i in "${!given[@]}"; do
    want=$(echo verify-attestation; printf '%s\n' "--type slsaprovenance1" "--certificate-oidc-issuer $ISSUER" "--certificate-identity $RELEASER" "${given[i]}" | LC_ALL=C sort)
    for ((k = 0; k < takes[i]; k++)); do
      nth=$((nth + 1)); got=$(sed -n "${nth}p" "$SB/cosign.log" | asked)
      [ "$got" = "$want" ] || wrong+=("call $nth, wanted about reference $((i + 1)) (${kinds[i]}), as the stub logged it: $(sed -n "${nth}p" "$SB/cosign.log" | grep '' || echo "there is no such call")")
    done
  done
  [ "${#wrong[@]}" -eq 0 ] && pass "$name: cosign is called $total times, three for a refused reference and one for each other, also for those after the uncovered one, each the call verify makes for its reference" \
    || fail "$name: the cosign calls the stub logged: $total, three for a refused reference and one for each other, the references after an uncovered one asked as well, each call verify-attestation with --type slsaprovenance1, the policy file's issuer, the releaser's identity and its one reference" \
         "${wrong[@]}" "the log:" "$([ -s "$SB/cosign.log" ] && cat "$SB/cosign.log" || echo "cosign was never called")"
}
uncovered_references() {
  local first="registry.example.test/tools/sprocket@sha256:e951d951d900000bf3f37bf37bf37ba2adc7bf32d951d444fa2a2a2a22adf518"
  local second="ghcr.io/acme/anvil@sha256:244444f97bf371d9518837bf37bf32a2a2a251d951d95188888837ba25000000"
  local third="ghcr.io/acme/gadgets-server@sha256:6f51d4444444ccccc72a2a2a2a2a2a2adccccc7bf32060000bf3888888800000"
  local fourth="ghcr.io/acme/bellows@sha256:d6e6951d951d9518ec2a251d90000000bf3200000bf37ba2a2a2a2a2a2a2a251"
  local per_reference
  # the jq calls of a run about one covered reference, counted as in case 4b:
  # as many pass before the first jq call about the reference after it
  fresh; jq_stand_in; envelopes "$(all_five)" > "$SB/envelopes.jsonl"
  run verify "$SB/root" "$first"; per_reference=$(grep -c '' "$SB/jq.log")
  [ "$rc" -eq 0 ] && [ "$per_reference" -ge 2 ] \
    || fail "report with an uncovered reference: the jq calls of a run about one covered reference are counted" "exit=$rc, wanted 0; jq calls the stand-in logged: $per_reference, wanted 2 or more" "stderr:" "${err:-nothing}"
  some_uncovered "report, the second of three references refused by cosign at all three attempts" covered "$first" refused "$second" covered "$third"
  some_uncovered "report, the second of three references with a statement built from another ref" covered "$first" "another ref" "$second" covered "$third"
  some_uncovered "report, the second of three references with no statement verified" covered "$first" "no statement" "$second" covered "$third"
  some_uncovered "report, the second of three references with jq giving no answer about its statement" covered "$first" "no answer from jq" "$second" covered "$third"
  some_uncovered "report, the first of three references refused by cosign at all three attempts" refused "$third" covered "$first" covered "$second"
  some_uncovered "report, the last of three references with a statement built from another ref" covered "$second" covered "$third" "another ref" "$first"
  some_uncovered "report, the second and the third of four references uncovered" covered "$fourth" refused "$first" "another ref" "$third" covered "$second"
}
uncovered_references

# 18: a report that cannot be made asks nothing (plan slice 3.1.3, FR-3 as
#    amended 2026-11-19). Everything verify ends with exit 2 on ends report
#    the same way, before cosign is asked about ANY reference: a report over
#    half the references, or one that asked under a fault, would read as a
#    finding about the images where it is the call, the policy file or the
#    machine that is at fault. 16 inputs, each over a fresh sandbox in which
#    every cosign call would be answered with a statement that meets all five,
#    so that a script that asks anyway gets an answer that passes:
#    no reference at all after the root, and report alone, which is wrong
#    usage; among three references one that names no image by a sha256 digest
#    (by tag, a digest of 63 hex characters, the empty string), standing
#    first, in the middle and last, the other two being good ones; a root
#    without catalogue-policy.yaml, a policy file that gives no issuer and one
#    that gives no releaser identity; cosign missing from PATH, as in case 14;
#    a pause that is no whole number, as in case 15.
#    Wanted of each: exit 2; NOTHING on stdout, also no 'covered' line for
#    the good references that stand before a bad one; stderr exactly one
#    line, begun '::error::check-provenance: ', with nothing of the shell's
#    or python's own words; cosign never called. For a bad reference the line
#    holds that reference as given and neither of the two good ones, which are
#    not at fault; for no reference it holds the usage form that names report.
#    For the policy, tool and pause inputs the line is byte for byte the one
#    verify writes under the same fault: verify is asked first, in the same
#    sandbox (its line holds the sandbox's paths), about the suite's
#    reference, and what it wrote is held to what the cases above hold of it.
#    That run is heard only when it fails: the input cannot be judged then,
#    and one FAIL line says so.
# One input: $1 names it; $2 is what its line holds, or the words 'as verify'
# for the line verify writes under the same fault; $3 is the fault laid down
# in the sandbox (none, no-policy, no-issuer, no-identity, no-cosign, pause);
# the arguments after them go to the script after the word report as they
# are, the word ROOT standing for the root. Where $2 is a reference, every
# other argument after the root is a good reference, which the line must not
# hold.
# The mode word is report unless the caller names another in MODE (case 21);
# under another the line of an input that is not 'as verify' must not hold
# the word report standing by itself, a blank before it and one after it, be
# it in the sentence or in a usage form: report was not the mode called
report_asks_nothing() {
  local name=$1 held=$2 fault=$3 mode=${MODE:-report} each want="" told="" hide="" pause="" other=""; local -a args=() wrong=(); shift 3
  fresh; envelopes "$(all_five)" > "$SB/envelopes.jsonl"
  case "$fault" in
    no-policy)   rm "$SB/root/catalogue-policy.yaml"; told="catalogue-policy.yaml" ;;
    no-issuer)   policy_with "" "      identity: $RELEASER" > "$SB/root/catalogue-policy.yaml"; told="verification.issuer" ;;
    no-identity) policy_with "  issuer: $ISSUER" "" > "$SB/root/catalogue-policy.yaml"; told="verification.roles.releaser.identity" ;;
    # the stub is no cosign on PATH either: it is taken out of the sandbox
    no-cosign)   rm "$SB/bin/cosign"; hide=cosign; told="cosign is not found on PATH" ;;
    pause)       pause=soon; told="CHECK_PROVENANCE_RETRY_DELAY" ;;
  esac
  if [ "$held" = "as verify" ]; then
    HIDE=$hide PAUSE=$pause run verify "$SB/root" "$REF"
    if [ "$rc" -ne 2 ] || [ -s "$SB/stdout" ] || ! one_line "$SB/stderr" || [[ "$err" != "::error::check-provenance: "*"$told"* ]] || [ -s "$SB/cosign.log" ]; then
      fail "$name: verify under the same fault ends as the cases above hold it to; without that the input is not judged" \
           "exit=$rc; lines on stderr: $(grep -c '' "$SB/stderr"); cosign calls logged: $(grep -c '' "$SB/cosign.log")" "stdout:" "${out:-nothing}" "stderr:" "${err:-nothing}" \
           "wanted: exit 2; nothing on stdout; stderr one line '::error::check-provenance: <a reason that holds $told>'; cosign never called"
      return
    fi
    want=$err
  fi
  for each in "$@"; do [ "$each" = ROOT ] && each="$SB/root"; args+=("$each"); done
  HIDE=$hide PAUSE=$pause run "$mode" ${args[@]+"${args[@]}"}
  exit_is "$name" 2 "a $mode that cannot be made is no $mode: the call, the policy file or the machine is at fault, no image"
  [ ! -s "$SB/stdout" ] && pass "$name: nothing on stdout, no line about any reference" \
    || fail "$name: stdout: nothing, no line about any reference, also not 'covered' for a good one that stands before a bad one" \
         "stdout (as cat -A shows it: a tab reads ^I, a line's end \$):" "$(cat -A "$SB/stdout" 2>/dev/null | grep '' || echo nothing)" "wanted: nothing"
  one_line "$SB/stderr" || wrong+=("stderr is not exactly one line, ended by its newline: lines on it: $(grep -c '' "$SB/stderr"), of them ended by a newline: $(wc -l < "$SB/stderr")")
  begun_error
  if [ "$held" = "as verify" ]; then
    [ "$err" = "$want" ] || wrong+=("it is not byte for byte the line verify writes under the same fault")
  else
    [[ "$err" == *"$held"* ]] || wrong+=("it does not hold '$held'")
    for each in "$@"; do
      [ "$each" = ROOT ] || [ "$each" = "$held" ] || [[ "$err" != *"$each"* ]] || wrong+=("it holds '$each', a reference that is not at fault")
    done
    if [ "$mode" != report ]; then
      other=", not the word report as the mode that was called"
      [[ "$err" != *" report "* ]] || wrong+=("it holds the word report by itself, between two blanks: the mode called was $mode")
    fi
  fi
  for each in "unbound variable" "command not found" "Traceback" "No such file"; do
    [[ "$err" != *"$each"* ]] || wrong+=("it holds '$each', the shell's or python's own words")
  done
  if [ "$held" = "as verify" ]; then
    [ "${#wrong[@]}" -eq 0 ] && pass "$name: stderr is one line, byte for byte the error line verify writes under the same fault" \
      || fail "$name: stderr: one line and no more, byte for byte the error line verify writes under the same fault" \
           "${wrong[@]}" "stderr:" "${err:-nothing}" "wanted, verify's line:" "$want"
  else
    [ "${#wrong[@]}" -eq 0 ] && pass "$name: stderr is one line, the script's error line, which holds '$held', no reference that is not at fault$other and nothing of the shell's or python's" \
      || fail "$name: stderr: one line and no more, begun '::error::check-provenance: ', that holds '$held', no reference that is not at fault$other and neither 'unbound variable' nor 'command not found' nor 'Traceback' nor 'No such file'" \
           "${wrong[@]}" "stderr:" "${err:-nothing}" "wanted: ::error::check-provenance: <a reason that holds '$held'>"
  fi
  never_asked "$name" "a $mode that cannot be made asks about no reference, also not about a good one that stands before a bad one"
}
report_refusals() {
  local first="registry.example.test/tools/sprocket@sha256:7c1e9a3b5d2f4a6c8e0b1d3f5a7c9e2b4d6f8a0c1e3b5d7f9a2c4e6b8d0f1a3c"
  local second="ghcr.io/acme/anvil@sha256:e4a1c8f2b6d09e3a7c5b1f8d2e6a4c0b9f7d3e1a5c8b2f6d0e4a9c7b3f1d5e8a"
  local third="ghcr.io/acme/gadgets-server@sha256:0d9b7f5e3c1a8e6c4b2f0d9a7e5c3b1f8d6a4e2c0b9f7d5a3e1c8b6f4d2a0e9c"
  # the image of the bad references is none of the good ones', so that no
  # good reference is found in the line by a part it shares with the bad one
  local image="ghcr.io/acme/bellows" hex="d6e6951d951d9518ec2a251d90000000bf3200000bf37ba2a2a2a2a2a2a2a251"
  local form='report <root> <image@sha256:digest>' n kind bad
  report_asks_nothing "report and the root, no reference" "$form" none ROOT
  report_asks_nothing "report alone, no root and no reference" "$form" none
  for n in 0 1 2; do
    case $n in
      0) kind="named by tag, no digest"; bad="$image:1.2.3" ;;
      1) kind="one with a digest of 63 hex characters"; bad="$image@sha256:${hex%?}" ;;
      2) kind="the empty string"; bad="" ;;
    esac
    report_asks_nothing "report, the first of three references is $kind" "$bad" none ROOT "$bad" "$first" "$second"
    report_asks_nothing "report, the second of three references is $kind" "$bad" none ROOT "$third" "$bad" "$first"
    report_asks_nothing "report, the last of three references is $kind" "$bad" none ROOT "$second" "$third" "$bad"
  done
  report_asks_nothing "report, the root holds no catalogue-policy.yaml" "as verify" no-policy ROOT "$first" "$second" "$third"
  report_asks_nothing "report, the policy file gives no verification.issuer" "as verify" no-issuer ROOT "$first" "$second" "$third"
  report_asks_nothing "report, the policy file gives no verification.roles.releaser.identity" "as verify" no-identity ROOT "$first" "$second" "$third"
  report_asks_nothing "report, cosign is not on PATH" "as verify" no-cosign ROOT "$first" "$second" "$third"
  report_asks_nothing "report, the pause is soon" "as verify" pause ROOT "$first" "$second" "$third"
}
report_refusals

# 19: require over references that are all covered ends as report does (plan
#    slice 3.2.1, FR-3 as amended 2026-11-19). The mode require takes the root
#    and then one or more references, as report does, and asks of each, in the
#    order given, the question verify asks of one; it differs from report only
#    where a reference is not covered, which a later slice holds. The inputs
#    are case 16's, through case 16's helper under the mode word require: the
#    three references that differ in name and digest, in their order, each
#    answered with one envelope whose statement meets all five, and then the
#    second of them alone. Wanted, as of report over the same answers: exit 0,
#    no reference being uncovered; stdout exactly one line per reference,
#    'covered', ONE tab and the reference, in the order given, each ended by
#    its newline, and not a byte more (not the line verify prints either);
#    nothing on stderr; cosign called once per reference in the order given,
#    each call with the arguments verify hands it for that reference and not
#    one more.
required_covered() {
  local first="registry.example.test/tools/sprocket@sha256:7c1e9a3b5d2f4a6c8e0b1d3f5a7c9e2b4d6f8a0c1e3b5d7f9a2c4e6b8d0f1a3c"
  local second="ghcr.io/acme/anvil@sha256:e4a1c8f2b6d09e3a7c5b1f8d2e6a4c0b9f7d3e1a5c8b2f6d0e4a9c7b3f1d5e8a"
  local third="ghcr.io/acme/gadgets-server@sha256:0d9b7f5e3c1a8e6c4b2f0d9a7e5c3b1f8d6a4e2c0b9f7d5a3e1c8b6f4d2a0e9c"
  MODE=require all_covered "require over three covered references" "$first" "$second" "$third"
  MODE=require all_covered "require over one covered reference" "$second"
}
required_covered

# 20: under require an uncovered reference fails the run, after every
#    reference was asked (plan slice 3.2.2, FR-3 as amended 2026-11-19).
#    require is the mode for where a missing provenance has to stop the
#    release: it tells of each reference what report tells, and of one that is
#    not covered also what verify tells, and ends with 1. The inputs are case
#    17's, through case 17's helper under the mode word require: the four ways
#    a reference is not covered (refused by cosign at all three attempts, a
#    statement built from another ref, no statement, no answer from jq), each
#    between two covered references; then the uncovered one first, then last,
#    then two of four. One input more, which case 17 has no use for: three of
#    four uncovered, the first of them with no warning of its own (another
#    ref) and after it two refused ones next to each other, so that warnings
#    stand after an error line and two references' warnings would stand
#    together if the error lines were kept for the end.
#    Wanted of each input: exit 1; stdout byte for byte what report prints
#    under the same answers, one line per reference in the order given,
#    'covered' or 'uncovered' as in case 17; every reference asked, also those
#    after an uncovered one, the same cosign calls as under report; stderr,
#    for each uncovered reference in the order given, byte for byte what
#    verify writes on stderr when asked about that reference alone under the
#    same answers (the two ::warning:: lines of a refused reference's first
#    two attempts, then the one ::error:: line verify ends on, once), the
#    lines of one reference together, and nothing else: no line for a covered
#    reference, nothing of cosign's or jq's own.
required_uncovered() {
  local first="registry.example.test/tools/sprocket@sha256:e951d951d900000bf3f37bf37bf37ba2adc7bf32d951d444fa2a2a2a22adf518"
  local second="ghcr.io/acme/anvil@sha256:244444f97bf371d9518837bf37bf32a2a2a251d951d95188888837ba25000000"
  local third="ghcr.io/acme/gadgets-server@sha256:6f51d4444444ccccc72a2a2a2a2a2a2adccccc7bf32060000bf3888888800000"
  local fourth="ghcr.io/acme/bellows@sha256:d6e6951d951d9518ec2a251d90000000bf3200000bf37ba2a2a2a2a2a2a2a251"
  local per_reference
  # the jq calls of a run about one covered reference, counted as in case 17
  fresh; jq_stand_in; envelopes "$(all_five)" > "$SB/envelopes.jsonl"
  run verify "$SB/root" "$first"; per_reference=$(grep -c '' "$SB/jq.log")
  [ "$rc" -eq 0 ] && [ "$per_reference" -ge 2 ] \
    || fail "require with an uncovered reference: the jq calls of a run about one covered reference are counted" "exit=$rc, wanted 0; jq calls the stand-in logged: $per_reference, wanted 2 or more" "stderr:" "${err:-nothing}"
  MODE=require some_uncovered "require, the second of three references refused by cosign at all three attempts" covered "$first" refused "$second" covered "$third"
  MODE=require some_uncovered "require, the second of three references with a statement built from another ref" covered "$first" "another ref" "$second" covered "$third"
  MODE=require some_uncovered "require, the second of three references with no statement verified" covered "$first" "no statement" "$second" covered "$third"
  MODE=require some_uncovered "require, the second of three references with jq giving no answer about its statement" covered "$first" "no answer from jq" "$second" covered "$third"
  MODE=require some_uncovered "require, the first of three references refused by cosign at all three attempts" refused "$third" covered "$first" covered "$second"
  MODE=require some_uncovered "require, the last of three references with a statement built from another ref" covered "$second" covered "$third" "another ref" "$first"
  MODE=require some_uncovered "require, the second and the third of four references uncovered" covered "$fourth" refused "$first" "another ref" "$third" covered "$second"
  MODE=require some_uncovered "require, three of four references uncovered, two refused ones after one with a statement built from another ref" "another ref" "$second" refused "$fourth" refused "$first" covered "$third"
}
required_uncovered

# 21: a require that cannot be made asks nothing (plan slice 3.2.3, FR-3 as
#    amended 2026-11-19). Everything verify ends with exit 2 on ends require
#    the same way, before cosign is asked about ANY reference: require is the
#    mode whose exit 1 stops a release for a provenance that is missing, and a
#    call, a policy file or a machine at fault must never read as that, nor as
#    the exit 0 of a release whose every digest is covered, which is what
#    require over no reference at all would say. The inputs are case 18's,
#    through case 18's helper under the mode word require, 16 of them, each
#    over a fresh sandbox in which every cosign call would be answered with a
#    statement that meets all five: no reference at all after the root, and
#    require alone; among three references one that names no image by a
#    sha256 digest (by tag, a digest of 63 hex characters, the empty string),
#    standing first, in the middle and last; a root without
#    catalogue-policy.yaml, a policy file that gives no issuer and one that
#    gives no releaser identity; cosign missing from PATH; a pause that is no
#    whole number.
#    Wanted of each, as of report in case 18: exit 2; NOTHING on stdout, also
#    no 'covered' line for the good references that stand before a bad one;
#    stderr exactly one line, begun '::error::check-provenance: ', with
#    nothing of the shell's or python's own words; cosign never called. For
#    no reference the line holds the usage form that names require, and not
#    the word report as the mode that was called; for a bad reference it holds
#    that reference as given and neither of the two good ones; for the policy,
#    tool and pause inputs it is byte for byte the line verify writes under
#    the same fault, in the same sandbox.
require_refusals() {
  local first="registry.example.test/tools/sprocket@sha256:7c1e9a3b5d2f4a6c8e0b1d3f5a7c9e2b4d6f8a0c1e3b5d7f9a2c4e6b8d0f1a3c"
  local second="ghcr.io/acme/anvil@sha256:e4a1c8f2b6d09e3a7c5b1f8d2e6a4c0b9f7d3e1a5c8b2f6d0e4a9c7b3f1d5e8a"
  local third="ghcr.io/acme/gadgets-server@sha256:0d9b7f5e3c1a8e6c4b2f0d9a7e5c3b1f8d6a4e2c0b9f7d5a3e1c8b6f4d2a0e9c"
  # the image of the bad references is none of the good ones', as in case 18
  local image="ghcr.io/acme/bellows" hex="d6e6951d951d9518ec2a251d90000000bf3200000bf37ba2a2a2a2a2a2a2a251"
  local form='require <root> <image@sha256:digest>...' n kind bad
  MODE=require report_asks_nothing "require and the root, no reference" "$form" none ROOT
  MODE=require report_asks_nothing "require alone, no root and no reference" "$form" none
  for n in 0 1 2; do
    case $n in
      0) kind="named by tag, no digest"; bad="$image:1.2.3" ;;
      1) kind="one with a digest of 63 hex characters"; bad="$image@sha256:${hex%?}" ;;
      2) kind="the empty string"; bad="" ;;
    esac
    MODE=require report_asks_nothing "require, the first of three references is $kind" "$bad" none ROOT "$bad" "$first" "$second"
    MODE=require report_asks_nothing "require, the second of three references is $kind" "$bad" none ROOT "$third" "$bad" "$first"
    MODE=require report_asks_nothing "require, the last of three references is $kind" "$bad" none ROOT "$second" "$third" "$bad"
  done
  MODE=require report_asks_nothing "require, the root holds no catalogue-policy.yaml" "as verify" no-policy ROOT "$first" "$second" "$third"
  MODE=require report_asks_nothing "require, the policy file gives no verification.issuer" "as verify" no-issuer ROOT "$first" "$second" "$third"
  MODE=require report_asks_nothing "require, the policy file gives no verification.roles.releaser.identity" "as verify" no-identity ROOT "$first" "$second" "$third"
  MODE=require report_asks_nothing "require, cosign is not on PATH" "as verify" no-cosign ROOT "$first" "$second" "$third"
  MODE=require report_asks_nothing "require, the pause is soon" "as verify" pause ROOT "$first" "$second" "$third"
}
require_refusals

# 22: a word that is no mode is told all three forms (plan slice 3.2.4, FR-3 as
#    amended 2026-11-19). The script has three modes, and a caller whose first
#    word is none of them has to read in the one line which words there are
#    and what stands after each: told verify's form alone, as while verify was
#    the one mode, whoever mistyped report or require would learn nothing of
#    the mode he meant. Six inputs, each over a fresh sandbox and one envelope
#    whose statement meets all five, so that a script that asks cosign anyway
#    gets an answer that passes: the mode words reprot, check, REPORT and
#    Require (a mode's name in other letters is no mode: the words are told
#    apart to the letter) and the empty string as mode word, each followed by
#    the root and one reference, and no argument at all. Wanted of each: exit
#    2; nothing on stdout; stderr exactly one line, begun
#    '::error::check-provenance: ', that holds ALL THREE usage forms, each
#    written out, 'verify <root> <image@sha256:digest>' (as it stands, no
#    three dots behind it: verify takes one reference),
#    'report <root> <image@sha256:digest>...' and
#    'require <root> <image@sha256:digest>...', and, where a word was given
#    that is not empty, that word as given, a word of its own (check is also
#    in the script's name, which does not count); nothing of the shell's or
#    python's own words; cosign never called.
# One input: $1 names it, $2 is the word its line holds (empty: none is asked
# of it), the arguments after them go to the script as they are, the word
# ROOT standing for the root
no_mode() {
  local name=$1 word=$2 each rest alone form='<root> <image@sha256:digest>'; local -a args=() wrong=(); shift 2
  fresh
  for each in "$@"; do [ "$each" = ROOT ] && each="$SB/root"; args+=("$each"); done
  envelopes "$(all_five)" > "$SB/envelopes.jsonl"
  run ${args[@]+"${args[@]}"}
  exit_is "$name" 2 "a word that is no mode is wrong usage"
  no_stdout "$name"
  one_line "$SB/stderr" || wrong+=("stderr is not exactly one line, ended by its newline: lines on it: $(grep -c '' "$SB/stderr"), of them ended by a newline: $(wc -l < "$SB/stderr")")
  begun_error
  # verify's form counts where no three dots stand behind it: with them it
  # would be the form of a mode over several references
  rest=${err//"verify $form..."/}
  [[ "$rest" == *"verify $form"* ]] || wrong+=("it does not hold verify's form, 'verify $form' with no three dots behind it")
  for each in report require; do
    [[ "$err" == *"$each $form..."* ]] || wrong+=("it does not hold $each's form, '$each $form...'")
  done
  if [ -n "$word" ]; then
    # the word by itself: neither a letter, a digit nor a hyphen before it or
    # behind it, so that check is not found in check-provenance
    alone="(^|[^[:alnum:]-])${word}([^[:alnum:]-]|\$)"
    [[ "$err" =~ $alone ]] || wrong+=("it does not hold the word as given, '$word', as a word of its own")
  fi
  for each in "unbound variable" "command not found" "Traceback" "No such file"; do
    [[ "$err" != *"$each"* ]] || wrong+=("it holds '$each', the shell's or python's own words")
  done
  [ "${#wrong[@]}" -eq 0 ] && pass "$name: stderr is one line, the script's error line, which holds ${word:+the word '$word' and }all three usage forms, verify's, report's and require's, and nothing of the shell's or python's" \
    || fail "$name: stderr: one line and no more, begun '::error::check-provenance: ', that holds ${word:+the word '$word' and }all three usage forms and neither 'unbound variable' nor 'command not found' nor 'Traceback' nor 'No such file'" \
         "${wrong[@]}" "stderr:" "${err:-nothing}" "wanted: ::error::check-provenance: <a reason that holds ${word:+'$word', }'verify $form', 'report $form...' and 'require $form...'>"
  never_asked "$name" "a word that is no mode is refused before cosign is asked"
}
no_modes() {
  no_mode "the mode word is reprot, report mistyped" reprot reprot ROOT "$REF"
  no_mode "the mode word is check" check check ROOT "$REF"
  no_mode "the mode word is REPORT, report in capitals" REPORT REPORT ROOT "$REF"
  no_mode "the mode word is Require, require begun with a capital" Require Require ROOT "$REF"
  no_mode "the mode word is the empty string, the root and the reference after it" "" "" ROOT "$REF"
  no_mode "no argument at all, told the three forms" ""
}
no_modes

# 23: the five expected values are the ones the policy file declares (plan
#    slice 4.1.1, FR-2 as sharpened 2026-11-20). The script reads them from
#    verification.provenance.expectations of the root's policy file
#    (builder_identity, build_type, source_repository, workflow_path, ref) and
#    derives none of them from the releaser's identity; cosign is asked as
#    before, under verification.issuer and verification.roles.releaser.identity.
#    In every sandbox above the declared five are what the identity's parts
#    give, so those cases cannot tell a script that reads from one that
#    derives. Here the policy file declares five values that ALL differ from
#    what the identity and GitHub's build type give, and none of which is a
#    part of the declared builder identity either; the releaser's identity is
#    the suite's first, which can be cut into its parts. The five keys stand
#    in another order than in this repository's file, the predicate type after
#    them, and a mapping provenance at the file's top, outside verification,
#    holds the values the identity gives: only the keys' names under
#    verification.provenance.expectations find the declared ones.
#    Three inputs. verify over a statement that carries the declared five:
#    exit 0, stdout one line begun 'check-provenance: ' that names the
#    reference and each of the five declared values, nothing on stderr. verify
#    over a statement that carries the five the identity gives: exit 1, nothing
#    on stdout, stderr the one error line in its frame with a clause for each
#    of the five, '<name> is <found>, expected <the declared value>', and
#    ', expected ' five times. report over two references, the first answered
#    with the one statement and the second with the other: exit 0, stdout
#    'covered', a tab and the first, then 'uncovered', a tab, the second, a
#    tab and verify's line for it with the five clauses, nothing on stderr.
#    In each run every cosign call is the one of case 1, under the issuer and
#    the RELEASER's identity, never under the declared builder identity.
# a fresh sandbox whose policy file declares the five values given, in the
# order of their names: builder identity, build type, source repository,
# workflow path, ref
declaring() {
  fresh
  cat > "$SB/root/catalogue-policy.yaml" <<EOF
provenance:
  predicate_type: https://slsa.dev/provenance/v1
  expectations:
    builder_identity: $RELEASER
    build_type: $BUILD_TYPE
    source_repository: $SOURCE
    workflow_path: $WORKFLOW
    ref: $GIT_REF
verification:
  issuer: $ISSUER
  provenance:
    expectations:
      ref: $5
      workflow_path: $4
      source_repository: $3
      build_type: $2
      builder_identity: $1
    predicate_type: https://slsa.dev/provenance/v1
  roles:
    re-attester:
      identity: $RE_ATTESTER
      attests: [spdxjson, cyclonedx, vuln, openvex]
    releaser:
      identity: $RELEASER
      attests: [spdxjson, cyclonedx, vuln, openvex]
EOF
}
# what a text ($1: the error line, or a line of stdout) lacks of the five
# clauses ($2...), added to the caller's list wrong: each clause once, and
# ', expected ' five times
five_clauses() {
  local text=$1 each n; shift
  for each in "$@"; do
    n=$(printf '%s' "$text" | occurs "$each")
    [ "$n" -eq 1 ] || wrong+=("the clause '$each' stands in it $n times, wanted once")
  done
  n=$(printf '%s' "$text" | occurs ", expected ")
  [ "$n" -eq 5 ] || wrong+=("', expected ' stands in it $n times, wanted 5, a clause for each of the five and no other")
}
# the cosign calls of the run, $2 of them, the n-th about the n-th reference
# after them, each as case 1 wants it
asked_as_ever() {
  local name=$1 total=$2 calls got want nth=0 each; local -a wrong=(); shift 2
  calls=$(grep -c '' "$SB/cosign.log")
  [ "$calls" -eq "$total" ] || wrong+=("calls logged: $calls, wanted $total")
  for each in "$@"; do
    nth=$((nth + 1)); got=$(sed -n "${nth}p" "$SB/cosign.log" | asked)
    want=$(echo verify-attestation; printf '%s\n' "--type slsaprovenance1" "--certificate-oidc-issuer $ISSUER" "--certificate-identity $RELEASER" "$each" | LC_ALL=C sort)
    [ "$got" = "$want" ] || wrong+=("call $nth, wanted about $each under the releaser's identity, as the stub logged it: $(sed -n "${nth}p" "$SB/cosign.log" | grep '' || echo "there is no such call")")
  done
  [ "${#wrong[@]}" -eq 0 ] && pass "$name: cosign is called $total time(s), each under the policy file's issuer and the releaser's identity, with not one argument more" \
    || fail "$name: the cosign calls the stub logged: $total, each verify-attestation with --type slsaprovenance1, verification.issuer, verification.roles.releaser.identity (not the declared builder identity) and its one reference" \
         "${wrong[@]}" "the log:" "$([ -s "$SB/cosign.log" ] && cat "$SB/cosign.log" || echo "cosign was never called")"
}
declared_values() {
  local builder="https://builders.example.test/forge/v2" type="https://buildtypes.example.test/forge/v1"
  local source="https://git.example.test/smiths/anvil" workflow="ci/build.yaml" ref="refs/tags/v2.0.0"
  local second="registry.example.test/tools/sprocket@sha256:e951d951d900000bf3f37bf37bf37ba2adc7bf32d951d444fa2a2a2a22adf518"
  local over="the policy file declares five values that all differ from what the releaser identity gives"
  local name each lines ended as_declared as_derived first_line second_line
  local -a values=("$builder" "$type" "$source" "$workflow" "$ref") clauses=() wrong=()
  clauses=(
    "builder identity is \"$RELEASER\", expected \"$builder\""
    "build type is \"$BUILD_TYPE\", expected \"$type\""
    "source repository is \"$SOURCE\", expected \"$source\""
    "workflow path is \"$WORKFLOW\", expected \"$workflow\""
    "ref is \"$GIT_REF\", expected \"$ref\""
  )
  as_declared=$(statement "${values[@]}"); as_derived=$(all_five)

  name="$over, verify over a statement that carries the declared five"
  declaring "${values[@]}"
  envelopes "$as_declared" > "$SB/envelopes.jsonl"
  run verify "$SB/root" "$REF"
  exit_is "$name" 0 "the statement meets the five declared values, and none of the five is derived from the identity"
  lines=$(grep -c '' "$SB/stdout"); ended=$(wc -l < "$SB/stdout")
  [ "$lines" -eq 1 ] && [ "$ended" -eq 1 ] || wrong+=("lines on stdout: $lines, of them ended by a newline: $ended, wanted 1 and 1")
  [[ "$out" == "check-provenance: "* ]] || wrong+=("it is not begun 'check-provenance: '")
  for each in "$REF" "${values[@]}"; do
    [[ "$out" == *"$each"* ]] || wrong+=("it does not hold '$each'")
  done
  [ "${#wrong[@]}" -eq 0 ] && pass "$name: stdout is one line, begun 'check-provenance: ', naming the reference and each of the five declared values" \
    || fail "$name: stdout: one line, begun 'check-provenance: ', that names the reference in full and each of the five declared values" \
         "${wrong[@]}" "stdout:" "${out:-nothing}" "wanted: one line begun 'check-provenance: ' that carries $REF and ${values[*]}"
  [ ! -s "$SB/stderr" ] && pass "$name: nothing on stderr" \
    || fail "$name: stderr: nothing" "stderr:" "$(cat "$SB/stderr")" "wanted: nothing"
  asked_as_ever "$name" 1 "$REF"

  name="$over, verify over a statement that carries the five the identity gives"
  wrong=()
  declaring "${values[@]}"
  envelopes "$as_derived" > "$SB/envelopes.jsonl"
  run verify "$SB/root" "$REF"
  exit_is "$name" 1 "the statement meets none of the five declared values: what the identity's parts give is not what is expected"
  no_stdout "$name"
  one_line "$SB/stderr" || wrong+=("stderr is not exactly one line, ended by its newline: lines on it: $(grep -c '' "$SB/stderr"), of them ended by a newline: $(wc -l < "$SB/stderr")")
  in_frame; no_other_failure
  five_clauses "$err" "${clauses[@]}"
  [ "${#wrong[@]}" -eq 0 ] && pass "$name: stderr is one line, the error line in its frame, with a clause for each of the five, the value found and the DECLARED value expected" \
    || fail "$name: stderr: one line and no more, '::error::check-provenance: ', the reference, a reason and ' (Req 2.28)', the reason holding for each of the five the clause '<name> is <found>, expected <the declared value>' once and ', expected ' five times" \
         "${wrong[@]}" "stderr:" "${err:-nothing}" "wanted: ::error::check-provenance: $REF: <words>$(printf '; %s' "${clauses[@]}") (Req 2.28), the words between the clauses free"
  asked_as_ever "$name" 1 "$REF"

  name="$over, report over a reference with the declared five and one with the five the identity gives"
  wrong=()
  declaring "${values[@]}"
  envelopes "$as_declared" > "$SB/envelopes.jsonl.1"; envelopes "$as_derived" > "$SB/envelopes.jsonl.2"
  # what no call may get: both calls of this run are answered above
  : > "$SB/envelopes.jsonl"
  run report "$SB/root" "$REF" "$second"
  exit_is "$name" 0 "every reference was asked, and a reference that is not covered does not fail report (Req 2.29)"
  lines=$(grep -c '' "$SB/stdout"); ended=$(wc -l < "$SB/stdout")
  first_line=$(sed -n 1p "$SB/stdout"); second_line=$(sed -n 2p "$SB/stdout")
  [ "$lines" -eq 2 ] && [ "$ended" -eq 2 ] || wrong+=("lines on stdout: $lines, of them ended by a newline: $ended, wanted 2 and 2")
  [ "$first_line" = "covered"$'\t'"$REF" ] || wrong+=("the first line is not 'covered', one tab and the first reference: the statement with the declared five covers it")
  [[ "$second_line" == "uncovered"$'\t'"$second"$'\t'"check-provenance: $second: "*" (Req 2.28)" ]] \
    || wrong+=("the second line is not 'uncovered', one tab, the second reference, one tab and verify's line for it, begun 'check-provenance: ' and the reference and ended ' (Req 2.28)'")
  five_clauses "$second_line" "${clauses[@]}"
  [ "${#wrong[@]}" -eq 0 ] && pass "$name: stdout is 'covered' for the first and 'uncovered' for the second, with the clause of each of the five against its declared value" \
    || fail "$name: stdout: two lines, 'covered', a tab and the first reference, then 'uncovered', a tab, the second reference, a tab and the line verify ends on for it without '::error::', which holds for each of the five the clause '<name> is <found>, expected <the declared value>' once" \
         "${wrong[@]}" "stdout (as cat -A shows it: a tab reads ^I, a line's end \$):" "$(cat -A "$SB/stdout" 2>/dev/null | grep '' || echo nothing)" \
         "wanted, the same way:" "covered^I$REF\$" "uncovered^I$second^Icheck-provenance: $second: <words>$(printf '; %s' "${clauses[@]}") (Req 2.28)\$"
  [ ! -s "$SB/stderr" ] && pass "$name: nothing on stderr" \
    || fail "$name: stderr: nothing, report writes no '::error::' line and no attempt failed" "stderr:" "$(cat "$SB/stderr")" "wanted: nothing"
  asked_as_ever "$name" 2 "$REF" "$second"
}
declared_values

# 24: a declaration that cannot serve is refused by name (plan slice 4.1.2,
#    FR-2's third clause of 2026-11-20). The five expected values and the
#    predicate type stand under verification.provenance of the root's policy
#    file, each a string that is not empty, and the type the one this script
#    asks cosign for: it asks for slsaprovenance1 and nothing else, so a
#    policy file that declares another type describes a check the script does
#    not make. A declaration that is absent, lacks one of the six, holds one
#    as anything but a string that is not empty, or declares another type
#    cannot serve: the check is not made, and whoever broke the file is told
#    which key, as for the issuer and the identity in case 10, not shown a
#    python trace and not a statement blamed for the file's fault.
#    Every input is the policy file as fresh writes it with the one fault,
#    over a sandbox in which every cosign call would be answered with a
#    statement that meets all five, so that a script that asks anyway gets an
#    answer that passes. 41 inputs under verify: the section
#    verification.provenance absent, expectations absent under it, provenance
#    a string, expectations a list (each of the five behind a dash); each of
#    the five expectations in turn absent, null, the empty string, a number, a
#    list, a mapping; the predicate type absent, null, the empty string, a
#    number, and three strings that are not the type: provenance v0.2, one
#    that begins with the right text (v1.1), and cosign's own word for the
#    type, slsaprovenance1. Eight of them again over three references, four
#    under report and four under require, one of each family in each mode (the
#    section, an expectation, the type as no string, the type as another
#    string): the modes share the reading, so a sample across them shows that
#    the refusal comes before the modes part, and all 41 under each would show
#    no more.
#    Wanted of each: exit 2; nothing on stdout; stderr exactly one line, begun
#    '::error::check-provenance: ', that names the file catalogue-policy.yaml
#    and the key by its dotted path, and holds nothing of python's or the
#    shell's own words; cosign never called. For an expectation or the type
#    the key named is that one and none of the other five. For the section
#    absent or of the wrong shape it is a key under it, which one is left
#    free. For a type that is another string the line holds the value found
#    as well and, beside it, the value the script checks for.
# stdin, with the line begun $1 taken out and $2 put in its place (empty:
# nothing in its place, the key is absent)
with_line() {
  local line
  while IFS= read -r line; do
    if [[ "$line" != "$1"* ]]; then printf '%s\n' "$line"
    elif [ -n "$2" ]; then printf '%s\n' "$2"
    fi
  done
}
# the policy file as fresh writes it
declaring_all() { policy_with "  issuer: $ISSUER" "      identity: $RELEASER"; }
# the same with the one fault: the expectation whose key ends in $1 and whose
# declared value is $2, held as $3 (absent, null, empty, number, list, mapping)
faulty_expectation() {
  local at="      $1:" line=""
  case $3 in
    null)    line="$at ~" ;;
    empty)   line="$at \"\"" ;;
    number)  line="$at 7" ;;
    list)    line="$at"$'\n'"        - \"$2\"" ;;
    mapping) line="$at"$'\n'"        value: \"$2\"" ;;
  esac
  declaring_all | with_line "$at" "$line"
}
# the same with $1 for what stands after the predicate type's key (the word
# absent: the key is not there)
faulty_type() {
  local at="    predicate_type:" line=""
  [ "$1" = absent ] || line="$at $1"
  declaring_all | with_line "$at" "$line"
}
# the six keys of the declaration by their dotted paths, the five expectations
# in the order of their names and then the type, and the type the script
# asks cosign for, as a policy file has to declare it
DECLARED_KEYS=(
  verification.provenance.expectations.builder_identity
  verification.provenance.expectations.build_type
  verification.provenance.expectations.source_repository
  verification.provenance.expectations.workflow_path
  verification.provenance.expectations.ref
  verification.provenance.predicate_type
)
CHECKED_TYPE="https://slsa.dev/provenance/v1"
# One input: $1 is the mode word, $2 names the fault, $3 is the policy file's
# text; the arguments after them are the keys of which the line names one or
# more. With one key given the line names none of the other five. Under
# verify the script is asked about the suite's reference, under report and
# require about three. Where the caller names in FOUND the value the file
# holds as its type, the line holds that value and, with every copy of it
# taken out, still the type the script checks for
declaration_refused() {
  local mode=$1 name="$1, $2" policy=$3 key named=no each rest; local -a wrong=() refs=("$REF"); shift 3
  [ "$mode" = verify ] || refs=(
    "registry.example.test/tools/sprocket@sha256:7c1e9a3b5d2f4a6c8e0b1d3f5a7c9e2b4d6f8a0c1e3b5d7f9a2c4e6b8d0f1a3c"
    "$REF"
    "ghcr.io/acme/anvil@sha256:e4a1c8f2b6d09e3a7c5b1f8d2e6a4c0b9f7d3e1a5c8b2f6d0e4a9c7b3f1d5e8a"
  )
  fresh
  printf '%s\n' "$policy" > "$SB/root/catalogue-policy.yaml"
  envelopes "$(all_five)" > "$SB/envelopes.jsonl"
  run "$mode" "$SB/root" "${refs[@]}"
  exit_is "$name" 2 "a declaration that cannot serve is the policy file's fault, the check is not made"
  [ ! -s "$SB/stdout" ] && pass "$name: nothing on stdout" \
    || fail "$name: stdout: nothing, no line says that a digest passed or is covered" \
         "stdout (as cat -A shows it: a tab reads ^I, a line's end \$):" "$(cat -A "$SB/stdout" 2>/dev/null | grep '' || echo nothing)" "wanted: nothing"
  one_line "$SB/stderr" || wrong+=("stderr is not exactly one line, ended by its newline: lines on it: $(grep -c '' "$SB/stderr"), of them ended by a newline: $(wc -l < "$SB/stderr")")
  begun_error
  [[ "$err" == *"catalogue-policy.yaml"* ]] || wrong+=("it does not name the file catalogue-policy.yaml")
  for key in "$@"; do [[ "$err" == *"$key"* ]] && named=yes; done
  [ "$named" = yes ] || wrong+=("it names no key by its dotted path, wanted: $(printf '%s' "$*" | sed 's/ / or /g')")
  if [ $# -eq 1 ]; then
    for each in "${DECLARED_KEYS[@]}"; do
      [ "$each" = "$1" ] || [[ "$err" != *"$each"* ]] || wrong+=("it names $each, a key that is not at fault")
    done
  fi
  if [ -n "${FOUND:-}" ]; then
    [[ "$err" == *"$FOUND"* ]] || wrong+=("it does not hold '$FOUND', the value found at the key")
    rest=${err//"$FOUND"/}
    [[ "$rest" == *"$CHECKED_TYPE"* ]] || wrong+=("it does not hold '$CHECKED_TYPE' beside the value found, the type the script checks for")
  fi
  for each in "Traceback" 'File "' "AttributeError" "TypeError" "KeyError" "unbound variable" "command not found"; do
    [[ "$err" != *"$each"* ]] || wrong+=("it holds '$each', python's or the shell's own words")
  done
  [ "${#wrong[@]}" -eq 0 ] && pass "$name: stderr is one line, the script's error line, which names catalogue-policy.yaml and the key${FOUND:+, the value found and the type the script checks for} and holds nothing of python's or the shell's" \
    || fail "$name: stderr: one line and no more, begun '::error::check-provenance: ', that names catalogue-policy.yaml and the key by its dotted path${FOUND:+, holds the value found and the type the script checks for} and nothing of python's or the shell's own words" \
         "${wrong[@]}" "stderr:" "${err:-nothing}" "wanted: ::error::check-provenance: <a reason that names catalogue-policy.yaml and $(printf '%s' "$*" | sed 's/ / or /g')${FOUND:+, and holds $FOUND and $CHECKED_TYPE}>"
  never_asked "$name" "a declaration that cannot serve ends the run before cosign is asked about any reference"
}
declaration_faults() {
  local kp=verification.provenance ke=verification.provenance.expectations kt=verification.provenance.predicate_type
  local n kind what text other
  local -a five=("${DECLARED_KEYS[@]:0:5}") goods=("$RELEASER" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$GIT_REF")
  local -a kinds=(absent null empty number list mapping)
  local -a words=("absent" "null, written ~" "the empty string, written \"\"" "a number" "a list" "a mapping")
  local -a sections=() shapes=()
  # the section and its shape: from the key provenance, or from expectations,
  # down to the last of the five, which fresh writes last
  sections=("$kp is absent" "$ke is absent" "$kp is a string" "$ke is a list, each of the five behind a dash")
  shapes=(
    "$(declaring_all | sed '/^  provenance:/,/^      ref:/d')"
    "$(declaring_all | sed '/^    expectations:/,/^      ref:/d')"
    "$(declaring_all | sed -e '/^    predicate_type:/,/^      ref:/d' -e 's/^  provenance:$/  provenance: a string/')"
    "$(declaring_all | sed '/^    expectations:/,/^      ref:/s/^      \([a-z_]*: \)/      - \1/')"
  )
  declaration_refused verify "${sections[0]}" "${shapes[0]}" "${DECLARED_KEYS[@]}"
  declaration_refused verify "${sections[1]}" "${shapes[1]}" "${five[@]}"
  declaration_refused verify "${sections[2]}" "${shapes[2]}" "${DECLARED_KEYS[@]}"
  declaration_refused verify "${sections[3]}" "${shapes[3]}" "${five[@]}"
  for n in 0 1 2 3 4; do
    for kind in 0 1 2 3 4 5; do
      declaration_refused verify "${five[n]} is ${words[kind]}" "$(faulty_expectation "${five[n]##*.}" "${goods[n]}" "${kinds[kind]}")" "${five[n]}"
    done
  done
  declaration_refused verify "$kt is absent" "$(faulty_type absent)" "$kt"
  declaration_refused verify "$kt is null, written ~" "$(faulty_type "~")" "$kt"
  declaration_refused verify "$kt is the empty string, written \"\"" "$(faulty_type '""')" "$kt"
  declaration_refused verify "$kt is a number" "$(faulty_type 1)" "$kt"
  for other in "https://slsa.dev/provenance/v0.2" "${CHECKED_TYPE}.1" "slsaprovenance1"; do
    FOUND=$other declaration_refused verify "$kt is $other, another type than the script checks for" "$(faulty_type "$other")" "$kt"
  done
  # the sample across the other two modes, over three references
  declaration_refused report "${sections[0]}" "${shapes[0]}" "${DECLARED_KEYS[@]}"
  declaration_refused report "${five[1]} is ${words[2]}" "$(faulty_expectation build_type "$BUILD_TYPE" empty)" "${five[1]}"
  declaration_refused report "$kt is absent" "$(faulty_type absent)" "$kt"
  other="https://slsa.dev/provenance/v0.2"
  FOUND=$other declaration_refused report "$kt is $other, another type than the script checks for" "$(faulty_type "$other")" "$kt"
  declaration_refused require "${sections[3]}" "${shapes[3]}" "${five[@]}"
  declaration_refused require "${five[4]} is ${words[3]}" "$(faulty_expectation ref "$GIT_REF" number)" "${five[4]}"
  declaration_refused require "$kt is a number" "$(faulty_type 1)" "$kt"
  other="${CHECKED_TYPE}.1"
  FOUND=$other declaration_refused require "$kt is $other, another type than the script checks for" "$(faulty_type "$other")" "$kt"
}
declaration_faults

# every run of the script above, held to what it left behind and to the
# stub's note of its cosign calls (plan slice 2.5.3b, see run); a later case
# goes above this call
nothing_left_behind

if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all check-provenance tests passed"
