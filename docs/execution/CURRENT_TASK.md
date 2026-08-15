# Current Task

## Program and card

- Phase / branch / card / global order: `S8 / phase/s8-quality / S8.4 / 35 of 36`.
- Card heading: `### S8.4 — Feedback with explicit attachment consent`.
- Position / boundary / immediate next card: `4 of 4 / phase boundary yes / S9.1 only after accepted S8.4 evidence, HANDOFF-only phase close, green exact-head phase CI, verified non-force main fast-forward, green exact-main CI, next-phase authority hydration, and fresh S9.1 G0`.
- Program autopilot / phase autopilot / exact S8 span / boundary integration: `enabled through accepted S9.1 / enabled / S8.1,S8.2,S8.3,S8.4 / yes at S8.4`.
- Frozen phase->branch->card map: `S0->phase/s0-foundation->S0.1; S1->phase/s1-shell-design->S1.1; S2->phase/s2-persistence-signs->S2.1,S2.2; S3->phase/s3-check-runner->S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4->phase/s4-reports->S4.1,S4.2,S4.3,S4.4,S4.5; S5->phase/s5-work-recheck->S5.1,S5.2,S5.3,S5.4; S6->phase/s6-data-rights->S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7->phase/s7-commerce->S7.1,S7.2,S7.3,S7.4,S7.5; S8->phase/s8-quality->S8.1,S8.2,S8.3,S8.4; S9->phase/s9-release->S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S8 phase-main base: `P=0b1e506dd71ba704cbfb48787d6cfa1731024d83`; this exact accepted S7 phase-close/exact-main head remains byte-for-byte fixed until the S8.4 boundary state machine verifies and advances it.
- Integrated/card base: `M=721acf69c74224919fa30fa9019a0e2dd1ffb0c4`, the accepted S8.3 implementation and verification head.
- Accepted S8.3 evidence: run `31896497197` / job `95040508518`, exact `phase/s8-quality@M`, attempt 1, P12/UI enabled, terminal success, build plus `2/2` unit plus `1/1` UI green. Artifact `ios-ci-31896497197-1`, ID `9250030547`, size `1590841`, digest `sha256:933f6ec44dc71fbdf617e5e8404b0a2de741764b035bc5bd1819ad147322a3b6`; all `95/95` payload checksums matched; `SHA256SUMS.txt` SHA-256 `7B9640A2FF8DBD159DC1154BE740574917A84A7FA92134F5D7B91872D2739998`.
- Accepted environment: `macos26` image `20260728.0273.1`; Xcode 26.6 build `17F113`; iPhone 17 / iOS 26.2 build `23C54`; Simulator UDID `9AA9ED9B-42D2-4F6E-B8B5-45AAB66D6404`; initial state `Shutdown`.
- S8.3 implementation lineage: authority `A=131129d0d027709257fdf2a7271656c38afbea85`; initial implementation `I=76436c6cc32cb2881e6afc67818b148b89ebaba5`; accepted test-only correction `I2=E=M`. Failed run `31895943753` / job `95039163086` was never rerun or accepted.
- Same-phase S8.4 transition authority must directly parent exact M and change only append-only `docs/execution/HANDOFF.md` plus this immediate-next `docs/execution/CURRENT_TASK.md`. Fresh G0 must observe and record that transition head as A without attempting to self-record its SHA here, prove `M..A` contains exactly those two paths, prove remote `phase/s8-quality=A`, and prove remote `main=P`.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S8.4 plan anchors: `## 14. Analytics, feedback, and learning` -> Settings Send feedback, user-written editable mail with app/version/device context, diagnostic review plus explicit consent, unavailable-mail Copy support address and optional Save diagnostics to Files, and no silent failure/provider/mailto attachment delivery; `## 11. Build slices and release gates` -> S8.4 explicit attachment consent. Global execution anchors remain `## 16` and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / selected card S8.4 only.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `BCD64E2A42752D28844435241B5ABFCA911D04190375CBBDBFC10B45ACBA97D7` / `workflow_dispatch`.
- Selector at G0 may still equal accepted S8.3 compact JSON plus LF, 348 bytes, SHA-256 `A3F9897C658B273AC991A30CFFF880458953682BF57516AEA552C4292F3A7626`; after complete G0 the first support mutation replaces it with the exact S8.4 object below, 338 bytes, SHA-256 `F886AB7AACB19223029540EA811D7E049B15A98CF6D7FB7B7FA11D7ADB443544`.

## Outcome and acceptance

- Outcome: add one Settings Send feedback flow backed by an injectable system-mail adapter. The user reviews the exact S8.3 sanitized diagnostic and then explicitly chooses `Attach` or `Don't Attach` before entering the same editable feedback composer.
- Configuration truth: production support address is intentionally absent until S9.1 and must fail closed without inventing or hardcoding one. Tests may inject only the controlled reserved address `support@example.invalid`; it is test authority, never production configuration, metadata, or a release value.
- Mail truth: the composer recipient comes only from validated configuration. Prefill contains only app version/build and device model/OS context plus a blank editable feedback area; it contains no customer/site/sign/address/note/photo/path/hash/report/backup/StoreKit transaction or entitlement content. The app neither sends nor claims delivery; the system composer remains user editable and user controlled.
- Consent truth: review shows the exact prepared canonical diagnostic bytes before any attachment. `Attach` passes exactly one `application/json` attachment named `field-record-diagnostics.json`; `Don't Attach` passes zero attachments. Both choices open the same composer context, and attachment choice is never inferred, remembered, or silently changed.
- Unavailable truth: when the system composer is unavailable and the configured support address is valid, show `Copy support address` and `Save diagnostics to Files`. Copy writes only that address to the pasteboard after the user's tap; Files uses the exact reviewed canonical bytes. Never silently fail, open `mailto:`, synthesize a provider/web request, attempt background upload, or preattach through another route.
- Missing configuration truth: missing, empty, malformed, or non-email production support configuration produces an honest blocked state with retry/close reachability, no composer, pasteboard mutation, Files attachment implication, URL open, or transport attempt.
- GOLDEN: with the controlled test address and available injected composer, the user reviews the exact sanitized file, chooses Attach, and the editable composer receives the controlled recipient, safe context, and exactly one byte-identical JSON attachment.
- ALT-1: Don't Attach opens the same editable feedback with zero attachments. An unavailable composer exposes Copy support address plus Save diagnostics to Files; a missing/invalid address fails closed; none silently fail or attempt provider/mailto attachment delivery.
- Unit truth: one bounded unit class verifies configuration validation, safe context/customer-content exclusion, exact reviewed-byte identity, Attach/Don't Attach payload cardinality, unavailable fallback actions, missing-address failure, and zero transport/provider behavior.
- UI truth: one bounded Accessibility XXXL Settings flow opens Send feedback, proves exact review/privacy/consent copy and 44-point controls, exercises both explicit consent states through the controlled test adapter plus the unavailable Files/copy fallback, returns in-app, and takes exactly one terminal in-app screenshot.
- Forbidden behavior: production support-address invention, automatic diagnostic attachment, prefilled customer content, background/provider/ticket SDK/upload, web form, `mailto:` attachment delivery, automatic send, delivery claim, diagnostics mutation, raw OSLog/MetricKit/database/media/report/backup attachment, schema/entity/dependency/permission/capability, rating prompt, S9 metadata/address, signing, TestFlight, submission, deployment, or release.

## Environment and exact selector

- Route / repository / refs: Windows authoring -> exact GitHub Actions macOS verification; `palatis3/AssetRounds / public / main / phase/s8-quality`; never run or claim Windows Xcode/Simulator results.
- Required posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Runner / Xcode / project: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer / FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.2`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S8.4","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S8_4FeedbackConsentTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S8_4FeedbackUITests"]}` plus exactly one LF; 338 UTF-8 bytes, no BOM; SHA-256 `F886AB7AACB19223029540EA811D7E049B15A98CF6D7FB7B7FA11D7ADB443544`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, and UITests result bundles; exactly one terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download. At the boundary only, append-only HANDOFF phase-close commit, exact-head phase verification, verified non-force main fast-forward, exact-main verification, and frozen S9 branch/first-card hydration are authorized. Force-push, merge commit, PR, ref rewrite/delete, settings/secrets, App Store Connect, signing, TestFlight/App Store, deployment/release, and S9.2/S9.3 are forbidden.

## Exact allowed implementation paths

Production paths (seven of the default ten-file cap):

- `FieldEvidenceApp/Domain/Feedback/FeedbackConfigurationV1.swift`
- `FieldEvidenceApp/Infrastructure/Feedback/MailComposerAdapter.swift`
- `FieldEvidenceApp/Features/Settings/FeedbackView.swift`
- `FieldEvidenceApp/Features/Settings/DiagnosticExportView.swift`
- `FieldEvidenceApp/Features/Shell/AppShellView.swift`
- `FieldEvidenceApp/Features/Signs/SignsRootView.swift`
- `FieldEvidenceApp/App/FieldEvidenceAppApp.swift`

Test paths (two of the default five-file cap):

- `FieldEvidenceAppTests/S8_4FeedbackConsentTests.swift`
- `FieldEvidenceAppUITests/S8_4FeedbackUITests.swift`

Standing selector exception:

- `Scripts/ci-selection.json`

No other production, model, project, resource, fixture, asset, script, workflow, authority, or documentation path is allowed during S8.4 implementation. Existing S8.3 diagnostic encoder/service/document, Settings/navigation dependency chain, UIKit representable/delegate patterns, pasteboard and Files APIs, app/version/device providers, design tokens, routes, fixtures, and test helpers may be read and reused without editing. Append-only `docs/execution/HANDOFF.md` remains separately authorized bookkeeping after accepted evidence.

## G0, verification, and phase boundary

- Fresh G0 must prove transition A directly parents exact M, `M..A` changes only append-only HANDOFF plus immediate-next CURRENT_TASK, `P..A` preserves the accepted S8 lineage, remote `phase/s8-quality=A`, and remote `main=P`; it must reprove accepted S8.3 run/artifact/checksums and every pin above.
- Validate the exact S8.4 P12 selector object against runbook Section 6 and the workflow schema. The accepted S8.3 selector is permitted only as predecessor state; after complete G0 replace only `Scripts/ci-selection.json` with the frozen S8.4 object as the first implementation-support mutation.
- Implement only S8.4. Reuse the exact prepared S8.3 canonical bytes and Settings/Files seams; production configuration remains absent until S9.1, and the reserved controlled address must be injectable/test-only.
- Candidate recovery follows the persistent evidence-driven direct-child loop. Never weaken explicit preview and attachment choice, byte identity/cardinality, editable system-composer truth, unavailable fallback, missing-config fail-closed behavior, customer-content exclusion, selector, screenshot count, or watchdogs.
- After accepted exact-head S8.4 CI, read `KNOWN_BUGS.md` and append immutable S8.4 HANDOFF only. Commit/push that HANDOFF-only phase-close C, accept exact-head P12/UI-enabled phase CI, then non-force fast-forward `main` to the exact green verification head and accept exact-main UI-enabled CI. Reprove both refs and accepted artifacts before creating `phase/s9-release` from green main and hydrating only S9.1 in a direct-child CURRENT_TASK-only authority commit. Any boundary failure remains S8.4 and follows the persistent correction loop. Do not start S9.1 implementation before fresh S9.1 G0; never start S9.2/S9.3.
