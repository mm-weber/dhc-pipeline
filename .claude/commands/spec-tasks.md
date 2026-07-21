---
description: Generate implementation tasks based on requirements and design
argument-hint: <feature-slug>
allowed-tools: Read, Write, Edit, Glob
---

# Generate Implementation Tasks

You are creating an implementation plan for `.specs/$ARGUMENTS/`

## Context

1. Read `.specs/$ARGUMENTS/requirements.md` to understand WHAT needs to be built
2. Read `.specs/$ARGUMENTS/design.md` to understand HOW it should be built
3. Break down into discrete, implementable tasks

## Your Task

Generate a comprehensive task list following the EXACT Kiro format:

### Tasks Document Structure

```markdown
# Implementation Plan

## Task List

- [ ] 1. [High-level phase/component name]
  - [ ] 1.1 [Specific implementable task]
    - [Detailed action item 1]
    - [Detailed action item 2]
    - [Detailed action item 3]
    - _Requirements: Req 1, Req 2_
  - [ ] 1.2 [Specific implementable task]
    - [Detailed action item 1]
    - [Detailed action item 2]
    - _Requirements: Req 1_

- [ ] 2. [Next high-level phase/component]
  - [ ] 2.1 [Specific implementable task]
    - [Detailed action item 1]
    - [Detailed action item 2]
    - _Requirements: Req 3_
  - [ ] 2.2 [Specific implementable task]
    - [Detailed action item 1]
    - [Detailed action item 2]
    - _Requirements: Req 3, Req 4_

- [ ] 3. [Integration Phase]
  - [ ] 3.1 [Integration task]
    - [Detailed action item]
    - _Requirements: Req 2, Req 4_

- [ ] 4. [Testing Phase]
  - [ ] 4.1 [Unit tests for component X]
    - [Test: Verify behavior A]
    - [Test: Verify behavior B]
    - [Test: Verify error handling]
    - _Requirements: All_
  - [ ] 4.2 [Integration tests]
    - [Test: End-to-end flow A]
    - [Test: End-to-end flow B]
    - _Requirements: All_

## Requirements Coverage

| Requirement | Covered By Tasks |
|-------------|------------------|
| Req 1: [Title] | 1.1, 1.2, 4.1 |
| Req 2: [Title] | 1.1, 3.1, 4.1 |
| Req 3: [Title] | 2.1, 2.2, 4.1 |
| Req 4: [Title] | 2.2, 3.1, 4.2 |
```

## Task Guidelines

### Numbering
- Major phases: `1.`, `2.`, `3.`
- Sub-tasks: `1.1`, `1.2`, `2.1`

### Checkboxes
- Use `- [ ]` for all uncompleted tasks
- Use `- [x]` for completed tasks (only after implementation)

### Granularity
- Each sub-task (X.Y) should be completable in ~30-60 minutes
- If larger, break into more sub-tasks

### Traceability
- Every sub-task MUST have `_Requirements: ..._` footer
- Reference requirement numbers from requirements.md

### Sequencing Order
1. Infrastructure/setup first
2. Data models and database
3. Core business logic
4. API endpoints
5. Frontend components
6. Integration
7. Testing (always last)

## Output

Write the complete task list to `.specs/$ARGUMENTS/tasks.md`

After completion, instruct the user:
- Review the implementation plan
- Provide feedback to adjust task breakdown, OR
- Run `/spec-implement $ARGUMENTS 1.1` to start implementing the first task

## Error Handling

Before proceeding, check:

1. **If `.specs/$ARGUMENTS/` does not exist:**
   - Inform user: "Feature '$ARGUMENTS' not found. Run `/spec-init $ARGUMENTS` first."

2. **If requirements.md does not exist:**
   - Inform user: "Requirements not found. Run `/spec-requirements $ARGUMENTS` first."

3. **If design.md does not exist:**
   - Inform user: "Design document not found. Run `/spec-design $ARGUMENTS` first to create the technical design."
   - Do NOT proceed without design - tasks depend on design decisions

4. **Workflow enforcement:**
   - The correct order is: init -> requirements -> design -> tasks
   - Skipping steps leads to incomplete or incorrect task plans
