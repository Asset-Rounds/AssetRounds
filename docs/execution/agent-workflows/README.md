# Saved agent workflows

**Active: cost**, owner requested 2026-09-23. This restores the previous one-helper approach with Astra High for any justified substantive helper. Root does the work by default; zero helpers normally, at most one for required independent review or bounded work that saves enough effort to justify delegation. No Extra High helpers, standing team, model-driven CI polling or automatic effort escalation. Slower progress is acceptable to conserve usage; savings are not yet measured.

The operative files are root `AGENTS.md` and `.codex/config.toml`; `active.json` records the selection. Primary/session model, effort and speed remain the owner's choice. Owner `max_threads = 3` is retained as capacity; active-helper policy is one. Explicit `gpt-6-astra` / `high` spawning is supported by the current desktop tool catalog. Configuration semantics follow [official subagent documentation](https://learn.chatgpt.com/docs/agent-configuration/subagents); do not add unsupported settings to the installed client.

## Saved profiles

`20260922-before-performance/AGENTS.saved.md` and `config.saved.toml` remain immutable exact original snapshots. Their manifest records hashes and original head. If Git normalizes config line endings, `validation.json` retains `exactPreviousConfig.base64` for exact recovery. The saved configuration had max_threads=5; never restore that over a later owner-selected capacity.

`performance.AGENTS.md` and `performance.config.toml` retain the prior performance option; they are inactive references. Say “use the performance agent workflow” to request that routing again, or “restore my previous agent workflow” to select the one-helper approach. Later explicit effort choices still win. Do not restore stale product/safety text from either snapshot.

## Safe switching

1. Verify saved snapshot hashes and inspect the current routing delta. Back up current files without overwriting saved originals.
2. Change only active routing, related config comments, ACTIVE_BRIEF cadence and active metadata. Preserve unrelated scope, primary/session settings, permissions, plugins, owner capacity and every safety/acceptance gate. Preserve the newer qualified semantic-once/deterministic-binding policy instead of restoring repeated model endorsements.
3. Apply the policy immediately to new delegation. Finish an in-flight shared mutation safely and retain each active CI original and sole collector. Never reinterpret an original's pinned source/configuration.
4. Validate TOML, routing consistency and unchanged unrelated sections. Fold policy changes into the next causal candidate; no policy-only native build. Reuse retained evidence while its inputs remain exact. Reusing context is useful only when relevant and does not guarantee token or cache savings.

All functionality, native coverage, watchdog, independent semantic review, critical human-review and final-main gates remain binding. Track available usage and avoidable rework in the existing REVIEW_EFFICIENCY record; no monitoring agent.
