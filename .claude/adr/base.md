
# ADR Template

This file describes the structure and purpose of Architecture Decision Records.

It is a reference for `create-styleguide-from-scratch` and any workflow that
creates or updates architectural decisions.

An ADR documents **why** an architectural decision was made.

It is not an implementation tutorial and should not duplicate the full
contents of a styleguide.

---

# <Decision Title>

## Status

Use one of:

- Proposed
- Accepted
- Superseded
- Deprecated

The status should reflect the current state of the decision.

---

## Context

Explain the problem that requires an architectural decision.

Describe only the context necessary to understand why a decision was needed.

Include relevant:

- system constraints;
- existing architecture;
- requirements;
- limitations;
- technical problems;
- business constraints when they materially affect the technical decision.

Do not describe the implementation in detail here.

---

## Decision

State the chosen approach clearly and directly.

A reader should be able to understand the decision without reading the rest
of the document.

Include the important architectural boundaries or constraints created by the
decision.

---

## Alternatives Considered

Document meaningful alternatives that were evaluated.

For each alternative, explain:

- what it was;
- why it was considered;
- why it was rejected.

Do not create a long list of obviously irrelevant alternatives.

Example:

### Alternative: <Name>

Description.

Rejected because:

- ...
- ...

---

## Consequences

Describe the consequences of the decision.

### Positive

Expected benefits.

### Negative

Accepted costs, complexity, limitations, or trade-offs.

### Risks

Important risks introduced by the decision.

---

## Implementation Constraints

Document important constraints that follow directly from the decision.

Examples:

- dependency boundaries;
- data ownership;
- transaction requirements;
- integration boundaries;
- performance constraints;
- operational requirements.

This section may be referenced when creating the corresponding styleguide.

Do not turn it into a step-by-step implementation guide.

---

## Related

Reference related documentation:

- styleguides;
- other ADRs;
- architectural documentation;
- relevant code.

---

# Writing Rules

## Explain Why

The primary purpose of an ADR is to preserve the reasoning behind a decision.

A future developer should understand:

> Why was this approach chosen?

without reconstructing the reasoning from Git history.

## Record Decisions, Not Discussions

Do not write a meeting transcript.

Capture the final decision and the important reasoning behind it.

## Include Trade-offs

Architectural decisions should document what was gained and what was
accepted in return.

## Keep the Scope Focused

One ADR should describe one coherent architectural decision.

## Prefer Durable Information

Avoid temporary implementation details that will become irrelevant quickly.

## Keep ADR and Styleguide Separate

ADR:

> Why did we choose this approach?

Styleguide:

> How should code using this approach be written?

Do not duplicate entire sections of one document into the other.

## Update Status When the Decision Changes

When a decision is replaced, superseded, or no longer applies, update the ADR
status and reference the newer decision where appropriate.
