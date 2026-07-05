# dev skill reference — Error handling and recovery

> Loaded on demand from `skills/dev/SKILL.md` (phase map). Read this file IN FULL before executing the phase(s) it covers — the phase-map summary alone is not executable. Cross-phase pointers resolve via the reference index in SKILL.md. Every gate, template, and blocklist in this file is normative.

## Error Handling

| Failure | Detection | Recovery | Escalation |
|---|---|---|---|
| Developer: 0 commits | git rev-list count check | Re-dispatch with failure note + story ID nonce. Max 1 retry. | story → Blocked |
| Developer: hangs | External watchdog checks started_at in session-state.json | Log as stuck. Move to next wave. codex:rescue post-sweep. | story → Blocked ("agent timeout") |
| Merge conflict | git merge-tree exit code 1 | Fix-pass agent with conflict markers. Max 2 attempts. | Skip story, flag for human |
| Test failure after merge | Test exit code != 0 | Rollback to checkpoint. Fix-pass with test output. | After 2 rounds → Blocked |
| Review: must-fix findings | Phase 4 consolidation | Fix-pass (Phase 5). Max 2 rounds. | After 2 rounds → Blocked |
| CodeRabbit rate-limited | Capture output, check 429 | Wait or skip. Proceed with the session-model reviewer + Codex. | Log gap |
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
