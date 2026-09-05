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
