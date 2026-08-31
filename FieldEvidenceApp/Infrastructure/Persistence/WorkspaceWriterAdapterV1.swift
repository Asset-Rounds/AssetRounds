import Foundation
import SwiftData

/// Applies content changes without saving. MutationJournalStoreV1 owns the
/// single atomic save containing content, revisions, and immutable receipt.
@MainActor
final class WorkspaceWriterAdapterV1: WorkspaceWriterAdapterPortV1 {
    let requiresInitialPlacementForFirstSign = true
    static let supportedCommandKinds: Set<WorkspaceCommandKindV1> = [
        .createFirstSign,
        .createCheckDraft,
        .acceptCheckEvidence,
        .updateSiteTimeZone,
    ]
    static let locationSupportedCommandKinds: Set<WorkspaceCommandKindV1> = [
        .applyLocationHierarchyChange,
        .applyAssetPlacementChange,
        .applyAssetCompositionChange,
    ]
    static let activeSupportedCommandKinds = supportedCommandKinds.union(locationSupportedCommandKinds)
        .union([
            .applySavedSmartView,
            .applyRequirementAssurance,
            .applyPartyAccountability,
            .applyAssetSemantics,
            .applyAuthorityCriterion,
            .applyFunctionalRelationship,
            .applyEvidenceAssurance,
            .applyInspectionReview,
            .applyWorkPacket,
            .applyFieldDraft,
            .applyPackagePromotion,
            .applyMeasurementIntegrity,
            .applyPrivacyTransform,
            .applyEvidenceMetadata,
            .applyClientCapability,
            .applyFieldReference,
            .applyAccessibleDocumentAssessment,
            .applySurveyDefinition,
            .applySurveySession,
            .applyAssetLocator,
            .applySchedule,
            .applyPlan,
            .applyPlacementPose,
            .applyEvidenceContext,
            .applyLighting,
            .applyAssistanceAcceptance,
            .applyTemporalEvidence,
            .applyAssetLabel,
            .applyOperationalContact,
            .applyActivityContract,
            .applyPortableReview,
            .applyWorkResource,
            .applyPartsStock,
            .applyMyDay,
            .applyServiceRequest,
            .applyServiceReliability,
            .applyShopReportProfile,
            .applyRoundSession,
            .applyImportBulk,
        ])

    /// C22 receipts are appended by the existing fenced journal authority;
    /// neither receipt rows nor disposable verification staging enter apply(_:).
    nonisolated static let appliesRecoverabilityVerificationReceipts = false
    nonisolated static let persistsRecoverabilityVerificationStaging = false

    static func recoverabilityVerificationReceiptAuthority(
        journal: MutationJournalStoreV1
    ) -> any RecoverabilityVerificationReceiptWritingV1 {
        journal
    }

    private let modelContext: ModelContext
    private let assetSemanticLifecycleAdapter: AssetSemanticLifecycleAdapterV1
    private let completedActivitySnapshotResolver:
        ((CompletedActivitySnapshotV2CompatibilityReferenceV1) throws
            -> CompletedActivitySnapshotResolutionContextV2)?
    private let activityFindingEvidenceResolver:
        (([PunchFindingLinkV1]) throws -> [FindingLifecycleCanonicalEvidenceV1])?

    init(
        modelContext: ModelContext,
        assetSemanticLifecycleAdapter: AssetSemanticLifecycleAdapterV1? = nil,
        completedActivitySnapshotResolver:
            ((CompletedActivitySnapshotV2CompatibilityReferenceV1) throws
                -> CompletedActivitySnapshotResolutionContextV2)? = nil,
        activityFindingEvidenceResolver:
            (([PunchFindingLinkV1]) throws -> [FindingLifecycleCanonicalEvidenceV1])? = nil
    ) {
        self.modelContext = modelContext
        self.completedActivitySnapshotResolver = completedActivitySnapshotResolver
        self.activityFindingEvidenceResolver = activityFindingEvidenceResolver
        if let assetSemanticLifecycleAdapter {
            self.assetSemanticLifecycleAdapter = assetSemanticLifecycleAdapter
        } else {
            let catalogRegistry = try? AssetSemanticCatalogRegistryV1(
                release: BundledInspectionPackageRegistryV2.shippingAssetSemanticCatalog()
            )
            self.assetSemanticLifecycleAdapter = AssetSemanticLifecycleAdapterV1(
                modelContext: modelContext,
                catalogRegistry: catalogRegistry
            )
        }
    }

    func apply(
        _ command: WorkspaceCommandV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard C50IncumbentFileExchangeWriterAdapterBoundaryV1.validate() else {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        guard !modelContext.hasChanges else {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        do {
            _ = try ObservationAndTimeRowStoreV1.validatedIndex(in: modelContext)
        } catch {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        switch command {
        case let .createFirstSign(value):
            return try createFirstSign(
                value,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .createCheckDraft(value):
            return try createCheckDraft(
                value,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .acceptCheckEvidence(value):
            return try acceptCheckEvidence(
                value,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .updateSiteTimeZone(value):
            return try updateSiteTimeZone(
                value,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .applyLocationHierarchyChange(value):
            let hierarchy = try applyLocationHierarchyChange(
                value.plan,
                placementChanges: value.placementChanges,
                temporaryRelativePath: temporaryRelativePath
            )
            var affected = hierarchy.affectedEntities
            for placement in value.placementChanges {
                affected += try applyAssetPlacementChange(
                    placement,
                    occurredAt: occurredAt,
                    temporaryRelativePath: temporaryRelativePath
                ).affectedEntities
            }
            return try WorkspaceMutationEffectV1(
                affectedEntities: affected,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .applyAssetPlacementChange(plan):
            return try applyAssetPlacementChange(plan, occurredAt: occurredAt, temporaryRelativePath: temporaryRelativePath)
        case let .applyAssetCompositionChange(plan):
            return try applyAssetCompositionChange(plan, temporaryRelativePath: temporaryRelativePath)
        case let .applySavedSmartView(value):
            return try applySavedSmartView(value, temporaryRelativePath: temporaryRelativePath)
        case let .applyRequirementAssurance(value):
            return try applyRequirementAssurance(
                value,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .applyPartyAccountability(value):
            return try applyPartyAccountability(value, temporaryRelativePath: temporaryRelativePath)
        case let .applyAssetSemantics(value):
            return try assetSemanticLifecycleAdapter.apply(
                value,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .applyAuthorityCriterion(value):
            return try applyAuthorityCriterion(value, temporaryRelativePath: temporaryRelativePath)
        case let .applyFunctionalRelationship(value):
            return try applyFunctionalRelationship(value, temporaryRelativePath: temporaryRelativePath)
        case let .applyEvidenceAssurance(value):return try applyEvidenceAssurance(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyInspectionReview(value):return try applyInspectionReview(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyWorkPacket(value):return try applyWorkPacket(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyFieldDraft(value):return try applyFieldDraft(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyPackagePromotion(value):return try applyPackagePromotion(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyMeasurementIntegrity(value):return try applyMeasurementIntegrity(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyPrivacyTransform(value):return try applyPrivacyTransform(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyEvidenceMetadata(value):return try applyEvidenceMetadata(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyClientCapability(value):return try applyClientCapability(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyFieldReference(value):return try applyFieldReference(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyAccessibleDocumentAssessment(value):return try applyAccessibleDocumentAssessment(value,temporaryRelativePath:temporaryRelativePath)
        case let .applySurveyDefinition(value):return try applySurveyDefinition(value,temporaryRelativePath:temporaryRelativePath)
        case let .applySurveySession(value):return try applySurveySession(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyAssetLocator(value):return try applyAssetLocator(value,temporaryRelativePath:temporaryRelativePath)
        case let .applySchedule(value):return try applySchedule(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyPlan(value):return try applyPlan(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyPlacementPose(value):return try applyPlacementPose(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyEvidenceContext(value):return try applyEvidenceContext(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyLighting(value):return try applyLighting(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyAssistanceAcceptance(request):
            try request.validate()
            switch request.targetMutation {
            case let .surveySession(mutation):
                return try applySurveySession(mutation, temporaryRelativePath: temporaryRelativePath)
            }
        case let .applyTemporalEvidence(value):
            return try applyTemporalEvidence(value, temporaryRelativePath: temporaryRelativePath)
        case let .applyAssetLabel(value):
            return try applyAssetLabel(value, temporaryRelativePath: temporaryRelativePath)
        case let .applyOperationalContact(value):
            return try applyOperationalContact(value, temporaryRelativePath: temporaryRelativePath)
        case let .applyActivityContract(value):
            return try applyActivityContract(value, temporaryRelativePath: temporaryRelativePath)
        case let .applyPortableReview(value):
            try value.validate()
            return try applyInspectionReview(
                value.inspectionReviewMutation,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .applyWorkResource(value):
            return try applyWorkResource(value, temporaryRelativePath: temporaryRelativePath)
        case let .applyPartsStock(value):
            return try applyPartsStock(value, temporaryRelativePath: temporaryRelativePath)
        case let .applyMyDay(value):
            return try applyMyDay(value, temporaryRelativePath: temporaryRelativePath)
        case let .applyServiceRequest(value):
            return try applyServiceRequest(value, temporaryRelativePath: temporaryRelativePath)
        case let .applyServiceReliability(value):
            return try applyServiceReliability(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyShopReportProfile(value):
            return try applyShopReportProfile(value, temporaryRelativePath: temporaryRelativePath)
        case let .applyRoundSession(value):
            return try applyRoundSession(value, temporaryRelativePath: temporaryRelativePath)
        case let .applyImportBulk(value):
            return try applyImportBulk(value, temporaryRelativePath: temporaryRelativePath)
        case .deleteAsset,
             .deleteSite,
             .eraseWorkspace,
             .finalizeCheck,
             .finalizeCorrection,
             .recordWork,
             .restoreWorkspace,
             .archiveEntities:
            throw WorkspaceMutationFailureV1.unsupportedCommand
        }
    }

    /// C08's three lifecycle rows participate in the same uncommitted context
    /// as the journal receipt.  This method intentionally never saves; the
    /// journal owns the sole transaction boundary and rolls it back on failure.
    private func applyImportBulk(
        _ mutation: ImportBulkWorkspaceMutationV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        do {
            try mutation.validate()
            switch mutation.operation {
            case let .upsertMappingProfile(profile, expectedProfileSHA256):
                let rows = try modelContext.fetch(FetchDescriptor<ImportMappingProfileRowV1>(
                    predicate: #Predicate { $0.profileID == profile.profileID }
                ))
                guard rows.count <= 1 else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
                if let existing = rows.first {
                    let prior = try existing.value()
                    if prior != profile {
                        guard expectedProfileSHA256 == prior.profileSHA256 else {
                            throw WorkspaceMutationFailureV1.staleEntityRevision(try mutation.concurrencyIdentity)
                        }
                        try existing.replace(with: profile, expectedProfileSHA256: prior.profileSHA256)
                    }
                } else {
                    guard expectedProfileSHA256 == nil else {
                        throw WorkspaceMutationFailureV1.staleEntityRevision(try mutation.concurrencyIdentity)
                    }
                    modelContext.insert(try ImportMappingProfileRowV1(profile))
                }
            case let .advanceSession(session, expectedSessionSHA256):
                let rows = try modelContext.fetch(FetchDescriptor<BulkSessionRowV1>(
                    predicate: #Predicate { $0.sessionID == session.sessionID }
                ))
                guard rows.count <= 1 else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
                if let existing = rows.first {
                    let prior = try existing.value()
                    if prior != session {
                        guard expectedSessionSHA256 == prior.sessionSHA256 else {
                            throw WorkspaceMutationFailureV1.staleEntityRevision(try mutation.concurrencyIdentity)
                        }
                        guard session.workspaceID == prior.workspaceID,
                              session.bulkPlanID == prior.bulkPlanID,
                              session.bulkPlanSHA256 == prior.bulkPlanSHA256,
                              session.sourceSHA256 == prior.sourceSHA256,
                              session.expectedWorkspaceRevisionSHA256 == prior.expectedWorkspaceRevisionSHA256,
                              session.chunkReceipts.starts(with: prior.chunkReceipts),
                              session.chunkReceipts.count > prior.chunkReceipts.count,
                              prior.state != .completed,
                              prior.state != .cancelled,
                              prior.state != .quarantinedChangedInput else {
                            throw WorkspaceMutationFailureV1.invalidCommand
                        }
                        try existing.replace(with: session, expectedSessionSHA256: prior.sessionSHA256)
                    }
                } else {
                    guard expectedSessionSHA256 == nil else {
                        throw WorkspaceMutationFailureV1.staleEntityRevision(try mutation.concurrencyIdentity)
                    }
                    modelContext.insert(try BulkSessionRowV1(session))
                }
            case let .appendReceipt(receipt):
                let rows = try modelContext.fetch(FetchDescriptor<BulkCommitReceiptRowV1>(
                    predicate: #Predicate { $0.receiptID == receipt.receiptID }
                ))
                guard rows.count <= 1 else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
                if let existing = rows.first {
                    guard try existing.value() == receipt else { throw WorkspaceMutationFailureV1.sequenceCollision }
                } else {
                    let workspaceID = receipt.workspaceID.rawValue
                    let bulkPlanID = receipt.bulkPlanID
                    let chunkIndex = receipt.chunkIndex
                    let duplicates = try modelContext.fetch(FetchDescriptor<BulkCommitReceiptRowV1>(
                        predicate: #Predicate {
                            $0.workspaceID == workspaceID && $0.bulkPlanID == bulkPlanID && $0.chunkIndex == chunkIndex
                        }
                    ))
                    guard duplicates.isEmpty else { throw WorkspaceMutationFailureV1.sequenceCollision }
                    modelContext.insert(try BulkCommitReceiptRowV1(receipt))
                }
            }
            return try WorkspaceMutationEffectV1(
                affectedEntities: [try mutation.affectedIdentity],
                temporaryRelativePath: temporaryRelativePath
            )
        } catch let failure as WorkspaceMutationFailureV1 {
            modelContext.rollback()
            throw failure
        } catch {
            modelContext.rollback()
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    /// V44 keeps immutable profile revisions under a profile-level concurrency
    /// stream. The canonical workspace/profile/revision row identity lets
    /// replay discover an effect that committed before its receipt.
    private func applyShopReportProfile(
        _ mutation: ShopReportProfileMutationV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        do {
            let profile = mutation.profile
            guard mutation.workspaceID == profile.workspaceID,
                  mutation.mutationID == profile.mutationID,
                  profile.revision == mutation.expectedRevision + 1,
                  (mutation.expectedRevision == 0) == (profile.predecessor == nil) else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            _ = try ShopReportProfileCanonicalCodecV1.decode(
                ShopReportProfileV1.self,
                from: try ShopReportProfileCanonicalCodecV1.encode(profile)
            )

            let workspaceID = mutation.workspaceID.rawValue
            let profileID = profile.profileID
            let profileRowID = ShopReportProfileRowV1.rowID(
                workspaceID: profile.workspaceID,
                profileID: profile.profileID,
                revision: profile.revision
            )
            let matchingMutationRows = try modelContext.fetch(
                FetchDescriptor<ShopReportProfileRowV1>(
                    predicate: #Predicate { $0.rowID == profileRowID }
                )
            )
            guard matchingMutationRows.count <= 1 else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            if let existing = matchingMutationRows.first {
                guard try existing.value() == profile else {
                    throw WorkspaceMutationFailureV1.sequenceCollision
                }
                return try WorkspaceMutationEffectV1(
                    affectedEntities: [try mutation.affectedIdentity],
                    temporaryRelativePath: temporaryRelativePath
                )
            }

            let rows = try modelContext.fetch(
                FetchDescriptor<ShopReportProfileRowV1>(
                    predicate: #Predicate {
                        $0.workspaceID == workspaceID && $0.profileID == profileID
                    }
                )
            )
            let history = try rows.map { try $0.value() }.sorted {
                ($0.revision, $0.mutationID.rawValue.uuidString)
                    < ($1.revision, $1.mutationID.rawValue.uuidString)
            }
            guard Set(history.map(\.revision)).count == history.count,
                  Set(history.map(\.mutationID)).count == history.count else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            if mutation.expectedRevision == 0 {
                guard history.isEmpty, profile.revision == 1,
                      profile.predecessor == nil else {
                    throw WorkspaceMutationFailureV1.staleEntityRevision(
                        try mutation.concurrencyIdentity
                    )
                }
            } else {
                guard let predecessor = history.last,
                      predecessor.revision == mutation.expectedRevision,
                      profile.predecessor == (try predecessor.reference),
                      profile.workspaceID == predecessor.workspaceID,
                      profile.profileID == predecessor.profileID,
                      profile.revision == predecessor.revision + 1,
                      profile.mutationID != predecessor.mutationID,
                      profile.recordedAt >= predecessor.recordedAt else {
                    throw WorkspaceMutationFailureV1.staleEntityRevision(
                        try mutation.concurrencyIdentity
                    )
                }
            }
            modelContext.insert(try ShopReportProfileRowV1(profile))
            return try WorkspaceMutationEffectV1(
                affectedEntities: [try mutation.affectedIdentity],
                temporaryRelativePath: temporaryRelativePath
            )
        } catch let failure as WorkspaceMutationFailureV1 {
            modelContext.rollback()
            throw failure
        } catch {
            modelContext.rollback()
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    func shopReportProfileHistory(
        workspaceID: WorkspaceID,
        profileID: UUID
    ) throws -> [ShopReportProfileV1] {
        let rawWorkspaceID = workspaceID.rawValue
        let rows = try modelContext.fetch(
            FetchDescriptor<ShopReportProfileRowV1>(
                predicate: #Predicate {
                    $0.workspaceID == rawWorkspaceID && $0.profileID == profileID
                }
            )
        )
        let history = try rows.map { try $0.value() }.sorted {
            ($0.revision, $0.mutationID.rawValue.uuidString)
                < ($1.revision, $1.mutationID.rawValue.uuidString)
        }
        guard Set(history.map(\.revision)).count == history.count,
              Set(history.map(\.mutationID)).count == history.count else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        for index in history.indices {
            let current = history[index]
            if index == history.startIndex {
                guard current.revision == 1, current.predecessor == nil else {
                    throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
                }
            } else {
                let predecessor = history[index - 1]
                guard current.revision == predecessor.revision + 1,
                      current.predecessor == (try predecessor.reference),
                      current.recordedAt >= predecessor.recordedAt else {
                    throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
                }
            }
        }
        return history
    }

    func persistedShopReportProfileEffectMatches(
        _ mutation: ShopReportProfileMutationV1
    ) throws -> Bool {
        let profile = mutation.profile
        let profileRowID = ShopReportProfileRowV1.rowID(
            workspaceID: profile.workspaceID,
            profileID: profile.profileID,
            revision: profile.revision
        )
        let rows = try modelContext.fetch(
            FetchDescriptor<ShopReportProfileRowV1>(
                predicate: #Predicate { $0.rowID == profileRowID }
            )
        )
        guard rows.count <= 1 else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        guard let row = rows.first else { return false }
        guard try row.value() == profile else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        _ = try shopReportProfileHistory(
            workspaceID: mutation.workspaceID,
            profileID: profile.profileID
        )
        return true
    }

    /// V45 stores a round session as immutable, revision-addressed semantic
    /// history. A committed row is accepted on replay only when its complete
    /// canonical lineage is still exact.
    private func applyRoundSession(
        _ mutation: RoundSessionMutationV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        do {
            try mutation.validate()
            let session = mutation.session
            guard mutation.workspaceID == session.workspaceID,
                  mutation.mutationID == session.mutationID,
                  session.revision == mutation.expectedRevision + 1,
                  (mutation.expectedRevision == 0) == (session.predecessor == nil) else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            _ = try RoundSessionCanonicalCodecV1.decode(
                RoundSessionV1.self,
                from: try RoundSessionCanonicalCodecV1.encode(session)
            )

            let workspaceID = mutation.workspaceID.rawValue
            let sessionID = session.sessionID
            let rowID = RoundSessionRevisionRowV1.rowID(
                workspaceID: session.workspaceID,
                sessionID: session.sessionID,
                revision: session.revision
            )
            let matchingRows = try modelContext.fetch(
                FetchDescriptor<RoundSessionRevisionRowV1>(
                    predicate: #Predicate { $0.rowID == rowID }
                )
            )
            guard matchingRows.count <= 1 else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            if let existing = matchingRows.first {
                guard try existing.value() == session else {
                    throw WorkspaceMutationFailureV1.sequenceCollision
                }
                return try WorkspaceMutationEffectV1(
                    affectedEntities: [try mutation.affectedIdentity],
                    temporaryRelativePath: temporaryRelativePath
                )
            }

            let rows = try modelContext.fetch(
                FetchDescriptor<RoundSessionRevisionRowV1>(
                    predicate: #Predicate {
                        $0.workspaceID == workspaceID && $0.sessionID == sessionID
                    }
                )
            )
            let history = try rows.map { try $0.value() }.sorted {
                ($0.revision, $0.mutationID.rawValue.uuidString)
                    < ($1.revision, $1.mutationID.rawValue.uuidString)
            }
            guard Set(history.map(\.revision)).count == history.count,
                  Set(history.map(\.mutationID)).count == history.count else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            _ = try RoundSessionHistoryValidatorV1.validate(
                history,
                workspaceID: mutation.workspaceID,
                sessionID: sessionID
            )
            if mutation.expectedRevision == 0 {
                guard history.isEmpty, session.revision == 1,
                      session.predecessor == nil else {
                    throw WorkspaceMutationFailureV1.staleEntityRevision(
                        try mutation.concurrencyIdentity
                    )
                }
            } else {
                guard let predecessor = history.last,
                      predecessor.revision == mutation.expectedRevision,
                      session.predecessor == (try predecessor.reference),
                      session.workspaceID == predecessor.workspaceID,
                      session.sessionID == predecessor.sessionID,
                      session.revision == predecessor.revision + 1,
                      session.mutationID != predecessor.mutationID,
                      session.recordedAt >= predecessor.recordedAt else {
                    throw WorkspaceMutationFailureV1.staleEntityRevision(
                        try mutation.concurrencyIdentity
                    )
                }
                try session.validateSuccessor(of: predecessor)
            }
            modelContext.insert(try RoundSessionRevisionRowV1(session))
            return try WorkspaceMutationEffectV1(
                affectedEntities: [try mutation.affectedIdentity],
                temporaryRelativePath: temporaryRelativePath
            )
        } catch let failure as WorkspaceMutationFailureV1 {
            modelContext.rollback()
            throw failure
        } catch {
            modelContext.rollback()
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    func roundSessionHistory(
        workspaceID: WorkspaceID,
        sessionID: UUID
    ) throws -> [RoundSessionV1] {
        let rawWorkspaceID = workspaceID.rawValue
        let rows = try modelContext.fetch(
            FetchDescriptor<RoundSessionRevisionRowV1>(
                predicate: #Predicate {
                    $0.workspaceID == rawWorkspaceID && $0.sessionID == sessionID
                }
            )
        )
        let history = try rows.map { try $0.value() }.sorted {
            ($0.revision, $0.mutationID.rawValue.uuidString)
                < ($1.revision, $1.mutationID.rawValue.uuidString)
        }
        guard Set(history.map(\.revision)).count == history.count,
              Set(history.map(\.mutationID)).count == history.count else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        do {
            _ = try RoundSessionHistoryValidatorV1.validate(
                history,
                workspaceID: workspaceID,
                sessionID: sessionID
            )
        } catch {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return history
    }

    func persistedRoundSessionEffectMatches(
        _ mutation: RoundSessionMutationV1
    ) throws -> Bool {
        let session = mutation.session
        let rowID = RoundSessionRevisionRowV1.rowID(
            workspaceID: session.workspaceID,
            sessionID: session.sessionID,
            revision: session.revision
        )
        let rows = try modelContext.fetch(
            FetchDescriptor<RoundSessionRevisionRowV1>(
                predicate: #Predicate { $0.rowID == rowID }
            )
        )
        guard rows.count <= 1 else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        guard let row = rows.first else { return false }
        guard try row.value() == session else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        _ = try roundSessionHistory(
            workspaceID: mutation.workspaceID,
            sessionID: session.sessionID
        )
        return true
    }

    private func requireCurrentMyDaySources(
        _ items: [MyDayItemV1],
        workspaceID: WorkspaceID
    ) throws {
        for item in items {
            switch item.reference {
            case let .workPacket(reference):
                let rows = try modelContext.fetch(FetchDescriptor<WorkPacketManifestRow>(
                    predicate: #Predicate { $0.manifestID == reference.manifestID }
                ))
                guard rows.count == 1,
                      let value = try rows.first?.value(),
                      value.workspaceID == workspaceID,
                      try WorkPacketManifestReferenceV1(value) == reference else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            case let .roundSession(referenceWorkspaceID, sessionID, revision, digest):
                let rows = try modelContext.fetch(FetchDescriptor<RoundSessionRevisionRowV1>(
                    predicate: #Predicate {
                        $0.workspaceID == referenceWorkspaceID.rawValue
                            && $0.sessionID == sessionID
                            && $0.revision == revision
                    }
                ))
                guard rows.count == 1,
                      let value = try rows.first?.value(),
                      referenceWorkspaceID == workspaceID,
                      value.workspaceID == workspaceID,
                      value.revision == revision,
                      value.sessionSHA256 == digest else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            case let .scheduleOccurrence(anchor, digest):
                let rows = try modelContext.fetch(FetchDescriptor<OccurrenceHistoryEventRow>())
                let events = try rows.map { try $0.value() }.filter {
                    $0.workspaceID == workspaceID && $0.occurrenceID == anchor.occurrenceID
                }.sorted { $0.revision < $1.revision }
                guard !events.isEmpty,
                      Set(events.map(\.revision)).count == events.count,
                      events.first?.revision == 1 else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                try events[0].validate(predecessor: nil)
                for index in events.indices.dropFirst() {
                    try events[index].validate(predecessor: events[index - 1])
                }
                guard let current = events.last,
                      try C34OccurrenceNavigationAnchorV1(event: current) == anchor,
                      current.eventSHA256 == digest,
                      current.action != .complete,
                      !(current.exception.map {
                          [.skipped, .cancelled, .missed, .retiredForRuleChange].contains($0.kind)
                      } ?? false) else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            case let .resumableDraft(referenceWorkspaceID, draftID, revision, digest, anchor):
                guard let value = try exactDraftCheckpoint(draftID, workspaceID: workspaceID),
                      referenceWorkspaceID == workspaceID,
                      value.draftRevision == revision,
                      value.checkpointSHA256 == digest,
                      value.resumeAnchor == anchor,
                      [.active, .conflicted, .recoveryRequired].contains(value.state) else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            }
        }
    }

    /// The My Day rows deliberately retain only canonical membership/order
    /// truth.  Source work, schedule, readiness, and due-state are read-only
    /// inputs to the command and are never projected into this mutation.
    private func applyMyDay(
        _ mutation: MyDayMutationV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        do {
            try mutation.validate()
            let successor = mutation.resultingPlan
            try requireCurrentMyDaySources(successor.items, workspaceID: mutation.workspaceID)
            let planRows = try modelContext.fetch(FetchDescriptor<MyDayPlanRowV1>())
            let decodedPlans = try planRows.map { try $0.value() }
            func lineage(planID: UUID) throws -> [MyDayPlanV1] {
                let values = decodedPlans.filter { $0.planID == planID }.sorted { $0.revision < $1.revision }
                guard values.allSatisfy({ $0.key.workspaceID == mutation.workspaceID }),
                      Set(values.map(\.revision)).count == values.count else {
                    throw WorkspaceMutationFailureV1.persistenceFailed
                }
                for (offset, value) in values.enumerated() {
                    if offset == 0 {
                        guard value.revision == 1, value.predecessorPlanSHA256 == nil else {
                            throw WorkspaceMutationFailureV1.persistenceFailed
                        }
                    } else {
                        try value.validate(predecessor: values[offset - 1])
                    }
                }
                return values
            }
            let existingLineage = try lineage(planID: successor.planID)
            let sameKey = decodedPlans.filter { $0.key == successor.key }
            guard Set(sameKey.map(\.planID)).count <= 1,
                  sameKey.first.map({ $0.planID == successor.planID }) ?? true else {
                throw WorkspaceMutationFailureV1.sequenceCollision
            }

            switch mutation.command {
            case let .save(value, predecessor):
                guard value == successor else { throw WorkspaceMutationFailureV1.invalidCommand }
                if let predecessor {
                    guard let persistedTip = existingLineage.last,
                          persistedTip == predecessor,
                          predecessor.key.workspaceID == mutation.workspaceID else {
                        throw WorkspaceMutationFailureV1.staleEntityRevision(
                            try .init(kind: .myDayPlan, id: successor.planID)
                        )
                    }
                    try value.validate(predecessor: predecessor)
                    modelContext.insert(try MyDayPlanRowV1(successor))
                } else {
                    guard existingLineage.isEmpty, sameKey.isEmpty, successor.revision == 1 else {
                        throw WorkspaceMutationFailureV1.sequenceCollision
                    }
                    modelContext.insert(try MyDayPlanRowV1(successor))
                }

            case let .carryover(plan, source, target, receipt):
                guard target == successor,
                      source.key.workspaceID == mutation.workspaceID,
                      try MyDayPlanReferenceV1(source) == plan.sourcePlan,
                      try MyDayPlanReferenceV1(target) == receipt.targetPlan else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                let sourceLineage = try lineage(planID: source.planID)
                guard sourceLineage.contains(source),
                      try MyDayPlanReferenceV1(source) == plan.sourcePlan else {
                    throw WorkspaceMutationFailureV1.staleEntityRevision(
                        try .init(kind: .myDayPlan, id: source.planID)
                    )
                }
                if let expected = plan.expectedTargetPlan {
                    guard let persistedTip = existingLineage.last,
                          expected.planID == target.planID else {
                        throw WorkspaceMutationFailureV1.staleEntityRevision(
                            try .init(kind: .myDayPlan, id: target.planID)
                        )
                    }
                    guard persistedTip == expected,
                          target.predecessorPlanSHA256 == persistedTip.planSHA256 else {
                        throw WorkspaceMutationFailureV1.staleEntityRevision(
                            try .init(kind: .myDayPlan, id: target.planID)
                        )
                    }
                    try target.validate(predecessor: persistedTip)
                    modelContext.insert(try MyDayPlanRowV1(target))
                } else {
                    guard existingLineage.isEmpty, sameKey.isEmpty, target.revision == 1 else {
                        throw WorkspaceMutationFailureV1.sequenceCollision
                    }
                    modelContext.insert(try MyDayPlanRowV1(target))
                }
                let receipts = try modelContext.fetch(FetchDescriptor<MyDayCarryoverReceiptRowV1>()).filter {
                    $0.receiptSHA256 == receipt.receiptSHA256 ||
                    ($0.workspaceID == mutation.workspaceID.rawValue && $0.mutationID == mutation.mutationID.rawValue)
                }
                guard receipts.isEmpty else { throw WorkspaceMutationFailureV1.sequenceCollision }
                modelContext.insert(try MyDayCarryoverReceiptRowV1(receipt))
            }
            return try WorkspaceMutationEffectV1(
                affectedEntities: mutation.affectedIdentities,
                temporaryRelativePath: temporaryRelativePath
            )
        } catch let failure as WorkspaceMutationFailureV1 {
            modelContext.rollback(); throw failure
        } catch {
            modelContext.rollback(); throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    func persistedMyDayEffectMatches(_ mutation: MyDayMutationV1) throws -> Bool {
        try mutation.validate()
        let planRows = try modelContext.fetch(FetchDescriptor<MyDayPlanRowV1>()).filter {
            $0.planID == mutation.resultingPlan.planID &&
            $0.workspaceID == mutation.workspaceID.rawValue
        }
        let plans = try planRows.map { try $0.value() }.sorted { $0.revision < $1.revision }
        guard Set(plans.map(\.revision)).count == plans.count,
              plans.first?.revision == 1,
              plans.first?.predecessorPlanSHA256 == nil else {
            return false
        }
        for index in plans.indices.dropFirst() {
            try plans[index].validate(predecessor: plans[index - 1])
        }
        guard plans.filter({ $0.revision == mutation.resultingPlan.revision }).count == 1,
              plans.first(where: { $0.revision == mutation.resultingPlan.revision }) == mutation.resultingPlan else {
            return false
        }
        guard let receipt = mutation.carryoverReceipt else { return true }
        let receiptRows = try modelContext.fetch(FetchDescriptor<MyDayCarryoverReceiptRowV1>()).filter {
            $0.workspaceID == mutation.workspaceID.rawValue &&
            $0.mutationID == mutation.mutationID.rawValue &&
            $0.receiptSHA256 == receipt.receiptSHA256
        }
        return receiptRows.count == 1 && (try receiptRows[0].value()) == receipt
    }

    func currentMyDayPlan(for key: MyDayKeyV1) throws -> MyDayPlanV1? {
        try key.validate()
        let rows = try modelContext.fetch(FetchDescriptor<MyDayPlanRowV1>())
        let values = try rows.map { try $0.value() }.filter { $0.key == key }
        guard !values.isEmpty else { return nil }
        guard Set(values.map(\.planID)).count == 1,
              Set(values.map(\.revision)).count == values.count else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        let ordered = values.sorted { $0.revision < $1.revision }
        guard ordered.first?.revision == 1,
              ordered.first?.predecessorPlanSHA256 == nil else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        for index in ordered.indices.dropFirst() {
            try ordered[index].validate(predecessor: ordered[index - 1])
        }
        return ordered.last
    }

    private func applyPartsStock(_ mutation: PartsStockMutationV1, temporaryRelativePath: String) throws -> WorkspaceMutationEffectV1 {
        do {
            try mutation.validate()
            func savePart(_ value: LocalPartDefinitionV1) throws {
                let rows = try modelContext.fetch(FetchDescriptor<LocalPartDefinitionRowV1>()).filter { $0.workspaceUUID == value.workspaceID.rawValue && $0.partID == value.partID }
                if rows.isEmpty { guard value.revision == 1 else { throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind: .localPartDefinition, id: value.partID)) }; modelContext.insert(try LocalPartDefinitionRowV1(value)); return }
                guard rows.count == 1, let row = rows.first else { throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind: .localPartDefinition, id: value.partID)) }
                let predecessor = try row.value()
                let (successorRevision, overflow) = predecessor.revision.addingReportingOverflow(1)
                guard !overflow, row.revision == predecessor.revision, successorRevision == value.revision else { throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind: .localPartDefinition, id: value.partID)) }
                if predecessor.canonicalUnit != value.canonicalUnit {
                    let movements = try modelContext.fetch(FetchDescriptor<StockMovementEventRowV1>()).map { try $0.value() }
                    guard !movements.contains(where: { $0.workspaceID == value.workspaceID && $0.part.partID == value.partID }) else {
                        throw WorkspaceMutationFailureV1.invalidCommand
                    }
                }
                row.revision = value.revision; row.archived = value.archived; row.displayName = value.displayName; row.canonicalData = try PartsStockPersistenceCodecV1.encode(value)
            }
            func saveLocation(_ value: StockStorageLocationV1) throws {
                let rows = try modelContext.fetch(FetchDescriptor<StockStorageLocationRowV1>()).filter { $0.workspaceUUID == value.workspaceID.rawValue && $0.locationID == value.locationID }
                if rows.isEmpty { guard value.revision == 1 else { throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind: .stockStorageLocation, id: value.locationID)) }; modelContext.insert(try StockStorageLocationRowV1(value)); return }
                guard rows.count == 1, let row = rows.first else { throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind: .stockStorageLocation, id: value.locationID)) }
                let predecessor = try row.value()
                let (successorRevision, overflow) = predecessor.revision.addingReportingOverflow(1)
                guard !overflow, row.revision == predecessor.revision, successorRevision == value.revision else { throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind: .stockStorageLocation, id: value.locationID)) }
                row.revision = value.revision; row.archived = value.archived; row.label = value.label; row.canonicalData = try PartsStockPersistenceCodecV1.encode(value)
            }
            func replayBalanceStream(_ source: [StockMovementEventV1], partID: UUID, locationID: UUID, workspaceID: WorkspaceID, unit: StockUnitV1) throws -> StockBalanceProjectionV1 {
                let stream = source.sorted { ($0.locationRevision, $0.movementID.uuidString) < ($1.locationRevision, $1.movementID.uuidString) }
                guard Set(stream.map(\.movementID)).count == stream.count,
                      Set(stream.map(\.locationRevision)).count == stream.count else {
                    throw WorkspaceMutationFailureV1.persistenceFailed
                }
                var balance: StockBalanceV1 = .unknown
                var revision: UInt64 = 0
                var lastMovementID: UUID?
                for event in stream {
                    try event.validate()
                    let (nextRevision, overflow) = revision.addingReportingOverflow(1)
                    guard !overflow,
                          event.workspaceID == workspaceID,
                          event.part.partID == partID,
                          event.locationID == locationID,
                          event.unit == unit,
                          event.expectedLocationRevision == revision,
                          event.locationRevision == nextRevision,
                          event.preBalance == balance else {
                        throw WorkspaceMutationFailureV1.persistenceFailed
                    }
                    if lastMovementID == nil {
                        guard event.preBalance == .unknown,
                              event.kind == .openingCount || event.kind == .physicalCount else {
                            throw WorkspaceMutationFailureV1.persistenceFailed
                        }
                    } else if event.kind == .openingCount {
                        throw WorkspaceMutationFailureV1.persistenceFailed
                    }
                    balance = .known(event.postBalance)
                    revision = event.locationRevision
                    lastMovementID = event.movementID
                }
                return StockBalanceProjectionV1(workspaceID: workspaceID, partID: partID, locationID: locationID, unit: unit, balance: balance, locationRevision: revision, lastMovementID: lastMovementID)
            }
            func appendMovement(_ value: StockMovementEventV1) throws {
                let duplicate = try modelContext.fetch(FetchDescriptor<StockMovementEventRowV1>()).filter { $0.workspaceUUID == value.workspaceID.rawValue && $0.movementID == value.movementID }
                guard duplicate.isEmpty else { throw WorkspaceMutationFailureV1.sequenceCollision }
                let partRows = try modelContext.fetch(FetchDescriptor<LocalPartDefinitionRowV1>()).filter { $0.workspaceUUID == value.workspaceID.rawValue && $0.partID == value.part.partID }
                guard partRows.count == 1, let part = try partRows.first?.value(), !part.archived,
                      value.unit == part.canonicalUnit, value.part == (try part.frozenReference()) else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                let stream = try modelContext.fetch(FetchDescriptor<StockMovementEventRowV1>()).map { try $0.value() }.filter {
                    $0.workspaceID == value.workspaceID && $0.part.partID == value.part.partID && $0.locationID == value.locationID
                }
                let prior = try replayBalanceStream(stream, partID: value.part.partID, locationID: value.locationID, workspaceID: value.workspaceID, unit: value.unit)
                let (nextRevision, overflow) = prior.locationRevision.addingReportingOverflow(1)
                guard !overflow,
                      value.expectedLocationRevision == prior.locationRevision,
                      value.locationRevision == nextRevision,
                      value.preBalance == prior.balance else {
                    throw WorkspaceMutationFailureV1.staleEntityRevision(try StockBalanceStreamIdentityV1.entity(partID: value.part.partID, locationID: value.locationID))
                }
                if prior.lastMovementID == nil {
                    guard value.preBalance == .unknown,
                          value.kind == .openingCount || value.kind == .physicalCount else {
                        throw WorkspaceMutationFailureV1.invalidCommand
                    }
                } else if value.kind == .openingCount {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                modelContext.insert(try StockMovementEventRowV1(value))
            }
            func currentBalances(partID: UUID, workspaceID: WorkspaceID, unit: StockUnitV1) throws -> [StockBalanceProjectionV1] {
                let locations = try modelContext.fetch(FetchDescriptor<StockStorageLocationRowV1>()).map { try $0.value() }.filter { $0.workspaceID == workspaceID }
                guard Set(locations.map(\.locationID)).count == locations.count else { throw WorkspaceMutationFailureV1.persistenceFailed }
                let events = try modelContext.fetch(FetchDescriptor<StockMovementEventRowV1>()).map { try $0.value() }.filter { $0.workspaceID == workspaceID && $0.part.partID == partID }
                let locationIDs = Set(locations.map(\.locationID))
                guard events.allSatisfy({ locationIDs.contains($0.locationID) }) else { throw WorkspaceMutationFailureV1.persistenceFailed }
                return try locations.map { location in
                    try replayBalanceStream(events.filter { $0.locationID == location.locationID }, partID: partID, locationID: location.locationID, workspaceID: workspaceID, unit: unit)
                }.sorted { $0.locationID.uuidString < $1.locationID.uuidString }
            }
            func requireCurrentArchivePredecessor(_ declared: LocalPartDefinitionV1, successor: LocalPartDefinitionV1) throws {
                let rows = try modelContext.fetch(FetchDescriptor<LocalPartDefinitionRowV1>()).filter {
                    $0.workspaceUUID == successor.workspaceID.rawValue && $0.partID == successor.partID
                }
                guard rows.count == 1, let predecessor = try rows.first?.value(),
                      predecessor == declared,
                      !predecessor.archived,
                      successor.archived,
                      predecessor.partID == successor.partID,
                      predecessor.workspaceID == successor.workspaceID,
                      predecessor.displayName == successor.displayName,
                      predecessor.canonicalUnit == successor.canonicalUnit,
                      predecessor.productIdentities == successor.productIdentities,
                      predecessor.preferredMinimum == successor.preferredMinimum,
                      predecessor.revision < UInt64.max,
                      successor.revision == predecessor.revision + 1 else {
                    throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind: .localPartDefinition, id: successor.partID))
                }
            }
            switch mutation {
            case let .upsertPart(value): try savePart(value)
            case let .retirePart(value):
                try requireCurrentArchivePredecessor(value.predecessorPart, successor: value.archivedPartSuccessor)
                let actual = try currentBalances(partID: value.archivedPartSuccessor.partID, workspaceID: value.archivedPartSuccessor.workspaceID, unit: value.archivedPartSuccessor.canonicalUnit)
                guard actual == value.verifiedBalances, actual.allSatisfy({ if case let .known(q) = $0.balance { return q.mantissa == 0 }; return false }) else { throw WorkspaceMutationFailureV1.invalidCommand }
                try savePart(value.archivedPartSuccessor)
            case let .upsertLocation(value, _): try saveLocation(value)
            case let .appendMovement(value): try appendMovement(value)
            case let .transfer(value): try appendMovement(value.outbound); try appendMovement(value.inbound)
            case let .use(value):
                try appendMovement(value.movement)
                guard value.workResourceSuccessor.materials.first(where: { $0.lineID == value.frozenMaterialLineID })?.unit == value.movement.unit.rawValue else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                let existing = try modelContext.fetch(FetchDescriptor<StockUseReceiptRowV1>()).filter { $0.workspaceUUID == value.workspaceID.rawValue && $0.receiptID == value.receiptID }
                guard existing.isEmpty else { throw WorkspaceMutationFailureV1.sequenceCollision }
                _ = try applyWorkResource(try .init(workspaceID: value.workspaceID, mutationID: value.mutationID, postImage: value.workResourceSuccessor), temporaryRelativePath: temporaryRelativePath)
                modelContext.insert(try StockUseReceiptRowV1(value))
            case let .reverseUse(value):
                try appendMovement(value.reversalMovement)
                let uses = try modelContext.fetch(FetchDescriptor<StockUseReceiptRowV1>()).filter { $0.workspaceUUID == value.workspaceID.rawValue && $0.receiptID == value.sourceUse.receiptID }
                guard uses.count == 1, try uses[0].value().receiptSHA256 == value.sourceUse.receiptSHA256 else { throw WorkspaceMutationFailureV1.invalidCommand }
                let existingReversals = try modelContext.fetch(FetchDescriptor<StockUseReversalReceiptRowV1>()).filter { $0.workspaceUUID == value.workspaceID.rawValue }
                let existingReturns = try modelContext.fetch(FetchDescriptor<StockReturnReceiptRowV1>()).filter { $0.workspaceUUID == value.workspaceID.rawValue }
                guard try !existingReversals.contains(where: { try $0.value().sourceUse.receiptID == value.sourceUse.receiptID }),
                      try !existingReturns.contains(where: { try $0.value().sourceUseReceiptID == value.sourceUse.receiptID }) else {
                    throw WorkspaceMutationFailureV1.sequenceCollision
                }
                _ = try applyWorkResource(try .init(workspaceID: value.workspaceID, mutationID: value.mutationID, postImage: value.workResourceSuccessor), temporaryRelativePath: temporaryRelativePath)
                modelContext.insert(try StockUseReversalReceiptRowV1(value))
            case let .returnAgainstUse(value):
                let uses = try modelContext.fetch(FetchDescriptor<StockUseReceiptRowV1>()).filter { $0.workspaceUUID == value.workspaceID.rawValue && $0.receiptID == value.sourceUseReceiptID }
                guard uses.count == 1 else { throw WorkspaceMutationFailureV1.invalidCommand }
                let sourceUse = try uses[0].value()
                guard sourceUse == value.sourceUse,
                      sourceUse.receiptSHA256 == value.sourceUseReceiptSHA256 else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                let reversals = try modelContext.fetch(FetchDescriptor<StockUseReversalReceiptRowV1>()).filter { $0.workspaceUUID == value.workspaceID.rawValue }
                guard try !reversals.contains(where: { try $0.value().sourceUse.receiptID == sourceUse.receiptID }) else {
                    throw WorkspaceMutationFailureV1.sequenceCollision
                }
                let existing = try modelContext.fetch(FetchDescriptor<StockReturnReceiptRowV1>()).filter { $0.workspaceUUID == value.workspaceID.rawValue && $0.receiptID == value.receiptID }
                guard existing.isEmpty else { throw WorkspaceMutationFailureV1.sequenceCollision }
                let returns = try modelContext.fetch(FetchDescriptor<StockReturnReceiptRowV1>()).map { try $0.value() }.filter {
                    $0.workspaceID == value.workspaceID && $0.sourceUseReceiptID == sourceUse.receiptID
                }
                guard returns.allSatisfy({ $0.sourceUse == sourceUse && $0.sourceUseReceiptSHA256 == sourceUse.receiptSHA256 }),
                      Set(returns.map(\.receiptID)).count == returns.count else {
                    throw WorkspaceMutationFailureV1.persistenceFailed
                }
                var frontier: StockReturnFrontierSnapshotV1?
                var remaining = returns
                while !remaining.isEmpty {
                    let candidates = remaining.filter { $0.predecessorFrontier == frontier }
                    guard candidates.count == 1, let next = candidates.first else {
                        throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind: .stockUseReceipt, id: sourceUse.receiptID))
                    }
                    frontier = try next.frontierSnapshot()
                    remaining.removeAll { $0.receiptID == next.receiptID }
                }
                guard value.predecessorFrontier == frontier else {
                    throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind: .stockUseReceipt, id: sourceUse.receiptID))
                }
                let predecessorID = frontier?.workResourceSuccessorID ?? sourceUse.workResourceSuccessor.entryID
                let predecessorRows = try modelContext.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).filter {
                    $0.entryID == predecessorID && $0.workspaceID == value.workspaceID.rawValue
                }
                guard predecessorRows.count == 1, let persistedPredecessor = try predecessorRows.first?.value(),
                      persistedPredecessor == value.workResourcePredecessor else {
                    throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind: .workResourceEntry, id: predecessorID))
                }
                if let frontier {
                    guard persistedPredecessor.revision == frontier.workResourceSuccessorRevision,
                          persistedPredecessor.entrySHA256 == frontier.workResourceSuccessorSHA256 else {
                        throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind: .workResourceEntry, id: predecessorID))
                    }
                } else {
                    guard persistedPredecessor == sourceUse.workResourceSuccessor else {
                        throw WorkspaceMutationFailureV1.invalidCommand
                    }
                }
                try appendMovement(value.returnMovement)
                _ = try applyWorkResource(try .init(workspaceID: value.workspaceID, mutationID: value.mutationID, postImage: value.workResourceSuccessor), temporaryRelativePath: temporaryRelativePath)
                modelContext.insert(try StockReturnReceiptRowV1(value))
            case let .abandon(value):
                try requireCurrentArchivePredecessor(value.predecessorPart, successor: value.archivedPartSuccessor)
                let existingIDs = Set(value.dispositions.map(\.dispositionID))
                let existing = try modelContext.fetch(FetchDescriptor<AbandonUnverifiedStockRowV1>()).filter { $0.workspaceUUID == value.archivedPartSuccessor.workspaceID.rawValue && existingIDs.contains($0.dispositionID) }
                guard existing.isEmpty else { throw WorkspaceMutationFailureV1.sequenceCollision }
                let actual = try currentBalances(partID: value.archivedPartSuccessor.partID, workspaceID: value.archivedPartSuccessor.workspaceID, unit: value.archivedPartSuccessor.canonicalUnit)
                let unknownIDs = Set(actual.compactMap { if case .unknown = $0.balance { return $0.locationID }; return nil })
                let actualByLocation = Dictionary(uniqueKeysWithValues: actual.map { ($0.locationID, $0) })
                guard unknownIDs == Set(value.dispositions.map(\.locationID)),
                      !actual.contains(where: { if case let .known(q) = $0.balance { return q.mantissa > 0 }; return false }),
                      value.dispositions.allSatisfy({ disposition in
                          guard let projection = actualByLocation[disposition.locationID] else { return false }
                          return disposition.lastLocationRevision == projection.locationRevision
                              && disposition.lastMovementID == projection.lastMovementID
                      }) else { throw WorkspaceMutationFailureV1.invalidCommand }
                try savePart(value.archivedPartSuccessor)
                for disposition in value.dispositions { modelContext.insert(try AbandonUnverifiedStockRowV1(disposition)) }
            }
            return try WorkspaceMutationEffectV1(affectedEntities: mutation.affectedIdentities, temporaryRelativePath: temporaryRelativePath)
        } catch let failure as WorkspaceMutationFailureV1 { modelContext.rollback(); throw failure }
          catch { modelContext.rollback(); throw WorkspaceMutationFailureV1.invalidCommand }
    }

    private func applyWorkResource(_ mutation: WorkResourceMutationV1, temporaryRelativePath: String) throws -> WorkspaceMutationEffectV1 {
        do {
            try mutation.validate()
            let value = mutation.postImage
            guard value.actor.responsibility == .recordedBy || value.actor.responsibility == .performedBy else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            try requireExactActor(value.actor)
            guard let subjectUUID = UUID(uuidString: value.subject.subjectID) else { throw WorkspaceMutationFailureV1.invalidCommand }
            switch value.subject.kind {
            case .workPacket:
                let rows = try modelContext.fetch(FetchDescriptor<WorkPacketManifestRow>(predicate: #Predicate { $0.manifestID == subjectUUID }))
                guard rows.count == 1, let subject = try rows.first?.value(),
                      subject.workspaceID == value.workspaceID,
                      subject.revision == value.subject.subjectRevision,
                      subject.manifestSHA256 == value.subject.subjectSHA256 else { throw WorkspaceMutationFailureV1.invalidCommand }
            case .correctiveWork:
                let rows = try modelContext.fetch(FetchDescriptor<CorrectiveActionEventRow>(predicate: #Predicate { $0.eventID == subjectUUID }))
                guard rows.count == 1, let subject = try rows.first?.value(),
                      subject.workspaceID == value.workspaceID,
                      subject.revision == value.subject.subjectRevision,
                      subject.eventSHA256 == value.subject.subjectSHA256 else { throw WorkspaceMutationFailureV1.invalidCommand }
            }
            let id = value.entryID
            let duplicate = try modelContext.fetch(FetchDescriptor<ManualWorkResourceRecordRow>(predicate: #Predicate { $0.entryID == id }))
            guard duplicate.isEmpty else { throw WorkspaceMutationFailureV1.sequenceCollision }
            if let predecessorID = value.supersedesEntryID {
                let rows = try modelContext.fetch(FetchDescriptor<ManualWorkResourceRecordRow>(predicate: #Predicate { $0.entryID == predecessorID }))
                guard rows.count == 1, let predecessor = try rows.first?.value() else { throw WorkspaceMutationFailureV1.staleEntityRevision(try mutation.concurrencyIdentity) }
                let successors = try modelContext.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).map { try $0.value() }.filter { $0.supersedesEntryID == predecessorID }
                guard successors.isEmpty else { throw WorkspaceMutationFailureV1.staleEntityRevision(try mutation.concurrencyIdentity) }
                try value.validateSuccessor(of: predecessor)
                guard value.entryID != predecessor.entryID,
                      value.mutationID != predecessor.mutationID,
                      value.recordedAt >= predecessor.recordedAt,
                      value.disposition == .superseded || value.disposition == .voidedWithReason || value.disposition == .reversed else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            } else {
                guard value.expectedRevision == 0, value.revision == 1,
                      value.disposition == .active else { throw WorkspaceMutationFailureV1.invalidCommand }
            }
            modelContext.insert(try ManualWorkResourceRecordRow(value))
            return try WorkspaceMutationEffectV1(affectedEntities: mutation.affectedIdentities, temporaryRelativePath: temporaryRelativePath)
        } catch let failure as WorkspaceMutationFailureV1 {
            modelContext.rollback(); throw failure
        } catch {
            modelContext.rollback(); throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    private func applyServiceRequest(
        _ mutation: ServiceRequestMutationV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        do {
            try mutation.validateForCanonicalWriter()
            for payload in mutation.payloads {
                switch payload {
                case let .appendRecord(value):
                    let id = value.recordID
                    let workspaceID = value.workspaceID.rawValue
                    let rows = try modelContext.fetch(FetchDescriptor<ServiceRequestRecordRow>(predicate: #Predicate { $0.recordID == id && $0.workspaceID == workspaceID }))
                    guard !rows.contains(where: { $0.revision == value.revision }) else {
                        throw WorkspaceMutationFailureV1.sequenceCollision
                    }
                    if let predecessorReference = value.supersedes {
                        let predecessors = try rows.filter { $0.revision == predecessorReference.revision }.map { try $0.value() }
                        guard predecessors.count == 1 else { throw WorkspaceMutationFailureV1.staleEntityRevision(try payload.concurrencyIdentity) }
                        try value.validateSuccessor(of: predecessors[0])
                        guard !rows.contains(where: { $0.revision > predecessorReference.revision }) else {
                            throw WorkspaceMutationFailureV1.staleEntityRevision(try payload.concurrencyIdentity)
                        }
                    } else {
                        guard rows.isEmpty else { throw WorkspaceMutationFailureV1.sequenceCollision }
                    }
                    modelContext.insert(try ServiceRequestRecordRow(value))
                case let .appendDisposition(value):
                    let id = value.eventID
                    guard try modelContext.fetch(FetchDescriptor<ServiceRequestDispositionEventRow>(predicate: #Predicate { $0.eventID == id })).isEmpty else {
                        throw WorkspaceMutationFailureV1.sequenceCollision
                    }
                    if let predecessorID = value.predecessorEventID {
                        let rows = try modelContext.fetch(FetchDescriptor<ServiceRequestDispositionEventRow>(predicate: #Predicate { $0.eventID == predecessorID }))
                        guard rows.count == 1 else { throw WorkspaceMutationFailureV1.staleEntityRevision(try payload.concurrencyIdentity) }
                        let predecessor = try rows[0].value()
                        try value.validateSuccessor(of: predecessor)
                        let successors = try modelContext.fetch(FetchDescriptor<ServiceRequestDispositionEventRow>())
                            .filter { $0.predecessorEventID == predecessorID }
                        guard successors.isEmpty else { throw WorkspaceMutationFailureV1.staleEntityRevision(try payload.concurrencyIdentity) }
                    } else {
                        let requestID = value.request.recordID
                        let existing = try modelContext.fetch(FetchDescriptor<ServiceRequestDispositionEventRow>())
                            .filter { $0.requestRecordID == requestID }
                        guard existing.isEmpty else { throw WorkspaceMutationFailureV1.sequenceCollision }
                    }
                    let requestID = value.request.recordID
                    let requestRevision = value.request.revision
                    let workspaceID = value.workspaceID.rawValue
                    let requestRows = try modelContext.fetch(FetchDescriptor<ServiceRequestRecordRow>(predicate: #Predicate { $0.recordID == requestID && $0.workspaceID == workspaceID }))
                    let matchingRequests = try requestRows.filter { $0.revision == requestRevision }.map { try $0.value() }
                    guard matchingRequests.count == 1,
                          try matchingRequests[0].reference == value.request else {
                        throw WorkspaceMutationFailureV1.invalidCommand
                    }
                    modelContext.insert(try ServiceRequestDispositionEventRow(value))
                case let .appendWorkLink(value), let .appendWorkLinkReversal(value):
                    let id = value.eventID
                    guard try modelContext.fetch(FetchDescriptor<ServiceRequestWorkLinkEventRow>(predicate: #Predicate { $0.eventID == id })).isEmpty else {
                        throw WorkspaceMutationFailureV1.sequenceCollision
                    }
                    if let predecessorID = value.predecessorEventID {
                        let rows = try modelContext.fetch(FetchDescriptor<ServiceRequestWorkLinkEventRow>(predicate: #Predicate { $0.eventID == predecessorID }))
                        guard rows.count == 1 else { throw WorkspaceMutationFailureV1.staleEntityRevision(try payload.concurrencyIdentity) }
                        let predecessor = try rows[0].value()
                        try value.validateSuccessor(of: predecessor)
                        guard predecessor.kind == .link,
                              value.target == predecessor.target,
                              value.choice == predecessor.choice,
                              value.canonicalWorkRevision == predecessor.canonicalWorkRevision,
                              value.canonicalWorkSHA256 == predecessor.canonicalWorkSHA256 else {
                            throw WorkspaceMutationFailureV1.invalidCommand
                        }
                        let successors = try modelContext.fetch(FetchDescriptor<ServiceRequestWorkLinkEventRow>())
                            .filter { $0.predecessorEventID == predecessorID }
                        guard successors.isEmpty else { throw WorkspaceMutationFailureV1.staleEntityRevision(try payload.concurrencyIdentity) }
                    } else {
                        let requestID = value.request.recordID
                        let existing = try modelContext.fetch(FetchDescriptor<ServiceRequestWorkLinkEventRow>())
                            .filter { $0.requestRecordID == requestID }
                        guard value.kind == .link, existing.isEmpty else { throw WorkspaceMutationFailureV1.sequenceCollision }
                    }
                    let requestID = value.request.recordID
                    let requestRevision = value.request.revision
                    let workspaceID = value.workspaceID.rawValue
                    let requestRows = try modelContext.fetch(FetchDescriptor<ServiceRequestRecordRow>(predicate: #Predicate { $0.recordID == requestID && $0.workspaceID == workspaceID }))
                    let matchingRequests = try requestRows.filter { $0.revision == requestRevision }.map { try $0.value() }
                    guard matchingRequests.count == 1,
                          try matchingRequests[0].reference == value.request else {
                        throw WorkspaceMutationFailureV1.invalidCommand
                    }
                    modelContext.insert(try ServiceRequestWorkLinkEventRow(value))
                }
            }
            return try WorkspaceMutationEffectV1(
                affectedEntities: mutation.affectedIdentities,
                temporaryRelativePath: temporaryRelativePath
            )
        } catch let failure as WorkspaceMutationFailureV1 {
            modelContext.rollback(); throw failure
        } catch {
            modelContext.rollback(); throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    func persistedServiceRequestEffectMatches(_ mutation: ServiceRequestMutationV1) throws -> Bool {
        try mutation.validateForCanonicalWriter()
        var matches = 0
        for payload in mutation.payloads {
            let exact: Bool
            switch payload {
            case let .appendRecord(value):
                let id = value.recordID
                let workspaceID = value.workspaceID.rawValue
                let revision = value.revision
                let rows = try modelContext.fetch(FetchDescriptor<ServiceRequestRecordRow>(predicate: #Predicate { $0.recordID == id && $0.workspaceID == workspaceID && $0.revision == revision }))
                guard rows.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exact = try rows.first.map { try $0.value() == value } ?? false
            case let .appendDisposition(value):
                let id = value.eventID
                let rows = try modelContext.fetch(FetchDescriptor<ServiceRequestDispositionEventRow>(predicate: #Predicate { $0.eventID == id }))
                guard rows.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exact = try rows.first.map { try $0.value() == value } ?? false
            case let .appendWorkLink(value), let .appendWorkLinkReversal(value):
                let id = value.eventID
                let rows = try modelContext.fetch(FetchDescriptor<ServiceRequestWorkLinkEventRow>(predicate: #Predicate { $0.eventID == id }))
                guard rows.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exact = try rows.first.map { try $0.value() == value } ?? false
            }
            if exact { matches += 1 }
        }
        guard matches == 0 || matches == mutation.payloads.count else {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        return matches == mutation.payloads.count
    }

    private func applyServiceReliability(_ bundle:ServiceReliabilityAtomicBundleV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{
        do{try bundle.validateForCanonicalWriter();for payload in bundle.payloads{try validateServiceReliabilityAppend(payload);switch payload{case .incident(let v):modelContext.insert(try AssetServiceIncidentRow(v));case .impact(let v):modelContext.insert(try ServiceImpactSegmentRow(v));case .cause(let v):modelContext.insert(try ServiceCauseAssertionRow(v));case .remedy(let v):modelContext.insert(try ServiceRemedyAssertionRow(v));case .repair(let v):modelContext.insert(try ServiceRepairIntervalRow(v));case .restoration(let v):modelContext.insert(try ServiceRestorationAssertionRow(v));case .exposure(let v):modelContext.insert(try QualifiedServiceExposureRow(v))}};return try WorkspaceMutationEffectV1(affectedEntities:bundle.affectedIdentities,temporaryRelativePath:temporaryRelativePath)}catch let failure as WorkspaceMutationFailureV1{modelContext.rollback();throw failure}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}
    }

    private func validateServiceReliabilityAppend(_ payload:ServiceReliabilityMutationPayloadV1)throws{
        let eventID=payload.eventID,workspaceID=payload.workspaceID.rawValue,predecessor=payload.predecessorReference
        func check(_ rows:[(UUID,UUID,UInt64,UUID?,String)])throws{guard !rows.contains(where:{$0.0==eventID&&$0.1==workspaceID})else{throw WorkspaceMutationFailureV1.sequenceCollision};if let predecessor{guard let prior=rows.first(where:{$0.0==predecessor.eventID&&$0.1==workspaceID}),!rows.contains(where:{$0.3==predecessor.eventID}),predecessor.revision==prior.2,predecessor.eventSHA256==prior.4,prior.2<UInt64.max,payload.revision==prior.2+1 else{throw WorkspaceMutationFailureV1.staleEntityRevision(try payload.concurrencyIdentity)}}else{guard payload.revision==1 else{throw WorkspaceMutationFailureV1.invalidCommand}}}
        switch payload{
        case .incident:try check(try modelContext.fetch(FetchDescriptor<AssetServiceIncidentRow>()).map{($0.eventID,$0.workspaceID,$0.revision,$0.predecessorEventID,$0.eventSHA256)})
        case .impact:try check(try modelContext.fetch(FetchDescriptor<ServiceImpactSegmentRow>()).map{($0.eventID,$0.workspaceID,$0.revision,$0.predecessorEventID,$0.eventSHA256)})
        case .cause:try check(try modelContext.fetch(FetchDescriptor<ServiceCauseAssertionRow>()).map{($0.eventID,$0.workspaceID,$0.revision,$0.predecessorEventID,$0.eventSHA256)})
        case .remedy:try check(try modelContext.fetch(FetchDescriptor<ServiceRemedyAssertionRow>()).map{($0.eventID,$0.workspaceID,$0.revision,$0.predecessorEventID,$0.eventSHA256)})
        case .repair:try check(try modelContext.fetch(FetchDescriptor<ServiceRepairIntervalRow>()).map{($0.eventID,$0.workspaceID,$0.revision,$0.predecessorEventID,$0.eventSHA256)})
        case .restoration:try check(try modelContext.fetch(FetchDescriptor<ServiceRestorationAssertionRow>()).map{($0.eventID,$0.workspaceID,$0.revision,$0.predecessorEventID,$0.eventSHA256)})
        case .exposure:try check(try modelContext.fetch(FetchDescriptor<QualifiedServiceExposureRow>()).map{($0.eventID,$0.workspaceID,$0.revision,$0.predecessorEventID,$0.eventSHA256)})}
    }

    func persistedServiceReliabilityEffectMatches(_ bundle:ServiceReliabilityAtomicBundleV1)throws->Bool{
        try bundle.validateForCanonicalWriter();var matches=0
        for payload in bundle.payloads{let exact:Bool;switch payload{case .incident(let v):exact=try modelContext.fetch(FetchDescriptor<AssetServiceIncidentRow>()).first(where:{$0.eventID==v.eventID&&$0.workspaceID==v.workspaceID.rawValue}).map{try $0.value()==v} ?? false;case .impact(let v):exact=try modelContext.fetch(FetchDescriptor<ServiceImpactSegmentRow>()).first(where:{$0.eventID==v.eventID&&$0.workspaceID==v.workspaceID.rawValue}).map{try $0.value()==v} ?? false;case .cause(let v):exact=try modelContext.fetch(FetchDescriptor<ServiceCauseAssertionRow>()).first(where:{$0.eventID==v.eventID&&$0.workspaceID==v.workspaceID.rawValue}).map{try $0.value()==v} ?? false;case .remedy(let v):exact=try modelContext.fetch(FetchDescriptor<ServiceRemedyAssertionRow>()).first(where:{$0.eventID==v.eventID&&$0.workspaceID==v.workspaceID.rawValue}).map{try $0.value()==v} ?? false;case .repair(let v):exact=try modelContext.fetch(FetchDescriptor<ServiceRepairIntervalRow>()).first(where:{$0.eventID==v.eventID&&$0.workspaceID==v.workspaceID.rawValue}).map{try $0.value()==v} ?? false;case .restoration(let v):exact=try modelContext.fetch(FetchDescriptor<ServiceRestorationAssertionRow>()).first(where:{$0.eventID==v.eventID&&$0.workspaceID==v.workspaceID.rawValue}).map{try $0.value()==v} ?? false;case .exposure(let v):exact=try modelContext.fetch(FetchDescriptor<QualifiedServiceExposureRow>()).first(where:{$0.eventID==v.eventID&&$0.workspaceID==v.workspaceID.rawValue}).map{try $0.value()==v} ?? false};if exact{matches+=1}}
        guard matches==0||matches==bundle.payloads.count else{throw WorkspaceMutationFailureV1.persistenceFailed};return matches==bundle.payloads.count
    }

    /// Read-only C47 recovery preflight.  Returning `false` is reserved for
    /// a wholly absent effect; every partial or noncanonical persisted shape
    /// fails closed so a retry cannot compound it.
    func persistedActivityContractEffectMatches(
        _ mutation: ActivityContractMutationV2
    ) throws -> Bool {
        try mutation.validateForCanonicalMutation()
        let mutationID = mutation.mutationID.rawValue
        let workspace = mutation.workspaceID.rawValue
        let envelopeRows = try modelContext.fetch(FetchDescriptor<ActivitySessionEnvelopeRow>(
            predicate: #Predicate { $0.mutationID == mutationID }
        ))
        let transitionRows = try modelContext.fetch(FetchDescriptor<ActivityStateTransitionRow>(
            predicate: #Predicate { $0.mutationID == mutationID }
        ))
        let resultRows = try modelContext.fetch(FetchDescriptor<InstallationTaskResultRow>(
            predicate: #Predicate { $0.mutationID == mutationID }
        ))
        let snapshotRows = try modelContext.fetch(FetchDescriptor<InstallationAsBuiltSnapshotRow>(
            predicate: #Predicate { $0.mutationID == mutationID }
        ))
        let basisRows = try modelContext.fetch(FetchDescriptor<PunchReviewBasisSnapshotRow>(
            predicate: #Predicate { $0.mutationID == mutationID }
        ))
        let rowCount = envelopeRows.count + transitionRows.count + resultRows.count
            + snapshotRows.count + basisRows.count
        guard rowCount > 0 else { return false }
        guard envelopeRows.allSatisfy({ $0.workspaceID == workspace }),
              transitionRows.allSatisfy({ $0.workspaceID == workspace }),
              resultRows.allSatisfy({ $0.workspaceID == workspace }),
              snapshotRows.allSatisfy({ $0.workspaceID == workspace }),
              basisRows.allSatisfy({ $0.workspaceID == workspace }),
              envelopeRows.count == 1,
              transitionRows.count == (mutation.transition == nil ? 0 : 1),
              resultRows.count == mutation.installationTaskResults.count,
              snapshotRows.count == (mutation.installationAsBuiltSnapshot == nil ? 0 : 1),
              basisRows.count == (mutation.punchReviewBasisSnapshot == nil ? 0 : 1),
              let envelopeRow = envelopeRows.first,
              try envelopeRow.value() == mutation.successorEnvelope else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        let transition = try transitionRows.first.map { try $0.value() }
        let results = try resultRows.map { try $0.value() }.sorted {
            $0.resultID.uuidString < $1.resultID.uuidString
        }
        let snapshot = try snapshotRows.first.map { try $0.value() }
        let basis = try basisRows.first.map { try $0.value() }
        guard transition == mutation.transition,
              results == mutation.installationTaskResults,
              snapshot == mutation.installationAsBuiltSnapshot,
              basis == mutation.punchReviewBasisSnapshot else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        let persisted = try ActivityContractMutationV2(
            workspaceID: mutation.workspaceID,
            expectedRevision: mutation.expectedRevision,
            mutationID: mutation.mutationID,
            predecessorEnvelope: mutation.predecessorEnvelope,
            successorEnvelope: try envelopeRow.value(),
            transition: transition,
            completedSnapshotReference: mutation.completedSnapshotReference,
            installationBasisSnapshot: mutation.installationBasisSnapshot,
            installationTaskResults: results,
            installationAsBuiltSnapshot: snapshot,
            punchReviewBasisSnapshot: basis
        )
        guard persisted.mutationSHA256 == mutation.mutationSHA256,
              try persisted.affectedIdentities == mutation.affectedIdentities,
              try persisted.mutationPostImages == mutation.mutationPostImages else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return true
    }

    /// C47 alone commits its already-validated effect at the explicit
    /// effect-before-receipt interruption boundary.  `apply` starts from a
    /// clean context, and the exact preflight below proves this save contains
    /// the complete C47 effect rather than unrelated pending changes.
    func persistAppliedActivityContractEffect(
        _ mutation: ActivityContractMutationV2
    ) throws {
        guard modelContext.hasChanges,
              try persistedActivityContractEffectMatches(mutation) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
    }

    private func applyActivityContract(
        _ mutation: ActivityContractMutationV2,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        do {
            try mutation.validateForCanonicalMutation()
            guard C47ActivityContractPersistenceBoundaryV2.acceptsCanonicalRow(
                kind: mutation.successorEnvelope.kind
            ) else { throw WorkspaceMutationFailureV1.invalidCommand }
            let workspace = mutation.workspaceID.rawValue
            let activityID = mutation.successorEnvelope.activityID
            let envelopeRows = try modelContext.fetch(FetchDescriptor<ActivitySessionEnvelopeRow>(
                predicate: #Predicate { $0.workspaceID == workspace && $0.activityID == activityID }
            ))
            guard envelopeRows.count <= 1 else { throw WorkspaceMutationFailureV1.sequenceCollision }
            let persistedTaskResults = try modelContext.fetch(FetchDescriptor<InstallationTaskResultRow>(
                predicate: #Predicate { $0.workspaceID == workspace && $0.activityID == activityID }
            )).map { try $0.value() }
            let currentTaskHeads = try InstallationTaskResultLineageV1
                .validateAndCurrentHeads(persistedTaskResults)
            let taskHeadContext = try InstallationTaskCurrentHeadContextV1(
                workspaceID: mutation.workspaceID,
                activityID: activityID,
                currentHeads: Array(currentTaskHeads.values)
            )
            let completedSnapshotContext = try mutation.completedSnapshotReference.map {
                try resolveCompletedActivitySnapshot($0)
            }
            let basisHeads = try resolveActivityBasisHeads(mutation)
            let workflowReleaseContext = try resolveActivityWorkflowRelease(mutation, basisHeads: basisHeads)
            let installationReferenceContext = try resolveInstallationReferences(mutation)
            let closeoutContext = try resolveActivityCloseout(mutation)
            try mutation.validateResolved(
                completedSnapshot: completedSnapshotContext,
                installationTaskHeads: taskHeadContext,
                currentInstallationBasis: basisHeads.installation,
                currentPunchBasis: basisHeads.punch,
                workflowReleaseContext: workflowReleaseContext,
                installationReferenceContext: installationReferenceContext,
                closeoutContext: closeoutContext
            )
            if let predecessor = mutation.predecessorEnvelope {
                guard let row = envelopeRows.first, try row.value() == predecessor else {
                    throw WorkspaceMutationFailureV1.staleEntityRevision(
                        try .init(kind: .activitySessionEnvelope, id: activityID)
                    )
                }
                try row.replace(with: mutation.successorEnvelope)
            } else {
                guard envelopeRows.isEmpty else { throw WorkspaceMutationFailureV1.sequenceCollision }
                modelContext.insert(try ActivitySessionEnvelopeRow(mutation.successorEnvelope))
            }

            if let transition = mutation.transition {
                let id = transition.transitionID
                guard try modelContext.fetch(FetchDescriptor<ActivityStateTransitionRow>(
                    predicate: #Predicate { $0.workspaceID == workspace && $0.transitionID == id }
                )).isEmpty else { throw WorkspaceMutationFailureV1.sequenceCollision }
                modelContext.insert(try ActivityStateTransitionRow(transition))
            }
            for result in mutation.installationTaskResults {
                let id = result.resultID
                guard try modelContext.fetch(FetchDescriptor<InstallationTaskResultRow>(
                    predicate: #Predicate { $0.workspaceID == workspace && $0.resultID == id }
                )).isEmpty else { throw WorkspaceMutationFailureV1.sequenceCollision }
                modelContext.insert(try InstallationTaskResultRow(result))
            }
            if let snapshot = mutation.installationAsBuiltSnapshot {
                let id = snapshot.snapshotID
                guard try modelContext.fetch(FetchDescriptor<InstallationAsBuiltSnapshotRow>(
                        predicate: #Predicate { $0.workspaceID == workspace && $0.snapshotID == id }
                      )).isEmpty else { throw WorkspaceMutationFailureV1.invalidCommand }
                modelContext.insert(try InstallationAsBuiltSnapshotRow(snapshot))
            }
            if let basis = mutation.punchReviewBasisSnapshot {
                let id = basis.basisID
                guard try modelContext.fetch(FetchDescriptor<PunchReviewBasisSnapshotRow>(
                    predicate: #Predicate { $0.workspaceID == workspace && $0.basisID == id }
                )).isEmpty else { throw WorkspaceMutationFailureV1.sequenceCollision }
                modelContext.insert(try PunchReviewBasisSnapshotRow(basis))
            }
            return try WorkspaceMutationEffectV1(
                affectedEntities: mutation.affectedIdentities,
                temporaryRelativePath: temporaryRelativePath
            )
        } catch let failure as WorkspaceMutationFailureV1 {
            modelContext.rollback(); throw failure
        } catch {
            modelContext.rollback(); throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    private func resolveActivityBasisHeads(
        _ mutation: ActivityContractMutationV2
    ) throws -> (installation: InstallationBasisSnapshotV1?, punch: PunchReviewBasisSnapshotV1?) {
        let workspace = mutation.workspaceID.rawValue
        let activityID = mutation.successorEnvelope.activityID
        let receiptRows = try modelContext.fetch(FetchDescriptor<MutationReceiptRow>(
            predicate: #Predicate { $0.workspaceID == workspace }
        ))
        var installationValues: [InstallationBasisSnapshotV1] = []
        for row in receiptRows {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData)
            guard case let .applyActivityContract(prior) = envelope.command,
                  prior.successorEnvelope.activityID == activityID,
                  let basis = prior.installationBasisSnapshot else { continue }
            try basis.validate()
            installationValues.append(basis)
        }
        let installation = try currentInstallationBasis(in: installationValues)
        let punchValues = try modelContext.fetch(FetchDescriptor<PunchReviewBasisSnapshotRow>(
            predicate: #Predicate { $0.workspaceID == workspace && $0.activityID == activityID }
        )).map { try $0.value() }
        let punch = try currentPunchBasis(in: punchValues)
        return (installation, punch)
    }

    private func currentInstallationBasis(
        in values: [InstallationBasisSnapshotV1]
    ) throws -> InstallationBasisSnapshotV1? {
        guard Set(values.map(\.basisID)).count == values.count,
              Set(values.map(\.basisSHA256)).count == values.count else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let ordered = values.sorted { $0.revision < $1.revision }
        for (index, value) in ordered.enumerated() {
            try value.validate()
            if index == 0 {
                guard value.revision == 1, value.predecessorBasisID == nil,
                      value.predecessorBasisSHA256 == nil else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            } else {
                try value.validateSuccessor(of: ordered[index - 1])
            }
        }
        return ordered.last
    }

    private func currentPunchBasis(
        in values: [PunchReviewBasisSnapshotV1]
    ) throws -> PunchReviewBasisSnapshotV1? {
        guard Set(values.map(\.basisID)).count == values.count,
              Set(values.map(\.basisSHA256)).count == values.count else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let ordered = values.sorted { $0.revision < $1.revision }
        for (index, value) in ordered.enumerated() {
            try value.validate()
            if index == 0 {
                guard value.revision == 1, value.predecessorBasisID == nil,
                      value.predecessorBasisSHA256 == nil else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            } else {
                try value.validateSuccessor(of: ordered[index - 1])
            }
        }
        return ordered.last
    }

    private func resolveActivityWorkflowRelease(
        _ mutation: ActivityContractMutationV2,
        basisHeads: (installation: InstallationBasisSnapshotV1?, punch: PunchReviewBasisSnapshotV1?)
    ) throws -> ActivityWorkflowReleaseResolutionContextV2? {
        let reference: ActivityWorkflowReleaseReferenceV2
        switch mutation.successorEnvelope.kind {
        case .installation:
            guard let basis = mutation.installationBasisSnapshot ?? basisHeads.installation else { return nil }
            reference = basis.workflowReleaseReference
        case .punchReview:
            guard let basis = mutation.punchReviewBasisSnapshot ?? basisHeads.punch else { return nil }
            reference = basis.workflowReleaseReference
        default:
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let forStart = mutation.predecessorEnvelope?.startedAt == nil
            && mutation.successorEnvelope.startedAt != nil
        return try PackageEvolutionLifecycleAdapterV1.resolveActivityWorkflowRelease(
            reference: reference,
            kind: mutation.successorEnvelope.kind,
            forStart: forStart,
            modelContext: modelContext
        )
    }

    private func resolveInstallationReferences(
        _ mutation: ActivityContractMutationV2
    ) throws -> ActivityInstallationReferenceResolutionContextV2? {
        guard mutation.successorEnvelope.kind == .installation else { return nil }
        let requestedContent = mutation.installationTaskResults.flatMap(\.evidenceReferences)
        let requestedPlacements = mutation.installationAsBuiltSnapshot?.placementReferences ?? []
        let evidenceRows = try modelContext.fetch(FetchDescriptor<EvidenceFile>())
        let instantFormatter = ISO8601DateFormatter()
        instantFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let resolvedContent = try requestedContent.map { reference -> ContentReferenceV1 in
            guard let id = UUID(uuidString: reference.contentID) else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            let matches = evidenceRows.filter { $0.id == id }
            guard matches.count == 1, let row = matches.first,
                  reference.workspaceID.lowercased() == mutation.workspaceID.rawValue.uuidString.lowercased(),
                  reference.byteLength == Int64(row.byteCount), reference.mediaType == row.mimeType,
                  reference.digests.digest(for: .sha256)?.hexadecimalValue == row.sha256,
                  reference.byteRole == .immutableOriginal,
                  reference.createdAt == instantFormatter.string(from: row.createdAt) else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            return reference
        }
        var plans: [PlanPlacementV1] = []
        var poses: [AssetPoseEventV1] = []
        for requested in requestedPlacements {
            switch requested {
            case let .plan(reference):
                let rows = try modelContext.fetch(FetchDescriptor<PlanPlacementRow>()).map { try $0.value() }
                    .filter { $0.placementID == reference.placementID && $0.revision == reference.revision && $0.placementSHA256 == reference.placementSHA256 }
                guard rows.count == 1, let value = rows.first else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                plans.append(value)
            case let .pose(reference):
                let rows = try modelContext.fetch(FetchDescriptor<AssetPoseEventRow>()).map { try $0.value() }
                    .filter { $0.reference == reference }
                guard rows.count == 1, let value = rows.first else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                poses.append(value)
            }
        }
        return try ActivityInstallationReferenceResolutionContextV2(
            contentReferences: resolvedContent, planPlacements: plans, poseEvents: poses
        )
    }

    private func resolveActivityCloseout(
        _ mutation: ActivityContractMutationV2
    ) throws -> ActivityCloseoutResolutionContextV2? {
        let links: [PunchFindingLinkV1]
        if let closeout = mutation.successorEnvelope.installationCloseout {
            links = closeout.openFindings
        } else if let closeout = mutation.successorEnvelope.punchReviewCloseout {
            links = closeout.scope.flatMap(\.findingLinks)
        } else {
            return nil
        }
        let workspace = mutation.workspaceID.rawValue
        let activityID = mutation.successorEnvelope.activityID
        let findings: [FindingV1]
        if links.isEmpty {
            findings = []
        } else {
            guard let activityFindingEvidenceResolver else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            let evidence = try activityFindingEvidenceResolver(links)
            try evidence.forEach { try $0.validate() }
            findings = evidence.map(\.finding)
            try validateResolvedActivityFindings(findings, links: links)
        }
        let receiptRows = try modelContext.fetch(FetchDescriptor<MutationReceiptRow>(
            predicate: #Predicate { $0.workspaceID == workspace }
        ))
        let receiptHistory = try receiptRows.map { row in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData)
            let receipt = try MutationReceiptV1.decodeCanonical(from: row.receiptData)
            guard receipt.mutationID == envelope.mutationID,
                  receipt.identity.workspaceID == envelope.workspaceID,
                  receipt.envelopeSHA256 == envelope.envelopeSHA256,
                  receipt.commandBodySHA256
                    == (try WorkspaceMutationCanonicalV1.sha256(envelope.command)) else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            return (envelope: envelope, receipt: receipt)
        }
        let requestedSourceSHA256s = Set(links.map(\.sourceContext.activitySHA256))
        var sourceEnvelopesBySHA256: [String: ActivitySessionEnvelopeV2] = [:]
        for entry in receiptHistory {
            guard case let .applyActivityContract(prior) = entry.envelope.command,
                  prior.workspaceID == mutation.workspaceID else { continue }
            var candidates = [prior.successorEnvelope]
            if let predecessor = prior.predecessorEnvelope {
                candidates.append(predecessor)
            }
            for candidate in candidates where requestedSourceSHA256s.contains(candidate.envelopeSHA256) {
                if let existing = sourceEnvelopesBySHA256[candidate.envelopeSHA256],
                   existing != candidate {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                sourceEnvelopesBySHA256[candidate.envelopeSHA256] = candidate
            }
        }
        guard sourceEnvelopesBySHA256.keys.count == requestedSourceSHA256s.count else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let supportingRecords = try resolveActivitySupportingRecords(
            links, receiptHistory: receiptHistory,
            workspaceID: mutation.workspaceID
        )
        let asBuilt: InstallationAsBuiltSnapshotV1?
        if let candidate = mutation.installationAsBuiltSnapshot {
            asBuilt = candidate
        } else if let digest = mutation.successorEnvelope.installationCloseout?.asBuiltSnapshotSHA256 {
            let matches = try modelContext.fetch(FetchDescriptor<InstallationAsBuiltSnapshotRow>(
                predicate: #Predicate { $0.workspaceID == workspace && $0.activityID == activityID }
            )).map { try $0.value() }.filter { $0.snapshotSHA256 == digest }
            guard matches.count == 1 else { throw WorkspaceMutationFailureV1.invalidCommand }
            asBuilt = matches.first
        } else {
            asBuilt = nil
        }
        return try ActivityCloseoutResolutionContextV2(
            findings: findings, supportingRecords: supportingRecords,
            sourceEnvelopes: Array(sourceEnvelopesBySHA256.values),
            installationAsBuiltSnapshot: asBuilt
        )
    }

    private func validateResolvedActivityFindings(
        _ findings: [FindingV1],
        links: [PunchFindingLinkV1]
    ) throws {
        let requested = Dictionary(grouping: links, by: \.findingID)
        guard requested.values.allSatisfy({ values in
                  Set(values.map { "\($0.findingRevision)|\($0.findingSHA256)" }).count == 1
              }),
              Set(findings.compactMap { UUID(uuidString: $0.findingID) }).count == findings.count,
              findings.count == requested.count else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        for finding in findings {
            guard let findingID = UUID(uuidString: finding.findingID),
                  let links = requested[findingID], let link = links.first,
                  finding.revision == link.findingRevision,
                  try WorkspaceMutationCanonicalV1.sha256(finding) == link.findingSHA256 else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        }
    }

    private func resolveActivitySupportingRecords(
        _ links: [PunchFindingLinkV1],
        receiptHistory: [(envelope: MutationEnvelopeV1, receipt: MutationReceiptV1)],
        workspaceID: WorkspaceID
    ) throws -> [ActivitySupportingRecordReferenceV2] {
        var resolved = Set<ActivitySupportingRecordReferenceV2>()
        for link in links {
            for reference in link.supportingRecords {
                switch reference.kind {
                case .correctiveAction:
                    let recordID = reference.recordID
                    let rows = try modelContext.fetch(FetchDescriptor<CorrectiveActionEventRow>(
                        predicate: #Predicate { $0.eventID == recordID }
                    ))
                    guard rows.count == 1, let event = try rows.first?.value(),
                          event.workspaceID == workspaceID,
                          event.revision == reference.revision,
                          event.eventSHA256 == reference.recordSHA256,
                          event.source.kind == .finding,
                          event.source.itemID.lowercased() == link.findingID.uuidString.lowercased(),
                          event.source.itemRevision == UInt64(link.findingRevision),
                          event.source.itemSHA256 == link.findingSHA256 else {
                        throw WorkspaceMutationFailureV1.invalidCommand
                    }
                case .operationalRecheck:
                    let recordID = reference.recordID
                    let rows = try modelContext.fetch(FetchDescriptor<WorkflowRecord>(
                        predicate: #Predicate { $0.id == recordID }
                    ))
                    guard rows.count == 1, let row = rows.first,
                          row.stage == WorkflowStage.recheck.rawValue,
                          row.issueID == link.findingID else {
                        throw WorkspaceMutationFailureV1.invalidCommand
                    }
                    let matches = receiptHistory.flatMap { $0.receipt.postImages }.filter { image in
                        guard case let .workflowRecord(id, revision, sha256) = image else { return false }
                        return id == reference.recordID && revision == reference.revision
                            && sha256 == reference.recordSHA256
                    }
                    guard matches.count == 1 else { throw WorkspaceMutationFailureV1.invalidCommand }
                }
                resolved.insert(reference)
            }
        }
        return resolved.sorted {
            ($0.kind.rawValue, $0.recordID.uuidString, $0.revision)
                < ($1.kind.rawValue, $1.recordID.uuidString, $1.revision)
        }
    }

    private func resolveCompletedActivitySnapshot(
        _ reference: CompletedActivitySnapshotV2CompatibilityReferenceV1
    ) throws -> CompletedActivitySnapshotResolutionContextV2 {
        if let completedActivitySnapshotResolver {
            return try completedActivitySnapshotResolver(reference)
        }
        let configurations = Array(modelContext.container.configurations)
        guard configurations.count == 1 else { throw WorkspaceMutationFailureV1.invalidCommand }
        let generationRootURL = configurations[0].url.deletingLastPathComponent()
        let rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
        let reports = try modelContext.fetch(FetchDescriptor<Report>()).filter {
            $0.snapshotSchemaVersion == CompletedActivitySnapshotV2.schemaVersion
        }
        var matches: [CompletedActivitySnapshotResolutionContextV2] = []
        for report in reports {
            let url = generationRootURL.appendingPathComponent(report.snapshotRelativePath)
            let data = try ReportPDFAnchoredFile.readRegularFile(
                at: url, within: generationRootURL, rootIdentity: rootIdentity
            )
            guard KernelCanonicalHashV1.sha256(data) == report.snapshotSHA256 else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            let snapshot = try CompletedActivitySnapshotCanonicalCodecV2.decode(data)
            if let context = try? CompletedActivitySnapshotResolutionContextV2(
                reference: reference, snapshot: snapshot
            ) {
                matches.append(context)
            }
        }
        guard matches.count == 1, let value = matches.first else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        return value
    }

    private func applyOperationalContact(
        _ mutation: OperationalContactMutationV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        do {
            try mutation.validate()
            let workspace = mutation.workspaceID.rawValue
            let allRows = try modelContext.fetch(FetchDescriptor<ServiceContactPointRow>(
                predicate: #Predicate { $0.workspaceID == workspace }
            ))
            var current = try Dictionary(uniqueKeysWithValues: allRows.map {
                let value = try $0.value()
                return (value.contactPointID, (row: $0, value: value))
            })
            let predecessors = Dictionary(uniqueKeysWithValues: mutation.predecessors.map {
                ($0.contactPointID, $0)
            })

            for predecessor in mutation.predecessors {
                guard current[predecessor.contactPointID]?.value == predecessor else {
                    throw WorkspaceMutationFailureV1.staleEntityRevision(
                        try WorkspaceEntityIdentityV1(kind: .serviceContactPoint, id: predecessor.contactPointID)
                    )
                }
            }
            for successor in mutation.successors {
                let partyID = successor.party.partyID
                let parties = try modelContext.fetch(FetchDescriptor<ServicePartyRow>(
                    predicate: #Predicate { $0.partyID == partyID }
                ))
                guard parties.count == 1,
                      let storedParty = try parties.first?.value(),
                      storedParty == successor.party,
                      storedParty.workspaceID == mutation.workspaceID,
                      storedParty.state == .effective else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                if let predecessor = predecessors[successor.contactPointID] {
                    guard let existing = current[successor.contactPointID],
                          existing.value == predecessor else {
                        throw WorkspaceMutationFailureV1.staleEntityRevision(
                            try WorkspaceEntityIdentityV1(kind: .serviceContactPoint, id: successor.contactPointID)
                        )
                    }
                    try existing.row.replace(with: successor, expectedRevision: predecessor.revision)
                    current[successor.contactPointID] = (existing.row, successor)
                } else {
                    guard current[successor.contactPointID] == nil else {
                        throw WorkspaceMutationFailureV1.sequenceCollision
                    }
                    let row = try ServiceContactPointRow(successor)
                    modelContext.insert(row)
                    current[successor.contactPointID] = (row, successor)
                }
            }

            let touchedPreferredScopeKeys = Set(
                (mutation.predecessors + mutation.successors).map {
                    "\($0.party.partyID.uuidString):\($0.kind.rawValue)"
                }
            )
            let declaredPreferredScopeKeys = Set(mutation.preferredScopes.map {
                "\($0.partyID.uuidString):\($0.kind.rawValue)"
            })
            guard touchedPreferredScopeKeys == declaredPreferredScopeKeys else {
                throw OperationalContactFailureV1.preferredConflict
            }
            for scope in mutation.preferredScopes {
                let effective = current.values.map(\.value).filter {
                    $0.party.partyID == scope.partyID && $0.kind == scope.kind && $0.lifecycle == .effective
                }
                let activeIDs = effective.map(\.contactPointID).sorted { $0.uuidString < $1.uuidString }
                let preferredIDs = effective.filter(\.preferred).map(\.contactPointID)
                guard activeIDs == scope.activeContactPointIDs,
                      preferredIDs.count <= 1,
                      preferredIDs.first == scope.preferredContactPointID else {
                    throw OperationalContactFailureV1.preferredConflict
                }
            }

            for intent in mutation.handoffIntents {
                guard intent.disposition == .activeSourceWorkspace else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                let intentID = intent.intentID
                let existing = try modelContext.fetch(FetchDescriptor<SystemHandoffIntentRow>(
                    predicate: #Predicate { $0.workspaceID == workspace && $0.intentID == intentID }
                ))
                guard existing.isEmpty else { throw WorkspaceMutationFailureV1.sequenceCollision }
                switch intent.target.kind {
                case .serviceContactPoint:
                    guard let target = current[intent.target.targetID]?.value,
                          target.lifecycle == .effective,
                          target.workspaceID == mutation.workspaceID,
                          target.revision == intent.target.expectedRevision,
                          target.contactPointSHA256 == intent.target.expectedSHA256 else {
                        throw WorkspaceMutationFailureV1.invalidCommand
                    }
                case .site:
                    try requireCurrentOperationalContactSiteTarget(intent.target)
                }
                modelContext.insert(try SystemHandoffIntentRow(intent))
            }
            return try WorkspaceMutationEffectV1(
                affectedEntities: mutation.affectedIdentities,
                temporaryRelativePath: temporaryRelativePath
            )
        } catch let failure as WorkspaceMutationFailureV1 {
            modelContext.rollback()
            throw failure
        } catch {
            modelContext.rollback()
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    private func requireCurrentOperationalContactSiteTarget(
        _ target: SystemHandoffTargetReferenceV1
    ) throws {
        let siteID = target.targetID
        let sites = try modelContext.fetch(FetchDescriptor<Site>(
            predicate: #Predicate { $0.id == siteID }
        ))
        let identity = try WorkspaceEntityIdentityV1(kind: .site, id: siteID)
        let key = identity.stableKey
        let revisions = try modelContext.fetch(FetchDescriptor<EntityMutationRevisionRow>(
            predicate: #Predicate { $0.stableIdentity == key }
        ))
        guard sites.count == 1, let site = sites.first,
              revisions.count == 1, let revisionRow = revisions.first,
              revisionRow.revision > 0,
              UInt64(revisionRow.revision) == target.expectedRevision else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let value = V4BackupSiteDTO(
            id: site.id, schemaVersion: site.schemaVersion, label: site.label,
            address: site.address, timeZoneID: site.timeZoneID,
            createdAt: site.createdAt, updatedAt: site.updatedAt
        )
        let digest = try WorkspaceMutationCanonicalV1.sha256(
            OperationalContactAdapterSiteDigestBasisV1(
                identity: identity,
                revision: UInt64(revisionRow.revision),
                value: value
            )
        )
        guard digest == target.expectedSHA256 else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    private func applyAssetLabel(
        _ mutation: AssetLabelMutationV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        do {
            try mutation.validate()
            let snapshot = mutation.snapshot
            let workspace = snapshot.workspaceID.rawValue
            let snapshotID = snapshot.snapshotID
            let mutationID = snapshot.mutationID.rawValue
            guard try modelContext.fetch(FetchDescriptor<AcceptedLabelGenerationSnapshotRow>(
                predicate: #Predicate { $0.workspaceID == workspace && $0.snapshotID == snapshotID }
            )).isEmpty,
            try modelContext.fetch(FetchDescriptor<AcceptedLabelGenerationSnapshotRow>(
                predicate: #Predicate { $0.mutationID == mutationID }
            )).isEmpty else {
                throw WorkspaceMutationFailureV1.sequenceCollision
            }
            for item in snapshot.plan.items {
                let assetID = item.assetID
                let assets = try modelContext.fetch(FetchDescriptor<Asset>(
                    predicate: #Predicate { $0.id == assetID }
                ))
                let assetIdentity = try WorkspaceEntityIdentityV1(kind: .asset, id: assetID)
                let assetRevisionKey = assetIdentity.stableKey
                let assetRevisions = try modelContext.fetch(
                    FetchDescriptor<EntityMutationRevisionRow>(
                        predicate: #Predicate { $0.stableIdentity == assetRevisionKey }
                    )
                )
                guard assets.count == 1, assetRevisions.count == 1,
                      let storedAssetRevision = assetRevisions.first?.revision,
                      storedAssetRevision > 0,
                      UInt64(storedAssetRevision) == item.assetRevision else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                let locatorID = item.locator.locatorID
                let locatorRows = try modelContext.fetch(FetchDescriptor<AssetLocatorRow>(
                    predicate: #Predicate { $0.locatorID == locatorID }
                ))
                let receiptID = item.bindingReceiptID
                let receiptRows = try modelContext.fetch(FetchDescriptor<LocatorBindingReceiptRow>(
                    predicate: #Predicate { $0.receiptID == receiptID }
                ))
                guard locatorRows.count == 1, let locator = try locatorRows.first?.value(),
                      locator.workspaceID == snapshot.workspaceID,
                      locator.assetID == item.assetID,
                      try locator.reference == item.locator,
                      locator.state == item.locatorState,
                      receiptRows.count == 1, let receipt = try receiptRows.first?.value(),
                      receipt.workspaceID == snapshot.workspaceID,
                      receipt.after == item.locator,
                      receipt.revision == item.bindingReceiptRevision,
                      receipt.receiptSHA256 == item.bindingReceiptSHA256 else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            }
            modelContext.insert(try AcceptedLabelGenerationSnapshotRow(snapshot))
            return try WorkspaceMutationEffectV1(
                affectedEntities: [mutation.affectedIdentity],
                temporaryRelativePath: temporaryRelativePath
            )
        } catch let failure as WorkspaceMutationFailureV1 {
            modelContext.rollback()
            throw failure
        } catch {
            modelContext.rollback()
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    private func applyTemporalEvidence(
        _ mutation: TemporalEvidenceMutationV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        do {
            try mutation.validate()
            switch mutation.payload {
            case let .acceptClip(value, review, predecessor):
                try validateTemporalEvidenceAuthority(value)
                try review.validate()
                guard review.workspaceID == value.workspaceID,
                      review.clipID == value.clipID,
                      review.decision == .accept,
                      review.reviewedAt == value.acceptedAt else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                let id = value.clipID
                let rows = try modelContext.fetch(FetchDescriptor<TemporalEvidenceClipRow>(
                    predicate: #Predicate { $0.clipID == id }
                ))
                guard rows.isEmpty else { throw WorkspaceMutationFailureV1.sequenceCollision }
                if let predecessor {
                    let predecessorID = predecessor.clipID
                    let predecessorRows = try modelContext.fetch(FetchDescriptor<TemporalEvidenceClipRow>(
                        predicate: #Predicate { $0.clipID == predecessorID }
                    ))
                    let all = try modelContext.fetch(FetchDescriptor<TemporalEvidenceClipRow>())
                        .map { try $0.value() }
                    guard predecessorRows.count == 1,
                          try predecessorRows.first?.value() == predecessor,
                          all.allSatisfy({ $0.supersedesClipID != predecessorID }) else {
                        throw WorkspaceMutationFailureV1.staleEntityRevision(
                            try .init(kind: .temporalEvidenceClip, id: predecessorID)
                        )
                    }
                }
                modelContext.insert(try TemporalEvidenceClipRow(value))
            case let .registerDerivative(value, derivative, predecessor, predecessorDerivative):
                try validateTemporalEvidenceAuthority(predecessor)
                try derivative.validate(clip: predecessor)
                if let predecessorDerivative { try predecessorDerivative.validate(clip: predecessor) }
                try appendTemporalEvidenceClipSuccessor(value, predecessor: predecessor)
            case let .applyRetention(value, event, predecessor, predecessorEvent):
                try validateTemporalEvidenceAuthority(predecessor)
                try event.validate(clip: predecessor)
                if let predecessorEvent { try predecessorEvent.validate(clip: predecessor) }
                try appendTemporalEvidenceClipSuccessor(value, predecessor: predecessor)
            case let .removeClip(event, clips, anchors, derivatives, predecessorEvent):
                try clips.forEach(validateTemporalEvidenceAuthority)
                guard let predecessor = clips.first(where: {
                    $0.clipID == event.clipID && $0.revision == event.clipRevision
                        && $0.clipSHA256 == event.clipSHA256
                }) else { throw WorkspaceMutationFailureV1.invalidCommand }
                try event.validate(clip: predecessor)
                if let predecessorEvent { try predecessorEvent.validate(clip: predecessor) }
                let persistedClipRows = try modelContext.fetch(FetchDescriptor<TemporalEvidenceClipRow>())
                let persistedClips = try persistedClipRows.map { try $0.value() }
                let removalContentIDs = Set(clips.map { $0.original.contentID })
                let storedRemovalClips = persistedClips.filter {
                    removalContentIDs.contains($0.original.contentID)
                }
                let persistedAnchorRows = try modelContext.fetch(FetchDescriptor<TimecodedEvidenceAnchorRow>())
                let persistedAnchors = try persistedAnchorRows.map { try $0.value() }
                let clipIDs = Set(clips.map(\.clipID))
                let storedRemovalAnchors = persistedAnchors.filter { clipIDs.contains($0.clipID) }
                guard Set(storedRemovalClips.map(\.clipID)) == Set(clips.map(\.clipID)),
                      Set(storedRemovalAnchors.map(\.anchorID)) == Set(anchors.map(\.anchorID)),
                      storedRemovalClips.allSatisfy({ clips.contains($0) }),
                      storedRemovalAnchors.allSatisfy({ anchors.contains($0) }),
                      Set(clips.flatMap { $0.derivativeReferences.map(\.derivativeID) })
                        == Set(derivatives.map(\.derivativeID)) else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                for row in persistedAnchorRows where anchors.contains(where: { $0.anchorID == row.anchorID }) {
                    modelContext.delete(row)
                }
                for row in persistedClipRows where clips.contains(where: { $0.clipID == row.clipID }) {
                    modelContext.delete(row)
                }
            case let .appendAnchor(value, clip, predecessor):
                try validateTemporalEvidenceAuthority(clip)
                let clipID = clip.clipID
                let clipRows = try modelContext.fetch(FetchDescriptor<TemporalEvidenceClipRow>(
                    predicate: #Predicate { $0.clipID == clipID }
                ))
                guard clipRows.count == 1, try clipRows.first?.value() == clip else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                let anchorID = value.anchorID
                guard try modelContext.fetch(FetchDescriptor<TimecodedEvidenceAnchorRow>(
                    predicate: #Predicate { $0.anchorID == anchorID }
                )).isEmpty else { throw WorkspaceMutationFailureV1.sequenceCollision }
                if let predecessor {
                    let predecessorID = predecessor.anchorID
                    let predecessorRows = try modelContext.fetch(FetchDescriptor<TimecodedEvidenceAnchorRow>(
                        predicate: #Predicate { $0.anchorID == predecessorID }
                    ))
                    let all = try modelContext.fetch(FetchDescriptor<TimecodedEvidenceAnchorRow>())
                        .map { try $0.value() }
                    guard predecessorRows.count == 1,
                          try predecessorRows.first?.value() == predecessor,
                          all.allSatisfy({ $0.supersedesAnchorID != predecessorID }) else {
                        throw WorkspaceMutationFailureV1.staleEntityRevision(
                            try .init(kind: .timecodedEvidenceAnchor, id: predecessorID)
                        )
                    }
                }
                modelContext.insert(try TimecodedEvidenceAnchorRow(value))
            }
            return try WorkspaceMutationEffectV1(
                affectedEntities: mutation.affectedIdentities,
                temporaryRelativePath: temporaryRelativePath
            )
        } catch let failure as WorkspaceMutationFailureV1 {
            modelContext.rollback()
            throw failure
        } catch {
            modelContext.rollback()
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    private func validateTemporalEvidenceAuthority(_ clip: TemporalEvidenceClipV1) throws {
        try clip.validateIntrinsic()
        let sessionID = clip.target.sessionID
        let sessions = try modelContext.fetch(FetchDescriptor<SurveySessionRow>(
            predicate: #Predicate { $0.sessionID == sessionID }
        ))
        guard sessions.count == 1, let session = try sessions.first?.value(),
              session.workspaceID == clip.workspaceID,
              session.revision == clip.target.sessionRevision,
              session.sessionSHA256 == clip.target.sessionSHA256 else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let releaseID = clip.target.definitionRelease.releaseID
        let definitions = try modelContext.fetch(FetchDescriptor<SurveyDefinitionReleaseRow>(
            predicate: #Predicate { $0.releaseID == releaseID }
        ))
        guard definitions.count == 1, let definition = try definitions.first?.value(),
              definition.workspaceID == clip.workspaceID,
              try SurveyDefinitionReleaseReferenceV1(definition) == clip.target.definitionRelease,
              definition.sections.flatMap(\.facts).contains(where: { $0.factID == clip.target.factID }) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let promotedRows = try modelContext.fetch(FetchDescriptor<PromotedPackageReleaseRow>())
        let promoted = try promotedRows.map { try $0.value() }.filter {
            $0.workspaceID == clip.workspaceID
                && $0.packageRelease.packageReleaseID == clip.limitProfile.packageRelease.packageReleaseID
        }
        guard promoted.count == 1, let promotedRelease = promoted.first,
              try SurveyPackageReleaseReferenceV1(promotedRelease.packageRelease)
                == clip.limitProfile.packageRelease,
              session.authority.packageRelease == clip.limitProfile.packageRelease,
              session.authority.definitionRelease == clip.limitProfile.definitionRelease,
              clip.limitProfile.definitionRelease == clip.target.definitionRelease else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let pointerRows = try modelContext.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>())
        let pointers = try pointerRows.map { try $0.value() }
        let active = pointers.filter { pointer in
            pointer.workspaceID == clip.workspaceID
                && pointer.activeReleaseRecordID == promotedRelease.releaseRecordID
                && pointer.activePackageReleaseID == promotedRelease.packageRelease.packageReleaseID
                && !pointers.contains(where: { $0.supersedesPointerID == pointer.pointerID })
        }
        guard active.count == 1 else { throw WorkspaceMutationFailureV1.invalidCommand }
    }

    private func appendTemporalEvidenceClipSuccessor(
        _ value: TemporalEvidenceClipV1,
        predecessor: TemporalEvidenceClipV1
    ) throws {
        let id = value.clipID
        guard try modelContext.fetch(FetchDescriptor<TemporalEvidenceClipRow>(
            predicate: #Predicate { $0.clipID == id }
        )).isEmpty else { throw WorkspaceMutationFailureV1.sequenceCollision }
        let predecessorID = predecessor.clipID
        let predecessorRows = try modelContext.fetch(FetchDescriptor<TemporalEvidenceClipRow>(
            predicate: #Predicate { $0.clipID == predecessorID }
        ))
        let all = try modelContext.fetch(FetchDescriptor<TemporalEvidenceClipRow>()).map { try $0.value() }
        guard predecessorRows.count == 1,
              try predecessorRows.first?.value() == predecessor,
              all.allSatisfy({ $0.supersedesClipID != predecessorID }) else {
            throw WorkspaceMutationFailureV1.staleEntityRevision(
                try .init(kind: .temporalEvidenceClip, id: predecessorID)
            )
        }
        modelContext.insert(try TemporalEvidenceClipRow(value))
    }

    private func applyFieldReference(_ mutation:FieldReferenceMutationV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{do{try mutation.validate();let affected=try mutation.affectedIdentity,concurrency=try mutation.concurrencyIdentity;guard try fieldReferenceValue(affected)==nil else{throw WorkspaceMutationFailureV1.sequenceCollision};if mutation.expectedRevision>0{guard let prior=try fieldReferenceValue(concurrency),try !fieldReferenceSuccessorExists(concurrency)else{throw WorkspaceMutationFailureV1.staleEntityRevision(concurrency)};switch(mutation,prior){case let (.importRelease(v),.release(p)):try v.validateSuccessor(of:p);case let (.bind(v,r),.binding(p)):try v.validateSuccessor(of:p,release:r);default:throw WorkspaceMutationFailureV1.invalidCommand}};switch mutation{case let .importRelease(v):modelContext.insert(try FieldReferenceReleaseRow(v));case let .bind(v,r):let id=r.releaseID,rows=try modelContext.fetch(FetchDescriptor<FieldReferenceReleaseRow>(predicate:#Predicate{$0.releaseID==id}));guard rows.count==1,let stored=try rows.first?.value(),stored==r else{throw WorkspaceMutationFailureV1.invalidCommand};let releaseIdentity=try WorkspaceEntityIdentityV1(kind:.fieldReferenceRelease,id:id);guard try !fieldReferenceSuccessorExists(releaseIdentity)else{throw WorkspaceMutationFailureV1.staleEntityRevision(releaseIdentity)};modelContext.insert(try FieldReferenceBindingRow(v,release:r))};return try WorkspaceMutationEffectV1(affectedEntities:[affected],temporaryRelativePath:temporaryRelativePath)}catch let f as WorkspaceMutationFailureV1{modelContext.rollback();throw f}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}}
    private func applyAccessibleDocumentAssessment(_ mutation:AccessibleDocumentMutationV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{do{try mutation.validate();try validateAccessibleDocumentExternalProof(mutation.receipt);let affected=try mutation.affectedIdentity,concurrency=try mutation.concurrencyIdentity,id=mutation.receipt.receiptID;let existing=try modelContext.fetch(FetchDescriptor<AccessibleDocumentAssessmentReceiptRow>(predicate:#Predicate{$0.receiptID==id}));guard existing.isEmpty else{throw WorkspaceMutationFailureV1.sequenceCollision};if mutation.expectedRevision>0{let predecessorID=concurrency.id,rows=try modelContext.fetch(FetchDescriptor<AccessibleDocumentAssessmentReceiptRow>(predicate:#Predicate{$0.receiptID==predecessorID}));guard rows.count==1,let prior=try rows.first?.value()else{throw WorkspaceMutationFailureV1.staleEntityRevision(concurrency)};let all=try modelContext.fetch(FetchDescriptor<AccessibleDocumentAssessmentReceiptRow>()),count=try all.map{$0.value()}.filter{$0.supersedesReceiptID==predecessorID}.count;guard count==0 else{if count>1{throw WorkspaceMutationFailureV1.persistenceFailed};throw WorkspaceMutationFailureV1.staleEntityRevision(concurrency)};let value=mutation.receipt;let scopeIsValid=value.scope==prior.scope||(prior.scope == .historicSource && value.scope == .currentOutput);guard value.receiptID != prior.receiptID,value.supersedesReceiptID==prior.receiptID,value.workspaceID==prior.workspaceID,value.treeSHA256==prior.treeSHA256,value.snapshotSHA256==prior.snapshotSHA256,value.audience==prior.audience,value.projectionVersion==prior.projectionVersion,value.manifestID==prior.manifestID,value.manifestVersion==prior.manifestVersion,value.manifestSHA256==prior.manifestSHA256,value.outputSHA256==prior.outputSHA256,value.outputByteCount==prior.outputByteCount,value.outputMediaType==prior.outputMediaType,value.localeIdentifier==prior.localeIdentifier,value.profileID==prior.profileID,value.profileRelease==prior.profileRelease,value.profileSHA256==prior.profileSHA256,value.brandProfileID==prior.brandProfileID,value.brandProfileRelease==prior.brandProfileRelease,value.brandProfileSHA256==prior.brandProfileSHA256,value.rendererID==prior.rendererID,value.rendererVersion==prior.rendererVersion,value.assessmentToolID==prior.assessmentToolID,value.assessmentToolVersion==prior.assessmentToolVersion,scopeIsValid,value.mutationID != prior.mutationID,prior.revision<UInt64.max,value.revision==prior.revision+1 else{throw WorkspaceMutationFailureV1.invalidCommand}};modelContext.insert(try AccessibleDocumentAssessmentReceiptRow(mutation.receipt));return try WorkspaceMutationEffectV1(affectedEntities:[affected],temporaryRelativePath:temporaryRelativePath)}catch let f as WorkspaceMutationFailureV1{modelContext.rollback();throw f}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}}
    private func applySurveyDefinition(_ mutation:SurveyDefinitionMutationV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{do{try mutation.validate();try requireExactActor(mutation.event.actor);try requireExactActor(mutation.identity.createdBy);try requireExactActor(mutation.release.authoredBy);let definitionID=mutation.identity.definitionID,releaseID=mutation.release.releaseID;let identities=try modelContext.fetch(FetchDescriptor<SurveyDefinitionIdentityRow>(predicate:#Predicate{$0.definitionID==definitionID}));guard identities.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};let releaseRows=try modelContext.fetch(FetchDescriptor<SurveyDefinitionReleaseRow>(predicate:#Predicate{$0.releaseID==releaseID}));if mutation.appendsRelease{guard releaseRows.isEmpty else{throw WorkspaceMutationFailureV1.sequenceCollision}}else{guard releaseRows.count==1,let stored=try releaseRows.first?.value(),stored==mutation.release else{throw WorkspaceMutationFailureV1.invalidCommand}};if mutation.expectedRevision==0{guard mutation.appendsRelease,identities.isEmpty,mutation.release.supersedesReleaseID==nil,mutation.event.predecessorEventID==nil,mutation.identity.revision==1 else{throw WorkspaceMutationFailureV1.sequenceCollision};modelContext.insert(try SurveyDefinitionReleaseRow(mutation.release));modelContext.insert(try SurveyDefinitionIdentityRow(mutation.identity))}else{guard identities.count==1,let row=identities.first else{throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind:.surveyDefinitionIdentity,id:definitionID))};let prior=try row.value(),prior.revision==mutation.expectedRevision,prior.workspaceID==mutation.workspaceID,prior.revision<UInt64.max,mutation.identity.revision==prior.revision+1,mutation.event.predecessorEventID==prior.latestLifecycleEventID,mutation.event.predecessorEventSHA256==prior.latestLifecycleEventSHA256 else{throw WorkspaceMutationFailureV1.invalidCommand};let priorReleaseID=prior.currentRelease.releaseID,priorRows=try modelContext.fetch(FetchDescriptor<SurveyDefinitionReleaseRow>(predicate:#Predicate{$0.releaseID==priorReleaseID}));guard priorRows.count==1,let priorRelease=try priorRows.first?.value()else{throw WorkspaceMutationFailureV1.persistenceFailed};if mutation.appendsRelease{guard mutation.release.supersedesReleaseID==priorReleaseID else{throw WorkspaceMutationFailureV1.invalidCommand};let all=try modelContext.fetch(FetchDescriptor<SurveyDefinitionReleaseRow>()),successorCount=try all.map{$0.value()}.filter{$0.supersedesReleaseID==priorReleaseID}.count;guard successorCount==0 else{if successorCount>1{throw WorkspaceMutationFailureV1.persistenceFailed};throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind:.surveyDefinitionRelease,id:priorReleaseID))};try mutation.release.validateSuccessor(of:priorRelease);modelContext.insert(try SurveyDefinitionReleaseRow(mutation.release))}else{guard mutation.release==priorRelease else{throw WorkspaceMutationFailureV1.invalidCommand}};try mutation.identity.validateSuccessor(of:prior,event:mutation.event,release:mutation.release);try row.replace(with:mutation.identity,currentRelease:mutation.release,event:mutation.event,expectedRevision:mutation.expectedRevision)};return try WorkspaceMutationEffectV1(affectedEntities:mutation.affectedIdentities,temporaryRelativePath:temporaryRelativePath)}catch let f as WorkspaceMutationFailureV1{modelContext.rollback();throw f}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}}
    private func applySurveySession(_ mutation:SurveySessionMutationV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{do{try mutation.validate();switch mutation.payload{
        case let .applySession(v,d,publication):try validateSurveyPackageRelease(session:v,definition:d);let id=v.sessionID,rows=try modelContext.fetch(FetchDescriptor<SurveySessionRow>(predicate:#Predicate{$0.sessionID==id}));if v.revision==1{guard rows.isEmpty else{throw WorkspaceMutationFailureV1.sequenceCollision};modelContext.insert(try SurveySessionRow(v))}else{guard rows.count==1,let row=rows.first else{throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind:.surveySession,id:id))};try row.replace(with:v,publication:publication,expectedRevision:v.revision-1)}
        case let .captureFact(v,s,d,prior):try validateSurveyPackageRelease(session:s,definition:d);let sessionID=s.sessionID,sessionRows=try modelContext.fetch(FetchDescriptor<SurveySessionRow>(predicate:#Predicate{$0.sessionID==sessionID}));guard sessionRows.count==1,let storedSession=try sessionRows.first?.value(),storedSession==s,(s.state == .draft || s.state == .amended)else{throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind:.surveySession,id:sessionID))};let id=v.captureID,rows=try modelContext.fetch(FetchDescriptor<FactCaptureRow>(predicate:#Predicate{$0.captureID==id}));guard rows.isEmpty else{throw WorkspaceMutationFailureV1.sequenceCollision};let all=try modelContext.fetch(FetchDescriptor<FactCaptureRow>()).map{try $0.value()};for predecessor in prior{guard all.filter({$0.captureID==predecessor.captureID}).count==1,all.first(where:{$0.captureID==predecessor.captureID})==predecessor,all.filter({$0.predecessors.contains(where:{$0.captureID==predecessor.captureID})}).isEmpty else{throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind:.factCapture,id:predecessor.captureID))}};modelContext.insert(try FactCaptureRow(v))
        case let .applyProvisionalSubject(v):let id=v.provisionalSubjectID,rows=try modelContext.fetch(FetchDescriptor<ProvisionalSubjectRow>(predicate:#Predicate{$0.provisionalSubjectID==id}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};if v.revision==1{guard v.state == .active,rows.isEmpty else{throw WorkspaceMutationFailureV1.sequenceCollision};modelContext.insert(try ProvisionalSubjectRow(v))}else{guard v.state == .active || v.state == .archived,let row=rows.first else{throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind:.provisionalSubject,id:id))};try row.replaceOrdinary(with:v,expectedRevision:v.revision-1)}
        case let .promoteSubject(v,r,preview,predecessor):let sid=v.provisionalSubjectID,rid=r.receiptID,subjects=try modelContext.fetch(FetchDescriptor<ProvisionalSubjectRow>(predicate:#Predicate{$0.provisionalSubjectID==sid})),receipts=try modelContext.fetch(FetchDescriptor<SubjectPromotionReceiptRow>(predicate:#Predicate{$0.receiptID==rid}));guard subjects.count==1,let subjectRow=subjects.first,receipts.isEmpty else{throw WorkspaceMutationFailureV1.sequenceCollision};let storedSubject=try subjectRow.value(),expectedState:ProvisionalSubjectStateV1 = r.action == .promoteToAsset ? .promoted : (r.action == .reconcileAsAlias ? .reconciledAlias : .promotionReversed);guard storedSubject.revision<UInt64.max,v.revision==storedSubject.revision+1,v.supersedesSubjectSHA256==storedSubject.subjectSHA256,r.provisionalSubject==storedSubject.reference,v.state==expectedState else{throw WorkspaceMutationFailureV1.invalidCommand};if let predecessor{let predecessorID=predecessor.receiptID,priorRows=try modelContext.fetch(FetchDescriptor<SubjectPromotionReceiptRow>(predicate:#Predicate{$0.receiptID==predecessorID}));guard priorRows.count==1,try priorRows.first?.value()==predecessor else{throw WorkspaceMutationFailureV1.invalidCommand};let all=try modelContext.fetch(FetchDescriptor<SubjectPromotionReceiptRow>()).map{try $0.value()};guard all.filter({$0.predecessorReceiptID==predecessorID}).isEmpty else{throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind:.subjectPromotionReceipt,id:predecessorID))}};try r.validate(preview:preview,predecessor:predecessor);try subjectRow.replaceForPromotion(with:v,action:r.action,expectedRevision:storedSubject.revision);modelContext.insert(try SubjectPromotionReceiptRow(r))
        case let .publish(s,p,d,c):try validateSurveyPackageRelease(session:s,definition:d);try validateSurveyPublication(session:s,snapshot:p,definition:d,captures:c);let sid=s.sessionID,pid=p.snapshotID,sessions=try modelContext.fetch(FetchDescriptor<SurveySessionRow>(predicate:#Predicate{$0.sessionID==sid})),snapshots=try modelContext.fetch(FetchDescriptor<SurveyPublicationSnapshotRow>(predicate:#Predicate{$0.snapshotID==pid}));guard sessions.count==1,let row=sessions.first,snapshots.isEmpty else{throw WorkspaceMutationFailureV1.sequenceCollision};if let predecessorID=p.supersedesSnapshotID{let all=try modelContext.fetch(FetchDescriptor<SurveyPublicationSnapshotRow>()).map{try $0.value()},prior=all.filter{$0.snapshotID==predecessorID},successors=all.filter{$0.supersedesSnapshotID==predecessorID};guard prior.count==1,successors.isEmpty,prior[0].workspaceID==p.workspaceID,prior[0].sessionID==p.sessionID,prior[0].revision<UInt64.max,p.revision==prior[0].revision+1 else{throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind:.surveyPublicationSnapshot,id:predecessorID))}}else{guard p.revision==1 else{throw WorkspaceMutationFailureV1.invalidCommand}};try row.replace(with:s,publication:p,expectedRevision:s.revision-1);modelContext.insert(try SurveyPublicationSnapshotRow(p))};return try WorkspaceMutationEffectV1(affectedEntities:mutation.affectedIdentities,temporaryRelativePath:temporaryRelativePath)}catch let f as WorkspaceMutationFailureV1{modelContext.rollback();throw f}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}}
    private func validateSurveyPackageRelease(session:SurveySessionV1,definition:SurveyDefinitionReleaseV1)throws{let packageReleaseID=session.authority.packageRelease.packageReleaseID,rows=try modelContext.fetch(FetchDescriptor<PromotedPackageReleaseRow>()),matches=try rows.map{try $0.value().packageRelease}.filter{$0.packageReleaseID==packageReleaseID};guard matches.count==1,let release=matches.first else{throw WorkspaceMutationFailureV1.invalidCommand};try session.validate(definition:definition);try session.authority.validate(definition:definition,packageRelease:release)}
    private func validateSurveyPublication(session:SurveySessionV1,snapshot:SurveyPublicationSnapshotV1,definition:SurveyDefinitionReleaseV1,captures:[FactCaptureV1])throws{let allCaptures=try modelContext.fetch(FetchDescriptor<FactCaptureRow>()).map{try $0.value()}.filter{$0.workspaceID==session.workspaceID&&$0.sessionID==session.sessionID};_ = try SurveySessionLifecycleClosureV1(definition:definition,sessions:[session],captures:allCaptures,provisionalSubjects:[],promotionReceipts:[],publications:[]);let referenced=Set(allCaptures.flatMap{$0.predecessors.map(\.captureID)}),heads=allCaptures.filter{!referenced.contains($0.captureID)},suppliedIDs=captures.map(\.captureID);guard Set(suppliedIDs).count==suppliedIDs.count,Set(suppliedIDs)==Set(heads.map(\.captureID)),captures.allSatisfy({value in allCaptures.filter{$0.captureID==value.captureID}.count==1&&allCaptures.first(where:{$0.captureID==value.captureID})==value})else{throw WorkspaceMutationFailureV1.invalidCommand};let allReceipts=try modelContext.fetch(FetchDescriptor<SubjectPromotionReceiptRow>()).map{try $0.value()}.filter{$0.workspaceID==session.workspaceID};for receipt in allReceipts{let predecessor=receipt.predecessorReceiptID.flatMap{id in allReceipts.first{$0.receiptID==id}};try receipt.validate(preview:receipt.reconstructedPreview,predecessor:predecessor);if let predecessorID=receipt.predecessorReceiptID{guard allReceipts.filter({$0.receiptID==predecessorID}).count==1,allReceipts.filter({$0.predecessorReceiptID==predecessorID}).count==1 else{throw WorkspaceMutationFailureV1.invalidCommand}}};let supersededReceiptIDs=Set(allReceipts.compactMap(\.predecessorReceiptID)),receiptHeads=allReceipts.filter{$0.affectedSessionIDs.contains(session.sessionID)&&!supersededReceiptIDs.contains($0.receiptID)},embedded=snapshot.promotionReceiptsAtPublication,embeddedIDs=embedded.map(\.receiptID);guard Set(embeddedIDs).count==embeddedIDs.count,Set(embeddedIDs)==Set(receiptHeads.map(\.receiptID)),embedded.allSatisfy({value in allReceipts.filter{$0.receiptID==value.receiptID}.count==1&&allReceipts.first(where:{$0.receiptID==value.receiptID})==value})else{throw WorkspaceMutationFailureV1.invalidCommand};try snapshot.validate(session:session,definition:definition,captures:heads)}
    private func applyAssetLocator(_ mutation:AssetLocatorMutationV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{
        do{
            try mutation.validate()
            let allRows=try modelContext.fetch(FetchDescriptor<AssetLocatorRow>())
            let all=try allRows.map{$0.value()}
            let receiptRows=try modelContext.fetch(FetchDescriptor<LocatorBindingReceiptRow>())
            let receipts=try receiptRows.map{$0.value()}
            let mutationRows=try modelContext.fetch(FetchDescriptor<MutationReceiptRow>())
            func requireAsset(_ value:AssetLocatorV1)throws{let assetID=value.assetID,assets=try modelContext.fetch(FetchDescriptor<Asset>(predicate:#Predicate{$0.id==assetID}));guard assets.count==1 else{throw WorkspaceMutationFailureV1.invalidCommand}}
            func requireReceipt(_ expected:LocatorBindingReceiptV1?)throws{guard let expected else{return};let matches=receipts.filter{$0.receiptID==expected.receiptID};guard matches.count==1,matches[0]==expected,receipts.filter({$0.predecessorReceiptID==expected.receiptID}).isEmpty else{throw WorkspaceMutationFailureV1.invalidCommand}}
            func requireAvailable(_ value:AssetLocatorV1,excluding:UUID?=nil)throws{let matches=all.filter{$0.workspaceID==value.workspaceID&&$0.lookupKey==value.lookupKey&&$0.state == .active&&$0.locatorID != excluding};guard matches.isEmpty else{throw WorkspaceMutationFailureV1.sequenceCollision}}
            func requireManualShortCodeProof(
                target:AssetLocatorV1,
                receipt:LocatorBindingReceiptV1
            )throws{
                let reserved:Bool
                if case .externalKey(let key)=target.representation {
                    reserved=key.namespaceID==ManualShortCodeV1.externalKeyNamespace
                }else{reserved=false}
                if reserved {
                    let targetReference=try target.reference
                    let receiptTarget=receipt.action == .replace
                        ? receipt.replacement
                        : Optional(receipt.after)
                    guard let code=receipt.manualShortCodeIssuance,
                          target.representation == .externalKey(try code.externalKey()),
                          receipt.workspaceID==mutation.workspaceID,
                          receipt.mutationID==mutation.mutationID,
                          receiptTarget==targetReference else {
                        throw WorkspaceMutationFailureV1.invalidCommand
                    }
                }else if receipt.manualShortCodeIssuance != nil {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            }
            func historicalLocatorValues()throws->[AssetLocatorV1]{
                var values:[AssetLocatorV1]=[]
                for row in mutationRows {
                    let envelope=try MutationEnvelopeV1.decodeCanonical(from:row.envelopeData)
                    guard row.mutationID==envelope.mutationID.rawValue,
                          row.workspaceID==envelope.workspaceID.rawValue,
                          row.workspaceMutationKey==MutationWorkspaceKeyV1.value(
                            workspaceID:envelope.workspaceID,
                            mutationID:envelope.mutationID
                          ),
                          row.commandKind==envelope.commandKind.rawValue,
                          row.envelopeSHA256==(try envelope.canonicalSHA256()) else {
                        throw WorkspaceMutationFailureV1.persistenceFailed
                    }
                    guard case let .applyAssetLocator(historical)=envelope.command else{continue}
                    let generic=try MutationReceiptV1.decodeCanonical(from:row.receiptData)
                    try generic.validate()
                    guard row.receiptIdentity==generic.identity.stableKey,
                          row.replicaID==generic.identity.replicaID.rawValue,
                          row.localSequence>=0,
                          UInt64(row.localSequence)==generic.identity.localSequence,
                          row.receiptSHA256==(try generic.canonicalSHA256()) else {
                        throw WorkspaceMutationFailureV1.persistenceFailed
                    }
                    _=try AssetLocatorMutationReceiptV1(
                        mutation:historical,
                        mutationReceipt:generic
                    )
                    switch historical.payload {
                    case let .bind(value,_,_):values.append(value)
                    case let .transition(value,_,predecessor,_):values += [predecessor,value]
                    case let .replace(value,replacement,_,predecessor,_):
                        values += [predecessor,value,replacement]
                    }
                }
                return values
            }
            func requireUnusedManualShortCode(_ value:AssetLocatorV1)throws{
                guard case .externalKey(let key)=value.representation,
                      key.namespaceID==ManualShortCodeV1.externalKeyNamespace else{return}
                let currentCollision=all.contains{
                    $0.workspaceID==value.workspaceID&&$0.lookupKey==value.lookupKey
                }
                let historicalCollision=try historicalLocatorValues().contains{
                    $0.workspaceID==value.workspaceID&&$0.lookupKey==value.lookupKey
                }
                guard !currentCollision,!historicalCollision else{
                    throw WorkspaceMutationFailureV1.sequenceCollision
                }
            }
            switch mutation.payload{
            case let .bind(value,receipt,predecessorReceipt):try requireManualShortCodeProof(target:value,receipt:receipt);guard receipt.action == .bind,all.filter({$0.locatorID==value.locatorID}).isEmpty,receipts.filter({$0.receiptID==receipt.receiptID}).isEmpty else{throw WorkspaceMutationFailureV1.sequenceCollision};try requireAsset(value);try requireReceipt(predecessorReceipt);try requireAvailable(value);try requireUnusedManualShortCode(value);try requireExactActor(receipt.recordedBy);modelContext.insert(try AssetLocatorRow(value));modelContext.insert(try LocatorBindingReceiptRow(receipt))
            case let .transition(value,receipt,prior,predecessorReceipt):let id=prior.locatorID,rows=allRows.filter{$0.locatorID==id};guard rows.count==1,try rows[0].value()==prior,receipts.filter({$0.receiptID==receipt.receiptID}).isEmpty else{throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind:.assetLocator,id:id))};let isRebind=receipt.action == .rebind;if isRebind{try requireManualShortCodeProof(target:value,receipt:receipt)}else if receipt.manualShortCodeIssuance != nil{throw WorkspaceMutationFailureV1.invalidCommand};try requireAsset(value);try requireReceipt(predecessorReceipt);if value.state == .active{try requireAvailable(value,excluding:id)};if isRebind{try requireUnusedManualShortCode(value)};try requireExactActor(receipt.recordedBy);try rows[0].replace(with:value,expectedRevision:prior.revision);modelContext.insert(try LocatorBindingReceiptRow(receipt))
            case let .replace(value,replacement,receipt,prior,predecessorReceipt):let id=prior.locatorID,rows=allRows.filter{$0.locatorID==id};guard rows.count==1,try rows[0].value()==prior,all.filter({$0.locatorID==replacement.locatorID}).isEmpty,receipts.filter({$0.receiptID==receipt.receiptID}).isEmpty else{throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind:.assetLocator,id:id))};try requireManualShortCodeProof(target:replacement,receipt:receipt);try requireAsset(value);try requireAsset(replacement);try requireReceipt(predecessorReceipt);try requireAvailable(replacement,excluding:id);try requireUnusedManualShortCode(replacement);try requireExactActor(receipt.recordedBy);try rows[0].replace(with:value,expectedRevision:prior.revision);modelContext.insert(try AssetLocatorRow(replacement));modelContext.insert(try LocatorBindingReceiptRow(receipt))
            }
            return try WorkspaceMutationEffectV1(affectedEntities:mutation.affectedIdentities,temporaryRelativePath:temporaryRelativePath)
        }catch let failure as WorkspaceMutationFailureV1{modelContext.rollback();throw failure}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}
    }
    private func applySchedule(_ mutation: ScheduleMutationV1, temporaryRelativePath: String) throws -> WorkspaceMutationEffectV1 {
        do {
            try mutation.validate()
            let releaseRows = try modelContext.fetch(FetchDescriptor<ScheduleDefinitionReleaseRow>())
            let eventRows = try modelContext.fetch(FetchDescriptor<OccurrenceHistoryEventRow>())
            let calendarRows = try modelContext.fetch(FetchDescriptor<ExceptionCalendarReleaseRow>())
            let overrideRows = try modelContext.fetch(FetchDescriptor<ScheduleOverrideEventRow>())
            let releases = try releaseRows.map { try $0.value() }
            let events = try eventRows.map { try $0.value() }
            let calendars = try calendarRows.map { try $0.value() }
            let overrides = try overrideRows.map { try $0.value() }

            func requireRelease(_ value: ScheduleDefinitionReleaseV1) throws {
                let matches = releases.filter { $0.releaseID == value.releaseID }
                guard matches.count == 1, matches[0] == value else { throw WorkspaceMutationFailureV1.invalidCommand }
            }
            func requireCalendar(_ reference: ExceptionCalendarReleaseReferenceV1) throws {
                let matches = calendars.filter { $0.releaseID == reference.releaseID }
                guard matches.count == 1, matches[0].reference == reference else { throw WorkspaceMutationFailureV1.invalidCommand }
            }
            func validateAdvancedCalendarBinding(_ release: ScheduleDefinitionReleaseV1) throws {
                if case let .advanced(configuration) = release.recurrence {
                    try requireCalendar(configuration.calendarRelease)
                }
            }
            func requireWork(_ value: ScheduledWorkInstanceReferenceV1?) throws {
                guard let value else { return }
                switch value {
                case let .workPacket(reference):
                    let id = reference.manifestID
                    let rows = try modelContext.fetch(FetchDescriptor<WorkPacketManifestRow>(predicate: #Predicate { $0.manifestID == id }))
                    guard rows.count == 1, let stored = try rows.first?.value(), try WorkPacketManifestReferenceV1(stored) == reference else { throw WorkspaceMutationFailureV1.invalidCommand }
                case let .roundSession(sessionID, revision, digest):
                    let workspaceID = mutation.workspaceID.rawValue
                    let rows = try modelContext.fetch(FetchDescriptor<RoundSessionRevisionRowV1>(predicate: #Predicate { $0.workspaceID == workspaceID && $0.sessionID == sessionID && $0.revision == revision }))
                    guard rows.count == 1, let stored = try rows.first?.value(), stored.workspaceID == mutation.workspaceID, stored.revision == revision, stored.sessionSHA256 == digest else { throw WorkspaceMutationFailureV1.invalidCommand }
                }
            }
            func appendEvent(_ value: OccurrenceHistoryEventV1, _ predecessor: OccurrenceHistoryEventV1?, _ release: ScheduleDefinitionReleaseV1) throws {
                try requireRelease(release); try requireWork(value.workInstance)
                guard !events.contains(where: { $0.eventID == value.eventID }) else { throw WorkspaceMutationFailureV1.sequenceCollision }
                if let predecessor {
                    let matches = events.filter { $0.eventID == predecessor.eventID }
                    let successors = events.filter { $0.predecessorEventID == predecessor.eventID }
                    guard matches.count == 1, matches[0] == predecessor, successors.isEmpty else { throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind: .occurrenceHistoryEvent, id: predecessor.eventID)) }
                } else {
                    guard !events.contains(where: { $0.occurrenceID == value.occurrenceID }) else { throw WorkspaceMutationFailureV1.sequenceCollision }
                }
                try value.validate(predecessor: predecessor)
                modelContext.insert(try OccurrenceHistoryEventRow(value))
            }
            func sameNamespaceReleaseReferences(_ release: ScheduleDefinitionReleaseV1) throws -> Set<ScheduleDefinitionReleaseReferenceV1> {
                try requireRelease(release)
                let candidates = releases.filter {
                    $0.workspaceID == release.workspaceID
                        && $0.scheduleDefinitionID == release.scheduleDefinitionID
                        && $0.occurrenceIdentityNamespaceID == release.occurrenceIdentityNamespaceID
                }
                var references: Set<ScheduleDefinitionReleaseReferenceV1> = []
                var current = release
                while true {
                    guard candidates.contains(current) else {
                        throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
                    }
                    guard references.insert(try ScheduleDefinitionReleaseReferenceV1(current)).inserted else {
                        throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
                    }
                    guard let predecessorID = current.supersedesReleaseID else { break }
                    let predecessors = candidates.filter { $0.releaseID == predecessorID }
                    guard predecessors.count == 1 else {
                        throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
                    }
                    try current.validateSuccessor(of: predecessors[0])
                    current = predecessors[0]
                }
                return references
            }
            func overrideClosure(_ release: ScheduleDefinitionReleaseV1) throws -> [ScheduleOverrideEventV1] {
                let references = try sameNamespaceReleaseReferences(release)
                return overrides.filter { references.contains($0.scheduleRelease) }
            }
            func appendOverride(_ value: ScheduleOverrideEventV1, _ predecessor: ScheduleOverrideEventV1?, _ release: ScheduleDefinitionReleaseV1) throws {
                try requireRelease(release)
                try ScheduleOverridePrecedenceV1.validateExpectedFrontier(value, against: try overrideClosure(release))
                guard !overrides.contains(where: { $0.eventID == value.eventID }) else { throw WorkspaceMutationFailureV1.staleWorkspaceRevision }
                if let predecessor {
                    let matches = overrides.filter { $0.eventID == predecessor.eventID }
                    let successors = overrides.filter { $0.supersedesEventID == predecessor.eventID }
                    guard matches.count == 1, matches[0] == predecessor, successors.isEmpty else { throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind: .scheduleOverrideEvent, id: predecessor.eventID)) }
                    try value.validateSuccessor(of: predecessor)
                } else { try value.validate() }
                _ = try ScheduleOverridePrecedenceV1.activeEvents(overrides + [value])
                modelContext.insert(try ScheduleOverrideEventRow(value))
            }

            switch mutation.payload {
            case let .appendRelease(value, predecessor):
                guard !releases.contains(where: { $0.releaseID == value.releaseID }) else { throw WorkspaceMutationFailureV1.sequenceCollision }
                try validateAdvancedCalendarBinding(value)
                if let predecessor {
                    let matches = releases.filter { $0.releaseID == predecessor.releaseID }
                    let successors = releases.filter { $0.supersedesReleaseID == predecessor.releaseID }
                    guard matches.count == 1, matches[0] == predecessor, successors.isEmpty else { throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind: .scheduleDefinitionRelease, id: predecessor.releaseID)) }
                    try value.validateSuccessor(of: predecessor)
                }
                modelContext.insert(try ScheduleDefinitionReleaseRow(value))
            case let .appendExceptionCalendarRelease(value, predecessor):
                guard !calendars.contains(where: { $0.releaseID == value.releaseID }) else { throw WorkspaceMutationFailureV1.sequenceCollision }
                if let predecessor {
                    let matches = calendars.filter { $0.releaseID == predecessor.releaseID }
                    let successors = calendars.filter { $0.supersedesReleaseID == predecessor.releaseID }
                    guard matches.count == 1, matches[0] == predecessor, successors.isEmpty else { throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind: .exceptionCalendarRelease, id: predecessor.releaseID)) }
                    try value.validateSuccessor(of: predecessor)
                }
                modelContext.insert(try ExceptionCalendarReleaseRow(value))
            case let .appendOverrideEvent(value, predecessor, release):
                try appendOverride(value, predecessor, release)
            case let .appendOccurrenceEvent(value, predecessor, release), let .startOccurrence(value, predecessor, release):
                try appendEvent(value, predecessor, release)
            case let .generateOccurrences(release, plan, values):
                try requireRelease(release); try plan.validate(definition: release)
                let references = try sameNamespaceReleaseReferences(release)
                let existingIDs = Set(events.filter { references.contains($0.scheduleRelease) }.map(\.occurrenceID))
                guard existingIDs == Set(plan.existingOccurrenceIDs) else { throw WorkspaceMutationFailureV1.staleWorkspaceRevision }
                for value in values { try appendEvent(value, nil, release) }
            }
            return try WorkspaceMutationEffectV1(affectedEntities: mutation.affectedIdentities, temporaryRelativePath: temporaryRelativePath)
        } catch let failure as WorkspaceMutationFailureV1 {
            modelContext.rollback(); throw failure
        } catch {
            modelContext.rollback(); throw WorkspaceMutationFailureV1.invalidCommand
        }
    }
    private func applyPlan(_ mutation:PlanMutationV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{do{try mutation.validate();let documents=try modelContext.fetch(FetchDescriptor<PlanDocumentRow>()).map{try $0.value()},revisions=try modelContext.fetch(FetchDescriptor<PlanRevisionRow>()).map{try $0.value()},placements=try modelContext.fetch(FetchDescriptor<PlanPlacementRow>()).map{try $0.value()},receipts=try modelContext.fetch(FetchDescriptor<RebaseReceiptRow>()).map{try $0.value()};func noSuccessor<T>(_ all:[T],_ count:(T)->Bool)throws{let n=all.filter(count).count;guard n==0 else{throw n>1 ? WorkspaceMutationFailureV1.persistenceFailed:.staleWorkspaceRevision}};func requireRevisionReferences(_ value:PlanRevisionV1)throws{let releaseID=value.contentBinding.fieldReferenceReleaseID,releaseRows=try modelContext.fetch(FetchDescriptor<FieldReferenceReleaseRow>(predicate:#Predicate{$0.releaseID==releaseID}));guard releaseRows.count==1,let release=try releaseRows.first?.value(),release.workspaceID==value.workspaceID,release.revision==value.contentBinding.fieldReferenceReleaseRevision,release.releaseSHA256==value.contentBinding.fieldReferenceReleaseSHA256,release.manifestSHA256==value.contentBinding.fieldReferenceManifestSHA256 else{throw WorkspaceMutationFailureV1.invalidCommand};let documentMatches=documents.filter{$0.planDocumentID==value.planDocument.planDocumentID&&$0.revision==value.planDocument.revision&&$0.documentSHA256==value.planDocument.documentSHA256};guard documentMatches.count==1 else{throw WorkspaceMutationFailureV1.invalidCommand}};func requirePlacementReferences(_ value:PlanPlacementV1)throws{let revisionMatches=revisions.filter{$0.planRevisionID==value.planRevision.planRevisionID&&$0.revision==value.planRevision.revision&&$0.revisionSHA256==value.planRevision.revisionSHA256};guard revisionMatches.count==1 else{throw WorkspaceMutationFailureV1.invalidCommand};if let binding=value.assetLocatorBinding{let receiptID=binding.bindingReceiptID,rows=try modelContext.fetch(FetchDescriptor<LocatorBindingReceiptRow>(predicate:#Predicate{$0.receiptID==receiptID}));guard rows.count==1,let stored=try rows.first?.value(),stored.revision==binding.bindingReceiptRevision,stored.receiptSHA256==binding.bindingReceiptSHA256,stored.after==binding.locator,stored.after.assetID==binding.assetID else{throw WorkspaceMutationFailureV1.invalidCommand}}};switch mutation.payload{case let .appendDocument(value,predecessor):guard documents.filter({$0.mutationID==value.mutationID}).isEmpty else{throw WorkspaceMutationFailureV1.sequenceCollision};if let predecessor{guard documents.filter({$0.documentSHA256==predecessor.documentSHA256}).count==1 else{throw WorkspaceMutationFailureV1.invalidCommand};try noSuccessor(documents){$0.supersedesDocumentSHA256==predecessor.documentSHA256}};modelContext.insert(try PlanDocumentRow(value));case let .appendRevision(value,predecessor,_):try requireRevisionReferences(value);guard revisions.filter({$0.planRevisionID==value.planRevisionID}).isEmpty else{throw WorkspaceMutationFailureV1.sequenceCollision};if let predecessor{guard revisions.filter({$0.planRevisionID==predecessor.planRevisionID&&$0==predecessor}).count==1 else{throw WorkspaceMutationFailureV1.invalidCommand};try noSuccessor(revisions){$0.supersedesPlanRevisionID==predecessor.planRevisionID}};modelContext.insert(try PlanRevisionRow(value));case let .appendPlacement(value,predecessor,_):try requirePlacementReferences(value);if let predecessor{guard placements.filter({$0.placementSHA256==predecessor.placementSHA256}).count==1 else{throw WorkspaceMutationFailureV1.invalidCommand};try noSuccessor(placements){$0.supersedesPlacementSHA256==predecessor.placementSHA256}};modelContext.insert(try PlanPlacementRow(value));case let .applyRebase(newRevision,priorRevision,values,priors,receipt,predecessorReceipt,poseEffects):guard revisions.filter({$0.planRevisionID==priorRevision.planRevisionID&&$0==priorRevision}).count==1,revisions.filter({$0.planRevisionID==newRevision.planRevisionID}).isEmpty else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision};try noSuccessor(revisions){$0.supersedesPlanRevisionID==priorRevision.planRevisionID};try requireRevisionReferences(newRevision);for prior in priors{guard placements.filter({$0.placementSHA256==prior.placementSHA256}).count==1 else{throw WorkspaceMutationFailureV1.invalidCommand};try noSuccessor(placements){$0.supersedesPlacementSHA256==prior.placementSHA256}};for value in values{try requirePlacementReferencesAgainst(value,newRevision)};try requireReceiptPredecessor(predecessorReceipt,receipts);if let poseEffects{_ = try applyPlacementPose(poseEffects,temporaryRelativePath:temporaryRelativePath)};modelContext.insert(try PlanRevisionRow(newRevision));for value in values{modelContext.insert(try PlanPlacementRow(value))};modelContext.insert(try RebaseReceiptRow(receipt));case let .recordRebaseRejection(receipt,predecessorReceipt):try requireReceiptPredecessor(predecessorReceipt,receipts);modelContext.insert(try RebaseReceiptRow(receipt))};return try WorkspaceMutationEffectV1(affectedEntities:mutation.affectedIdentities,temporaryRelativePath:temporaryRelativePath)}catch let failure as WorkspaceMutationFailureV1{modelContext.rollback();throw failure}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}}

    private func applyEvidenceContext(_ operation:EvidenceContextWriteOperationV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{do{try operation.validate();switch operation{case let .appendContext(value,predecessor):let rows=try modelContext.fetch(FetchDescriptor<EvidenceContextRow>()).map{try $0.value()};guard rows.filter({$0.contextID==value.contextID}).isEmpty else{throw WorkspaceMutationFailureV1.sequenceCollision};if let predecessor{guard rows.filter({$0==predecessor}).count==1,rows.filter({$0.predecessorContextSHA256==predecessor.contextSHA256}).isEmpty else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision}}else{guard rows.filter({$0.workspaceID==value.workspaceID&&$0.evidenceID==value.evidenceID}).isEmpty else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision}};modelContext.insert(try EvidenceContextRow(value));case let .appendPair(value,predecessor):let rows=try modelContext.fetch(FetchDescriptor<PairedObservationLinkRow>()).map{try $0.value()};try validateEvidencePairPurpose(value,existing:rows);guard rows.filter({$0.linkID==value.linkID}).isEmpty else{throw WorkspaceMutationFailureV1.sequenceCollision};if let predecessor{guard rows.filter({$0==predecessor}).count==1,rows.filter({$0.predecessorLinkSHA256==predecessor.linkSHA256}).isEmpty else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision}}else{guard rows.filter({$0.workspaceID==value.workspaceID&&Set([$0.first.evidenceID,$0.second.evidenceID])==Set([value.first.evidenceID,value.second.evidenceID])}).isEmpty else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision}};modelContext.insert(try PairedObservationLinkRow(value))};return try WorkspaceMutationEffectV1(affectedEntities:[operation.affectedIdentity],temporaryRelativePath:temporaryRelativePath)}catch let failure as WorkspaceMutationFailureV1{modelContext.rollback();throw failure}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}}

    private func applyLighting(_ operation: LightingWriteOperationV1, temporaryRelativePath: String) throws -> WorkspaceMutationEffectV1 {
        do {
            try operation.validate()
            try LightingPersistedAdmissionV1.validate(operation, in: modelContext)
            func requireExact<T: Equatable>(_ value: T, in values: [T]) throws {
                guard values.filter({ $0 == value }).count == 1 else { throw WorkspaceMutationFailureV1.invalidCommand }
            }
            func oneSuccessor<T>(_ all: [T], _ matches: (T) -> Bool) throws {
                let count = all.filter(matches).count
                guard count == 0 else { throw count > 1 ? WorkspaceMutationFailureV1.persistenceFailed : .staleWorkspaceRevision }
            }
            func requirePackage(_ reference: LightingPackageReleaseReferenceV1) throws {
                let releases = try modelContext.fetch(FetchDescriptor<PromotedPackageReleaseRow>()).map { try $0.value().packageRelease }
                let matches = releases.filter { $0.packageReleaseID == reference.packageReleaseID }
                guard matches.count == 1, let release = matches.first else { throw WorkspaceMutationFailureV1.invalidCommand }
                try reference.validate(release)
            }
            func requireSystem(_ system: LightingSystemV1) throws {
                try requirePackage(system.packageRelease)
                try requireExact(system, in: try modelContext.fetch(FetchDescriptor<LightingSystemRow>()).map { try $0.value() })
            }
            func requireTopology(_ admission: LightingTopologyAdmissionClosureV1) throws {
                let descriptors = try modelContext.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>()).map { try $0.value() }
                let events = try modelContext.fetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>()).map { try $0.value() }
                for value in admission.descriptors { try requireExact(value, in: descriptors) }
                for value in admission.relationshipEvents { try requireExact(value, in: events) }
                let relationshipIDs = Set(admission.relationshipEvents.map(\.relationshipID))
                let persistedHistory = events.filter { relationshipIDs.contains($0.relationshipID) }
                guard persistedHistory.count == admission.relationshipEvents.count,
                      persistedHistory.allSatisfy({ admission.relationshipEvents.contains($0) }) else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            }
            func requireIssueAdmission(_ admission: LightingIssueAdmissionClosureV1) throws {
                try requireExact(admission.observation, in: try modelContext.fetch(FetchDescriptor<LightingObservationRow>()).map { try $0.value() })
            }
            func requireClaimAdmission(_ admission: LightingClaimAdmissionClosureV1) throws {
                func observation(_ value: LightingObservationV1) throws { try requireExact(value, in: try modelContext.fetch(FetchDescriptor<LightingObservationRow>()).map { try $0.value() }) }
                func plan(_ value: MeasurementPlanV1) throws { try requireExact(value, in: try modelContext.fetch(FetchDescriptor<MeasurementPlanRow>()).map { try $0.value() }) }
                func protocolRelease(_ value: MeasurementProtocolReleaseV1) throws { try requireExact(value, in: try modelContext.fetch(FetchDescriptor<MeasurementProtocolReleaseRow>()).map { try $0.value() }) }
                func captures(_ values: [MeasurementCaptureV1]) throws { let stored=try modelContext.fetch(FetchDescriptor<MeasurementCaptureRow>()).map{try $0.value()};for value in values{try requireExact(value,in:stored)} }
                func instrument(_ value: InstrumentReferenceV1) throws { try requireExact(value, in: try modelContext.fetch(FetchDescriptor<InstrumentReferenceRow>()).map { try $0.value() }) }
                func calibration(_ value: CalibrationStatusSnapshotV1) throws { try requireExact(value, in: try modelContext.fetch(FetchDescriptor<CalibrationStatusSnapshotRow>()).map { try $0.value() }) }
                func quality(_ values: [MeasurementQualityAssessmentV1]) throws { let stored=try modelContext.fetch(FetchDescriptor<MeasurementQualityAssessmentRow>()).map{try $0.value()};for value in values{try requireExact(value,in:stored)} }
                switch admission {
                case .observed(let o): try observation(o)
                case .measured(let o,let p,let protocolValue,let c,_,let i,let calibrationValue,let q): try observation(o);try plan(p);try protocolRelease(protocolValue);try captures(c);try instrument(i);try calibration(calibrationValue);try quality(q)
                case .derived(let o,let p,let protocolValue,let evaluator,let c,_,let i,let calibrationValue,let q): try observation(o);try plan(p);try protocolRelease(protocolValue);try requireExact(evaluator,in:try modelContext.fetch(FetchDescriptor<DerivedFactEvaluatorDescriptorRow>()).map{try $0.value()});try captures(c);try instrument(i);try calibration(calibrationValue);try quality(q)
                case .screened(let o,let p,let protocolValue,let c,_,let i,let calibrationValue,let q,let classification,_,let authority,let basis,let applicability,let scope): try observation(o);try plan(p);try protocolRelease(protocolValue);try captures(c);try instrument(i);try calibration(calibrationValue);try quality(q);try requireExact(classification,in:try modelContext.fetch(FetchDescriptor<FindingClassificationBindingRow>()).map{try $0.value()});try requireExact(authority,in:try modelContext.fetch(FetchDescriptor<AuthoritySourceReleaseRow>()).map{try $0.value()});try requireExact(basis,in:try modelContext.fetch(FetchDescriptor<RequirementBasisBindingRow>()).map{try $0.value()});try requireExact(applicability,in:try modelContext.fetch(FetchDescriptor<ApplicabilityContextSnapshotRow>()).map{try $0.value()});try requireExact(scope,in:try modelContext.fetch(FetchDescriptor<AssessmentScopeSnapshotRow>()).map{try $0.value()})
                case .externallyAttested(let o,let attestation): try observation(o);try requireExact(attestation,in:try modelContext.fetch(FetchDescriptor<AttestationRow>()).map{try $0.value()})
                }
            }
            switch operation {
            case let .appendSystem(value, predecessor, admission):
                try requirePackage(value.packageRelease); try requireTopology(admission)
                let all=try modelContext.fetch(FetchDescriptor<LightingSystemRow>()).map{try $0.value()};guard all.allSatisfy({$0.recordID != value.recordID})else{throw WorkspaceMutationFailureV1.sequenceCollision};if let predecessor{try requireExact(predecessor,in:all);try oneSuccessor(all){$0.supersedesRecordID==predecessor.recordID};try value.validateSuccessor(of:predecessor)};modelContext.insert(try LightingSystemRow(value))
            case let .appendObservation(value, predecessor, system):
                try requireSystem(system);let all=try modelContext.fetch(FetchDescriptor<LightingObservationRow>()).map{try $0.value()};guard all.allSatisfy({$0.recordID != value.recordID})else{throw WorkspaceMutationFailureV1.sequenceCollision};if let predecessor{try requireExact(predecessor,in:all);try oneSuccessor(all){$0.supersedesRecordID==predecessor.recordID}};try value.validate(system:system);modelContext.insert(try LightingObservationRow(value))
            case let .appendIssue(value, predecessor, admission):
                try requireIssueAdmission(admission);let all=try modelContext.fetch(FetchDescriptor<LightingIssueRow>()).map{try $0.value()};guard all.allSatisfy({$0.recordID != value.recordID})else{throw WorkspaceMutationFailureV1.sequenceCollision};if let predecessor{try requireExact(predecessor,in:all);try oneSuccessor(all){$0.supersedesRecordID==predecessor.recordID}};modelContext.insert(try LightingIssueRow(value))
            case let .appendMeasurementPlan(value, predecessor, system):
                try requireSystem(system);let all=try modelContext.fetch(FetchDescriptor<MeasurementPlanRow>()).map{try $0.value()};guard all.allSatisfy({$0.recordID != value.recordID})else{throw WorkspaceMutationFailureV1.sequenceCollision};if let predecessor{try requireExact(predecessor,in:all);try oneSuccessor(all){$0.supersedesRecordID==predecessor.recordID}};try value.validate(system:system);modelContext.insert(try MeasurementPlanRow(value))
            case let .appendClaim(value, predecessor, admission):
                try requireClaimAdmission(admission);let all=try modelContext.fetch(FetchDescriptor<LightingClaimStateRow>()).map{try $0.value()};guard all.allSatisfy({$0.recordID != value.recordID})else{throw WorkspaceMutationFailureV1.sequenceCollision};if let predecessor{try requireExact(predecessor,in:all);try oneSuccessor(all){$0.supersedesRecordID==predecessor.recordID}};modelContext.insert(try LightingClaimStateRow(value))
            }
            return try WorkspaceMutationEffectV1(affectedEntities:[operation.affectedIdentity],temporaryRelativePath:temporaryRelativePath)
        } catch let failure as WorkspaceMutationFailureV1 { modelContext.rollback();throw failure }
        catch { modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand }
    }

    private func validateEvidencePairPurpose(_ value:PairedObservationLinkV1,existing:[PairedObservationLinkV1])throws{for candidate in [value.first,value.second]{let historical=existing.filter{$0.workspaceID==value.workspaceID}.flatMap{[$0.first,$0.second]}.filter{$0.evidenceID==candidate.evidenceID};guard historical.allSatisfy({$0.purpose==candidate.purpose&&$0.purposeRevision==candidate.purposeRevision})else{throw WorkspaceMutationFailureV1.invalidCommand}}}

    private func applyPlacementPose(_ mutation:PlacementPoseMutationV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{do{try mutation.validate();try validatePlacementPoseAdmissionClosure(mutation.admissionClosure);let storedEvents=try modelContext.fetch(FetchDescriptor<AssetPoseEventRow>()).map{try $0.value()},storedObservations=try modelContext.fetch(FetchDescriptor<SpatialAnchorObservationRow>()).map{try $0.value()};for (value,predecessor) in zip(mutation.events,mutation.eventPredecessors){guard try modelContext.fetch(FetchDescriptor<Asset>(predicate:#Predicate{$0.id==value.assetID})).count==1 else{throw WorkspaceMutationFailureV1.invalidCommand};let placementID=value.placementEventID,placementRows=try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>(predicate:#Predicate{$0.id==placementID}));guard placementRows.count==1,let placement=try placementRows.first?.value(),placement.workspaceID==mutation.workspaceID,placement.assetID==value.assetID,placement.physicalEpisodeID==value.placementEpisodeID else{throw WorkspaceMutationFailureV1.invalidCommand};if let predecessor{guard storedEvents.filter({$0.eventID==predecessor.eventID&&$0==predecessor}).count==1,storedEvents.filter({$0.predecessor?.eventID==predecessor.eventID}).isEmpty else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision}}else{guard storedEvents.filter({$0.workspaceID==value.workspaceID&&$0.assetID==value.assetID&&$0.axisDescriptor.axisID==value.axisDescriptor.axisID&&$0.placementEpisodeID==value.placementEpisodeID}).isEmpty else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision}};modelContext.insert(try AssetPoseEventRow(value))};for (value,predecessor) in zip(mutation.observations,mutation.observationPredecessors){guard try modelContext.fetch(FetchDescriptor<Asset>(predicate:#Predicate{$0.id==value.assetID})).count==1 else{throw WorkspaceMutationFailureV1.invalidCommand};let revisionID=value.planFrame.planRevision.planRevisionID,revisionRows=try modelContext.fetch(FetchDescriptor<PlanRevisionRow>(predicate:#Predicate{$0.planRevisionID==revisionID}));guard revisionRows.count==1,let revision=try revisionRows.first?.value(),revision.workspaceID==value.workspaceID,revision.revision==value.planFrame.planRevision.revision,revision.revisionSHA256==value.planFrame.planRevision.revisionSHA256,revision.spatialFrames.contains(where:{$0.frameID==value.planFrame.spatialFrameID&&$0.pageID==value.planFrame.pageID}) else{throw WorkspaceMutationFailureV1.invalidCommand};if let predecessor{guard storedObservations.filter({$0.observationID==predecessor.observationID&&$0==predecessor}).count==1,storedObservations.filter({$0.predecessorObservationID==predecessor.observationID}).isEmpty else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision}}else{guard storedObservations.filter({$0.workspaceID==value.workspaceID&&$0.assetID==value.assetID&&$0.placementEpisodeID==value.placementEpisodeID&&$0.planFrame.spatialFrameID==value.planFrame.spatialFrameID}).isEmpty else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision}};modelContext.insert(try SpatialAnchorObservationRow(value))};return try WorkspaceMutationEffectV1(affectedEntities:mutation.affectedIdentities,temporaryRelativePath:temporaryRelativePath)}catch let failure as WorkspaceMutationFailureV1{modelContext.rollback();throw failure}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}}

    private func validatePlacementPoseAdmissionClosure(_ closure:PlacementPoseAdmissionClosureV1)throws{
        let releaseID=closure.packageRelease.packageReleaseID
        let releaseRows=try modelContext.fetch(FetchDescriptor<PromotedPackageReleaseRow>())
        guard releaseRows.filter({(try? $0.value().packageRelease.packageReleaseID)==releaseID}).count==1,
              let releaseRow=releaseRows.first(where:{(try? $0.value().packageRelease.packageReleaseID)==releaseID}),
              try releaseRow.value().packageRelease==closure.packageRelease else{throw WorkspaceMutationFailureV1.invalidCommand}
        let revisions=try modelContext.fetch(FetchDescriptor<PlanRevisionRow>()).map{try $0.value()}
        for value in closure.planRevisions{guard revisions.filter({$0==value}).count==1 else{throw WorkspaceMutationFailureV1.invalidCommand}}
        let placements=try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>()).map{try $0.value()}
        for value in closure.placementEvents{guard placements.filter({$0==value}).count==1 else{throw WorkspaceMutationFailureV1.invalidCommand}}
    }
    private func requirePlacementReferencesAgainst(_ value:PlanPlacementV1,_ revision:PlanRevisionV1)throws{guard value.planRevision==(try revision.reference)else{throw WorkspaceMutationFailureV1.invalidCommand};if let binding=value.assetLocatorBinding{let receiptID=binding.bindingReceiptID,rows=try modelContext.fetch(FetchDescriptor<LocatorBindingReceiptRow>(predicate:#Predicate{$0.receiptID==receiptID}));guard rows.count==1,let stored=try rows.first?.value(),stored.revision==binding.bindingReceiptRevision,stored.receiptSHA256==binding.bindingReceiptSHA256,stored.after==binding.locator,stored.after.assetID==binding.assetID else{throw WorkspaceMutationFailureV1.invalidCommand}}}
    private func requireReceiptPredecessor(_ predecessor:RebaseReceiptV1?,_ receipts:[RebaseReceiptV1])throws{guard let predecessor else{return};let matches=receipts.filter{$0.receiptID==predecessor.receiptID},successors=receipts.filter{$0.supersedesReceiptSHA256==predecessor.receiptSHA256};guard matches.count==1,matches[0]==predecessor,successors.isEmpty else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision}}
    private func validateAccessibleDocumentExternalProof(_ receipt:AccessibleDocumentAssessmentReceiptV1)throws{
        guard receipt.scope == .currentOutput,receipt.state == .externallyProved else{return}
        let evidenceAudience:EvidenceAudienceV1=receipt.audience == .customerSafe ? .customerReport:.internalReview
        let linkRows=try modelContext.fetch(FetchDescriptor<ClaimEvidenceLinkRow>())
        let links=try linkRows.map{$0.value()}
        let superseded=Set(links.compactMap(\.supersedesLinkID))
        let heads=links.filter{!superseded.contains($0.linkID)}
        for proof in receipt.externalProof{
            guard let evidenceID=UUID(uuidString:proof.evidenceID)else{throw WorkspaceMutationFailureV1.invalidCommand}
            let files=try modelContext.fetch(FetchDescriptor<EvidenceFile>(predicate:#Predicate{$0.id==evidenceID}))
            guard files.count==1,let evidence=files.first else{throw WorkspaceMutationFailureV1.invalidCommand}
            let recordID=evidence.recordID
            let records=try modelContext.fetch(FetchDescriptor<WorkflowRecord>(predicate:#Predicate{$0.id==recordID}))
            let originalMatches=evidence.sha256==proof.evidenceSHA256&&evidence.mimeType==proof.mediaType
            let thumbnailMatches=evidence.thumbnailSHA256==proof.evidenceSHA256&&proof.mediaType=="image/jpeg"
            let authorities=heads.filter{$0.workspaceID==receipt.workspaceID&&$0.evidenceID==proof.evidenceID&&$0.evidenceSHA256==proof.evidenceSHA256&&$0.decision.audience==evidenceAudience}
            guard records.count==1,records[0].state==WorkflowState.completed.rawValue,[originalMatches,thumbnailMatches].filter{$0}.count==1,authorities.count==1,authorities[0].decision.disposition == .included else{throw WorkspaceMutationFailureV1.invalidCommand}
        }
    }
    private enum FieldReferenceStoredValue{case release(FieldReferenceReleaseV1);case binding(FieldReferenceBindingV1)}
    private func fieldReferenceValue(_ identity:WorkspaceEntityIdentityV1)throws->FieldReferenceStoredValue?{let id=identity.id;switch identity.kind{case .fieldReferenceRelease:let rows=try modelContext.fetch(FetchDescriptor<FieldReferenceReleaseRow>(predicate:#Predicate{$0.releaseID==id}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return try rows.first.map{.release(try $0.value())};case .fieldReferenceBinding:let rows=try modelContext.fetch(FetchDescriptor<FieldReferenceBindingRow>(predicate:#Predicate{$0.bindingID==id}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};guard let row=rows.first else{return nil};let releaseID=row.releaseID,releases=try modelContext.fetch(FetchDescriptor<FieldReferenceReleaseRow>(predicate:#Predicate{$0.releaseID==releaseID}));guard releases.count==1,let release=try releases.first?.value()else{throw WorkspaceMutationFailureV1.persistenceFailed};return .binding(try row.value(release:release));default:return nil}}
    private func fieldReferenceSuccessorExists(_ identity:WorkspaceEntityIdentityV1)throws->Bool{let id=identity.id;switch identity.kind{case .fieldReferenceRelease:let rows=try modelContext.fetch(FetchDescriptor<FieldReferenceReleaseRow>());let count=try rows.map{$0.value()}.filter{$0.supersedesReleaseID==id}.count;guard count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return count==1;case .fieldReferenceBinding:let rows=try modelContext.fetch(FetchDescriptor<FieldReferenceBindingRow>());var count=0;for row in rows{let releaseID=row.releaseID,releases=try modelContext.fetch(FetchDescriptor<FieldReferenceReleaseRow>(predicate:#Predicate{$0.releaseID==releaseID}));guard releases.count==1,let release=try releases.first?.value()else{throw WorkspaceMutationFailureV1.persistenceFailed};if try row.value(release:release).supersedesBindingID==id{count+=1}};guard count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return count==1;default:return false}}

    private func applyPackagePromotion(_ mutation:PackagePromotionMutationV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{do{try mutation.validate();let affected=try mutation.affectedIdentities;for identity in affected{guard try !packageEvolutionRowExists(identity)else{throw WorkspaceMutationFailureV1.sequenceCollision}};try requireExactActor(mutation.actor);if let embedded=mutation.predecessorPointer{let id=embedded.pointerID;let rows=try modelContext.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>(predicate:#Predicate{$0.pointerID==id}));guard rows.count==1,let stored=try rows.first?.value(),stored==embedded,stored.workspaceID==mutation.workspaceID,stored.revision==mutation.expectedPointerRevision,try !packagePointerSuccessorExists(id)else{throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind:.activePackageRegistryPointer,id:id))};try mutation.resultingPointer.validateSuccessor(of:stored,expectedRevision:mutation.expectedPointerRevision)}else{guard mutation.expectedPointerRevision==0,mutation.resultingPointer.supersedesPointerID==nil else{throw WorkspaceMutationFailureV1.invalidCommand}};_ = try PackageEvolutionLifecycleClosureV1(promotedReleases:[mutation.promotedRelease],sandboxRuns:[mutation.sandboxRun],promotionReceipts:[mutation.receipt],activePointers:[mutation.predecessorPointer,mutation.resultingPointer].compactMap{$0});modelContext.insert(try PromotedPackageReleaseRow(mutation.promotedRelease));modelContext.insert(try PackageSandboxRunRow(mutation.sandboxRun));modelContext.insert(try PackagePromotionReceiptRow(mutation.receipt));modelContext.insert(try ActivePackageRegistryPointerRow(mutation.resultingPointer));return try WorkspaceMutationEffectV1(affectedEntities:affected,temporaryRelativePath:temporaryRelativePath)}catch let f as WorkspaceMutationFailureV1{modelContext.rollback();throw f}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}}
    private func packageEvolutionRowExists(_ identity:WorkspaceEntityIdentityV1)throws->Bool{let id=identity.id;switch identity.kind{case .promotedPackageRelease:return try uniquePresence(modelContext.fetch(FetchDescriptor<PromotedPackageReleaseRow>(predicate:#Predicate{$0.releaseRecordID==id})));case .packageSandboxRun:return try uniquePresence(modelContext.fetch(FetchDescriptor<PackageSandboxRunRow>(predicate:#Predicate{$0.runID==id})));case .packagePromotionReceipt:return try uniquePresence(modelContext.fetch(FetchDescriptor<PackagePromotionReceiptRow>(predicate:#Predicate{$0.receiptID==id})));case .activePackageRegistryPointer:return try uniquePresence(modelContext.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>(predicate:#Predicate{$0.pointerID==id})));default:return false}}
    private func packagePointerSuccessorExists(_ predecessorID:UUID)throws->Bool{let id=predecessorID;let rows=try modelContext.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>(predicate:#Predicate{$0.supersedesPointerID==id}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return !rows.isEmpty}

    private func applyMeasurementIntegrity(_ mutation:MeasurementIntegrityMutationV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{do{try mutation.validate();let affected=try mutation.affectedIdentities;for payload in mutation.bundle.mutationPayloads{let identity=try payload.identity;guard try measurementValue(identity)==nil else{throw WorkspaceMutationFailureV1.sequenceCollision};if let predecessor=try payload.predecessorIdentity{guard let prior=try measurementValue(predecessor),prior.revision==(try mutation.expectedRevision(for:predecessor)),prior.workspaceID==mutation.workspaceID,try !measurementSuccessorExists(predecessor)else{throw WorkspaceMutationFailureV1.staleEntityRevision(predecessor)};switch(payload,prior){case let (.instrument(v),.instrument(p)):try v.validateSuccessor(of:p);case let (.calibration(v),.calibration(p)):try v.validateSuccessor(of:p);case let (.capture(v),.capture(p)):try v.validateSuccessor(of:p);case let (.series(v),.series(p)):try v.validateSuccessor(of:p);case let (.quality(v),.quality(p)):try v.validateSuccessor(of:p);default:throw WorkspaceMutationFailureV1.invalidCommand}}}
        for value in mutation.bundle.instruments{modelContext.insert(try InstrumentReferenceRow(value))}
        for value in mutation.bundle.calibrations{
            let instrument=try exactInstrument(value.instrument.referenceID)
            guard instrument.workspaceID==value.workspaceID,
                  instrument.instrumentID==value.instrument.instrumentID,
                  instrument.revision==value.instrument.revision,
                  instrument.referenceSHA256==value.instrument.referenceSHA256 else{throw WorkspaceMutationFailureV1.invalidCommand}
            modelContext.insert(try CalibrationStatusSnapshotRow(value))
        }
        for value in mutation.bundle.captures{
            let instrument=try value.instrument.map{try exactInstrument($0.referenceID)}
            let calibration=try value.calibration.map{try exactCalibration($0.snapshotID)}
            try value.validateClosure(instrument:instrument,calibration:calibration)
            modelContext.insert(try MeasurementCaptureRow(value))
        }
        for value in mutation.bundle.series{
            let captures=try value.samples.map{try exactCapture($0.captureID)}
            let protocolRelease=try exactMeasurementProtocol(value.protocolReference.releaseID)
            try value.validateClosure(captures:captures,protocolRelease:protocolRelease)
            modelContext.insert(try MeasurementSeriesRow(value))
        }
        for value in mutation.bundle.assessments{
            switch value.subjectKind{
            case .capture:
                let subject=try exactCapture(value.subjectID)
                guard subject.workspaceID==value.workspaceID,subject.revision==value.subjectRevision,subject.captureSHA256==value.subjectSHA256 else{throw WorkspaceMutationFailureV1.invalidCommand}
            case .series:
                let subject=try exactSeries(value.subjectID,revision:value.subjectRevision)
                guard subject.workspaceID==value.workspaceID,subject.seriesSHA256==value.subjectSHA256 else{throw WorkspaceMutationFailureV1.invalidCommand}
            }
            modelContext.insert(try MeasurementQualityAssessmentRow(value))
        }
        return try WorkspaceMutationEffectV1(affectedEntities:affected,temporaryRelativePath:temporaryRelativePath)
    }catch let failure as WorkspaceMutationFailureV1{modelContext.rollback();throw failure}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}}
    private enum MeasurementStoredValue{case instrument(InstrumentReferenceV1),calibration(CalibrationStatusSnapshotV1),capture(MeasurementCaptureV1),series(MeasurementSeriesV1),quality(MeasurementQualityAssessmentV1);var workspaceID:WorkspaceID{switch self{case let .instrument(v):v.workspaceID;case let .calibration(v):v.workspaceID;case let .capture(v):v.workspaceID;case let .series(v):v.workspaceID;case let .quality(v):v.workspaceID}}var revision:UInt64{switch self{case let .instrument(v):v.revision;case let .calibration(v):v.revision;case let .capture(v):v.revision;case let .series(v):v.revision;case let .quality(v):v.revision}}}
    private func measurementValue(_ i:WorkspaceEntityIdentityV1)throws->MeasurementStoredValue?{let id=i.id;switch i.kind{case .instrumentReference:let r=try modelContext.fetch(FetchDescriptor<InstrumentReferenceRow>(predicate:#Predicate{$0.referenceID==id}));guard r.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return try r.first.map{.instrument(try $0.value())};case .calibrationStatusSnapshot:let r=try modelContext.fetch(FetchDescriptor<CalibrationStatusSnapshotRow>(predicate:#Predicate{$0.snapshotID==id}));guard r.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return try r.first.map{.calibration(try $0.value())};case .measurementCapture:let r=try modelContext.fetch(FetchDescriptor<MeasurementCaptureRow>(predicate:#Predicate{$0.captureID==id}));guard r.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return try r.first.map{.capture(try $0.value())};case .measurementSeries:let r=try modelContext.fetch(FetchDescriptor<MeasurementSeriesRow>(predicate:#Predicate{$0.snapshotID==id}));guard r.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return try r.first.map{.series(try $0.value())};case .measurementQualityAssessment:let r=try modelContext.fetch(FetchDescriptor<MeasurementQualityAssessmentRow>(predicate:#Predicate{$0.assessmentID==id}));guard r.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return try r.first.map{.quality(try $0.value())};default:return nil}}
    private func measurementSuccessorExists(_ p:WorkspaceEntityIdentityV1)throws->Bool{let id=p.id;let count:Int;switch p.kind{case .instrumentReference:count=try modelContext.fetch(FetchDescriptor<InstrumentReferenceRow>()).map{try $0.value()}.filter{$0.supersedesReferenceID==id}.count;case .calibrationStatusSnapshot:count=try modelContext.fetch(FetchDescriptor<CalibrationStatusSnapshotRow>()).map{try $0.value()}.filter{$0.supersedesSnapshotID==id}.count;case .measurementCapture:count=try modelContext.fetch(FetchDescriptor<MeasurementCaptureRow>()).map{try $0.value()}.filter{$0.supersedesCaptureID==id}.count;case .measurementSeries:count=try modelContext.fetch(FetchDescriptor<MeasurementSeriesRow>()).map{try $0.value()}.filter{$0.supersedesSnapshotID==id}.count;case .measurementQualityAssessment:count=try modelContext.fetch(FetchDescriptor<MeasurementQualityAssessmentRow>()).map{try $0.value()}.filter{$0.supersedesAssessmentID==id}.count;default:throw WorkspaceMutationFailureV1.invalidCommand};guard count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return count==1}
    private func exactInstrument(_ id:UUID)throws->InstrumentReferenceV1{guard case let .instrument(v)?=try measurementValue(.init(kind:.instrumentReference,id:id))else{throw WorkspaceMutationFailureV1.invalidCommand};return v}
    private func exactCalibration(_ id:UUID)throws->CalibrationStatusSnapshotV1{guard case let .calibration(v)?=try measurementValue(.init(kind:.calibrationStatusSnapshot,id:id))else{throw WorkspaceMutationFailureV1.invalidCommand};return v}
    private func exactCapture(_ id:UUID)throws->MeasurementCaptureV1{guard case let .capture(v)?=try measurementValue(.init(kind:.measurementCapture,id:id))else{throw WorkspaceMutationFailureV1.invalidCommand};return v}
    private func exactSeries(_ id:UUID,revision:UInt64)throws->MeasurementSeriesV1{let subjectID=id;let rows=try modelContext.fetch(FetchDescriptor<MeasurementSeriesRow>(predicate:#Predicate{$0.seriesID==subjectID}));let matches=try rows.map{$0.value()}.filter{$0.revision==revision};guard matches.count==1,let value=matches.first else{throw WorkspaceMutationFailureV1.invalidCommand};return value}
    private func exactMeasurementProtocol(_ id:UUID)throws->MeasurementProtocolReleaseV1{let releaseID=id;let rows=try modelContext.fetch(FetchDescriptor<MeasurementProtocolReleaseRow>(predicate:#Predicate{$0.releaseID==releaseID}));guard rows.count==1,let value=try rows.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return value}

    private func applyPrivacyTransform(_ mutation:PrivacyTransformMutationV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{do{try mutation.validate();let affected=try mutation.affectedIdentities;for identity in affected{guard try privacyRow(identity)==nil else{throw WorkspaceMutationFailureV1.sequenceCollision}};switch mutation{case let .policy(value):if let id=value.supersedesPolicyID{guard case let .policy(old)?=try privacyRow(.init(kind:.privacyTransformPolicy,id:id)),try !privacySuccessorExists(.init(kind:.privacyTransformPolicy,id:id))else{throw WorkspaceMutationFailureV1.invalidCommand};try value.validateSuccessor(of:old)};modelContext.insert(try PrivacyTransformPolicyRow(value));case let .publish(policy,regions,manifest):guard case let .policy(storedPolicy)?=try privacyRow(.init(kind:.privacyTransformPolicy,id:policy.policyID)),storedPolicy==policy else{throw WorkspaceMutationFailureV1.invalidCommand};if let id=manifest.supersedesManifestID{guard case let .manifest(old)?=try privacyRow(.init(kind:.privacyTransformManifest,id:id)),try !privacySuccessorExists(.init(kind:.privacyTransformManifest,id:id))else{throw WorkspaceMutationFailureV1.invalidCommand};try manifest.validateSuccessor(of:old,policy:policy)};for region in regions{try requireExactActor(region.author);modelContext.insert(try PrivacyRegionRow(region))};modelContext.insert(try PrivacyTransformManifestRow(manifest));case let .review(value,manifest,policy):guard case let .policy(storedPolicy)?=try privacyRow(.init(kind:.privacyTransformPolicy,id:policy.policyID)),storedPolicy==policy,case let .manifest(storedManifest)?=try privacyRow(.init(kind:.privacyTransformManifest,id:manifest.manifestID)),storedManifest==manifest else{throw WorkspaceMutationFailureV1.invalidCommand};try requireExactActor(value.reviewer);if let id=value.supersedesReceiptID{guard case let .review(old)?=try privacyRow(.init(kind:.privacyReviewReceipt,id:id)),try !privacySuccessorExists(.init(kind:.privacyReviewReceipt,id:id))else{throw WorkspaceMutationFailureV1.invalidCommand};try old.validate(manifest:manifest,policy:policy);try value.validateSuccessor(of:old,manifest:manifest,policy:policy)};modelContext.insert(try PrivacyReviewReceiptRow(value))};return try WorkspaceMutationEffectV1(affectedEntities:affected,temporaryRelativePath:temporaryRelativePath)}catch let failure as WorkspaceMutationFailureV1{modelContext.rollback();throw failure}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}}
    private func applyEvidenceMetadata(
        _ mutation: EvidenceMetadataMutationV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        do {
            try mutation.validate()
            let event = mutation.associationEvent
            let workspace = event.workspaceID
            let evidenceID = event.evidenceID
            let eventRowID = "\(workspace)|\(event.associationEventID)"
            let duplicateEventRows = try modelContext.fetch(
                FetchDescriptor<EvidenceAssociationEventRowV1>(
                    predicate: #Predicate { $0.rowID == eventRowID }
                )
            )
            guard duplicateEventRows.isEmpty else {
                throw WorkspaceMutationFailureV1.sequenceCollision
            }

            let existingAssociations = try validatedEvidenceAssociations(
                workspaceID: mutation.workspaceID
            )
            let priorEvents = existingAssociations.filter { $0.evidenceID == evidenceID }
            if event.expectedEvidenceRevision == 0 {
                guard priorEvents.isEmpty,
                      event.action == .assigned,
                      event.supersedesAssociationEventID == nil else {
                    throw WorkspaceMutationFailureV1.staleWorkspaceRevision
                }
            } else {
                guard let prior = priorEvents.last,
                      prior.resultingEvidenceRevision == event.expectedEvidenceRevision else {
                    throw WorkspaceMutationFailureV1.staleWorkspaceRevision
                }
                try event.validateSuccessor(of: prior)
            }
            try EvidenceAssociationLedgerV1.validate(existingAssociations + [event])

            let sequenceID = mutation.sequenceSuccessor.sequenceID
            let sequences = try evidenceSequenceHistory(
                workspaceID: mutation.workspaceID,
                sequenceID: sequenceID
            )
            if mutation.expectedSequenceRevision == 0 {
                guard sequences.isEmpty,
                      mutation.sequenceSuccessor.predecessor == nil else {
                    throw WorkspaceMutationFailureV1.staleWorkspaceRevision
                }
            } else {
                guard let expectedCount = Int(exactly: mutation.expectedSequenceRevision),
                      let prior = sequences.last,
                      prior.revision == mutation.expectedSequenceRevision,
                      sequences.count == expectedCount else {
                    throw WorkspaceMutationFailureV1.staleWorkspaceRevision
                }
                try mutation.sequenceSuccessor.validateSuccessor(of: prior)
            }

            for item in mutation.sequenceSuccessor.orderedItems {
                let history = item.evidenceID == evidenceID
                    ? priorEvents + [event]
                    : try evidenceAssociationHistory(
                        workspaceID: mutation.workspaceID,
                        evidenceID: item.evidenceID
                    )
                guard let terminal = history.last,
                      terminal.action != .removed,
                      terminal.evidenceID == item.evidenceID,
                      terminal.contentID == item.contentID,
                      terminal.target == item.target,
                      item.associationBinding == (try EvidenceAssociationBindingV1(terminal)) else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            }
            if event.action == .removed {
                guard !mutation.sequenceSuccessor.orderedItems.contains(where: {
                    $0.evidenceID == event.evidenceID
                }) else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            }

            modelContext.insert(try EvidenceAssociationEventRowV1(event))
            modelContext.insert(try EvidenceSequenceRevisionRowV1(mutation.sequenceSuccessor))
            return try WorkspaceMutationEffectV1(
                affectedEntities: mutation.affectedIdentities,
                temporaryRelativePath: temporaryRelativePath
            )
        } catch let failure as WorkspaceMutationFailureV1 {
            modelContext.rollback()
            throw failure
        } catch {
            modelContext.rollback()
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    func evidenceAssociationHistory(
        workspaceID: WorkspaceID,
        evidenceID: String
    ) throws -> [EvidenceAssociationV1] {
        guard ContentContractValidationV1.validID(evidenceID) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        return try validatedEvidenceAssociations(workspaceID: workspaceID).filter {
            $0.evidenceID == evidenceID
        }
    }

    private func validatedEvidenceAssociations(
        workspaceID: WorkspaceID
    ) throws -> [EvidenceAssociationV1] {
        let workspace = workspaceID.rawValue.uuidString.lowercased()
        let rows = try modelContext.fetch(
            FetchDescriptor<EvidenceAssociationEventRowV1>(
                predicate: #Predicate { $0.workspaceID == workspace }
            )
        )
        let values = try rows.map { try $0.value() }.sorted {
            ($0.evidenceID, $0.resultingEvidenceRevision, $0.associationEventID)
                < ($1.evidenceID, $1.resultingEvidenceRevision, $1.associationEventID)
        }
        try EvidenceAssociationLedgerV1.validate(values)
        return values
    }

    func evidenceSequenceHistory(
        workspaceID: WorkspaceID,
        sequenceID: UUID
    ) throws -> [EvidenceSequenceV1] {
        try validatedEvidenceSequences(workspaceID: workspaceID).filter {
            $0.sequenceID == sequenceID
        }
    }

    private func validatedEvidenceSequences(
        workspaceID: WorkspaceID
    ) throws -> [EvidenceSequenceV1] {
        let workspace = workspaceID.rawValue
        let rows = try modelContext.fetch(
            FetchDescriptor<EvidenceSequenceRevisionRowV1>(
                predicate: #Predicate { $0.workspaceID == workspace }
            )
        )
        let values = try rows.map { try $0.value() }.sorted {
            ($0.sequenceID.uuidString, $0.revision)
                < ($1.sequenceID.uuidString, $1.revision)
        }
        let revisionKeys = values.map {
            "\($0.sequenceID.uuidString.lowercased())|\($0.revision)"
        }
        guard Set(revisionKeys).count == values.count,
              Set(values.map(\.mutationID)).count == values.count,
              Dictionary(grouping: values, by: \.sequenceID).values.allSatisfy({
                  $0.first?.revision == 1 && $0.first?.predecessor == nil
              }) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        for history in Dictionary(grouping: values, by: \.sequenceID).values {
            for index in history.indices.dropFirst() {
                try history[index].validateSuccessor(of: history[index - 1])
            }
        }
        return values
    }

    func persistedEvidenceMetadataEffectMatches(
        _ mutation: EvidenceMetadataMutationV1
    ) throws -> Bool {
        try mutation.validate()
        let event = mutation.associationEvent
        let eventRowID = "\(event.workspaceID)|\(event.associationEventID)"
        let eventRows = try modelContext.fetch(
            FetchDescriptor<EvidenceAssociationEventRowV1>(
                predicate: #Predicate { $0.rowID == eventRowID }
            )
        )
        let sequenceID = mutation.sequenceSuccessor.sequenceID
        let workspace = mutation.workspaceID.rawValue
        let revision = mutation.sequenceSuccessor.revision
        let sequenceRows = try modelContext.fetch(
            FetchDescriptor<EvidenceSequenceRevisionRowV1>(
                predicate: #Predicate {
                    $0.workspaceID == workspace
                        && $0.sequenceID == sequenceID
                        && $0.revision == revision
                }
            )
        )
        guard eventRows.count <= 1, sequenceRows.count <= 1 else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        let presentCount = eventRows.count + sequenceRows.count
        guard presentCount > 0 else { return false }
        guard presentCount == 2,
              let eventRow = eventRows.first,
              let sequenceRow = sequenceRows.first,
              try eventRow.value() == event,
              try sequenceRow.value() == mutation.sequenceSuccessor else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        let allAssociations = try validatedEvidenceAssociations(
            workspaceID: mutation.workspaceID
        )
        let allSequences = try validatedEvidenceSequences(
            workspaceID: mutation.workspaceID
        )
        try EvidenceMetadataGraphV1.validate(
            sequences: allSequences,
            associationEvents: allAssociations
        )
        return true
    }

    private enum PrivacyStoredValue{case policy(PrivacyTransformPolicyV1),region(PrivacyRegionV1),manifest(PrivacyTransformManifestV1),review(PrivacyReviewReceiptV1)}
    private func privacyRow(_ identity:WorkspaceEntityIdentityV1)throws->PrivacyStoredValue?{
        let id=identity.id
        switch identity.kind{
        case .privacyTransformPolicy:let r=try modelContext.fetch(FetchDescriptor<PrivacyTransformPolicyRow>(predicate:#Predicate{$0.policyID==id}));guard r.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return try r.first.map{.policy(try $0.value())}
        case .privacyRegion:let r=try modelContext.fetch(FetchDescriptor<PrivacyRegionRow>(predicate:#Predicate{$0.regionID==id}));guard r.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return try r.first.map{.region(try $0.value())}
        case .privacyTransformManifest:let r=try modelContext.fetch(FetchDescriptor<PrivacyTransformManifestRow>(predicate:#Predicate{$0.manifestID==id}));guard r.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return try r.first.map{.manifest(try privacyManifestValue($0))}
        case .privacyReviewReceipt:let r=try modelContext.fetch(FetchDescriptor<PrivacyReviewReceiptRow>(predicate:#Predicate{$0.receiptID==id}));guard r.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return try r.first.map{.review(try privacyReviewValue($0))}
        default:return nil
        }
    }
    private func privacyManifestValue(_ row:PrivacyTransformManifestRow)throws->PrivacyTransformManifestV1{
        let id=row.policyID
        let policies=try modelContext.fetch(FetchDescriptor<PrivacyTransformPolicyRow>(predicate:#Predicate{$0.policyID==id}))
        guard policies.count==1,let policy=try policies.first?.value() else{throw WorkspaceMutationFailureV1.persistenceFailed}
        return try row.value(policy:policy)
    }
    private func privacyReviewValue(_ row:PrivacyReviewReceiptRow)throws->PrivacyReviewReceiptV1{
        let manifestID=row.manifestID,policyID=row.policyID
        let manifestRows=try modelContext.fetch(FetchDescriptor<PrivacyTransformManifestRow>(predicate:#Predicate{$0.manifestID==manifestID}))
        let policyRows=try modelContext.fetch(FetchDescriptor<PrivacyTransformPolicyRow>(predicate:#Predicate{$0.policyID==policyID}))
        guard manifestRows.count==1,policyRows.count==1,let policy=try policyRows.first?.value(),let manifestRow=manifestRows.first else{throw WorkspaceMutationFailureV1.persistenceFailed}
        let manifest=try manifestRow.value(policy:policy)
        return try row.value(manifest:manifest,policy:policy)
    }
    private func privacySuccessorExists(_ identity:WorkspaceEntityIdentityV1)throws->Bool{let id=identity.id;let count:Int;switch identity.kind{case .privacyTransformPolicy:count=try modelContext.fetch(FetchDescriptor<PrivacyTransformPolicyRow>()).map{try $0.value()}.filter{$0.supersedesPolicyID==id}.count;case .privacyTransformManifest:count=try modelContext.fetch(FetchDescriptor<PrivacyTransformManifestRow>()).map{try privacyManifestValue($0)}.filter{$0.supersedesManifestID==id}.count;case .privacyReviewReceipt:count=try modelContext.fetch(FetchDescriptor<PrivacyReviewReceiptRow>()).map{try privacyReviewValue($0)}.filter{$0.supersedesReceiptID==id}.count;default:throw WorkspaceMutationFailureV1.invalidCommand};guard count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return count==1}
    private func applyClientCapability(_ mutation:ClientCapabilityMutationV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{do{try mutation.validate();let affected=try mutation.affectedIdentity;guard try clientCapabilityRow(affected,release:mutation.release)==nil else{throw WorkspaceMutationFailureV1.sequenceCollision};if mutation.expectedRevision>0{let predecessor=try mutation.concurrencyIdentity;guard let prior=try clientCapabilityRow(predecessor,release:mutation.release),try !clientCapabilitySuccessorExists(predecessor,release:mutation.release)else{throw WorkspaceMutationFailureV1.staleEntityRevision(predecessor)};switch(mutation,prior){case let (.profile(v),.profile(p)):try v.validateSuccessor(of:p);case let (.policy(v,r),.policy(p)):try v.validateSuccessor(of:p,release:r);case let (.disposition(v,r),.disposition(p)):try v.validateSuccessor(of:p,release:r);default:throw WorkspaceMutationFailureV1.invalidCommand}};switch mutation{case let .profile(v):modelContext.insert(try ClientCapabilityProfileRow(v));case let .policy(v,r):modelContext.insert(try PackageLifecyclePolicyRow(v,release:r));case let .disposition(v,r):modelContext.insert(try PackageLifecycleDispositionRow(v,release:r));case let .admission(v,p,policy,d,r):guard case let .profile(sp)?=try clientCapabilityRow(.init(kind:.clientCapabilityProfile,id:p.profileID),release:r),sp==p,case let .policy(sPolicy)?=try clientCapabilityRow(.init(kind:.packageLifecyclePolicy,id:policy.policyID),release:r),sPolicy==policy,case let .disposition(sd)?=try clientCapabilityRow(.init(kind:.packageLifecycleDisposition,id:d.dispositionID),release:r),sd==d else{throw WorkspaceMutationFailureV1.invalidCommand};modelContext.insert(try ClientCapabilityAdmissionDecisionRow(v,profile:p,policy:policy,disposition:d,release:r))};return try WorkspaceMutationEffectV1(affectedEntities:[affected],temporaryRelativePath:temporaryRelativePath)}catch let f as WorkspaceMutationFailureV1{modelContext.rollback();throw f}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}}
    private enum ClientCapabilityStoredValue{case profile(ClientCapabilityProfileV1),policy(PackageLifecyclePolicyV1),disposition(PackageLifecycleDispositionV1),admission(ClientCapabilityAdmissionDecisionV1)}
    private func clientCapabilityRow(_ identity:WorkspaceEntityIdentityV1,release:InspectionPackageReleaseV1?)throws->ClientCapabilityStoredValue?{let id=identity.id;switch identity.kind{case .clientCapabilityProfile:let rows=try modelContext.fetch(FetchDescriptor<ClientCapabilityProfileRow>(predicate:#Predicate{$0.profileID==id}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return try rows.first.map{.profile(try $0.value())};case .packageLifecyclePolicy:guard let release else{throw WorkspaceMutationFailureV1.invalidCommand};let rows=try modelContext.fetch(FetchDescriptor<PackageLifecyclePolicyRow>(predicate:#Predicate{$0.policyID==id}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return try rows.first.map{.policy(try $0.value(release:release))};case .packageLifecycleDisposition:guard let release else{throw WorkspaceMutationFailureV1.invalidCommand};let rows=try modelContext.fetch(FetchDescriptor<PackageLifecycleDispositionRow>(predicate:#Predicate{$0.dispositionID==id}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return try rows.first.map{.disposition(try $0.value(release:release))};case .clientCapabilityAdmissionDecision:guard let release else{throw WorkspaceMutationFailureV1.invalidCommand};let rows=try modelContext.fetch(FetchDescriptor<ClientCapabilityAdmissionDecisionRow>(predicate:#Predicate{$0.decisionID==id}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};guard let row=rows.first else{return nil};let profileID=row.profileID,policyID=row.policyID,dispositionID=row.dispositionID;guard case let .profile(p)?=try clientCapabilityRow(.init(kind:.clientCapabilityProfile,id:profileID),release:release),case let .policy(policy)?=try clientCapabilityRow(.init(kind:.packageLifecyclePolicy,id:policyID),release:release),case let .disposition(d)?=try clientCapabilityRow(.init(kind:.packageLifecycleDisposition,id:dispositionID),release:release)else{throw WorkspaceMutationFailureV1.persistenceFailed};return .admission(try row.value(profile:p,policy:policy,disposition:d,release:release));default:return nil}}
    private func clientCapabilitySuccessorExists(_ identity:WorkspaceEntityIdentityV1,release:InspectionPackageReleaseV1?)throws->Bool{let id=identity.id;let count:Int;switch identity.kind{case .clientCapabilityProfile:count=try modelContext.fetch(FetchDescriptor<ClientCapabilityProfileRow>()).map{try $0.value()}.filter{$0.supersedesProfileID==id}.count;case .packageLifecyclePolicy:guard let release else{throw WorkspaceMutationFailureV1.invalidCommand};let packageReleaseID=release.packageReleaseID;count=try modelContext.fetch(FetchDescriptor<PackageLifecyclePolicyRow>(predicate:#Predicate{$0.packageReleaseID==packageReleaseID})).map{try $0.value(release:release)}.filter{$0.supersedesPolicyID==id}.count;case .packageLifecycleDisposition:guard let release else{throw WorkspaceMutationFailureV1.invalidCommand};let packageReleaseID=release.packageReleaseID;count=try modelContext.fetch(FetchDescriptor<PackageLifecycleDispositionRow>(predicate:#Predicate{$0.packageReleaseID==packageReleaseID})).map{try $0.value(release:release)}.filter{$0.supersedesDispositionID==id}.count;default:throw WorkspaceMutationFailureV1.invalidCommand};guard count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return count==1}

    private func applyWorkPacket(_ mutation:WorkPacketMutationV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{do{try mutation.validate();let affected=try mutation.affectedIdentity;guard try !workPacketRowExists(affected)else{throw WorkspaceMutationFailureV1.sequenceCollision};if let predecessor=try mutation.postImage.predecessorIdentity{let prior=try workPacketValue(predecessor);guard prior.revision==mutation.expectedRevision,prior.workspaceID==mutation.workspaceID,prior.revision<UInt64.max,try !workPacketSuccessorExists(predecessor)else{throw WorkspaceMutationFailureV1.staleEntityRevision(predecessor)};switch mutation.postImage{case let .supersedeClaim(v):guard case let .claim(p)=prior else{throw WorkspaceMutationFailureV1.invalidCommand};try v.validateSuccessor(of:p);case let .supersedeLease(v):guard case let .lease(p)=prior else{throw WorkspaceMutationFailureV1.invalidCommand};try v.validateSuccessor(of:p);default:throw WorkspaceMutationFailureV1.invalidCommand}}
        switch mutation.postImage{case let .appendManifest(v):try requireExactActor(v.creator);modelContext.insert(try WorkPacketManifestRow(v));case let .appendClaim(v),let .supersedeClaim(v):try requireExactActor(v.holder);let m=try requireWorkPacketManifest(v.manifest.manifestID,workspaceID:v.workspaceID);guard try WorkPacketManifestReferenceV1(m)==v.manifest,m.items.contains(where:{$0.itemID==v.item.itemID&&((try? WorkPacketItemReferenceV1(manifest:m,item:$0))==v.item)})else{throw WorkspaceMutationFailureV1.invalidCommand};modelContext.insert(try WorkItemClaimRow(v));case let .appendLease(v),let .supersedeLease(v):try requireExactActor(v.holder);let claim=try requireWorkClaim(v.claimID,workspaceID:v.workspaceID);guard claim.item==v.item,claim.holder.actor==v.holder.actor else{throw WorkspaceMutationFailureV1.invalidCommand};modelContext.insert(try WorkLeaseRow(v));case let .recordRelease(v):try requireExactActor(v.holder);let claim=try requireWorkClaim(v.claimID,workspaceID:v.workspaceID);let lease=try requireWorkLease(v.leaseID,workspaceID:v.workspaceID);let manifest=try requireWorkPacketManifest(claim.manifest.manifestID,workspaceID:v.workspaceID);try v.validate(claim:claim,lease:lease,manifest:manifest);modelContext.insert(try WorkReleaseRow(v));case let .recordHandoff(v):try requireExactActor(v.fromHolder);try requireExactActor(v.toHolder);let release=try requireWorkRelease(v.releaseID,workspaceID:v.workspaceID);try v.validate(release:release);modelContext.insert(try WorkHandoffRow(v))};return try WorkspaceMutationEffectV1(affectedEntities:[affected],temporaryRelativePath:temporaryRelativePath)}catch let f as WorkspaceMutationFailureV1{modelContext.rollback();throw f}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}}
    private enum WorkPacketStoredValue{case manifest(WorkPacketManifestV1),claim(WorkItemClaimV1),lease(WorkLeaseV1),release(WorkReleaseV1),handoff(WorkHandoffV1);var workspaceID:WorkspaceID{switch self{case let .manifest(v):v.workspaceID;case let .claim(v):v.workspaceID;case let .lease(v):v.workspaceID;case let .release(v):v.workspaceID;case let .handoff(v):v.workspaceID}}var revision:UInt64{switch self{case let .manifest(v):v.revision;case let .claim(v):v.revision;case let .lease(v):v.revision;case let .release(v):v.revision;case let .handoff(v):v.revision}}}
    private func workPacketRowExists(_ i:WorkspaceEntityIdentityV1)throws->Bool{let id=i.id;switch i.kind{case .workPacketManifest:return try uniquePresence(modelContext.fetch(FetchDescriptor<WorkPacketManifestRow>(predicate:#Predicate{$0.manifestID==id})));case .workItemClaim:return try uniquePresence(modelContext.fetch(FetchDescriptor<WorkItemClaimRow>(predicate:#Predicate{$0.claimID==id})));case .workLease:return try uniquePresence(modelContext.fetch(FetchDescriptor<WorkLeaseRow>(predicate:#Predicate{$0.leaseID==id})));case .workRelease:return try uniquePresence(modelContext.fetch(FetchDescriptor<WorkReleaseRow>(predicate:#Predicate{$0.releaseID==id})));case .workHandoff:return try uniquePresence(modelContext.fetch(FetchDescriptor<WorkHandoffRow>(predicate:#Predicate{$0.handoffID==id})));default:return false}}
    private func workPacketValue(_ i:WorkspaceEntityIdentityV1)throws->WorkPacketStoredValue{let id=i.id;switch i.kind{case .workPacketManifest:let r=try modelContext.fetch(FetchDescriptor<WorkPacketManifestRow>(predicate:#Predicate{$0.manifestID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return .manifest(v);case .workItemClaim:let r=try modelContext.fetch(FetchDescriptor<WorkItemClaimRow>(predicate:#Predicate{$0.claimID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return .claim(v);case .workLease:let r=try modelContext.fetch(FetchDescriptor<WorkLeaseRow>(predicate:#Predicate{$0.leaseID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return .lease(v);case .workRelease:let r=try modelContext.fetch(FetchDescriptor<WorkReleaseRow>(predicate:#Predicate{$0.releaseID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return .release(v);case .workHandoff:let r=try modelContext.fetch(FetchDescriptor<WorkHandoffRow>(predicate:#Predicate{$0.handoffID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return .handoff(v);default:throw WorkspaceMutationFailureV1.invalidCommand}}
    private func workPacketSuccessorExists(_ p:WorkspaceEntityIdentityV1)throws->Bool{let id=p.id;let count:Int;switch p.kind{case .workItemClaim:count=try modelContext.fetch(FetchDescriptor<WorkItemClaimRow>()).map{try $0.value()}.filter{$0.supersedesClaimID==id}.count;case .workLease:count=try modelContext.fetch(FetchDescriptor<WorkLeaseRow>()).map{try $0.value()}.filter{$0.supersedesLeaseID==id}.count;default:throw WorkspaceMutationFailureV1.invalidCommand};guard count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return count==1}
    private func requireWorkPacketManifest(_ id:UUID,workspaceID:WorkspaceID)throws->WorkPacketManifestV1{guard case let .manifest(v)=try workPacketValue(.init(kind:.workPacketManifest,id:id)),v.workspaceID==workspaceID else{throw WorkspaceMutationFailureV1.invalidCommand};return v}
    private func requireWorkClaim(_ id:UUID,workspaceID:WorkspaceID)throws->WorkItemClaimV1{guard case let .claim(v)=try workPacketValue(.init(kind:.workItemClaim,id:id)),v.workspaceID==workspaceID else{throw WorkspaceMutationFailureV1.invalidCommand};return v}
    private func requireWorkLease(_ id:UUID,workspaceID:WorkspaceID)throws->WorkLeaseV1{guard case let .lease(v)=try workPacketValue(.init(kind:.workLease,id:id)),v.workspaceID==workspaceID else{throw WorkspaceMutationFailureV1.invalidCommand};return v}
    private func requireWorkRelease(_ id:UUID,workspaceID:WorkspaceID)throws->WorkReleaseV1{guard case let .release(v)=try workPacketValue(.init(kind:.workRelease,id:id)),v.workspaceID==workspaceID else{throw WorkspaceMutationFailureV1.invalidCommand};return v}

    private func applyFieldDraft(_ mutation:FieldDraftMutationV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{do{try mutation.validate();let affected=try mutation.affectedIdentities;switch mutation.postImage{
        case let .createCheckpoint(value):let identity=affected[0];guard case nil = try fieldDraftRow(identity) else{throw WorkspaceMutationFailureV1.sequenceCollision};modelContext.insert(try FieldDraftCheckpointRow(value))
        case let .reviseCheckpoint(value):let identity=affected[0];guard case let .checkpoint(row)?=try fieldDraftRow(identity)else{throw WorkspaceMutationFailureV1.staleEntityRevision(identity)};try row.replace(with:value,expectedRevision:mutation.expectedRevision)
        case let .appendStagingItem(value):let identity=affected[0];guard case nil = try fieldDraftRow(identity) else{throw WorkspaceMutationFailureV1.sequenceCollision};guard let checkpoint=try exactDraftCheckpoint(value.draftID,workspaceID:value.workspaceID),checkpoint.stageIDs.contains(value.stageID)else{throw WorkspaceMutationFailureV1.invalidCommand};modelContext.insert(try AttachmentStagingItemRow(value))
        case let .reviseStagingItem(value):let identity=affected[0];guard case let .stage(row)?=try fieldDraftRow(identity)else{throw WorkspaceMutationFailureV1.staleEntityRevision(identity)};try row.replace(with:value,expectedRevision:mutation.expectedRevision)
        case let .appendCommitSaga(value):let identity=affected[0];guard case nil = try fieldDraftRow(identity) else{throw WorkspaceMutationFailureV1.sequenceCollision};guard let checkpoint=try exactDraftCheckpoint(value.draftID,workspaceID:value.workspaceID),checkpoint.draftRevision==value.plan.draftRevision,checkpoint.baseCanonicalRevision==value.plan.baseCanonicalRevision,checkpoint.payloadSHA256==value.plan.payloadSHA256 else{throw WorkspaceMutationFailureV1.invalidCommand};modelContext.insert(try DraftCommitSagaRow(value))
        case let .advanceCommitSaga(value):let identity=affected[0];guard case nil = try fieldDraftRow(identity) else{throw WorkspaceMutationFailureV1.sequenceCollision};guard let predecessorID=value.predecessorSagaID,case let .saga(prior)?=try fieldDraftRow(.init(kind:.draftCommitSaga,id:predecessorID)),try !fieldDraftSagaSuccessorExists(predecessorID)else{throw WorkspaceMutationFailureV1.invalidCommand};let predecessor=try prior.value();try value.validateSuccessor(of:predecessor);guard predecessor.revision==mutation.expectedRevision else{throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind:.draftCommitSaga,id:predecessorID))};modelContext.insert(try DraftCommitSagaRow(value))
        case let .appendContentReservation(value):let identity=affected[0];guard case nil = try fieldDraftRow(identity) else{throw WorkspaceMutationFailureV1.sequenceCollision};guard let checkpoint=try exactDraftCheckpoint(value.draftID,workspaceID:value.workspaceID),checkpoint.stageIDs.contains(value.stageID)else{throw WorkspaceMutationFailureV1.invalidCommand};modelContext.insert(try DraftContentReservationRow(value))
        case let .reviseContentReservation(value):let identity=affected[0];guard case let .reservation(row)?=try fieldDraftRow(identity)else{throw WorkspaceMutationFailureV1.staleEntityRevision(identity)};try row.replace(with:value,expectedRevision:mutation.expectedRevision)
        case let .applyCommitTerminal(bundle,expectedSagaRevision):try applyFieldDraftCommitTerminal(bundle,expectedDraftRevision:mutation.expectedRevision,expectedSagaRevision:expectedSagaRevision)
        case let .applyDiscardTerminal(bundle):try applyFieldDraftDiscardTerminal(bundle,expectedDraftRevision:mutation.expectedRevision)
        };return try WorkspaceMutationEffectV1(affectedEntities:affected,temporaryRelativePath:temporaryRelativePath)}catch let failure as WorkspaceMutationFailureV1{modelContext.rollback();throw failure}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}}
    private enum FieldDraftStoredRow{case checkpoint(FieldDraftCheckpointRow),stage(AttachmentStagingItemRow),saga(DraftCommitSagaRow),reservation(DraftContentReservationRow),commitReceipt(DraftCommitReceiptRow),discardReceipt(DraftDiscardReceiptRow)}
    private func fieldDraftRow(_ identity:WorkspaceEntityIdentityV1)throws->FieldDraftStoredRow?{let id=identity.id;switch identity.kind{case .fieldDraftCheckpoint:let rows=try modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>(predicate:#Predicate{$0.draftID==id}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return rows.first.map(FieldDraftStoredRow.checkpoint);case .attachmentStagingItem:let rows=try modelContext.fetch(FetchDescriptor<AttachmentStagingItemRow>(predicate:#Predicate{$0.stageID==id}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return rows.first.map(FieldDraftStoredRow.stage);case .draftCommitSaga:let rows=try modelContext.fetch(FetchDescriptor<DraftCommitSagaRow>(predicate:#Predicate{$0.sagaID==id}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return rows.first.map(FieldDraftStoredRow.saga);case .draftContentReservation:let rows=try modelContext.fetch(FetchDescriptor<DraftContentReservationRow>(predicate:#Predicate{$0.reservationID==id}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return rows.first.map(FieldDraftStoredRow.reservation);case .draftCommitReceipt:let rows=try modelContext.fetch(FetchDescriptor<DraftCommitReceiptRow>(predicate:#Predicate{$0.receiptID==id}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return rows.first.map(FieldDraftStoredRow.commitReceipt);case .draftDiscardReceipt:let rows=try modelContext.fetch(FetchDescriptor<DraftDiscardReceiptRow>(predicate:#Predicate{$0.receiptID==id}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return rows.first.map(FieldDraftStoredRow.discardReceipt);default:return nil}}
    private func exactDraftCheckpoint(_ draftID:UUID,workspaceID:WorkspaceID)throws->FieldDraftCheckpointV1?{guard case let .checkpoint(row)?=try fieldDraftRow(.init(kind:.fieldDraftCheckpoint,id:draftID))else{return nil};let value=try row.value();guard value.workspaceID==workspaceID else{throw WorkspaceMutationFailureV1.invalidCommand};return value}
    private func fieldDraftSagaSuccessorExists(_ predecessorID:UUID)throws->Bool{let rows=try modelContext.fetch(FetchDescriptor<DraftCommitSagaRow>(predicate:#Predicate{$0.predecessorSagaID==predecessorID}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return !rows.isEmpty}
    private func applyFieldDraftCommitTerminal(_ bundle:DraftCommitTerminalBundleV1,expectedDraftRevision:UInt64,expectedSagaRevision:UInt64)throws{try bundle.validate();let checkpointIdentity=try WorkspaceEntityIdentityV1(kind:.fieldDraftCheckpoint,id:bundle.committedCheckpoint.draftID),sagaIdentity=try WorkspaceEntityIdentityV1(kind:.draftCommitSaga,id:bundle.retiredSaga.sagaID),receiptIdentity=try WorkspaceEntityIdentityV1(kind:.draftCommitReceipt,id:bundle.receipt.receiptID);guard case let .checkpoint(checkpointRow)?=try fieldDraftRow(checkpointIdentity),case nil=try fieldDraftRow(sagaIdentity),case nil=try fieldDraftRow(receiptIdentity),let predecessorID=bundle.retiredSaga.predecessorSagaID,case let .saga(predecessorRow)?=try fieldDraftRow(.init(kind:.draftCommitSaga,id:predecessorID)),try !fieldDraftSagaSuccessorExists(predecessorID),try !fieldDraftCommitReceiptExists(sagaID:bundle.retiredSaga.sagaID)else{throw WorkspaceMutationFailureV1.invalidCommand};let checkpoint=try checkpointRow.value(),predecessor=try predecessorRow.value();try bundle.committedCheckpoint.validateSuccessor(of:checkpoint,expectedDraftRevision:expectedDraftRevision,expectedBaseRevision:checkpoint.baseCanonicalRevision);try bundle.retiredSaga.validateSuccessor(of:predecessor);guard predecessor.revision==expectedSagaRevision,try fieldDraftSagaDigestChain(endingAt:predecessor)+[bundle.retiredSaga.sagaSHA256]==bundle.receipt.sagaEventSHA256Chain,try fieldDraftConsumedContent(for:bundle.retiredSaga.plan)==bundle.receipt.consumedStageToContentID else{throw WorkspaceMutationFailureV1.invalidCommand};try checkpointRow.replace(with:bundle.committedCheckpoint,expectedRevision:expectedDraftRevision);modelContext.insert(try DraftCommitSagaRow(bundle.retiredSaga));modelContext.insert(try DraftCommitReceiptRow(bundle.receipt))}
    private func applyFieldDraftDiscardTerminal(_ bundle:DraftDiscardTerminalBundleV1,expectedDraftRevision:UInt64)throws{try bundle.validate();let checkpointIdentity=try WorkspaceEntityIdentityV1(kind:.fieldDraftCheckpoint,id:bundle.discardedCheckpoint.draftID),receiptIdentity=try WorkspaceEntityIdentityV1(kind:.draftDiscardReceipt,id:bundle.receipt.receiptID);guard case let .checkpoint(checkpointRow)?=try fieldDraftRow(checkpointIdentity),case nil=try fieldDraftRow(receiptIdentity),try !fieldDraftDiscardReceiptExists(draftID:bundle.discardedCheckpoint.draftID)else{throw WorkspaceMutationFailureV1.invalidCommand};let checkpoint=try checkpointRow.value();try bundle.discardedCheckpoint.validateSuccessor(of:checkpoint,expectedDraftRevision:expectedDraftRevision,expectedBaseRevision:checkpoint.baseCanonicalRevision);try checkpointRow.replace(with:bundle.discardedCheckpoint,expectedRevision:expectedDraftRevision);modelContext.insert(try DraftDiscardReceiptRow(bundle.receipt))}
    private func fieldDraftCommitReceiptExists(sagaID:UUID)throws->Bool{let id=sagaID;let rows=try modelContext.fetch(FetchDescriptor<DraftCommitReceiptRow>(predicate:#Predicate{$0.sagaID==id}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return !rows.isEmpty}
    private func fieldDraftDiscardReceiptExists(draftID:UUID)throws->Bool{let id=draftID;let rows=try modelContext.fetch(FetchDescriptor<DraftDiscardReceiptRow>(predicate:#Predicate{$0.draftID==id}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return !rows.isEmpty}
    private func fieldDraftConsumedContent(for plan:DraftCommitPlanV1)throws->[String:String]{let values=try modelContext.fetch(FetchDescriptor<DraftContentReservationRow>()).map{try $0.value()}.filter{$0.workspaceID==plan.workspaceID&&$0.draftID==plan.draftID&&$0.commitPlanSHA256==plan.planSHA256};guard values.count==plan.stageDigests.count,Set(values.map(\.stageID)).count==values.count else{throw WorkspaceMutationFailureV1.invalidCommand};return Dictionary(uniqueKeysWithValues:values.map{($0.stageID.uuidString,$0.locator.contentID)})}
    private func fieldDraftSagaDigestChain(endingAt terminal:DraftCommitSagaV1)throws->[String]{var current:DraftCommitSagaV1?=terminal;var seen=Set<UUID>();var reverse:[String]=[];while let saga=current{guard seen.insert(saga.sagaID).inserted else{throw WorkspaceMutationFailureV1.persistenceFailed};reverse.append(saga.sagaSHA256);if let predecessorID=saga.predecessorSagaID{guard case let .saga(row)?=try fieldDraftRow(.init(kind:.draftCommitSaga,id:predecessorID))else{throw WorkspaceMutationFailureV1.invalidCommand};current=try row.value()}else{current=nil}};return Array(reverse.reversed())}

    private func applyInspectionReview(_ mutation:InspectionReviewMutationV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{
        do{
            try mutation.validate();let affected=try mutation.affectedIdentities
            for identity in affected{guard try !inspectionReviewRowExists(identity)else{throw WorkspaceMutationFailureV1.sequenceCollision}}
            if let predecessor=try mutation.postImage.predecessorIdentity{
                let prior=try inspectionReviewRevision(predecessor)
                guard prior.workspaceID==mutation.workspaceID,prior.revision==mutation.expectedRevision,prior.revision<UInt64.max,mutation.postImage.revision==prior.revision+1,try !inspectionReviewSuccessorExists(predecessor)else{throw WorkspaceMutationFailureV1.staleEntityRevision(predecessor)}
                try validateInspectionReviewSuccessor(mutation.postImage,predecessor:predecessor)
            }
            switch mutation.postImage{
            case let .applyReviewBundle(b):let v=b.transition;try requireExactActor(v.actor);let candidateTransitions=try modelContext.fetch(FetchDescriptor<InspectionReviewTransitionRow>()).map{try $0.value()}+[v];let candidateDispositions=try modelContext.fetch(FetchDescriptor<ReviewDispositionRow>()).map{try $0.value()}+(b.disposition.map{[$0]} ?? []);let candidateRequests=try modelContext.fetch(FetchDescriptor<ChangeRequestRow>()).map{try $0.value()}+b.changeRequests;_ = try InspectionReviewProjectionBuilderV1.rebuild(workspaceID:v.workspaceID,reviewID:v.reviewID,transitions:candidateTransitions,dispositions:candidateDispositions,changeRequests:candidateRequests);if let d=b.disposition{try requireExactActor(d.reviewer);if let id=d.assuranceManifestID{let manifest=try requireAssuranceManifest(id,workspaceID:d.workspaceID);guard manifest.revision==d.assuranceManifestRevision,manifest.manifestSHA256==d.assuranceManifestSHA256 else{throw WorkspaceMutationFailureV1.invalidCommand}};if let predecessor=d.supersedesDispositionID{let predecessorRows=try modelContext.fetch(FetchDescriptor<ReviewDispositionRow>(predicate:#Predicate{$0.dispositionID==predecessor}));guard predecessorRows.count==1,let predecessorValue=try predecessorRows.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};try d.validateSuccessor(of:predecessorValue);try requireInspectionReviewSuccessor(.reviewDisposition,predecessor,valueRevision:d.revision,workspaceID:d.workspaceID)};modelContext.insert(try ReviewDispositionRow(d))};for r in b.changeRequests{try requireExactActor(r.requester);if let resolution=r.resolution{try requireExactActor(resolution.resolver)};if let predecessor=r.supersedesRequestRevisionID{try requireInspectionReviewSuccessor(.changeRequest,predecessor,valueRevision:r.revision,workspaceID:r.workspaceID)};modelContext.insert(try ChangeRequestRow(r))};modelContext.insert(try InspectionReviewTransitionRow(v))
            case let .appendCorrectivePolicy(v),let .supersedeCorrectivePolicy(v):modelContext.insert(try CorrectiveActionPolicyRow(v))
            case let .appendCorrectiveEvent(v),let .appendCorrectiveEventSuccessor(v):let policy=try requireCorrectivePolicy(v.policy.releaseID,workspaceID:v.workspaceID);guard try CorrectiveActionPolicyReferenceV1(policy)==v.policy else{throw WorkspaceMutationFailureV1.invalidCommand};try requireExactActor(v.recorder);if let verifier=v.verifier{try requireExactActor(verifier)};if v.predecessorEventID==nil{try v.validateAdmission(policy:policy)};modelContext.insert(try CorrectiveActionEventRow(v))
            }
            return try WorkspaceMutationEffectV1(affectedEntities:affected,temporaryRelativePath:temporaryRelativePath)
        }catch let f as WorkspaceMutationFailureV1{modelContext.rollback();throw f}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}
    }
    private func inspectionReviewRowExists(_ i:WorkspaceEntityIdentityV1)throws->Bool{let id=i.id;switch i.kind{case .inspectionReviewTransition:return try uniquePresence(modelContext.fetch(FetchDescriptor<InspectionReviewTransitionRow>(predicate:#Predicate{$0.transitionID==id})));case .reviewDisposition:return try uniquePresence(modelContext.fetch(FetchDescriptor<ReviewDispositionRow>(predicate:#Predicate{$0.dispositionID==id})));case .changeRequest:return try uniquePresence(modelContext.fetch(FetchDescriptor<ChangeRequestRow>(predicate:#Predicate{$0.requestRevisionID==id})));case .correctiveActionPolicy:return try uniquePresence(modelContext.fetch(FetchDescriptor<CorrectiveActionPolicyRow>(predicate:#Predicate{$0.releaseID==id})));case .correctiveActionEvent:return try uniquePresence(modelContext.fetch(FetchDescriptor<CorrectiveActionEventRow>(predicate:#Predicate{$0.eventID==id})));default:return false}}
    private func inspectionReviewRevision(_ i:WorkspaceEntityIdentityV1)throws->(workspaceID:WorkspaceID,revision:UInt64){let id=i.id;switch i.kind{case .inspectionReviewTransition:let r=try modelContext.fetch(FetchDescriptor<InspectionReviewTransitionRow>(predicate:#Predicate{$0.transitionID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return(v.workspaceID,v.revision);case .reviewDisposition:let r=try modelContext.fetch(FetchDescriptor<ReviewDispositionRow>(predicate:#Predicate{$0.dispositionID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return(v.workspaceID,v.revision);case .changeRequest:let r=try modelContext.fetch(FetchDescriptor<ChangeRequestRow>(predicate:#Predicate{$0.requestRevisionID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return(v.workspaceID,v.revision);case .correctiveActionPolicy:let r=try modelContext.fetch(FetchDescriptor<CorrectiveActionPolicyRow>(predicate:#Predicate{$0.releaseID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return(v.workspaceID,v.revision);case .correctiveActionEvent:let r=try modelContext.fetch(FetchDescriptor<CorrectiveActionEventRow>(predicate:#Predicate{$0.eventID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return(v.workspaceID,v.revision);default:throw WorkspaceMutationFailureV1.invalidCommand}}
    private func inspectionReviewSuccessorExists(_ p:WorkspaceEntityIdentityV1)throws->Bool{let id=p.id;let count:Int;switch p.kind{case .inspectionReviewTransition:count=try modelContext.fetch(FetchDescriptor<InspectionReviewTransitionRow>()).map{try $0.value()}.filter{$0.predecessorTransitionID==id}.count;case .reviewDisposition:count=try modelContext.fetch(FetchDescriptor<ReviewDispositionRow>()).map{try $0.value()}.filter{$0.supersedesDispositionID==id}.count;case .changeRequest:count=try modelContext.fetch(FetchDescriptor<ChangeRequestRow>()).map{try $0.value()}.filter{$0.supersedesRequestRevisionID==id}.count;case .correctiveActionPolicy:count=try modelContext.fetch(FetchDescriptor<CorrectiveActionPolicyRow>()).map{try $0.value()}.filter{$0.supersedesReleaseID==id}.count;case .correctiveActionEvent:count=try modelContext.fetch(FetchDescriptor<CorrectiveActionEventRow>()).map{try $0.value()}.filter{$0.predecessorEventID==id}.count;default:throw WorkspaceMutationFailureV1.invalidCommand};guard count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return count==1}
    private func validateInspectionReviewSuccessor(_ payload:InspectionReviewMutationPayloadV1,predecessor:WorkspaceEntityIdentityV1)throws{let id=predecessor.id;switch payload{case let .applyReviewBundle(b):let r=try modelContext.fetch(FetchDescriptor<InspectionReviewTransitionRow>(predicate:#Predicate{$0.transitionID==id}));guard r.count==1,let p=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};try b.transition.validateSuccessor(of:p);case let .supersedeCorrectivePolicy(v):let r=try modelContext.fetch(FetchDescriptor<CorrectiveActionPolicyRow>(predicate:#Predicate{$0.releaseID==id}));guard r.count==1,let p=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};try v.validateSuccessor(of:p);case let .appendCorrectiveEventSuccessor(v):let r=try modelContext.fetch(FetchDescriptor<CorrectiveActionEventRow>(predicate:#Predicate{$0.eventID==id}));guard r.count==1,let p=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};let policy=try requireCorrectivePolicy(v.policy.releaseID,workspaceID:v.workspaceID);try v.validateSuccessor(of:p,policy:policy);default:throw WorkspaceMutationFailureV1.invalidCommand}}
    private func requireInspectionReviewSuccessor(_ kind:WorkspaceEntityKindV1,_ predecessorID:UUID,valueRevision:UInt64,workspaceID:WorkspaceID)throws{let identity=try WorkspaceEntityIdentityV1(kind:kind,id:predecessorID);let prior=try inspectionReviewRevision(identity);guard prior.workspaceID==workspaceID,prior.revision<UInt64.max,valueRevision==prior.revision+1,try !inspectionReviewSuccessorExists(identity)else{throw WorkspaceMutationFailureV1.staleEntityRevision(identity)}}
    private func requireCorrectivePolicy(_ id:UUID,workspaceID:WorkspaceID)throws->CorrectiveActionPolicyV1{let r=try modelContext.fetch(FetchDescriptor<CorrectiveActionPolicyRow>(predicate:#Predicate{$0.releaseID==id}));guard r.count==1,let v=try r.first?.value(),v.workspaceID==workspaceID else{throw WorkspaceMutationFailureV1.invalidCommand};return v}
    private func requireReviewBindings(reviewID:UUID,workspaceID:WorkspaceID,subject:InspectionReviewSubjectReferenceV1,reviewRevision:UInt64,mutationID:MutationIDV1,dispositionID:UUID?,changeRequestIDs:[UUID])throws{try requireCurrentChangeRequests(changeRequestIDs,reviewID:reviewID,workspaceID:workspaceID);if let id=dispositionID{let rows=try modelContext.fetch(FetchDescriptor<ReviewDispositionRow>(predicate:#Predicate{$0.dispositionID==id}));guard rows.count==1,let v=try rows.first?.value(),v.workspaceID==workspaceID,v.reviewID==reviewID,v.subject==subject,v.reviewRevision==reviewRevision,v.mutationID==mutationID else{throw WorkspaceMutationFailureV1.invalidCommand}}}
    private func requireCurrentChangeRequests(_ ids:[UUID],reviewID:UUID,workspaceID:WorkspaceID)throws{let all=try modelContext.fetch(FetchDescriptor<ChangeRequestRow>()).map{try $0.value()};for id in ids{let matching=all.filter{$0.requestID==id};guard let head=matching.max(by:{$0.revision<$1.revision}),head.workspaceID==workspaceID,head.reviewID==reviewID else{throw WorkspaceMutationFailureV1.invalidCommand}}}

    private func applyEvidenceAssurance(_ mutation:EvidenceAssuranceMutationV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{
        do{try mutation.validate();let affected=try mutation.affectedIdentity;guard try !evidenceAssuranceRowExists(affected)else{throw WorkspaceMutationFailureV1.sequenceCollision};if let predecessor=try mutation.postImage.predecessorIdentity{let prior=try evidenceAssuranceRevision(predecessor);guard prior.workspaceID==mutation.workspaceID,prior.revision==mutation.expectedRevision,prior.revision<UInt64.max,mutation.postImage.revision==prior.revision+1,try !evidenceAssuranceSuccessorExists(predecessor)else{throw WorkspaceMutationFailureV1.staleEntityRevision(predecessor)};try validateEvidenceAssuranceSuccessor(mutation.postImage,predecessor:predecessor)}
            switch mutation.postImage{case let .appendVisibility(v),let .supersedeVisibility(v):modelContext.insert(try EvidenceVisibilityRow(v));case let .appendLink(v),let .supersedeLink(v):let visibility=try requireEvidenceVisibility(v.visibilityID,workspaceID:v.workspaceID);try v.validate(visibility:visibility);modelContext.insert(try ClaimEvidenceLinkRow(v));case let .appendManifest(v,p),let .supersedeManifest(v,p):try requireFreshAssurancePreview(p);try v.validateFresh(preview:p);modelContext.insert(try AssuranceManifestRow(v));case let .recordAttestation(v,m),let .supersedeAttestation(v,m),let .voidAttestation(v,m):let stored=try requireAssuranceManifest(v.manifestID,workspaceID:v.workspaceID);guard stored==m else{throw WorkspaceMutationFailureV1.invalidCommand};try v.validate(manifest:stored);modelContext.insert(try AttestationRow(v))}
            return try WorkspaceMutationEffectV1(affectedEntities:[affected],temporaryRelativePath:temporaryRelativePath)
        }catch let f as WorkspaceMutationFailureV1{modelContext.rollback();throw f}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}
    }
    private func evidenceAssuranceRowExists(_ i:WorkspaceEntityIdentityV1)throws->Bool{let id=i.id;switch i.kind{case .evidenceVisibility:return try uniquePresence(modelContext.fetch(FetchDescriptor<EvidenceVisibilityRow>(predicate:#Predicate{$0.visibilityID==id})));case .claimEvidenceLink:return try uniquePresence(modelContext.fetch(FetchDescriptor<ClaimEvidenceLinkRow>(predicate:#Predicate{$0.linkID==id})));case .assuranceManifest:return try uniquePresence(modelContext.fetch(FetchDescriptor<AssuranceManifestRow>(predicate:#Predicate{$0.manifestID==id})));case .attestation:return try uniquePresence(modelContext.fetch(FetchDescriptor<AttestationRow>(predicate:#Predicate{$0.attestationID==id})));default:return false}}
    private func evidenceAssuranceRevision(_ i:WorkspaceEntityIdentityV1)throws->(workspaceID:WorkspaceID,revision:UInt64){let id=i.id;switch i.kind{case .evidenceVisibility:let r=try modelContext.fetch(FetchDescriptor<EvidenceVisibilityRow>(predicate:#Predicate{$0.visibilityID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return(v.workspaceID,v.revision);case .claimEvidenceLink:let r=try modelContext.fetch(FetchDescriptor<ClaimEvidenceLinkRow>(predicate:#Predicate{$0.linkID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return(v.workspaceID,v.revision);case .assuranceManifest:let r=try modelContext.fetch(FetchDescriptor<AssuranceManifestRow>(predicate:#Predicate{$0.manifestID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return(v.workspaceID,v.revision);case .attestation:let r=try modelContext.fetch(FetchDescriptor<AttestationRow>(predicate:#Predicate{$0.attestationID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return(v.workspaceID,v.revision);default:throw WorkspaceMutationFailureV1.invalidCommand}}
    private func evidenceAssuranceSuccessorExists(_ p:WorkspaceEntityIdentityV1)throws->Bool{let id=p.id;let count:Int;switch p.kind{case .evidenceVisibility:count=try modelContext.fetch(FetchDescriptor<EvidenceVisibilityRow>()).map{try $0.value()}.filter{$0.supersedesVisibilityID==id}.count;case .claimEvidenceLink:count=try modelContext.fetch(FetchDescriptor<ClaimEvidenceLinkRow>()).map{try $0.value()}.filter{$0.supersedesLinkID==id}.count;case .assuranceManifest:count=try modelContext.fetch(FetchDescriptor<AssuranceManifestRow>()).map{try $0.value()}.filter{$0.supersedesManifestID==id}.count;case .attestation:count=try modelContext.fetch(FetchDescriptor<AttestationRow>()).map{try $0.value()}.filter{$0.supersedesAttestationID==id}.count;default:throw WorkspaceMutationFailureV1.invalidCommand};guard count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return count==1}
    private func validateEvidenceAssuranceSuccessor(_ payload:EvidenceAssuranceMutationPayloadV1,predecessor:WorkspaceEntityIdentityV1)throws{let id=predecessor.id;switch payload{case let .supersedeVisibility(v):let r=try modelContext.fetch(FetchDescriptor<EvidenceVisibilityRow>(predicate:#Predicate{$0.visibilityID==id}));guard r.count==1,let p=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};try v.validateSuccessor(of:p);case let .supersedeLink(v):let r=try modelContext.fetch(FetchDescriptor<ClaimEvidenceLinkRow>(predicate:#Predicate{$0.linkID==id}));guard r.count==1,let p=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};let visibility=try requireEvidenceVisibility(v.visibilityID,workspaceID:v.workspaceID);try v.validateSuccessor(of:p,visibility:visibility);case let .supersedeManifest(v,_):let r=try modelContext.fetch(FetchDescriptor<AssuranceManifestRow>(predicate:#Predicate{$0.manifestID==id}));guard r.count==1,let p=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};try v.validateSuccessor(of:p);case let .supersedeAttestation(v,_),let .voidAttestation(v,_):let r=try modelContext.fetch(FetchDescriptor<AttestationRow>(predicate:#Predicate{$0.attestationID==id}));guard r.count==1,let p=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};try v.validateSuccessor(of:p);default:throw WorkspaceMutationFailureV1.invalidCommand}}
    private func requireEvidenceVisibility(_ id:UUID,workspaceID:WorkspaceID)throws->EvidenceVisibilityV1{let r=try modelContext.fetch(FetchDescriptor<EvidenceVisibilityRow>(predicate:#Predicate{$0.visibilityID==id}));guard r.count==1,let v=try r.first?.value(),v.workspaceID==workspaceID else{throw WorkspaceMutationFailureV1.invalidCommand};return v}
    private func requireAssuranceManifest(_ id:UUID,workspaceID:WorkspaceID)throws->AssuranceManifestV1{let r=try modelContext.fetch(FetchDescriptor<AssuranceManifestRow>(predicate:#Predicate{$0.manifestID==id}));guard r.count==1,let v=try r.first?.value(),v.workspaceID==workspaceID else{throw WorkspaceMutationFailureV1.invalidCommand};return v}
    private func requireFreshAssurancePreview(_ preview:AssuranceProjectionPreviewV1)throws{let raw=preview.workspaceID.rawValue;let all=try modelContext.fetch(FetchDescriptor<ClaimEvidenceLinkRow>(predicate:#Predicate{$0.workspaceID==raw})).map{try $0.value()};let superseded=Set(all.compactMap(\.supersedesLinkID));let current=all.filter{!superseded.contains($0.linkID)&&$0.decision.audience==preview.audience};let rebuilt=try AssuranceProjectionPreviewV1(previewID:preview.previewID,workspaceID:preview.workspaceID,audience:preview.audience,snapshotSHA256:preview.snapshotSHA256,projectionVersion:preview.projectionVersion,links:current,createdAt:preview.createdAt);guard rebuilt==preview else{throw WorkspaceMutationFailureV1.invalidCommand}}

    private func applyFunctionalRelationship(
        _ mutation: FunctionalRelationshipMutationV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        do {
            try mutation.validate()
            let affected = try mutation.affectedIdentity
            guard try !functionalRelationshipRowExists(affected) else {
                throw WorkspaceMutationFailureV1.sequenceCollision
            }
            if let predecessor = try mutation.postImage.predecessorIdentity {
                let prior = try functionalRelationshipValue(predecessor)
                guard prior.workspaceID == mutation.workspaceID,
                      prior.revision == mutation.expectedRevision,
                      prior.revision < UInt64.max,
                      mutation.postImage.revision == prior.revision + 1,
                      try !functionalRelationshipSuccessorExists(predecessor) else {
                    throw WorkspaceMutationFailureV1.staleEntityRevision(predecessor)
                }
                switch mutation.postImage {
                case let .supersedeDescriptor(value):
                    let id = predecessor.id
                    let rows = try modelContext.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>(predicate: #Predicate { $0.descriptorReleaseID == id }))
                    guard rows.count == 1, let priorValue = try rows.first?.value() else { throw WorkspaceMutationFailureV1.invalidCommand }
                    try value.validateSuccessor(of: priorValue)
                case let .endRelationship(value), let .supersedeRelationship(value):
                    let id = predecessor.id
                    let rows = try modelContext.fetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>(predicate: #Predicate { $0.eventID == id }))
                    guard rows.count == 1, let priorValue = try rows.first?.value() else { throw WorkspaceMutationFailureV1.invalidCommand }
                    try value.validateSuccessor(of: priorValue)
                default: throw WorkspaceMutationFailureV1.invalidCommand
                }
            }
            switch mutation.postImage {
            case let .appendDescriptor(value), let .supersedeDescriptor(value):
                modelContext.insert(try FunctionalRelationshipTypeDescriptorRow(value))
            case let .addRelationship(value), let .endRelationship(value), let .supersedeRelationship(value):
                let descriptorID = value.descriptor.descriptorReleaseID
                let descriptors = try modelContext.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>(
                    predicate: #Predicate { $0.descriptorReleaseID == descriptorID }
                ))
                guard descriptors.count == 1, let descriptorRow = descriptors.first else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                let descriptor = try descriptorRow.value()
                guard descriptor.workspaceID == value.workspaceID,
                      value.descriptor == FunctionalRelationshipDescriptorReferenceV1(descriptor) else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                let source = try functionalRelationshipEndpoint(value.sourceAssetID, workspaceID: value.workspaceID)
                let target = try functionalRelationshipEndpoint(value.targetAssetID, workspaceID: value.workspaceID)
                let existing = try modelContext.fetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>())
                    .map { try $0.value() }.filter { $0.workspaceID == value.workspaceID }
                try FunctionalRelationshipProjectionBuilderV1.validateCandidate(
                    value, source: source, target: target, descriptor: descriptor,
                    existingCurrent: try FunctionalRelationshipProjectionBuilderV1.rebuild(
                        workspaceID: value.workspaceID,
                        events: existing,
                        descriptors: try modelContext.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>()).map { try $0.value() }.filter { $0.workspaceID == value.workspaceID }
                    ).currentRelationships
                )
                modelContext.insert(try AssetFunctionalRelationshipEventRow(value))
            }
            return try WorkspaceMutationEffectV1(
                affectedEntities: [affected], temporaryRelativePath: temporaryRelativePath
            )
        } catch let failure as WorkspaceMutationFailureV1 { modelContext.rollback(); throw failure }
        catch { modelContext.rollback(); throw WorkspaceMutationFailureV1.invalidCommand }
    }

    private func functionalRelationshipEndpoint(
        _ assetID: UUID, workspaceID: WorkspaceID
    ) throws -> FunctionalRelationshipEndpointSnapshotV1 {
        let assets = try modelContext.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetID }))
        guard assets.count == 1, let asset = assets.first else { throw WorkspaceMutationFailureV1.invalidCommand }
        let kindValues = try modelContext.fetch(FetchDescriptor<AssetKindBindingEventRow>())
            .map { try $0.value() }.filter { $0.assetID == assetID && $0.workspaceID == workspaceID }
        guard let kind = kindValues.max(by: { $0.revision < $1.revision }) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let workflowValues = try modelContext.fetch(FetchDescriptor<AssetWorkflowCapabilityBindingEventRow>())
            .map { try $0.value() }.filter {
                $0.assetID == assetID && $0.workspaceID == workspaceID
                    && $0.kindBindingEventID == kind.eventID && $0.disposition == .bound
            }
        let capabilities = workflowValues.max(by: { $0.revision < $1.revision })?.capabilityIDs ?? []
        let identity = try WorkspaceEntityIdentityV1(kind: .asset, id: assetID)
        let key = identity.stableKey
        let revisions = try modelContext.fetch(FetchDescriptor<EntityMutationRevisionRow>(predicate: #Predicate { $0.stableIdentity == key }))
        guard revisions.count == 1, let rawRevision = revisions.first?.revision, rawRevision > 0 else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        return try FunctionalRelationshipEndpointSnapshotV1(
            assetID: assetID, workspaceID: workspaceID, siteID: asset.siteID,
            assetRevision: UInt64(rawRevision), kindBindingEventID: kind.eventID,
            kindBindingRevision: kind.revision, catalogRelease: kind.catalogRelease,
            semanticID: kind.semanticID, capabilityIDs: capabilities
        )
    }

    private func functionalRelationshipRowExists(_ identity: WorkspaceEntityIdentityV1) throws -> Bool {
        let id = identity.id
        switch identity.kind {
        case .functionalRelationshipTypeDescriptor:
            return try uniquePresence(modelContext.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>(predicate: #Predicate { $0.descriptorReleaseID == id })))
        case .assetFunctionalRelationshipEvent:
            return try uniquePresence(modelContext.fetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>(predicate: #Predicate { $0.eventID == id })))
        default: return false
        }
    }

    private func functionalRelationshipValue(
        _ identity: WorkspaceEntityIdentityV1
    ) throws -> (workspaceID: WorkspaceID, revision: UInt64) {
        let id = identity.id
        switch identity.kind {
        case .functionalRelationshipTypeDescriptor:
            let rows = try modelContext.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>(predicate: #Predicate { $0.descriptorReleaseID == id }))
            guard rows.count == 1, let value = try rows.first?.value() else { throw WorkspaceMutationFailureV1.invalidCommand }
            return (value.workspaceID, value.revision)
        case .assetFunctionalRelationshipEvent:
            let rows = try modelContext.fetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>(predicate: #Predicate { $0.eventID == id }))
            guard rows.count == 1, let value = try rows.first?.value() else { throw WorkspaceMutationFailureV1.invalidCommand }
            return (value.workspaceID, value.revision)
        default: throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    private func functionalRelationshipSuccessorExists(_ predecessor: WorkspaceEntityIdentityV1) throws -> Bool {
        let id = predecessor.id
        let count: Int
        switch predecessor.kind {
        case .functionalRelationshipTypeDescriptor:
            count = try modelContext.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>())
                .map { try $0.value() }.filter { $0.supersedesDescriptorReleaseID == id }.count
        case .assetFunctionalRelationshipEvent:
            count = try modelContext.fetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>())
                .map { try $0.value() }.filter { $0.predecessorEventID == id }.count
        default: throw WorkspaceMutationFailureV1.invalidCommand
        }
        guard count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
        return count == 1
    }

    private func applyAuthorityCriterion(
        _ mutation: AuthorityCriterionMutationV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        do {
            try mutation.validate()
            let identity = try mutation.affectedIdentity
            try validateAuthorityCriterionReferences(mutation.postImage)
            if let predecessor = try mutation.postImage.predecessorIdentity {
                let prior = try authorityCriterionRevision(predecessor)
                guard prior.workspaceID == mutation.workspaceID,
                      prior.revision < UInt64.max,
                      prior.revision + 1 == mutation.postImage.revision else {
                    throw WorkspaceMutationFailureV1.staleEntityRevision(predecessor)
                }
                guard try !authorityCriterionSuccessorExists(predecessor) else {
                    throw WorkspaceMutationFailureV1.sequenceCollision
                }
            }
            guard try !authorityCriterionRowExists(identity) else {
                throw WorkspaceMutationFailureV1.sequenceCollision
            }
            switch mutation.postImage {
            case .appendAuthoritySource(let v), .supersedeAuthoritySource(let v): modelContext.insert(try AuthoritySourceReleaseRow(v))
            case .appendRequirementBasis(let v), .supersedeRequirementBasis(let v): modelContext.insert(try RequirementBasisBindingRow(v))
            case .appendApplicabilityContext(let v), .supersedeApplicabilityContext(let v): modelContext.insert(try ApplicabilityContextSnapshotRow(v))
            case .appendAssessmentScope(let v), .supersedeAssessmentScope(let v): modelContext.insert(try AssessmentScopeSnapshotRow(v))
            case .appendSeverityScale(let v), .supersedeSeverityScale(let v): modelContext.insert(try SeverityScaleReleaseRow(v))
            case .appendFindingClassification(let v), .supersedeFindingClassification(let v): modelContext.insert(try FindingClassificationBindingRow(v))
            case .appendMeasurementProtocol(let v), .supersedeMeasurementProtocol(let v): modelContext.insert(try MeasurementProtocolReleaseRow(v))
            case .appendEvaluatorDescriptor(let v), .supersedeEvaluatorDescriptor(let v): modelContext.insert(try DerivedFactEvaluatorDescriptorRow(v))
            case .appendDerivedFact(let v), .supersedeDerivedFact(let v): modelContext.insert(try DerivedFactProvenanceRow(v))
            }
            return try WorkspaceMutationEffectV1(affectedEntities: [identity], temporaryRelativePath: temporaryRelativePath)
        } catch let failure as WorkspaceMutationFailureV1 {
            modelContext.rollback(); throw failure
        } catch {
            modelContext.rollback(); throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    private func authorityCriterionRowExists(_ identity: WorkspaceEntityIdentityV1) throws -> Bool {
        let id = identity.id
        switch identity.kind {
        case .authoritySourceRelease: return try uniquePresence(modelContext.fetch(FetchDescriptor<AuthoritySourceReleaseRow>(predicate: #Predicate { $0.releaseID == id })))
        case .requirementBasisBinding: return try uniquePresence(modelContext.fetch(FetchDescriptor<RequirementBasisBindingRow>(predicate: #Predicate { $0.bindingID == id })))
        case .applicabilityContextSnapshot: return try uniquePresence(modelContext.fetch(FetchDescriptor<ApplicabilityContextSnapshotRow>(predicate: #Predicate { $0.snapshotID == id })))
        case .assessmentScopeSnapshot: return try uniquePresence(modelContext.fetch(FetchDescriptor<AssessmentScopeSnapshotRow>(predicate: #Predicate { $0.snapshotID == id })))
        case .severityScaleRelease: return try uniquePresence(modelContext.fetch(FetchDescriptor<SeverityScaleReleaseRow>(predicate: #Predicate { $0.releaseID == id })))
        case .findingClassificationBinding: return try uniquePresence(modelContext.fetch(FetchDescriptor<FindingClassificationBindingRow>(predicate: #Predicate { $0.bindingID == id })))
        case .measurementProtocolRelease: return try uniquePresence(modelContext.fetch(FetchDescriptor<MeasurementProtocolReleaseRow>(predicate: #Predicate { $0.releaseID == id })))
        case .derivedFactEvaluatorDescriptor: return try uniquePresence(modelContext.fetch(FetchDescriptor<DerivedFactEvaluatorDescriptorRow>(predicate: #Predicate { $0.descriptorID == id })))
        case .derivedFactProvenance: return try uniquePresence(modelContext.fetch(FetchDescriptor<DerivedFactProvenanceRow>(predicate: #Predicate { $0.provenanceID == id })))
        default: return false
        }
    }

    private func uniquePresence<T>(_ rows: [T]) throws -> Bool {
        guard rows.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
        return rows.count == 1
    }

    private func authorityCriterionSuccessorExists(
        _ predecessor: WorkspaceEntityIdentityV1
    ) throws -> Bool {
        let id = predecessor.id
        let count: Int
        switch predecessor.kind {
        case .authoritySourceRelease:
            count = try modelContext.fetch(FetchDescriptor<AuthoritySourceReleaseRow>()).map { try $0.value() }.filter { $0.supersedesReleaseID == id }.count
        case .requirementBasisBinding:
            count = try modelContext.fetch(FetchDescriptor<RequirementBasisBindingRow>()).map { try $0.value() }.filter { $0.supersedesBindingID == id }.count
        case .applicabilityContextSnapshot:
            count = try modelContext.fetch(FetchDescriptor<ApplicabilityContextSnapshotRow>()).map { try $0.value() }.filter { $0.supersedesSnapshotID == id }.count
        case .assessmentScopeSnapshot:
            count = try modelContext.fetch(FetchDescriptor<AssessmentScopeSnapshotRow>()).map { try $0.value() }.filter { $0.supersedesSnapshotID == id }.count
        case .severityScaleRelease:
            count = try modelContext.fetch(FetchDescriptor<SeverityScaleReleaseRow>()).map { try $0.value() }.filter { $0.supersedesReleaseID == id }.count
        case .findingClassificationBinding:
            count = try modelContext.fetch(FetchDescriptor<FindingClassificationBindingRow>()).map { try $0.value() }.filter { $0.supersedesBindingID == id }.count
        case .measurementProtocolRelease:
            count = try modelContext.fetch(FetchDescriptor<MeasurementProtocolReleaseRow>()).map { try $0.value() }.filter { $0.supersedesReleaseID == id }.count
        case .derivedFactEvaluatorDescriptor:
            count = try modelContext.fetch(FetchDescriptor<DerivedFactEvaluatorDescriptorRow>()).map { try $0.value() }.filter { $0.supersedesDescriptorID == id }.count
        case .derivedFactProvenance:
            count = try modelContext.fetch(FetchDescriptor<DerivedFactProvenanceRow>()).map { try $0.value() }.filter { $0.predecessorProvenanceID == id }.count
        default: throw WorkspaceMutationFailureV1.invalidCommand
        }
        guard count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
        return count == 1
    }

    private func authorityCriterionRevision(
        _ identity: WorkspaceEntityIdentityV1
    ) throws -> (workspaceID: WorkspaceID, revision: UInt64) {
        let id = identity.id
        switch identity.kind {
        case .authoritySourceRelease:
            let r=try modelContext.fetch(FetchDescriptor<AuthoritySourceReleaseRow>(predicate:#Predicate{$0.releaseID == id})); guard r.count==1,let v=try r.first?.value() else{throw WorkspaceMutationFailureV1.invalidCommand}; return(v.workspaceID,v.revision)
        case .requirementBasisBinding:
            let r=try modelContext.fetch(FetchDescriptor<RequirementBasisBindingRow>(predicate:#Predicate{$0.bindingID == id})); guard r.count==1,let v=try r.first?.value() else{throw WorkspaceMutationFailureV1.invalidCommand}; return(v.workspaceID,v.revision)
        case .applicabilityContextSnapshot:
            let r=try modelContext.fetch(FetchDescriptor<ApplicabilityContextSnapshotRow>(predicate:#Predicate{$0.snapshotID == id})); guard r.count==1,let v=try r.first?.value() else{throw WorkspaceMutationFailureV1.invalidCommand}; return(v.workspaceID,v.revision)
        case .assessmentScopeSnapshot:
            let r=try modelContext.fetch(FetchDescriptor<AssessmentScopeSnapshotRow>(predicate:#Predicate{$0.snapshotID == id})); guard r.count==1,let v=try r.first?.value() else{throw WorkspaceMutationFailureV1.invalidCommand}; return(v.workspaceID,v.revision)
        case .severityScaleRelease:
            let r=try modelContext.fetch(FetchDescriptor<SeverityScaleReleaseRow>(predicate:#Predicate{$0.releaseID == id})); guard r.count==1,let v=try r.first?.value() else{throw WorkspaceMutationFailureV1.invalidCommand}; return(v.workspaceID,v.revision)
        case .findingClassificationBinding:
            let r=try modelContext.fetch(FetchDescriptor<FindingClassificationBindingRow>(predicate:#Predicate{$0.bindingID == id})); guard r.count==1,let v=try r.first?.value() else{throw WorkspaceMutationFailureV1.invalidCommand}; return(v.workspaceID,v.revision)
        case .measurementProtocolRelease:
            let r=try modelContext.fetch(FetchDescriptor<MeasurementProtocolReleaseRow>(predicate:#Predicate{$0.releaseID == id})); guard r.count==1,let v=try r.first?.value() else{throw WorkspaceMutationFailureV1.invalidCommand}; return(v.workspaceID,v.revision)
        case .derivedFactEvaluatorDescriptor:
            let r=try modelContext.fetch(FetchDescriptor<DerivedFactEvaluatorDescriptorRow>(predicate:#Predicate{$0.descriptorID == id})); guard r.count==1,let v=try r.first?.value() else{throw WorkspaceMutationFailureV1.invalidCommand}; return(v.workspaceID,v.revision)
        case .derivedFactProvenance:
            let r=try modelContext.fetch(FetchDescriptor<DerivedFactProvenanceRow>(predicate:#Predicate{$0.provenanceID == id})); guard r.count==1,let v=try r.first?.value() else{throw WorkspaceMutationFailureV1.invalidCommand}; return(v.workspaceID,v.revision)
        default: throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    private func validateAuthorityCriterionReferences(
        _ payload: AuthorityCriterionMutationPayloadV1
    ) throws {
        func require(_ kind: WorkspaceEntityKindV1, _ id: UUID, _ workspaceID: WorkspaceID) throws {
            let identity = try WorkspaceEntityIdentityV1(kind: kind, id: id)
            let stored = try authorityCriterionRevision(identity)
            guard stored.workspaceID == workspaceID else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        }
        switch payload {
        case .appendAuthoritySource, .supersedeAuthoritySource,
             .appendSeverityScale, .supersedeSeverityScale,
             .appendEvaluatorDescriptor, .supersedeEvaluatorDescriptor:
            break
        case .appendRequirementBasis(let v), .supersedeRequirementBasis(let v):
            try require(.authoritySourceRelease, v.authorityReleaseID, v.workspaceID)
            try requireExactActor(v.selectedBy)
        case .appendApplicabilityContext(let v), .supersedeApplicabilityContext(let v):
            try requireExactWorkSubjectScope(v.workSubjectScope)
            try requireExactActor(v.actor)
            if let qualification = v.qualification { try requireExactQualification(qualification) }
            for basis in v.basisBindings { try requireExactRequirementBasis(basis) }
        case .appendAssessmentScope(let v), .supersedeAssessmentScope(let v):
            try require(.applicabilityContextSnapshot, v.applicabilityContextID, v.workspaceID)
            try requireExactWorkSubjectScope(v.workSubjectScope)
        case .appendFindingClassification(let v), .supersedeFindingClassification(let v):
            try require(.applicabilityContextSnapshot, v.applicabilityContextID, v.workspaceID)
            try require(.assessmentScopeSnapshot, v.assessmentScopeID, v.workspaceID)
            if let releaseID = v.severityScaleReleaseID {
                let scale = try requireSeverityScale(releaseID, workspaceID: v.workspaceID)
                guard let levelID = v.severityLevelID,
                      scale.levels.contains(where: { $0.levelID == levelID }) else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            }
        case .appendMeasurementProtocol(let v), .supersedeMeasurementProtocol(let v):
            try require(.derivedFactEvaluatorDescriptor, v.evaluatorDescriptorID, v.workspaceID)
        case .appendDerivedFact(let v), .supersedeDerivedFact(let v):
            try require(.measurementProtocolRelease, v.protocolReleaseID, v.workspaceID)
            try require(.derivedFactEvaluatorDescriptor, v.evaluatorDescriptorID, v.workspaceID)
        }
    }

    private func requireExactActor(_ expected: ActorSnapshotV1) throws {
        let id = expected.snapshotID
        let rows = try modelContext.fetch(FetchDescriptor<ActorSnapshotRow>(predicate: #Predicate { $0.snapshotID == id }))
        guard rows.count == 1, let row = rows.first,
              try row.value() == expected else { throw WorkspaceMutationFailureV1.invalidCommand }
    }

    private func requireExactQualification(_ expected: QualificationSnapshotV1) throws {
        let id = expected.snapshotID
        let rows = try modelContext.fetch(FetchDescriptor<QualificationSnapshotRow>(predicate: #Predicate { $0.snapshotID == id }))
        guard rows.count == 1, let row = rows.first,
              try row.value() == expected else { throw WorkspaceMutationFailureV1.invalidCommand }
    }

    private func requireExactWorkSubjectScope(_ expected: WorkSubjectScopeSnapshotV1) throws {
        let id = expected.snapshotID
        let rows = try modelContext.fetch(FetchDescriptor<WorkSubjectScopeSnapshotRow>(predicate: #Predicate { $0.snapshotID == id }))
        guard rows.count == 1, let row = rows.first,
              try row.value() == expected else { throw WorkspaceMutationFailureV1.invalidCommand }
    }

    private func requireExactRequirementBasis(_ expected: RequirementBasisBindingV1) throws {
        let id = expected.bindingID
        let rows = try modelContext.fetch(FetchDescriptor<RequirementBasisBindingRow>(predicate: #Predicate { $0.bindingID == id }))
        guard rows.count == 1, let row = rows.first,
              try row.value() == expected else { throw WorkspaceMutationFailureV1.invalidCommand }
    }

    private func requireSeverityScale(
        _ releaseID: UUID,
        workspaceID: WorkspaceID
    ) throws -> SeverityScaleReleaseV1 {
        let rows = try modelContext.fetch(FetchDescriptor<SeverityScaleReleaseRow>(predicate: #Predicate { $0.releaseID == releaseID }))
        guard rows.count == 1, let row = rows.first else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let value = try row.value()
        guard value.workspaceID == workspaceID else { throw WorkspaceMutationFailureV1.invalidCommand }
        return value
    }

    func queryExisting(
        identities: [WorkspaceEntityIdentityV1]
    ) throws -> (
        identities: [WorkspaceEntityIdentityV1],
        packageBindings: [WorkspacePackageBindingV1]
    ) {
        guard !modelContext.hasChanges,
              identities.count <= 256,
              Set(identities).count == identities.count else {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        var existing: [WorkspaceEntityIdentityV1] = []
        var bindings: [WorkspacePackageBindingV1] = []
        let deletionLedgerRows: [DeletionLedgerRow]
        let deletionLedgerIdentities: [DeletionIdentityV2]
        if identities.contains(where: { $0.kind == .deletionLedgerEntry }) {
            deletionLedgerRows = try modelContext.fetch(FetchDescriptor<DeletionLedgerRow>())
            guard Set(deletionLedgerRows.map(\.typedID)).count == deletionLedgerRows.count else {
                throw WorkspaceMutationFailureV1.persistenceFailed
            }
            do {
                deletionLedgerIdentities = try deletionLedgerRows.map {
                    try DeletionIdentityV2(typedID: $0.typedID)
                }
            } catch {
                throw WorkspaceMutationFailureV1.persistenceFailed
            }
        } else {
            deletionLedgerRows = []
            deletionLedgerIdentities = []
        }
        for identity in identities {
            let id = identity.id
            let exists: Bool
            switch identity.kind {
            case .stockBalanceStream: exists = false
            case .localPartDefinition: exists = try modelContext.fetch(FetchDescriptor<LocalPartDefinitionRowV1>()).contains { $0.partID == id }
            case .stockStorageLocation: exists = try modelContext.fetch(FetchDescriptor<StockStorageLocationRowV1>()).contains { $0.locationID == id }
            case .stockMovementEvent: exists = try modelContext.fetch(FetchDescriptor<StockMovementEventRowV1>()).contains { $0.movementID == id }
            case .stockUseReceipt: exists = try modelContext.fetch(FetchDescriptor<StockUseReceiptRowV1>()).contains { $0.receiptID == id }
            case .stockUseReversalReceipt: exists = try modelContext.fetch(FetchDescriptor<StockUseReversalReceiptRowV1>()).contains { $0.receiptID == id }
            case .stockReturnReceipt: exists = try modelContext.fetch(FetchDescriptor<StockReturnReceiptRowV1>()).contains { $0.receiptID == id }
            case .stockAbandonment: exists = try modelContext.fetch(FetchDescriptor<AbandonUnverifiedStockRowV1>()).contains { $0.dispositionID == id }
            case .site:
                let values = try modelContext.fetch(FetchDescriptor<Site>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .asset:
                let assets = try modelContext.fetch(FetchDescriptor<Asset>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard assets.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = assets.count == 1
                if let asset = assets.first {
                    bindings.append(WorkspacePackageBindingV1(
                        assetID: asset.id,
                        packageID: asset.packID,
                        packageSchemaVersion: asset.packSchemaVersion,
                        packageContentVersion: asset.packContentVersion
                    ))
                }
            case .locationNode:
                let values = try modelContext.fetch(FetchDescriptor<LocationNodeRow>(predicate: #Predicate { $0.id == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .assetPlacementEvent:
                let values = try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>(predicate: #Predicate { $0.id == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .assetCompositionEdge:
                let values = try modelContext.fetch(FetchDescriptor<AssetCompositionEdgeRow>(predicate: #Predicate { $0.id == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .assetCompositionEvent:
                let values = try modelContext.fetch(FetchDescriptor<AssetCompositionEventRow>(predicate: #Predicate { $0.id == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .savedSmartView:
                let values = try modelContext.fetch(FetchDescriptor<SavedSmartViewRowV1>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .serviceParty:
                let values = try modelContext.fetch(FetchDescriptor<ServicePartyRow>(predicate: #Predicate { $0.partyID == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }; exists = values.count == 1
            case .activitySessionEnvelope:
                let values = try modelContext.fetch(FetchDescriptor<ActivitySessionEnvelopeRow>(
                    predicate: #Predicate { $0.activityID == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                do {
                    if let row = values.first {
                        let value = try row.value()
                        guard value.activityID == id, value.revision == row.revision,
                              value.envelopeSHA256 == row.envelopeSHA256 else {
                            throw WorkspaceMutationFailureV1.persistenceFailed
                        }
                    }
                } catch {
                    throw WorkspaceMutationFailureV1.persistenceFailed
                }
                exists = values.count == 1
            case .activityStateTransition:
                let values = try modelContext.fetch(FetchDescriptor<ActivityStateTransitionRow>(
                    predicate: #Predicate { $0.transitionID == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                do {
                    if let row = values.first {
                        let value = try row.value()
                        guard value.transitionID == id, value.revision == row.revision,
                              value.transitionSHA256 == row.transitionSHA256 else {
                            throw WorkspaceMutationFailureV1.persistenceFailed
                        }
                    }
                } catch {
                    throw WorkspaceMutationFailureV1.persistenceFailed
                }
                exists = values.count == 1
            case .installationTaskResult:
                let values = try modelContext.fetch(FetchDescriptor<InstallationTaskResultRow>(
                    predicate: #Predicate { $0.resultID == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                do {
                    if let row = values.first {
                        let value = try row.value()
                        guard value.resultID == id, value.revision == row.revision,
                              value.resultSHA256 == row.resultSHA256 else {
                            throw WorkspaceMutationFailureV1.persistenceFailed
                        }
                    }
                } catch {
                    throw WorkspaceMutationFailureV1.persistenceFailed
                }
                exists = values.count == 1
            case .installationAsBuiltSnapshot:
                let values = try modelContext.fetch(FetchDescriptor<InstallationAsBuiltSnapshotRow>(
                    predicate: #Predicate { $0.snapshotID == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                do {
                    if let row = values.first {
                        let value = try row.value()
                        guard value.snapshotID == id, value.revision == row.revision,
                              value.snapshotSHA256 == row.snapshotSHA256 else {
                            throw WorkspaceMutationFailureV1.persistenceFailed
                        }
                    }
                } catch {
                    throw WorkspaceMutationFailureV1.persistenceFailed
                }
                exists = values.count == 1
            case .punchReviewBasisSnapshot:
                let values = try modelContext.fetch(FetchDescriptor<PunchReviewBasisSnapshotRow>(
                    predicate: #Predicate { $0.basisID == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                do {
                    if let row = values.first {
                        let value = try row.value()
                        guard value.basisID == id, value.revision == row.revision,
                              value.basisSHA256 == row.basisSHA256 else {
                            throw WorkspaceMutationFailureV1.persistenceFailed
                        }
                    }
                } catch {
                    throw WorkspaceMutationFailureV1.persistenceFailed
                }
                exists = values.count == 1
            case .workResourceEntry:
                let values = try modelContext.fetch(FetchDescriptor<ManualWorkResourceRecordRow>(predicate: #Predicate { $0.entryID == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                do {
                    if let row = values.first {
                        let value = try row.value()
                        guard value.entryID == id, value.revision == row.revision,
                              value.entrySHA256 == row.entrySHA256 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                    }
                } catch { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .serviceRequestRecord:
                let values = try modelContext.fetch(FetchDescriptor<ServiceRequestRecordRow>(predicate: #Predicate { $0.recordID == id }))
                exists = !values.isEmpty
            case .serviceRequestDispositionEvent:
                let values = try modelContext.fetch(FetchDescriptor<ServiceRequestDispositionEventRow>(predicate: #Predicate { $0.eventID == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }; exists = values.count == 1
            case .serviceRequestWorkLinkEvent:
                let values = try modelContext.fetch(FetchDescriptor<ServiceRequestWorkLinkEventRow>(predicate: #Predicate { $0.eventID == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }; exists = values.count == 1
            case .assetServiceIncident:exists=try modelContext.fetch(FetchDescriptor<AssetServiceIncidentRow>()).contains{$0.eventID==id}
            case .serviceImpactSegment:exists=try modelContext.fetch(FetchDescriptor<ServiceImpactSegmentRow>()).contains{$0.eventID==id}
            case .serviceCauseAssertion:exists=try modelContext.fetch(FetchDescriptor<ServiceCauseAssertionRow>()).contains{$0.eventID==id}
            case .serviceRemedyAssertion:exists=try modelContext.fetch(FetchDescriptor<ServiceRemedyAssertionRow>()).contains{$0.eventID==id}
            case .serviceRepairInterval:exists=try modelContext.fetch(FetchDescriptor<ServiceRepairIntervalRow>()).contains{$0.eventID==id}
            case .serviceRestorationAssertion:exists=try modelContext.fetch(FetchDescriptor<ServiceRestorationAssertionRow>()).contains{$0.eventID==id}
            case .qualifiedServiceExposure:exists=try modelContext.fetch(FetchDescriptor<QualifiedServiceExposureRow>()).contains{$0.eventID==id}
            case .sitePartyRoleEvent:
                let values = try modelContext.fetch(FetchDescriptor<SitePartyRoleEventRow>(predicate: #Predicate { $0.eventID == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }; exists = values.count == 1
            case .actorSnapshot:
                let values = try modelContext.fetch(FetchDescriptor<ActorSnapshotRow>(predicate: #Predicate { $0.snapshotID == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }; exists = values.count == 1
            case .qualificationSnapshot:
                let values = try modelContext.fetch(FetchDescriptor<QualificationSnapshotRow>(predicate: #Predicate { $0.snapshotID == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }; exists = values.count == 1
            case .signoffSnapshot:
                let values = try modelContext.fetch(FetchDescriptor<SignoffSnapshotRow>(predicate: #Predicate { $0.snapshotID == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }; exists = values.count == 1
            case .authoritySourceRelease, .requirementBasisBinding,
                 .applicabilityContextSnapshot, .assessmentScopeSnapshot,
                 .severityScaleRelease, .findingClassificationBinding,
                 .measurementProtocolRelease, .derivedFactEvaluatorDescriptor,
                 .derivedFactProvenance:
                exists = try authorityCriterionRowExists(identity)
            case .workflowRecord:
                let values = try modelContext.fetch(FetchDescriptor<WorkflowRecord>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .evidenceFile:
                let values = try modelContext.fetch(FetchDescriptor<EvidenceFile>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .issue:
                let values = try modelContext.fetch(FetchDescriptor<Issue>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .packet:
                let values = try modelContext.fetch(FetchDescriptor<Packet>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .report:
                let values = try modelContext.fetch(FetchDescriptor<Report>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .deletionLedgerEntry:
                let matches = deletionLedgerIdentities.filter { $0.id == identity.id }
                guard matches.count <= 1 else {
                    throw WorkspaceMutationFailureV1.persistenceFailed
                }
                exists = matches.count == 1
            }
            if exists { existing.append(identity) }
        }
        return (
            existing.sorted { $0.stableKey < $1.stableKey },
            bindings.sorted { $0.assetID.uuidString < $1.assetID.uuidString }
        )
    }

    func createFirstSign(
        _ value: FirstSignMutationV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard value.assetLabel == value.assetLabel.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.assetLabel.isEmpty,
              !value.packID.isEmpty,
              value.packSchemaVersion > 0,
              value.packContentVersion > 0,
              Self.isFinite(value.createdAt),
              value.newSite == nil || value.newSite?.id == value.siteID else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let placementFields = [
            value.initialPlacementMutationID != nil,
            value.initialPlacementEventID != nil,
            value.initialPhysicalEpisodeID != nil,
        ]
        guard placementFields.allSatisfy({ $0 }) || placementFields.allSatisfy({ !$0 }) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let assetID = value.assetID
        guard try modelContext.fetch(FetchDescriptor<Asset>(
            predicate: #Predicate { $0.id == assetID }
        )).isEmpty else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }

        let siteID = value.siteID
        let existingSites = try modelContext.fetch(FetchDescriptor<Site>(
            predicate: #Predicate { $0.id == siteID }
        ))
        if value.newSite == nil {
            guard existingSites.count == 1 else { throw WorkspaceMutationFailureV1.invalidCommand }
        } else {
            guard existingSites.isEmpty else { throw WorkspaceMutationFailureV1.invalidCommand }
        }

        var identities = [try WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID)]
        if let site = value.newSite {
            guard site.label == site.label.trimmingCharacters(in: .whitespacesAndNewlines),
                  !site.label.isEmpty else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            identities.append(try WorkspaceEntityIdentityV1(kind: .site, id: site.id))
        }
        if let placementEventID = value.initialPlacementEventID {
            guard try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>(
                predicate: #Predicate { $0.id == placementEventID }
            )).isEmpty else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            identities.append(try WorkspaceEntityIdentityV1(
                kind: .assetPlacementEvent,
                id: placementEventID
            ))
        }
        let effect = try WorkspaceMutationEffectV1(
            affectedEntities: identities,
            temporaryRelativePath: temporaryRelativePath
        )

        if let site = value.newSite {
            modelContext.insert(Site(
                id: site.id,
                label: site.label,
                address: site.address,
                timeZoneID: site.timeZoneID,
                createdAt: value.createdAt
            ))
        }
        modelContext.insert(Asset(
            id: value.assetID,
            siteID: value.siteID,
            packID: value.packID,
            packSchemaVersion: value.packSchemaVersion,
            packContentVersion: value.packContentVersion,
            label: value.assetLabel,
            createdAt: value.createdAt
        ))
        if let mutationID = value.initialPlacementMutationID,
           let eventID = value.initialPlacementEventID,
           let episodeID = value.initialPhysicalEpisodeID {
            let siteDisplay = value.newSite?.label ?? existingSites[0].label
            let event = try AssetPlacementEventV1(
                id: eventID,
                workspaceID: try currentWorkspaceID(),
                assetID: value.assetID,
                siteID: value.siteID,
                locationNodeID: nil,
                predecessorEventID: nil,
                source: .manual,
                physicalEpisodeID: episodeID,
                continuity: .samePhysicalInstallation,
                pathSnapshot: try LocationPathSnapshotV1(
                    siteID: value.siteID,
                    siteDisplay: siteDisplay,
                    nodes: []
                ),
                mutationID: mutationID,
                occurredAt: occurredAt
            )
            try AssetPlacementHistoryV1.validate([event])
            modelContext.insert(try AssetPlacementEventRow(event))
        }
        return effect
    }

    private func currentWorkspaceID() throws -> WorkspaceID {
        let states = try modelContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
        guard states.count == 1, let state = states.first else {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        return WorkspaceID(rawValue: state.workspaceID)
    }

    func createCheckDraft(
        _ value: CheckDraftMutationV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard let stage = WorkflowStage(rawValue: value.stage),
              !value.packID.isEmpty,
              value.packSchemaVersion > 0,
              value.packContentVersion > 0,
              !value.pdfTemplateID.isEmpty,
              value.pdfTemplateVersion > 0,
              Self.isFinite(value.startedAt),
              value.observedAtUTC.map({ Self.isFinite($0) }) ?? true else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        guard (value.observationBasis == nil) == (value.temporalContext == nil) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let observationBasisData: Data
        let temporalContextData: Data
        do {
            if let observationBasis = value.observationBasis,
               let temporalContext = value.temporalContext {
                try Self.requireLegacyTimeProjectionMatches(
                    temporalContext,
                    command: value
                )
                observationBasisData = try ObservationAndTimeCodecV1.encode(
                    observationBasis
                )
                temporalContextData = try ObservationAndTimeCodecV1.encode(
                    temporalContext
                )
            } else {
                let migratedBasis = try ObservationAndTimeLegacyMigrationV1.observationBasis(
                    couldNotVerifyKey: nil,
                    displaySnapshot: nil,
                    registryVersion: nil
                )
                let migratedTemporal = try ObservationAndTimeLegacyMigrationV1.temporalContext(
                    observedAtUTC: value.observedAtUTC,
                    recordedAtUTC: value.startedAt,
                    timeZoneID: value.timeZoneID,
                    utcOffsetMinutes: value.utcOffsetMinutes,
                    localDate: value.localDate,
                    localTime: value.localTime
                )
                guard let migratedBasis, let migratedTemporal else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                observationBasisData = try ObservationAndTimeCodecV1.encode(migratedBasis)
                temporalContextData = try ObservationAndTimeCodecV1.encode(migratedTemporal)
            }
        } catch {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let draftStep: WorkflowDraftStep?
        if let key = value.draftStepKey {
            guard let parsed = WorkflowDraftStep(rawValue: key) else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            draftStep = parsed
        } else {
            draftStep = nil
        }
        guard (stage == .work && draftStep == nil)
                || (stage != .work && draftStep != nil) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let recordID = value.recordID
        guard try modelContext.fetch(FetchDescriptor<WorkflowRecord>(
            predicate: #Predicate { $0.id == recordID }
        )).isEmpty else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let assetID = value.assetID
        guard try modelContext.fetch(FetchDescriptor<Asset>(
            predicate: #Predicate { $0.id == assetID }
        )).count == 1 else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let identity = try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.recordID)
        let effect = try WorkspaceMutationEffectV1(
            affectedEntities: [identity],
            temporaryRelativePath: temporaryRelativePath
        )
        modelContext.insert(WorkflowRecord(
            id: value.recordID,
            assetID: value.assetID,
            packetID: nil,
            issueID: value.issueID,
            parentRecordID: value.parentRecordID,
            recordRevisionRootID: value.recordID,
            revisesRecordID: nil,
            evidenceSourceRecordID: nil,
            revisionKind: .original,
            stage: stage,
            state: .draft,
            draftStepKey: draftStep,
            startedAt: value.startedAt,
            completedAt: nil,
            observedAtUTC: value.observedAtUTC,
            timeZoneID: value.timeZoneID,
            utcOffsetMinutes: value.utcOffsetMinutes,
            localDate: value.localDate,
            localTime: value.localTime,
            afterDarkAcknowledgementKey: value.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: value.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: value.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: value.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: value.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: value.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: value.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: value.safePositionAcknowledgementAccepted,
            packID: value.packID,
            packSchemaVersion: value.packSchemaVersion,
            packContentVersion: value.packContentVersion,
            pdfTemplateID: value.pdfTemplateID,
            pdfTemplateVersion: value.pdfTemplateVersion,
            outcomeKey: nil,
            couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil,
            couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: nil,
            workDescription: nil,
            note: nil,
            finalizationMutationID: nil
        ))
        modelContext.insert(try ObservationAndTimeRow(
            recordID: value.recordID,
            observationBasisV1Data: observationBasisData,
            temporalContextV1Data: temporalContextData
        ))
        let workspaceID = try currentWorkspaceID().rawValue
        modelContext.insert(try RequirementAssuranceRow.blockingUnknownBackfill(
            workflowRecordID: value.recordID,
            workspaceID: workspaceID,
            evaluatedRevision: 1,
            requirementID: "legacy_assurance_unknown",
            requirementVersion: 1,
            requirementTypeID: "legacy_assurance_unknown",
            policySHA256: StoreMigrationCanonicalJSONV1.sha256(
                Data("legacy-assurance-unknown-v1".utf8)
            ),
            mutationID: value.recordID,
            timestamp: value.startedAt
        ))
        return effect
    }

    private static func requireLegacyTimeProjectionMatches(
        _ temporal: TemporalContextV1,
        command: CheckDraftMutationV1
    ) throws {
        try temporal.validate()
        guard temporal.occurredAtUTC == command.observedAtUTC,
              temporal.localDate == command.localDate,
              temporal.localTime == command.localTime,
              temporal.ianaTimeZoneIdentifier == command.timeZoneID else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let expectedOffsetSeconds: Int?
        if let minutes = command.utcOffsetMinutes {
            let (seconds, overflow) = minutes.multipliedReportingOverflow(
                by: 60
            )
            guard !overflow else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            expectedOffsetSeconds = seconds
        } else {
            expectedOffsetSeconds = nil
        }
        guard temporal.utcOffsetSeconds == expectedOffsetSeconds else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    func acceptCheckEvidence(
        _ value: CheckEvidenceMutationV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard WorkflowDraftStep(rawValue: value.nextDraftStepKey) != nil,
              value.byteCount >= 0,
              value.thumbnailByteCount >= 0,
              Self.isSHA256(value.sha256),
              Self.isSHA256(value.thumbnailSHA256),
              Self.isSafeRelativePath(value.relativePath),
              Self.isSafeRelativePath(value.thumbnailRelativePath),
              !value.mimeType.isEmpty,
              !value.purposeKey.isEmpty,
              Self.isFinite(value.createdAt) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let draftID = value.draftID
        let drafts = try modelContext.fetch(FetchDescriptor<WorkflowRecord>(
            predicate: #Predicate { $0.id == draftID }
        ))
        guard drafts.count == 1,
              let draft = drafts.first,
              draft.state == WorkflowState.draft.rawValue else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let evidenceID = value.evidenceID
        guard try modelContext.fetch(FetchDescriptor<EvidenceFile>(
            predicate: #Predicate { $0.id == evidenceID }
        )).isEmpty else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let identities = try [
            WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.draftID),
            WorkspaceEntityIdentityV1(kind: .evidenceFile, id: value.evidenceID),
        ]
        let effect = try WorkspaceMutationEffectV1(
            affectedEntities: identities,
            temporaryRelativePath: temporaryRelativePath
        )
        draft.draftStepKey = value.nextDraftStepKey
        modelContext.insert(EvidenceFile(
            id: value.evidenceID,
            recordID: value.draftID,
            purposeKey: value.purposeKey,
            relativePath: value.relativePath,
            mimeType: value.mimeType,
            byteCount: value.byteCount,
            sha256: value.sha256,
            createdAt: value.createdAt,
            thumbnailRelativePath: value.thumbnailRelativePath,
            thumbnailByteCount: value.thumbnailByteCount,
            thumbnailSHA256: value.thumbnailSHA256
        ))
        return effect
    }

    func updateSiteTimeZone(
        _ value: SiteTimeZoneMutationV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard TimeZone(identifier: value.timeZoneID) != nil,
              Self.isFinite(value.confirmedAt) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let siteID = value.siteID
        let sites = try modelContext.fetch(FetchDescriptor<Site>(
            predicate: #Predicate { $0.id == siteID }
        ))
        guard sites.count == 1, let site = sites.first else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let effect = try WorkspaceMutationEffectV1(
            affectedEntities: [try WorkspaceEntityIdentityV1(kind: .site, id: siteID)],
            temporaryRelativePath: temporaryRelativePath
        )
        site.timeZoneID = value.timeZoneID
        site.updatedAt = value.confirmedAt
        return effect
    }

    func rollback() {
        assetSemanticLifecycleAdapter.rollback()
        modelContext.rollback()
    }

    private func applyLocationHierarchyChange(
        _ plan: LocationHierarchyChangePlanV1,
        placementChanges: [AssetPlacementChangePlanV1],
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        try plan.validate()
        let workspaceID = plan.workspaceID.rawValue
        let rows = try modelContext.fetch(FetchDescriptor<LocationNodeRow>(
            predicate: #Predicate { $0.workspaceID == workspaceID }
        ))
        let current = try rows.map { try $0.value() }
        let affectedIDs = Set(plan.beforeNodes.map(\.id)).union(plan.afterNodes.map(\.id))
        let currentAffected = current.filter { affectedIDs.contains($0.id) }.sorted { $0.id.uuidString < $1.id.uuidString }
        guard currentAffected == plan.beforeNodes.sorted(by: { $0.id.uuidString < $1.id.uuidString }) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let placementEvents = try modelContext.fetch(
            FetchDescriptor<AssetPlacementEventRow>(predicate: #Predicate { $0.workspaceID == workspaceID })
        ).map { try $0.value() }
        let immutablePlacementReferencedNodeIDs = placementEvents.compactMap(\.locationNodeID)
            .sorted { $0.uuidString < $1.uuidString }
        guard Array(Set(immutablePlacementReferencedNodeIDs)).sorted(by: { $0.uuidString < $1.uuidString })
                == plan.immutablePlacementReferencedNodeIDs else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let unaffected = current.filter { !affectedIDs.contains($0.id) }
        let resultingNodes = unaffected + plan.afterNodes
        try LocationHierarchyPolicyV1.validate(resultingNodes)
        let sites = try modelContext.fetch(FetchDescriptor<Site>())
        let siteDisplayByID = Dictionary(uniqueKeysWithValues: sites.map { ($0.id, $0.label) })
        let liveAssetIDs = Set(try modelContext.fetch(FetchDescriptor<Asset>()).map(\.id))
        let placementPredecessorIDs = Set(placementEvents.compactMap(\.predecessorEventID))
        let liveTips = placementEvents.filter {
            liveAssetIDs.contains($0.assetID) && !placementPredecessorIDs.contains($0.id)
        }
        guard Set(liveTips.map(\.assetID)).count == liveTips.count,
              Set(liveTips.map(\.assetID)) == liveAssetIDs else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let placementChangesByAssetID = Dictionary(
            uniqueKeysWithValues: placementChanges.map { ($0.basis.assetID, $0) }
        )
        var expectedPathChanges: [AssetLocationPathChangeV1] = []
        for tip in liveTips {
            guard let beforeSiteDisplay = siteDisplayByID[tip.siteID] else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            let beforePath = try makeLocationPath(
                siteID: tip.siteID,
                siteDisplay: beforeSiteDisplay,
                nodeID: tip.locationNodeID,
                nodes: current
            )
            let change = placementChangesByAssetID[tip.assetID]
            let afterSiteID = change?.basis.proposedSiteID ?? tip.siteID
            let afterNodeID = change?.basis.proposedLocationNodeID ?? tip.locationNodeID
            guard let afterSiteDisplay = siteDisplayByID[afterSiteID] else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            let afterPath = try makeLocationPath(
                siteID: afterSiteID,
                siteDisplay: afterSiteDisplay,
                nodeID: afterNodeID,
                nodes: resultingNodes
            )
            if beforePath != afterPath {
                expectedPathChanges.append(try AssetLocationPathChangeV1(
                    assetID: tip.assetID,
                    beforePath: beforePath,
                    afterPath: afterPath
                ))
            }
            if let change {
                guard change.basis.currentPlacement == tip,
                      change.basis.proposedPath == afterPath else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            }
        }
        expectedPathChanges.sort()
        guard expectedPathChanges == plan.assetPathChanges,
              expectedPathChanges.map(\.assetID) == plan.affectedAssetIDs else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let rowsByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let afterByID = Dictionary(uniqueKeysWithValues: plan.afterNodes.map { ($0.id, $0) })
        for id in affectedIDs {
            if let value = afterByID[id], let row = rowsByID[id] {
                let replacement = try LocationNodeRow(value)
                row.workspaceID = replacement.workspaceID; row.siteID = replacement.siteID
                row.parentNodeID = replacement.parentNodeID; row.kind = replacement.kind
                row.label = replacement.label; row.shortCode = replacement.shortCode
                row.siblingOrder = replacement.siblingOrder; row.state = replacement.state
                row.revision = replacement.revision; row.mutationID = replacement.mutationID
                row.occurredAt = replacement.occurredAt
                row.canonicalData = replacement.canonicalData
            } else if let value = afterByID[id] {
                modelContext.insert(try LocationNodeRow(value))
            } else if let row = rowsByID[id] {
                modelContext.delete(row)
            }
        }
        return try WorkspaceMutationEffectV1(
            affectedEntities: try affectedIDs.map { try .init(kind: .locationNode, id: $0) },
            temporaryRelativePath: temporaryRelativePath
        )
    }

    private func applyAssetPlacementChange(
        _ plan: AssetPlacementChangePlanV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        let rebuilt = try AssetPlacementChangePlanV1(
            operationID: plan.operationID,
            mutationID: plan.mutationID,
            basis: plan.basis,
            newEventID: plan.newEventID,
            resultingPhysicalEpisodeID: plan.resultingPhysicalEpisodeID,
            componentContributions: plan.componentContributions,
            poseEvents: plan.poseEvents,
            poseEventPredecessors: plan.poseEventPredecessors,
            poseAdmissionClosure:plan.poseAdmissionClosure
        )
        guard rebuilt == plan else { throw WorkspaceMutationFailureV1.invalidCommand }
        let assetID = plan.basis.assetID
        let assets = try modelContext.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetID }))
        guard assets.count == 1, let asset = assets.first else { throw WorkspaceMutationFailureV1.invalidCommand }
        let placementRows = try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>(
            predicate: #Predicate { $0.assetID == assetID }
        ))
        let placements = try placementRows.map { try $0.value() }
        let predecessorIDs = Set(placements.compactMap(\.predecessorEventID))
        let tips = placements.filter { !predecessorIDs.contains($0.id) }
        let newEventID = plan.newEventID
        guard tips.count <= 1, tips.first == plan.basis.currentPlacement,
              asset.siteID == (plan.basis.currentPlacement?.siteID ?? plan.basis.proposedSiteID),
              try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>(
                predicate: #Predicate { $0.id == newEventID }
              )).isEmpty else { throw WorkspaceMutationFailureV1.invalidCommand }
        let exactPath = try currentLocationPath(
            workspaceID: plan.basis.workspaceID,
            siteID: plan.basis.proposedSiteID,
            nodeID: plan.basis.proposedLocationNodeID
        )
        guard exactPath == plan.basis.proposedPath else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let event = try AssetPlacementEventV1(
            id: plan.newEventID,
            workspaceID: plan.basis.workspaceID,
            assetID: assetID,
            siteID: plan.basis.proposedSiteID,
            locationNodeID: plan.basis.proposedLocationNodeID,
            predecessorEventID: plan.basis.currentPlacement?.id,
            source: plan.basis.source,
            physicalEpisodeID: plan.resultingPhysicalEpisodeID,
            continuity: plan.basis.reviewedContinuity,
            pathSnapshot: plan.basis.proposedPath,
            mutationID: plan.mutationID,
            occurredAt: occurredAt
        )
        try AssetPlacementHistoryV1.validate(placements + [event])
        asset.siteID = event.siteID
        asset.updatedAt = occurredAt
        modelContext.insert(try AssetPlacementEventRow(event))
        if !plan.poseEvents.isEmpty {
            guard let poseAdmissionClosure=plan.poseAdmissionClosure else{throw WorkspaceMutationFailureV1.invalidCommand}
            let poseMutation = try PlacementPoseMutationV1(
                workspaceID: plan.basis.workspaceID,
                mutationID: plan.mutationID,
                events: plan.poseEvents,
                eventPredecessors: plan.poseEventPredecessors.map(Optional.some),
                admissionClosure:poseAdmissionClosure
            )
            _ = try applyPlacementPose(
                poseMutation,
                temporaryRelativePath: temporaryRelativePath
            )
        }
        return try WorkspaceMutationEffectV1(
            affectedEntities: try ([
                .init(kind: .asset, id: assetID),
                .init(kind: .assetPlacementEvent, id: event.id),
            ] + plan.poseEvents.map { try .init(kind: .assetPoseEvent, id: $0.eventID) }),
            temporaryRelativePath: temporaryRelativePath
        )
    }

    private func currentLocationPath(
        workspaceID: WorkspaceID,
        siteID: UUID,
        nodeID: UUID?
    ) throws -> LocationPathSnapshotV1 {
        let sites = try modelContext.fetch(FetchDescriptor<Site>(
            predicate: #Predicate { $0.id == siteID }
        ))
        guard sites.count == 1, let site = sites.first else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let rawWorkspaceID = workspaceID.rawValue
        let nodes = try modelContext.fetch(FetchDescriptor<LocationNodeRow>(
            predicate: #Predicate { $0.workspaceID == rawWorkspaceID }
        )).map { try $0.value() }
        try LocationHierarchyPolicyV1.validate(nodes)
        return try makeLocationPath(
            siteID: siteID,
            siteDisplay: site.label,
            nodeID: nodeID,
            nodes: nodes
        )
    }

    private func makeLocationPath(
        siteID: UUID,
        siteDisplay: String,
        nodeID: UUID?,
        nodes: [LocationNodeV1]
    ) throws -> LocationPathSnapshotV1 {
        guard let nodeID else {
            return try LocationPathSnapshotV1(siteID: siteID, siteDisplay: siteDisplay, nodes: [])
        }
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var cursorID: UUID? = nodeID
        var visited = Set<UUID>()
        var reversed: [LocationPathComponentV1] = []
        while let id = cursorID {
            guard visited.insert(id).inserted, let node = byID[id], node.siteID == siteID,
                  node.state == .active else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            reversed.append(try LocationPathComponentV1(
                nodeID: node.id,
                kind: node.kind,
                label: node.label,
                shortCode: node.shortCode,
                revision: node.revision
            ))
            cursorID = node.parentNodeID
        }
        return try LocationPathSnapshotV1(
            siteID: siteID,
            siteDisplay: siteDisplay,
            nodes: Array(reversed.reversed())
        )
    }

    private func applyAssetCompositionChange(
        _ plan: AssetCompositionChangePlanV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        try plan.validate()
        let event = plan.event
        let eventID = event.id
        guard try modelContext.fetch(FetchDescriptor<AssetCompositionEventRow>(
            predicate: #Predicate { $0.id == eventID }
        )).isEmpty else { throw WorkspaceMutationFailureV1.invalidCommand }
        let edgeID = event.edge.id
        let edgeRows = try modelContext.fetch(FetchDescriptor<AssetCompositionEdgeRow>(
            predicate: #Predicate { $0.id == edgeID }
        ))
        guard edgeRows.count <= 1 else { throw WorkspaceMutationFailureV1.invalidCommand }
        let priorEvents = try modelContext.fetch(FetchDescriptor<AssetCompositionEventRow>(
            predicate: #Predicate { $0.edgeID == edgeID }
        ))
        let priorValues = try priorEvents.map {
            let value = try LocationPersistenceCodecV1.decode(AssetCompositionEventV1.self, from: $0.canonicalData)
            try value.validate()
            return value
        }
        let predecessorIDs = Set(priorValues.compactMap(\.predecessorEventID))
        let tips = priorValues.filter { !predecessorIDs.contains($0.id) }
        let priorRevision: UInt64
        if let prior = edgeRows.first {
            guard prior.revision >= 0, prior.revision < Int64.max else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            priorRevision = UInt64(prior.revision)
        } else {
            priorRevision = 0
        }
        guard tips.count <= 1, tips.first?.id == event.predecessorEventID,
              event.edge.revision == priorRevision + 1 else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        try AssetCompositionHistoryV1.validate(priorValues + [event], currentEdge: event.edge)
        let allEdges = try modelContext.fetch(FetchDescriptor<AssetCompositionEdgeRow>()).map {
            let value = try LocationPersistenceCodecV1.decode(AssetCompositionEdgeV1.self, from: $0.canonicalData)
            try value.validate()
            return value
        }
        let resultingEdges = (allEdges.filter { $0.id != edgeID } + [event.edge]).filter(\.isActive).sorted { $0.id.uuidString < $1.id.uuidString }
        let liveAssetIDs = Set(try modelContext.fetch(FetchDescriptor<Asset>()).map(\.id))
        let placementValues = try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>()).map { try $0.value() }
        let allPredecessors = Set(placementValues.compactMap(\.predecessorEventID))
        let placementTips = placementValues.filter {
            liveAssetIDs.contains($0.assetID) && !allPredecessors.contains($0.id)
        }
        guard Set(placementTips.map(\.assetID)).count == placementTips.count,
              Set(placementTips.map(\.assetID)) == liveAssetIDs else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let placementByAsset = Dictionary(uniqueKeysWithValues: placementTips.map { ($0.assetID, $0) })
        guard plan.currentPlacementByAssetID.allSatisfy({ placementByAsset[$0.key] == $0.value }),
              resultingEdges == plan.resultingActiveEdges else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        try AssetCompositionPolicyV1.validate(edges: resultingEdges, placementByAssetID: placementByAsset)
        if let row = edgeRows.first {
            let replacement = try AssetCompositionEdgeRow(event.edge)
            row.workspaceID = replacement.workspaceID; row.parentAssetID = replacement.parentAssetID
            row.childAssetID = replacement.childAssetID; row.relationship = replacement.relationship
            row.isActive = replacement.isActive; row.revision = replacement.revision
            row.edgeSHA256 = replacement.edgeSHA256; row.canonicalData = replacement.canonicalData
        } else {
            modelContext.insert(try AssetCompositionEdgeRow(event.edge))
        }
        modelContext.insert(try AssetCompositionEventRow(event))
        return try WorkspaceMutationEffectV1(
            affectedEntities: try [
                .init(kind: .assetCompositionEdge, id: event.edge.id),
                .init(kind: .assetCompositionEvent, id: event.id),
            ],
            temporaryRelativePath: temporaryRelativePath
        )
    }

    private func applySavedSmartView(
        _ mutation: SavedSmartViewMutationV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        try mutation.validate()
        let id = mutation.id
        let stableKey = SavedSmartViewRowV1.key(
            workspaceID: mutation.workspaceID,
            stableID: mutation.stableID
        )
        let byID = try modelContext.fetch(FetchDescriptor<SavedSmartViewRowV1>(
            predicate: #Predicate { $0.id == id }
        ))
        let byStableKey = try modelContext.fetch(FetchDescriptor<SavedSmartViewRowV1>(
            predicate: #Predicate { $0.workspaceStableKey == stableKey }
        ))
        guard byID.count <= 1, byStableKey.count <= 1,
              Set((byID + byStableKey).map(\.id)).count <= 1 else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let existing = byID.first ?? byStableKey.first
        if let existing {
            guard existing.id == id,
                  existing.workspaceStableKey == stableKey,
                  existing.workspaceID == mutation.workspaceID,
                  existing.stableID == mutation.stableID else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        }
        let existingDescriptor = try existing?.descriptor()
        switch mutation.disposition {
        case .upsert:
            guard let descriptor = mutation.descriptor,
                  descriptor.origin == .userSaved,
                  existingDescriptor.map({
                      $0.revision == mutation.expectedDescriptorRevision
                  })
                    ?? (mutation.expectedDescriptorRevision == 0) else {
                throw WorkspaceMutationFailureV1.staleEntityRevision(
                    try .init(kind: .savedSmartView, id: id)
                )
            }
            if let existing { modelContext.delete(existing) }
            modelContext.insert(try SavedSmartViewRowV1(descriptor))
        case .delete:
            guard let existing,
                  existingDescriptor?.origin == .userSaved,
                  existingDescriptor?.revision == mutation.expectedDescriptorRevision,
                  existing.workspaceID == mutation.workspaceID,
                  existing.stableID == mutation.stableID else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            modelContext.delete(existing)
        }
        return try WorkspaceMutationEffectV1(
            affectedEntities: [.init(kind: .savedSmartView, id: id)],
            temporaryRelativePath: temporaryRelativePath
        )
    }

    private func applyRequirementAssurance(
        _ mutation: RequirementAssuranceMutationV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        try mutation.validate()
        let recordID = mutation.snapshot.workflowRecordID
        var recordDescriptor = FetchDescriptor<WorkflowRecord>(
            predicate: #Predicate { $0.id == recordID }
        )
        recordDescriptor.fetchLimit = 2
        let records = try modelContext.fetch(recordDescriptor)
        guard records.count == 1 else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }

        var assuranceDescriptor = FetchDescriptor<RequirementAssuranceRow>(
            predicate: #Predicate { $0.workflowRecordID == recordID }
        )
        assuranceDescriptor.fetchLimit = 2
        let rows = try modelContext.fetch(assuranceDescriptor)
        guard rows.count <= 1 else {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        if let row = rows.first {
            do {
                try row.replace(
                    with: mutation.snapshot,
                    expectedRevision: mutation.expectedEvaluatedRevision,
                    mutationID: mutation.mutationID,
                    updatedAt: occurredAt
                )
            } catch RequirementAssuranceFailureV1.staleRevision {
                throw WorkspaceMutationFailureV1.staleEntityRevision(
                    try .init(kind: .workflowRecord, id: recordID)
                )
            }
        } else {
            guard mutation.expectedEvaluatedRevision == 0 else {
                throw WorkspaceMutationFailureV1.staleEntityRevision(
                    try .init(kind: .workflowRecord, id: recordID)
                )
            }
            modelContext.insert(try RequirementAssuranceRow(
                snapshot: mutation.snapshot,
                mutationID: mutation.mutationID,
                createdAt: occurredAt,
                updatedAt: occurredAt
            ))
        }
        return try WorkspaceMutationEffectV1(
            affectedEntities: [.init(kind: .workflowRecord, id: recordID)],
            temporaryRelativePath: temporaryRelativePath
        )
    }

    private func applyPartyAccountability(
        _ mutation: PartyAccountabilityMutationV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        try mutation.validate()
        let identity = try mutation.affectedIdentity
        switch mutation {
        case let .recordParty(value):
            let partyID = value.partyID
            var descriptor = FetchDescriptor<ServicePartyRow>(predicate: #Predicate { $0.partyID == partyID })
            descriptor.fetchLimit = 2
            let rows = try modelContext.fetch(descriptor)
            guard rows.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
            if let row = rows.first {
                let prior = try row.value()
                guard prior.revision < UInt64.max else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                do {
                    try value.validateSuccessor(of: prior)
                    try row.replace(with: value, expectedRevision: prior.revision)
                } catch PartyAccountabilityFailureV1.staleRevision {
                    throw WorkspaceMutationFailureV1.staleEntityRevision(identity)
                } catch {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            } else if value.revision != 1 {
                throw WorkspaceMutationFailureV1.invalidCommand
            } else {
                modelContext.insert(try ServicePartyRow(value))
            }
        case let .appendSiteRole(value):
            let eventID = value.eventID
            let siteID = value.siteID
            let partyID = value.partyID
            var duplicate = FetchDescriptor<SitePartyRoleEventRow>(predicate: #Predicate { $0.eventID == eventID })
            duplicate.fetchLimit = 1
            guard try modelContext.fetch(duplicate).isEmpty else { throw WorkspaceMutationFailureV1.invalidCommand }
            var site = FetchDescriptor<Site>(predicate: #Predicate { $0.id == siteID }); site.fetchLimit = 1
            var party = FetchDescriptor<ServicePartyRow>(predicate: #Predicate { $0.partyID == partyID }); party.fetchLimit = 1
            guard try modelContext.fetch(site).count == 1,
                  let partyValue = try modelContext.fetch(party).first?.value(),
                  partyValue.workspaceID == value.workspaceID else { throw WorkspaceMutationFailureV1.invalidCommand }
            let predecessor: SitePartyRoleEventV1?
            if let predecessorID = value.supersedesEventID {
                var d = FetchDescriptor<SitePartyRoleEventRow>(predicate: #Predicate { $0.eventID == predecessorID }); d.fetchLimit = 1
                guard let row = try modelContext.fetch(d).first else { throw WorkspaceMutationFailureV1.invalidCommand }
                predecessor = try row.value()
            } else { predecessor = nil }
            modelContext.insert(try SitePartyRoleEventRow(value, predecessor: predecessor))
        case let .appendActorSnapshot(value):
            let snapshotID = value.snapshotID
            var d = FetchDescriptor<ActorSnapshotRow>(predicate: #Predicate { $0.snapshotID == snapshotID }); d.fetchLimit = 1
            guard try modelContext.fetch(d).isEmpty else { throw WorkspaceMutationFailureV1.invalidCommand }
            if let partyID = value.actor.partyID {
                var partyDescriptor = FetchDescriptor<ServicePartyRow>(
                    predicate: #Predicate { $0.partyID == partyID }
                )
                partyDescriptor.fetchLimit = 2
                let partyRows = try modelContext.fetch(partyDescriptor)
                guard partyRows.count == 1 else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                let party = try partyRows[0].value()
                do {
                    try value.actor.validatePartyReference(party)
                } catch {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            }
            modelContext.insert(try ActorSnapshotRow(value))
        case let .appendQualificationSnapshot(value):
            let snapshotID = value.snapshotID
            var d = FetchDescriptor<QualificationSnapshotRow>(predicate: #Predicate { $0.snapshotID == snapshotID }); d.fetchLimit = 1
            guard try modelContext.fetch(d).isEmpty else { throw WorkspaceMutationFailureV1.invalidCommand }
            modelContext.insert(try QualificationSnapshotRow(value))
        case let .appendSignoff(value):
            let snapshotID = value.snapshotID
            var d = FetchDescriptor<SignoffSnapshotRow>(predicate: #Predicate { $0.snapshotID == snapshotID }); d.fetchLimit = 1
            guard try modelContext.fetch(d).isEmpty else { throw WorkspaceMutationFailureV1.invalidCommand }
            if let embeddedActor = value.roleAssertion?.actor {
                let actorID = embeddedActor.snapshotID
                var actorDescriptor = FetchDescriptor<ActorSnapshotRow>(predicate: #Predicate { $0.snapshotID == actorID })
                actorDescriptor.fetchLimit = 2
                let actorRows = try modelContext.fetch(actorDescriptor)
                guard actorRows.count == 1,
                      try actorRows[0].value() == embeddedActor else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            }
            if let embeddedQualification = value.qualification {
                let qualificationID = embeddedQualification.snapshotID
                var qualificationDescriptor = FetchDescriptor<QualificationSnapshotRow>(predicate: #Predicate { $0.snapshotID == qualificationID })
                qualificationDescriptor.fetchLimit = 2
                let qualificationRows = try modelContext.fetch(qualificationDescriptor)
                guard qualificationRows.count == 1,
                      try qualificationRows[0].value() == embeddedQualification else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            }
            let predecessor: SignoffSnapshotV1?
            if let predecessorID = value.supersedesSnapshotID {
                var p = FetchDescriptor<SignoffSnapshotRow>(predicate: #Predicate { $0.snapshotID == predecessorID }); p.fetchLimit = 1
                guard let row = try modelContext.fetch(p).first else { throw WorkspaceMutationFailureV1.invalidCommand }
                predecessor = try row.value()
            } else { predecessor = nil }
            modelContext.insert(try SignoffSnapshotRow(value, predecessor: predecessor))
        }
        return try WorkspaceMutationEffectV1(affectedEntities: [identity], temporaryRelativePath: temporaryRelativePath)
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func isSafeRelativePath(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("/") && !value.contains("..") && !value.contains("\\")
    }

    private static func isFinite(_ value: Date) -> Bool {
        value.timeIntervalSinceReferenceDate.isFinite
    }
}

private struct OperationalContactAdapterSiteDigestBasisV1: Codable {
    let identity: WorkspaceEntityIdentityV1
    let revision: UInt64
    let value: V4BackupSiteDTO
}

enum C50IncumbentFileExchangeWriterAdapterBoundaryV1 {
    static let profileSelectionSessionSourceQuarantineAreNonpersistent = true
    static let adapterOwnsNoCanonicalWriter = true
    static let adapterOwnsNoSwiftDataModel = true
    static let adapterCreatesNoMutationKind = true
    static let previewWritesWorkspace = false
    static let acceptedCanonicalEffectsUseExistingWriter = true
    static let journalAndReceiptOwnershipRemainsExisting = true
    static let persistenceDisposition = "NONPERSISTENT"
    static let mutationDisposition = "NOT_APPLICABLE"

    static func validate() -> Bool {
        profileSelectionSessionSourceQuarantineAreNonpersistent
            && adapterOwnsNoCanonicalWriter
            && adapterOwnsNoSwiftDataModel
            && adapterCreatesNoMutationKind
            && !previewWritesWorkspace
            && acceptedCanonicalEffectsUseExistingWriter
            && journalAndReceiptOwnershipRemainsExisting
            && persistenceDisposition == "NONPERSISTENT"
            && mutationDisposition == "NOT_APPLICABLE"
            && C50IncumbentFileExchangePersistenceBoundaryV1.validate()
    }
}

/// Resolves every authority embedded in a C31 admission closure to one exact
/// canonical row. This is shared by live writes, journal replay, and startup.
enum LightingPersistedAdmissionV1 {
    static func validate(_ operation: LightingWriteOperationV1, in context: ModelContext) throws {
        func exact<T: Equatable>(_ value: T, _ values: [T]) throws {
            guard values.filter({ $0 == value }).count == 1 else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
        }
        func observation(_ value: LightingObservationV1) throws { try exact(value, try context.fetch(FetchDescriptor<LightingObservationRow>()).map { try $0.value() }) }
        func plan(_ value: MeasurementPlanV1) throws { try exact(value, try context.fetch(FetchDescriptor<MeasurementPlanRow>()).map { try $0.value() }) }
        func protocolRelease(_ value: MeasurementProtocolReleaseV1) throws { try exact(value, try context.fetch(FetchDescriptor<MeasurementProtocolReleaseRow>()).map { try $0.value() }) }
        func captures(_ values: [MeasurementCaptureV1]) throws { let rows=try context.fetch(FetchDescriptor<MeasurementCaptureRow>()).map{try $0.value()};for value in values{try exact(value,rows)} }
        func instrument(_ value: InstrumentReferenceV1) throws { try exact(value, try context.fetch(FetchDescriptor<InstrumentReferenceRow>()).map { try $0.value() }) }
        func calibration(_ value: CalibrationStatusSnapshotV1) throws { try exact(value, try context.fetch(FetchDescriptor<CalibrationStatusSnapshotRow>()).map { try $0.value() }) }
        func quality(_ values: [MeasurementQualityAssessmentV1]) throws { let rows=try context.fetch(FetchDescriptor<MeasurementQualityAssessmentRow>()).map{try $0.value()};for value in values{try exact(value,rows)} }
        func claim(_ admission: LightingClaimAdmissionClosureV1, value: LightingClaimStateV1) throws {
            switch admission {
            case .observed(let o): try observation(o)
            case .measured(let o,let p,let protocolValue,let c,_,let i,let calibrationValue,let q): try observation(o);try plan(p);try protocolRelease(protocolValue);try captures(c);try instrument(i);try calibration(calibrationValue);try quality(q)
            case .derived(let o,let p,let protocolValue,let evaluator,let c,_,let i,let calibrationValue,let q): try observation(o);try plan(p);try protocolRelease(protocolValue);try exact(evaluator,try context.fetch(FetchDescriptor<DerivedFactEvaluatorDescriptorRow>()).map{try $0.value()});guard let provenance=value.derivedFact else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};try exact(provenance,try context.fetch(FetchDescriptor<DerivedFactProvenanceRow>()).map{try $0.value()});try captures(c);try instrument(i);try calibration(calibrationValue);try quality(q)
            case .screened(let o,let p,let protocolValue,let c,_,let i,let calibrationValue,let q,let classification,_,let authority,let basis,let applicability,let scope): try observation(o);try plan(p);try protocolRelease(protocolValue);try captures(c);try instrument(i);try calibration(calibrationValue);try quality(q);try exact(classification,try context.fetch(FetchDescriptor<FindingClassificationBindingRow>()).map{try $0.value()});try exact(authority,try context.fetch(FetchDescriptor<AuthoritySourceReleaseRow>()).map{try $0.value()});try exact(basis,try context.fetch(FetchDescriptor<RequirementBasisBindingRow>()).map{try $0.value()});try exact(applicability,try context.fetch(FetchDescriptor<ApplicabilityContextSnapshotRow>()).map{try $0.value()});try exact(scope,try context.fetch(FetchDescriptor<AssessmentScopeSnapshotRow>()).map{try $0.value()})
            case .externallyAttested(let o,let attestation): try observation(o);try exact(attestation,try context.fetch(FetchDescriptor<AttestationRow>()).map{try $0.value()})
            }
        }
        switch operation {
        case .appendSystem(let system,_,let admission):
            let descriptors=try context.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>()).map{try $0.value()}
            let events=try context.fetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>()).map{try $0.value()}
            for value in admission.descriptors { try exact(value,descriptors) }
            for value in admission.relationshipEvents { try exact(value,events) }
            let requiredDescriptorIDs=Set(system.luminaires.compactMap{$0.supportRelationship?.descriptorReleaseID})
            let requiredEventIDs=Set(system.luminaires.compactMap(\.supportRelationshipEventID))
            let relationshipIDs=Set(system.luminaires.compactMap{$0.supportRelationship?.relationshipID})
            guard Set(admission.descriptors.map(\.descriptorReleaseID))==requiredDescriptorIDs,
                  requiredEventIDs.isSubset(of:Set(admission.relationshipEvents.map(\.eventID))),
                  admission.relationshipEvents.allSatisfy({relationshipIDs.contains($0.relationshipID)}) else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
        case .appendIssue(_,_,let admission): try observation(admission.observation)
        case .appendClaim(let value,_,let admission): try claim(admission,value:value)
        case .appendObservation, .appendMeasurementPlan: break
        }
    }
}

enum C34SceneNavigationWorkspaceWriterAdapterBoundaryV1 {
    static let adapterWriteCount = 0
    static let resolvesOrRestoresRoutes = false
    static func validate() -> Bool { adapterWriteCount == 0 && !resolvesOrRestoresRoutes && C34SceneNavigationWorkspaceWriterBoundaryV1.validate() }
}
// C52_BOUNDARY_ANCHOR: canonical-service-request-apply-recover

extension WorkspaceWriterAdapterV1: ShopReportProfileCurrentReadingV1 {}
extension WorkspaceWriterAdapterV1: RoundSessionCurrentReadingV1 {}
