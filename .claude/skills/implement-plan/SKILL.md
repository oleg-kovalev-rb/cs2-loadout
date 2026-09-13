---
name: implement-plan
description: Implement an approved and styleguide-checked development plan using TDD, following all applicable project guidelines and verifying the final result.
---

# Implement Development Plan

## Purpose

Implement the completed development plan.

The plan has already passed:

1. codebase research;
2. development planning;
3. styleguide checking.

This skill is responsible for implementation, TDD, refactoring, and verification.

## Preconditions

Before implementation:

- a development plan exists at `.claude/plans/<slug>.md`;
- the plan file's `status` frontmatter field is `styleguide-checked`;
- applicable styleguides are identified in the plan's `Applicable
  Styleguides` section;
- required missing styleguides have been created;
- implementation scope is clear.

Do not skip directly to implementation when the required plan or styleguides are missing.

If no plan path is known, ask for it or locate it under `.claude/plans/`
before proceeding — do not implement from a plan recalled only from
conversation memory, since this skill may run in a session that never saw
the planning stages.

## Core Principles

- Follow the implementation plan.
- Read and follow all applicable styleguides.
- Follow existing project patterns.
- Implement the smallest solution that satisfies the plan.
- Avoid unrelated refactoring.
- Do not introduce speculative abstractions.
- Do not add dependencies unless explicitly approved.
- Use TDD for new or changed behavior.
- Keep the test suite green throughout the implementation.

## Implementation Workflow

### 1. Validate the plan

Before changing code:

- read the complete implementation plan from `.claude/plans/<slug>.md` on
  disk (not from conversation history — it may predate this session);
- confirm `status` is `styleguide-checked`; if it is `draft` or `blocked`,
  stop and return to `create-dev-plan` or `styleguides-check` instead of
  proceeding;
- read every applicable styleguide listed in the plan's `Applicable
  Styleguides` section;
- verify that the planned files and components still match the current codebase;
- identify any contradiction between the plan and the actual code.

Do not silently resolve major contradictions.

If implementation reveals that the plan is materially incorrect:

1. stop implementation;
2. explain what was discovered;
3. revise the plan through the appropriate planning stage;
4. continue only after the plan is consistent again.

### 2. Work in small increments

Implement the plan step by step.

Keep each change focused and easy to verify.

Do not batch unrelated changes together.

Before editing a file, check whether it is listed in
`.claude/styleguides/fix_me.md`. If it is, and bringing it into
compliance is small and within a styleguide already applicable to this
change, fix it as part of the same change and remove its entry. Do not
expand scope to fix an unrelated flagged file just because it happens to
be listed.

## TDD Workflow

For every new or changed behavior:

### RED

Write a test that expresses the desired behavior.

Run the test.

Verify that:

- the test fails;
- it fails for the expected reason;
- the failure demonstrates the missing or incorrect behavior.

Do not proceed if the test fails for an unrelated reason.

### GREEN

Implement the minimum code required to make the test pass.

Run the test again.

Verify that it passes.

### REFACTOR

Improve the implementation while preserving the tested behavior.

Possible refactoring includes:

- removing duplication;
- improving naming;
- simplifying control flow;
- extracting a responsibility when justified;
- aligning the implementation with project conventions.

Run the relevant tests after refactoring.

## Test Rules

- Prefer behavior-focused tests.
- Follow the project's existing test structure.
- Reuse existing helpers and factories where appropriate.
- Add regression tests for bug fixes.
- Cover relevant edge cases.
- Keep assertions meaningful.
- Do not weaken tests to make implementation pass.
- Do not remove existing tests without a clear reason.
- Do not skip tests without documenting why.

## Code Rules

- Follow applicable styleguides.
- Reuse existing abstractions where appropriate.
- Keep responsibilities clear.
- Avoid unnecessary complexity.
- Avoid unrelated cleanup.
- Modify only files required by the plan unless an additional change is strictly necessary.
- Preserve existing behavior outside the requested scope.

## Verification

After implementation:

### Relevant Tests

Run tests directly related to the changes.

### Broader Tests

Run the broader relevant test suite when practical.

### Static Checks

Run the project's relevant:

- linter;
- formatter;
- type checker;
- static analysis.

### Final Diff Review

Inspect the complete diff.

Verify:

- only intended files changed;
- no debug code remains;
- no accidental changes were introduced;
- the implementation matches the final plan;
- applicable styleguides were followed.

### Persist the outcome

Update the plan file at `.claude/plans/<slug>.md`:

- set the `status` frontmatter field to `implemented`;
- append the `Implementation Summary` (see `Output` below) to the end of
  the file.

The plan file now doubles as a record of what was actually done, in case
the summary is needed after this conversation ends.

## Handling Unexpected Discoveries

If implementation reveals:

- a missing requirement;
- an incorrect assumption;
- an architectural conflict;
- a missing styleguide;
- a need for a materially different implementation;

do not silently improvise.

Stop and report the discovery.

Return to the appropriate earlier stage:

- codebase misunderstanding → `research-codebase`;
- behavior or implementation plan issue → `create-dev-plan`;
- missing or incorrect engineering guidance → `styleguides-check`.

Resume implementation only after the plan is consistent again. When
stopping, set the plan file's `status` frontmatter field back to `draft`
(if returning to `create-dev-plan`) or `blocked` (if returning to
`styleguides-check`) so the plan file doesn't misrepresent the plan as
still ready for implementation.

## Completion Criteria

The task is complete only when:

- all planned behavior is implemented;
- TDD was followed for new or changed behavior;
- relevant tests pass;
- relevant static checks pass;
- the final diff is focused;
- applicable styleguides are satisfied;
- the plan file's `status` is `implemented` and its `Implementation
  Summary` is appended;
- no known blocking issue remains.

## Output

Return:

# Implementation Summary

## Implemented

What was changed.

## Tests

Tests added or changed.

List the commands that were actually executed.

## Verification

Results of tests, linters, formatters, and other checks.

Do not claim a check passed unless it was actually executed successfully.

## Deviations

Describe any deviation from the implementation plan and why it was necessary.

## Remaining Issues

List any unresolved issues or follow-up work that is genuinely required.
