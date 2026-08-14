# Current Task

## Program and card

- Phase / branch / card / global order: `S5 / phase/s5-work-recheck / S5.3 / 19 of 36`.
- Card heading: `### S5.3 — Original resolved, different visible issue`.
- Position / boundary / immediate next card: `3 of 4 / phase boundary no / S5.4 only after accepted S5.3 exact-head CI`.
- Program autopilot / phase autopilot / exact S5 span / boundary integration: `enabled through accepted S9.1 / enabled / S5.1,S5.2,S5.3,S5.4 / yes at S5.4 only`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S5 phase-main base: `P=dc28f80c76dcbfb3d78ee79349e9a261c5a2bd1e`; this is the accepted S4 HANDOFF-only phase-close and exact-main verification head.
- Integrated/card base: `M=E=bbc5d7b69ce5107efffcde5032060050b2b3e88c`, the accepted S5.2 implementation; remote `main` remains P.
- Accepted S5.2 evidence: run `31761221175` / job `94647800123`, exact `phase/s5-work-recheck@M`, P12/UI enabled, `5/5` units and `1/1` UI green; artifact `ios-ci-31761221175-1`, ID `9204862667`, size `4971440`, GitHub/raw ZIP digest `sha256:692f2c808c66a3f473f69916483302316f784206ae54f6b0d2b956ecf77b6eae`; all `101/101` manifest payloads matched; terminal screenshot SHA-256 `0C0E337D17C21304248517C3CD000BB409C398A971E2D9789D486376573D308F`.
- Accepted S5.2 environment: `macos26` image `20260728.0273.1`; Xcode 26.6 build `17F113`; iPhone 17 / iOS 26.5 build `23F77`; Simulator UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`.
- Task-start authority A is the direct-child same-phase transition commit observed after it exists at fresh G0; this file deliberately never self-records that future SHA.
- Required `M..A`: exactly one direct-child transition changing only append-only `docs/execution/HANDOFF.md` plus this immediate-next `docs/execution/CURRENT_TASK.md`; remote `phase/s5-work-recheck=A`, remote `main=P`, and no other dirty path at fresh G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S5.3 plan anchors: `## 6. Core workflow and state truth` → `Work and recheck` plus the closed WorkflowRecord/Issue lineage and final-choice table; `## 7. Free evaluation, subscriptions, and payments` → one newly finalized recheck root consumes one evaluation use while an existing validated draft may complete; `## 9. Smallest reusable architecture` → closed recheck/Issue/Packet/Report/snapshot/evidence/finalization truth; `## 14. Analytics, feedback, and learning` → best-effort lower-bound `report_saved` and `recheck_completed` attempts only after a created result; global execution anchors remain `## 11`, `## 16`, and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / selected card S5.3 only.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Accepted generalized UI exporter: `Scripts/ui-smoke.sh` / `6304A318EE046B6B19F4FDDC43BB143F9B21E8150B9D332E449B87A0182D4CDB`.
- Selector at G0 remains accepted S5.2 compact JSON plus LF, 336 bytes, SHA-256 `4323E709BCCC43EA9604A357FBF3B594F1B1093B117D686484E61C9B7172FC8E`; after G0 the first support mutation replaces it with the exact S5.3 object below, 343 bytes, SHA-256 `F105470B001D4FDF9505913F3CB71B4E6E4A43482FB8B3B8B4ADC56E50A12F35`.

## Outcome and acceptance

- Outcome: extend the existing S5.2 recheck outcome flow with the explicit choice `Original resolved, different visible issue`; require one newly selected closed-registry issue-label key and exact display snapshot; complete the same recheck draft against its uniquely valid original `recheck_due` Issue; atomically resolve that original Issue and open exactly one new Issue UUID while creating the same single recoverable Packet/Report/stable root.
- Recheck record truth: schema 1; original revision with `recordRevisionRootID == id`; same Asset and original Issue link; unique mutation; `stage=recheck`; completed state; required nondecreasing started/completed instants; complete frozen time and both acknowledgement groups; exact current sign pack and fixed PDF-template versions; required new canonical `wide_context` and `close_detail` evidence; `outcomeKey=original_resolved_different_issue`; null work and CNV fields; optional trimmed note; Packet and evaluation-counted root required.
- Source authority: the original Issue must be schema 1, uniquely `recheck_due`, unresolved, on the same live Asset, and backed by one closed substantive original check/work/recheck chain whose unique terminal record is the recheck parent. Corrections never become substantive parents. Reject missing, forked, cyclic, cross-Asset, cross-Issue, revised-only, draft, malformed, colliding, stale, or nonterminal authority rather than sorting or guessing.
- New-Issue authority: require one closed `IlluminatedSignPack@1` issue-label key and its exact display snapshot plus one fresh noncolliding Issue UUID. The category key may equal the original Issue's key, but the Issue lineage and UUID are new. The new Issue is schema 1, same Asset, `openedByRecordID` equal to this completed recheck, `status=open`, `resolvedByRecordID=nil`, and has deterministic immutable creation/update instants supplied once and replayed exactly.
- GOLDEN: in one recoverable finalization transaction complete the recheck, set the original Issue to `resolved` with `resolvedByRecordID` equal to this recheck, insert exactly one new open Issue, and create exactly one Packet/current Report/stable root/snapshot. The snapshot freezes both post-state Issues deterministically, retains only this recheck's new evidence as current evidence, and preserves prior check/work/recheck evidence only as immutable earlier history.
- ALT-1: an injected transaction, promotion, journal, model-save, renderer, or diagnostics failure never leaves only one side of the Issue transition. Before durable domain commit, restore the draft and original Issue and remove the new Issue/Packet/Report/root plus exact-owned staged/final/journal bytes; after durable commit, retain one recoverable complete domain authority. Diagnostics failure never rolls back domain truth.
- Atomic/replay truth: the finalization plan, intent payload, database classification, recovery apply/rollback, and replay comparison carry both the original Issue transition and the new Issue insertion. Absent means draft + exact original-before + no new Issue/Packet/Report; matching means completed record + exact original-after + exact new Issue + exact Packet/Report. Reject every partial, duplicate, colliding, or mismatched combination; same-identifier replay returns the existing result and never inserts another Issue or root.
- Evidence/PDF truth: prior photos can appear only as immutable earlier history and can never satisfy the new recheck's required evidence. The existing canonical media, snapshot, descriptor-anchored journal, renderer, pending/failed recovery, cached ready-PDF, history, evaluation, and report-delivery rules remain authoritative; no alternate finalization or render path is allowed.
- Diagnostics truth: only when finalization returns `createdAuthority=true`, attempt `report_saved` and `recheck_completed` once as independent best-effort lower bounds after domain success. Counter failure never rolls back, changes, retries, or authorizes Issue/domain/report/evaluation truth; replay does not increment.
- UI/copy: reuse the existing preflight, capture, outcome review, closed issue-label picker, value receipt, report delivery, and failure/retry surfaces. Add only plan-supplied public wording `Original resolved, different visible issue`; use exact existing pack issue-label display copy; do not invent another outcome, new issue label, success claim, or implicit original state.
- UI/accessibility: the reused runner and outcome/review screens scroll at every Dynamic Type category; required controls remain at least 44×44 points; labels, button/selection traits, logical order, closed-label validation, capture, review, saving/finalizing/delivery, completion focus, and return navigation are deterministic. The sole UI test starts from persisted work/recheck-due truth, captures new wide/close evidence, chooses `Original resolved, different visible issue`, selects one exact pack label, reaches the existing receipt/report surface, reopens the original Issue as resolved and the new Issue as open, proves exactly one new report visit/root, and retains one terminal in-app screenshot at Accessibility XXXL.
- Negative family: dirty context; duplicate/colliding Site/Asset/original Issue/new Issue/record/mutation/evidence/Packet/root/Report identities; unknown or mismatched label key/display; wrong/nonlive Asset; original Issue missing/not recheck_due/already resolved/malformed; invalid opening/work/recheck lineage; fork/cycle/correction-only/cross-authority/stale-parent race; missing/unaccepted time or acknowledgement truth; invalid/old/reused/duplicate evidence; noncanonical JPEG or mismatched path/hash/bytes; partial original transition/new insertion state; multiple inserted Issues; malformed snapshot/payload/intent; unsafe generation/path/symlink/special file; storage, promotion, journal, save, render, cleanup, rollback, or diagnostics failure. Every case fails closed or remains exactly recoverable without Issue drift, duplicate Issue/root/use, partial report authority, staging/final/journal orphan, counter-driven truth, or touched retained/unowned byte.
- Forbidden behavior: leaving original Issue state implicit; zero or multiple new Issues; changing the original label; using an unknown/free-form label; resolving or linking the new Issue; `Resolved`, `Issue still visible`, or recheck Could-not-verify implementation changes; using prior photos as current evidence; work mutation; correction authoring; multiple Packet/root creation; evaluation refund; alternate renderer/snapshot/store; entitlement/paywall/commerce; schema/model/project/package/capability/permission changes; deletion/backup/restore/feedback/release; remote/backend/sync/account/upload; notifications; S5.4+ work.

## Environment and exact selector

- Route / repository / refs: Windows authoring → exact GitHub Actions macOS verification; `palatis3/AssetRounds / public / main / phase/s5-work-recheck`; never run or claim Windows Xcode/Simulator results.
- Required posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Runner / Xcode / project: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer / FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S5.3","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S5_3DifferentIssueTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S5_3DifferentIssueUITests"]}` plus exactly one LF; 343 UTF-8 bytes, no BOM; SHA-256 `F105470B001D4FDF9505913F3CB71B4E6E4A43482FB8B3B8B4ADC56E50A12F35`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, and UISmoke result bundles; terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download. Force-push, merge commit, PR, ref rewrite/delete, main mutation before S5.4 boundary, settings/secrets, signing, TestFlight/App Store, deployment/release, and S9.2/S9.3 are forbidden.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/Domain/Workflow/DifferentIssueOutcomeRule.swift`
- `FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift`
- `FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift`
- `FieldEvidenceApp/Features/Issues/WorkCoordinator.swift`
- `FieldEvidenceApp/Features/Signs/SignsRootView.swift`
- `FieldEvidenceApp/Infrastructure/Finalization/FinalizationRecoveryService.swift`
- `FieldEvidenceApp/Infrastructure/Finalization/FinalizationService.swift`

Test paths:

- `FieldEvidenceAppTests/S5_3DifferentIssueTests.swift`
- `FieldEvidenceAppUITests/S5_3DifferentIssueUITests.swift`

Standing selector exception:

- `Scripts/ci-selection.json`

No other implementation, project, model, resource, fixture, script, workflow, authority, or documentation path is allowed during S5.3 implementation. Append-only `docs/execution/HANDOFF.md` remains separately authorized bookkeeping after accepted evidence.

## G0 and transition

- Fresh G0 must prove clean `phase/s5-work-recheck`, `A^=M`, exact HANDOFF-plus-CURRENT_TASK `M..A`, remote phase=A, remote main=P, all pins and accepted S5.2 run/artifact live and exact, the accepted S5.2 selector still byte-exact, and the seven-production/two-test expanded envelope inside the default 10/5 cap.
- After G0, replace only `Scripts/ci-selection.json` with the frozen S5.3 object, then implement exactly this card. Candidate recovery follows the persistent evidence-driven direct-child loop without weakening acceptance or expanding paths.
- After accepted exact-head S5.3 CI, read `KNOWN_BUGS.md`, append HANDOFF, and—only if fresh refs still match—transition with exactly HANDOFF plus immediate-next S5.4 CURRENT_TASK; do not start S5.4 early and do not mutate main.
