# AI Agent Configuration Surfaces

This repository intentionally keeps agent/runtime configuration split by tool rather than consolidated.

- **Do not merge these directories together**.
- Use the config surface that matches the tool you are actively using.

## Quick map

| Path | Loaded by | When it applies |
|---|---|---|
| `CLAUDE.md` (+ `AGENTS.md`) | Claude Code / opencode Claude sessions | Always for Claude-driven sessions in this repo |
| `.cursor/hooks.json`, `.cursor/hooks/*` | Cursor | During Cursor file edit lifecycle events |
| `.opencode/plugins/*` | opencode | During opencode session events |
| `.opencode/package.json` | opencode plugin runtime | Only when opencode loads local plugins |

## `.claude/` and Claude-side guidance

This repo does not maintain a project-local `.claude/` directory. Claude behavior is controlled by:

1. Repo-level instruction files (`CLAUDE.md`, `AGENTS.md`)
2. User/global Claude configuration (for example `~/.claude/...`, outside this repo)

Use this model for Claude:

- Put **project policy and architecture guidance** in `CLAUDE.md` / `AGENTS.md`.
- Keep user-specific Claude customizations in `~/.claude` (not in this repository).

## `.cursor/` (Cursor-only hooks)

Cursor config is isolated under `.cursor/`:

- `.cursor/hooks.json` registers hook bindings.
- `.cursor/hooks/flag-doc-drift.sh` runs after edits to `apps/base/` or `base/services/` and emits a **non-blocking doc reminder**.

This is advisory only (no hard failure), intended to remind contributors about docs freshness while editing infra manifests in Cursor.

## `.opencode/` (opencode-only config)

opencode config is isolated under `.opencode/`:

- `.opencode/plugins/doc-guard.ts` mirrors Cursor's doc-drift reminder behavior via opencode session events.
- `.opencode/package.json` defines plugin runtime dependency (`@opencode-ai/plugin`).
- `.opencode/.gitignore` ignores local runtime artifacts under `.opencode/`.

This path is only used by opencode sessions and has no effect on Cursor hook execution.

## Cross-reference and ownership rules

- If the behavior should apply to **all contributors regardless of editor**, prefer repo docs + git hooks (`AGENTS.md`, `CLAUDE.md`, `.pre-commit-config.yaml`, `scripts/pre-commit/*`).
- If behavior is **editor/runtime specific**, keep it in that tool's namespace (`.cursor/` or `.opencode/`).
- Keep duplicated policy text minimal: for architecture details, point to `CLAUDE.md`; for onboarding and quickstart, point to `README.md`; for agent rules, point to `AGENTS.md`.
