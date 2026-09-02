# AssetRounds V30 Fresh-Task Handoff

## Handoff state

- Prepared: 2026-09-02
- Handoff schema: `V30FreshTaskHandoffV1`
- Required external authority ID: `ASSETROUNDS-V30-PRE-S10-20260902-R2`
- Program: AssetRounds V30 Globalization
- Current mode: `READY_FOR_OWNER_ACTIVATION_PRE_S10`
- Current card: none selected
- Next card after installation/genesis: `V30-P00-C01`
- Card display: `Card 1 of 55 — Provisional authority and isolated-lane validation`
- Pre-S10 executable cohort: the 37 graph-enumerated `PRE_S10_PROVISIONAL` cards
- Post-S10 locked cohort: the 18 graph-enumerated cards beginning at `V30-P05-C01`
- Final credit available before reconciliation: false
- Phase 10 completion polling: forbidden

This handoff is designed for a new Codex task. It is not valid as a hidden agent-to-agent message. The owner must send `NEXT_CODEX_SESSION_PROMPT.md` as the new task's user message so authority comes directly from the owner. This external handoff, the Foundation Plan, the Architecture Blueprint, and the copy-ready prompt are the immutable four Markdown package inputs: install them byte-for-byte, but do not append to or rewrite them. The installed execution ledger is `docs/design/v30/execution/V30_EXECUTION_HANDOFF.md`.

## Exact read order

Read all of these before mutation:

1. From frozen B only, read `C:\AssetRounds-v23-expansion\AGENTS.md` and every applicable instruction it names. Do not access `C:\AssetRounds` while doing this.
2. `NEXT_CODEX_SESSION_PROMPT.md` — owner-sent activation request.
3. `V30_PRE_S10_PROVISIONAL_IMPLEMENTATION_AUTHORITY.json` — machine-readable external boundary.
4. `V30_PACKAGE_MANIFEST.json` — exact external package hashes and authority content digest.
5. `EXPANSION_V30_FOUNDATION_PLAN.md` — execution epochs and scope.
6. `EXPANSION_V30_ARCHITECTURE_BLUEPRINT.md` — complete architecture, 55-card graph, evidence law, and reconciliation.
7. This handoff.
8. Before branch creation or any mutation, compare the owner message's literal `authorityID` and `authorityContentDigest` to the exact fields in the external authority and manifest. Absence or mismatch is a read-only hold; the prompt never issues or amends authority.
9. After the dedicated V30 worktree exists, re-read its inherited `AGENTS.md` and applicable instructions before the next mutation. Its active task and selector are `docs/design/v30/execution/V30_CURRENT_TASK.md` and `docs/design/v30/execution/V30_CI_SELECTION.json`; inherited V4 `CURRENT_TASK`, plan, and runbook remain frozen predecessor evidence and are never edited or used as the active selector.

The underscore names in steps 3–4 are external package source filenames. The manifest installs those exact bytes at `docs/design/v30/authority/V30PreS10ProvisionalImplementationAuthorityV1.json` and `docs/design/v30/authority/V30PackageManifestV1.json`; this deliberate source-to-install mapping is not a filename contradiction.

Never substitute a summary for the complete Architecture Blueprint.

## Frozen authoritative observations

### Repository and V23

| Fact | Value |
|---|---|
| Repository | `https://github.com/Asset-Rounds/AssetRounds.git` |
| Frozen V23 worktree | `C:\AssetRounds-v23-expansion` |
| Frozen V23 branch | `phase/v23-expansion` |
| Frozen V23 HEAD | `acbfb68355f903fe98638b6ef22e4814e7b48328` |
| Frozen V23 tree | `47e17fae6b73dccd5029ccf4ac7cca659196f225` |
| Frozen V23 origin branch | same HEAD |
| Frozen V23 status at handoff | clean |
| V23 package | `ASSETROUNDS-EXPANSION-V23-20260825` |
| V23 package digest | `99a2719885ad1abfb8cf5d49c6b2099754bb0ba4b5d27fcbae06476aad507570` |
| V23 register/graph | 146 cards / 230 direct edges |

### Frozen coordination observation

| Fact | Value |
|---|---|
| Worktree | `C:\AssetRounds-v23-coordination` |
| Branch | `main` |
| HEAD | `51ef2b3d970a25b4c83df8c8238609316e37034e` |
| Tree | `060c83c3d1489fc011b1c921f6c85bec2b074478` |
| Origin main | same HEAD |
| Status at handoff | clean |
| Sequence | 626 |
| Ledger digest | `973090852e843e895125bea8da87c7e1689611c46d8219a70c1749be49398067` |
| Projection digest | `cf57849e8f7c245d38fd21a39da5938d10e13c9aca3976a71b7d3a3ee401f12d` |

This coordination state is a frozen read-only observation. The pre-S10 V30 lane creates its own provisional ledger and does not append to the canonical V23 ledger.

### Frozen S10 reservation

| Fact | Value |
|---|---|
| Artifact | `C:\AssetRounds-v23-expansion\docs\design\v23\foundation\ActiveS10OwnershipReservationV1.json` |
| Raw SHA-256 | `9f7c27431271728d167731d4af806c7449447dfbcc8bf46778102e2f9a89b576` |
| Ordered path count | 86 |
| Content digest | `274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a` |
| Frozen owner branch | `phase/s10-brand-refresh` |
| Binding mode | `FROZEN_OBSERVATION_NO_POLL_UNTIL_OWNER_REPORTS_S10_6_COMPLETE` |

Use the artifact's exact ordered `reservedPaths` array. Do not retype it from prose. Its owner head/tree are historical observations, not current Phase 10 truth.

### Unfinished V23 cards

- Card 135 / V23-P05-C02 — OWNER_ACTION / NOT_STARTED
- Card 136 / V23-P05-C03 — MONITOR / NOT_STARTED / unarmed
- Card 141 / V23-P06-C05 — DEFERRED
- Card 146 / V23-P06-C10 — DEFERRED

All retain `staticPreparation=false`. V30 must not fabricate their completion.

## Worktree/ref state at handoff

| Location/ref | State |
|---|---|
| `C:\AssetRounds` / active Phase 10 | Exists; forbidden to inspect, poll, or mutate |
| `C:\AssetRounds-v23-expansion` / `phase/v23-expansion` | Exists, clean, frozen |
| `C:\AssetRounds-v23-coordination` / `main` | Exists, clean, frozen observation |
| `C:\AssetRounds-v30-globalization-foundation` / `phase/v30-globalization-foundation` | Exists, clean R1 planning marker |
| `C:\AssetRounds-v30-globalization` / `phase/v30-globalization` | Absent at handoff; create only through the owner prompt |
| `C:\AssetRounds-v30-globalization-coordination` / `coord/v30-globalization-provisional` | Absent at handoff; isolated provisional coordination branch in the separate coordination repository |
| `C:\AssetRounds-v30-globalization-reconciliation` / `phase/v30-globalization-reconciliation` | Absent; forbidden before Phase 10.6 trigger |
| local/origin `phase/v30-globalization` | Absent at handoff |

Do not interpret later drift as permission to overwrite it. Any unexpected existence or ref movement requires read-only provenance inspection outside the Phase 10 checkout.

## Owner-authorized start-today outcome

The new task may, after exact validation:

- create the provisional branch/worktree at the exact V23 base;
- install the hash-bound V30 package;
- establish the sole namespaced provisional ledger genesis and its expected-absent receipt;
- create one Card 1 current-task/selector projection;
- continue the graph-enumerated pre-S10 cohort under exact card fences;
- use subagents on nonoverlapping paths;
- run Windows-safe deterministic checks;
- run task-pinned hosted macOS branch CI as provisional development evidence only;
- commit and non-force push the V30 branch when the active V30 card explicitly authorizes it.

The closed bootstrap exception permits only branch/worktree creation, exhaustive installation of manifest-enumerated package support artifacts, one expected-absent provisional ledger genesis/receipt, and one Card 1 current-task/selector projection. It permits no product work and no other active-card mutation. After bootstrap, a card can mutate only exact paths pre-authorized by its installed fence, including new files explicitly classified `EXPECTED_ABSENT_NEW_PATH`; no card may grow the external support-artifact set.

Card 5 alone may wire the three pre-issued workflow/helper copies in the V30 branch to its V30 selector. The actual Phase 10 CI lane and inherited selector stay untouched. Before reconciliation, native runs are optional diagnostics: unavailable runs remain `NOT_EXECUTED_NO_NATIVE_CREDIT`; required static checks may still allow provisional coding to continue. Preserve all failures and require final native qualification after reconciliation.

The new task may not:

- inspect, poll, or mutate `C:\AssetRounds`;
- mutate frozen V23 or canonical V23 coordination;
- mutate `main`, Phase 10 refs, or release refs;
- select any member of the graph-enumerated post-S10 cohort;
- call any pre-S10 card accepted;
- merge the planning/provisional branch wholesale;
- sign, TestFlight, upload, submit, release, or activate another storefront;
- invent professional/native, legal, licensed, physical-device, owner, monitor, or deferred evidence.

## Exact installation sequence

1. Treat the owner-sent prompt as a request to validate, not self-proving authority; read frozen-B instructions and compare the exact external authority ID/content digest first.
2. Recompute and compare every package hash and canonical digest, validate the authority JSON and manifest without rewriting them, and verify frozen V23 and coordination facts from only their named worktrees. Package generators are `--check` only after owner invocation; a mismatch requires a successor package, not regeneration in the execution task.
3. Verify target branch/worktree absence or exact idempotent installed state.
4. Create `phase/v30-globalization` at `acbfb68355f903fe98638b6ef22e4814e7b48328`, then create `C:\AssetRounds-v30-globalization` for that branch.
5. Install all and only external-authority/manifest-enumerated support artifacts, byte-for-byte, including the four immutable Markdown package files, authority/manifest, generator/validator, and generated machine artifacts. No active card may add to that set.
6. Create one exact package-install commit and read back parent/head/tree/diff.
7. G3 is the sole provisional-ledger genesis. Create `coord/v30-globalization-provisional` and `C:\AssetRounds-v30-globalization-coordination` from the exact frozen head of the separate coordination repository, using expected-absent branch creation. Commit the expected-absent namespaced ledger as a direct child of that head, with the frozen head as the expected old Git ref; then append/read back one activation receipt by a second CAS. P00-C03 later validates that genesis; it does not create another ledger. Use only the authority's exact three coordination bootstrap paths and request IDs.
8. From the exact install commit, create one direct-child selection-projection commit changing exactly the authority-pinned Card 1 context, fence, execution-handoff genesis, read-only provisional-ledger projection, `docs/design/v30/execution/V30_CURRENT_TASK.md`, and `docs/design/v30/execution/V30_CI_SELECTION.json` bytes. Advance only the V30 branch with an expected-old-value compare-and-swap against the install head; do not edit inherited V4 authority or selectors.
9. In a later coordination CAS, select Card 1 and bind the exact selection-projection commit/tree/diff and six materialized projection digests. If that final CAS fails, the projection commit has no active-card authority; resume only by exact readback with the same installation request ID and expected hashes.

Do not collapse install, ledger genesis, activation receipt, projection commit, or ledger selection.

Use the pinned installation request ID `ASSETROUNDS-V30-PRE-S10-20260902-R2/INSTALL` and exact `bootstrapRequestIDs`; never allocate new IDs to retry the same operation. The authority defines the separate ledger identity, namespace, writer generation, expected-ref rules, and receipt paths. Once bootstrap is complete, only the named ledger file receives append-only provisional events in that coordination branch.

Run the validator from the external flat package. Before installation, use `python -B validate_v30_package.py` in that external folder. For G2 readback, use the same external script with `--installed-root C:\AssetRounds-v30-globalization`; it verifies every exact source-to-install mapping against the manifest. The split copies under `Scripts/v30/` are immutable provenance and are not a second flat package. Never run a generator's `--apply` mode inside the implementation worktree.

## Card 1

### V30-P00-C01 — Provisional authority and isolated-lane validation

Outcome:

- prove the owner prompt, package, branch, base, worktree, S10 reservation, V23/coordination observations, no-poll rule, and zero-credit law;
- freeze the exact package/graph/locale/source identities;
- define the exact P00-C01 file fence before implementation;
- select only P00-C02 after a verified provisional checkpoint.

Initial exact allowed paths are limited to the seven execution-governance paths pre-issued by the Card 1 fence, including explicitly expected-absent receipts and context. The hydrated task must enumerate each file; no directory root or glob is valid. Card 1 must not change shipping product code, tests, project files, resources, CI, inherited AGENTS, inherited V4 plan/runbook/current-task, inherited V4 selector, or any S10-reserved path. It cannot modify external package inputs or grow the installed support-artifact set.

Expected terminal state:

`PROVISIONAL_CHECKPOINTED / finalCredit=false / next=V30-P00-C02`

## Pre-S10 card law

- One current card at a time.
- Exact individual-file paths only.
- A pre-S10 shared S10 path is permitted only when its exact pre-issued authority tuple appears in both `allowedPaths` and `s10SharedPaths`; any other overlap is `CONFLICT_HOLD`.
- Shared paths receive one writer.
- Locale agents may parallelize read-only preparation only. Exactly one card may mutate, checkpoint, or transition at a time.
- No pre-S10 human translation review is final acceptance.
- No branch CI is final acceptance.
- Corrections are direct children and preserve failure evidence.
- Append execution evidence only to `docs/design/v30/execution/V30_EXECUTION_HANDOFF.md`; always state “Card N of 55.”

## Phase 10.6 trigger and later reconciliation

The owner will later state that Phase 10.6 is complete. Until then, do not check it. That completion message is only a read-only trigger: it does not activate post-S10 work by itself.

After that message:

1. stop provisional writes and freeze exact provisional head/tree/ledger;
2. obtain and validate a new external `V30PostS10ReconciliationAuthorityV1` package;
3. prove S is an accepted Phase 10.6 plus lossless-V23 exact-main lineage, with all 146 V23 cards/230 edges represented, the four unfinished V23 states preserved, and green exact-main evidence;
4. create the separate reconciliation worktree from accepted S;
5. compute three-lineage B/P/S differences;
6. replay or reimplement each frozen provisional-cohort delta in graph order;
7. let accepted Phase 10 own actual brand/UI conflicts while reapplying V30 semantics;
8. rerun all invalidated checks;
9. perform canonical coordination adoption;
10. continue Card 44 / V30-P06-C01 only after P05-C06.

## Subagent routing

- Reuse relevant agents when their context is still valid.
- Use Luna max for bounded inventory, extraction, hash, hygiene, monitoring, and deterministic support.
- Use Terra at the lowest sufficient medium/high/xhigh/max level for substantive implementation, tests, tooling, reviews, and CI analysis.
- Use Sol low/medium for the most consequential integration, architecture, and CI decisions.
- Give every agent: exact objective, allowed/read-only paths, pins, invariants, commands, prohibitions, and decision-ready return format.
- Never give two agents concurrent write ownership of the same path.
- Keep one independent audit lane for consequential contracts/integration when capacity permits.

## Fresh-task stop conditions

Stop mutation and report a read-only hold for:

- any package hash mismatch or placeholder;
- absent/mismatched owner-message `authorityID` or `authorityContentDigest`;
- target branch/worktree collision not proven to be exact idempotent state;
- frozen V23 or coordination mismatch;
- unowned dirty/untracked work;
- unclassifiable path ownership;
- a card fence that is not fully expanded;
- a required owner/professional/legal/release fact;
- an attempted post-S10-cohort selection before validated `V30PostS10ReconciliationAuthorityV1`;
- an S10 overlap lacking its exact pre-issued tuple.

Do not stop merely because Phase 10 is still running. Provisional graph progression through Card 37 is authorized, but it creates no final, canonical, post-S10, main, release, or successor credit.
