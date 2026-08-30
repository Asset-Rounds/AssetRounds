import Foundation

struct IncumbentFileInputV1: Equatable, Sendable {
    let bytes: Data
    let byteSHA256: String
    let filenameExtension: String
    let uniformTypeIdentifier: String

    init(bytes: Data, filenameExtension: String, uniformTypeIdentifier: String) throws {
        guard !bytes.isEmpty else { throw IncumbentFileContractFailureV1.invalidValue }
        try IncumbentFileContractV1.requireToken(filenameExtension)
        try IncumbentFileContractV1.requireToken(uniformTypeIdentifier)
        self.bytes = bytes
        byteSHA256 = CanonicalJSONV1.sha256(bytes)
        self.filenameExtension = filenameExtension
        self.uniformTypeIdentifier = uniformTypeIdentifier
    }
}

struct IncumbentFileDetectionV1: Codable, Equatable, Sendable {
    let releaseID: UUID; let releaseSHA256: String; let inputSHA256: String
    let observedHeaders: [String]; let observedVersion: String; let rowCount: Int

    init(release: IncumbentFileProfileReleaseV1, inputSHA256: String,
         observedHeaders: [String], observedVersion: String, rowCount: Int) throws {
        try release.validate(); try IncumbentFileContractV1.requireDigest(inputSHA256)
        guard observedHeaders == release.orderedHeaders,
              observedVersion == release.versionValue,
              rowCount > 0, rowCount <= release.budget.maximumRowCount else {
            throw observedHeaders == release.orderedHeaders
                ? IncumbentFileContractFailureV1.unsupportedVersion
                : IncumbentFileContractFailureV1.headerMismatch
        }
        self.releaseID = release.releaseID; self.releaseSHA256 = release.releaseSHA256
        self.inputSHA256 = inputSHA256; self.observedHeaders = observedHeaders
        self.observedVersion = observedVersion; self.rowCount = rowCount
    }

    func validate(input: IncumbentFileInputV1,
                  release: IncumbentFileProfileReleaseV1) throws {
        let decoded = try IncumbentDelimitedTextSafetyV1.validateInputBytes(input.bytes,
            release: release)
        let versionIndex = try IncumbentDelimitedTextSafetyV1.versionColumnIndex(release: release)
        guard let firstDataRow = decoded.dropFirst().first else {
            throw IncumbentFileContractFailureV1.unsupportedVersion
        }
        let rebuilt = try Self(release: release, inputSHA256: input.byteSHA256,
            observedHeaders: decoded[0], observedVersion: firstDataRow[versionIndex],
            rowCount: decoded.count - 1)
        guard self == rebuilt else { throw IncumbentFileContractFailureV1.invalidDigest }
    }
}

struct IncumbentFileCellV1: Codable, Equatable, Hashable, Sendable {
    let field: IncumbentCanonicalFieldV1; let value: String
    init(field: IncumbentCanonicalFieldV1, value: String, maximumScalars: Int) throws {
        guard value.unicodeScalars.count <= maximumScalars,
              value.unicodeScalars.allSatisfy({
                  $0.value >= 0x20 || $0.value == 0x0a || $0.value == 0x0d || $0.value == 0x09
              }) else {
            throw IncumbentFileContractFailureV1.budgetExceeded
        }
        self.field = field; self.value = value.precomposedStringWithCanonicalMapping
    }

    init(field: String, value: String, maximumScalars: Int) throws {
        guard let typed = IncumbentCanonicalFieldV1(rawValue: field) else {
            throw IncumbentFileContractFailureV1.fieldNotAllowed
        }
        try self.init(field: typed, value: value, maximumScalars: maximumScalars)
    }

    func validate(maximumScalars: Int) throws {
        guard self == (try Self(field: field, value: value, maximumScalars: maximumScalars)) else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
    }
}

struct IncumbentFileRowV1: Codable, Equatable, Sendable {
    let ordinal: Int; let cells: [IncumbentFileCellV1]
    init(ordinal: Int, cells: [IncumbentFileCellV1], release: IncumbentFileProfileReleaseV1) throws {
        guard ordinal > 0, cells.count == release.mappingManifest.mappings.count,
              cells.map(\.field) == release.mappingManifest.mappings.map(\.canonicalField) else {
            throw IncumbentFileContractFailureV1.headerMismatch
        }
        self.ordinal = ordinal; self.cells = cells
    }

    init(ordinal: Int, projection: IncumbentAdapterProjectionV1,
         release: IncumbentFileProfileReleaseV1, scope: IncumbentExchangeScopeV1) throws {
        try projection.validate(scope: scope)
        guard scope.releaseID == release.releaseID,
              scope.releaseSHA256 == release.releaseSHA256,
              release.mappingManifest.mappings.allSatisfy({
                  scope.allowedCanonicalFields.contains($0.canonicalField)
              }),
              scope.privacyApproval == projection.privacyApproval else {
            throw IncumbentFileContractFailureV1.privacyApprovalRequired
        }
        let cells = try release.mappingManifest.mappings.map { mapping in
            let value: String?
            if mapping.canonicalField == .fileFormatVersion {
                value = release.versionValue
            } else {
                value = try projection.value(for: mapping.canonicalField, scope: scope)
            }
            guard value != nil || !mapping.required else {
                throw IncumbentFileContractFailureV1.fieldNotAllowed
            }
            return try IncumbentFileCellV1(field: mapping.canonicalField, value: value ?? "",
                maximumScalars: release.budget.maximumScalarCountPerCell)
        }
        try self.init(ordinal: ordinal, cells: cells, release: release)
    }

    func validate(release: IncumbentFileProfileReleaseV1) throws {
        try cells.forEach { try $0.validate(maximumScalars: release.budget.maximumScalarCountPerCell) }
        guard self == (try Self(ordinal: ordinal, cells: cells, release: release)) else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
    }
}

struct IncumbentExchangeScopeV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let operationID: UUID; let workspaceID: WorkspaceID
    let workspaceRevision: UInt64; let releaseID: UUID; let releaseSHA256: String
    let direction: IncumbentFileDirectionV1; let allowedCanonicalFields: [IncumbentCanonicalFieldV1]
    let privacyApproval: IncumbentPrivacyApprovalReferenceV1?; let scopeSHA256: String

    init(operationID: UUID, workspaceID: WorkspaceID, workspaceRevision: UInt64,
         release: IncumbentFileProfileReleaseV1, direction: IncumbentFileDirectionV1,
         allowedCanonicalFields: [IncumbentCanonicalFieldV1],
         privacyApproval: IncumbentPrivacyApprovalReferenceV1?) throws {
        try IncumbentFileContractV1.requireID(operationID); try release.validate()
        try privacyApproval?.requireAuthoritativelyBound()
        if let privacyApproval {
            try privacyApproval.validate(
                workspaceID: workspaceID,
                workspaceRevision: workspaceRevision,
                allowedCanonicalFields: allowedCanonicalFields
            )
        }
        let declared = release.mappingManifest.mappings.filter { allowedCanonicalFields.contains($0.canonicalField) }
        guard workspaceRevision > 0, direction == release.direction || release.direction == .bidirectionalFiles,
              !allowedCanonicalFields.isEmpty,
              allowedCanonicalFields == allowedCanonicalFields.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(allowedCanonicalFields).count == allowedCanonicalFields.count,
              declared.count == allowedCanonicalFields.count,
              release.mappingManifest.mappings.filter(\.required)
                .allSatisfy({ allowedCanonicalFields.contains($0.canonicalField) }),
              privacyApproval.map({
                  $0.workspaceID == workspaceID
                      && $0.allowedCanonicalFields == allowedCanonicalFields
              }) ?? true,
              declared.allSatisfy({ !$0.canonicalField.requiresExplicitPrivacyApproval }) || privacyApproval != nil else {
            throw IncumbentFileContractFailureV1.fieldNotAllowed
        }
        schemaVersion = Self.schemaVersion; self.operationID = operationID; self.workspaceID = workspaceID
        self.workspaceRevision = workspaceRevision; releaseID = release.releaseID
        releaseSHA256 = release.releaseSHA256; self.direction = direction
        self.allowedCanonicalFields = allowedCanonicalFields; self.privacyApproval = privacyApproval
        scopeSHA256 = try IncumbentFileContractV1.digest(Basis(
            schemaVersion: Self.schemaVersion, operationID: operationID, workspaceID: workspaceID,
            workspaceRevision: workspaceRevision, releaseID: release.releaseID,
            releaseSHA256: release.releaseSHA256, direction: direction,
            allowedCanonicalFields: allowedCanonicalFields, privacyApproval: privacyApproval))
    }

    init(operationID: UUID, workspaceID: WorkspaceID, workspaceRevision: UInt64,
         release: IncumbentFileProfileReleaseV1, direction: IncumbentFileDirectionV1,
         allowedCanonicalFields: [String], privacyApproval: IncumbentPrivacyApprovalReferenceV1?) throws {
        let typed = try allowedCanonicalFields.map { value -> IncumbentCanonicalFieldV1 in
            guard let field = IncumbentCanonicalFieldV1(rawValue: value) else {
                throw IncumbentFileContractFailureV1.fieldNotAllowed
            }
            return field
        }
        try self.init(operationID: operationID, workspaceID: workspaceID,
            workspaceRevision: workspaceRevision, release: release, direction: direction,
            allowedCanonicalFields: typed, privacyApproval: privacyApproval)
    }

    func validate(release: IncumbentFileProfileReleaseV1) throws {
        guard self == (try Self(operationID: operationID, workspaceID: workspaceID,
            workspaceRevision: workspaceRevision, release: release, direction: direction,
            allowedCanonicalFields: allowedCanonicalFields, privacyApproval: privacyApproval)) else {
            throw IncumbentFileContractFailureV1.invalidDigest
        }
    }

    func revalidatedPrivacyAuthority(
        manifest: PrivacyTransformManifestV1, review: PrivacyReviewReceiptV1,
        policy: PrivacyTransformPolicyV1,
        expectedProjection: IncumbentAdapterProjectionPayloadV1,
        expectedWorkspaceID: WorkspaceID,
        expectedWorkspaceRevision: UInt64,
        expectedAllowedCanonicalFields: [IncumbentCanonicalFieldV1],
        release: IncumbentFileProfileReleaseV1
    ) throws -> Self {
        let expectedProjectionKind = expectedProjection.projectionKind
        let expectedCanonicalProjectionValues = try expectedProjection.canonicalProjectionValues()
        let expectedCanonicalProjectionSHA256 = try expectedProjection.canonicalProjectionSHA256()
        let expectedWorkspaceFrontier = try IncumbentAdapterWorkspaceFrontierV1(
            workspaceID: expectedWorkspaceID,
            workspaceRevision: expectedWorkspaceRevision
        )
        guard let privacyApproval,
              workspaceID == expectedWorkspaceID,
              workspaceRevision == expectedWorkspaceRevision,
              projectionKind == expectedProjectionKind,
              allowedCanonicalFields == expectedAllowedCanonicalFields,
              privacyApproval.workspaceFrontier == expectedWorkspaceFrontier,
              privacyApproval.canonicalProjectionValues == expectedCanonicalProjectionValues,
              privacyApproval.canonicalProjectionSHA256 == expectedCanonicalProjectionSHA256 else {
            throw IncumbentFileContractFailureV1.privacyApprovalRequired
        }
        let bound = try privacyApproval.revalidated(
            manifest: manifest, review: review, policy: policy,
            expectedProjection: expectedProjection,
            workspaceID: expectedWorkspaceID,
            workspaceRevision: expectedWorkspaceRevision,
            allowedCanonicalFields: expectedAllowedCanonicalFields
        )
        let rebuilt = try Self(operationID: operationID, workspaceID: workspaceID,
            workspaceRevision: workspaceRevision, release: release, direction: direction,
            allowedCanonicalFields: allowedCanonicalFields, privacyApproval: bound)
        guard rebuilt == self else { throw IncumbentFileContractFailureV1.invalidDigest }
        return rebuilt
    }

    private struct Basis: Codable {
        let schemaVersion: Int; let operationID: UUID; let workspaceID: WorkspaceID
        let workspaceRevision: UInt64; let releaseID: UUID; let releaseSHA256: String
        let direction: IncumbentFileDirectionV1; let allowedCanonicalFields: [IncumbentCanonicalFieldV1]
        let privacyApproval: IncumbentPrivacyApprovalReferenceV1?
    }
}

struct IncumbentMappingPreviewV1: Codable, Equatable, Sendable {
    let scopeSHA256: String; let inputSHA256: String; let mappingManifestSHA256: String
    let rowCount: Int; let includedFields: [IncumbentCanonicalFieldV1]
    let omittedFields: [IncumbentCanonicalFieldV1]
    let unresolvedStableKeys: [String]; let previewSHA256: String

    init(scope: IncumbentExchangeScopeV1, inputSHA256: String,
         release: IncumbentFileProfileReleaseV1, rowCount: Int,
         unresolvedStableKeys: [String] = []) throws {
        try IncumbentFileContractV1.requireDigest(inputSHA256); try release.validate()
        let all = release.mappingManifest.mappings.map(\.canonicalField)
            .sorted(by: { $0.rawValue < $1.rawValue })
        guard scope.releaseID == release.releaseID, scope.releaseSHA256 == release.releaseSHA256,
              rowCount > 0, rowCount <= release.budget.maximumRowCount,
              unresolvedStableKeys == unresolvedStableKeys.sorted(),
              Set(unresolvedStableKeys).count == unresolvedStableKeys.count,
              unresolvedStableKeys.allSatisfy({
                  (try? IncumbentFileContractV1.requireToken($0, maximumBytes: 256)) != nil
              }) else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        scopeSHA256 = scope.scopeSHA256; self.inputSHA256 = inputSHA256
        mappingManifestSHA256 = release.mappingManifest.manifestSHA256; self.rowCount = rowCount
        includedFields = scope.allowedCanonicalFields
        omittedFields = all.filter { !scope.allowedCanonicalFields.contains($0) }
        self.unresolvedStableKeys = unresolvedStableKeys
        previewSHA256 = try IncumbentFileContractV1.digest(Basis(
            scopeSHA256: scope.scopeSHA256, inputSHA256: inputSHA256,
            mappingManifestSHA256: release.mappingManifest.manifestSHA256,
            rowCount: rowCount, includedFields: includedFields, omittedFields: omittedFields,
            unresolvedStableKeys: unresolvedStableKeys))
    }
    func validate(scope: IncumbentExchangeScopeV1,
                  release: IncumbentFileProfileReleaseV1) throws {
        guard self == (try Self(scope: scope, inputSHA256: inputSHA256, release: release,
            rowCount: rowCount, unresolvedStableKeys: unresolvedStableKeys)) else {
            throw IncumbentFileContractFailureV1.invalidDigest
        }
    }
    private struct Basis: Codable { let scopeSHA256:String;let inputSHA256:String;let mappingManifestSHA256:String;let rowCount:Int;let includedFields:[IncumbentCanonicalFieldV1];let omittedFields:[IncumbentCanonicalFieldV1];let unresolvedStableKeys:[String] }
}

enum IncumbentQuarantineReasonV1: String, Codable, CaseIterable, Hashable, Sendable {
    case unsupportedVersion = "UNSUPPORTED_VERSION"; case headerMismatch = "HEADER_MISMATCH"
    case encodingRejected = "ENCODING_REJECTED"; case budgetExceeded = "BUDGET_EXCEEDED"
    case ambiguousStableKey = "AMBIGUOUS_STABLE_KEY"; case sourceChanged = "SOURCE_CHANGED"
    case privacyViolation = "PRIVACY_VIOLATION"; case divergentRecovery = "DIVERGENT_RECOVERY"
}

struct IncumbentFileQuarantineReceiptV1: Codable, Equatable, Sendable {
    let operationID: UUID; let inputSHA256: String; let releaseSHA256: String?
    let reason: IncumbentQuarantineReasonV1; let canonicalEffectOccurred: Bool
    let quarantinedAt: Date; let receiptSHA256: String
    init(operationID: UUID, inputSHA256: String, releaseSHA256: String?,
         reason: IncumbentQuarantineReasonV1, quarantinedAt: Date) throws {
        try IncumbentFileContractV1.requireID(operationID); try IncumbentFileContractV1.requireDigest(inputSHA256)
        if let releaseSHA256 { try IncumbentFileContractV1.requireDigest(releaseSHA256) }
        guard quarantinedAt.timeIntervalSinceReferenceDate.isFinite else { throw IncumbentFileContractFailureV1.invalidValue }
        self.operationID = operationID; self.inputSHA256 = inputSHA256; self.releaseSHA256 = releaseSHA256
        self.reason = reason; canonicalEffectOccurred = false; self.quarantinedAt = quarantinedAt
        receiptSHA256 = try IncumbentFileContractV1.digest(Basis(operationID: operationID,
            inputSHA256: inputSHA256, releaseSHA256: releaseSHA256, reason: reason,
            canonicalEffectOccurred: false, quarantinedAt: quarantinedAt))
    }
    func validate() throws {
        guard self == (try Self(operationID: operationID, inputSHA256: inputSHA256,
            releaseSHA256: releaseSHA256, reason: reason, quarantinedAt: quarantinedAt)) else {
            throw IncumbentFileContractFailureV1.invalidDigest
        }
    }
    private struct Basis: Codable { let operationID:UUID;let inputSHA256:String;let releaseSHA256:String?;let reason:IncumbentQuarantineReasonV1;let canonicalEffectOccurred:Bool;let quarantinedAt:Date }
}

enum IncumbentExternalAvailabilityV1: String, Codable, CaseIterable, Hashable, Sendable {
    case notAttempted = "NOT_ATTEMPTED"; case fileCreatedLocally = "FILE_CREATED_LOCALLY"
    case unknownAfterCallbackLoss = "EXTERNAL_AVAILABILITY_UNKNOWN"
}

struct IncumbentCanonicalMutationReceiptReferenceV1: Codable, Equatable, Sendable {
    private enum AuthorityBindingV1: Equatable, Sendable { case bound, unbound }

    let workspaceID: WorkspaceID; let mutationID: MutationIDV1
    let commandBodySHA256: String; let envelopeSHA256: String; let receiptSHA256: String
    let expectedPlanSHA256: String
    private let authorityBinding: AuthorityBindingV1

    init(receipt: MutationReceiptV1, plan: IncumbentExchangeRecoveryPlanV1) throws {
        try receipt.validate(); try plan.validate()
        guard receipt.identity.workspaceID == plan.workspaceID,
              receipt.mutationID == plan.expectedMutationID,
              receipt.commandBodySHA256 == plan.expectedCommandBodySHA256 else {
            throw IncumbentFileContractFailureV1.divergentRecovery
        }
        workspaceID = receipt.identity.workspaceID; mutationID = receipt.mutationID
        commandBodySHA256 = receipt.commandBodySHA256; envelopeSHA256 = receipt.envelopeSHA256
        receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(receipt)
        expectedPlanSHA256 = plan.planSHA256
        authorityBinding = .bound
        try validate(plan: plan)
    }

    func validate() throws {
        try IncumbentFileContractV1.requireDigest(commandBodySHA256)
        try IncumbentFileContractV1.requireDigest(envelopeSHA256)
        try IncumbentFileContractV1.requireDigest(receiptSHA256)
        try IncumbentFileContractV1.requireDigest(expectedPlanSHA256)
    }

    func validate(plan: IncumbentExchangeRecoveryPlanV1) throws {
        try validate(); try plan.validate(); try requireAuthoritativelyBound()
        guard workspaceID == plan.workspaceID,
              mutationID == plan.expectedMutationID,
              commandBodySHA256 == plan.expectedCommandBodySHA256,
              expectedPlanSHA256 == plan.planSHA256 else {
            throw IncumbentFileContractFailureV1.divergentRecovery
        }
    }

    func requireAuthoritativelyBound() throws {
        guard authorityBinding == .bound else {
            throw IncumbentFileContractFailureV1.divergentRecovery
        }
    }

    func revalidated(receipt: MutationReceiptV1,
                     plan: IncumbentExchangeRecoveryPlanV1) throws -> Self {
        let authoritative = try Self(receipt: receipt, plan: plan)
        guard self == authoritative else {
            throw IncumbentFileContractFailureV1.divergentRecovery
        }
        return authoritative
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.workspaceID == rhs.workspaceID && lhs.mutationID == rhs.mutationID
            && lhs.commandBodySHA256 == rhs.commandBodySHA256
            && lhs.envelopeSHA256 == rhs.envelopeSHA256
            && lhs.receiptSHA256 == rhs.receiptSHA256
            && lhs.expectedPlanSHA256 == rhs.expectedPlanSHA256
    }

    private enum CodingKeys: String, CodingKey {
        case workspaceID, mutationID, commandBodySHA256, envelopeSHA256, receiptSHA256
        case expectedPlanSHA256
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        workspaceID = try values.decode(WorkspaceID.self, forKey: .workspaceID)
        mutationID = try values.decode(MutationIDV1.self, forKey: .mutationID)
        commandBodySHA256 = try values.decode(String.self, forKey: .commandBodySHA256)
        envelopeSHA256 = try values.decode(String.self, forKey: .envelopeSHA256)
        receiptSHA256 = try values.decode(String.self, forKey: .receiptSHA256)
        expectedPlanSHA256 = try values.decode(String.self, forKey: .expectedPlanSHA256)
        authorityBinding = .unbound
        try validate()
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(workspaceID, forKey: .workspaceID)
        try values.encode(mutationID, forKey: .mutationID)
        try values.encode(commandBodySHA256, forKey: .commandBodySHA256)
        try values.encode(envelopeSHA256, forKey: .envelopeSHA256)
        try values.encode(receiptSHA256, forKey: .receiptSHA256)
        try values.encode(expectedPlanSHA256, forKey: .expectedPlanSHA256)
    }
}

enum IncumbentExchangeOutcomeV1: String, Codable, CaseIterable, Hashable, Sendable {
    case previewedZeroWrite = "PREVIEWED_ZERO_WRITE"; case importedCanonical = "IMPORTED_CANONICAL"
    case exportedLocalFile = "EXPORTED_LOCAL_FILE"; case cancelled = "CANCELLED"
    case exportAvailabilityUnknown = "EXPORT_AVAILABILITY_UNKNOWN"
    case quarantined = "QUARANTINED"; case failedNoEffect = "FAILED_NO_EFFECT"
}

struct IncumbentFileExportManifestV1: Codable, Equatable, Sendable {
    let operationID: UUID; let scopeSHA256: String; let releaseSHA256: String
    let outputSHA256: String; let outputByteCount: UInt64; let rowCount: Int
    let includedFields: [IncumbentCanonicalFieldV1]
    let omittedFields: [IncumbentCanonicalFieldV1]; let manifestSHA256: String
    init(scope: IncumbentExchangeScopeV1, release: IncumbentFileProfileReleaseV1,
         output: Data, rowCount: Int) throws {
        guard scope.releaseID == release.releaseID, scope.releaseSHA256 == release.releaseSHA256,
              release.direction.permitsExport, UInt64(output.count) <= release.budget.maximumByteCount,
              rowCount > 0, rowCount <= release.budget.maximumRowCount else {
            throw IncumbentFileContractFailureV1.budgetExceeded
        }
        operationID = scope.operationID; scopeSHA256 = scope.scopeSHA256; releaseSHA256 = release.releaseSHA256
        outputSHA256 = CanonicalJSONV1.sha256(output); outputByteCount = UInt64(output.count); self.rowCount = rowCount
        includedFields = scope.allowedCanonicalFields
        omittedFields = release.mappingManifest.mappings.map(\.canonicalField)
            .sorted(by: { $0.rawValue < $1.rawValue })
            .filter { !scope.allowedCanonicalFields.contains($0) }
        manifestSHA256 = try IncumbentFileContractV1.digest(Basis(operationID: operationID,
            scopeSHA256: scopeSHA256, releaseSHA256: releaseSHA256, outputSHA256: outputSHA256,
            outputByteCount: outputByteCount, rowCount: rowCount,
            includedFields: includedFields, omittedFields: omittedFields))
    }
    func validate(scope: IncumbentExchangeScopeV1, release: IncumbentFileProfileReleaseV1,
                  output: Data) throws {
        guard self == (try Self(scope: scope, release: release, output: output,
            rowCount: rowCount)) else { throw IncumbentFileContractFailureV1.invalidDigest }
    }
    private struct Basis: Codable { let operationID:UUID;let scopeSHA256:String;let releaseSHA256:String;let outputSHA256:String;let outputByteCount:UInt64;let rowCount:Int;let includedFields:[IncumbentCanonicalFieldV1];let omittedFields:[IncumbentCanonicalFieldV1] }
}

enum IncumbentDelimitedTextSafetyV1 {
    static func versionColumnIndex(release: IncumbentFileProfileReleaseV1) throws -> Int {
        guard let index = release.orderedHeaders.firstIndex(of: release.versionHeader) else {
            throw IncumbentFileContractFailureV1.unsupportedVersion
        }
        return index
    }

    static func validateInputBytes(_ data: Data,
                                   release: IncumbentFileProfileReleaseV1) throws -> [[String]] {
        try validate(data, release: release, expectedDataRows: nil)
    }

    static func validateRenderedBytes(_ data: Data, release: IncumbentFileProfileReleaseV1,
                                      expectedDataRows: Int) throws {
        _ = try validate(data, release: release, expectedDataRows: expectedDataRows)
    }

    private static func validate(_ data: Data, release: IncumbentFileProfileReleaseV1,
                                 expectedDataRows: Int?) throws -> [[String]] {
        guard !data.isEmpty, UInt64(data.count) <= release.budget.maximumByteCount,
              let text = String(data: data, encoding: .utf8), Data(text.utf8) == data,
              text == text.precomposedStringWithCanonicalMapping,
              text.unicodeScalars.allSatisfy({ scalar in
                  let allowedLayoutControl = scalar.value == 0x09
                    || scalar.value == 0x0a || scalar.value == 0x0d
                  return allowedLayoutControl
                    || (!CharacterSet.controlCharacters.contains(scalar)
                        && ![0x202a, 0x202b, 0x202c, 0x202d, 0x202e,
                             0x2066, 0x2067, 0x2068, 0x2069].contains(scalar.value))
              }) else { throw IncumbentFileContractFailureV1.unsupportedVersion }
        let rows = try parse(text, delimiter: release.delimiter.scalar)
        guard rows.count >= 2, rows.count - 1 <= release.budget.maximumRowCount,
              expectedDataRows.map({ rows.count == $0 + 1 }) ?? true,
              rows.first == release.orderedHeaders,
              Set(rows[0]).count == rows[0].count,
              rows.allSatisfy({
                  $0.count == release.orderedHeaders.count
                    && $0.count <= release.budget.maximumColumnCount
                    && $0.allSatisfy({ $0.unicodeScalars.count <= release.budget.maximumScalarCountPerCell })
              }) else { throw IncumbentFileContractFailureV1.headerMismatch }
        let versionIndex = try versionColumnIndex(release: release)
        guard rows.dropFirst().allSatisfy({ $0[versionIndex] == release.versionValue }) else {
            throw IncumbentFileContractFailureV1.unsupportedVersion
        }
        for cell in rows.dropFirst().flatMap({ $0 }) {
            let trimmed = cell.drop(while: { $0.isWhitespace })
            if let first = trimmed.first, "=+-@".contains(first) {
                throw IncumbentFileContractFailureV1.invalidValue
            }
        }
        return rows
    }

    private static func parse(_ text: String, delimiter: UnicodeScalar) throws -> [[String]] {
        var rows: [[String]] = []; var row: [String] = []; var field = ""
        var quoted = false; var atFieldStart = true; var justClosedQuote = false
        var index = text.startIndex
        func finishField() {
            row.append(field); field.removeAll(keepingCapacity: true)
            atFieldStart = true; justClosedQuote = false
        }
        func finishRow() { finishField(); rows.append(row); row.removeAll(keepingCapacity: true) }
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                let next = text.index(after: index)
                if quoted, next < text.endIndex, text[next] == "\"" {
                    field.append("\""); index = text.index(after: next); continue
                }
                if quoted {
                    quoted = false; justClosedQuote = true; index = next; continue
                }
                guard atFieldStart, !justClosedQuote else {
                    throw IncumbentFileContractFailureV1.headerMismatch
                }
                quoted = true; atFieldStart = false; index = next; continue
            }
            if !quoted, character.unicodeScalars.count == 1,
               character.unicodeScalars.first == delimiter {
                finishField(); index = text.index(after: index); continue
            }
            if !quoted, character == "\n" {
                finishRow(); index = text.index(after: index); continue
            }
            if !quoted, character == "\r" {
                let next = text.index(after: index)
                guard next < text.endIndex, text[next] == "\n" else {
                    throw IncumbentFileContractFailureV1.headerMismatch
                }
                finishRow(); index = text.index(after: next); continue
            }
            guard !justClosedQuote else { throw IncumbentFileContractFailureV1.headerMismatch }
            atFieldStart = false
            field.append(character); index = text.index(after: index)
        }
        guard !quoted else { throw IncumbentFileContractFailureV1.headerMismatch }
        if !field.isEmpty || !row.isEmpty { finishRow() }
        return rows
    }
}

struct IncumbentFileExchangeReceiptV1: Codable, Equatable, Sendable {
    let operationID: UUID; let workspaceID: WorkspaceID; let releaseSHA256: String
    let scopeSHA256: String; let inputOrOutputSHA256: String; let previewSHA256: String?
    let outcome: IncumbentExchangeOutcomeV1; let canonicalMutation: IncumbentCanonicalMutationReceiptReferenceV1?
    let externalAvailability: IncumbentExternalAvailabilityV1; let occurredAt: Date; let receiptSHA256: String

    init(scope: IncumbentExchangeScopeV1, release: IncumbentFileProfileReleaseV1,
         inputOrOutputSHA256: String, previewSHA256: String?, outcome: IncumbentExchangeOutcomeV1,
         canonicalMutation: IncumbentCanonicalMutationReceiptReferenceV1?,
         recoveryPlan: IncumbentExchangeRecoveryPlanV1? = nil,
         externalAvailability: IncumbentExternalAvailabilityV1, occurredAt: Date) throws {
        try IncumbentFileContractV1.requireDigest(inputOrOutputSHA256)
        if let previewSHA256 { try IncumbentFileContractV1.requireDigest(previewSHA256) }
        let linkageIsValid: Bool
        switch outcome {
        case .importedCanonical:
            guard let canonicalMutation, let recoveryPlan else {
                throw IncumbentFileContractFailureV1.divergentRecovery
            }
            try canonicalMutation.validate(plan: recoveryPlan)
            linkageIsValid = canonicalMutation.workspaceID == scope.workspaceID
                && recoveryPlan.operationID == scope.operationID
                && recoveryPlan.workspaceID == scope.workspaceID
                && recoveryPlan.scopeSHA256 == scope.scopeSHA256
                && recoveryPlan.sourceSHA256 == inputOrOutputSHA256
                && recoveryPlan.previewSHA256 == previewSHA256
                && recoveryPlan.mappingManifestSHA256 == release.mappingManifest.manifestSHA256
                && previewSHA256 != nil && externalAvailability == .notAttempted
        case .exportedLocalFile:
            linkageIsValid = canonicalMutation == nil && recoveryPlan == nil
                && externalAvailability == .fileCreatedLocally
        case .cancelled:
            linkageIsValid = canonicalMutation == nil && recoveryPlan == nil
                && externalAvailability == .notAttempted
        case .exportAvailabilityUnknown:
            linkageIsValid = canonicalMutation == nil && recoveryPlan == nil
                && externalAvailability == .unknownAfterCallbackLoss
        case .previewedZeroWrite, .quarantined, .failedNoEffect:
            linkageIsValid = canonicalMutation == nil && recoveryPlan == nil
                && externalAvailability == .notAttempted
        }
        guard scope.releaseSHA256 == release.releaseSHA256,
              occurredAt.timeIntervalSinceReferenceDate.isFinite,
              linkageIsValid else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        operationID = scope.operationID; workspaceID = scope.workspaceID; releaseSHA256 = release.releaseSHA256
        scopeSHA256 = scope.scopeSHA256; self.inputOrOutputSHA256 = inputOrOutputSHA256
        self.previewSHA256 = previewSHA256; self.outcome = outcome; self.canonicalMutation = canonicalMutation
        self.externalAvailability = externalAvailability; self.occurredAt = occurredAt
        receiptSHA256 = try IncumbentFileContractV1.digest(Basis(operationID: operationID,
            workspaceID: workspaceID, releaseSHA256: releaseSHA256, scopeSHA256: scopeSHA256,
            inputOrOutputSHA256: inputOrOutputSHA256, previewSHA256: previewSHA256,
            outcome: outcome, canonicalMutation: canonicalMutation,
            externalAvailability: externalAvailability, occurredAt: occurredAt))
    }
    func validate(scope: IncumbentExchangeScopeV1,
                  release: IncumbentFileProfileReleaseV1,
                  recoveryPlan: IncumbentExchangeRecoveryPlanV1? = nil) throws {
        guard self == (try Self(scope: scope, release: release,
            inputOrOutputSHA256: inputOrOutputSHA256, previewSHA256: previewSHA256,
            outcome: outcome, canonicalMutation: canonicalMutation,
            recoveryPlan: recoveryPlan,
            externalAvailability: externalAvailability, occurredAt: occurredAt)) else {
            throw IncumbentFileContractFailureV1.invalidDigest
        }
    }

    func revalidated(scope: IncumbentExchangeScopeV1,
                     release: IncumbentFileProfileReleaseV1,
                     receipt: MutationReceiptV1?,
                     plan: IncumbentExchangeRecoveryPlanV1?) throws -> Self {
        switch outcome {
        case .importedCanonical:
            guard let canonicalMutation, let receipt, let plan else {
                throw IncumbentFileContractFailureV1.divergentRecovery
            }
            let authoritative = try canonicalMutation.revalidated(receipt: receipt, plan: plan)
            let revalidated = try Self(scope: scope, release: release,
                inputOrOutputSHA256: inputOrOutputSHA256, previewSHA256: previewSHA256,
                outcome: outcome, canonicalMutation: authoritative, recoveryPlan: plan,
                externalAvailability: externalAvailability, occurredAt: occurredAt)
            guard self == revalidated else {
                throw IncumbentFileContractFailureV1.invalidDigest
            }
            return revalidated
        default:
            guard receipt == nil, plan == nil else {
                throw IncumbentFileContractFailureV1.divergentRecovery
            }
            let revalidated = try Self(scope: scope, release: release,
                inputOrOutputSHA256: inputOrOutputSHA256, previewSHA256: previewSHA256,
                outcome: outcome, canonicalMutation: nil, recoveryPlan: nil,
                externalAvailability: externalAvailability, occurredAt: occurredAt)
            guard self == revalidated else {
                throw IncumbentFileContractFailureV1.invalidDigest
            }
            return revalidated
        }
    }
    private struct Basis: Codable { let operationID:UUID;let workspaceID:WorkspaceID;let releaseSHA256:String;let scopeSHA256:String;let inputOrOutputSHA256:String;let previewSHA256:String?;let outcome:IncumbentExchangeOutcomeV1;let canonicalMutation:IncumbentCanonicalMutationReceiptReferenceV1?;let externalAvailability:IncumbentExternalAvailabilityV1;let occurredAt:Date }
}

enum IncumbentExchangeRecoveryDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case beforeCanonicalEffect = "BEFORE_CANONICAL_EFFECT"; case appliedMatchingReceipt = "APPLIED_MATCHING_RECEIPT"
    case cleanupOnly = "CLEANUP_ONLY"; case divergentQuarantined = "DIVERGENT_QUARANTINED"
}

struct IncumbentExchangeRecoveryPlanV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let operationID: UUID; let workspaceID: WorkspaceID
    let sourceSHA256: String; let scopeSHA256: String; let previewSHA256: String
    let mappingManifestSHA256: String; let expectedMutationID: MutationIDV1
    let expectedCommandBodySHA256: String; let cleanupIdentitySHA256: String
    let planSHA256: String

    init(operationID: UUID, workspaceID: WorkspaceID, sourceSHA256: String,
         scope: IncumbentExchangeScopeV1, preview: IncumbentMappingPreviewV1,
         mappingManifestSHA256: String, expectedMutationID: MutationIDV1,
         expectedCommandBodySHA256: String, cleanupIdentitySHA256: String) throws {
        try IncumbentFileContractV1.requireID(operationID)
        try [sourceSHA256, mappingManifestSHA256, expectedCommandBodySHA256,
             cleanupIdentitySHA256].forEach { try IncumbentFileContractV1.requireDigest($0) }
        guard operationID == scope.operationID, workspaceID == scope.workspaceID,
              preview.scopeSHA256 == scope.scopeSHA256,
              preview.inputSHA256 == sourceSHA256,
              preview.mappingManifestSHA256 == mappingManifestSHA256 else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion; self.operationID = operationID
        self.workspaceID = workspaceID; self.sourceSHA256 = sourceSHA256
        scopeSHA256 = scope.scopeSHA256; previewSHA256 = preview.previewSHA256
        self.mappingManifestSHA256 = mappingManifestSHA256
        self.expectedMutationID = expectedMutationID
        self.expectedCommandBodySHA256 = expectedCommandBodySHA256
        self.cleanupIdentitySHA256 = cleanupIdentitySHA256
        planSHA256 = try IncumbentFileContractV1.digest(Basis(schemaVersion: Self.schemaVersion,
            operationID: operationID, workspaceID: workspaceID, sourceSHA256: sourceSHA256,
            scopeSHA256: scope.scopeSHA256, previewSHA256: preview.previewSHA256,
            mappingManifestSHA256: mappingManifestSHA256, expectedMutationID: expectedMutationID,
            expectedCommandBodySHA256: expectedCommandBodySHA256,
            cleanupIdentitySHA256: cleanupIdentitySHA256))
    }
    func validate() throws {
        try [sourceSHA256, scopeSHA256, previewSHA256, mappingManifestSHA256,
             expectedCommandBodySHA256, cleanupIdentitySHA256, planSHA256]
            .forEach { try IncumbentFileContractV1.requireDigest($0) }
        let digest = try IncumbentFileContractV1.digest(Basis(schemaVersion: schemaVersion,
            operationID: operationID, workspaceID: workspaceID, sourceSHA256: sourceSHA256,
            scopeSHA256: scopeSHA256, previewSHA256: previewSHA256,
            mappingManifestSHA256: mappingManifestSHA256, expectedMutationID: expectedMutationID,
            expectedCommandBodySHA256: expectedCommandBodySHA256,
            cleanupIdentitySHA256: cleanupIdentitySHA256))
        guard schemaVersion == Self.schemaVersion, digest == planSHA256 else {
            throw IncumbentFileContractFailureV1.invalidDigest
        }
    }
    private struct Basis: Codable {
        let schemaVersion:Int;let operationID:UUID;let workspaceID:WorkspaceID
        let sourceSHA256:String;let scopeSHA256:String;let previewSHA256:String
        let mappingManifestSHA256:String;let expectedMutationID:MutationIDV1
        let expectedCommandBodySHA256:String;let cleanupIdentitySHA256:String
    }
}

struct IncumbentCleanupEvidenceV1: Codable, Equatable, Sendable {
    let operationID: UUID; let sourceSHA256: String; let cleanupIdentitySHA256: String
    let cleanedAt: Date; let evidenceSHA256: String
    init(operationID: UUID, sourceSHA256: String, cleanupIdentitySHA256: String,
         cleanedAt: Date) throws {
        try IncumbentFileContractV1.requireID(operationID)
        try IncumbentFileContractV1.requireDigest(sourceSHA256)
        try IncumbentFileContractV1.requireDigest(cleanupIdentitySHA256)
        guard cleanedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        self.operationID=operationID;self.sourceSHA256=sourceSHA256
        self.cleanupIdentitySHA256=cleanupIdentitySHA256;self.cleanedAt=cleanedAt
        evidenceSHA256=try IncumbentFileContractV1.digest(Basis(operationID:operationID,
            sourceSHA256:sourceSHA256,cleanupIdentitySHA256:cleanupIdentitySHA256,cleanedAt:cleanedAt))
    }
    func validate(plan: IncumbentExchangeRecoveryPlanV1) throws {
        let rebuilt = try Self(operationID: operationID, sourceSHA256: sourceSHA256,
            cleanupIdentitySHA256: cleanupIdentitySHA256, cleanedAt: cleanedAt)
        guard self == rebuilt, operationID == plan.operationID,
              sourceSHA256 == plan.sourceSHA256,
              cleanupIdentitySHA256 == plan.cleanupIdentitySHA256 else {
            throw IncumbentFileContractFailureV1.divergentRecovery
        }
    }
    private struct Basis:Codable{let operationID:UUID;let sourceSHA256:String;let cleanupIdentitySHA256:String;let cleanedAt:Date}
}

struct IncumbentExchangeRecoveryReceiptV1: Codable, Equatable, Sendable {
    let operationID: UUID; let workspaceID: WorkspaceID; let expectedPlanSHA256: String
    let expectedSourceSHA256: String; let observedSourceSHA256: String
    let observedReceiptSHA256: String?; let cleanupEvidenceSHA256: String?
    let disposition: IncumbentExchangeRecoveryDispositionV1; let canonicalReapplyOccurred: Bool
    let recoveryReceiptSHA256: String
    init(plan: IncumbentExchangeRecoveryPlanV1, observedSourceSHA256: String,
         observedReceiptSHA256: String?, cleanupEvidenceSHA256: String?,
         disposition: IncumbentExchangeRecoveryDispositionV1) throws {
        try plan.validate(); try IncumbentFileContractV1.requireDigest(observedSourceSHA256)
        if let observedReceiptSHA256 { try IncumbentFileContractV1.requireDigest(observedReceiptSHA256) }
        if let cleanupEvidenceSHA256 { try IncumbentFileContractV1.requireDigest(cleanupEvidenceSHA256) }
        let sourceMatches = observedSourceSHA256 == plan.sourceSHA256
        let linkage: Bool
        switch disposition {
        case .beforeCanonicalEffect:
            linkage = sourceMatches && observedReceiptSHA256 == nil && cleanupEvidenceSHA256 == nil
        case .appliedMatchingReceipt:
            linkage = sourceMatches && observedReceiptSHA256 != nil && cleanupEvidenceSHA256 == nil
        case .cleanupOnly:
            linkage = sourceMatches && observedReceiptSHA256 != nil && cleanupEvidenceSHA256 != nil
        case .divergentQuarantined:
            linkage = !sourceMatches || observedReceiptSHA256 != nil || cleanupEvidenceSHA256 != nil
        }
        guard linkage else {
            throw IncumbentFileContractFailureV1.divergentRecovery
        }
        operationID=plan.operationID;workspaceID=plan.workspaceID;expectedPlanSHA256=plan.planSHA256
        expectedSourceSHA256=plan.sourceSHA256;self.observedSourceSHA256=observedSourceSHA256
        self.observedReceiptSHA256=observedReceiptSHA256;self.cleanupEvidenceSHA256=cleanupEvidenceSHA256
        self.disposition = disposition
        canonicalReapplyOccurred = false
        recoveryReceiptSHA256 = try IncumbentFileContractV1.digest(Basis(
            operationID: plan.operationID, workspaceID: plan.workspaceID,
            expectedPlanSHA256: plan.planSHA256, expectedSourceSHA256: plan.sourceSHA256,
            observedSourceSHA256: observedSourceSHA256,
            observedReceiptSHA256: observedReceiptSHA256,
            cleanupEvidenceSHA256: cleanupEvidenceSHA256, disposition: disposition,
            canonicalReapplyOccurred: false))
    }
    func validate(plan: IncumbentExchangeRecoveryPlanV1) throws {
        guard self == (try Self(plan: plan, observedSourceSHA256: observedSourceSHA256,
            observedReceiptSHA256: observedReceiptSHA256,
            cleanupEvidenceSHA256: cleanupEvidenceSHA256, disposition: disposition)) else {
            throw IncumbentFileContractFailureV1.invalidDigest
        }
    }
    private struct Basis: Codable {
        let operationID:UUID;let workspaceID:WorkspaceID;let expectedPlanSHA256:String
        let expectedSourceSHA256:String;let observedSourceSHA256:String
        let observedReceiptSHA256:String?;let cleanupEvidenceSHA256:String?
        let disposition:IncumbentExchangeRecoveryDispositionV1;let canonicalReapplyOccurred:Bool
    }
}

enum IncumbentFileCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try WorkspaceMutationCanonicalV1.data(value)
    }

    private static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= 8_388_608 else {
            throw IncumbentFileContractFailureV1.budgetExceeded
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        guard try encode(value) == data else { throw IncumbentFileContractFailureV1.invalidDigest }
        return value
    }

    static func decodeRelease(from data: Data) throws -> IncumbentFileProfileReleaseV1 {
        let value = try decode(IncumbentFileProfileReleaseV1.self, from: data)
        try value.validate(); return value
    }
    static func decodeMappingManifest(from data: Data) throws -> IncumbentMappingManifestV1 {
        let value = try decode(IncumbentMappingManifestV1.self, from: data)
        try value.validate(); return value
    }
    static func decodeSelection(from data: Data,
                                releases: [IncumbentFileProfileReleaseV1]) throws
        -> IncumbentSelectionReceiptV1 {
        let value = try decode(IncumbentSelectionReceiptV1.self, from: data)
        let release = releases.first {
            $0.releaseID == value.selectedReleaseID && $0.releaseSHA256 == value.selectedReleaseSHA256
        }
        try value.validate(selectedRelease: release); return value
    }
    static func decodeScope(from data: Data, release: IncumbentFileProfileReleaseV1) throws
        -> IncumbentExchangeScopeV1 {
        let value = try decode(IncumbentExchangeScopeV1.self, from: data)
        try value.validate(release: release); return value
    }
    static func decodeScope(
        from data: Data, release: IncumbentFileProfileReleaseV1,
        privacyManifest: PrivacyTransformManifestV1, privacyReview: PrivacyReviewReceiptV1,
        privacyPolicy: PrivacyTransformPolicyV1,
        expectedProjection: IncumbentAdapterProjectionPayloadV1,
        expectedWorkspaceID: WorkspaceID,
        expectedWorkspaceRevision: UInt64,
        expectedAllowedCanonicalFields: [IncumbentCanonicalFieldV1]
    ) throws -> IncumbentExchangeScopeV1 {
        let decoded = try decode(IncumbentExchangeScopeV1.self, from: data)
        return try decoded.revalidatedPrivacyAuthority(
            manifest: privacyManifest, review: privacyReview,
            policy: privacyPolicy,
            expectedProjection: expectedProjection,
            expectedWorkspaceID: expectedWorkspaceID,
            expectedWorkspaceRevision: expectedWorkspaceRevision,
            expectedAllowedCanonicalFields: expectedAllowedCanonicalFields,
            release: release
        )
    }
    static func decodePreview(from data: Data, scope: IncumbentExchangeScopeV1,
                              release: IncumbentFileProfileReleaseV1) throws
        -> IncumbentMappingPreviewV1 {
        let value = try decode(IncumbentMappingPreviewV1.self, from: data)
        try value.validate(scope: scope, release: release); return value
    }
    static func decodeQuarantine(from data: Data) throws -> IncumbentFileQuarantineReceiptV1 {
        let value = try decode(IncumbentFileQuarantineReceiptV1.self, from: data)
        try value.validate(); return value
    }
    static func decodeExportManifest(from data: Data, scope: IncumbentExchangeScopeV1,
                                     release: IncumbentFileProfileReleaseV1, output: Data) throws
        -> IncumbentFileExportManifestV1 {
        let value = try decode(IncumbentFileExportManifestV1.self, from: data)
        try value.validate(scope: scope, release: release, output: output); return value
    }
    static func decodeExchangeReceipt(from data: Data, scope: IncumbentExchangeScopeV1,
                                      release: IncumbentFileProfileReleaseV1,
                                      receipt: MutationReceiptV1? = nil,
                                      plan: IncumbentExchangeRecoveryPlanV1? = nil) throws
        -> IncumbentFileExchangeReceiptV1 {
        let value = try decode(IncumbentFileExchangeReceiptV1.self, from: data)
        return try value.revalidated(scope: scope, release: release,
                                     receipt: receipt, plan: plan)
    }
    static func decodeRecoveryPlan(from data: Data) throws -> IncumbentExchangeRecoveryPlanV1 {
        let value = try decode(IncumbentExchangeRecoveryPlanV1.self, from: data)
        try value.validate(); return value
    }
    static func decodeCleanup(from data: Data, plan: IncumbentExchangeRecoveryPlanV1) throws
        -> IncumbentCleanupEvidenceV1 {
        let value = try decode(IncumbentCleanupEvidenceV1.self, from: data)
        try value.validate(plan: plan); return value
    }
    static func decodeRecoveryReceipt(from data: Data, plan: IncumbentExchangeRecoveryPlanV1) throws
        -> IncumbentExchangeRecoveryReceiptV1 {
        let value = try decode(IncumbentExchangeRecoveryReceiptV1.self, from: data)
        try value.validate(plan: plan); return value
    }
}

protocol IncumbentFileAdapterV1: Sendable {
    var adapterID: UUID { get }
    var release: IncumbentFileProfileReleaseV1 { get }
    func detect(_ input: IncumbentFileInputV1) throws -> IncumbentFileDetectionV1
    func parse(_ input: IncumbentFileInputV1, detection: IncumbentFileDetectionV1) throws -> [IncumbentFileRowV1]
    func render(rows: [IncumbentFileRowV1], scope: IncumbentExchangeScopeV1) throws -> Data
}

extension IncumbentFileAdapterV1 {
    var adapterID: UUID { release.adapterID }
}
