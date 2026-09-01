import Foundation
import XCTest

@testable import FieldEvidenceApp

private enum C19TestSupportV1 {
    static let now = Date(timeIntervalSince1970: 1_800_100_000)
    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "c1900000-0000-4000-8000-%012x", value))!
    }
    static func digest(_ value: Character) -> String { String(repeating: String(value), count: 64) }
    static func workspace() -> WorkspaceID { WorkspaceID(rawValue: id(1)) }
    static func mutation(_ value: Int) throws -> MutationIDV1 { try .init(rawValue: id(value)) }
    static func actor(_ responsibility: ResponsibilityKindV1, slot: Int) throws -> ActorSnapshotV1 {
        let workspace = workspace()
        let local = try LocalActorReferenceV1(actorReferenceID: id(slot), workspaceID: workspace,
                                              displayName: "C19 local actor")
        return try ActorSnapshotV1(snapshotID: id(slot + 1), workspaceID: workspace,
                                   actor: local, responsibility: responsibility,
                                   displayNameAtTime: local.displayName, capturedAt: now)
    }

    struct Fixture {
        let content: ContentReferenceV1
        let locator: ContentLocatorV1
        let release: FieldReferenceReleaseV1
        let fieldBinding: FieldReferenceBindingV1
        let document: PlanDocumentV1
        let revision: PlanRevisionV1
        let page: PlanPageReferenceV1
        let frame: SpatialReferenceFrameV1
        let placement: PlanPlacementV1
        let assetLocator: AssetLocatorV1
        let locatorReceipt: LocatorBindingReceiptV1
        let manifest: WorkPacketManifestV1
        let item: WorkPacketItemV1
        let referenceProjection: WorkPacketFieldReferenceProjectionV1
        let prerequisites: PlanPrerequisiteClosureV1
    }

    static func fixture() throws -> Fixture {
        let workspace = workspace()
        let contentDigest = try ContentDigestV1(algorithm: .sha256, hexadecimalValue: digest("b"))
        let entry = try ContentManifestEntryV1(contentID: "c19-plan-pdf", expectedByteLength: 4,
                                               mediaType: "application/pdf", digest: contentDigest,
                                               expectedLocatorRevision: 1, requiredForOpen: true)
        let contentManifest = try ContentManifestV1(
            manifestID: "c19-content-manifest",
            workspaceID: workspace.rawValue.uuidString.lowercased(), manifestRevision: 1,
            entries: [entry]
        )
        let content = try ContentReferenceV1(
            workspaceID: workspace.rawValue.uuidString.lowercased(), contentID: entry.contentID,
            byteLength: entry.expectedByteLength, mediaType: entry.mediaType,
            digests: try ContentDigestSetV1([contentDigest]), byteRole: .immutableOriginal,
            createdAt: "2026-09-01T00:00:00.000Z"
        )
        let locator = try ContentLocatorV1(
            locatorID: "c19-plan-locator", workspaceID: content.workspaceID,
            contentID: content.contentID, locatorRevision: 1, contentDigest: contentDigest,
            expectedByteLength: content.byteLength
        )
        let provenance = try FieldReferenceProvenanceV1(
            kind: .synthetic, sourceName: "C19 fixture",
            sourceReleaseIdentifier: "c19-release-1", licenseScope: .localUseOnly
        )
        let release = try FieldReferenceReleaseV1(
            releaseID: id(10), workspaceID: workspace, referencePackID: "c19-plan-pack",
            kind: .drawing, semanticVersion: "1.0.0", provenance: provenance,
            manifest: contentManifest, issuedAt: now, mutationID: try mutation(11)
        )
        let document = try PlanDocumentV1(
            planDocumentID: id(20), workspaceID: workspace, stablePlanKey: "c19-plan",
            displayName: "C19 plan", revision: 1, mutationID: try mutation(21), recordedAt: now
        )
        let crop = try PlanCropRectV1(
            minX: .init(millionths: 0), minY: .init(millionths: 0),
            maxX: .init(millionths: PlanLimitsV1.normalizedScale),
            maxY: .init(millionths: PlanLimitsV1.normalizedScale)
        )
        let page = try PlanPageReferenceV1(
            pageID: id(30), sourcePageOrdinal: 0, presentedPageOrdinal: 0,
            pixelWidth: 2_000, pixelHeight: 1_000, crop: crop,
            rotation: .degrees0, sourcePageSHA256: digest("c")
        )
        let frame = try SpatialReferenceFrameV1(frameID: id(31), pageID: page.pageID)
        let contentBinding = try PlanContentBindingV1(content: content, locator: locator,
                                                      fieldReferenceRelease: release)
        let revision = try PlanRevisionV1(
            planRevisionID: id(40), workspaceID: workspace,
            planDocument: try document.reference, contentBinding: contentBinding,
            pages: [page], spatialFrames: [frame], state: .released, revision: 1,
            mutationID: try mutation(41),
            recordedBy: try actor(.recordedBy, slot: 42), recordedAt: now
        )
        let assetID = id(51)
        let assetLocator = try AssetLocatorV1(
            locatorID: id(45), workspaceID: workspace, assetID: assetID,
            representation: .externalKey(try .init(namespaceID: "c19.fixture",
                                                     normalization: .exactNFC,
                                                     suppliedValue: "asset-51")),
            state: .active, revision: 1, mutationID: try mutation(46), recordedAt: now
        )
        let locatorPreview = try LocatorBindingPreviewV1(
            workspaceID: workspace, action: .bind, before: nil,
            after: assetLocator.reference, replacement: nil, generatedAt: now
        )
        let locatorReceipt = try LocatorBindingReceiptV1(
            receiptID: id(47), preview: locatorPreview,
            recordedBy: try actor(.recordedBy, slot: 48), predecessor: nil,
            revision: 1, mutationID: try mutation(49), recordedAt: now
        )
        let placement = try PlanPlacementV1(
            placementID: id(50), workspaceID: workspace, subjectKind: .asset,
            subjectID: assetID, planRevision: try revision.reference,
            spatialFrameID: frame.frameID,
            x: try .init(millionths: 300_000), y: try .init(millionths: 400_000),
            assetLocatorBinding: try .init(locator: assetLocator, receipt: locatorReceipt),
            revision: 1, mutationID: try mutation(52), recordedAt: now
        )
        let item = try WorkPacketItemV1(itemID: "c19-item", kind: .inspection,
                                        expectedRevision: 1, itemSHA256: digest("d"))
        let manifest = try WorkPacketManifestV1(
            manifestID: id(60), packetID: id(61), packetVersion: 1, workspaceID: workspace,
            items: [item], packageReleases: [], creationBasis: .explicitLocalSelection,
            creator: try actor(.recordedBy, slot: 62), createdAt: now,
            mutationID: try mutation(63)
        )
        let fieldBinding = try FieldReferenceBindingV1(
            bindingID: id(70), workspaceID: workspace, subjectKind: .workPacket,
            subjectID: manifest.packetID, subjectRevision: manifest.packetVersion,
            subjectState: .active, release: release, boundAt: now,
            mutationID: try mutation(71)
        )
        let readiness = try FieldReferenceOfflineReadinessV1(
            release: release, binding: fieldBinding, references: [content], locators: [locator],
            knownSuccessorReleaseIDs: [], checkedAt: now
        )
        let packetProjection = try WorkPacketProjectionBuilderV1.rebuild(
            workspaceID: workspace, manifest: manifest, claims: [], leases: [],
            releases: [], handoffs: [], at: now
        )
        let referenceProjection = try WorkPacketFieldReferenceProjectionV1(
            projection: packetProjection, manifest: manifest, bindings: [fieldBinding],
            releases: [release], readiness: [readiness]
        )
        let prerequisites = PlanPrerequisiteClosureV1(
            content: content, contentLocator: locator, fieldReferenceRelease: release,
            assetLocators: [assetLocator], locatorBindingReceipts: [locatorReceipt]
        )
        return .init(content: content, locator: locator, release: release,
                     fieldBinding: fieldBinding, document: document, revision: revision,
                     page: page, frame: frame, placement: placement,
                     assetLocator: assetLocator, locatorReceipt: locatorReceipt, manifest: manifest,
                     item: item, referenceProjection: referenceProjection,
                     prerequisites: prerequisites)
    }

    static func source(openability: PlanDocumentOpenabilityStateV1 = .openable,
                       disposition: PlanRevisionSelectionDispositionV1 = .current,
                       availableBytes: Int64? = 10_000,
                       protectedDataAvailable: Bool = true,
                       applicability: PlanApplicabilityV1 = .required,
                       planAbsent: Bool = false) throws -> PlanOfflineWorkSourceV1 {
        let fixture = try fixture()
        let observation = try PlanDocumentOpenabilityObservationV1(
            contentBinding: fixture.revision.contentBinding,
            observedByteLength: openability == .missing ? nil : fixture.content.byteLength,
            observedSHA256: openability == .missing ? nil : digest("b"),
            state: openability, checkedAt: now
        )
        let storage = try OfflineReadinessStorageObservationV1(
            capacityState: availableBytes == nil ? .unavailable : .checked,
            availableBytes: availableBytes, operationReserveBytes: 64
        )
        return PlanOfflineWorkSourceV1(
            applicability: applicability, manifest: fixture.manifest, item: fixture.item,
            fieldReferenceProjection: planAbsent ? nil : fixture.referenceProjection,
            fieldReference: planAbsent ? nil : fixture.referenceProjection.references[0],
            planRevision: planAbsent ? nil : fixture.revision,
            placements: planAbsent ? [] : [fixture.placement],
            prerequisites: planAbsent ? nil : fixture.prerequisites,
            openability: planAbsent ? nil : observation,
            storage: storage, access: .init(protectedDataAvailable: protectedDataAvailable),
            revisionDisposition: planAbsent ? nil : disposition, checkedAt: now
        )
    }

    static func poseEvent(fixture: Fixture, observed: Bool, axis: String) throws -> AssetPoseEventV1 {
        let descriptor = try PoseAxisDescriptorV1(
            axisID: PoseAxisID(rawValue: "axis.\(axis)"), localizedLabelKey: "pose.\(axis)",
            semanticRole: .assetForwardAxis, requiredComponents: .azimuthOnly,
            observationRequirement: .optional, applicability: .applicable
        )
        let pose: PlacementPoseV1
        if observed {
            pose = try PlacementPoseV1(
                disposition: .observed,
                referenceFrame: .planRelative(.init(
                    planRevision: try fixture.revision.reference, pageID: fixture.page.pageID,
                    spatialFrameID: fixture.frame.frameID, acceptedTransformSHA256: digest("e")
                )),
                azimuth: try .init(kind: .azimuth, milliDegrees: 90_000),
                horizontalUncertainty: .known(try .init(kind: .horizontalUncertainty, milliDegrees: 1)),
                descriptor: descriptor
            )
        } else {
            pose = try PlacementPoseV1(disposition: .notObserved, referenceFrame: .unknown,
                                       notObservedReason: .sourceUnavailable,
                                       descriptor: descriptor)
        }
        let eventID = observed ? id(80) : id(81)
        return try AssetPoseEventV1(
            eventID: eventID, workspaceID: workspace(), assetID: fixture.placement.subjectID,
            axisDescriptor: descriptor,
            placementEpisodeID: try .init(rawValue: id(83)), placementEventID: id(84),
            locationPathSnapshot: try .init(siteID: id(85), siteDisplay: "C19 site", nodes: []),
            pose: pose, source: .manual, rootObservationEventID: eventID,
            rootObservedAt: now, predecessor: nil, revision: 1,
            mutationID: try mutation(observed ? 86 : 87),
            recordedBy: try actor(.observedBy, slot: observed ? 88 : 90),
            occurredAt: now, recordedAt: now.addingTimeInterval(1)
        )
    }

    static func preview() throws -> RebasePreviewV1 {
        let f = try fixture()
        let next = try PlanRevisionV1(
            planRevisionID: id(100), workspaceID: workspace(),
            planDocument: try f.document.reference, contentBinding: f.revision.contentBinding,
            pages: [f.page], spatialFrames: [f.frame], state: .released,
            predecessor: f.revision, revision: 2, mutationID: try mutation(101),
            recordedBy: try actor(.recordedBy, slot: 102),
            recordedAt: now.addingTimeInterval(1)
        )
        let registry = try PlanRebaseComponentRegistryV1(
            components: [C19IdentityRebaseComponentV1()]
        )
        return try PlanRebasePreviewBuilderV1.build(
            previewID: id(110), workspaceID: workspace(), oldRevision: f.revision,
            newRevision: next,
            transform: try .init(m11: PlanLimitsV1.transformScale, m12: 0, m21: 0,
                                 m22: PlanLimitsV1.transformScale, tx: 0, ty: 0),
            placements: [f.placement], registry: registry, expectedRevision: 1,
            generatedAt: now.addingTimeInterval(2)
        )
    }

    static func corpus() throws -> Corpus {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V23/Plans/V23P04C19PlanOfflineWorkCorpusV1.json")
        return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    }
    struct Corpus: Decodable { let cardID: String; let caseCount: Int; let cases: [CorpusCase] }
    struct CorpusCase: Decodable { let category: String; let expected: String; let id: String; let scenario: String }
}

private struct C19IdentityRebaseComponentV1: PlanRebaseComponentV1 {
    let componentID = "c19.identity"
    let componentVersion = 1
    let stableSortOrdinal = 0
    func evaluate(_ context: PlanRebaseComponentContextV1) throws -> PlanRebaseComponentContributionV1 {
        let newReference = try context.newRevision.reference
        let rows = try context.placements.map { old -> PlanRebaseRowV1 in
            let next = try PlanPlacementV1(
                placementID: old.placementID, workspaceID: old.workspaceID,
                subjectKind: old.subjectKind, subjectID: old.subjectID,
                planRevision: newReference, spatialFrameID: old.spatialFrameID,
                x: old.x, y: old.y, assetLocatorBinding: old.assetLocatorBinding,
                disposition: .accepted, predecessor: old, revision: old.revision + 1,
                mutationID: try C19TestSupportV1.mutation(120),
                recordedAt: C19TestSupportV1.now.addingTimeInterval(1)
            )
            return .init(placementID: old.placementID,
                         before: .init(placementID: old.placementID, revision: old.revision,
                                       placementSHA256: old.placementSHA256),
                         proposedAfter: next, disposition: .accepted, residualMillionths: 0)
        }
        return try .init(componentID: componentID, componentVersion: componentVersion,
                         rows: rows, warnings: [], requiresReview: true)
    }
}

final class V9_82PlanOfflineWorkTests: XCTestCase {
    func testV23P04C19G01ColdLaunchPreparedPacketProvesExactOfflineReadiness() throws {
        let source = try C19TestSupportV1.source()
        let value = try OfflineWorkPacketReadinessV1(source: source)
        try value.validateIntrinsic(); try value.validate(source: source)
        XCTAssertEqual(value.status, .ready)
        XCTAssertEqual(value.contentBinding?.byteLength, 4)
        XCTAssertEqual(value.openability?.state, .openable)
        XCTAssertEqual(value.fieldReference?.availability, .readyOffline)
        XCTAssertEqual(try PlanOfflineReadinessManifestBindingV1(value).readinessSHA256,
                       value.readinessSHA256)
        let absent = try C19TestSupportV1.source(applicability: .notApplicable, planAbsent: true)
        let noPlan = try OfflineWorkPacketReadinessV1(source: absent)
        XCTAssertNil(noPlan.planRevision)
        XCTAssertNil(noPlan.contentBinding)
        XCTAssertEqual(noPlan.status, .ready)
        XCTAssertThrowsError(try C19TestSupportV1.source(applicability: .required,
                                                         planAbsent: true).validate())
    }

    func testV23P04C19A01PlacementCreateMoveResumeAndAccessiblePoseParity() throws {
        let source = try C19TestSupportV1.source()
        let fixture = try C19TestSupportV1.fixture()
        let binding = try PlanPlacementPoseBindingV1(
            placementID: fixture.placement.placementID, assetID: fixture.placement.subjectID,
            placementEventID: C19TestSupportV1.id(84),
            physicalEpisodeID: .init(rawValue: C19TestSupportV1.id(83))
        )
        let revision = try fixture.revision.reference
        let observed = try PlanMaterializedPoseSnapshotV1(
            placement: fixture.placement, binding: binding,
            event: C19TestSupportV1.poseEvent(fixture: fixture, observed: true, axis: "forward"),
            planRevision: revision
        )
        let notObserved = try PlanMaterializedPoseSnapshotV1(
            placement: fixture.placement, binding: binding,
            event: C19TestSupportV1.poseEvent(fixture: fixture, observed: false, axis: "secondary"),
            planRevision: revision
        )
        let viewport = try PlanViewportPresentationV1(
            pageID: fixture.page.pageID, zoomMillionths: 1_000_000,
            panXMillionths: 0, panYMillionths: 0, displayedRotation: .degrees90
        )
        let surface = try PlanWorkSurfaceStateV1(
            source: source, selectedPageID: fixture.page.pageID,
            selectedPlacementID: fixture.placement.placementID, viewport: viewport,
            resumeDraft: nil, poseSnapshots: [notObserved, observed],
            evaluatedAt: C19TestSupportV1.now
        )
        try surface.validateIntrinsic()
        XCTAssertEqual(surface.placements.map(\.accessibilityOrdinal), [1])
        XCTAssertEqual(surface.poseSnapshots.map(\.disposition), [.observed, .notObserved])
        XCTAssertFalse(PlanViewportPresentationV1.conveysPhysicalDirection)
        let foreignBinding = try PlanPlacementPoseBindingV1(
            placementID: fixture.placement.placementID, assetID: fixture.placement.subjectID,
            placementEventID: C19TestSupportV1.id(999),
            physicalEpisodeID: .init(rawValue: C19TestSupportV1.id(83))
        )
        XCTAssertThrowsError(try observed.validate(placement: fixture.placement,
                                                    binding: foreignBinding,
                                                    planRevision: revision))
    }

    func testV23P04C19H01MissingCorruptWithdrawnEncryptedAndUnsupportedReferencesFailClosed() throws {
        for state in [PlanDocumentOpenabilityStateV1.missing, .partial, .corrupt,
                      .encrypted, .unsupportedDocument, .uncheckable] {
            let value = try OfflineWorkPacketReadinessV1(
                source: C19TestSupportV1.source(openability: state)
            )
            XCTAssertEqual(value.status, .blocked)
            XCTAssertFalse(value.findings.isEmpty)
        }
        XCTAssertEqual(try C19TestSupportV1.corpus().caseCount, 45)
        let cases = try C19TestSupportV1.corpus().cases
        XCTAssertEqual(cases.map(\.id), cases.map(\.id).sorted())
        XCTAssertEqual(Set(cases.map(\.id)).count, 45)
        XCTAssertTrue(cases.contains(where: { $0.scenario == "expired field reference" }))
        XCTAssertTrue(cases.contains(where: { $0.scenario == "withdrawn field reference" }))
        XCTAssertTrue(cases.contains(where: { $0.scenario == "concurrent placement move and rebase" }))
        let fixture = try C19TestSupportV1.fixture()
        XCTAssertNoThrow(try PlanOfflineWorkRequestV1(
            workspaceID: C19TestSupportV1.workspace(),
            packet: WorkPacketManifestReferenceV1(fixture.manifest),
            item: WorkPacketItemReferenceV1(manifest: fixture.manifest, item: fixture.item),
            applicability: .notApplicable, exactPlanRevision: nil,
            checkedAt: C19TestSupportV1.now
        ))
        XCTAssertThrowsError(try PlanOfflineWorkRequestV1(
            workspaceID: C19TestSupportV1.workspace(),
            packet: WorkPacketManifestReferenceV1(fixture.manifest),
            item: WorkPacketItemReferenceV1(manifest: fixture.manifest, item: fixture.item),
            applicability: .required, exactPlanRevision: nil,
            checkedAt: C19TestSupportV1.now
        ))
        XCTAssertThrowsError(try PlanOfflineWorkCoordinatorV1.validateResumeEligibility(
            source: C19TestSupportV1.source(disposition: .historic), hasResumeDraft: true
        ))
        XCTAssertThrowsError(try PlanOfflineWorkCoordinatorV1.validateResumeEligibility(
            source: C19TestSupportV1.source(protectedDataAvailable: false), hasResumeDraft: true
        ))
        XCTAssertNoThrow(try PlanOfflineWorkCoordinatorV1.validateResumeEligibility(
            source: C19TestSupportV1.source(), hasResumeDraft: true
        ))
    }

    func testV23P04C19I01RebaseApproveRejectAndInterruptedActivationAreIdempotent() throws {
        let preview = try C19TestSupportV1.preview()
        let pending = try RebaseReviewStateV1.pending(preview: preview,
                                                      evaluatedAt: C19TestSupportV1.now)
        XCTAssertEqual(pending.disposition, .pending)
        let receipt = try RebaseReceiptV1(
            receiptID: C19TestSupportV1.id(130), preview: preview, decision: .rejected,
            resultingRevision: nil, resultingPlacementsSHA256: nil,
            canonicalPlanMutationSHA256: nil,
            reviewedBy: try C19TestSupportV1.actor(.reviewedBy, slot: 131),
            recordedAt: C19TestSupportV1.now.addingTimeInterval(3), revision: 1,
            mutationID: try C19TestSupportV1.mutation(133)
        )
        let first = try RebaseReviewStateV1.resolved(
            preview: preview, receipt: receipt, evaluatedAt: C19TestSupportV1.now.addingTimeInterval(4)
        )
        let replay = try RebaseReviewStateV1.resolved(
            preview: preview, receipt: receipt, evaluatedAt: C19TestSupportV1.now.addingTimeInterval(4)
        )
        XCTAssertEqual(first, replay)
        XCTAssertEqual(first.disposition, .rejected)
        XCTAssertEqual(first.rows, preview.rows)
    }

    func testV23P04C19R01RestoreRebuildAndHistoricReportRetainOriginalPlanRevision() throws {
        let source = try C19TestSupportV1.source(disposition: .historic)
        let readiness = try OfflineWorkPacketReadinessV1(source: source)
        try readiness.validateIntrinsic()
        XCTAssertEqual(readiness.revisionDisposition, .historic)
        XCTAssertEqual(readiness.planRevision, try source.planRevision?.reference)
        XCTAssertEqual(readiness.contentBinding?.contentSHA256,
                       source.planRevision?.contentBinding.contentSHA256)
        XCTAssertTrue(readiness.findings.contains(where: { $0.code == .historicSource }))
        let encoded = try PlanCanonicalCodecV1.encode(readiness)
        let restored = try PlanCanonicalCodecV1.decode(OfflineWorkPacketReadinessV1.self,
                                                        from: encoded)
        try restored.validateIntrinsic()
        XCTAssertEqual(restored, readiness)
    }
}
