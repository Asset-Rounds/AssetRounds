import Foundation

struct GuidedSurveyFlowRequestV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let definitionRelease: SurveyDefinitionReleaseReferenceV1
    let sessionID: UUID
    let sessionRevision: UInt64
    let sessionSHA256: String
    let resumeContext: GuidedSurveyResumeContextV1
    let favorite: Bool
    let recentOrdinal: Int?

    func validate() throws {
        try definitionRelease.validate()
        guard sessionID != SurveyDefinitionLimitsV1.zero, sessionRevision > 0,
              KernelCanonicalHashV1.validSHA256(sessionSHA256),
              workspaceID == resumeContext.workspaceID,
              sessionID == resumeContext.sessionID,
              sessionRevision == resumeContext.sessionRevision,
              sessionSHA256 == resumeContext.sessionSHA256,
              recentOrdinal.map({ $0 >= 0 }) ?? true else {
            throw GuidedSurveyFlowFailureV1.invalidValue
        }
    }
}

struct GuidedSurveyFlowSourceV1: Sendable {
    let request: GuidedSurveyFlowRequestV1
    let definition: SurveyDefinitionReleaseV1
    let identity: SurveyDefinitionIdentityV1
    let lifecycleEvent: SurveyDefinitionLifecycleEventV1
    let session: SurveySessionV1
    let captures: [FactCaptureV1]
    let publication: SurveyPublicationSnapshotV1?
    let packageRelease: InspectionPackageReleaseV1
    let poseRegistryRelease: PoseAxisRegistryReleaseV1?
    let priorFacts: [GuidedSurveyPriorFactV1]

    func validate() throws {
        try request.validate(); try definition.validate()
        try identity.validate(currentRelease: definition, event: lifecycleEvent)
        try session.validate(definition: definition)
        try session.authority.validate(definition: definition, packageRelease: packageRelease)
        try captures.forEach { try $0.validate(session: session, definition: definition) }
        if let publication {
            try publication.validate(session: session, definition: definition, captures: captures)
        }
        try poseRegistryRelease?.validate(packageRelease: packageRelease)
        try priorFacts.forEach { try $0.validate() }
        guard definition.workspaceID == request.workspaceID,
              session.workspaceID == request.workspaceID,
              request.definitionRelease == (try SurveyDefinitionReleaseReferenceV1(definition)),
              session.sessionID == request.sessionID, session.revision == request.sessionRevision,
              session.sessionSHA256 == request.sessionSHA256,
              publication.map({ $0.workspaceID == request.workspaceID &&
                                $0.sessionID == session.sessionID &&
                                session.latestPublication == $0.reference }) ?? true,
              poseRegistryRelease.map({ $0.packageReleaseID == session.authority.packageRelease.packageReleaseID }) ?? true,
              priorFacts.map(\.factID) == priorFacts.map(\.factID).sorted(),
              Set(priorFacts.map(\.factID)).count == priorFacts.count else {
            throw GuidedSurveyFlowFailureV1.staleSource
        }
    }

    func projection() throws -> GuidedSurveyFlowV1 {
        try validate()
        return try .init(workspaceID: request.workspaceID, definition: definition,
            identity: identity, lifecycleEvent: lifecycleEvent, session: session,
            captures: captures, publication: publication,
            resumeContext: request.resumeContext,
            poseRequirement: .init(release: poseRegistryRelease), priorFacts: priorFacts,
            favorite: request.favorite, recentOrdinal: request.recentOrdinal)
    }
}

struct GuidedSurveyFlowLifecycleOperationsV1: Sendable {
    let exactDefinitionRelease: @Sendable (WorkspaceID, SurveyDefinitionReleaseReferenceV1) async throws -> SurveyDefinitionReleaseV1?
    let exactDefinitionIdentityAndEvent: @Sendable (WorkspaceID, UUID, UInt64) async throws -> (SurveyDefinitionIdentityV1, SurveyDefinitionLifecycleEventV1)?
    let exactSession: @Sendable (WorkspaceID, UUID, UInt64, String) async throws -> SurveySessionV1?
    let exactCaptures: @Sendable (WorkspaceID, UUID, SurveyDefinitionReleaseReferenceV1) async throws -> [FactCaptureV1]
    let exactPublication: @Sendable (WorkspaceID, SurveyPublicationReferenceV1) async throws -> SurveyPublicationSnapshotV1?
    let exactPackageRelease: @Sendable (SurveyPackageReleaseReferenceV1) async throws -> InspectionPackageReleaseV1?
    let exactPoseRegistryRelease: @Sendable (InspectionPackageReleaseV1) async throws -> PoseAxisRegistryReleaseV1?
    let priorPermittedFacts: @Sendable (WorkspaceID, SurveySessionSubjectV1, SurveyDefinitionReleaseV1) async throws -> [GuidedSurveyPriorFactV1]
}

@MainActor
final class GuidedSurveyFlowLifecycleAdapterV1: GuidedSurveyFlowSourceResolvingV1, @unchecked Sendable {
    private let operations: GuidedSurveyFlowLifecycleOperationsV1
    init(operations: GuidedSurveyFlowLifecycleOperationsV1) { self.operations = operations }

    func source(for request: GuidedSurveyFlowRequestV1) async throws -> GuidedSurveyFlowSourceV1 {
        try request.validate()
        guard let definition = try await operations.exactDefinitionRelease(
            request.workspaceID, request.definitionRelease
        ), let pair = try await operations.exactDefinitionIdentityAndEvent(
            request.workspaceID, request.definitionRelease.definitionID,
            request.definitionRelease.revision
        ), let session = try await operations.exactSession(
            request.workspaceID, request.sessionID, request.sessionRevision,
            request.sessionSHA256
        ) else { throw GuidedSurveyFlowFailureV1.missingExactSource }
        let captures = try await operations.exactCaptures(
            request.workspaceID, request.sessionID, request.definitionRelease
        ).sorted { $0.captureID.uuidString < $1.captureID.uuidString }
        let publication: SurveyPublicationSnapshotV1?
        if let reference = session.latestPublication {
            publication = try await operations.exactPublication(request.workspaceID, reference)
            guard publication != nil else { throw GuidedSurveyFlowFailureV1.missingExactSource }
        } else { publication = nil }
        guard let package = try await operations.exactPackageRelease(session.authority.packageRelease) else {
            throw GuidedSurveyFlowFailureV1.missingExactSource
        }
        let pose = try await operations.exactPoseRegistryRelease(package)
        let prior = try await operations.priorPermittedFacts(
            request.workspaceID, session.subject, definition
        ).sorted { $0.factID < $1.factID }
        let value = GuidedSurveyFlowSourceV1(
            request: request, definition: definition, identity: pair.0,
            lifecycleEvent: pair.1, session: session, captures: captures,
            publication: publication, packageRelease: package,
            poseRegistryRelease: pose, priorFacts: prior
        )
        try value.validate(); return value
    }
}
