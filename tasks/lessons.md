# Lessons (corrections, with the rule that prevents the repeat)

## 2026-08-26: always plain language and examples in conversation

**What happened.** Session reports were dense spec-speak (criterion
numbers, "supported set", "quantifiers", "attestation") with no
translation. The owner, new to hardened-image catalogue concepts, had to
ask for simple language.

**Rule.** Every message to the owner uses plain words and one everyday
example per concept (SBOM as the ingredients list, VEX as the honest
note on a known problem, the revocation record as a product recall list,
the active set as the on/off switch list). Introduce a term once with
its plain meaning before using it. Criterion numbers and paths appear
only as small parenthetical references. The formal register stays inside
repo artifacts, where the validator and house style require it.

## 2026-08-26: never run a blind regex over a structured file

**What happened.** A repo-wide `sed` replacing every spaced em dash with
a colon was run over YAML and shell files just before committing task
9.8, to satisfy the no-em-dash rule. In
`.github/workflows/validate.yml` it rewrote step names into
`- name: pin + definition lint: docs/CONVENTIONS.md`. A plain YAML
scalar may not contain a colon followed by a space, so the whole file
stopped parsing. GitHub refuses to run a workflow whose YAML is invalid
and reports it only on the run page, so **both validate jobs never ran,
their two required checks never appeared on the pull request**, and the
other workflows going green made the pull request look healthy. The
owner spotted the missing jobs; the local checks run after the sed
(sandboxed unit suites and the rendering drift check) could not see it.

**Rules.**
1. Edit structured files (YAML, JSON, TOML) through targeted edits, never
   a blind pattern replacement. If a sweep is unavoidable, parse every
   touched file afterwards and diff the result.
2. Any edit made after the verification run invalidates that run. Re-run
   the **whole** chain against the real repository, not only the
   sandboxed unit suites: the skipped step here was
   `scripts/lint-workflow-policy.sh` against the repository itself, which
   would have caught it.
3. Gate a commit on the verifier's success verdict, not on a grep exit
   code that can pass while the tool fails (this cost a bad commit on the
   primitives branch the same week).
4. A tool that reads a structured file reports a parse error by name
   rather than crashing: `lint-workflow-policy.sh` gained that behaviour
   and its own regression test in this task, and it named the one
   remaining broken line immediately.
5. A generator must not depend on which implementation of a text tool is
   installed. The rendered snippet carries shell line continuations;
   GitHub's runners ship gawk, which strips a backslash before a newline
   in an `awk -v` assignment, while this devcontainer ships mawk, which
   keeps it. The drift check therefore passed locally and failed in CI
   with no local reproduction. Splicing moved into python3, which does no
   escape processing, and a stub awk mimicking gawk is now a regression
   test. Same class as command substitution eating trailing newlines:
   keep rendered text inside one implementation that touches nothing.
6. Run the gate exactly as CI runs it, never a subset. The follow-up
   commit still failed once, because the local check was
   `yamllint .github/workflows/ catalogue-policy.yaml` while CI runs
   `yamllint .`: the rendered `policies/verify-catalogue-images.yaml`
   was missing its trailing newline, which this repo lints as an error.
   A generator must satisfy the repo's own linters, so the renderer now
   ends every artifact with a newline and its test asserts it.

## 2026-09-01: moving inline shell into a script leaves dangling references behind

**What happened.** Task 9.1 moved the trivy invocation out of
`build.yml` into `scripts/scan-image.sh`, and the `accepted=` assignment
went with it. The step summary that stayed behind still read `$accepted`
three times; under `set -u` the first read killed the step on its first
real run. Every script suite was green, because the defect lived in
workflow shell, which no suite reads. actionlint+shellcheck would not
have flagged it either: actionlint suppresses SC2154 by default, since
workflow env vars look unassigned to shellcheck.

**Rules.**
1. After extracting inline shell into a script, sweep what remains for
   references to anything the extraction took along, before the first
   push. The working check: run shellcheck with `--include=SC2154` over
   each `run:` block with that step's `env:` keys prepended as assigned;
   on 2026-09-01 that sweep reported exactly the one real defect across
   all six workflows and nothing else.
2. A step that has never completed in CI gets a local rehearsal before
   the next push: extract the `run:` block verbatim, set the step's env,
   and execute it against a real published digest. Both summary branches
   (empty triage and populated triage) ran locally before the fix went
   up, which is how one round-trip replaced several.

## 2026-09-02: this repository squash-merges, so a stacked PR conflicts at the second merge

**What happened.** Task 9.4 was branched from task 9.3's unmerged branch and
opened as PR #118 with that branch as base. #116 (9.3) was squash-merged, so
main received one new commit while the 9.3 branch kept its original commits;
merging #118 then landed the 9.4 commit onto the orphaned 9.3 branch, and the
owner's follow-up PR offering that branch to main conflicted with main's
squashed twin of 9.3. Rebuilding the branch as main plus one cherry-picked
commit (verified byte-identical) resolved it.

**Rule.** Never stack a PR on another open PR here. When a task depends on
unmerged work, either wait for the merge, or branch from it and, the moment
the base squash-merges, reset the branch to main and cherry-pick only the
new commits before anyone merges the dependent PR.

## 2026-09-07: an outward-facing draft carried two claims a grep had invented

**What happened.** The valkey-helm draft said the exporter's image value was
`metrics.image` and that the init script needed "tee, cat, rm, mkdir and
date". Both came from a grep for the names I expected rather than from
reading the files: the value is `metrics.exporter.image`, and the script also
calls chmod, touch, sha256sum and cut on the ACL path. An adversarial second
review, prompted by the owner asking whether the ask was naive, found both.
The ask itself held up (no design reason for image parity, no existing knob,
active maintainers), but either slip alone would have read as uninformed on
the upstream tracker.

**Rule.** Before a draft leaves the repo, read every upstream file it cites
end to end and quote value paths verbatim from `values.yaml`; count binaries
over the whole script, including every conditional branch, and make the
check script print the full list so the count is measured, not remembered.
Then have a second reviewer argue against filing before the owner does.

## 2026-09-08: a fixture that hardcodes the value a bump PR moves turns every bump red

**What happened.** The helm chart-version manager fixture (task 11.4)
asserted the three pinned chart versions as literals while reading the real
`chart/<name>/chart.yaml` files. The first two chart bumps Renovate opened
(#167 cert-manager v1.21.1, #168 valkey 0.12.0) failed the lint battery on
that fixture alone, and the CI annotations named nothing, so the cause was
found only by running the whole validate chain locally on the PR branch.
The tool-pin suites hardcode versions on purpose (the test is the second
record of a human-verified pin); a chart version has no human half, so the
literal only made the tracking self-defeating.

**Rule.** A fixture over a file that Renovate rewrites asserts the shape of
the captured value and that it equals what the file pins now, never the
literal, unless a human is meant to touch the test on every bump and the
test says so. Before merging a new manager, simulate its own bump PR
against the fixture (edit the pin, run the suite, revert).

## 2026-09-08: a step ran before the tool it needs was installed, and the script read the missing tool as data

**What happened.** The publish-on-change comparator calls cosign; build.yml
installed cosign in the release part, after the comparator; the runner image
has none. "cosign: command not found" was caught by the comparator's
"unreadable attestation" branch, which publishes by design, so every nightly
rebuild published every definition for a week. The unit suite could not see
it (cosign was stubbed on PATH), the local rehearsal could not see it (cosign
is installed here), and the daily summary said "different" in a place the API
does not expose. The LOG even recorded the symptom without asking why.

**Rule.** For every workflow step, list the tools its script calls and check
each is installed EARLIER in the same job (grep the step order, not the
file). A script that shells out guards its tools up front and refuses when
one is missing; a missing tool is an environment failure, never a data
verdict. And when a nightly publishes without a reason you can name, that is
a finding, not a line in the log.

## 2026-09-10: a manager that bumps modules one at a time breaks module families

Enabling Renovate's gomod manager (D4) offered `k8s.io/api` alone; the
Kubernetes client libraries only work at one version together, and here they
are pinned by the e2e framework. Rule: when a manager is switched on, ask which
of its dependencies form a family that must move as one, and either group them
or let the one that pins them carry the rest. Renovate reports an artifact
failure as a PR comment, not in the PR body or the CI log; read the comments
before the log.
