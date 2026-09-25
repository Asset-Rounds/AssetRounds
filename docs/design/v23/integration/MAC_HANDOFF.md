# Mac development handoff (2026-09-25)

Owner decisions 8 to 11 in AGENTS.md: development moves to a persistent cloud Mac (rentamac.io Mac mini M4, 16 GB, 256 GB) running Claude Code; development-run rules are relaxed; development is trunk-based after Phase 1; Bitrise Build Hub may add development and sweep capacity. Official merge and release evidence still comes only from the hosted GitHub route.

## Machine setup (owner)

1. Xcode 26.6 plus the iOS 26.2 Simulator runtime (build 23C54, matching CI). Confirm with `xcodebuild -version` and `xcrun simctl list runtimes`.
2. `brew install gh jq python`, then `gh auth login` and `git config user.name/user.email`.
3. Claude Code, started in the repository root.
4. `git clone https://github.com/Asset-Rounds/AssetRounds.git`, then `git checkout codex/v23-s10-integration-20260910`.
5. Evidence root: copy `v23-original-ledger.jsonl` and `v23-original-attempts/` from `C:\AssetRounds-v23-review-evidence` into `~/AssetRounds-v23-review-evidence/`. The tools read `V23_EVIDENCE_ROOT` (default `~/AssetRounds-v23-review-evidence` off Windows). Full retained originals stay on the Windows PC.

The Windows working copy `C:\AssetRounds-v23-s10-integration` keeps about 55 uncommitted owner drafts. Never reset or delete it. The clean Mac clone has none, so normal `git add <paths>` commits replace the Windows overlay and candidate-tree scripts.

## Fast local loop on the Mac (development only)

- Compile check (no signing, no index), from the repo root:
  ```
  xcodebuild build-for-testing -project FieldEvidenceApp.xcodeproj -scheme FieldEvidenceApp -configuration Debug -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17' -derivedDataPath ~/DD CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO
  ```
- Targeted tests: `xcodebuild test-without-building … -only-testing:FieldEvidenceAppTests/<Class>/<method>` with the same destination and derived data.
- Keep `~/DD` between runs so incremental builds stay fast. Prune simulators and derived data when disk is low.
- Local results are development feedback, never evidence.

## Hosted routes and tools

- `Scripts/dev/v23-original.py` (after the tools batch lands): `dispatch --selection ID`, `collect --run ID`, plus the relaxed development commands (`--infra-retry-of`, `cancel`) recorded in the ledger. Merge and release gates stay strict.
- Development batch: edit `Scripts/v23-dev-batch.json` (exact ordered tests; include one method from a support class's own file when classes subclass it), then dispatch `v23-dev-batch-no-index-d50`.
- Full coverage: regenerate `Scripts/v23-coverage-partitions.json` with `python3 Scripts/v23-coverage-partitions.py --source Scripts/v23-coverage-partitions.json --output Scripts/v23-coverage-partitions.json` after any test-method change, then dispatch `v23-shared-coverage-d50x` (one build, 44 test-only partitions, 5 at a time; zero other active runs).
- Local protocol suites: `python3 Scripts/dev/prun.py Scripts/test-v23-native-ci.py -j 8` and the same for `Scripts/test-v23-selection-generator.py`.
- The template-budget guard keeps called-workflow content under 5.75 MiB (GitHub rejects about 6 MiB).

## State at handoff

Read ACTIVE_BRIEF first, then CURRENT_INTEGRATION's newest sections.

**Pushed head:** `5eb2f5f` (batch I, slim shared worker).
- The early full sweep, original 36133511753, was running. The shared route was qualified live: the producer built and sealed, and consumers restored and tested without rebuilding. All seven Round mount journeys passed.
- It must be collected with the shared collector, then failures triaged by family.

**Batch J, assembled and reviewed but not pushed:** Phase 1 UI tests, S10 reconciliation, signoff editor S10 styling, the S-class UI launch fix, combined-tree re-pins and regenerated partitions.
- It was built on Windows as candidate tree `candJ1` over `5eb2f5f`, with its suites running.
- If it isn't on the branch when you arrive, rebuild it on the Mac from the scratch commits named in CURRENT_INTEGRATION, or wait for the Windows session to push it.

**Next steps**
1. Collect and triage the sweep.
2. Push batch J.
3. Add the RUI1 UI route (plan in CURRENT_INTEGRATION "S10 reconciliation and Phase 1 UI evidence").
4. Fix sweep failures in parallel by family.
5. Run the Phase 1 UI evidence run and the owner's human review.
6. Do the final same-head full-coverage sweep and one independent integration review.
7. Fast-forward main and verify exact main.

After Phase 1, work trunk-based on main.

## Unchanged rules

- No force-push, merge commit, PR, settings or secrets change, signing, distribution or submission.
- Card135 is owner-only; releaseReady stays false.
- The five accepted S10 receipts stay bound to `docs/design/s10/**` and `Release/**`, which are never edited.
- Every consequential batch gets one independent reviewer who never authors it. Root alone commits, pushes and dispatches.
