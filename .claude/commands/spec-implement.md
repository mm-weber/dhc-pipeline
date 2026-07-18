---
description: Implement a specific task from the spec
argument-hint: <feature-slug> [task-id]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Implement Spec Task

You are implementing a task from the specification.

## Parse Arguments

The arguments are: **$ARGUMENTS**

Extract:
- First word = feature-slug (e.g., "user-auth")
- Second word (optional) = task-id (e.g., "1.1", "2.3")

## Context

1. Read `.specs/<feature-slug>/requirements.md` for acceptance criteria
2. Read `.specs/<feature-slug>/design.md` for technical approach
3. Read `.specs/<feature-slug>/tasks.md` to find the task

## Your Task

1. Locate the task with the specified ID in tasks.md (e.g., "1.1", "2.3")
2. Read the task details including:
   - The detailed action items
   - The linked requirements (`_Requirements: ..._`)
3. Look up the linked requirements in requirements.md for acceptance criteria
4. Implement the task following the design document
5. After successful implementation, update tasks.md:
   - Change `- [ ] X.Y` to `- [x] X.Y`

## Implementation Guidelines

- Follow existing code patterns in the codebase
- Implement according to the design.md specifications
- Ensure acceptance criteria from requirements.md are met
- Write tests if specified in the task
- Use the interfaces and data models from design.md

## After Implementation

1. Mark the task as complete in tasks.md: `- [x] X.Y [Task Title]`
2. Report what was implemented:
   - Files created/modified
   - Key decisions made
   - Any deviations from design (with justification)
3. Suggest the next task to implement

## If No Task ID Provided

If no task ID is provided:
1. Read `.specs/<feature-slug>/tasks.md`
2. Find the first incomplete task (first `- [ ]` at the sub-task level like `1.1`, `2.1`)
3. Implement that task
4. Mark it as complete

## Example Usage

- `/spec-implement user-auth 1.1` - Implement task 1.1 of user-auth spec
- `/spec-implement user-auth` - Implement next incomplete task
