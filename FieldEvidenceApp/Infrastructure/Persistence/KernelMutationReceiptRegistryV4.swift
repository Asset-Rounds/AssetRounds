import Foundation

enum KernelMutationEffectDispositionV4: String, Codable, Sendable {
    case canonicalWorkspace = "CANONICAL_WORKSPACE_EFFECT"
    case immutableAppend = "IMMUTABLE_APPEND_EFFECT"
    case appendOnlyReceipt = "APPEND_ONLY_RECEIPT_EFFECT"
    case localOperational = "LOCAL_OPERATIONAL_EFFECT"
    case recoveryJournal = "RECOVERY_JOURNAL_EFFECT"
    case dormantNoRuntimeEffect = "DORMANT_NO_RUNTIME_EFFECT"
}

enum SurveySessionKernelMutationReceiptPolicyV1{
    static let entityKinds:Set<WorkspaceEntityKindV1>=[.surveySession,.factCapture,.provisionalSubject,.subjectPromotionReceipt,.surveyPublicationSnapshot]
    static func validate(mutation:SurveySessionMutationV1,receipt:MutationReceiptV1)throws{let affected=try mutation.affectedIdentities;guard entityKinds.count==5,affected.allSatisfy({entityKinds.contains($0.kind)})else{throw WorkspaceMutationFailureV1.invalidReceipt};_ = try SurveySessionMutationReceiptV1(mutation:mutation,mutationReceipt:receipt)}
}

enum AssetLocatorKernelMutationReceiptPolicyV1{
    static let entityKinds:Set<WorkspaceEntityKindV1>=[.assetLocator,.locatorBindingReceipt]
    static func validate(mutation:AssetLocatorMutationV1,receipt:MutationReceiptV1)throws{let affected=try mutation.affectedIdentities;guard entityKinds.count==2,affected.allSatisfy({entityKinds.contains($0.kind)})else{throw WorkspaceMutationFailureV1.invalidReceipt};_ = try AssetLocatorMutationReceiptV1(mutation:mutation,mutationReceipt:receipt)}
}
enum ScheduleKernelMutationReceiptPolicyV1{static let entityKinds:Set<WorkspaceEntityKindV1>=[.scheduleDefinitionRelease,.occurrenceHistoryEvent,.exceptionCalendarRelease,.scheduleOverrideEvent];static func validate(mutation:ScheduleMutationV1,receipt:MutationReceiptV1)throws{let affected=try mutation.affectedIdentities;guard entityKinds.count==4,affected.allSatisfy({entityKinds.contains($0.kind)})else{throw WorkspaceMutationFailureV1.invalidReceipt};_ = try ScheduleMutationReceiptV1(mutation:mutation,mutationReceipt:receipt)}}
enum PlanKernelMutationReceiptPolicyV1{static let entityKinds:Set<WorkspaceEntityKindV1>=[.planDocument,.planRevision,.planPlacement,.planRebaseReceipt];static func validate(mutation:PlanMutationV1,receipt:MutationReceiptV1)throws{let affected=try mutation.affectedIdentities;guard entityKinds.count==4,affected.allSatisfy({entityKinds.contains($0.kind)})else{throw WorkspaceMutationFailureV1.invalidReceipt};_ = try PlanMutationReceiptV1(mutation:mutation,mutationReceipt:receipt)}}
enum PlacementPoseKernelMutationReceiptPolicyV1{static let entityKinds:Set<WorkspaceEntityKindV1>=[.assetPoseEvent,.spatialAnchorObservation];static func validate(mutation:PlacementPoseMutationV1,receipt:MutationReceiptV1)throws{let affected=try mutation.affectedIdentities;guard entityKinds.count==2,affected.allSatisfy({entityKinds.contains($0.kind)})else{throw WorkspaceMutationFailureV1.invalidReceipt};_ = try PlacementPoseMutationReceiptV1(mutation:mutation,mutationReceipt:receipt)}}
enum EvidenceContextKernelMutationReceiptPolicyV1{static let entityKinds:Set<WorkspaceEntityKindV1>=[.evidenceContext,.pairedObservationLink];static func validate(operation:EvidenceContextWriteOperationV1,receipt:MutationReceiptV1)throws{let affected=try operation.affectedIdentity;guard entityKinds.contains(affected.kind)else{throw WorkspaceMutationFailureV1.invalidReceipt};_ = try EvidenceContextMutationReceiptV1(operation:operation,mutationReceipt:receipt)}}
enum LightingKernelMutationReceiptPolicyV1{static let entityKinds:Set<WorkspaceEntityKindV1>=[.lightingSystem,.lightingObservation,.lightingIssue,.lightingMeasurementPlan,.lightingClaimState];static func validate(operation:LightingWriteOperationV1,receipt:MutationReceiptV1)throws{guard entityKinds.contains((try operation.affectedIdentity).kind)else{throw WorkspaceMutationFailureV1.invalidReceipt};_ = try LightingMutationReceiptV1(operation:operation,mutationReceipt:receipt)}}
enum EvidenceMetadataKernelMutationReceiptPolicyV1 {
    static let entityKinds: Set<WorkspaceEntityKindV1> = [
        .evidenceAssociationEvent,
        .evidenceSequenceRevision,
    ]

    static func validate(
        mutation: EvidenceMetadataMutationV1,
        receipt: MutationReceiptV1
    ) throws {
        let affected = try mutation.affectedIdentities
        guard affected.count == 2,
              Set(affected.map(\.kind)) == entityKinds else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
        _ = try EvidenceMetadataMutationReceiptV1(
            mutation: mutation,
            mutationReceipt: receipt
        )
    }
}

enum ShopReportProfileKernelMutationReceiptPolicyV1 {
    static let entityKinds: Set<WorkspaceEntityKindV1> = [.shopReportProfile]

    static func validate(
        mutation: ShopReportProfileMutationV1,
        receipt: MutationReceiptV1
    ) throws {
        try mutation.validate()
        guard [try mutation.affectedIdentity].map(\.kind) == [.shopReportProfile] else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
        _ = try ShopReportProfileMutationReceiptV1(
            mutation: mutation,
            mutationReceipt: receipt
        )
    }
}

enum RoundSessionKernelMutationReceiptPolicyV1 {
    static let entityKinds: Set<WorkspaceEntityKindV1> = [.roundSession]

    static func validate(
        mutation: RoundSessionMutationV1,
        receipt: MutationReceiptV1
    ) throws {
        try mutation.validate()
        guard [try mutation.affectedIdentity].map(\.kind) == [.roundSession] else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
        _ = try RoundSessionMutationReceiptV1(
            mutation: mutation,
            mutationReceipt: receipt
        )
    }
}

struct KernelMutationRegistrationV4: Codable, Equatable, Comparable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, mutationEnvelopeTypeID, effectID, effectDisposition, receiptTypeID
        case expectedRevisionRequired, durableReceiptRequired, effectBeforeReceiptRecovery
    }

    let kind: KernelPersistenceV4RecordKind
    let mutationEnvelopeTypeID: String
    let effectID: String
    let effectDisposition: KernelMutationEffectDispositionV4
    let receiptTypeID: String
    let expectedRevisionRequired: Bool
    let durableReceiptRequired: Bool
    let effectBeforeReceiptRecovery: Bool

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.kind < rhs.kind }

    init(
        kind: KernelPersistenceV4RecordKind,
        mutationEnvelopeTypeID: String,
        effectID: String,
        effectDisposition: KernelMutationEffectDispositionV4,
        receiptTypeID: String,
        expectedRevisionRequired: Bool = true,
        durableReceiptRequired: Bool = true,
        effectBeforeReceiptRecovery: Bool = true
    ) throws {
        self.kind = kind
        self.mutationEnvelopeTypeID = mutationEnvelopeTypeID
        self.effectID = effectID
        self.effectDisposition = effectDisposition
        self.receiptTypeID = receiptTypeID
        self.expectedRevisionRequired = expectedRevisionRequired
        self.durableReceiptRequired = durableReceiptRequired
        self.effectBeforeReceiptRecovery = effectBeforeReceiptRecovery
        try validate()
    }

    init(from decoder: Decoder) throws {
        try KernelPersistenceV4Validation.rejectUnknownKeys(decoder, keys: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: values.decode(KernelPersistenceV4RecordKind.self, forKey: .kind),
            mutationEnvelopeTypeID: values.decode(String.self, forKey: .mutationEnvelopeTypeID),
            effectID: values.decode(String.self, forKey: .effectID),
            effectDisposition: values.decode(KernelMutationEffectDispositionV4.self, forKey: .effectDisposition),
            receiptTypeID: values.decode(String.self, forKey: .receiptTypeID),
            expectedRevisionRequired: values.decode(Bool.self, forKey: .expectedRevisionRequired),
            durableReceiptRequired: values.decode(Bool.self, forKey: .durableReceiptRequired),
            effectBeforeReceiptRecovery: values.decode(Bool.self, forKey: .effectBeforeReceiptRecovery)
        )
    }

    func validate() throws {
        let descriptor = try KernelPersistenceV4Schema.recordDescriptor(for: kind)
        guard mutationEnvelopeTypeID == "MutationEnvelopeV1",
              effectID == descriptor.canonicalMutationEffectID,
              effectDisposition == KernelMutationReceiptRegistryV4.effectDisposition(descriptor.classification),
              receiptTypeID == "KernelMutationReceiptV4",
              expectedRevisionRequired, durableReceiptRequired, effectBeforeReceiptRecovery else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
        if descriptor.classification == .dormantContractDeclaration {
            guard effectDisposition == .dormantNoRuntimeEffect else {
                throw KernelPersistenceV4Failure.partialActivation
            }
        }
    }
}

struct KernelMutationEffectV4: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaID, schemaVersion, kind, mutationID, expectedRevision, resultingRevision
        case payloadSHA256, effectID, effectSHA256
    }

    let schemaID: String
    let schemaVersion: Int
    let kind: KernelPersistenceV4RecordKind
    let mutationID: String
    let expectedRevision: UInt64
    let resultingRevision: UInt64
    let payloadSHA256: String
    let effectID: String
    let effectSHA256: String

    init(
        kind: KernelPersistenceV4RecordKind,
        mutationID: String,
        expectedRevision: UInt64,
        resultingRevision: UInt64,
        payloadSHA256: String,
        effectID: String,
        effectSHA256: String? = nil
    ) throws {
        schemaID = KernelPersistenceV4Validation.schemaID
        schemaVersion = KernelPersistenceV4Validation.schemaVersion
        self.kind = kind
        self.mutationID = mutationID
        self.expectedRevision = expectedRevision
        self.resultingRevision = resultingRevision
        self.payloadSHA256 = payloadSHA256
        self.effectID = effectID
        self.effectSHA256 = try effectSHA256 ?? Self.digest(
            kind: kind, mutationID: mutationID, expectedRevision: expectedRevision,
            resultingRevision: resultingRevision, payloadSHA256: payloadSHA256, effectID: effectID
        )
        try validate()
    }

    init(from decoder: Decoder) throws {
        try KernelPersistenceV4Validation.rejectUnknownKeys(decoder, keys: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(String.self, forKey: .schemaID) == KernelPersistenceV4Validation.schemaID,
              try values.decode(Int.self, forKey: .schemaVersion) == KernelPersistenceV4Validation.schemaVersion else {
            throw KernelPersistenceV4Failure.futureVersion
        }
        try self.init(
            kind: values.decode(KernelPersistenceV4RecordKind.self, forKey: .kind),
            mutationID: values.decode(String.self, forKey: .mutationID),
            expectedRevision: values.decode(UInt64.self, forKey: .expectedRevision),
            resultingRevision: values.decode(UInt64.self, forKey: .resultingRevision),
            payloadSHA256: values.decode(String.self, forKey: .payloadSHA256),
            effectID: values.decode(String.self, forKey: .effectID),
            effectSHA256: values.decode(String.self, forKey: .effectSHA256)
        )
    }

    func validate() throws {
        let registration = try KernelMutationReceiptRegistryV4.registration(for: kind)
        guard schemaID == KernelPersistenceV4Validation.schemaID,
              schemaVersion == KernelPersistenceV4Validation.schemaVersion,
              registration.effectDisposition != .dormantNoRuntimeEffect,
              KernelPersistenceV4Validation.validID(mutationID),
              expectedRevision < UInt64.max,
              resultingRevision == expectedRevision + 1,
              Self.validSHA256(payloadSHA256), effectID == registration.effectID,
              effectSHA256 == (try Self.digest(
                kind: kind, mutationID: mutationID, expectedRevision: expectedRevision,
                resultingRevision: resultingRevision, payloadSHA256: payloadSHA256, effectID: effectID
              )) else {
            throw KernelPersistenceV4Failure.invalidTransition
        }
    }

    private struct DigestMaterial: Encodable {
        let schemaID: String
        let schemaVersion: Int
        let kind: KernelPersistenceV4RecordKind
        let mutationID: String
        let expectedRevision: UInt64
        let resultingRevision: UInt64
        let payloadSHA256: String
        let effectID: String
    }

    private static func digest(
        kind: KernelPersistenceV4RecordKind,
        mutationID: String,
        expectedRevision: UInt64,
        resultingRevision: UInt64,
        payloadSHA256: String,
        effectID: String
    ) throws -> String {
        try KernelPersistenceV4Validation.canonicalDigest(DigestMaterial(
            schemaID: KernelPersistenceV4Validation.schemaID,
            schemaVersion: KernelPersistenceV4Validation.schemaVersion,
            kind: kind, mutationID: mutationID, expectedRevision: expectedRevision,
            resultingRevision: resultingRevision, payloadSHA256: payloadSHA256, effectID: effectID
        ))
    }

    static func validSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }
}

struct KernelMutationReceiptV4: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaID, schemaVersion, kind, mutationID, effectSHA256, resultingRevision, receiptSHA256
    }

    let schemaID: String
    let schemaVersion: Int
    let kind: KernelPersistenceV4RecordKind
    let mutationID: String
    let effectSHA256: String
    let resultingRevision: UInt64
    let receiptSHA256: String

    init(effect: KernelMutationEffectV4, receiptSHA256: String? = nil) throws {
        try effect.validate()
        schemaID = KernelPersistenceV4Validation.schemaID
        schemaVersion = KernelPersistenceV4Validation.schemaVersion
        kind = effect.kind
        mutationID = effect.mutationID
        effectSHA256 = effect.effectSHA256
        resultingRevision = effect.resultingRevision
        self.receiptSHA256 = try receiptSHA256 ?? Self.digest(
            kind: kind, mutationID: mutationID, effectSHA256: effectSHA256,
            resultingRevision: resultingRevision
        )
        try validate()
    }

    init(from decoder: Decoder) throws {
        try KernelPersistenceV4Validation.rejectUnknownKeys(decoder, keys: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(String.self, forKey: .schemaID) == KernelPersistenceV4Validation.schemaID,
              try values.decode(Int.self, forKey: .schemaVersion) == KernelPersistenceV4Validation.schemaVersion else {
            throw KernelPersistenceV4Failure.futureVersion
        }
        let kind = try values.decode(KernelPersistenceV4RecordKind.self, forKey: .kind)
        let mutationID = try values.decode(String.self, forKey: .mutationID)
        let effectSHA256 = try values.decode(String.self, forKey: .effectSHA256)
        let resultingRevision = try values.decode(UInt64.self, forKey: .resultingRevision)
        let receiptSHA256 = try values.decode(String.self, forKey: .receiptSHA256)
        schemaID = KernelPersistenceV4Validation.schemaID
        schemaVersion = KernelPersistenceV4Validation.schemaVersion
        self.kind = kind
        self.mutationID = mutationID
        self.effectSHA256 = effectSHA256
        self.resultingRevision = resultingRevision
        self.receiptSHA256 = receiptSHA256
        try validate()
    }

    func validate() throws {
        _ = try KernelMutationReceiptRegistryV4.registration(for: kind)
        guard schemaID == KernelPersistenceV4Validation.schemaID,
              schemaVersion == KernelPersistenceV4Validation.schemaVersion,
              KernelPersistenceV4Validation.validID(mutationID),
              KernelMutationEffectV4.validSHA256(effectSHA256),
              resultingRevision > 0,
              receiptSHA256 == (try Self.digest(
                kind: kind, mutationID: mutationID, effectSHA256: effectSHA256,
                resultingRevision: resultingRevision
              )) else {
            throw KernelPersistenceV4Failure.digestMismatch
        }
    }

    private struct DigestMaterial: Encodable {
        let schemaID: String
        let schemaVersion: Int
        let kind: KernelPersistenceV4RecordKind
        let mutationID: String
        let effectSHA256: String
        let resultingRevision: UInt64
    }

    private static func digest(
        kind: KernelPersistenceV4RecordKind,
        mutationID: String,
        effectSHA256: String,
        resultingRevision: UInt64
    ) throws -> String {
        try KernelPersistenceV4Validation.canonicalDigest(DigestMaterial(
            schemaID: KernelPersistenceV4Validation.schemaID,
            schemaVersion: KernelPersistenceV4Validation.schemaVersion,
            kind: kind, mutationID: mutationID, effectSHA256: effectSHA256,
            resultingRevision: resultingRevision
        ))
    }
}

enum KernelMutationReceiptRegistryV4 {
    static func validatePackagePromotion(
        mutation: PackagePromotionMutationV1,
        receipt: MutationReceiptV1
    ) throws {
        _ = try PackagePromotionMutationReceiptV1(
            mutation: mutation,
            mutationReceipt: receipt
        )
    }
    static func validateMeasurementIntegrity(mutation:MeasurementIntegrityMutationV1,receipt:MutationReceiptV1)throws{_ = try MeasurementIntegrityMutationReceiptV1(mutation:mutation,mutationReceipt:receipt)}
    static func validatePrivacyTransform(mutation:PrivacyTransformMutationV1,receipt:MutationReceiptV1)throws{_ = try PrivacyTransformMutationReceiptV1(mutation:mutation,mutationReceipt:receipt)}
    static func validateEvidenceMetadata(
        mutation: EvidenceMetadataMutationV1,
        receipt: MutationReceiptV1
    ) throws {
        try EvidenceMetadataKernelMutationReceiptPolicyV1.validate(
            mutation: mutation,
            receipt: receipt
        )
    }
    static func validateFastSurveyInbox(
        command: FastSurveyInboxMutationCommandV1,
        receipt: FastSurveyInboxMutationReceiptV1
    ) throws {
        try command.validate()
        try receipt.validate(command: command)
        let targets = try command.affectedIdentitiesForCanonicalWriter()
        guard (1...2).contains(targets.count),
              targets == targets.sorted { $0.stableKey < $1.stableKey },
              Set(targets).count == targets.count,
              receipt.semanticSHA256s == command.payload.semanticSHA256s else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
    }
    static func validateReinspectionException(
        command: ReinspectionExceptionMutationCommandV1,
        receipt: ReinspectionExceptionMutationReceiptV1
    ) throws {
        try command.validate()
        try receipt.validate(command: command)
        let targets = try command.affectedIdentitiesForCanonicalWriter()
        guard targets.count == 1,
              receipt.recoveryState == .receiptCommitted,
              receipt.semanticSHA256s == command.payload.semanticSHA256s.sorted() else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
    }

    /// C13 receives the generic receipt through the one canonical writer and
    /// persists a typed receipt only when it closes the exact immutable alias
    /// or consolidation effect. A preview plan never reaches this boundary.
    static func validateEntityIdentityResolution(
        command: EntityIdentityResolutionMutationCommandV1,
        receipt: EntityIdentityResolutionMutationReceiptV1
    ) throws {
        try command.validate()
        try receipt.validate(command: command)
        guard receipt.recoveryState == .receiptCommitted,
              receipt.semanticSHA256s == command.payload.semanticSHA256s.sorted(),
              receipt.resultingWorkspaceRevision
                == command.expectedRevision.workspaceRevision + 1 else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
    }
    static func validateShopReportProfile(
        mutation: ShopReportProfileMutationV1,
        receipt: MutationReceiptV1
    ) throws {
        try ShopReportProfileKernelMutationReceiptPolicyV1.validate(
            mutation: mutation,
            receipt: receipt
        )
    }
    static func validateRoundSession(
        mutation: RoundSessionMutationV1,
        receipt: MutationReceiptV1
    ) throws {
        try RoundSessionKernelMutationReceiptPolicyV1.validate(
            mutation: mutation,
            receipt: receipt
        )
    }
    static func validateClientCapability(mutation:ClientCapabilityMutationV1,receipt:MutationReceiptV1)throws{_ = try ClientCapabilityMutationReceiptV1(mutation:mutation,mutationReceipt:receipt)}
    static func validateFieldReference(mutation:FieldReferenceMutationV1,receipt:MutationReceiptV1)throws{_ = try FieldReferenceMutationReceiptV1(mutation:mutation,mutationReceipt:receipt)}
    static func validateAccessibleDocumentAssessment(mutation:AccessibleDocumentMutationV1,receipt:MutationReceiptV1)throws{_ = try AccessibleDocumentMutationReceiptV1(mutation:mutation,mutationReceipt:receipt)}
    static func validateSurveyDefinition(mutation:SurveyDefinitionMutationV1,receipt:MutationReceiptV1)throws{_ = try SurveyDefinitionMutationReceiptV1(mutation:mutation,mutationReceipt:receipt)}
    static func validateTemporalEvidence(
        mutation: TemporalEvidenceMutationV1,
        receipt: MutationReceiptV1
    ) throws {
        try C33TemporalEvidenceJournalBoundaryV1.validate(
            mutation: mutation,
            receipt: receipt
        )
    }
    static let registrations: [KernelMutationRegistrationV4] = {
        do {
            return try KernelPersistenceV4RecordKind.allCases.map { kind in
                let descriptor = try KernelPersistenceV4Schema.recordDescriptor(for: kind)
                return try KernelMutationRegistrationV4(
                    kind: kind,
                    mutationEnvelopeTypeID: "MutationEnvelopeV1",
                    effectID: descriptor.canonicalMutationEffectID,
                    effectDisposition: effectDisposition(descriptor.classification),
                    receiptTypeID: "KernelMutationReceiptV4"
                )
            }.sorted()
        } catch { preconditionFailure("Invalid KERNEL_PERSISTENCE_V4 mutation registry: \(error)") }
    }()

    /// Receipt-producing kernel registrations are metadata only. C17 derives
    /// its provider-neutral events from accepted `MutationReceiptV1` journal
    /// rows, never from these effect declarations or from provider state.
    static var acceptedProjectionSourceRegistrations: [KernelMutationRegistrationV4] {
        registrations.filter {
            $0.durableReceiptRequired
                && $0.effectBeforeReceiptRecovery
                && $0.effectDisposition != .dormantNoRuntimeEffect
        }
    }

    static func validateAcceptedProjectionSource() throws {
        let coverage = IntegrationEventJournalCoverageV1()
        try coverage.validate()
        try validate()
        guard !acceptedProjectionSourceRegistrations.isEmpty,
              acceptedProjectionSourceRegistrations == acceptedProjectionSourceRegistrations.sorted(),
              acceptedProjectionSourceRegistrations.allSatisfy({
                  $0.durableReceiptRequired
                      && $0.effectBeforeReceiptRecovery
                      && $0.effectDisposition != .dormantNoRuntimeEffect
              }) else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }

    static func registration(for kind: KernelPersistenceV4RecordKind) throws -> KernelMutationRegistrationV4 {
        let matches = registrations.filter { $0.kind == kind }
        guard matches.count == 1, let value = matches.first else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
        return value
    }

    static var canonicalDigest: String {
        get throws { try KernelPersistenceV4Validation.canonicalDigest(registrations) }
    }

    static func validate() throws {
        guard C50IncumbentFileExchangeKernelMutationReceiptBoundaryV1.validate(),
              C04ShopReportProfileKernelMutationReceiptBoundaryV1.validate(),
              C05RoundSessionKernelMutationReceiptBoundaryV1.validate(),
              C11FastSurveyInboxKernelMutationReceiptBoundaryV1.validate(),
              C12ReinspectionExceptionKernelMutationReceiptBoundaryV1.validate(),
              C13EntityIdentityResolutionKernelMutationReceiptBoundaryV1.validate() else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
        try validate(registrations)
    }

    static func validate(_ candidate: [KernelMutationRegistrationV4]) throws {
        try KernelPersistenceV4Schema.validate()
        try candidate.forEach { try $0.validate() }
        let kinds = candidate.map(\.kind)
        guard candidate == candidate.sorted(),
              kinds == KernelPersistenceV4RecordKind.allCases.sorted(),
              Set(kinds).count == kinds.count,
              Set(candidate.map(\.effectID)).count == candidate.count else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }

    static func receipt(for effect: KernelMutationEffectV4) throws -> KernelMutationReceiptV4 {
        try KernelMutationReceiptV4(effect: effect)
    }

    static func reconcile(
        effect: KernelMutationEffectV4,
        existingReceipt: KernelMutationReceiptV4?
    ) throws -> KernelMutationReceiptV4 {
        let canonical = try receipt(for: effect)
        guard let existingReceipt else { return canonical }
        try existingReceipt.validate()
        guard existingReceipt == canonical else { throw KernelPersistenceV4Failure.duplicateIdentity }
        return existingReceipt
    }

    static func effectDisposition(
        _ classification: KernelPersistenceV4Classification
    ) -> KernelMutationEffectDispositionV4 {
        switch classification {
        case .canonicalWorkspace: return .canonicalWorkspace
        case .immutableContentMetadata: return .immutableAppend
        case .appendOnlyReceipt: return .appendOnlyReceipt
        case .deviceLocalOperational: return .localOperational
        case .recoveryJournal: return .recoveryJournal
        case .dormantContractDeclaration: return .dormantNoRuntimeEffect
        }
    }
}

enum C04ShopReportProfileKernelMutationReceiptBoundaryV1 {
    static let commandKind: WorkspaceCommandKindV1 = .applyShopReportProfile
    static let durableReceiptRequired = true
    static let effectBeforeReceiptRecovery = true
    static let postimageCount = 1

    static func validate() -> Bool {
        commandKind == .applyShopReportProfile
            && durableReceiptRequired
            && effectBeforeReceiptRecovery
            && postimageCount == 1
    }
}

enum C05RoundSessionKernelMutationReceiptBoundaryV1 {
    static let commandKind: WorkspaceCommandKindV1 = .applyRoundSession
    static let durableReceiptRequired = true
    static let effectBeforeReceiptRecovery = true
    static let postimageCount = 1

    static func validate() -> Bool {
        commandKind == .applyRoundSession
            && durableReceiptRequired
            && effectBeforeReceiptRecovery
            && postimageCount == 1
    }
}

enum C11FastSurveyInboxKernelMutationReceiptBoundaryV1 {
    static let commandKind: WorkspaceCommandKindV1 = .applyFastSurveyInbox
    static let durableReceiptRequired = true
    static let effectBeforeReceiptRecovery = true
    static let maximumPostimageCount = 2

    static func validate() -> Bool {
        commandKind == .applyFastSurveyInbox
            && durableReceiptRequired
            && effectBeforeReceiptRecovery
            && maximumPostimageCount == 2
    }
}

enum C12ReinspectionExceptionKernelMutationReceiptBoundaryV1 {
    static let commandKind: WorkspaceCommandKindV1 = .applyReinspectionException
    static let durableReceiptRequired = true
    static let effectBeforeReceiptRecovery = true
    static let postimageCount = 1

    static func validate() -> Bool {
        commandKind == .applyReinspectionException
            && durableReceiptRequired
            && effectBeforeReceiptRecovery
            && postimageCount == 1
    }
}

enum C13EntityIdentityResolutionKernelMutationReceiptBoundaryV1 {
    static let commandKind: WorkspaceCommandKindV1 = .applyEntityIdentityResolution
    static let durableReceiptRequired = true
    static let effectBeforeReceiptRecovery = true
    static let previewPlanIsNonpersistent = true

    static func validate() -> Bool {
        commandKind == .applyEntityIdentityResolution
            && durableReceiptRequired
            && effectBeforeReceiptRecovery
            && previewPlanIsNonpersistent
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Persistence_KernelMutationReceiptRegistryV4 {
    enum ProposalDispositionV1: Sendable {
        case nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
    }

    enum AcceptanceDispositionV1: Sendable {
        case durableThroughExistingCanonicalWriter
    }

    static func disposition(
        for proposal: AssistanceProposalV1
    ) throws -> ProposalDispositionV1 {
        try proposal.validate()
        guard !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent else {
            throw AssistanceContractFailureV1.nonCanonicalData
        }
        switch proposal.verificationState {
        case .unverified:
            return .nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
        }
    }

    static func disposition(
        for receipt: AssistanceAcceptanceReceiptV1
    ) throws -> AcceptanceDispositionV1 {
        try receipt.validate()
        guard AssistancePersistenceEnrollmentV1.durableModelCount == 1 else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return .durableThroughExistingCanonicalWriter
    }

    static let capabilityScratchIsDiscardedOnTerminalReview = true
    static let manualFallbackRemainsAvailable = true
    static let interruptionNeverPromotesAProposal = true
    static let createsParallelStoreOrWriter = false
}

enum C45AcceptedLabelMutationReceiptEnrollmentV1 { static let commandKind:WorkspaceCommandKindV1 = .applyAssetLabel;static let effectBeforeReceipt=true }

enum C46OperationalContactBoundary_48{static let persistentFamilies=OperationalContactPersistenceEnrollmentV1.persistentFamilies;static let platformOutcomesPersistent=false}
enum C47ActivityContractMutationReceiptEnrollmentV2 { static let commandKind:WorkspaceCommandKindV1 = .applyActivityContract;static let receiptValidatesExactFiveRowPostimages=true;static let completedSnapshotReferenceIsCompatibilityOnly=true }
enum C48PortableReviewMutationReceiptEnrollmentV1 { static let commandKind:WorkspaceCommandKindV1 = .applyPortableReview;static let canonicalPostimagesAreExistingC14Families=true;static let exactResponseBytesRemainEnvelopeAndSessionBound=true;static let sessionOnlyDecisionsAreNotKernelMutations=true }
enum C49WorkResourceMutationReceiptEnrollmentV1 { static let commandKind:WorkspaceCommandKindV1 = .applyWorkResource;static let typedReceiptBindsExactEntryPostimage=true;static let directCostHasNoIndependentReceiptOrLedger=true }

enum C50IncumbentFileExchangeKernelMutationReceiptBoundaryV1 {
    static let profileSelectionSessionSourceQuarantineDisposition = "NONPERSISTENT"
    static let canonicalRegistrationCount = 0
    static let mutationReceiptCountAdded = 0
    static let adapterStateIsNotAReceipt = true
    static let sourceAndQuarantineBytesAreNotReceipts = true
    static let canonicalImportedEffectsUseExistingReceiptRegistry = true
    static let disposition = "NOT_APPLICABLE"

    static func validate() -> Bool {
        profileSelectionSessionSourceQuarantineDisposition == "NONPERSISTENT"
            && canonicalRegistrationCount == 0
            && mutationReceiptCountAdded == 0
            && adapterStateIsNotAReceipt
            && sourceAndQuarantineBytesAreNotReceipts
            && canonicalImportedEffectsUseExistingReceiptRegistry
            && disposition == "NOT_APPLICABLE"
            && C50IncumbentFileExchangePersistenceBoundaryV1.validate()
    }
}

enum C34SceneNavigationKernelReceiptRegistryBoundaryV1 {
    static let registeredReceiptKindCount = 0
    static let registersRouteMutation = false
    static func validate() -> Bool { registeredReceiptKindCount == 0 && !registersRouteMutation && C34SceneNavigationMutationReceiptBoundaryV1.validate() }
}
// C52_BOUNDARY_ANCHOR: canonical-service-request-receipt
enum C52ServiceRequestMutationReceiptEnrollmentV1 {
    static let commandKind: WorkspaceCommandKindV1 = .applyServiceRequest
    static let typedReceipt = ServiceRequestMutationReceiptV1.self
    static let postImageKinds: [WorkspaceEntityKindV1] = [.serviceRequestRecord, .serviceRequestDispositionEvent, .serviceRequestWorkLinkEvent]
    static let durableReceiptRecoveryRequired = true
}
enum C53AssetServiceReliabilityMutationReceiptEnrollmentV1{static let commandKind:WorkspaceCommandKindV1 = .applyServiceReliability;static let typedReceipt=ServiceReliabilityMutationReceiptV1.self;static let postImageKinds:[WorkspaceEntityKindV1]=[.assetServiceIncident,.serviceImpactSegment,.serviceCauseAssertion,.serviceRemedyAssertion,.serviceRepairInterval,.serviceRestorationAssertion,.qualifiedServiceExposure];static let durableReceiptRecoveryRequired=true}
enum C55PartsStockMutationReceiptEnrollmentV1{static let commandKind:WorkspaceCommandKindV1 = .applyPartsStock;static let typedReceipt=PartsStockMutationReceiptV1.self;static let postImageKinds:[WorkspaceEntityKindV1]=[.localPartDefinition,.stockStorageLocation,.stockMovementEvent,.stockUseReceipt,.stockUseReversalReceipt,.stockReturnReceipt,.stockAbandonment,.workResourceEntry];static let durableReceiptRecoveryRequired=true}
enum C57MyDayMutationReceiptEnrollmentV1{static let commandKind:WorkspaceCommandKindV1 = .applyMyDay;static let typedReceipt=MyDayWorkspaceMutationReceiptV1.self;static let postImageKinds:[WorkspaceEntityKindV1]=[.myDayPlan,.myDayCarryoverReceipt];static let durableReceiptRecoveryRequired=true}
/// C08 uses the generic immutable mutation receipt; its three domain rows are
/// exact post-images and never form a parallel import receipt ledger.
enum C08ImportBulkMutationReceiptEnrollmentV1 {
    static let commandKind: WorkspaceCommandKindV1 = .applyImportBulk
    static let postImageKinds: [WorkspaceEntityKindV1] = [
        .importMappingProfile, .bulkSession, .bulkCommitReceipt
    ]
    static let durableReceiptRecoveryRequired = true
    static let createsSecondReceiptAuthority = false
    static func validate() -> Bool {
        commandKind == .applyImportBulk
            && postImageKinds.count == 3
            && durableReceiptRecoveryRequired
            && !createsSecondReceiptAuthority
    }
}
