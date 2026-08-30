import CryptoKit
import Foundation

enum FinalizationPhaseV1: String, Codable, Equatable, Sendable {
    case prepared
    case snapshotPromoted = "snapshot_promoted"
    case databaseCommitted = "database_committed"
}

enum C50IncumbentFinalizationBoundaryV1 {
    static let importCannotFinalize = true
    static let exportCannotChangeFinalization = true
    static let completedBytesRemainImmutable = true
}

enum FinalizationAccessibleDocumentBoundaryV1{
    static let assessmentRequiredToFinalize=false
    static let finalSnapshotRewrittenByAssessment=false
}

struct FinalizationIntentV1: Codable, Equatable, Sendable {
    let completedAt: Date
    let finalizationMutationID: UUID
    let finalizationPayload: FinalizationPayloadV1
    let finalizationPayloadSHA256: String
    let generationID: UUID
    let packetID: UUID
    let phase: FinalizationPhaseV1
    let recordID: UUID
    let reportID: UUID
    let schemaVersion: Int
    let snapshotCreatedAt: Date
    let snapshotFinalRelativePath: String
    let snapshotSHA256: String
    let snapshotStagingRelativePath: String
    let stableRootID: UUID

    func withPhase(_ phase: FinalizationPhaseV1) -> FinalizationIntentV1 {
        FinalizationIntentV1(
            completedAt: completedAt,
            finalizationMutationID: finalizationMutationID,
            finalizationPayload: finalizationPayload,
            finalizationPayloadSHA256: finalizationPayloadSHA256,
            generationID: generationID,
            packetID: packetID,
            phase: phase,
            recordID: recordID,
            reportID: reportID,
            schemaVersion: schemaVersion,
            snapshotCreatedAt: snapshotCreatedAt,
            snapshotFinalRelativePath: snapshotFinalRelativePath,
            snapshotSHA256: snapshotSHA256,
            snapshotStagingRelativePath: snapshotStagingRelativePath,
            stableRootID: stableRootID
        )
    }
}

struct FinalizationPayloadV1: Codable, Equatable, Sendable {
    let issueInsert: IssuePayloadV1?
    let issueTransition: IssueTransitionV1?
    let packetAfter: PacketPayloadV1
    let packetBefore: PacketPayloadV1?
    let reportInsert: ReportPayloadV1?
    let workflowRecordAfter: WorkflowRecordPayloadV1
}

struct IssueTransitionV1: Codable, Equatable, Sendable {
    let after: IssuePayloadV1
    let before: IssuePayloadV1
}

struct WorkflowRecordPayloadV1: Codable, Equatable, Sendable {
    let id: UUID
    let schemaVersion: Int
    let assetID: UUID
    let packetID: UUID?
    let issueID: UUID?
    let parentRecordID: UUID?
    let recordRevisionRootID: UUID
    let revisesRecordID: UUID?
    let evidenceSourceRecordID: UUID?
    let revisionKind: String
    let stage: String
    let state: String
    let draftStepKey: String?
    let startedAt: Date
    let completedAt: Date?
    let observedAtUTC: Date?
    let timeZoneID: String?
    let utcOffsetMinutes: Int?
    let localDate: String?
    let localTime: String?
    let afterDarkAcknowledgementKey: String?
    let afterDarkAcknowledgementCopy: String?
    let afterDarkAcknowledgementVersion: String?
    let afterDarkAcknowledgementAccepted: Bool?
    let safePositionAcknowledgementKey: String?
    let safePositionAcknowledgementCopy: String?
    let safePositionAcknowledgementVersion: String?
    let safePositionAcknowledgementAccepted: Bool?
    let packID: String
    let packSchemaVersion: Int
    let packContentVersion: Int
    let pdfTemplateID: String
    let pdfTemplateVersion: Int
    let outcomeKey: String?
    let couldNotVerifyKey: String?
    let couldNotVerifyDisplaySnapshot: String?
    let couldNotVerifyRegistryVersion: String?
    let workPerformedLocalDate: String?
    let workDescription: String?
    let note: String?
    let finalizationMutationID: UUID?
    var observationBasisV1Data: Data? = nil
    var temporalContextV1Data: Data? = nil
}

struct IssuePayloadV1: Codable, Equatable, Sendable {
    let id: UUID
    let schemaVersion: Int
    let assetID: UUID
    let openedByRecordID: UUID
    let labelKey: String
    let labelDisplaySnapshot: String
    let status: String
    let resolvedByRecordID: UUID?
    let createdAt: Date
    let updatedAt: Date
}

struct PacketPayloadV1: Codable, Equatable, Sendable {
    let id: UUID
    let schemaVersion: Int
    let stableRootID: UUID
    let currentRecordID: UUID?
    let evaluationCounted: Bool
    let contentDeletedAt: Date?
    let createdAt: Date
}

struct ReportPayloadV1: Codable, Equatable, Sendable {
    let id: UUID
    let schemaVersion: Int
    let packetID: UUID
    let sourceRecordID: UUID
    let snapshotSchemaVersion: Int
    let snapshotRelativePath: String
    let snapshotSHA256: String
    let pdfState: String
    let pdfRelativePath: String?
    let pdfSHA256: String?
    let createdAt: Date
    let replacesReportID: UUID?
}

// MARK: - C23 finalization/read-only binding gates

extension WorkflowRecordPayloadV1 {
    /// Finalization payloads retain their historical shape. C23 validates the
    /// supplied immutable binding as a side-input and never places reference
    /// bytes, locators, or mutable release state in the payload.
    func c23ValidateFieldReferenceBinding(
        workspaceID: WorkspaceID,
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1,
        subjectRevision: UInt64,
        subjectState: FieldReferenceSubjectStateV1? = nil
    ) throws -> WorkSessionFieldReferenceProjectionV1 {
        let expectedKind: FieldReferenceSubjectKindV1 =
            packetID == nil ? .roundSession : .workPacket
        let expectedSubjectID = packetID ?? id
        let expectedState: FieldReferenceSubjectStateV1 =
            state == WorkflowState.completed.rawValue ? .finalized : .active
        guard binding.subjectKind == expectedKind,
              binding.subjectID == expectedSubjectID,
              binding.subjectRevision == subjectRevision,
              binding.subjectState == expectedState,
              subjectState.map({ $0 == expectedState }) ?? true else {
            throw WorkSessionFieldReferenceFailureV1.wrongSubject
        }
        let projection = try WorkSessionFieldReferenceProjectionV1(
            binding: binding, release: release, readiness: readiness
        )
        try projection.validate(
            expectedWorkspaceID: workspaceID,
            expectedSubjectKind: expectedKind,
            expectedSubjectID: expectedSubjectID,
            expectedSubjectRevision: subjectRevision,
            expectedSubjectState: expectedState
        )
        return projection
    }
}

extension PacketPayloadV1 {
    /// Packet payloads are immutable finalization inputs. A binding is valid
    /// only for this packet and its caller-supplied packet revision/state.
    func c23ValidateFieldReferenceBinding(
        workspaceID: WorkspaceID,
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1,
        subjectRevision: UInt64,
        subjectState: FieldReferenceSubjectStateV1 = .active
    ) throws -> WorkSessionFieldReferenceProjectionV1 {
        guard binding.subjectKind == .workPacket,
              binding.subjectID == id,
              binding.subjectRevision == subjectRevision,
              binding.subjectState == subjectState else {
            throw WorkSessionFieldReferenceFailureV1.wrongSubject
        }
        let projection = try WorkSessionFieldReferenceProjectionV1(
            binding: binding, release: release, readiness: readiness
        )
        try projection.validate(
            expectedWorkspaceID: workspaceID,
            expectedSubjectKind: .workPacket,
            expectedSubjectID: id,
            expectedSubjectRevision: subjectRevision,
            expectedSubjectState: subjectState
        )
        return projection
    }
}

extension ReportPayloadV1 {
    /// Reports expose only metadata projections and must re-prove the packet
    /// binding before encoding/export. The report payload itself is unchanged.
    func c23ValidateFieldReferenceBinding(
        workspaceID: WorkspaceID,
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1,
        subjectRevision: UInt64,
        subjectState: FieldReferenceSubjectStateV1 = .finalized
    ) throws -> WorkSessionFieldReferenceProjectionV1 {
        guard binding.subjectKind == .workPacket,
              binding.subjectID == packetID,
              binding.subjectRevision == subjectRevision,
              binding.subjectState == subjectState else {
            throw WorkSessionFieldReferenceFailureV1.wrongSubject
        }
        let projection = try WorkSessionFieldReferenceProjectionV1(
            binding: binding, release: release, readiness: readiness
        )
        try projection.validate(
            expectedWorkspaceID: workspaceID,
            expectedSubjectKind: .workPacket,
            expectedSubjectID: packetID,
            expectedSubjectRevision: subjectRevision,
            expectedSubjectState: subjectState
        )
        return projection
    }
}

struct EncodedFinalizationContractV1: Equatable, Sendable {
    let data: Data
    let sha256: String
}

enum FinalizationContractEncodingErrorV1: Error, Equatable {
    case invalidPayloadHash
    case unsupportedValue
}

enum FinalizationContractDecodingErrorV1: Error, Equatable {
    case invalidCanonicalIntent
}

struct FinalizationContractDecoderV1 {
    func decodeIntent(_ data: Data) throws -> FinalizationIntentV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard Self.isCanonicalTimestamp(string),
                  let date = Self.timestampFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected canonical RFC3339 UTC milliseconds"
                )
            }
            return date
        }
        let intent: FinalizationIntentV1
        do {
            intent = try decoder.decode(FinalizationIntentV1.self, from: data)
            let canonical = try FinalizationContractEncoderV1().encodeIntent(intent).data
            guard canonical == data else {
                throw FinalizationContractDecodingErrorV1.invalidCanonicalIntent
            }
        } catch {
            throw FinalizationContractDecodingErrorV1.invalidCanonicalIntent
        }
        return intent
    }

    private static func isCanonicalTimestamp(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 24 else { return false }
        let punctuation: [Int: UInt8] = [
            4: 0x2d, 7: 0x2d, 10: 0x54, 13: 0x3a,
            16: 0x3a, 19: 0x2e, 23: 0x5a,
        ]
        for (index, byte) in bytes.enumerated() {
            if let expected = punctuation[index] {
                guard byte == expected else { return false }
            } else if !(0x30...0x39).contains(byte) {
                return false
            }
        }
        return true
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

struct FinalizationContractEncoderV1 {
    func encodePayload(_ payload: FinalizationPayloadV1) throws -> EncodedFinalizationContractV1 {
        guard Self.validObservationAndTime(payload.workflowRecordAfter) else {
            throw FinalizationContractEncodingErrorV1.unsupportedValue
        }
        let value = CanonicalJSONV1.finalizationPayload(payload)
        let data = try CanonicalJSONV1.encode(value)
        return EncodedFinalizationContractV1(data: data, sha256: CanonicalJSONV1.sha256(data))
    }

    func encodeIntent(_ intent: FinalizationIntentV1) throws -> EncodedFinalizationContractV1 {
        let payload = try encodePayload(intent.finalizationPayload)
        guard payload.sha256 == intent.finalizationPayloadSHA256 else {
            throw FinalizationContractEncodingErrorV1.invalidPayloadHash
        }
        let data = try CanonicalJSONV1.encode(CanonicalJSONV1.finalizationIntent(intent))
        return EncodedFinalizationContractV1(data: data, sha256: CanonicalJSONV1.sha256(data))
    }

    private static func validObservationAndTime(
        _ record: WorkflowRecordPayloadV1
    ) -> Bool {
        guard (record.observationBasisV1Data == nil)
                == (record.temporalContextV1Data == nil) else { return false }
        guard let basisData = record.observationBasisV1Data,
              let temporalData = record.temporalContextV1Data else { return true }
        do {
            let basis = try ObservationAndTimeCodecV1.decodeObservationBasis(basisData)
            let temporal = try ObservationAndTimeCodecV1.decodeTemporalContext(temporalData)
            let canonicalBasis = try ObservationAndTimeCodecV1.encode(basis)
            let canonicalTemporal = try ObservationAndTimeCodecV1.encode(temporal)
            return canonicalBasis == basisData && canonicalTemporal == temporalData
        } catch {
            return false
        }
    }
}

enum CanonicalJSONValueV1: Equatable {
    case array([CanonicalJSONValueV1])
    case bool(Bool)
    case integer(Int)
    case null
    case object([String: CanonicalJSONValueV1])
    case string(String)
}

enum CanonicalJSONV1 {
    static func encode(_ value: CanonicalJSONValueV1) throws -> Data {
        Data(try render(value).utf8)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func date(_ value: Date) -> CanonicalJSONValueV1 {
        .string(timestampFormatter.string(from: value))
    }

    static func uuid(_ value: UUID) -> CanonicalJSONValueV1 {
        .string(value.uuidString.lowercased())
    }

    static func optionalDate(_ value: Date?) -> CanonicalJSONValueV1 {
        value.map(date) ?? .null
    }

    static func optionalUUID(_ value: UUID?) -> CanonicalJSONValueV1 {
        value.map(uuid) ?? .null
    }

    static func optionalString(_ value: String?) -> CanonicalJSONValueV1 {
        value.map(CanonicalJSONValueV1.string) ?? .null
    }

    static func optionalInteger(_ value: Int?) -> CanonicalJSONValueV1 {
        value.map(CanonicalJSONValueV1.integer) ?? .null
    }

    static func optionalBool(_ value: Bool?) -> CanonicalJSONValueV1 {
        value.map(CanonicalJSONValueV1.bool) ?? .null
    }

    static func finalizationIntent(_ value: FinalizationIntentV1) -> CanonicalJSONValueV1 {
        .object([
            "completedAt": date(value.completedAt),
            "finalizationMutationID": uuid(value.finalizationMutationID),
            "finalizationPayload": finalizationPayload(value.finalizationPayload),
            "finalizationPayloadSHA256": .string(value.finalizationPayloadSHA256),
            "generationID": uuid(value.generationID),
            "packetID": uuid(value.packetID),
            "phase": .string(value.phase.rawValue),
            "recordID": uuid(value.recordID),
            "reportID": uuid(value.reportID),
            "schemaVersion": .integer(value.schemaVersion),
            "snapshotCreatedAt": date(value.snapshotCreatedAt),
            "snapshotFinalRelativePath": .string(value.snapshotFinalRelativePath),
            "snapshotSHA256": .string(value.snapshotSHA256),
            "snapshotStagingRelativePath": .string(value.snapshotStagingRelativePath),
            "stableRootID": uuid(value.stableRootID),
        ])
    }

    static func finalizationPayload(_ value: FinalizationPayloadV1) -> CanonicalJSONValueV1 {
        .object([
            "issueInsert": value.issueInsert.map(issue) ?? .null,
            "issueTransition": value.issueTransition.map(issueTransition) ?? .null,
            "packetAfter": packet(value.packetAfter),
            "packetBefore": value.packetBefore.map(packet) ?? .null,
            "reportInsert": value.reportInsert.map(report) ?? .null,
            "workflowRecordAfter": workflowRecord(value.workflowRecordAfter),
        ])
    }

    private static func issueTransition(_ value: IssueTransitionV1) -> CanonicalJSONValueV1 {
        .object([
            "after": issue(value.after),
            "before": issue(value.before),
        ])
    }

    private static func workflowRecord(_ value: WorkflowRecordPayloadV1) -> CanonicalJSONValueV1 {
        var object: [String: CanonicalJSONValueV1] = [
            "afterDarkAcknowledgementAccepted": optionalBool(value.afterDarkAcknowledgementAccepted),
            "afterDarkAcknowledgementCopy": optionalString(value.afterDarkAcknowledgementCopy),
            "afterDarkAcknowledgementKey": optionalString(value.afterDarkAcknowledgementKey),
            "afterDarkAcknowledgementVersion": optionalString(value.afterDarkAcknowledgementVersion),
            "assetID": uuid(value.assetID),
            "completedAt": optionalDate(value.completedAt),
            "couldNotVerifyDisplaySnapshot": optionalString(value.couldNotVerifyDisplaySnapshot),
            "couldNotVerifyKey": optionalString(value.couldNotVerifyKey),
            "couldNotVerifyRegistryVersion": optionalString(value.couldNotVerifyRegistryVersion),
            "draftStepKey": optionalString(value.draftStepKey),
            "evidenceSourceRecordID": optionalUUID(value.evidenceSourceRecordID),
            "finalizationMutationID": optionalUUID(value.finalizationMutationID),
            "id": uuid(value.id),
            "issueID": optionalUUID(value.issueID),
            "localDate": optionalString(value.localDate),
            "localTime": optionalString(value.localTime),
            "note": optionalString(value.note),
            "observedAtUTC": optionalDate(value.observedAtUTC),
            "outcomeKey": optionalString(value.outcomeKey),
            "packContentVersion": .integer(value.packContentVersion),
            "packID": .string(value.packID),
            "packSchemaVersion": .integer(value.packSchemaVersion),
            "packetID": optionalUUID(value.packetID),
            "parentRecordID": optionalUUID(value.parentRecordID),
            "pdfTemplateID": .string(value.pdfTemplateID),
            "pdfTemplateVersion": .integer(value.pdfTemplateVersion),
            "recordRevisionRootID": uuid(value.recordRevisionRootID),
            "revisesRecordID": optionalUUID(value.revisesRecordID),
            "revisionKind": .string(value.revisionKind),
            "safePositionAcknowledgementAccepted": optionalBool(value.safePositionAcknowledgementAccepted),
            "safePositionAcknowledgementCopy": optionalString(value.safePositionAcknowledgementCopy),
            "safePositionAcknowledgementKey": optionalString(value.safePositionAcknowledgementKey),
            "safePositionAcknowledgementVersion": optionalString(value.safePositionAcknowledgementVersion),
            "schemaVersion": .integer(value.schemaVersion),
            "stage": .string(value.stage),
            "startedAt": date(value.startedAt),
            "state": .string(value.state),
            "timeZoneID": optionalString(value.timeZoneID),
            "utcOffsetMinutes": optionalInteger(value.utcOffsetMinutes),
            "workDescription": optionalString(value.workDescription),
            "workPerformedLocalDate": optionalString(value.workPerformedLocalDate),
        ]
        // Nil is the exact released pre-ObservationAndTimeSchemaV1 shape. Do
        // not add null members: old finalization/recovery bytes must re-encode
        // byte-for-byte. New rows carry the codec's canonical bytes verbatim.
        if let data = value.observationBasisV1Data {
            object["observationBasisV1Data"] = .string(data.base64EncodedString())
        }
        if let data = value.temporalContextV1Data {
            object["temporalContextV1Data"] = .string(data.base64EncodedString())
        }
        return .object(object)
    }

    private static func issue(_ value: IssuePayloadV1) -> CanonicalJSONValueV1 {
        .object([
            "assetID": uuid(value.assetID),
            "createdAt": date(value.createdAt),
            "id": uuid(value.id),
            "labelDisplaySnapshot": .string(value.labelDisplaySnapshot),
            "labelKey": .string(value.labelKey),
            "openedByRecordID": uuid(value.openedByRecordID),
            "resolvedByRecordID": optionalUUID(value.resolvedByRecordID),
            "schemaVersion": .integer(value.schemaVersion),
            "status": .string(value.status),
            "updatedAt": date(value.updatedAt),
        ])
    }

    private static func packet(_ value: PacketPayloadV1) -> CanonicalJSONValueV1 {
        .object([
            "contentDeletedAt": optionalDate(value.contentDeletedAt),
            "createdAt": date(value.createdAt),
            "currentRecordID": optionalUUID(value.currentRecordID),
            "evaluationCounted": .bool(value.evaluationCounted),
            "id": uuid(value.id),
            "schemaVersion": .integer(value.schemaVersion),
            "stableRootID": uuid(value.stableRootID),
        ])
    }

    private static func report(_ value: ReportPayloadV1) -> CanonicalJSONValueV1 {
        .object([
            "createdAt": date(value.createdAt),
            "id": uuid(value.id),
            "packetID": uuid(value.packetID),
            "pdfRelativePath": optionalString(value.pdfRelativePath),
            "pdfSHA256": optionalString(value.pdfSHA256),
            "pdfState": .string(value.pdfState),
            "replacesReportID": optionalUUID(value.replacesReportID),
            "schemaVersion": .integer(value.schemaVersion),
            "snapshotRelativePath": .string(value.snapshotRelativePath),
            "snapshotSHA256": .string(value.snapshotSHA256),
            "snapshotSchemaVersion": .integer(value.snapshotSchemaVersion),
            "sourceRecordID": uuid(value.sourceRecordID),
        ])
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static func render(_ value: CanonicalJSONValueV1) throws -> String {
        switch value {
        case .array(let values):
            return "[" + (try values.map(render).joined(separator: ",")) + "]"
        case .bool(let value):
            return value ? "true" : "false"
        case .integer(let value):
            return String(value)
        case .null:
            return "null"
        case .object(let object):
            let members = try object.keys.sorted().map { key in
                guard let value = object[key] else {
                    throw FinalizationContractEncodingErrorV1.unsupportedValue
                }
                return try quoted(key) + ":" + render(value)
            }
            return "{" + members.joined(separator: ",") + "}"
        case .string(let value):
            return try quoted(value)
        }
    }

    private static func quoted(_ value: String) throws -> String {
        let normalized = value.precomposedStringWithCanonicalMapping
        var result = "\""
        for scalar in normalized.unicodeScalars {
            switch scalar.value {
            case 0x08: result += "\\b"
            case 0x09: result += "\\t"
            case 0x0a: result += "\\n"
            case 0x0c: result += "\\f"
            case 0x0d: result += "\\r"
            case 0x22: result += "\\\""
            case 0x5c: result += "\\\\"
            case 0x00...0x1f:
                result += String(format: "\\u%04x", scalar.value)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        result += "\""
        return result
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_Workflow_FinalizationContracts {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_Workflow_FinalizationContracts_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}

enum C30EvidenceContextFinalizationBoundaryV1 {
    static let finalizedReportCarriesRecordedContext = true
    static let finalizationDoesNotRecalculateHistory = true
    static let contextIsNotNonRepudiation = true

    static func validate(context: EvidenceContextV1,
                         link: PairedObservationLinkV1? = nil) throws {
        try C30EvidenceContextWorkflowBoundaryV1.validate(context: context, pairedLink: link)
        guard finalizedReportCarriesRecordedContext,
              finalizationDoesNotRecalculateHistory, contextIsNotNonRepudiation else {
            throw EvidenceContextFailureV1.invalidValue
        }
    }
}

enum C31LightingFinalizationBoundaryV1 {
    static let finalizationBindsRecordedRevisions = true
    static let finalizedDisplayIsImmutable = true
    static let noLicensedCriterionTextIsGenerated = true

    static func validate(
        records: [V31BackupLightingRecordV1],
        workspaceID: WorkspaceID
    ) throws {
        try C31LightingWorkflowBoundaryV1.validate(
            records: records,
            workspaceID: workspaceID
        )
        guard finalizationBindsRecordedRevisions,
              finalizedDisplayIsImmutable,
              noLicensedCriterionTextIsGenerated else {
            throw LightingContractFailureV1.invalidValue
        }
    }
}
// MARK: - C32 assistance finalization boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Workflow_FinalizationContracts_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let proposalCannotFinalizeReport = true

    static func validateProposal(_ proposal: AssistanceProposalV1, in context: AssistanceProposalEvaluationContextV1) throws {
        try proposal.validate()
        try context.validate()
        guard proposal.verificationState.rawValue == AssistanceProposalVerificationStateV1.unverified.rawValue,
              context.policy.manualFallback == .typeManually else {
            throw AssistanceContractFailureV1.incompatibleCapability
        }
        if let reason = try proposal.expiryReason(in: context) {
            throw AssistanceContractFailureV1.expired(reason)
        }
    }

    static func validateAcceptanceReceipt(_ receipt: AssistanceAcceptanceReceiptV1) throws {
        try receipt.validate()
    }
}

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Domain_Workflow_FinalizationContracts_swift {
    static let durableFamilyCount = TemporalEvidencePersistenceEnrollmentV1.durableModelCount
    static func validate(clip: TemporalEvidenceClipV1,
                         anchor: TimecodedEvidenceAnchorV1) throws {
        try clip.validateIntrinsic()
        try anchor.validate(clip: clip)
        guard durableFamilyCount == 2 else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
    }
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row154 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}

enum C46OperationalContactConformance_FieldEvidenceApp_Domain_Workflow_FinalizationContracts_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let siteRoleOwnershipForbidden = true
}

enum C48PortableReviewFinalizationBoundaryV1 {
    static let externalReviewCannotFinalize = true
    static let responseDispositionIsNotCompletionTruth = true
    static let capabilityProofIsNotFinalizationEvidence = true
    static let rawResponseBytesAreNotFinalizationInput = true
    static let existingFinalizationWriterRemainsTheOnlyMutationRoute = true
}

// MARK: - C49 finalization projection

enum C49WorkResourceFinalizationBoundaryV1 {
    static let finalizationConsumesSnapshotOnly = true
    static let finalizationIsAppendOnly = true
    static let finalizationCannotCreateInventoryClaims = true

    static func envelope(
        _ projection: C49WorkResourceReportProjectionV1,
        format: String = "OPEN_JSON"
    ) throws -> C49WorkResourceProjectionEnvelopeV1 {
        try C49WorkResourceProjectionSupportV1.envelope(projection, format: format)
    }
}
