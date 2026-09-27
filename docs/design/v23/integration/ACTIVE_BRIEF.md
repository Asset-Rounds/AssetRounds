# Active integration brief — 2026-09-27

Read AGENTS.md first. This brief gives current state only. CURRENT_INTEGRATION.md retains exact batch/review/evidence history; VERIFICATION_DUE.md retains every open obligation; MERGE_READINESS.md defines the phased goal. All results below are development only.

## Authority and checkouts

- Primary: `/Users/rentamac/Developer/AssetRounds`, branch `codex/v23-s10-integration-20260910`, pushed checkpoint `074d1b79`. Main remains accepted S10 `b1d04ae5`; Phase 1 is not merge-ready.
- Live development: `/Users/rentamac/.codex/worktrees/integration-checkpoint/AssetRounds`, stale git HEAD `4a21cccb` plus authoritative newer overlay. Never reset it or transfer stale HEAD. Owner primary `.codex/config.toml` stays untouched/unstaged.
- Root alone installs, collects, commits, pushes and dispatches. Sol medium/high and optional Luna max helpers only; reuse context and actual available slots. No Astra resume.
- No force-push, history rewrite, merge commits, PRs, broad staging, signing or release. Never edit `docs/design/s10/**` or `Release/**`; preserve owner drafts, V30, Windows work and evidence.
- Local: Xcode26.6/17F113, iOS26.5/23F77. Gates: GitHub Xcode26.6/iOS26.2/23C54. Physical TMPDIR `/private/var/folders/y6/44_p71z11778jy4vnj43r3bc0000gn/T/`. DerivedData `/Users/rentamac/DD-integration-checkpoint`; six build workers on this 16GB Mac.

## Current source and live handles — inspect before acting

- Pushed074d1b79 is the reviewed102-source/five-record development checkpoint, with known failures. Later Erase/C46 source remains only in the live overlay; no current-overlay hosted run or gate evidence.
- Latest full app/all304unitSwift build PASS92.414s: `.codex-temp/m2-owner-snapshot-replacement-diagnostic-build-v1`. Its seven-selector diagnostic native ended7FAIL93.213s, exact selectors/source/products unchanged; root retained1,312artifacts/268products at `~/AssetRounds-v23-review-evidence/m2-owner-snapshot-replacement-diagnostic-v1-20260927`. C46 successor full304buildPASS30.162s/native3=2PASS1FAIL76.681s now collected1,306artifacts/268products. No live native/build remains.
- Current five-source checkpoint: BackupRestore9ef7f6bf, EraseService95f82d0f, MutationJournalfa326350, Router1052843a and V953testb0634512. Independent Sol-high composition review3d02bfa8 approves intermediate integration publication only after exact staged-record verification. Native2PASS1FAIL retains the later authority failure; new diagnostics and ownership corrections remain held in scratch.
- Isolated C05 compiler session29356 terminalPASS271.361s: `.codex-temp/m2-c05-module-typecheck-v6`, immutable snapshot `.codex-temp/m2-c05-isolated-typecheck-v6`, INPUTS8070b9a0 (1,202bound inputs/602appSwift). Prior isolatedv5 PASS276.907s applies only to that older snapshot. No C05 live installation or runtime proof.
- `.codex-temp/m2-next-bounded-composition-20260927.json` tracks handles and pending packets. Old installed packet before-hashes must not be reapplied.

## Current failure families

- Erase preactivation diagnostic first=registry-owner. Source trace shows Router and Coordinator constructed distinct Registry providers: source writer token and preparation reader belong to different owners. Preserve equality; exact writer-owned factory binding correction is in scratch.
- S6/V906 completed-abort proof reports source.tree-different around current ledger validation. V949 original-source physical proof also reports tree-different, not a scan error. These remain separate unresolved proof failures; no rebaseline or predicate relaxation.
- C46 historical secondclone/missing-receipt-negative and C32 replacement controls PASS in prior native17 (5PASS12FAIL158.512s). R01 now completes emptyInstall/clone/fork materialization, then replacement passed workspace-chain after reviewed target-frontier correction; later invalidRestoreAuthorityLine17955 remains. Same author diagnosing.
- C05 partial CASv2 received independent Sol-high approval cc3b128b for isolated typecheck only after sticky failed-close uncertainty correction. Positive cold V3 route, schema2/absent-C05 no-repair control observation, held-out scanner, publication readback, checked closure and native tests remain incomplete. Service/Intent/Router next step is scratch only; no C05 live installation.
- Other open families remain in VERIFICATION_DUE: AppAccess, broader S6/retired Erase, V949, V907 corpus, manual placement, C45/C47/C05 ownership/publication and journal/backup compatibility. Historical Search23+WholeSign7 passes and S6 golden Erase pass retain their exact scopes; they do not close broader suites.
- Manual-placement original100 request executed51 (46PASS5FAIL);49 extension owners were misqualified. Separate never-run49 supplement47PASS2FAIL. Evidence is retained truthfully as two scopes, never a single full100run.
- Unit census3,627. Historical native-CI379+selection42 passes retain prior captured inputs; subsequent source changes are not automatically covered. Cold CI route qualification remains due.

## Next milestones and reserved decisions

1. Finish source-grounded family corrections, independent review, full compile and affected development verification. Collect terminal native evidence before rebuilding products; keep unrelated work isolated.
2. Refresh exact source inventory, seal a coherent checkpoint, record failures honestly, obtain appropriate independent review, stage explicit paths and non-force push after refreshing refs.
3. Stabilize with a deliberate hosted development sweep, then freeze one candidate for all required same-head coverage, qualified critical UI, independent integration review and genuine owner screenshots/checklist. Only then non-force main fast-forward and exact-main verification.
4. Continue all remaining V23 phases before release, keeping S10 look/brand. C55 owner decision, privacy/AppStore and human review remain reserved. Physical protection UNVERIFIED/release-blocking; decision24 applies only to Phase1 functional Simulator gates. Card135 remains owner-only/skipped.

## Capacity

Last measured5.4GiB free. Reviewed164-blob APFS consolidation recovered5,173,968,896bytes plus priorS07trial31,539,200bytes; logical hashes/original ZIPs/manifests preserved. Extracted inode/birthtime/ctime/provenance differences are recorded, not metadata identity. Earlier33 diagnostic compressions retain separate records. Owner work, app data and products preserved.
