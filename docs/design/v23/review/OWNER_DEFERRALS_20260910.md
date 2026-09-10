# Owner testing deferrals and expansion pause — 2026-09-10

## Current instruction and precedence

The owner directed this task to save the policy changes and then pause until further instruction after the separate S10.6 task. This record governs the V23 review branch prospectively; it does not rewrite accepted S10.4 evidence, the frozen V23 package, historical receipts, or the active S10.6 candidate.

The current update changes only this file, `AGENTS.md`, and `docs/design/v23/review/CURRENT_REVIEW.md` on `codex/v23-premerge-review-20260905`. Product implementation, diagnostic dispatch, source integration, branch deletion and release operations are not part of this update.

### Owner's source messages

The following messages were supplied directly by the owner in this task on 2026-09-10, in order. This transcription records the instruction, not physical or native acceptance evidence.

> I deferred it for now. 10.6 is working now as we speak. and 10.4 min oS will be deferred indef. until future, once app is in the app store.

> Okay, 10.6 is almost done. Just wait until further instruction. Change policy to allow min os to be deferred indef.

> also 10.5 can be deferred because I cannot test app yet. I rather test app fully with expansion involved.

> So lets fix those policy changes and whatever else is needed and then pause goal. I will come back when done when 10.6 is finished.

## Minimum-OS verification: indefinitely deferred

- All seven S10.4 minimum-runtime full profiles and the separate minimum core smoke remain **DEFERRED indefinitely**. There is no due date, retry count, scheduled follow-up or automatic resumption.
- Only an explicit future owner instruction may reactivate that verification. S10.6 completion or App Store availability does not reactivate it. The owner's reference to reconsidering it after the app is in the App Store is future context, not an automatic trigger or a promise to perform the work.
- Preserve the complete fourteen-profile catalog, its 938 visual slots and 84 accessibility rows. The accepted current-runtime scope remains seven profiles, 469 visual cells and 42 accessibility rows; the minimum-runtime 469 cells and 42 rows remain deferred with no PASS, NOT_APPLICABLE, native success or minimum-runtime support claim.
- Preserve the iOS 18.0 deployment target, all original failures/artifacts, current-runtime assertions and accepted S10.4 E/K/C history. This timing clarification does not hide a known defect affecting retained coverage and does not authorize minimum-runtime CI.

## S10.5 physical testing: deferred to the combined app

- S10.5 remains **DEFERRED**, because the owner cannot test the app yet and wants to test the finalized app with the expansion included.
- Owner physical testing is to be revisited only when an expansion-inclusive build is actually available for that testing and the owner supplies further instruction. Do not require the owner to test the current unexpanded app merely to clear this deferral, or automatically request testing when S10.6 repository preparation finishes.
- Deferral is not completion, a PhysicalExperience PASS, an installation record, an E/K/C receipt, or a waiver of the genuine physical evidence required for final release acceptance. Testing of the eventual combined build must identify that actual build/head; historical unexpanded-app evidence cannot be relabeled as combined-app proof.
- Owner-only signing, distribution, credentials, TestFlight/App Store operations, legal assertions and submission remain outside this task. Do not fabricate device, operator, installation, physical, legal or release facts.

## S10.6 ownership and release boundaries

The separate task **Resume S10.4 verification** currently owns S10.6 preparation in `C:\AssetRounds`, including CURRENT_TASK, the active plan/runbook/contract/activation pins, HANDOFF and the S10.6 evidence/metadata envelope. It confirmed candidate `df52d7517806192b8ccff46923d1add1680ec75f` is committed/pushed and its ordinary GitHub F25 run was dispatched. That is a candidate observation, not a reported CI pass or final S10.6 acceptance.

That task acknowledged the owner's clarifications and reserved incorporation of the minimal prospective active-policy wording until after preserving the current exact-head CI evidence. This review does not edit those shared authority files or claim their new wording has already been applied. Its existing no-minimum-retry and physical-DEFERRED rules remain in force meanwhile.

The owner pause takes precedence over the earlier request to start merging immediately. After the owner returns, re-read the actual S10.6 handoff and distinguish repository preparation from final release acceptance. Hydrate any required source-integration authority against that actual state; do not assume a physical-deferred preparation receipt is an accepted S10.6 final-release receipt. This checkpoint does not advance `main`, waive final gates or silently amend the frozen V23 reconciliation prerequisite.

## Nonaccepting integration checkpoint

- Accepted S10.4 native E: `0adebd72ae0226a80e14eaf515ca133072fb1c76`; evidence K: `e2189af36a89caf815cf078756341c1f1542f7df`; receipt C: `0d54add4a5d09ec3b54483a1fc2a55d8eea8b0e3`.
- Original `main`: `01233f789b1cef5a6f56c7ff4caa9271409cd3bc`; frozen V23: `acbfb68355f903fe98638b6ef22e4814e7b48328`; reviewed V23 source: `4175e75da9c4fb1a51220a2fe463142696507773`. This policy-only descendant is not a new native verification head.
- Read-only merge simulation found three text-conflict paths: `AGENTS.md`, `FieldEvidenceApp/Features/Issues/IssueDetailView.swift`, and `Scripts/ci-selection.json`. No merge was applied and no integration branch was created.
- Both source lines retain one app target and bundle ID `com.palatis3.fieldrecord`. Preserve accepted S10.4 branding, semantic tokens, icons, accessibility identifiers and existing journeys in any future combined candidate.
- V23's `ProductionCompositionRoot` is not instantiated by production app sources. Some shell callers still select compatibility mutation paths, and sampled expansion views have no production route. Persistent storage moves from the accepted schema version 1 to V23's active v53 using the existing workspace location. Native compilation, actual sole-writer/root adoption, complete feature routing, populated-data migration and branded golden-path verification remain required; a Git merge cannot supply them.
- Latest V23 diagnostic run `33980870020` at reviewed source `4175e75da9c4fb1a51220a2fe463142696507773` is nonaccepting failure. Its resumed detailed audit was interrupted for this owner pause; do not infer test success or complete artifact verification from this checkpoint. Prior reviewed fixes and failure evidence remain intact.

## Stop and future cleanup

After recording and verifying this documentation-only update, stop this task's agents and work. Do not create a reminder, monitor, recurring task or automatic continuation for minimum testing, physical testing, S10.6 completion or expansion integration. The user controls the app's goal pause/resume state; recording this instruction does not claim to change that UI state or mark the goal complete.

The owner also requested removal of the obsolete expansion branch after successful integration. Preserve it now. Only after a verified combined app is safely incorporated into `main`, with recoverable source history and exact target checks, may the requested obsolete expansion ref be removed. No separate repository deletion, force-push or destruction of V30/coordination/history is authorized by that cleanup request.
