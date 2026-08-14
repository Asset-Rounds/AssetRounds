# Current Task

## Program and card

- Phase / branch / card / global order: `S7 / phase/s7-commerce / S7.2 / 28 of 36`.
- Card heading: `### S7.2 — Purchasable paywall and purchase-state truth`.
- Position / boundary / immediate next card: `2 of 5 / phase boundary no / S7.3 only after accepted S7.2 evidence and a fresh same-phase transition G0`.
- Program autopilot / phase autopilot / exact S7 span / boundary integration: `enabled through accepted S9.1 / enabled / S7.1,S7.2,S7.3,S7.4,S7.5 / yes`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S7 phase-main base: `P=5f50551f61bc363b430d4e877e462cb47865065d`; this is the accepted S6 HANDOFF-only phase-close and exact-main verification head. It remains byte-for-byte fixed throughout S7.
- Integrated/card base: `M=f1d22d248a5d76dd2ac66bb2c57e7f06d0d177bc`; accepted S7.1 implementation and exact-head verification head.
- Accepted S7.1 product evidence: `E=M=f1d22d248a5d76dd2ac66bb2c57e7f06d0d177bc`; run `31841797858` / job `94900070630`, exact `phase/s7-commerce@E`, attempt 1, N8/UI disabled, terminal success, build plus `5/5` units green.
- Accepted S7.1 artifact: `ios-ci-31841797858-1`, ID `9234729879`, size `128221`, digest `sha256:749284a0628a63e674835956ad39f64588f2334b30513dff009a7d868b0c6913`; all `63/63` checksums matched; `SHA256SUMS.txt` SHA-256 `7E129174BE4AD43930DFBF1737CE47B6741A76408B7F3AA0DDA3970BD5C4C292`.
- Accepted environment: `macos26` image `20260728.0273.1`; Xcode 26.6 build `17F113`; iPhone 17 / iOS 26.5; Simulator UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`.
- S7.1 recovery provenance remains immutable: failed candidates `31840694764` and `31841260095` were diagnosed, corrected by successive direct children, and never accepted or rerun by run ID.
- Mandatory later integration evidence remains frozen: a prior-card `CheckRunnerCoordinator.finalizationAttempt` can survive a completed recheck and misclassify a same-session fresh check. S8.1 must exercise and correct that reusable seam before release.
- Task-start transition authority: `A=02b9aa17c7c29c9614a0cd3b4f9f0ca0e4996013`; `A^=M`, and `M..A` changes only append-only `docs/execution/HANDOFF.md` plus the S7.2 replacement `docs/execution/CURRENT_TASK.md`.
- Owner-copy authority: the owner approved all four exact recovery messages on `2026-08-14`. The direct-child CURRENT_TASK-only authority correction `A2` is observed after it exists at fresh G0; this file deliberately never self-records that future SHA.
- Required `A..A2`: exactly one direct-child commit changing only `docs/execution/CURRENT_TASK.md`; remote `phase/s7-commerce=A2`, remote `main=P`, and no other dirty path at fresh G0.
- Diagnosed recovery authority: after exact-head run `31847380324` proved the existing StoreKit configuration is unavailable to the scheme Test action, the owner approved `FieldEvidenceApp.xcodeproj/xcshareddata/xcschemes/FieldEvidenceApp.xcscheme` as the one additional S7.2 project path on `2026-08-14`. The authority commit changes only this file; the following correction may attach only the existing `TestFixtures/StoreKit/FieldEvidence.storekit` reference to the Test action without changing the fixture, product, selector, workflow, or pinned environment.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S7.2 plan anchors: `## 7. Free evaluation, subscriptions, and payments` → sole monthly product, explicit paywall, StoreKit-localized price/duration/eligibility, required purchase states, exact data/no-sync boundary, durable-before-finish entitlement truth, existing-data visibility, and no annual/external purchase path; `## 11. Build slices and release gates` → S7.2 first purchase UI; global execution anchors remain `## 16` and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / selected card S7.2 only.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Selector at G0 remains accepted S7.1 compact JSON plus LF, 288 bytes, SHA-256 `5EDA4846E62842DBC2933A65706B335C6B6431D067DF38F46DFA1443E528DE08`; after a complete G0 the first support mutation replaces it with the exact S7.2 object below, 337 bytes, SHA-256 `3E2E10AB82C3EABCA1FCC68C2F08D95BC56A1B9BFA33AD33AEC609B81F65CB1B`.

## Outcome and acceptance

- Outcome: add the first purchasable `SubscriptionStoreView(productIDs:)` for only `com.palatis3.fieldrecord.sub.solo.monthly.v1`, one explicit Settings entry, one shared purchase coordinator, honest loading/unavailable/eligible/ineligible/purchasing/terminal state truth, StoreKit-localized disclosure, injected test-only catalog links, and close-to-history behavior through the already installed S7.1 processor.
- Product disclosure truth: render only StoreKit-provided localized product name, one-month duration, full renewal price, and introductory eligibility. Eligible fixture truth visibly states `14 days free` and the exact post-trial monthly renewal; ineligible truth shows the localized standard monthly renewal without claiming a trial. Include unlimited-local value and the frozen boundary that inspection data/photos are device-local and do not sync with the subscription. Never guess or hardcode a customer price, annual savings, eligibility, group, or unavailable product fact.
- Purchase truth: only an explicit user tap starts purchase. While purchasing, one lock prevents double submission. A verified exact-product transaction flows through the preinstalled processor, becomes entitled only after the canonical cache is durably written and reopened, then finishes exactly once; the UI cannot unlock from a tap, download, pending result, or unverified result.
- Terminal-state truth: StoreKit user-cancelled, pending, unverified, and other failed results keep all existing history visible, do not create paid authority, release the purchasing lock, show their owner-frozen exact recovery message, and increment only the matching closed diagnostics bucket. Verified increments only `verified` after durable processing. Product loading, renewal updates, redraws, Close, and links increment no purchase-result bucket.
- Owner-frozen recovery copy: cancelled is `Purchase canceled. Nothing changed. You can try again when you’re ready.`; pending is `Purchase pending. Your existing data is still available. Access will update when the App Store completes the purchase.`; unverified is `Purchase couldn’t be verified. Your existing data is still available. Try again.`; failed is `Purchase couldn’t be completed. Your existing data is still available. Try again.`. These strings are exact and may not be shortened, combined, or paraphrased.
- Presentation/diagnostics truth: `paywall_presented` is attempted once per distinct modal token, never per SwiftUI redraw. Close returns to unchanged history and never implies purchase success. Counter failure cannot roll back or grant entitlement.
- Link truth: Terms, Privacy, and Support use only injected URLs in tests: `https://example.invalid/terms`, `https://example.invalid/privacy`, and `https://example.invalid/support`. Production configuration remains absent at this card; every missing, malformed, non-HTTPS, or unexpected host fails closed without opening a link. No link becomes an external purchase route.
- Unavailable truth: product-load or catalog-link unavailability shows honest retry/close, retains history, and displays no guessed name, price, trial, duration, eligibility, or success.
- GOLDEN: eligible and ineligible StoreKit fixtures prove localized monthly name/duration/full renewal price, exact trial/renewal/no-sync disclosures, visible close-to-history, a single purchasing lock, verified durable-before-unlock/finish behavior, one presentation diagnostic, and exactly one verified result bucket. Table-driven cancelled, pending, unverified, and failed paths prove unchanged history/authority, lock release, exact recovery copy, and only their matching diagnostic bucket.
- ALT-1: unavailable product, missing/malformed/unsafe links, wrong product, double tap, counter failure, and purchase failure show honest retry/close, never guess price/trial, never unlock, never hide data, never finish an unverified transaction, and never open a web/external purchase path.
- Accessibility/UI: one bounded Accessibility XXXL paywall flow with StoreKit-localized truth, exact recovery focus, 44-point controls, reachable links/Close/Retry, non-color status, no clipped primary action, and exactly one terminal in-app screenshot.
- Forbidden behavior: Restore Purchases; `AppStore.sync()`; Manage Subscription; lifecycle/grace/billing/expiry/refund status UI; access gating or `DraftAccessPolicy`; automatic paywall from first-sign onboarding/value receipt; annual product; hardcoded price; web checkout; external-purchase link; Stripe/license key; remote paywall/config; entitlement or domain schema/model migration; App Store Connect/Sandbox account mutation; backend/account/sync; signing, TestFlight, submission, deployment, or release.

## Environment and exact selector

- Route / repository / refs: Windows authoring → exact GitHub Actions macOS verification; `palatis3/AssetRounds / public / main / phase/s7-commerce`; never run or claim Windows Xcode/Simulator results.
- Required posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Runner / Xcode / project: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer / FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S7.2","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S7_2PaywallPurchaseTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S7_2PaywallUITests"]}` plus exactly one LF; 337 UTF-8 bytes, no BOM; SHA-256 `3E2E10AB82C3EABCA1FCC68C2F08D95BC56A1B9BFA33AD33AEC609B81F65CB1B`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, and UISmoke result bundles; exact one terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download. Force-push, merge commit, PR, ref rewrite/delete, main mutation before the S7 boundary, settings/secrets, App Store Connect, signing, TestFlight/App Store, deployment/release, and S9.2/S9.3 are forbidden.

## Exact allowed implementation paths

Production/project paths:

- `FieldEvidenceApp/Features/Subscription/PaywallView.swift`
- `FieldEvidenceApp/Infrastructure/Commerce/StoreKitPurchaseCoordinator.swift`
- `FieldEvidenceApp/Infrastructure/Commerce/StoreKitProductLoader.swift`
- `FieldEvidenceApp/Infrastructure/Commerce/StoreKitTransactionProcessor.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift`
- `FieldEvidenceApp/App/FieldEvidenceAppApp.swift`
- `FieldEvidenceApp/Features/Shell/AppShellView.swift`
- `FieldEvidenceApp/Features/Signs/SignsRootView.swift`
- `FieldEvidenceApp.xcodeproj/xcshareddata/xcschemes/FieldEvidenceApp.xcscheme`

Test paths:

- `FieldEvidenceAppTests/S7_2PaywallPurchaseTests.swift`
- `FieldEvidenceAppUITests/S7_2PaywallUITests.swift`

Standing selector exception:

- `Scripts/ci-selection.json`

No other implementation, model, project, resource, fixture, script, workflow, authority, or documentation path is allowed during S7.2 implementation. Existing S7.1 entitlement facts/reducer/store, Diagnostics purchase/paywall APIs, StoreKit fixture, navigation, design tokens, history, and data-rights surfaces may be read and reused without editing. Append-only `docs/execution/HANDOFF.md` remains separately authorized bookkeeping after accepted evidence.

## G0 and verification

- Fresh recovery G0 must additionally prove the owner-approved CURRENT_TASK-only authority commit directly parents exact failed head `b7601c50e669ea7f34349da65e5e38fd1555fad8`, remote `main=P`, all pins and selector bytes remain unchanged, and the nine-production/project/two-test expanded envelope remains inside the default 10/5 cap.
- After complete G0, replace only `Scripts/ci-selection.json` with the frozen S7.2 object, then implement exactly this card. Candidate recovery follows the persistent evidence-driven direct-child loop without weakening acceptance or expanding paths.
- After accepted exact-head S7.2 CI, read `KNOWN_BUGS.md`, append the immutable S7.2 HANDOFF, and—only with phase autopilot still enabled—commit/push exactly that append plus immediate-next S7.3 CURRENT_TASK. Run fresh S7.3 G0; do not mutate `main` during a same-phase transition.
