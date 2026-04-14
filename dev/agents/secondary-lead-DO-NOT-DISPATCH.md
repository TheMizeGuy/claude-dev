---
name: secondary-lead-DO-NOT-DISPATCH
description: |-
  DO NOT DISPATCH. DOCUMENTATION ONLY. This file preserves the intended architecture for secondary team leads pending a platform fix. Secondary leads are currently NON-FUNCTIONAL because Claude Code sub-agents never get the Agent tool in in-process mode (anthropics/claude-code#46424, #31977, #47898). Do not invoke this agent via subagent_type. See spec Section 8 for current large-batch behavior.
---

# ⚠️ DO NOT DISPATCH — DOCUMENTATION ONLY ⚠️

**This file is preserved as a reference for the intended secondary-lead architecture. It is NOT a functional agent. The primary team lead (SKILL.md) does all dispatching. There is no hierarchy in the current runtime.**

## Why this file exists

When Anthropic fixes anthropics/claude-code#46424 (sub-agents don't get Agent tool), secondary leads will become viable. This file documents the intended toolset and behavior so the upgrade path is clear.

## Intended toolset (NOT currently enforced)

```yaml
tools: Agent, Read, Write, Bash, Glob, Grep, Skill, TodoWrite, goodmem_*, serena_*, context7_*, obsidian_*
```

Key: has `Agent` (for dispatching developers), no `Edit` (delegator, not implementer).

## Intended behavior (FUTURE)

When unblocked:
- Owns a subset of stories partitioned by file-ownership connected components
- Runs in its own worktree (parallel-safe with other leads)
- Dispatches dev:developer agents SEQUENTIALLY within its worktree
- Does NOT dispatch further secondary leads (no recursion)
- Writes results to SESSION_DIR (absolute path) for primary to read
- Commits all work before returning

## Current large-batch behavior

See spec Section 8: primary team lead runs more sequential waves (5-15 waves for large batches). No hierarchy. Cost guard scales with story count.
