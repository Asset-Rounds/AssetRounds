import Foundation
import XCTest

@testable import FieldEvidenceApp

private enum C29PlanTestFailure: Error {
    case interrupted
}

private enum C29PlanTestSupport {
    static let fixedDate = Date(timeIntervalSince1970: 1_800_010_000)

    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c2900000-0000-4000-8000-%012x", slot))!
    }

    static func workspace(_ slot: Int = 1) -> WorkspaceID {
        WorkspaceID(rawValue: id(slot))
    }

    static func mutation(_ slot: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(slot))
    }

    static func digest(_ character: Character = "a") -> String {
        String(repeating: character, count: 64)
    }

    static func actor(
        workspaceID: WorkspaceID,
        slot: Int,
        responsibility: ResponsibilityKindV1
    ) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(
            actorReferenceID: id(slot),
            workspaceID: workspaceID,
            displayName: "C29 local plan reviewer"
        )
        return try ActorSnapshotV1(
            snapshotID: id(slot + 1),
            workspaceID: workspaceID,
            actor: reference,
            responsibility: responsibility,
            displayNameAtTime: reference.displayName,
            capturedAt: fixedDate
        )
    }

    static func contentAndRelease(workspaceID: WorkspaceID) throws -> (ContentReferenceV1, ContentLocatorV1, FieldReferenceReleaseV1) {
        let contentDigest = try ContentDigestV1(
            algorithm: .sha256,
            hexadecimalValue: digest("b")
        )
        let manifestEntry = try ContentManifestEntryV1(
            contentID: "c29-plan-pdf",
            expectedByteLength: 4,
            mediaType: "application/pdf",
            digest: contentDigest,
            expectedLocatorRevision: 1,
            requiredForOpen: true
        )
        let manifest = try ContentManifestV1(
            manifestID: "c29-plan-manifest",
            workspaceID: workspaceID.rawValue.uuidString.lowercased(),
            manifestRevision: 1,
            entries: [manifestEntry]
        )
        let content = try ContentReferenceV1(
            workspaceID: workspaceID.rawValue.uuidString.lowercased(),
            contentID: manifestEntry.contentID,
            byteLength: manifestEntry.expectedByteLength,
            mediaType: manifestEntry.mediaType,
            digests: try ContentDigestSetV1([contentDigest]),
            byteRole: .immutableOriginal,
            createdAt: "2026-08-29T00:00:00.000Z"
        )
        let locator = try ContentLocatorV1(
            locatorID: "c29-plan-locator",
            workspaceID: content.workspaceID,
            contentID: content.contentID,
            locatorRevision: 1,
            contentDigest: contentDigest,
            expectedByteLength: content.byteLength
        )
        let provenance = try FieldReferenceProvenanceV1(
            kind: .synthetic,
            sourceName: "C29 local fixture",
            sourceReleaseIdentifier: "c29-plan-fixture-1",
            licenseScope: .localUseOnly
        )
        let release = try FieldReferenceReleaseV1(
            releaseID: id(4),
            workspaceID: workspaceID,
            referencePackID: "c29-plan-reference-pack",
            kind: .drawing,
            semanticVersion: "1.0.0",
            provenance: provenance,
            manifest: manifest,
            issuedAt: fixedDate,
            revision: 1,
            mutationID: try mutation(5)
        )
        return (content, locator, release)
    }

    struct Fixture {
        let workspaceID: WorkspaceID
        let content: ContentReferenceV1
        let locator: ContentLocatorV1
        let release: FieldReferenceReleaseV1
        let binding: PlanContentBindingV1
        let prerequisites: PlanPrerequisiteClosureV1
        let document: PlanDocumentV1
        let oldRevision: PlanRevisionV1
        let newRevision: PlanRevisionV1
        let frame: SpatialReferenceFrameV1
        let oldPlacement: PlanPlacementV1
        let registry: PlanRebaseComponentRegistryV1
        let preview: RebasePreviewV1

        var oldPlacements: [PlanPlacementV1] { [oldPlacement] }

        var newPlacements: [PlanPlacementV1] {
            preview.rows.compactMap(\.proposedAfter)
        }
    }

    static func fixture(requiresReview: Bool = false) throws -> Fixture {
        let workspaceID = workspace()
        let (content, locator, release) = try contentAndRelease(workspaceID: workspaceID)
        let binding = try PlanContentBindingV1(content: content, locator: locator, fieldReferenceRelease: release)
        let prerequisites = PlanPrerequisiteClosureV1(
            content: content,
            contentLocator: locator,
            fieldReferenceRelease: release,
            assetLocators: [],
            locatorBindingReceipts: []
        )
        let document = try PlanDocumentV1(
            planDocumentID: id(10),
            workspaceID: workspaceID,
            stablePlanKey: "c29-plan-key",
            displayName: "C29 plan",
            revision: 1,
            mutationID: try mutation(11),
            recordedAt: fixedDate
        )
        let crop = try PlanCropRectV1(
            minX: try NormalizedPlanCoordinateV1(millionths: 0),
            minY: try NormalizedPlanCoordinateV1(millionths: 0),
            maxX: try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale),
            maxY: try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale)
        )
        let page = try PlanPageReferenceV1(
            pageID: id(20),
            sourcePageOrdinal: 0,
            presentedPageOrdinal: 0,
            pixelWidth: 2_000,
            pixelHeight: 1_000,
            crop: crop,
            rotation: .degrees0,
            sourcePageSHA256: digest("c")
        )
        let frame = try SpatialReferenceFrameV1(frameID: id(21), pageID: page.pageID)
        let oldRevision = try PlanRevisionV1(
            planRevisionID: id(30),
            workspaceID: workspaceID,
            planDocument: try document.reference,
            contentBinding: binding,
            pages: [page],
            spatialFrames: [frame],
            state: .released,
            revision: 1,
            mutationID: try mutation(31),
            recordedBy: try actor(workspaceID: workspaceID, slot: 32, responsibility: .recordedBy),
            recordedAt: fixedDate
        )
        let newRevision = try PlanRevisionV1(
            planRevisionID: id(40),
            workspaceID: workspaceID,
            planDocument: try document.reference,
            contentBinding: binding,
            pages: [page],
            spatialFrames: [frame],
            state: .released,
            predecessor: oldRevision,
            revision: 2,
            mutationID: try mutation(90),
            recordedBy: try actor(workspaceID: workspaceID, slot: 42, responsibility: .recordedBy),
            recordedAt: fixedDate.addingTimeInterval(1)
        )
        let oldPlacement = try PlanPlacementV1(
            placementID: id(50),
            workspaceID: workspaceID,
            subjectKind: .location,
            subjectID: id(51),
            planRevision: try oldRevision.reference,
            spatialFrameID: frame.frameID,
            x: try NormalizedPlanCoordinateV1(millionths: 300_000),
            y: try NormalizedPlanCoordinateV1(millionths: 400_000),
            disposition: .accepted,
            revision: 1,
            mutationID: try mutation(52),
            recordedAt: fixedDate
        )
        let component = C29PlanComponent(
            componentID: "c29.identity",
            stableSortOrdinal: 0,
            requiresReview: requiresReview
        )
        let registry = try PlanRebaseComponentRegistryV1(components: [component])
        let preview = try PlanRebasePreviewBuilderV1.build(
            previewID: id(60),
            workspaceID: workspaceID,
            oldRevision: oldRevision,
            newRevision: newRevision,
            transform: try identityTransform(),
            placements: [oldPlacement],
            registry: registry,
            expectedRevision: 1,
            generatedAt: fixedDate.addingTimeInterval(2)
        )
        return Fixture(
            workspaceID: workspaceID,
            content: content,
            locator: locator,
            release: release,
            binding: binding,
            prerequisites: prerequisites,
            document: document,
            oldRevision: oldRevision,
            newRevision: newRevision,
            frame: frame,
            oldPlacement: oldPlacement,
            registry: registry,
            preview: preview
        )
    }

    static func identityTransform() throws -> PlanAffineTransformV1 {
        try PlanAffineTransformV1(
            m11: PlanLimitsV1.transformScale,
            m12: 0,
            m21: 0,
            m22: PlanAffineTransformV1.transformScale,
            tx: 0,
            ty: 0
        )
    }
}

private struct C29PlanComponent: PlanRebaseComponentV1 {
    let componentID: String
    let componentVersion: Int = 1
    let stableSortOrdinal: Int
    let requiresReview: Bool
    let xOffset: Int64

    init(componentID: String, stableSortOrdinal: Int, requiresReview: Bool, xOffset: Int64 = 0) {
        self.componentID = componentID
        self.stableSortOrdinal = stableSortOrdinal
        self.requiresReview = requiresReview
        self.xOffset = xOffset
    }

    func evaluate(_ context: PlanRebaseComponentContextV1) throws -> PlanRebaseComponentContributionV1 {
        let newRevision = try context.newRevision.reference
        let rows = try context.placements.map { placement -> PlanRebaseRowV1 in
            let transformed = try context.transform.applying(x: placement.x, y: placement.y)
            let x = try NormalizedPlanCoordinateV1(millionths: transformed.0 + xOffset)
            let y = try NormalizedPlanCoordinateV1(millionths: transformed.1)
            let proposed = try PlanPlacementV1(
                placementID: placement.placementID,
                workspaceID: context.workspaceID,
                subjectKind: placement.subjectKind,
                subjectID: placement.subjectID,
                planRevision: newRevision,
                spatialFrameID: placement.spatialFrameID,
                x: x,
                y: y,
                assetLocatorBinding: placement.assetLocatorBinding,
                disposition: .accepted,
                predecessor: placement,
                revision: placement.revision + 1,
                mutationID: try C29PlanTestSupport.mutation(90),
                recordedAt: C29PlanTestSupport.fixedDate.addingTimeInterval(1)
            )
            return PlanRebaseRowV1(
                placementID: placement.placementID,
                before: PlanPlacementReferenceV1(
                    placementID: placement.placementID,
                    revision: placement.revision,
                    placementSHA256: placement.placementSHA256
                ),
                proposedAfter: proposed,
                disposition: .accepted,
                residualMillionths: 0
            )
        }
        return try PlanRebaseComponentContributionV1(
            componentID: componentID,
            componentVersion: componentVersion,
            rows: rows,
            warnings: [],
            requiresReview: requiresReview
        )
    }
}

@MainActor
private final class C29CapturingWriter: PlanRebaseWorkspaceWritingV1 {
    private(set) var received: PlanMutationV1?

    func commitPlan(
        _ mutation: PlanMutationV1,
        validatedAgainst preview: RebasePreviewV1
    ) throws -> MutationReceiptV1 {
        received = mutation
        try mutation.validate()
        throw C29PlanTestFailure.interrupted
    }
}

private struct C29NoReceiptRecovery: PlanRebaseReceiptRecoveringV1 {
    func acceptedPlanMutationReceipt(mutationID: MutationIDV1) throws -> MutationReceiptV1? {
        nil
    }
}

@MainActor
final class V9_43PlanRebaseTests: XCTestCase {
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
    func testV23P03C29G01ImmutableRevisionAndNormalizedPlacementProduceOneDeterministicRebaseReceipt() throws {
        let first = try C29PlanTestSupport.fixture()
        let second = try C29PlanTestSupport.fixture()

        XCTAssertEqual(first.document.documentSHA256, second.document.documentSHA256)
        XCTAssertEqual(first.oldRevision.revisionSHA256, second.oldRevision.revisionSHA256)
        XCTAssertEqual(first.preview, second.preview)
        XCTAssertEqual(first.preview.rows.map(\.placementID), first.preview.rows.sorted().map(\.placementID))
        XCTAssertEqual(first.oldPlacement.x.millionths, 300_000)
        XCTAssertEqual(first.oldPlacement.y.millionths, 400_000)
        XCTAssertEqual(first.preview.rows.first?.disposition, .accepted)
        XCTAssertEqual(first.preview.requiresReview, false)
        XCTAssertEqual(try PlanRebasePreviewBuilderV1.placementSetSHA256(first.oldPlacements),
                       try PlanRebasePreviewBuilderV1.placementSetSHA256(Array(first.oldPlacements.reversed())))
        XCTAssertEqual(try PlanCanonicalCodecV1.decode(
            RebasePreviewV1.self,
            from: PlanCanonicalCodecV1.encode(first.preview)
        ), first.preview)
        XCTAssertThrowsError(try NormalizedPlanCoordinateV1(millionths: -1))
        XCTAssertThrowsError(try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale + 1))
    }

    func testV23P03C29A01MissingUnsupportedOrInaccessiblePlanPreservesCompleteManualFallback() throws {
        let fixture = try C29PlanTestSupport.fixture()
        let writer = C29CapturingWriter()
        let coordinator = PlanRebaseCoordinatorV1(registry: fixture.registry, writer: writer)
        let preview = try coordinator.preview(
            previewID: fixture.preview.previewID,
            workspaceID: fixture.workspaceID,
            oldRevision: fixture.oldRevision,
            newRevision: fixture.newRevision,
            transform: fixture.preview.transform,
            placements: fixture.oldPlacements,
            oldPrerequisites: fixture.prerequisites,
            newPrerequisites: fixture.prerequisites,
            expectedRevision: fixture.preview.expectedRevision,
            generatedAt: fixture.preview.generatedAt
        )

        XCTAssertEqual(preview, fixture.preview)
        XCTAssertTrue(writer.received == nil)
        XCTAssertEqual(fixture.oldRevision.contentBinding.contentID, fixture.content.contentID)
        XCTAssertEqual(fixture.oldRevision.contentBinding.fieldReferenceReleaseID, fixture.release.releaseID)
        XCTAssertEqual(fixture.oldRevision.contentBinding.locatorID, fixture.locator.locatorID)
        XCTAssertEqual(fixture.frame.coordinateConvention, SpatialReferenceFrameV1.coordinateConvention)
        XCTAssertEqual(fixture.oldRevision.pages.first?.pageID, fixture.frame.pageID)
        try fixture.binding.validate(content: fixture.content, locator: fixture.locator, release: fixture.release)
        let forgedLocator = try ContentLocatorV1(
            locatorID: "c29-forged-locator",
            workspaceID: fixture.content.workspaceID,
            contentID: fixture.content.contentID,
            locatorRevision: 2,
            contentDigest: try ContentDigestV1(algorithm: .sha256, hexadecimalValue: C29PlanTestSupport.digest("d")),
            expectedByteLength: fixture.content.byteLength
        )
        XCTAssertThrowsError(try PlanContentBindingV1(
            content: fixture.content,
            locator: forgedLocator,
            fieldReferenceRelease: fixture.release
        ))
    }

    func testV23P03C29H01CorruptHugeInvalidBoundsAndRegistryForksFailClosedWithoutPartialActivation() throws {
        let fixture = try C29PlanTestSupport.fixture()

        XCTAssertThrowsError(try C29PlanTestSupport.fixture().registry.evaluate(
            PlanRebaseComponentContextV1(
                workspaceID: fixture.workspaceID,
                oldRevision: fixture.oldRevision,
                newRevision: fixture.newRevision,
                transform: try C29PlanTestSupport.identityTransform(),
                placements: fixture.oldPlacements + fixture.oldPlacements
            )
        ))
        XCTAssertThrowsError(try PlanRebaseComponentRegistryV1(components: [
            C29PlanComponent(componentID: "c29.one", stableSortOrdinal: 0, requiresReview: false),
            C29PlanComponent(componentID: "c29.two", stableSortOrdinal: 0, requiresReview: false)
        ]))
        XCTAssertThrowsError(try RebasePreviewV1(
            previewID: fixture.preview.previewID,
            workspaceID: fixture.workspaceID,
            oldRevision: try fixture.oldRevision.reference,
            newRevision: try fixture.newRevision.reference,
            transform: fixture.preview.transform,
            registrySHA256: fixture.registry.registrySHA256,
            registryVersion: fixture.registry.registryVersion + 1,
            componentDescriptors: fixture.registry.descriptors,
            contributions: fixture.preview.contributions,
            expectedRevision: fixture.preview.expectedRevision,
            generatedAt: fixture.preview.generatedAt
        ))
        XCTAssertThrowsError(try PlanAffineTransformV1(
            m11: Int64.max,
            m12: Int64.max,
            m21: Int64.max,
            m22: Int64.max,
            tx: 0,
            ty: 0
        ))
        XCTAssertThrowsError(try PlanDocumentV1(
            planDocumentID: C29PlanTestSupport.id(70),
            workspaceID: fixture.workspaceID,
            stablePlanKey: "c29-infinite",
            displayName: "invalid",
            revision: 1,
            mutationID: try C29PlanTestSupport.mutation(71),
            recordedAt: Date(timeIntervalSinceReferenceDate: .infinity)
        ))

        let foreignPlacement = try fixture.oldPlacement.rebound(
            to: C29PlanTestSupport.workspace(2),
            planRevision: fixture.oldPlacement.planRevision,
            assetLocatorBinding: nil,
            predecessor: nil
        )
        XCTAssertThrowsError(try PlanRebasePreviewBuilderV1.build(
            previewID: fixture.preview.previewID,
            workspaceID: fixture.workspaceID,
            oldRevision: fixture.oldRevision,
            newRevision: fixture.newRevision,
            transform: fixture.preview.transform,
            placements: [foreignPlacement],
            registry: fixture.registry,
            expectedRevision: 1,
            generatedAt: fixture.preview.generatedAt
        ))

        let context = PlanRebaseComponentContextV1(
            workspaceID: fixture.workspaceID,
            oldRevision: fixture.oldRevision,
            newRevision: fixture.newRevision,
            transform: fixture.preview.transform,
            placements: fixture.oldPlacements
        )
        let first = try C29PlanComponent(
            componentID: "c29.first",
            stableSortOrdinal: 0,
            requiresReview: false
        ).evaluate(context)
        let conflicting = try C29PlanComponent(
            componentID: "c29.second",
            stableSortOrdinal: 1,
            requiresReview: false,
            xOffset: 1
        ).evaluate(context)
        XCTAssertThrowsError(try RebasePreviewV1(
            previewID: fixture.preview.previewID,
            workspaceID: fixture.workspaceID,
            oldRevision: try fixture.oldRevision.reference,
            newRevision: try fixture.newRevision.reference,
            transform: fixture.preview.transform,
            registrySHA256: fixture.registry.registrySHA256,
            registryVersion: fixture.registry.registryVersion,
            componentDescriptors: fixture.registry.descriptors,
            contributions: [first, conflicting],
            expectedRevision: 1,
            generatedAt: fixture.preview.generatedAt
        ))
    }

    func testV23P03C29I01InterruptedApprovalExposesOldSetOrOneSealedNewSet() throws {
        let fixture = try C29PlanTestSupport.fixture(requiresReview: true)
        XCTAssertTrue(fixture.preview.requiresReview)
        let writer = C29CapturingWriter()
        let coordinator = PlanRebaseCoordinatorV1(registry: fixture.registry, writer: writer)
        let reviewer = try C29PlanTestSupport.actor(
            workspaceID: fixture.workspaceID,
            slot: 80,
            responsibility: .reviewedBy
        )

        XCTAssertThrowsError(try coordinator.approve(
            preview: fixture.preview,
            newRevision: fixture.newRevision,
            predecessorRevision: fixture.oldRevision,
            placements: fixture.newPlacements,
            predecessorPlacements: fixture.oldPlacements,
            receiptID: C29PlanTestSupport.id(81),
            prerequisites: fixture.prerequisites,
            predecessorReceipt: nil,
            mutationID: try C29PlanTestSupport.mutation(90),
            reviewedBy: reviewer,
            recordedAt: C29PlanTestSupport.fixedDate.addingTimeInterval(3)
        ))
        XCTAssertNotNil(writer.received)
        try writer.received?.validate()

        let adapter = PlanLifecycleAdapterV1(
            coordinator: coordinator,
            recovery: C29NoReceiptRecovery()
        )
        XCTAssertEqual(
            try adapter.recover(mutationID: try C29PlanTestSupport.mutation(90)),
            .retryRequired
        )
        XCTAssertEqual(fixture.oldPlacements, [fixture.oldPlacement])
    }

    func testV23P03C29R01RestorePreservesOriginalRevisionHistoricReportAndOfflineReadiness() throws {
        let fixture = try C29PlanTestSupport.fixture()
        let writer = C29CapturingWriter()
        let coordinator = PlanRebaseCoordinatorV1(registry: fixture.registry, writer: writer)
        let rejection = try coordinator.rejectionReceipt(
            preview: fixture.preview,
            receiptID: C29PlanTestSupport.id(100),
            predecessorReceipt: nil,
            mutationID: try C29PlanTestSupport.mutation(101),
            reviewedBy: try C29PlanTestSupport.actor(
                workspaceID: fixture.workspaceID,
                slot: 102,
                responsibility: .reviewedBy
            ),
            recordedAt: C29PlanTestSupport.fixedDate.addingTimeInterval(3)
        )
        try rejection.validate(preview: fixture.preview)

        let closure = PlanLifecycleClosureV1(
            documentHistory: [fixture.document],
            revisionHistory: [fixture.oldRevision, fixture.newRevision],
            placementHistory: [fixture.oldPlacement] + fixture.newPlacements,
            receipts: [rejection]
        )
        try closure.validate()
        XCTAssertEqual(try PlanDocumentRow(fixture.document).value(), fixture.document)
        XCTAssertEqual(try PlanRevisionRow(fixture.oldRevision).value(), fixture.oldRevision)
        XCTAssertEqual(try PlanPlacementRow(fixture.oldPlacement).value(), fixture.oldPlacement)
        XCTAssertEqual(try RebaseReceiptRow(rejection).value(), rejection)
        XCTAssertEqual(try PlanCanonicalCodecV1.decode(
            PlanDocumentV1.self,
            from: PlanCanonicalCodecV1.encode(fixture.document)
        ), fixture.document)

        let cloneWorkspace = C29PlanTestSupport.workspace(3)
        let clone = try fixture.document.rebound(to: cloneWorkspace, predecessor: nil)
        XCTAssertEqual(clone.stablePlanKey, fixture.document.stablePlanKey)
        XCTAssertEqual(clone.displayName, fixture.document.displayName)
        XCTAssertNotEqual(clone.workspaceID, fixture.document.workspaceID)
        XCTAssertNotEqual(clone.documentSHA256, fixture.document.documentSHA256)
        XCTAssertEqual(fixture.document.revision, 1)
        XCTAssertEqual(fixture.oldRevision.revision, 1)
        XCTAssertEqual(fixture.newRevision.revision, 2)
        XCTAssertEqual(writer.received, nil)
    }
}
