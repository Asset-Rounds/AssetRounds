import Foundation
import SwiftData

/// Synchronous admission for the one bounded first-sign compensation. This
/// reader never writes, saves, acquires a lease, or constructs a file owner.
/// Unknown retained payload ownership is a refusal, not evidence of absence.
@MainActor
enum FirstSignCompensationAdmissionV1 {
    private static let maximumRows = 100_000

    static func admit(
        _ payload: FirstSignCompensationV1,
        in context: ModelContext,
        generationID: UUID
    ) throws -> Asset {
        try payload.validate()
        guard !context.hasChanges else { throw WorkspaceMutationFailureV1.invalidReversal }
        let reader = Reader(context: context, assetID: payload.assetID,
                            workspaceID: payload.expectedRevision.workspaceID)
        try reader.requireEnrollment()
        let deletion = try DeletionIdentityV2(kind: .asset, id: payload.assetID)
        guard !Set(try DeletionLedgerStore(context: context, privateSystemDiscoveryIndex: nil)
            .snapshot().entries.map(\.identity)).contains(deletion) else {
            throw WorkspaceMutationFailureV1.invalidReversal
        }
        let asset = try WholeSignDeletionService.firstSignCompensationCoreAdmission(
            in: context, generationID: generationID, payload: payload)
        try reader.validateTypedRoots()
        try reader.validateDraftHistory()
        try reader.requireResolvedOwners()
        guard !context.hasChanges else { throw WorkspaceMutationFailureV1.invalidReversal }
        return asset
    }

    @MainActor
    private struct Reader {
        let context: ModelContext
        let assetID: UUID
        let workspaceID: WorkspaceID

        func rows<T: PersistentModel>(_ type: T.Type) throws -> [T] {
            var descriptor = FetchDescriptor<T>()
            descriptor.fetchLimit = maximumRows + 1
            let values = try context.fetch(descriptor)
            guard values.count <= maximumRows else {
                throw WorkspaceMutationFailureV1.invalidReversal
            }
            return values
        }

        func absent(_ id: UUID?) throws {
            guard id != assetID else { throw WorkspaceMutationFailureV1.invalidReversal }
        }

        func subject(_ value: WorkSubjectReferenceV1) throws {
            try value.validate()
            if value.kind == .asset { try absent(value.subjectID) }
            try absent(value.ownerAssetID)
            if let reference = value.functionalRelationship {
                let matches = try rows(AssetFunctionalRelationshipEventRow.self)
                    .map { try $0.value() }.filter {
                        $0.workspaceID == workspaceID
                            && $0.relationshipID == reference.relationshipID
                            && $0.revision == reference.relationshipRevision
                    }
                guard matches.count == 1, let value = matches.first else {
                    throw WorkspaceMutationFailureV1.invalidReversal
                }
                let descriptors = try rows(FunctionalRelationshipTypeDescriptorRow.self)
                    .map { try $0.value() }.filter {
                        $0.workspaceID == workspaceID
                            && $0.descriptorReleaseID == reference.descriptorReleaseID
                            && $0.revision == reference.descriptorReleaseRevision
                    }
                guard descriptors.count == 1, let descriptor = descriptors.first,
                      value.descriptor == FunctionalRelationshipDescriptorReferenceV1(descriptor),
                      descriptor.packageRelease == reference.packageRelease,
                      descriptor.sourceCatalogRelease == reference.semanticCatalogRelease,
                      descriptor.semanticID == reference.semanticID else {
                    throw WorkspaceMutationFailureV1.invalidReversal
                }
                // A composition-component subjectID has no EdgeID meaning.
                // Functional relationships, in contrast, own typed endpoints.
                try absent(value.sourceAssetID)
                try absent(value.targetAssetID)
            }
        }

        func scope(_ value: WorkSubjectScopeSnapshotV1) throws {
            try value.validate()
            guard value.workspaceID == workspaceID else {
                throw WorkspaceMutationFailureV1.invalidReversal
            }
            for value in value.subjects { try subject(value) }
            for value in value.semanticBindings { try absent(value.assetID) }
        }

        func round(_ value: RoundSessionV1) throws {
            try value.validateIntrinsic()
            for item in value.items { try absent(item.selection.assetID) }
        }

        func validateTypedRoots() throws {
            for row in try rows(AssetKindBindingEventRow.self) { try absent(row.value().assetID) }
            for row in try rows(AssetWorkflowCapabilityBindingEventRow.self) { try absent(row.value().assetID) }
            for row in try rows(AssetProductIdentityRow.self) { try absent(row.value().assetID) }
            for row in try rows(AssetLifecycleEventRow.self) { try absent(row.value().record.assetID) }
            for row in try rows(AssetSuccessorLinkRow.self) {
                let value = try row.value()
                try absent(value.predecessorAssetID); try absent(value.successorAssetID)
            }
            for row in try rows(AssetCompositionEventRow.self) {
                let value = try row.value()
                try absent(value.edge.parentAssetID); try absent(value.edge.childAssetID)
            }
            for row in try rows(AssetFunctionalRelationshipEventRow.self) {
                let value = try row.value()
                try absent(value.sourceAssetID); try absent(value.targetAssetID)
            }
            for row in try rows(WorkSubjectScopeSnapshotRow.self) { try scope(row.value()) }
            for row in try rows(ApplicabilityContextSnapshotRow.self) { try scope(row.value().workSubjectScope) }
            for row in try rows(AssessmentScopeSnapshotRow.self) { try scope(row.value().workSubjectScope) }
            for row in try rows(EvidenceContextRow.self) { try absent(row.value().assetID) }
            for row in try rows(PairedObservationLinkRow.self) {
                let value = try row.value()
                try absent(value.first.assetID); try absent(value.second.assetID)
            }
            for row in try rows(AssetPoseEventRow.self) { try absent(row.value().assetID) }
            for row in try rows(SpatialAnchorObservationRow.self) { try absent(row.value().assetID) }
            for row in try rows(PlanPlacementRow.self) {
                let value = try row.value()
                if value.subjectKind == .asset {
                    try absent(value.subjectID); try absent(value.assetLocatorBinding?.assetID)
                } else {
                    // No incumbent general observation/location-to-Asset owner
                    // resolver is available here. Never reinterpret its UUID.
                    throw WorkspaceMutationFailureV1.invalidReversal
                }
            }
            for row in try rows(RoundSessionRevisionRowV1.self) { try round(row.value()) }
            for row in try rows(AcceptedLabelGenerationSnapshotRow.self) {
                for item in try row.value().plan.items { try absent(item.assetID) }
            }
            for row in try rows(ServiceRequestRecordRow.self) {
                for asset in try row.value().scope.assets { try absent(asset.assetID) }
            }
            for row in try rows(ServiceRequestWorkLinkEventRow.self) {
                let value = try row.value()
                try subject(value.target)
                // target is not the whole retained work owner. Its separate
                // canonical work tuple has no complete incumbent item resolver.
                throw WorkspaceMutationFailureV1.invalidReversal
            }
            for row in try rows(AssetServiceIncidentRow.self) { try reliability(row.value().subject) }
            for row in try rows(ServiceImpactSegmentRow.self) { try reliability(row.value().subject) }
            for row in try rows(ServiceCauseAssertionRow.self) { try reliability(row.value().subject) }
            for row in try rows(ServiceRemedyAssertionRow.self) {
                let value = try row.value()
                try reliability(value.subject); try scheduledWork(value.work)
            }
            for row in try rows(ServiceRepairIntervalRow.self) {
                let value = try row.value()
                try reliability(value.subject)
                if let work = value.work { try scheduledWork(work) }
            }
            for row in try rows(ServiceRestorationAssertionRow.self) { try reliability(row.value().subject) }
            for row in try rows(QualifiedServiceExposureRow.self) { try reliability(row.value().subject) }
            try validateLighting()
            try validateOtherTypedRoots()
            try validateIndependentMetadata()
        }

        func reliability(_ value: ServiceReliabilitySubjectV1) throws {
            try value.validate()
            try subject(value.asset); try scope(value.frozenScope)
        }

        func scheduledWork(_ value: ScheduledWorkInstanceReferenceV1) throws {
            try value.validate()
            switch value {
            case .workPacket:
                // A manifest item's kind/string/digest does not itself resolve
                // the inspection/review/finding owner's Asset relationship.
                throw WorkspaceMutationFailureV1.invalidReversal
            case let .roundSession(id, revision, digest):
                let matches = try rows(RoundSessionRevisionRowV1.self).map { try $0.value() }.filter {
                    $0.workspaceID == workspaceID && $0.sessionID == id
                        && $0.revision == revision && $0.sessionSHA256 == digest
                }
                guard matches.count == 1 else { throw WorkspaceMutationFailureV1.invalidReversal }
                try round(matches[0])
            }
        }

        func survey(_ value: SurveySessionV1) throws {
            try value.validateIntrinsic()
            switch value.subject {
            case let .canonical(reference): try subject(reference)
            case .provisional: break // Provisional identities are not Assets.
            }
        }

        func validateOtherTypedRoots() throws {
            for row in try rows(AssetLocatorRow.self) { try absent(row.value().assetID) }
            let sessions = try rows(SurveySessionRow.self).map { try $0.value() }
            for value in sessions { try survey(value) }
            for row in try rows(SubjectPromotionReceiptRow.self) { try subject(row.value().canonicalSubject) }
            for row in try rows(ScheduleDefinitionReleaseRow.self) { try subject(row.value().subject) }
            let clips = try rows(TemporalEvidenceClipRow.self).map { try $0.value() }
            for value in clips {
                let matches = sessions.filter {
                    $0.workspaceID == value.target.workspaceID && $0.sessionID == value.target.sessionID
                        && $0.revision == value.target.sessionRevision && $0.sessionSHA256 == value.target.sessionSHA256
                }
                guard matches.count == 1 else { throw WorkspaceMutationFailureV1.invalidReversal }
                try survey(matches[0])
            }
            for row in try rows(TimecodedEvidenceAnchorRow.self) {
                let value = try row.value()
                let matches = clips.filter {
                    $0.workspaceID == value.workspaceID && $0.clipID == value.clipID
                        && $0.revision == value.clipRevision && $0.clipSHA256 == value.clipSHA256
                }
                guard matches.count == 1 else { throw WorkspaceMutationFailureV1.invalidReversal }
                try value.validate(clip: matches[0])
            }
            for row in try rows(EntityAliasLinkRowV1.self) {
                let value = try row.value()
                for identity in [value.alias.identity, value.canonicalEntity.identity] {
                    if identity.kind == .asset { try absent(identity.id) }
                }
            }
            for row in try rows(EntityConsolidationReceiptRowV1.self) {
                let value = try row.value()
                for identity in [value.source.identity, value.survivor.identity] {
                    if identity.kind == .asset { try absent(identity.id) }
                }
            }
            for row in try rows(EntityIdentityResolutionMutationReceiptRowV1.self) { _ = try row.value() }
        }

        func validateIndependentMetadata() throws {
            // These canonical types carry configuration/category/party/Site or
            // immutable receipt provenance, not an Asset owner. Text is never
            // searched for an identity. Owning domain roots are checked apart.
            for row in try rows(SavedSmartViewRowV1.self) { _ = try row.descriptor() }
            for row in try rows(EvidenceVisibilityRow.self) { _ = try row.value() }
            for row in try rows(ExceptionCalendarReleaseRow.self) { _ = try row.value() }
            for row in try rows(ServiceContactPointRow.self) { _ = try row.value() }
            for row in try rows(SystemHandoffIntentRow.self) { _ = try row.value() }
            for row in try rows(CaptureInboxItemRowV1.self) { _ = try row.value() }
            for row in try rows(SnippetRowV1.self) { _ = try row.value() }
            for row in try rows(FastSurveyInboxMutationReceiptRowV1.self) { _ = try row.value() }
            for row in try rows(ImportMappingProfileRowV1.self) { _ = try row.value() }
            for row in try rows(BulkSessionRowV1.self) { _ = try row.value() }
            for row in try rows(BulkCommitReceiptRowV1.self) { _ = try row.value() }
            for row in try rows(PracticeWorkspaceProvenanceRowV1.self) { _ = try row.value() }
            for row in try rows(AuthoritySourceReleaseRow.self) { _ = try row.value() }
            for row in try rows(RequirementBasisBindingRow.self) { _ = try row.value() }
            for row in try rows(SeverityScaleReleaseRow.self) { _ = try row.value() }
            for row in try rows(MeasurementProtocolReleaseRow.self) { _ = try row.value() }
            for row in try rows(DerivedFactEvaluatorDescriptorRow.self) { _ = try row.value() }
            for row in try rows(LocationNodeRow.self) { _ = try row.value() }
            for row in try rows(LocationHierarchyEventRow.self) { _ = try row.values() }
            for row in try rows(ServicePartyRow.self) { _ = try row.value() }
            for row in try rows(SitePartyRoleEventRow.self) { _ = try row.value() }
            for row in try rows(ActorSnapshotRow.self) { _ = try row.value() }
            for row in try rows(QualificationSnapshotRow.self) { _ = try row.value() }
            for row in try rows(SignoffSnapshotRow.self) { _ = try row.value() }
            for row in try rows(PromotedPackageReleaseRow.self) { _ = try row.value() }
            for row in try rows(PackageSandboxRunRow.self) { _ = try row.value() }
            for row in try rows(PackagePromotionReceiptRow.self) { _ = try row.value() }
            for row in try rows(ActivePackageRegistryPointerRow.self) { _ = try row.value() }
            for row in try rows(InstrumentReferenceRow.self) { _ = try row.value() }
            for row in try rows(CalibrationStatusSnapshotRow.self) { _ = try row.value() }
            for row in try rows(CorrectiveActionPolicyRow.self) { _ = try row.value() }
            for row in try rows(PrivacyTransformPolicyRow.self) { _ = try row.value() }
            for row in try rows(ClientCapabilityProfileRow.self) { _ = try row.value() }
            try validateClientCapabilityMetadata()
            for row in try rows(FieldReferenceReleaseRow.self) { _ = try row.value() }
            try validateFieldReferenceOwners()
            for row in try rows(RecoverabilityVerificationReceiptRow.self) { _ = try row.value() }
            for row in try rows(SurveyDefinitionIdentityRow.self) { _ = try row.value() }
            for row in try rows(SurveyDefinitionReleaseRow.self) { _ = try row.value() }
            for row in try rows(AccessibleDocumentAssessmentReceiptRow.self) { _ = try row.value() }
            for row in try rows(LocalPartDefinitionRowV1.self) { _ = try row.value() }
            for row in try rows(StockStorageLocationRowV1.self) { _ = try row.value() }
            for row in try rows(ShopReportProfileRowV1.self) { _ = try row.value() }
            for row in try rows(PlanDocumentRow.self) { _ = try row.value() }
            for row in try rows(PlanRevisionRow.self) { _ = try row.value() }
            try validateQualityProvenance()
            let markers = try rows(PersistentSchemaReleaseMarker.self)
            guard markers.count <= 1 else { throw WorkspaceMutationFailureV1.invalidReversal }
            for marker in markers {
                guard marker.id == PersistentSchemaReleaseRegistryV1.v2MarkerID,
                      marker.schemaVersion == 53,
                      marker.releaseID == PersistentSchemaReleaseV1.v53.compatibilityID,
                      marker.predecessorReleaseID == PersistentSchemaReleaseV1.v52.compatibilityID else {
                    throw WorkspaceMutationFailureV1.invalidReversal
                }
            }
        }

        func validateClientCapabilityMetadata() throws {
            var releases: [InspectionPackageReleaseV1] = []
            for row in try rows(PromotedPackageReleaseRow.self) {
                let value = try row.value().packageRelease
                if !releases.contains(value) { releases.append(value) }
            }
            let profiles = try rows(ClientCapabilityProfileRow.self).map { try $0.value() }
            var policies: [PackageLifecyclePolicyV1] = []
            for row in try rows(PackageLifecyclePolicyRow.self) {
                let values = releases.compactMap { try? row.value(release: $0) }
                guard values.count == 1 else { throw WorkspaceMutationFailureV1.invalidReversal }
                policies.append(values[0])
            }
            var dispositions: [PackageLifecycleDispositionV1] = []
            for row in try rows(PackageLifecycleDispositionRow.self) {
                let values = releases.compactMap { try? row.value(release: $0) }
                guard values.count == 1 else { throw WorkspaceMutationFailureV1.invalidReversal }
                dispositions.append(values[0])
            }
            for row in try rows(ClientCapabilityAdmissionDecisionRow.self) {
                let profile = profiles.filter { $0.profileID == row.profileID }
                let policy = policies.filter { $0.policyID == row.policyID }
                let disposition = dispositions.filter { $0.dispositionID == row.dispositionID }
                guard profile.count == 1, policy.count == 1, disposition.count == 1 else {
                    throw WorkspaceMutationFailureV1.invalidReversal
                }
                let values = releases.compactMap {
                    try? row.value(profile: profile[0], policy: policy[0], disposition: disposition[0], release: $0)
                }
                guard values.count == 1 else { throw WorkspaceMutationFailureV1.invalidReversal }
            }
        }

        func validateFieldReferenceOwners() throws {
            let releases = try rows(FieldReferenceReleaseRow.self).map { try $0.value() }
            let rounds = try rows(RoundSessionRevisionRowV1.self).map { try $0.value() }
            for row in try rows(FieldReferenceBindingRow.self) {
                let release = releases.filter { $0.releaseID == row.releaseID }
                guard release.count == 1 else { throw WorkspaceMutationFailureV1.invalidReversal }
                let value = try row.value(release: release[0])
                switch value.subjectKind {
                case .workPacket: throw WorkspaceMutationFailureV1.invalidReversal
                case .roundSession:
                    let matches = rounds.filter {
                        $0.workspaceID == value.workspaceID && $0.sessionID == value.subjectID
                            && $0.revision == value.subjectRevision
                    }
                    guard matches.count == 1 else { throw WorkspaceMutationFailureV1.invalidReversal }
                    try round(matches[0])
                }
            }
        }

        func validateQualityProvenance() throws {
            // C10 ordinary deletion explicitly preserves this advisory history.
            // Rule/evidence tokens are not Asset IDs and confer no live owner.
            let rules = try rows(EvidenceQualityRuleSetRowV1.self).map { try $0.value() }
            var assessments: [EvidenceQualityAssessmentV1] = []
            for row in try rows(EvidenceQualityAssessmentRowV1.self) {
                let candidates = rules.compactMap { try? row.value(ruleSet: $0) }
                guard candidates.count == 1 else { throw WorkspaceMutationFailureV1.invalidReversal }
                assessments.append(candidates[0])
            }
            for row in try rows(EvidenceQualityWaiverRowV1.self) {
                let candidates = assessments.compactMap { try? row.value(assessment: $0) }
                guard candidates.count == 1 else { throw WorkspaceMutationFailureV1.invalidReversal }
            }
            for row in try rows(EvidenceQualityMutationReceiptRowV1.self) { _ = try row.value() }
        }

        func lightingSystem(_ value: LightingSystemV1) throws {
            try value.validateIntrinsic()
            for luminaire in value.luminaires {
                try absent(luminaire.assetID); try absent(luminaire.semanticBinding.assetID)
                try absent(luminaire.supportAssemblyAssetID)
                try absent(luminaire.supportAssemblySemanticBinding?.assetID)
            }
        }

        func validateLighting() throws {
            let systemRows = try rows(LightingSystemRow.self)
            let observationRows = try rows(LightingObservationRow.self)
            let issueRows = try rows(LightingIssueRow.self)
            let planRows = try rows(MeasurementPlanRow.self)
            let claimRows = try rows(LightingClaimStateRow.self)
            var records: [V31BackupLightingRecordV1] = []
            for row in systemRows {
                _ = try row.value()
                records.append(.init(kind: .lightingSystem, id: row.recordID, workspaceID: row.workspaceID,
                                     revision: row.revision, canonicalData: row.canonicalData))
            }
            for row in observationRows {
                _ = try row.value()
                records.append(.init(kind: .lightingObservation, id: row.recordID, workspaceID: row.workspaceID,
                                     revision: row.revision, canonicalData: row.canonicalData))
            }
            for row in issueRows {
                _ = try row.value()
                records.append(.init(kind: .lightingIssue, id: row.recordID, workspaceID: row.workspaceID,
                                     revision: row.revision, canonicalData: row.canonicalData))
            }
            for row in planRows {
                _ = try row.value()
                records.append(.init(kind: .measurementPlan, id: row.recordID, workspaceID: row.workspaceID,
                                     revision: row.revision, canonicalData: row.canonicalData))
            }
            for row in claimRows {
                _ = try row.value()
                records.append(.init(kind: .lightingClaim, id: row.recordID, workspaceID: row.workspaceID,
                                     revision: row.revision, canonicalData: row.canonicalData))
            }
            records.sort {
                ($0.kind.rawValue, $0.id.uuidString.lowercased()) < ($1.kind.rawValue, $1.id.uuidString.lowercased())
            }
            let roots = try LightingBackupRecordSetV1.decode(records)
            let systems = roots.systems
            for system in systems { try lightingSystem(system) }
            for row in observationRows {
                let value = try row.value()
                try absent(value.assetID); try absent(value.evidenceContext.assetID)
            }
            for row in issueRows {
                let value = try row.value()
                try absent(value.subjectAssetID); try absent(value.observation.assetID)
            }
            for row in claimRows {
                let value = try row.value()
                try absent(value.subjectAssetID); try absent(value.observation?.assetID)
            }
            for row in planRows {
                let value = try row.value()
                let matches = systems.filter {
                    $0.workspaceID == value.workspaceID && $0.systemID == value.systemID
                        && $0.revision == value.systemRevision && $0.systemSHA256 == value.systemSHA256
                }
                guard matches.count == 1 else { throw WorkspaceMutationFailureV1.invalidReversal }
                try lightingSystem(matches[0])
            }
            let dayRows = try rows(LightingDayInventoryWorkflowRowV1.self)
            let dayRecords = try dayRows.map { row -> V52BackupLightingDayInventoryRecordV1 in
                _ = try row.value()
                return .init(kind: .workflow, id: row.recordID, workspaceID: row.workspaceID,
                             revision: row.revision, canonicalData: row.canonicalData)
            }.sorted { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
            for value in try LightingDayInventoryBackupRecordSetV1.decode(dayRecords) {
                let matches = systems.filter {
                    $0.workspaceID == value.workspaceID && $0.systemID == value.systemID
                        && $0.revision == value.systemRevision && $0.systemSHA256 == value.systemSHA256
                }
                guard matches.count == 1 else { throw WorkspaceMutationFailureV1.invalidReversal }
                try lightingSystem(matches[0]); try subject(value.safetyIntake.area)
                for condition in value.conditionSnapshots { try absent(condition.assetID) }
            }
            let rounds = try rows(RoundSessionRevisionRowV1.self).map { try $0.value() }
            let nightRows = try rows(LightingNightWorkflowRowV1.self)
            let nightRecords = try nightRows.map { row -> V53BackupLightingNightWorkflowRecordV1 in
                _ = try row.value()
                return .init(kind: .workflow, id: row.recordID, workspaceID: row.workspaceID,
                             revision: row.revision, canonicalData: row.canonicalData)
            }.sorted { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
            for value in try LightingNightWorkflowBackupRecordSetV1.decode(nightRecords) {
                let matches = systems.filter {
                    $0.workspaceID == value.workspaceID && $0.systemID == value.system.systemID
                        && $0.revision == value.system.systemRevision && $0.systemSHA256 == value.system.systemSHA256
                }
                guard matches.count == 1 else { throw WorkspaceMutationFailureV1.invalidReversal }
                try lightingSystem(matches[0])
                for delta in value.deltas { try absent(delta.assetID) }
                for repair in value.repairs { try absent(repair.issue.observation.assetID) }
                for recheck in value.rechecks {
                    try absent(recheck.issue.observation.assetID); try absent(recheck.nightObservation?.assetID)
                }
                for reopen in value.reopens {
                    try absent(reopen.issue.observation.assetID); try absent(reopen.recurrenceObservation.assetID)
                }
                for group in value.rootCauseGroups {
                    for issue in group.childIssues { try absent(issue.observation.assetID) }
                }
                if let patrol = value.patrol {
                    let matches = rounds.filter {
                        $0.workspaceID == patrol.round.workspaceID && $0.sessionID == patrol.round.sessionID
                            && $0.revision == patrol.round.revision && $0.sessionSHA256 == patrol.round.sessionSHA256
                    }
                    guard matches.count == 1 else { throw WorkspaceMutationFailureV1.invalidReversal }
                    try round(matches[0])
                }
            }
        }

        func validateDraftHistory() throws {
            for row in try rows(FieldDraftCheckpointRow.self) { try checkpoint(row.value()) }
            let draftIDs = Set(try rows(FieldDraftCheckpointRow.self).map { try $0.value().draftID })
            for row in try rows(AttachmentStagingItemRow.self) {
                guard draftIDs.contains(try row.value().draftID) else { throw WorkspaceMutationFailureV1.invalidReversal }
            }
            for row in try rows(DraftCommitSagaRow.self) {
                guard draftIDs.contains(try row.value().draftID) else { throw WorkspaceMutationFailureV1.invalidReversal }
            }
            for row in try rows(DraftContentReservationRow.self) {
                guard draftIDs.contains(try row.value().draftID) else { throw WorkspaceMutationFailureV1.invalidReversal }
            }
            for row in try rows(DraftCommitReceiptRow.self) {
                guard draftIDs.contains(try row.value().draftID) else { throw WorkspaceMutationFailureV1.invalidReversal }
            }
            for row in try rows(DraftDiscardReceiptRow.self) {
                guard draftIDs.contains(try row.value().draftID) else { throw WorkspaceMutationFailureV1.invalidReversal }
            }
            for row in try rows(MutationReceiptRow.self) {
                let envelope = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData)
                if case let .applySurveySession(mutation) = envelope.command {
                    try mutation.validate()
                    switch mutation.payload {
                    case let .applySession(value, _, _): try survey(value)
                    case let .captureFact(_, value, _, _): try survey(value)
                    case .applyProvisionalSubject: break
                    case let .promoteSubject(_, receipt, _, predecessor):
                        try subject(receipt.canonicalSubject)
                        if let predecessor { try subject(predecessor.canonicalSubject) }
                    case let .publish(value, _, _, _): try survey(value)
                    }
                }
                guard case .applyFieldDraft = envelope.command else { continue }
                // Imported history remains legitimate history. The incumbent
                // local reviewed-resolution approval helper is not reused.
                let evidence = try FieldDraftCommittedEvidenceV1(
                    envelope: envelope, receipt: MutationReceiptV1.decodeCanonical(from: row.receiptData))
                switch evidence.mutation.postImage {
                case let .createCheckpoint(value), let .reviseCheckpoint(value): try checkpoint(value)
                case let .resolveConflict(value): try checkpoint(value.successorCheckpoint)
                case let .publishReadyStage(value): try checkpoint(value.successorCheckpoint)
                case let .applyCommitTerminal(value, _): try checkpoint(value.committedCheckpoint)
                case let .applyDiscardTerminal(value): try checkpoint(value.discardedCheckpoint)
                default: break
                }
            }
        }

        func checkpoint(_ value: FieldDraftCheckpointV1) throws {
            try value.validate()
            guard value.workspaceID == workspaceID else { throw WorkspaceMutationFailureV1.invalidReversal }
            if value.codec == (try CheckRunnerItemDraftCodecV1.release()) {
                let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(value)
                try absent(payload.source.assetID)
                try absent(payload.source.originalItem.selection.assetID)
                try absent(payload.source.itemAtEntry.selection.assetID)
            } else if value.codec == (try CheckRunnerPhotoDraftCodecV1.release()) {
                let payload = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(value)
                try absent(payload.assetID)
                try absent(payload.sourceBinding.assetID)
            } else if value.codec == (try RepetitiveCaptureDraftCodecV1.release()) {
                guard value.purpose == .repetitiveCapture else { throw WorkspaceMutationFailureV1.invalidReversal }
                switch try RepetitiveCaptureDraftCodecV1.decode(value.payloadData) {
                case let .source(_, _, selection):
                    for preview in selection.previews { try absent(preview.asset?.assetID) }
                case let .continuation(_, request):
                    try absent(request.assetID)
                    for preview in request.plan.selection.previews { try absent(preview.asset?.assetID) }
                    try round(request.roundMutation.session)
                }
            } else if value.codec == (try RepetitiveCaptureProgressDraftCodecV2.release()) {
                guard value.purpose == .repetitiveCapture else { throw WorkspaceMutationFailureV1.invalidReversal }
                // decode validates source and retained progress, unlike the
                // revision1 active-source-only validateCheckpoint overload.
                switch try RepetitiveCaptureProgressDraftCodecV2.decode(value.payloadData) {
                case let .source(source): try round(source.round)
                case let .progress(progress):
                    try round(progress.expectedRound)
                    if let mutation = progress.roundMutation { try round(mutation.session) }
                }
            } else if value.codec == (try RepetitiveCaptureDestinationReviewCodecV1.release()) {
                try RepetitiveCaptureDestinationReviewCodecV1.validateCheckpoint(value)
                let payload = try RepetitiveCaptureDestinationReviewCodecV1.decode(value.payloadData)
                for pair in payload.provenance.ultimateToDestinationPairs where pair.kind == .asset {
                    try absent(pair.destinationID)
                }
            } else if value.codec == (try MyDayPlanningDraftCodecV1.release()) {
                _ = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(value)
                // Its eligible references are typed work/round/occurrence/draft
                // owners. Missing exact recursive owner proof is never absence.
                throw WorkspaceMutationFailureV1.invalidReversal
            } else {
                throw WorkspaceMutationFailureV1.invalidReversal
            }
        }

        func unresolvedOwner<T: PersistentModel>(_ type: T.Type) throws {
            guard try rows(type).isEmpty else {
                #if DEBUG
                // Closed active model names only; no identifiers or payloads.
                print("FirstSignCompensationAdmission unresolved-owner=\(String(describing: type))")
                #endif
                throw WorkspaceMutationFailureV1.invalidReversal
            }
        }

        func requireResolvedOwners() throws {
            // Present roots without an incumbent exact typed owner proof are
            // preserved and refuse before staging. Absence is read in the same
            // synchronous ModelContext interval, never cached authorization.
            try unresolvedOwner(LocationMigrationReceiptRow.self)
            try unresolvedOwner(RequirementAssuranceRow.self)
            try unresolvedOwner(FindingClassificationBindingRow.self)
            try unresolvedOwner(DerivedFactProvenanceRow.self)
            try unresolvedOwner(ClaimEvidenceLinkRow.self)
            try unresolvedOwner(AssuranceManifestRow.self)
            try unresolvedOwner(AttestationRow.self)
            try unresolvedOwner(InspectionReviewTransitionRow.self)
            try unresolvedOwner(ReviewDispositionRow.self)
            try unresolvedOwner(ChangeRequestRow.self)
            try unresolvedOwner(CorrectiveActionEventRow.self)
            try unresolvedOwner(WorkPacketManifestRow.self)
            try unresolvedOwner(WorkItemClaimRow.self)
            try unresolvedOwner(WorkLeaseRow.self)
            try unresolvedOwner(WorkReleaseRow.self)
            try unresolvedOwner(WorkHandoffRow.self)
            try unresolvedOwner(MeasurementCaptureRow.self)
            try unresolvedOwner(MeasurementSeriesRow.self)
            try unresolvedOwner(MeasurementQualityAssessmentRow.self)
            try unresolvedOwner(PrivacyRegionRow.self)
            try unresolvedOwner(PrivacyTransformManifestRow.self)
            try unresolvedOwner(PrivacyReviewReceiptRow.self)
            try unresolvedOwner(FactCaptureRow.self)
            try unresolvedOwner(ProvisionalSubjectRow.self)
            try unresolvedOwner(SurveyPublicationSnapshotRow.self)
            try unresolvedOwner(LocatorBindingReceiptRow.self)
            try unresolvedOwner(OccurrenceHistoryEventRow.self)
            try unresolvedOwner(RebaseReceiptRow.self)
            try unresolvedOwner(AssistanceAcceptanceReceiptRow.self)
            try unresolvedOwner(ActivitySessionEnvelopeRow.self)
            try unresolvedOwner(ActivityStateTransitionRow.self)
            try unresolvedOwner(InstallationTaskResultRow.self)
            try unresolvedOwner(InstallationAsBuiltSnapshotRow.self)
            try unresolvedOwner(PunchReviewBasisSnapshotRow.self)
            try unresolvedOwner(ManualWorkResourceRecordRow.self)
            try unresolvedOwner(ScheduleOverrideEventRow.self)
            try unresolvedOwner(ServiceRequestDispositionEventRow.self)
            try unresolvedOwner(StockMovementEventRowV1.self)
            try unresolvedOwner(StockUseReceiptRowV1.self)
            try unresolvedOwner(StockUseReversalReceiptRowV1.self)
            try unresolvedOwner(StockReturnReceiptRowV1.self)
            try unresolvedOwner(AbandonUnverifiedStockRowV1.self)
            try unresolvedOwner(MyDayPlanRowV1.self)
            try unresolvedOwner(MyDayCarryoverReceiptRowV1.self)
            try unresolvedOwner(EvidenceAssociationEventRowV1.self)
            try unresolvedOwner(EvidenceSequenceRevisionRowV1.self)
            try unresolvedOwner(CapturePromotionRowV1.self)
            try unresolvedOwner(SnippetInsertionHistoryRowV1.self)
            try unresolvedOwner(ReinspectionPlanRowV1.self)
            try unresolvedOwner(UnchangedAttestationRowV1.self)
            try unresolvedOwner(ExceptionQueueAcknowledgementRowV1.self)
            try unresolvedOwner(ReinspectionExceptionMutationReceiptRowV1.self)
        }

        func requireEnrollment() throws {
            let known = Self.classifiedModelTypes.map { ObjectIdentifier($0) }
            let active = PersistentSchemaReleaseRegistryV1.activeRelease.models.map { ObjectIdentifier($0) }
            guard known.count == 168, Set(known).count == known.count,
                  active.count == known.count, Set(active) == Set(known) else {
                throw WorkspaceMutationFailureV1.invalidReversal
            }
        }

        // A closed enrollment guard, not an Asset-owner inference. Each listed
        // model still requires its explicit core, typed, retained, or unresolved
        // disposition below; count equality never supplies an absence proof.
        private static let classifiedModelTypes: [any PersistentModel.Type] = [
            Site.self,
            Asset.self,
            WorkflowRecord.self,
            EvidenceFile.self,
            Issue.self,
            Packet.self,
            Report.self,
            PersistentSchemaReleaseMarker.self,
            DeletionLedgerRow.self,
            MutationReceiptRow.self,
            MutationQuarantineRow.self,
            WorkspaceMutationStateRow.self,
            EntityMutationRevisionRow.self,
            ObservationAndTimeRow.self,
            LocationNodeRow.self,
            LocationHierarchyEventRow.self,
            AssetPlacementEventRow.self,
            AssetCompositionEdgeRow.self,
            AssetCompositionEventRow.self,
            LocationMigrationReceiptRow.self,
            SavedSmartViewRowV1.self,
            RequirementAssuranceRow.self,
            ServicePartyRow.self,
            SitePartyRoleEventRow.self,
            ActorSnapshotRow.self,
            QualificationSnapshotRow.self,
            SignoffSnapshotRow.self,
            AssetKindBindingEventRow.self,
            AssetWorkflowCapabilityBindingEventRow.self,
            AssetProductIdentityRow.self,
            AssetLifecycleEventRow.self,
            AssetSuccessorLinkRow.self,
            WorkSubjectScopeSnapshotRow.self,
            AuthoritySourceReleaseRow.self,
            RequirementBasisBindingRow.self,
            ApplicabilityContextSnapshotRow.self,
            AssessmentScopeSnapshotRow.self,
            SeverityScaleReleaseRow.self,
            FindingClassificationBindingRow.self,
            MeasurementProtocolReleaseRow.self,
            DerivedFactEvaluatorDescriptorRow.self,
            DerivedFactProvenanceRow.self,
            FunctionalRelationshipTypeDescriptorRow.self,
            AssetFunctionalRelationshipEventRow.self,
            EvidenceVisibilityRow.self,
            ClaimEvidenceLinkRow.self,
            AssuranceManifestRow.self,
            AttestationRow.self,
            InspectionReviewTransitionRow.self,
            ReviewDispositionRow.self,
            ChangeRequestRow.self,
            CorrectiveActionPolicyRow.self,
            CorrectiveActionEventRow.self,
            WorkPacketManifestRow.self,
            WorkItemClaimRow.self,
            WorkLeaseRow.self,
            WorkReleaseRow.self,
            WorkHandoffRow.self,
            FieldDraftCheckpointRow.self,
            AttachmentStagingItemRow.self,
            DraftCommitSagaRow.self,
            DraftContentReservationRow.self,
            DraftCommitReceiptRow.self,
            DraftDiscardReceiptRow.self,
            PromotedPackageReleaseRow.self,
            PackageSandboxRunRow.self,
            PackagePromotionReceiptRow.self,
            ActivePackageRegistryPointerRow.self,
            InstrumentReferenceRow.self,
            CalibrationStatusSnapshotRow.self,
            MeasurementCaptureRow.self,
            MeasurementSeriesRow.self,
            MeasurementQualityAssessmentRow.self,
            PrivacyTransformPolicyRow.self,
            PrivacyRegionRow.self,
            PrivacyTransformManifestRow.self,
            PrivacyReviewReceiptRow.self,
            ClientCapabilityProfileRow.self,
            ClientCapabilityAdmissionDecisionRow.self,
            PackageLifecyclePolicyRow.self,
            PackageLifecycleDispositionRow.self,
            RecoverabilityVerificationReceiptRow.self,
            FieldReferenceReleaseRow.self,
            FieldReferenceBindingRow.self,
            AccessibleDocumentAssessmentReceiptRow.self,
            SurveyDefinitionIdentityRow.self,
            SurveyDefinitionReleaseRow.self,
            SurveySessionRow.self,
            FactCaptureRow.self,
            ProvisionalSubjectRow.self,
            SubjectPromotionReceiptRow.self,
            SurveyPublicationSnapshotRow.self,
            AssetLocatorRow.self,
            LocatorBindingReceiptRow.self,
            ScheduleDefinitionReleaseRow.self,
            OccurrenceHistoryEventRow.self,
            PlanDocumentRow.self,
            PlanRevisionRow.self,
            PlanPlacementRow.self,
            RebaseReceiptRow.self,
            AssetPoseEventRow.self,
            SpatialAnchorObservationRow.self,
            EvidenceContextRow.self,
            PairedObservationLinkRow.self,
            LightingSystemRow.self,
            LightingObservationRow.self,
            LightingIssueRow.self,
            MeasurementPlanRow.self,
            LightingClaimStateRow.self,
            AssistanceAcceptanceReceiptRow.self,
            TemporalEvidenceClipRow.self,
            TimecodedEvidenceAnchorRow.self,
            AcceptedLabelGenerationSnapshotRow.self,
            ServiceContactPointRow.self,
            SystemHandoffIntentRow.self,
            ActivitySessionEnvelopeRow.self,
            ActivityStateTransitionRow.self,
            InstallationTaskResultRow.self,
            InstallationAsBuiltSnapshotRow.self,
            PunchReviewBasisSnapshotRow.self,
            ManualWorkResourceRecordRow.self,
            ExceptionCalendarReleaseRow.self,
            ScheduleOverrideEventRow.self,
            ServiceRequestRecordRow.self,
            ServiceRequestDispositionEventRow.self,
            ServiceRequestWorkLinkEventRow.self,
            AssetServiceIncidentRow.self,
            ServiceImpactSegmentRow.self,
            ServiceCauseAssertionRow.self,
            ServiceRemedyAssertionRow.self,
            ServiceRepairIntervalRow.self,
            ServiceRestorationAssertionRow.self,
            QualifiedServiceExposureRow.self,
            LocalPartDefinitionRowV1.self,
            StockStorageLocationRowV1.self,
            StockMovementEventRowV1.self,
            StockUseReceiptRowV1.self,
            StockUseReversalReceiptRowV1.self,
            StockReturnReceiptRowV1.self,
            AbandonUnverifiedStockRowV1.self,
            MyDayPlanRowV1.self,
            MyDayCarryoverReceiptRowV1.self,
            EvidenceAssociationEventRowV1.self,
            EvidenceSequenceRevisionRowV1.self,
            ShopReportProfileRowV1.self,
            RoundSessionRevisionRowV1.self,
            ImportMappingProfileRowV1.self,
            BulkSessionRowV1.self,
            BulkCommitReceiptRowV1.self,
            EvidenceQualityRuleSetRowV1.self,
            EvidenceQualityAssessmentRowV1.self,
            EvidenceQualityWaiverRowV1.self,
            EvidenceQualityMutationReceiptRowV1.self,
            CaptureInboxItemRowV1.self,
            CapturePromotionRowV1.self,
            SnippetRowV1.self,
            SnippetInsertionHistoryRowV1.self,
            FastSurveyInboxMutationReceiptRowV1.self,
            ReinspectionPlanRowV1.self,
            UnchangedAttestationRowV1.self,
            ExceptionQueueAcknowledgementRowV1.self,
            ReinspectionExceptionMutationReceiptRowV1.self,
            EntityAliasLinkRowV1.self,
            EntityConsolidationReceiptRowV1.self,
            EntityIdentityResolutionMutationReceiptRowV1.self,
            PracticeWorkspaceProvenanceRowV1.self,
            LightingDayInventoryWorkflowRowV1.self,
            LightingNightWorkflowRowV1.self,
        ]
    }
}
