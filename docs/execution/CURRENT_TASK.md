# Current Task

## Program and card

- Phase / branch / card / global order: `S5 / phase/s5-work-recheck / S5.4 / 20 of 36`.
- Card heading: `### S5.4 — Recheck Could-not-verify`.
- Position / boundary / immediate next card: `4 of 4 / phase boundary yes / phase-end fast-forward/exact-main CI; then S6.1 only`.
- Program autopilot / phase autopilot / exact S5 span / boundary integration: `enabled through accepted S9.1 / enabled / S5.1,S5.2,S5.3,S5.4 / yes at S5.4 only`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S5 phase-main base: `P=dc28f80c76dcbfb3d78ee79349e9a261c5a2bd1e`; this is the accepted S4 HANDOFF-only phase-close and exact-main verification head.
- Integrated/card base: `M=E=3bc7f42f84bb36dd6d306168fc894faf9976eb3e`, the accepted S5.3 implementation; remote `main` remains P.
- Accepted S5.3 evidence: run `31764299215` / job `94656885520`, exact `phase/s5-work-recheck@M`, P12/UI enabled, `7/7` units and `1/1` UI green; artifact `ios-ci-31764299215-1`, ID `9205908925`, size `4607931`, GitHub/raw ZIP digest `sha256:00076d7f91528505541bfc006fa10ce7aa67763e8c87e89a52581918abcf93c5`; all `105/105` manifest payloads matched; terminal screenshot SHA-256 `7077815A0AA5C655D8776CB8D1518D99290753C50BFDEF017390010D23377201`.
- Accepted S5.3 environment: `macos26` image `20260728.0273.1`; Xcode 26.6 build `17F113`; iPhone 17 / iOS 26.5 build `23F77`; Simulator UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`.
- Task-start authority A is the direct-child same-phase transition commit observed after it exists at fresh G0; this file deliberately never self-records that future SHA.
- Required `M..A`: exactly one direct-child transition changing only append-only `docs/execution/HANDOFF.md` plus this immediate-next `docs/execution/CURRENT_TASK.md`; remote `phase/s5-work-recheck=A`, remote `main=P`, and no other dirty path at fresh G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S5.4 plan anchors: `## 6. Core workflow and state truth` → post-draft `Cannot complete`, exact CNV registry, `Work and recheck`, closed WorkflowRecord/Issue lineage, final-choice table, and recheck CNV invariant; `## 7. Free evaluation, subscriptions, and payments` → one newly finalized recheck root consumes one evaluation use while an existing validated draft may complete; `## 9. Smallest reusable architecture` → closed CNV/recheck/Issue/Packet/Report/snapshot/evidence/finalization truth; `## 14. Analytics, feedback, and learning` → best-effort lower-bound `report_saved` and `recheck_completed` attempts only after a created result; global execution anchors remain `## 11`, `## 16`, and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / selected card S5.4 only.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Accepted generalized UI exporter: `Scripts/ui-smoke.sh` / `6304A318EE046B6B19F4FDDC43BB143F9B21E8150B9D332E449B87A0182D4CDB`.
- Selector at G0 remains accepted S5.3 compact JSON plus LF, 343 bytes, SHA-256 `F105470B001D4FDF9505913F3CB71B4E6E4A43482FB8B3B8B4ADC56E50A12F35`; after G0 the first support mutation replaces it with the exact S5.4 object below, 335 bytes, SHA-256 `26B050C4BDE1BFDF9CC5324A6FE63DFE16AD36AEF215052FDA9480E3FB142A64`.

## Outcome and acceptance

- Outcome: extend the existing post-draft `Cannot complete` flow to a recheck whose original Issue is uniquely valid and `recheck_due`; accept zero or partial new evidence, finalize one honest incomplete recheck/Packet/Report/stable root, preserve the original Issue authority exactly in `recheck_due`, and then attempt both lower-bound diagnostics.
- Recheck record truth: schema 1; original revision with `recordRevisionRootID == id`; same Asset and original Issue link; unique mutation; `stage=recheck`; completed state; required nondecreasing started/completed instants; complete frozen time and both acknowledgement groups; exact current sign pack and fixed PDF-template versions; zero or one each newly accepted canonical `wide_context` and `close_detail` evidence; `outcomeKey=could_not_verify`; exact closed-registry reason key/display/version; null work fields; optional trimmed note; Packet and evaluation-counted root required.
- Source authority: the original Issue must be schema 1, uniquely `recheck_due`, unresolved, on the same live Asset, and backed by one closed substantive original check/work/recheck chain whose unique terminal record is the recheck parent. Corrections never become substantive parents. Reject missing, forked, cyclic, cross-Asset, cross-Issue, revised-only, draft, malformed, stale, or nonterminal authority rather than sorting or guessing.
- CNV registry: persist exactly one key/display from `cnv.reason.en-US.v1`: `conditions_changed` → `Conditions changed`; `access_lost` → `I lost safe access`; `unsafe_to_continue` → `It became unsafe to continue`; `required_view_obstructed` → `Required view is blocked`; `capture_unavailable` → `Camera or photo capture is unavailable`; `other` → `Another reason`. Unknown, mismatched, empty, or free-form reason authority fails closed.
- GOLDEN: after one newly accepted evidence item, selecting `conditions_changed` atomically completes the recheck and creates exactly one incomplete Packet/current Report/stable root/snapshot while the original Issue payload remains byte-for-byte unchanged and `recheck_due`; no Issue is opened, resolved, relabeled, or inserted.
- ALT-1: with zero new evidence, selecting `unsafe_to_continue` creates the same single incomplete authority and has the identical no-change Issue effect. Each missing current purpose renders `Not captured — Could not verify`; prior history is labeled history and never substitutes for current evidence.
- Atomic/replay truth: the finalization plan, intent payload, database classification, recovery apply/rollback, and replay comparison explicitly carry and validate the linked original Issue as exact identical before/after authority with no Issue insertion. Absent means draft + exact original Issue + no Packet/Report; matching means completed CNV record + exact unchanged original Issue + exact Packet/Report. Reject every partial, duplicate, colliding, stale, or mismatched combination; same-identifier replay returns the existing result and never creates another root/use or mutates the Issue.
- Failure/recovery truth: before durable domain commit, any transaction, promotion, journal, model-save, renderer, or cleanup failure restores the draft, exact original Issue, and exact-owned bytes and removes Packet/Report/root authority; after durable commit, retain one recoverable completed authority. Pending/failed journal recovery applies or rolls back only the exact absent/matching state and never opens/resolves/inserts an Issue, refunds evaluation, or touches retained/unowned bytes.
- Evidence/PDF truth: zero/partial current evidence is intentional for CNV. Any accepted new evidence remains attached; prior photos can appear only as immutable earlier history. Snapshot, renderer, PDF, cached ready-PDF, history, evaluation, and report-delivery rules remain authoritative; no history substitution, false pass language, alternate finalization, or alternate render path is allowed.
- Diagnostics truth: only when finalization returns `createdAuthority=true`, attempt `report_saved` and `recheck_completed` once as independent best-effort lower bounds after domain success. Counter failure never rolls back, changes, retries, or authorizes Issue/domain/report/evaluation truth; replay does not increment.
- UI/copy: reuse the existing recheck preflight, capture, `Cannot complete`, bounded reason/note, review, value receipt, report delivery, and failure/retry surfaces. Use exact plan-supplied `Could not verify` and CNV registry copy; never claim resolved, open, pass, fixed, or verified.
- UI/accessibility: the reused runner and CNV/review screens scroll at every Dynamic Type category; required controls remain at least 44×44 points; labels, button/selection traits, logical order, reason validation, saving/finalizing/delivery, completion focus, and return navigation are deterministic. The sole UI test starts from persisted original Issue `recheck_due` truth, enters one recheck, retains partial evidence, chooses `Cannot complete` → `Conditions changed`, reaches the existing receipt/report surface, returns to the exact original Issue still `recheck_due`, proves exactly one new report visit/root and no new Issue, and retains one terminal in-app screenshot at Accessibility XXXL.
- Negative family: dirty context; duplicate/colliding Site/Asset/Issue/record/mutation/evidence/Packet/root/Report identities; wrong/nonlive Asset; original Issue missing/not recheck_due/already resolved/malformed; invalid opening/work/recheck lineage; fork/cycle/correction-only/cross-authority/stale-parent race; missing/unaccepted time or acknowledgement truth; unknown/mismatched CNV key/display/version; invalid/reused/duplicate evidence; noncanonical JPEG or mismatched path/hash/bytes; partial record/report state; any Issue drift/insertion; malformed snapshot/payload/intent; unsafe generation/path/symlink/special file; storage, promotion, journal, save, render, cleanup, rollback, or diagnostics failure. Every case fails closed or remains exactly recoverable without Issue drift, duplicate root/use, partial report authority, staging/final/journal orphan, counter-driven truth, or touched retained/unowned byte.
- Forbidden behavior: changing the original Issue payload; opening, resolving, relabeling, or inserting any Issue; treating CNV as pass/fixed/verified; requiring both photos or substituting prior photos as current evidence; `Resolved`, `Issue still visible`, or `Original resolved, different visible issue` implementation changes; work mutation; correction authoring; multiple Packet/root creation; evaluation refund; alternate renderer/snapshot/store; entitlement/paywall/commerce; schema/model/project/package/capability/permission changes; deletion/backup/restore/feedback/release; remote/backend/sync/account/upload; notifications; S6.1+ work.

## Environment and exact selector

- Route / repository / refs: Windows authoring → exact GitHub Actions macOS verification; `palatis3/AssetRounds / public / main / phase/s5-work-recheck`; never run or claim Windows Xcode/Simulator results.
- Required posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Runner / Xcode / project: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer / FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S5.4","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S5_4RecheckCNVTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S5_4RecheckCNVUITests"]}` plus exactly one LF; 335 UTF-8 bytes, no BOM; SHA-256 `26B050C4BDE1BFDF9CC5324A6FE63DFE16AD36AEF215052FDA9480E3FB142A64`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, and UISmoke result bundles; terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download. Force-push, merge commit, PR, ref rewrite/delete, main mutation before the accepted S5.4 boundary sequence, settings/secrets, signing, TestFlight/App Store, deployment/release, and S9.2/S9.3 are forbidden.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/Domain/Workflow/RecheckOutcomeRule.swift`
- `FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift`
- `FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift`
- `FieldEvidenceApp/Features/Issues/WorkCoordinator.swift`
- `FieldEvidenceApp/Infrastructure/Finalization/FinalizationRecoveryService.swift`
- `FieldEvidenceApp/Infrastructure/Finalization/FinalizationService.swift`

Test paths:

- `FieldEvidenceAppTests/S5_4RecheckCNVTests.swift`
- `FieldEvidenceAppUITests/S5_4RecheckCNVUITests.swift`

Standing selector exception:

- `Scripts/ci-selection.json`

No other implementation, project, model, resource, fixture, script, workflow, authority, or documentation path is allowed during S5.4 implementation. Append-only `docs/execution/HANDOFF.md` remains separately authorized bookkeeping after accepted evidence.

## G0 and transition

- Fresh G0 must prove clean `phase/s5-work-recheck`, `A^=M`, exact HANDOFF-plus-CURRENT_TASK `M..A`, remote phase=A, remote main=P, all pins and accepted S5.3 run/artifact live and exact, the accepted S5.3 selector still byte-exact, and the six-production/two-test expanded envelope inside the default 10/5 cap.
- After G0, replace only `Scripts/ci-selection.json` with the frozen S5.4 object, then implement exactly this card. Candidate recovery follows the persistent evidence-driven direct-child loop without weakening acceptance or expanding paths.
- After accepted exact-head S5.4 CI, read `KNOWN_BUGS.md`, append the immutable phase/card HANDOFF, commit the HANDOFF-only phase-close C, and—only if fresh refs still match—fast-forward the phase branch and then `main` non-force to the exact accepted verification head, accepting exact-head phase and exact-main UI-enabled CI in order. Reprove both remote refs at that head before creating `phase/s6-data-rights` from green `main` and hydrating S6.1 only; never start S6.1 early or merge/force/rewrite a ref.
