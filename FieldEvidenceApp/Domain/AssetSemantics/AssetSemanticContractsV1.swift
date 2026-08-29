import Foundation

enum AssetSemanticScheduleBoundaryV1 { static let assetSemanticsInferDueState = false }

enum AssetLocatorSemanticBoundaryV1 {
    static let locatorMayInferProductIdentity = false
    static let locatorMayInferLifecycleState = false

    static func validate(_ locator: AssetLocatorV1, assetID: UUID) throws {
        try locator.validate()
        guard locator.assetID == assetID else { throw AssetLocatorFailureV1.invalidValue }
    }
}

enum AssetSemanticContractFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case duplicateValue
    case incompatibleRelease
    case unknownSemanticID
    case invalidAtomicReference
    case crossWorkspaceReference
    case cycleDetected
    case nonCanonicalData
}

enum AssetSemanticCompatibilityPolicyV1: String, Codable, CaseIterable, Hashable, Sendable {
    case exactReleaseOnly = "EXACT_RELEASE_ONLY"
    case sameSemanticIDSuccessor = "SAME_SEMANTIC_ID_SUCCESSOR"
}

struct AssetSemanticCapabilityIDV1: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) throws {
        guard AssetSemanticValidationV1.validIdentifier(rawValue, maximumBytes: 120) else {
            throw AssetSemanticContractFailureV1.invalidValue
        }
        self.rawValue = rawValue
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    private enum CodingKeys: String, CodingKey { case rawValue }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(values.decode(String.self, forKey: .rawValue))
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(rawValue, forKey: .rawValue)
    }
}

struct AssetSemanticCatalogReleaseReferenceV1: Codable, Equatable, Hashable, Sendable {
    let releaseID: UUID
    let packageRelease: PackageReleaseIdentityV1
    let catalogSHA256: String

    func validate() throws {
        guard releaseID != AssetSemanticValidationV1.zeroUUID,
              AssetSemanticValidationV1.validPackageRelease(packageRelease),
              AssetSemanticValidationV1.validSHA256(catalogSHA256) else {
            throw AssetSemanticContractFailureV1.invalidValue
        }
    }
}

struct AssetKindDefinitionV1: Codable, Equatable, Hashable, Sendable {
    let semanticID: String
    let displayNameLocalizationKey: String
    let descriptionLocalizationKey: String?
    let capabilityIDs: [AssetSemanticCapabilityIDV1]
    let compatibleWorkflowPackageReleases: [PackageReleaseIdentityV1]
    let compatibilityPolicy: AssetSemanticCompatibilityPolicyV1
    let definitionSHA256: String

    init(
        semanticID: String,
        displayNameLocalizationKey: String,
        descriptionLocalizationKey: String? = nil,
        capabilityIDs: [AssetSemanticCapabilityIDV1],
        compatibleWorkflowPackageReleases: [PackageReleaseIdentityV1] = [],
        compatibilityPolicy: AssetSemanticCompatibilityPolicyV1,
        definitionSHA256: String? = nil
    ) throws {
        let orderedCapabilities = capabilityIDs.sorted()
        let orderedWorkflowReleases = compatibleWorkflowPackageReleases.sorted()
        self.semanticID = semanticID
        self.displayNameLocalizationKey = displayNameLocalizationKey
        self.descriptionLocalizationKey = descriptionLocalizationKey
        self.capabilityIDs = orderedCapabilities
        self.compatibleWorkflowPackageReleases = orderedWorkflowReleases
        self.compatibilityPolicy = compatibilityPolicy
        let expectedSHA256 = try AssetSemanticDigestV1.sha256(
            AssetKindDefinitionDigestBasisV1(
                semanticID: semanticID,
                displayNameLocalizationKey: displayNameLocalizationKey,
                descriptionLocalizationKey: descriptionLocalizationKey,
                capabilityIDs: orderedCapabilities,
                compatibleWorkflowPackageReleases: orderedWorkflowReleases,
                compatibilityPolicy: compatibilityPolicy
            )
        )
        guard definitionSHA256 == nil || definitionSHA256 == expectedSHA256 else {
            throw AssetSemanticContractFailureV1.nonCanonicalData
        }
        self.definitionSHA256 = expectedSHA256
        try validate()
    }

    func validate() throws {
        guard AssetSemanticValidationV1.validIdentifier(semanticID, maximumBytes: 160),
              AssetSemanticValidationV1.validLocalizationKey(displayNameLocalizationKey),
              descriptionLocalizationKey.map(AssetSemanticValidationV1.validLocalizationKey) ?? true,
              capabilityIDs.count <= 64,
              capabilityIDs == capabilityIDs.sorted(),
              Set(capabilityIDs).count == capabilityIDs.count,
              compatibleWorkflowPackageReleases.count <= 32,
              compatibleWorkflowPackageReleases == compatibleWorkflowPackageReleases.sorted(),
              Set(compatibleWorkflowPackageReleases).count
                == compatibleWorkflowPackageReleases.count,
              compatibleWorkflowPackageReleases.allSatisfy(
                AssetSemanticValidationV1.validPackageRelease
              ),
              capabilityIDs.allSatisfy({
                  AssetSemanticValidationV1.validIdentifier($0.rawValue, maximumBytes: 120)
              }),
              AssetSemanticValidationV1.validSHA256(definitionSHA256),
              definitionSHA256 == (try AssetSemanticDigestV1.sha256(
                AssetKindDefinitionDigestBasisV1(
                    semanticID: semanticID,
                    displayNameLocalizationKey: displayNameLocalizationKey,
                    descriptionLocalizationKey: descriptionLocalizationKey,
                    capabilityIDs: capabilityIDs,
                    compatibleWorkflowPackageReleases: compatibleWorkflowPackageReleases,
                    compatibilityPolicy: compatibilityPolicy
                )
              )) else {
            throw AssetSemanticContractFailureV1.invalidValue
        }
    }
}

struct AssetSemanticCatalogReleaseV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let releaseID: UUID
    let packageRelease: PackageReleaseIdentityV1
    let revision: UInt64
    let definitions: [AssetKindDefinitionV1]
    let releasedAt: Date
    let catalogSHA256: String

    init(
        releaseID: UUID,
        packageRelease: PackageReleaseIdentityV1,
        revision: UInt64,
        definitions: [AssetKindDefinitionV1],
        releasedAt: Date,
        catalogSHA256: String? = nil
    ) throws {
        let orderedDefinitions = definitions.sorted { $0.semanticID < $1.semanticID }
        schemaVersion = Self.schemaVersion
        self.releaseID = releaseID
        self.packageRelease = packageRelease
        self.revision = revision
        self.definitions = orderedDefinitions
        self.releasedAt = releasedAt
        let expectedSHA256 = try AssetSemanticDigestV1.sha256(
            AssetSemanticCatalogDigestBasisV1(
                schemaVersion: Self.schemaVersion,
                releaseID: releaseID,
                packageRelease: packageRelease,
                revision: revision,
                definitions: orderedDefinitions,
                releasedAt: releasedAt
            )
        )
        guard catalogSHA256 == nil || catalogSHA256 == expectedSHA256 else {
            throw AssetSemanticContractFailureV1.nonCanonicalData
        }
        self.catalogSHA256 = expectedSHA256
        try validate()
    }

    var reference: AssetSemanticCatalogReleaseReferenceV1 {
        AssetSemanticCatalogReleaseReferenceV1(
            releaseID: releaseID,
            packageRelease: packageRelease,
            catalogSHA256: catalogSHA256
        )
    }

    func definition(semanticID: String) throws -> AssetKindDefinitionV1 {
        guard let value = definitions.first(where: { $0.semanticID == semanticID }) else {
            throw AssetSemanticContractFailureV1.unknownSemanticID
        }
        return value
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              releaseID != AssetSemanticValidationV1.zeroUUID,
              AssetSemanticValidationV1.validPackageRelease(packageRelease),
              revision > 0,
              releasedAt.timeIntervalSinceReferenceDate.isFinite,
              !definitions.isEmpty,
              definitions.count <= 512,
              definitions == definitions.sorted(by: { $0.semanticID < $1.semanticID }),
              Set(definitions.map(\.semanticID)).count == definitions.count,
              AssetSemanticValidationV1.validSHA256(catalogSHA256),
              catalogSHA256 == (try AssetSemanticDigestV1.sha256(
                AssetSemanticCatalogDigestBasisV1(
                    schemaVersion: schemaVersion,
                    releaseID: releaseID,
                    packageRelease: packageRelease,
                    revision: revision,
                    definitions: definitions,
                    releasedAt: releasedAt
                )
              )) else {
            throw AssetSemanticContractFailureV1.invalidValue
        }
        try definitions.forEach { try $0.validate() }
    }
}

struct AssetKindBindingEventV1: Codable, Equatable, Hashable, Sendable {
    let eventID: UUID
    let workspaceID: WorkspaceID
    let assetID: UUID
    let catalogRelease: AssetSemanticCatalogReleaseReferenceV1
    let semanticID: String
    let predecessorEventID: UUID?
    let revision: UInt64
    let mutationID: MutationIDV1
    let recordedAt: Date
    let eventSHA256: String

    static func canonical(
        eventID: UUID,
        workspaceID: WorkspaceID,
        assetID: UUID,
        catalogRelease: AssetSemanticCatalogReleaseReferenceV1,
        semanticID: String,
        predecessorEventID: UUID?,
        revision: UInt64,
        mutationID: MutationIDV1,
        recordedAt: Date
    ) throws -> Self {
        let basis = AssetKindBindingDigestBasisV1(
            eventID: eventID, workspaceID: workspaceID, assetID: assetID,
            catalogRelease: catalogRelease, semanticID: semanticID,
            predecessorEventID: predecessorEventID, revision: revision,
            mutationID: mutationID, recordedAt: recordedAt
        )
        let value = Self(
            eventID: eventID, workspaceID: workspaceID, assetID: assetID,
            catalogRelease: catalogRelease, semanticID: semanticID,
            predecessorEventID: predecessorEventID, revision: revision,
            mutationID: mutationID, recordedAt: recordedAt,
            eventSHA256: try AssetSemanticDigestV1.sha256(basis)
        )
        try value.validate()
        return value
    }

    func validate(against catalog: AssetSemanticCatalogReleaseV1? = nil) throws {
        try catalogRelease.validate()
        guard eventID != AssetSemanticValidationV1.zeroUUID,
              workspaceID.rawValue != AssetSemanticValidationV1.zeroUUID,
              assetID != AssetSemanticValidationV1.zeroUUID,
              predecessorEventID != AssetSemanticValidationV1.zeroUUID,
              revision > 0,
              recordedAt.timeIntervalSinceReferenceDate.isFinite,
              AssetSemanticValidationV1.validIdentifier(semanticID, maximumBytes: 160),
              predecessorEventID != eventID,
              AssetSemanticValidationV1.validSHA256(eventSHA256),
              eventSHA256 == (try AssetSemanticDigestV1.sha256(
                AssetKindBindingDigestBasisV1(
                    eventID: eventID, workspaceID: workspaceID, assetID: assetID,
                    catalogRelease: catalogRelease, semanticID: semanticID,
                    predecessorEventID: predecessorEventID, revision: revision,
                    mutationID: mutationID, recordedAt: recordedAt
                )
              )) else {
            throw AssetSemanticContractFailureV1.invalidValue
        }
        if let catalog {
            try catalog.validate()
            guard catalog.reference == catalogRelease else {
                throw AssetSemanticContractFailureV1.incompatibleRelease
            }
            _ = try catalog.definition(semanticID: semanticID)
        }
    }
}

enum AssetWorkflowCapabilityBindingDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case bound = "BOUND"
    case ended = "ENDED"
}

struct AssetWorkflowCapabilityBindingEventV1: Codable, Equatable, Hashable, Sendable {
    let eventID: UUID
    let workspaceID: WorkspaceID
    let assetID: UUID
    let kindBindingEventID: UUID
    let kindBindingRevision: UInt64
    let workflowPackageRelease: PackageReleaseIdentityV1
    let capabilityIDs: [AssetSemanticCapabilityIDV1]
    let disposition: AssetWorkflowCapabilityBindingDispositionV1
    let predecessorEventID: UUID?
    let revision: UInt64
    let mutationID: MutationIDV1
    let recordedAt: Date
    let eventSHA256: String

    init(
        eventID: UUID,
        workspaceID: WorkspaceID,
        assetID: UUID,
        kindBindingEventID: UUID,
        kindBindingRevision: UInt64,
        workflowPackageRelease: PackageReleaseIdentityV1,
        capabilityIDs: [AssetSemanticCapabilityIDV1],
        disposition: AssetWorkflowCapabilityBindingDispositionV1,
        predecessorEventID: UUID?,
        revision: UInt64,
        mutationID: MutationIDV1,
        recordedAt: Date,
        eventSHA256: String? = nil
    ) throws {
        let orderedCapabilities = capabilityIDs.sorted()
        self.eventID = eventID
        self.workspaceID = workspaceID
        self.assetID = assetID
        self.kindBindingEventID = kindBindingEventID
        self.kindBindingRevision = kindBindingRevision
        self.workflowPackageRelease = workflowPackageRelease
        self.capabilityIDs = orderedCapabilities
        self.disposition = disposition
        self.predecessorEventID = predecessorEventID
        self.revision = revision
        self.mutationID = mutationID
        self.recordedAt = recordedAt
        let expectedSHA256 = try AssetSemanticDigestV1.sha256(
            AssetWorkflowBindingDigestBasisV1(
                eventID: eventID, workspaceID: workspaceID, assetID: assetID,
                kindBindingEventID: kindBindingEventID,
                kindBindingRevision: kindBindingRevision,
                workflowPackageRelease: workflowPackageRelease,
                capabilityIDs: orderedCapabilities, disposition: disposition,
                predecessorEventID: predecessorEventID, revision: revision,
                mutationID: mutationID, recordedAt: recordedAt
            )
        )
        guard eventSHA256 == nil || eventSHA256 == expectedSHA256 else {
            throw AssetSemanticContractFailureV1.nonCanonicalData
        }
        self.eventSHA256 = expectedSHA256
        try validate()
    }

    func validate() throws {
        guard eventID != AssetSemanticValidationV1.zeroUUID,
              workspaceID.rawValue != AssetSemanticValidationV1.zeroUUID,
              assetID != AssetSemanticValidationV1.zeroUUID,
              kindBindingEventID != AssetSemanticValidationV1.zeroUUID,
              predecessorEventID != AssetSemanticValidationV1.zeroUUID,
              AssetSemanticValidationV1.validPackageRelease(workflowPackageRelease),
              kindBindingRevision > 0,
              revision > 0,
              recordedAt.timeIntervalSinceReferenceDate.isFinite,
              predecessorEventID != eventID,
              capabilityIDs.count <= 64,
              capabilityIDs == capabilityIDs.sorted(),
              Set(capabilityIDs).count == capabilityIDs.count,
              capabilityIDs.allSatisfy({
                  AssetSemanticValidationV1.validIdentifier($0.rawValue, maximumBytes: 120)
              }),
              AssetSemanticValidationV1.validSHA256(eventSHA256),
              eventSHA256 == (try AssetSemanticDigestV1.sha256(
                AssetWorkflowBindingDigestBasisV1(
                    eventID: eventID, workspaceID: workspaceID, assetID: assetID,
                    kindBindingEventID: kindBindingEventID,
                    kindBindingRevision: kindBindingRevision,
                    workflowPackageRelease: workflowPackageRelease,
                    capabilityIDs: capabilityIDs, disposition: disposition,
                    predecessorEventID: predecessorEventID, revision: revision,
                    mutationID: mutationID, recordedAt: recordedAt
                )
              )) else {
            throw AssetSemanticContractFailureV1.invalidValue
        }
    }
}

enum AssetProductIdentifierKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case manufacturer = "MANUFACTURER"
    case model = "MODEL"
    case serial = "SERIAL"
    case lot = "LOT"
    case part = "PART"
    case upcGtin = "UPC_GTIN"
    case externalCode = "EXTERNAL_CODE"
}

enum AssetProductIdentifierProvenanceV1: String, Codable, CaseIterable, Hashable, Sendable {
    case humanRecorded = "HUMAN_RECORDED"
    case importedExternalEvidence = "IMPORTED_EXTERNAL_EVIDENCE"
}

enum AssetProductIdentifierReviewStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case unreviewed = "UNREVIEWED"
    case reviewedAsRecorded = "REVIEWED_AS_RECORDED"
    case duplicateRecorded = "DUPLICATE_RECORDED"
    case unknownRecorded = "UNKNOWN_RECORDED"
}

struct AssetProductIdentifierV1: Codable, Equatable, Hashable, Sendable {
    let kind: AssetProductIdentifierKindV1
    let value: String?
    let normalizedComparisonValue: String?
    let issuer: String?
    let provenance: AssetProductIdentifierProvenanceV1
    let reviewState: AssetProductIdentifierReviewStateV1
    let effectiveFrom: Date
    let effectiveUntil: Date?

    func validate() throws {
        guard value.map({ AssetSemanticValidationV1.validText($0, maximumCharacters: 300) }) ?? true,
              normalizedComparisonValue.map({
                  AssetSemanticValidationV1.validText($0, maximumCharacters: 300)
              }) ?? true,
              issuer.map({ AssetSemanticValidationV1.validText($0, maximumCharacters: 200) }) ?? true,
              (value == nil) == (normalizedComparisonValue == nil),
              (reviewState != .unknownRecorded || value == nil),
              (effectiveUntil.map { $0 >= effectiveFrom } ?? true) else {
            throw AssetSemanticContractFailureV1.invalidValue
        }
    }
}

struct AssetProductIdentityV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let identityID: UUID
    let workspaceID: WorkspaceID
    let assetID: UUID
    let identifiers: [AssetProductIdentifierV1]
    let predecessorIdentityID: UUID?
    let revision: UInt64
    let mutationID: MutationIDV1
    let recordedAt: Date
    let identitySHA256: String

    init(
        identityID: UUID,
        workspaceID: WorkspaceID,
        assetID: UUID,
        identifiers: [AssetProductIdentifierV1],
        predecessorIdentityID: UUID?,
        revision: UInt64,
        mutationID: MutationIDV1,
        recordedAt: Date,
        identitySHA256: String? = nil
    ) throws {
        schemaVersion = Self.schemaVersion
        self.identityID = identityID
        self.workspaceID = workspaceID
        self.assetID = assetID
        self.identifiers = identifiers
        self.predecessorIdentityID = predecessorIdentityID
        self.revision = revision
        self.mutationID = mutationID
        self.recordedAt = recordedAt
        let expectedSHA256 = try AssetSemanticDigestV1.sha256(
            AssetProductIdentityDigestBasisV1(
                schemaVersion: Self.schemaVersion, identityID: identityID,
                workspaceID: workspaceID, assetID: assetID,
                identifiers: identifiers, predecessorIdentityID: predecessorIdentityID,
                revision: revision, mutationID: mutationID, recordedAt: recordedAt
            )
        )
        guard identitySHA256 == nil || identitySHA256 == expectedSHA256 else {
            throw AssetSemanticContractFailureV1.nonCanonicalData
        }
        self.identitySHA256 = expectedSHA256
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              identityID != AssetSemanticValidationV1.zeroUUID,
              workspaceID.rawValue != AssetSemanticValidationV1.zeroUUID,
              assetID != AssetSemanticValidationV1.zeroUUID,
              predecessorIdentityID != AssetSemanticValidationV1.zeroUUID,
              revision > 0,
              recordedAt.timeIntervalSinceReferenceDate.isFinite,
              identifiers.count <= 64,
              predecessorIdentityID != identityID,
              AssetSemanticValidationV1.validSHA256(identitySHA256),
              identitySHA256 == (try AssetSemanticDigestV1.sha256(
                AssetProductIdentityDigestBasisV1(
                    schemaVersion: schemaVersion, identityID: identityID,
                    workspaceID: workspaceID, assetID: assetID,
                    identifiers: identifiers, predecessorIdentityID: predecessorIdentityID,
                    revision: revision, mutationID: mutationID, recordedAt: recordedAt
                )
              )) else {
            throw AssetSemanticContractFailureV1.invalidValue
        }
        try identifiers.forEach { try $0.validate() }
    }
}

struct AssetLifecycleEventRecordV1: Codable, Equatable, Hashable, Sendable {
    let eventID: UUID
    let workspaceID: WorkspaceID
    let assetID: UUID
    let predecessorEventID: UUID?
    let revision: UInt64
    let mutationID: MutationIDV1
    let recordedAt: Date
    let kindBindingEventID: UUID?
    let successorLinkID: UUID?
    let eventSHA256: String

    static func canonical(
        for kind: AssetLifecycleEventKindV1,
        eventID: UUID,
        workspaceID: WorkspaceID,
        assetID: UUID,
        predecessorEventID: UUID?,
        revision: UInt64,
        mutationID: MutationIDV1,
        recordedAt: Date,
        kindBindingEventID: UUID? = nil,
        successorLinkID: UUID? = nil
    ) throws -> Self {
        let basis = AssetLifecycleDigestBasisV1(
            kind: kind, eventID: eventID, workspaceID: workspaceID,
            assetID: assetID, predecessorEventID: predecessorEventID,
            revision: revision, mutationID: mutationID, recordedAt: recordedAt,
            kindBindingEventID: kindBindingEventID, successorLinkID: successorLinkID
        )
        let value = Self(
            eventID: eventID, workspaceID: workspaceID, assetID: assetID,
            predecessorEventID: predecessorEventID, revision: revision,
            mutationID: mutationID, recordedAt: recordedAt,
            kindBindingEventID: kindBindingEventID, successorLinkID: successorLinkID,
            eventSHA256: try AssetSemanticDigestV1.sha256(basis)
        )
        try value.validate(for: kind)
        return value
    }

    func validate(for kind: AssetLifecycleEventKindV1) throws {
        let classificationReferenceIsValid = kind == .classificationChangedRecorded
            ? kindBindingEventID != nil && successorLinkID == nil
            : kindBindingEventID == nil
        let replacementReferenceIsValid = kind == .replacedRecorded
            ? successorLinkID != nil && kindBindingEventID == nil
            : successorLinkID == nil
        guard eventID != AssetSemanticValidationV1.zeroUUID,
              workspaceID.rawValue != AssetSemanticValidationV1.zeroUUID,
              assetID != AssetSemanticValidationV1.zeroUUID,
              predecessorEventID != AssetSemanticValidationV1.zeroUUID,
              kindBindingEventID != AssetSemanticValidationV1.zeroUUID,
              successorLinkID != AssetSemanticValidationV1.zeroUUID,
              revision > 0,
              recordedAt.timeIntervalSinceReferenceDate.isFinite,
              predecessorEventID != eventID,
              classificationReferenceIsValid,
              replacementReferenceIsValid,
              AssetSemanticValidationV1.validSHA256(eventSHA256),
              eventSHA256 == (try AssetSemanticDigestV1.sha256(
                AssetLifecycleDigestBasisV1(
                    kind: kind, eventID: eventID, workspaceID: workspaceID,
                    assetID: assetID, predecessorEventID: predecessorEventID,
                    revision: revision, mutationID: mutationID, recordedAt: recordedAt,
                    kindBindingEventID: kindBindingEventID,
                    successorLinkID: successorLinkID
                )
              )) else {
            throw AssetSemanticContractFailureV1.invalidValue
        }
    }
}

enum AssetLifecycleEventKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case commissioningNotRecorded = "COMMISSIONING_NOT_RECORDED"
    case activeRecorded = "ACTIVE_RECORDED"
    case retiredRecorded = "RETIRED_RECORDED"
    case replacedRecorded = "REPLACED_RECORDED"
    case classificationChangedRecorded = "CLASSIFICATION_CHANGED_RECORDED"
}

enum AssetLifecycleEventV1: Codable, Equatable, Hashable, Sendable {
    case commissioningNotRecorded(AssetLifecycleEventRecordV1)
    case activeRecorded(AssetLifecycleEventRecordV1)
    case retiredRecorded(AssetLifecycleEventRecordV1)
    case replacedRecorded(AssetLifecycleEventRecordV1)
    case classificationChangedRecorded(AssetLifecycleEventRecordV1)

    var kind: AssetLifecycleEventKindV1 {
        switch self {
        case .commissioningNotRecorded: .commissioningNotRecorded
        case .activeRecorded: .activeRecorded
        case .retiredRecorded: .retiredRecorded
        case .replacedRecorded: .replacedRecorded
        case .classificationChangedRecorded: .classificationChangedRecorded
        }
    }

    var record: AssetLifecycleEventRecordV1 {
        switch self {
        case let .commissioningNotRecorded(value), let .activeRecorded(value),
             let .retiredRecorded(value), let .replacedRecorded(value),
             let .classificationChangedRecorded(value): value
        }
    }

    func validate() throws { try record.validate(for: kind) }

    func validateAtomicReference(kindBinding: AssetKindBindingEventV1) throws {
        try validate()
        try kindBinding.validate()
        guard kind == .classificationChangedRecorded,
              record.kindBindingEventID == kindBinding.eventID,
              record.workspaceID == kindBinding.workspaceID,
              record.assetID == kindBinding.assetID,
              record.mutationID == kindBinding.mutationID else {
            throw AssetSemanticContractFailureV1.invalidAtomicReference
        }
    }

    func validateAtomicReference(successorLink: AssetSuccessorLinkV1) throws {
        try validate()
        try successorLink.validate()
        guard kind == .replacedRecorded,
              record.successorLinkID == successorLink.linkID,
              record.workspaceID == successorLink.workspaceID,
              record.assetID == successorLink.predecessorAssetID,
              record.mutationID == successorLink.mutationID else {
            throw AssetSemanticContractFailureV1.invalidAtomicReference
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, record }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try values.decode(AssetLifecycleEventKindV1.self, forKey: .kind)
        let record = try values.decode(AssetLifecycleEventRecordV1.self, forKey: .record)
        switch kind {
        case .commissioningNotRecorded: self = .commissioningNotRecorded(record)
        case .activeRecorded: self = .activeRecorded(record)
        case .retiredRecorded: self = .retiredRecorded(record)
        case .replacedRecorded: self = .replacedRecorded(record)
        case .classificationChangedRecorded: self = .classificationChangedRecorded(record)
        }
        try validate()
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(kind, forKey: .kind)
        try values.encode(record, forKey: .record)
    }
}

struct AssetSuccessorLinkV1: Codable, Equatable, Hashable, Sendable {
    let linkID: UUID
    let workspaceID: WorkspaceID
    let predecessorAssetID: UUID
    let successorAssetID: UUID
    let predecessorLinkID: UUID?
    let revision: UInt64
    let mutationID: MutationIDV1
    let recordedAt: Date
    let linkSHA256: String

    static func canonical(
        linkID: UUID,
        workspaceID: WorkspaceID,
        predecessorAssetID: UUID,
        successorAssetID: UUID,
        predecessorLinkID: UUID?,
        revision: UInt64,
        mutationID: MutationIDV1,
        recordedAt: Date
    ) throws -> Self {
        let basis = AssetSuccessorDigestBasisV1(
            linkID: linkID, workspaceID: workspaceID,
            predecessorAssetID: predecessorAssetID,
            successorAssetID: successorAssetID,
            predecessorLinkID: predecessorLinkID, revision: revision,
            mutationID: mutationID, recordedAt: recordedAt
        )
        let value = Self(
            linkID: linkID, workspaceID: workspaceID,
            predecessorAssetID: predecessorAssetID, successorAssetID: successorAssetID,
            predecessorLinkID: predecessorLinkID, revision: revision,
            mutationID: mutationID, recordedAt: recordedAt,
            linkSHA256: try AssetSemanticDigestV1.sha256(basis)
        )
        try value.validate()
        return value
    }

    func validate() throws {
        guard linkID != AssetSemanticValidationV1.zeroUUID,
              workspaceID.rawValue != AssetSemanticValidationV1.zeroUUID,
              predecessorAssetID != AssetSemanticValidationV1.zeroUUID,
              successorAssetID != AssetSemanticValidationV1.zeroUUID,
              predecessorAssetID != successorAssetID,
              predecessorLinkID != AssetSemanticValidationV1.zeroUUID,
              predecessorLinkID != linkID,
              revision > 0,
              recordedAt.timeIntervalSinceReferenceDate.isFinite,
              AssetSemanticValidationV1.validSHA256(linkSHA256),
              linkSHA256 == (try AssetSemanticDigestV1.sha256(
                AssetSuccessorDigestBasisV1(
                    linkID: linkID, workspaceID: workspaceID,
                    predecessorAssetID: predecessorAssetID,
                    successorAssetID: successorAssetID,
                    predecessorLinkID: predecessorLinkID, revision: revision,
                    mutationID: mutationID, recordedAt: recordedAt
                )
              )) else {
            throw AssetSemanticContractFailureV1.invalidValue
        }
    }

    static func validateAcyclic(_ links: [Self]) throws {
        try links.forEach { try $0.validate() }
        var successors: [UUID: UUID] = [:]
        for link in links {
            guard successors[link.predecessorAssetID] == nil else {
                throw AssetSemanticContractFailureV1.duplicateValue
            }
            successors[link.predecessorAssetID] = link.successorAssetID
        }
        for origin in successors.keys {
            var seen = Set<UUID>()
            var cursor: UUID? = origin
            while let value = cursor {
                guard seen.insert(value).inserted else {
                    throw AssetSemanticContractFailureV1.cycleDetected
                }
                cursor = successors[value]
            }
        }
    }
}

enum WorkSubjectKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case site = "SITE"
    case locationNode = "LOCATION_NODE"
    case asset = "ASSET"
    case compositionComponent = "COMPOSITION_COMPONENT"
    case functionalRelationship = "FUNCTIONAL_RELATIONSHIP"
}

/// C39 freezes the identity and release provenance of a declared functional
/// relationship without defining its endpoint, direction, cardinality, cycle,
/// traversal, or Site policy. Those behaviors remain exclusively C41-owned.
struct FrozenFunctionalRelationshipReferenceV1: Codable, Equatable, Hashable, Sendable {
    let relationshipID: UUID
    let relationshipRevision: UInt64
    let descriptorReleaseID: UUID
    let descriptorReleaseRevision: UInt64
    let packageRelease: PackageReleaseIdentityV1
    let semanticCatalogRelease: AssetSemanticCatalogReleaseReferenceV1
    let semanticID: String

    init(
        relationshipID: UUID,
        relationshipRevision: UInt64,
        descriptorReleaseID: UUID,
        descriptorReleaseRevision: UInt64,
        packageRelease: PackageReleaseIdentityV1,
        semanticCatalogRelease: AssetSemanticCatalogReleaseReferenceV1,
        semanticID: String
    ) {
        self.relationshipID = relationshipID
        self.relationshipRevision = relationshipRevision
        self.descriptorReleaseID = descriptorReleaseID
        self.descriptorReleaseRevision = descriptorReleaseRevision
        self.packageRelease = packageRelease
        self.semanticCatalogRelease = semanticCatalogRelease
        self.semanticID = semanticID
    }

    init(
        event: AssetFunctionalRelationshipEventV1,
        descriptor: FunctionalRelationshipTypeDescriptorV1
    ) throws {
        try event.validate()
        try descriptor.validate()
        guard event.workspaceID == descriptor.workspaceID,
              event.descriptor == FunctionalRelationshipDescriptorReferenceV1(descriptor),
              event.action != .ended else {
            throw AssetSemanticContractFailureV1.invalidAtomicReference
        }
        relationshipID = event.relationshipID
        relationshipRevision = event.revision
        descriptorReleaseID = descriptor.descriptorReleaseID
        descriptorReleaseRevision = descriptor.revision
        packageRelease = descriptor.packageRelease
        semanticCatalogRelease = descriptor.sourceCatalogRelease
        semanticID = descriptor.semanticID
        try validate()
    }

    func validate() throws {
        guard relationshipID != AssetSemanticValidationV1.zeroUUID,
              descriptorReleaseID != AssetSemanticValidationV1.zeroUUID,
              relationshipRevision > 0,
              descriptorReleaseRevision > 0,
              AssetSemanticValidationV1.validIdentifier(semanticID, maximumBytes: 160) else {
            throw AssetSemanticContractFailureV1.invalidValue
        }
        try semanticCatalogRelease.validate()
    }
}

struct WorkSubjectReferenceV1: Codable, Equatable, Hashable, Sendable {
    let kind: WorkSubjectKindV1
    let subjectID: UUID
    let revision: UInt64
    let ownerAssetID: UUID?
    let functionalRelationship: FrozenFunctionalRelationshipReferenceV1?

    init(
        kind: WorkSubjectKindV1,
        subjectID: UUID,
        revision: UInt64,
        ownerAssetID: UUID?,
        functionalRelationship: FrozenFunctionalRelationshipReferenceV1? = nil
    ) {
        self.kind = kind
        self.subjectID = subjectID
        self.revision = revision
        self.ownerAssetID = ownerAssetID
        self.functionalRelationship = functionalRelationship
    }

    func validate() throws {
        let ownerRequired = kind == .compositionComponent
        let relationshipRequired = kind == .functionalRelationship
        guard subjectID != AssetSemanticValidationV1.zeroUUID,
              revision > 0,
              ownerRequired == (ownerAssetID != nil),
              relationshipRequired == (functionalRelationship != nil),
              !relationshipRequired || ownerAssetID == nil else {
            throw AssetSemanticContractFailureV1.invalidValue
        }
        if let ownerAssetID, ownerAssetID == AssetSemanticValidationV1.zeroUUID {
            throw AssetSemanticContractFailureV1.invalidValue
        }
        if let functionalRelationship {
            try functionalRelationship.validate()
            guard functionalRelationship.relationshipID == subjectID,
                  functionalRelationship.relationshipRevision == revision else {
                throw AssetSemanticContractFailureV1.invalidValue
            }
        }
    }
}

struct WorkSubjectSemanticBindingSnapshotV1: Codable, Equatable, Hashable, Sendable {
    let assetID: UUID
    let kindBindingEventID: UUID
    let kindBindingRevision: UInt64
    let catalogRelease: AssetSemanticCatalogReleaseReferenceV1
    let semanticID: String
    let workflowPackageReleases: [PackageReleaseIdentityV1]

    init(
        assetID: UUID,
        kindBindingEventID: UUID,
        kindBindingRevision: UInt64,
        catalogRelease: AssetSemanticCatalogReleaseReferenceV1,
        semanticID: String,
        workflowPackageReleases: [PackageReleaseIdentityV1]
    ) throws {
        self.assetID = assetID
        self.kindBindingEventID = kindBindingEventID
        self.kindBindingRevision = kindBindingRevision
        self.catalogRelease = catalogRelease
        self.semanticID = semanticID
        self.workflowPackageReleases = workflowPackageReleases.sorted()
        try validate()
    }

    func validate() throws {
        try catalogRelease.validate()
        guard kindBindingRevision > 0,
              AssetSemanticValidationV1.validIdentifier(semanticID, maximumBytes: 160),
              workflowPackageReleases.count <= 32,
              workflowPackageReleases == workflowPackageReleases.sorted(),
              Set(workflowPackageReleases).count == workflowPackageReleases.count else {
            throw AssetSemanticContractFailureV1.invalidValue
        }
    }
}

struct WorkSubjectScopeSnapshotV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let snapshotID: UUID
    let workspaceID: WorkspaceID
    let siteID: UUID
    let subjects: [WorkSubjectReferenceV1]
    let semanticBindings: [WorkSubjectSemanticBindingSnapshotV1]
    let workspaceRevision: UInt64
    let recordedAt: Date
    let snapshotSHA256: String

    init(
        snapshotID: UUID,
        workspaceID: WorkspaceID,
        siteID: UUID,
        subjects: [WorkSubjectReferenceV1],
        semanticBindings: [WorkSubjectSemanticBindingSnapshotV1],
        workspaceRevision: UInt64,
        recordedAt: Date,
        snapshotSHA256: String? = nil
    ) throws {
        let orderedSubjects = subjects.sorted {
            ($0.kind.rawValue, $0.subjectID.uuidString) < ($1.kind.rawValue, $1.subjectID.uuidString)
        }
        let orderedSemanticBindings = semanticBindings.sorted {
            $0.assetID.uuidString < $1.assetID.uuidString
        }
        schemaVersion = Self.schemaVersion
        self.snapshotID = snapshotID
        self.workspaceID = workspaceID
        self.siteID = siteID
        self.subjects = orderedSubjects
        self.semanticBindings = orderedSemanticBindings
        self.workspaceRevision = workspaceRevision
        self.recordedAt = recordedAt
        let expectedSHA256 = try AssetSemanticDigestV1.sha256(
            WorkSubjectScopeDigestBasisV1(
                schemaVersion: Self.schemaVersion, snapshotID: snapshotID,
                workspaceID: workspaceID, siteID: siteID, subjects: orderedSubjects,
                semanticBindings: orderedSemanticBindings,
                workspaceRevision: workspaceRevision, recordedAt: recordedAt
            )
        )
        guard snapshotSHA256 == nil || snapshotSHA256 == expectedSHA256 else {
            throw AssetSemanticContractFailureV1.nonCanonicalData
        }
        self.snapshotSHA256 = expectedSHA256
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              snapshotID != AssetSemanticValidationV1.zeroUUID,
              workspaceID.rawValue != AssetSemanticValidationV1.zeroUUID,
              siteID != AssetSemanticValidationV1.zeroUUID,
              workspaceRevision > 0,
              recordedAt.timeIntervalSinceReferenceDate.isFinite,
              !subjects.isEmpty,
              subjects.count <= 1_024,
              semanticBindings.count <= 1_024,
              Set(subjects.map { "\($0.kind.rawValue):\($0.subjectID.uuidString)" }).count
                == subjects.count,
              Set(semanticBindings.map(\.assetID)).count == semanticBindings.count,
              AssetSemanticValidationV1.validSHA256(snapshotSHA256),
              snapshotSHA256 == (try AssetSemanticDigestV1.sha256(
                WorkSubjectScopeDigestBasisV1(
                    schemaVersion: schemaVersion, snapshotID: snapshotID,
                    workspaceID: workspaceID, siteID: siteID, subjects: subjects,
                    semanticBindings: semanticBindings,
                    workspaceRevision: workspaceRevision, recordedAt: recordedAt
                )
              )) else {
            throw AssetSemanticContractFailureV1.invalidValue
        }
        try subjects.forEach { try $0.validate() }
        try semanticBindings.forEach { try $0.validate() }
        let scopedAssets = Set(subjects.compactMap { subject -> UUID? in
            if subject.kind == .asset { return subject.subjectID }
            return subject.ownerAssetID
        })
        guard Set(semanticBindings.map(\.assetID)).isSubset(of: scopedAssets) else {
            throw AssetSemanticContractFailureV1.invalidValue
        }
    }
}

extension WorkSubjectScopeSnapshotV1 {
    func validateAuthorityAssessmentScope(
        workspaceID: WorkspaceID,
        siteID: UUID,
        packageReleases: [PackageReleaseIdentityV1]
    ) throws {
        try validate()
        guard self.workspaceID == workspaceID,
              self.siteID == siteID,
              packageReleases == packageReleases.sorted(),
              Set(packageReleases).count == packageReleases.count else {
            throw AssetSemanticContractFailureV1.incompatibleRelease
        }
        let frozenPackages = Set(semanticBindings.flatMap(\.workflowPackageReleases))
        guard Set(packageReleases).isSubset(of: frozenPackages) else {
            throw AssetSemanticContractFailureV1.incompatibleRelease
        }
    }

    func validateFunctionalRelationshipSnapshot(
        _ snapshot: CompletedFunctionalRelationshipSnapshotV1
    ) throws {
        try validate()
        try snapshot.validate()
        guard snapshot.workspaceID == workspaceID else {
            throw AssetSemanticContractFailureV1.crossWorkspaceReference
        }
        let frozen = Set(snapshot.frozenReferences)
        let scoped = subjects.compactMap(\.functionalRelationship)
        guard !scoped.isEmpty,
              Set(scoped).count == scoped.count,
              Set(scoped).isSubset(of: frozen) else {
            throw AssetSemanticContractFailureV1.invalidAtomicReference
        }
    }
}

enum AssetSemanticCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= 8_388_608 else {
            throw AssetSemanticContractFailureV1.invalidValue
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        switch value {
        case let value as AssetSemanticCatalogReleaseReferenceV1:
            try value.validate()
        case let value as AssetKindDefinitionV1:
            try value.validate()
        case let value as AssetSemanticCatalogReleaseV1:
            try value.validate()
        case let value as AssetKindBindingEventV1:
            try value.validate()
        case let value as AssetWorkflowCapabilityBindingEventV1:
            try value.validate()
        case let value as AssetProductIdentifierV1:
            try value.validate()
        case let value as AssetProductIdentityV1:
            try value.validate()
        case let value as AssetLifecycleEventV1:
            try value.validate()
        case let value as AssetSuccessorLinkV1:
            try value.validate()
        case let value as FrozenFunctionalRelationshipReferenceV1:
            try value.validate()
        case let value as WorkSubjectReferenceV1:
            try value.validate()
        case let value as WorkSubjectSemanticBindingSnapshotV1:
            try value.validate()
        case let value as WorkSubjectScopeSnapshotV1:
            try value.validate()
        default:
            break
        }
        guard try encode(value) == data else {
            throw AssetSemanticContractFailureV1.nonCanonicalData
        }
        return value
    }
}

enum AssetSemanticValidationV1 {
    static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )

    static func validIdentifier(_ value: String, maximumBytes: Int) -> Bool {
        guard !value.isEmpty, value.utf8.count <= maximumBytes,
              value == value.lowercased(),
              value == value.precomposedStringWithCanonicalMapping else { return false }
        return value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x7A).contains($0)
                || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F
        }
    }

    static func validPackageRelease(_ value: PackageReleaseIdentityV1) -> Bool {
        !value.packageID.isEmpty
            && value.packageID == value.packageID.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.schemaVersion > 0
            && value.contentVersion > 0
    }

    static func validLocalizationKey(_ value: String) -> Bool {
        validIdentifier(value, maximumBytes: 240)
    }

    static func validText(_ value: String, maximumCharacters: Int) -> Bool {
        value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.isEmpty && value.count <= maximumCharacters
            && value == value.precomposedStringWithCanonicalMapping
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    static func validSHA256(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }
}

extension AssetKindBindingEventV1 {
    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        let basis = AssetKindBindingDigestBasisV1(
            eventID: eventID, workspaceID: workspaceID, assetID: assetID,
            catalogRelease: catalogRelease, semanticID: semanticID,
            predecessorEventID: predecessorEventID, revision: revision,
            mutationID: mutationID, recordedAt: recordedAt
        )
        return Self(
            eventID: eventID, workspaceID: workspaceID, assetID: assetID,
            catalogRelease: catalogRelease, semanticID: semanticID,
            predecessorEventID: predecessorEventID, revision: revision,
            mutationID: mutationID, recordedAt: recordedAt,
            eventSHA256: try AssetSemanticDigestV1.sha256(basis)
        )
    }
}

extension AssetWorkflowCapabilityBindingEventV1 {
    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        let basis = AssetWorkflowBindingDigestBasisV1(
            eventID: eventID, workspaceID: workspaceID, assetID: assetID,
            kindBindingEventID: kindBindingEventID, kindBindingRevision: kindBindingRevision,
            workflowPackageRelease: workflowPackageRelease, capabilityIDs: capabilityIDs,
            disposition: disposition, predecessorEventID: predecessorEventID,
            revision: revision, mutationID: mutationID, recordedAt: recordedAt
        )
        return try Self(
            eventID: eventID, workspaceID: workspaceID, assetID: assetID,
            kindBindingEventID: kindBindingEventID, kindBindingRevision: kindBindingRevision,
            workflowPackageRelease: workflowPackageRelease, capabilityIDs: capabilityIDs,
            disposition: disposition, predecessorEventID: predecessorEventID,
            revision: revision, mutationID: mutationID, recordedAt: recordedAt,
            eventSHA256: try AssetSemanticDigestV1.sha256(basis)
        )
    }
}

extension AssetProductIdentityV1 {
    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        let basis = AssetProductIdentityDigestBasisV1(
            schemaVersion: schemaVersion, identityID: identityID, workspaceID: workspaceID,
            assetID: assetID, identifiers: identifiers,
            predecessorIdentityID: predecessorIdentityID, revision: revision,
            mutationID: mutationID, recordedAt: recordedAt
        )
        return try Self(
            identityID: identityID, workspaceID: workspaceID, assetID: assetID,
            identifiers: identifiers, predecessorIdentityID: predecessorIdentityID,
            revision: revision, mutationID: mutationID, recordedAt: recordedAt,
            identitySHA256: try AssetSemanticDigestV1.sha256(basis)
        )
    }
}

extension AssetLifecycleEventV1 {
    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        let prior = record
        let basis = AssetLifecycleDigestBasisV1(
            kind: kind, eventID: prior.eventID, workspaceID: workspaceID,
            assetID: prior.assetID, predecessorEventID: prior.predecessorEventID,
            revision: prior.revision, mutationID: prior.mutationID,
            recordedAt: prior.recordedAt, kindBindingEventID: prior.kindBindingEventID,
            successorLinkID: prior.successorLinkID
        )
        let rebound = AssetLifecycleEventRecordV1(
            eventID: prior.eventID, workspaceID: workspaceID, assetID: prior.assetID,
            predecessorEventID: prior.predecessorEventID, revision: prior.revision,
            mutationID: prior.mutationID, recordedAt: prior.recordedAt,
            kindBindingEventID: prior.kindBindingEventID,
            successorLinkID: prior.successorLinkID,
            eventSHA256: try AssetSemanticDigestV1.sha256(basis)
        )
        switch kind {
        case .commissioningNotRecorded: return .commissioningNotRecorded(rebound)
        case .activeRecorded: return .activeRecorded(rebound)
        case .retiredRecorded: return .retiredRecorded(rebound)
        case .replacedRecorded: return .replacedRecorded(rebound)
        case .classificationChangedRecorded: return .classificationChangedRecorded(rebound)
        }
    }
}

extension AssetSuccessorLinkV1 {
    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        let basis = AssetSuccessorDigestBasisV1(
            linkID: linkID, workspaceID: workspaceID,
            predecessorAssetID: predecessorAssetID, successorAssetID: successorAssetID,
            predecessorLinkID: predecessorLinkID, revision: revision,
            mutationID: mutationID, recordedAt: recordedAt
        )
        return Self(
            linkID: linkID, workspaceID: workspaceID,
            predecessorAssetID: predecessorAssetID, successorAssetID: successorAssetID,
            predecessorLinkID: predecessorLinkID, revision: revision,
            mutationID: mutationID, recordedAt: recordedAt,
            linkSHA256: try AssetSemanticDigestV1.sha256(basis)
        )
    }
}

extension WorkSubjectScopeSnapshotV1 {
    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        let basis = WorkSubjectScopeDigestBasisV1(
            schemaVersion: schemaVersion, snapshotID: snapshotID,
            workspaceID: workspaceID, siteID: siteID, subjects: subjects,
            semanticBindings: semanticBindings, workspaceRevision: workspaceRevision,
            recordedAt: recordedAt
        )
        return try Self(
            snapshotID: snapshotID, workspaceID: workspaceID, siteID: siteID,
            subjects: subjects, semanticBindings: semanticBindings,
            workspaceRevision: workspaceRevision, recordedAt: recordedAt,
            snapshotSHA256: try AssetSemanticDigestV1.sha256(basis)
        )
    }
}

private enum AssetSemanticDigestV1 {
    static func sha256<T: Encodable>(_ value: T) throws -> String {
        try WorkspaceMutationCanonicalV1.sha256(value)
    }
}

private struct AssetKindDefinitionDigestBasisV1: Codable {
    let semanticID: String
    let displayNameLocalizationKey: String
    let descriptionLocalizationKey: String?
    let capabilityIDs: [AssetSemanticCapabilityIDV1]
    let compatibleWorkflowPackageReleases: [PackageReleaseIdentityV1]
    let compatibilityPolicy: AssetSemanticCompatibilityPolicyV1
}

private struct AssetSemanticCatalogDigestBasisV1: Codable {
    let schemaVersion: Int
    let releaseID: UUID
    let packageRelease: PackageReleaseIdentityV1
    let revision: UInt64
    let definitions: [AssetKindDefinitionV1]
    let releasedAt: Date
}

private struct AssetKindBindingDigestBasisV1: Codable {
    let eventID: UUID; let workspaceID: WorkspaceID; let assetID: UUID
    let catalogRelease: AssetSemanticCatalogReleaseReferenceV1; let semanticID: String
    let predecessorEventID: UUID?; let revision: UInt64; let mutationID: MutationIDV1; let recordedAt: Date
}
private struct AssetWorkflowBindingDigestBasisV1: Codable {
    let eventID: UUID; let workspaceID: WorkspaceID; let assetID: UUID
    let kindBindingEventID: UUID; let kindBindingRevision: UInt64
    let workflowPackageRelease: PackageReleaseIdentityV1
    let capabilityIDs: [AssetSemanticCapabilityIDV1]
    let disposition: AssetWorkflowCapabilityBindingDispositionV1
    let predecessorEventID: UUID?; let revision: UInt64; let mutationID: MutationIDV1; let recordedAt: Date
}
private struct AssetProductIdentityDigestBasisV1: Codable {
    let schemaVersion: Int; let identityID: UUID; let workspaceID: WorkspaceID; let assetID: UUID
    let identifiers: [AssetProductIdentifierV1]; let predecessorIdentityID: UUID?
    let revision: UInt64; let mutationID: MutationIDV1; let recordedAt: Date
}
private struct AssetLifecycleDigestBasisV1: Codable {
    let kind: AssetLifecycleEventKindV1; let eventID: UUID; let workspaceID: WorkspaceID; let assetID: UUID
    let predecessorEventID: UUID?; let revision: UInt64; let mutationID: MutationIDV1; let recordedAt: Date
    let kindBindingEventID: UUID?; let successorLinkID: UUID?
}
private struct AssetSuccessorDigestBasisV1: Codable {
    let linkID: UUID; let workspaceID: WorkspaceID; let predecessorAssetID: UUID; let successorAssetID: UUID
    let predecessorLinkID: UUID?; let revision: UInt64; let mutationID: MutationIDV1; let recordedAt: Date
}
private struct WorkSubjectScopeDigestBasisV1: Codable {
    let schemaVersion: Int; let snapshotID: UUID; let workspaceID: WorkspaceID; let siteID: UUID
    let subjects: [WorkSubjectReferenceV1]
    let semanticBindings: [WorkSubjectSemanticBindingSnapshotV1]
    let workspaceRevision: UInt64; let recordedAt: Date
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_AssetSemantics_AssetSemanticContractsV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_AssetSemantics_AssetSemanticContractsV1_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Domain_AssetSemantics_AssetSemanticContractsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/AssetSemantics/AssetSemanticContractsV1.swift", role: .asset)
}

// MARK: - C31 lighting asset-semantic consumer boundary

enum C31LightingAssetSemanticConsumerBoundaryV1 {
    static let topologyUsesCanonicalAssetIdentity = true
    static let displayUsesLocalizedLabels = true
    static let privateLocatorsAndActorIdentityExcluded = true
    static let operationalClaimsExcluded = true

    static func assetIDs(
        from system: LightingSystemV1
    ) throws -> [UUID] {
        try system.validateIntrinsic()
        return system.luminaires.map(\.assetID).sorted {
            $0.uuidString < $1.uuidString
        }
    }
}
// MARK: - C32 assistance asset semantics boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_AssetSemantics_AssetSemanticContractsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let acceptedEffectRebindsToCanonicalAssetSemantics = true

    static func validateProposal(_ proposal: AssistanceProposalV1, in context: AssistanceProposalEvaluationContextV1) throws {
        try proposal.validate()
        try context.validate()
        guard proposal.verificationState.rawValue == AssistanceProposalVerificationStateV1.unverified.rawValue,
              context.policy.manualFallback == .typeManually else {
            throw AssistanceContractFailureV1.incompatibleCapability
        }
        if let reason = try proposal.expiryReason(in: context) {
            throw AssistanceContractFailureV1.expired(reason)
        }
    }

    static func validateAcceptanceReceipt(_ receipt: AssistanceAcceptanceReceiptV1) throws {
        try receipt.validate()
    }
}

enum C33TemporalEvidenceBoundary_Domain_AssetSemantics_AssetSemanticContractsV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}
