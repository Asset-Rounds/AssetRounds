import Foundation

enum ContentContractPublicationBoundaryV1: String, CaseIterable, Sendable {
    case beforeValidation = "BEFORE_VALIDATION"
    case afterValidationBeforePublication = "AFTER_VALIDATION_BEFORE_PUBLICATION"
    case afterPublicationBeforeReceipt = "AFTER_PUBLICATION_BEFORE_RECEIPT"
}

struct ContentContractRegistryV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let persistentContractSchema = "KERNEL_MEDIA_V1"
    static let downgradeDisposition = "DORMANT_REVERT_ALLOWED"

    let schemaVersion: Int
    let persistentContractSchema: String
    let downgradeDisposition: String
    let declaredContracts: [String]

    init(declaredContracts: [String]) throws {
        let expected = [
            "ContentReferenceV1",
            "ContentLocatorV1",
            "ContentManifestV1",
            "EvidenceAssociationV1",
            "ContentDerivativeProvenanceV1",
            "LocalContentStoreV1",
        ]
        guard declaredContracts == expected else { throw ContentContractFailureV1.invalidValue }
        schemaVersion = Self.schemaVersion
        persistentContractSchema = Self.persistentContractSchema
        downgradeDisposition = Self.downgradeDisposition
        self.declaredContracts = declaredContracts
    }

    static func canonical() throws -> ContentContractRegistryV1 {
        try .init(declaredContracts: [
            "ContentReferenceV1",
            "ContentLocatorV1",
            "ContentManifestV1",
            "EvidenceAssociationV1",
            "ContentDerivativeProvenanceV1",
            "LocalContentStoreV1",
        ])
    }
}

struct ContentContractRegistryReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let registrySHA256: String
    let publicationState: String
    let nativeCompileRan: Bool
    let hostedDispatchRan: Bool
    let acceptanceCredit: Bool
    let releaseCredit: Bool
    let requiresAcceptedS10_6Reconciliation: Bool

    fileprivate init(registrySHA256: String) throws {
        guard KernelCanonicalHashV1.validSHA256(registrySHA256) else {
            throw ContentContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.registrySHA256 = registrySHA256
        publicationState = "COMPLETE"
        nativeCompileRan = false
        hostedDispatchRan = false
        acceptanceCredit = false
        releaseCredit = false
        requiresAcceptedS10_6Reconciliation = true
    }
}

enum ContentContractRegistryPublicationV1: Equatable, Sendable {
    case zero
    case complete(registry: ContentContractRegistryV1, receipt: ContentContractRegistryReceiptV1)
}

enum ContentContractRegistryCanonicalCodecV1 {
    static func encode(_ registry: ContentContractRegistryV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(registry)
        guard !data.isEmpty, data.count <= ContentContractLimitsV1.maximumCanonicalBytes else {
            throw ContentContractFailureV1.limitExceeded
        }
        return data
    }

    static func decode(_ data: Data) throws -> ContentContractRegistryV1 {
        guard !data.isEmpty, data.count <= ContentContractLimitsV1.maximumCanonicalBytes else {
            throw ContentContractFailureV1.limitExceeded
        }
        let registry = try JSONDecoder().decode(ContentContractRegistryV1.self, from: data)
        guard try encode(registry) == data else { throw ContentContractFailureV1.digestMismatch }
        return registry
    }
}

enum ContentContractRegistryPublisherV1 {
    static func publish(
        recoveringFrom boundary: ContentContractPublicationBoundaryV1?
    ) throws -> ContentContractRegistryPublicationV1 {
        switch boundary {
        case .beforeValidation, .afterValidationBeforePublication:
            return .zero
        case .afterPublicationBeforeReceipt, .none:
            let registry = try ContentContractRegistryV1.canonical()
            let canonicalBytes = try ContentContractRegistryCanonicalCodecV1.encode(registry)
            return .complete(
                registry: registry,
                receipt: try .init(registrySHA256: KernelCanonicalHashV1.sha256(canonicalBytes))
            )
        }
    }

    static func recover(
        canonicalData: Data?,
        receipt: ContentContractRegistryReceiptV1?
    ) throws -> ContentContractRegistryV1? {
        switch (canonicalData, receipt) {
        case (nil, nil):
            return nil
        case (.some(let data), .some(let receipt)):
            guard receipt.registrySHA256 == KernelCanonicalHashV1.sha256(data) else {
                throw ContentContractFailureV1.digestMismatch
            }
            return try ContentContractRegistryCanonicalCodecV1.decode(data)
        default:
            throw ContentIntegrityFailureV1.partialEffect
        }
    }
}

extension ContentContractRegistryV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, persistentContractSchema, downgradeDisposition, declaredContracts
    }

    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try c.decode(String.self, forKey: .persistentContractSchema) == Self.persistentContractSchema,
              try c.decode(String.self, forKey: .downgradeDisposition) == Self.downgradeDisposition else {
            throw ContentContractFailureV1.incompatibleVersion
        }
        try self.init(declaredContracts: c.decode([String].self, forKey: .declaredContracts))
    }
}


// C20 is additive. Keeping this separate preserves the immutable C05 registry
// receipt while publishing the privacy-transform contract family explicitly.
extension ContentContractRegistryV1 {
    static let c20PrivacyTransformContracts: [String] = [
        "PrivacyTransformPolicyV1",
        "PrivacyCoordinateSpaceV1",
        "PrivacyImageOrientationV1",
        "PrivacyCoordinateScaleV1",
        "PrivacyIntegerRectV1",
        "PrivacyRegionV1",
        "PrivacyTransformManifestV1",
        "PrivacyReviewReceiptV1",
        "PrivacyTransformPublicationAuthorityV1",
        "ExistingContentStorePrivacyDerivativeWriterV1",
        "WorkspacePrivacyTransformPublicationAuthorityV1",
    ]

    static func c20BoundaryContracts() throws -> [String] {
        let registry = try canonical()
        return registry.declaredContracts + c20PrivacyTransformContracts
    }
}

extension ContentContractRegistryReceiptV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, registrySHA256, publicationState, nativeCompileRan, hostedDispatchRan
        case acceptanceCredit, releaseCredit, requiresAcceptedS10_6Reconciliation
    }

    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try c.decode(String.self, forKey: .publicationState) == "COMPLETE",
              try c.decode(Bool.self, forKey: .nativeCompileRan) == false,
              try c.decode(Bool.self, forKey: .hostedDispatchRan) == false,
              try c.decode(Bool.self, forKey: .acceptanceCredit) == false,
              try c.decode(Bool.self, forKey: .releaseCredit) == false,
              try c.decode(Bool.self, forKey: .requiresAcceptedS10_6Reconciliation) else {
            throw ContentContractFailureV1.incompatibleVersion
        }
        try self.init(registrySHA256: c.decode(String.self, forKey: .registrySHA256))
    }
}

// MARK: - C36 contract registration

extension ContentContractRegistryV1 {
    /// C36 is additive to the C05 content contract.  These names describe
    /// device-local staging/reservation boundaries and do not claim a second
    /// canonical content store.
    static let c36StagingContracts: [String] = [
        "AttachmentStagingItemV1",
        "DraftAttachmentStagingAdapterV1",
        "DraftContentReservationV1",
        "DraftContentPromotionPortV1",
    ]

    static func c36BoundaryContracts() throws -> [String] {
        let registry = try canonical()
        return registry.declaredContracts + c36StagingContracts
    }

    static func validateC36Reservation(
        _ reservation: DraftContentReservationV1,
        reference: ContentReferenceV1
    ) throws {
        try ContentIntegrityV1.validateDraftReservation(
            reservation,
            reference: reference
        )
    }
}
