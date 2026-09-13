# Styleguide Template

This file describes the structure and purpose of project styleguides.

It is a reference for `create-styleguide`, `create-styleguide-from-scratch`,
and `styleguides-check`.

Do not copy every section blindly.
Use only sections that provide meaningful project-specific guidance.

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
