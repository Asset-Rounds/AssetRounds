import Foundation

enum C50IncumbentFileExchangeDeletionLedgerBoundaryV1 {
    static let excludesSceneRouteState = C34SceneNavigationCompatibilityBoundaryV1.validate()
    static let createsDeletionLedgerKind = false
    static let ordinaryDeletionPreservesCanonicalImportedHistory = true
    static let scratchAndQuarantineCreateNoTombstone = true
    static let eraseOwnsAppControlledScratchAndQuarantine = true
    static let escapedFilesCannotBeRecalled = true

    static func validate() -> Bool {
        excludesSceneRouteState
            && !createsDeletionLedgerKind
            && ordinaryDeletionPreservesCanonicalImportedHistory
            && scratchAndQuarantineCreateNoTombstone
            && eraseOwnsAppControlledScratchAndQuarantine
            && escapedFilesCannotBeRecalled
    }
}

/// The system index is derived-only. Its REMOVAL_JOURNALED operation belongs
/// to the protected index actor and never introduces a canonical tombstone
/// kind into the backup/deletion ledger.
enum PrivateSystemDiscoveryDeletionLedgerPolicyV1 {
    static let deletionDisposition = "REMOVAL_JOURNALED"
    static let createsCanonicalLedgerKind = false
    static let includedInBackup = false
    static let workspaceRemovalPreservesOtherWorkspaceState = true

    static func validate() throws {
        guard deletionDisposition == "REMOVAL_JOURNALED",
              !createsCanonicalLedgerKind,
              !includedInBackup,
              workspaceRemovalPreservesOtherWorkspaceState,
              PrivateSystemDiscoveryLifecycleV1.removalIsJournaled,
              !PrivateSystemDiscoveryLifecycleV1.canonicalPersistence else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
    }
}

enum DeletionLedgerFailureV2: Error, Equatable, Sendable {
    case invalidSchemaVersion
    case invalidIdentity
    case duplicateIdentity
    case unorderedEntries
    case invalidTimestamp
}

enum C49WorkResourceDeletionLedgerPolicyV1 {
    static let addsRowTombstoneKind = false
    static let ordinarySubjectDeletionPreservesAcceptedHistory = true
    static let eraseUsesWorkspaceEraseAuthority = true
}

/// C52 canonical request history is not an ordinary subject-deletion tombstone
/// target. Erase removes the workspace-owned rows and asks the C48 protected
/// session store to invalidate outstanding capabilities in the same operation.
enum C52ServiceRequestDeletionLedgerPolicyV1 {
    static let durableKinds = C52ServiceRequestBackupEnrollmentV1.canonicalRowKinds
    static let protectedOperationKind = "PortableExchangeSessionNamespaceV2.SERVICE_REQUEST"
    static let eraseInventory = durableKinds + [protectedOperationKind]
    static let ordinaryDeletionPreservesCanonicalHistory = true
    static let ordinaryDeletionPreservesImmutableSourceBytes = true
    static let workspaceEraseRemovesCanonicalRows = true
    static let workspaceEraseRemovesOwnedProtectedState = true
    static let eraseInvalidatesOutstandingCapabilitiesViaC48Store = true
    static let rawCapabilityBytesCreateLedgerEntries = false
    static let derivedProjectionCreatesLedgerEntries = false
    static let createsParallelServiceRequestTombstoneKind = false

    static func validate() throws {
        guard durableKinds.count == 3,
              Set(durableKinds).count == durableKinds.count,
              eraseInventory == durableKinds + [protectedOperationKind],
              ordinaryDeletionPreservesCanonicalHistory,
              ordinaryDeletionPreservesImmutableSourceBytes,
              workspaceEraseRemovesCanonicalRows,
              workspaceEraseRemovesOwnedProtectedState,
              eraseInvalidatesOutstandingCapabilitiesViaC48Store,
              !rawCapabilityBytesCreateLedgerEntries,
              !derivedProjectionCreatesLedgerEntries,
              !createsParallelServiceRequestTombstoneKind,
              ServiceRequestLifecycleRegistrationBoundaryV1.eraseRemovesOwnedProtectedState,
              ServiceRequestLifecycleRegistrationBoundaryV1.cloneOrForkInvalidatesOutstandingCapabilities else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
    }

    static func validate(
        records: V4BackupRecordsV1,
        workspaceID: UUID? = nil
    ) throws {
        try validate()
        do {
            try C52ServiceRequestBackupEnrollmentV1.validate(
                records: records,
                workspaceID: workspaceID
            )
        } catch {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
    }
}

/// C05's two V43 families are the immutable association/sequence history.
/// Removing evidence from a report is represented by an append-only successor
/// association, never by a deletion-ledger tombstone or physical history
/// removal. Workspace Erase is the sole physical row-and-owned-content clear.
enum EvidenceMetadataDeletionLedgerPolicyV1 {
    static let durableFamilies = [
        EvidenceMetadataPersistenceEnrollmentV1.associationEventFamily,
        EvidenceMetadataPersistenceEnrollmentV1.sequenceRevisionFamily,
    ]
    static let ordinaryRemovalCreatesAppendOnlySuccessor = true
    static let ordinaryRemovalPhysicallyDeletesMetadata = false
    static let deletionEvidenceIsAssociationPredecessorBound = true
    static let workspaceEraseClearsRowsAndOwnedDerivatives = true
    static let createsDeletionLedgerTombstoneKind = false

    static func validate() throws {
        guard durableFamilies.count == 2,
              Set(durableFamilies).count == durableFamilies.count,
              EvidenceMetadataPersistenceEnrollmentV1.schemaVersion == 43,
              EvidenceMetadataPersistenceEnrollmentV1.recordsSchemaVersion == 42,
              EvidenceMetadataPersistenceEnrollmentV1.durableModelCount
                == durableFamilies.count,
              EvidenceMetadataPersistenceEnrollmentV1.totalSchemaModelCount == 144,
              ordinaryRemovalCreatesAppendOnlySuccessor,
              !ordinaryRemovalPhysicallyDeletesMetadata,
              deletionEvidenceIsAssociationPredecessorBound,
              workspaceEraseClearsRowsAndOwnedDerivatives,
              !createsDeletionLedgerTombstoneKind else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
    }
}

struct DeletionLedgerProofV2: Codable, Equatable, Sendable {
    let entryCount: Int
    let canonicalSHA256: String

    init(entryCount: Int, canonicalSHA256: String) throws {
        self.entryCount = entryCount
        self.canonicalSHA256 = canonicalSHA256
        try validate()
    }

    func validate() throws {
        try EvidenceMetadataDeletionLedgerPolicyV1.validate()
        try ClientCapabilityDeletionLedgerPolicyV1.validate()
        try RecoverabilityVerificationDeletionLedgerPolicyV1.validate()
        try FieldReferenceDeletionLedgerPolicyV1.validate()
        try AccessibleDocumentDeletionLedgerPolicyV1.validate()
        try PlanDeletionLedgerPolicyV1.validate()
        try PlacementPoseDeletionLedgerPolicyV1.validate()
        try AssetLabelDeletionLedgerPolicyV1.validate()
        let allowed = CharacterSet(charactersIn: "0123456789abcdef")
        guard entryCount >= 0,
              canonicalSHA256.utf8.count == 64,
              canonicalSHA256.unicodeScalars.allSatisfy(allowed.contains) else {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
    }
}
enum ClientCapabilityDeletionLedgerPolicyV1{static func validate()throws{guard V20BackupClientCapabilityRecordV1.Kind.allCases.count==4 else{throw DeletionLedgerFailureV2.invalidSchemaVersion}}}
enum RecoverabilityVerificationDeletionLedgerPolicyV1{static func validate()throws{guard RecoverabilityVerificationReceiptV1.schemaVersion==1 else{throw DeletionLedgerFailureV2.invalidSchemaVersion}}}
enum FieldReferenceDeletionLedgerPolicyV1{static let immutableKinds=["FieldReferenceReleaseV1","FieldReferenceBindingV1"];static let ordinaryDeletionRetainsBoundAndFinalizedBytes=true;static let workspaceEraseRemovesRowsAndOwnedBytes=true;static func validate()throws{guard V22BackupFieldReferenceRecordV1.Kind.allCases.count==2,FieldReferencePackLifecycleV1.stagingPersistence=="DERIVED_ONLY",immutableKinds==FieldReferencePackLifecycleV1.persistentFamilies,ordinaryDeletionRetainsBoundAndFinalizedBytes,workspaceEraseRemovesRowsAndOwnedBytes else{throw DeletionLedgerFailureV2.invalidSchemaVersion}}}
enum SurveyDefinitionDeletionLedgerPolicyV1{static let durableKinds=SurveyDefinitionLifecycleV1.persistentFamilies;static let ordinaryAssetOrSiteDeleteRetainsAll=true;static let workspaceEraseRemovesAll=true;static let quarantineCandidatesAreNotDurable=true;static func validate()throws{guard durableKinds==["SurveyDefinitionIdentityV1","SurveyDefinitionReleaseV1"],ordinaryAssetOrSiteDeleteRetainsAll,workspaceEraseRemovesAll,quarantineCandidatesAreNotDurable,V24BackupSurveyDefinitionRecordV1.Kind.allCases.count==2 else{throw DeletionLedgerFailureV2.invalidSchemaVersion}}}

enum SurveySessionDeletionLedgerPolicyV1{static let durableKinds=["SurveySessionV1","FactCaptureV1","ProvisionalSubjectV1","SubjectPromotionReceiptV1","SurveyPublicationSnapshotV1"];static let ordinaryAssetOrSiteDeleteRetainsFrozenPublications=true;static let workspaceEraseRemovesAll=true;static func validate()throws{guard durableKinds.count==5,Set(durableKinds).count==5,ordinaryAssetOrSiteDeleteRetainsFrozenPublications,workspaceEraseRemovesAll else{throw DeletionLedgerFailureV2.invalidSchemaVersion}}}
/// Schedule releases are immutable content and occurrence events are
/// append-only history. Ordinary asset/site deletion cannot prune either
/// family; workspace Erase is the only operation that removes them.
enum ScheduleDeletionLedgerPolicyV1 {
    static let durableKinds = [
        "ScheduleDefinitionReleaseV1", "OccurrenceHistoryEventV1",
        "ExceptionCalendarReleaseV1", "ScheduleOverrideEventV1"
    ]
    static let embeddedC51Kinds = C51ScheduleBackupClosureV1.embeddedCanonicalComponents
    static let lifecycleEventsRemainInMutationHistory = true
    static let ordinaryDeletionPreservesReleaseAndOccurrenceHistory = true
    static let ordinaryDeletionPreservesCalendarOverrideBasisAndReceiptClosure = true
    static let workspaceEraseRemovesAll = true

    static func validate() throws {
        guard durableKinds.count == 4,
              Set(durableKinds).count == durableKinds.count,
              embeddedC51Kinds.count == 6,
              lifecycleEventsRemainInMutationHistory,
              ordinaryDeletionPreservesReleaseAndOccurrenceHistory,
              ordinaryDeletionPreservesCalendarOverrideBasisAndReceiptClosure,
              workspaceEraseRemovesAll else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
    }
}
enum AccessibleDocumentDeletionLedgerPolicyV1{static let ordinaryDeletionPreservesAcceptedReceiptAndOutput=true;static let removalRequiresPrivacyExpiryTombstoneAndRedactionProof=true;static let workspaceEraseRemovesReceiptAndOwnedOutput=true;static func validate()throws{guard AccessibleDocumentLifecycleV1.persistentFamilies==["AccessibleDocumentAssessmentReceiptV1"],AccessibleDocumentLifecycleV1.semanticTreePersistence=="DERIVED_ONLY",ordinaryDeletionPreservesAcceptedReceiptAndOutput,removalRequiresPrivacyExpiryTombstoneAndRedactionProof,workspaceEraseRemovesReceiptAndOwnedOutput else{throw DeletionLedgerFailureV2.invalidSchemaVersion}}}

/// Plans have no independent filesystem payload. Ordinary deletion keeps
/// immutable document/revision/frame/placement history and rebase receipts;
/// workspace Erase is the only operation that removes those canonical rows.
enum PlanDeletionLedgerPolicyV1 {
    static let durableKinds = [
        "PlanDocumentV1", "PlanRevisionV1", "SpatialReferenceFrameV1",
        "PlanPlacementV1", "RebaseReceiptV1"
    ]
    static let ordinaryDeletionPreservesImmutableHistory = true
    static let workspaceEraseRemovesAllCanonicalRows = true
    static let previewsAndRegistriesAreDerived = true
    static let missingFilesystemBytesCannotDeletePlanHistory = true

    static func validate() throws {
        guard durableKinds.count == 5,
              Set(durableKinds).count == durableKinds.count,
              PlanPersistenceEnrollmentV1.durableModelCount == 4,
              V28BackupPlanRecordV1.Kind.allCases.count == durableKinds.count,
              ordinaryDeletionPreservesImmutableHistory,
              workspaceEraseRemovesAllCanonicalRows,
              previewsAndRegistriesAreDerived,
              missingFilesystemBytesCannotDeletePlanHistory else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
    }
}

/// Pose event and spatial-anchor rows are immutable history. Ordinary
/// asset/site deletion preserves both chains; only a workspace Erase removes
/// them. Current tips and placement snapshots are derived and therefore never
/// receive deletion-ledger identities.
enum PlacementPoseDeletionLedgerPolicyV1 {
    static let durableKinds = ["AssetPoseEventV1", "SpatialAnchorObservationV1"]
    static let ordinaryDeletionPreservesImmutableHistory = true
    static let workspaceEraseRemovesAllCanonicalRows = true
    static let derivedTipsAndSnapshotsAreLedgerFree = true
    static let sensorProposalPersistence = "NONPERSISTENT"

    static func validate() throws {
        guard durableKinds.count == 2,
              Set(durableKinds).count == durableKinds.count,
              PlacementPosePersistenceEnrollmentV1.durableModelCount == 2,
              V29BackupPlacementPoseRecordV1.Kind.allCases.count == durableKinds.count,
              ordinaryDeletionPreservesImmutableHistory,
              workspaceEraseRemovesAllCanonicalRows,
              derivedTipsAndSnapshotsAreLedgerFree,
              sensorProposalPersistence == "NONPERSISTENT" else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
    }
}

/// The closed set of persisted content kinds. System rows such as the schema
/// marker and deletion-ledger rows are deliberately outside this registry.
enum DeletionRecordKindV2: String, CaseIterable, Codable, Equatable, Sendable {
    case site = "site"
    case asset = "asset"
    case workflowRecord = "workflowRecord"
    case evidenceFile = "evidenceFile"
    case issue = "issue"
    case packet = "packet"
    case report = "report"
    case acceptedLabelGenerationSnapshot = "acceptedLabelGenerationSnapshot"
}

enum AssetLabelDeletionLedgerPolicyV1 {
    static let durableFamily = "AcceptedLabelGenerationSnapshotRow"
    static let matchingBatchSnapshotIsDeletedWhole = true
    static let unrelatedAssetAndLocatorRowsRemain = true
    static let publishedOutputCleanupIsReceiptBound = true
    static let committedLedgerAuthorizesIdempotentCleanupRetry = true

    static func validate() throws {
        guard AssetLabelPersistenceEnrollmentV1.persistentFamilies == [durableFamily],
              matchingBatchSnapshotIsDeletedWhole,
              unrelatedAssetAndLocatorRowsRemain,
              publishedOutputCleanupIsReceiptBound,
              committedLedgerAuthorizesIdempotentCleanupRetry else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
    }
}

enum PartyAccountabilityDeletionDispositionV1: String, Codable, Equatable, Sendable {
    case preserveImmutableHistoryUntilWorkspaceErase = "PRESERVE_IMMUTABLE_HISTORY_UNTIL_WORKSPACE_ERASE"
}

enum PartyAccountabilityDeletionLedgerPolicyV1 {
    static func disposition(
        for kind: V9BackupPartyAccountabilityRecordV1.Kind
    ) -> PartyAccountabilityDeletionDispositionV1 {
        switch kind {
        case .serviceParty, .sitePartyRoleEvent, .actorSnapshot,
             .qualificationSnapshot, .signoffSnapshot:
            return .preserveImmutableHistoryUntilWorkspaceErase
        }
    }

    static func validate() throws {
        let kinds = V9BackupPartyAccountabilityRecordV1.Kind.allCases
        guard kinds.count == 5,
              Set(kinds.map(\.rawValue)).count == kinds.count,
              kinds.allSatisfy({
                  disposition(for: $0) == .preserveImmutableHistoryUntilWorkspaceErase
              }) else {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
    }
}

enum AssetSemanticDeletionDispositionV1: String, Codable, Equatable, Sendable {
    case preserveImmutableHistoryUntilWorkspaceErase = "PRESERVE_IMMUTABLE_HISTORY_UNTIL_WORKSPACE_ERASE"
}

enum AssetSemanticDeletionLedgerPolicyV1 {
    static func disposition(
        for kind: V10BackupAssetSemanticRecordV1.Kind
    ) -> AssetSemanticDeletionDispositionV1 {
        switch kind {
        case .kindBindingEvent, .workflowCapabilityBindingEvent, .productIdentity,
             .lifecycleEvent, .successorLink, .workSubjectScopeSnapshot:
            return .preserveImmutableHistoryUntilWorkspaceErase
        }
    }

    static func validate() throws {
        let kinds = V10BackupAssetSemanticRecordV1.Kind.allCases
        guard kinds.count == 6, Set(kinds.map(\.rawValue)).count == kinds.count,
              kinds.allSatisfy({
                  disposition(for: $0) == .preserveImmutableHistoryUntilWorkspaceErase
              }) else { throw DeletionLedgerFailureV2.invalidIdentity }
    }
}

enum AuthorityCriterionDeletionLedgerPolicyV1 {
    static func validate() throws {
        let kinds = V11BackupAuthorityCriterionRecordV1.Kind.allCases
        guard kinds.count == 9, Set(kinds.map(\.rawValue)).count == kinds.count else {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
    }
}

enum FunctionalRelationshipDeletionDispositionV1: String, Codable, Equatable, Sendable {
    case preserveImmutableHistoryUntilWorkspaceErase = "PRESERVE_IMMUTABLE_HISTORY_UNTIL_WORKSPACE_ERASE"
}

enum FunctionalRelationshipDeletionLedgerPolicyV1 {
    static func disposition(
        for kind: V12BackupFunctionalRelationshipRecordV1.Kind
    ) -> FunctionalRelationshipDeletionDispositionV1 {
        switch kind {
        case .descriptor, .event: return .preserveImmutableHistoryUntilWorkspaceErase
        }
    }

    static func validate() throws {
        let kinds = V12BackupFunctionalRelationshipRecordV1.Kind.allCases
        guard kinds.count == 2, Set(kinds.map(\.rawValue)).count == kinds.count,
              kinds.allSatisfy({ disposition(for: $0) == .preserveImmutableHistoryUntilWorkspaceErase })
        else { throw DeletionLedgerFailureV2.invalidIdentity }
    }
}

enum EvidenceAssuranceDeletionLedgerPolicyV1 {
    static func validate() throws {
        let kinds = V13BackupEvidenceAssuranceRecordV1.Kind.allCases
        guard kinds.count == 4, Set(kinds.map(\.rawValue)).count == kinds.count else {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
    }
}

enum InspectionReviewDeletionLedgerPolicyV1 {
    static func validate() throws {
        let kinds = V14BackupInspectionReviewRecordV1.Kind.allCases
        guard kinds.count == 5, Set(kinds.map(\.rawValue)).count == kinds.count else {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
    }
}

enum WorkPacketDeletionLedgerPolicyV1 {static func validate()throws{let kinds=V15BackupWorkPacketRecordV1.Kind.allCases;guard kinds.count==5,Set(kinds.map(\.rawValue)).count==kinds.count else{throw DeletionLedgerFailureV2.invalidIdentity}}}

enum FieldDraftDeletionLedgerPolicyV1 {
    static func validate() throws {
        let kinds = V16BackupFieldDraftRecordV1.Kind.allCases
        guard kinds.count == 6, Set(kinds.map(\.rawValue)).count == kinds.count else {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
    }
}

struct DeletionIdentityV2: Codable, Comparable, Equatable, Hashable, Sendable {
    static let separator = ":"

    let kind: DeletionRecordKindV2
    let id: UUID

    init(kind: DeletionRecordKindV2, id: UUID) throws {
        guard id.uuidString != "00000000-0000-0000-0000-000000000000" else {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
        self.kind = kind
        self.id = id
    }

    init(typedID: String) throws {
        let pieces = typedID.split(separator: Character(Self.separator), omittingEmptySubsequences: false)
        guard pieces.count == 2,
              let kind = DeletionRecordKindV2(rawValue: String(pieces[0])),
              let id = UUID(uuidString: String(pieces[1])),
              id.uuidString.lowercased() == pieces[1] else {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
        try self.init(kind: kind, id: id)
    }

    var typedID: String {
        kind.rawValue + Self.separator + id.uuidString.lowercased()
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.typedID < rhs.typedID
    }
}

struct DeletionLedgerEntryV2: Codable, Equatable, Hashable, Sendable {
    let schemaVersion: Int
    let identity: DeletionIdentityV2
    let deletedAt: Date

    init(
        identity: DeletionIdentityV2,
        deletedAt: Date,
        schemaVersion: Int = 2
    ) throws {
        self.schemaVersion = schemaVersion
        self.identity = identity
        self.deletedAt = deletedAt
        try validate()
    }

    func validate() throws {
        try EvidenceMetadataDeletionLedgerPolicyV1.validate()
        try PrivacyTransformDeletionLedgerPolicyV1.validate()
        try MeasurementIntegrityDeletionLedgerPolicyV1.validate()
        try PackageEvolutionDeletionLedgerPolicyV1.validate()
        try PartyAccountabilityDeletionLedgerPolicyV1.validate()
        try AssetSemanticDeletionLedgerPolicyV1.validate()
        try AuthorityCriterionDeletionLedgerPolicyV1.validate()
        try FunctionalRelationshipDeletionLedgerPolicyV1.validate()
        try EvidenceAssuranceDeletionLedgerPolicyV1.validate()
        try ScheduleDeletionLedgerPolicyV1.validate()
        try AssetLabelDeletionLedgerPolicyV1.validate()
        guard schemaVersion == 2 else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
        guard deletedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw DeletionLedgerFailureV2.invalidTimestamp
        }
        _ = try DeletionIdentityV2(typedID: identity.typedID)
    }
}

enum PrivacyTransformDeletionLedgerPolicyV1 {
    enum Disposition: String, Codable, Sendable { case preserveImmutableOriginalAndDerivativeHistory }
    static func disposition(for kind: V19BackupPrivacyTransformRecordV1.Kind) -> Disposition {
        _ = kind
        return .preserveImmutableOriginalAndDerivativeHistory
    }
    static func validate() throws {
        guard V19BackupPrivacyTransformRecordV1.Kind.allCases.count == 4,
              V19BackupPrivacyTransformRecordV1.Kind.allCases.allSatisfy({ disposition(for: $0) == .preserveImmutableOriginalAndDerivativeHistory }) else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
    }
}

enum PackageEvolutionDeletionLedgerPolicyV1 {
    enum Disposition: String, Sendable { case preservePromotedHistoryUntilWorkspaceErase }
    static func disposition(for kind: V17BackupPackageEvolutionRecordV1.Kind) -> Disposition {
        _ = kind
        return .preservePromotedHistoryUntilWorkspaceErase
    }
    static func validate() throws {
        guard V17BackupPackageEvolutionRecordV1.Kind.allCases.count == 4,
              V17BackupPackageEvolutionRecordV1.Kind.allCases.allSatisfy({
                  disposition(for: $0) == .preservePromotedHistoryUntilWorkspaceErase
              }) else { throw DeletionLedgerFailureV2.invalidSchemaVersion }
    }
}

enum MeasurementIntegrityDeletionLedgerPolicyV1 {
    enum Disposition: String, Codable, Sendable { case preserveImmutableHistory, eraseWithWorkspace }
    static func disposition(for kind: V18BackupMeasurementIntegrityRecordV1.Kind) -> Disposition {
        switch kind {
        case .instrumentReference, .calibrationSnapshot, .measurementCapture, .measurementSeries, .qualityAssessment:
            return .preserveImmutableHistory
        }
    }
    static func validate() throws {
        guard V18BackupMeasurementIntegrityRecordV1.Kind.allCases.count == 5,
              V18BackupMeasurementIntegrityRecordV1.Kind.allCases.allSatisfy({ disposition(for: $0) == .preserveImmutableHistory }) else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
    }
}

/// Locator lookup rows are asset-owned durable state.  An ordinary asset
/// deletion removes the lookup/receipt rows together so no row can outlive its
/// asset; workspace erase additionally requires the entire locator closure to
/// be empty.  Lifecycle events themselves remain in the mutation journal.
enum AssetLocatorDeletionLedgerPolicyV1 {
    static let durableFamilies = ["AssetLocatorRow", "LocatorBindingReceiptRow"]
    static let durableFamilyCount = 2
    static let ordinaryDeletionRemovesAssetOwnedLookupRows = true
    static let workspaceEraseRemovesEntireClosure = true
    static let lifecycleEventsRemainInMutationHistory = true

    static func validate() throws {
        guard V26BackupAssetLocatorRecordV1.Kind.allCases.count == durableFamilyCount,
              durableFamilies.count == durableFamilyCount,
              ordinaryDeletionRemovesAssetOwnedLookupRows,
              workspaceEraseRemovesEntireClosure,
              lifecycleEventsRemainInMutationHistory else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
    }
}

/// Ordinary asset/site deletion retains immutable context and comparison
/// provenance; workspace Erase is the only operation that removes the rows.
enum C30EvidenceContextDeletionLedgerPolicyV1 {
    static let durableKinds = ["EvidenceContextRow", "PairedObservationLinkRow"]
    static let ordinaryDeletionPreservesImmutableHistory = true
    static let workspaceEraseRemovesRowsAndOwnedBytes = true
    static let derivedProjectionIsNotDeletionTruth = true

    static func validate(contexts: [EvidenceContextV1],
                         links: [PairedObservationLinkV1]) throws {
        guard durableKinds.count == 2,
              ordinaryDeletionPreservesImmutableHistory,
              workspaceEraseRemovesRowsAndOwnedBytes,
              derivedProjectionIsNotDeletionTruth else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
        try contexts.forEach { try $0.validateIntrinsic() }
        try links.forEach { try $0.validateIntrinsic() }
        guard Set(contexts.map(\.contextID)).count == contexts.count,
              Set(links.map(\.linkID)).count == links.count else {
            throw DeletionLedgerFailureV2.duplicateIdentity
        }
    }
}

/// Lighting roots are immutable evidence-bearing records. Ordinary asset/site
/// deletion must leave their historical bytes addressable; workspace Erase is
/// the sole operation allowed to remove the complete five-root closure.
enum C31LightingDeletionLedgerPolicyV1 {
    static let durableKinds = V31BackupLightingRecordV1.Kind.allCases
    static let durableFamilyCount = 5
    static let ordinaryDeletionPreservesImmutableHistory = true
    static let workspaceEraseRemovesCompleteClosure = true
    static let derivedProjectionIsNotDeletionTruth = true
    static let orphanLightingRowsAreRejected = true

    static func validate(rows: [V31BackupLightingRecordV1] = []) throws {
        guard durableKinds.count == durableFamilyCount,
              ordinaryDeletionPreservesImmutableHistory,
              workspaceEraseRemovesCompleteClosure,
              derivedProjectionIsNotDeletionTruth,
              orphanLightingRowsAreRejected else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
        _ = try LightingBackupRecordSetV1.decode(rows)
    }
}

enum LightingNightWorkflowDeletionLedgerPolicyV1 {
    static let ordinaryDeletionPreservesImmutableHistory = true
    static let workspaceEraseRemovesCompleteClosure = true
    static func validate(rows: [V53BackupLightingNightWorkflowRecordV1] = []) throws {
        guard ordinaryDeletionPreservesImmutableHistory,
              workspaceEraseRemovesCompleteClosure else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
        _ = try LightingNightWorkflowBackupRecordSetV1.decode(rows)
    }
}

/// Accepted Assistance receipts are immutable mutation history. Entity
/// deletion never creates a partial/orphan receipt; workspace Erase removes
/// the receipt and its canonical mutation receipt together. Proposals have no
/// deletion-ledger identity because they are nonpersistent.
enum C32AssistanceDeletionLedgerPolicyV1 {
    static let durableFamilies = ["AssistanceAcceptanceReceiptRow"]
    static let ordinaryDeletionPreservesCanonicalMutationHistory = true
    static let workspaceEraseRemovesReceiptWithMutationHistory = true
    static let orphanReceiptsRejected = true
    static let proposalLedgerEntriesCreated = false

    static func validate() throws {
        guard durableFamilies.count == AssistancePersistenceEnrollmentV1.durableModelCount,
              ordinaryDeletionPreservesCanonicalMutationHistory,
              workspaceEraseRemovesReceiptWithMutationHistory,
              orphanReceiptsRejected,
              !proposalLedgerEntriesCreated else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
    }
}

/// Temporal evidence is a closed clip/anchor graph. Ordinary retention removal
/// tombstones every durable identity and schedules the exact original and
/// derivative content references for cleanup; workspace Erase owns the same
/// closure. Derivative and retention values remain canonical journal support,
/// not additional deletion-ledger row families.
enum C33TemporalEvidenceDeletionLedgerPolicyV1 {
    static let durableFamilies = ["TemporalEvidenceClipRow", "TimecodedEvidenceAnchorRow"]
    static let ordinaryRemovalClosesRowsJournalAndContent = true
    static let workspaceEraseClosesRowsJournalAndContent = true
    static let supportingValuesAreJournalEmbedded = true

    static func validate() throws {
        guard durableFamilies == TemporalEvidencePersistenceEnrollmentV1.persistentFamilies,
              durableFamilies.count == TemporalEvidencePersistenceEnrollmentV1.durableModelCount,
              ordinaryRemovalClosesRowsJournalAndContent,
              workspaceEraseClosesRowsJournalAndContent,
              supportingValuesAreJournalEmbedded else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
    }
}

struct DeletionLedgerV2: Codable, Equatable, Sendable {
    static let maximumEntryCount = 100_000

    let schemaVersion: Int
    let entries: [DeletionLedgerEntryV2]

    init(entries: [DeletionLedgerEntryV2], schemaVersion: Int = 2) throws {
        self.schemaVersion = schemaVersion
        self.entries = entries
        try validate()
    }

    static var empty: Self {
        try! Self(entries: [])
    }

    func validate() throws {
        try AuthorityCriterionDeletionLedgerPolicyV1.validate()
        try AssetLocatorDeletionLedgerPolicyV1.validate()
        try PlanDeletionLedgerPolicyV1.validate()
        try C31LightingDeletionLedgerPolicyV1.validate()
        try C32AssistanceDeletionLedgerPolicyV1.validate()
        try C33TemporalEvidenceDeletionLedgerPolicyV1.validate()
        try C52ServiceRequestDeletionLedgerPolicyV1.validate()
        try C53ServiceReliabilityDeletionLedgerBoundaryV1.validate()
        try C55PartsStockDeletionLedgerBoundaryV1.validate()
        guard schemaVersion == 2 else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
        guard entries.count <= Self.maximumEntryCount else {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
        try entries.forEach { try $0.validate() }
        let identities = entries.map(\.identity)
        guard Set(identities).count == identities.count else {
            throw DeletionLedgerFailureV2.duplicateIdentity
        }
        guard identities == identities.sorted() else {
            throw DeletionLedgerFailureV2.unorderedEntries
        }
    }

    func union(_ other: Self) throws -> Self {
        try validate()
        try other.validate()
        var byIdentity = Dictionary(uniqueKeysWithValues: entries.map { ($0.identity, $0) })
        for entry in other.entries {
            if let existing = byIdentity[entry.identity] {
                if entry.deletedAt < existing.deletedAt {
                    byIdentity[entry.identity] = entry
                }
            } else {
                byIdentity[entry.identity] = entry
            }
        }
        return try Self(entries: byIdentity.values.sorted { $0.identity < $1.identity })
    }

    func canonicalData() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

enum C45AcceptedLabelDeletionLedgerBoundaryV1 { static let snapshotDeletionRequiresWorkspaceGraphClosure=true;static let outputPossessionIsNeverInferred=true }

enum C46OperationalContactBoundary_05{static let recordsSchemaVersion=34;static let sourceBytesPersistent=false;static let platformOutcomesPersistent=false}
enum C47ActivityContractDeletionLedgerBoundaryV2 { static let finalizedAndSupersededActivityHistoryIsRetained=true;static let cancelledAndUnableActivityHistoryIsRetained=true;static let immutableActivityEvidenceIsRetained=true;static let unfinalizedMatchingSubjectGraphMayBeDeleted=true;static let ordinaryRemovalRequiresAssetTombstone=true;static let workspaceEraseOwnsAllCanonicalRowsAndReleasedSnapshotFiles=true }

enum C48PortableExchangeDeletionLedgerBoundaryV2 {
    static let createsParallelTombstoneKind = false
    static let ordinaryDeletionInvalidatesExactMappedSessions = true
    static let immutableExchangeHistoryIsRetained = true
    static let workspaceEraseClearsProtectedLocalStore = true
}
enum C52ServiceRequestBoundary_DeletionLedgerV2 {
    static let sourceKind: ServiceRequestSourceKindV1 = .portableSubmission
    static let requesterAssertionType: ServiceRequestRequesterAssertionV1.Type = ServiceRequestRequesterAssertionV1.self
    static let contactAssertionType: ServiceRequestContactAssertionV1.Type = ServiceRequestContactAssertionV1.self
    static let requesterIdentityIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.requesterIdentityIsVerified
    static let contactAssertionWording: String = "SELF_ASSERTED_UNVERIFIED"
    static let urgencyIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.urgencyIsVerified
    static let cleartextIsReadableAndForwardable: Bool = PortableServiceRequestFormatBoundaryV1.submissionIsCleartext && PortableServiceRequestFormatBoundaryV1.invitationIsReadableAndForwardable
    static let providerContactPurposeSeparationRequired: Bool = true
    static let canonicalSourceBytesAreAuthoritative: Bool = true
    static let duplicateCandidatesAreDerived: Bool = !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityMayBecomeWorkspaceTruth: Bool = ServiceRequestNoncanonicalBoundaryV1.rawCapabilityIsWorkspaceTruth
    static let automaticWorkOrDuplicateActionPermitted: Bool = ServiceRequestNoncanonicalBoundaryV1.automaticWorkCreationPermitted || ServiceRequestNoncanonicalBoundaryV1.automaticDuplicateMergePermitted
    static let excludedSurfaces: [String] = ["REPORT", "SEARCH", "DIAGNOSTIC", "LIFECYCLE", "COMPATIBILITY", "BACKUP", "DELETE"]
}

/// C53 source rows are deleted through the existing whole-sign ledger and
/// mutation journal.  Incident/exposure history remains append-only until
/// workspace Erase; the ledger never becomes a second reliability store.
enum C53ServiceReliabilityDeletionLedgerBoundaryV1 {
    static let durableFamilyCount = AssetServiceReliabilityPersistenceEnrollmentV1.durableFamilies.count
    static let durableFamilies = AssetServiceReliabilityPersistenceEnrollmentV1.durableFamilies
    static let ordinaryDeletionPreservesAppendOnlyHistory = true
    static let ordinaryDeletionPreservesReliabilityIdentityEpochs = true
    static let workspaceEraseClearsAllSourceRowsAndReceipts = true
    static let derivedProjectionsAreRebuilt = true
    static let derivedProjectionsCreateLedgerEntries = false
    static let createsParallelTombstoneFamily = false

    static func validate() throws {
        try AssetServiceReliabilityPersistenceEnrollmentV1.validate()
        guard durableFamilyCount == 7,
              durableFamilies.count == durableFamilyCount,
              ordinaryDeletionPreservesAppendOnlyHistory,
              ordinaryDeletionPreservesReliabilityIdentityEpochs,
              workspaceEraseClearsAllSourceRowsAndReceipts,
              derivedProjectionsAreRebuilt,
              !derivedProjectionsCreateLedgerEntries,
              !createsParallelTombstoneFamily else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
    }

    static func eraseClosure(
        records: V4BackupRecordsV1,
        workspaceID: UUID
    ) throws -> C53ServiceReliabilityEraseClosureV1 {
        try validate()
        return try C53ServiceReliabilityEraseClosureV1(
            records: records,
            workspaceID: workspaceID
        )
    }
}

/// C55 has no backup-specific tombstone family. Ordinary catalog retirement
/// keeps movement/use/return history; only the incumbent workspace erase
/// authority clears the seven canonical rows together.
enum C55PartsStockDeletionLedgerBoundaryV1 {
    static let durableFamilyCount = C55PartsStockKernelBackupRestoreEnrollmentV1.durableFamilies.count
    static let ordinaryDeletePreservesAppendOnlyHistory = true
    static let workspaceEraseClearsAllFamilies = true
    static let createsParallelTombstoneFamily = false

    static func validate() throws {
        guard durableFamilyCount == 7,
              ordinaryDeletePreservesAppendOnlyHistory,
              workspaceEraseClearsAllFamilies,
              !createsParallelTombstoneFamily else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
    }
}

struct C53ServiceReliabilityEraseClosureV1: Equatable, Sendable {
    let workspaceID: UUID
    let sourceEventIDs: [UUID]
    let receiptMutationIDs: [UUID]

    init(records: V4BackupRecordsV1, workspaceID: UUID) throws {
        guard workspaceID != UUID.zero else { throw DeletionLedgerFailureV2.invalidIdentity }
        let rows: C53ServiceReliabilityBackupRowsV1
        do {
            rows = try C53ServiceReliabilityBackupEnrollmentV1.canonicalRows(
                from: records,
                workspaceID: workspaceID
            )
        } catch {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
        let eventIDs = rows.incidents.map(\.eventID)
            + rows.impactSegments.map(\.eventID)
            + rows.causeAssertions.map(\.eventID)
            + rows.remedyAssertions.map(\.eventID)
            + rows.repairIntervals.map(\.eventID)
            + rows.restorationAssertions.map(\.eventID)
            + rows.qualifiedExposures.map(\.eventID)
        guard Set(eventIDs).count == eventIDs.count else {
            throw DeletionLedgerFailureV2.duplicateIdentity
        }
        let mutationIDs = rows.receipts.map { $0.mutationReceipt.mutationID.rawValue }
        guard Set(mutationIDs).count == mutationIDs.count else {
            throw DeletionLedgerFailureV2.duplicateIdentity
        }
        self.workspaceID = workspaceID
        sourceEventIDs = eventIDs.sorted { $0.uuidString < $1.uuidString }
        receiptMutationIDs = mutationIDs.sorted { $0.uuidString < $1.uuidString }
    }

    func validate(records: V4BackupRecordsV1) throws {
        let expected = try Self(records: records, workspaceID: workspaceID)
        guard self == expected else { throw DeletionLedgerFailureV2.invalidIdentity }
    }
}
