# Development workflow

## Core principles

1. **Spec before code.** Requirements are amended in `.specs/dhc-catalogue-mvp/requirements.md` (EARS) with a design decision and a task entry before anything is implemented. A track's `spec.md` and `plan.md` derive from that.
2. **Test-driven, one slice at a time.** Strict TDD: one failing test, the minimum code to pass it, commit, next test. Never several tests in one red phase.
3. **The agent split.** The orchestrator never implements. For each slice it dispatches a RED agent (writes exactly one failing test, runs it, reports the failure reason) and then a GREEN agent (makes that one test pass with the smallest change, runs the whole suite). The orchestrator reviews the diff, runs the suite itself, and commits.
4. **Worktree per pull request.** `scripts/worktree-create.sh dhc-pipeline <branch>` from `/workspace`; never commit on `main/`; one pull request per task; squash merges; never stack pull requests.
5. **Everything named.** Every check fails by name citing its criterion; every commit names the criterion and the task.

## Task lifecycle

1. **Select** the next `[ ]` task in the track's `plan.md`; confirm its dependencies are merged.
2. **Mark** it `[~]` in `plan.md` (committed with the first slice).
3. **RED (agent):** one test in the script's `_test.sh` suite (or Go test), run, must fail for the stated reason.
4. **GREEN (agent):** the minimum change; the whole suite green.
5. **Refactor** only with the suite green, and only inside the slice's scope.
6. **Verify (orchestrator):** run the suite, run the touched lint against the real repository (`scripts/<lint>.sh .`), run yamllint on touched YAML, and rehearse any validate step that changed. Any edit after a verification run invalidates it; rerun the chain.
7. **Commit (orchestrator):** signed, message `<area>: <what> (Req <n.m>; task <N.M>)`, trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` only, never a session link.
8. **Mark** the task `[x]` with the commit hash in `plan.md`.

## Phase completion

A phase is one pull request. At its end:

1. All phase tasks `[x]`; the full suite of every touched script green; the real-repository runs green.
2. Push the branch, open the pull request with the title in the commit style, the body opening with a `## TL;DR` section (what ships as of the head; updated whenever a review comes in, with each finding's disposition), then why, what, and how it was verified, ending with the Claude Code attribution line. No session links.
3. The owner reviews and merges (squash). Checkpoint reached when the merge lands; the next phase branches from the new main.

## Verification commands

```bash
scripts/definition-lib_test.sh          # the shared readers
scripts/lint-probes_test.sh             # the probe lint
scripts/lint-probes.sh .                # the lint against this repository
scripts/lint-active-set.sh .            # the active set, after a policy file edit
scripts/release-policy.sh . check       # the release switches, after a policy file edit
yamllint catalogue-policy.yaml
scripts/lint-live-evidence.sh .         # after a requirements change
```

## Commit and pull request conventions

- Signed commits (SSH key in the repository's `.keys/`), verified on GitHub.
- No em-dashes in messages or bodies.
- A pull request touches one logical change. Spec amendments, scaffolding and code are separate pull requests.
- Every pull request body opens with a `## TL;DR` section, updated when reviews come in (`docs/CONVENTIONS.md`, rule of 2026-10-16).
- Renovate's own commits stay unsigned and are not rewritten.

## Lessons that bind

`tasks/lessons.md` holds corrections with the rule each produced. Two that apply to every task: never run a blind pattern replacement over a structured file; rerun the whole verification chain after any edit, including the lints against the real repository, not only sandboxed suites.
