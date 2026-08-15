# Current Task

## Program and card

- Phase / branch / card / global order: `S7 / phase/s7-commerce / S7.5 / 31 of 36`.
- Card heading: `### S7.5 — Lapse/data rights and Erase-subscription independence`.
- Position / boundary / immediate next card: `5 of 5 / phase boundary yes / S8.1 only after accepted S7.5 evidence, closed phase verification, exact-main integration, and fresh next-phase G0`.
- Program autopilot / phase autopilot / exact S7 span / boundary integration: `enabled through accepted S9.1 / enabled / S7.1,S7.2,S7.3,S7.4,S7.5 / yes`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S7 phase-main base: `P=5f50551f61bc363b430d4e877e462cb47865065d`; it remains byte-for-byte fixed throughout S7.
- Integrated/card base: `M=826b1c2193869c7282611300df31a56c51a56da9`; accepted S7.4 implementation and exact-head verification head.
- Accepted S7.4 evidence: run `31870467506` / job `94978205243`, exact `phase/s7-commerce@M`, attempt 1, F25/UI enabled, terminal success, build plus `4/4` units plus `1/1` UI green.
- Accepted S7.4 artifact: `ios-ci-31870467506-1`, ID `9243388326`, size `4461295`, digest `sha256:e3bfeb518883921139b9c8eee751cd28fcabae12d7c88da16be4169e7fbc8131`; all `99/99` checksums matched; `SHA256SUMS.txt` SHA-256 `A1AD82A25252A78BE3B694578E7DE4782A3E1272337FA73CDC8CECC1A26242FB`.
- Accepted environment: `macos26` image `20260728.0273.1`; Xcode 26.6 build `17F113`; iPhone 17 / iOS 26.2; Simulator UDID `9AA9ED9B-42D2-4F6E-B8B5-45AAB66D6404`.
- Task-start authority is the direct-child same-phase transition commit created from M. Fresh G0 must observe its exact SHA, prove `M..A` changes only append-only `docs/execution/HANDOFF.md` plus this immediate-next `docs/execution/CURRENT_TASK.md`, prove remote `phase/s7-commerce=A` and remote `main=P`, and record A later without attempting to self-record it here.
- Mandatory S8.1 integration evidence remains frozen: a prior-card `CheckRunnerCoordinator.finalizationAttempt` can survive a completed recheck and misclassify a same-session fresh check. S8.1 must exercise and correct that reusable seam before release.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S7.5 plan anchors: `## 7. Free evaluation, subscriptions, and payments` → former-paid lapse blocks only new sign/draft authority while retaining every existing-data right and exact validated-draft completion; `## 10. Local erase and crash-safe recovery` → Erase never calls StoreKit sync/cancel/manage and ordinary verified refresh may rediscover active access; `## 11. Build slices and release gates` → S7.5 lapse/data-right/Erase independence integration; global execution anchors remain `## 16` and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / selected card S7.5 only.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `BCD64E2A42752D28844435241B5ABFCA911D04190375CBBDBFC10B45ACBA97D7` / `workflow_dispatch`.
- Selector at G0 may still equal accepted S7.4 compact JSON plus LF, 344 bytes, SHA-256 `584C85FFDC4BE63DDB36CA0350FF6CC124AEA008A04D994D75363DF00523D5A0`; after complete G0 the first support mutation replaces it with the exact S7.5 object below, 349 bytes, SHA-256 `C87DCB47F4B18FB3B6E4F637FAB459CB7F026DC35F606505E5CC61307673C62F`.

## Outcome and acceptance

- Outcome: prove and correct only the exact integration boundary where former-paid inactivity blocks new value but preserves every existing-data right and exact stored-draft completion, while Erase remains independent of Apple subscription state and ordinary launch can rediscover still-active verified access.
- Lapse truth: `former_paid_inactive` blocks only a new sign, check, work, or recheck through the shared closable paywall. It never blocks reading history, report detail/preview, Share, Files export, backup export, PDF retry, clerical correction, whole-sign deletion, Erase, or continuation of an exact repository-validated existing draft.
- Existing-data truth: lapse does not mutate, hide, rewrite, or downgrade Sites, Assets, records, Issues, evidence, snapshots, PDFs, backup members, evaluation roots, or deletion authority. Correction, retry, export, and deletion retain their existing independent validation and recovery contracts and never call `DraftAccessPolicy`.
- Erase truth: active-subscriber Erase performs no `AppStore.sync()`, transaction finish, purchase, cancellation, Manage Subscription, account deletion, or remote erase call. It removes the local commerce cache and `hasEverVerifiedPaid` together with the frozen local generation/auxiliary roots, activates one empty generation, and resets only installation-scoped evaluation.
- Rediscovery truth: after Erase and a clean launch, ordinary verified StoreKit refresh—without explicit sync—may re-establish active access in the empty local generation. Offline absence or unverified/wrong-product authority never invents entitlement, grace, or prior-paid facts.
- GOLDEN: a former-paid lapse reads, previews, shares, Files-exports, backs up, retries PDF, corrects, deletes, and completes an already-created exact draft while every new sign/draft opens the same paywall.
- ALT-1: active-subscriber Erase makes no cancel/sync/manage call; the cold empty launch rediscovers active verified entitlement through the ordinary processor and still has zero local Assets, reports, evidence, or counted evaluation roots.
- Accessibility/UI: one bounded Accessibility XXXL flow proves readable existing history and data-right actions through lapse, exact stored-draft completion, blocked new value through the shared closable paywall, Erase/subscription-independent copy, 44-point controls, and exactly one terminal in-app screenshot.
- Forbidden behavior: any new subsystem, cancellation/account deletion/remote erase, automatic `AppStore.sync()`, existing-data gate, entitlement import from backup, evaluation preservation across Erase, guessed/offline entitlement, new product/price/schema/capability, S8 behavior, signing, TestFlight, submission, deployment, or release.

## Environment and exact selector

- Route / repository / refs: Windows authoring → exact GitHub Actions macOS verification; `palatis3/AssetRounds / public / main / phase/s7-commerce`; never run or claim Windows Xcode/Simulator results.
- Required posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Runner / Xcode / project: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer / FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.2`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `F25 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S7.5","tier":"F25","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":900,"testTimeoutSeconds":1200,"uiTimeoutSeconds":1800,"totalBudgetSeconds":4500,"unitTestSelectors":["FieldEvidenceAppTests/S7_5DataRightsIntegrationTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S7_5LapseRightsUITests"]}` plus exactly one LF; 349 UTF-8 bytes, no BOM; SHA-256 `C87DCB47F4B18FB3B6E4F637FAB459CB7F026DC35F606505E5CC61307673C62F`.
- Exact commands: `bash Scripts/run-with-timeout.sh 900 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 1200 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 1800 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, and UISmoke result bundles; exact one terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download. Force-push, merge commit, PR, ref rewrite/delete, main mutation before the S7 boundary, settings/secrets, App Store Connect, signing, TestFlight/App Store, deployment/release, and S9.2/S9.3 are forbidden.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/Infrastructure/Commerce/StoreKitTransactionProcessor.swift`
- `FieldEvidenceApp/Infrastructure/Commerce/StoreKitLifecycleCoordinator.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift`
- `FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift`
- `FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift`
- `FieldEvidenceApp/Infrastructure/Reporting/ReportDeliveryCoordinator.swift`
- `FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift`
- `FieldEvidenceApp/Features/Signs/SignsRootView.swift`
- `FieldEvidenceApp/Features/Shell/AppShellView.swift`
- `FieldEvidenceApp/App/FieldEvidenceAppApp.swift`

Test paths:

- `FieldEvidenceAppTests/S7_5DataRightsIntegrationTests.swift`
- `FieldEvidenceAppUITests/S7_5LapseRightsUITests.swift`

Standing selector exception:

- `Scripts/ci-selection.json`

No other implementation, model, project, resource, fixture, asset, script, workflow, authority, or documentation path is allowed during S7.5 implementation. Existing entitlement facts/reducer/store, `DraftAccessPolicy`, entry coordinators, Packet accounting, deletion/Erase journals, backup/import/restore, report history/detail/share/Files/correction/PDF retry, product loader, StoreKit fixture/project/scheme, diagnostics APIs, purchase coordinator/paywall/status view, navigation, and design tokens may be read and reused without editing. Append-only `docs/execution/HANDOFF.md` remains separately authorized bookkeeping after accepted evidence.

## G0 and verification

- Fresh G0 must prove the transition authority directly parents exact M, changes only append-only `docs/execution/HANDOFF.md` plus this immediate-next `docs/execution/CURRENT_TASK.md`, leaves remote `main=P`, preserves all pins, and expands the runbook's shorthand into exactly ten production and two test paths within the default 10/5 cap.
- Validate the exact S7.5 F25 selector object against runbook Section 6 and the workflow schema. The accepted S7.4 selector is permitted only as predecessor state; after complete G0 replace only `Scripts/ci-selection.json` with the frozen S7.5 object as the first implementation-support mutation.
- Implement only S7.5. Candidate recovery follows the persistent evidence-driven direct-child loop without weakening GOLDEN/ALT, selectors, tests, lapse/data-right/Erase/StoreKit truth, watchdogs, or scope.
- After accepted exact-head S7.5 CI, read `KNOWN_BUGS.md`, append the immutable S7.5 HANDOFF, then use the enabled phase-boundary state machine only: commit/push HANDOFF-only phase close C; verify exact phase; non-force fast-forward `main` to the accepted green verification head; verify exact-main CI; create `phase/s8-quality` from that green main; hydrate only S8.1; and run fresh S8.1 G0. Never merge, force, or start S8.2/S9 work.
