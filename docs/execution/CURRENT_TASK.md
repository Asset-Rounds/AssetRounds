# Current Task

- Phase / card ID and global order: `S0 / S0.1 / 1 of 36`
- Phase autopilot enabled / exact ordered authorized same-phase card span: `yes` / `S0.1`
- Autopilot transition rule: only after accepted exact-head CI; only the immediate next runbook card inside the span; commit exactly prior HANDOFF append plus next CURRENT_TASK; fresh G0 before implementation; ambiguity or owner input stops; boundary commits final HANDOFF only when explicitly authorized, then stops. Immediately before either bookkeeping push, prove the remote phase ref still equals accepted `I`/`I2`; use non-force push only and then prove the remote ref equals the new bookkeeping commit. The enabled state, ordered span, transition-authorization flag, and boundary-authorization flag are owner-set here and immutable during Codex transitions.
- Card position in phase / runbook-marked phase boundary: `1 of 1` / `yes`
- Predecessor card IDs: `NONE—S0.1 is the first coding card`
- Required predecessor evidence: `N/A—first implementation; project/scripts do not exist yet`
- Integrated/base SHA `M`: `c3e536a03775cc8d25f42a8e31c2f24db4390d4d` (owner replacement bootstrap `B`; local `main`, `origin/main`, and `origin/HEAD` matched at branch creation)
- Task-start authority HEAD `A`: `OBSERVE AT G0; record in HANDOFF, never self-record here`
- Required `M..A` authority-only path set and expected diff: exactly `docs/execution/CURRENT_TASK.md`, changed from the unhydrated template to this S0.1 contract; no other path
- Pre-existing dirty paths and owner/disposition: `NONE`; stop at G0 if any uncommitted or untracked path exists
- Build-plan path: `docs/product/BUILD_PLAN_V4.md`
- Build-plan SHA-256 over exact bytes: `BC1AA5E8C1F8F34A640EBC1A559F0B3A97603F7918B280AA96490A3B7D718481`
- Exact plan heading anchors: `## 11. Build slices and release gates`; `## 16. Owner preparation checklist`; `## 18. Codex execution authority`
- Implementation-runbook path: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`
- Implementation-runbook SHA-256 over exact bytes: `6542CD37BF61A6D2CC50EDAEBA53E94E3F80CDA2DF43C08B8739AAC2CB091738`
- Selected runbook card ID and heading anchor: `S0.1` / `### S0.1 — Repository and unsigned CI baseline`
- Outcome: `checked-in project, shared scheme, synchronized groups, launch-only app, unit/UI targets, four bounded scripts, validated selector file, and fail-closed CI evidence.`
- Product mode: `single-user, device-local V4`
- Starting fixture/state: replacement bootstrap `B` contains only frozen authority/templates, `.codex/config.toml`, `.gitattributes`, and the manual unsigned CI workflow; there is no Xcode project, app source, test target, `Scripts/` directory, persistence, product fixture, or prior iOS CI run
- Execution route: `Windows authoring → GitHub Actions macOS verification`
- Authoring host OS/build: `Microsoft Windows 11 Home, 64-bit, version 10.0.26200, build 26200`
- GitHub repository / visibility and branch-control posture / base branch / phase branch: `palatis3/AssetRounds` / `private solo repository; no server-enforced main protection required; Codex push/merge/force-push/write to main forbidden; owner-only main writes and exact-ref checks` / `main` / `phase/s0-foundation`
- CI workflow path / workflow file SHA-256 / trigger / branch ref: `.github/workflows/ios-ci.yml` / `421DDE01B6B034D3C9E87F3D62430A922F4FB987E04140E5A78173E24C03F4FD` / `workflow_dispatch` with `run_ui_smoke=true` / `phase/s0-foundation`
- Dispatch-head rule: immediately before dispatch, verify `refs/heads/phase/s0-foundation` points to implementation commit `I` or the one allowed `I2`, permit no intervening push, and require returned `head_sha` equality; record the actual expected/ref-head SHA only in HANDOFF after it exists
- Hosted-macOS runner label / expected Xcode version+build: `macos-26` / `Xcode 26.6, Build version 17F113, DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer`
- Minimum iOS deployment target: `18.0`
- Project or workspace / target / shared scheme / configuration: `FieldEvidenceApp.xcodeproj` / `FieldEvidenceApp` / `FieldEvidenceApp` / `Debug`
- CI Simulator model / OS selector: `iPhone 17` / `iOS 26.5` (UDID resolves per ephemeral job and is never reused)
- UI-smoke mode: `CI XCUITest (P12)`
- Allowed GitHub/MCP tool methods and exact repository/ref/workflow arguments/operations: local read-only `git status`, `git rev-parse`, `git diff`, `git show`, `git ls-remote`; local task-owned explicit-path `git add`, `git commit`; only `git push origin HEAD:refs/heads/phase/s0-foundation` (non-force); `gh repo view palatis3/AssetRounds`; `gh workflow view .github/workflows/ios-ci.yml --repo palatis3/AssetRounds`; one normal dispatch plus one diagnosed-fix dispatch maximum via `gh workflow run .github/workflows/ios-ci.yml --repo palatis3/AssetRounds --ref phase/s0-foundation -f run_ui_smoke=true`; matching-run-only `gh run list`, `gh run view`, `gh run watch`, and `gh run download`. `XcodeBuildMCP = disabled`; no PR, issue, merge, release, settings, secrets, collaborator, or `main` mutation method is authorized.
- Owner-required sandbox / approval / command-network / trusted-config / GitHub-tool posture: project-scoped `.codex/config.toml` trusted; `sandbox_mode=workspace-write`; `approval_policy=on-request`; general command network disabled except exact bounded Git/GitHub operations above when individually authorized; goals enabled; GitHub plugin constrained above; XcodeBuildMCP disabled; tool visibility is not authority
- G0 observation rule: record actual effective posture in HANDOFF; stop if a required operation is unavailable, posture contradicts this contract, or an unlisted external write tool is approved/enabled
- G0 selector-transition rule: `Scripts/ci-selection.json` may be absent for S0.1; after G0 passes, create the exact object below as the first implementation-support mutation and require it to match before I/I2 or dispatch
- Task-owned implementation commit authorized: `yes—one I, plus one I2 only after a diagnosed first-run failure`
- Exact phase-branch push authorized: `yes—only HEAD:refs/heads/phase/s0-foundation; never main; non-force only`
- Named CI workflow dispatch authorized: `yes—only the workflow/ref/input above, once normally and once after the single authorized fix`
- Named run inspection + artifact download authorized: `yes—only the run whose head_sha is the exact I/I2 being evaluated`
- Same-phase post-green transition commit/push authorized: `no—S0 has one card and no same-phase successor`
- Phase-boundary HANDOFF-only commit/push authorized: `yes—after accepted exact-head CI, with the remote-ref pre/post checks above; then stop before main/merge/main CI/new branch/S1`
- PR creation/merge, any Codex write to `main`, deployment, signing, TestFlight upload, App Store, repository settings, secrets, and other external mutation: `forbidden`
- Required verification tier: `P12`

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
| GOLDEN | Clean authority `A`; no project/scripts; fresh pinned ephemeral Simulator; `run_ui_smoke=true` | Implement exact paths; create I; prove remote ref=I; dispatch; CI builds/tests/launches, inert-taps screen, captures evidence | (1) exact selector/P12 validates; (2) shared scheme resolves three targets at iOS 18.0; (3) unsigned build/app product/Build.xcresult exist; (4) S0 unit class executes non-skipped; (5) fresh app reaches foreground; (6) root/title identifiers and visible untruncated title persist after inert tap at accessibility XXXL; (7) selectors/artifacts/checksums validate within 720s | Matching exact-head run and downloaded `FieldEvidenceCI` artifact with logs, result bundles, screenshot, runner/toolchain/selection records, SHA256SUMS |
| ALT-1 | `NONE` | `NONE` | `NONE`; unavailable or mismatched pinned runner/Xcode/runtime/device is a stop, not alternate implementation | `NONE` |

## Explicitly out of scope

- Everything after the static launch screen, all S1–S9 behavior, visual polish beyond system baseline, icons/App Store assets, physical-device proof, signing/archive/upload, refactoring, or generalized infrastructure
- Owned launch-smoke IDs: `baseline`
- Exact terminal screen/data artifact: one responsive static screen showing `AssetRounds` then `Sign Inspection`; no data/navigation/control/permission/product state
- Future controls omitted: signs/reports/settings/onboarding/checks/packs/persistence/camera/reports/share/backup/paywall/diagnostics/feedback/release

## Change envelope

- Exact S0.1 override: five production/project paths and six test/support paths; selector and HANDOFF excluded. No additional path, deletion, or rename.

## Verification

- Windows structural/read-only checks: clean status; HEAD/ancestry; `git diff --name-only M..A` exactly CURRENT_TASK; plan/runbook/workflow SHA-256; exact remote refs/repo/workflow; after implementation exact allowed paths/selector/script LF+100755/project structure and no forbidden settings. Never invoke local Xcode/xcodebuild/Simulator/XcodeBuildMCP.
- CI incremental build command: `bash Scripts/run-with-timeout.sh 180 bash Scripts/build-smoke.sh`, unsigned build-for-testing, shared DerivedData, `Build.xcresult`
- CI targeted test command: `bash Scripts/run-with-timeout.sh 180 bash Scripts/test-smoke.sh`, exact `-only-testing:FieldEvidenceAppTests/S0LaunchTests`, `UnitTests.xcresult`
- CI UI-smoke command/checkpoints: `bash Scripts/run-with-timeout.sh 240 bash Scripts/ui-smoke.sh`, exact `-only-testing:FieldEvidenceAppUITests/S0LaunchUITests`, `UISmoke.xcresult`, final screenshot; XCUITest launches with `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`
- Exact `ci-selection.json` object: `{"schemaVersion":1,"taskID":"S0.1","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":120,"buildTimeoutSeconds":180,"testTimeoutSeconds":180,"uiTimeoutSeconds":240,"totalBudgetSeconds":720,"unitTestSelectors":["FieldEvidenceAppTests/S0LaunchTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S0LaunchUITests"]}`
- Exact timeout preset: `P12 = setup/artifacts 120s / build 180s / unit 180s / UI 240s / total 720s`
- Expected CI artifacts: nonempty build/test/UI logs, three result bundles, nonempty final screenshot, runner/Xcode/build-settings/Simulator/selection/run evidence, and relative SHA256SUMS
- Accessibility: no interactive control; title is semantic system header, first in reading order, system colors/no color-only state, visible/untruncated at `UIContentSizeCategory.accessibilityExtraExtraExtraLarge`; other interaction checks N/A

## Stop and ask

- Any source/hash/card/span/branch/ref/authority/dirty-path/posture mismatch; any unexpected ref movement; missing required route; forbidden or extra path; any new package/target/workspace/generator/permission/schema/backend/auth/payment/analytics/signing/service/deployment; unresolved selector/artifact; user work overwrite; second non-green run; or unlisted external write action

## Definition of done

- Every GOLDEN checkpoint passes in one exact-head P12 run; both selected classes execute non-skipped; artifacts/checksums validate within budget; diff is exact; no adjacent behavior appears; KNOWN_BUGS is read and no primary blocker is accepted
- After exact-head green CI, append complete S0.1 HANDOFF outside I/I2. Because boundary flag is `yes`, prove remote phase ref still equals I/I2, commit only HANDOFF, non-force push, prove remote ref equals that bookkeeping commit, name S1.1, and stop
- Owner outside this `/goal` reviews/merges phase branch, verifies exact resulting `main`, runs UI-enabled matching-head main CI, then prepares S1
- Next planned task remains unstarted: `S1.1`
