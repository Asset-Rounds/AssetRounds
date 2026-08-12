# Current Task

## Program and card

- Phase / branch / card / global order: `S3 / phase/s3-check-runner / S3.2 / 6 of 36`.
- Card heading: `### S3.2 — Imported-fixture media pipeline and runner`.
- Position / boundary / immediate next card: `2 of 7 / phase boundary no / S3.3`.
- Program autopilot / phase autopilot / exact S3 span / boundary integration: `enabled through accepted S9.1 / enabled / S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7 / yes at S3.7 only`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S3 phase-main base: `P=7d135aaddd0bdc50168552b0610f04adc1703506`.
- Accepted S3.1 integrated/card base: `M=E=I2=770785cbf890501b4df21cab86fafd804f00c6c6`; initial S3.1 product/test head `I=df4f184735da7f220e671c1b976d601c7e7b87d1`; I2 changed only the S3.1 unit-test fixture's StoreGenerationSession lifetime.
- Predecessor exact-head evidence: run `31638832689`, job `94255903791`, succeeded at exact `phase/s3-check-runner@M` with P12/UI enabled; artifact `ios-ci-31638832689-1`, ID `9158415545`, API/raw ZIP digest `sha256:4d7eeaea42aba3128c1505cb196210df353a67d45571256093032ed1f440c022`; `SHA256SUMS.txt` SHA-256 `C60C1BE3953F66E2F41EC6848B5AD75F9651496460604EF9F7FB8ECF567C0414`; all 115 payloads independently matched; `ui-final.png` SHA-256 `C2A8FAFB5D0D54C918953109D0EBC541534FE1AF29CD2811B8213D8BE60D5CC6`. Runner `macos26` image `20260728.0273.1`, Xcode 26.6 `17F113`, iPhone 17/iOS 26.5, UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`; setup `30/300` s, readiness `354/900` s, setup+artifact `32/300` s, total `756/3300` s.
- Task-start authority head `A`: `OBSERVE AT POST-COMMIT G0; never self-record its SHA here`.
- Required `M..A`: one direct-child same-phase transition commit changing exactly the append-only `docs/execution/HANDOFF.md` S3.1 entry plus this immediate-next `docs/execution/CURRENT_TASK.md`.
- Construction state: immediately before transition, remote `phase/s3-check-runner=M` and remote `main=P`; commit/push only the two authority paths, then require clean index/worktree/untracked state and fresh G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S3.2 plan anchors: `## 6. Core workflow and state truth`; `## 9. Smallest reusable architecture` (`EvidenceFile`, exact evidence purposes); `## 10. Storage, crash consistency, and one-off bug prevention` (`MediaContractV1`, bundle promotion, storage preflight). Global execution anchors remain `## 11`, `## 16`, and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79`.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Accepted generalized UI exporter: `Scripts/ui-smoke.sh` / `6304A318EE046B6B19F4FDDC43BB143F9B21E8150B9D332E449B87A0182D4CDB`.
- Selector schema path: `Scripts/ci-selection.json`; at G0 it may remain accepted S3.1 LF SHA-256 `F8C9C17EB06713BA6299F3869DC444D53E18AD41C5172CBB9EDFC961AE65237D`. Its first support mutation replaces it with the exact S3.2 object below, LF SHA-256 `B2C7E95F27D48E717C503AF95A128EBA9E4E986ECD6A58B619A9BB635B025296`.

## Outcome and acceptance

- Outcome: implement the imported-fixture capture runner for an existing committed draft: canonical `MediaContractV1` normalization, important-usage storage preflight, actor-isolated staging/final file store, atomic original+thumbnail bundle acceptance, exact EvidenceFile persistence, and ordered wide then close progression. Outcome/finalization remain unavailable.
- Media contract: accept one still frame only from public JPEG/HEIC/HEIF/PNG; reject animated/multipage, RAW, unsupported, malformed, oversized, or over-dimension sources with one actionable import error. Source maximums are 80 MiB, 100,000,000 decoded pixels, and 1–16,384 pixels per axis.
- Canonical outputs: apply orientation; tone-map HDR/wide-gamut/CMYK/grayscale into 8-bit sRGB; composite alpha on white; strip EXIF/GPS/IPTC/XMP/TIFF/orientation metadata. Original is one JPEG quality 0.90, no upscale, longest edge <=4096, <=32 MiB. Thumbnail uses the same canonical pipeline at quality 0.75, no upscale, longest edge <=512, <=2 MiB. Only structural JFIF plus the selected sRGB ICC profile may remain. Durable MIME is exactly `image/jpeg`; sniff decoded type/frame count and validate bytes rather than trusting declarations/extensions.
- Storage preflight: read important-usage capacity for the actual generation volume; require the 68 MiB evidence-acceptance estimate plus the frozen 64 MiB reserve before staging. Failure creates no file/row, preserves prior accepted state, and shows a retry/space-recovery state. Do not add the S3.5 injectable failure framework.
- Acceptance sequence: write `.staging/evidence/<lowercase-evidence-id>/{original.jpg,thumbnail.jpg}`, verify exact regular nonsymlink files, decoded contract, byte counts, and lowercase SHA-256; atomically rename that one directory to `evidence/<id>/`; only then perform one SwiftData save that inserts one EvidenceFile row with exact generation-relative paths/counts/hashes/record/purpose/createdAt and advances the draft step `wide→close` or `close→outcome`; if that save fails, roll back both row/step changes, remove only that newly promoted unowned bundle, and preserve prior evidence.
- Runner: the existing original/check/draft accepts exactly one `wide_context` (`Wide view`; `Take one wide photo showing the full sign and its surroundings.`), then exactly one `close_detail` (`Close view`; `Take one close photo showing the sign face clearly.`); headings are `1 of 2 · Wide view` then `2 of 2 · Close view`. No duplicate or wrong-purpose evidence. **Retake** removes only the current unaccepted staging bytes and returns to import without changing an accepted EvidenceFile. **Use Photo** is the sole acceptance action. After wide commit advance draft step to close; after close commit advance to outcome and expose only explicit `Outcome is unavailable until S3.3.`
- GOLDEN: deterministic test-only injected wide and close fixtures produce exact canonical original+thumbnail JPEG MIME/path/byte-count/hash facts; bytes decode within the frozen bounds and retain only structural JFIF plus the selected sRGB ICC profile; each accepted bundle and EvidenceFile survives termination/relaunch through the existing sole-draft path without adding a recovery matrix; progress resumes at close after wide and at S3.3-unavailable after close; accepted wide remains byte-identical while close is processed.
- ALT-1: import a candidate, choose Retake, and prove only unaccepted staging bytes disappear while accepted prior evidence, row, draft step, and durable bundle remain unchanged; then import/Use Photo succeeds.
- Forbidden behavior: camera adapter/request/permission/usage key; PhotosPicker/library recovery; production fixture route; durable HEIC/PNG; work/recheck/outcome choices/review/CNV/finalization/Packet/Report/Issue operation; startup staging reconciliation/resume matrix beyond the active in-process acceptance path; broad storage/write fault injection; repository/job/media framework; model/schema/project/package/capability/permission/remote delta; diagnostics/evaluation/access/paywall/StoreKit.

## Environment and exact selector

- Route / host: Windows authoring → GitHub Actions macOS verification; never run or claim local Windows Xcode/Simulator results.
- Required tool posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Repository / visibility / default / phase: `palatis3/AssetRounds / public / main / phase/s3-check-runner`.
- Runner / Xcode / developer dir: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer`.
- Project / scheme / configuration / deployment: `FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S3.2","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S3_2MediaPipelineTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S3_2ImportedCaptureUITests"]}`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, UISmoke result bundles; terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download; after green, HANDOFF plus immediate S3.3 transition only. Forbidden: force-push, merge/main mutation before S3.7, PR, ref rewrite/delete, repository/settings/secret mutation, signing, TestFlight/App Store, deployment/release, S9.2/S9.3.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/App/FieldEvidenceAppApp.swift`
- `FieldEvidenceApp/Domain/Media/MediaContractV1.swift`
- `FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift`
- `FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift`
- `FieldEvidenceApp/Features/CheckRunner/PreflightView.swift`
- `FieldEvidenceApp/Features/Shell/AppShellView.swift`
- `FieldEvidenceApp/Features/Signs/SignsRootView.swift`
- `FieldEvidenceApp/Infrastructure/Media/EvidenceBundleStore.swift`
- `FieldEvidenceApp/Infrastructure/Media/MediaNormalizerV1.swift`
- `FieldEvidenceApp/Infrastructure/Storage/StoragePreflightService.swift`

Test paths:

- `FieldEvidenceAppTests/S3_2MediaPipelineTests.swift`
- `FieldEvidenceAppUITests/S3_2ImportedCaptureUITests.swift`
- `FieldEvidenceAppUITests/Fixtures/S3_2WideInput.png`
- `FieldEvidenceAppUITests/Fixtures/S3_2CloseInput.png`

Standing support exception:

- `Scripts/ci-selection.json`

`docs/execution/HANDOFF.md` is append-only post-green bookkeeping and is not part of the implementation commit. No other path may change.

## Execution

1. Fresh G0 proves `A^=M`; `M..A` is exactly one append-only HANDOFF plus CURRENT_TASK transition commit; remote main=P and remote phase=A; carried map/pins/public repository/environment/tool/method posture are byte-identical; selector remains accepted S3.1; no other path is dirty.
2. Replace selector first, implement only allowed paths, run structural/static Windows checks, explicitly stage task paths, and commit direct-child I.
3. Push exact phase ref non-force and run the one-at-a-time persistent P12 loop. Accept only green exact-head CI with complete checksum-verified unit/UI/evidence artifacts; each terminal failure permits only the smallest diagnosed direct-child correction before fresh verification.
4. After accepted S3.2 evidence, append HANDOFF and transition only to immediate-next S3.3 when remote phase still equals accepted head. Do not mutate main.

## Definition of done

- Exact green S3.2 evidence: imported fixtures canonically normalize; capacity gate precedes writes; original+thumbnail stage/verify/atomic promotion precedes row save; wide then close rows/bundles/hashes/progress survive relaunch; Retake removes only unaccepted staging; terminal UI truthfully states S3.3 outcome is unavailable; all adjacent future behavior remains absent.
- Handoff records required evidence; remote phase equals accepted verification head, then continue only with S3.3.
