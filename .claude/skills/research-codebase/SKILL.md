---
name: research-codebase
description: Research the existing codebase and build the context required to safely plan a development task. Use before creating a development plan for any non-trivial task.
---

# Research Codebase

## Purpose

Understand the existing codebase and collect the context required to make a safe and well-grounded development plan.

This skill is for investigation only.

Do not design the final solution.
Do not implement code.
Do not modify application code.

## Core Principles

- Inspect the existing code before making assumptions.
- Prefer project conventions over generic best practices.
- Start from relevant entry points and trace the actual execution flow.
- Look for existing implementations of similar behavior.
- Inspect tests before proposing changes.
- Distinguish observed facts from assumptions.
- Keep the research focused on the requested task.

## Workflow

### 1. Understand the task

Identify:

- requested behavior;
- expected outcome;
- relevant domain or subsystem;
- explicit constraints;
- known out-of-scope areas.

If the task description is ambiguous, resolve ambiguity using the existing codebase whenever possible.

### 2. Find relevant entry points

Identify the most likely files and components involved.

Depending on the task, inspect:

- routes;
- controllers;
- models;
- services;
- query objects;
- jobs;
- serializers;
- API clients;
- views;
- components;
- configuration;
- database schema;
- tests.

Do not inspect the entire repository without a reason.

### 3. Trace the current behavior

Follow the relevant execution path.

Determine:

- where the request or event enters the system;
- how data flows through the system;
- where business logic lives;
- where external systems are called;
- where data is persisted;
- how errors are handled;
- how the final result is returned or consumed.

### 4. Find existing patterns

Search for code solving similar problems.

Identify:

- existing abstractions;
- naming conventions;
- architectural patterns;
- error handling;
- transaction boundaries;
- background job patterns;
- external integration patterns;
- testing patterns.

Prefer existing patterns when they fit the requested behavior.

### 5. Inspect tests

Find tests related to the affected behavior.

Determine:

- what behavior is already guaranteed;
- what edge cases are covered;
- what test types are used;
- what test helpers or shared contexts exist;
- what behavior is currently missing coverage.

### 6. Inspect relevant project documentation

Check:

- `CLAUDE.md`;
- `.claude/styleguides/` (top level — shared across every app);
- `.claude/styleguides/<app>/` for the app(s) the task touches (e.g.
  `fetcher/` for `app_fetcher`, `core/` for `app_core`);
- `.claude/styleguides/fix_me.md` — note if any file the task will touch
  is already listed as a known deviation;
- relevant project documentation;
- existing architectural documentation.

Do not create or modify styleguides during this skill.

### 7. Identify constraints and risks

Look for relevant:

- backwards compatibility concerns;
- data integrity concerns;
- database implications;
- performance concerns;
- concurrency or race conditions;
- external API constraints;
- authentication/authorization concerns;
- error handling requirements;
- existing technical limitations.

## Output

Return a structured research report.

### Task Understanding

Briefly restate the requested behavior in terms of the existing system.

### Relevant Files

For each relevant file:

- path;
- role;
- why it matters.

### Current Architecture

Describe the relevant components and how they interact.

### Current Flow

Describe the execution/data flow step by step.

### Existing Patterns

Describe existing patterns that the eventual implementation should likely follow.

### Existing Tests

Describe relevant tests and what behavior they currently cover.

### Constraints and Risks

List important constraints, risks, and edge cases discovered during research.

### Open Questions

List only questions that cannot reasonably be answered from the codebase and that may affect implementation.

## Completion Criteria

Research is complete when:

- the relevant subsystem is understood;
- the current behavior is understood;
- relevant files have been identified;
- similar implementations have been inspected;
- relevant tests have been inspected;
- important constraints and risks are known.

Do not implement the task as part of this skill.
