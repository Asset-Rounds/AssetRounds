import Foundation

/// A rebuildable local preflight result. It is deliberately not canonical workspace truth.
enum OfflineReadinessManifestFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case limitExceeded
    case digestMismatch
    case nonCanonicalEncoding
}

enum OfflineReadinessManifestLifecycleV1 {
    static let schema = "OFFLINE_READINESS_V1"
    static let persistenceMode = "DERIVED_ONLY"
    static let migrationRequired = false
    static let backupRestoreRequired = false
    static let exportReportRequired = false
    static let downgradeDisposition = "DROP_AND_REBUILD"
    static let coldLaunchRequiresRebuild = true
    static let terminationRequiresRebuild = true
    static let rebootRequiresRebuild = true
}

enum OfflineReadinessStatusV1: String, CaseIterable, Codable, Hashable, Sendable {
    case ready = "READY"
    case blocked = "BLOCKED"
    case warning = "WARNING"
    case stale = "STALE"
}

enum OfflineReadinessRequirementCategoryV1: String, CaseIterable, Codable, Hashable, Sendable {
    case package = "PACKAGE"
    case selectedAsset = "SELECTED_ASSET"
    case guidance = "GUIDANCE"
    case fieldReference = "FIELD_REFERENCE"
    case content = "CONTENT"
    case protection = "PROTECTION"
    case storage = "STORAGE"
    case clock = "CLOCK"
    case binding = "BINDING"
}

enum OfflineReadinessRequirementStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case satisfied = "SATISFIED"
    case missing = "MISSING"
    case corrupt = "CORRUPT"
    case partial = "PARTIAL"
    case wrongWorkspace = "WRONG_WORKSPACE"
    case protectedDataUnavailable = "PROTECTED_DATA_UNAVAILABLE"
    case capacityUnavailable = "CAPACITY_UNAVAILABLE"
    case insufficientCapacity = "INSUFFICIENT_CAPACITY"
    case uncheckable = "UNCHECKABLE"
    case mismatch = "MISMATCH"
    case stale = "STALE"
}

enum OfflineReadinessReasonV1: String, CaseIterable, Codable, Hashable, Sendable {
    case packageMismatch = "PACKAGE_MISMATCH"
    case selectedAssetMismatch = "SELECTED_ASSET_MISMATCH"
    case guidanceReferenceMismatch = "GUIDANCE_REFERENCE_MISMATCH"
    case fieldReferenceUnavailable = "FIELD_REFERENCE_UNAVAILABLE"
    case missingMandatoryContent = "MISSING_MANDATORY_CONTENT"
    case missingOptionalContent = "MISSING_OPTIONAL_CONTENT"
    case corruptMandatoryContent = "CORRUPT_MANDATORY_CONTENT"
    case corruptOptionalContent = "CORRUPT_OPTIONAL_CONTENT"
    case partialMandatoryContent = "PARTIAL_MANDATORY_CONTENT"
    case partialOptionalContent = "PARTIAL_OPTIONAL_CONTENT"
    case wrongWorkspaceContent = "WRONG_WORKSPACE_CONTENT"
    case protectedDataUnavailable = "PROTECTED_DATA_UNAVAILABLE"
    case storageUncheckable = "STORAGE_UNCHECKABLE"
    case insufficientStorage = "INSUFFICIENT_STORAGE"
    case storageArithmeticOverflow = "STORAGE_ARITHMETIC_OVERFLOW"
    case clockUncheckable = "CLOCK_UNCHECKABLE"
    case clockOrTimeZoneChanged = "CLOCK_OR_TIME_ZONE_CHANGED"
    case sourceBindingDrift = "SOURCE_BINDING_DRIFT"
}

enum OfflineReadinessRemediationV1: String, CaseIterable, Codable, Hashable, Sendable {
    case rebuildPreflight = "REBUILD_PREFLIGHT"
    case restoreExactPackage = "RESTORE_EXACT_PACKAGE"
    case reselectAssets = "RESELECT_ASSETS"
    case restoreGuidance = "RESTORE_GUIDANCE"
    case restoreFieldReference = "RESTORE_FIELD_REFERENCE"
    case restoreExactContent = "RESTORE_EXACT_CONTENT"
    case unlockProtectedData = "UNLOCK_PROTECTED_DATA"
    case freeStorage = "FREE_STORAGE"
    case checkStorageAgain = "CHECK_STORAGE_AGAIN"
    case checkClockAndTimeZone = "CHECK_CLOCK_AND_TIME_ZONE"
}

enum OfflineReadinessManualFallbackV1: String, CaseIterable, Codable, Hashable, Sendable {
    case doNotStart = "DO_NOT_START"
    case deferFieldWork = "DEFER_FIELD_WORK"
    case useApprovedManualProcedure = "USE_APPROVED_MANUAL_PROCEDURE"
    case contactSupervisor = "CONTACT_SUPERVISOR"
}

enum OfflineReadinessContentObservationStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case present = "PRESENT"
    case missing = "MISSING"
    case corrupt = "CORRUPT"
    case partial = "PARTIAL"
    case uncheckable = "UNCHECKABLE"
}

enum OfflineReadinessClockStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case checked = "CHECKED"
    case changedSincePriorManifest = "CHANGED_SINCE_PRIOR_MANIFEST"
    case uncheckable = "UNCHECKABLE"
}

enum OfflineReadinessCapacityStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case checked = "CHECKED"
    case unavailable = "UNAVAILABLE"
}

enum OfflineReadinessManifestLimitsV1 {
    static let maximumAssets = 512
    static let maximumGuidanceReferences = 512
    static let maximumContentRequirements = 512
    static let maximumFieldReferences = 256
    static let maximumRequirementRows = 1_600
    static let maximumCanonicalBytes = 2 * 1_024 * 1_024
    static let maximumTokenBytes = 512
}

enum OfflineReadinessClosedCodingV1 {
    static func exact(_ decoder: Decoder, _ keys: [String]) throws {
        // Synthesized `Encodable` omits nil optionals. Required values still
        // use `decode(_:forKey:)` below; this closes unknown keys while keeping
        // canonical optional omission round-trippable.
        try KernelClosedCodingV1.require(decoder, keys: keys, required: [])
    }
}

func offlineReadinessTokenV1(_ value: String) -> Bool {
    !value.isEmpty && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
        && value.utf8.count <= OfflineReadinessManifestLimitsV1.maximumTokenBytes
        && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
}

private func offlineReadinessWorkspaceV1(_ id: WorkspaceID) -> String {
    id.rawValue.uuidString.lowercased()
}

struct OfflineReadinessContentRequirementV1: Codable, Equatable, Hashable, Sendable {
    let reference: ContentReferenceV1
    let mandatory: Bool

    init(reference: ContentReferenceV1, mandatory: Bool) throws {
        guard offlineReadinessTokenV1(reference.contentID) else {
            throw OfflineReadinessManifestFailureV1.invalidValue
        }
        self.reference = reference
        self.mandatory = mandatory
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case reference, mandatory }
    init(from decoder: Decoder) throws {
        try OfflineReadinessClosedCodingV1.exact(decoder, CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(reference: c.decode(ContentReferenceV1.self, forKey: .reference), mandatory: c.decode(Bool.self, forKey: .mandatory))
    }
}

struct OfflineReadinessContentObservationV1: Codable, Equatable, Hashable, Sendable {
    let contentID: String
    let workspaceID: String
    let state: OfflineReadinessContentObservationStateV1
    let observedSHA256: String?
    let observedByteLength: Int64?

    init(contentID: String, workspaceID: String, state: OfflineReadinessContentObservationStateV1, observedSHA256: String? = nil, observedByteLength: Int64? = nil) throws {
        guard offlineReadinessTokenV1(contentID), offlineReadinessTokenV1(workspaceID),
              observedSHA256.map(KernelCanonicalHashV1.validSHA256) ?? true,
              observedByteLength.map({ $0 >= 0 }) ?? true,
              state != .present || (observedSHA256 != nil && observedByteLength != nil) else {
            throw OfflineReadinessManifestFailureV1.invalidValue
        }
        self.contentID = contentID; self.workspaceID = workspaceID; self.state = state
        self.observedSHA256 = observedSHA256; self.observedByteLength = observedByteLength
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case contentID, workspaceID, state, observedSHA256, observedByteLength }
    init(from decoder: Decoder) throws {
        try OfflineReadinessClosedCodingV1.exact(decoder, CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(contentID: c.decode(String.self, forKey: .contentID), workspaceID: c.decode(String.self, forKey: .workspaceID), state: c.decode(OfflineReadinessContentObservationStateV1.self, forKey: .state), observedSHA256: try c.decodeIfPresent(String.self, forKey: .observedSHA256), observedByteLength: try c.decodeIfPresent(Int64.self, forKey: .observedByteLength))
    }
}

struct OfflineReadinessStorageObservationV1: Codable, Equatable, Hashable, Sendable {
    let capacityState: OfflineReadinessCapacityStateV1
    let availableBytes: Int64?
    let reservedBytes: Int64
    let operationReserveBytes: Int64

    init(capacityState: OfflineReadinessCapacityStateV1, availableBytes: Int64?, reservedBytes: Int64 = 0, operationReserveBytes: Int64 = 0) throws {
        guard reservedBytes >= 0, operationReserveBytes >= 0,
              availableBytes.map({ $0 >= 0 }) ?? true,
              (capacityState == .checked) == (availableBytes != nil) else {
            throw OfflineReadinessManifestFailureV1.invalidValue
        }
        self.capacityState = capacityState; self.availableBytes = availableBytes
        self.reservedBytes = reservedBytes; self.operationReserveBytes = operationReserveBytes
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case capacityState, availableBytes, reservedBytes, operationReserveBytes }
    init(from decoder: Decoder) throws {
        try OfflineReadinessClosedCodingV1.exact(decoder, CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(capacityState: c.decode(OfflineReadinessCapacityStateV1.self, forKey: .capacityState), availableBytes: try c.decodeIfPresent(Int64.self, forKey: .availableBytes), reservedBytes: c.decode(Int64.self, forKey: .reservedBytes), operationReserveBytes: c.decode(Int64.self, forKey: .operationReserveBytes))
    }
}

struct OfflineReadinessAccessObservationV1: Codable, Equatable, Hashable, Sendable {
    let protectedDataAvailable: Bool
    init(protectedDataAvailable: Bool) { self.protectedDataAvailable = protectedDataAvailable }
    private enum CodingKeys: String, CodingKey, CaseIterable { case protectedDataAvailable }
    init(from decoder: Decoder) throws {
        try OfflineReadinessClosedCodingV1.exact(decoder, CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(protectedDataAvailable: c.decode(Bool.self, forKey: .protectedDataAvailable))
    }
}

struct OfflineReadinessReferenceObservationV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: String
    let releaseID: UUID
    let releaseRevision: UInt64
    let releaseSHA256: String
    let manifestSHA256: String
    let bindingID: UUID
    let bindingRevision: UInt64
    let bindingSHA256: String
    let availability: FieldReferenceAvailabilityV1
    let missingContentIDs: [String]
    let readinessSHA256: String

    init(_ value: FieldReferenceOfflineReadinessV1) throws {
        try self.init(workspaceID: offlineReadinessWorkspaceV1(value.workspaceID), releaseID: value.releaseID, releaseRevision: value.releaseRevision, releaseSHA256: value.releaseSHA256, manifestSHA256: value.manifestSHA256, bindingID: value.bindingID, bindingRevision: value.bindingRevision, bindingSHA256: value.bindingSHA256, availability: value.availability, missingContentIDs: value.missingContentIDs, readinessSHA256: value.readinessSHA256)
    }

    init(workspaceID: String, releaseID: UUID, releaseRevision: UInt64, releaseSHA256: String, manifestSHA256: String, bindingID: UUID, bindingRevision: UInt64, bindingSHA256: String, availability: FieldReferenceAvailabilityV1, missingContentIDs: [String], readinessSHA256: String) throws {
        guard offlineReadinessTokenV1(workspaceID), releaseRevision > 0, bindingRevision > 0,
              KernelCanonicalHashV1.validSHA256(releaseSHA256), KernelCanonicalHashV1.validSHA256(manifestSHA256),
              KernelCanonicalHashV1.validSHA256(bindingSHA256), KernelCanonicalHashV1.validSHA256(readinessSHA256),
              missingContentIDs.count <= OfflineReadinessManifestLimitsV1.maximumContentRequirements,
              missingContentIDs == missingContentIDs.sorted(), Set(missingContentIDs).count == missingContentIDs.count,
              missingContentIDs.allSatisfy(offlineReadinessTokenV1) else { throw OfflineReadinessManifestFailureV1.invalidValue }
        self.workspaceID = workspaceID; self.releaseID = releaseID; self.releaseRevision = releaseRevision
        self.releaseSHA256 = releaseSHA256; self.manifestSHA256 = manifestSHA256; self.bindingID = bindingID
        self.bindingRevision = bindingRevision; self.bindingSHA256 = bindingSHA256; self.availability = availability
        self.missingContentIDs = missingContentIDs; self.readinessSHA256 = readinessSHA256
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case workspaceID, releaseID, releaseRevision, releaseSHA256, manifestSHA256, bindingID, bindingRevision, bindingSHA256, availability, missingContentIDs, readinessSHA256 }
    init(from decoder: Decoder) throws {
        try OfflineReadinessClosedCodingV1.exact(decoder, CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(workspaceID: c.decode(String.self, forKey: .workspaceID), releaseID: c.decode(UUID.self, forKey: .releaseID), releaseRevision: c.decode(UInt64.self, forKey: .releaseRevision), releaseSHA256: c.decode(String.self, forKey: .releaseSHA256), manifestSHA256: c.decode(String.self, forKey: .manifestSHA256), bindingID: c.decode(UUID.self, forKey: .bindingID), bindingRevision: c.decode(UInt64.self, forKey: .bindingRevision), bindingSHA256: c.decode(String.self, forKey: .bindingSHA256), availability: c.decode(FieldReferenceAvailabilityV1.self, forKey: .availability), missingContentIDs: c.decode([String].self, forKey: .missingContentIDs), readinessSHA256: c.decode(String.self, forKey: .readinessSHA256))
    }
}

/// The immutable identity/binding expected by this round. Availability belongs
/// only to an observed readback and can never manufacture a requirement.
struct OfflineReadinessFieldReferenceRequirementV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: String
    let releaseID: UUID
    let releaseRevision: UInt64
    let releaseSHA256: String
    let manifestSHA256: String
    let bindingID: UUID
    let bindingRevision: UInt64
    let bindingSHA256: String

    init(workspaceID: String, releaseID: UUID, releaseRevision: UInt64, releaseSHA256: String, manifestSHA256: String, bindingID: UUID, bindingRevision: UInt64, bindingSHA256: String) throws {
        guard offlineReadinessTokenV1(workspaceID), releaseRevision > 0, bindingRevision > 0,
              KernelCanonicalHashV1.validSHA256(releaseSHA256), KernelCanonicalHashV1.validSHA256(manifestSHA256),
              KernelCanonicalHashV1.validSHA256(bindingSHA256) else { throw OfflineReadinessManifestFailureV1.invalidValue }
        self.workspaceID = workspaceID; self.releaseID = releaseID; self.releaseRevision = releaseRevision
        self.releaseSHA256 = releaseSHA256; self.manifestSHA256 = manifestSHA256; self.bindingID = bindingID
        self.bindingRevision = bindingRevision; self.bindingSHA256 = bindingSHA256
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case workspaceID, releaseID, releaseRevision, releaseSHA256, manifestSHA256, bindingID, bindingRevision, bindingSHA256 }
    init(from decoder: Decoder) throws {
        try OfflineReadinessClosedCodingV1.exact(decoder, CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(workspaceID: c.decode(String.self, forKey: .workspaceID), releaseID: c.decode(UUID.self, forKey: .releaseID), releaseRevision: c.decode(UInt64.self, forKey: .releaseRevision), releaseSHA256: c.decode(String.self, forKey: .releaseSHA256), manifestSHA256: c.decode(String.self, forKey: .manifestSHA256), bindingID: c.decode(UUID.self, forKey: .bindingID), bindingRevision: c.decode(UInt64.self, forKey: .bindingRevision), bindingSHA256: c.decode(String.self, forKey: .bindingSHA256))
    }

    func matches(_ observation: OfflineReadinessReferenceObservationV1) -> Bool {
        workspaceID == observation.workspaceID && releaseID == observation.releaseID && releaseRevision == observation.releaseRevision
            && releaseSHA256 == observation.releaseSHA256 && manifestSHA256 == observation.manifestSHA256
            && bindingID == observation.bindingID && bindingRevision == observation.bindingRevision
            && bindingSHA256 == observation.bindingSHA256
    }
}

struct OfflineReadinessRequirementV1: Codable, Equatable, Hashable, Sendable {
    let requirementID: String
    let category: OfflineReadinessRequirementCategoryV1
    let mandatory: Bool
    let contentRole: ContentByteRoleV1?
    let expectedWorkspaceID: String?
    let expectedSHA256: String?
    let expectedByteLength: Int64?
    let observedWorkspaceID: String?
    let observedSHA256: String?
    let observedByteLength: Int64?
    let state: OfflineReadinessRequirementStateV1
    let reason: OfflineReadinessReasonV1?
    let remediation: OfflineReadinessRemediationV1?
    let manualFallback: OfflineReadinessManualFallbackV1?

    init(requirementID: String, category: OfflineReadinessRequirementCategoryV1, mandatory: Bool, contentRole: ContentByteRoleV1? = nil, expectedWorkspaceID: String? = nil, expectedSHA256: String? = nil, expectedByteLength: Int64? = nil, observedWorkspaceID: String? = nil, observedSHA256: String? = nil, observedByteLength: Int64? = nil, state: OfflineReadinessRequirementStateV1, reason: OfflineReadinessReasonV1? = nil, remediation: OfflineReadinessRemediationV1? = nil, manualFallback: OfflineReadinessManualFallbackV1? = nil) throws {
        guard offlineReadinessTokenV1(requirementID), expectedWorkspaceID.map(offlineReadinessTokenV1) ?? true,
              observedWorkspaceID.map(offlineReadinessTokenV1) ?? true, expectedSHA256.map(KernelCanonicalHashV1.validSHA256) ?? true,
              observedSHA256.map(KernelCanonicalHashV1.validSHA256) ?? true, expectedByteLength.map({ $0 >= 0 }) ?? true,
              observedByteLength.map({ $0 >= 0 }) ?? true,
              (state == .satisfied) == (reason == nil && remediation == nil && manualFallback == nil),
              state == .satisfied || (reason != nil && remediation != nil && manualFallback != nil) else {
            throw OfflineReadinessManifestFailureV1.invalidValue
        }
        self.requirementID = requirementID; self.category = category; self.mandatory = mandatory; self.contentRole = contentRole
        self.expectedWorkspaceID = expectedWorkspaceID; self.expectedSHA256 = expectedSHA256; self.expectedByteLength = expectedByteLength
        self.observedWorkspaceID = observedWorkspaceID; self.observedSHA256 = observedSHA256; self.observedByteLength = observedByteLength
        self.state = state; self.reason = reason; self.remediation = remediation; self.manualFallback = manualFallback
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case requirementID, category, mandatory, contentRole, expectedWorkspaceID, expectedSHA256, expectedByteLength, observedWorkspaceID, observedSHA256, observedByteLength, state, reason, remediation, manualFallback }
    init(from decoder: Decoder) throws {
        try OfflineReadinessClosedCodingV1.exact(decoder, CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(requirementID: c.decode(String.self, forKey: .requirementID), category: c.decode(OfflineReadinessRequirementCategoryV1.self, forKey: .category), mandatory: c.decode(Bool.self, forKey: .mandatory), contentRole: try c.decodeIfPresent(ContentByteRoleV1.self, forKey: .contentRole), expectedWorkspaceID: try c.decodeIfPresent(String.self, forKey: .expectedWorkspaceID), expectedSHA256: try c.decodeIfPresent(String.self, forKey: .expectedSHA256), expectedByteLength: try c.decodeIfPresent(Int64.self, forKey: .expectedByteLength), observedWorkspaceID: try c.decodeIfPresent(String.self, forKey: .observedWorkspaceID), observedSHA256: try c.decodeIfPresent(String.self, forKey: .observedSHA256), observedByteLength: try c.decodeIfPresent(Int64.self, forKey: .observedByteLength), state: c.decode(OfflineReadinessRequirementStateV1.self, forKey: .state), reason: try c.decodeIfPresent(OfflineReadinessReasonV1.self, forKey: .reason), remediation: try c.decodeIfPresent(OfflineReadinessRemediationV1.self, forKey: .remediation), manualFallback: try c.decodeIfPresent(OfflineReadinessManualFallbackV1.self, forKey: .manualFallback))
    }
}

struct OfflineReadinessManifestV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let schema: String
    let persistenceMode: String
    let session: RoundSessionReferenceV1
    let expectedPackage: RoundPackageReleaseReferenceV1
    let observedPackage: RoundPackageReleaseReferenceV1?
    let selectedAssets: [RoundAssetSelectionV1]
    let observedAssetIDs: [UUID]
    let guidanceReferenceIDs: [String]
    let availableGuidanceReferenceIDs: [String]
    let contentRequirements: [OfflineReadinessContentRequirementV1]
    let contentObservations: [OfflineReadinessContentObservationV1]
    let expectedFieldReferences: [OfflineReadinessFieldReferenceRequirementV1]
    let referenceObservations: [OfflineReadinessReferenceObservationV1]
    let requiredBytes: Int64?
    let availableBytes: Int64?
    let storage: OfflineReadinessStorageObservationV1
    let protectedDataAvailable: Bool
    let checkedAt: Date
    let timeZoneIdentifier: String
    let clockState: OfflineReadinessClockStateV1
    let sourceSnapshotSHA256: String
    /// Optional exact source proof from the manifest being superseded.
    let priorSourceSnapshotSHA256: String?
    let requirements: [OfflineReadinessRequirementV1]
    let status: OfflineReadinessStatusV1
    let manifestSHA256: String

    var mandatoryRequirementsAreSatisfied: Bool {
        requirements.filter(\.mandatory).allSatisfy { $0.state == .satisfied }
    }

    var mayStartFieldWork: Bool {
        (status == .ready || status == .warning) && mandatoryRequirementsAreSatisfied
    }

    var maySafelyCloseFieldWork: Bool {
        status == .ready && mandatoryRequirementsAreSatisfied
    }

    var sourceBindingDrift: Bool {
        priorSourceSnapshotSHA256 != nil && priorSourceSnapshotSHA256 != sourceSnapshotSHA256
    }

    init(session: RoundSessionReferenceV1, expectedPackage: RoundPackageReleaseReferenceV1, observedPackage: RoundPackageReleaseReferenceV1?, selectedAssets: [RoundAssetSelectionV1], observedAssetIDs: [UUID], guidanceReferenceIDs: [String], availableGuidanceReferenceIDs: [String], contentRequirements: [OfflineReadinessContentRequirementV1], contentObservations: [OfflineReadinessContentObservationV1], expectedFieldReferences: [OfflineReadinessFieldReferenceRequirementV1], referenceObservations: [OfflineReadinessReferenceObservationV1], requiredBytes: Int64?, availableBytes: Int64?, storage: OfflineReadinessStorageObservationV1, protectedDataAvailable: Bool, checkedAt: Date, timeZoneIdentifier: String, clockState: OfflineReadinessClockStateV1, sourceSnapshotSHA256: String, priorSourceSnapshotSHA256: String?, requirements: [OfflineReadinessRequirementV1], status: OfflineReadinessStatusV1) throws {
        try session.validate(); try expectedPackage.validate(); try observedPackage?.validate()
        guard selectedAssets.count <= OfflineReadinessManifestLimitsV1.maximumAssets, selectedAssets == selectedAssets.sorted { $0.assetID.uuidString < $1.assetID.uuidString }, Set(selectedAssets.map(\.assetID)).count == selectedAssets.count, observedAssetIDs.count <= OfflineReadinessManifestLimitsV1.maximumAssets, observedAssetIDs == observedAssetIDs.sorted { $0.uuidString < $1.uuidString }, Set(observedAssetIDs).count == observedAssetIDs.count,
              guidanceReferenceIDs.count <= OfflineReadinessManifestLimitsV1.maximumGuidanceReferences, guidanceReferenceIDs == guidanceReferenceIDs.sorted(), Set(guidanceReferenceIDs).count == guidanceReferenceIDs.count, guidanceReferenceIDs.allSatisfy(offlineReadinessTokenV1),
              availableGuidanceReferenceIDs.count <= OfflineReadinessManifestLimitsV1.maximumGuidanceReferences, availableGuidanceReferenceIDs == availableGuidanceReferenceIDs.sorted(), Set(availableGuidanceReferenceIDs).count == availableGuidanceReferenceIDs.count, Set(availableGuidanceReferenceIDs).isSubset(of: Set(guidanceReferenceIDs)),
              contentRequirements.count <= OfflineReadinessManifestLimitsV1.maximumContentRequirements, contentRequirements == contentRequirements.sorted { $0.reference.id < $1.reference.id }, Set(contentRequirements.map { $0.reference.id }).count == contentRequirements.count, contentObservations.count == contentRequirements.count, contentObservations == contentObservations.sorted { $0.contentID < $1.contentID }, Set(contentObservations.map(\.contentID)) == Set(contentRequirements.map { $0.reference.contentID }),
              expectedFieldReferences.count <= OfflineReadinessManifestLimitsV1.maximumFieldReferences, expectedFieldReferences == expectedFieldReferences.sorted { $0.releaseID.uuidString < $1.releaseID.uuidString }, Set(expectedFieldReferences.map(\.releaseID)).count == expectedFieldReferences.count,
              referenceObservations.count <= OfflineReadinessManifestLimitsV1.maximumFieldReferences, referenceObservations == referenceObservations.sorted { $0.releaseID.uuidString < $1.releaseID.uuidString }, Set(referenceObservations.map(\.releaseID)).count == referenceObservations.count,
              Set(referenceObservations.map(\.releaseID)).isSubset(of: Set(expectedFieldReferences.map(\.releaseID))),
              requiredBytes.map({ $0 >= 0 }) ?? true, availableBytes.map({ $0 >= 0 }) ?? true,
              checkedAt.timeIntervalSinceReferenceDate.isFinite, offlineReadinessTokenV1(timeZoneIdentifier), KernelCanonicalHashV1.validSHA256(sourceSnapshotSHA256), priorSourceSnapshotSHA256.map(KernelCanonicalHashV1.validSHA256) ?? true,
              requirements.count <= OfflineReadinessManifestLimitsV1.maximumRequirementRows, requirements == requirements.sorted { $0.requirementID < $1.requirementID }, Set(requirements.map(\.requirementID)).count == requirements.count else { throw OfflineReadinessManifestFailureV1.invalidValue }
        let reduction = try OfflineReadinessManifestReducerV1.reduce(.init(session: session, expectedPackage: expectedPackage, observedPackage: observedPackage, selectedAssets: selectedAssets, observedAssetIDs: observedAssetIDs, guidanceReferenceIDs: guidanceReferenceIDs, availableGuidanceReferenceIDs: availableGuidanceReferenceIDs, contentRequirements: contentRequirements, contentObservations: contentObservations, expectedFieldReferences: expectedFieldReferences, referenceObservations: referenceObservations, storage: storage, access: .init(protectedDataAvailable: protectedDataAvailable), timeZoneIdentifier: timeZoneIdentifier, clockState: clockState, priorSourceSnapshotSHA256: priorSourceSnapshotSHA256))
        guard sourceSnapshotSHA256 == reduction.sourceSnapshotSHA256, requirements == reduction.requirements, requiredBytes == reduction.requiredBytes, availableBytes == storage.availableBytes, status == reduction.status else { throw OfflineReadinessManifestFailureV1.invalidValue }
        self.schemaVersion = Self.schemaVersion; self.schema = OfflineReadinessManifestLifecycleV1.schema; self.persistenceMode = OfflineReadinessManifestLifecycleV1.persistenceMode
        self.session = session; self.expectedPackage = expectedPackage; self.observedPackage = observedPackage; self.selectedAssets = selectedAssets; self.observedAssetIDs = observedAssetIDs; self.guidanceReferenceIDs = guidanceReferenceIDs; self.availableGuidanceReferenceIDs = availableGuidanceReferenceIDs; self.contentRequirements = contentRequirements; self.contentObservations = contentObservations; self.expectedFieldReferences = expectedFieldReferences; self.referenceObservations = referenceObservations; self.requiredBytes = requiredBytes; self.availableBytes = availableBytes; self.storage = storage; self.protectedDataAvailable = protectedDataAvailable; self.checkedAt = checkedAt; self.timeZoneIdentifier = timeZoneIdentifier; self.clockState = clockState; self.sourceSnapshotSHA256 = sourceSnapshotSHA256; self.priorSourceSnapshotSHA256 = priorSourceSnapshotSHA256; self.requirements = requirements; self.status = status
        manifestSHA256 = try OfflineReadinessManifestCanonicalCodecV1.sha256(Basis(schemaVersion: Self.schemaVersion, schema: schema, persistenceMode: persistenceMode, session: session, expectedPackage: expectedPackage, observedPackage: observedPackage, selectedAssets: selectedAssets, observedAssetIDs: observedAssetIDs, guidanceReferenceIDs: guidanceReferenceIDs, availableGuidanceReferenceIDs: availableGuidanceReferenceIDs, contentRequirements: contentRequirements, contentObservations: contentObservations, expectedFieldReferences: expectedFieldReferences, referenceObservations: referenceObservations, requiredBytes: requiredBytes, availableBytes: availableBytes, storage: storage, protectedDataAvailable: protectedDataAvailable, checkedAt: checkedAt, timeZoneIdentifier: timeZoneIdentifier, clockState: clockState, sourceSnapshotSHA256: sourceSnapshotSHA256, priorSourceSnapshotSHA256: priorSourceSnapshotSHA256, requirements: requirements, status: status))
    }

    func validate() throws {
        let reconstructed = try Self(session: session, expectedPackage: expectedPackage, observedPackage: observedPackage, selectedAssets: selectedAssets, observedAssetIDs: observedAssetIDs, guidanceReferenceIDs: guidanceReferenceIDs, availableGuidanceReferenceIDs: availableGuidanceReferenceIDs, contentRequirements: contentRequirements, contentObservations: contentObservations, expectedFieldReferences: expectedFieldReferences, referenceObservations: referenceObservations, requiredBytes: requiredBytes, availableBytes: availableBytes, storage: storage, protectedDataAvailable: protectedDataAvailable, checkedAt: checkedAt, timeZoneIdentifier: timeZoneIdentifier, clockState: clockState, sourceSnapshotSHA256: sourceSnapshotSHA256, priorSourceSnapshotSHA256: priorSourceSnapshotSHA256, requirements: requirements, status: status)
        guard reconstructed.manifestSHA256 == manifestSHA256 else { throw OfflineReadinessManifestFailureV1.digestMismatch }
    }

    func canonicalData() throws -> Data {
        try validate()
        return try OfflineReadinessManifestCanonicalCodecV1.encode(self)
    }

    static func decodeCanonical(from data: Data) throws -> Self {
        let value = try OfflineReadinessManifestCanonicalCodecV1.decode(Self.self, from: data)
        try value.validate()
        return value
    }

    private struct Basis: Codable { let schemaVersion: Int; let schema: String; let persistenceMode: String; let session: RoundSessionReferenceV1; let expectedPackage: RoundPackageReleaseReferenceV1; let observedPackage: RoundPackageReleaseReferenceV1?; let selectedAssets: [RoundAssetSelectionV1]; let observedAssetIDs: [UUID]; let guidanceReferenceIDs: [String]; let availableGuidanceReferenceIDs: [String]; let contentRequirements: [OfflineReadinessContentRequirementV1]; let contentObservations: [OfflineReadinessContentObservationV1]; let expectedFieldReferences: [OfflineReadinessFieldReferenceRequirementV1]; let referenceObservations: [OfflineReadinessReferenceObservationV1]; let requiredBytes: Int64?; let availableBytes: Int64?; let storage: OfflineReadinessStorageObservationV1; let protectedDataAvailable: Bool; let checkedAt: Date; let timeZoneIdentifier: String; let clockState: OfflineReadinessClockStateV1; let sourceSnapshotSHA256: String; let priorSourceSnapshotSHA256: String?; let requirements: [OfflineReadinessRequirementV1]; let status: OfflineReadinessStatusV1 }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, schema, persistenceMode, session, expectedPackage, observedPackage, selectedAssets, observedAssetIDs, guidanceReferenceIDs, availableGuidanceReferenceIDs, contentRequirements, contentObservations, expectedFieldReferences, referenceObservations, requiredBytes, availableBytes, storage, protectedDataAvailable, checkedAt, timeZoneIdentifier, clockState, sourceSnapshotSHA256, priorSourceSnapshotSHA256, requirements, status, manifestSHA256 }
    init(from decoder: Decoder) throws {
        try OfflineReadinessClosedCodingV1.exact(decoder, CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion, c.decode(String.self, forKey: .schema) == OfflineReadinessManifestLifecycleV1.schema, c.decode(String.self, forKey: .persistenceMode) == OfflineReadinessManifestLifecycleV1.persistenceMode else { throw OfflineReadinessManifestFailureV1.invalidValue }
        let value = try Self(session: c.decode(RoundSessionReferenceV1.self, forKey: .session), expectedPackage: c.decode(RoundPackageReleaseReferenceV1.self, forKey: .expectedPackage), observedPackage: try c.decodeIfPresent(RoundPackageReleaseReferenceV1.self, forKey: .observedPackage), selectedAssets: c.decode([RoundAssetSelectionV1].self, forKey: .selectedAssets), observedAssetIDs: c.decode([UUID].self, forKey: .observedAssetIDs), guidanceReferenceIDs: c.decode([String].self, forKey: .guidanceReferenceIDs), availableGuidanceReferenceIDs: c.decode([String].self, forKey: .availableGuidanceReferenceIDs), contentRequirements: c.decode([OfflineReadinessContentRequirementV1].self, forKey: .contentRequirements), contentObservations: c.decode([OfflineReadinessContentObservationV1].self, forKey: .contentObservations), expectedFieldReferences: c.decode([OfflineReadinessFieldReferenceRequirementV1].self, forKey: .expectedFieldReferences), referenceObservations: c.decode([OfflineReadinessReferenceObservationV1].self, forKey: .referenceObservations), requiredBytes: try c.decodeIfPresent(Int64.self, forKey: .requiredBytes), availableBytes: try c.decodeIfPresent(Int64.self, forKey: .availableBytes), storage: c.decode(OfflineReadinessStorageObservationV1.self, forKey: .storage), protectedDataAvailable: c.decode(Bool.self, forKey: .protectedDataAvailable), checkedAt: c.decode(Date.self, forKey: .checkedAt), timeZoneIdentifier: c.decode(String.self, forKey: .timeZoneIdentifier), clockState: c.decode(OfflineReadinessClockStateV1.self, forKey: .clockState), sourceSnapshotSHA256: c.decode(String.self, forKey: .sourceSnapshotSHA256), priorSourceSnapshotSHA256: try c.decodeIfPresent(String.self, forKey: .priorSourceSnapshotSHA256), requirements: c.decode([OfflineReadinessRequirementV1].self, forKey: .requirements), status: c.decode(OfflineReadinessStatusV1.self, forKey: .status))
        guard value.manifestSHA256 == c.decode(String.self, forKey: .manifestSHA256) else { throw OfflineReadinessManifestFailureV1.digestMismatch }; self = value
    }
}

struct OfflineReadinessManifestReductionInputV1: Equatable, Sendable {
    let session: RoundSessionReferenceV1; let expectedPackage: RoundPackageReleaseReferenceV1; let observedPackage: RoundPackageReleaseReferenceV1?
    let selectedAssets: [RoundAssetSelectionV1]; let observedAssetIDs: [UUID]
    let guidanceReferenceIDs: [String]; let availableGuidanceReferenceIDs: [String]
    let contentRequirements: [OfflineReadinessContentRequirementV1]; let contentObservations: [OfflineReadinessContentObservationV1]
    let expectedFieldReferences: [OfflineReadinessFieldReferenceRequirementV1]; let referenceObservations: [OfflineReadinessReferenceObservationV1]
    let storage: OfflineReadinessStorageObservationV1; let access: OfflineReadinessAccessObservationV1
    let timeZoneIdentifier: String; let clockState: OfflineReadinessClockStateV1
    let priorSourceSnapshotSHA256: String?
}

struct OfflineReadinessManifestReductionV1: Equatable, Sendable {
    let requirements: [OfflineReadinessRequirementV1]
    let requiredBytes: Int64?
    let status: OfflineReadinessStatusV1
    let sourceSnapshotSHA256: String
}

/// Canonical current-observation proof. It deliberately excludes all derived
/// rows and all prior evidence, so no caller can choose current source truth.
enum OfflineReadinessManifestSourceProofV1 {
    static func digest(_ input: OfflineReadinessManifestReductionInputV1) throws -> String {
        try OfflineReadinessManifestCanonicalCodecV1.sha256(Basis(input: input))
    }

    private struct Basis: Codable {
        let session: RoundSessionReferenceV1
        let expectedPackage: RoundPackageReleaseReferenceV1
        let observedPackage: RoundPackageReleaseReferenceV1?
        let selectedAssets: [RoundAssetSelectionV1]
        let observedAssetIDs: [UUID]
        let guidanceReferenceIDs: [String]
        let availableGuidanceReferenceIDs: [String]
        let contentRequirements: [OfflineReadinessContentRequirementV1]
        let contentObservations: [OfflineReadinessContentObservationV1]
        let expectedFieldReferences: [OfflineReadinessFieldReferenceRequirementV1]
        let referenceObservations: [OfflineReadinessReferenceObservationV1]
        let storage: OfflineReadinessStorageObservationV1
        let access: OfflineReadinessAccessObservationV1
        let timeZoneIdentifier: String
        let clockState: OfflineReadinessClockStateV1

        init(input: OfflineReadinessManifestReductionInputV1) {
            session = input.session
            expectedPackage = input.expectedPackage
            observedPackage = input.observedPackage
            selectedAssets = input.selectedAssets
            observedAssetIDs = input.observedAssetIDs
            guidanceReferenceIDs = input.guidanceReferenceIDs
            availableGuidanceReferenceIDs = input.availableGuidanceReferenceIDs
            contentRequirements = input.contentRequirements
            contentObservations = input.contentObservations
            expectedFieldReferences = input.expectedFieldReferences
            referenceObservations = input.referenceObservations
            storage = input.storage
            access = input.access
            timeZoneIdentifier = input.timeZoneIdentifier
            clockState = input.clockState
        }
    }
}

enum OfflineReadinessManifestReducerV1 {
    static func reduce(_ input: OfflineReadinessManifestReductionInputV1) throws -> OfflineReadinessManifestReductionV1 {
        let sourceSnapshotSHA256 = try OfflineReadinessManifestSourceProofV1.digest(input)
        let sourceBindingDrift = input.priorSourceSnapshotSHA256 != nil
            && input.priorSourceSnapshotSHA256 != sourceSnapshotSHA256
        var rows: [OfflineReadinessRequirementV1] = []
        let fallback: OfflineReadinessManualFallbackV1 = .doNotStart
        let packageReady = input.observedPackage == input.expectedPackage
        rows.append(try row("package", .package, true, packageReady ? .satisfied : .mismatch, packageReady ? nil : .packageMismatch, packageReady ? nil : .restoreExactPackage, packageReady ? nil : fallback))
        for asset in input.selectedAssets {
            let present = input.observedAssetIDs.contains(asset.assetID)
            rows.append(try row("asset-\(asset.assetID.uuidString.lowercased())", .selectedAsset, true, present ? .satisfied : .missing, present ? nil : .selectedAssetMismatch, present ? nil : .reselectAssets, present ? nil : fallback))
        }
        for guidanceID in input.guidanceReferenceIDs {
            let present = input.availableGuidanceReferenceIDs.contains(guidanceID)
            rows.append(try row("guidance-\(guidanceID)", .guidance, true, present ? .satisfied : .missing, present ? nil : .guidanceReferenceMismatch, present ? nil : .restoreGuidance, present ? nil : fallback))
        }
        let observedReferences = Dictionary(uniqueKeysWithValues: input.referenceObservations.map { ($0.releaseID, $0) })
        for expected in input.expectedFieldReferences {
            let observed = observedReferences[expected.releaseID]
            let ready = observed.map { expected.matches($0) && $0.workspaceID == offlineReadinessWorkspaceV1(input.session.workspaceID) && $0.availability == .readyOffline } ?? false
            let state: OfflineReadinessRequirementStateV1 = observed == nil ? .missing : (observed?.workspaceID != offlineReadinessWorkspaceV1(input.session.workspaceID) ? .wrongWorkspace : (ready ? .satisfied : .mismatch))
            rows.append(try row("field-reference-\(expected.releaseID.uuidString.lowercased())", .fieldReference, true, state, ready ? nil : .fieldReferenceUnavailable, ready ? nil : .restoreFieldReference, ready ? nil : fallback))
        }
        let observations = Dictionary(uniqueKeysWithValues: input.contentObservations.map { ($0.contentID, $0) })
        for requirement in input.contentRequirements { rows.append(try contentRow(requirement, observations[requirement.reference.contentID], input.access.protectedDataAvailable)) }
        let protected = input.access.protectedDataAvailable
        rows.append(try row("protected-data", .protection, true, protected ? .satisfied : .protectedDataUnavailable, protected ? nil : .protectedDataUnavailable, protected ? nil : .unlockProtectedData, protected ? nil : .deferFieldWork))
        let storage = try storageRow(input.storage, requirements: input.contentRequirements)
        rows.append(storage.row)
        switch input.clockState {
        case .checked: rows.append(try row("clock", .clock, true, .satisfied, nil, nil, nil))
        case .changedSincePriorManifest: rows.append(try row("clock", .clock, true, .stale, .clockOrTimeZoneChanged, .rebuildPreflight, fallback))
        case .uncheckable: rows.append(try row("clock", .clock, true, .uncheckable, .clockUncheckable, .checkClockAndTimeZone, fallback))
        }
        if sourceBindingDrift { rows.append(try row("zz-source-binding", .binding, true, .stale, .sourceBindingDrift, .rebuildPreflight, fallback)) }
        rows.sort { $0.requirementID < $1.requirementID }
        return .init(requirements: rows, requiredBytes: storage.requiredBytes, status: status(rows, clockState: input.clockState), sourceSnapshotSHA256: sourceSnapshotSHA256)
    }

    static func status(_ rows: [OfflineReadinessRequirementV1], clockState: OfflineReadinessClockStateV1) -> OfflineReadinessStatusV1 {
        if clockState == .changedSincePriorManifest || rows.contains(where: { $0.state == .stale }) { return .stale }
        if rows.contains(where: { $0.mandatory && $0.state != .satisfied }) { return .blocked }
        if rows.contains(where: { !$0.mandatory && $0.state != .satisfied }) { return .warning }
        return .ready
    }

    private static func row(_ id: String, _ category: OfflineReadinessRequirementCategoryV1, _ mandatory: Bool, _ state: OfflineReadinessRequirementStateV1, _ reason: OfflineReadinessReasonV1?, _ remediation: OfflineReadinessRemediationV1?, _ fallback: OfflineReadinessManualFallbackV1?) throws -> OfflineReadinessRequirementV1 { try .init(requirementID: id, category: category, mandatory: mandatory, state: state, reason: reason, remediation: remediation, manualFallback: fallback) }
    private static func contentRow(_ requirement: OfflineReadinessContentRequirementV1, _ observed: OfflineReadinessContentObservationV1?, _ protected: Bool) throws -> OfflineReadinessRequirementV1 {
        let reference = requirement.reference; let expectedSHA = reference.digests.digest(for: .sha256)?.hexadecimalValue
        func make(_ state: OfflineReadinessRequirementStateV1, _ reason: OfflineReadinessReasonV1?, _ remediation: OfflineReadinessRemediationV1?, _ fallback: OfflineReadinessManualFallbackV1?) throws -> OfflineReadinessRequirementV1 { try .init(requirementID: "content-\(reference.contentID)", category: .content, mandatory: requirement.mandatory, contentRole: reference.byteRole, expectedWorkspaceID: reference.workspaceID, expectedSHA256: expectedSHA, expectedByteLength: reference.byteLength, observedWorkspaceID: observed?.workspaceID, observedSHA256: observed?.observedSHA256, observedByteLength: observed?.observedByteLength, state: state, reason: reason, remediation: remediation, manualFallback: fallback) }
        if !protected { return try make(.protectedDataUnavailable, .protectedDataUnavailable, .unlockProtectedData, .deferFieldWork) }
        guard let observed else { return try issue(make, .missing, requirement.mandatory ? .missingMandatoryContent : .missingOptionalContent) }
        guard observed.workspaceID == reference.workspaceID else { return try make(.wrongWorkspace, .wrongWorkspaceContent, .restoreExactContent, .doNotStart) }
        switch observed.state {
        case .missing: return try issue(make, .missing, requirement.mandatory ? .missingMandatoryContent : .missingOptionalContent)
        case .corrupt: return try issue(make, .corrupt, requirement.mandatory ? .corruptMandatoryContent : .corruptOptionalContent)
        case .partial: return try issue(make, .partial, requirement.mandatory ? .partialMandatoryContent : .partialOptionalContent)
        case .uncheckable: return try issue(make, .uncheckable, requirement.mandatory ? .missingMandatoryContent : .missingOptionalContent)
        case .present: return observed.observedSHA256 == expectedSHA && observed.observedByteLength == reference.byteLength ? try make(.satisfied, nil, nil, nil) : try issue(make, .corrupt, requirement.mandatory ? .corruptMandatoryContent : .corruptOptionalContent)
        }
    }
    private static func issue(_ make: (OfflineReadinessRequirementStateV1, OfflineReadinessReasonV1?, OfflineReadinessRemediationV1?, OfflineReadinessManualFallbackV1?) throws -> OfflineReadinessRequirementV1, _ state: OfflineReadinessRequirementStateV1, _ reason: OfflineReadinessReasonV1) throws -> OfflineReadinessRequirementV1 { try make(state, reason, .restoreExactContent, reason == .missingOptionalContent || reason == .corruptOptionalContent || reason == .partialOptionalContent ? .useApprovedManualProcedure : .doNotStart) }
    private static func storageRow(_ storage: OfflineReadinessStorageObservationV1, requirements: [OfflineReadinessContentRequirementV1]) throws -> (row: OfflineReadinessRequirementV1, requiredBytes: Int64?) {
        var required: Int64 = 0
        for requirement in requirements where requirement.mandatory { let (next, overflow) = required.addingReportingOverflow(requirement.reference.byteLength); guard !overflow else { return (try row("storage", .storage, true, .uncheckable, .storageArithmeticOverflow, .checkStorageAgain, .doNotStart), nil) }; required = next }
        for addition in [storage.reservedBytes, storage.operationReserveBytes] { let (next, overflow) = required.addingReportingOverflow(addition); guard !overflow else { return (try row("storage", .storage, true, .uncheckable, .storageArithmeticOverflow, .checkStorageAgain, .doNotStart), nil) }; required = next }
        guard storage.capacityState == .checked, let available = storage.availableBytes else { return (try row("storage", .storage, true, .capacityUnavailable, .storageUncheckable, .checkStorageAgain, .doNotStart), required) }
        guard available >= required else { return (try row("storage", .storage, true, .insufficientCapacity, .insufficientStorage, .freeStorage, .deferFieldWork), required) }
        return (try row("storage", .storage, true, .satisfied, nil, nil, nil), required)
    }
}

enum OfflineReadinessManifestCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(value)
        guard data.count <= OfflineReadinessManifestLimitsV1.maximumCanonicalBytes else { throw OfflineReadinessManifestFailureV1.limitExceeded }
        return data
    }
    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= OfflineReadinessManifestLimitsV1.maximumCanonicalBytes else { throw OfflineReadinessManifestFailureV1.limitExceeded }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        guard try encode(value) == data else { throw OfflineReadinessManifestFailureV1.nonCanonicalEncoding }
        return value
    }
    static func sha256<T: Encodable>(_ value: T) throws -> String { KernelCanonicalHashV1.sha256(try encode(value)) }
}

// MARK: - C17 exterior-lighting day inventory derived readiness

/// Exact canonical inputs needed to rebuild the C17 local-readiness result.
/// This value is carried by the derived projection only; it is not a new
/// persistent row and never replaces asset, plan, package, route, or content
/// authority.
struct C17LightingDayReadinessSourceV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let workflowID: UUID
    let workflowRevision: UInt64
    let workflowSHA256: String
    let assetIDs: [UUID]
    let systemID: UUID
    let systemRevision: UInt64
    let systemSHA256: String
    let planRevision: PlanRevisionReferenceV1
    let packageRelease: LightingPackageReleaseReferenceV1
    let referenceBindingSHA256s: [String]
    let routeSHA256: String
    let storageObservationSHA256: String
    let evidencePurposeIDs: [String]
    let sourceSHA256: String

    init(
        workflow: LightingDayInventoryWorkflowV1,
        planRevision: PlanRevisionReferenceV1,
        referenceBindingSHA256s: [String],
        storage: OfflineReadinessStorageObservationV1,
        evidencePurposeIDs: [String]
    ) throws {
        try workflow.validateIntrinsic()
        try planRevision.validate()
        let orderedAssets = workflow.conditionSnapshots.map(\.assetID).sorted {
            $0.uuidString < $1.uuidString
        }
        let orderedReferences = referenceBindingSHA256s.sorted()
        let orderedPurposes = evidencePurposeIDs.sorted()
        let storageSHA256 = try OfflineReadinessManifestCanonicalCodecV1.sha256(storage)
        guard let routeSHA256 = workflow.safetyIntake.route?.pathSHA256 else {
            throw OfflineReadinessManifestFailureV1.invalidValue
        }
        guard workflow.state != .safetyStopped,
              !orderedAssets.isEmpty,
              orderedAssets.count <= OfflineReadinessManifestLimitsV1.maximumAssets,
              Set(orderedAssets).count == orderedAssets.count,
              orderedReferences.count <= OfflineReadinessManifestLimitsV1.maximumFieldReferences,
              Set(orderedReferences).count == orderedReferences.count,
              !orderedPurposes.isEmpty,
              orderedPurposes.count <= OfflineReadinessManifestLimitsV1.maximumGuidanceReferences,
              Set(orderedPurposes).count == orderedPurposes.count,
              orderedPurposes.allSatisfy(offlineReadinessTokenV1),
              [workflow.workflowSHA256, workflow.systemSHA256,
               planRevision.revisionSHA256, workflow.packageRelease.packageSHA256,
               routeSHA256, storageSHA256].allSatisfy(KernelCanonicalHashV1.validSHA256),
              orderedReferences.allSatisfy(KernelCanonicalHashV1.validSHA256) else {
            throw OfflineReadinessManifestFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.workspaceID = workflow.workspaceID
        self.workflowID = workflow.workflowID
        self.workflowRevision = workflow.revision
        self.workflowSHA256 = workflow.workflowSHA256
        self.assetIDs = orderedAssets
        self.systemID = workflow.systemID
        self.systemRevision = workflow.systemRevision
        self.systemSHA256 = workflow.systemSHA256
        self.planRevision = planRevision
        packageRelease = workflow.packageRelease
        self.referenceBindingSHA256s = orderedReferences
        self.routeSHA256 = routeSHA256
        storageObservationSHA256 = storageSHA256
        self.evidencePurposeIDs = orderedPurposes
        sourceSHA256 = try OfflineReadinessManifestCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion, workspaceID: workflow.workspaceID,
            workflowID: workflow.workflowID, workflowRevision: workflow.revision,
            workflowSHA256: workflow.workflowSHA256, assetIDs: orderedAssets,
            systemID: workflow.systemID, systemRevision: workflow.systemRevision,
            systemSHA256: workflow.systemSHA256, planRevision: planRevision,
            packageRelease: workflow.packageRelease, referenceBindingSHA256s: orderedReferences,
            routeSHA256: routeSHA256, storageObservationSHA256: storageSHA256,
            evidencePurposeIDs: orderedPurposes
        ))
    }

    func validate(
        workflow: LightingDayInventoryWorkflowV1,
        storage: OfflineReadinessStorageObservationV1
    ) throws {
        let rebuilt = try Self(
            workflow: workflow, planRevision: planRevision,
            referenceBindingSHA256s: referenceBindingSHA256s,
            storage: storage, evidencePurposeIDs: evidencePurposeIDs
        )
        guard rebuilt == self else { throw OfflineReadinessManifestFailureV1.digestMismatch }
    }

    private struct Basis: Codable {
        let schemaVersion: Int; let workspaceID: WorkspaceID; let workflowID: UUID
        let workflowRevision: UInt64; let workflowSHA256: String; let assetIDs: [UUID]
        let systemID: UUID; let systemRevision: UInt64; let systemSHA256: String
        let planRevision: PlanRevisionReferenceV1
        let packageRelease: LightingPackageReleaseReferenceV1
        let referenceBindingSHA256s: [String]; let routeSHA256: String
        let storageObservationSHA256: String; let evidencePurposeIDs: [String]
    }
}

/// Disposable C17 projection binding the exact C17 source to the exact C06
/// manifest. Canonical workflow state may freeze these two digests, while the
/// full projection is dropped and rebuilt after relaunch or source drift.
struct C17LightingDayOfflineReadinessProjectionV1: Codable, Equatable, Sendable {
    static let persistenceMode = "DERIVED_ONLY"
    let source: C17LightingDayReadinessSourceV1
    let manifest: OfflineReadinessManifestV1
    let inputBindingSHA256: String
    let readinessSourceSHA256: String
    let manifestSHA256: String
    let projectionSHA256: String

    init(source: C17LightingDayReadinessSourceV1, manifest: OfflineReadinessManifestV1) throws {
        try manifest.validate()
        guard manifest.session.workspaceID == source.workspaceID,
              manifest.expectedPackage.packageReleaseID == source.packageRelease.packageReleaseID,
              manifest.expectedPackage.packageID == source.packageRelease.packageID,
              manifest.expectedPackage.packageContentVersion == source.packageRelease.contentVersion,
              manifest.expectedPackage.packageSHA256 == source.packageRelease.packageSHA256,
              manifest.expectedPackage.workflowSHA256 == source.packageRelease.workflowSHA256,
              manifest.selectedAssets.map(\.assetID) == source.assetIDs else {
            throw OfflineReadinessManifestFailureV1.invalidValue
        }
        self.source = source
        self.manifest = manifest
        inputBindingSHA256 = source.sourceSHA256
        readinessSourceSHA256 = manifest.sourceSnapshotSHA256
        manifestSHA256 = manifest.manifestSHA256
        projectionSHA256 = try OfflineReadinessManifestCanonicalCodecV1.sha256(Basis(
            persistenceMode: Self.persistenceMode, inputBindingSHA256: source.sourceSHA256,
            readinessSourceSHA256: manifest.sourceSnapshotSHA256,
            manifestSHA256: manifest.manifestSHA256
        ))
    }

    func validate() throws {
        let rebuilt = try Self(source: source, manifest: manifest)
        guard rebuilt == self else { throw OfflineReadinessManifestFailureV1.digestMismatch }
    }

    func validate(nightFollowupPlan: LightingNightFollowupPlanV1) throws {
        try validate(); try nightFollowupPlan.validate()
        guard nightFollowupPlan.workspaceID == source.workspaceID,
              nightFollowupPlan.sourceSystemID == source.systemID,
              nightFollowupPlan.sourceSystemRevision == source.systemRevision,
              nightFollowupPlan.sourceSystemSHA256 == source.systemSHA256,
              nightFollowupPlan.offlineReadinessSourceSHA256 == readinessSourceSHA256,
              nightFollowupPlan.offlineReadinessManifestSHA256 == manifestSHA256,
              nightFollowupPlan.readinessCheckedAt == manifest.checkedAt,
              manifest.status == .ready,
              manifest.mayStartFieldWork else {
            throw OfflineReadinessManifestFailureV1.digestMismatch
        }
    }

    private struct Basis: Codable {
        let persistenceMode: String; let inputBindingSHA256: String
        let readinessSourceSHA256: String; let manifestSHA256: String
    }
}

struct C18LightingNightReadinessSourceV1:Codable,Equatable,Sendable{
 static let persistenceMode="DERIVED_ONLY";let workspaceID:WorkspaceID;let workflowID:UUID;let workflowRevision:UInt64;let workflowSHA256:String;let assetIDs:[UUID];let system:LightingNightSystemBindingV1;let day:LightingNightDayBindingV1;let planFrontier:LightingNightPlanFrontierV1;let patrol:LightingPatrolReferenceV1?;let storageObservationSHA256:String;let sourceSHA256:String
 init(workflow:LightingNightWorkflowV1,storage:OfflineReadinessStorageObservationV1)throws{try workflow.validateIntrinsic();guard let frontier=workflow.planFrontier else{throw OfflineReadinessManifestFailureV1.invalidValue};let assets=workflow.deltas.map(\.assetID).sorted{$0.uuidString<$1.uuidString};let storageSHA=try OfflineReadinessManifestCanonicalCodecV1.sha256(storage);workspaceID=workflow.workspaceID;workflowID=workflow.workflowID;workflowRevision=workflow.revision;workflowSHA256=workflow.workflowSHA256;assetIDs=assets;system=workflow.system;day=workflow.day;planFrontier=frontier;patrol=workflow.patrol;storageObservationSHA256=storageSHA;sourceSHA256=try OfflineReadinessManifestCanonicalCodecV1.sha256(Basis(workspaceID:workspaceID,workflowID:workflowID,workflowRevision:workflowRevision,workflowSHA256:workflowSHA256,assetIDs:assetIDs,system:system,day:day,planFrontier:planFrontier,patrol:patrol,storageObservationSHA256:storageSHA));guard !assets.isEmpty,Set(assets).count==assets.count else{throw OfflineReadinessManifestFailureV1.invalidValue}}
 func validate(workflow:LightingNightWorkflowV1,storage:OfflineReadinessStorageObservationV1)throws{guard try Self(workflow:workflow,storage:storage)==self else{throw OfflineReadinessManifestFailureV1.digestMismatch}}
 private struct Basis:Codable{let workspaceID:WorkspaceID;let workflowID:UUID;let workflowRevision:UInt64;let workflowSHA256:String;let assetIDs:[UUID];let system:LightingNightSystemBindingV1;let day:LightingNightDayBindingV1;let planFrontier:LightingNightPlanFrontierV1;let patrol:LightingPatrolReferenceV1?;let storageObservationSHA256:String}
}

struct C18LightingNightOfflineReadinessProjectionV1:Codable,Equatable,Sendable{static let persistenceMode="DERIVED_ONLY";let source:C18LightingNightReadinessSourceV1;let manifest:OfflineReadinessManifestV1;let projectionSHA256:String;init(source:C18LightingNightReadinessSourceV1,manifest:OfflineReadinessManifestV1)throws{try manifest.validate();let selectedAssetIDs=Set(manifest.selectedAssets.map(\.assetID));guard manifest.session.workspaceID==source.workspaceID,Set(source.assetIDs).isSubset(of:selectedAssetIDs),manifest.sourceSnapshotSHA256==source.planFrontier.readinessSourceSHA256,manifest.manifestSHA256==source.planFrontier.readinessManifestSHA256 else{throw OfflineReadinessManifestFailureV1.invalidValue};self.source=source;self.manifest=manifest;projectionSHA256=try OfflineReadinessManifestCanonicalCodecV1.sha256(Basis(persistenceMode:Self.persistenceMode,sourceSHA256:source.sourceSHA256,manifestSHA256:manifest.manifestSHA256))}func validate()throws{guard try Self(source:source,manifest:manifest)==self else{throw OfflineReadinessManifestFailureV1.digestMismatch}}private struct Basis:Codable{let persistenceMode:String;let sourceSHA256:String;let manifestSHA256:String}}

/// C19 bridge into the incumbent readiness owner. It carries only the exact
/// derived proof identity and is rebuilt from OfflineWorkPacketReadinessV1.
/// No readiness Boolean or additional durable family is introduced.
struct PlanOfflineReadinessManifestBindingV1: Codable, Equatable, Sendable {
    static let persistenceMode = "DERIVED_ONLY"
    let persistenceMode: String
    let workspaceID: WorkspaceID
    let packet: WorkPacketManifestReferenceV1
    let item: WorkPacketItemReferenceV1
    let planRevision: PlanRevisionReferenceV1?
    let revisionDisposition: PlanRevisionSelectionDispositionV1?
    let sourceSnapshotSHA256: String
    let readinessSHA256: String
    let evaluatedAt: Date
    let bindingSHA256: String

    init(_ value: OfflineWorkPacketReadinessV1) throws {
        try value.validateIntrinsic()
        persistenceMode = Self.persistenceMode; workspaceID = value.workspaceID
        packet = value.packet; item = value.item; planRevision = value.planRevision
        revisionDisposition = value.revisionDisposition
        sourceSnapshotSHA256 = value.sourceSnapshotSHA256
        readinessSHA256 = value.readinessSHA256; evaluatedAt = value.checkedAt
        bindingSHA256 = try OfflineReadinessManifestCanonicalCodecV1.sha256(Basis(
            persistenceMode: Self.persistenceMode, workspaceID: value.workspaceID,
            packet: value.packet, item: value.item, planRevision: value.planRevision,
            revisionDisposition: value.revisionDisposition,
            sourceSnapshotSHA256: value.sourceSnapshotSHA256,
            readinessSHA256: value.readinessSHA256, evaluatedAt: value.checkedAt
        ))
    }

    func validate(_ value: OfflineWorkPacketReadinessV1) throws {
        try value.validateIntrinsic()
        guard self == (try Self(value)) else { throw OfflineReadinessManifestFailureV1.digestMismatch }
    }

    private struct Basis: Codable { let persistenceMode: String; let workspaceID: WorkspaceID; let packet: WorkPacketManifestReferenceV1; let item: WorkPacketItemReferenceV1; let planRevision: PlanRevisionReferenceV1?; let revisionDisposition: PlanRevisionSelectionDispositionV1?; let sourceSnapshotSHA256: String; let readinessSHA256: String; let evaluatedAt: Date }
}
