# Current Task

- Phase / card ID and global order: `S0 / S0.1 boundary integration recovery / 1 of 36`; the S0.1 coding card is closed and must not be rerun or edited
- Program autopilot enabled / exact ordered phase→branch→card map / final owner-only boundary: `yes` / `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1` / `stop after accepted S9.1 exact-main CI; S9.2 signing/TestFlight and S9.3 App Store submission are owner-only`
- Phase autopilot enabled / exact ordered authorized same-phase card span: `yes` / `S0.1` (completed; no same-phase successor)
- Autopilot transition rule: one current card at a time. S0.1 remains closed by accepted exact-I3 CI and its committed HANDOFF. This task authorizes only the one S0 authority-only boundary recovery state machine below; success permits only S1.1 first-card hydration under the closed runbook rule. Program map, Full access posture, product/code/workflow/selector/tier/timeouts, prohibitions, and final S9.2/S9.3 owner boundary are immutable.
- Card position in phase / runbook-marked phase boundary: `1 of 1` / `yes—completed card; boundary integration recovery active`
- Predecessor card IDs: `NONE—S0.1 is the first coding card and is complete`
- Required completed-card evidence: initial `I=6dac0a660110b05643bcdaaf97113b75f54080a0` produced exact-head failed run `31562160165`; diagnosed fix `I2=481d272ec319d3210d0e393d20130c7c1f8f0e1a` produced exact-head failed run `31562792005`; owner-authorized card authority `A0=9590743877627cdd915a68ec581cdff88d9d6418` directly parents I2 and changed exactly the prior four authority documents; recovery implementation `I3=ac310dd37700d65165200f742aaec1d48d0a34d6` directly parents A0, changes exactly `Scripts/build-smoke.sh` and `Scripts/test-smoke.sh`, and produced successful exact-head P12 run `31566371521`; HANDOFF-only `C=15348e92466a79efd02bfb71f5ffee043e615829` directly parents I3 and completely closes S0.1.
- Failed boundary evidence and owner decision: remote phase and `main` were both exact C; exact-main UI-enabled run `31567299022` at C failed before `xcodebuild` because the hosted Simulator remained in `CoreLocationMigrator` through the 180-second build wrapper. The owner authorized one authority-only phase-boundary recovery `R`, one exact-main R decision, and no product fix, C rerun, or further recovery.
- Historical immutable S0 phase-main base SHA `P`: `c3e536a03775cc8d25f42a8e31c2f24db4390d4d` (bootstrap B; remains historical S0 base evidence and is not rewritten by R)
- Historical S0.1 integrated/base SHA `M`: `481d272ec319d3210d0e393d20130c7c1f8f0e1a` (I2; used only by the completed card recovery)
- Historical S0.1 task-start authority HEAD `A0`: `9590743877627cdd915a68ec581cdff88d9d6418`
- Completed S0.1 implementation / HANDOFF-only phase-close: `I3=ac310dd37700d65165200f742aaec1d48d0a34d6` / `C=15348e92466a79efd02bfb71f5ffee043e615829`
- Boundary-recovery base SHA: `C=15348e92466a79efd02bfb71f5ffee043e615829`; local HEAD, remote `phase/s0-foundation`, remote `main`, and remote HEAD all equaled C at the owner-authorized pre-amendment G0; local and remote `phase/s1-shell-design` were absent
- Boundary-recovery authority commit `R`: `OBSERVE AT POST-COMMIT G0; never self-record its SHA here`
- Required `C..R` authority-only path set and expected diff: one direct-child commit changing exactly `AGENTS.md`, `docs/product/BUILD_PLAN_V4.md`, `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`, and `docs/execution/CURRENT_TASK.md`; it records this bounded boundary recovery, repins the changed plan/runbook, and changes no HANDOFF, implementation, project, app, test, script, selector, workflow, tier, timeout, product behavior, or product implementation byte outside those four authority documents
- Pre-existing dirty paths and owner/disposition: `NONE at pre-amendment G0`; while constructing R only the exact four owner-authorized authority paths above may be dirty, and post-commit G0 requires a completely clean index/worktree/untracked set
- Build-plan path: `docs/product/BUILD_PLAN_V4.md`
- Build-plan SHA-256 over exact bytes: `987B31AA56FAD607EE2C069E18605C7DC0666715405B565FBDDB4401F371DE2E`
- Exact plan heading anchors: `## 11. Build slices and release gates`; `## 16. Owner preparation checklist`; `## 18. Codex execution authority`
- Implementation-runbook path: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`
- Implementation-runbook SHA-256 over exact bytes: `E2FDCF16CCC4BCBB1A3F3ED1FD95B7BC4CE84C744B08978EC971E0ABB1589510`
- Selected runbook card ID and heading anchor: `S0.1` / `### S0.1 — Repository and unsigned CI baseline`; lifecycle Step 8 is the active boundary-recovery authority
- Outcome: preserve the accepted I3 implementation and complete S0.1 HANDOFF byte-for-byte; create one four-document authority-only R; obtain one successful UI-enabled exact-main P12 result at R; then use R as accepted S0 phase-close and the sole base for S1.1 hydration.
- Product mode: `single-user, device-local V4`
- Starting fixture/state: clean completed S0 phase at C; exact S0.1 selector and all I3 implementation bytes; successful card run `31566371521`; complete committed HANDOFF; remote phase/main/HEAD=C; S1 absent; the only main/head=C candidate is failed run `31567299022`, which is never rerun and is not an R candidate.
- Execution route: `Windows authoring → GitHub Actions macOS verification`
- Authoring host OS/build: `Microsoft Windows 11 Home, 64-bit, version 10.0.26200, build 26200`
- GitHub repository / visibility and branch-control posture / base branch / phase branch: `palatis3/AssetRounds` / `private solo repository; no server-enforced main protection required; only the exact non-force C→R phase/main advances below are allowed; every force push, merge commit, divergent-main repair, and other main write is forbidden` / `main` / `phase/s0-foundation`
- CI workflow path / workflow file SHA-256 / trigger / recovery branch ref: `.github/workflows/ios-ci.yml` / `ED3865E07A5CD25B641B75D049F4D6376EF42D8B0ABDF85570DBED6786FEF771` / `workflow_dispatch` with `run_ui_smoke=true` / `main`
- Dispatch-head rule: after R exists and remote phase and `main` both equal exact R, search for an exact `main/head_sha=R` workflow-dispatch candidate. Reuse a matching candidate if present; dispatch exactly once only when absent; permit no intervening push; accept only terminal success whose `head_sha` equals R. Run `31567299022` at C is never rerun and cannot satisfy R.
- Hosted-macOS runner label / expected Xcode version+build: `macos-26` / `Xcode 26.6, Build version 17F113, DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer`
- Minimum iOS deployment target: `18.0`
- Project or workspace / target / shared scheme / configuration: `FieldEvidenceApp.xcodeproj` / `FieldEvidenceApp` / `FieldEvidenceApp` / `Debug`
- CI Simulator model / OS selector: `iPhone 17` / `iOS 26.5` (UDID resolves per ephemeral job and is never reused)
- UI-smoke mode: `CI XCUITest (P12)`
- Allowed GitHub/CLI methods and exact repository/ref/workflow operations: read-only `git status`, `git rev-parse`, `git diff`, `git show`, `git branch --show-current`, `git ls-remote`; explicit-path `git add|commit` for R; exactly one non-force `git push origin HEAD:refs/heads/phase/s0-foundation` after post-R G0 proves remote phase=C; exactly one non-force `git push origin R:refs/heads/main`, where token R means the exact SHA observed at post-commit G0, after phase=R and main=C; `gh workflow run .github/workflows/ios-ci.yml --repo palatis3/AssetRounds --ref main -f run_ui_smoke=true` exactly once only when no `main/head_sha=R` candidate exists; matching-run-only `gh run list|view|watch|download`; repo/workflow view; after accepted R only, `git switch -c phase/s1-shell-design R` or resume an exact valid local S1 authority, where R again means its observed exact SHA; explicit CURRENT_TASK-only commit; and non-force `git push origin A:refs/heads/phase/s1-shell-design`, where A means the exact observed S1.1 authority SHA. `XcodeBuildMCP=disabled`; no force push, PR, issue, merge commit, release, settings, secrets, collaborator, signing, upload, deployment, or submission operation.
- Owner-required sandbox / approval / command-network / trusted-config / GitHub-tool posture: owner GUI/session Full access; `sandbox_mode=danger-full-access`; `approval_policy=never`; command network enabled; project trusted; goals enabled; GitHub available; XcodeBuildMCP disabled. Broader enabled capability is not authority and not a G0 blocker; actual use remains limited to named paths and operations.
- G0 observation rule: record effective posture in the S1.1 authority/handoff evidence; stop only if a required operation is unavailable or an intended action exceeds this contract. Do not stop merely because other tools, connectors, credentials, filesystem locations, or network access are available.
- Selector state: `Scripts/ci-selection.json` must remain byte-identical to accepted I3/C and the exact S0.1 P12 object below throughout R and its main run; no selector mutation is authorized
- Task-owned implementation commit authorized: `no—S0.1 is complete; R is authority-only and no I4/fix exists`
- Boundary-recovery authority commit R authorized: `yes—exactly one direct child of C changing exactly the four authority paths`
- Exact phase-branch push authorized: `yes—exactly one non-force C→R push after post-R G0`
- Exact main fast-forward authorized: `yes—exactly one non-force C→R push after phase ref=R and remote main=C`
- Named CI workflow dispatch authorized: `yes—exactly one main/ref/UI-enabled dispatch at R only when no matching candidate exists`
- Named run inspection + artifact download authorized: `yes—failed historical main run 31567299022 and the sole main/head=R candidate only`
- Same-phase post-green transition commit/push authorized: `no—S0 has no successor card`
- HANDOFF append/edit/commit/push authorized: `no—the complete S0.1 HANDOFF at C is immutable during this recovery`
- Program boundary immediate-next-branch creation and first-card hydration authorized: `yes—only after successful exact-main R; S0 next is phase/s1-shell-design / S1.1`
- PR creation, merge commits, force push, divergent-main repair, deployment, signing, TestFlight upload, App Store, repository settings, secrets, and every external mutation not explicitly named above: `forbidden`
- Required verification tier: `P12` unchanged

## S0 boundary-recovery state machine

1. Construct R locally from clean C by changing exactly the four authority paths. Commit them together once. Do not stage or change any other path, and do not push R separately before post-commit G0.
2. Fresh post-commit G0 requires local branch `phase/s0-foundation`, clean local HEAD=R, `R^=C`, exactly one commit in `C..R`, exact four-path diff, exact pinned hashes/anchors, historical A0/I3/card-run/C/HANDOFF evidence unchanged, selector/workflow/implementation bytes unchanged, remote phase=C, remote main=C, remote HEAD=C, and S1 absent locally/remotely. Any mismatch stops without ref mutation.
3. Immediately re-read remote phase. Require exact C, permit no intervening push, non-force push local R to `refs/heads/phase/s0-foundation`, and verify remote phase=R. Any rejection or mismatch stops.
4. Immediately re-read remote phase and main. Require phase=R and main=C, permit no intervening push, non-force fast-forward R to `refs/heads/main`, and verify remote phase=main=remote HEAD=R. Any non-fast-forward, rejection, or mismatch stops without reconciliation.
5. Search all named workflow-dispatch candidates at `ref=main/head_sha=R`. Run `31567299022` at C is historical failure, not an R candidate, and must never be rerun. If a matching candidate is successful, accept it; if queued/in-progress, watch it; if terminal non-success, stop permanently. Dispatch exactly once with `run_ui_smoke=true` only when no matching candidate exists, then require exact `head_sha=R`. No edit, rerun, or further recovery is allowed after a non-green R decision.
6. After matching success, download and verify the exact artifact/evidence and reprove remote phase=main=remote HEAD=R with S1 absent. R then becomes the accepted S0 phase-close and S1 phase-main/card base; it remains authority-only and never replaces I3 as S0.1 implementation evidence.
7. S1 next-ref recovery: valid local `phase/s1-shell-design` state is absent, R, or an exact CURRENT_TASK-only S1.1 authority A directly after R; valid remote state is absent or that exact A. From absent/R, create the local branch at R, hydrate only S1.1 under runbook Section 3, set S1 `P=M=R`, record accepted R run evidence, and commit only CURRENT_TASK as A. If local exact A and remote absent, non-force create remote at A; if remote exact A exists, check out/resume it. Require local/remote A equality. Any other collision/content stops. Fresh S1 G0 must prove `R..A` changes only CURRENT_TASK.
8. Resume the ordinary frozen program only after fresh S1.1 G0 passes. Generalize the normal state machine only to each immediate next mapped card/phase. After S9.1, create no S10 branch and stop for owner-only S9.2/S9.3.

## Allowed paths

- `AGENTS.md`
- `docs/product/BUILD_PLAN_V4.md`
- `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`
- `docs/execution/CURRENT_TASK.md`

These four paths are authorized only for the single authority-only R commit. After R, all four are read-only until successful exact-main R permits the one CURRENT_TASK-only S1.1 authority commit. No standing HANDOFF or selector exception applies during R. No glob, directory root, additional path, deletion, or rename is authorized.

## Forbidden paths

- `docs/execution/HANDOFF.md`, `.github/workflows/ios-ci.yml`, `Scripts/ci-selection.json`, every script under `Scripts/`, `.codex/**`, `.gitattributes`, `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md`, `docs/execution/DECISIONS.md`, and `docs/execution/KNOWN_BUGS.md`
- Every project, app, test, fixture, asset, release, package, entitlement, permission, signing, team/profile, secret, dependency, lockfile, generator, or other repository path not individually allowed above
- Every product behavior, schema, UI, navigation, pack, persistence, camera, report, backup, StoreKit, analytics, feedback, deployment, signing, upload, submission, or adjacent implementation change

## Project, implementation, and persistence delta

- Project integration mode: `none—preserve accepted I3/C bytes`
- Exact permitted project/app/test/script semantic delta: `none`
- Persistent-schema delta: `none`
- Workflow/selector/tier/timeout delta: `none`; preserve exact workflow hash, exact selector bytes, and P12 `120/180/180/240/720`
- HANDOFF delta: `none`; the complete S0.1 entry remains byte-identical
- Authority delta: record exactly the one R boundary recovery and its closed ref/run/next-phase rules in the four allowed documents

## Acceptance

| ID | Precondition/reset | Ordered actions | Expected checkpoints | Evidence path |
|---|---|---|---|---|
| GOLDEN | Clean C; remote phase/main/HEAD=C; S1 absent; accepted I3 run/HANDOFF; exact selector/workflow/toolchain; failed C run diagnosed before build | Create exact four-doc R; post-R G0; non-force phase C→R; non-force main C→R; reuse/dispatch one main/head=R UI-enabled P12 run; verify evidence | (1) R direct child C and exact four-path diff; (2) no implementation/HANDOFF/workflow/selector/tier/timeout change; (3) phase/main refs advance only C→R; (4) selector/P12 validates unchanged; (5) pinned runner/Xcode/Simulator route builds, tests, and runs exact S0.1 UI smoke; (6) exact R run succeeds within 720s with required artifacts/checksums; (7) R becomes S1 P=M only after success | Git history/remote-ref proofs plus the sole matching successful `main/head_sha=R` run and downloaded `ios-ci-<run_id>-<run_attempt>` artifact |
| ALT-1 | `NONE` | `NONE` | `NONE`; a terminal non-green R run, unavailable pinned environment, ref mismatch, or non-fast-forward is a permanent stop | `NONE` |

## Explicitly out of scope

- Rerunning or modifying S0.1; changing C or HANDOFF; changing any app/project/test/script/selector/workflow byte; changing P12 values; implementing S1 before accepted R; adding any adjacent product or CI behavior
- Any second R, R2, boundary fix, duplicate dispatch, timeout increase, workflow change, product fix on main, force push, merge commit, PR, signing, upload, deployment, or submission
- S1–S9 implementation before the exact S1.1 authority and fresh G0; S9.2/S9.3 remain owner-only

## Change envelope

- Exact owner-authorized boundary-recovery override: zero production/project/test/script/support paths and exactly four authority-document paths. No HANDOFF, selector, workflow, additional path, deletion, or rename.

## Verification

- Pre-amendment G0: clean local C; remote HEAD/main/phase=C; S1 absent; exact historical ancestry/scopes; exact prior hashes; successful I3 run and complete HANDOFF; only main/head=C candidate is failed run 31567299022; failure remained in CoreLocationMigrator through 02:58 and exited 124 before xcodebuild.
- Post-R Windows structural checks: clean local R directly parents C; one commit in C..R; exact four-path name-status; `git diff --check`; plan/runbook/workflow hashes; anchors unique; zero unresolved owner placeholders; all product behavior and product implementation bytes outside the four authority documents, and all HANDOFF/workflow/selector bytes, unchanged from C; exact selector SHA-256 remains `9E0050FEA98E2E99F37A9113B11B58450AA16B73E99F6842BEBEA09F338C929C`.
- Ref gates: before phase push remote phase/main=C; after phase push phase=R/main=C; before main push same; after main push remote phase/main/HEAD=R; all pushes non-force and no reconciliation.
- Exact selector object: `{"schemaVersion":1,"taskID":"S0.1","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":120,"buildTimeoutSeconds":180,"testTimeoutSeconds":180,"uiTimeoutSeconds":240,"totalBudgetSeconds":720,"unitTestSelectors":["FieldEvidenceAppTests/S0LaunchTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S0LaunchUITests"]}`
- Exact timeout preset: `P12 = setup/artifacts 120s / build 180s / unit 180s / UI 240s / total 720s`
- CI commands remain workflow-owned and unchanged: `bash Scripts/run-with-timeout.sh 180 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 180 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 240 bash Scripts/ui-smoke.sh`.
- Expected CI artifact: `ios-ci-<run_id>-<run_attempt>` containing nonempty build/test/UI logs, three result bundles, nonempty final screenshot, runner/Xcode/build-settings/Simulator/selection/run evidence, setup/evidence budget records, and relative SHA256SUMS under its `FieldEvidenceCI` root.
- Never invoke local Xcode/xcodebuild/Simulator/XcodeBuildMCP.

## Stop and ask

- Any source/hash/authority/ancestry/path/dirty-state mismatch; R not a direct child of C; extra C..R commit/path; any changed implementation/HANDOFF/workflow/selector/tier/timeout/product behavior or product implementation byte outside the four authority documents; remote phase/main not exact expected value; S1 collision; unavailable operation; intervening movement; rejected/non-fast-forward push; duplicate or ambiguous R candidate; any terminal non-success R run; ambiguous S1.1 hydration; unresolved owner input; or any unlisted external write

## Definition of done

- R is one direct-child four-authority-document commit after C; post-R G0 passes; remote phase and main advance non-force from C to R with exact pre/post proofs; the sole matching UI-enabled P12 main/head=R run is green and its artifact/checksums pass; no implementation/HANDOFF/workflow/selector/tier/timeout/product behavior or product implementation byte outside the four authority documents changed.
- After accepted R, create/resume only `phase/s1-shell-design`, hydrate only S1.1 in a CURRENT_TASK-only A directly after R with S1 `P=M=R` and exact R-run predecessor evidence, push non-force, and pass fresh S1.1 G0.
- Continue the same persistent goal through the frozen map. After S9.1, report final C/main-run evidence and stop without S10 or owner-only S9.2/S9.3 actions.
- Next planned task: `S1.1`; start it automatically only after successful exact-main R and the full recovery state machine.
