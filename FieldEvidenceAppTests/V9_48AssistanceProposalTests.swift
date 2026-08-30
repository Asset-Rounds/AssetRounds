import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_V9_48AssistanceProposalTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

private final class C45AssistanceCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityNeverTreatsDerivedProposalOrPlanAsAcceptedSnapshot() {
        XCTAssertEqual(AssetLabelPersistenceEnrollmentV1.persistentFamilies, ["AcceptedLabelGenerationSnapshotRow"])
        XCTAssertFalse(AssetLabelPersistenceEnrollmentV1.persistentFamilies.contains("AssetLabelGenerationPlanV1"))
        XCTAssertEqual(LabelOutputActivationDecisionV1.disabledOrDeferred.rawValue, "DISABLED_OR_DEFERRED")
    }
}

enum C32AssistanceTestSupport {
    static let fixedDate = Date(timeIntervalSince1970: 1_810_003_200)
    static let packageDigest = String(repeating: "a", count: 64)
    static let definitionDigest = String(repeating: "b", count: 64)
    static let sourceDigest = String(repeating: "c", count: 64)

    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c3200000-0000-4000-8000-%012x", slot))!
    }

    static func workspace(_ slot: Int = 1) -> WorkspaceID {
        WorkspaceID(rawValue: id(slot))
    }

    static func capability(
        id: String = "OCR_FIELD_PROPOSAL",
        version: String = "OCR_FIELD_PROPOSAL_V1",
        locale: String? = "en-US"
    ) throws -> AssistanceCapabilityReferenceV1 {
        try AssistanceCapabilityReferenceV1(
            capabilityID: id,
            version: version,
            localeIdentifier: locale
        )
    }

    static func policy(
        capability: AssistanceCapabilityReferenceV1? = nil,
        enabled: Bool = true,
        confidence: AssistanceMetadataRequirementV1 = .required,
        quality: AssistanceMetadataRequirementV1 = .optional,
        fallback: ManualFallbackActionV1 = .typeManually
    ) throws -> AssistanceCapabilityPolicyV1 {
        try AssistanceCapabilityPolicyV1(
            capability: capability ?? self.capability(),
            enabled: enabled,
            confidenceRequirement: confidence,
            qualityRequirement: quality,
            manualFallback: fallback
        )
    }

    static func source(
        kind: AssistanceSourceKindV1 = .leasedScratch,
        sourceID: String = "scratch-c32-source",
        revision: UInt64 = 1,
        digest: String = sourceDigest
    ) throws -> AssistanceSourceReferenceV1 {
        try AssistanceSourceReferenceV1(
            kind: kind,
            sourceID: sourceID,
            revision: revision,
            contentSHA256: digest
        )
    }

    static func target(
        workspaceID: WorkspaceID = workspace(),
        entityKind: WorkspaceEntityKindV1 = .asset,
        entityID: UUID = id(20),
        revision: UInt64 = 7,
        fieldID: String = "survey.fact-a"
    ) throws -> AssistanceTargetV1 {
        try AssistanceTargetV1(
            workspaceID: workspaceID,
            entity: WorkspaceEntityIdentityV1(kind: entityKind, id: entityID),
            revision: revision,
            fieldID: fieldID
        )
    }

    static func proposal(
        slot: Int = 30,
        capability: AssistanceCapabilityReferenceV1? = nil,
        target: AssistanceTargetV1? = nil,
        value: ResponseValueV1 = .text("Observed local field value"),
        source: AssistanceSourceReferenceV1? = nil,
        confidence: AssistanceConfidenceV1? = try? AssistanceConfidenceV1(basisPoints: 8_750),
        quality: AssistanceQualityMetadataV1? = try? AssistanceQualityMetadataV1(
            metricID: "OCR_TEXT_QUALITY",
            ratingID: "REVIEW_REQUIRED"
        ),
        packageDigest: String? = packageDigest,
        definitionDigest: String? = definitionDigest,
        createdAt: Date = fixedDate,
        expiresAt: Date? = nil,
        privacyClass: AssistancePrivacyClassV1 = .workspaceOperational
    ) throws -> AssistanceProposalV1 {
        try AssistanceProposalV1(
            proposalID: id(slot),
            capability: capability ?? self.capability(),
            target: target ?? self.target(),
            value: value,
            source: source ?? self.source(),
            confidence: confidence,
            quality: quality,
            packageReleaseSHA256: packageDigest,
            definitionReleaseSHA256: definitionDigest,
            createdAt: createdAt,
            expiresAt: expiresAt ?? createdAt.addingTimeInterval(600),
            privacyClass: privacyClass
        )
    }

    static func context(
        proposal: AssistanceProposalV1,
        workspaceID: WorkspaceID? = nil,
        targetRevision: UInt64? = nil,
        policy: AssistanceCapabilityPolicyV1? = nil,
        packageDigest: String?? = nil,
        definitionDigest: String?? = nil,
        source: AssistanceSourceReferenceV1?? = nil,
        evaluatedAt: Date? = nil
    ) throws -> AssistanceProposalEvaluationContextV1 {
        AssistanceProposalEvaluationContextV1(
            workspaceID: workspaceID ?? proposal.target.workspaceID,
            targetRevision: targetRevision ?? proposal.target.revision,
            policy: policy ?? (try self.policy(capability: proposal.capability)),
            packageReleaseSHA256: packageDigest ?? proposal.packageReleaseSHA256,
            definitionReleaseSHA256: definitionDigest ?? proposal.definitionReleaseSHA256,
            currentSource: source ?? .some(proposal.source),
            evaluatedAt: evaluatedAt ?? proposal.createdAt.addingTimeInterval(1)
        )
    }

    static func authoritativeState(
        proposal: AssistanceProposalV1,
        workspaceRevision: UInt64 = 12,
        targetRevision: UInt64? = nil,
        policy: AssistanceCapabilityPolicyV1? = nil,
        packageDigest: String?? = nil,
        definitionDigest: String?? = nil,
        source: AssistanceSourceReferenceV1?? = nil,
        evaluatedAt: Date
    ) throws -> AssistanceAuthoritativeStateV1 {
        try AssistanceAuthoritativeStateV1(
            workspaceRevision: WorkspaceRevisionV1(
                workspaceID: proposal.target.workspaceID,
                generationID: id(90),
                writerInstanceID: id(91),
                revision: workspaceRevision,
                entityRevisions: [
                    WorkspaceEntityRevisionV1(
                        identity: proposal.target.entity,
                        revision: targetRevision ?? proposal.target.revision
                    )
                ]
            ),
            policy: policy ?? self.policy(capability: proposal.capability),
            packageReleaseSHA256: packageDigest ?? proposal.packageReleaseSHA256,
            definitionReleaseSHA256: definitionDigest ?? proposal.definitionReleaseSHA256,
            currentSource: source ?? .some(proposal.source),
            evaluatedAt: evaluatedAt
        )
    }

    static func mutation(_ slot: Int = 40) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(slot))
    }

    static func expectedRevision(
        target: AssistanceTargetV1,
        workspaceRevision: UInt64 = 12
    ) throws -> WorkspaceExpectedRevisionV1 {
        try WorkspaceExpectedRevisionV1(
            workspaceID: target.workspaceID,
            generationID: id(50),
            writerInstanceID: id(51),
            workspaceRevision: workspaceRevision,
            entityRevisions: [
                WorkspaceEntityRevisionV1(identity: target.entity, revision: target.revision)
            ]
        )
    }

    struct AcceptanceFixture {
        let proposal: AssistanceProposalV1
        let targetMutation: AssistanceCanonicalTargetMutationV1
        let expectedRevision: WorkspaceExpectedRevisionV1
        let mutationID: MutationIDV1
        let reviewer: ActorSnapshotV1
        let acceptedAt: Date
    }

    static func acceptanceFixture(
        slot: Int,
        value: ResponseValueV1 = .text("explicitly reviewed local value"),
        workspaceRevision: UInt64 = 12,
        workspaceID: WorkspaceID? = nil
    ) throws -> AcceptanceFixture {
        let workspaceID = workspaceID ?? workspace()
        let release = try C26SurveySessionTestSupport.release(
            releaseSlot: 10 + slot,
            workspaceID: workspaceID
        )
        let authority = try C26SurveySessionTestSupport.authority(for: release)
        let provisional = try C26SurveySessionTestSupport.provisional(
            workspaceID: workspaceID,
            slot: 40 + slot
        )
        let session = try C26SurveySessionTestSupport.session(
            authority: authority,
            workspaceID: workspaceID,
            sessionID: id(2_000 + slot),
            subject: .provisional(provisional.reference),
            state: .draft,
            transition: .create,
            revision: 1,
            actorSlot: 600 + slot
        )
        let reviewer = try C26SurveySessionTestSupport.actor(
            workspaceID: session.workspaceID,
            slot: 1_000 + slot,
            responsibility: .reviewedBy
        )
        let acceptedAt = C26SurveySessionTestSupport.fixedDate.addingTimeInterval(Double(2_000 + slot))
        let capture = try FactCaptureV1(
            captureID: id(3_000 + slot),
            workspaceID: session.workspaceID,
            sessionID: session.sessionID,
            definitionRelease: session.authority.definitionRelease,
            factID: "fact-a",
            action: .record,
            value: value,
            predecessors: [],
            capturedBy: reviewer,
            capturedAt: acceptedAt,
            revision: 1,
            mutationID: C26SurveySessionTestSupport.mutation(5_000 + slot)
        )
        let mutation = try SurveySessionMutationV1(
            workspaceID: session.workspaceID,
            mutationID: capture.mutationID,
            payload: .captureFact(
                capture,
                session: session,
                definition: release,
                predecessors: []
            )
        )
        let targetMutation = AssistanceCanonicalTargetMutationV1.surveySession(mutation)
        let concurrency = try mutation.concurrencyIdentities
        let expectedRevision = try WorkspaceExpectedRevisionV1(
            workspaceID: session.workspaceID,
            generationID: id(6_000 + slot),
            writerInstanceID: id(7_000 + slot),
            workspaceRevision: workspaceRevision,
            entityRevisions: try concurrency.map {
                WorkspaceEntityRevisionV1(
                    identity: $0,
                    revision: try mutation.expectedRevision(for: $0)
                )
            }
        )
        let proposal = try AssistanceProposalV1(
            proposalID: id(8_000 + slot),
            capability: capability(),
            target: AssistanceTargetV1(
                workspaceID: session.workspaceID,
                entity: WorkspaceEntityIdentityV1(kind: .surveySession, id: session.sessionID),
                revision: session.revision,
                fieldID: capture.factID
            ),
            value: value,
            source: source(),
            confidence: AssistanceConfidenceV1(basisPoints: 8_750),
            quality: AssistanceQualityMetadataV1(
                metricID: "OCR_TEXT_QUALITY",
                ratingID: "REVIEW_REQUIRED"
            ),
            packageReleaseSHA256: session.authority.packageRelease.packageSHA256,
            definitionReleaseSHA256: release.releaseSHA256,
            createdAt: acceptedAt.addingTimeInterval(-60),
            expiresAt: acceptedAt.addingTimeInterval(600),
            privacyClass: .workspaceOperational
        )
        return AcceptanceFixture(
            proposal: proposal,
            targetMutation: targetMutation,
            expectedRevision: expectedRevision,
            mutationID: capture.mutationID,
            reviewer: reviewer,
            acceptedAt: acceptedAt
        )
    }

    static func reviewer(workspaceID: WorkspaceID = workspace()) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(
            actorReferenceID: id(60),
            workspaceID: workspaceID,
            displayName: "C32 local proposal reviewer"
        )
        return try ActorSnapshotV1(
            snapshotID: id(61),
            workspaceID: workspaceID,
            actor: reference,
            responsibility: .reviewedBy,
            displayNameAtTime: reference.displayName,
            capturedAt: fixedDate
        )
    }

    static func typedValues() throws -> [ResponseValueV1] {
        [
            .text("Observed local text"),
            .singleOption("NOT_OBSERVED"),
            .integer(4),
            .decimal(try ExactDecimalV1(mantissa: 1_250, scale: 2)),
            .boolean(true),
            .triState(.unknown),
            .duration(try ResponseDurationV1(milliseconds: 90_000)),
            .multipleOptions(["LOCAL", "REVIEWED"])
        ]
    }

    static func ownerProposal(
        entityKind: WorkspaceEntityKindV1,
        fieldID: String,
        value: ResponseValueV1
    ) throws -> AssistanceProposalV1 {
        try proposal(
            slot: 900,
            target: target(entityKind: entityKind, entityID: id(700), fieldID: fieldID),
            value: value,
            source: source(kind: .deterministicRule, sourceID: "owner-\(entityKind.rawValue)")
        )
    }

    static func replacingReleaseBindings(
        in proposal: AssistanceProposalV1,
        packageDigest: String?,
        definitionDigest: String?
    ) throws -> AssistanceProposalV1 {
        try AssistanceProposalV1(
            proposalID: proposal.proposalID,
            capability: proposal.capability,
            target: proposal.target,
            value: proposal.value,
            source: proposal.source,
            confidence: proposal.confidence,
            quality: proposal.quality,
            packageReleaseSHA256: packageDigest,
            definitionReleaseSHA256: definitionDigest,
            createdAt: proposal.createdAt,
            expiresAt: proposal.expiresAt,
            privacyClass: proposal.privacyClass
        )
    }

    @MainActor
    static func commitPersistentAcceptance(
        in session: StoreGenerationSession,
        slot: Int
    ) throws -> AssistanceAcceptanceReceiptV1 {
        let fixture = try acceptanceFixture(
            slot: slot,
            workspaceRevision: 0,
            workspaceID: session.workspaceID
        )
        let surveySession: SurveySessionV1
        switch fixture.targetMutation {
        case .surveySession(let mutation):
            guard case let .captureFact(_, capturedSession, _, _) = mutation.payload else {
                throw AssistanceContractFailureV1.invalidValue
            }
            surveySession = capturedSession
        }
        try C26SurveySessionTestSupport.seedPersistence(
            context: session.modelContext,
            session: surveySession,
            packageRelease: surveySession.authority.packageRelease,
            packageSlot: 12_000 + slot
        )
        session.modelContext.insert(EntityMutationRevisionRow(
            identity: fixture.proposal.target.entity,
            revision: fixture.proposal.target.revision
        ))
        try session.modelContext.save()
        let store = try MutationJournalStoreV1(
            modelContext: session.modelContext,
            identity: session.workspaceIdentity,
            generationID: session.generationID
        )
        let writer = try WorkspaceWriterV1(
            identity: session.workspaceIdentity,
            generationID: session.generationID,
            initialRevision: store.currentRevision(
                writerInstanceID: fixture.expectedRevision.writerInstanceID
            ),
            clock: C32PersistentClock(value: fixture.acceptedAt),
            idSource: C32PersistentIDSource(value: fixture.expectedRevision.writerInstanceID),
            fileAuthority: C32PersistentFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext),
            journalStore: store
        )
        let current = try store.currentRevision(
            writerInstanceID: fixture.expectedRevision.writerInstanceID
        )
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: fixture.expectedRevision.entityRevisions
        )
        return try writer.commitAssistanceAcceptance(AssistanceAcceptanceRequestV1(
            proposal: fixture.proposal,
            targetMutation: fixture.targetMutation,
            expectedRevision: expected,
            mutationID: fixture.mutationID,
            acceptedBy: fixture.reviewer,
            acceptedAt: fixture.acceptedAt
        ))
    }

    static func assertOwnerBoundary(
        _ proposal: AssistanceProposalV1,
        entityKind: WorkspaceEntityKindV1,
        fieldID: String,
        valueKind: ResponseValueKindV1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(proposal.target.entity.kind, entityKind, file: file, line: line)
        XCTAssertEqual(proposal.target.fieldID, fieldID, file: file, line: line)
        XCTAssertEqual(proposal.value.kind, valueKind, file: file, line: line)
        XCTAssertFalse(AssistancePersistenceEnrollmentV1.proposalIsPersistent, file: file, line: line)
        XCTAssertNil(try proposal.expiryReason(in: context(proposal: proposal)), file: file, line: line)
    }
}

private struct C32AssistanceCorpusV1: Decodable {
    let schema: String
    let schemaVersion: Int
    let cardID: String
    let proposalPersistenceDisposition: String
    let durableFamilies: [String]
    let persistentSchemaVersion: Int
    let recordsSchemaVersion: Int
    let requiredContractNames: [String]
    let evidenceIDs: [String]
    let transitionMatrix: [Transition]
    let expiryTriggers: [String]
    let hostileCases: [String]
    let lifecycle: Lifecycle
    let invariants: Invariants

    struct Transition: Decodable {
        let action: String
        let proposalDisposition: String
        let scratchDisposition: String
        let canonicalMutationCount: Int
        let durableAcceptanceReceiptCount: Int
    }

    struct Lifecycle: Decodable {
        let proposal: String
        let scratch: String
        let acceptanceReceipt: String
        let backup: String
        let restore: String
        let search: String
        let report: String
        let diagnostics: String
        let replication: String
        let deleteErase: String
    }

    struct Invariants: Decodable {
        let proposalNeverCanonical: Bool
        let proposalNeverPersistent: Bool
        let proposalNeverBackedUp: Bool
        let proposalNeverSearched: Bool
        let proposalNeverReported: Bool
        let noDirectMutation: Bool
        let explicitReviewRequired: Bool
        let expectedRevisionRequired: Bool
        let manualPathEquivalent: Bool
        let capabilitiesRollbackIndependently: Bool
        let noSharedGlobalConfidenceThreshold: Bool
        let noHiddenNetworkFallback: Bool
        let noDiagnosisOrComplianceSuggestion: Bool
        let rejectedProposalCorpusRetained: Bool
    }
}

@MainActor
private final class C32ScratchSpy: AssistanceScratchDiscardingV1 {
    private(set) var discarded: [(UUID, AssistanceSourceReferenceV1)] = []
    private(set) var finished: [(UUID, ScratchPublicationDispositionV1, String?)] = []
    private(set) var orphanRetentionSets: [Set<UUID>] = []

    func discardAssistanceScratch(
        proposalID: UUID,
        source: AssistanceSourceReferenceV1
    ) async throws {
        discarded.append((proposalID, source))
    }

    func discardOrphanedAssistanceScratch(
        retainingProposalIDs: Set<UUID>
    ) async throws {
        orphanRetentionSets.append(retainingProposalIDs)
    }

    func finishAssistanceScratch(
        proposalID: UUID,
        source: AssistanceSourceReferenceV1,
        disposition: ScratchPublicationDispositionV1,
        immutableContentReceiptDigest: String?
    ) async throws {
        discarded.append((proposalID, source))
        finished.append((proposalID, disposition, immutableContentReceiptDigest))
    }
}

@MainActor
private final class C32TrustedStateResolver: AssistanceCurrentStateResolvingV1 {
    private var contexts: [UUID: AssistanceProposalEvaluationContextV1] = [:]
    private var proposals: [UUID: AssistanceProposalV1] = [:]

    func trust(
        _ proposal: AssistanceProposalV1,
        context: AssistanceProposalEvaluationContextV1
    ) {
        contexts[proposal.proposalID] = context
        proposals[proposal.proposalID] = proposal
    }

    func obtainReviewSnapshot(
        for proposal: AssistanceProposalV1
    ) async throws -> AssistanceProposalEvaluationContextV1 {
        try proposal.validate()
        guard proposals[proposal.proposalID] == proposal,
              let context = contexts[proposal.proposalID] else {
            throw AssistanceContractFailureV1.staleTarget
        }
        return context
    }

    func currentEvaluationContext(
        proposalID: UUID,
        capability: AssistanceCapabilityReferenceV1,
        target: AssistanceTargetV1,
        source: AssistanceSourceReferenceV1
    ) async throws -> AssistanceProposalEvaluationContextV1 {
        guard let context = contexts[proposalID],
              let proposal = proposals[proposalID],
              proposal.capability == capability,
              proposal.target == target,
              proposal.source == source else {
            throw AssistanceContractFailureV1.staleTarget
        }
        return context
    }
}

@MainActor
private final class C32AuthoritativeStateReader: AssistanceAuthoritativeStateReadingV1 {
    var state: AssistanceAuthoritativeStateV1
    private(set) var requests: [(UUID, AssistanceCapabilityReferenceV1, AssistanceTargetV1, AssistanceSourceReferenceV1)] = []

    init(state: AssistanceAuthoritativeStateV1) {
        self.state = state
    }

    func readCurrentAssistanceState(
        proposalID: UUID,
        capability: AssistanceCapabilityReferenceV1,
        target: AssistanceTargetV1,
        source: AssistanceSourceReferenceV1
    ) async throws -> AssistanceAuthoritativeStateV1 {
        requests.append((proposalID, capability, target, source))
        return state
    }
}

private enum C32WriterInterruption: Error {
    case afterCanonicalEffect
}

private actor C32CapabilityScratchLeaseSpy: CapabilityScratchLeasePortV1 {
    private var requests: [UUID: CapabilityScratchLeaseRequestV1] = [:]
    private var recoveryCalls = 0
    private var finishedDisposition: ScratchPublicationDispositionV1?
    private var finishedDigest: String?

    func acquire(_ request: CapabilityScratchLeaseRequestV1) async throws -> CapabilityScratchLeaseV1 {
        requests[request.leaseID] = request
        return CapabilityScratchLeaseV1(
            leaseID: request.leaseID,
            purpose: request.purpose,
            relativeDirectory: "c32-\(request.leaseID.uuidString.lowercased())"
        )
    }

    func write(
        _ data: Data,
        named: String,
        lease: CapabilityScratchLeaseV1
    ) async throws -> URL {
        URL(fileURLWithPath: "/synthetic/\(lease.relativeDirectory)/\(named)")
    }

    func finish(
        lease: CapabilityScratchLeaseV1,
        disposition: ScratchPublicationDispositionV1,
        immutableContentReceiptDigest: String?
    ) async throws -> ScratchPublicationLinkageReceiptV1 {
        let request = try XCTUnwrap(requests.removeValue(forKey: lease.leaseID))
        finishedDisposition = disposition
        finishedDigest = immutableContentReceiptDigest
        return try ScratchPublicationLinkageReceiptV1(
            operationID: request.operationID,
            leaseID: lease.leaseID,
            purpose: lease.purpose,
            disposition: disposition,
            immutableContentReceiptDigest: immutableContentReceiptDigest,
            scratchDeleted: true
        )
    }

    func recoverAfterInterruption() async throws -> ScratchDataLeaseRecoverySummaryV1 {
        recoveryCalls += 1
        return try ScratchDataLeaseRecoverySummaryV1(
            recoveredExpiredLeaseCount: requests.count,
            removedByteCount: 0
        )
    }

    func recoveryCallCount() -> Int { recoveryCalls }
    func lastFinishedDisposition() -> String? { finishedDisposition?.rawValue }
    func lastFinishedDigest() -> String? { finishedDigest }
}

@MainActor
private final class C32WriterSpy: AssistanceCanonicalWorkspaceWritingV1 {
    private(set) var committedRequests: [AssistanceAcceptanceRequestV1] = []
    private(set) var receipts: [MutationIDV1: AssistanceAcceptanceReceiptV1] = [:]
    var interruptAfterEffect = false

    func commitAssistanceAcceptance(
        _ request: AssistanceAcceptanceRequestV1
    ) throws -> AssistanceAcceptanceReceiptV1 {
        if let existing = receipts[request.mutationID] { return existing }
        let receipt = try makeReceipt(request)
        committedRequests.append(request)
        receipts[request.mutationID] = receipt
        if interruptAfterEffect {
            interruptAfterEffect = false
            throw C32WriterInterruption.afterCanonicalEffect
        }
        return receipt
    }

    func acceptedAssistanceReceipt(
        mutationID: MutationIDV1
    ) throws -> AssistanceAcceptanceReceiptV1? {
        receipts[mutationID]
    }

    private func makeReceipt(
        _ request: AssistanceAcceptanceRequestV1
    ) throws -> AssistanceAcceptanceReceiptV1 {
        let workspaceID = request.proposal.target.workspaceID
        let replicaID = ReplicaID(rawValue: C32AssistanceTestSupport.id(52))
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: workspaceID,
            replicaID: replicaID
        )
        let envelope = try MutationEnvelopeV1(
            request: request.canonicalWorkspaceMutationRequest(),
            identity: identity
        )
        let postImages: [MutationPostImageV1]
        switch request.targetMutation {
        case .surveySession(let mutation): postImages = try mutation.mutationPostImages
        }
        let resultingRevision = try MutationPortableExpectedRevisionV1(
            WorkspaceExpectedRevisionV1(
                workspaceID: workspaceID,
                generationID: request.expectedRevision.generationID,
                writerInstanceID: request.expectedRevision.writerInstanceID,
                workspaceRevision: request.expectedRevision.workspaceRevision + 1,
                entityRevisions: try postImages.map {
                    WorkspaceEntityRevisionV1(identity: try $0.identity, revision: $0.revision)
                }
            )
        )
        let canonical = try MutationReceiptV1(
            identity: MutationReceiptIdentityV1(
                workspaceID: workspaceID,
                replicaID: replicaID,
                localSequence: 1
            ),
            envelope: envelope,
            resultingRevision: resultingRevision,
            postImages: postImages,
            committedAt: request.acceptedAt.addingTimeInterval(1)
        )
        return try AssistanceAcceptanceReceiptV1(
            request: request,
            canonicalMutationReceipt: canonical
        )
    }
}

private struct C32PersistentClock: ApplicationClock {
    let value: Date
    func now() -> Date { value }
}

private struct C32PersistentIDSource: ApplicationIDSource {
    let value: UUID
    func makeID() -> UUID { value }
}

private struct C32PersistentFileAuthority: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(
        mutationID: MutationIDV1,
        component: String
    ) throws -> String {
        "c32/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

@MainActor
private final class C32PersistentAcceptanceHarness {
    let fixture: C32AssistanceTestSupport.AcceptanceFixture
    let container: ModelContainer
    let context: ModelContext
    let identity: WorkspaceReplicaIdentityV1
    let store: MutationJournalStoreV1
    let writer: WorkspaceWriterV1

    init(
        slot: Int,
        failureBoundary: MutationJournalFaultBoundaryV1? = nil
    ) throws {
        let fixture = try C32AssistanceTestSupport.acceptanceFixture(
            slot: slot,
            workspaceRevision: 0
        )
        let schema = Schema(
            PersistentSchemaV32.models,
            version: PersistentSchemaV32.versionIdentifier
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "C32PersistentAcceptance-\(slot)",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )]
        )
        let context = container.mainContext
        context.autosaveEnabled = false
        let session: SurveySessionV1
        switch fixture.targetMutation {
        case .surveySession(let mutation):
            guard case let .captureFact(_, capturedSession, _, _) = mutation.payload else {
                throw AssistanceContractFailureV1.invalidValue
            }
            session = capturedSession
        }
        try C26SurveySessionTestSupport.seedPersistence(
            context: context,
            session: session,
            packageRelease: session.authority.packageRelease,
            packageSlot: 9_000 + slot
        )
        context.insert(EntityMutationRevisionRow(
            identity: fixture.proposal.target.entity,
            revision: fixture.proposal.target.revision
        ))
        try context.save()
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: fixture.proposal.target.workspaceID,
            replicaID: ReplicaID(rawValue: C32AssistanceTestSupport.id(9_500 + slot))
        )
        let store = try MutationJournalStoreV1(
            modelContext: context,
            identity: identity,
            generationID: fixture.expectedRevision.generationID,
            failureInjection: failureBoundary.map {
                MutationJournalFailureInjectionV1(failOnceAt: $0)
            }
        )
        let writer = try WorkspaceWriterV1(
            identity: identity,
            generationID: fixture.expectedRevision.generationID,
            initialRevision: store.currentRevision(
                writerInstanceID: fixture.expectedRevision.writerInstanceID
            ),
            clock: C32PersistentClock(value: fixture.acceptedAt),
            idSource: C32PersistentIDSource(value: fixture.expectedRevision.writerInstanceID),
            fileAuthority: C32PersistentFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context),
            journalStore: store
        )
        self.fixture = fixture
        self.container = container
        self.context = context
        self.identity = identity
        self.store = store
        self.writer = writer
    }

    func request() throws -> AssistanceAcceptanceRequestV1 {
        try AssistanceAcceptanceRequestV1(
            proposal: fixture.proposal,
            targetMutation: fixture.targetMutation,
            expectedRevision: fixture.expectedRevision,
            mutationID: fixture.mutationID,
            acceptedBy: fixture.reviewer,
            acceptedAt: fixture.acceptedAt
        )
    }

    func relaunched() throws -> (
        context: ModelContext,
        store: MutationJournalStoreV1,
        writer: WorkspaceWriterV1
    ) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let store = try MutationJournalStoreV1(
            modelContext: context,
            identity: identity,
            generationID: fixture.expectedRevision.generationID,
            allowStateBootstrap: false
        )
        try MutationReceiptRecoveryServiceV1(store: store).recoverBeforeWriterActivation()
        let writer = try WorkspaceWriterV1(
            identity: identity,
            generationID: fixture.expectedRevision.generationID,
            initialRevision: store.currentRevision(
                writerInstanceID: fixture.expectedRevision.writerInstanceID
            ),
            clock: C32PersistentClock(value: fixture.acceptedAt),
            idSource: C32PersistentIDSource(value: fixture.expectedRevision.writerInstanceID),
            fileAuthority: C32PersistentFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context),
            journalStore: store
        )
        return (context, store, writer)
    }
}

@MainActor
private final class C33TemporalEvidenceAnchorV948AssistanceProposal: XCTestCase {
    func testC33V948AssistanceProposalCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "assistance.temporal-manual-fallback",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "assistance.temporal-manual-fallback",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

@MainActor
final class V9_48AssistanceProposalTests: XCTestCase {
    private func corpus() throws -> C32AssistanceCorpusV1 {
        let url: URL
#if SWIFT_PACKAGE
        url = try XCTUnwrap(Bundle.module.url(
            forResource: "V22P03C32AssistanceProposalCorpusV1",
            withExtension: "json",
            subdirectory: "Fixtures/V22/Assistance"
        ))
#else
        let bundle = Bundle(for: Self.self)
        url = try XCTUnwrap(
            bundle.url(
                forResource: "V22P03C32AssistanceProposalCorpusV1",
                withExtension: "json",
                subdirectory: "Fixtures/V22/Assistance"
            ) ?? bundle.url(
                forResource: "V22P03C32AssistanceProposalCorpusV1",
                withExtension: "json"
            )
        )
#endif
        return try JSONDecoder().decode(C32AssistanceCorpusV1.self, from: Data(contentsOf: url))
    }

    func testV23P03C32G01ProposalReviewAcceptanceUsesOneCanonicalMutation() async throws {
        let writer = C32WriterSpy()
        let scratch = C32ScratchSpy()
        let fixture = try C32AssistanceTestSupport.acceptanceFixture(slot: 101)
        let accepted = fixture.proposal
        let acceptedContext = try C32AssistanceTestSupport.context(
            proposal: accepted,
            evaluatedAt: fixture.acceptedAt
        )
        let trustedState = C32TrustedStateResolver()
        trustedState.trust(accepted, context: acceptedContext)
        let coordinator = AssistanceCoordinatorV1(
            lifecycle: AssistanceLifecycleAdapterV1(
                writer: writer,
                scratch: scratch,
                currentState: trustedState
            )
        )
        try await coordinator.present(accepted, context: acceptedContext)
        XCTAssertEqual(writer.committedRequests.count, 0, "presentation must never mutate canonical state")
        guard case .ready(let reviewed) = try await coordinator.review(
            proposalID: accepted.proposalID,
            context: acceptedContext
        ) else { return XCTFail("valid proposal must remain reviewable") }
        XCTAssertEqual(reviewed, accepted)
        let receipt = try await coordinator.accept(
            proposalID: accepted.proposalID,
            targetMutation: fixture.targetMutation,
            expectedRevision: fixture.expectedRevision,
            mutationID: fixture.mutationID,
            acceptedBy: fixture.reviewer,
            acceptedAt: fixture.acceptedAt,
            context: acceptedContext
        )
        XCTAssertEqual(receipt.acceptedValue, accepted.value)
        XCTAssertEqual(receipt.target.revision, 1)
        XCTAssertEqual(receipt.canonicalEffectIdentities, try fixture.targetMutation.affectedIdentities.sorted { $0.stableKey < $1.stableKey })
        XCTAssertEqual(receipt.targetMutationSHA256, try fixture.targetMutation.mutationSHA256)
        XCTAssertEqual(writer.committedRequests.count, 1)
        let acceptedProposalAfterCommit = await coordinator.proposal(proposalID: accepted.proposalID)
        XCTAssertNil(acceptedProposalAfterCommit)

        let rejected = try C32AssistanceTestSupport.proposal(slot: 103)
        let rejectedContext = try C32AssistanceTestSupport.context(proposal: rejected)
        trustedState.trust(rejected, context: rejectedContext)
        try await coordinator.present(rejected, context: rejectedContext)
        let rejection = try await coordinator.reject(proposalID: rejected.proposalID)
        XCTAssertEqual(rejection.kind, .rejected)
        XCTAssertFalse(rejection.durableRejectedCorpusCreated)
        XCTAssertTrue(rejection.scratchDeleted)
        XCTAssertTrue(rejection.manualTextPreserved)

        let cancelled = try C32AssistanceTestSupport.proposal(slot: 104)
        let cancelledContext = try C32AssistanceTestSupport.context(proposal: cancelled)
        trustedState.trust(cancelled, context: cancelledContext)
        try await coordinator.present(cancelled, context: cancelledContext)
        let cancellation = try await coordinator.cancel(proposalID: cancelled.proposalID)
        XCTAssertEqual(cancellation.kind, .cancelled)
        XCTAssertFalse(cancellation.durableRejectedCorpusCreated)

        let expired = try C32AssistanceTestSupport.proposal(slot: 105)
        let initialExpiryContext = try C32AssistanceTestSupport.context(proposal: expired)
        trustedState.trust(expired, context: initialExpiryContext)
        try await coordinator.present(expired, context: initialExpiryContext)
        trustedState.trust(
            expired,
            context: try C32AssistanceTestSupport.context(proposal: expired, source: .some(nil))
        )
        let expiry = try await coordinator.expire(proposalID: expired.proposalID, reason: .sourceDeleted)
        XCTAssertEqual(expiry.kind, .expired)
        XCTAssertEqual(expiry.expiryReason, .sourceDeleted)
        XCTAssertEqual(writer.committedRequests.count, 1)
        XCTAssertEqual(Set(scratch.discarded.map(\.0)), Set([accepted, rejected, cancelled, expired].map(\.proposalID)))
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: scratch.finished.map { ($0.0, $0.1.rawValue) }),
            [
                accepted.proposalID: ScratchPublicationDispositionV1.acceptedIntoImmutableContent.rawValue,
                rejected.proposalID: ScratchPublicationDispositionV1.rejected.rawValue,
                cancelled.proposalID: ScratchPublicationDispositionV1.cancelled.rawValue,
                expired.proposalID: ScratchPublicationDispositionV1.expired.rawValue
            ]
        )
        XCTAssertEqual(
            scratch.finished.first { $0.0 == accepted.proposalID }?.2,
            receipt.receiptSHA256,
            "accepted scratch is linked only to its immutable canonical receipt"
        )
        XCTAssertTrue(
            scratch.finished.filter { $0.0 != accepted.proposalID }.allSatisfy { $0.2 == nil },
            "reject, cancel, and expire delete scratch without publishing immutable content"
        )

        let snapshotTime = accepted.createdAt.addingTimeInterval(10)
        let initialAuthority = try C32AssistanceTestSupport.authoritativeState(
            proposal: accepted,
            evaluatedAt: snapshotTime
        )
        let authorityReader = C32AuthoritativeStateReader(state: initialAuthority)
        let snapshotAuthority = AssistanceTrustedSnapshotAuthorityV1(reader: authorityReader)
        let snapshotCoordinator = AssistanceCoordinatorV1(
            lifecycle: AssistanceLifecycleAdapterV1(
                writer: C32WriterSpy(),
                scratch: C32ScratchSpy(),
                currentState: snapshotAuthority
            )
        )
        let obtainedSnapshot = try await snapshotCoordinator.obtainReviewSnapshot(for: accepted)
        XCTAssertEqual(obtainedSnapshot.evaluatedAt, snapshotTime)
        XCTAssertEqual(authorityReader.requests.count, 1)

        authorityReader.state = try C32AssistanceTestSupport.authoritativeState(
            proposal: accepted,
            evaluatedAt: snapshotTime.addingTimeInterval(20)
        )
        let unchangedSnapshot = try await snapshotAuthority.currentEvaluationContext(
            proposalID: accepted.proposalID,
            capability: accepted.capability,
            target: accepted.target,
            source: accepted.source
        )
        XCTAssertEqual(
            unchangedSnapshot,
            obtainedSnapshot,
            "a later trusted clock read must not change an otherwise identical review snapshot"
        )
        authorityReader.state = try C32AssistanceTestSupport.authoritativeState(
            proposal: accepted,
            evaluatedAt: snapshotTime.addingTimeInterval(-1)
        )
        do {
            _ = try await snapshotAuthority.currentEvaluationContext(
                proposalID: accepted.proposalID,
                capability: accepted.capability,
                target: accepted.target,
                source: accepted.source
            )
            XCTFail("trusted clock rollback must fail closed")
        } catch {
            XCTAssertEqual(error as? AssistanceContractFailureV1, .staleTarget)
        }

        let targetChangedAt = snapshotTime.addingTimeInterval(30)
        authorityReader.state = try C32AssistanceTestSupport.authoritativeState(
            proposal: accepted,
            targetRevision: accepted.target.revision + 1,
            evaluatedAt: targetChangedAt
        )
        let targetChanged = try await snapshotAuthority.currentEvaluationContext(
            proposalID: accepted.proposalID,
            capability: accepted.capability,
            target: accepted.target,
            source: accepted.source
        )
        XCTAssertEqual(targetChanged.targetRevision, accepted.target.revision + 1)
        XCTAssertEqual(targetChanged.evaluatedAt, targetChangedAt)

        let workspaceChangedAt = snapshotTime.addingTimeInterval(40)
        authorityReader.state = try C32AssistanceTestSupport.authoritativeState(
            proposal: accepted,
            workspaceRevision: initialAuthority.workspaceRevision.revision + 1,
            evaluatedAt: workspaceChangedAt
        )
        let workspaceChanged = try await snapshotAuthority.currentEvaluationContext(
            proposalID: accepted.proposalID,
            capability: accepted.capability,
            target: accepted.target,
            source: accepted.source
        )
        XCTAssertEqual(workspaceChanged.evaluatedAt, workspaceChangedAt)

        let policyChangedAt = snapshotTime.addingTimeInterval(50)
        let disabledPolicy = try C32AssistanceTestSupport.policy(
            capability: accepted.capability,
            enabled: false
        )
        authorityReader.state = try C32AssistanceTestSupport.authoritativeState(
            proposal: accepted,
            policy: disabledPolicy,
            evaluatedAt: policyChangedAt
        )
        let policyChanged = try await snapshotAuthority.currentEvaluationContext(
            proposalID: accepted.proposalID,
            capability: accepted.capability,
            target: accepted.target,
            source: accepted.source
        )
        XCTAssertEqual(policyChanged.policy, disabledPolicy)
        XCTAssertEqual(policyChanged.evaluatedAt, policyChangedAt)

        let releaseChangedAt = snapshotTime.addingTimeInterval(60)
        let changedPackage = String(repeating: "d", count: 64)
        let changedDefinition = String(repeating: "e", count: 64)
        authorityReader.state = try C32AssistanceTestSupport.authoritativeState(
            proposal: accepted,
            packageDigest: .some(changedPackage),
            definitionDigest: .some(changedDefinition),
            evaluatedAt: releaseChangedAt
        )
        let releaseChanged = try await snapshotAuthority.currentEvaluationContext(
            proposalID: accepted.proposalID,
            capability: accepted.capability,
            target: accepted.target,
            source: accepted.source
        )
        XCTAssertEqual(releaseChanged.packageReleaseSHA256, changedPackage)
        XCTAssertEqual(releaseChanged.definitionReleaseSHA256, changedDefinition)
        XCTAssertEqual(releaseChanged.evaluatedAt, releaseChangedAt)

        let sourceChangedAt = snapshotTime.addingTimeInterval(70)
        let changedSource = try C32AssistanceTestSupport.source(revision: accepted.source.revision + 1)
        authorityReader.state = try C32AssistanceTestSupport.authoritativeState(
            proposal: accepted,
            source: .some(changedSource),
            evaluatedAt: sourceChangedAt
        )
        let sourceChanged = try await snapshotAuthority.currentEvaluationContext(
            proposalID: accepted.proposalID,
            capability: accepted.capability,
            target: accepted.target,
            source: accepted.source
        )
        XCTAssertEqual(sourceChanged.currentSource, changedSource)
        XCTAssertEqual(sourceChanged.evaluatedAt, sourceChangedAt)

        authorityReader.state = try C32AssistanceTestSupport.authoritativeState(
            proposal: accepted,
            evaluatedAt: accepted.expiresAt
        )
        let timedOut = try await snapshotAuthority.currentEvaluationContext(
            proposalID: accepted.proposalID,
            capability: accepted.capability,
            target: accepted.target,
            source: accepted.source
        )
        XCTAssertEqual(
            timedOut.evaluatedAt,
            accepted.expiresAt,
            "timeout must refresh the trusted time so expiry cannot reuse a cached pre-timeout snapshot"
        )
    }

    func testV23P03C32A01RejectCancelExpireDeleteScratchAndPreserveManualText() throws {
        let values = try C32AssistanceTestSupport.typedValues()
        XCTAssertEqual(Set(values.map(\.kind)).count, values.count)
        for (index, value) in values.enumerated() {
            let proposal = try C32AssistanceTestSupport.proposal(slot: 200 + index, value: value)
            XCTAssertEqual(
                try AssistanceCanonicalCodecV1.decode(
                    AssistanceProposalV1.self,
                    from: AssistanceCanonicalCodecV1.encode(proposal)
                ),
                proposal
            )
            XCTAssertEqual(proposal.value, value, "manual entry and accepted proposal share the exact typed value")
        }

        let ocr = try C32AssistanceTestSupport.proposal(slot: 220)
        let dictationCapability = try C32AssistanceTestSupport.capability(
            id: "DICTATION_FIELD_PROPOSAL",
            version: "DICTATION_FIELD_PROPOSAL_V1"
        )
        let dictation = try C32AssistanceTestSupport.proposal(
            slot: 221,
            capability: dictationCapability
        )
        let revokedOCR = try C32AssistanceTestSupport.policy(
            capability: ocr.capability,
            enabled: false
        )
        XCTAssertEqual(
            try ocr.expiryReason(in: C32AssistanceTestSupport.context(proposal: ocr, policy: revokedOCR)),
            .capabilityRevoked
        )
        XCTAssertNil(
            try dictation.expiryReason(in: C32AssistanceTestSupport.context(proposal: dictation)),
            "rolling back OCR must not roll back dictation"
        )
        XCTAssertEqual(try C32AssistanceTestSupport.policy().manualFallback, .typeManually)
        XCTAssertThrowsError(try C32AssistanceTestSupport.policy(fallback: .noFallback))

        let acceptance = try C32AssistanceTestSupport.acceptanceFixture(slot: 222)
        let request = try AssistanceAcceptanceRequestV1(
            proposal: acceptance.proposal,
            targetMutation: acceptance.targetMutation,
            expectedRevision: acceptance.expectedRevision,
            mutationID: acceptance.mutationID,
            acceptedBy: acceptance.reviewer,
            acceptedAt: acceptance.acceptedAt
        )
        XCTAssertNoThrow(
            try request.validateManualPathEquivalence(to: acceptance.targetMutation),
            "acceptance must reuse the exact canonical mutation available to manual entry"
        )
        let differentManualMutation = try C32AssistanceTestSupport.acceptanceFixture(slot: 223).targetMutation
        XCTAssertThrowsError(try request.validateManualPathEquivalence(to: differentManualMutation)) { error in
            XCTAssertEqual(error as? AssistanceContractFailureV1, .invalidValue)
        }
    }

    func testV23P03C32H01StaleTargetsInvalidValuesAndForbiddenCapabilityPathsFailClosed() async throws {
        let proposal = try C32AssistanceTestSupport.proposal(slot: 301)
        let foreignWorkspace = C32AssistanceTestSupport.workspace(2)
        let disabled = try C32AssistanceTestSupport.policy(capability: proposal.capability, enabled: false)
        let wrongVersion = try C32AssistanceTestSupport.capability(version: "OCR_FIELD_PROPOSAL_V2")
        let wrongLocale = try C32AssistanceTestSupport.capability(locale: "fr-CA")
        let wrongSource = try C32AssistanceTestSupport.source(revision: 2)

        let cases: [(AssistanceProposalEvaluationContextV1, AssistanceProposalExpiryReasonV1)] = [
            (try C32AssistanceTestSupport.context(proposal: proposal, targetRevision: 8), .targetRevisionChanged),
            (try C32AssistanceTestSupport.context(proposal: proposal, policy: disabled), .capabilityRevoked),
            (try C32AssistanceTestSupport.context(
                proposal: proposal,
                policy: C32AssistanceTestSupport.policy(capability: wrongVersion)
            ), .capabilityVersionChanged), // Wrong local model/version cannot reuse an older proposal.
            (try C32AssistanceTestSupport.context(
                proposal: proposal,
                policy: C32AssistanceTestSupport.policy(capability: wrongLocale)
            ), .capabilityLocaleChanged),
            (try C32AssistanceTestSupport.context(proposal: proposal, packageDigest: String(repeating: "f", count: 64)), .packageChanged),
            (try C32AssistanceTestSupport.context(proposal: proposal, definitionDigest: String(repeating: "0", count: 64)), .definitionChanged),
            (try C32AssistanceTestSupport.context(
                proposal: proposal,
                evaluatedAt: proposal.expiresAt
            ), .timedOut),
            (try C32AssistanceTestSupport.context(proposal: proposal, workspaceID: foreignWorkspace), .workspaceChanged),
            (try C32AssistanceTestSupport.context(proposal: proposal, source: .some(nil)), .sourceDeleted),
            (try C32AssistanceTestSupport.context(proposal: proposal, source: .some(wrongSource)), .sourceChanged)
        ]
        for (context, expected) in cases {
            XCTAssertEqual(try proposal.expiryReason(in: context), expected)
        }
        XCTAssertEqual(
            try proposal.expiryReason(in: C32AssistanceTestSupport.context(
                proposal: proposal,
                targetRevision: proposal.target.revision + 1
            )),
            .targetRevisionChanged,
            "a target revision change expires rather than overwrites a user edit"
        )
        XCTAssertEqual(
            try proposal.expiryReason(in: C32AssistanceTestSupport.context(
                proposal: proposal,
                policy: disabled
            )),
            .capabilityRevoked,
            "capability revocation, including permission revocation, keeps the manual path"
        )
        XCTAssertEqual(
            try proposal.expiryReason(in: C32AssistanceTestSupport.context(
                proposal: proposal,
                source: .some(nil)
            )),
            .sourceDeleted,
            "source deletion removes the proposal and its scratch authority"
        )
        XCTAssertEqual(Set(cases.map(\.1)), Set(AssistanceProposalExpiryReasonV1.allCases).subtracting([.capabilityPolicyChanged]))

        let noPackageBinding = try C32AssistanceTestSupport.proposal(
            slot: 305,
            packageDigest: nil
        )
        XCTAssertEqual(
            try noPackageBinding.expiryReason(in: C32AssistanceTestSupport.context(
                proposal: noPackageBinding,
                packageDigest: .some(C32AssistanceTestSupport.packageDigest)
            )),
            .packageChanged
        )
        XCTAssertEqual(
            try proposal.expiryReason(in: C32AssistanceTestSupport.context(
                proposal: proposal,
                packageDigest: .some(nil)
            )),
            .packageChanged
        )
        let noDefinitionBinding = try C32AssistanceTestSupport.proposal(
            slot: 306,
            definitionDigest: nil
        )
        XCTAssertEqual(
            try noDefinitionBinding.expiryReason(in: C32AssistanceTestSupport.context(
                proposal: noDefinitionBinding,
                definitionDigest: .some(C32AssistanceTestSupport.definitionDigest)
            )),
            .definitionChanged
        )
        XCTAssertEqual(
            try proposal.expiryReason(in: C32AssistanceTestSupport.context(
                proposal: proposal,
                definitionDigest: .some(nil)
            )),
            .definitionChanged
        )

        let absentConfidence = try C32AssistanceTestSupport.proposal(slot: 302, confidence: nil)
        XCTAssertEqual(
            try absentConfidence.expiryReason(in: C32AssistanceTestSupport.context(
                proposal: absentConfidence,
                policy: C32AssistanceTestSupport.policy(
                    capability: absentConfidence.capability,
                    confidence: .required
                )
            )),
            .capabilityPolicyChanged
        )
        XCTAssertThrowsError(try AssistanceConfidenceV1(basisPoints: -1))
        XCTAssertThrowsError(try AssistanceConfidenceV1(basisPoints: 10_001))
        XCTAssertThrowsError(try C32AssistanceTestSupport.proposal(value: .noValue))

        let acceptance = try C32AssistanceTestSupport.acceptanceFixture(slot: 303)
        let concurrency = try acceptance.targetMutation.concurrencyIdentities
        let staleExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: acceptance.proposal.target.workspaceID,
            generationID: acceptance.expectedRevision.generationID,
            writerInstanceID: acceptance.expectedRevision.writerInstanceID,
            workspaceRevision: 12,
            entityRevisions: try concurrency.map {
                WorkspaceEntityRevisionV1(identity: $0, revision: 99)
            }
        )
        XCTAssertThrowsError(try AssistanceAcceptanceRequestV1(
            proposal: acceptance.proposal,
            targetMutation: acceptance.targetMutation,
            expectedRevision: staleExpected,
            mutationID: acceptance.mutationID,
            acceptedBy: acceptance.reviewer,
            acceptedAt: acceptance.acceptedAt
        )) { error in
            XCTAssertEqual(error as? AssistanceContractFailureV1, .staleTarget)
        }
        for proposalWithoutBinding in [
            try C32AssistanceTestSupport.replacingReleaseBindings(
                in: acceptance.proposal,
                packageDigest: nil,
                definitionDigest: acceptance.proposal.definitionReleaseSHA256
            ),
            try C32AssistanceTestSupport.replacingReleaseBindings(
                in: acceptance.proposal,
                packageDigest: acceptance.proposal.packageReleaseSHA256,
                definitionDigest: nil
            )
        ] {
            XCTAssertThrowsError(try AssistanceAcceptanceRequestV1(
                proposal: proposalWithoutBinding,
                targetMutation: acceptance.targetMutation,
                expectedRevision: acceptance.expectedRevision,
                mutationID: acceptance.mutationID,
                acceptedBy: acceptance.reviewer,
                acceptedAt: acceptance.acceptedAt
            )) { error in
                XCTAssertEqual(error as? AssistanceContractFailureV1, .invalidValue)
            }
        }

        let trustedWriter = C32WriterSpy()
        let trustedScratch = C32ScratchSpy()
        let trustedResolver = C32TrustedStateResolver()
        let trustedContext = try C32AssistanceTestSupport.context(
            proposal: acceptance.proposal,
            evaluatedAt: acceptance.acceptedAt
        )
        trustedResolver.trust(acceptance.proposal, context: trustedContext)
        let trustedCoordinator = AssistanceCoordinatorV1(
            lifecycle: AssistanceLifecycleAdapterV1(
                writer: trustedWriter,
                scratch: trustedScratch,
                currentState: trustedResolver
            )
        )
        let callerForgedContext = try C32AssistanceTestSupport.context(
            proposal: acceptance.proposal,
            evaluatedAt: acceptance.acceptedAt.addingTimeInterval(-1)
        )
        do {
            try await trustedCoordinator.present(
                acceptance.proposal,
                context: callerForgedContext
            )
            XCTFail("caller-supplied clock state cannot replace trusted current state")
        } catch {
            XCTAssertEqual(error as? AssistanceContractFailureV1, .staleTarget)
        }
        try await trustedCoordinator.present(acceptance.proposal, context: trustedContext)
        do {
            _ = try await trustedCoordinator.review(
                proposalID: acceptance.proposal.proposalID,
                context: callerForgedContext
            )
            XCTFail("review requires exact equality with trusted current state")
        } catch {
            XCTAssertEqual(error as? AssistanceContractFailureV1, .staleTarget)
        }
        do {
            _ = try await trustedCoordinator.accept(
                proposalID: acceptance.proposal.proposalID,
                targetMutation: acceptance.targetMutation,
                expectedRevision: acceptance.expectedRevision,
                mutationID: acceptance.mutationID,
                acceptedBy: acceptance.reviewer,
                acceptedAt: acceptance.acceptedAt.addingTimeInterval(-1),
                context: trustedContext
            )
            XCTFail("acceptance time must equal the trusted evaluation instant")
        } catch {
            XCTAssertEqual(error as? AssistanceContractFailureV1, .staleTarget)
        }
        XCTAssertTrue(trustedWriter.committedRequests.isEmpty)

        let leases = C32CapabilityScratchLeaseSpy()
        let scratchBridge = AssistanceCapabilityScratchLifecycleAdapterV1(leases: leases)
        let proposalID = C32AssistanceTestSupport.id(310)
        let leaseID = C32AssistanceTestSupport.id(311)
        let scratchRequest = try CapabilityScratchLeaseRequestV1(
            leaseID: leaseID,
            operationID: proposalID,
            purpose: .capture,
            requestedByteCount: 1_024,
            createdAt: C32AssistanceTestSupport.fixedDate,
            expiresAt: C32AssistanceTestSupport.fixedDate.addingTimeInterval(60)
        )
        let scratchSource = try C32AssistanceTestSupport.source(
            sourceID: leaseID.uuidString.lowercased()
        )
        let immutableSource = try C32AssistanceTestSupport.source(
            kind: .deterministicRule,
            sourceID: "immutable-source"
        )
        XCTAssertThrowsError(try AssistanceCapabilityScratchV1(
            proposalID: proposalID,
            source: immutableSource
        ))
        XCTAssertThrowsError(try scratchBridge.currentSource(
            proposalID: proposalID,
            expected: immutableSource
        )) { error in
            XCTAssertEqual(error as? AssistanceContractFailureV1, .invalidValue)
        }
        let wrongOperationRequest = try CapabilityScratchLeaseRequestV1(
            leaseID: leaseID,
            operationID: C32AssistanceTestSupport.id(312),
            purpose: .capture,
            requestedByteCount: 1_024,
            createdAt: C32AssistanceTestSupport.fixedDate,
            expiresAt: C32AssistanceTestSupport.fixedDate.addingTimeInterval(60)
        )
        do {
            _ = try await scratchBridge.acquireAndBind(
                proposalID: proposalID,
                source: scratchSource,
                request: wrongOperationRequest
            )
            XCTFail("scratch request operation must equal the proposal identity")
        } catch {
            XCTAssertEqual(error as? AssistanceContractFailureV1, .invalidValue)
        }
        let wrongSource = try C32AssistanceTestSupport.source(sourceID: C32AssistanceTestSupport.id(313).uuidString.lowercased())
        do {
            _ = try await scratchBridge.acquireAndBind(
                proposalID: proposalID,
                source: wrongSource,
                request: scratchRequest
            )
            XCTFail("scratch source identity must equal the requested lease identity")
        } catch {
            XCTAssertEqual(error as? AssistanceContractFailureV1, .invalidValue)
        }
        let linkage = try AssistanceCapabilityScratchV1(proposalID: proposalID, source: scratchSource)
        XCTAssertThrowsError(try scratchBridge.bind(
            linkage,
            lease: CapabilityScratchLeaseV1(
                leaseID: C32AssistanceTestSupport.id(314),
                purpose: .capture,
                relativeDirectory: "wrong-lease"
            ),
            request: scratchRequest
        ))
        XCTAssertThrowsError(try scratchBridge.bind(
            linkage,
            lease: CapabilityScratchLeaseV1(
                leaseID: leaseID,
                purpose: .source,
                relativeDirectory: "wrong-purpose"
            ),
            request: scratchRequest
        ))
        do {
            try await scratchBridge.discardOrphanedAssistanceScratch(retainingProposalIDs: [proposalID])
            XCTFail("recovery cannot discard scratch retained by a live proposal")
        } catch {
            XCTAssertEqual(error as? AssistanceContractFailureV1, .scratchCleanupFailed)
        }
        _ = try await scratchBridge.acquireAndBind(
            proposalID: proposalID,
            source: scratchSource,
            request: scratchRequest
        )
        XCTAssertEqual(
            try scratchBridge.currentSource(proposalID: proposalID, expected: scratchSource),
            scratchSource
        )
        do {
            try await scratchBridge.discardOrphanedAssistanceScratch(retainingProposalIDs: [])
            XCTFail("recovery cannot run while an assistance scratch binding is live")
        } catch {
            XCTAssertEqual(error as? AssistanceContractFailureV1, .scratchCleanupFailed)
        }
        let recoveryCallsBeforeFinish = await leases.recoveryCallCount()
        XCTAssertEqual(recoveryCallsBeforeFinish, 0)
        let receiptDigest = String(repeating: "d", count: 64)
        try await scratchBridge.finishAssistanceScratch(
            proposalID: proposalID,
            source: scratchSource,
            disposition: .acceptedIntoImmutableContent,
            immutableContentReceiptDigest: receiptDigest
        )
        let finishedDisposition = await leases.lastFinishedDisposition()
        let finishedDigest = await leases.lastFinishedDigest()
        XCTAssertEqual(finishedDisposition, ScratchPublicationDispositionV1.acceptedIntoImmutableContent.rawValue)
        XCTAssertEqual(finishedDigest, receiptDigest)
        XCTAssertNil(try scratchBridge.currentSource(proposalID: proposalID, expected: scratchSource))
        try await scratchBridge.discardOrphanedAssistanceScratch(retainingProposalIDs: [])
        let recoveryCallsAfterFinish = await leases.recoveryCallCount()
        XCTAssertEqual(recoveryCallsAfterFinish, 1)
    }

    func testV23P03C32I01InterruptedAcceptanceRecoversIdempotentlyWithoutDirectWrites() async throws {
        let writer = C32WriterSpy()
        writer.interruptAfterEffect = true
        let scratch = C32ScratchSpy()
        let fixture = try C32AssistanceTestSupport.acceptanceFixture(slot: 401)
        let proposal = fixture.proposal
        let context = try C32AssistanceTestSupport.context(
            proposal: proposal,
            evaluatedAt: fixture.acceptedAt
        )
        let trustedState = C32TrustedStateResolver()
        trustedState.trust(proposal, context: context)
        let lifecycle = AssistanceLifecycleAdapterV1(
            writer: writer,
            scratch: scratch,
            currentState: trustedState
        )
        let coordinator = AssistanceCoordinatorV1(lifecycle: lifecycle)
        let mutationID = fixture.mutationID
        let expected = fixture.expectedRevision
        let reviewer = fixture.reviewer
        let acceptedAt = fixture.acceptedAt
        try await coordinator.present(proposal, context: context)

        do {
            _ = try await coordinator.accept(
                proposalID: proposal.proposalID,
                targetMutation: fixture.targetMutation,
                expectedRevision: expected,
                mutationID: mutationID,
                acceptedBy: reviewer,
                acceptedAt: acceptedAt,
                context: context
            )
            XCTFail("simulated effect-before-receipt interruption must escape")
        } catch C32WriterInterruption.afterCanonicalEffect {}
        XCTAssertEqual(writer.committedRequests.count, 1)
        let proposalAfterInterruptedReturn = await coordinator.proposal(proposalID: proposal.proposalID)
        XCTAssertNotNil(proposalAfterInterruptedReturn)

        let recovered = try await coordinator.accept(
            proposalID: proposal.proposalID,
            targetMutation: fixture.targetMutation,
            expectedRevision: expected,
            mutationID: mutationID,
            acceptedBy: reviewer,
            acceptedAt: acceptedAt,
            context: context
        )
        XCTAssertEqual(recovered, writer.receipts[mutationID])
        XCTAssertEqual(writer.committedRequests.count, 1)
        let proposalAfterRecovery = await coordinator.proposal(proposalID: proposal.proposalID)
        XCTAssertNil(proposalAfterRecovery)

        let relaunched = AssistanceCoordinatorV1(
            lifecycle: AssistanceLifecycleAdapterV1(
                writer: writer,
                scratch: scratch,
                currentState: trustedState
            )
        )
        let proposalAfterRelaunch = await relaunched.proposal(proposalID: proposal.proposalID)
        XCTAssertNil(proposalAfterRelaunch)
        try await relaunched.recoverAfterInterruption()
        XCTAssertEqual(scratch.orphanRetentionSets.last, Set<UUID>())
        XCTAssertTrue(AssistancePersistenceEnrollmentV1.proposalIsPersistent == false)

        let persistent = try C32PersistentAcceptanceHarness(
            slot: 450,
            failureBoundary: .afterSaveBeforeReturn
        )
        let persistentRequest = try persistent.request()
        XCTAssertThrowsError(
            try persistent.writer.commitAssistanceAcceptance(persistentRequest)
        ) { error in
            XCTAssertTrue(error is MutationJournalFailureV1)
        }
        XCTAssertEqual(
            try persistent.context.fetchCount(FetchDescriptor<FactCaptureRow>()),
            1,
            "the canonical survey fact and both receipts commit atomically before interruption"
        )
        XCTAssertEqual(
            try persistent.context.fetchCount(FetchDescriptor<MutationReceiptRow>()),
            1
        )
        XCTAssertEqual(
            try persistent.context.fetchCount(FetchDescriptor<AssistanceAcceptanceReceiptRow>()),
            1
        )
        let persistentRelaunch = try persistent.relaunched()
        let recoveredPersistentReceipt = try XCTUnwrap(
            persistentRelaunch.writer.acceptedAssistanceReceipt(
                mutationID: persistent.fixture.mutationID
            )
        )
        let idempotentPersistentReceipt = try persistentRelaunch.writer
            .commitAssistanceAcceptance(persistentRequest)
        XCTAssertEqual(idempotentPersistentReceipt, recoveredPersistentReceipt)
        XCTAssertEqual(idempotentPersistentReceipt.expectedRevision, persistent.fixture.expectedRevision)
        XCTAssertEqual(
            try persistentRelaunch.context.fetchCount(FetchDescriptor<FactCaptureRow>()),
            1
        )
        XCTAssertEqual(
            try persistentRelaunch.context.fetchCount(FetchDescriptor<MutationReceiptRow>()),
            1
        )
        XCTAssertEqual(
            try persistentRelaunch.context.fetchCount(FetchDescriptor<AssistanceAcceptanceReceiptRow>()),
            1
        )
    }

    func testV23P03C32R01RestoreReplayAndCapabilityRollbackRemainExact() async throws {
        let writer = C32WriterSpy()
        let scratch = C32ScratchSpy()
        let fixture = try C32AssistanceTestSupport.acceptanceFixture(slot: 501)
        let proposal = fixture.proposal
        let context = try C32AssistanceTestSupport.context(
            proposal: proposal,
            evaluatedAt: fixture.acceptedAt
        )
        let trustedState = C32TrustedStateResolver()
        trustedState.trust(proposal, context: context)
        let coordinator = AssistanceCoordinatorV1(
            lifecycle: AssistanceLifecycleAdapterV1(
                writer: writer,
                scratch: scratch,
                currentState: trustedState
            )
        )
        let mutationID = fixture.mutationID
        let expected = fixture.expectedRevision
        let reviewer = fixture.reviewer
        let acceptedAt = fixture.acceptedAt
        try await coordinator.present(proposal, context: context)
        let first = try await coordinator.accept(
            proposalID: proposal.proposalID,
            targetMutation: fixture.targetMutation,
            expectedRevision: expected,
            mutationID: mutationID,
            acceptedBy: reviewer,
            acceptedAt: acceptedAt,
            context: context
        )
        func assertInvalidRecoveredReceipt(
            _ operation: () async throws -> Void,
            file: StaticString = #filePath,
            line: UInt = #line
        ) async {
            do {
                try await operation()
                XCTFail("relaunch recovery must validate every canonical acceptance input", file: file, line: line)
            } catch {
                XCTAssertEqual(error as? AssistanceContractFailureV1, .invalidReceipt, file: file, line: line)
            }
        }
        let otherMutation = try C32AssistanceTestSupport.acceptanceFixture(slot: 502).targetMutation
        await assertInvalidRecoveredReceipt {
            _ = try await coordinator.accept(
                proposalID: proposal.proposalID,
                targetMutation: otherMutation,
                expectedRevision: expected,
                mutationID: mutationID,
                acceptedBy: reviewer,
                acceptedAt: acceptedAt,
                context: context
            )
        }
        let expectedTokenMismatches = [
            try WorkspaceExpectedRevisionV1(
                workspaceID: expected.workspaceID,
                generationID: C32AssistanceTestSupport.id(505),
                writerInstanceID: expected.writerInstanceID,
                workspaceRevision: expected.workspaceRevision,
                entityRevisions: expected.entityRevisions
            ),
            try WorkspaceExpectedRevisionV1(
                workspaceID: expected.workspaceID,
                generationID: expected.generationID,
                writerInstanceID: C32AssistanceTestSupport.id(506),
                workspaceRevision: expected.workspaceRevision,
                entityRevisions: expected.entityRevisions
            ),
            try WorkspaceExpectedRevisionV1(
                workspaceID: expected.workspaceID,
                generationID: expected.generationID,
                writerInstanceID: expected.writerInstanceID,
                workspaceRevision: expected.workspaceRevision + 1,
                entityRevisions: expected.entityRevisions
            )
        ]
        for mismatchedExpected in expectedTokenMismatches {
            await assertInvalidRecoveredReceipt {
                _ = try await coordinator.accept(
                    proposalID: proposal.proposalID,
                    targetMutation: fixture.targetMutation,
                    expectedRevision: mismatchedExpected,
                    mutationID: mutationID,
                    acceptedBy: reviewer,
                    acceptedAt: acceptedAt,
                    context: context
                )
            }
        }
        let staleRecoveredExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: expected.workspaceID,
            generationID: expected.generationID,
            writerInstanceID: expected.writerInstanceID,
            workspaceRevision: expected.workspaceRevision,
            entityRevisions: expected.entityRevisions.map {
                WorkspaceEntityRevisionV1(identity: $0.identity, revision: $0.revision + 1)
            }
        )
        await assertInvalidRecoveredReceipt {
            _ = try await coordinator.accept(
                proposalID: proposal.proposalID,
                targetMutation: fixture.targetMutation,
                expectedRevision: staleRecoveredExpected,
                mutationID: mutationID,
                acceptedBy: reviewer,
                acceptedAt: acceptedAt,
                context: context
            )
        }
        let otherReviewer = try C32AssistanceTestSupport.reviewer(workspaceID: proposal.target.workspaceID)
        await assertInvalidRecoveredReceipt {
            _ = try await coordinator.accept(
                proposalID: proposal.proposalID,
                targetMutation: fixture.targetMutation,
                expectedRevision: expected,
                mutationID: mutationID,
                acceptedBy: otherReviewer,
                acceptedAt: acceptedAt,
                context: context
            )
        }
        await assertInvalidRecoveredReceipt {
            _ = try await coordinator.accept(
                proposalID: proposal.proposalID,
                targetMutation: fixture.targetMutation,
                expectedRevision: expected,
                mutationID: mutationID,
                acceptedBy: reviewer,
                acceptedAt: acceptedAt.addingTimeInterval(1),
                context: context
            )
        }
        let foreignContext = try C32AssistanceTestSupport.context(
            proposal: proposal,
            workspaceID: C32AssistanceTestSupport.workspace(503)
        )
        await assertInvalidRecoveredReceipt {
            _ = try await coordinator.accept(
                proposalID: proposal.proposalID,
                targetMutation: fixture.targetMutation,
                expectedRevision: expected,
                mutationID: mutationID,
                acceptedBy: reviewer,
                acceptedAt: acceptedAt,
                context: foreignContext
            )
        }
        await assertInvalidRecoveredReceipt {
            _ = try await coordinator.accept(
                proposalID: C32AssistanceTestSupport.id(504),
                targetMutation: fixture.targetMutation,
                expectedRevision: expected,
                mutationID: mutationID,
                acceptedBy: reviewer,
                acceptedAt: acceptedAt,
                context: context
            )
        }
        let second = try await coordinator.accept(
            proposalID: proposal.proposalID,
            targetMutation: fixture.targetMutation,
            expectedRevision: expected,
            mutationID: mutationID,
            acceptedBy: reviewer,
            acceptedAt: acceptedAt,
            context: context
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(writer.committedRequests.count, 1)
        XCTAssertEqual(try AssistanceCanonicalCodecV1.decode(
            AssistanceAcceptanceReceiptV1.self,
            from: AssistanceCanonicalCodecV1.encode(first)
        ), first)

        let value = try corpus()
        XCTAssertEqual(value.schema, "V22P03C32AssistanceProposalCorpusV1")
        XCTAssertEqual(value.schemaVersion, 1)
        XCTAssertEqual(value.cardID, "V23-P03-C32")
        XCTAssertEqual(value.proposalPersistenceDisposition, "NONPERSISTENT")
        XCTAssertEqual(value.durableFamilies, ["AssistanceAcceptanceReceiptV1"])
        XCTAssertEqual(value.persistentSchemaVersion, AssistancePersistenceEnrollmentV1.persistentSchemaVersion)
        XCTAssertEqual(value.recordsSchemaVersion, AssistancePersistenceEnrollmentV1.recordsSchemaVersion)
        XCTAssertEqual(value.evidenceIDs, ["V23-P03-C32-G01", "V23-P03-C32-A01", "V23-P03-C32-H01", "V23-P03-C32-I01", "V23-P03-C32-R01"])
        XCTAssertEqual(Set(value.transitionMatrix.map(\.action)), ["ACCEPT", "REJECT", "CANCEL", "EXPIRE"])
        XCTAssertEqual(Set(value.expiryTriggers), ["TARGET_REVISION_CHANGED", "CAPABILITY_REVOKED", "PACKAGE_CHANGED", "DEFINITION_CHANGED", "TIMEOUT", "WORKSPACE_SWITCHED", "SOURCE_DELETED"])
        XCTAssertTrue(value.invariants.proposalNeverCanonical)
        XCTAssertTrue(value.invariants.proposalNeverPersistent)
        XCTAssertTrue(value.invariants.proposalNeverBackedUp)
        XCTAssertTrue(value.invariants.proposalNeverSearched)
        XCTAssertTrue(value.invariants.proposalNeverReported)
        XCTAssertTrue(value.invariants.noDirectMutation)
        XCTAssertTrue(value.invariants.explicitReviewRequired)
        XCTAssertTrue(value.invariants.expectedRevisionRequired)
        XCTAssertTrue(value.invariants.manualPathEquivalent)
        XCTAssertTrue(value.invariants.capabilitiesRollbackIndependently)
        XCTAssertFalse(value.invariants.rejectedProposalCorpusRetained)
        XCTAssertEqual(value.lifecycle.proposal, "NONPERSISTENT")
        XCTAssertEqual(value.lifecycle.backup, "ACCEPTANCE_RECEIPT_ONLY")
        XCTAssertEqual(value.lifecycle.search, "EXCLUDED")
        XCTAssertEqual(value.lifecycle.report, "EXCLUDED")
    }
}
private final class C46V948AssistanceCompatibilityTests: XCTestCase {
    func testC46AssistanceProposalCannotAutoCreateContact() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "assistance-proposal",
            kind: .email,
            handoff: .email,
            slot: 46048
        )
    }
}
