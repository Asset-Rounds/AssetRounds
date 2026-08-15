# Current Task

## Program and card

- Phase / branch / card / global order: `S7 / phase/s7-commerce / S7.3 / 29 of 36`.
- Card heading: `### S7.3 — Restore, manage, lifecycle status, and offline refresh`.
- Position / boundary / immediate next card: `3 of 5 / phase boundary no / S7.4 only after accepted S7.3 evidence and a fresh same-phase transition G0`.
- Program autopilot / phase autopilot / exact S7 span / boundary integration: `enabled through accepted S9.1 / enabled / S7.1,S7.2,S7.3,S7.4,S7.5 / yes`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S7 phase-main base: `P=5f50551f61bc363b430d4e877e462cb47865065d`; it remains byte-for-byte fixed throughout S7.
- Integrated/card base: `M=f09ddd11b10371b237f6e60bc2211b7ccb1b8739`; accepted S7.2 implementation and exact-head verification head.
- Accepted S7.2 evidence: run `31863494463` / job `94960691821`, exact `phase/s7-commerce@M`, attempt 1, P12/UI enabled, terminal success, build plus `5/5` units plus `1/1` UI green.
- Accepted S7.2 artifact: `ios-ci-31863494463-1`, ID `9241454169`, size `2959789`, digest `sha256:fd21cb0055ab72b1885d5a6c765cd826e968bde2475336ff63e6a6441b35fc36`; all `101/101` checksums matched; `SHA256SUMS.txt` SHA-256 `30F04B96907544C7B8CD292036457B52A810C893B0989D09D9DCF011E16F0BA7`.
- Accepted environment: `macos26` image `20260728.0273.1`; Xcode 26.6 build `17F113`; iPhone 17 / iOS 26.2; Simulator UDID `9AA9ED9B-42D2-4F6E-B8B5-45AAB66D6404`.
- Task-start authority is the direct-child same-phase transition commit created from M. Fresh G0 must observe its exact SHA, prove `M..A` changes only append-only `docs/execution/HANDOFF.md` plus this immediate-next `docs/execution/CURRENT_TASK.md`, prove remote `phase/s7-commerce=A` and remote `main=P`, and record A later without attempting to self-record it here.
- Mandatory S8.1 integration evidence remains frozen: a prior-card `CheckRunnerCoordinator.finalizationAttempt` can survive a completed recheck and misclassify a same-session fresh check. S8.1 must exercise and correct that reusable seam before release.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S7.3 plan anchors: `## 7. Free evaluation, subscriptions, and payments` → explicit Restore Purchases, system Manage Subscription, signed lifecycle facts, paid-to-paid 16-day grace, Family Sharing off, data visibility, offline truth, and no data sync claim; `## 11. Build slices and release gates` → S7.3 restore/manage/status/offline; global execution anchors remain `## 16` and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / selected card S7.3 only.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `BCD64E2A42752D28844435241B5ABFCA911D04190375CBBDBFC10B45ACBA97D7` / `workflow_dispatch`.
- Selector at G0 may still equal accepted S7.2 compact JSON plus LF, 337 bytes, SHA-256 `3E2E10AB82C3EABCA1FCC68C2F08D95BC56A1B9BFA33AD33AEC609B81F65CB1B`; after complete G0 the first support mutation replaces it with the exact S7.3 object below, 342 bytes, SHA-256 `209F452E409683B78AD8F3958506D5AF19FF63D6305F39D744E822D3BF0F63F4`.

## Outcome and acceptance

- Outcome: activate separate **Restore Purchases** actions on Welcome and Settings, one shared lifecycle coordinator, system **Manage Subscription**, renewal/auto-renew-off, verified grace, billing retry/lapse, expiration, refund/revocation, startup/status updates, and signed offline interpretation through the existing S7.1 reducer/store/processor and S7.2 commerce navigation.
- Restore truth: only an explicit user tap may call `AppStore.sync()`. Both routes share one in-flight lock and the same result surface. Verified current entitlement must pass through the installed transaction processor, persist and reopen canonical authority before success, and never increment a purchase-result bucket. Cancel/failure/unverified/no-current-entitlement outcomes preserve all existing data and show honest retry/close without inventing access.
- Manage truth: **Manage Subscription** presents only Apple's system subscription-management surface and never a web checkout, guessed URL, direct cancellation, or app-authored billing control. Dismissal changes no authority and increments no purchase-result diagnostic.
- Lifecycle truth: render only verified signed facts and the frozen reducer state for introductory trial, active auto-renew-on/off, paid-to-paid grace, billing retry, expired/lapsed, refunded, and revoked. Active/auto-renew-off truth uses exact leading copy `Active until` with the verified expiration date. Grace requires signed grace authority and never exceeds the fixed 16-day paid-to-paid fact; billing retry without signed grace does not unlock.
- Offline truth: startup and transaction/status updates may refresh verified facts without calling `AppStore.sync()`. Offline UI reads only the durable cache and signed expiration/grace windows; stale, malformed, wrong-product, unresolved-tie, never-paid, expired, refunded, or revoked authority never invents grace or access. Existing signs/photos/reports remain visible in every state and subscription restore never claims to restore app data.
- GOLDEN: explicit Restore Purchases from Welcome and Settings processes verified current entitlement, durably persists access, preserves history, and exposes the system Manage Subscription route. The full signed status matrix shows truthful non-color lifecycle state including exact `Active until` copy, while startup/updates and fresh/offline reopen agree.
- ALT-1: offline/lapsed, no-current-entitlement, sync failure, pending/unverified/wrong-product, malformed cache, unresolved tie, duplicate tap, Manage dismissal, and counter failure retain data, do not finish or persist invalid authority, never auto-sync, and never invent grace/unlock.
- Accessibility/UI: one bounded Accessibility XXXL lifecycle flow proves the separate Restore action, non-color status, focus on progress/result/error, 44-point Restore/Manage/Close/Retry controls, unchanged existing history, and exactly one terminal in-app screenshot.
- Forbidden behavior: automatic `AppStore.sync()`; Restore-data-backup conflation; server receipt validation; backend/account/sync; annual/new product; Family Sharing; guessed grace/renewal/price; web/external purchase or management; direct cancellation; access gating or `DraftAccessPolicy`; entitlement/domain schema migration; App Store Connect mutation; signing, TestFlight, submission, deployment, release, or S7.4/S7.5 behavior.

## Environment and exact selector

- Route / repository / refs: Windows authoring → exact GitHub Actions macOS verification; `palatis3/AssetRounds / public / main / phase/s7-commerce`; never run or claim Windows Xcode/Simulator results.
- Required posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Runner / Xcode / project: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer / FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.2`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `F25 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S7.3","tier":"F25","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":900,"testTimeoutSeconds":1200,"uiTimeoutSeconds":1800,"totalBudgetSeconds":4500,"unitTestSelectors":["FieldEvidenceAppTests/S7_3LifecycleRestoreTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S7_3LifecycleUITests"]}` plus exactly one LF; 342 UTF-8 bytes, no BOM; SHA-256 `209F452E409683B78AD8F3958506D5AF19FF63D6305F39D744E822D3BF0F63F4`.
- Exact commands: `bash Scripts/run-with-timeout.sh 900 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 1200 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 1800 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, and UISmoke result bundles; exact one terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download. Force-push, merge commit, PR, ref rewrite/delete, main mutation before the S7 boundary, settings/secrets, App Store Connect, signing, TestFlight/App Store, deployment/release, and S9.2/S9.3 are forbidden.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/Infrastructure/Commerce/StoreKitTransactionProcessor.swift`
- `FieldEvidenceApp/Infrastructure/Commerce/StoreKitLifecycleCoordinator.swift`
- `FieldEvidenceApp/Features/Subscription/SubscriptionStatusView.swift`
- `FieldEvidenceApp/Features/Shell/AppShellView.swift`
- `FieldEvidenceApp/Features/Signs/SignsRootView.swift`

Test paths:

- `FieldEvidenceAppTests/S7_3LifecycleRestoreTests.swift`
- `FieldEvidenceAppUITests/S7_3LifecycleUITests.swift`

Standing selector exception:

- `Scripts/ci-selection.json`

No other implementation, model, project, resource, fixture, asset, script, workflow, authority, or documentation path is allowed during S7.3 implementation. Existing entitlement facts/reducer/store, product loader, StoreKit fixture/project/scheme, diagnostics APIs, purchase coordinator/paywall, app bootstrap, navigation, history, data-rights, and design tokens may be read and reused without editing. Append-only `docs/execution/HANDOFF.md` remains separately authorized bookkeeping after accepted evidence.

## G0 and verification

- Fresh G0 must prove the transition authority directly parents exact M, changes only append-only `docs/execution/HANDOFF.md` plus this immediate-next `docs/execution/CURRENT_TASK.md`, leaves remote `main=P`, preserves all pins, and expands the runbook's shorthand into exactly five production and two test paths within the default 10/5 cap.
- Validate the exact S7.3 F25 selector object against runbook Section 6 and the workflow schema. The accepted S7.2 selector is permitted only as predecessor state; after complete G0 replace only `Scripts/ci-selection.json` with the frozen S7.3 object as the first implementation-support mutation.
- Implement only S7.3. Candidate recovery follows the persistent evidence-driven direct-child loop without weakening GOLDEN/ALT, selectors, tests, StoreKit truth, watchdogs, or scope.
- After accepted exact-head S7.3 CI, read `KNOWN_BUGS.md`, append the immutable S7.3 HANDOFF, and—only with phase autopilot still enabled—commit/push exactly that append plus immediate-next S7.4 CURRENT_TASK. Run fresh S7.4 G0; do not mutate `main` during a same-phase transition.
