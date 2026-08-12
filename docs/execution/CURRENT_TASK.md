# Current Task

## Program and card

- Phase / branch / card / global order: `S2 / phase/s2-persistence-signs / S2.2 / 4 of 36`.
- Card heading: `### S2.2 — Add and reopen the first site/sign`.
- Position / boundary / immediate next card: `2 of 2 / phase boundary yes / S3.1`.
- Program autopilot / phase autopilot / exact S2 span / boundary integration: `enabled through accepted S9.1 / enabled / S2.1,S2.2 / yes`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S2 phase-main base: `P=8d5b0a7a2648589586b72e31dfe5dfc70eea63bd`.
- Accepted S2.1 product implementation and S2.2 card base: `E=M=I4=92005aadbaa75c2234a44c091322db9c58a82a5a`.
- Accepted S2.1 verification evidence: run `31622291782`, job `94199863326`, succeeded at exact `phase/s2-persistence-signs@M` with N8 and `run_ui_smoke=false`; artifact `ios-ci-31622291782-1`, ID `9151934510`, API digest `sha256:ac59e8fe8248f66035808981eb42b4bd81e48dc8eb1cba9ceaf786ea1d4a2b52`; `SHA256SUMS.txt` SHA-256 `21805E7F09DD24409C345C86A55B143729C6E7CA3EFB27F9BC32C97A448D941F`; all 75 listed payload files independently matched with no missing, unlisted, duplicate, or mismatched file; exact selector resolved and all 11 non-skipped unit tests passed. Runner `macos26` image `20260728.0273.1`, Xcode 26.6 `17F113`, iPhone 17/iOS 26.5, UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`; setup 29/300 s, Simulator readiness 274/900 s, build 152/600 s, test 83/900 s, setup+artifact 33/300 s, total 401/2400 s.
- Prior S2.1 failure provenance: I run `31619809012` failed on the missing DiagnosticsV1 return; I2 run `31620710289` failed on malformed parameterized-test tuple syntax; I3 run `31621397396` built and ran 11 tests but failed 6 assertions because absent `FieldEvidenceData` was not recognized as fresh bootstrap. Each direct-child correction addressed only its diagnosed cause; none of those runs is accepted.
- Task-start authority head `A`: `OBSERVE AT POST-COMMIT G0; never self-record its SHA here`.
- Required `M..A`: one direct-child same-phase transition commit changing exactly the append-only accepted S2.1 entry in `docs/execution/HANDOFF.md` plus `docs/execution/CURRENT_TASK.md`.
- Construction state: immediately before transition, remote `phase/s2-persistence-signs` must equal M and remote `main` must remain P. Push only the exact transition non-force and require remote phase A plus clean index/worktree/untracked state at fresh G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S2.2 plan anchors: `## 5. Navigation and onboarding` (`### Navigation`, `### Onboarding contract`, steps 1–2); `## 7. Free evaluation, subscriptions, and payments` (`### Free evaluation`); `## 9. Smallest reusable architecture` (`### Technology`, `### Persistent models`). Global execution anchors remain `## 11. Build slices and release gates`, `## 16. Owner preparation checklist`, and `## 18. Codex execution authority`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79`.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Selector schema path: `Scripts/ci-selection.json`; at G0 it may still equal the accepted S2.1 object with LF-terminated SHA-256 `552480502E50CFFCCD871CEE9A42396BDE53780DCDB12B83E72C839636BA983E`. Its first support mutation must replace it with the exact S2.2 object below, LF-terminated SHA-256 `C5EAA9DD13E1262BF54187604C4E72795F8D491DE109A544E6E21C04222FBAA5`.

## Outcome and acceptance

- Outcome: add the Welcome, View sample, and Add first sign flow; save one required customer/site label and sign label, optional collapsed address, and optional confirmed-IANA time zone; show sign detail and reopen that exact sign after relaunch. Welcome exposes stable **Restore data backup** and separate accessible **Restore Purchases** anchors, but S6.4 and S7.3 respectively remain their first activation cards.
- Exact Welcome delta: show title `Turn tonight's sign check into a clear report.`, primary **Add first sign**, secondary **View sample**, and stable separately identified **Restore data backup** and **Restore Purchases** anchors. The latter two perform no restore, commerce, remote, or navigation operation in S2.2.
- Exact new-sign delta: require customer/site name and sign name; keep address collapsed and optional; accept only an optional explicitly confirmed exact IANA time-zone identifier, otherwise persist `Site.timeZoneID=null`; expose primary **Save and start check**. One successful model save inserts exactly one Site and one Asset using the loaded exact bundled pack ID/schema/content versions, then shows sign detail; it creates no WorkflowRecord or draft.
- Direct persistence seam: feature code uses the coordinator-provided `ModelContext` and the existing `DiagnosticsStore` instance passed from `StartupRouter`. It retains no `ModelContainer` and creates no repository, persistence service, command bus, second diagnostics actor, or generic form engine.
- Input and atomicity rules: trim surrounding whitespace; blank optional address becomes nil. A supplied zone must be an exact member of `TimeZone.knownTimeZoneIdentifiers` and explicitly confirmed; omitted input alone may remain nil. Validate before insert, focus one first invalid accessible state, and write no row/counter on invalid input. Require zero existing Asset rows for this first-sign-only action. Insert Site+Asset, perform one context save, and only after successful first Asset commit attempt `first_sign_created`; diagnostics failure is non-gating and has no retry/applied-ID ledger.
- Sign detail delta: show the exact saved site/sign labels and optional address/time-zone values. **Start Check** is explicitly unavailable until S3.1 and creates no draft.
- GOLDEN: present-optional and nil-optional first-sign cases save, release, and reopen the exact site/sign labels, address, nullable confirmed-IANA zone, Site↔Asset ID link, and exact pack ID/schema/content versions. Diagnostics has only `first_sign_created=1`. UI proves Welcome, sample/back, create, detail, inert explicitly unavailable Start Check, termination/relaunch, and identical reopened detail.
- ALT-1: parameterized whitespace-only required labels, unknown IANA identifier, and supplied-but-unconfirmed zone focus exactly one accessible validation state and leave zero Site rows, zero Asset rows, and zero diagnostics increments.
- Forbidden behavior: second-sign control; map, geocoder, location lookup, device-zone default/guess; Packet/root accounting implementation; draft/preflight/check runner; access policy/paywall; restore/import or StoreKit behavior; repository/persistence abstraction; extra ledger; camera/media/report code; project/package/capability/permission delta; remote service; or generic onboarding/form framework.

## Environment and exact selector

- Route / host: Windows authoring → GitHub Actions macOS verification; never run or claim local Windows Xcode/Simulator results.
- Required tool posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration is active; XcodeBuildMCP and an owner-operated Mac are unnecessary.
- Repository / visibility / default / phase: `palatis3/AssetRounds / private / main / phase/s2-persistence-signs`.
- Runner / Xcode / developer dir: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer`.
- Project / scheme / configuration / deployment: `FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S2.2","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S2SignSetupTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S2SignSetupUITests"]}`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, and UISmoke result bundles; terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging and one-purpose commits; non-force phase-branch push; named `workflow_dispatch` with exact branch ref and `run_ui_smoke=true`; run observation and artifact download; after accepted S2.2 evidence, HANDOFF-only phase close, exact phase verification, verified non-force `main` fast-forward from P, exact-main P12 verification, and creation/hydration of only `phase/s3-check-runner` at S3.1. Forbidden methods: force-push, merge commit, PR creation/merge, ref deletion/rewrite, repository/settings/secret mutation, signing, TestFlight/App Store upload, deployment, release publication, or S9.2/S9.3 action.

## Known predecessor harness posture

- The inherited `Scripts/ui-smoke.sh` contains S1-specific test/attachment export assumptions. This observation grants no ordinary S2.2 edit authority, and the script is excluded from the product envelope.
- Dispatch and inspect the exact S2.2 product head first. Only terminal evidence diagnosing an S2 selector or retained-attachment harness mismatch may authorize one direct-child nonproduct K changing the smallest causal `Scripts/ui-smoke.sh` delta plus required `CURRENT_TASK.md` recovery evidence/pin under the standing recovery policy. Preserve product, project, tests, fixtures, selector semantics, exact commands, required evidence/checksum/upload enforcement, and timeout behavior.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/App/FieldEvidenceAppApp.swift`
- `FieldEvidenceApp/Features/Shell/AppShellView.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift`
- `FieldEvidenceApp/Features/Signs/FirstSignCoordinator.swift`
- `FieldEvidenceApp/Features/Signs/SignsRootView.swift`
- `FieldEvidenceApp/Features/Signs/NewSignView.swift`
- `FieldEvidenceApp/Features/Signs/SignDetailView.swift`

Test paths:

- `FieldEvidenceAppTests/S2SignSetupTests.swift`
- `FieldEvidenceAppUITests/S2SignSetupUITests.swift`

Standing support exception:

- `Scripts/ci-selection.json`

`docs/execution/HANDOFF.md` is append-only post-green bookkeeping and is not part of the implementation commit. `Scripts/ui-smoke.sh` is not an ordinary S2.2 implementation path. No other path may change.

## Execution

1. Commit exactly the accepted S2.1 HANDOFF append plus this immediate-next `CURRENT_TASK.md`, push non-force only after proving remote phase=M and main=P, then run fresh S2.2 G0.
2. G0 proves A^=M; exactly one commit and exactly HANDOFF plus CURRENT_TASK in M..A; the HANDOFF delta is one append-only complete S2.1 entry; P, program map, S2 branch/span/integration flags, pins/environment/method posture are unchanged; every immediate-card field equals frozen S2.2; selector remains the accepted S2.1 object; and no other path is dirty.
3. Replace the selector first, implement only the allowed paths, run structural/static checks available on Windows, explicitly stage only task paths, and commit direct-child implementation I.
4. Push the exact phase ref non-force and run the one-at-a-time persistent P12 verification loop. Accept only green exact-head CI with complete checksummed evidence. Hosted variance gets a fresh run ID; diagnosed product or harness failures get one direct-child correction per commit with no numeric ceiling.
5. Do not preemptively edit `Scripts/ui-smoke.sh`. If terminal exact-product-head evidence diagnoses its inherited S1-specific export as the sole harness failure, create only the minimal nonproduct K permitted by the recovery policy and verify that exact K.
6. After accepted S2.2 product and verification evidence, append HANDOFF and create/push HANDOFF-only phase close C. Verify exact phase C or a diagnosed later nonproduct verification head, fast-forward main non-force from exact P to that accepted head, and require exact-main P12/UI success.
7. Only after accepted exact-main S2 create `phase/s3-check-runner` from that head, hydrate CURRENT_TASK-only S3.1, and run fresh G0.

## Definition of done

- Exact green S2.2 implementation, phase-close, and exact-main P12 evidence with complete artifacts; exact first-site/sign save and relaunch reopen; optional address and nullable explicitly confirmed IANA zone; exact Welcome/sample/later-activation anchors; installation-first diagnostics attempt; invalid input writes nothing and focuses one accessible state; Start Check explicitly unavailable; no second sign, draft, evaluation ledger, restore/commerce implementation, schema, or forbidden path.
- Handoff records all required evidence. Remote S2 phase and main equal the accepted S2 verification head. Then continue only with S3.1.
