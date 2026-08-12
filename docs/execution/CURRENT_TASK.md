# Current Task

- Phase / active operation / global order: `S0 / hosted-CI infrastructure support K3 / closed S0.1 (1 of 36)`
- Program autopilot enabled / exact ordered phase→branch→card map / final owner-only boundary: `yes` / `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1` / `stop after accepted S9.1 exact-main CI; S9.2 signing/TestFlight and S9.3 App Store submission are owner-only`
- Phase/card position and boundary: `S0.1 complete / 1 of 1 / final boundary verification recovery active`; do not rerun or edit S0.1
- Phase autopilot enabled / exact authorized same-phase span: `yes` / `S0.1 only (complete; no same-phase successor)`
- Immediate next unstarted card: `S1.1` on `phase/s1-shell-design`; hydrate only after accepted green exact-main current K
- Product implementation evidence `E`: `I3=ac310dd37700d65165200f742aaec1d48d0a34d6`; exact-head P12 run `31566371521` succeeded; I3 remains the sole S0.1 product result
- Immutable completed bookkeeping: `C=15348e92466a79efd02bfb71f5ffee043e615829` directly parents I3 and changes only `docs/execution/HANDOFF.md`; the complete S0.1 HANDOFF is immutable
- Historical card chain: `I=6dac0a660110b05643bcdaaf97113b75f54080a0` / run `31562160165` failed; `I2=481d272ec319d3210d0e393d20130c7c1f8f0e1a` / run `31562792005` failed; `A0=9590743877627cdd915a68ec581cdff88d9d6418`; accepted I3/run `31566371521`; C; `R=1e0322cc072fda28718468bcd1b0dbe1f5d0accc`; K1; K2
- Historical ordinary-card `M/A/M..A`: `M=I2=481d272ec319d3210d0e393d20130c7c1f8f0e1a`; `A=A0=9590743877627cdd915a68ec581cdff88d9d6418`; direct-child authority commit changing exactly AGENTS, plan, runbook, and CURRENT_TASK. Active infrastructure G0 uses E/F/K while preserving this history.
- Immutable S0 bootstrap phase-main base: `P=c3e536a03775cc8d25f42a8e31c2f24db4390d4d`
- Failed boundary evidence: exact-main run `31567299022` at C and exact-main run `31571125674` at R failed before xcodebuild during hosted exact-Simulator readiness; never rerun or accept them
- K1 evidence: `K1=0da62482db7e3f90742876ef05574de9e9569e32` directly parents R; phase run `31579936670`, attempt 1, failed only total `727 > 720` after readiness, setup/artifact, build, unit, UI, selectors, evidence, 90-entry checksum verification, and upload passed
- K2 evidence / failed verification base `F`: `K2=400f8827f5451b9a44f4d846340b51377554069d` directly parents K1; exact phase run `31583957094`, attempt 1, passed selection and pinned Xcode/scheme/Simulator inspection, then first failed setup `232 > 120` after the K2 boot request put exact-Simulator readiness on setup's critical path; total `233 <= 720`; build/unit/UI did not run; later evidence/checksum failures were deterministic; partial artifact upload succeeded. The run is non-green, retired, and never accepted or redispatched.
- Candidate support head `K3`: `OBSERVE AT POST-COMMIT G0; never self-record its SHA here`
- Required `K2..K3`: K3 directly parents K2; exactly one commit changes only the seven K3 paths below
- Pre-existing dirty paths: `NONE at K3 construction start`; during construction only the seven K3 paths may be dirty; post-commit G0 requires clean index/worktree/untracked state

## Immutable gate, lineage, and signature ledger

- Canonical gate string: `gate-v1|repository-id=1331480630|workflow-id=332381264|workflow-path=.github/workflows/ios-ci.yml|job=verify|phase=S0|card=S0.1-closed-boundary|phase-branch=phase/s0-foundation|required-ref-roles=phase/s0-foundation,main|E=ac310dd37700d65165200f742aaec1d48d0a34d6|P=c3e536a03775cc8d25f42a8e31c2f24db4390d4d|selector-sha256=9e0050fea98e2e99f37a9113b11b58450aa16b73e99f6842bebea09f338c929c|tier=P12|first-failed-run=31567299022|first-failed-head=15348e92466a79efd02bfb71f5ffee043e615829`
- Gate SHA-256: `a4070e143c52d8bba81038200dfd79ff70ac3a084f9200791e11eccc8d1cecfd`
- Legacy K1 target: `cause-v1|gate=sha256:a4070e143c52d8bba81038200dfd79ff70ac3a084f9200791e11eccc8d1cecfd|operation=build|guard=build-wrapper-exit|fault=timeout-124|mechanism=exact-simulator-readiness|failure=pre-product|repair=dedicated-prebuild-exact-udid-readiness`
- Legacy K1 target SHA-256 / fixed index: `126fcb04b8460cb2076c95d2fcf8f5dabe6ba2a29ad44330289c16fc08e14c18` / `1`
- Legacy K2 target: `cause-v1|gate=sha256:a4070e143c52d8bba81038200dfd79ff70ac3a084f9200791e11eccc8d1cecfd|operation=total-budget|guard=elapsed-seconds-lte-total-budget|fault=assertion-nonzero|mechanism=lane-harness-scheduling-accounting|failure=post-evidence|repair=schedule-readiness-outside-build-envelope`
- Legacy K2 target SHA-256 / fixed index: `b3dad4c21eeb4bff09b649fbdcad1dddbae44a527f411a547f5aabd6876f7a62` / `2`
- K3 failure record: `failure-v1|gate=sha256:a4070e143c52d8bba81038200dfd79ff70ac3a084f9200791e11eccc8d1cecfd|operation=setup-budget|guard=setup-elapsed-lte-setup-budget|fault=assertion-nonzero|mechanism=lane-harness-scheduling-accounting|product=not-run|artifact=partial-upload-no-checksum`
- K3 failure SHA-256 / derived index: `36de2304301206a49cb5e8613c67f8ec9184dad6f83a09fa799bddbf10c1a01e` / `3`
- K3 repair record / SHA-256: `repair-v1|gate=sha256:a4070e143c52d8bba81038200dfd79ff70ac3a084f9200791e11eccc8d1cecfd|key=background-exact-simulator-readiness-concurrent-with-build-joined-before-tests` / `c1c0cb113b1d830e56039d5a5dd6bfed61ef2d0a42e0e3cc5d5282cd84efaef2`
- K2 bootstrap artifact provenance: `artifact id 9136413551 / ios-ci-31583957094-1 / sha256:284632a9587fa296a36b1c57c9e9320779f022a4d68b8ff5a592305105bfaedd`; this exact legacy no-manifest exception is consumed by K3 and cannot classify a later run
- K3 required commit trailers: `Infrastructure-Gate: sha256:a4070e143c52d8bba81038200dfd79ff70ac3a084f9200791e11eccc8d1cecfd`; `Infrastructure-Support-Index: 3`; `Infrastructure-Failed-Run: 31583957094`; `Infrastructure-Failed-Head: 400f8827f5451b9a44f4d846340b51377554069d`; `Infrastructure-Failed-Ref: refs/heads/phase/s0-foundation`; `Infrastructure-Failure-Signature: sha256:36de2304301206a49cb5e8613c67f8ec9184dad6f83a09fa799bddbf10c1a01e`; `Infrastructure-Repair-Key: sha256:c1c0cb113b1d830e56039d5a5dd6bfed61ef2d0a42e0e3cc5d5282cd84efaef2`
- History-derived candidates at K3 construction: K1 phase has exactly failed run `31579936670` and no retry; K1 main has none; K2 phase has exactly failed run `31583957094` and no retry; K2 main has none; K3 phase/main have zero candidates. No provider/transport no-code retry failure/repair has been consumed for this gate. Creating K3 retires every unused K2 dispatch/retry. Future no-code retry consumption derives immediately from exact GitHub history and is mirrored only at the next otherwise-authorized CURRENT_TASK commit; prose cannot reset it.

## Pinned authority

- Build-plan path / SHA-256: `docs/product/BUILD_PLAN_V4.md` / `6DD88EA22B32B6FDB2CB92E8DEC628FFF34B833138C02E9000CC760C0B09C6CA`
- Exact plan anchors: `## 11. Build slices and release gates`; `## 16. Owner preparation checklist`; `## 18. Codex execution authority`
- Implementation-runbook path / SHA-256: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `61514650B53B6859C6A2D1F6678B6F7E21FC2ABEFF9C110EF4B1BF3B8BD7D164`
- Selected runbook card / heading / lifecycle: `S0.1` / `### S0.1 — Repository and unsigned CI baseline` / `Steps 8–9 monotonic evidence-bounded hosted-CI recovery`
- Execution-contract path / SHA-256: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `488E7A14129227D2E8BC70845757477A4E09F08D6CB8FF840F73F3881232E45B`
- CI workflow path / SHA-256 / trigger: `.github/workflows/ios-ci.yml` / `2D2751C6FC42E01EC9283174E9D47BE2D6E1905B47BF95F447ABCEE3D147FBB6` / `workflow_dispatch` with exact `run_ui_smoke=true`
- Selector path / SHA-256: `Scripts/ci-selection.json` / `9E0050FEA98E2E99F37A9113B11B58450AA16B73E99F6842BEBEA09F338C929C`; bytes remain immutable

## Outcome and exact delta

- Outcome: install the no-approval, monotonic evidence-bounded infrastructure lane; preserve accepted S0.1 I3/HANDOFF; correct only K2's distinct setup/readiness scheduling cause; require green exact-head phase and exact-main current-K P12 evidence; then use the accepted current K only as S0 verification/phase-close and S1 base
- Exact workflow delta: restore pinned Xcode version/list/shared-scheme/build-settings/deployment inspection, exact runtime/name/UDID selection, exact-one state validation, and the unchanged setup `<=120` assertion before any Simulator boot wait. Accept selected state only `Shutdown` or `Booted`.
- Exact readiness/build scheduling delta: after setup passes, launch one exact-UDID `simctl bootstatus -b` under the unchanged process-group 300-second ceiling as tracked GitHub background step `simulator_boot`; capture wrapper/tee status without masking exit 124; concurrently run the unchanged exact-destination build under its independent 180-second ceiling; then execute unconditional `wait: simulator_boot` before tests so background failure propagates and the logs are closed before evidence hashing. Both intervals remain inside raw total.
- Exact build-smoke delta: remove only its redundant second `simctl bootstatus -b`; leave the following exact `xcodebuild ... build-for-testing` invocation and all product-result checks byte-for-byte unchanged. Build-smoke does not consume background environment/output before the wait.
- Exact fail-closed evidence-order delta: export measured setup elapsed before asserting setup `<=120`; generate and verify `SHA256SUMS.txt` before asserting setup-plus-artifact `<=120`; keep both assertions, raw endpoints, and the later evidence-budget recheck unchanged. This consumes the K2 legacy no-manifest exception and never turns a failed budget into acceptance.
- Frozen acceptance: selector and P12 stay exact `setup/artifacts 120 / build 180 / unit 180 / UI 240 / total 720`; raw total starts before checkout and ends after checksum, so readiness remains fully counted. Runner/Xcode/project/scheme/configuration/deployment/Simulator selector, exact build/unit/UI commands, tests, result validation, artifacts/checksums, and 30-minute hard stop remain unchanged.
- Product/project/app/test/fixture/asset/selector/HANDOFF delta: `NONE`
- ALT-1: `NONE` for product behavior. Infrastructure candidate handling follows the frozen monotonic lane only.

## Environment and selector

- Product mode: `single-user, device-local V4`
- Execution route / authoring host: `Windows authoring → GitHub Actions macOS verification` / `Microsoft Windows 11 Home 64-bit 10.0.26200`
- Repository / visibility / base / phase: `palatis3/AssetRounds` / `private solo` / `main` / `phase/s0-foundation`
- Current refs at K3 construction: local/remote phase=`K2`; remote main/default HEAD=`R`; local/remote `phase/s1-shell-design` absent; worktree initially clean
- Branch control: only exact non-force advances in the state machine; no force push, merge commit, PR, divergent repair, or broad write
- Runner / Xcode: `macos-26` / `Xcode 26.6, Build version 17F113, DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer`
- Minimum deployment / project / target / shared scheme / configuration: `iOS 18.0` / `FieldEvidenceApp.xcodeproj` / `FieldEvidenceApp` / `FieldEvidenceApp` / `Debug`
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one available UDID per ephemeral job
- UI mode / tier: `CI XCUITest` / `P12`
- Exact selector object: `{"schemaVersion":1,"taskID":"S0.1","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":120,"buildTimeoutSeconds":180,"testTimeoutSeconds":180,"uiTimeoutSeconds":240,"totalBudgetSeconds":720,"unitTestSelectors":["FieldEvidenceAppTests/S0LaunchTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S0LaunchUITests"]}`
- Exact commands: `bash Scripts/run-with-timeout.sh 180 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 180 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 240 bash Scripts/ui-smoke.sh`
- Required artifact: `ios-ci-<run_id>-<run_attempt>` with nonempty two boot logs, build/test/UI logs, three result bundles, final screenshot, runner/Xcode/build-settings/Simulator/selection/run/budget evidence, and verified relative `SHA256SUMS.txt`
- Tool posture: Full access, `sandbox_mode=danger-full-access`, `approval_policy=never`, command network enabled, project trusted, GitHub available, goals enabled, XcodeBuildMCP disabled. Capability breadth is not a blocker and never expands scope.

## K3 allowed paths and operations

- `AGENTS.md`
- `docs/product/BUILD_PLAN_V4.md`
- `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`
- `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md`
- `docs/execution/CURRENT_TASK.md`
- `.github/workflows/ios-ci.yml`
- `Scripts/build-smoke.sh`
- No glob/root, deletion, rename, HANDOFF exception, selector exception, or other script exception applies to K3.
- Read-only exact Git/GitHub/ref/run/candidate inspection and artifact download are authorized.
- Explicitly stage and commit exactly the seven paths once with the seven required trailers; do not push before post-commit G0.
- Initial valid state is phase=K2/main=R/S1 absent with zero K3 candidates. Reprove refs, non-force push phase K2→K3, verify phase=K3/main=R, then apply exact phase/head=K3 candidate history.
- Dispatch once only at zero candidates: `gh workflow run .github/workflows/ios-ci.yml --repo palatis3/AssetRounds --ref phase/s0-foundation -f run_ui_smoke=true`. Wait one active; accept one green; classify one terminal result under the lane. Never rerun a failed run ID.
- Only accepted green phase K3 permits main R→K3 by non-force fast-forward. Verify phase/main/default HEAD=K3, then apply the same exact-main/head=K3 candidate history and absent-only dispatch with `--ref main`.
- Resume states are closed: phase=K2/main=R permits only phase push; phase=K3/main=R requires valid phase history and zero main K3 candidates; phase/main=K3 requires prior accepted green phase K3 and valid main history. Any other ref/provenance state stops.
- After K3, a distinct eligible future failure with one unique causal lane delta mechanically creates direct-child next K under the frozen rule, changing only `docs/execution/CURRENT_TASK.md` plus the uniquely causal body between exact `INFRA_RECOVERY_BEGIN`/`INFRA_RECOVERY_END` markers in `.github/workflows/ios-ci.yml`; it derives index/failure/repair/trailers from ancestry/history, retires the failed head, and restarts the ordered phase→main cursor. Repeated/overlapping consumed failure or repair cannot create another K.
- After accepted green exact-main current K, create only `phase/s1-shell-design` from that K, hydrate only S1.1 in a CURRENT_TASK-only authority commit with `P=M=current K`, push non-force, and run fresh S1.1 G0.

## Forbidden

- During K3, changing HANDOFF, selector, project/app/tests/fixtures/assets, product behavior, schema, UI/navigation/persistence/camera/report/backup/StoreKit/analytics/release bytes, or any path outside the seven K3 paths. After K3, every path except CURRENT_TASK and the exact marked workflow body is forbidden by the standing lane.
- Changing runner/Xcode/Simulator selection, N8/P12/F25 values, exact selectors/commands, xcodebuild invocation, product/card assertions, aggregate start/end/value/assertion, evidence/checksum/upload enforcement, trigger/permissions/action pins, or 30-minute job ceiling
- Accepting/rerunning historical failures, calling K1/K2 successful, reopening S0.1, replacing I3 as product evidence, or amending HANDOFF
- Force push, merge commit, PR, divergent repair, settings/secrets/collaborators, signing, TestFlight/App Store upload, deployment, or submission
- Local Xcode, Simulator, xcodebuild, or XcodeBuildMCP

## K3 state machine and acceptance

1. Construct K3 from clean K2 with exactly the seven paths/delta, final repins, canonical identities, and trailers. Commit once; do not push before post-commit G0.
2. Fresh G0 proves clean `K3^=K2`; exact one-commit seven-path diff; trailer/gate/index/run/head/ref/signature hashes; unique signature and repair key across lineage; pins/anchors/selector; protected-tree and frozen workflow-spine equality; immutable I3/C/HANDOFF; exact historical candidates; S1 absent; and one closed ref state.
3. Advance/resume phase exactly once, apply closed exact candidate history, and accept only terminal success at `head_sha=K3` with complete checksummed artifacts inside 120/300/180/180/240/720.
4. After accepted phase K3, advance/resume main exactly once and require the same exact-main success contract.
5. GOLDEN: setup inspection/state selection passes within 120 before readiness starts; tracked exact-UDID background readiness passes within 300 while unchanged build passes within its independent 180; unconditional wait joins readiness before unit/UI tests; unchanged unit/UI commands pass within 180/240; exact S0 selectors execute non-skipped; total is at most 720; all evidence/checksums pass; no protected byte changed.
6. Green exact-main current K makes it S0 verification/phase-close and S1 base while E=I3 remains product implementation. Hydrate only S1.1 and resume strict order through S9.1.

## Technical stop conditions

- Stop without asking for authority text on ambiguous/unresolved first cause, failure/repair identity, or unique delta; repeated or overlapping consumed failure/repair; path outside lane; multiple operational deltas; protected/frozen/evidence weakening; compiler/test/product failure; insufficient classification evidence; ref divergence/non-fast-forward/intervening movement; invalid candidate history; or unavailable required GitHub route.
- Numeric K index is never a stop. If a distinct eligible signature and unique delta exist, mechanically create the next K under the frozen lane instead of requesting approval.

## Definition of done

- The first current K at index 3 or later with exact green phase and exact-main P12 runs, complete artifacts, all unchanged ceilings, and protected-byte proofs is accepted as S0 verification/phase-close; remote phase/main/default HEAD equal it; I3 remains product evidence.
- Create/resume only `phase/s1-shell-design`, hydrate only S1.1 with `P=M=accepted current K`, pass fresh G0, and continue the goal through S9.1. Stop before owner-only S9.2/S9.3.
