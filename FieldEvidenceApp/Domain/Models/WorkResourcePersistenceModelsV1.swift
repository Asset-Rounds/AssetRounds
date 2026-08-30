import Foundation
import SwiftData

/// Persistence failures are deliberately separate from the canonical domain
/// contract.  A malformed row, cross-workspace bundle, or unavailable
/// lifecycle authority must never be interpreted as a successful append.
enum WorkResourcePersistenceFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case invalidText
    case invalidDigest
    case invalidRevision
    case crossWorkspaceReference
    case duplicateIdentity
    case corruptRow
    case unavailable
    case unsupportedVersion
}

enum WorkResourcePersistenceLimitsV1 {
    static let maximumSnapshotRows = 10_000
    static let maximumSearchQueryBytes = 512
    static let maximumDescriptionBytes = 160
    static let maximumUnitBytes = 24
    static let maximumNoteBytes = 1_024
    static let maximumMaterialLines = 50
}

/// Canonical bytes are shared with the mutation subsystem.  This type is only
/// a persistence adapter; it does not define a second work-resource codec.
private enum WorkResourcePersistenceCodecV1 {
    static func data<T: Encodable>(_ value: T) throws -> Data {
        try WorkspaceMutationCanonicalV1.data(value)
    }

    static func sha256<T: Encodable>(_ value: T) throws -> String {
        try WorkspaceMutationCanonicalV1.sha256(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }

    static func isDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}

enum WorkResourceReportProfileV1: String, Codable, CaseIterable, Hashable, Sendable {
    case internalDurationMaterialAndCost = "INTERNAL_DURATION_MATERIAL_AND_COST"
    case customerSafeDurationMaterial = "CUSTOMER_SAFE_DURATION_MATERIAL"
}

/// A bundle is the atomic persistence boundary.  Direct cost is exposed only
/// as a derived compatibility view; the canonical source remains
/// `entry.directCost` and is serialized once with the entry.
struct WorkResourceAtomicBundleV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let entry: WorkResourceEntryV1

    init(workspaceID: WorkspaceID, entry: WorkResourceEntryV1) throws {
        guard workspaceID == entry.workspaceID else {
            throw WorkResourcePersistenceFailureV1.crossWorkspaceReference
        }
        try entry.validate()
        self.workspaceID = workspaceID
        self.entry = entry
    }

    init(entry: WorkResourceEntryV1) throws {
        try self.init(workspaceID: entry.workspaceID, entry: entry)
    }

    /// Compatibility initializer for callers that still provide a detached
    /// cost list.  It accepts only the one value already embedded in `entry`.
    init(
        workspaceID: WorkspaceID,
        entry: WorkResourceEntryV1,
        directCosts: [DirectCostEntryV1]
    ) throws {
        let expected = entry.directCost.map { [$0] } ?? []
        guard directCosts == expected else {
            throw WorkResourcePersistenceFailureV1.invalidValue
        }
        try self.init(workspaceID: workspaceID, entry: entry)
    }

    /// Derived view retained while backup consumers migrate to the embedded
    /// representation.  It is not an independently persisted truth source.
    var directCosts: [DirectCostEntryV1] {
        entry.directCost.map { [$0] } ?? []
    }

    func validate() throws {
        _ = try Self(workspaceID: workspaceID, entry: entry)
    }
}

struct WorkResourceBackupSnapshotV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let bundles: [WorkResourceAtomicBundleV1]
    let snapshotSHA256: String

    init(workspaceID: WorkspaceID, bundles: [WorkResourceAtomicBundleV1]) throws {
        guard bundles.count <= WorkResourcePersistenceLimitsV1.maximumSnapshotRows,
              bundles.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw WorkResourcePersistenceFailureV1.crossWorkspaceReference
        }
        for bundle in bundles {
            try bundle.validate()
        }
        let ordered = bundles.sorted {
            ($0.entry.workspaceID.rawValue.uuidString.lowercased(),
             $0.entry.entryID.uuidString.lowercased())
                < ($1.entry.workspaceID.rawValue.uuidString.lowercased(),
                   $1.entry.entryID.uuidString.lowercased())
        }
        guard Set(ordered.map { $0.entry.entryID }).count == ordered.count else {
            throw WorkResourcePersistenceFailureV1.duplicateIdentity
        }
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.bundles = ordered
        snapshotSHA256 = try WorkResourcePersistenceCodecV1.sha256(
            Basis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID, bundles: ordered)
        )
    }

    var entries: [WorkResourceEntryV1] {
        bundles.map(\.entry)
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw WorkResourcePersistenceFailureV1.unsupportedVersion
        }
        let rebuilt = try Self(workspaceID: workspaceID, bundles: bundles)
        guard rebuilt.snapshotSHA256 == snapshotSHA256 else {
            throw WorkResourcePersistenceFailureV1.invalidDigest
        }
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let workspaceID: WorkspaceID
        let bundles: [WorkResourceAtomicBundleV1]
    }
}

struct WorkResourceRestoreReceiptV1: Codable, Equatable, Sendable {
    let operationID: UUID
    let sourceWorkspaceID: WorkspaceID
    let targetWorkspaceID: WorkspaceID
    let snapshotSHA256: String
    let effectSHA256: String
    let cloneOrFork: Bool
    let completedAt: Date

    init(
        operationID: UUID,
        sourceWorkspaceID: WorkspaceID,
        targetWorkspaceID: WorkspaceID,
        snapshotSHA256: String,
        effectSHA256: String,
        cloneOrFork: Bool,
        completedAt: Date
    ) throws {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        guard operationID != zero,
              sourceWorkspaceID.rawValue != zero,
              targetWorkspaceID.rawValue != zero,
              completedAt.timeIntervalSinceReferenceDate.isFinite,
              WorkResourcePersistenceCodecV1.isDigest(snapshotSHA256),
              WorkResourcePersistenceCodecV1.isDigest(effectSHA256) else {
            throw WorkResourcePersistenceFailureV1.invalidValue
        }
        self.operationID = operationID
        self.sourceWorkspaceID = sourceWorkspaceID
        self.targetWorkspaceID = targetWorkspaceID
        self.snapshotSHA256 = snapshotSHA256
        self.effectSHA256 = effectSHA256
        self.cloneOrFork = cloneOrFork
        self.completedAt = completedAt
    }
}

/// The composition root supplies the existing writer, backup, journal,
/// search, and report authorities.  This port owns no canonical bytes.
@MainActor
protocol WorkResourceLifecyclePortV1: AnyObject {
    func append(_ entry: WorkResourceEntryV1) async throws -> WorkResourceMutationReceiptV1
    func snapshotForBackup(workspaceID: WorkspaceID) async throws -> WorkResourceBackupSnapshotV1
    func restore(
        _ snapshot: WorkResourceBackupSnapshotV1,
        targetWorkspaceID: WorkspaceID,
        operationID: UUID,
        cloneOrFork: Bool
    ) async throws -> WorkResourceRestoreReceiptV1
    func delete(workspaceID: WorkspaceID, subject: WorkResourceSubjectV1) async throws
    func erase(workspaceID: WorkspaceID) async throws
    func rebuildSearch(workspaceID: WorkspaceID) async throws
    func search(workspaceID: WorkspaceID, query: String) async throws -> [WorkResourceEntryV1]
    func report(
        workspaceID: WorkspaceID,
        profile: WorkResourceReportProfileV1
    ) async throws -> WorkResourceTotalsProjectionV1
}

extension WorkResourceLifecyclePortV1 {
    func append(_ bundle: WorkResourceAtomicBundleV1) async throws -> WorkResourceMutationReceiptV1 {
        try await append(bundle.entry)
    }
}

enum C49WorkResourcePersistenceBoundaryV1 {
    static let cardID = "V23-P03-C49"
    static let persistentSchemaVersion = 37
    static let recordsSchemaVersion = 36
    static let durableModelCount = 1
    static let newlyEnrolledRows = ["ManualWorkResourceRecordRow"]
    static let durableFamilies = newlyEnrolledRows
    static let appendOnlyHistory = true
    static let directCostIsEmbedded = true
    static let separateDirectCostRow = false
    static let localPartSnapshotIsEmbedded = true
    static let localPartSnapshotIsLiveInventoryRow = false
    static let noCatalogOrMovementRows = true
    static let noLiveTimer = true
    static let noAccountingProjection = true
    static let acceptedBytesAreCanonical = true
    static let backupRestoreCloneForkDeleteAndEraseUseExistingAuthorities = true
    static let forwardFixPreservesReleasedCanonicalRows = true
    static let releasedReadersRemainAvailable = true
    static let canonicalRowsAreNeverRewrittenInPlace = true
    static let directCostTotalsRemainSeparateByCurrency = true
    static let directCostCurrencyConversion = false
    static let directCostCurrencyConversionIsForbidden = true

    static func validate() throws {
        guard durableModelCount == newlyEnrolledRows.count,
              Set(newlyEnrolledRows).count == newlyEnrolledRows.count,
              persistentSchemaVersion == 37,
              recordsSchemaVersion == 36,
              directCostIsEmbedded,
              !separateDirectCostRow,
              localPartSnapshotIsEmbedded,
              !localPartSnapshotIsLiveInventoryRow,
              forwardFixPreservesReleasedCanonicalRows,
              releasedReadersRemainAvailable,
              canonicalRowsAreNeverRewrittenInPlace,
              directCostTotalsRemainSeparateByCurrency,
              !directCostCurrencyConversion,
              directCostCurrencyConversionIsForbidden else {
            throw WorkResourcePersistenceFailureV1.invalidValue
        }
    }

    /// A forward fix may add a successor row, but it must continue to read
    /// every released canonical entry without rewriting that entry in place.
    static func validateForwardFix(_ entry: WorkResourceEntryV1) throws {
        guard forwardFixPreservesReleasedCanonicalRows,
              releasedReadersRemainAvailable,
              canonicalRowsAreNeverRewrittenInPlace else {
            throw WorkResourcePersistenceFailureV1.invalidValue
        }
        try entry.validate()
    }

    /// Currency totals are keyed projections.  This guard intentionally does
    /// not convert, combine, or otherwise reinterpret one currency as another.
    static func validateDirectCostTotals(
        _ totals: [String: Int64]
    ) throws {
        guard directCostTotalsRemainSeparateByCurrency,
              !directCostCurrencyConversion,
              directCostCurrencyConversionIsForbidden,
              totals.count == Set(totals.keys).count,
              totals.values.allSatisfy({ $0 > 0 }) else {
            throw WorkResourcePersistenceFailureV1.invalidValue
        }
    }
}

typealias WorkResourcePersistenceEnrollmentV1 = C49WorkResourcePersistenceBoundaryV1

/// The lifecycle adapter may construct a profile-filtered projection after
/// querying immutable rows.  This convenience keeps the canonical material
/// totals explicit; the snapshot initializer remains the domain-owned total
/// route.
extension WorkResourceTotalsProjectionV1 {
    init(
        durationMinutes: Int,
        materialLineCount: Int,
        materialTotals: [WorkResourceMaterialTotalV1],
        directCostByCurrency: [String: Int64]
    ) {
        self.durationMinutes = durationMinutes
        self.materialLineCount = materialLineCount
        self.materialTotals = materialTotals.sorted {
            ($0.description, $0.unit ?? "") < ($1.description, $1.unit ?? "")
        }
        self.directCostByCurrency = directCostByCurrency
    }

    /// Compatibility for the pre-material-totals test/support constructor.
    /// Callers with resource detail must use the explicit `materialTotals`
    /// overload; an empty array here means that only aggregate counters were
    /// supplied by that legacy authority, not that a report discarded rows.
    @available(*, deprecated, message: "Supply explicit materialTotals when material detail is available")
    init(
        durationMinutes: Int,
        materialLineCount: Int,
        directCostByCurrency: [String: Int64]
    ) {
        self.init(
            durationMinutes: durationMinutes,
            materialLineCount: materialLineCount,
            materialTotals: [],
            directCostByCurrency: directCostByCurrency
        )
    }
}

/// One SwiftData row stores the complete canonical entry, including an
/// embedded direct cost and any frozen local-part snapshot in a material line.
/// No detached direct-cost row is enrolled.
@Model
final class ManualWorkResourceRecordRow {
    @Attribute(.unique) var stableIdentity: String
    var entryID: UUID
    var workspaceID: UUID
    var subjectKindRawValue: String
    var subjectID: String
    var subjectRevision: UInt64
    var subjectSHA256: String
    var dispositionRawValue: String
    var revision: UInt64
    var mutationID: UUID
    var entrySHA256: String
    var canonicalData: Data

    init(_ value: WorkResourceEntryV1) throws {
        try C49WorkResourcePersistenceBoundaryV1.validateForwardFix(value)
        stableIdentity = Self.identity(workspaceID: value.workspaceID.rawValue, id: value.entryID)
        entryID = value.entryID
        workspaceID = value.workspaceID.rawValue
        subjectKindRawValue = value.subject.kind.rawValue
        subjectID = value.subject.subjectID
        subjectRevision = value.subject.subjectRevision
        subjectSHA256 = value.subject.subjectSHA256
        dispositionRawValue = value.disposition.rawValue
        revision = value.revision
        mutationID = value.mutationID.rawValue
        entrySHA256 = value.entrySHA256
        canonicalData = try WorkResourcePersistenceCodecV1.data(value)
    }

    convenience init(entry: WorkResourceEntryV1) throws {
        try self.init(entry)
    }

    func value() throws -> WorkResourceEntryV1 {
        let value = try WorkResourcePersistenceCodecV1.decode(
            WorkResourceEntryV1.self,
            from: canonicalData
        )
        try C49WorkResourcePersistenceBoundaryV1.validateForwardFix(value)
        guard stableIdentity == Self.identity(
                  workspaceID: value.workspaceID.rawValue,
                  id: value.entryID
              ),
              entryID == value.entryID,
              workspaceID == value.workspaceID.rawValue,
              subjectKindRawValue == value.subject.kind.rawValue,
              subjectID == value.subject.subjectID,
              subjectRevision == value.subject.subjectRevision,
              subjectSHA256 == value.subject.subjectSHA256,
              dispositionRawValue == value.disposition.rawValue,
              revision == value.revision,
              mutationID == value.mutationID.rawValue,
              entrySHA256 == value.entrySHA256,
              canonicalData == (try WorkResourcePersistenceCodecV1.data(value)) else {
            throw WorkResourcePersistenceFailureV1.corruptRow
        }
        return value
    }

    private static func identity(workspaceID: UUID, id: UUID) -> String {
        "\(workspaceID.uuidString.lowercased())|\(id.uuidString.lowercased())"
    }
}

@MainActor
final class WorkResourceRowQueryV1 {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func entries(workspaceID: WorkspaceID) throws -> [WorkResourceEntryV1] {
        let rawWorkspaceID = workspaceID.rawValue
        return try modelContext.fetch(
            FetchDescriptor<ManualWorkResourceRecordRow>(
                predicate: #Predicate { $0.workspaceID == rawWorkspaceID }
            )
        )
        .map { try $0.value() }
        .sorted {
            ($0.revision, $0.entryID.uuidString.lowercased())
                < ($1.revision, $1.entryID.uuidString.lowercased())
        }
    }

    /// Direct costs are projected from the immutable entry rows.  This query
    /// never consults or creates a second direct-cost store.
    func directCosts(workspaceID: WorkspaceID) throws -> [DirectCostEntryV1] {
        try entries(workspaceID: workspaceID)
            .compactMap(\.directCost)
    }

    func snapshot(workspaceID: WorkspaceID, recordID: UUID) throws -> WorkResourceSnapshotV1? {
        let rawWorkspaceID = workspaceID.rawValue
        let rows = try modelContext.fetch(
            FetchDescriptor<ManualWorkResourceRecordRow>(
                predicate: #Predicate {
                    $0.workspaceID == rawWorkspaceID && $0.entryID == recordID
                }
            )
        )
        guard rows.count <= 1 else {
            throw WorkResourcePersistenceFailureV1.duplicateIdentity
        }
        guard let row = rows.first else { return nil }
        return try WorkResourceSnapshotV1(entry: row.value())
    }

    func snapshot(workspaceID: WorkspaceID, entryID: UUID) throws -> WorkResourceSnapshotV1? {
        try snapshot(workspaceID: workspaceID, recordID: entryID)
    }
}
