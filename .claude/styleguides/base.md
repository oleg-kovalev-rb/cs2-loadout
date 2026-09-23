# Styleguide Template

This file describes the structure and purpose of project styleguides.

It is a reference for `create-styleguide`, `create-styleguide-from-scratch`,
and `styleguides-check`.

Do not copy every section blindly.
Use only sections that provide meaningful project-specific guidance.

If a rule needs more than a few sentences to justify itself (why an
alternative was rejected, what trade-off was made), that justification
belongs in an ADR (`.claude/adr/base.md`), not in the styleguide. A
styleguide states the rule and points to the ADR for the reasoning behind
it — it does not restate that reasoning inline.

Every styleguide starts with a one-line frontmatter `description`, the
same way `SKILL.md` files do. This lets `research-codebase` and
`styleguides-check` judge relevance from the description alone before
opening the full file.

```yaml
---
description: <one line: what this styleguide covers and when it applies>
---
```

---

# <Guideline Name>

## Purpose

Explain what this type of code, pattern, or domain component is responsible for.

Answer:

- What problem does it solve?
- What belongs here?
- What does not belong here?

Keep this section focused on responsibility rather than implementation details.

---

## When to Use

Explain when this pattern should be used.

Also explain when another pattern should be preferred.

This section should help developers decide whether this guideline applies
to a task at all.

---

## Structure

Describe the expected structure of this type of code.

Include project-specific conventions such as:

- file location;
- module/class structure;
- naming;
- organization;
- public entry points.

Do not document generic language syntax.

---

## Interface

Describe the public interface expected from this type of code.

Include:

- public methods;
- arguments;
- return values;
- result objects;
- exceptions;
- callbacks;
- lifecycle expectations.

Only document conventions that are actually relevant to the pattern.

---

## Responsibilities

Describe what this type of code is responsible for.

Also describe responsibilities that must remain in other layers.

Use this section to make architectural boundaries explicit.

---

## Dependencies

Describe what this code may depend on and how dependencies should be handled.

Document rules such as:

- allowed dependencies;
- prohibited dependencies;
- dependency direction;
- dependency injection;
- access to external systems.

---

## Rules

This is the main normative section.

Document concrete project-specific rules.

Rules should be:

- actionable;
- specific;
- enforceable through review or tooling when possible.

Prefer explicit rules such as:

- "Services expose a single `.call` entry point."

over vague rules such as:

- "Keep services clean."

When useful, distinguish:

### MUST

Rules that must always be followed.

### SHOULD

Preferred conventions with reasonable exceptions.

### MUST NOT

Patterns that are prohibited.

---

## Error Handling

Describe how errors and failures should be handled.

Include relevant conventions for:

- expected business failures;
- unexpected failures;
- exceptions;
- retries;
- fallbacks;
- logging;
- error propagation.

Do not include generic error-handling advice unrelated to the project.

---

## Data / Transactions

Use this section when the pattern interacts with persistence or consistency.

Describe:

- transaction boundaries;
- persistence responsibilities;
- locking;
- consistency requirements;
- database access rules.

Omit this section when it is not relevant.

---

## Interaction With Other Layers

Describe how this code interacts with surrounding architectural layers.

For example:

```text
Controller
    ↓
Service
    ↓
Domain / Query
    ↓
Database
```

---

## Testing

Describe how this type of code is tested — only the parts specific to
this pattern. General testing mechanics (spec levels, stubbing rules,
fixtures) belong in a shared testing styleguide (e.g.
`.claude/styleguides/rspec-conventions.md`); cross-reference it instead
of restating it here.

Include, when relevant:

- which test level this pattern is exercised at, and why, if it differs
  from the shared guide's default mapping;
- what must be exercised for real vs. stubbed, specific to this pattern;
- fixtures or helpers unique to this pattern.

Omit this section when the shared testing styleguide already fully
covers this pattern with nothing left to add.

---

## Canonical Implementations

List existing files that best exemplify this pattern today. Point to
them instead of re-explaining what they already show in code.

If no implementation exists yet, say so explicitly rather than omitting
the section — it tells the next plan or styleguide author where the
first one should go.

---

## Related ADR

If an ADR documents the architectural decision behind this pattern, link
it here (`.claude/adr/<app>/<slug>.md`).

Do not duplicate the ADR's reasoning in the styleguide — the styleguide
states the rule, the ADR explains why it was chosen. Omit this section
when no ADR applies.
