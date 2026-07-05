# dev skill reference — Session state schemas

> Loaded on demand from `skills/dev/SKILL.md` (phase map). Read this file IN FULL before executing the phase(s) it covers — the phase-map summary alone is not executable. Cross-phase pointers resolve via the reference index in SKILL.md. Every gate, template, and blocklist in this file is normative.

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
  "agents_by_type": {
    "developer": 4,
    "reviewer": 4,
    "fix_pass": 1,
    "codex": 2,
    "scrum_master": 1,
    "colleague": 0
  },
  "capabilities_invoked": [
    "superpowers:test-driven-development",
    "superpowers:systematic-debugging",
    "superpowers:verification-before-completion",
    "context7",
    "serena",
    "goodmem",
    "typescript-senior-review:review-typescript",
    "anti-slop:slop-check",
    "coderabbit:code-review",
    "codex:rescue"
  ],
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
      "capability_decisions": [
        {"capability": "superpowers:test-driven-development", "decision": "INVOKE", "reason": "new function needs failing test first"},
        {"capability": "context7", "decision": "INVOKE", "reason": "uses URLSession API"},
        {"capability": "frontend-design", "decision": "SKIP", "reason": "no UI in story"}
      ],
      "commit": "abc1234",
      "test_output": "47 passed, 0 failed",
      "review_status": "passed",
      "review_file": ".claude/dev-sessions/<id>/wave-1/story-MG2-NET-01/review.md",
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
