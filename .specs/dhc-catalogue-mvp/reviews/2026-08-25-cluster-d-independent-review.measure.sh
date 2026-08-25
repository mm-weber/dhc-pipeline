#!/usr/bin/env bash
# Measurements behind the PR #103 (cluster D) independent review, 2026-08-25.
# Run from the worktree root. Network sections need the devcontainer allowlist
# (api.github.com, docs.github.com, raw.githubusercontent.com, ghcr.io).
# Sections:
#   S1  EARS validator over the amended requirements, and over the review's proposed rewordings
#   S2  anonymous rulesets API: list, single-ruleset field inventory (bypass_actors absent),
#       main_sec pull_request rule parameters (required_approving_review_count still 1)
#   S3  docs.github.com REST rules page: bypass_actors returned only with write access;
#       endpoint usable without authentication on public repos
#   S4  behavioral bypass proof: PR #102 merged 2026-08-25 with no APPROVED review
#       under the live one-approval rule, so a bypass actor exists and is invisible anonymously
#   S5  private vulnerability reporting status, anonymous read (Req 9.2, 9.3 basis)
#   S6  repository security advisories, anonymous reads: this repo plus grafana/grafana control (Req 9.4 basis)
#   S7  ruleset export or import format: docs import flow, and a real export in
#       github/ruleset-recipes carrying bypass_actors and id (Req 9.8, 9.9 basis)
#   S8  grype --vex source facts: product identifier forms, statuses filtered (Req 9.11 to 9.13 basis)
#   S9  catalogue tag counts per repository (scale behind Req 9.12's rescan-wide portability block)
#   S10 packages REST docs: deletion endpoints operate on packages and versions, no tag endpoint
#       (revocation runbook mechanics, task 13.3)
#   S11 tree facts: DHI-style label occurrences, consumer-facing grype and vexctl absence,
#       ADR 0003 line 142, absent posture artifacts, LOG-anchor lint absent from every task group
set -uo pipefail
SCRATCH="${SCRATCH:-$(mktemp -d)}"
echo "scratch: $SCRATCH"
API="https://api.github.com/repos/mm-weber/dhc-pipeline"

echo
echo "== S1: EARS validator"
node .claude/skills/ears-notation/scripts/ears-validator.js .specs/dhc-catalogue-mvp/requirements.md | grep -E "Valid Statements|PASSED|FAILED"
mkdir -p "$SCRATCH/earscheck"
cat > "$SCRATCH/earscheck/requirements.md" <<'EOF'
# Requirements Document

## Introduction

Scratch validation of the review's proposed rewordings.

## Requirements

### Requirement 9: Scratch

**Objective:** As a reviewer, I want proposed texts validated, so that fixes are drop-in.

#### Acceptance Criteria

1. THE Scan Pipeline SHALL compare at least once per day each committed ruleset's name, target, enforcement, conditions and rules against its live counterpart through anonymous reads, and SHALL report each difference, each committed ruleset lacking an active live counterpart and each active branch ruleset lacking a committed counterpart as a failure of that run.
2. THE Scan Pipeline SHALL run at least once per day its published consumer verification instructions verbatim against one published digest, SHALL report a failed instruction step or a suppression missing in its authoritative consumer as a failure of that run, and SHALL report each remaining declared consumer's suppression result and each divergence in that run's portability block.
3. THE Repository SHALL carry a notice file naming its hardening substrate's copyright and licence, SHALL carry a copy of its hardening substrate's licence text, and SHALL state beside them that third-party packages carry upstream licences enumerated in attested SBOMs.
4. THE Repository SHALL declare its VEX consumers as a list in its catalogue policy file, exactly one consumer marked authoritative, each consumer an adapter emitting findings in one normalised shape: vulnerability identifier, package url and suppression state.
5. IF triage/revocations.yaml violates its schema THEN THE CI Pipeline SHALL fail validation naming each violation.
6. THE Repository SHALL record every revoked digest in triage/revocations.yaml, each entry carrying digest, reason, replacement digest or a recorded absence of one, advisory link and date.
7. IF an accepted-risk exception's reasoning reference or a VEX source statement's log citation resolves to no heading in triage/LOG.md THEN THE CI Pipeline SHALL fail validation naming that reference.
8. WHEN a pull request scan or a scheduled rescan completes THE Scan Pipeline SHALL report a VEX portability block naming, for each statement its authoritative scanner suppressed on that pull request's images or on a supported digest, each declared consumer's suppression result and each divergence.
EOF
node .claude/skills/ears-notation/scripts/ears-validator.js "$SCRATCH/earscheck/requirements.md" | grep -E "Valid Statements|PASSED|FAILED"

echo
echo "== S2: anonymous rulesets API"
curl -s "$API/rulesets" | python3 -c "
import json,sys
for r in json.load(sys.stdin): print('list entry:', r['id'], r['name'], r['enforcement'])
"
curl -s "$API/rulesets/20716271" -o "$SCRATCH/main_sec.json"
python3 -c "
import json
d = json.load(open('$SCRATCH/main_sec.json'))
print('single-ruleset top-level keys:', sorted(d.keys()))
print('bypass_actors key present:', 'bypass_actors' in d)
print('current_user_can_bypass key present:', 'current_user_can_bypass' in d)
for r in d['rules']:
    if r['type'] == 'pull_request':
        p = r['parameters']
        print('pull_request parameters:', json.dumps(p, sort_keys=True))
    if r['type'] == 'required_status_checks':
        print('required checks:', [c['context'] for c in r['parameters']['required_status_checks']])
"

echo "-- rules API (rules/branches/main), the endpoint task 13.2 names, for contrast:"
curl -s "$API/rules/branches/main" | python3 -c "
import json,sys
d = json.load(sys.stdin)
print('merged rule entries:', len(d))
print('entry keys of first rule:', sorted(d[0].keys()))
print('ruleset_ids present:', sorted(set(r['ruleset_id'] for r in d)))
"

echo
echo "== S3: docs.github.com REST rules page notes"
curl -s "https://docs.github.com/en/rest/repos/rules?apiVersion=2022-11-28" -o "$SCRATCH/rules_docs.html"
python3 -c "
import re,html
t = open('$SCRATCH/rules_docs.html', encoding='utf-8').read()
t = re.sub('<[^>]+>',' ',t); t = html.unescape(t); t = re.sub(r'\s+',' ',t)
m = re.search(r'To prevent leaking sensitive information[^.]*\.', t)
print('bypass note:', m.group(0) if m else 'NOT FOUND')
print('without-authentication note occurrences:', len(re.findall('This endpoint can be used without authentication', t)))
"

echo
echo "== S4: behavioral bypass proof (PR #102)"
curl -s "$API/pulls/102" | python3 -c "
import json,sys
d = json.load(sys.stdin)
print('PR 102 author:', d['user']['login'], '| merged_at:', d['merged_at'])
"
curl -s "$API/pulls/102/reviews" | python3 -c "
import json,sys
d = json.load(sys.stdin)
print('PR 102 reviews:', [(r['user']['login'], r['state']) for r in d])
print('APPROVED count:', sum(1 for r in d if r['state'] == 'APPROVED'))
"

echo
echo "== S5: private vulnerability reporting, anonymous"
curl -s -w "HTTP %{http_code}\n" "$API/private-vulnerability-reporting"

echo
echo "== S6: repository security advisories, anonymous"
curl -s -o "$SCRATCH/adv.json" -w "own repo HTTP %{http_code}: " "$API/security-advisories"; python3 -c "
import json; print('advisory count:', len(json.load(open('$SCRATCH/adv.json'))))"
curl -s "https://api.github.com/repos/grafana/grafana/security-advisories?per_page=2" | python3 -c "
import json,sys
d = json.load(sys.stdin)
print('grafana/grafana control:', [(a['ghsa_id'], a['state']) for a in d])
"

echo
echo "== S7: ruleset export or import format"
python3 -c "
import re,html
t = open('$SCRATCH/rules_docs.html', encoding='utf-8').read()
" 2>/dev/null || true
curl -s "https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/managing-rulesets-for-a-repository" -o "$SCRATCH/managing.html"
python3 -c "
import re,html
t = open('$SCRATCH/managing.html', encoding='utf-8').read()
t = re.sub('<[^>]+>',' ',t); t = html.unescape(t); t = re.sub(r'\s+',' ',t)
m = re.search(r'Import a ruleset[^.]*\. Open the exported JSON file\.', t)
print('import flow:', m.group(0) if m else 'NOT FOUND')
"
curl -s "https://raw.githubusercontent.com/github/ruleset-recipes/main/universe-demos/Repo-Universe%20Demo.json" | python3 -c "
import json,sys
d = json.load(sys.stdin)
print('ruleset-recipes repo export top-level keys:', sorted(d.keys()))
print('bypass_actors in export:', json.dumps(d.get('bypass_actors')))
print('id in export:', d.get('id'), '| source in export:', d.get('source'))
"

echo
echo "== S8: grype --vex source facts (anchore/grype main)"
curl -s "https://raw.githubusercontent.com/anchore/grype/main/grype/vex/openvex/implementation.go" -o "$SCRATCH/grype_openvex.go"
grep -n "identifiers = append" "$SCRATCH/grype_openvex.go"
grep -n "StatusNotAffected\|StatusFixed" "$SCRATCH/grype_openvex.go" | head -4
curl -s "https://raw.githubusercontent.com/anchore/grype/main/README.md" | grep -n -i "openvex"

echo
echo "== S9: catalogue tag counts (anonymous ghcr)"
TOTAL=0
for repo in hardened-app cert-manager-controller cert-manager-webhook cert-manager-cainjector grafana valkey; do
  TOK=$(curl -s "https://ghcr.io/token?scope=repository:mm-weber/dhc/$repo:pull" | python3 -c "import json,sys; print(json.load(sys.stdin)['token'])")
  N=$(curl -s -H "Authorization: Bearer $TOK" "https://ghcr.io/v2/mm-weber/dhc/$repo/tags/list" | python3 -c "
import json,sys
d = json.load(sys.stdin)
ts = [t for t in d.get('tags') or [] if not t.startswith('sha256-')]
print(len(ts))")
  echo "$repo: $N catalogue tags"
  TOTAL=$((TOTAL + N))
done
echo "total catalogue tags: $TOTAL"

echo
echo "== S10: packages REST docs deletion endpoints"
curl -s "https://docs.github.com/en/rest/packages/packages?apiVersion=2022-11-28" -o "$SCRATCH/packages_docs.html"
python3 -c "
import re,html
t = open('$SCRATCH/packages_docs.html', encoding='utf-8').read()
t = re.sub('<[^>]+>',' ',t); t = html.unescape(t); t = re.sub(r'\s+',' ',t)
kinds = sorted(set(re.findall(r'Delete (?:a )?package(?: version)? for [a-z ]+', t)))
print('delete endpoint families:', kinds)
print('tag-scoped delete endpoint mentions:', len(re.findall(r'[Dd]elete[^.]{0,40}tag', t)))
"

echo
echo "== S11: tree facts"
echo "-- DHI-style label occurrences outside reviews and ADR history:"
grep -rn "DHI-style\|Images](https://docs.docker.com/dhi/)-style" README.md CLAUDE.md .specs/dhc-catalogue-mvp/requirements.md .specs/dhc-catalogue-mvp/design.md docs/decisions/0001-build-layer.md
echo "-- grype and vexctl locations in the manual and README (file:line only; all are maintainer-side):"
grep -n "grype\|vexctl" docs/user-manual.md README.md | cut -d: -f1,2
echo "-- grype or vexctl inside the consumer verification sections (manual lines 144 to 246, README lines 27 to 45):"
sed -n '144,246p' docs/user-manual.md | grep -n "grype\|vexctl" || echo "(none: no consumer-facing grype or vexctl step exists in the manual recipe)"
sed -n '27,45p' README.md | grep -n "grype\|vexctl" || echo "(none in README verify section)"
echo "-- ADR 0003 on the merge step:"
sed -n '117,118p;142p' docs/decisions/0003-one-openvex-document-per-digest.md
echo "-- posture artifacts absent (expected, tasks open):"
for f in SECURITY.md NOTICE CODEOWNERS .github/rulesets triage/revocations.yaml; do
  [ -e "$f" ] && echo "$f EXISTS" || echo "$f absent"
done
echo "-- LOG-anchor lint in any task or criterion:"
grep -n "anchor" .specs/dhc-catalogue-mvp/tasks.md .specs/dhc-catalogue-mvp/requirements.md || echo "(no task or criterion delivers the F13 LOG-anchor lint)"
echo
echo "done."
