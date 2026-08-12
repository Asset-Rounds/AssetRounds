# Current Task

## Program and card

- Phase / branch / card / global order: `S2 / phase/s2-persistence-signs / S2.1 / 3 of 36`.
- Card heading: `### S2.1 — Persistence roots, generation seam, and diagnostics`.
- Position / boundary / immediate next card: `1 of 2 / phase boundary no / S2.2`.
- Program autopilot / phase autopilot / exact S2 span / boundary integration: `enabled through accepted S9.1 / enabled / S2.1,S2.2 / yes`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Accepted S1 phase-close/verification head and S2 phase-main base: `P=M=8d5b0a7a2648589586b72e31dfe5dfc70eea63bd`.
- Accepted S1 product/verification lineage: `E=I4=2b9c921e545536d13712c85015d4b0d2f9fb780b`; nonproduct verification head `K=88f8b69ad9262f47e2b00511fab4b73b745c0168`; HANDOFF-only phase close `C=8d5b0a7a2648589586b72e31dfe5dfc70eea63bd`, a direct child of K changing exactly `docs/execution/HANDOFF.md`.
- Predecessor phase evidence: run `31613512833`, job `94170508910`, succeeded at exact `phase/s1-shell-design@C` with P12/UI enabled; artifact `ios-ci-31613512833-1`, ID `9148640755`, API digest `sha256:d33f3f61100fbff9e66de404c00b206bbb8d13163d25ff323677c0399b75ad43`, with 99 checksum entries.
- Predecessor exact-main evidence: run `31614912784`, job `94175195169`, succeeded at exact `main@C` with P12/UI enabled; artifact `ios-ci-31614912784-1`, ID `9149259731`, API digest `sha256:4e1977b54de689894ef941afa707f033b8d0f526a616615b4b19f26fdca58da2`; `SHA256SUMS.txt` SHA-256 `BECF7BB2BD2D89258A28ECE8D7A696A4F384F664119B4489E908D5482426A306`; all 99 listed payloads independently matched with no missing, unlisted, duplicate, or mismatched file; accepted `ui-final.png` SHA-256 `EA33D215DDE2FC11F362531BFB5ED5C9A9A5A70A74F4ABCF2F94F03B4FCEE310` visually shows the actual Dark accessibility-XXXL app shell. Runner `macos26` image `20260728.0273.1`, Xcode 26.6 `17F113`, iPhone 17/iOS 26.5, UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`; setup 26/300 s, Simulator readiness 364/900 s, setup+artifact 27/300 s, total 795/3300 s.
- Task-start authority head `A`: `OBSERVE AT POST-COMMIT G0; never self-record its SHA here`.
- Required `M..A`: one direct-child authority commit changing exactly `docs/execution/CURRENT_TASK.md`.
- Construction state: both remote `main` and `phase/s1-shell-design` equal C; remote `phase/s2-persistence-signs` is absent. Create only `phase/s2-persistence-signs` from M=C, commit CURRENT_TASK-only A, and require clean index/worktree/untracked state at post-commit G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S2.1 plan anchors: `## 9. Smallest reusable architecture` (`### Technology`, `### Persistent models`); `## 10. Storage, crash consistency, and one-off bug prevention`; `## 14. Analytics, feedback, and learning`. Global execution anchors remain `## 11. Build slices and release gates`, `## 16. Owner preparation checklist`, and `## 18. Codex execution authority`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79`.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Selector schema path: `Scripts/ci-selection.json`; at G0 it may still equal the accepted S1.1 object with SHA-256 `F6D8FD7495095C20EC7C7285E12223BE718880DDF7C5D5DA8A4ED34982E775CC`. Its first support mutation must replace it with the exact S2.1 object below, LF-terminated SHA-256 `552480502E50CFFCCD871CEE9A42396BDE53780DCDB12B83E72C839636BA983E`.

## Outcome and acceptance

- Outcome: add only the exact `Site` and `Asset` SwiftData models, immutable-generation data root and pointer seam, main-actor `StoreSessionCoordinator`, exact `DiagnosticsV1` store, fixed startup ordering, and initialized minimal full-screen `StartupMaintenanceView`.
- Exact model delta: schema version 1 adds only `Site` with `id`, `schemaVersion`, `label`, nullable `address`, nullable confirmed-IANA `timeZoneID`, `createdAt`, and `updatedAt`; and `Asset` with `id`, `schemaVersion`, `siteID`, `packID`, `packSchemaVersion`, `packContentVersion`, `label`, `createdAt`, and `updatedAt`. No other model or schema field is added.
- Exact generation delta: create `Application Support/FieldEvidenceData/current.json` as canonical `{"generationID":"<lowercase-uuid>","schemaVersion":1}`, `retired.json` as canonical `{"generationIDs":[...],"schemaVersion":1}`, and the first `generations/<generation-uuid>/model.sqlite`. Absence of the entire data root alone bootstraps; an existing root with a missing or malformed pointer fails closed. The coordinator owns the current container and monotonically increasing UI-generation token; feature code receives its context and never retains a permanent container.
- Exact diagnostics delta: create canonical `Application Support/FieldEvidenceDiagnostics/counters.json` with `schemaVersion=1`; six nonnegative saturating Int64 scalar counters `first_sign_created`, `onboarding_completed`, `paywall_presented`, `recheck_completed`, `report_saved`, and `report_share_sheet_presented`; and the closed `purchase_result` histogram `cancelled`, `failed`, `pending`, `unverified`, and `verified`. Writes use atomic replacement. Unknown or malformed diagnostics reset only this file to the exact zero object with a privacy-safe OSLog fault and never change domain data or pointers.
- Exact startup/maintenance delta: route checks in fixed order `Erase → Restore → current open/validation → finalization → deletion → media → PDF reconciliation`. Later-card operations remain unimplemented. Closed maintenance reasons are `data_pointer_invalid`, `data_generation_missing`, `finalization_inconsistent`, `media_inconsistent`, `restore_inconsistent`, and `erase_inconsistent`. The title is `Local data needs attention`; copy is `The app stopped to avoid changing or losing local records.` It always offers **Retry checks** and **Recovery steps**. Recovery steps show exactly `If Retry cannot recover this device, delete and reinstall the app. This removes all local app data and does not cancel your Apple subscription. A backup stored outside this app can be restored from Welcome after reinstalling.`
- GOLDEN: persist, release, and reopen a fixture Site/Asset through the generation named by `current.json`; its pointer, `retired.json`, model values, and counters reload identically. Startup proves the frozen ordering before feature writes are enabled.
- ALT-1: parameterized malformed-pointer and closed-reason cases open the minimal write-blocking maintenance surface with the exact reinstall/data-loss/subscription/backup fallback. A corrupt diagnostics file resets only diagnostics with private OSLog and leaves domain bytes and generation pointers unchanged.
- Forbidden behavior: sign creation or editing UI; `WorkflowRecord`, `EvidenceFile`, `Issue`, `Packet`, `Report`, or any other model; evaluation ledger; repository/persistence abstraction; restore, erase, finalization, deletion, media, or PDF implementation; raw-file editor; newest-directory guessing; automatic data deletion; generic recovery framework; package, capability, permission, project-file, remote-service, commerce, or report delta.

## Environment and exact selector

- Route / host: Windows authoring → GitHub Actions macOS verification; never run or claim local Windows Xcode/Simulator results.
- Required tool posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration is active; XcodeBuildMCP and an owner-operated Mac are unnecessary.
- Repository / visibility / default / phase: `palatis3/AssetRounds / private / main / phase/s2-persistence-signs`.
- Runner / Xcode / developer dir: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer`.
- Project / scheme / configuration / deployment: `FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `N8 / run_ui_smoke=false`.
- Exact selector: `{"schemaVersion":1,"taskID":"S2.1","tier":"N8","runUISmoke":false,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":0,"totalBudgetSeconds":2400,"unitTestSelectors":["FieldEvidenceAppTests/S2PersistenceLedgerTests"],"uiTestSelectors":[]}`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`.
- Required evidence: nonempty boot/build/unit logs; Build and UnitTests result bundles; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`. UI execution, UI selector, UISmoke result, and screenshot are rejected for this N8 card.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging and one-purpose commits; non-force phase-branch create/push; named `workflow_dispatch` with the exact branch ref and `run_ui_smoke=false`; run observation and artifact download; after accepted S2.1 evidence, the exact HANDOFF-plus-CURRENT_TASK same-phase transition to S2.2. Phase-boundary main integration is not reached until accepted S2.2. Forbidden methods: force-push, merge commit, PR creation/merge, ref deletion or rewrite, repository/settings/secret mutation, signing, TestFlight/App Store upload, deployment, release publication, or S9.2/S9.3 action.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/App/FieldEvidenceAppApp.swift`
- `FieldEvidenceApp/Domain/Models/Site.swift`
- `FieldEvidenceApp/Domain/Models/Asset.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/StoreSessionCoordinator.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift`
- `FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift`
- `FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift`

Test paths:

- `FieldEvidenceAppTests/S2PersistenceLedgerTests.swift`

Standing support exception:

- `Scripts/ci-selection.json`

`docs/execution/HANDOFF.md` is append-only post-green bookkeeping and is not part of the implementation commit. No other path may change.

## Execution

1. Create or resume only `phase/s2-persistence-signs` from P=M, commit the CURRENT_TASK-only authority head A, push/create the phase ref non-force, and run fresh G0. G0 proves A^=M, exact M..A, pins/map/environment, accepted S1 predecessor evidence, selector predecessor state, and no other dirty path.
2. Replace the selector first, implement only the allowed paths, run structural/static checks available on Windows, explicitly stage only task paths, and commit direct-child implementation I.
3. Push the exact phase ref non-force and run the one-at-a-time persistent N8 verification loop. Accept only green exact-head CI with complete checksummed evidence. Hosted variance gets a fresh run ID; diagnosed product or harness failures get one direct-child correction per commit with no numeric ceiling.
4. After green S2.1 implementation evidence, append HANDOFF, hydrate only immediate-next S2.2, and commit exactly the HANDOFF append plus `docs/execution/CURRENT_TASK.md`. Re-fetch before non-force push, prove the remote phase ref still equals the accepted S2.1 verification head, push the transition, and run fresh S2.2 G0. Do not update main during S2.1.

## Definition of done

- Exact green S2.1 N8 evidence with complete artifacts; exact Site/Asset-only schema; canonical first immutable generation and pointers; coordinator context survives release/reopen; exact diagnostics persist and diagnostics-only corruption resets safely; frozen startup order and write-blocking maintenance behavior pass; no sign-creation UI, future model, generic repository, recovery framework, or forbidden path.
- Handoff records all required evidence. The remote phase ref advances through the exact S2.1 transition commit, then work continues only with S2.2.
