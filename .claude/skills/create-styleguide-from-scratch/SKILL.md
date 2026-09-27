---
name: create-styleguide-from-scratch
description: Create a new styleguide for a code pattern that does not yet exist in the codebase, together with an ADR documenting the architectural decision.
---

# Create Styleguide From Scratch

Create a new project-specific engineering pattern when no sufficient existing
implementation can be used as a reference.

Use:

- `.claude/styleguides/base.md` for the styleguide format;
- `.claude/adr/base.md` for the ADR format.

## Workflow

1. Confirm that no sufficient existing pattern exists.
   - If an existing file already half-implements the pattern
     inconsistently, do not treat it as a second precedent and do not fix
     it inline — log it in `.claude/styleguides/fix_me.md` under the
     relevant scope once the new styleguide exists to point at.
2. Inspect the surrounding architecture and constraints.
3. Identify the meaningful design alternatives.
4. Choose the approach that best fits the project.
5. Create an ADR documenting:
   - context;
   - decision;
   - alternatives;
   - consequences;
   - implementation constraints.
   Place it under `.claude/adr/<app>/` for the app the decision belongs to
   — ADRs are always app-specific, never shared.
6. Decide where the styleguide belongs: `.claude/styleguides/` (top level)
   if the new pattern applies identically across apps, or
   `.claude/styleguides/<app>/` if it's specific to that app's domain.
   Default to the app-specific folder when unsure.
7. Create the styleguide based on the accepted decision.
8. Make the styleguide describe how the new pattern must be implemented.
9. Present the ADR and styleguide to the user and wait for explicit
   approval before treating either as final.
10. Do not update the development plan. Updating its `status`
    frontmatter field and its `Missing Styleguides`/`Applicable
    Styleguides` sections is the exclusive responsibility of
    `styleguides-check` — once the ADR and styleguide are approved,
    control returns to that skill to re-check and finalize the plan.

## ADR Requirement

An ADR is mandatory for this skill.

The architectural decision must be documented before the styleguide is
finalized.

The ADR explains **why** the approach was chosen.

The styleguide explains **how** the approach should be implemented.

Do not duplicate the full ADR inside the styleguide.

## Result

The task is complete only when:

- the architectural decision is documented in an accepted ADR;
- the styleguide is created;
- the styleguide reflects the ADR;
- the user has approved the ADR and styleguide;
- implementation can proceed without making the architectural decision again.

This skill does not update the development plan. Updating the plan's
`status` frontmatter field and its `Missing Styleguides`/`Applicable
Styleguides` sections is the exclusive responsibility of
`styleguides-check` — hand control back to it once the ADR and
styleguide are approved.
