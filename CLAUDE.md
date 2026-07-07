# claude-dev

Public release repo of the `dev` Claude Code plugin — an autonomous multi-agent development-team orchestrator. A team-lead skill pulls kanban stories (or decomposes an ad-hoc request), dispatches developer/reviewer/fix-pass subagents, and runs each story through a full dev-review-rework cycle with optional CodeRabbit/adversarial review. Install: `/plugin marketplace add TheMizeGuy/claude-dev` then `/plugin install dev@claude-dev`.

## PUBLIC REPO — scrub gate on every commit

This repo is maintained by re-genericizing content from a private source; never copy private material in un-scrubbed. Before any commit, verify zero hits for: user-specific absolute paths (`/Users/...`), memory-space UUIDs, private hostnames or machine names, and real credential patterns. The most recent history includes a dedicated scrub commit — treat that as the standing bar, not a one-off. The `goodmem_space` value in README stays the literal placeholder `<your-project-space-uuid>`.

## Structure

- `.claude-plugin/marketplace.json` — this repo is its own single-plugin marketplace (`dev`, source `./dev`). Bump the version here AND in `dev/.claude-plugin/plugin.json` together.
- `dev/skills/dev/SKILL.md` — lead orchestrator: phase map + invariants; per-phase depth in `dev/skills/dev/references/` (9 files).
- `dev/agents/developer.md`, `reviewer.md`, `fix-pass.md` — dispatched agents. None pins a `model:` — agents inherit the session model. Never re-add pins.
- `dev/hooks/` — session-scoped stop-gate scripts; wired by the skill at runtime (there is deliberately no static hooks.json).

## The one agent you never dispatch

`dev/agents/secondary-lead-DO-NOT-DISPATCH.md` is documentation-only: secondary team leads are non-functional because Claude Code subagents don't receive the Agent tool in in-process mode (anthropics/claude-code#46424, #31977, #47898). Any invocation of it is a defect. Large batches run as sequential waves from the primary lead (see `references/kanban-phase-6-finalize.md`).

## Graceful degradation (documented contract — preserve it)

The orchestrator must keep working when optional tooling is absent: no GoodMem MCP → memory steps skip; no CodeRabbit CLI → that review stage skips; no serena → falls back to Grep/Glob. When editing the skill, never turn an optional dependency into a hard requirement.

## What this repo is not

No application code, no build, no tests, no CI — quality control is prompt review plus a scrub pass. Consumer-side configuration lives in the consuming project's `.claude/dev.local.md` (`target_branch`, `max_parallel`, `max_fix_rounds`, `codex_review`, `coderabbit_review`, `goodmem_space`, `ci_type`, `ci_skip`), documented in README — keep that table current when adding config fields.
