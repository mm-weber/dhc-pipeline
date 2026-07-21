---
description: Validate spec documents for EARS syntax compliance
argument-hint: <feature-slug>
allowed-tools: Read, Bash, Glob
---

# Validate Specification

Validate the specification at `.specs/$ARGUMENTS/` for correctness and EARS compliance.

## Validation Rules

### 1. EARS Syntax Validation (STRICT - NO EXCEPTIONS)

Every acceptance criterion in requirements.md MUST match one of these EXACT patterns:

| Pattern | Regex | Example |
|---------|-------|---------|
| Ubiquitous | `^THE .+ SHALL .+$` | THE System SHALL encrypt passwords |
| Event-Driven | `^WHEN .+ THE .+ SHALL .+$` | WHEN user logs in THE System SHALL create session |
| State-Driven | `^WHILE .+ THE .+ SHALL .+$` | WHILE user is authenticated THE System SHALL show dashboard |
| Optional | `^WHERE .+ THE .+ SHALL .+$` | WHERE 2FA is enabled THE System SHALL require code |
| Unwanted | `^IF .+ THEN THE .+ SHALL .+$` | IF password is wrong THEN THE System SHALL show error |
| Complex | `^WHILE .+ WHEN .+ THE .+ SHALL .+$` | WHILE logged in WHEN timeout occurs THE System SHALL logout |

**Strict Rules:**
- Keywords MUST be UPPERCASE: WHEN, THE, SHALL, IF, THEN, WHILE, WHERE
- Using "should", "must", "will" instead of "SHALL" is INVALID
- Using lowercase "the system" instead of "THE [System]" is INVALID

### 2. Requirements Structure Validation

Each requirement MUST have:
- A numbered title (e.g., "### Requirement 1: [Title]")
- An Objective with: role, feature, benefit ("As a [role], I want [feature], so that [benefit]")
- At least one acceptance criterion under "#### Acceptance Criteria"

### 3. Task Coverage Validation (if tasks.md exists)

- Every requirement MUST be referenced in at least one task
- Check `_Requirements: ..._` links in tasks.md
- Report any requirements not covered by tasks

### 4. Design Completeness Validation (if design.md exists)

Required sections:
- Overview (with Purpose, Users, Impact)
- Architecture (with at least one Mermaid diagram)
- Components and Interfaces
- Data Models

## Validation Process

1. Read `.specs/$ARGUMENTS/requirements.md`
2. Extract all acceptance criteria (numbered items under "Acceptance Criteria")
3. Validate each criterion against EARS patterns
4. Check requirements structure
5. If design.md exists, validate completeness
6. If tasks.md exists, validate coverage

## Output Format

```markdown
# Validation Report: <feature-slug>

## EARS Syntax Validation

### Result: [PASSED/FAILED]

**Valid Statements:** X
**Invalid Statements:** Y

### Issues (if any)

#### Line [N]: Invalid EARS Syntax
**Content:** `[the invalid statement]`
**Error:** [specific error]
**Fix:** [how to fix it]

---

## Requirements Structure

### Result: [PASSED/FAILED]

- [OK/-] All requirements have titles
- [OK/-] All requirements have objectives
- [OK/-] All requirements have acceptance criteria

---

## Task Coverage (if tasks.md exists)

### Result: [PASSED/FAILED]

| Requirement | Covered | Tasks |
|-------------|---------|-------|
| Req 1 | OK | 1.1, 2.1 |
| Req 2 | - | - |

---

## Design Completeness (if design.md exists)

### Result: [PASSED/FAILED]

- [OK/-] Overview section
- [OK/-] Architecture diagram
- [OK/-] Components section
- [OK/-] Data Models section

---

## Summary

**Overall Status:** [PASSED/FAILED]
**Total Issues:** X errors, Y warnings

### Required Actions
1. [Action to fix issue 1]
2. [Action to fix issue 2]
```

## Important

- Be STRICT about EARS syntax - REJECT any non-conforming statements
- Report EXACT line numbers for issues
- Provide SPECIFIC fix suggestions
- Do NOT modify any files - only report
