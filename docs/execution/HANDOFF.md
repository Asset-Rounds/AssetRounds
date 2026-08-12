# Task Handoff — append-only log

Never edit or replace an earlier entry. The block between the explicit BEGIN/END markers is an exemplar, not an entry. Copy only the content between the markers (not the markers), replace every placeholder, and append that copy after all prior entries. Never fill or edit the exemplar or an earlier entry.

<!-- BEGIN HANDOFF ENTRY TEMPLATE -->

## `<Task ID>` — `<complete | blocked | stopped — CI NOT RUN>` — `<UTC timestamp>`

- Phase ID / phase branch / card position / phase-boundary card (`yes | no`):
- Program-autopilot state / exact phase-and-branch map / final owner-only boundary:
- Phase-autopilot state / exact authorized same-phase span:
- Predecessor IDs and evidence:
- Outcome:
- Exact build-plan path / SHA-256:
- Exact implementation-runbook path / SHA-256 / selected card:
- Authoring host OS/build:
- GitHub repository / visibility and private-solo branch-control posture / base branch / phase branch:
- Immutable phase-main base SHA `P` and evidence (`S0`: bootstrap `B`; later: prior accepted exact-main phase-close SHA):
- Integrated/card-base SHA `M` and evidence (within phase: prior green implementation; phase start: `P`; `S0.1`: predecessor iOS run N/A):
- Observed task-start authority SHA `A` and `M..A` authority-only diff result:
- Implementation commit SHA (the CI `head_sha`):
- Pre-existing dirty paths and owner/disposition:
- Workflow path / workflow file SHA-256 / trigger / frozen branch ref / actual expected ref-head SHA observed after `I`/`I2` and immediately before dispatch:
- CI selector task ID / tier / `runUISmoke` / workflow input equality result:
- Actions run ID / URL / `head_sha` / conclusion:
- Runner image / Xcode version+build / minimum iOS:
- Project or workspace / target / shared scheme / configuration:
- Simulator selector and actual model / OS / UDID; UI-smoke mode:
- Allowed GitHub/MCP tool methods and exact repository/ref/workflow arguments/operations from task:
- Owner-required posture from task and G0-observed effective sandbox / approval / command-network / trusted-config / GitHub-tool state:
- Card-owned implementation commit / phase-branch push / dispatch / inspection authorizations and actions actually performed:
- Boundary recovery state observed, when applicable (`HANDOFF pending | C on phase only | main=C no run | matching run in progress | main green | next A created`):
- Owned launch-smoke IDs:
- Project/persistent-schema delta actually used:

### Changed paths

-

### Verification

| Command or smoke | Run/job | Timeout | Exit code | Actual duration | Result | Artifact/evidence path and checksum |
|---|---|---:|---:|---:|---|---|
| | | | | | | |

Confirm that the successful run's `head_sha` exactly equals the implementation commit SHA. A stale or different-revision run is not evidence. This entry is not part of that implementation commit. Same-phase autopilot may commit it with only immediate-next CURRENT_TASK. At an authorized boundary it is committed alone before verified fast-forward main integration. The entry never self-records its containing commit or the later main run; the next phase's CURRENT_TASK records the accepted main SHA/run as predecessor evidence.

### Acceptance results

- Golden path `PASS | FAIL | NOT RUN` and checkpoints:
- Named alternate `PASS | FAIL | NOT RUN` and checkpoints:
- Accessibility spot check `PASS | FAIL | N/A—N8 changed no user-facing control | NOT RUN`:
- Exact terminal screen/data artifact `PASS | FAIL | NOT RUN`:
- Future controls verified omitted/inert `PASS | FAIL | NOT RUN`:

### Known bugs or limitations

- Bug ID / severity / disposition, or `NONE`:

### Blockers

-

### Next unstarted task

- Task ID only; it was not started:
- Next gate:
  - Within phase, autopilot enabled and transition flag `yes`: if the immediate next card is inside the exact span and uniquely resolvable, Codex commits/pushes only this HANDOFF append plus that next CURRENT_TASK, then runs fresh G0; a false flag or ambiguity leaves the append uncommitted and stops.
  - Phase boundary: when program autopilot and integration are `yes`, Codex commits/pushes this HANDOFF as C. `main=P` may fast-forward once; `main=C` resumes; any other value stops. Reuse matching C CI before dispatch; after green, create only an absent mapped next branch or resume an exact valid A, then fresh G0. After S9.1, report C/run in the goal final response and stop for owner S9.2/S9.3.

<!-- END HANDOFF ENTRY TEMPLATE -->

## `S0.1` — `complete` — `2026-08-12T05:34:42Z`

- Phase ID / phase branch / card position / phase-boundary card (`yes | no`): `S0` / `phase/s0-foundation` / `1 of 1` / `yes`
- Program-autopilot state / exact phase-and-branch map / final owner-only boundary: `yes` / exact frozen S0–S9 map in `CURRENT_TASK.md` / stop after accepted S9.1 exact-main CI; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only
- Phase-autopilot state / exact authorized same-phase span: `yes` / `S0.1`
- Predecessor IDs and evidence: no earlier coding card. Initial `I=6dac0a660110b05643bcdaaf97113b75f54080a0` produced exact-head failed run `31562160165`; diagnosed fix `I2=481d272ec319d3210d0e393d20130c7c1f8f0e1a` produced exact-head failed run `31562792005`. Both built successfully but exhausted the unit ceiling during cold Simulator readiness/launch. The owner then authorized the bounded recovery authority amendment, exact `I3` relocation, and one final dispatch.
- Outcome: preserved the complete S0.1 project/app/tests/scripts/selector; moved the one exact-UDID boot-readiness command from the unit wrapper to the build wrapper before `xcodebuild`; obtained green exact-`I3` P12 CI with no other implementation change
- Exact build-plan path / SHA-256: `docs/product/BUILD_PLAN_V4.md` / `EF3C352A82F3259494DEC3D0EE68631B8B0C7385C06188D1C9184C007FC33697`
- Exact implementation-runbook path / SHA-256 / selected card: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `191187066BCD52F1C69A08F0F9795AF7D731A5CDFAC985694573B4E47A46848C` / `S0.1 — Repository and unsigned CI baseline`
- Authoring host OS/build: Microsoft Windows 11 Home, 64-bit, version `10.0.26200`, build `26200`
- GitHub repository / visibility and private-solo branch-control posture / base branch / phase branch: `palatis3/AssetRounds` / private solo repository, exact-ref/non-force-only posture / `main` / `phase/s0-foundation`
- Immutable phase-main base SHA `P` and evidence (`S0`: bootstrap `B`; later: prior accepted exact-main phase-close SHA): `c3e536a03775cc8d25f42a8e31c2f24db4390d4d`; local and live remote `main` and remote `HEAD` equaled this S0 bootstrap before boundary bookkeeping
- Integrated/card-base SHA `M` and evidence (within phase: prior green implementation; phase start: `P`; `S0.1`: predecessor iOS run N/A): recovery `M=I2=481d272ec319d3210d0e393d20130c7c1f8f0e1a`; live remote phase equaled `M` before the sole recovery push; the two exact-head failed-run records above are the recovery predecessor evidence
- Observed task-start authority SHA `A` and `M..A` authority-only diff result: `A=9590743877627cdd915a68ec581cdff88d9d6418`, a direct child of `M`; `M..A` was one commit changing exactly `AGENTS.md`, `docs/product/BUILD_PLAN_V4.md`, `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`, and `docs/execution/CURRENT_TASK.md`; `A` was never pushed separately
- Implementation commit SHA (the CI `head_sha`): recovery `I3=ac310dd37700d65165200f742aaec1d48d0a34d6`
- Pre-existing dirty paths and owner/disposition: `NONE`; G0 worktree/index/untracked state was clean
- Workflow path / workflow file SHA-256 / trigger / frozen branch ref / actual expected ref-head SHA observed after `I`/`I2` and immediately before dispatch: `.github/workflows/ios-ci.yml` / `ED3865E07A5CD25B641B75D049F4D6376EF42D8B0ABDF85570DBED6786FEF771` / `workflow_dispatch` / `phase/s0-foundation` / `ac310dd37700d65165200f742aaec1d48d0a34d6`
- CI selector task ID / tier / `runUISmoke` / workflow input equality result: `S0.1` / `P12` / `true` / `PASS`; exact frozen selector bytes used `120/180/180/240/720` and the one S0 unit plus one S0 UI selector
- Actions run ID / URL / `head_sha` / conclusion: `31566371521` / `https://github.com/palatis3/AssetRounds/actions/runs/31566371521` / `ac310dd37700d65165200f742aaec1d48d0a34d6` / `success`
- Runner image / Xcode version+build / minimum iOS: `ImageOS=macos26`, `ImageVersion=20260728.0273.1`, `ImageArch=unknown` / `Xcode 26.6`, `Build version 17F113`, `DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer` / iOS `18.0`
- Project or workspace / target / shared scheme / configuration: `FieldEvidenceApp.xcodeproj` / `FieldEvidenceApp` / `FieldEvidenceApp` / `Debug`
- Simulator selector and actual model / OS / UDID; UI-smoke mode: `iPhone 17` + `iOS 26.5` / iPhone 17 / iOS 26.5 build `23F77` / `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`; CI XCUITest P12
- Allowed GitHub/MCP tool methods and exact repository/ref/workflow arguments/operations from task: task-named read-only git/`gh` inspection; explicit-path add/commit; one non-force `git push origin HEAD:refs/heads/phase/s0-foundation`; one `gh workflow run .github/workflows/ios-ci.yml --repo palatis3/AssetRounds --ref phase/s0-foundation -f run_ui_smoke=true`; exact-run view/watch/download; boundary operations remain subject to the closed state machine
- Owner-required posture from task and G0-observed effective sandbox / approval / command-network / trusted-config / GitHub-tool state: Full access observed; `sandbox_mode=danger-full-access`; `approval_policy=never`; command network enabled; project configuration trusted; goals enabled; authenticated GitHub CLI had `repo` and `workflow` scopes; XcodeBuildMCP absent/disabled
- Card-owned implementation commit / phase-branch push / dispatch / inspection authorizations and actions actually performed: created only `I3`; proved remote phase=`M` and main=`P`; performed the one non-force phase push including local `A`+`I3`; proved remote phase=`I3`; performed exactly one recovery dispatch; inspected only the recorded failed runs and exact `I3` run; downloaded only artifact `ios-ci-31566371521-1`
- Boundary recovery state observed, when applicable (`HANDOFF pending | C on phase only | main=C no run | matching run in progress | main green | next A created`): `HANDOFF pending`; live remote phase=`I3`, live remote `main=P`, and `phase/s1-shell-design` absent at the pre-HANDOFF observation
- Owned launch-smoke IDs: `baseline`
- Project/persistent-schema delta actually used: existing checked-in S0 project/shared scheme preserved; no project or persistent-schema change in recovery

### Changed paths

- Recovery authority `A`: `AGENTS.md`
- Recovery authority `A`: `docs/product/BUILD_PLAN_V4.md`
- Recovery authority `A`: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`
- Recovery authority `A`: `docs/execution/CURRENT_TASK.md`
- Recovery implementation `I3`: `Scripts/build-smoke.sh`
- Recovery implementation `I3`: `Scripts/test-smoke.sh`
- The complete pre-existing S0.1 implementation at `M` was preserved byte-for-byte outside those two scripts, including project/shared scheme, launch app, unit/UI tests, remaining smoke scripts, asset catalog, and exact selector

### Verification

| Command or smoke | Run/job | Timeout | Exit code | Actual duration | Result | Artifact/evidence path and checksum |
|---|---|---:|---:|---:|---|---|
| Fresh recovery G0: branch/cleanliness, `A^=M`, exact four-path `M..A`, pins, selector, historical runs, live refs | local + GitHub read-only | fail closed | 0 | bounded | PASS | `A=9590743877627cdd915a68ec581cdff88d9d6418`; live phase=`M`, main=`P` |
| Exact I3 structural diff and shell syntax | local Windows read-only | fail closed | 0 | bounded | PASS | exactly 2 insertions in build + 2 deletions in unit; both `100755`, LF, `bash -n` pass; selector blob unchanged `8c57bbbf169e03aedfa560ef378444df0a16caed` |
| `bash Scripts/run-with-timeout.sh 180 bash Scripts/build-smoke.sh` | `31566371521` / `94018899512` | 180 s | 0 | 176 s | PASS — exact UDID reached terminal boot readiness, then `** TEST BUILD SUCCEEDED **` | `build-smoke.log` SHA-256 `FDAAA5E524A26523E1286BE612D063AC98E804401C78AF2B6A9CBB43EA93F6AF`; nonempty `Build.xcresult` |
| `bash Scripts/run-with-timeout.sh 180 bash Scripts/test-smoke.sh` / exact `FieldEvidenceAppTests/S0LaunchTests` | same | 180 s | 0 | 32 s step; 0.001 s test | PASS — exactly 1 non-skipped test, 0 failures | `test-smoke.log` SHA-256 `7DF998ED3725DD4CE2FD13BD616A1897BF59F962A267489E4F241C71A2821609`; nonempty `UnitTests.xcresult` |
| `bash Scripts/run-with-timeout.sh 240 bash Scripts/ui-smoke.sh` / exact `FieldEvidenceAppUITests/S0LaunchUITests` | same | 240 s | 0 | 45 s step; 16.227 s test | PASS — exactly 1 non-skipped test, 0 failures | `ui-smoke.log` SHA-256 `F2ACF3CDD1688769C504EE859445EA60420F64BD594BCE4AF4711DBC99CD0B12`; nonempty `UISmoke.xcresult`; `ui-final.png` SHA-256 `CB9AF9D5ED4B22C96B07BADC1B95461B39341644CD4D8F7AE65C5B9A505661C5` |
| Required-evidence validation, selector resolution, checksum generation/verification, and P12 budgets | same | setup/artifact 120 s; total 720 s | 0 | setup 15 s; artifact 7 s; setup+artifact 22 s; total 281 s | PASS | artifact `ios-ci-31566371521-1`, ID `9129680774`, API digest `sha256:fd5164199cfc3c58778340b2b7f52a74e68466cf53c7f9e49ad269ee8d9af03f`; `SHA256SUMS.txt` SHA-256 `F4E792415A15A20FCD126ADEE4E47149FE4F2502B3B3BF079710E5F9A1F15752`; all 89 listed payload files independently matched with no missing/unlisted/mismatch |

The successful run's `head_sha` exactly equals recovery implementation commit `I3=ac310dd37700d65165200f742aaec1d48d0a34d6`. Neither recovery authority `A` nor this HANDOFF entry is used as implementation evidence.

### Acceptance results

- Golden path `PASS` and checkpoints: exact selector/P12 validated unchanged; build-step bootstatus targeted only the resolved UDID and reached terminal readiness; shared scheme/project/deployment resolved; unsigned app/test build and `Build.xcresult` succeeded; exact unit class executed non-skipped; exact UI class launched a fresh app and proved foreground; exact root/title/subtitle IDs and labels were visible with nonempty ordered in-window frames at accessibility XXXL; zero buttons/navigation bars existed; inert root tap left content, foreground state, and frames unchanged; result bundles, required logs, screenshot, checksums, and budgets all validated.
- Named alternate `PASS` and checkpoints: `ALT-1=NONE`; the pinned runner/Xcode/runtime/device were available exactly, so no alternate was entered.
- Accessibility spot check `PASS`: title uses the exact semantic baseline contract; UI assertions proved root/title/subtitle visibility/order at accessibility XXXL, no clipped/empty frames, no interactive control, and inert-tap persistence.
- Exact terminal screen/data artifact `PASS`: the exact passing UI log/result bundle proves `AssetRounds` then `Sign Inspection`, foreground state, IDs, frame containment/order, zero controls, and post-tap persistence. The required nonempty PNG is a checksummed post-test Simulator home-screen capture and is not claimed as pixel evidence of the in-app terminal screen.
- Future controls verified omitted/inert `PASS`: test found zero buttons and navigation bars; no tab, persistence, permission, pack, report, commerce, signing, or later-card behavior was added.

### Known bugs or limitations

- Bug ID / severity / disposition, or `NONE`: `NONE`. Evidence-quality limitation only: `ui-final.png` was captured after XCUITest teardown and shows SpringBoard; the frozen contract requires a nonempty screenshot while the exact in-app checkpoints are separately proven by the successful UI test/log/result bundle. No product defect, blocker, or accepted `KNOWN_BUGS.md` entry results.
- Nonblocking pinned-tool diagnostics only: destination architecture ambiguity, AppIntents metadata skip, XCTest framework strip notices, UI-runner launch-metric/duplicate accessibility-class/LLDB-version diagnostics; no build error, crash, assertion failure, or acceptance regression.

### Blockers

- `NONE`

### Next unstarted task

- Task ID only; it was not started: `S1.1`
- Next gate:
  - This is an S0 phase boundary. Before the HANDOFF-only phase-close push, re-prove remote phase=`I3` and remote main=`P`; commit only this append as `C`, non-force push, and prove remote phase=`C`.
  - Continue only through the exact boundary state machine in `CURRENT_TASK.md`: accept only the permitted `main=P→C` fast-forward or exact `main=C` resume, reuse any matching main/head=`C` workflow-dispatch candidate before dispatching, require UI-enabled exact-main success, then create or resume only the frozen `phase/s1-shell-design` first-card authority and run fresh G0.

## `S1.1` — `complete` — `2026-08-12T15:35:05Z`

- Phase ID / phase branch / card position / phase-boundary card (`yes | no`): `S1` / `phase/s1-shell-design` / `1 of 1` / `yes`
- Program-autopilot state / exact phase-and-branch map / final owner-only boundary: `enabled through accepted S9.1` / exact frozen S0–S9 map in `CURRENT_TASK.md` / stop after accepted S9.1 exact-main CI; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only
- Phase-autopilot state / exact authorized same-phase span: `enabled` / `S1.1 only`
- Predecessor IDs and evidence: accepted S0 verification/phase-close head `5b826bd6a9f59318f5a161103f3d93a20c46f438`; phase run `31597722994` and exact-main run `31598703886` both succeeded at that exact head with P12/UI and complete independently verified 91-entry artifacts
- Outcome: created the Signs/Reports shell with Settings toolbar gear, literal Worklight Precision token assets/components, strict exact `IlluminatedSignPack@1` loader and complete isolated sample; invalid/unknown content fails closed locally; proved accessibility XXXL in actual Light and Dark rendering and exported the exact named retained Dark app attachment as terminal screenshot
- Exact build-plan path / SHA-256: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`
- Exact implementation-runbook path / SHA-256 / selected card: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / `S1.1 — Shell, Worklight Precision, and exact pack`
- Authoring host OS/build: Microsoft Windows 11 Home, 64-bit, version `10.0.26200`, build `26200`
- GitHub repository / visibility and private-solo branch-control posture / base branch / phase branch: `palatis3/AssetRounds` / private solo repository, exact-ref/non-force-only posture / `main` / `phase/s1-shell-design`
- Immutable phase-main base SHA `P` and evidence (`S0`: bootstrap `B`; later: prior accepted exact-main phase-close SHA): `5b826bd6a9f59318f5a161103f3d93a20c46f438`; accepted S0 exact-main head/run `31598703886`
- Integrated/card-base SHA `M` and evidence (within phase: prior green implementation; phase start: `P`; `S0.1`: predecessor iOS run N/A): `M=P=5b826bd6a9f59318f5a161103f3d93a20c46f438`; first S1 card began from the accepted S0 exact-main phase-close head
- Observed task-start authority SHA `A` and `M..A` authority-only diff result: `A=05b54998af701c0ffb3981b9328ef1cb7d70155b`, a direct child of `M`; `M..A` was one commit changing exactly `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` and `docs/execution/CURRENT_TASK.md`
- Implementation commit SHA (the CI `head_sha`): accepted product implementation `E=I4=2b9c921e545536d13712c85015d4b0d2f9fb780b`; accepted nonproduct verification head `K=88f8b69ad9262f47e2b00511fab4b73b745c0168`, a direct child of `E`
- Pre-existing dirty paths and owner/disposition: `NONE`; G0 worktree/index/untracked state was clean
- Workflow path / workflow file SHA-256 / trigger / frozen branch ref / actual expected ref-head SHA observed after `I`/`I2` and immediately before dispatch: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch` / `phase/s1-shell-design` / accepted verification ref head `88f8b69ad9262f47e2b00511fab4b73b745c0168`
- CI selector task ID / tier / `runUISmoke` / workflow input equality result: `S1.1` / `P12` / `true` / `PASS`; exact object used `300/600/900/900/3300`, unit selector `FieldEvidenceAppTests/S1PackTokenTests`, UI selector `FieldEvidenceAppUITests/S1ShellUITests`
- Actions run ID / URL / `head_sha` / conclusion: accepted verification run `31611775614` / `https://github.com/palatis3/AssetRounds/actions/runs/31611775614` / `88f8b69ad9262f47e2b00511fab4b73b745c0168` / `success`; product run `31610009321` at `E` also succeeded but its post-teardown `ui-final.png` remained SpringBoard and was not terminal visual acceptance
- Runner image / Xcode version+build / minimum iOS: `ImageOS=macos26`, `ImageVersion=20260728.0273.1`, `ImageArch=unknown` / `Xcode 26.6`, `Build version 17F113`, `DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer` / iOS `18.0`
- Project or workspace / target / shared scheme / configuration: `FieldEvidenceApp.xcodeproj` / `FieldEvidenceApp` / `FieldEvidenceApp` / `Debug`
- Simulator selector and actual model / OS / UDID; UI-smoke mode: `iPhone 17` + `iOS 26.5` / iPhone 17 / iOS 26.5 / `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`; P12 XCUITest at accessibility XXXL in explicit Light and Dark test modes
- Allowed GitHub/MCP tool methods and exact repository/ref/workflow arguments/operations from task: task-named read/fetch/ref/run/workflow/artifact inspection; explicit-path add/commit; non-force phase create/push to `refs/heads/phase/s1-shell-design`; named `.github/workflows/ios-ci.yml` workflow dispatch on that branch with `run_ui_smoke=true`; exact-run observation/download; boundary phase/main operations remain subject to the closed state machine
- Owner-required posture from task and G0-observed effective sandbox / approval / command-network / trusted-config / GitHub-tool state: Full access observed; `sandbox_mode=danger-full-access`; `approval_policy=never`; command network enabled; trusted repository configuration active; authenticated GitHub CLI available; XcodeBuildMCP and owner-operated Mac unnecessary
- Card-owned implementation commit / phase-branch push / dispatch / inspection authorizations and actions actually performed: created append-only direct-child sequence `I=5de55ff2e6d4abc2619e07324e383c46143d32f5`, `I2=2e54716ac27c93a6e53e693a957602a23db9e287`, `I3=8c187203d928adc01dc0ef65d715e0a705a6e08d`, `E=I4=2b9c921e545536d13712c85015d4b0d2f9fb780b`, and nonproduct `K=88f8b69ad9262f47e2b00511fab4b73b745c0168`; non-force pushed each exact phase head, dispatched one fresh candidate per head, inspected complete logs/artifacts, and accepted only exact `K`
- Boundary recovery state observed, when applicable (`HANDOFF pending | C on phase only | main=C no run | matching run in progress | main green | next A created`): `HANDOFF pending`; remote phase=`K`, remote `main=P`, and next phase branch remained unstarted at handoff preparation
- Owned launch-smoke IDs: `--s1-invalid-pack`, `--s1-ui-test-light-mode`, `--s1-ui-test-dark-mode`; accessibility IDs `s1.shell.screen`, `s1.settings.button`, `s1.settings.screen`, `s1.sample.scroll`, `s1.reports.placeholder`, `s1.pack.unavailable`, and `s1.sample.disclaimer`
- Project/persistent-schema delta actually used: `NONE`; no project, target, package, capability, permission, persistence, or schema change

### Changed paths

- Product/test/support `A..E`: `FieldEvidenceApp/App/FieldEvidenceAppApp.swift`
- `FieldEvidenceApp/DesignSystem/DesignTokens.swift`
- `FieldEvidenceApp/DesignSystem/WorklightComponents.swift`
- `FieldEvidenceApp/Domain/Packs/SignPack.swift`
- `FieldEvidenceApp/Domain/Packs/SignPackLoader.swift`
- `FieldEvidenceApp/Features/Sample/PackSampleView.swift`
- `FieldEvidenceApp/Features/Shell/AppShellView.swift`
- `FieldEvidenceApp/Resources/Packs/IlluminatedSignPack.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightAccentContainer.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightAttentionContainer.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightAttentionText.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightBlockedContainer.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightBlockedText.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightCanvas.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightCompleteContainer.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightCompleteText.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightEssentialControlStroke.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightInformationContainer.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightInformationText.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightInteractionAccent.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightOnAccent.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightOnAccentContainer.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightPrimaryText.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightRaisedSurface.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightSecondaryText.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightSurface.colorset/Contents.json`
- `FieldEvidenceApp/Resources/Assets.xcassets/WorklightTertiaryText.colorset/Contents.json`
- `FieldEvidenceAppTests/S1PackTokenTests.swift`
- `FieldEvidenceAppUITests/S1ShellUITests.swift`
- `Scripts/ci-selection.json`
- Verification-only `E..K`: `Scripts/ui-smoke.sh`; product/project/test/fixture/asset/selector bytes equal `E`

### Verification

| Command or smoke | Run/job | Timeout | Exit code | Actual duration | Result | Artifact/evidence path and checksum |
|---|---|---:|---:|---:|---|---|
| Fresh G0: branch/cleanliness, `A^=M`, exact two-path `M..A`, pins/map/environment/selector/live refs | local + GitHub read-only | fail closed | 0 | bounded | PASS | `A=05b54998af701c0ffb3981b9328ef1cb7d70155b`; phase created from `M=P` |
| Exact product and recovery structure | local Windows read-only | fail closed | 0 | bounded | PASS | `E..K` changes only executable `Scripts/ui-smoke.sh`; `bash -n` and `git diff --check` pass; protected product/project/test/fixture/asset/selector/workflow bytes unchanged |
| Initial exact `I` P12 candidate | `31602296616` / `94132488633` | UI 900 s | nonzero | UI test 496.512 s | FAIL — build and 4 units green; UI could not scroll to `access_lost | I lost safe access`; led directly to `I2` traversal correction | artifact `ios-ci-31602296616-1`, ID `9144382990`, API digest `sha256:6aa40c78e6f6b224eb011707b69ec19909a38edc06ff1ae6e367cfe2f1a13379` |
| Exact `I2` P12 candidate | `31605048780` / `94141741045` | UI 900 s | nonzero | UI test 150.733 s | FAIL — traversal fixed; exact Settings semantic control height `36` was below `44`; led directly to `I3` | artifact `ios-ci-31605048780-1`, ID `9145176693`, API digest `sha256:726d3166dbdf564258a4480767629b0531f22e7c746346c12049845d34ccd161` |
| Exact `I3` P12 candidate | `31606827272` / `94147823643` | P12 | 0 | workflow 848 s | NON-ACCEPTING despite workflow success — build/unit/UI assertions passed, but independent visual audit found SpringBoard `ui-final.png` and a light-palette retained attachment mislabeled Dark (`#F3F5F6` canvas / `#FFFFFF` surface) | artifact `ios-ci-31606827272-1`, ID `9145978177`, API digest `sha256:6bfbb1feee30a6b8811abd0f780e68dc4b3ce505eb96658c4b75c662f64a3ef8`; 99 checksums |
| Exact product `E=I4` P12 candidate | `31610009321` / `94158648499` | P12 | 0 | workflow 772 s; UI 250.008 s | PRODUCT PASS — explicit test-only Light/Dark environment probes passed, retained attachment visually proved actual Dark/XXXL app; post-teardown `ui-final.png` still SpringBoard, requiring nonproduct K export | artifact `ios-ci-31610009321-1`, ID `9147224666`, API digest `sha256:00144c930df3f71f0760a50a1476a920909ac5692cf8137d0c61510c3552b710`; retained dark PNG SHA-256 `78CE6B46000782B3DA5FB0AF3DD37C98E16B788F758260A97772AB3DB8EB6280`; all 99 checksum entries matched |
| `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh` | accepted `31611775614` / `94164624112` | 600 s | 0 | step 306 s with parallel readiness | PASS — unsigned exact-destination `** TEST BUILD SUCCEEDED **` | `build-smoke.log` SHA-256 `BE3148254032AE0B937A3543918F6A9C40C9B2301D8C218AA302614783110012`; nonempty `Build.xcresult` |
| `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh` / exact `FieldEvidenceAppTests/S1PackTokenTests` | same | 900 s | 0 | step 161 s; tests 0.029 s | PASS — exactly 4 non-skipped tests, 0 failures | `test-smoke.log` SHA-256 `0F37E47D2A2390E7172881670B84F2AEAAC9E665CBB82523A7BDB2182D0C58BD`; nonempty `UnitTests.xcresult` |
| `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh` / exact `FieldEvidenceAppUITests/S1ShellUITests` | same | 900 s | 0 | step 331 s; test 206.051 s | PASS — exact UI test, actual Light and Dark probes, named attachment export, 0 failures | `ui-smoke.log` SHA-256 `2BB7EFEA567924CF0F275B44A7683288971B4FDC41FB6B68CAADFD69687F869D`; nonempty `UISmoke.xcresult`; exported `ui-final.png` SHA-256 `733E8941299DE69058FE5B63292ED5FA2CAE900607CB41BBD95AB8A5BACB8F56` |
| Required-evidence/checksum validation and P12 budgets | same | setup/artifact 300 s; readiness 900 s; total 3300 s | 0 | setup 16 s; readiness 143 s; artifact 0 s; setup+artifact 16 s; total 819 s | PASS | artifact `ios-ci-31611775614-1`, ID `9148006723`, API digest `sha256:815d415fa951d3b76baad82d6719bc218d9e77b21234ea74aa90ed84b8fa7f80`; `SHA256SUMS.txt` SHA-256 `0DB92CE7CBC17B3188E058E723E061016EDCD38B54DE213540D09E579D95B039`; all 99 listed payload files independently matched with no missing/unlisted/mismatch |

The accepted verification run's `head_sha` exactly equals `K=88f8b69ad9262f47e2b00511fab4b73b745c0168`. Product implementation remains `E=2b9c921e545536d13712c85015d4b0d2f9fb780b`; `E..K` is only the diagnosed screenshot-export harness correction, so K is verification/integration/next-base evidence rather than replacement product implementation. This HANDOFF entry is not part of either head.

### Acceptance results

- Golden path `PASS` and checkpoints: Signs and Reports are the only tabs; Settings is a toolbar gear and not a tab; exact pack ID/schema/content version, nouns, evidence purpose keys/displays/instructions, acknowledgements, issue registry, CNV registry, stage/outcome displays, and disclaimer all render in the isolated sample; Reports round-trip works; Settings has a semantic/hittable `44×44` minimum target; explicit shell probes prove actual `Light` and `Dark` environments at accessibility XXXL.
- Named alternate `PASS` and checkpoints: malformed payload launched with `--s1-invalid-pack` produces exactly one local `Content unavailable` / `No partial or guessed content is shown.` surface, with no tab bar or partial sample; unit matrix rejects missing, extra, duplicate, unknown-version, and drifted content without fallback or remote recovery.
- Accessibility spot check `PASS`: exact P12 UI test proved accessibility XXXL, semantic two-tab navigation, hittable Signs/Reports/Settings controls, Settings `>=44×44`, complete sample traversal, exact terminal disclaimer, and Light/Dark shell usability.
- Exact terminal screen/data artifact `PASS`: accepted `ui-final.png` is a byte-for-byte copy of the sole exact named retained attachment `S1 Worklight shell — Dark accessibility XXXL` in `UISmoke.xcresult`; independent visual inspection showed the foreground AssetRounds Signs shell in actual Dark mode at accessibility XXXL, Worklight canvas pixel `#0B1114`, card `#1A252A`, toolbar gear, and Signs/Reports tab bar; SHA-256 `733E8941299DE69058FE5B63292ED5FA2CAE900607CB41BBD95AB8A5BACB8F56`.
- Future controls verified omitted/inert `PASS`: no SwiftData, runner/check execution, reports/PDF production behavior, camera/media, generic workflow/pack engine, remote pack, persistence, commerce, packages, permissions, project-file change, or future Settings behavior was added; Settings remains an explicit sample-unavailable surface and Reports remains a saved-reports placeholder.

### Known bugs or limitations

- Bug ID / severity / disposition, or `NONE`: `NONE`. Historical evidence-quality failures were corrected before acceptance: run `31606827272` falsely appeared green while its dark-named attachment was light and `ui-final.png` was SpringBoard; run `31610009321` proved the product's actual Dark render but its post-XCUITest screenshot still captured SpringBoard. `K` now deterministically selects exactly one non-failure PNG attachment by exact test ID/name, validates safe exported filename and PNG magic, copies it to `ui-final.png`, and byte-compares source/destination; accepted run `31611775614` proved the correction. No `KNOWN_BUGS.md` entry is required.
- Nonblocking pinned-tool diagnostics only: destination architecture ambiguity, AppIntents metadata skip, XCTest framework strip notices, UI-runner launch-metric/duplicate accessibility-class/LLDB-version diagnostics; no build error, crash, assertion failure, or acceptance regression.

### Blockers

- `NONE`

### Next unstarted task

- Task ID only; it was not started: `S2.1`
- Next gate:
  - This is the S1 phase boundary. Before the HANDOFF-only phase-close push, re-prove remote phase=`K` and remote main=`P`; commit/push only this append as `C`, then accept exact phase/head P12 verification at `C` or a later diagnosed nonproduct K.
  - After green phase verification, non-force fast-forward `main` from exact `P` to that exact green verification head, require successful exact-main P12/UI evidence, then create only `phase/s2-persistence-signs`, hydrate only S2.1, and run fresh G0.

## `S2.1` — `complete` — `2026-08-12T17:30:40Z`

- Phase ID / phase branch / card position / phase-boundary card (`yes | no`): `S2` / `phase/s2-persistence-signs` / `1 of 2` / `no`
- Program-autopilot state / exact phase-and-branch map / final owner-only boundary: `enabled through accepted S9.1` / exact frozen S0–S9 map in `CURRENT_TASK.md` / stop after accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only
- Phase-autopilot state / exact authorized same-phase span: `enabled` / `S2.1,S2.2`
- Predecessor IDs and evidence: accepted S1 verification/phase-close head `8d5b0a7a2648589586b72e31dfe5dfc70eea63bd`; exact S1 phase run `31613512833` and exact-main run `31614912784` both succeeded at that head with P12/UI and complete independently verified 99-entry artifacts
- Outcome: added only exact Site/Asset SwiftData models, canonical immutable-generation roots/current and retired pointers, the main-actor `StoreSessionCoordinator`, exact `DiagnosticsV1` storage, frozen startup ordering, and the minimal write-blocking `StartupMaintenanceView`
- Exact build-plan path / SHA-256: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`
- Exact implementation-runbook path / SHA-256 / selected card: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / `S2.1 — Persistence roots, generation seam, and diagnostics`
- Authoring host OS/build: Microsoft Windows Home, 64-bit, version `10.0.26200`, build `26200`
- GitHub repository / visibility and private-solo branch-control posture / base branch / phase branch: `palatis3/AssetRounds` / private solo, exact-ref/non-force-only / `main` / `phase/s2-persistence-signs`
- Immutable phase-main base SHA `P` and evidence: `8d5b0a7a2648589586b72e31dfe5dfc70eea63bd`; accepted S1 exact-main run `31614912784`
- Integrated/card-base SHA `M` and evidence: initial S2.1 `M=P=8d5b0a7a2648589586b72e31dfe5dfc70eea63bd`; first S2 card began from the accepted S1 exact-main phase-close head
- Observed task-start authority SHA `A` and `M..A` authority-only diff result: `A=1548a12f107c1d5b6a62745645734e518005b78b`, a direct child of M; `M..A` was one commit changing exactly `docs/execution/CURRENT_TASK.md`
- Implementation commit SHA: initial `I=13b063ed3b836684d4939359e79c61c6873f2648`; `I2=d69530957fb311da337c284d2db453d95e896d77`; `I3=ec39f3eee191d6579dc0532abbf82c9b1c9d3d45`; accepted `E=I4=92005aadbaa75c2234a44c091322db9c58a82a5a`, which becomes S2.2 next-card `M`
- Pre-existing dirty paths and owner/disposition: `NONE`; G0, each correction preflight, and accepted-head dispatch state were clean
- Workflow path / workflow file SHA-256 / trigger / frozen branch ref / actual expected head: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch` / `phase/s2-persistence-signs` / `92005aadbaa75c2234a44c091322db9c58a82a5a`
- CI selector task ID / tier / `runUISmoke` / workflow input equality result: `S2.1` / `N8` / `false` / `PASS`; exact object used `300/600/900/0/2400`, unit selector `FieldEvidenceAppTests/S2PersistenceLedgerTests`, and an empty UI selector
- Actions run ID / URL / `head_sha` / conclusion: `31622291782` / `https://github.com/palatis3/AssetRounds/actions/runs/31622291782` / `92005aadbaa75c2234a44c091322db9c58a82a5a` / `success`
- Actions job ID / conclusion: `94199863326` / `success`
- Runner image / Xcode version+build / minimum iOS: `ImageOS=macos26`, `ImageVersion=20260728.0273.1`, `ImageArch=unknown` / `Xcode 26.6`, `Build version 17F113`, `DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer` / iOS `18.0`
- Project or workspace / target / shared scheme / configuration: `FieldEvidenceApp.xcodeproj` / `FieldEvidenceApp` / `FieldEvidenceApp` / `Debug`
- Simulator selector and actual model / OS / UDID; UI-smoke mode: `iPhone 17` + `iOS 26.5` / iPhone 17 / iOS 26.5 / `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`; N8 with UI disabled
- Allowed GitHub/MCP tool methods and exact repository/ref/workflow arguments/operations from task: task-named read/fetch/ref/run/workflow/artifact inspection; explicit-path add/commit; non-force phase create/push to `refs/heads/phase/s2-persistence-signs`; named `.github/workflows/ios-ci.yml` dispatch on that branch with `run_ui_smoke=false`; exact-run observation/download; no main mutation during S2.1
- Owner-required posture from task and G0-observed effective sandbox / approval / command-network / trusted-config / GitHub-tool state: Full access observed; `sandbox_mode=danger-full-access`; `approval_policy=never`; command network enabled; trusted repository configuration active; authenticated GitHub CLI available; XcodeBuildMCP and owner-operated Mac unnecessary
- Card-owned implementation commit / phase-branch push / dispatch / inspection actions: created and non-force pushed append-only direct children I, I2, I3, and I4; dispatched one exact candidate per head; inspected complete terminal diagnostics and artifacts; accepted only exact I4
- Boundary recovery state: accepted S2.1 HANDOFF pending; remote phase=`I4`, remote `main=P`, and S2.2 was unstarted before this append
- Owned identifiers: `s2.startup.checking`, `s2.maintenance.screen`, `s2.maintenance.retry`, `s2.maintenance.recovery.button`, and `s2.maintenance.recovery.text`
- Project/persistent-schema delta: no project delta; schema version 1 adds only exact Site and Asset

### Changed paths

- `FieldEvidenceApp/App/FieldEvidenceAppApp.swift`
- `FieldEvidenceApp/Domain/Models/Site.swift`
- `FieldEvidenceApp/Domain/Models/Asset.swift`
- `FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift`
- `FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/StoreSessionCoordinator.swift`
- `FieldEvidenceAppTests/S2PersistenceLedgerTests.swift`
- `Scripts/ci-selection.json`
- I→I2 changed exactly `DiagnosticsStore.swift`, adding the required explicit return from `snapshot()`
- I2→I3 changed exactly `S2PersistenceLedgerTests.swift`, correcting four malformed parameterized-case tuples
- I3→I4 changed exactly `StoreGenerationFactory.swift`, classifying an absent data root as fresh-install bootstrap rather than propagating Cocoa error 260

### Verification

| Command or smoke | Run/job | Timeout | Exit code | Actual duration | Result | Artifact/evidence path and checksum |
|---|---|---:|---:|---:|---|---|
| Fresh G0: branch/cleanliness, `A^=M`, exact one-path `M..A`, pins/map/environment/selector/live refs | local + GitHub read-only | fail closed | 0 | bounded | PASS | `A=1548a12f107c1d5b6a62745645734e518005b78b`; phase and main began at M=P |
| Exact A..I4 structure and task envelope | local Windows read-only | fail closed | 0 | bounded | PASS | exactly 8 production, 1 test, and selector-exception paths; each correction is a direct child with one diagnosed delta; `git diff --check` passes |
| Initial exact-I candidate | `31619809012` / `94191508757` | N8 | nonzero | build step 136 s | FAIL — sole compiler cause was `DiagnosticsStore.swift:139:9: error: missing return in instance method expected to return 'DiagnosticsV1'`; led directly to I2 | artifact `ios-ci-31619809012-1`, ID `9150978944`, digest `sha256:1c4c4b992ed1cb594cde5063972023ead14e26cc8e99df82d85aa3818f12f83e` |
| Exact-I2 candidate | `31620710289` / `94194573194` | N8 | nonzero | build step 143 s | FAIL — product compiled, but `S2PersistenceLedgerTests.swift:464` had an expected-comma tuple syntax error; led directly to I3 | artifact `ios-ci-31620710289-1`, ID `9151299872`, digest `sha256:490001c82389c54cb3fb07baebce1ea5cd1b915aefbabf945f18441f286a3384` |
| Exact-I3 candidate | `31621397396` / `94196861555` | N8 | nonzero | build 111 s; unit step 154 s | FAIL — build passed and 11 tests executed; 6 failures traced to absent `FieldEvidenceData` incorrectly escaping bootstrap as Cocoa error 260, which also truncated startup after current-open; led directly to I4 | artifact `ios-ci-31621397396-1`, ID `9151616195`, digest `sha256:c9f14d8fb8fee064a88ff9bc96827208cb5e3738a80af177c8cb7f04825d77eb` |
| `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh` | accepted `31622291782` / `94199863326` | 600 s | 0 | 152 s | PASS — exact-destination unsigned `** TEST BUILD SUCCEEDED **` | `build-smoke.log` SHA-256 `06D5A8FA62B0D7A77337BA70D1C4040762D154E201B8C083AA1A7DC926D4C19E`; nonempty `Build.xcresult` |
| `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh` / exact `FieldEvidenceAppTests/S2PersistenceLedgerTests` | same | 900 s | 0 | 83 s; tests 1.562 s | PASS — exactly 11 non-skipped tests, 0 failures | `test-smoke.log` SHA-256 `0F1483DFD938A18E0148C2E5C6972EFE14F3F38288F92877EF45D27592ABB4AD`; nonempty `UnitTests.xcresult` |
| Required-evidence validation, selector resolution, checksum generation/verification, and N8 budgets | same | setup/artifact 300 s; readiness 900 s; total 2400 s | 0 | setup 29 s; readiness 274 s; artifact 4 s; setup+artifact 33 s; total 401 s | PASS | artifact `ios-ci-31622291782-1`, ID `9151934510`, API digest `sha256:ac59e8fe8248f66035808981eb42b4bd81e48dc8eb1cba9ceaf786ea1d4a2b52`; `SHA256SUMS.txt` SHA-256 `21805E7F09DD24409C345C86A55B143729C6E7CA3EFB27F9BC32C97A448D941F`; all 75 listed payload files independently matched with no missing, unlisted, duplicate, or mismatched file |

The accepted run's `head_sha` exactly equals `E=M=I4=92005aadbaa75c2234a44c091322db9c58a82a5a`. This HANDOFF append is not implementation evidence and does not self-record its future transition commit.

### Acceptance results

- Golden path `PASS`: exact Site/Asset values persisted through the generation named by `current.json`; canonical current/retired pointers and diagnostics round-tripped; the container released/reopened; coordinator activation changed context and monotonically advanced its UI token; startup executed Erase→Restore→current-open→finalization→deletion→media→PDF before enabling writes
- Named alternate `PASS`: parameterized malformed/missing pointer and generation cases failed closed without newest-directory guessing or mutation; pending Erase/Restore roots mapped to exact maintenance reasons; malformed diagnostics reset only diagnostics while preserving domain/pointer sentinels; all six maintenance reasons and exact fallback copy remained closed
- Accessibility spot check: N8 intentionally rejected UI execution; unit/static contract verified the exact maintenance labels, copy, closed reasons, and accessibility identifiers
- Exact terminal screen/data artifact `PASS`: N8 produced no UI screenshot by contract; canonical pointer/diagnostics bytes, exact executed-test JSON, and `UnitTests.xcresult` are the accepted data evidence
- Future controls verified omitted/inert `PASS`: no sign creation UI, workflow model, evaluation ledger, repository abstraction, restore/erase implementation, raw editor, newest-directory selection, generic recovery framework, package, permission, or remote service was added

### Known bugs or limitations

- `NONE`; `docs/execution/KNOWN_BUGS.md` was read and contains no qualifying S2.1 defect

### Blockers

- `NONE`

### Next unstarted task

- Task ID only; it was not started: `S2.2`
- Next gate: same-phase autopilot may commit and non-force push exactly this append plus the immediate-next S2.2 `CURRENT_TASK.md`, then must run fresh G0. Remote phase must still equal I4 and remote main must remain P immediately before the transition push.
