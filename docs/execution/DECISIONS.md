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
