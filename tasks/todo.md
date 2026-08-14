# #74 — pin + verify all workflow-installed tools (Req 7.5/7.6)

Plan: extend the existing `install-tool.sh` pin-block machinery (already
renovate-tracked) for helm and ct; hash-pinned pip requirements file for the
python installs; renovate manager + fixtures for the new pin surface.

- [x] 1. `install-tool.sh`: add `helm` (get.helm.sh tarball, member
      `linux-amd64/helm`, pin v4.2.4 = what the unpinned action resolves
      today) and `ct` (github tarball, member `ct`, plus `etc/lintconf.yaml`
      + `etc/chart_schema.yaml` extras — ct lint needs them)
- [x] 2. `install-tool_test.sh`: TDD the new cases via the existing
      BASE_URL/PINS seams (helm nested member, ct extras, checksum refusal)
- [x] 3. `.github/requirements-ci.txt`: yamllint + pathspec + pyyaml + yamale,
      exact pins, full PyPI `--hash` sets, `# renovate:` comments
- [x] 4. Workflows: e2e.yml + chart.yml helm via install-tool.sh (drop
      azure/setup-helm); chart.yml ct via install-tool.sh + pip
      `--require-hashes` (drop chart-testing-action), ct lint gets explicit
      --lint-conf/--chart-yaml-schema; validate.yml + rescan.yml pip
      `--require-hashes`
- [x] 5. renovate.json5: regex manager for requirements-ci.txt (pypi
      datasource, version-only bumps — hash refresh stays human, same
      friction model as the sha256 pins)
- [x] 6. test/renovate: fixture + managers.test.mjs cases (extract + no
      false-positive), both directions
- [x] 7. Docs: tasks.md 8.6 list + CONVENTIONS.md pinning claim reflect the
      new coverage
- [x] 8. Run all touched test suites; yamllint; commit; PR

## Review

(to fill when done)
All items done — see PR. Local verification: install-tool suite (23 new
assertions), scanners suite, renovate manager fixtures + strict config
validation, --require-hashes install in a clean venv, real ct install from
upstream (checksum matched) and a real `ct lint` run over hardened-app with
the new flags. helm fetch is firewall-blocked locally; its pin was
cross-checked against the helm release notes and CI verifies the bytes.
