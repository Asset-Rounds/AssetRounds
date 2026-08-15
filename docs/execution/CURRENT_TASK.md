# Current Task

## Program and card

- Phase / branch / card / global order: `S8 / phase/s8-quality / S8.2 / 33 of 36`.
- Card heading: `### S8.2 — Full golden-flow accessibility CI`.
- Position / boundary / immediate next card: `2 of 4 / phase boundary no / S8.3 only after accepted S8.2 evidence and fresh same-phase G0`.
- Program autopilot / phase autopilot / exact S8 span / boundary integration: `enabled through accepted S9.1 / enabled / S8.1,S8.2,S8.3,S8.4 / yes at S8.4 only`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S8 phase-main base: `P=0b1e506dd71ba704cbfb48787d6cfa1731024d83`; this exact accepted S7 phase-close/exact-main head remains byte-for-byte fixed throughout S8.
- Integrated/card base: `M=d0e8762fffbcaf6e6f9076c26ed50e5de2bf254e`, the accepted S8.1 implementation and verification head.
- Accepted S8.1 evidence: run `31877304310` / job `94994834315`, exact `phase/s8-quality@M`, attempt 1, N8/UI disabled, terminal success, build plus `2/2` units green. Artifact `ios-ci-31877304310-1`, ID `9245126681`, size `124545`, digest `sha256:68949b3c7fe8aba17fbf76d77e91139091914af224d92abc7ef82e04ef15266c`; all `57/57` payload checksums matched; `SHA256SUMS.txt` SHA-256 `3A040983C33484C4595CE84FCAB6E03B9ADDE6E2EA98DDD3659A8C9C1CBE714E`.
- Accepted environment: `macos26` image `20260728.0273.1`; Xcode 26.6 build `17F113`; iPhone 17 / iOS 26.2 build `23C54`; Simulator UDID `9AA9ED9B-42D2-4F6E-B8B5-45AAB66D6404`; initial state `Shutdown`.
- S8.1 implementation lineage: authority `A3=b1bf9d932df649cd7820a5429a1c9ad9d655ae86`; implementation `I=b3420922b024f0232237da08e789a4d7516cde01`; test-only corrections `I2=322a3d44d1b42367f54a057c7e95befa26b5e26e` and accepted `I3=M`. Failed candidates `31876686374` and `31876991684` were never rerun or accepted.
- Same-phase S8.2 transition authority must directly parent exact M and change only append-only `docs/execution/HANDOFF.md` plus this immediate-next `docs/execution/CURRENT_TASK.md`. Fresh G0 must observe and record that transition head as A without attempting to self-record its SHA here, prove `M..A` contains exactly those two paths, prove remote `phase/s8-quality=A`, and prove remote `main=P`.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S8.2 plan anchors: `### Typography, spacing, and components` → semantic Dynamic Type, minimum 44×44-point controls, VoiceOver state/focus, non-color status, system Light/Dark behavior, and no deceptive evidence treatment; `## 11. Build slices and release gates` → S8.2 verification-only complete golden-flow accessibility CI; `## 12. Twelve must-pass launch smokes` → smoke 12 exact accessibility-tree/default-and-largest-accessibility/Light-and-Dark proof. Global execution anchors remain `## 16` and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / selected card S8.2 only.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `BCD64E2A42752D28844435241B5ABFCA911D04190375CBBDBFC10B45ACBA97D7` / `workflow_dispatch`.
- Selector at G0 may still equal accepted S8.1 compact JSON plus LF, 294 bytes, SHA-256 `08F058C46FD35D3904FD9636E86F06E136926110F5FBB3A39987B8DA92D1A54A`; after complete G0 the first support mutation replaces it with the exact S8.2 object below, 355 bytes, SHA-256 `56ED06D4189ECDA0D643F680BC0291E78631F999207E896BAE6F8045FFD14807`.

## Outcome and acceptance

- Outcome: one bounded fresh-install accessibility proof traverses first sign → check → report → visible Issue → work → evidence-bearing recheck → Settings → monthly paywall through existing production routes, accessibility identifiers, and named checkpoints. It verifies the default Light flow, then the largest accessibility Dynamic Type flow in Dark Mode, without adding or redesigning product behavior.
- Verification-only truth: the implementation commit may add only one unit-test class and one UI fixture/test class plus the standing selector. It may reuse existing production test seams, StoreKit fixture, media helpers, identifiers, routes, and tokens read-only; it must not add a production accessibility branch, test-only product route, synthetic product result, or alternate flow.
- Accessibility-tree truth: primary controls and states expose exact labels, identifiers, enabled/selected traits or equivalent AX values, deterministic reading/order checkpoints, save/progress/selection announcements where exposed, and the next actionable or recovery focus target. Assertions must prove semantics, not private SwiftUI hierarchy or pixel coincidence.
- Layout truth: the complete golden route starts in default Light, then relaunches or checkpoints at `UICTContentSizeCategoryAccessibilityXXXL` in Dark Mode. Required actions remain reachable through scrolling, text does not become the sole control, evidence stays aspect-fit and untinted, and the test makes no claim about device/locale/orientation matrices or physical spoken VoiceOver output.
- Non-color/target truth: completion, attention, blocked/destructive, information, selection, and progress meaning remains available in text/traits/symbols rather than color alone; every required interactive target proven by the UI fixture is at least 44×44 points.
- Representative-error truth: one bounded validation or permission recovery path must surface truthful actionable copy and move accessibility focus to that error/recovery surface without deleting prior work or relying on color alone.
- Unit truth: the one bounded unit class proves the exact identifier/semantic contract and any deterministic accessibility helper used by the sole UI class; it may not duplicate broad product matrices or inspect unsupported private system hierarchy.
- GOLDEN: the fresh-install class completes the full first-sign/check/report/issue/work/recheck/Settings/paywall route with exact named checkpoints, then verifies largest-accessibility Dark labels/traits/order/focus/non-color state/44-point reachability and one terminal in-app screenshot.
- ALT-1: the representative validation/permission error receives actionable accessibility focus, leaves earlier authority intact, and can recover into the same route; no color-only, clipped, hidden, duplicate, or false-completion state passes.
- Forbidden behavior: visual redesign, new design token, production route/identifier/fixture branch, device/locale/orientation matrix, screenshot-only acceptance, pixel-diff suite, broad accessibility audit, synthetic StoreKit result, new entity/schema/service/permission/dependency, product copy invention, data/commerce mutation outside the golden route, S8.3/S8.4 behavior, signing, TestFlight, submission, deployment, or release.

## Environment and exact selector

- Route / repository / refs: Windows authoring → exact GitHub Actions macOS verification; `palatis3/AssetRounds / public / main / phase/s8-quality`; never run or claim Windows Xcode/Simulator results.
- Required posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Runner / Xcode / project: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer / FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.2`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `F25 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S8.2","tier":"F25","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":900,"testTimeoutSeconds":1200,"uiTimeoutSeconds":1800,"totalBudgetSeconds":4500,"unitTestSelectors":["FieldEvidenceAppTests/S8_2GoldenAccessibilityTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S8_2GoldenAccessibilityUITests"]}` plus exactly one LF; 355 UTF-8 bytes, no BOM; SHA-256 `56ED06D4189ECDA0D643F680BC0291E78631F999207E896BAE6F8045FFD14807`.
- Exact commands: `bash Scripts/run-with-timeout.sh 900 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 1200 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 1800 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, and UITests result bundles; exactly one terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download. Force-push, merge commit, PR, ref rewrite/delete, main mutation before the S8 boundary, settings/secrets, App Store Connect, signing, TestFlight/App Store, deployment/release, and S9.2/S9.3 are forbidden.

## Exact allowed implementation paths

Verification-only proof paths:

- `FieldEvidenceAppTests/S8_2GoldenAccessibilityTests.swift`
- `FieldEvidenceAppUITests/S8_2GoldenAccessibilityUITests.swift`

Standing selector exception:

- `Scripts/ci-selection.json`

No production, model, project, resource, fixture, asset, script, workflow, authority, or documentation path is allowed during the initial S8.2 verification implementation. If exact hosted evidence identifies a production defect, keep S8.2 active and first apply one mechanical CURRENT_TASK authority correction naming only the exact earlier-card-owned production path that introduced the failed semantic; then create one direct-child correction limited to that path and rerun the unchanged S8.2 selector. Existing production code, StoreKit test fixture/project wiring, design tokens, models, routes, identifiers, media fixtures, and test helpers may be read and reused without editing. Append-only `docs/execution/HANDOFF.md` remains separately authorized bookkeeping after accepted evidence.

## G0 and verification

- Fresh G0 must prove transition A directly parents exact M, `M..A` changes only append-only HANDOFF plus immediate-next CURRENT_TASK, `P..A` preserves the accepted S8 lineage, remote `phase/s8-quality=A`, and remote `main=P`; it must reprove accepted S8.1 run/artifact/checksums and every pin above.
- Validate the exact S8.2 F25 selector object against runbook Section 6 and the workflow schema. The accepted S8.1 selector is permitted only as predecessor state; after complete G0 replace only `Scripts/ci-selection.json` with the frozen S8.2 object as the first implementation-support mutation.
- Implement only S8.2. Add one bounded unit class and one bounded UI class with exactly one terminal in-app screenshot. Reuse current production semantics; do not pre-authorize or guess a production defect.
- Candidate recovery follows the persistent evidence-driven direct-child loop. Never weaken the route, largest-accessibility Dark checkpoint, representative focused error, exact semantics, 44-point proof, StoreKit-system route, selector, screenshot count, or watchdogs.
- After accepted exact-head S8.2 CI, read `KNOWN_BUGS.md`, append immutable S8.2 HANDOFF, then enabled same-phase autopilot may commit/push exactly that append plus immediate-next S8.3 CURRENT_TASK and must run fresh S8.3 G0. Do not mutate `main` before the S8.4 phase boundary and do not start S8.4/S9 work.
