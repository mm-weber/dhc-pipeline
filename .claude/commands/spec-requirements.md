---
description: Generate or update requirements with EARS notation
argument-hint: <feature-slug>
allowed-tools: Read, Write, Edit, Glob, Grep
---

# Generate Requirements

You are generating structured requirements for the feature specification at `.specs/$ARGUMENTS/`

## Context

First, read the existing `.specs/$ARGUMENTS/requirements.md` file if it exists to understand the current state.

If this is a fresh spec, ask the user to describe what they want to build.

## Your Task

Generate comprehensive requirements following the EXACT Kiro format:

### Requirements Document Structure

```markdown
# Requirements Document

## Introduction

[2-3 sentences describing the feature, its purpose, and the problem it solves]

## Requirements

### Requirement 1: [Descriptive Title]

**Objective:** As a [user role], I want [feature/capability], so that [benefit/value]

#### Acceptance Criteria

1. WHEN [trigger event] THE [System] SHALL [expected behavior]
2. IF [condition] THEN THE [System] SHALL [expected behavior]
3. WHILE [ongoing state] THE [System] SHALL [continuous behavior]
4. WHERE [context/feature present] THE [System] SHALL [behavior]
5. IF [error/edge case] THEN THE [System] SHALL [error handling]

### Requirement 2: [Descriptive Title]

**Objective:** As a [user role], I want [feature/capability], so that [benefit/value]

#### Acceptance Criteria

1. WHEN ... THE [System] SHALL ...
[continue pattern]
```

## EARS Notation Rules (STRICT)

You MUST use these exact patterns. No variations allowed:

| Pattern | Syntax | When to Use |
|---------|--------|-------------|
| **Ubiquitous** | `THE [System] SHALL [behavior]` | Always-true requirements |
| **Event-Driven** | `WHEN [event] THE [System] SHALL [response]` | Triggered behaviors |
| **State-Driven** | `WHILE [state] THE [System] SHALL [behavior]` | Ongoing conditions |
| **Optional Feature** | `WHERE [feature] THE [System] SHALL [behavior]` | Feature-dependent |
| **Unwanted Behavior** | `IF [condition] THEN THE [System] SHALL [response]` | Error handling, edge cases |
| **Complex** | `WHILE [state] WHEN [event] THE [System] SHALL [response]` | Multi-condition |

## Strict Validation Rules

1. Keywords MUST be UPPERCASE: WHEN, THE, SHALL, IF, THEN, WHILE, WHERE
2. NEVER use "should", "must", "will" - ONLY use "SHALL"
3. NEVER use "the system" lowercase - ALWAYS "THE [System]"
4. Every criterion must be specific and testable
5. Cover error cases and edge cases with IF/THEN patterns

## Output

Write the complete requirements to `.specs/$ARGUMENTS/requirements.md`

After completion, instruct the user:
- Review the requirements carefully
- Provide feedback to iterate, OR
- Run `/spec-design $ARGUMENTS` to proceed to design phase

## Error Handling

Before proceeding, check:

1. **If `.specs/` directory does not exist:**
   - Inform user: "No specs directory found. Run `/spec-init <feature-name>` first to create a new feature specification."

2. **If `.specs/$ARGUMENTS/` does not exist:**
   - Inform user: "Feature '$ARGUMENTS' not found. Run `/spec-init $ARGUMENTS` to create it, or check the feature slug."
   - List existing features: Show directories in `.specs/`

3. **If requirements.md is empty (only template):**
   - Ask user to describe what they want to build
   - Do NOT proceed without user input
