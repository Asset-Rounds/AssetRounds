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

The owner subsequently clarified the policy directly in the active S10 task, and explicitly asked it to relay the non-blocking rule to this expansion task:

> Is there anyway I can change policy change to just not include 10.5 going forward until the app is in the app store and I can come back to it for like "bug fixes" or anything.

The source receipt is `C:\AssetRounds\Temp\S10_6_ReleasePreparation\post-release-deferral\OWNER_REQUEST_20260910.json`, SHA256 `2C2F440BDB4EB999DF9DF93793F843AABF382681E85690A01761A8254BE7FE7A`. This task read the receipt and verified that hash. It records S10.5 as non-blocking for S10.6 and phase acceptance, physicalResult DEFERRED, no physical PASS, no automatic resumption, no other release-gate waiver, and no signing/upload/submission authorization. The later clarification supersedes the earlier requirement to supply S10.5 physical proof before integration or final S10 closure; it does not resume the paused merge.

## Minimum-OS verification: indefinitely deferred

- All seven S10.4 minimum-runtime full profiles and the separate minimum core smoke remain **DEFERRED indefinitely**. There is no due date, retry count, scheduled follow-up or automatic resumption.
- Only an explicit future owner instruction may reactivate that verification. S10.6 completion or App Store availability does not reactivate it. The owner's reference to reconsidering it after the app is in the App Store is future context, not an automatic trigger or a promise to perform the work.
- Preserve the complete fourteen-profile catalog, its 938 visual slots and 84 accessibility rows. The accepted current-runtime scope remains seven profiles, 469 visual cells and 42 accessibility rows; the minimum-runtime 469 cells and 42 rows remain deferred with no PASS, NOT_APPLICABLE, native success or minimum-runtime support claim.
- Preserve the iOS 18.0 deployment target, all original failures/artifacts, current-runtime assertions and accepted S10.4 E/K/C history. This timing clarification does not hide a known defect affecting retained coverage and does not authorize minimum-runtime CI.

## S10.5 physical testing: deferred and non-blocking

- S10.5 remains **DEFERRED until after App Store release** and is **NON-BLOCKING for S10.6, S10 phase completion and expansion integration**. The owner cannot test now and wants any later testing to involve the completed expansion-inclusive app.
- Missing S10.5 installation, physical-test evidence or a PhysicalExperience E/K/C receipt must not be treated as an integration or S10.6/phase-completion prerequisite. Do not manufacture such a receipt to satisfy an obsolete unconditional six-stage gate. The active S10 task owns the corresponding prospective authority/validator changes.
- Only explicit future owner instruction may resume S10.5 after App Store release. Release itself, S10.6 completion, build availability, or an elapsed interval is not an automatic trigger. Do not require the owner to test the current unexpanded app to clear this deferral.
- Deferral is not completion, a PhysicalExperience PASS, an installation record, or an E/K/C receipt. Any physical result later claimed must identify the actual tested build/head; historical unexpanded-app evidence cannot be relabeled as combined-app proof. Only the S10.5 prerequisite is made non-blocking; other integration and release requirements remain mandatory.
- Owner-only signing, distribution, credentials, TestFlight/App Store operations, legal assertions and submission remain outside this task. Do not fabricate device, operator, installation, physical, legal or release facts.

## S10.6 ownership and release boundaries

The separate task **Resume S10.4 verification** currently owns S10.6 preparation in `C:\AssetRounds`, including CURRENT_TASK, the active plan/runbook/contract/activation pins, HANDOFF and the S10.6 evidence/metadata envelope. It confirmed candidate `df52d7517806192b8ccff46923d1add1680ec75f` is committed/pushed and its ordinary GitHub F25 run was dispatched. That is a candidate observation, not a reported CI pass or final S10.6 acceptance.

That task acknowledged the owner's clarifications, confirmed the later S10.5 non-blocking interpretation, and reserved incorporation of the prospective active-policy amendment until after preserving the current exact-head CI evidence. This review does not edit those shared authority files or claim their new wording/validators have already been applied. Its existing no-minimum-retry and physical-DEFERRED rules remain in force meanwhile.

The owner pause takes precedence over the earlier request to start merging immediately. After the owner returns, re-read the actual S10.6 handoff and its applied prospective authority, and distinguish repository preparation from acceptance of all remaining gates. Hydrate source-integration authority against that actual state, applying this explicit S10.5 non-blocking exception wherever inherited V23 wording would otherwise require its physical receipt. Do not confuse a preparation-only receipt with S10.6 acceptance of the remaining requirements. Preserve all other reconciliation, exact-head CI, data-survival, brand/accessibility and release gates. This checkpoint does not advance `main`, start a merge, invent acceptance, or authorize release operations.

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
