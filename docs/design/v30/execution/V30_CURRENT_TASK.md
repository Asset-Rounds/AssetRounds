# V30 Current Task

- Schema: `V30CurrentTaskV1`
- Authority ID: `ASSETROUNDS-V30-PRE-S10-20260902-R2`
- Card: `V30-P00-C01 — Provisional authority and isolated-lane validation`
- Card ordinal: `1 of 55`
- Execution epoch: `PRE_S10_PROVISIONAL`
- Direct prerequisites: `[]`
- Outcome: Validate authority, package, dedicated worktree, Phase 10 isolation, and zero-credit posture only. No product work.
- Allowed paths: exactly the generated Card 1 fence; no inferred paths.
- Exact Card 1 fence: `docs/design/v30/execution/fences/V30-P00-C01-attempt-1.json`.
- Installation request ID: `ASSETROUNDS-V30-PRE-S10-20260902-R2/INSTALL`.
- Active selector: `docs/design/v30/execution/V30_CI_SELECTION.json` (`DISABLED_STATIC_PREFLIGHT`).
- Hosted dispatch: forbidden until `V30-P00-C05` pins the route.
- Phase 10 checkout `C:\AssetRounds`: forbidden read/write/poll/build/test/Git/process target.
- Inherited `docs/execution/CURRENT_TASK.md`, `docs/product/BUILD_PLAN_V4.md`, and `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`: frozen read-only predecessor evidence; not V30 active-task authority.
- Inherited `Scripts/ci-selection.json`: frozen read-only predecessor evidence; never the V30 active selector and never modified.
- Credit: all pre-S10 work is provisional and earns no final-card, main, release, or Phase 10 compatibility credit.

## Exact allowed paths

- `docs/design/v30/execution/V30_CURRENT_TASK.md`
- `docs/design/v30/execution/V30_CI_SELECTION.json`
- `docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json`
- `docs/design/v30/execution/V30_EXECUTION_HANDOFF.md`
- `docs/design/v30/execution/V30_PROVISIONAL_ACTIVATION_RECEIPT.json`
- `docs/design/v30/execution/contexts/V30-P00-C01-attempt-1.json`
- `docs/design/v30/execution/receipts/V30-P00-C01-validation-receipt.json`
