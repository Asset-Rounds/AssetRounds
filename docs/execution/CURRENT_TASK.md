# Current Task

## Program and card

- Phase / branch / card / global order: `S5 / phase/s5-work-recheck / S5.2 / 18 of 36`.
- Card heading: `### S5.2 — Resolved or still-visible recheck`.
- Position / boundary / immediate next card: `2 of 4 / phase boundary no / S5.3 only after accepted S5.2 exact-head CI`.
- Program autopilot / phase autopilot / exact S5 span / boundary integration: `enabled through accepted S9.1 / enabled / S5.1,S5.2,S5.3,S5.4 / yes at S5.4 only`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S5 phase-main base: `P=dc28f80c76dcbfb3d78ee79349e9a261c5a2bd1e`; this is the accepted S4 HANDOFF-only phase-close and exact-main verification head.
- Integrated/card base: `M=E=fc3de1772297cdcac9134be3594187e0abc39c24`, the accepted S5.1 implementation; remote `main` remains P.
- Accepted S5.1 evidence: run `31753067635` / job `94622857870`, exact `phase/s5-work-recheck@M`, P12/UI enabled, `5/5` units and `1/1` UI green; artifact `ios-ci-31753067635-1`, ID `9201925316`, size `5206751`, API digest `sha256:182b93e81f83321331fb35095da813a40390e0c36dd71b878f0e31c0a206116a`; all `101/101` manifest payloads matched; terminal screenshot SHA-256 `321C22819A8D47688AB4C3FDD60DB5CA088D674FEB77EDC878E2D60AB85E3E17`.
- Accepted S5.1 environment: `macos26` image `20260728.0273.1`; Xcode 26.6 build `17F113`; iPhone 17 / iOS 26.5 build `23F77`; Simulator UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`.
- Task-start authority A is the direct-child same-phase transition commit observed after it exists at fresh G0; this file deliberately never self-records that future SHA.
- Required `M..A`: exactly one direct-child transition changing only append-only `docs/execution/HANDOFF.md` plus this immediate-next `docs/execution/CURRENT_TASK.md`; remote `phase/s5-work-recheck=A`, remote `main=P`, and no other dirty path at fresh G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S5.2 plan anchors: `## 6. Core workflow and state truth` → `Work and recheck`; `## 7. Free evaluation, subscriptions, and payments` → one newly finalized recheck root consumes one evaluation use while a validated existing draft may complete; `## 9. Smallest reusable architecture` → closed recheck/Issue/Packet/Report/snapshot/evidence/finalization truth; `## 14. Analytics, feedback, and learning` → best-effort lower-bound `report_saved` and `recheck_completed` attempts only after a created result; global execution anchors remain `## 11`, `## 16`, and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / selected card S5.2 only.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Accepted generalized UI exporter: `Scripts/ui-smoke.sh` / `6304A318EE046B6B19F4FDDC43BB143F9B21E8150B9D332E449B87A0182D4CDB`.
- Selector at G0 remains accepted S5.1 compact JSON plus LF, 335 bytes, SHA-256 `74923EB79FFB5DFBC49E54E1074334773A1D9A89C7BFCA503525113200A2920E`; after G0 the first support mutation replaces it with the exact S5.2 object below, 336 bytes, SHA-256 `4323E709BCCC43EA9604A357FBF3B594F1B1093B117D686484E61C9B7172FC8E`.

## Outcome and acceptance

- Outcome: from one uniquely valid `recheck_due` Issue on the current sign, expose `Start recheck`; begin or resume the sign's sole existing draft using the existing frozen time-context/acknowledgement and wide/close capture runner; parent the recheck to the Issue chain's unique latest completed substantive record and link the original Issue explicitly; finalize `Resolved` or `Issue still visible` with only the new recheck's evidence into one recoverable Packet/Report/stable root.
- Recheck record truth: schema 1; original revision with `recordRevisionRootID == id`; same Asset and original Issue; unique mutation; `stage=recheck`; completed state; required nondecreasing started/completed instants; complete frozen time and both acknowledgement groups; exact current sign pack and fixed PDF-template versions; required new canonical `wide_context` and `close_detail` evidence; null work and CNV fields for these two outcomes; optional trimmed note; Packet and evaluation-counted root required.
- Lineage authority: the source Issue must be schema 1, uniquely `recheck_due`, unresolved, same live Asset, and backed by one closed substantive original check/work/recheck chain whose unique terminal record is the recheck parent. Corrections never become substantive parents. Reject missing, forked, cyclic, cross-Asset, cross-Issue, revised-only, draft, malformed, colliding, stale, or nonterminal authority rather than sorting or guessing.
- GOLDEN — `Resolved`: atomically complete the recheck, create exactly one Packet/current Report/stable root and snapshot, retain only new recheck evidence as current evidence while preserving immutable earlier work/check history, set the original Issue to `resolved`, set `resolvedByRecordID` to this recheck ID, and create no new Issue.
- ALT-1 — `Issue still visible`: atomically complete the recheck and same report/root authority, return the same original Issue UUID to `open`, leave `resolvedByRecordID` null, advance `updatedAt`, and create no new Issue UUID. The user may later record work again; this card does not implement that subsequent cycle.
- Evidence/PDF truth: prior check/work photos can appear only as immutable earlier history and can never satisfy the new recheck's required evidence. The existing canonical media, snapshot, journal, renderer, pending/failed recovery, cached ready-PDF, history, evaluation, and report-delivery rules remain authoritative; no alternate finalization or render path is allowed.
- Diagnostics truth: only when finalization returns `createdAuthority=true`, attempt `report_saved` and `recheck_completed` once as independent best-effort lower bounds after domain success. Counter failure never rolls back, changes, retries, or authorizes domain/report/evaluation truth; replay does not increment.
- UI/copy: reuse the existing preflight, capture, outcome review, value receipt, report delivery, and failure/retry surfaces. Add only plan-supplied public wording `Start recheck`, `Resolved`, and `Issue still visible`; preserve existing runner/pack copy and frozen labels. Do not expose `Original resolved, different visible issue` or recheck Could-not-verify in this card.
- UI/accessibility: Issue detail and the reused runner scroll at every Dynamic Type category; required controls remain at least 44×44 points; labels, button traits, logical order, non-color Issue status, validation, capture, review, saving/finalizing/delivery, completion focus, and return navigation are deterministic. The sole UI test starts from persisted work/recheck-due truth, captures new wide/close evidence, chooses `Resolved`, reaches the existing value receipt/report surface, reopens the original Issue as resolved, proves exactly one new report visit/root, and retains one terminal in-app screenshot at Accessibility XXXL.
- Negative family: dirty context; duplicate/colliding Site/Asset/Issue/record/mutation/evidence/Packet/root/Report identities; wrong/nonlive Asset; Issue missing/not recheck_due/already resolved/malformed; invalid opening/work/recheck lineage; fork/cycle/correction-only/cross-authority/stale-parent race; missing/unaccepted time or acknowledgement truth; invalid/old/reused/duplicate evidence; noncanonical JPEG or mismatched path/hash/bytes; unsafe generation/path/symlink/special file; malformed snapshot/payload/intent; storage, promotion, journal, save, render, cleanup, rollback, or diagnostics failure. Every case fails closed or remains exactly recoverable without Issue drift, duplicate root/use, partial report authority, staging/final/journal orphan, counter-driven truth, or touched retained/unowned byte.
- Forbidden behavior: `Original resolved, different visible issue`; recheck Could-not-verify; new Issue creation; implicit original Issue state; using prior photos as current evidence; work mutation; correction authoring; multiple Packet/root creation; evaluation refund; alternate renderer/snapshot/store; entitlement/paywall/commerce; schema/model/project/package/capability/permission changes; deletion/backup/restore/feedback/release; remote/backend/sync/account/upload; notifications; S5.3+ work.

## Environment and exact selector

- Route / repository / refs: Windows authoring → exact GitHub Actions macOS verification; `palatis3/AssetRounds / public / main / phase/s5-work-recheck`; never run or claim Windows Xcode/Simulator results.
- Required posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Runner / Xcode / project: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer / FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S5.2","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S5_2RecheckOutcomeTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S5_2RecheckUITests"]}` plus exactly one LF; 336 UTF-8 bytes, no BOM; SHA-256 `4323E709BCCC43EA9604A357FBF3B594F1B1093B117D686484E61C9B7172FC8E`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, and UISmoke result bundles; terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download. Force-push, merge commit, PR, ref rewrite/delete, main mutation before S5.4 boundary, settings/secrets, signing, TestFlight/App Store, deployment/release, and S9.2/S9.3 are forbidden.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/Domain/Workflow/RecheckOutcomeRule.swift`
- `FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift`
- `FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift`
- `FieldEvidenceApp/Features/Issues/IssueDetailView.swift`
- `FieldEvidenceApp/Features/Signs/SignDetailView.swift`
- `FieldEvidenceApp/Features/Signs/SignsRootView.swift`
- `FieldEvidenceApp/Infrastructure/Finalization/FinalizationRecoveryService.swift`
- `FieldEvidenceApp/Infrastructure/Finalization/FinalizationService.swift`

Test paths:

- `FieldEvidenceAppTests/S5_2RecheckOutcomeTests.swift`
- `FieldEvidenceAppUITests/S5_2RecheckUITests.swift`

Standing selector exception:

- `Scripts/ci-selection.json`

No other implementation, project, model, resource, fixture, script, workflow, authority, or documentation path is allowed during S5.2 implementation. Append-only `docs/execution/HANDOFF.md` remains separately authorized bookkeeping after accepted evidence.

## G0 and transition

- Fresh G0 must prove clean `phase/s5-work-recheck`, `A^=M`, exact HANDOFF-plus-CURRENT_TASK `M..A`, remote phase=A, remote main=P, all pins and accepted S5.1 run/artifact live and exact, the accepted S5.1 selector still byte-exact, and the eight-production/two-test expanded envelope inside the default 10/5 cap.
- After G0, replace only `Scripts/ci-selection.json` with the frozen S5.2 object, then implement exactly this card. Candidate recovery follows the persistent evidence-driven direct-child loop without weakening acceptance or expanding paths.
- After accepted exact-head S5.2 CI, read `KNOWN_BUGS.md`, append HANDOFF, and—only if fresh refs still match—transition with exactly HANDOFF plus immediate-next S5.3 CURRENT_TASK; do not start S5.3 early and do not mutate main.
