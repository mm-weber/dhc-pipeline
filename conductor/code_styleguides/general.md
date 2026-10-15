# General style

The rulebook the lints enforce is `docs/CONVENTIONS.md`; corrections and the rules they produced are in `tasks/lessons.md`. This guide is what holds across languages.

- **Fail by name.** A check reports every failure, each with the file, the problem, the way out and the criterion number. Never only the first failure; never a silent pass.
- **Refusal versus violation.** Exit 2 when the input cannot be read as what it claims (missing file, wrong shape, missing tool); exit 1 when it was read and found wrong. A refusal is never "nothing to do".
- **One reader per declared value.** A value in `catalogue-policy.yaml` has exactly one reader in `scripts/definition-lib.sh`, `release-policy.sh` or `triage-policy.sh`; every consumer goes through it. No local re-parse.
- **No placeholders.** A field either carries a real value or is absent; the check decides what absence means.
- **Pin everything.** Tools by version and checksum, images by digest, sources by commit.
- **Comments say why,** cite the criterion and the task, and record what was measured and when. A comment never claims more than the code does.
- **Structured files are edited by hand or by a parser,** never by a blind pattern replacement (lesson of 2026-08-26).
- **No em-dashes** in code comments, docs, messages.
- **Dates** are ISO (`YYYY-MM-DD`), UTC, and every clock has a test seam (`DHC_TODAY`).
