---
description: Show status of all specs or a specific spec
argument-hint: "[feature-slug]"
allowed-tools: Read, Glob
---

# Spec Status Report

Show the status of feature specifications.

## Parse Arguments

The arguments are: **$ARGUMENTS**

If empty, show status of ALL specs. Otherwise, show status of the specific feature.

## If Feature Slug Provided

Read and analyze `.specs/<feature-slug>/`:

1. **Check which files exist:**
   - requirements.md
   - design.md
   - tasks.md

2. **If tasks.md exists, calculate progress:**
   - Count total sub-tasks: lines matching `- [ ]` and `- [x]` at sub-task level (X.Y format)
   - Count completed: lines matching `- [x]`
   - Calculate percentage

3. **Determine current phase:**
   - `initialized` - Only empty requirements.md exists
   - `requirements` - requirements.md has content, no design.md
   - `design` - design.md exists, no tasks.md
   - `implementation` - tasks.md exists
   - `completed` - All tasks are `[x]`

4. **Find next task (if in implementation phase):**
   - First line matching `- [ ] X.Y` pattern

5. **Display status:**

```
## Feature: <feature-slug>

### Phase: [current phase]

### Documents
- [x] requirements.md
- [x] design.md
- [ ] tasks.md

### Progress
Tasks: 5/12 completed (42%)

### Next Task
- [ ] 2.3 Implement user validation

### Commands
- Continue: `/spec-implement <feature-slug> 2.3`
- Validate: `/spec-validate <feature-slug>`
```

## If No Feature Slug Provided

1. List all directories in `.specs/`
2. For each directory, calculate brief status
3. Display summary table:

```
## All Specifications

| Feature | Phase | Requirements | Design | Tasks | Progress |
|---------|-------|--------------|--------|-------|----------|
| user-auth | implementation | OK | OK | OK | 8/12 (67%) |
| payment-flow | design | OK | OK | - | - |
| dashboard | requirements | OK | - | - | - |

### Commands
- View details: `/spec-status <feature-slug>`
- Create new: `/spec-init <feature-name>`
```

## Output

Display a formatted status report. Do NOT modify any files.
