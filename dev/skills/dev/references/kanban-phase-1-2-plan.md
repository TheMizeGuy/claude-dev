# dev skill reference — Phases 1-2: Recon and Plan (KANBAN MODE)

> Loaded on demand from `skills/dev/SKILL.md` (phase map). Read this file IN FULL before executing the phase(s) it covers — the phase-map summary alone is not executable. Cross-phase pointers resolve via the reference index in SKILL.md. Every gate, template, and blocklist in this file is normative.

## Phase 1: Recon (KANBAN MODE)

### Step 1: GoodMem retrieve

Query prior learnings for this task topic. Always query Learnings + UserContext; add project space if configured:

```
mcp__goodmem__goodmem_memories_retrieve({
  message: "<project name> + <scope keyword from user input>",
  space_keys: [
    {spaceId: "<your-goodmem-learnings-space-id>"},  // Learnings (always)
    {spaceId: "<your-goodmem-usercontext-space-id>"},  // UserContext (always)
    // If goodmem_space is configured in dev.local.md or scrum-master.local.md, add:
    // {spaceId: "<project-space-uuid>"}
  ],
  requested_size: 15,
  fetch_memory: false,
  post_processor: {
    name: "com.goodmem.retrieval.postprocess.ChatPostProcessorFactory",
    config: { reranker_id: "<your-goodmem-reranker-id>" }
  }
})
```

Note relevant memories for the wave-planning step (Phase 2) — especially any prior gotchas for this project.

### Step 1.5: Scrum-master dependency graph

Dispatch `scrum-master:scrum-master` in `deps` mode to get the current dependency graph as a Mermaid DAG. This tells you:
- Which stories are truly ready (all blockers Done)
- Which stories should be prioritized because they UNBLOCK other stories (dependency-bearing)
- Which stories are terminal (nothing depends on them — lower dispatch priority)

**Dependency-bearing stories get priority**: if story A blocks stories B, C, D — dispatch A first, even if it's lower priority. Completing A unlocks 3 more stories for the next wave. This maximizes throughput.

Cost guard applies. If scrum-master plugin is not installed, fall back to parsing `dependencies.blocked-by` from story YAML directly.

### Step 2: Read and filter stories

For each file matching `{BOARD_PATH}/*.md`:
1. Read the YAML frontmatter
2. Parse: `id`, `state`, `priority`, `effort`, `scope`, `acceptance`, `dependencies.blocks`, `dependencies.blocked-by` (normalize: accept both `blocked-by` and `blocked_by` as equivalent)
3. Skip files with no `id` field (not stories)

Build a story dict keyed by `id`.

### Step 3: Filter Ready + unblocked

A story is dispatchable if:
- `state == "Ready"`
- `dependencies.blocked-by` is empty OR all blockers have `state == "Done"`

### Step 4: Apply scope filter

Per the argument parsed in Phase 0 Step 1:
- `all`: no additional filter
- Integer N: take top N by priority (P0 first, then P1, ...) then effort (S first)
- Epic: filter to stories where `epic == <epic-code>`
- Priority: filter to stories where `priority == <P0|P1|P2|P3>`
- Story IDs: filter to stories whose `id` matches any ID in the list

### Step 5: Check count

If 0 stories match, report:
- "No ready stories match `<scope>`. Available Ready stories: <count>. Specific IDs: <list first 10>."
- Stop.

### Step 6: Announce

```
"Found N ready stories. Planning dispatch."
```

List the story IDs and titles. Proceed to Phase 2.

## Phase 2: Plan (KANBAN MODE)

### Step 1: Per-story domain analysis

For each story dispatchable in this sweep, extract task signals from the story YAML:
- `scope.include` glob patterns (e.g., `*.swift`, `src/**/*.ts`, `Dockerfile`)
- `acceptance` assertions (check for keywords: `xcodebuild`, `npm test`, `pytest`, `cargo test`, `go test`, `railway`, etc.)
- `tags` array
- `epic` code

Use these signals to route to the best skill/plugin/MCP in Step 2.

### Step 2: Capability routing — assign primary skill per story

Match each story against this routing catalog:

**Developer skill routing:**

| Signal | Primary skill | Also invoke |
|---|---|---|
| *.swift, *.xc*, xcodebuild | superpowers:test-driven-development | context7 (SwiftUI/UIKit) |
| *.ts, *.tsx, npm/bun | superpowers:test-driven-development | context7 (library) |
| *.tsx + component/page path | frontend-design:frontend-design | ui-ux-pro-max |
| *.py, pytest, pip/uv | superpowers:test-driven-development | context7 (library) |
| *.go, go test | superpowers:test-driven-development | context7 (library) |
| *.rs, cargo test | superpowers:test-driven-development | context7 (library) |
| *.java, *.kt, gradle/maven | superpowers:test-driven-development | context7 (library) |
| *.sql, migrations/ | superpowers:test-driven-development | context7 (ORM/DB) |
| *.yml in .github/ or CI config | No auto-dispatch — flag for human review | (skip) |
| Dockerfile, railway, infra | railway-operator:railway-op (dispatch agent) | railway:use-railway |
| anthropic SDK imports | claude-api | context7 |
| MCP server code | mcp-server-dev:build-mcp-server | context7 |
| Plugin code (.claude/ or plugins/) | plugin-dev:create-plugin | plugin-dev:* |
| Bug/failure in AC | superpowers:systematic-debugging | (always) |
| Test files only in scope | superpowers:systematic-debugging | (not TDD) |
| Any implementation (fallback) | superpowers:test-driven-development | (always) |

**Reviewer skill routing:**

| Codebase domain | Review skill |
|---|---|
| TypeScript | typescript-senior-review:review-typescript |
| iOS / Swift / SwiftUI | ios-code-review:review-ios |
| Python / Go / Rust / Java / Kotlin | superpowers:requesting-code-review (generic; CodeRabbit + Codex carry domain weight) |
| Any (fallback) | superpowers:requesting-code-review |

**Universal stack (every agent gets):**
- superpowers:test-driven-development (developers) OR superpowers:systematic-debugging (test-only scope)
- superpowers:verification-before-completion (all)
- anti-slop:slop-check (all)
- context7 for any library detected
- serena for symbol navigation
- goodmem for prior learnings (Learnings + UserContext + project space)

**MCP server routing (per story need):**

| Condition | MCP servers |
|---|---|
| Always | context7, serena, goodmem |
| Story touches UI | + playwright (visual verification) |
| Story touches infra | + railway CLI (via Bash) |
| Story touches vault | + obsidian, obsidian-tools |

Record the routing decision per story (`skill_primary`, `skill_secondary`, `mcp_servers`) — will be used in developer briefings (Phase 3).

### Step 3: Build file-ownership matrix

For each story, extract `scope.include` patterns. Resolve them to ACTUAL file lists:

```bash
# For each story, expand globs to concrete file paths
for story in stories:
  FILES=$(git ls-files -- ${story.scope.include_patterns})
  story.resolved_files = FILES
  story.resolved_dirs = unique parent directories of FILES
```

**Directory-level conflict detection** (NOT prefix-based):

Two stories conflict if they share ANY concrete file OR directory. The old prefix-based heuristic collapsed all `*.swift` stories to "repo root" — making every iOS story sequential. This is wrong. Stories touching `Sources/Networking/` and `Sources/UI/` are independent even if both are Swift.

```
For story A and story B:
  conflict = (A.resolved_dirs ∩ B.resolved_dirs) is non-empty
           OR (A.resolved_files ∩ B.resolved_files) is non-empty
```

If `scope.include` contains only a bare extension glob (`*.swift`, `*.ts`) with no directory qualifier, expand it against the actual file system to get real directories. Do NOT fall back to "repo root" — that's the bug that kills parallelism.

### Step 4: Import edge discovery (bounded)

Count total files matched by all stories' `scope.include` patterns:
```bash
TOTAL_FILES=$(... count files matched by all patterns ...)
```

**If TOTAL_FILES <= 50:**
Activate serena for the project (`mcp__plugin_serena_serena__activate_project`). For each scope.include file:
1. Use `mcp__plugin_serena_serena__find_referencing_symbols` to find imports
2. Add an import edge from the importing story to the imported file's owning story

**If TOTAL_FILES > 50:**
Skip serena calls. Use the directory-level conflict matrix only (Step 3).

**After import discovery**: release serena activation — each agent dispatched later will activate its own serena instance scoped to its context. Serena is session-scoped; holding activation during dispatch causes races.

### Step 5: Group into waves

Using the file-ownership matrix + import edges, partition stories into waves:
- Two stories CAN share a wave only if they have NO conflicting directories/files (Step 3) and no import edge (Step 4)
- Within each wave, sort by priority (P0 → P1 → P2 → P3) then by effort (S → M → L → XL, smallest-diff-first)
- Cap at `max_parallel_per_wave` (default **4** — Max-plan practical ceiling per anthropics/claude-code#44481; override via `.claude/dev.local.md`) agents per wave
- **MAXIMIZE PARALLELISM**: the goal is to pack as many non-conflicting stories per wave as possible, not to be conservative. If stories touch different directories, they go in the same wave. One-story waves are a failure of wave planning, not a safety feature.

Produce a wave plan:
```
Wave 1: [story-id-A, story-id-B, story-id-C, story-id-D]  (4 non-conflicting stories)
Wave 2: [story-id-E, story-id-F]                            (2 stories that conflict with wave 1)
...
```

**Self-check**: if the wave plan has more waves than `ceil(story_count / max_parallel_per_wave)`, the conflict detection is too aggressive. Re-examine whether the conflicts are real directory overlaps or false positives from overly broad glob patterns.

### Step 6: Large-sweep announcement

Compute total planned waves. Based on story count, announce:

| Story count | Waves (at 2/wave) | Announcement |
|---|---|---|
| 1-4 | 1-2 | "Standard sweep: N stories in M waves." |
| 5-8 | 3-4 | "Standard sweep: N stories in M waves, ~30-60 min." |
| 9-16 | 5-8 | "Large sweep: N stories in M waves. Estimated 1-2 hours. Cost guard: X agents max." |
| 17-30 | 9-15 | "Extended sweep: N stories in M waves, estimated 2-4 hours. Stop-hook inactivity TTL: 1h." |
| >30 | >15 | "30+ stories. Recommend splitting into separate /dev invocations by epic or priority tier for manageable sweeps. Continue anyway? (y/n)" |

If >30 and user declines, abort.

### Step 7: Ensure .gitignore contains .claude/dev-sessions/

```bash
if ! grep -q "^\.claude/dev-sessions/" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
  echo ".claude/dev-sessions/" >> "$PROJECT_ROOT/.gitignore"
fi
```

### Step 8: Create session directory

```bash
SESSION_DIR="$PROJECT_ROOT/.claude/dev-sessions/$CLAUDE_SESSION_ID"
mkdir -p "$SESSION_DIR"
```

### Step 9: Create session-scoped stop-hook marker

```bash
touch "$SESSION_DIR/active"
```

### Step 10: Register stop-hook

Update `.claude/settings.local.json` to register the stop-hook. Use absolute paths so it works from any CWD. The orchestrator passes `DEV_SESSION_DIR` as an env var so the hook knows which session dir to read:

```bash
# Example pseudo-JSON merge (the actual implementation reads existing settings.local.json,
# adds the Stop hook entry if missing, and writes back):
#
# {
#   "hooks": {
#     "Stop": [
#       {
#         "hooks": [{
#           "type": "command",
#           "command": "DEV_SESSION_DIR='$SESSION_DIR' ${CLAUDE_PLUGIN_ROOT}/hooks/dev-sweep-stop-gate.sh",
#           "timeout": 10000
#         }]
#       }
#     ]
#   }
# }
```

Read existing `.claude/settings.local.json` (may not exist), merge in the dev hook entry, write back. If the user has other Stop hooks already registered, preserve them — append the dev hook to the list.

**Do NOT add `permissions.allow` rules to settings.local.json.** Adding an `allow` array alongside `defaultMode: "bypassPermissions"` causes Claude Code to switch to allowlist-mode evaluation for matched tool types, prompting for every non-matching invocation. The `bypassPermissions` mode already covers all tool calls including `.claude/dev-sessions/` writes.

### Step 11: Announce wave plan

Print a table for the user:

```
Wave plan (N waves, M stories):

| Wave | Stories | Skills | Agents |
|---|---|---|---|
| 1 | MG2-NET-01, MG2-NET-02 | TDD + context7 | 2 |
| 2 | MG2-UI-03 | frontend-design | 1 |
| ... | ... | ... | ... |

Cost guard: max X agents (default: max(200, stories*10)).

Live dashboard: run in another terminal:
  ${CLAUDE_PLUGIN_ROOT}/hooks/dev-sweep-watch.sh
```

Per the global fan-out budget (≤10 agents/wave, ≤20 total per workflow/turn without sign-off), if the sweep's projected total agent count exceeds 20, this announcement is a sign-off gate: state the projected agent count + rough token estimate and get explicit user confirmation before dispatching Wave 1.

### Step 12: Initial session-state.json write

Create the initial state file:

```json
{
  "session_id": "<CLAUDE_SESSION_ID>",
  "project_root": "<PROJECT_ROOT>",
  "target_branch": "<target-branch>",
  "integration_branch": "integration-<YYYYMMDD>-<HHMM>",
  "current_wave": 0,
  "total_waves": <N>,
  "agents_dispatched": 0,
  "max_agents_per_session": <computed: max(200, story_count * 10)>,
  "checkpoint_before_current_wave": null,
  "ci": {
    "type": "<CI_TYPE from Phase 0 detection>",
    "config": "<CI_CONFIG path>",
    "has_remote": <true|false>,
    "status": "pending",
    "run_url": null,
    "fix_pass_rounds": 0
  },
  "stories": {
    "MG2-NET-01": {
      "state": "Ready",
      "wave": 1,
      "agent_id": null,
      "agent_branch": null,
      "skill": "superpowers:test-driven-development",
      "skill_secondary": ["context7"],
      "commit": null,
      "test_output": null,
      "review_status": "pending",
      "started_at": null,
      "errors": []
    },
    ...
  },
  "learnings": []
}
```

Write atomically via the Write tool to `$SESSION_DIR/session-state.json`.

### Step 13: Release serena activation

If you activated serena in Step 4, release it now (no corresponding deactivate tool exists, but avoid holding an active project at this point — each subagent will call `activate_project` with its own scope).

---

Proceed to Phase 3 (`references/kanban-phase-3-execute.md`).
