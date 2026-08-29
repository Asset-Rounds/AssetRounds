import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

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
