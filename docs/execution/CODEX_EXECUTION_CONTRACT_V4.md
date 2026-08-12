# Codex iOS Execution Contract V4

Use this contract in the new application repository. It keeps Codex focused, prevents adjacent invention, and defines a small trustworthy verification loop.

## Execution route

V4 uses **Windows for Codex authoring**, a **GitHub-hosted macOS runner for every Xcode build, automated test, and Simulator check**, and **TestFlight on a physical iPhone for hardware and release verification**. “Local” and “local-first” describe device-local product data, not the build host. No owner-operated Mac, local Xcode, local Simulator, XcodeBuildMCP, or local signing identity is required.

Windows can edit and structurally inspect files but cannot prove that iOS code compiles. A build or test claim is valid only when the named GitHub Actions run is green for the exact verification head: product implementation `E` normally, or infrastructure-only `K` after the standing lane proves `E..K` contains no protected product/selector change. Ordinary CI is an unsigned Simulator job. Signing, archive, and TestFlight upload are isolated in a later owner-dispatched S9.2 workflow whose secrets are unavailable to ordinary CI.

## Repository shape

```text
/
├─ AGENTS.md
├─ .gitattributes
├─ .codex/config.toml
├─ .github/
│  └─ workflows/
│     ├─ ios-ci.yml
│     └─ testflight.yml              # created inactive in S9.1; owner-dispatched in S9.2
├─ docs/
│  ├─ product/BUILD_PLAN_V4.md
│  └─ execution/
│     ├─ CODEX_EXECUTION_CONTRACT_V4.md
│     ├─ V4_IMPLEMENTATION_RUNBOOK.md
│     ├─ CURRENT_TASK.md
│     ├─ DECISIONS.md
│     ├─ KNOWN_BUGS.md
│     └─ HANDOFF.md
├─ FieldEvidenceApp.xcodeproj/
│  └─ xcshareddata/xcschemes/FieldEvidenceApp.xcscheme
├─ FieldEvidenceApp/
│  ├─ App/
│  ├─ Features/<Feature>/
│  ├─ Domain/
│  ├─ Infrastructure/
│  ├─ DesignSystem/
│  ├─ Resources/
│  └─ PreviewSupport/
├─ FieldEvidenceAppTests/
├─ FieldEvidenceAppUITests/
├─ TestFixtures/
└─ Scripts/
   ├─ build-smoke.sh
   ├─ test-smoke.sh
   ├─ ui-smoke.sh
   ├─ run-with-timeout.sh
   └─ ci-selection.json
```

## Root `AGENTS.md` rules

1. Implement only the one current card in `docs/execution/CURRENT_TASK.md`. Phase/program autopilot is a sequencing exception after accepted card and phase CI, not multi-card implementation authority. Adjacent improvements are not authorized.
2. The task controls current-card scope/environment plus the exact authorized same-phase span; its exact SHA-256-pinned V4 plan controls product invariants and phase order; its exact SHA-256-pinned runbook card controls selected implementation sequence/files/acceptance/tests. The runbook is a catalog, not whole-app authority. Tests/code describe the baseline and cannot expand scope.
3. Touch only allowed paths. Preserve user changes. Do not refactor or format unrelated code.
4. Reuse existing navigation, domain models, design tokens, dependencies, and fixtures.
5. Do not add a package, target, capability, entitlement, permission, migration, API, backend, analytics event/SDK, account/auth flow, payment behavior, public metadata, deployment, or App Store submission unless the task names it.
6. Device-local and hosted product behavior require separate product decisions and task IDs. Hosted CI verification does not authorize sync, accounts, teams, guests, or server behavior.
7. Use the exact phase branch, workflow/ref, runner label, expected Xcode version/build, project, shared scheme, configuration, Simulator model/OS selector, scripts, validated `ci-selection.json`, and N8/P12/F25 timeout preset. GitHub manual dispatch uses a branch name, not a raw SHA: prove that ref points to the expected head, permit no intervening push, and accept only a matching `head_sha`. Resolve the Simulator UDID inside each ephemeral job; never pin a UDID across jobs. One diagnosed product/card `I2` and rerun is allowed. A mechanically eligible hosted-infrastructure failure instead uses only the separate monotonic evidence-bounded lane below and never consumes or resets `I2`.
8. Do not fix an unrelated baseline failure.
9. The append-only handoff must list phase/card/boundary state; authoring OS; immutable phase-main base `P`; integrated/card-base SHA `M` and predecessor evidence; observed task-start authority SHA `A` plus authority-only `M..A` result; repository/phase branch and implementation SHA; workflow path/run ID/URL/head SHA; runner image/Xcode; resolved Simulator/OS/UDID; artifacts; exact commands/results; dirty/changed paths; defects; and next unstarted card. It never records the future transition or phase-close bookkeeping commit that will contain the entry. The next G0 observes transition/main evidence; S9.1 terminal main evidence is reported in the goal final response and re-queried by S9.2. Never create a self-referential SHA field.
10. Before mutation, fail closed on a required preflight `UNSET`, needed placeholder, plan/runbook hash or selected-card mismatch, incomplete predecessor, non-authority path in `M..A`, overlapping unowned dirty work, unavailable required GitHub operation/runner/Xcode/runtime, or effective project posture that contradicts CURRENT_TASK. Full access, network access, and no approval prompts are the selected posture. Broader filesystem, network, connector, plugin, credential, or external-write capability is never a G0 blocker and never expands task authority. A mechanically eligible infrastructure failure does not require another owner message; its standing lane itself supplies the bounded path/ref/dispatch authority. Later phases never authorize unused product artifacts now.
11. `HANDOFF.md` is append-only bookkeeping outside the cap and never belongs to product implementation `I`/`I2`. `Scripts/ci-selection.json` is the only standing card implementation-support exception. Same-phase autopilot may commit HANDOFF plus immediate-next CURRENT_TASK; a boundary commits HANDOFF only as phase-close `C`. A committed boundary HANDOFF forbids rerunning or editing the card but permits exact idempotent continuation and an eligible infrastructure verification `K`. Record product implementation `E` and distinct successful verification head `K` separately; bookkeeping or `K` never replaces card implementation evidence.
12. A coding card may commit/push only task-owned paths to its named phase branch and trigger/inspect only its named CI workflow. At an authorized boundary, program autopilot may non-force fast-forward `main` to the exact phase-close/verification commit, verify exact-main CI, create the frozen next phase branch, and hydrate its first card. The infrastructure lane authorizes only its exact same-repository refs/workflow and allowlisted CI-harness paths; it never authorizes force-push, divergence repair, merge commit, PR, deployment, signing, TestFlight upload, App Store action, repository settings/secrets, or another external mutation.

## Canonical `CURRENT_TASK.md`

`docs/execution/CURRENT_TASK.md` is the sole active template. Every task includes program-autopilot state and exact phase/branch map; immutable phase-main base `P`; phase/card/boundary position and predecessor/main evidence; dirty-path ownership; exact pins; one outcome; environment and GitHub posture; allowed paths/operations; delta; acceptance; selectors/budget; stop conditions; boundary action; and next card. An ordinary card task includes integrated/card-base `M`, observed authority `A`, and declared `M..A`. An infrastructure task preserves historical card M/A and instead includes product head E, failed verification head F, post-commit-observed K, canonical gate/failure/repair records and hashes under AGENTS' literal grammar, derived next support index, required commit trailers, exact `F..K`, ordered ref cursor/predecessors, and full exact-ref/head candidate history. Every allowed path is one fully expanded repository-relative file; globs, roots, brace/set expressions, and `/**` are invalid. CURRENT_TASK cannot raise caps, broaden/reset the standing lane, relabel an overlap, or make mutable prose authoritative over Git/GitHub history.

Freeze `P` as bootstrap `B` throughout S0 and as the prior accepted exact-main phase-close/verification SHA throughout each later phase. Within a phase, `M` is the preceding card's accepted implementation or verification head; for a phase's first card, `M=P`. At phase start, owner- or program-autopilot-prepared `A` normally changes only CURRENT_TASK. A separate owner product/program decision may install a finite authority/config amendment when CURRENT_TASK declares it; mechanically eligible hosted-CI recovery instead uses the standing lane below without another message. Same-phase autopilot creates later `A` only as prior HANDOFF plus immediate-next CURRENT_TASK. Program autopilot creates next-phase `A` only after verified fast-forward main plus matching green main CI and only as the first-card CURRENT_TASK commit on the frozen next branch. Fresh G0 proves the appropriate exact diff and immutable program map, then permits only frozen card-specific changes. The selector may be absent for S0.1 or equal the accepted predecessor until G0 passes, after which replacement with the current exact object is the first implementation-support mutation.

## Autonomous hosted-CI infrastructure recovery

No new approval message is required. An exact terminal non-green run is eligible only when complete logs and checksum-verified artifacts prove its first causative failure is hosted-runner provisioning, pinned toolchain/runtime readiness, exact-Simulator readiness, Actions service/transport, or lane-owned harness scheduling/accounting, with no compiler diagnostic, product test result/assertion, selector mismatch, or product failure. Pre-repository failure may use authoritative metadata plus complete logs proving no repository command ran; upload failure requires logs proving validation/checksum creation succeeded first. The sole legacy no-manifest exception is exact K2 phase run `31583957094`/head `400f8827f5451b9a44f4d846340b51377554069d`/artifact `9136413551` digest `sha256:284632a9587fa296a36b1c57c9e9320779f022a4d68b8ff5a592305105bfaedd`; it authorizes K3 only and is consumed. K3 makes every later post-checkout classification checksum-verified. Setup `<=120` is eligible only as first failure before product commands; aggregate total only after every constituent/product/selector/evidence/checksum/upload gate passed. Build/unit/UI ceilings and every other acceptance failure are ineligible. Failed assertions remain non-green; ambiguity is ineligible.

For immutable gate identity phase/card/workflow/ordered-ref-roles/product head E/first-failed-run+head, support heads are one direct-child sequence `K1,K2,...`; there is no numeric ceiling or approval gate. Fresh G0 derives the next index from reachable lineage plus every exact-ref/head candidate; freezes canonical gate/failure/repair records under AGENTS' literal grammar and closed registries; hashes them; freezes one diagnosis/minimal delta; proves `K^=F`; and proves no earlier K consumed the same/overlapping operation+mechanism or repair key. Volatile ref/run/head/display/time/UDID/duration/log/cascade values are provenance only. K3+ commits carry one exact gate/index/failed-run/head/ref/failure/repair trailer each; G0 recomputes them. Legacy K1/K2 are indices 1/2. CURRENT_TASK cannot reset/relabel history.

Each K contains mechanical CURRENT_TASK evidence/pins plus exactly one correction across the smallest causal subset. Current K3 is the sole installer exception: it may amend AGENTS/plan/runbook/contract/CURRENT_TASK/workflow/build-smoke once to install static schema/refreeze, non-accepting failure-evidence ordering, and exactly one K2 causal correction. After K3 the four static sources and all smoke/timeout scripts refreeze. Later K may use only CURRENT_TASK plus marker-delimited infrastructure-recovery workflow bodies, and one-delta/no-adjacent-hardening is absolute. Preserve HANDOFF, selector, product/project/tests/fixtures/assets, runner/Xcode/Simulator selection, N8/P12/F25 values, trigger/permissions/action pins, exact build/test/UI commands/selectors/destinations/results, selector/tier/result validation, fail-fast/timeout/exit behavior, evidence/checksum/upload enforcement, and raw aggregate start-before-checkout/end-after-checksum. Readiness stays `<=300` and fully inside raw total. G0 proves the direct delta, cumulative E..K protected-tree/workflow-spine equality, and attribution of every lane hunk to one unique failure/repair.

Per exact workflow/ref/head, zero candidates dispatches once; one active waits; one green accepts. One terminal failure chooses exactly one same-head fresh-runner candidate only for pre-repository provider or post-checksum upload/transport failure with no repository delta, or the next K for a distinct eligible failure/repair and unique correction. Retry consumption is gate-wide: before the no-code retry, canonicalize an unconsumed failure/repair; the first terminal candidate plus exact GitHub receipt consumes both across every ref, and its retry is their sole disposition. GitHub history is immediately authoritative; CURRENT_TASK mirrors it only at the next otherwise-authorized commit. Setup/aggregate failures never redispatch same-head. Creating K retires all unused dispatch/retry authority at F. Exactly two candidates are valid only as that consumed provider/transport failure followed by active/green/terminal; green accepts, while terminal can create another K only for a distinct eligible failure/repair. Any consumed failure/repair recurrence on any ref, a second retry, ambiguity/ineligibility, another ordering, or more than two candidates stops technically. Failed run IDs are never rerun. CURRENT_TASK freezes ordered ref predecessors/cursor; each role moves once by non-force fast-forward after prior roles are green, and an exact already-moved role resumes without re-push. Accept only green exact-K complete artifacts. E remains product evidence; accepted K becomes verification/integration/next base. An open card may use ordinary unused I2 after product failure; a closed boundary card never reopens. Numeric index never stops; technical stops never request authority text.

Exact S0 bridge: K1 `0da62482db7e3f90742876ef05574de9e9569e32` and K2 `400f8827f5451b9a44f4d846340b51377554069d` remain failed. K1 phase run `31579936670` failed only aggregate `727 > 720` after every constituent/product/evidence/checksum/upload gate passed. K2 phase run `31583957094` first failed setup `232 > 120` after its boot request put exact-Simulator readiness on setup's critical path; build/unit/UI did not run, downstream evidence/checksum failure was deterministic, total `233 <= 720`, and upload succeeded. Never accept or redispatch them. Direct-child K3 changes exactly the seven conversion paths, restores setup inspection before readiness, runs bounded exact-UDID readiness as a tracked GitHub background step concurrently with the unchanged exact-destination build, removes only build-smoke's redundant readiness command, and explicitly waits before tests. All P12 values, independent 300/180 ceilings, aggregate endpoints, selector, product/tests, and exact xcodebuild invocation remain unchanged. The first current K at index 3 or later with green exact-head phase and exact-main CI becomes S0 phase-close/S1 `P=M`, while I3 remains product evidence. Distinct eligible later failure/repair pairs may create later K mechanically; repeated/overlapping failures or repairs and other technical stops do not request authority text.

## Phase gate loop

| Gate | Work | Exit |
|---|---|---|
| G0 Scope lock | Read only: exact pins/card/tool state; ordinary `M/A/M..A` or infrastructure `E/F/K/F..K/gate counters`; sources, paths, fixture, selectors, logical Simulator selector | Card or infrastructure gate is unambiguous; missing or broader authority/CI route stops |
| G1 Compile/launch | Minimal structure for this slice | Exact verification head builds, installs, and launches on the CI Simulator while product implementation `E` remains separately identified |
| G2 Golden slice | One deterministic end-to-end path | Targeted tests plus CI XCUITest/Simulator acceptance |
| G3 Named resilience/accessibility | Only the named alternate state and touched controls | Named recovery plus bounded automated or S9.2 physical-device check |
| G4 Integration | Only if persistence/StoreKit is named | Contract test plus unchanged golden path |
| G5 Handoff/integration | No new product behavior | Accepted product implementation plus green exact verification-head run and append-only evidence; then the authorized same-phase transition or fast-forward boundary integration, exact-main CI, and next-phase first-card authority |

## Test budget

- Normal loop on the named Actions runner: one affected-target build and one targeted unit-test run.
- Phase gate: one 5–8-checkpoint CI Simulator smoke when the task authorizes it.
- Final: fresh CI Simulator install/launch, relevant unit tests, one golden UI smoke, and one accessibility spot check; physical-only checks remain S9.2.
- `Scripts/ci-selection.json` has exactly the runbook Section 6 schema. The workflow rejects unknown/missing keys, wrong types, wrong tier values, duplicate/unresolved selectors, or an input mismatch. N8 = setup/evidence 90s + build 150s + targeted unit tests 240s + targeted UI 0s, `runUISmoke=false`, empty UI selector; P12 = 120s + 180s + 180s + 240s, `runUISmoke=true`, one UI selector; F25 = 180s + 240s + 300s + 780s, `runUISmoke=true`, one UI selector. Totals are 480/720/1500 seconds and cover setup through evidence validation/checksum; upload remains within the 30-minute hard stop. `run-with-timeout.sh` enforces step ceilings. Required logs, `.xcresult` directories, and enabled-UI screenshot fail closed before relative-path checksums/upload.
- Do not run fuzzing, exhaustive device/OS/orientation/locale matrices, endurance loops, broad security scans, or a full UI suite unless the task separately authorizes them.
- A product/card timeout is the first failed product attempt. Inspect the complete failing step, raw log, and result artifact; after one concrete task-scoped `I2` and one rerun, any product/compiler/test/acceptance non-green result stops the card.
- A mechanically proven hosted-runner/image/runtime/Simulator/Actions/transport or lane-harness scheduling failure uses only the monotonic evidence-bounded infrastructure lane. It never permits substituting `latest`, changing the pinned environment, weakening evidence, or asking the owner for a routine authority amendment.

## Known-bug policy

May ship: only owner-approved low-severity, non-regressing defects outside the golden path, with reproduction, workaround, owner, and revisit version. Read `KNOWN_BUGS.md` before completion and record every discovered defect in the handoff.

May not ship: primary-path crash/hang, data loss/corruption, privacy/security exposure, incorrect payment/entitlement/permission state, blocked navigation, inaccessible primary action, false completion, broken PDF, or protected CI archive/sign/upload failure.

## GitHub and tool posture

- Run CLI-first `xcodebuild` only in GitHub Actions macOS jobs. Windows edits files and inspects diffs, run logs, and artifacts; it never claims local iOS compilation.
- Do not configure or require XcodeBuildMCP. Use XCUITest and `simctl` in CI; owner-manual hardware/accessibility checks use the S9.2 TestFlight build.
- Pin the runner label, expected Xcode version/build, project/shared scheme/configuration, and Simulator model/OS selector. Each run records `ImageVersion`, the actual Xcode build, and resolved UDID, and fails on mismatch.
- Ordinary CI has `contents: read`, receives no signing secrets, and uses `CODE_SIGNING_ALLOWED=NO`. It uploads logs and `.xcresult`/screenshots even on failure.
- AssetRounds permits the owner's Full access Codex GUI/session posture: unrestricted local filesystem and network capability with no approval prompts. Project `.codex/config.toml` must not downgrade that selected posture. CURRENT_TASK still restricts actual use to its exact paths, repository/ref/workflow arguments, and named external actions. Capability or tool breadth is not a G0 blocker and never expands product or task scope; XcodeBuildMCP remains unnecessary for the Windows-to-GitHub route.
- Before S0, owner bootstrap `B` on the default branch contains all static authority documents/templates, the unhydrated CURRENT_TASK template, owner-created project config, `.gitattributes`, and `ios-ci.yml`. A manual dispatch cannot start until the workflow exists there. `B` has no project/scripts and therefore no predecessor iOS run. The S0 phase branch starts from `B`; its `A` normally changes only hydrated CURRENT_TASK, except for an exact pre-implementation owner authority/config amendment declared under the rule above.
- GitHub branch push, workflow dispatch/inspection, and artifact download are verification actions only when the task names them. PR merge and TestFlight/App Store actions remain separately authorized.
- One persistent `/goal` may traverse the frozen S0–S9.1 coding phase map, with one active card and one phase branch at a time. Each card records product implementation `E`; exact verification normally runs at `E`, or at distinct green `K` after an eligible infrastructure recovery. Same-phase transitions remain exact HANDOFF-plus-CURRENT_TASK bookkeeping followed by fresh G0.
- At a runbook-marked boundary, enabled program autopilot creates HANDOFF-only `C`. Remote `main=P` permits one non-force fast-forward; exact `main=C` resumes. Reuse a matching run, dispatch once only if absent, and accept only green exact-main evidence. An eligible hosted failure invokes the monotonic evidence-bounded K lane: phase first, then main, each non-force and exact-ref gated; the next phase bases on green exact-main K. Every other collision stops. S9.2/S9.3 remain owner-only.
- Figma, Sentry, PostHog, Supabase, RevenueCat, and security tooling are separate authorized tasks, not defaults.

## Phase and device rules

- The exact 36-card decomposition plus two owner-only release gates is frozen in `V4_IMPLEMENTATION_RUNBOOK.md`. CURRENT_TASK always selects one card with one golden and at most one alternate family. One `/goal` may traverse its immutable program map through S9.1 using the closed boundary state machine; it never enters `/plan`, combines cards, or enters owner-only S9.2/S9.3.
- Every current card names predecessor evidence, terminal artifact, smoke IDs, and omitted/inert future controls. The immediate next same-phase card starts only after green CI, closed transition hydration, a bookkeeping commit, and fresh G0.
- The owner's bootstrap `B` places every static authority document/template, project config, supplied `.gitattributes`, and manual `ios-ci.yml` on the default branch before S0. S0 owns the checked-in `.xcodeproj`, shared scheme, four smoke/timeout scripts, selector, and first unsigned GitHub CI baseline. Verify the S0 phase-branch ref points to its implementation SHA, dispatch that ref with `run_ui_smoke=true`, permit no intervening push, and require the run's `head_sha` to equal that commit. Do not introduce a project generator unless the task explicitly pins and authorizes it.
- Before schema freeze, only the exact task-named SwiftData delta is allowed. Reset only the exact app container in the active ephemeral CI Simulator job; never run `simctl erase all` or erase a shared/physical device.
- S1 installs the primary sign-pack manifest/loader; S3 consumes it in the runner; S4 consumes it in the renderer; S8 adds only the nonshipping second fixture.
- CI Simulator work uses deterministic photo fixtures. Camera hardware, true low light, physical VoiceOver/gesture quality, and production-like StoreKit checks are separately named S9.2 gates on the TestFlight iPhone build.
- S9.1 is the final Windows-authored, unsigned-CI-verified coding task and may create the inactive owner-only release workflow. S9.2 is an owner-only manual workflow dispatch for archive/sign/upload of the reviewed exact `main` SHA under the private-solo ref rule followed by iPhone TestFlight verification. For a private repository, select a GitHub plan that supports environment secrets; do not claim a required environment-reviewer gate unless the selected plan supports it. S9.3 is owner-operated App Store Connect submission. Ordinary coding tasks never receive release secrets or mutate release state.

Official references: [Codex AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md), [Codex prompting](https://learn.chatgpt.com/docs/prompting), [Codex native iOS loop](https://learn.chatgpt.com/use-cases/native-ios-apps), [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [runner image/Xcode inventory](https://github.com/actions/runner-images), [Actions secrets](https://docs.github.com/en/actions/concepts/security/secrets), [Apple build uploads](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/), and [TestFlight](https://developer.apple.com/testflight/).
