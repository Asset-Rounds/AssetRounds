import Foundation

/// Narrow, read-only surface used to resolve the already-validated session
/// frontier. `RoundSessionCoordinatorV1` remains the canonical mutation owner.
@MainActor
protocol OfflineReadinessRoundSessionReadingV1: AnyObject {
    func current(sessionID: UUID) throws -> RoundSessionV1?
    func validateCurrentFrontier(_ reference: RoundSessionReferenceV1) throws -> RoundSessionV1
}

extension RoundSessionCoordinatorV1: OfflineReadinessRoundSessionReadingV1 {}

/// Every dependency here is a readback authority. Implementations are
/// side-effect free while answering a preflight.
@MainActor
protocol OfflineReadinessPreflightAuthorityReadingV1: AnyObject {
    func checkCancellation() throws
    func checkedAt() async throws -> Date
    func timeZoneIdentifier() async throws -> String
    func clockState(
        previous: OfflineReadinessManifestV1?,
        checkedAt: Date,
        timeZoneIdentifier: String
    ) async throws -> OfflineReadinessClockStateV1

    func observedPackage(
        for expected: RoundPackageReleaseReferenceV1
    ) async throws -> RoundPackageReleaseReferenceV1?
    func observedAssetIDs(
        workspaceID: WorkspaceID,
        selectedAssets: [RoundAssetSelectionV1]
    ) async throws -> Set<UUID>
    func guidanceReferenceIDs(
        for expected: RoundPackageReleaseReferenceV1
    ) async throws -> [String]
    func availableGuidanceReferenceIDs(
        for expected: RoundPackageReleaseReferenceV1
    ) async throws -> Set<String>
    func contentObservations(
        for requirements: [OfflineReadinessContentRequirementV1]
    ) async throws -> [OfflineReadinessContentObservationV1]
    /// An empty result is authoritative only when this exact session/package
    /// declares no field-reference requirement.
    func expectedFieldReferenceBindings(
        session: RoundSessionReferenceV1,
        expectedPackage: RoundPackageReleaseReferenceV1
    ) async throws -> [(release: FieldReferenceReleaseV1, binding: FieldReferenceBindingV1)]
    func fieldReferenceReadiness(
        workspaceID: WorkspaceID,
        checkedAt: Date
    ) async throws -> [FieldReferenceOfflineReadinessV1]
    func storageObservation(
        for requirements: [OfflineReadinessContentRequirementV1]
    ) async throws -> OfflineReadinessStorageObservationV1
    func accessObservation() async throws -> OfflineReadinessAccessObservationV1
}

enum OfflineReadinessPreflightCoordinatorFailureV1: Error, Equatable, LocalizedError {
    case currentSessionUnavailable
    case inconsistentSessionRequirements
    case frontierChangedDuringReadback

    var errorDescription: String? {
        switch self {
        case .currentSessionUnavailable:
            "This round is no longer available. Reopen it and run the preflight again."
        case .inconsistentSessionRequirements:
            "This round has inconsistent offline requirements. Do not start it; reselect the round items."
        case .frontierChangedDuringReadback:
            "This round changed while offline readiness was being checked. Run the preflight again."
        }
    }
}

/// Rebuilds a derived-only offline manifest. A new coordinator after
/// termination, unlock, storage retry, or time-zone change simply re-queries
/// its authorities.
@MainActor
final class OfflineReadinessPreflightCoordinatorV1 {
    private let sessionReader: any OfflineReadinessRoundSessionReadingV1
    private let authority: any OfflineReadinessPreflightAuthorityReadingV1

    init(
        sessionReader: any OfflineReadinessRoundSessionReadingV1,
        authority: any OfflineReadinessPreflightAuthorityReadingV1
    ) {
        self.sessionReader = sessionReader
        self.authority = authority
    }

    /// Performs an initial materialized read and a second readback. If either
    /// differs from the prior manifest or from the second read, the returned
    /// derived manifest is explicitly stale; no RoundSession mutation occurs.
    func rebuild(
        sessionID: UUID,
        previous: OfflineReadinessManifestV1? = nil
    ) async throws -> OfflineReadinessManifestV1 {
        try authority.checkCancellation()
        guard let initialSession = try sessionReader.current(sessionID: sessionID) else {
            throw OfflineReadinessPreflightCoordinatorFailureV1.currentSessionUnavailable
        }
        let validatedInitial = try sessionReader.validateCurrentFrontier(initialSession.reference)
        let initialSnapshot = try await materialize(
            session: validatedInitial,
            previous: previous
        )
        let initialManifest = try OfflineReadinessManifestBuilderV1.build(
            snapshot: initialSnapshot,
            previous: previous
        )

        try authority.checkCancellation()
        guard let rereadCandidate = try sessionReader.current(sessionID: sessionID) else {
            throw OfflineReadinessPreflightCoordinatorFailureV1.currentSessionUnavailable
        }
        let rereadSession = try sessionReader.validateCurrentFrontier(rereadCandidate.reference)
        guard try rereadSession.reference == initialSnapshot.session else {
            throw OfflineReadinessPreflightCoordinatorFailureV1.frontierChangedDuringReadback
        }
        let rereadSnapshot = try await materialize(
            session: rereadSession,
            previous: initialManifest
        )

        // Keep the initial stale result visible when it differs from the
        // caller's prior binding. Otherwise compare the second materialized
        // read to the first one, which detects source drift during readback.
        if initialManifest.status == .stale {
            return initialManifest
        }
        return try OfflineReadinessManifestBuilderV1.build(
            snapshot: rereadSnapshot,
            previous: initialManifest
        )
    }

    /// C19's plan-work preflight accepts only a fully materialized immutable
    /// source. It does not select a current plan revision, claim an item, or
    /// persist a readiness Boolean.
    func rebuildPlanOfflineWork(
        source: PlanOfflineWorkSourceV1
    ) throws -> OfflineWorkPacketReadinessV1 {
        try authority.checkCancellation()
        return try OfflineReadinessManifestBuilderV1.buildPlanOfflineWork(source: source)
    }

    func scanToWorkProof(sessionID: UUID, assetID: UUID,
                         previous: OfflineReadinessManifestV1? = nil) async throws -> ScanToWorkOfflineReadinessProofV1 {
        let manifest = try await rebuild(sessionID: sessionID, previous: previous)
        return try manifest.scanToWorkProof(assetID: assetID)
    }

    private func materialize(
        session: RoundSessionV1,
        previous: OfflineReadinessManifestV1?
    ) async throws -> OfflineReadinessSnapshotV1 {
        try authority.checkCancellation()
        let inputs = try requirements(for: session)
        let checkedAt = try await authority.checkedAt()
        try authority.checkCancellation()
        let timeZoneIdentifier = try await authority.timeZoneIdentifier()
        let clockState = try await authority.clockState(
            previous: previous,
            checkedAt: checkedAt,
            timeZoneIdentifier: timeZoneIdentifier
        )

        let expectedPackage = inputs.package
        let observedPackage = try await authority.observedPackage(for: expectedPackage)
        try authority.checkCancellation()
        let observedAssetIDs = try await authority.observedAssetIDs(
            workspaceID: session.workspaceID,
            selectedAssets: inputs.assets
        )
        let guidanceReferenceIDs = try await authority.guidanceReferenceIDs(for: expectedPackage)
        let availableGuidanceReferenceIDs = try await authority.availableGuidanceReferenceIDs(
            for: expectedPackage
        )
        try authority.checkCancellation()
        let contentObservations = try await authority.contentObservations(
            for: inputs.contentRequirements
        )
        let sessionReference = try session.reference
        let expectedBindings = try await authority.expectedFieldReferenceBindings(
            session: sessionReference,
            expectedPackage: expectedPackage
        )
        let expectedFieldReferences = try expectedFieldReferences(
            from: expectedBindings,
            session: session
        )
        try authority.checkCancellation()
        let fieldReferenceReadiness = try await authority.fieldReferenceReadiness(
            workspaceID: session.workspaceID,
            checkedAt: checkedAt
        )
        let storage = try await authority.storageObservation(for: inputs.contentRequirements)
        let access = try await authority.accessObservation()
        try authority.checkCancellation()

        return try OfflineReadinessSnapshotV1(
            session: sessionReference,
            expectedPackage: expectedPackage,
            observedPackage: observedPackage,
            selectedAssets: inputs.assets,
            observedAssetIDs: observedAssetIDs,
            guidanceReferenceIDs: guidanceReferenceIDs.sorted(),
            availableGuidanceReferenceIDs: availableGuidanceReferenceIDs,
            contentRequirements: inputs.contentRequirements,
            contentObservations: contentObservations.sorted { $0.contentID < $1.contentID },
            expectedFieldReferences: expectedFieldReferences,
            fieldReferenceReadiness: fieldReferenceReadiness,
            storage: storage,
            access: access,
            checkedAt: checkedAt,
            timeZoneIdentifier: timeZoneIdentifier,
            clockState: clockState
        )
    }

    private func requirements(
        for session: RoundSessionV1
    ) throws -> (
        package: RoundPackageReleaseReferenceV1,
        assets: [RoundAssetSelectionV1],
        contentRequirements: [OfflineReadinessContentRequirementV1]
    ) {
        guard let package = session.items.first?.requirement.packageRelease,
              session.items.allSatisfy({ $0.requirement.packageRelease == package }) else {
            throw OfflineReadinessPreflightCoordinatorFailureV1.inconsistentSessionRequirements
        }

        let assets = session.items.map(\.selection).sorted {
            $0.assetID.uuidString < $1.assetID.uuidString
        }
        guard Set(assets.map(\.assetID)).count == assets.count else {
            throw OfflineReadinessPreflightCoordinatorFailureV1.inconsistentSessionRequirements
        }

        var referencesByID: [String: ContentReferenceV1] = [:]
        for reference in session.items.flatMap(\.requirement.requiredContent) {
            if let existing = referencesByID[reference.contentID], existing != reference {
                throw OfflineReadinessPreflightCoordinatorFailureV1.inconsistentSessionRequirements
            }
            referencesByID[reference.contentID] = reference
        }
        let contentRequirements = try referencesByID.values
            .sorted { $0.id < $1.id }
            .map { try OfflineReadinessContentRequirementV1(reference: $0, mandatory: true) }
        return (package, assets, contentRequirements)
    }

    private func expectedFieldReferences(
        from bindings: [(release: FieldReferenceReleaseV1, binding: FieldReferenceBindingV1)],
        session: RoundSessionV1
    ) throws -> [OfflineReadinessFieldReferenceRequirementV1] {
        let expected = try bindings.map { source in
            try source.binding.validate(release: source.release)
            guard source.release.workspaceID == session.workspaceID,
                  source.binding.workspaceID == session.workspaceID,
                  source.binding.subjectKind == .roundSession,
                  source.binding.subjectID == session.sessionID else {
                throw OfflineReadinessPreflightCoordinatorFailureV1.inconsistentSessionRequirements
            }
            return try OfflineReadinessFieldReferenceRequirementV1(
                workspaceID: source.binding.workspaceID.rawValue.uuidString.lowercased(),
                releaseID: source.release.releaseID,
                releaseRevision: source.release.revision,
                releaseSHA256: source.release.releaseSHA256,
                manifestSHA256: source.release.manifestSHA256,
                bindingID: source.binding.bindingID,
                bindingRevision: source.binding.revision,
                bindingSHA256: source.binding.bindingSHA256
            )
        }.sorted { $0.releaseID.uuidString < $1.releaseID.uuidString }
        guard Set(expected.map(\.releaseID)).count == expected.count else {
            throw OfflineReadinessPreflightCoordinatorFailureV1.inconsistentSessionRequirements
        }
        return expected
    }
}

/// C17 application boundary for a fully materialized, read-only snapshot.
/// It owns no cache or persistent state and delegates to the sole C06 builder.
enum C17LightingDayOfflineReadinessCoordinatorV1 {
    static let persistenceMode = C17LightingDayOfflineReadinessProjectionV1.persistenceMode
    static let ownsPersistentRow = false
    static let writesCanonicalWorkspaceState = false

    static func rebuild(
        workflow: LightingDayInventoryWorkflowV1,
        source: C17LightingDayReadinessSourceV1,
        snapshot: OfflineReadinessSnapshotV1,
        previous: C17LightingDayOfflineReadinessProjectionV1? = nil
    ) throws -> C17LightingDayOfflineReadinessProjectionV1 {
        guard persistenceMode == "DERIVED_ONLY",
              !ownsPersistentRow,
              !writesCanonicalWorkspaceState else {
            throw OfflineReadinessManifestFailureV1.invalidValue
        }
        return try OfflineReadinessManifestBuilderV1.buildC17LightingDay(
            workflow: workflow, source: source, snapshot: snapshot, previous: previous
        )
    }
}

enum C18LightingNightOfflineReadinessCoordinatorV1{static let persistenceMode=C18LightingNightOfflineReadinessProjectionV1.persistenceMode;static func preflight(workflow:LightingNightWorkflowV1,source:C18LightingNightReadinessSourceV1,storage:OfflineReadinessStorageObservationV1,manifest:OfflineReadinessManifestV1)throws->C18LightingNightOfflineReadinessProjectionV1{try workflow.validateIntrinsic();try source.validate(workflow:workflow,storage:storage);return try C18LightingNightOfflineReadinessProjectionV1(source:source,manifest:manifest)}}
