#!/usr/bin/env node

/**
 * EARS (Easy Approach to Requirements Syntax) Validator
 *
 * Validates that acceptance criteria in requirements.md follow strict EARS patterns.
 * This is a critical tool for maintaining spec quality in Spec-Driven Development.
 *
 * Usage: node ears-validator.js <path-to-requirements.md>
 */

const fs = require('fs');
const path = require('path');

// Strict EARS patterns - these are the ONLY valid formats
const EARS_PATTERNS = {
  // THE [System] SHALL [behavior]
  ubiquitous: /^THE\s+\S.+\s+SHALL\s+\S.+$/,

  // WHEN [event] THE [System] SHALL [response]
  eventDriven: /^WHEN\s+\S.+\s+THE\s+\S.+\s+SHALL\s+\S.+$/,

  // WHILE [state] THE [System] SHALL [behavior]
  stateDriven: /^WHILE\s+\S.+\s+THE\s+\S.+\s+SHALL\s+\S.+$/,

  // WHERE [feature] THE [System] SHALL [behavior]
  optionalFeature: /^WHERE\s+\S.+\s+THE\s+\S.+\s+SHALL\s+\S.+$/,

  // IF [condition] THEN THE [System] SHALL [response]
  unwantedBehavior: /^IF\s+\S.+\s+THEN\s+THE\s+\S.+\s+SHALL\s+\S.+$/,

  // WHILE [state] WHEN [event] THE [System] SHALL [response]
  complex: /^WHILE\s+\S.+\s+WHEN\s+\S.+\s+THE\s+\S.+\s+SHALL\s+\S.+$/,
};

// Keywords that MUST be uppercase
const STRICT_KEYWORDS = ['WHEN', 'THE', 'SHALL', 'IF', 'THEN', 'WHILE', 'WHERE'];

// Invalid alternatives to SHALL
const INVALID_MODAL_VERBS = ['should', 'must', 'will', 'can', 'may', 'might', 'could', 'would'];

function validateEarsStatement(statement, lineNumber) {
  const trimmed = statement.trim();

  // Check for invalid modal verbs (should, must, will, etc.)
  for (const verb of INVALID_MODAL_VERBS) {
    const verbRegex = new RegExp(`\\b${verb}\\b`, 'i');
    if (verbRegex.test(trimmed)) {
      return {
        line: lineNumber,
        content: trimmed,
        error: `Invalid modal verb "${verb}" - use "SHALL" instead`,
        suggestion: trimmed.replace(new RegExp(`\\b${verb}\\b`, 'gi'), 'SHALL'),
        severity: 'error'
      };
    }
  }

  // Check for lowercase EARS keywords that should be uppercase
  for (const keyword of STRICT_KEYWORDS) {
    const lowerKeyword = keyword.toLowerCase();
    // Match the keyword as a whole word, case-insensitive, but not already uppercase
    const lowerRegex = new RegExp(`\\b${lowerKeyword}\\b`, 'g');
    const upperRegex = new RegExp(`\\b${keyword}\\b`, 'g');

    const lowerMatches = trimmed.match(lowerRegex);
    const upperMatches = trimmed.match(upperRegex);

    if (lowerMatches && (!upperMatches || lowerMatches.length > (upperMatches?.length || 0))) {
      return {
        line: lineNumber,
        content: trimmed,
        error: `Keyword "${lowerKeyword}" must be UPPERCASE "${keyword}"`,
        suggestion: trimmed.replace(new RegExp(`\\b${lowerKeyword}\\b`, 'gi'), keyword),
        severity: 'error'
      };
    }
  }

  // If statement contains SHALL (case-sensitive), validate against patterns
  if (trimmed.includes('SHALL')) {
    const isValidPattern = Object.entries(EARS_PATTERNS).some(([name, pattern]) => {
      return pattern.test(trimmed);
    });

    if (!isValidPattern) {
      return {
        line: lineNumber,
        content: trimmed,
        error: 'Statement does not match any valid EARS pattern',
        suggestion: `Valid patterns:
  - THE [System] SHALL [behavior]
  - WHEN [event] THE [System] SHALL [response]
  - WHILE [state] THE [System] SHALL [behavior]
  - WHERE [feature] THE [System] SHALL [behavior]
  - IF [condition] THEN THE [System] SHALL [response]
  - WHILE [state] WHEN [event] THE [System] SHALL [response]`,
        severity: 'error'
      };
    }
  }

  return null;
}

function extractAcceptanceCriteria(content) {
  const lines = content.split('\n');
  const criteria = [];

  let inAcceptanceCriteria = false;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const lineNumber = i + 1;

    // Detect start of acceptance criteria section
    if (/^#{1,4}\s*Acceptance Criteria/i.test(line)) {
      inAcceptanceCriteria = true;
      continue;
    }

    // Detect end of acceptance criteria section (next heading or requirement)
    if (inAcceptanceCriteria && /^#{1,4}\s*(Requirement|Introduction|##)/i.test(line)) {
      inAcceptanceCriteria = false;
      continue;
    }

    // Extract numbered criteria (1. 2. 3. etc.)
    if (inAcceptanceCriteria) {
      const match = line.match(/^\s*\d+\.\s+(.+)$/);
      if (match) {
        criteria.push({
          line: lineNumber,
          text: match[1].trim()
        });
      }
    }
  }

  return criteria;
}

function validate(filePath) {
  const fullPath = path.resolve(filePath);

  // Check if file exists
  if (!fs.existsSync(fullPath)) {
    console.log(`File not found: ${filePath}`);
    process.exit(1);
  }

  const content = fs.readFileSync(fullPath, 'utf-8');

  // Extract all acceptance criteria
  const criteria = extractAcceptanceCriteria(content);

  if (criteria.length === 0) {
    console.log(`No acceptance criteria found in ${filePath}

Make sure your requirements.md has sections like:

#### Acceptance Criteria

1. WHEN [event] THE [System] SHALL [behavior]
2. IF [condition] THEN THE [System] SHALL [response]`);
    process.exit(1);
  }

  const issues = [];
  let validCount = 0;

  // Validate each criterion
  for (const criterion of criteria) {
    const issue = validateEarsStatement(criterion.text, criterion.line);

    if (issue) {
      issues.push(issue);
    } else if (criterion.text.includes('SHALL')) {
      validCount++;
    } else {
      // Statement doesn't contain SHALL - might be missing it entirely
      issues.push({
        line: criterion.line,
        content: criterion.text,
        error: 'Acceptance criterion missing "SHALL" keyword',
        suggestion: 'Rewrite using EARS pattern: WHEN [event] THE [System] SHALL [behavior]',
        severity: 'error'
      });
    }
  }

  // Format output
  if (issues.length === 0) {
    console.log(`EARS Validation PASSED

**File:** ${filePath}
**Valid Statements:** ${validCount}
**Status:** All acceptance criteria follow valid EARS patterns.

Your requirements are ready for the design phase!
Run \`/spec-design <feature-slug>\` to continue.`);
    process.exit(0);
  } else {
    let output = `EARS Validation FAILED

**File:** ${filePath}
**Valid Statements:** ${validCount}
**Invalid Statements:** ${issues.length}

## Issues Found

`;

    for (const issue of issues) {
      const truncatedContent = issue.content.length > 70
        ? issue.content.substring(0, 70) + '...'
        : issue.content;

      output += `### Line ${issue.line}

**Statement:** \`${truncatedContent}\`

**Error:** ${issue.error}

**Suggestion:** ${issue.suggestion}

---

`;
    }

    output += `
## How to Fix

1. Open the requirements.md file
2. Find each line number listed above
3. Rewrite using valid EARS patterns
4. Run validation again

## Valid EARS Patterns

| Pattern | Syntax |
|---------|--------|
| Ubiquitous | \`THE [System] SHALL [behavior]\` |
| Event-Driven | \`WHEN [event] THE [System] SHALL [response]\` |
| State-Driven | \`WHILE [state] THE [System] SHALL [behavior]\` |
| Optional | \`WHERE [feature] THE [System] SHALL [behavior]\` |
| Error Handling | \`IF [condition] THEN THE [System] SHALL [response]\` |
| Complex | \`WHILE [state] WHEN [event] THE [System] SHALL [response]\` |
`;

    console.log(output);
    process.exit(1);
  }
}

// CLI entry point
const args = process.argv.slice(2);

if (args.length === 0) {
  console.log('Usage: node ears-validator.js <path-to-requirements.md>');
  process.exit(1);
}

validate(args[0]);
