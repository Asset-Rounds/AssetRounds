# Saved agent workflows

**Active: performance**, requested by the owner on 2026-09-22, until the owner changes it. The operative files are the repository-root `AGENTS.md` and `.codex/config.toml`. Files here are saved profiles, not additional active instructions.

- Say **“restore my previous agent workflow”** or **“switch back to my previous AGENTS.md”** to return to the saved one-helper routing.
- Say **“use the performance agent workflow”** to reactivate bounded parallel work.
- No additional confirmation is needed for either requested switch. Finish any in-flight shared-file mutation safely; stop assigning new work beyond the selected cap, preserve completed work, and retain active CI originals and their sole collector.

## Exact saved originals

`20260922-before-performance/AGENTS.saved.md` and `config.saved.toml` are byte-exact local copies of the working files immediately before this switch. Their SHA-256 digests and original Git head are in that directory's `manifest.json`. Git retains the saved AGENTS bytes unchanged but may normalize the config's line endings. `validation.json` also retains the original config as base64 with its SHA-256; decode that value for a byte-exact config restore after checkout. Never overwrite the originals. The saved config already had `max_threads = 5`; the prior one-helper limit came from policy.

`performance.AGENTS.md` and `performance.config.toml` retain the performance profile for switching. Its routing section follows owner-approved updates; unrelated content remains an activation-time reference, not instructions to restore stale product or safety history.

## Safe switching procedure

1. Verify the selected snapshot hashes and inspect the current workflow section/config changes. If Git normalized the saved config, decode `validation.json`'s `exactPreviousConfig.base64` and verify its SHA-256 against the original manifest before using those bytes.
2. Replace only the `## Model routing and efficient execution` section in root `AGENTS.md` with the selected profile's corresponding section. Preserve all later unrelated product, safety, run-limit and acceptance changes. If the owner explicitly requests an exact whole-file restore, compare and report any intervening unrelated changes before overwriting them.
3. Restore only the workflow comments and `[agents]` values from the selected config. Preserve the current primary model/reasoning/speed overrides, permissions, features, plugins, secrets and other settings. Neither profile changes the current session's selected model or reasoning effort. The saved configs record activation-time `max_threads = 5`; preserve a later owner-selected capacity (currently `max_threads = 3`) unless the owner explicitly requests changing it. Performance policy permits at most four helpers, further limited by configured/session capacity; previous policy permits one.
4. Update the routing sentence in `ACTIVE_BRIEF.md` and `active.json`; validate TOML, routing consistency and unchanged unrelated sections. Fold the change into the next reviewed causal CI candidate rather than dispatching a policy-only native build. Apply the selected workflow immediately to new delegation; never reinterpret an already-running original's pinned configuration.

## Performance choices

Root remains hands-on. Use zero to four helpers, normally two when independent useful tasks are ready. Astra Extra High (`xhigh`) is the default for substantive coding, diagnosis and complete-contract semantic review until the owner changes it. High remains available for clearly bounded tasks when adequate. Astra low handles mechanical work; Luna low is limited to simple non-coding work. One independent reviewer owns the entire consequential batch after deterministic checks. No recursive delegation, duplicate investigations, standing monitoring team or duplicate CI.

The desktop collaboration tool explicitly exposes `gpt-6-astra` with low/medium/high/xhigh/max/ultra and `gpt-5.6-luna` with low/medium/high/xhigh/max; actual Astra high helper execution is retained in this task. Installed CLI0.144.5's model catalog does not list Astra, so it is not used to override desktop availability. Its full strict-config check stops on an existing user-level `features.context_management` key; this switch does not alter global config or claim that check passed.

Reuse relevant workers and the same independent reviewer with short delta-only follow-ups and existing evidence checkpoints. Reset context for a substantial workstream/routing change or costly stale history. Freeze qualified dependent candidates until adoption is ready, then qualify the actual changed bindings. Reusing a session does not guarantee prompt-cache hits or lower total token use; measure available usage and mark it unknown otherwise ([official context and caching guidance](https://developers.openai.com/api/docs/guides/agents-api/observability)).

The installed `agents.max_threads` setting is retained; newer default-subagent fields are not added. Explicit spawn model/effort takes precedence in the [official subagent documentation](https://learn.chatgpt.com/docs/agent-configuration/subagents). Runtime settings can differ by installed client, so availability and effective routing must be checked at the actual spawn boundary.

All existing safety, required tests, native/provider qualification, usage/run limits, independent review, human visual review and final-main gates remain intact. Measure results in the existing REVIEW_EFFICIENCY record; more parallelism is not proof of lower token use or faster completion.
