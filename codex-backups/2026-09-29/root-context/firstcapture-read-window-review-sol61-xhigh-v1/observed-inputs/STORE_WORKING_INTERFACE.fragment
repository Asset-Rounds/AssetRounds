// GPT-6.1 Sol xhigh. Interface-only working V4 agreement, no implementation.
// Syntax-only protocols avoid bodyless concrete methods. External actual owner
// types remain counterpart compile dependencies; no protocol mints authority.
import Foundation

enum EraseSchema2ColdTableRoleV4: UInt8, CaseIterable {
    case originalSources = 1, originalPairs = 2, pairPredecessors = 3
    case mixedTargets = 4, targetDependencies = 5, bornProducerSlots = 6
    case currentProjection = 7, capturedBirths = 8, rawBlobCatalog = 9
    case registryPrefixProjection = 10, registryDispositions = 11
    case terminalDeletionCatalog = 12
}

enum EraseSchema2ColdProducerRoleV4: UInt16 {
    case leaseMetadata = 1, opaqueIngressPayload = 2, scratchControlErase = 3
    case hygieneReceipt = 4, hygieneFinalizing = 5, finalizedHygienePrepare = 6
    case hygienePrepare = 7, ingressErasePrepare = 8, ingressEraseComplete = 9
    case ingressPreparation = 10, ingressClaim = 11, ingressPublication = 12
    case ingressPending = 13, ingressTerminal = 14, ingressAborted = 15
    case freshIngressErasePrepare = 16
}

struct EraseSchema2ColdTableCommitmentV4: Equatable {
    let role: EraseSchema2ColdTableRoleV4
    let rowCount: UInt64
    let logicalByteCount: UInt64
    let leafCount: UInt64
    let treeLevel: UInt8
    let logicalRootSHA256: String
    let commitmentSHA256: String
}

// Eleven numeric slots, canonical decimal reconstruction in exact captured
// order. Signed time/size/device slots encode two's-complement bits; small
// unsigned slots validate against actual source type's range before use.
struct EraseSchema2ColdNumericFullFactV4: Equatable {
    let device: Int64
    let inode: UInt64
    let mode: UInt32
    let user: UInt32
    let group: UInt32
    let links: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64
}

struct EraseSchema2ColdPageDescriptorV4: Equatable {
    enum Kind: UInt8 { case metadataLeaf = 1, metadataIndex = 2, rawSource = 3, fixedControl = 4 }
    let role: EraseSchema2ColdTableRoleV4
    let level: UInt8
    let kind: Kind
    let flags: UInt8
    let epochSHA256: String
    let publicationOrdinal: UInt64
    let physicalSHA256: String
    let fullFact: EraseSchema2ColdNumericFullFactV4
    let fileByteCount: UInt64
    let firstPostorderOrdinal: UInt64
    let lastPostorderOrdinal: UInt64
    let subtreePhysicalFileCount: UInt64
    let logicalOffset: UInt64
    let logicalByteCount: UInt64
    let firstIntersectingRow: UInt64
    let rowCount: UInt64
    let logicalSHA256: String
    let firstKeySHA256: String
    let lastKeySHA256: String
    // Canonical512 bytes; field offsets pinned by contract, trailing188 zero.
}

struct EraseSchema2ColdBornSlotIdentityV4: Equatable, Hashable {
    let slotOrdinal: UInt64
    let producerOrdinal: UInt64
    let role: EraseSchema2ColdProducerRoleV4
    let operationsRelativePath: String
    let mixedTargetIndex: UInt64
}

struct EraseSchema2ColdCapturedVersionV4: Equatable {
    let slot: EraseSchema2ColdBornSlotIdentityV4
    let payloadSHA256: String
    let originalSourceFullFact: EraseSchema2ColdNumericFullFactV4
    let sourceByteCount: UInt64
    let rawBlobSHA256: String
}

struct EraseSchema2ColdCurrentC16RecordV4: Equatable {
    let planSHA256: String
    let actualManifestSHA256: String
    let actualManifestFullFact: EraseSchema2ColdNumericFullFactV4
    let recordBindingSHA256: String
    let logicalProgressSHA256: String
    let progress: OriginalEraseC16ReferenceProgressV1
    let completedMixedPrefixCount: UInt64
    let activeMixedTargetIndex: UInt64?
    let capturedSlotCount: UInt64
    // ReferenceProgress Int fields use exact checked UInt64->Int conversion;
    // completed/active C16 are derived solely from retained mixed Target rows.
}

struct EraseSchema2ColdPairAccountingSourceHeaderV4: Equatable {
    let originalOperationID: UUID
    let eraseID: UUID
    let captureToken: String
    let originalRosterSHA256: String
    let rowCount: UInt64
    let pairTableCommitmentSHA256: String
    let predecessorTableCommitmentSHA256: String
    let actualSourcesManifestSHA256: String
    let actualSourcesManifestFullFact: EraseSchema2ColdNumericFullFactV4
    let sourceCutBindingSHA256: String
}

struct EraseSchema2ColdPairAccountingRowCoreV4: Equatable {
    enum Kind: UInt8 { case canonicalProducer = 1, observedOwnedGenericAliases = 2 }
    enum MetadataState: UInt8 { case notApplicable = 0, validatedLease = 1, ownedOrphan = 2 }
    struct Member: Equatable {
        let operationsRelativePath: String
        let observedFact: String
        let fullFact: String
    }
    let index: UInt64
    let kind: Kind
    let producerRole: EraseSchema2ColdProducerRoleV4?
    let firstMember: Member
    let secondMember: Member
    let sha256: String
    let byteCount: UInt64
    let device: UInt64
    let inode: UInt64
    let metadataState: MetadataState
    let metadataOriginalSourceOrdinal: UInt64?
    let firstPredecessorOrdinal: UInt64
    let predecessorCount: UInt64
    let predecessorCommitmentSHA256: String
}

// Complete original Operations source table includes ALL original nodes,
// including fact-only directories/opaque regular files. ProducerRole nil is
// permitted only for that data-only kind; it never grants a control role.
struct EraseSchema2ColdOriginalScratchChildV4: Equatable {
    enum Kind: UInt8 { case directory = 1, opaqueRegular = 2, canonicalControl = 3 }
    let sourceOrdinal: UInt64
    let operationsRelativePath: String
    let kind: Kind
    let observedFact: String
    let sourceFullFact: String
    let contentSHA256: String?
    let byteCount: UInt64
    let producerRole: EraseSchema2ColdProducerRoleV4?
}

struct EraseSchema2ColdOriginalScratchDirectoryV4: Equatable {
    enum MetadataState: UInt8 { case validatedLease = 1, ownedOrphan = 2 }
    let sourceOrdinal: UInt64
    let operationsRelativePath: String
    let observedFact: String
    let sourceFullFact: String
    let metadataState: MetadataState
    let metadataSourceOrdinal: UInt64?
    let originalChildCount: UInt64
    let originalChildrenValueSHA256: String
    let sourceCutBindingSHA256: String
    let recordBindingSHA256: String
}

// This is a live original Store observation, not serialized/cold authority.
// Store's future private issuer retains its OWN actual publication transitions.
// At most four closed leaves; original intent/prep each retain old96MiB cap.
@MainActor
final class EraseOriginalFirstCaptureControlReadbackV4 {
    struct Leaf {
        enum Name: UInt8 { case intent = 1, preparation = 2, auxiliaryRoster = 3, auxiliaryRosterTemporary = 4 }
        let name: Name
        let byteCount: UInt64
        let sha256: String
        let actualFullFact: EraseSchema2ColdNumericFullFactV4
    }
    struct OwnedTransition {
        enum Effect: UInt8 { case createTemporary = 1, publishCanonical = 2 }
        let effect: Effect
        let beforeRoot: EraseSchema2ColdNumericFullFactV4
        let afterRoot: EraseSchema2ColdNumericFullFactV4
        let ownedLeafBefore: Leaf?
        let ownedLeafAfter: Leaf
        let actualPublicationAttemptID: UUID
        // Contains only already-observed actual facts, no future syscall delta.
    }
    struct CheckedTemporary {
        let actualPublicationAttemptID: UUID
        let expectedCanonicalSHA256: String
        let expectedCanonicalByteCount: UInt64
        let initialDevice: UInt64
        let initialInode: UInt64
        let currentHeldFullFact: EraseSchema2ColdNumericFullFactV4
        let currentNamedFullFact: EraseSchema2ColdNumericFullFactV4
        let checkedWrittenPrefixByteCount: UInt64
        let checkedPrefixSHA256: String
        let actualPolicyObservation: TemporalPolicyObservationV1
        // Positively checked EOF and exact expected canonical prefix; returned
        // only while no syscall/write/policy/close is in-flight or uncertain.
    }
    enum RootLinkLaw: UInt8 { case subdirectoriesOnly = 1, allEntries = 2 }
    enum PublicationCut: UInt8 {
        case firstControlsOnly = 1, ownedTemporaryZero = 2
        case ownedTemporaryPrefix = 3, ownedTemporaryFull = 4, canonicalSettled = 5
    }
    let stableControlBindingSHA256: String
    let operationID: UUID
    let eraseID: UUID
    let originalBeforeEraseRoot: EraseSchema2ColdNumericFullFactV4
    let currentHeldEraseRoot: EraseSchema2ColdNumericFullFactV4
    let currentNamedEraseRoot: EraseSchema2ColdNumericFullFactV4
    let originalIntentBytes: Data
    let originalPreparationBytes: Data
    let originalIntentLeaf: Leaf
    let originalPreparationLeaf: Leaf
    let currentLeaves: [Leaf]
    let publicationCut: PublicationCut
    let rootLinkLaw: RootLinkLaw
    let checkedTemporary: CheckedTemporary?
    let ownedTransitions: [OwnedTransition]
    private let reproveActualOriginalStore: @MainActor () throws -> Void
    private var uncertain = false

    fileprivate init(stableControlBindingSHA256: String,
        operationID: UUID, eraseID: UUID,
        originalBeforeEraseRoot: EraseSchema2ColdNumericFullFactV4,
        currentHeldEraseRoot: EraseSchema2ColdNumericFullFactV4,
        currentNamedEraseRoot: EraseSchema2ColdNumericFullFactV4,
        originalIntentBytes: Data, originalPreparationBytes: Data,
        originalIntentLeaf: Leaf, originalPreparationLeaf: Leaf,
        currentLeaves: [Leaf], publicationCut: PublicationCut,
        rootLinkLaw: RootLinkLaw, checkedTemporary: CheckedTemporary?,
        ownedTransitions: [OwnedTransition],
        reproveActualOriginalStore: @escaping @MainActor () throws -> Void) throws {
        try reproveActualOriginalStore()
        self.stableControlBindingSHA256 = stableControlBindingSHA256
        self.operationID = operationID; self.eraseID = eraseID
        self.originalBeforeEraseRoot = originalBeforeEraseRoot
        self.currentHeldEraseRoot = currentHeldEraseRoot
        self.currentNamedEraseRoot = currentNamedEraseRoot
        self.originalIntentBytes = originalIntentBytes
        self.originalPreparationBytes = originalPreparationBytes
        self.originalIntentLeaf = originalIntentLeaf
        self.originalPreparationLeaf = originalPreparationLeaf
        self.currentLeaves = currentLeaves; self.publicationCut = publicationCut
        self.rootLinkLaw = rootLinkLaw; self.checkedTemporary = checkedTemporary
        self.ownedTransitions = ownedTransitions
        self.reproveActualOriginalStore = reproveActualOriginalStore
        try reproveActualOriginalStore()
    }
    func requireCurrentOriginalStoreBinding() throws {
        do {
            guard !uncertain else { throw EraseIntentStoreError.invalidAuthority }
            try reproveActualOriginalStore()
        } catch { uncertain = true; throw error }
    }
}

// All helpers are data-only. Implementations must use the deterministic binary
// fragmented stream in the contract, never full mixed JSON encoding. Compatibility
// array helpers iterate existing arrays; durable callers use visitors.
@MainActor
protocol EraseSchema2ColdLogicalCommitmentContractV4 {
    static func targetCommitmentSHA256(
        rowCount: UInt64,
        visit: (@MainActor (EraseSchema2ColdCleanupProgressV1.Target) throws -> Void) throws -> Void
    ) throws -> String
    static func projectionCommitmentSHA256(
        rowCount: UInt64,
        visit: (@MainActor (EraseSchema2ColdCleanupProgressV1.Projection) throws -> Void) throws -> Void
    ) throws -> String
    // Header and table commitment input fields are enumerated in the wire schema;
    // the helper excludes physical catalog/page birth facts from logical Progress.
    static func logicalProgressCommitmentSHA256(
        header: EraseSchema2ColdProgressHeaderV4
    ) throws -> String
}

@MainActor
protocol EraseSchema2ColdStoreReadbackContractV4 {
    // Genuine original FirstCapture hook a738; no permit/load/source recursion.
    func requireOriginalEraseFirstCaptureControls(
        operation: EraseRouterOperationV1, intent: EraseIntentV1,
        preparation: ErasePreparationV2
    ) throws -> String

    func observeOriginalEraseFirstCaptureControls(
        operation: EraseRouterOperationV1, intent: EraseIntentV1,
        preparation: ErasePreparationV2
    ) throws -> EraseOriginalFirstCaptureControlReadbackV4

    func requireSchema2ColdC16CurrentRecordBinding(
        planSHA256: String, ordinal: Int,
        permit: EraseSchema2ColdControlPermitV1
    ) throws -> EraseSchema2ColdCurrentC16RecordV4

    func canonicalSchema2ColdCapturedBornSource(
        slot: OriginalEraseC16BornProducerSlotV1,
        record: EraseSchema2ColdCurrentC16RecordV4,
        permit: EraseSchema2ColdControlPermitV1
    ) throws -> (bytes: Data, fullFact: String)?

    func canonicalSchema2ColdTransferredSource(
        path: String, permit: EraseSchema2ColdControlPermitV1
    ) throws -> (bytes: Data, fullFact: String)

    func requireSchema2ColdOriginalPairAccountingHeader(
        permit: EraseSchema2ColdControlPermitV1
    ) throws -> EraseSchema2ColdPairAccountingSourceHeaderV4

    func loadSchema2ColdOriginalPairAccountingRow(
        at index: UInt64, header: EraseSchema2ColdPairAccountingSourceHeaderV4,
        permit: EraseSchema2ColdControlPermitV1
    ) throws -> EraseSchema2ColdPairAccountingRowCoreV4

    func visitSchema2ColdOriginalPairAccountingPredecessors(
        row: EraseSchema2ColdPairAccountingRowCoreV4,
        header: EraseSchema2ColdPairAccountingSourceHeaderV4,
        permit: EraseSchema2ColdControlPermitV1,
        body: @MainActor (String) throws -> Void
    ) throws

    func canonicalSchema2ColdOriginalPairMetadata(
        row: EraseSchema2ColdPairAccountingRowCoreV4,
        header: EraseSchema2ColdPairAccountingSourceHeaderV4,
        permit: EraseSchema2ColdControlPermitV1
    ) throws -> (bytes: Data, observedFact: String, fullFact: String)?

    func loadSchema2ColdOriginalScratchDirectory(
        path: String, sources: EraseSchema2ColdSourcesHeaderV4,
        record: EraseSchema2ColdProgressReadbackV4,
        permit: EraseSchema2ColdControlPermitV1
    ) throws -> EraseSchema2ColdOriginalScratchDirectoryV4

    func visitSchema2ColdOriginalScratchDirectoryChildren(
        directory: EraseSchema2ColdOriginalScratchDirectoryV4,
        sources: EraseSchema2ColdSourcesHeaderV4,
        record: EraseSchema2ColdProgressReadbackV4,
        permit: EraseSchema2ColdControlPermitV1,
        body: @MainActor (EraseSchema2ColdOriginalScratchChildV4) throws -> Void
    ) throws

    func canonicalSchema2ColdOriginalScratchDirectoryMetadata(
        directory: EraseSchema2ColdOriginalScratchDirectoryV4,
        sources: EraseSchema2ColdSourcesHeaderV4,
        record: EraseSchema2ColdProgressReadbackV4,
        permit: EraseSchema2ColdControlPermitV1
    ) throws -> (bytes: Data, observedFact: String, fullFact: String)?
}

struct EraseSchema2ColdProgressHeaderV4: Equatable {
    let eraseID: UUID
    let preparationSHA256: String
    let originalRosterSHA256: String
    let targetPointerSHA256: String
    let planSHA256: String
    let sourcesLogicalSHA256: String
    let pairsLogicalSHA256: String
    let targetsLogicalSHA256: String
    let dependenciesLogicalSHA256: String
    let slotsLogicalSHA256: String
    let stage: OriginalScratchLifecycleRecordV1.Stage
    let completedMixedPrefixCount: UInt64
    let activeMixedTargetIndex: UInt64?
    let prefixSHA256: String
    let lastCheckedProjection: EraseSchema2ColdTableCommitmentV4
    let capturedBirths: EraseSchema2ColdTableCommitmentV4
    let lastCheckedProjectionValueSHA256: String
    let pendingProducer: EraseSchema2ColdPendingProducerDataV4?
    let transitionMixedTargetIndex: UInt64?
    let transitionPreimageSHA256: String?
    let transitionPostimageSHA256: String?
    let checkedClose: Bool
}


// Genuine source-only bootstrap cut: complete original source/pair/raw roots
// and actual exact Plan readback, before complete Slots/Targets/SourceManifest.
// Its actual checkpoint identity changes with each owned page publication.
struct EraseSchema2ColdBootstrapSourceReadbackV4: Equatable {
    let originalOperationID: UUID
    let eraseID: UUID
    let originalRosterSHA256: String
    let originalSources: EraseSchema2ColdTableCommitmentV4
    let originalPairs: EraseSchema2ColdTableCommitmentV4
    let pairPredecessors: EraseSchema2ColdTableCommitmentV4
    let actualOriginalSourcesRoot: EraseSchema2ColdPageDescriptorV4?
    let actualOriginalPairsRoot: EraseSchema2ColdPageDescriptorV4?
    let actualPairPredecessorsRoot: EraseSchema2ColdPageDescriptorV4?
    let actualRawCatalogRoot: EraseSchema2ColdPageDescriptorV4?
    let planSHA256: String
    let actualPlanCopy: EraseSchema2ColdPageDescriptorV4
    let actualPublicationCheckpointSHA256: String
    let actualPublicationCheckpointFullFact: EraseSchema2ColdNumericFullFactV4
    let sourceCutBindingSHA256: String
}

struct EraseSchema2ColdSourcesHeaderV4: Equatable {
    let eraseID: UUID
    let originalOperationID: UUID
    let captureTokenSHA256: String
    let preparationSHA256: String
    let originalRosterSHA256: String
    let targetPointerSHA256: String
    let c16PlanSHA256: String
    let sourcesLogicalSHA256: String
    let pairAccountingLogicalSHA256: String
    let targetsValueSHA256: String
    let targetStorageCommitmentSHA256: String
    let dependenciesCommitmentSHA256: String
    let slotsCommitmentSHA256: String
    let originalSourceCount: UInt64
    let pairCount: UInt64
    let c16TargetCount: UInt64
    let mixedTargetCount: UInt64
    let producerSlotCount: UInt64
    let actualSourcesManifestSHA256: String
    let actualSourcesManifestFullFact: EraseSchema2ColdNumericFullFactV4
    let sourceCutBindingSHA256: String
}

struct EraseSchema2ColdProgressReadbackV4: Equatable {
    let header: EraseSchema2ColdProgressHeaderV4
    let actualManifestSHA256: String
    let actualManifestFullFact: EraseSchema2ColdNumericFullFactV4
    let recordBindingSHA256: String
    let logicalProgressSHA256: String
}

struct EraseSchema2ColdMixedTargetCoreV4: Equatable {
    let mixedTargetIndex: UInt64
    let kind: EraseSchema2ColdCleanupProgressV1.Target.Kind
    let ordinal: UInt64
    let path: String
    let semanticSHA256: String
    let firstDependencyOrdinal: UInt64
    let dependencyCount: UInt64
    let dependencyValueSHA256: String
    let firstAllowedSlotOrdinal: UInt64
    let allowedSlotCount: UInt64
    let allowedBirthPathsValueSHA256: String
}

// DATA only. The private actual Ledger PublicationSession request and Router
// scope determine this value. It never contains a future physical sourcefact.
struct EraseSchema2ColdPendingProducerDataV4: Equatable {
    enum PublicationMode: UInt8 { case linkExclusiveFinal = 1, renameExclusiveFinal = 2 }
    let slotOrdinal: UInt64
    let producerOrdinal: UInt64
    let role: EraseSchema2ColdProducerRoleV4
    let temporaryOperationsPath: String
    let publicationMode: PublicationMode
    let payloadSHA256: String
    let payloadByteCount: UInt64
    let rawBlobSHA256: String
    let requestCommitmentSHA256: String
    let producerInputRecordBindingSHA256: String
}

// Exact StoreAPI1e97e77c counterpart DATA return. Router's private one-use
// BoundaryReceipt is the authority-bearing acknowledgment, not this struct.
struct EraseSchema2ColdProducerRequestReadbackV4 {
    let slot: OriginalEraseC16BornProducerSlotV1
    let temporaryPath: String
    let publicationMode: OriginalEraseC16ProducerRequestV4.PublicationMode
    let payloadSHA256: String
    let requestCommitmentSHA256: String
    let record: EraseSchema2ColdCurrentC16RecordV4
}

// Direct physical DATA adapter. No capturedBirths array or full Progress JSON.
// Physical retains its complete immutable target builder/census separately;
// actual permit checks BOTH record cut and logical value on every IO edge.
struct EraseSchema2ColdPhysicalProgressViewV4: Equatable {
    let record: EraseSchema2ColdProgressReadbackV4
    let targetsValueSHA256: String
    let mixedTargetCount: UInt64
    let referenceProgress: OriginalEraseC16ReferenceProgressV1
    let projectionRowCount: UInt64
}

@MainActor
protocol EraseSchema2ColdStoreControllerContractV4: EraseSchema2ColdStoreReadbackContractV4 {
    func requireSchema2ColdBootstrapSourceCut(permit: EraseSchema2ColdControlPermitV1)
        throws -> EraseSchema2ColdBootstrapSourceReadbackV4
    func loadSchema2ColdBootstrapC16Plan(source: EraseSchema2ColdBootstrapSourceReadbackV4,
        permit: EraseSchema2ColdControlPermitV1) throws -> OriginalEraseC16PlanV1
    func requireSchema2ColdSources(permit: EraseSchema2ColdControlPermitV1)
        throws -> EraseSchema2ColdSourcesHeaderV4
    func loadSchema2ColdC16Plan(sources: EraseSchema2ColdSourcesHeaderV4,
        permit: EraseSchema2ColdControlPermitV1) throws -> OriginalEraseC16PlanV1
    func loadSchema2ColdProgress(sources: EraseSchema2ColdSourcesHeaderV4,
        permit: EraseSchema2ColdControlPermitV1) throws -> EraseSchema2ColdProgressReadbackV4
    func requireSchema2ColdPhysicalProgressView(
        sources: EraseSchema2ColdSourcesHeaderV4,
        record: EraseSchema2ColdProgressReadbackV4,
        permit: EraseSchema2ColdControlPermitV1) throws -> EraseSchema2ColdPhysicalProgressViewV4
    func visitSchema2ColdLastCheckedProjection(
        sources: EraseSchema2ColdSourcesHeaderV4,
        record: EraseSchema2ColdProgressReadbackV4,
        permit: EraseSchema2ColdControlPermitV1,
        body: @MainActor (EraseSchema2ColdCleanupProgressV1.Projection) throws -> Void) throws
    func loadSchema2ColdMixedTarget(at index: UInt64,
        sources: EraseSchema2ColdSourcesHeaderV4,
        record: EraseSchema2ColdProgressReadbackV4,
        permit: EraseSchema2ColdControlPermitV1) throws -> EraseSchema2ColdMixedTargetCoreV4
    func visitSchema2ColdTargetDependencies(target: EraseSchema2ColdMixedTargetCoreV4,
        sources: EraseSchema2ColdSourcesHeaderV4,
        record: EraseSchema2ColdProgressReadbackV4,
        permit: EraseSchema2ColdControlPermitV1,
        body: @MainActor (String) throws -> Void) throws
    func visitSchema2ColdTargetAllowedBirthPaths(target: EraseSchema2ColdMixedTargetCoreV4,
        sources: EraseSchema2ColdSourcesHeaderV4,
        record: EraseSchema2ColdProgressReadbackV4,
        permit: EraseSchema2ColdControlPermitV1,
        body: @MainActor (String) throws -> Void) throws
    func createSchema2ColdProgress(header: EraseSchema2ColdProgressHeaderV4,
        projectionRowCount: UInt64,
        visitProjection: (@MainActor (EraseSchema2ColdCleanupProgressV1.Projection) throws -> Void) throws -> Void,
        sources: EraseSchema2ColdSourcesHeaderV4,
        permit: EraseSchema2ColdControlPermitV1) throws -> EraseSchema2ColdProgressReadbackV4
    func replaceSchema2ColdProgress(expected: EraseSchema2ColdProgressReadbackV4,
        replacement: EraseSchema2ColdProgressHeaderV4,
        projectionRowCount: UInt64,
        visitProjection: (@MainActor (EraseSchema2ColdCleanupProgressV1.Projection) throws -> Void) throws -> Void,
        sources: EraseSchema2ColdSourcesHeaderV4,
        permit: EraseSchema2ColdControlPermitV1) throws -> EraseSchema2ColdProgressReadbackV4
    func prepareSchema2ColdProducerRequest(_ request: OriginalEraseC16ProducerRequestV4,
        expectedRecordBindingSHA256: String,
        permit: EraseSchema2ColdControlPermitV1) throws -> EraseSchema2ColdProducerRequestReadbackV4
    func canonicalSchema2ColdProducerRequest(slot: OriginalEraseC16BornProducerSlotV1,
        record: EraseSchema2ColdCurrentC16RecordV4,
        permit: EraseSchema2ColdControlPermitV1)
        throws -> (temporaryPath: String, bytes: Data, sha256: String)?
    func captureSchema2ColdBornCleanupSource(observation: OriginalEraseC16BoundaryObservationV1,
        expected: EraseSchema2ColdProgressReadbackV4,
        sources: EraseSchema2ColdSourcesHeaderV4,
        projectionRowCount: UInt64,
        visitProjection: (@MainActor (EraseSchema2ColdCleanupProgressV1.Projection) throws -> Void) throws -> Void,
        permit: EraseSchema2ColdControlPermitV1) throws -> EraseSchema2ColdProgressReadbackV4
    func replaceSchema2ColdCleanupPhase(expected: EraseIntentV1,
        replacement: EraseIntentV1, record: EraseSchema2ColdProgressReadbackV4,
        permit: EraseSchema2ColdControlPermitV1) throws -> EraseIntentV1
}
