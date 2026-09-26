# AssetRounds: V23 on S10, working agreement (v2, owner-approved 2026-09-25)

## Goal

V23 becomes the base app and includes the accepted S10 app. It keeps S10's look, brand and design system. Main advances in verified phases. Phase 1 covers the platform and the four-tab shell, with unfinished features hidden behind `V23PhaseGateV1`. After Phase 1, development is trunk-based on main, and each finished feature is switched on only after its phase gates pass. Release requires the full V23 scope.

## Where to work

- Until Phase 1 merges, work on branch `codex/v23-s10-integration-20260910`. After that, work on `main`.
- The primary development machine is the owner's cloud Mac, running Codex with Xcode 26.6. Local development uses the installed iOS 26.5 Simulator; gates retain iOS 26.2 (23C54) on GitHub. Setup is in `docs/design/v23/integration/MAC_HANDOFF.md`.
- The Windows checkout `C:\AssetRounds-v23-s10-integration` holds about 55 uncommitted owner drafts. Never reset, delete, overwrite or reformat them, and never stage them without the owner's say-so. In every checkout, preserve owner drafts, untracked work, frozen branches, V30 and the coordination ledger.
- Start every session with `docs/design/v23/integration/ACTIVE_BRIEF.md`. Then use:
  - `CURRENT_INTEGRATION.md` for batch detail;
  - `MERGE_READINESS.md` for phases and the phase ledger;
  - `VERIFICATION_DUE.md` for open obligations.
- Product authority is the frozen V23 design material under `docs/design/v23/`. Never infer product truth. Ask the owner about product decisions.

## Hard boundaries (never)

- No force-push, no rewriting published history, no merge commits and no pull requests. Use linear, non-force pushes only. Refresh refs before every push and investigate unexpected ref movement.
- No GitHub or Bitrise settings, secrets or paid-capacity changes; the owner selects machines and caches. No signing, distribution, App Store submission or other release operation. `releaseReady` stays false until the owner decides. App Store metadata, privacy, rights, assets and owner actions remain required for release.
- Card135 stays owner-only and skipped. Minimum-runtime and physical-device verification stay deferred.
- Never edit `docs/design/s10/**` or `Release/**`. They are bound to the five accepted S10 receipts. Accepted S10 main `b1d04ae5e684aa9c6807af655089efa1df8a7ed6` stays the historical baseline.
- Keep one app, one Xcode project and shared scheme, and one writer, store and renderer. No second app.
- Never fabricate evidence. Never present local, Windows-protocol or development results as acceptance. Static, source or protocol review never implies compilation or runtime success.
- Never broad-stage (`git add -A` or `git add .`); stage explicit owned paths only.
- Don't create accounts, handle passwords or payment details, or change the owner's account settings. The owner does those.

## Verification: two tiers

### Development (fast)

- **Local.** On the Mac, builds and targeted tests (see MAC_HANDOFF) give quick feedback.
- **Tools and evidence.** The dispatcher and collector are `Scripts/dev/v23-original.py` once the tools batch lands; until then they are `.codex-temp/native-tools/v23-original.py` on Windows. The ledger (`v23-original-ledger.jsonl`), attempt records and retained evidence live under `V23_EVIDENCE_ROOT`: `C:/AssetRounds-v23-review-evidence` on Windows and `~/AssetRounds-v23-review-evidence` on the Mac. Full historical originals stay on Windows.
- **Hosted development routes.**
  - The development batch: `v23-dev-batch-no-index-d50`, listing tests in `Scripts/v23-dev-batch.json`.
  - The shared-build coverage sweep: `v23-shared-coverage-d50x`, with partitions in `Scripts/v23-coverage-partitions.json`, regenerated whenever test methods change.
  - Bitrise Build Hub may add development capacity on its available iOS 26 runtime.
- **Allowed for development runs only**, each recorded in the ledger through the dispatcher (see the tools path above):
  - rerun after an infrastructure failure (runner, setup, network or artifact transport), never to retry failing tests;
  - cancel a run already known to be broken;
  - run distinct development batches in parallel.
- Development results never count as acceptance. A run counts toward a gate only if it is recorded as a gate run on the frozen candidate head before dispatch; development, local, rerun or cancelled runs never count.

### Gates (strict)

Required before main advances for a phase, or before a feature is switched on:
1. Same-head full unit coverage through the shared-build route, with every partition passing.
2. Qualified UI evidence (RUI1 budget: 300/1800/900/UI 900/3900, 90 min) of the phase's critical states on the pinned GitHub route.
3. One independent integration review of the phase candidate.
4. The owner's genuine human review of the critical states, using screenshots and a checklist.
5. A non-force fast-forward of main, then exact-main verification on the pinned GitHub route (Xcode 26.6, iOS 26.2 23C54).

All gate evidence binds to one frozen candidate head. A missing required runtime or execution kind blocks the gate on any provider. The shared-build route counts for gate 1 only after a cold qualifying original has proved payload binding, safe extraction, no-rebuild and per-partition results covering every unit method.

Gate runs follow these rules:
- One original per head and question, with a sole collector.
- No rerun or cancel.
- Complete logs and artifacts are retained with SHA-256 manifests.

Functional, privacy, accessibility or unusable-state defects block a phase. Noncritical visual polish goes in VERIFICATION_DUE and is finished before release.

### Main after Phase 1

- Each change reaches main by a non-force fast-forward from a pushed candidate branch. Before that fast-forward, the candidate's exact head has passed an independent review and a hosted GitHub compile and affected-test run, recorded in the ledger as a gate run under the gate-run rules. Exact-main verification follows. Code that lands switched off meets the same rules.
- No schema, persistence, backup, restore or migration change reaches main, even behind a switch, until it is complete and has passed all five gates.
- A full-coverage sweep runs at least before any feature is switched on.
- New features land with their switch off until their gates pass.

## How we work

- **Root session.** It diagnoses, implements understood fixes, integrates, and alone commits, pushes and dispatches.
- **Helpers.** Use as many as speed delivery. Each gets one bounded question and disjoint files, or read-only scope. Implementation helpers work in worktrees created by root at the exact head. Watch usage limits: typically 2–4 helpers at a time.
- **Risk-based independent review (owner-approved 2026-09-26).** Data safety, security, persistence, backup, restore, migration, CI evidence logic and merge candidates require an independent GPT-6 Astra reviewer. Routine fixture and cosmetic changes may share a milestone review instead of a review for every intermediate batch. Legitimate test-expectation changes still require a recorded reason and independent review; no test, predicate, coverage or watchdog may be weakened. The reviewer is read-only and never the author. Corrections go back to the same reviewer, and verdicts are recorded in CURRENT_INTEGRATION along with the reviewer model. Reviewers always assess compile risk. Automated checks are never labelled as independent review.
- **Standing implementation authority (owner-approved 2026-09-26).** Root decides reversible implementation and internal tooling choices within the existing scope and hard boundaries, without repeated owner confirmation. Frozen design remains product authority; unresolved or contradictory product decisions, genuine human visual acceptance, privacy sign-off and release decisions remain owner-reserved. This authority does not change gate requirements or authorize account/settings/secrets, paid capacity, signing or release operations.
- **Compile first.** Compile new Swift on the Mac, or with one development batch, before fanning out native runs.
- **Integration cadence (owner-approved 2026-09-26).** Prefer small, coherent integration-branch checkpoints. Keep subsequent fixes isolated while a checkpoint is being verified; do not continually expand a running batch. Before an integration commit, compile changed Swift and run affected development tests, obtain the risk-appropriate review above, and record exact results and remaining failures. These checkpoints are not acceptance and do not advance main. Run a deliberate hosted development sweep after meaningful stabilization, then all required same-head gates on a frozen merge candidate. Do not repeat full coverage for each intermediate integration commit, duplicate unchanged runs, or transfer development evidence into gates. Address measured performance bottlenecks without weakening checks or budgets. Phase 1 is an intermediate milestone: V23 is the app baseline incorporating accepted S10, and the complete V23 scope remains required for release.
- **Family batches and prerequisites (owner-approved 2026-09-26).** Group failures by a proven shared cause and combine their reviewed corrections into one bounded compile/affected-test cycle. Fix prerequisite migration, restore and ownership defects before spending hosted capacity on dependent UI qualification. Keep unrelated follow-ups isolated while a batch is being verified; do not keep expanding a running batch. A checkpoint may retain explicitly recorded development failures under the integration cadence above; this never makes it merge-ready.
- **Proportionate development verification (owner-approved 2026-09-26).** After integrating already verified candidates, check their exact source bindings, changed interfaces, ordered coverage census and affected behavior. Repeat a full development suite when new changes, failures or unresolved coupling justify it; do not automatically repeat both full suites merely because an independently checked adjacent batch landed. Required CI suites still run for each changed CI candidate. Prior results retain their exact head/input scope, and no development result becomes gate evidence. All full same-head gates remain mandatory.
- **Efficient execution (owner-approved 2026-09-26).** Reuse helpers with relevant context, assign disjoint files or read-only scopes, and overlap independent implementation/review with builds and tests. Choose local worker counts from available CPU and memory rather than a fixed low count; avoid contention with active Xcode/simulator work. Remove measured repeated computation through bounded, independently reviewed changes while preserving filesystem, source-change, data-safety and evidence checks. Never cache an authorization or acceptance decision merely to make a run faster.
- **Failures.**
  - Fix failures by family, in batches.
  - Never weaken tests, predicates, coverage or watchdogs.
  - A legitimate expectation change needs a recorded reason and review.
- **Tests.**
  - Prefer behaviour tests to exact-byte source pins.
  - When a pin must change, recompute it from the real bytes with the test's own algorithm, and record the provenance.
  - S10 brand protection comes from the design system, the closed-vocabulary test, behaviour tests and screenshot review.
- **Diagnostics.** Build in named DEBUG step and error reporting, so one failing run names its cause.
- **CI changes.**
  - Run `Scripts/test-v23-native-ci.py` and `Scripts/test-v23-selection-generator.py` through `Scripts/dev/prun.py` (or plain `python3 <suite>` until the tools batch lands).
  - Keep the template-budget guard: called-workflow content stays under 5.75 MiB, because GitHub rejects about 6 MiB.

## Records (short)

- `ACTIVE_BRIEF.md`: 60 lines or fewer, covering current state and next steps.
- `CURRENT_INTEGRATION.md`: one checkpoint per batch, with the requirement, files, review verdict and native result.
- `MERGE_READINESS.md`: phases and the ledger.
- `VERIFICATION_DUE.md`: open obligations.
- `REVIEW_EFFICIENCY.md`: optional notes.
- Fold record updates into the next real commit.

## Model and effort

The owner sets the session model and effort in the app. On 2026-09-26 the owner moved all Claude roles to GPT-6 Astra, including the independent reviewer. Codex helpers use `gpt-6-astra` at `high` under the retained Codex routing rule. Repository policy never changes the primary session settings.

Helper budget (owner, 2026-09-25, lowered the same evening to save 5-hour usage): at most 5 concurrent active subagents plus the root session (raised by the owner on 2026-09-26); an idle reviewer does not count until it is working. Before a helper is retired, it writes a short handoff note (scratchpad or VERIFICATION_DUE) so its knowledge can be reused. Reuse an existing helper that already holds the relevant context before spawning a new one, to save tokens. Use the available follow-up/resume tool to activate an idle helper; a message-only tool may not start a new turn. The owner may raise the limit again if the 5-hour usage allows. Use the Mac's 16 GB and CPU fully within that limit; up to about 3 concurrent Xcode builds, the CPU being the practical limit.

## Owner decisions in force (2026-09-24/25)

1. The independent reviewer is a separate GPT-6 Astra subagent that never authors what it approves (owner updated 2026-09-26).
2. My Day fork history: the bounded normalized-history amendment (`.codex-temp/my-day-fork-lineage/FORK_COMPATIBILITY_AMENDMENT.md`) is approved.
3. RUI1 UI budget is approved.
4. Full coverage uses a shared build per head with test-only partitions of up to 3,000 s, five at a time. One early development sweep runs first, and the final same-head sweep is still required.
5. The merge is phased. Unfinished features stay unreachable and are listed in MERGE_READINESS. Nothing is silently dropped, and there is no silent feature reduction. Release requires the full V23 scope.
6. Completed-work signoff: the purpose `WORK_DETAIL_COMPLETED_RESPONSE_V1` means "approval response", and the actor responsibility is `ACKNOWLEDGED_BY`. The UI never says "Approved".
7. S10 card-time tests prove the committed S10 history, not live CI state. Only card-time CI-state tests that already failed at b1d04ae are rewritten, and their semantic brand checks stay. Receipt-bound files are never edited.
8. Privacy: the S10 review stays as history. A V23 successor review (`privacy-supply-chain-review-v23.json`) is signed off by the owner before release.
9. Development moves to the cloud Mac. Local builds and tests are allowed for development; official evidence stays on GitHub.
10. Development-run rules are relaxed as described above. Gates stay strict.
11. Trunk-based development on main after Phase 1.
12. Bitrise Build Hub (runner group `Asset Roundddd`) may be used for development capacity. It becomes official evidence only after it provides the exact runtime and is qualified.
13. Pending the owner's call: the C55 reversal-restore decision (`C55_REVERSAL_RESTORE_DECISION.md`), a V23 privacy sign-off, App Store items, and confirmation of the D50 development tier.

Owner decisions, 2026-09-25 (cloud Mac session):

14. Standing decision authority. Root decides a product question when frozen V23 design material settles it. Root cites the evidence and records the decision as owner-delegated and reversible in CURRENT_INTEGRATION. Root asks the owner only when the design material is silent or contradicts itself. This never covers releases, signing, accounts, privacy sign-off or the owner's human review.
15. DEBUG diagnostics. The DEBUG-only protected-file diagnostic journal may be batched or summarized to cut test time, with no change to Release builds. The underlying lease/fence and file-policy performance work is still a consequential product change: it needs independent review and the gates.
16. Tooling follow-ups. Approved:
    - a workflow change that allows parallel development batches, with a per-head concurrency term reviewed against the template-budget guard;
    - solo partitions of up to 5,400 s for known-slow single tests until the performance fix lands.
    Gate runs keep all other gate rules.
17. Phase 1 scope stays as written: every unit test must be green. After the current development sweep is triaged, root will bring the owner numbers for a possible known-failures list limited to switched-off-only features. Shipping-app, S10, backup, restore, migration, privacy and access tests are never eligible. The owner decides then.
18. Premium quality bar. When root chooses between valid options, it picks the one that gives the best end-user experience:
    - root-cause fixes over workarounds;
    - fast, smooth, never-hanging flows (performance is part of quality);
    - reliable data safety;
    - polished S10 look and feel.
    Gates, frozen design and the boundaries above still govern.

Owner decisions, 2026-09-26 (Codex workflow update):

19. Review follows risk rather than intermediate batch size: independent review remains mandatory for restricted/high-risk changes and merge candidates; routine fixture/cosmetic work may share a milestone review. Test-expectation changes retain their recorded-reason and review requirement.
20. Root has standing authority over reversible implementation and internal tooling choices within scope and existing boundaries. Owner-reserved decisions and all gate obligations remain unchanged.

21. Use small coherent integration checkpoints, isolated follow-up work and compile/affected development verification before integration commits; schedule full hosted sweeps at meaningful stabilization and frozen merge milestones. All same-head gates remain mandatory before main; Phase 1 does not reduce the complete V23 scope.

22. Work by proven failure family, fix prerequisites first, combine reviewed corrections into bounded verification cycles, avoid redundant full development reruns, and reuse helper context and available local resources. The detailed rules above preserve all gate, data-safety and owner-review requirements.

## History

Owner decision, 2026-09-26: use GPT-6 Astra for every role previously assigned to Claude. Up to 6–7 helpers are authorized subject to configured capacity; this Codex session supports five helpers plus root. The independent reviewer remains read-only and separate from the authors. Historical Claude verdicts and their model attribution are preserved.

Earlier instructions are preserved verbatim in `docs/execution/AGENTS_HISTORY_20260911.md` and `docs/execution/AGENTS_HISTORY_20260925.md`. This file supersedes them wherever they conflict. Enduring safety and gate constraints in those files, such as not adding packages, targets, capabilities or entitlements without authority, stay in force unless this file explicitly changes them. Codex routing rules (`gpt-6-astra`) apply only if work returns to Codex.
