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
# The answer is read in three places: cosign's exit code, its stderr when it
# fails, its stdout when it ends with 0. Any code but 0 is a failed attempt,
# a crash of cosign's as much as a refusal, and a failed attempt is tried
# again, up to three attempts: what makes cosign fail can go away by itself,
# a registry that does not answer for a moment. After the third failure the
# check has failed: one ::error:: line on stderr naming the reference, the
# three attempts and what cosign said the last time, and exit 1 whatever code
# cosign ended with. What cosign said is what it wrote on stderr in that
# attempt, word by word on the one line: of a refusal, which cosign prints
# twice (under "Error: " and then under "error during command execution: "),
# the first copy without its prefix; of anything else, a Go panic's trace for
# one, all of it.
# With 0 cosign has printed on stdout the attestations it verified, one
# envelope per line, the statement base64 in the envelope's payload. That
# stdout is read for whether it holds a provenance statement: an envelope
# whose payload is a string that decodes from base64 to a JSON object. Nothing
# else is one: not a line that is no envelope, not a payload that is null,
# that is not base64 or that decodes to anything but a JSON object. With no
# statement the check has failed, though cosign ended with 0: a self-check
# that passes when nothing was verified has checked nothing. One ::error::
# line on stderr naming the reference, and exit 1; cosign is not asked again,
# what it printed with 0 is its answer and no failed attempt.
# With a statement the other half is asked, what the statement says: cosign
# has checked who signed it, not what it says of who built. Of the five
# expectations (ADR 0005, decision 5) one is read so far, the builder
# identity: the value at .predicate.runDetails.builder.id has to be the build
# workflow's identity, exactly the one cosign was asked under, as the policy's
# rule compares for equality (Req 2.28). With another value there, one that
# only begins or ends like that identity as much as any other, or with no such
# field, the check has failed: one ::error:: line on stderr naming the
# reference and holding the clause "builder identity is <found>, expected
# <expected>", and exit 1; cosign is not asked again. Both values stand in the
# clause as the JSON text jq prints on one line: a value found shows as it is,
# a line break in it as \n, and never breaks the line in two; null stands for
# no such field. A path that cannot be walked, the builder a string for one,
# fails too, but not yet in that one line. With that identity at the path the
# script ends with 0 and one line on stdout that names the reference and says
# so. The other four expectations, build type, source repository, workflow
# path and ref, are not read yet, and of several statements none is chosen
# yet. Nothing cosign writes is passed on as it is.
set -uo pipefail
# after the mode word: the root that holds catalogue-policy.yaml, and the
# reference cosign is asked about
ROOT="$2"
REF="$3"

ISSUER=$(python3 -c 'import sys,yaml; print((yaml.safe_load(open(sys.argv[1])) or {}).get("verification",{}).get("issuer",""))' "$ROOT/catalogue-policy.yaml")
# the role named releaser, whatever its place and whatever it attests
IDENTITY=$(python3 -c 'import sys,yaml; print((yaml.safe_load(open(sys.argv[1])) or {}).get("verification",{}).get("roles",{}).get("releaser",{}).get("identity",""))' "$ROOT/catalogue-policy.yaml")

# where cosign's stdout is kept until it is read, gone on exit
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# cosign is asked up to three times, since what makes it fail can go away by
# itself; any exit code but 0 is a failed attempt
for attempt in 1 2 3; do
  # stdin is the caller's: the script is called once per digest, and a tool
  # that read stdin would eat what a caller's loop still has to read from it.
  # What cosign writes ends here: its stderr is kept for the error line, its
  # stdout goes to a file that every attempt begins anew, so that what a
  # failed attempt printed is never read (2>&1 stands first, so the capture
  # takes stderr alone)
  said=$(cosign verify-attestation --type slsaprovenance1 --certificate-oidc-issuer "$ISSUER" --certificate-identity "$IDENTITY" "$REF" </dev/null 2>&1 >"$TMP/stdout") && break
  [ "$attempt" -lt 3 ] && continue
  # cosign prints a refusal twice, under "Error: " and then under "error
  # during command execution: ": the message is the first copy without its
  # prefix, so the second is cut off. What cosign wrote without such lines, a
  # Go panic's trace for one, is the message as a whole
  said=${said%%$'\n'"error during command execution: "*}
  # onto the one line word by word, so that no blank is doubled: a message's
  # lines after the first begin with a blank, and the last can end in one
  read -r -d '' -a words <<<"${said#Error: }"
  # 1 whatever code cosign ended with: the code says that the check failed,
  # not how cosign did
  echo "::error::check-provenance: ${REF}: cosign failed on each of 3 attempts, the last time with:" "${words[@]}" "(Req 2.28)" >&2
  exit 1
done
# cosign has ended with 0: the statements in what it printed, each decoded
# from its envelope's payload, one per line. What jq prints is the answer,
# its exit code is not: over no input, and a blank line is none, jq -e ends
# with 0 on jq 1.6 and with 4 on jq 1.7.1. A payload is decoded only when it
# is a string (jq decodes null as it would the word null), and one that is
# not base64, or decodes to no JSON, is no statement and no error, hence the
# try; nor is JSON that is no object a statement. What jq says of a line
# that is no JSON is not passed on
statements=$(jq -c 'try (.payload | strings | @base64d | fromjson | objects) catch empty' "$TMP/stdout" 2>/dev/null)
# nothing verified never passes, and cosign is not asked again: what it
# printed with 0 is no failed attempt
if [ -z "$statements" ]; then
  echo "::error::check-provenance: ${REF}: cosign ended with exit code 0 and what it printed holds no provenance statement (Req 2.28)" >&2
  exit 1
fi
# cosign has checked who signed the statement, not what it says of who built:
# its builder identity has to be the build workflow's too, exactly the
# identity cosign was asked under, as the policy's rule compares for equality
# (Req 2.28). The two are compared as the JSON text jq prints on one line: so
# nothing of the value found is lost on its way through the shell, and the
# error line shows it as it is without ever breaking in two. null is what jq
# prints where the statement has no such field
found=$(jq -c '.predicate.runDetails.builder.id' <<<"$statements")
expected=$(jq -nc --arg identity "$IDENTITY" '$identity')
if [ "$found" != "$expected" ]; then
  echo "::error::check-provenance: ${REF}: the provenance statement cosign verified is not one the catalogue's verification policy would admit: builder identity is ${found}, expected ${expected} (Req 2.28)" >&2
  exit 1
fi
echo "check-provenance: ${REF}: cosign was asked for a SLSA provenance statement signed by ${IDENTITY} and ended with exit code 0, what it printed holds a provenance statement whose builder identity is that identity, what else the statement says is not read"
