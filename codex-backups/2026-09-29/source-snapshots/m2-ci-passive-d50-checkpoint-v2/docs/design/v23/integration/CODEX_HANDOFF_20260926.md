# Codex handoff: V23 on S10 integration (2026-09-26)

This handoff comes from the Claude Code root session on the owner's cloud Mac. Read it after `AGENTS.md`, which is the binding working agreement (owner decisions 1–18). If anything here conflicts with `AGENTS.md`, `AGENTS.md` wins.

## 1. Goal and hard rules (summary; AGENTS.md is authoritative)

- V23 becomes the base app on top of the accepted S10 app, keeping S10's look, brand and design system: one app, one project and scheme, one writer.
- Main advances by verified phases. **Phase 1** covers platform and shell: S10 migration, the writer and journal, leases, startup recovery, backup/validate/restore/replace/Erase for every family, and the four-tab shell. Unfinished features stay hidden behind `V23PhaseGateV1`.
- Main moves only after all five gates on one frozen head:
  1. same-head full coverage sweep, every partition green;
  2. RUI1 UI evidence;
  3. one independent integration review;
  4. the owner's screenshot review;
  5. a non-force fast-forward, then exact-main verification.
  Development runs never count as gate evidence.
- Never:
  - force-push, merge commits, pull requests, or broad staging (`git add -A` / `git add .`);
  - edit `docs/design/s10/**` or `Release/**`;
  - touch signing, release, secrets, settings or accounts;
  - fabricate evidence;
  - weaken tests, predicates or watchdogs.
  Stage explicit paths only. Refresh refs before every push.
- Restricted: schema, persistence, backup, restore, migration and writer/fence changes need an independent review, and all five gates before main.
- Owner decision 14: root decides product questions the frozen `docs/design/v23` material settles, cites the evidence, and records them in CURRENT_INTEGRATION. Anything else goes to the owner.
- Owner decision 18: premium quality bar. Prefer root-cause fixes; fast, never-hanging flows; reliable data safety.
- Every consequential batch gets one independent reviewer that did not author it. Record the verdict and model in CURRENT_INTEGRATION.
- Codex routing rules (`gpt-6-astra`) in the AGENTS history apply now that work returns to Codex.

## 2. Where things are

- Branch: `codex/v23-s10-integration-20260910`. Pushed head: **`1d3c80fa`** (this handoff commit sits on top). `main` is untouched: accepted S10 main `b1d04ae5`, plus the phase history.
- Batches pushed since 2026-09-25. Each is independently reviewed and recorded in CURRENT_INTEGRATION.md:

| Commit | Batch | Content |
|---|---|---|
| e37ea967 | K | 455 private test classes made selectable; finalization Date binding; partitions by measured time |
| 3db97959 | L | Phase 1 gate native witnesses; persistence pins at v53 |
| 75533dba | M | parallel dev runs and the D90S solo tier; cheaper DEBUG diagnostics; owner decisions D1–D5; export deadlock fix |
| dc79f4e2 | N | restore receipt order; backup worker 16 MiB stack; writer-based test seeding |
| 779b21f1 | O | **S10→V23 upgrade blocker fixed**: framed layered digests, aggregate journal schema 2 (restricted) |
| 7a409d21 | Q | mutable-semantic checkpoint v2 covering all 148 kinds (restricted); fail-closed maintenance; parts-stock time |
| 27388c99 | R | restore staging-root anchoring; per-test discovery isolation; maintenance "Save photos and reports" salvage |
| 1d3c80fa | S | writer lease proven once per scope, with commits still fenced |

- Latest collected development sweep: **36218186328 at 27388c99**.
  - Coverage exact: 3,462 executed; 3,006 passed, 437 failed, 13 interrupted.
  - Trend: 2,774 → 2,969 → 2,983 → 3,006 passed.
  - Sweep 36232533297 at 1d3c80fa was running at handoff; its collector writes to `~/AssetRounds-v23-review-evidence/36232533297/`.
- Phase 1 numbers (owner decision 17), from the reviewer's triage of those 437 failures:
  - ~346 Phase-1 core (never eligible);
  - ~49 switched-off feature workflows;
  - ~41 infrastructure/anchor.
  - Root recommendation: no known-failures list; fix to green.

## 3. Finished but NOT yet reviewed or pushed

These commits exist only on local branches on the owner's Mac (`~/Developer/wt/<name>`), all based on `1d3c80fa`. They need one independent review as a combined batch (T), then integration, compile and push.

| Local branch | Commit(s) | What | Type | Local result |
|---|---|---|---|---|
| wt/c13-20260926 | 4c4fce74 | C13 post-images keyed by concurrency identity, carrying typed linkSHA256/receiptSHA256; queryExisting uses the same identity | product | V9_77 6/6 |
| wt/anchors-20260926 | d4a60543 | C27 locator, C45 and C47 activity anchors assert the exact current sets (`.search`, `NoPlanFallbackV1`) | test | 39/39 (was 24) |
| wt/clone-20260926 | 367e4854 | clone expected history projects dropped draft revisions to `restoreTombstoneSHA256`; history preserved (C52) | product, restricted restore | 26 readback failures gone; S6_4 23→19 |
| wt/perf2-20260926 | 7d893736 | one restore-generation authority per epoch read; duplicate manifest protectFile removed | product, performance | protected checks −41% |
| wt/family-20260926 | 649cb7ba, b50a0c0a | V9_104 readiness seeding through the writer; V9_55 creates test roots | test | V9_104 12→4, V9_55 8→1 |

If Codex runs on another machine, ask the owner to have these branches pushed first (for example under `review/` names), or recreate them from the descriptions above.

Integration recipe (as root did for batches M–S):
1. Cherry-pick each commit in order.
2. On a conflict in `Scripts/v23-coverage-partitions.json`, keep ours.
3. `git reset --soft <base>`.
4. Regenerate the partitions: `python3.14 Scripts/v23-coverage-partitions.py --source Scripts/v23-coverage-partitions.json --output Scripts/v23-coverage-partitions.json --timings Scripts/v23-coverage-timings.json --repack` with a resolved TMPDIR.
5. Compile, get the review, record it, commit, push.

## 4. Next work, in priority order

1. **Batch T**: review, integrate and push section 3.
2. **Journal receipt-digest family** (restricted; same pattern as the C13 fix in 4c4fce74):
   - Reinspection: the commit and typed-receipt checks (MutationJournalStoreV1 ~1483, 4521–4738) compare postimage `semanticSHA256` with domain SHAs, but postimages are hashed through `PersistedPostImageDigestBasis`, so every reinspection commit fails. V9_76 ×9, likely V9_75; fast-survey inbox has the same pattern at ~1482.
   - Package forward-fix promotion: the pointer postimage uses `concurrencyIdentity: identity` (~7662/8757), while `PackagePromotionMutationV1.mutationPostImages` (MutationReceiptV1.swift:1034) uses the mutation identity. V9_104 ×2, likely V9_32 I01.
3. **S6_4 remaining 19**: CloneRetirement/FrozenEvidence fail at invalidRestoreAuthority :16104 (directory-pin identity in retirement); golden L1894 (restore file-snapshot targetMismatch, possibly a stale expectation); C32 invalidPackage; C41 unknownDescriptor.
4. **Top Phase-1 classes** (VERIFICATION_DUE lists the families): V9_18 (12; 4 recheck CancellationError at :129), V23MutationReceiptSafety (10), V9_03 (9), S6_1 (9), V23RepetitiveCaptureSourceGraphReview (9), V10_02 (8), S4_4 (8), V10_01 (7), S3_4 (7), V9_05 (6, restore-identity), V9_08 (5), S3_1 (6).
5. **Infrastructure**: S9_1 release preflight (14; check whether it's card-time CI state under a decision-7 analogue); V9_22 localization (12, binds Phase 1); V9_54 C47 I01 :2714 (same anchor drift as d4a60543).
6. **Performance**: FiveSaga-class tests still take ~560 s locally. Profile wall time; protected-file checks are only ~18 s of it locally, but ~142 s on hosted 26.2.
7. **Then:**
   - the RUI1 UI route and Phase 1 UI evidence;
   - the owner's screenshot review (checklist in VERIFICATION_DUE, including the maintenance diagnostics and salvage states);
   - the final same-head gate sweep;
   - the integration review;
   - fast-forward main.

Open owner items: pre-gate confirmation of delegated decisions D2 and D5; the maintenance reason granularity; the replication `LocalChangeJournalV1` 16/15 version pin versus V53; the C55 reversal-restore decision; the V23 privacy sign-off.

## 5. Tooling facts (the Mac)

- Xcode 26.6 (17F113). The iOS 26.2 runtime isn't downloadable from this Xcode, so local runs use the **iOS 26.5 Simulator (development only)**. Gates run on GitHub (Xcode 26.6, iOS 26.2 23C54).
- Local compile: `xcodebuild build-for-testing -project FieldEvidenceApp.xcodeproj -scheme FieldEvidenceApp -configuration Debug -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17 Pro' -derivedDataPath ~/DD2 -jobs 8 CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO`, then `test-without-building -only-testing:FieldEvidenceAppTests/<Class>[/<method>]`.
- Pitfalls:
  - zsh doesn't word-split `$var`, so build `-only-testing` argument arrays in bash.
  - `-parallel-testing-enabled YES` with `-only-testing` runs 0 tests.
  - Use a separate DerivedData folder and Simulator per parallel run.
  - Never `git stash`: it's shared across worktrees.
- Python: `/usr/bin/python3` is 3.9 and too old. Use `/opt/homebrew/bin/python3` (3.14) with `export TMPDIR=$(cd "$TMPDIR" && pwd -P)/`.
  - Suites: `python3.14 Scripts/dev/prun.py Scripts/test-v23-native-ci.py -j 6`, and the same for `test-v23-selection-generator.py` and `Scripts/dev/test_v23_original.py`. Two real-git fixture tests fail on macOS only, from file-mode diffs.
- Hosted runs: `python3.14 Scripts/dev/v23-original.py dispatch --selection v23-shared-coverage-d50x --kind development`, then `… collect --run <id>` (sole collector). Evidence root: `~/AssetRounds-v23-review-evidence`.
  - The account runs 5 macOS jobs at once. Parallel development sweeps share those slots.
  - A full sweep takes about 4–6.5 h.
  - After test-method changes, regenerate the partitions with `--repack`.
- Every writable test fixture must seed through the canonical writer (`FieldEvidenceAppTests/TestSupport/CanonicalWriterSeedingV1`). Relaunch `validateAll` detects out-of-writer rows by design (checkpoint v2).
- Git: `gh auth setup-git` is configured. Commit identity: palatis3 with the GitHub noreply address. End commit messages with the Co-Authored-By line required by the current agent's conventions.

## 6. Records to keep current

`ACTIVE_BRIEF.md` (≤60 lines), `CURRENT_INTEGRATION.md` (one checkpoint per batch), `MERGE_READINESS.md` (phases and ledger), `VERIFICATION_DUE.md` (open obligations: the most detailed list of what's left). Fold record updates into the next real commit.
