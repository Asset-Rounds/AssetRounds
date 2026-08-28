import Foundation
import SwiftData

@Model
final class DeletionLedgerRow {
    var schemaVersion: Int
    @Attribute(.unique) var typedID: String
    var deletedAt: Date

    init(typedID: String, deletedAt: Date, schemaVersion: Int = 2) {
        self.schemaVersion = schemaVersion
        self.typedID = typedID
        self.deletedAt = deletedAt
    }
}

@Model
final class WorkflowRecord {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var assetID: UUID
    var packetID: UUID?
    var issueID: UUID?
    var parentRecordID: UUID?
    private(set) var recordRevisionRootID: UUID
    var revisesRecordID: UUID?
    var evidenceSourceRecordID: UUID?
    var revisionKind: String
    var stage: String
    var state: String
    var draftStepKey: String?
    var startedAt: Date
    var completedAt: Date?
    var observedAtUTC: Date?
    var timeZoneID: String?
    var utcOffsetMinutes: Int?
    var localDate: String?
    var localTime: String?
    var afterDarkAcknowledgementKey: String?
    var afterDarkAcknowledgementCopy: String?
    var afterDarkAcknowledgementVersion: String?
    var afterDarkAcknowledgementAccepted: Bool?
    var safePositionAcknowledgementKey: String?
    var safePositionAcknowledgementCopy: String?
    var safePositionAcknowledgementVersion: String?
    var safePositionAcknowledgementAccepted: Bool?
    var packID: String
    var packSchemaVersion: Int
    var packContentVersion: Int
    var pdfTemplateID: String
    var pdfTemplateVersion: Int
    var outcomeKey: String?
    var couldNotVerifyKey: String?
    var couldNotVerifyDisplaySnapshot: String?
    var couldNotVerifyRegistryVersion: String?
    var workPerformedLocalDate: String?
    var workDescription: String?
    var note: String?
    @Attribute(.unique) var finalizationMutationID: UUID?

    init(
        id: UUID,
        assetID: UUID,
        packetID: UUID?,
        issueID: UUID?,
        parentRecordID: UUID?,
        recordRevisionRootID: UUID,
        revisesRecordID: UUID?,
        evidenceSourceRecordID: UUID?,
        revisionKind: WorkflowRevisionKind,
        stage: WorkflowStage,
        state: WorkflowState,
        draftStepKey: WorkflowDraftStep?,
        startedAt: Date,
        completedAt: Date?,
        observedAtUTC: Date?,
        timeZoneID: String?,
        utcOffsetMinutes: Int?,
        localDate: String?,
        localTime: String?,
        afterDarkAcknowledgementKey: String?,
        afterDarkAcknowledgementCopy: String?,
        afterDarkAcknowledgementVersion: String?,
        afterDarkAcknowledgementAccepted: Bool?,
        safePositionAcknowledgementKey: String?,
        safePositionAcknowledgementCopy: String?,
        safePositionAcknowledgementVersion: String?,
        safePositionAcknowledgementAccepted: Bool?,
        packID: String,
        packSchemaVersion: Int,
        packContentVersion: Int,
        pdfTemplateID: String,
        pdfTemplateVersion: Int,
        outcomeKey: String?,
        couldNotVerifyKey: String?,
        couldNotVerifyDisplaySnapshot: String?,
        couldNotVerifyRegistryVersion: String?,
        workPerformedLocalDate: String?,
        workDescription: String?,
        note: String?,
        finalizationMutationID: UUID?
    ) {
        self.id = id
        self.schemaVersion = 1
        self.assetID = assetID
        self.packetID = packetID
        self.issueID = issueID
        self.parentRecordID = parentRecordID
        self.recordRevisionRootID = recordRevisionRootID
        self.revisesRecordID = revisesRecordID
        self.evidenceSourceRecordID = evidenceSourceRecordID
        self.revisionKind = revisionKind.rawValue
        self.stage = stage.rawValue
        self.state = state.rawValue
        self.draftStepKey = draftStepKey?.rawValue
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.observedAtUTC = observedAtUTC
        self.timeZoneID = timeZoneID
        self.utcOffsetMinutes = utcOffsetMinutes
        self.localDate = localDate
        self.localTime = localTime
        self.afterDarkAcknowledgementKey = afterDarkAcknowledgementKey
        self.afterDarkAcknowledgementCopy = afterDarkAcknowledgementCopy
        self.afterDarkAcknowledgementVersion = afterDarkAcknowledgementVersion
        self.afterDarkAcknowledgementAccepted = afterDarkAcknowledgementAccepted
        self.safePositionAcknowledgementKey = safePositionAcknowledgementKey
        self.safePositionAcknowledgementCopy = safePositionAcknowledgementCopy
        self.safePositionAcknowledgementVersion = safePositionAcknowledgementVersion
        self.safePositionAcknowledgementAccepted = safePositionAcknowledgementAccepted
        self.packID = packID
        self.packSchemaVersion = packSchemaVersion
        self.packContentVersion = packContentVersion
        self.pdfTemplateID = pdfTemplateID
        self.pdfTemplateVersion = pdfTemplateVersion
        self.outcomeKey = outcomeKey
        self.couldNotVerifyKey = couldNotVerifyKey
        self.couldNotVerifyDisplaySnapshot = couldNotVerifyDisplaySnapshot
        self.couldNotVerifyRegistryVersion = couldNotVerifyRegistryVersion
        self.workPerformedLocalDate = workPerformedLocalDate
        self.workDescription = workDescription
        self.note = note
        self.finalizationMutationID = finalizationMutationID
    }
}

@Model
final class EvidenceFile {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var recordID: UUID
    var purposeKey: String
    var relativePath: String
    var mimeType: String
    var byteCount: Int
    var sha256: String
    var createdAt: Date
    var thumbnailRelativePath: String
    var thumbnailByteCount: Int
    var thumbnailSHA256: String

    init(
        id: UUID,
        recordID: UUID,
        purposeKey: String,
        relativePath: String,
        mimeType: String,
        byteCount: Int,
        sha256: String,
        createdAt: Date,
        thumbnailRelativePath: String,
        thumbnailByteCount: Int,
        thumbnailSHA256: String
    ) {
        self.id = id
        self.schemaVersion = 1
        self.recordID = recordID
        self.purposeKey = purposeKey
        self.relativePath = relativePath
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.sha256 = sha256
        self.createdAt = createdAt
        self.thumbnailRelativePath = thumbnailRelativePath
        self.thumbnailByteCount = thumbnailByteCount
        self.thumbnailSHA256 = thumbnailSHA256
    }
}

// MARK: - C19 workflow binding

extension WorkflowRecord {
    /// The frozen V4 SwiftData row remains unchanged. C19 measurements bind
    /// through the existing package identity and do not add a parallel
    /// workflow store or outcome-derived compliance state.
    func c19ValidateMeasurementCapture(
        _ capture: MeasurementCaptureV1,
        against release: InspectionPackageReleaseV1
    ) throws {
        try release.c19ValidateMeasurementCapture(capture)
        guard packID == release.packageID,
              packContentVersion == release.packageContentVersion else {
            throw MeasurementIntegrityFailureV1.staleReference
        }
    }
}

@Model
final class Issue {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var assetID: UUID
    var openedByRecordID: UUID
    private(set) var labelKey: String
    private(set) var labelDisplaySnapshot: String
    var status: String
    var resolvedByRecordID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        assetID: UUID,
        openedByRecordID: UUID,
        labelKey: String,
        labelDisplaySnapshot: String,
        status: IssueStatus,
        resolvedByRecordID: UUID?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.schemaVersion = 1
        self.assetID = assetID
        self.openedByRecordID = openedByRecordID
        self.labelKey = labelKey
        self.labelDisplaySnapshot = labelDisplaySnapshot
        self.status = status.rawValue
        self.resolvedByRecordID = resolvedByRecordID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class Packet {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    @Attribute(.unique) private(set) var stableRootID: UUID
    var currentRecordID: UUID?
    var evaluationCounted: Bool
    var contentDeletedAt: Date?
    var createdAt: Date

    init(
        id: UUID,
        stableRootID: UUID,
        currentRecordID: UUID?,
        evaluationCounted: Bool,
        contentDeletedAt: Date?,
        createdAt: Date
    ) {
        self.id = id
        self.schemaVersion = 1
        self.stableRootID = stableRootID
        self.currentRecordID = currentRecordID
        self.evaluationCounted = evaluationCounted
        self.contentDeletedAt = contentDeletedAt
        self.createdAt = createdAt
    }
}

@Model
final class Report {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    private(set) var packetID: UUID
    private(set) var sourceRecordID: UUID
    private(set) var snapshotSchemaVersion: Int
    private(set) var snapshotRelativePath: String
    private(set) var snapshotSHA256: String
    var pdfState: String
    var pdfRelativePath: String?
    var pdfSHA256: String?
    private(set) var createdAt: Date
    private(set) var replacesReportID: UUID?

    init(
        id: UUID,
        packetID: UUID,
        sourceRecordID: UUID,
        snapshotSchemaVersion: Int,
        snapshotRelativePath: String,
        snapshotSHA256: String,
        pdfState: ReportPDFState,
        pdfRelativePath: String?,
        pdfSHA256: String?,
        createdAt: Date,
        replacesReportID: UUID?
    ) {
        self.id = id
        self.schemaVersion = 1
        self.packetID = packetID
        self.sourceRecordID = sourceRecordID
        self.snapshotSchemaVersion = snapshotSchemaVersion
        self.snapshotRelativePath = snapshotRelativePath
        self.snapshotSHA256 = snapshotSHA256
        self.pdfState = pdfState.rawValue
        self.pdfRelativePath = pdfRelativePath
        self.pdfSHA256 = pdfSHA256
        self.createdAt = createdAt
        self.replacesReportID = replacesReportID
    }
}
