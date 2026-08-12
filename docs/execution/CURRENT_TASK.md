# Current Task

- Phase / active operation / global order: `S0 / hosted-CI infrastructure verification recovery K1 / closed S0.1 (1 of 36)`
- Program autopilot enabled / exact ordered phase→branch→card map / final owner-only boundary: `yes` / `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1` / `stop after accepted S9.1 exact-main CI; S9.2 signing/TestFlight and S9.3 App Store submission are owner-only`
- Phase/card position and boundary: `S0.1 is complete / 1 of 1 / boundary verification recovery active`; do not rerun or edit S0.1
- Phase autopilot enabled / exact authorized same-phase span: `yes` / `S0.1 only (complete; no same-phase successor)`
- Immediate next unstarted card: `S1.1` on `phase/s1-shell-design`; it may be hydrated only after green exact-main K1
- Product implementation evidence `E`: `I3=ac310dd37700d65165200f742aaec1d48d0a34d6`; exact-head P12 run `31566371521` succeeded; I3 remains the sole S0.1 implementation result
- Immutable completed bookkeeping evidence: `C=15348e92466a79efd02bfb71f5ffee043e615829` directly parents I3 and changes only `docs/execution/HANDOFF.md`; the complete S0.1 HANDOFF is immutable
- Historical card chain: `I=6dac0a660110b05643bcdaaf97113b75f54080a0` / failed run `31562160165`; `I2=481d272ec319d3210d0e393d20130c7c1f8f0e1a` / failed run `31562792005`; `A0=9590743877627cdd915a68ec581cdff88d9d6418`; accepted `I3` / run `31566371521`; `C`; `R`
- Historical ordinary-card `M/A/M..A`: `M=I2=481d272ec319d3210d0e393d20130c7c1f8f0e1a`; `A=A0=9590743877627cdd915a68ec581cdff88d9d6418`; exactly one direct-child authority commit changing `AGENTS.md`, `docs/product/BUILD_PLAN_V4.md`, `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`, and `docs/execution/CURRENT_TASK.md`. These are immutable completed-card evidence; active infrastructure G0 uses E/F/K below instead of a new ordinary M/A.
- Historical immutable S0 bootstrap phase-main base: `P=c3e536a03775cc8d25f42a8e31c2f24db4390d4d`
- Failed verification evidence: exact-main run `31567299022` at C and exact-main run `31571125674` at `R=1e0322cc072fda28718468bcd1b0dbe1f5d0accc` both failed before `xcodebuild`; their checksummed evidence shows exact-UDID Simulator migration consumed the entire 180-second build wrapper. They are hosted-infrastructure evidence, never green/product evidence, and must not be rerun.
- Failed verification base `F`: `R=1e0322cc072fda28718468bcd1b0dbe1f5d0accc`; at recovery start local HEAD, remote HEAD, `main`, and `phase/s0-foundation` equal R; local and remote `phase/s1-shell-design` are absent
- Candidate infrastructure verification head `K1`: `OBSERVE AT POST-COMMIT G0; never self-record its SHA here`
- Required `R..K1` ancestry and path set: K1 directly parents R; exactly one commit changes only `AGENTS.md`, `docs/product/BUILD_PLAN_V4.md`, `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`, `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md`, `docs/execution/CURRENT_TASK.md`, and `.github/workflows/ios-ci.yml`
- Immutable infrastructure gate identity: `phase=S0; card=S0.1-closed-boundary; workflow=.github/workflows/ios-ci.yml; required-ref-roles=phase/s0-foundation then main; E=I3; first-failed-run/head=31567299022/C`; R/run `31571125674` is the second historical failed verification base in that same gate
- Infrastructure-recovery counters at K1 construction: `K1 of maximum K1/K2`; same-K phase redispatch `unused at construction`; same-K main redispatch `unused at construction`; ordinary S0.1 product-fix budget remains historical. Live counters derive only from reachable K commits and all GitHub exact-ref/head candidate history; this prose cannot reset them and is not amended for a no-code retry.
- Pre-existing dirty paths and disposition: `NONE at recovery start`; during K1 construction only the exact six paths above may be dirty; post-commit G0 requires clean index/worktree/untracked state

## Pinned authority

- Build-plan path / SHA-256: `docs/product/BUILD_PLAN_V4.md` / `655EAF15DF6E00E9E30DC8B6371F2D34E1782F7FA4618FFF87F83579CB794843`
- Exact plan anchors: `## 11. Build slices and release gates`; `## 16. Owner preparation checklist`; `## 18. Codex execution authority`
- Implementation-runbook path / SHA-256: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `0DC87CB28461B840975891604E1FB1BE32CF6395494EC3F7F1BBBB9FB35E917A`
- Selected runbook card / heading / lifecycle: `S0.1` / `### S0.1 — Repository and unsigned CI baseline` / `Steps 8–9 autonomous hosted-CI infrastructure recovery`
- Execution-contract path / SHA-256: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9753CE44491FB336E57EF0EB227976AC50AFF174FBB5641AA9DE8B3A35809437`
- CI workflow path / SHA-256 / trigger: `.github/workflows/ios-ci.yml` / `67A278F619C7524C636E46E96125784203191EC327C587FDAB3CABA848EA49EA` / `workflow_dispatch` with exact `run_ui_smoke=true`
- Selector path / SHA-256: `Scripts/ci-selection.json` / `9E0050FEA98E2E99F37A9113B11B58450AA16B73E99F6842BEBEA09F338C929C`; bytes remain immutable

## Outcome and exact delta

- Outcome: preserve accepted S0.1 product implementation I3 and completed HANDOFF; install the standing autonomous hosted-CI recovery guardrail; give exact-UDID Simulator readiness a dedicated 300-second infrastructure step before the unchanged P12 build step; require green exact-head phase and exact-main K1 evidence; then use K1 only as S0 verification/phase-close and S1 base.
- Sole operational workflow delta: define `CI_SIMULATOR_BOOT_TIMEOUT_SECONDS=300`; after setup-budget validation and before `Build unsigned simulator app`, run `bash Scripts/run-with-timeout.sh "$CI_SIMULATOR_BOOT_TIMEOUT_SECONDS" xcrun simctl bootstatus "$CI_SIMULATOR_UDID" -b`, tee to `simulator-boot.log`, require that log nonempty, and include it in ordinary relative checksum evidence.
- Frozen values: selector and P12 `setup/artifacts 120 / build 180 / unit 180 / UI 240 / total 720`; total 720 includes the new infrastructure wait. Build, unit, and UI commands remain byte-for-byte unchanged. Runner, Xcode, project, scheme, configuration, deployment target, Simulator model/runtime, exact test selectors, all preexisting required result bundles/logs/screenshot/checksums, and 30-minute job ceiling remain unchanged; only the named additive nonempty checksummed `simulator-boot.log` joins them.
- Project/app/test/script/fixture/asset/selector/HANDOFF/product delta: `NONE`
- ALT-1: `NONE` for product behavior. Hosted-infrastructure recurrence follows only the finite K lane below and is not card ALT-1.

## Environment and selector

- Product mode: `single-user, device-local V4`
- Execution route / authoring host: `Windows authoring → GitHub Actions macOS verification` / `Microsoft Windows 11 Home 64-bit 10.0.26200`
- Repository / visibility / base / phase: `palatis3/AssetRounds` / `private solo` / `main` / `phase/s0-foundation`
- Branch control: only exact non-force advances named below; no force push, merge commit, PR, divergent-ref repair, or broad write
- Runner / Xcode: `macos-26` / `Xcode 26.6, Build version 17F113, DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer`
- Minimum deployment / project / target / shared scheme / configuration: `iOS 18.0` / `FieldEvidenceApp.xcodeproj` / `FieldEvidenceApp` / `FieldEvidenceApp` / `Debug`
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one available UDID inside every ephemeral job and never reuse a pinned UDID across jobs
- UI mode / tier: `CI XCUITest` / `P12`
- Exact selector object: `{"schemaVersion":1,"taskID":"S0.1","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":120,"buildTimeoutSeconds":180,"testTimeoutSeconds":180,"uiTimeoutSeconds":240,"totalBudgetSeconds":720,"unitTestSelectors":["FieldEvidenceAppTests/S0LaunchTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S0LaunchUITests"]}`
- Exact ordinary commands remain: `bash Scripts/run-with-timeout.sh 180 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 180 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 240 bash Scripts/ui-smoke.sh`
- Required artifact: `ios-ci-<run_id>-<run_attempt>` with nonempty `simulator-boot.log`, build/test/UI logs, three result bundles, final screenshot, runner/Xcode/build-settings/Simulator/selection/run/budget evidence, and verified relative `SHA256SUMS.txt`
- Tool posture: Full access, `sandbox_mode=danger-full-access`, `approval_policy=never`, command network enabled, project trusted, GitHub available, goals enabled, XcodeBuildMCP disabled. Broader capability is not a blocker and never expands product scope.

## Allowed paths and operations

- K1 paths: `AGENTS.md`
- K1 paths: `docs/product/BUILD_PLAN_V4.md`
- K1 paths: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`
- K1 paths: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md`
- K1 paths: `docs/execution/CURRENT_TASK.md`
- K1 paths: `.github/workflows/ios-ci.yml`
- No path cap override, glob, directory root, deletion, rename, HANDOFF exception, or selector exception applies to K1.
- Read-only Git/GitHub inspection and artifact download are authorized for exact named refs/runs/candidates.
- Commit K1 once with explicit staging of exactly the six paths.
- Closed ref-resume states: (a) phase/main/HEAD=R with S1 absent is initial and permits the one phase push; (b) phase=K1 and main/HEAD=R resumes exact phase candidate history with no re-push, and only accepted phase CI permits the main advance; (c) phase/main/HEAD=K1 resumes exact main candidate history with no re-push. Every other state stops.
- From initial state only, non-force push `HEAD:refs/heads/phase/s0-foundation`; verify phase=K1 and main/HEAD=R.
- On the phase ref, apply the closed exact workflow/ref/head candidate-history rule below. Dispatch the initial run with `gh workflow run .github/workflows/ios-ci.yml --repo palatis3/AssetRounds --ref phase/s0-foundation -f run_ui_smoke=true` only when zero candidates exist. Accept only green exact-K1 artifacts.
- After accepted phase K1, reprove or resume phase=K1/main/HEAD=R and non-force fast-forward exact K1 to `refs/heads/main` only if main is still R; if main already equals K1, do not re-push. Verify phase/main/HEAD=K1.
- On main, apply the same closed exact workflow/ref/head candidate-history rule. Dispatch the initial run with `gh workflow run .github/workflows/ios-ci.yml --repo palatis3/AssetRounds --ref main -f run_ui_smoke=true` only when zero candidates exist. Accept only green exact-K1 artifacts.
- If an exact-K1 phase or main run repeats an identical mechanically eligible infrastructure signature under the standing eligibility rule, with no compiler diagnostic, test result/assertion, selector, acceptance, or product failure, one no-code fresh-runner dispatch on that same ref is authorized after fresh exact-ref/candidate G0. Never rerun the failed run ID. Any other failure cannot use this retry.
- Closed candidate history, independently per exact workflow/ref/head: zero candidates → dispatch initial once; one active → wait; one green → accept; one eligible terminal failure with unused retry → dispatch retry once; exactly two are valid only when the first is that eligible failure and the second is active or green, so wait for/accept only the second. A terminal second run, any other status/order, or more than two candidates stops. The authorized pair is not a duplicate; every unexpected multiplicity is.
- A distinct complete-artifact hosted-infrastructure cause may use K2 only under the frozen standing plan/runbook/contract rule. It must directly parent failed K1 and change only a causally required subset of `docs/execution/CURRENT_TASK.md`, `.github/workflows/ios-ci.yml`, and the four smoke/timeout scripts. CURRENT_TASK may record evidence/repin but cannot broaden/reset the lane. K2 may use its one identical-signature same-head retry; if K2 remains non-green afterward or has any ineligible failure, stop technically without requesting approval and create no K3.
- After green exact-main K1, create only `phase/s1-shell-design` from K1, hydrate only S1.1 via runbook Section 3 in a CURRENT_TASK-only authority commit with `P=M=K1`, push non-force, and run fresh S1.1 G0.

## Forbidden

- Changing `docs/execution/HANDOFF.md`, `Scripts/ci-selection.json`, any script, project/app/test/fixture/asset, package, lockfile, entitlement, permission, capability, product behavior, schema, UI, navigation, persistence, camera, report, backup, StoreKit, analytics, signing, release, deployment, or submission byte in K1
- Changing runner/Xcode/Simulator selector, N8/P12/F25 values, test selectors/commands, existing product/card acceptance assertions, any preexisting required evidence/checksum enforcement, workflow input, or 30-minute job ceiling; only additive infrastructure-readiness acceptance and nonempty checksummed `simulator-boot.log` are allowed
- Rerunning runs `31567299022` or `31571125674`; calling C/R successful; reopening S0.1; replacing I3 as product implementation evidence; amending HANDOFF
- Force push, merge commit, PR, divergent ref repair, settings, secrets, collaborators, release, signing, TestFlight/App Store upload, deployment, or submission
- Local Xcode, Simulator, `xcodebuild`, or XcodeBuildMCP

## K1 state machine and acceptance

1. Construct K1 from clean R with exactly the six allowed paths and the exact delta above. Compute and pin final plan/runbook/contract/workflow hashes. Explicitly stage and commit once; do not push before post-commit G0.
2. Fresh post-commit/resume G0 proves local branch `phase/s0-foundation`, clean `K1^=R`, one commit in `R..K1`, exact six-path diff, `git diff --check`, all pins/anchors, selector equality, protected-tree equality, immutable I3/C/HANDOFF and failed-run evidence, local/remote S1 absent, and exactly one closed ref-resume state: initial R/R, phase-only K1/R, or integrated K1/K1.
3. In initial R/R only, re-read refs and non-force push phase R→K1, then verify phase=K1/main=R. In phase-only K1/R, do not re-push. Apply the closed exact phase/head=K1 candidate history, permit no intervening movement, and require terminal success plus complete checksummed artifact. One same-K1 retry is allowed only for an identical mechanically eligible infrastructure signature with no compiler/test/selector/acceptance/product failure.
4. After accepted phase run, if phase=K1/main=R, non-force fast-forward main R→K1 and verify phase/main/HEAD=K1; if phase/main already equal K1, do not re-push. Apply/resume the closed exact main/head=K1 candidate history and require terminal success plus complete checksummed artifact. The same narrow same-K1 retry rule applies.
5. GOLDEN checkpoints: dedicated exact-UDID boot step succeeds within 300 seconds and creates nonempty checksummed `simulator-boot.log`; unchanged build/unit/UI steps succeed within 180/180/240; exact S0 selectors each execute non-skipped and pass; total evidence budget is at most 720; all required artifacts/checksums pass; `head_sha=K1`; no protected byte changed.
6. Green exact-main K1 makes K1 the S0 verification/phase-close and S1 phase/card base while E=I3 remains S0.1 implementation. Create/hydrate only S1.1 as above, run fresh G0, then resume strict frozen order through S9.1.

## Stop conditions

- Stop technically, without requesting an authority/approval message, on unresolved source/hash/ancestry/path/dirty-state evidence; ref divergence/intervening movement; non-fast-forward/rejection; candidate history outside the closed authorized sequence; unlisted required path; weakened/changed selector, test, product, tier, existing product/card acceptance, or preexisting evidence; compiler diagnostic; product test/acceptance failure; K2 still non-green after its allowed same-head retry; or any ineligible K2 failure.
- If a required GitHub operation or pinned environment is externally unavailable, report that external technical blocker; do not substitute or ask for guardrail approval.

## Definition of done

- K1 is a direct child of R with exactly the six-path guardrail/workflow diff; all pins and protected-byte proofs pass; exact-head phase and exact-main UI-enabled P12 runs are green with complete artifacts; I3 and K1 are recorded separately; remote phase/main/HEAD equal K1.
- Create/resume only `phase/s1-shell-design`, hydrate only S1.1 with `P=M=K1`, pass fresh G0, and continue the existing goal through S9.1. Stop before owner-only S9.2/S9.3.
