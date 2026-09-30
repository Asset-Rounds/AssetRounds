import Foundation
import SwiftData

enum MeasurementIntegrityPersistenceFailureV1: Error { case corruptRow }

private enum MeasurementIntegrityPersistenceCodecV1 {
    static func decode<T: Codable>(_ type: T.Type, _ data: Data) throws -> T {
        try MeasurementIntegrityCanonicalCodecV1.decode(type, from: data)
    }
}

@Model final class InstrumentReferenceRow {
    @Attribute(.unique) var referenceID: UUID; var instrumentID: UUID; var workspaceID: UUID; var revision: UInt64; var mutationID: UUID; var referenceSHA256: String; var canonicalData: Data
    init(_ value: InstrumentReferenceV1) throws { try value.validate(); referenceID=value.referenceID;instrumentID=value.instrumentID;workspaceID=value.workspaceID.rawValue;revision=value.revision;mutationID=value.mutationID.rawValue;referenceSHA256=value.referenceSHA256;canonicalData=try MeasurementIntegrityCanonicalCodecV1.encode(value) }
    func value() throws -> InstrumentReferenceV1 { let v:InstrumentReferenceV1=try MeasurementIntegrityPersistenceCodecV1.decode(InstrumentReferenceV1.self,canonicalData);guard v.referenceID==referenceID,v.instrumentID==instrumentID,v.workspaceID.rawValue==workspaceID,v.revision==revision,v.mutationID.rawValue==mutationID,v.referenceSHA256==referenceSHA256 else{throw MeasurementIntegrityPersistenceFailureV1.corruptRow};return v }
}

@Model final class CalibrationStatusSnapshotRow {
    @Attribute(.unique) var snapshotID: UUID; var workspaceID: UUID; var instrumentID: UUID; var revision: UInt64; var mutationID: UUID; var snapshotSHA256: String; var canonicalData: Data
    init(_ value: CalibrationStatusSnapshotV1) throws { try value.validate();snapshotID=value.snapshotID;workspaceID=value.workspaceID.rawValue;instrumentID=value.instrument.instrumentID;revision=value.revision;mutationID=value.mutationID.rawValue;snapshotSHA256=value.snapshotSHA256;canonicalData=try MeasurementIntegrityCanonicalCodecV1.encode(value) }
    func value() throws -> CalibrationStatusSnapshotV1 { let v:CalibrationStatusSnapshotV1=try MeasurementIntegrityPersistenceCodecV1.decode(CalibrationStatusSnapshotV1.self,canonicalData);guard v.snapshotID==snapshotID,v.workspaceID.rawValue==workspaceID,v.instrument.instrumentID==instrumentID,v.revision==revision,v.mutationID.rawValue==mutationID,v.snapshotSHA256==snapshotSHA256 else{throw MeasurementIntegrityPersistenceFailureV1.corruptRow};return v }
}

@Model final class MeasurementCaptureRow {
    @Attribute(.unique) var captureID: UUID; var workspaceID: UUID; var revision: UInt64; var mutationID: UUID; var captureSHA256: String; var canonicalData: Data
    init(_ value: MeasurementCaptureV1) throws { try value.validate();captureID=value.captureID;workspaceID=value.workspaceID.rawValue;revision=value.revision;mutationID=value.mutationID.rawValue;captureSHA256=value.captureSHA256;canonicalData=try MeasurementIntegrityCanonicalCodecV1.encode(value) }
    func value() throws -> MeasurementCaptureV1 { let v:MeasurementCaptureV1=try MeasurementIntegrityPersistenceCodecV1.decode(MeasurementCaptureV1.self,canonicalData);guard v.captureID==captureID,v.workspaceID.rawValue==workspaceID,v.revision==revision,v.mutationID.rawValue==mutationID,v.captureSHA256==captureSHA256 else{throw MeasurementIntegrityPersistenceFailureV1.corruptRow};return v }
}

@Model final class MeasurementSeriesRow {
    @Attribute(.unique) var snapshotID: UUID; var seriesID: UUID; var workspaceID: UUID; var revision: UInt64; var mutationID: UUID; var seriesSHA256: String; var canonicalData: Data
    init(_ value: MeasurementSeriesV1) throws { try value.validate();snapshotID=value.snapshotID;seriesID=value.seriesID;workspaceID=value.workspaceID.rawValue;revision=value.revision;mutationID=value.mutationID.rawValue;seriesSHA256=value.seriesSHA256;canonicalData=try MeasurementIntegrityCanonicalCodecV1.encode(value) }
    func value() throws -> MeasurementSeriesV1 { let v:MeasurementSeriesV1=try MeasurementIntegrityPersistenceCodecV1.decode(MeasurementSeriesV1.self,canonicalData);guard v.snapshotID==snapshotID,v.seriesID==seriesID,v.workspaceID.rawValue==workspaceID,v.revision==revision,v.mutationID.rawValue==mutationID,v.seriesSHA256==seriesSHA256 else{throw MeasurementIntegrityPersistenceFailureV1.corruptRow};return v }
}

@Model final class MeasurementQualityAssessmentRow {
    @Attribute(.unique) var assessmentID: UUID; var workspaceID: UUID; var subjectID: UUID; var revision: UInt64; var mutationID: UUID; var assessmentSHA256: String; var canonicalData: Data
    init(_ value: MeasurementQualityAssessmentV1) throws { try value.validate();assessmentID=value.assessmentID;workspaceID=value.workspaceID.rawValue;subjectID=value.subjectID;revision=value.revision;mutationID=value.mutationID.rawValue;assessmentSHA256=value.assessmentSHA256;canonicalData=try MeasurementIntegrityCanonicalCodecV1.encode(value) }
    func value() throws -> MeasurementQualityAssessmentV1 { let v:MeasurementQualityAssessmentV1=try MeasurementIntegrityPersistenceCodecV1.decode(MeasurementQualityAssessmentV1.self,canonicalData);guard v.assessmentID==assessmentID,v.workspaceID.rawValue==workspaceID,v.subjectID==subjectID,v.revision==revision,v.mutationID.rawValue==mutationID,v.assessmentSHA256==assessmentSHA256 else{throw MeasurementIntegrityPersistenceFailureV1.corruptRow};return v }
}

enum C53SharedMeasurementPersistenceBoundaryV1 {
    static let exposureType: QualifiedServiceExposureV1.Type = QualifiedServiceExposureV1.self
    static let c19MeasurementRowsRemainCanonical = true
    static let c53ReliabilityRowsAreNotStoredInMeasurementModels = true
    static let canonicalDataDigestAndRevisionAreValidated = true
    static let crossWorkspaceOrDuplicateEvidenceFailsClosed = true
    static let derivedReliabilityProjectionIsNotPersistedHere = true
    static let sourceContractNames = C53SharedServiceReliabilitySemanticBoundaryV1.contractNames
}
