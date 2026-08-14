# Current Task

## Program and card

- Phase / branch / card / global order: `S7 / phase/s7-commerce / S7.1 / 27 of 36`.
- Card heading: `### S7.1 — StoreKit reducer and durable processor core, no purchase UI`.
- Position / boundary / immediate next card: `1 of 5 / phase boundary no / S7.2 only after accepted S7.1 evidence and a fresh same-phase transition G0`.
- Program autopilot / phase autopilot / exact S7 span / boundary integration: `enabled through accepted S9.1 / enabled / S7.1,S7.2,S7.3,S7.4,S7.5 / yes`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S7 phase-main base: `P=5f50551f61bc363b430d4e877e462cb47865065d`; this is the accepted S6 HANDOFF-only phase-close and exact-main verification head. It remains byte-for-byte fixed throughout S7.
- Integrated/card base: `M=P=5f50551f61bc363b430d4e877e462cb47865065d`; S7.1 is the first S7 card.
- Accepted S6.6 product evidence: `E=198d577cba3e51c2380b16d5e07ed4f213067882`; run `31834072656` / job `94876291120`, exact `phase/s6-data-rights@E`, attempt 1, P12/UI enabled, terminal success, `9/9` units and `1/1` UI green.
- Accepted S6 phase-close evidence: `C=P=5f50551f61bc363b430d4e877e462cb47865065d`; run `31835241736` / job `94879988422`, exact `phase/s6-data-rights@P`, attempt 1, P12/UI enabled, terminal success. Artifact `ios-ci-31835241736-1`, ID `9232526436`, size `4429071`, digest `sha256:3563ae7ef05cc15a12c23b83948b31354988b331e7c877a3d4d08b16312ce928`; all `109/109` checksums matched; `SHA256SUMS.txt` SHA-256 `5DC9B4FBC82C3F72879C437D714D2BD34DF7FDA5FEB7FC2E7BE5F8BD5F4ECB8D`.
- Accepted exact-main S6 integration evidence: run `31836285367` / job `94883189785`, exact `main@P`, attempt 1, P12/UI enabled, terminal success, build plus `9/9` units plus `1/1` UI green. Artifact `ios-ci-31836285367-1`, ID `9233101396`, size `4473532`, digest `sha256:8ba0e2ea3508122be58a0f4fe020bc2934fdd9623f15d1177a929b5a0b4daa0e`; all `109/109` checksums matched; `SHA256SUMS.txt` SHA-256 `242C36345948D3AD1CC975E517760643475CBC48E2463EDE92FE0150513E6D5C`; terminal screenshot SHA-256 `F01299E82577B0561FFE06D910B57D7029827F98D0ECA468C8C57D95D805BDD2`.
- Accepted environment: `macos26` image `20260728.0273.1`; Xcode 26.6 build `17F113`; iPhone 17 / iOS 26.5; Simulator UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`.
- S6.6 recovery provenance remains immutable: failed candidates `31819851272`, `31820957460`, `31821990724`, `31823318129`, `31824479813`, `31826107503`, `31827681166`, `31829229147`, `31831021189`, and `31833079389` were diagnosed, corrected by successive direct children, and never accepted or rerun by run ID.
- Mandatory later integration evidence remains frozen: a prior-card `CheckRunnerCoordinator.finalizationAttempt` can survive a completed recheck and misclassify a same-session fresh check. S8.1 must exercise and correct that reusable seam before release.
- Task-start authority A is the direct-child S7.1 hydration commit observed after it exists at fresh G0; this file deliberately never self-records that future SHA.
- Required `P..A`: exactly one direct-child commit changing only this replacement `docs/execution/CURRENT_TASK.md`; remote `phase/s7-commerce=A`, remote `main=P`, remote `phase/s6-data-rights=P`, and no other dirty path at fresh G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S7.1 plan anchors: `## 7. Free evaluation, subscriptions, and payments` → exact monthly identifier, verified StoreKit authority, required purchase states, durable-before-finish ordering, offline expiration truth, 14-day introductory offer, 16-day paid-renewal grace, and Family Sharing off; `## 11. Build slices and release gates` → S7.1 core with no purchase UI; global execution anchors remain `## 16` and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / selected card S7.1 only.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Selector at G0 remains accepted S6.6 compact JSON plus LF, 336 bytes, SHA-256 `8EE33FCE260474843CD33FBF8565C0FE19248AA19B550F4FB59542E41B191BC2`; after G0 the first support mutation replaces it with the exact S7.1 object below, 288 bytes, SHA-256 `5EDA4846E62842DBC2933A65706B335C6B6431D067DF38F46DFA1443E528DE08`.

## Outcome and acceptance

- Outcome: install the exact monthly StoreKit product loader, verified-fact model, pure normalized entitlement reducer, canonical durable entitlement cache, transaction processor/observer, and offline-cache interpretation at app startup, with no purchasable UI or explicit StoreKit sync.
- Product/fixture truth: the sole product ID is `com.palatis3.fieldrecord.sub.solo.monthly.v1`; the shared CI/Simulator-only `.storekit` configuration is monthly, includes the frozen 14-day introductory offer, represents the frozen 16-day paid-to-paid Billing Grace behavior, and has Family Sharing off. Runtime product name, duration, price, and eligibility remain StoreKit-provided; no annual product, guessed product/group, hardcoded customer price, live App Store SKU, or App Store Connect mutation is created.
- Cache truth: canonical `Application Support/FieldEvidenceCommerce/entitlement.json` contains exactly `schemaVersion=1`, `productID`, normalized `state`, nullable `expirationAt`, nullable `graceExpirationAt`, nullable `revocationAt`, `verifiedAt`, and monotonic `hasEverVerifiedPaid`. It stores no JWS, receipt, transaction ID, storefront/customer identity, or content. Only verified exact-product facts can change it; malformed/unknown/colliding authority fails closed.
- Reducer truth: accept only verified exact-product transaction, subscription-status, and renewal facts. Output only `loading`, `entitled(active, until)`, `entitled(grace, until)`, `never_paid`, or `former_paid_inactive(reason=billing_retry|expired|refunded|revoked)`. Active trial/subscription and auto-renew-off remain entitled through signed expiration; signed grace remains entitled only through its grace expiration; billing retry outside grace and expiration are inactive; verified refund/revocation is immediately inactive.
- Selection truth: when more than one verified exact-product status exists, choose the latest product transaction by purchase instant and then expiration; an unresolved tie fails closed. Never combine authority across products or synthesize missing time/renewal facts.
- Durability truth: a verified purchased transaction, including an introductory trial, sets `hasEverVerifiedPaid=true` irreversibly, persists the complete normalized entitlement atomically, reopens/verifies the canonical bytes, and only then calls `finish()` exactly once. A failed durable write never finishes. Pending, cancelled, failed, and unverified inputs never mutate paid facts and never finish an unverified transaction.
- Startup/observer truth: ordinary startup installs one processor and observes `Transaction.updates` plus current verified entitlement/status facts without `AppStore.sync()`. Repeated startup/update delivery is idempotent and cannot regress a still-valid verified cache or double-finish a transaction.
- Offline truth: honor a previously verified cache only through its recorded signed expiration/grace/revocation facts at the supplied current time; never invent a second timer or grace interval. Pending/unverified facts never overwrite a still-valid verified cache. When no valid cache remains, `hasEverVerifiedPaid=false` yields `never_paid`; a known former payer yields the exact inactive reason rather than reopening the free evaluation.
- GOLDEN: a parameterized verified-state table proves active subscription, introductory trial, auto-renew-off before expiration, signed grace, billing retry outside grace, expiration, refund, revocation, latest-fact selection, offline-before/at/after-boundary interpretation, durable reopen, updates observation, and persist-before-finish.
- ALT-1: wrong-product, unresolved tie, pending, cancelled, failed, unverified, malformed-cache, write-failure, replay, and offline-expired inputs fail closed without creating or regressing paid authority or finishing an unverified/unpersisted transaction.
- Accessibility/UI: none in this card. S7.1 adds no route, purchase action, paywall, disclosure surface, customer-facing price/trial copy, or UI smoke.
- Forbidden behavior: `SubscriptionStoreView`; purchase button; paywall route; Restore Purchases; `AppStore.sync()`; Manage Subscription; unlock UI; `DraftAccessPolicy`; feature gating; annual product; hardcoded price; external purchase/web checkout; Stripe/license key; entitlement schema/model migration; App Store Connect/Sandbox account mutation; capability/entitlement/permission/backend/account/sync; signing, TestFlight, submission, deployment, or release.

## Environment and exact selector

- Route / repository / refs: Windows authoring → exact GitHub Actions macOS verification; `palatis3/AssetRounds / public / main / phase/s7-commerce`; never run or claim Windows Xcode/Simulator results.
- Required posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Runner / Xcode / project: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer / FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `N8 / run_ui_smoke=false`.
- Exact selector: `{"schemaVersion":1,"taskID":"S7.1","tier":"N8","runUISmoke":false,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":0,"totalBudgetSeconds":2400,"unitTestSelectors":["FieldEvidenceAppTests/S7_1CommerceCoreTests"],"uiTestSelectors":[]}` plus exactly one LF; 288 UTF-8 bytes, no BOM; SHA-256 `5EDA4846E62842DBC2933A65706B335C6B6431D067DF38F46DFA1443E528DE08`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; UI smoke is disabled and its selector is empty.
- Required evidence: nonempty boot/build/unit logs; Build and UnitTests result bundles; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`. No UISmoke result or screenshot is required for N8.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=false`; exact-run observation/download. Force-push, merge commit, PR, ref rewrite/delete, main mutation before the S7 boundary, settings/secrets, App Store Connect, signing, TestFlight/App Store, deployment/release, and S9.2/S9.3 are forbidden.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/Domain/Commerce/EntitlementFactsV1.swift`
- `FieldEvidenceApp/Domain/Commerce/EntitlementReducerV1.swift`
- `FieldEvidenceApp/Infrastructure/Commerce/EntitlementStore.swift`
- `FieldEvidenceApp/Infrastructure/Commerce/StoreKitProductLoader.swift`
- `FieldEvidenceApp/Infrastructure/Commerce/StoreKitTransactionProcessor.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift`
- `FieldEvidenceApp/App/FieldEvidenceAppApp.swift`
- `FieldEvidenceApp.xcodeproj/project.pbxproj`
- `FieldEvidenceApp.xcodeproj/xcshareddata/xcschemes/FieldEvidenceApp.xcscheme`
- `TestFixtures/StoreKit/FieldEvidence.storekit`

Test paths:

- `FieldEvidenceAppTests/S7_1CommerceCoreTests.swift`

Standing selector exception:

- `Scripts/ci-selection.json`

No other implementation, model, project, resource, fixture, script, workflow, authority, or documentation path is allowed during S7.1 implementation. Existing StoreKit-free app startup, immutable-generation/session, canonical JSON, descriptor-pinned storage, Diagnostics, Erase, backup/restore, and navigation seams may be read and reused without editing. Append-only `docs/execution/HANDOFF.md` remains separately authorized bookkeeping after accepted evidence.

## G0 and verification

- Fresh G0 must prove clean `phase/s7-commerce`, `A^=M=P`, exact one-commit CURRENT_TASK-only `P..A`, remote S7 phase=A, remote main=P, remote S6 phase=P, all pins, accepted S6.6/phase/exact-main run and artifact evidence, accepted predecessor S6.6 selector byte-exact, and the ten-production/one-test expanded envelope inside the default 10/5 cap.
- After G0, replace only `Scripts/ci-selection.json` with the frozen S7.1 object, then implement exactly this card. Candidate recovery follows the persistent evidence-driven direct-child loop without weakening acceptance or expanding paths.
- After accepted exact-head S7.1 CI, read `KNOWN_BUGS.md`, append the immutable S7.1 HANDOFF, and—only with phase autopilot still enabled—commit/push exactly that append plus immediate-next S7.2 CURRENT_TASK. Run fresh S7.2 G0; do not mutate `main` during a same-phase transition.
