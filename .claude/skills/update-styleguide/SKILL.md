---
name: update-styleguide
description: Amend an existing styleguide to cover an edge case or scenario its current rules don't address. Use when a styleguide already exists and already applies, but a specific situation falls outside what it documents today. Not for patterns with no styleguide yet — use create-styleguide or create-styleguide-from-scratch for those instead.
---

# Update Styleguide

Amend an existing project styleguide in place to cover an edge case it doesn't currently address.

Use `.claude/styleguides/base.md` as the format reference — the target file should already follow it; check that the amendment keeps it that way.

## When this applies

Use this skill only when the relevant styleguide already exists and already applies to the area of code in question, but the current work surfaces a concrete case — an exception, a boundary condition, a scenario — that the guide's existing rules don't cover.

If no styleguide exists yet for the pattern at all, this is not an update — use `create-styleguide` (pattern already exists in code) or `create-styleguide-from-scratch` (pattern doesn't exist in code yet) instead. Forcing an unrelated rule into a guide just because a file happens to exist at that path is worse than leaving the gap visible.

## Workflow

1. Identify the specific edge case: what situation isn't covered, and which existing styleguide file should cover it.
2. Re-read the full existing styleguide, not just its frontmatter description, to confirm the gap is real and to find where the new rule belongs among the existing sections.
3. Find representative implementations of this specific edge case in the codebase (or, if none exist yet, the closest real precedent the new rule will follow).
4. Inspect their tests and related code.
5. Identify the rule the edge case implies.
   - If a representative implementation deviates from the rule followed by the others, do not fold the deviation in as an alternative and do not fix it inline — extract the rule from the conforming majority, then log the deviating file in `.claude/styleguides/fix_me.md` under the relevant scope (see that file for the format).
6. Integrate the new rule into the existing file:
   - locate the section it belongs under, or add a new section if none fits;
   - write it so it reads as part of the existing guide, not as an appendix bolted onto the end;
   - add a canonical example for the new case alongside the existing ones — do not replace or remove existing canonical examples, and do not rewrite unrelated sections while you're in the file.
7. Validate the amended guide against the codebase.
8. Present the amendment — the specific addition, not the whole file — to the user and wait for explicit approval before treating it as final. This skill only amends the styleguide (and, when applicable, the ADR); it does not update the development plan. Updating the plan's `status` frontmatter field and its `Missing Styleguides`/`Applicable Styleguides` sections is the exclusive responsibility of `styleguides-check`.

Do not invent conventions that are not supported by the existing code.

If the edge case turns out to be broad enough that it's really a distinct pattern rather than a scenario of the existing one, stop and reconsider whether `create-styleguide` is the better fit.

## ADR

After understanding the edge case, determine whether covering it is itself a meaningful architectural decision, not just a clarification of existing guidance.

An ADR is usually unnecessary for ordinary clarifications or narrow exceptions.

An ADR may be appropriate when the amendment introduces:

- a new architectural boundary;
- a new dependency rule;
- a significant design pattern not implied by the existing guide;
- a choice between meaningful alternatives;
- an intentional long-term constraint.

If an ADR may be appropriate:

1. Explain why.
2. Ask the user whether an ADR should be created.
3. Create it only after approval, under `.claude/adr/<app>/` for the app the decision belongs to (ADRs are always app-specific, never shared). If an ADR already exists for the styleguide being amended, consider extending it instead of creating a new one.
4. Use `.claude/adr/base.md` as the format reference.

## Result

The task is complete when:

- the existing styleguide file is amended in place, at its existing location — no new file is created;
- the new rule is grounded in existing code (or, lacking that, the closest real precedent);
- the new rule sits in the section it belongs to, not appended as an afterthought;
- a canonical example for the new case is added alongside the existing ones, none of which were removed or rewritten;
- unrelated content in the file is untouched;
- any deviating files found along the way are logged in `.claude/styleguides/fix_me.md`, not fixed inline;
- ADR handling is resolved when applicable;
- the user has approved the amendment;
- the development plan was not modified by this skill.
