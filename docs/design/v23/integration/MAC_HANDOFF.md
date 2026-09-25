# Mac development handoff

Owner decisions of 2026-09-25 (AGENTS.md): development moves to a persistent cloud Mac running Claude Code: a dedicated Apple-silicon Mac mini (for example from myremotemac.com or rentamac.io) with 16 GB+ RAM and a 512 GB SSD, on a macOS that runs Xcode 26.6 and the iOS 26.2 Simulator. Local builds and tests are for development feedback; official merge and release evidence still comes only from the hosted GitHub route.

## 1. One-time setup (owner, on the Mac)

Open Terminal and run these in order.

1. **Xcode 26.6.**
   - Check the version: `xcodebuild -version` must report `Xcode 26.6`.
   - If it doesn't, install 26.6 from developer.apple.com/download (Apple ID sign-in), move it to `/Applications/Xcode.app`, then run `sudo xcode-select -s /Applications/Xcode.app` and `sudo xcodebuild -license accept`.
2. **iOS 26.2 Simulator runtime** (the CI pins build 23C54).
   - Download it from Xcode › Settings › Components › iOS 26.2.
   - Check: `xcrun simctl list runtimes` must show `iOS 26.2 (23C54)`.
3. **Command-line tools.**
   - Install Homebrew from brew.sh.
   - Run `brew install gh jq python git`.
   - Run `gh auth login`: choose GitHub.com and HTTPS, then log in with the browser.
4. **Git identity.** Run `git config --global user.name "palatis3"`, then `git config --global user.email` with your usual address.
5. **Claude Code.** Install it with the official installer from claude.com/claude-code, run `claude` once, and sign in.
6. **Repository.** Clone it into `~/Developer/AssetRounds`:
   ```
   mkdir -p ~/Developer && cd ~/Developer
   git clone https://github.com/Asset-Rounds/AssetRounds.git
   cd AssetRounds
   git checkout codex/v23-s10-integration-20260910
   ```
7. **Evidence folder.** Create `~/AssetRounds-v23-review-evidence`. Then copy two items from the Windows PC folder `C:\AssetRounds-v23-review-evidence` into it: the file `v23-original-ledger.jsonl` and the folder `v23-original-attempts`. A cloud drive, email or DeskIn file transfer all work.
   - Leave all the large run folders on Windows.
   - The tools find this folder through `V23_EVIDENCE_ROOT`, which defaults to `~/AssetRounds-v23-review-evidence` on macOS.
8. **Start Claude Code.** Run `cd ~/Developer/AssetRounds && claude`. CLAUDE.md loads AGENTS.md automatically. The first message to send:
   > Read CLAUDE.md, AGENTS.md, docs/design/v23/integration/ACTIVE_BRIEF.md and MAC_HANDOFF.md. Verify the Mac setup (section 2), run the compile check, then continue the next steps in ACTIVE_BRIEF.

Keep the Windows PC folder `C:\AssetRounds-v23-s10-integration`. It holds about 55 uncommitted owner drafts, and they're preserved there. The Mac clone is clean, so ordinary `git add <paths>` commits work.

## 2. Verify the setup (Claude on the Mac)

- `xcodebuild -version` must show Xcode 26.6.
- `xcrun simctl list runtimes` must include iOS 26.2 (23C54).
- `gh auth status` must be logged in.
- `git status` must be clean on `codex/v23-s10-integration-20260910`.
- `python3 Scripts/dev/prun.py Scripts/test-v23-native-ci.py -j 8` must pass. Run it with `Scripts/test-v23-selection-generator.py` too.

## 3. The fast local loop (development only)

- **Compile check.** Warm incremental builds take minutes. Keep `~/DD` between runs.
  ```
  xcodebuild build-for-testing -project FieldEvidenceApp.xcodeproj -scheme FieldEvidenceApp -configuration Debug \
    -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17' -derivedDataPath ~/DD \
    CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO
  ```
  If `iPhone 17` isn't present, list the devices with `xcrun simctl list devices available` and use any iOS 26.2 iPhone.
- **Targeted tests.** Use the same command with `test-without-building -only-testing:FieldEvidenceAppTests/<Class>/<method>`. Add more `-only-testing` flags as needed.
- **Disk hygiene.** To reclaim space, run `xcrun simctl delete unavailable`, then remove `~/DD` and rebuild. Don't keep many runtimes.
- **Memory.** With 16 GB, avoid running several heavy builds at once. If a clean build thrashes, add `-jobs 4`.

## 4. Hosted runs (development and gates)

- **The tool.** `python3 Scripts/dev/v23-original.py dispatch --selection <id> --kind development|gate` starts a run, and `… collect --run <id>` collects it.
  - `--kind` is required for the two routes below. Use `development` for everyday runs and `gate` only for the frozen candidate's gate evidence.
  - Always pass `--kind` explicitly. Other selections default to `gate`, which is only a strictness label; a run counts as gate evidence only on the frozen candidate head, as AGENTS.md says.
  - Development runs only: `--infra-retry-of <run> --reason "<why>"` allows one rerun after a genuine runner, setup or artifact failure, and never after test failures. `cancel --run <id> --reason "<why>"` stops a run already known to be broken.
  - Gate runs never rerun or cancel, and a gate is refused if its head and selection already have an original.
  - Parallel development batches are refused until the workflow concurrency groups include the head; that is a small follow-up batch.
- **Development batch.**
  1. Edit `Scripts/v23-dev-batch.json` with the exact ordered tests, up to 150. If a test class subclasses a support class, also include one method from the file that defines it.
  2. Commit and push.
  3. Dispatch `v23-dev-batch-no-index-d50` with `--kind development`.
- **Full coverage (shared build).**
  1. After any test-method change, run `python3 Scripts/v23-coverage-partitions.py --source Scripts/v23-coverage-partitions.json --output Scripts/v23-coverage-partitions.json`.
  2. Commit and push.
  3. Dispatch `v23-shared-coverage-d50x` with `--kind development` for sweeps, or `--kind gate` for the frozen phase candidate. It needs zero other active runs, and it builds once then runs 44 test-only partitions, five at a time.
- **Workflow size.** Keep the template-budget guard test passing. GitHub rejects about 6 MiB of called-workflow content per parse.

## 5. State at handoff (keep ACTIVE_BRIEF current after this)

**Pushed branch head: see `git log`.** Batch J (`b16e965`) added:
- the Phase 1 gate;
- the shared-build route;
- the quiet Simulator protected-file check;
- S10 reconciliation;
- signoff S10 styling;
- the S-class UI launch fix;
- Phase 1 critical-state UI tests (27 states, catalogue `phase1-critical-states.json`);
- partitions for 3,445 methods.

**Early full sweep: original 36133511753, at `5eb2f5f`.**
- The shared route qualified live, and all seven Round mount journeys passed.
- If the Windows session hasn't collected it, collect it here after copying the ledger. Then triage failures by family.

**Also pushed:**
- the concise policy (`AGENTS.md`), `CLAUDE.md` and this handoff (`35eefd8`);
- the `Scripts/dev` tools with run kinds and the relaxed development commands (the commit after `35eefd8`).

Still due: the workflow change that allows parallel development batches, a per-head concurrency term reviewed with the template-budget guard.

**Next steps**
1. Collect and triage the sweep, then fix failure families (helpers can work in parallel).
2. Add the RUI1 UI route (`v23-ui-batch-rui1`; plan in CURRENT_INTEGRATION "S10 reconciliation and Phase 1 UI evidence").
3. Run the Phase 1 UI evidence and build the owner's review package.
4. Run the final same-head full sweep, then one independent integration review.
5. Fast-forward main, then run exact-main verification.
6. Work trunk-based on main after Phase 1.

**Phase 2 (Round capture), already due:**
- lost-acknowledgement finalization;
- the defer and two-photo journeys;
- B3 Retake/Remove;
- the startup live-path test rewrite;
- a production Round creator and package source;
- journey performance.
