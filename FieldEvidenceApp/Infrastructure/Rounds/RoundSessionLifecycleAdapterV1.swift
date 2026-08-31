import Foundation

/// Derived lifecycle bridge for the canonical round-session coordinator. This
/// adapter owns no session rows, writers, renderer, or search store: it proves
/// the live canonical frontier before producing metadata-only derivatives.
@MainActor
final class RoundSessionLifecycleAdapterV1 {
    private let roundCoordinator: RoundSessionCoordinatorV1

    init(roundCoordinator: RoundSessionCoordinatorV1) {
        self.roundCoordinator = roundCoordinator
    }

    func progress(
        at frontier: RoundSessionReferenceV1
    ) throws -> C05RoundSessionProgressReportProjectionV1 {
        let current = try roundCoordinator.validateCurrentFrontier(frontier)
        return try ReportProjectionRegistryV1.roundSessionProgress(session: current)
    }

    func closeout(
        at frontier: RoundSessionReferenceV1
    ) throws -> C05RoundSessionCloseoutReportProjectionV1 {
        let current = try roundCoordinator.validateCurrentFrontier(frontier)
        return try reconciledCloseout(session: current)
    }

    func searchProjection(
        at frontier: RoundSessionReferenceV1
    ) throws -> C05RoundSessionSearchProjectionV1 {
        let current = try roundCoordinator.validateCurrentFrontier(frontier)
        let progress = try ReportProjectionRegistryV1.roundSessionProgress(session: current)
        let closeout = current.state == .completed
            ? try reconciledCloseout(session: current)
            : nil
        return try C05RoundSessionSearchProjectionBoundaryV1.projection(
            progress: progress,
            closeout: closeout
        )
    }

    func recoverProgress(
        _ projection: C05RoundSessionProgressReportProjectionV1
    ) throws -> C05RoundSessionProgressReportProjectionV1 {
        let current = try roundCoordinator.validateCurrentFrontier(projection.session)
        return try ReportRecoveryService.recoverRoundSessionProgress(
            projection,
            source: current
        )
    }

    func recoverCloseout(
        _ projection: C05RoundSessionCloseoutReportProjectionV1
    ) throws -> C05RoundSessionCloseoutReportProjectionV1 {
        let current = try roundCoordinator.validateCurrentFrontier(projection.progress.session)
        _ = try ReportRecoveryService.recoverRoundSessionCloseout(
            projection,
            source: current
        )
        return try reconciledCloseout(session: current)
    }

    /// Index invalidation occurs strictly after the incumbent coordinator has
    /// accepted the canonical mutation and after the caller supplies its new
    /// workspace-wide source revision. The index remains disposable truth, so
    /// post-commit invalidation failure returns the committed receipt together
    /// with a rebuild-required disposition instead of misreporting a failed save.
    func save(
        _ mutation: RoundSessionMutationV1,
        postCommitSearchSource: SearchSourceRevisionV1,
        searchLifecycle: any SearchIndexLifecyclePortV1
    ) async throws -> C07RoundSessionPostCommitResultV1 {
        try mutation.validate()
        guard postCommitSearchSource.workspaceID == mutation.workspaceID.rawValue else {
            throw RoundSessionFailureV1.authorityMismatch
        }
        let receipt = try roundCoordinator.save(mutation)
        try receipt.validate()
        guard receipt.sessionFrontier == (try mutation.session.reference) else {
            throw RoundSessionFailureV1.authorityMismatch
        }
        let searchDisposition: C07RoundSessionSearchPostCommitDispositionV1
        do {
            try await searchLifecycle.invalidateAfterCanonicalCommit(
                source: postCommitSearchSource
            )
            searchDisposition = .reconciled
        } catch {
            searchDisposition = .rebuildRequired
        }
        return try C07RoundSessionPostCommitResultV1(
            receipt: receipt,
            searchDisposition: searchDisposition
        )
    }

    func rebuildSearch(
        using rebuildCoordinator: SearchIndexRebuildCoordinatorV1
    ) async throws -> SearchIndexRebuildResultV1 {
        try await rebuildCoordinator.rebuildIfNeeded()
    }

    /// Rebuilds the navigation index only from the validated current frontier
    /// and caller-materialized, exact requirement/draft inputs.
    func fieldSectionIndex(
        at frontier: RoundSessionReferenceV1,
        requirementBindings: [FieldSectionIndexRequirementBindingV1],
        draftAnchors: [FieldSectionIndexDraftAnchorV1] = [],
        packagePermissions: [FieldSectionIndexOutOfOrderPermissionV1]
    ) throws -> FieldSectionIndexProjectionV1 {
        let current = try roundCoordinator.validateCurrentFrontier(frontier)
        let projection = try FieldSectionIndexProjectionV1(
            session: current,
            requirementBindings: requirementBindings,
            draftAnchors: draftAnchors,
            packagePermissions: packagePermissions
        )
        try projection.validate(session: current)
        return projection
    }

    /// The local handoff is a manifest/plan only. Its creation requires an
    /// exact reconciled completed closeout and makes no delivery claim.
    func handoffManifest(
        at frontier: RoundSessionReferenceV1
    ) throws -> C07RoundSessionHandoffManifestV1 {
        let current = try roundCoordinator.validateCurrentFrontier(frontier)
        let progress = try ReportProjectionRegistryV1.roundSessionProgress(session: current)
        let closeout = try reconciledCloseout(session: current)
        let search = try C05RoundSessionSearchProjectionBoundaryV1.projection(
            progress: progress,
            closeout: closeout
        )
        return try C07RoundSessionHandoffManifestV1(
            progress: progress,
            closeout: closeout,
            search: search
        )
    }

    /// Ordinary deletion is only an informed preview: C05 preserves canonical
    /// session history, while an actual workspace Erase remains its incumbent
    /// authority. This method performs neither action.
    func deletePreview(
        at frontier: RoundSessionReferenceV1
    ) throws -> C07RoundSessionDeletePreviewV1 {
        let current = try roundCoordinator.validateCurrentFrontier(frontier)
        return try C07RoundSessionDeletePreviewV1(session: current)
    }

    /// Recreates the disposable C05 search record from the current canonical
    /// frontier; a stale prior projection is never retained as current truth.
    func recoverSearch(
        _ projection: C05RoundSessionSearchProjectionV1
    ) throws -> C05RoundSessionSearchProjectionV1 {
        let current = try roundCoordinator.validateCurrentFrontier(projection.session)
        return try searchProjection(at: current.reference)
    }

    func recoverHandoff(
        _ manifest: C07RoundSessionHandoffManifestV1
    ) throws -> C07RoundSessionHandoffManifestV1 {
        try manifest.validate()
        let current = try roundCoordinator.validateCurrentFrontier(manifest.session)
        return try handoffManifest(at: current.reference)
    }

    /// Captures the incumbent lifecycle closure as a derived proof scoped to
    /// one exact canonical frontier. It is not a second lifecycle registry.
    func lifecycleEvidence(
        at frontier: RoundSessionReferenceV1
    ) throws -> C07RoundSessionLifecycleEvidenceV1 {
        let current = try roundCoordinator.validateCurrentFrontier(frontier)
        return try C07RoundSessionLifecycleEvidenceV1(session: current)
    }

    private func reconciledCloseout(
        session: RoundSessionV1
    ) throws -> C05RoundSessionCloseoutReportProjectionV1 {
        guard session.state == .completed,
              session.counts.undispositioned == 0,
              session.counts.inaccessible == 0 else {
            throw C07RoundSessionLifecycleAdapterFailureV1.incompleteCloseout
        }
        return try ReportProjectionRegistryV1.roundSessionCloseout(session: session)
    }
}

enum C07RoundSessionLifecycleAdapterFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case incompleteCloseout
    case digestMismatch
}

/// Closed post-commit truth for a canonical round-session save. A failed
/// disposable-index invalidation never changes the accepted writer receipt.
enum C07RoundSessionSearchPostCommitDispositionV1: String, Codable, Equatable, Sendable {
    case reconciled = "RECONCILED"
    case rebuildRequired = "REBUILD_REQUIRED"
}

struct C07RoundSessionPostCommitResultV1: Equatable, Sendable {
    let receipt: RoundSessionMutationReceiptV1
    let searchDisposition: C07RoundSessionSearchPostCommitDispositionV1

    init(
        receipt: RoundSessionMutationReceiptV1,
        searchDisposition: C07RoundSessionSearchPostCommitDispositionV1
    ) throws {
        try receipt.validate()
        self.receipt = receipt
        self.searchDisposition = searchDisposition
    }
}

enum C07RoundSessionDeleteDispositionV1: String, CaseIterable, Codable, Equatable, Sendable {
    case preserveCanonicalHistory = "PRESERVE_CANONICAL_HISTORY"
    case workspaceEraseOnly = "WORKSPACE_ERASE_ONLY"
}

/// An informed, non-destructive preview. Canonical session history is never
/// removed by this adapter, including when a session remains incomplete.
struct C07RoundSessionDeletePreviewV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let session: RoundSessionReferenceV1
    let state: RoundSessionStateV1
    let incompleteCount: Int
    let ordinaryDisposition: C07RoundSessionDeleteDispositionV1
    let eraseDisposition: C07RoundSessionDeleteDispositionV1
    let previewSHA256: String

    init(session source: RoundSessionV1) throws {
        try source.validateIntrinsic()
        schemaVersion = Self.schemaVersion
        session = try source.reference
        state = source.state
        incompleteCount = source.counts.undispositioned
        ordinaryDisposition = .preserveCanonicalHistory
        eraseDisposition = .workspaceEraseOnly
        previewSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: schemaVersion,
            session: session,
            state: state,
            incompleteCount: incompleteCount,
            ordinaryDisposition: ordinaryDisposition,
            eraseDisposition: eraseDisposition
        ))
        try validate()
    }

    func validate() throws {
        try session.validate()
        guard schemaVersion == Self.schemaVersion,
              incompleteCount >= 0,
              ordinaryDisposition == .preserveCanonicalHistory,
              eraseDisposition == .workspaceEraseOnly,
              previewSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else {
            throw C07RoundSessionLifecycleAdapterFailureV1.digestMismatch
        }
    }

    private var basis: Basis {
        Basis(schemaVersion: schemaVersion, session: session, state: state,
              incompleteCount: incompleteCount, ordinaryDisposition: ordinaryDisposition,
              eraseDisposition: eraseDisposition)
    }
    private struct Basis: Codable {
        let schemaVersion: Int; let session: RoundSessionReferenceV1
        let state: RoundSessionStateV1; let incompleteCount: Int
        let ordinaryDisposition: C07RoundSessionDeleteDispositionV1
        let eraseDisposition: C07RoundSessionDeleteDispositionV1
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, session, state, incompleteCount, ordinaryDisposition, eraseDisposition, previewSHA256
    }
    init(from decoder: Decoder) throws {
        try KernelClosedCodingV1.require(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        session = try c.decode(RoundSessionReferenceV1.self, forKey: .session)
        state = try c.decode(RoundSessionStateV1.self, forKey: .state)
        incompleteCount = try c.decode(Int.self, forKey: .incompleteCount)
        ordinaryDisposition = try c.decode(C07RoundSessionDeleteDispositionV1.self, forKey: .ordinaryDisposition)
        eraseDisposition = try c.decode(C07RoundSessionDeleteDispositionV1.self, forKey: .eraseDisposition)
        previewSHA256 = try c.decode(String.self, forKey: .previewSHA256)
        try validate()
    }
}

/// A local-only handoff plan bound to every derived source it presents. It
/// cannot exist for an incomplete, inaccessible, deferred, or otherwise
/// unreconciled closeout because C05's closeout projection rejects that state.
struct C07RoundSessionHandoffManifestV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let session: RoundSessionReferenceV1
    let progressProjectionSHA256: String
    let closeoutSHA256: String
    let searchProjectionSHA256: String
    let sourceSHA256s: [String]
    let localHandoffPermitted: Bool
    let manifestSHA256: String

    init(
        progress: C05RoundSessionProgressReportProjectionV1,
        closeout: C05RoundSessionCloseoutReportProjectionV1,
        search: C05RoundSessionSearchProjectionV1
    ) throws {
        try progress.validate(); try closeout.validate(); try search.validate()
        guard closeout.progress == progress,
              search.session == progress.session,
              search.sourceFrontierSHA256 == progress.sourceFrontierSHA256,
              search.progressProjectionSHA256 == progress.projectionSHA256,
              search.closeoutSHA256 == closeout.closeoutSHA256,
              progress.state == .completed,
              progress.counts.undispositioned == 0,
              progress.counts.inaccessible == 0 else {
            throw C07RoundSessionLifecycleAdapterFailureV1.incompleteCloseout
        }
        schemaVersion = Self.schemaVersion
        session = progress.session
        progressProjectionSHA256 = progress.projectionSHA256
        closeoutSHA256 = closeout.closeoutSHA256
        searchProjectionSHA256 = search.projectionSHA256
        sourceSHA256s = [
            progress.sourceFrontierSHA256,
            progress.projectionSHA256,
            closeout.closeoutSHA256,
            search.projectionSHA256
        ].sorted()
        localHandoffPermitted = true
        manifestSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: schemaVersion,
            session: session,
            progressProjectionSHA256: progressProjectionSHA256,
            closeoutSHA256: closeoutSHA256,
            searchProjectionSHA256: searchProjectionSHA256,
            sourceSHA256s: sourceSHA256s,
            localHandoffPermitted: localHandoffPermitted
        ))
        try validate()
    }

    func validate() throws {
        try session.validate()
        guard schemaVersion == Self.schemaVersion,
              KernelCanonicalHashV1.validSHA256(progressProjectionSHA256),
              KernelCanonicalHashV1.validSHA256(closeoutSHA256),
              KernelCanonicalHashV1.validSHA256(searchProjectionSHA256),
              sourceSHA256s.count == 4,
              sourceSHA256s == sourceSHA256s.sorted(),
              Set(sourceSHA256s).count == sourceSHA256s.count,
              sourceSHA256s.allSatisfy(KernelCanonicalHashV1.validSHA256),
              sourceSHA256s.contains(session.sessionSHA256),
              sourceSHA256s.contains(progressProjectionSHA256),
              sourceSHA256s.contains(closeoutSHA256),
              sourceSHA256s.contains(searchProjectionSHA256),
              localHandoffPermitted,
              manifestSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else {
            throw C07RoundSessionLifecycleAdapterFailureV1.digestMismatch
        }
    }

    private var basis: Basis {
        Basis(schemaVersion: schemaVersion, session: session,
              progressProjectionSHA256: progressProjectionSHA256,
              closeoutSHA256: closeoutSHA256,
              searchProjectionSHA256: searchProjectionSHA256,
              sourceSHA256s: sourceSHA256s,
              localHandoffPermitted: localHandoffPermitted)
    }
    private struct Basis: Codable {
        let schemaVersion: Int; let session: RoundSessionReferenceV1
        let progressProjectionSHA256: String; let closeoutSHA256: String
        let searchProjectionSHA256: String; let sourceSHA256s: [String]
        let localHandoffPermitted: Bool
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, session, progressProjectionSHA256, closeoutSHA256, searchProjectionSHA256, sourceSHA256s, localHandoffPermitted, manifestSHA256
    }
    init(from decoder: Decoder) throws {
        try KernelClosedCodingV1.require(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        session = try c.decode(RoundSessionReferenceV1.self, forKey: .session)
        progressProjectionSHA256 = try c.decode(String.self, forKey: .progressProjectionSHA256)
        closeoutSHA256 = try c.decode(String.self, forKey: .closeoutSHA256)
        searchProjectionSHA256 = try c.decode(String.self, forKey: .searchProjectionSHA256)
        sourceSHA256s = try c.decode([String].self, forKey: .sourceSHA256s)
        localHandoffPermitted = try c.decode(Bool.self, forKey: .localHandoffPermitted)
        manifestSHA256 = try c.decode(String.self, forKey: .manifestSHA256)
        try validate()
    }
}

enum C07RoundSessionLifecycleDimensionV1: String, CaseIterable, Codable, Equatable, Sendable {
    case backup, replaceRestore, clone, fork, import, export, report, journalReplay
    case searchRebuild, ordinaryDelete, workspaceErase, retention, compatibility
    case forwardFix, interruption, idempotentReceipt
}

/// Declares that C07 reuses the C05 canonical enrollment and provides only
/// rebuildable adapter output. The closed dimension set makes omissions
/// visible without introducing a second lifecycle owner.
struct C07RoundSessionLifecycleEvidenceV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let session: RoundSessionReferenceV1
    let dimensions: [C07RoundSessionLifecycleDimensionV1]
    let canonicalHistoryReused: Bool
    let derivedOnly: Bool
    let evidenceSHA256: String

    init(session source: RoundSessionV1) throws {
        try source.validateIntrinsic()
        guard C07RoundSessionLifecycleBoundaryV1.validate() else {
            throw C07RoundSessionLifecycleAdapterFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        session = try source.reference
        dimensions = C07RoundSessionLifecycleDimensionV1.allCases.sorted { $0.rawValue < $1.rawValue }
        canonicalHistoryReused = true
        derivedOnly = true
        evidenceSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: schemaVersion,
            session: session,
            dimensions: dimensions,
            canonicalHistoryReused: canonicalHistoryReused,
            derivedOnly: derivedOnly
        ))
        try validate()
    }

    func validate() throws {
        try session.validate()
        guard schemaVersion == Self.schemaVersion,
              dimensions == C07RoundSessionLifecycleDimensionV1.allCases.sorted(by: { $0.rawValue < $1.rawValue }),
              canonicalHistoryReused,
              derivedOnly,
              evidenceSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else {
            throw C07RoundSessionLifecycleAdapterFailureV1.digestMismatch
        }
    }

    private var basis: Basis {
        Basis(schemaVersion: schemaVersion, session: session, dimensions: dimensions,
              canonicalHistoryReused: canonicalHistoryReused, derivedOnly: derivedOnly)
    }
    private struct Basis: Codable {
        let schemaVersion: Int; let session: RoundSessionReferenceV1
        let dimensions: [C07RoundSessionLifecycleDimensionV1]
        let canonicalHistoryReused: Bool; let derivedOnly: Bool
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, session, dimensions, canonicalHistoryReused, derivedOnly, evidenceSHA256
    }
    init(from decoder: Decoder) throws {
        try KernelClosedCodingV1.require(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        session = try c.decode(RoundSessionReferenceV1.self, forKey: .session)
        dimensions = try c.decode([C07RoundSessionLifecycleDimensionV1].self, forKey: .dimensions)
        canonicalHistoryReused = try c.decode(Bool.self, forKey: .canonicalHistoryReused)
        derivedOnly = try c.decode(Bool.self, forKey: .derivedOnly)
        evidenceSHA256 = try c.decode(String.self, forKey: .evidenceSHA256)
        try validate()
    }
}

/// C07 consumes the incumbent C05 lifecycle enrollment rather than declaring
/// another persistent kind, storage owner, or mutation path.
enum C07RoundSessionLifecycleBoundaryV1 {
    static let canonicalWriterIsRoundSessionCoordinatorOnly =
        C05RoundSessionLifecycleBoundaryV1.canonicalWriterIsRoundSessionCoordinatorOnly
    static let reportsRequireCurrentFrontierValidation =
        C05RoundSessionLifecycleBoundaryV1.derivedReportRequiresCurrentFrontierValidation
    static let closeoutRequiresCompletedFullyDispositionedSession =
        C05RoundSessionLifecycleBoundaryV1.closeoutRequiresCompletedFullyDispositionedSession
    static let backupEnrollment: Any.Type = C05RoundSessionBackupEnrollmentV1.self
    static let backupRestoreEnrollment: Any.Type = C05RoundSessionKernelBackupRestoreEnrollmentV1.self
    static let deletionEraseEnrollment: Any.Type = C05RoundSessionKernelDeletionEraseEnrollmentV1.self
    static let searchProjectionBoundary: Any.Type = C05RoundSessionSearchProjectionBoundaryV1.self
    static let searchRebuildBoundary: Any.Type = C05RoundSessionSearchRebuildBoundaryV1.self
    static let reportRecoveryBoundary: Any.Type = C05RoundSessionReportRecoveryBoundaryV1.self
    static let mutationReceiptBoundary: Any.Type = C05RoundSessionKernelMutationReceiptBoundaryV1.self

    static func validate() -> Bool {
        canonicalWriterIsRoundSessionCoordinatorOnly
            && reportsRequireCurrentFrontierValidation
            && closeoutRequiresCompletedFullyDispositionedSession
    }
}

enum C05RoundSessionLifecycleBoundaryV1 {
    static let canonicalWriterIsRoundSessionCoordinatorOnly = true
    static let derivedReportRequiresCurrentFrontierValidation = true
    static let closeoutRequiresCompletedFullyDispositionedSession = true
    static let searchInvalidationOccursAfterCanonicalCommitOnly = true
    static let adapterCreatesNoRendererStoreOrRoute = true
    static let qrRecurrenceDueReminderNetworkAndTeamDispatchAreAbsent = true
}
