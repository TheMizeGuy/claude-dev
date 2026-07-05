# dev skill reference — Phase 0: Parse, detect, and mode selection

> Loaded on demand from `skills/dev/SKILL.md` (phase map). Read this file IN FULL before executing the phase(s) it covers — the phase-map summary alone is not executable. Cross-phase pointers resolve via the reference index in SKILL.md. Every gate, template, and blocklist in this file is normative.

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

### Step 3.5: Build capability catalog (both modes)

Enumerate every skill, plugin, and MCP server available in this session. Source material:

1. **Skills** — read the `user-invocable skills` list that the session exposes. Categorize by tier: process (always applicable), domain (per file type), quality (always at completion).
2. **MCP servers** — list every `mcp__<server>__*` tool class visible in the session.
3. **Review plugins** — list every `<plugin>:<reviewer-agent>` subagent type visible.
4. **Language-specific plugins** — detect `typescript-senior-review`, `ios-code-review`, `api-expert`, `railway-operator`, etc. by checking for their skills in the trigger catalog.

Write the catalog to:
- **Kanban mode:** `$SESSION_DIR/capabilities.md`
- **Ad-hoc mode:** in-memory (inlined into every briefing)

Use the skeleton from `references/proactive-capabilities.md`. Fill in what's actually available in THIS session — do not hardcode from the skeleton. Plugins change between sessions.

The catalog is inlined into every subagent briefing via `{CAPABILITY_CATALOG}`. If the catalog has fewer than 10 entries, something is wrong — most Claude Code sessions have 30+ skills available.

### Step 3.6: Integration-ancestry pre-flight (MANDATORY — auto-invoked)

Before any dispatch, verify the integration branch is a superset of the default branch. This catches stale-base drift — the failure mode that landed 68 commits of a TypeScript migration against a 2-day-stale fork on a real monorepo migration sweep.

```bash
# Determine integration + default branches
INTEGRATION=$(git rev-parse --abbrev-ref HEAD)
DEFAULT=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|^refs/remotes/origin/||' || echo main)

# 1. If the project ships its own ancestry script, invoke it
if [[ -x "$PROJECT_ROOT/tools/check-integration-ancestry.sh" ]]; then
  bash "$PROJECT_ROOT/tools/check-integration-ancestry.sh" "$INTEGRATION" "$DEFAULT"
  GATE_EXIT=$?
# 2. Otherwise run the inline minimal check
else
  MISSING_COUNT=$(git log --oneline "$INTEGRATION..$DEFAULT" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$MISSING_COUNT" -gt 0 ]]; then
    echo "BLOCK: $INTEGRATION is missing $MISSING_COUNT commit(s) from $DEFAULT."
    git log --oneline "$INTEGRATION..$DEFAULT" | head -20
    echo ""
    echo "Resolve: git merge $DEFAULT into $INTEGRATION, fix conflicts, re-run."
    GATE_EXIT=1
  else
    echo "OK: $INTEGRATION ⊇ $DEFAULT"
    GATE_EXIT=0
  fi
fi

# 3. Secondary check: orphaned / unpushed feature branches (warn, don't halt)
UNPUSHED_BRANCHES=$(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads | grep -E '\[(ahead|gone)' || true)
if [[ -n "$UNPUSHED_BRANCHES" ]]; then
  echo ""
  echo "WARN: local branches not in sync with remote (may hold orphaned feature work):"
  echo "$UNPUSHED_BRANCHES"
  echo ""
  echo "  [ahead N] — N unpushed commits on this branch. Push or archive before assuming 'done'."
  echo "  [gone]     — upstream deleted. Delete the branch or re-push if work still relevant."
  echo ""
  echo "Rationale: a real migration sweep once discovered 30+ product-feature commits"
  echo "on local main that were never pushed. They were orphaned from remote history and"
  echo "invisible to the ancestry check above. A secondary audit catches this class of drift."
fi

# 4. Halt on ancestry failure (unless explicit bypass)
if [[ "$GATE_EXIT" -ne 0 ]]; then
  case "$ARGUMENTS" in
    *--force-ancestry-bypass*)
      echo ""
      echo "BYPASSED (--force-ancestry-bypass). Operator accepts divergence."
      ;;
    *)
      echo ""
      echo "HALT. Ancestry gate failed. Pass --force-ancestry-bypass if divergence is intentional,"
      echo "or merge default into integration and re-run /dev."
      exit 1
      ;;
  esac
fi
```

Project-level customization: projects that want a stricter or custom ancestry policy ship their own `tools/check-integration-ancestry.sh` (add orphaned-branch guidance there if your team wants it). The plugin auto-invokes it when present.

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

**If KANBAN MODE**: read `references/kanban-phase-1-2-plan.md`, then proceed to Phase 1 (Recon).

**If AD-HOC MODE**: skip Phases 1-2 (kanban-specific). Read `references/ad-hoc-mode.md` and execute its workflow.

### Self-referential tasks

When the task scope includes this plugin's own files (`${CLAUDE_PLUGIN_ROOT}/**`):

- Use `general-purpose` reviewer or `codex:rescue` rather than `dev:reviewer` (avoid re-entry where the dev plugin reviews itself)
- Do NOT use `dev:developer` with `isolation: "worktree"` to edit plugin files — use `general-purpose` agents or edit directly on the main filesystem (the plugin is not git-tracked, so worktree isolation provides no real benefit and risks confusion)
- Warn the user: "Plugin changes take effect on the next /dev invocation (session restart may be required for frontmatter changes)"
