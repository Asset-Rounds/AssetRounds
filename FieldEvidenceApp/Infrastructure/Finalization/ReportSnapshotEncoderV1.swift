import Foundation

struct EncodedReportSnapshotV1: Equatable, Sendable {
    let data: Data
    let sha256: String
}

enum AccessibleDocumentTreeCanonicalEncoderV1{
    static func encode(_ tree:AccessibleDocumentSemanticTreeV1)throws->EncodedReportSnapshotV1{try tree.validate();let data=try AccessibleDocumentCanonicalCodecV1.encode(tree);return .init(data:data,sha256:KernelCanonicalHashV1.sha256(data))}
}

enum ReportSnapshotEncodingErrorV1: Error, Equatable {
    case invalidSnapshot
    case noncanonicalData
}

enum IntegrationProjectionReportSnapshotExclusionV1 {
    static func validate() throws {
        let coverage = IntegrationEventJournalCoverageV1()
        try coverage.validate()
        guard !coverage.reportSourceOfTruth,
              !IntegrationProjectionSchemaV1.canonicalReportSource else {
            throw ReportSnapshotEncodingErrorV1.invalidSnapshot
        }
    }
}

/// Provisional-only companion codec. Production finalization deliberately does
/// not populate this projection until its owning release surface is activated.
enum RequirementAssuranceSnapshotCanonicalCodecV1 {
    static let status = "PROVISIONAL_NONRELEASE_ONLY"

    static func isValid(_ snapshot: RequirementAssuranceSnapshotV1) -> Bool {
        (try? snapshot.validate()) != nil
            && snapshot.evaluatedRevision <= UInt64(Int.max)
            && snapshot.evaluations.allSatisfy {
                $0.evaluatedRevision <= UInt64(Int.max)
            }
            && snapshot.decision.evaluatedRevision <= UInt64(Int.max)
    }

    static func encode(_ snapshot: RequirementAssuranceSnapshotV1) throws -> Data {
        do {
            guard isValid(snapshot) else {
                throw ReportSnapshotEncodingErrorV1.invalidSnapshot
            }
            let data = try RequirementAssuranceCanonicalV1.data(snapshot)
            guard !data.isEmpty,
                  data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
                throw ReportSnapshotEncodingErrorV1.invalidSnapshot
            }
            return data
        } catch let error as ReportSnapshotEncodingErrorV1 {
            throw error
        } catch {
            throw ReportSnapshotEncodingErrorV1.invalidSnapshot
        }
    }

    static func decode(_ data: Data) throws -> RequirementAssuranceSnapshotV1 {
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw ReportSnapshotEncodingErrorV1.noncanonicalData
        }
        do {
            let value = try JSONDecoder().decode(
                RequirementAssuranceSnapshotV1.self,
                from: data
            )
            try value.validate()
            guard try encode(value) == data else {
                throw ReportSnapshotEncodingErrorV1.noncanonicalData
            }
            return value
        } catch let error as ReportSnapshotEncodingErrorV1 {
            if error == .invalidSnapshot {
                throw ReportSnapshotEncodingErrorV1.noncanonicalData
            }
            throw error
        } catch {
            throw ReportSnapshotEncodingErrorV1.noncanonicalData
        }
    }
}

/// C13's preview/manifest envelope is encoded for deterministic local
/// inspection only.  It is intentionally not a finalization producer and the
/// status remains provisional until a later release surface authorizes it.
enum ReportEvidenceAssuranceCanonicalCodecV1 {
    static let status = ReportEvidenceAssuranceProjectionPolicyV1.publicationDisposition

    static func isValid(_ value: ReportEvidenceAssuranceProjectionV1) -> Bool {
        (try? value.validate()) != nil
    }

    static func encode(_ value: ReportEvidenceAssuranceProjectionV1) throws -> Data {
        guard isValid(value) else { throw ReportSnapshotEncodingErrorV1.invalidSnapshot }
        do {
            let data = try EvidenceAssuranceCanonicalCodecV1.encode(value)
            guard !data.isEmpty,
                  data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
                throw ReportSnapshotEncodingErrorV1.invalidSnapshot
            }
            return data
        } catch let error as ReportSnapshotEncodingErrorV1 {
            throw error
        } catch {
            throw ReportSnapshotEncodingErrorV1.invalidSnapshot
        }
    }

    static func decode(_ data: Data) throws -> ReportEvidenceAssuranceProjectionV1 {
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw ReportSnapshotEncodingErrorV1.noncanonicalData
        }
        do {
            let value = try EvidenceAssuranceCanonicalCodecV1.decode(
                ReportEvidenceAssuranceProjectionV1.self, from: data
            )
            try value.validate()
            guard try encode(value) == data else {
                throw ReportSnapshotEncodingErrorV1.noncanonicalData
            }
            return value
        } catch let error as ReportSnapshotEncodingErrorV1 {
            throw error
        } catch {
            throw ReportSnapshotEncodingErrorV1.noncanonicalData
        }
    }
}

struct ReportSnapshotEncoderV1: Sendable {
    static let authorityCriterionWriterStatus = "PROVISIONAL_READ_ONLY_PRE_S10"
    static let requirementAssuranceCodecStatus =
        RequirementAssuranceSnapshotCanonicalCodecV1.status

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

    func encode(_ snapshot: CompletedActivitySnapshotV3) throws -> EncodedReportSnapshotV1 {
        do {
            let data = try CompletedActivitySnapshotCanonicalCodecV3.encode(snapshot)
            return EncodedReportSnapshotV1(
                data: data,
                sha256: KernelCanonicalHashV1.sha256(data)
            )
        } catch {
            throw ReportSnapshotEncodingErrorV1.invalidSnapshot
        }
    }

    func decodeCompletedActivityV3(_ data: Data) throws -> CompletedActivitySnapshotV3 {
        do { return try CompletedActivitySnapshotCanonicalCodecV3.decode(data) }
        catch { throw ReportSnapshotEncodingErrorV1.noncanonicalData }
    }

    func encode(_ snapshot: CompletedActivitySnapshotV4) throws -> EncodedReportSnapshotV1 {
        do {
            let data = try CompletedActivitySnapshotCanonicalCodecV4.encode(snapshot)
            return EncodedReportSnapshotV1(
                data: data,
                sha256: KernelCanonicalHashV1.sha256(data)
            )
        } catch {
            throw ReportSnapshotEncodingErrorV1.invalidSnapshot
        }
    }

    func decodeCompletedActivityV4(_ data: Data) throws -> CompletedActivitySnapshotV4 {
        do { return try CompletedActivitySnapshotCanonicalCodecV4.decode(data) }
        catch { throw ReportSnapshotEncodingErrorV1.noncanonicalData }
    }

    func encode(_ snapshot: CompletedActivitySnapshotV5) throws -> EncodedReportSnapshotV1 {
        do {
            let data = try CompletedActivitySnapshotCanonicalCodecV5.encode(snapshot)
            return EncodedReportSnapshotV1(data: data, sha256: KernelCanonicalHashV1.sha256(data))
        } catch { throw ReportSnapshotEncodingErrorV1.invalidSnapshot }
    }

    func decodeCompletedActivityV5(_ data: Data) throws -> CompletedActivitySnapshotV5 {
        do { return try CompletedActivitySnapshotCanonicalCodecV5.decode(data) }
        catch { throw ReportSnapshotEncodingErrorV1.noncanonicalData }
    }

    /// C41's additive frozen snapshot codec. V1--V5 encode/decode behavior is
    /// intentionally unchanged so an older report cannot be rewritten by a
    /// newer relationship projection.
    func encode(_ snapshot: CompletedActivitySnapshotV6) throws -> EncodedReportSnapshotV1 {
        do {
            let data = try CompletedActivitySnapshotCanonicalCodecV6.encode(snapshot)
            return EncodedReportSnapshotV1(data: data, sha256: KernelCanonicalHashV1.sha256(data))
        } catch { throw ReportSnapshotEncodingErrorV1.invalidSnapshot }
    }

    func decodeCompletedActivityV6(_ data: Data) throws -> CompletedActivitySnapshotV6 {
        do { return try CompletedActivitySnapshotCanonicalCodecV6.decode(data) }
        catch { throw ReportSnapshotEncodingErrorV1.noncanonicalData }
    }

    /// C13's additive completed snapshot codec. V1--V6 encoding remains
    /// unchanged and the assurance facts stay bound to the inner V6 digest.
    func encode(_ snapshot: CompletedActivitySnapshotV7) throws -> EncodedReportSnapshotV1 {
        do {
            let data = try CompletedActivitySnapshotCanonicalCodecV7.encode(snapshot)
            return EncodedReportSnapshotV1(data: data, sha256: KernelCanonicalHashV1.sha256(data))
        } catch { throw ReportSnapshotEncodingErrorV1.invalidSnapshot }
    }

    func decodeCompletedActivityV7(_ data: Data) throws -> CompletedActivitySnapshotV7 {
        do { return try CompletedActivitySnapshotCanonicalCodecV7.decode(data) }
        catch { throw ReportSnapshotEncodingErrorV1.noncanonicalData }
    }

    /// C14's additive completed snapshot codec. Review, change-request, and
    /// corrective-action facts remain bound to the exact V7 source digest;
    /// this route only encodes an already validated frozen value.
    func encode(_ snapshot: CompletedActivitySnapshotV8) throws -> EncodedReportSnapshotV1 {
        do {
            let data = try CompletedActivitySnapshotCanonicalCodecV8.encode(snapshot)
            return EncodedReportSnapshotV1(data: data, sha256: KernelCanonicalHashV1.sha256(data))
        } catch { throw ReportSnapshotEncodingErrorV1.invalidSnapshot }
    }

    func decodeCompletedActivityV8(_ data: Data) throws -> CompletedActivitySnapshotV8 {
        do { return try CompletedActivitySnapshotCanonicalCodecV8.decode(data) }
        catch { throw ReportSnapshotEncodingErrorV1.noncanonicalData }
    }

    /// C15's additive completed snapshot codec. The V8 review history remains
    /// immutable and the packet event history is encoded as a sibling value
    /// bound to the same workspace and packet identity.
    func encode(_ snapshot: CompletedActivitySnapshotV9) throws -> EncodedReportSnapshotV1 {
        do {
            let data = try CompletedActivitySnapshotCanonicalCodecV9.encode(snapshot)
            return EncodedReportSnapshotV1(data: data, sha256: KernelCanonicalHashV1.sha256(data))
        } catch { throw ReportSnapshotEncodingErrorV1.invalidSnapshot }
    }

    func decodeCompletedActivityV9(_ data: Data) throws -> CompletedActivitySnapshotV9 {
        do { return try CompletedActivitySnapshotCanonicalCodecV9.decode(data) }
        catch { throw ReportSnapshotEncodingErrorV1.noncanonicalData }
    }

    func encode(
        _ history: CompletedInspectionReviewHistorySnapshotV1
    ) throws -> EncodedReportSnapshotV1 {
        do {
            let data = try InspectionReviewCanonicalCodecV1.encode(history)
            return EncodedReportSnapshotV1(data: data, sha256: KernelCanonicalHashV1.sha256(data))
        } catch { throw ReportSnapshotEncodingErrorV1.invalidSnapshot }
    }

    func decodeInspectionReviewHistory(
        _ data: Data
    ) throws -> CompletedInspectionReviewHistorySnapshotV1 {
        do {
            return try InspectionReviewCanonicalCodecV1.decode(
                CompletedInspectionReviewHistorySnapshotV1.self,
                from: data
            )
        } catch { throw ReportSnapshotEncodingErrorV1.noncanonicalData }
    }

    func encode(
        _ snapshot: RequirementAssuranceSnapshotV1
    ) throws -> EncodedReportSnapshotV1 {
        let data = try RequirementAssuranceSnapshotCanonicalCodecV1.encode(snapshot)
        return EncodedReportSnapshotV1(
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data)
        )
    }

    func decodeRequirementAssurance(
        _ data: Data
    ) throws -> RequirementAssuranceSnapshotV1 {
        try RequirementAssuranceSnapshotCanonicalCodecV1.decode(data)
    }

    func encode(
        _ assurance: ReportEvidenceAssuranceProjectionV1
    ) throws -> EncodedReportSnapshotV1 {
        let data = try ReportEvidenceAssuranceCanonicalCodecV1.encode(assurance)
        return EncodedReportSnapshotV1(data: data, sha256: KernelCanonicalHashV1.sha256(data))
    }

    func decodeEvidenceAssurance(
        _ data: Data
    ) throws -> ReportEvidenceAssuranceProjectionV1 {
        try ReportEvidenceAssuranceCanonicalCodecV1.decode(data)
    }

    func encode(_ snapshot: ReportSnapshotV1) throws -> EncodedReportSnapshotV1 {
        try IntegrationProjectionReportSnapshotExclusionV1.validate()
        guard (1...4).contains(snapshot.snapshotSchemaVersion) else {
            throw ReportSnapshotEncodingErrorV1.invalidSnapshot
        }
        return try canonicalEncoding(snapshot)
    }

    private func canonicalEncoding(_ snapshot: ReportSnapshotV1) throws -> EncodedReportSnapshotV1 {
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
            if let value = try? container.decode(String.self) {
                guard Self.isCanonicalTimestamp(value),
                      let date = Self.timestampFormatter.date(from: value) else {
                    throw ReportSnapshotEncodingErrorV1.noncanonicalData
                }
                return date
            }
            // C41's nested domain codec uses canonical milliseconds. Accept
            // that representation only for the additive relationship field;
            // legacy report dates remain strict UTC timestamp strings.
            if let milliseconds = try? container.decode(Double.self),
               milliseconds.isFinite {
                return Date(timeIntervalSince1970: milliseconds / 1_000)
            }
            throw ReportSnapshotEncodingErrorV1.noncanonicalData
        }

        guard let snapshot = try? decoder.decode(ReportSnapshotV1.self, from: data),
              let encoded = try? canonicalEncoding(snapshot),
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
        guard (1...4).contains(snapshot.snapshotSchemaVersion),
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

        guard (snapshot.snapshotSchemaVersion >= 3) == (snapshot.authorityCriterion != nil),
              (snapshot.snapshotSchemaVersion >= 4) == (snapshot.inspectionReviewHistory != nil) else {
            return false
        }

        if let assurance = snapshot.requirementAssurance {
            guard RequirementAssuranceSnapshotCanonicalCodecV1.isValid(assurance) else {
                return false
            }
        }

        if let accountability = snapshot.accountability {
            guard (try? accountability.validate()) != nil,
                  accountability.parties.allSatisfy({ $0.revision <= UInt64(Int.max) }),
                  accountability.roleEvents.allSatisfy({ $0.revision <= UInt64(Int.max) }),
                  accountability.signoffs.allSatisfy({ $0.subjectRevision <= UInt64(Int.max) }) else {
                return false
            }
        }

        if let assetSemantics = snapshot.assetSemantics {
            guard (try? assetSemantics.validate()) != nil else {
                return false
            }
        }
        if let authorityCriterion = snapshot.authorityCriterion {
            guard (try? authorityCriterion.validate()) != nil else { return false }
        }
        if let functionalRelationships = snapshot.functionalRelationships {
            guard (try? functionalRelationships.validate()) != nil else { return false }
        }
        if let assurance = snapshot.assurance {
            guard ReportEvidenceAssuranceCanonicalCodecV1.isValid(assurance) else { return false }
        }
        if let inspectionReviewHistory = snapshot.inspectionReviewHistory {
            guard (try? inspectionReviewHistory.validate()) != nil,
                  snapshot.accountability != nil,
                  snapshot.assetSemantics != nil,
                  snapshot.authorityCriterion != nil,
                  snapshot.functionalRelationships != nil,
                  snapshot.assurance != nil else { return false }
        }
        if let workPacket = snapshot.workPacket {
            guard snapshot.snapshotSchemaVersion >= 4,
                  (try? workPacket.validate()) != nil,
                  workPacket.packetID == snapshot.packetID,
                  workPacket.itemCount == workPacket.itemIDs.count,
                  workPacket.itemCount == workPacket.itemStateLabels.count,
                  ReportWorkPacketProjectionPolicyV1.supports(.openJSON),
                  ReportWorkPacketProjectionPolicyV1.supports(.structuredText) else {
                return false
            }
        }
        if let measurementIntegrity = snapshot.measurementIntegrity {
            guard (try? measurementIntegrity.validate()) != nil,
                  measurementIntegrity.revision <= UInt64(Int.max),
                  measurementIntegrity.protocolRevision.map({ $0 <= UInt64(Int.max) }) ?? true,
                  ReportMeasurementIntegrityProjectionPolicyV1.supportedFormats.allSatisfy({
                      ReportMeasurementIntegrityProjectionPolicyV1.supports($0)
                  }) else {
                return false
            }
        }
        if let privacyTransform = snapshot.privacyTransform {
            guard (try? privacyTransform.validate()) != nil,
                  PrivacyTransformReportProjectionPolicyV1.supportedFormats.allSatisfy({
                      PrivacyTransformReportProjectionPolicyV1.supports($0)
                  }) else {
                return false
            }
        }
        if let clientCapability = snapshot.clientCapability {
            guard (try? clientCapability.validate()) != nil,
                  ClientCapabilityReportProjectionPolicyV1.supportedFormats.allSatisfy({
                      ClientCapabilityReportProjectionPolicyV1.supports($0)
                  }) else {
                return false
            }
        }
        if let surveyPublication = snapshot.surveyPublication {
            guard (try? surveyPublication.validate()) != nil,
                  surveyPublication.sessionRevision <= UInt64(Int.max),
                  surveyPublication.publicationRevision <= UInt64(Int.max),
                  surveyPublication.definitionRevision <= UInt64(Int.max) else {
                return false
            }
        }
        if let scheduleProjection = snapshot.scheduleProjection {
            guard (try? ScheduleReportProjectionPolicyV1.validate(scheduleProjection)) != nil else {
                return false
            }
        }
        if let planProjection = snapshot.planProjection {
            guard (try? PlanReportProjectionPolicyV1.validate(planProjection)) != nil else {
                return false
            }
        }
        if let placementPose = snapshot.placementPose {
            guard snapshot.snapshotSchemaVersion >= 4,
                  (try? placementPose.validate()) != nil else {
                return false
            }
        }

        guard validObservationAndTime(
            basis: snapshot.observationBasis,
            temporal: snapshot.temporalContext,
            required: snapshot.snapshotSchemaVersion >= 2
        ) else { return false }

        return snapshot.history.allSatisfy {
            ($0.stage == "check" || $0.stage == "work" || $0.stage == "recheck")
                && Set($0.evidenceIDs).count == $0.evidenceIDs.count
                && Set($0.issueIDs).count == $0.issueIDs.count
                && validObservationAndTime(
                    basis: $0.observationBasis,
                    temporal: $0.temporalContext,
                    required: snapshot.snapshotSchemaVersion >= 2
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
        if value.snapshotSchemaVersion >= 2,
           let basis = value.observationBasis,
           let temporal = value.temporalContext {
            object["observationBasis"] = observationBasis(basis)
            object["temporalContext"] = temporalContext(temporal)
        }
        if let assurance = value.requirementAssurance {
            object["requirementAssurance"] = requirementAssurance(assurance)
        }
        if let accountability = value.accountability {
            object["accountability"] = Self.accountability(accountability)
        }
        if let assetSemantics = value.assetSemantics {
            object["assetSemantics"] = Self.assetSemantics(assetSemantics)
        }
        if let authorityCriterion = value.authorityCriterion {
            object["authorityCriterion"] = Self.authorityCriterion(authorityCriterion)
        }
        if let functionalRelationships = value.functionalRelationships {
            object["functionalRelationships"] = Self.functionalRelationships(functionalRelationships)
        }
        if let assurance = value.assurance {
            object["assurance"] = Self.assurance(assurance)
        }
        if let inspectionReviewHistory = value.inspectionReviewHistory {
            object["inspectionReviewHistory"] = Self.inspectionReviewHistory(
                inspectionReviewHistory
            )
        }
        if let workPacket = value.workPacket {
            object["workPacket"] = Self.workPacket(workPacket)
        }
        if let measurementIntegrity = value.measurementIntegrity {
            object["measurementIntegrity"] = Self.measurementIntegrity(measurementIntegrity)
        }
        if let privacyTransform = value.privacyTransform {
            object["privacyTransform"] = Self.privacyTransform(privacyTransform)
        }
        if let clientCapability = value.clientCapability {
            object["clientCapability"] = Self.clientCapability(clientCapability)
        }
        if let surveyPublication = value.surveyPublication {
            object["surveyPublication"] = Self.surveyPublication(surveyPublication)
        }
        if let scheduleProjection = value.scheduleProjection {
            object["scheduleProjection"] = Self.scheduleProjection(scheduleProjection)
        }
        if let planProjection = value.planProjection {
            object["planProjection"] = Self.planProjection(planProjection)
        }
        if let placementPose = value.placementPose {
            object["placementPose"] = Self.placementPose(placementPose)
        }
        return .object(object)
    }

    private static func scheduleProjection(
        _ value: ScheduleReportProjectionV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "schemaVersion": .integer(value.schemaVersion),
            "projectionVersion": .string(value.projectionVersion),
            "workspaceID": uuid(value.workspaceID),
            "scheduleDefinitionID": uuid(value.scheduleDefinitionID),
            "scheduleRelease": scheduleRelease(value.scheduleRelease),
            "lifecycleState": .string(value.lifecycleState.rawValue),
            "recurrenceKind": .string(value.recurrenceKind),
            "timeBasis": timeBasis(value.timeBasis),
            "evaluatedAt": date(value.evaluatedAt),
            "occurrences": .array(value.occurrences.map(scheduleOccurrence)),
            "dueQueueProjectionSHA256": .string(value.dueQueueProjectionSHA256),
            "reminderProjectionSHA256": value.reminderProjectionSHA256.map { .string($0) } ?? .null,
            "sourceClosureSHA256": .string(value.sourceClosureSHA256),
            "historyFrozen": .bool(value.historyFrozen),
            "notificationDeliveryIsTruth": .bool(value.notificationDeliveryIsTruth),
            "projectionSHA256": .string(value.projectionSHA256),
        ])
    }

    private static func scheduleRelease(
        _ value: ScheduleDefinitionReleaseReferenceV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "scheduleDefinitionID": uuid(value.scheduleDefinitionID),
            "releaseID": uuid(value.releaseID),
            "revision": .integer(Int(value.revision)),
            "releaseSHA256": .string(value.releaseSHA256),
        ])
    }

    private static func timeBasis(
        _ value: FrozenScheduleTimeBasisV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "calendar": .string(value.calendar.rawValue),
            "ianaTimeZoneIdentifier": .string(value.ianaTimeZoneIdentifier),
            "timeZoneRuleSetVersion": .string(value.timeZoneRuleSetVersion),
            "timeZoneRuleSetSHA256": .string(value.timeZoneRuleSetSHA256),
            "ambiguousTimePolicy": .string(value.ambiguousTimePolicy.rawValue),
            "nonexistentTimePolicy": .string(value.nonexistentTimePolicy.rawValue),
            "calendarBasisID": .string(value.calendarBasisID),
            "calendarBasisRevision": .integer(Int(value.calendarBasisRevision)),
            "calendarBasisSHA256": .string(value.calendarBasisSHA256),
        ])
    }

    private static func scheduleOccurrence(
        _ value: ScheduleOccurrenceReportProjectionV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "schemaVersion": .integer(value.schemaVersion),
            "occurrenceID": .string(value.occurrenceID.rawValue),
            "state": .string(value.state.rawValue),
            "scheduleRelease": scheduleRelease(value.scheduleRelease),
            "nominalBasis": occurrenceBasis(value.nominalBasis),
            "effectiveBasis": occurrenceBasis(value.effectiveBasis),
            "historyEventSHA256": .string(value.historyEventSHA256),
            "workInstanceRecorded": .bool(value.workInstanceRecorded),
        ])
    }

    private static func occurrenceBasis(
        _ value: ResolvedOccurrenceBasisV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "nominalLocalDate": .string(value.nominalLocalDate),
            "nominalLocalTime": .string(value.nominalLocalTime),
            "resolvedAtUTC": value.resolvedAtUTC.map(date) ?? .null,
            "utcOffsetSeconds": value.utcOffsetSeconds.map { .integer($0) } ?? .null,
            "disposition": .string(value.disposition.rawValue),
            "timeBasisSHA256": .string(value.timeBasisSHA256),
            "adjustmentProvenanceSHA256": value.adjustmentProvenanceSHA256.map { .string($0) } ?? .null,
        ])
    }

    private static func planProjection(
        _ value: PlanReportProjectionV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "schemaVersion": .integer(value.schemaVersion),
            "projectionVersion": .string(value.projectionVersion),
            "workspaceID": uuid(value.workspaceID),
            "documentReference": c29PlanDocumentReference(value.documentReference),
            "revisionReference": c29PlanRevisionReference(value.revisionReference),
            "documentState": .string(value.documentState.rawValue),
            "revisionState": .string(value.revisionState.rawValue),
            "contentReleaseID": uuid(value.contentReleaseID),
            "contentReleaseRevision": .integer(Int(value.contentReleaseRevision)),
            "contentReleaseSHA256": .string(value.contentReleaseSHA256),
            "contentManifestSHA256": .string(value.contentManifestSHA256),
            "pageCount": .integer(value.pageCount),
            "placements": .array(value.placements.map(c29PlanPlacement)),
            "rebasePreview": value.rebasePreview.map(c29PlanPreview) ?? .null,
            "rebaseReceipt": value.rebaseReceipt.map(c29PlanReceipt) ?? .null,
            "historicDisplayIsFrozen": .bool(value.historicDisplayIsFrozen),
            "previewIsNotApplied": .bool(value.previewIsNotApplied),
            "projectionSHA256": .string(value.projectionSHA256),
        ])
    }

    private static func c29PlanDocumentReference(
        _ value: PlanDocumentReferenceV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "planDocumentID": uuid(value.planDocumentID),
            "revision": .integer(Int(value.revision)),
            "documentSHA256": .string(value.documentSHA256),
        ])
    }

    private static func c29PlanRevisionReference(
        _ value: PlanRevisionReferenceV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "planRevisionID": uuid(value.planRevisionID),
            "planDocumentID": uuid(value.planDocumentID),
            "revision": .integer(Int(value.revision)),
            "revisionSHA256": .string(value.revisionSHA256),
        ])
    }

    private static func c29PlanPlacement(
        _ value: PlanPlacementReportProjectionV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "schemaVersion": .integer(value.schemaVersion),
            "placementID": uuid(value.placementID),
            "subjectKind": .string(value.subjectKind.rawValue),
            "subjectID": uuid(value.subjectID),
            "planRevisionID": uuid(value.planRevisionID),
            "spatialFrameID": uuid(value.spatialFrameID),
            "xMillionths": .integer(Int(value.xMillionths)),
            "yMillionths": .integer(Int(value.yMillionths)),
            "disposition": .string(value.disposition.rawValue),
            "revision": .integer(Int(value.revision)),
            "placementSHA256": .string(value.placementSHA256),
        ])
    }

    private static func placementPose(
        _ value: C37PlacementPoseFrozenSnapshotV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "sourceSnapshotID": uuid(value.sourceSnapshotID),
            "projection": placementPoseProjection(value.projection),
            "historicDisplayIsFrozen": .bool(value.historicDisplayIsFrozen),
            "snapshotSHA256": .string(value.snapshotSHA256),
        ])
    }

    private static func placementPoseProjection(
        _ value: C37PlacementPoseReportProjectionV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "schemaVersion": .integer(value.schemaVersion),
            "projectionVersion": .string(value.projectionVersion),
            "workspaceID": uuid(value.workspaceID.rawValue),
            "assetID": uuid(value.assetID),
            "currentTipReferences": .array(value.currentTipReferences.map(placementPoseReference)),
            "history": .array(value.history.map(placementPoseHistory)),
            "capturedAt": date(value.capturedAt),
            "historyFrozen": .bool(value.historyFrozen),
            "rebasePreviewIsNotApplied": .bool(value.rebasePreviewIsNotApplied),
            "sensorInputAllowed": .bool(value.sensorInputAllowed),
            "networkInputAllowed": .bool(value.networkInputAllowed),
            "projectionSHA256": .string(value.projectionSHA256),
        ])
    }

    private static func placementPoseReference(
        _ value: AssetPoseEventReferenceV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "eventID": uuid(value.eventID),
            "workspaceID": uuid(value.workspaceID.rawValue),
            "assetID": uuid(value.assetID),
            "axisID": .string(value.axisID.rawValue),
            "revision": .integer(Int(value.revision)),
            "eventSHA256": .string(value.eventSHA256),
        ])
    }

    private static func placementPoseHistory(
        _ value: C37PoseHistoryProjectionV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "eventID": uuid(value.eventID),
            "axisID": .string(value.axisID),
            "placementEpisodeID": uuid(value.placementEpisodeID),
            "placementEventID": uuid(value.placementEventID),
            "rootObservationEventID": uuid(value.rootObservationEventID),
            "rootObservedAt": date(value.rootObservedAt),
            "occurredAt": date(value.occurredAt),
            "recordedAt": date(value.recordedAt),
            "referenceFrame": .string(value.referenceFrame.rawValue),
            "disposition": .string(value.disposition.rawValue),
            "observationState": .string(value.observationState.rawValue),
            "notObservedReason": value.notObservedReason.map { .string($0.rawValue) } ?? .null,
            "azimuthMilliDegrees": value.azimuthMilliDegrees.map { .integer(Int($0)) } ?? .null,
            "elevationMilliDegrees": value.elevationMilliDegrees.map { .integer(Int($0)) } ?? .null,
            "horizontalUncertaintyMilliDegrees": value.horizontalUncertaintyMilliDegrees.map { .integer(Int($0)) } ?? .null,
            "verticalUncertaintyMilliDegrees": value.verticalUncertaintyMilliDegrees.map { .integer(Int($0)) } ?? .null,
            "horizontalUncertaintyState": .string(value.horizontalUncertaintyState.rawValue),
            "verticalUncertaintyState": .string(value.verticalUncertaintyState.rawValue),
            "source": .string(value.source.rawValue),
            "revision": .integer(Int(value.revision)),
            "eventSHA256": .string(value.eventSHA256),
            "planRevisionID": value.planRevisionID.map { .string($0.uuidString.lowercased()) } ?? .null,
            "planPageID": value.planPageID.map { .string($0.uuidString.lowercased()) } ?? .null,
            "planSpatialFrameID": value.planSpatialFrameID.map { .string($0.uuidString.lowercased()) } ?? .null,
            "planTransformSHA256": value.planTransformSHA256.map { .string($0) } ?? .null,
        ])
    }

    private static func c29PlanPreview(
        _ value: PlanRebasePreviewReportProjectionV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "schemaVersion": .integer(value.schemaVersion),
            "previewID": uuid(value.previewID),
            "oldRevision": c29PlanRevisionReference(value.oldRevision),
            "newRevision": c29PlanRevisionReference(value.newRevision),
            "transformSHA256": .string(value.transformSHA256),
            "registrySHA256": .string(value.registrySHA256),
            "componentIDs": .array(value.componentIDs.map { .string($0) }),
            "rowCount": .integer(value.rowCount),
            "acceptedRowCount": .integer(value.acceptedRowCount),
            "reviewRequiredRowCount": .integer(value.reviewRequiredRowCount),
            "warningCodes": .array(value.warningCodes.map { .string($0.rawValue) }),
            "requiresReview": .bool(value.requiresReview),
            "expectedRevision": .integer(Int(value.expectedRevision)),
            "generatedAt": date(value.generatedAt),
            "previewSHA256": .string(value.previewSHA256),
        ])
    }

    private static func c29PlanReceipt(
        _ value: PlanRebaseReceiptReportProjectionV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "schemaVersion": .integer(value.schemaVersion),
            "receiptID": uuid(value.receiptID),
            "previewID": uuid(value.previewID),
            "previewSHA256": .string(value.previewSHA256),
            "decision": .string(value.decision.rawValue),
            "resultingRevision": value.resultingRevision.map(c29PlanRevisionReference) ?? .null,
            "resultingPlacementsSHA256": value.resultingPlacementsSHA256.map { .string($0) } ?? .null,
            "canonicalMutationReceiptSHA256": value.canonicalMutationReceiptSHA256.map { .string($0) } ?? .null,
            "recordedAt": date(value.recordedAt),
            "revision": .integer(Int(value.revision)),
            "receiptSHA256": .string(value.receiptSHA256),
        ])
    }

    private static func surveyPublication(
        _ value: SurveyPublicationReportProjectionV1
    ) -> CanonicalJSONValueV1 {
        let subject: CanonicalJSONValueV1
        switch value.subjectAtPublication {
        case .canonical(let reference):
            subject = .object([
                "kind": .string("CANONICAL"),
                "subjectID": uuid(reference.subjectID),
                "subjectKind": .string(reference.kind.rawValue),
                "subjectRevision": .integer(Int(reference.revision)),
                "ownerAssetID": reference.ownerAssetID.map(uuid) ?? .null,
            ])
        case .provisional(let reference):
            subject = .object([
                "kind": .string("PROVISIONAL"),
                "subjectID": uuid(reference.provisionalSubjectID),
                "subjectRevision": .integer(Int(reference.revision)),
                "subjectSHA256": .string(reference.subjectSHA256),
            ])
        }
        return .object([
            "projectionVersion": .string(value.projectionVersion),
            "snapshotID": uuid(value.snapshotID),
            "workspaceID": uuid(value.workspaceID.rawValue),
            "sessionID": uuid(value.sessionID),
            "sessionRevision": .integer(Int(value.sessionRevision)),
            "publicationRevision": .integer(Int(value.publicationRevision)),
            "publicationSHA256": .string(value.publicationSHA256),
            "definitionReleaseID": uuid(value.definitionReleaseID),
            "definitionRevision": .integer(Int(value.definitionRevision)),
            "definitionSHA256": .string(value.definitionSHA256),
            "packageReleaseID": .string(value.packageReleaseID),
            "packageID": .string(value.packageID),
            "packageContentVersion": .integer(value.packageContentVersion),
            "packageSHA256": .string(value.packageSHA256),
            "workflowSHA256": .string(value.workflowSHA256),
            "subjectAtPublication": subject,
            "factCount": .integer(value.factCount),
            "evidenceCount": .integer(value.evidenceCount),
        ])
    }

    /// C20 exposes only the approved derivative's bounded binding. In
    /// particular, this object has no original/derivative locator, bytes,
    /// reviewer identity, or rationale.
    private static func privacyTransform(
        _ value: PrivacyTransformReportProjectionV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "schemaVersion": .integer(value.schemaVersion),
            "projectionVersion": .string(value.projectionVersion),
            "workspaceID": .object(["rawValue": uuid(value.workspaceID.rawValue)]),
            "manifestID": uuid(value.manifestID),
            "reviewReceiptID": uuid(value.reviewReceiptID),
            "policyID": uuid(value.policyID),
            "audience": .string(value.audience.rawValue),
            "derivativeContentID": .string(value.derivativeContentID),
            "derivativeSHA256": .string(value.derivativeSHA256),
            "sourceRevision": .integer(Int(value.sourceRevision)),
            "sourceSHA256": .string(value.sourceSHA256),
            "policyRevision": .integer(Int(value.policyRevision)),
            "policySHA256": .string(value.policySHA256),
            "reviewRevision": .integer(Int(value.reviewRevision)),
            "reviewSHA256": .string(value.reviewSHA256),
            "reviewDecision": .string(value.reviewDecision.rawValue),
            "staleState": .string(value.staleState.rawValue),
            "metadataSanitized": .bool(value.metadataSanitized),
            "redactionDeclared": .bool(value.redactionDeclared),
            "derivativeOnly": .bool(value.derivativeOnly),
            "originalReferenceExcluded": .bool(value.originalReferenceExcluded),
            "transformKinds": .array(value.transformKinds.map { .string($0.rawValue) }),
            "regionCount": .integer(value.regionCount),
            "projectionSHA256": .string(value.projectionSHA256),
        ])
    }

    /// C21 carries only deterministic local admission/lifecycle metadata.
    /// Package bytes, client/device identity, users, endpoints, providers,
    /// and remote delivery or acknowledgement details are intentionally absent.
    private static func clientCapability(
        _ value: ClientCapabilityReportProjectionV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "schemaVersion": .integer(value.schemaVersion),
            "projectionVersion": .string(value.projectionVersion),
            "workspaceID": .object(["rawValue": uuid(value.workspaceID.rawValue)]),
            "decisionID": uuid(value.decisionID),
            "profileID": uuid(value.profileID),
            "policyID": uuid(value.policyID),
            "dispositionID": uuid(value.dispositionID),
            "packageReleaseID": .string(value.packageReleaseID),
            "packageSHA256": .string(value.packageSHA256),
            "workflowSHA256": .string(value.workflowSHA256),
            "profileRevision": .integer(Int(value.profileRevision)),
            "policyRevision": .integer(Int(value.policyRevision)),
            "dispositionRevision": .integer(Int(value.dispositionRevision)),
            "decisionRevision": .integer(Int(value.decisionRevision)),
            "profileSHA256": .string(value.profileSHA256),
            "policySHA256": .string(value.policySHA256),
            "dispositionSHA256": .string(value.dispositionSHA256),
            "decisionSHA256": .string(value.decisionSHA256),
            "operation": .string(value.operation.rawValue),
            "admission": .string(value.admission.rawValue),
            "lifecycleState": .string(value.lifecycleState.rawValue),
            "reasons": .array(value.reasons.map { .string($0.rawValue) }),
            "readAllowed": .bool(value.readAllowed),
            "writeAllowed": .bool(value.writeAllowed),
            "operationAllowed": .bool(value.operationAllowed),
            "historicArtifact": .bool(value.historicArtifact),
            "historicExportAllowed": .bool(value.historicExportAllowed),
            "immutableHistoric": .bool(value.immutableHistoric),
            "projectionSHA256": .string(value.projectionSHA256),
        ])
    }

    /// C19 is deliberately an additive, privacy-safe report object. Exact
    /// decimal components and enum tokens are retained for deterministic
    /// reopening; operator snapshots, opaque serials, raw responses, and
    /// evidence locators never enter this output.
    private static func measurementIntegrity(
        _ value: MeasurementIntegrityReportProjectionV1
    ) -> CanonicalJSONValueV1 {
        func decimal(_ value: ExactDecimalV1) -> CanonicalJSONValueV1 {
            .object([
                "mantissa": .integer(Int(value.mantissa)),
                "scale": .integer(value.scale),
            ])
        }
        func optionalDecimal(_ value: ExactDecimalV1?) -> CanonicalJSONValueV1 {
            value.map(decimal) ?? .null
        }
        return .object([
            "schemaVersion": .integer(value.schemaVersion),
            "captureID": uuid(value.captureID),
            "workspaceID": .object(["rawValue": uuid(value.workspaceID.rawValue)]),
            "packageReleaseID": .string(value.packageReleaseID),
            "workflowSHA256": .string(value.workflowSHA256),
            "enteredValue": decimal(value.enteredValue),
            "enteredUnitID": .string(value.enteredUnitID),
            "canonicalValue": decimal(value.canonicalValue),
            "canonicalUnitID": .string(value.canonicalUnitID),
            "dimension": .string(value.dimension.rawValue),
            "precisionScale": .integer(value.precisionScale),
            "uncertaintyCanonical": optionalDecimal(value.uncertaintyCanonical),
            "source": .string(value.source.rawValue),
            "sourceMode": .string(value.sourceMode.rawValue),
            "captureMethodID": .string(value.captureMethodID),
            "instrumentReferenceID": optionalUUID(value.instrumentReferenceID),
            "instrumentID": optionalUUID(value.instrumentID),
            "instrumentKind": value.instrumentKind.map { .string($0.rawValue) } ?? .null,
            "instrumentLifecycleState": value.instrumentLifecycleState.map { .string($0.rawValue) } ?? .null,
            "calibrationSnapshotID": optionalUUID(value.calibrationSnapshotID),
            "calibrationStatus": value.calibrationStatus.map { .string($0.rawValue) } ?? .null,
            "calibrationBasis": value.calibrationBasis.map { .string($0.rawValue) } ?? .null,
            "seriesID": optionalUUID(value.seriesID),
            "seriesState": value.seriesState.map { .string($0.rawValue) } ?? .null,
            "seriesExpectedSampleCount": value.seriesExpectedSampleCount.map { .integer($0) } ?? .null,
            "seriesObservedSampleCount": value.seriesObservedSampleCount.map { .integer($0) } ?? .null,
            "protocolReleaseID": optionalUUID(value.protocolReleaseID),
            "protocolRevision": value.protocolRevision.map { .integer(Int($0)) } ?? .null,
            "aggregationPolicy": value.aggregationPolicy.map { .string($0.rawValue) } ?? .null,
            "qualityResult": value.qualityResult.map { .string($0.rawValue) } ?? .null,
            "qualityReasonCodes": .array(value.qualityReasonCodes.map { .string($0.rawValue) }),
            "qualityPolicyVersion": value.qualityPolicyVersion.map { .string($0) } ?? .null,
            "qualityPolicySHA256": value.qualityPolicySHA256.map { .string($0) } ?? .null,
            "capturedAt": date(value.capturedAt),
            "revision": .integer(Int(value.revision)),
            "captureSHA256": .string(value.captureSHA256),
        ])
    }

    /// C14 history is owned by its canonical inspection-review codec. Keeping
    /// that object intact in the report tree prevents a second report-specific
    /// schema from drifting from the frozen review/change/action facts.
    private static func inspectionReviewHistory(
        _ value: CompletedInspectionReviewHistorySnapshotV1
    ) -> CanonicalJSONValueV1 {
        guard let data = try? InspectionReviewCanonicalCodecV1.encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .null
        }
        return canonicalValue(object)
    }

    /// C41 relationship descriptors and event history are encoded by the
    /// domain's canonical codec first, then copied into the report JSON tree.
    /// This preserves exact nested keys/digests without exposing a second
    /// report-specific wire representation.
    private static func functionalRelationships(
        _ value: CompletedFunctionalRelationshipSnapshotV1
    ) -> CanonicalJSONValueV1 {
        guard let data = try? FunctionalRelationshipCanonicalCodecV1.encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .null
        }
        return canonicalValue(object)
    }

    private static func authorityCriterion(
        _ value: CompletedAuthorityCriterionSnapshotV1
    ) -> CanonicalJSONValueV1 {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            try container.encode(formatter.string(from: date))
        }
        guard let data = try? encoder.encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) else { return .null }
        return canonicalValue(object)
    }

    /// C39 values are already validated and canonically encoded by their
    /// domain codec. Converting that object into the report's canonical JSON
    /// tree keeps report key ordering deterministic without duplicating the
    /// semantic domain's wire schema here.
    private static func assetSemantics(
        _ value: CompletedAssetSemanticsSnapshotV1
    ) -> CanonicalJSONValueV1 {
        guard let data = try? AssetSemanticCanonicalCodecV1.encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .null
        }
        return canonicalValue(object)
    }

    /// The assurance domain codec owns the nested wire representation. Copying
    /// that canonical object into the report tree keeps the preview, manifest,
    /// visibility, and attestation facts byte-stable without duplicating them.
    private static func assurance(
        _ value: ReportEvidenceAssuranceProjectionV1
    ) -> CanonicalJSONValueV1 {
        guard let data = try? ReportEvidenceAssuranceCanonicalCodecV1.encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .null
        }
        return canonicalValue(object)
    }

    /// C15 report output is a typed count/state projection. The packet's
    /// actor, lease, result, and evidence rows are intentionally not copied.
    private static func workPacket(
        _ value: ReportWorkPacketProjectionV1
    ) -> CanonicalJSONValueV1 {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .null
        }
        return canonicalValue(object)
    }

    private static func canonicalValue(_ value: Any) -> CanonicalJSONValueV1 {
        switch value {
        case let value as String: return .string(value)
        case let value as Bool: return .bool(value)
        case let value as NSNumber: return .integer(value.intValue)
        case let value as [Any]: return .array(value.map(canonicalValue))
        case let value as [String: Any]:
            return .object(value.mapValues(canonicalValue))
        case _ as NSNull: return .null
        default: return .null
        }
    }

    private static func accountability(
        _ value: CompletedAccountabilitySnapshotV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "actors": .array(value.actors.map(actor)),
            "parties": .array(value.parties.map(party)),
            "qualifications": .array(value.qualifications.map(qualification)),
            "roleEvents": .array(value.roleEvents.map(roleEvent)),
            "schemaVersion": .integer(value.schemaVersion),
            "signoffs": .array(value.signoffs.map(signoff)),
            "snapshotSHA256": .string(value.snapshotSHA256),
            "workspaceID": uuid(value.workspaceID.rawValue),
        ])
    }

    private static func party(
        _ value: ServicePartyReferenceV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "displayName": .string(value.displayName),
            "effectiveAt": date(value.effectiveAt),
            "kind": .string(value.kind.rawValue),
            "partyID": uuid(value.partyID),
            "privacyClass": .string(value.privacyClass.rawValue),
            "profileDescriptor": optionalString(value.profileDescriptor),
            "provenance": .string(value.provenance.rawValue),
            "receiptSHA256": .string(value.receiptSHA256),
            "retiredAt": optionalDate(value.retiredAt),
            "revision": .integer(Int(value.revision)),
            "schemaVersion": .integer(value.schemaVersion),
            "state": .string(value.state.rawValue),
            "workspaceID": uuid(value.workspaceID.rawValue),
        ])
    }

    private static func roleEvent(
        _ value: SitePartyRoleEventV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "effectiveFrom": date(value.effectiveFrom),
            "effectiveUntil": optionalDate(value.effectiveUntil),
            "eventID": uuid(value.eventID),
            "mutationID": uuid(value.mutationID.rawValue),
            "partyID": uuid(value.partyID),
            "receiptSHA256": .string(value.receiptSHA256),
            "recordedAt": date(value.recordedAt),
            "revision": .integer(Int(value.revision)),
            "role": .string(value.role.rawValue),
            "schemaVersion": .integer(value.schemaVersion),
            "siteID": uuid(value.siteID),
            "source": .string(value.source.rawValue),
            "supersedesEventID": optionalUUID(value.supersedesEventID),
            "workspaceID": uuid(value.workspaceID.rawValue),
        ])
    }

    private static func actor(
        _ value: ActorSnapshotV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "actor": .object([
                "actorReferenceID": uuid(value.actor.actorReferenceID),
                "displayName": .string(value.actor.displayName),
                "partyID": optionalUUID(value.actor.partyID),
                "schemaVersion": .integer(value.actor.schemaVersion),
                "workspaceID": uuid(value.actor.workspaceID.rawValue),
            ]),
            "capturedAt": date(value.capturedAt),
            "displayNameAtTime": .string(value.displayNameAtTime),
            "responsibility": .string(value.responsibility.rawValue),
            "schemaVersion": .integer(value.schemaVersion),
            "snapshotID": uuid(value.snapshotID),
            "snapshotSHA256": .string(value.snapshotSHA256),
            "workspaceID": uuid(value.workspaceID.rawValue),
        ])
    }

    private static func qualification(
        _ value: QualificationSnapshotV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "capturedAt": date(value.capturedAt),
            "credentialLocator": optionalString(value.credentialLocator),
            "declaredScope": .string(value.declaredScope),
            "effectiveAt": optionalDate(value.effectiveAt),
            "expiresAt": optionalDate(value.expiresAt),
            "issuerDisplay": optionalString(value.issuerDisplay),
            "provenance": .string(value.provenance.rawValue),
            "schemaVersion": .integer(value.schemaVersion),
            "snapshotID": uuid(value.snapshotID),
            "snapshotSHA256": .string(value.snapshotSHA256),
            "workspaceID": uuid(value.workspaceID.rawValue),
        ])
    }

    private static func signoff(
        _ value: SignoffSnapshotV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "disposition": .string(value.disposition.rawValue),
            "externalEvidenceID": optionalUUID(value.externalEvidenceID),
            "method": .string(value.method.rawValue),
            "mutationID": uuid(value.mutationID.rawValue),
            "occurredAt": optionalDate(value.occurredAt),
            "purpose": .string(value.purpose),
            "qualification": value.qualification.map(qualification) ?? .null,
            "recordedAt": date(value.recordedAt),
            "roleAssertion": value.roleAssertion.map(roleAssertion) ?? .null,
            "schemaVersion": .integer(value.schemaVersion),
            "snapshotID": uuid(value.snapshotID),
            "snapshotSHA256": .string(value.snapshotSHA256),
            "subjectID": uuid(value.subjectID),
            "subjectRevision": .integer(Int(value.subjectRevision)),
            "supersedesSnapshotID": optionalUUID(value.supersedesSnapshotID),
            "workspaceID": uuid(value.workspaceID.rawValue),
        ])
    }

    private static func roleAssertion(
        _ value: SignoffRoleAssertionV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "actor": actor(value.actor),
            "claimedRelationship": value.claimedRelationship.map { .string($0.rawValue) } ?? .null,
            "claimedRole": .string(value.claimedRole),
            "disclosureRelease": .object([
                "disclosureText": .string(value.disclosureRelease.disclosureText),
                "disclaimsIdentityVerification": .bool(value.disclosureRelease.disclaimsIdentityVerification),
                "disclaimsLegalSignature": .bool(value.disclosureRelease.disclaimsLegalSignature),
                "releaseID": .string(value.disclosureRelease.releaseID),
                "schemaVersion": .integer(value.disclosureRelease.schemaVersion),
                "statesLocalAssertionOnly": .bool(value.disclosureRelease.statesLocalAssertionOnly),
            ]),
            "schemaVersion": .integer(value.schemaVersion),
        ])
    }

    static func requirementAssurance(
        _ value: RequirementAssuranceSnapshotV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "decision": completionDecision(value.decision),
            "evaluatedRevision": .integer(Int(value.evaluatedRevision)),
            "evaluations": .array(value.evaluations.map(evaluation)),
            "findings": .array(value.findings.map(integrityFinding)),
            "policySetSHA256": .string(value.policySetSHA256),
            "schemaVersion": .integer(value.schemaVersion),
            "snapshotSHA256": .string(value.snapshotSHA256),
            "workflowRecordID": uuid(value.workflowRecordID),
            "workspaceID": uuid(value.workspaceID),
        ])
    }

    private static func evaluation(
        _ value: RequirementEvaluationV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "evidenceReferenceIDs": .array(value.evidenceReferenceIDs.map { .string($0) }),
            "evaluatedRevision": .integer(Int(value.evaluatedRevision)),
            "gateEffect": .string(value.gateEffect.rawValue),
            "invalidEvidenceReferences": .array(value.invalidEvidenceReferences.map { .string($0) }),
            "missingEvidenceReferences": .array(value.missingEvidenceReferences.map { .string($0) }),
            "policySHA256": .string(value.policySHA256),
            "reasonCodes": .array(value.reasonCodes.map { .string($0.rawValue) }),
            "requirementID": .string(value.requirementID),
            "requirementTypeID": .string(value.requirementTypeID),
            "requirementVersion": .integer(value.requirementVersion),
            "result": .string(value.result.rawValue),
            "schemaVersion": .integer(value.schemaVersion),
            "waiverID": optionalString(value.waiverID),
        ])
    }

    private static func completionDecision(
        _ value: CompletionDecisionV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "disposition": .string(value.disposition.rawValue),
            "evaluationSetSHA256": .string(value.evaluationSetSHA256),
            "evaluatedRevision": .integer(Int(value.evaluatedRevision)),
            "hardBlockerRequirementIDs": .array(value.hardBlockerRequirementIDs.map { .string($0) }),
            "notApplicableRequirementIDs": .array(value.notApplicableRequirementIDs.map { .string($0) }),
            "policySetSHA256": .string(value.policySetSHA256),
            "schemaVersion": .integer(value.schemaVersion),
            "unknownRequirementIDs": .array(value.unknownRequirementIDs.map { .string($0) }),
            "waivedRequirementIDs": .array(value.waivedRequirementIDs.map { .string($0) }),
            "warningRequirementIDs": .array(value.warningRequirementIDs.map { .string($0) }),
        ])
    }

    private static func integrityFinding(
        _ value: IntegrityFindingV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "kind": .string(value.kind.rawValue),
            "reasonCode": .string(value.reasonCode),
            "referenceIDs": .array(value.referenceIDs.map { .string($0) }),
            "requirementID": optionalString(value.requirementID),
            "schemaVersion": .integer(value.schemaVersion),
        ])
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

extension ReportSnapshotEncoderV1 {
    /// Encodes the C18 package binding as an additive report companion. The
    /// existing report snapshot codecs remain byte-for-byte compatible; this
    /// helper is used only when a report explicitly carries package-evolution
    /// metadata.
    static func encodePackageEvolutionReport(
        _ projection: PackageEvolutionReportProjectionV1
    ) throws -> EncodedReportSnapshotV1 {
        do {
            try projection.validate()
            let data = try PackageEvolutionCanonicalCodecV1.encode(projection)
            guard !data.isEmpty,
                  data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
                throw ReportSnapshotEncodingErrorV1.invalidSnapshot
            }
            return EncodedReportSnapshotV1(
                data: data,
                sha256: KernelCanonicalHashV1.sha256(data)
            )
        } catch let error as ReportSnapshotEncodingErrorV1 {
            throw error
        } catch {
            throw ReportSnapshotEncodingErrorV1.invalidSnapshot
        }
    }

    static func decodePackageEvolutionReport(
        _ data: Data
    ) throws -> PackageEvolutionReportProjectionV1 {
        do {
            let projection = try PackageEvolutionCanonicalCodecV1.decode(
                PackageEvolutionReportProjectionV1.self,
                from: data
            )
            try projection.validate()
            guard try encodePackageEvolutionReport(projection).data == data else {
                throw ReportSnapshotEncodingErrorV1.noncanonicalData
            }
            return projection
        } catch let error as ReportSnapshotEncodingErrorV1 {
            throw error
        } catch {
            throw ReportSnapshotEncodingErrorV1.noncanonicalData
        }
    }

    /// Encodes the standalone C20 projection with the same sorted, local
    /// canonical rules used by the report companion renderers.
    func encode(
        _ projection: PrivacyTransformReportProjectionV1
    ) throws -> EncodedReportSnapshotV1 {
        try projection.validate()
        let data = try PrivacyTransformCanonicalCodecV1.encode(projection)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw ReportSnapshotEncodingErrorV1.invalidSnapshot
        }
        return EncodedReportSnapshotV1(
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data)
        )
    }

    func decodePrivacyTransformProjection(
        _ data: Data
    ) throws -> PrivacyTransformReportProjectionV1 {
        let projection = try PrivacyTransformCanonicalCodecV1.decode(
            PrivacyTransformReportProjectionV1.self,
            from: data
        )
        try projection.validate()
        guard try encode(projection).data == data else {
            throw ReportSnapshotEncodingErrorV1.noncanonicalData
        }
        return projection
    }

    /// Encodes the standalone C21 admission/lifecycle projection using the
    /// canonical client-capability codec. This is metadata only; package bytes
    /// and client identity are not part of the projection.
    func encode(
        _ projection: ClientCapabilityReportProjectionV1
    ) throws -> EncodedReportSnapshotV1 {
        try projection.validate()
        let data = try ClientCapabilityCanonicalCodecV1.encode(projection)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw ReportSnapshotEncodingErrorV1.invalidSnapshot
        }
        return EncodedReportSnapshotV1(
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data)
        )
    }

    func decodeClientCapabilityProjection(
        _ data: Data
    ) throws -> ClientCapabilityReportProjectionV1 {
        let projection = try ClientCapabilityCanonicalCodecV1.decode(
            ClientCapabilityReportProjectionV1.self,
            from: data
        )
        try projection.validate()
        guard try encode(projection).data == data else {
            throw ReportSnapshotEncodingErrorV1.noncanonicalData
        }
        return projection
    }

    /// Encodes only the bounded C23 release/binding projection.  The
    /// canonical pack codec is reused so reports never acquire reference
    /// bytes, private locators, license notices, or subject identity.
    func encode(
        _ projection: FieldReferenceReportProjectionV1
    ) throws -> EncodedReportSnapshotV1 {
        try FieldReferenceReportProjectionPolicyV1.validate(projection, format: .openJSON)
        let data = try FieldReferencePackCanonicalCodecV1.encode(projection)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw ReportSnapshotEncodingErrorV1.invalidSnapshot
        }
        return EncodedReportSnapshotV1(
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data)
        )
    }

    func decodeFieldReferenceProjection(
        _ data: Data
    ) throws -> FieldReferenceReportProjectionV1 {
        let projection = try FieldReferencePackCanonicalCodecV1.decode(
            FieldReferenceReportProjectionV1.self,
            from: data
        )
        try FieldReferenceReportProjectionPolicyV1.validate(projection, format: .openJSON)
        guard try encode(projection).data == data else {
            throw ReportSnapshotEncodingErrorV1.noncanonicalData
        }
        return projection
    }

    /// Encodes the bounded C27 locator report companion.  The canonical
    /// locator codec preserves the recorded interpretation but never adds the
    /// scanned input, key material, or private locator bytes to a report.
    func encode(
        _ projection: AssetLocatorReportProjectionV1
    ) throws -> EncodedReportSnapshotV1 {
        do {
            try projection.validate(format: .openJSON)
            let data = try AssetLocatorCanonicalCodecV1.encode(projection)
            guard !data.isEmpty,
                  data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
                throw ReportSnapshotEncodingErrorV1.invalidSnapshot
            }
            return EncodedReportSnapshotV1(
                data: data,
                sha256: KernelCanonicalHashV1.sha256(data)
            )
        } catch let error as ReportSnapshotEncodingErrorV1 {
            throw error
        } catch {
            throw ReportSnapshotEncodingErrorV1.invalidSnapshot
        }
    }

    func decodeAssetLocatorProjection(
        _ data: Data
    ) throws -> AssetLocatorReportProjectionV1 {
        do {
            let projection = try AssetLocatorCanonicalCodecV1.decode(
                AssetLocatorReportProjectionV1.self,
                from: data
            )
            try projection.validate(format: .openJSON)
            guard try encode(projection).data == data else {
                throw ReportSnapshotEncodingErrorV1.noncanonicalData
            }
            return projection
        } catch let error as ReportSnapshotEncodingErrorV1 {
            throw error
        } catch {
            throw ReportSnapshotEncodingErrorV1.noncanonicalData
        }
    }

    /// Encodes the standalone C37 frozen pose companion. The normal report
    /// encoder includes this value under `placementPose`; this helper makes
    /// the same canonical boundary available to local recovery/export code.
    func encodePlacementPoseSnapshot(
        _ snapshot: C37PlacementPoseFrozenSnapshotV1
    ) throws -> EncodedReportSnapshotV1 {
        try snapshot.validate()
        let data = try PlacementPoseCanonicalCodecV1.encode(snapshot)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw ReportSnapshotEncodingErrorV1.invalidSnapshot
        }
        return EncodedReportSnapshotV1(
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data)
        )
    }

    func decodePlacementPoseSnapshot(
        _ data: Data
    ) throws -> C37PlacementPoseFrozenSnapshotV1 {
        let snapshot = try PlacementPoseCanonicalCodecV1.decode(
            C37PlacementPoseFrozenSnapshotV1.self,
            from: data
        )
        try snapshot.validate()
        guard try encodePlacementPoseSnapshot(snapshot).data == data else {
            throw ReportSnapshotEncodingErrorV1.noncanonicalData
        }
        return snapshot
    }
}
// MARK: - C30 operating-context encoding

extension ReportSnapshotEncoderV1 {
    func encodeOperatingContextReference(
        _ projection: C30EvidenceContextReportReferenceV1
    ) throws -> EncodedReportSnapshotV1 {
        try projection.validate()
        var encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(projection)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw ReportSnapshotEncodingErrorV1.invalidSnapshot
        }
        return EncodedReportSnapshotV1(
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data)
        )
    }

    func decodeOperatingContextReference(
        _ data: Data
    ) throws -> C30EvidenceContextReportReferenceV1 {
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw ReportSnapshotEncodingErrorV1.invalidSnapshot
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(C30EvidenceContextReportReferenceV1.self, from: data)
        try value.validate()
        guard try encodeOperatingContextReference(value).data == data else {
            throw ReportSnapshotEncodingErrorV1.noncanonicalData
        }
        return value
    }

    static let c30OperatingContextEncodingIsStandalone = true
    static let c30OperatingContextEncodingExcludesActorAndSourceBytes = true
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_Finalization_ReportSnapshotEncoderV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Finalization/ReportSnapshotEncoderV1.swift", role: .finalization)
}

extension ReportSnapshotEncoderV1 {
    func encodeLightingProjection(
        _ projection: C31LightingReportProjectionV1
    ) throws -> EncodedReportSnapshotV1 {
        try C31LightingProjectionPolicyV1.validate(projection)
        var encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(projection)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw ReportSnapshotEncodingErrorV1.invalidSnapshot
        }
        return EncodedReportSnapshotV1(
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data)
        )
    }

    func decodeLightingProjection(
        _ data: Data
    ) throws -> C31LightingReportProjectionV1 {
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw ReportSnapshotEncodingErrorV1.invalidSnapshot
        }
        let value = try JSONDecoder().decode(
            C31LightingReportProjectionV1.self,
            from: data
        )
        try C31LightingProjectionPolicyV1.validate(value)
        guard try encodeLightingProjection(value).data == data else {
            throw ReportSnapshotEncodingErrorV1.noncanonicalData
        }
        return value
    }

    static let c31LightingEncodingPreservesFrozenProjection = true
    static let c31LightingEncodingExcludesActorsBytesAndPrivateLocators = true
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Finalization_ReportSnapshotEncoderV1 {
    enum ProposalDispositionV1: Sendable {
        case nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
    }

    enum AcceptanceDispositionV1: Sendable {
        case durableThroughExistingCanonicalWriter
    }

    static func disposition(
        for proposal: AssistanceProposalV1
    ) throws -> ProposalDispositionV1 {
        try proposal.validate()
        guard !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent else {
            throw AssistanceContractFailureV1.nonCanonicalData
        }
        switch proposal.verificationState {
        case .unverified:
            return .nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
        }
    }

    static func disposition(
        for receipt: AssistanceAcceptanceReceiptV1
    ) throws -> AcceptanceDispositionV1 {
        try receipt.validate()
        guard AssistancePersistenceEnrollmentV1.durableModelCount == 1 else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return .durableThroughExistingCanonicalWriter
    }

    static let capabilityScratchIsDiscardedOnTerminalReview = true
    static let manualFallbackRemainsAvailable = true
    static let interruptionNeverPromotesAProposal = true
    static let createsParallelStoreOrWriter = false
}
