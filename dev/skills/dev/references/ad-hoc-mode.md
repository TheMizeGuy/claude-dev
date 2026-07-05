# dev skill reference — AD-HOC mode workflow

> Loaded on demand from `skills/dev/SKILL.md` (phase map). Read this file IN FULL before executing the phase(s) it covers — the phase-map summary alone is not executable. Cross-phase pointers resolve via the reference index in SKILL.md. Every gate, template, and blocklist in this file is normative.

AD-HOC MODE (chosen at Phase 0 Step 6) skips Phases 1-2 (kanban-specific). Execute the following steps instead:

1. **Recon**: query GoodMem Learnings + UserContext for the task topic. Read relevant vault sections. Activate serena for the project if applicable.

2. **Decompose**: break the user's request into discrete work items. For each:
   - Identify the task domain (same routing catalog as Phase 2 Step 2 — `references/kanban-phase-1-2-plan.md`)
   - Assign the best skill/plugin/MCP
   - Determine scope (which files/directories are affected)
   - Assign a work-item ID: `adhoc-<short-slug>-<4-char-rand>` (e.g., `adhoc-auth-fix-a3b9`). The 4-char random suffix mitigates anthropics/claude-code#37873 (deterministic branch-name collision on same-agent-type reruns) and serves as a nonce in agent prompts.
   - Define done: for implementation work, acceptance = tests pass; for review/audit work, acceptance = deliverable artifact exists at documented path.

3. **Cost guard**: maintain an in-memory counter (no session-state.json needed in ad-hoc mode). Cap at `max(50, work_items * 10)`. Check the counter BEFORE every Agent dispatch. If reached, announce `"Cost guard reached: X agents dispatched. Stopping."` and stop. Increment the counter immediately after each Agent call returns. Per the global fan-out budget, if the projected total exceeds 20 agents, announce the planned agent count + rough token estimate and get explicit user sign-off before dispatching past 20.

4. **Dispatch**: for each work item, dispatch agents using the same patterns as Phase 3 (briefing template: `references/kanban-phase-3-execute.md`):
   - Implementation work → `dev:developer` (worktree-isolated, skill-scoped briefing, work-item ID as nonce, full capability catalog inlined)
   - Investigation → `Explore` agent or `codex:rescue`
   - Infrastructure → `general-purpose` agent with `railway:use-railway` skill
   - Research → `general-purpose` agent with `deep-research:deep-research` skill or direct goodmem/vault/context7 queries

   **Every implementation work item dispatched as `dev:developer` MUST be followed by a `dev:reviewer` dispatch in step 5. There is no exit condition that skips the reviewer.**

5. **Review (MANDATORY — unconditional dispatch per work item, then scaled additional stages):**

   **Stage 1 (always, per work item):** dispatch `dev:reviewer` on the work item's diff. Use the same briefing contract as Phase 4 Stage 1 (`references/kanban-phase-4-5-review.md`). This is non-negotiable — every developer dispatch gets a reviewer dispatch. Single-work-item or small-diff is NOT an exit condition.

   **Stage 2 (scaled by total diff):** if combined diff across all work items > 50 lines OR work-item count >= 2, also run CodeRabbit CLI:
   ```bash
   cr --plain --base <target-branch> > $SESSION_DIR/review-coderabbit.txt 2>&1
   ```
   Wait for completion (3-5 min typical). If rate-limited (429), log gap, proceed with remaining stages.

   **Stage 3 (scaled by work-item count >= 3 OR any HIGH-severity finding in Stage 1/2):** dispatch `codex:codex-rescue` as adversarial reviewer with the full diff inlined. Always use this for infrastructure, security, or auth changes regardless of item count.

   **Stage 4 (domain review — invoked based on primary language, not item count):** if the project is TypeScript, dispatch `typescript-senior-review:senior-typescript-reviewer` on the diff. If iOS/Swift, dispatch `ios-code-review:senior-ios-reviewer`. Additional to Stages 1-3, not replacement.

   Consolidate findings across all stages into `$SESSION_DIR/consolidated-findings.md` before proceeding.

6. **Fix-pass (conditional on must-fix findings, same contract as Phase 5 — `references/kanban-phase-4-5-review.md`):** if consolidated findings contain must-fix items, dispatch `dev:fix-pass` directly on the main working branch. After fix-pass returns, re-dispatch `dev:reviewer` for a quick re-review. 2-round cap: if must-fix items persist after 2 fix-pass rounds, surface to the user without further attempts.

   If must-fix count is 0 after Stage 1+: skip fix-pass, but the reviewer WAS still dispatched — that's the non-negotiable invariant.

7. **CI gate** (MANDATORY if CI detected in Phase 0 Step 2, same rules as Phase 6 Step 2 — `references/kanban-phase-6-finalize.md`):
   - If `CI_TYPE != "none"` AND `HAS_REMOTE` is set AND `ci_skip` is not `true`:
     1. Push the current branch to remote
     2. Wait for CI to complete (same polling logic as Phase 6 Step 2b)
     3. If CI fails: dispatch fix-pass with CI failure logs, 2-round cap, re-push after each fix
     4. **Do NOT report success until CI is green or skipped**
   - If CI is not applicable: skip with announcement

8. **Report**: structured summary of what was done, what was reviewed, what issues were found and resolved. Include CI status: `CI: <pass|fail|skip|timeout> (<run-url>)`.

Ad-hoc mode does NOT require: kanban stories, session-state.json, stop-hook, integration branch, wave planning. It's a lighter-weight orchestration for direct tasks. Use git branches and worktrees as needed but without the full sweep infrastructure.

For complex ad-hoc tasks (>3 work items), consider creating kanban stories first via scrum-master (`/scrum-master create-stories`) and then switching to kanban mode.
