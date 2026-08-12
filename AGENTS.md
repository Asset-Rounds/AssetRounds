# Repository Instructions

Implement only `docs/execution/CURRENT_TASK.md`. Adjacent improvements are not authorized.

## Build route

Author on Windows. Compile, test, and run the iOS Simulator only through the task-named GitHub Actions macOS workflow. “Local” describes device-local app data, not the build host. Never claim an iOS build/test result from Windows. XcodeBuildMCP and an owner-operated Mac are not required.

## Authority

1. `docs/execution/CURRENT_TASK.md` controls the active outcome, paths, environment, allowed GitHub operations, and verification budget.
2. The exact SHA-256-pinned `docs/product/BUILD_PLAN_V4.md` controls product invariants and phase order.
3. The exact SHA-256-pinned `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` controls only the selected card's sequence, files, acceptance, tests, and next card where consistent with the plan.
4. Existing tests and code describe the baseline but cannot expand scope.

The runbook is a catalog, not blanket authority. Execute only the card ID selected in CURRENT_TASK. Never select, combine, skip, or begin another card.

`docs/execution/DECISIONS.md` is history, not active authority. A decision becomes active only after the owner revises the task and, when needed, the plan hash. A task/plan-requested delta from current code or tests is not a conflict. Stop only when an invariant outside the named delta is incompatible; precedence never authorizes silently overriding a product invariant.

## Fail-closed preflight

Before editing or any mutation, stop if a required preflight task field is blank/`UNSET`; an input needed now retains a placeholder such as `<owner.reverse.domain>`; the plan/runbook path or hash differs from exact bytes; the selected runbook card does not match; predecessor evidence is incomplete; edits overlap unowned dirty work; or the recorded Windows/GitHub/runner/Xcode/runtime/tool route is unavailable.

Verify the phase branch and integrated/base SHA `M`, observe task-start authority HEAD `A`, and prove `M..A` contains only the declared authority documents. `M` is the preceding card's exact green implementation SHA within a phase, or the prior phase's exact green `main` SHA for the first card of a phase. S0.1 alone uses owner bootstrap SHA `B` as `M` and the explicit N/A predecessor-iOS-run statement. At a phase start, `A` changes only hydrated `CURRENT_TASK.md`; within a phase, `A` changes only the prior append-only `HANDOFF.md` entry plus hydrated `CURRENT_TASK.md`. `A` is observed at G0 and recorded later in HANDOFF; never attempt to write `A` into its own commit.

The owner-required sandbox, approval, command-network, trusted-config, and GitHub-tool posture must be effective. A required operation being unavailable or an unlisted external write tool being explicitly enabled/approved for this task is a stop. Mere visibility, installation, or broader credential capability is not task authority and is not by itself a blocker; never use a visible tool or a repository/ref/workflow argument that `CURRENT_TASK.md` does not name. Windows is expected; stop only when the named macOS workflow cannot provide the required verification.

## Scope

- Read the current task, exact pinned plan, and exact selected pinned runbook card before editing. Do not enter `/plan`; the active card is already planned.
- Touch only its allowed paths and stay inside its file envelope.
- Paths in `CURRENT_TASK.md` are fully expanded repository-relative paths. Apply the runbook's mechanical app-root rule before G0: app-module shorthand such as `Domain/...` becomes `FieldEvidenceApp/Domain/...`, and every brace/set expression becomes individual paths. Never guess a location. A directory ending in `/**` is recursive; otherwise only the exact path is authorized. Forbidden paths win. Count each created, changed, deleted, or renamed repo path once.
- Preserve user changes; do not reformat or refactor unrelated code.
- Reuse current navigation, models, design tokens, dependencies, fixtures, checked-in project, and shared scheme.
- Device-local and hosted product behavior require separate task IDs; hosted CI is verification, not hosted product scope.
- When explicitly authorized, stage only task-owned paths, commit, push the exact phase branch, dispatch/observe the named workflow, and download its artifacts. PR creation/merge, deployment, signing, TestFlight upload, App Store actions, and other external mutation remain forbidden unless a separate release task names them.
- Never use broad staging or include pre-existing/unowned changes.
- Do not add packages, targets, capabilities, entitlements, permissions, migrations, APIs/backends, accounts/auth, analytics, payment behavior, public metadata, deployment, or App Store submission unless the task explicitly names it.
- Later plan sections constrain compatibility but do not authorize artifacts now. Do not add unused entities, protocols, services, routes, generalized seams, stubs, or fixtures for a later slice.
- Owner-provisioned `.codex/config.toml`, `AGENTS.md`, the frozen plan, `CURRENT_TASK.md`, and `DECISIONS.md` are read-only unless explicitly named. Tool approval never expands product scope.
- Append-only `docs/execution/HANDOFF.md` is always authorized bookkeeping and excluded from the file cap, but it is never part of the implementation commit whose SHA CI verifies.
- `Scripts/ci-selection.json` is the only standing implementation support exception. Each card may replace it with the exact runbook/CURRENT_TASK selector object; it is excluded from the cap and grants no product scope. No other script is a standing exception.
- After the exact implementation-head CI run, append the handoff and stop. Do not commit or push that new entry. Within a phase, the owner reviews it and creates the next authority-preparation commit containing only that prior handoff append plus the newly hydrated `CURRENT_TASK.md`. At a runbook-marked phase boundary, the owner creates a handoff-only phase-close commit and merges once, verifies `main` points to the expected merge SHA, dispatches by the `main` ref with `run_ui_smoke=true`, permits no intervening push, and accepts only the exact matching green `head_sha` before preparing the next phase.

## Verification

- Use only the task's exact phase branch, workflow/ref, runner label, expected Xcode version/build, project/shared scheme/configuration, Simulator model/OS selector, smoke scripts, and validated selector object. Manual dispatch uses the named branch ref, never a raw SHA: first verify it points to the expected implementation SHA, allow no intervening push, and accept only a matching run `head_sha`.
- Do not run `xcodebuild` locally on Windows. Run the smallest relevant test bundle and golden XCUITest/Simulator path on the GitHub macOS runner.
- A pass must be from a successful run whose `head_sha` equals the task's implementation commit SHA `I` (or the single allowed fix SHA `I2`). Record run ID/URL, runner image, Xcode build, resolved Simulator UDID, and artifact names. An authority or phase-close bookkeeping commit is never implementation evidence.
- Use the exact task tier and `ci-selection.json` values from runbook Section 6: N8 = 90/150/240/0/480 seconds with UI false/empty; P12 = 120/180/180/240/720 with UI true/one selector; F25 = 180/240/300/780/1500 with UI true/one selector. The workflow input must match. Step ceilings and setup-through-checksum total are enforced; artifact upload remains under the 30-minute hard stop. Missing required logs, `.xcresult`, or enabled-UI screenshot fails the run.
- Inspect the complete failing step and artifacts, apply at most one concrete task-scoped fix, then rerun once. If that post-fix rerun is not green, stop regardless of whether its failure is identical.
- No exhaustive matrices, fuzzing, endurance tests, broad scans, or full UI suite unless separately authorized.

## Handoff

Before completion, read `docs/execution/KNOWN_BUGS.md`. Golden-path, regressing, or prohibited-class defects are blockers. An eligible defect can enter `KNOWN_BUGS.md` only after owner approval and explicit task authorization of that path; otherwise record it only in `HANDOFF.md`.

Record the phase/card; changed paths; integrated/base SHA `M` and its predecessor evidence; observed task-start authority SHA `A` and authority-only diff result; implementation SHA; workflow branch ref/expected head, run ID/URL/head SHA, and selector tier/input; exact commands/results; runner image/Xcode; resolved Simulator/OS/UDID; artifacts; acceptance evidence; every defect/blocker; boundary state; and the next unstarted task in `docs/execution/HANDOFF.md`. Do not self-record the future owner authority or phase-close commit that will contain this entry; the next task observes its `A`, or git history records the phase-close commit. Report the next card but never start it. Within the phase, the owner reviews and prepares the next authority-only commit on the same phase branch. Only at a runbook-marked boundary does the owner perform the branch-ref/exact-head UI-enabled main verification above.
