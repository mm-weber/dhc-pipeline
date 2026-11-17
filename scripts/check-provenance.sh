#!/usr/bin/env bash
# check-provenance.sh verify <root> <image@sha256:digest>
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
# The script has the one mode, verify: any other first word, or none, is wrong
# usage,
# one ::error:: line on stderr holding the usage form, and exit 2, before
# anything is read or asked. A caller who meant another thing is told so, and
# no check is run that he did not ask for by its name.
# After the mode word come the root and the reference, the two and no more:
# any other number of arguments is wrong usage the same way, one ::error::
# line on stderr holding the usage form and the number given, and exit 2. A
# caller's slip must read as that, not as the shell's "unbound variable".
# The reference has to name the image by a sha256 digest: it ends in @sha256:
# and 64 lower-case hex characters, after a name that is not empty and holds
# no white space, one reference being one word: with two in the one argument
# the first would pass for part of the second's name. Nor does the name hold
# an @: the digest begins at the reference's one @, and with a second the
# name would end at one place for this test and at another for cosign. By a tag
# cosign would verify whatever the tag points at, which need not be the digest
# the release pushed, and a mistyped digest would cost three attempts. Any
# other reference is wrong usage: one ::error:: line on stderr holding the
# reference as it was given, and exit 2, before the policy file is read and
# before cosign is asked.
# The root has to hold the policy file, catalogue-policy.yaml: a root without
# it is wrong usage as well, one ::error:: line on stderr naming the file and
# no key of it, and exit 2, before anything is read from it and before cosign
# is asked. A file that is not there gives no key, and the caller is to look
# at the root he handed over, not into a policy file.
# The issuer and the identity each have to be there as a string that is not
# empty: an empty one
# handed to cosign is a question about nobody, and a mapping or a number
# printed as text one about an issuer or a signer of that name. A policy file
# that does not give one of them cannot serve, which is another thing than a
# statement that fails the check: one ::error:: line on stderr naming the
# file and the key, verification.issuer or
# verification.roles.releaser.identity, and exit 2, before cosign is asked.
# That holds as well where python cannot read the file down to the key (a
# string where a mapping belongs): it prints no value then, and its own words
# on stderr are kept back, the line being all there is.
# A file that is no YAML, or no UTF-8 text, gives no key at all, and is told
# by that cause, not
# by a key: one ::error:: line on stderr naming the file and saying that it
# cannot be read as YAML, and exit 2, before cosign is asked. Whoever repairs
# the release is to look at the file's syntax, not for a key it seems to lack.
# A file that is there and cannot be opened, this user having no permission
# to read it, gives no key either and is told by that cause the same way: one
# ::error:: line on stderr naming the file and saying that it cannot be
# opened, and exit 2, before cosign is asked. The place to look is the file's
# mode and owner, not what stands in it.
# A python3 whose import of yaml fails reads no file at all and is told by
# that cause as well: one ::error:: line on stderr naming python3 and its
# yaml module, and exit 2, before cosign is asked. The place to look is the
# machine the check runs on, not the policy file.
# A tool the check needs that is not on PATH, python3, jq or cosign, is told
# by that cause: one ::error:: line on stderr naming the tool and saying
# that it is not found on PATH, and exit 2, before the file is read and
# before cosign is asked. Asked for all the same, the shell would print no
# value: without python3 the file would seem to lack a key, without jq what
# cosign verified would seem to hold no statement, and without cosign three
# attempts would seem to have failed.
# A mktemp that fails gives no directory to keep cosign's answer in, and is
# told by that cause: one ::error:: line on stderr naming mktemp and saying
# that there is no directory for temporary files, and exit 2, before cosign
# is asked. Gone on all the same, cosign's answer would be written nowhere,
# and three attempts would seem to have failed.
# The identity has to hold an @ with something after it besides: the workflow
# path ends and the ref begins at its first @, and an identity without one,
# or with nothing after it, gives no ref. Before that first @ it has to read
# as the cuts take it, <scheme>://<host>/<owner>/<repo>/ and then the workflow
# path, which ends in no slash: with the @ right after the repository, or
# after its slash, there is no workflow path. Scheme, host, owner and
# repository are each a segment, not empty and holding no slash: where two
# slashes stand together a segment is empty, and the cuts would take the next
# for it. Cut all the same it would give nonsense, and the error line would
# blame the statement for the policy file's fault. Such a file cannot serve
# either: one ::error:: line on stderr naming the file and the key and holding
# the identity as it stands there, and exit 2, before cosign is asked.
# The answer is read in three places: cosign's exit code, its stderr when it
# fails, its stdout when it ends with 0. Any code but 0 is a failed attempt,
# a crash of cosign's as much as a refusal, and a failed attempt is tried
# again, up to three attempts: what makes cosign fail can go away by itself,
# a registry that does not answer for a moment. Asking again at once would
# mostly meet the same blip, so a failed attempt that another follows is
# answered by a pause, sleep called with the seconds held in
# CHECK_PROVENANCE_RETRY_DELAY, 10 where it is not set, and before the pause
# by one ::warning:: line on stderr naming the reference, the attempt and
# what cosign said in it: the line shows in the release's log that an attempt
# was lost, and why. After the third failure there is neither, the
# check has failed: one ::error:: line on stderr naming the reference, the
# three attempts and what cosign said the last time, and exit 1 whatever code
# cosign ended with. What cosign said, in a warning as in the error line, is
# what it wrote on stderr in that attempt, word by word on the one line:
# of a refusal, which cosign prints
# twice (under "Error: " and then under "error during command execution: "),
# the first copy without its prefix; of anything else, a Go panic's trace for
# one, all of it.
# With 0 cosign has printed on stdout the attestations it verified, one
# envelope per line, the statement base64 in the envelope's payload. That
# stdout is read line by line for whether it holds a provenance statement: a
# line that is an envelope whose payload is a string that decodes from base64
# to a JSON object. Nothing else is one: not a line that is no envelope, not a
# payload that is null, that is not base64 or that decodes to anything but a
# JSON object. Every line is judged by itself: one that is no JSON counts for
# nothing and hides no statement on the lines before it or after it. With no
# statement the check has failed, though cosign ended with 0: a self-check
# that passes when nothing was verified has checked nothing. One ::error::
# line on stderr naming the reference, and exit 1; cosign is not asked again,
# what it printed with 0 is its answer and no failed attempt.
# With a statement the other half is asked, what the statement says: cosign
# has checked who signed it, not what it says of who built. The five
# expectations (ADR 0005, decision 5) are read one after another. First the
# builder identity: the value at .predicate.runDetails.builder.id has to be
# the build workflow's identity, exactly the one cosign was asked under, as
# the policy's rule compares for equality (Req 2.28). With another value
# there, one that only begins or ends like that identity as much as any
# other, or with no value there, the statement misses the expectation, and
# the clause "builder identity is <found>, expected <expected>" is kept for
# the error line. Both values stand in the
# clause as the JSON text jq prints on one line: a value found shows as it is,
# a line break in it as \n, and never breaks the line in two; null stands for
# no value there: no such field, or a path that cannot be walked, the builder
# a string where an object belongs for one. Met or missed, the build type is
# read next, the same way: the value at
# .predicate.buildDefinition.buildType has to be exactly GitHub's build type
# for a workflow run, which says what the fields under externalParameters
# mean. Anything else there is a miss as with the builder identity, the
# clause being "build type is <found>, expected <expected>".
# Then the source repository is read the same way, which says
# whose workflow file was run: the value at
# .predicate.buildDefinition.externalParameters.workflow.repository has to be
# exactly the build workflow's repository, the clause being "source
# repository is <found>, expected <expected>". That repository is cut from
# the identity, which reads https://github.com/<owner>/<repo>/<workflow
# path>@<ref>: its scheme, its host and the first two segments of its path,
# what stands before the third slash after the host.
# Then the workflow path is read the same way, which says
# which of the repository's workflow files was run: the value at
# .predicate.buildDefinition.externalParameters.workflow.path has to be
# exactly the build workflow's path, the clause being "workflow path is
# <found>, expected <expected>". That path is cut from the identity too: what
# stands between the slash after the repository and the first @ (a ref can
# hold an @, a workflow file's name does not in practice).
# Then the ref is read the same way, which says from which branch
# or tag the workflow file was taken: the value at
# .predicate.buildDefinition.externalParameters.workflow.ref has to be
# exactly the build workflow's ref, the clause being "ref is <found>,
# expected <expected>". That ref is cut from the identity too: all that
# stands after the first @, the @ at which the workflow path ends.
# A miss does not end the run where it is found: all five are read, since a
# release run is expensive and one failed check has to show all that is wrong
# with the statement, so that one fix and one more run are enough. With one
# or more missed the check has failed: one ::error:: line on stderr naming
# the reference and holding the clause of each expectation missed, each once,
# and nothing of an expectation the statement meets, and exit 1; cosign is
# not asked again.
# With the five met the script ends with 0 and one line on stdout that names
# the reference and says so.
# Several statements are judged one by one, in the order cosign printed them,
# each by itself as told above. The first that meets all five is the admitted
# one: the run ends with 0 there, the statements after it are not read, and
# nothing is said of what those before it miss. When none meets all five the
# check has failed, also when the five are met between two statements and by
# neither. What each statement misses is kept until all are read, and the one
# error line then says it per statement: each one's clauses together behind
# "statement <i>: ", <i> its place in cosign's order, counted from 1. A lone
# statement has no other to be told from, and its line carries no such text.
# Nothing cosign writes is passed on as it is.
# The statements, and of each expectation read the value found and the value
# expected, are each what jq prints when asked, one call after another:
# one call for the statements and ten for each statement judged, whatever it
# misses: eleven in a run over one statement.
# A jq call that
# printed nothing gave no answer, however it came to that (a jq that was
# killed and a jq that ended on an error of its own are two ways it comes
# about), and with no answer the check has failed, whichever of the calls it
# is: exit 1, nothing on stdout, one ::error:: line on stderr naming
# the reference, and neither cosign nor jq is asked again. After the first
# call nothing printed is no statement, and the line is that of no statement.
# After each later one, whose answer is never empty, the line holds
# no clause, not one kept before that call either, and says that jq gave no
# answer, and to which question: an empty
# text is no value, so it is never compared (two of them would be equal, and
# the check would pass unchecked), never shown as found or as expected, and
# nothing is put in its place. In such a run too that line is all the
# script's stderr holds: what jq itself writes on stderr is kept back at
# every call, whatever it is, and of a jq that was killed the shell
# writes no notice of its own, each call being made inside $( ).
set -uo pipefail
# the one mode there is; a word that is not it is a call that meant another
# thing, and is told the form instead of being given this check. So is a call
# with no word at all: under set -u a bare $1 would end it in the shell's words
[ "${1-}" = verify ] || { echo "::error::check-provenance: '${1-}' is no mode of this script, usage: check-provenance.sh verify <root> <image@sha256:digest> (Req 2.28)" >&2; exit 2; }
# the two after the mode word, counted before either is read: under set -u a
# missing one would end the run in the shell's words, and one too many would
# be dropped unseen, the caller's slip checked as if it were none
[ "$#" -eq 3 ] || { echo "::error::check-provenance: $(($# - 1)) argument(s) after verify where two belong, usage: check-provenance.sh verify <root> <image@sha256:digest> (Req 2.28)" >&2; exit 2; }
# the root that holds catalogue-policy.yaml, and the reference cosign is
# asked about
ROOT="$2"
REF="$3"
# only a digest pins what the release pushed: a tag can be moved, and cosign
# would verify whatever it points at. The hex digits are written out, a range
# like a-f taking in capitals under some locales. No white space in the name:
# a second reference behind a blank is no part of one image's name. No @ in
# it either: an image's name holds none, the digest begins at the one @, and
# cosign cannot read a reference with two
[[ "$REF" =~ ^[^[:space:]@]+@sha256:[0123456789abcdef]{64}$ ]] || { echo "::error::check-provenance: '$REF' does not name an image by a sha256 digest, which reads <image>@sha256: and 64 lower-case hex characters (Req 2.28)" >&2; exit 2; }
# a root without the policy file is the caller's slip, told as that: read all
# the same, a file would seem to lack a key where it is the file that is
# missing
[ -f "$ROOT/catalogue-policy.yaml" ] || { echo "::error::check-provenance: '$ROOT' holds no catalogue-policy.yaml, the root has to be the directory that holds it (Req 2.28)" >&2; exit 2; }
# the build type GitHub's provenance service writes for a workflow run (ADR
# 0005, decision 5)
BUILD_TYPE="https://actions.github.io/buildtypes/workflow/v1"

# only a string is the issuer: anything else the key holds, python would
# print as text, and cosign would be asked under an issuer nobody wrote.
# What python writes on stderr is kept back: where the file cannot be read
# down to the key, python ends on a trace and prints no value, and the line
# below says what is missing. A file that yaml cannot parse is another cause
# and has to be told from that: python ends with 3 there, a code of its own
# (a trace ends with 1), so the shell reads the cause from the exit code and
# never from the text, which is the file's value. A file that cannot be
# opened is a third cause, told the same way: python ends with 4 there. A
# python whose import of yaml fails is a fourth, and no fault of the file's:
# python ends with 5 there. The
# file is handed to yaml as bytes: bytes that are no UTF-8 are then yaml's to
# refuse as well, whatever the locale would have made of them. Before all
# that the tools have to be there: a shell that does not find one prints no
# value either, which would read as a key the file lacks (python3), as
# nothing verified (jq) or as three failed attempts (cosign), and is the
# machine's fault and none of theirs
for tool in python3 jq cosign; do
  command -v "$tool" >/dev/null || { echo "::error::check-provenance: $tool is not found on PATH, the check cannot be made without it, $tool has to be installed where the check runs (Req 2.28)" >&2; exit 2; }
done
ISSUER=$(python3 -c 'import sys
try: import yaml
except ImportError: sys.exit(5)
try: d=yaml.safe_load(open(sys.argv[1],"rb"))
except OSError: sys.exit(4)
except yaml.YAMLError: sys.exit(3)
v=(d or {}).get("verification",{}).get("issuer"); print(v if isinstance(v,str) else "")' "$ROOT/catalogue-policy.yaml" 2>/dev/null)
# no yaml to read with, no file to read or no YAML in it, no key: the
# machine's python, the file's mode or owner, or its syntax or its encoding,
# is at fault, and the line says which instead of naming a key the file
# would seem to lack
case $? in
  5) echo "::error::check-provenance: python3 cannot import its yaml module, so '$ROOT/catalogue-policy.yaml' is not read, the module has to be installed where the check runs (Req 2.28)" >&2; exit 2 ;;
  4) echo "::error::check-provenance: '$ROOT/catalogue-policy.yaml' cannot be opened, the file is there and this user has no permission to read it, so no key of it is read (Req 2.28)" >&2; exit 2 ;;
  3) echo "::error::check-provenance: '$ROOT/catalogue-policy.yaml' cannot be read as YAML, its syntax or its encoding is at fault and no key of it is read (Req 2.28)" >&2; exit 2 ;;
esac
# without an issuer there is no question to put to cosign: the file cannot
# serve, and whoever broke it is told which key
[ -n "$ISSUER" ] || { echo "::error::check-provenance: '$ROOT/catalogue-policy.yaml' gives no verification.issuer, which has to be a string that is not empty (Req 2.28)" >&2; exit 2; }
# the role named releaser, whatever its place and whatever it attests; only a
# string is its identity, as with the issuer
IDENTITY=$(python3 -c 'import sys,yaml; v=(yaml.safe_load(open(sys.argv[1],"rb")) or {}).get("verification",{}).get("roles",{}).get("releaser",{}).get("identity"); print(v if isinstance(v,str) else "")' "$ROOT/catalogue-policy.yaml" 2>/dev/null)
# without an identity cosign would be asked about nobody: the file cannot
# serve here either, and no other role's identity stands in
[ -n "$IDENTITY" ] || { echo "::error::check-provenance: '$ROOT/catalogue-policy.yaml' gives no verification.roles.releaser.identity, which has to be a string that is not empty (Req 2.28)" >&2; exit 2; }
# the ref is what follows the identity's first @: an identity without one,
# or with nothing after it, has no ref. The workflow path ends at that @, and
# begins after the repository's slash, the one the first cut below looks for:
# without that slash before the @, or with it right before the @, there is
# no path. Scheme, host, owner and repository are counted as segments, each
# one or more characters that are no slash: a * would take an empty one, or
# two for one. What the cuts below made of any of these would be held against
# every statement,
# which is not at fault. The file cannot serve, as above
[[ "$IDENTITY" == *@?* && "${IDENTITY%%@*}" == +([!/])://+([!/])/+([!/])/+([!/])/*[!/] ]] || { echo "::error::check-provenance: '$ROOT/catalogue-policy.yaml' gives a verification.roles.releaser.identity that cannot be cut into its parts, '$IDENTITY' holds no scheme, host, owner, repository and workflow path before its first @ or no ref after it, the form is <scheme>://<host>/<owner>/<repo>/<workflow path>@<ref> (Req 2.28)" >&2; exit 2; }

# the build workflow's repository, cut from the identity in two steps: what
# follows scheme, host, owner and repository, and then the identity without
# it and without the slash before it
SOURCE=${IDENTITY#*://*/*/*/}
SOURCE=${IDENTITY%"/$SOURCE"}
# the build workflow's path: what follows the repository and its slash, up to
# the first @, where the ref begins (a ref can hold an @ of its own)
WORKFLOW=${IDENTITY#"$SOURCE/"}
WORKFLOW=${WORKFLOW%%@*}
# the build workflow's ref: all that follows that first @
WORKFLOW_REF=${IDENTITY#*@}

# where cosign's stdout is kept until it is read, gone on exit. Without it
# the check cannot be made: cosign's answer would have no place to go, and
# the fault would read as cosign's. mktemp's own words are kept back
TMP=$(mktemp -d 2>/dev/null) || { echo "::error::check-provenance: mktemp gave no directory for temporary files, the check cannot be made without one, the place to look is TMPDIR and the machine's directory for temporary files (Req 2.28)" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# cosign is asked up to three times, since what makes it fail can go away by
# itself; any exit code but 0 is a failed attempt. Between two attempts lies
# a pause, since asking again at once mostly meets the same blip
for attempt in 1 2 3; do
  # stdin is the caller's: the script is called once per digest, and a tool
  # that read stdin would eat what a caller's loop still has to read from it.
  # What cosign writes ends here: its stderr is kept for the script's own
  # lines, its
  # stdout goes to a file that every attempt begins anew, so that what a
  # failed attempt printed is never read (2>&1 stands first, so the capture
  # takes stderr alone)
  said=$(cosign verify-attestation --type slsaprovenance1 --certificate-oidc-issuer "$ISSUER" --certificate-identity "$IDENTITY" "$REF" </dev/null 2>&1 >"$TMP/stdout") && break
  # cosign prints a refusal twice, under "Error: " and then under "error
  # during command execution: ": the message is the first copy without its
  # prefix, so the second is cut off. What cosign wrote without such lines, a
  # Go panic's trace for one, is the message as a whole
  said=${said%%$'\n'"error during command execution: "*}
  # onto the one line word by word, so that no blank is doubled: a message's
  # lines after the first begin with a blank, and the last can end in one
  read -r -d '' -a words <<<"${said#Error: }"
  # another attempt follows: the warning shows in the release's log that this
  # one was lost, and why; then the pause, which reads no stdin either
  if [ "$attempt" -lt 3 ]; then
    echo "::warning::check-provenance: ${REF}: cosign failed on attempt ${attempt} of 3 and is asked again after ${CHECK_PROVENANCE_RETRY_DELAY:-10} seconds, it said:" "${words[@]}" >&2
    sleep "${CHECK_PROVENANCE_RETRY_DELAY:-10}" </dev/null
    continue
  fi
  # 1 whatever code cosign ended with: the code says that the check failed,
  # not how cosign did
  echo "::error::check-provenance: ${REF}: cosign failed on each of 3 attempts, the last time with:" "${words[@]}" "(Req 2.28)" >&2
  exit 1
done
# cosign has ended with 0: the statements in what it printed, each decoded
# from its envelope's payload, one per line. What jq prints is the answer,
# its exit code is not: over no input, and a blank line is none, jq -e ends
# with 0 on jq 1.6 and with 4 on jq 1.7.1. Every line is taken as text (-R)
# and parsed inside the try, each by itself: read as a stream of JSON values,
# jq would stop at the first line that is no JSON and never see the envelopes
# after it. A payload is decoded only when it is a string (jq decodes null as
# it would the word null), and a line that is no JSON, or a payload that is
# not base64 or decodes to no JSON, is no statement and no error, hence the
# try; nor is JSON that is no object a statement. What jq writes on stderr
# is not passed on
statements=$(jq -R -c 'try (fromjson | .payload | strings | @base64d | fromjson | objects) catch empty' "$TMP/stdout" 2>/dev/null)
# nothing verified never passes, and cosign is not asked again: what it
# printed with 0 is no failed attempt
if [ -z "$statements" ]; then
  echo "::error::check-provenance: ${REF}: cosign ended with exit code 0 and what it printed holds no provenance statement (Req 2.28)" >&2
  exit 1
fi
# a jq call that gave no answer: the check has failed, and there is no clause
# to show for it. One ::error:: line naming the reference and the question
# ($1), exit 1; neither cosign nor jq is asked again
unanswered() { echo "::error::check-provenance: ${REF}: the provenance statement cosign verified could not be judged: jq gave no answer when asked for $1 (Req 2.28)" >&2; exit 1; }
# the statements are judged one by one, each by itself: the policy's rule
# admits on any statement that meets the conditions, wherever it stands among
# the others, and the self-check is neither stricter nor laxer than the rule.
# They are read on a file descriptor of the loop's own: a jq started inside
# inherits the loop's stdin, and one that read it would eat the statements
# still to come. Each is counted, its number being its name in the error line
count=0
misses=""
while IFS= read -r statement <&3; do
  count=$((count + 1))
  # cosign has checked who signed the statement, not what it says of who built:
  # its builder identity has to be the build workflow's too, exactly the
  # identity cosign was asked under, as the policy's rule compares for equality
  # (Req 2.28). The two are compared as the JSON text jq prints on one line: so
  # nothing of the value found is lost on its way through the shell, and the
  # error line shows it as it is without ever breaking in two. null is what jq
  # prints where the statement has no such field, and what the try answers
  # where the path cannot be walked because something on the way to the field
  # is no object: there is no value at such a path either, and jq by itself
  # would end on an error there and print nothing. Only the path is answered
  # for: an empty text is no value and is not dressed as null by the shell. A
  # call that printed nothing gave no answer, however it came to that (a jq
  # that was killed and a jq that ended on an error of its own are two ways it
  # comes about), and its empty text fails the check before any text is
  # compared or shown: two empty texts would be equal, and the check would pass
  # unchecked. Whether the text is empty is all that is asked, jq's exit code
  # is not read here either: an answer is never empty, since the try gives a
  # value or null for every statement and the identity always has its JSON
  # text. Both calls stay inside $( ): there bash writes no notice of its own
  # about a jq that was killed, as it does on the script's stderr for a plain
  # command. What jq itself writes on stderr is kept back at both, as at the
  # first call, whatever it is: with no answer the script's stderr holds the
  # one line of unanswered and no more. A miss does not end the run: its clause
  # is kept and the next expectation is read, so that the one error line after
  # the fifth names all that the statement misses
  missed=""
  found=$(jq -c 'try (.predicate.runDetails.builder.id) catch null' <<<"$statement" 2>/dev/null)
  [ -n "$found" ] || unanswered "its builder identity"
  expected=$(jq -nc --arg identity "$IDENTITY" '$identity' 2>/dev/null)
  [ -n "$expected" ] || unanswered "the JSON text of the builder identity expected of it"
  [ "$found" = "$expected" ] || missed="${missed:+$missed; }builder identity is ${found}, expected ${expected}"
  # the build type says which kind of build wrote the statement, and with it
  # what the fields under externalParameters mean: the policy's rule compares
  # it for equality too. Asked, compared and kept as the builder identity is:
  # an expectation the statement meets leaves nothing for the line
  found=$(jq -c 'try (.predicate.buildDefinition.buildType) catch null' <<<"$statement" 2>/dev/null)
  [ -n "$found" ] || unanswered "its build type"
  expected=$(jq -nc --arg type "$BUILD_TYPE" '$type' 2>/dev/null)
  [ -n "$expected" ] || unanswered "the JSON text of the build type expected of it"
  [ "$found" = "$expected" ] || missed="${missed:+$missed; }build type is ${found}, expected ${expected}"
  # the source repository says whose workflow file was run, and the policy's
  # rule compares it for equality as well: a fork, or the URL with something
  # after it, is another repository, so the value found is compared as it is.
  # Asked, compared and kept as the two before it
  found=$(jq -c 'try (.predicate.buildDefinition.externalParameters.workflow.repository) catch null' <<<"$statement" 2>/dev/null)
  [ -n "$found" ] || unanswered "its source repository"
  expected=$(jq -nc --arg source "$SOURCE" '$source' 2>/dev/null)
  [ -n "$expected" ] || unanswered "the JSON text of the source repository expected of it"
  [ "$found" = "$expected" ] || missed="${missed:+$missed; }source repository is ${found}, expected ${expected}"
  # the workflow path says which of the repository's workflow files was run: a
  # repository holds several, the policy's rule admits the build workflow alone
  # and compares for equality here as well, so the value found is not tidied
  # before it is compared. Asked, compared and kept as the three before it
  found=$(jq -c 'try (.predicate.buildDefinition.externalParameters.workflow.path) catch null' <<<"$statement" 2>/dev/null)
  [ -n "$found" ] || unanswered "its workflow path"
  expected=$(jq -nc --arg workflow "$WORKFLOW" '$workflow' 2>/dev/null)
  [ -n "$expected" ] || unanswered "the JSON text of the workflow path expected of it"
  [ "$found" = "$expected" ] || missed="${missed:+$missed; }workflow path is ${found}, expected ${expected}"
  # the ref says from which branch or tag the workflow file was taken: the
  # policy's rule admits the release branch alone and compares for equality
  # here as well, so the same file run from another branch is a miss, and the
  # value found is not tidied before it is compared. Asked, compared and kept
  # as the four before it
  found=$(jq -c 'try (.predicate.buildDefinition.externalParameters.workflow.ref) catch null' <<<"$statement" 2>/dev/null)
  [ -n "$found" ] || unanswered "its ref"
  expected=$(jq -nc --arg ref "$WORKFLOW_REF" '$ref' 2>/dev/null)
  [ -n "$expected" ] || unanswered "the JSON text of the ref expected of it"
  [ "$found" = "$expected" ] || missed="${missed:+$missed; }ref is ${found}, expected ${expected}"
  # a statement that misses nothing is the admitted one: the others are not
  # read, and nothing is said of those read before it
  [ -n "$missed" ] || break
  # what this one misses is kept under its number: should none meet all five,
  # the line has to say of each statement what is wrong with it
  misses="${misses:+$misses; }statement ${count}: ${missed}"
done 3<<<"$statements"
# no statement met all five, the last one read neither, and the check has
# failed; cosign is not asked again. One line: of a lone statement the clause
# of each expectation it missed, of several the same for each under its number
if [ -n "$missed" ]; then
  if [ "$count" -gt 1 ]; then
    echo "::error::check-provenance: ${REF}: none of the ${count} provenance statements cosign verified is one the catalogue's verification policy would admit: ${misses} (Req 2.28)" >&2
    exit 1
  fi
  echo "::error::check-provenance: ${REF}: the provenance statement cosign verified is not one the catalogue's verification policy would admit: ${missed} (Req 2.28)" >&2
  exit 1
fi
echo "check-provenance: ${REF}: cosign was asked for a SLSA provenance statement signed by ${IDENTITY} and ended with exit code 0, what it printed holds a provenance statement whose builder identity is that identity, whose build type is ${BUILD_TYPE}, whose source repository is ${SOURCE}, whose workflow path is ${WORKFLOW} and whose ref is ${WORKFLOW_REF}, what else the statement says is not read"
