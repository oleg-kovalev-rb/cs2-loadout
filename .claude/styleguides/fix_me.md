# Style Deviations

Files that deviate from an established convention or styleguide rule,
found while writing/updating a styleguide, doing research, or
implementing a plan.

This is not a task backlog and not a place to design a fix. It exists so:

- a deviation found while extracting a styleguide doesn't get silently
  folded in as an "alternative" convention, or fixed on the spot (out of
  scope for `create-styleguide`/`create-styleguide-from-scratch`);
- anyone who later touches one of these files already knows it's
  non-conforming, instead of re-deriving that from scratch.

Format: one line per file —

```
- <path> — <which rule/convention it deviates from, in one line>
```

Group entries under the scope they belong to (mirrors
`.claude/styleguides/` itself). Once a file is brought into compliance,
delete its entry — don't leave a stale line behind.

`implement-plan` checks this file for any file it's about to touch: if the
fix is small and within the styleguide already being followed for that
change, fix it as part of that change and remove the entry. Don't expand
a change's scope just because an unrelated file is flagged here.

---

## Shared

(none yet)

## `app_fetcher`

(none yet)

## `app_core`

- `app_core/lib/steam/authenticator.rb` — missing a Sorbet `# typed:`
  sigil entirely; every sibling in `lib/steam/` (`bridge_token.rb`,
  `profile_fetcher.rb`) is `typed: strict`.
- `app_core/app/controllers/sessions_controller.rb`,
  `app_core/app/controllers/dashboards_controller.rb` — `typed: true`
  instead of `typed: strict`, unlike `app/actions/`, `app/models/`, and
  `lib/steam/` in the same app. May be intentional (Rails controller
  magic doesn't always play well with `strict`) — confirm when the
  shared Ruby/Sorbet styleguide is written, then either codify the
  exception there or fix these two files and remove this entry.
