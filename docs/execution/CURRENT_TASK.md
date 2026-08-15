# Current Task

## Program and card

- Phase / branch / card / global order: `S7 / phase/s7-commerce / S7.4 / 30 of 36`.
- Card heading: `### S7.4 — Shared DraftAccessPolicy and paid multi-sign entry`.
- Position / boundary / immediate next card: `4 of 5 / phase boundary no / S7.5 only after accepted S7.4 evidence and a fresh same-phase transition G0`.
- Program autopilot / phase autopilot / exact S7 span / boundary integration: `enabled through accepted S9.1 / enabled / S7.1,S7.2,S7.3,S7.4,S7.5 / yes`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S7 phase-main base: `P=5f50551f61bc363b430d4e877e462cb47865065d`; it remains byte-for-byte fixed throughout S7.
- Integrated/card base: `M=a21b456ec72de192aa0144129773e4008c980e18`; accepted S7.3 implementation and exact-head verification head.
- Accepted S7.3 evidence: run `31866590332` / job `94968561813`, exact `phase/s7-commerce@M`, attempt 1, F25/UI enabled, terminal success, build plus `6/6` units plus `1/1` UI green.
- Accepted S7.3 artifact: `ios-ci-31866590332-1`, ID `9242303582`, size `3140702`, digest `sha256:b9387edfa8a655138bf8cc8b73aa1987cd12b4d09f9471a991da69eab1e7a6c4`; all `103/103` checksums matched; `SHA256SUMS.txt` SHA-256 `B40B181C8DFE98846B5A89BABC14109520F637BF26A2E1CA0A4FD74E24BA7BCB`.
- Accepted environment: `macos26` image `20260728.0273.1`; Xcode 26.6 build `17F113`; iPhone 17 / iOS 26.2; Simulator UDID `9AA9ED9B-42D2-4F6E-B8B5-45AAB66D6404`.
- Task-start authority is the direct-child same-phase transition commit created from M. Fresh G0 must observe its exact SHA, prove `M..A` changes only append-only `docs/execution/HANDOFF.md` plus this immediate-next `docs/execution/CURRENT_TASK.md`, prove remote `phase/s7-commerce=A` and remote `main=P`, and record A later without attempting to self-record it here.
- Mandatory S8.1 integration evidence remains frozen: a prior-card `CheckRunnerCoordinator.finalizationAttempt` can survive a completed recheck and misclassify a same-session fresh check. S8.1 must exercise and correct that reusable seam before release.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S7.4 plan anchors: `## 7. Free evaluation, subscriptions, and payments` → one concurrent free live sign, three monotonic counted roots, former-paid behavior, exact normalized access table, and one pure repository-backed `DraftAccessPolicy`; `## 11. Build slices and release gates` → S7.4 shared access policy/multi-sign entry; global execution anchors remain `## 16` and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / selected card S7.4 only.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `BCD64E2A42752D28844435241B5ABFCA911D04190375CBBDBFC10B45ACBA97D7` / `workflow_dispatch`.
- Selector at G0 may still equal accepted S7.3 compact JSON plus LF, 342 bytes, SHA-256 `209F452E409683B78AD8F3958506D5AF19FF63D6305F39D744E822D3BF0F63F4`; after complete G0 the first support mutation replaces it with the exact S7.4 object below, 344 bytes, SHA-256 `584C85FFDC4BE63DDB36CA0350FF6CC124AEA008A04D994D75363DF00523D5A0`.

## Outcome and acceptance

- Outcome: implement one pure repository-backed `DraftAccessPolicy` for explicit create-sign, new-check, new-work, and new-recheck entry; include the fresh-offline never-paid loading branch; activate **Add sign** through the existing S2 form with existing-site or **New site** choice; and always allow a repository-validated existing draft to finish honestly.
- Policy truth: inputs are only normalized access state, live `Asset` count, the distinct live+tombstoned `evaluationCounted=true` stable-root set, requested entry `create_sign|check|work|recheck`, and an optional repository-validated existing draft. Precedence is exact: valid existing draft → `continue_existing`; current entitlement → `allow`; former-paid inactive → `block_paid`; never-paid → local concurrent-sign/three-root evaluation; loading with a still-valid cache follows that cache, known prior-paid without valid cache → `wait_for_store`, and no cache plus `hasEverVerifiedPaid=false` applies never-paid evaluation.
- Repository truth: a supplied UUID never bypasses policy. The owning coordinator must prove the draft exists, belongs to the exact requested Asset/Issue/stage, predates the gate check, and is a continuation rather than a clone. Every blocked new-value action fails before any Site, Asset, draft, row, evidence file, staging byte, or counter mutation.
- Evaluation truth: never-paid permits at most one concurrent live sign and fewer than three distinct counted roots. Whole-sign deletion frees only the live-sign slot; tombstoned counted roots remain. Work records and report corrections consume no root. A former-paid lapse never reopens the free evaluation; active or signed-grace entitlement permits multiple Assets and new drafts.
- Paywall/navigation truth: an explicitly blocked new-value action opens the same closable monthly paywall and returns to unchanged history. First-sign onboarding never auto-presents a paywall. **Add sign** reuses S2 validation and supports an existing Site or a newly entered Site without creating a second form or route-specific policy.
- GOLDEN: a never-paid installation with one live sign and three counted roots blocks an explicit new-value action before any row/file and opens the same closable paywall; active entitlement permits multiple Assets and relaunch selection; existing validated drafts finish.
- ALT-1: fresh loading with no cache/ever-paid=false permits the first offline never-paid report; known prior-paid without valid cache waits; deleting the only sign below three roots permits one replacement, while three retained roots do not. Every check/work/recheck and supplied-draft mismatch fails through the same policy without mutation.
- Accessibility/UI: one bounded Accessibility XXXL flow proves explicit Add sign/new-draft gating, the shared closable paywall, unchanged readable history, active paid multi-sign entry, 44-point controls, and exactly one terminal in-app screenshot.
- Forbidden behavior: fingerprinting, DeviceCheck, account/backend/remote counter, hidden usage ledger, route-specific access policies, automatic paywall, mutation before policy, evaluation decrement on deletion, correction/read/preview/share/export/backup/delete/Erase gating, automatic `AppStore.sync()`, new product/price/commerce state, schema migration, S7.5 behavior, signing, TestFlight, submission, deployment, or release.

## Environment and exact selector

- Route / repository / refs: Windows authoring → exact GitHub Actions macOS verification; `palatis3/AssetRounds / public / main / phase/s7-commerce`; never run or claim Windows Xcode/Simulator results.
- Required posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Runner / Xcode / project: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer / FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.2`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `F25 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S7.4","tier":"F25","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":900,"testTimeoutSeconds":1200,"uiTimeoutSeconds":1800,"totalBudgetSeconds":4500,"unitTestSelectors":["FieldEvidenceAppTests/S7_4DraftAccessPolicyTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S7_4AccessGateUITests"]}` plus exactly one LF; 344 UTF-8 bytes, no BOM; SHA-256 `584C85FFDC4BE63DDB36CA0350FF6CC124AEA008A04D994D75363DF00523D5A0`.
- Exact commands: `bash Scripts/run-with-timeout.sh 900 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 1200 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 1800 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, and UISmoke result bundles; exact one terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download. Force-push, merge commit, PR, ref rewrite/delete, main mutation before the S7 boundary, settings/secrets, App Store Connect, signing, TestFlight/App Store, deployment/release, and S9.2/S9.3 are forbidden.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/Domain/Commerce/DraftAccessPolicy.swift`
- `FieldEvidenceApp/Infrastructure/Commerce/StoreKitTransactionProcessor.swift`
- `FieldEvidenceApp/Infrastructure/Commerce/StoreKitLifecycleCoordinator.swift`
- `FieldEvidenceApp/Features/Signs/FirstSignCoordinator.swift`
- `FieldEvidenceApp/Features/Signs/NewSignView.swift`
- `FieldEvidenceApp/Features/Signs/SignDetailView.swift`
- `FieldEvidenceApp/Features/Signs/SignsRootView.swift`
- `FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift`
- `FieldEvidenceApp/Features/Issues/WorkCoordinator.swift`
- `FieldEvidenceApp/Features/Shell/AppShellView.swift`

Test paths:

- `FieldEvidenceAppTests/S7_4DraftAccessPolicyTests.swift`
- `FieldEvidenceAppUITests/S7_4AccessGateUITests.swift`

Standing selector exception:

- `Scripts/ci-selection.json`

No other implementation, model, project, resource, fixture, asset, script, workflow, authority, or documentation path is allowed during S7.4 implementation. Existing entitlement facts/reducer/store, Packet accounting, deletion tombstones, product loader, StoreKit fixture/project/scheme, diagnostics APIs, purchase coordinator/paywall/status view, app bootstrap, navigation, history, data-rights, and design tokens may be read and reused without editing. Append-only `docs/execution/HANDOFF.md` remains separately authorized bookkeeping after accepted evidence.

## G0 and verification

- Fresh G0 must prove the transition authority directly parents exact M, changes only append-only `docs/execution/HANDOFF.md` plus this immediate-next `docs/execution/CURRENT_TASK.md`, leaves remote `main=P`, preserves all pins, and expands the runbook's shorthand into exactly ten production and two test paths within the default 10/5 cap.
- Validate the exact S7.4 F25 selector object against runbook Section 6 and the workflow schema. The accepted S7.3 selector is permitted only as predecessor state; after complete G0 replace only `Scripts/ci-selection.json` with the frozen S7.4 object as the first implementation-support mutation.
- Implement only S7.4. Candidate recovery follows the persistent evidence-driven direct-child loop without weakening GOLDEN/ALT, selectors, tests, evaluation/StoreKit truth, watchdogs, or scope.
- After accepted exact-head S7.4 CI, read `KNOWN_BUGS.md`, append the immutable S7.4 HANDOFF, and—only with phase autopilot still enabled—commit/push exactly that append plus immediate-next S7.5 CURRENT_TASK. Run fresh S7.5 G0; do not mutate `main` during a same-phase transition.
