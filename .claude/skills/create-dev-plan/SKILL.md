---
name: create-dev-plan
description: Create a concrete development plan from codebase research. Define the intended behavior, scope, implementation approach, tests, and execution steps without performing implementation or styleguide analysis.
---

# Create Development Plan

## Purpose

Turn codebase research into a concrete, implementation-ready development plan.

This skill defines what should be built and how the work should be structured.

It does not implement the task.
It does not create or select styleguides.

## Preconditions

Before using this skill:

- codebase research must be available;
- the current implementation must be understood;
- relevant existing patterns must have been inspected;
- relevant tests must have been inspected.

If research is incomplete, do not invent missing context.

## Core Principles

- Build the plan from the actual codebase.
- Prefer the smallest change that fully satisfies the requirement.
- Reuse existing architecture where appropriate.
- Avoid speculative refactoring.
- Keep the plan focused on the requested behavior.
- Include testing as part of the implementation plan.
- Make implementation steps concrete enough to execute without redesigning the task.
- Do not introduce technical rules that belong in styleguides-check.

## Workflow

### 1. Define the goal

Describe the intended result in one clear statement.

### 2. Define expected behavior

Translate the task into observable behavior.

Include:

- normal behavior;
- relevant edge cases;
- failure behavior;
- behavior that must remain unchanged.

Focus on what the system should do, not on coding conventions.

### 3. Define scope

Explicitly identify:

- what is in scope;
- what is out of scope.

Avoid adding unrelated cleanup or refactoring.

### 4. Define the implementation approach

Based on the research, determine:

- which existing components should change;
- which new components are actually required;
- how the components should interact;
- where the new behavior should live.

Reuse existing architecture whenever possible.

### 5. Define the test strategy

Describe what behavior needs to be verified.

Identify:

- test locations;
- test types;
- important scenarios;
- edge cases;
- regression coverage.

Tests are part of the implementation plan, not a separate follow-up task.

### 6. Define implementation steps

Create a sequential plan.

Each step should explain:

- what needs to change;
- where it needs to change;
- why it is needed.

Do not write implementation code.

### 7. Define verification

Specify what should be verified after implementation.

Examples:

- relevant test suite;
- broader test suite;
- linter;
- formatter;
- integration checks;
- manual verification where necessary.

### 8. Persist the plan

Write the plan to a file so it survives past this conversation:

- path: `.claude/plans/<slug>.md`, where `<slug>` is a short kebab-case
  summary of the goal (e.g. `add-price-history-endpoint.md`);
- if a plan file for this task already exists, update it in place rather
  than creating a duplicate;
- prepend frontmatter:

  ```yaml
  ---
  status: draft
  app: fetcher | core | fetcher+core
  goal: <one-line goal>
  created: <today's date>
  ---
  ```

- follow it with the plan body (see `Output` below).

`.claude/plans/` is committed to the repo, so a plan stays visible across
sessions and to the rest of the team. Once a task is implemented, the
durable record still lives primarily in the code, tests, commit message,
and any styleguide/ADR produced along the way — the plan file is a
working artifact of how that record came to be, not a replacement for it.

Report the file path back to the user.

## Output

Return a development plan using this structure:

# Development Plan

## Goal

What the task should accomplish.

## Expected Behavior

Observable behavior that must exist after implementation.

## Scope

### In Scope

...

### Out of Scope

...

## Implementation Approach

High-level technical approach based on the researched codebase.

## Files To Modify

For each file:

- path;
- planned change;
- reason.

## Files To Create

For each new file:

- path;
- responsibility;
- reason it is necessary.

## Test Plan

Describe tests that should be written or changed.

## Implementation Steps

A sequential implementation plan.

## Verification

Checks that should be run after implementation.

## Risks

Known implementation risks discovered during planning.

## Assumptions

Only assumptions that could not be verified from the codebase.

## Completion Criteria

The plan is complete when:

- the desired behavior is explicit;
- scope is explicit;
- affected files/components are identified;
- test strategy is defined;
- implementation steps are ordered;
- verification is defined;
- the plan has been written to `.claude/plans/<slug>.md`.

Do not implement the task as part of this skill.
