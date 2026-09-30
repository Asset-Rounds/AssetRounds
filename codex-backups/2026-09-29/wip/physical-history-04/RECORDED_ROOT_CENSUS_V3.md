# Recorded root census and segmented mixed controls

Working physical successor; GPT-6.1 Sol xhigh. This document defines pure data APIs and exact mapping, not authorization, compilation, runtime, review or gate evidence.

`EraseSchema2ColdPhysicalCleanupOwnerV1.recordedRootKeys` fixes original wire order:

| Tree key | Named parent | Prospective generic target identities |
| --- | --- | --- |
| support/FieldEvidenceRestore | support | none |
| support/FieldEvidenceCommerce | support | none |
| support/FieldEvidenceDiagnostics | support | none |
| support/LocalSearchIndexV1 | support | projection.json, root if originally absent |
| support/PortableReviewExchangeV2 | support | none |
| support/local-jobs-v1 | support | none |
| support/FieldEvidenceOperations | support | AppLockNotificationControlV1/notification-erase.json, Notification root if originally absent |
| caches/FieldEvidenceApp | caches | none |
| temporary/FieldEvidenceApp | temporary | none |

A root node uses exactly the key, while a descendant uses `key/relativePath`. Relative path components are nonempty, contain no NUL, and are neither `.` nor `..`. The three parent-only projection roles are `support`, `caches`, `temporary`. No Data/Erase descendant enters this projection: their actual private generation and Store owners prove those separate domains, avoiding self-containing or future SHA claims. The Support closed direct names still include the actual Data and Erase roots.

Actual full fact has exactly eleven fields: `dev|ino|mode|uid|gid|nlink|size|mtime_s|mtime_ns|ctime_s|ctime_ns`. The immutable persisted nine-field fact removes only UID/GID, mapping full indices `[0,1,2,5,6,7,8,9,10]`. No historical UID/GID is manufactured. Each current root has actual parent-derived UID/GID/device, private directory 0700/file0600 and real scope/PFP observation.

For every original present tree, `nodes.count < 100000`, directory relative depth <=64, regular file relative depth <=65, individual file bytes <=1GiB and the sum of all regular entries (including both recorded aliases) <=1GiB. Every current scanner tree retains its existing <=100000 node count, the same depth and byte bounds. C16 semantic plan independently retains its <=100000 steps. These are per-domain bounds; no global mixed 100000 count narrows all nine original trees.

Pure nested data type:

```swift
struct RecordedRootCensusV1: Codable, Equatable {
    let key: String
    let originalNodeCount: Int
    let originalRegularBytes: Int64
    let genericTargetCount: Int
}
static func fixedRootCensus(originalP: EraseSchema2ColdAuxiliaryPhysicalRosterV1,
    c16Plan: OriginalEraseC16PlanV1, targetGenerationID: UUID)
    throws -> [RecordedRootCensusV1]
static func requireRecordedProjectionCensus(
    originalP: EraseSchema2ColdAuxiliaryPhysicalRosterV1,
    projection: [EraseSchema2ColdCleanupProgressV1.Projection]) throws
```

The exact logical count is C16 steps plus the sum of these derived generic counts, committed losslessly by the new Store control segments in logical ordinal order. `fixedRootCensus` computes from the authentic immutable canonical P and the existing `fixedNonC16Targets`; it never enumerates Q/R to derive target names. `requireRecordedProjectionCensus` checks finite grammar, ownership lineage and per-tree bounds of actual full11 data; it grants no permission and cannot replace the genuine scope, current Store CAS, source, external receipt, policy or OS result. The retained owner validates P once as immutable data and checks each actual image bound afresh; it never caches authorization.

Generic order: unowned Scratch lease/orphan original postorder first; all non-Operations trees in fixed recorded order and original postorder; Operations remaining original controls postorder; Operations root last. C16 subsequence and every generic ordinal remain fixed in the central mixed table. Registry token descendants are removed only by the authentic retained drain. Old Notification descendants are consumed only by actual typed absence/present-removal and real OS observations. The exact target-generation Manifest leaf is moved only by real incumbent retirement, while every other schema-migration control stays in generic original postorder. None of those exclusions is justified by current survivors.

Generic physical execution creates no nodes. Search `projection.json` and Notification `notification-erase.json` each add at most one fixed prospective leaf and at most one corresponding original-absent root; actual presence, bytes, ownership and directory facts require real respective owner receipts, and contribute to that tree's current limits. Every C16 prospective birth is exact finite plan `allowedBirthPaths` plus genuine Ledger born-source receipts, confined to Operations. Registry projection is an authentic retained reader/drain census, not generic birth authority. Manifest has only exact target-preservation/retirement effects; no generic producer or policy repair is invoked.
