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
            .applyClientCapability,
            .applyFieldReference,
            .applyAccessibleDocumentAssessment,
            .applySurveyDefinition,
            .applySurveySession,
            .applyAssetLocator,
            .applySchedule,
            .applyPlan,
            .applyPlacementPose,
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

    init(
        modelContext: ModelContext,
        assetSemanticLifecycleAdapter: AssetSemanticLifecycleAdapterV1? = nil
    ) {
        self.modelContext = modelContext
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
        case let .applyClientCapability(value):return try applyClientCapability(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyFieldReference(value):return try applyFieldReference(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyAccessibleDocumentAssessment(value):return try applyAccessibleDocumentAssessment(value,temporaryRelativePath:temporaryRelativePath)
        case let .applySurveyDefinition(value):return try applySurveyDefinition(value,temporaryRelativePath:temporaryRelativePath)
        case let .applySurveySession(value):return try applySurveySession(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyAssetLocator(value):return try applyAssetLocator(value,temporaryRelativePath:temporaryRelativePath)
        case let .applySchedule(value):return try applySchedule(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyPlan(value):return try applyPlan(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyPlacementPose(value):return try applyPlacementPose(value,temporaryRelativePath:temporaryRelativePath)
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
            func requireAsset(_ value:AssetLocatorV1)throws{let assetID=value.assetID,assets=try modelContext.fetch(FetchDescriptor<Asset>(predicate:#Predicate{$0.id==assetID}));guard assets.count==1 else{throw WorkspaceMutationFailureV1.invalidCommand}}
            func requireReceipt(_ expected:LocatorBindingReceiptV1?)throws{guard let expected else{return};let matches=receipts.filter{$0.receiptID==expected.receiptID};guard matches.count==1,matches[0]==expected,receipts.filter({$0.predecessorReceiptID==expected.receiptID}).isEmpty else{throw WorkspaceMutationFailureV1.invalidCommand}}
            func requireAvailable(_ value:AssetLocatorV1,excluding:UUID?=nil)throws{let matches=all.filter{$0.workspaceID==value.workspaceID&&$0.lookupKey==value.lookupKey&&$0.state == .active&&$0.locatorID != excluding};guard matches.isEmpty else{throw WorkspaceMutationFailureV1.sequenceCollision}}
            switch mutation.payload{
            case let .bind(value,receipt,predecessorReceipt):guard all.filter({$0.locatorID==value.locatorID}).isEmpty,receipts.filter({$0.receiptID==receipt.receiptID}).isEmpty else{throw WorkspaceMutationFailureV1.sequenceCollision};try requireAsset(value);try requireReceipt(predecessorReceipt);try requireAvailable(value);try requireExactActor(receipt.recordedBy);modelContext.insert(try AssetLocatorRow(value));modelContext.insert(try LocatorBindingReceiptRow(receipt))
            case let .transition(value,receipt,prior,predecessorReceipt):let id=prior.locatorID,rows=allRows.filter{$0.locatorID==id};guard rows.count==1,try rows[0].value()==prior,receipts.filter({$0.receiptID==receipt.receiptID}).isEmpty else{throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind:.assetLocator,id:id))};try requireAsset(value);try requireReceipt(predecessorReceipt);if value.state == .active{try requireAvailable(value,excluding:id)};try requireExactActor(receipt.recordedBy);try rows[0].replace(with:value,expectedRevision:prior.revision);modelContext.insert(try LocatorBindingReceiptRow(receipt))
            case let .replace(value,replacement,receipt,prior,predecessorReceipt):let id=prior.locatorID,rows=allRows.filter{$0.locatorID==id};guard rows.count==1,try rows[0].value()==prior,all.filter({$0.locatorID==replacement.locatorID}).isEmpty,receipts.filter({$0.receiptID==receipt.receiptID}).isEmpty else{throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind:.assetLocator,id:id))};try requireAsset(value);try requireAsset(replacement);try requireReceipt(predecessorReceipt);try requireAvailable(replacement,excluding:id);try requireExactActor(receipt.recordedBy);try rows[0].replace(with:value,expectedRevision:prior.revision);modelContext.insert(try AssetLocatorRow(replacement));modelContext.insert(try LocatorBindingReceiptRow(receipt))
            }
            return try WorkspaceMutationEffectV1(affectedEntities:mutation.affectedIdentities,temporaryRelativePath:temporaryRelativePath)
        }catch let failure as WorkspaceMutationFailureV1{modelContext.rollback();throw failure}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}
    }
    private func applySchedule(_ mutation:ScheduleMutationV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{do{try mutation.validate();let releaseRows=try modelContext.fetch(FetchDescriptor<ScheduleDefinitionReleaseRow>()),eventRows=try modelContext.fetch(FetchDescriptor<OccurrenceHistoryEventRow>()),releases=try releaseRows.map{$0.value()},events=try eventRows.map{$0.value()};func requireRelease(_ value:ScheduleDefinitionReleaseV1)throws{let matches=releases.filter{$0.releaseID==value.releaseID};guard matches.count==1,matches[0]==value else{throw WorkspaceMutationFailureV1.invalidCommand}};func requireWork(_ value:ScheduledWorkInstanceReferenceV1?)throws{guard let value else{return};switch value{case let .workPacket(reference):let id=reference.manifestID,rows=try modelContext.fetch(FetchDescriptor<WorkPacketManifestRow>(predicate:#Predicate{$0.manifestID==id}));guard rows.count==1,let stored=try rows.first?.value(),try WorkPacketManifestReferenceV1(stored)==reference else{throw WorkspaceMutationFailureV1.invalidCommand};case let .roundSession(sessionID,revision,digest):let id=sessionID,rows=try modelContext.fetch(FetchDescriptor<SurveySessionRow>(predicate:#Predicate{$0.sessionID==id}));guard rows.count==1,let stored=try rows.first?.value(),stored.revision==revision,stored.sessionSHA256==digest else{throw WorkspaceMutationFailureV1.invalidCommand}}};func appendEvent(_ value:OccurrenceHistoryEventV1,_ predecessor:OccurrenceHistoryEventV1?,_ release:ScheduleDefinitionReleaseV1)throws{try requireRelease(release);try requireWork(value.workInstance);guard events.filter({$0.eventID==value.eventID}).isEmpty else{throw WorkspaceMutationFailureV1.sequenceCollision};if let predecessor{let matches=events.filter{$0.eventID==predecessor.eventID},successors=events.filter{$0.predecessorEventID==predecessor.eventID};guard matches.count==1,matches[0]==predecessor,successors.isEmpty else{throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind:.occurrenceHistoryEvent,id:predecessor.eventID))}}else{guard events.filter({$0.occurrenceID==value.occurrenceID}).isEmpty else{throw WorkspaceMutationFailureV1.sequenceCollision}};try value.validate(predecessor:predecessor);modelContext.insert(try OccurrenceHistoryEventRow(value))};switch mutation.payload{case let .appendRelease(value,predecessor):guard releases.filter({$0.releaseID==value.releaseID}).isEmpty else{throw WorkspaceMutationFailureV1.sequenceCollision};if let predecessor{let matches=releases.filter{$0.releaseID==predecessor.releaseID},successors=releases.filter{$0.supersedesReleaseID==predecessor.releaseID};guard matches.count==1,matches[0]==predecessor,successors.isEmpty else{throw WorkspaceMutationFailureV1.staleEntityRevision(try .init(kind:.scheduleDefinitionRelease,id:predecessor.releaseID))};try value.validateSuccessor(of:predecessor)};modelContext.insert(try ScheduleDefinitionReleaseRow(value));case let .appendOccurrenceEvent(value,predecessor,release):try appendEvent(value,predecessor,release);case let .startOccurrence(value,predecessor,release):try appendEvent(value,predecessor,release);case let .generateOccurrences(release,plan,values):try requireRelease(release);try plan.validate(definition:release);let existingIDs=Set(events.filter{$0.scheduleRelease.releaseID==release.releaseID}.map(\.occurrenceID));guard existingIDs==Set(plan.existingOccurrenceIDs)else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision};for value in values{try appendEvent(value,nil,release)}};return try WorkspaceMutationEffectV1(affectedEntities:mutation.affectedIdentities,temporaryRelativePath:temporaryRelativePath)}catch let failure as WorkspaceMutationFailureV1{modelContext.rollback();throw failure}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}}
    private func applyPlan(_ mutation:PlanMutationV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{do{try mutation.validate();let documents=try modelContext.fetch(FetchDescriptor<PlanDocumentRow>()).map{try $0.value()},revisions=try modelContext.fetch(FetchDescriptor<PlanRevisionRow>()).map{try $0.value()},placements=try modelContext.fetch(FetchDescriptor<PlanPlacementRow>()).map{try $0.value()},receipts=try modelContext.fetch(FetchDescriptor<RebaseReceiptRow>()).map{try $0.value()};func noSuccessor<T>(_ all:[T],_ count:(T)->Bool)throws{let n=all.filter(count).count;guard n==0 else{throw n>1 ? WorkspaceMutationFailureV1.persistenceFailed:.staleWorkspaceRevision}};func requireRevisionReferences(_ value:PlanRevisionV1)throws{let releaseID=value.contentBinding.fieldReferenceReleaseID,releaseRows=try modelContext.fetch(FetchDescriptor<FieldReferenceReleaseRow>(predicate:#Predicate{$0.releaseID==releaseID}));guard releaseRows.count==1,let release=try releaseRows.first?.value(),release.workspaceID==value.workspaceID,release.revision==value.contentBinding.fieldReferenceReleaseRevision,release.releaseSHA256==value.contentBinding.fieldReferenceReleaseSHA256,release.manifestSHA256==value.contentBinding.fieldReferenceManifestSHA256 else{throw WorkspaceMutationFailureV1.invalidCommand};let documentMatches=documents.filter{$0.planDocumentID==value.planDocument.planDocumentID&&$0.revision==value.planDocument.revision&&$0.documentSHA256==value.planDocument.documentSHA256};guard documentMatches.count==1 else{throw WorkspaceMutationFailureV1.invalidCommand}};func requirePlacementReferences(_ value:PlanPlacementV1)throws{let revisionMatches=revisions.filter{$0.planRevisionID==value.planRevision.planRevisionID&&$0.revision==value.planRevision.revision&&$0.revisionSHA256==value.planRevision.revisionSHA256};guard revisionMatches.count==1 else{throw WorkspaceMutationFailureV1.invalidCommand};if let binding=value.assetLocatorBinding{let receiptID=binding.bindingReceiptID,rows=try modelContext.fetch(FetchDescriptor<LocatorBindingReceiptRow>(predicate:#Predicate{$0.receiptID==receiptID}));guard rows.count==1,let stored=try rows.first?.value(),stored.revision==binding.bindingReceiptRevision,stored.receiptSHA256==binding.bindingReceiptSHA256,stored.after==binding.locator,stored.after.assetID==binding.assetID else{throw WorkspaceMutationFailureV1.invalidCommand}}};switch mutation.payload{case let .appendDocument(value,predecessor):guard documents.filter({$0.mutationID==value.mutationID}).isEmpty else{throw WorkspaceMutationFailureV1.sequenceCollision};if let predecessor{guard documents.filter({$0.documentSHA256==predecessor.documentSHA256}).count==1 else{throw WorkspaceMutationFailureV1.invalidCommand};try noSuccessor(documents){$0.supersedesDocumentSHA256==predecessor.documentSHA256}};modelContext.insert(try PlanDocumentRow(value));case let .appendRevision(value,predecessor,_):try requireRevisionReferences(value);guard revisions.filter({$0.planRevisionID==value.planRevisionID}).isEmpty else{throw WorkspaceMutationFailureV1.sequenceCollision};if let predecessor{guard revisions.filter({$0.planRevisionID==predecessor.planRevisionID&&$0==predecessor}).count==1 else{throw WorkspaceMutationFailureV1.invalidCommand};try noSuccessor(revisions){$0.supersedesPlanRevisionID==predecessor.planRevisionID}};modelContext.insert(try PlanRevisionRow(value));case let .appendPlacement(value,predecessor,_):try requirePlacementReferences(value);if let predecessor{guard placements.filter({$0.placementSHA256==predecessor.placementSHA256}).count==1 else{throw WorkspaceMutationFailureV1.invalidCommand};try noSuccessor(placements){$0.supersedesPlacementSHA256==predecessor.placementSHA256}};modelContext.insert(try PlanPlacementRow(value));case let .applyRebase(newRevision,priorRevision,values,priors,receipt,predecessorReceipt,poseEffects):guard revisions.filter({$0.planRevisionID==priorRevision.planRevisionID&&$0==priorRevision}).count==1,revisions.filter({$0.planRevisionID==newRevision.planRevisionID}).isEmpty else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision};try noSuccessor(revisions){$0.supersedesPlanRevisionID==priorRevision.planRevisionID};try requireRevisionReferences(newRevision);for prior in priors{guard placements.filter({$0.placementSHA256==prior.placementSHA256}).count==1 else{throw WorkspaceMutationFailureV1.invalidCommand};try noSuccessor(placements){$0.supersedesPlacementSHA256==prior.placementSHA256}};for value in values{try requirePlacementReferencesAgainst(value,newRevision)};try requireReceiptPredecessor(predecessorReceipt,receipts);if let poseEffects{_ = try applyPlacementPose(poseEffects,temporaryRelativePath:temporaryRelativePath)};modelContext.insert(try PlanRevisionRow(newRevision));for value in values{modelContext.insert(try PlanPlacementRow(value))};modelContext.insert(try RebaseReceiptRow(receipt));case let .recordRebaseRejection(receipt,predecessorReceipt):try requireReceiptPredecessor(predecessorReceipt,receipts);modelContext.insert(try RebaseReceiptRow(receipt))};return try WorkspaceMutationEffectV1(affectedEntities:mutation.affectedIdentities,temporaryRelativePath:temporaryRelativePath)}catch let failure as WorkspaceMutationFailureV1{modelContext.rollback();throw failure}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}}

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
