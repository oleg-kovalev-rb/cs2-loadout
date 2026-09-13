---
name: create-styleguide
description: Create a styleguide for an existing code pattern by extracting conventions from the codebase.
---

# Create Styleguide

Create a project-specific styleguide for an existing code pattern.

Use `.claude/styleguides/base.md` as the format reference.

## Workflow

1. Identify the scope of the styleguide.
2. Find and inspect several representative implementations.
3. Inspect their tests and related code.
4. Identify recurring conventions, boundaries, and anti-patterns.
   - If a representative implementation deviates from the convention
     followed by the others, do not fold the deviation in as an
     alternative and do not fix it inline — extract the rule from the
     conforming majority, then log the deviating file in
     `.claude/styleguides/fix_me.md` under the relevant scope (see that
     file for the format).
5. Check existing styleguides — both `.claude/styleguides/` (shared) and
   `.claude/styleguides/<app>/` (e.g. `fetcher/`, `core/`) — for overlap or
   conflicts.
6. Extract only established, project-specific rules.
7. Decide where the styleguide belongs:
   - `.claude/styleguides/` (top level), if the rule applies identically to
     every app (e.g. Ruby style, git conventions, generic Rails/testing
     conventions shared across apps);
   - `.claude/styleguides/<app>/`, if the rule is specific to that app's
     domain (e.g. `fetcher/` for Steam ingestion/parsing/jobs, `core/` for
     the dashboard/React island — nothing with an equivalent in the other
     app).
   If unsure, default to the app-specific folder — it's easier to promote a
   proven local rule to shared later than to walk back a shared rule that
   turns out to be app-only.
8. Create the styleguide in the chosen location using
   `.claude/styleguides/base.md` as the format.
9. Add references to canonical implementations.
10. Validate the guide against the codebase.

Do not invent conventions that are not supported by the existing code.

If there is not enough existing code to derive reliable conventions, do not
create the guide. Use `create-styleguide-from-scratch` instead.

## ADR

After understanding the pattern, determine whether the styleguide captures a
meaningful architectural decision.

An ADR is usually unnecessary for ordinary implementation conventions.

An ADR may be appropriate when the guide documents:

- an architectural boundary;
- a dependency rule;
- a significant design pattern;
- a choice between meaningful alternatives;
- an intentional long-term constraint.

If an ADR may be appropriate:

1. Explain why.
2. Ask the user whether an ADR should be created.
3. Create it only after approval, under `.claude/adr/<app>/` for the app the
   decision belongs to (ADRs are always app-specific, never shared).
4. Use `.claude/adr/base.md` as the format reference.

## Result

The task is complete when:

- the styleguide is created in the correct location (shared vs `<app>/`);
- its rules are grounded in existing code;
- canonical examples are included;
- related styleguides were checked;
- any deviating files found along the way are logged in
  `.claude/styleguides/fix_me.md`, not fixed inline;
- ADR handling is resolved when applicable.
