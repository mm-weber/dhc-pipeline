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
