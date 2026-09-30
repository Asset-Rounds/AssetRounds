import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

/// Shared SIG-1 fixtures. Completed work comes only from the incumbent
/// finalize path (`makeReadyReport`) and the incumbent clerical-correction
/// path; nothing here constructs a report, packet or record directly.
extension V23ProductionFourRootShellTestSupport {
    @MainActor
    func makeCompletedWorkWorkflow(
        store: StoreSessionCoordinator,
        diagnostics: DiagnosticsStore,
        access: AppAccessPresentationV1.ContentAccess
    ) throws -> ProductionSignWorkflow {
        try access.withRead {
            let profiles = try WorkspacePackageLifecycleCompatibilityV1
                .legacyV3Registry(package: .illuminatedSignV1)
            let root = try ProductionCompositionRoot(
                storeSession: store,
                diagnosticsStore: diagnostics,
                profileRegistry: profiles
            )
            return try root.makeSignWorkflow(
                signPack: .illuminatedSignV1,
                accessState: { .entitled }
            )
        }
    }

    @MainActor
    func makeCompletedWorkWorkflow(
        in fixture: V23ProductionMyDayPresentationHarness
    ) throws -> ProductionSignWorkflow {
        try makeCompletedWorkWorkflow(
            store: fixture.coordinator,
            diagnostics: fixture.diagnostics,
            access: try XCTUnwrap(fixture.presentation.renderAccess)
        )
    }

    @MainActor
    func completedWorkResolver(
        in fixture: V23ProductionMyDayPresentationHarness
    ) -> CompletedWorkSubjectResolverV1 {
        CompletedWorkSubjectResolverV1(
            modelContext: fixture.coordinator.modelContext,
            workspaceID: fixture.coordinator.workspaceID,
            generationID: fixture.coordinator.generationID,
            generationRootURL: fixture.coordinator.generationRootURL,
            signPack: .illuminatedSignV1
        )
    }

    @MainActor
    func completedWorkKey(
        _ reportID: UUID,
        revision: UInt64,
        in fixture: V23ProductionMyDayPresentationHarness
    ) throws -> CompletedWorkSubjectKeyV1 {
        try CompletedWorkSubjectKeyV1(
            workspaceID: fixture.coordinator.workspaceID,
            subjectID: reportID,
            subjectRevision: revision
        )
    }

    /// Incumbent note-only clerical correction. `makeReadyReport` finalizes
    /// at 1_800_500_011, so every correction is created after that instant.
    @MainActor
    func correctCompletedReport(
        _ reportID: UUID,
        workflow: ProductionSignWorkflow,
        note: String,
        createdAt: Date = Date(timeIntervalSince1970: 1_800_500_100)
    ) async throws -> UUID {
        let source = try workflow.reportDelivery.correctionSource(reportID: reportID)
        let result = try await workflow.reportDelivery.submitCorrection(
            from: source,
            note: note,
            snapshotCreatedAt: createdAt,
            sourceApp: SourceAppSnapshotV1(build: "sig1-correction", version: "1")
        )
        switch result {
        case let .ready(chain):
            return chain.current.reportID
        case let .pdfUnavailable(reportID: correctedID, prior: _):
            return correctedID
        }
    }

    @MainActor
    func completedWorkSubmission(
        for proof: CompletedWorkSubjectProofV1,
        typedName: String = "Casey Responder",
        claimedRole: String = "Site manager",
        relationship: SitePartyRoleV1? = .client
    ) -> SignoffEnrollmentSubmissionV1 {
        SignoffEnrollmentSubmissionV1(
            route: SignoffEnrollmentRouteMetadataV1(
                workspaceID: proof.workspaceID,
                subjectID: proof.reportID,
                subjectRevision: proof.chainPosition,
                subject: proof.display
            ),
            typedName: typedName,
            claimedRole: claimedRole,
            claimedRelationship: relationship
        )
    }

    @MainActor
    func completedWorkRowCount<T: PersistentModel>(
        _ type: T.Type,
        in context: ModelContext
    ) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }
}

final class V23CompletedWorkSubjectTests: V23ProductionFourRootShellTestSupport {
    @MainActor
    func testOriginalFinalizedReportIsRevisionOneEligibleRegardlessOfPDFState() async throws {
        let fixture = try await makeFixture("sig1-subject-original")
        defer { fixture.cleanUp() }
        let report = try await makeReadyReport(in: fixture, label: "sig1-original")
        let workflow = try makeCompletedWorkWorkflow(in: fixture)
        let service = workflow.completedWorkResponses
        let resolver = completedWorkResolver(in: fixture)
        let context = fixture.coordinator.modelContext
        let key = try completedWorkKey(report.reportID, revision: 1, in: fixture)
        let row = try XCTUnwrap(context.fetch(FetchDescriptor<Report>()).first {
            $0.id == report.reportID
        })
        XCTAssertEqual(row.pdfState, ReportPDFState.ready.rawValue)

        let readyProof = try XCTUnwrap(resolver.resolve(key).proof)
        XCTAssertEqual(readyProof.reportID, report.reportID)
        XCTAssertEqual(readyProof.workspaceID, fixture.coordinator.workspaceID)
        XCTAssertEqual(readyProof.generationID, fixture.coordinator.generationID)
        XCTAssertEqual(readyProof.chainPosition, 1)
        XCTAssertTrue(readyProof.isTip)
        XCTAssertEqual(readyProof.eligibility, .eligible)
        XCTAssertEqual(readyProof.snapshotFamily, .legacyReportSnapshot)
        XCTAssertEqual(readyProof.snapshotSchemaVersion, row.snapshotSchemaVersion)
        XCTAssertEqual(readyProof.snapshotSHA256, row.snapshotSHA256)
        XCTAssertEqual(readyProof.sourceRecordID, row.sourceRecordID)
        XCTAssertEqual(readyProof.display.version, 1)
        XCTAssertEqual(readyProof.display.versionText, "Version 1")
        XCTAssertEqual(try readyProof.key, key)

        let listing = try service.completedWork()
        XCTAssertEqual(listing.map(\.key), [key])
        XCTAssertEqual(listing.first?.eligibility, .eligible)
        XCTAssertEqual(listing.first?.display, readyProof.display)
        XCTAssertEqual(listing.first?.responseCount, 0)

        // PDF state is irrelevant. The fixture changes only the PDF fields,
        // exactly as the incumbent failed/pending shapes store them.
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        for state in [ReportPDFState.failed, ReportPDFState.pending] {
            row.pdfState = state.rawValue
            row.pdfRelativePath = nil
            row.pdfSHA256 = nil
            try context.save()
            let proof = try XCTUnwrap(
                resolver.resolve(key).proof,
                "PDF state \(state.rawValue) must not change eligibility"
            )
            XCTAssertEqual(proof, readyProof)
            let detail = try service.subjectDetail(key)
            XCTAssertEqual(detail.eligibility, .eligible)
            XCTAssertEqual(detail.proof, readyProof)
            XCTAssertEqual(try service.completedWork().map(\.key), [key])
        }
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor
    func testClericalCorrectionSupersedesOriginalAndIsRevisionTwoTip() async throws {
        let fixture = try await makeFixture("sig1-subject-correction")
        defer { fixture.cleanUp() }
        let report = try await makeReadyReport(in: fixture, label: "sig1-correction")
        let workflow = try makeCompletedWorkWorkflow(in: fixture)
        let correctedID = try await correctCompletedReport(
            report.reportID, workflow: workflow, note: "Clerical correction for SIG-1"
        )
        XCTAssertNotEqual(correctedID, report.reportID)
        let resolver = completedWorkResolver(in: fixture)
        let originalKey = try completedWorkKey(report.reportID, revision: 1, in: fixture)
        let correctedKey = try completedWorkKey(correctedID, revision: 2, in: fixture)

        let original = try XCTUnwrap(resolver.resolve(originalKey).proof)
        XCTAssertFalse(original.isTip)
        XCTAssertEqual(original.eligibility, .superseded)
        XCTAssertFalse(original.eligibility.canRecord)
        XCTAssertNotNil(original.eligibility.reasonText)
        XCTAssertEqual(original.chainPosition, 1)

        let corrected = try XCTUnwrap(resolver.resolve(correctedKey).proof)
        XCTAssertTrue(corrected.isTip)
        XCTAssertEqual(corrected.eligibility, .eligible)
        XCTAssertEqual(corrected.chainPosition, 2)
        XCTAssertEqual(corrected.packetID, original.packetID)
        XCTAssertNotEqual(corrected.snapshotSHA256, original.snapshotSHA256)
        XCTAssertEqual(corrected.display.versionText, "Version 2")

        // The position is fixed per report, never the chain length.
        XCTAssertEqual(
            resolver.resolve(try completedWorkKey(correctedID, revision: 1, in: fixture)),
            .unavailable(.revisionMismatch)
        )
        XCTAssertEqual(
            resolver.resolve(try completedWorkKey(report.reportID, revision: 2, in: fixture)),
            .unavailable(.revisionMismatch)
        )
        let chain = try XCTUnwrap(try resolver.chain(containing: report.reportID))
        XCTAssertEqual(chain.positions, [report.reportID: 1, correctedID: 2])
        XCTAssertEqual(chain.tipReportID, correctedID)

        let service = workflow.completedWorkResponses
        XCTAssertEqual(try service.completedWork().map(\.key), [correctedKey])
        XCTAssertEqual(try service.subjectDetail(originalKey).eligibility, .superseded)
        XCTAssertEqual(try service.subjectDetail(correctedKey).eligibility, .eligible)
    }

    @MainActor
    func testDeletedTamperedMissingAndTypedFamilySubjectsAreUnavailableNotSubstituted() async throws {
        let fixture = try await makeFixture("sig1-subject-unavailable")
        defer { fixture.cleanUp() }
        let first = try await makeReadyReport(in: fixture, label: "sig1-first")
        let second = try await makeReadyReport(in: fixture, label: "sig1-second")
        let workflow = try makeCompletedWorkWorkflow(in: fixture)
        let service = workflow.completedWorkResponses
        let resolver = completedWorkResolver(in: fixture)
        let context = fixture.coordinator.modelContext
        let firstKey = try completedWorkKey(first.reportID, revision: 1, in: fixture)
        let secondKey = try completedWorkKey(second.reportID, revision: 1, in: fixture)
        let firstProof = try XCTUnwrap(resolver.resolve(firstKey).proof)
        XCTAssertNotNil(resolver.resolve(secondKey).proof)

        // Missing: an unknown report is never replaced by another subject.
        let missing = try completedWorkKey(UUID(), revision: 1, in: fixture)
        XCTAssertEqual(resolver.resolve(missing), .unavailable(.missing))
        let missingDetail = try service.subjectDetail(missing)
        XCTAssertNil(missingDetail.proof)
        XCTAssertEqual(missingDetail.eligibility, .unavailable(.missing))
        XCTAssertFalse(missingDetail.eligibility.canRecord)

        // Typed CompletedActivitySnapshotV2 / C06 family is reserved in batch 1.
        let typed = try CompletedWorkSubjectKeyV1(
            workspaceID: fixture.coordinator.workspaceID,
            family: .typedCompletedActivityReserved,
            subjectID: first.reportID,
            subjectRevision: 1
        )
        XCTAssertEqual(resolver.resolve(typed), .unavailable(.unsupportedFamily))
        XCTAssertNil(try service.subjectDetail(typed).proof)

        // Tampered frozen snapshot bytes. The resolver is read directly: the
        // service listing is cached by canonical state, and a file-only change
        // is caught at record time by the two proof checks.
        let secondRow = try XCTUnwrap(context.fetch(FetchDescriptor<Report>()).first {
            $0.id == second.reportID
        })
        let snapshotURL = fixture.coordinator.generationRootURL
            .appendingPathComponent(secondRow.snapshotRelativePath)
        let originalBytes = try Data(contentsOf: snapshotURL)
        var tamperedBytes = originalBytes
        tamperedBytes.append(0x20)
        try tamperedBytes.write(to: snapshotURL)
        XCTAssertEqual(resolver.resolve(secondKey), .unavailable(.tampered))
        XCTAssertEqual(
            resolver.resolve(firstKey).proof, firstProof,
            "Another subject's tampering never substitutes or hides this subject"
        )
        let tamperedTips = try resolver.currentTips()
        XCTAssertEqual(Set(tamperedTips.map(\.key)), [firstKey, secondKey])
        XCTAssertEqual(
            tamperedTips.first { $0.key == secondKey }?.resolution,
            .unavailable(.tampered)
        )
        XCTAssertEqual(tamperedTips.first { $0.key == firstKey }?.resolution, .resolved(firstProof))
        try originalBytes.write(to: snapshotURL)
        XCTAssertNotNil(resolver.resolve(secondKey).proof)

        // Deleted: a response on the first subject, then the real whole-sign
        // deletion path. The response is retained until Erase.
        let prepared = try service.prepare(
            submission: completedWorkSubmission(for: firstProof, typedName: "Deleted Subject Responder"),
            expectedProof: firstProof
        )
        guard case let .saved(receipt) = service.record(prepared) else {
            return XCTFail("Expected a saved response before deletion")
        }
        XCTAssertEqual(try service.completedWork().first { $0.key == firstKey }?.responseCount, 1)
        _ = try await workflow.deletion.delete(assetID: first.assetID)
        XCTAssertFalse(context.hasChanges)

        XCTAssertEqual(resolver.resolve(firstKey), .unavailable(.missing))
        let deletedDetail = try service.subjectDetail(firstKey)
        XCTAssertNil(deletedDetail.proof)
        XCTAssertEqual(deletedDetail.eligibility, .unavailable(.missing))
        let secondAfter = try XCTUnwrap(resolver.resolve(secondKey).proof,
            "The other subject stays resolvable after the deletion")
        XCTAssertEqual(secondAfter.eligibility, .eligible)
        let listing = try service.completedWork()
        XCTAssertEqual(listing.map(\.key), [secondKey], "The deleted subject is never substituted")
        XCTAssertEqual(listing.first?.eligibility, .eligible)

        let history = try service.history(focusedSignoffID: receipt.snapshotID)
        XCTAssertNil(history.subject)
        XCTAssertEqual(history.unavailableReason, .missing,
            "The screen shows the response under Completed work unavailable")
        XCTAssertTrue(history.earlier.isEmpty)
        XCTAssertEqual(history.current.count, 1)
        XCTAssertEqual(history.current.first?.facts?.typedName, "Deleted Subject Responder")
        XCTAssertEqual(history.current.first?.version, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SignoffSnapshotRow>()), 1)
    }

    @MainActor
    func testSubjectKeyRejectsWrongRevisionUnknownIDAndNonC43Purpose() async throws {
        let fixture = try await makeFixture("sig1-subject-key")
        defer { fixture.cleanUp() }
        let report = try await makeReadyReport(in: fixture, label: "sig1-key")
        let workspaceID = fixture.coordinator.workspaceID
        let zero = PartyAccountabilityValidationV1.zero

        XCTAssertThrowsError(try CompletedWorkSubjectKeyV1(
            workspaceID: workspaceID, subjectID: report.reportID, subjectRevision: 0
        )) { XCTAssertEqual($0 as? CompletedWorkSubjectFailureV1, .invalidKey) }
        XCTAssertThrowsError(try CompletedWorkSubjectKeyV1(
            workspaceID: workspaceID, subjectID: zero, subjectRevision: 1
        )) { XCTAssertEqual($0 as? CompletedWorkSubjectFailureV1, .invalidKey) }
        XCTAssertThrowsError(try CompletedWorkSubjectKeyV1(
            workspaceID: WorkspaceID(rawValue: zero), subjectID: report.reportID, subjectRevision: 1
        )) { XCTAssertEqual($0 as? CompletedWorkSubjectFailureV1, .invalidKey) }

        let resolver = completedWorkResolver(in: fixture)
        XCTAssertEqual(
            resolver.resolve(try completedWorkKey(report.reportID, revision: 2, in: fixture)),
            .unavailable(.revisionMismatch)
        )
        XCTAssertEqual(
            resolver.resolve(try completedWorkKey(UUID(), revision: 1, in: fixture)),
            .unavailable(.missing)
        )
        XCTAssertEqual(
            resolver.resolve(try CompletedWorkSubjectKeyV1(
                workspaceID: WorkspaceID(), subjectID: report.reportID, subjectRevision: 1
            )),
            .unavailable(.wrongWorkspace)
        )

        let recordedAt = Date(timeIntervalSince1970: 1_800_500_300)
        let foreignPurpose = try SignoffSnapshotV1(
            snapshotID: UUID(), workspaceID: workspaceID,
            purpose: "WORK_DETAIL_COMPLETED_ACKNOWLEDGEMENT_V1",
            subjectID: report.reportID, subjectRevision: 1,
            disposition: .notRecorded, method: .noAssertion,
            recordedAt: recordedAt, mutationID: try MutationIDV1(rawValue: UUID())
        )
        XCTAssertThrowsError(try CompletedWorkSubjectKeyV1(signoff: foreignPurpose)) {
            XCTAssertEqual($0 as? CompletedWorkSubjectFailureV1, .unsupportedPurpose)
        }

        let c43Purpose = try SignoffSnapshotV1(
            snapshotID: UUID(), workspaceID: workspaceID,
            purpose: SignoffEnrollmentManifestV1.workDetailCompletedResponseV1.purpose,
            subjectID: report.reportID, subjectRevision: 1,
            disposition: .notRecorded, method: .noAssertion,
            recordedAt: recordedAt, mutationID: try MutationIDV1(rawValue: UUID())
        )
        let c43Key = try CompletedWorkSubjectKeyV1(signoff: c43Purpose)
        XCTAssertEqual(c43Key, try completedWorkKey(report.reportID, revision: 1, in: fixture))
        XCTAssertEqual(c43Key.family, .legacyReportSnapshot)
        XCTAssertNotNil(resolver.resolve(c43Key).proof)
        // A C43-purpose shape outside the enrollment boundary is not a response.
        XCTAssertThrowsError(try C43SignoffEnrollmentBoundaryV1.validate(c43Purpose))
    }
}
