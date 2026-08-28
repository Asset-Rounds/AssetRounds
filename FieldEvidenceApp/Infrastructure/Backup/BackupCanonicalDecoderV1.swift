import Foundation

private struct PrivacyTransformCanonicalManifestEnvelopeV1: Decodable {
    let policyID: UUID; let policyRevision: UInt64; let policySHA256: String
}
private struct PrivacyTransformCanonicalReviewEnvelopeV1: Decodable {
    let manifestID: UUID; let manifestRevision: UInt64; let manifestSHA256: String
    let policyID: UUID; let policyRevision: UInt64; let policySHA256: String
}

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
            try Self.validateWorkPackets(value)
            try Self.validateFieldDrafts(value)
            try Self.validatePackageEvolution(value)
            try Self.validateMeasurementIntegrity(value)
            try Self.validatePrivacyTransforms(value)
            try Self.validateClientCapabilities(value)
            try Self.validateRecoverabilityReceipts(value)
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
    static func validateRecoverabilityReceipts(_ records:V4BackupRecordsV1)throws{
        guard records.recordsSchemaVersion>=20 else{guard records.recoverabilityReceipts.isEmpty else{throw BackupCanonicalDecodingErrorV1.invalidRecords};return}
        var keys=Set<UUID>()
        for record in records.recoverabilityReceipts{let value=try RecoverabilityVerificationReceiptRow(RecoverabilityVerificationCanonicalCodecV1.decode(RecoverabilityVerificationReceiptV1.self,from:record.canonicalData)).value();guard record.id==value.receiptID,record.workspaceID==value.workspaceID.rawValue,record.revision==value.revision,keys.insert(record.id).inserted else{throw BackupCanonicalDecodingErrorV1.invalidRecords}}
    }

    static func validateClientCapabilities(_ records:V4BackupRecordsV1)throws{
        guard records.recordsSchemaVersion>=19 else{guard records.clientCapabilities.isEmpty else{throw BackupCanonicalDecodingErrorV1.invalidRecords};return}
        let releases=try records.packageEvolution.filter{$0.kind == .promotedRelease}.map{try PackageEvolutionCanonicalCodecV1.decode(PromotedPackageReleaseV1.self,from:$0.canonicalData).packageRelease}
        let releaseIndex=Dictionary(uniqueKeysWithValues:releases.map{($0.packageReleaseID,$0)});var keys=Set<String>()
        func accept(_ row:V20BackupClientCapabilityRecordV1,_ id:UUID,_ workspaceID:WorkspaceID,_ revision:UInt64)throws{guard row.id==id,row.workspaceID==workspaceID.rawValue,row.revision==revision,keys.insert("\(row.kind.rawValue)|\(row.id.uuidString)").inserted else{throw BackupCanonicalDecodingErrorV1.invalidRecords}}
        let profiles=try Dictionary(uniqueKeysWithValues:records.clientCapabilities.filter{$0.kind == .profile}.map{row in let v=try ClientCapabilityProfileRow(ClientCapabilityCanonicalCodecV1.decode(ClientCapabilityProfileV1.self,from:row.canonicalData)).value();try accept(row,v.profileID,v.workspaceID,v.revision);return(v.profileID,v)})
        let policies=try Dictionary(uniqueKeysWithValues:records.clientCapabilities.filter{$0.kind == .policy}.map{row in let seed=try ClientCapabilityCanonicalCodecV1.decode(PackageLifecyclePolicyV1.self,from:row.canonicalData);guard let release=releaseIndex[seed.packageReleaseID]else{throw BackupCanonicalDecodingErrorV1.invalidRecords};let v=try PackageLifecyclePolicyRow(seed,release:release).value(release:release);try accept(row,v.policyID,v.workspaceID,v.revision);return(v.policyID,v)})
        let dispositions=try Dictionary(uniqueKeysWithValues:records.clientCapabilities.filter{$0.kind == .disposition}.map{row in let seed=try ClientCapabilityCanonicalCodecV1.decode(PackageLifecycleDispositionV1.self,from:row.canonicalData);guard let release=releaseIndex[seed.packageReleaseID]else{throw BackupCanonicalDecodingErrorV1.invalidRecords};let v=try PackageLifecycleDispositionRow(seed,release:release).value(release:release);try accept(row,v.dispositionID,v.workspaceID,v.revision);return(v.dispositionID,v)})
        for row in records.clientCapabilities where row.kind == .admissionDecision{let seed=try ClientCapabilityCanonicalCodecV1.decode(ClientCapabilityAdmissionDecisionV1.self,from:row.canonicalData);guard let profile=profiles[seed.profileID],let policy=policies[seed.policyID],let disposition=dispositions[seed.dispositionID],let release=releaseIndex[seed.packageReleaseID]else{throw BackupCanonicalDecodingErrorV1.invalidRecords};let v=try ClientCapabilityAdmissionDecisionRow(seed,profile:profile,policy:policy,disposition:disposition,release:release).value(profile:profile,policy:policy,disposition:disposition,release:release);try accept(row,v.decisionID,v.workspaceID,v.revision)}
    }

    static func validatePrivacyTransforms(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 18 else {
            guard records.privacyTransforms.isEmpty else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            return
        }
        var keys = Set<String>()
        func accept(_ record: V19BackupPrivacyTransformRecordV1, _ id: UUID, _ workspaceID: WorkspaceID, _ revision: UInt64) throws {
            guard id == record.id, workspaceID.rawValue == record.workspaceID, revision == record.revision,
                  keys.insert("\(record.kind.rawValue)|\(record.id.uuidString)").inserted else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
        }
        let policyPairs = try records.privacyTransforms.filter { $0.kind == .policy }.map { record -> (UUID, PrivacyTransformPolicyV1) in
            let value = try PrivacyTransformPolicyRow(PrivacyTransformCanonicalCodecV1.decodePolicy(from: record.canonicalData)).value()
            try accept(record, value.policyID, value.workspaceID, value.revision); return (value.policyID, value)
        }
        let policies = Dictionary(uniqueKeysWithValues: policyPairs)
        for record in records.privacyTransforms where record.kind == .region {
            let value = try PrivacyRegionRow(PrivacyTransformCanonicalCodecV1.decodeRegion(from: record.canonicalData)).value()
            try accept(record, value.regionID, value.workspaceID, value.revision)
        }
        let manifestPairs = try records.privacyTransforms.filter { $0.kind == .manifest }.map { record -> (UUID, PrivacyTransformManifestV1) in
            let reference = try JSONDecoder().decode(PrivacyTransformCanonicalManifestEnvelopeV1.self, from: record.canonicalData)
            guard let policy = policies[reference.policyID], policy.revision == reference.policyRevision, policy.policySHA256 == reference.policySHA256 else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            let provisional = try PrivacyTransformCanonicalCodecV1.decodeManifest(from: record.canonicalData, policy: policy)
            let value = try PrivacyTransformManifestRow(provisional).value(policy: policy)
            try accept(record, value.manifestID, value.workspaceID, value.revision); return (value.manifestID, value)
        }
        let manifests = Dictionary(uniqueKeysWithValues: manifestPairs)
        for record in records.privacyTransforms where record.kind == .reviewReceipt {
            let reference = try JSONDecoder().decode(PrivacyTransformCanonicalReviewEnvelopeV1.self, from: record.canonicalData)
            guard let manifest = manifests[reference.manifestID], manifest.revision == reference.manifestRevision, manifest.manifestSHA256 == reference.manifestSHA256,
                  let policy = policies[reference.policyID], policy.revision == reference.policyRevision, policy.policySHA256 == reference.policySHA256 else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            let provisional = try PrivacyTransformCanonicalCodecV1.decodeReview(from: record.canonicalData, manifest: manifest, policy: policy)
            let value = try PrivacyReviewReceiptRow(provisional).value(manifest: manifest, policy: policy)
            try accept(record, value.receiptID, value.workspaceID, value.revision)
        }
    }

    static func validateMeasurementIntegrity(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 17 else {
            guard records.measurementIntegrity.isEmpty else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            return
        }
        var keys = Set<String>()
        for record in records.measurementIntegrity {
            let identity: (UUID, WorkspaceID, UInt64)
            switch record.kind {
            case .instrumentReference:
                let v = try MeasurementIntegrityCanonicalCodecV1.decode(InstrumentReferenceV1.self, from: record.canonicalData); identity = (v.referenceID, v.workspaceID, v.revision)
            case .calibrationSnapshot:
                let v = try MeasurementIntegrityCanonicalCodecV1.decode(CalibrationStatusSnapshotV1.self, from: record.canonicalData); identity = (v.snapshotID, v.workspaceID, v.revision)
            case .measurementCapture:
                let v = try MeasurementIntegrityCanonicalCodecV1.decode(MeasurementCaptureV1.self, from: record.canonicalData); identity = (v.captureID, v.workspaceID, v.revision)
            case .measurementSeries:
                let v = try MeasurementIntegrityCanonicalCodecV1.decode(MeasurementSeriesV1.self, from: record.canonicalData); identity = (v.snapshotID, v.workspaceID, v.revision)
            case .qualityAssessment:
                let v = try MeasurementIntegrityCanonicalCodecV1.decode(MeasurementQualityAssessmentV1.self, from: record.canonicalData); identity = (v.assessmentID, v.workspaceID, v.revision)
            }
            guard identity.0 == record.id, identity.1.rawValue == record.workspaceID,
                  identity.2 == record.revision,
                  keys.insert("\(record.kind.rawValue)|\(record.id.uuidString)").inserted else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }
    }

    static func validatePackageEvolution(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 16 else {
            guard records.packageEvolution.isEmpty else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            return
        }
        var keys = Set<String>()
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        for record in records.packageEvolution {
            guard record.id != zero, record.workspaceID != zero, record.revision > 0,
                  !record.canonicalData.isEmpty,
                  keys.insert("\(record.kind.rawValue)|\(record.id.uuidString)").inserted else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }
    }

    static func validateFieldDrafts(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 15 else {
            guard records.fieldDrafts.isEmpty else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            return
        }
        for record in records.fieldDrafts {
            let identity: (UUID, WorkspaceID, UInt64)
            switch record.kind {
            case .checkpoint:
                let v = try FieldDraftCanonicalCodecV1.decode(FieldDraftCheckpointV1.self, from: record.canonicalData)
                identity = (v.draftID, v.workspaceID, v.draftRevision)
            case .stagingItem:
                let v = try FieldDraftCanonicalCodecV1.decode(AttachmentStagingItemV1.self, from: record.canonicalData)
                identity = (v.stageID, v.workspaceID, v.revision)
            case .commitSaga:
                let v = try FieldDraftCanonicalCodecV1.decode(DraftCommitSagaV1.self, from: record.canonicalData)
                identity = (v.sagaID, v.workspaceID, v.revision)
            case .contentReservation:
                let v = try FieldDraftCanonicalCodecV1.decode(DraftContentReservationV1.self, from: record.canonicalData)
                identity = (v.reservationID, v.workspaceID, v.revision)
            case .commitReceipt:
                let v = try FieldDraftCanonicalCodecV1.decode(DraftCommitReceiptV1.self, from: record.canonicalData)
                identity = (v.receiptID, v.workspaceID, v.revision)
            case .discardReceipt:
                let v = try FieldDraftCanonicalCodecV1.decode(DraftDiscardReceiptV1.self, from: record.canonicalData)
                identity = (v.receiptID, v.workspaceID, v.revision)
            }
            guard identity.0 == record.id, identity.1.rawValue == record.workspaceID,
                  identity.2 == record.revision else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }
    }

    static func validateWorkPackets(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 14 else {
            guard records.workPackets.isEmpty else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            return
        }
        for record in records.workPackets {
            let identity: (UUID, WorkspaceID, UInt64)
            switch record.kind {
            case .manifest:
                let v = try WorkPacketCanonicalCodecV1.decode(WorkPacketManifestV1.self, from: record.canonicalData); identity=(v.manifestID,v.workspaceID,v.revision)
            case .claim:
                let v = try WorkPacketCanonicalCodecV1.decode(WorkItemClaimV1.self, from: record.canonicalData); identity=(v.claimID,v.workspaceID,v.revision)
            case .lease:
                let v = try WorkPacketCanonicalCodecV1.decode(WorkLeaseV1.self, from: record.canonicalData); identity=(v.leaseID,v.workspaceID,v.revision)
            case .release:
                let v = try WorkPacketCanonicalCodecV1.decode(WorkReleaseV1.self, from: record.canonicalData); identity=(v.releaseID,v.workspaceID,v.revision)
            case .handoff:
                let v = try WorkPacketCanonicalCodecV1.decode(WorkHandoffV1.self, from: record.canonicalData); identity=(v.handoffID,v.workspaceID,v.revision)
            }
            guard identity.0 == record.id, identity.1.rawValue == record.workspaceID,
                  identity.2 == record.revision else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
        }
    }

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
