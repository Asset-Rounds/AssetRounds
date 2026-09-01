import Foundation
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V9_87DictationLocationProposalTests: XCTestCase {
    func testV23P04C24G01EnabledOnDeviceDictationEditAcceptAndOneShotLocationReview() async throws {
        let policy = try C24Support.policy(enabled: true)
        let dictation = try C24Support.dictationBundle(policy: policy)
        let location = try C24Support.locationBundle(policy: policy)
        let lifecycle = C24AssistanceLifecycle()
        let coordinator = try C24Support.coordinator(
            policy: policy,
            dictation: dictation,
            location: location,
            lifecycle: lifecycle
        )

        let draftOutcome = try await coordinator.dictate(dictation.request)
        guard case .dictation(let draft) = draftOutcome else { return XCTFail("expected dictation") }
        XCTAssertEqual(draft.request.recognitionRequestRevision, 3)
        XCTAssertEqual(draft.transcriptRevision, 1)
        XCTAssertEqual(draft.audioRevision, draft.request.scratchSource.revision)
        XCTAssertTrue(draft.processedOnDevice)
        XCTAssertFalse(draft.networkAccessUsed)
        XCTAssertFalse(draft.temporaryAudioRetained)
        XCTAssertEqual(lifecycle.acceptCount, 0, "provider output must never write automatically")

        let context = try C32AssistanceTestSupport.context(proposal: draft.proposal)
        try await coordinator.present(draft, context: context)
        XCTAssertEqual(dictation.edited.transcriptRevision, 2)
        XCTAssertEqual(dictation.edited.transcript, "Reviewed dictated value")
        let dictationReview = try DictationLocationProposalReviewV1(
            originalProposalID: draft.proposal.proposalID,
            originalEvidenceSHA256: draft.proposalEvidenceSHA256,
            originalValue: draft.proposal.value,
            disposition: .edited,
            reviewedValue: .text("Reviewed dictated value"),
            reviewedBy: dictation.acceptance.reviewer,
            reviewedAt: dictation.acceptance.acceptedAt
        )
        let reviewedDictationValue = try await coordinator.applyReview(
            dictationReview,
            dictation: draft,
            correctedProposalID: C32AssistanceTestSupport.id(8_702),
            context: context
        )
        let reviewedDictation = try XCTUnwrap(reviewedDictationValue)
        XCTAssertEqual(lifecycle.scratchTransferCount, 1)
        XCTAssertEqual(lifecycle.scratchTerminalCount, 0)
        XCTAssertEqual(lifecycle.scratchOwnerProposalID, reviewedDictation.proposalID)
        let dictationReceipt = try await coordinator.acceptReviewed(
            reviewedDictation,
            dictation: draft,
            review: dictationReview,
            targetMutation: dictation.acceptance.targetMutation,
            expectedRevision: dictation.acceptance.expectedRevision,
            mutationID: dictation.acceptance.mutationID,
            context: context
        )
        XCTAssertEqual(dictationReceipt.acceptedValue, .text("Reviewed dictated value"))
        XCTAssertEqual(lifecycle.scratchTerminalCount, 1)
        XCTAssertNil(lifecycle.scratchOwnerProposalID)
        try dictationReceipt.validate(
            dictation: draft,
            review: dictationReview,
            acceptedProposal: reviewedDictation
        )
        XCTAssertTrue(try DictationLocationProposalSearchRebuildBoundaryV1.acceptsCanonicalTargetFact(
            receipt: dictationReceipt,
            dictation: draft,
            review: dictationReview,
            acceptedProposal: reviewedDictation,
            policy: policy
        ))

        let locationOutcome = try await coordinator.locate(location.request)
        guard case .location(let oneShot) = locationOutcome else { return XCTFail("expected location") }
        XCTAssertEqual(oneShot.observation.latitudeMicrodegrees, 40_712_800)
        XCTAssertEqual(oneShot.observation.longitudeMicrodegrees, -74_006_000)
        XCTAssertEqual(oneShot.observation.observedAt, oneShot.request.requestedAt.addingTimeInterval(1))
        XCTAssertEqual(oneShot.observation.horizontalAccuracyMillimeters, 12_500)
        XCTAssertEqual(oneShot.observation.verticalAccuracyMillimeters, 20_000)
        XCTAssertEqual(oneShot.observation.source, .coreLocationWhenInUse)
        XCTAssertEqual(oneShot.observation.accuracyAuthorization, .full)
        XCTAssertEqual(lifecycle.acceptCount, 1, "location proposal must await explicit review")
        let locationContext = try C32AssistanceTestSupport.context(proposal: oneShot.proposal)
        try await coordinator.present(oneShot, context: locationContext)
        let locationReview = try DictationLocationProposalReviewV1(
            originalProposalID: oneShot.proposal.proposalID,
            originalEvidenceSHA256: oneShot.proposalEvidenceSHA256,
            originalValue: oneShot.proposal.value,
            disposition: .accepted,
            reviewedValue: oneShot.proposal.value,
            reviewedBy: location.acceptance.reviewer,
            reviewedAt: location.acceptance.acceptedAt
        )
        let reviewedLocationValue = try await coordinator.applyReview(
            locationReview,
            location: oneShot,
            correctedProposalID: nil,
            context: locationContext
        )
        let reviewedLocation = try XCTUnwrap(reviewedLocationValue)
        let locationReceipt = try await coordinator.acceptReviewed(
            reviewedLocation,
            location: oneShot,
            review: locationReview,
            targetMutation: location.acceptance.targetMutation,
            expectedRevision: location.acceptance.expectedRevision,
            mutationID: location.acceptance.mutationID,
            context: locationContext
        )
        XCTAssertEqual(locationReceipt.acceptedValue, location.manualValue)
        try locationReceipt.validate(
            location: oneShot,
            review: locationReview,
            acceptedProposal: reviewedLocation
        )
        XCTAssertTrue(try DictationLocationProposalReportProjectionBoundaryV1.acceptsCanonicalTargetFact(
            receipt: locationReceipt,
            location: oneShot,
            review: locationReview,
            acceptedProposal: reviewedLocation,
            policy: policy
        ))
        XCTAssertEqual(lifecycle.acceptCount, 2)
    }

    func testV23P04C24A01IndependentPermissionDenialsAndCompleteManualFallbacks() async throws {
        let policy = try C24Support.policy(enabled: true)
        let dictation = try C24Support.dictationBundle(policy: policy)
        let location = try C24Support.locationBundle(policy: policy)
        let deniedSpeech = try SpeechPermissionDispositionV1(
            microphone: .denied,
            speechRecognition: .authorized,
            observedAt: C24Support.permissionDate
        )
        let deniedLocation = try LocationPermissionDispositionV1(
            whenInUse: .denied,
            observedAt: C24Support.permissionDate
        )
        let providerCalls = C24CallCounter()
        let coordinator = try C24Support.coordinator(
            policy: policy,
            dictation: dictation,
            location: location,
            speechPermission: deniedSpeech,
            locationPermission: deniedLocation,
            providerCalls: providerCalls,
            lifecycle: C24AssistanceLifecycle()
        )
        XCTAssertEqual(
            try await coordinator.dictate(dictation.request),
            .manualDictation(DictationManualFallbackV1.allCases)
        )
        XCTAssertEqual(
            try await coordinator.locate(location.request),
            .manualLocation(LocationManualFallbackV1.allCases)
        )
        let deniedProviderCount = await providerCalls.value()
        XCTAssertEqual(deniedProviderCount, 0)

        let speechRecognitionDenied = try SpeechPermissionDispositionV1(
            microphone: .authorized,
            speechRecognition: .denied,
            observedAt: C24Support.permissionDate
        )
        let independentCalls = C24CallCounter()
        let independentCoordinator = try C24Support.coordinator(
            policy: policy,
            dictation: dictation,
            location: location,
            speechPermission: speechRecognitionDenied,
            locationPermission: location.permission,
            providerCalls: independentCalls,
            lifecycle: C24AssistanceLifecycle()
        )
        XCTAssertEqual(
            try await independentCoordinator.dictate(dictation.request),
            .manualDictation(DictationManualFallbackV1.allCases)
        )
        guard case .location = try await independentCoordinator.locate(location.request) else {
            return XCTFail("speech denial must not disable one-shot location")
        }
        let independentProviderCount = await independentCalls.value()
        XCTAssertEqual(independentProviderCount, 1)
        XCTAssertFalse(speechRecognitionDenied.permitsOnDeviceDictation)
        XCTAssertFalse(deniedLocation.permitsOneShotForegroundLocation)
        XCTAssertEqual(policy.dictationPolicy.manualFallback, .typeManually)
        XCTAssertEqual(policy.locationPolicy.manualFallback, .typeManually)
    }

    func testV23P04C24H01UnsupportedLocalePoorAccuracyStaleTargetAndNoServer() async throws {
        let policy = try C24Support.policy(enabled: true)
        let unsupported = try C24Support.dictationBundle(policy: policy, locale: "fr-FR")
        let location = try C24Support.locationBundle(policy: policy)
        let calls = C24CallCounter()
        let coordinator = try C24Support.coordinator(
            policy: policy,
            dictation: unsupported,
            location: location,
            providerCalls: calls,
            lifecycle: C24AssistanceLifecycle()
        )
        XCTAssertEqual(
            try await coordinator.dictate(unsupported.request),
            .manualDictation(DictationManualFallbackV1.allCases)
        )
        let unsupportedProviderCount = await calls.value()
        XCTAssertEqual(unsupportedProviderCount, 0)

        XCTAssertThrowsError(
            try C24Support.locationBundle(policy: policy, horizontalAccuracyMillimeters: 100_001)
        ) { error in
            XCTAssertEqual(error as? DictationLocationProposalFailureV1, .invalidValue)
        }
        let stale = try C32AssistanceTestSupport.context(
            proposal: location.proposal.proposal,
            targetRevision: location.proposal.proposal.target.revision + 1
        )
        XCTAssertEqual(
            try location.proposal.proposal.expiryReason(in: stale),
            .targetRevisionChanged
        )
        XCTAssertFalse(location.request.foreground == false)
        XCTAssertFalse(dictation.edited.networkAccessUsed)
        XCTAssertFalse(DictationLocationProposalLifecycleBoundaryV1.serverSpeechFallbackAllowed)
        XCTAssertFalse(DictationLocationProposalLifecycleBoundaryV1.backgroundLocationAllowed)
        XCTAssertFalse(DictationLocationProposalSearchRebuildBoundaryV1.rawTranscriptIndexed)
        XCTAssertFalse(DictationLocationProposalReportProjectionBoundaryV1.preciseLocationProposalReported)

        let forgedLifecycle = C24AssistanceLifecycle()
        let validDictation = try C24Support.dictationBundle(policy: policy)
        let forgedCoordinator = try C24Support.coordinator(
            policy: policy,
            dictation: validDictation,
            location: location,
            lifecycle: forgedLifecycle
        )
        let forgedContext = try C32AssistanceTestSupport.context(
            proposal: validDictation.draft.proposal
        )
        try await forgedCoordinator.present(validDictation.draft, context: forgedContext)
        let forgedReview = try DictationLocationProposalReviewV1(
            originalProposalID: validDictation.draft.proposal.proposalID,
            originalEvidenceSHA256: String(repeating: "f", count: 64),
            originalValue: validDictation.draft.proposal.value,
            disposition: .accepted,
            reviewedValue: validDictation.draft.proposal.value,
            reviewedBy: validDictation.acceptance.reviewer,
            reviewedAt: validDictation.acceptance.acceptedAt
        )
        await XCTAssertThrowsC24(try await forgedCoordinator.acceptReviewed(
            validDictation.draft.proposal,
            dictation: validDictation.draft,
            review: forgedReview,
            targetMutation: validDictation.acceptance.targetMutation,
            expectedRevision: validDictation.acceptance.expectedRevision,
            mutationID: validDictation.acceptance.mutationID,
            context: forgedContext
        ))
        XCTAssertEqual(forgedLifecycle.acceptCount, 0, "forged review must fail before writer effect")
    }

    func testV23P04C24I01AudioInterruptionLocationTimeoutAndScratchCleanup() async throws {
        let policy = try C24Support.policy(enabled: true)
        let dictation = try C24Support.dictationBundle(policy: policy)
        let location = try C24Support.locationBundle(policy: policy)
        let scratch = C24ScratchLifecycle()
        let speechPermission = dictation.permission
        let locationPermission = location.permission
        let speech = InjectedOnDeviceSpeechCapabilityAdapterV1(
            permission: { speechPermission },
            requestMicrophone: { speechPermission },
            requestSpeechRecognition: { speechPermission },
            dictate: { _ in throw C24TestFailure.audioInterrupted }
        )
        let locationAdapter = InjectedOneShotLocationCapabilityAdapterV1(
            permission: { locationPermission },
            requestWhenInUse: { locationPermission },
            locate: { _ in throw C24TestFailure.locationTimeout }
        )
        let coordinator = try DictationLocationProposalCoordinatorV1(
            policy: policy,
            access: C24AccessGate(),
            speech: speech,
            location: locationAdapter,
            scratch: scratch,
            assistance: AssistanceCoordinatorV1(lifecycle: C24AssistanceLifecycle())
        )
        await XCTAssertThrowsC24(try await coordinator.dictate(dictation.request)) { error in
            XCTAssertEqual(error as? C24TestFailure, .audioInterrupted)
        }
        XCTAssertEqual(scratch.prepareCount, 1)
        XCTAssertEqual(scratch.discardCount, 1)
        XCTAssertNil(scratch.boundRequestID)
        await XCTAssertThrowsC24(try await coordinator.locate(location.request)) { error in
            XCTAssertEqual(error as? C24TestFailure, .locationTimeout)
        }
        XCTAssertEqual(scratch.discardCount, 1, "location never owns dictation audio scratch")
        let rejectionLifecycle = C24AssistanceLifecycle()
        let rejectionCoordinator = try C24Support.coordinator(
            policy: policy,
            dictation: dictation,
            location: location,
            lifecycle: rejectionLifecycle
        )
        let rejectionContext = try C32AssistanceTestSupport.context(
            proposal: dictation.draft.proposal
        )
        try await rejectionCoordinator.present(dictation.draft, context: rejectionContext)
        let rejectionReview = try DictationLocationProposalReviewV1(
            originalProposalID: dictation.draft.proposal.proposalID,
            originalEvidenceSHA256: dictation.draft.proposalEvidenceSHA256,
            originalValue: dictation.draft.proposal.value,
            disposition: .rejected,
            reviewedValue: nil,
            reviewedBy: dictation.acceptance.reviewer,
            reviewedAt: dictation.acceptance.acceptedAt
        )
        let rejectedValue = try await rejectionCoordinator.applyReview(
            rejectionReview,
            dictation: dictation.draft,
            correctedProposalID: nil,
            context: rejectionContext
        )
        XCTAssertNil(rejectedValue)
        XCTAssertEqual(rejectionLifecycle.scratchTerminalCount, 1)
        XCTAssertNil(rejectionLifecycle.scratchOwnerProposalID)
        XCTAssertTrue(DictationLocationProposalLifecycleBoundaryV1.latestTargetFallbackAllowed == false)
        XCTAssertEqual(DictationLocationProposalLifecycleBoundaryV1.addedDurableRows, 0)
    }

    func testV23P04C24R01AcceptedReceiptRestoreNoEphemeralOrphanAndAccessibility() async throws {
        let policy = try C24Support.policy(enabled: true)
        let dictation = try C24Support.dictationBundle(policy: policy)
        let location = try C24Support.locationBundle(policy: policy)
        let dictationReceipt = try C24Support.receipt(
            proposal: dictation.edited.proposal,
            acceptance: dictation.acceptance
        )
        let locationReceipt = try C24Support.receipt(
            proposal: location.proposal.proposal,
            acceptance: location.acceptance
        )
        let restoredDictation = try AssistanceCanonicalCodecV1.decode(
            AssistanceAcceptanceReceiptV1.self,
            from: AssistanceCanonicalCodecV1.encode(dictationReceipt)
        )
        let restoredLocation = try AssistanceCanonicalCodecV1.decode(
            AssistanceAcceptanceReceiptV1.self,
            from: AssistanceCanonicalCodecV1.encode(locationReceipt)
        )
        XCTAssertTrue(try DictationLocationProposalSearchRebuildBoundaryV1.acceptsCanonicalTargetFact(
            receipt: restoredDictation, proposal: dictation.edited, policy: policy
        ))
        XCTAssertTrue(try DictationLocationProposalReportProjectionBoundaryV1.acceptsCanonicalTargetFact(
            receipt: restoredLocation, proposal: location.proposal, policy: policy
        ))
        XCTAssertFalse(DictationLocationProposalSearchRebuildBoundaryV1.mayIndex(dictation.edited))
        XCTAssertFalse(DictationLocationProposalSearchRebuildBoundaryV1.mayIndex(location.proposal))
        XCTAssertFalse(DictationLocationProposalReportProjectionBoundaryV1.mayProject(dictation.edited))
        XCTAssertFalse(DictationLocationProposalReportProjectionBoundaryV1.mayProject(location.proposal))

        let localization = try BundledLocalizationCatalogV1.dictationLocationProposalRegistry()
        let accessibility = try BundledLocalizationCatalogV1.dictationLocationProposalAccessibilityRegistry(
            localization: localization
        )
        try C24DictationLocationLocalizationPolicyV1.validate()
        try C24DictationLocationAccessibilityPolicyV1.validate()
        XCTAssertEqual(C24DictationLocationLocalizationKeyV1.allCases.count, 30)
        XCTAssertEqual(C24DictationLocationAccessibilityIDV1.allCases.count, 18)
        XCTAssertFalse(C24DictationLocationAccessibilityPolicyV1.uiAdoptionClaimed)
        XCTAssertFalse(accessibility.entries.isEmpty)

        let corpus = try C24Support.loadCorpus()
        XCTAssertEqual(corpus["sourceLocale"] as? String, "en")
        XCTAssertEqual((corpus["selectors"] as? [String])?.count, 5)
        XCTAssertEqual(DictationLocationPersistenceBoundaryV1.addedDurableRowCount, 0)
        XCTAssertEqual(DictationLocationPersistenceBoundaryV1.acceptanceRowName, "AssistanceAcceptanceReceiptRow")
        XCTAssertFalse(DictationLocationPersistenceBoundaryV1.productionAdoptionEnabled)
    }
}

private enum C24TestFailure: Error, Equatable { case audioInterrupted, locationTimeout, unavailable }

private enum C24Support {
    static let permissionDate = C32AssistanceTestSupport.fixedDate.addingTimeInterval(-1)

    struct DictationBundle {
        let request: OnDeviceDictationRequestV1
        let draft: OnDeviceDictationProposalV1
        let edited: OnDeviceDictationProposalV1
        let permission: SpeechPermissionDispositionV1
        let acceptance: C32AssistanceTestSupport.AcceptanceFixture
    }
    struct LocationBundle {
        let request: OneShotLocationRequestV1
        let proposal: OneShotLocationProposalV1
        let permission: LocationPermissionDispositionV1
        let manualValue: ResponseValueV1
        let acceptance: C32AssistanceTestSupport.AcceptanceFixture
    }

    static func capability(_ id: String, locale: String? = nil) throws
        -> AssistanceCapabilityReferenceV1 {
        try AssistanceCapabilityReferenceV1(
            capabilityID: id,
            version: "\(id)_V1",
            localeIdentifier: locale
        )
    }

    static func policy(enabled: Bool) throws -> DictationLocationCapabilityPolicyV1 {
        try DictationLocationCapabilityPolicyV1(
            dictationPolicy: C32AssistanceTestSupport.policy(
                capability: capability("DICTATION_FIELD_PROPOSAL", locale: "en-US"),
                enabled: enabled
            ),
            locationPolicy: C32AssistanceTestSupport.policy(
                capability: capability("ONE_SHOT_LOCATION_PROPOSAL"),
                enabled: enabled
            ),
            dictationActivation: enabled ? .enabledOnDevice : .preparedDisabled,
            locationActivation: enabled ? .enabledOnDevice : .preparedDisabled,
            supportedDictationLocales: ["en-US"],
            maximumTranscriptUTF8Bytes: 256,
            maximumHorizontalAccuracyMillimeters: 100_000
        )
    }

    static func dictationBundle(
        policy: DictationLocationCapabilityPolicyV1,
        locale: String = "en-US"
    ) throws -> DictationBundle {
        let finalValue = ResponseValueV1.text("Reviewed dictated value")
        let acceptance = try C32AssistanceTestSupport.acceptanceFixture(slot: 87, value: finalValue)
        let source = try C32AssistanceTestSupport.source(
            sourceID: "dictation-c24-audio",
            revision: 9,
            digest: String(repeating: "d", count: 64)
        )
        let request = try OnDeviceDictationRequestV1(
            requestID: C32AssistanceTestSupport.id(8_701),
            workspaceID: acceptance.proposal.target.workspaceID,
            target: acceptance.proposal.target,
            scratchSource: source,
            localeIdentifier: locale,
            recognitionRequestRevision: 3,
            explicitUserAction: true,
            requestedAt: C32AssistanceTestSupport.fixedDate
        )
        let permission = try SpeechPermissionDispositionV1(
            microphone: .authorized,
            speechRecognition: .authorized,
            observedAt: permissionDate
        )
        func proposal(_ text: String, revision: UInt64) throws -> OnDeviceDictationProposalV1 {
            let assistance = try AssistanceProposalV1(
                proposalID: request.requestID,
                capability: capability("DICTATION_FIELD_PROPOSAL", locale: locale),
                target: request.target,
                value: .text(text),
                source: source,
                confidence: AssistanceConfidenceV1(basisPoints: 7_500),
                quality: nil,
                packageReleaseSHA256: acceptance.proposal.packageReleaseSHA256,
                definitionReleaseSHA256: acceptance.proposal.definitionReleaseSHA256,
                createdAt: acceptance.proposal.createdAt,
                expiresAt: acceptance.proposal.expiresAt,
                privacyClass: .sensitiveWorkData
            )
            return try OnDeviceDictationProposalV1(
                request: request,
                permission: permission,
                providerVersion: "APPLE_SPEECH_V1",
                transcriptRevision: revision,
                audioRevision: source.revision,
                transcript: text,
                proposal: assistance,
                maximumTranscriptUTF8Bytes: policy.maximumTranscriptUTF8Bytes
            )
        }
        return try DictationBundle(
            request: request,
            draft: proposal("Draft dictated value", revision: 1),
            edited: proposal("Reviewed dictated value", revision: 2),
            permission: permission,
            acceptance: acceptance
        )
    }

    static func locationBundle(
        policy: DictationLocationCapabilityPolicyV1,
        horizontalAccuracyMillimeters: UInt64 = 12_500
    ) throws -> LocationBundle {
        let manualValue = ResponseValueV1.text("40.712800,-74.006000")
        let acceptance = try C32AssistanceTestSupport.acceptanceFixture(
            slot: 88,
            value: manualValue,
            workspaceID: C32AssistanceTestSupport.workspace(2)
        )
        let source = try C32AssistanceTestSupport.source(
            kind: .deviceObservation,
            sourceID: "location-c24-once",
            revision: 1,
            digest: String(repeating: "e", count: 64)
        )
        let request = try OneShotLocationRequestV1(
            requestID: C32AssistanceTestSupport.id(8_801),
            workspaceID: acceptance.proposal.target.workspaceID,
            target: acceptance.proposal.target,
            source: source,
            foreground: true,
            explicitUserAction: true,
            requestedAt: C32AssistanceTestSupport.fixedDate
        )
        let observation = try OneShotLocationObservationV1(
            latitudeMicrodegrees: 40_712_800,
            longitudeMicrodegrees: -74_006_000,
            observedAt: request.requestedAt.addingTimeInterval(1),
            horizontalAccuracyMillimeters: horizontalAccuracyMillimeters,
            verticalAccuracyMillimeters: 20_000,
            source: .coreLocationWhenInUse,
            accuracyAuthorization: .full
        )
        let assistance = try AssistanceProposalV1(
            proposalID: request.requestID,
            capability: capability("ONE_SHOT_LOCATION_PROPOSAL"),
            target: request.target,
            value: manualValue,
            source: source,
            confidence: AssistanceConfidenceV1(basisPoints: 8_000),
            quality: nil,
            packageReleaseSHA256: acceptance.proposal.packageReleaseSHA256,
            definitionReleaseSHA256: acceptance.proposal.definitionReleaseSHA256,
            createdAt: acceptance.proposal.createdAt,
            expiresAt: acceptance.proposal.expiresAt,
            privacyClass: .preciseLocation
        )
        let permission = try LocationPermissionDispositionV1(
            whenInUse: .authorized,
            observedAt: request.requestedAt
        )
        let proposal = try OneShotLocationProposalV1(
            request: request,
            permission: permission,
            observation: observation,
            manualEquivalentValue: manualValue,
            proposal: assistance,
            maximumHorizontalAccuracyMillimeters: policy.maximumHorizontalAccuracyMillimeters
        )
        return try LocationBundle(
            request: request,
            proposal: proposal,
            permission: permission,
            manualValue: manualValue,
            acceptance: acceptance
        )
    }

    @MainActor static func coordinator(
        policy: DictationLocationCapabilityPolicyV1,
        dictation: DictationBundle,
        location: LocationBundle,
        speechPermission: SpeechPermissionDispositionV1? = nil,
        locationPermission: LocationPermissionDispositionV1? = nil,
        providerCalls: C24CallCounter? = nil,
        lifecycle: C24AssistanceLifecycle
    ) throws -> DictationLocationProposalCoordinatorV1 {
        let speechValue = dictation.draft
        let locationValue = location.proposal
        let speechPermission = speechPermission ?? dictation.permission
        let locationPermission = locationPermission ?? location.permission
        return try DictationLocationProposalCoordinatorV1(
            policy: policy,
            access: C24AccessGate(),
            speech: InjectedOnDeviceSpeechCapabilityAdapterV1(
                permission: { speechPermission },
                requestMicrophone: { speechPermission },
                requestSpeechRecognition: { speechPermission },
                dictate: { _ in await providerCalls?.increment(); return speechValue }
            ),
            location: InjectedOneShotLocationCapabilityAdapterV1(
                permission: { locationPermission },
                requestWhenInUse: { locationPermission },
                locate: { _ in await providerCalls?.increment(); return locationValue }
            ),
            scratch: C24ScratchLifecycle(),
            assistance: AssistanceCoordinatorV1(lifecycle: lifecycle)
        )
    }

    static func receipt(
        proposal: AssistanceProposalV1,
        acceptance: C32AssistanceTestSupport.AcceptanceFixture
    ) throws -> AssistanceAcceptanceReceiptV1 {
        let request = try AssistanceAcceptanceRequestV1(
            proposal: proposal,
            targetMutation: acceptance.targetMutation,
            expectedRevision: acceptance.expectedRevision,
            mutationID: acceptance.mutationID,
            acceptedBy: acceptance.reviewer,
            acceptedAt: acceptance.acceptedAt
        )
        let replicaID = ReplicaID(rawValue: C32AssistanceTestSupport.id(8_899))
        let envelope = try MutationEnvelopeV1(
            request: request.canonicalWorkspaceMutationRequest(),
            identity: WorkspaceReplicaIdentityV1(
                workspaceID: proposal.target.workspaceID,
                replicaID: replicaID
            )
        )
        let postImages: [MutationPostImageV1]
        switch request.targetMutation {
        case .surveySession(let mutation): postImages = try mutation.mutationPostImages
        }
        let resultingRevision = try MutationPortableExpectedRevisionV1(
            WorkspaceExpectedRevisionV1(
                workspaceID: proposal.target.workspaceID,
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
                workspaceID: proposal.target.workspaceID,
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

    static func loadCorpus() throws -> [String: Any] {
        let url = try XCTUnwrap(Foundation.Bundle(for: V9_87DictationLocationProposalTests.self).url(
            forResource: "V23P04C24DictationLocationProposalCorpusV1",
            withExtension: "json",
            subdirectory: "Fixtures/V23/Assistance"
        ))
        return try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any])
    }
}

private actor C24CallCounter {
    private var count = 0
    func increment() { count += 1 }
    func value() -> Int { count }
}

private actor C24AccessGate: AppAccessGatePortV1 {
    func currentState() async -> AppAccessStateV1 { .disabled }
    func lock(reason: AppLockReasonV1) async {}
    func authenticate(trigger: LocalAuthenticationTriggerV1) async -> LocalAuthenticationOutcomeV1 {
        .unavailable
    }
    func requireContentAccess() async throws {}
}

@MainActor
private final class C24ScratchLifecycle: DictationAudioScratchLifecycleV1 {
    private(set) var prepareCount = 0
    private(set) var discardCount = 0
    private(set) var boundRequestID: UUID?
    func prepare(_ request: OnDeviceDictationRequestV1) async throws {
        try request.validate(); prepareCount += 1; boundRequestID = request.requestID
    }
    func discardAfterFailedDictation(_ request: OnDeviceDictationRequestV1) async throws {
        try request.validate()
        guard boundRequestID == request.requestID else { throw C24TestFailure.unavailable }
        discardCount += 1; boundRequestID = nil
    }
}

@MainActor
private final class C24AssistanceLifecycle: AssistanceProposalLifecycleV1 {
    private var proposals: [UUID: AssistanceProposalV1] = [:]
    private(set) var acceptCount = 0
    private(set) var scratchTransferCount = 0
    private(set) var scratchTerminalCount = 0
    private(set) var scratchOwnerProposalID: UUID?
    func obtainReviewSnapshot(for proposal: AssistanceProposalV1) async throws
        -> AssistanceProposalEvaluationContextV1 { try C32AssistanceTestSupport.context(proposal: proposal) }
    func present(_ proposal: AssistanceProposalV1,
                 context: AssistanceProposalEvaluationContextV1) async throws {
        try proposal.validate(); proposals[proposal.proposalID] = proposal
        if proposal.source.kind == .leasedScratch, scratchOwnerProposalID == nil {
            scratchOwnerProposalID = proposal.proposalID
        }
    }
    func replaceForReview(
        originalProposalID: UUID,
        with corrected: AssistanceProposalV1,
        context: AssistanceProposalEvaluationContextV1
    ) async throws {
        guard let original = proposals[originalProposalID],
              original.source == corrected.source,
              original.source.kind == .leasedScratch,
              scratchOwnerProposalID == originalProposalID else {
            throw C24TestFailure.unavailable
        }
        proposals.removeValue(forKey: originalProposalID)
        proposals[corrected.proposalID] = corrected
        scratchOwnerProposalID = corrected.proposalID
        scratchTransferCount += 1
    }
    func proposal(proposalID: UUID) async -> AssistanceProposalV1? { proposals[proposalID] }
    func activeProposals(workspaceID: WorkspaceID) async -> [AssistanceProposalV1] {
        proposals.values.filter { $0.target.workspaceID == workspaceID }
    }
    func review(proposalID: UUID, context: AssistanceProposalEvaluationContextV1) async throws
        -> AssistanceReviewDecisionV1 {
        guard let proposal = proposals[proposalID] else { throw C24TestFailure.unavailable }
        return .ready(proposal)
    }
    func accept(proposalID: UUID, targetMutation: AssistanceCanonicalTargetMutationV1,
                expectedRevision: WorkspaceExpectedRevisionV1, mutationID: MutationIDV1,
                acceptedBy: ActorSnapshotV1, acceptedAt: Date,
                context: AssistanceProposalEvaluationContextV1) async throws
        -> AssistanceAcceptanceReceiptV1 {
        guard let proposal = proposals[proposalID] else { throw C24TestFailure.unavailable }
        let fixture = C32AssistanceTestSupport.AcceptanceFixture(
            proposal: proposal,
            targetMutation: targetMutation,
            expectedRevision: expectedRevision,
            mutationID: mutationID,
            reviewer: acceptedBy,
            acceptedAt: acceptedAt
        )
        let receipt = try C24Support.receipt(proposal: proposal, acceptance: fixture)
        proposals.removeValue(forKey: proposalID); acceptCount += 1
        if proposal.source.kind == .leasedScratch {
            guard scratchOwnerProposalID == proposalID else { throw C24TestFailure.unavailable }
            scratchOwnerProposalID = nil
            scratchTerminalCount += 1
        }
        return receipt
    }
    func remove(proposalID: UUID, kind: AssistanceRemovalKindV1,
                expiryReason: AssistanceProposalExpiryReasonV1?) async throws
        -> AssistanceRemovalDispositionV1 {
        let proposal = proposals.removeValue(forKey: proposalID)
        if proposal?.source.kind == .leasedScratch {
            guard scratchOwnerProposalID == proposalID else { throw C24TestFailure.unavailable }
            scratchOwnerProposalID = nil
            scratchTerminalCount += 1
        }
        return try AssistanceRemovalDispositionV1(
            proposalID: proposalID,
            kind: kind,
            expiryReason: expiryReason
        )
    }
    func expireAll(contextByProposal: [UUID: AssistanceProposalEvaluationContextV1]) async throws
        -> [AssistanceExpiryDispositionV1] { [] }
    func recoverAfterInterruption() async throws {}
}

private func XCTAssertThrowsC24<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ handler: (Error) -> Void = { _ in }
) async {
    do { _ = try await expression(); XCTFail("Expected error", file: file, line: line) }
    catch { handler(error) }
}
