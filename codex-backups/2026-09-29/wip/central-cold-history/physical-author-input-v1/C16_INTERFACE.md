# Cold Ledger continuation interface v1 (author contract, 2026-09-29)

Author GPT-6.1 Sol xhigh. Parent b24e/7341 at dbdb. This is an interface agreement and implementation authority, not completed source or verification. Root authorized new private versioned Erase controls under decisions 14/20 and frozen Blueprint1802/1821, DeletionRights105–123, OwnedStorage98–103, LocalJob295–321. Existing intent/preparation/roster formats, existing C16 plan declaration/bounds, all registered kinds and engine remain unchanged.

## Ownership

Ledger author owns its separate OwnedStorageLedgerV1 candidate. This packet retains that before/candidate unchanged. This author owns Router/Store/Manifest/observer/Service/Factory/Coordinator. Root alone composes/imports/compiles/tests.

## Concrete callable contract

Router defines @MainActor `EraseSchema2ColdScratchLifecyclePermitV1` with fileprivate issuer/revocation, internal `requireHeld() throws`, `poisonOnUncertainEffect()`, and `requireTransferredSource(path: String, bytes: Data, fullFact: String) throws`, plus `canonicalTransferredSource(path: String) throws -> (bytes: Data, fullFact: String)` for fixed replay dependencies whose physical source has disappeared, and `originalPPhysicalFact(path: String) throws -> String?` for bounded read-only lookup in the immutable complete original-P Operations roster. The latter rejects unknown/unassigned paths; nil proves exact original-P absence for an already fixed semantic plan dependency, never generic absence permission. Permit is lexical under the actual schema2 Registry G and retained Support EX. Checks bind exact cold operation, immutable original-P auxiliary roster SHA, canonical current Store progress record and fixed C16 ordinal, held support/Operations parents, original control/payload source facts, unchanged branches and actual registry census. It is revoked before G release. No cached permission/ordinary SH or nil success.

Ledger exposes the new entry (same borrowed shared engine, not a second engine):

```swift
@MainActor static func withSchema2ColdBorrowedExistingRoot<Value>(
    applicationSupportURL: URL,
    operationID: UUID,
    permit: EraseSchema2ColdScratchLifecyclePermitV1,
    frozenGenericLeaseAdmission: OriginalEraseFrozenLeaseAdmissionV1? = nil,
    referencePlan: OriginalEraseC16PlanV1? = nil,
    referenceProgress: OriginalEraseC16ReferenceProgressV1? = nil,
    verifyPostimageBeforeClose: @MainActor (Bool, Bool) throws -> Void,
    _ body: @MainActor (ScratchDataLeaseStoreV1) throws -> Value
) throws -> Value
```

The `OriginalEraseC16*` pure plan/step/projection/fact types and `OriginalEraseFrozenLeaseAdmissionV1` use the exact ba657 declaration/bounds as direction, independently implemented/adapted against current3224; no whole-file import or inherited approval. `OriginalEraseC16PlanV1.maximumEncodedBytes` stays 96 MiB and 100,000 limits stay unchanged. Planning is `originalEraseC16PlanFromFirstP(firstPPartials:)` only after Router positively proves current source bytes/facts identical to the immutable original-P roster. Existing plan is passed before fresh-owner admission; never mint from a Q survivor.

Execution uses `performOriginalEraseC16Step(_:ordinal:plan:controlMarkerState:ingressMarkerState:requireCut:)`, and retains the existing read-only semantic expected-tree/projection APIs with exact first-P/captured-birth source choices. Require real MainActor permit checks before/after every effect/semantic read/close and retain uncertain descriptors with numeric-FD reuse fencing. All pending/H/E, cross-H and claim-only relationships are required; no permanent valid-state refusal, arbitrary hole or empty-only path.

Store defines `OriginalScratchLifecycleRecordV1.Stage` with exact values PREPARED/PREPARING/PREPARING_CAPTURED/COMPLETED/COMPLETED_EMPTY/PHASE_CAS_PREPARING/PHASE_CAS_COMPLETE, preserving the reference stage meanings. Cleanup-only stages never enter Ledger. Router derives `completedC16PrefixCount` and `activeC16Ordinal` solely from the fixed `.c16` subsequence and authenticated canonical record; never mixed root ordinal. Require full plan.steps equality.

## Durable source transfer

New private versioned Erase control `schema2-cleanup-sources-v1.json` stores schemaVersion1, eraseID, preparationSHA256, originalPAuxiliaryRosterSHA256, targetPointerSHA256, C16 canonical plan SHA/leaf binding and a sorted unique source table. Each source has `path` relative to Operations, `fullFact`, `sha256`, exact byteCount and a fixed content-addressed Erase source-leaf name/fact. Source leaves contain the exact canonical source bytes, with the original source maximum enforced per leaf (no base64 wrapper that narrows or inflates it); the versioned index enforces the existing96 MiB/100,000 metadata/plan limits. Source-control bytes are not duplicated into the existing C16 plan. No plan field/bound inflation. It is published/read back under actual original-P or positively original-P-matching cold admission before any of its source leaves disappear. First observed canonical/control full facts/policy are retained before effects. Source entries must match the immutable physical roster's exact path/full fact/SHA; actual born markers are transferred by a second PREPARING_CAPTURED CAS before their dependencies disappear. No unknown path, same-name substituted source or current-Q replanning is admitted.

New private versioned `schema2-cleanup-progress-v1.json` binds the source-control SHA/first physical fact, complete fixed mixed target order, actual canonical stage/ordinal, checked prefix, current exact physical projection and captured births/transitions. Store owns all checked publication/CAS/pair/zero-prefix authentication/readback. Ledger never advances Store ordinals. `requireTransferredSource` succeeds only after Store authenticates the matching source transfer/control and fresh record readback, and only for the currently bound fixed semantic effect. Readback transferred canonical bytes is data authority for that exact source; it never mints EX/G or terminal retirement.

Ledger's fresh/born E/scratch marker observations must be surfaced before any dependency deletion through `requireCut` / captured-birth observation callbacks; Router persists/readbacks PREPARING_CAPTURED then re-enters the exact step. Report any concrete additional callback/signature required before authoring an incompatible API. Current normal P/Search/Notification producer SH and callback/publisher/fd0a remain unchanged.

## Verification obligations (root)

DEBUG/nonDEBUG parse only at authors. Root coupled compilation precedes tests. Require populated all C16 classes and scratch generic leases/orphans; simultaneous/overlapping H; claim-only H partial/absence; current fixed E suffix; original pending/terminal transfer; exact nlink2 pair and zero/prefix temporary cuts; policy/setter/rename/link/fsync/close interruption; same owner/fresh owner; wrong source/policy/sibling/ordinal/readback and ambiguous close no-effect refusal. Full family joins Q/R/rostered cleanup and terminal absence/provenance before ready, with no original callback or duplicate writer/reader.
