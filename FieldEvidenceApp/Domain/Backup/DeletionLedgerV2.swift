import Foundation

enum DeletionLedgerFailureV2: Error, Equatable, Sendable {
    case invalidSchemaVersion
    case invalidIdentity
    case duplicateIdentity
    case unorderedEntries
    case invalidTimestamp
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
        try ClientCapabilityDeletionLedgerPolicyV1.validate()
        try RecoverabilityVerificationDeletionLedgerPolicyV1.validate()
        try FieldReferenceDeletionLedgerPolicyV1.validate()
        try AccessibleDocumentDeletionLedgerPolicyV1.validate()
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
enum AccessibleDocumentDeletionLedgerPolicyV1{static let ordinaryDeletionPreservesAcceptedReceiptAndOutput=true;static let removalRequiresPrivacyExpiryTombstoneAndRedactionProof=true;static let workspaceEraseRemovesReceiptAndOwnedOutput=true;static func validate()throws{guard AccessibleDocumentLifecycleV1.persistentFamilies==["AccessibleDocumentAssessmentReceiptV1"],AccessibleDocumentLifecycleV1.semanticTreePersistence=="DERIVED_ONLY",ordinaryDeletionPreservesAcceptedReceiptAndOutput,removalRequiresPrivacyExpiryTombstoneAndRedactionProof,workspaceEraseRemovesReceiptAndOwnedOutput else{throw DeletionLedgerFailureV2.invalidSchemaVersion}}}

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
        try PrivacyTransformDeletionLedgerPolicyV1.validate()
        try MeasurementIntegrityDeletionLedgerPolicyV1.validate()
        try PackageEvolutionDeletionLedgerPolicyV1.validate()
        try PartyAccountabilityDeletionLedgerPolicyV1.validate()
        try AssetSemanticDeletionLedgerPolicyV1.validate()
        try AuthorityCriterionDeletionLedgerPolicyV1.validate()
        try FunctionalRelationshipDeletionLedgerPolicyV1.validate()
        try EvidenceAssuranceDeletionLedgerPolicyV1.validate()
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
