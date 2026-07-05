# Changelog

All notable changes to the `dev` plugin are documented here.

## 0.1.1

- **Model policy**: removed the pinned `model: opus` from every agent's frontmatter (`developer`, `fix-pass`, `reviewer`, `secondary-lead-DO-NOT-DISPATCH`). Agents now inherit the session model — always the strongest available Claude — instead of a hardcoded model. Rewrote "Opus 4.6" references in `plugin.json`, `marketplace.json`, `README.md`, and `skills/dev/SKILL.md` to session-model language. Added an "Execution mode" note documenting that a single-item AD-HOC task may run inline in the main context instead of dispatching, without relaxing the reviewer's read-only isolation.
- **Optimize (context-efficiency pass)**: externalized `skills/dev/SKILL.md` from a single large file into a phase-map skeleton (invariants + phase table, always loaded) plus per-phase `skills/dev/references/*.md` files (phase-0 setup, ad-hoc mode, kanban phases 1-2/3/4-5/6-7, proactive-capability doctrine, error recovery, session schemas). Cuts always-loaded context while keeping every phase's full normative text one read away.
- **Proactive capability usage**: every dispatched agent (`developer`, `reviewer`, `fix-pass`) now receives a required enumerate/decide/invoke/report workflow against the session's full capability catalog, with a documented baseline of capabilities to invoke for its role.
- **Repo hygiene**: `.gitignore` now covers `.serena/`, `.claude/`, `.anti-slop/`, `.remember/`, `node_modules/`.
- **Docs**: README rewritten with an accurate component table, a marketplace-and-clone install section matching this repo's actual layout, a worked kanban-sweep walkthrough, and a troubleshooting table. Added this CHANGELOG. `plugin.json` and `marketplace.json` `author`/`owner` set to `TheMizeGuy` (email `ben@meipath.com`).

## 0.1.0

- Initial release: autonomous multi-agent development team orchestrator.
- KANBAN mode (pulls Ready stories via a scrum-master-compatible board) and AD-HOC mode (decomposes a natural-language task directly), auto-detected from the invocation.
- Dispatch pipeline: `dev:developer` (worktree-isolated implementation) -> `dev:reviewer` (read-only spec/quality review) -> `dev:fix-pass` (rework on must-fix findings), mandatory for every work item.
- Three-stage review: per-story reviewer + CodeRabbit CLI + adversarial cross-review, plus a comprehensive domain-review stage across all waves before finalize.
- Wave planning with directory-level conflict detection (not prefix-based) to maximize parallel dispatch; smallest-diff-first merge ordering with a test gate and rollback checkpoints.
- Mandatory CI/CD gate before any merge to the target branch when a pipeline is detected.
- Session-scoped stop-hook (`dev-sweep-stop-gate.sh`) with activity-based TTL, and a live dashboard (`dev-sweep-watch.sh`) for a second terminal.
- Hard cost guard (`max(200, story_count * 10)` agents per session) checked before every dispatch.
