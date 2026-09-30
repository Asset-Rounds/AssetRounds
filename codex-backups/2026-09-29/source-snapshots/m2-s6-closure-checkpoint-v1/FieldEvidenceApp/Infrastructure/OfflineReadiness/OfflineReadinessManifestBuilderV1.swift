import Foundation

/// Fully materialized input for the derived-only preflight. Acquisition belongs
/// to the coordinator; this value deliberately performs no external access.
struct OfflineReadinessSnapshotV1: Sendable {
    let session: RoundSessionReferenceV1
    let expectedPackage: RoundPackageReleaseReferenceV1
    let observedPackage: RoundPackageReleaseReferenceV1?
    let selectedAssets: [RoundAssetSelectionV1]
    let observedAssetIDs: Set<UUID>
    /// Required package-bound local guidance identities.
    let guidanceReferenceIDs: [String]
    /// Closed observation set for locally available package guidance identities.
    let availableGuidanceReferenceIDs: Set<String>
    let contentRequirements: [OfflineReadinessContentRequirementV1]
    /// Closed observation set: exactly one observation for every requirement.
    let contentObservations: [OfflineReadinessContentObservationV1]
    /// Required exact field-reference release/binding identities.
    let expectedFieldReferences: [OfflineReadinessFieldReferenceRequirementV1]
    /// Closed subset of observations for the declared field-reference identities.
    let fieldReferenceReadiness: [FieldReferenceOfflineReadinessV1]
    let storage: OfflineReadinessStorageObservationV1
    let access: OfflineReadinessAccessObservationV1
    let checkedAt: Date
    let timeZoneIdentifier: String
    let clockState: OfflineReadinessClockStateV1

    init(session: RoundSessionReferenceV1, expectedPackage: RoundPackageReleaseReferenceV1, observedPackage: RoundPackageReleaseReferenceV1?, selectedAssets: [RoundAssetSelectionV1], observedAssetIDs: Set<UUID>, guidanceReferenceIDs: [String], availableGuidanceReferenceIDs: Set<String>, contentRequirements: [OfflineReadinessContentRequirementV1], contentObservations: [OfflineReadinessContentObservationV1], expectedFieldReferences: [OfflineReadinessFieldReferenceRequirementV1], fieldReferenceReadiness: [FieldReferenceOfflineReadinessV1], storage: OfflineReadinessStorageObservationV1, access: OfflineReadinessAccessObservationV1, checkedAt: Date, timeZoneIdentifier: String, clockState: OfflineReadinessClockStateV1) throws {
        try session.validate()
        try expectedPackage.validate()
        try observedPackage?.validate()
        let observedReferences = try fieldReferenceReadiness.map(OfflineReadinessReferenceObservationV1.init)
        guard selectedAssets.count <= OfflineReadinessManifestLimitsV1.maximumAssets,
              selectedAssets == selectedAssets.sorted(by: { $0.assetID.uuidString < $1.assetID.uuidString }),
              Set(selectedAssets.map(\.assetID)).count == selectedAssets.count,
              observedAssetIDs.count <= OfflineReadinessManifestLimitsV1.maximumAssets,
              guidanceReferenceIDs.count <= OfflineReadinessManifestLimitsV1.maximumGuidanceReferences,
              guidanceReferenceIDs == guidanceReferenceIDs.sorted(),
              Set(guidanceReferenceIDs).count == guidanceReferenceIDs.count,
              guidanceReferenceIDs.allSatisfy(offlineReadinessTokenV1),
              availableGuidanceReferenceIDs.count <= OfflineReadinessManifestLimitsV1.maximumGuidanceReferences,
              availableGuidanceReferenceIDs.allSatisfy(offlineReadinessTokenV1),
              availableGuidanceReferenceIDs.isSubset(of: Set(guidanceReferenceIDs)),
              contentRequirements.count <= OfflineReadinessManifestLimitsV1.maximumContentRequirements,
              contentRequirements == contentRequirements.sorted(by: { $0.reference.id < $1.reference.id }),
              Set(contentRequirements.map { $0.reference.id }).count == contentRequirements.count,
              contentObservations.count == contentRequirements.count,
              contentObservations == contentObservations.sorted(by: { $0.contentID < $1.contentID }),
              Set(contentObservations.map(\.contentID)) == Set(contentRequirements.map { $0.reference.contentID }),
              expectedFieldReferences.count <= OfflineReadinessManifestLimitsV1.maximumFieldReferences,
              expectedFieldReferences == expectedFieldReferences.sorted(by: { $0.releaseID.uuidString < $1.releaseID.uuidString }),
              Set(expectedFieldReferences.map(\.releaseID)).count == expectedFieldReferences.count,
              fieldReferenceReadiness.count <= OfflineReadinessManifestLimitsV1.maximumFieldReferences,
              Set(observedReferences.map(\.releaseID)).count == observedReferences.count,
              Set(observedReferences.map(\.releaseID)).isSubset(of: Set(expectedFieldReferences.map(\.releaseID))),
              checkedAt.timeIntervalSinceReferenceDate.isFinite,
              offlineReadinessTokenV1(timeZoneIdentifier) else {
            throw OfflineReadinessManifestFailureV1.invalidValue
        }
        self.session = session
        self.expectedPackage = expectedPackage
        self.observedPackage = observedPackage
        self.selectedAssets = selectedAssets
        self.observedAssetIDs = observedAssetIDs
        self.guidanceReferenceIDs = guidanceReferenceIDs
        self.availableGuidanceReferenceIDs = availableGuidanceReferenceIDs
        self.contentRequirements = contentRequirements
        self.contentObservations = contentObservations
        self.expectedFieldReferences = expectedFieldReferences
        self.fieldReferenceReadiness = fieldReferenceReadiness
        self.storage = storage
        self.access = access
        self.checkedAt = checkedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.clockState = clockState
    }
}

enum OfflineReadinessManifestBuilderV1 {
    static func scanToWorkProof(manifest: OfflineReadinessManifestV1,
                                assetID: UUID) throws -> ScanToWorkOfflineReadinessProofV1 {
        try manifest.scanToWorkProof(assetID: assetID)
    }
    /// C19 composes an explicit historic source tuple. The result is derived
    /// on demand and records no durable readiness Boolean.
    static func buildPlanOfflineWork(
        source: PlanOfflineWorkSourceV1
    ) throws -> OfflineWorkPacketReadinessV1 {
        try source.validate()
        return try OfflineWorkPacketReadinessV1(source: source)
    }

    /// C22 consumes only fully materialized incumbent readiness values. This
    /// is a pure binding check, not a second readiness store or writer.
    static func recurringRoundReadiness(
        request: RecurringRoundStartRequestV1,
        roundManifest: OfflineReadinessManifestV1? = nil,
        workPacketReadiness: OfflineWorkPacketReadinessV1? = nil
    ) throws -> RecurringRoundStartReadinessV1 {
        try .init(
            request: request,
            roundManifest: roundManifest,
            workPacketReadiness: workPacketReadiness
        )
    }

    static func build(snapshot: OfflineReadinessSnapshotV1, previous: OfflineReadinessManifestV1? = nil) throws -> OfflineReadinessManifestV1 {
        let referenceObservations = try snapshot.fieldReferenceReadiness
            .map(OfflineReadinessReferenceObservationV1.init)
            .sorted { $0.releaseID.uuidString < $1.releaseID.uuidString }
        if let previous {
            try previous.validate()
        }
        let input = OfflineReadinessManifestReductionInputV1(
            session: snapshot.session,
            expectedPackage: snapshot.expectedPackage,
            observedPackage: snapshot.observedPackage,
            selectedAssets: snapshot.selectedAssets,
            observedAssetIDs: snapshot.observedAssetIDs.sorted { $0.uuidString < $1.uuidString },
            guidanceReferenceIDs: snapshot.guidanceReferenceIDs,
            availableGuidanceReferenceIDs: snapshot.availableGuidanceReferenceIDs.sorted(),
            contentRequirements: snapshot.contentRequirements,
            contentObservations: snapshot.contentObservations,
            expectedFieldReferences: snapshot.expectedFieldReferences,
            referenceObservations: referenceObservations,
            storage: snapshot.storage,
            access: snapshot.access,
            timeZoneIdentifier: snapshot.timeZoneIdentifier,
            clockState: snapshot.clockState,
            priorSourceSnapshotSHA256: previous?.sourceSnapshotSHA256
        )
        let reduction = try OfflineReadinessManifestReducerV1.reduce(input)
        return try OfflineReadinessManifestV1(
            session: snapshot.session,
            expectedPackage: snapshot.expectedPackage,
            observedPackage: snapshot.observedPackage,
            selectedAssets: snapshot.selectedAssets,
            observedAssetIDs: input.observedAssetIDs,
            guidanceReferenceIDs: snapshot.guidanceReferenceIDs,
            availableGuidanceReferenceIDs: input.availableGuidanceReferenceIDs,
            contentRequirements: snapshot.contentRequirements,
            contentObservations: snapshot.contentObservations,
            expectedFieldReferences: snapshot.expectedFieldReferences,
            referenceObservations: referenceObservations,
            requiredBytes: reduction.requiredBytes,
            availableBytes: snapshot.storage.availableBytes,
            storage: snapshot.storage,
            protectedDataAvailable: snapshot.access.protectedDataAvailable,
            checkedAt: snapshot.checkedAt,
            timeZoneIdentifier: snapshot.timeZoneIdentifier,
            clockState: snapshot.clockState,
            sourceSnapshotSHA256: reduction.sourceSnapshotSHA256,
            priorSourceSnapshotSHA256: input.priorSourceSnapshotSHA256,
            requirements: reduction.requirements,
            status: reduction.status
        )
    }

    static func buildC17LightingDay(
        workflow: LightingDayInventoryWorkflowV1,
        source: C17LightingDayReadinessSourceV1,
        snapshot: OfflineReadinessSnapshotV1,
        previous: C17LightingDayOfflineReadinessProjectionV1? = nil
    ) throws -> C17LightingDayOfflineReadinessProjectionV1 {
        try source.validate(workflow: workflow, storage: snapshot.storage)
        try previous?.validate()
        let manifest = try build(snapshot: snapshot, previous: previous?.manifest)
        return try C17LightingDayOfflineReadinessProjectionV1(
            source: source, manifest: manifest
        )
    }

}

extension OfflineReadinessManifestBuilderV1{static func buildC18LightingNight(workflow:LightingNightWorkflowV1,source:C18LightingNightReadinessSourceV1,storage:OfflineReadinessStorageObservationV1,manifest:OfflineReadinessManifestV1)throws->C18LightingNightOfflineReadinessProjectionV1{try source.validate(workflow:workflow,storage:storage);return try .init(source:source,manifest:manifest)}}
