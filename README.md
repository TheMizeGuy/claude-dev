# claude-dev

Autonomous multi-agent development team orchestrator for Claude Code. A lead agent, running on the session model (always the strongest available Claude), pulls kanban stories via a scrum-master-compatible board (or works ad-hoc from a natural-language task), dispatches developer/reviewer/fix-pass subagents plus optional adversarial review, runs each story through a full dev-review-rework cycle, and dynamically routes tasks to the best available skill/plugin/MCP. Scales to large batches via sequential waves. Fully autonomous with session-scoped stop-hook gating.

## Install

This repo ships its own marketplace manifest (`.claude-plugin/marketplace.json`) with the plugin nested under `dev/`.

### Via the marketplace (recommended)

```
/plugin marketplace add TheMizeGuy/claude-dev
/plugin install dev@claude-dev
```

### Manual clone

```bash
git clone https://github.com/TheMizeGuy/claude-dev.git
```

Then point Claude Code at the `claude-dev/dev` directory — either add it as a plugin source in your own marketplace definition, or copy/symlink `dev/` into a directory Claude Code scans for plugins (e.g. `.claude/plugins/dev/` relative to a project).

## Quickstart

1. Install the plugin (see above).
2. In any git repo, invoke `/dev` (or say "dev team work on...", "have the dev team...").
3. The plugin auto-detects mode: if kanban story files exist (`Backlog/current/*.md`, `Backlog/*.md`, or `stories/*.md`), it pulls Ready stories (KANBAN mode); otherwise it decomposes your natural-language request directly (AD-HOC mode).
4. Watch the wave-dispatch announcements: developer agents implement, a reviewer checks the diff against acceptance criteria, and a fix-pass agent applies any must-fix findings — sequential across waves, concurrent within a wave.
5. Read the Phase 7 report (`DEV SWEEP COMPLETE`) for the final summary: stories completed, agents dispatched by type, review findings resolved, CI status, and the commit the work landed on.

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
- "help me develop" (plain implementation request without "dev team" framing)

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

In AD-HOC mode, work items are tagged `adhoc-<short-slug>-<4-char-rand>`, review depth scales with item count (1 item → session-model review only; 4+ items → full three-stage), and CodeRabbit uses `--base <target-branch>`. If ad-hoc work grows beyond ~3 items, consider creating kanban stories first (e.g. via a kanban/scrum-master plugin) and switching to kanban mode.

### Walkthrough: kanban sweep

A concrete run of `/dev P0` in a project with a `Backlog/current/` board:

1. **Phase 0** — parses `P0` as a priority filter, detects the project root, CI type, and the kanban board path; builds the session's capability catalog.
2. **Phase 1** — queries GoodMem (if configured) for prior learnings on this project, reads and filters stories to those `state: Ready` with priority `P0` and no unmet blockers.
3. **Phase 2** — routes each story to a primary skill (e.g., TypeScript stories → a TDD skill + `context7`), builds the file-ownership matrix, groups non-conflicting stories into waves, creates the session directory and registers the stop-hook.
4. **Phase 3** — dispatches up to `max_parallel` developer agents for wave 1 in one message (worktree-isolated); each implements its story with TDD discipline, commits, and writes `result.json`.
5. **Phase 4** — dispatches a reviewer per story plus optional CodeRabbit and adversarial cross-review; findings are consolidated and classified must-fix / should-fix / nit.
6. **Phase 5** — if must-fix findings exist, dispatches a fix-pass agent on the integration branch, then re-reviews (2-round cap).
7. Repeats Phases 3-5 for each subsequent wave, then **Phase 5.5** runs a comprehensive domain review across all waves.
8. **Phase 6** — runs the full test suite, waits for CI to go green (mandatory if CI is detected), fast-forward merges the integration branch into the target branch, and updates every story to `state: Done` with `evidence.commit`.
9. **Phase 6.5** — verifies `reviewers_dispatched >= developers_dispatched` and that every merged story has a review file; catches up any gaps before reporting.
10. **Phase 7** — prints the `DEV SWEEP COMPLETE` summary table.

### Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `/dev` stops dispatching mid-sweep with a "Cost guard reached" message | `agents_dispatched` hit `max_agents_per_session` (`max(200, story_count*10)`) | Check `session-state.json`; resume with `/dev` (KANBAN) once you're ready to continue, or narrow the scope |
| Session won't end — stop-hook keeps blocking | The stop-hook gates session end while `$SESSION_DIR/active` is fresh (sweep still in progress or crashed) | Wait out the inactivity TTL (default 1h), or `touch $SESSION_DIR/done` to release manually |
| A story is stuck as `merge_status: conflict-deferred` | `git merge-tree --write-tree` predicted a conflict with another merged branch | Check the story's `errors` array in `session-state.json` for the conflicting files; it is picked up by the next fix-pass |
| Finalize never merges to the target branch | CI is failing, timing out, or never triggering (branch filter excludes integration branches) | Check `$SESSION_DIR/ci-failure.md`; set `ci_skip: true` in `.claude/dev.local.md` only if you intend to bypass the gate intentionally |
| "No ready stories match `<scope>`" | Board path wrong, or no stories satisfy `state: Ready` + unblocked dependencies for that filter | Verify `Backlog/current/*.md` (or your configured board path) has matching stories; check `dependencies.blocked-by` on the ones you expect |
| `dev-sweep-watch.sh` prints "No active dev session found" | No sweep is currently running in this project | Start a sweep with `/dev` first, then re-run the dashboard script in a second terminal |

## Architecture

Flat dispatch from a single primary lead. No secondary leads (blocked by platform limitation [anthropics/claude-code#46424](https://github.com/anthropics/claude-code/issues/46424) — sub-agents never receive the Agent tool in in-process mode).

```
User
  |
  v
Lead (SKILL.md, session model)
  |
  |-- scrum-master integration  (deps, board updates, wave planning — throughout lifecycle, if installed)
  |-- dev:developer             (implementation, worktree-isolated)
  |-- dev:reviewer              (read-only code review)
  |-- dev:fix-pass              (rework on integration branch)
  |-- adversarial cross-review  (optional, e.g. via a Codex-style plugin)
  |-- CodeRabbit CLI            (cr --plain pre-merge scan — optional)
  |
  v
Integration branch --> target branch (ff-only)
```

### Agent roles

| Agent | Model | Tools | Purpose |
|---|---|---|---|
| Lead (SKILL.md) | Session model | Agent, Read, Write, Bash, Glob, Grep, Skill, all MCPs | Orchestrates all phases; dispatches every subagent; merges branches; updates board |
| `dev:developer` | Session model | Edit, Read, Write, Bash, Glob, Grep, Skill, goodmem, serena, context7, obsidian | Implements one story in worktree isolation; TDD discipline; commits with story-ID prefix |
| `dev:reviewer` | Session model | Read, Bash, Glob, Grep, Skill, goodmem, serena, context7 | Reviews one story's diff against ACs; read-only (no Edit/Write/Agent) |
| `dev:fix-pass` | Session model | Edit, Read, Write, Bash, Glob, Grep, Skill, goodmem, serena, context7 | Applies must-fix/should-fix findings on integration branch; no Agent tool |
| `secondary-lead-DO-NOT-DISPATCH` | — | — | Documentation only. Preserves intended architecture for when #46424 is fixed |

Every dispatched agent inherits the session model — always the strongest available Claude. Nothing in this plugin pins a model or waits on one that isn't the session model; see "Execution mode" in `skills/dev/SKILL.md` for the single-item inline-execution optimization.

### Execution phases (KANBAN mode)

| Phase | What happens |
|---|---|
| 0 | Parse scope, auto-detect project + CI pipeline, check for interrupted session, pick mode |
| 1 | Recon: read stories, query memory (if configured), map codebase |
| 2 | Plan: assign stories to waves, route skills, set up session dir + stop-hook + integration branch |
| 3 | Execute: dispatch developers in parallel (worktree-isolated, up to `max_parallel`/wave), merge per-story to integration, run tests, update board + re-evaluate deps after each wave |
| 4 | Review: dispatch reviewer + optional adversarial cross-review + CodeRabbit per wave |
| 5 | Fix-pass: consolidate findings, dispatch fix-pass agent if must-fix items exist |
| 5.5 | Comprehensive domain review across all waves (cross-story lens) before finalize |
| 6 | Finalize: local test suite → **CI/CD gate (mandatory if pipeline detected)** → ff-only merge to target → update kanban board → clean up |
| 6.5 | Pipeline verification gate: reviewers >= developers, missing reviews caught up, else halt |
| 7 | Report: summary table with CI status, learnings written to memory (if configured) |

AD-HOC mode collapses this to: recon → decompose → dispatch (per work item) → review → fix-pass if needed → report. No session-state, no stop-hook, no integration branch.

## Configuration

Auto-detects project conventions from git and any scrum-master-compatible config. Optional explicit config at `.claude/dev.local.md`:

```yaml
---
target_branch: main
max_parallel: 4
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
| `codex_review` | `true` | Enable adversarial cross-review (requires a compatible plugin) |
| `coderabbit_review` | `true` | Enable CodeRabbit CLI pre-merge scan (requires the `cr` CLI) |
| `goodmem_space` | unset | Project-specific GoodMem space UUID for retrieval (requires a GoodMem MCP server) |
| `ci_type` | auto-detected | Override CI type (`github-actions`, `gitlab-ci`, `jenkins`, `circleci`, etc.) |
| `ci_skip` | `false` | Set to `true` to skip the CI gate entirely |

All integrations are optional. The plugin degrades gracefully:

- No GoodMem MCP? Memory steps are skipped.
- No adversarial-review plugin? That stage is skipped.
- No CodeRabbit CLI? That stage is skipped; the reviewer agent carries the review.
- No serena? Symbol navigation falls back to Grep/Glob.
- No obsidian MCP? Vault lookups are skipped.
- No scrum-master-compatible plugin? Kanban mode requires story files present on disk; otherwise use AD-HOC mode.

## Component files

| File | Purpose |
|---|---|
| `dev/.claude-plugin/plugin.json` | Plugin manifest (name, version, author, keywords) |
| `dev/skills/dev/SKILL.md` | Lead orchestrator skill: phase map + critical invariants (always loaded) |
| `dev/skills/dev/references/` | Per-phase deep material loaded on demand: phase-0 setup, ad-hoc mode, kanban phases 1-7, proactive-capability doctrine, error recovery, session schemas |
| `dev/agents/developer.md` | Implementation agent definition |
| `dev/agents/reviewer.md` | Code review agent definition |
| `dev/agents/fix-pass.md` | Rework agent definition |
| `dev/agents/secondary-lead-DO-NOT-DISPATCH.md` | Architecture reference (non-functional, pending #46424) |
| `dev/hooks/dev-sweep-stop-gate.sh` | Session-scoped stop-hook; blocks session end while sweep is active |
| `dev/hooks/dev-sweep-watch.sh` | Live CLI dashboard; run in a separate terminal during sweeps |
| `.claude-plugin/marketplace.json` | Marketplace manifest for this repo |
| `README.md` | This file |
| `LICENSE` | MIT license |

## Key rules

1. Lead dispatches ALL agents. No secondary leads in the current runtime.
2. Every developer runs in worktree isolation (`isolation: "worktree"`) in KANBAN mode.
3. Developers dispatched in parallel (up to `max_parallel` per wave, default 4) in a single message block.
4. Tests gate every merge. Integration branch failure rolls back to last-good checkpoint.
5. **CI/CD pipeline gate is mandatory** if a CI config is detected. No merge without CI green. Override with `ci_skip: true`.
6. Three-stage review: spec compliance (`dev:reviewer`) + adversarial cross-review (optional) + automated (CodeRabbit, optional) — any optional stage is skipped if the integration isn't present.
7. Fix code to match tests, never the reverse. No test modification in implementation commits.
8. Session state persists to `.claude/dev-sessions/<id>/session-state.json` for resume in KANBAN mode.
9. Stop-hook prevents premature session termination while sweep is active. Activity-based TTL (default 1h of inactivity releases).

## Related plugins this pairs well with

None are required, but if installed they are used automatically:

- **scrum-master** (or any compatible kanban plugin) — kanban board management, story file format, wave planning
- **codex** (or any compatible adversarial-review plugin) — cross-review pass
- **coderabbit** — automated pre-merge review via the `cr` CLI
- **goodmem** (or any compatible GoodMem-protocol MCP) — cross-session memory for learnings and user preferences
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
- Cross-session watchdog for hung subagents — tracked as an external companion tool.
- Automated resume of an interrupted sweep across machine reboots — session dir survives, but orphan worktree reconciliation is manual.

## License

MIT. See `LICENSE`.
