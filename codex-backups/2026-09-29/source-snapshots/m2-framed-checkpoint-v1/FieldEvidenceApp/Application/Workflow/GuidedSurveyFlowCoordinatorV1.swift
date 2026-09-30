import Foundation

@MainActor
protocol GuidedSurveyFlowSourceResolvingV1: Sendable {
    func source(for request: GuidedSurveyFlowRequestV1) async throws -> GuidedSurveyFlowSourceV1
}

@MainActor
final class GuidedSurveyFlowCoordinatorV1 {
    private let source: any GuidedSurveyFlowSourceResolvingV1
    private let definitions: SurveyDefinitionCoordinatorV1
    private let sessions: SurveySessionCoordinatorV1
    private let drafts: FieldDraftCoordinatorV1

    init(source: any GuidedSurveyFlowSourceResolvingV1,
         definitions: SurveyDefinitionCoordinatorV1,
         sessions: SurveySessionCoordinatorV1,
         drafts: FieldDraftCoordinatorV1) {
        self.source = source; self.definitions = definitions
        self.sessions = sessions; self.drafts = drafts
    }

    func flow(for request: GuidedSurveyFlowRequestV1) async throws -> GuidedSurveyFlowV1 {
        let value = try await source.source(for: request)
        return try value.projection()
    }

    func checkpoint(_ value: FieldDraftCheckpointV1,
                    expectedDraftRevision: UInt64,
                    expectedBaseRevision: UInt64) throws -> MutationReceiptV1 {
        try drafts.checkpoint(value, expectedDraftRevision: expectedDraftRevision,
                              expectedBaseRevision: expectedBaseRevision)
    }

    func createDefinitionDraft(identity: SurveyDefinitionIdentityV1,
                               release: SurveyDefinitionReleaseV1,
                               event: SurveyDefinitionLifecycleEventV1) async throws
        -> SurveyDefinitionMutationReceiptV1 {
        try await definitions.createDraft(identity: identity, release: release, event: event)
    }

    func applyDefinitionSuccessor(previousIdentity: SurveyDefinitionIdentityV1,
                                  previousRelease: SurveyDefinitionReleaseV1,
                                  previousEvent: SurveyDefinitionLifecycleEventV1,
                                  identity: SurveyDefinitionIdentityV1,
                                  release: SurveyDefinitionReleaseV1,
                                  event: SurveyDefinitionLifecycleEventV1) async throws
        -> SurveyDefinitionMutationReceiptV1 {
        try await definitions.applySuccessor(
            previousIdentity: previousIdentity, previousRelease: previousRelease,
            previousEvent: previousEvent, identity: identity, release: release, event: event
        )
    }

    func previewSemanticAdoption(source: SurveyDefinitionReleaseV1,
                                 target: SurveyDefinitionReleaseV1,
                                 affectedDraftIDs: [UUID], pinnedActiveWorkCount: Int,
                                 generatedAt: Date) async throws -> SurveyDefinitionAdoptionPreviewV1 {
        try await definitions.previewAdoption(source: source, target: target,
            affectedDraftIDs: affectedDraftIDs,
            pinnedActiveWorkCount: pinnedActiveWorkCount, generatedAt: generatedAt)
    }

    func importAsFreshDraft(candidate: SurveyTemplateQuarantineCandidateV1,
                            newDefinitionID: UUID, newReleaseID: UUID, newEventID: UUID,
                            workspaceID: WorkspaceID, actor: ActorSnapshotV1,
                            mutationID: MutationIDV1, recordedAt: Date) async throws
        -> SurveyDefinitionMutationReceiptV1 {
        try await definitions.importAsNewDraft(
            candidate: candidate, newDefinitionID: newDefinitionID,
            newReleaseID: newReleaseID, newEventID: newEventID,
            workspaceID: workspaceID, actor: actor, mutationID: mutationID,
            recordedAt: recordedAt
        )
    }

    func applySession(_ session: SurveySessionV1,
                      definition: SurveyDefinitionReleaseV1,
                      packageRelease: InspectionPackageReleaseV1) throws
        -> SurveySessionMutationReceiptV1 {
        try sessions.apply(session: session, definition: definition,
                           packageRelease: packageRelease)
    }

    func capture(_ capture: FactCaptureV1, session: SurveySessionV1,
                 definition: SurveyDefinitionReleaseV1,
                 packageRelease: InspectionPackageReleaseV1,
                 predecessors: [FactCaptureV1]) throws -> SurveySessionMutationReceiptV1 {
        try sessions.capture(capture, session: session, definition: definition,
                             packageRelease: packageRelease, predecessors: predecessors)
    }

    func publish(session: SurveySessionV1, snapshot: SurveyPublicationSnapshotV1,
                 definition: SurveyDefinitionReleaseV1,
                 packageRelease: InspectionPackageReleaseV1,
                 captures: [FactCaptureV1]) throws -> SurveySessionMutationReceiptV1 {
        try sessions.publish(session: session, snapshot: snapshot, definition: definition,
                             packageRelease: packageRelease, captures: captures)
    }

    func promote(provisionalSubject: ProvisionalSubjectV1,
                 receipt: SubjectPromotionReceiptV1,
                 preview: SubjectPromotionPreviewV1,
                 predecessor: SubjectPromotionReceiptV1?) throws
        -> SurveySessionMutationReceiptV1 {
        try sessions.promote(provisionalSubject: provisionalSubject, receipt: receipt,
                             preview: preview, predecessor: predecessor)
    }
}
