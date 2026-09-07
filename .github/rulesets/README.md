# Committed rulesets (Req 9.8, 9.9)

`main_sec.json` is the intended branch ruleset for `main`, in GitHub's
export format (Settings, Rules, the ruleset's "Export"), importable the same
way. It requires the build gate and the e2e gate (with the lint battery, the
Go modules and the render and policy gate), one approving review, linear
history, signed commits and squash merges.

The daily rescan compares every file here against the live rulesets API
through anonymous reads (`scripts/check-governance.sh`, Req 9.9): by ruleset
name, over name, target, enforcement, conditions and rules, ignoring
server-assigned fields (`id`, `source`, `source_type`, `node_id`, `_links`,
timestamps) and ignoring order inside lists. It runs both directions: a
committed ruleset with no active live counterpart and an active live branch
ruleset with no committed counterpart are both failures, so a retired
ruleset that returns is caught.

`bypass_actors` is outside the compared set because anonymous reads withhold
it. It is carried here by the export (the repository administrator, bypass
mode `always`), stated in `SECURITY.md`, and recorded from the admin view in
`data/rulesets-admin-view-2026-09-07.json`.

The second-maintainer switch is `require_code_owner_review` in the
`pull_request` rule, `false` today: set it to `true` and add the second
maintainer to `CODEOWNERS`, then import the file, and the one-review rule is
enforced instead of bypassed.

To change the ruleset: edit it in the UI and export it over this file, or
edit this file and import it; either way the next rescan proves the two
agree.
