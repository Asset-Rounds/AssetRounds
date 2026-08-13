# Current Task

## Program and card

- Phase / branch / card / global order: `S4 / phase/s4-reports / S4.1 / 12 of 36`.
- Card heading: `### S4.1 — Byte-deterministic snapshot-to-PDF renderer`.
- Position / boundary / immediate next card: `1 of 5 / phase boundary no / S4.2`.
- Program autopilot / phase autopilot / exact S4 span / boundary integration: `enabled through accepted S9.1 / enabled / S4.1,S4.2,S4.3,S4.4,S4.5 / yes at S4.5 only`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S4 phase-main base and accepted integrated/card base: `P=M=C=8b33ee6a26ed4f7ccdccc8e092920b26c6e04122`; no distinct infrastructure verification head K exists.
- Accepted S3.7 product implementation: `E=I2=755554c3442cc6ceda7947a6c4fa891c5f366e68`; initial `I=dfaf41e53dbe851537a802d49f31dcbdcb4b9276` failed only the diagnosed optional-outcome compiler error. `C^=E`, and `E..C` changes exactly the append-only `docs/execution/HANDOFF.md` S3.7 entry.
- Accepted S3 phase-close evidence: run `31658250052`, job `94317349911`, succeeded at exact `phase/s3-check-runner@C` with P12/UI enabled; artifact `ios-ci-31658250052-1`, ID `9165416492`, size `2031712`, API/raw ZIP digest `sha256:7ee6ef2fe72c9c34aff4ed7342690686e06c19b5f3ddf65977fe3ecbac5b9108`; `SHA256SUMS.txt` SHA-256 `71F416D90CC0E9DD3405D9005508BF851A963C0BA19075F20E1B59868C0DA0E4`; all 99 payloads independently matched; `ui-final.png` SHA-256 `CAE41534D6ABB94A930B6F860BD5F99E1CB379E72BC95A879DE9ABA73A952615`. Setup `16/300` s, readiness `273/900` s, build `179/600` s, unit `154/900` s, UI `218/900` s, setup+artifact `18/300` s, total `674/3300` s.
- Accepted exact-main integration evidence: run `31658998104`, job `94319639357`, succeeded at exact `main@C` with P12/UI enabled; artifact `ios-ci-31658998104-1`, ID `9165632393`, size `2008358`, API/raw ZIP digest `sha256:3c72b806ad73dfe401185e1288d3d667b806ad3a17684157a0f1bb3fe44f31e9`; `SHA256SUMS.txt` SHA-256 `476DBBFDA7CDB1C67FD68B34AB1490725035DE2BC338A992BD811207EE7BFC64`; all 99 payloads independently matched; `ui-final.png` SHA-256 `CD9FE7B941EFC11407021AD98755D1B266531856E0288925F4884A7419B54E1C`. Runner `macos26` image `20260728.0273.1`, Xcode 26.6 `17F113`, iPhone 17/iOS 26.5, UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`; setup `15/300` s, readiness `262/900` s, build `169/600` s, unit `72/900` s, UI `169/900` s, setup+artifact `16/300` s, total `527/3300` s.
- Task-start authority head `A`: `OBSERVE AT POST-COMMIT G0; never self-record its SHA here`.
- Required `M..A`: one direct-child next-phase authority commit changing exactly this `docs/execution/CURRENT_TASK.md`; `docs/execution/HANDOFF.md` remains byte-identical.
- Construction state: accepted `phase/s3-check-runner` and `main` both equal `M`; remote `phase/s4-reports` is at the authorized accepted-head state `M`. Commit only this CURRENT_TASK as direct-child A, non-force fast-forward the S4 phase ref to A, then require clean index/worktree/untracked state and fresh G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S4.1 plan anchors: `## 6. Core workflow and state truth` Report truth; `## 9. Smallest reusable architecture` Persistent models, Exact ReportSnapshotV1, and Exact PDFTemplateV1; `## 10. Storage, crash consistency, and one-off bug prevention` PDF preflight and promotion; `## 13. Quality budget and known bugs` broken-PDF release blockers; global execution anchors remain `## 11`, `## 16`, and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79`.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Accepted generalized UI exporter: `Scripts/ui-smoke.sh` / `6304A318EE046B6B19F4FDDC43BB143F9B21E8150B9D332E449B87A0182D4CDB`.
- Selector schema path: `Scripts/ci-selection.json`; at G0 it may remain accepted S3.7 LF SHA-256 `57C8276ED267CCA525C924A5189FB93C09AB0CDA7D0AC8509F7768CB1F242AD0`. Its first support mutation replaces it with the exact S4.1 object below, LF SHA-256 `0637239D84BE60B3D7B158ED21B1B2CA0D1C198160B8405B246CB143838A5C5D`.

## Outcome and acceptance

- Outcome: an exact two-pass `WorklightPDFRendererV1` plus a bounded render service turns one pending Report into ready only from its durable canonical `ReportSnapshotV1`, exact effective-source current evidence, and validated history thumbnails. Rendering performs no pack, database, current clock, locale, or device-zone lookup.
- Snapshot authority: validate canonical snapshot bytes and SHA, Report/Packet/current-source/stable-root/template/pack relationships, completed record authority, effective source `evidenceSourceRecordID ?? sourceRecordID`, unique referenced IDs, strictly earlier history, and the exact snapshot/current/history evidence union before rendering. Every referenced EvidenceFile must match its exact row, purpose, source record, canonical `evidence/<lowercase-id>/original.jpg` and thumbnail paths, MIME, counts, lowercase hashes, created instant, and regular nonsymlink canonical JPEG bytes. The renderer receives only the validated snapshot, computed digest, and already-verified referenced image bytes; it cannot accept a raw snapshot or reread mutable files.
- PDF template: implement `PDFTemplateV1` exactly as `field.evidence.pdf.worklight.v1` version `1`, Letter `612×792`, outer margin `42`, content rect `x=42,y=72,width=528,height=678`, footer rect `x=42,y=42,width=528,height=18`, and a 12-point clear gap. Canvas is white, accent is `#006D75`, text is black, and every status includes plain text; nothing draws outside content/footer rectangles.
- Typography/pagination: only built-in Helvetica-Bold `22/27` title and `15/18` section, Helvetica `10/14` body and `8/11` caption, and Courier `7/9` footer. Spacing is exactly 18 after title, 12 before section, 6 after heading, 6 between ordinary blocks, and 4 between image/label. Core Text wraps within 528 points; headings keep two following body lines, paragraphs of at least four lines split only 2/2 or better, history rows never split, and deterministic first-pass pagination precedes second-pass drawing.
- Evidence/order truth: current evidence is only `recordID == effectiveSourceRecordID` and uses originals aspect-fit/no-upscale within `528×288`; history uses only validated thumbnails, no more than three `160×120` boxes per row with 12-point gaps. Never crop, tint, filter, upscale, or substitute. Freeze purpose/date captions. A missing required CNV purpose renders exactly `Not captured — Could not verify`; history never fills that slot. Order is frozen identity/time, current wide, current close, stage/outcome/CNV/note, issues plus strictly earlier work/recheck history, disclaimer, then the every-page two-line footer with snapshot time/app/pack/template/snapshot hash at left and `Page n of N` at right.
- Determinism/metadata: formatting is `en_US_POSIX` Gregorian from snapshot strings only. Metadata uses the frozen snapshot time and fixed creator `FieldEvidenceApp PDFTemplateV1`, with no author, subject, or keywords; no current date, zone, random dictionary order, temporary path, or volatile PDF identifier may enter output. The same validated authority on the pinned toolchain must produce byte-identical PDF bytes and lowercase SHA-256 in independent clean roots.
- Storage/commit: overflow-safe PDF preflight on the actual generation volume requires twice referenced-image bytes plus 32 MiB operation allowance, plus the existing 64 MiB reserve, before any PDF write or Report mutation. Write and verify one report-ID-owned same-generation staging PDF, atomically promote it to exact final `pdfs/<lowercase-report-id>.pdf`, reread/hash-verify it, then one SwiftData save changes only the pending Report's `pdfState` to ready and sets exact `pdfRelativePath`/`pdfSHA256`. Never overwrite ready authority or an existing unexpected final. S4.1 adds no startup presence matrix, failure state, Retry, or reconciliation; those belong to S4.2.
- GOLDEN: the same fully validated fixture rendered through the service in two clean generation roots yields byte-identical PDFs and hashes, exact ready paths/rows, exact text/image geometry, frozen order/fonts/footer/metadata, current originals/history thumbnails at their bounds, and the exact missing-CNV label without history substitution.
- ALT-1: changing the device default time zone across winter/summer/DST contexts leaves snapshot interpretation, layout, PDF bytes, and hash unchanged.
- Negative family: unknown template/version, noncanonical or mismatched snapshot, broken Report/Packet/source/root relation, duplicate/missing/wrong-source evidence, history containing the effective source, path/symlink/byte/count/hash/MIME/JPEG mismatch, insufficient/unavailable/overflowed capacity, or unexpected stage/final authority fails closed with no ready row and no unowned durable PDF.
- Forbidden behavior: S4.2 failure/Retry/relaunch/startup reconciliation; S4.3 detail/preview/Share/Files; S4.4 index/filter/history comparison UI; S4.5 correction; new template engine/alternate template; pack/database/current-zone/current-clock lookup inside the renderer; image substitution/cropping/upscale; schema/model/project/package/capability/permission/remote changes; camera/media mutation; work/recheck behavior; deletion/backup/restore; access/commerce; or any later-phase behavior.

## Environment and exact selector

- Route / host: Windows authoring → GitHub Actions macOS verification; never run or claim local Windows Xcode/Simulator results.
- Required tool posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Repository / visibility / default / phase: `palatis3/AssetRounds / public / main / phase/s4-reports`.
- Runner / Xcode / developer dir: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer`.
- Project / scheme / configuration / deployment: `FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `N8 / run_ui_smoke=false`.
- Exact selector: `{"schemaVersion":1,"taskID":"S4.1","tier":"N8","runUISmoke":false,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":0,"totalBudgetSeconds":2400,"unitTestSelectors":["FieldEvidenceAppTests/S4_1DeterministicRendererTests"],"uiTestSelectors":[]}`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; no UI command.
- Required evidence: nonempty boot/build/unit logs; Build and UnitTests result bundles; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`. N8 rejects UI execution, UI selectors, UISmoke result bundles, and screenshots.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=false`; exact-run observation/download; after green, append HANDOFF and execute the same-phase transition below. Forbidden: force-push, merge commit, PR, ref rewrite/delete, main mutation during S4, repository/settings/secret mutation, signing, TestFlight/App Store, deployment/release, S9.2/S9.3.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/Infrastructure/Reporting/SnapshotValidatorV1.swift`
- `FieldEvidenceApp/Infrastructure/Reporting/WorklightPDFRendererV1.swift`
- `FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift`
- `FieldEvidenceApp/Infrastructure/Storage/StoragePreflightService.swift`

Test paths:

- `FieldEvidenceAppTests/S4_1DeterministicRendererTests.swift`

Standing support exception:

- `Scripts/ci-selection.json`

The three reporting paths are the smallest closed validator→renderer→pending-to-ready service boundary. `StoragePreflightService` owns the exact PDF capacity calculation on the target volume. The deterministic fixture is generated inside the single unit-test path; no resource or project delta is needed because synchronized source groups already include new Swift files. Existing `ReportSnapshotV1`, `ReportSnapshotEncoderV1`, seven-model schema, media normalizer, generation/session ownership, and finalization snapshot bytes remain unchanged. `StartupRouter` stays inert because S4.2 owns relaunch reconciliation. `docs/execution/HANDOFF.md` is append-only post-green bookkeeping and is not part of the implementation commit. No other path may change.

## Execution

1. Re-fetch and prove remote `main=M=P`, remote `phase/s3-check-runner=M`, remote `phase/s4-reports=M`, and a clean workspace; explicitly stage only this CURRENT_TASK, commit direct-child authority A, and non-force fast-forward only `phase/s4-reports` to A.
2. Fresh G0 proves `A^=M`; `M..A` changes exactly this CURRENT_TASK, remote `main=M=P`, remote `phase/s4-reports=A`, accepted S3 phase-close/exact-main evidence is complete, carried map/pins/public repository/environment/tool/method posture is exact, selector remains accepted S3.7, and no other path is dirty.
3. Replace selector first, implement only the exact allowed paths, run structural/static Windows checks plus PDF test-fixture sanity checks without claiming an iOS build, explicitly stage task paths, and commit direct-child I.
4. Push exact phase ref non-force and run the one-at-a-time persistent N8 loop. Accept only green exact-head CI with complete checksum-verified build/unit evidence; each terminal failure permits only the smallest diagnosed direct-child correction before fresh verification.
5. After accepted S4.1 evidence, re-fetch and append the complete S4.1 HANDOFF plus hydrate only immediate-next S4.2 CURRENT_TASK in one direct-child same-phase authority commit; keep `main=P`, push non-force, and require fresh S4.2 G0 before any S4.2 implementation.

## Definition of done

- Exact green S4.1 N8 evidence proves validated-snapshot/effective-source authority, exact two-pass Letter geometry/order/fonts/spacing/pagination/footer/metadata, canonical original/thumbnail truth, exact CNV missing-evidence truth, overflow-safe storage preflight, deterministic promotion/ready mutation, byte-identical clean-root output/hash, and zone/DST independence. No S4.2 recovery/Retry or S4.3+ UI/share/history behavior exists. Continue only with S4.2 after the exact same-phase authority transition and fresh G0.
