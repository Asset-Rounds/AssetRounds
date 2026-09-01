import CryptoKit
import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V9_98RecipientReviewWorkflowTests: XCTestCase {
    func testV23P04C35G01OfflineIsolatedDraftResponsePreviewAndExplicitAcceptAndApply() async throws {
        let corpus = try C35Corpus.load(); corpus.assertScenario("G01", kind: "GOLDEN")
        let h = try await C35Harness()
        let projection = try await h.workflow.projection(context: h.workflowContext)
        XCTAssertTrue(projection.hasReplayableManifest); XCTAssertTrue(projection.hasReplayablePackage)
        XCTAssertTrue(projection.canCreateResponse); XCTAssertFalse(projection.previewWrites)
        XCTAssertFalse(projection.recipientModeUsesNormalWorkspace)

        guard case let .requestReplay(replay) = try await h.workflow.execute(
            .replayClearRequest(kind: .package, userAcknowledgedCleartextWarning: true),
            context: h.workflowContext
        ) else { return XCTFail("Expected exact request replay") }
        XCTAssertEqual(replay.request.bytes, h.packageBytes)
        XCTAssertTrue(replay.isOffline); XCTAssertFalse(replay.entitlementRequired)
        XCTAssertTrue(replay.isIsolatedFromNormalWorkspaces)

        let response = try await h.createResponse()
        let before = try await h.store.statistics(for: .review)
        let preview = try await h.preview(response: response, decision: .acceptAndApply)
        XCTAssertTrue(preview.isZeroWrite); XCTAssertTrue(preview.requiresExplicitDecision)
        XCTAssertEqual(try await h.store.statistics(for: .review), before)
        let receipt = try await h.apply(preview: preview)
        XCTAssertEqual(receipt.mutationReceipt.mutationID, h.mutation.mutationID)
        XCTAssertEqual(try h.transitionRows().filter { $0.transitionID == h.appliedTransition.transitionID }.count, 1)
        let replayed = try await h.apply(preview: preview)
        XCTAssertEqual(replayed, receipt)
        XCTAssertEqual(try h.transitionRows().filter { $0.transitionID == h.appliedTransition.transitionID }.count, 1)
        #if DEBUG
        try await h.assertEncryptedRoundTrip()
        #endif
    }

    func testV23P04C35A01LegacyClearElsewhereHistoryAndDisabledEncryptionRemainExplicit() async throws {
        let corpus = try C35Corpus.load(); corpus.assertScenario("A01", kind: "ALTERNATE")
        let h = try await C35Harness()
        XCTAssertEqual(h.workflow.encryptionAvailability, .disabled)
        await XCTAssertThrowsErrorAsync(try await h.workflow.execute(
            .replayClearRequest(kind: .manifest, userAcknowledgedCleartextWarning: false),
            context: h.workflowContext
        )) { XCTAssertEqual($0 as? RecipientReviewWorkflowFailureV1, .cleartextWarningRequired) }
        guard case let .requestReplay(clear) = try await h.workflow.execute(
            .replayClearRequest(kind: .manifest, userAcknowledgedCleartextWarning: true),
            context: h.workflowContext
        ) else { return XCTFail("Expected legacy clear replay") }
        XCTAssertEqual(clear.protection, .legacyClearWithExplicitWarning)
        XCTAssertTrue(clear.protection.displaysCleartextWarning)

        let origin = try OriginRecordedReviewResponseV1(
            requestPublicID: h.requestID,
            responseBody: try ReviewResponseBodyV1(
                disposition: .acknowledged,
                author: try ResponseAuthorAssertionV1(
                    displayName: "Recipient named by recorder",
                    source: .originUserAssertionUnverified
                )
            ),
            sourceWording: "Recorder states that a response was received outside the app; identity and delivery are unverified.",
            recordedByActorID: C35Support.id(201), recordedAt: C35Support.date
        )
        guard case let .unverifiedHistoryRecorded(history) = try await h.workflow.execute(
            .recordResponseReceivedElsewhere(origin), context: h.workflowContext
        ) else { return XCTFail("Expected unverified history") }
        XCTAssertEqual(history.state, .historyOnlyTerminal)
        XCTAssertEqual(history.proofValidity, .unavailable)
        XCTAssertFalse(history.isVerifiedResponse); XCTAssertFalse(history.appliedToCanonicalWorkspace)
        XCTAssertEqual(try h.transitionRows().count, 2)
    }

    func testV23P04C35H01HostileMismatchDivergenceStalePreviewAndClaimsFailWithoutEffect() async throws {
        let corpus = try C35Corpus.load(); corpus.assertScenario("H01", kind: "HOSTILE")
        let h = try await C35Harness()
        let response = try await h.createResponse()
        let stalePreview = try await h.preview(response: response, decision: .acceptAndApply)
        _ = try await h.store.applyImport(response, decision: .recordAsHistoryOnly, capability: h.capability)
        let baselineStatistics = try await h.store.statistics(for: .review)
        let baselineSessions = try await h.store.sessions(in: .review)
        let baselineRows = try h.transitionRows()
        let wrongContext = try RecipientReviewWorkflowContextV1(
            requestPublicID: try .init("review-request-c35-wrong")
        )
        await XCTAssertThrowsErrorAsync(try await h.workflow.execute(
            .previewImport(try h.previewCommand(response: response, decision: .acceptAndApply)),
            context: wrongContext
        )) { XCTAssertEqual($0 as? PortableReviewFailureV1, .invalidValue) }
        try await h.assertNoHostileEffect(
            statistics: baselineStatistics, sessions: baselineSessions, transitions: baselineRows
        )

        let badProof = try ReviewCapabilityProofV1(rawBytes: C35Support.flipped(response.proof.rawBytes))
        let bad = try ReviewResponseEnvelopeV1(
            responsePublicID: "review-response-c35-bad-proof", requestPublicID: h.requestID,
            body: response.body, proof: badProof, canonicalBodyDigest: response.canonicalBodyDigest
        )
        let badRecord = try h.responseRecord(bad, assessment: .init(proofValidity: .invalid, applicationEligibility: .closed))
        let badPreview = try await h.workflow.previewImport(
            response: bad, capability: h.capability, responseRecord: badRecord,
            mapping: h.mapping, reviewID: h.fixture.reviewID, basisWorkspaceRevision: h.expected.workspaceRevision,
            decision: .keepQuarantined, mutationID: try C35Support.mutation(301)
        )
        XCTAssertEqual(badPreview.sessionPreview.disposition, .capabilityProofInvalid)
        try await h.assertNoHostileEffect(
            statistics: baselineStatistics, sessions: baselineSessions, transitions: baselineRows
        )
        XCTAssertThrowsError(try ResponseAuthorAssertionV1(displayName: "unsafe\nrecipient"))
        let wrongPassphrase = EncryptedEnvelopeErrorCategoryV1.externalFailure(
            for: EncryptedPortableEnvelopeFailureV1.invalidPassphrase
        )
        let damagedOrHostile = EncryptedEnvelopeErrorCategoryV1.externalFailure(
            for: EncryptedPortableEnvelopeFailureV1.hostileInnerPackage
        )
        XCTAssertEqual(wrongPassphrase, .wrongPassphraseOrDamagedEnvelope)
        XCTAssertEqual(damagedOrHostile, wrongPassphrase)
        try await h.assertNoHostileEffect(
            statistics: baselineStatistics, sessions: baselineSessions, transitions: baselineRows
        )
        #if DEBUG
        try await h.assertNeutralEncryptedTamperWithoutEffect()
        #endif
        try await h.assertNoHostileEffect(
            statistics: baselineStatistics, sessions: baselineSessions, transitions: baselineRows
        )

        let staleExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: h.expected.workspaceID, generationID: h.expected.generationID,
            writerInstanceID: h.expected.writerInstanceID,
            workspaceRevision: h.expected.workspaceRevision + 1,
            entityRevisions: h.expected.entityRevisions
        )
        await XCTAssertThrowsErrorAsync(try await h.workflow.acceptAndApply(
            preview: stalePreview, inspectionReviewMutation: h.mutation, expectedRevision: staleExpected
        )) { XCTAssertEqual($0 as? RecipientReviewWorkflowFailureV1, .previewDecisionMismatch) }
        try await h.assertNoHostileEffect(
            statistics: baselineStatistics, sessions: baselineSessions, transitions: baselineRows
        )

        let duplicate = try await h.store.previewImport(response, capability: h.capability)
        XCTAssertEqual(duplicate.disposition, .duplicateAlreadyApplied)
        try await h.assertNoHostileEffect(
            statistics: baselineStatistics, sessions: baselineSessions, transitions: baselineRows
        )
        let divergentBody = try ReviewResponseBodyV1(
            disposition: .changesRequested, changeItems: ["Recorded change requested"],
            author: try ResponseAuthorAssertionV1(displayName: "External reviewer")
        )
        let divergent = try h.workflow.createResponse(
            requestManifest: h.manifest, capability: h.capability,
            responsePublicID: response.responsePublicID, body: divergentBody
        )
        XCTAssertEqual(try await h.store.previewImport(divergent, capability: h.capability).disposition,
                       .divergentSameResponseID)
        try await h.assertNoHostileEffect(
            statistics: baselineStatistics, sessions: baselineSessions, transitions: baselineRows
        )
        XCTAssertFalse(RecipientReviewWorkflowClaimsV1.establishesIdentity)
        XCTAssertFalse(RecipientReviewWorkflowClaimsV1.establishesDelivery)
        XCTAssertFalse(RecipientReviewWorkflowClaimsV1.establishesRead)
        XCTAssertFalse(RecipientReviewWorkflowClaimsV1.establishesLegalEffect)
        XCTAssertFalse(RecipientReviewWorkflowClaimsV1.establishesSecurityApproval)
        corpus.assertExcludedCanaries()
    }

    func testV23P04C35I01InterruptionRecoveryProducesZeroOrOneEffectAndClearsSecrets() async throws {
        let corpus = try C35Corpus.load(); corpus.assertScenario("I01", kind: "INTERRUPTION")
        let h = try await C35Harness(failAfterEffectBeforeReceipt: true)
        let preview = try await h.preview(response: try await h.createResponse(), decision: .acceptAndApply)
        do {
            _ = try await h.apply(preview: preview)
            XCTFail("Injected effect-before-receipt interruption must surface")
        } catch {
            XCTAssertEqual(error as? MutationJournalFailureV1, .injected(.afterEffectBeforeReceipt))
        }
        XCTAssertLessThanOrEqual(try h.transitionRows().filter {
            $0.transitionID == h.appliedTransition.transitionID
        }.count, 1)
        _ = try await h.workflow.execute(.recoverAcceptAndApply(h.mutation.mutationID), context: h.workflowContext)
        let recovered = try await h.apply(preview: preview)
        XCTAssertEqual(recovered.mutationReceipt.mutationID, h.mutation.mutationID)
        XCTAssertEqual(try h.transitionRows().filter { $0.transitionID == h.appliedTransition.transitionID }.count, 1)

        let secret = try EphemeralPassphraseV1(openingPassphrase: "C35 interruption passphrase 🔐")
        XCTAssertGreaterThan(secret.withUnsafeBytes { $0.count }, 0)
        let disabled = try RecipientReviewWorkflowCoordinatorV1(
            sessions: h.store, canonicalReview: h.canonical, encryptionAvailability: .disabled
        )
        do {
            _ = try await disabled.openEncryptedReviewRequest(try h.unsupportedOpen(passphrase: secret))
            XCTFail("Disabled encryption must fail closed")
        } catch { XCTAssertEqual(error as? RecipientReviewWorkflowFailureV1, .encryptionDisabled) }
        XCTAssertEqual(secret.withUnsafeBytes { $0.count }, 0)
    }

    func testV23P04C35R01RelaunchReplayReexportReceiptAndDivergenceAreDeterministic() async throws {
        let corpus = try C35Corpus.load(); corpus.assertScenario("R01", kind: "RECOVERY")
        let h = try await C35Harness()
        let first = try await h.workflow.replayClearReviewRequest(
            publicRequestID: h.requestID, kind: .package, userAcknowledgedCleartextWarning: true
        )
        let relaunchedStore = try PortableExchangeSessionStoreV2(applicationSupportURL: h.root)
        let relaunched = try RecipientReviewWorkflowCoordinatorV1(
            sessions: relaunchedStore, canonicalReview: h.canonical, encryptionAvailability: .disabled
        )
        let second = try await relaunched.replayClearReviewRequest(
            publicRequestID: h.requestID, kind: .package, userAcknowledgedCleartextWarning: true
        )
        XCTAssertEqual(first, second); XCTAssertEqual(first.request.sha256, second.request.sha256)

        let response = try await h.createResponse()
        let preview = try await h.preview(response: response, decision: .acceptAndApply)
        let receipt = try await h.apply(preview: preview)
        _ = try await h.workflow.execute(.recoverAcceptAndApply(h.mutation.mutationID), context: h.workflowContext)
        XCTAssertEqual(try await h.apply(preview: preview), receipt)
        XCTAssertEqual(try h.transitionRows().filter { $0.transitionID == h.appliedTransition.transitionID }.count, 1)

        let changed = try h.workflow.createResponse(
            requestManifest: h.manifest, capability: h.capability,
            responsePublicID: response.responsePublicID,
            body: try ReviewResponseBodyV1(
                disposition: .changesRequested, changeItems: ["Different bytes under the same response ID"],
                author: try ResponseAuthorAssertionV1(displayName: "External reviewer")
            )
        )
        let divergentAssessment = ReviewProofAssessmentV1(
            proofValidity: .invalid, applicationEligibility: .closed
        )
        let divergentRecord = try h.responseRecord(changed, assessment: divergentAssessment)
        let quarantineMutationID = try C35Support.mutation(510)
        let divergentPreview = try await h.workflow.previewImport(
            response: changed, capability: h.capability, responseRecord: divergentRecord,
            mapping: h.mapping, reviewID: h.fixture.reviewID,
            basisWorkspaceRevision: receipt.mutationReceipt.resultingRevision.workspaceRevision,
            decision: .keepQuarantined, mutationID: quarantineMutationID
        )
        XCTAssertEqual(divergentPreview.sessionPreview.disposition, .divergentSameResponseID)
        let beforeQuarantine = try await h.store.statistics(for: .review)
        let beforeSessions = try await h.store.sessions(in: .review)
        let beforeTransitions = try h.transitionRows()
        XCTAssertNil(try h.portableReceipt(mutationID: quarantineMutationID))
        let quarantineReceipt = try ExternalReviewImportReceiptV1(
            workspaceID: h.fixture.workspaceID,
            basisWorkspaceRevision: divergentPreview.canonicalPlan.basisWorkspaceRevision,
            responseRecord: divergentRecord, decision: .keepQuarantined,
            mutationID: quarantineMutationID,
            effectDigest: Data(SHA256.hash(data: divergentRecord.canonicalResponse.canonicalBytes)),
            proofAssessment: divergentAssessment, resultingLifecycleState: .historyOnlyTerminal,
            appliedWorkspaceRevision: nil
        )
        guard case let .sessionFinalized(finalized) = try await h.workflow.execute(
            .finalizeSessionOnly(preview: divergentPreview, receipt: quarantineReceipt),
            context: h.workflowContext
        ) else { return XCTFail("Expected explicit session-only quarantine finalization") }
        XCTAssertEqual(finalized, quarantineReceipt)
        let afterQuarantine = try await h.store.statistics(for: .review)
        XCTAssertEqual(afterQuarantine.quarantineByteCount - beforeQuarantine.quarantineByteCount,
                       UInt64(divergentRecord.canonicalResponse.canonicalBytes.count))
        XCTAssertEqual(afterQuarantine.sessionCount, beforeQuarantine.sessionCount)
        XCTAssertEqual(afterQuarantine.immutableByteCount, beforeQuarantine.immutableByteCount)
        XCTAssertEqual(try await h.store.sessions(in: .review), beforeSessions)
        XCTAssertEqual(try h.transitionRows(), beforeTransitions)
        XCTAssertNil(try h.portableReceipt(mutationID: quarantineMutationID))
    }
}

private struct C35Corpus {
    let value: [String: Any]
    static func load() throws -> Self {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V23/ReviewExchange/V23P04C35RecipientReviewWorkflowCorpusV1.json")
        return .init(value: try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]))
    }
    func assertScenario(_ id: String, kind: String) {
        XCTAssertEqual(value["schema"] as? String, "V23P04C35RecipientReviewWorkflowCorpusV1")
        XCTAssertEqual((value["persistence"] as? [String: Any])?["persistentSchemaVersion"] as? Int, 36)
        XCTAssertEqual((value["persistence"] as? [String: Any])?["recordInventoryVersion"] as? Int, 35)
        XCTAssertEqual((value["persistence"] as? [String: Any])?["addsRecordFamily"] as? Bool, false)
        XCTAssertTrue((value["scenarios"] as? [[String: Any]])?.contains {
            $0["id"] as? String == id && $0["kind"] as? String == kind
        } == true)
    }
    func assertExcludedCanaries() {
        let exclusions = value["excludedFromStableExchange"] as? [String] ?? []
        XCTAssertTrue(["WorkspaceID", "raw originals", "internal notes", "contacts"].allSatisfy(exclusions.contains))
        let claims = value["forbiddenClaims"] as? [String] ?? []
        XCTAssertTrue(["sent", "delivered", "read", "secure", "legal acceptance"].allSatisfy(claims.contains))
    }
}

private enum C35Support {
    static let date = Date(timeIntervalSince1970: 2_320_000_000)
    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "35000000-0000-4000-8000-%012d", value))!
    }
    static func mutation(_ value: Int) throws -> MutationIDV1 { try .init(rawValue: id(value)) }
    static func flipped(_ data: Data) -> Data { var result = data; if !result.isEmpty { result[0] ^= 1 }; return result }
    static func allBytes(_ source: any EncryptedEnvelopeBoundedSeekableSourceV1) throws -> Data {
        let count = try source.encryptedEnvelopeByteCount()
        guard count <= UInt64(Int.max) else { throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded }
        return try source.readExactly(atOffset: 0, byteCount: Int(count))
    }
    struct Clock: ApplicationClock { func now() -> Date { date } }
    struct IDs: ApplicationIDSource { let value: UUID; func makeID() -> UUID { value } }
    struct Files: ApplicationFileAuthorityV1 {
        func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
            "mutation-staging/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
        }
    }
}

private final class C35Bytes: EncryptedEnvelopeProtectedScratchSinkV1,
    EncryptedPortableEnvelopePublishedSourceV1, @unchecked Sendable {
    let protectionClass = EncryptedEnvelopeProtectionClassV1.complete
    let isExcludedFromBackup = true
    var isIndependentFromProtectedScratch: Bool { true }
    private let lock = NSLock()
    private var bytes: Data
    private var expected: UInt64?
    init(_ bytes: Data = Data()) { self.bytes = bytes }
    func encryptedEnvelopeByteCount() throws -> UInt64 { lock.withLock { UInt64(bytes.count) } }
    func readExactly(atOffset: UInt64, byteCount: Int) throws -> Data {
        try lock.withLock {
            let start = Int(atOffset); guard start >= 0, byteCount >= 0, start + byteCount <= bytes.count else {
                throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
            }
            return Data(bytes[start..<(start + byteCount)])
        }
    }
    func prepareForStreamingWrite(expectedByteCount: UInt64) throws {
        lock.withLock { bytes.removeAll(); expected = expectedByteCount }
    }
    func appendStreamingBytes(_ value: Data) throws {
        try lock.withLock {
            guard let expected, UInt64(bytes.count + value.count) <= expected else {
                throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
            }
            bytes.append(value)
        }
    }
    func synchronizeStreamingWrite() throws {
        try lock.withLock {
            guard UInt64(bytes.count) == expected else { throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout }
        }
    }
    func discardStreamingBytes() throws { lock.withLock { bytes.removeAll(); expected = nil } }
    func data() -> Data { lock.withLock { bytes } }
}

#if DEBUG
private struct C35CryptoPort: EncryptedPortableEnvelopeCryptographicPortV1, @unchecked Sendable {
    let value = EncryptedPortableEnvelopeCryptoV1(testRandomBytes: { Data(repeating: UInt8($0), count: $0) })
    func structuralPreflight(source: any EncryptedEnvelopeBoundedSeekableSourceV1,
                             limits: EncryptedPortableEnvelopeResourceLimitsV1,
                             cancellation: any EncryptedEnvelopeCancellationCheckingV1) throws -> EncryptedEnvelopeStructuralPreflightReceiptV1 {
        try value.structuralPreflight(source: source, limits: limits, cancellation: cancellation)
    }
    func sealStreaming(innerSource: any EncryptedEnvelopeBoundedSeekableSourceV1,
                       innerKind: EncryptedPortableEnvelopeInnerKindV1,
                       innerProtocolVersion: EncryptedPortableEnvelopeInnerProtocolVersionV1,
                       reviewProtectionMode: ReviewExchangeProtectionV1?, passphrase: EphemeralPassphraseV1,
                       context: EncryptedEnvelopeOperationReceiptContextV1,
                       limits: EncryptedPortableEnvelopeResourceLimitsV1,
                       envelopeScratch: any EncryptedEnvelopeProtectedScratchSinkV1,
                       reopenPlaintextScratch: any EncryptedEnvelopeProtectedScratchSinkV1,
                       validateSourceInner: EncryptedEnvelopeStreamingInnerValidatorV1,
                       validateReopenedInner: EncryptedEnvelopeStreamingInnerValidatorV1,
                       cancellation: any EncryptedEnvelopeCancellationCheckingV1) throws -> EncryptedPortableEnvelopeStreamingSealResultV1 {
        try value.sealStreaming(innerSource: innerSource, innerKind: innerKind,
            innerProtocolVersion: innerProtocolVersion, reviewProtectionMode: reviewProtectionMode,
            passphrase: passphrase, context: context, limits: limits, envelopeScratch: envelopeScratch,
            reopenPlaintextScratch: reopenPlaintextScratch, validateSourceInner: validateSourceInner,
            validateReopenedInner: validateReopenedInner, cancellation: cancellation)
    }
    func openStreaming(envelopeSource: any EncryptedEnvelopeBoundedSeekableSourceV1,
                       passphrase: EphemeralPassphraseV1, context: EncryptedEnvelopeOperationReceiptContextV1,
                       limits: EncryptedPortableEnvelopeResourceLimitsV1,
                       plaintextScratch: any EncryptedEnvelopeProtectedScratchSinkV1,
                       validateInner: EncryptedEnvelopeStreamingInnerValidatorV1,
                       cancellation: any EncryptedEnvelopeCancellationCheckingV1) throws -> EncryptedPortableEnvelopeStreamingOpenResultV1 {
        try value.openStreaming(envelopeSource: envelopeSource, passphrase: passphrase, context: context,
            limits: limits, plaintextScratch: plaintextScratch, validateInner: validateInner,
            cancellation: cancellation)
    }
}

private actor C35CryptoLifecycle: EncryptedPortableEnvelopeAttemptLifecycleV1 {
    private struct State { let secret: EphemeralPassphraseV1; let token: EncryptedPortableEnvelopeCancellationTokenV1
        var envelope: C35Bytes?; var reopen: C35Bytes?; var plaintext: C35Bytes? }
    private var states: [EncryptedPortableEnvelopeOperationIdentityV1: State] = [:]
    func claimSecret(operation: EncryptedPortableEnvelopeOperationIdentityV1,
                     secret: EphemeralPassphraseV1) async throws -> EncryptedPortableEnvelopeCancellationTokenV1 {
        if let state = states[operation] { return state.token }
        let token = EncryptedPortableEnvelopeCancellationTokenV1()
        states[operation] = .init(secret: secret, token: token, envelope: nil, reopen: nil, plaintext: nil)
        return token
    }
    func prepareSeal(operation: EncryptedPortableEnvelopeOperationIdentityV1,
                     topology: EncryptedPortableEnvelopeTopologyV1) async throws -> EncryptedPortableEnvelopeSealResourcesV1 {
        guard var state = states[operation] else { throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader }
        state.envelope = C35Bytes(); state.reopen = C35Bytes(); states[operation] = state; _ = topology
        return .init(operation: operation, envelopeScratch: state.envelope!,
                     reopenPlaintextScratch: state.reopen!, cancellation: state.token)
    }
    func prepareOpen(operation: EncryptedPortableEnvelopeOperationIdentityV1,
                     preflight: EncryptedEnvelopeStructuralPreflightReceiptV1) async throws -> EncryptedPortableEnvelopeOpenResourcesV1 {
        guard var state = states[operation] else { throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader }
        state.plaintext = C35Bytes(); states[operation] = state; _ = preflight
        return .init(operation: operation, plaintextScratch: state.plaintext!, cancellation: state.token)
    }
    func publishAndCleanupSeal(resources: EncryptedPortableEnvelopeSealResourcesV1,
                               facts: EncryptedEnvelopeSealCryptographicFactsV1) async throws -> EncryptedPortableEnvelopeFinalizedSealV1 {
        guard let state = states.removeValue(forKey: resources.operation), let envelope = state.envelope,
              facts.reopenedAndAuthenticated else { throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader }
        if !states.values.contains(where: { $0.secret === state.secret }) { state.secret.clear() }
        return .init(source: C35Bytes(envelope.data()), receipt: try .init(finalizing: facts))
    }
    func cleanupOpen(resources: EncryptedPortableEnvelopeOpenResourcesV1,
                     facts: EncryptedEnvelopeOpenCryptographicFactsV1) async throws {
        guard let state = states.removeValue(forKey: resources.operation), facts.outerAuthenticationComplete else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        if !states.values.contains(where: { $0.secret === state.secret }) { state.secret.clear() }
        try state.plaintext?.discardStreamingBytes()
    }
    func completeOpenFinalization(operation: EncryptedPortableEnvelopeOperationIdentityV1,
                                  cancellation: EncryptedPortableEnvelopeCancellationTokenV1) async throws { _ = (operation, cancellation) }
    func abandonOpenFinalization(operation: EncryptedPortableEnvelopeOperationIdentityV1) async { _ = operation }
    func abort(operation: EncryptedPortableEnvelopeOperationIdentityV1) async throws {
        guard let state = states.removeValue(forKey: operation) else { return }; state.secret.clear()
    }
}

private final class C35InnerTransaction: EncryptedPortableEnvelopeAuthenticatedInnerTransactionV1, @unchecked Sendable {
    func commit() async throws {}
    func rollback() async {}
}
private struct C35InnerConsumer: EncryptedPortableEnvelopeAuthenticatedInnerConsumerV1 {
    func stageAuthenticatedInner(source: any EncryptedEnvelopeBoundedSeekableSourceV1,
                                 kind: EncryptedPortableEnvelopeInnerKindV1,
                                 version: EncryptedPortableEnvelopeInnerProtocolVersionV1) async throws -> any EncryptedPortableEnvelopeAuthenticatedInnerTransactionV1 {
        guard try source.encryptedEnvelopeByteCount() > 0 else { throw EncryptedPortableEnvelopeFailureV1.hostileInnerPackage }
        try version.validateReleased(for: kind); return C35InnerTransaction()
    }
}
private struct C35LegacyReader: EncryptedPortableEnvelopeLegacyClearReaderV1 {
    func readLegacyClear(source: any EncryptedEnvelopeBoundedSeekableSourceV1,
                         kind: EncryptedPortableEnvelopeInnerKindV1,
                         version: EncryptedPortableEnvelopeInnerProtocolVersionV1) throws {
        guard try source.encryptedEnvelopeByteCount() > 0 else { throw EncryptedPortableEnvelopeFailureV1.hostileInnerPackage }
        try version.validateReleased(for: kind)
    }
}
#endif

@MainActor
private final class C35Harness {
    let root: URL
    let store: PortableExchangeSessionStoreV2
    let canonical: PortableReviewCoordinatorV1
    let workflow: RecipientReviewWorkflowCoordinatorV1
    let fixture: C14InspectionReviewTestSupportV1.Fixture
    let requestID: ReviewRequestPublicIDV1
    let manifest: ReviewRequestManifestV1
    let capability: BearerResponseCapabilityV1
    let workflowContext: RecipientReviewWorkflowContextV1
    let mapping: ReviewRequestC14SubjectItemMappingV1
    let mutation: InspectionReviewMutationV1
    let appliedTransition: InspectionReviewTransitionV1
    let expected: WorkspaceExpectedRevisionV1
    let packageBytes = Data("C35 customer-safe package; no private notes, contacts, paths, or originals.".utf8)
    private let modelContext: ModelContext
    private let writer: WorkspaceWriterV1

    init(failAfterEffectBeforeReceipt: Bool = false) async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("V9_98-C35-\(UUID().uuidString)", isDirectory: true)
        store = try PortableExchangeSessionStoreV2(applicationSupportURL: root, clock: C35Support.Clock(), idSource: C35Support.IDs(value: C35Support.id(1)))
        fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 350_000)
        requestID = try .init("review-request-c35-0001")
        capability = try BearerResponseCapabilityV1(rawBytes: Data((0..<32).map { UInt8($0) }))
        let manifestBytes = Data("C35 request manifest".utf8)
        let release = try PortableReviewProtocolReleaseV1(
            releaseID: "portable-review-v1", releaseDigest: Data((32..<64).map { UInt8($0) })
        )
        manifest = try ReviewRequestManifestV1(
            requestPublicID: requestID, protocolRelease: release,
            requestManifestDigest: Data(SHA256.hash(data: manifestBytes)),
            innerRequestPackageDigest: Data(SHA256.hash(data: packageBytes))
        )
        let sessionID = C35Support.id(2)
        _ = try await store.stage(
            sessionID: sessionID, publicRequestID: requestID.rawValue,
            workspaceID: fixture.workspaceID.rawValue,
            canonicalReviewIdentity: fixture.reviewID.uuidString.lowercased(),
            canonicalSubjectIdentity: fixture.subject.subjectID,
            protocolReleaseDigest: release.releaseDigest,
            requestManifestBytes: manifestBytes, requestPackageBytes: packageBytes,
            capability: capability
        )
        _ = try await store.markExported(id: sessionID)

        let schema = Schema(PersistentSchemaV36.models, version: PersistentSchemaV36.versionIdentifier)
        let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [
            ModelConfiguration("C35Writer", schema: schema, isStoredInMemoryOnly: true, allowsSave: true, cloudKitDatabase: .none)
        ])
        modelContext = container.mainContext; modelContext.autosaveEnabled = false
        modelContext.insert(try ActorSnapshotRow(fixture.recorder)); modelContext.insert(try ActorSnapshotRow(fixture.reviewer))
        try modelContext.save()
        let replica = try WorkspaceReplicaIdentityV1(workspaceID: fixture.workspaceID, replicaID: .init(rawValue: C35Support.id(3)))
        let generation = C35Support.id(4), writerID = C35Support.id(5)
        let seedJournal = try MutationJournalStoreV1(
            modelContext: modelContext, identity: replica, generationID: generation
        )
        let seedWriter = try WorkspaceWriterV1(
            identity: replica, generationID: generation,
            initialRevision: seedJournal.currentRevision(writerInstanceID: writerID),
            clock: C35Support.Clock(), idSource: C35Support.IDs(value: writerID),
            fileAuthority: C35Support.Files(), adapter: WorkspaceWriterAdapterV1(modelContext: modelContext),
            journalStore: seedJournal
        )
        for (index, transition) in fixture.transitions.prefix(2).enumerated() {
            let seedMutation = try InspectionReviewMutationV1(
                workspaceID: fixture.workspaceID, expectedRevision: UInt64(index),
                mutationID: transition.mutationID,
                postImage: .applyReviewBundle(try .init(transition: transition))
            )
            _ = try seedWriter.execute(.applyInspectionReview(seedMutation), mutationID: transition.mutationID)
        }
        if failAfterEffectBeforeReceipt {
            let faultedJournal = try MutationJournalStoreV1(
                modelContext: modelContext, identity: replica, generationID: generation,
                failureInjection: .init(failOnceAt: .afterEffectBeforeReceipt)
            )
            writer = try WorkspaceWriterV1(
                identity: replica, generationID: generation,
                initialRevision: faultedJournal.currentRevision(writerInstanceID: writerID),
                clock: C35Support.Clock(), idSource: C35Support.IDs(value: writerID),
                fileAuthority: C35Support.Files(), adapter: WorkspaceWriterAdapterV1(modelContext: modelContext),
                journalStore: faultedJournal
            )
        } else {
            writer = seedWriter
        }
        let lifecycle = InspectionReviewLifecycleAdapterV1(modelContext: modelContext)
        canonical = PortableReviewCoordinatorV1(writer: writer, sessions: store, reviewLifecycle: lifecycle)
        workflow = try RecipientReviewWorkflowCoordinatorV1(sessions: store, canonicalReview: canonical)
        workflowContext = try .init(requestPublicID: requestID, sessionID: sessionID, requestManifest: manifest)
        mapping = try .init(workspaceID: fixture.workspaceID, requestPublicID: requestID, subject: fixture.subject, items: [])

        let dispositionID = C35Support.id(11)
        appliedTransition = try C14InspectionReviewTestSupportV1.makeTransition(
            seed: 350_010, reviewID: fixture.reviewID, workspaceID: fixture.workspaceID,
            subject: fixture.subject, from: .readyForReview, to: .accepted, actor: fixture.reviewer,
            revision: 3, mutationSeed: 10, predecessor: fixture.transitions[1].transitionID,
            dispositionID: dispositionID
        )
        let disposition = try ReviewDispositionV1(
            dispositionID: dispositionID, reviewID: fixture.reviewID, workspaceID: fixture.workspaceID,
            subject: fixture.subject, reviewRevision: 3, kind: .accepted, reviewer: fixture.reviewer,
            reason: "External response was explicitly accepted and applied as recorded review truth.",
            recordedAt: C35Support.date, mutationID: appliedTransition.mutationID
        )
        mutation = try .init(
            workspaceID: fixture.workspaceID, expectedRevision: 2, mutationID: appliedTransition.mutationID,
            postImage: .applyReviewBundle(try .init(transition: appliedTransition, disposition: disposition))
        )
        let current = try writer.currentRevision()
        expected = try .init(
            workspaceID: current.workspaceID, generationID: current.generationID,
            writerInstanceID: current.writerInstanceID, workspaceRevision: current.revision,
            entityRevisions: try mutation.concurrencyIdentities.map {
                try .init(identity: $0, revision: $0.kind == .inspectionReviewTransition ? 2 : 0)
            }
        )
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func createResponse() async throws -> ReviewResponseEnvelopeV1 {
        guard case let .responseCreated(response) = try await workflow.execute(
            .createResponse(
                capability: capability, responsePublicID: "review-response-c35-0001",
                body: try ReviewResponseBodyV1(
                    disposition: .approved,
                    author: try ResponseAuthorAssertionV1(displayName: "External reviewer")
                )
            ), context: workflowContext
        ) else { throw RecipientReviewWorkflowFailureV1.requestUnavailable }
        return response
    }

    func responseRecord(_ response: ReviewResponseEnvelopeV1,
                        assessment: ReviewProofAssessmentV1 = .init(proofValidity: .valid, applicationEligibility: .eligible)) throws -> ExternalReviewResponseRecordV1 {
        try .init(recordID: C35Support.id(12), workspaceID: fixture.workspaceID,
                  requestManifest: manifest, canonicalResponse: .init(response: response),
                  source: .portableFile, proofAssessment: assessment, recordedAt: C35Support.date)
    }

    func previewCommand(response: ReviewResponseEnvelopeV1,
                        decision: ExternalReviewImportDecisionV1) throws -> RecipientReviewPreviewImportCommandV1 {
        .init(response: response, capability: capability, responseRecord: try responseRecord(response),
              mapping: mapping, reviewID: fixture.reviewID, basisWorkspaceRevision: expected.workspaceRevision,
              decision: decision, mutationID: mutation.mutationID)
    }

    func preview(response: ReviewResponseEnvelopeV1,
                 decision: ExternalReviewImportDecisionV1) async throws -> RecipientReviewImportPreviewV1 {
        guard case let .importPreview(value) = try await workflow.execute(
            .previewImport(try previewCommand(response: response, decision: decision)), context: workflowContext
        ) else { throw RecipientReviewWorkflowFailureV1.requestUnavailable }
        return value
    }

    func apply(preview: RecipientReviewImportPreviewV1) async throws -> PortableReviewMutationReceiptV1 {
        guard case let .canonicalApplied(value) = try await workflow.execute(
            .acceptAndApply(preview: preview, mutation: mutation, expectedRevision: expected), context: workflowContext
        ) else { throw RecipientReviewWorkflowFailureV1.previewDecisionMismatch }
        return value
    }

    func transitionRows() throws -> [InspectionReviewTransitionV1] {
        try modelContext.fetch(FetchDescriptor<InspectionReviewTransitionRow>()).map { try $0.value() }
    }

    func portableReceipt(mutationID: MutationIDV1) throws -> PortableReviewMutationReceiptV1? {
        try writer.portableReviewReceipt(mutationID: mutationID)
    }

    func assertNoHostileEffect(
        statistics: PortableExchangeSessionStoreStatisticsV2,
        sessions: [PortableExchangeSessionRecordV2],
        transitions: [InspectionReviewTransitionV1],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        XCTAssertEqual(try await store.statistics(for: .review), statistics, file: file, line: line)
        XCTAssertEqual(try await store.sessions(in: .review), sessions, file: file, line: line)
        XCTAssertEqual(try transitionRows(), transitions, file: file, line: line)
    }

    #if DEBUG
    func assertEncryptedRoundTrip() async throws {
        let version = try EncryptedPortableEnvelopeInnerProtocolVersionV1(1)
        let (coordinator, encryptedWorkflow) = try encryptedPair(version: version)
        XCTAssertEqual(try await encryptedWorkflow.readLegacyClear(
            source: C35Bytes(packageBytes), kind: .reviewRequest,
            userAcknowledgedCleartextWarning: true
        ), .legacyClearWithExplicitWarning)
        let requestSecret = try EphemeralPassphraseV1(
            passphrase: "C35 encrypted review passphrase 🔐",
            confirmation: "C35 encrypted review passphrase 🔐"
        )
        let requestOperation = try encryptedOperation(401)
        let sealedRequest = try await coordinator.seal(.init(
            operation: requestOperation, source: C35Bytes(packageBytes), innerKind: .reviewRequest,
            innerProtocolVersion: version, reviewProtectionMode: .passphraseEncryptedV1,
            passphrase: requestSecret, receiptContext: try encryptedContext(requestOperation),
            limits: .released, executionMode: .new
        ))
        let requestSource = try XCTUnwrap(sealedRequest.source)
        XCTAssertEqual(requestSecret.withUnsafeBytes { $0.count }, 0)
        let openSecret = try EphemeralPassphraseV1(openingPassphrase: "C35 encrypted review passphrase 🔐")
        let openOperation = try encryptedOperation(402)
        let opened = try await encryptedWorkflow.openEncryptedReviewRequest(.init(
            operation: openOperation, source: requestSource, passphrase: openSecret,
            receiptContext: try encryptedContext(openOperation), limits: .released, executionMode: .new
        ))
        XCTAssertEqual(opened.effect, .completed)
        XCTAssertEqual(opened.receipt?.innerKind, .reviewRequest)
        XCTAssertEqual(openSecret.withUnsafeBytes { $0.count }, 0)

        let sharedProtectSecret = try EphemeralPassphraseV1(
            passphrase: "C35 encrypted review passphrase 🔐",
            confirmation: "C35 encrypted review passphrase 🔐"
        )
        let protectOpenOperation = try encryptedOperation(405)
        let protectSealOperation = try encryptedOperation(406)
        let protectedResponse = try await encryptedWorkflow.protectEncryptedReviewResponse(
            opening: .init(
                operation: protectOpenOperation, source: requestSource, passphrase: sharedProtectSecret,
                receiptContext: try encryptedContext(protectOpenOperation), limits: .released, executionMode: .new
            ),
            sealing: .init(
                operation: protectSealOperation,
                source: C35Bytes(Data("C35 protected response using the request passphrase".utf8)),
                innerKind: .reviewResponse, innerProtocolVersion: version,
                reviewProtectionMode: .passphraseEncryptedV1, passphrase: sharedProtectSecret,
                receiptContext: try encryptedContext(protectSealOperation), limits: .released, executionMode: .new
            )
        )
        XCTAssertEqual(protectedResponse.effect, .completed)
        XCTAssertEqual(protectedResponse.receipt?.innerKind, .reviewResponse)
        XCTAssertEqual(sharedProtectSecret.withUnsafeBytes { $0.count }, 0)

        let responseSecret = try EphemeralPassphraseV1(
            passphrase: "C35 encrypted response passphrase 🔐",
            confirmation: "C35 encrypted response passphrase 🔐"
        )
        let responseOperation = try encryptedOperation(403)
        let sealedResponse = try await encryptedWorkflow.sealEncryptedReviewResponse(.init(
            operation: responseOperation, source: C35Bytes(Data("C35 canonical review response".utf8)),
            innerKind: .reviewResponse, innerProtocolVersion: version,
            reviewProtectionMode: .passphraseEncryptedV1, passphrase: responseSecret,
            receiptContext: try encryptedContext(responseOperation), limits: .released, executionMode: .new
        ))
        XCTAssertEqual(sealedResponse.effect, .completed)
        XCTAssertEqual(sealedResponse.receipt?.innerKind, .reviewResponse)
        XCTAssertEqual(responseSecret.withUnsafeBytes { $0.count }, 0)
        let responseOpenSecret = try EphemeralPassphraseV1(openingPassphrase: "C35 encrypted response passphrase 🔐")
        let responseOpenOperation = try encryptedOperation(404)
        let openedResponse = try await coordinator.open(.init(
            operation: responseOpenOperation, source: try XCTUnwrap(sealedResponse.source),
            passphrase: responseOpenSecret, receiptContext: try encryptedContext(responseOpenOperation),
            limits: .released, executionMode: .new
        ))
        XCTAssertEqual(openedResponse.effect, .completed)
        XCTAssertEqual(openedResponse.receipt?.innerKind, .reviewResponse)
        XCTAssertEqual(responseOpenSecret.withUnsafeBytes { $0.count }, 0)
        XCTAssertEqual(encryptedWorkflow.encryptionAvailability, .manualPassphraseAvailable)
    }

    func assertNeutralEncryptedTamperWithoutEffect() async throws {
        let version = try EncryptedPortableEnvelopeInnerProtocolVersionV1(1)
        let (coordinator, encryptedWorkflow) = try encryptedPair(version: version)
        let sealSecret = try EphemeralPassphraseV1(
            passphrase: "C35 hostile envelope passphrase 🔐",
            confirmation: "C35 hostile envelope passphrase 🔐"
        )
        let sealOperation = try encryptedOperation(420)
        let sealed = try await coordinator.seal(.init(
            operation: sealOperation, source: C35Bytes(packageBytes), innerKind: .reviewRequest,
            innerProtocolVersion: version, reviewProtectionMode: .passphraseEncryptedV1,
            passphrase: sealSecret, receiptContext: try encryptedContext(sealOperation),
            limits: .released, executionMode: .new
        ))
        let validSource = try XCTUnwrap(sealed.source)
        let beforeStatistics = try await store.statistics(for: .review)
        let beforeTransitions = try transitionRows()

        let wrongSecret = try EphemeralPassphraseV1(openingPassphrase: "C35 wrong hostile passphrase 🔐")
        let wrongOperation = try encryptedOperation(421)
        var wrongError: Error?
        do {
            _ = try await encryptedWorkflow.openEncryptedReviewRequest(.init(
                operation: wrongOperation, source: validSource, passphrase: wrongSecret,
                receiptContext: try encryptedContext(wrongOperation), limits: .released, executionMode: .new
            ))
            XCTFail("Wrong passphrase must fail closed")
        } catch { wrongError = error }

        var tamperedBytes = try C35Support.allBytes(validSource)
        tamperedBytes[tamperedBytes.index(before: tamperedBytes.endIndex)] ^= 0x01
        let tamperedSecret = try EphemeralPassphraseV1(openingPassphrase: "C35 hostile envelope passphrase 🔐")
        let tamperedOperation = try encryptedOperation(422)
        var tamperedError: Error?
        do {
            _ = try await encryptedWorkflow.openEncryptedReviewRequest(.init(
                operation: tamperedOperation, source: C35Bytes(tamperedBytes), passphrase: tamperedSecret,
                receiptContext: try encryptedContext(tamperedOperation), limits: .released, executionMode: .new
            ))
            XCTFail("Authenticated-envelope byte tampering must fail closed")
        } catch { tamperedError = error }

        XCTAssertEqual(wrongError as? EncryptedPortableEnvelopeExternalFailureV1,
                       .wrongPassphraseOrDamagedEnvelope)
        XCTAssertEqual(tamperedError as? EncryptedPortableEnvelopeExternalFailureV1,
                       wrongError as? EncryptedPortableEnvelopeExternalFailureV1)
        XCTAssertEqual(wrongSecret.withUnsafeBytes { $0.count }, 0)
        XCTAssertEqual(tamperedSecret.withUnsafeBytes { $0.count }, 0)
        XCTAssertEqual(try await store.statistics(for: .review), beforeStatistics)
        XCTAssertEqual(try transitionRows(), beforeTransitions)
    }

    private func encryptedPair(version: EncryptedPortableEnvelopeInnerProtocolVersionV1) throws
        -> (EncryptedPortableEnvelopeCoordinatorV1, RecipientReviewWorkflowCoordinatorV1) {
        let validator: EncryptedEnvelopeStreamingInnerValidatorV1 = { source, kind, actualVersion in
            guard try source.encryptedEnvelopeByteCount() > 0,
                  actualVersion == .released(for: kind) else {
                throw EncryptedPortableEnvelopeFailureV1.hostileInnerPackage
            }
        }
        let coordinator = EncryptedPortableEnvelopeCoordinatorV1(
            crypto: C35CryptoPort(), lifecycle: C35CryptoLifecycle(),
            innerDispatch: .init(
                workspaceBackup: .init(version: version, validate: validator),
                reviewRequest: .init(version: version, validate: validator),
                reviewResponse: .init(version: version, validate: validator)
            ), innerConsumer: C35InnerConsumer(), legacyClearReader: C35LegacyReader()
        )
        let encryptedWorkflow = try RecipientReviewWorkflowCoordinatorV1(
            sessions: store, canonicalReview: canonical, encryptedEnvelope: coordinator,
            encryptionAvailability: .manualPassphraseAvailable
        )
        return (coordinator, encryptedWorkflow)
    }

    private func encryptedOperation(_ slot: Int) throws -> EncryptedPortableEnvelopeOperationIdentityV1 {
        try .init(workspaceID: fixture.workspaceID, attemptID: C35Support.id(slot),
                  mutationID: C35Support.mutation(slot), createdAt: C35Support.date,
                  expiresAt: C35Support.date.addingTimeInterval(300))
    }
    private func encryptedContext(_ operation: EncryptedPortableEnvelopeOperationIdentityV1) throws
        -> EncryptedEnvelopeOperationReceiptContextV1 {
        try .init(operationID: operation.mutationID.rawValue, attemptID: operation.attemptID,
                  candidateHead: String(repeating: "c", count: 40),
                  candidateTree: String(repeating: "d", count: 40),
                  toolchainIdentifier: "V9_98 deterministic C35 encryption probe")
    }
    #endif

    func unsupportedOpen(passphrase: EphemeralPassphraseV1) throws -> EncryptedPortableEnvelopeOpenRequestV1 {
        let operation = try EncryptedPortableEnvelopeOperationIdentityV1(
            workspaceID: fixture.workspaceID, attemptID: C35Support.id(90), mutationID: try C35Support.mutation(90),
            createdAt: C35Support.date, expiresAt: C35Support.date.addingTimeInterval(300)
        )
        return .init(operation: operation, source: C35Bytes(Data(repeating: 0, count: 8)), passphrase: passphrase,
                     receiptContext: try .init(
                        operationID: operation.mutationID.rawValue, attemptID: operation.attemptID,
                        candidateHead: String(repeating: "a", count: 40),
                        candidateTree: String(repeating: "b", count: 40),
                        toolchainIdentifier: "V9_98 static encrypted-boundary fixture"
                     ),
                     limits: .released, executionMode: .new)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void = { _ in }
) async {
    do { _ = try await expression(); XCTFail("Expected error") } catch { handler(error) }
}
