# Shell style (`scripts/*.sh`)

- `#!/usr/bin/env bash`, `set -euo pipefail` (test suites use `set -u` and count failures).
- A header comment: what the script holds, which criterion and task, what it refuses and what it reports; measured facts with their date.
- Arguments: `<root>` first for anything reading the repository; usage errors exit 2 with a `::error::` line.
- YAML is parsed with an inline `python3 - "$arg" <<'PY' ... PY` block using PyYAML, never yq. The Python prints results one per line or tab-separated for the shell to read.
- Readers live in `scripts/definition-lib.sh` and are sourced with `# shellcheck source=definition-lib.sh`; a reader refuses (exit 2, `::error file=catalogue-policy.yaml::<reader>: ... (Req n.m)`) rather than returning an empty answer.
- Lints print `::error file=<path>::<lint>: <problem>; <way out> (Req n.m)` per failure, count violations, exit 1 if any, and print one summary line on success saying what was checked and how many.
- Every script has `<name>_test.sh` beside it, run by a validate step. Suites build sandboxes with `mktemp -d`, write minimal fixtures (`image/<n>/image.yaml`, `chart/<c>/chart.yaml`, `catalogue-policy.yaml`), call the script with the sandbox as root, and assert exit code plus substrings with an `expect` helper. Numbered cases with a one-line intent comment.
- Time comes from `${DHC_TODAY:-$(date -u +%F)}` so tests can set the clock.
- `shellcheck` directives are kept; quoting is strict; no `echo` of unquoted variables.
