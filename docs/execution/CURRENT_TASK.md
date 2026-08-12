# Current Task

- Phase / card ID and global order: `S0 / S0.1 / 1 of 36`
- Program autopilot enabled / exact ordered phase→branch→card map / final owner-only boundary: `yes` / `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1` / `stop after accepted S9.1 exact-main CI; S9.2 signing/TestFlight and S9.3 App Store submission are owner-only`
- Phase autopilot enabled / exact ordered authorized same-phase card span: `yes` / `S0.1`
- Autopilot transition rule: one current card at a time. Same-phase transition requires accepted exact-head CI, immediate next card inside the frozen span, exact HANDOFF-plus-CURRENT_TASK bookkeeping, and fresh G0. Boundary integration follows the exact `P/C/main-run/next-branch` state machine below. Program map, Full access posture, prohibitions, and final owner-only release boundary are immutable; ambiguity or missing owner input stops.
- Card position in phase / runbook-marked phase boundary: `1 of 1` / `yes`
- Predecessor card IDs: `NONE—S0.1 is the first coding card`
- Required predecessor evidence: `N/A—first implementation; project/scripts do not exist yet`
- Immutable phase-main base SHA `P`: `c3e536a03775cc8d25f42a8e31c2f24db4390d4d` (S0 bootstrap `B`; must remain unchanged throughout S0 and equal remote `main` until phase-close integration)
- Integrated/base SHA `M`: `c3e536a03775cc8d25f42a8e31c2f24db4390d4d` (owner replacement bootstrap `B`; local `main`, `origin/main`, and `origin/HEAD` matched at branch creation)
- Task-start authority HEAD `A`: `OBSERVE AT G0; record in HANDOFF, never self-record here`
- Required `M..A` authority-only path set and expected diff: exactly `.codex/config.toml`, `.github/workflows/ios-ci.yml`, `AGENTS.md`, `docs/product/BUILD_PLAN_V4.md`, `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md`, `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`, `docs/execution/CURRENT_TASK.md`, `docs/execution/DECISIONS.md`, and `docs/execution/HANDOFF.md`; cumulative pre-S0 owner-approved D-004/D-005/D-006 authority/config/CI amendment plus hydrated S0.1, with no app/project/test/script implementation path
- Pre-existing dirty paths and owner/disposition: `NONE`; stop at G0 if any uncommitted or untracked path exists
- Build-plan path: `docs/product/BUILD_PLAN_V4.md`
- Build-plan SHA-256 over exact bytes: `DA877E7C720BD29203B0340FA47B64AB553B98380432DDD925C4A8FE782D5C70`
- Exact plan heading anchors: `## 11. Build slices and release gates`; `## 16. Owner preparation checklist`; `## 18. Codex execution authority`
- Implementation-runbook path: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`
- Implementation-runbook SHA-256 over exact bytes: `1D56FDCB9CB3226865E430D45BFF0247BA9F7D095279FF5070FACF4BD7453338`
- Selected runbook card ID and heading anchor: `S0.1` / `### S0.1 — Repository and unsigned CI baseline`
- Outcome: `checked-in project, shared scheme, synchronized groups, launch-only app, unit/UI targets, four bounded scripts, validated selector file, and fail-closed CI evidence.`
- Product mode: `single-user, device-local V4`
- Starting fixture/state: replacement bootstrap `B` contains only frozen authority/templates, `.codex/config.toml`, `.gitattributes`, and the manual unsigned CI workflow; there is no Xcode project, app source, test target, `Scripts/` directory, persistence, product fixture, or prior iOS CI run
- Execution route: `Windows authoring → GitHub Actions macOS verification`
- Authoring host OS/build: `Microsoft Windows 11 Home, 64-bit, version 10.0.26200, build 26200`
- GitHub repository / visibility and branch-control posture / base branch / phase branch: `palatis3/AssetRounds` / `private solo repository; no server-enforced main protection required; only the exact non-force program-main update below is allowed; every force push, merge commit, divergent-main repair, and other main write is forbidden` / `main` / `phase/s0-foundation`
- CI workflow path / workflow file SHA-256 / trigger / branch ref: `.github/workflows/ios-ci.yml` / `ED3865E07A5CD25B641B75D049F4D6376EF42D8B0ABDF85570DBED6786FEF771` / `workflow_dispatch` with `run_ui_smoke=true` / `phase/s0-foundation`
- Dispatch-head rule: immediately before dispatch, verify `refs/heads/phase/s0-foundation` points to implementation commit `I` or the one allowed `I2`, permit no intervening push, and require returned `head_sha` equality; record the actual expected/ref-head SHA only in HANDOFF after it exists
- Hosted-macOS runner label / expected Xcode version+build: `macos-26` / `Xcode 26.6, Build version 17F113, DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer`
- Minimum iOS deployment target: `18.0`
- Project or workspace / target / shared scheme / configuration: `FieldEvidenceApp.xcodeproj` / `FieldEvidenceApp` / `FieldEvidenceApp` / `Debug`
- CI Simulator model / OS selector: `iPhone 17` / `iOS 26.5` (UDID resolves per ephemeral job and is never reused)
- UI-smoke mode: `CI XCUITest (P12)`
- Allowed GitHub/MCP tool methods and exact repository/ref/workflow arguments/operations: read-only `git status`, `git rev-parse`, `git diff`, `git show`, `git branch --show-current`, `git ls-remote`; explicit-path `git add|commit`; non-force `git push origin HEAD:refs/heads/phase/s0-foundation`; card CI `gh workflow run .github/workflows/ios-ci.yml --repo palatis3/AssetRounds --ref phase/s0-foundation -f run_ui_smoke=true`; at C only, non-force `git push origin <C>:refs/heads/main`; main CI `gh workflow run .github/workflows/ios-ci.yml --repo palatis3/AssetRounds --ref main -f run_ui_smoke=true` only when no named workflow-dispatch candidate at ref main/head C exists; matching-run-only `gh run list|view|watch|download`; boundary-only `git switch -c phase/s1-shell-design <C>` or switch to an exact valid local A, explicit CURRENT_TASK commit, then non-force `git push origin <A>:refs/heads/phase/s1-shell-design`; repo/workflow view. Later authority rotates only current/immediate-next mapped refs and selector input. `XcodeBuildMCP=disabled`; no force push, PR, issue, merge commit, release, settings, secrets, collaborator, signing, upload, deployment, or submission operation.
- Owner-required sandbox / approval / command-network / trusted-config / GitHub-tool posture: owner GUI/session Full access; `sandbox_mode=danger-full-access`; `approval_policy=never`; command network enabled; project trusted; goals enabled; GitHub available; XcodeBuildMCP disabled. Broader enabled capability is not authority and not a G0 blocker; actual use remains limited to named paths and operations.
- G0 observation rule: record effective posture in HANDOFF; stop only if a required operation is unavailable or an intended action exceeds this contract. Do not stop merely because other tools, connectors, credentials, filesystem locations, or network access are available.
- G0 selector-transition rule: `Scripts/ci-selection.json` may be absent for S0.1; after G0 passes, create the exact object below as the first implementation-support mutation and require it to match before I/I2 or dispatch
- Task-owned implementation commit authorized: `yes—one I, plus one I2 only after a diagnosed first-run failure`
- Exact phase-branch push authorized: `yes—only the current mapped ref; non-force only`
- Named CI workflow dispatch authorized: `yes—only the workflow/ref/input above, once normally and once after the single authorized fix`
- Named run inspection + artifact download authorized: `yes—only the card run whose head_sha=I/I2 or the named main workflow-dispatch candidate whose ref=main and head_sha=C`
- Same-phase post-green transition commit/push authorized: `no—S0 has one card and no same-phase successor`
- Phase-boundary HANDOFF-only commit/push authorized: `yes—after accepted exact-head CI, with exact phase-ref pre/post checks`
- Program boundary integration / exact-main CI / immediate-next-branch creation and first-card hydration authorized: `yes / yes / yes—only the frozen state machine below; S0 next is phase/s1-shell-design`
- PR creation, merge commits, force push, divergent-main repair, deployment, signing, TestFlight upload, App Store, repository settings, secrets, and every external mutation not explicitly named above: `forbidden`
- Required verification tier: `P12`

## Boundary continuation state machine

1. Before accepted card CI, no boundary action is permitted. After green `I`/`I2`, append HANDOFF, require remote phase ref=`I`/`I2`, commit only HANDOFF as `C`, non-force push, and require remote phase ref=`C`. If an exact HANDOFF-only `C` already exists, validate it and never rerun/re-edit S0.1.
2. Read remote `main` (remote is authoritative; local `main` may remain stale). `main=P` permits exactly one non-force `C:refs/heads/main` push; `main=C` resumes; any other value stops. Require remote phase ref=`C` and remote main=`C`.
3. Any named workflow-dispatch run with `ref=main` and `head_sha=C` is the existing candidate. Matching success is accepted; queued/in-progress is watched; every terminal non-success stops with no product fix on main; dispatch exactly once only if none exists (the workflow enforces UI-input equality). Then recheck both remote phase and main refs=`C`.
4. S0 next-ref recovery: valid local state is absent, C, or exact CURRENT_TASK-only A; valid remote state is absent or that exact A. From absent/C, hydrate S1.1 and commit A. If local is exact A and remote is absent, non-force create remote at A; if remote exact A exists, check out/resume it. Require local and remote A equality. Any other combination/content stops. Fresh S1 G0 must prove C..A exactly CURRENT_TASK.
5. Generalize Step 4 only to the immediate next frozen map entry. After S9.1, create no S10 branch and no post-C main commit; report C plus main-run ID/URL/head in the goal final response so S9.2 can re-query it.

## Allowed paths

- `FieldEvidenceApp.xcodeproj/project.pbxproj`
- `FieldEvidenceApp.xcodeproj/xcshareddata/xcschemes/FieldEvidenceApp.xcscheme`
- `FieldEvidenceApp/App/FieldEvidenceAppApp.swift`
- `FieldEvidenceApp/App/LaunchView.swift`
- `FieldEvidenceApp/Resources/Assets.xcassets/Contents.json`
- `FieldEvidenceAppTests/S0LaunchTests.swift`
- `FieldEvidenceAppUITests/S0LaunchUITests.swift`
- `Scripts/build-smoke.sh`
- `Scripts/test-smoke.sh`
- `Scripts/ui-smoke.sh`
- `Scripts/run-with-timeout.sh`
- `Scripts/ci-selection.json` (exact selected-card object; standing exception excluded from cap)
- `docs/execution/HANDOFF.md` (append-only exception after exact-head CI; never in I/I2)

The eleven counted implementation paths above are exact individual file paths: five production/project and six test/support paths under the S0.1 runbook override. Selector and HANDOFF are standing exceptions. No glob, directory root, delete, rename, or additional path is authorized.

## Forbidden paths

- `.github/workflows/ios-ci.yml`, `.codex/**`, `.gitattributes`, `AGENTS.md`, `docs/product/BUILD_PLAN_V4.md`, `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md`, `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`, `docs/execution/CURRENT_TASK.md`, `docs/execution/DECISIONS.md`, and `docs/execution/KNOWN_BUGS.md`
- Every app, test, or script path not individually named above; all `DesignSystem`, `Domain`, `Features`, `Infrastructure`, `PreviewSupport`, `TestFixtures`, `Release`, workspace, plist/storyboard/icon, entitlement, package, dependency-lock, generator, signing/team/profile, and secret paths
- Tabs, navigation, onboarding, settings, persistence, packs, camera, reports, backup, StoreKit, backend/auth/sync, analytics, deployment, signing, and release behavior

## Project and persistence delta

- Project integration mode: `S0 checked-in project/shared scheme`
- Exact permitted project-file semantic delta: create a valid checked-in `FieldEvidenceApp.xcodeproj` without generator/workspace; PBX file-system-synchronized roots for app/unit/UI roots; exactly three iPhone targets `FieldEvidenceApp`, `FieldEvidenceAppTests`, `FieldEvidenceAppUITests`; iOS 18.0 all configurations; generated Info.plists/launch-screen settings; bundle IDs `com.palatis3.fieldrecord`, `com.palatis3.fieldrecord.tests`, `com.palatis3.fieldrecord.uitests`; display name `AssetRounds`; shared scheme builds app, tests both targets, launches app, uses Debug run/test and Release archive; no team/signing/profile/entitlement/capability/permission/package/schema. App is only `FieldEvidenceAppApp` plus system-styled `LaunchView` showing `AssetRounds` and `Sign Inspection`, with identifiers `s0.launch.screen` and `s0.launch.title`; no control/navigation.
- Persistent-schema delta: `none`
- Disposable dev-store reset: `UI smoke may uninstall only com.palatis3.fieldrecord from the exact resolved CI_SIMULATOR_UDID; never erase the Simulator`
- Script contract: four LF executable `100755` scripts. Timeout wrapper accepts positive seconds+command, owns process group, TERM then ≤5s then KILL, returns child status or 124. Build uses unsigned build-for-testing and Build.xcresult; unit/UI use safe exact `-only-testing` args without eval and shared DerivedData; UI targets only resolved UDID, uninstalls only app bundle, writes UISmoke.xcresult and nonempty ui-final.png; all outputs stay in runner temp except Simulator app state.

## Acceptance

| ID | Precondition/reset | Ordered user actions | Expected checkpoints | Evidence path |
|---|---|---|---|---|
| GOLDEN | Clean authority `A`; no project/scripts; fresh pinned ephemeral Simulator; `run_ui_smoke=true` | Implement exact paths; create I; prove remote ref=I; dispatch; CI builds/tests/launches, inert-taps screen, captures evidence | (1) exact selector/P12 validates; (2) shared scheme resolves three targets at iOS 18.0; (3) unsigned build/app product/Build.xcresult exist; (4) S0 unit class executes non-skipped; (5) fresh app reaches foreground; (6) root/title identifiers and visible untruncated title persist after inert tap at accessibility XXXL; (7) selectors/artifacts/checksums validate within 720s | Matching exact-head run and downloaded `ios-ci-<run_id>-<run_attempt>` artifact with `FieldEvidenceCI` contents, result bundles, screenshot, runner/toolchain/selection records, and SHA256SUMS |
| ALT-1 | `NONE` | `NONE` | `NONE`; unavailable or mismatched pinned runner/Xcode/runtime/device is a stop, not alternate implementation | `NONE` |

## Explicitly out of scope

- Everything after the static launch screen, all S1–S9 behavior, visual polish beyond system baseline, icons/App Store assets, physical-device proof, signing/archive/upload, refactoring, or generalized infrastructure
- Owned launch-smoke IDs: `baseline`
- Exact terminal screen/data artifact: one responsive static screen showing `AssetRounds` then `Sign Inspection`; no data/navigation/control/permission/product state
- Future controls omitted: signs/reports/settings/onboarding/checks/packs/persistence/camera/reports/share/backup/paywall/diagnostics/feedback/release

## Change envelope

- Exact S0.1 override: five production/project paths and six test/support paths; selector and HANDOFF excluded. No additional path, deletion, or rename.

## Verification

- Windows structural/read-only checks: clean status; HEAD/ancestry; immutable `P`; `git diff --name-only M..A` exactly the nine declared authority/config/CI paths; plan/runbook/workflow SHA-256; exact remote refs/repo/workflow; after implementation exact allowed paths/selector/script LF+100755/project structure and no forbidden settings. Never invoke local Xcode/xcodebuild/Simulator/XcodeBuildMCP.
- CI incremental build command: `bash Scripts/run-with-timeout.sh 180 bash Scripts/build-smoke.sh`, unsigned build-for-testing, shared DerivedData, `Build.xcresult`
- CI targeted test command: `bash Scripts/run-with-timeout.sh 180 bash Scripts/test-smoke.sh`, exact `-only-testing:FieldEvidenceAppTests/S0LaunchTests`, `UnitTests.xcresult`
- CI UI-smoke command/checkpoints: `bash Scripts/run-with-timeout.sh 240 bash Scripts/ui-smoke.sh`, exact `-only-testing:FieldEvidenceAppUITests/S0LaunchUITests`, `UISmoke.xcresult`, final screenshot; XCUITest launches with `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`
- Exact `ci-selection.json` object: `{"schemaVersion":1,"taskID":"S0.1","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":120,"buildTimeoutSeconds":180,"testTimeoutSeconds":180,"uiTimeoutSeconds":240,"totalBudgetSeconds":720,"unitTestSelectors":["FieldEvidenceAppTests/S0LaunchTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S0LaunchUITests"]}`
- Exact timeout preset: `P12 = setup/artifacts 120s / build 180s / unit 180s / UI 240s / total 720s`
- Expected CI artifact: GitHub artifact named `ios-ci-<run_id>-<run_attempt>` containing nonempty build/test/UI logs, three result bundles, nonempty final screenshot, runner/Xcode/build-settings/Simulator/selection/run evidence, setup/evidence budget records, and relative SHA256SUMS under its `FieldEvidenceCI` content root
- Accessibility: no interactive control; title is semantic system header, first in reading order, system colors/no color-only state, visible/untruncated at `UIContentSizeCategory.accessibilityExtraExtraExtraLarge`; other interaction checks N/A

## Stop and ask

- Any source/hash/card/span/branch/ref/authority/dirty-path mismatch; unavailable required operation; unexpected ref movement; non-fast-forward; invalid next-branch collision; forbidden/extra path; any unnamed package/target/workspace/generator/permission/schema/backend/auth/payment/analytics/signing/service/deployment; unresolved selector/artifact; user-work overwrite; second non-green card run; any non-green exact-main run; ambiguous hydration; or actual unlisted external write

## Definition of done

- Every GOLDEN checkpoint passes in one exact-head P12 run; both selected classes execute non-skipped; artifacts/checksums validate within budget; diff is exact; no adjacent behavior appears; KNOWN_BUGS is read and no primary blocker is accepted
- After exact-head green CI, append complete S0.1 HANDOFF outside I/I2; prove remote phase ref=I/I2; commit only HANDOFF as phase-close `C`; non-force push and prove phase ref=C.
- Complete the exact idempotent Boundary continuation state machine above, including phase+main reproof and valid local/remote next-A recovery combinations. Do not require local `main` to move.
- Continue the same goal through the frozen map. After S9.1, record C/main-run evidence in the goal final response for owner re-query and stop without S10 or a post-C main commit.
- Next planned task: `S1.1`; start it automatically only after the full boundary state machine passes
