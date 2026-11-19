#!/usr/bin/env bash
# check-provenance.sh verify <root> <image@sha256:digest>
# check-provenance.sh report <root> <image@sha256:digest>...
# check-provenance.sh require <root> <image@sha256:digest>...
#
# Puts to cosign the question the release's self-check begins with: does the
# digest carry a SLSA provenance statement signed by the build workflow? The
# self-check asks each pushed digest, before the release applies any tag, the
# way a consumer would ask it, whether its provenance is one the catalogue's
# verification policy would admit (Req 2.28); cosign answers the signer's half
# of that (ADR 0005, decision 2): `cosign verify-attestation --type
# slsaprovenance1` under the issuer and the build workflow's identity. Both
# are read from <root>/catalogue-policy.yaml, the one committed home of the
# verification inputs (Req 7.7), from which that policy is rendered too:
# verification.issuer and verification.roles.releaser.identity. The role is
# taken by its name, releaser: its place among the roles means nothing, and
# its attests list names cosign's own attestation types, the provenance not
# among them. cosign gets exactly these arguments: no flag that weakens the
# check rides along.
#
# Whatever keeps the check from being made or makes it fail is told the one
# way: one ::error:: line on stderr, nothing on stdout, and an exit code, 2
# where the call, the policy file or the machine is at fault and cosign was
# never asked, 1 where cosign was asked and the check has failed. What follows
# tells each such end in the order the script comes to it, what its line names
# and why it is told so; each comes before anything told after it is read or
# asked.
#
# The script has three modes, verify, report and require: any other first
# word, or none, is wrong usage, the line holding the word as it was given and
# the usage form of each of the three, and exit 2, before anything is read or
# asked: whoever mistyped a mode reads in the one line which words there are
# and what stands after each. A caller who meant another thing is told so, and
# no check is run that he did not ask for by its name.
#
# verify asks about one reference, and all that follows tells its run. report
# takes the root and then the references, and asks of each, in the order
# given, the question verify asks of one: the same cosign call with the same
# arguments, the same reading of what cosign printed, the same five
# expectations. Of a reference that passes it prints one line on stdout,
# covered, one tab and the reference, in place of the line verify prints. A
# reference that fails the check, in any of the ways that end verify with 1,
# neither fails report nor stops it (Req 2.29: an absent attestation never
# fails the run): of such a one it prints uncovered, one tab, the reference,
# one tab and the reason, which is the line verify ends on for that reference
# without its leading ::error::, and the references after it are asked as
# well. These lines are all its stdout, one per reference in the order given;
# its stderr holds the ::warning:: lines of failed attempts as verify writes
# them, each reference's when its question is answered, and no ::error:: line
# for a reference that is not covered; with every reference asked it ends
# with 0. A report that cannot be made asks nothing: whatever ends verify with
# 2 ends report with 2 as well, with nothing on stdout and before cosign is
# asked about any reference, the good ones that stand before a bad one among
# them. The line is the one verify writes under the same fault, but for the
# count of the arguments, told next.
#
# require takes the root and then the references as report does, and asks of
# each, in the order given, the same question. Over references that all pass
# it does what report does over them: one line covered, one tab and the
# reference for each on stdout, in the order given and nothing else, nothing
# on stderr but the ::warning:: lines of failed attempts, and exit 0. A
# reference that fails the check fails require, but does not stop it: require
# is the mode for where a missing provenance has to stop the release. Of such
# a one it prints on stdout the line uncovered that report prints, and writes
# on stderr what verify writes of that reference, the ::warning:: lines of its
# failed attempts and behind them the one ::error:: line verify ends on, once,
# when that reference's question is answered and not at the run's end, so
# that the lines of one reference stand together and the references in the
# order given. The references after it are asked as well, and with the last
# one asked it ends with 1, however many were not covered. A require that
# cannot be made asks nothing, as with report: whatever ends verify with 2
# ends require with 2 as well, with nothing on stdout and before cosign is
# asked about any reference, the line the one verify writes under the same
# fault, but for the count of the arguments, told next.
#
# After the mode word verify come the root and the reference, the two and no
# more: any other number of arguments is wrong usage the same way, the line
# holding the usage form and the number given, and exit 2. A caller's slip
# must read as that, not as the shell's "unbound variable". After report come
# the root and one or more references: the root alone, or nothing, is wrong
# usage the same way, the line holding report's usage form and the number
# given, and exit 2. After require they come as after report, and the root
# alone, or nothing, is told the same way under require's name: the line holds
# require's usage form and the number given, and exit 2, where require over no
# reference would else end with 0 as if every digest were covered.
#
# The reference has to name the image by a sha256 digest: it ends in @sha256:
# and 64 lower-case hex characters, after a name that is not empty and holds
# no white space, one reference being one word: with two in the one argument
# the first would pass for part of the second's name. Nor does the name hold
# an @: the digest begins at the reference's one @, and with a second the name
# would end at one place for this test and at another for cosign. By a tag
# cosign would verify whatever the tag points at, which need not be the digest
# the release pushed, and a mistyped digest would cost three attempts. Any
# other reference is wrong usage: the line holds the reference as it was
# given, and exit 2. report's references are tested so as well, all of them in
# the order given and before any is asked: the first that names no image by a
# digest ends the run with that line, which holds it and none of the others.
# So are require's.
#
# The pause between two attempts, CHECK_PROVENANCE_RETRY_DELAY, is 10 seconds
# where the variable is not set or is empty; otherwise it has to be a whole
# number of seconds, digits alone. Anything else cannot be used: sleep would
# fail on it, the attempts would follow each other at once and nobody would be
# told. The line names the variable and holds the value as given, and exit 2,
# at the start, also in a run in which no attempt would fail.
#
# The root has to hold the policy file, catalogue-policy.yaml: a root without
# it is wrong usage as well, the line naming the file and no key of it, and
# exit 2, before anything is read from it. A file that is not there gives no
# key, and the caller is to look at the root he handed over, not into a policy
# file.
#
# A tool the check needs that is not on PATH, python3, jq or cosign, is told
# by that cause: the line names the tool and says that it is not found on
# PATH, and exit 2, before the file is read. Asked for all the same, the shell
# would print no value: without python3 the file would seem to lack a key,
# without jq what cosign verified would seem to hold no statement, and without
# cosign three attempts would seem to have failed.
#
# The issuer is read from the file first and the identity after it, each by a
# python3 call of its own, and what keeps either from being read is told the
# same way, by its cause. A python3 whose import of yaml fails reads no file
# at all: the line names python3 and its yaml module, and exit 2. The place to
# look is the machine the check runs on, not the policy file. A file that is
# there and cannot be opened, this user having no permission to read it, gives
# no key: the line names the file and says that it cannot be opened, and exit
# 2. The place to look is the file's mode and owner, not what stands in it. A
# file that is no YAML, or no UTF-8 text, gives no key at all, and is told by
# that cause, not by a key: the line names the file and says that it cannot be
# read as YAML, and exit 2. Whoever repairs the release is to look at the
# file's syntax, not for a key it seems to lack.
#
# The issuer and the identity each have to be there as a string that is not
# empty: an empty one handed to cosign is a question about nobody, and a
# mapping or a number printed as text one about an issuer or a signer of that
# name. A policy file that does not give one of them cannot serve, which is
# another thing than a statement that fails the check: the line names the file
# and the key, verification.issuer or verification.roles.releaser.identity,
# and exit 2. That holds as well where python cannot read the file down to the
# key (a string where a mapping belongs): it prints no value then, and its own
# words on stderr are kept back, the line being all there is.
#
# The identity has to hold an @ with something after it besides: the workflow
# path ends and the ref begins at its first @, and an identity without one, or
# with nothing after it, gives no ref. Before that first @ it has to read as
# the cuts take it, <scheme>://<host>/<owner>/<repo>/ and then the workflow
# path, which ends in no slash: with the @ right after the repository, or
# after its slash, there is no workflow path. Scheme, host, owner and
# repository are each a segment, not empty and holding no slash: where two
# slashes stand together a segment is empty, and the cuts would take the next
# for it. Cut all the same it would give nonsense, and the error line would
# blame the statement for the policy file's fault. Such a file cannot serve
# either: the line names the file and the key and holds the identity as it
# stands there, and exit 2.
#
# A mktemp that fails gives no directory to keep cosign's answer in, and is
# told by that cause: the line names mktemp and says that there is no
# directory for temporary files, and exit 2, before cosign is asked. Gone on
# all the same, cosign's answer would be written nowhere, and three attempts
# would seem to have failed.
#
# cosign's answer is read in three places: its exit code, its stderr when it
# fails, its stdout when it ends with 0. Any code but 0 is a failed attempt, a
# crash of cosign's as much as a refusal, and a failed attempt is tried again,
# up to three attempts: what makes cosign fail can go away by itself, a
# registry that does not answer for a moment. Asking again at once would
# mostly meet the same blip, so a failed attempt that another follows is
# answered by a pause, sleep called with the seconds of
# CHECK_PROVENANCE_RETRY_DELAY, and before the pause by one ::warning:: line
# on stderr naming the reference, the attempt and what cosign said in it: the
# line shows in the release's log that an attempt was lost, and why. After the
# third failure there is neither, the check has failed: the line names the
# reference, the three attempts and what cosign said the last time, and exit 1
# whatever code cosign ended with. What cosign said, in a warning as in the
# error line, is what it wrote on stderr in that attempt, word by word on the
# one line: of a refusal, which cosign prints twice (under "Error: " and then
# under "error during command execution: "), the first copy without its
# prefix; of anything else, a Go panic's trace for one, all of it.
#
# With 0 cosign has printed on stdout the attestations it verified, one
# envelope per line, the statement base64 in the envelope's payload. That
# stdout is read line by line for whether it holds a provenance statement: a
# line that is an envelope whose payload is a string that decodes from base64
# to a JSON object. Nothing else is one: not a line that is no envelope, not a
# payload that is null, that is not base64 or that decodes to anything but a
# JSON object. Every line is judged by itself: one that is no JSON counts for
# nothing and hides no statement on the lines before it or after it. With no
# statement the check has failed, though cosign ended with 0: a self-check
# that passes when nothing was verified has checked nothing. The line names
# the reference, and exit 1; cosign is not asked again, what it printed with 0
# is its answer and no failed attempt.
#
# With a statement the other half is asked, what the statement says: cosign
# has checked who signed it, not what it says of who built. The five
# expectations (ADR 0005, decision 5) are read one after another, each the
# same way: the value at one path of the statement has to be exactly the value
# expected, as the policy's rule compares for equality (Req 2.28). With
# another value there, one that only begins or ends like the expected one as
# much as any other, or with no value there, the statement misses the
# expectation, and the clause "<name> is <found>, expected <expected>" is kept
# for the error line. Both values stand in the clause as the JSON text jq
# prints on one line: a value found shows as it is, a line break in it as \n,
# and never breaks the line in two; null stands for no value there: no such
# field, or a path that cannot be walked, the builder a string where an object
# belongs for one.
#
# The five, by the names their clauses carry. The builder identity, at
# .predicate.runDetails.builder.id: the build workflow's identity, exactly the
# one cosign was asked under. The build type, at
# .predicate.buildDefinition.buildType: GitHub's build type for a workflow
# run, which says what the fields under externalParameters mean. The other
# three stand under .predicate.buildDefinition.externalParameters.workflow and
# are held against the parts of the identity, which reads
# https://github.com/<owner>/<repo>/<workflow path>@<ref>. The source
# repository, at .repository, says whose workflow file was run: the build
# workflow's repository, which is the identity's scheme, its host and the
# first two segments of its path, what stands before the third slash after the
# host. The workflow path, at .path, says which of the repository's workflow
# files was run: the build workflow's path, what stands in the identity
# between the slash after the repository and the first @ (a ref can hold an @,
# a workflow file's name does not in practice). The ref, at .ref, says from
# which branch or tag the workflow file was taken: the build workflow's ref,
# all that stands in the identity after the first @, the @ at which the
# workflow path ends.
#
# A miss does not end the run where it is found: met or missed, the next
# expectation is read, all five, since a release run is expensive and one
# failed check has to show all that is wrong with the statement, so that one
# fix and one more run are enough. With one or more missed the check has
# failed: the line names the reference and holds the clause of each
# expectation missed, each once, and nothing of an expectation the statement
# meets, and exit 1; cosign is not asked again. With the five met the script
# ends with 0 and one line on stdout that names the reference and says so.
#
# Several statements are judged one by one, in the order cosign printed them,
# each by itself as told above. The first that meets all five is the admitted
# one: the run ends with 0 there, the statements after it are not read, and
# nothing is said of what those before it miss. When none meets all five the
# check has failed, also when the five are met between two statements and by
# neither. What each statement misses is kept until all are read, and the one
# error line then says it per statement: each one's clauses together behind
# "statement <i>: ", <i> its place in cosign's order, counted from 1. A lone
# statement has no other to be told from, and its line carries no such text.
#
# Nothing cosign writes is passed on as it is. The statements, and of each
# expectation read the value found and the value expected, are each what jq
# prints when asked, one call after another: one call for the statements and
# ten for each statement judged, whatever it misses, of each expectation the
# value found before the value expected: eleven in a run over one statement. A
# jq call that printed nothing gave no answer, however it came to that (a jq
# that was killed and a jq that ended on an error of its own are two ways it
# comes about), and with no answer the check has failed, whichever of the
# calls it is: exit 1, nothing on stdout, the line naming the reference, and
# neither cosign nor jq is asked again. After the first call nothing printed
# is no statement, and the line is that of no statement. After each later one,
# whose answer is never empty, the line holds no clause, not one kept before
# that call either, and says that jq gave no answer, and to which question: an
# empty text is no value, so it is never compared (two of them would be equal,
# and the check would pass unchecked), never shown as found or as expected,
# and nothing is put in its place. In such a run too that line is all the
# script's stderr holds: what jq itself writes on stderr is kept back at every
# call, whatever it is, and of a jq that was killed the shell writes no notice
# of its own, each call being made inside $( ).
set -uo pipefail
# every such end is one ::error:: line on stderr in the one frame, the
# script's name before the reason and the requirement's number after it, and
# the run ends there with the code given first. The reason's words are echo's
# words, one blank between two, so a reason handed over as several words comes
# out as one line, an array of no words adding no blank
refuse() {
  local code=$1
  shift
  echo "::error::check-provenance:" "$@" "(Req 2.28)" >&2
  exit "$code"
}
# the three modes there are; a word that is none of them is a call that meant
# another thing, and is told the three forms instead of being given a check.
# So is a call with no word at all: under set -u a bare $1 would end it in
# the shell's words
[ "${1-}" = verify ] || [ "${1-}" = report ] || [ "${1-}" = require ] \
  || refuse 2 "'${1-}' is no mode of this script, usage: check-provenance.sh verify <root> <image@sha256:digest>, check-provenance.sh report <root> <image@sha256:digest>... or check-provenance.sh require <root> <image@sha256:digest>..."
# the two after the mode word, counted before either is read: under set -u a
# missing one would end the run in the shell's words, and one too many would
# be dropped unseen, the caller's slip checked as if it were none. report
# takes its references after the root, however many, but one at the least: a
# report about nothing is a caller's slip too, and is told report's form.
# verify's count is verify's alone: require takes its references as report
# does, one at the least as well, and is told its own form, the line naming
# the mode that was called: require over nothing would end with 0, the code
# of a release whose every digest is covered
[ "$1" = verify ] || [ "$#" -ge 3 ] \
  || refuse 2 "$(($# - 1)) argument(s) after $1 where the root and one or more references belong, usage: check-provenance.sh $1 <root> <image@sha256:digest>..."
[ "$1" != verify ] || [ "$#" -eq 3 ] \
  || refuse 2 "$(($# - 1)) argument(s) after verify where two belong, usage: check-provenance.sh verify <root> <image@sha256:digest>"
# the root that holds catalogue-policy.yaml; the references cosign is asked
# about stand after it, verify's one and the several of report and require,
# and REF names each in turn, here to be tested and under those two in the
# loop at the end to be asked
ROOT="$2"
# only a digest pins what the release pushed: a tag can be moved, and cosign
# would verify whatever it points at. The hex digits are written out, a range
# like a-f taking in capitals under some locales. No white space in the name:
# a second reference behind a blank is no part of one image's name. No @ in it
# either: an image's name holds none, the digest begins at the one @, and
# cosign cannot read a reference with two. Every reference is tested, in the
# order given and before anything is asked about any: a report over the good
# ones that stand before a bad one would be half a report
for REF in "${@:3}"; do
  [[ "$REF" =~ ^[^[:space:]@]+@sha256:[0123456789abcdef]{64}$ ]] \
    || refuse 2 "'$REF' does not name an image by a sha256 digest, which reads <image>@sha256: and 64 lower-case hex characters"
done
# the pause between two attempts, 10 seconds unless the caller sets another.
# Seconds in digits alone, the digits written out as above: sleep fails on
# anything else, and the attempts would follow at once with nobody told. It is
# tested here, not where an attempt fails: most runs never get there, and a
# value that cannot be used would wait unseen for the run that does
PAUSE="${CHECK_PROVENANCE_RETRY_DELAY:-10}"
[[ "$PAUSE" =~ ^[0123456789]+$ ]] \
  || refuse 2 "CHECK_PROVENANCE_RETRY_DELAY is '$PAUSE', which is no pause between attempts, it has to be a whole number of seconds in digits alone, or not set or empty for 10 seconds"
# a root without the policy file is the caller's slip, told as that: read all
# the same, a file would seem to lack a key where it is the file that is
# missing
POLICY="$ROOT/catalogue-policy.yaml"
[ -f "$POLICY" ] \
  || refuse 2 "'$ROOT' holds no catalogue-policy.yaml, the root has to be the directory that holds it"

# before the file is read the tools have to be there: a shell that does not
# find one prints no value, which would read as a key the file lacks
# (python3), as nothing verified (jq) or as three failed attempts (cosign),
# and is the machine's fault and none of theirs
for tool in python3 jq cosign; do
  command -v "$tool" >/dev/null \
    || refuse 2 "$tool is not found on PATH, the check cannot be made without it, $tool has to be installed where the check runs"
done
# one string of the policy file, the one at the dotted key $2, put into the
# variable named $1; the issuer and the identity are both read by it, so that
# neither is read with less care than the other. Only a string is a value:
# anything else the key holds, python would print as text, and cosign would be
# asked under an issuer or about a signer nobody wrote. What python writes on
# stderr is kept back: where the file cannot be read down to the key, python
# ends on a trace and prints no value, and the last line below says which key
# is missing. A file that yaml cannot parse is another cause and has to be
# told from that: python ends with 3 there, a code of its own (a trace ends
# with 1), so the shell reads the cause from the exit code and never from the
# text, which is the file's value. A file that cannot be opened is a third
# cause, told the same way: python ends with 4 there. A python whose import of
# yaml fails is a fourth, and no fault of the file's: python ends with 5
# there. The file is handed to yaml as bytes: bytes that are no UTF-8 are then
# yaml's to refuse as well, whatever the locale would have made of them
policy_string() {
  local name=$1 value
  value=$(python3 -c 'import sys
try: import yaml
except ImportError: sys.exit(5)
try: v=yaml.safe_load(open(sys.argv[1],"rb")) or {}
except OSError: sys.exit(4)
except yaml.YAMLError: sys.exit(3)
for k in sys.argv[2].split("."): v=v.get(k,{})
print(v if isinstance(v,str) else "")' "$POLICY" "$2" 2>/dev/null)
  # no yaml to read with, no file to read or no YAML in it: the machine's
  # python, the file's mode or owner, or its syntax or its encoding, is at
  # fault, and the line says which instead of naming a key the file would seem
  # to lack
  case $? in
    5) refuse 2 "python3 cannot import its yaml module, so '$POLICY' is not read, the module has to be installed where the check runs" ;;
    4) refuse 2 "'$POLICY' cannot be opened, the file is there and this user has no permission to read it, so no key of it is read" ;;
    3) refuse 2 "'$POLICY' cannot be read as YAML, its syntax or its encoding is at fault and no key of it is read" ;;
  esac
  # no string at the key: the file cannot serve, and whoever broke it is told
  # which key
  [ -n "$value" ] \
    || refuse 2 "'$POLICY' gives no $2, which has to be a string that is not empty"
  printf -v "$name" %s "$value"
}
# without an issuer there is no question to put to cosign
policy_string ISSUER verification.issuer
# the role named releaser, whatever its place and whatever it attests: without
# its identity cosign would be asked about nobody, and no other role's
# identity stands in
policy_string IDENTITY verification.roles.releaser.identity
# the ref is what follows the identity's first @: an identity without one, or
# with nothing after it, has no ref. The workflow path ends at that @, and
# begins after the repository's slash, the one the first cut below looks for:
# without that slash before the @, or with it right before the @, there is no
# path. Scheme, host, owner and repository are counted as segments, each one
# or more characters that are no slash: a * would take an empty one, or two
# for one. What the cuts below made of any of these would be held against
# every statement, which is not at fault. The file cannot serve, as above
[[ "$IDENTITY" == *@?* \
  && "${IDENTITY%%@*}" == +([!/])://+([!/])/+([!/])/+([!/])/*[!/] ]] \
  || refuse 2 "'$POLICY' gives a verification.roles.releaser.identity that cannot be cut into its parts, '$IDENTITY' holds no scheme, host, owner, repository and workflow path before its first @ or no ref after it, the form is <scheme>://<host>/<owner>/<repo>/<workflow path>@<ref>"

# the build workflow's repository, cut from the identity in two steps: what
# follows scheme, host, owner and repository, and then the identity without it
# and without the slash before it
SOURCE=${IDENTITY#*://*/*/*/}
SOURCE=${IDENTITY%"/$SOURCE"}
# the build workflow's path: what follows the repository and its slash, up to
# the first @, where the ref begins (a ref can hold an @ of its own)
WORKFLOW=${IDENTITY#"$SOURCE/"}
WORKFLOW=${WORKFLOW%%@*}
# the build workflow's ref: all that follows that first @
WORKFLOW_REF=${IDENTITY#*@}
# the build type GitHub's provenance service writes for a workflow run (ADR
# 0005, decision 5)
BUILD_TYPE="https://actions.github.io/buildtypes/workflow/v1"

# the five expectations a statement is held against, a row of each list for
# each, in the order they are read. First the name the clause and the question
# carry. cosign has checked who signed the statement, not what it says of who
# built, and the policy's rule compares each of the five for equality (Req
# 2.28), so no value found is tidied before it is compared
EXPECTATIONS=(
  # the builder has to be the build workflow too, exactly the identity cosign
  # was asked under
  "builder identity"
  # which kind of build wrote the statement, and with it what the fields under
  # externalParameters mean
  "build type"
  # whose workflow file was run: a fork, or the URL with something after it,
  # is another repository
  "source repository"
  # which of the repository's workflow files was run: a repository holds
  # several, and the rule admits the build workflow alone
  "workflow path"
  # from which branch or tag the workflow file was taken: the rule admits the
  # release branch alone, so the same file run from another branch is a miss
  "ref"
)
# where in a statement the value of each stands
FIELDS=(
  .predicate.runDetails.builder.id
  .predicate.buildDefinition.buildType
  .predicate.buildDefinition.externalParameters.workflow.repository
  .predicate.buildDefinition.externalParameters.workflow.path
  .predicate.buildDefinition.externalParameters.workflow.ref
)
# the value expected of each, and the name jq is handed it under
VALUES=("$IDENTITY" "$BUILD_TYPE" "$SOURCE" "$WORKFLOW" "$WORKFLOW_REF")
ARGS=(identity type source workflow ref)
# a jq call that gave no answer: the check has failed, and there is no clause
# to show for it. One ::error:: line naming the reference and the question
# ($1), exit 1; neither cosign nor jq is asked again
unanswered() {
  refuse 1 "${REF}: the provenance statement cosign verified could not be judged: jq gave no answer when asked for $1"
}
# ONE statement ($1) judged against the five: it leaves in missed the clause
# of each expectation the statement misses, "; " between two, and leaves it
# empty for a statement that meets all five. Whoever needs a statement judged
# calls this, and nothing judges one in any other way. Of each expectation the
# value found is asked first and then the JSON text of the value expected, and
# the two are compared as the JSON text jq prints on one line: so nothing of
# the value found is lost on its way through the shell, and the error line
# shows it as it is without ever breaking in two. null is what jq prints where
# the statement has no such field, and what the try answers where the path
# cannot be walked because something on the way to the field is no object:
# there is no value at such a path either, and jq by itself would end on an
# error there and print nothing. Only the path is answered for: an empty text
# is no value and is not dressed as null by the shell. A call that printed
# nothing gave no answer, however it came to that (a jq that was killed and a
# jq that ended on an error of its own are two ways it comes about), and its
# empty text fails the check before any text is compared or shown: two empty
# texts would be equal, and the check would pass unchecked. Whether the text
# is empty is all that is asked, jq's exit code is not read here either: an
# answer is never empty, since the try gives a value or null for every
# statement and every value expected has its JSON text. Both calls stay inside
# $( ): there bash writes no notice of its own about a jq that was killed, as
# it does on the script's stderr for a plain command. What jq itself writes on
# stderr is kept back at both, as at the first call, whatever it is: with no
# answer the script's stderr holds the one line of unanswered and no more. A
# miss does not end the judging: its clause is kept and the next expectation
# is read, so that the one error line names all that the statement misses, and
# an expectation the statement meets leaves nothing for the line
judge_statement() {
  local i name arg found expected
  missed=""
  for i in "${!EXPECTATIONS[@]}"; do
    name=${EXPECTATIONS[i]}
    found=$(jq -c "try (${FIELDS[i]}) catch null" <<<"$1" 2>/dev/null)
    [ -n "$found" ] || unanswered "its $name"
    arg=${ARGS[i]}
    expected=$(jq -nc --arg "$arg" "${VALUES[i]}" "\$$arg" 2>/dev/null)
    [ -n "$expected" ] \
      || unanswered "the JSON text of the $name expected of it"
    [ "$found" = "$expected" ] \
      || missed="${missed:+$missed; }$name is $found, expected $expected"
  done
}

# where cosign's stdout is kept until it is read, gone on exit. Without it the
# check cannot be made: cosign's answer would have no place to go, and the
# fault would read as cosign's. mktemp's own words are kept back
TMP=$(mktemp -d 2>/dev/null) \
  || refuse 2 "mktemp gave no directory for temporary files, the check cannot be made without one, the place to look is TMPDIR and the machine's directory for temporary files"
trap 'rm -rf "$TMP"' EXIT

# the question itself, put about the one reference in REF: cosign asked, what
# it printed read for a statement, the statements judged against the five.
# Every mode asks it through here and in no other way. It comes back with one
# line on stdout, that of a reference that passed; every other end is refuse's
ask() {
  # cosign is asked up to three times, since what makes it fail can go away by
  # itself; any exit code but 0 is a failed attempt. Between two attempts lies
  # a pause, since asking again at once mostly meets the same blip
  for attempt in 1 2 3; do
    # stdin is the caller's: the script is called once per digest, and a tool
    # that read stdin would eat what a caller's loop still has to read from
    # it. What cosign writes ends here: its stderr is kept for the script's
    # own lines, its stdout goes to a file that every attempt begins anew, so
    # that what a failed attempt printed is never read (2>&1 stands first, so
    # the capture takes stderr alone)
    said=$(cosign verify-attestation --type slsaprovenance1 --certificate-oidc-issuer "$ISSUER" --certificate-identity "$IDENTITY" "$REF" </dev/null 2>&1 >"$TMP/stdout") && break
    # cosign prints a refusal twice, under "Error: " and then under "error
    # during command execution: ": the message is the first copy without its
    # prefix, so the second is cut off. What cosign wrote without such lines,
    # a Go panic's trace for one, is the message as a whole
    said=${said%%$'\n'"error during command execution: "*}
    # onto the one line word by word, so that no blank is doubled: a message's
    # lines after the first begin with a blank, and the last can end in one
    read -r -d '' -a words <<<"${said#Error: }"
    # another attempt follows: the warning shows in the release's log that
    # this one was lost, and why; then the pause, which reads no stdin either
    if [ "$attempt" -lt 3 ]; then
      echo "::warning::check-provenance: ${REF}: cosign failed on attempt ${attempt} of 3 and is asked again after ${PAUSE} seconds, it said:" "${words[@]}" >&2
      # shellcheck disable=SC2217  # every program gets no stdin, sleep too
      sleep "$PAUSE" </dev/null
      continue
    fi
    # 1 whatever code cosign ended with: the code says that the check failed,
    # not how cosign did
    refuse 1 "${REF}: cosign failed on each of 3 attempts, the last time with:" \
      "${words[@]}"
  done
  # cosign has ended with 0: the statements in what it printed, each decoded
  # from its envelope's payload, one per line. What jq prints is the answer,
  # its exit code is not: over no input, and a blank line is none, jq -e ends
  # with 0 on jq 1.6 and with 4 on jq 1.7.1. Every line is taken as text (-R)
  # and parsed inside the try, each by itself: read as a stream of JSON
  # values, jq would stop at the first line that is no JSON and never see the
  # envelopes after it. A payload is decoded only when it is a string (jq
  # decodes null as it would the word null), and a line that is no JSON, or a
  # payload that is not base64 or decodes to no JSON, is no statement and no
  # error, hence the try; nor is JSON that is no object a statement. What jq
  # writes on stderr is not passed on
  statements=$(jq -R -c 'try (fromjson | .payload | strings | @base64d | fromjson | objects) catch empty' "$TMP/stdout" 2>/dev/null)
  # nothing verified never passes, and cosign is not asked again: what it
  # printed with 0 is no failed attempt
  [ -n "$statements" ] \
    || refuse 1 "${REF}: cosign ended with exit code 0 and what it printed holds no provenance statement"
  # the statements are judged one by one, each by itself: the policy's rule
  # admits on any statement that meets the conditions, wherever it stands
  # among the others, and the self-check is neither stricter nor laxer than
  # the rule. They are read on a file descriptor of the loop's own: a jq
  # started inside inherits the loop's stdin, and one that read it would eat
  # the statements still to come. Each is counted, its number being its name
  # in the error line
  count=0
  misses=""
  while IFS= read -r statement <&3; do
    count=$((count + 1))
    judge_statement "$statement"
    # a statement that misses nothing is the admitted one: the others are not
    # read, and nothing is said of those read before it
    [ -n "$missed" ] || break
    # what this one misses is kept under its number: should none meet all
    # five, the line has to say of each statement what is wrong with it
    misses="${misses:+$misses; }statement ${count}: ${missed}"
  done 3<<<"$statements"
  # no statement met all five, the last one read neither, and the check has
  # failed; cosign is not asked again. One line: of a lone statement the
  # clause of each expectation it missed, of several the same for each under
  # its number
  if [ -n "$missed" ]; then
    [ "$count" -eq 1 ] \
      || refuse 1 "${REF}: none of the ${count} provenance statements cosign verified is one the catalogue's verification policy would admit: ${misses}"
    refuse 1 "${REF}: the provenance statement cosign verified is not one the catalogue's verification policy would admit: ${missed}"
  fi
  echo "check-provenance: ${REF}: cosign was asked for a SLSA provenance statement signed by ${IDENTITY} and ended with exit code 0, what it printed holds a provenance statement whose builder identity is that identity, whose build type is ${BUILD_TYPE}, whose source repository is ${SOURCE}, whose workflow path is ${WORKFLOW} and whose ref is ${WORKFLOW_REF}, what else the statement says is not read"
}

# report: each reference asked in the order given, the same question each
# time, and of one that passed the one line covered, a tab and the reference.
# The line the question itself prints of it is verify's and is dropped here.
# The question is put inside $( ): a refuse in there ends that shell alone,
# with the directory for temporary files left standing (the EXIT trap is this
# shell's), so a reference that is not covered does not end the run, and what
# the question wrote on stderr is held back until it is answered. Of a
# reference that failed the last line of that is the error line, which is
# told on stdout as the reason, without its ::error::, and never on stderr;
# the lines before it, and all of them for one that passed, are the warnings
# of failed attempts and go on to stderr as they are. require goes through
# the same loop and differs in two things: the error line of a reference that
# failed goes on to stderr as well, behind that reference's warnings, as
# verify writes it, and one such reference or more makes the exit code 1,
# which is decided after the last reference was asked
if [ "$1" != verify ]; then
  code=0
  for REF in "${@:3}"; do
    if told=$(ask 2>&1 >/dev/null); then
      [ -z "$told" ] || printf '%s\n' "$told" >&2
      printf 'covered\t%s\n' "$REF"
    else
      reason=${told##*$'\n'}
      if [ "$1" = require ]; then
        printf '%s\n' "$told" >&2
        code=1
      else
        printf '%s' "${told%"$reason"}" >&2
      fi
      printf 'uncovered\t%s\t%s\n' "$REF" "${reason#::error::}"
    fi
  done
  exit "$code"
fi
ask
