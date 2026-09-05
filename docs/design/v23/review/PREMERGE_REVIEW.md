# V23 pre-merge review — 2026-09-05

## Decision

**Not cleared for integration or release yet.** All 146 cards are accounted for, but the frozen V23 ledger records provisional/static preparation, not native implementation/adoption/acceptance credit. This review fixes demonstrated source defects on a separate branch. It does not complete the reserved Phase 10 integration or turn historical static receipts into runtime evidence.

Review output: `codex/v23-premerge-review-20260905` in `C:\AssetRounds-v23-premerge-review`, based on `acbfb68355f903fe98638b6ef22e4814e7b48328`. Coordination input: `51ef2b3d970a25b4c83df8c8238609316e37034e`, sequence 626. The frozen V23 branch, canonical coordination, original app, Phase 10 and V30 are not modified by this review.

## Coverage and limits

See [CARD_COVERAGE.md](CARD_COVERAGE.md) for the full 146-card evidence inventory. All cards have ledger rows; 141 have provisional candidate identities. Latest ledger states: 121 CHECKPOINTED, 14 TARGETED_GREEN, 5 VERIFIED_PROVISIONAL, 3 NOT_STARTED, 2 DEFERRED, 1 IMPLEMENTING. Those names do not establish native test success: all relevant implementation/adoption/acceptance/native/hosted/physical/phase/main/merge/release credits remain false.

The five inactive entries are the S10 activation/bootstrap dependency V23-P00-C03 and the four previously known unfinished cards: Card 135 / V23-P05-C02 owner action; Card 136 / V23-P05-C03 unarmed monitor; Card 141 / V23-P06-C05 deferred; Card 146 / V23-P06-C10 deferred. No card was silently omitted by this review.

Deep source review targeted mutation replay and receipt identity, backup decoding, generation fences, runtime composition/navigation, search/report seams, and the repeated throwing-closure defect family across app/test sources. This is not an exhaustive semantic review of every source line or a full security assessment. Presence of a manifest, contract, fixture or test is not proof that its feature works on an iPhone.

## Corrections

| Finding | Correction | Regression/evidence |
| --- | --- | --- |
| Throwing calls inside closures lack inner `try`, preventing compilation | 136 annotation insertions in 41 source paths; no validator or acceptance assertion removed | Source-resolved throwing methods/getters; inversion check and repeated bounded family scan. Native type-check still required. |
| Malformed backup nested release identities can trap in `Dictionary(uniqueKeysWithValues:)` | Collision-checked release index throws `invalidRecords` | Three decoder tests: valid unique release; duplicate payload under distinct outer IDs; distinct valid records with duplicate nested release identity. |
| Successful measurement retry is rejected against already-advanced live revisions | Validate durable receipt identity before optimistic revision comparison, retaining active-writer/workspace/reentrancy/current lease checks | Five real-store tests: exact retry, reopening, divergent mutation reuse, invalidation, and released lease. Compare rows, receipt/envelope bytes and revisions. |
| First shop profile mutation rejects nil predecessor at revision zero | Handle initial revision separately from successor predecessor equality | First-save paths in real-store shop tests; preserve stale successor rejection. |
| Shop profile exact retry is treated as a successor of itself | Recognize an exact immutable history item and delegate to typed durable receipt validation before live revision comparison | Four real-store tests: exact retry, historical retry after successor, divergent mutation reuse, stale new write. |
| Initial round session mutation has the same nil-predecessor comparison defect; its receipt retry also bypasses a released lease | Accept the valid first revision and validate the existing writer lease before receipt lookup | Three tests: valid initial/bound successor, hostile constructor inputs, released-lease replay rejection. |
| Fresh Windows checkout changes hash-pinned Python bytes to CRLF | Add `*.py text eol=lf` to `.gitattributes`; normalize only clean Python checkout bytes without a source/index delta | Manifest verifier originally failed its raw hash test; all 50 cases pass after normalization without changing stored hashes. |
| Active agent routing differs from owner's Astra preference | Review-specific active authority/routing in `AGENTS.md` | Historical model wording, frozen plans, and receipt hashes preserved. |

Exact causal paths and constraints are listed in [CURRENT_REVIEW.md](CURRENT_REVIEW.md). No speculative feature, schema migration, entitlement, dependency, backend or release metadata was added.

## Verification evidence

- `python -B Scripts/v23/verify_card_contracts.py`: PASS, 50 tests, zero failures/errors after LF checkout correction; acceptance and release disabled.
- `python -B Scripts/v23/verify_controller.py`: PASS, 31 cases; no provider mutation or acceptance.
- All 422 tracked Python files passed in-memory syntax parsing in the initial source audit. This is Python syntax evidence only.
- `git diff --check`: PASS at source checkpoints; final check recorded with the review delivery.
- Repeated bounded throwing-closure scan: no remaining matches in the audited family. This does not prove absence of other Swift compile errors.
- Fifteen new XCTest methods are selected in `Scripts/ci-selection.json`; Windows cannot execute them. Hosted diagnostic result is pending below.
- Historical per-card verifiers remain bound to their historical heads/coordination. For example P06-C09 reports COORD_IDENTITY_MISMATCH at the final coordination tip; do not falsify its old pins to make it pass on this branch.

## Native diagnostic

Run [33979981288](https://github.com/Asset-Rounds/AssetRounds/actions/runs/33979981288) verified head `074dba9eb40af6be12787e7ddfeb6751d4011832` and passed toolchain/setup/simulator checks, then **failed Swift parsing during build-for-testing**. All 15 selected tests were skipped; no native pass is claimed. Build errors identify 43 source paths (648 repeated diagnostic lines, including cascades), primarily ambiguous guard closures, malformed compressed declarations and expressions. This is a product-source failure, not a runner failure.

Downloaded evidence: `C:\AssetRounds-v23-review-evidence\33979981288\ios-ci-33979981288-1`; includes build log and `Build.xcresult`. Runner image `20260728.0273.1`, Xcode26.6/17F113, iPhone17/iOS26.2, UDID `9AA9ED9B-42D2-4F6E-B8B5-45AAB66D6404`. Compiler correction batch 2 is partially saved at the owner's requested turn boundary. See CURRENT_REVIEW for exact resumed work; do not treat the checkpoint as a completed compiler fix or dispatch before the remaining lanes and independent review finish.

Independent evidence audit: all 22 SHA256SUMS members exist and match. The 648 error lines represent 324 normalized file/site/message diagnostics at 296 unique file:line:column sites; each normalized diagnostic occurs twice. These counts include parser cascades, not 324 independently proven behavioral bugs. There is no UnitTests.xcresult or executed-test evidence. The SDK recorded by the build is iOS Simulator 26.5, distinct from the selected iOS 26.2 runtime.

Batch-2 source completion: resumed the saved checkpoint and finished all compiler-reported path corrections. Independent audits verified that existing predicates/data values/order remain intact; the restored derivative failure branch uses its adjacent `invalidPlan` contract, and the added getter brace closes the correct property. Static checks again pass (50 card-contract tests, 31 controller cases, diff hygiene). Native parsing/type-checking and execution of the 15 regressions remain unproven until the fresh diagnostic completes.

## What still blocks a safe final merge

1. Reconcile against the accepted Phase 10 head when the owner declares that work ready. Preserve branding, original navigation and sole-writer ownership; do not blindly merge old app roots over the accepted app.
2. Complete production composition and feature-root adoption explicitly deferred in V23. The incumbent shell still launches; a production-root type existing in the source does not mean V23 is wired into the running app.
3. Compile the combined source and test targets, resolve genuine compiler/test failures, run required card-native selectors and golden-path parity on that exact integrated head. Existing V23 UI test skip paths are not test passes.
4. Verify migration, backup/restore, mutation replay, deletion/Erase, search rebuilding and immutable report history against the combined schema and actual runtime.
5. Carry these review corrections into V30's eventual reconciliation too. V30 descends from the frozen V23 base; it must not lose later fixes or overwrite them with older versions.
6. Resolve the owner/deferred cards through their actual acceptance authority. Signing, store submission, physical/legal evidence and release decisions are not supplied by this source review.

## Premium-quality priorities

Reliability comes first: safe backup rejection, exactly-once save/retry behavior, clear failed-save recovery, migration preservation and reproducible reports. After the roots are wired, verify real-device navigation, empty/error/loading states, accessibility/Dynamic Type, search responsiveness and report fidelity. Localization remains owned by V30, not a competing new implementation here. These are integration review priorities, not claims that new features were added or verified in this pass.
