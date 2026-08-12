# Current Task

## Program position

- Active operation: `S0 hosted-CI authority/support K4`; S0.1 product implementation is complete and only boundary verification remains.
- Program autopilot: `enabled through accepted S9.1`.
- Phase autopilot: `enabled`; exact authorized span in each phase is that phase's ordered card subsequence in the frozen map below; no cross-phase card selection is permitted before green exact-main boundary evidence.
- Boundary integration: `yes through S9.1`; Codex may perform the verified non-force phase/main transitions in the persistent state machine below.
- Exact phase → branch → card order: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1 CI with complete evidence. S9.2 signing/TestFlight and S9.3 App Store submission remain outside this goal.
- Immediate next card after S0 closes: `S1.1`.

## Exact current state and evidence

- Repository / visibility / default branch: `palatis3/AssetRounds` / `private` / `main`.
- Local branch and construction base: `phase/s0-foundation` / `K3=e569951909c2ee8aff4253bae0d442550c229a16`.
- Immutable S0 phase-main base: `P=c3e536a03775cc8d25f42a8e31c2f24db4390d4d`.
- Historical ordinary-card G0: `M=I2=481d272ec319d3210d0e393d20130c7c1f8f0e1a`; `A=A0=9590743877627cdd915a68ec581cdff88d9d6418`; `M..A` is one direct-child authority commit changing exactly the historical four declared authority documents. K4 preserves this history.
- Remote phase, remote main, and remote default HEAD at K4 construction: all `K3`; `phase/s1-shell-design` absent; worktree/index/untracked initially clean.
- Failed verification base `F=K3=e569951909c2ee8aff4253bae0d442550c229a16`; derived support index `4`; candidate K4: `OBSERVE AT POST-COMMIT G0`; K4 must directly parent K3 and comprise one commit changing exactly the seven K4 paths below.
- Accepted S0.1 product evidence: `E=I3=ac310dd37700d65165200f742aaec1d48d0a34d6`; phase run `31566371521` green. Product/project/app/test/HANDOFF bytes remain unchanged by K4.
- Immutable S0.1 HANDOFF commit: `C=15348e92466a79efd02bfb71f5ffee043e615829`.
- Historical infrastructure heads: `R=1e0322cc072fda28718468bcd1b0dbe1f5d0accc`; `K1=0da62482db7e3f90742876ef05574de9e9569e32`; `K2=400f8827f5451b9a44f4d846340b51377554069d`; `K3=e569951909c2ee8aff4253bae0d442550c229a16`.
- Accepted K3 phase evidence: run `31590956549`, exact phase ref/head K3, succeeded with setup `15/120`, readiness `184/300`, build `116/180`, unit `160/180`, UI `99/240`, total `469/720`, and complete verified artifacts.
- Failed K3 main evidence: run `31591804256`, exact main/head K3, failed only because exact-Simulator readiness reached the old 300-second watchdog while CoreLocationMigrator remained active. Setup passed `14/120`, unchanged build passed `134/180`, wrapper propagated `124`, unit/UI were skipped, total passed `316/720`, checksums passed, and artifact upload `9139566365` completed. This run remains failed and is never acceptance evidence.
- K4 diagnosis: K3 phase/main A/B evidence proves hosted cold-Simulator readiness is variable beyond 300 seconds and the old build/unit/aggregate margins are brittle. Preserve K3 concurrency and raise cleanup watchdogs; do not change product behavior or commands.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- Required plan anchors: `## 11. Build slices and release gates`; `## 16. Owner preparation checklist`; `## 18. Codex execution authority`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `D4BFAC281FAD255C97C4AECD02FFFA0B884D026770ABF96EF2DC20E108B052DB`.
- Selected runbook card: `### S0.1 — Repository and unsigned CI baseline`; lifecycle `persistent verification/correction recovery`.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Selector: `Scripts/ci-selection.json` / `B46D4707C758DE1C086109960DA5D4E98662F0AD0083E7DA497C9CDA3B34D645`.

## K4 outcome and exact delta

- Replace repository-created approval gates, retry ceilings, single-fix ceilings, consumed-signature stops, ambiguity stops, and owner-only phase advancement with persistent evidence-driven execution through S9.1.
- Preserve one action at a time: reuse green exact-head evidence, wait for one active candidate, otherwise dispatch one new run ID. Never rerun a failed run ID.
- A hosted-infrastructure failure authorizes another exact-head fresh-runner candidate or one direct-child diagnosed harness correction. A product/compiler/test/acceptance failure authorizes one direct-child card-scoped correction. Repeat without a numeric ceiling until exact-head green; no failed result is ever accepted.
- Permit Codex to fast-forward the exact phase branch and `main` non-force only after the required green predecessor evidence and immediate ref reproof. Never force-push, create a merge commit or PR, rewrite a published ref, or change repository settings/secrets.
- Keep the K3 Simulator-readiness/build concurrency and mandatory join. Raise readiness from `300` to `900` seconds; job cleanup ceiling from `30` to `90` minutes.
- Replace timeout tiers with exact watchdog values: `N8=300/600/900/0/2400`, `P12=300/600/900/900/3300`, `F25=300/900/1200/1800/4500` in setup/build/unit/UI/total order. Tier names are stable legacy IDs, not literal minute counts.
- Replace the S0.1 selector with the exact new P12 values. Preserve the S0 unit/UI selectors, result bundles, screenshot, logs, checksum verification, and raw total endpoints.
- Product/project/app/test/fixture/asset/HANDOFF delta: `NONE`.

## Environment and selector

- Route: Windows authoring → named GitHub Actions macOS workflow. Never claim a local Windows iOS build/test result.
- Runner / Xcode / developer dir: `macos-26` / `Xcode 26.6, Build version 17F113` / `/Applications/Xcode_26.6.app/Contents/Developer`.
- Project / scheme / configuration / deployment: `FieldEvidenceApp.xcodeproj` / `FieldEvidenceApp` / `Debug` / `iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12` / `run_ui_smoke=true`.
- Exact selector object: `{"schemaVersion":1,"taskID":"S0.1","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S0LaunchTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S0LaunchUITests"]}`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required artifact: `ios-ci-<run_id>-<run_attempt>` with boot/build/test/UI logs, enabled result bundles and screenshot, runner/Xcode/Simulator/selection/budget evidence, and verified relative `SHA256SUMS.txt`.

## K4 allowed paths

- `AGENTS.md`
- `docs/product/BUILD_PLAN_V4.md`
- `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`
- `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md`
- `docs/execution/CURRENT_TASK.md`
- `.github/workflows/ios-ci.yml`
- `Scripts/ci-selection.json`

No other path may change in K4. Read-only Git/GitHub inspection and artifact download are authorized. Explicit staging, one K4 commit, non-force pushes, exact workflow dispatches, and artifact downloads are authorized as described here.

## Persistent execution state machine

1. Finish K4 with exact repins, validate only the seven paths are dirty, stage only those paths, commit once, and prove clean K4 directly parents K3.
2. Re-fetch refs immediately before mutation. If the phase ref is K3, non-force fast-forward it to K4. If it is already K4, resume. If an external descendant appeared, reconstruct the unpushed correction linearly on that descendant and reverify; never force or merge.
3. For the phase ref/head K4, and for any later direct-child correction head: accept an existing green complete candidate; wait if one is active; otherwise dispatch one fresh `workflow_dispatch` candidate with `run_ui_smoke=true`. Inspect every terminal run completely. Repeat same-head candidates for infrastructure/provider/transport variance; create one direct-child diagnosed correction for repository failures. Continue until green.
4. After green exact phase evidence, re-fetch `main`. Non-force fast-forward K3→accepted verification head, or resume if already equal. Run the same one-at-a-time exact-main loop until green. A main-discovered product failure keeps S0 active and authorizes a correction; it never reopens or falsifies prior evidence.
5. After green exact-main S0 evidence, create `phase/s1-shell-design` at the accepted head, hydrate S1.1 from its frozen runbook card, and continue card/phase order. Within a phase, transition only to the immediate next card after green exact-head evidence. At each later phase boundary, append/push the handoff-only close, obtain green exact phase-ref evidence for that close or a later direct-child recovery head, non-force fast-forward main to that exact green head, verify exact main, then create the next phase branch.
6. Repeat this state machine through accepted exact-main S9.1. Do not enter S9.2/S9.3.

## Acceptance and non-negotiable safeguards

- Exact-head green CI and complete required evidence remain mandatory; a retry or larger watchdog never converts a failure to acceptance.
- Preserve card outcomes, GOLDEN and ALT-1 behavior, exact selectors, exact product commands/destinations, result validation, checksums, and phase/card order unless the active frozen card itself names their change.
- Each correction commit has one diagnosed purpose and touches only the active card paths or causally required CI-harness paths. There is no numeric limit on sequential correction commits or fresh-runner candidates.
- Missing or ambiguous evidence triggers another diagnostic run or a narrow diagnostic change. It is not an authority stop and is not acceptance.
- Remote movement triggers re-fetch, wait, or a new linear descendant with fresh verification. It never authorizes force-push or silent overwrite.
- No signing, TestFlight/App Store upload, deployment, production secret mutation, or S9.2/S9.3 action is authorized.

## Definition of done

- K4 or a later accepted direct-child verification head has exact green phase and exact-main S0 P12 runs with complete artifacts; remote phase/main/default HEAD equal that accepted verification head; `E=I3` remains S0 product evidence unless exact verification diagnoses a real S0 product correction.
- Every card S1.1 through S9.1 is then implemented in exact frozen order, corrected and rerun until green, handed off, and boundary-verified on exact main.
- Stop only after accepted exact-main S9.1 evidence. External service unavailability may require waiting, but no repository-created approval message, retry count, correction count, K index, repeated failure label, or ambiguity label terminates the goal.
