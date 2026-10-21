# Backup reader compatibility — owner decision, 2026-10-19

The owner approved this answer in the primary AssetRounds chat:

> Allow new backups to require the updated app (Recommended)

The question expressly required the updated app to keep importing existing backups and to preserve all history. This resolves the older-reader compatibility decision for the maximum-history backup correction; it does not select a particular codec, archive layout or version number.

The correction must remain lossless. Existing supported backup readers and their validation remain available in the updated app. The implementation must preserve history bytes, logical data and integrity, and must keep the protective size, extraction, path, validation and resource predicates. Do not truncate history, reduce required fixture content, weaken tests or increase limits to hide the failure.

Root will select the smallest suitable versioned wire representation after source analysis and independent GPT-6.1 Sol/xhigh review. The correction needs meaningful current, legacy, hostile-input and maximum-history behavior verification. This is a bounded correction to existing backup requirements, with no new app, persistence/schema reduction or feature-scope reduction.

The published integration checkpoint `10eccc3e7518e022984a57b6863fe5abd96fcfcb` stays fixed for its mandatory next pinned GitHub 3,803-method/40-partition DEVELOPMENT feedback. Keep this successor family isolated; it does not replace that feedback.

All five Phase 1 gates, genuine independent and human owner reviews, data safety, S10 quality, full V23 scope, exact-main verification and release boundaries remain. `SourceReady=false` and `releaseReady=false`. No signing or distribution is authorized.

The exact owner reply and original question are retained in `.codex-temp/resume-20261002/verification/c90-root-final-correction-composition-v1/c1541-owner-approved-new-lossless-backup-reader-compatibility-decision-v1/ROOT_OWNER_COMPATIBILITY_DECISION_AND_ISOLATED_BACKUP_FAMILY_AUTHORITY.json` (2,668 bytes; SHA-256 `ae8b04a8a712eb33cce4a1713a1e7b008e3a972c398032d53a342188d8918ebb`). Current proof of the unavoidable old representation overhead and absence of an existing compatible partition route remains in C1514 and C1521.
