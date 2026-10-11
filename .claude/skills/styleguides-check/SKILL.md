---
name: styleguides-check
description: Check a development plan against project styleguides. Identify all required styleguides, report missing or incomplete ones, and finalize the development plan only after all required styleguides are available.
---

# Styleguides Check

## Purpose

Review a development plan against the project's styleguides and engineering conventions.

This skill acts as a gate between planning and implementation.

Its responsibility is to:

1. determine which styleguides are required for the planned work;
2. verify that those styleguides exist and contain sufficient guidance;
3. report all missing or insufficient styleguides;
4. wait for the styleguides to be added or completed;
5. re-check the plan against the completed styleguides;
6. finalize the development plan with the required technical constraints.

The implementation must not begin until this process is complete.

## Core Principles

- The development plan defines **what** should be built.
- Styleguides define **how** it should be built.
- Do not change the intended behavior of the development plan during this skill.
- Prefer project-specific conventions over generic best practices.
- Do not invent styleguides that are not relevant to the planned implementation.
- Do not consider the check complete while a required styleguide is missing or insufficient.
- The final development plan must explicitly reference all applicable styleguides and technical constraints.
- Updating the plan file's `status` frontmatter field and its `Missing
  Styleguides`/`Applicable Styleguides` sections is the exclusive
  responsibility of this skill — `create-styleguide`,
  `create-styleguide-from-scratch`, and `update-styleguide` only produce or
  amend and get user approval for the styleguide/ADR artifacts; they must
  not modify the plan file.

## Workflow

### 1. Read the development plan

Read the plan from its file at `.claude/plans/<slug>.md` (produced by
`create-dev-plan`) rather than relying on conversation history — the plan
may have been approved in an earlier session.

Understand:

- goal;
- expected behavior;
- scope;
- implementation approach;
- affected files and components;
- test strategy;
- risks.

Do not redesign the plan.

### 2. Inspect the styleguide directories

Styleguides live under `.claude/styleguides/`, split by scope:

- `.claude/styleguides/` (top level, not in a subfolder) — conventions
  shared across every app (Ruby style, git conventions, cross-app
  Rails/testing conventions);
- `.claude/styleguides/<app>/` — conventions local to that app's domain
  (`fetcher/` for `app_fetcher`, `core/` for `app_core`).

Inspect the shared level plus the subfolder(s) for whichever app(s) the plan
touches. If a rule appears both shared and in an app subfolder with
conflicting guidance, the app-local styleguide wins for work in that app.

Before opening a file's full body, read its frontmatter `description`
line to judge relevance — open the full file only for the ones that look
applicable to the plan. This is a filter, not the sufficiency
determination itself: a description ruling a file out is enough to skip
it, but confirming a file is sufficient (step 3) still requires reading
its body.

Determine which existing styleguides are relevant to the planned implementation.

Consider areas such as:

- Ruby;
- Rails;
- architecture;
- testing;
- database;
- APIs;
- background jobs;
- performance;
- security;
- frontend;
- integrations.

Only select styleguides that affect the planned work.

### 3. Determine required styleguides

For every relevant technical area, determine whether a sufficiently detailed styleguide exists.

A styleguide is sufficient only when it contains enough project-specific guidance to make the required implementation decisions consistently.

Do not treat generic or unrelated documentation as sufficient guidance.

### 4. Identify missing or insufficient styleguides

For every gap found, classify it as one of two kinds — they get resolved by
different skills in step 6:

- **Missing**: no styleguide file exists yet for this technical area.
- **Insufficient**: a styleguide file exists and already applies to this
  area, but it is empty, too vague, outdated for the planned
  implementation, or missing a critical rule the plan needs — e.g. the plan
  hits a specific case the guide's current rules don't address.

Do not create or amend them automatically during this step.

The purpose of this step is to identify what is required before implementation can proceed.

### 5. Stop if styleguides are missing

If any required styleguides are missing or insufficient:

- do not finalize the development plan;
- do not mark the styleguide check as complete;
- do not proceed to implementation.

Output a `Missing Styleguides` section containing, for every missing or insufficient styleguide:

- expected file path;
- whether it's missing or insufficient (per the classification in step 4) —
  this determines which skill resolves it in step 6;
- for insufficient guides, which existing section it falls under and what
  specifically the guide fails to cover;
- reason it is required;
- topics it must cover;
- which part of the development plan depends on it.

Example:

```md
## Missing Styleguides

### `.claude/styleguides/fetcher/background-jobs.md`

Status: missing.

Required because the plan introduces a new background job.

Must define:

- job responsibilities;
- idempotency requirements;
- retry behavior;
- error handling;
- database transaction rules;
- testing conventions.

### `.claude/styleguides/fetcher/rate-limiting.md`

Status: insufficient — exists and already applies, but its "Backoff"
section doesn't cover exponential backoff on `429` responses, which the
plan's retry logic depends on.

Required because the plan adds a call path that can be rate-limited.
```

Write this `Missing Styleguides` section into the plan file itself (see
step 8), and set the plan's `status` frontmatter field to `blocked`. This
makes the blocked state visible to anyone (or any future session) opening
the plan file, not just visible in this conversation.

### 6. Wait for styleguides to be created or updated

Do not create or amend the flagged styleguides yourself as part of this
skill:

- for guides classified **missing**, that belongs to `create-styleguide` or
  `create-styleguide-from-scratch`;
- for guides classified **insufficient** (they already exist and already
  apply, but don't cover something the plan needs), that belongs to
  `update-styleguide`.

Those skills only produce or amend the styleguide (and ADR, when
applicable) and wait for user approval — they do not touch the plan file.
Updating it happens only in step 8 below, and only by this skill.

Resume this skill only after the missing or insufficient styleguides have
been created, amended, and approved by the user.

### 7. Re-check the plan

Once the flagged styleguides have been created or amended, repeat steps 2-4
against the updated styleguide set.

If any styleguide is still missing or insufficient, return to step 5.

### 8. Finalize the plan

Once every required styleguide exists and is sufficient:

- update the plan file at `.claude/plans/<slug>.md` in place;
- remove any `Missing Styleguides` section;
- add an `Applicable Styleguides` section listing, for each styleguide that
  applies:
  - path;
  - which part of the plan it constrains;
- set the plan's `status` frontmatter field to `styleguide-checked`.

The plan file is now ready for `implement-plan`.

## Output

Return the finalized (or blocked) plan.

If blocked, return:

## Missing Styleguides

(as defined in step 5, also persisted to the plan file)

If finalized, return:

## Applicable Styleguides

For each styleguide that applies to the plan:

- path;
- which part of the plan it constrains.

## Completion Criteria

The styleguide check is complete only when:

- every technical area touched by the plan has a sufficient, project-specific
  styleguide;
- the plan file's `Applicable Styleguides` section is populated;
- the plan file's `status` frontmatter field is `styleguide-checked`;
- no `Missing Styleguides` section remains.

Do not implement the task as part of this skill.
