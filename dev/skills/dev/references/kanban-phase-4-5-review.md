# dev skill reference — Phases 4, 5, 5.5: Review, Fix-pass, Comprehensive domain review (KANBAN MODE)

> Loaded on demand from `skills/dev/SKILL.md` (phase map). Read this file IN FULL before executing the phase(s) it covers — the phase-map summary alone is not executable. Cross-phase pointers resolve via the reference index in SKILL.md. Every gate, template, and blocklist in this file is normative.

## Phase 4: Review (KANBAN MODE, per wave, after merge)

Three review stages per wave. All three stages complete before consolidation.

### Stage 1: Spec/quality reviewer (per story, session model)

For each story in the wave, dispatch a reviewer agent with a FULL briefing — not a terse stub. The reviewer must know which domain skill to invoke and must actually call it via the Skill tool.

**Before dispatching reviewers**: look up the `skill_review` for each story from Phase 2 Step 2's reviewer routing table. This is NOT optional.

Dispatch reviewers for ALL stories in the wave as a parallel batch (same single-message contract as Phase 3 Step 3 — `references/kanban-phase-3-execute.md`):

````
Agent({
  subagent_type: "dev:reviewer",
  // omit model — inherits the session model
  prompt: "REVIEW BRIEFING

== STORY ==
Story ID: {STORY_ID}
Title: {STORY_TITLE}

== ACCEPTANCE CRITERIA (the spec — check each one) ==
{STORY_ACCEPTANCE_CRITERIA}

== DIFF TO REVIEW ==
```
{GIT_DIFF_FOR_THIS_STORY}
```

== STEP 0: CAPABILITY INVENTORY (BEFORE ANY REVIEW) ==
Your session has these skills/tools/MCPs available. You must enumerate and use every
applicable one for review — under-use is a contract violation.

{CAPABILITY_CATALOG}

Process:
1. For each capability, decide INVOKE or SKIP with a one-line reason.
2. Invoke every INVOKE entry. Review-relevant defaults: context7 (verify API usage),
   serena (trace references), goodmem (check for known issues), coderabbit:code-review
   (additional findings), anti-slop:slop-check (AI pattern scan), playwright (UI
   verification if applicable), WebSearch (CVE lookup), session-manager (mark review
   progress).
3. Record decisions in the review file under `## Capability decisions`.

== STEP 1: INVOKE DOMAIN REVIEW SKILL (MANDATORY) ==
Use the Skill tool to invoke: {REVIEW_SKILL}

This is the domain-specific review plugin for this codebase. It provides
structured review dimensions, severity ratings, and domain expertise
that a generic review cannot match. Invoke it FIRST, then layer your
own AC verification on top of its findings.

{REVIEW_SKILL} is one of:
- ios-code-review:review-ios (Swift/SwiftUI/UIKit — App Review + engineering)
- typescript-senior-review:review-typescript (TypeScript — 18 dimensions)
- superpowers:requesting-code-review (generic fallback)

== STEP 2: AC VERIFICATION ==
Check each AC assertion against the diff. Does the diff satisfy it?

== STEP 3: CODE QUALITY ==
Check: naming, patterns, error handling, test coverage, behavioral contracts.
Check for AI cheat patterns: test modification, weak assertions, debug leftovers.

== STEP 4: ADJACENT SKILLS (invoke ALL that apply) ==
- anti-slop:slop-check on the diff content
- coderabbit:code-review for AI-assisted second opinion (if not already run at wave level)
- simplify skill for reuse/clarity check
- goodmem query for similar bugs/gotchas in the codebase history
- context7 for every library API used in the diff

== OUTPUT ==
Write findings to the blackboard via Bash:
REVIEW_OUTPUT_PATH={SESSION_DIR}/wave-{WAVE}/story-{STORY_ID}/review.md

Format:
```
## Review: {STORY_ID}

### Capability decisions
| Capability | Decision | Reason |
|---|---|---|
| <every catalog entry> | INVOKE/SKIP | <one line> |

### Capabilities invoked
- <list with brief note on what each produced>

### must-fix
- [ ] <finding with file:line>

### should-fix
- [ ] <finding>

### nit
- [ ] <finding>

### AC verification
| AC | Pass? | Evidence |
|---|---|---|
```
"
})
````

**Parallel dispatch**: emit all reviewer Agent blocks for the wave in ONE message (same contract as developer dispatch). Reviewers are independent — they read different diffs.

**Before each dispatch**: run the cost guard check (Phase 3 Step 2 — `references/kanban-phase-3-execute.md`). **After the batch returns**: increment `agents_dispatched` by batch size AND `agents_by_type.reviewer` by batch size in session-state.json. Merge each reviewer's invoked capabilities into the session-level `capabilities_invoked`. For each story, set `review_status` (`passed` / `has-findings`) and `review_file` path. Touch `$SESSION_DIR/active`.

### Stage 2: CodeRabbit CLI (per wave)

```bash
cr --plain --base <checkpoint-tag-before-wave> > <SESSION_DIR>/wave-<N>/review-coderabbit.txt 2>&1
```

**CRITICAL**: use `--base <checkpoint-tag-before-wave>`, NOT `--base main`. Otherwise CodeRabbit reviews ALL prior waves too, producing duplicate findings. If CodeRabbit fails or rate-limits (429), skip it -- proceed with the session-model reviewer + Codex only. Log the gap in session-state.json.

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

**Before dispatch**: cost guard check. **After return**: increment `agents_dispatched` AND `agents_by_type.codex` by 1. Touch `$SESSION_DIR/active`.

The team lead writes Codex findings to `<SESSION_DIR>/wave-<N>/review-codex.md`.

### Consolidation

After all 3 stages complete:

1. Read review files from `<SESSION_DIR>/wave-<N>/`:
   - `story-<ID>/review.md` (per story)
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
  // omit model — inherits the session model
  prompt: "FIX-PASS BRIEFING

== STEP 0: CAPABILITY INVENTORY (BEFORE ANY FIX) ==
Your session has these skills/tools/MCPs available — use every applicable one. Fix-pass
quality depends on invoking the same capability stack as the original developer plus the
review plugins that produced the findings.

{CAPABILITY_CATALOG}

Process:
1. For each capability, decide INVOKE or SKIP with one-line reason.
2. Always invoke for fix-pass: superpowers:systematic-debugging (findings are bugs),
   superpowers:test-driven-development (write regression test if fixing a bug with no test),
   anti-slop:slop-check (post-fix), context7 (any library API touched), serena (trace
   impact of fix), goodmem (check for prior fixes of similar issues).
3. Record decisions in fix-pass-result.md under `## Capability decisions`.

== FINDINGS TO APPLY ==

MUST-FIX:
<list all must-fix findings from consolidated-findings.md with file:line>

SHOULD-FIX:
<list all should-fix findings>

Story ACs for reference:
<AC text for all stories in this wave>

Domain skill directive for this wave: {WAVE_DOMAIN_SKILL}

== CONTRACT ==
1. For each must-fix, apply the fix. Run relevant tests after each fix.
2. For each should-fix, apply if straightforward; skip if ambiguous (note as skipped
   with reason in fix-pass-result.md).
3. Run the FULL test suite after all fixes. Show output.
4. Run the linter. Fix warnings in files you touched.
5. Invoke anti-slop:slop-check on modified files.
6. Invoke superpowers:verification-before-completion before claiming done.
7. Commit: git commit -m 'fix({STORY_IDS}): address review findings'
8. Write fix-pass-result.md to {SESSION_DIR}/wave-{WAVE}/fix-pass-round-{N}.md with:
   - Capability decisions table
   - Findings table: # | status | commit-hash | notes
   - Test output
   - Skipped items with reasons
"
})
```

The fix-pass agent runs directly on the integration branch (no worktree isolation). This is safe because the wave sequencing invariant guarantees no concurrent writers.

**Before dispatch**: cost guard check (Phase 3 Step 2). **After return**: increment `agents_dispatched` AND `agents_by_type.fix_pass` by 1. Merge fix-pass's invoked capabilities into session-level `capabilities_invoked`. Touch `$SESSION_DIR/active`.

### Step 2: Re-verification

After fix-pass returns:

1. Dispatch `dev:reviewer` again for a quick re-review scoped to the must-fix findings (Stage 1 only — no CodeRabbit or Codex for the re-review, those already produced the consolidated findings). Use the same briefing contract as Phase 4 Stage 1 but include `RE_REVIEW: true` and list the specific findings to verify as resolved. After return: increment `agents_dispatched` AND `agents_by_type.reviewer` by 1.
2. If the re-review still finds must-fix items: round 2 (dispatch fix-pass again, same contract).

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

After Phase 5 completes (or is skipped), loop back to Phase 3 (`references/kanban-phase-3-execute.md`) for the next wave. When all waves are complete, proceed to Phase 5.5 (comprehensive domain review).

## Phase 5.5: Comprehensive domain review (KANBAN MODE, after all waves)

**After ALL waves complete but BEFORE Phase 6 (finalize/merge)**, run a comprehensive domain review using the appropriate review plugin. This is the whole-project lens that catches cross-story issues the per-story reviewers miss.

### Step 1: Detect the dominant domain

Look at the `skill_review` assignments from Phase 2. Pick the most-used domain review skill across all stories:

| Dominant domain | Review plugin to dispatch | Scope |
|---|---|---|
| iOS / Swift / SwiftUI | `ios-code-review:review-ios` | `diff` against target branch (reviews all changes from the sweep) |
| TypeScript | `typescript-senior-review:review-typescript` | `diff` against target branch |
| Mixed (no dominant) | Dispatch BOTH the top-2 domain plugins | Each scoped to its own file types |
| Generic only | Skip Phase 5.5 — per-story reviews + CodeRabbit + Codex already covered it |

### Step 2: Dispatch the domain review plugin

This is NOT a `dev:reviewer` agent. Dispatch the ACTUAL domain review plugin agent directly:

```
Agent({
  subagent_type: "ios-code-review:senior-ios-reviewer",   // or typescript-senior-review:senior-typescript-reviewer
  // omit model — inherits the session model
  prompt: "Comprehensive review of all changes from the dev sweep.
           Scope: diff against <target-branch> (all stories merged to integration branch).
           This is a full-project review, not a per-story review.
           Focus on cross-cutting concerns: architecture coherence, naming consistency
           across stories, shared state mutations, concurrency safety, API surface changes."
})
```

**Before dispatch**: cost guard check. **After return**: increment counter. Touch `$SESSION_DIR/active`.

### Step 3: Process domain review findings

If the domain review produces must-fix findings:
1. Dispatch `dev:fix-pass` with the domain review findings (same 2-round cap as Phase 5)
2. Re-run the domain review after fix-pass to confirm fixes
3. If still failing after 2 rounds: halt, report findings to user, do NOT proceed to Phase 6

Write domain review output to `$SESSION_DIR/review-domain-comprehensive.md`.

### Step 4: Announce

```
"Comprehensive {domain} review complete: N must-fix, N should-fix, N nits.
 {Fixed N must-fix items via fix-pass. | No must-fix items — proceeding to finalize.}"
```

After Phase 5.5 completes with zero unresolved must-fix findings, proceed to Phase 6 (`references/kanban-phase-6-finalize.md`).
