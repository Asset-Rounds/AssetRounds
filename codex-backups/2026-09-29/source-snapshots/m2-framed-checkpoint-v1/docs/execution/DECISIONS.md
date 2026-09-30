# Approved Change Decisions

Append decisions. Never rewrite completed gate evidence.

## Change-request template

- ID/date:
- Trigger:
- Requested delta:
- Reason:
- Smallest alternative considered:
- Affected paths/contracts/tests/gates:
- Risk and rollback:
- Budget/schedule effect:
- Owner decision:
- Revised task/build-plan version:

## D-001 — 2026-08-11 — Private solo repository control

- ID/date: `D-001` / `2026-08-11`
- Trigger: `palatis3/AssetRounds` will remain private, and the selected GitHub plan does not provide server-enforced branch protection for this private repository.
- Requested delta: Use the approved private-solo rule. The owner's explicit one-time installation of this decision and its companion static-authority edits creates the replacement bootstrap `B`; the rule becomes active immediately after that push. Thereafter Codex may push only an exact task-named phase branch and must never push, merge, force-push, or otherwise write `main`. Only the owner may write or merge `main`. At each phase boundary the owner reviews and merges once, verifies `refs/heads/main` equals the intended result SHA, permits no intervening push or history rewrite, dispatches CI by the `main` ref with `run_ui_smoke=true`, and accepts only a green run whose `head_sha` exactly matches. Unexpected ref movement stops the train. S9.2 uses the same owner-reviewed exact-`main` rule.
- Reason: Preserve a private repository and the exact-SHA evidence model without paying for server-side branch protection that is not available on the selected plan.
- Smallest alternative considered: Make the repository public or upgrade GitHub solely for branch protection. The owner rejected both for now.
- Affected paths/contracts/tests/gates: Repository authority language in `AGENTS.md`, build plan, runbook, execution contract, CURRENT_TASK template, and HANDOFF template. Product scope and test coverage do not change.
- Risk and rollback: The owner account is the procedural control point. Any additional writer, bot with write scope, unexpected ref movement, or history rewrite is a hard stop. Upgrade and enable branch protection later without changing product behavior.
- Budget/schedule effect: No implementation-card or CI-test increase; owner performs the existing exact-ref check at each phase boundary.
- Owner decision: Approved.
- Revised task/build-plan version: V4 product scope unchanged; repository-execution amendment `D-001`; changed plan/runbook hashes must be pinned by each hydrated task.

## D-002 — 2026-08-11 — Neutral immutable identifiers

- ID/date: `D-002` / `2026-08-11`
- Trigger: S0 requires an immutable reverse-domain identifier before creating the checked-in Xcode project.
- Requested delta: Freeze app bundle ID `com.palatis3.fieldrecord`, unit-test bundle ID `com.palatis3.fieldrecord.tests`, UI-test bundle ID `com.palatis3.fieldrecord.uitests`, monthly StoreKit product ID `com.palatis3.fieldrecord.sub.solo.monthly.v1`, and exported backup UTI `com.palatis3.fieldrecordbackup`. Keep internal target/scheme and persistence identifiers brand-neutral.
- Reason: Resolve owner placeholders before S0 while preserving later vertical reuse and avoiding the public product name in durable technical identifiers.
- Smallest alternative considered: Defer the product and backup identifiers to S6/S7. The owner chose one stable namespace now to reduce later setup decisions.
- Affected paths/contracts/tests/gates: Build-plan S0/S6/S7 owner inputs, runbook backup contract, S0 project settings, later StoreKit fixture, and backup type declaration.
- Risk and rollback: Apple bundle and product identifiers become costly or impossible to rename after release. These values are therefore treated as immutable; changing one requires a new approved decision and a compatibility/release assessment.
- Budget/schedule effect: No added product scope or card; removes placeholders from later hydration.
- Owner decision: Approved.
- Revised task/build-plan version: V4 product scope unchanged; identifier amendment `D-002`; changed plan/runbook hashes must be pinned by each hydrated task.

## D-003 — 2026-08-11 — Same-phase Codex autopilot

- ID/date: `D-003` / `2026-08-11`
- Trigger: The owner wants one persistent Codex `/goal` per phase instead of relaunching one task for every coding card.
- Requested delta: Phase autopilot is a sequencing exception, not multi-card implementation authority. CURRENT_TASK always selects exactly one current card and names the exact ordered cards allowed in the current phase. Its enabled state, ordered span, transition-authorization flag, and boundary-authorization flag are owner-set at phase start and immutable during Codex transitions. After that card has accepted green exact-`I`/`I2`-head CI, Codex may append HANDOFF and, only for the runbook's immediate next card inside the same authorized phase span, replace CURRENT_TASK and create one transition commit containing exactly HANDOFF plus CURRENT_TASK. Immediately before any transition/boundary bookkeeping push, remote phase ref must still equal accepted `I`/`I2`; the push is non-force and the ref must equal the new commit afterward. The next card starts only after fresh G0 proves `M` is the prior green implementation and `M..A` is exactly those two authority paths. Codex may not skip, reorder, combine, pre-implement, or cross a phase boundary. At a boundary Codex commits final HANDOFF bookkeeping only when explicitly authorized and stops before every `main` write, merge, main CI, new branch, next-phase hydration, signing, upload, deployment, or submission. Any second non-green card run, hydration ambiguity, unresolved owner input, or unexpected/intervening ref movement outside the exact just-authorized push stops the phase goal.
- Reason: Remove repetitive owner launches while preserving isolated card scope, exact-head CI, and an owner gate at every phase.
- Smallest alternative considered: Keep 36 owner-prepared launches. Rejected as unnecessary ceremony.
- Affected paths/contracts/tests/gates: `AGENTS.md`, build-plan §§11/16/18, runbook authority/hydration/lifecycle/prompt, execution contract, CURRENT_TASK, HANDOFF, and project goals setting. Product behavior, card count, workflow, test scope, and D-001's owner-only `main` rule do not change.
- Risk and rollback: Codex prepares its immediate next same-phase contract. If any path, selector, fixture, owner input, or acceptance field cannot be resolved uniquely from frozen authority/current code, it must stop. Roll back by setting phase autopilot disabled; completed implementation commits and evidence remain valid.
- Budget/schedule effect: No added implementation CI; one bookkeeping transition per within-phase edge; still one merge and exact-main CI per phase.
- Owner decision: Approved.
- Revised task/build-plan version: V4 product scope unchanged; execution amendment `D-003`; the owner explicitly authorizes this one-time static-authority/config installation on `main` as the replacement bootstrap before autopilot becomes active; recompute and pin changed plan/runbook hashes.

## D-004 — 2026-08-11 — Owner-selected Full access posture

- ID/date: `D-004` / `2026-08-11`
- Trigger: The owner wants AssetRounds Codex goals to honor the current GUI Full access posture and proceed without sandbox, network, connector, or approval-profile blockers.
- Requested delta: Permit and expect `sandbox_mode=danger-full-access`, `approval_policy=never`, unrestricted command network, and the owner's enabled GUI tools/connectors. Project `.codex/config.toml` no longer downgrades the GUI/session permission profile. G0 must not stop because filesystem, network, plugin, connector, credential, or external-write capability is broader than the active card. Full access grants capability only: CURRENT_TASK remains the sole authority for product scope, exact paths, GitHub repository/ref/workflow arguments, branch writes, CI, deployment, signing, TestFlight, App Store, and every external mutation.
- Reason: Remove repetitive permission questions and false permission-posture stops while preserving the already approved concrete card, branch, and exact-head CI workflow.
- Smallest alternative considered: Keep `workspace-write` plus `on-request` and approve Git/GitHub access repeatedly. The owner rejected that interaction model.
- Affected paths/contracts/tests/gates: `.codex/config.toml`, `AGENTS.md`, execution contract, runbook authority lifecycle, CURRENT_TASK posture and cumulative authority diff, and this decision log. Product behavior, S0 paths, CI workflow, selectors, test budget, owner-only `main`, and release gates do not change.
- Risk and rollback: Full access can reach files, credentials, network services, and external systems without approval prompts. Scope rules therefore constrain use rather than capability. Roll back by restoring the restricted project posture and revising CURRENT_TASK before the next G0.
- Budget/schedule effect: No new card or CI run; removes permission approval pauses.
- Owner decision: Approved explicitly in chat.
- Revised task/build-plan version: V4 product scope and build-plan bytes unchanged; execution amendment `D-004`; repin the changed runbook hash in the active task.

## D-005 — 2026-08-11 — Cross-phase program autopilot

- ID/date: `D-005` / `2026-08-11`
- Trigger: The owner wants Codex to integrate each completed phase automatically and immediately continue into the next coding phase without a new prompt or routine owner checkpoint.
- Requested delta: One persistent goal may execute S0.1 through S9.1 sequentially. After every phase's final card has green exact-implementation-head CI, Codex commits/pushes final HANDOFF, verifies the phase and unchanged `main` refs, performs only a non-force fast-forward of `main` to the exact phase-close commit, requires UI-enabled exact-main CI, creates only the next branch in the frozen phase map from that green SHA, hydrates only its first runbook card with exact predecessor evidence, runs fresh G0, and continues. Any non-fast-forward, unexpected ref movement, CI mismatch/failure, hydration ambiguity, or missing required owner input stops without force or speculative repair. S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.
- Supersession: For this closed S0–S9.1 lifecycle only, D-005 supersedes D-001's owner-only-`main` clause, D-003's stop-at-every-phase clause, and D-004's statement that owner-only `main` remains unchanged. All no-force, exact-ref, exact-head-CI, one-card, no-sign/upload/submit, and owner-only S9.2/S9.3 controls remain active.
- Frozen phase branches: `S0=phase/s0-foundation`; `S1=phase/s1-shell-design`; `S2=phase/s2-persistence-signs`; `S3=phase/s3-check-runner`; `S4=phase/s4-reports`; `S5=phase/s5-work-recheck`; `S6=phase/s6-data-rights`; `S7=phase/s7-commerce`; `S8=phase/s8-quality`; `S9=phase/s9-release`.
- Reason: Remove repeated phase-launch and manual-main-integration steps while preserving one-card scope, exact-head evidence, linear history, and recoverability.
- Smallest alternative considered: Owner merges and starts each phase manually. The owner rejected that routine interaction model.
- Affected paths/contracts/tests/gates: `AGENTS.md`, build plan, execution contract, runbook lifecycle/goal, CURRENT_TASK program fields/remote authority, HANDOFF continuation text, and this decision. Product scope, card count, per-card CI, one-fix limit, signing, TestFlight, and App Store release gates remain unchanged.
- Risk and rollback: Full-access Codex can write `main`; the closed non-force fast-forward/ref-equality checks are the control. Any divergence stops. Roll back by disabling program autopilot in owner-prepared CURRENT_TASK; completed linear commits and CI evidence remain valid.
- Budget/schedule effect: Removes ten routine owner main integrations and nine next-phase launches; retains one branch CI per card and one main CI per phase.
- Owner decision: Approved explicitly in chat.
- Revised task/build-plan version: V4 product behavior unchanged; execution amendment `D-005`; recompute and pin changed plan/runbook hashes.

## D-006 — 2026-08-11 — Enforce frozen CI evidence budgets

- ID/date: `D-006` / `2026-08-11`
- Trigger: Pre-S0 audit found the workflow validated the setup/evidence ceiling but did not enforce it and the S0 task confused the runner staging directory with the uploaded GitHub artifact name.
- Requested delta: Add fail-closed elapsed-time checks for setup and evidence-finalization using the already frozen selector value, preserve the total/job limits, and name the uploaded artifact exactly as `ios-ci-<run_id>-<run_attempt>` with `FieldEvidenceCI` only as its content root.
- Reason: Prevent the first S0 run from stopping or falsely passing against its existing P12 contract.
- Smallest alternative considered: Weaken the plan/task wording. Rejected because the workflow already exposes the frozen budget field and can enforce it with a bounded change.
- Affected paths/contracts/tests/gates: `.github/workflows/ios-ci.yml`, CURRENT_TASK workflow hash/evidence wording, D-004/D-005 cumulative pre-S0 authority path set. No product code or card scope changes.
- Risk and rollback: Timing is based on runner wall clock; a genuinely slow setup/evidence phase fails as designed. Revert only with a new authority decision and repinned workflow/task.
- Budget/schedule effect: No new run; two small validation steps inside the existing 30-minute job.
- Owner decision: Approved as part of the requested pre-S0 blocker removal.
- Revised task/build-plan version: V4 product behavior unchanged; CI enforcement amendment `D-006`; repin workflow hash.
