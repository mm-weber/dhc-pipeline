---
description: Generate or update technical design based on requirements
argument-hint: <feature-slug>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Generate Technical Design

You are creating a technical design document for `.specs/$ARGUMENTS/`

## Context

1. Read `.specs/$ARGUMENTS/requirements.md` to understand what needs to be built
2. Analyze the existing codebase to understand patterns and conventions
3. Design a solution that fits the existing architecture

## Your Task

Generate a comprehensive design document following the EXACT Kiro format:

### Design Document Structure

```markdown
# Technical Design Document

## Overview

**Purpose**: [What this feature delivers and to whom]

**Users**: [Who will use this feature and how]

**Impact**: [Effect on overall system/product]

### Goals
- [Primary goal 1]
- [Primary goal 2]
- [Primary goal 3]

### Non-Goals
- [Explicitly out of scope 1]
- [Explicitly out of scope 2]

## Architecture

### High-Level Architecture

\`\`\`mermaid
graph TB
    subgraph [Layer Name]
        Component1[Component]
        Component2[Component]
    end

    Component1 --> Component2
\`\`\`

### Technology Stack

| Layer | Technology | Rationale |
|-------|------------|-----------|
| Frontend | [Tech] | [Why] |
| Backend | [Tech] | [Why] |
| Database | [Tech] | [Why] |

### Key Design Decisions

1. **[Decision Title]**
   - **Context**: [Why this decision was needed]
   - **Options Considered**: [Alternatives evaluated]
   - **Decision**: [What was chosen]
   - **Rationale**: [Why this option]
   - **Trade-offs**: [Acknowledged downsides]

## System Flows

### [Primary Flow Name]

\`\`\`mermaid
sequenceDiagram
    participant User
    participant Frontend
    participant API
    participant Database

    User->>Frontend: Action
    Frontend->>API: Request
    API->>Database: Query
    Database-->>API: Result
    API-->>Frontend: Response
    Frontend-->>User: Display
\`\`\`

## Components and Interfaces

### [Component Name]

**Responsibility**: [What this component does]

**Interface**:
\`\`\`typescript
interface ComponentName {
  methodName(param: Type): Promise<ReturnType>;
}
\`\`\`

**Dependencies**:
- Inbound: [What calls this]
- Outbound: [What this calls]

## Data Models

### [Entity Name]

\`\`\`typescript
interface EntityName {
  id: string;
  field1: Type;
  field2: Type;
  createdAt: Date;
  updatedAt: Date;
}
\`\`\`

### Database Schema

\`\`\`sql
CREATE TABLE table_name (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  field_name VARCHAR(255) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_field ON table_name(field_name);
\`\`\`

## Error Handling

### Error Categories

| Category | HTTP Status | User Message | Recovery |
|----------|-------------|--------------|----------|
| Validation | 400 | [Message] | [Action] |
| Auth | 401/403 | [Message] | [Action] |
| Not Found | 404 | [Message] | [Action] |
| Server | 500 | [Message] | [Action] |

## Testing Strategy

### Unit Tests
- [What to unit test]

### Integration Tests
- [What to integration test]

### E2E Tests
- [End-to-end scenarios]

## Security Considerations

- [Security measure 1]
- [Security measure 2]
```

## Important

- Include Mermaid diagrams for architecture and flows
- Reference requirements when explaining design decisions
- Analyze existing code patterns and follow them
- Be specific about interfaces and data models

## Output

Write the complete design to `.specs/$ARGUMENTS/design.md`

After completion, instruct the user:
- Review the design document
- Click "Preview" to see rendered Mermaid diagrams
- Provide feedback to iterate, OR
- Run `/spec-tasks $ARGUMENTS` to proceed to task planning

## Error Handling

Before proceeding, check:

1. **If `.specs/$ARGUMENTS/` does not exist:**
   - Inform user: "Feature '$ARGUMENTS' not found. Run `/spec-init $ARGUMENTS` first."
   - List existing features in `.specs/`

2. **If requirements.md does not exist or is empty:**
   - Inform user: "Requirements not found. Run `/spec-requirements $ARGUMENTS` first to generate requirements."
   - Do NOT proceed without requirements

3. **If requirements.md lacks EARS criteria:**
   - Warn user: "Requirements may be incomplete - no EARS acceptance criteria found."
   - Suggest running `/spec-validate $ARGUMENTS` first
