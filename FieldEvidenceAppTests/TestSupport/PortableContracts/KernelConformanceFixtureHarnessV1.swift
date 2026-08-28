import Foundation
import CryptoKit
import SwiftData
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import FieldEvidenceApp

enum KernelConformanceFixtureFailureV1: Error, Equatable {
    case missingArtifact(String)
    case invalidArtifact(String)
    case incompleteCoverage(String)
}

struct KernelConformanceLifecycleTransitionV1: Decodable, Equatable, Sendable {
    let sequence: Int
    let action: String
    let adapter: String
    let inputState: String
    let outputState: String
    let persistentConsumers: [String]
    let brandState: String
    private enum CodingKeys: String, CodingKey, CaseIterable { case sequence, action, adapter, inputState, outputState, persistentConsumers, brandState }
    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        sequence = try c.decode(Int.self, forKey: .sequence); action = try c.decode(String.self, forKey: .action); adapter = try c.decode(String.self, forKey: .adapter)
        inputState = try c.decode(String.self, forKey: .inputState); outputState = try c.decode(String.self, forKey: .outputState)
        persistentConsumers = try c.decode([String].self, forKey: .persistentConsumers); brandState = try c.decode(String.self, forKey: .brandState)
    }
}

struct KernelConformanceFaultInjectionV1: Decodable, Equatable, Sendable {
    let boundary: String
    let faultClass: String
    let recoveryAction: String
    let expectedDisposition: String
    let selectors: [String]
    let evidenceIDs: [String]
    private enum CodingKeys: String, CodingKey, CaseIterable { case boundary, faultClass, recoveryAction, expectedDisposition, selectors, evidenceIDs }
    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        boundary = try c.decode(String.self, forKey: .boundary); faultClass = try c.decode(String.self, forKey: .faultClass)
        recoveryAction = try c.decode(String.self, forKey: .recoveryAction); expectedDisposition = try c.decode(String.self, forKey: .expectedDisposition)
        selectors = try c.decode([String].self, forKey: .selectors); evidenceIDs = try c.decode([String].self, forKey: .evidenceIDs)
    }
}

struct KernelConformanceReplicaScheduleV1: Decodable, Equatable, Sendable {
    let id: String
    let replicas: [String]
    let deliveries: [String]
    let expectedSemanticSHA256: String
    let replayCount: Int
    let expectedNormalizedSHA256: String
    private enum CodingKeys: String, CodingKey, CaseIterable { case id, replicas, deliveries, expectedSemanticSHA256, replayCount, expectedNormalizedSHA256 }
    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); replicas = try c.decode([String].self, forKey: .replicas); deliveries = try c.decode([String].self, forKey: .deliveries)
        expectedSemanticSHA256 = try c.decode(String.self, forKey: .expectedSemanticSHA256); replayCount = try c.decode(Int.self, forKey: .replayCount)
        expectedNormalizedSHA256 = try c.decode(String.self, forKey: .expectedNormalizedSHA256)
    }
}

struct KernelConformanceExpectedProjectionV1: Decodable, Equatable, Sendable {
    let canonicalUTF8Hex: String
    let sha256: String
    let recordIDs: [String]
    private enum CodingKeys: String, CodingKey, CaseIterable { case canonicalUTF8Hex, sha256, recordIDs }
    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        canonicalUTF8Hex = try c.decode(String.self, forKey: .canonicalUTF8Hex); sha256 = try c.decode(String.self, forKey: .sha256); recordIDs = try c.decode([String].self, forKey: .recordIDs)
    }
}

struct KernelConformanceReleaseAbsenceV1: Decodable, Equatable, Sendable {
    let testOnly: Bool
    let shippingAdoptionEnabled: Bool
    let nativeCompileRan: Bool
    let hostedDispatchRan: Bool
    let acceptanceCredit: Bool
    let releaseCredit: Bool
    let requiresAcceptedS10_6Reconciliation: Bool
    private enum CodingKeys: String, CodingKey, CaseIterable { case testOnly, shippingAdoptionEnabled, nativeCompileRan, hostedDispatchRan, acceptanceCredit, releaseCredit, requiresAcceptedS10_6Reconciliation }
    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        testOnly = try c.decode(Bool.self, forKey: .testOnly); shippingAdoptionEnabled = try c.decode(Bool.self, forKey: .shippingAdoptionEnabled)
        nativeCompileRan = try c.decode(Bool.self, forKey: .nativeCompileRan); hostedDispatchRan = try c.decode(Bool.self, forKey: .hostedDispatchRan)
        acceptanceCredit = try c.decode(Bool.self, forKey: .acceptanceCredit); releaseCredit = try c.decode(Bool.self, forKey: .releaseCredit)
        requiresAcceptedS10_6Reconciliation = try c.decode(Bool.self, forKey: .requiresAcceptedS10_6Reconciliation)
    }
}

struct KernelConformanceEvidenceBindingV1: Decodable, Equatable, Sendable {
    let selector: String
    let evidenceID: String
    let covers: [String]
    private enum CodingKeys: String, CodingKey, CaseIterable { case selector, evidenceID, covers }
    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        selector = try c.decode(String.self, forKey: .selector); evidenceID = try c.decode(String.self, forKey: .evidenceID); covers = try c.decode([String].self, forKey: .covers)
    }
}

struct KernelConformanceFixtureManifestV1: Decodable, Equatable, Sendable {
    let schema: String
    let schemaVersion: Int
    let fixtureID: String
    let shapeID: String
    let productionAdapters: [String]
    let lifecycleTransitions: [KernelConformanceLifecycleTransitionV1]
    let faultInjections: [KernelConformanceFaultInjectionV1]
    let replicaSchedules: [KernelConformanceReplicaScheduleV1]
    let expectedNormalizedProjection: KernelConformanceExpectedProjectionV1
    let releaseAbsence: KernelConformanceReleaseAbsenceV1
    let evidenceBindings: [KernelConformanceEvidenceBindingV1]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schema, schemaVersion, fixtureID, shapeID, productionAdapters
        case lifecycleTransitions, faultInjections, replicaSchedules
        case expectedNormalizedProjection, releaseAbsence, evidenceBindings
    }

    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schema = try values.decode(String.self, forKey: .schema)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        fixtureID = try values.decode(String.self, forKey: .fixtureID)
        shapeID = try values.decode(String.self, forKey: .shapeID)
        productionAdapters = try values.decode([String].self, forKey: .productionAdapters)
        lifecycleTransitions = try values.decode([KernelConformanceLifecycleTransitionV1].self, forKey: .lifecycleTransitions)
        faultInjections = try values.decode([KernelConformanceFaultInjectionV1].self, forKey: .faultInjections)
        replicaSchedules = try values.decode([KernelConformanceReplicaScheduleV1].self, forKey: .replicaSchedules)
        expectedNormalizedProjection = try values.decode(KernelConformanceExpectedProjectionV1.self, forKey: .expectedNormalizedProjection)
        releaseAbsence = try values.decode(KernelConformanceReleaseAbsenceV1.self, forKey: .releaseAbsence)
        evidenceBindings = try values.decode([KernelConformanceEvidenceBindingV1].self, forKey: .evidenceBindings)
    }
}

struct KernelConformanceGraphNodeV1: Decodable, Equatable, Sendable {
    let id: String
    let phase: String
    let adapter: String
    let persistentConsumers: [String]
    let brandState: String
    private enum CodingKeys: String, CodingKey, CaseIterable { case id, phase, adapter, persistentConsumers, brandState }
    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); phase = try c.decode(String.self, forKey: .phase); adapter = try c.decode(String.self, forKey: .adapter)
        persistentConsumers = try c.decode([String].self, forKey: .persistentConsumers); brandState = try c.decode(String.self, forKey: .brandState)
    }
}

struct KernelConformanceGraphEdgeV1: Decodable, Equatable, Sendable {
    let id: String
    let from: String
    let to: String
    let action: String
    let boundary: String
    private enum CodingKeys: String, CodingKey, CaseIterable { case id, from, to, action, boundary }
    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); from = try c.decode(String.self, forKey: .from); to = try c.decode(String.self, forKey: .to)
        action = try c.decode(String.self, forKey: .action); boundary = try c.decode(String.self, forKey: .boundary)
    }
}

struct KernelConformanceSelectorBindingV1: Decodable, Equatable, Sendable {
    let selector: String
    let evidenceID: String
    let nodeIDs: [String]
    let boundaries: [String]
    private enum CodingKeys: String, CodingKey, CaseIterable { case selector, evidenceID, nodeIDs, boundaries }
    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        selector = try c.decode(String.self, forKey: .selector); evidenceID = try c.decode(String.self, forKey: .evidenceID)
        nodeIDs = try c.decode([String].self, forKey: .nodeIDs); boundaries = try c.decode([String].self, forKey: .boundaries)
    }
}

struct KernelConformancePersistentConsumerV1: Decodable, Equatable, Sendable {
    let id: String
    let adapter: String
    let publicationAuthority: String
    let recoveryDisposition: String
    private enum CodingKeys: String, CodingKey, CaseIterable { case id, adapter, publicationAuthority, recoveryDisposition }
    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); adapter = try c.decode(String.self, forKey: .adapter)
        publicationAuthority = try c.decode(String.self, forKey: .publicationAuthority); recoveryDisposition = try c.decode(String.self, forKey: .recoveryDisposition)
    }
}

struct KernelConformanceBrandStateV1: Decodable, Equatable, Sendable {
    let id: String
    let changedUI: Bool
    let nodeIDs: [String]
    private enum CodingKeys: String, CodingKey, CaseIterable { case id, changedUI, nodeIDs }
    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); changedUI = try c.decode(Bool.self, forKey: .changedUI); nodeIDs = try c.decode([String].self, forKey: .nodeIDs)
    }
}

struct KernelConformanceScenarioGraphV1: Decodable, Equatable, Sendable {
    let schema: String
    let schemaVersion: Int
    let nodes: [KernelConformanceGraphNodeV1]
    let edges: [KernelConformanceGraphEdgeV1]
    let selectorBindings: [KernelConformanceSelectorBindingV1]
    let persistentConsumers: [KernelConformancePersistentConsumerV1]
    let brandStates: [KernelConformanceBrandStateV1]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schema, schemaVersion, nodes, edges, selectorBindings
        case persistentConsumers, brandStates
    }

    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schema = try values.decode(String.self, forKey: .schema)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        nodes = try values.decode([KernelConformanceGraphNodeV1].self, forKey: .nodes)
        edges = try values.decode([KernelConformanceGraphEdgeV1].self, forKey: .edges)
        selectorBindings = try values.decode([KernelConformanceSelectorBindingV1].self, forKey: .selectorBindings)
        persistentConsumers = try values.decode([KernelConformancePersistentConsumerV1].self, forKey: .persistentConsumers)
        brandStates = try values.decode([KernelConformanceBrandStateV1].self, forKey: .brandStates)
    }
}

struct PortableContractCorpusV1: Decodable, Equatable, Sendable {
    let schema: String
    let schemaVersion: Int
    let cases: [PortableContractCaseV1]

    private enum CodingKeys: String, CodingKey, CaseIterable { case schema, schemaVersion, cases }

    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schema = try values.decode(String.self, forKey: .schema)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        cases = try values.decode([PortableContractCaseV1].self, forKey: .cases)
    }
}

enum KernelConformanceFixtureShapeV1: CaseIterable, Sendable {
    case checklist
    case measurementRepeat

    var resourceName: String {
        switch self {
        case .checklist: "V21P03C10ChecklistFixtureManifestV1"
        case .measurementRepeat: "V21P03C10MeasurementRepeatFixtureManifestV1"
        }
    }

    var schema: String { resourceName }

    var fixtureID: String {
        switch self {
        case .checklist: "V21-P03-C10-CHECKLIST-FIXTURE-V1"
        case .measurementRepeat: "V21-P03-C10-MEASUREMENT-REPEAT-FIXTURE-V1"
        }
    }

    var shapeID: String {
        switch self {
        case .checklist: "CHECKLIST_BRANCHING_EVIDENCE_FIRST"
        case .measurementRepeat: "MEASUREMENT_REPEAT_LOOP_RECHECK"
        }
    }
}

enum KernelConformanceFixtureHarnessV1 {
    static let selectors = [
        "testV9_20G01BothFixtureShapesCompleteFullLifecycleWithPortableSchemaParity",
        "testV9_20A01EveryPublicationBoundaryFaultRecoversWithoutPartialAuthority",
        "testV9_20H01HostilePortableCorpusFixtureLeakAndReleaseHooksFailClosed",
        "testV9_20I01RelaunchResumesOrCleansEveryDurableBoundaryDeterministically",
        "testV9_20R01TwoAndThreeReplicaSchedulesReconcileArchiveRestoreSearchDeleteAndErase",
    ]

    static let evidenceIDs = [
        "V23-P03-C10-G01", "V23-P03-C10-A01", "V23-P03-C10-H01",
        "V23-P03-C10-I01", "V23-P03-C10-R01",
    ]

    static let requiredLifecycle = [
        "VALIDATE", "START", "RESUME", "RESPOND", "EVIDENCE", "FIND", "WORK",
        "RECHECK", "FINALIZE", "PROJECT", "ARCHIVE", "RESTORE", "SEARCH",
        "DELETE", "ERASE", "RECOVER",
    ]

    static let productionAdapters: Set<String> = [
        "StoreGenerationFactory", "StoreSessionCoordinator", "WorkspaceWriterV1",
        "WorkspaceWriterAdapterV1", "CheckRunnerCoordinator", "WorkCoordinator",
        "PackFinalizationAdapterV1", "ReportProjectionRegistryV2", "BackupExportService",
        "StreamingArchiveService", "BackupRestoreService", "LocalChangeJournalV1",
        "SearchCoordinatorV1", "SearchIndexRebuildCoordinatorV1",
        "WholeSignDeletionService", "EraseAllService",
    ]

    static let productionFaultIdentities: [String: String] = [
        "FINALIZATION_SNAPSHOT_STAGING_WRITE": "FinalizationIntentStoreFailurePoint.snapshotStagingWrite",
        "FINALIZATION_SNAPSHOT_PROMOTION_MOVE": "FinalizationIntentStoreFailurePoint.snapshotPromotionMove",
        "FINALIZATION_INTENT_PHASE_WRITE": "FinalizationIntentStoreFailurePoint.intentPhaseWrite",
        "FINALIZATION_MODEL_SAVE": "FinalizationServiceFailurePoint.modelSave",
        "WORK_MODEL_SAVE": "WorkCoordinatorFailurePoint.modelSave",
        "WORK_AFTER_EVIDENCE_PROMOTION": "WorkCoordinatorFailurePoint.afterEvidencePromotion",
        "REPORT_RENDER": "ReportRenderFailurePoint.render", "REPORT_STAGE_WRITE": "ReportRenderFailurePoint.stageWrite",
        "REPORT_PROMOTION": "ReportRenderFailurePoint.promotion", "REPORT_REREAD": "ReportRenderFailurePoint.reread",
        "REPORT_READY_SAVE": "ReportRenderFailurePoint.readySave", "REPORT_FAILED_STATE_SAVE": "ReportRenderFailurePoint.failedStateSave",
        "REPORT_RETRY_TRANSITION_SAVE": "ReportRecoveryFailurePoint.retryTransitionSave",
        "JOURNAL_AFTER_CHECKPOINT_PREPARED": "LocalChangeJournalV1.InterruptionPointV1.afterCheckpointPrepared",
        "JOURNAL_AFTER_CHECKPOINT_STATE_WRITTEN": "LocalChangeJournalV1.InterruptionPointV1.afterCheckpointStateWritten",
        "JOURNAL_AFTER_REPLAY_MUTATION": "LocalChangeJournalV1.InterruptionPointV1.afterReplayMutation",
        "JOURNAL_AFTER_COMPACTION_STATE_WRITTEN": "LocalChangeJournalV1.InterruptionPointV1.afterCompactionStateWritten",
        "RESTORE_BEFORE_PREPARED_WRITE": "BackupRestoreFailurePoint.beforePreparedWrite", "RESTORE_AFTER_PREPARED_WRITE": "BackupRestoreFailurePoint.afterPreparedWrite",
        "RESTORE_BEFORE_GENERATION_INSTALL": "BackupRestoreFailurePoint.beforeGenerationInstall", "RESTORE_AFTER_GENERATION_INSTALL": "BackupRestoreFailurePoint.afterGenerationInstall",
        "RESTORE_BEFORE_POINTER_SWITCH": "BackupRestoreFailurePoint.beforePointerSwitch", "RESTORE_AFTER_POINTER_SWITCH": "BackupRestoreFailurePoint.afterPointerSwitch",
        "RESTORE_BEFORE_NEW_GENERATION_VALIDATION": "BackupRestoreFailurePoint.beforeNewGenerationValidation", "RESTORE_AFTER_NEW_GENERATION_VALIDATION": "BackupRestoreFailurePoint.afterNewGenerationValidation",
        "RESTORE_BEFORE_CLEANUP": "BackupRestoreFailurePoint.beforeCleanup",
        "DELETE_PREPARED_JOURNAL": "WholeSignDeletionFailurePoint.preparedJournal", "DELETE_DATABASE_SAVE": "WholeSignDeletionFailurePoint.databaseSave",
        "DELETE_COMMITTED_PHASE": "WholeSignDeletionFailurePoint.committedPhase", "DELETE_FILE_CLEANUP": "WholeSignDeletionFailurePoint.fileCleanup",
        "DELETE_JOURNAL_REMOVAL": "WholeSignDeletionFailurePoint.journalRemoval",
        "ERASE_AFTER_EMPTY_GENERATION_DIRECTORY_CREATE": "EraseAllFailurePoint.afterEmptyGenerationDirectoryCreate",
        "ERASE_BEFORE_PREPARED_WRITE": "EraseAllFailurePoint.beforePreparedWrite", "ERASE_AFTER_PREPARED_WRITE": "EraseAllFailurePoint.afterPreparedWrite",
        "ERASE_BEFORE_POINTER_SWITCH": "EraseAllFailurePoint.beforePointerSwitch", "ERASE_AFTER_POINTER_SWITCH": "EraseAllFailurePoint.afterPointerSwitch",
        "ERASE_BEFORE_POINTER_PHASE_WRITE": "EraseAllFailurePoint.beforePointerPhaseWrite", "ERASE_AFTER_POINTER_PHASE_WRITE": "EraseAllFailurePoint.afterPointerPhaseWrite",
        "ERASE_BEFORE_SESSION_ACTIVATION": "EraseAllFailurePoint.beforeSessionActivation", "ERASE_AFTER_SESSION_ACTIVATION": "EraseAllFailurePoint.afterSessionActivation",
        "ERASE_BEFORE_SESSION_PHASE_WRITE": "EraseAllFailurePoint.beforeSessionPhaseWrite", "ERASE_AFTER_SESSION_PHASE_WRITE": "EraseAllFailurePoint.afterSessionPhaseWrite",
        "ERASE_BEFORE_CLEANUP": "EraseAllFailurePoint.beforeCleanup", "ERASE_AFTER_CLEANUP": "EraseAllFailurePoint.afterCleanup",
        "ERASE_BEFORE_CLEANUP_PHASE_WRITE": "EraseAllFailurePoint.beforeCleanupPhaseWrite", "ERASE_AFTER_CLEANUP_PHASE_WRITE": "EraseAllFailurePoint.afterCleanupPhaseWrite",
        "ERASE_BEFORE_JOURNAL_REMOVAL": "EraseAllFailurePoint.beforeJournalRemoval",
        "SEARCH_CANCELLATION": "Task.CancellationError", "SEARCH_CHECKPOINT": "SearchIndexRebuildCheckpointV1",
        "SEARCH_STALE": "SearchIndexReconciliationV1.staleDropAndRebuild", "SEARCH_AHEAD": "SearchIndexReconciliationV1.aheadDropAndRebuild",
        "SEARCH_INCOMPATIBLE": "SearchIndexReconciliationV1.incompatibleFormatDropAndRebuild", "SEARCH_PUBLICATION_TOKEN": "SearchIndexPublicationTokenV1",
    ]

    static func loadManifest(_ shape: KernelConformanceFixtureShapeV1) throws -> KernelConformanceFixtureManifestV1 {
        let value: KernelConformanceFixtureManifestV1 = try decodeResource(
            shape.resourceName,
            subdirectory: "Fixtures/V21/Kernel"
        )
        try validate(value, shape: shape)
        return value
    }

    static func loadScenarioGraph() throws -> KernelConformanceScenarioGraphV1 {
        let value: KernelConformanceScenarioGraphV1 = try decodeResource(
            "V21P03C10KernelConformanceScenarioGraphV1",
            subdirectory: "Fixtures/V21/Kernel"
        )
        try validate(value)
        return value
    }

    static func loadPortableCorpus() throws -> PortableContractCorpusV1 {
        let value: PortableContractCorpusV1 = try decodeResource(
            "V21P03C10PortableContractCorpusV1",
            subdirectory: "Fixtures/V21/Contracts"
        )
        guard value.schema == "V21P03C10PortableContractCorpusV1", value.schemaVersion == 1,
              !value.cases.isEmpty, Set(value.cases.map(\.id)).count == value.cases.count,
              Set(value.cases.map(\.expectedClass)) == [.accepted, .rejected] else {
            throw KernelConformanceFixtureFailureV1.invalidArtifact(value.schema)
        }
        return value
    }

    static func sourceRoot() -> URL {
        var value = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<3 { value.deleteLastPathComponent() }
        return value
    }

    static func toolLockURL() -> URL {
        sourceRoot().appendingPathComponent(PortableContractToolLockReaderV1.relativePath)
    }

    static func c06CorpusURL() -> URL {
        sourceRoot().appendingPathComponent("FieldEvidenceAppTests/Fixtures/V21/Contracts/V21P03C06SnapshotProjectionCorpusV1.json")
    }

    static func c06SchemaURL() -> URL {
        sourceRoot().appendingPathComponent("Scripts/v23/completed-activity-snapshot.schema.json")
    }

    static func c11CorpusURL() -> URL {
        sourceRoot().appendingPathComponent("FieldEvidenceAppTests/Fixtures/V21/ChangeJournal/V21P03C11ChangeJournalCheckpointReplayCorpusV1.json")
    }

    static func readRequiredData(_ url: URL, maximumBytes: Int = 4 * 1_024 * 1_024) throws -> Data {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            throw KernelConformanceFixtureFailureV1.missingArtifact(url.path)
        }
        let value = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard !value.isEmpty, value.count <= maximumBytes else {
            throw KernelConformanceFixtureFailureV1.invalidArtifact(url.path)
        }
        return value
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func decodeResource<T: Decodable>(
        _ name: String,
        subdirectory: String
    ) throws -> T {
        let bundle = Bundle(for: KernelConformanceBundleMarkerV1.self)
        let bundled = bundle.url(forResource: name, withExtension: "json", subdirectory: subdirectory)
            ?? bundle.url(forResource: name, withExtension: "json")
        let source = sourceRoot().appendingPathComponent("FieldEvidenceAppTests/\(subdirectory)/\(name).json")
        let data = try readRequiredData(bundled ?? source)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw KernelConformanceFixtureFailureV1.invalidArtifact(name) }
    }

    private static func validate(
        _ value: KernelConformanceFixtureManifestV1,
        shape: KernelConformanceFixtureShapeV1
    ) throws {
        let actions = value.lifecycleTransitions.sorted { $0.sequence < $1.sequence }
        let adapterSet = Set(value.productionAdapters)
        let bindings = Dictionary(uniqueKeysWithValues: value.evidenceBindings.map { ($0.selector, $0.evidenceID) })
        guard value.schema == shape.schema, value.schemaVersion == 1,
              value.fixtureID == shape.fixtureID, value.shapeID == shape.shapeID,
              adapterSet.count == value.productionAdapters.count,
              adapterSet.isSubset(of: productionAdapters),
              actions.map(\.sequence) == Array(1...actions.count),
              Set(actions.map(\.action)) == Set(requiredLifecycle),
              actions.allSatisfy({ adapterSet.contains($0.adapter) && !$0.persistentConsumers.isEmpty && !$0.brandState.isEmpty }),
              !value.faultInjections.isEmpty,
              value.faultInjections.allSatisfy({ !$0.selectors.isEmpty && !$0.evidenceIDs.isEmpty && Set($0.selectors).isSubset(of: Set(selectors)) && Set($0.evidenceIDs).isSubset(of: Set(evidenceIDs)) }),
              Set(value.replicaSchedules.map(\.id)) == ["two-replica-golden", "three-replica-adversarial"],
              value.replicaSchedules.allSatisfy({ $0.replayCount == 2 && isSHA256($0.expectedSemanticSHA256) && isSHA256($0.expectedNormalizedSHA256) }),
              isSHA256(value.expectedNormalizedProjection.sha256),
              sha256(Data(hexV1: value.expectedNormalizedProjection.canonicalUTF8Hex) ?? Data()) == value.expectedNormalizedProjection.sha256,
              value.releaseAbsence.testOnly, !value.releaseAbsence.shippingAdoptionEnabled,
              !value.releaseAbsence.nativeCompileRan, !value.releaseAbsence.hostedDispatchRan,
              !value.releaseAbsence.acceptanceCredit, !value.releaseAbsence.releaseCredit,
              value.releaseAbsence.requiresAcceptedS10_6Reconciliation,
              bindings == Dictionary(uniqueKeysWithValues: zip(selectors, evidenceIDs)) else {
            throw KernelConformanceFixtureFailureV1.invalidArtifact(value.fixtureID)
        }
    }

    private static func validate(_ value: KernelConformanceScenarioGraphV1) throws {
        let nodeIDs = Set(value.nodes.map(\.id))
        let boundaries = Set(value.edges.map(\.boundary))
        let consumerIDs = Set(value.persistentConsumers.map(\.id))
        let brandIDs = Set(value.brandStates.map(\.id))
        guard value.schema == "V21P03C10KernelConformanceScenarioGraphV1", value.schemaVersion == 1,
              !nodeIDs.isEmpty, nodeIDs.count == value.nodes.count,
              value.nodes.allSatisfy({ productionAdapters.contains($0.adapter) && Set($0.persistentConsumers).isSubset(of: consumerIDs) && brandIDs.contains($0.brandState) }),
              Set(value.edges.map(\.id)).count == value.edges.count,
              value.edges.allSatisfy({ nodeIDs.contains($0.from) && nodeIDs.contains($0.to) && !$0.action.isEmpty && !$0.boundary.isEmpty }),
              Set(value.selectorBindings.map(\.selector)) == Set(selectors),
              Dictionary(uniqueKeysWithValues: value.selectorBindings.map { ($0.selector, $0.evidenceID) }) == Dictionary(uniqueKeysWithValues: zip(selectors, evidenceIDs)),
              value.selectorBindings.allSatisfy({ Set($0.nodeIDs).isSubset(of: nodeIDs) && Set($0.boundaries).isSubset(of: boundaries) }),
              consumerIDs.count == value.persistentConsumers.count,
              value.persistentConsumers.allSatisfy({ productionAdapters.contains($0.adapter) && !$0.publicationAuthority.isEmpty && !$0.recoveryDisposition.isEmpty }),
              brandIDs.count == value.brandStates.count,
              value.brandStates.allSatisfy({ !$0.changedUI && Set($0.nodeIDs).isSubset(of: nodeIDs) }) else {
            throw KernelConformanceFixtureFailureV1.invalidArtifact(value.schema)
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isNumber || ("a"..."f").contains(String($0)) }
    }

    static func c18PackageEvolutionSurfaceIsClosed() -> Bool {
        PackageEvolutionLifecycleV1.schema == "PACKAGE_EVOLUTION_V1"
            && PackageEvolutionLifecycleV1.persistent
            && PackageEvolutionLifecycleV1.migrationRequired
            && PackageEvolutionLifecycleV1.backupRestoreRequired
            && PackageEvolutionLifecycleV1.deleteEraseRequired
            && PackageEvolutionLifecycleV1.exportReportRequired
            && PackageEvolutionLifecycleV1.searchRebuildReplayRequired
            && PackageEvolutionLifecycleV1.writer == "SOLE_CANONICAL_WORKSPACE_WRITER"
            && PackageSemanticDiffClassificationV1.allCases.count == 5
            && PackageSandboxCheckKindV1.allCases.count == 12
    }
}

/// Test-only C40 receipt.  It proves that the typed authority aggregate can be
/// validated and replayed through the same canonical bytes without implying
/// native adoption, hosted verification, or release acceptance.
struct AuthorityCriterionConformanceReceiptV1: Equatable, Sendable {
    let canonicalAggregateSHA256: String
    let replayAggregateSHA256: String
    let sourceCount: Int
    let applicabilityCount: Int
    let classificationCount: Int
    let measurementProtocolCount: Int
    let derivedFactCount: Int
    let searchFieldIDs: [String]
    let reportSectionID: String
    let requiredReportWording: String
    let excludesLicensedSourceBytes: Bool
    let excludesRawLocators: Bool
}

extension KernelConformanceFixtureHarnessV1 {
    static func makeC40Receipt(
        for aggregate: AuthorityCriterionAggregateV1,
        workspaceID: WorkspaceID
    ) throws -> AuthorityCriterionConformanceReceiptV1 {
        try AuthorityCriterionRegistryV1.validate(aggregate, workspaceID: workspaceID)
        try aggregate.severityMappingReleases.forEach { try $0.validate() }
        let canonical = try AuthorityCriterionCanonicalCodecV1.encode(aggregate)
        let replayed = try AuthorityCriterionCanonicalCodecV1.decode(
            AuthorityCriterionAggregateV1.self,
            from: canonical
        )
        let replay = try AuthorityCriterionCanonicalCodecV1.encode(replayed)
        guard replayed == aggregate, replay == canonical else {
            throw KernelConformanceFixtureFailureV1.invalidArtifact("c40-canonical-replay")
        }
        return AuthorityCriterionConformanceReceiptV1(
            canonicalAggregateSHA256: sha256(canonical),
            replayAggregateSHA256: sha256(replay),
            sourceCount: aggregate.sourceReleases.count,
            applicabilityCount: aggregate.applicabilityContexts.count,
            classificationCount: aggregate.classificationBindings.count,
            measurementProtocolCount: aggregate.measurementProtocolReleases.count,
            derivedFactCount: aggregate.derivedFacts.count,
            searchFieldIDs: SearchAuthorityCriterionPersistencePolicyV1.fieldIDs,
            reportSectionID: ReportAuthorityCriterionProjectionPolicyV1.sectionID,
            requiredReportWording: ReportAuthorityCriterionProjectionPolicyV1.requiredWording,
            excludesLicensedSourceBytes: SearchAuthorityCriterionPersistencePolicyV1.excludesLicensedSourceBytes,
            excludesRawLocators: SearchAuthorityCriterionPersistencePolicyV1.excludesRawLocators
        )
    }
}

/// Test-only C40 mutation boundary evidence.  The helper exercises the
/// coordinator, typed predecessor/concurrency identity, canonical mutation
/// replay, and the journal-owned receipt binding without opening a second
/// persistence path.
struct AuthorityCriterionMutationBoundaryReceiptV1: Equatable, Sendable {
    let append: AuthorityCriterionMutationReceiptV1
    let successor: AuthorityCriterionMutationReceiptV1
    let appendMutationSHA256: String
    let successorMutationSHA256: String
    let appendReplayStable: Bool
    let successorReplayStable: Bool
    let coordinatorValidationPassed: Bool
    let staleAppendRejected: Bool
    let missingPredecessorRejected: Bool
    let foreignWorkspaceRejected: Bool
}

extension KernelConformanceFixtureHarnessV1 {
    static func makeC40MutationBoundaryReceipt() throws -> AuthorityCriterionMutationBoundaryReceiptV1 {
        func id(_ suffix: String) -> UUID { UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")! }

        let workspaceID = try WorkspaceID(rawValue: id("00000000c440"))
        let replicaID = try ReplicaID(rawValue: id("00000000c441"))
        let writerInstanceID = id("00000000c442")
        let identity = try WorkspaceReplicaIdentityV1(workspaceID: workspaceID, replicaID: replicaID)
        let recordedAt = Date(timeIntervalSince1970: 1_735_700_000)
        let appendMutationID = try MutationIDV1(rawValue: id("00000000c443"))
        let successorMutationID = try MutationIDV1(rawValue: id("00000000c444"))
        let source = try AuthoritySourceReleaseV1(
            releaseID: id("00000000c445"), workspaceID: workspaceID,
            sourceID: id("00000000c446"), sourceType: .guidance,
            designation: "C40 mutation boundary", editionOrRevision: "1",
            retrievedAt: recordedAt, licenseStorageDisposition: .notStored,
            recordedAt: recordedAt.addingTimeInterval(1), revision: 1,
            mutationID: appendMutationID
        )
        let successor = try AuthoritySourceReleaseV1(
            releaseID: id("00000000c447"), workspaceID: workspaceID,
            sourceID: source.sourceID, sourceType: source.sourceType,
            designation: source.designation, editionOrRevision: "2",
            retrievedAt: recordedAt.addingTimeInterval(2),
            supersedesReleaseID: source.releaseID,
            licenseStorageDisposition: .notStored,
            recordedAt: recordedAt.addingTimeInterval(3), revision: 2,
            mutationID: successorMutationID
        )

        let appendPayload = AuthorityCriterionMutationPayloadV1.appendAuthoritySource(source)
        let appendPrepared = try AuthorityCriterionCoordinatorV1.prepare(
            workspaceID: workspaceID, expectedRevision: 0, payload: appendPayload
        )
        try appendPrepared.validate()
        let appendMutation = appendPrepared.mutation
        let appendData = try appendMutation.canonicalData()
        let appendReplay = try AuthorityCriterionMutationV1.decodeCanonical(from: appendData)

        let successorPayload = AuthorityCriterionMutationPayloadV1.supersedeAuthoritySource(successor)
        let successorPrepared = try AuthorityCriterionCoordinatorV1.prepare(
            workspaceID: workspaceID, expectedRevision: 1, payload: successorPayload
        )
        try successorPrepared.validate()
        let successorMutation = successorPrepared.mutation
        let successorData = try successorMutation.canonicalData()
        let successorReplay = try AuthorityCriterionMutationV1.decodeCanonical(from: successorData)

        let appendIdentity = try appendMutation.affectedIdentity
        let successorIdentity = try successorMutation.affectedIdentity
        let predecessorIdentity = try successorMutation.postImage.predecessorIdentity
        let appendConcurrencyIdentity = try appendMutation.concurrencyIdentity
        let successorConcurrencyIdentity = try successorMutation.concurrencyIdentity
        guard predecessorIdentity == appendIdentity,
              appendConcurrencyIdentity == appendIdentity,
              successorConcurrencyIdentity == appendIdentity else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("c40-mutation-identities")
        }

        let appendExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: workspaceID, generationID: id("00000000c448"),
            writerInstanceID: writerInstanceID, workspaceRevision: 0,
            entityRevisions: [.init(identity: appendIdentity, revision: 0)]
        )
        let appendEnvelope = try MutationEnvelopeV1(
            request: .init(
                mutationID: appendMutation.mutationID,
                expectedRevision: appendExpected,
                command: .applyAuthorityCriterion(appendMutation)
            ), identity: identity
        )
        let appendResulting = try WorkspaceExpectedRevisionV1(
            workspaceID: workspaceID, generationID: appendExpected.generationID,
            writerInstanceID: writerInstanceID, workspaceRevision: 1,
            entityRevisions: [.init(identity: appendIdentity, revision: 1)]
        )
        let appendReceipt = try MutationReceiptV1(
            identity: .init(workspaceID: workspaceID, replicaID: replicaID, localSequence: 1),
            envelope: appendEnvelope,
            resultingRevision: try MutationPortableExpectedRevisionV1(appendResulting),
            postImages: [try appendPayload.mutationPostImage],
            committedAt: recordedAt.addingTimeInterval(4)
        )
        let typedAppendReceipt = try AuthorityCriterionMutationReceiptV1(
            mutation: appendMutation, mutationReceipt: appendReceipt
        )

        let successorExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: workspaceID, generationID: appendExpected.generationID,
            writerInstanceID: writerInstanceID, workspaceRevision: 1,
            entityRevisions: [.init(identity: appendIdentity, revision: 1)]
        )
        let successorEnvelope = try MutationEnvelopeV1(
            request: .init(
                mutationID: successorMutation.mutationID,
                expectedRevision: successorExpected,
                command: .applyAuthorityCriterion(successorMutation)
            ), identity: identity
        )
        let successorResulting = try WorkspaceExpectedRevisionV1(
            workspaceID: workspaceID, generationID: appendExpected.generationID,
            writerInstanceID: writerInstanceID, workspaceRevision: 2,
            entityRevisions: [.init(identity: successorIdentity, revision: 2)]
        )
        let successorReceipt = try MutationReceiptV1(
            identity: .init(workspaceID: workspaceID, replicaID: replicaID, localSequence: 2),
            envelope: successorEnvelope,
            resultingRevision: try MutationPortableExpectedRevisionV1(successorResulting),
            postImages: [try successorPayload.mutationPostImage],
            committedAt: recordedAt.addingTimeInterval(5)
        )
        let typedSuccessorReceipt = try AuthorityCriterionMutationReceiptV1(
            mutation: successorMutation, mutationReceipt: successorReceipt
        )
        let appendOutcome = WorkspaceMutationOutcomeV1(
            mutationID: appendMutation.mutationID,
            commandDigest: appendPrepared.canonicalSHA256,
            occurredAt: recordedAt.addingTimeInterval(6),
            before: try WorkspaceRevisionV1(
                workspaceID: workspaceID, generationID: appendExpected.generationID,
                writerInstanceID: writerInstanceID, revision: 0,
                entityRevisions: [.init(identity: appendIdentity, revision: 0)]
            ),
            after: try WorkspaceRevisionV1(
                workspaceID: workspaceID, generationID: appendExpected.generationID,
                writerInstanceID: writerInstanceID, revision: 1,
                entityRevisions: [.init(identity: appendIdentity, revision: 1)]
            ),
            effect: try WorkspaceMutationEffectV1(
                affectedEntities: [appendIdentity], temporaryRelativePath: "authority/c40/append"
            )
        )
        try AuthorityCriterionCoordinatorV1.validate(outcome: appendOutcome, for: appendPrepared)
        let successorOutcome = WorkspaceMutationOutcomeV1(
            mutationID: successorMutation.mutationID,
            commandDigest: successorPrepared.canonicalSHA256,
            occurredAt: recordedAt.addingTimeInterval(7),
            before: try WorkspaceRevisionV1(
                workspaceID: workspaceID, generationID: successorExpected.generationID,
                writerInstanceID: writerInstanceID, revision: 1,
                entityRevisions: [.init(identity: appendIdentity, revision: 1)]
            ),
            after: try WorkspaceRevisionV1(
                workspaceID: workspaceID, generationID: successorExpected.generationID,
                writerInstanceID: writerInstanceID, revision: 2,
                entityRevisions: [.init(identity: successorIdentity, revision: 2)]
            ),
            effect: try WorkspaceMutationEffectV1(
                affectedEntities: [successorIdentity], temporaryRelativePath: "authority/c40/successor"
            )
        )
        try AuthorityCriterionCoordinatorV1.validate(outcome: successorOutcome, for: successorPrepared)
        let appendReceiptReplay = try AuthorityCriterionCanonicalCodecV1.decode(
            AuthorityCriterionMutationReceiptV1.self,
            from: AuthorityCriterionCanonicalCodecV1.encode(typedAppendReceipt)
        )
        let successorReceiptReplay = try AuthorityCriterionCanonicalCodecV1.decode(
            AuthorityCriterionMutationReceiptV1.self,
            from: AuthorityCriterionCanonicalCodecV1.encode(typedSuccessorReceipt)
        )

        let staleAppendRejected: Bool
        do {
            _ = try AuthorityCriterionCoordinatorV1.prepare(
                workspaceID: workspaceID, expectedRevision: 1, payload: appendPayload
            )
            staleAppendRejected = false
        } catch AuthorityCriterionCoordinatorFailureV1.staleRevision {
            staleAppendRejected = true
        }

        let missingPredecessorRejected: Bool
        let malformedSuccessor = try AuthoritySourceReleaseV1(
            releaseID: id("00000000c449"), workspaceID: workspaceID,
            sourceID: source.sourceID, sourceType: source.sourceType,
            designation: source.designation, editionOrRevision: "3",
            retrievedAt: recordedAt.addingTimeInterval(6),
            licenseStorageDisposition: .notStored,
            recordedAt: recordedAt.addingTimeInterval(7), revision: 2,
            mutationID: try MutationIDV1(rawValue: id("00000000c44a"))
        )
        do {
            try AuthorityCriterionMutationPayloadV1.supersedeAuthoritySource(malformedSuccessor).validate()
            missingPredecessorRejected = false
        } catch {
            missingPredecessorRejected = true
        }

        let foreignWorkspaceRejected: Bool
        let foreignWorkspace = try WorkspaceID(rawValue: id("00000000c44b"))
        let foreignSource = try source.rebound(to: foreignWorkspace)
        do {
            _ = try AuthorityCriterionCoordinatorV1.prepare(
                workspaceID: workspaceID, expectedRevision: 0,
                payload: .appendAuthoritySource(foreignSource)
            )
            foreignWorkspaceRejected = false
        } catch AuthorityCriterionCoordinatorFailureV1.wrongWorkspace {
            foreignWorkspaceRejected = true
        }

        return AuthorityCriterionMutationBoundaryReceiptV1(
            append: typedAppendReceipt,
            successor: typedSuccessorReceipt,
            appendMutationSHA256: try appendMutation.canonicalSHA256(),
            successorMutationSHA256: try successorMutation.canonicalSHA256(),
            appendReplayStable: appendReplay == appendMutation && appendReceiptReplay == typedAppendReceipt,
            successorReplayStable: successorReplay == successorMutation && successorReceiptReplay == typedSuccessorReceipt,
            coordinatorValidationPassed: true,
            staleAppendRejected: staleAppendRejected,
            missingPredecessorRejected: missingPredecessorRejected,
            foreignWorkspaceRejected: foreignWorkspaceRejected
        )
    }
}

struct KernelConformanceLifecycleTraceV1: Equatable, Sendable {
    let shapeID: String
    let executedActions: [String]
    let sourceRevision: SearchSourceRevisionV1
    let indexedRecordCount: Int
    let restoredAssetCount: Int
    let restoredReportCount: Int
    let deletionID: UUID
    let erasedWorkspaceIsEmpty: Bool
}

struct KernelConformanceNormalizedReplicaProjectionV1: Equatable, Hashable, Sendable {
    let semanticSHA256: String
    let canonicalSnapshotSHA256: String
    let tombstoneStableKeys: [String]
    let unresolvedConflictSHA256: [String]
    let contentDispositionSHA256: String
    let observedMutationIDs: [String]
    let contentDependencyIDs: [String]
    let siteCount: Int
    let assetCount: Int
    let placementEventCount: Int
}

struct KernelConformanceReplicaScheduleReceiptV1: Equatable, Sendable {
    let shapeID: String
    let replicaCount: Int
    let deliveries: [String]
    let firstRun: KernelConformanceNormalizedReplicaProjectionV1
    let secondRun: KernelConformanceNormalizedReplicaProjectionV1
    let firstRunReplicaProjectionCount: Int
    let secondRunReplicaProjectionCount: Int
    let postConvergence: KernelConformancePostConvergenceReceiptV1
}

struct KernelConformancePostConvergenceReceiptV1: Equatable, Sendable {
    let archivePrepared: Bool
    let restoreActivated: Bool
    let searchRebuilt: Bool
    let deletionCommitted: Bool
    let eraseActivated: Bool
    let recoveryCompleted: Bool
}

struct KernelConformanceSearchFaultReceiptV1: Equatable, Sendable {
    let boundary: String
    let visibleFailure: String
    let coldRecoverySucceeded: Bool
    let noPartialAuthority: Bool
    let disposition: SearchIndexReconciliationV1?
    let resumedFromCheckpoint: Bool
    let canonicalRecordCount: Int
    let residualStagingCount: Int
}

struct KernelConformanceCompatibilityBoundsReceiptV1: Equatable, Sendable {
    let unknownBatchVersionRejected: Bool
    let unknownBatchFieldRejected: Bool
    let unknownConflictRuleRejected: Bool
    let unknownConflictVersionRejected: Bool
    let unknownRegisteredCodecRejected: Bool
    let noncanonicalCodecRejected: Bool
    let observedMaximumPageItems: Int
    let observedMaximumPageBytes: Int
    let configuredMaximumGapPages: Int
    let configuredMaximumReplayAttempts: Int
    let scaleItemCount: Int
    let scalePageItemLimit: Int
    let scalePageCount: Int
    let scaleMaximumResidentBytes: Int
    let scaleSemanticSHA256: String
}

struct KernelConformanceRendererReconciliationReceiptV1: Equatable, Sendable {
    let corpusSchema: String
    let inheritedAcceptanceTests: [String]
    let snapshotSHA256: String
    let pdfSHA256: String
    let openJSONSHA256: String
    let structuredTextSHA256: String
    let semanticSHA256: String
    let orderedSemanticIDs: [String]
    let pdfReopened: Bool
    let openJSONReopened: Bool
    let structuredTextReopened: Bool
    let repeatRenderByteIdentical: Bool
    let zeroOrCompleteBoundaryCount: Int
    let retryByteIdentical: Bool
    let legacySnapshotRoundTrip: Bool
    let oldProfileRendered: Bool
    let hostileTextRejectionCount: Int
    let privacyCanaryRejected: Bool
    let declaredHostileCaseRejectionCount: Int
    let privacyCanaryRejectionCount: Int
    let unsupportedAccessibilityClaimRejected: Bool
    let originalAmendedSupersededReconciled: Bool
    let originalHistoricalBytesImmutable: Bool
}

struct KernelConformanceFaultBoundaryReceiptV1: Equatable, Sendable {
    let boundary: String
    let family: String
    let visibleFailure: String
    let operationAttempted: String
    let recoveryOperation: String
    let coldRecoverySucceeded: Bool
    let noPartialAuthority: Bool
    let canonicalRowCount: Int
    let residualIntentCount: Int
    let orphanPathCount: Int
}

@MainActor
private final class KernelConformanceJournalInterruptionBoxV1 {
    var point: LocalChangeJournalV1.InterruptionPointV1 = .none
}

private actor KernelConformanceSearchSourceV1: SearchCanonicalProjectionSourceV1 {
    let revision: SearchSourceRevisionV1
    let records: [SearchIndexProjectionRecordV1]
    private var failAtOffset: Int?

    init(
        revision: SearchSourceRevisionV1,
        records: [SearchIndexProjectionRecordV1],
        failAtOffset: Int? = nil
    ) {
        self.revision = revision
        self.records = records.sorted()
        self.failAtOffset = failAtOffset
    }

    func currentSearchSourceRevision() async throws -> SearchSourceRevisionV1 { revision }

    func searchProjectionPage(
        at source: SearchSourceRevisionV1,
        canonicalOffset: Int,
        limit: Int
    ) async throws -> SearchCanonicalProjectionPageV1 {
        try Task.checkCancellation()
        guard source == revision else {
            throw SearchIndexRebuildFailureV1.sourceChangedDuringRebuild
        }
        if failAtOffset == canonicalOffset {
            failAtOffset = nil
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("search-checkpoint-interruption")
        }
        let end = min(records.count, canonicalOffset + limit)
        let page = canonicalOffset < end ? Array(records[canonicalOffset..<end]) : []
        return try SearchCanonicalProjectionPageV1(
            requestedCanonicalOffset: canonicalOffset,
            nextCanonicalOffset: end,
            isComplete: end == records.count,
            records: page
        )
    }
}

@MainActor
private final class KernelConformanceReplicaNodeV1 {
    let label: String
    let applicationSupportURL: URL
    let session: StoreGenerationSession
    let coordinator: StoreSessionCoordinator
    let journal: LocalChangeJournalV1

    init(
        label: String,
        applicationSupportURL: URL,
        identity: WorkspaceReplicaIdentityV1,
        limits: ChangeJournalLimitsV1,
        profile: WorkspacePackageLifecycleProfileV1,
        interruptionPoint: @escaping () -> LocalChangeJournalV1.InterruptionPointV1 = { .none }
    ) throws {
        self.label = label
        self.applicationSupportURL = applicationSupportURL
        session = try StoreGenerationFactory(
            applicationSupportURL: applicationSupportURL,
            pointerEnrichmentIdentity: identity
        ).openOrBootstrapCurrent()
        coordinator = try StoreSessionCoordinator(validatingSession: session)
        let registry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        let dependencies = try coordinator.packageLifecycleDependencies(profileRegistry: registry)
        let backup = BackupExportService(
            modelContext: session.modelContext,
            generationRootURL: session.generationRootURL,
            lifecycleDependencies: dependencies,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max })
        )
        journal = try coordinator.localChangeJournal(
            backupExport: backup,
            limits: limits,
            policyResolver: { _, _ in
                try ConflictPolicyV1(
                    policyID: "v9_20_r01_append_union", rule: .stableIDAppendUnion
                )
            },
            contentReferenceResolver: { _ in throw ContentContractFailureV1.missingContent },
            contentEntryResolver: { _ in throw ContentContractFailureV1.missingContent },
            interruptionPoint: interruptionPoint
        )
    }
}

private struct KernelConformanceReplicaRunV1 {
    let projections: [KernelConformanceNormalizedReplicaProjectionV1]
    let postConvergence: KernelConformancePostConvergenceReceiptV1?
}

@MainActor
final class KernelConformanceProductionHarnessV1 {
    static let productionExecutedFaultBoundaries: Set<String> = [
        "FINALIZATION_SNAPSHOT_STAGING_WRITE",
        "FINALIZATION_SNAPSHOT_PROMOTION_MOVE",
        "FINALIZATION_INTENT_PHASE_WRITE",
        "FINALIZATION_MODEL_SAVE",
        "WORK_MODEL_SAVE",
        "WORK_AFTER_EVIDENCE_PROMOTION",
        "REPORT_RENDER",
        "REPORT_STAGE_WRITE",
        "REPORT_PROMOTION",
        "REPORT_REREAD",
        "REPORT_READY_SAVE",
        "REPORT_FAILED_STATE_SAVE",
        "REPORT_RETRY_TRANSITION_SAVE",
        "JOURNAL_AFTER_CHECKPOINT_PREPARED",
        "JOURNAL_AFTER_CHECKPOINT_STATE_WRITTEN",
        "JOURNAL_AFTER_REPLAY_MUTATION",
        "JOURNAL_AFTER_COMPACTION_STATE_WRITTEN",
        "RESTORE_BEFORE_PREPARED_WRITE",
        "RESTORE_AFTER_PREPARED_WRITE",
        "RESTORE_BEFORE_GENERATION_INSTALL",
        "RESTORE_AFTER_GENERATION_INSTALL",
        "RESTORE_BEFORE_POINTER_SWITCH",
        "RESTORE_AFTER_POINTER_SWITCH",
        "RESTORE_BEFORE_NEW_GENERATION_VALIDATION",
        "RESTORE_AFTER_NEW_GENERATION_VALIDATION",
        "RESTORE_BEFORE_CLEANUP",
        "DELETE_PREPARED_JOURNAL",
        "DELETE_DATABASE_SAVE",
        "DELETE_COMMITTED_PHASE",
        "DELETE_FILE_CLEANUP",
        "DELETE_JOURNAL_REMOVAL",
        "ERASE_AFTER_EMPTY_GENERATION_DIRECTORY_CREATE",
        "ERASE_BEFORE_PREPARED_WRITE",
        "ERASE_AFTER_PREPARED_WRITE",
        "ERASE_BEFORE_POINTER_SWITCH",
        "ERASE_AFTER_POINTER_SWITCH",
        "ERASE_BEFORE_POINTER_PHASE_WRITE",
        "ERASE_AFTER_POINTER_PHASE_WRITE",
        "ERASE_BEFORE_SESSION_ACTIVATION",
        "ERASE_AFTER_SESSION_ACTIVATION",
        "ERASE_BEFORE_SESSION_PHASE_WRITE",
        "ERASE_AFTER_SESSION_PHASE_WRITE",
        "ERASE_BEFORE_CLEANUP",
        "ERASE_AFTER_CLEANUP",
        "ERASE_BEFORE_CLEANUP_PHASE_WRITE",
        "ERASE_AFTER_CLEANUP_PHASE_WRITE",
        "ERASE_BEFORE_JOURNAL_REMOVAL",
        "SEARCH_CANCELLATION",
        "SEARCH_CHECKPOINT",
        "SEARCH_STALE",
        "SEARCH_AHEAD",
        "SEARCH_INCOMPATIBLE",
        "SEARCH_PUBLICATION_TOKEN",
    ]

    private static let c06PrivacyCanaries = [
        "PRIVATE-CANARY-NOTE",
        "ORIGINAL-CANARY-MEDIA",
        "CONTACT-CANARY",
        "COST-CANARY",
        "SECRET-CANARY",
        "LOCAL-ID-CANARY",
        "C:\\private\\canary.jpg",
        "DIAGNOSTIC-CANARY",
        "VERIFIED-PERSON-CANARY",
    ]

    let root: URL
    private var activeApplicationSupportURL: URL
    private(set) var session: StoreGenerationSession!
    private(set) var coordinator: StoreSessionCoordinator!

    init(label: String) throws {
        let harnessRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V9_20KernelConformanceTests-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        root = harnessRoot
        activeApplicationSupportURL = harnessRoot
        session = try StoreGenerationFactory(
            applicationSupportURL: activeApplicationSupportURL
        ).openOrBootstrapCurrent()
        coordinator = try StoreSessionCoordinator(validatingSession: session)
    }

    func exerciseFullLifecycle(
        shape: KernelConformanceFixtureShapeV1
    ) async throws -> KernelConformanceLifecycleTraceV1 {
        var actions: [String] = []
        let validationProfile = try Self.profile(for: shape)
        let validationRegistry = try WorkspacePackageLifecycleProfileRegistryV1(
            profiles: [validationProfile]
        )
        guard try validationRegistry.resolve(validationProfile.release) == validationProfile else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("production-profile-validation")
        }
        _ = try coordinator.packageLifecycleDependencies(profileRegistry: validationRegistry)
        actions.append("VALIDATE")
        try await createFirstSign(assetLabel: shape.shapeID, profile: validationProfile)
        actions.append(contentsOf: try await exercisePackageLifecycle(
            shape: shape, profile: validationProfile
        ))
        try ReportProjectionRegistryV2().validate()
        actions.append("PROJECT")
        _ = try prepareProductionArchive()
        actions.append("ARCHIVE")
        let restored = try await exerciseArchiveRestoreRoundTrip()
        actions.append("RESTORE")
        let restoredAssetCount = try restored.modelContext.fetchCount(FetchDescriptor<Asset>())
        let restoredReportCount = try restored.modelContext.fetchCount(FetchDescriptor<Report>())
        let search = try await coordinator.rebuildSearchProjectionIfNeeded()
        actions.append("SEARCH")
        let deletion = try await deleteFirstAssetThroughProductionService(
            profile: validationProfile
        )
        actions.append("DELETE")
        if shape == .measurementRepeat {
            try relaunchCanonicalSession()
            let registry = try WorkspacePackageLifecycleProfileRegistryV1(
                profiles: [validationProfile]
            )
            let dependencies = try coordinator.packageLifecycleDependencies(
                profileRegistry: registry
            )
            let deletionRecovery = WholeSignDeletionService(
                modelContext: coordinator.modelContext,
                lifecycleDependencies: dependencies
            )
            let firstRecovery = try await deletionRecovery.reconcile()
            let secondRecovery = try await deletionRecovery.reconcile()
            let ledger = try DeletionLedgerStore(context: coordinator.modelContext).snapshot()
            guard firstRecovery.cancelledPreparedCount == 0,
                  firstRecovery.completedCommittedCount == 0,
                  secondRecovery.cancelledPreparedCount == 0,
                  secondRecovery.completedCommittedCount == 0,
                  try coordinator.modelContext.fetchCount(FetchDescriptor<Asset>()) == 0,
                  ledger.entries.contains(where: {
                      $0.identity.kind == .asset && $0.identity.id == deletion.assetID
                  }) else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage("delete-recovery")
            }
            actions.append("RECOVER")
            _ = try await eraseWorkspaceThroughProductionService(profile: validationProfile)
            actions.append("ERASE")
        } else {
            _ = try await eraseWorkspaceThroughProductionService(profile: validationProfile)
            actions.append("ERASE")
            try relaunchCanonicalSession()
            actions.append("RECOVER")
        }
        let empty = try coordinator.modelContext.fetchCount(FetchDescriptor<Site>()) == 0
            && coordinator.modelContext.fetchCount(FetchDescriptor<Asset>()) == 0
            && coordinator.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()) == 0
            && coordinator.modelContext.fetchCount(FetchDescriptor<Report>()) == 0
        guard actions.count == KernelConformanceFixtureHarnessV1.requiredLifecycle.count,
              KernelConformanceFixtureHarnessV1.requiredLifecycle.allSatisfy({ action in
                  actions.filter { $0 == action }.count == 1
              }) else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("observed-lifecycle")
        }
        return KernelConformanceLifecycleTraceV1(
            shapeID: shape.shapeID,
            executedActions: actions,
            sourceRevision: search.source,
            indexedRecordCount: search.indexedRecordCount,
            restoredAssetCount: restoredAssetCount,
            restoredReportCount: restoredReportCount,
            deletionID: deletion.deletionID,
            erasedWorkspaceIsEmpty: empty
        )
    }

    private func relaunchCanonicalSession() throws {
        coordinator = nil
        session = nil
        let reopened = try StoreGenerationFactory(applicationSupportURL: activeApplicationSupportURL)
            .openOrBootstrapCurrent()
        session = reopened
        coordinator = try StoreSessionCoordinator(validatingSession: reopened)
    }

    func replayReplicaSchedule(
        shape: KernelConformanceFixtureShapeV1,
        replicas: [String],
        deliveries: [String]
    ) async throws -> KernelConformanceReplicaScheduleReceiptV1 {
        guard (replicas.count == 2 || replicas.count == 3),
              replicas == replicas.sorted(),
              Set(replicas).count == replicas.count,
              Set(replicas).isSubset(of: Set(["A", "B", "C"])),
              !deliveries.isEmpty else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("replica-schedule")
        }
        let fixture = try KernelConformanceFixtureHarnessV1.loadManifest(shape)
        guard fixture.shapeID == shape.shapeID,
              fixture.replicaSchedules.contains(where: {
                  $0.replicas == replicas && $0.deliveries == deliveries && $0.replayCount == 2
              }) else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage(
                "\(shape.shapeID)-replica-schedule"
            )
        }
        let profile = try Self.profile(for: shape)
        let firstRun = try await runReplicaSchedule(
            runLabel: "first-\(shape.shapeID)-\(replicas.joined())", replicas: replicas,
            deliveries: deliveries, profile: profile, exercisePostConvergence: true
        )
        let secondRun = try await runReplicaSchedule(
            runLabel: "second-\(shape.shapeID)-\(replicas.joined())", replicas: replicas,
            deliveries: deliveries, profile: profile, exercisePostConvergence: false
        )
        let first = firstRun.projections, second = secondRun.projections
        guard Set(first).count == 1, Set(second).count == 1,
              let firstNormalized = first.first,
              let secondNormalized = second.first,
              firstNormalized == secondNormalized,
              let post = firstRun.postConvergence else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("replica-convergence")
        }
        return KernelConformanceReplicaScheduleReceiptV1(
            shapeID: shape.shapeID,
            replicaCount: replicas.count,
            deliveries: deliveries,
            firstRun: firstNormalized,
            secondRun: secondNormalized,
            firstRunReplicaProjectionCount: first.count,
            secondRunReplicaProjectionCount: second.count,
            postConvergence: post
        )
    }

    func exerciseReplicaSchedule(
        shape: KernelConformanceFixtureShapeV1,
        replicas: [String],
        deliveries: [String]
    ) async throws -> KernelConformanceReplicaScheduleReceiptV1 {
        try await replayReplicaSchedule(
            shape: shape, replicas: replicas, deliveries: deliveries
        )
    }

    func exerciseCompatibilityAndBounds() async throws
        -> KernelConformanceCompatibilityBoundsReceiptV1 {
        let c11 = try Self.loadC11Bounds()
        let profile = try Self.profile(for: .checklist)
        let limits = try ChangeJournalLimitsV1(
            maximumChangesPerBatch: c11.maximumPageItems,
            maximumBatchBytes: c11.maximumPageBytes,
            maximumEntitiesPerCheckpoint: c11.scaleItemCount,
            maximumContentEntriesPerCheckpoint: c11.scaleItemCount,
            maximumReplicaFrontiers: 4,
            maximumConflicts: 64
        )
        let workspaceID = WorkspaceID(rawValue: Self.fixedUUID(label: "K", slot: 600))
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: workspaceID,
            replicaID: ReplicaID(rawValue: Self.fixedUUID(label: "K", slot: 601))
        )
        let support = isolatedFaultRoot("compatibility-bounds")
        defer { try? FileManager.default.removeItem(at: support) }
        let node = try KernelConformanceReplicaNodeV1(
            label: "compatibility", applicationSupportURL: support,
            identity: identity, limits: limits, profile: profile
        )
        let siteID = Self.fixedUUID(label: "K", slot: 602)
        _ = try node.coordinator.workspaceWriter.execute(
            .createFirstSign(.init(
                siteID: siteID,
                newSite: .init(id: siteID, label: "Bounds Site", address: nil, timeZoneID: "UTC"),
                assetID: Self.fixedUUID(label: "K", slot: 603),
                assetLabel: "Bounds Asset", packID: profile.package.packID,
                packSchemaVersion: profile.package.schemaVersion,
                packContentVersion: profile.package.contentVersion,
                createdAt: Date(timeIntervalSince1970: 1_700_060_000),
                initialPlacementMutationID: try MutationIDV1(
                    rawValue: Self.fixedUUID(label: "K", slot: 604)
                ),
                initialPlacementEventID: Self.fixedUUID(label: "K", slot: 605),
                initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(
                    rawValue: Self.fixedUUID(label: "K", slot: 606)
                )
            )),
            mutationID: try MutationIDV1(rawValue: Self.fixedUUID(label: "K", slot: 607))
        )
        let checkpoint = try node.journal.prepareCheckpoint(
            supplement: .init(contentEntries: [], reversalEligibility: [])
        )
        _ = try node.journal.activatePreparedCheckpoint(checkpoint)
        let timeZones = [
            "America/New_York", "America/Chicago",
            "America/Denver", "America/Los_Angeles",
        ]
        for index in timeZones.indices {
            _ = try node.coordinator.workspaceWriter.execute(
                .updateSiteTimeZone(.init(
                    siteID: siteID, timeZoneID: timeZones[index],
                    confirmedAt: Date(timeIntervalSince1970: 1_700_060_100 + Double(index))
                )),
                mutationID: try MutationIDV1(
                    rawValue: Self.fixedUUID(label: "K", slot: 610 + index)
                )
            )
        }
        var cursor = try node.journal.initialCursor(
            consumerReplicaID: ReplicaID(rawValue: Self.fixedUUID(label: "D", slot: 620)),
            checkpointID: checkpoint.manifest.checkpointID
        )
        var observedItemMaximum = 0
        var observedByteMaximum = 0
        var firstBatch: ChangeBatchV1?
        while true {
            let batch = try node.journal.page(after: cursor)
            if firstBatch == nil { firstBatch = batch }
            let bytes = try batch.canonicalData(limits: limits).count
            observedItemMaximum = max(observedItemMaximum, batch.changes.count)
            observedByteMaximum = max(observedByteMaximum, bytes)
            cursor = batch.afterCursor
            if batch.changes.isEmpty { break }
        }
        guard let batch = firstBatch else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("c11-production-page")
        }
        let canonicalBatch = try batch.canonicalData(limits: limits)
        let unknownBatchVersionRejected = try Self.decodeMutationRejected(
            canonicalBatch, key: "schemaVersion", replacement: 999,
            as: ChangeBatchV1.self, expected: .batchVersion
        )
        let unknownBatchFieldRejected = try Self.decodeMutationRejected(
            canonicalBatch, key: "unknownField", replacement: true,
            as: ChangeBatchV1.self, expected: .batchField
        )
        let policy = try ConflictPolicyV1(
            policyID: "v9_20_compatibility", rule: .stableIDAppendUnion
        )
        let policyData = try WorkspaceMutationCanonicalV1.data(policy)
        let unknownConflictRuleRejected = try Self.decodeCanonicalPolicyMutationRejected(
            policyData, key: "rule", replacement: "UNKNOWN_RULE", expectedRuleFailure: true
        )
        let unknownConflictVersionRejected = try Self.decodeCanonicalPolicyMutationRejected(
            policyData, key: "schemaVersion", replacement: 999, expectedRuleFailure: false
        )
        let noncanonicalCodecRejected: Bool
        do {
            _ = try ReplicationCodecV1(
                codecID: "Unknown Codec", readableVersions: [1], currentWriteVersion: 1
            )
            noncanonicalCodecRejected = false
        } catch { noncanonicalCodecRejected = true }
        let unknownRegisteredCodecRejected = try Self.unknownRegisteredCodecIsRejected()

        var scaleHasher = SHA256()
        var scalePageCount = 0
        var residentMaximum = 0
        var pageBytes = 0
        var pageItems = 0
        for index in 0..<c11.scaleItemCount {
            let item = Data(String(
                format: "asset:%05d|Asset-%05d\n", index, index
            ).utf8)
            scaleHasher.update(data: item)
            pageBytes += item.count
                + MemoryLayout<Data>.stride
                + MemoryLayout<String>.stride
            pageItems += 1
            if pageItems == c11.scalePageItems || index == c11.scaleItemCount - 1 {
                scalePageCount += 1
                residentMaximum = max(residentMaximum, pageBytes)
                pageBytes = 0
                pageItems = 0
            }
        }
        let scaleSHA = scaleHasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard observedItemMaximum == c11.maximumPageItems,
              observedByteMaximum <= c11.maximumPageBytes,
              scalePageCount == c11.scaleExpectedPageCount,
              residentMaximum <= c11.scaleMaximumResidentBytes else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("c11-bounds")
        }
        guard unknownBatchVersionRejected, unknownBatchFieldRejected,
              unknownConflictRuleRejected, unknownConflictVersionRejected,
              unknownRegisteredCodecRejected, noncanonicalCodecRejected else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("compatibility-rejection")
        }
        return .init(
            unknownBatchVersionRejected: unknownBatchVersionRejected,
            unknownBatchFieldRejected: unknownBatchFieldRejected,
            unknownConflictRuleRejected: unknownConflictRuleRejected,
            unknownConflictVersionRejected: unknownConflictVersionRejected,
            unknownRegisteredCodecRejected: unknownRegisteredCodecRejected,
            noncanonicalCodecRejected: noncanonicalCodecRejected,
            observedMaximumPageItems: observedItemMaximum,
            observedMaximumPageBytes: observedByteMaximum,
            configuredMaximumGapPages: c11.maximumGapPages,
            configuredMaximumReplayAttempts: c11.maximumReplayAttempts,
            scaleItemCount: c11.scaleItemCount,
            scalePageItemLimit: c11.scalePageItems,
            scalePageCount: scalePageCount,
            scaleMaximumResidentBytes: residentMaximum,
            scaleSemanticSHA256: scaleSHA
        )
    }

    func exerciseRendererReconciliation() throws
        -> KernelConformanceRendererReconciliationReceiptV1 {
        let corpusData = try KernelConformanceFixtureHarnessV1.readRequiredData(
            KernelConformanceFixtureHarnessV1.c06CorpusURL()
        )
        guard let corpus = try JSONSerialization.jsonObject(with: corpusData) as? [String: Any],
              let corpusSchema = corpus["schema"] as? String,
              corpusSchema == "V21P03C06SnapshotProjectionCorpusV1",
              corpus["schemaVersion"] as? Int == 1,
              let formats = corpus["projectionFormats"] as? [String],
              formats == ["OPEN_JSON", "PDF", "STRUCTURED_TEXT"],
              let inheritedAcceptanceTests = corpus["inheritedAcceptanceTests"] as? [String],
              Set(inheritedAcceptanceTests) == Set([
                  "hostile text and accessibility-claim negatives",
                  "independent language-neutral fixture validation",
                  "old package/profile render",
                  "original/amended/superseded report and open-JSON reconciliation",
                  "PDF/JSON/text reconciliation",
                  "repeat-render byte equality",
              ]), inheritedAcceptanceTests.count == 6,
              let hostileCaseIDs = corpus["hostileCases"] as? [String],
              Set(hostileCaseIDs) == Set([
                  "ABSOLUTE_LOCAL_PATH", "BIDI_OVERRIDE", "CAPABILITY_SECRET",
                  "CLOSED_ENUM_UNKNOWN", "CONTACT_DATA", "CONTROL_CHARACTER",
                  "DIAGNOSTIC_RAW_ERROR", "DIRECT_COST", "DUPLICATE_SEMANTIC_ID",
                  "EXPLICIT_NULL_FOR_REQUIRED", "FORGED_CONFIRMATION",
                  "LOCAL_IDENTIFIER", "MISSING_REQUIRED", "ORIGINAL_MEDIA",
                  "PRIVATE_NOTE", "PROJECTION_DIGEST_MISMATCH",
                  "STALE_PROFILE_BINDING", "WRONG_SCHEMA_VERSION",
              ]), hostileCaseIDs.count == 18,
              let privacyCanaries = corpus["privacyCanaries"] as? [String],
              privacyCanaries == Self.c06PrivacyCanaries,
              privacyCanaries.count == 9 else {
            throw KernelConformanceFixtureFailureV1.invalidArtifact("c06-corpus")
        }
        let fixture = try Self.makeRendererFixture(snapshotRevision: 1)
        let releaseRegistry = ReportProjectionRegistryV2()
        try releaseRegistry.validate()
        let registry = releaseRegistry.baseRendererRegistry
        try registry.validate()
        guard case .complete(let firstBundle) = try registry.render(
            snapshot: fixture.snapshot,
            manifest: fixture.manifest,
            reportProfile: fixture.layout,
            exportProfile: fixture.export
        ), case .complete(let secondBundle) = try registry.render(
            snapshot: fixture.snapshot,
            manifest: fixture.manifest,
            reportProfile: fixture.layout,
            exportProfile: fixture.export
        ) else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("c06-render")
        }
        guard firstBundle == secondBundle,
              firstBundle.pdf.data == secondBundle.pdf.data,
              firstBundle.openJSON.data == secondBundle.openJSON.data,
              firstBundle.structuredText.data == secondBundle.structuredText.data else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("c06-repeat-bytes")
        }
        var zeroBoundaryCount = 0
        for boundary in ReportProjectionPublicationBoundaryV1.allCases {
            guard try registry.render(
                snapshot: fixture.snapshot,
                manifest: fixture.manifest,
                reportProfile: fixture.layout,
                exportProfile: fixture.export,
                recoveringFrom: boundary
            ) == .zero else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage(
                    "c06-publication-\(boundary.rawValue)"
                )
            }
            zeroBoundaryCount += 1
        }
        let retryFromZero = try registry.recover(
            snapshot: fixture.snapshot,
            manifest: fixture.manifest,
            reportProfile: fixture.layout,
            exportProfile: fixture.export,
            storedBundle: nil
        )
        let retryFromComplete = try registry.recover(
            snapshot: fixture.snapshot,
            manifest: fixture.manifest,
            reportProfile: fixture.layout,
            exportProfile: fixture.export,
            storedBundle: firstBundle
        )
        guard retryFromZero == firstBundle, retryFromComplete == firstBundle else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("c06-retry")
        }
        let bundle = firstBundle
        let pdfProjection = try DeterministicPDFRendererV1.reopen(bundle.pdf.data)
        let openProjection = try DeterministicOpenJSONRendererV1.reopen(bundle.openJSON.data)
        let textProjection = try DeterministicOpenJSONRendererV1.reopenStructuredText(
            bundle.structuredText.data
        )
        let decodedProjection = try JSONDecoder().decode(
            ReportSemanticProjectionV1.self, from: bundle.openJSON.data
        )
        guard pdfProjection == bundle.semanticProjection,
              openProjection == bundle.semanticProjection,
              textProjection == bundle.semanticProjection,
              decodedProjection == bundle.semanticProjection,
              bundle.pdf.semanticSHA256 == bundle.openJSON.semanticSHA256,
              bundle.openJSON.semanticSHA256 == bundle.structuredText.semanticSHA256,
              bundle.pdf.orderedSemanticIDs == bundle.openJSON.orderedSemanticIDs,
              bundle.openJSON.orderedSemanticIDs == bundle.structuredText.orderedSemanticIDs,
              bundle.openJSON.orderedSemanticIDs
                == bundle.semanticProjection.nodes.map(\.semanticID) else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("c06-reconcile")
        }

        let legacyURL = KernelConformanceFixtureHarnessV1.sourceRoot().appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/S3_3ReportSnapshotV1.json"
        )
        let legacySHAURL = legacyURL.deletingPathExtension().appendingPathExtension("sha256")
        let legacyBytes = try KernelConformanceFixtureHarnessV1.readRequiredData(legacyURL)
        let legacySHAText = try KernelConformanceFixtureHarnessV1.readRequiredData(legacySHAURL)
        guard let legacySHA = String(data: legacySHAText, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              KernelCanonicalHashV1.sha256(legacyBytes) == legacySHA else {
            throw KernelConformanceFixtureFailureV1.invalidArtifact("c06-legacy-sha")
        }
        let legacySnapshot = try ReportSnapshotEncoderV1().decode(legacyBytes)
        guard try ReportSnapshotEncoderV1().encode(legacySnapshot).data == legacyBytes else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("c06-legacy-round-trip")
        }

        let hostileValues = [
            ("hostile-control", "hidden\u{0000}value"),
            ("hostile-bidi", "hidden\u{202E}value"),
            ("hostile-noncharacter", "hidden\u{FFFE}value"),
            (
                "hostile-byte-bound",
                String(
                    repeating: "é",
                    count: (SnapshotProjectionLimitsV1.maximumTextBytes / 2) + 1
                )
            ),
        ]
        var hostileTextRejectionCount = 0
        var hostileTextRejections = Set<String>()
        for (fieldID, value) in hostileValues {
            do {
                _ = try EvidenceDetailFieldV1(
                    fieldID: fieldID,
                    label: "Hostile",
                    value: value,
                    sensitivity: .audienceSafe
                )
            } catch {
                hostileTextRejectionCount += 1
                hostileTextRejections.insert(fieldID)
            }
        }
        guard hostileTextRejectionCount == hostileValues.count else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("c06-hostile-text")
        }
        let unsupportedAccessibilityClaim = ReportProjectionOutputV1(
            format: .pdf,
            data: bundle.pdf.data,
            sha256: bundle.pdf.sha256,
            semanticSHA256: bundle.pdf.semanticSHA256,
            orderedSemanticIDs: bundle.pdf.orderedSemanticIDs,
            taggedPDFAccessibilityEvidence: true
        )
        let unsupportedAccessibilityClaimRejected: Bool
        do {
            _ = try ReportProjectionBundleV1(
                snapshot: fixture.snapshot,
                semanticProjection: bundle.semanticProjection,
                pdf: unsupportedAccessibilityClaim,
                openJSON: bundle.openJSON,
                structuredText: bundle.structuredText
            )
            unsupportedAccessibilityClaimRejected = false
        } catch {
            unsupportedAccessibilityClaimRejected = true
        }
        guard unsupportedAccessibilityClaimRejected,
              !bundle.taggedPDFAccessibilityClaimed,
              bundle.accessibleStructuredTextAlwaysPresent else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage(
                "c06-accessibility-claim"
            )
        }

        guard let safeCard = fixture.snapshot.payload.evidenceCards.first else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("c06-safe-card")
        }
        let cardEncoder = JSONEncoder()
        cardEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let safeCardJSON = String(
            data: try cardEncoder.encode(safeCard), encoding: .utf8
        ) else {
            throw KernelConformanceFixtureFailureV1.invalidArtifact("c06-safe-card-json")
        }
        func operationIsRejected(_ operation: () throws -> Void) -> Bool {
            do {
                try operation()
                return false
            } catch {
                return true
            }
        }
        var blockedPrivacyCanaries = Set<String>()
        for canary in privacyCanaries {
            let detection = try EvidenceDetailComposerV1.detectPostMarkupPrivacy(
                card: safeCard,
                policy: safeCard.audiencePrivacyPolicy,
                semanticText: "Reviewed customer-safe semantic output",
                composedOutput: Data(canary.utf8),
                detectorID: "audience-privacy-detector-v1",
                detectorVersion: 1
            )
            if detection.disposition == .blocked,
               detection.findingKinds.contains(.prohibitedSemanticText) {
                blockedPrivacyCanaries.insert(canary)
            }
        }
        let privacyCanaryRejected = blockedPrivacyCanaries == Set(privacyCanaries)
        let hostileCardJSON = safeCardJSON.replacingOccurrences(
            of: "Reviewed for customer-safe output",
            with: "PRIVATE-CANARY-NOTE"
        )
        let hostileCardRejected = operationIsRejected {
            _ = try JSONDecoder().decode(
                EvidenceDetailCardV1.self, from: Data(hostileCardJSON.utf8)
            )
        }
        guard privacyCanaryRejected, hostileCardRejected else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("c06-privacy-canary")
        }

        let canonicalSnapshot = try CompletedActivitySnapshotCanonicalCodecV1.encode(
            fixture.snapshot
        )
        func mutatedSnapshot(
            _ mutate: (inout [String: Any]) throws -> Void
        ) throws -> Data {
            guard var root = try JSONSerialization.jsonObject(
                with: canonicalSnapshot
            ) as? [String: Any] else {
                throw KernelConformanceFixtureFailureV1.invalidArtifact(
                    "c06-canonical-snapshot"
                )
            }
            try mutate(&root)
            return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        }
        let wrongSchemaVersionRejected = operationIsRejected {
            let data = try mutatedSnapshot { $0["schemaVersion"] = 999 }
            _ = try CompletedActivitySnapshotCanonicalCodecV1.decode(data)
        }
        let missingRequiredRejected = operationIsRejected {
            let data = try mutatedSnapshot { root in
                guard var payload = root["payload"] as? [String: Any] else {
                    throw KernelConformanceFixtureFailureV1.invalidArtifact("c06-payload")
                }
                payload.removeValue(forKey: "snapshotID")
                root["payload"] = payload
            }
            _ = try CompletedActivitySnapshotCanonicalCodecV1.decode(data)
        }
        let explicitNullRejected = operationIsRejected {
            let data = try mutatedSnapshot { root in
                guard var payload = root["payload"] as? [String: Any] else {
                    throw KernelConformanceFixtureFailureV1.invalidArtifact("c06-payload")
                }
                payload["snapshotID"] = NSNull()
                root["payload"] = payload
            }
            _ = try CompletedActivitySnapshotCanonicalCodecV1.decode(data)
        }
        let closedEnumRejected = operationIsRejected {
            let data = try mutatedSnapshot { root in
                guard var payload = root["payload"] as? [String: Any],
                      var binding = payload["profileBinding"] as? [String: Any] else {
                    throw KernelConformanceFixtureFailureV1.invalidArtifact("c06-binding")
                }
                binding["audience"] = "UNKNOWN_FUTURE_AUDIENCE"
                payload["profileBinding"] = binding
                root["payload"] = payload
            }
            _ = try CompletedActivitySnapshotCanonicalCodecV1.decode(data)
        }
        var duplicateIDs = bundle.pdf.orderedSemanticIDs
        guard duplicateIDs.count > 1 else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage(
                "c06-semantic-id-count"
            )
        }
        duplicateIDs[1] = duplicateIDs[0]
        let duplicateSemanticIDsRejected = operationIsRejected {
            let duplicatePDF = ReportProjectionOutputV1(
                format: .pdf,
                data: bundle.pdf.data,
                sha256: bundle.pdf.sha256,
                semanticSHA256: bundle.pdf.semanticSHA256,
                orderedSemanticIDs: duplicateIDs,
                taggedPDFAccessibilityEvidence: false
            )
            _ = try ReportProjectionBundleV1(
                snapshot: fixture.snapshot,
                semanticProjection: bundle.semanticProjection,
                pdf: duplicatePDF,
                openJSON: bundle.openJSON,
                structuredText: bundle.structuredText
            )
        }
        var corruptedPDFData = bundle.pdf.data
        corruptedPDFData.append(0x20)
        let projectionDigestMismatchRejected = operationIsRejected {
            let corruptedPDF = ReportProjectionOutputV1(
                format: .pdf,
                data: corruptedPDFData,
                sha256: bundle.pdf.sha256,
                semanticSHA256: bundle.pdf.semanticSHA256,
                orderedSemanticIDs: bundle.pdf.orderedSemanticIDs,
                taggedPDFAccessibilityEvidence: false
            )
            _ = try ReportProjectionBundleV1(
                snapshot: fixture.snapshot,
                semanticProjection: bundle.semanticProjection,
                pdf: corruptedPDF,
                openJSON: bundle.openJSON,
                structuredText: bundle.structuredText
            )
        }
        let staleProfileBindingRejected = operationIsRejected {
            let mismatchedLayout = try ReportLayoutProfileV1(
                profileID: fixture.layout.profileID,
                profileRelease: fixture.layout.profileRelease,
                audience: fixture.layout.audience,
                detail: fixture.layout.detail,
                sectionIDs: fixture.layout.sectionIDs,
                mediaLayout: fixture.layout.mediaLayout,
                orientation: .landscape,
                localeIdentifier: fixture.layout.localeIdentifier,
                unitsProfileID: fixture.layout.unitsProfileID,
                displayProfileID: fixture.layout.displayProfileID,
                registry: fixture.manifest.reportSectionRegistry
            )
            _ = try registry.render(
                snapshot: fixture.snapshot,
                manifest: fixture.manifest,
                reportProfile: mismatchedLayout,
                exportProfile: fixture.export
            )
        }
        let safeComposedOutput = Data("Final reviewed customer-safe bytes".utf8)
        let safeDetection = try EvidenceDetailComposerV1.detectPostMarkupPrivacy(
            card: safeCard,
            policy: safeCard.audiencePrivacyPolicy,
            semanticText: "Reviewed customer-safe semantic output",
            composedOutput: safeComposedOutput,
            detectorID: "audience-privacy-detector-v1",
            detectorVersion: 1
        )
        let forgedConfirmationRejected = operationIsRejected {
            _ = try FinalAudiencePrivacyConfirmationV1(
                confirmationID: "confirmation-forged",
                sourceSnapshotSHA256: fixture.snapshot.snapshotSHA256,
                semanticSHA256: String(repeating: "b", count: 64),
                composedOutputSHA256: String(repeating: "d", count: 64),
                card: safeCard,
                detection: safeDetection,
                userConfirmedExactComposedBytes: true
            )
        }
        let hostileCaseResults: [String: Bool] = [
            "ABSOLUTE_LOCAL_PATH": blockedPrivacyCanaries.contains("C:\\private\\canary.jpg"),
            "BIDI_OVERRIDE": hostileTextRejections.contains("hostile-bidi"),
            "CAPABILITY_SECRET": blockedPrivacyCanaries.contains("SECRET-CANARY"),
            "CLOSED_ENUM_UNKNOWN": closedEnumRejected,
            "CONTACT_DATA": blockedPrivacyCanaries.contains("CONTACT-CANARY"),
            "CONTROL_CHARACTER": hostileTextRejections.contains("hostile-control"),
            "DIAGNOSTIC_RAW_ERROR": blockedPrivacyCanaries.contains("DIAGNOSTIC-CANARY"),
            "DIRECT_COST": blockedPrivacyCanaries.contains("COST-CANARY"),
            "DUPLICATE_SEMANTIC_ID": duplicateSemanticIDsRejected,
            "EXPLICIT_NULL_FOR_REQUIRED": explicitNullRejected,
            "FORGED_CONFIRMATION": forgedConfirmationRejected,
            "LOCAL_IDENTIFIER": blockedPrivacyCanaries.contains("LOCAL-ID-CANARY"),
            "MISSING_REQUIRED": missingRequiredRejected,
            "ORIGINAL_MEDIA": blockedPrivacyCanaries.contains("ORIGINAL-CANARY-MEDIA"),
            "PRIVATE_NOTE": blockedPrivacyCanaries.contains("PRIVATE-CANARY-NOTE"),
            "PROJECTION_DIGEST_MISMATCH": projectionDigestMismatchRejected,
            "STALE_PROFILE_BINDING": staleProfileBindingRejected,
            "WRONG_SCHEMA_VERSION": wrongSchemaVersionRejected,
        ]
        guard Set(hostileCaseResults.keys) == Set(hostileCaseIDs),
              hostileCaseResults.values.allSatisfy({ $0 }) else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("c06-hostile-cases")
        }

        let originalBytes = try CompletedActivitySnapshotCanonicalCodecV1.encode(
            fixture.snapshot
        )
        let amendment = try Self.makeRendererFixture(
            snapshotRevision: 2,
            snapshotID: "snapshot-b",
            priorSnapshot: fixture.snapshot,
            serviceStatus: "Corrected"
        )
        try amendment.snapshot.validateSupersession(of: fixture.snapshot)
        try CompletedActivitySnapshotChainV1.validate([
            fixture.snapshot, amendment.snapshot,
        ])
        let originalAfterAmendment = try registry.recover(
            snapshot: fixture.snapshot,
            manifest: fixture.manifest,
            reportProfile: fixture.layout,
            exportProfile: fixture.export,
            storedBundle: bundle
        )
        let amendedBundle = try registry.recover(
            snapshot: amendment.snapshot,
            manifest: amendment.manifest,
            reportProfile: amendment.layout,
            exportProfile: amendment.export,
            storedBundle: nil
        )
        let amendedOpenProjection = try DeterministicOpenJSONRendererV1.reopen(
            amendedBundle.openJSON.data
        )
        let originalHistoricalBytesImmutable = try CompletedActivitySnapshotCanonicalCodecV1
            .encode(fixture.snapshot) == originalBytes
        let originalAmendedSupersededReconciled = originalAfterAmendment == bundle
            && amendedOpenProjection == amendedBundle.semanticProjection
            && amendedBundle.snapshotSHA256 != bundle.snapshotSHA256
            && bundle.semanticProjection.nodes.contains(where: {
                $0.sectionID == "supersession" && $0.label == "Supersession"
            })
            && amendedBundle.semanticProjection.nodes.contains(where: {
                $0.sectionID == "supersession" && $0.label == "Supersedes snapshot"
            })
        guard originalHistoricalBytesImmutable, originalAmendedSupersededReconciled else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("c06-supersession")
        }

        let legacyProfile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let oldFixture = try Self.makeRendererFixture(
            snapshotRevision: 1,
            snapshotID: "snapshot-old-profile",
            packageReleaseID: legacyProfile.release.packageID,
            reportProfileID: "customer-summary-v1",
            reportProfileRelease: 1,
            detail: .summary,
            sectionIDs: [
                "identity", "limitations", "provenance", "supersession", "manifest",
            ],
            includeEvidenceCard: false
        )
        guard case .complete(let oldBundle) = try registry.render(
            snapshot: oldFixture.snapshot,
            manifest: oldFixture.manifest,
            reportProfile: oldFixture.layout,
            exportProfile: oldFixture.export
        ) else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("c06-old-profile-render")
        }
        let oldProfileRendered = oldFixture.snapshot.payload.packageReleaseID
            == legacyProfile.release.packageID
            && oldFixture.snapshot.payload.profileBinding.reportProfileID
                == oldFixture.layout.profileID
            && oldFixture.snapshot.payload.profileBinding.reportProfileRelease
                == oldFixture.layout.profileRelease
            && (try DeterministicOpenJSONRendererV1.reopen(oldBundle.openJSON.data))
                == oldBundle.semanticProjection
        guard oldProfileRendered else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("c06-old-package-profile")
        }
        return .init(
            corpusSchema: corpusSchema,
            inheritedAcceptanceTests: inheritedAcceptanceTests,
            snapshotSHA256: fixture.snapshot.snapshotSHA256,
            pdfSHA256: bundle.pdf.sha256,
            openJSONSHA256: bundle.openJSON.sha256,
            structuredTextSHA256: bundle.structuredText.sha256,
            semanticSHA256: bundle.semanticProjection.semanticSHA256,
            orderedSemanticIDs: bundle.semanticProjection.nodes.map(\.semanticID),
            pdfReopened: pdfProjection == bundle.semanticProjection,
            openJSONReopened: openProjection == bundle.semanticProjection,
            structuredTextReopened: textProjection == bundle.semanticProjection,
            repeatRenderByteIdentical: firstBundle == secondBundle,
            zeroOrCompleteBoundaryCount: zeroBoundaryCount,
            retryByteIdentical: retryFromZero == bundle && retryFromComplete == bundle,
            legacySnapshotRoundTrip: try ReportSnapshotEncoderV1()
                .encode(legacySnapshot).data == legacyBytes,
            oldProfileRendered: oldProfileRendered,
            hostileTextRejectionCount: hostileTextRejectionCount,
            privacyCanaryRejected: privacyCanaryRejected,
            declaredHostileCaseRejectionCount: hostileCaseResults.count,
            privacyCanaryRejectionCount: blockedPrivacyCanaries.count,
            unsupportedAccessibilityClaimRejected: unsupportedAccessibilityClaimRejected,
            originalAmendedSupersededReconciled: originalAmendedSupersededReconciled,
            originalHistoricalBytesImmutable: originalHistoricalBytesImmutable
        )
    }

    func exerciseSearchFaultBoundary(
        _ boundary: String
    ) async throws -> KernelConformanceSearchFaultReceiptV1 {
        let allowed = Set([
            "SEARCH_CANCELLATION", "SEARCH_CHECKPOINT", "SEARCH_STALE",
            "SEARCH_AHEAD", "SEARCH_INCOMPATIBLE", "SEARCH_PUBLICATION_TOKEN",
        ])
        guard allowed.contains(boundary) else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
        }
        let searchRoot = root.appendingPathComponent(
            "search-fault-\(boundary.lowercased())", isDirectory: true
        )
        let store = try LocalSearchIndexStoreV1(applicationSupportURL: searchRoot)
        let revision = try SearchSourceRevisionV1(
            workspaceID: Self.fixedUUID(label: "W", slot: 301),
            generationID: Self.fixedUUID(label: "G", slot: 302),
            commitRevision: 42
        )
        let count = boundary == "SEARCH_CHECKPOINT" ? 251 : 2
        let records = try (0..<count).map { index in
            try SearchIndexProjectionRecordV1(
                workspaceID: revision.workspaceID,
                sourceKind: .asset,
                sourceStableID: String(format: "asset-%05d", index),
                sourceRevision: revision.commitRevision,
                fieldID: "asset_identifier",
                normalizedTokens: [String(format: "asset%05d", index)],
                displayIdentity: String(format: "Asset %05d", index),
                locationBreadcrumb: [],
                status: "Incomplete",
                permittedSnippet: String(format: "Asset %05d", index),
                sourceTimestamp: Date(timeIntervalSince1970: TimeInterval(index + 1))
            )
        }
        let registry = coordinator.searchServices.registry
        switch boundary {
        case "SEARCH_CANCELLATION":
            let source = KernelConformanceSearchSourceV1(revision: revision, records: records)
            let rebuild = try SearchIndexRebuildCoordinatorV1(
                store: store, source: source, registry: registry
            )
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await rebuild.rebuildIfNeeded()
            }
            var visible = ""
            do { _ = try await task.value }
            catch is CancellationError { visible = "CancellationError" }
            guard !visible.isEmpty, (try await store.revision()) == nil else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
            }
            let recovered = try await SearchIndexRebuildCoordinatorV1(
                store: store, source: source, registry: registry
            ).rebuildIfNeeded()
            return try await verifiedSearchFaultReceipt(
                boundary: boundary, visibleFailure: visible, recovered: recovered,
                searchRoot: searchRoot, revision: revision, records: records,
                registry: registry
            )
        case "SEARCH_CHECKPOINT":
            let source = KernelConformanceSearchSourceV1(
                revision: revision, records: records,
                failAtOffset: SearchIndexRebuildCoordinatorV1.pageSize
            )
            let rebuild = try SearchIndexRebuildCoordinatorV1(
                store: store, source: source, registry: registry
            )
            var visible = ""
            do { _ = try await rebuild.rebuildIfNeeded() }
            catch { visible = String(describing: error) }
            let staging = try await store.rebuildStaging()
            guard !visible.isEmpty,
                  staging?.checkpoint.nextCanonicalOffset
                    == SearchIndexRebuildCoordinatorV1.pageSize,
                  (try await store.revision()) == nil else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
            }
            let recovered = try await SearchIndexRebuildCoordinatorV1(
                store: store, source: source, registry: registry
            ).rebuildIfNeeded()
            return try await verifiedSearchFaultReceipt(
                boundary: boundary, visibleFailure: visible, recovered: recovered,
                searchRoot: searchRoot, revision: revision, records: records,
                registry: registry
            )
        case "SEARCH_STALE", "SEARCH_AHEAD":
            let storedRevision = try SearchSourceRevisionV1(
                workspaceID: revision.workspaceID,
                generationID: revision.generationID,
                commitRevision: boundary == "SEARCH_STALE" ? 41 : 43
            )
            let storedRecord = try Self.searchRecord(
                revision: storedRevision, stableID: "stored"
            )
            try await store.replaceProjection(
                source: storedRevision, records: [storedRecord], registry: registry
            )
            let source = KernelConformanceSearchSourceV1(revision: revision, records: records)
            let recovered = try await SearchIndexRebuildCoordinatorV1(
                store: store, source: source, registry: registry
            ).rebuildIfNeeded()
            let expected: SearchIndexReconciliationV1 = boundary == "SEARCH_STALE"
                ? .staleDropAndRebuild : .aheadDropAndRebuild
            guard recovered.disposition == expected else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
            }
            return try await verifiedSearchFaultReceipt(
                boundary: boundary, visibleFailure: expected.rawValue, recovered: recovered,
                searchRoot: searchRoot, revision: revision, records: records,
                registry: registry
            )
        case "SEARCH_INCOMPATIBLE":
            try await store.replaceProjection(
                source: revision, records: records, registry: registry
            )
            try Self.rewriteStoredProjectionFormat(in: searchRoot, as: 999)
            let reloaded = try LocalSearchIndexStoreV1(applicationSupportURL: searchRoot)
            let source = KernelConformanceSearchSourceV1(revision: revision, records: records)
            let recovered = try await SearchIndexRebuildCoordinatorV1(
                store: reloaded, source: source, registry: registry
            ).rebuildIfNeeded()
            guard recovered.disposition == .incompatibleFormatDropAndRebuild else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
            }
            return try await verifiedSearchFaultReceipt(
                boundary: boundary,
                visibleFailure: SearchIndexReconciliationV1.incompatibleFormatDropAndRebuild.rawValue,
                recovered: recovered, searchRoot: searchRoot, revision: revision,
                records: records, registry: registry
            )
        case "SEARCH_PUBLICATION_TOKEN":
            let token = await store.publicationToken()
            try await store.dropProjection()
            var visible = ""
            do {
                try await store.replaceProjection(
                    source: revision, records: records, registry: registry,
                    publicationToken: token
                )
            } catch let error as LocalSearchIndexStoreFailureV1 {
                guard error == .staleMutation else { throw error }
                visible = "staleMutation"
            }
            guard !visible.isEmpty, (try await store.revision()) == nil else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
            }
            let source = KernelConformanceSearchSourceV1(revision: revision, records: records)
            let recovered = try await SearchIndexRebuildCoordinatorV1(
                store: store, source: source, registry: registry
            ).rebuildIfNeeded()
            return try await verifiedSearchFaultReceipt(
                boundary: boundary, visibleFailure: visible, recovered: recovered,
                searchRoot: searchRoot, revision: revision, records: records,
                registry: registry
            )
        default:
            throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
        }
    }

    private func verifiedSearchFaultReceipt(
        boundary: String,
        visibleFailure: String,
        recovered: SearchIndexRebuildResultV1,
        searchRoot: URL,
        revision: SearchSourceRevisionV1,
        records: [SearchIndexProjectionRecordV1],
        registry: SearchableFieldRegistryV1
    ) async throws -> KernelConformanceSearchFaultReceiptV1 {
        let coldStore = try LocalSearchIndexStoreV1(applicationSupportURL: searchRoot)
        let published = try await coldStore.revision()
        let projection = try await coldStore.projection(for: revision, registry: registry)
        let staging = try await coldStore.rebuildStaging()
        let second = try await SearchIndexRebuildCoordinatorV1(
            store: coldStore,
            source: KernelConformanceSearchSourceV1(revision: revision, records: records),
            registry: registry
        ).rebuildIfNeeded()
        let exactRevision = published?.workspaceID == revision.workspaceID
            && published?.generationID == revision.generationID
            && published?.indexedCommitRevision == revision.commitRevision
        let exactRecords = projection.records.sorted() == records.sorted()
        let coldRecoverySucceeded = exactRevision
            && recovered.indexedRecordCount == records.count
            && projection.records.count == records.count
            && second.disposition == .current
            && second.indexedRecordCount == records.count
        let noPartialAuthority = exactRecords && staging == nil
            && !second.resumedFromCheckpoint
        guard coldRecoverySucceeded, noPartialAuthority else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage(
                "\(boundary)-cold-search-recovery"
            )
        }
        return KernelConformanceSearchFaultReceiptV1(
            boundary: boundary,
            visibleFailure: visibleFailure,
            coldRecoverySucceeded: coldRecoverySucceeded,
            noPartialAuthority: noPartialAuthority,
            disposition: recovered.disposition,
            resumedFromCheckpoint: recovered.resumedFromCheckpoint,
            canonicalRecordCount: projection.records.count,
            residualStagingCount: staging == nil ? 0 : 1
        )
    }

    func exerciseProductionFaultBoundary(
        _ boundary: String
    ) async throws -> KernelConformanceFaultBoundaryReceiptV1 {
        guard Self.productionExecutedFaultBoundaries.contains(boundary) else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
        }
        if boundary.hasPrefix("FINALIZATION_") {
            return try await exerciseFinalizationFaultBoundary(boundary)
        }
        if boundary.hasPrefix("WORK_") {
            return try await exerciseWorkFaultBoundary(boundary)
        }
        if boundary.hasPrefix("REPORT_") {
            return try await exerciseReportFaultBoundary(boundary)
        }
        if boundary.hasPrefix("JOURNAL_") {
            return try await exerciseJournalFaultBoundary(boundary)
        }
        if boundary.hasPrefix("RESTORE_") {
            return try await exerciseRestoreFaultBoundary(boundary)
        }
        if boundary.hasPrefix("DELETE_") {
            return try await exerciseDeleteFaultBoundary(boundary)
        }
        if boundary.hasPrefix("ERASE_") {
            return try await exerciseEraseFaultBoundary(boundary)
        }
        if boundary.hasPrefix("SEARCH_") {
            let receipt = try await exerciseSearchFaultBoundary(boundary)
            return .init(
                boundary: boundary, family: "SEARCH",
                visibleFailure: receipt.visibleFailure,
                operationAttempted: "SearchIndexRebuildCoordinatorV1.rebuildIfNeeded",
                recoveryOperation: "cold-LocalSearchIndexStoreV1+rebuildIfNeeded",
                coldRecoverySucceeded: receipt.coldRecoverySucceeded,
                noPartialAuthority: receipt.noPartialAuthority,
                canonicalRowCount: receipt.canonicalRecordCount,
                residualIntentCount: receipt.residualStagingCount,
                orphanPathCount: receipt.residualStagingCount
            )
        }
        throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
    }

    func exerciseProductionFaultBoundaries(
        _ boundaries: [String]
    ) async throws -> [KernelConformanceFaultBoundaryReceiptV1] {
        guard Set(boundaries).count == boundaries.count else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("duplicate-fault-boundary")
        }
        var receipts: [KernelConformanceFaultBoundaryReceiptV1] = []
        for boundary in boundaries.sorted() {
            receipts.append(try await exerciseProductionFaultBoundary(boundary))
        }
        return receipts
    }

    private struct ReadyCheckBoundaryFixture {
        let session: StoreGenerationSession
        let runner: CheckRunnerCoordinator
        let assetID: UUID
        let issueLabel: String
        let observedAt: Date
    }

    private func makeReadyCheckBoundaryFixture(
        at support: URL,
        finalizationStoreFailure: FinalizationIntentStoreFailureInjection? = nil,
        finalizationServiceFailure: FinalizationServiceFailureInjection? = nil
    ) async throws -> ReadyCheckBoundaryFixture {
        let installed = try StoreGenerationFactory(applicationSupportURL: support)
            .openOrBootstrapCurrent()
        let siteID = UUID(), assetID = UUID()
        installed.modelContext.insert(Site(
            id: siteID, label: "Boundary Site", address: nil,
            timeZoneID: "America/New_York", createdAt: Date(timeIntervalSince1970: 1_700_020_000)
        ))
        installed.modelContext.insert(Asset(
            id: assetID, siteID: siteID, packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
            packContentVersion: SignPack.illuminatedSignV1.contentVersion,
            label: "Boundary Asset", createdAt: Date(timeIntervalSince1970: 1_700_020_001)
        ))
        try installed.modelContext.save()
        let runner = CheckRunnerCoordinator(
            modelContext: installed.modelContext, signPack: .illuminatedSignV1,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max }),
            finalizationStoreFailureInjection: finalizationStoreFailure,
            finalizationServiceFailureInjection: finalizationServiceFailure
        )
        runner.configureCapture(generationRootURL: installed.generationRootURL)
        let observedAt = Date(timeIntervalSince1970: 1_700_020_100)
        _ = try runner.beginCheck(
            assetID: assetID, timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true, afterDarkAccepted: true,
            safePositionAccepted: true, observedAt: observedAt
        )
        for offset in [1, 2] {
            let candidate = try await runner.importCandidate(
                assetID: assetID, sourceData: try Self.makePNG(seed: UInt8(70 + offset)),
                createdAt: observedAt.addingTimeInterval(TimeInterval(offset))
            )
            _ = try await runner.accept(candidate: candidate, assetID: assetID)
        }
        return ReadyCheckBoundaryFixture(
            session: installed, runner: runner, assetID: assetID,
            issueLabel: SignPack.illuminatedSignV1.issueLabels[0].key,
            observedAt: observedAt
        )
    }

    private func exerciseFinalizationFaultBoundary(
        _ boundary: String
    ) async throws -> KernelConformanceFaultBoundaryReceiptV1 {
        let support = isolatedFaultRoot(boundary)
        defer { try? FileManager.default.removeItem(at: support) }
        let storeFailure: FinalizationIntentStoreFailureInjection?
        let serviceFailure: FinalizationServiceFailureInjection?
        switch boundary {
        case "FINALIZATION_SNAPSHOT_STAGING_WRITE":
            storeFailure = .init(failOnceAt: .snapshotStagingWrite); serviceFailure = nil
        case "FINALIZATION_SNAPSHOT_PROMOTION_MOVE":
            storeFailure = .init(failOnceAt: .snapshotPromotionMove); serviceFailure = nil
        case "FINALIZATION_INTENT_PHASE_WRITE":
            storeFailure = .init(failOnceAt: .intentPhaseWrite(.databaseCommitted)); serviceFailure = nil
        case "FINALIZATION_MODEL_SAVE":
            storeFailure = nil; serviceFailure = .init(failOnceAt: .modelSave)
        default:
            throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
        }
        let identifiers = FinalizationIdentifiers(
            mutationID: UUID(), packetID: UUID(), stableRootID: UUID(),
            reportID: UUID(), issueID: UUID()
        )
        let faultingRun: (
            assetID: UUID, issueLabel: String, observedAt: Date, visibleFailure: String
        ) = try await { () async throws -> (
            assetID: UUID, issueLabel: String, observedAt: Date, visibleFailure: String
        ) in
            let fixture = try await makeReadyCheckBoundaryFixture(
                at: support, finalizationStoreFailure: storeFailure,
                finalizationServiceFailure: serviceFailure
            )
            var visibleFailure = ""
            do {
                _ = try await fixture.runner.finalize(
                    assetID: fixture.assetID,
                    selection: .visibleIssue(labelKey: fixture.issueLabel),
                    completedAt: fixture.observedAt.addingTimeInterval(3),
                    snapshotCreatedAt: fixture.observedAt.addingTimeInterval(4),
                    sourceApp: .init(build: "920", version: "9.20"), identifiers: identifiers
                )
            } catch {
                visibleFailure = String(describing: error)
            }
            guard !visibleFailure.isEmpty else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
            }
            let beforePackets = try fixture.session.modelContext.fetchCount(FetchDescriptor<Packet>())
            let beforeReports = try fixture.session.modelContext.fetchCount(FetchDescriptor<Report>())
            guard beforePackets == beforeReports, beforePackets <= 1 else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage("\(boundary)-partial")
            }
            return (fixture.assetID, fixture.issueLabel, fixture.observedAt, visibleFailure)
        }()
        await Task.yield()
        let coldSession = try StoreGenerationFactory(applicationSupportURL: support)
            .openOrBootstrapCurrent()
        _ = try StoreSessionCoordinator(validatingSession: coldSession)
        _ = try await FinalizationRecoveryService(
            modelContext: coldSession.modelContext,
            generationRootURL: coldSession.generationRootURL
        ).reconcile()
        let replay = CheckRunnerCoordinator(
            modelContext: coldSession.modelContext, signPack: .illuminatedSignV1,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max })
        )
        replay.configureCapture(generationRootURL: coldSession.generationRootURL)
        _ = try await replay.finalize(
            assetID: faultingRun.assetID,
            selection: .visibleIssue(labelKey: faultingRun.issueLabel),
            completedAt: faultingRun.observedAt.addingTimeInterval(3),
            snapshotCreatedAt: faultingRun.observedAt.addingTimeInterval(4),
            sourceApp: .init(build: "920", version: "9.20"), identifiers: identifiers
        )
        let packets = try coldSession.modelContext.fetchCount(FetchDescriptor<Packet>())
        let reports = try coldSession.modelContext.fetchCount(FetchDescriptor<Report>())
        let residual = try await FinalizationIntentStore(
            generationRootURL: coldSession.generationRootURL
        ).discoverRecoverableFinalizations()
        let stagingSnapshot = coldSession.generationRootURL
            .appendingPathComponent(".staging/snapshots", isDirectory: true)
            .appendingPathComponent("\(identifiers.reportID.uuidString.lowercased()).json")
        let orphanCount = FileManager.default.fileExists(atPath: stagingSnapshot.path) ? 1 : 0
        guard packets == 1, reports == 1, residual.isEmpty, orphanCount == 0 else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("\(boundary)-recovery")
        }
        let coldRecovered = packets == 1 && reports == 1 && residual.isEmpty
        let noPartial = coldRecovered && orphanCount == 0
        return .init(
            boundary: boundary, family: "FINALIZATION", visibleFailure: faultingRun.visibleFailure,
            operationAttempted: "CheckRunnerCoordinator.finalize",
            recoveryOperation: "FinalizationRecoveryService.reconcile+idempotent-finalize",
            coldRecoverySucceeded: coldRecovered, noPartialAuthority: noPartial,
            canonicalRowCount: packets + reports, residualIntentCount: residual.count,
            orphanPathCount: orphanCount
        )
    }

    private func exerciseWorkFaultBoundary(
        _ boundary: String
    ) async throws -> KernelConformanceFaultBoundaryReceiptV1 {
        let support = isolatedFaultRoot(boundary)
        defer { try? FileManager.default.removeItem(at: support) }
        let point: WorkCoordinatorFailurePoint
        switch boundary {
        case "WORK_MODEL_SAVE": point = .modelSave
        case "WORK_AFTER_EVIDENCE_PROMOTION": point = .afterEvidencePromotion
        default: throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
        }
        let faultingRun: (
            draftID: UUID, submission: WorkSaveSubmission, identifiers: WorkIdentifiers,
            rowsBefore: Int, evidenceBefore: Int, visibleFailure: String
        ) = try await { () async throws -> (
            draftID: UUID, submission: WorkSaveSubmission, identifiers: WorkIdentifiers,
            rowsBefore: Int, evidenceBefore: Int, visibleFailure: String
        ) in
            let fixture = try await makeReadyCheckBoundaryFixture(at: support)
            let finalized = try await fixture.runner.finalize(
                assetID: fixture.assetID,
                selection: .visibleIssue(labelKey: fixture.issueLabel),
                completedAt: fixture.observedAt.addingTimeInterval(3),
                snapshotCreatedAt: fixture.observedAt.addingTimeInterval(4),
                sourceApp: .init(build: "920", version: "9.20")
            )
            let issueID = try requireValue(finalized.issueID, "\(boundary)-issue")
            let injection = WorkCoordinatorFailureInjection(failOnceAt: point)
            let faulted = try WorkCoordinator(
                modelContext: fixture.session.modelContext, signPack: .illuminatedSignV1,
                generationRootURL: fixture.session.generationRootURL,
                checkRunnerCoordinator: fixture.runner,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max }),
                failureInjection: injection
            )
            let draft = try faulted.beginWork(issueID: issueID)
            let identifiers = WorkIdentifiers(mutationID: UUID(), evidenceID: UUID())
            let submission = WorkSaveSubmission(
                performedLocalDate: "2026-08-27", description: "Boundary repair",
                note: "Injected production work boundary",
                photos: [.init(
                    purposeKey: "work_context", sourceData: try Self.makePNG(seed: 91),
                    createdAt: draft.startedAt.addingTimeInterval(1)
                )], completedAt: draft.startedAt.addingTimeInterval(2)
            )
            let rowsBefore = try fixture.session.modelContext.fetchCount(
                FetchDescriptor<WorkflowRecord>()
            )
            let evidenceBefore = try fixture.session.modelContext.fetchCount(
                FetchDescriptor<EvidenceFile>()
            )
            var visibleFailure = ""
            do {
                _ = try await faulted.saveWork(
                    draftID: draft.recordID, submission: submission, identifiers: identifiers
                )
            } catch { visibleFailure = String(describing: error) }
            guard !visibleFailure.isEmpty else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
            }
            return (
                draft.recordID, submission, identifiers, rowsBefore, evidenceBefore, visibleFailure
            )
        }()
        await Task.yield()
        let coldSession = try StoreGenerationFactory(applicationSupportURL: support)
            .openOrBootstrapCurrent()
        _ = try StoreSessionCoordinator(validatingSession: coldSession)
        let coldRunner = CheckRunnerCoordinator(
            modelContext: coldSession.modelContext, signPack: .illuminatedSignV1,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max })
        )
        coldRunner.configureCapture(generationRootURL: coldSession.generationRootURL)
        let resumed = try WorkCoordinator(
            modelContext: coldSession.modelContext, signPack: .illuminatedSignV1,
            generationRootURL: coldSession.generationRootURL,
            checkRunnerCoordinator: coldRunner,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max })
        )
        let saved = try await resumed.saveWork(
            draftID: faultingRun.draftID, submission: faultingRun.submission,
            identifiers: faultingRun.identifiers
        )
        let rowsAfter = try coldSession.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>())
        let evidenceAfter = try coldSession.modelContext.fetchCount(FetchDescriptor<EvidenceFile>())
        let staging = coldSession.generationRootURL
            .appendingPathComponent(".staging/evidence", isDirectory: true)
        let orphanCount = (try? FileManager.default.contentsOfDirectory(atPath: staging.path).count) ?? 0
        guard saved.status == .recheckDue, rowsAfter == faultingRun.rowsBefore,
              evidenceAfter == faultingRun.evidenceBefore + 1, orphanCount == 0 else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("\(boundary)-recovery")
        }
        let coldRecovered = saved.status == .recheckDue && rowsAfter == faultingRun.rowsBefore
            && evidenceAfter == faultingRun.evidenceBefore + 1
        let noPartial = coldRecovered && orphanCount == 0
        return .init(
            boundary: boundary, family: "WORK", visibleFailure: faultingRun.visibleFailure,
            operationAttempted: "WorkCoordinator.saveWork",
            recoveryOperation: "cold-WorkCoordinator.saveWork-same-identifiers",
            coldRecoverySucceeded: coldRecovered, noPartialAuthority: noPartial,
            canonicalRowCount: rowsAfter + evidenceAfter, residualIntentCount: 0,
            orphanPathCount: orphanCount
        )
    }

    private func exerciseReportFaultBoundary(
        _ boundary: String
    ) async throws -> KernelConformanceFaultBoundaryReceiptV1 {
        let support = isolatedFaultRoot(boundary)
        defer { try? FileManager.default.removeItem(at: support) }
        let faultingRun: (reportID: UUID, visibleFailure: String) = try await {
            () async throws -> (reportID: UUID, visibleFailure: String) in
            let fixture = try await makeReadyCheckBoundaryFixture(at: support)
            let finalized = try await fixture.runner.finalize(
                assetID: fixture.assetID, selection: .noVisibleIssue,
                completedAt: fixture.observedAt.addingTimeInterval(3),
                snapshotCreatedAt: fixture.observedAt.addingTimeInterval(4),
                sourceApp: .init(build: "920", version: "9.20")
            )
            let reportID = finalized.reportID
            var visibleFailure = ""
            if boundary == "REPORT_RETRY_TRANSITION_SAVE" {
                let initial = try ReportRenderService(
                    modelContext: fixture.session.modelContext,
                    generationRootURL: fixture.session.generationRootURL,
                    failureInjection: .init(failOnceAt: .render)
                )
                _ = try initial.attemptPendingReport(id: reportID)
                let faulted = try ReportRecoveryService(
                    modelContext: fixture.session.modelContext,
                    generationRootURL: fixture.session.generationRootURL,
                    recoveryFailureInjection: .init(failOnceAt: .retryTransitionSave)
                )
                try faulted.reconcileAtStartup()
                do { _ = try await faulted.retryFailedReport(id: reportID) }
                catch { visibleFailure = String(describing: error) }
            } else if boundary == "REPORT_FAILED_STATE_SAVE" {
                let faulted = try ReportRenderService(
                    modelContext: fixture.session.modelContext,
                    generationRootURL: fixture.session.generationRootURL,
                    storagePreflight: StoragePreflightService(capacityProvider: { _ in 0 }),
                    failureInjection: .init(failOnceAt: .failedStateSave)
                )
                do { _ = try faulted.attemptPendingReport(id: reportID) }
                catch { visibleFailure = String(describing: error) }
            } else {
                let point: ReportRenderFailurePoint
                switch boundary {
                case "REPORT_RENDER": point = .render
                case "REPORT_STAGE_WRITE": point = .stageWrite
                case "REPORT_PROMOTION": point = .promotion
                case "REPORT_REREAD": point = .reread
                case "REPORT_READY_SAVE": point = .readySave
                default: throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
                }
                let faulted = try ReportRecoveryService(
                    modelContext: fixture.session.modelContext,
                    generationRootURL: fixture.session.generationRootURL,
                    failureInjection: .init(failOnceAt: point)
                )
                try faulted.reconcileAtStartup()
                let state = try requireValue(
                    fixture.session.modelContext.fetch(FetchDescriptor<Report>())
                        .first(where: { $0.id == reportID })?.pdfState,
                    "\(boundary)-report"
                )
                if state == ReportPDFState.failed.rawValue { visibleFailure = "report-failed" }
            }
            guard !visibleFailure.isEmpty else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
            }
            return (reportID, visibleFailure)
        }()
        await Task.yield()
        let coldSession = try StoreGenerationFactory(applicationSupportURL: support)
            .openOrBootstrapCurrent()
        _ = try StoreSessionCoordinator(validatingSession: coldSession)
        let recovery = try ReportRecoveryService(
            modelContext: coldSession.modelContext,
            generationRootURL: coldSession.generationRootURL
        )
        try recovery.reconcileAtStartup()
        if let failed = try coldSession.modelContext.fetch(FetchDescriptor<Report>())
            .first(where: {
                $0.id == faultingRun.reportID && $0.pdfState == ReportPDFState.failed.rawValue
            }) {
            _ = try await recovery.retryFailedReport(id: failed.id)
        }
        let reports = try coldSession.modelContext.fetch(FetchDescriptor<Report>())
        let report = try requireValue(
            reports.first(where: { $0.id == faultingRun.reportID }), "\(boundary)-ready"
        )
        guard reports.count == 1, report.pdfState == ReportPDFState.ready.rawValue,
              let relative = report.pdfRelativePath,
              FileManager.default.fileExists(
                atPath: coldSession.generationRootURL.appendingPathComponent(relative).path
              ) else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("\(boundary)-recovery")
        }
        let staging = coldSession.generationRootURL.appendingPathComponent(
            ".staging/reports", isDirectory: true
        )
        let orphanCount = (try? FileManager.default.contentsOfDirectory(atPath: staging.path).count) ?? 0
        guard orphanCount == 0 else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("\(boundary)-orphan")
        }
        let coldRecovered = reports.count == 1
            && report.pdfState == ReportPDFState.ready.rawValue
        let noPartial = coldRecovered && orphanCount == 0
        return .init(
            boundary: boundary, family: "REPORT", visibleFailure: faultingRun.visibleFailure,
            operationAttempted: boundary == "REPORT_RETRY_TRANSITION_SAVE"
                ? "ReportRecoveryService.retryFailedReport"
                : "ReportRenderService.attemptPendingReport",
            recoveryOperation: "cold-ReportRecoveryService.reconcileAtStartup+retry",
            coldRecoverySucceeded: coldRecovered, noPartialAuthority: noPartial,
            canonicalRowCount: reports.count, residualIntentCount: 0,
            orphanPathCount: orphanCount
        )
    }

    private func exerciseRestoreFaultBoundary(
        _ boundary: String
    ) async throws -> KernelConformanceFaultBoundaryReceiptV1 {
        let support = isolatedFaultRoot(boundary)
        defer { try? FileManager.default.removeItem(at: support) }
        let point: BackupRestoreFailurePoint
        switch boundary {
        case "RESTORE_BEFORE_PREPARED_WRITE": point = .beforePreparedWrite
        case "RESTORE_AFTER_PREPARED_WRITE": point = .afterPreparedWrite
        case "RESTORE_BEFORE_GENERATION_INSTALL": point = .beforeGenerationInstall
        case "RESTORE_AFTER_GENERATION_INSTALL": point = .afterGenerationInstall
        case "RESTORE_BEFORE_POINTER_SWITCH": point = .beforePointerSwitch
        case "RESTORE_AFTER_POINTER_SWITCH": point = .afterPointerSwitch
        case "RESTORE_BEFORE_NEW_GENERATION_VALIDATION": point = .beforeNewGenerationValidation
        case "RESTORE_AFTER_NEW_GENERATION_VALIDATION": point = .afterNewGenerationValidation
        case "RESTORE_BEFORE_CLEANUP": point = .beforeCleanup
        default: throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
        }

        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let registry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        let sourceSupport = support.appendingPathComponent("source", isDirectory: true)
        let sourceSession = try StoreGenerationFactory(applicationSupportURL: sourceSupport)
            .openOrBootstrapCurrent()
        let sourceCoordinator = try StoreSessionCoordinator(validatingSession: sourceSession)
        _ = try await createBoundaryAsset(
            coordinator: sourceCoordinator, profile: profile, label: "Restore Boundary Asset"
        )
        let sourceSiteCount = try sourceSession.modelContext.fetchCount(FetchDescriptor<Site>())
        let sourceAssetCount = try sourceSession.modelContext.fetchCount(FetchDescriptor<Asset>())
        let sourceLocationCount = try sourceSession.modelContext.fetchCount(
            FetchDescriptor<LocationNode>()
        )
        let sourceDependencies = try sourceCoordinator.packageLifecycleDependencies(
            profileRegistry: registry
        )
        let exporter = BackupExportService(
            modelContext: sourceSession.modelContext,
            generationRootURL: sourceSession.generationRootURL,
            lifecycleDependencies: sourceDependencies,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max })
        )
        let preview = try exporter.prepareStreaming()
        let exportRoot = support.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let archive = try exporter.exportStreaming(previewID: preview.id, to: exportRoot)

        let targetSupport = support.appendingPathComponent("target", isDirectory: true)
        let targetFactory = StoreGenerationFactory(applicationSupportURL: targetSupport)
        var targetSession: StoreGenerationSession? = try targetFactory.openOrBootstrapCurrent()
        var targetCoordinator: StoreSessionCoordinator? = try StoreSessionCoordinator(
            validatingSession: requireValue(targetSession, "\(boundary)-target")
        )
        let oldID = try requireValue(targetSession, "\(boundary)-old-session").generationID
        let newID = UUID()
        let restoreID = UUID()
        let validated = try BackupImportService(
            generationRootURL: try requireValue(targetSession, "\(boundary)-import-session")
                .generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max }),
            scopedAccess: .alreadyAuthorized
        ).stageAndValidate(selectedPackageURL: archive)
        var visibleFailure = ""
        do {
            let activeSession = try requireValue(targetSession, "\(boundary)-active-session")
            let activeCoordinator = try requireValue(targetCoordinator, "\(boundary)-active-coordinator")
            let dependencies = try activeCoordinator.packageLifecycleDependencies(
                profileRegistry: registry
            )
            let service = try BackupRestoreService(
                applicationSupportURL: targetSupport,
                lifecycleDependencies: dependencies,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max }),
                makeUUID: uuidSequence([newID, restoreID]),
                failureInjection: BackupRestoreFailureInjection(failOnceAt: point)
            )
            do {
                _ = try await service.restore(
                    validatedPackage: validated,
                    currentModelContext: activeSession.modelContext,
                    currentGenerationID: oldID,
                    currentGenerationRootURL: activeSession.generationRootURL,
                    mode: .emptyInstall
                )
            } catch {
                guard error as? BackupRestoreServiceError == .injectedFailure else { throw error }
                visibleFailure = String(describing: error)
            }
        }
        guard !visibleFailure.isEmpty else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
        }
        targetCoordinator = nil
        targetSession = nil
        await Task.yield()

        let startupDependencies: WorkspacePackageLifecycleDependenciesV1
        do {
            let startupSession = try targetFactory.openOrBootstrapCurrent()
            let startupCoordinator = try StoreSessionCoordinator(validatingSession: startupSession)
            startupDependencies = try startupCoordinator.packageLifecycleDependencies(
                profileRegistry: registry
            )
        }
        await Task.yield()
        let recovery = try BackupRestoreService(
            applicationSupportURL: targetSupport,
            lifecycleDependencies: startupDependencies,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max })
        )
        let recovered = try recovery.reconcileAtStartup()
        let canonical = try recovered ?? targetFactory.openOrBootstrapCurrent()
        let expectedOld = [
            .beforePreparedWrite, .afterPreparedWrite, .beforeGenerationInstall,
        ].contains(point)
        let expectedID = expectedOld ? oldID : newID
        let siteCount = try canonical.modelContext.fetchCount(FetchDescriptor<Site>())
        let assetCount = try canonical.modelContext.fetchCount(FetchDescriptor<Asset>())
        let locationCount = try canonical.modelContext.fetchCount(FetchDescriptor<LocationNode>())
        let canonicalRows = try canonicalDomainRowCount(canonical.modelContext)
        let second = try recovery.reconcileAtStartup()
        let residualIntent = fileExists(
            targetSupport.appendingPathComponent("FieldEvidenceRestore/restore.json")
        ) ? 1 : 0
        let orphanCount = temporaryFileCount(under: targetSupport)
            + directoryEntryCount(
                targetSupport.appendingPathComponent("FieldEvidenceRestore/generations", isDirectory: true)
            )
            + (fileExists(validated.stagedPackageURL) ? 1 : 0)
        let coldRecovered = try targetFactory.currentGenerationID() == expectedID
            && siteCount == (expectedOld ? 0 : sourceSiteCount)
            && assetCount == (expectedOld ? 0 : sourceAssetCount)
            && locationCount == (expectedOld ? 0 : sourceLocationCount)
        let noPartial = coldRecovered && second == nil
            && residualIntent == 0 && orphanCount == 0
        guard coldRecovered, noPartial else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("\(boundary)-recovery")
        }
        return .init(
            boundary: boundary, family: "RESTORE", visibleFailure: visibleFailure,
            operationAttempted: "BackupRestoreService.restore",
            recoveryOperation: "cold-BackupRestoreService.reconcileAtStartup-twice",
            coldRecoverySucceeded: coldRecovered, noPartialAuthority: noPartial,
            canonicalRowCount: canonicalRows,
            residualIntentCount: residualIntent, orphanPathCount: orphanCount
        )
    }

    private func exerciseDeleteFaultBoundary(
        _ boundary: String
    ) async throws -> KernelConformanceFaultBoundaryReceiptV1 {
        let support = isolatedFaultRoot(boundary)
        defer { try? FileManager.default.removeItem(at: support) }
        let point: WholeSignDeletionFailurePoint
        switch boundary {
        case "DELETE_PREPARED_JOURNAL": point = .preparedJournal
        case "DELETE_DATABASE_SAVE": point = .databaseSave
        case "DELETE_COMMITTED_PHASE": point = .committedPhase
        case "DELETE_FILE_CLEANUP": point = .fileCleanup
        case "DELETE_JOURNAL_REMOVAL": point = .journalRemoval
        default: throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
        }
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let registry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        var activeSession: StoreGenerationSession? = try StoreGenerationFactory(
            applicationSupportURL: support
        ).openOrBootstrapCurrent()
        var activeCoordinator: StoreSessionCoordinator? = try StoreSessionCoordinator(
            validatingSession: requireValue(activeSession, "\(boundary)-session")
        )
        let assetID = try await createBoundaryAsset(
            coordinator: requireValue(activeCoordinator, "\(boundary)-coordinator"),
            profile: profile, label: "Deletion Boundary Asset"
        )
        var visibleFailure = ""
        var ownedRelativePaths: [String] = []
        do {
            let session = try requireValue(activeSession, "\(boundary)-active-session")
            let coordinator = try requireValue(activeCoordinator, "\(boundary)-active-coordinator")
            let dependencies = try coordinator.packageLifecycleDependencies(profileRegistry: registry)
            let runner = try CheckRunnerCoordinator(
                modelContext: session.modelContext,
                packageLifecycleDependencies: dependencies,
                packageLifecycleProfile: profile
            )
            runner.configureCapture(generationRootURL: session.generationRootURL)
            let observedAt = Date(timeIntervalSince1970: 1_700_041_000)
            _ = try runner.beginCheck(
                assetID: assetID, timeZoneID: "America/New_York",
                isTimeZoneConfirmed: true, afterDarkAccepted: true,
                safePositionAccepted: true, observedAt: observedAt
            )
            let candidate = try await runner.importCandidate(
                assetID: assetID, sourceData: try Self.makePNG(seed: 113),
                createdAt: observedAt.addingTimeInterval(1)
            )
            _ = try await runner.accept(candidate: candidate, assetID: assetID)
            ownedRelativePaths = try session.modelContext.fetch(FetchDescriptor<EvidenceFile>())
                .flatMap { [$0.relativePath, $0.thumbnailRelativePath] }
            guard ownedRelativePaths.count == 2,
                  ownedRelativePaths.allSatisfy({ relative in
                      fileExists(session.generationRootURL.appendingPathComponent(relative))
                  }) else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage(
                    "\(boundary)-owned-files"
                )
            }
            let service = WholeSignDeletionService(
                modelContext: session.modelContext,
                lifecycleDependencies: dependencies,
                failureInjection: WholeSignDeletionFailureInjection(failOnceAt: point)
            )
            do { _ = try await service.delete(assetID: assetID) }
            catch {
                guard error as? WholeSignDeletionServiceError == .injectedFailure else { throw error }
                visibleFailure = String(describing: error)
            }
        }
        guard !visibleFailure.isEmpty else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
        }
        activeCoordinator = nil
        activeSession = nil
        await Task.yield()

        let coldSession = try StoreGenerationFactory(applicationSupportURL: support)
            .openOrBootstrapCurrent()
        let coldCoordinator = try StoreSessionCoordinator(validatingSession: coldSession)
        let coldDependencies = try coldCoordinator.packageLifecycleDependencies(profileRegistry: registry)
        let recovery = WholeSignDeletionService(
            modelContext: coldSession.modelContext,
            lifecycleDependencies: coldDependencies
        )
        let first = try await recovery.reconcile()
        let second = try await recovery.reconcile()
        let assets = try coldSession.modelContext.fetch(FetchDescriptor<Asset>())
        let ledger = try DeletionLedgerStore(context: coldSession.modelContext).snapshot()
        let residualIntent = directoryEntryCount(
            support.appendingPathComponent("FieldEvidenceOperations/deletion", isDirectory: true)
        )
        let canonicalRows = try canonicalDomainRowCount(coldSession.modelContext)
        let expectedOld = point == .databaseSave
        let survivingOwnedPathCount = ownedRelativePaths.filter {
            fileExists(coldSession.generationRootURL.appendingPathComponent($0))
        }.count
        let cleanupViolationCount = expectedOld
            ? ownedRelativePaths.count - survivingOwnedPathCount
            : survivingOwnedPathCount
        let orphanCount = temporaryFileCount(under: coldSession.generationRootURL)
            + cleanupViolationCount
        let deletionComplete = assets.allSatisfy { $0.id != assetID }
            && ledger.entries.contains { $0.identity.kind == .asset && $0.identity.id == assetID }
        let oldPreserved = assets.contains { $0.id == assetID }
            && !ledger.entries.contains { $0.identity.kind == .asset && $0.identity.id == assetID }
        let firstRecoveryCount = first.completedCommittedCount + first.cancelledPreparedCount
        let coldRecovered = (expectedOld ? oldPreserved : deletionComplete)
            && firstRecoveryCount == (expectedOld ? 0 : 1)
        let noPartial = coldRecovered
            && second.cancelledPreparedCount == 0
            && second.completedCommittedCount == 0
            && residualIntent == 0 && orphanCount == 0
        guard coldRecovered, noPartial else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("\(boundary)-recovery")
        }
        return .init(
            boundary: boundary, family: "DELETE", visibleFailure: visibleFailure,
            operationAttempted: "WholeSignDeletionService.delete",
            recoveryOperation: "cold-WholeSignDeletionService.reconcile-twice",
            coldRecoverySucceeded: coldRecovered, noPartialAuthority: noPartial,
            canonicalRowCount: canonicalRows, residualIntentCount: residualIntent,
            orphanPathCount: orphanCount
        )
    }

    private func exerciseEraseFaultBoundary(
        _ boundary: String
    ) async throws -> KernelConformanceFaultBoundaryReceiptV1 {
        let base = isolatedFaultRoot(boundary)
        defer { try? FileManager.default.removeItem(at: base) }
        let support = base.appendingPathComponent("ApplicationSupport", isDirectory: true)
        let caches = base.appendingPathComponent("Caches", isDirectory: true)
        let temporary = base.appendingPathComponent("Temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let point: EraseAllFailurePoint
        switch boundary {
        case "ERASE_AFTER_EMPTY_GENERATION_DIRECTORY_CREATE": point = .afterEmptyGenerationDirectoryCreate
        case "ERASE_BEFORE_PREPARED_WRITE": point = .beforePreparedWrite
        case "ERASE_AFTER_PREPARED_WRITE": point = .afterPreparedWrite
        case "ERASE_BEFORE_POINTER_SWITCH": point = .beforePointerSwitch
        case "ERASE_AFTER_POINTER_SWITCH": point = .afterPointerSwitch
        case "ERASE_BEFORE_POINTER_PHASE_WRITE": point = .beforePointerPhaseWrite
        case "ERASE_AFTER_POINTER_PHASE_WRITE": point = .afterPointerPhaseWrite
        case "ERASE_BEFORE_SESSION_ACTIVATION": point = .beforeSessionActivation
        case "ERASE_AFTER_SESSION_ACTIVATION": point = .afterSessionActivation
        case "ERASE_BEFORE_SESSION_PHASE_WRITE": point = .beforeSessionPhaseWrite
        case "ERASE_AFTER_SESSION_PHASE_WRITE": point = .afterSessionPhaseWrite
        case "ERASE_BEFORE_CLEANUP": point = .beforeCleanup
        case "ERASE_AFTER_CLEANUP": point = .afterCleanup
        case "ERASE_BEFORE_CLEANUP_PHASE_WRITE": point = .beforeCleanupPhaseWrite
        case "ERASE_AFTER_CLEANUP_PHASE_WRITE": point = .afterCleanupPhaseWrite
        case "ERASE_BEFORE_JOURNAL_REMOVAL": point = .beforeJournalRemoval
        default: throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
        }
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let registry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        let factory = StoreGenerationFactory(applicationSupportURL: support)
        var activeSession: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        var activeCoordinator: StoreSessionCoordinator? = try StoreSessionCoordinator(
            validatingSession: requireValue(activeSession, "\(boundary)-session")
        )
        _ = try await createBoundaryAsset(
            coordinator: requireValue(activeCoordinator, "\(boundary)-coordinator"),
            profile: profile, label: "Erase Boundary Asset"
        )
        let oldID = try requireValue(activeSession, "\(boundary)-old-session").generationID
        let newID = UUID(), eraseID = UUID()
        let erasedWorkspaceID = UUID(), erasedReplicaID = UUID()
        let diagnostics = DiagnosticsStore(applicationSupportURL: support)
        await diagnostics.prepare()
        let defaultsName = "V9_20-A01-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: defaultsName) else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("\(boundary)-defaults")
        }
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        var visibleFailure = ""
        do {
            let coordinator = try requireValue(activeCoordinator, "\(boundary)-active-coordinator")
            let dependencies = try coordinator.packageLifecycleDependencies(profileRegistry: registry)
            let service = EraseAllService(
                applicationSupportURL: support,
                cachesDirectoryURL: caches,
                temporaryDirectoryURL: temporary,
                userDefaults: defaults,
                makeUUID: uuidSequence([
                    newID, eraseID, erasedWorkspaceID, erasedReplicaID,
                ]),
                failureInjection: EraseAllFailureInjection(failOnceAt: point)
            )
            do {
                _ = try await service.erase(
                    confirmation: EraseAllService.requiredConfirmation,
                    coordinator: coordinator,
                    diagnosticsStore: diagnostics,
                    activate: { replacement in coordinator.activate(session: replacement) },
                    lifecycleDependencies: dependencies
                )
            } catch {
                guard error as? EraseAllServiceError == .injectedFailure else { throw error }
                visibleFailure = String(describing: error)
            }
        }
        guard !visibleFailure.isEmpty else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
        }
        activeCoordinator = nil
        activeSession = nil
        await Task.yield()

        let recovery = EraseAllService(
            applicationSupportURL: support,
            cachesDirectoryURL: caches,
            temporaryDirectoryURL: temporary,
            userDefaults: defaults
        )
        let recovered = try await recovery.reconcileAtStartup(diagnosticsStore: diagnostics)
        let second = try await recovery.reconcileAtStartup(diagnosticsStore: diagnostics)
        let canonical = try recovered ?? factory.openOrBootstrapCurrent()
        let expectedOld = point == .afterEmptyGenerationDirectoryCreate || point == .beforePreparedWrite
        let expectedID = expectedOld ? oldID : newID
        let assetCount = try canonical.modelContext.fetchCount(FetchDescriptor<Asset>())
        let canonicalRows = try canonicalDomainRowCount(canonical.modelContext)
        let residualIntent = fileExists(
            support.appendingPathComponent("FieldEvidenceErase/erase.json")
        ) ? 1 : 0
        let orphanCount = temporaryFileCount(under: base)
            + directoryEntryCount(support.appendingPathComponent("FieldEvidenceErase", isDirectory: true))
        let coldRecovered = try factory.currentGenerationID() == expectedID
            && assetCount == (expectedOld ? 1 : 0)
            && (!expectedOld ? canonicalRows == 0 : canonicalRows > 0)
        let noPartial = coldRecovered && second == nil
            && residualIntent == 0 && orphanCount == 0
        guard coldRecovered, noPartial else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("\(boundary)-recovery")
        }
        return .init(
            boundary: boundary, family: "ERASE", visibleFailure: visibleFailure,
            operationAttempted: "EraseAllService.erase",
            recoveryOperation: "cold-EraseAllService.reconcileAtStartup-twice",
            coldRecoverySucceeded: coldRecovered, noPartialAuthority: noPartial,
            canonicalRowCount: canonicalRows, residualIntentCount: residualIntent,
            orphanPathCount: orphanCount
        )
    }

    private func exerciseJournalFaultBoundary(
        _ boundary: String
    ) async throws -> KernelConformanceFaultBoundaryReceiptV1 {
        if boundary == "JOURNAL_AFTER_REPLAY_MUTATION" {
            return try await exerciseJournalReplayFaultBoundary(boundary)
        }
        let support = isolatedFaultRoot(boundary)
        defer { try? FileManager.default.removeItem(at: support) }
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: Self.fixedUUID(label: "J", slot: 400)),
            replicaID: ReplicaID(rawValue: Self.fixedUUID(label: "J", slot: 401))
        )
        let limits = try ChangeJournalLimitsV1(
            maximumChangesPerBatch: 1, maximumBatchBytes: 4_194_304,
            maximumEntitiesPerCheckpoint: 10_000,
            maximumContentEntriesPerCheckpoint: 10_000,
            maximumReplicaFrontiers: 4, maximumConflicts: 64
        )
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let registry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        let box = KernelConformanceJournalInterruptionBoxV1()
        var visibleFailure = ""
        var operation = ""
        var beforeCanonical = "", beforeTombstones = "", beforeMutations = ""
        do {
            let installed = try StoreGenerationFactory(
                applicationSupportURL: support, pointerEnrichmentIdentity: identity
            ).openOrBootstrapCurrent()
            let active = try StoreSessionCoordinator(validatingSession: installed)
            let dependencies = try active.packageLifecycleDependencies(profileRegistry: registry)
            let backup = BackupExportService(
                modelContext: installed.modelContext,
                generationRootURL: installed.generationRootURL,
                lifecycleDependencies: dependencies,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max })
            )
            let siteID = Self.fixedUUID(label: "J", slot: 410)
            _ = try active.workspaceWriter.execute(
                .createFirstSign(.init(
                    siteID: siteID,
                    newSite: .init(id: siteID, label: "Journal Site", address: nil, timeZoneID: "UTC"),
                    assetID: Self.fixedUUID(label: "J", slot: 411), assetLabel: "Journal Asset",
                    packID: profile.package.packID,
                    packSchemaVersion: profile.package.schemaVersion,
                    packContentVersion: profile.package.contentVersion,
                    createdAt: Date(timeIntervalSince1970: 1_700_030_000),
                    initialPlacementMutationID: try MutationIDV1(
                        rawValue: Self.fixedUUID(label: "J", slot: 412)
                    ),
                    initialPlacementEventID: Self.fixedUUID(label: "J", slot: 413),
                    initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(
                        rawValue: Self.fixedUUID(label: "J", slot: 414)
                    )
                )),
                mutationID: try MutationIDV1(rawValue: Self.fixedUUID(label: "J", slot: 415))
            )
            let journal = try active.localChangeJournal(
                backupExport: backup, limits: limits,
                policyResolver: { _, _ in
                    try ConflictPolicyV1(policyID: "v9_20_a01_append_union", rule: .stableIDAppendUnion)
                },
                contentReferenceResolver: { _ in throw ContentContractFailureV1.missingContent },
                contentEntryResolver: { _ in throw ContentContractFailureV1.missingContent },
                interruptionPoint: { box.point }
            )
            let before = try journal.semanticProjection(unresolvedConflicts: nil)
            beforeCanonical = before.canonicalSnapshotSHA256
            beforeTombstones = String(describing: before.tombstoneIdentities)
            beforeMutations = String(describing: before.observedMutationIDs)
            switch boundary {
            case "JOURNAL_AFTER_CHECKPOINT_PREPARED":
                box.point = .afterCheckpointPrepared
                operation = "LocalChangeJournalV1.prepareCheckpoint"
                do { _ = try journal.prepareCheckpoint(supplement: .init(contentEntries: [], reversalEligibility: [])) }
                catch { visibleFailure = String(describing: error) }
            case "JOURNAL_AFTER_CHECKPOINT_STATE_WRITTEN":
                let preparation = try journal.prepareCheckpoint(
                    supplement: .init(contentEntries: [], reversalEligibility: [])
                )
                box.point = .afterCheckpointStateWritten
                operation = "LocalChangeJournalV1.activatePreparedCheckpoint"
                do { _ = try journal.activatePreparedCheckpoint(preparation) }
                catch { visibleFailure = String(describing: error) }
            case "JOURNAL_AFTER_COMPACTION_STATE_WRITTEN":
                let preparation = try journal.prepareCheckpoint(
                    supplement: .init(contentEntries: [], reversalEligibility: [])
                )
                _ = try journal.activatePreparedCheckpoint(preparation)
                box.point = .afterCompactionStateWritten
                operation = "LocalChangeJournalV1.compact"
                do { _ = try journal.compact(through: preparation.manifest.checkpointID) }
                catch { visibleFailure = String(describing: error) }
            default:
                throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
            }
        }
        guard !visibleFailure.isEmpty else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
        }
        await Task.yield()
        box.point = .none
        let reopened = try StoreGenerationFactory(
            applicationSupportURL: support, pointerEnrichmentIdentity: identity
        ).openOrBootstrapCurrent()
        let coldCoordinator = try StoreSessionCoordinator(validatingSession: reopened)
        let coldDependencies = try coldCoordinator.packageLifecycleDependencies(profileRegistry: registry)
        let coldBackup = BackupExportService(
            modelContext: reopened.modelContext,
            generationRootURL: reopened.generationRootURL,
            lifecycleDependencies: coldDependencies,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max })
        )
        let recovered = try coldCoordinator.localChangeJournal(
            backupExport: coldBackup, limits: limits,
            policyResolver: { _, _ in
                try ConflictPolicyV1(policyID: "v9_20_a01_append_union", rule: .stableIDAppendUnion)
            },
            contentReferenceResolver: { _ in throw ContentContractFailureV1.missingContent },
            contentEntryResolver: { _ in throw ContentContractFailureV1.missingContent }
        )
        try recovered.recoverInterruptedWork()
        _ = try recovered.resumeStagedBatches()
        let preparations = try recovered.resumableCheckpointPreparations()
        for preparation in preparations {
            _ = try? recovered.activatePreparedCheckpoint(preparation)
        }
        try recovered.recoverInterruptedWork()
        let secondResume = try recovered.resumeStagedBatches()
        let after = try recovered.semanticProjection(unresolvedConflicts: nil)
        let residual = try recovered.resumableCheckpointPreparations().count
        let orphanCount = temporaryFileCount(under: reopened.generationRootURL)
        let coldRecovered = beforeCanonical == after.canonicalSnapshotSHA256
            && beforeTombstones == String(describing: after.tombstoneIdentities)
            && beforeMutations == String(describing: after.observedMutationIDs)
        let noPartial = coldRecovered && secondResume.isEmpty
            && residual == 0 && orphanCount == 0
        guard coldRecovered, noPartial else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("\(boundary)-projection")
        }
        return .init(
            boundary: boundary, family: "JOURNAL", visibleFailure: visibleFailure,
            operationAttempted: operation,
            recoveryOperation: "cold-LocalChangeJournalV1.recoverInterruptedWork+resume",
            coldRecoverySucceeded: coldRecovered, noPartialAuthority: noPartial,
            canonicalRowCount: after.observedMutationIDs.count,
            residualIntentCount: residual,
            orphanPathCount: orphanCount
        )
    }

    private func exerciseJournalReplayFaultBoundary(
        _ boundary: String
    ) async throws -> KernelConformanceFaultBoundaryReceiptV1 {
        let support = isolatedFaultRoot(boundary)
        defer { try? FileManager.default.removeItem(at: support) }
        let workspace = WorkspaceID(rawValue: Self.fixedUUID(label: "R", slot: 500))
        let sourceIdentity = try WorkspaceReplicaIdentityV1(
            workspaceID: workspace,
            replicaID: ReplicaID(rawValue: Self.fixedUUID(label: "A", slot: 501))
        )
        let destinationIdentity = try WorkspaceReplicaIdentityV1(
            workspaceID: workspace,
            replicaID: ReplicaID(rawValue: Self.fixedUUID(label: "B", slot: 502))
        )
        let limits = try ChangeJournalLimitsV1(
            maximumChangesPerBatch: 1, maximumBatchBytes: 4_194_304,
            maximumEntitiesPerCheckpoint: 10_000,
            maximumContentEntriesPerCheckpoint: 10_000,
            maximumReplicaFrontiers: 4, maximumConflicts: 64
        )
        let box = KernelConformanceJournalInterruptionBoxV1()
        let source = try KernelConformanceReplicaNodeV1(
            label: "A", applicationSupportURL: support.appendingPathComponent("source"),
            identity: sourceIdentity, limits: limits,
            profile: try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        )
        let destinationURL = support.appendingPathComponent("destination")
        var destination: KernelConformanceReplicaNodeV1? = try KernelConformanceReplicaNodeV1(
            label: "B", applicationSupportURL: destinationURL,
            identity: destinationIdentity, limits: limits,
            profile: try WorkspacePackageLifecycleCompatibilityV1.shippingProfile(),
            interruptionPoint: { box.point }
        )
        let preparation = try source.journal.prepareCheckpoint(
            supplement: .init(contentEntries: [], reversalEligibility: [])
        )
        let transported = try source.journal.exportPreparedCheckpoint(
            preparation, packageRelativePath: "kernel/replay-checkpoint.fecp"
        )
        _ = try source.journal.activatePreparedCheckpoint(preparation)
        _ = try requireValue(destination, "journal-destination").journal.installImportedCheckpoint(
            export: transported.export, packageData: transported.packageData
        )
        let siteID = Self.fixedUUID(label: "A", slot: 510)
        let outcome = try source.coordinator.workspaceWriter.execute(
            .createFirstSign(.init(
                siteID: siteID,
                newSite: .init(id: siteID, label: "Replay Site", address: nil, timeZoneID: "UTC"),
                assetID: Self.fixedUUID(label: "A", slot: 511), assetLabel: "Replay Asset",
                packID: SignPack.illuminatedSignV1.packID,
                packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
                packContentVersion: SignPack.illuminatedSignV1.contentVersion,
                createdAt: Date(timeIntervalSince1970: 1_700_031_000),
                initialPlacementMutationID: try MutationIDV1(
                    rawValue: Self.fixedUUID(label: "A", slot: 512)
                ),
                initialPlacementEventID: Self.fixedUUID(label: "A", slot: 513),
                initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(
                    rawValue: Self.fixedUUID(label: "A", slot: 514)
                )
            )),
            mutationID: try MutationIDV1(rawValue: Self.fixedUUID(label: "A", slot: 515))
        )
        let cursor = try source.journal.initialCursor(
            consumerReplicaID: destinationIdentity.replicaID,
            checkpointID: preparation.manifest.checkpointID
        )
        let batch = try source.journal.page(after: cursor)
        guard batch.changes.count == 1 else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("\(boundary)-batch")
        }
        box.point = .afterReplayMutation(0)
        var visibleFailure = ""
        do { _ = try requireValue(destination, "journal-destination").journal.replayResult(batch) }
        catch { visibleFailure = String(describing: error) }
        guard !visibleFailure.isEmpty else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage(boundary)
        }
        destination = nil
        box.point = .none
        let recovered = try KernelConformanceReplicaNodeV1(
            label: "B-cold", applicationSupportURL: destinationURL,
            identity: destinationIdentity, limits: limits,
            profile: try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        )
        try recovered.journal.recoverInterruptedWork()
        let resumed = try recovered.journal.resumeStagedBatches()
        let projection = try recovered.journal.semanticProjection(unresolvedConflicts: nil)
        let observed = projection.observedMutationIDs.filter { $0 == outcome.mutationID }
        let secondResume = try recovered.journal.resumeStagedBatches()
        let orphanCount = temporaryFileCount(under: recovered.session.generationRootURL)
        let coldRecovered = resumed.count == 1 && observed.count == 1
        let noPartial = coldRecovered && secondResume.isEmpty && orphanCount == 0
        guard coldRecovered, noPartial else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("\(boundary)-recovery")
        }
        return .init(
            boundary: boundary, family: "JOURNAL", visibleFailure: visibleFailure,
            operationAttempted: "LocalChangeJournalV1.replayResult",
            recoveryOperation: "cold-LocalChangeJournalV1.recoverInterruptedWork+resumeStagedBatches",
            coldRecoverySucceeded: coldRecovered, noPartialAuthority: noPartial,
            canonicalRowCount: projection.observedMutationIDs.count,
            residualIntentCount: 0, orphanPathCount: orphanCount
        )
    }

    private func isolatedFaultRoot(_ boundary: String) -> URL {
        root.appendingPathComponent(
            "fault-\(boundary.lowercased())-\(UUID().uuidString)", isDirectory: true
        )
    }

    private func createBoundaryAsset(
        coordinator: StoreSessionCoordinator,
        profile: WorkspacePackageLifecycleProfileV1,
        label: String
    ) async throws -> UUID {
        let siteID = UUID(), assetID = UUID()
        _ = try await coordinator.executeAndSynchronizeSearchIndex(
            .createFirstSign(.init(
                siteID: siteID,
                newSite: .init(
                    id: siteID, label: "\(label) Site", address: nil,
                    timeZoneID: "America/New_York"
                ),
                assetID: assetID, assetLabel: label,
                packID: profile.package.packID,
                packSchemaVersion: profile.package.schemaVersion,
                packContentVersion: profile.package.contentVersion,
                createdAt: Date(timeIntervalSince1970: 1_700_040_000),
                initialPlacementMutationID: try MutationIDV1(rawValue: UUID()),
                initialPlacementEventID: UUID(),
                initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: UUID())
            ))
        )
        return assetID
    }

    private func uuidSequence(_ values: [UUID]) -> () -> UUID {
        var remaining = values
        return { remaining.removeFirst() }
    }

    private func canonicalDomainRowCount(_ context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Site>())
            + context.fetchCount(FetchDescriptor<Asset>())
            + context.fetchCount(FetchDescriptor<LocationNode>())
            + context.fetchCount(FetchDescriptor<WorkflowRecord>())
            + context.fetchCount(FetchDescriptor<EvidenceFile>())
            + context.fetchCount(FetchDescriptor<Issue>())
            + context.fetchCount(FetchDescriptor<Packet>())
            + context.fetchCount(FetchDescriptor<Report>())
            + context.fetchCount(FetchDescriptor<DeletionLedgerRow>())
    }

    private func directoryEntryCount(_ directory: URL) -> Int {
        (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ).count) ?? 0
    }

    private func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func requireValue<T>(_ value: T?, _ label: String) throws -> T {
        guard let value else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage(label)
        }
        return value
    }

    private func temporaryFileCount(under root: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else { return 0 }
        return enumerator.compactMap { $0 as? URL }.filter {
            $0.lastPathComponent.hasSuffix(".tmp")
        }.count
    }

    private func runReplicaSchedule(
        runLabel: String,
        replicas: [String],
        deliveries: [String],
        profile: WorkspacePackageLifecycleProfileV1,
        exercisePostConvergence: Bool
    ) async throws -> KernelConformanceReplicaRunV1 {
        let workspaceID = WorkspaceID(rawValue: Self.fixedUUID(label: "W", slot: 1))
        let limits = try ChangeJournalLimitsV1(
            maximumChangesPerBatch: 1,
            maximumBatchBytes: 4_194_304,
            maximumEntitiesPerCheckpoint: 10_000,
            maximumContentEntriesPerCheckpoint: 10_000,
            maximumReplicaFrontiers: 4,
            maximumConflicts: 64
        )
        var nodes: [String: KernelConformanceReplicaNodeV1] = [:]
        for label in replicas {
            let identity = try WorkspaceReplicaIdentityV1(
                workspaceID: workspaceID,
                replicaID: ReplicaID(rawValue: Self.fixedUUID(label: label, slot: 1))
            )
            nodes[label] = try KernelConformanceReplicaNodeV1(
                label: label,
                applicationSupportURL: root.appendingPathComponent(
                    "r01-\(runLabel)-\(label)", isDirectory: true
                ),
                identity: identity,
                limits: limits,
                profile: profile
            )
        }
        var checkpoints: [String: WorkspaceCheckpointPreparationV1] = [:]
        var exports: [String: (export: WorkspaceCheckpointExportV1, packageData: Data)] = [:]
        for label in replicas {
            guard let node = nodes[label] else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage(label)
            }
            let preparation = try node.journal.prepareCheckpoint(
                supplement: .init(contentEntries: [], reversalEligibility: [])
            )
            checkpoints[label] = preparation
            exports[label] = try node.journal.exportPreparedCheckpoint(
                preparation, packageRelativePath: "kernel/\(label)-checkpoint.fecp"
            )
            _ = try node.journal.activatePreparedCheckpoint(preparation)
        }
        for source in replicas {
            guard let transported = exports[source] else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage(source)
            }
            for destination in replicas where destination != source {
                guard let node = nodes[destination] else {
                    throw KernelConformanceFixtureFailureV1.incompleteCoverage(destination)
                }
                _ = try node.journal.installImportedCheckpoint(
                    export: transported.export, packageData: transported.packageData
                )
            }
        }
        let requiredIndices = try Self.requiredTokenIndices(
            replicas: replicas, deliveries: deliveries
        )
        var outcomes: [String: WorkspaceMutationOutcomeV1] = [:]
        for label in replicas {
            guard let node = nodes[label], let maximum = requiredIndices[label] else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage(label)
            }
            if maximum >= 1 {
                let siteID = Self.fixedUUID(label: label, slot: 10)
                let command = WorkspaceCommandV1.createFirstSign(FirstSignMutationV1(
                    siteID: siteID,
                    newSite: .init(
                        id: siteID, label: "Replica \(label) Site", address: nil,
                        timeZoneID: "America/New_York"
                    ),
                    assetID: Self.fixedUUID(label: label, slot: 11),
                    assetLabel: "Replica \(label) Asset",
                    packID: profile.package.packID,
                    packSchemaVersion: profile.package.schemaVersion,
                    packContentVersion: profile.package.contentVersion,
                    createdAt: Date(timeIntervalSince1970: 1_700_001_000),
                    initialPlacementMutationID: try MutationIDV1(
                        rawValue: Self.fixedUUID(label: label, slot: 12)
                    ),
                    initialPlacementEventID: Self.fixedUUID(label: label, slot: 13),
                    initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(
                        rawValue: Self.fixedUUID(label: label, slot: 14)
                    )
                ))
                outcomes["\(label)1"] = try node.coordinator.workspaceWriter.execute(
                    command,
                    mutationID: try MutationIDV1(
                        rawValue: Self.fixedUUID(label: label, slot: 101)
                    )
                )
            }
            if maximum >= 2 {
                outcomes["\(label)2"] = try node.coordinator.workspaceWriter.execute(
                    .updateSiteTimeZone(SiteTimeZoneMutationV1(
                        siteID: Self.fixedUUID(label: label, slot: 10),
                        timeZoneID: "UTC",
                        confirmedAt: Date(timeIntervalSince1970: 1_700_001_100)
                    )),
                    mutationID: try MutationIDV1(
                        rawValue: Self.fixedUUID(label: label, slot: 102)
                    )
                )
            }
        }
        var batches: [String: ChangeBatchV1] = [:]
        for source in replicas {
            guard let sourceNode = nodes[source], let checkpoint = checkpoints[source],
                  let maximum = requiredIndices[source] else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage(source)
            }
            for destination in replicas where destination != source {
                guard let destinationNode = nodes[destination] else {
                    throw KernelConformanceFixtureFailureV1.incompleteCoverage(destination)
                }
                var cursor = try sourceNode.journal.initialCursor(
                    consumerReplicaID: destinationNode.coordinator.replicaID,
                    checkpointID: checkpoint.manifest.checkpointID
                )
                for index in 1...maximum {
                    let batch = try sourceNode.journal.page(after: cursor)
                    guard batch.changes.count == 1 else {
                        throw KernelConformanceFixtureFailureV1.incompleteCoverage(
                            "\(source)\(index)>\(destination)"
                        )
                    }
                    batches["\(source)\(index)>\(destination)"] = batch
                    cursor = batch.afterCursor
                }
            }
        }
        let policy = try ConflictPolicyV1(
            policyID: "v9_20_r01_append_union", rule: .stableIDAppendUnion
        )
        let competitors = try ["A1", "B1"].compactMap { token -> ConflictCompetitorV1? in
            guard let outcome = outcomes[token] else { return nil }
            return try ConflictCompetitorV1(
                mutationID: outcome.mutationID,
                canonicalInputSHA256: outcome.commandDigest
            )
        }
        guard competitors.count == min(2, replicas.count) else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("resolution-inputs")
        }
        let resolution = try ConflictResolutionBasisV1(
            subject: .workspace(workspaceID),
            policy: policy,
            competitors: competitors,
            causalFrontier: try ConflictCausalFrontierV1(
                baseRevision: 0, baseSemanticSHA256: nil, observedInputs: competitors
            ),
            disposition: .stableIDAppendUnion
        )
        for delivery in deliveries {
            if delivery.hasPrefix("RESOLUTION>") {
                let destination = String(delivery.dropFirst("RESOLUTION>".count))
                guard let node = nodes[destination] else {
                    throw KernelConformanceFixtureFailureV1.incompleteCoverage(delivery)
                }
                try node.journal.installConflictResolution(resolution)
            } else {
                guard let destination = delivery.split(separator: ">").last.map(String.init),
                      let node = nodes[destination], let batch = batches[delivery] else {
                    throw KernelConformanceFixtureFailureV1.incompleteCoverage(delivery)
                }
                _ = try node.journal.replayResult(batch)
                _ = try node.journal.resumeStagedBatches()
            }
        }
        var normalized: [KernelConformanceNormalizedReplicaProjectionV1] = []
        let expectedMutationIDs = replicas.flatMap { label in
            (1...(requiredIndices[label] ?? 0)).map { index in
                Self.fixedUUID(label: label, slot: 100 + index).uuidString.lowercased()
            }
        }.sorted()
        for label in replicas {
            guard let node = nodes[label] else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage(label)
            }
            try node.journal.recoverInterruptedWork()
            _ = try node.journal.resumeStagedBatches()
            let projection = try node.journal.semanticProjection(unresolvedConflicts: nil)
            let history = try node.coordinator.workspaceWriter.sourceMutationHistorySnapshot()
            let content = try Set(history.receipts.flatMap {
                try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData)
                    .contentDependencyIDs
            }).sorted()
            let observedMutationIDs = projection.observedMutationIDs
                .map { $0.rawValue.uuidString.lowercased() }.sorted()
            let assets = try node.session.modelContext.fetch(FetchDescriptor<Asset>())
            let siteCount = try node.session.modelContext.fetchCount(FetchDescriptor<Site>())
            let placementEventCount = try node.session.modelContext.fetchCount(
                FetchDescriptor<AssetPlacementEventRow>()
            )
            guard projection.tombstoneIdentities.isEmpty,
                  projection.unresolvedConflictIdentities.isEmpty,
                  content.isEmpty,
                  observedMutationIDs == expectedMutationIDs,
                  history.receipts.count == expectedMutationIDs.count,
                  siteCount == replicas.count,
                  assets.count == replicas.count,
                  placementEventCount == replicas.count,
                  assets.allSatisfy({
                      $0.packID == profile.package.packID
                        && $0.packSchemaVersion == profile.package.schemaVersion
                        && $0.packContentVersion == profile.package.contentVersion
                  }) else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage(
                    "normalized-replica-oracle-\(label)"
                )
            }
            normalized.append(KernelConformanceNormalizedReplicaProjectionV1(
                semanticSHA256: projection.semanticSHA256,
                canonicalSnapshotSHA256: projection.canonicalSnapshotSHA256,
                tombstoneStableKeys: projection.tombstoneIdentities.map(\.stableKey).sorted(),
                unresolvedConflictSHA256: projection.unresolvedConflictIdentities
                    .map(\.digestSHA256).sorted(),
                contentDispositionSHA256: projection.contentDispositionSHA256,
                observedMutationIDs: observedMutationIDs,
                contentDependencyIDs: content,
                siteCount: siteCount,
                assetCount: assets.count,
                placementEventCount: placementEventCount
            ))
        }
        let post: KernelConformancePostConvergenceReceiptV1?
        if exercisePostConvergence {
            guard let primary = nodes[replicas[0]] else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage("post-convergence")
            }
            post = try await Self.exercisePostConvergenceLifecycle(
                primary, profile: profile
            )
        } else {
            post = nil
        }
        return KernelConformanceReplicaRunV1(
            projections: normalized, postConvergence: post
        )
    }

    private static func requiredTokenIndices(
        replicas: [String], deliveries: [String]
    ) throws -> [String: Int] {
        var result = Dictionary(uniqueKeysWithValues: replicas.map { ($0, 0) })
        for delivery in deliveries where !delivery.hasPrefix("RESOLUTION>") {
            let halves = delivery.split(separator: ">", omittingEmptySubsequences: false)
            guard halves.count == 2, halves[0].count == 2,
                  let label = halves[0].first.map(String.init), replicas.contains(label),
                  let index = Int(String(halves[0].last!)), (1...2).contains(index),
                  replicas.contains(String(halves[1])) else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage(delivery)
            }
            result[label] = max(result[label, default: 0], index)
        }
        guard result.values.allSatisfy({ $0 > 0 }) else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("replica-token")
        }
        return result
    }

    private static func exercisePostConvergenceLifecycle(
        _ node: KernelConformanceReplicaNodeV1,
        profile: WorkspacePackageLifecycleProfileV1
    ) async throws -> KernelConformancePostConvergenceReceiptV1 {
        try node.journal.recoverInterruptedWork()
        _ = try node.journal.resumeStagedBatches()
        let registry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        let dependencies = try node.coordinator.packageLifecycleDependencies(
            profileRegistry: registry
        )
        let exporter = BackupExportService(
            modelContext: node.session.modelContext,
            generationRootURL: node.session.generationRootURL,
            lifecycleDependencies: dependencies,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max })
        )
        let preview = try exporter.prepareStreaming()
        let destination = node.applicationSupportURL.appendingPathComponent(
            "exports", isDirectory: true
        )
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let archive = try exporter.exportStreaming(previewID: preview.id, to: destination)
        let restoreSupport = node.applicationSupportURL.appendingPathComponent(
            "restore-proof", isDirectory: true
        )
        let chain: (
            restoreActivated: Bool, searchRebuilt: Bool,
            deletionCommitted: Bool, eraseActivated: Bool
        ) = try await { () async throws -> (
            restoreActivated: Bool, searchRebuilt: Bool,
            deletionCommitted: Bool, eraseActivated: Bool
        ) in
            let restoreTarget = try StoreGenerationFactory(applicationSupportURL: restoreSupport)
                .openOrBootstrapCurrent()
            let validated = try BackupImportService(
                generationRootURL: restoreTarget.generationRootURL,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max }),
                scopedAccess: .alreadyAuthorized
            ).stageAndValidate(selectedPackageURL: archive)
            let restored = try await BackupRestoreService(
                applicationSupportURL: restoreSupport,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max })
            ).restore(
                validatedPackage: validated,
                currentModelContext: restoreTarget.modelContext,
                currentGenerationID: restoreTarget.generationID,
                currentGenerationRootURL: restoreTarget.generationRootURL,
                mode: .emptyInstall
            )
            let restoredCoordinator = try StoreSessionCoordinator(validatingSession: restored)
            let restoredDependencies = try restoredCoordinator.packageLifecycleDependencies(
                profileRegistry: registry
            )
            let restoreActivated = try restored.modelContext.fetchCount(
                FetchDescriptor<Asset>()
            ) > 0
            let search = try await restoredCoordinator.rebuildSearchProjectionIfNeeded()
            guard restoreActivated, search.indexedRecordCount > 0,
                  let assetID = try restored.modelContext.fetch(FetchDescriptor<Asset>()).first?.id
            else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage("post-delete")
            }
            let deletion = try await WholeSignDeletionService(
                modelContext: restored.modelContext,
                lifecycleDependencies: restoredDependencies
            ).delete(assetID: assetID)
            let diagnostics = DiagnosticsStore(applicationSupportURL: restoreSupport)
            let erase = try await EraseAllService(
                applicationSupportURL: restoreSupport
            ).erase(
                confirmation: EraseAllService.requiredConfirmation,
                coordinator: restoredCoordinator,
                diagnosticsStore: diagnostics,
                activate: { [weak coordinator = restoredCoordinator] replacement in
                    coordinator?.activate(session: replacement)
                },
                lifecycleDependencies: restoredDependencies
            )
            return (
                restoreActivated,
                search.indexedRecordCount > 0,
                deletion.assetID == assetID,
                try erase.session.modelContext.fetchCount(FetchDescriptor<Asset>()) == 0
            )
        }()
        await Task.yield()
        let reopenedAfterErase = try StoreGenerationFactory(
            applicationSupportURL: restoreSupport
        ).openOrBootstrapCurrent()
        _ = try StoreSessionCoordinator(validatingSession: reopenedAfterErase)
        let reopenedContext = reopenedAfterErase.modelContext
        let recoveryCompleted = try reopenedContext.fetchCount(FetchDescriptor<Site>()) == 0
            && reopenedContext.fetchCount(FetchDescriptor<Asset>()) == 0
            && reopenedContext.fetchCount(FetchDescriptor<LocationNode>()) == 0
            && reopenedContext.fetchCount(FetchDescriptor<WorkflowRecord>()) == 0
            && reopenedContext.fetchCount(FetchDescriptor<Issue>()) == 0
            && reopenedContext.fetchCount(FetchDescriptor<Packet>()) == 0
            && reopenedContext.fetchCount(FetchDescriptor<Report>()) == 0
            && reopenedContext.fetchCount(FetchDescriptor<EvidenceFile>()) == 0
            && DeletionLedgerStore(context: reopenedContext).snapshot() == .empty
        guard recoveryCompleted else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("post-erase-cold-recovery")
        }
        return KernelConformancePostConvergenceReceiptV1(
            archivePrepared: preview.declaredPayloadByteCount > 0,
            restoreActivated: chain.restoreActivated,
            searchRebuilt: chain.searchRebuilt,
            deletionCommitted: chain.deletionCommitted,
            eraseActivated: chain.eraseActivated,
            recoveryCompleted: recoveryCompleted
        )
    }

    private static func fixedUUID(label: String, slot: Int) -> UUID {
        let scalar = Int(label.utf8.first ?? 0)
        return UUID(uuidString: String(
            format: "92000000-0000-4000-8000-%012x", slot * 256 + scalar
        ))!
    }

    private static func searchRecord(
        revision: SearchSourceRevisionV1,
        stableID: String
    ) throws -> SearchIndexProjectionRecordV1 {
        try SearchIndexProjectionRecordV1(
            workspaceID: revision.workspaceID,
            sourceKind: .asset,
            sourceStableID: stableID,
            sourceRevision: revision.commitRevision,
            fieldID: "asset_identifier",
            normalizedTokens: SearchCoordinatorV1.normalizedTokens(stableID),
            displayIdentity: stableID,
            locationBreadcrumb: [],
            status: "Incomplete",
            permittedSnippet: stableID,
            sourceTimestamp: Date(timeIntervalSince1970: 1)
        )
    }

    private static func rewriteStoredProjectionFormat(
        in applicationSupportURL: URL,
        as format: Int
    ) throws {
        let url = applicationSupportURL
            .appendingPathComponent(LocalSearchIndexStoreV1.directoryName)
            .appendingPathComponent(LocalSearchIndexStoreV1.fileName)
        guard var envelope = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any],
        var projection = envelope["projection"] as? [String: Any],
        var index = projection["index"] as? [String: Any] else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("search-envelope")
        }
        index["projectionFormatVersion"] = format
        projection["index"] = index
        envelope["projection"] = projection
        try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
            .write(to: url)
    }

    func prepareProductionArchive() throws -> BackupExportPreviewV1 {
        try BackupExportService(
            modelContext: session.modelContext,
            generationRootURL: session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max })
        ).prepareStreaming()
    }

    func exerciseArchiveRestoreRoundTrip() async throws -> StoreGenerationSession {
        let exportDirectory = root.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let exporter = BackupExportService(
            modelContext: session.modelContext,
            generationRootURL: session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max })
        )
        let preview = try exporter.prepareStreaming()
        let archive = try exporter.exportStreaming(previewID: preview.id, to: exportDirectory)
        let targetSupport = root.appendingPathComponent("restore-target", isDirectory: true)
        let restored: StoreGenerationSession = try await {
            let target = try StoreGenerationFactory(applicationSupportURL: targetSupport)
                .openOrBootstrapCurrent()
            let validated = try BackupImportService(
                generationRootURL: target.generationRootURL,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max }),
                scopedAccess: .alreadyAuthorized
            ).stageAndValidate(selectedPackageURL: archive)
            return try await BackupRestoreService(
                applicationSupportURL: targetSupport,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max })
            ).restore(
                validatedPackage: validated,
                currentModelContext: target.modelContext,
                currentGenerationID: target.generationID,
                currentGenerationRootURL: target.generationRootURL,
                mode: .emptyInstall
            )
        }()
        await Task.yield()
        coordinator = nil
        session = nil
        activeApplicationSupportURL = targetSupport
        session = restored
        coordinator = try StoreSessionCoordinator(validatingSession: restored)
        return restored
    }

    func deleteFirstAssetThroughProductionService(
        profile suppliedProfile: WorkspacePackageLifecycleProfileV1? = nil
    ) async throws -> WholeSignDeletionOutcome {
        guard let assetID = try session.modelContext.fetch(FetchDescriptor<Asset>()).first?.id else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("delete-asset")
        }
        let profile = try suppliedProfile
            ?? WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let registry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        let dependencies = try coordinator.packageLifecycleDependencies(profileRegistry: registry)
        return try await WholeSignDeletionService(
            modelContext: session.modelContext,
            lifecycleDependencies: dependencies
        ).delete(assetID: assetID)
    }

    func eraseWorkspaceThroughProductionService(
        profile suppliedProfile: WorkspacePackageLifecycleProfileV1? = nil
    ) async throws -> EraseAllOutcome {
        let profile = try suppliedProfile
            ?? WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let registry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        let dependencies = try coordinator.packageLifecycleDependencies(profileRegistry: registry)
        let diagnostics = DiagnosticsStore(applicationSupportURL: activeApplicationSupportURL)
        return try await EraseAllService(
            applicationSupportURL: activeApplicationSupportURL
        ).erase(
            confirmation: EraseAllService.requiredConfirmation,
            coordinator: coordinator,
            diagnosticsStore: diagnostics,
            activate: { [weak activeCoordinator = coordinator] replacement in
                activeCoordinator?.activate(session: replacement)
            },
            lifecycleDependencies: dependencies
        )
    }

    private func createFirstSign(
        assetLabel: String,
        profile: WorkspacePackageLifecycleProfileV1
    ) async throws {
        let siteID = UUID()
        let assetID = UUID()
        let placementMutationID = try MutationIDV1(rawValue: UUID())
        let command = WorkspaceCommandV1.createFirstSign(FirstSignMutationV1(
            siteID: siteID,
            newSite: .init(id: siteID, label: "\(assetLabel) Site", address: nil, timeZoneID: "America/New_York"),
            assetID: assetID,
            assetLabel: assetLabel,
            packID: profile.package.packID,
            packSchemaVersion: profile.package.schemaVersion,
            packContentVersion: profile.package.contentVersion,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            initialPlacementMutationID: placementMutationID,
            initialPlacementEventID: UUID(),
            initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: UUID())
        ))
        _ = try await coordinator.executeAndSynchronizeSearchIndex(command)
    }

    func exercisePackageLifecycle(
        shape: KernelConformanceFixtureShapeV1,
        profile suppliedProfile: WorkspacePackageLifecycleProfileV1? = nil
    ) async throws -> [String] {
        var actions: [String] = []
        let profile = try suppliedProfile ?? Self.profile(for: shape)
        let registry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        guard let assetID = try session.modelContext.fetch(FetchDescriptor<Asset>()).first?.id,
              let issueLabel = profile.package.issueLabels.first?.key else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("check-start")
        }
        let observedAt = Date(timeIntervalSince1970: 1_700_000_200)
        let persistedDraftID: UUID
        do {
            let initialDependencies = try coordinator.packageLifecycleDependencies(
                profileRegistry: registry
            )
            let initialRunner = try CheckRunnerCoordinator(
                modelContext: session.modelContext,
                packageLifecycleDependencies: initialDependencies,
                packageLifecycleProfile: profile
            )
            initialRunner.configureCapture(generationRootURL: session.generationRootURL)
            let draft = try initialRunner.beginCheck(
                assetID: assetID,
                timeZoneID: nil,
                isTimeZoneConfirmed: false,
                afterDarkAccepted: true,
                safePositionAccepted: true,
                observedAt: observedAt
            )
            persistedDraftID = draft.id
            actions.append("START")
            for offset in [1.0, 2.0] {
                let candidate = try await initialRunner.importCandidate(
                    assetID: assetID,
                    sourceData: try Self.makePNG(seed: UInt8(offset * 19)),
                    createdAt: observedAt.addingTimeInterval(offset)
                )
                _ = try await initialRunner.accept(candidate: candidate, assetID: assetID)
            }
            actions.append("EVIDENCE")
            _ = try initialRunner.prepareReview(
                assetID: assetID,
                selection: .visibleIssue(labelKey: issueLabel)
            )
            actions.append("RESPOND")
        }

        coordinator = nil
        session = nil
        session = try StoreGenerationFactory(applicationSupportURL: activeApplicationSupportURL)
            .openOrBootstrapCurrent()
        coordinator = try StoreSessionCoordinator(validatingSession: session)
        var dependencies: WorkspacePackageLifecycleDependenciesV1? = try coordinator
            .packageLifecycleDependencies(profileRegistry: registry)
        var runner: CheckRunnerCoordinator? = try CheckRunnerCoordinator(
            modelContext: session.modelContext,
            packageLifecycleDependencies: requireValue(
                dependencies, "package-lifecycle-dependencies"
            ),
            packageLifecycleProfile: profile
        )
        try requireValue(runner, "check-runner").configureCapture(
            generationRootURL: session.generationRootURL
        )
        let persistedResumeMatched = try { () throws -> Bool in
            let resumedDraft = try requireValue(
                runner, "check-runner"
            ).beginOrResumeDraft(BeginDraftSubmission(
                assetID: assetID,
                requestedStage: .check,
                issueID: nil,
                observedAtUTC: observedAt,
                confirmedTimeZoneID: nil,
                afterDarkAccepted: true,
                safePositionAccepted: true
            ))
            let resumedEvidenceCount = try session.modelContext.fetch(
                FetchDescriptor<EvidenceFile>()
            ).filter { $0.recordID == persistedDraftID }.count
            return resumedDraft.id == persistedDraftID && resumedEvidenceCount == 2
        }()
        guard persistedResumeMatched else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("persisted-check-resume")
        }
        if shape == .checklist {
            actions.append("RESUME")
        }
        let productionFindMatched = try { () throws -> Bool in
            let activeDependencies = try requireValue(
                dependencies, "package-lifecycle-dependencies"
            )
            let assetIdentity = try WorkspaceEntityIdentityV1(kind: .asset, id: assetID)
            let query = try WorkspacePackageLifecycleQueryRequestV1(
                workspaceID: activeDependencies.workspaceID,
                generationID: activeDependencies.generationID,
                operation: .query,
                identities: [assetIdentity]
            )
            let found = try activeDependencies.queryClient.query(query)
            return found.existingIdentities == [assetIdentity]
                && found.packageBindings.count == 1
                && found.packageBindings[0].assetID == assetID
                && found.packageBindings[0].packageID == profile.package.packID
                && found.packageBindings[0].packageSchemaVersion
                    == profile.package.schemaVersion
                && found.packageBindings[0].packageContentVersion
                    == profile.package.contentVersion
        }()
        guard productionFindMatched else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("production-find")
        }
        actions.append("FIND")
        let finalized = try await requireValue(runner, "check-runner").finalize(
            assetID: assetID,
            selection: .visibleIssue(labelKey: issueLabel),
            completedAt: observedAt.addingTimeInterval(3),
            snapshotCreatedAt: observedAt.addingTimeInterval(4),
            sourceApp: SourceAppSnapshotV1(build: "920", version: "9.20"),
            identifiers: FinalizationIdentifiers(
                mutationID: UUID(), packetID: UUID(), stableRootID: UUID(),
                reportID: UUID(), issueID: UUID()
            )
        )
        guard finalized.issueID != nil else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("check-finalize")
        }
        let finalizedRecordID = finalized.recordID
        let finalizedIssueID = finalized.issueID!
        actions.append("FINALIZE")
        if profile.stages.flatMap(\.outcomes).contains(where: { $0.role == .workRecorded }) {
            let recheckPreparation = try await {
                () async throws -> (submission: BeginDraftSubmission, draftID: UUID) in
                let activeRunner = try requireValue(runner, "check-runner")
                let work = try WorkCoordinator(
                    modelContext: session.modelContext,
                    signPack: profile.package,
                    generationRootURL: session.generationRootURL,
                    checkRunnerCoordinator: activeRunner
                )
                let workDraft = try work.beginWork(issueID: finalizedIssueID)
                let saved = try await work.saveWork(
                    draftID: workDraft.recordID,
                    submission: WorkSaveSubmission(
                        performedLocalDate: "2026-08-27",
                        description: "Replaced failed component",
                        note: "Production lifecycle conformance",
                        photos: [],
                        completedAt: observedAt.addingTimeInterval(30)
                    ),
                    identifiers: WorkIdentifiers(mutationID: UUID(), evidenceID: nil)
                )
                guard saved.status == .recheckDue else {
                    throw KernelConformanceFixtureFailureV1.incompleteCoverage("work")
                }
                actions.append("WORK")
                let submission = BeginDraftSubmission(
                    assetID: assetID,
                    requestedStage: .recheck,
                    issueID: finalizedIssueID,
                    observedAtUTC: observedAt.addingTimeInterval(40),
                    confirmedTimeZoneID: "America/New_York",
                    afterDarkAccepted: true,
                    safePositionAccepted: true
                )
                let draft = try activeRunner.beginOrResumeDraft(submission)
                return (submission: submission, draftID: draft.id)
            }()
            if shape == .measurementRepeat {
                runner = nil
                dependencies = nil
                await Task.yield()
                try relaunchCanonicalSession()
                dependencies = try coordinator.packageLifecycleDependencies(
                    profileRegistry: registry
                )
                runner = try CheckRunnerCoordinator(
                    modelContext: session.modelContext,
                    packageLifecycleDependencies: requireValue(
                        dependencies, "package-lifecycle-dependencies"
                    ),
                    packageLifecycleProfile: profile
                )
                try requireValue(runner, "check-runner").configureCapture(
                    generationRootURL: session.generationRootURL
                )
                let resumedRecheck = try requireValue(
                    runner, "check-runner"
                ).beginOrResumeDraft(recheckPreparation.submission)
                guard resumedRecheck.id == recheckPreparation.draftID else {
                    throw KernelConformanceFixtureFailureV1.incompleteCoverage(
                        "persisted-recheck-resume"
                    )
                }
                actions.append("RESUME")
            }
            let activeRunner = try requireValue(runner, "check-runner")
            for offset in [41.0, 42.0] {
                let candidate = try await activeRunner.importCandidate(
                    assetID: assetID,
                    sourceData: try Self.makePNG(seed: UInt8(offset)),
                    createdAt: observedAt.addingTimeInterval(offset)
                )
                _ = try await activeRunner.accept(candidate: candidate, assetID: assetID)
            }
            let recheck = try await activeRunner.finalize(
                assetID: assetID,
                selection: .resolved(note: "Production lifecycle recheck"),
                completedAt: observedAt.addingTimeInterval(50),
                snapshotCreatedAt: observedAt.addingTimeInterval(51),
                sourceApp: SourceAppSnapshotV1(build: "920", version: "9.20")
            )
            guard recheck.recordID != finalizedRecordID else {
                throw KernelConformanceFixtureFailureV1.incompleteCoverage("recheck")
            }
            actions.append("RECHECK")
        }
        let recovery = try PackFinalizationRecoveryAdapterV1(
            dependencies: requireValue(dependencies, "package-lifecycle-dependencies"),
            profile: profile,
            legacyModelContext: session.modelContext
        )
        let outcome = try await recovery.reconcile()
        guard outcome.packageRelease == profile.release,
              outcome.summary.recoveredDraftRecordIDs.isEmpty,
              !outcome.zeroFeatureWriteClosureClaimed else {
            throw KernelConformanceFixtureFailureV1.invalidArtifact("package-lifecycle")
        }
        withExtendedLifetime(runner) {}
        return actions
    }

    func cleanup() {
        coordinator = nil
        session = nil
        try? FileManager.default.removeItem(at: root)
    }

    private struct C11BoundsV1 {
        let maximumPageItems: Int
        let maximumPageBytes: Int
        let maximumGapPages: Int
        let maximumReplayAttempts: Int
        let scaleItemCount: Int
        let scalePageItems: Int
        let scaleExpectedPageCount: Int
        let scaleMaximumResidentBytes: Int
    }

    private struct RendererFixtureV1 {
        let snapshot: CompletedActivitySnapshotV1
        let manifest: ContractManifestV1
        let layout: ReportLayoutProfileV1
        let export: ExportProfileV1
    }

    private static func makeRendererFixture(
        snapshotRevision: Int,
        snapshotID: String = "snapshot-a",
        priorSnapshot: CompletedActivitySnapshotV1? = nil,
        packageReleaseID: String = "package-release-v1",
        reportProfileID: String = "customer-complete-v1",
        reportProfileRelease: Int = 1,
        detail: ReportDetailLevelV1 = .complete,
        sectionIDs: [String]? = nil,
        serviceStatus: String = "Scheduled",
        includeEvidenceCard: Bool = true
    ) throws -> RendererFixtureV1 {
        let formats: [ReportProjectionFormatV1] = [.openJSON, .pdf, .structuredText]
        let sections = try [
            ReportSectionDefinitionV1(sectionID: "identity", version: 1, required: true, supportedFormats: formats, privacyClass: .mandatoryPublicTruth, requiresHeading: true, requiresTextAlternative: true, order: 0),
            ReportSectionDefinitionV1(sectionID: "service", version: 1, required: false, supportedFormats: formats, privacyClass: .audienceSafe, requiresHeading: true, requiresTextAlternative: true, order: 1),
            ReportSectionDefinitionV1(sectionID: "evidence", version: 1, required: false, supportedFormats: formats, privacyClass: .audienceSafe, requiresHeading: true, requiresTextAlternative: true, order: 2),
            ReportSectionDefinitionV1(sectionID: "limitations", version: 1, required: true, supportedFormats: formats, privacyClass: .mandatoryPublicTruth, requiresHeading: true, requiresTextAlternative: true, order: 3),
            ReportSectionDefinitionV1(sectionID: "provenance", version: 1, required: true, supportedFormats: formats, privacyClass: .mandatoryPublicTruth, requiresHeading: true, requiresTextAlternative: true, order: 4),
            ReportSectionDefinitionV1(sectionID: "supersession", version: 1, required: true, supportedFormats: formats, privacyClass: .mandatoryPublicTruth, requiresHeading: true, requiresTextAlternative: true, order: 5),
            ReportSectionDefinitionV1(sectionID: "manifest", version: 1, required: true, supportedFormats: formats, privacyClass: .mandatoryPublicTruth, requiresHeading: true, requiresTextAlternative: true, order: 6),
        ]
        let sectionRegistry = try ReportSectionRegistryV1(
            registryID: "section-registry-v1", registryVersion: 1, sections: sections
        )
        let manifest = try ContractManifestV1(
            manifestID: "snapshot-contract-manifest-v1", manifestVersion: 1,
            codec: ContractCodecRuleV1(codecVersion: 1),
            compatibility: ContractCompatibilityRuleV1(
                minimumReaderVersion: 1, maximumReaderVersion: 1,
                unknownObjectFields: .reject
            ),
            objects: [try ContractObjectDefinitionV1(
                typeID: "completed-snapshot", version: 1, unknownFieldPolicy: .reject,
                fields: [try ContractFieldDefinitionV1(
                    fieldID: "snapshot-id", jsonName: "snapshotID", kind: .string,
                    required: true, maximumUTF8Bytes: 128
                )]
            )],
            enums: [try ContractEnumDefinitionV1(
                typeID: "report-audience", version: 1, policy: .closed,
                knownValues: ["CUSTOMER_SAFE", "INTERNAL"]
            )],
            reportSectionRegistry: sectionRegistry
        )
        let selectedSectionIDs = sectionIDs ?? sections.map(\.sectionID)
        let layout = try ReportLayoutProfileV1(
            profileID: reportProfileID, profileRelease: reportProfileRelease,
            audience: .customerSafe, detail: detail,
            sectionIDs: selectedSectionIDs, mediaLayout: .standardGrid,
            orientation: .portrait, localeIdentifier: "en_US",
            unitsProfileID: "units-si-v1", displayProfileID: "display-v1",
            registry: sectionRegistry
        )
        let export = try ExportProfileV1(
            exportProfileID: "portable-v1", exportProfileRelease: 1,
            formats: formats, packaging: .combined,
            privacyTransformID: "customer-safe-v1", maximumMediaItems: 32,
            maximumArchiveBytes: Int64(SnapshotProjectionLimitsV1.maximumProjectionBytes)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let binding = try FinalizedReportProfileBindingV1(
            workspaceID: "workspace-a", snapshotID: snapshotID,
            outputScopeID: "output-scope-a",
            reportProfileID: layout.profileID,
            reportProfileRelease: layout.profileRelease,
            reportProfileSHA256: KernelCanonicalHashV1.sha256(try encoder.encode(layout)),
            exportProfileID: export.exportProfileID,
            exportProfileRelease: export.exportProfileRelease,
            exportProfileSHA256: KernelCanonicalHashV1.sha256(try encoder.encode(export)),
            sectionRegistryID: sectionRegistry.registryID,
            sectionRegistryVersion: sectionRegistry.registryVersion,
            sectionRegistrySHA256: KernelCanonicalHashV1.sha256(
                try encoder.encode(sectionRegistry)
            ),
            contractManifestID: manifest.manifestID,
            contractManifestVersion: manifest.manifestVersion,
            contractManifestSHA256: KernelCanonicalHashV1.sha256(
                try encoder.encode(manifest)
            ),
            sectionIDs: layout.sectionIDs,
            audience: .customerSafe, detail: detail,
            privacyTransformID: "customer-safe-v1", localeIdentifier: "en_US",
            unitsProfileID: "units-si-v1", displayProfileID: "display-v1",
            orientation: .portrait, mediaLayout: .standardGrid,
            rendererVersion: ReportSemanticProjectorV1.rendererVersion,
            projectionVersion: "report-projection-v1"
        )
        let serviceFacts = try [
            CompletedServiceFactV1(
                factID: "service-history", kind: .serviceHistory,
                privacyClass: .audienceSafe, label: "Service history",
                value: "Request received",
                effectiveAt: "2026-08-26T23:59:59.000Z"
            ),
            CompletedServiceFactV1(
                factID: "service-status", kind: .serviceStatus,
                privacyClass: .audienceSafe, label: "Service status",
                value: serviceStatus, effectiveAt: "2026-08-27T00:00:00.000Z"
            ),
        ]
        let evidenceCards: [EvidenceDetailCardV1]
        if includeEvidenceCard {
            let contentDigest = try ContentDigestV1(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "1", count: 64)
            )
            let reference = try ContentReferenceV1(
                workspaceID: "workspace-a",
                contentID: "content-original",
                byteLength: 12,
                mediaType: "image/jpeg",
                digests: ContentDigestSetV1([contentDigest]),
                byteRole: .derivative,
                createdAt: "2026-08-27T00:00:00.000Z"
            )
            let outputReference = try OutputScopedContentReferenceV1(
                outputScopeID: "output-scope-a", ordinal: 0, reference: reference
            )
            let privacyPolicy = try AudiencePrivacyPolicyV1(
                policyID: "customer-safe-policy-v1",
                policyVersion: 1,
                audience: .customerSafe,
                prohibitedCanaries: Self.c06PrivacyCanaries.sorted()
            )
            let detailProfile = try EvidenceDetailCardProfileV1(
                profileID: "evidence-detail-customer-v1",
                profileRelease: 1,
                audience: .customerSafe,
                outputScopeID: "output-scope-a",
                privacyTransformID: "customer-safe-v1",
                privacyTransformVersion: 1,
                markupProfileID: "reviewed-markup-v1",
                markupProfileVersion: 1,
                localeIdentifier: "en_US",
                displayProfileID: "display-v1",
                rendererVersion: ReportSemanticProjectorV1.rendererVersion,
                audiencePrivacyPolicy: privacyPolicy,
                includedFieldIDs: [
                    "private_note", "service_request", "service_status",
                ],
                limitationsText: "Evidence detail does not verify capture time, location, or person."
            )
            let fields = try [
                EvidenceDetailFieldV1(
                    fieldID: "private_note", label: "Private note",
                    value: "PRIVATE-CANARY", sensitivity: .privateNote
                ),
                EvidenceDetailFieldV1(
                    fieldID: "service_request", label: "Service request",
                    value: "SR-100", sensitivity: .audienceSafe
                ),
                EvidenceDetailFieldV1(
                    fieldID: "service_status", label: "Service status",
                    value: serviceStatus, sensitivity: .audienceSafe
                ),
            ]
            evidenceCards = [try EvidenceDetailComposerV1.compose(
                cardID: "evidence-card-a",
                workspaceID: "workspace-a",
                evidenceID: "evidence-a",
                fields: fields,
                profile: detailProfile,
                markupID: "markup-a",
                annotations: ["Reviewed for customer-safe output"],
                referenceLabels: ["Customer-safe derivative"],
                outputReferences: [outputReference]
            )]
        } else {
            evidenceCards = []
        }
        let payload = try CompletedActivitySnapshotPayloadV1(
            workspaceID: "workspace-a", snapshotID: snapshotID,
            snapshotRevision: snapshotRevision,
            sourceActivityID: "activity-a", sourceRevision: snapshotRevision,
            reportID: "report-a",
            packageReleaseID: packageReleaseID,
            generatedAt: "2026-08-27T00:00:00.000Z",
            completedAt: "2026-08-27T00:00:00.000Z",
            supersedesSnapshotID: priorSnapshot?.payload.snapshotID,
            supersededSnapshotSHA256: priorSnapshot?.snapshotSHA256,
            amendmentReason: priorSnapshot == nil
                ? nil : "Corrected reviewed service status",
            profileBinding: binding,
            serviceFacts: serviceFacts.sorted { $0.factID < $1.factID },
            evidenceCards: evidenceCards,
            limitations: ["Projection facts are frozen from the completed activity."]
        )
        let snapshot: CompletedActivitySnapshotV1
        if let priorSnapshot {
            snapshot = try CompletedActivitySnapshotV1.freezeAmendment(
                payload, superseding: priorSnapshot
            )
        } else if snapshotRevision == 1 {
            snapshot = try CompletedActivitySnapshotV1.freezeOriginal(payload)
        } else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
        return RendererFixtureV1(
            snapshot: snapshot, manifest: manifest, layout: layout, export: export
        )
    }

    private static func loadC11Bounds() throws -> C11BoundsV1 {
        let data = try KernelConformanceFixtureHarnessV1.readRequiredData(
            KernelConformanceFixtureHarnessV1.c11CorpusURL()
        )
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["schema"] as? String
                == "V21P03C11ChangeJournalCheckpointReplayCorpusV1",
              root["schemaVersion"] as? Int == 1,
              let bounds = root["bounds"] as? [String: Any],
              let scale = root["scale"] as? [String: Any],
              Set(bounds.keys) == Set([
                  "maximumPageItems", "maximumPageBytes", "maximumGapPages",
                  "maximumReplayAttempts", "scaleAssetCount", "scalePageItems",
                  "scaleExpectedPageCount", "scaleMaximumResidentBytes",
              ]),
              let maximumPageItems = bounds["maximumPageItems"] as? Int,
              let maximumPageBytes = bounds["maximumPageBytes"] as? Int,
              let maximumGapPages = bounds["maximumGapPages"] as? Int,
              let maximumReplayAttempts = bounds["maximumReplayAttempts"] as? Int,
              let scaleItemCount = bounds["scaleAssetCount"] as? Int,
              let scalePageItems = bounds["scalePageItems"] as? Int,
              let scaleExpectedPageCount = bounds["scaleExpectedPageCount"] as? Int,
              let scaleMaximumResidentBytes = bounds["scaleMaximumResidentBytes"] as? Int,
              scale["assetCount"] as? Int == scaleItemCount,
              scale["pageItemLimit"] as? Int == scalePageItems,
              scale["expectedPageCount"] as? Int == scaleExpectedPageCount,
              scale["maximumResidentBytes"] as? Int == scaleMaximumResidentBytes,
              maximumPageItems == 3, maximumPageBytes == 65_536,
              maximumGapPages == 2, maximumReplayAttempts == 4,
              scaleItemCount == 10_000, scalePageItems == 128,
              scaleExpectedPageCount == 79,
              scaleMaximumResidentBytes == 16_777_216 else {
            throw KernelConformanceFixtureFailureV1.invalidArtifact("c11-bounds")
        }
        return C11BoundsV1(
            maximumPageItems: maximumPageItems,
            maximumPageBytes: maximumPageBytes,
            maximumGapPages: maximumGapPages,
            maximumReplayAttempts: maximumReplayAttempts,
            scaleItemCount: scaleItemCount,
            scalePageItems: scalePageItems,
            scaleExpectedPageCount: scaleExpectedPageCount,
            scaleMaximumResidentBytes: scaleMaximumResidentBytes
        )
    }

    private enum HostileDecodeExpectationV1: Equatable { case batchVersion, batchField }

    private static func decodeMutationRejected<Value: Decodable>(
        _ canonical: Data,
        key: String,
        replacement: Any,
        as type: Value.Type,
        expected: HostileDecodeExpectationV1
    ) throws -> Bool {
        guard var object = try JSONSerialization.jsonObject(with: canonical) as? [String: Any]
        else { throw KernelConformanceFixtureFailureV1.invalidArtifact("canonical-mutation") }
        object[key] = replacement
        let hostile = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        do {
            _ = try JSONDecoder().decode(type, from: hostile)
            return false
        } catch ChangeJournalFailureV1.incompatibleVersion {
            return expected == .batchVersion
        } catch InspectionKernelFailureV1.invalidValue {
            return expected == .batchField
        }
    }

    private static func decodeCanonicalPolicyMutationRejected(
        _ canonical: Data,
        key: String,
        replacement: Any,
        expectedRuleFailure: Bool
    ) throws -> Bool {
        guard var object = try JSONSerialization.jsonObject(with: canonical) as? [String: Any]
        else { throw KernelConformanceFixtureFailureV1.invalidArtifact("policy-mutation") }
        object[key] = replacement
        let hostile = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        do {
            _ = try ConflictPolicyV1.decodeCanonical(from: hostile)
            return false
        } catch DecodingError.dataCorrupted(_) {
            return expectedRuleFailure
        } catch ConflictPolicyFailureV1.invalidPolicy {
            return !expectedRuleFailure
        }
    }

    private static func unknownRegisteredCodecIsRejected() throws -> Bool {
        let current = try CurrentSyncClassificationCatalogV1.current
        guard let baseline = current.registrations.first else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("codec-registry")
        }
        let canonical = try baseline.replicationPolicy.canonicalData()
        guard var object = try JSONSerialization.jsonObject(with: canonical) as? [String: Any],
              var codec = object["codec"] as? [String: Any] else {
            throw KernelConformanceFixtureFailureV1.invalidArtifact("codec-registry")
        }
        codec["readableVersions"] = [2]
        object["codec"] = codec
        let hostile = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        do {
            _ = try ReplicationPolicyV1.decodeCanonical(from: hostile)
            return false
        } catch ReplicationPolicyFailureV1.invalidCodec {
            return true
        }
    }

    private static func profile(
        for shape: KernelConformanceFixtureShapeV1
    ) throws -> WorkspacePackageLifecycleProfileV1 {
        switch shape {
        case .checklist:
            return try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        case .measurementRepeat:
            return try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(
                package: try alternatePackage()
            )
        }
    }

    private static func alternatePackage() throws -> SignPack {
        let data = try KernelConformanceFixtureHarnessV1.readRequiredData(
            KernelConformanceFixtureHarnessV1.sourceRoot().appendingPathComponent(
                "FieldEvidenceAppTests/Fixtures/V21/Packs/V21P03C01AlternatePackV1.json"
            )
        )
        let canonical = data.last == 0x0A ? Data(data.dropLast()) : data
        let package = try InspectionPackageCanonicalCodecV2.decode(canonical)
        let p = package.presentation
        var evidencePurposes = p.evidencePurposes
        evidencePurposes.append(.init(
            key: "work_context",
            display: "Fixture work context",
            instruction: "Capture bounded synthetic work context for the alternate fixture."
        ))
        var outcomeDisplays = p.outcomeDisplays
        outcomeDisplays.append(contentsOf: [
            .init(key: "resolved", display: "Synthetic condition resolved"),
            .init(key: "issue_still_visible", display: "Synthetic condition still visible"),
            .init(
                key: "original_resolved_different_issue",
                display: "Original resolved; different synthetic condition visible"
            ),
        ])
        return SignPack(
            schemaVersion: package.schemaVersion, packID: package.packageID,
            contentVersion: package.contentVersion + 1,
            nouns: .init(asset: .init(singular: p.assetSingular, plural: p.assetPlural), check: .init(singular: p.checkSingular, plural: p.checkPlural), issue: .init(singular: p.issueSingular, plural: p.issuePlural)),
            evidencePurposes: evidencePurposes.map { .init(key: $0.key, display: $0.display, instruction: $0.instruction) },
            acknowledgements: p.acknowledgements.map { .init(key: $0.key, copy: $0.copy, version: $0.version) },
            issueLabels: p.issueLabels.map { .init(key: $0.key, display: $0.display) },
            couldNotVerifyReasons: .init(version: p.couldNotVerifyRegistryVersion, entries: p.couldNotVerifyReasons.map { .init(key: $0.key, display: $0.display) }),
            stageDisplays: p.stageDisplays.map { .init(key: $0.key, display: $0.display) },
            outcomeDisplays: outcomeDisplays.map { .init(key: $0.key, display: $0.display) },
            disclaimer: p.disclaimer
        )
    }

    private static func makePNG(seed: UInt8) throws -> Data {
        let width = 96, height = 72, bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                pixels[offset] = seed &+ UInt8(truncatingIfNeeded: x)
                pixels[offset + 1] = seed &+ UInt8(truncatingIfNeeded: y)
                pixels[offset + 2] = seed &+ UInt8(truncatingIfNeeded: x + y)
                pixels[offset + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: bytesPerRow, space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("png")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { throw KernelConformanceFixtureFailureV1.incompleteCoverage("png") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw KernelConformanceFixtureFailureV1.incompleteCoverage("png")
        }
        return data as Data
    }
}

private final class KernelConformanceBundleMarkerV1: NSObject {}

private extension Data {
    init?(hexV1 value: String) {
        guard value.count.isMultiple(of: 2), value.allSatisfy({ $0.isNumber || ("a"..."f").contains(String($0)) }) else { return nil }
        var result = Data(capacity: value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let end = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<end], radix: 16) else { return nil }
            result.append(byte)
            index = end
        }
        self = result
    }
}

/// Small, deterministic C41 fixtures shared by the legacy lifecycle tests.
/// The helper only constructs the canonical C41 contract objects; persistence
/// and coordinator behavior remain owned by their production adapters.
enum C41FunctionalRelationshipTestSupportV1 {
    struct Fixture {
        let workspaceID: WorkspaceID
        let packageRelease: PackageReleaseIdentityV1
        let sourceCatalog: AssetSemanticCatalogReleaseV1
        let targetCatalog: AssetSemanticCatalogReleaseV1
        let descriptor: FunctionalRelationshipTypeDescriptorV1
        let actor: LocalActorReferenceV1
        let relationshipID: UUID
        let sourceAssetID: UUID
        let targetAssetID: UUID
        let added: AssetFunctionalRelationshipEventV1
        let ended: AssetFunctionalRelationshipEventV1
        let superseded: AssetFunctionalRelationshipEventV1
    }

    static let fixedDate = Date(timeIntervalSince1970: 1_735_689_600.125)

    static func id(_ seed: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", seed))!
    }

    static func workspace(_ seed: Int = 41_000) -> WorkspaceID {
        WorkspaceID(rawValue: id(seed))
    }

    static func sourceRoot() -> URL {
        KernelConformanceFixtureHarnessV1.sourceRoot()
    }

    static func mutation(_ seed: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(seed))
    }

    static func makeFixture(
        seed: Int = 41_000,
        direction: FunctionalRelationshipDirectionV1 = .directed,
        symmetry: FunctionalRelationshipSymmetryV1 = .asymmetric,
        cyclePolicy: FunctionalRelationshipCyclePolicyV1 = .forbidden,
        sourceMinimum: Int = 0,
        targetMinimum: Int = 0,
        sourceMaximum: Int = 2,
        targetMaximum: Int = 2,
        minimumCardinalityBoundaries: [FunctionalRelationshipReadinessBoundaryV1] = [.readiness, .finalization]
    ) throws -> Fixture {
        let workspaceID = workspace(seed)
        let packageRelease = try PackageReleaseIdentityV1(
            packageID: "com.assetrounds.c41.fixture",
            schemaVersion: 1,
            contentVersion: 1
        )
        let sourceCapability = try AssetSemanticCapabilityIDV1("capability.control")
        let targetCapability = try AssetSemanticCapabilityIDV1("capability.inspect")
        let sourceCatalog = try makeCatalog(
            packageRelease: packageRelease,
            releaseID: id(seed + 1),
            semanticID: "asset.controller",
            capabilityIDs: [sourceCapability]
        )
        let targetCatalog = try makeCatalog(
            packageRelease: packageRelease,
            releaseID: id(seed + 2),
            semanticID: "asset.zone",
            capabilityIDs: [targetCapability]
        )
        let descriptor = try FunctionalRelationshipTypeDescriptorV1(
            descriptorReleaseID: id(seed + 3),
            workspaceID: workspaceID,
            packageRelease: packageRelease,
            semanticID: "relationship.controls",
            sourceCatalogRelease: sourceCatalog.reference,
            targetCatalogRelease: targetCatalog.reference,
            sourceSemanticIDs: ["asset.controller"],
            targetSemanticIDs: ["asset.zone"],
            requiredSourceCapabilityIDs: [sourceCapability],
            requiredTargetCapabilityIDs: [targetCapability],
            direction: direction,
            symmetry: symmetry,
            sourceCardinality: try FunctionalRelationshipCardinalityV1(
                minimum: sourceMinimum, maximum: sourceMaximum
            ),
            targetCardinality: try FunctionalRelationshipCardinalityV1(
                minimum: targetMinimum, maximum: targetMaximum
            ),
            selfEdgePolicy: .forbidden,
            cyclePolicy: cyclePolicy,
            maximumTraversalDepth: 8,
            maximumHardEdges: 16,
            sitePolicy: .sameSiteRequired,
            minimumCardinalityBoundaries: minimumCardinalityBoundaries,
            displayNameLocalizationKey: "functional_relationship.controls.name",
            descriptionLocalizationKey: "functional_relationship.controls.description",
            sourceRoleLocalizationKey: "functional_relationship.controls.source",
            targetRoleLocalizationKey: "functional_relationship.controls.target",
            releasedAt: fixedDate,
            mutationID: try mutation(seed + 4)
        )
        let actor = try LocalActorReferenceV1(
            actorReferenceID: id(seed + 5), workspaceID: workspaceID,
            displayName: "C41 fixture actor"
        )
        let relationshipID = id(seed + 6)
        let sourceAssetID = id(seed + 7)
        let targetAssetID = id(seed + 8)
        let added = try makeEvent(
            eventID: id(seed + 10), relationshipID: relationshipID,
            workspaceID: workspaceID, action: .added,
            sourceAssetID: sourceAssetID, targetAssetID: targetAssetID,
            descriptor: descriptor, actor: actor,
            predecessorEventID: nil, expectedRelationshipRevision: 0,
            revision: 1, mutationID: try mutation(seed + 11)
        )
        let ended = try makeEvent(
            eventID: id(seed + 13), relationshipID: relationshipID,
            workspaceID: workspaceID, action: .ended,
            sourceAssetID: sourceAssetID, targetAssetID: targetAssetID,
            descriptor: descriptor, actor: actor,
            predecessorEventID: added.eventID, expectedRelationshipRevision: 1,
            revision: 2, mutationID: try mutation(seed + 14),
            recordedAt: fixedDate.addingTimeInterval(2)
        )
        let superseded = try makeEvent(
            eventID: id(seed + 16), relationshipID: relationshipID,
            workspaceID: workspaceID, action: .superseded,
            sourceAssetID: sourceAssetID, targetAssetID: targetAssetID,
            descriptor: descriptor, actor: actor,
            predecessorEventID: added.eventID, expectedRelationshipRevision: 1,
            revision: 2, mutationID: try mutation(seed + 17),
            recordedAt: fixedDate.addingTimeInterval(2)
        )
        return Fixture(
            workspaceID: workspaceID, packageRelease: packageRelease,
            sourceCatalog: sourceCatalog, targetCatalog: targetCatalog,
            descriptor: descriptor, actor: actor, relationshipID: relationshipID,
            sourceAssetID: sourceAssetID, targetAssetID: targetAssetID,
            added: added, ended: ended, superseded: superseded
        )
    }

    static func makeCatalog(
        packageRelease: PackageReleaseIdentityV1,
        releaseID: UUID,
        semanticID: String,
        capabilityIDs: [AssetSemanticCapabilityIDV1]
    ) throws -> AssetSemanticCatalogReleaseV1 {
        try AssetSemanticCatalogReleaseV1(
            releaseID: releaseID,
            packageRelease: packageRelease,
            revision: 1,
            definitions: [try AssetKindDefinitionV1(
                semanticID: semanticID,
                displayNameLocalizationKey: "functional_relationship.\(semanticID).name",
                descriptionLocalizationKey: "functional_relationship.\(semanticID).description",
                capabilityIDs: capabilityIDs,
                compatibleWorkflowPackageReleases: [packageRelease],
                compatibilityPolicy: .sameSemanticIDSuccessor
            )],
            releasedAt: fixedDate
        )
    }

    static func makeEvent(
        eventID: UUID,
        relationshipID: UUID,
        workspaceID: WorkspaceID,
        action: AssetFunctionalRelationshipEventActionV1,
        sourceAssetID: UUID,
        targetAssetID: UUID,
        descriptor: FunctionalRelationshipTypeDescriptorV1,
        actor: LocalActorReferenceV1,
        predecessorEventID: UUID?,
        expectedRelationshipRevision: UInt64,
        revision: UInt64,
        mutationID: MutationIDV1,
        recordedAt: Date = fixedDate
    ) throws -> AssetFunctionalRelationshipEventV1 {
        try AssetFunctionalRelationshipEventV1(
            eventID: eventID, relationshipID: relationshipID,
            workspaceID: workspaceID, action: action,
            sourceAssetID: sourceAssetID, targetAssetID: targetAssetID,
            sourceAssetRevision: 1, targetAssetRevision: 1,
            descriptor: FunctionalRelationshipDescriptorReferenceV1(descriptor),
            effectiveAt: fixedDate, recordedAt: recordedAt, actor: actor,
            provenance: "C41_SYNTHETIC_FIXTURE",
            predecessorEventID: predecessorEventID,
            expectedRelationshipRevision: expectedRelationshipRevision,
            revision: revision, mutationID: mutationID
        )
    }

    static func makeCycleEvents(_ fixture: Fixture) throws -> [AssetFunctionalRelationshipEventV1] {
        let second = try makeEvent(
            eventID: id(42_101), relationshipID: id(42_102),
            workspaceID: fixture.workspaceID, action: .added,
            sourceAssetID: fixture.targetAssetID, targetAssetID: id(42_103),
            descriptor: fixture.descriptor, actor: fixture.actor,
            predecessorEventID: nil, expectedRelationshipRevision: 0,
            revision: 1, mutationID: mutation(42_104),
            recordedAt: fixedDate.addingTimeInterval(1)
        )
        let third = try makeEvent(
            eventID: id(42_106), relationshipID: id(42_107),
            workspaceID: fixture.workspaceID, action: .added,
            sourceAssetID: id(42_103), targetAssetID: fixture.sourceAssetID,
            descriptor: fixture.descriptor, actor: fixture.actor,
            predecessorEventID: nil, expectedRelationshipRevision: 0,
            revision: 1, mutationID: mutation(42_108),
            recordedAt: fixedDate.addingTimeInterval(1)
        )
        return [fixture.added, second, third]
    }
}

/// Deterministic C13 objects shared by legacy lifecycle tests.  The fixture
/// deliberately keeps all evidence synthetic and exercises both included and
/// excluded audience decisions without introducing a second writer or store.
enum C13EvidenceAssuranceTestSupportV1 {
    struct Fixture {
        let workspaceID: WorkspaceID
        let actor: LocalActorReferenceV1
        let routineVisibility: EvidenceVisibilityV1
        let internalOnlyVisibility: EvidenceVisibilityV1
        let restrictedVisibility: EvidenceVisibilityV1
        let highlyRestrictedVisibility: EvidenceVisibilityV1
        let customerLink: ClaimEvidenceLinkV1
        let internalOnlyCustomerLink: ClaimEvidenceLinkV1
        let restrictedExternalLink: ClaimEvidenceLinkV1
        let internalLink: ClaimEvidenceLinkV1
        let customerPreview: AssuranceProjectionPreviewV1
        let customerManifest: AssuranceManifestV1
        let customerAttestation: AttestationV1
    }

    static let fixedDate = Date(timeIntervalSince1970: 1_735_690_600.125)
    static let evidenceSHA256 = String(repeating: "a", count: 64)
    static let projectionVersion = "C13_EVIDENCE_ASSURANCE_V1"

    static func id(_ seed: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", seed))!
    }

    static func workspace(_ seed: Int = 51_000) -> WorkspaceID {
        WorkspaceID(rawValue: id(seed))
    }

    static func mutation(_ seed: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(seed))
    }

    static func makeVisibility(
        seed: Int,
        workspaceID: WorkspaceID,
        sensitivity: EvidenceSensitivityV1,
        allowedAudiences: [EvidenceAudienceV1],
        supersedesVisibilityID: UUID? = nil,
        revision: UInt64 = 1
    ) throws -> EvidenceVisibilityV1 {
        try EvidenceVisibilityV1(
            visibilityID: id(seed),
            workspaceID: workspaceID,
            sensitivity: sensitivity,
            allowedAudiences: allowedAudiences,
            effectiveAt: fixedDate,
            supersedesVisibilityID: supersedesVisibilityID,
            revision: revision,
            mutationID: try mutation(seed + 100)
        )
    }

    static func makeLink(
        seed: Int,
        workspaceID: WorkspaceID,
        visibility: EvidenceVisibilityV1,
        audience: EvidenceAudienceV1,
        evidenceID: String,
        claimID: String = "claim.visible-condition",
        limitation: EvidenceLimitationV1? = nil,
        limitationNote: String? = nil,
        supersedesLinkID: UUID? = nil,
        revision: UInt64 = 1
    ) throws -> ClaimEvidenceLinkV1 {
        try ClaimEvidenceLinkV1(
            linkID: id(seed),
            workspaceID: workspaceID,
            claimID: claimID,
            criterionID: "criterion.visible-condition",
            evidenceID: evidenceID,
            evidenceRevision: 1,
            evidenceSHA256: evidenceSHA256,
            visibility: visibility,
            audience: audience,
            limitation: limitation,
            limitationNote: limitationNote,
            supersedesLinkID: supersedesLinkID,
            revision: revision,
            mutationID: try mutation(seed + 100)
        )
    }

    static func makeFixture(seed: Int = 51_000) throws -> Fixture {
        let workspaceID = workspace(seed)
        let actor = try LocalActorReferenceV1(
            actorReferenceID: id(seed + 1), workspaceID: workspaceID,
            displayName: "C13 local reviewer"
        )
        let routineVisibility = try makeVisibility(
            seed: seed + 10, workspaceID: workspaceID, sensitivity: .routine,
            allowedAudiences: [.internalReview, .customerReport, .externalCollaborator]
        )
        let internalOnlyVisibility = try makeVisibility(
            seed: seed + 20, workspaceID: workspaceID, sensitivity: .routine,
            allowedAudiences: [.internalReview]
        )
        let restrictedVisibility = try makeVisibility(
            seed: seed + 30, workspaceID: workspaceID, sensitivity: .restricted,
            allowedAudiences: [.internalReview, .customerReport]
        )
        let highlyRestrictedVisibility = try makeVisibility(
            seed: seed + 40, workspaceID: workspaceID, sensitivity: .highlyRestricted,
            allowedAudiences: [.internalReview]
        )
        let customerLink = try makeLink(
            seed: seed + 50, workspaceID: workspaceID, visibility: routineVisibility,
            audience: .customerReport, evidenceID: "evidence.customer-safe"
        )
        let internalOnlyCustomerLink = try makeLink(
            seed: seed + 51, workspaceID: workspaceID, visibility: internalOnlyVisibility,
            audience: .customerReport, evidenceID: "evidence.internal-canary",
            limitationNote: "Internal-only evidence omitted from this customer projection."
        )
        let restrictedExternalLink = try makeLink(
            seed: seed + 52, workspaceID: workspaceID, visibility: restrictedVisibility,
            audience: .externalCollaborator, evidenceID: "evidence.restricted-canary",
            limitationNote: "Restricted evidence omitted from this collaborator projection."
        )
        let internalLink = try makeLink(
            seed: seed + 53, workspaceID: workspaceID, visibility: highlyRestrictedVisibility,
            audience: .internalReview, evidenceID: "evidence.internal-review"
        )
        let customerPreview = try AssuranceProjectionPreviewV1(
            previewID: id(seed + 60), workspaceID: workspaceID,
            audience: .customerReport, snapshotSHA256: evidenceSHA256,
            projectionVersion: projectionVersion,
            links: [customerLink, internalOnlyCustomerLink],
            createdAt: fixedDate.addingTimeInterval(1)
        )
        let customerManifest = try AssuranceManifestV1(
            manifestID: id(seed + 61), preview: customerPreview,
            recordedAt: fixedDate.addingTimeInterval(2), mutationID: try mutation(seed + 62)
        )
        let scope = try AttestationScopeV1(
            kind: .assuranceManifest, scopeID: customerManifest.manifestID,
            scopeRevision: customerManifest.revision
        )
        let customerAttestation = try AttestationV1(
            attestationID: id(seed + 70), workspaceID: workspaceID,
            purpose: .acknowledgeReport, scope: scope, manifest: customerManifest,
            declaredActor: actor, method: .explicitLocalConfirmation,
            occurredAt: fixedDate.addingTimeInterval(3),
            recordedAt: fixedDate.addingTimeInterval(3),
            mutationID: try mutation(seed + 71)
        )
        return Fixture(
            workspaceID: workspaceID, actor: actor,
            routineVisibility: routineVisibility,
            internalOnlyVisibility: internalOnlyVisibility,
            restrictedVisibility: restrictedVisibility,
            highlyRestrictedVisibility: highlyRestrictedVisibility,
            customerLink: customerLink,
            internalOnlyCustomerLink: internalOnlyCustomerLink,
            restrictedExternalLink: restrictedExternalLink,
            internalLink: internalLink,
            customerPreview: customerPreview,
            customerManifest: customerManifest,
            customerAttestation: customerAttestation
        )
    }

    static func corpusURL() -> URL {
        KernelConformanceFixtureHarnessV1.sourceRoot().appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V21/EvidenceAssurance/V21P03C13EvidenceAssuranceCorpusV1.json"
        )
    }
}

/// Deterministic C14 review/corrective-action values shared by the C14 lane
/// and its boundary assertions.  Every reference is local to the synthetic
/// workspace; no account, remote identity, or delivery claim is represented.
enum C14InspectionReviewTestSupportV1 {
    struct Fixture {
        let workspaceID: WorkspaceID
        let otherWorkspaceID: WorkspaceID
        let reviewID: UUID
        let actionID: UUID
        let subject: InspectionReviewSubjectReferenceV1
        let otherSubject: InspectionReviewSubjectReferenceV1
        let actor: LocalActorReferenceV1
        let reviewer: ActorSnapshotV1
        let recorder: ActorSnapshotV1
        let assignee: LocalActorReferenceV1
        let verifier: ActorSnapshotV1
        let transitions: [InspectionReviewTransitionV1]
        let supersedingTransition: InspectionReviewTransitionV1
        let changesRequestedDisposition: ReviewDispositionV1
        let acceptedDisposition: ReviewDispositionV1
        let changeRequest: ChangeRequestV1
        let resolvedChangeRequest: ChangeRequestV1
        let policy: CorrectiveActionPolicyV1
        let supersedingPolicy: CorrectiveActionPolicyV1
        let noDuePolicy: CorrectiveActionPolicyV1
        let due: CorrectiveActionDueCalculationV1
        let noDue: CorrectiveActionDueCalculationV1
        let closureEvidence: [ReviewEvidenceReferenceV1]
        let actions: [CorrectiveActionEventV1]
        let noDueOpenAction: CorrectiveActionEventV1
        let noDueClosedAction: CorrectiveActionEventV1
    }

    static let fixedDate = Date(timeIntervalSince1970: 1_740_000_000.125)
    static let digest = String(repeating: "c", count: 64)

    static func id(_ seed: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", seed))!
    }

    static func workspace(_ seed: Int = 140_000) -> WorkspaceID {
        WorkspaceID(rawValue: id(seed))
    }

    static func mutation(_ seed: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(seed))
    }

    static func actorReference(
        seed: Int,
        workspaceID: WorkspaceID,
        partyID: UUID? = nil,
        name: String
    ) throws -> LocalActorReferenceV1 {
        try LocalActorReferenceV1(
            actorReferenceID: id(seed), workspaceID: workspaceID,
            partyID: partyID, displayName: name
        )
    }

    static func actorSnapshot(
        seed: Int,
        workspaceID: WorkspaceID,
        actor: LocalActorReferenceV1,
        responsibility: ResponsibilityKindV1,
        capturedAt: Date = fixedDate
    ) throws -> ActorSnapshotV1 {
        try ActorSnapshotV1(
            snapshotID: id(seed), workspaceID: workspaceID, actor: actor,
            responsibility: responsibility, displayNameAtTime: actor.displayName,
            capturedAt: capturedAt
        )
    }

    static func makeSubject(
        seed: Int,
        workspaceID: WorkspaceID,
        kind: InspectionReviewSubjectKindV1 = .completedActivitySnapshot,
        revision: UInt64 = 1
    ) throws -> InspectionReviewSubjectReferenceV1 {
        try InspectionReviewSubjectReferenceV1(
            workspaceID: workspaceID, kind: kind,
            subjectID: "c14-subject-\(seed)", subjectRevision: revision,
            subjectSHA256: digest
        )
    }

    static func changeItem(
        kind: ChangeRequestItemKindV1 = .finding,
        itemID: String = "c14-finding-001",
        revision: UInt64 = 1
    ) throws -> ChangeRequestItemReferenceV1 {
        try ChangeRequestItemReferenceV1(
            kind: kind, itemID: itemID, itemRevision: revision,
            itemSHA256: digest
        )
    }

    static func makeTransition(
        seed: Int,
        reviewID: UUID,
        workspaceID: WorkspaceID,
        subject: InspectionReviewSubjectReferenceV1,
        from: InspectionReviewStateV1,
        to: InspectionReviewStateV1,
        actor: ActorSnapshotV1,
        revision: UInt64,
        mutationSeed: Int,
        predecessor: UUID? = nil,
        dispositionID: UUID? = nil,
        changeRequestIDs: [UUID] = [],
        successorReviewID: UUID? = nil,
        successorSubject: InspectionReviewSubjectReferenceV1? = nil
    ) throws -> InspectionReviewTransitionV1 {
        let timestamp = fixedDate.addingTimeInterval(TimeInterval(revision))
        return try InspectionReviewTransitionV1(
            transitionID: id(seed), reviewID: reviewID, workspaceID: workspaceID,
            subject: subject, fromState: from, toState: to, actor: actor,
            reason: "C14 synthetic transition \(revision)",
            dispositionID: dispositionID, changeRequestIDs: changeRequestIDs,
            successorReviewID: successorReviewID, successorSubject: successorSubject,
            occurredAt: timestamp, recordedAt: timestamp,
            predecessorTransitionID: predecessor, revision: revision,
            mutationID: try mutation(mutationSeed)
        )
    }

    static func makePolicy(
        seed: Int,
        workspaceID: WorkspaceID,
        assignmentRule: CorrectiveActionAssignmentRuleV1 = .required,
        verifierRule: CorrectiveActionVerifierRuleV1 = .differentActorAndPartyRequired,
        effectiveAt: Date = fixedDate,
        supersedesReleaseID: UUID? = nil,
        revision: UInt64 = 1,
        noDue: Bool = false
    ) throws -> CorrectiveActionPolicyV1 {
        let rules: [CorrectiveActionPriorityRuleV1]
        if noDue {
            rules = [try CorrectiveActionPriorityRuleV1(
                priority: .low,
                dueRule: try CorrectiveActionDueRuleV1(kind: .noDueDate)
            )]
        } else {
            rules = [
                try CorrectiveActionPriorityRuleV1(
                    priority: .urgent,
                    dueRule: try CorrectiveActionDueRuleV1(kind: .elapsedSeconds, amount: 3_600),
                    graceSeconds: 600
                ),
                try CorrectiveActionPriorityRuleV1(
                    priority: .high,
                    dueRule: try CorrectiveActionDueRuleV1(
                        kind: .calendarDaysAtLocalTime, amount: 1, localHour: 9, localMinute: 0
                    ), graceSeconds: 900
                ),
                try CorrectiveActionPriorityRuleV1(
                    priority: .normal,
                    dueRule: try CorrectiveActionDueRuleV1(kind: .elapsedSeconds, amount: 86_400),
                    graceSeconds: 1_800
                ),
                try CorrectiveActionPriorityRuleV1(
                    priority: .low,
                    dueRule: try CorrectiveActionDueRuleV1(kind: .noDueDate)
                )
            ]
        }
        let evidence: [CorrectiveClosureEvidenceRequirementV1] = noDue ? [] : [
            try CorrectiveClosureEvidenceRequirementV1(
                requirementID: "c14-evidence-activity",
                kind: .completedActivitySnapshot, minimumCount: 1
            ),
            try CorrectiveClosureEvidenceRequirementV1(
                requirementID: "c14-evidence-recheck",
                kind: .verifiedRecheck, minimumCount: 1
            )
        ]
        return try CorrectiveActionPolicyV1(
            releaseID: id(seed), policyID: id(seed + 1), workspaceID: workspaceID,
            priorityRules: rules, assignmentRule: assignmentRule,
            closureEvidenceRequirements: evidence, verifierRule: verifierRule,
            reopenTriggers: noDue ? [.manualRecordedReason] : [
                .failedVerifiedRecheck, .newEvidenceDigest, .subjectAmended,
                .manualRecordedReason
            ], effectiveAt: effectiveAt, supersedesReleaseID: supersedesReleaseID,
            revision: revision, mutationID: try mutation(seed + 2)
        )
    }

    static func makeAction(
        seed: Int,
        actionID: UUID,
        workspaceID: WorkspaceID,
        source: ChangeRequestItemReferenceV1,
        policy: CorrectiveActionPolicyV1,
        priority: CorrectiveActionPriorityV1,
        state: CorrectiveActionStateV1,
        recorder: ActorSnapshotV1,
        assignee: LocalActorReferenceV1?,
        due: CorrectiveActionDueCalculationV1,
        closureEvidence: [ReviewEvidenceReferenceV1] = [],
        verifier: ActorSnapshotV1? = nil,
        reopenTrigger: CorrectiveActionReopenTriggerV1? = nil,
        predecessor: UUID? = nil,
        revision: UInt64
    ) throws -> CorrectiveActionEventV1 {
        let timestamp = fixedDate.addingTimeInterval(100 + TimeInterval(revision))
        return try CorrectiveActionEventV1(
            eventID: id(seed), actionID: actionID, workspaceID: workspaceID,
            source: source, policy: try CorrectiveActionPolicyReferenceV1(policy),
            priority: priority, state: state, assignee: assignee, recorder: recorder,
            due: due, closureEvidence: closureEvidence, verifier: verifier,
            reopenTrigger: reopenTrigger, reason: "C14 synthetic action \(revision)",
            occurredAt: timestamp, recordedAt: timestamp,
            predecessorEventID: predecessor, revision: revision,
            mutationID: try mutation(seed + 50)
        )
    }

    static func makeFixture(seed: Int = 140_000) throws -> Fixture {
        let workspaceID = workspace(seed)
        let otherWorkspaceID = workspace(seed + 900)
        let reviewID = id(seed + 1)
        let actionID = id(seed + 2)
        let subject = try makeSubject(seed: seed + 3, workspaceID: workspaceID)
        let otherSubject = try makeSubject(seed: seed + 4, workspaceID: otherWorkspaceID)
        let partyID = id(seed + 10)
        let assigneePartyID = id(seed + 11)
        let verifierPartyID = id(seed + 12)
        let actor = try actorReference(
            seed: seed + 20, workspaceID: workspaceID, partyID: partyID,
            name: "C14 local recorder"
        )
        let reviewerActor = try actorReference(
            seed: seed + 21, workspaceID: workspaceID, partyID: partyID,
            name: "C14 local reviewer"
        )
        let assignee = try actorReference(
            seed: seed + 22, workspaceID: workspaceID, partyID: assigneePartyID,
            name: "C14 local assignee"
        )
        let verifierActor = try actorReference(
            seed: seed + 23, workspaceID: workspaceID, partyID: verifierPartyID,
            name: "C14 local verifier"
        )
        let recorder = try actorSnapshot(
            seed: seed + 30, workspaceID: workspaceID, actor: actor,
            responsibility: .recordedBy
        )
        let reviewer = try actorSnapshot(
            seed: seed + 31, workspaceID: workspaceID, actor: reviewerActor,
            responsibility: .reviewedBy, capturedAt: fixedDate.addingTimeInterval(1)
        )
        let verifier = try actorSnapshot(
            seed: seed + 32, workspaceID: workspaceID, actor: verifierActor,
            responsibility: .verifiedBy, capturedAt: fixedDate.addingTimeInterval(2)
        )

        let item = try changeItem()
        let requestID = id(seed + 40)
        let requestRevisionID = id(seed + 41)
        let requirementChange = try ChangeRequestRequirementV1(
            requirementID: "c14-requirement-change",
            kind: .recordedChange, description: "Record the requested corrective change."
        )
        let requirementEvidence = try ChangeRequestRequirementV1(
            requirementID: "c14-requirement-evidence",
            kind: .additionalEvidence, description: "Attach one local evidence reference."
        )
        let changesMutation = try mutation(seed + 51)
        let changeRequest = try ChangeRequestV1(
            requestRevisionID: requestRevisionID, requestID: requestID,
            reviewID: reviewID, workspaceID: workspaceID, reviewRevision: 3,
            item: item, reason: "C14 synthetic missing evidence reason",
            requirements: [requirementChange, requirementEvidence], requester: reviewer,
            state: .open, recordedAt: fixedDate.addingTimeInterval(3), revision: 1,
            mutationID: changesMutation
        )
        let requestEvidence = try ReviewEvidenceReferenceV1(
            kind: .requirementEvaluation, referenceID: "c14-requirement-evaluation",
            revision: 1, sha256: digest
        )
        let resolution = try ChangeRequestResolutionV1(
            kind: .fulfilled, resolver: reviewer, evidence: [requestEvidence],
            reason: "C14 synthetic requirements fulfilled.",
            resolvedAt: fixedDate.addingTimeInterval(5)
        )
        let resolvedChangeRequest = try ChangeRequestV1(
            requestRevisionID: id(seed + 43), requestID: requestID,
            reviewID: reviewID, workspaceID: workspaceID, reviewRevision: 3,
            item: item, reason: changeRequest.reason, requirements: changeRequest.requirements,
            requester: reviewer, state: .resolved, resolution: resolution,
            recordedAt: fixedDate.addingTimeInterval(5),
            supersedesRequestRevisionID: requestRevisionID, revision: 2,
            mutationID: try mutation(seed + 44)
        )

        let changesDispositionID = id(seed + 50)
        let changesDisposition = try ReviewDispositionV1(
            dispositionID: changesDispositionID, reviewID: reviewID,
            workspaceID: workspaceID, subject: subject, reviewRevision: 3,
            kind: .changesRequested, reviewer: reviewer,
            reason: "C14 synthetic change request disposition.",
            changeRequestIDs: [requestID], recordedAt: fixedDate.addingTimeInterval(3),
            mutationID: changesMutation
        )
        let acceptedDispositionID = id(seed + 52)
        let acceptedMutation = try mutation(seed + 53)
        let acceptedDisposition = try ReviewDispositionV1(
            dispositionID: acceptedDispositionID, reviewID: reviewID,
            workspaceID: workspaceID, subject: subject, reviewRevision: 5,
            kind: .accepted, reviewer: reviewer,
            reason: "C14 synthetic review accepted.",
            recordedAt: fixedDate.addingTimeInterval(5), mutationID: acceptedMutation
        )

        let first = try makeTransition(
            seed: seed + 60, reviewID: reviewID, workspaceID: workspaceID,
            subject: subject, from: .draft, to: .fieldComplete, actor: recorder,
            revision: 1, mutationSeed: seed + 61
        )
        let second = try makeTransition(
            seed: seed + 62, reviewID: reviewID, workspaceID: workspaceID,
            subject: subject, from: .fieldComplete, to: .readyForReview, actor: recorder,
            revision: 2, mutationSeed: seed + 63, predecessor: first.transitionID
        )
        let third = try makeTransition(
            seed: seed + 64, reviewID: reviewID, workspaceID: workspaceID,
            subject: subject, from: .readyForReview, to: .changesRequested,
            actor: reviewer, revision: 3, mutationSeed: seed + 51,
            predecessor: second.transitionID, dispositionID: changesDispositionID,
            changeRequestIDs: [requestID]
        )
        let fourth = try makeTransition(
            seed: seed + 65, reviewID: reviewID, workspaceID: workspaceID,
            subject: subject, from: .changesRequested, to: .readyForReview,
            actor: recorder, revision: 4, mutationSeed: seed + 66,
            predecessor: third.transitionID
        )
        let fifth = try makeTransition(
            seed: seed + 67, reviewID: reviewID, workspaceID: workspaceID,
            subject: subject, from: .readyForReview, to: .accepted, actor: reviewer,
            revision: 5, mutationSeed: seed + 53, predecessor: fourth.transitionID,
            dispositionID: acceptedDispositionID
        )
        let sixth = try makeTransition(
            seed: seed + 68, reviewID: reviewID, workspaceID: workspaceID,
            subject: subject, from: .accepted, to: .finalized, actor: recorder,
            revision: 6, mutationSeed: seed + 69, predecessor: fifth.transitionID
        )
        let seventh = try makeTransition(
            seed: seed + 70, reviewID: reviewID, workspaceID: workspaceID,
            subject: subject, from: .finalized, to: .amended, actor: recorder,
            revision: 7, mutationSeed: seed + 71, predecessor: sixth.transitionID
        )
        let successorReviewID = id(seed + 72)
        let successorSubject = try makeSubject(
            seed: seed + 73, workspaceID: workspaceID, revision: 2
        )
        let supersedingTransition = try makeTransition(
            seed: seed + 74, reviewID: reviewID, workspaceID: workspaceID,
            subject: subject, from: .amended, to: .superseded, actor: recorder,
            revision: 8, mutationSeed: seed + 75, predecessor: seventh.transitionID,
            successorReviewID: successorReviewID, successorSubject: successorSubject
        )

        let policy = try makePolicy(seed: seed + 80, workspaceID: workspaceID)
        let supersedingPolicy = try makePolicy(
            seed: seed + 83, workspaceID: workspaceID,
            effectiveAt: fixedDate.addingTimeInterval(10),
            supersedesReleaseID: policy.releaseID, revision: 2
        )
        let noDuePolicy = try makePolicy(
            seed: seed + 86, workspaceID: workspaceID,
            assignmentRule: .optional, verifierRule: .notRequired, noDue: true
        )
        let due = try CorrectiveActionDueCalculatorV1.calculate(
            policy: policy, priority: .urgent,
            openedAt: fixedDate.addingTimeInterval(101), timeZoneIdentifier: nil
        )
        let noDue = try CorrectiveActionDueCalculatorV1.calculate(
            policy: noDuePolicy, priority: .low,
            openedAt: fixedDate.addingTimeInterval(101), timeZoneIdentifier: nil
        )
        let activityEvidence = try ReviewEvidenceReferenceV1(
            kind: .completedActivitySnapshot, referenceID: "c14-activity-result",
            revision: 1, sha256: digest
        )
        let recheckEvidence = try ReviewEvidenceReferenceV1(
            kind: .verifiedRecheck, referenceID: "c14-verified-recheck",
            revision: 1, sha256: digest
        )
        let closureEvidence = [activityEvidence, recheckEvidence]
        let actionOpen = try makeAction(
            seed: seed + 100, actionID: actionID, workspaceID: workspaceID,
            source: item, policy: policy, priority: .urgent, state: .open,
            recorder: recorder, assignee: assignee, due: due, revision: 1
        )
        let actionInProgress = try makeAction(
            seed: seed + 101, actionID: actionID, workspaceID: workspaceID,
            source: item, policy: policy, priority: .urgent, state: .inProgress,
            recorder: recorder, assignee: assignee, due: due,
            predecessor: actionOpen.eventID, revision: 2
        )
        let actionAwaiting = try makeAction(
            seed: seed + 102, actionID: actionID, workspaceID: workspaceID,
            source: item, policy: policy, priority: .urgent,
            state: .awaitingVerification, recorder: recorder, assignee: assignee,
            due: due, predecessor: actionInProgress.eventID, revision: 3
        )
        let actionClosed = try makeAction(
            seed: seed + 103, actionID: actionID, workspaceID: workspaceID,
            source: item, policy: policy, priority: .urgent, state: .closed,
            recorder: recorder, assignee: assignee, due: due,
            closureEvidence: closureEvidence, verifier: verifier,
            predecessor: actionAwaiting.eventID, revision: 4
        )
        let actionReopened = try makeAction(
            seed: seed + 104, actionID: actionID, workspaceID: workspaceID,
            source: item, policy: policy, priority: .urgent, state: .reopened,
            recorder: recorder, assignee: assignee, due: due,
            reopenTrigger: .failedVerifiedRecheck,
            predecessor: actionClosed.eventID, revision: 5
        )
        let actionSuperseded = try makeAction(
            seed: seed + 105, actionID: actionID, workspaceID: workspaceID,
            source: item, policy: policy, priority: .urgent, state: .superseded,
            recorder: recorder, assignee: assignee, due: due,
            predecessor: actionReopened.eventID, revision: 6
        )
        let noDueItem = try changeItem(kind: .criterion, itemID: "c14-no-due-criterion")
        let noDueOpenAction = try makeAction(
            seed: seed + 110, actionID: id(seed + 111), workspaceID: workspaceID,
            source: noDueItem, policy: noDuePolicy, priority: .low, state: .open,
            recorder: recorder, assignee: nil, due: noDue, revision: 1
        )
        let noDueClosedAction = try makeAction(
            seed: seed + 112, actionID: noDueOpenAction.actionID,
            workspaceID: workspaceID, source: noDueItem, policy: noDuePolicy,
            priority: .low, state: .closed, recorder: recorder, assignee: nil,
            due: noDue, predecessor: noDueOpenAction.eventID, revision: 2
        )
        return Fixture(
            workspaceID: workspaceID, otherWorkspaceID: otherWorkspaceID,
            reviewID: reviewID, actionID: actionID, subject: subject,
            otherSubject: otherSubject, actor: actor, reviewer: reviewer,
            recorder: recorder, assignee: assignee, verifier: verifier,
            transitions: [first, second, third, fourth, fifth, sixth, seventh],
            supersedingTransition: supersedingTransition,
            changesRequestedDisposition: changesDisposition,
            acceptedDisposition: acceptedDisposition,
            changeRequest: changeRequest, resolvedChangeRequest: resolvedChangeRequest,
            policy: policy, supersedingPolicy: supersedingPolicy, noDuePolicy: noDuePolicy,
            due: due, noDue: noDue, closureEvidence: closureEvidence,
            actions: [actionOpen, actionInProgress, actionAwaiting, actionClosed, actionReopened, actionSuperseded],
            noDueOpenAction: noDueOpenAction, noDueClosedAction: noDueClosedAction
        )
    }

    static func corpusURL() -> URL {
        KernelConformanceFixtureHarnessV1.sourceRoot().appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V21/ReviewAndCorrectiveAction/V21P03C14ReviewAndCorrectiveActionCorpusV1.json"
        )
    }
}

enum C15WorkPacketManifestTestSupportV1 {
    struct Fixture {
        let workspaceID: WorkspaceID
        let otherWorkspaceID: WorkspaceID
        let manifest: WorkPacketManifestV1
        let alternateManifest: WorkPacketManifestV1
        let manifestReference: WorkPacketManifestReferenceV1
        let item: WorkPacketItemV1
        let secondItem: WorkPacketItemV1
        let itemReference: WorkPacketItemReferenceV1
        let creator: ActorSnapshotV1
        let holder: ActorSnapshotV1
        let successorHolder: ActorSnapshotV1
        let claim: WorkItemClaimV1
        let successorClaim: WorkItemClaimV1
        let competingClaim: WorkItemClaimV1
        let lease: WorkLeaseV1
        let successorLease: WorkLeaseV1
        let result: WorkPacketResultLinkV1
        let staleResult: WorkPacketResultLinkV1
        let divergentResult: WorkPacketResultLinkV1
        let alternateResult: WorkPacketResultLinkV1
        let completedRelease: WorkReleaseV1
        let handoffRelease: WorkReleaseV1
        let expiredRelease: WorkReleaseV1
        let divergentRelease: WorkReleaseV1
        let handoff: WorkHandoffV1
        let packageRelease: PackageReleaseIdentityV1
        let policyReference: WorkPacketPolicyReferenceV1
        let evidenceRequirement: WorkPacketEvidenceRequirementV1
    }

    static let fixedDate = C14InspectionReviewTestSupportV1.fixedDate.addingTimeInterval(10_000)
    static let digest = String(repeating: "d", count: 64)
    static let alternateDigest = String(repeating: "e", count: 64)

    static func id(_ seed: Int) -> UUID {
        C14InspectionReviewTestSupportV1.id(seed)
    }

    static func workspace(_ seed: Int) -> WorkspaceID {
        C14InspectionReviewTestSupportV1.workspace(seed)
    }

    static func mutation(_ seed: Int) throws -> MutationIDV1 {
        try C14InspectionReviewTestSupportV1.mutation(seed)
    }

    static func makeFixture(seed: Int = 150_000) throws -> Fixture {
        let workspaceID = workspace(seed)
        let otherWorkspaceID = workspace(seed + 900)
        let base = fixedDate.addingTimeInterval(Double(seed % 100))
        let creatorReference = try C14InspectionReviewTestSupportV1.actorReference(
            seed: seed + 1, workspaceID: workspaceID, name: "C15 recorder"
        )
        let holderReference = try C14InspectionReviewTestSupportV1.actorReference(
            seed: seed + 2, workspaceID: workspaceID, name: "C15 holder"
        )
        let successorReference = try C14InspectionReviewTestSupportV1.actorReference(
            seed: seed + 3, workspaceID: workspaceID, name: "C15 successor"
        )
        let creator = try C14InspectionReviewTestSupportV1.actorSnapshot(
            seed: seed + 4, workspaceID: workspaceID, actor: creatorReference,
            responsibility: .recordedBy, capturedAt: base
        )
        let holder = try C14InspectionReviewTestSupportV1.actorSnapshot(
            seed: seed + 5, workspaceID: workspaceID, actor: holderReference,
            responsibility: .assignedTo, capturedAt: base.addingTimeInterval(1)
        )
        let successorHolder = try C14InspectionReviewTestSupportV1.actorSnapshot(
            seed: seed + 6, workspaceID: workspaceID, actor: successorReference,
            responsibility: .assignedTo, capturedAt: base.addingTimeInterval(2)
        )
        let packageRelease = try PackageReleaseIdentityV1(
            packageID: "com.assetrounds.c15", schemaVersion: 1, contentVersion: 1
        )
        let policyReference = try WorkPacketPolicyReferenceV1(
            policyID: "c15-policy", policyRevision: 1, policySHA256: digest
        )
        let evidenceRequirement = try WorkPacketEvidenceRequirementV1(
            requirementID: "c15-result-evidence",
            evidenceKind: .completedActivitySnapshot,
            minimumCount: 1
        )
        let item = try WorkPacketItemV1(
            itemID: "c15-inspection", kind: .inspection, expectedRevision: 1,
            itemSHA256: digest, policyReferences: [policyReference],
            evidenceRequirements: [evidenceRequirement]
        )
        let secondItem = try WorkPacketItemV1(
            itemID: "c15-recheck", kind: .operationalRecheck, expectedRevision: 1,
            itemSHA256: alternateDigest
        )
        let correctiveItem = try WorkPacketItemV1(
            itemID: "c15-corrective", kind: .correctiveAction, expectedRevision: 1,
            itemSHA256: digest
        )
        let changeRequestItem = try WorkPacketItemV1(
            itemID: "c15-change-request", kind: .reviewChangeRequest, expectedRevision: 1,
            itemSHA256: alternateDigest
        )
        let manifest = try WorkPacketManifestV1(
            manifestID: id(seed + 10), packetID: id(seed + 11), packetVersion: 1,
            workspaceID: workspaceID, items: [secondItem, item, correctiveItem, changeRequestItem],
            packageReleases: [packageRelease], creationBasis: .explicitLocalSelection,
            creator: creator, createdAt: base.addingTimeInterval(3),
            mutationID: try mutation(seed + 12)
        )
        let alternateManifest = try WorkPacketManifestV1(
            manifestID: id(seed + 10), packetID: id(seed + 11), packetVersion: 2,
            workspaceID: workspaceID, items: [item, secondItem, correctiveItem, changeRequestItem],
            packageReleases: [packageRelease], creationBasis: .deterministicDueProjection,
            creator: creator, createdAt: base.addingTimeInterval(4),
            mutationID: try mutation(seed + 13)
        )
        let manifestReference = try WorkPacketManifestReferenceV1(manifest)
        let itemReference = try WorkPacketItemReferenceV1(manifest: manifest, item: item)
        let claim = try WorkItemClaimV1(
            claimID: id(seed + 20), workspaceID: workspaceID, manifest: manifestReference,
            item: itemReference, holder: holder, claimSequence: 1,
            claimedAt: base.addingTimeInterval(5), mutationID: try mutation(seed + 21)
        )
        let successorClaim = try WorkItemClaimV1(
            claimID: id(seed + 22), workspaceID: workspaceID, manifest: manifestReference,
            item: itemReference, holder: successorHolder, claimSequence: 2,
            claimedAt: base.addingTimeInterval(6), supersedesClaimID: claim.claimID,
            revision: 2, mutationID: try mutation(seed + 23)
        )
        let competingClaim = try WorkItemClaimV1(
            claimID: id(seed + 24), workspaceID: workspaceID, manifest: manifestReference,
            item: itemReference, holder: successorHolder, claimSequence: 1,
            claimedAt: base.addingTimeInterval(7), mutationID: try mutation(seed + 25)
        )
        let lease = try WorkLeaseV1(
            leaseID: id(seed + 30), workspaceID: workspaceID, claimID: claim.claimID,
            item: itemReference, holder: holder, leaseSequence: 1,
            startsAt: base.addingTimeInterval(8), expiresAt: base.addingTimeInterval(3_608),
            mutationID: try mutation(seed + 31)
        )
        let successorLease = try WorkLeaseV1(
            leaseID: id(seed + 32), workspaceID: workspaceID, claimID: claim.claimID,
            item: itemReference, holder: holder, leaseSequence: 2,
            startsAt: base.addingTimeInterval(9), expiresAt: base.addingTimeInterval(3_609),
            supersedesLeaseID: lease.leaseID, revision: 2,
            mutationID: try mutation(seed + 33)
        )
        let evidence = try ReviewEvidenceReferenceV1(
            kind: .completedActivitySnapshot, referenceID: "c15-result-evidence",
            revision: 1, sha256: digest
        )
        let result = try WorkPacketResultLinkV1(
            resultID: id(seed + 40), resultMutationID: try mutation(seed + 41),
            itemExpectedRevision: 1, resultRevision: 1, resultSHA256: digest,
            evidence: [evidence]
        )
        let staleResult = try WorkPacketResultLinkV1(
            resultID: id(seed + 42), resultMutationID: try mutation(seed + 43),
            itemExpectedRevision: 2, resultRevision: 1, resultSHA256: digest,
            evidence: [evidence]
        )
        let divergentResult = try WorkPacketResultLinkV1(
            resultID: result.resultID, resultMutationID: try mutation(seed + 44),
            itemExpectedRevision: 1, resultRevision: 1, resultSHA256: alternateDigest,
            evidence: [evidence]
        )
        let alternateResult = try WorkPacketResultLinkV1(
            resultID: id(seed + 45), resultMutationID: try mutation(seed + 46),
            itemExpectedRevision: 1, resultRevision: 1, resultSHA256: alternateDigest,
            evidence: [evidence]
        )
        let completedRelease = try WorkReleaseV1(
            releaseID: id(seed + 50), workspaceID: workspaceID, claimID: claim.claimID,
            leaseID: lease.leaseID, item: itemReference, holder: holder, reason: .completed,
            resultLinks: [result], releasedAt: base.addingTimeInterval(100),
            mutationID: try mutation(seed + 51)
        )
        let handoffRelease = try WorkReleaseV1(
            releaseID: id(seed + 52), workspaceID: workspaceID, claimID: claim.claimID,
            leaseID: lease.leaseID, item: itemReference, holder: holder, reason: .handoff,
            resultLinks: [alternateResult], releasedAt: base.addingTimeInterval(120),
            mutationID: try mutation(seed + 53)
        )
        let expiredRelease = try WorkReleaseV1(
            releaseID: id(seed + 54), workspaceID: workspaceID, claimID: claim.claimID,
            leaseID: lease.leaseID, item: itemReference, holder: holder,
            reason: .leaseExpired, resultLinks: [staleResult],
            releasedAt: base.addingTimeInterval(3_609), mutationID: try mutation(seed + 55)
        )
        let divergentRelease = try WorkReleaseV1(
            releaseID: id(seed + 56), workspaceID: workspaceID, claimID: claim.claimID,
            leaseID: lease.leaseID, item: itemReference, holder: holder, reason: .completed,
            resultLinks: [divergentResult], releasedAt: base.addingTimeInterval(130),
            mutationID: try mutation(seed + 57)
        )
        let handoff = try WorkHandoffV1(
            handoffID: id(seed + 60), workspaceID: workspaceID,
            releaseID: handoffRelease.releaseID, item: itemReference,
            fromHolder: holder, toHolder: successorHolder, resultLinks: [alternateResult],
            reason: "C15 local handoff", handedOffAt: base.addingTimeInterval(121),
            mutationID: try mutation(seed + 61)
        )
        return Fixture(
            workspaceID: workspaceID, otherWorkspaceID: otherWorkspaceID,
            manifest: manifest, alternateManifest: alternateManifest,
            manifestReference: manifestReference, item: item, secondItem: secondItem,
            itemReference: itemReference, creator: creator, holder: holder,
            successorHolder: successorHolder, claim: claim, successorClaim: successorClaim,
            competingClaim: competingClaim, lease: lease, successorLease: successorLease,
            result: result, staleResult: staleResult, divergentResult: divergentResult,
            alternateResult: alternateResult, completedRelease: completedRelease,
            handoffRelease: handoffRelease, expiredRelease: expiredRelease,
            divergentRelease: divergentRelease, handoff: handoff,
            packageRelease: packageRelease, policyReference: policyReference,
            evidenceRequirement: evidenceRequirement
        )
    }

    static func corpusURL() -> URL {
        KernelConformanceFixtureHarnessV1.sourceRoot().appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V21/WorkPacketManifest/V21P03C15WorkPacketManifestCorpusV1.json"
        )
    }
}

/// Deterministic C36 field-draft evidence.  The fixture deliberately keeps the
/// operational graph in one place so each legacy V9/V10 lane exercises the
/// same checkpoint, staging, saga, reservation, receipt, and restore bytes.
enum C36FieldDraftTestSupportV1 {
    struct Fixture {
        let workspaceID: WorkspaceID
        let otherWorkspaceID: WorkspaceID
        let draftID: UUID
        let codec: DraftPayloadCodecReleaseV1
        let registry: DraftPurposeRegistryV1
        let scope: DraftScopeKeyV1
        let anchor: DraftResumeAnchorV1
        let payload: Data
        let activeCheckpoint: FieldDraftCheckpointV1
        let committingCheckpoint: FieldDraftCheckpointV1
        let committedCheckpoint: FieldDraftCheckpointV1
        let discardPendingCheckpoint: FieldDraftCheckpointV1
        let discardedCheckpoint: FieldDraftCheckpointV1
        let readyItem: AttachmentStagingItemV1
        let alternateReadyItem: AttachmentStagingItemV1
        let failedItem: AttachmentStagingItemV1
        let retryCapture: AttachmentStagingItemV1
        let retryHashing: AttachmentStagingItemV1
        let retryProcessing: AttachmentStagingItemV1
        let retryReady: AttachmentStagingItemV1
        let committedItem: AttachmentStagingItemV1
        let plan: DraftCommitPlanV1
        let rowMutationIDs: DraftCommitRowMutationIDsV1
        let preparedSaga: DraftCommitSagaV1
        let promotedSaga: DraftCommitSagaV1
        let targetCommittedSaga: DraftCommitSagaV1
        let retirePendingSaga: DraftCommitSagaV1
        let retiredSaga: DraftCommitSagaV1
        let conflictedSaga: DraftCommitSagaV1
        let recoverySaga: DraftCommitSagaV1
        let reservation: DraftContentReservationV1
        let reusedReservation: DraftContentReservationV1
        let associatedReservation: DraftContentReservationV1
        let quarantinedReservation: DraftContentReservationV1
        let deletedReservation: DraftContentReservationV1
        let commitReceipt: DraftCommitReceiptV1
        let commitTerminalBundle: DraftCommitTerminalBundleV1
        let discardPlan: DraftDiscardPlanV1
        let discardReceipt: DraftDiscardReceiptV1
        let discardTerminalBundle: DraftDiscardTerminalBundleV1
    }

    static let fixedDate = Date(timeIntervalSince1970: 1_748_000_000.125)
    static let digest = String(repeating: "a", count: 64)
    static let alternateDigest = String(repeating: "b", count: 64)

    static func id(_ seed: Int) -> UUID {
        C14InspectionReviewTestSupportV1.id(seed)
    }

    static func workspace(_ seed: Int = 136_000) -> WorkspaceID {
        WorkspaceID(rawValue: id(seed))
    }

    static func mutation(_ seed: Int) throws -> MutationIDV1 {
        try C14InspectionReviewTestSupportV1.mutation(seed)
    }

    static func codec(for purpose: DraftPurposeV1) throws -> DraftPayloadCodecReleaseV1 {
        try DraftPayloadCodecReleaseV1(
            codecID: "c36.\(purpose.rawValue.lowercased())",
            codecVersion: 1,
            releaseSHA256: digest
        )
    }

    static func makeRegistry() throws -> DraftPurposeRegistryV1 {
        let definitions = try DraftPurposeV1.allCases.map { purpose in
            try DraftPurposeDefinitionV1(
                purpose: purpose,
                codec: codec(for: purpose),
                maximumPayloadBytes: 4_096,
                maximumStageItems: 4,
                targetCommandKind: targetCommandKind(for: purpose),
                retention: purpose == .assetFieldEdit ? .retireAfterCommit : .explicitDiscardOnly,
                attachmentKinds: DraftAttachmentKindV1.allCases.sorted(),
                privacyClass: purpose == .evidenceCuration ? .restrictedEvidence : .workspacePrivate
            )
        }
        return try DraftPurposeRegistryV1(definitions)
    }

    static func targetCommandKind(for purpose: DraftPurposeV1) -> WorkspaceCommandKindV1 {
        switch purpose {
        case .inspectionReview: .applyInspectionReview
        case .workPacket: .applyWorkPacket
        case .correctiveAction: .finalizeCorrection
        case .requirementEvaluation: .applyRequirementAssurance
        case .evidenceCuration: .applyEvidenceAssurance
        case .assetFieldEdit: .applyAssetSemantics
        }
    }

    static func makeFixture(seed: Int = 136_000) throws -> Fixture {
        let workspaceID = workspace(seed)
        let otherWorkspaceID = workspace(seed + 900)
        let draftID = id(seed + 1)
        let codec = try codec(for: .inspectionReview)
        let registry = try makeRegistry()
        let scope = try DraftScopeKeyV1(
            scopeKind: "inspection-field",
            stableComponentIDs: ["section-observation", "field-notes"]
        )
        let anchor = try DraftResumeAnchorV1(
            sectionID: "section-observation", fieldID: "field-notes",
            selectedStableID: "field-notes", boundedPosition: 7
        )
        let payload = Data("notes=Visible local draft • א".utf8)
        let readyDigest = try ContentDigestV1(algorithm: .sha256, hexadecimalValue: digest)
        let alternateContentDigest = try ContentDigestV1(
            algorithm: .sha256, hexadecimalValue: alternateDigest
        )
        let workspaceString = workspaceID.rawValue.uuidString.lowercased()
        let readyReference = try ContentReferenceV1(
            workspaceID: workspaceString, contentID: "c36-content-one", byteLength: 64,
            mediaType: "image/jpeg", digests: try ContentDigestSetV1([readyDigest]),
            byteRole: .immutableOriginal, createdAt: "2025-05-01T00:00:00.000Z"
        )
        let alternateReference = try ContentReferenceV1(
            workspaceID: workspaceString, contentID: "c36-content-two", byteLength: 32,
            mediaType: "audio/mpeg", digests: try ContentDigestSetV1([alternateContentDigest]),
            byteRole: .immutableOriginal, createdAt: "2025-05-01T00:00:01.000Z"
        )
        let readyLocator = try ContentLocatorV1(
            locatorID: "c36-locator-one", workspaceID: workspaceString,
            contentID: readyReference.contentID, locatorRevision: 1,
            contentDigest: readyDigest, expectedByteLength: readyReference.byteLength
        )
        let alternateLocator = try ContentLocatorV1(
            locatorID: "c36-locator-two", workspaceID: workspaceString,
            contentID: alternateReference.contentID, locatorRevision: 1,
            contentDigest: alternateContentDigest, expectedByteLength: alternateReference.byteLength
        )
        let readyItem = try AttachmentStagingItemV1(
            stageID: id(seed + 10), draftID: draftID, workspaceID: workspaceID,
            attachmentKind: .photo, scratchLeaseID: id(seed + 20), expectedByteCount: 64,
            actualByteCount: 64, contentDigest: readyDigest, retryClass: .none,
            state: .readyLocal, protectionState: .available, revision: 1,
            mutationID: try mutation(seed + 30)
        )
        let alternateReadyItem = try AttachmentStagingItemV1(
            stageID: id(seed + 11), draftID: draftID, workspaceID: workspaceID,
            attachmentKind: .audio, scratchLeaseID: id(seed + 21), expectedByteCount: 32,
            actualByteCount: 32, contentDigest: alternateContentDigest, retryClass: .none,
            state: .readyLocal, protectionState: .available, revision: 1,
            mutationID: try mutation(seed + 31)
        )
        let failedItem = try AttachmentStagingItemV1(
            stageID: id(seed + 12), draftID: draftID, workspaceID: workspaceID,
            attachmentKind: .video, scratchLeaseID: id(seed + 22), expectedByteCount: 16,
            retryClass: .retryable, state: .failedRetryable,
            protectionState: .available, revision: 1, mutationID: try mutation(seed + 32)
        )
        let retryCapture = try AttachmentStagingItemV1(
            stageID: failedItem.stageID, draftID: draftID, workspaceID: workspaceID,
            attachmentKind: .video, scratchLeaseID: failedItem.scratchLeaseID,
            expectedByteCount: 16, retryClass: .retryable, state: .capturing,
            protectionState: .available, revision: 2, mutationID: try mutation(seed + 33)
        )
        let retryHashing = try AttachmentStagingItemV1(
            stageID: failedItem.stageID, draftID: draftID, workspaceID: workspaceID,
            attachmentKind: .video, scratchLeaseID: failedItem.scratchLeaseID,
            expectedByteCount: 16, retryClass: .retryable, state: .hashing,
            protectionState: .available, revision: 3, mutationID: try mutation(seed + 34)
        )
        let retryProcessing = try AttachmentStagingItemV1(
            stageID: failedItem.stageID, draftID: draftID, workspaceID: workspaceID,
            attachmentKind: .video, scratchLeaseID: failedItem.scratchLeaseID,
            expectedByteCount: 16, retryClass: .retryable, state: .processing,
            protectionState: .available, revision: 4, mutationID: try mutation(seed + 35)
        )
        let retryDigest = try ContentDigestV1(algorithm: .sha256, hexadecimalValue: digest)
        let retryReady = try AttachmentStagingItemV1(
            stageID: failedItem.stageID, draftID: draftID, workspaceID: workspaceID,
            attachmentKind: .video, scratchLeaseID: failedItem.scratchLeaseID,
            expectedByteCount: 16, actualByteCount: 16, contentDigest: retryDigest,
            retryClass: .none, state: .readyLocal, protectionState: .available,
            revision: 5, mutationID: try mutation(seed + 36)
        )
        let committedItem = try AttachmentStagingItemV1(
            stageID: readyItem.stageID, draftID: draftID, workspaceID: workspaceID,
            attachmentKind: .photo, scratchLeaseID: readyItem.scratchLeaseID,
            expectedByteCount: 64, actualByteCount: 64, contentDigest: readyDigest,
            contentReference: readyReference, retryClass: .none, state: .committed,
            protectionState: .available, revision: 2, mutationID: try mutation(seed + 37)
        )
        let plan = try DraftCommitPlanV1(
            planID: id(seed + 40), workspaceID: workspaceID, draftID: draftID,
            draftRevision: 2, baseCanonicalRevision: 7,
            payloadSHA256: FieldDraftCanonicalCodecV1.sha256(payload),
            stageDigests: [readyItem.stageSHA256, alternateReadyItem.stageSHA256],
            targetCommandKind: .applyInspectionReview, expectedTargetRevision: 3,
            mutationID: try mutation(seed + 41), outputKeys: ["inspection-review", "c36-local"]
        )
        let activeCheckpoint = try FieldDraftCheckpointV1(
            draftID: draftID, workspaceID: workspaceID, scope: scope,
            purpose: .inspectionReview, codec: codec, baseCanonicalRevision: 7,
            draftRevision: 1, payloadData: payload,
            stageIDs: [readyItem.stageID, alternateReadyItem.stageID, failedItem.stageID],
            resumeAnchor: anchor, state: .active, updatedAt: fixedDate,
            mutationID: try mutation(seed + 42)
        )
        let committingCheckpoint = try FieldDraftCheckpointV1(
            draftID: draftID, workspaceID: workspaceID, scope: scope,
            purpose: .inspectionReview, codec: codec, baseCanonicalRevision: 7,
            draftRevision: 2, payloadData: payload,
            stageIDs: [readyItem.stageID, alternateReadyItem.stageID, failedItem.stageID],
            resumeAnchor: anchor, state: .committing,
            lastDurableMutationID: try mutation(seed + 43),
            updatedAt: fixedDate.addingTimeInterval(1), mutationID: try mutation(seed + 44)
        )
        let preparedSaga = try DraftCommitSagaV1(
            sagaID: id(seed + 50), workspaceID: workspaceID, draftID: draftID,
            plan: plan, state: .prepared, revision: 1,
            mutationID: try mutation(seed + 51), updatedAt: fixedDate.addingTimeInterval(2)
        )
        let promotedSaga = try DraftCommitSagaV1(
            sagaID: id(seed + 52), workspaceID: workspaceID, draftID: draftID,
            plan: plan, state: .contentPromotedUnbound, predecessorSagaID: preparedSaga.sagaID,
            revision: 2, mutationID: try mutation(seed + 53), updatedAt: fixedDate.addingTimeInterval(3)
        )
        let targetCommittedSaga = try DraftCommitSagaV1(
            sagaID: id(seed + 54), workspaceID: workspaceID, draftID: draftID,
            plan: plan, state: .targetCommitted, predecessorSagaID: promotedSaga.sagaID,
            revision: 3, mutationID: try mutation(seed + 55), updatedAt: fixedDate.addingTimeInterval(4)
        )
        let retirePendingSaga = try DraftCommitSagaV1(
            sagaID: id(seed + 56), workspaceID: workspaceID, draftID: draftID,
            plan: plan, state: .draftRetirePending, predecessorSagaID: targetCommittedSaga.sagaID,
            revision: 4, mutationID: try mutation(seed + 57), updatedAt: fixedDate.addingTimeInterval(5)
        )
        let retiredSaga = try DraftCommitSagaV1(
            sagaID: id(seed + 58), workspaceID: workspaceID, draftID: draftID,
            plan: plan, state: .draftRetired, predecessorSagaID: retirePendingSaga.sagaID,
            revision: 5, mutationID: try mutation(seed + 102), updatedAt: fixedDate.addingTimeInterval(6)
        )
        let rowMutationIDs = try DraftCommitRowMutationIDsV1(
            reservationByStageID: [
                readyItem.stageID: try mutation(seed + 100),
                alternateReadyItem.stageID: try mutation(seed + 101)
            ],
            terminalBundleMutationID: try mutation(seed + 102)
        )
        try rowMutationIDs.validate(
            stageIDs: [readyItem.stageID, alternateReadyItem.stageID],
            targetMutationID: plan.mutationID,
            sagaMutationIDs: [
                preparedSaga.mutationID, promotedSaga.mutationID,
                targetCommittedSaga.mutationID, retirePendingSaga.mutationID
            ]
        )
        let conflictedSaga = try DraftCommitSagaV1(
            sagaID: id(seed + 60), workspaceID: workspaceID, draftID: draftID,
            plan: plan, state: .conflicted, predecessorSagaID: preparedSaga.sagaID,
            revision: 2, mutationID: try mutation(seed + 61), updatedAt: fixedDate.addingTimeInterval(7)
        )
        let recoverySaga = try DraftCommitSagaV1(
            sagaID: id(seed + 62), workspaceID: workspaceID, draftID: draftID,
            plan: plan, state: .recoveryRequired, predecessorSagaID: promotedSaga.sagaID,
            revision: 3, mutationID: try mutation(seed + 63), updatedAt: fixedDate.addingTimeInterval(8)
        )
        let sagaChain = [
            preparedSaga.sagaSHA256, promotedSaga.sagaSHA256, targetCommittedSaga.sagaSHA256,
            retirePendingSaga.sagaSHA256, retiredSaga.sagaSHA256
        ]
        let commitReceipt = try DraftCommitReceiptV1(
            receiptID: id(seed + 90), workspaceID: workspaceID, draftID: draftID,
            sagaID: retiredSaga.sagaID, commitPlanSHA256: plan.planSHA256,
            sagaEventSHA256Chain: sagaChain, targetMutationID: plan.mutationID,
            targetReceiptSHA256: digest,
            consumedStageToContentID: [
                readyItem.stageID.uuidString: readyReference.contentID,
                alternateReadyItem.stageID.uuidString: alternateReference.contentID
            ], committedAt: fixedDate.addingTimeInterval(10),
            mutationID: rowMutationIDs.terminalBundleMutationID
        )
        let committedCheckpoint = try FieldDraftCheckpointV1(
            draftID: draftID, workspaceID: workspaceID, scope: scope,
            purpose: .inspectionReview, codec: codec, baseCanonicalRevision: 7,
            draftRevision: 3, payloadData: payload,
            stageIDs: [readyItem.stageID, alternateReadyItem.stageID, failedItem.stageID],
            resumeAnchor: anchor, state: .committed,
            lastDurableMutationID: rowMutationIDs.terminalBundleMutationID,
            lastReceiptSHA256: commitReceipt.receiptSHA256,
            updatedAt: fixedDate.addingTimeInterval(10), mutationID: rowMutationIDs.terminalBundleMutationID
        )
        let commitTerminalBundle = try DraftCommitTerminalBundleV1(
            retiredSaga: retiredSaga, committedCheckpoint: committedCheckpoint,
            receipt: commitReceipt
        )
        let reservation = try DraftContentReservationV1(
            reservationID: id(seed + 70), workspaceID: workspaceID, draftID: draftID,
            stageID: readyItem.stageID, commitPlanSHA256: plan.planSHA256,
            mutationID: try mutation(seed + 71), contentDigest: readyDigest,
            locator: readyLocator, createdAt: fixedDate, reviewAfter: fixedDate.addingTimeInterval(86_400),
            reconciliationState: .reserved, revision: 1
        )
        let reusedReservation = try DraftContentReservationV1(
            reservationID: reservation.reservationID, workspaceID: workspaceID, draftID: draftID,
            stageID: readyItem.stageID, commitPlanSHA256: plan.planSHA256,
            mutationID: try mutation(seed + 72), contentDigest: readyDigest, locator: readyLocator,
            createdAt: fixedDate, reviewAfter: fixedDate.addingTimeInterval(86_400),
            reconciliationState: .reused, revision: 2
        )
        let associatedReservation = try DraftContentReservationV1(
            reservationID: id(seed + 73), workspaceID: workspaceID, draftID: draftID,
            stageID: alternateReadyItem.stageID, commitPlanSHA256: plan.planSHA256,
            mutationID: try mutation(seed + 74), contentDigest: alternateContentDigest,
            locator: alternateLocator, createdAt: fixedDate, reviewAfter: fixedDate.addingTimeInterval(86_400),
            reconciliationState: .associated, revision: 1
        )
        let quarantinedReservation = try DraftContentReservationV1(
            reservationID: id(seed + 75), workspaceID: workspaceID, draftID: draftID,
            stageID: failedItem.stageID, commitPlanSHA256: plan.planSHA256,
            mutationID: try mutation(seed + 76), contentDigest: readyDigest, locator: readyLocator,
            createdAt: fixedDate, reviewAfter: fixedDate.addingTimeInterval(86_400),
            reconciliationState: .orphanQuarantined, revision: 2
        )
        let deletedReservation = try DraftContentReservationV1(
            reservationID: quarantinedReservation.reservationID, workspaceID: workspaceID, draftID: draftID,
            stageID: failedItem.stageID, commitPlanSHA256: plan.planSHA256,
            mutationID: try mutation(seed + 77), contentDigest: readyDigest, locator: readyLocator,
            createdAt: fixedDate, reviewAfter: fixedDate.addingTimeInterval(86_400),
            reconciliationState: .deleted, revision: 3
        )
        let discardPlan = try DraftDiscardPlanV1(
            planID: id(seed + 80), workspaceID: workspaceID, draftID: draftID,
            expectedDraftRevision: 2, nonemptyPayload: true,
            stageIDs: [failedItem.stageID], reservationIDs: [quarantinedReservation.reservationID],
            estimatedBytes: 16
        )
        let discardPendingCheckpoint = try FieldDraftCheckpointV1(
            draftID: draftID, workspaceID: workspaceID, scope: scope,
            purpose: .inspectionReview, codec: codec, baseCanonicalRevision: 7,
            draftRevision: 2, payloadData: payload,
            stageIDs: [readyItem.stageID, alternateReadyItem.stageID, failedItem.stageID],
            resumeAnchor: anchor, state: .discardPending,
            updatedAt: fixedDate.addingTimeInterval(11), mutationID: try mutation(seed + 83)
        )
        let discardReceipt = try DraftDiscardReceiptV1(
            receiptID: id(seed + 81), workspaceID: workspaceID, draftID: draftID,
            planSHA256: discardPlan.planSHA256, disposedStageIDs: [failedItem.stageID],
            quarantinedReservationIDs: [quarantinedReservation.reservationID],
            discardedAt: fixedDate.addingTimeInterval(12), mutationID: try mutation(seed + 82)
        )
        let discardedCheckpoint = try FieldDraftCheckpointV1(
            draftID: draftID, workspaceID: workspaceID, scope: scope,
            purpose: .inspectionReview, codec: codec, baseCanonicalRevision: 7,
            draftRevision: 3, payloadData: payload,
            stageIDs: [readyItem.stageID, alternateReadyItem.stageID, failedItem.stageID],
            resumeAnchor: anchor, state: .discarded,
            lastDurableMutationID: discardReceipt.mutationID,
            lastReceiptSHA256: discardReceipt.receiptSHA256,
            updatedAt: fixedDate.addingTimeInterval(12), mutationID: discardReceipt.mutationID
        )
        let discardTerminalBundle = try DraftDiscardTerminalBundleV1(
            discardedCheckpoint: discardedCheckpoint, receipt: discardReceipt
        )
        _ = readyReference
        _ = alternateReference
        return Fixture(
            workspaceID: workspaceID, otherWorkspaceID: otherWorkspaceID, draftID: draftID,
            codec: codec, registry: registry, scope: scope, anchor: anchor, payload: payload,
            activeCheckpoint: activeCheckpoint, committingCheckpoint: committingCheckpoint,
            committedCheckpoint: committedCheckpoint,
            discardPendingCheckpoint: discardPendingCheckpoint,
            discardedCheckpoint: discardedCheckpoint,
            readyItem: readyItem,
            alternateReadyItem: alternateReadyItem, failedItem: failedItem,
            retryCapture: retryCapture, retryHashing: retryHashing, retryProcessing: retryProcessing,
            retryReady: retryReady, committedItem: committedItem, plan: plan,
            rowMutationIDs: rowMutationIDs,
            preparedSaga: preparedSaga, promotedSaga: promotedSaga,
            targetCommittedSaga: targetCommittedSaga, retirePendingSaga: retirePendingSaga,
            retiredSaga: retiredSaga, conflictedSaga: conflictedSaga, recoverySaga: recoverySaga,
            reservation: reservation, reusedReservation: reusedReservation,
            associatedReservation: associatedReservation, quarantinedReservation: quarantinedReservation,
            deletedReservation: deletedReservation, commitReceipt: commitReceipt,
            commitTerminalBundle: commitTerminalBundle, discardPlan: discardPlan,
            discardReceipt: discardReceipt, discardTerminalBundle: discardTerminalBundle
        )
    }

    static func corpusURL() -> URL {
        KernelConformanceFixtureHarnessV1.sourceRoot().appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V21/Drafts/V21P03C36FieldDraftResilienceCorpusV1.json"
        )
    }
}

/// Typed, provider-free C17 lifecycle fixture.  It deliberately contains only
/// the registry and an empty disposable checkpoint; production event bytes are
/// projected from accepted receipt history by the C17 implementation.
enum C17IntegrationEventTestSupportV1 {
    struct Fixture {
        let workspaceID: WorkspaceID
        let limits: IntegrationEventLimitsV1
        let registry: IntegrationContractRegistryV1
        let consumerID: String
        let consumerVersion: Int
        let emptyCheckpoint: ProjectionCheckpointV1
    }

    static func makeFixture() throws -> Fixture {
        let workspaceID = WorkspaceID(rawValue: UUID(
            uuidString: "00000000-0000-4000-8000-000000017017"
        )!)
        let limits = try IntegrationEventLimitsV1()
        let registry = try IntegrationContractRegistryV1(
            releaseID: "V23-P03-C17-CONFORMANCE",
            definitions: [
                try IntegrationEventContractDefinitionV1(
                    eventKind: "asset.changed",
                    eventVersion: 1,
                    sourceEntityKind: .asset,
                    sensitivity: .sensitiveWorkspaceData,
                    emittedVisibility: .sensitiveRedacted,
                    redaction: .identifiersOnly
                ),
                try IntegrationEventContractDefinitionV1(
                    eventKind: "site.changed",
                    eventVersion: 1,
                    sourceEntityKind: .site,
                    sensitivity: .workspaceData,
                    emittedVisibility: .workspaceInternal,
                    redaction: .notRequired
                ),
            ],
            limits: limits
        )
        let consumerID = "assetrounds.local.c17.lifecycle"
        let consumerVersion = 1
        let emptyCheckpoint = try ProjectionCheckpointV1(
            consumerID: consumerID,
            consumerVersion: consumerVersion,
            workspaceID: workspaceID,
            registrySHA256: registry.registrySHA256,
            lastEvent: nil,
            consumedEventCount: 0,
            consumerStateSHA256: String(repeating: "0", count: 64)
        )
        try emptyCheckpoint.validateResume(
            workspaceID: workspaceID, registry: registry
        )
        return Fixture(
            workspaceID: workspaceID,
            limits: limits,
            registry: registry,
            consumerID: consumerID,
            consumerVersion: consumerVersion,
            emptyCheckpoint: emptyCheckpoint
        )
    }
}

extension KernelConformanceFixtureHarnessV1 {
    /// C19 conformance anchor kept beside the existing portable fixture
    /// harness. It proves the measurement family is canonical and local
    /// without adding another store, writer, or provider seam.
    static func c19MeasurementIntegrityAnchor() throws -> String {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        try fixture.bundle.validate()
        try C19MeasurementIntegrityTestSupport.assertAllCanonicalRoundTrips(fixture)
        guard fixture.bundle.workspaceID == fixture.workspace,
              fixture.bundle.mutationID == fixture.mutationID,
              fixture.capture.measurement.source.isLocalMeasurementCaptureSource,
              fixture.series.samples.map(\.sampleOrdinal) == [1, 2] else {
            throw MeasurementIntegrityFailureV1.invalidValue
        }
        return fixture.bundle.bundleSHA256
    }

    static func c20PrivacyTransformAnchor() throws -> String {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        try fixture.bundle.validate()
        let closure = PrivacyTransformLifecycleClosureV1(
            policy: fixture.policy, regions: fixture.regions,
            manifest: fixture.manifest, review: fixture.approvedReview
        )
        try closure.validate()
        return fixture.manifest.manifestSHA256
    }

    static func c21ClientCapabilityLifecycleAnchor() throws -> Int {
        try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19)
        guard ClientCapabilityProfileV1.schemaVersion == 1,
              ClientAdmissionV1.allCases.count == 5,
              PackageLifecycleOperationV1.allCases.count == 9,
              PersistentSchemaV20.models.count == 81 else {
            throw ClientCapabilityFailureV1.invalidValue
        }
        return PersistentSchemaV20.models.count
    }
}
