# Current Task

## Program and card

- Phase / branch / card / global order: `S3 / phase/s3-check-runner / S3.1 / 5 of 36`.
- Card heading: `### S3.1 — Frozen workflow schema, preflight, and one active draft`.
- Position / boundary / immediate next card: `1 of 7 / phase boundary no / S3.2`.
- Program autopilot / phase autopilot / exact S3 span / boundary integration: `enabled through accepted S9.1 / enabled / S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7 / yes at S3.7 only`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Accepted S2 phase-close and immutable S3 phase-main/card base: `P=M=C=7d135aaddd0bdc50168552b0610f04adc1703506`.
- Accepted S2 product/verification lineage: S2.2 product `E=89c60edc39f3f6cbb94497629c829ea15c5d3184`; nonproduct verification `K1=404bc29ef784f96679b450585b9a02a484999334`; HANDOFF-only phase close `C`, a direct child of K1 changing exactly `docs/execution/HANDOFF.md`.
- Predecessor phase evidence: run `31632629616`, job `94234979816`, succeeded at exact `phase/s2-persistence-signs@C` with P12/UI enabled; artifact `ios-ci-31632629616-1`, ID `9156065563`, API digest `sha256:59bfda772b230536acedfdcf271f9b6a90c4e0d9d03178f50fa500314f616066`; `SHA256SUMS.txt` SHA-256 `9C8D6FF4435CC4AF6B91B7B17540C152AC76DC3A1E70E5947575C95EAF4DEFB7`; all 101 payloads independently matched; accepted `ui-final.png` SHA-256 `4EA9FE22BC7EFC94D2D7082A80E68C70202E698B408C94545303F2AA23B5D115`.
- Predecessor exact-main evidence: run `31633843776`, job `94239090824`, succeeded at exact `main@C` with P12/UI enabled; artifact `ios-ci-31633843776-1`, ID `9156429863`, API digest `sha256:65448f34574d0cc9244687b77972c70a59bb3ebd573b8293000cc4473ba153f5`; `SHA256SUMS.txt` SHA-256 `C9F9F1A87FD34C4B51F8DC552EDEAA71120C8B507B6F37847EE627B562FA1E68`; all 101 payloads independently matched; accepted `ui-final.png` SHA-256 `0CD2DE9064D5B5A9338224D8FEFA6E0A7EF342BAF72B0C214610EE91FF7ECAF2`. Runner `macos26` image `20260728.0273.1`, Xcode 26.6 `17F113`, iPhone 17/iOS 26.5, UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`; setup `16/300` s, readiness `104/900` s, setup+artifact `17/300` s, total `540/3300` s.
- Task-start authority head `A`: `OBSERVE AT POST-COMMIT G0; never self-record its SHA here`.
- Required `M..A`: one direct-child authority commit changing exactly `docs/execution/CURRENT_TASK.md`.
- Construction state: remote `main` and `phase/s2-persistence-signs` equal C; remote `phase/s3-check-runner` is absent. Create only local `phase/s3-check-runner` from C, commit this CURRENT_TASK-only A, non-force create the remote phase ref, and require clean index/worktree/untracked state at fresh G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S3.1 plan anchors: `## 5. Navigation and onboarding` (`Ready for night check`); `## 6. Core workflow and state truth`; `## 9. Smallest reusable architecture` (`Persistent models`, issue parent chain, time context, exact pack acknowledgements). Global execution anchors remain `## 11. Build slices and release gates`, `## 16. Owner preparation checklist`, and `## 18. Codex execution authority`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79`.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Accepted generalized UI exporter baseline: `Scripts/ui-smoke.sh` / `6304A318EE046B6B19F4FDDC43BB143F9B21E8150B9D332E449B87A0182D4CDB`.
- Selector schema path: `Scripts/ci-selection.json`; at G0 it may still equal accepted S2.2 LF SHA-256 `C5EAA9DD13E1262BF54187604C4E72795F8D491DE109A544E6E21C04222FBAA5`. Its first support mutation must replace it with the exact S3.1 object below, LF SHA-256 `F8C9C17EB06713BA6299F3869DC444D53E18AD41C5172CBB9EDFC961AE65237D`.

## Outcome and acceptance

- Outcome: extend the persistent schema from Site/Asset to exactly the seven frozen V4 models by adding WorkflowRecord, EvidenceFile, Issue, Packet, and Report; add closed draft-era workflow contracts, exact time-context rule, Ready-for-night-check preflight, and stage-aware sole-draft `beginOrResumeDraft(assetID:requestedStage:issueID:)`. Capture and finalization remain unavailable.
- Exact schema delta: every new model/property/nullability/raw domain is exactly the plan. WorkflowRecord carries the complete frozen property set and invariants; EvidenceFile, Issue, Packet, and Report carry their complete exact fields; unique stable IDs/finalization mutation/stable packet root are enforced as specified. Schema remains version 1 and the model set freezes at exactly seven; no Observation or hidden answer/form model exists.
- Closed contracts: raw values are only revision `original|clerical_correction`, stage `check|work|recheck`, state `draft|completed`, draft step `wide|close|outcome|review`, issue state `open|recheck_due|resolved`, and PDF state `pending|ready|failed`, plus bounded request/result/error types. Do not add `ReportSnapshotV1`, finalization/media DTOs, or a generic repository/service/command bus.
- Time rule: freeze one supplied observed instant using the confirmed Site IANA time zone; resolve the offset at that instant; format Gregorian/en_US_POSIX `YYYY-MM-DD` and `HH:mm:ss`; never infer or recompute from the device/current zone.
- Sole-draft rule: every requested route first fetches the Asset's sole existing draft and returns it unchanged regardless of the newly requested stage/Issue. More than one draft fails closed. Only with no draft may check validate nil Issue/parent; work validate an open same-Asset Issue and latest completed substantive parent; recheck validate a recheck-due same-Asset Issue and latest completed substantive parent.
- Preflight UI: activate Sign detail **Start Check**. Ready-for-night-check asks for exact-IANA time-zone input and explicit confirmation only when the Site has no confirmed zone. Always show the exact pack acknowledgements, initially unchecked and in order: `It is dark enough to observe the sign's visible illumination.` then `I am in a safe, authorized position to take these photos.` Both plus a valid confirmed zone are required before **Begin check**. Secondary is **Cancel — no check started**.
- Begin sequence: only after **Begin check**, first persist and verify a newly confirmed Site zone in its own save; only after that succeeds, create and save exactly one original/check/draft/wide WorkflowRecord. The draft has `id==recordRevisionRootID`; nil packet/issue/parent/revision/evidence-source/completion/outcome/CNV/work/note/finalization fields; exact supplied observed UTC/zone/offset/local values; both accepted acknowledgement key/copy/version groups; Asset pack versions; and `field.evidence.pdf.worklight.v1/1`. Create no EvidenceFile, Issue, Packet, or Report. If the later draft save fails, the confirmed zone remains a valid user-confirmed Site fact while no partial draft exists.
- Post-begin UI: show only explicit `Capture is unavailable until S3.2.` and preserve/resume the same draft. There is no photo import, camera, outcome, review, completion, evaluation count, report, PDF, or diagnostics increment in S3.1.
- GOLDEN: under the seven-model schema reopen the existing S2 Site/Asset unchanged; begin with a fixed instant and confirmed IANA zone; release/reopen exactly one draft with every frozen field exact; assert zero rows for the other four new models; every requested check/work/recheck route first returns the identical existing draft; in no-draft state, unit tests prove exact stage/Issue/latest-parent validation. UI proves saved sign → active Start Check → nil-zone confirmation → two acknowledgements → Begin → S3.2-unavailable state → termination/relaunch → same single draft.
- ALT-1: Cancel before Begin writes no WorkflowRecord and does not persist a merely entered/confirmed zone; return to exact sign detail and visibly present `No check was started.` Relaunch remains draft-free.
- Forbidden behavior: evidence bundle/media normalization/staging/import; camera/PhotosPicker/permission; capture/Retake/Use Photo; outcome/review/CNV; finalization intent/snapshot encoder/Packet/Report/Issue creation or transitions; resume-step recovery matrix; storage/fault framework; work/recheck UI; evaluation/access/paywall/StoreKit; repository/service/command bus/generic workflow/form engine; package/project/capability/permission/remote delta; any model beyond the exact five or later schema change.

## Environment and exact selector

- Route / host: Windows authoring → GitHub Actions macOS verification; never run or claim local Windows Xcode/Simulator results.
- Required tool posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration is active; XcodeBuildMCP and an owner-operated Mac are unnecessary.
- Repository / visibility / default / phase: `palatis3/AssetRounds / public / main / phase/s3-check-runner`.
- Runner / Xcode / developer dir: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer`.
- Project / scheme / configuration / deployment: `FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S3.1","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S3_1DraftSchemaTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S3_1PreflightUITests"]}`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, and UISmoke result bundles; terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging and one-purpose commits; non-force phase-branch create/push; named `workflow_dispatch` with exact branch ref and `run_ui_smoke=true`; run observation and artifact download; after accepted S3.1 evidence, HANDOFF plus immediate-next S3.2 CURRENT_TASK transition only. Forbidden methods: force-push, merge commit, main mutation before S3.7 boundary, PR creation/merge, ref deletion/rewrite, repository/settings/secret mutation, signing, TestFlight/App Store upload, deployment, release publication, or S9.2/S9.3 action.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/Domain/Models/WorkflowModels.swift`
- `FieldEvidenceApp/Domain/Workflow/WorkflowContracts.swift`
- `FieldEvidenceApp/Domain/Workflow/TimeContextRule.swift`
- `FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift`
- `FieldEvidenceApp/Features/CheckRunner/PreflightView.swift`
- `FieldEvidenceApp/Features/Signs/SignsRootView.swift`
- `FieldEvidenceApp/Features/Signs/SignDetailView.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift`

Test paths:

- `FieldEvidenceAppTests/S3_1DraftSchemaTests.swift`
- `FieldEvidenceAppUITests/S3_1PreflightUITests.swift`

Standing support exception:

- `Scripts/ci-selection.json`

`docs/execution/HANDOFF.md` is append-only post-green bookkeeping and is not part of the implementation commit. No other path may change.

## Execution

1. Commit exactly this hydrated CURRENT_TASK as A on local `phase/s3-check-runner` created from M=C; non-force create only the matching remote phase ref after re-proving remote main=C, remote S2=C, and remote S3 absent.
2. Fresh G0 proves `A^=M`; `M..A` is exactly one CURRENT_TASK-only commit; remote main/S2 remain C; remote S3=A; carried map/pins/public repository/environment/tool/method posture are exact; selector remains the accepted S2.2 object; and no other path is dirty.
3. Replace the selector first, implement only the allowed paths, run structural/static checks available on Windows, explicitly stage only task paths, and commit direct-child implementation I.
4. Push the exact phase ref non-force and run the one-at-a-time persistent P12 verification loop. Accept only green exact-head CI with complete checksum-verified evidence; diagnose each terminal product or harness failure and apply only one smallest direct-child correction before verifying again.
5. After accepted S3.1 evidence, append HANDOFF and, only if remote phase still equals the accepted verification head, transition same-phase by committing/pushing exactly that append plus immediate-next S3.2 CURRENT_TASK. Run fresh S3.2 G0. Do not mutate main.

## Definition of done

- Exact green S3.1 implementation evidence: seven-model schema frozen; existing S2 data reopens; one exact preflight draft persists/resumes with frozen instant/zone/offset/local values and two exact acknowledgements; stage-aware existing-draft precedence and no-draft lineage validation pass; pre-begin Cancel writes nothing and reports `No check was started.`; capture/finalization and every forbidden future behavior remain absent.
- Handoff records all required evidence. Remote S3 phase equals the accepted verification head, then continue only with S3.2.
