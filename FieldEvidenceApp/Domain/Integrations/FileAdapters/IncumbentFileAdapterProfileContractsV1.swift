import Foundation

enum IncumbentFileContractFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case invalidDigest
    case unsupportedVersion
    case headerMismatch
    case budgetExceeded
    case fieldNotAllowed
    case privacyApprovalRequired
    case noSelectedProfile
    case multipleSelectedProfiles
    case staleSelection
    case quarantined
    case divergentRecovery
}

enum IncumbentFileContractV1 {
    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func requireID(_ value: UUID) throws {
        guard value != zeroUUID else { throw IncumbentFileContractFailureV1.invalidValue }
    }

    static func requireDigest(_ value: String) throws {
        guard MutationEnvelopeV1.isSHA256(value), value == value.lowercased() else {
            throw IncumbentFileContractFailureV1.invalidDigest
        }
    }

    static func requireToken(_ value: String, maximumBytes: Int = 160) throws {
        guard !value.isEmpty, value.utf8.count <= maximumBytes,
              value.unicodeScalars.allSatisfy({
                  $0.value >= 0x21 && $0.value <= 0x7e
                    && ![0x22, 0x27, 0x5c].contains($0.value)
              }) else { throw IncumbentFileContractFailureV1.invalidValue }
    }

    static func requireText(_ value: String, maximumBytes: Int = 1_024) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.utf8.count <= maximumBytes,
              value.unicodeScalars.allSatisfy({
                  $0.value >= 0x20 && $0.value != 0x7f
                    && ![0x202a, 0x202b, 0x202c, 0x202d, 0x202e,
                         0x2066, 0x2067, 0x2068, 0x2069].contains($0.value)
              }) else { throw IncumbentFileContractFailureV1.invalidValue }
    }

    static func digest<T: Encodable>(_ value: T) throws -> String {
        try WorkspaceMutationCanonicalV1.sha256(value)
    }
}

enum IncumbentFileDirectionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case importOnly = "IMPORT_ONLY"
    case exportOnly = "EXPORT_ONLY"
    case bidirectionalFiles = "BIDIRECTIONAL_FILES"

    var permitsImport: Bool { self != .exportOnly }
    var permitsExport: Bool { self != .importOnly }
}

enum IncumbentFileEncodingV1: String, Codable, CaseIterable, Hashable, Sendable {
    case utf8 = "UTF_8"
}

enum IncumbentFileDelimiterV1: String, Codable, CaseIterable, Hashable, Sendable {
    case comma = "COMMA"
    case tab = "TAB"
    case semicolon = "SEMICOLON"

    var scalar: UnicodeScalar {
        switch self {
        case .comma: return ","
        case .tab: return "\t"
        case .semicolon: return ";"
        }
    }
}

enum IncumbentExternalKeyPolicyV1: String, Codable, CaseIterable, Hashable, Sendable {
    case exactOpaqueStableKey = "EXACT_OPAQUE_STABLE_KEY"
    case userResolvedBinding = "USER_RESOLVED_BINDING"
}

enum IncumbentTimeZonePolicyV1: String, Codable, CaseIterable, Hashable, Sendable {
    case explicitIANAColumn = "EXPLICIT_IANA_COLUMN"
    case frozenWorkspaceTimeZone = "FROZEN_WORKSPACE_TIME_ZONE"
    case noTemporalFields = "NO_TEMPORAL_FIELDS"
}

enum IncumbentFileFieldClassV1: String, Codable, CaseIterable, Hashable, Sendable {
    case ordinary = "ORDINARY"
    case contact = "CONTACT"
    case evidence = "EVIDENCE"
    case media = "MEDIA"
    case qualification = "QUALIFICATION"
    case directCost = "DIRECT_COST"

    var requiresExplicitPrivacyApproval: Bool { self != .ordinary }
}

/// The only canonical values C50 may expose to a provider codec. These are
/// derived, customer-safe projections owned by C48/C49, never canonical rows.
enum IncumbentCanonicalFieldV1: String, Codable, CaseIterable, Hashable, Sendable {
    case fileFormatVersion = "file.formatVersion"
    case portableReviewPublicID = "portableReview.publicID"
    case portableReviewState = "portableReview.state"
    case portableReviewLatestResponsePublicID = "portableReview.latestResponsePublicID"
    case workDurationMinutes = "workResource.durationMinutes"
    case workMaterialLineCount = "workResource.materialLineCount"
    case workMaterialTotals = "workResource.materialTotals"

    var fieldClass: IncumbentFileFieldClassV1 { .ordinary }
    var requiresExplicitPrivacyApproval: Bool { self != .fileFormatVersion }
}

enum IncumbentAdapterProjectionKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case portableReview = "PORTABLE_REVIEW"
    case workResource = "WORK_RESOURCE"

    private var permittedCanonicalFields: Set<IncumbentCanonicalFieldV1> {
        switch self {
        case .portableReview:
            return [
                .fileFormatVersion,
                .portableReviewPublicID,
                .portableReviewState,
                .portableReviewLatestResponsePublicID,
            ]
        case .workResource:
            return [
                .fileFormatVersion,
                .workDurationMinutes,
                .workMaterialLineCount,
                .workMaterialTotals,
            ]
        }
    }

    func validate(allowedCanonicalFields: [IncumbentCanonicalFieldV1]) throws {
        guard !allowedCanonicalFields.isEmpty,
              allowedCanonicalFields == allowedCanonicalFields.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(allowedCanonicalFields).count == allowedCanonicalFields.count,
              allowedCanonicalFields.contains(.fileFormatVersion),
              allowedCanonicalFields.allSatisfy(permittedCanonicalFields.contains) else {
            throw IncumbentFileContractFailureV1.fieldNotAllowed
        }
    }
}

struct IncumbentCanonicalProjectionValueV1: Codable, Equatable, Hashable, Sendable {
    let canonicalField: IncumbentCanonicalFieldV1
    let canonicalValue: String?
}

struct IncumbentAdapterWorkspaceFrontierV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let workspaceRevision: UInt64

    init(workspaceID: WorkspaceID, workspaceRevision: UInt64) throws {
        guard workspaceRevision > 0 else {
            throw IncumbentFileContractFailureV1.privacyApprovalRequired
        }
        self.workspaceID = workspaceID
        self.workspaceRevision = workspaceRevision
    }
}

/// A closed, typed projection payload. Its canonical value digest is computed
/// from the actual C48/C49 value, never accepted from a caller.
enum IncumbentAdapterProjectionPayloadV1: Codable, Equatable, Sendable {
    case portableReview(C50PortableReviewAdapterProjectionV1)
    case workResource(C50WorkResourceAdapterProjectionV1)

    var projectionKind: IncumbentAdapterProjectionKindV1 {
        switch self {
        case .portableReview: return .portableReview
        case .workResource: return .workResource
        }
    }

    var privacyPreviewApproval: C50PrivacyPreviewApprovalReferenceV1 {
        switch self {
        case let .portableReview(value): return value.privacyApproval
        case let .workResource(value): return value.privacyApproval
        }
    }

    var workspaceID: WorkspaceID { privacyPreviewApproval.workspaceID }

    func validate() throws {
        try privacyPreviewApproval.requireAuthoritativelyBound()
        switch self {
        case let .portableReview(value):
            try C50PortableReviewAdapterDelegationV1.validate(value)
        case let .workResource(value):
            try C50WorkResourceAdapterDelegationV1.validate(value)
        }
    }

    func canonicalProjectionValues() throws -> [IncumbentCanonicalProjectionValueV1] {
        func canonical<T: Encodable>(_ value: T) throws -> String {
            let data = try WorkspaceMutationCanonicalV1.data(value)
            guard let text = String(data: data, encoding: .utf8) else {
                throw IncumbentFileContractFailureV1.invalidValue
            }
            return text
        }
        switch self {
        case let .portableReview(value):
            return [
                IncumbentCanonicalProjectionValueV1(
                    canonicalField: .portableReviewPublicID,
                    canonicalValue: value.requestPublicID.rawValue
                ),
                IncumbentCanonicalProjectionValueV1(
                    canonicalField: .portableReviewState,
                    canonicalValue: value.state.rawValue
                ),
                IncumbentCanonicalProjectionValueV1(
                    canonicalField: .portableReviewLatestResponsePublicID,
                    canonicalValue: value.latestResponsePublicID
                ),
            ].sorted(by: { $0.canonicalField.rawValue < $1.canonicalField.rawValue })
        case let .workResource(value):
            return try [
                IncumbentCanonicalProjectionValueV1(
                    canonicalField: .workDurationMinutes,
                    canonicalValue: String(value.durationMinutes)
                ),
                IncumbentCanonicalProjectionValueV1(
                    canonicalField: .workMaterialLineCount,
                    canonicalValue: String(value.materialLineCount)
                ),
                IncumbentCanonicalProjectionValueV1(
                    canonicalField: .workMaterialTotals,
                    canonicalValue: canonical(value.materialTotals)
                ),
            ].sorted(by: { $0.canonicalField.rawValue < $1.canonicalField.rawValue })
        }
    }

    func canonicalProjectionSHA256() throws -> String {
        try IncumbentFileContractV1.digest(canonicalProjectionValues())
    }
}

/// Integrations-owned approval for one exact adapter projection. The Content
/// contract continues to approve only the privacy derivative; this wrapper
/// binds that approval to the actual projection value, a closed projection
/// kind, an exact workspace frontier, and an exact canonical-field allowlist
/// without introducing a Content-to-Integrations dependency.
struct IncumbentPrivacyApprovalReferenceV1: Codable, Equatable, Hashable, Sendable {
    private enum AuthorityBindingV1: Equatable, Sendable { case bound, unbound }

    static let schemaVersion = 1
    let schemaVersion: Int
    let privacyPreviewApproval: C50PrivacyPreviewApprovalReferenceV1
    let projectionKind: IncumbentAdapterProjectionKindV1
    let allowedCanonicalFields: [IncumbentCanonicalFieldV1]
    let workspaceFrontier: IncumbentAdapterWorkspaceFrontierV1
    let canonicalProjectionValues: [IncumbentCanonicalProjectionValueV1]
    let canonicalProjectionSHA256: String
    let bindingSHA256: String
    private let authorityBinding: AuthorityBindingV1

    var workspaceID: WorkspaceID { privacyPreviewApproval.workspaceID }
    var workspaceRevision: UInt64 { workspaceFrontier.workspaceRevision }

    init(
        projection: IncumbentAdapterProjectionPayloadV1,
        workspaceRevision: UInt64,
        allowedCanonicalFields: [IncumbentCanonicalFieldV1]
    ) throws {
        try projection.validate()
        try projection.projectionKind.validate(allowedCanonicalFields: allowedCanonicalFields)
        schemaVersion = Self.schemaVersion
        privacyPreviewApproval = projection.privacyPreviewApproval
        projectionKind = projection.projectionKind
        self.allowedCanonicalFields = allowedCanonicalFields
        workspaceFrontier = try IncumbentAdapterWorkspaceFrontierV1(
            workspaceID: projection.workspaceID,
            workspaceRevision: workspaceRevision
        )
        canonicalProjectionValues = try projection.canonicalProjectionValues()
        canonicalProjectionSHA256 = try projection.canonicalProjectionSHA256()
        bindingSHA256 = try IncumbentFileContractV1.digest(Basis(
            schemaVersion: Self.schemaVersion,
            privacyPreviewApproval: projection.privacyPreviewApproval,
            projectionKind: projection.projectionKind,
            allowedCanonicalFields: allowedCanonicalFields,
            workspaceFrontier: workspaceFrontier,
            canonicalProjectionValues: canonicalProjectionValues,
            canonicalProjectionSHA256: canonicalProjectionSHA256
        ))
        authorityBinding = .bound
        try validate()
    }

    /// Structural and digest validation intentionally does not grant runtime
    /// authority. A decoded value remains unusable until exact revalidation.
    func validate() throws {
        try privacyPreviewApproval.validate(workspaceID: privacyPreviewApproval.workspaceID)
        guard workspaceFrontier.workspaceID == workspaceID,
              workspaceFrontier.workspaceRevision > 0,
              canonicalProjectionValues == canonicalProjectionValues.sorted(by: {
                  $0.canonicalField.rawValue < $1.canonicalField.rawValue
              }),
              Set(canonicalProjectionValues.map(\.canonicalField)).count
                == canonicalProjectionValues.count else {
            throw IncumbentFileContractFailureV1.privacyApprovalRequired
        }
        try IncumbentFileContractV1.requireDigest(canonicalProjectionSHA256)
        try IncumbentFileContractV1.requireDigest(bindingSHA256)
        guard canonicalProjectionSHA256 == (try IncumbentFileContractV1.digest(
            canonicalProjectionValues
        )) else {
            throw IncumbentFileContractFailureV1.invalidDigest
        }
        let expectedBindingSHA256 = try IncumbentFileContractV1.digest(Basis(
            schemaVersion: schemaVersion,
            privacyPreviewApproval: privacyPreviewApproval,
            projectionKind: projectionKind,
            allowedCanonicalFields: allowedCanonicalFields,
            workspaceFrontier: workspaceFrontier,
            canonicalProjectionValues: canonicalProjectionValues,
            canonicalProjectionSHA256: canonicalProjectionSHA256
        ))
        guard schemaVersion == Self.schemaVersion,
              bindingSHA256 == expectedBindingSHA256 else {
            throw IncumbentFileContractFailureV1.invalidDigest
        }
        try projectionKind.validate(allowedCanonicalFields: allowedCanonicalFields)
    }

    func validate(workspaceID expectedWorkspaceID: WorkspaceID) throws {
        try validate()
        guard workspaceID == expectedWorkspaceID else {
            throw IncumbentFileContractFailureV1.privacyApprovalRequired
        }
    }

    func validate(
        workspaceID expectedWorkspaceID: WorkspaceID,
        workspaceRevision expectedWorkspaceRevision: UInt64,
        allowedCanonicalFields expectedAllowedCanonicalFields: [IncumbentCanonicalFieldV1]
    ) throws {
        try projectionKind.validate(allowedCanonicalFields: expectedAllowedCanonicalFields)
        try validate(workspaceID: expectedWorkspaceID)
        try requireAuthoritativelyBound()
        guard workspaceRevision == expectedWorkspaceRevision,
              allowedCanonicalFields == expectedAllowedCanonicalFields else {
            throw IncumbentFileContractFailureV1.privacyApprovalRequired
        }
    }

    func validate(
        expectedProjection: IncumbentAdapterProjectionPayloadV1,
        workspaceID expectedWorkspaceID: WorkspaceID,
        workspaceRevision expectedWorkspaceRevision: UInt64,
        allowedCanonicalFields expectedAllowedCanonicalFields: [IncumbentCanonicalFieldV1]
    ) throws {
        try expectedProjection.validate()
        let expectedCanonicalProjectionValues = try expectedProjection.canonicalProjectionValues()
        let expectedCanonicalProjectionSHA256 = try expectedProjection.canonicalProjectionSHA256()
        let expectedWorkspaceFrontier = try IncumbentAdapterWorkspaceFrontierV1(
            workspaceID: expectedWorkspaceID,
            workspaceRevision: expectedWorkspaceRevision
        )
        try validate(
            workspaceID: expectedWorkspaceID,
            workspaceRevision: expectedWorkspaceRevision,
            allowedCanonicalFields: expectedAllowedCanonicalFields
        )
        try requireAuthoritativelyBound()
        guard projectionKind == expectedProjection.projectionKind,
              privacyPreviewApproval == expectedProjection.privacyPreviewApproval,
              workspaceID == expectedProjection.workspaceID,
              workspaceFrontier == expectedWorkspaceFrontier,
              canonicalProjectionValues == expectedCanonicalProjectionValues,
              canonicalProjectionSHA256 == expectedCanonicalProjectionSHA256 else {
            throw IncumbentFileContractFailureV1.privacyApprovalRequired
        }
    }

    func requireAuthoritativelyBound() throws {
        guard authorityBinding == .bound else {
            throw IncumbentFileContractFailureV1.privacyApprovalRequired
        }
        do {
            try privacyPreviewApproval.requireAuthoritativelyBound()
        } catch {
            throw IncumbentFileContractFailureV1.privacyApprovalRequired
        }
    }

    func revalidated(
        manifest: PrivacyTransformManifestV1,
        review: PrivacyReviewReceiptV1,
        policy: PrivacyTransformPolicyV1,
        expectedProjection: IncumbentAdapterProjectionPayloadV1,
        workspaceID expectedWorkspaceID: WorkspaceID,
        workspaceRevision expectedWorkspaceRevision: UInt64,
        allowedCanonicalFields expectedAllowedCanonicalFields: [IncumbentCanonicalFieldV1]
    ) throws -> Self {
        let boundPrivacyPreviewApproval = try privacyPreviewApproval.revalidated(
            manifest: manifest,
            review: review,
            policy: policy
        )
        try expectedProjection.validate()
        guard expectedProjection.privacyPreviewApproval == boundPrivacyPreviewApproval,
              expectedProjection.workspaceID == expectedWorkspaceID else {
            throw IncumbentFileContractFailureV1.privacyApprovalRequired
        }
        let expectedWorkspaceFrontier = try IncumbentAdapterWorkspaceFrontierV1(
            workspaceID: expectedWorkspaceID,
            workspaceRevision: expectedWorkspaceRevision
        )
        let expectedCanonicalProjectionValues = try expectedProjection.canonicalProjectionValues()
        let expectedCanonicalProjectionSHA256 = try expectedProjection.canonicalProjectionSHA256()
        let authoritative = try Self(
            projection: expectedProjection,
            workspaceRevision: expectedWorkspaceRevision,
            allowedCanonicalFields: expectedAllowedCanonicalFields
        )
        guard authoritative.workspaceFrontier == expectedWorkspaceFrontier,
              authoritative.canonicalProjectionValues == expectedCanonicalProjectionValues,
              authoritative.canonicalProjectionSHA256 == expectedCanonicalProjectionSHA256 else {
            throw IncumbentFileContractFailureV1.privacyApprovalRequired
        }
        guard self == authoritative else {
            throw IncumbentFileContractFailureV1.privacyApprovalRequired
        }
        return authoritative
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.schemaVersion == rhs.schemaVersion
            && lhs.privacyPreviewApproval == rhs.privacyPreviewApproval
            && lhs.projectionKind == rhs.projectionKind
            && lhs.allowedCanonicalFields == rhs.allowedCanonicalFields
            && lhs.workspaceFrontier == rhs.workspaceFrontier
            && lhs.canonicalProjectionValues == rhs.canonicalProjectionValues
            && lhs.canonicalProjectionSHA256 == rhs.canonicalProjectionSHA256
            && lhs.bindingSHA256 == rhs.bindingSHA256
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(schemaVersion)
        hasher.combine(privacyPreviewApproval)
        hasher.combine(projectionKind)
        hasher.combine(allowedCanonicalFields)
        hasher.combine(workspaceFrontier)
        hasher.combine(canonicalProjectionValues)
        hasher.combine(canonicalProjectionSHA256)
        hasher.combine(bindingSHA256)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, privacyPreviewApproval, projectionKind
        case allowedCanonicalFields, workspaceFrontier
        case canonicalProjectionValues, canonicalProjectionSHA256, bindingSHA256
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        privacyPreviewApproval = try values.decode(
            C50PrivacyPreviewApprovalReferenceV1.self,
            forKey: .privacyPreviewApproval
        )
        projectionKind = try values.decode(
            IncumbentAdapterProjectionKindV1.self,
            forKey: .projectionKind
        )
        allowedCanonicalFields = try values.decode(
            [IncumbentCanonicalFieldV1].self,
            forKey: .allowedCanonicalFields
        )
        workspaceFrontier = try values.decode(
            IncumbentAdapterWorkspaceFrontierV1.self,
            forKey: .workspaceFrontier
        )
        canonicalProjectionValues = try values.decode(
            [IncumbentCanonicalProjectionValueV1].self,
            forKey: .canonicalProjectionValues
        )
        canonicalProjectionSHA256 = try values.decode(
            String.self,
            forKey: .canonicalProjectionSHA256
        )
        bindingSHA256 = try values.decode(String.self, forKey: .bindingSHA256)
        authorityBinding = .unbound
        try validate()
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(privacyPreviewApproval, forKey: .privacyPreviewApproval)
        try values.encode(projectionKind, forKey: .projectionKind)
        try values.encode(allowedCanonicalFields, forKey: .allowedCanonicalFields)
        try values.encode(workspaceFrontier, forKey: .workspaceFrontier)
        try values.encode(canonicalProjectionValues, forKey: .canonicalProjectionValues)
        try values.encode(canonicalProjectionSHA256, forKey: .canonicalProjectionSHA256)
        try values.encode(bindingSHA256, forKey: .bindingSHA256)
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let privacyPreviewApproval: C50PrivacyPreviewApprovalReferenceV1
        let projectionKind: IncumbentAdapterProjectionKindV1
        let allowedCanonicalFields: [IncumbentCanonicalFieldV1]
        let workspaceFrontier: IncumbentAdapterWorkspaceFrontierV1
        let canonicalProjectionValues: [IncumbentCanonicalProjectionValueV1]
        let canonicalProjectionSHA256: String
    }
}

enum IncumbentAdapterProjectionV1: Codable, Equatable, Sendable {
    case portableReview(C50PortableReviewAdapterProjectionV1,
                        privacyApproval: IncumbentPrivacyApprovalReferenceV1)
    case workResource(C50WorkResourceAdapterProjectionV1,
                      privacyApproval: IncumbentPrivacyApprovalReferenceV1)

    var privacyApproval: IncumbentPrivacyApprovalReferenceV1 {
        switch self {
        case let .portableReview(_, approval), let .workResource(_, approval): return approval
        }
    }

    var projectionKind: IncumbentAdapterProjectionKindV1 {
        projectionPayload.projectionKind
    }

    var projectionPayload: IncumbentAdapterProjectionPayloadV1 {
        switch self {
        case let .portableReview(value, _): return .portableReview(value)
        case let .workResource(value, _): return .workResource(value)
        }
    }

    func validate(scope: IncumbentExchangeScopeV1) throws {
        try privacyApproval.validate(
            expectedProjection: projectionPayload,
            workspaceID: scope.workspaceID,
            workspaceRevision: scope.workspaceRevision,
            allowedCanonicalFields: scope.allowedCanonicalFields
        )
        guard scope.privacyApproval == privacyApproval else {
            throw IncumbentFileContractFailureV1.privacyApprovalRequired
        }
        switch self {
        case let .portableReview(value, approval):
            try value.privacyApproval.requireAuthoritativelyBound()
            guard approval.projectionKind == .portableReview,
                  value.privacyApproval == approval.privacyPreviewApproval else {
                throw IncumbentFileContractFailureV1.privacyApprovalRequired
            }
            try C50PortableReviewAdapterDelegationV1.validate(value)
        case let .workResource(value, approval):
            try value.privacyApproval.requireAuthoritativelyBound()
            guard approval.projectionKind == .workResource,
                  value.privacyApproval == approval.privacyPreviewApproval else {
                throw IncumbentFileContractFailureV1.privacyApprovalRequired
            }
            try C50WorkResourceAdapterDelegationV1.validate(value)
        }
    }

    func value(for field: IncumbentCanonicalFieldV1,
               scope: IncumbentExchangeScopeV1) throws -> String? {
        try validate(scope: scope)
        func canonical<T: Encodable>(_ value: T) throws -> String {
            let data = try WorkspaceMutationCanonicalV1.data(value)
            guard let text = String(data: data, encoding: .utf8) else {
                throw IncumbentFileContractFailureV1.invalidValue
            }
            return text
        }
        switch (self, field) {
        case (_, .fileFormatVersion): return nil
        case let (.portableReview(value, _), .portableReviewPublicID): return value.requestPublicID.rawValue
        case let (.portableReview(value, _), .portableReviewState): return value.state.rawValue
        case let (.portableReview(value, _), .portableReviewLatestResponsePublicID):
            guard let responseID = value.latestResponsePublicID else { return nil }
            return responseID
        case let (.workResource(value, _), .workDurationMinutes): return String(value.durationMinutes)
        case let (.workResource(value, _), .workMaterialLineCount): return String(value.materialLineCount)
        case let (.workResource(value, _), .workMaterialTotals): return try canonical(value.materialTotals)
        default: return nil
        }
    }
}

struct IncumbentFileBudgetV1: Codable, Equatable, Hashable, Sendable {
    let maximumByteCount: UInt64
    let maximumRowCount: Int
    let maximumColumnCount: Int
    let maximumScalarCountPerCell: Int

    init(maximumByteCount: UInt64, maximumRowCount: Int,
         maximumColumnCount: Int, maximumScalarCountPerCell: Int) throws {
        guard (1...4_294_967_296).contains(maximumByteCount),
              (1...250_000).contains(maximumRowCount),
              (1...256).contains(maximumColumnCount),
              (1...65_536).contains(maximumScalarCountPerCell) else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        self.maximumByteCount = maximumByteCount
        self.maximumRowCount = maximumRowCount
        self.maximumColumnCount = maximumColumnCount
        self.maximumScalarCountPerCell = maximumScalarCountPerCell
    }
}

struct IncumbentFieldMappingV1: Codable, Equatable, Hashable, Sendable {
    let externalHeader: String
    let canonicalField: IncumbentCanonicalFieldV1
    let fieldClass: IncumbentFileFieldClassV1
    let required: Bool

    init(externalHeader: String, canonicalField: IncumbentCanonicalFieldV1,
         fieldClass: IncumbentFileFieldClassV1? = nil, required: Bool) throws {
        try IncumbentFileContractV1.requireText(externalHeader, maximumBytes: 256)
        guard fieldClass == nil || fieldClass == canonicalField.fieldClass else {
            throw IncumbentFileContractFailureV1.fieldNotAllowed
        }
        self.externalHeader = externalHeader
        self.canonicalField = canonicalField
        self.fieldClass = canonicalField.fieldClass
        self.required = required
    }

    init(externalHeader: String, canonicalField: String,
         fieldClass: IncumbentFileFieldClassV1 = .ordinary, required: Bool) throws {
        guard let typed = IncumbentCanonicalFieldV1(rawValue: canonicalField) else {
            throw IncumbentFileContractFailureV1.fieldNotAllowed
        }
        try self.init(externalHeader: externalHeader, canonicalField: typed,
                      fieldClass: fieldClass, required: required)
    }
}

struct IncumbentMappingManifestV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let mappings: [IncumbentFieldMappingV1]
    let manifestSHA256: String

    init(mappings: [IncumbentFieldMappingV1]) throws {
        guard !mappings.isEmpty, mappings.count <= 256,
              Set(mappings.map(\.externalHeader)).count == mappings.count,
              Set(mappings.map(\.canonicalField)).count == mappings.count else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.mappings = mappings
        manifestSHA256 = try IncumbentFileContractV1.digest(
            Basis(schemaVersion: Self.schemaVersion, mappings: mappings)
        )
    }

    func validate() throws {
        let rebuilt = try Self(mappings: mappings)
        guard schemaVersion == Self.schemaVersion,
              manifestSHA256 == rebuilt.manifestSHA256 else {
            throw IncumbentFileContractFailureV1.invalidDigest
        }
    }

    private struct Basis: Codable { let schemaVersion: Int; let mappings: [IncumbentFieldMappingV1] }
}

struct IncumbentFileProfileReleaseV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let profileID: UUID
    let adapterID: UUID
    let releaseID: UUID
    let revision: UInt64
    let providerDisplayToken: String
    let uniformTypeIdentifiers: [String]
    let filenameExtensions: [String]
    let encoding: IncumbentFileEncodingV1
    let delimiter: IncumbentFileDelimiterV1
    let orderedHeaders: [String]
    let versionHeader: String
    let versionValue: String
    let direction: IncumbentFileDirectionV1
    let budget: IncumbentFileBudgetV1
    let mappingManifest: IncumbentMappingManifestV1
    let externalKeyPolicy: IncumbentExternalKeyPolicyV1
    let timeZonePolicy: IncumbentTimeZonePolicyV1
    let predecessorReleaseID: UUID?
    let predecessorReleaseSHA256: String?
    let releaseSHA256: String

    init(profileID: UUID, adapterID: UUID, releaseID: UUID, revision: UInt64,
         providerDisplayToken: String, uniformTypeIdentifiers: [String],
         filenameExtensions: [String], encoding: IncumbentFileEncodingV1 = .utf8,
         delimiter: IncumbentFileDelimiterV1, orderedHeaders: [String],
         versionHeader: String, versionValue: String, direction: IncumbentFileDirectionV1,
         budget: IncumbentFileBudgetV1, mappingManifest: IncumbentMappingManifestV1,
         externalKeyPolicy: IncumbentExternalKeyPolicyV1,
         timeZonePolicy: IncumbentTimeZonePolicyV1,
         predecessorReleaseID: UUID? = nil, predecessorReleaseSHA256: String? = nil) throws {
        try IncumbentFileContractV1.requireID(profileID)
        try IncumbentFileContractV1.requireID(adapterID)
        try IncumbentFileContractV1.requireID(releaseID)
        try IncumbentFileContractV1.requireToken(providerDisplayToken)
        try IncumbentFileContractV1.requireText(versionHeader, maximumBytes: 256)
        try IncumbentFileContractV1.requireToken(versionValue)
        try mappingManifest.validate()
        guard revision > 0, !uniformTypeIdentifiers.isEmpty, !filenameExtensions.isEmpty,
              uniformTypeIdentifiers == uniformTypeIdentifiers.sorted(),
              filenameExtensions == filenameExtensions.sorted(),
              Set(uniformTypeIdentifiers).count == uniformTypeIdentifiers.count,
              Set(filenameExtensions).count == filenameExtensions.count,
              !orderedHeaders.isEmpty, orderedHeaders.count == mappingManifest.mappings.count,
              orderedHeaders.count <= budget.maximumColumnCount,
              orderedHeaders == mappingManifest.mappings.map(\.externalHeader),
              Set(orderedHeaders).count == orderedHeaders.count,
              orderedHeaders.contains(versionHeader),
              mappingManifest.mappings.filter({ $0.externalHeader == versionHeader }).count == 1,
              mappingManifest.mappings.first(where: { $0.externalHeader == versionHeader })?
                .canonicalField == .fileFormatVersion,
              uniformTypeIdentifiers.allSatisfy({ (try? IncumbentFileContractV1.requireToken($0)) != nil }),
              filenameExtensions.allSatisfy({ (try? IncumbentFileContractV1.requireToken($0)) != nil }),
              (revision == 1) == (predecessorReleaseID == nil && predecessorReleaseSHA256 == nil),
              (revision > 1) == (predecessorReleaseID != nil && predecessorReleaseSHA256 != nil) else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        if let predecessorReleaseID { try IncumbentFileContractV1.requireID(predecessorReleaseID) }
        if let predecessorReleaseSHA256 { try IncumbentFileContractV1.requireDigest(predecessorReleaseSHA256) }
        schemaVersion = Self.schemaVersion; self.profileID = profileID; self.adapterID = adapterID
        self.releaseID = releaseID
        self.revision = revision; self.providerDisplayToken = providerDisplayToken
        self.uniformTypeIdentifiers = uniformTypeIdentifiers; self.filenameExtensions = filenameExtensions
        self.encoding = encoding; self.delimiter = delimiter; self.orderedHeaders = orderedHeaders
        self.versionHeader = versionHeader; self.versionValue = versionValue; self.direction = direction
        self.budget = budget; self.mappingManifest = mappingManifest
        self.externalKeyPolicy = externalKeyPolicy; self.timeZonePolicy = timeZonePolicy
        self.predecessorReleaseID = predecessorReleaseID
        self.predecessorReleaseSHA256 = predecessorReleaseSHA256
        releaseSHA256 = try IncumbentFileContractV1.digest(Basis(
            schemaVersion: Self.schemaVersion, profileID: profileID, adapterID: adapterID,
            releaseID: releaseID,
            revision: revision, providerDisplayToken: providerDisplayToken,
            uniformTypeIdentifiers: uniformTypeIdentifiers, filenameExtensions: filenameExtensions,
            encoding: encoding, delimiter: delimiter, orderedHeaders: orderedHeaders,
            versionHeader: versionHeader, versionValue: versionValue, direction: direction,
            budget: budget, mappingManifest: mappingManifest,
            externalKeyPolicy: externalKeyPolicy, timeZonePolicy: timeZonePolicy,
            predecessorReleaseID: predecessorReleaseID,
            predecessorReleaseSHA256: predecessorReleaseSHA256
        ))
    }

    func validate() throws {
        let rebuilt = try Self(profileID: profileID, adapterID: adapterID,
            releaseID: releaseID, revision: revision,
            providerDisplayToken: providerDisplayToken, uniformTypeIdentifiers: uniformTypeIdentifiers,
            filenameExtensions: filenameExtensions, encoding: encoding, delimiter: delimiter,
            orderedHeaders: orderedHeaders, versionHeader: versionHeader, versionValue: versionValue,
            direction: direction, budget: budget, mappingManifest: mappingManifest,
            externalKeyPolicy: externalKeyPolicy, timeZonePolicy: timeZonePolicy,
            predecessorReleaseID: predecessorReleaseID,
            predecessorReleaseSHA256: predecessorReleaseSHA256)
        guard schemaVersion == Self.schemaVersion, releaseSHA256 == rebuilt.releaseSHA256 else {
            throw IncumbentFileContractFailureV1.invalidDigest
        }
    }

    func validateSuccessor(of predecessor: Self) throws {
        try validate(); try predecessor.validate()
        guard profileID == predecessor.profileID, adapterID == predecessor.adapterID,
              releaseID != predecessor.releaseID,
              revision == predecessor.revision + 1,
              predecessorReleaseID == predecessor.releaseID,
              predecessorReleaseSHA256 == predecessor.releaseSHA256 else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
    }

    private struct Basis: Codable {
        let schemaVersion: Int; let profileID: UUID; let adapterID: UUID
        let releaseID: UUID; let revision: UInt64
        let providerDisplayToken: String; let uniformTypeIdentifiers: [String]; let filenameExtensions: [String]
        let encoding: IncumbentFileEncodingV1; let delimiter: IncumbentFileDelimiterV1; let orderedHeaders: [String]
        let versionHeader: String; let versionValue: String; let direction: IncumbentFileDirectionV1
        let budget: IncumbentFileBudgetV1; let mappingManifest: IncumbentMappingManifestV1
        let externalKeyPolicy: IncumbentExternalKeyPolicyV1; let timeZonePolicy: IncumbentTimeZonePolicyV1
        let predecessorReleaseID: UUID?; let predecessorReleaseSHA256: String?
    }
}

enum IncumbentSelectionDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case enabledNamedProfile = "ENABLED_NAMED_PROFILE"
    case disabledNoSelectedProfile = "DISABLED_NO_SELECTED_PROFILE"
}

enum IncumbentTermsDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case approvedForLocalFileExchange = "APPROVED_FOR_LOCAL_FILE_EXCHANGE"
    case unavailable = "UNAVAILABLE"
    case expired = "EXPIRED"
}

struct IncumbentSelectionReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let receiptID: UUID; let revision: UInt64
    let predecessorReceiptID: UUID?; let predecessorReceiptSHA256: String?
    let disposition: IncumbentSelectionDispositionV1
    let selectedReleaseID: UUID?; let selectedReleaseSHA256: String?
    let sanitizedFixtureProvenance: String; let targetWorkflow: String
    let fileVersion: String?; let direction: IncumbentFileDirectionV1?
    let stableKeyMeaning: String; let termsDisposition: IncumbentTermsDispositionV1
    let evidenceDate: Date; let evidenceExpiresAt: Date?; let receiptSHA256: String

    init(receiptID: UUID, revision: UInt64 = 1,
         predecessorReceiptID: UUID? = nil, predecessorReceiptSHA256: String? = nil,
         disposition: IncumbentSelectionDispositionV1,
         selectedRelease: IncumbentFileProfileReleaseV1?, sanitizedFixtureProvenance: String,
         targetWorkflow: String, fileVersion: String?, direction: IncumbentFileDirectionV1?,
         stableKeyMeaning: String, termsDisposition: IncumbentTermsDispositionV1,
         evidenceDate: Date, evidenceExpiresAt: Date?) throws {
        try IncumbentFileContractV1.requireID(receiptID)
        try IncumbentFileContractV1.requireText(sanitizedFixtureProvenance)
        try IncumbentFileContractV1.requireToken(targetWorkflow)
        try IncumbentFileContractV1.requireText(stableKeyMeaning)
        try selectedRelease?.validate()
        guard revision > 0,
              (revision == 1) == (predecessorReceiptID == nil && predecessorReceiptSHA256 == nil),
              (revision > 1) == (predecessorReceiptID != nil && predecessorReceiptSHA256 != nil),
              evidenceDate.timeIntervalSinceReferenceDate.isFinite,
              evidenceExpiresAt?.timeIntervalSinceReferenceDate.isFinite ?? true,
              evidenceExpiresAt.map({ $0 > evidenceDate }) ?? true,
              disposition == .enabledNamedProfile
                ? (selectedRelease != nil && fileVersion == selectedRelease?.versionValue
                    && direction == selectedRelease?.direction
                    && termsDisposition == .approvedForLocalFileExchange && evidenceExpiresAt != nil)
                : (selectedRelease == nil && fileVersion == nil && direction == nil
                    && termsDisposition != .approvedForLocalFileExchange) else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        if let predecessorReceiptID { try IncumbentFileContractV1.requireID(predecessorReceiptID) }
        if let predecessorReceiptSHA256 { try IncumbentFileContractV1.requireDigest(predecessorReceiptSHA256) }
        schemaVersion = Self.schemaVersion; self.receiptID = receiptID; self.revision = revision
        self.predecessorReceiptID = predecessorReceiptID
        self.predecessorReceiptSHA256 = predecessorReceiptSHA256
        self.disposition = disposition
        selectedReleaseID = selectedRelease?.releaseID; selectedReleaseSHA256 = selectedRelease?.releaseSHA256
        self.sanitizedFixtureProvenance = sanitizedFixtureProvenance; self.targetWorkflow = targetWorkflow
        self.fileVersion = fileVersion; self.direction = direction; self.stableKeyMeaning = stableKeyMeaning
        self.termsDisposition = termsDisposition; self.evidenceDate = evidenceDate
        self.evidenceExpiresAt = evidenceExpiresAt
        receiptSHA256 = try IncumbentFileContractV1.digest(Basis(
            schemaVersion: Self.schemaVersion, receiptID: receiptID, revision: revision,
            predecessorReceiptID: predecessorReceiptID,
            predecessorReceiptSHA256: predecessorReceiptSHA256, disposition: disposition,
            selectedReleaseID: selectedRelease?.releaseID,
            selectedReleaseSHA256: selectedRelease?.releaseSHA256,
            sanitizedFixtureProvenance: sanitizedFixtureProvenance, targetWorkflow: targetWorkflow,
            fileVersion: fileVersion, direction: direction, stableKeyMeaning: stableKeyMeaning,
            termsDisposition: termsDisposition, evidenceDate: evidenceDate,
            evidenceExpiresAt: evidenceExpiresAt))
    }

    func validate(selectedRelease: IncumbentFileProfileReleaseV1?, at date: Date? = nil) throws {
        let rebuilt = try Self(receiptID: receiptID, revision: revision,
            predecessorReceiptID: predecessorReceiptID,
            predecessorReceiptSHA256: predecessorReceiptSHA256, disposition: disposition,
            selectedRelease: selectedRelease, sanitizedFixtureProvenance: sanitizedFixtureProvenance,
            targetWorkflow: targetWorkflow, fileVersion: fileVersion, direction: direction,
            stableKeyMeaning: stableKeyMeaning, termsDisposition: termsDisposition,
            evidenceDate: evidenceDate, evidenceExpiresAt: evidenceExpiresAt)
        guard schemaVersion == Self.schemaVersion, receiptSHA256 == rebuilt.receiptSHA256 else {
            throw IncumbentFileContractFailureV1.invalidDigest
        }
        if disposition == .enabledNamedProfile, let date,
           !(evidenceExpiresAt.map({ date < $0 }) ?? false) {
            throw IncumbentFileContractFailureV1.staleSelection
        }
    }

    func validateSuccessor(of predecessor: Self,
                           selectedRelease: IncumbentFileProfileReleaseV1?) throws {
        try validate(selectedRelease: selectedRelease)
        guard receiptID != predecessor.receiptID, revision == predecessor.revision + 1,
              predecessorReceiptID == predecessor.receiptID,
              predecessorReceiptSHA256 == predecessor.receiptSHA256,
              evidenceDate >= predecessor.evidenceDate else {
            throw IncumbentFileContractFailureV1.staleSelection
        }
    }

    private struct Basis: Codable {
        let schemaVersion: Int; let receiptID: UUID; let revision: UInt64
        let predecessorReceiptID: UUID?; let predecessorReceiptSHA256: String?
        let disposition: IncumbentSelectionDispositionV1
        let selectedReleaseID: UUID?; let selectedReleaseSHA256: String?
        let sanitizedFixtureProvenance: String; let targetWorkflow: String; let fileVersion: String?
        let direction: IncumbentFileDirectionV1?; let stableKeyMeaning: String
        let termsDisposition: IncumbentTermsDispositionV1; let evidenceDate: Date; let evidenceExpiresAt: Date?
    }
}

struct ClosedIncumbentAdapterRegistryV1: Sendable {
    let currentProductionReleases: [IncumbentFileProfileReleaseV1]
    let historicReleases: [IncumbentFileProfileReleaseV1]
    let selection: IncumbentSelectionReceiptV1
    let selectionHistory: [IncumbentSelectionReceiptV1]
    let availabilityReceipt: TypedAvailabilityAndFallbackReceiptV1

    init(currentProductionReleases: [IncumbentFileProfileReleaseV1],
         historicReleases: [IncumbentFileProfileReleaseV1] = [],
         selection: IncumbentSelectionReceiptV1,
         selectionHistory: [IncumbentSelectionReceiptV1],
         availabilityReceipt: TypedAvailabilityAndFallbackReceiptV1) throws {
        guard currentProductionReleases.count <= 1 else {
            throw IncumbentFileContractFailureV1.multipleSelectedProfiles
        }
        let all = currentProductionReleases + historicReleases
        try all.forEach { try $0.validate() }
        guard Set(all.map(\.profileID)).count <= 1,
              Set(all.map(\.releaseID)).count == all.count,
              Set(all.map(\.releaseSHA256)).count == all.count else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        for release in all where release.revision > 1 {
            let predecessors = all.filter {
                $0.profileID == release.profileID
                    && $0.releaseID == release.predecessorReleaseID
                    && $0.releaseSHA256 == release.predecessorReleaseSHA256
            }
            guard predecessors.count == 1 else {
                throw IncumbentFileContractFailureV1.unsupportedVersion
            }
            try release.validateSuccessor(of: predecessors[0])
        }
        if let current = currentProductionReleases.first {
            guard !all.contains(where: {
                $0.profileID == current.profileID && $0.revision > current.revision
            }) else { throw IncumbentFileContractFailureV1.staleSelection }
        }
        let selected = currentProductionReleases.first
        guard !selectionHistory.isEmpty, selectionHistory.last == selection,
              selectionHistory.map(\.revision) == Array(1...UInt64(selectionHistory.count)),
              Set(selectionHistory.map(\.receiptID)).count == selectionHistory.count,
              Set(selectionHistory.map(\.receiptSHA256)).count == selectionHistory.count else {
            throw IncumbentFileContractFailureV1.staleSelection
        }
        for (index, receipt) in selectionHistory.enumerated() {
            let receiptRelease = all.first {
                $0.releaseID == receipt.selectedReleaseID
                    && $0.releaseSHA256 == receipt.selectedReleaseSHA256
            }
            try receipt.validate(selectedRelease: receiptRelease)
            if index > 0 {
                try receipt.validateSuccessor(of: selectionHistory[index - 1],
                                              selectedRelease: receiptRelease)
            }
        }
        guard (selection.disposition == .enabledNamedProfile) == (selected != nil) else {
            throw IncumbentFileContractFailureV1.noSelectedProfile
        }
        guard selection.selectedReleaseID == selected?.releaseID,
              selection.selectedReleaseSHA256 == selected?.releaseSHA256 else {
            throw IncumbentFileContractFailureV1.staleSelection
        }
        try availabilityReceipt.validate()
        let availabilityMatchesSelection = selected == nil
            ? availabilityReceipt.availabilityReason != .available
            : availabilityReceipt.availabilityReason == .available
        guard availabilityReceipt.capabilityID == .filesAndShare,
              availabilityMatchesSelection else {
            throw IncumbentFileContractFailureV1.staleSelection
        }
        self.currentProductionReleases = currentProductionReleases
        self.historicReleases = historicReleases
        self.selection = selection
        self.selectionHistory = selectionHistory
        self.availabilityReceipt = availabilityReceipt
    }

    /// Reuses the capability receipt as availability evidence; it does not
    /// persist selection or create a second capability authority.
    func validateAvailability(_ receipt: TypedAvailabilityAndFallbackReceiptV1) throws {
        try receipt.validate()
        guard receipt == availabilityReceipt, receipt.capabilityID == .filesAndShare,
              (currentProductionReleases.isEmpty
                ? receipt.availabilityReason != .available
                : receipt.availabilityReason == .available) else {
            throw IncumbentFileContractFailureV1.staleSelection
        }
    }

    func selectedRelease(at date: Date) throws -> IncumbentFileProfileReleaseV1 {
        guard let value = currentProductionReleases.first else {
            throw IncumbentFileContractFailureV1.noSelectedProfile
        }
        try selection.validate(selectedRelease: value, at: date)
        return value
    }

    func exactHistoricRelease(id: UUID, sha256: String) throws -> IncumbentFileProfileReleaseV1 {
        let matches = (currentProductionReleases + historicReleases).filter {
            $0.releaseID == id && $0.releaseSHA256 == sha256
        }
        guard matches.count == 1 else { throw IncumbentFileContractFailureV1.unsupportedVersion }
        return matches[0]
    }
}
