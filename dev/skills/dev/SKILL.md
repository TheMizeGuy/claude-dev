---
name: dev
description: |-
  Autonomous multi-agent development team orchestrator. Use when the user says
  "dev team work on...", "have the dev team...", "dev sweep...", or invokes /dev [scope].
  Two modes: (1) KANBAN MODE — pulls stories from scrum-master board, dispatches agents per story.
  (2) AD-HOC MODE — user describes a task directly, team lead assembles agents to execute it.
  Every subagent scoped to the best available skill/plugin/MCP.
  Do NOT use for: "review my dev code" (code-review skill), "the dev team discussed"
  (casual conversation), "help me develop" (feature-dev skill without "dev team" prefix).
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
- Delegate implementation to dev:developer or dev:fix-pass agents. You are the orchestrator — your primary tools are Agent (to dispatch), Read/Grep/Glob (to understand), Bash (for git/test operations), and Skill (to invoke capabilities). You CAN use any tool if needed, but prefer delegation for code changes.
- You dispatch ALL agents (developers, reviewers, fix-pass, Codex, colleagues) — no secondary leads (platform blocks sub-agent Agent tool, see anthropics/claude-code#46424).
- Every subagent is scoped to the best matching skill/plugin/MCP for the task.
- For kanban mode: after EVERY state change, write session-state.json AND `touch $SESSION_DIR/active` (refreshes stop-hook inactivity timer).
- You have full access to goodmem, serena, context7, obsidian, playwright, and every other MCP server in the session. USE THEM for research, code navigation, prior learnings, and verification.

## Phase 0: Parse, detect, and mode selection

### Step 1: Parse scope from ARGUMENTS

First, determine operating mode:

**KANBAN MODE triggers** (any of these):
- Empty args / `all` — sweep all Ready stories
- A single integer `N` — next N stories
- An epic code (matches `^[A-Z][A-Z0-9_-]*$`)
- `P0` / `P1` / `P2` / `P3` — priority filter
- Story IDs (match ID regex)
- User says "stories", "backlog", "sweep", "kanban"

**AD-HOC MODE triggers** (anything else):
- Natural language task description ("review this plugin", "fix the auth bug", "refactor the API layer")
- No kanban stories found in the project after Phase 0 Step 2 detection
- User explicitly describes work without referencing stories

If ambiguous, default to ad-hoc mode (it's the more flexible path).

### Step 2: Auto-detect project (run in parallel)

Gather via parallel tool calls:

1. **Project root:**
   ```bash
   git rev-parse --show-toplevel 2>/dev/null || pwd
   ```
2. **Dev config** (optional):
   ```bash
   cat .claude/dev.local.md 2>/dev/null || echo "NONE"
   ```
3. **Scrum-master config** (inherit board_path, id_prefix, goodmem_space if present):
   ```bash
   cat .claude/scrum-master.local.md 2>/dev/null || echo "NONE"
   ```
4. **Story files** (Glob in order, stop at first hit):
   - `**/Backlog/current/*.md`
   - `**/Backlog/*.md`
   - `**/stories/*.md`
   The first-hit parent directory is the detected `BOARD_PATH`.
5. **Project conventions:** Read first 200 lines of `./CLAUDE.md` if it exists.
6. **Recent context:**
   ```bash
   git log --oneline -20 2>/dev/null || echo "no git"
   ```
7. **CI/CD pipeline detection:**
   ```bash
   # Detect CI config files (check all common locations in parallel)
   CI_TYPE="none"
   CI_CONFIG=""
   if [[ -d ".github/workflows" ]] && ls .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null | head -1 > /dev/null; then
     CI_TYPE="github-actions"
     CI_CONFIG=".github/workflows/"
   elif [[ -f ".gitlab-ci.yml" ]]; then
     CI_TYPE="gitlab-ci"
     CI_CONFIG=".gitlab-ci.yml"
   elif [[ -f "Jenkinsfile" ]]; then
     CI_TYPE="jenkins"
     CI_CONFIG="Jenkinsfile"
   elif [[ -f ".circleci/config.yml" ]]; then
     CI_TYPE="circleci"
     CI_CONFIG=".circleci/config.yml"
   elif [[ -f "bitbucket-pipelines.yml" ]]; then
     CI_TYPE="bitbucket"
     CI_CONFIG="bitbucket-pipelines.yml"
   elif [[ -f ".travis.yml" ]]; then
     CI_TYPE="travis"
     CI_CONFIG=".travis.yml"
   elif [[ -f "azure-pipelines.yml" ]]; then
     CI_TYPE="azure-devops"
     CI_CONFIG="azure-pipelines.yml"
   elif [[ -f "Taskfile.yml" ]] || [[ -f "Earthfile" ]]; then
     CI_TYPE="task-or-earth"
     CI_CONFIG="Taskfile.yml or Earthfile"
   fi
   # Check for remote (needed to push integration branch for CI)
   HAS_REMOTE=$(git remote -v 2>/dev/null | head -1 || echo "")
   echo "CI_TYPE=$CI_TYPE CI_CONFIG=$CI_CONFIG HAS_REMOTE=${HAS_REMOTE:+yes}"
   ```

   Record `CI_TYPE`, `CI_CONFIG`, and `HAS_REMOTE` for the CI gate in Phase 6. Override via `ci_type` and `ci_skip` in `.claude/dev.local.md` YAML frontmatter.

   **If `CI_TYPE != "none"`, the CI gate in Phase 6 is MANDATORY.** No merge to target branch without CI green. See Phase 6 Step 2.

### Step 3: Validate

- Board path exists (directory is readable)
- At least one story file found
- Target branch exists (from dev.local.md `target_branch`, default `main` or `dev` — check which the project uses via `git branch --list`)

If validation fails, report the specific gap (no board path, no stories, missing target branch) and stop.

### Step 4: Resume check

Check for existing session dirs at `<PROJECT_ROOT>/.claude/dev-sessions/*/`:

```bash
for session in "$PROJECT_ROOT/.claude/dev-sessions"/*/; do
  [[ -d "$session" ]] || continue
  [[ -f "$session/active" ]] || continue
  # Active session found
  STATE_FILE="$session/session-state.json"
  if [[ -f "$STATE_FILE" ]]; then
    # Offer resume or cleanup
  fi
done
```

If an active session with in-progress stories is found:
- Report: "Found interrupted sweep at `<session-dir>`: N/M stories done, wave K in progress."
- Enumerate orphaned worktree branches: `git branch --list 'worktree-agent-*'`
- For each branch: `git rev-list --count <target-branch>..<branch>` to find unmerged commits
- Offer: "Resume (skip completed, re-dispatch pending)? Or clean up (delete session dir, prune worktrees)?"
- If user says "resume": load session-state.json, skip to current_wave, re-dispatch only pending/in-progress stories (they may need retry)
- If user says "clean up": delete session dir, prune worktrees matching the branch pattern, remove stop-hook registration, stop

### Step 5: Stale session cleanup

Delete any session dirs with a `done` marker older than 24 hours:

```bash
find "$PROJECT_ROOT/.claude/dev-sessions" -name done -mtime +1 -print 2>/dev/null | while read done_marker; do
  session_dir="$(dirname "$done_marker")"
  rm -rf "$session_dir"
done
```

### Step 6: Mode branch

**If KANBAN MODE**: proceed to Phase 1 (Recon) below.

**If AD-HOC MODE**: skip Phases 1-2 (kanban-specific). Instead:

1. **Recon**: query GoodMem Learnings + UserContext for the task topic. Read relevant vault sections. Activate serena for the project if applicable.

2. **Decompose**: break the user's request into discrete work items. For each:
   - Identify the task domain (same routing catalog as Phase 2 Step 2)
   - Assign the best skill/plugin/MCP
   - Determine scope (which files/directories are affected)
   - Assign a work-item ID: `adhoc-<short-slug>-<4-char-rand>` (e.g., `adhoc-auth-fix-a3b9`). The 4-char random suffix mitigates anthropics/claude-code#37873 (deterministic branch-name collision on same-agent-type reruns) and serves as a nonce in agent prompts.
   - Define done: for implementation work, acceptance = tests pass; for review/audit work, acceptance = deliverable artifact exists at documented path.

3. **Cost guard**: maintain an in-memory counter (no session-state.json needed in ad-hoc mode). Cap at `max(50, work_items * 10)`. Check the counter BEFORE every Agent dispatch. If reached, announce `"Cost guard reached: X agents dispatched. Stopping."` and stop. Increment the counter immediately after each Agent call returns.

4. **Dispatch**: for each work item, dispatch agents using the same patterns as Phase 3:
   - Implementation work → `dev:developer` (worktree-isolated, skill-scoped briefing, work-item ID as nonce)
   - Review work → `dev:reviewer` or domain-specific review plugin (typescript-senior-review, ios-code-review, etc.)
   - Investigation → `Explore` agent or `codex:rescue`
   - Infrastructure → `general-purpose` agent with `railway:use-railway` skill
   - Research → `general-purpose` agent with `deep-research:deep-research` skill or direct goodmem/vault/context7 queries

5. **Review**: scale review depth to work-item count:

   | Work items | Diff size | Review stages |
   |---|---|---|
   | 1 | <50 lines | Opus reviewer only |
   | 2-3 | any | Opus reviewer + CodeRabbit CLI |
   | 4+ | any | Full three-stage (Opus + CodeRabbit + Codex adversarial) |

   For CodeRabbit: use `cr --plain --base <target-branch>` (NOT `--base <checkpoint-tag-before-wave>` — there are no waves in ad-hoc mode).

6. **Fix-pass**: if must-fix findings exist, dispatch `dev:fix-pass` directly on the main working branch (no integration branch in ad-hoc mode — fixes apply in place). The 2-round cap from kanban mode still applies: if findings persist after 2 rounds, surface them to the user without further fix-pass attempts.

7. **CI gate** (MANDATORY if CI detected in Phase 0 Step 2, same rules as Phase 6 Step 2):
   - If `CI_TYPE != "none"` AND `HAS_REMOTE` is set AND `ci_skip` is not `true`:
     1. Push the current branch to remote
     2. Wait for CI to complete (same polling logic as Phase 6 Step 2b)
     3. If CI fails: dispatch fix-pass with CI failure logs, 2-round cap, re-push after each fix
     4. **Do NOT report success until CI is green or skipped**
   - If CI is not applicable: skip with announcement

8. **Report**: structured summary of what was done, what was reviewed, what issues were found and resolved. Include CI status: `CI: <pass|fail|skip|timeout> (<run-url>)`.

Ad-hoc mode does NOT require: kanban stories, session-state.json, stop-hook, integration branch, wave planning. It's a lighter-weight orchestration for direct tasks. Use git branches and worktrees as needed but without the full sweep infrastructure.

For complex ad-hoc tasks (>3 work items), consider creating kanban stories first via scrum-master (`/scrum-master create-stories`) and then switching to kanban mode.

### Self-referential tasks

When the task scope includes this plugin's own files (the plugin install directory, typically `<claude-home>/plugins/dev/**`):

- Use `general-purpose` reviewer or `codex:rescue` rather than `dev:reviewer` (avoid re-entry where the dev plugin reviews itself)
- Do NOT use `dev:developer` with `isolation: "worktree"` to edit plugin files — use `general-purpose` agents or edit directly on the main filesystem
- Warn the user: "Plugin changes take effect on the next /dev invocation (session restart may be required for frontmatter changes)"

---

## Phase 1: Recon (KANBAN MODE)

### Step 1: GoodMem retrieve

If GoodMem is configured in your environment, query your Learnings space (or any other configured space) for prior art on this task. Template:

```
mcp__plugin_goodmem_goodmem__goodmem_memories_retrieve({
  message: "<project name> + <scope keyword from user input>",
  space_keys: [
    {spaceId: "<your-learnings-space-uuid>"},
    // Add any other configured spaces (project-specific, user-context, etc.)
  ],
  requested_size: 15,
  fetch_memory: false,
  post_processor: {
    name: "com.goodmem.retrieval.postprocess.ChatPostProcessorFactory",
    config: { reranker_id: "<your-reranker-uuid-if-configured>" }
  }
})
```

If GoodMem is not installed, skip this step. Fall back to reading project CLAUDE.md, vault docs, or any other knowledge base your setup provides.

Note relevant memories for the wave-planning step (Phase 2) — especially any prior gotchas for this project.

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

For each story, extract `scope.include` patterns. Compute directory prefixes:
- Each pattern `foo/bar/**/*.ts` → prefix `foo/bar/`
- Each pattern `src/auth/*` → prefix `src/auth/`
- Each pattern `*.swift` → prefix is repo root (treat as root-level, high collision risk)

Two stories share a prefix (high conflict risk) if any prefix from story A is a prefix of (or equal to) any prefix from story B.

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
Skip serena calls. Use the directory-prefix heuristic only (Step 3).

**After import discovery**: release serena activation — each agent dispatched later will activate its own serena instance scoped to its context. Serena is session-scoped; holding activation during dispatch causes races.

### Step 5: Group into waves

Using the file-ownership matrix + import edges, partition stories into waves:
- Two stories CAN share a wave only if their prefix sets share NO common directory prefix (and no import edge)
- File ownership is PREFIX-BASED: new files created by a developer inherit the parent directory's ownership. If two stories could create files in the same directory, they cannot be in the same wave.
- Within each wave, sort by priority (P0 → P1 → P2 → P3) then by effort (S → M → L → XL, smallest-diff-first)
- Cap at `max_parallel_per_wave` (default **4** — Max-plan practical ceiling per anthropics/claude-code#44481; override via `.claude/dev.local.md`) agents per wave

Produce a wave plan:
```
Wave 1: [story-id-A, story-id-B]
Wave 2: [story-id-C]
Wave 3: [story-id-D, story-id-E]
...
```

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
# adds the Stop hook entry AND the dev-sessions allow rules if missing, and writes back):
#
# {
#   "permissions": {
#     "allow": [
#       "Write(./.claude/dev-sessions/**)",
#       "Edit(./.claude/dev-sessions/**)",
#       "Read(./.claude/dev-sessions/**)",
#       "Bash(touch .claude/dev-sessions/**)",
#       "Bash(mkdir -p .claude/dev-sessions/**)",
#       "Bash(rm -rf .claude/dev-sessions/**)"
#     ]
#   },
#   "hooks": {
#     "Stop": [
#       {
#         "hooks": [{
#           "type": "command",
#           "command": "DEV_SESSION_DIR='$SESSION_DIR' <plugin-install-dir>/hooks/dev-sweep-stop-gate.sh",
#           "timeout": 10000
#         }]
#       }
#     ]
#   }
# }
```

Read existing `.claude/settings.local.json` (may not exist), merge in the dev hook entry AND the allow rules for `.claude/dev-sessions/**`, write back. If the user has other Stop hooks or allow rules already registered, preserve them — append the dev entries. Deduplicate allow rules by exact-match string.

**Why the allow rules matter**: the team lead writes `session-state.json` and touches the `active` marker after every state change (dispatch, return, merge, review). If the user's global `defaultMode` is not `bypassPermissions` OR a project-level setting overrides it, each write to a new `$SESSION_ID` directory triggers a permission prompt. The explicit allow rules survive `defaultMode` overrides and cover the full lifecycle (Write, Edit, Read, touch, mkdir, rm -rf for Phase 0 Step 5 cleanup).

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
  <plugin-install-dir>/hooks/dev-sweep-watch.sh
```

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

Proceed to Phase 3.

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
  model: "opus",
  isolation: "worktree",
  prompt: <developer briefing for story A>
})
Agent({
  subagent_type: "dev:developer",
  model: "opus",
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
1. Increment `agents_dispatched` by the batch size.
2. For each story, update `agent_id`, `agent_branch`, `started_at`, `completed_at`.
3. Write session-state.json ONCE for the whole batch.
4. Touch `$SESSION_DIR/active` ONCE.

**Branch disambiguation**: include the story ID as a nonce in each developer prompt. This mitigates anthropics/claude-code#37873 (deterministic branch-name collision on same-agent-type reruns).

#### Developer briefing template

This is the full prompt passed to each developer agent. It must be self-contained — a fresh Opus developer reading it cold must be able to implement the story without any external context.

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

== STEP 1: SEARCH KNOWLEDGE (do this FIRST, before any code) ==
Three sources, in order of specificity:

(a) GoodMem — cross-session knowledge base (if configured)
    ```
    goodmem_memories_retrieve({
      message: "{STORY_TITLE} {STORY_SCOPE_KEYWORDS}",
      space_keys: [{GOODMEM_SPACE_KEYS}],
      requested_size: 15,
      fetch_memory: false,
      post_processor: {
        name: "com.goodmem.retrieval.postprocess.ChatPostProcessorFactory",
        config: { reranker_id: "{GOODMEM_RERANKER_ID_OR_OMIT}" }
      }
    })
    ```
    Relevant hits: goodmem_memories_get({id: "<id>", include_content: true})

    If your GoodMem setup includes a UserContext space, query it to pick up
    user preferences the main agent already knows. Skip this step
    entirely if GoodMem is not installed.

(b) Obsidian vault — canonical human-readable references (if configured)
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
mcp__plugin_context7_context7__resolve-library-id
mcp__plugin_context7_context7__query-docs
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
9. WRITE TO MEMORY if you learned anything non-obvious (debugged >5min, hit a gotcha, found a fix) AND the user has GoodMem (or similar memory system) configured. Template:
   ```
   goodmem_memories_create({
     space_id: "<your-learnings-space-uuid>",
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
  "skills_invoked": ["<list of skills invoked>"],
  "goodmem_written": <true|false>,
  "errors": []
}
RESULT_EOF
```
Replace placeholders with actual values before writing. If status is "failure", populate the errors array with specific failure descriptions.
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

Proceed to Phase 4.

## Phase 4: Review (KANBAN MODE, per wave, after merge)

Three review stages per wave. All three stages complete before consolidation.

### Stage 1: Opus spec/quality reviewer (per story)

For each story in the wave, dispatch a reviewer agent:

```
Agent({
  subagent_type: "dev:reviewer",
  model: "opus",
  prompt: "Review the diff for story <ID> against its ACs.
           Write findings to <SESSION_DIR>/wave-<N>/story-<ID>/review-opus.md via Bash.
           Focus: spec compliance, code quality, test coverage, behavioral contracts.
           [+ domain-specific review skill per routing table from Phase 2]
           REVIEW_OUTPUT_PATH=<SESSION_DIR>/wave-<N>/story-<ID>/review-opus.md"
})
```

**Before each dispatch**: run the cost guard check (Phase 3 Step 2). **After each return**: increment `agents_dispatched` in session-state.json. Touch `$SESSION_DIR/active`.

### Stage 2: CodeRabbit CLI (per wave)

```bash
cr --plain --base <checkpoint-tag-before-wave> > <SESSION_DIR>/wave-<N>/review-coderabbit.txt 2>&1
```

**CRITICAL**: use `--base <checkpoint-tag-before-wave>`, NOT `--base main`. Otherwise CodeRabbit reviews ALL prior waves too, producing duplicate findings. If CodeRabbit fails or rate-limits (429), skip it -- proceed with Opus + Codex only. Log the gap in session-state.json.

### Stage 3: Codex adversarial reviewer (per wave)

1. Compute the wave diff: `git diff <checkpoint-before-wave>...<checkpoint-after-last-story-in-wave>`
2. Inline the diff text in the prompt (Codex cannot read files):

```
Agent({
  subagent_type: "codex:codex-rescue",
  prompt: "Review this diff adversarially. The diff text follows:

<INLINE DIFF TEXT HERE>

Look for: test modification cheats, weak assertions, debug leftovers,
security vulnerabilities, behavioral contract violations.

Story ACs for reference:
<INLINE AC TEXT FOR ALL STORIES IN THIS WAVE>"
})
```

**Before dispatch**: cost guard check. **After return**: increment counter. Touch `$SESSION_DIR/active`.

The team lead writes Codex findings to `<SESSION_DIR>/wave-<N>/review-codex.md`.

### Consolidation

After all 3 stages complete:

1. Read review files from `<SESSION_DIR>/wave-<N>/`:
   - `story-<ID>/review-opus.md` (per story)
   - `review-coderabbit.txt` (per wave)
   - `review-codex.md` (per wave)
2. Deduplicate findings across all 3 stages.
3. Classify each finding: **must-fix** / **should-fix** / **nit**.
4. Write consolidated findings to `<SESSION_DIR>/wave-<N>/consolidated-findings.md`.
5. Update session-state.json: set `review_status` per story (`passed` or `has-findings`).
6. `touch $SESSION_DIR/active`
7. Announce: `"Review complete: N must-fix, N should-fix, N nits."`
8. If must-fix count > 0: proceed to Phase 5.
9. If must-fix count == 0: skip Phase 5, proceed to next wave (Phase 3).

## Phase 5: Fix-pass (KANBAN MODE, if needed)

**INVARIANT: fix-pass MUST complete before next wave dispatches.**

### Step 1: Dispatch fix-pass agent

```
Agent({
  subagent_type: "dev:fix-pass",
  model: "opus",
  prompt: "Apply these review findings to the integration branch.

MUST-FIX:
<list all must-fix findings from consolidated-findings.md>

SHOULD-FIX:
<list all should-fix findings>

Story ACs for reference:
<AC text for all stories in this wave>

[+ domain skill directive matching the wave's stories]

Run the full test suite after fixes. Commit: git commit -m 'fix(<story-IDs>): address review findings'"
})
```

The fix-pass agent runs directly on the integration branch (no worktree isolation). This is safe because the wave sequencing invariant guarantees no concurrent writers.

**Before dispatch**: cost guard check (Phase 3 Step 2). **After return**: increment `agents_dispatched`. Touch `$SESSION_DIR/active`.

### Step 2: Re-verification

After fix-pass returns:

1. Run Stage 1 review only (single Opus reviewer, quick check against must-fix findings).
2. If still must-fix findings after re-review: round 2 (dispatch fix-pass again).

### Step 3: 2-round cap

If still failing after 2 fix-pass rounds:

1. Move affected stories to `state: Blocked` with reason: `"Fix-pass failed after 2 rounds: <specific issues>"`.
2. Rollback integration branch to the last clean checkpoint: `git reset --hard <checkpoint-tag>`.
3. Update session-state.json with blocked status + error details.
4. `touch $SESSION_DIR/active`
5. Announce: `"Fix-pass failed for stories [X, Y]. Blocked. Rollback to checkpoint-<tag>."`
6. Continue with remaining stories / next wave.

### Step 4: Announce fix-pass result

```
"Fix-pass complete: N issues resolved, M stories blocked.
 Next: wave N+1 (or finalize if last wave)."
```

After Phase 5 completes (or is skipped), loop back to Phase 3 for the next wave. When all waves are complete, proceed to Phase 6.

## Phase 6: Finalize (KANBAN MODE)

After all waves complete:

### Step 1: Local test suite

Run the full test suite on the integration branch. If it fails, dispatch a fix-pass agent. Do NOT proceed until local tests are green.

### Step 2: CI/CD pipeline gate (MANDATORY if CI detected)

**This gate is non-negotiable. If the project has a CI/CD pipeline (detected in Phase 0 Step 2), the integration branch MUST pass CI before ANY merge to the target branch. No exceptions. No "CI is slow, let's merge anyway." No "it passed locally so it's fine."**

**Skip conditions** (only these):
- `CI_TYPE == "none"` (no CI config detected in Phase 0)
- `ci_skip: true` in `.claude/dev.local.md` (explicit user opt-out)
- `HAS_REMOTE` is empty (no git remote configured — can't push)

**If skipping**: announce `"CI gate skipped: <reason>. Proceeding with local-only verification."` and go to Step 3.

**If CI is active**: execute the following sequence:

#### 2a: Push integration branch to remote

```bash
git push -u origin <integration-branch>
```

If push fails (auth, permissions, network): announce the failure, do NOT merge, leave the integration branch for manual push. Stop finalization with `"CI gate blocked: push failed. Integration branch preserved at <branch>. Push manually and verify CI before merging."`

#### 2b: Wait for CI to complete

**GitHub Actions** (most common):

```bash
# Wait for the workflow run to appear (up to 60s — GitHub has propagation delay)
sleep 5
gh run list --branch <integration-branch> --limit 1 --json databaseId,status,conclusion

# Poll until completed (max 30 minutes)
TIMEOUT=1800
ELAPSED=0
INTERVAL=30
while true; do
  STATUS=$(gh run list --branch <integration-branch> --limit 1 --json status,conclusion --jq '.[0].status')
  if [[ "$STATUS" == "completed" ]]; then
    break
  fi
  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo "CI_TIMEOUT"
    break
  fi
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done
```

**GitLab CI**: Use `glab ci status` or the GitLab API.
**Other CI systems**: Use the appropriate CLI or poll the CI system's API.

**During the wait**: announce progress every ~2 minutes:
```
CI running on <integration-branch>... (<elapsed>s / <timeout>s)
```

#### 2c: Evaluate CI result

| CI result | Action |
|---|---|
| **All checks pass** | Announce `"CI GREEN on <integration-branch> (<run-url>). Proceeding to merge."` Proceed to Step 3 |
| **Any check fails** | Announce `"CI FAILED on <integration-branch> (<run-url>)."` Fetch failure details: `gh run view <run-id> --log-failed` (GitHub) or equivalent. Write failure summary to `$SESSION_DIR/ci-failure.md`. **Do NOT merge.** Dispatch fix-pass agent with CI failure logs as context. Re-run CI after fix. Apply 2-round cap same as Phase 5 |
| **Timeout (30 min)** | Announce `"CI timed out after 30 minutes. Integration branch preserved at <branch>. Monitor CI manually and merge when green."` **Do NOT merge.** Stop finalization |
| **No workflow triggered** | Announce `"No CI workflow triggered on <integration-branch>. Check CI config: <CI_CONFIG>."` **Do NOT merge.** This often means the workflow file has a branch filter that excludes integration branches — surface this to the user |

**CI fix-pass flow**: if CI fails, the fix-pass dispatch follows the same 2-round cap as Phase 5. After each fix-pass round:
1. Commit the fix
2. Push the updated integration branch: `git push origin <integration-branch>`
3. Wait for CI again (same polling loop)
4. If green: proceed to Step 3
5. If still failing after 2 rounds: stop finalization, preserve branch, report failure details

### Step 3: Merge to target branch

FF merge integration → target branch (`main`/`dev`):
```bash
git checkout <target-branch>
git merge --ff-only <integration-branch>
```

If not fast-forwardable: merge conflict between integration and target. Dispatch fix-pass with the conflict. After fix-pass, re-run local tests AND the CI gate (Step 2) before retrying the merge.

### Step 4: Update kanban

- For each completed story: direct YAML edit → `state: Done`, `evidence.commit: <hash>`, `evidence.test_output: <summary>`, `evidence.ci_status: <pass|skip>`, `evidence.ci_run_url: <url>`, `updated: <today>`
- Parse-back verify each YAML write
- Dispatch `scrum-master:scrum-master` (as general-purpose with inlined agent body) in `validate` mode — schema-checks all edited stories
- Dispatch `scrum-master:scrum-master` in `update` mode — regenerates board view
(Cost guard check before each dispatch)

### Step 5: Write memories

- Write goodmem learnings (anything non-obvious discovered during sweep)
- Write serena memory (if new architecture was mapped)
- If CI failed and was fixed: write a goodmem learning with the CI failure root cause

### Step 6: Clean up

- Prune worktrees: `git worktree prune --verbose`
- Remove stop-hook registration from `.claude/settings.local.json` (read, remove the dev hook entry, write back)
- Delete remote integration branch if CI passed and merge succeeded: `git push origin --delete <integration-branch>`

### Step 7: Finalize session

- Mark session done: `touch $SESSION_DIR/done`
  Session dir preserved for debugging; cleaned up on next `/dev` invocation (Phase 0 Step 5 handles stale sessions).
- Write final session-state.json with all stories at final state, including `ci_status` and `ci_run_url`
- `touch $SESSION_DIR/active` (final refresh before Phase 7 report)

## Phase 7: Report

Print a structured final summary:

```
DEV SWEEP COMPLETE

Stories completed: N/M
Stories blocked: N
  <blocked-story-id>: <reason>
  ...
Waves executed: N
Agents dispatched: N
  Developers: X
  Reviewers: Y
  Codex: Z
  Fix-pass: W
  Scrum-master: V
  Colleagues: U
Review findings resolved: N must-fix, N should-fix, N nits
CI/CD: <PASS (<run-url>) | SKIP (<reason>) | FAIL (<run-url>) | TIMEOUT>
Integration branch: <branch> merged to <target> at <commit-hash>
Session dir: <path> (preserved for debugging)
Learnings written: N goodmem memories
```

Do NOT add a trailing summary beyond this block.

## Large Batch Handling

The primary team lead handles ALL dispatching for all batch sizes. There is no hierarchical dispatch (secondary team leads are aspirational — blocked by anthropics/claude-code#46424, #31977, #47898: sub-agents never get the Agent tool in in-process mode).

For large batches (>8 stories), the team lead runs more sequential waves:

| Story count | Waves (at 2/wave) | Estimated duration | Notes |
|---|---|---|---|
| 1-4 | 1-2 | 15-30 min | Standard sweep |
| 5-8 | 3-4 | 30-60 min | Standard sweep |
| 9-16 | 5-8 | 1-2 hours | Large sweep. Cost guard: max(200, stories*10). |
| 17-30 | 9-15 | 2-4 hours | Extended sweep. Inactivity TTL: 1h. |
| >30 | >15 | 4+ hours | Recommend splitting by epic or priority tier. |

The stop-hook's activity-based TTL (default 1 hour of INACTIVITY) handles long sweeps safely — as long as the team lead touches $SESSION_DIR/active after every state change, the hook won't release.

The agents/secondary-lead-DO-NOT-DISPATCH.md file preserves the intended future architecture for when Anthropic fixes #46424.

## Error Handling

| Failure | Detection | Recovery | Escalation |
|---|---|---|---|
| Developer: 0 commits | git rev-list count check | Re-dispatch with failure note + story ID nonce. Max 1 retry. | story → Blocked |
| Developer: hangs | External watchdog checks started_at in session-state.json | Log as stuck. Move to next wave. codex:rescue post-sweep. | story → Blocked ("agent timeout") |
| Merge conflict | git merge-tree exit code 1 | Fix-pass agent with conflict markers. Max 2 attempts. | Skip story, flag for human |
| Test failure after merge | Test exit code != 0 | Rollback to checkpoint. Fix-pass with test output. | After 2 rounds → Blocked |
| Review: must-fix findings | Phase 4 consolidation | Fix-pass (Phase 5). Max 2 rounds. | After 2 rounds → Blocked |
| CodeRabbit rate-limited | Capture output, check 429 | Wait or skip. Proceed with Opus + Codex. | Log gap |
| Session reset (#44753) | session-state.json exists, context empty | Phase 0 resume: read state, skip completed, re-dispatch pending | Announce recovery |
| Compaction | Earlier wave details vanish | Read session-state.json + wave files from disk | Transparent (blackboard) |
| Fabricated consent (#44778) | System event as user-role message | Require filesystem signal for merges (test gate), not model text | All merge = test exit code |
| Cost guard triggered | agents_dispatched >= max | Stop, write state, announce with resume instructions | User increases cap, re-runs /dev |
| AC unverifiable | Test/file in AC doesn't exist | story → Blocked ("AC unverifiable: <detail>") | Skip, continue wave |
| Wrong skill routed | Compare result.json skills_invoked vs Phase 2 routing | Log to goodmem. No retry — implementation may be correct. | Observability only |
| YAML write corruption | Parse-back validation | Restore from git, retry. If still fails: scrum-master update mode. | Fall back to scrum-master |
| Stop-hook JSON parse error | PARSE_OK flag in hook script | Fail-CLOSED: block with diagnostic + touch $DONE_MARKER path | User investigates or releases |
| CI push failed | git push exit code != 0 | Announce failure, preserve integration branch | User pushes manually, verifies CI |
| CI check failed | gh run conclusion != "success" | Fetch `gh run view --log-failed`, dispatch fix-pass with CI logs | After 2 fix-pass rounds → halt finalization, preserve branch |
| CI timeout (30 min) | Polling loop exceeds TIMEOUT | Announce timeout, preserve integration branch | User monitors CI manually, merges when green |
| No CI workflow triggered | gh run list returns empty for branch | Announce gap (likely branch filter in CI config), do NOT merge | User fixes CI config or adds branch pattern |
| CI passes but merge blocked | gh pr checks or branch protection | Report protection rules, suggest PR-based merge instead of direct FF | User creates PR manually from integration branch |

### Recovery invariant

Never bare-retry. Every retry includes new evidence (error output, partial diff, test failure). Use codex:rescue for second-opinion diagnosis before re-dispatching stuck agents.

### Hung agent detection (platform gap)

Claude Code's in-harness subagent timeouts don't fire on hung agents (#44783). The team lead blocks waiting for the Agent tool call to return. Mitigation: external watchdog script (not part of this plugin — companion tool) that polls result.json file age and kills processes older than 30 min. The started_at field in session-state.json identifies which agent is stuck.

## Session State Schemas

### session-state.json

```json
{
  "session_id": "<CLAUDE_SESSION_ID>",
  "project_root": "/abs/path",
  "target_branch": "dev",
  "integration_branch": "integration-20260414-0500",
  "current_wave": 2,
  "total_waves": 4,
  "agents_dispatched": 6,
  "max_agents_per_session": 200,
  "checkpoint_before_current_wave": "checkpoint-after-wave-1",
  "stories": {
    "MG2-NET-01": {
      "state": "Done",
      "wave": 1,
      "agent_id": "a1b2c3",
      "agent_branch": "worktree-agent-a1b2c3",
      "skill": "superpowers:test-driven-development",
      "skill_secondary": ["context7"],
      "commit": "abc1234",
      "test_output": "47 passed, 0 failed",
      "review_status": "passed",
      "started_at": "2026-04-14T05:00:00Z",
      "errors": []
    }
  },
  "learnings": []
}
```

### result.json (written by developer agents)

```json
{
  "story_id": "MG2-NET-01",
  "status": "success",
  "branch": "worktree-agent-a1b2c3d4",
  "commit": "abc1234def5678",
  "test_output": "47 tests passed, 0 failed, exit 0",
  "linter_output": "0 warnings in changed files",
  "files_changed": ["src/Networking/APIClient.swift"],
  "diff_stat": "+142 -0",
  "skills_invoked": ["superpowers:test-driven-development", "context7"],
  "goodmem_written": true,
  "errors": []
}
```

### Write cadence

After EVERY state change, the team lead does TWO things:
1. Write session-state.json (atomic via Write tool)
2. `touch $SESSION_DIR/active` (refreshes stop-hook inactivity timer)

Events that trigger both:
- Agent dispatch (story → In Progress, agent_id assigned)
- Agent return (result status, commit)
- Merge (checkpoint tag)
- Review consolidation (review_status)
- Fix-pass (fix status)
- Finalization (story → Done with evidence)
