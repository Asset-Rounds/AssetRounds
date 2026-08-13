# Current Task

## Program and card

- Phase / branch / card / global order: `S4 / phase/s4-reports / S4.4 / 15 of 36`.
- Card heading: `### S4.4 — Reports index, history, current revision, and comparison`.
- Position / boundary / immediate next card: `4 of 5 / phase boundary no / S4.5`.
- Program autopilot / phase autopilot / exact S4 span / boundary integration: `enabled through accepted S9.1 / enabled / S4.1,S4.2,S4.3,S4.4,S4.5 / yes at S4.5 only`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S4 phase-main base: `P=8b33ee6a26ed4f7ccdccc8e092920b26c6e04122`; remote `main` must remain exactly P throughout S4.4.
- Accepted S4.3 integrated/card base and product implementation: `M=E=I5=2601787b1377b408568d5f07faab2bda65648e9d`; implementation sequence `I=6f3d6efb2c94e81a288bf0db23815a2f052262c8`, `I2=7134d13cb080524c53284768ec306adfa96f7dec`, `I3=dd076b5afc435a6038dcab7d1cd673ffeaf093fc`, `I4=d4ee41ec43b9b58fd348051eb6b0d5580eca2afc`, then accepted I5. No distinct infrastructure verification head K exists.
- Immutable failed candidate provenance: run `31672818079`, job `94360899015`, failed at exact I2 when the UI fixture preview did not appear, artifact `ios-ci-31672818079-1`, ID `9170583567`, size `70786235`; fresh exact-I2 run `31673737324`, job `94363648486`, failed after cold reopen routed to honest `Report unavailable`, artifact `ios-ci-31673737324-1`, ID `9170922678`, size `110889090`; exact-I3 run `31674714383`, job `94366671811`, failed the post-Share Save-to-Files UI assertion, artifact `ios-ci-31674714383-1`, ID `9171334940`, size `87074143`; exact-I4 run `31675836560`, job `94370109178`, failed because the remote Share dismissal control never became hittable, artifact `ios-ci-31675836560-1`, ID `9171838664`, size `76495406`. These run IDs remain failed and are never rerun or described as accepted.
- Accepted predecessor exact-head evidence: run `31677280546`, job `94374516642`, succeeded at exact `phase/s4-reports@M` with F25/UI enabled; artifact `ios-ci-31677280546-1`, ID `9172311092`, size `3049533`, API/raw ZIP digest `sha256:854be0f95326aaae8a2c89e9ec369ce930cb4af421f2007b12ff5e0bf12f18cf`; `SHA256SUMS.txt` SHA-256 `A652B37B6FAE2E11587ABC9CA998B064922C3B0283A423A8A339B89E3AEA40DE`; all `107/107` payloads independently matched; `ui-final.png` SHA-256 `E8DBB6B2B73DDC3A28FEC37784AF08CE5A7D546CF3985D76BBDF584483C979CD`; `8/8` unit and `1/1` UI tests passed.
- Predecessor runner/toolchain/destination/budgets: `macos26` image `20260728.0273.1`; Xcode 26.6 `17F113`; iPhone 17 / iOS 26.5 build `23F77` / UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`; setup `18/300` s, Simulator readiness `314/900` s, build `167/900` s, unit `154/1200` s, UI `185/1800` s, artifact `0` s, setup-plus-artifact `18/300` s, total `677/4500` s.
- Task-start authority head A is the direct-child S4.3→S4.4 transition commit observed after that commit exists at fresh G0; this pre-commit authority file deliberately never self-records A's future SHA.
- Required `M..A`: exactly one direct-child same-phase transition commit changing only the append-only `docs/execution/HANDOFF.md` S4.3 entry plus this immediate-next `docs/execution/CURRENT_TASK.md`; remote `phase/s4-reports=A`, remote `main=P`, and no other path dirty at G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S4.4 plan anchors: `## 5. Navigation and onboarding` Reports navigation/filtering; `## 6. Core workflow and state truth` Comparison and Report truth; `## 9. Smallest reusable architecture` exact seven-model/current-revision/snapshot authority; `## 13. Quality budget and known bugs` blocked navigation/data/report-truth blockers; global execution anchors remain `## 11`, `## 16`, and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / selected card S4.4 only.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Accepted generalized UI exporter: `Scripts/ui-smoke.sh` / `6304A318EE046B6B19F4FDDC43BB143F9B21E8150B9D332E449B87A0182D4CDB`.
- Selector at G0 may remain accepted S4.3 LF SHA-256 `58363B3FDAD13A57EF0F320F0DB92F80E020877A160D1131AC28BB61698DCDEF`; the first support mutation replaces it with the exact S4.4 object below, LF SHA-256 `B3F3F01BA00E88AC4405DD8EF2CD06AF83A2A1D71739F131431F78D3E8366D0E`.

## Outcome and acceptance

- Outcome: activate the existing Reports tab as a newest-first Reports index; add site/sign filters, sign-scoped chronological history, one current Report revision per live Packet stable root, and a Then/Now comparison against only the immediately previous distinct Packet visit. Do not add correction or any later workflow.
- Current-revision authority: start from unique schema-1 live Packets with nonnull unique `currentRecordID`, null `contentDeletedAt`, unique `stableRootID`, and a unique completed current WorkflowRecord. Collapse every stable root to exactly one current Report whose `packetID` and `sourceRecordID` match that Packet/current record and whose complete ready snapshot/PDF/evidence authority validates. A correction/replacement revision under the same Packet/root is never another visit; reverse replacement status is derived and no prior row is mutated. Pending, failed, tombstoned, duplicated, colliding, broken, or unvalidated authority never becomes a browsable current report.
- Membership and filters: derive report membership through one unambiguous Site→Asset→WorkflowRecord→Packet→Report chain using stable IDs. Expose All, site, and sign filtering without search. Filter membership may use current Site/Asset identity, but every report/history/comparison fact and label remains frozen snapshot truth; later mutable Site/Asset/Issue or pack-registry text never rewrites history.
- Chronology: derive each visit instant from its completed substantive/effective evidence-owning record rather than Report creation or correction time. Sort the index newest first by that completion instant, using canonical Packet stable-root UUID only as the deterministic tie-break after distinct roots are established. Equal instants may be ordered deterministically for history but never satisfy the strictly-earlier comparison relationship.
- Comparison: for a selected current visit, choose only the immediately preceding distinct Packet stable root for the same sign after current-revision collapse, and only when its substantive completion instant is strictly earlier. Both sides must retain unique fully validated ready authority and their required purpose-matched current evidence. Then/Now dates, captions, outcome, and evidence come only from the two immutable validated snapshots/files; images are never cropped, tinted, filtered, scored, or upscaled.
- Detail/navigation: index and sign history open the existing `ReportDetailView` through the existing exact ready-report loader; the Reports tab replaces its static stub. Sign detail gains only a history action and preserves S4.3 direct exact-one-ready reopen. Navigation identity carries stable IDs and resolves immutable values from validated authority without a second transient presentation source of truth.
- GOLDEN: with multiple sites/signs/Packet revisions, the filtered history selects the unique current revision for each live stable root, orders visits newest first, and shows exact Then/Now evidence and dates for two unambiguous visits while opening the exact current cached Report/PDF.
- ALT-1: ambiguous ordering, a non-strictly-earlier predecessor, broken/ambiguous current-revision authority, or missing required evidence omits comparison and keeps the chronological filtered history accessible without guessing or mutation.
- UI acceptance: exercise the Reports tab, site/sign filters, sign history, unique current revision, detail reopen, and one unambiguous Then/Now comparison; prove an ambiguous/missing-evidence posture omits comparison while history remains usable; retain one terminal in-app screenshot. Touched primary controls require exact labels, button traits, logical order, non-color state, 44-point targets, Dynamic Type-safe scrolling, and deterministic focus behavior.
- Negative family: dirty context; duplicate Site/Asset/Packet/stable-root/current-record/Report authority; tombstone; pending/failed or nonterminal ready fields; replacement collision/cycle; unknown schema/template/pack; noncanonical/mismatched snapshot/PDF/evidence path/hash/bytes; unsafe directory/symlink/special file; missing effective source/completion/evidence; cross-sign relationship; or equal/ambiguous chronology never guesses a current revision, comparison side, or report truth and never mutates domain/files.
- Forbidden behavior: search; AI; OCR; image comparison/scoring; newest/current guessing from Report creation time; treating a correction/replacement as a visit; editing/correcting/replacing/deleting a Report; S4.5 correction; new model/schema/project/package/capability/permission; renderer/template/storage/finalization/recovery mutation; ready regeneration/demotion; hosted link/backend/upload; automatic Share/export; rating/notification/paywall/purchase/access gating; work/recheck/deletion/backup/restore/commerce/diagnostic-export/feedback; or any later-phase behavior.

## Environment and exact selector

- Route / repository / refs: Windows authoring → exact GitHub Actions macOS verification; `palatis3/AssetRounds / public / main / phase/s4-reports`; never run or claim Windows Xcode/Simulator results.
- Required posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Runner / Xcode / project: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer / FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S4.4","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S4_4HistoryComparisonTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S4_4ReportsUITests"]}` plus exactly one LF; 339 bytes.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, UISmoke result bundles; terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download; after green, HANDOFF plus immediate S4.5 transition only. Main mutation before S4.5 phase close, force-push, merge, PR, ref rewrite/delete, settings/secrets, signing, TestFlight/App Store, deployment/release, and S9.2/S9.3 are forbidden.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/Features/Shell/AppShellView.swift`
- `FieldEvidenceApp/Features/Signs/SignsRootView.swift`
- `FieldEvidenceApp/Features/Signs/SignDetailView.swift`
- `FieldEvidenceApp/Features/Reports/ReportsRootView.swift`
- `FieldEvidenceApp/Infrastructure/Reporting/ReportHistoryCoordinator.swift`
- `FieldEvidenceApp/Infrastructure/Reporting/ReportDeliveryCoordinator.swift`

Test paths:

- `FieldEvidenceAppTests/S4_4HistoryComparisonTests.swift`
- `FieldEvidenceAppUITests/S4_4ReportsUITests.swift`

Standing support exception:

- `Scripts/ci-selection.json`

New `ReportHistoryCoordinator` is the sole read-only query/projection boundary for unique membership, stable-root current-revision collapse, filtering, deterministic chronology, and comparison eligibility. Existing `ReportDeliveryCoordinator` exposes/reuses its complete anchored ready snapshot/PDF/evidence authority so history/comparison/detail never duplicate unsafe reads or weaken S4.3 validation. New `ReportsRootView` owns the index/filter/history/comparison UI and may use file-private subviews; AppShell activates it, and Signs adds only sign-scoped history navigation. Synchronized source groups include the two new Swift files. Existing `ReportDetailView`, seven-model schema, `SnapshotValidatorV1`, render/recovery/finalization/storage/media services, app root, project, resources, and fixtures remain unchanged. Unit fixtures are synthesized inside the one test file and UI reuses existing imported media; no project/resource/fixture delta is needed. `docs/execution/HANDOFF.md` is append-only post-green bookkeeping outside the implementation commit/cap. No other path may change.

## Execution

1. Fresh G0 observes A and proves `A^=M`; `M..A` is exactly the append-only S4.3 HANDOFF plus this S4.4 CURRENT_TASK transition; remote phase=A, remote main=P; accepted S4.3 I–I5/run/artifact evidence and all immutable failed candidates are complete; selector remains accepted S4.3; no other path is dirty.
2. Replace selector first, implement only the exact allowed paths, run structural/static Windows checks without claiming an iOS build, explicitly stage task-owned paths, and commit direct-child I.
3. Re-fetch, prove phase still at the intended parent, non-force push exact phase ref, and run the one-at-a-time persistent P12 loop. Accept only green exact-head CI with complete checksum-verified unit/UI/artifact evidence; each terminal failure permits only the smallest diagnosed direct-child correction before a fresh candidate.
4. After accepted S4.4 evidence, re-fetch and append the complete S4.4 HANDOFF plus hydrate only immediate-next S4.5 CURRENT_TASK in one direct-child same-phase authority commit; keep main=P, push non-force, and require fresh S4.5 G0 before S4.5 implementation.

## Definition of done

- Exact green S4.4 evidence proves the active Reports index and sign-scoped history expose only unique fully validated current revisions per live Packet stable root; filters preserve unambiguous Site/sign membership; chronology uses substantive completion truth; correction revisions never become visits; Then/Now compares only the immediately previous distinct strictly-earlier Packet with required immutable evidence; ambiguity or missing evidence omits comparison without hiding history; exact current ready reports reopen through retained S4.3 authority; no mutation, search, scoring, correction, or later behavior exists. Handoff records complete evidence, remote phase equals the accepted verification head, and only then may the exact S4.5 authority transition begin.
