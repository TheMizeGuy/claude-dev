# dev skill reference — Phases 6, 6.5, 7: Finalize, Verification gate, Report + Large Batch Handling

> Loaded on demand from `skills/dev/SKILL.md` (phase map). Read this file IN FULL before executing the phase(s) it covers — the phase-map summary alone is not executable. Cross-phase pointers resolve via the reference index in SKILL.md. Every gate, template, and blocklist in this file is normative.

## Phase 6: Finalize (KANBAN MODE)

After all waves AND the comprehensive domain review complete:

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
- `touch $SESSION_DIR/active` (final refresh before Phase 6.5 gate)

## Phase 6.5: Dispatch pipeline verification gate (MANDATORY — halts report if violated)

**This gate is non-negotiable. It runs BEFORE Phase 7. It catches the historical defect
where `/dev` invocations dispatched developers but skipped reviewers and fix-pass.**

### Step 1: Read dispatch counters

```bash
DEVELOPERS=$(jq '.agents_by_type.developer // 0' "$SESSION_DIR/session-state.json")
REVIEWERS=$(jq '.agents_by_type.reviewer // 0'  "$SESSION_DIR/session-state.json")
FIX_PASSES=$(jq '.agents_by_type.fix_pass // 0' "$SESSION_DIR/session-state.json")
CAPABILITIES=$(jq '.capabilities_invoked | length' "$SESSION_DIR/session-state.json")
```

Also read per-story review-file presence:
```bash
for story_id in $(jq -r '.stories | keys[]' "$SESSION_DIR/session-state.json"); do
  wave=$(jq -r ".stories[\"$story_id\"].wave" "$SESSION_DIR/session-state.json")
  review_file="$SESSION_DIR/wave-$wave/story-$story_id/review.md"
  [[ -f "$review_file" ]] || MISSING_REVIEWS+=("$story_id")
done
```

### Step 2: Assert the invariants

| Assertion | Failure action |
|---|---|
| `REVIEWERS >= DEVELOPERS` | Catch-up review pass (Step 3) |
| `MISSING_REVIEWS` is empty | Dispatch reviewer for each missing story |
| `CAPABILITIES >= 5` (team lead used at least 5 distinct skills/tools/MCPs) | Flag as "under-utilized team lead" in report, not a halt |
| For every merged story: `review_status != "pending"` | Dispatch reviewer for pending ones |
| For every review with must-fix findings: corresponding fix-pass-round-*.md exists | Dispatch fix-pass for missing ones |

### Step 3: Catch-up dispatch (if invariants failed)

```
Announce: "Pipeline verification gate detected {N} missing reviewers. Catch-up dispatching."

For each story in MISSING_REVIEWS:
  Dispatch dev:reviewer with full briefing (same as Phase 4 Stage 1)
  Wait for return
  Increment agents_dispatched counter

For each must-fix finding with no corresponding fix-pass:
  Dispatch dev:fix-pass with the findings
  Wait for return
  Re-dispatch dev:reviewer for re-verification
```

Each catch-up dispatch is subject to the cost guard. If the cost guard blocks catch-up, halt
with `"Cost guard blocked catch-up review. Manual intervention required: N stories missing
reviewer."` — do NOT silently skip.

### Step 4: Re-run the gate

After catch-up dispatches, re-read the counters and re-evaluate. If invariants still fail
after one catch-up round, halt finalization with a loud error message listing which
stories violated which invariants. Do NOT proceed to Phase 7 report with silent violations.

### Step 5: Record verification outcome

Write `$SESSION_DIR/pipeline-verification.json`:
```json
{
  "developers_dispatched": <N>,
  "reviewers_dispatched": <N>,
  "fix_passes_dispatched": <N>,
  "capabilities_invoked_count": <N>,
  "missing_reviews_caught_up": [<story-ids>],
  "missing_fix_passes_caught_up": [<story-ids>],
  "verification_passed": true,
  "catch_up_rounds": <0|1>
}
```

This file is the source of truth for Phase 7's reporting integrity.

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
  Reviewers: Y  (invariant: Y >= X)
  Codex: Z
  Fix-pass: W
  Scrum-master: V
  Colleagues: U
Pipeline verification: <PASS | CAUGHT_UP (N missing reviewers re-dispatched) | FAIL>
Capabilities invoked (team lead): N distinct
  Skills: <list>
  MCPs: <list>
  Review plugins: <list>
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

Per the global fan-out budget, any sweep projected to exceed 20 total agents requires explicit user sign-off (agent count + token estimate) at the Step 11 wave-plan announcement before Wave 1 dispatches.

The stop-hook's activity-based TTL (default 1 hour of INACTIVITY) handles long sweeps safely — as long as the team lead touches $SESSION_DIR/active after every state change, the hook won't release.

The agents/secondary-lead-DO-NOT-DISPATCH.md file preserves the intended future architecture for when Anthropic fixes #46424.
