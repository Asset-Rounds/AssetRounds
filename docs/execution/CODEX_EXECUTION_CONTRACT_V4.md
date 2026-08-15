# Codex iOS Execution Contract V4

Use this contract in the new application repository. It keeps Codex focused, prevents adjacent invention, and defines a small trustworthy verification loop.

## Execution route

V4 uses **Windows for Codex authoring**, a **GitHub-hosted macOS runner for every Xcode build, automated test, and Simulator check**, and **TestFlight on a physical iPhone for hardware and release verification**. “Local” and “local-first” describe device-local product data, not the build host. No owner-operated Mac, local Xcode, local Simulator, XcodeBuildMCP, or local signing identity is required.

Windows can edit and structurally inspect files but cannot prove that iOS code compiles. A build or test claim is valid only when the named GitHub Actions run is green for the exact verification head: product implementation `E` normally, or infrastructure-only `K` after the standing lane proves `E..K` contains no protected product change and any selector-watchdog change is the exact explicit policy migration. Ordinary CI is an unsigned Simulator job. Signing, archive, and TestFlight upload are isolated in a later owner-dispatched S9.2 workflow whose secrets are unavailable to ordinary CI.

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
│  ├─ design/s10/                    # frozen Brand Handoff activation/contracts/evidence
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
7. Use the exact phase branch, workflow/ref, runner label, expected Xcode version/build, project, shared scheme, configuration, Simulator model/OS selector, scripts, validated `ci-selection.json`, and N8/P12/F25 watchdog preset. GitHub manual dispatch uses a branch name, not a raw SHA: prove that ref points to the expected head, permit no intervening push, and accept only a matching `head_sha`. Resolve the Simulator UDID inside each ephemeral job; never pin a UDID across jobs. Diagnosed product/card corrections use successive direct-child heads `I`, `I2`, `I3`, and so on until acceptance passes. Hosted-infrastructure and lane-harness failures use the persistent fresh-runner/K loop below; neither lane has a retry or numeric correction ceiling.
8. Do not fix an unrelated baseline failure.
9. The append-only handoff must list phase/card/boundary state; authoring OS; immutable phase-main base `P`; integrated/card-base SHA `M` and predecessor evidence; observed task-start authority SHA `A` plus authority-only `M..A` result; repository/phase branch and implementation SHA; workflow path/run ID/URL/head SHA; runner image/Xcode; resolved Simulator/OS/UDID; artifacts; exact commands/results; dirty/changed paths; defects; and next unstarted card. It never records the future transition or phase-close bookkeeping commit that will contain the entry. The next G0 observes transition/main evidence; S10.6 terminal main evidence is reported in the goal final response and re-queried by S9.2. Never create a self-referential SHA field.
10. Before mutation, resolve every required preflight fact. An `UNSET`, placeholder, pin/card mismatch, incomplete predecessor, non-authority path in `M..A`, overlapping dirty work, unavailable GitHub/runner/toolchain route, or posture mismatch creates a read-only recovery state: re-read, re-fetch, wait, gather diagnostics, or apply the authorized mechanical authority/correction update. It is not an approval-message gate and never authorizes guessing product truth. Full access, network access, and no approval prompts are the selected posture. Broader capability is never a G0 blocker and never expands task authority. Hosted-infrastructure and product verification failures continue under the persistent recovery loop without another owner message.
11. `HANDOFF.md` is append-only bookkeeping outside the cap and never belongs to product implementation heads. `Scripts/ci-selection.json` is the standing card implementation-support exception. Same-phase autopilot may commit HANDOFF plus immediate-next CURRENT_TASK; a boundary commits HANDOFF only as phase-close `C`. A committed boundary HANDOFF remains immutable but permits idempotent boundary continuation and successive product or infrastructure correction evidence before the next phase begins. Record accepted product implementation `E` and any distinct successful verification head `K` separately; bookkeeping or `K` never replaces product implementation evidence. During S10, product E freezes app/project/test bytes, descendant K may add only card-authorized evidence documents and required task pins, and later C records receipts/bookkeeping; E, K, and C are never conflated or self-recorded.
12. A coding card may commit/push only task-owned paths to its named phase branch and trigger/inspect only its named CI workflow. At an authorized boundary, program autopilot may non-force fast-forward `main` to the exact phase-close/verification commit, verify exact-main CI, create the frozen next phase branch, and hydrate its first card. The infrastructure lane authorizes only its exact same-repository refs/workflow and allowlisted CI-harness paths; it never authorizes force-push, divergence repair, merge commit, PR, deployment, signing, TestFlight upload, App Store action, repository settings/secrets, or another external mutation.

## Canonical `CURRENT_TASK.md`

`docs/execution/CURRENT_TASK.md` is the sole active template. Every task includes program-autopilot state and exact phase/branch map; immutable phase-main base `P`; phase/card/boundary position and predecessor/main evidence; dirty-path ownership; exact pins; one outcome; environment and GitHub posture; allowed paths/operations; delta; acceptance; selectors/watchdogs; recovery conditions; boundary action; and next card. An ordinary card task includes integrated/card-base `M`, observed authority `A`, and declared `M..A`. An infrastructure task preserves historical card M/A and includes product head E, failed verification head F, post-commit-observed K, audit gate/failure/repair records and hashes, derived next support index, required commit trailers when used, exact `F..K`, ordered ref cursor/predecessors, and full exact-ref/head candidate history. Every allowed path is one fully expanded repository-relative file; globs, roots, brace/set expressions, and `/**` are invalid. CURRENT_TASK cannot make mutable prose authoritative over Git/GitHub history or weaken product acceptance, but prior candidates and records do not consume future retry/correction authority.

Freeze `P` as bootstrap `B` throughout S0 and as the prior accepted exact-main phase-close/verification SHA throughout each later phase. Within a phase, `M` is the preceding card's accepted implementation or verification head; for a phase's first card, `M=P`. At phase start, owner- or program-autopilot-prepared `A` normally changes only CURRENT_TASK. An explicit owner execution-policy amendment may update the named authority/config documents and selector-watchdog object atomically with their pins; ordinary product and hosted-CI recovery then use the persistent loop below without another message. Same-phase autopilot creates later `A` only as prior HANDOFF plus immediate-next CURRENT_TASK. Program autopilot creates next-phase `A` only after verified non-force fast-forward main plus matching green main CI and only as the first-card CURRENT_TASK commit on the frozen next branch. Fresh G0 proves the appropriate exact diff and immutable program map, then permits only frozen card-specific changes. The selector may be absent for S0.1 or equal the accepted predecessor until G0 passes, after which replacement with the current exact object is the first implementation-support mutation; an explicit watchdog migration may likewise replace it with the exact repinned object.

## Autonomous verification and correction recovery

No additional owner approval message is required for implementation or verification recovery within the current card, frozen phase/program order, named repository, refs, workflow, and allowed product or CI-harness paths.

Candidate history is append-only and has no retry or cardinality ceiling per exact workflow/ref/head. Workflow concurrency uses `cancel-in-progress: false`. If any candidate is green with complete required evidence, accept it and do not dispatch another. If one candidate is queued or running, wait for it. Otherwise inspect all terminal candidates, their complete logs, and available artifacts, then dispatch exactly one new `workflow_dispatch` candidate at the same branch ref, exact head, inputs, pinned runner/toolchain/Simulator selector, and tier. Each fresh-runner redispatch creates a new run ID; never use Actions rerun on a failed run ID. Repeat until green or until evidence identifies a repository correction. Terminal count, recurrence, overlap, ambiguity, missing artifacts, and previously used failure or repair labels are audit provenance, not authority consumption or terminal conditions.

For a diagnosed product, compiler, test, or card-acceptance failure, create one direct-child task-scoped correction commit changing only the current card's allowed product paths and required CURRENT_TASK evidence/pins, then repeat exact-head verification. Successive implementation heads are `I`, `I2`, `I3`, and so on; there is no numeric correction or rerun ceiling. The accepted product implementation `E` is the first such head with green exact-head required evidence. Never weaken the card outcome, GOLDEN, ALT-1, selectors, tests, watchdog values, evidence, or acceptance.

For a diagnosed hosted-runner, pinned-toolchain/runtime, exact-Simulator, Actions service/transport, or lane-harness failure, either redispatch the same exact head on a fresh runner or create one direct-child `K(n+1)` containing one minimal diagnosed correction. Successive K commits may refine the same operation, mechanism, or repair. Failure/repair records, hashes, trailers, prior candidates, and labels remain append-only audit provenance rather than consumption gates. There is no K, correction, or redispatch ceiling. When evidence is insufficient, gather another exact-head fresh-runner candidate; if the harness still cannot expose the cause, one diagnostic K may add non-accepting evidence collection before the next run.

Each correction commit contains one diagnosed operational delta so its result remains attributable; successive commits may address successive evidence. A K may change required CURRENT_TASK evidence/pins and the smallest causally required subset of `.github/workflows/ios-ci.yml`, `Scripts/build-smoke.sh`, `Scripts/test-smoke.sh`, `Scripts/ui-smoke.sh`, and `Scripts/run-with-timeout.sh`. Preserve HANDOFF and product/project/test/fixture/asset bytes; pinned runner/toolchain/Simulator selector semantics; exact product commands, selectors, and destinations; timeout exit behavior; result/evidence/checksum/upload enforcement; and raw aggregate accounting. The workflow's cleanup watchdogs are exact and non-accepting: Simulator readiness `900` seconds; N8 `300/600/900/0/2400`, P12 `300/600/900/900/3300`, and F25 `300/900/1200/1800/4500` for setup/build/unit/UI/total; and a 90-minute job watchdog. Exceeding one keeps that candidate non-green and feeds the same evidence-driven retry/correction loop; it is not an authority limit.

Infrastructure commits retain the seven legacy trailers—`Infrastructure-Gate`, `Infrastructure-Support-Index`, `Infrastructure-Failed-Run`, `Infrastructure-Failed-Head`, `Infrastructure-Failed-Ref`, `Infrastructure-Failure-Signature`, and `Infrastructure-Repair-Key`—when CURRENT_TASK uses them. Fresh G0 derives a positive monotonic index and verifies direct parent, run/ref/head provenance, declared paths, and E..K protected-product equality. Matching or overlapping signatures and repair keys may recur when later evidence shows the prior correction was insufficient; they never consume future correction authority. Volatile ref/run/head/time/UDID/duration/log values remain provenance only, and prose may not falsify or delete history.

CURRENT_TASK preserves ordered ref roles and exact accepted predecessors. At a boundary, verify the phase first and then main. Re-fetch immediately before every mutation. Advance phase and main only by a verified non-force fast-forward to the exact green verification head; if a ref has already reached that head, resume without another push. Unexpected movement triggers read-only fetch, ancestry/provenance inspection, and waiting or recreation of unaccepted work as a direct child of the valid lineage; never overwrite or silently reconcile unrelated history. Accept only green exact-head CI with complete checksummed artifacts. Record `E` as product implementation evidence and any distinct `K` as verification/integration/next base. If phase or exact-main verification exposes a product failure before the next phase starts, the boundary card stays active for successive task-scoped correction heads; preserve prior HANDOFF entries and append corrective evidence after green phase and exact-main verification.

Exact S0 history remains factual and immutable. K1 `0da62482db7e3f90742876ef05574de9e9569e32` phase run `31579936670` failed aggregate `727 > 720`. K2 `400f8827f5451b9a44f4d846340b51377554069d` phase run `31583957094` failed setup `232 > 120` after its boot request put exact-Simulator readiness on setup's critical path; artifact `9136413551` has digest `sha256:284632a9587fa296a36b1c57c9e9320779f022a4d68b8ff5a592305105bfaedd`. K3 `e569951909c2ee8aff4253bae0d442550c229a16` passed exact-head phase run `31590956549`; exact-main K3 run `31591804256` failed only its historical 300-second Simulator-readiness watchdog. These failed run IDs are never accepted or rerun by run ID. K4 or later recovery continues through this persistent loop. I3 remains S0.1 product implementation evidence until a diagnosed product correction is required.

A required path outside the current card or CI-harness recovery subset remains out of scope; gather evidence or continue with an in-scope correction rather than weakening acceptance. The owner-approved S10 authority amendment and its frozen V4.1 activation are not repeated approval-message gates; normal implementation, evidence, GitHub push, CI dispatch, inspection, and correction proceed autonomously inside the selected card. The loop never authorizes force-push, merge commit, PR, signing, TestFlight/App Store upload, deployment, submission, repository settings, secrets, or S9.2/S9.3.

## Phase gate loop

| Gate | Work | Exit |
|---|---|---|
| G0 Scope lock | Read only: exact pins/card/tool state; ordinary `M/A/M..A` or infrastructure `E/F/K/F..K/gate counters`; sources, paths, fixture, selectors, logical Simulator selector | Resolve the exact card/recovery route; missing or ambiguous evidence triggers re-read, re-fetch, waiting, or diagnostic collection rather than an approval stop |
| G1 Compile/launch | Minimal structure for this slice | Exact verification head builds, installs, and launches on the CI Simulator while product implementation `E` remains separately identified |
| G2 Golden slice | One deterministic end-to-end path | Targeted tests plus CI XCUITest/Simulator acceptance |
| G3 Named resilience/accessibility | Only the named alternate state and touched controls | Named recovery plus bounded automated or S9.2 physical-device check |
| G4 Integration | Only if persistence/StoreKit is named | Contract test plus unchanged golden path |
| G5 Handoff/integration | No new product behavior | Accepted product implementation plus green exact verification-head run and append-only evidence; then the authorized same-phase transition or fast-forward boundary integration, exact-main CI, and next-phase first-card authority |

## Test budget

- Normal loop on the named Actions runner: one affected-target build and one targeted unit-test run.
- Phase gate: one 5–8-checkpoint CI Simulator smoke when the task authorizes it.
- Final: fresh CI Simulator install/launch, relevant unit tests, one golden UI smoke, and one accessibility spot check; S10.5 owns the branded owner-bridged physical evidence contract, while actual signing/upload and release verification remain owner-only S9.2.
- `Scripts/ci-selection.json` has exactly the runbook Section 6 schema. The workflow rejects unknown/missing keys, wrong types, wrong tier values, duplicate/unresolved selectors, or an input mismatch. N8 = setup/evidence 300s + build 600s + targeted unit tests 900s + targeted UI 0s, `runUISmoke=false`, empty UI selector; P12 = 300s + 600s + 900s + 900s, `runUISmoke=true`, one UI selector; F25 = 300s + 900s + 1200s + 1800s, `runUISmoke=true`, one UI selector. Totals are 2400/3300/4500 seconds and cover setup through evidence validation/checksum; Simulator readiness is 900 seconds, the job watchdog is 90 minutes, and workflow concurrency uses `cancel-in-progress: false`. `run-with-timeout.sh` enforces step watchdogs. Required logs, `.xcresult` directories, and enabled-UI screenshot remain fail-closed acceptance evidence; a watchdog or evidence failure feeds persistent retry/correction rather than consuming authority.
- Do not run fuzzing, exhaustive device/OS/orientation/locale matrices, endurance loops, broad security scans, or a full UI suite unless the task separately authorizes them.
- A product/card timeout or failure keeps the card active. Inspect the complete failing step, raw log, and result artifact; create one diagnosed task-scoped direct-child correction, then repeat exact-head CI through `I2`, `I3`, and later heads until acceptance passes.
- A hosted-runner/image/runtime/Simulator/Actions/transport or lane-harness scheduling failure uses the persistent fresh-runner/K loop. It never permits substituting `latest`, changing the pinned environment, weakening evidence, or asking the owner for a routine authority amendment.

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
- One persistent `/goal` may traverse the frozen S0–S10.6 coding phase map, with one active card and one phase branch at a time. Each card records product implementation `E`; exact verification normally runs at `E`, or at distinct green `K` after an eligible infrastructure recovery/evidence lane. Same-phase transitions remain exact HANDOFF-plus-CURRENT_TASK bookkeeping followed by fresh G0.
- At a runbook-marked boundary, enabled program autopilot creates HANDOFF-only `C`. Remote `main=P` permits a verified non-force fast-forward; exact `main=C` resumes. Reuse a green matching candidate, wait for an active one, and otherwise dispatch one fresh-runner candidate at a time until green or until evidence calls for a diagnosed direct-child correction. Recovery verifies phase first and then main, each non-force and exact-ref gated; the next phase bases on green exact-main E/K. Unexpected collisions trigger re-fetch and provenance recovery without overwrite. S9.2/S9.3 remain owner-only.
- Figma, Sentry, PostHog, Supabase, RevenueCat, and security tooling are separate authorized tasks, not defaults.

## Phase and device rules

- The exact 42-card decomposition plus two owner-only release gates is frozen in `V4_IMPLEMENTATION_RUNBOOK.md`. CURRENT_TASK always selects one card with one golden and at most one alternate family. One `/goal` may traverse its immutable program map through S10.6 using the closed boundary state machine; it never enters `/plan`, combines cards, or enters owner-only S9.2/S9.3.
- Every current card names predecessor evidence, terminal artifact, smoke IDs, and omitted/inert future controls. The immediate next same-phase card starts only after green CI, closed transition hydration, a bookkeeping commit, and fresh G0.
- The owner's bootstrap `B` places every static authority document/template, project config, supplied `.gitattributes`, and manual `ios-ci.yml` on the default branch before S0. S0 owns the checked-in `.xcodeproj`, shared scheme, four smoke/timeout scripts, selector, and first unsigned GitHub CI baseline. Verify the S0 phase-branch ref points to its implementation SHA, dispatch that ref with `run_ui_smoke=true`, permit no intervening push, and require the run's `head_sha` to equal that commit. Do not introduce a project generator unless the task explicitly pins and authorizes it.
- Before schema freeze, only the exact task-named SwiftData delta is allowed. Reset only the exact app container in the active ephemeral CI Simulator job; never run `simctl erase all` or erase a shared/physical device.
- S1 installs the primary sign-pack manifest/loader; S3 consumes it in the runner; S4 consumes it in the renderer; S8 adds only the nonshipping second fixture.
- CI Simulator work uses deterministic photo fixtures. S10.5 separately binds owner-recorded camera hardware, true low light, physical accessibility/gesture quality, field durability, and performance evidence to exact product E through the frozen owner-operated bridge. Production-like StoreKit upload/release verification remains S9.2.
- S9.1 creates the unsigned-CI-verified unpublished candidate and inactive owner-only release workflow. S10.1–S10.6 replace only that unpublished candidate with the frozen V4.1 brand system and evidence; they remain Windows-authored/unsigned-CI-verified and never dispatch the release workflow. S9.2 is an owner-only manual workflow dispatch for archive/sign/upload of the reviewed exact branded `main` SHA under the private-solo ref rule followed by iPhone TestFlight verification. For a private repository, select a GitHub plan that supports environment secrets; do not claim a required environment-reviewer gate unless the selected plan supports it. S9.3 is owner-operated App Store Connect submission. Ordinary coding tasks never receive release secrets or mutate release state.

Official references: [Codex AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md), [Codex prompting](https://learn.chatgpt.com/docs/prompting), [Codex native iOS loop](https://learn.chatgpt.com/use-cases/native-ios-apps), [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [runner image/Xcode inventory](https://github.com/actions/runner-images), [Actions secrets](https://docs.github.com/en/actions/concepts/security/secrets), [Apple build uploads](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/), and [TestFlight](https://developer.apple.com/testflight/).
