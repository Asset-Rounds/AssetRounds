import Foundation

struct ReportCorrectionIdentifiers: Equatable, Sendable {
    let mutationID: UUID
    let recordID: UUID
    let reportID: UUID
}

struct ReportCorrectionRuleSource: Equatable, Sendable {
    let currentRecord: WorkflowRecordPayloadV1
    let packet: PacketPayloadV1
    let currentReport: ReportPayloadV1
    let currentSnapshot: ReportSnapshotV1
}

struct ReportCorrectionRuleRequest: Equatable, Sendable {
    let note: String?
    let snapshotCreatedAt: Date
    let sourceApp: SourceAppSnapshotV1
    let identifiers: ReportCorrectionIdentifiers
}

struct ReportCorrectionRulePlan: Equatable, Sendable {
    let recordAfter: WorkflowRecordPayloadV1
    let packetBefore: PacketPayloadV1
    let packetAfter: PacketPayloadV1
    let reportInsert: ReportPayloadV1
    let snapshot: ReportSnapshotV1
}

enum ReportCorrectionRuleError: Error, Equatable {
    case invalidAuthority
    case invalidNote
}

/// The closed, value-only authority for a clerical report correction.
///
/// Callers must first prove the source is the unique current, fully validated
/// ready report and that its revision/replacement chain is complete. This rule
/// then permits only the correction identities, note, and the five snapshot
/// fields named by the frozen contract to change.
struct ReportCorrectionRule {
    func validateEdge(
        prior: ReportCorrectionRuleSource,
        correctionRecord: WorkflowRecordPayloadV1,
        correctionReport: ReportPayloadV1,
        correctionSnapshot: ReportSnapshotV1,
        canonicalizeSerializedRecordDates: Bool = false
    ) throws {
        guard let mutationID = correctionRecord.finalizationMutationID else {
            throw ReportCorrectionRuleError.invalidAuthority
        }
        let plan = try makePlan(
            source: prior,
            request: ReportCorrectionRuleRequest(
                note: correctionRecord.note,
                snapshotCreatedAt: correctionSnapshot.snapshotCreatedAt,
                sourceApp: correctionSnapshot.sourceApp,
                identifiers: ReportCorrectionIdentifiers(
                    mutationID: mutationID,
                    recordID: correctionRecord.id,
                    reportID: correctionReport.id
                )
            )
        )
        let normalizedReport = ReportPayloadV1(
            id: correctionReport.id,
            schemaVersion: correctionReport.schemaVersion,
            packetID: correctionReport.packetID,
            sourceRecordID: correctionReport.sourceRecordID,
            snapshotSchemaVersion: correctionReport.snapshotSchemaVersion,
            snapshotRelativePath: correctionReport.snapshotRelativePath,
            snapshotSHA256: correctionReport.snapshotSHA256,
            pdfState: ReportPDFState.pending.rawValue,
            pdfRelativePath: nil,
            pdfSHA256: nil,
            createdAt: correctionReport.createdAt,
            replacesReportID: correctionReport.replacesReportID
        )
        let legalDeliveryState = correctionReport.pdfState == ReportPDFState.pending.rawValue
            && correctionReport.pdfRelativePath == nil
            && correctionReport.pdfSHA256 == nil
            || correctionReport.pdfState == ReportPDFState.failed.rawValue
                && correctionReport.pdfRelativePath == nil
                && correctionReport.pdfSHA256 == nil
            || correctionReport.pdfState == ReportPDFState.ready.rawValue
                && correctionReport.pdfRelativePath
                    == "pdfs/\(correctionReport.id.uuidString.lowercased()).pdf"
                && correctionReport.pdfSHA256.map(isLowercaseSHA256) == true
        let recordMatches = canonicalizeSerializedRecordDates
            ? correctionRecordMatchesCanonicalDates(plan.recordAfter, correctionRecord)
            : plan.recordAfter == correctionRecord
        guard recordMatches,
              plan.packetBefore == prior.packet,
              plan.packetAfter.currentRecordID == correctionRecord.id,
              plan.reportInsert == normalizedReport,
              plan.snapshot == correctionSnapshot,
              legalDeliveryState else {
            throw ReportCorrectionRuleError.invalidAuthority
        }
    }

    func makePlan(
        source: ReportCorrectionRuleSource,
        request: ReportCorrectionRuleRequest
    ) throws -> ReportCorrectionRulePlan {
        let old = source.currentRecord
        let packet = source.packet
        let report = source.currentReport
        let snapshot = source.currentSnapshot
        guard let snapshotCreatedAt = canonicalDate(
            request.snapshotCreatedAt
        ) else {
            throw ReportCorrectionRuleError.invalidAuthority
        }

        guard validCurrentRecord(old),
              packet.schemaVersion == 1,
              packet.currentRecordID == old.id,
              packet.evaluationCounted,
              packet.contentDeletedAt == nil,
              old.packetID == packet.id,
              report.schemaVersion == 1,
              report.packetID == packet.id,
              report.sourceRecordID == old.id,
              (report.snapshotSchemaVersion == 1
                || report.snapshotSchemaVersion == 2),
              report.snapshotRelativePath
                == "snapshots/\(report.id.uuidString.lowercased()).json",
              isLowercaseSHA256(report.snapshotSHA256),
              report.pdfState == ReportPDFState.ready.rawValue,
              report.pdfRelativePath
                == "pdfs/\(report.id.uuidString.lowercased()).pdf",
              report.pdfSHA256.map(isLowercaseSHA256) == true,
              snapshot.snapshotSchemaVersion == report.snapshotSchemaVersion,
              snapshot.reportID == report.id,
              snapshot.packetID == packet.id,
              snapshot.stableRootID == packet.stableRootID,
              snapshot.sourceRecordID == old.id,
              snapshot.evidenceSourceRecordID == effectiveEvidenceOwner(old),
              snapshot.stage == old.stage,
              snapshot.outcome == old.outcomeKey,
              snapshot.note == old.note,
              snapshot.pack.id == old.packID,
              snapshot.pack.schemaVersion == old.packSchemaVersion,
              snapshot.pack.contentVersion == old.packContentVersion,
              snapshot.pdfTemplate.id == old.pdfTemplateID,
              snapshot.pdfTemplate.version == old.pdfTemplateVersion,
              snapshotObservationAndTimeMatches(snapshot, record: old),
              canonicalDate(snapshot.snapshotCreatedAt)
                == canonicalDate(report.createdAt),
              snapshotCreatedAt > snapshot.snapshotCreatedAt,
              request.identifiers.recordID != old.id,
              request.identifiers.reportID != report.id,
              request.identifiers.mutationID != old.finalizationMutationID else {
            throw ReportCorrectionRuleError.invalidAuthority
        }
        try validateNote(request.note, prior: old.note)

        let recordAfter = WorkflowRecordPayloadV1(
            id: request.identifiers.recordID,
            schemaVersion: 1,
            assetID: old.assetID,
            packetID: packet.id,
            issueID: old.issueID,
            parentRecordID: old.parentRecordID,
            recordRevisionRootID: old.recordRevisionRootID,
            revisesRecordID: old.id,
            evidenceSourceRecordID: effectiveEvidenceOwner(old),
            revisionKind: WorkflowRevisionKind.clericalCorrection.rawValue,
            stage: old.stage,
            state: WorkflowState.completed.rawValue,
            draftStepKey: nil,
            startedAt: old.startedAt,
            completedAt: old.completedAt,
            observedAtUTC: old.observedAtUTC,
            timeZoneID: old.timeZoneID,
            utcOffsetMinutes: old.utcOffsetMinutes,
            localDate: old.localDate,
            localTime: old.localTime,
            afterDarkAcknowledgementKey: old.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: old.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: old.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: old.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: old.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: old.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: old.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: old.safePositionAcknowledgementAccepted,
            packID: old.packID,
            packSchemaVersion: old.packSchemaVersion,
            packContentVersion: old.packContentVersion,
            pdfTemplateID: old.pdfTemplateID,
            pdfTemplateVersion: old.pdfTemplateVersion,
            outcomeKey: old.outcomeKey,
            couldNotVerifyKey: old.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: old.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: old.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: old.workPerformedLocalDate,
            workDescription: old.workDescription,
            note: request.note,
            finalizationMutationID: request.identifiers.mutationID,
            observationBasisV1Data: old.observationBasisV1Data,
            temporalContextV1Data: old.temporalContextV1Data
        )
        let packetAfter = PacketPayloadV1(
            id: packet.id,
            schemaVersion: packet.schemaVersion,
            stableRootID: packet.stableRootID,
            currentRecordID: recordAfter.id,
            evaluationCounted: packet.evaluationCounted,
            contentDeletedAt: packet.contentDeletedAt,
            createdAt: packet.createdAt
        )
        let correctedSnapshot = ReportSnapshotV1(
            acknowledgements: snapshot.acknowledgements,
            asset: snapshot.asset,
            couldNotVerify: snapshot.couldNotVerify,
            disclaimer: snapshot.disclaimer,
            display: snapshot.display,
            evidence: snapshot.evidence,
            evidenceSourceRecordID: snapshot.evidenceSourceRecordID,
            history: snapshot.history,
            issues: snapshot.issues,
            note: request.note,
            observationBasis: snapshot.observationBasis,
            outcome: snapshot.outcome,
            pack: snapshot.pack,
            packetID: snapshot.packetID,
            pdfTemplate: snapshot.pdfTemplate,
            reportID: request.identifiers.reportID,
            site: snapshot.site,
            snapshotCreatedAt: snapshotCreatedAt,
            snapshotSchemaVersion: snapshot.snapshotSchemaVersion,
            sourceApp: request.sourceApp,
            sourceRecordID: request.identifiers.recordID,
            stableRootID: snapshot.stableRootID,
            stage: snapshot.stage,
            temporalContext: snapshot.temporalContext,
            timeContext: snapshot.timeContext
        )
        let encodedSnapshot: EncodedReportSnapshotV1
        do {
            encodedSnapshot = try ReportSnapshotEncoderV1().encode(correctedSnapshot)
        } catch {
            throw ReportCorrectionRuleError.invalidAuthority
        }
        let canonicalReportID = request.identifiers.reportID.uuidString.lowercased()
        let reportInsert = ReportPayloadV1(
            id: request.identifiers.reportID,
            schemaVersion: 1,
            packetID: packet.id,
            sourceRecordID: recordAfter.id,
            snapshotSchemaVersion: correctedSnapshot.snapshotSchemaVersion,
            snapshotRelativePath: "snapshots/\(canonicalReportID).json",
            snapshotSHA256: encodedSnapshot.sha256,
            pdfState: ReportPDFState.pending.rawValue,
            pdfRelativePath: nil,
            pdfSHA256: nil,
            createdAt: snapshotCreatedAt,
            replacesReportID: report.id
        )

        return ReportCorrectionRulePlan(
            recordAfter: recordAfter,
            packetBefore: packet,
            packetAfter: packetAfter,
            reportInsert: reportInsert,
            snapshot: correctedSnapshot
        )
    }

    private func validCurrentRecord(_ record: WorkflowRecordPayloadV1) -> Bool {
        guard record.schemaVersion == 1,
              record.state == WorkflowState.completed.rawValue,
              record.draftStepKey == nil,
              record.packetID != nil,
              record.completedAt != nil,
              record.finalizationMutationID != nil,
              record.outcomeKey != nil,
              record.stage == WorkflowStage.check.rawValue
                || record.stage == WorkflowStage.recheck.rawValue,
              record.workPerformedLocalDate == nil,
              record.workDescription == nil,
              validObservationAndTime(record) else { return false }

        switch WorkflowRevisionKind(rawValue: record.revisionKind) {
        case .original:
            return record.recordRevisionRootID == record.id
                && record.revisesRecordID == nil
                && record.evidenceSourceRecordID == nil
        case .clericalCorrection:
            return record.revisesRecordID != nil
                && record.evidenceSourceRecordID == record.recordRevisionRootID
                && record.recordRevisionRootID != record.id
        case nil:
            return false
        }
    }

    private func validateNote(_ note: String?, prior: String?) throws {
        if let note {
            guard note == note.trimmingCharacters(in: .whitespacesAndNewlines),
                  (1...1000).contains(note.count) else {
                throw ReportCorrectionRuleError.invalidNote
            }
        }
        guard note != prior else {
            throw ReportCorrectionRuleError.invalidNote
        }
    }

    private func effectiveEvidenceOwner(_ record: WorkflowRecordPayloadV1) -> UUID {
        record.evidenceSourceRecordID ?? record.id
    }

    private func snapshotObservationAndTimeMatches(
        _ snapshot: ReportSnapshotV1,
        record: WorkflowRecordPayloadV1
    ) -> Bool {
        guard validObservationAndTime(record) else { return false }
        switch snapshot.snapshotSchemaVersion {
        case 1:
            // A migrated source row may be enriched after an immutable v1
            // snapshot was emitted; v1 itself must retain its original shape.
            return snapshot.observationBasis == nil
                && snapshot.temporalContext == nil
        case 2:
            guard let basisData = record.observationBasisV1Data,
                  let temporalData = record.temporalContextV1Data else {
                return false
            }
            do {
                return snapshot.observationBasis
                        == (try ObservationAndTimeCodecV1.decodeObservationBasis(basisData))
                    && snapshot.temporalContext
                        == (try ObservationAndTimeCodecV1.decodeTemporalContext(temporalData))
            } catch {
                return false
            }
        default:
            return false
        }
    }

    private func validObservationAndTime(_ record: WorkflowRecordPayloadV1) -> Bool {
        guard (record.observationBasisV1Data == nil)
                == (record.temporalContextV1Data == nil) else { return false }
        guard let basisData = record.observationBasisV1Data,
              let temporalData = record.temporalContextV1Data else { return true }
        do {
            let basis = try ObservationAndTimeCodecV1.decodeObservationBasis(basisData)
            let temporal = try ObservationAndTimeCodecV1.decodeTemporalContext(temporalData)
            return try ObservationAndTimeCodecV1.encode(basis) == basisData
                && ObservationAndTimeCodecV1.encode(temporal) == temporalData
        } catch {
            return false
        }
    }

    private func correctionRecordMatchesCanonicalDates(
        _ expected: WorkflowRecordPayloadV1,
        _ actual: WorkflowRecordPayloadV1
    ) -> Bool {
        var expected = expected
        var actual = actual
        guard canonicalDate(expected.startedAt) == canonicalDate(actual.startedAt),
              canonicalOptionalDate(expected.completedAt)
                == canonicalOptionalDate(actual.completedAt),
              canonicalOptionalDate(expected.observedAtUTC)
                == canonicalOptionalDate(actual.observedAtUTC) else {
            return false
        }
        expected = replacingDates(in: expected)
        actual = replacingDates(in: actual)
        return expected == actual
    }

    private func replacingDates(
        in value: WorkflowRecordPayloadV1
    ) -> WorkflowRecordPayloadV1 {
        WorkflowRecordPayloadV1(
            id: value.id, schemaVersion: value.schemaVersion,
            assetID: value.assetID, packetID: value.packetID,
            issueID: value.issueID, parentRecordID: value.parentRecordID,
            recordRevisionRootID: value.recordRevisionRootID,
            revisesRecordID: value.revisesRecordID,
            evidenceSourceRecordID: value.evidenceSourceRecordID,
            revisionKind: value.revisionKind, stage: value.stage,
            state: value.state, draftStepKey: value.draftStepKey,
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: value.completedAt.map { _ in Date(timeIntervalSince1970: 0) },
            observedAtUTC: value.observedAtUTC.map { _ in Date(timeIntervalSince1970: 0) },
            timeZoneID: value.timeZoneID, utcOffsetMinutes: value.utcOffsetMinutes,
            localDate: value.localDate, localTime: value.localTime,
            afterDarkAcknowledgementKey: value.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: value.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: value.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: value.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: value.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: value.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: value.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: value.safePositionAcknowledgementAccepted,
            packID: value.packID, packSchemaVersion: value.packSchemaVersion,
            packContentVersion: value.packContentVersion,
            pdfTemplateID: value.pdfTemplateID,
            pdfTemplateVersion: value.pdfTemplateVersion,
            outcomeKey: value.outcomeKey,
            couldNotVerifyKey: value.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: value.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: value.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: value.workPerformedLocalDate,
            workDescription: value.workDescription, note: value.note,
            finalizationMutationID: value.finalizationMutationID,
            observationBasisV1Data: value.observationBasisV1Data,
            temporalContextV1Data: value.temporalContextV1Data
        )
    }

    private func canonicalOptionalDate(_ value: Date?) -> Date? {
        value.flatMap(canonicalDate)
    }

    private func canonicalDate(_ value: Date) -> Date? {
        Self.timestampFormatter.date(
            from: Self.timestampFormatter.string(from: value)
        )
    }

    private func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
