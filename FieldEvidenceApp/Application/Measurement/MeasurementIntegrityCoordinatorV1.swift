import Foundation

enum MeasurementIntegrityCoordinatorFailureV1: Error, Equatable, Sendable {
    case invalidBundle
    case wrongWorkspace
    case staleRevision
    case receiptMismatch
}

/// One transaction request. This is an application command, not a second
/// persistence writer; production conformers must delegate to WorkspaceWriterV1.
struct MeasurementIntegrityAtomicBundleV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let mutationID: MutationIDV1
    let instruments: [InstrumentReferenceV1]
    let calibrations: [CalibrationStatusSnapshotV1]
    let captures: [MeasurementCaptureV1]
    let series: [MeasurementSeriesV1]
    let assessments: [MeasurementQualityAssessmentV1]
    let bundleSHA256: String

    init(workspaceID: WorkspaceID, mutationID: MutationIDV1,
         instruments: [InstrumentReferenceV1] = [],
         calibrations: [CalibrationStatusSnapshotV1] = [],
         captures: [MeasurementCaptureV1] = [],
         series: [MeasurementSeriesV1] = [],
         assessments: [MeasurementQualityAssessmentV1] = []) throws {
        let instruments = instruments.sorted { $0.referenceID.uuidString < $1.referenceID.uuidString }
        let calibrations = calibrations.sorted { $0.snapshotID.uuidString < $1.snapshotID.uuidString }
        let captures = captures.sorted { $0.captureID.uuidString < $1.captureID.uuidString }
        let series = series.sorted { $0.snapshotID.uuidString < $1.snapshotID.uuidString }
        let assessments = assessments.sorted { $0.assessmentID.uuidString < $1.assessmentID.uuidString }
        self.workspaceID = workspaceID; self.mutationID = mutationID; self.instruments = instruments
        self.calibrations = calibrations; self.captures = captures; self.series = series; self.assessments = assessments
        bundleSHA256 = try MeasurementIntegrityCanonicalCodecV1.sha256(DigestBasis(
            workspaceID: workspaceID, mutationID: mutationID, instruments: instruments,
            calibrations: calibrations, captures: captures, series: series, assessments: assessments))
        try validate()
    }

    func validate() throws {
        let count = instruments.count + calibrations.count + captures.count + series.count + assessments.count
        guard count > 0, count <= 128,
              Set(instruments.map(\.referenceID)).count == instruments.count,
              Set(calibrations.map(\.snapshotID)).count == calibrations.count,
              Set(captures.map(\.captureID)).count == captures.count,
              Set(series.map(\.snapshotID)).count == series.count,
              Set(assessments.map(\.assessmentID)).count == assessments.count else {
            throw MeasurementIntegrityCoordinatorFailureV1.invalidBundle
        }
        try instruments.forEach { try $0.validate() }; try calibrations.forEach { try $0.validate() }
        try captures.forEach { try $0.validate() }; try series.forEach { try $0.validate() }
        try assessments.forEach { try $0.validate() }
        let workspaces = instruments.map(\.workspaceID) + calibrations.map(\.workspaceID)
            + captures.map(\.workspaceID) + series.map(\.workspaceID) + assessments.map(\.workspaceID)
        let mutationIDs = instruments.map(\.mutationID) + calibrations.map(\.mutationID)
            + captures.map(\.mutationID) + series.map(\.mutationID) + assessments.map(\.mutationID)
        guard workspaces.allSatisfy({ $0 == workspaceID }), mutationIDs.allSatisfy({ $0 == mutationID }),
              bundleSHA256 == (try MeasurementIntegrityCanonicalCodecV1.sha256(digestBasis)) else {
            throw MeasurementIntegrityCoordinatorFailureV1.wrongWorkspace
        }
    }

    private var digestBasis: DigestBasis { .init(workspaceID: workspaceID, mutationID: mutationID,
        instruments: instruments, calibrations: calibrations, captures: captures, series: series,
        assessments: assessments) }
    private struct DigestBasis: Codable { let workspaceID:WorkspaceID;let mutationID:MutationIDV1;let instruments:[InstrumentReferenceV1];let calibrations:[CalibrationStatusSnapshotV1];let captures:[MeasurementCaptureV1];let series:[MeasurementSeriesV1];let assessments:[MeasurementQualityAssessmentV1] }
}

struct MeasurementIntegrityWriteReceiptV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let mutationID: MutationIDV1
    let bundleSHA256: String
    let journalReceiptSHA256: String

    init(workspaceID: WorkspaceID, mutationID: MutationIDV1, bundleSHA256: String,
         journalReceiptSHA256: String) throws {
        guard MutationEnvelopeV1.isSHA256(bundleSHA256), MutationEnvelopeV1.isSHA256(journalReceiptSHA256) else {
            throw MeasurementIntegrityCoordinatorFailureV1.receiptMismatch
        }
        self.workspaceID = workspaceID; self.mutationID = mutationID
        self.bundleSHA256 = bundleSHA256; self.journalReceiptSHA256 = journalReceiptSHA256
    }
}

protocol MeasurementIntegrityWorkspaceWriterV1: Sendable {
    /// Must be implemented by the existing sole workspace writer in one
    /// transaction with its mutation receipt and journal publication.
    func commitMeasurementIntegrity(_ bundle: MeasurementIntegrityAtomicBundleV1) async throws
        -> MeasurementIntegrityWriteReceiptV1
}

enum MeasurementIntegrityCoordinatorV1 {
    static func prepare(workspaceID: WorkspaceID, mutationID: MutationIDV1,
                        instruments: [InstrumentReferenceV1] = [],
                        calibrations: [CalibrationStatusSnapshotV1] = [],
                        captures: [MeasurementCaptureV1] = [],
                        series: [MeasurementSeriesV1] = [],
                        assessments: [MeasurementQualityAssessmentV1] = []) throws
        -> MeasurementIntegrityAtomicBundleV1 {
        try .init(workspaceID: workspaceID, mutationID: mutationID, instruments: instruments,
                  calibrations: calibrations, captures: captures, series: series, assessments: assessments)
    }

    static func validate(_ receipt: MeasurementIntegrityWriteReceiptV1,
                         for bundle: MeasurementIntegrityAtomicBundleV1) throws {
        try bundle.validate()
        guard receipt.workspaceID == bundle.workspaceID, receipt.mutationID == bundle.mutationID,
              receipt.bundleSHA256 == bundle.bundleSHA256 else {
            throw MeasurementIntegrityCoordinatorFailureV1.receiptMismatch
        }
    }

    static func captureBundle(workspaceID: WorkspaceID, mutationID: MutationIDV1,
                              instrument: InstrumentReferenceV1?, calibration: CalibrationStatusSnapshotV1?,
                              capture: MeasurementCaptureV1, fieldDefinition: ResponseFieldDefinitionV1,
                              assessment: MeasurementQualityAssessmentV1?) throws -> MeasurementIntegrityAtomicBundleV1 {
        try capture.validate(fieldDefinition: fieldDefinition)
        try capture.validateClosure(instrument: instrument, calibration: calibration)
        if let assessment {
            try assessment.validate()
            guard assessment.subjectKind == .capture, assessment.subjectID == capture.captureID,
                  assessment.subjectRevision == capture.revision,
                  assessment.subjectSHA256 == capture.captureSHA256 else {
                throw MeasurementIntegrityCoordinatorFailureV1.invalidBundle
            }
        }
        return try prepare(workspaceID: workspaceID, mutationID: mutationID,
                           instruments: instrument.map { [$0] } ?? [],
                           calibrations: calibration.map { [$0] } ?? [], captures: [capture],
                           assessments: assessment.map { [$0] } ?? [])
    }
}
