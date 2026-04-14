# claude-dev

Autonomous multi-agent development team orchestrator for Claude Code. A lead Opus 4.6 agent pulls kanban stories via the scrum-master integration (or works ad-hoc from a natural-language task), dispatches developer/reviewer/fix-pass subagents + Codex rescue, runs each story through a full dev-review-rework cycle, and dynamically routes tasks to the best available skill/plugin/MCP. Scales to large batches via sequential waves. Fully autonomous with session-scoped stop-hook gating.

## Install

### As a plugin directory

Clone into your Claude Code plugins directory:

```bash
git clone https://github.com/<your-org>/claude-dev ~/.claude/plugins/dev
```

Or place the folder anywhere Claude Code discovers plugins (`.claude/plugins/dev/` relative to a project, or a configured marketplace).

### Via a plugin marketplace

Add this repo to a `marketplace.json` in your marketplace definition:

```json
{
  "name": "dev",
  "source": "https://github.com/<your-org>/claude-dev",
  "version": "0.1.0",
  "category": "development"
}
```

Then enable in `~/.claude/settings.json` under `enabledPlugins`.

## Usage

### Slash command

```
/dev [scope]
```

| Scope | Behavior |
|---|---|
| (empty) / `all` | Sweep all Ready stories (KANBAN) or expect an ad-hoc task from conversation (AD-HOC) |
| `3` (integer) | Sweep next N stories by priority |
| `AUTH` (epic code) | Filter to stories in that epic |
| `P0` / `P1` / `P2` / `P3` | Filter to that priority level |
| `NET-01 NET-02` (story IDs) | Filter to those specific stories |

### Natural language

Works with conversation context:

- "dev team work on the auth stories"
- "have the dev team sweep P0"
- "dev sweep the next 5 stories"
- "dev team review this plugin"
- "have the dev team fix the auth bug in src/auth/"

### Negative triggers (will NOT activate this skill)

- "review my dev code" (use a code-review skill)
- "the dev team discussed" (casual conversation)
- "help me develop" (use feature-dev skill)

### Operating modes

The plugin runs in one of two modes, auto-detected from the invocation:

| Mode | When it triggers | How it differs |
|---|---|---|
| **KANBAN** | Scope arg is empty / `all` / integer / epic code / priority / story IDs; or kanban stories are found in the project | Pulls Ready stories, plans dispatch waves, runs full session-state.json + stop-hook + integration-branch infrastructure |
| **AD-HOC** | Natural-language task description; no kanban stories found; user describes work directly | No stories needed; lighter-weight orchestration; in-memory cost guard (no session-state); fixes apply on main working branch (no integration branch); no stop-hook registration |

**AD-HOC examples:**

- "dev team review this plugin"
- "have the dev team fix the auth bug in src/auth/"
- "dev team refactor the API layer"
- "have the dev team audit the deployment scripts"

In AD-HOC mode, work items are tagged `adhoc-<short-slug>-<4-char-rand>`, review depth scales with item count (1 item → Opus only; 4+ items → full three-stage), and CodeRabbit uses `--base <target-branch>`. If ad-hoc work grows beyond ~3 items, consider creating kanban stories first via a kanban plugin and switching to kanban mode.

## Architecture

Flat dispatch from a single primary lead. No secondary leads (blocked by platform limitation [anthropics/claude-code#46424](https://github.com/anthropics/claude-code/issues/46424) — sub-agents never receive the Agent tool in in-process mode).

```
User
  |
  v
Lead (SKILL.md, Opus 4.6)
  |
  |-- scrum-master integration  (deps, board updates, wave planning — throughout lifecycle)
  |-- dev:developer             (implementation, worktree-isolated)
  |-- dev:reviewer              (read-only code review)
  |-- dev:fix-pass              (rework on integration branch)
  |-- codex:codex-rescue        (adversarial cross-review — optional)
  |-- CodeRabbit CLI            (cr --plain pre-merge scan — optional)
  |
  v
Integration branch --> target branch (ff-only)
```

### Agent roles

| Agent | Model | Tools | Purpose |
|---|---|---|---|
| Lead (SKILL.md) | Opus 4.6 | Full session tool set (Agent, Read, Write, Bash, Glob, Grep, Skill, all MCPs) | Orchestrates all phases; dispatches every subagent; merges branches; updates board |
| `dev:developer` | Opus 4.6 | Full session tool set; Agent architecturally forbidden (no sub-delegation) | Implements one story in worktree isolation; TDD discipline; commits with story-ID prefix |
| `dev:reviewer` | Opus 4.6 | Full session tool set; Edit/Write/Agent architecturally forbidden (read-only) | Reviews one story's diff against ACs; writes findings via Bash heredoc only |
| `dev:fix-pass` | Opus 4.6 | Full session tool set; Agent architecturally forbidden (no sub-delegation) | Applies must-fix/should-fix findings on integration branch |
| `secondary-lead-DO-NOT-DISPATCH` | — | — | Documentation only. Preserves intended architecture for when #46424 is fixed |

### Execution phases (KANBAN mode)

| Phase | What happens |
|---|---|
| 0 | Parse scope, auto-detect project + CI pipeline, check for interrupted session, pick mode |
| 1 | Recon: read stories, query memory (if configured), map codebase |
| 2 | Plan: assign stories to waves, route skills, set up session dir + stop-hook + integration branch |
| 3 | Execute: dispatch developers in parallel (worktree-isolated, up to 4/wave), merge per-story to integration, run tests, update board + re-evaluate deps after each wave |
| 4 | Review: dispatch reviewer (with domain review skill) + Codex cross-review + CodeRabbit per wave |
| 5 | Fix-pass: consolidate findings, dispatch fix-pass agent if must-fix items exist |
| 5.5 | Comprehensive domain review: dispatch the full domain review plugin (ios-code-review, typescript-senior-review) for whole-project analysis |
| 6 | Finalize: local test suite → **CI/CD gate (mandatory if pipeline detected)** → ff-only merge to target → update kanban board → clean up |
| 7 | Report: summary table with CI status, learnings written to memory (if configured) |

AD-HOC mode collapses this to: recon → decompose → dispatch (per work item) → review → fix-pass if needed → report. No session-state, no stop-hook, no integration branch.

## Configuration

Auto-detects project conventions from git, `./CLAUDE.md`, and any scrum-master config. Optional explicit config at `.claude/dev.local.md`:

```yaml
---
target_branch: main
max_parallel: 3
max_fix_rounds: 2
codex_review: true
coderabbit_review: true
# Optional: your GoodMem space UUID if you have GoodMem configured
goodmem_space: "<your-project-space-uuid>"
---

Additional project-specific instructions for the dev team lead.
Content below the YAML frontmatter is passed verbatim to the lead.
```

| Field | Default | Purpose |
|---|---|---|
| `target_branch` | auto-detected (`main`, `dev`, etc.) | Branch to ff-only merge into after sweep |
| `max_parallel` | `4` | Max concurrent developer agents per wave |
| `max_fix_rounds` | `2` | Max review-fix iterations before escalating to Blocked |
| `codex_review` | `true` | Enable Codex adversarial cross-review (requires `codex` plugin) |
| `coderabbit_review` | `true` | Enable CodeRabbit CLI pre-merge scan (requires `cr` CLI) |
| `goodmem_space` | unset | Project-specific GoodMem space UUID for retrieval (requires `goodmem` MCP) |
| `ci_type` | auto-detected | Override CI type (`github-actions`, `gitlab-ci`, `jenkins`, `circleci`, etc.) |
| `ci_skip` | `false` | Set to `true` to skip the CI gate entirely |

All integrations are optional. The plugin degrades gracefully:

- No GoodMem? Memory steps are skipped.
- No Codex plugin? Codex stage is skipped.
- No CodeRabbit CLI? That stage is skipped; Opus reviewer carries the review.
- No serena? Symbol navigation falls back to Grep/Glob.
- No obsidian MCP? Vault lookups are skipped.
- No scrum-master plugin? Kanban mode requires story files present on disk; otherwise use AD-HOC mode.

## Component files

| File | Purpose |
|---|---|
| `.claude-plugin/plugin.json` | Plugin manifest (name, version, keywords) |
| `skills/dev/SKILL.md` | Lead orchestrator skill (Phase 0-7 + Large Batch + Errors + Session Schemas) |
| `agents/developer.md` | Implementation agent definition |
| `agents/reviewer.md` | Code review agent definition |
| `agents/fix-pass.md` | Rework agent definition |
| `agents/secondary-lead-DO-NOT-DISPATCH.md` | Architecture reference (non-functional, pending #46424) |
| `hooks/dev-sweep-stop-gate.sh` | Session-scoped stop-hook; blocks session end while sweep is active |
| `hooks/dev-sweep-watch.sh` | Live CLI dashboard; run in a separate terminal during sweeps |
| `README.md` | This file |

## Key rules

1. Lead dispatches ALL agents. No secondary leads in the current runtime.
2. Every developer runs in worktree isolation (`isolation: "worktree"`) in KANBAN mode.
3. Developers dispatched in parallel (up to `max_parallel` per wave, default 4) in a single message block.
4. Tests gate every merge. Integration branch failure rolls back to last-good checkpoint.
5. **CI/CD pipeline gate is mandatory** if a CI config is detected. No merge without CI green. Override with `ci_skip: true`.
6. Three-stage review: spec compliance (`dev:reviewer`) + adversarial (Codex) + automated (CodeRabbit) — any stage is skippable if the integration isn't present.
7. Fix code to match tests, never the reverse. No test modification in implementation commits.
8. Session state persists to `.claude/dev-sessions/<id>/session-state.json` for resume in KANBAN mode.
9. Stop-hook prevents premature session termination while sweep is active. Activity-based TTL (default 1h of inactivity releases).

## Related plugins this pairs well with

None are required, but if installed they are used automatically:

- **scrum-master** — kanban board management, story file format, wave planning
- **codex** — adversarial cross-review via `codex:rescue`
- **coderabbit** — automated pre-merge review via `cr` CLI
- **goodmem** — cross-session memory for learnings and user preferences
- **serena** — semantic code navigation
- **context7** — up-to-date library documentation
- **obsidian** — vault search for project conventions

## Platform notes

### Known issues this plugin works around

- [#46424](https://github.com/anthropics/claude-code/issues/46424), [#31977](https://github.com/anthropics/claude-code/issues/31977), [#47898](https://github.com/anthropics/claude-code/issues/47898) — Sub-agents never receive the Agent tool. Consequence: no hierarchical dispatch (secondary leads). Primary lead does all dispatching.
- [#37873](https://github.com/anthropics/claude-code/issues/37873) — Deterministic worktree branch name collision. Mitigation: story ID injected as nonce in developer briefing.
- [#29110](https://github.com/anthropics/claude-code/issues/29110) — Uncommitted work lost on worktree cleanup. Mitigation: every developer commits before declaring success.
- [#28041](https://github.com/anthropics/claude-code/issues/28041) — `.claude/` shallow-copy in worktrees. Mitigation: session dir referenced by absolute path in all briefings.
- [#44778](https://github.com/anthropics/claude-code/issues/44778) — Fabricated consent from system events. Mitigation: filesystem markers (test exit codes) gate merges, not model text.

### What the plugin cannot do yet

- Secondary team leads (hierarchical dispatch) — blocked by #46424.
- Cross-session watchdog for hung subagents — tracked as external companion tool.
- Automated resume of an interrupted sweep across machine reboots — session dir survives, but orphan worktree reconciliation is manual.

## License

MIT. See `LICENSE` if included.
