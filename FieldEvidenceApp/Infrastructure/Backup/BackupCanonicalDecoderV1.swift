import Foundation

struct BackupCanonicalDecoderV1: Sendable {
    func decodeManifestOffMain(
        _ data: Data,
        context: ResumableLocalJobExecutionContextV1? = nil
    ) async throws -> V4BackupManifestV1 {
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        let value = try await BackupOffMainWorkV1.run {
            try Self().decodeManifest(data)
        }
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        return value
    }

    func decodeRecordsOffMain(
        _ data: Data,
        context: ResumableLocalJobExecutionContextV1? = nil
    ) async throws -> V4BackupRecordsV1 {
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        let value = try await BackupOffMainWorkV1.run {
            try Self().decodeRecords(data)
        }
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        return value
    }

    func decodeManifest(_ data: Data) throws -> V4BackupManifestV1 {
        do {
            let value = try decoder().decode(V4BackupManifestV1.self, from: data)
            let canonical = try BackupCanonicalEncoderV1().encodeManifest(value).data
            guard canonical == data else {
                throw BackupCanonicalDecodingErrorV1.invalidManifest
            }
            return value
        } catch {
            throw BackupCanonicalDecodingErrorV1.invalidManifest
        }
    }

    func decodeRecords(_ data: Data) throws -> V4BackupRecordsV1 {
        do {
            let value = try decoder().decode(V4BackupRecordsV1.self, from: data)
            try Self.validatePartyAccountability(value)
            try Self.validateAssetSemantics(value)
            try Self.validateAuthorityCriterion(value)
            try Self.validateFunctionalRelationships(value)
            try Self.validateEvidenceAssurance(value)
            try Self.validateInspectionReview(value)
            let canonical = try BackupCanonicalEncoderV1().encodeRecords(value).data
            guard canonical == data else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
            return value
        } catch {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
    }
}

private extension BackupCanonicalDecoderV1 {
    static func validateInspectionReview(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 13 else {
            guard records.inspectionReview.isEmpty else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            return
        }
        for record in records.inspectionReview {
            let identity: (UUID, WorkspaceID, UInt64)
            switch record.kind {
            case .reviewTransition:
                let value = try InspectionReviewCanonicalCodecV1.decode(InspectionReviewTransitionV1.self, from: record.canonicalData)
                identity = (value.transitionID, value.workspaceID, value.revision)
            case .reviewDisposition:
                let value = try InspectionReviewCanonicalCodecV1.decode(ReviewDispositionV1.self, from: record.canonicalData)
                identity = (value.dispositionID, value.workspaceID, value.revision)
            case .changeRequest:
                let value = try InspectionReviewCanonicalCodecV1.decode(ChangeRequestV1.self, from: record.canonicalData)
                identity = (value.requestRevisionID, value.workspaceID, value.revision)
            case .correctiveActionPolicy:
                let value = try InspectionReviewCanonicalCodecV1.decode(CorrectiveActionPolicyV1.self, from: record.canonicalData)
                identity = (value.releaseID, value.workspaceID, value.revision)
            case .correctiveActionEvent:
                let value = try InspectionReviewCanonicalCodecV1.decode(CorrectiveActionEventV1.self, from: record.canonicalData)
                identity = (value.eventID, value.workspaceID, value.revision)
            }
            guard identity.0 == record.id, identity.1.rawValue == record.workspaceID,
                  identity.2 == record.revision else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
        }
    }

    static func validateEvidenceAssurance(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 12 else {
            guard records.evidenceAssurance.isEmpty else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            return
        }
        for record in records.evidenceAssurance {
            let identity: (UUID, WorkspaceID, UInt64)
            switch record.kind {
            case .visibility:
                let value = try EvidenceAssuranceCanonicalCodecV1.decode(EvidenceVisibilityV1.self, from: record.canonicalData)
                identity = (value.visibilityID, value.workspaceID, value.revision)
            case .evidenceLink:
                let value = try EvidenceAssuranceCanonicalCodecV1.decode(ClaimEvidenceLinkV1.self, from: record.canonicalData)
                identity = (value.linkID, value.workspaceID, value.revision)
            case .manifest:
                let value = try EvidenceAssuranceCanonicalCodecV1.decode(AssuranceManifestV1.self, from: record.canonicalData)
                identity = (value.manifestID, value.workspaceID, value.revision)
            case .attestation:
                let value = try EvidenceAssuranceCanonicalCodecV1.decode(AttestationV1.self, from: record.canonicalData)
                identity = (value.attestationID, value.workspaceID, value.revision)
            }
            guard identity.0 == record.id, identity.1.rawValue == record.workspaceID,
                  identity.2 == record.revision else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
        }
    }

    static func validateFunctionalRelationships(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 11 else {
            guard records.functionalRelationships.isEmpty else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            return
        }
        for record in records.functionalRelationships {
            let identity: (UUID, WorkspaceID, UInt64)
            switch record.kind {
            case .descriptor:
                let value = try FunctionalRelationshipCanonicalCodecV1.decode(FunctionalRelationshipTypeDescriptorV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.descriptorReleaseID, value.workspaceID, value.revision)
            case .event:
                let value = try FunctionalRelationshipCanonicalCodecV1.decode(AssetFunctionalRelationshipEventV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.eventID, value.workspaceID, value.revision)
            }
            guard identity.0 == record.id, identity.1.rawValue == record.workspaceID,
                  identity.2 == record.revision else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
        }
    }

    static func validateAuthorityCriterion(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 10 else {
            guard records.authorityCriterion.isEmpty else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            return
        }
        for record in records.authorityCriterion {
            let identity: (UUID, WorkspaceID, Bool)
            switch record.kind {
            case .authoritySourceRelease:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(AuthoritySourceReleaseV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.releaseID, value.workspaceID, try AuthorityCriterionCanonicalCodecV1.encode(value) == record.canonicalData)
            case .requirementBasisBinding:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(RequirementBasisBindingV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.bindingID, value.workspaceID, try AuthorityCriterionCanonicalCodecV1.encode(value) == record.canonicalData)
            case .applicabilityContextSnapshot:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(ApplicabilityContextSnapshotV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.snapshotID, value.workspaceID, try AuthorityCriterionCanonicalCodecV1.encode(value) == record.canonicalData)
            case .assessmentScopeSnapshot:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(AssessmentScopeSnapshotV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.snapshotID, value.workspaceID, try AuthorityCriterionCanonicalCodecV1.encode(value) == record.canonicalData)
            case .severityScaleRelease:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(SeverityScaleReleaseV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.releaseID, value.workspaceID, try AuthorityCriterionCanonicalCodecV1.encode(value) == record.canonicalData)
            case .findingClassificationBinding:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(FindingClassificationBindingV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.bindingID, value.workspaceID, try AuthorityCriterionCanonicalCodecV1.encode(value) == record.canonicalData)
            case .measurementProtocolRelease:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(MeasurementProtocolReleaseV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.releaseID, value.workspaceID, try AuthorityCriterionCanonicalCodecV1.encode(value) == record.canonicalData)
            case .derivedFactEvaluatorDescriptor:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(DerivedFactEvaluatorDescriptorV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.descriptorID, value.workspaceID, try AuthorityCriterionCanonicalCodecV1.encode(value) == record.canonicalData)
            case .derivedFactProvenance:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(DerivedFactProvenanceV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.provenanceID, value.workspaceID, try AuthorityCriterionCanonicalCodecV1.encode(value) == record.canonicalData)
            }
            guard identity.0 == record.id, identity.1.rawValue == record.workspaceID,
                  identity.2 else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }
    }

    static func validateAssetSemantics(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 9 else {
            guard records.assetSemantics.isEmpty else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
            return
        }
        for record in records.assetSemantics {
            let identity: (UUID, WorkspaceID, UInt64)
            switch record.kind {
            case .kindBindingEvent:
                let value = try AssetSemanticCanonicalCodecV1.decode(
                    AssetKindBindingEventV1.self, from: record.canonicalData
                )
                try value.validate(); identity = (value.eventID, value.workspaceID, value.revision)
            case .workflowCapabilityBindingEvent:
                let value = try AssetSemanticCanonicalCodecV1.decode(
                    AssetWorkflowCapabilityBindingEventV1.self, from: record.canonicalData
                )
                try value.validate(); identity = (value.eventID, value.workspaceID, value.revision)
            case .productIdentity:
                let value = try AssetSemanticCanonicalCodecV1.decode(
                    AssetProductIdentityV1.self, from: record.canonicalData
                )
                try value.validate(); identity = (value.identityID, value.workspaceID, value.revision)
            case .lifecycleEvent:
                let value = try AssetSemanticCanonicalCodecV1.decode(
                    AssetLifecycleEventV1.self, from: record.canonicalData
                )
                try value.validate()
                identity = (value.record.eventID, value.record.workspaceID, value.record.revision)
            case .successorLink:
                let value = try AssetSemanticCanonicalCodecV1.decode(
                    AssetSuccessorLinkV1.self, from: record.canonicalData
                )
                try value.validate(); identity = (value.linkID, value.workspaceID, value.revision)
            case .workSubjectScopeSnapshot:
                let value = try AssetSemanticCanonicalCodecV1.decode(
                    WorkSubjectScopeSnapshotV1.self, from: record.canonicalData
                )
                try value.validate()
                identity = (value.snapshotID, value.workspaceID, value.workspaceRevision)
            }
            guard identity.0 == record.id,
                  identity.1.rawValue == record.workspaceID,
                  identity.2 == record.revision else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }
    }

    static func validatePartyAccountability(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 8 else {
            guard records.partyAccountability.isEmpty else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
            return
        }
        var partyIDs = Set<UUID>()
        var roleValues: [SitePartyRoleEventV1] = []
        var actorValues: [UUID: ActorSnapshotV1] = [:]
        var qualificationValues: [UUID: QualificationSnapshotV1] = [:]
        var signoffValues: [SignoffSnapshotV1] = []
        for record in records.partyAccountability {
            switch record.kind {
            case .serviceParty:
                let value = try PartyAccountabilitySnapshotCodecV1.decode(
                    ServicePartyReferenceV1.self, from: record.canonicalData
                )
                guard value.partyID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision,
                      partyIDs.insert(value.partyID).inserted else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
            case .sitePartyRoleEvent:
                let value = try PartyAccountabilitySnapshotCodecV1.decode(
                    SitePartyRoleEventV1.self, from: record.canonicalData
                )
                guard value.eventID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
                roleValues.append(value)
            case .actorSnapshot:
                let value = try PartyAccountabilitySnapshotCodecV1.decode(
                    ActorSnapshotV1.self, from: record.canonicalData
                )
                guard value.snapshotID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      record.revision == nil,
                      actorValues.updateValue(value, forKey: value.snapshotID) == nil else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
            case .qualificationSnapshot:
                let value = try PartyAccountabilitySnapshotCodecV1.decode(
                    QualificationSnapshotV1.self, from: record.canonicalData
                )
                guard value.snapshotID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      record.revision == nil,
                      qualificationValues.updateValue(value, forKey: value.snapshotID) == nil else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
            case .signoffSnapshot:
                let value = try PartyAccountabilitySnapshotCodecV1.decode(
                    SignoffSnapshotV1.self, from: record.canonicalData
                )
                guard value.snapshotID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.subjectRevision == record.revision else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
                signoffValues.append(value)
            }
        }
        let siteIDs = Set(records.sites.map(\.id))
        guard roleValues.allSatisfy({
                  partyIDs.contains($0.partyID) && siteIDs.contains($0.siteID)
              }),
              actorValues.values.allSatisfy({ value in
                  value.actor.partyID.map(partyIDs.contains) ?? true
              }),
              signoffValues.allSatisfy({ value in
                  (value.roleAssertion.map {
                      actorValues[$0.actor.snapshotID] == $0.actor
                  } ?? true)
                    && (value.qualification.map {
                        qualificationValues[$0.snapshotID] == $0
                    } ?? true)
              }) else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
    }

    func decoder() -> JSONDecoder {
        let value = JSONDecoder()
        let timestampFormatter = Self.makeTimestampFormatter()
        value.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard Self.isCanonicalTimestamp(string),
                  let date = timestampFormatter.date(from: string),
                  timestampFormatter.string(from: date) == string else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected canonical RFC3339 UTC milliseconds"
                )
            }
            return date
        }
        return value
    }

    static func isCanonicalTimestamp(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 24 else { return false }
        let punctuation: [Int: UInt8] = [
            4: 0x2d,
            7: 0x2d,
            10: 0x54,
            13: 0x3a,
            16: 0x3a,
            19: 0x2e,
            23: 0x5a,
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

    static func makeTimestampFormatter() -> ISO8601DateFormatter {
        let value = ISO8601DateFormatter()
        value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        value.timeZone = TimeZone(secondsFromGMT: 0)
        return value
    }
}
