import XCTest
import SwiftData
@testable import FieldEvidenceApp

private enum C40 {
    static let date = Date(timeIntervalSince1970: 1_735_689_600)
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "40000000-0000-4000-8000-%012d", n))! }
    static func mutation(_ n: Int) throws -> MutationIDV1 { try MutationIDV1(rawValue: id(n)) }
    static func digest(_ c: Character) -> String { String(repeating: String(c), count: 64) }
    static func scope() throws -> ServiceRequestScopeSnapshotV1 {
        try .init(siteID: id(1), siteExpectedRevision: 1, siteSemanticSHA256: digest("a"), assets: [
            .init(assetID: id(2), expectedRevision: 1, semanticSHA256: digest("b"))
        ])
    }
    static func body(_ text: String = "Door closer needs adjustment") throws -> ServiceRequestSubmissionBodyV1 {
        try .init(requestText: text, urgency: .routine,
                  requester: .init(displayName: "Synthetic requester"),
                  contact: .init(value: "test@example.invalid"), category: "hardware")
    }
    static func intake(_ source: ServiceRequestSourceKindV1 = .phone) throws -> ServiceRequestManualIntakeV1 {
        try .init(source: source, scope: scope(), body: body(), mediaManifest: .init(entries: []))
    }
    static func portable() throws -> (PortableServiceRequestProtocolReleaseV1,
        PortableServiceRequestInvitationV1, PortableServiceRequestSubmissionV1,
        CanonicalServiceRequestSourceBytesV1) {
        let release = try PortableServiceRequestProtocolReleaseV1(budget: .init(
            maximumScopedAssets: 2, maximumMediaItems: 2, maximumSingleMediaBytes: 1_024,
            maximumTotalMediaBytes: 2_048, maximumSubmissionBytes: 8_192,
            maximumDuplicateCandidates: 4))
        let manifest = try ServiceRequestInvitationManifestV1(protocolRelease: release,
            invitationPublicID: .init("INV-C40-GOLDEN-001"), scope: scope())
        let capability = try ServiceRequestSubmissionCapabilityV1(
            rawBytes: Data((0..<32).map(UInt8.init))
        )
        let invitation = try PortableServiceRequestInvitationV1(manifest: manifest, capability: capability)
        let body = try body("Portable door closer request")
        let media = try ServiceRequestMediaManifestV1(entries: [])
        let submissionID = try ServiceRequestSubmissionPublicIDV1("SUB-C40-GOLDEN-001")
        func bytes(_ hex: String) -> Data {
            Data(stride(from: 0, to: hex.count, by: 2).map { offset in
                let start = hex.index(hex.startIndex, offsetBy: offset)
                let end = hex.index(start, offsetBy: 2)
                return UInt8(hex[start..<end], radix: 16)!
            })
        }
        let proof = try ServiceRequestCapabilityProofCodecV1.makeProof(capability: capability,
            input: .init(protocolReleaseDigest: bytes(release.releaseSHA256),
                invitationPublicID: manifest.invitationPublicID,
                invitationManifestDigest: bytes(manifest.manifestSHA256),
                frozenScopeSnapshotDigest: bytes(manifest.scope.scopeSHA256),
                submissionPublicID: submissionID,
                canonicalSubmissionBodyDigest: bytes(try ServiceRequestCanonicalCodecV1.sha256(body)),
                mediaManifestDigest: bytes(media.manifestSHA256)))
        let submission = try PortableServiceRequestSubmissionV1(
            protocolReleaseSHA256: release.releaseSHA256, invitationManifest: manifest,
            submissionPublicID: submissionID, body: body, mediaManifest: media, proof: proof)
        return (release, invitation, submission,
                try CanonicalServiceRequestSourceBytesV1(ServiceRequestCanonicalCodecV1.data(submission)))
    }
    static func checkpoint(workspaceID: WorkspaceID, draftID: UUID,
                           manifest: ServiceRequestInvitationManifestV1) throws -> FieldDraftCheckpointV1 {
        try .init(draftID: draftID, workspaceID: workspaceID,
            scope: .init(scopeKind: "SERVICE_REQUEST", stableComponentIDs: [manifest.invitationPublicID.rawValue]),
            purpose: .serviceRequest,
            codec: .init(codecID: "C40_SERVICE_REQUEST_MANIFEST", codecVersion: 1,
                         releaseSHA256: digest("7")),
            baseCanonicalRevision: 0, draftRevision: 1,
            payloadData: ServiceRequestCanonicalCodecV1.data(manifest), stageIDs: [],
            resumeAnchor: .init(sectionID: "request"), state: .active,
            updatedAt: date, mutationID: mutation(70))
    }
}

private struct C40Clock: ApplicationClock { func now() -> Date { C40.date } }
private final class C40IDs: ApplicationIDSource, @unchecked Sendable {
    private var next = 100
    func makeID() -> UUID { defer { next += 1 }; return C40.id(next) }
}
@MainActor private final class C40ManualDuplicates: ServiceRequestManualDuplicateProjectingV1 {
    var candidate: ServiceRequestRevisionReferenceV1?
    func projectCandidates(workspaceID: WorkspaceID, record: ServiceRequestRecordV1) throws -> ServiceRequestDuplicateProjectionV1 {
        let candidates = try candidate.map { prior in [try ServiceRequestDuplicateCandidateV1(
            record: prior, sharedSiteID: record.scope.siteID,
            sharedAssetID: record.scope.assets.first?.assetID,
            reasons: [.init(kind: .exactCategory, explanation: "Same scoped synthetic category")]
        )] } ?? []
        return try .init(basisRequestSHA256: record.recordSHA256,
                         ruleReleaseSHA256: C40.digest("d"), candidates: candidates)
    }
}
@MainActor private final class C40PortableDuplicates: ServiceRequestDuplicateProjectingV1 {
    func projectCandidates(workspaceID: WorkspaceID, submission: PortableServiceRequestSubmissionV1,
                           canonicalSourceSHA256: String) throws -> ServiceRequestDuplicateProjectionV1 {
        try .init(basisRequestSHA256: canonicalSourceSHA256,
                  ruleReleaseSHA256: C40.digest("e"), candidates: [])
    }
}
@MainActor private final class C40Contacts: ServiceRequestContactPromotionPreviewingV1 {
    func previewOperationalContactPromotion(request: ServiceRequestRecordV1,
                                            party: ServicePartyReferenceV1) throws -> ServiceRequestContactPromotionPreviewV1 {
        try .init(request: request.reference, party: party, assertedValue: "test@example.invalid", suggestedKind: .email)
    }
}

@MainActor private final class C40Harness {
    let root: URL
    let session: StoreGenerationSession
    let ids = C40IDs()
    let manualDuplicates = C40ManualDuplicates()
    let store: PortableExchangeSessionStoreV2
    let lifecycle: ServiceRequestLifecycleAdapterV1
    init(_ name: String) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("c40-\(name)-\(UUID().uuidString)")
        session = try StoreGenerationFactory(applicationSupportURL: root).openOrBootstrapCurrent()
        store = try PortableExchangeSessionStoreV2(applicationSupportURL: root)
        lifecycle = ServiceRequestLifecycleAdapterV1(store: store)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func make(failure: MutationJournalFailureInjectionV1? = nil) throws -> (ServiceRequestWorkflowCoordinatorV1, WorkspaceExpectedRevisionV1) {
        let bundle = try makeBundle(failure: failure)
        return (bundle.0, bundle.2)
    }
    func makeBundle(failure: MutationJournalFailureInjectionV1? = nil) throws ->
        (ServiceRequestWorkflowCoordinatorV1, ServiceRequestCoordinatorV1, WorkspaceExpectedRevisionV1) {
        let journal = try MutationJournalStoreV1(modelContext: session.modelContext,
            identity: session.workspaceIdentity, generationID: session.generationID, failureInjection: failure)
        let writerID = C40.id(90)
        let current = try journal.currentRevision(writerInstanceID: writerID)
        let writer = try WorkspaceWriterV1(identity: session.workspaceIdentity,
            generationID: session.generationID, initialRevision: current, clock: C40Clock(),
            idSource: C40FixedID(writerID), fileAuthority: SystemApplicationFileAuthorityV1(),
            adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext), journalStore: journal)
        let canonical = ServiceRequestCoordinatorV1(duplicates: C40PortableDuplicates(), writer: writer,
            lifecycle: lifecycle, contactPromotion: C40Contacts(), clock: C40Clock(), idSource: ids)
        return (ServiceRequestWorkflowCoordinatorV1(canonical: canonical,
            manualDuplicates: manualDuplicates, clock: C40Clock()), canonical,
            try WorkspaceExpectedRevisionV1(workspaceID: current.workspaceID,
                generationID: current.generationID, writerInstanceID: current.writerInstanceID,
                workspaceRevision: current.revision, entityRevisions: current.entityRevisions))
    }
    func rowCounts() throws -> (Int, Int, Int) {
        (try session.modelContext.fetch(FetchDescriptor<ServiceRequestRecordRow>()).count,
         try session.modelContext.fetch(FetchDescriptor<ServiceRequestDispositionEventRow>()).count,
         try session.modelContext.fetch(FetchDescriptor<ServiceRequestWorkLinkEventRow>()).count)
    }
}
private struct C40FixedID: ApplicationIDSource { let value: UUID; init(_ value: UUID) { self.value = value }; func makeID() -> UUID { value } }

final class V9_103ServiceRequestWorkflowTests: XCTestCase {
    @MainActor
    func testV23P04C40G01ManualAndPortablePreviewCommitTriageWorkAndSafeStatus() async throws {
        let h = try C40Harness("G")
        let (workflow, expected) = try h.make()
        let portable = try C40.portable()
        _ = try await h.lifecycle.stageInvitation(portable.1, release: portable.0,
                                                   workspaceID: h.session.workspaceID.rawValue)
        _ = try await h.lifecycle.markInvitationExported(portable.1.manifest.invitationPublicID)
        guard case let .portablePreview(portablePreview) = try await workflow.execute(.previewPortable(.init(
            expectedRevision: expected, release: portable.0, invitation: portable.1,
            submission: portable.2, canonicalSourceBytes: portable.3, disposition: .acceptAsNew,
            selectedDuplicate: nil, reason: nil, mutationID: C40.mutation(3)))) else {
            return XCTFail("portable preview")
        }
        XCTAssertTrue(portablePreview.plan.zeroWrite); XCTAssertEqual(try h.rowCounts().0, 0)
        guard case let .manualPreview(preview) = try await workflow.execute(.previewManual(
            expectedRevision: expected, intake: C40.intake(), decision: .needsTriage,
            mutationID: C40.mutation(1))) else { return XCTFail("manual preview") }
        XCTAssertTrue(preview.zeroWrite); XCTAssertEqual(try h.rowCounts().0, 0)
        guard case let .manualReceipt(receipt) = try await workflow.execute(.commitManual(preview)) else {
            return XCTFail("manual receipt")
        }
        XCTAssertEqual(receipt.resultingState, .openUntriaged)
        XCTAssertEqual(try h.rowCounts().0, 1)
        let context = try ServiceRequestWorkflowContextV1(workspaceID: h.session.workspaceID,
            expectedRevision: preview.expectedRevision, records: [preview.record], dispositionEvents: [], workLinkEvents: [])
        let projection = try workflow.project(context)
        XCTAssertEqual(projection.needsTriage.items.map(\.request), [preview.record.reference])
        XCTAssertTrue(projection.needsTriage.derived); XCTAssertTrue(projection.needsTriage.rebuildable)

        let (next, nextRevision) = try h.make()
        let work = try ServiceRequestCanonicalWorkPreviewV1(target: .init(kind: .asset,
            subjectID: C40.id(2), revision: 1, ownerAssetID: nil),
            choice: .activity(activityID: C40.id(210), expectedRevision: 1, semanticSHA256: C40.digest("f")),
            canonicalWorkID: C40.id(211), canonicalWorkRevision: 1, canonicalWorkSHA256: C40.digest("1"))
        guard case let .workPreview(plan) = try await next.execute(.previewWorkConversion(.init(
            request: preview.record.reference, expectedRevision: nextRevision, work: work,
            mutationID: C40.mutation(2)))) else { return XCTFail("work preview") }
        XCTAssertTrue(plan.zeroWrite); XCTAssertEqual(try h.rowCounts().2, 0)
        guard case let .workReceipt(workReceipt) = try await next.execute(.commitWork(plan)) else { return XCTFail("work receipt") }
        XCTAssertEqual(try h.rowCounts().2, 1)
        let state = try ServiceRequestStateProjectionV1(request: preview.record.reference,
            state: .handledByLinkedWork, latestDispositionEventSHA256: C40.digest("2"),
            activeWorkLinkEventSHA256: workReceipt.event.eventSHA256)
        guard case let .statusArtifact(artifact) = try await next.execute(.makeStatusArtifact(
            projection: state, customerNote: "Synthetic customer-safe note")) else { return XCTFail("status") }
        XCTAssertEqual(artifact.statusText, "Linked work has been recorded.")
        XCTAssertFalse(artifact.deliveryClaimed); XCTAssertFalse(artifact.requesterIdentityVerified)
        XCTAssertNotNil(artifact.textLines.joined(separator: "\n").data(using: .utf8))
    }

    @MainActor
    func testV23P04C40A01SixManualChannelsDispositionsDuplicatesUnlinkAndContactSeparation() async throws {
        let sources: [ServiceRequestSourceKindV1] = [.phone, .email, .text, .paper, .inPerson, .other]
        for (index, source) in sources.enumerated() {
            let h = try C40Harness("A\(index)"); let (workflow, expected) = try h.make()
            guard case let .manualPreview(preview) = try await workflow.execute(.previewManual(
                expectedRevision: expected, intake: C40.intake(source), decision: .needsTriage,
                mutationID: C40.mutation(20 + index))) else { return XCTFail("channel") }
            XCTAssertEqual(preview.record.source, source); XCTAssertTrue(preview.zeroWrite)
        }
        XCTAssertEqual(ServiceRequestImportDispositionV1.allCases,
            [.acceptAsNew, .acceptAndLinkDuplicate, .declineWithReason, .recordHistoryOnly, .keepQuarantined, .discardUnimported])
        XCTAssertEqual(ServiceRequestStateV1.allCases.count, 6)
        let draft = try ServiceRequestDraftReferenceV1(draftID: C40.id(30), draftRevision: 2,
            draftSHA256: C40.digest("3"), compatibility: .current)
        let h = try C40Harness("A-draft"); let (workflow, expected) = try h.make()
        let context = try ServiceRequestWorkflowContextV1(workspaceID: h.session.workspaceID,
            expectedRevision: expected, records: [], dispositionEvents: [], workLinkEvents: [], draft: draft)
        XCTAssertTrue(try workflow.project(context).canCommitDraft)
        XCTAssertTrue(ServiceRequestWorkflowClaimsV1().workAutomaticallyCreated == false)

        let linked = try C40Harness("A-linked")
        let (linkedWorkflow, canonical, linkedExpected) = try linked.makeBundle()
        guard case let .manualPreview(requestPreview) = try await linkedWorkflow.execute(.previewManual(
            expectedRevision: linkedExpected, intake: C40.intake(.email), decision: .needsTriage,
            mutationID: C40.mutation(31))),
              case .manualReceipt = try await linkedWorkflow.execute(.commitManual(requestPreview)) else {
            return XCTFail("request setup")
        }
        let party = try ServicePartyReferenceV1(partyID: C40.id(32), workspaceID: linked.session.workspaceID,
            kind: .organization, displayName: "Synthetic facilities contact",
            provenance: .locallyRecorded, state: .effective, effectiveAt: C40.date,
            revision: 1, mutationID: C40.mutation(32))
        let contact = try canonical.previewContactPromotion(request: requestPreview.record, party: party)
        XCTAssertTrue(contact.zeroWrite); XCTAssertEqual(contact.purpose, "OPERATIONAL_CONTACT_ONLY")
        XCTAssertEqual(try linked.rowCounts().0, 1)

        let (_, afterRequest) = try linked.make()
        let work = try ServiceRequestCanonicalWorkPreviewV1(target: .init(kind: .asset,
            subjectID: C40.id(2), revision: 1, ownerAssetID: nil),
            choice: .activity(activityID: C40.id(33), expectedRevision: 1,
                              semanticSHA256: C40.digest("8")),
            canonicalWorkID: C40.id(34), canonicalWorkRevision: 1,
            canonicalWorkSHA256: C40.digest("9"))
        let link = try canonical.previewWorkConversion(request: requestPreview.record.reference,
            expectedRevision: afterRequest, work: work, predecessor: nil, mutationID: C40.mutation(35))
        _ = try canonical.commitWorkConversion(link)
        let (_, afterLink) = try linked.make()
        let reversal = try canonical.previewWorkLinkReversal(predecessor: link.event,
            expectedRevision: afterLink, mutationID: C40.mutation(36))
        let reversalReceipt = try canonical.commitWorkConversion(reversal)
        XCTAssertEqual(reversalReceipt.event.kind, .unlinkReversal)
        XCTAssertEqual(reversalReceipt.event.reversesEventID, link.event.eventID)
        XCTAssertEqual(try linked.rowCounts().2, 2)
    }

    @MainActor
    func testV23P04C40H01HostileInputsAndStaleOrCrossScopeDecisionsHaveNoCanonicalEffect() async throws {
        let h = try C40Harness("H"); let (workflow, expected) = try h.make(); let baseline = try h.rowCounts()
        XCTAssertThrowsError(try C40.intake(.portableSubmission))
        XCTAssertThrowsError(try ServiceRequestDraftReferenceV1(draftID: C40.id(40), draftRevision: 0,
            draftSHA256: C40.digest("4"), compatibility: .unsupported))
        let prior = try ServiceRequestRevisionReferenceV1(recordID: C40.id(41), revision: 1, recordSHA256: C40.digest("5"))
        h.manualDuplicates.candidate = prior
        do {
            _ = try await workflow.execute(.previewManual(expectedRevision: expected,
                intake: C40.intake(), decision: .disposition(.acceptAndLinkDuplicate,
                    selectedDuplicate: nil, reason: nil), mutationID: C40.mutation(42)))
            XCTFail("A duplicate-link decision without a selected candidate must fail closed")
        } catch {
            XCTAssertEqual(error as? ServiceRequestCoordinatorFailureV1, .duplicateDecisionMismatch)
        }
        do {
            _ = try await workflow.execute(.previewManual(expectedRevision: expected,
                intake: C40.intake(), decision: .disposition(.declineWithReason,
                    selectedDuplicate: nil, reason: nil), mutationID: C40.mutation(43)))
            XCTFail("A decline without a reason must fail closed")
        } catch {
            XCTAssertEqual(error as? ServiceRequestCoordinatorFailureV1, .duplicateDecisionMismatch)
        }
        let stale = try WorkspaceExpectedRevisionV1(workspaceID: expected.workspaceID,
            generationID: expected.generationID, writerInstanceID: expected.writerInstanceID,
            workspaceRevision: expected.workspaceRevision + 1, entityRevisions: expected.entityRevisions)
        guard case let .manualPreview(stalePreview) = try await workflow.execute(.previewManual(
            expectedRevision: stale, intake: C40.intake(.text), decision: .needsTriage,
            mutationID: C40.mutation(44))) else { return XCTFail("stale preview setup") }
        do {
            _ = try await workflow.execute(.commitManual(stalePreview))
            XCTFail("A stale workspace preview must not commit")
        } catch {
            XCTAssertNotNil(error as? WorkspaceMutationFailureV1)
        }
        let portable = try C40.portable()
        _ = try await h.lifecycle.stageInvitation(portable.1, release: portable.0,
                                                   workspaceID: h.session.workspaceID.rawValue)
        _ = try await h.lifecycle.markInvitationExported(portable.1.manifest.invitationPublicID)
        do {
            _ = try await workflow.execute(.previewPortable(.init(
                expectedRevision: expected, release: portable.0, invitation: portable.1,
                submission: portable.2,
                canonicalSourceBytes: try CanonicalServiceRequestSourceBytesV1(Data("corrupt".utf8)),
                disposition: .acceptAsNew, selectedDuplicate: nil, reason: nil,
                mutationID: C40.mutation(45))))
            XCTFail("Corrupt portable source bytes must fail closed")
        } catch {
            XCTAssertEqual(try h.rowCounts().0, baseline.0)
        }
        let after = try h.rowCounts()
        XCTAssertEqual(after.0, baseline.0); XCTAssertEqual(after.1, baseline.1); XCTAssertEqual(after.2, baseline.2)
        XCTAssertThrowsError(try CanonicalServiceRequestSourceBytesV1(Data(count: ServiceRequestLimitsV1.maximumPortableFileBytes + 1)))
    }

    @MainActor
    func testV23P04C40I01DraftCancellationAndEffectBeforeReceiptRecoverToOneExactEffect() async throws {
        let h = try C40Harness("I")
        let draft = try ServiceRequestDraftReferenceV1(draftID: C40.id(50), draftRevision: 1,
            draftSHA256: C40.digest("6"), compatibility: .current)
        let (_, expected) = try h.make()
        let context = try ServiceRequestWorkflowContextV1(workspaceID: h.session.workspaceID,
            expectedRevision: expected, records: [], dispositionEvents: [], workLinkEvents: [], draft: draft)
        XCTAssertTrue(try h.make().0.project(context).canCommitDraft)
        let before = try h.rowCounts()
        XCTAssertEqual(before.0, 0); XCTAssertEqual(before.1, 0); XCTAssertEqual(before.2, 0)
        let (faulted, revision) = try h.make(failure: .init(failOnceAt: .afterEffectBeforeReceipt))
        guard case let .manualPreview(preview) = try await faulted.execute(.previewManual(
            expectedRevision: revision, intake: C40.intake(), decision: .needsTriage,
            mutationID: C40.mutation(51))) else { return XCTFail("preview") }
        do {
            _ = try await faulted.execute(.commitManual(preview))
            XCTFail("The injected effect-before-receipt boundary must interrupt the first commit")
        } catch {
            XCTAssertEqual(error as? MutationJournalFailureV1, .injected(.afterEffectBeforeReceipt))
        }
        let (recovered, _) = try h.make()
        guard case let .manualReceipt(first) = try await recovered.execute(.recoverManual(preview)),
              case let .manualReceipt(second) = try await recovered.execute(.recoverManual(preview)) else {
            return XCTFail("recover")
        }
        XCTAssertEqual(first, second); XCTAssertEqual(try h.rowCounts().0, 1)
    }

    @MainActor
    func testV23P04C40R01ExactReplayRebuildAndLifecycleBoundariesPreserveNamespaces() async throws {
        let h = try C40Harness("R"); let (workflow, expected) = try h.make()
        guard case let .manualPreview(preview) = try await workflow.execute(.previewManual(
            expectedRevision: expected, intake: C40.intake(.paper), decision: .needsTriage,
            mutationID: C40.mutation(60))),
              case let .manualReceipt(first) = try await workflow.execute(.commitManual(preview)),
              case let .manualReceipt(second) = try await workflow.execute(.recoverManual(preview)) else {
            return XCTFail("replay")
        }
        XCTAssertEqual(first, second); XCTAssertEqual(try h.rowCounts().0, 1)
        let rebuilt = try workflow.project(.init(workspaceID: h.session.workspaceID,
            expectedRevision: preview.expectedRevision, records: [preview.record],
            dispositionEvents: [], workLinkEvents: []))
        XCTAssertEqual(rebuilt.needsTriage.items.count, 1)
        XCTAssertTrue(ServiceRequestLifecycleRegistrationBoundaryV1.replaceRestorePreservesHistory)
        XCTAssertTrue(ServiceRequestLifecycleRegistrationBoundaryV1.cloneOrForkPreservesHistory)
        XCTAssertTrue(ServiceRequestLifecycleRegistrationBoundaryV1.cloneOrForkInvalidatesOutstandingCapabilities)
        XCTAssertTrue(ServiceRequestLifecycleRegistrationBoundaryV1.eraseRemovesOwnedProtectedState)
        XCTAssertEqual(PortableExchangeSessionNamespaceV2.serviceRequest.rawValue, "SERVICE_REQUEST")
        XCTAssertNotEqual(PortableExchangeSessionNamespaceV2.serviceRequest, .review)
        XCTAssertTrue(C48PortableReviewPersistenceBoundaryV1.reviewAndServiceNamespacesAreIndependent)
        let portable = try C40.portable()
        let checkpoint = try C40.checkpoint(workspaceID: h.session.workspaceID, draftID: C40.id(71),
                                            manifest: portable.1.manifest)
        let input = PortableExchangeServiceRequestDraftMigrationInputV2(
            legacyCheckpoint: checkpoint,
            legacyDraft: try checkpoint.serviceRequestDraftReference(compatibility: .migrationRequired),
            protocolRelease: portable.0, capability: try portable.1.capability)
        let migrated = try await h.store.migrateLegacyServiceRequestDraft(input)
        let replayed = try await h.store.migrateLegacyServiceRequestDraft(input)
        XCTAssertEqual(migrated.disposition, .migrated)
        XCTAssertEqual(replayed.disposition, .replayed)
        XCTAssertEqual(migrated.migratedDraft, replayed.migratedDraft)
        XCTAssertTrue(migrated.sourceDeletionAuthorized)
        let reloaded = try PortableExchangeSessionStoreV2(applicationSupportURL: h.root)
        let afterRelaunch = try await reloaded.migrateLegacyServiceRequestDraft(input)
        XCTAssertEqual(afterRelaunch.disposition, .replayed)
        XCTAssertEqual(afterRelaunch.sourceSHA256, migrated.sourceSHA256)
        let distinctIdentityCheckpoint = try C40.checkpoint(
            workspaceID: h.session.workspaceID,
            draftID: C40.id(72),
            manifest: portable.1.manifest
        )
        var distinctIdentityAuthorizedSourceDeletion = false
        do {
            let distinctIdentity = try await reloaded.migrateLegacyServiceRequestDraft(.init(
                legacyCheckpoint: distinctIdentityCheckpoint,
                legacyDraft: try distinctIdentityCheckpoint.serviceRequestDraftReference(
                    compatibility: .migrationRequired
                ),
                protocolRelease: portable.0,
                capability: try portable.1.capability
            ))
            XCTAssertNotEqual(distinctIdentity.migrationID, migrated.migrationID)
            XCTAssertNotEqual(distinctIdentity.disposition, .replayed)
            distinctIdentityAuthorizedSourceDeletion = distinctIdentity.sourceDeletionAuthorized
        } catch {
            XCTAssertEqual(try h.rowCounts().0, 1)
        }
        XCTAssertFalse(
            distinctIdentityAuthorizedSourceDeletion,
            "Identical bytes under a different migration identity cannot authorize deletion"
        )
        let divergentManifest = try ServiceRequestInvitationManifestV1(
            protocolRelease: portable.0,
            invitationPublicID: .init("INV-C40-DIVERGENT-001"), scope: try C40.scope())
        let divergentCheckpoint = try C40.checkpoint(workspaceID: h.session.workspaceID,
            draftID: checkpoint.draftID, manifest: divergentManifest)
        do {
            _ = try await reloaded.migrateLegacyServiceRequestDraft(.init(
                legacyCheckpoint: divergentCheckpoint,
                legacyDraft: try divergentCheckpoint.serviceRequestDraftReference(
                    compatibility: .migrationRequired
                ),
                protocolRelease: portable.0, capability: try portable.1.capability))
            XCTFail("Divergent bytes for the same migrated draft ID must fail closed")
        } catch {
            XCTAssertEqual(try h.rowCounts().0, 1)
        }
        XCTAssertEqual(try h.rowCounts().0, 1, "draft divergence cannot create a canonical request")
    }
}
