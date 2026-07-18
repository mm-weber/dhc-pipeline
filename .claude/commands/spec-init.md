---
description: Initialize a new feature specification
argument-hint: <feature-name>
allowed-tools: Bash, Write
---

# Initialize Feature Specification

You are initializing a new spec-driven development workflow for the feature: **$ARGUMENTS**

## Your Task

1. Create the feature slug from the name (kebab-case, lowercase)
   - Example: "User Authentication" -> "user-authentication"
   - Example: "Payment Flow" -> "payment-flow"

2. Create the directory `.specs/<feature-slug>/`

3. Create an initial `requirements.md` with this exact template:

```markdown
# Requirements Document

## Introduction

[Brief description of the feature will be added during requirements phase]

## Requirements

[Requirements will be generated in the next phase]
```

4. Confirm the initialization was successful

5. Instruct the user to run `/spec-requirements <feature-slug>` to continue

## Important

- Feature slug must be kebab-case (e.g., "User Authentication" -> "user-authentication")
- Only create the directory and initial requirements.md file
- Do NOT generate actual requirements yet - that happens in the next phase
- If the directory already exists, inform the user and ask if they want to overwrite
