# Current Task

## Program and card

- Phase / branch / card / global order: `S1 / phase/s1-shell-design / S1.1 / 2 of 36`.
- Card heading: `### S1.1 — Shell, Worklight Precision, and exact pack`.
- Position / boundary / immediate next card: `1 of 1 / phase boundary yes / S2.1`.
- Program autopilot / phase autopilot / exact S1 span / boundary integration: `enabled through accepted S9.1 / enabled / S1.1 only / yes`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Accepted S0 phase-close/verification head and S1 phase-main base: `P=M=5b826bd6a9f59318f5a161103f3d93a20c46f438`.
- Predecessor evidence: phase run `31597722994` and exact-main run `31598703886` both succeeded at P with P12/UI enabled, complete independently verified 91-entry checksum artifacts, Xcode 26.6 `17F113`, iPhone 17/iOS 26.5.
- Task-start authority head `A`: `OBSERVE AT POST-COMMIT G0; never self-record its SHA here`.
- Required `M..A`: one direct-child authority commit changing exactly `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` and `docs/execution/CURRENT_TASK.md`. The runbook change adds only the explicit S1.1 envelope required to implement the plan's literal named Color Sets.
- Construction state: local branch starts at M; remote `phase/s1-shell-design` absent; before the authority commit only the two required M..A paths may be dirty; post-commit G0 requires clean index/worktree/untracked state.
- Historical S0 product evidence remains `E=I3=ac310dd37700d65165200f742aaec1d48d0a34d6`; K4 is verification/integration evidence and S1 base, not a replacement product implementation.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S1.1 plan anchors: `## 5. Navigation and onboarding` (`### Navigation`); `## 8. Premium, field-readable visual system` (`### Direction: Worklight Precision`, `### Semantic tokens`, `### Typography, spacing, and components`); `## 9. Smallest reusable architecture` (`### Bundled vertical pack`, `### Exact IlluminatedSignPack@1`). Global execution anchors remain `## 11. Build slices and release gates`, `## 16. Owner preparation checklist`, and `## 18. Codex execution authority`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79`.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Selector schema path: `Scripts/ci-selection.json`; at G0 it may still be the accepted S0 predecessor object with SHA-256 `B46D4707C758DE1C086109960DA5D4E98662F0AD0083E7DA497C9CDA3B34D645`. Its first support mutation must replace it with the exact S1.1 object below, LF-terminated SHA-256 `F6D8FD7495095C20EC7C7285E12223BE718880DDF7C5D5DA8A4ED34982E775CC`.

## Outcome and acceptance

- Outcome: create the two-tab Signs/Reports shell with a toolbar Settings gear, Worklight Precision semantic tokens/components, an isolated pack sample, and the one strict bundled `IlluminatedSignPack@1` loader. Invalid or unknown bundle content produces one local unavailable state and never guesses.
- Exact delta: no project, target, package, capability, permission, persistence, or schema delta. Add only shell/sample presentation, literal named Color Sets, Worklight components, the immutable exact pack value/loader/manifest, and targeted tests. The pack defines no navigation, persistence, executable workflow, PDF geometry/order, remote lookup, marketplace, or second production vertical.
- GOLDEN: Signs and Reports are the only tabs; Settings is a toolbar gear, not a tab. Every exact noun, prompt, evidence purpose, acknowledgement, issue/CNV registry entry, stage/outcome display, and disclaimer renders in the isolated sample. The shell remains usable at accessibility XXXL in Light and Dark Mode.
- ALT-1: any missing, extra, unknown, or drifted pack key/ID/schema/content version/copy causes one local content-unavailable surface. No fallback registry, guessed copy, partial pack, or remote recovery exists.
- Forbidden behavior: SwiftData, runner behavior, report/PDF code, media/camera, generic workflow or pack engine, remote pack, persistence, commerce, packages, permissions, project-file edits, or future Settings behavior.

## Environment and exact selector

- Route / host: Windows authoring → GitHub Actions macOS verification; never run or claim local Windows Xcode/Simulator results.
- Required tool posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration is active; XcodeBuildMCP and an owner-operated Mac are unnecessary.
- Repository / visibility / default / phase: `palatis3/AssetRounds / private / main / phase/s1-shell-design`.
- Runner / Xcode / developer dir: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer`.
- Project / scheme / configuration / deployment: `FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S1.1","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S1PackTokenTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S1ShellUITests"]}`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build/UnitTests/UISmoke result bundles; final screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging and one-purpose commits; non-force phase-branch create/push; named `workflow_dispatch` with exact branch ref and `run_ui_smoke=true`; run observation and artifact download; after exact green phase-close evidence, verified non-force `main` fast-forward and exact-main dispatch; after exact-main acceptance, creation of only the frozen immediate-next phase branch. Forbidden methods: force-push, merge commit, PR creation/merge, ref deletion or rewrite, repository/settings/secret mutation, signing, TestFlight/App Store upload, deployment, release publication, or S9.2/S9.3 action.

## Exact allowed implementation paths

Production paths (27-path explicit S1.1 override):

- `FieldEvidenceApp/App/FieldEvidenceAppApp.swift`
- `FieldEvidenceApp/DesignSystem/DesignTokens.swift`
- `FieldEvidenceApp/DesignSystem/WorklightComponents.swift`
- `FieldEvidenceApp/Domain/Packs/SignPack.swift`
- `FieldEvidenceApp/Domain/Packs/SignPackLoader.swift`
- `FieldEvidenceApp/Features/Shell/AppShellView.swift`
- `FieldEvidenceApp/Features/Sample/PackSampleView.swift`
- `FieldEvidenceApp/Resources/Packs/IlluminatedSignPack.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightCanvas.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightSurface.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightRaisedSurface.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightPrimaryText.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightSecondaryText.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightTertiaryText.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightInteractionAccent.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightOnAccent.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightAccentContainer.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightOnAccentContainer.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightEssentialControlStroke.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightCompleteText.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightCompleteContainer.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightAttentionText.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightAttentionContainer.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightBlockedText.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightBlockedContainer.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightInformationText.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightInformationContainer.colorset/Contents.json`

Test paths:

- `FieldEvidenceAppTests/S1PackTokenTests.swift`
- `FieldEvidenceAppUITests/S1ShellUITests.swift`

Standing support exception:

- `Scripts/ci-selection.json`

`docs/execution/HANDOFF.md` is append-only post-green bookkeeping and is not part of the implementation commit. No other path may change.

## Execution

1. Commit the two-path authority amendment A, push/create only `phase/s1-shell-design` non-force from M, and run fresh G0. G0 proves A^=M, exact M..A, pins/map/environment, selector predecessor state, and no other dirty path.
2. Replace selector first, implement only the allowed paths, run structural/static checks available on Windows, explicitly stage only task paths, and commit direct-child implementation I.
3. Push the exact phase ref non-force and run the one-at-a-time persistent P12 verification loop. Accept only green exact-head CI with complete checksummed evidence. Hosted variance gets a fresh run ID; diagnosed product/harness failures get one direct-child correction per commit with no numeric ceiling.
4. After green implementation evidence, append HANDOFF and create/push phase-close C. Verify the exact phase ref at C or a later direct-child recovery head until green, then non-force fast-forward main to that exact green head and require green exact-main P12 evidence.
5. From accepted exact-main S1 head create only `phase/s2-persistence-signs`, hydrate only S2.1, and run fresh G0.

## Definition of done

- Exact green S1.1 implementation, phase-close, and exact-main P12 evidence with complete artifacts; only the two tabs and toolbar Settings entry; strict complete pack and literal token assets; Light/Dark/accessibility XXXL coverage; invalid pack fails closed; no forbidden feature or path.
- Handoff records all required evidence. Remote phase/main/default HEAD equal the accepted S1 verification head. Then continue only with S2.1.
