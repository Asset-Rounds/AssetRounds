# CURRENT TASK — S10.1 Brand activation, inventory, and corrected S9 baselines

## Selection and immutable program authority

- Selected on: `2026-08-15`.
- Phase / branch / card / global order: `S10 / phase/s10-brand-refresh / S10.1 / 37 of 42`.
- Card heading: `### S10.1 — Brand activation, released-state inventory, and corrected S9 baselines`.
- Position / boundary / immediate next: `1 of 6 / phase boundary no / S10.2`.
- Program autopilot / phase autopilot / exact S10 span / boundary integration: `enabled through accepted exact-main S10.6 / enabled / S10.1,S10.2,S10.3,S10.4,S10.5,S10.6 / yes at S10.6`.
- Frozen phase→branch→card map: `S0->phase/s0-foundation->S0.1; S1->phase/s1-shell-design->S1.1; S2->phase/s2-persistence-signs->S2.1,S2.2; S3->phase/s3-check-runner->S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4->phase/s4-reports->S4.1,S4.2,S4.3,S4.4,S4.5; S5->phase/s5-work-recheck->S5.1,S5.2,S5.3,S5.4; S6->phase/s6-data-rights->S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7->phase/s7-commerce->S7.1,S7.2,S7.3,S7.4,S7.5; S8->phase/s8-quality->S8.1,S8.2,S8.3,S8.4; S9->phase/s9-release->S9.1; S10->phase/s10-brand-refresh->S10.1,S10.2,S10.3,S10.4,S10.5,S10.6`.
- End condition: accepted exact-main S10.6; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.
- Repository/visibility/remote/default branch: `palatis3/AssetRounds / private solo / origin / main`.
- Full-access posture: Windows `danger-full-access`, approval policy `never`, network enabled. No approval-message gate applies to ordinary S10 implementation, exact-path commits/pushes, named CI dispatch/inspection, or current-card correction.
- Immutable S10 phase-main and integrated/card base: `P=M=01233f789b1cef5a6f56c7ff4caa9271409cd3bc`.
- Accepted predecessor: S9.1 product `E=35e87b0d97c732f4c63621cc87f9faf86eef97d3`; phase verification run `31907266760`; accepted exact-main head `01233f789b1cef5a6f56c7ff4caa9271409cd3bc`; exact-main run `31908483947`, job `95069878862`, artifact `9253163917` / `ios-ci-31908483947-1` / digest `sha256:b3c5927f6635cedce7e06648ecb12e7b2d053be71fa7f6f9709f55c7527cd0e4`.
- At owner-directed S10 activation, `origin/main` and `origin/phase/s9-release` both equal exact M. The S9.1 HANDOFF remains immutable.
- This owner-directed authority amendment creates A as a direct child of M and changes exactly: `AGENTS.md`, `docs/product/BUILD_PLAN_V4.md`, `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`, `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md`, this `docs/execution/CURRENT_TASK.md`, `docs/design/s10/s10-activation.json`, `docs/design/s10/authority/assetrounds-brand-assets-v4.1-20260815.zip`, and `docs/design/s10/authority/asset-manifest.json`. Fresh G0 observes A after commit; this file never self-records A.
- Fresh G0 must prove `M..A` contains exactly those eight authority paths, remote `phase/s10-brand-refresh=A`, remote `main=M`, exact pins/digests, no overlapping dirt, and no product/project/test/fixture/runtime-asset change.
- Owner-directed post-boundary correction authority: exact-head S10.1 run `31919914831` at `d28108f939efc8fc6db135d9b550fb14fcabd44c` passed build and units, then proved the accepted S9 behavior defect that a valid terminal `issue_still_visible` recheck returns its Issue to `open` but `WorkCoordinator` rejects the same lineage when starting another work record. Direct-child correction `d2747870241b8e617eedcdd3a8df521101c3f357` closed that admission defect with the frozen status reducer grammar.
- Owner-directed follow-on correction authority: exact-head S10.1 run `31922598904` at `d2747870241b8e617eedcdd3a8df521101c3f357` passed build and units and traversed the repaired still-visible cycle, then proved the matching accepted S9 finalization/recovery defect: `FinalizationService` and `FinalizationRecoveryService` still require exactly one work record and reject the valid repeated `work -> could_not_verify -> issue_still_visible -> work -> original_resolved_different_issue` lineage. Preserve S9 refs/HANDOFF and the published S10 ancestry. A direct-child authority commit may change only this file, the pinned runbook, and the activation instance needed to keep its exact paths/cap/runbook pin coherent; its direct-child product correction may change only `FieldEvidenceApp/Infrastructure/Finalization/FinalizationService.swift` and `FieldEvidenceApp/Infrastructure/Finalization/FinalizationRecoveryService.swift`. The unchanged 67-state S10.1 GOLDEN must prove the corrected route in its original order; reordering or omitting the path is forbidden.

## Frozen authority and package

- Plan: `docs/product/BUILD_PLAN_V4.md` / SHA-256 `0477672A3F97E02E229A8DC84B3F27AAF60A3B535FD51B68DADA94ADF410FF4D` / S10 brand-system refresh plus Sections 11, 16, and 18.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / SHA-256 `0B85DE8685EE0E84272EAEDA94729A65CEB5122C718C9EB65DA9A0FFECF7951E` / selected card S10.1 only.
- Contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / SHA-256 `0D09F319EB729A2D57F05515B400B400FF0B753A2E373E7BB8A0AB0561A50BB6`.
- Activation: `docs/design/s10/s10-activation.json` / SHA-256 `693C8E286D2B860398B507AC7899061B8B49D9DF2C14FE279ACD2C64A8F7DD67`.
- Frozen package: `docs/design/s10/authority/assetrounds-brand-assets-v4.1-20260815.zip` / SHA-256 `D05ACDC8195B1C7C05230BCBD0AC59E436681D93FCA9AC12108B2BE98A408400`.
- External manifest anchor: `docs/design/s10/authority/asset-manifest.json` / SHA-256 `F771EB8FBD3D42960FC4B8C0A516A05E8B0FD16EBA2C88107ADD6A4E0D74F551`.
- Owner-directed activation correction: the package validator's two unresolved-placeholder scans use case-sensitive `-cmatch`, preventing the legitimate lowercase `required_pseudolanguages` key from being misclassified as an uppercase `REQUIRED_*` value. Only the validator member, its manifest row, package bytes, activation digests, and these pins changed; all brand/runtime image bytes remain unchanged.
- The V4.1 activation instance now mirrors the conditional earlier-card-owned `WorkCoordinator.swift`, `FinalizationService.swift`, and `FinalizationRecoveryService.swift` paths, ten-file cap, and corrected runbook pin. The frozen ZIP, external package manifest, runtime images, card list/order, selectors, and brand truth remain byte-for-byte unchanged; this is not a brand-package member, brand mutation, or reusable scope expansion.
- Route/state: `replace_unpublished_candidate / unpublished`. No TestFlight or published-release evidence exists.
- Owner use grant: accepted for the AssetRounds project/app/marketing/distribution by repository owner `palatis3`; this is not trademark, title, claim, or URL clearance. Trademark clearance remains `NOT_CLEARED` and blocks S10.6 release readiness.
- Physical bridge plan: owner-signed development install to a named physical iPhone, tied to exact product E by git SHA, bundle ID/version/build, and signed artifact SHA-256. The owner operates signing/install later; Codex does not sign, upload, or fabricate physical evidence.
- Permanent identity: `AssetRounds`; descriptor: `Field Inspections`; current title: `AssetRounds: Sign Inspection` pending professional clearance.
- No V4.1 package file other than the frozen ZIP/manifest enters source authority before its card. The exact 12 app runtime files and project setting remain reserved to S10.2.

## Outcome, GOLDEN, and ALT-1

- Outcome: freeze the complete released route/state/common-task inventory, approved token coverage, corrected S9 pre-migration visual baselines, accessibility/device/locale matrices, experience protocol, store-slot plan, and six one-to-one stage checkpoints before any brand/presentation byte changes.
- Exact S10 checkpoint order: `Inventory -> ComponentSystem -> Migration -> AutomatedLab -> PhysicalExperience -> Release`.
- S10 evidence model: E is the accepted product/test implementation; descendant K may add only this card's exact evidence documents and required task pins after CI; later C records receipt/bookkeeping. K/C never replace E or mutate app/project/test/fixture/asset bytes.
- GOLDEN: one bounded F25 UI class traverses every frozen S9 baseline-capture scenario on the unchanged app and produces exact screenshots. One unit class plus the V4.1 validator prove exact state↔token↔baseline coverage, source/fixture reachability, complete common tasks, device/locale/pseudolanguage/accessibility matrices, store screenshot slots, selector hashes, and all six checkpoints.
- ALT-1: omitted/duplicate route or state; missing/stale source/fixture; unknown token; missing/duplicate baseline; malformed selector/hash; unauthorized package member; or invented physical/legal/release evidence fails closed. Existing baselines are never silently regenerated or replaced.

## Exact card envelope

Product/document cap is exactly 10; test cap is exactly 2. Allowed implementation paths:

1. `docs/design/s10/s10-stage-checkpoints.json`
2. `docs/design/s10/s10-screen-state-inventory.json`
3. `docs/design/s10/s10-accessibility-common-tasks.json`
4. `docs/design/s10/s10-token-coverage.json`
5. `docs/design/s10/s10-visual-regression.json`
6. `docs/design/s10/s10-experience-validation.json`
7. `docs/design/s10/s10-store-readiness.json`
8. `FieldEvidenceApp/Features/Issues/WorkCoordinator.swift`
9. `FieldEvidenceApp/Infrastructure/Finalization/FinalizationService.swift`
10. `FieldEvidenceApp/Infrastructure/Finalization/FinalizationRecoveryService.swift`
11. `FieldEvidenceAppTests/S10_1BrandInventoryTests.swift`
12. `FieldEvidenceAppUITests/S10_1BrandInventoryUITests.swift`

- `Scripts/ci-selection.json` remains the sole standing implementation-support exception.
- `docs/execution/HANDOFF.md` remains append-only bookkeeping only after accepted evidence.
- Activation/package authority files are read-only during S10.1 implementation.
- App changes are limited to the exact repeated-lineage reducer corrections diagnosed by runs `31919914831` and `31922598904`: `WorkCoordinator.swift` admission plus matching `FinalizationService.swift` precommit/replay and `FinalizationRecoveryService.swift` recovery authority. No other app, project, resource, runtime asset, feature, coordinator, model, service, schema, fixture, release metadata, workflow, CI harness, or unrelated documentation path may change.
- Forbidden: S10.2 asset/token/component work; S10.3 migration; baseline regeneration after product mutation; Figma/prototype substitution; new route/feature/copy/data behavior; signing/archive/upload/TestFlight/App Store action; secrets/settings/PR/merge/force push; fabricated legal/physical evidence.

## Environment, workflow, selector, and GitHub authority

- Workflow: `.github/workflows/ios-ci.yml` / SHA-256 `BCD64E2A42752D28844435241B5ABFCA911D04190375CBBDBFC10B45ACBA97D7` / ref `phase/s10-brand-refresh`.
- Runner/toolchain: `macos-26`; image `macos26-20260728.0273.1`; `/Applications/Xcode_26.6.app/Contents/Developer`; Xcode `26.6` build `17F113`; SDK `iphonesimulator26.5` build `23F81a`; Swift language mode 5.
- Project/scheme/configuration/minimum: `FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iOS 26.2 / iPhone 17`; each job resolves a fresh UDID.
- Exact selector after G0: `{"schemaVersion":1,"taskID":"S10.1","tier":"F25","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":900,"testTimeoutSeconds":1200,"uiTimeoutSeconds":1800,"totalBudgetSeconds":4500,"unitTestSelectors":["FieldEvidenceAppTests/S10_1BrandInventoryTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S10_1BrandInventoryUITests"]}` plus one LF; 348 bytes; SHA-256 `2845C608EE15C2B53990C613D19981FFA713F02BD034CF2E007B7514573BF012`.
- Activation selector SHA-256 over the compact ordered snake-case selector object: `A81865294251B405D6937849E8A888338A9BBC925FE3BEC875713CF4ACB1060C`.
- F25 watchdogs: setup/evidence 300s, build 900s, tests 1200s, UI 1800s, total 4500s; Simulator readiness 900s; job watchdog 90 minutes; UI enabled with exactly one selector.
- Allowed GitHub operations: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; exact `ios-ci.yml` dispatch on the phase branch with `run_ui_smoke=true`; exact run observation/download. No PR, merge commit, force/ref rewrite, settings/secrets, release workflow, signing, upload, deployment, submission, or S9.2/S9.3.
- On failure, use the persistent one-candidate evidence loop and smallest direct-child correction inside this exact envelope. Do not weaken selector, coverage, baseline, or evidence acceptance.

## Ordered execution and next

1. Commit/push the eight-path owner-directed authority amendment as A and perform fresh G0.
2. Replace only `Scripts/ci-selection.json` with the exact S10.1 selector as the first support mutation.
3. Preserve the accepted direct-child WorkCoordinator authority/correction sequence, then commit/push the follow-on three-path owner-directed correction authority as a direct child of `d2747870241b8e617eedcdd3a8df521101c3f357`; perform a fresh correction preflight without changing refs other than the exact non-force phase advance.
4. Correct only the diagnosed `FinalizationService.swift` and `FinalizationRecoveryService.swift` repeated-lineage predicates, including replay truth. Preserve the seven canonical instances, the two bounded tests, the unchanged selector, and the exact 67-state traversal order; validate package, schemas, Inventory contract, diff, and exact path count.
5. Commit/push product E, dispatch exactly one F25 candidate, inspect full evidence, and correct persistently until exact-head green.
6. If screenshots/document evidence must be committed after E, create only the descendant evidence K allowed above, revalidate without product-byte changes, and accept exact-head CI at K while retaining E.
7. Read `docs/execution/KNOWN_BUGS.md`; append S10.1 HANDOFF; record the latent-S9 correction and accepted evidence; hydrate only S10.2 through exact HANDOFF-plus-CURRENT_TASK transition; run fresh G0.
8. Immediate next card: `S10.2 — Brand assets, semantic tokens, and reusable components`.
