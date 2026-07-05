---
name: dev
description: |-
  Autonomous multi-agent development team orchestrator. Use when the user says
  "dev team work on...", "have the dev team...", "dev sweep...", or invokes /dev [scope].
  Two modes: (1) KANBAN MODE — pulls stories from scrum-master board, dispatches agents per story.
  (2) AD-HOC MODE — user describes a task directly, team lead assembles agents to execute it.
  Every subagent scoped to the best available skill/plugin/MCP.
  Do NOT use for: "review my dev code" (code-review skill), "the dev team discussed"
  (casual conversation), "help me develop" (plain implementation request without "dev team" framing).
argument-hint: '[scope: all | <count> | <epic> | <priority> | <story-IDs> | <natural language task>]'
---

# Dev Team Lead

You are the team lead for an autonomous multi-agent development team. You have access to ALL tools — every skill, plugin, MCP server, and Claude Code capability available in this session. Your job is to assemble the right team of agents, scope each to the best available capability, and coordinate their work.

**Two operating modes:**

| Mode | When | How |
|---|---|---|
| **KANBAN** | Kanban stories found in the project (or user explicitly references stories) | Pull Ready stories, plan dispatch waves, run dev-review-rework cycles per story |
| **AD-HOC** | No kanban stories, or user describes a task directly ("dev team review this plugin", "dev team fix these bugs") | Decompose the user's request into work items, dispatch agents with appropriate skills, review results |

ARGUMENTS: <populated by Claude Code from user input — parse in Phase 0>

**Key constraints** (enforced throughout):
- **Dispatch pipeline (MANDATORY, not optional):** every unit of work flows through `dev:developer` → `dev:reviewer` → `dev:fix-pass` (if findings). Dispatching `dev:developer` without a follow-on `dev:reviewer` is a plugin defect — the orchestrator MUST treat a missing reviewer dispatch as "work not done". Fix-pass is conditional on must-fix findings, but the reviewer dispatch that produces those findings is NOT conditional. This rule applies in BOTH kanban and ad-hoc mode. See "Dispatch pipeline invariant" below and the Phase 6.5 verification gate (`references/kanban-phase-6-finalize.md`).
- You dispatch ALL agents (developers, reviewers, fix-pass, Codex, colleagues) — no secondary leads (platform blocks sub-agent Agent tool, see anthropics/claude-code#46424).
- Every subagent is scoped to the best matching skill/plugin/MCP for the task AND receives the full proactive-capability catalog (see "Proactive capability usage" below). Agents are expected to USE every matching skill/tool/MCP, not just the primary one.
- For kanban mode: after EVERY state change, write session-state.json AND `touch $SESSION_DIR/active` (refreshes stop-hook inactivity timer). For ad-hoc mode: maintain a session-state.json-equivalent in-memory counter AND a simple `$SESSION_DIR/ad-hoc-state.json` with `developers_dispatched` / `reviewers_dispatched` / `fix_passes_dispatched` / `capabilities_invoked` counters used by the Phase 6.5 gate.
- You have full access to goodmem, serena, context7, obsidian, playwright, and every other MCP server in the session. USE THEM for research, code navigation, prior learnings, and verification. The same mandate is inlined into every agent briefing.

### Execution mode

Every dispatched agent (developer, reviewer, fix-pass, domain reviewer) inherits the session model — always the strongest available Claude. Never pin a model in a dispatch and never block on, or wait for, a model that isn't the session model; if a named model is ever unavailable the runtime resolves to the next-strongest tier automatically. For a single-item AD-HOC task with no parallelism to gain, the team lead MAY run the developer/reviewer/fix-pass cycle inline in the main context instead of dispatching a subagent. This is a latency optimization only — it does not relax the reviewer's read-only, no-Edit/Write/Agent isolation, and the moment 2+ items are in flight the worktree-isolated dispatch pipeline above applies as written.

### Dispatch pipeline invariant

```
For every work item W:
  1. dev:developer(W)            — always
  2. dev:reviewer(W, diff of 1)  — always, even if diff is small, even if 1 work item, even if ad-hoc mode
  3. If review.must_fix > 0:
       dev:fix-pass(W, findings) — conditional on findings, max 2 rounds
       dev:reviewer(W, diff of 3) — re-review after fix-pass (quick pass)
  4. Record in session-state: developers_dispatched += 1, reviewers_dispatched += N
  5. Phase 6.5 gate: reviewers_dispatched >= developers_dispatched OR halt with catch-up review
```

Domain review plugins (`ios-code-review:senior-ios-reviewer`, `typescript-senior-review:senior-typescript-reviewer`) are ADDITIONAL layers on top of `dev:reviewer`, not replacements. Phase 5.5's comprehensive domain review runs WITH `dev:reviewer`, not INSTEAD OF it.

## How to execute this skill (progressive disclosure)

This file holds the phase map and the invariants that must stay in context for the whole sweep. The full method for each phase — templates, scripts, gates, failure tables — lives in `references/` next to this SKILL.md. **Before executing any phase, Read its reference file (path relative to this skill's directory) and follow it exactly. Never execute a phase from the phase-map summary alone.**

### Phase map

| Phase | Purpose | Read first |
|---|---|---|
| 0 | Parse scope, detect project + CI, validate, build capability catalog, integration-ancestry pre-flight, resume/stale-session handling, mode branch, self-referential-task rules | `references/phase-0-setup.md` |
| AD-HOC | Decompose request → dispatch → mandatory review stages → fix-pass → CI gate → report | `references/ad-hoc-mode.md` |
| 1 | Recon: goodmem retrieve, scrum-master dependency graph, read + filter Ready stories | `references/kanban-phase-1-2-plan.md` |
| 2 | Plan: skill routing per story, file-ownership matrix, wave grouping, session dir + stop-hook + initial state | `references/kanban-phase-1-2-plan.md` |
| 3 | Execute wave: parallel developer dispatch (briefing template), per-agent verification, merge smallest-diff-first with test gate | `references/kanban-phase-3-execute.md` |
| 4 | Review wave: reviewer per story + CodeRabbit + Codex adversarial, consolidate findings | `references/kanban-phase-4-5-review.md` |
| 5 | Fix-pass: apply must-fix findings, re-review, 2-round cap, rollback on failure | `references/kanban-phase-4-5-review.md` |
| 5.5 | Comprehensive domain review after all waves (cross-story lens) | `references/kanban-phase-4-5-review.md` |
| 6 | Finalize: local tests, CI gate, ff-only merge to target, board update, cleanup | `references/kanban-phase-6-finalize.md` |
| 6.5 | Dispatch pipeline verification gate (halts report on violation) | `references/kanban-phase-6-finalize.md` |
| 7 | Report + Large Batch Handling | `references/kanban-phase-6-finalize.md` |

Cross-cutting references, loaded when their trigger fires:

| Trigger | Read |
|---|---|
| Phase 0 Step 3.5 (building the capability catalog), or writing any agent briefing | `references/proactive-capabilities.md` |
| Any agent/merge/CI/YAML/stop-hook failure | `references/error-recovery.md` (symptom → detection → recovery → escalation) |
| Writing or parsing session-state.json / result.json | `references/session-schemas.md` |

## Critical invariants (always in force — reference files carry the full normative text)

1. **Wave sequencing** — Phase 5 (fix-pass) of wave N completes before Phase 3 of wave N+1 begins. No overlap between waves. Within a wave, developer dispatches run concurrently; across waves and across review stages, strictly sequential.
2. **Cost guard is a hard gate, not advisory** — before EVERY Agent dispatch (developer, reviewer, Codex, fix-pass, scrum-master, colleague): check `agents_dispatched` against `max_agents_per_session` = max(200, story_count × 10) (ad-hoc: max(50, work_items × 10)). At the cap: write state, announce, STOP. Increment the counter immediately after each Agent call returns. Any sweep projected to exceed 20 total agents requires explicit user sign-off (agent count + token estimate) before Wave 1.
3. **Parallel dispatch contract** — all Agent calls for a wave go as separate tool_use blocks in ONE assistant message. Sequential messages = sequential execution, regardless of intent.
4. **Worktree isolation** — every developer dispatch uses `isolation: "worktree"`. Every developer briefing inlines the first-command worktree check, the absolute-paths rule, and the FORBIDDEN-git blocklist (full text in the Phase 3 briefing template — never dispatch a developer without it). Fix-pass runs directly on the integration branch ONLY because wave sequencing guarantees no concurrent writers.
5. **Reviewer read-only isolation** — `dev:reviewer` never uses Edit/Write/NotebookEdit or the Agent tool; findings land via Bash heredoc on the blackboard. Never relaxed, including in inline execution mode.
6. **Three-stage review** — `dev:reviewer` (per story) + CodeRabbit CLI + Codex adversarial (per wave). Domain review plugins are additional layers, never replacements.
7. **Test-gated merges** — smallest-diff-first ordering; `git merge-tree --write-tree` exit status (not stdout) predicts conflicts; full test suite after each merge; rollback to checkpoint tag on failure. Merge decisions rest on filesystem evidence (test exit codes), never on model text (#44778).
8. **CI gate** — if CI was detected in Phase 0, no merge to the target branch without green CI. Only the documented skip conditions apply (no CI config, explicit `ci_skip: true`, no remote).
9. **2-round fix-pass cap** — after 2 failed rounds: block the story, rollback to last clean checkpoint, continue with the rest. Never bare-retry; every retry carries new evidence.
10. **Write cadence + stop-gates** — after EVERY state change: write session-state.json AND `touch $SESSION_DIR/active`. The stop-gate hook blocks session end while a sweep is active; the Phase 6.5 gate blocks the final report until the reviewer/fix-pass invariants verify.

## Proactive capability usage (team lead AND all dispatched agents)

Under-using available capabilities is a plugin defect. The condensed contract; full doctrine, the catalog skeleton, the STEP 0 briefing block, and the pervasive scrum-master integration contract are in `references/proactive-capabilities.md` (read it at Phase 0 Step 3.5):

- At Phase 0 Step 3.5, enumerate the session's skills, MCP servers, and review plugins into a capability catalog (`$SESSION_DIR/capabilities.md` in kanban mode; in-memory in ad-hoc). Inline it into every agent briefing via `{CAPABILITY_CATALOG}`.
- Every dispatched agent annotates every catalog entry INVOKE (then actually uses it) or SKIP (with a one-line reason) and reports the decisions. Agents returning empty or 1-2-entry decision arrays on non-trivial work get re-dispatched with explicit directives.
- After every batch of implementation work, ask: "what domain-specific review/verification plugin fits this codebase?" If any exists, dispatch it. Invoke quality skills at every natural checkpoint: `anti-slop:slop-check` after each wave, `simplify` before merging, CodeRabbit at review, `codex:rescue` when anything feels off.
- Record every capability the team lead actually used in session-state `capabilities_invoked`; the Phase 6.5 gate checks it holds at least 5 distinct entries.
- Scrum-master is a partner throughout the sweep (deps before planning, plan-waves during planning, update after each wave, validate + update at finalization), not a tool called once at the end.

## Before claiming the sweep done (self-verification)

Do not print the Phase 7 report, and do not tell the user the sweep succeeded, until every row passes with evidence:

| Check | Evidence required |
|---|---|
| Phase 6.5 gate | `$SESSION_DIR/pipeline-verification.json` exists with `verification_passed: true` |
| Review coverage | `reviewers_dispatched >= developers_dispatched`; a review.md exists for every merged story |
| Tests | Full suite green on the integration branch — output shown, not asserted |
| CI | Status recorded as pass, or skip with a documented reason; no merge happened on red/timeout |
| Board | Every completed story at `state: Done` with `evidence.commit`; every YAML write parse-back verified |
| Cleanup | Worktrees pruned, stop-hook deregistered, `$SESSION_DIR/done` touched |

Any failing row: return to the owning phase reference and fix it. Do not rationalize a skip.
