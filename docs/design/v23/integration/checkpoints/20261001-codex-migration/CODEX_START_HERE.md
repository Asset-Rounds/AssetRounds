# AssetRounds — Codex-only remote source handoff (2026-10-01)

Owner requested preservation for moving from this cloud Mac to a larger Mac, and then narrowed the work to Codex only. This checkpoint saves source for remote continuation. It does not integrate unfinished app changes, resume the paused merge, claim acceptance, or replace a full evidence backup. Claude's later worktrees/history are outside this checkpoint.

## Start on the new Mac

1. Install/sign into Codex and the existing private GitHub repository with the owner's normal account. Credentials and passwords are not in this source checkpoint.
2. Keep the same home path `/Users/rentamac` if possible. Clone `https://github.com/Asset-Rounds/AssetRounds.git` into `/Users/rentamac/Developer/AssetRounds` and check out `codex/v23-s10-integration-20260910`. Do not overwrite existing work or the owner's Windows drafts.
3. Read `AGENTS.md`, `docs/design/v23/integration/ACTIVE_BRIEF.md`, `CLAUDE_HANDOFF_20261001.md` (historical Codex pause handoff despite its filename), `CURRENT_INTEGRATION.md`, `MERGE_READINESS.md`, `VERIFICATION_DUE.md`, and this checkpoint's `README.md`/`MANIFEST.json`.
4. Inspect the checkpoint before reconstructing isolated worktrees. The saved patches are relative to the exact published base in MANIFEST. Never apply them wholesale to main or the populated primary checkout. Recover the selected lane only into a fresh isolated source checkout at that base. Verify the gzip SHA-256, decompress, and use `git apply --check` before applying. A patch may be empty. Restore its paired untracked TAR only into that fresh tree after inspecting its contents.
5. Restore required local evidence separately. Install Xcode 26.6 (17F113) and the appropriate simulator using the owner's normal setup. This Mac had macOS 26.5.2 (25F84) and local iOS 26.5 (23F77). Official gates still pin GitHub Xcode 26.6 / iOS 26.2 (23C54). Local/Windows/source results do not become acceptance.

## What GitHub contains

The published integration history includes Codex's committed code, frozen V23/S10 design, records, source checkpoint patch, and Dropbox lookup files. This new save-only checkpoint additionally preserves:

- Diffs from the published base for every registered non-Claude source worktree, paired with untracked non-ignored files (excluding Finder `.DS_Store`, private evidence, and this new checkpoint itself).
- Diffs for all local `refs/codex` archived snapshots/turn captures, preserving otherwise local Codex source states without uploading native artifacts in their snapshot objects.
- Source scripts and human-readable handoffs in ignored Codex packets, as an archive, with its index. Native products, logs, trace packages, JSON configurations/manifests and synthetic/binary fixtures remain in the separate evidence backup. The source archive alone may therefore be insufficient to execute an old tooling packet.
- Original locations, object IDs, hashes and status for selecting a lane. This is a navigation/reconstruction index, not an execution/authorization ledger.

The two formerly active paths `.codex/worktrees/auxiliary-retirement-close/AssetRounds` and `.codex/worktrees/app-access-transition-tests/AssetRounds` were absent at inspection (only their parent marker files remained). Do not assume that the older brief's paths still exist. All currently retained local Codex snapshot diffs are saved. The original four-leaf auxiliary patch remains at `checkpoints/20261001/AUXILIARY_RETIREMENT_UNINTEGRATED.patch.gz` with SOURCE_CHECKPOINT.json. Do not reset or manufacture original provenance when reconstructing an archived state.

## Where the verified merge actually stands

The code/history save baseline is `cca175753e0d29b1da4b02eddb88ab75114b7353`. Accepted S10 main remains `b1d04ae5e684aa9c6807af655089efa1df8a7ed6`. All five Phase 1 gates are OPEN; `releaseReady=false`. The full V23 scope remains required. The owner asked to pause development; migration/source preservation is not a request to restart builds or dispatch gates.

The paused Codex state includes source-reviewed auxiliary-control retirement and five regressions, DEBUG/conditional nonDEBUG compilation and unit typecheck, and local CI 381/381 plus 42/42. Actual new linked Products/affected native runtime and CI-result review remain due in that recorded scope. The earlier DATA-node original failed and remains immutable under HOLD. Cold caller v3 recorded 21/27 pass, 6 failures; actual copy/export and cold qualification remain due. Any later Claude results are separate and not accepted or overwritten by this handoff.

Before resuming, obtain owner authorization and inspect the current original evidence/holds/resources. Reuse exact applicable receipts. Do not retry failing originals unchanged, duplicate unchanged suites, weaken predicates/coverage/watchdogs, edit S10 receipts/Release, advance main, sign/distribute or treat a reconstructed source tree as original runtime evidence.

## What still needs a PC/storage copy

Do not retire the old Mac just because the source checkpoint is on GitHub. To preserve Codex's evidence without deciding which originals can be discarded, transfer:

- `/Users/rentamac/AssetRounds-v23-review-evidence` (about 106 GiB).
- `/Users/rentamac/Developer/AssetRounds/.codex-temp` (about 44 GiB; includes ignored records, configurations, reviews and run results).
- `/Users/rentamac/.codex` if retaining local Codex chats/app state is desired, including hidden files and archived context. Running app databases need a consistent app-state backup; copying live SQLite/WAL files is not a certified conversation migration. Source recovery on GitHub does not require importing account credentials or replaying schedules.
- Held builds `/Users/rentamac/DD-original-transition-v1`, `DD-next-app-access-v1`, `DD-integration-checkpoint`; original worktree packets under `.codex/worktrees` and `/Users/rentamac/Documents/Codex` if not already included in the copied `.codex`/repo. Preserve any other DD under an evidence hold rather than delete it.

Use a separate `C:\MAC TRANSFER\Mac-20261001` directory; never overwrite `C:\AssetRounds-v23-s10-integration` or existing Windows evidence. Large folders are not uploaded in this Git source checkpoint. Keep transfer originals until the new Mac can read the backup.

The 233 historical artifacts already offloaded remain in Dropbox `/AssetRounds-Archive-20260930`. Lookup files `EVIDENCE_ARCHIVE_20260930.json`, `EVIDENCE_ARCHIVE_PRODUCTS_20261001.json` and its additive STATUS map immutable IDs/revisions/hashes. Recover selectively through reviewed tooling, without overwriting current evidence or replaying deletion/offload scripts.

A copied/restored artifact has new filesystem identity; it does not preserve the old host, open descriptors, process, inode or simulator qualification. Keep original records immutable and document path translation. Physical protection remains unverified/release-blocking. Owner human UI review, privacy sign-off and release decisions remain owner-only.

## Prompt for the new Codex

“Read AGENTS.md and docs/design/v23/integration/checkpoints/20261001-codex-migration/README.md and CODEX_START_HERE.md, then ACTIVE_BRIEF.md and the historical pause handoff. Inspect MANIFEST.json to locate Codex's unfinished source. Explain the current code and evidence availability before restoring one lane. Preserve the paused merge, original failures/holds and all five gates. Do not apply all patches or run builds/hosted tests until I ask to resume.”
