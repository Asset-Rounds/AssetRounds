# Current Task

- Phase / card ID and global order: `S0 / S0.1 / 1 of 36`
- Card position in phase / runbook-marked phase boundary: `1 of 1` / `yes`
- Predecessor card IDs: `NONE—S0.1 is the first coding card`
- Required predecessor evidence: `N/A—first implementation; project/scripts do not exist yet`
- Integrated/base SHA `M`: `e8d91bb8b11508c7da62e10c7c493490a76ff830` (owner replacement bootstrap `B`; local `main`, `origin/main`, and `origin/HEAD` matched at branch creation)
- Task-start authority HEAD `A`: `OBSERVE AT G0; record in HANDOFF, never self-record here`
- Required `M..A` authority-only path set and expected diff: exactly `docs/execution/CURRENT_TASK.md`, changed from the unhydrated template to this S0.1 contract; no other path
- Pre-existing dirty paths and owner/disposition: `NONE`; stop at G0 if any uncommitted or untracked path exists
- Build-plan path: `docs/product/BUILD_PLAN_V4.md`
- Build-plan SHA-256 over exact bytes: `3ABBEE1A0A30107643C6B1CC266BD5F395CC7530AE3B948D77DB07F54B562A98`
- Exact plan heading anchors: `## 11. Build slices and release gates`; `## 16. Owner preparation checklist`; `## 18. Codex execution authority`
- Implementation-runbook path: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`
- Implementation-runbook SHA-256 over exact bytes: `E71166FB4F556CC59AF8595B788CB1916FB8F2BC0278ACE635F424E20239E22E`
- Selected runbook card ID and heading anchor: `S0.1` / `### S0.1 — Repository and unsigned CI baseline`
- Outcome: `checked-in project, shared scheme, synchronized groups, launch-only app, unit/UI targets, four bounded scripts, validated selector file, and fail-closed CI evidence.`
- Product mode: `single-user, device-local V4`
- Starting fixture/state: replacement bootstrap `B` contains only frozen authority/templates, `.codex/config.toml`, `.gitattributes`, and the manual unsigned CI workflow; there is no Xcode project, app source, test target, `Scripts/` directory, persistence, product fixture, or prior iOS CI run
- Execution route: `Windows authoring → GitHub Actions macOS verification`
- Authoring host OS/build: `Windows 10 Home 64-bit, WindowsVersion 2009, OS build 26200`
- GitHub repository / visibility and branch-control posture / base branch / phase branch: `palatis3/AssetRounds` / `private solo repository; no server-enforced main protection required; Codex push/merge/force-push/write to main forbidden; owner-only main writes and exact-ref checks` / `main` / `phase/s0-foundation`
- CI workflow path / workflow file SHA-256 / trigger / branch ref: `.github/workflows/ios-ci.yml` / `421DDE01B6B034D3C9E87F3D62430A922F4FB987E04140E5A78173E24C03F4FD` / `workflow_dispatch` with `run_ui_smoke=true` / `phase/s0-foundation`
- Dispatch-head rule: immediately before dispatch, verify `refs/heads/phase/s0-foundation` points to the implementation commit just created by this task (`I`, or the one allowed fix `I2`), permit no intervening push, and require the run's returned `head_sha` to equal that commit. `A` never contains this future SHA; record the actual expected/ref-head SHA only in `HANDOFF.md` after the implementation commit exists.
- Hosted-macOS runner label / expected Xcode version+build: `macos-26` / `Xcode 26.6, Build version 17F113, DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer`
- Minimum iOS deployment target: `18.0`
- Project or workspace / target / shared scheme / configuration: `FieldEvidenceApp.xcodeproj` / `FieldEvidenceApp` / `FieldEvidenceApp` / `Debug`
- CI Simulator model / OS selector: `iPhone 17` / `iOS 26.5` (UDID resolves per ephemeral job and is never reused across jobs)
- UI-smoke mode: `CI XCUITest (P12)`
- Allowed GitHub/MCP tool methods and exact repository/ref/workflow arguments/operations: local read-only `git status`, `git rev-parse`, `git diff`, `git show`, `git ls-remote`; local task-owned `git add` with explicit allowed paths, `git commit`, and only `git push origin HEAD:refs/heads/phase/s0-foundation`; `gh repo view palatis3/AssetRounds`; `gh workflow view .github/workflows/ios-ci.yml --repo palatis3/AssetRounds`; exactly one normal dispatch plus one diagnosed rerun maximum via `gh workflow run .github/workflows/ios-ci.yml --repo palatis3/AssetRounds --ref phase/s0-foundation -f run_ui_smoke=true`; matching-run-only `gh run list`, `gh run view`, `gh run watch`, and `gh run download` for `palatis3/AssetRounds`. `XcodeBuildMCP = disabled`; GitHub connector may be used read-only only and grants no write authority; no PR, issue, merge, release, settings, secrets, collaborator, or `main` mutation method is authorized.
- Owner-required sandbox / approval / command-network / trusted-config / GitHub-tool posture: project-scoped `.codex/config.toml` trusted; `sandbox_mode=workspace-write`; `approval_policy=on-request`; general command network disabled except the exact bounded Git/GitHub operations above when individually authorized; GitHub plugin enabled only as constrained above; XcodeBuildMCP disabled; mere visibility of other tools/connectors is not authority
- G0 observation rule: Codex records the actual effective posture in HANDOFF. Stop if a required operation is unavailable, the effective project posture contradicts the owner-required posture, or an unlisted external write tool is explicitly approved/enabled for this task. Mere visibility, installation, or broader credential capability is not authority; never use an unnamed tool or argument.
- Task-owned implementation commit authorized: `yes—one I, plus one I2 only after a diagnosed first-run failure`
- Exact phase-branch push authorized: `yes—only HEAD:refs/heads/phase/s0-foundation; never main`
- Named CI workflow dispatch authorized: `yes—only the workflow/ref/input above, once normally and once more only after the single authorized fix`
- Named run inspection + artifact download authorized: `yes—only the run whose head_sha is the exact I/I2 being evaluated`
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
- `Scripts/ci-selection.json` (exact selected-card CI object only; standing support exception excluded from cap; grants no product scope)
- `docs/execution/HANDOFF.md` (append-only bookkeeping exception after exact-head CI; excluded from cap and never included in I/I2)

The eleven implementation paths above are an exact set, not merely a maximum. `Scripts/ci-selection.json` and append-only `HANDOFF.md` are the only standing exceptions. No delete, rename, or additional path is authorized. Every path is fully expanded and repository-relative.

## Forbidden paths

- `.github/workflows/ios-ci.yml`, `.codex/**`, `.gitattributes`, `AGENTS.md`, `docs/product/BUILD_PLAN_V4.md`, `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md`, `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`, `docs/execution/CURRENT_TASK.md`, `docs/execution/DECISIONS.md`, and `docs/execution/KNOWN_BUGS.md`.
- Every `FieldEvidenceApp/**`, `FieldEvidenceAppTests/**`, `FieldEvidenceAppUITests/**`, and `Scripts/**` path not named in Allowed paths.
- `DesignSystem/**`, `Domain/**`, `Features/**`, `Infrastructure/**`, `PreviewSupport/**`, `TestFixtures/**`, `Release/**`, workspace files, extra plists/storyboards/assets, app icons, entitlements, signing/team/profile settings, packages, dependency lockfiles, project generators, and additional scripts/tests/fixtures.
- Tabs, navigation, onboarding, Settings, persistence/models, packs, camera/photo permissions, reports/PDF, backup, StoreKit/paywall, backend/auth/sync, analytics/diagnostics, deployment, signing, and release behavior.
- Signing credentials, provisioning profiles, `.p8`/`.p12` files, secrets, and real customer data in repository files, logs, fixtures, or artifacts.

## Project and persistence delta

- Project integration mode: `S0 checked-in project/shared scheme`
- Exact permitted project-file semantic delta: manually create a valid checked-in `FieldEvidenceApp.xcodeproj` without a generator or workspace. Use PBX file-system-synchronized root groups for `FieldEvidenceApp`, `FieldEvidenceAppTests`, and `FieldEvidenceAppUITests`; create exactly three iPhone targets named `FieldEvidenceApp`, `FieldEvidenceAppTests`, and `FieldEvidenceAppUITests`; set every target/configuration deployment target to iOS `18.0`; use generated Info.plists and generated launch-screen settings; app bundle ID `com.palatis3.fieldrecord`, unit-test bundle ID `com.palatis3.fieldrecord.tests`, UI-test bundle ID `com.palatis3.fieldrecord.uitests`; product display name `AssetRounds`; app target supports iPhone only; shared scheme `FieldEvidenceApp` builds the app, includes both test targets in TestAction, launches the app target, uses Debug for run/test and Release for archive. Add no DEVELOPMENT_TEAM, signing identity, profile, entitlement, capability, permission string, package, framework beyond Apple SDK defaults, schema, or explicit signing. The app consists only of `FieldEvidenceAppApp` wiring and a system-styled `LaunchView` with visible title `AssetRounds`, subtitle `Sign Inspection`, accessibility root identifier `s0.launch.screen`, and title identifier `s0.launch.title`; no control or navigation.
- Persistent-schema delta: `none`
- Disposable dev-store reset: `active CI Simulator's exact app container only; UI smoke may uninstall only com.palatis3.fieldrecord from the resolved CI_SIMULATOR_UDID; never erase the Simulator`
- Script contract: all four `.sh` files are LF and executable mode `100755`. `run-with-timeout.sh` accepts a positive integer plus command/arguments, runs one process group, forwards the child exit status, and on expiry sends TERM, waits at most five seconds, sends KILL if needed, and returns `124`. `build-smoke.sh` performs unsigned `xcodebuild build-for-testing` with the workflow's exact project/scheme/configuration/destination, one shared `$RUNNER_TEMP/DerivedData`, and `$CI_ARTIFACT_DIR/Build.xcresult`. `test-smoke.sh` safely converts only the selection file's exact unit selectors into `-only-testing` arguments without `eval` and performs `test-without-building` into `UnitTests.xcresult`. `ui-smoke.sh` validates and uses only `$CI_SIMULATOR_UDID`, uninstalls only `com.palatis3.fieldrecord`, boots that exact Simulator when needed, safely converts the exact UI selectors, performs `test-without-building` into `UISmoke.xcresult`, and writes nonempty `ui-final.png`; none may erase all devices or write outside runner temp except normal Simulator app install state.

## Acceptance

| ID | Precondition/reset | Ordered user actions | Expected checkpoints (5–8, not tap count) | Evidence path |
|---|---|---|---|---|
| GOLDEN | Exact clean authority commit `A` on `phase/s0-foundation`; bootstrap has no project/scripts; fresh ephemeral `iPhone 17` / `iOS 26.5`; dispatch input `run_ui_smoke=true` | Implement only allowed paths; create I; verify remote phase ref equals I; dispatch named workflow; workflow resolves its ephemeral Simulator, builds/tests/launches, performs one inert screen tap, and captures evidence | (1) exact 11-key P12 selector and workflow input validate; (2) shared scheme resolves three exact targets and every reported deployment target is 18.0; (3) unsigned build-for-testing yields nonempty app product and `Build.xcresult`; (4) `FieldEvidenceAppTests/S0LaunchTests` executes non-skipped and `UnitTests.xcresult` exists; (5) fresh app install/launch reaches foreground; (6) `s0.launch.screen` and visible/untruncated `s0.launch.title` exist at `UIContentSizeCategory.accessibilityExtraExtraExtraLarge`, remain after one inert tap, and the UI test passes; (7) evidence validator resolves every selector, required artifacts/checksums pass, and setup-through-checksum elapsed time is at most 720 seconds | Matching GitHub Actions run for I/I2; downloaded `FieldEvidenceCI` artifact containing logs, runner/toolchain/selection records, `Build.xcresult`, `UnitTests.xcresult`, `UISmoke.xcresult`, `ui-final.png`, and verified relative `SHA256SUMS.txt` |
| ALT-1 | `NONE` | `NONE` | `NONE`; an unavailable or mismatched pinned runner/Xcode/runtime/device is a G0 or CI stop, not an alternate implementation | `NONE` |

No second alternate/failure family is authorized.

## Explicitly out of scope

- All user workflow beyond one static launch-only screen; all V4 S1–S9 product behavior; visual polish beyond system text/spacing/colors needed for the baseline; app icon and App Store assets; physical-device proof; signing/archive/upload; refactoring or generalized infrastructure.
- Owned launch-smoke IDs: `baseline`
- Exact terminal screen/data artifact for this partial phase: one responsive static launch screen showing `AssetRounds` then `Sign Inspection`; no persistent data, navigation, tab, button, permission, or product state
- Future controls that must be omitted or inert: Signs/Reports tabs, Settings, onboarding, sign/check actions, packs, persistence, camera/import, report/share, backup/restore, paywall/purchase, diagnostics, feedback, and release controls are absent—not placeholders or disabled stubs

## Change envelope

- Exactly eleven counted implementation paths: three app/resource paths plus eight project/test/script paths. `Scripts/ci-selection.json` and append-only `docs/execution/HANDOFF.md` are excluded standing exceptions. This explicit envelope overrides the default support-file cap. No additional path, deletion, or rename is allowed even if a nominal category has headroom.

## Verification

- Windows structural/read-only checks before implementation: `git status --short --branch`; `git rev-parse HEAD`; `git diff --name-only e8d91bb8b11508c7da62e10c7c493490a76ff830..HEAD` (must be exactly `docs/execution/CURRENT_TASK.md`); `git diff --check`; SHA-256 checks for the pinned plan/runbook/workflow; `git ls-remote --heads origin main phase/s0-foundation`; `gh repo view palatis3/AssetRounds --json nameWithOwner,isPrivate,defaultBranchRef,viewerPermission`; `gh workflow view .github/workflows/ios-ci.yml --repo palatis3/AssetRounds --yaml`. After implementation, verify changed paths are exactly the authorized set, selector JSON is exactly equal to the object below, four scripts are mode 100755/LF, and text/structure inspection of `project.pbxproj` and the shared scheme proves three targets, synchronized roots, iOS 18.0 everywhere, exact bundle IDs, generated plists, correct TestAction/archive configuration, and absence of package/entitlement/team/signing additions. Never invoke local `xcodebuild`, Xcode, Simulator, or XcodeBuildMCP on Windows.
- CI incremental build command: workflow invokes `bash Scripts/run-with-timeout.sh 180 bash Scripts/build-smoke.sh`; the script uses `xcodebuild build-for-testing -project "$PROJECT_PATH" -scheme "$SCHEME" -configuration "$CONFIGURATION" -destination "$CI_DESTINATION" -derivedDataPath "$RUNNER_TEMP/DerivedData" -resultBundlePath "$CI_ARTIFACT_DIR/Build.xcresult" CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO`
- CI targeted test command with exact `-only-testing`: workflow invokes `bash Scripts/run-with-timeout.sh 180 bash Scripts/test-smoke.sh`; the script uses the shared DerivedData and `xcodebuild test-without-building` with exactly `-only-testing:FieldEvidenceAppTests/S0LaunchTests`, writing `$CI_ARTIFACT_DIR/UnitTests.xcresult`
- CI UI-smoke command/checkpoints: workflow invokes `bash Scripts/run-with-timeout.sh 240 bash Scripts/ui-smoke.sh`; the script targets only `$CI_SIMULATOR_UDID`, uses exactly `-only-testing:FieldEvidenceAppUITests/S0LaunchUITests`, writes `$CI_ARTIFACT_DIR/UISmoke.xcresult`, then `xcrun simctl io "$CI_SIMULATOR_UDID" screenshot "$CI_ARTIFACT_DIR/ui-final.png"`; before `XCUIApplication.launch()`, `S0LaunchUITests` sets `app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]`, corresponding to `UIContentSizeCategory.accessibilityExtraExtraExtraLarge`, then fresh-launches the app, asserts foreground state plus identifiers/text/order, performs one inert screen tap, and reasserts foreground/title visibility
- Exact `ci-selection.json` object: `{"schemaVersion":1,"taskID":"S0.1","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":120,"buildTimeoutSeconds":180,"testTimeoutSeconds":180,"uiTimeoutSeconds":240,"totalBudgetSeconds":720,"unitTestSelectors":["FieldEvidenceAppTests/S0LaunchTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S0LaunchUITests"]}`
- Exact timeout preset: `P12 = setup/artifacts 120s / build 180s / targeted unit tests 180s / targeted UI 240s`
- Selected total workflow budget: `P12 720s (12 minutes), including setup through evidence validation/checksum; artifact upload remains within the workflow's 30-minute hard stop`
- Expected CI artifacts: nonempty `build-smoke.log`, `Build.xcresult/`, nonempty `test-smoke.log`, `UnitTests.xcresult/`, nonempty `ui-smoke.log`, `UISmoke.xcresult/`, nonempty `ui-final.png`, runner image/Xcode/build settings/simulator/selection/GitHub-run evidence, and relative-path `SHA256SUMS.txt`
- Accessibility spot check: no interactive control exists, so 44-point target/selected state/focus/contrast/transparency/motion checks are N/A. Assert the title is semantic system text with header trait and identifier `s0.launch.title`, reading order is title before subtitle, system colors are used with no color-only state, and both remain visible/untruncated at `UIContentSizeCategory.accessibilityExtraExtraExtraLarge`, launched with `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`.
- The selected timeout preset is fixed for P12. A timeout is the first failed attempt; after one concrete S0-scoped fix, one rerun is the maximum and any non-green rerun stops.

## Stop and ask

- Source conflict, plan/runbook/workflow hash or selected-card mismatch, branch or ref mismatch/movement, unresolved placeholder, unclear authority, a non-CURRENT_TASK path in `M..A`, any dirty path, or any server state inconsistent with the recorded private-solo posture.
- Any required path beyond the exact eleven plus two standing exceptions; any delete/rename; any attempt to broaden the launch screen or create future scaffolding.
- New package, extra target, workspace/generator, entitlement, permission, persistent schema, backend, auth, payment, analytics, signing, external service, deployment, or submission is required.
- GitHub authorization, exact phase branch, workflow, runner/Xcode/runtime/device, or fixture is missing; the remote phase ref cannot be proven equal to I/I2 immediately before dispatch; `main` or any unexpected ref moves.
- Any selector cannot be resolved/executed in the matching `.xcresult`, a required artifact is missing, or the one post-fix rerun is not green regardless of whether its failure differs.
- User work would be overwritten or an unlisted external write action/tool would be required.

## Definition of done

- Every GOLDEN checkpoint passes in one exact-head P12 run; no alternate behavior is claimed.
- The exact implementation commit SHA's named Actions run builds, tests, fresh-installs, launches, and captures the baseline on the pinned macOS/Xcode/Simulator route with `head_sha` equality.
- Both selected test classes execute non-skipped in their matching result bundles; all required logs/results/screenshot/checksums validate within budget.
- The static launch screen meets the bounded accessibility assertions; no interactive control or adjacent behavior was added.
- Diff remains exactly inside the authorized path set/envelope; no package, signing, permission, persistent schema, future product behavior, or unrelated cleanup appears.
- `docs/execution/KNOWN_BUGS.md` is read before completion. No primary launch/build/test blocker is accepted as known; all other defects are recorded truthfully.
- After exact-head green CI, append one complete S0.1 entry to `HANDOFF.md` in the working tree, including observed A, I/I2, ref check, run URL/ID/head/conclusion, actual runner/Xcode/Simulator/UDID, commands/durations/artifact checksums, acceptance, defects, phase-boundary state, and next card. Do not include HANDOFF in I/I2 and do not commit or push the appended entry.
- Post-card owner gate, outside this Codex `/goal`: owner reviews S0.1, commits the final HANDOFF append alone, merges `phase/s0-foundation` once, verifies `refs/heads/main` equals the intended result SHA under the private-solo rule, permits no intervening push/history rewrite, dispatches `main` with `run_ui_smoke=true`, and accepts only a green matching `head_sha` before creating the S1 phase branch and its CURRENT_TASK-only authority commit.
- Next planned task is named but remains unstarted: `S1.1`.
