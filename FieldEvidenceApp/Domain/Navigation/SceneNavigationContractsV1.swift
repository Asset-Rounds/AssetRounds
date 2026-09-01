import Foundation

struct SceneRootPathV1: Codable, Equatable, Sendable {
    let root: AppRootV1
    let targets: [NavigationTargetV1]

    func validate(workspaceID: WorkspaceID) throws {
        guard targets.allSatisfy({ $0.workspaceID == workspaceID && $0.root == root }) else {
            throw SceneNavigationFailureV1.invalidPath
        }
        try targets.forEach { try $0.validate() }
    }
}

struct SceneNavigationSnapshotV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let selectedRoot: AppRootV1
    let paths: [SceneRootPathV1]
    let snapshotID: UUID

    init(workspaceID: WorkspaceID, selectedRoot: AppRootV1, paths: [SceneRootPathV1], snapshotID: UUID) throws {
        self.schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.selectedRoot = selectedRoot
        let order = Dictionary(uniqueKeysWithValues: AppRootV1.frozenOrder.enumerated().map { ($1, $0) })
        self.paths = paths.sorted { order[$0.root, default: Int.max] < order[$1.root, default: Int.max] }
        self.snapshotID = snapshotID
        try validate()
    }

    func validate() throws {
        try WorkspaceExperienceRouteBoundaryV1.validate()
        guard schemaVersion == Self.schemaVersion, workspaceID.rawValue != RouteContractValidationV1.zeroUUID,
              snapshotID != RouteContractValidationV1.zeroUUID,
              paths.map(\.root) == AppRootV1.frozenOrder else { throw SceneNavigationFailureV1.invalidSnapshot }
        try paths.forEach { try $0.validate(workspaceID: workspaceID) }
    }

    var selectedTarget: NavigationTargetV1? {
        paths.first(where: { $0.root == selectedRoot })?.targets.last
    }
}

enum RouteRestorationSourceV1: String, Codable, Hashable, Sendable {
    case startupMaintenance = "STARTUP_MAINTENANCE"
    case incompleteMutationRecovery = "INCOMPLETE_MUTATION_RECOVERY"
    case explicitIngress = "EXPLICIT_INGRESS"
    case sceneSnapshot = "SCENE_SNAPSHOT"
    case todayFallback = "TODAY_FALLBACK"
}

enum RouteEvidenceKindV1: String, Codable, Hashable, Sendable {
    case golden = "V23-P03-C34-G01"
    case alternate = "V23-P03-C34-A01"
    case hostile = "V23-P03-C34-H01"
    case interruption = "V23-P03-C34-I01"
    case recovery = "V23-P03-C34-R01"
}

enum RouteReceiptReconciliationDispositionV1: String, Codable, Hashable, Sendable {
    case sameReceipt = "SAME_RECEIPT"
    case distinctReceipt = "DISTINCT_RECEIPT"
    case quarantineChangedInput = "QUARANTINE_CHANGED_INPUT"
}

struct RouteRestorationReceiptV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let receiptID: UUID
    let evidenceKind: RouteEvidenceKindV1
    let source: RouteRestorationSourceV1
    let result: RouteResolutionResultV1
    let snapshotID: UUID?
    let canonicalMutationCount: Int
    let startsAutomaticWork: Bool
    let receiptSHA256: String

    init(receiptID: UUID, evidenceKind: RouteEvidenceKindV1, source: RouteRestorationSourceV1, result: RouteResolutionResultV1, snapshotID: UUID?) throws {
        schemaVersion = 1
        self.receiptID = receiptID
        self.evidenceKind = evidenceKind
        self.source = source
        self.result = result
        self.snapshotID = snapshotID
        canonicalMutationCount = 0
        startsAutomaticWork = false
        receiptSHA256 = try RouteCanonicalCodecV1.sha256(Basis(schemaVersion: 1, receiptID: receiptID, evidenceKind: evidenceKind, source: source, result: result, snapshotID: snapshotID, canonicalMutationCount: 0, startsAutomaticWork: false))
        try validate()
    }

    func validate() throws {
        guard schemaVersion == 1, receiptID != RouteContractValidationV1.zeroUUID,
              canonicalMutationCount == 0, !startsAutomaticWork,
              result.canonicalMutationCount == 0, !result.startsAutomaticWork,
              receiptSHA256 == (try RouteCanonicalCodecV1.sha256(basis)) else { throw SceneNavigationFailureV1.invalidReceipt }
    }

    static func reconcile(candidate: Self, existing: Self) throws -> RouteReceiptReconciliationDispositionV1 {
        try candidate.validate()
        try existing.validate()
        guard candidate.receiptID == existing.receiptID else { return .distinctReceipt }
        return candidate.receiptSHA256 == existing.receiptSHA256 ? .sameReceipt : .quarantineChangedInput
    }

    private var basis: Basis { .init(schemaVersion: schemaVersion, receiptID: receiptID, evidenceKind: evidenceKind, source: source, result: result, snapshotID: snapshotID, canonicalMutationCount: canonicalMutationCount, startsAutomaticWork: startsAutomaticWork) }
    private struct Basis: Codable { let schemaVersion: Int; let receiptID: UUID; let evidenceKind: RouteEvidenceKindV1; let source: RouteRestorationSourceV1; let result: RouteResolutionResultV1; let snapshotID: UUID?; let canonicalMutationCount: Int; let startsAutomaticWork: Bool }
}

struct RouteConformanceReceiptV1: Codable, Equatable, Sendable {
    let evidenceKind: RouteEvidenceKindV1
    let roots: [AppRootV1]
    let routeIDs: [String]
    let packageIDs: [String]
    let duplicateCount: Int
    let shellCount: Int
    let parserCount: Int
    let mutationAuthorityCount: Int

    init(
        registry: RouteRegistryV1,
        evidenceKind: RouteEvidenceKindV1,
        observedShellCount: Int,
        observedParserCount: Int,
        observedMutationAuthorityCount: Int
    ) {
        self.evidenceKind = evidenceKind
        roots = AppRootV1.frozenOrder
        routeIDs = registry.descriptors.map(\.routeID)
        packageIDs = registry.manifests.map(\.packageID)
        duplicateCount = routeIDs.count - Set(routeIDs).count
        shellCount = observedShellCount
        parserCount = observedParserCount
        mutationAuthorityCount = observedMutationAuthorityCount
    }

    func validate() throws {
        guard roots == AppRootV1.frozenOrder, roots.count == 4, duplicateCount == 0,
              shellCount == 1, parserCount == 1, mutationAuthorityCount == 0 else { throw SceneNavigationFailureV1.invalidConformance }
    }
}

enum SceneNavigationFailureV1: Error, Equatable {
    case invalidPath
    case invalidSnapshot
    case invalidReceipt
    case invalidConformance
}

struct SceneNavigationLifecycleDispositionV1: Codable, Equatable, Sendable {
    let persistenceClass = "DEVICE_OPERATIONAL_NONCANONICAL"
    let workspaceTruth = false
    let backupIncluded = false
    let journalIncluded = false
    let reportIncluded = false
    let exportIncluded = false
    let searchIncluded = false
    let eraseClears = true
    let tolerantDecode = true
    let activeWorkspaceSelectionIsDeviceLocal = true
    let activeWorkspaceSelectionIsBackedUp = false
}
