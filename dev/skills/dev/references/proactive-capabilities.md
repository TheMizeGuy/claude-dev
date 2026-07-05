# dev skill reference — Proactive capability usage (full doctrine)

> Loaded on demand from `skills/dev/SKILL.md` (phase map). Read this file IN FULL before executing the phase(s) it covers — the phase-map summary alone is not executable. Cross-phase pointers resolve via the reference index in SKILL.md. Every gate, template, and blocklist in this file is normative.

## Proactive skill/tool/MCP usage (applies to team lead AND all dispatched agents)

The dev plugin is a team lead of a TEAM that uses EVERY tool at its disposal. Under-using available capabilities is a plugin defect.

**The team lead** MUST, at session start (Phase 0), enumerate the session's available capabilities into a catalog. This catalog is then inlined into every agent briefing so subagents (which start with fresh context) know what they have access to and are obligated to use.

### Session capability catalog (enumerate once at Phase 0 Step 3.5)

Maintain the catalog in `$SESSION_DIR/capabilities.md` (kanban) or in-memory (ad-hoc):

```
== AVAILABLE SKILLS (from session context — list ALL that appear in available skills) ==
Process skills (always applicable):
  - superpowers:brainstorming, superpowers:test-driven-development,
    superpowers:systematic-debugging, superpowers:verification-before-completion,
    superpowers:writing-plans, superpowers:receiving-code-review,
    superpowers:requesting-code-review, superpowers:using-git-worktrees
Domain skills (applicable per file type):
  - frontend-design:frontend-design, ui-ux-pro-max:ui-ux-pro-max
  - typescript-senior-review:review-typescript
  - ios-code-review:review-ios (+ --team mode for large codebases)
  - claude-api (if Anthropic SDK imports present)
  - mcp-server-dev:build-mcp-server / build-mcp-app / build-mcpb
  - plugin-dev:create-plugin + component skills
  - railway:use-railway (reference), railway-operator:railway-op (execution)
  - api-expert:api-expert (+ sub-skills: design, review, debug, optimize, audit-security, migrate, deprecate, create-spec)
  - deep-research:deep-research (knowledge base work)
Quality skills (always run at completion):
  - anti-slop:anti-slop, anti-slop:slop-check
  - simplify
  - coderabbit:code-review, coderabbit:autofix
  - codex:rescue (second-opinion diagnosis)

== AVAILABLE MCP SERVERS (enumerate from available tools) ==
  - goodmem (Learnings + UserContext + project spaces)
  - context7 (mandatory for any library/framework)
  - serena (semantic code nav — prefer over grep)
  - obsidian + obsidian-tools (vault reference)
  - playwright (UI verification)
  - session-manager (milestones, context tracking)
  - [project-specific: firebase, figma, etc. if present]

== AVAILABLE REVIEW PLUGINS ==
  - dev:reviewer (this plugin — always)
  - typescript-senior-review (18 dimensions)
  - ios-code-review (App Store + engineering, [R]/[R?]/[W]/[~]/[+] tags)
  - coderabbit:code-reviewer, pr-review-toolkit, anti-slop:slop-detector
  - codex:codex-rescue (adversarial)
```

### Team lead proactive-use contract

- After every batch of implementation work, ask: **"what domain-specific review/verification plugin should I dispatch for this codebase?"** If the answer is anything other than "none exist", dispatch it. The Phase 5.5 comprehensive domain review is the floor, not the ceiling.
- Before every phase, check the catalog for applicable skills. If Phase 3 dispatches developers on Swift files, the briefing MUST include `ios-code-review:review-ios` directive even if the primary skill is TDD.
- Invoke quality skills at EVERY natural checkpoint: `anti-slop:slop-check` after each wave, `simplify` before merging, `coderabbit` at review, `codex:rescue` when anything feels off.
- Record in session-state.json the `capabilities_invoked` array — every skill/plugin/MCP the team lead actually used. Phase 6.5 verifies this isn't empty and isn't just `["goodmem", "context7"]`.

### Subagent proactive-use contract (inlined into every briefing)

Every `dev:developer`, `dev:reviewer`, `dev:fix-pass` briefing includes:

```
== STEP 0: CAPABILITY INVENTORY (BEFORE ANY WORK) ==
Your session has these skills/tools/MCPs available (inlined from team lead catalog):
{CAPABILITY_CATALOG}

REQUIRED: for every skill/tool/MCP in the catalog, decide in one sentence:
  (a) INVOKE — this applies to my task, I will use it now
  (b) SKIP — does not apply, reason: <one-line reason>
Report your decisions in result.json `capability_decisions` (or review file for reviewers).

You are required to INVOKE every skill/tool/MCP where (a) applies. Skipping an
applicable capability and not reporting why is a contract violation.
```

Agents that return with `capability_decisions` empty or `capabilities_invoked` containing only 1-2 items on a non-trivial task get flagged by the team lead as "under-used capabilities" and re-dispatched with explicit directives.

**Scrum-master integration** (pervasive — not just at finalization):
- The scrum-master plugin (`scrum-master:scrum-master`) is your partner throughout the sweep, not a tool you call once at the end.
- **Before planning**: dispatch scrum-master in `deps` mode to get the dependency graph. Use it to determine which stories to unblock first and which to defer.
- **During planning**: dispatch scrum-master in `plan-waves` mode to get its recommendation for wave ordering based on dependency chains. Incorporate its output into your wave plan (Phase 2 Step 5).
- **After each wave completes**: dispatch scrum-master in `update` mode to update story states on the board. Don't wait until Phase 6.
- **When stories finish**: update story state to `Done` with evidence immediately (not batched at the end). The board should reflect reality at every moment.
- **When stories block**: dispatch scrum-master to update the blocked story AND to re-evaluate what other stories are now unblocked by completed dependencies.
- **At finalization**: dispatch scrum-master in `validate` + `update` mode for final board sync.
- Cost guard applies to every scrum-master dispatch. But don't avoid calling it to save the counter — board accuracy and dependency awareness are worth the cost.

**Proactive skill and plugin usage** (non-negotiable):
- You are the team lead of a TEAM. A team uses every tool at its disposal. When you finish implementing iOS code, you dispatch the iOS review plugin. When you finish TypeScript code, you dispatch the TypeScript review plugin. When you touch infrastructure, you use the Railway plugin. This is not optional.
- After EVERY batch of implementation work, ask: "what domain-specific review/verification plugin should I dispatch for this codebase?" If the answer is anything other than "none exist", dispatch it.
- The per-story reviewer skill routing from Phase 2 is a FLOOR, not a ceiling. If you see a more relevant plugin or skill at runtime, use it.
