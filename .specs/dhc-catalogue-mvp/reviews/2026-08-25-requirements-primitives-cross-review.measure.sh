#!/usr/bin/env bash
# Measurements behind the requirements primitives cross-review, 2026-08-25.
# Run from the worktree root. No network needed.
# Sections:
#   S1  EARS validator over the standing requirements.md (expected: PASSED, 164)
#   S1b EARS validator over the review's 15 proposed replacement criteria
#       (expected: PASSED, 15)
#   S2  numeric cross-reference sweep: which criteria other criteria cite by
#       number (confirms no removal candidate is cited by a surviving criterion)
#   S3  criterion counts per group (expected 19, 26, 12, 9, 8, 60, 10, 2, 18)
#   S4  dash audit of the review file (expected: none)
#   S5  subject facts: branch, head commit, diff stat against main
set -uo pipefail
REQ=.specs/dhc-catalogue-mvp/requirements.md
REVIEW=.specs/dhc-catalogue-mvp/reviews/2026-08-25-requirements-primitives-cross-review.md
SCRATCH="${SCRATCH:-$(mktemp -d)}"
echo "scratch: $SCRATCH"

echo
echo "== S1: EARS validator, standing requirements"
node .claude/skills/ears-notation/scripts/ears-validator.js "$REQ" | grep -E "Valid Statements|PASSED|FAILED"

echo
echo "== S1b: EARS validator, the 15 proposed replacement criteria"
cat > "$SCRATCH/proposals.md" <<'EOF'
# Requirements Document

### Requirement X: Cross-review proposals (scratch)

#### Acceptance Criteria

1. THE Scan Pipeline SHALL enumerate at least once per day every catalogue tag in every catalogue repository together with each digest it references, SHALL scan for findings within that decision aperture every platform manifest of each tag-referenced digest, or that digest itself for a single image manifest, and SHALL apply criteria 2.21 and 2.24 to that enumeration.
2. IF a pushed digest's release-time scan produces no report for one or more of its platform manifests THEN THE CI Pipeline SHALL sign nothing, attest nothing and apply no tag for that digest, and SHALL report that failing scan in that run.
3. THE Catalogue SHALL author every definition in native syntax of its archetype's installed build backend, that backend and its declared alternative being named in its trust-boundary table.
4. WHEN a triage decision concludes accepted risk or upstream transfer THE Triage Process SHALL record a time-boxed exception under triage/accepted-risk/ carrying a treatment, an owner, a decision date, a reference to its reasoning in triage/LOG.md, a justification for why avoidance and remediation were unavailable, an expiry date, and every binary path to which that exception applies.
5. IF an accepted-risk exception omits its treatment, owner, decision date, reasoning reference, unavailability justification, expiry date, or binary paths, or sets an expiry date later than its decision date plus that catalogue policy file's largest ceiling, THEN THE CI Pipeline SHALL fail validation.
6. IF a VEX statement names a product that is not an OCI package URL for an existing image definition, or names a product identifier declaring a repository other than that image definition's published repository, THEN THE CI Pipeline SHALL fail validation.
7. IF a VEX source statement's product identifier carries a version that is not a published tag of any image definition publishing that product's repository, carries no version for a statement recording status fixed, or carries no version beside status notes recording no reason its claim holds for every release, THEN THE CI Pipeline SHALL fail validation.
8. WHEN a VEX document is compiled THE VEX Compiler SHALL set every product identifier in that document to a sha256 digest of an image being scanned, covering, for an image index, that index's digest and every scanned platform manifest digest.
9. THE Catalogue SHALL keep exactly one OpenVEX attestation on every tag-referenced digest and on each of its platform manifests, THE Scan Pipeline reporting each digest or platform manifest carrying more than one as a failure of each scheduled rescan run.
10. WHEN a pull request opens THE CI Pipeline SHALL run yamllint on changed YAML files and SHALL validate schema conformance and pinning conventions of every changed definition file before merge.
11. THE Repository SHALL declare in one committed catalogue policy file every release setting that criteria 2.13, 2.14 and 2.17 name, its public-release state that criterion 2.21 reads, every scheduled workflow's schedule, every platform it admits for publishing, every verification input that criterion 2.23 names, its registry namespace, and its active set of definitions.
12. WHEN a pull request affects an image or chart THE Test Suite SHALL install each affected chart adaptation deploying an active definition's images on a kind cluster in CI.
13. IF an image build fails THEN THE CI Pipeline SHALL publish no artifacts from that run and SHALL report each failing step in that run's checks.
14. WHEN a pull request builds an image THE Scan Gate SHALL scan that image with its declared authoritative consumer and SHALL fail on every uncovered finding in that scan's report.
15. IF a pinned third-party executable has a newer released version THEN THE Renovate Automation SHALL open a pull request updating that pin.
EOF
node .claude/skills/ears-notation/scripts/ears-validator.js "$SCRATCH/proposals.md" | grep -E "Valid Statements|PASSED|FAILED"

echo
echo "== S2: numeric cross-references between criteria"
grep -n "criteri" "$REQ" | grep -oE "criteri(on|a) [0-9]+\.[0-9]+( to [0-9]+\.[0-9]+)?(, [0-9]+\.[0-9]+)*( and [0-9]+\.[0-9]+)?" | sort | uniq -c

echo
echo "== S3: criterion count per group"
awk '/^### Requirement [0-9]+/ {req=$3; sub(":","",req)} /^[0-9]+\. / {count[req]++} END {total=0; for (r=1; r<=9; r++) {printf "Req %s: %d\n", r, count[r]; total+=count[r]}; printf "total: %d\n", total}' "$REQ"

echo
echo "== S4: dash audit of the review file (expect: no output between markers)"
echo "--- begin"
LC_ALL=C grep -nP "\xe2\x80\x94|\xe2\x80\x93" "$REVIEW" || true
echo "--- end"

echo
echo "== S5: subject facts"
git rev-parse --abbrev-ref HEAD
git log --oneline -1
git diff main...HEAD --shortstat
