# Shared agent docs

Canonical home for docs shared by **Claude Code** and **Cursor**.

| Path | Purpose |
|------|---------|
| `adr/` | Architecture Decision Records |
| `styleguides/` | Engineering conventions (shared + per-app) |
| `US/` | User stories |
| `plans/` | Development plans (`draft` → `styleguide-checked` → `implemented`) |

Skills stay tool-specific:

- Claude: `.claude/skills/`
- Cursor: `.cursor/skills/`

Both tool trees write and read these same paths.
