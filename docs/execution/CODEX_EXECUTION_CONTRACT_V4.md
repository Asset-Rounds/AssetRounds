# Codex iOS Execution Contract V4

Use this contract in the new application repository. It keeps Codex focused, prevents adjacent invention, and defines a small trustworthy verification loop.

## Execution route

V4 uses **Windows for Codex authoring**, a **GitHub-hosted macOS runner for every Xcode build, automated test, and Simulator check**, and **TestFlight on a physical iPhone for hardware and release verification**. “Local” and “local-first” describe device-local product data, not the build host. No owner-operated Mac, local Xcode, local Simulator, XcodeBuildMCP, or local signing identity is required.

Windows can edit and structurally inspect files but cannot prove that iOS code compiles. A build or test claim is valid only when the named GitHub Actions run is green for the exact implementation commit SHA. Ordinary CI is an unsigned Simulator job. Signing, archive, and TestFlight upload are isolated in a later owner-dispatched S9.2 workflow whose secrets are unavailable to ordinary CI.

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

1. Implement only `docs/execution/CURRENT_TASK.md`. Adjacent improvements are not authorized.
2. The task controls active scope and environment; its exact SHA-256-pinned V4 plan controls product invariants and phase order; its exact SHA-256-pinned runbook card controls the selected implementation sequence/files/acceptance/tests where consistent with the plan. The runbook is a catalog, not whole-app authority. Tests/code describe the baseline and cannot expand scope. A named task/plan delta is intended; only an incompatible invariant outside that delta stops the task.
3. Touch only allowed paths. Preserve user changes. Do not refactor or format unrelated code.
4. Reuse existing navigation, domain models, design tokens, dependencies, and fixtures.
5. Do not add a package, target, capability, entitlement, permission, migration, API, backend, analytics event/SDK, account/auth flow, payment behavior, public metadata, deployment, or App Store submission unless the task names it.
6. Device-local and hosted product behavior require separate product decisions and task IDs. Hosted CI verification does not authorize sync, accounts, teams, guests, or server behavior.
7. Use the exact phase branch, workflow/ref, runner label, expected Xcode version/build, project, shared scheme, configuration, Simulator model/OS selector, scripts, validated `ci-selection.json`, and N8/P12/F25 timeout preset. GitHub manual dispatch uses a branch name, not a raw SHA: prove that ref points to the expected implementation SHA, permit no intervening push, and accept only a run whose `head_sha` matches. Resolve the Simulator UDID inside each ephemeral job; never pin a UDID across jobs. One diagnosed fix-and-rerun is allowed; if that rerun is not green, stop.
8. Do not fix an unrelated baseline failure.
9. The append-only handoff must list phase/card/boundary state; authoring OS; integrated/base SHA `M` and predecessor evidence; observed task-start authority SHA `A` plus authority-only `M..A` result; repository/phase branch and implementation SHA; workflow path/run ID/URL/head SHA; runner image/Xcode; resolved Simulator/OS/UDID; artifacts; exact commands/results; dirty/changed paths; defects; and next unstarted card. It never records the future owner commit that will contain the entry. The next G0 observes a within-phase authority commit; git history records a phase-close commit. Never create a self-referential SHA field.
10. Before mutation, fail closed on a required preflight `UNSET`, needed placeholder, plan/runbook hash or selected-card mismatch, incomplete predecessor, non-authority path in `M..A`, overlapping unowned dirty work, unavailable required GitHub operation/runner/Xcode/runtime, or effective project posture that contradicts CURRENT_TASK. Mere visibility, installation, or broader credential capability is not task authority and is not by itself a blocker; never use an unnamed tool or repository/ref/workflow argument. An unlisted external write tool explicitly enabled/approved for the task is a stop. Later phases never authorize unused artifacts now.
11. `HANDOFF.md` is an append-only bookkeeping exception outside the file cap and is never part of the implementation commit whose SHA CI verifies. `Scripts/ci-selection.json` is the only standing implementation support exception: each card may replace it with the exact selected-card object, outside the cap, but it grants no product scope. Codex appends HANDOFF after exact-head CI and stops. Within a phase, the owner commits that prior append together with the next hydrated CURRENT_TASK as the next authority-preparation commit. At a runbook-marked boundary, the owner commits the final append alone as phase-close bookkeeping before merge. Neither commit requires a separate card CI run and neither records its own SHA in its content.
12. A coding card may commit and push only task-owned paths to its named phase branch and trigger/inspect only its named CI workflow when `CURRENT_TASK.md` authorizes each operation. Codex never merges. PR/merge, deployment, signing, TestFlight upload, App Store action, and any other external mutation require separate explicit authority.

## Canonical `CURRENT_TASK.md`

`docs/execution/CURRENT_TASK.md` is the sole active-task template. It must include phase/card/boundary position and predecessor evidence; integrated/base SHA `M`; declared authority-only `M..A` paths (with `A` observed at G0, not self-recorded); dirty-path ownership; exact plan path/hash/headings; exact runbook path/hash/selected card; one observable outcome; Windows authoring and GitHub repository/protected-base/phase-branch/workflow/runner/Xcode/project/Simulator-selector posture; allowed paths and remote operations; project/schema delta; one golden and at most one alternate family; smoke IDs; exact selector-object values/commands and timeout tier; accessibility check; stop conditions; and next unstarted card. Every allowed path is fully expanded and repository-relative; runbook app shorthand is expanded under `FieldEvidenceApp/`, and brace/set notation is expanded into individual entries.

Within a phase, `M` is the preceding card's exact green implementation SHA. For the first card in a phase, `M` is the prior phase's exact green protected-`main` SHA. S0.1 alone uses bootstrap SHA `B` as `M` and explicitly marks predecessor iOS CI N/A. At a phase start, authority commit `A` changes only hydrated CURRENT_TASK; within a phase, it changes only the prior append-only HANDOFF entry plus hydrated CURRENT_TASK. Owner-required tool posture is hydrated before the task; G0-observed posture is recorded in HANDOFF. Every other required preflight field starts as `UNSET` so preflight cannot pass accidentally.

## Phase gate loop

| Gate | Work | Exit |
|---|---|---|
| G0 Scope lock | Read only: exact plan/runbook/workflow hashes, selected card, Windows/GitHub/tool state, `M`, observed `A`, authority-only `M..A`, sources, paths, fixture, selectors, logical Simulator selector | Card is unambiguous; missing or broader authority/CI route stops |
| G1 Compile/launch | Minimal structure for this slice | Exact implementation SHA builds, installs, and launches on the CI Simulator |
| G2 Golden slice | One deterministic end-to-end path | Targeted tests plus CI XCUITest/Simulator acceptance |
| G3 Named resilience/accessibility | Only the named alternate state and touched controls | Named recovery plus bounded automated or S9.2 physical-device check |
| G4 Integration | Only if persistence/StoreKit is named | Contract test plus unchanged golden path |
| G5 Handoff | No new behavior | Green exact-implementation-SHA run, scoped diff, artifacts, and append-only evidence ready for the owner's next authority or phase-close commit |

## Test budget

- Normal loop on the named Actions runner: one affected-target build and one targeted unit-test run.
- Phase gate: one 5–8-checkpoint CI Simulator smoke when the task authorizes it.
- Final: fresh CI Simulator install/launch, relevant unit tests, one golden UI smoke, and one accessibility spot check; physical-only checks remain S9.2.
- `Scripts/ci-selection.json` has exactly the runbook Section 6 schema. The workflow rejects unknown/missing keys, wrong types, wrong tier values, duplicate/unresolved selectors, or an input mismatch. N8 = setup/evidence 90s + build 150s + targeted unit tests 240s + targeted UI 0s, `runUISmoke=false`, empty UI selector; P12 = 120s + 180s + 180s + 240s, `runUISmoke=true`, one UI selector; F25 = 180s + 240s + 300s + 780s, `runUISmoke=true`, one UI selector. Totals are 480/720/1500 seconds and cover setup through evidence validation/checksum; upload remains within the 30-minute hard stop. `run-with-timeout.sh` enforces step ceilings. Required logs, `.xcresult` directories, and enabled-UI screenshot fail closed before relative-path checksums/upload.
- Do not run fuzzing, exhaustive device/OS/orientation/locale matrices, endurance loops, broad security scans, or a full UI suite unless the task separately authorizes them.
- A timeout is the first failed attempt. Inspect the complete failing step, raw log, and result artifact; after one concrete task-scoped fix and one rerun, any non-green result stops the task.
- A runner outage or unavailable pinned image/runtime is an infrastructure blocker, not permission to substitute `latest` or a different environment silently.

## Known-bug policy

May ship: only owner-approved low-severity, non-regressing defects outside the golden path, with reproduction, workaround, owner, and revisit version. Read `KNOWN_BUGS.md` before completion and record every discovered defect in the handoff.

May not ship: primary-path crash/hang, data loss/corruption, privacy/security exposure, incorrect payment/entitlement/permission state, blocked navigation, inaccessible primary action, false completion, broken PDF, or protected CI archive/sign/upload failure.

## GitHub and tool posture

- Run CLI-first `xcodebuild` only in GitHub Actions macOS jobs. Windows edits files and inspects diffs, run logs, and artifacts; it never claims local iOS compilation.
- Do not configure or require XcodeBuildMCP. Use XCUITest and `simctl` in CI; owner-manual hardware/accessibility checks use the S9.2 TestFlight build.
- Pin the runner label, expected Xcode version/build, project/shared scheme/configuration, and Simulator model/OS selector. Each run records `ImageVersion`, the actual Xcode build, and resolved UDID, and fails on mismatch.
- Ordinary CI has `contents: read`, receives no signing secrets, and uses `CODE_SIGNING_ALLOWED=NO`. It uploads logs and `.xcresult`/screenshots even on failure.
- Use project-scoped `.codex/config.toml` with only the required GitHub tool methods where configurable. CURRENT_TASK restricts their exact repository/ref/workflow arguments. General command network remains off unless the task names bounded Git/GitHub operations; XcodeBuildMCP remains disabled. Tool visibility, installation, approval, or credential breadth never expands product or task scope.
- Before S0, owner bootstrap `B` on the default branch contains all static authority documents/templates, the unhydrated CURRENT_TASK template, owner-created project config, `.gitattributes`, and `ios-ci.yml`. A manual dispatch cannot start until the workflow exists there. `B` has no project/scripts and therefore no predecessor iOS run. The S0 phase branch starts from `B`; its `A` commit changes only hydrated CURRENT_TASK.
- GitHub branch push, workflow dispatch/inspection, and artifact download are verification actions only when the task names them. PR merge and TestFlight/App Store actions remain separately authorized.
- One runbook phase uses one phase branch. Within a phase, each card receives exact-head CI on implementation SHA `I`/`I2`. After owner review, the next authority commit contains only the prior HANDOFF append plus the next hydrated CURRENT_TASK; the next card uses the prior green implementation SHA as `M`. No main merge or main CI occurs between cards in the same phase.
- At a runbook-marked phase boundary, the owner commits the final HANDOFF append alone and merges the phase branch once. The owner verifies protected `main` points to the expected merge SHA, dispatches by the `main` branch ref with `run_ui_smoke=true`, permits no intervening push, and accepts only a green run with that exact `head_sha`. The first card of the next phase uses that SHA as `M`; its `A` changes only hydrated CURRENT_TASK. Codex never merges.
- Figma, Sentry, PostHog, Supabase, RevenueCat, and security tooling are separate authorized tasks, not defaults.

## Phase and device rules

- The exact 36-card decomposition plus two owner-only release gates is frozen in `V4_IMPLEMENTATION_RUNBOOK.md`. Each `CURRENT_TASK` selects one card with one golden path and at most one alternate/failure family; Codex uses one `/goal`, never enters `/plan`, and never combines or starts the next card.
- Every task names predecessor evidence, exact terminal artifact, owned launch-smoke IDs, and future controls that remain omitted/inert. Report but never start the next task.
- The owner's bootstrap `B` places every static authority document/template, project config, supplied `.gitattributes`, and manual `ios-ci.yml` on the default branch before S0. S0 owns the checked-in `.xcodeproj`, shared scheme, four smoke/timeout scripts, selector, and first unsigned GitHub CI baseline. Verify the S0 phase-branch ref points to its implementation SHA, dispatch that ref with `run_ui_smoke=true`, permit no intervening push, and require the run's `head_sha` to equal that commit. Do not introduce a project generator unless the task explicitly pins and authorizes it.
- Before schema freeze, only the exact task-named SwiftData delta is allowed. Reset only the exact app container in the active ephemeral CI Simulator job; never run `simctl erase all` or erase a shared/physical device.
- S1 installs the primary sign-pack manifest/loader; S3 consumes it in the runner; S4 consumes it in the renderer; S8 adds only the nonshipping second fixture.
- CI Simulator work uses deterministic photo fixtures. Camera hardware, true low light, physical VoiceOver/gesture quality, and production-like StoreKit checks are separately named S9.2 gates on the TestFlight iPhone build.
- S9.1 is the final Windows-authored, unsigned-CI-verified coding task and may create the inactive protected release workflow. S9.2 is an owner-only manual workflow dispatch for archive/sign/upload of the reviewed protected-`main` SHA followed by iPhone TestFlight verification. For a private repository, select a GitHub plan that supports environment secrets; do not claim a required environment-reviewer gate unless the selected plan supports it. S9.3 is owner-operated App Store Connect submission. Ordinary coding tasks never receive release secrets or mutate release state.

Official references: [Codex AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md), [Codex prompting](https://learn.chatgpt.com/docs/prompting), [Codex native iOS loop](https://learn.chatgpt.com/use-cases/native-ios-apps), [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [runner image/Xcode inventory](https://github.com/actions/runner-images), [Actions secrets](https://docs.github.com/en/actions/concepts/security/secrets), [Apple build uploads](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/), and [TestFlight](https://developer.apple.com/testflight/).
