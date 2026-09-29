# Hand-Rolled SVG for Repeated Sparklines, Recharts Only for the Hero Chart

## Status

Accepted

## Context

The dashboard renders two different kinds of line chart:

- One large, interactive chart with real axes, tick formatting, and a
  hover tooltip — the hero chart shown in `PortfolioTile`
  (`HeroChart.jsx`), rendered exactly once per dashboard view.
- Many small, purely decorative trend indicators — one per visible item
  row (`ItemRow`'s sparkline, up to `PAGE_SIZE = 8` per page) plus one in
  `MarketVolumeTile` — with no axes, no tooltip, no legend, and no
  interactivity requirement.

`recharts` is already a dependency, used for the hero chart. The
straightforward-looking choice would be to reuse it for the small
sparklines too, on the reasoning that the codebase should have "one way
to draw a line chart." `Sparkline.jsx` instead hand-rolls minimal inline
SVG (a point-to-pixel mapping + a single `<path>`, optionally a filled
area) with no charting library involved.

## Decision

Use Recharts only where its actual features — axes, tick formatting, a
tooltip, responsive interactivity — are needed, which today is exactly
one component, `HeroChart`. Use a hand-rolled, minimal SVG component
(`Sparkline.jsx`) for small, repeated, decorative-only trend lines with
none of those requirements, rendered many times per page view.

## Alternatives Considered

### Alternative: Recharts everywhere, including per-row sparklines

Render each item row's sparkline as its own small Recharts
`<LineChart>`/`<AreaChart>` instance instead of hand-rolled SVG.

Rejected because:

- A Recharts instance carries its own internal state, a
  `ResizeObserver`-driven `ResponsiveContainer`, and SVG-generation
  machinery meant for a chart with axes/tooltip/legend — multiplying a
  full instance of that by 8-9+ per page view (one per visible row, plus
  the volume strip) is meaningfully heavier than a handful of computed
  `<path>` elements, for a visualization that uses none of what the
  library provides.

### Alternative: Hand-rolled SVG everywhere, drop Recharts entirely

Reimplement the hero chart's axes, tick formatting, and hover tooltip by
hand instead of depending on a charting library at all.

Rejected because:

- The hero chart's actual requirements — real axes with formatted ticks,
  a hover tooltip, smooth area rendering, responsive sizing — are exactly
  the problem a charting library solves well. It renders once per page
  view, so its overhead is a non-issue; reimplementing that correctly by
  hand would cost more than it saves.

## Consequences

### Positive

- Sparkline rendering cost stays flat and cheap regardless of how many
  rows are visible or how large `PAGE_SIZE` grows.
- The hero chart keeps full library-quality axes, tick formatting, and
  tooltip behavior without reinventing them.

### Negative

- Two different rendering mechanisms for "a line chart" exist side by
  side in the same directory; a contributor has to know which one a new
  visualization should use rather than reaching for a single obvious
  tool.

### Risks

- A future contributor could look at `Sparkline.jsx`'s minimal hand-rolled
  SVG and read it as an unfinished placeholder worth "upgrading" to
  Recharts for consistency with `HeroChart`. Doing so would reintroduce
  the exact per-row instantiation cost this decision exists to avoid —
  `Sparkline.jsx`'s own code comment states the reasoning directly so
  that question has an answer before someone acts on the assumption.

## Implementation Constraints

- A new small, repeated (rendered more than a couple of times per view)
  decorative visualization with no axes/tooltip/legend requirement
  extends or reuses `Sparkline.jsx`, not a new Recharts instance.
- A new visualization that genuinely needs axes, a tooltip, or a legend,
  and renders at most once (or a small fixed number of times) per view,
  uses Recharts, following `HeroChart.jsx`'s shape — a thin wrapper
  around Recharts primitives plus the shared `ChartTooltip`.
- Don't merge the two into one shared "chart" abstraction — they exist to
  solve different cost/feature trade-offs, not the same problem
  implemented twice by accident.

## Related

- `.claude/styleguides/core/react-dashboard.md` — Charting section
- `app_core/app/frontend/dashboard/components/Sparkline.jsx`
- `app_core/app/frontend/dashboard/components/HeroChart.jsx`
- `app_core/app/frontend/dashboard/components/ChartTooltip.jsx`
- `app_core/app/frontend/dashboard/components/ItemRow.jsx`,
  `MarketVolumeTile.jsx` — `Sparkline` call sites
