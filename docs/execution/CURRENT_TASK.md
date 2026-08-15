# Current Task

## Program and card

- Phase / branch / card / global order: `S9 / phase/s9-release / S9.1 / 36 of 36`.
- Card heading: `### S9.1 — Unsigned release candidate and inactive TestFlight workflow`.
- Position / boundary / immediate next gate: `1 of 1 / phase boundary yes / owner-only S9.2 after accepted S9.1 implementation, HANDOFF-only phase close, green exact-head phase CI, verified non-force main fast-forward, and green exact-main CI`.
- Program autopilot / phase autopilot / exact S9 span / boundary integration: `enabled through accepted exact-main S9.1 / enabled for S9.1 only / S9.1 / yes at S9.1`; coding stops after that exact-main gate.
- Frozen phase->branch->card map: `S0->phase/s0-foundation->S0.1; S1->phase/s1-shell-design->S1.1; S2->phase/s2-persistence-signs->S2.1,S2.2; S3->phase/s3-check-runner->S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4->phase/s4-reports->S4.1,S4.2,S4.3,S4.4,S4.5; S5->phase/s5-work-recheck->S5.1,S5.2,S5.3,S5.4; S6->phase/s6-data-rights->S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7->phase/s7-commerce->S7.1,S7.2,S7.3,S7.4,S7.5; S8->phase/s8-quality->S8.1,S8.2,S8.3,S8.4; S9->phase/s9-release->S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S9 phase-main base and integrated/card base: `P=M=2e9f8a1bdade83f4510c6c6ff6bd18cefc7343a9`, the accepted S8 phase-close and exact-main verification head. It remains byte-for-byte fixed throughout S9.1 until the terminal S9 boundary state machine advances main.
- Accepted S8 phase evidence: run `31900317667` / job `95049942017`, exact `phase/s8-quality@M`, attempt 1, P12/UI enabled, terminal success, build plus `2/2` units plus `1/1` UI green. Artifact `ios-ci-31900317667-1`, ID `9251000247`, size `4400407`, digest `sha256:604faf9f11db27adf7593562eee988680bba19bc5c44882cc1a35c8b76a59383`; all `95/95` payload checksums matched; `SHA256SUMS.txt` SHA-256 `368F476D9619395736614A42C44F5490E2CD8D09305F0AD391042BF7B25BF7D4`.
- Accepted exact-main evidence: run `31900819297` / job `95051208912`, exact `main@M`, attempt 1, P12/UI enabled, terminal success, build plus `2/2` units plus `1/1` UI green. Artifact `ios-ci-31900819297-1`, ID `9251141391`, size `5380871`, digest `sha256:60de73326c62be5960e7670713029493f552cf33a4f88b617353687743072840`; all `95/95` payload checksums matched; `SHA256SUMS.txt` SHA-256 `F05579BF851D2C5AB7FFBD841BF95EBCEB4463FBF516009C8F0107C1DBDA1F9E`.
- Accepted environment: `macos26` image `20260728.0273.1`; Xcode 26.6 build `17F113`; iPhone 17 / iOS 26.2 build `23C54`; Simulator UDID `9AA9ED9B-42D2-4F6E-B8B5-45AAB66D6404`; initial state `Shutdown`.
- S8.4 boundary lineage: production implementation `0459a23671800b4501a66938bc3237edda239d0c`; HANDOFF-only close `c8efdd479cf5d2b7868f31371159d716819702b5`; phase run `31899623500` / job `95048229253` failed only a post-Files XXXL hittability race; direct-child test correction and accepted phase/main head `M`. No failed run ID was rerun or accepted.
- S9.1 transition authority must directly parent exact M and change only this immediate-next `docs/execution/CURRENT_TASK.md`. Fresh G0 must observe and record that transition head as A without self-recording its SHA here, prove `M..A` contains exactly this one path, prove remote `phase/s9-release=A`, and prove remote `main=M` plus remote `phase/s8-quality=M`.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S9.1 plan anchors: `## 11. Build slices and release gates` -> final Codex coding card and inactive owner-only release workflow; `## 12. Twelve must-pass launch smokes`; `## 13. Quality budget and known bugs`; `## 16. Owner preparation checklist` -> exact pending/provided release inputs; and `## 18. Codex execution authority` -> no invented live values, secrets, signing, upload, deployment, or submission.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / selected card S9.1 only.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `BCD64E2A42752D28844435241B5ABFCA911D04190375CBBDBFC10B45ACBA97D7` / `workflow_dispatch`.
- Selector at G0 may still equal accepted S8.4 compact JSON plus LF, 338 bytes, SHA-256 `F886AB7AACB19223029540EA811D7E049B15A98CF6D7FB7B7FA11D7ADB443544`; after complete G0 the first support mutation replaces it with the exact S9.1 object below, 340 bytes, SHA-256 `03C23506919733DDE0174448E446D26DF4753C505BE242587886F142D281314F`.

## Outcome and acceptance

- Outcome: create the complete repository-derived unsigned RC package: canonical pending/provided release-input manifest and provided-values config, unsigned metadata, privacy manifest/review, App Review checklist, 12-smoke evidence index, export options, bounded preflight, and a complete but inactive owner-only TestFlight workflow. No signing, upload, deployment, or submission occurs.
- Prehydrated truth: only `com.palatis3.fieldrecord`, `com.palatis3.fieldrecord.tests`, `com.palatis3.fieldrecord.uitests`, and `com.palatis3.fieldrecord.sub.solo.monthly.v1` are frozen as provided identifiers. `AssetRounds: Sign Inspection` remains an adopted candidate title pending professional clearance and is not asserted as cleared/final metadata.
- Release-input truth: every external value named by plan S9 and the owner-only S9.2/S9.3 gates is present exactly once as `provided` or `pending`, with a closed key, nonsecret source/status, and no placeholder treated as live truth. This includes owner/account/program authority, title clearance, six-of-ten evidence, agreements/bank/tax/Small Business status, live product/group/storefront/offer/grace, owner domain/support email/three live URLs, App Store record and metadata/review/privacy/age/encryption inputs, release version/build, environment secrets, and signing credentials.
- Readiness truth: repository-derived values may be provided, all currently unspecified live values remain pending, and `releaseReady` is true only when every required input is provided and internally consistent. Pending inputs make S9.2 unavailable but do not fail the unsigned S9.1 build or fabricate data.
- Privacy truth: `PrivacyInfo.xcprivacy` and the review describe only behavior evidenced by the source and built product, declare no app-developed tracking or silent data upload, and include only required-reason API categories/reasons actually used. The manifest, metadata, diagnostics, backup, commerce, mail, and system-link boundaries remain mutually consistent.
- Workflow truth: `.github/workflows/testflight.yml` has only explicit manual dispatch, requires the owner-reviewed exact `main` SHA under the private-solo ref rule, serializes without cancellation, fails closed while release readiness or secrets are absent, uses a temporary keychain and SHA-pinned `actions/*`, invokes Apple-native archive/export/upload tools exactly once, sanitizes evidence, and has no automatic upload retry. Ordinary S9.1 CI inspects it but never executes signing or upload.
- GOLDEN: ordinary unsigned F25 CI builds/tests the RC, validates every repository-derived and provided value plus every explicit pending value, validates PrivacyInfo and inactive workflow secret boundaries, runs the final golden UI smoke, and produces the evidence index and checksummed artifact while honestly reporting non-release-ready pending inputs.
- ALT-1: one bounded preflight family fails closed for malformed/inconsistent provided config, an omitted/duplicate/unknown manifest key, readiness mismatch, privacy inconsistency, wrong or moved main authority, unpinned action, forbidden trigger/retry, or embedded secret. It never converts a pending external value into a coding failure or a release-ready claim.
- Unit truth: one bounded unit class validates exact package schemas/content, identifier/version/project consistency, privacy manifest, 12-smoke evidence coverage, pending/provided readiness reduction, workflow triggers/ref/secret/action/keychain/upload boundaries, and the malformed/inconsistent preflight family.
- UI truth: one bounded Accessibility XXXL final-RC test completes the existing golden sign/check/report route, reopens its report and Settings/data-right surfaces, proves primary controls remain reachable, and takes exactly one terminal in-app screenshot. It makes no signing, upload, live-link, physical-device, or spoken-VoiceOver claim.
- Forbidden behavior: feature/backend/analytics SDK, account/auth, remote config, live-value invention, production SKU/App Store record creation, secret/credential/signing material, automatic workflow trigger, signing/archive/upload execution during S9.1, retrying upload, PR/merge/force-push, TestFlight/App Store mutation, deployment, submission, or any S9.2/S9.3 action.

## Environment and exact selector

- Route / repository / refs: Windows authoring -> exact GitHub Actions macOS verification; `palatis3/AssetRounds / public / main / phase/s9-release`; never run or claim Windows Xcode/Simulator results.
- Required posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Runner / Xcode / project: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer / FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.2`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `F25 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S9.1","tier":"F25","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":900,"testTimeoutSeconds":1200,"uiTimeoutSeconds":1800,"totalBudgetSeconds":4500,"unitTestSelectors":["FieldEvidenceAppTests/S9_1ReleasePreflightTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S9_1FinalRCUITests"]}` plus exactly one LF; 340 UTF-8 bytes, no BOM; SHA-256 `03C23506919733DDE0174448E446D26DF4753C505BE242587886F142D281314F`.
- Exact commands: `bash Scripts/run-with-timeout.sh 900 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 1200 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 1800 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, and UITests result bundles; exactly one terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named ordinary unsigned `ios-ci.yml` dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download. At the terminal boundary only, append-only HANDOFF phase-close commit, exact-head phase verification, verified non-force main fast-forward, and exact-main verification are authorized. The newly committed TestFlight workflow is inspection-only in S9.1 and must not be dispatched. Force-push, merge commit, PR, ref rewrite/delete, settings/secrets, App Store Connect, signing, archive/export/upload execution, TestFlight/App Store, deployment/release, and S9.2/S9.3 are forbidden.

## Exact allowed implementation paths

Release/product paths (ten of the default ten-file cap):

- `Release/ReleaseInputManifestV1.json`
- `Release/ProvidedReleaseValuesV1.json`
- `Release/UnsignedRCMetadataV1.json`
- `Release/PrivacyReviewV1.md`
- `Release/AppReviewChecklistV1.md`
- `Release/LaunchSmokeEvidenceIndexV1.json`
- `Release/TestFlightExportOptions.plist`
- `FieldEvidenceApp/PrivacyInfo.xcprivacy`
- `.github/workflows/testflight.yml`
- `Scripts/release-preflight.sh`

Test paths (two of the default five-file cap):

- `FieldEvidenceAppTests/S9_1ReleasePreflightTests.swift`
- `FieldEvidenceAppUITests/S9_1FinalRCUITests.swift`

Standing selector exception:

- `Scripts/ci-selection.json`

No other production, feature, model, project, resource, fixture, asset, script, workflow, authority, metadata, or documentation path is allowed during S9.1 implementation. Existing app/project settings, synchronized app resources, all accepted tests/helpers, release-relevant source, S0–S8 HANDOFF evidence, and ordinary unsigned CI may be read and validated without editing. Append-only `docs/execution/HANDOFF.md` remains separately authorized bookkeeping after accepted evidence.

## G0, verification, and phase boundary

- Fresh G0 must prove transition A directly parents exact `P=M`, `M..A` changes only this immediate-next CURRENT_TASK, remote `phase/s9-release=A`, and remote `main=M` plus `phase/s8-quality=M`; it must reprove both accepted S8 boundary runs/artifacts/checksums and every pin above.
- Validate the exact S9.1 F25 selector object against runbook Section 6 and the workflow schema. The accepted S8.4 selector is permitted only as predecessor state; after complete G0 replace only `Scripts/ci-selection.json` with the frozen S9.1 object as the first implementation-support mutation.
- Implement only S9.1. Continue every repository-derived artifact while recording unspecified live inputs as pending. Do not ask for, fabricate, store, log, or use release secrets; do not dispatch the inactive TestFlight workflow.
- Candidate recovery follows the persistent evidence-driven direct-child loop. Never weaken manifest completeness/readiness, privacy consistency, exact-main authority, secret boundaries, pinned actions, single-attempt upload design, final golden smoke, selector, screenshot count, or watchdogs.
- After accepted exact-head S9.1 implementation CI, read `KNOWN_BUGS.md` and append immutable S9.1 HANDOFF only. Commit/push that HANDOFF-only phase-close C, accept exact-head F25/UI-enabled phase CI, non-force fast-forward `main` to the exact green verification head, and accept exact-main F25/UI-enabled CI with complete artifacts. Then report the accepted head/runs and stop coding. Never dispatch TestFlight, sign, archive/export/upload, deploy, submit, or enter S9.2/S9.3.
