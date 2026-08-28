import Foundation

struct ReportSnapshotV1: Codable, Equatable, Sendable {
    let acknowledgements: [AcknowledgementSnapshotV1]
    let asset: AssetSnapshotV1
    let couldNotVerify: CouldNotVerifySnapshotV1?
    let disclaimer: String
    let display: DisplaySnapshotV1
    let evidence: [EvidenceSnapshotV1]
    let evidenceSourceRecordID: UUID
    let history: [HistoryEntrySnapshotV1]
    let issues: [IssueSnapshotV1]
    let note: String?
    var observationBasis: ObservationBasisV1? = nil
    let outcome: String
    let pack: PackSnapshotV1
    let packetID: UUID
    let pdfTemplate: PDFTemplateReferenceV1
    let reportID: UUID
    let site: SiteSnapshotV1
    let snapshotCreatedAt: Date
    let snapshotSchemaVersion: Int
    let sourceApp: SourceAppSnapshotV1
    let sourceRecordID: UUID
    let stableRootID: UUID
    let stage: String
    var temporalContext: TemporalContextV1? = nil
    let timeContext: TimeContextSnapshotV1
    /// Optional, frozen requirement-assurance projection.  A missing value is
    /// the legacy snapshot shape; activation and production population remain
    /// owned by a later release surface.
    var requirementAssurance: RequirementAssuranceSnapshotV1? = nil
    /// Optional C38 accountability projection.  It freezes only recorded
    /// party/role/actor/qualification/signoff values and never asserts
    /// identity, authorization, legal effect, or external verification.
    var accountability: CompletedAccountabilitySnapshotV1? = nil
    /// Optional C39 asset-semantic projection.  It is a frozen view of
    /// canonical semantic/product/lifecycle/work-subject records only.
    var assetSemantics: CompletedAssetSemanticsSnapshotV1? = nil
    /// Optional C40 frozen authority, applicability, assessment, classification,
    /// severity, measurement-protocol, and derived-fact projection.
    var authorityCriterion: CompletedAuthorityCriterionSnapshotV1? = nil
    /// Optional C41 frozen functional-relationship descriptor/history snapshot.
    /// It is a typed report fact only; later events never mutate this value.
    var functionalRelationships: CompletedFunctionalRelationshipSnapshotV1? = nil
    /// Optional C13 preview-first evidence assurance binding. It is a
    /// read-only projection and never grants publication, delivery, approval,
    /// or release authority.
    var assurance: ReportEvidenceAssuranceProjectionV1? = nil
    /// Optional C14 frozen review, change-request, and corrective-action
    /// history. The value is an immutable projection over the exact completed
    /// snapshot boundary; amendments create a replacement snapshot and never
    /// rewrite this history in place.
    var inspectionReviewHistory: CompletedInspectionReviewHistorySnapshotV1? = nil
    /// Optional C15 packet-coordination projection. The completed packet
    /// snapshot remains the source of truth; this value contains only bounded
    /// item state/counts and exact provenance digests.
    var workPacket: ReportWorkPacketProjectionV1? = nil
    /// Optional C19 frozen measurement-integrity projection. It preserves
    /// fixed-point values, typed unit meaning, capture-time calibration facts,
    /// and bounded quality status without carrying operator or opaque serial
    /// detail into a report.
    var measurementIntegrity: MeasurementIntegrityReportProjectionV1? = nil
    /// Optional C20 audience-safe privacy-transform projection. It contains
    /// only the approved, current derivative binding; original access remains
    /// a separately authorized content operation.
    var privacyTransform: PrivacyTransformReportProjectionV1? = nil

    /// Optional C21 local client-capability and package-lifecycle projection.
    /// It contains only closed admission/operation/state values and digest
    /// bindings. Historic finalized snapshots remain readable after withdrawal
    /// and are never rewritten in place.
    var clientCapability: ClientCapabilityReportProjectionV1? = nil

    /// Optional C23 metadata-only field-reference projections. Reference
    /// bytes, locators, content IDs, and subject identity are never serialized
    /// into a report snapshot.
    var fieldReferences: [FieldReferenceReportProjectionV1]? = nil

    var audienceSafeDerivativeProjection: PrivacyTransformReportProjectionV1? {
        privacyTransform
    }

    var privacyDerivativeProjection: PrivacyTransformReportProjectionV1? {
        privacyTransform
    }

    var privacyTransformProjection: PrivacyTransformReportProjectionV1? {
        privacyTransform
    }

    var clientCapabilityAdmission: ClientCapabilityReportProjectionV1? {
        clientCapability
    }

    var packageLifecycleProjection: ClientCapabilityReportProjectionV1? {
        clientCapability
    }

    var reviewHistory: [InspectionReviewTransitionV1] {
        inspectionReviewHistory?.reviewHistory ?? []
    }

    var changeHistory: [ChangeRequestV1] {
        inspectionReviewHistory?.changeHistory ?? []
    }

    var actionHistory: [CorrectiveActionEventV1] {
        inspectionReviewHistory?.actionHistory ?? []
    }
}

enum ReportSnapshotAccessibleDocumentBoundaryV1{
    static let semanticTreeFieldStoredInSnapshot=false
    static let rebuildUsesFrozenSnapshotOnly=true
}

// MARK: - C23 metadata-only reference projection

extension ReportSnapshotV1 {
    /// Builds the existing audience-safe report projection only after proving
    /// that the binding names this report's packet generation. Reference bytes,
    /// locators, content IDs, and subject identity stay outside the report.
    func c23FieldReferenceProjection(
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1,
        subjectRevision: UInt64
    ) throws -> FieldReferenceReportProjectionV1 {
        guard binding.subjectKind == .workPacket,
              binding.subjectID == packetID,
              binding.subjectRevision == subjectRevision,
              binding.subjectState == .finalized else {
            throw WorkSessionFieldReferenceFailureV1.wrongSubject
        }
        let reference = try WorkSessionFieldReferenceProjectionV1(
            binding: binding, release: release, readiness: readiness
        )
        try reference.validate(
            expectedWorkspaceID: release.workspaceID,
            expectedSubjectKind: .workPacket,
            expectedSubjectID: packetID,
            expectedSubjectRevision: subjectRevision,
            expectedSubjectState: .finalized
        )
        return try FieldReferenceReportProjectionV1(
            release: release, binding: binding, readiness: readiness
        )
    }

    /// Re-validates a previously constructed C23 report projection against
    /// the immutable packet subject before it is encoded or exported.
    func c23ValidateFieldReferenceProjection(
        _ projection: FieldReferenceReportProjectionV1,
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1,
        subjectRevision: UInt64
    ) throws -> FieldReferenceReportProjectionV1 {
        let expected = try c23FieldReferenceProjection(
            binding: binding,
            release: release,
            readiness: readiness,
            subjectRevision: subjectRevision
        )
        guard projection == expected else {
            throw WorkSessionFieldReferenceFailureV1.staleBinding
        }
        return projection
    }

    /// Returns an additive snapshot carrying one validated, finalized
    /// field-reference projection. Existing snapshot fields and historical
    /// bytes remain unchanged; a different release requires an explicit new
    /// snapshot rather than an in-place rebind.
    func withC23FieldReferenceProjection(
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1,
        subjectRevision: UInt64
    ) throws -> ReportSnapshotV1 {
        let projection = try c23FieldReferenceProjection(
            binding: binding,
            release: release,
            readiness: readiness,
            subjectRevision: subjectRevision
        )
        var copy = self
        copy.fieldReferences = [projection]
        return copy
    }
}

struct AcknowledgementSnapshotV1: Codable, Equatable, Sendable {
    let accepted: Bool
    let copy: String
    let key: String
    let version: String
}

struct AssetSnapshotV1: Codable, Equatable, Sendable {
    let label: String
}

struct CouldNotVerifySnapshotV1: Codable, Equatable, Sendable {
    let display: String
    let key: String
    let registryVersion: String
}

struct DisplaySnapshotV1: Codable, Equatable, Sendable {
    let assetSingular: String
    let checkSingular: String
    let issueSingular: String
    let outcome: String
    let stage: String
}

struct EvidenceSnapshotV1: Codable, Equatable, Sendable {
    let byteCount: Int
    let createdAt: Date
    let evidenceID: UUID
    let mimeType: String
    let purposeDisplay: String
    let purposeKey: String
    let recordID: UUID
    let relativePath: String
    let sha256: String
    let thumbnailByteCount: Int
    let thumbnailRelativePath: String
    let thumbnailSHA256: String
}

struct HistoryEntrySnapshotV1: Codable, Equatable, Sendable {
    let completedAt: Date
    let couldNotVerify: CouldNotVerifySnapshotV1?
    let evidenceIDs: [UUID]
    let issueIDs: [UUID]
    let note: String?
    var observationBasis: ObservationBasisV1? = nil
    let outcome: String
    let outcomeDisplay: String
    let recordID: UUID
    let stage: String
    let stageDisplay: String
    var temporalContext: TemporalContextV1? = nil
    let workDescription: String?
    let workPerformedLocalDate: String?
}

struct IssueSnapshotV1: Codable, Equatable, Sendable {
    let createdAt: Date
    let display: String
    let issueID: UUID
    let key: String
    let openedByRecordID: UUID
    let resolvedByRecordID: UUID?
    let status: String
    let updatedAt: Date
}

struct PackSnapshotV1: Codable, Equatable, Sendable {
    let contentVersion: Int
    let id: String
    let schemaVersion: Int
}

struct PDFTemplateReferenceV1: Codable, Equatable, Sendable {
    let id: String
    let version: Int
}

struct SiteSnapshotV1: Codable, Equatable, Sendable {
    let address: String?
    let label: String
}

struct SourceAppSnapshotV1: Codable, Equatable, Sendable {
    let build: String
    let version: String
}

struct TimeContextSnapshotV1: Codable, Equatable, Sendable {
    let localDate: String
    let localTime: String
    let observedAtUTC: Date
    let timeZoneID: String
    let utcOffsetMinutes: Int
}
