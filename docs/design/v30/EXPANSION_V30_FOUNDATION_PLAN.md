# AssetRounds V30 Globalization Foundation Plan

## Status

- Revision: R2
- Prepared: 2026-09-02
- Owner intent: begin provisional V30 implementation today while Phase 10 continues independently
- Product: one AssetRounds iPhone app
- Initial market, storefront, and project jurisdiction: United States only
- Initial complete localization cohort: `en`, `es`, `zh-Hans`, `zh-Hant`, `vi`, `ko`
- Provisional branch/worktree: `phase/v30-globalization` / `C:\AssetRounds-v30-globalization`
- Reconciliation branch/worktree after Phase 10.6: `phase/v30-globalization-reconciliation` / `C:\AssetRounds-v30-globalization-reconciliation`
- Active Phase 10 checkout: `C:\AssetRounds` — permanently forbidden to V30; later reconciliation uses externally supplied accepted evidence and a separate clean worktree
- Complete architecture and graph: `EXPANSION_V30_ARCHITECTURE_BLUEPRINT.md`
- Fresh-task authority: external `V30PreS10ProvisionalImplementationAuthorityV1`, activated only by an owner message that names its exact `authorityID` and `authorityContentDigest`

This file is part of a hash-bound owner handoff. It does not authorize itself. The owner activates the external authority by sending the companion prompt as a user message in a new Codex task; absent or mismatched authority ID/content digest is a read-only hold. The Foundation Plan, Architecture Blueprint, Fresh-Task Handoff, and copy-ready prompt are immutable external package inputs. Execution evidence belongs only in installed `docs/design/v30/execution/V30_EXECUTION_HANDOFF.md`.

## 1. Decision

V30 begins now from the exact frozen V23 expansion head, in a separate Git worktree. It does not wait for Phase 10.6 to finish before doing useful implementation.

This is safe because:

1. V30 never operates in the Phase 10 checkout.
2. Pre-S10 results are quarantined as provisional and cannot reach `main`.
3. Every changed file is card-fenced and every S10-reserved overlap is labeled.
4. After Phase 10.6, V30 is replayed or reimplemented card by card onto the accepted Phase-10/V23 lineage.
5. All invalidated tests and evidence are rerun before final acceptance.

The provisional branch is not merged wholesale. The reconciliation branch is the only future V30 lineage eligible for final acceptance and a non-force `main` fast-forward.

## 2. Frozen inputs

| Input | Exact value |
|---|---|
| Repository | `https://github.com/Asset-Rounds/AssetRounds.git` |
| Frozen V23 branch | `phase/v23-expansion` |
| Frozen V23 head | `acbfb68355f903fe98638b6ef22e4814e7b48328` |
| Frozen V23 tree | `47e17fae6b73dccd5029ccf4ac7cca659196f225` |
| Frozen V23 package digest | `99a2719885ad1abfb8cf5d49c6b2099754bb0ba4b5d27fcbae06476aad507570` |
| V23 graph | 146 cards / 230 direct edges |
| Frozen coordination head | `51ef2b3d970a25b4c83df8c8238609316e37034e` |
| Frozen coordination tree | `060c83c3d1489fc011b1c921f6c85bec2b074478` |
| Frozen coordination sequence | 626 |
| Frozen coordination ledger digest | `973090852e843e895125bea8da87c7e1689611c46d8219a70c1749be49398067` |
| Frozen coordination projection digest | `cf57849e8f7c245d38fd21a39da5938d10e13c9aca3976a71b7d3a3ee401f12d` |
| S10 reservation artifact raw SHA-256 | `9f7c27431271728d167731d4af806c7449447dfbcc8bf46778102e2f9a89b576` |
| S10 ordered reservation | 86 paths |
| S10 reservation content digest | `274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a` |
| Preserved R1 V30 blueprint SHA-256 | `81c74f074ea2af4500883b56117813cc3f0c85ba059e7a568db1ef17e019c84c` |
| V24 planning-input SHA-256 | `370c378bbb3b567c465d217111e8de3342581916e260b234a32511e807c01d94` |

V23 unfinished truth remains:

- Card 135 / V23-P05-C02 — OWNER_ACTION, NOT_STARTED
- Card 136 / V23-P05-C03 — MONITOR, NOT_STARTED and unarmed
- Card 141 / V23-P06-C05 — DEFERRED
- Card 146 / V23-P06-C10 — DEFERRED

V30 cannot fabricate, reclassify, or satisfy them.

## 3. Two execution epochs

### Epoch A — work today

The 37-card pre-S10 provisional cohort enumerated in the machine register, ending at `V30-P04-C07`:

- provisional authority, ledger, CI, and replay contracts;
- research freeze and scope disposition;
- complete string/surface inventory;
- language/locale/content/report/storefront/jurisdiction contracts;
- canonical-data invariance;
- system/per-app language resolution and English fallback;
- locale-aware formatting and input;
- catalog release/provenance/offline behavior;
- English normalization;
- Unicode, RTL, long-text, Dynamic Type, accessibility, fonts, search, and Settings;
- field workflows, forms, reports/PDFs, CSV/JSON, sharing, OCR/dictation truth, backup/restore, errors, permissions, notifications, and recovery;
- termbase and translation workflow;
- Spanish, Simplified Chinese, Traditional Chinese, Vietnamese, and Korean;
- provisional shared catalog/project integration.

Every terminal result is `PROVISIONAL_CHECKPOINTED` with `finalCredit=false`.

Locale agents may use parallel read-only preparation, but exactly one V30 card may mutate, checkpoint, or transition at a time.

### Epoch B — after an external reconciliation authority is validated

The 18-card post-S10 cohort enumerated in the machine register, beginning at `V30-P05-C01`:

- verify accepted Phase 10.6 and V23 evidence;
- freeze B/P/S lineages;
- create a new reconciliation branch from accepted S;
- replay or reimplement every V30 card-scoped delta;
- preserve V23 unfinished-card truth;
- rerun invalidated hosted evidence;
- adopt reconciled V30 into canonical coordination;
- run complete-locale machine audit;
- obtain professional/native in-context review;
- run multi-locale UI/accessibility and output/offline/invariance qualification;
- prepare truthful U.S. metadata/screenshots;
- accept U.S. legal/privacy/support readiness;
- accept one exact V30 candidate;
- non-force integrate to `main`;
- keep release, future-country activation, and monitoring owner-gated.

An owner report that Phase 10.6 is complete is only a read-only trigger. It cannot select these cards. Before any post-S10 mutation, validate a new external `V30PostS10ReconciliationAuthorityV1` and prove S contains accepted Phase 10.6, lossless V23 representation of all 146 cards and 230 edges, preservation of the four unfinished V23 states, and green exact-main evidence.

## 4. Phase 10 isolation

At any time, including after the owner trigger, a V30 task must not:

- read any file under `C:\AssetRounds`;
- run status/log/diff/fetch/build/test commands with that path as a target;
- poll its branch, workflows, processes, or completion;
- mutate an S10 ref;
- infer current Phase 10 truth from worktree metadata.

Pre-S10 authority also forbids every `main` mutation. Any later main integration requires the separate post-S10 authority and exact acceptance evidence; it never permits access to the active Phase 10 checkout.

The frozen 86-path reservation is a planning input. It no longer blocks useful work on a separate V30 branch. Instead:

- disjoint paths are `V30_PROVISIONAL_OWNED`;
- an exact card-fenced overlap carrying its exact pre-issued authority tuple in both `allowedPaths` and `s10SharedPaths` is `S10_SHARED_RECONCILIATION_REQUIRED`;
- an unowned, unexplained, or tuple-less overlap is `CONFLICT_HOLD`.

No overlap affects the active Phase 10 checkout because V30 writes only its own worktree. At reconciliation, accepted Phase 10 owns brand/design truth on actual conflicts and V30 semantics are reapplied against that truth.

## 5. Language and jurisdiction rules

The required initial binary localizations are:

| Binary ID | Recommended resource profile | U.S. App Store metadata label |
|---|---|---|
| `en` | `en-US` | English (US) |
| `es` | `es-US` with es-MX/es-419 validation | Spanish (Mexico) |
| `zh-Hans` | Simplified-script resource | Chinese (Simplified) |
| `zh-Hant` | Traditional-script resource | Chinese (Traditional) |
| `vi` | Vietnamese resource | Vietnamese |
| `ko` | Korean resource | Korean |

These are binary/resource and metadata decisions, not foreign-market claims. Storefront and project jurisdiction stay U.S.-only.

The app:

- follows Apple device/per-app language resolution;
- exposes the effective language in AssetRounds Settings with an iOS Settings handoff;
- falls back exact locale → base language → English;
- never shows raw keys;
- keeps app language, formatting locale, authored content, report language, storefront, and jurisdiction separate;
- never stores translated display text as canonical business truth;
- never infers standards, qualifications, OCR/dictation capability, or legal scope from language.

Future-language research order is pt-BR, fil, ar, fr/fr-CA, ru, pl, hi, id, ja, tr, and ht. It creates no automatic scope.

## 6. Evidence law

The following never provide final card, phase, main, release, or successor credit:

- planning;
- research;
- generated/static evidence;
- Windows-only checks;
- pre-S10 commits;
- pre-S10 hosted CI;
- provisional translation;
- provisional review;
- failed/superseded candidates;
- owner-action placeholders;
- deferred or monitor state;
- package installation.

Final credit requires post-S10 reconciliation, exact reconciled head/tree evidence, all card-specific acceptance, canonical CAS admission, and—where required—exact-main hosted CI.

Every card in the graph-enumerated pre-S10 provisional cohort may progress and preserve evidence, but never provide final, canonical, post-S10, main, release, or successor credit.

## 7. Git and recovery law

- Never force-push.
- Never merge the planning or provisional branch wholesale.
- Never rewrite accepted history.
- Preserve every failed/superseded candidate.
- Use exact-path staging and direct-child corrections.
- Re-fetch before any authorized remote mutation.
- A mismatched branch, head, tree, digest, path fence, ledger CAS, or package hash changes nothing and returns to read-only diagnosis.
- Signing, TestFlight, App Store submission, availability, foreign storefronts, and release are outside pre-S10 authority.

## 8. Immediate next action

The fresh Codex task:

1. reads the complete package;
2. validates every hash and frozen pin without accessing `C:\AssetRounds`;
3. verifies the execution branch/worktree are absent or exactly resumable;
4. creates `phase/v30-globalization` and `C:\AssetRounds-v30-globalization` from exact frozen V23;
5. uses the closed bootstrap exception only to install all and only manifest-enumerated package support artifacts, including immutable external package inputs;
6. creates the sole expected-absent G3 namespaced provisional ledger and receipt;
7. selects only Card 1, `V30-P00-C01 — Provisional authority and isolated-lane validation`, through `docs/design/v30/execution/V30_CURRENT_TASK.md` and `docs/design/v30/execution/V30_CI_SELECTION.json`; P00-C03 validates G3 rather than creating another ledger;
8. proceeds through the closed graph without polling Phase 10.

If Phase 10.6 remains incomplete after Card 37, freeze and wait for the user's report.
