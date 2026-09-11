import Foundation
import CryptoKit
import SwiftData
import XCTest

@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_V10_01WorkspaceWriterTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

private enum C53AssetServiceReliabilityBoundary_V10_01WorkspaceWriterTests {
    static let typedAnchor: C53AssetServiceReliabilityBoundaryTokenV1.Type = C53AssetServiceReliabilityBoundaryTokenV1.self
}

/// Test-side copy of the released V4 journal checkpoint envelope. The
/// expected digest is produced from the historical recipe, independently of
/// the validator under test.
private struct HistoricalJournalMutableItemV1: Codable {
    let stableIdentity: String
    let revision: UInt64
    let semanticSHA256: String
}

private struct HistoricalJournalMutableBasisV1: Codable {
    let content: [HistoricalJournalMutableItemV1]
    let deletionLedger: DeletionLedgerV2
}

private struct HistoricalJournalPostImageBasisV1<Value: Codable>: Codable {
    let identity: WorkspaceEntityIdentityV1
    let revision: UInt64
    let value: Value
}

private struct HistoricalWorkflowPostImageV8: Codable {
    let record: V4BackupWorkflowRecordDTO
    let requirementAssurance: RequirementAssuranceSnapshotV1?
}

private final class C45WorkspaceWriterCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityWriterSupportsOnlyTypedAssetLabelCommand() {
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyAssetLabel))
        XCTAssertEqual(WorkspaceCommandKindV1.applyAssetLabel.rawValue, "apply_asset_label")
        XCTAssertEqual(AssetLabelPersistenceEnrollmentV1.durableModelCount, 1)
    }
}

private final class C30EvidenceContextAnchorV10_01WorkspaceWriter: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class V10_01WorkspaceWriterTests: XCTestCase {
    func testV23P03C37TypedPoseContractAnchor() throws {
        let axis = try PoseAxisDescriptorV1(
            axisID: PoseAxisID(rawValue: "axis.c37.anchor"),
            localizedLabelKey: "pose.c37.anchor",
            semanticRole: .otherDeclaredAxis,
            requiredComponents: .azimuthOnly,
            observationRequirement: .optional,
            applicability: .applicable
        )
        let registry = try PoseAxisDescriptorRegistryV1(descriptors: [axis])
        XCTAssertEqual(try registry.descriptor(for: axis.axisID), axis)
    }
    func testV23P03C29TypedPlanContractAnchor() throws {
        let minimum = try NormalizedPlanCoordinateV1(millionths: 0)
        let maximum = try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale)
        XCTAssertEqual(minimum.millionths, 0)
        XCTAssertEqual(maximum.millionths, PlanLimitsV1.normalizedScale)
        XCTAssertEqual(PlanDocumentV1.schemaVersion, 1)
    }
    func testV23P03C39SemanticCodecRetryBytesAreIdempotent() throws {
        let value = [
            try AssetSemanticCapabilityIDV1("capability.inspect"),
            try AssetSemanticCapabilityIDV1("capability.repair")
        ]
        let first = try AssetSemanticCanonicalCodecV1.encode(value)
        let retry = try AssetSemanticCanonicalCodecV1.encode(value)
        XCTAssertEqual(first, retry)
        XCTAssertEqual(
            try AssetSemanticCanonicalCodecV1.decode([AssetSemanticCapabilityIDV1].self, from: retry),
            value
        )
    }

    @MainActor
    func testCanonicalCommitInvalidatesSearchAtExactWriterRevision() throws {
        let recorder = SearchRevisionRecorder()
        let harness = try Harness(searchIndexInvalidation: { recorder.values.append($0) })
        let before = try harness.writer.currentRevision()
        let request = try harness.request(mutation: 1, label: "Indexed", expected: before)
        let outcome = try harness.writer.execute(request)

        XCTAssertEqual(recorder.values.count, 1)
        XCTAssertEqual(recorder.values.first?.workspaceID, harness.workspaceID.rawValue)
        XCTAssertEqual(recorder.values.first?.generationID, harness.generationID)
        XCTAssertEqual(recorder.values.first?.commitRevision, outcome.after.revision)

        let stale = try harness.request(mutation: 2, label: "Rejected", expected: before)
        XCTAssertThrowsError(try harness.writer.execute(stale))
        XCTAssertEqual(recorder.values.count, 1)
    }

    @MainActor
    func testV9_08G01ExpectedRevisionSuccessAndStaleRejection() throws {
        let harness = try Harness()
        let request = try harness.request(mutation: 1, label: "North sign")
        let outcome = try harness.writer.execute(request)
        XCTAssertEqual(outcome.before.revision, 0)
        XCTAssertEqual(outcome.after.revision, 1)
        XCTAssertEqual(outcome.occurredAt, Date(timeIntervalSince1970: 1_800_000_000))
        if case let .createFirstSign(value) = request.command {
            XCTAssertEqual(value.createdAt, Date(timeIntervalSince1970: 1_800_000_010))
            XCTAssertNotEqual(value.createdAt, outcome.occurredAt)
        } else {
            XCTFail("Expected create-first-sign command")
        }
        XCTAssertEqual(harness.adapter.applyCount, 1)

        let stale = try harness.request(
            mutation: 2,
            label: "South sign",
            expected: outcome.before
        )
        XCTAssertThrowsError(try harness.writer.execute(stale)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .staleWorkspaceRevision)
        }
        XCTAssertEqual(harness.adapter.applyCount, 1)

        let applicationSupport = try Self.makeTemporaryApplicationSupportURL()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let session = try StoreGenerationFactory(applicationSupportURL: applicationSupport)
            .openOrBootstrapCurrent()
        let realWriter = StoreSessionCoordinator(
            session: session,
            clock: TestApplicationClockV1(value: Date(timeIntervalSince1970: 1_800_000_100)),
            idSource: TestApplicationIDSourceV1(value: Harness.id(80)),
            fileAuthority: TestApplicationFileAuthorityV1()
        ).workspaceWriter
        let realSiteID = Harness.id(81)
        let realAssetID = Harness.id(82)
        let realMutationID = try MutationIDV1(rawValue: Harness.id(83))
        let realPlacementEventID = Harness.id(84)
        let realPhysicalEpisodeID = try PhysicalPlacementEpisodeIDV1(rawValue: Harness.id(85))
        let realCreatedAt = Date(timeIntervalSince1970: 1_800_000_110)
        let realCurrent = try realWriter.currentRevision()
        let realExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: realCurrent.workspaceID,
            generationID: realCurrent.generationID,
            writerInstanceID: realCurrent.writerInstanceID,
            workspaceRevision: realCurrent.revision,
            entityRevisions: [
                .init(
                    identity: try WorkspaceEntityIdentityV1(kind: .site, id: realSiteID),
                    revision: 0
                ),
                .init(
                    identity: try WorkspaceEntityIdentityV1(kind: .asset, id: realAssetID),
                    revision: 0
                ),
                .init(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .assetPlacementEvent,
                        id: realPlacementEventID
                    ),
                    revision: 0
                ),
            ]
        )
        XCTAssertThrowsError(try realWriter.execute(.init(
            mutationID: try MutationIDV1(rawValue: Harness.id(86)),
            expectedRevision: realExpected,
            command: .createFirstSign(.init(
                siteID: realSiteID,
                newSite: .init(
                    id: realSiteID,
                    label: "Real site",
                    address: nil,
                    timeZoneID: "UTC"
                ),
                assetID: realAssetID,
                assetLabel: "Real asset",
                packID: "test.pack",
                packSchemaVersion: 1,
                packContentVersion: 1,
                createdAt: realCreatedAt
            ))
        ))) { error in
            XCTAssertEqual(error as? WorkspaceMutationFailureV1, .invalidCommand)
        }
        let realOutcome = try realWriter.execute(.init(
            mutationID: realMutationID,
            expectedRevision: realExpected,
            command: .createFirstSign(.init(
                siteID: realSiteID,
                newSite: .init(id: realSiteID, label: "Real site", address: nil, timeZoneID: "UTC"),
                assetID: realAssetID,
                assetLabel: "Real asset",
                packID: "test.pack",
                packSchemaVersion: 1,
                packContentVersion: 1,
                createdAt: realCreatedAt,
                initialPlacementMutationID: realMutationID,
                initialPlacementEventID: realPlacementEventID,
                initialPhysicalEpisodeID: realPhysicalEpisodeID
            ))
        ))
        XCTAssertEqual(realOutcome.after.revision, 1)
        let persistedSites = try session.modelContext.fetch(FetchDescriptor<Site>(
            predicate: #Predicate { $0.id == realSiteID }
        ))
        let persistedAssets = try session.modelContext.fetch(FetchDescriptor<Asset>(
            predicate: #Predicate { $0.id == realAssetID }
        ))
        let persistedPlacements = try session.modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>(
            predicate: #Predicate { $0.id == realPlacementEventID }
        ))
        XCTAssertEqual(persistedSites.count, 1)
        XCTAssertEqual(persistedSites.first?.createdAt, realCreatedAt)
        XCTAssertEqual(persistedAssets.count, 1)
        XCTAssertEqual(persistedAssets.first?.createdAt, realCreatedAt)
        let placement = try XCTUnwrap(persistedPlacements.first).value()
        XCTAssertEqual(persistedPlacements.count, 1)
        XCTAssertEqual(placement.assetID, realAssetID)
        XCTAssertEqual(placement.siteID, realSiteID)
        XCTAssertNil(placement.locationNodeID)
        XCTAssertNil(placement.predecessorEventID)
        XCTAssertEqual(placement.source, .manual)
        XCTAssertEqual(placement.physicalEpisodeID, realPhysicalEpisodeID)
        XCTAssertEqual(placement.mutationID, realMutationID)
        XCTAssertEqual(placement.occurredAt, realOutcome.occurredAt)
        XCTAssertNoThrow(try AssetPlacementHistoryV1.validate([placement]))
    }

    @MainActor
    func testV9_08A01SerializedOrderingUsesOneRevisionSequence() throws {
        let harness = try Harness()
        let priorWriterRevision = try harness.writer.currentRevision()
        let relaunched = try Harness(writerInstanceByte: 91)
        XCTAssertThrowsError(try relaunched.writer.execute(
            relaunched.request(mutation: 92, label: "Cross-instance", expected: priorWriterRevision)
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .wrongWriterInstance)
        }
        let first = try harness.writer.execute(harness.request(mutation: 3, label: "A"))
        let current = try harness.writer.currentRevision()
        let second = try harness.writer.execute(
            harness.request(mutation: 4, label: "B", expected: current)
        )
        XCTAssertEqual(first.after.revision, 1)
        XCTAssertEqual(second.before.revision, 1)
        XCTAssertEqual(second.after.revision, 2)
        XCTAssertEqual(harness.adapter.applyCount, 2)
        harness.writer.invalidate()
        XCTAssertThrowsError(try harness.writer.currentRevision()) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .writerInvalidated)
        }

        let firstRoot = try Self.makeTemporaryApplicationSupportURL()
        let secondRoot = try Self.makeTemporaryApplicationSupportURL()
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }
        let firstSession = try StoreGenerationFactory(applicationSupportURL: firstRoot)
            .openOrBootstrapCurrent()
        let secondSession = try StoreGenerationFactory(applicationSupportURL: secondRoot)
            .openOrBootstrapCurrent()
        let instanceIDs = SequenceApplicationIDSourceV1(values: [
            Harness.id(84),
            Harness.id(85),
        ])
        let coordinator = StoreSessionCoordinator(
            session: firstSession,
            idSource: instanceIDs
        )
        let oldWriter = coordinator.workspaceWriter
        let oldRevision = try oldWriter.currentRevision()
        let initialToken = coordinator.uiGenerationToken
        coordinator.activate(session: secondSession)
        XCTAssertThrowsError(try oldWriter.currentRevision()) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .writerInvalidated)
        }
        XCTAssertFalse(coordinator.workspaceWriter === oldWriter)
        let replacementRevision = try coordinator.workspaceWriter.currentRevision()
        XCTAssertEqual(replacementRevision.generationID, secondSession.generationID)
        XCTAssertNotEqual(replacementRevision.writerInstanceID, oldRevision.writerInstanceID)
        XCTAssertEqual(coordinator.uiGenerationToken, initialToken + 1)
    }

    @MainActor
    func testV9_08H01SameIDRetryAndChangedInputQuarantine() throws {
        let harness = try Harness()
        let request = try harness.request(mutation: 5, label: "Exact")
        let first = try harness.writer.execute(request)
        let retry = try harness.writer.execute(request)
        XCTAssertEqual(first, retry)
        XCTAssertEqual(harness.adapter.applyCount, 1)

        let changed = try harness.request(mutation: 5, label: "Changed")
        XCTAssertThrowsError(try harness.writer.execute(changed)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertThrowsError(try harness.writer.execute(request)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertEqual(harness.adapter.applyCount, 1)
    }

    @MainActor
    func testV9_08I01BoundedNoEvictionIdempotency() throws {
        let harness = try Harness(maximumRemembered: 1)
        let firstRequest = try harness.request(mutation: 6, label: "Remembered")
        let first = try harness.writer.execute(firstRequest)
        let current = try harness.writer.currentRevision()
        let secondRequest = try harness.request(mutation: 7, label: "Rejected", expected: current)
        XCTAssertThrowsError(try harness.writer.execute(secondRequest)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .idempotencyCapacityReached)
        }
        XCTAssertEqual(try harness.writer.execute(firstRequest), first)
        XCTAssertEqual(harness.adapter.applyCount, 1)
    }

    @MainActor
    func testV9_08R01CompleteReversalPolicyAndPurePreview() throws {
        let allCommandKinds: Set<WorkspaceCommandKindV1> = [
            .createFirstSign,
            .createCheckDraft,
            .acceptCheckEvidence,
            .updateSiteTimeZone,
            .deleteAsset,
            .deleteSite,
            .eraseWorkspace,
            .finalizeCheck,
            .finalizeCorrection,
            .recordWork,
            .restoreWorkspace,
            .archiveEntities,
            .applyLocationHierarchyChange,
            .applyAssetPlacementChange,
            .applyAssetCompositionChange,
            .applySavedSmartView,
            .applyRequirementAssurance,
            .applyPartyAccountability,
            .applyPartyContactSiteRoleImport,
            .applyAssetSemantics,
            .applyAuthorityCriterion,
            .applyFunctionalRelationship,
            .applyEvidenceAssurance,
            .applyInspectionReview,
            .applyWorkPacket,
            .applyFieldDraft,
            .applyPackagePromotion,
        ]
        let activeCommandKinds: Set<WorkspaceCommandKindV1> = [
            .createFirstSign,
            .createCheckDraft,
            .acceptCheckEvidence,
            .updateSiteTimeZone,
            .applyLocationHierarchyChange,
            .applyAssetPlacementChange,
            .applyAssetCompositionChange,
            .applySavedSmartView,
            .applyRequirementAssurance,
            .applyPartyAccountability,
            .applyPartyContactSiteRoleImport,
            .applyAssetSemantics,
            .applyAuthorityCriterion,
            .applyFunctionalRelationship,
            .applyEvidenceAssurance,
            .applyInspectionReview,
            .applyWorkPacket,
            .applyFieldDraft,
            .applyPackagePromotion,
        ]
        XCTAssertEqual(Set(WorkspaceCommandKindV1.allCases), allCommandKinds)
        XCTAssertEqual(WorkspaceWriterAdapterV1.activeSupportedCommandKinds, activeCommandKinds)
        XCTAssertEqual(
            Set(MutationReversalPolicyRegistryV1.policies.map(\.commandKind)),
            Set(WorkspaceCommandKindV1.allCases)
        )
        XCTAssertEqual(
            Set(WorkspaceCommandKindV1.allCases),
            allCommandKinds
        )
        XCTAssertEqual(WorkspaceWriterAdapterV1.supportedCommandKinds, [
            .createFirstSign, .createCheckDraft, .acceptCheckEvidence, .updateSiteTimeZone,
        ])
        XCTAssertEqual(WorkspaceWriterAdapterV1.locationSupportedCommandKinds, [
            .applyLocationHierarchyChange,
            .applyAssetPlacementChange,
            .applyAssetCompositionChange,
        ])
        XCTAssertEqual(
            WorkspaceWriterAdapterV1.activeSupportedCommandKinds,
            activeCommandKinds
        )
        XCTAssertFalse(WorkspaceWriterAdapterV1.supportedCommandKinds.contains(.finalizeCheck))
        XCTAssertFalse(WorkspaceWriterAdapterV1.supportedCommandKinds.contains(.eraseWorkspace))
        XCTAssertEqual(MutationBoundaryClosureReceiptV1.kernel.writersPerWorkspaceGeneration, 1)
        XCTAssertEqual(
            MutationBoundaryClosureReceiptV1.kernel.unreservedProductionFeatureOwnedInsertSaveDeleteCount,
            0
        )
        XCTAssertEqual(MutationBoundaryClosureReceiptV1.kernel.deferredReservedDirectWritePaths, [
            "FieldEvidenceApp/Features/Issues/WorkCoordinator.swift",
            "FieldEvidenceApp/Features/Shell/AppShellView.swift",
        ])
        XCTAssertFalse(MutationBoundaryClosureReceiptV1.kernel.fullyClosed)
        XCTAssertTrue(MutationBoundaryClosureReceiptV1.kernel.reconciliationRequired)
        XCTAssertTrue(MutationBoundaryClosureReceiptV1.kernel.durableMutationSchemaPresent)

        let harness = try Harness()
        let target = try WorkspaceEntityIdentityV1(kind: .site, id: Harness.id(40))
        let expected = WorkspaceExpectedRevisionV1(snapshot: try harness.writer.currentRevision())
        let first = try SemanticReversalPlanV1(
            mutationID: MutationIDV1(rawValue: Harness.id(41)),
            commandKind: .updateSiteTimeZone,
            expectedRevision: expected,
            prospectiveTargets: [target],
            requiredSemanticValues: [.init(key: "before", value: "UTC")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [.updateSiteTimeZone(.init(
                siteID: target.id,
                timeZoneID: "UTC",
                confirmedAt: Date(timeIntervalSince1970: 1_800_000_000)
            ))]
        )
        let second = try SemanticReversalPlanV1(
            mutationID: MutationIDV1(rawValue: Harness.id(41)),
            commandKind: .updateSiteTimeZone,
            expectedRevision: expected,
            prospectiveTargets: [target],
            requiredSemanticValues: [.init(key: "before", value: "UTC")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [.updateSiteTimeZone(.init(
                siteID: target.id,
                timeZoneID: "UTC",
                confirmedAt: Date(timeIntervalSince1970: 1_800_000_000)
            ))]
        )
        XCTAssertEqual(first.planDigest, second.planDigest)
        XCTAssertEqual(first.disposition, .reversible)

        let observedAt = Date(timeIntervalSince1970: 1_800_000_100)
        let draft = CheckDraftMutationV1(
            recordID: Harness.id(43),
            assetID: Harness.id(44),
            issueID: nil,
            parentRecordID: nil,
            stage: WorkflowStage.check.rawValue,
            draftStepKey: WorkflowDraftStep.wide.rawValue,
            startedAt: Date(timeIntervalSince1970: 1_800_000_050),
            observedAtUTC: observedAt,
            timeZoneID: "America/New_York",
            utcOffsetMinutes: -300,
            localDate: "2027-01-15",
            localTime: "09:30",
            afterDarkAcknowledgementKey: "after_dark",
            afterDarkAcknowledgementCopy: "After-dark acknowledgement",
            afterDarkAcknowledgementVersion: "1",
            afterDarkAcknowledgementAccepted: true,
            safePositionAcknowledgementKey: "safe_authorized_position",
            safePositionAcknowledgementCopy: "Safe-position acknowledgement",
            safePositionAcknowledgementVersion: "1",
            safePositionAcknowledgementAccepted: true,
            packID: "test.pack",
            packSchemaVersion: 1,
            packContentVersion: 1,
            pdfTemplateID: "worklight.report",
            pdfTemplateVersion: 1
        )
        let draftDecoder = JSONDecoder()
        draftDecoder.dateDecodingStrategy = .millisecondsSince1970
        let decodedDraft = try draftDecoder.decode(
            CheckDraftMutationV1.self,
            from: WorkspaceMutationCanonicalV1.data(draft)
        )
        XCTAssertEqual(decodedDraft, draft)
        XCTAssertEqual(decodedDraft.observedAtUTC, observedAt)

        let workDraft = CheckDraftMutationV1(
            recordID: Harness.id(45),
            assetID: Harness.id(44),
            issueID: Harness.id(46),
            parentRecordID: nil,
            stage: WorkflowStage.work.rawValue,
            draftStepKey: nil,
            startedAt: Date(timeIntervalSince1970: 1_800_000_060),
            observedAtUTC: nil,
            timeZoneID: nil,
            utcOffsetMinutes: nil,
            localDate: nil,
            localTime: nil,
            afterDarkAcknowledgementKey: nil,
            afterDarkAcknowledgementCopy: nil,
            afterDarkAcknowledgementVersion: nil,
            afterDarkAcknowledgementAccepted: nil,
            safePositionAcknowledgementKey: nil,
            safePositionAcknowledgementCopy: nil,
            safePositionAcknowledgementVersion: nil,
            safePositionAcknowledgementAccepted: nil,
            packID: "test.pack",
            packSchemaVersion: 1,
            packContentVersion: 1,
            pdfTemplateID: "worklight.report",
            pdfTemplateVersion: 1
        )
        XCTAssertNil(workDraft.draftStepKey)

        XCTAssertThrowsError(try SemanticReversalPlanV1(
            mutationID: MutationIDV1(rawValue: Harness.id(42)),
            commandKind: .acceptCheckEvidence,
            expectedRevision: expected,
            prospectiveTargets: [target],
            requiredSemanticValues: [],
            contentReferences: ["evidence/original"],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [.archiveEntities(.init(identities: [target], reason: "not_allowed"))]
        ))
    }

    func testV23P03C38WriterBoundaryBindsRowsToMutationAndExpectedRevision() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let writerSource = try String(
            contentsOf: root.appendingPathComponent(
                "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(writerSource.contains("MutationReceipt"))
        XCTAssertTrue(writerSource.contains("mutationID"))
        XCTAssertTrue(writerSource.contains("expectedRevision"))
        XCTAssertTrue(writerSource.contains("currentRevision"))

        let rowsSource = try String(
            contentsOf: root.appendingPathComponent(
                "FieldEvidenceApp/Domain/Models/PartyAccountabilityPersistenceModelsV1.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(rowsSource.contains("func replace(with successor"))
        XCTAssertTrue(rowsSource.contains("expectedRevision: UInt64"))
        XCTAssertTrue(rowsSource.contains("PartyAccountabilitySnapshotCodecV1.encode"))
    }

    @MainActor
    func testV23P03C40WriterUsesPredecessorRevisionAndReceiptsNewPostImage() throws {
        let root = try Self.makeTemporaryApplicationSupportURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try StoreGenerationFactory(applicationSupportURL: root).openOrBootstrapCurrent()
        let writer = StoreSessionCoordinator(session: session).workspaceWriter
        let workspaceID = try writer.currentRevision().workspaceID
        let firstMutationID = try MutationIDV1(rawValue: Harness.id(101))
        let first = try AuthoritySourceReleaseV1(
            releaseID: Harness.id(102), workspaceID: workspaceID, sourceID: Harness.id(103),
            sourceType: .ownerPolicy, designation: "Owner policy", editionOrRevision: "1",
            retrievedAt: Date(timeIntervalSince1970: 1_800_001_000),
            licenseStorageDisposition: .notStored,
            recordedAt: Date(timeIntervalSince1970: 1_800_001_000),
            mutationID: firstMutationID
        )
        let append = try AuthorityCriterionMutationV1(
            workspaceID: workspaceID, expectedRevision: 0, mutationID: firstMutationID,
            postImage: .appendAuthoritySource(first)
        )
        let firstOutcome = try writer.execute(.applyAuthorityCriterion(append), mutationID: firstMutationID)
        let firstIdentity = try append.affectedIdentity
        XCTAssertEqual(firstOutcome.after.entityRevisions.first { $0.identity == firstIdentity }?.revision, 1)

        let secondMutationID = try MutationIDV1(rawValue: Harness.id(104))
        let second = try AuthoritySourceReleaseV1(
            releaseID: Harness.id(105), workspaceID: workspaceID, sourceID: first.sourceID,
            sourceType: .ownerPolicy, designation: "Owner policy", editionOrRevision: "2",
            retrievedAt: Date(timeIntervalSince1970: 1_800_001_100),
            licenseStorageDisposition: .notStored, supersedesReleaseID: first.releaseID,
            recordedAt: Date(timeIntervalSince1970: 1_800_001_100), revision: 2,
            mutationID: secondMutationID
        )
        let supersede = try AuthorityCriterionMutationV1(
            workspaceID: workspaceID, expectedRevision: 1, mutationID: secondMutationID,
            postImage: .supersedeAuthoritySource(second)
        )
        XCTAssertEqual(try supersede.concurrencyIdentity, firstIdentity)
        let secondIdentity = try supersede.affectedIdentity
        XCTAssertNotEqual(secondIdentity, firstIdentity)
        let secondOutcome = try writer.execute(.applyAuthorityCriterion(supersede), mutationID: secondMutationID)
        XCTAssertEqual(secondOutcome.before.entityRevisions.first { $0.identity == firstIdentity }?.revision, 1)
        XCTAssertEqual(
            secondOutcome.after.entityRevisions.first { $0.identity == secondIdentity }?.revision,
            2
        )
        let receipt = try XCTUnwrap(writer.durableReceipt(mutationID: secondMutationID))
        let typed = try AuthorityCriterionMutationReceiptV1(mutation: supersede, mutationReceipt: receipt)
        XCTAssertEqual(typed.predecessorIdentity, firstIdentity)
        XCTAssertEqual(typed.concurrencyIdentity, firstIdentity)
        XCTAssertEqual(typed.affectedIdentity, secondIdentity)
        XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<AuthoritySourceReleaseRow>()), 2)
    }

    private static func makeTemporaryApplicationSupportURL() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V10_01WorkspaceWriterTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }
}

extension V10_01WorkspaceWriterTests {
#if DEBUG
    @MainActor
    func testHistoricalJournalCheckpointValidationUsesActualReleasedSchemas() async throws {
        for release in [PersistentSchemaReleaseV1.v4, .v9] {
            let root = try Self.makeAbsentApplicationSupportURL(label: release.rawValue)
            defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
            let generationID = UUID()
            let migrationID = UUID()
            let identity = try Self.historicalIdentity()
            let factory = StoreGenerationFactory(applicationSupportURL: root)
            _ = try factory.seedReleasedCheckpointTestFixture(
                release: release,
                generationID: generationID,
                migrationID: migrationID,
                identity: identity
            ) { context in
                let checkpoint: String?
                if release == .v4 {
                    checkpoint = nil
                } else {
                    checkpoint = try Self.historicalCheckpoint([])
                }
                context.insert(WorkspaceMutationStateRow(
                    workspaceID: identity.workspaceID.rawValue,
                    generationID: generationID,
                    activeReplicaID: identity.replicaID.rawValue,
                    mutableSemanticSHA256: checkpoint
                ))
            }
            Self.assertAwaitingIndependentValidation(
                try await factory.openForStartup(recoverOriginalSource: { _ in })
            )
        }
    }

    @MainActor
    func testAggregateTerminalNormalizationRetriesWholePostAndRejectsCandidateDrift() async throws {
        for candidateFault in [
            "none", "pre-retry", "mixed-tuple", "assurance-metadata", "observation",
            "asset-semantics", "base", "revision", "receipt-anchor",
        ] {
        let root = try Self.makeAbsentApplicationSupportURL(
            label: "terminal-normalization-retry-\(candidateFault)"
        )
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let generationID = UUID()
        let migrationID = UUID()
        let identity = try Self.historicalIdentity()
        let timestamp = Date(timeIntervalSince1970: 1_700_030_000)
        let site = Site(id: UUID(), label: "Retry site", timeZoneID: "UTC", createdAt: timestamp)
        let asset = Asset(
            id: UUID(), siteID: site.id,
            packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
            packContentVersion: SignPack.illuminatedSignV1.contentVersion,
            label: "Retry asset", createdAt: timestamp
        )
        let record = Self.historicalWorkflowRecord(assetID: asset.id, timestamp: timestamp)
        let siteIdentity = try WorkspaceEntityIdentityV1(kind: .site, id: site.id)
        let assetIdentity = try WorkspaceEntityIdentityV1(kind: .asset, id: asset.id)
        let workflowIdentity = try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: record.id)
        let siteValue = try Self.historicalItem(
            identity: siteIdentity, revision: 1,
            value: V4BackupSiteDTO(
                id: site.id, schemaVersion: site.schemaVersion, label: site.label,
                address: site.address, timeZoneID: site.timeZoneID,
                createdAt: site.createdAt, updatedAt: site.updatedAt
            )
        )
        let assetValue = try Self.historicalItem(
            identity: assetIdentity, revision: 1,
            value: V4BackupAssetDTO(
                id: asset.id, schemaVersion: asset.schemaVersion, siteID: asset.siteID,
                packID: asset.packID, packSchemaVersion: asset.packSchemaVersion,
                packContentVersion: asset.packContentVersion, label: asset.label,
                createdAt: asset.createdAt, updatedAt: asset.updatedAt
            )
        )
        let workflowValue = try Self.historicalItem(
            identity: workflowIdentity, revision: 1,
            value: Self.historicalWorkflowDTO(record, observationBasisData: nil, temporalContextData: nil)
        )
        let writerInstanceID = UUID()
        let firstMutationID = try MutationIDV1(rawValue: UUID())
        let firstExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: identity.workspaceID, generationID: generationID,
            writerInstanceID: writerInstanceID, workspaceRevision: 0,
            entityRevisions: [
                .init(identity: siteIdentity, revision: 0),
                .init(identity: assetIdentity, revision: 0),
            ]
        )
        let firstEnvelope = try MutationEnvelopeV1(
            request: .init(
                mutationID: firstMutationID, expectedRevision: firstExpected,
                command: .createFirstSign(.init(
                    siteID: site.id,
                    newSite: .init(
                        id: site.id, label: site.label, address: site.address,
                        timeZoneID: site.timeZoneID
                    ),
                    assetID: asset.id, assetLabel: asset.label,
                    packID: asset.packID, packSchemaVersion: asset.packSchemaVersion,
                    packContentVersion: asset.packContentVersion, createdAt: timestamp
                ))
            ),
            identity: identity
        )
        let firstResulting = try WorkspaceExpectedRevisionV1(
            workspaceID: identity.workspaceID, generationID: generationID,
            writerInstanceID: writerInstanceID, workspaceRevision: 1,
            entityRevisions: [
                .init(identity: siteIdentity, revision: 1),
                .init(identity: assetIdentity, revision: 1),
            ]
        )
        let firstReceipt = try MutationReceiptV1(
            identity: .init(
                workspaceID: identity.workspaceID,
                replicaID: identity.replicaID,
                localSequence: 1
            ),
            envelope: firstEnvelope,
            resultingRevision: MutationPortableExpectedRevisionV1(firstResulting),
            postImages: [
                .site(id: site.id, revision: 1, semanticSHA256: siteValue.semanticSHA256),
                .asset(id: asset.id, revision: 1, semanticSHA256: assetValue.semanticSHA256),
            ],
            committedAt: timestamp
        )
        let firstReceiptRow = try MutationReceiptRow(
            envelope: firstEnvelope, receipt: firstReceipt
        )
        let draftMutationID = try MutationIDV1(rawValue: UUID())
        let draftExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: identity.workspaceID, generationID: generationID,
            writerInstanceID: writerInstanceID, workspaceRevision: 1,
            entityRevisions: [
                .init(identity: siteIdentity, revision: 1),
                .init(identity: assetIdentity, revision: 1),
                .init(identity: workflowIdentity, revision: 0),
            ]
        )
        let draftEnvelope = try MutationEnvelopeV1(
            request: .init(
                mutationID: draftMutationID, expectedRevision: draftExpected,
                command: .createCheckDraft(Self.historicalCheckDraftCommand(record))
            ),
            identity: identity
        )
        let draftResulting = try WorkspaceExpectedRevisionV1(
            workspaceID: identity.workspaceID, generationID: generationID,
            writerInstanceID: writerInstanceID, workspaceRevision: 2,
            entityRevisions: [
                .init(identity: siteIdentity, revision: 1),
                .init(identity: assetIdentity, revision: 1),
                .init(identity: workflowIdentity, revision: 1),
            ]
        )
        let draftReceipt = try MutationReceiptV1(
            identity: .init(
                workspaceID: identity.workspaceID,
                replicaID: identity.replicaID,
                localSequence: 2
            ),
            envelope: draftEnvelope,
            resultingRevision: MutationPortableExpectedRevisionV1(draftResulting),
            postImages: [
                .workflowRecord(
                    id: record.id, revision: 1,
                    semanticSHA256: workflowValue.semanticSHA256
                ),
            ],
            committedAt: timestamp
        )
        let draftReceiptRow = try MutationReceiptRow(
            envelope: draftEnvelope, receipt: draftReceipt
        )
        let checkpoint = try Self.historicalCheckpoint([siteValue, assetValue, workflowValue])
        let injection = StoreMigrationFailureInjection(
            aggregateFault: candidateFault == "pre-retry"
                ? .afterAdjacentMarkerSave : .afterFinalCheckpointSave,
            targetRelease: .v53
        )
        let factory = StoreGenerationFactory(
            applicationSupportURL: root,
            migrationFailureInjection: injection
        )
        let sourceModelURL = try factory.seedReleasedCheckpointTestFixture(
            release: .v4,
            generationID: generationID,
            migrationID: migrationID,
            identity: identity
        ) { context in
            context.insert(site)
            context.insert(asset)
            context.insert(record)
            context.insert(firstReceiptRow)
            context.insert(draftReceiptRow)
            context.insert(EntityMutationRevisionRow(
                identity: siteIdentity,
                revision: 1,
                externalProjectionSHA256: siteValue.semanticSHA256
            ))
            context.insert(EntityMutationRevisionRow(identity: assetIdentity, revision: 1))
            context.insert(EntityMutationRevisionRow(identity: workflowIdentity, revision: 1))
            context.insert(WorkspaceMutationStateRow(
                workspaceID: identity.workspaceID.rawValue,
                generationID: generationID,
                activeReplicaID: identity.replicaID.rawValue,
                workspaceRevision: 2,
                lastLocalSequence: 2,
                mutableSemanticSHA256: checkpoint
            ))
        }
        let sourceBytes = try Data(contentsOf: sourceModelURL)
        let sourceSnapshot = try factory.makeRestoreGenerationAuthority()
            .snapshotInstalledGeneration(id: generationID)
        let pointerURL = root.appendingPathComponent("FieldEvidenceData/current.json")
        let pointerBytes = try Data(contentsOf: pointerURL)
        do {
            _ = try await factory.openForStartup(recoverOriginalSource: { _ in })
            XCTFail("Expected the exact post-save fault")
        } catch let boundary as StoreAggregateMigrationFaultBoundaryV1 {
            XCTAssertEqual(
                boundary,
                candidateFault == "pre-retry" ? .afterAdjacentMarkerSave : .afterFinalCheckpointSave
            )
        }
        let interrupted = try XCTUnwrap(
            StoreAggregateMigrationControlV1(applicationSupportURL: root)?.load()
        )
        XCTAssertEqual(interrupted.phase, .migrating)
        XCTAssertEqual(interrupted.authorizedTargetRelease, .v53)
        if candidateFault != "none" && candidateFault != "pre-retry" {
            let candidateURL = factory.restoreStagingGenerationURL(
                id: interrupted.targetGenerationID
            ).appendingPathComponent("model.sqlite")
            let schema = Schema(
                PersistentSchemaV53.models,
                version: PersistentSchemaV53.versionIdentifier
            )
            let configuration = ModelConfiguration(
                "V10_01MixedTerminalTuple",
                schema: schema,
                url: candidateURL,
                cloudKitDatabase: .none
            )
            weak var retainedCandidateContainer: ModelContainer?
            weak var retainedCandidateContext: ModelContext?
            try autoreleasepool {
                let container = try ModelContainer(
                    for: schema,
                    migrationPlan: nil,
                    configurations: [configuration]
                )
                let context = container.mainContext
                context.autosaveEnabled = false
                retainedCandidateContainer = container
                retainedCandidateContext = context
                if candidateFault == "mixed-tuple" {
                    let rows = try context.fetch(FetchDescriptor<EntityMutationRevisionRow>())
                    let row = try XCTUnwrap(rows.first { $0.entityID == asset.id })
                    XCTAssertNotNil(row.externalProjectionSHA256)
                    row.externalProjectionSHA256 = nil
                } else if candidateFault == "assurance-metadata" {
                    let old = try XCTUnwrap(context.fetch(FetchDescriptor<RequirementAssuranceRow>()).first)
                    let snapshot = try old.snapshot()
                    let originalMutationID = old.mutationID
                    context.delete(old)
                    try context.save()
                    let hostileMutationID = UUID(uuidString: "ffffffff-ffff-4fff-bfff-ffffffffffff")!
                    XCTAssertNotEqual(hostileMutationID, originalMutationID)
                    context.insert(try RequirementAssuranceRow(
                        snapshot: snapshot,
                        mutationID: hostileMutationID,
                        createdAt: timestamp,
                        updatedAt: timestamp
                    ))
                } else if candidateFault == "observation" {
                    let row = try XCTUnwrap(context.fetch(FetchDescriptor<ObservationAndTimeRow>()).first)
                    let basis = try row.observationBasisV1()
                    row.observationBasisV1Data = try ObservationAndTimeCodecV1.encode(ObservationBasisV1(
                        kind: basis.kind, method: basis.method, source: basis.source,
                        limitations: basis.limitations + ["Hostile candidate observation"]
                    ))
                } else if candidateFault == "asset-semantics" {
                    let row = try XCTUnwrap(context.fetch(FetchDescriptor<AssetKindBindingEventRow>()).first)
                    context.delete(row)
                } else if candidateFault == "base" {
                    let row = try XCTUnwrap(context.fetch(FetchDescriptor<Asset>()).first)
                    row.label = "Hostile candidate base"
                } else if candidateFault == "revision" {
                    let rows = try context.fetch(FetchDescriptor<EntityMutationRevisionRow>())
                    let row = try XCTUnwrap(rows.first { $0.entityID == asset.id })
                    row.revision = 2
                } else if candidateFault == "receipt-anchor" {
                    let rows = try context.fetch(FetchDescriptor<MutationReceiptRow>())
                    let row = try XCTUnwrap(rows.first {
                        $0.mutationID == firstMutationID.rawValue
                    })
                    XCTAssertEqual(
                        row.commandKind,
                        WorkspaceCommandKindV1.createFirstSign.rawValue
                    )
                    row.commandKind = WorkspaceCommandKindV1.createCheckDraft.rawValue
                }
                try context.save()
            }
            XCTAssertNil(retainedCandidateContext)
            XCTAssertNil(retainedCandidateContainer)
            do {
                _ = try await factory.openForStartup(recoverOriginalSource: { _ in
                    XCTFail("A frozen source must not be recovered again")
                })
                XCTFail("Expected mixed PRE/POST terminal tuple rejection")
            } catch {
                XCTAssertTrue(error is StoreMigrationFailure || error is WorkspaceMutationFailureV1)
            }
        } else {
            Self.assertAwaitingIndependentValidation(
                try await factory.openForStartup(recoverOriginalSource: { _ in
                    XCTFail("A frozen source must not be recovered again")
                })
            )
        }
        XCTAssertEqual(try Data(contentsOf: sourceModelURL), sourceBytes)
        if candidateFault == "none" || candidateFault == "pre-retry" {
            XCTAssertNotEqual(try Data(contentsOf: pointerURL), pointerBytes)
        } else {
            XCTAssertEqual(try Data(contentsOf: pointerURL), pointerBytes)
        }
        let sourceAfter = try factory.makeRestoreGenerationAuthority()
            .snapshotInstalledGeneration(id: generationID)
        XCTAssertEqual(sourceAfter.files, sourceSnapshot.files)
        XCTAssertEqual(sourceAfter.frozenIdentityDigest, sourceSnapshot.frozenIdentityDigest)
        }
    }

    @MainActor
    func testHistoricalTerminalProjectionUsesV4V5V8V9RecipesAndMixedUnchangedRows() async throws {
        for release in [PersistentSchemaReleaseV1.v4, .v5, .v8, .v9] {
            let root = try Self.makeAbsentApplicationSupportURL(label: "\(release.rawValue)-workflow")
            defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
            let generationID = UUID()
            let migrationID = UUID()
            let identity = try Self.historicalIdentity()
            let timestamp = Date(timeIntervalSince1970: 1_700_040_000)
            let site = Site(id: UUID(), label: "Workflow site", timeZoneID: "UTC", createdAt: timestamp)
            let asset = Asset(
                id: UUID(), siteID: site.id,
                packID: SignPack.illuminatedSignV1.packID,
                packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
                packContentVersion: SignPack.illuminatedSignV1.contentVersion,
                label: "Workflow asset", createdAt: timestamp
            )
            let record = Self.historicalWorkflowRecord(assetID: asset.id, timestamp: timestamp)
            let observation = try ObservationAndTimeMigrationV1.migrate(
                existingObservationBasisData: nil,
                existingTemporalContextData: nil,
                couldNotVerifyKey: record.couldNotVerifyKey,
                couldNotVerifyDisplaySnapshot: record.couldNotVerifyDisplaySnapshot,
                couldNotVerifyRegistryVersion: record.couldNotVerifyRegistryVersion,
                observedAtUTC: record.observedAtUTC,
                recordedAtUTC: record.startedAt,
                timeZoneID: record.timeZoneID,
                utcOffsetMinutes: record.utcOffsetMinutes,
                localDate: record.localDate,
                localTime: record.localTime
            )
            var observationBasisData = try XCTUnwrap(observation.observationBasisData)
            var temporalContextData = try XCTUnwrap(observation.temporalContextData)
            if release == .v5 {
                let generatedBasis = try ObservationAndTimeCodecV1.decodeObservationBasis(observationBasisData)
                let generatedTime = try ObservationAndTimeCodecV1.decodeTemporalContext(temporalContextData)
                observationBasisData = try ObservationAndTimeCodecV1.encode(ObservationBasisV1(
                    kind: generatedBasis.kind,
                    method: generatedBasis.method,
                    source: generatedBasis.source,
                    limitations: ["Caller-provided canonical V5 observation"]
                ))
                temporalContextData = try ObservationAndTimeCodecV1.encode(TemporalContextV1(
                    occurredAtUTC: generatedTime.occurredAtUTC,
                    recordedAtUTC: generatedTime.recordedAtUTC.addingTimeInterval(17),
                    localDate: generatedTime.localDate,
                    localTime: generatedTime.localTime,
                    utcOffsetSeconds: generatedTime.utcOffsetSeconds,
                    ianaTimeZoneIdentifier: generatedTime.ianaTimeZoneIdentifier,
                    localTimeDisposition: generatedTime.localTimeDisposition
                ))
                XCTAssertNotEqual(observationBasisData, observation.observationBasisData)
                XCTAssertNotEqual(temporalContextData, observation.temporalContextData)
            }
            let assurance = try RequirementAssuranceRow.blockingUnknownBackfill(
                workflowRecordID: record.id,
                workspaceID: identity.workspaceID.rawValue,
                evaluatedRevision: 1,
                requirementID: "historical.workflow.required",
                requirementVersion: 1,
                requirementTypeID: "historical.workflow",
                policySHA256: String(repeating: "a", count: 64),
                mutationID: migrationID,
                timestamp: timestamp
            )
            let recordDTO = Self.historicalWorkflowDTO(
                record,
                observationBasisData: release.versionIdentifier.major >= 5 ? observationBasisData : nil,
                temporalContextData: release.versionIdentifier.major >= 5 ? temporalContextData : nil
            )
            let workflowValue: HistoricalJournalMutableItemV1
            let workflowIdentity = try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: record.id)
            if release.versionIdentifier.major >= 8 {
                workflowValue = try Self.historicalItem(
                    identity: workflowIdentity,
                    revision: 1,
                    value: HistoricalWorkflowPostImageV8(
                        record: recordDTO,
                        requirementAssurance: try assurance.snapshot()
                    )
                )
            } else {
                workflowValue = try Self.historicalItem(identity: workflowIdentity, revision: 1, value: recordDTO)
            }
            let siteDTO = V4BackupSiteDTO(
                id: site.id, schemaVersion: site.schemaVersion, label: site.label,
                address: site.address, timeZoneID: site.timeZoneID,
                createdAt: site.createdAt, updatedAt: site.updatedAt
            )
            let assetDTO = V4BackupAssetDTO(
                id: asset.id, schemaVersion: asset.schemaVersion, siteID: asset.siteID,
                packID: asset.packID, packSchemaVersion: asset.packSchemaVersion,
                packContentVersion: asset.packContentVersion, label: asset.label,
                createdAt: asset.createdAt, updatedAt: asset.updatedAt
            )
            let siteIdentity = try WorkspaceEntityIdentityV1(kind: .site, id: site.id)
            let assetIdentity = try WorkspaceEntityIdentityV1(kind: .asset, id: asset.id)
            let siteValue = try Self.historicalItem(identity: siteIdentity, revision: 1, value: siteDTO)
            let assetValue = try Self.historicalItem(identity: assetIdentity, revision: 1, value: assetDTO)
            let checkpoint = try Self.historicalCheckpoint([siteValue, assetValue, workflowValue])
            let factory = StoreGenerationFactory(applicationSupportURL: root)
            _ = try factory.seedReleasedCheckpointTestFixture(
                release: release,
                generationID: generationID,
                migrationID: migrationID,
                identity: identity
            ) { context in
                context.insert(site)
                context.insert(asset)
                context.insert(record)
                if release.versionIdentifier.major >= 5 {
                    context.insert(try ObservationAndTimeRow(
                        recordID: record.id,
                        observationBasisV1Data: observationBasisData,
                        temporalContextV1Data: temporalContextData
                    ))
                }
                if release.versionIdentifier.major >= 8 { context.insert(assurance) }
                if release.versionIdentifier.major < 8 {
                    let writerInstanceID = UUID()
                    let firstMutationID = try MutationIDV1(rawValue: UUID())
                    let firstExpected = try WorkspaceExpectedRevisionV1(
                        workspaceID: identity.workspaceID,
                        generationID: generationID,
                        writerInstanceID: writerInstanceID,
                        workspaceRevision: 0,
                        entityRevisions: [
                            .init(identity: siteIdentity, revision: 0),
                            .init(identity: assetIdentity, revision: 0),
                        ]
                    )
                    let firstEnvelope = try MutationEnvelopeV1(
                        request: .init(
                            mutationID: firstMutationID,
                            expectedRevision: firstExpected,
                            command: .createFirstSign(.init(
                                siteID: site.id,
                                newSite: .init(
                                    id: site.id, label: site.label,
                                    address: site.address, timeZoneID: site.timeZoneID
                                ),
                                assetID: asset.id, assetLabel: asset.label,
                                packID: asset.packID,
                                packSchemaVersion: asset.packSchemaVersion,
                                packContentVersion: asset.packContentVersion,
                                createdAt: timestamp
                            ))
                        ),
                        identity: identity
                    )
                    let firstResulting = try WorkspaceExpectedRevisionV1(
                        workspaceID: identity.workspaceID,
                        generationID: generationID,
                        writerInstanceID: writerInstanceID,
                        workspaceRevision: 1,
                        entityRevisions: [
                            .init(identity: siteIdentity, revision: 1),
                            .init(identity: assetIdentity, revision: 1),
                        ]
                    )
                    let firstReceipt = try MutationReceiptV1(
                        identity: .init(
                            workspaceID: identity.workspaceID,
                            replicaID: identity.replicaID,
                            localSequence: 1
                        ),
                        envelope: firstEnvelope,
                        resultingRevision: MutationPortableExpectedRevisionV1(firstResulting),
                        postImages: [
                            .site(
                                id: site.id, revision: 1,
                                semanticSHA256: siteValue.semanticSHA256
                            ),
                            .asset(id: asset.id, revision: 1, semanticSHA256: assetValue.semanticSHA256),
                        ],
                        committedAt: timestamp
                    )
                    context.insert(try MutationReceiptRow(
                        envelope: firstEnvelope, receipt: firstReceipt
                    ))
                    let draftMutationID = try MutationIDV1(rawValue: UUID())
                    let draftExpected = try WorkspaceExpectedRevisionV1(
                        workspaceID: identity.workspaceID,
                        generationID: generationID,
                        writerInstanceID: writerInstanceID,
                        workspaceRevision: 1,
                        entityRevisions: [
                            .init(identity: siteIdentity, revision: 1),
                            .init(identity: assetIdentity, revision: 1),
                            .init(identity: workflowIdentity, revision: 0),
                        ]
                    )
                    let draftEnvelope = try MutationEnvelopeV1(
                        request: .init(
                            mutationID: draftMutationID,
                            expectedRevision: draftExpected,
                            command: .createCheckDraft(Self.historicalCheckDraftCommand(
                                record,
                                observationBasisData: release == .v5
                                    ? observationBasisData : nil,
                                temporalContextData: release == .v5
                                    ? temporalContextData : nil
                            ))
                        ),
                        identity: identity
                    )
                    let draftResulting = try WorkspaceExpectedRevisionV1(
                        workspaceID: identity.workspaceID,
                        generationID: generationID,
                        writerInstanceID: writerInstanceID,
                        workspaceRevision: 2,
                        entityRevisions: [
                            .init(identity: siteIdentity, revision: 1),
                            .init(identity: assetIdentity, revision: 1),
                            .init(identity: workflowIdentity, revision: 1),
                        ]
                    )
                    let draftReceipt = try MutationReceiptV1(
                        identity: .init(
                            workspaceID: identity.workspaceID,
                            replicaID: identity.replicaID,
                            localSequence: 2
                        ),
                        envelope: draftEnvelope,
                        resultingRevision: MutationPortableExpectedRevisionV1(draftResulting),
                        postImages: [
                            .workflowRecord(
                                id: record.id, revision: 1,
                                semanticSHA256: workflowValue.semanticSHA256
                            ),
                        ],
                        committedAt: timestamp
                    )
                    context.insert(try MutationReceiptRow(
                        envelope: draftEnvelope, receipt: draftReceipt
                    ))
                }
                context.insert(EntityMutationRevisionRow(
                    identity: siteIdentity,
                    revision: 1,
                    externalProjectionSHA256: siteValue.semanticSHA256
                ))
                context.insert(EntityMutationRevisionRow(
                    identity: assetIdentity,
                    revision: 1,
                    externalProjectionSHA256: release.versionIdentifier.major < 8
                        ? nil : assetValue.semanticSHA256
                ))
                context.insert(EntityMutationRevisionRow(
                    identity: workflowIdentity,
                    revision: 1,
                    externalProjectionSHA256: release.versionIdentifier.major < 8
                        ? nil : workflowValue.semanticSHA256
                ))
                context.insert(WorkspaceMutationStateRow(
                    workspaceID: identity.workspaceID.rawValue,
                    generationID: generationID,
                    activeReplicaID: identity.replicaID.rawValue,
                    workspaceRevision: release.versionIdentifier.major < 8 ? 2 : 0,
                    lastLocalSequence: release.versionIdentifier.major < 8 ? 2 : 0,
                    mutableSemanticSHA256: checkpoint
                ))
            }
            Self.assertAwaitingIndependentValidation(
                try await factory.openForStartup(recoverOriginalSource: { _ in })
            )
        }
    }

    @MainActor
    func testV9MixesOldReceiptBridgeWithIndependentCurrentWorkflowRecipe() async throws {
        let root = try Self.makeAbsentApplicationSupportURL(label: "V9-mixed-workflow-recipes")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let generationID = UUID(), migrationID = UUID(), identity = try Self.historicalIdentity()
        let timestamp = Date(timeIntervalSince1970: 1_700_045_000)
        let site = Site(id: UUID(), label: "Mixed V9 site", timeZoneID: "UTC", createdAt: timestamp)
        let asset = Asset(id: UUID(), siteID: site.id, packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
            packContentVersion: SignPack.illuminatedSignV1.contentVersion,
            label: "Mixed V9 asset", createdAt: timestamp)
        let old = Self.historicalWorkflowRecord(assetID: asset.id, timestamp: timestamp)
        let current = Self.historicalWorkflowRecord(assetID: asset.id, timestamp: timestamp.addingTimeInterval(60))
        func observation(_ record: WorkflowRecord) throws -> ObservationAndTimeMigrationResultV1 {
            try ObservationAndTimeMigrationV1.migrate(existingObservationBasisData: nil,
                existingTemporalContextData: nil, couldNotVerifyKey: record.couldNotVerifyKey,
                couldNotVerifyDisplaySnapshot: record.couldNotVerifyDisplaySnapshot,
                couldNotVerifyRegistryVersion: record.couldNotVerifyRegistryVersion,
                observedAtUTC: record.observedAtUTC, recordedAtUTC: record.startedAt,
                timeZoneID: record.timeZoneID, utcOffsetMinutes: record.utcOffsetMinutes,
                localDate: record.localDate, localTime: record.localTime)
        }
        let oldObservation = try observation(old), currentObservation = try observation(current)
        let oldBasis = try XCTUnwrap(oldObservation.observationBasisData)
        let oldTime = try XCTUnwrap(oldObservation.temporalContextData)
        let currentBasis = try XCTUnwrap(currentObservation.observationBasisData)
        let currentTime = try XCTUnwrap(currentObservation.temporalContextData)
        let oldAssurance = try RequirementAssuranceRow.blockingUnknownBackfill(
            workflowRecordID: old.id, workspaceID: identity.workspaceID.rawValue,
            evaluatedRevision: 1, requirementID: "legacy_assurance_unknown", requirementVersion: 1,
            requirementTypeID: "legacy_assurance_unknown",
            policySHA256: StoreMigrationCanonicalJSONV1.sha256(Data("legacy-assurance-unknown-v1".utf8)),
            mutationID: old.id, timestamp: old.startedAt)
        let currentAssurance = try RequirementAssuranceRow.blockingUnknownBackfill(
            workflowRecordID: current.id, workspaceID: identity.workspaceID.rawValue,
            evaluatedRevision: 1, requirementID: "accepted.current.requirement", requirementVersion: 7,
            requirementTypeID: "accepted.current.type", policySHA256: String(repeating: "c", count: 64),
            mutationID: migrationID, timestamp: current.startedAt)
        let oldIdentity = try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: old.id)
        let currentIdentity = try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: current.id)
        let oldDTO = Self.historicalWorkflowDTO(old, observationBasisData: oldBasis, temporalContextData: oldTime)
        let currentDTO = Self.historicalWorkflowDTO(current, observationBasisData: currentBasis, temporalContextData: currentTime)
        let oldV5 = try Self.historicalItem(identity: oldIdentity, revision: 1, value: oldDTO)
        let oldV8 = try Self.historicalItem(identity: oldIdentity, revision: 1,
            value: HistoricalWorkflowPostImageV8(record: oldDTO, requirementAssurance: try oldAssurance.snapshot()))
        let currentV8 = try Self.historicalItem(identity: currentIdentity, revision: 1,
            value: HistoricalWorkflowPostImageV8(record: currentDTO, requirementAssurance: try currentAssurance.snapshot()))
        let siteIdentity = try WorkspaceEntityIdentityV1(kind: .site, id: site.id)
        let assetIdentity = try WorkspaceEntityIdentityV1(kind: .asset, id: asset.id)
        let siteItem = try Self.historicalItem(identity: siteIdentity, revision: 1,
            value: V4BackupSiteDTO(id: site.id, schemaVersion: site.schemaVersion, label: site.label,
                address: site.address, timeZoneID: site.timeZoneID, createdAt: site.createdAt, updatedAt: site.updatedAt))
        let assetItem = try Self.historicalItem(identity: assetIdentity, revision: 1,
            value: V4BackupAssetDTO(id: asset.id, schemaVersion: asset.schemaVersion, siteID: asset.siteID,
                packID: asset.packID, packSchemaVersion: asset.packSchemaVersion,
                packContentVersion: asset.packContentVersion, label: asset.label,
                createdAt: asset.createdAt, updatedAt: asset.updatedAt))
        let writerInstanceID = UUID()
        let firstMutationID = try MutationIDV1(rawValue: UUID())
        let firstExpected = try WorkspaceExpectedRevisionV1(workspaceID: identity.workspaceID,
            generationID: generationID, writerInstanceID: writerInstanceID, workspaceRevision: 0,
            entityRevisions: [
                .init(identity: siteIdentity, revision: 0),
                .init(identity: assetIdentity, revision: 0),
            ])
        let firstEnvelope = try MutationEnvelopeV1(request: .init(mutationID: firstMutationID,
            expectedRevision: firstExpected, command: .createFirstSign(.init(
                siteID: site.id,
                newSite: .init(id: site.id, label: site.label, address: site.address,
                    timeZoneID: site.timeZoneID),
                assetID: asset.id, assetLabel: asset.label, packID: asset.packID,
                packSchemaVersion: asset.packSchemaVersion,
                packContentVersion: asset.packContentVersion, createdAt: timestamp))),
            identity: identity)
        let firstResulting = try WorkspaceExpectedRevisionV1(workspaceID: identity.workspaceID,
            generationID: generationID, writerInstanceID: writerInstanceID, workspaceRevision: 1,
            entityRevisions: [
                .init(identity: siteIdentity, revision: 1),
                .init(identity: assetIdentity, revision: 1),
            ])
        let firstReceipt = try MutationReceiptV1(identity: .init(
            workspaceID: identity.workspaceID, replicaID: identity.replicaID, localSequence: 1),
            envelope: firstEnvelope,
            resultingRevision: MutationPortableExpectedRevisionV1(firstResulting),
            postImages: [
                .site(id: site.id, revision: 1, semanticSHA256: siteItem.semanticSHA256),
                .asset(id: asset.id, revision: 1, semanticSHA256: assetItem.semanticSHA256),
            ], committedAt: timestamp)
        let draftMutationID = try MutationIDV1(rawValue: UUID())
        let draftExpected = try WorkspaceExpectedRevisionV1(workspaceID: identity.workspaceID,
            generationID: generationID, writerInstanceID: writerInstanceID, workspaceRevision: 1,
            entityRevisions: [
                .init(identity: siteIdentity, revision: 1),
                .init(identity: assetIdentity, revision: 1),
                .init(identity: oldIdentity, revision: 0),
            ])
        let draftEnvelope = try MutationEnvelopeV1(request: .init(mutationID: draftMutationID,
            expectedRevision: draftExpected,
            command: .createCheckDraft(Self.historicalCheckDraftCommand(
                old, observationBasisData: oldBasis, temporalContextData: oldTime
            ))), identity: identity)
        let draftResulting = try WorkspaceExpectedRevisionV1(workspaceID: identity.workspaceID,
            generationID: generationID, writerInstanceID: writerInstanceID, workspaceRevision: 2,
            entityRevisions: [
                .init(identity: siteIdentity, revision: 1),
                .init(identity: assetIdentity, revision: 1),
                .init(identity: oldIdentity, revision: 1),
            ])
        let draftReceipt = try MutationReceiptV1(identity: .init(workspaceID: identity.workspaceID,
            replicaID: identity.replicaID, localSequence: 2), envelope: draftEnvelope,
            resultingRevision: MutationPortableExpectedRevisionV1(draftResulting),
            postImages: [
                .workflowRecord(id: old.id, revision: 1, semanticSHA256: oldV5.semanticSHA256),
            ], committedAt: timestamp)
        let sourceReceiptData = try draftReceipt.canonicalData()
        let checkpoint = try Self.historicalCheckpoint([siteItem, assetItem, oldV8, currentV8])
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        _ = try factory.seedReleasedCheckpointTestFixture(release: .v9, generationID: generationID,
            migrationID: migrationID, identity: identity) { context in
            context.insert(site); context.insert(asset)
            context.insert(old); context.insert(current)
            context.insert(try ObservationAndTimeRow(recordID: old.id,
                observationBasisV1Data: oldBasis, temporalContextV1Data: oldTime))
            context.insert(try ObservationAndTimeRow(recordID: current.id,
                observationBasisV1Data: currentBasis, temporalContextV1Data: currentTime))
            context.insert(oldAssurance); context.insert(currentAssurance)
            context.insert(try MutationReceiptRow(envelope: firstEnvelope, receipt: firstReceipt))
            context.insert(try MutationReceiptRow(envelope: draftEnvelope, receipt: draftReceipt))
            context.insert(EntityMutationRevisionRow(identity: siteIdentity, revision: 1,
                externalProjectionSHA256: siteItem.semanticSHA256))
            context.insert(EntityMutationRevisionRow(identity: assetIdentity, revision: 1,
                externalProjectionSHA256: assetItem.semanticSHA256))
            context.insert(EntityMutationRevisionRow(identity: oldIdentity, revision: 1,
                externalProjectionSHA256: oldV5.semanticSHA256))
            context.insert(EntityMutationRevisionRow(identity: currentIdentity, revision: 1,
                externalProjectionSHA256: currentV8.semanticSHA256))
            context.insert(WorkspaceMutationStateRow(workspaceID: identity.workspaceID.rawValue,
                generationID: generationID, activeReplicaID: identity.replicaID.rawValue,
                workspaceRevision: 2, lastLocalSequence: 2, mutableSemanticSHA256: checkpoint))
        }
        Self.assertAwaitingIndependentValidation(try await factory.openForStartup(recoverOriginalSource: { _ in }))
        let migrated = try XCTUnwrap(StoreAggregateMigrationControlV1(applicationSupportURL: root)?.load())
        let schema = Schema(PersistentSchemaV53.models, version: PersistentSchemaV53.versionIdentifier)
        let configuration = ModelConfiguration("V10_01V9ReceiptInspection", schema: schema,
            url: factory.installedGenerationURL(id: migrated.targetGenerationID).appendingPathComponent("model.sqlite"),
            allowsSave: false, cloudKitDatabase: .none)
        try autoreleasepool {
            let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [configuration])
            container.mainContext.autosaveEnabled = false
            let rows = try container.mainContext.fetch(FetchDescriptor<MutationReceiptRow>())
            XCTAssertEqual(
                try XCTUnwrap(rows.first { $0.mutationID == draftMutationID.rawValue }).receiptData,
                sourceReceiptData
            )
        }
    }

    @MainActor
    func testV4RejectsLaterCommandBeforeReferenceFetchWithoutChangingSource() async throws {
        let root = try Self.makeAbsentApplicationSupportURL(label: "V4-future-command")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let generationID = UUID()
        let migrationID = UUID()
        let identity = try Self.historicalIdentity()
        let siteID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_050_000)
        let site = Site(
            id: siteID, label: "Historical site", timeZoneID: "UTC",
            createdAt: timestamp, updatedAt: timestamp
        )
        let siteIdentity = try WorkspaceEntityIdentityV1(kind: .site, id: siteID)
        let siteDTO = V4BackupSiteDTO(
            id: site.id, schemaVersion: site.schemaVersion, label: site.label,
            address: site.address, timeZoneID: site.timeZoneID,
            createdAt: site.createdAt, updatedAt: site.updatedAt
        )
        let siteItem = try Self.historicalItem(identity: siteIdentity, revision: 1, value: siteDTO)
        let mutationID = try MutationIDV1(rawValue: UUID())
        let actor = try LocalActorReferenceV1(
            actorReferenceID: UUID(), workspaceID: identity.workspaceID,
            displayName: "Historical recorder"
        )
        let recordedBy = try ActorSnapshotV1(
            snapshotID: UUID(), workspaceID: identity.workspaceID, actor: actor,
            responsibility: .recordedBy, displayNameAtTime: actor.displayName,
            capturedAt: timestamp
        )
        func reference(_ evidenceID: String, _ digest: Character) -> PairedObservationReferenceV1 {
            PairedObservationReferenceV1(
                workspaceID: identity.workspaceID, evidenceID: evidenceID,
                evidenceSHA256: String(repeating: String(digest), count: 64),
                evidenceRevision: 1, assetID: UUID(), assetRevision: 1,
                controlGroupID: "historical-control", purpose: .conditionComparison,
                purposeRevision: 1, planReferenceSHA256: nil,
                viewpointReferenceSHA256: String(repeating: "c", count: 64),
                temporalBucketID: "historical-bucket",
                surfaceWeatherBasisSHA256: String(repeating: "d", count: 64),
                measurementMethodID: "historical-method"
            )
        }
        let firstReference = reference("historical-evidence-a", "a")
        let secondReference = PairedObservationReferenceV1(
            workspaceID: identity.workspaceID, evidenceID: "historical-evidence-b",
            evidenceSHA256: String(repeating: "b", count: 64),
            evidenceRevision: 1, assetID: firstReference.assetID, assetRevision: 1,
            controlGroupID: firstReference.controlGroupID, purpose: firstReference.purpose,
            purposeRevision: 1, planReferenceSHA256: firstReference.planReferenceSHA256,
            viewpointReferenceSHA256: firstReference.viewpointReferenceSHA256,
            temporalBucketID: firstReference.temporalBucketID,
            surfaceWeatherBasisSHA256: firstReference.surfaceWeatherBasisSHA256,
            measurementMethodID: firstReference.measurementMethodID
        )
        let pair = try PairedObservationLinkV1(
            linkID: UUID(), workspaceID: identity.workspaceID,
            first: firstReference, second: secondReference, predecessor: nil,
            revision: 1, mutationID: mutationID, recordedBy: recordedBy,
            recordedAt: timestamp
        )
        let laterOperation = EvidenceContextWriteOperationV1.appendPair(value: pair, predecessor: nil)
        let laterIdentity = try laterOperation.concurrencyIdentity
        let laterExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: identity.workspaceID, generationID: generationID,
            writerInstanceID: UUID(), workspaceRevision: 0,
            entityRevisions: [.init(identity: laterIdentity, revision: 0)]
        )
        let laterEnvelope = try MutationEnvelopeV1(
            request: .init(
                mutationID: mutationID,
                expectedRevision: laterExpected,
                command: .applyEvidenceContext(laterOperation)
            ),
            identity: identity
        )
        let laterResult = try WorkspaceExpectedRevisionV1(
            workspaceID: identity.workspaceID, generationID: generationID,
            writerInstanceID: UUID(), workspaceRevision: 1,
            entityRevisions: [.init(identity: laterIdentity, revision: 1)]
        )
        let laterReceipt = try MutationReceiptV1(
            identity: .init(
                workspaceID: identity.workspaceID,
                replicaID: identity.replicaID,
                localSequence: 1
            ),
            envelope: laterEnvelope,
            resultingRevision: MutationPortableExpectedRevisionV1(laterResult),
            postImages: [try laterOperation.mutationPostImage],
            committedAt: timestamp
        )
        let futureRow = try MutationReceiptRow(envelope: laterEnvelope, receipt: laterReceipt)
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let modelURL = try factory.seedReleasedCheckpointTestFixture(
            release: .v4,
            generationID: generationID,
            migrationID: migrationID,
            identity: identity
        ) { context in
            context.insert(site)
            context.insert(futureRow)
            context.insert(EntityMutationRevisionRow(identity: siteIdentity, revision: 1))
            context.insert(WorkspaceMutationStateRow(
                workspaceID: identity.workspaceID.rawValue,
                generationID: generationID,
                activeReplicaID: identity.replicaID.rawValue,
                workspaceRevision: 1,
                lastLocalSequence: 1,
                mutableSemanticSHA256: try Self.historicalCheckpoint([siteItem])
            ))
        }
        let pointerURL = root.appendingPathComponent("FieldEvidenceData/current.json")
        let pointerBefore = try Data(contentsOf: pointerURL)
        let sourceBytesBefore = try Data(contentsOf: modelURL)
        let sourceSnapshotBefore = try factory.makeRestoreGenerationAuthority()
            .snapshotInstalledGeneration(id: generationID)
        let installedParent = factory.installedGenerationURL(id: UUID()).deletingLastPathComponent()
        let stagingParent = factory.restoreStagingGenerationURL(id: UUID()).deletingLastPathComponent()
        let installedBefore = Self.directoryEntryNames(at: installedParent)
        let stagingBefore = Self.directoryEntryNames(at: stagingParent)
        do {
            _ = try await factory.openForStartup(recoverOriginalSource: { _ in })
            XCTFail("Expected a V30 command in a V4 receipt to fail before its missing-model fetch")
        } catch {
            XCTAssertTrue(error is StoreMigrationFailure || error is WorkspaceMutationFailureV1)
        }
        XCTAssertEqual(try Data(contentsOf: pointerURL), pointerBefore)
        XCTAssertEqual(try Data(contentsOf: modelURL), sourceBytesBefore)
        let sourceSnapshotAfter = try factory.makeRestoreGenerationAuthority()
            .snapshotInstalledGeneration(id: generationID)
        XCTAssertEqual(sourceSnapshotAfter.files, sourceSnapshotBefore.files)
        XCTAssertEqual(sourceSnapshotAfter.sourceTreeDigest, sourceSnapshotBefore.sourceTreeDigest)
        XCTAssertEqual(sourceSnapshotAfter.frozenIdentityDigest, sourceSnapshotBefore.frozenIdentityDigest)
        XCTAssertEqual(Self.directoryEntryNames(at: installedParent), installedBefore)
        XCTAssertEqual(Self.directoryEntryNames(at: stagingParent), stagingBefore)
        let control = try XCTUnwrap(StoreAggregateMigrationControlV1(applicationSupportURL: root))
        if let journal = try control.load() {
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: factory.installedGenerationURL(id: journal.targetGenerationID).path
            ))
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: factory.restoreStagingGenerationURL(id: journal.targetGenerationID).path
            ))
        }
    }

    @MainActor
    func testV4AcceptsCanonicalReceiptMirrorsReversalBasisAndQuarantine() async throws {
        let root = try Self.makeAbsentApplicationSupportURL(label: "V4-journal-history")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let generationID = UUID()
        let migrationID = UUID()
        let identity = try Self.historicalIdentity()
        let siteID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_060_000)
        let site = Site(
            id: siteID, label: "Historical site", timeZoneID: "UTC",
            createdAt: timestamp, updatedAt: timestamp
        )
        let entity = try WorkspaceEntityIdentityV1(kind: .site, id: siteID)
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: identity.workspaceID, generationID: generationID,
            writerInstanceID: UUID(), workspaceRevision: 0,
            entityRevisions: [.init(identity: entity, revision: 0)]
        )
        let mutationID = try MutationIDV1(rawValue: UUID())
        let command = WorkspaceCommandV1.updateSiteTimeZone(.init(
            siteID: siteID, timeZoneID: "UTC", confirmedAt: timestamp
        ))
        let plan = try SemanticReversalPlanV1(
            mutationID: mutationID, commandKind: .updateSiteTimeZone,
            expectedRevision: expected, prospectiveTargets: [entity],
            requiredSemanticValues: [.init(key: "before", value: "UTC")],
            contentReferences: [], dependencyGraph: [], conflicts: [],
            compensatingCommands: [command]
        )
        let envelope = try MutationEnvelopeV1(
            request: .init(mutationID: mutationID, expectedRevision: expected, command: command),
            identity: identity,
            reversalPlanDigest: plan.planDigest
        )
        let resulting = try WorkspaceExpectedRevisionV1(
            workspaceID: identity.workspaceID, generationID: generationID,
            writerInstanceID: UUID(), workspaceRevision: 1,
            entityRevisions: [.init(identity: entity, revision: 1)]
        )
        let siteDTO = V4BackupSiteDTO(
            id: site.id, schemaVersion: site.schemaVersion, label: site.label,
            address: site.address, timeZoneID: site.timeZoneID,
            createdAt: site.createdAt, updatedAt: site.updatedAt
        )
        let item = try Self.historicalItem(identity: entity, revision: 1, value: siteDTO)
        let receipt = try MutationReceiptV1(
            identity: .init(workspaceID: identity.workspaceID, replicaID: identity.replicaID, localSequence: 1),
            envelope: envelope,
            resultingRevision: MutationPortableExpectedRevisionV1(resulting),
            postImages: [.site(id: siteID, revision: 1, semanticSHA256: item.semanticSHA256)],
            committedAt: timestamp
        )
        let basis = try ReversalBasisV1(
            targetMutationID: mutationID,
            targetReceiptIdentity: receipt.identity,
            plan: plan
        )
        let row = try MutationReceiptRow(envelope: envelope, receipt: receipt, reversalBasis: basis)
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        _ = try factory.seedReleasedCheckpointTestFixture(
            release: .v4, generationID: generationID, migrationID: migrationID, identity: identity
        ) { context in
            context.insert(site)
            context.insert(row)
            context.insert(MutationQuarantineRow(
                workspaceID: identity.workspaceID, mutationID: mutationID,
                identityDomain: .mutationEnvelope,
                acceptedIdentitySHA256: try envelope.canonicalSHA256(),
                conflictingIdentitySHA256: String(repeating: "f", count: 64),
                detectedAt: timestamp
            ))
            context.insert(EntityMutationRevisionRow(identity: entity, revision: 1))
            context.insert(WorkspaceMutationStateRow(
                workspaceID: identity.workspaceID.rawValue, generationID: generationID,
                activeReplicaID: identity.replicaID.rawValue, workspaceRevision: 1,
                lastLocalSequence: 1,
                mutableSemanticSHA256: try Self.historicalCheckpoint([item])
            ))
        }
        Self.assertAwaitingIndependentValidation(
            try await factory.openForStartup(recoverOriginalSource: { _ in })
        )

        for hostile in ["receipt-mirror", "reversal-mirror", "quarantine-mirror"] {
            let hostileRoot = try Self.makeAbsentApplicationSupportURL(label: "V4-\(hostile)")
            defer { try? FileManager.default.removeItem(at: hostileRoot.deletingLastPathComponent()) }
            let hostileFactory = StoreGenerationFactory(applicationSupportURL: hostileRoot)
            let hostileRow = try MutationReceiptRow(
                envelope: envelope, receipt: receipt, reversalBasis: basis
            )
            if hostile == "receipt-mirror" {
                hostileRow.commandKind = WorkspaceCommandKindV1.createCheckDraft.rawValue
            } else if hostile == "reversal-mirror" {
                hostileRow.reversalBasisSHA256 = String(repeating: "e", count: 64)
            }
            let acceptedDigest = hostile == "quarantine-mirror"
                ? String(repeating: "e", count: 64)
                : try envelope.canonicalSHA256()
            let hostileModelURL = try hostileFactory.seedReleasedCheckpointTestFixture(
                release: .v4, generationID: generationID,
                migrationID: migrationID, identity: identity
            ) { context in
                context.insert(Site(
                    id: siteDTO.id, label: siteDTO.label, address: siteDTO.address,
                    timeZoneID: siteDTO.timeZoneID, createdAt: siteDTO.createdAt,
                    updatedAt: siteDTO.updatedAt
                ))
                context.insert(hostileRow)
                context.insert(MutationQuarantineRow(
                    workspaceID: identity.workspaceID, mutationID: mutationID,
                    identityDomain: .mutationEnvelope,
                    acceptedIdentitySHA256: acceptedDigest,
                    conflictingIdentitySHA256: String(repeating: "f", count: 64),
                    detectedAt: timestamp
                ))
                context.insert(EntityMutationRevisionRow(identity: entity, revision: 1))
                context.insert(WorkspaceMutationStateRow(
                    workspaceID: identity.workspaceID.rawValue,
                    generationID: generationID,
                    activeReplicaID: identity.replicaID.rawValue,
                    workspaceRevision: 1, lastLocalSequence: 1,
                    mutableSemanticSHA256: try Self.historicalCheckpoint([item])
                ))
            }
            let pointerURL = hostileRoot.appendingPathComponent("FieldEvidenceData/current.json")
            let pointerBefore = try Data(contentsOf: pointerURL)
            let sourceBefore = try Data(contentsOf: hostileModelURL)
            do {
                _ = try await hostileFactory.openForStartup(recoverOriginalSource: { _ in })
                XCTFail("Expected \(hostile) corruption to fail closed")
            } catch {
                XCTAssertTrue(error is StoreMigrationFailure || error is WorkspaceMutationFailureV1)
            }
            XCTAssertEqual(try Data(contentsOf: pointerURL), pointerBefore)
            XCTAssertEqual(try Data(contentsOf: hostileModelURL), sourceBefore)
            if let journal = try StoreAggregateMigrationControlV1(applicationSupportURL: hostileRoot)?.load() {
                XCTAssertFalse(FileManager.default.fileExists(
                    atPath: hostileFactory.installedGenerationURL(id: journal.targetGenerationID).path
                ))
                XCTAssertFalse(FileManager.default.fileExists(
                    atPath: hostileFactory.restoreStagingGenerationURL(id: journal.targetGenerationID).path
                ))
            }
        }
    }

    @MainActor
    func testV10HistoricalAssetBackfillAcceptsOnlyItsFrozenV9Checkpoint() async throws {
        let root = try Self.makeAbsentApplicationSupportURL(label: "V10-asset-backfill")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let generationID = UUID()
        let migrationID = UUID()
        let identity = try Self.historicalIdentity()
        let siteID = UUID()
        let assetID = UUID()
        let recordedAt = Date(timeIntervalSince1970: 1_700_100_000)
        let site = Site(id: siteID, label: "V10 site", timeZoneID: "UTC", createdAt: recordedAt)
        let asset = Asset(
            id: assetID,
            siteID: siteID,
            packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
            packContentVersion: SignPack.illuminatedSignV1.contentVersion,
            label: "V10 asset",
            createdAt: recordedAt
        )
        let siteIdentity = try WorkspaceEntityIdentityV1(kind: .site, id: siteID)
        let assetIdentity = try WorkspaceEntityIdentityV1(kind: .asset, id: assetID)
        let siteDTO = V4BackupSiteDTO(
            id: site.id, schemaVersion: site.schemaVersion, label: site.label,
            address: site.address, timeZoneID: site.timeZoneID,
            createdAt: site.createdAt, updatedAt: site.updatedAt
        )
        let assetDTO = V4BackupAssetDTO(
            id: asset.id, schemaVersion: asset.schemaVersion, siteID: asset.siteID,
            packID: asset.packID, packSchemaVersion: asset.packSchemaVersion,
            packContentVersion: asset.packContentVersion, label: asset.label,
            createdAt: asset.createdAt, updatedAt: asset.updatedAt
        )
        let checkpoint = try Self.historicalCheckpoint([
            try Self.historicalItem(identity: siteIdentity, value: siteDTO),
            try Self.historicalItem(identity: assetIdentity, value: assetDTO),
        ])
        let catalog = try BundledInspectionPackageRegistryV2.shippingAssetSemanticCatalog()
        let mutationID = try MutationIDV1(rawValue: migrationID)
        let kindEventID = Self.historicalAssetSemanticUUID(
            domain: "asset-semantics/legacy-kind-binding/v1",
            workspaceID: identity.workspaceID.rawValue,
            assetID: assetID
        )
        let kind = try AssetKindBindingEventV1.canonical(
            eventID: kindEventID,
            workspaceID: identity.workspaceID,
            assetID: assetID,
            catalogRelease: catalog.reference,
            semanticID: AssetSemanticPersistenceReleaseV1.acceptedLegacySignSemanticID,
            predecessorEventID: nil,
            revision: 1,
            mutationID: mutationID,
            recordedAt: recordedAt
        )
        let workflow = try AssetWorkflowCapabilityBindingEventV1(
            eventID: Self.historicalAssetSemanticUUID(
                domain: "asset-semantics/legacy-workflow-binding/v1",
                workspaceID: identity.workspaceID.rawValue,
                assetID: assetID
            ),
            workspaceID: identity.workspaceID,
            assetID: assetID,
            kindBindingEventID: kindEventID,
            kindBindingRevision: 1,
            workflowPackageRelease: catalog.packageRelease,
            capabilityIDs: [],
            disposition: .bound,
            predecessorEventID: nil,
            revision: 1,
            mutationID: mutationID,
            recordedAt: recordedAt
        )
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        _ = try factory.seedReleasedCheckpointTestFixture(
            release: .v10,
            generationID: generationID,
            migrationID: migrationID,
            identity: identity
        ) { context in
            context.insert(site)
            context.insert(asset)
            context.insert(try AssetKindBindingEventRow(kind))
            context.insert(try AssetWorkflowCapabilityBindingEventRow(workflow))
            context.insert(WorkspaceMutationStateRow(
                workspaceID: identity.workspaceID.rawValue,
                generationID: generationID,
                activeReplicaID: identity.replicaID.rawValue,
                mutableSemanticSHA256: checkpoint
            ))
        }
        Self.assertAwaitingIndependentValidation(
            try await factory.openForStartup(recoverOriginalSource: { _ in })
        )

        let hostileRoot = try Self.makeAbsentApplicationSupportURL(label: "V10-malformed-backfill")
        defer { try? FileManager.default.removeItem(at: hostileRoot.deletingLastPathComponent()) }
        let hostileGenerationID = UUID()
        let malformedKindEventID = UUID()
        let malformedKind = try AssetKindBindingEventV1.canonical(
            eventID: malformedKindEventID,
            workspaceID: identity.workspaceID,
            assetID: assetID,
            catalogRelease: catalog.reference,
            semanticID: AssetSemanticPersistenceReleaseV1.acceptedLegacySignSemanticID,
            predecessorEventID: nil,
            revision: 1,
            mutationID: mutationID,
            recordedAt: recordedAt
        )
        let malformedWorkflow = try AssetWorkflowCapabilityBindingEventV1(
            eventID: Self.historicalAssetSemanticUUID(
                domain: "asset-semantics/legacy-workflow-binding/v1",
                workspaceID: identity.workspaceID.rawValue,
                assetID: assetID
            ),
            workspaceID: identity.workspaceID,
            assetID: assetID,
            kindBindingEventID: malformedKindEventID,
            kindBindingRevision: 1,
            workflowPackageRelease: catalog.packageRelease,
            capabilityIDs: [],
            disposition: .bound,
            predecessorEventID: nil,
            revision: 1,
            mutationID: mutationID,
            recordedAt: recordedAt
        )
        let hostileFactory = StoreGenerationFactory(applicationSupportURL: hostileRoot)
        let hostileModelURL = try hostileFactory.seedReleasedCheckpointTestFixture(
            release: .v10,
            generationID: hostileGenerationID,
            migrationID: migrationID,
            identity: identity
        ) { context in
            context.insert(Site(
                id: siteDTO.id, label: siteDTO.label, address: siteDTO.address,
                timeZoneID: siteDTO.timeZoneID, createdAt: siteDTO.createdAt,
                updatedAt: siteDTO.updatedAt
            ))
            context.insert(Asset(
                id: assetDTO.id, siteID: assetDTO.siteID, packID: assetDTO.packID,
                packSchemaVersion: assetDTO.packSchemaVersion,
                packContentVersion: assetDTO.packContentVersion, label: assetDTO.label,
                createdAt: assetDTO.createdAt, updatedAt: assetDTO.updatedAt
            ))
            context.insert(try AssetKindBindingEventRow(malformedKind))
            context.insert(try AssetWorkflowCapabilityBindingEventRow(malformedWorkflow))
            context.insert(WorkspaceMutationStateRow(
                workspaceID: identity.workspaceID.rawValue,
                generationID: hostileGenerationID,
                activeReplicaID: identity.replicaID.rawValue,
                mutableSemanticSHA256: checkpoint
            ))
        }
        let hostilePointerURL = hostileRoot.appendingPathComponent("FieldEvidenceData/current.json")
        let hostilePointerBefore = try Data(contentsOf: hostilePointerURL)
        let hostileSourceBytesBefore = try Data(contentsOf: hostileModelURL)
        let hostileSnapshotBefore = try hostileFactory.makeRestoreGenerationAuthority()
            .snapshotInstalledGeneration(id: hostileGenerationID)
        do {
            _ = try await hostileFactory.openForStartup(recoverOriginalSource: { _ in })
            XCTFail("Expected a non-deterministic V10 legacy event identity to fail closed")
        } catch {
            XCTAssertTrue(error is StoreMigrationFailure || error is WorkspaceMutationFailureV1)
        }
        XCTAssertEqual(try Data(contentsOf: hostilePointerURL), hostilePointerBefore)
        XCTAssertEqual(try Data(contentsOf: hostileModelURL), hostileSourceBytesBefore)
        let hostileSnapshotAfter = try hostileFactory.makeRestoreGenerationAuthority()
            .snapshotInstalledGeneration(id: hostileGenerationID)
        XCTAssertEqual(hostileSnapshotAfter.files, hostileSnapshotBefore.files)
        XCTAssertEqual(hostileSnapshotAfter.sourceTreeDigest, hostileSnapshotBefore.sourceTreeDigest)
        XCTAssertEqual(hostileSnapshotAfter.frozenIdentityDigest, hostileSnapshotBefore.frozenIdentityDigest)
        if let journal = try StoreAggregateMigrationControlV1(applicationSupportURL: hostileRoot)?.load() {
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: hostileFactory.installedGenerationURL(id: journal.targetGenerationID).path
            ))
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: hostileFactory.restoreStagingGenerationURL(id: journal.targetGenerationID).path
            ))
        }
    }

    @MainActor
    func testV14HistoricalCheckpointIncludesItsIntroducedMutableContributor() async throws {
        let root = try Self.makeAbsentApplicationSupportURL(label: "V14-contributor")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let generationID = UUID()
        let migrationID = UUID()
        let identity = try Self.historicalIdentity()
        let releaseID = UUID()
        let entity = try WorkspaceEntityIdentityV1(kind: .authoritySourceRelease, id: releaseID)
        let value = try AuthoritySourceReleaseV1(
            releaseID: releaseID,
            workspaceID: identity.workspaceID,
            sourceID: UUID(),
            sourceType: .ownerPolicy,
            designation: "Historical authority",
            editionOrRevision: "V14",
            retrievedAt: Date(timeIntervalSince1970: 1_700_000_000),
            licenseStorageDisposition: .notStored,
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
            mutationID: try MutationIDV1(rawValue: UUID())
        )
        let checkpoint = try Self.historicalCheckpoint([
            .init(stableIdentity: entity.stableKey, revision: 1, semanticSHA256: value.releaseSHA256),
        ])
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        _ = try factory.seedReleasedCheckpointTestFixture(
            release: .v14,
            generationID: generationID,
            migrationID: migrationID,
            identity: identity
        ) { context in
            context.insert(try AuthoritySourceReleaseRow(value))
            context.insert(EntityMutationRevisionRow(
                identity: entity,
                revision: 1,
                externalProjectionSHA256: value.releaseSHA256
            ))
            context.insert(WorkspaceMutationStateRow(
                workspaceID: identity.workspaceID.rawValue,
                generationID: generationID,
                activeReplicaID: identity.replicaID.rawValue,
                mutableSemanticSHA256: checkpoint
            ))
        }
        Self.assertAwaitingIndependentValidation(
            try await factory.openForStartup(recoverOriginalSource: { _ in })
        )
    }

    @MainActor
    func testHistoricalCheckpointRejectsCounterRevisionProjectionAndFutureKindDrift() async throws {
        for hostile in [
            "checkpoint-drift", "future-terminal-kind", "stale-v9-with-v14-contributor",
            "negative-workspace-counter", "negative-sequence-counter", "missing-revision-row",
            "divergent-revision-row",
        ] {
            let root = try Self.makeAbsentApplicationSupportURL(label: hostile)
            defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
            let generationID = UUID()
            let migrationID = UUID()
            let identity = try Self.historicalIdentity()
            let factory = StoreGenerationFactory(applicationSupportURL: root)
            _ = try factory.seedReleasedCheckpointTestFixture(
                release: .v14,
                generationID: generationID,
                migrationID: migrationID,
                identity: identity
            ) { context in
                let state = WorkspaceMutationStateRow(
                    workspaceID: identity.workspaceID.rawValue,
                    generationID: generationID,
                    activeReplicaID: identity.replicaID.rawValue,
                    workspaceRevision: hostile == "negative-workspace-counter" ? -1 : 0,
                    lastLocalSequence: hostile == "negative-sequence-counter" ? -1 : 0,
                    mutableSemanticSHA256: try Self.historicalCheckpoint([])
                )
                context.insert(state)
                if hostile == "checkpoint-drift" {
                    context.insert(Site(id: UUID(), label: "Uncheckpointed", timeZoneID: "UTC"))
                } else if hostile == "future-terminal-kind" {
                    context.insert(EntityMutationRevisionRow(
                        identity: try WorkspaceEntityIdentityV1(kind: .lightingSystem, id: UUID()),
                        revision: 1,
                        externalProjectionSHA256: String(repeating: "a", count: 64)
                    ))
                } else if hostile == "stale-v9-with-v14-contributor" {
                    let releaseID = UUID()
                    let value = try AuthoritySourceReleaseV1(
                        releaseID: releaseID, workspaceID: identity.workspaceID, sourceID: UUID(),
                        sourceType: .ownerPolicy, designation: "Uncheckpointed authority",
                        editionOrRevision: "V14", retrievedAt: Date(timeIntervalSince1970: 1_700_000_000),
                        licenseStorageDisposition: .notStored,
                        recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
                        mutationID: try MutationIDV1(rawValue: UUID())
                    )
                    context.insert(try AuthoritySourceReleaseRow(value))
                    context.insert(EntityMutationRevisionRow(
                        identity: try WorkspaceEntityIdentityV1(kind: .authoritySourceRelease, id: releaseID),
                        revision: 1,
                        externalProjectionSHA256: value.releaseSHA256
                    ))
                } else if hostile == "missing-revision-row" || hostile == "divergent-revision-row" {
                    let site = Site(id: UUID(), label: "Revision-bound", timeZoneID: "UTC")
                    let siteIdentity = try WorkspaceEntityIdentityV1(kind: .site, id: site.id)
                    let siteDTO = V4BackupSiteDTO(
                        id: site.id, schemaVersion: site.schemaVersion, label: site.label,
                        address: site.address, timeZoneID: site.timeZoneID,
                        createdAt: site.createdAt, updatedAt: site.updatedAt
                    )
                    let item = try Self.historicalItem(identity: siteIdentity, revision: 1, value: siteDTO)
                    context.insert(site)
                    state.mutableSemanticSHA256 = try Self.historicalCheckpoint([item])
                    if hostile == "divergent-revision-row" {
                        context.insert(EntityMutationRevisionRow(
                            identity: siteIdentity,
                            revision: 2,
                            externalProjectionSHA256: item.semanticSHA256
                        ))
                    }
                }
            }
            do {
                _ = try await factory.openForStartup(recoverOriginalSource: { _ in })
                XCTFail("Expected hostile historical checkpoint to be rejected")
            } catch {
                XCTAssertTrue(error is StoreMigrationFailure || error is WorkspaceMutationFailureV1)
            }
        }
    }
#endif

    @MainActor
    func testCurrentActiveValidateAllBehaviorRemainsStrict() throws {
        let root = try Self.makeTemporaryApplicationSupportURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try StoreGenerationFactory(applicationSupportURL: root).openOrBootstrapCurrent()
        let journal = try MutationJournalStoreV1(
            modelContext: session.modelContext,
            identity: session.workspaceIdentity,
            generationID: session.generationID
        )
        XCTAssertNoThrow(try journal.validateAll())
        let state = try XCTUnwrap(session.modelContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first)
        state.mutableSemanticSHA256 = String(repeating: "f", count: 64)
        XCTAssertThrowsError(try journal.validateAll()) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
    }

    private static func historicalCheckpoint(_ content: [HistoricalJournalMutableItemV1]) throws -> String {
        try WorkspaceMutationCanonicalV1.sha256(HistoricalJournalMutableBasisV1(
            content: content.sorted { $0.stableIdentity < $1.stableIdentity },
            deletionLedger: .empty
        ))
    }

    private static func historicalItem<Value: Codable>(
        identity: WorkspaceEntityIdentityV1,
        revision: UInt64 = 0,
        value: Value
    ) throws -> HistoricalJournalMutableItemV1 {
        .init(
            stableIdentity: identity.stableKey,
            revision: revision,
            semanticSHA256: try WorkspaceMutationCanonicalV1.sha256(
                HistoricalJournalPostImageBasisV1(identity: identity, revision: revision, value: value)
            )
        )
    }

    private static func historicalAssetSemanticUUID(
        domain: String,
        workspaceID: UUID,
        assetID: UUID
    ) -> UUID {
        let material = Data(
            "\(domain)|\(workspaceID.uuidString.lowercased())|\(assetID.uuidString.lowercased())".utf8
        )
        var bytes = Array(SHA256.hash(data: material).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func historicalWorkflowRecord(assetID: UUID, timestamp: Date) -> WorkflowRecord {
        let recordID = UUID()
        return WorkflowRecord(
            id: recordID, assetID: assetID, packetID: nil, issueID: nil,
            parentRecordID: nil, recordRevisionRootID: recordID,
            revisesRecordID: nil, evidenceSourceRecordID: nil,
            revisionKind: .original, stage: .check, state: .draft,
            draftStepKey: .wide, startedAt: timestamp, completedAt: nil,
            observedAtUTC: timestamp, timeZoneID: "UTC", utcOffsetMinutes: 0,
            localDate: "2023-11-15", localTime: "09:20:00",
            afterDarkAcknowledgementKey: nil,
            afterDarkAcknowledgementCopy: nil,
            afterDarkAcknowledgementVersion: nil,
            afterDarkAcknowledgementAccepted: nil,
            safePositionAcknowledgementKey: nil,
            safePositionAcknowledgementCopy: nil,
            safePositionAcknowledgementVersion: nil,
            safePositionAcknowledgementAccepted: nil,
            packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
            packContentVersion: SignPack.illuminatedSignV1.contentVersion,
            pdfTemplateID: "historical.report",
            pdfTemplateVersion: 1, outcomeKey: nil, couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil, couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: nil, workDescription: nil, note: nil,
            finalizationMutationID: nil
        )
    }

    private static func historicalWorkflowDTO(
        _ row: WorkflowRecord,
        observationBasisData: Data?,
        temporalContextData: Data?
    ) -> V4BackupWorkflowRecordDTO {
        V4BackupWorkflowRecordDTO(
            id: row.id, schemaVersion: row.schemaVersion, assetID: row.assetID,
            packetID: row.packetID, issueID: row.issueID, parentRecordID: row.parentRecordID,
            recordRevisionRootID: row.recordRevisionRootID, revisesRecordID: row.revisesRecordID,
            evidenceSourceRecordID: row.evidenceSourceRecordID, revisionKind: row.revisionKind,
            stage: row.stage, state: row.state, draftStepKey: row.draftStepKey,
            startedAt: row.startedAt, completedAt: row.completedAt,
            observedAtUTC: row.observedAtUTC, timeZoneID: row.timeZoneID,
            utcOffsetMinutes: row.utcOffsetMinutes, localDate: row.localDate,
            localTime: row.localTime,
            afterDarkAcknowledgementKey: row.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: row.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: row.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: row.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: row.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: row.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: row.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: row.safePositionAcknowledgementAccepted,
            packID: row.packID, packSchemaVersion: row.packSchemaVersion,
            packContentVersion: row.packContentVersion, pdfTemplateID: row.pdfTemplateID,
            pdfTemplateVersion: row.pdfTemplateVersion, outcomeKey: row.outcomeKey,
            couldNotVerifyKey: row.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: row.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: row.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: row.workPerformedLocalDate,
            workDescription: row.workDescription, note: row.note,
            finalizationMutationID: row.finalizationMutationID,
            observationBasisV1Data: observationBasisData,
            temporalContextV1Data: temporalContextData
        )
    }

    private static func historicalCheckDraftCommand(
        _ row: WorkflowRecord,
        observationBasisData: Data? = nil,
        temporalContextData: Data? = nil
    ) throws -> CheckDraftMutationV1 {
        guard (observationBasisData == nil) == (temporalContextData == nil) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        return try CheckDraftMutationV1(
            recordID: row.id,
            assetID: row.assetID,
            issueID: row.issueID,
            parentRecordID: row.parentRecordID,
            stage: row.stage,
            draftStepKey: row.draftStepKey,
            startedAt: row.startedAt,
            observedAtUTC: row.observedAtUTC,
            timeZoneID: row.timeZoneID,
            utcOffsetMinutes: row.utcOffsetMinutes,
            localDate: row.localDate,
            localTime: row.localTime,
            afterDarkAcknowledgementKey: row.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: row.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: row.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: row.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: row.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: row.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: row.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: row.safePositionAcknowledgementAccepted,
            packID: row.packID,
            packSchemaVersion: row.packSchemaVersion,
            packContentVersion: row.packContentVersion,
            pdfTemplateID: row.pdfTemplateID,
            pdfTemplateVersion: row.pdfTemplateVersion,
            observationBasis: observationBasisData.map {
                try ObservationAndTimeCodecV1.decodeObservationBasis($0)
            },
            temporalContext: temporalContextData.map {
                try ObservationAndTimeCodecV1.decodeTemporalContext($0)
            }
        )
    }

    private static func historicalIdentity() throws -> WorkspaceReplicaIdentityV1 {
        try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: UUID()),
            replicaID: ReplicaID(rawValue: UUID())
        )
    }

    private static func assertAwaitingIndependentValidation(
        _ result: StoreStartupOpenResultV1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .awaitingIndependentValidation = result else {
            return XCTFail("Expected the first historical-source process to await validation", file: file, line: line)
        }
    }

    private static func directoryEntryNames(at url: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
    }

    private static func makeAbsentApplicationSupportURL(label: String) throws -> URL {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V10_01HistoricalParent-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        return parent.appendingPathComponent(label, isDirectory: true)
    }
}

private final class C27V1001TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(LocatorBindingActionV1.allCases.count, 6)
        XCTAssertEqual(AssetLocatorLimitsV1.maximumCandidates, 32)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.scanMutatesCanonicalState)
    }
}

extension V10_01WorkspaceWriterTests {
    func testC22RecoverabilityVerificationAnchor() throws {
        XCTAssertEqual(RecoverabilityVerificationReceiptV1.schemaVersion, 1)
        try V21RecoverabilityImportBoundaryV1.validate(persistentSchemaVersion: 21, recordsSchemaVersion: 20)
        XCTAssertEqual(RecoverabilityVerificationLifecycleV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.liveRestorePermitted)
    }
}

extension V10_01WorkspaceWriterTests {
    func testV23P03C57MyDayMutationClosesCASIdentityAndAtomicCarryoverImages() throws {
        let fixture = try C57MyDayExistingSuiteFixtureV1.make()
        let generationID = UUID(uuidString: "57000000-0000-4000-8000-000000000101")!
        let writerInstanceID = UUID(uuidString: "57000000-0000-4000-8000-000000000102")!

        let saveExpected = try fixture.expectedRevision(
            for: fixture.saveCommand,
            workspaceRevision: 0,
            generationID: generationID,
            writerInstanceID: writerInstanceID
        )
        let save = try MyDayMutationV1(
            command: fixture.saveCommand,
            expectedRevision: saveExpected
        )
        try save.validate()
        XCTAssertEqual(WorkspaceCommandV1.applyMyDay(save).kind, .applyMyDay)
        XCTAssertEqual(try save.concurrencyIdentities, [
            try .init(kind: .myDayPlan, id: fixture.sourcePlan.planID),
        ])
        XCTAssertEqual(try save.mutationPostImages.count, 1)
        XCTAssertEqual(try save.mutationPostImages.first?.identity.kind, .myDayPlan)
        XCTAssertEqual(try save.expectedRevision(for: save.concurrencyIdentities[0]), 0)

        let carryExpected = try fixture.expectedRevision(
            for: fixture.carryoverCommand,
            workspaceRevision: 1,
            generationID: generationID,
            writerInstanceID: writerInstanceID
        )
        let carryover = try MyDayMutationV1(
            command: fixture.carryoverCommand,
            expectedRevision: carryExpected
        )
        try carryover.validate()
        XCTAssertEqual(WorkspaceCommandV1.applyMyDay(carryover).kind, .applyMyDay)
        XCTAssertEqual(Set(try carryover.concurrencyIdentities.map(\.kind)), [
            .myDayPlan, .myDayCarryoverReceipt,
        ])
        XCTAssertEqual(try carryover.concurrencyIdentities.count, 3)
        XCTAssertEqual(Set(try carryover.mutationPostImages.map { try $0.identity.kind }), [
            .myDayPlan, .myDayCarryoverReceipt,
        ])
        XCTAssertEqual(try carryover.mutationPostImages.count, 2)
        XCTAssertEqual(
            carryover.carryoverReceiptID,
            fixture.carryoverReceipt.mutationID.rawValue
        )

        let stalePlanIdentity = try WorkspaceEntityIdentityV1(
            kind: .myDayPlan,
            id: fixture.sourcePlan.planID
        )
        let staleExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: fixture.workspaceID,
            generationID: generationID,
            writerInstanceID: writerInstanceID,
            workspaceRevision: 0,
            entityRevisions: [.init(identity: stalePlanIdentity, revision: 1)]
        )
        XCTAssertThrowsError(try MyDayMutationV1(
            command: fixture.saveCommand,
            expectedRevision: staleExpected
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationContractFailureV1, .invalidPlan)
        }
    }
}

extension V10_01WorkspaceWriterTests {
    func testV23P03C15WriterMutationUsesPacketIdentityAndCanonicalReceiptBytes() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_201)
        let mutation = try WorkPacketMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: 0,
            mutationID: fixture.manifest.mutationID,
            postImage: .appendManifest(fixture.manifest)
        )
        XCTAssertEqual(try mutation.affectedIdentity.kind, .workPacketManifest)
        XCTAssertEqual(try mutation.affectedIdentity.id, fixture.manifest.manifestID)
        XCTAssertEqual(try mutation.concurrencyIdentity.id, fixture.manifest.manifestID)
        XCTAssertEqual(try mutation.canonicalSHA256().count, 64)
    }
}

extension V10_01WorkspaceWriterTests {
    func testV23P03C36WriterMutationUsesOneTypedDraftPostImageAndCASIdentity() throws {
        let fixture = try C36FieldDraftTestSupportV1.makeFixture()
        let mutation = try FieldDraftMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: 0,
            expectedBaseCanonicalRevision: fixture.activeCheckpoint.baseCanonicalRevision,
            mutationID: fixture.activeCheckpoint.mutationID,
            postImage: .createCheckpoint(fixture.activeCheckpoint)
        )
        try mutation.validate()
        XCTAssertEqual(try mutation.affectedIdentity.kind, .fieldDraftCheckpoint)
        XCTAssertEqual(try mutation.concurrencyIdentity.kind, .fieldDraftCheckpoint)
        XCTAssertEqual(WorkspaceCommandV1.applyFieldDraft(mutation).kind, .applyFieldDraft)
        XCTAssertEqual(try mutation.affectedIdentity.id, fixture.draftID)
        XCTAssertEqual(try mutation.canonicalSHA256().count, 64)

        let stagingPayload = FieldDraftMutationPayloadV1.appendStagingItem(fixture.readyItem)
        XCTAssertEqual(stagingPayload.workspaceID, fixture.workspaceID)
        XCTAssertEqual(try stagingPayload.affectedIdentity.kind, .attachmentStagingItem)
    }
}

@MainActor
private final class TestWorkspaceWriterAdapterV1: WorkspaceWriterAdapterPortV1 {
    private(set) var applyCount = 0

    func apply(
        _ command: WorkspaceCommandV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        applyCount += 1
        switch command {
        case let .createFirstSign(value):
            var identities = [try WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID)]
            if let site = value.newSite {
                identities.append(try WorkspaceEntityIdentityV1(kind: .site, id: site.id))
            }
            return try WorkspaceMutationEffectV1(
                affectedEntities: identities,
                temporaryRelativePath: temporaryRelativePath
            )
        default:
            throw WorkspaceMutationFailureV1.unsupportedCommand
        }
    }
}

private struct TestApplicationClockV1: ApplicationClock {
    let value: Date
    func now() -> Date { value }
}

private struct TestApplicationIDSourceV1: ApplicationIDSource {
    let value: UUID
    func makeID() -> UUID { value }
}

private final class SequenceApplicationIDSourceV1: ApplicationIDSource, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID]

    init(values: [UUID]) {
        precondition(!values.isEmpty)
        self.values = values
    }

    func makeID() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        precondition(!values.isEmpty, "Unexpected deterministic ID authority consumption")
        return values.removeFirst()
    }
}

private struct TestApplicationFileAuthorityV1: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(
        mutationID: MutationIDV1,
        component: String
    ) throws -> String {
        "mutation-staging/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

@MainActor
private final class SearchRevisionRecorder {
    var values: [SearchSourceRevisionV1] = []
}

@MainActor
private final class Harness {
    let workspaceID = WorkspaceID(rawValue: Harness.id(1))
    let generationID = Harness.id(2)
    let siteID = Harness.id(3)
    let assetID = Harness.id(4)
    let adapter = TestWorkspaceWriterAdapterV1()
    let writer: WorkspaceWriterV1

    init(
        maximumRemembered: Int = 10,
        writerInstanceByte: UInt8 = 90,
        searchIndexInvalidation: ((SearchSourceRevisionV1) -> Void)? = nil
    ) throws {
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: workspaceID,
            replicaID: ReplicaID(rawValue: Self.id(5))
        )
        let site = try WorkspaceEntityIdentityV1(kind: .site, id: siteID)
        let asset = try WorkspaceEntityIdentityV1(kind: .asset, id: assetID)
        let initial = try WorkspaceRevisionV1(
            workspaceID: workspaceID,
            generationID: generationID,
            revision: 0,
            entityRevisions: [
                .init(identity: site, revision: 0),
                .init(identity: asset, revision: 0),
            ]
        )
        writer = try WorkspaceWriterV1(
            identity: identity,
            generationID: generationID,
            initialRevision: initial,
            clock: TestApplicationClockV1(value: Date(timeIntervalSince1970: 1_800_000_000)),
            idSource: TestApplicationIDSourceV1(value: Self.id(writerInstanceByte)),
            fileAuthority: TestApplicationFileAuthorityV1(),
            adapter: adapter,
            searchIndexInvalidation: searchIndexInvalidation,
            maximumRememberedMutationCount: maximumRemembered
        )
    }

    func request(
        mutation: UInt8,
        label: String,
        expected: WorkspaceRevisionV1? = nil
    ) throws -> WorkspaceMutationRequestV1 {
        WorkspaceMutationRequestV1(
            mutationID: try MutationIDV1(rawValue: Self.id(mutation)),
            expectedRevision: WorkspaceExpectedRevisionV1(
                snapshot: expected ?? (try writer.currentRevision())
            ),
            command: .createFirstSign(.init(
                siteID: siteID,
                newSite: .init(id: siteID, label: "Site", address: nil, timeZoneID: "UTC"),
                assetID: assetID,
                assetLabel: label,
                packID: "test.pack",
                packSchemaVersion: 1,
                packContentVersion: 1,
                createdAt: Date(timeIntervalSince1970: 1_800_000_010)
            ))
        )
    }

    static func id(_ byte: UInt8) -> UUID {
        UUID(uuid: (byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
    }
}

extension V10_01WorkspaceWriterTests {
    func testV23P03C41WriterInputCarriesExplicitMutationAndRevisionIdentity() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 41_010)

        XCTAssertEqual(fixture.added.action, .added)
        XCTAssertEqual(fixture.added.revision, 1)
        XCTAssertNil(fixture.added.predecessorEventID)
        XCTAssertEqual(fixture.added.expectedRelationshipRevision, 0)
        XCTAssertNotEqual(fixture.added.mutationID.rawValue, FunctionalRelationshipLimitsV1.zeroUUID)
        XCTAssertNotEqual(fixture.descriptor.mutationID.rawValue, FunctionalRelationshipLimitsV1.zeroUUID)
        XCTAssertNotEqual(fixture.added.mutationID, fixture.descriptor.mutationID)
        try fixture.added.validate()
    }
}

extension V10_01WorkspaceWriterTests {
    func testV23P03C13WriterCommandCarriesExpectedRevisionAndMutationIdentity() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_010)
        let mutation = try EvidenceAssuranceMutationV1(
            workspaceID: fixture.workspaceID,
            expectedRevision: 0,
            mutationID: fixture.customerLink.mutationID,
            postImage: .appendLink(fixture.customerLink)
        )

        try mutation.validate()
        XCTAssertEqual(mutation.workspaceID, fixture.workspaceID)
        XCTAssertEqual(mutation.expectedRevision, 0)
        XCTAssertEqual(mutation.mutationID, fixture.customerLink.mutationID)
        XCTAssertEqual(try mutation.affectedIdentity.kind, .claimEvidenceLink)
        XCTAssertEqual(try mutation.affectedIdentity.id, fixture.customerLink.linkID)
        XCTAssertEqual(try mutation.concurrencyIdentity, try mutation.affectedIdentity)
    }
}

extension V10_01WorkspaceWriterTests {
    func testV23P03C14WriterMutationBindsAffectedAndConcurrencyIdentity() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_101)
        let transition = fixture.transitions[0]
        let bundle = try InspectionReviewAtomicBundleV1(transition: transition)
        let mutation = try InspectionReviewMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: 0,
            mutationID: transition.mutationID, postImage: .applyReviewBundle(bundle)
        )
        try mutation.validate()
        XCTAssertEqual(try mutation.affectedIdentities.count, 1)
        XCTAssertEqual(try mutation.concurrencyIdentities.count, 1)
        XCTAssertNil(try mutation.predecessorIdentity)
        XCTAssertEqual(try mutation.affectedIdentity.kind, .inspectionReviewTransition)
        XCTAssertEqual(try mutation.affectedIdentity.id, transition.transitionID)
        XCTAssertEqual(try mutation.concurrencyIdentity.id, transition.transitionID)
    }
}

extension V10_01WorkspaceWriterTests {
    func testV23P03C18PromotionUsesTheSoleCanonicalWriterAndAtomicBundle() throws {
        XCTAssertEqual(PackageEvolutionLifecycleV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")
        XCTAssertEqual(
            PackageEvolutionLifecycleV1.interruption,
            "OLD_COMPLETE_OR_NEW_COMPLETE_NEVER_HYBRID"
        )
        XCTAssertTrue(PackageEvolutionLifecycleV1.persistent)
        XCTAssertTrue(PackageEvolutionLifecycleV1.exportReportRequired)
        XCTAssertTrue(PackageEvolutionLifecycleV1.searchRebuildReplayRequired)

        // Keep the compile-time references on the canonical coordinator and
        // atomic bundle types; package evolution does not add a second writer.
        XCTAssertGreaterThan(MemoryLayout<PackageEvolutionCoordinatorV1>.size, 0)
        XCTAssertGreaterThan(MemoryLayout<PackagePromotionAtomicBundleV1>.size, 0)
    }

    func testV23P03C19CoordinatorPreparesOneTypedAtomicBundle() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let bundle = try MeasurementIntegrityCoordinatorV1.prepare(
            workspaceID: fixture.workspace, mutationID: fixture.mutationID,
            instruments: [fixture.instrument], calibrations: [fixture.currentCalibration],
            captures: [fixture.capture], series: [fixture.series],
            assessments: [fixture.qualityClear]
        )
        XCTAssertEqual(bundle.workspaceID, fixture.workspace)
        XCTAssertEqual(bundle.mutationID, fixture.mutationID)
        XCTAssertEqual(bundle.instruments.count + bundle.calibrations.count + bundle.captures.count + bundle.series.count + bundle.assessments.count, 5)
        try bundle.validate()
    }

    func testC20PrivacyTransformWriterReceivesValidatedPublicationBundle() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        try fixture.bundle.validate()
        XCTAssertEqual(fixture.bundle.manifest.manifestID, fixture.manifest.manifestID)
        XCTAssertEqual(fixture.bundle.derivativeLocator.contentID, fixture.derivative.contentID)
    }
}

extension V10_01WorkspaceWriterTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}

extension V10_01WorkspaceWriterTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorV1001WorkspaceWriterTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

private final class C33TemporalEvidenceAnchorV1001WorkspaceWriter: XCTestCase {
    func testC33V1001WorkspaceWriterCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "writer.temporal-evidence-single-command",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "writer.temporal-evidence-single-command",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorV1001WorkspaceWriter: XCTestCase {
    func testC32V1001WorkspaceWriterCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .asset,
            fieldID: "writer.explicit-acceptance",
            value: .text("expected revision value")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .asset,
            fieldID: "writer.explicit-acceptance",
            valueKind: .text
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46V1001WriterCompatibilityTests: XCTestCase {
    func testC46WorkspaceWriterBindsContactConcurrencyIdentity() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "workspace-writer",
            kind: .phone,
            handoff: .call,
            slot: 46101
        )
    }
}

extension C45WorkspaceWriterCompatibilityTests {
    func testV23P03C51WorkspaceWriterUsesScheduleCommandAndFrontier() {
        XCTAssertTrue(
            C51ScheduleOverrideRecoveryBoundaryV1.commandKind == .applySchedule
                && WorkspaceCommandKindV1.applySchedule.rawValue == "apply_schedule"
                && C51ScheduleOverrideRecoveryBoundaryV1
                    .overrideFrontierIsRevalidatedFromPersistedRows
                && !C51ScheduleOverrideRecoveryBoundaryV1.createsParallelWriter
        )
    }
}

extension V10_01WorkspaceWriterTests {
    func testV23P03C34RouteResolutionCannotWriteOrStartWork() throws {
        let workspaceID = WorkspaceID(
            rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000003401")!
        )
        let target = try NavigationTargetV1(
            workspaceID: workspaceID, destination: .work, requestedMode: .resume
        )
        let result = try RouteRegistryV1().resolve(
            target,
            context: .init(currentWorkspaceID: workspaceID, currentRevision: 0)
        )
        XCTAssertEqual(result.disposition, .resolved)
        XCTAssertEqual(result.canonicalMutationCount, 0)
        XCTAssertFalse(result.startsAutomaticWork)
    }
}

extension V10_01WorkspaceWriterTests {
    @MainActor
    func testV23P03C57WorkspaceWriterCommitsCarryoverAtomicallyAndReplaysExactly() throws {
        let seedFixture = try C57MyDayExistingSuiteFixtureV1.make()
        var fixture = seedFixture
        let schema = Schema(
            PersistentSchemaV42.models,
            version: PersistentSchemaV42.versionIdentifier
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "C57-Existing-Writer",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )]
        )
        let context = container.mainContext
        context.autosaveEnabled = false
        let generationID = UUID(uuidString: "57000000-0000-4000-8000-000000000201")!
        let writerInstanceID = UUID(uuidString: "57000000-0000-4000-8000-000000000202")!
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: seedFixture.workspaceID,
            replicaID: .init(rawValue: UUID(
                uuidString: "57000000-0000-4000-8000-000000000203"
            )!)
        )
        let journal = try MutationJournalStoreV1(
            modelContext: context,
            identity: identity,
            generationID: generationID
        )
        let writer = try WorkspaceWriterV1(
            identity: identity,
            generationID: generationID,
            initialRevision: journal.currentRevision(writerInstanceID: writerInstanceID),
            clock: TestApplicationClockV1(
                value: Date(timeIntervalSince1970: 1_800_100_100)
            ),
            idSource: TestApplicationIDSourceV1(value: writerInstanceID),
            fileAuthority: TestApplicationFileAuthorityV1(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context),
            journalStore: journal
        )

        let missingExpected = try seedFixture.expectedRevision(
            for: seedFixture.saveCommand,
            workspaceRevision: 0,
            generationID: generationID,
            writerInstanceID: writerInstanceID
        )
        let missingMutation = try MyDayMutationV1(
            command: seedFixture.saveCommand,
            expectedRevision: missingExpected
        )
        XCTAssertThrowsError(try writer.commitMyDay(missingMutation)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidCommand)
        }
        XCTAssertEqual(try writer.currentRevision().revision, 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<MyDayPlanRowV1>()).isEmpty)

        let release = try C26SurveySessionTestSupport.release(
            workspaceID: seedFixture.workspaceID
        )
        let authority = try C26SurveySessionTestSupport.authority(for: release)
        let provisional = try C26SurveySessionTestSupport.provisional(
            workspaceID: seedFixture.workspaceID
        )
        guard case let .roundSession(_, activeSessionID, _, _) =
                seedFixture.sourcePlan.items[0].reference else {
            XCTFail("Expected the fixed C57 round-session reference")
            return
        }
        let activeSession = try C26SurveySessionTestSupport.session(
            authority: authority,
            workspaceID: seedFixture.workspaceID,
            sessionID: activeSessionID,
            subject: .provisional(provisional.reference),
            state: .draft,
            transition: .create,
            revision: 1,
            actorSlot: 570
        )
        context.insert(try SurveySessionRow(activeSession))
        try context.save()

        let staleReference = MyDayEligibleReferenceV1.roundSession(
            workspaceID: seedFixture.workspaceID,
            sessionID: activeSession.sessionID,
            revision: activeSession.revision + 1,
            sessionSHA256: activeSession.sessionSHA256
        )
        let staleFixture = try C57MyDayExistingSuiteFixtureV1.make(
            reference: staleReference,
            sourceMutationSlot: 11
        )
        let staleExpected = try staleFixture.expectedRevision(
            for: staleFixture.saveCommand,
            workspaceRevision: 0,
            generationID: generationID,
            writerInstanceID: writerInstanceID
        )
        let staleMutation = try MyDayMutationV1(
            command: staleFixture.saveCommand,
            expectedRevision: staleExpected
        )
        XCTAssertThrowsError(try writer.commitMyDay(staleMutation)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidCommand)
        }

        let otherWorkspace = WorkspaceID(rawValue: UUID(
            uuidString: "57000000-0000-4000-8000-000000000204"
        )!)
        XCTAssertThrowsError(try C57MyDayExistingSuiteFixtureV1.make(reference:
            .roundSession(
                workspaceID: otherWorkspace,
                sessionID: activeSession.sessionID,
                revision: activeSession.revision,
                sessionSHA256: activeSession.sessionSHA256
            )
        )) {
            XCTAssertEqual($0 as? MyDayFailureV1, .invalidValue)
        }

        let terminalID = C26SurveySessionTestSupport.id(5_700)
        let terminalDraft = try C26SurveySessionTestSupport.session(
            authority: authority,
            workspaceID: seedFixture.workspaceID,
            sessionID: terminalID,
            subject: .provisional(provisional.reference),
            state: .draft,
            transition: .create,
            revision: 1,
            actorSlot: 571
        )
        let terminalSession = try C26SurveySessionTestSupport.session(
            authority: authority,
            workspaceID: seedFixture.workspaceID,
            sessionID: terminalID,
            subject: .provisional(provisional.reference),
            state: .deleted,
            transition: .delete,
            predecessor: terminalDraft,
            revision: 2,
            actorSlot: 572
        )
        context.insert(try SurveySessionRow(terminalSession))
        try context.save()
        let terminalFixture = try C57MyDayExistingSuiteFixtureV1.make(
            reference: .roundSession(
                workspaceID: seedFixture.workspaceID,
                sessionID: terminalSession.sessionID,
                revision: terminalSession.revision,
                sessionSHA256: terminalSession.sessionSHA256
            ),
            sourceMutationSlot: 12
        )
        let terminalExpected = try terminalFixture.expectedRevision(
            for: terminalFixture.saveCommand,
            workspaceRevision: 0,
            generationID: generationID,
            writerInstanceID: writerInstanceID
        )
        let terminalMutation = try MyDayMutationV1(
            command: terminalFixture.saveCommand,
            expectedRevision: terminalExpected
        )
        XCTAssertThrowsError(try writer.commitMyDay(terminalMutation)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidCommand)
        }
        XCTAssertEqual(try writer.currentRevision().revision, 0)

        fixture = try C57MyDayExistingSuiteFixtureV1.make(
            reference: .roundSession(
                workspaceID: seedFixture.workspaceID,
                sessionID: activeSession.sessionID,
                revision: activeSession.revision,
                sessionSHA256: activeSession.sessionSHA256
            ),
            sourceMutationSlot: 13,
            targetMutationSlot: 14
        )

        let sourceExpected = try fixture.expectedRevision(
            for: fixture.saveCommand,
            workspaceRevision: 0,
            generationID: generationID,
            writerInstanceID: writerInstanceID
        )
        let sourceMutation = try MyDayMutationV1(
            command: fixture.saveCommand,
            expectedRevision: sourceExpected
        )
        let sourceReceipt = try writer.commitMyDay(sourceMutation)
        try sourceReceipt.validate(command: fixture.saveCommand)
        XCTAssertEqual(
            try writer.currentPlan(for: fixture.sourcePlan.key),
            fixture.sourcePlan
        )

        let carryExpected = try fixture.expectedRevision(
            for: fixture.carryoverCommand,
            workspaceRevision: 1,
            generationID: generationID,
            writerInstanceID: writerInstanceID
        )
        let carryMutation = try MyDayMutationV1(
            command: fixture.carryoverCommand,
            expectedRevision: carryExpected
        )
        let carryReceipt = try writer.commitMyDay(carryMutation)
        try carryReceipt.validate(command: fixture.carryoverCommand)
        XCTAssertEqual(try writer.commitMyDay(carryMutation), carryReceipt)
        let applicationResult = try XCTUnwrap(writer.result(
            workspaceID: fixture.workspaceID,
            mutationID: carryMutation.mutationID
        ))
        XCTAssertEqual(applicationResult.plan, fixture.targetPlan)
        try applicationResult.receipt.validate(command: fixture.carryoverCommand)
        let durableCarryReceipt = try XCTUnwrap(
            journal.receipt(mutationID: carryMutation.mutationID)
        )
        let typedCarryReceipt = try MyDayWorkspaceMutationReceiptV1(
            mutation: carryMutation,
            mutationReceipt: durableCarryReceipt
        )
        XCTAssertEqual(
            typedCarryReceipt.affectedIdentities,
            try carryMutation.affectedIdentities
        )
        XCTAssertEqual(
            durableCarryReceipt.postImages,
            try carryMutation.mutationPostImages
        )

        let sourceSuccessor = try fixture.sourceSuccessor()
        let successorCommand = MyDayCommandV1.save(
            successor: sourceSuccessor,
            predecessor: fixture.sourcePlan
        )
        let successorResult = try writer.commit(successorCommand)
        XCTAssertEqual(successorResult.plan, sourceSuccessor)
        try successorResult.receipt.validate(command: successorCommand)
        XCTAssertEqual(
            try writer.currentPlan(for: fixture.sourcePlan.key),
            sourceSuccessor
        )

        let plans = try context.fetch(FetchDescriptor<MyDayPlanRowV1>()).map {
            try $0.value()
        }
        XCTAssertEqual(Set(plans), [
            fixture.sourcePlan, sourceSuccessor, fixture.targetPlan,
        ])
        XCTAssertEqual(
            plans.filter { $0.planID == fixture.sourcePlan.planID }
                .sorted { $0.revision < $1.revision },
            [fixture.sourcePlan, sourceSuccessor]
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MyDayCarryoverReceiptRowV1>())
                .map { try $0.value() },
            [fixture.carryoverReceipt]
        )
        XCTAssertEqual(try writer.currentRevision().revision, 3)

        let divergentMutation = try MyDayMutationV1(
            command: fixture.divergentSaveCommand(),
            expectedRevision: sourceExpected
        )
        XCTAssertThrowsError(try writer.commitMyDay(divergentMutation)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertEqual(try writer.currentRevision().revision, 3)
    }
}
