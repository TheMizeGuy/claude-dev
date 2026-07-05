# dev skill reference — Phase 3: Execute (KANBAN MODE)

> Loaded on demand from `skills/dev/SKILL.md` (phase map). Read this file IN FULL before executing the phase(s) it covers — the phase-map summary alone is not executable. Cross-phase pointers resolve via the reference index in SKILL.md. Every gate, template, and blocklist in this file is normative.

## Phase 3: Execute (KANBAN MODE, per wave, strictly sequential)

**Invariant: Phase 5 (fix-pass) of wave N MUST complete before Phase 3 of wave N+1 begins. No overlap between waves.**

**Wave-level concurrency**: within a single wave, developer dispatches run CONCURRENTLY (see Step 3 dispatch contract). Across waves is sequential. Across review stages within a wave is sequential.

### Step 0: Scrum-master consultation (dependency/AC gate)

Before touching story state, check whether the wave needs scrum-master involvement:

| Trigger | Action |
|---|---|
| Any story in the wave has `dependencies.blocked-by` entries not marked `Done` in session-state.json | Dispatch `scrum-master:scrum-master` in `deps` mode to recompute dependency graph. If still blocked, drop the story from this wave and re-plan waves |
| Any story's ACs reference symbols, files, or APIs that grep can't find in the project | Dispatch `scrum-master:scrum-master` in `validate` mode for that story. If validate flags the story, move to Blocked and drop from this wave |
| Any story has `effort: XL` OR `acceptance` list has >5 entries | Dispatch `scrum-master:scrum-master` with a split request. Use its decomposition output as the new wave plan |

Each dispatch is subject to the cost guard (Step 2). Skip this step entirely if the wave passes all three triggers cleanly — no gratuitous scrum-master calls.

### Step 1: Move stories to In Progress

For each story in the current wave, edit its YAML frontmatter directly:

**Write-contract fields ONLY** — you may write exactly these three fields and nothing else:

| Field | Value |
|---|---|
| `state` | `In Progress` |
| `owner` | `dev-team-lead` |
| `updated` | Current date (`YYYY-MM-DD`) |

All other fields (`acceptance`, `scope`, `dependencies`, `priority`, `effort`, `epic`, `tags`) are **READ-ONLY**. Do not modify them.

**Parse-back validation** — after every YAML write:

```bash
# Read the file back and verify it round-trips
python3 -c "
import yaml, sys
with open('$STORY_FILE') as f:
    data = yaml.safe_load(f)
assert data.get('state') == 'In Progress', f'state write failed: {data.get(\"state\")}'
assert data.get('owner') == 'dev-team-lead', f'owner write failed: {data.get(\"owner\")}'
print('YAML round-trip OK')
" || echo "YAML ROUND-TRIP FAILED — fix before dispatching"
```

If round-trip fails, re-read the file, fix the YAML, and retry once. If it fails again, skip the story and add it to the errors list.

Write session-state.json. Touch `$SESSION_DIR/active`.

### Step 2: Cost guard check

**This is a hard gate, not advisory. It runs before EVERY Agent dispatch — developers, reviewers, Codex, fix-pass, scrum-master, colleagues. It runs at every dispatch site in Phases 3, 4, 5, and 6.**

```
Read agents_dispatched from session-state.json.
Compute max_agents_per_session = max(200, story_count * 10).

If agents_dispatched >= max_agents_per_session:
  1. Write session-state.json with current_phase: "cost-guard-halt"
  2. Touch $SESSION_DIR/active
  3. Announce:
     "Cost guard reached: {agents_dispatched}/{max_agents_per_session} agents dispatched.
      Session paused. To resume: /dev resume"
  4. STOP. Do NOT dispatch any more agents.
```

Every dispatch (developer, reviewer, Codex, fix-pass, scrum-master, colleague) increments `agents_dispatched` in session-state.json immediately after the Agent call returns. The counter is the source of truth for the guard.

### Step 3: Dispatch developers

Per story in the current wave, dispatch up to `max_parallel_per_wave` (default 4) developer agents.

**PARALLEL DISPATCH CONTRACT (non-negotiable):**

You MUST emit all N developer Agent calls for this wave as N separate `tool_use` blocks in a **SINGLE assistant message**. The Claude Code harness only runs Agent calls concurrently when they appear together in one message. Sequential messages = sequential execution, even if you wrote "in parallel" anywhere in your reasoning.

**DO:**
- One assistant message containing 2-4 `Agent(...)` tool_use blocks side by side
- Let them all run. Wait for the batch to return. Process all results together.

**DO NOT:**
- Emit one Agent call, wait for it, then emit the next (this is sequential).
- Write session-state.json between dispatches within the same wave (that forces serialization — you can't write state you don't yet have).
- Use `run_in_background: true` for wave agents (you need their results before merging).

**Per-story pre-dispatch gates (run BEFORE emitting the batch):**

| Gate | How | Failure handling |
|---|---|---|
| Cost guard | Check Step 2; `agents_dispatched + wave_size <= max_agents_per_session` | Halt, announce, write state |
| Routed skills populated | For each story, verify `skill_primary` from Phase 2 Step 2 is non-empty and `{ROUTED_SKILLS}` in the briefing is a concrete skill name (not literal `{ROUTED_SKILLS}`) | If empty: re-run Phase 2 Step 2 routing. Do NOT dispatch with blank skill directives |
| AC sanity | For each story, verify ACs reference symbols/files that exist (grep quickly) | If AC references unverifiable target: dispatch `scrum-master:scrum-master` in `validate` mode for that story first (cost-guarded), then re-gate |

**The batch dispatch (one message, multiple blocks):**

```
Agent({
  subagent_type: "dev:developer",
  // omit model — inherits the session model
  isolation: "worktree",
  prompt: <developer briefing for story A>
})
Agent({
  subagent_type: "dev:developer",
  // omit model — inherits the session model
  isolation: "worktree",
  prompt: <developer briefing for story B>
})
... up to max_parallel_per_wave ...
```

All blocks go in ONE assistant message. The harness dispatches them concurrently.

**PRE-DISPATCH ANNOUNCEMENT** (print BEFORE the Agent blocks, same message):

```
WAVE {N} DISPATCHING {COUNT} AGENTS
  [{story-A}] "{title}" -> {skill_primary}
  [{story-B}] "{title}" -> {skill_primary}
  ...
```

**After the batch returns** (all agents done, results in hand):

**POST-DISPATCH STATUS TABLE** (print immediately):

```
WAVE {N} RESULTS
| Story | Status | Commits | Tests | Files |
|---|---|---|---|---|
| {story-A} | success | {hash} | {pass/fail} | {count} |
| {story-B} | failed | - | - | - |
```

Then:
1. Increment `agents_dispatched` by the batch size AND `agents_by_type.developer` by the batch size.
2. Merge each returned agent's `capability_decisions` into the story's record, and union each agent's `skills_invoked` + `mcps_invoked` into the session-level `capabilities_invoked` array (deduplicated).
3. For each story, update `agent_id`, `agent_branch`, `started_at`, `completed_at`.
4. Write session-state.json ONCE for the whole batch.
5. Touch `$SESSION_DIR/active` ONCE.
6. **Capability-use check (per agent):** if any agent returned with `capability_decisions` empty or with fewer than 3 INVOKE entries on a non-trivial story, flag that story for re-dispatch with an explicit directive: `"Previous dispatch under-used capabilities. Inventory showed X available skills; you invoked Y. Re-inspect the catalog and invoke every matching capability."` Counts as a new dispatch against the cost guard.

**Branch disambiguation**: include the story ID as a nonce in each developer prompt. This mitigates anthropics/claude-code#37873 (deterministic branch-name collision on same-agent-type reruns).

#### Developer briefing template

This is the full prompt passed to each developer agent. It must be self-contained — a fresh developer agent, running on the session model, reading it cold must be able to implement the story without any external context.

Fill in all `{PLACEHOLDERS}` before dispatch. The template uses 4-backtick fences for the outer block; inner code samples use 3-backtick fences.

````
OPERATIONAL CONTEXT (non-negotiable rules — follow exactly):

== QUALITY ==
No emojis. No AI slop (filler phrases, sycophancy, hedge words). No trailing summaries.
Concise output — lead with the answer, skip preamble.
Fix code to match tests, never modify tests to match code.
Grep all callers before modifying any shared function/type/API.
Match codebase patterns exactly — search for how similar things are done first.
Preserve behavioral contracts (error strings, HTTP codes, log levels, metric names, defaults).

== STEP 0: CAPABILITY INVENTORY (BEFORE ANY WORK) ==
Your session has these skills/tools/MCPs available — you MUST enumerate and use every
applicable one. Under-use is a contract violation the team lead will reject.

{CAPABILITY_CATALOG}

Process (before writing any code):
1. Scan the catalog line by line.
2. For each entry, decide in one sentence: INVOKE (applies, will use now) OR SKIP (doesn't
   apply, reason: <one line>). No entry left unannotated.
3. Invoke every INVOKE entry via the Skill tool, the MCP tool call, or the documented CLI.
4. Record your decisions in result.json `capability_decisions` array (see template below).

Hard rule: if a skill/tool/MCP in the catalog matches your task, you are REQUIRED to use it.
Primary skill from `{ROUTED_SKILLS}` is a floor, not a ceiling — invoke additional ones
proactively. Returning with only 1-2 capabilities invoked on a non-trivial task gets you
re-dispatched with explicit directives.

== STEP 1: SEARCH KNOWLEDGE (do this FIRST, before any code) ==
Three sources, in order of specificity:

(a) GoodMem — session learnings + user preferences (cross-session knowledge)
    ```
    goodmem_memories_retrieve({
      message: "{STORY_TITLE} {STORY_SCOPE_KEYWORDS}",
      space_keys: [
        {spaceId: "<your-goodmem-learnings-space-id>"},
        {spaceId: "<your-goodmem-usercontext-space-id>"}{PROJECT_SPACE_ENTRY}
      ],
      requested_size: 15,
      fetch_memory: false,
      post_processor: {
        name: "com.goodmem.retrieval.postprocess.ChatPostProcessorFactory",
        config: { reranker_id: "<your-goodmem-reranker-id>" }
      }
    })
    ```
    Relevant hits: goodmem_memories_get({id: "<id>", include_content: true})

    UserContext carries persistent user preferences (name/nickname, git author
    identity, commit-trailer conventions, default tool/service choices, etc.).
    Always query it so you don't violate preferences the main agent already knows.

(b) Obsidian vault — canonical human-readable references
    Location: ~/Claude/vault/
    Search: mcp__obsidian__search_notes({query: "{STORY_TITLE}"})
    Direct read: mcp__obsidian__read_note({filepath: "<topic>/00 - Index.md"})

(c) Serena — project-specific architecture memory
    mcp__plugin_serena_serena__list_memories() then read_memory(name)

== STEP 2: INVOKE SKILLS (before writing any code) ==
Use the Skill tool to invoke matching process skills:
{ROUTED_SKILLS}

== STEP 3: CONTEXT7 (mandatory for library/framework code) ==
Before writing code using ANY library/framework/SDK:
```
mcp__context7__resolve-library-id
mcp__context7__query-docs
```
Never rely on training data for API syntax, config, or version-specific behavior.

== STEP 4: EXPLORE BEFORE EDITING ==
Understand existing code before editing:
- Read ./CLAUDE.md if present (project-specific rules inherit to you)
- Semantic nav: mcp__plugin_serena_serena__get_symbols_overview, find_symbol, find_referencing_symbols
- Fallback: Grep/Glob for patterns. Never edit blind.

== WORKTREE ISOLATION ==
Your FIRST Bash command must be:
```bash
pwd && git rev-parse --show-toplevel && git worktree list
```
If outputs don't agree on a .claude/worktrees/agent-* path, ABORT and report the mismatch.

CRITICAL: Use ABSOLUTE PATHS for all Read/Edit/Glob/Grep/Write calls.
Relative paths resolve to the MAIN repo, not your worktree.

FORBIDDEN git commands (shared state across worktrees — will corrupt other agents):
git stash, git checkout -- ., git reset --hard, git clean -fdx,
git notes add, git push --force on non-owned branches, git rebase on shared branches,
git lfs prune, git worktree remove --force --force on non-owned worktrees.

COMMIT before declaring success. The harness may not preserve uncommitted work.

== SESSION BLACKBOARD ==
Write your result to the session blackboard via Bash:
```bash
RESULT_DIR="{SESSION_DIR}/wave-{WAVE_NUMBER}/{STORY_ID}"
mkdir -p "$RESULT_DIR"
```
Write result.json to $RESULT_DIR when done (see RESULT.JSON TEMPLATE below).

== STORY ==
Story ID:    {STORY_ID}
Title:       {STORY_TITLE}
Priority:    {STORY_PRIORITY}
Effort:      {STORY_EFFORT}
Epic:        {STORY_EPIC}

Scope (files to touch):
{STORY_SCOPE}

Acceptance criteria (these are the spec — implementation must satisfy ALL):
{STORY_ACCEPTANCE_CRITERIA}

Dependencies (already merged):
{STORY_DEPENDENCIES}

== PROJECT CONTEXT ==
{PROJECT_CONTEXT_FROM_DEV_LOCAL_MD}

== RELATED PROJECTS ==
{CROSS_PROJECT_READ_LIST}

== BEFORE COMPLETING (all 10 steps mandatory) ==
1. Run the FULL test suite. Show the output — not just "tests pass".
2. Run the linter if configured. Fix all warnings in code you touched.
3. Self-review `git diff`: debug leftovers? accidental changes? naming inconsistent with neighbors? missing error handling?
4. Trace downstream impact: grep every caller/consumer of modified code, verify each still works.
5. COMMIT all changes. Include story ID in commit message: "{STORY_ID}: <description>".
6. Write result.json to the session blackboard (see template below).
7. Anti-slop pass: invoke `anti-slop:slop-check` skill on written code/prose.
8. Pre-claim verification: invoke `superpowers:verification-before-completion` before reporting success.
9. WRITE TO MEMORY if you learned anything non-obvious (debugged >5min, hit a gotcha, found a fix):
   ```
   goodmem_memories_create({
     space_id: "<your-goodmem-learnings-space-id>",
     content_type: "text/markdown",
     original_content: "# Title\n\n## Symptom\n...\n## Root cause\n...\n## Fix\n...",
     metadata: {"type": "learning", "topic": "{TOPIC_KEYWORD}", "date": "{TODAY}"}
   })
   ```
10. Report failures honestly. Never claim success without evidence.

== RESULT.JSON TEMPLATE ==
Write this to {SESSION_DIR}/wave-{WAVE_NUMBER}/{STORY_ID}/result.json via Bash heredoc:
```bash
cat > "{SESSION_DIR}/wave-{WAVE_NUMBER}/{STORY_ID}/result.json" << 'RESULT_EOF'
{
  "story_id": "{STORY_ID}",
  "status": "success",
  "branch": "<your worktree branch name>",
  "commit": "<full commit hash of final commit>",
  "test_output": "<test suite summary: N passed, M failed, exit code>",
  "linter_output": "<linter summary or 'no linter configured'>",
  "files_changed": ["<list of files>"],
  "diff_stat": "<+N -M>",
  "skills_invoked": ["<list of skills actually invoked with Skill tool>"],
  "mcps_invoked": ["<list of MCP servers actually used: goodmem, context7, serena, etc>"],
  "capability_decisions": [
    {"capability": "superpowers:test-driven-development", "decision": "INVOKE", "reason": "implementing new function, writing failing test first"},
    {"capability": "context7", "decision": "INVOKE", "reason": "code uses SwiftUI, need current API docs"},
    {"capability": "frontend-design:frontend-design", "decision": "SKIP", "reason": "no UI in this story"},
    {"capability": "railway:use-railway", "decision": "SKIP", "reason": "no infra changes"}
  ],
  "goodmem_written": <true|false>,
  "errors": []
}
RESULT_EOF
```
Replace placeholders with actual values before writing. If status is "failure", populate the errors array with specific failure descriptions.

CRITICAL: `capability_decisions` must contain one entry for EVERY skill/tool/MCP listed in the CAPABILITY_CATALOG. Empty or partial arrays are treated as contract violations.
````

### Step 4: Verify each agent

After each developer agent returns, verify its output before proceeding to merge:

| Check | Command / Condition | On failure |
|---|---|---|
| Has commits | `git rev-list --count {target_branch}..{agent_branch}` > 0 | Mark story as `failed-no-commits`, add to errors |
| result.json exists | `test -f $SESSION_DIR/wave-N/$STORY_ID/result.json` | Mark story as `failed-no-result`, add to errors |
| Status is success | Parse result.json, check `status == "success"` | Mark story as `failed-agent-reported`, record errors |
| Test output present | `test_output` field is non-empty | Mark story as `failed-no-tests`, add to errors |
| Commit hash matches | `git rev-parse {agent_branch}` matches result.json `commit` | Log warning (non-blocking) |

Failed stories are deferred to the fix-pass phase (Phase 5). They do NOT block other stories in the wave from merging.

Write session-state.json. Touch `$SESSION_DIR/active`.

### Step 5: Merge to integration branch

Merge verified agent branches into the integration branch. Follow these rules strictly:

**Smallest-diff-first ordering**: sort verified branches by diff size (ascending) and merge in that order. Smaller diffs have fewer conflict surfaces.

```bash
# Sort branches by diff size
for branch in "${VERIFIED_BRANCHES[@]}"; do
  size=$(git diff --shortstat "{TARGET_BRANCH}...$branch" | awk '{print $4+$6}')
  printf '%s\t%s\n' "${size:-0}" "$branch"
done | sort -n | cut -f2
```

**Per-merge protocol** (for each branch, in order):

1. **Merge-tree check** — use `git merge-tree --write-tree` **exit status** (NOT stdout) to predict conflicts:
   ```bash
   git merge-tree --write-tree "$INTEGRATION_BRANCH" "$AGENT_BRANCH"
   MERGE_STATUS=$?
   # Exit 0 = clean merge possible
   # Exit non-zero = conflicts
   ```

2. **If clean**: merge with no-ff:
   ```bash
   git checkout "$INTEGRATION_BRANCH"
   git merge --no-ff --no-edit "$AGENT_BRANCH"
   ```

3. **Test gate**: run the full test suite after the merge. If tests fail:
   ```bash
   git reset --hard "checkpoint-after-${LAST_SUCCESSFUL_BRANCH}"
   ```
   Mark the story as `failed-test-after-merge`, defer to fix-pass.

4. **Checkpoint tag** on success:
   ```bash
   git tag "checkpoint-after-${AGENT_BRANCH//\//-}"
   ```
   Record this as `checkpoint_before_current_wave` in session-state.json for rollback safety.

5. **Update session-state.json**: set the story's `commit` field, `merge_status: "merged"`. Write session-state.json. Touch `$SESSION_DIR/active`.

### Step 6: Handle conflicts

If `git merge-tree --write-tree` returns non-zero (conflict predicted):

1. Do NOT attempt the merge. Do NOT block other stories.
2. Record the story as `merge_status: "conflict-deferred"` in session-state.json.
3. Add the conflict details to the story's `errors` array: which files conflict, which other branch they conflict with.
4. Continue merging the remaining branches in order.
5. Conflicted stories are passed to Phase 5 (fix-pass) with the conflict context.

Write session-state.json. Touch `$SESSION_DIR/active`.

### Step 7: Announce wave complete

After all merges (and conflict deferrals) for the current wave:

```
"Wave {N} complete: {MERGED_COUNT} stories merged ({MERGED_IDS}).
 {CONFLICT_COUNT} conflicts deferred to fix-pass ({CONFLICT_IDS}).
 {FAILED_COUNT} agent failures ({FAILED_IDS}).
 Integration branch: {INTEGRATION_BRANCH} at {CHECKPOINT_TAG}."
```

Write session-state.json with `current_wave` incremented. Touch `$SESSION_DIR/active`.

### Step 8: Update board + re-evaluate dependencies

After each wave (not just at finalization):

1. **Update story states on the board**: for each successfully merged story, edit its YAML to `state: In Review` (not Done yet — review hasn't happened). For failed stories, update to `state: Blocked` with reason.
2. **Dispatch scrum-master in `update` mode**: regenerate the board view so it reflects current reality.
3. **Re-evaluate dependencies**: dispatch scrum-master in `deps` mode. Stories that were blocked by stories completed in THIS wave may now be unblockable. If newly unblocked stories exist:
   - Add them to future waves in the wave plan
   - Re-run Step 5 (wave grouping) for remaining stories to incorporate the newly unblocked ones
   - Announce: `"Wave {N} unblocked {COUNT} additional stories: {IDS}. Added to wave plan."`
4. Cost guard applies to each scrum-master dispatch.

This is the key to maximizing throughput: completing dependency-bearing stories early unblocks downstream work, and the team lead must detect and act on this immediately — not wait until finalization.

Proceed to Phase 4 (`references/kanban-phase-4-5-review.md`).
