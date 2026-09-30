# Live original Scratch Registry G component

Migration alone mints `OriginalEraseScratchCleanupHeldGScopeV1`. Its fileprivate constructor is reached after actual process/G lock acquisition, genuine original-owner hook, current canonical P/preparation, no active migration reservation, and the checked canonical Registry cohort read. It retains the actual Registry, operation, Store, EX and activity before the effect callback.

```
withOriginalEraseScratchCleanupEffect(
    activity: GenerationTemporalActivityHandleV1,
    operation: EraseRouterOperationV1,
    store: EraseIntentStore,
    exclusion: StoreTemporalNormalizationExclusionV1,
    _ body: @MainActor (OriginalEraseScratchCleanupHeldGScopeV1)
        throws -> OriginalEraseScratchCleanupReceiptV1
) throws -> OriginalEraseScratchCleanupReceiptV1
```

`scope.requireHeld(operation:store:registry:exclusion:activity:)` requires this exact active object, actual depth-one G, actual existing exclusive activity, strict held/named Registry controls and the central pure under-G same-owner/cohort hook. It neither performs a recursive census nor takes SH/EX/G. `scope.requireCheckedRelease` is DATA proving this object's checked lexical G release, not a future permission or Ledger-resource-close certificate.

Central supplies `requireOriginalEraseScratchCleanupEffectUnderHeldG(registry:activity:store:exclusion:) -> [GenerationLeaseTokenV1]` and permanent `failOriginalEraseScratchCleanupEffect()`. The fixed actual caller is in copied CENTRAL_ROUTER_ACTUAL_CALLER_HOOKS_V1, SHA5f7ae445: the effect permit is created only after the real Operations FD opens and revoked before Operations close; the outer retained parent loan proves this still-held scope before and after. No revoked effect permit is revived.

Ledger supplies a privately issued actual receipt with `requireCheckedSettlement()` and `requireBound(operation:store:registry:exclusion:activity:)`. Its latter call must use actual retained pure origin after the effect permit is revoked. A foreign/forged receipt cannot bind. The copied unsealed Foundation V2 shows this API; the complete fixed engine and its coupled full-image/PFP producers are external pending source.

The ordinary verifier, constructor, activity validation and no-migration loader remain byte-identical. This lane uses new fixed, nonrepairing held/named validation and operation-retained checked leaf/directory reads. Directory child-link changes retain the baseline Identity predicate; the exact owned link/full-fact delta belongs to the central/physical whole-image proof, never to a Registry nlink waiver.
