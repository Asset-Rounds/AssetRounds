# Current Task

- Phase / card ID and global order: `UNSET`
- Card position in phase / runbook-marked phase boundary: `UNSET` / `yes | no` → `UNSET`
- Predecessor card IDs: `UNSET`
- Required predecessor evidence: `UNSET` (within phase: prior card HANDOFF plus exact green implementation SHA/run; phase start: prior phase exact green `main` SHA/run; `S0.1`: exactly `N/A—first implementation; project/scripts do not exist yet`)
- Integrated/base SHA `M`: `UNSET` (within phase: preceding card's exact green implementation SHA; phase start: prior phase's exact green `main` SHA; `S0.1`: owner bootstrap SHA `B`)
- Task-start authority HEAD `A`: `OBSERVE AT G0; record in HANDOFF, never self-record here`
- Required `M..A` authority-only path set and expected diff: `UNSET` (phase start/S0.1: hydrated `docs/execution/CURRENT_TASK.md` only; within phase: prior append-only `docs/execution/HANDOFF.md` entry plus hydrated `CURRENT_TASK.md` only)
- Pre-existing dirty paths and owner/disposition: `UNSET`
- Build-plan path: `docs/product/BUILD_PLAN_V4.md`
- Build-plan SHA-256 over exact bytes: `UNSET`
- Exact plan heading anchors: `UNSET`
- Implementation-runbook path: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`
- Implementation-runbook SHA-256 over exact bytes: `UNSET`
- Selected runbook card ID and heading anchor: `UNSET`
- Outcome: `UNSET`
- Product mode: `single-user, device-local V4`
- Starting fixture/state: `UNSET`
- Execution route: `Windows authoring → GitHub Actions macOS verification`
- Authoring host OS/build: `Windows UNSET`
- GitHub repository / visibility and branch-control posture / base branch / phase branch: `UNSET` (approved posture: private solo repository; no server-enforced `main` protection required; Codex push/merge/force-push/write to `main` forbidden; owner-only `main` writes)
- CI workflow path / workflow file SHA-256 / trigger / branch ref: `UNSET` (the branch ref is frozen at hydration/G0; manual dispatch never accepts a raw SHA as `ref`)
- Dispatch-head rule: immediately before dispatch, verify the frozen branch ref points to the implementation commit just created by this task (`I`, or the one allowed fix `I2`), permit no intervening push, and require the run's returned `head_sha` to equal that commit. `A` never contains this future SHA; record the actual expected/ref-head SHA only in `HANDOFF.md` after the implementation commit exists.
- Hosted-macOS runner label / expected Xcode version+build: `UNSET`
- Minimum iOS deployment target: `18.0` (fixed by the V4 plan; changing it requires a plan revision)
- Project or workspace / target / shared scheme / configuration: `UNSET`
- CI Simulator model / OS selector: `UNSET` (UDID resolves per ephemeral job)
- UI-smoke mode: `NOT REQUIRED (N8) | CI XCUITest (P12/F25) | owner TestFlight manual (S9.2 only)` → `UNSET`
- Allowed GitHub/MCP tool methods and exact repository/ref/workflow arguments/operations: `UNSET` (`XcodeBuildMCP = disabled`; visible or installed tools are not authority)
- Owner-required sandbox / approval / command-network / trusted-config / GitHub-tool posture: `UNSET`
- G0 observation rule: Codex records the actual effective posture in HANDOFF. Stop if a required operation is unavailable, the effective project posture contradicts the owner-required posture, or an unlisted external write tool is explicitly approved/enabled for this task. Mere visibility, installation, or broader credential capability is not authority; never use an unnamed tool or argument.
- Task-owned implementation commit authorized: `yes | no` → `UNSET`
- Exact phase-branch push authorized: `yes | no` → `UNSET` (authorization never includes a push or write to `main`)
- Named CI workflow dispatch authorized: `yes | no` → `UNSET`
- Named run inspection + artifact download authorized: `yes | no` → `UNSET`
- PR creation/merge, any Codex write to `main`, deployment, signing, TestFlight upload, App Store, and other external mutation: `forbidden unless this owner-release gate names the exact operation`; the private-solo rule never authorizes Codex to write `main`
- Required verification tier: `N8 | P12 | F25` → `UNSET`

## Allowed paths

- `UNSET`
- `docs/execution/HANDOFF.md` (append-only bookkeeping exception; excluded from cap)
- `Scripts/ci-selection.json` (exact selected-card CI object only; standing support exception excluded from cap; grants no product scope)

Every entry above must be a fully expanded repository-relative path. Expand runbook app-module shorthand under `FieldEvidenceApp/` and expand brace/set notation into individual entries before committing this task. No shorthand is active authority.

## Forbidden paths

- Project settings, entitlements, packages, backend, signing, and release files unless named above.
- Adjacent feature folders.
- Signing credentials, provisioning profiles, `.p8`/`.p12` files, and real customer data in repository files, logs, fixtures, or artifacts.

## Project and persistence delta

- Project integration mode: `none | file references only | named setting delta | S0 checked-in project/shared scheme` → `UNSET`
- Exact permitted project-file semantic delta: `UNSET`
- Persistent-schema delta: `none | exact named models/fields` → `UNSET`
- Disposable dev-store reset: `active CI Simulator’s exact app container only | none` → `UNSET`
- Never use `simctl erase all` or erase a shared/physical device.

## Acceptance

| ID | Precondition/reset | Ordered user actions | Expected checkpoints (5–8, not tap count) | Evidence path |
|---|---|---|---|---|
| GOLDEN | `UNSET` | `UNSET` | `UNSET` | `UNSET` |
| ALT-1 | `NONE` | `NONE` | `NONE` | `NONE` |

If this task needs a second alternate/failure family, split it into another task.

## Explicitly out of scope

- `UNSET`
- Owned launch-smoke IDs: `UNSET`
- Exact terminal screen/data artifact for this partial phase: `UNSET`
- Future controls that must be omitted or inert: `UNSET`

## Change envelope

- Maximum 10 production files and 5 test/support files unless this task says otherwise.

## Verification

- Windows structural/read-only checks: `UNSET`
- CI incremental build command: `UNSET`
- CI targeted test command with exact `-only-testing`: `UNSET`
- CI UI-smoke command/checkpoints, or `NOT REQUIRED`: `UNSET`
- Exact `ci-selection.json` object: `UNSET` (all eleven runbook Section 6 keys and values; no unknown keys)
- Exact timeout preset: `N8 = setup/artifacts 90s / build 150s / targeted unit tests 240s / targeted UI 0s (UI+accessibility execution rejected) | P12 = setup/artifacts 120s / build 180s / targeted unit tests 180s / targeted UI 240s | F25 = setup/artifacts 180s / build 240s / targeted unit tests 300s / targeted UI 780s` → `UNSET`
- Selected total workflow budget: `N8 480s (8 minutes) | P12 720s (12 minutes) | F25 1500s (25 minutes)` → `UNSET` (setup/artifact time is included; workflow hard cap is 30 minutes)
- Expected CI artifacts: nonempty `build-smoke.log`, `Build.xcresult/`, nonempty `test-smoke.log`, `UnitTests.xcresult/`, runner/toolchain/selection evidence, and relative-path `SHA256SUMS.txt`; P12/F25 additionally require nonempty `ui-smoke.log`, `UISmoke.xcresult/`, and `ui-final.png`.
- Accessibility spot check: `N/A—N8 changes no user-facing control | exact touched controls: label/trait/order, selected state, progress/error focus, 44-point target, named Dynamic Type category, and relevant Increase Contrast/Reduce Transparency/Reduce Motion state` → `UNSET`
- The selected timeout preset is fixed for the tier. A timeout is the first failed attempt; after one task-scoped fix, one rerun is the maximum and any non-green rerun stops.

## Stop and ask

- Source conflict, plan/runbook hash or selected-card mismatch, unresolved placeholder, unclear state authority, or non-authority path in `M..A`.
- Scope/file envelope exceeded.
- New package, target, entitlement, permission, migration, backend, auth, payment, analytics, signing, external service, deployment, or submission is required but unnamed.
- Missing GitHub authorization, named branch/workflow, runner/Xcode/runtime/fixture, or—only for an S9.2 release task—approved signing secret/identity.
- The Actions run is not for the exact implementation commit SHA.
- The one post-fix rerun is not green, whether or not its failure is identical.
- User work would be overwritten.

## Definition of done

- Listed acceptance passes; unlisted behavior is not claimed.
- The exact implementation commit SHA’s named Actions run builds and runs the required tests on the pinned macOS/Xcode/Simulator route.
- Smallest relevant tests pass; fresh-install/UI smoke passes only when the named tier requires it.
- Touched primary actions have useful accessibility labels, traits, and order.
- Every owned launch-smoke ID passes; no broader regression claim is made.
- Diff remains within allowed paths/envelope.
- `HANDOFF.md` records exact implementation SHA, run identity, artifacts, evidence, every known defect, phase-boundary state, and next card. It is appended after exact-head CI and is not included in the implementation commit.
- If commit/push/CI was not authorized or did not run, status is `stopped — CI NOT RUN`, never `complete`.
- Post-card owner gate, outside this Codex `/goal`: if this is not a phase-boundary card, the owner reviews the result and creates the next authority-preparation commit on the same phase branch containing only this prior HANDOFF append plus the next hydrated `CURRENT_TASK.md`. The next card uses this card's green implementation SHA as `M`, observes that authority commit as `A`, and requires no intervening main merge or iOS rerun.
- Post-card owner gate, outside this Codex `/goal`: if this is a runbook-marked phase-boundary card, the owner commits the final HANDOFF append as phase-close bookkeeping and merges the phase branch. Under the approved private-solo rule, the owner alone verifies `refs/heads/main` points to the expected merge SHA, permits no intervening push or history rewrite, dispatches that ref with `run_ui_smoke=true`, and requires a green run whose `head_sha` is exact before creating the next phase branch and its CURRENT_TASK-only `A` commit. Any unexpected ref movement stops.
- Next planned task is named but remains unstarted: `UNSET`.
