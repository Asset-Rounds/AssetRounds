import Foundation

struct EncodedReportSnapshotV1: Equatable, Sendable {
    let data: Data
    let sha256: String
}

enum ReportSnapshotEncodingErrorV1: Error, Equatable {
    case invalidSnapshot
    case noncanonicalData
}

struct ReportSnapshotEncoderV1: Sendable {
    func encode(_ snapshot: CompletedActivitySnapshotV2) throws -> EncodedReportSnapshotV1 {
        do {
            let data = try CompletedActivitySnapshotCanonicalCodecV2.encode(snapshot)
            return EncodedReportSnapshotV1(
                data: data,
                sha256: KernelCanonicalHashV1.sha256(data)
            )
        } catch {
            throw ReportSnapshotEncodingErrorV1.invalidSnapshot
        }
    }

    func decodeCompletedActivityV2(_ data: Data) throws -> CompletedActivitySnapshotV2 {
        do { return try CompletedActivitySnapshotCanonicalCodecV2.decode(data) }
        catch { throw ReportSnapshotEncodingErrorV1.noncanonicalData }
    }

    func encode(_ snapshot: ReportSnapshotV1) throws -> EncodedReportSnapshotV1 {
        guard Self.isValid(snapshot) else {
            throw ReportSnapshotEncodingErrorV1.invalidSnapshot
        }

        let data = try CanonicalJSONV1.encode(CanonicalJSONV1.reportSnapshot(snapshot))
        return EncodedReportSnapshotV1(data: data, sha256: CanonicalJSONV1.sha256(data))
    }

    func decode(_ data: Data) throws -> ReportSnapshotV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard Self.isCanonicalTimestamp(value),
                  let date = Self.timestampFormatter.date(from: value)
            else {
                throw ReportSnapshotEncodingErrorV1.noncanonicalData
            }
            return date
        }

        guard let snapshot = try? decoder.decode(ReportSnapshotV1.self, from: data),
              let encoded = try? encode(snapshot),
              encoded.data == data
        else {
            throw ReportSnapshotEncodingErrorV1.noncanonicalData
        }
        return snapshot
    }

    /// Provisional job-kernel entry point. The released synchronous encoder is
    /// intentionally unchanged while activation remains disabled.
    func encodeOffMain(
        _ snapshot: ReportSnapshotV1
    ) async throws -> EncodedReportSnapshotV1 {
        let worker = DeterministicOffMainWorkerV1()
        return try await worker.run { try self.encode(snapshot) }
    }

    func decodeOffMain(_ data: Data) async throws -> ReportSnapshotV1 {
        let worker = DeterministicOffMainWorkerV1()
        return try await worker.run { try self.decode(data) }
    }

    private static func isValid(_ snapshot: ReportSnapshotV1) -> Bool {
        guard snapshot.snapshotSchemaVersion == 1 || snapshot.snapshotSchemaVersion == 2,
              snapshot.stage == "check" || snapshot.stage == "recheck",
              snapshot.pdfTemplate.id == "field.evidence.pdf.worklight.v1",
              snapshot.pdfTemplate.version == 1,
              snapshot.acknowledgements.count == 2,
              snapshot.acknowledgements[0].key == "after_dark",
              snapshot.acknowledgements[1].key == "safe_authorized_position",
              snapshot.acknowledgements.allSatisfy(\.accepted),
              snapshot.evidence.allSatisfy({
                  $0.mimeType == "image/jpeg"
                      && $0.byteCount >= 0
                      && $0.thumbnailByteCount >= 0
                      && isLowercaseSHA256($0.sha256)
                      && isLowercaseSHA256($0.thumbnailSHA256)
              }),
              Set(snapshot.evidence.map(\.evidenceID)).count == snapshot.evidence.count,
              Set(snapshot.issues.map(\.issueID)).count == snapshot.issues.count
        else {
            return false
        }

        guard validObservationAndTime(
            basis: snapshot.observationBasis,
            temporal: snapshot.temporalContext,
            required: snapshot.snapshotSchemaVersion == 2
        ) else { return false }

        return snapshot.history.allSatisfy {
            ($0.stage == "check" || $0.stage == "work" || $0.stage == "recheck")
                && Set($0.evidenceIDs).count == $0.evidenceIDs.count
                && Set($0.issueIDs).count == $0.issueIDs.count
                && validObservationAndTime(
                    basis: $0.observationBasis,
                    temporal: $0.temporalContext,
                    required: snapshot.snapshotSchemaVersion == 2
                )
        } && snapshot.issues.allSatisfy {
            $0.status == "open" || $0.status == "recheck_due" || $0.status == "resolved"
        }
    }

    private static func validObservationAndTime(
        basis: ObservationBasisV1?,
        temporal: TemporalContextV1?,
        required: Bool
    ) -> Bool {
        guard (basis == nil) == (temporal == nil),
              (required && basis != nil) || (!required && basis == nil) else {
            return false
        }
        guard let basis, let temporal else { return !required }
        do {
            try basis.validate()
            try temporal.validate()
            let basisData = try ObservationAndTimeCodecV1.encode(basis)
            let temporalData = try ObservationAndTimeCodecV1.encode(temporal)
            let decodedBasis = try ObservationAndTimeCodecV1
                .decodeObservationBasis(basisData)
            let decodedTemporal = try ObservationAndTimeCodecV1
                .decodeTemporalContext(temporalData)
            return decodedBasis == basis && decodedTemporal == temporal
        } catch {
            return false
        }
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (97...102).contains($0.value)
        }
    }

    private static func isCanonicalTimestamp(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        guard scalars.count == 24 else { return false }
        let punctuation: [Int: Unicode.Scalar] = [
            4: "-", 7: "-", 10: "T", 13: ":", 16: ":", 19: ".", 23: "Z",
        ]
        for (index, scalar) in scalars.enumerated() {
            if let expected = punctuation[index] {
                guard scalar == expected else { return false }
            } else if !(48...57).contains(scalar.value) {
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

extension CanonicalJSONV1 {
    static func reportSnapshot(_ value: ReportSnapshotV1) -> CanonicalJSONValueV1 {
        var object: [String: CanonicalJSONValueV1] = [
            "acknowledgements": .array(value.acknowledgements.map(acknowledgement)),
            "asset": asset(value.asset),
            "couldNotVerify": value.couldNotVerify.map(couldNotVerify) ?? .null,
            "disclaimer": .string(value.disclaimer),
            "display": display(value.display),
            "evidence": .array(value.evidence.map(evidence)),
            "evidenceSourceRecordID": uuid(value.evidenceSourceRecordID),
            "history": .array(value.history.map(history)),
            "issues": .array(value.issues.map(issueSnapshot)),
            "note": optionalString(value.note),
            "outcome": .string(value.outcome),
            "pack": pack(value.pack),
            "packetID": uuid(value.packetID),
            "pdfTemplate": pdfTemplate(value.pdfTemplate),
            "reportID": uuid(value.reportID),
            "site": site(value.site),
            "snapshotCreatedAt": date(value.snapshotCreatedAt),
            "snapshotSchemaVersion": .integer(value.snapshotSchemaVersion),
            "sourceApp": sourceApp(value.sourceApp),
            "sourceRecordID": uuid(value.sourceRecordID),
            "stableRootID": uuid(value.stableRootID),
            "stage": .string(value.stage),
            "timeContext": timeContext(value.timeContext),
        ]
        if value.snapshotSchemaVersion == 2,
           let basis = value.observationBasis,
           let temporal = value.temporalContext {
            object["observationBasis"] = observationBasis(basis)
            object["temporalContext"] = temporalContext(temporal)
        }
        return .object(object)
    }

    private static func acknowledgement(_ value: AcknowledgementSnapshotV1) -> CanonicalJSONValueV1 {
        .object([
            "accepted": .bool(value.accepted),
            "copy": .string(value.copy),
            "key": .string(value.key),
            "version": .string(value.version),
        ])
    }

    private static func asset(_ value: AssetSnapshotV1) -> CanonicalJSONValueV1 {
        .object(["label": .string(value.label)])
    }

    private static func couldNotVerify(_ value: CouldNotVerifySnapshotV1) -> CanonicalJSONValueV1 {
        .object([
            "display": .string(value.display),
            "key": .string(value.key),
            "registryVersion": .string(value.registryVersion),
        ])
    }

    private static func display(_ value: DisplaySnapshotV1) -> CanonicalJSONValueV1 {
        .object([
            "assetSingular": .string(value.assetSingular),
            "checkSingular": .string(value.checkSingular),
            "issueSingular": .string(value.issueSingular),
            "outcome": .string(value.outcome),
            "stage": .string(value.stage),
        ])
    }

    private static func evidence(_ value: EvidenceSnapshotV1) -> CanonicalJSONValueV1 {
        .object([
            "byteCount": .integer(value.byteCount),
            "createdAt": date(value.createdAt),
            "evidenceID": uuid(value.evidenceID),
            "mimeType": .string(value.mimeType),
            "purposeDisplay": .string(value.purposeDisplay),
            "purposeKey": .string(value.purposeKey),
            "recordID": uuid(value.recordID),
            "relativePath": .string(value.relativePath),
            "sha256": .string(value.sha256),
            "thumbnailByteCount": .integer(value.thumbnailByteCount),
            "thumbnailRelativePath": .string(value.thumbnailRelativePath),
            "thumbnailSHA256": .string(value.thumbnailSHA256),
        ])
    }

    private static func history(_ value: HistoryEntrySnapshotV1) -> CanonicalJSONValueV1 {
        var object: [String: CanonicalJSONValueV1] = [
            "completedAt": date(value.completedAt),
            "couldNotVerify": value.couldNotVerify.map(couldNotVerify) ?? .null,
            "evidenceIDs": .array(value.evidenceIDs.map(uuid)),
            "issueIDs": .array(value.issueIDs.map(uuid)),
            "note": optionalString(value.note),
            "outcome": .string(value.outcome),
            "outcomeDisplay": .string(value.outcomeDisplay),
            "recordID": uuid(value.recordID),
            "stage": .string(value.stage),
            "stageDisplay": .string(value.stageDisplay),
            "workDescription": optionalString(value.workDescription),
            "workPerformedLocalDate": optionalString(value.workPerformedLocalDate),
        ]
        if let basis = value.observationBasis, let temporal = value.temporalContext {
            object["observationBasis"] = observationBasis(basis)
            object["temporalContext"] = temporalContext(temporal)
        }
        return .object(object)
    }

    private static func issueSnapshot(_ value: IssueSnapshotV1) -> CanonicalJSONValueV1 {
        .object([
            "createdAt": date(value.createdAt),
            "display": .string(value.display),
            "issueID": uuid(value.issueID),
            "key": .string(value.key),
            "openedByRecordID": uuid(value.openedByRecordID),
            "resolvedByRecordID": optionalUUID(value.resolvedByRecordID),
            "status": .string(value.status),
            "updatedAt": date(value.updatedAt),
        ])
    }

    private static func pack(_ value: PackSnapshotV1) -> CanonicalJSONValueV1 {
        .object([
            "contentVersion": .integer(value.contentVersion),
            "id": .string(value.id),
            "schemaVersion": .integer(value.schemaVersion),
        ])
    }

    private static func pdfTemplate(_ value: PDFTemplateReferenceV1) -> CanonicalJSONValueV1 {
        .object([
            "id": .string(value.id),
            "version": .integer(value.version),
        ])
    }

    private static func site(_ value: SiteSnapshotV1) -> CanonicalJSONValueV1 {
        .object([
            "address": optionalString(value.address),
            "label": .string(value.label),
        ])
    }

    private static func sourceApp(_ value: SourceAppSnapshotV1) -> CanonicalJSONValueV1 {
        .object([
            "build": .string(value.build),
            "version": .string(value.version),
        ])
    }

    private static func timeContext(_ value: TimeContextSnapshotV1) -> CanonicalJSONValueV1 {
        .object([
            "localDate": .string(value.localDate),
            "localTime": .string(value.localTime),
            "observedAtUTC": date(value.observedAtUTC),
            "timeZoneID": .string(value.timeZoneID),
            "utcOffsetMinutes": .integer(value.utcOffsetMinutes),
        ])
    }

    private static func observationBasis(
        _ value: ObservationBasisV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "kind": .string(value.kind.rawValue),
            "limitations": .array(value.limitations.map { .string($0) }),
            "method": .object(["key": .string(value.method.key)]),
            "source": .object([
                "kind": .string(value.source.kind.rawValue),
                "reference": optionalString(value.source.reference),
            ]),
            "version": .integer(value.version),
        ])
    }

    private static func temporalContext(
        _ value: TemporalContextV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "ianaTimeZoneIdentifier": optionalString(value.ianaTimeZoneIdentifier),
            "localDate": optionalString(value.localDate),
            "localTime": optionalString(value.localTime),
            "localTimeDisposition": .string(value.localTimeDisposition.rawValue),
            "occurredAtUTC": optionalDate(value.occurredAtUTC),
            "recordedAtUTC": date(value.recordedAtUTC),
            "utcOffsetSeconds": optionalInteger(value.utcOffsetSeconds),
            "version": .integer(value.version),
        ])
    }
}
