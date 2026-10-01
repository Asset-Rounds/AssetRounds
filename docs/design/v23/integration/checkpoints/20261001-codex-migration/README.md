# Codex source preservation — 2026-10-01

Owner requested remote recovery of Codex's work before moving Macs, then explicitly excluded Claude's later work. This is a save-only source checkpoint, not a finished merge, integrated feature, evidence backup or permission to resume development. All five Phase 1 gates remain open; main and releaseReady remain unchanged.

Read **CODEX_START_HERE.md** first. **MANIFEST.json** indexes 34 live non-Claude source states (primary, 28 Codex worktrees and five older Developer/wt trees) and 26 local private Git snapshot/capture refs. Each patch is relative to published base `cca175753e0d29b1da4b02eddb88ab75114b7353`, not to its original worktree HEAD. Paired TARs preserve eligible untracked files without staging their original paths.

The 43 MiB **CODEX_PRIVATE_TOOLS_AND_HANDOFFS.tar.gz** preserves 5,922 selected private source/Markdown files. **PRIVATE_TOOLS_INDEX.json** lists hashes, excluded copied production/build trees and 11 omitted oversized/credential-pattern candidates. Claude-prefixed packets are excluded. JSON configurations/manifests, binary/synthetic fixtures, raw logs, trace packages, modules and native Products remain in the separate local backup. Do not assume the source TAR is an execution-ready evidence packet or that every ignored source artifact is online.

Do not apply all saved states to the app. A fresh clone contains the integrated source; choose one unfinished lane only after reading the records. Verify its gzip hash, decompress and inspect it, then run `git apply --check` in a fresh isolated tree at the exact published base. Only then apply that selected patch. Inspect the paired untracked TAR before extracting into that fresh tree, refusing any absolute/traversal path, duplicate member or unexpected link. Do not extract over owner work. These packets reconstruct file contents; they do not reconstruct original Git object identity, worktree registration, inode, open descriptor, process or runtime qualification.

Previously documented auxiliary-retirement-close and app-access-transition-tests source directories were absent at the time of this migration. Saved local snapshot diffs and the earlier `../20261001/AUXILIARY_RETIREMENT_UNINTEGRATED.patch.gz` are recovery inputs, not authority to recreate historical evidence. Their discovery does not authorize cleanup or silent changes to an original HOLD.

## Evidence still needed

Keep `/Users/rentamac/AssetRounds-v23-review-evidence` and `/Users/rentamac/Developer/AssetRounds/.codex-temp`, plus held DD Products, local original worktree packets and review Documents. Codex chats/app state under `~/.codex` are a separate optional context backup. Do not retire the old Mac until the required large backup is available on the new Mac. The 233 historical Dropbox artifacts already offloaded stay in Dropbox; committed lookup JSON files identify selective recovery by immutable ID/revision/hash.

## Preservation verification

The source packet has SHA-256 bindings and an independent read-only GPT-6.1 Sol xhigh review recorded in CURRENT_INTEGRATION. No Swift was integrated, no app build/native test or hosted run was started, no originals were deleted, and none of these archive checks is acceptance evidence. The source checkpoint is published by an explicit-path linear non-force push on the existing integration branch; main does not advance.
