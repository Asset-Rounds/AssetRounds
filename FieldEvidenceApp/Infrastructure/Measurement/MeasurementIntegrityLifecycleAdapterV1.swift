import Foundation

/// C19 application adapter. It owns no store and delegates every durable
/// publication to the injected sole-writer conformance.
@MainActor
final class MeasurementIntegrityLifecycleAdapterV1 {
    private let workspaceID: WorkspaceID
    private let writer: any MeasurementIntegrityWorkspaceWriterV1

    init(workspaceID: WorkspaceID, writer: any MeasurementIntegrityWorkspaceWriterV1) {
        self.workspaceID = workspaceID; self.writer = writer
    }

    func commit(_ bundle: MeasurementIntegrityAtomicBundleV1) async throws
        -> MeasurementIntegrityWriteReceiptV1 {
        try bundle.validate()
        guard bundle.workspaceID == workspaceID else { throw MeasurementIntegrityCoordinatorFailureV1.wrongWorkspace }
        let receipt = try await writer.commitMeasurementIntegrity(bundle)
        try MeasurementIntegrityCoordinatorV1.validate(receipt, for: bundle)
        return receipt
    }

    func recordCapture(mutationID: MutationIDV1, instrument: InstrumentReferenceV1? = nil,
                       calibration: CalibrationStatusSnapshotV1? = nil,
                       capture: MeasurementCaptureV1, fieldDefinition: ResponseFieldDefinitionV1,
                       assessment: MeasurementQualityAssessmentV1? = nil) async throws
        -> MeasurementIntegrityWriteReceiptV1 {
        let bundle = try MeasurementIntegrityCoordinatorV1.captureBundle(
            workspaceID: workspaceID, mutationID: mutationID, instrument: instrument,
            calibration: calibration, capture: capture, fieldDefinition: fieldDefinition,
            assessment: assessment)
        return try await commit(bundle)
    }
}

enum MeasurementIntegrityLifecycleDispositionV1: String, Codable, CaseIterable, Sendable {
    case canonicalPersistent = "CANONICAL_PERSISTENT"
    case nonpersistentProjection = "NONPERSISTENT_PROJECTION"
}

enum MeasurementIntegrityLifecycleCatalogV1 {
    static let persistentKinds = [
        "INSTRUMENT_REFERENCE_V1", "CALIBRATION_STATUS_SNAPSHOT_V1", "MEASUREMENT_CAPTURE_V1",
        "MEASUREMENT_SERIES_V1", "MEASUREMENT_QUALITY_ASSESSMENT_V1"
    ]
    static let nonpersistentKinds = ["INSTALLATION_PLAN_REFERENCE_V1", "PUNCH_PLAN_REFERENCE_V1"]

    static func disposition(for kind: String) -> MeasurementIntegrityLifecycleDispositionV1? {
        if persistentKinds.contains(kind) { return .canonicalPersistent }
        if nonpersistentKinds.contains(kind) { return .nonpersistentProjection }
        return nil
    }
}
