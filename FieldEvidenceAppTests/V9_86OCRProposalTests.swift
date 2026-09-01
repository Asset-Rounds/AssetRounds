import Foundation
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V9_86OCRProposalTests: XCTestCase {
    func testV23P04C23G01SupportedExplicitOCRReviewAcceptAndNoAutomaticWrite() async throws {
        let bundle = try C23OCRSupport.bundle()
        try bundle.evidence.validate()

        XCTAssertTrue(bundle.request.explicitUserAction)
        XCTAssertEqual(bundle.evidence.request.target, bundle.evidence.proposal.target)
        XCTAssertEqual(bundle.evidence.request.source, bundle.evidence.proposal.source)
        XCTAssertEqual(bundle.evidence.observation.crop, bundle.request.sourceCrop)
        XCTAssertEqual(bundle.evidence.configuredLanguageIdentifiers, ["en-US"])
        XCTAssertTrue(bundle.evidence.customWordsAreHintsOnly)
        XCTAssertTrue(bundle.evidence.processedOnDevice)
        XCTAssertFalse(bundle.evidence.networkAccessUsed)
        XCTAssertEqual(bundle.evidence.proposal.verificationState.rawValue, "UNVERIFIED")

        let accepted = try C23OCRSupport.review(.accepted, evidence: bundle.evidence)
        let edited = try C23OCRSupport.review(
            .edited,
            value: .text("Reviewed correction"),
            evidence: bundle.evidence
        )
        let rejected = try C23OCRSupport.review(.rejected, value: nil, evidence: bundle.evidence)
        XCTAssertEqual(accepted.reviewedValue, bundle.evidence.proposal.value)
        XCTAssertNotEqual(edited.reviewedValue, bundle.evidence.proposal.value)
        XCTAssertNil(rejected.reviewedValue)

        XCTAssertEqual(OCRProposalPersistenceBoundaryV1.addedDurableRowCount, 0)
        XCTAssertFalse(OCRProposalPersistenceBoundaryV1.activationEnabled)
        XCTAssertFalse(OCRProposalSearchRebuildBoundaryV1.mayIndex(bundle.evidence))
        XCTAssertFalse(OCRProposalReportProjectionBoundaryV1.mayProject(bundle.evidence))
        let receipt = try C23OCRSupport.acceptanceReceipt(bundle)
        XCTAssertTrue(try OCRProposalSearchRebuildBoundaryV1.acceptsCanonicalTargetFact(
            receipt: receipt,
            evidence: bundle.evidence
        ))
        XCTAssertTrue(try OCRProposalReportProjectionBoundaryV1.acceptsCanonicalTargetFact(
            receipt: receipt,
            evidence: bundle.evidence
        ))
    }

    func testV23P04C23A01UnsupportedLanguageDeviceAndCompleteManualFallback() async throws {
        let bundle = try C23OCRSupport.bundle()
        let access = C23AccessGate(state: .disabled)
        let calls = C23CallCounter()
        let scratch = C23ScratchLifecycle()
        let extractedEvidence = bundle.evidence
        let extractor = InjectedOnDeviceOCRProposalAdapterV1 { _ in
            await calls.increment()
            return [extractedEvidence]
        }
        let coordinator = try OCRProposalCoordinatorV1(
            policy: C23OCRSupport.policy(),
            access: access,
            extractor: extractor,
            scratch: scratch,
            assistance: AssistanceCoordinatorV1(lifecycle: C23AssistanceLifecycle())
        )

        let outcome = try await coordinator.extractText(bundle.request)
        let initialCallCount = await calls.value()
        let initialSurfaces = await access.requestedSurfaces()
        let initialScratchCount = scratch.prepareCount
        XCTAssertEqual(outcome, .manualFallback(.typeManually))
        XCTAssertEqual(initialCallCount, 0, "PREPARED_DISABLED must not call OCR")
        XCTAssertEqual(initialSurfaces, [.ocrProposal])
        XCTAssertEqual(initialScratchCount, 0, "disabled policy must not allocate scratch")

        let unsupported = try C23OCRSupport.bundle(languages: ["fr-FR"])
        let unsupportedOutcome = try await coordinator.extractText(unsupported.request)
        let unsupportedCallCount = await calls.value()
        XCTAssertEqual(unsupportedOutcome, .manualFallback(.typeManually))
        XCTAssertEqual(unsupportedCallCount, 0)

        await access.setState(.locked(reason: .protectedDataUnavailable))
        await XCTAssertThrowsErrorAsync(try await coordinator.extractText(bundle.request))
        let lockedCallCount = await calls.value()
        XCTAssertEqual(lockedCallCount, 0, "access denial must precede provider inspection")

        await XCTAssertThrowsErrorAsync(
            try await PreparedDisabledOCRProposalExtractorV1().extract(bundle.request)
        ) { error in
            XCTAssertEqual(error as? OCRProposalFailureV1, .capabilityUnavailable)
        }
    }

    func testV23P04C23H01LowConfidenceConflictStaleTargetAndHostileSources() async throws {
        let low = try C23OCRSupport.bundle(confidenceBasisPoints: 1_000)
        XCTAssertEqual(low.evidence.observation.confidence.basisPoints, 1_000)
        XCTAssertEqual(low.evidence.proposal.verificationState.rawValue, "UNVERIFIED")

        XCTAssertThrowsError(try OCRNormalizedCropV1(
            xBasisPoints: 9_999,
            yBasisPoints: 0,
            widthBasisPoints: 2,
            heightBasisPoints: 10_000
        ).validate())
        XCTAssertThrowsError(try C23OCRSupport.bundle(explicitUserAction: false))
        let mismatchedCrop = OCRNormalizedCropV1(
            xBasisPoints: 5_000,
            yBasisPoints: 750,
            widthBasisPoints: 4_000,
            heightBasisPoints: 2_000
        )
        XCTAssertThrowsError(try C23OCRSupport.bundle(observationCrop: mismatchedCrop)) { error in
            XCTAssertEqual(error as? OCRProposalFailureV1, .invalidValue)
        }

        let bundle = try C23OCRSupport.bundle()
        let staleContext = try C32AssistanceTestSupport.context(
            proposal: bundle.evidence.proposal,
            targetRevision: bundle.evidence.proposal.target.revision + 1
        )
        XCTAssertEqual(
            try bundle.evidence.proposal.expiryReason(in: staleContext),
            .targetRevisionChanged
        )
        XCTAssertFalse(OCRProposalSearchRebuildBoundaryV1.rawObservationIndexed)
        XCTAssertFalse(OCRProposalSearchRebuildBoundaryV1.confidenceIndexed)
        XCTAssertFalse(OCRProposalReportProjectionBoundaryV1.scratchOrSourceCropReported)
        XCTAssertFalse(OCRProposalReportProjectionBoundaryV1.customWordsReported)

        let narrowPolicy = try C23OCRSupport.policy(maximumRecognizedTextBytes: 8)
        XCTAssertThrowsError(
            try C23OCRSupport.bundle(maximumRecognizedTextBytes: 8)
        ) { error in
            XCTAssertEqual(error as? OCRProposalFailureV1, .invalidValue)
        }
        XCTAssertThrowsError(try bundle.evidence.validate(policy: narrowPolicy)) { error in
            XCTAssertEqual(error as? OCRProposalFailureV1, .invalidValue)
        }
        let narrowCoordinator = try OCRProposalCoordinatorV1(
            policy: narrowPolicy,
            access: C23AccessGate(state: .disabled),
            extractor: PreparedDisabledOCRProposalExtractorV1(),
            scratch: C23ScratchLifecycle(),
            assistance: AssistanceCoordinatorV1(lifecycle: C23AssistanceLifecycle())
        )
        let context = try C32AssistanceTestSupport.context(proposal: bundle.evidence.proposal)
        await XCTAssertThrowsErrorAsync(
            try await narrowCoordinator.present(bundle.evidence, context: context)
        ) { error in
            XCTAssertEqual(error as? OCRProposalFailureV1, .invalidValue)
        }
    }

    func testV23P04C23I01CancellationMemoryPressureAndScratchCleanup() async throws {
        let bundle = try C23OCRSupport.bundle()
        let cancelled = InjectedOnDeviceOCRProposalAdapterV1 { _ in throw CancellationError() }
        await XCTAssertThrowsErrorAsync(try await cancelled.extract(bundle.request)) { error in
            XCTAssertTrue(error is CancellationError)
        }
        let pressured = InjectedOnDeviceOCRProposalAdapterV1 { _ in
            throw C23TestFailure.memoryPressure
        }
        await XCTAssertThrowsErrorAsync(try await pressured.extract(bundle.request)) { error in
            XCTAssertEqual(error as? C23TestFailure, .memoryPressure)
        }

        let prepareFailureScratch = C23PrepareThenThrowScratch()
        let providerCalls = C23CallCounter()
        let failureEvidence = bundle.evidence
        let neverReachedProvider = InjectedOnDeviceOCRProposalAdapterV1 { _ in
            await providerCalls.increment()
            return [failureEvidence]
        }
        let enabledCoordinator = try OCRProposalCoordinatorV1(
            policy: C23OCRSupport.policy(activation: .enabledOnDevice),
            access: C23AccessGate(state: .disabled),
            extractor: neverReachedProvider,
            scratch: prepareFailureScratch,
            assistance: AssistanceCoordinatorV1(lifecycle: C23AssistanceLifecycle())
        )
        await XCTAssertThrowsErrorAsync(
            try await enabledCoordinator.extractText(bundle.request)
        ) { error in
            XCTAssertEqual(error as? C23TestFailure, .memoryPressure)
        }
        let providerCallCount = await providerCalls.value()
        XCTAssertEqual(prepareFailureScratch.prepareCount, 1)
        XCTAssertEqual(prepareFailureScratch.discardCount, 1)
        XCTAssertNil(prepareFailureScratch.boundRequestID)
        XCTAssertEqual(providerCallCount, 0)

        let scratchDiscarder = C23ScratchDiscarder()
        let scratch = AssistanceOCRProposalScratchLifecycleV1(
            assistanceScratch: scratchDiscarder,
            prepare: { request in try request.validate() }
        )
        try await scratch.prepare(bundle.request)
        try await scratch.discardAfterFailedExtraction(bundle.request)
        XCTAssertEqual(scratchDiscarder.finishedProposalIDs, [bundle.request.requestID])
        XCTAssertEqual(scratchDiscarder.finishedDispositions.map(\.rawValue), ["FAILED"])

        XCTAssertTrue(OCRProposalLifecycleBoundaryV1.scratchDeletionIsIdempotent)
        XCTAssertEqual(
            OCRProposalLifecycleBoundaryV1.persistenceMode,
            "EPHEMERAL_PROPOSAL_EXISTING_ACCEPTANCE_RECEIPT"
        )
        XCTAssertEqual(OCRProposalLifecycleBoundaryV1.addedRowCount, 0)
        XCTAssertFalse(OCRProposalLifecycleBoundaryV1.latestFallbackAllowed)
    }

    func testV23P04C23R01AcceptedReceiptRestoreNoEphemeralOrphanAndAccessibility() throws {
        let corpus = try C23OCRSupport.loadCorpus()
        XCTAssertEqual(corpus["schemaVersion"] as? Int, 1)
        XCTAssertEqual(corpus["featureDisposition"] as? String, "PREPARED_DISABLED")
        XCTAssertEqual((corpus["selectors"] as? [String])?.count, 5)

        XCTAssertEqual(OCRProposalPersistenceBoundaryV1.schemaVersion, 53)
        XCTAssertEqual(OCRProposalPersistenceBoundaryV1.activeModelCount, 168)
        XCTAssertEqual(
            OCRProposalPersistenceBoundaryV1.acceptanceRowName,
            "AssistanceAcceptanceReceiptRow"
        )
        XCTAssertTrue(OCRProposalSearchRebuildBoundaryV1.acceptedCanonicalTargetUsesIncumbentProjection)
        XCTAssertTrue(OCRProposalReportProjectionBoundaryV1.acceptedCanonicalTargetUsesIncumbentProjection)
        XCTAssertFalse(OCRProposalSearchRebuildBoundaryV1.acceptedReceiptIndexedAsFact)
        XCTAssertFalse(OCRProposalReportProjectionBoundaryV1.acceptedReceiptRenderedAsFieldFact)

        let bundle = try C23OCRSupport.bundle()
        let receipt = try C23OCRSupport.acceptanceReceipt(bundle)
        let encoded = try AssistanceCanonicalCodecV1.encode(receipt)
        let restored = try AssistanceCanonicalCodecV1.decode(
            AssistanceAcceptanceReceiptV1.self,
            from: encoded
        )
        try restored.validate(ocrEvidence: bundle.evidence)
        XCTAssertEqual(restored, receipt)

        let localization = try BundledLocalizationCatalogV1.ocrProposalRegistry()
        let accessibility = try BundledLocalizationCatalogV1.ocrProposalAccessibilityRegistry(
            localization: localization
        )
        try C32AssistanceLocalizationPolicyV1.validate()
        try C32AssistanceAccessibilityPolicyV1.validate(
            registry: accessibility,
            localization: localization
        )
        XCTAssertEqual(C32AssistanceLocalizationKeyV1.allCases.count, 31)
        XCTAssertTrue(C32AssistanceAccessibilityPolicyV1.dynamicTypeThroughAX5Required)
        XCTAssertTrue(C32AssistanceAccessibilityPolicyV1.rightToLeftReadingOrderRequired)
        XCTAssertTrue(C32AssistanceAccessibilityPolicyV1.errorFocusRequired)
        XCTAssertFalse(C32AssistanceAccessibilityPolicyV1.uiAdoptionClaimed)
    }
}

private enum C23TestFailure: Error, Equatable { case unavailable, memoryPressure }

private enum C23OCRSupport {
    struct Bundle {
        let request: OCRExtractionRequestV1
        let evidence: OCRProposalEvidenceV1
        let acceptance: C32AssistanceTestSupport.AcceptanceFixture
    }

    static func policy(
        activation: OCRFeatureActivationV1 = .preparedDisabled,
        maximumRecognizedTextBytes: Int = 8_192
    ) throws -> OCRCapabilityPolicyV1 {
        try OCRCapabilityPolicyV1(
            assistancePolicy: C32AssistanceTestSupport.policy(
                enabled: activation == .enabledOnDevice
            ),
            activation: activation,
            supportedLanguageIdentifiers: ["en-US"],
            maximumRecognizedTextBytes: maximumRecognizedTextBytes
        )
    }

    static func bundle(
        languages: [String] = ["en-US"],
        confidenceBasisPoints: Int = 8_750,
        explicitUserAction: Bool = true,
        observationCrop: OCRNormalizedCropV1? = nil,
        maximumRecognizedTextBytes: Int = 8_192
    ) throws -> Bundle {
        let acceptedValue = ResponseValueV1.text("Observed local field value")
        let acceptance = try C32AssistanceTestSupport.acceptanceFixture(
            slot: 86,
            value: acceptedValue
        )
        let target = acceptance.proposal.target
        let source = acceptance.proposal.source
        let crop = OCRNormalizedCropV1(
            xBasisPoints: 500,
            yBasisPoints: 750,
            widthBasisPoints: 4_000,
            heightBasisPoints: 2_000
        )
        let request = try OCRExtractionRequestV1(
            requestID: C32AssistanceTestSupport.id(8_601),
            workspaceID: target.workspaceID,
            target: target,
            source: source,
            sourceCrop: crop,
            requestedLanguageIdentifiers: languages,
            packageCustomWords: ["Emergency", "Luminaire"],
            explicitUserAction: explicitUserAction,
            requestedAt: C32AssistanceTestSupport.fixedDate
        )
        let confidence = try AssistanceConfidenceV1(basisPoints: confidenceBasisPoints)
        let observation = OCRTextObservationV1(
            observationID: C32AssistanceTestSupport.id(8_602),
            recognizedText: "Observed local field value",
            confidence: confidence,
            crop: observationCrop ?? crop
        )
        let metadataSHA = try OCRProposalEvidenceV1.metadataSHA256(
            request: request,
            frameworkIdentifier: "APPLE_VISION",
            frameworkRevision: 1,
            recognitionRequestRevision: 1,
            configuredLanguageIdentifiers: languages,
            maximumRecognizedTextBytes: maximumRecognizedTextBytes,
            observation: observation
        )
        let proposal = try AssistanceProposalV1(
            proposalID: request.requestID,
            capability: acceptance.proposal.capability,
            target: target,
            value: acceptedValue,
            source: source,
            confidence: confidence,
            quality: AssistanceQualityMetadataV1(
                metricID: "OCR_EVIDENCE_V1",
                ratingID: metadataSHA
            ),
            packageReleaseSHA256: acceptance.proposal.packageReleaseSHA256,
            definitionReleaseSHA256: acceptance.proposal.definitionReleaseSHA256,
            createdAt: acceptance.proposal.createdAt,
            expiresAt: acceptance.proposal.expiresAt,
            privacyClass: acceptance.proposal.privacyClass
        )
        let evidence = try OCRProposalEvidenceV1(
            request: request,
            frameworkIdentifier: "APPLE_VISION",
            frameworkRevision: 1,
            recognitionRequestRevision: 1,
            configuredLanguageIdentifiers: languages,
            maximumRecognizedTextBytes: maximumRecognizedTextBytes,
            observation: observation,
            proposal: proposal
        )
        return Bundle(request: request, evidence: evidence, acceptance: acceptance)
    }

    static func acceptanceReceipt(_ bundle: Bundle) throws -> AssistanceAcceptanceReceiptV1 {
        let fixture = bundle.acceptance
        let request = try AssistanceAcceptanceRequestV1(
            proposal: bundle.evidence.proposal,
            targetMutation: fixture.targetMutation,
            expectedRevision: fixture.expectedRevision,
            mutationID: fixture.mutationID,
            acceptedBy: fixture.reviewer,
            acceptedAt: fixture.acceptedAt
        )
        let replicaID = ReplicaID(rawValue: C32AssistanceTestSupport.id(8_610))
        let envelope = try MutationEnvelopeV1(
            request: request.canonicalWorkspaceMutationRequest(),
            identity: WorkspaceReplicaIdentityV1(
                workspaceID: request.proposal.target.workspaceID,
                replicaID: replicaID
            )
        )
        let postImages: [MutationPostImageV1]
        switch request.targetMutation {
        case .surveySession(let mutation): postImages = try mutation.mutationPostImages
        }
        let resultingRevision = try MutationPortableExpectedRevisionV1(
            WorkspaceExpectedRevisionV1(
                workspaceID: request.proposal.target.workspaceID,
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
                workspaceID: request.proposal.target.workspaceID,
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

    static func review(
        _ disposition: OCRFieldReviewDispositionV1,
        value: ResponseValueV1? = .text("Observed local field value"),
        evidence: OCRProposalEvidenceV1
    ) throws -> OCRFieldReviewV1 {
        try OCRFieldReviewV1(
            evidence: evidence,
            disposition: disposition,
            reviewedValue: value,
            reviewedBy: C26SurveySessionTestSupport.actor(
                workspaceID: evidence.request.workspaceID,
                slot: 8_604,
                responsibility: .reviewedBy
            ),
            reviewedAt: evidence.proposal.createdAt.addingTimeInterval(1)
        )
    }

    static func loadCorpus() throws -> [String: Any] {
        let url = try XCTUnwrap(Foundation.Bundle(for: V9_86OCRProposalTests.self).url(
            forResource: "V23P04C23OCRProposalCorpusV1",
            withExtension: "json",
            subdirectory: "Fixtures/V23/Assistance"
        ))
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}

private actor C23CallCounter {
    private var count = 0
    func increment() { count += 1 }
    func value() -> Int { count }
}

@MainActor
private final class C23ScratchLifecycle: OCRProposalScratchLifecycleV1 {
    private(set) var prepareCount = 0
    private(set) var discardCount = 0
    func prepare(_ request: OCRExtractionRequestV1) async throws {
        try request.validate()
        prepareCount += 1
    }
    func discardAfterFailedExtraction(_ request: OCRExtractionRequestV1) async throws {
        try request.validate()
        discardCount += 1
    }
}

@MainActor
private final class C23PrepareThenThrowScratch: OCRProposalScratchLifecycleV1 {
    private(set) var prepareCount = 0
    private(set) var discardCount = 0
    private(set) var boundRequestID: UUID?
    func prepare(_ request: OCRExtractionRequestV1) async throws {
        try request.validate()
        prepareCount += 1
        boundRequestID = request.requestID
        throw C23TestFailure.memoryPressure
    }
    func discardAfterFailedExtraction(_ request: OCRExtractionRequestV1) async throws {
        try request.validate()
        guard boundRequestID == request.requestID else { throw C23TestFailure.unavailable }
        discardCount += 1
        boundRequestID = nil
    }
}

@MainActor
private final class C23ScratchDiscarder: AssistanceScratchDiscardingV1 {
    private(set) var finishedProposalIDs: [UUID] = []
    private(set) var finishedDispositions: [ScratchPublicationDispositionV1] = []
    func discardAssistanceScratch(
        proposalID: UUID,
        source: AssistanceSourceReferenceV1
    ) async throws {}
    func discardOrphanedAssistanceScratch(
        retainingProposalIDs: Set<UUID>
    ) async throws {}
    func finishAssistanceScratch(
        proposalID: UUID,
        source: AssistanceSourceReferenceV1,
        disposition: ScratchPublicationDispositionV1,
        immutableContentReceiptDigest: String?
    ) async throws {
        finishedProposalIDs.append(proposalID)
        finishedDispositions.append(disposition)
        XCTAssertNil(immutableContentReceiptDigest)
    }
}

private actor C23AccessGate: AppAccessGatePortV1 {
    private var state: AppAccessStateV1
    private var surfaces: [AppAccessContentReadSurfaceV1] = []
    init(state: AppAccessStateV1) { self.state = state }
    func currentState() async -> AppAccessStateV1 { state }
    func lock(reason: AppLockReasonV1) async { state = .locked(reason: reason) }
    func authenticate(trigger: LocalAuthenticationTriggerV1) async -> LocalAuthenticationOutcomeV1 {
        .unavailable
    }
    func requireContentAccess() async throws {
        guard state.permitsContentAccess else { throw C23TestFailure.unavailable }
    }
    func requireContentAccess(
        for surface: AppAccessContentReadSurfaceV1
    ) async throws -> AppAccessContentPermitV1 {
        surfaces.append(surface)
        return try AppAccessContentPermitV1(surface: surface, state: state)
    }
    func setState(_ state: AppAccessStateV1) { self.state = state }
    func requestedSurfaces() -> [AppAccessContentReadSurfaceV1] { surfaces }
}

@MainActor
private final class C23AssistanceLifecycle: AssistanceProposalLifecycleV1 {
    func obtainReviewSnapshot(for proposal: AssistanceProposalV1) async throws
        -> AssistanceProposalEvaluationContextV1 { throw C23TestFailure.unavailable }
    func present(_ proposal: AssistanceProposalV1,
                 context: AssistanceProposalEvaluationContextV1) async throws {}
    func proposal(proposalID: UUID) async -> AssistanceProposalV1? { nil }
    func activeProposals(workspaceID: WorkspaceID) async -> [AssistanceProposalV1] { [] }
    func review(proposalID: UUID, context: AssistanceProposalEvaluationContextV1) async throws
        -> AssistanceReviewDecisionV1 { throw C23TestFailure.unavailable }
    func accept(proposalID: UUID, targetMutation: AssistanceCanonicalTargetMutationV1,
                expectedRevision: WorkspaceExpectedRevisionV1, mutationID: MutationIDV1,
                acceptedBy: ActorSnapshotV1, acceptedAt: Date,
                context: AssistanceProposalEvaluationContextV1) async throws
        -> AssistanceAcceptanceReceiptV1 { throw C23TestFailure.unavailable }
    func remove(proposalID: UUID, kind: AssistanceRemovalKindV1,
                expiryReason: AssistanceProposalExpiryReasonV1?) async throws
        -> AssistanceRemovalDispositionV1 {
        try AssistanceRemovalDispositionV1(
            proposalID: proposalID,
            kind: kind,
            expiryReason: expiryReason
        )
    }
    func expireAll(contextByProposal: [UUID: AssistanceProposalEvaluationContextV1]) async throws
        -> [AssistanceExpiryDispositionV1] { [] }
    func recoverAfterInterruption() async throws {}
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error. \(message())", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
