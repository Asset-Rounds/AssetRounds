import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private enum C47ActivityTestSupport {
    static let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "47000000-0000-4000-8000-%012d", slot))!
    }

    static func workspace(_ slot: Int = 1) -> WorkspaceID {
        WorkspaceID(rawValue: id(slot))
    }

    static func mutation(_ slot: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(slot))
    }

    static func digest(_ character: Character) -> String {
        String(repeating: character, count: 64)
    }

    static func contentReference(
        workspaceID: WorkspaceID,
        slot: Int,
        digestCharacter: Character
    ) throws -> ContentReferenceV1 {
        try ContentReferenceV1(
            workspaceID: workspaceID.rawValue.uuidString.lowercased(),
            contentID: id(slot).uuidString.lowercased(),
            byteLength: 1,
            mediaType: "application/octet-stream",
            digests: ContentDigestSetV1([
                try ContentDigestV1(
                    algorithm: .sha256,
                    hexadecimalValue: digest(digestCharacter)
                )
            ]),
            byteRole: .immutableOriginal,
            createdAt: "2027-01-15T08:00:00.000Z"
        )
    }

    struct EvidenceFixture {
        let reference: ContentReferenceV1
        let file: EvidenceFile
        let originalJPEG: Data
        let thumbnailJPEG: Data
    }

    static func evidenceFixture(
        workspaceID: WorkspaceID,
        slot: Int,
        recordSlot: Int
    ) throws -> EvidenceFixture {
        let sourcePNG = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        let normalized = try MediaNormalizerV1().normalize(sourcePNG)
        let originalSHA256 = KernelCanonicalHashV1.sha256(normalized.originalJPEG)
        let thumbnailSHA256 = KernelCanonicalHashV1.sha256(normalized.thumbnailJPEG)
        let reference = try ContentReferenceV1(
            workspaceID: workspaceID.rawValue.uuidString.lowercased(),
            contentID: id(slot).uuidString.lowercased(),
            byteLength: Int64(normalized.originalJPEG.count),
            mediaType: "image/jpeg",
            digests: try ContentDigestSetV1([
                try ContentDigestV1(
                    algorithm: .sha256,
                    hexadecimalValue: originalSHA256
                )
            ]),
            byteRole: .immutableOriginal,
            createdAt: "2027-01-15T08:00:00.000Z"
        )
        let canonicalID = id(slot).uuidString.lowercased()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdAt = try XCTUnwrap(formatter.date(from: reference.createdAt))
        let file = EvidenceFile(
            id: id(slot),
            recordID: id(recordSlot),
            purposeKey: "wide_context",
            relativePath: "evidence/\(canonicalID)/original.jpg",
            mimeType: "image/jpeg",
            byteCount: normalized.originalJPEG.count,
            sha256: originalSHA256,
            createdAt: createdAt,
            thumbnailRelativePath: "evidence/\(canonicalID)/thumbnail.jpg",
            thumbnailByteCount: normalized.thumbnailJPEG.count,
            thumbnailSHA256: thumbnailSHA256
        )
        return EvidenceFixture(
            reference: reference,
            file: file,
            originalJPEG: normalized.originalJPEG,
            thumbnailJPEG: normalized.thumbnailJPEG
        )
    }

    static func actor(
        workspaceID: WorkspaceID = workspace(),
        slot: Int = 80,
        responsibility: ResponsibilityKindV1 = .recordedBy
    ) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(
            actorReferenceID: id(slot),
            workspaceID: workspaceID,
            displayName: "C47 recorded operator"
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

    static func planPlacement(
        workspaceID: WorkspaceID,
        subjectID: UUID,
        slot: Int,
        mutationSlot: Int
    ) throws -> PlanPlacementV1 {
        try PlanPlacementV1(
            placementID: id(slot),
            workspaceID: workspaceID,
            subjectKind: .location,
            subjectID: subjectID,
            planRevision: PlanRevisionReferenceV1(
                planRevisionID: id(slot + 1),
                planDocumentID: id(slot + 2),
                revision: 1,
                revisionSHA256: digest("c")
            ),
            spatialFrameID: id(slot + 3),
            x: try NormalizedPlanCoordinateV1(millionths: 125_000),
            y: try NormalizedPlanCoordinateV1(millionths: 250_000),
            disposition: .accepted,
            revision: 1,
            mutationID: try mutation(mutationSlot),
            recordedAt: fixedDate
        )
    }

    static func poseEvent(
        workspaceID: WorkspaceID,
        assetID: UUID,
        eventSlot: Int,
        mutationSlot: Int
    ) throws -> AssetPoseEventV1 {
        let descriptor = try PoseAxisDescriptorV1(
            axisID: try PoseAxisID(rawValue: "axis.c47.\(eventSlot)"),
            localizedLabelKey: "pose.c47",
            semanticRole: .assetForwardAxis,
            requiredComponents: .azimuthOnly,
            observationRequirement: .optional,
            applicability: .applicable
        )
        let pose = try PlacementPoseV1(
            disposition: .observed,
            referenceFrame: .trueBearing,
            azimuth: try PoseAngleMilliDegreesV1(kind: .azimuth, milliDegrees: 0),
            horizontalUncertainty: .known(
                try PoseAngleMilliDegreesV1(kind: .horizontalUncertainty, milliDegrees: 1)
            ),
            descriptor: descriptor
        )
        return try AssetPoseEventV1(
            eventID: id(eventSlot),
            workspaceID: workspaceID,
            assetID: assetID,
            axisDescriptor: descriptor,
            placementEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: id(eventSlot + 1)),
            placementEventID: id(eventSlot + 2),
            locationPathSnapshot: try LocationPathSnapshotV1(
                siteID: id(eventSlot + 3),
                siteDisplay: "C47 site",
                nodes: []
            ),
            pose: pose,
            source: .manual,
            rootObservationEventID: id(eventSlot),
            rootObservedAt: fixedDate,
            predecessor: nil,
            revision: 1,
            mutationID: try mutation(mutationSlot),
            recordedBy: try actor(
                workspaceID: workspaceID,
                slot: eventSlot + 4,
                responsibility: .observedBy
            ),
            occurredAt: fixedDate,
            recordedAt: fixedDate.addingTimeInterval(1)
        )
    }

    static func installationRelease(
        registry: InspectionPackageRegistryV2,
        workspaceID: WorkspaceID
    ) throws -> InstallationWorkflowDefinitionReleaseV1 {
        let selection = try registry.bundledActivityWorkflowRelease(
            kind: .installation,
            packageID: ShippingIlluminatedSignAdapterV1.packageID,
            workspaceID: workspaceID
        )
        guard case let .installation(value) = selection.release else {
            throw InspectionPackageFailureV2.incompatiblePackage
        }
        return value
    }

    static func punchRelease(
        registry: InspectionPackageRegistryV2,
        workspaceID: WorkspaceID
    ) throws -> PunchReviewWorkflowDefinitionReleaseV1 {
        let selection = try registry.bundledActivityWorkflowRelease(
            kind: .punchReview,
            packageID: ShippingIlluminatedSignAdapterV1.packageID,
            workspaceID: workspaceID
        )
        guard case let .punch(value) = selection.release else {
            throw InspectionPackageFailureV2.incompatiblePackage
        }
        return value
    }

    struct PackageAuthorityFixture {
        let packageRelease: InspectionPackageReleaseV1
        let promoted: PromotedPackageReleaseV1
        let pointer: ActivePackageRegistryPointerV1
    }

    static func packageAuthority(
        workspaceID: WorkspaceID,
        slot: Int
    ) throws -> PackageAuthorityFixture {
        let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let workflow = try WorkflowDefinitionV1(
            workflowID: "c47.activity.authority.v1",
            entryNodeID: "c47.authority.section",
            declaredFieldIDs: [],
            nodes: [
                try WorkflowNodeV1(
                    nodeID: "c47.authority.section",
                    kind: .section,
                    localizationKey: "c47.authority.section",
                    outgoingNodeIDs: ["c47.authority.terminal"]
                ),
                try WorkflowNodeV1(
                    nodeID: "c47.authority.terminal",
                    kind: .terminal,
                    localizationKey: "c47.authority.terminal",
                    outgoingNodeIDs: []
                )
            ]
        )
        let draft = try InspectionPackageReleaseV1.makeDraft(
            package: package,
            workflow: workflow
        )
        let packageRelease = try InspectionPackageReleasePublisherV1.publish(
            InspectionPackageReleasePublisherV1.test(draft)
        ).release
        let authorityMutationID = try mutation(slot + 3)
        let promoted = try PromotedPackageReleaseV1(
            releaseRecordID: id(slot),
            workspaceID: workspaceID,
            packageRelease: packageRelease,
            mutationID: authorityMutationID,
            promotedAt: fixedDate
        )
        let pointer = try ActivePackageRegistryPointerV1(
            pointerID: id(slot + 1),
            workspaceID: workspaceID,
            packageID: packageRelease.packageID,
            activeReleaseRecordID: promoted.releaseRecordID,
            promotionReceiptID: id(slot + 2),
            activePackageReleaseID: packageRelease.packageReleaseID,
            activeReleaseRecordSHA256: promoted.releaseRecordSHA256,
            revision: 1,
            mutationID: authorityMutationID
        )
        return PackageAuthorityFixture(
            packageRelease: packageRelease,
            promoted: promoted,
            pointer: pointer
        )
    }

    static func readiness() throws -> [ActivityReadinessFacetV1] {
        [
            try ActivityReadinessFacetV1(
                facetID: "access",
                kind: .access,
                disposition: .ready
            ),
            try ActivityReadinessFacetV1(
                facetID: "weather",
                kind: .weather,
                disposition: .notApplicable
            )
        ]
    }

    static func envelope(
        kind: ActivityKindV2,
        state: ActivityStateV2 = .draft,
        revision: UInt64 = 1,
        mutationSlot: Int = 10,
        predecessor: ActivitySessionEnvelopeV2? = nil,
        variations: [ActivityVariationV1] = [],
        workspaceID: WorkspaceID? = nil,
        activityID: UUID? = nil
    ) throws -> ActivitySessionEnvelopeV2 {
        try ActivitySessionEnvelopeV2(
            activityID: predecessor?.activityID ?? activityID ?? id(2),
            workspaceID: predecessor?.workspaceID ?? workspaceID ?? workspace(),
            kind: kind,
            state: state,
            reviewState: state == .readyForReview ? .pending : .notRequested,
            subjectID: id(3),
            title: "Recorded field activity",
            readiness: readiness(),
            variations: variations,
            startedAt: state.hasStarted ? fixedDate : nil,
            finalizedAt: state == .finalized ? fixedDate.addingTimeInterval(60) : nil,
            revision: revision,
            mutationID: try mutation(mutationSlot),
            predecessorEnvelopeSHA256: predecessor?.envelopeSHA256
        )
    }

    struct CompletedReportFixture {
        let snapshot: CompletedActivitySnapshotV2
        let manifest: ContractManifestV1
        let layout: ReportLayoutProfileV1
        let export: ExportProfileV1
    }

    static func completedReportFixture(
        workspaceID: WorkspaceID,
        activityID: UUID,
        assetID: UUID,
        sourceRevision: Int
    ) throws -> CompletedReportFixture {
        let formats: [ReportProjectionFormatV1] = [.openJSON, .pdf, .structuredText]
        let sections = try [
            ReportSectionDefinitionV1(
                sectionID: "identity", version: 1, required: true,
                supportedFormats: formats, privacyClass: .mandatoryPublicTruth,
                requiresHeading: true, requiresTextAlternative: true, order: 0
            ),
            ReportSectionDefinitionV1(
                sectionID: "limitations", version: 1, required: true,
                supportedFormats: formats, privacyClass: .mandatoryPublicTruth,
                requiresHeading: true, requiresTextAlternative: true, order: 1
            ),
            ReportSectionDefinitionV1(
                sectionID: "provenance", version: 1, required: true,
                supportedFormats: formats, privacyClass: .mandatoryPublicTruth,
                requiresHeading: true, requiresTextAlternative: true, order: 2
            ),
            ReportSectionDefinitionV1(
                sectionID: "supersession", version: 1, required: true,
                supportedFormats: formats, privacyClass: .mandatoryPublicTruth,
                requiresHeading: true, requiresTextAlternative: true, order: 3
            ),
            ReportSectionDefinitionV1(
                sectionID: "manifest", version: 1, required: true,
                supportedFormats: formats, privacyClass: .mandatoryPublicTruth,
                requiresHeading: true, requiresTextAlternative: true, order: 4
            ),
        ]
        let registry = try ReportSectionRegistryV1(
            registryID: "c47-section-registry-v1",
            registryVersion: 1,
            sections: sections
        )
        let manifest = try ContractManifestV1(
            manifestID: "c47-completed-activity-v2",
            manifestVersion: 1,
            codec: ContractCodecRuleV1(codecVersion: 1),
            compatibility: ContractCompatibilityRuleV1(
                minimumReaderVersion: 1,
                maximumReaderVersion: 1,
                unknownObjectFields: .reject
            ),
            objects: [try ContractObjectDefinitionV1(
                typeID: "completed-snapshot",
                version: 1,
                unknownFieldPolicy: .reject,
                fields: [try ContractFieldDefinitionV1(
                    fieldID: "snapshot-id",
                    jsonName: "snapshotID",
                    kind: .string,
                    required: true,
                    maximumUTF8Bytes: 128
                )]
            )],
            enums: [],
            reportSectionRegistry: registry
        )
        let layout = try ReportLayoutProfileV1(
            profileID: "c47-customer-complete-v1",
            profileRelease: 1,
            audience: .customerSafe,
            detail: .complete,
            sectionIDs: sections.map(\.sectionID),
            mediaLayout: .standardGrid,
            orientation: .portrait,
            localeIdentifier: "en_US",
            unitsProfileID: "units-si-v1",
            displayProfileID: "display-v1",
            registry: registry
        )
        let export = try ExportProfileV1(
            exportProfileID: "c47-portable-v1",
            exportProfileRelease: 1,
            formats: formats,
            packaging: .combined,
            privacyTransformID: "customer-safe-v1",
            maximumMediaItems: 32,
            maximumArchiveBytes: Int64(SnapshotProjectionLimitsV1.maximumProjectionBytes)
        )
        let workspaceToken = workspaceID.rawValue.uuidString.lowercased()
        let activityToken = activityID.uuidString.lowercased()
        let snapshotID = "c47-completed-snapshot-v1"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let profileBinding = try FinalizedReportProfileBindingV1(
            workspaceID: workspaceToken,
            snapshotID: snapshotID,
            outputScopeID: "c47-output-scope-v1",
            reportProfileID: layout.profileID,
            reportProfileRelease: layout.profileRelease,
            reportProfileSHA256: KernelCanonicalHashV1.sha256(try encoder.encode(layout)),
            exportProfileID: export.exportProfileID,
            exportProfileRelease: export.exportProfileRelease,
            exportProfileSHA256: KernelCanonicalHashV1.sha256(try encoder.encode(export)),
            sectionRegistryID: registry.registryID,
            sectionRegistryVersion: registry.registryVersion,
            sectionRegistrySHA256: KernelCanonicalHashV1.sha256(try encoder.encode(registry)),
            contractManifestID: manifest.manifestID,
            contractManifestVersion: manifest.manifestVersion,
            contractManifestSHA256: KernelCanonicalHashV1.sha256(try encoder.encode(manifest)),
            sectionIDs: layout.sectionIDs,
            audience: .customerSafe,
            detail: .complete,
            privacyTransformID: export.privacyTransformID,
            localeIdentifier: layout.localeIdentifier,
            unitsProfileID: layout.unitsProfileID,
            displayProfileID: layout.displayProfileID,
            orientation: layout.orientation,
            mediaLayout: layout.mediaLayout,
            rendererVersion: ReportSemanticProjectorV1.rendererVersion,
            projectionVersion: "c47-activity-contract-v2"
        )
        let activity = try CompletedActivitySnapshotPayloadV1(
            workspaceID: workspaceToken,
            snapshotID: snapshotID,
            snapshotRevision: 1,
            sourceActivityID: activityToken,
            sourceRevision: sourceRevision,
            reportID: "c47-report-v1",
            packageReleaseID: "c47-bundled-workflow-v1",
            generatedAt: "2027-01-15T08:00:00.000Z",
            completedAt: "2027-01-15T08:00:00.000Z",
            supersedesSnapshotID: nil,
            supersededSnapshotSHA256: nil,
            amendmentReason: nil,
            profileBinding: profileBinding,
            serviceFacts: [],
            evidenceCards: [],
            limitations: ["Recorded completion is not approval, certification, or authorization."]
        )
        let siteID = id(410)
        let locationPath = try LocationPathSnapshotV1(
            siteID: siteID,
            siteDisplay: "Recorded site",
            nodes: []
        )
        let placement = try AssetPlacementEventV1(
            id: id(411),
            workspaceID: workspaceID,
            assetID: assetID,
            siteID: siteID,
            locationNodeID: nil,
            predecessorEventID: nil,
            source: .migratedBaseline,
            physicalEpisodeID: PhysicalPlacementEpisodeIDV1(rawValue: id(412)),
            continuity: .samePhysicalInstallation,
            pathSnapshot: locationPath,
            mutationID: mutation(413),
            occurredAt: fixedDate
        )
        let location = try CompletedLocationCompositionSnapshotV1.build(
            workspaceID: workspaceID,
            assetID: assetID,
            currentLocationPath: locationPath,
            currentPlacementByAssetID: [assetID: placement],
            activeCompositionEdges: [],
            frozenAtRevision: 1
        )
        let payload = try CompletedActivitySnapshotPayloadV2(
            activity: activity,
            assetID: assetID,
            locationComposition: location
        )
        return CompletedReportFixture(
            snapshot: try CompletedActivitySnapshotV2.freezeOriginal(payload),
            manifest: manifest,
            layout: layout,
            export: export
        )
    }
}

@MainActor
final class V9_54ActivityContractFamiliesTests: XCTestCase {
    func testV23P03C47G01SharedEnvelopeInstallationAndPunchAcceptAsThreeIsolatedReceipts() async throws {
        XCTAssertEqual(
            ActivityKindV2.knownCases.map(\.rawValue),
            [
                "INSPECTION", "SURVEY", "PREVENTIVE_MAINTENANCE", "REPAIR",
                "OPERATIONAL_RECHECK", "INSTALLATION", "PUNCH_REVIEW"
            ]
        )
        let fallback = try NoPlanFallbackV1(
            limitation: "Manual subject selection; no plan or scan authority was supplied."
        )
        let shippingPackage = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let packageRegistry = try InspectionPackageRegistryV2(packages: [shippingPackage])
        let installationWorkflowRelease = try C47ActivityTestSupport.installationRelease(
            registry: packageRegistry, workspaceID: C47ActivityTestSupport.workspace()
        )
        let punchWorkflowRelease = try C47ActivityTestSupport.punchRelease(
            registry: packageRegistry, workspaceID: C47ActivityTestSupport.workspace()
        )
        let shared = try SharedActivityEnvelopeReceiptV1(
            sharedContractSHA256: C47ActivityTestSupport.digest("a")
        )
        let installation = try InstallationActivityContractReceiptV1(
            sharedContractSHA256: shared.sharedContractSHA256,
            installationContractSHA256: installationWorkflowRelease.releaseSHA256,
            noPlanFallbackSHA256: fallback.fallbackSHA256
        )
        let punch = try PunchActivityContractReceiptV1(
            sharedContractSHA256: shared.sharedContractSHA256,
            punchContractSHA256: punchWorkflowRelease.releaseSHA256,
            noPlanFallbackSHA256: fallback.fallbackSHA256
        )
        XCTAssertEqual(shared.persistence, .nonpersistent)
        XCTAssertEqual(installation.persistence, .nonpersistent)
        XCTAssertEqual(punch.persistence, .nonpersistent)
        XCTAssertNotEqual(shared.receiptSHA256, installation.receiptSHA256)
        XCTAssertNotEqual(shared.receiptSHA256, punch.receiptSHA256)
        XCTAssertNotEqual(installation.receiptSHA256, punch.receiptSHA256)

        let changedInstallation = try InstallationActivityContractReceiptV1(
            sharedContractSHA256: shared.sharedContractSHA256,
            installationContractSHA256: C47ActivityTestSupport.digest("d"),
            noPlanFallbackSHA256: fallback.fallbackSHA256
        )
        XCTAssertNotEqual(changedInstallation.receiptSHA256, installation.receiptSHA256)
        XCTAssertEqual(punch.sharedContractSHA256, shared.sharedContractSHA256)
        let changedPunch = try PunchActivityContractReceiptV1(
            sharedContractSHA256: shared.sharedContractSHA256,
            punchContractSHA256: C47ActivityTestSupport.digest("e"),
            noPlanFallbackSHA256: fallback.fallbackSHA256
        )
        XCTAssertNotEqual(changedPunch.receiptSHA256, punch.receiptSHA256)
        XCTAssertEqual(installation.sharedContractSHA256, shared.sharedContractSHA256)

        let installationEnvelope = try C47ActivityTestSupport.envelope(kind: .installation)
        let punchEnvelope = try C47ActivityTestSupport.envelope(
            kind: .punchReview,
            mutationSlot: 11
        )
        XCTAssertEqual(installationEnvelope.kind, .installation)
        XCTAssertEqual(punchEnvelope.kind, .punchReview)
        XCTAssertNotEqual(installationEnvelope.envelopeSHA256, punchEnvelope.envelopeSHA256)

        let installationCloseout = try InstallationCloseoutV1(
            completion: .completedAsRecorded,
            asBuiltSnapshotSHA256: C47ActivityTestSupport.digest("5")
        )
        let punchCloseout = try PunchReviewCloseoutV1(
            completion: .completedNoPunchItemsRecordedInScope,
            basisSHA256: C47ActivityTestSupport.digest("7"),
            scope: [
                try PunchItemProjectionV1(
                    scopeItemID: "standalone.scope",
                    disposition: .reviewedNoItemRecorded
                )
            ],
            scopeAndTimeLimitation: "No item was recorded only in the reviewed scope and time."
        )
        XCTAssertEqual(installationCloseout.completion, .completedAsRecorded)
        XCTAssertEqual(punchCloseout.completion, .completedNoPunchItemsRecordedInScope)

        let support = FileManager.default.temporaryDirectory.appendingPathComponent(
            "c47-coordinator-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: support) }
        let session = try StoreGenerationFactory(applicationSupportURL: support)
            .openOrBootstrapCurrent()
        let packageAuthority = try C47ActivityTestSupport.packageAuthority(
            workspaceID: session.workspaceID,
            slot: 500
        )
        session.modelContext.insert(try PromotedPackageReleaseRow(packageAuthority.promoted))
        session.modelContext.insert(try ActivePackageRegistryPointerRow(packageAuthority.pointer))
        try session.modelContext.save()
        XCTAssertEqual(
            try session.modelContext.fetch(FetchDescriptor<PromotedPackageReleaseRow>()).count,
            1
        )
        XCTAssertEqual(
            try session.modelContext.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>()).count,
            1
        )
        let writerInstanceID = C47ActivityTestSupport.id(130)
        let journal = try MutationJournalStoreV1(
            modelContext: session.modelContext,
            identity: session.workspaceIdentity,
            generationID: session.generationID
        )
        let writer = try WorkspaceWriterV1(
            identity: session.workspaceIdentity,
            generationID: session.generationID,
            initialRevision: journal.currentRevision(writerInstanceID: writerInstanceID),
            clock: C47ActivityClock(value: C47ActivityTestSupport.fixedDate),
            idSource: C47ActivityIDSource(value: writerInstanceID),
            fileAuthority: C47ActivityFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext),
            journalStore: journal
        )
        let conformanceAuthority = try ActivityContractConformanceAuthorityV2(
            sharedReceipt: shared,
            installationContractSHA256: installation.installationContractSHA256,
            punchContractSHA256: punch.punchContractSHA256,
            noPlanFallback: fallback
        )
        let coordinator = ActivityContractCoordinatorV2(
            query: ActivityContractRowQueryV2(
                modelContext: session.modelContext,
                workspaceID: session.workspaceID,
                writer: writer
            ),
            writer: writer,
            conformanceAuthority: conformanceAuthority
        )
        func rootMutation(
            kind: ActivityKindV2,
            activitySlot: Int,
            mutationSlot: Int,
            includeFamilyPayload: Bool = false
        ) throws -> ActivityContractMutationV2 {
            let activityID = C47ActivityTestSupport.id(activitySlot)
            let subjectID = C47ActivityTestSupport.id(3)
            let mutationID = try C47ActivityTestSupport.mutation(mutationSlot)
            let installationBasis = includeFamilyPayload && kind == .installation
                ? try InstallationBasisSnapshotV1(
                    basisID: C47ActivityTestSupport.id(activitySlot + 20),
                    workspaceID: session.workspaceID,
                    activityID: activityID,
                    subjectID: subjectID,
                    workflowReleaseReference: ActivityWorkflowReleaseReferenceV2(
                        installation: installationWorkflowRelease,
                        package: shippingPackage
                    ),
                    source: .noPlan(fallback),
                    capturedAt: C47ActivityTestSupport.fixedDate,
                    revision: 1,
                    mutationID: mutationID
                )
                : nil
            let punchBasis = includeFamilyPayload && kind == .punchReview
                ? try PunchReviewBasisSnapshotV1(
                    basisID: C47ActivityTestSupport.id(activitySlot + 20),
                    workspaceID: session.workspaceID,
                    activityID: activityID,
                    subjectID: subjectID,
                    workflowReleaseReference: ActivityWorkflowReleaseReferenceV2(
                        punchReview: punchWorkflowRelease,
                        package: shippingPackage
                    ),
                    source: .noPlan(fallback),
                    scopeLimitation: "Standalone recorded punch scope; no installation truth is inferred.",
                    capturedAt: C47ActivityTestSupport.fixedDate,
                    revision: 1,
                    mutationID: mutationID
                )
                : nil
            let currentBasisReference: ActivityBasisHeadReferenceV2?
            if let installationBasis {
                currentBasisReference = .installation(
                    try InstallationBasisReferenceV1(installationBasis)
                )
            } else if let punchBasis {
                currentBasisReference = .punchReview(
                    try PunchReviewBasisReferenceV1(punchBasis)
                )
            } else {
                currentBasisReference = nil
            }
            let envelope = try ActivitySessionEnvelopeV2(
                activityID: activityID,
                workspaceID: session.workspaceID,
                kind: kind,
                state: .draft,
                reviewState: .notRequested,
                subjectID: subjectID,
                title: "Recorded field activity",
                readiness: C47ActivityTestSupport.readiness(),
                currentBasisReference: currentBasisReference,
                revision: 1,
                mutationID: mutationID
            )
            let current = try writer.currentRevision()
            return try ActivityContractMutationV2(
                workspaceID: session.workspaceID,
                expectedRevision: WorkspaceExpectedRevisionV1(
                    workspaceID: current.workspaceID,
                    generationID: current.generationID,
                    writerInstanceID: current.writerInstanceID,
                    workspaceRevision: current.revision,
                    entityRevisions: current.entityRevisions + [
                        WorkspaceEntityRevisionV1(
                            identity: try WorkspaceEntityIdentityV1(
                                kind: .activitySessionEnvelope,
                                id: activityID
                            ),
                            revision: 0
                        )
                    ]
                ),
                mutationID: mutationID,
                successorEnvelope: envelope,
                installationBasisSnapshot: installationBasis,
                punchReviewBasisSnapshot: punchBasis
            )
        }
        let sharedMutation = try rootMutation(kind: .installation, activitySlot: 131, mutationSlot: 132)
        // The shared-only family is intentionally represented by a generic
        // draft envelope with no selected basis or family-owned rows. It must
        // remain usable without manufacturing installation or punch truth.
        XCTAssertEqual(sharedMutation.successorEnvelope.state, .draft)
        XCTAssertNil(sharedMutation.successorEnvelope.currentBasisReference)
        XCTAssertNil(sharedMutation.installationBasisSnapshot)
        XCTAssertNil(sharedMutation.punchReviewBasisSnapshot)
        XCTAssertTrue(sharedMutation.installationTaskResults.isEmpty)
        XCTAssertNil(sharedMutation.installationAsBuiltSnapshot)
        XCTAssertThrowsError(try ActivityContractAcceptanceRequestV2(
            family: .shared,
            mutation: sharedMutation,
            sharedReceipt: shared,
            independentFamilyContractSHA256: installation.installationContractSHA256,
            noPlanFallback: fallback
        )) { error in
            XCTAssertEqual(error as? ActivityContractCoordinatorFailureV2, .invalidFamily)
        }
        XCTAssertTrue(
            try session.modelContext.fetch(FetchDescriptor<ActivitySessionEnvelopeRow>()).isEmpty
        )
        let sharedResult = try await coordinator.accept(ActivityContractAcceptanceRequestV2(
            family: .shared,
            mutation: sharedMutation,
            sharedReceipt: shared
        ))
        let installationMutation = try rootMutation(
            kind: .installation,
            activitySlot: 133,
            mutationSlot: 134,
            includeFamilyPayload: true
        )
        let divergentFallback = try NoPlanFallbackV1(
            limitation: "A caller-supplied fallback must not replace the released authority."
        )
        let divergentDigestRequest = try ActivityContractAcceptanceRequestV2(
            family: .installation,
            mutation: installationMutation,
            sharedReceipt: shared,
            independentFamilyContractSHA256: C47ActivityTestSupport.digest("f"),
            noPlanFallback: fallback
        )
        do {
            _ = try await coordinator.accept(divergentDigestRequest)
            XCTFail("A caller-supplied family digest must not bypass the authority binding")
        } catch {
            XCTAssertEqual(error as? ActivityContractCoordinatorFailureV2, .invalidFamily)
        }
        let divergentFallbackRequest = try ActivityContractAcceptanceRequestV2(
            family: .installation,
            mutation: installationMutation,
            sharedReceipt: shared,
            independentFamilyContractSHA256: installation.installationContractSHA256,
            noPlanFallback: divergentFallback
        )
        do {
            _ = try await coordinator.accept(divergentFallbackRequest)
            XCTFail("A caller-supplied fallback must not bypass the authority binding")
        } catch {
            XCTAssertEqual(error as? ActivityContractCoordinatorFailureV2, .invalidFamily)
        }
        let installationResult = try await coordinator.accept(ActivityContractAcceptanceRequestV2(
            family: .installation,
            mutation: installationMutation,
            sharedReceipt: shared,
            independentFamilyContractSHA256: installation.installationContractSHA256,
            noPlanFallback: fallback
        ))
        let divergentSharedReceipt = try SharedActivityEnvelopeReceiptV1(
            sharedContractSHA256: C47ActivityTestSupport.digest("b")
        )
        let divergentReplayRequest = try ActivityContractAcceptanceRequestV2(
            family: .installation,
            mutation: installationMutation,
            sharedReceipt: divergentSharedReceipt,
            independentFamilyContractSHA256: installation.installationContractSHA256,
            noPlanFallback: fallback
        )
        do {
            _ = try await coordinator.accept(divergentReplayRequest)
            XCTFail("The same MutationID must not replay with a divergent nonpersistent receipt")
        } catch {
            XCTAssertEqual(error as? ActivityContractCoordinatorFailureV2, .invalidFamily)
        }
        XCTAssertThrowsError(try ActivityContractAcceptanceRequestV2(
            family: .punch,
            mutation: installationMutation,
            sharedReceipt: shared,
            independentFamilyContractSHA256: punch.punchContractSHA256,
            noPlanFallback: fallback
        )) { error in
            XCTAssertEqual(error as? ActivityContractCoordinatorFailureV2, .invalidFamily)
        }
        let punchMutation = try rootMutation(
            kind: .punchReview,
            activitySlot: 135,
            mutationSlot: 136,
            includeFamilyPayload: true
        )
        XCTAssertThrowsError(try ActivityContractAcceptanceRequestV2(
            family: .installation,
            mutation: punchMutation,
            sharedReceipt: shared,
            independentFamilyContractSHA256: installation.installationContractSHA256,
            noPlanFallback: fallback
        )) { error in
            XCTAssertEqual(error as? ActivityContractCoordinatorFailureV2, .invalidFamily)
        }
        XCTAssertEqual(
            try session.modelContext.fetch(FetchDescriptor<ActivitySessionEnvelopeRow>()).count,
            2
        )
        let punchResult = try await coordinator.accept(ActivityContractAcceptanceRequestV2(
            family: .punch,
            mutation: punchMutation,
            sharedReceipt: shared,
            independentFamilyContractSHA256: punch.punchContractSHA256,
            noPlanFallback: fallback
        ))
        XCTAssertNotEqual(sharedMutation.successorEnvelope.envelopeSHA256,
                          installationMutation.successorEnvelope.envelopeSHA256)
        XCTAssertNotEqual(installationMutation.successorEnvelope.envelopeSHA256,
                          punchMutation.successorEnvelope.envelopeSHA256)
        XCTAssertEqual(sharedResult.receipt, .shared(shared))
        XCTAssertEqual(installationResult.receipt, .installation(installation))
        XCTAssertEqual(punchResult.receipt, .punch(punch))
        XCTAssertEqual(
            Set([sharedResult.durableReceipt.mutationID,
                 installationResult.durableReceipt.mutationID,
                 punchResult.durableReceipt.mutationID]).count,
            3
        )
        let interleavedReceiptSequences = [
            sharedResult.durableReceipt.identity.localSequence,
            installationResult.durableReceipt.identity.localSequence,
            punchResult.durableReceipt.identity.localSequence,
        ]
        XCTAssertEqual(interleavedReceiptSequences, interleavedReceiptSequences.sorted())
        XCTAssertTrue(zip(interleavedReceiptSequences, interleavedReceiptSequences.dropFirst()).allSatisfy {
            prior, next in prior < next
        })
        XCTAssertEqual(
            try session.modelContext.fetch(FetchDescriptor<ActivitySessionEnvelopeRow>()).count,
            3
        )
        try journal.validateAll()
    }

    func testV23P03C47A01NoPlanFallbackReadinessDeferredUnableAndCancellationRemainExact() throws {
        let fallback = try NoPlanFallbackV1(
            limitation: "Plan truth absent; manual lookup and recorded scope remain required."
        )
        XCTAssertTrue(fallback.manualSubjectSelectionRequired)
        XCTAssertFalse(fallback.planRequired)
        XCTAssertFalse(fallback.scanRequired)

        let blocked = try ActivityReadinessFacetV1(
            facetID: "material",
            kind: .material,
            disposition: .blocked,
            reason: "Recorded material is unavailable."
        )
        let deferred = try ActivityReadinessFacetV1(
            facetID: "weather",
            kind: .weather,
            disposition: .deferred,
            reason: "Recorded weather prevents field work."
        )
        XCTAssertEqual(blocked.disposition, .blocked)
        XCTAssertEqual(deferred.disposition, .deferred)

        let installationReadinessPolicy = try InstallationReadinessPolicyV1(
            requiredFacets: [.material]
        )
        XCTAssertThrowsError(try ActivitySessionEnvelopeV2(
            activityID: C47ActivityTestSupport.id(18),
            workspaceID: C47ActivityTestSupport.workspace(),
            kind: .installation,
            state: .ready,
            reviewState: .notRequested,
            subjectID: C47ActivityTestSupport.id(19),
            title: "Blocked installation cannot become ready",
            readiness: [blocked],
            readinessPolicy: .installation(installationReadinessPolicy),
            revision: 1,
            mutationID: C47ActivityTestSupport.mutation(18)
        )) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .invalidTransition)
        }

        let deferredTask = try InstallationTaskResultV1(
            resultID: C47ActivityTestSupport.id(20),
            workspaceID: C47ActivityTestSupport.workspace(),
            activityID: C47ActivityTestSupport.id(2),
            taskID: "install.task",
            outcome: .deferred,
            deferredReason: .materialUnavailable,
            note: "Material unavailable at the recorded attempt.",
            revision: 1,
            mutationID: C47ActivityTestSupport.mutation(20)
        )
        let unableTask = try InstallationTaskResultV1(
            resultID: C47ActivityTestSupport.id(21),
            workspaceID: C47ActivityTestSupport.workspace(),
            activityID: C47ActivityTestSupport.id(2),
            taskID: "install.unable",
            outcome: .unable,
            unableReason: .unsafeRecordedCondition,
            note: "Only the observed inability is recorded.",
            revision: 1,
            mutationID: C47ActivityTestSupport.mutation(21)
        )
        XCTAssertEqual(deferredTask.deferredReason, .materialUnavailable)
        XCTAssertEqual(unableTask.unableReason, .unsafeRecordedCondition)

        let completedTask = try InstallationTaskResultV1(
            resultID: C47ActivityTestSupport.id(22),
            workspaceID: deferredTask.workspaceID,
            activityID: deferredTask.activityID,
            taskID: deferredTask.taskID,
            outcome: .completed,
            evidenceReferences: [try C47ActivityTestSupport.contentReference(
                workspaceID: deferredTask.workspaceID,
                slot: 221,
                digestCharacter: "1"
            )],
            revision: 2,
            mutationID: C47ActivityTestSupport.mutation(22),
            predecessorResultID: deferredTask.resultID,
            predecessorResultSHA256: deferredTask.resultSHA256
        )
        try completedTask.validateSuccessor(of: deferredTask)
        let taskHeads = try InstallationTaskCurrentHeadContextV1(
            workspaceID: deferredTask.workspaceID,
            activityID: deferredTask.activityID,
            currentHeads: [deferredTask]
        )
        try taskHeads.validate(successors: [completedTask])
        XCTAssertEqual(
            try InstallationTaskResultLineageV1.validateAndCurrentHeads([
                deferredTask, completedTask,
            ])[deferredTask.taskID],
            completedTask
        )

        XCTAssertTrue(ActivityStateMachineV2.permits(from: .draft, to: .cancelled))
        XCTAssertTrue(ActivityStateMachineV2.permits(from: .ready, to: .deferred))
        XCTAssertTrue(ActivityStateMachineV2.permits(from: .inProgress, to: .unableToComplete))
        XCTAssertFalse(ActivityStateMachineV2.permits(from: .cancelled, to: .finalized))

        let shipping = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let registry = try InspectionPackageRegistryV2(packages: [shipping])
        let punchRelease = try C47ActivityTestSupport.punchRelease(
            registry: registry,
            workspaceID: C47ActivityTestSupport.workspace()
        )
        let punchBasis = try PunchReviewBasisSnapshotV1(
            basisID: C47ActivityTestSupport.id(30),
            workspaceID: C47ActivityTestSupport.workspace(),
            activityID: C47ActivityTestSupport.id(31),
            subjectID: C47ActivityTestSupport.id(32),
            workflowReleaseReference: ActivityWorkflowReleaseReferenceV2(
                punchReview: punchRelease,
                package: shipping
            ),
            source: .noPlan(fallback),
            scopeLimitation: "Standalone FJ04 scope; no installation activity, package, route, or report.",
            capturedAt: C47ActivityTestSupport.fixedDate,
            revision: 1,
            mutationID: C47ActivityTestSupport.mutation(30)
        )
        if case let .noPlan(value) = punchBasis.source {
            XCTAssertEqual(value, fallback)
        } else {
            XCTFail("Standalone punch must retain the explicit no-plan fallback")
        }

        XCTAssertEqual(punchRelease.bundledRelease, .punchReviewV1)
        XCTAssertEqual(punchBasis.workflowReleaseReference.targetReleaseSHA256,
                       punchRelease.releaseSHA256)
    }

    func testV23P03C47H01CrossFamilyClaimsInvalidTransitionsAndStaleInputsFailClosed() throws {
        let unknownBytes = Data("\"FUTURE_ACTIVITY_KIND\"".utf8)
        let unknown = try JSONDecoder().decode(ActivityKindV2.self, from: unknownBytes)
        XCTAssertEqual(unknown, .unknown("FUTURE_ACTIVITY_KIND"))
        XCTAssertEqual(try JSONEncoder().encode(unknown), unknownBytes)
        XCTAssertEqual(
            ActivityKindV1CompatibilityAdapterV2.disposition(unknown),
            .unknownReadExportOnly
        )
        XCTAssertThrowsError(try unknown.requireKnownForMutation()) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .unknownKindMutation)
        }

        // Unknown kinds are retained as opaque canonical rows for read and
        // export, but the current C47 row boundary and backup restore path
        // must not admit them as writable family data.
        let unknownSeed = try C47ActivityTestSupport.envelope(
            kind: .installation,
            activityID: C47ActivityTestSupport.id(246),
            mutationSlot: 247
        )
        var unknownObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: unknownSeed.canonicalData()) as? [String: Any]
        )
        unknownObject["kind"] = "FUTURE_ACTIVITY_KIND"
        unknownObject.removeValue(forKey: "envelopeSHA256")
        let unknownBasisBytes = try JSONSerialization.data(
            withJSONObject: unknownObject,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        unknownObject["envelopeSHA256"] = KernelCanonicalHashV1.sha256(unknownBasisBytes)
        let unknownEnvelopeBytes = try JSONSerialization.data(
            withJSONObject: unknownObject,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let unknownDecoder = JSONDecoder()
        unknownDecoder.dateDecodingStrategy = .millisecondsSince1970
        let unknownEnvelope = try unknownDecoder.decode(
            ActivitySessionEnvelopeV2.self,
            from: unknownEnvelopeBytes
        )
        XCTAssertEqual(unknownEnvelope.kind, unknown)
        XCTAssertEqual(try unknownEnvelope.canonicalData(), unknownEnvelopeBytes)
        try unknownEnvelope.validateForRead()
        let unknownSearchProjection = try ActivityContractSearchProjectionV2(
            envelope: unknownEnvelope
        )
        XCTAssertEqual(unknownSearchProjection.kind, unknown)
        let unknownReportProjection = try ActivityContractReportProjectionV2(
            envelope: unknownEnvelope
        )
        try C47ActivityContractConformance_FieldEvidenceApp_Infrastructure_Reporting_ReportProjectionRegistryV1_swift
            .validate(unknownReportProjection)
        XCTAssertFalse(
            C47ActivityContractPersistenceBoundaryV2.acceptsCanonicalRow(
                kind: unknownEnvelope.kind
            )
        )
        XCTAssertThrowsError(try ActivitySessionEnvelopeRow(unknownEnvelope)) { error in
            XCTAssertEqual(error as? ActivityContractPersistenceFailureV2, .corruptRow)
        }
        let knownBackupRecord = try V36BackupActivityContractRecordV2(unknownSeed)
        var unknownBackupObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: WorkspaceMutationCanonicalV1.data(knownBackupRecord)
            ) as? [String: Any]
        )
        unknownBackupObject["kind"] = "FUTURE_ACTIVITY_KIND"
        let unknownBackupBytes = try JSONSerialization.data(
            withJSONObject: unknownBackupObject,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        XCTAssertThrowsError(try JSONDecoder().decode(
            V36BackupActivityContractRecordV2.self,
            from: unknownBackupBytes
        ))

        for (index, legacy) in ActivityKindV1.allCases.enumerated() {
            let kind = ActivityKindV1CompatibilityAdapterV2.v2(legacy)
            let activityID = C47ActivityTestSupport.id(150 + index)
            let envelope = try C47ActivityTestSupport.envelope(
                kind: kind,
                mutationSlot: 160 + index,
                activityID: activityID
            )
            let expected = try WorkspaceExpectedRevisionV1(
                workspaceID: envelope.workspaceID,
                generationID: C47ActivityTestSupport.id(170),
                writerInstanceID: C47ActivityTestSupport.id(171),
                workspaceRevision: 0,
                entityRevisions: [
                    WorkspaceEntityRevisionV1(
                        identity: try WorkspaceEntityIdentityV1(
                            kind: .activitySessionEnvelope,
                            id: activityID
                        ),
                        revision: 0
                    )
                ]
            )
            XCTAssertThrowsError(try ActivityContractMutationV2(
                workspaceID: envelope.workspaceID,
                expectedRevision: expected,
                mutationID: envelope.mutationID,
                successorEnvelope: envelope
            )) { error in
                XCTAssertEqual(error as? ActivityContractFailureV2, .unknownKindMutation)
            }
            XCTAssertEqual(ActivityKindV1CompatibilityAdapterV2.disposition(kind), .exactV1)
            XCTAssertEqual(ActivityKindV1CompatibilityAdapterV2.v1(kind), legacy)
            let route = try ActivityRouteV2(
                workspaceID: envelope.workspaceID,
                activityID: envelope.activityID,
                kind: kind,
                routeID: "legacy.read.\(index)"
            )
            let routeBytes = try ActivityRouteCanonicalRegistryV2.encode(route)
            XCTAssertEqual(try ActivityRouteCanonicalRegistryV2.decode(routeBytes), route)
            XCTAssertEqual(try ActivityContractSearchProjectionV2(envelope: envelope).kind, kind)
            try C47ActivityContractConformance_FieldEvidenceApp_Infrastructure_Reporting_ReportProjectionRegistryV1_swift
                .validate(ActivityContractReportProjectionV2(envelope: envelope))
        }

        for from in ActivityStateV2.allCases {
            let table = ActivityStateMachineV2.exhaustiveTable[from] ?? []
            for to in ActivityStateV2.allCases {
                XCTAssertEqual(table.contains(to), ActivityStateMachineV2.permits(from: from, to: to))
            }
        }
        XCTAssertFalse(ActivityStateMachineV2.permits(from: .draft, to: .finalized))
        XCTAssertTrue(ActivityStateMachineV2.permits(from: .finalized, to: .superseded))
        XCTAssertTrue(
            ActivityStateV2.allCases.filter { $0 != .superseded }.allSatisfy {
                !ActivityStateMachineV2.permits(from: .finalized, to: $0)
            }
        )

        let startRule = try PackageLifecycleOperationRuleV1(
            operation: .start,
            active: .readWrite,
            deprecated: .readWrite,
            withdrawn: .reject,
            quarantined: .reject,
            superseded: .reject
        )
        let exportRule = try PackageLifecycleOperationRuleV1(
            operation: .export,
            active: .readWrite,
            deprecated: .readOnly,
            withdrawn: .readOnly,
            quarantined: .reject,
            superseded: .readOnly
        )
        XCTAssertEqual(startRule.admission(for: .withdrawn), .reject)
        XCTAssertEqual(exportRule.admission(for: .withdrawn), .readOnly)

        // A retired workflow release remains valid for historic read/export,
        // but it can never be used to start a new activity.
        let shipping = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let retiredSupport = FileManager.default.temporaryDirectory.appendingPathComponent(
            "c47-retired-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: retiredSupport) }
        let retiredSession = try StoreGenerationFactory(
            applicationSupportURL: retiredSupport
        ).openOrBootstrapCurrent()
        let retiredAuthority = try C47ActivityTestSupport.packageAuthority(
            workspaceID: retiredSession.workspaceID,
            slot: 560
        )
        retiredSession.modelContext.insert(
            try PromotedPackageReleaseRow(retiredAuthority.promoted)
        )
        retiredSession.modelContext.insert(
            try ActivePackageRegistryPointerRow(retiredAuthority.pointer)
        )
        let withdrawn = try PackageLifecycleDispositionV1(
            dispositionID: C47ActivityTestSupport.id(563),
            workspaceID: retiredSession.workspaceID,
            release: retiredAuthority.packageRelease,
            state: .withdrawn,
            reason: "C47 retired historic release",
            recordedAt: C47ActivityTestSupport.fixedDate,
            mutationID: try C47ActivityTestSupport.mutation(564)
        )
        retiredSession.modelContext.insert(
            try PackageLifecycleDispositionRow(
                withdrawn,
                release: retiredAuthority.packageRelease
            )
        )
        try retiredSession.modelContext.save()
        let retiredRegistry = try InspectionPackageRegistryV2(packages: [shipping])
        let retiredRelease = try C47ActivityTestSupport.installationRelease(
            registry: retiredRegistry,
            workspaceID: retiredSession.workspaceID
        )
        let punchRelease = try C47ActivityTestSupport.punchRelease(
            registry: retiredRegistry,
            workspaceID: C47ActivityTestSupport.workspace()
        )
        let historicReference = try ActivityWorkflowReleaseReferenceV2(
            installation: retiredRelease,
            package: shipping
        )
        let historicWorkflow = try PackageEvolutionLifecycleAdapterV1
            .resolveActivityWorkflowRelease(
                reference: historicReference,
                kind: .installation,
                forStart: false,
                modelContext: retiredSession.modelContext
            )
        guard case let .installation(_, historicRelease, historicPackage, historicAvailability) = historicWorkflow else {
            XCTFail("The promoted installation bytes must resolve as an installation family")
            return
        }
        let promotedHistoricPackage = try InspectionPackageCanonicalCodecV2.decode(
            retiredAuthority.promoted.packageRelease.canonicalPackageBytes
        )
        XCTAssertEqual(historicPackage, promotedHistoricPackage)
        XCTAssertEqual(historicPackage, shipping)
        XCTAssertEqual(historicRelease.bundledRelease, .installationV1)
        XCTAssertEqual(historicAvailability.disposition, .historicReadExportOnly)
        try historicWorkflow.validate(expectedReference: historicReference, forStart: false)
        XCTAssertThrowsError(try PackageEvolutionLifecycleAdapterV1
            .resolveActivityWorkflowRelease(
                reference: historicReference,
                kind: .installation,
                forStart: true,
                modelContext: retiredSession.modelContext
            )) { error in
            XCTAssertEqual(error as? InspectionPackageFailureV2, .incompatiblePackage)
        }
        let retiredRegistryForLocalBasis = try InspectionPackageRegistryV2(packages: [shipping])
        let localRetiredRelease = try C47ActivityTestSupport.installationRelease(
            registry: retiredRegistryForLocalBasis,
            workspaceID: C47ActivityTestSupport.workspace()
        )
        let retiredReference = try ActivityWorkflowReleaseReferenceV2(
            installation: localRetiredRelease,
            package: shipping
        )

        // Basis lineage is append-only. Both optional-plan and externally
        // supplied references remain accepted without turning the no-plan
        // fallback into a requirement on the selected basis source.
        let installationWorkflowReference = retiredReference
        let punchBasis = try PunchReviewBasisSnapshotV1(
            basisID: C47ActivityTestSupport.id(180),
            workspaceID: C47ActivityTestSupport.workspace(),
            activityID: C47ActivityTestSupport.id(181),
            subjectID: C47ActivityTestSupport.id(3),
            workflowReleaseReference: try ActivityWorkflowReleaseReferenceV2(
                punchReview: punchRelease,
                package: shipping
            ),
            source: .noPlan(fallback),
            scopeLimitation: "Standalone punch scope remains independent from installation truth.",
            capturedAt: C47ActivityTestSupport.fixedDate,
            revision: 1,
            mutationID: try C47ActivityTestSupport.mutation(179)
        )
        let optionalPlan = try ActivityExternalReferenceV1(
            referenceID: "plan.optional.c47",
            revision: 1,
            sha256: C47ActivityTestSupport.digest("a")
        )
        let externalCapture = try ActivityExternalReferenceV1(
            referenceID: "capture.external.c47",
            revision: 1,
            sha256: C47ActivityTestSupport.digest("b")
        )
        // Decoding is a validation boundary for every nested basis source;
        // changing only the nested payload must never produce a usable basis.
        func tamperedBasisSource(
            _ source: ActivityBasisSourceV1,
            key: String,
            edit: (inout [String: Any]) -> Void
        ) throws -> Data {
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(
                    with: WorkspaceMutationCanonicalV1.data(source)
                ) as? [String: Any]
            )
            var nested = try XCTUnwrap(object[key] as? [String: Any])
            edit(&nested)
            object[key] = nested
            return try JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
        }
        let malformedNoPlan = try tamperedBasisSource(
            .noPlan(fallback),
            key: "noPlan"
        ) { nested in
            nested["planRequired"] = true
        }
        XCTAssertThrowsError(try JSONDecoder().decode(
            ActivityBasisSourceV1.self,
            from: malformedNoPlan
        ))
        let malformedOptionalPlan = try tamperedBasisSource(
            .optionalPlan(optionalPlan),
            key: "optionalPlan"
        ) { nested in
            nested["sha256"] = "not-a-sha256"
        }
        XCTAssertThrowsError(try JSONDecoder().decode(
            ActivityBasisSourceV1.self,
            from: malformedOptionalPlan
        ))
        let malformedExternalLocal = try tamperedBasisSource(
            .externalLocal(externalCapture),
            key: "externalLocal"
        ) { nested in
            nested["revision"] = 0
        }
        XCTAssertThrowsError(try JSONDecoder().decode(
            ActivityBasisSourceV1.self,
            from: malformedExternalLocal
        ))
        let basisActivityID = C47ActivityTestSupport.id(182)
        let basisSubjectID = C47ActivityTestSupport.id(3)
        let basisOneMutationID = try C47ActivityTestSupport.mutation(183)
        let basisOne = try InstallationBasisSnapshotV1(
            basisID: C47ActivityTestSupport.id(184),
            workspaceID: C47ActivityTestSupport.workspace(),
            activityID: basisActivityID,
            subjectID: basisSubjectID,
            workflowReleaseReference: installationWorkflowReference,
            source: .optionalPlan(optionalPlan),
            capturedAt: C47ActivityTestSupport.fixedDate,
            revision: 1,
            mutationID: basisOneMutationID
        )
        let basisTwoMutationID = try C47ActivityTestSupport.mutation(185)
        let basisTwo = try InstallationBasisSnapshotV1(
            basisID: C47ActivityTestSupport.id(186),
            workspaceID: basisOne.workspaceID,
            activityID: basisActivityID,
            subjectID: basisSubjectID,
            workflowReleaseReference: installationWorkflowReference,
            source: .externalLocal(externalCapture),
            capturedAt: C47ActivityTestSupport.fixedDate.addingTimeInterval(1),
            revision: 2,
            mutationID: basisTwoMutationID,
            predecessorBasisID: basisOne.basisID,
            predecessorBasisSHA256: basisOne.basisSHA256
        )
        try basisTwo.validateSuccessor(of: basisOne)
        if case let .optionalPlan(value) = basisOne.source {
            XCTAssertEqual(value, optionalPlan)
        } else {
            XCTFail("The first basis must retain its optional-plan reference")
        }
        if case let .externalLocal(value) = basisTwo.source {
            XCTAssertEqual(value, externalCapture)
        } else {
            XCTFail("The successor basis must retain its external reference")
        }
        let basisVariation = try ActivityVariationV1(
            variationID: C47ActivityTestSupport.id(187),
            workspaceID: basisOne.workspaceID,
            revision: 1,
            kind: .basisCorrected,
            predecessorBasisSHA256: basisOne.basisSHA256,
            successorBasisSHA256: basisTwo.basisSHA256,
            reason: "Recorded basis lineage changed without rewriting the predecessor.",
            actor: C47ActivityTestSupport.actor(slot: 188),
            occurredAt: C47ActivityTestSupport.fixedDate.addingTimeInterval(1),
            mutationID: basisTwoMutationID
        )
        let basisOneEnvelope = try ActivitySessionEnvelopeV2(
            activityID: basisActivityID,
            workspaceID: basisOne.workspaceID,
            kind: .installation,
            state: .draft,
            reviewState: .notRequested,
            subjectID: basisSubjectID,
            title: "Multi-basis activity",
            readiness: C47ActivityTestSupport.readiness(),
            currentBasisReference: .installation(
                try InstallationBasisReferenceV1(basisOne)
            ),
            revision: 1,
            mutationID: basisOneMutationID
        )
        let basisTwoEnvelope = try ActivitySessionEnvelopeV2(
            activityID: basisActivityID,
            workspaceID: basisOne.workspaceID,
            kind: .installation,
            state: .preflightRequired,
            reviewState: .notRequested,
            subjectID: basisSubjectID,
            title: basisOneEnvelope.title,
            readiness: basisOneEnvelope.readiness,
            variations: [basisVariation],
            currentBasisReference: .installation(
                try InstallationBasisReferenceV1(basisTwo)
            ),
            revision: 2,
            mutationID: basisTwoMutationID,
            predecessorEnvelopeSHA256: basisOneEnvelope.envelopeSHA256
        )
        try basisTwoEnvelope.validateSuccessor(of: basisOneEnvelope)
        let basisTransition = try ActivityStateTransitionV2(
            transitionID: C47ActivityTestSupport.id(240),
            workspaceID: basisOne.workspaceID,
            activityID: basisActivityID,
            kind: .installation,
            fromState: .draft,
            toState: .preflightRequired,
            actor: C47ActivityTestSupport.actor(slot: 241),
            occurredAt: C47ActivityTestSupport.fixedDate.addingTimeInterval(1),
            revision: 2,
            mutationID: basisTwoMutationID
        )
        let multiBasisMutation = try ActivityContractMutationV2(
            workspaceID: basisOne.workspaceID,
            expectedRevision: try WorkspaceExpectedRevisionV1(
                workspaceID: basisOne.workspaceID,
                generationID: C47ActivityTestSupport.id(189),
                writerInstanceID: C47ActivityTestSupport.id(190),
                workspaceRevision: 1,
                entityRevisions: [WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .activitySessionEnvelope,
                        id: basisActivityID
                    ),
                    revision: 1
                )]
            ),
            mutationID: basisTwoMutationID,
            predecessorEnvelope: basisOneEnvelope,
            successorEnvelope: basisTwoEnvelope,
            transition: basisTransition,
            installationBasisSnapshot: basisTwo
        )
        try multiBasisMutation.validate()

        // The writer-side resolver accepts all three existing authority rows
        // only when their typed references match the mutation's workspace and
        // subject. Exercise the positive path, then each missing/mismatched
        // owner path independently.
        let resolvedContent = try C47ActivityTestSupport.contentReference(
            workspaceID: basisOne.workspaceID,
            slot: 197,
            digestCharacter: "e"
        )
        let resolvedPlan = try C47ActivityTestSupport.planPlacement(
            workspaceID: basisOne.workspaceID,
            subjectID: basisSubjectID,
            slot: 198,
            mutationSlot: 199
        )
        let resolvedPose = try C47ActivityTestSupport.poseEvent(
            workspaceID: basisOne.workspaceID,
            assetID: basisSubjectID,
            eventSlot: 202,
            mutationSlot: 203
        )
        let resolvedTaskMutationID = try C47ActivityTestSupport.mutation(204)
        let resolvedTask = try InstallationTaskResultV1(
            resultID: C47ActivityTestSupport.id(205),
            workspaceID: basisOne.workspaceID,
            activityID: basisActivityID,
            taskID: "identify-subject",
            outcome: .completed,
            note: "The declared identify task resolves its typed content owner.",
            evidenceReferences: [resolvedContent],
            revision: 1,
            mutationID: resolvedTaskMutationID
        )
        let resolvedPlacementTask = try InstallationTaskResultV1(
            resultID: C47ActivityTestSupport.id(700),
            workspaceID: basisOne.workspaceID,
            activityID: basisActivityID,
            taskID: "record-placement",
            outcome: .completed,
            note: "The declared placement task resolves the plan and pose owners.",
            evidenceReferences: [resolvedContent],
            revision: 1,
            mutationID: resolvedTaskMutationID
        )
        let resolvedAsBuiltTask = try InstallationTaskResultV1(
            resultID: C47ActivityTestSupport.id(701),
            workspaceID: basisOne.workspaceID,
            activityID: basisActivityID,
            taskID: "record-as-built",
            outcome: .completed,
            note: "The declared as-built task resolves its typed content owner.",
            evidenceReferences: [resolvedContent],
            revision: 1,
            mutationID: resolvedTaskMutationID
        )
        let resolvedTaskResults = [resolvedTask, resolvedPlacementTask, resolvedAsBuiltTask]
        let resolvedAsBuilt = try InstallationAsBuiltSnapshotV1(
            snapshotID: C47ActivityTestSupport.id(206),
            workspaceID: basisOne.workspaceID,
            activityID: basisActivityID,
            basisReference: try InstallationBasisReferenceV1(basisOne),
            taskResultSHA256s: resolvedTaskResults.map(\.resultSHA256),
            placementReferences: [
                .plan(PlanPlacementReferenceV1(
                    placementID: resolvedPlan.placementID,
                    revision: resolvedPlan.revision,
                    placementSHA256: resolvedPlan.placementSHA256
                )),
                .pose(resolvedPose.reference),
            ],
            completion: .completedAsRecorded,
            revision: 1,
            mutationID: resolvedTaskMutationID
        )
        let resolvedCloseout = try InstallationCloseoutV1(
            completion: .completedAsRecorded,
            asBuiltSnapshotSHA256: resolvedAsBuilt.snapshotSHA256
        )
        let resolvedReport = try C47ActivityTestSupport.completedReportFixture(
            workspaceID: basisOne.workspaceID,
            activityID: basisActivityID,
            assetID: basisSubjectID,
            sourceRevision: 2
        )
        let resolvedCompletedReference = try CompletedActivitySnapshotV2CompatibilityReferenceV1(
            resolvedReport.snapshot,
            activityCloseoutSHA256: resolvedCloseout.closeoutSHA256
        )
        let resolvedPredecessorEnvelope = try ActivitySessionEnvelopeV2(
            activityID: basisActivityID,
            workspaceID: basisOne.workspaceID,
            kind: .installation,
            state: .readyForReview,
            reviewState: .pending,
            subjectID: basisSubjectID,
            title: "Resolved reference activity",
            readiness: C47ActivityTestSupport.readiness(),
            currentBasisReference: .installation(try InstallationBasisReferenceV1(basisOne)),
            startedAt: C47ActivityTestSupport.fixedDate,
            revision: 1,
            mutationID: try C47ActivityTestSupport.mutation(215)
        )
        let resolvedEnvelope = try ActivitySessionEnvelopeV2(
            activityID: basisActivityID,
            workspaceID: basisOne.workspaceID,
            kind: .installation,
            state: .finalized,
            reviewState: .acceptedRecordedFacts,
            subjectID: basisSubjectID,
            title: "Resolved reference activity",
            readiness: C47ActivityTestSupport.readiness(),
            currentBasisReference: .installation(try InstallationBasisReferenceV1(basisOne)),
            installationCloseout: resolvedCloseout,
            completedSnapshotReference: resolvedCompletedReference,
            startedAt: C47ActivityTestSupport.fixedDate,
            finalizedAt: C47ActivityTestSupport.fixedDate.addingTimeInterval(60),
            revision: 2,
            mutationID: resolvedTaskMutationID,
            predecessorEnvelopeSHA256: resolvedPredecessorEnvelope.envelopeSHA256
        )
        let resolvedTransition = try ActivityStateTransitionV2(
            transitionID: C47ActivityTestSupport.id(213),
            workspaceID: basisOne.workspaceID,
            activityID: basisActivityID,
            kind: .installation,
            fromState: .readyForReview,
            toState: .finalized,
            actor: C47ActivityTestSupport.actor(workspaceID: basisOne.workspaceID, slot: 214),
            occurredAt: C47ActivityTestSupport.fixedDate.addingTimeInterval(60),
            revision: 2,
            mutationID: resolvedTaskMutationID
        )
        let resolvedExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: basisOne.workspaceID,
            generationID: C47ActivityTestSupport.id(207),
            writerInstanceID: C47ActivityTestSupport.id(208),
            workspaceRevision: 1,
            entityRevisions: [
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .activitySessionEnvelope,
                        id: basisActivityID
                    ),
                    revision: 1
                ),
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .activityStateTransition,
                        id: resolvedTransition.transitionID
                    ),
                    revision: 0
                ),
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .installationTaskResult,
                        id: resolvedTask.resultID
                    ),
                    revision: 0
                ),
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .installationTaskResult,
                        id: resolvedPlacementTask.resultID
                    ),
                    revision: 0
                ),
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .installationTaskResult,
                        id: resolvedAsBuiltTask.resultID
                    ),
                    revision: 0
                ),
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .installationAsBuiltSnapshot,
                        id: resolvedAsBuilt.snapshotID
                    ),
                    revision: 0
                )
            ]
        )
        let resolvedMutation = try ActivityContractMutationV2(
            workspaceID: basisOne.workspaceID,
            expectedRevision: resolvedExpected,
            mutationID: resolvedTaskMutationID,
            predecessorEnvelope: resolvedPredecessorEnvelope,
            successorEnvelope: resolvedEnvelope,
            transition: resolvedTransition,
            completedSnapshotReference: resolvedCompletedReference,
            installationTaskResults: resolvedTaskResults,
            installationAsBuiltSnapshot: resolvedAsBuilt
        )
        let resolvedReferences = try ActivityInstallationReferenceResolutionContextV2(
            contentReferences: [resolvedContent],
            planPlacements: [resolvedPlan],
            poseEvents: [resolvedPose]
        )
        try resolvedReferences.validate(resolvedMutation)
        XCTAssertEqual(resolvedReferences.contentReferences, Set([resolvedContent]))
        XCTAssertEqual(resolvedReferences.planPlacementsByReference.count, 1)
        XCTAssertEqual(resolvedReferences.poseEventsByReference.count, 1)
        let missingContentReferences = try ActivityInstallationReferenceResolutionContextV2(
            contentReferences: [],
            planPlacements: [resolvedPlan],
            poseEvents: [resolvedPose]
        )
        XCTAssertThrowsError(try missingContentReferences.validate(resolvedMutation)) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .missingReference)
        }
        let missingPlanReferences = try ActivityInstallationReferenceResolutionContextV2(
            contentReferences: [resolvedContent],
            planPlacements: [],
            poseEvents: [resolvedPose]
        )
        XCTAssertThrowsError(try missingPlanReferences.validate(resolvedMutation)) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .missingReference)
        }
        let wrongSubjectPose = try C47ActivityTestSupport.poseEvent(
            workspaceID: basisOne.workspaceID,
            assetID: C47ActivityTestSupport.id(209),
            eventSlot: 210,
            mutationSlot: 211
        )
        let mismatchedPoseReferences = try ActivityInstallationReferenceResolutionContextV2(
            contentReferences: [resolvedContent],
            planPlacements: [resolvedPlan],
            poseEvents: [wrongSubjectPose]
        )
        XCTAssertThrowsError(try mismatchedPoseReferences.validate(resolvedMutation)) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .missingReference)
        }
        let resolvedWorkflowContext = try ActivityWorkflowReleaseResolutionContextV2(
            reference: installationWorkflowReference,
            installation: localRetiredRelease,
            package: shipping,
            availability: try ActivityWorkflowFamilyAvailabilityV2(
                reference: installationWorkflowReference,
                disposition: .availableForStart
            )
        )
        let resolvedSnapshotContext = try CompletedActivitySnapshotResolutionContextV2(
            reference: resolvedCompletedReference,
            snapshot: resolvedReport.snapshot
        )
        let resolvedCloseoutContext = try ActivityCloseoutResolutionContextV2(
            findings: [],
            supportingRecords: [],
            sourceEnvelopes: [],
            installationAsBuiltSnapshot: resolvedAsBuilt
        )
        try resolvedMutation.validateResolved(
            completedSnapshot: resolvedSnapshotContext,
            installationTaskHeads: InstallationTaskCurrentHeadContextV1(
                workspaceID: basisOne.workspaceID,
                activityID: basisActivityID,
                currentHeads: []
            ),
            currentInstallationBasis: basisOne,
            workflowReleaseContext: resolvedWorkflowContext,
            installationReferenceContext: resolvedReferences,
            closeoutContext: resolvedCloseoutContext
        )
        let newerTaskMutationID = try C47ActivityTestSupport.mutation(720)
        let newerIdentifyTask = try InstallationTaskResultV1(
            resultID: C47ActivityTestSupport.id(721),
            workspaceID: basisOne.workspaceID,
            activityID: basisActivityID,
            taskID: "identify-subject",
            outcome: .completed,
            note: "A newer task head invalidates the older closeout as-built proof.",
            evidenceReferences: [resolvedContent],
            revision: 2,
            mutationID: newerTaskMutationID,
            predecessorResultID: resolvedTask.resultID,
            predecessorResultSHA256: resolvedTask.resultSHA256
        )
        let newerTaskHeads = try InstallationTaskCurrentHeadContextV1(
            workspaceID: basisOne.workspaceID,
            activityID: basisActivityID,
            currentHeads: [
                newerIdentifyTask,
                resolvedPlacementTask,
                resolvedAsBuiltTask,
            ]
        )
        let supersededMutationID = try C47ActivityTestSupport.mutation(722)
        let supersededEnvelope = try ActivitySessionEnvelopeV2(
            activityID: basisActivityID,
            workspaceID: basisOne.workspaceID,
            kind: .installation,
            state: .superseded,
            reviewState: .acceptedRecordedFacts,
            subjectID: basisSubjectID,
            title: resolvedEnvelope.title,
            readiness: resolvedEnvelope.readiness,
            currentBasisReference: resolvedEnvelope.currentBasisReference,
            installationCloseout: resolvedEnvelope.installationCloseout,
            completedSnapshotReference: resolvedCompletedReference,
            startedAt: resolvedEnvelope.startedAt,
            finalizedAt: resolvedEnvelope.finalizedAt,
            revision: resolvedEnvelope.revision + 1,
            mutationID: supersededMutationID,
            predecessorEnvelopeSHA256: resolvedEnvelope.envelopeSHA256
        )
        let supersededTransition = try ActivityStateTransitionV2(
            transitionID: C47ActivityTestSupport.id(723),
            workspaceID: basisOne.workspaceID,
            activityID: basisActivityID,
            kind: .installation,
            fromState: .finalized,
            toState: .superseded,
            actor: C47ActivityTestSupport.actor(workspaceID: basisOne.workspaceID, slot: 724),
            occurredAt: C47ActivityTestSupport.fixedDate.addingTimeInterval(61),
            revision: supersededEnvelope.revision,
            mutationID: supersededMutationID
        )
        let closeoutContextMutation = try ActivityContractMutationV2(
            workspaceID: basisOne.workspaceID,
            expectedRevision: resolvedExpected,
            mutationID: supersededMutationID,
            predecessorEnvelope: resolvedEnvelope,
            successorEnvelope: supersededEnvelope,
            transition: supersededTransition,
            completedSnapshotReference: resolvedCompletedReference
        )
        XCTAssertThrowsError(try closeoutContextMutation.validateResolved(
            completedSnapshot: resolvedSnapshotContext,
            installationTaskHeads: newerTaskHeads,
            currentInstallationBasis: basisOne,
            workflowReleaseContext: resolvedWorkflowContext,
            installationReferenceContext: resolvedReferences,
            closeoutContext: resolvedCloseoutContext
        )) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .staleRevision)
        }
        let missingTerminalTaskHeads = try InstallationTaskCurrentHeadContextV1(
            workspaceID: basisOne.workspaceID,
            activityID: basisActivityID,
            currentHeads: [resolvedTask, resolvedPlacementTask]
        )
        XCTAssertThrowsError(try closeoutContextMutation.validateResolved(
            completedSnapshot: resolvedSnapshotContext,
            installationTaskHeads: missingTerminalTaskHeads,
            currentInstallationBasis: basisOne,
            workflowReleaseContext: resolvedWorkflowContext,
            installationReferenceContext: resolvedReferences,
            closeoutContext: resolvedCloseoutContext
        )) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .unsupportedClaim)
        }
        let undeclaredTask = try InstallationTaskResultV1(
            resultID: C47ActivityTestSupport.id(725),
            workspaceID: basisOne.workspaceID,
            activityID: basisActivityID,
            taskID: "undeclared-workflow-task",
            outcome: .completed,
            note: "An undeclared task must not satisfy a released workflow.",
            evidenceReferences: [resolvedContent],
            revision: 1,
            mutationID: try C47ActivityTestSupport.mutation(726)
        )
        let undeclaredTaskHeads = try InstallationTaskCurrentHeadContextV1(
            workspaceID: basisOne.workspaceID,
            activityID: basisActivityID,
            currentHeads: [
                resolvedTask,
                resolvedPlacementTask,
                resolvedAsBuiltTask,
                undeclaredTask,
            ]
        )
        XCTAssertThrowsError(try closeoutContextMutation.validateResolved(
            completedSnapshot: resolvedSnapshotContext,
            installationTaskHeads: undeclaredTaskHeads,
            currentInstallationBasis: basisOne,
            workflowReleaseContext: resolvedWorkflowContext,
            installationReferenceContext: resolvedReferences,
            closeoutContext: resolvedCloseoutContext
        )) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .missingReference)
        }
        let forgedSubjectEnvelope = try ActivitySessionEnvelopeV2(
            activityID: resolvedEnvelope.activityID,
            workspaceID: resolvedEnvelope.workspaceID,
            kind: resolvedEnvelope.kind,
            state: resolvedEnvelope.state,
            reviewState: resolvedEnvelope.reviewState,
            subjectID: C47ActivityTestSupport.id(238),
            title: resolvedEnvelope.title,
            readiness: resolvedEnvelope.readiness,
            currentBasisReference: resolvedEnvelope.currentBasisReference,
            installationCloseout: resolvedEnvelope.installationCloseout,
            completedSnapshotReference: resolvedEnvelope.completedSnapshotReference,
            startedAt: resolvedEnvelope.startedAt,
            finalizedAt: resolvedEnvelope.finalizedAt,
            revision: resolvedEnvelope.revision,
            mutationID: resolvedEnvelope.mutationID,
            predecessorEnvelopeSHA256: resolvedPredecessorEnvelope.envelopeSHA256
        )
        let forgedSubjectMutation = try ActivityContractMutationV2(
            workspaceID: basisOne.workspaceID,
            expectedRevision: resolvedExpected,
            mutationID: resolvedTaskMutationID,
            predecessorEnvelope: resolvedPredecessorEnvelope,
            successorEnvelope: forgedSubjectEnvelope,
            transition: resolvedTransition,
            completedSnapshotReference: resolvedCompletedReference,
            installationTaskResults: resolvedTaskResults,
            installationAsBuiltSnapshot: resolvedAsBuilt
        )
        XCTAssertThrowsError(try forgedSubjectMutation.validateResolved(
            completedSnapshot: resolvedSnapshotContext,
            installationTaskHeads: InstallationTaskCurrentHeadContextV1(
                workspaceID: basisOne.workspaceID,
                activityID: basisActivityID,
                currentHeads: []
            ),
            currentInstallationBasis: basisOne,
            workflowReleaseContext: resolvedWorkflowContext,
            installationReferenceContext: resolvedReferences,
            closeoutContext: resolvedCloseoutContext
        )) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .missingReference)
        }

        // Punch closeout/search/report stay independently typed. A punch-only
        // activity must not acquire installation rows or an installation
        // projection merely because the package registry contains both
        // bundled workflow families.
        let punchProjectionScope = [try PunchItemProjectionV1(
            scopeItemID: "punch.scope.c47",
            disposition: .reviewedNoItemRecorded
        )]
        let punchCloseoutForProjection = try PunchReviewCloseoutV1(
            completion: .completedNoPunchItemsRecordedInScope,
            basisSHA256: punchBasis.basisSHA256,
            scope: punchProjectionScope,
            scopeAndTimeLimitation: "Only the declared punch scope and recorded time were reviewed."
        )
        let punchActivityMutationID = try C47ActivityTestSupport.mutation(212)
        let punchCompletedReport = try C47ActivityTestSupport.completedReportFixture(
            workspaceID: punchBasis.workspaceID,
            activityID: punchBasis.activityID,
            assetID: punchBasis.subjectID,
            sourceRevision: 1
        )
        let punchCompletedReference = try CompletedActivitySnapshotV2CompatibilityReferenceV1(
            punchCompletedReport.snapshot,
            activityCloseoutSHA256: punchCloseoutForProjection.closeoutSHA256
        )
        let punchFinalizedEnvelope = try ActivitySessionEnvelopeV2(
            activityID: punchBasis.activityID,
            workspaceID: punchBasis.workspaceID,
            kind: .punchReview,
            state: .finalized,
            reviewState: .acceptedRecordedFacts,
            subjectID: punchBasis.subjectID,
            title: "Punch review closeout",
            readiness: C47ActivityTestSupport.readiness(),
            currentBasisReference: .punchReview(try PunchReviewBasisReferenceV1(punchBasis)),
            punchReviewCloseout: punchCloseoutForProjection,
            completedSnapshotReference: punchCompletedReference,
            startedAt: C47ActivityTestSupport.fixedDate,
            finalizedAt: C47ActivityTestSupport.fixedDate.addingTimeInterval(60),
            revision: 1,
            mutationID: punchActivityMutationID
        )
        let punchSearchProjection = try ActivityContractSearchProjectionV2(
            envelope: punchFinalizedEnvelope
        )
        XCTAssertEqual(punchSearchProjection.kind, .punchReview)
        XCTAssertEqual(punchSearchProjection.closeoutKind, "PUNCH_REVIEW")
        XCTAssertEqual(
            punchSearchProjection.closeoutDisposition,
            PunchReviewCompletionDispositionV1.completedNoPunchItemsRecordedInScope.rawValue
        )
        XCTAssertEqual(punchSearchProjection.recordedFindingCount, 0)
        XCTAssertEqual(punchSearchProjection.reviewedScopeItemCount, 1)
        let punchReportProjection = try ActivityContractReportProjectionV2(
            envelope: punchFinalizedEnvelope,
            completed: punchCompletedReport.snapshot,
            punch: punchBasis
        )
        try C47ActivityContractConformance_FieldEvidenceApp_Infrastructure_Reporting_ReportProjectionRegistryV1_swift
            .validate(punchReportProjection)
        XCTAssertThrowsError(try ActivityContractReportProjectionV2(
            envelope: punchFinalizedEnvelope,
            completed: punchCompletedReport.snapshot,
            installation: resolvedAsBuilt,
            punch: punchBasis
        )) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .invalidValue)
        }
        let mismatchedPunchCloseout = try PunchReviewCloseoutV1(
            completion: .completedNoPunchItemsRecordedInScope,
            basisSHA256: C47ActivityTestSupport.digest("f"),
            scope: punchProjectionScope,
            scopeAndTimeLimitation: punchCloseoutForProjection.scopeAndTimeLimitation
        )
        XCTAssertThrowsError(try ActivitySessionEnvelopeV2(
            activityID: punchFinalizedEnvelope.activityID,
            workspaceID: punchFinalizedEnvelope.workspaceID,
            kind: .punchReview,
            state: .finalized,
            reviewState: .acceptedRecordedFacts,
            subjectID: punchFinalizedEnvelope.subjectID,
            title: punchFinalizedEnvelope.title,
            readiness: punchFinalizedEnvelope.readiness,
            currentBasisReference: punchFinalizedEnvelope.currentBasisReference,
            punchReviewCloseout: mismatchedPunchCloseout,
            completedSnapshotReference: punchCompletedReference,
            startedAt: punchFinalizedEnvelope.startedAt,
            finalizedAt: punchFinalizedEnvelope.finalizedAt,
            revision: punchFinalizedEnvelope.revision,
            mutationID: punchFinalizedEnvelope.mutationID
        )) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .missingReference)
        }

        // Cross-workspace rebinds preserve immutable source closeout
        // provenance, but the target closeout is freshly mapped and therefore
        // cannot silently reuse the source target digest.
        let targetWorkspace = C47ActivityTestSupport.workspace(230)
        let targetActivityID = C47ActivityTestSupport.id(231)
        let targetInstallationRelease = try C47ActivityTestSupport.installationRelease(
            registry: retiredRegistry,
            workspaceID: targetWorkspace
        )
        let targetWorkflowReference = try basisOne.workflowReleaseReference.rebound(
            to: targetWorkspace,
            installation: targetInstallationRelease,
            package: shipping
        )
        let targetBasis = try basisOne.rebound(
            to: targetWorkspace,
            activityID: targetActivityID,
            subjectID: basisSubjectID,
            workflowReleaseReference: targetWorkflowReference,
            revision: 1,
            mutationID: C47ActivityTestSupport.mutation(232),
            mappedPredecessorBasisID: nil,
            mappedPredecessorBasisSHA256: nil
        )
        let targetCloseout = try InstallationCloseoutV1(
            completion: .completedAsRecorded,
            asBuiltSnapshotSHA256: C47ActivityTestSupport.digest("g")
        )
        let reboundEnvelope = try resolvedEnvelope.rebound(
            to: targetWorkspace,
            activityID: targetActivityID,
            subjectID: basisSubjectID,
            revision: 1,
            mutationID: C47ActivityTestSupport.mutation(233),
            mappedPredecessorEnvelopeSHA256: nil,
            mappedVariations: [],
            mappedAmendment: nil,
            mappedCurrentBasisReference: .installation(try InstallationBasisReferenceV1(targetBasis)),
            mappedInstallationCloseout: targetCloseout,
            mappedPunchReviewCloseout: nil
        )
        let reboundCompletedReference = try XCTUnwrap(
            reboundEnvelope.completedSnapshotReference
        )
        XCTAssertEqual(
            reboundCompletedReference.sourceCloseoutSHA256,
            resolvedCompletedReference.sourceCloseoutSHA256
        )
        XCTAssertEqual(
            reboundCompletedReference.targetCloseoutSHA256,
            targetCloseout.closeoutSHA256
        )
        XCTAssertNotEqual(
            reboundCompletedReference.targetCloseoutSHA256,
            resolvedCompletedReference.targetCloseoutSHA256
        )
        XCTAssertThrowsError(try resolvedEnvelope.rebound(
            to: targetWorkspace,
            activityID: targetActivityID,
            subjectID: basisSubjectID,
            revision: 1,
            mutationID: C47ActivityTestSupport.mutation(234),
            mappedPredecessorEnvelopeSHA256: nil,
            mappedVariations: [],
            mappedAmendment: nil,
            mappedCurrentBasisReference: .installation(try InstallationBasisReferenceV1(targetBasis)),
            mappedInstallationCloseout: nil,
            mappedPunchReviewCloseout: nil
        )) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .missingReference)
        }
        XCTAssertThrowsError(try resolvedCompletedReference.rebound(
            to: targetWorkspace,
            activityID: targetActivityID,
            targetCloseoutSHA256: "not-a-sha256"
        )) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .missingReference)
        }
        let targetPunchActivityID = C47ActivityTestSupport.id(235)
        let targetPunchRelease = try C47ActivityTestSupport.punchRelease(
            registry: retiredRegistry,
            workspaceID: targetWorkspace
        )
        let targetPunchWorkflowReference = try punchBasis.workflowReleaseReference.rebound(
            to: targetWorkspace,
            punchReview: targetPunchRelease,
            package: shipping
        )
        let targetPunchBasis = try punchBasis.rebound(
            to: targetWorkspace,
            activityID: targetPunchActivityID,
            subjectID: punchBasis.subjectID,
            workflowReleaseReference: targetPunchWorkflowReference,
            revision: 1,
            mutationID: C47ActivityTestSupport.mutation(236),
            mappedPredecessorBasisID: nil,
            mappedPredecessorBasisSHA256: nil
        )
        let targetPunchCloseout = try PunchReviewCloseoutV1(
            completion: .completedNoPunchItemsRecordedInScope,
            basisSHA256: targetPunchBasis.basisSHA256,
            scope: punchProjectionScope,
            scopeAndTimeLimitation: punchCloseoutForProjection.scopeAndTimeLimitation
        )
        let reboundPunchEnvelope = try punchFinalizedEnvelope.rebound(
            to: targetWorkspace,
            activityID: targetPunchActivityID,
            subjectID: punchBasis.subjectID,
            revision: 1,
            mutationID: C47ActivityTestSupport.mutation(237),
            mappedPredecessorEnvelopeSHA256: nil,
            mappedVariations: [],
            mappedAmendment: nil,
            mappedCurrentBasisReference: .punchReview(
                try PunchReviewBasisReferenceV1(targetPunchBasis)
            ),
            mappedInstallationCloseout: nil,
            mappedPunchReviewCloseout: targetPunchCloseout
        )
        let reboundPunchReference = try XCTUnwrap(
            reboundPunchEnvelope.completedSnapshotReference
        )
        XCTAssertEqual(
            reboundPunchReference.sourceCloseoutSHA256,
            punchCompletedReference.sourceCloseoutSHA256
        )
        XCTAssertEqual(
            reboundPunchReference.targetCloseoutSHA256,
            targetPunchCloseout.closeoutSHA256
        )
        XCTAssertNotEqual(
            reboundPunchReference.targetCloseoutSHA256,
            punchCompletedReference.targetCloseoutSHA256
        )

        let draftInstallationCloseout = try InstallationCloseoutV1(
            completion: .completedAsRecorded,
            asBuiltSnapshotSHA256: C47ActivityTestSupport.digest("c")
        )
        XCTAssertThrowsError(try ActivitySessionEnvelopeV2(
            activityID: C47ActivityTestSupport.id(191),
            workspaceID: C47ActivityTestSupport.workspace(),
            kind: .installation,
            state: .draft,
            reviewState: .notRequested,
            subjectID: C47ActivityTestSupport.id(192),
            title: "Draft closeout is forbidden",
            readiness: C47ActivityTestSupport.readiness(),
            installationCloseout: draftInstallationCloseout,
            revision: 1,
            mutationID: C47ActivityTestSupport.mutation(193)
        )) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .unsupportedClaim)
        }
        let draftPunchCloseout = try PunchReviewCloseoutV1(
            completion: .completedNoPunchItemsRecordedInScope,
            basisSHA256: C47ActivityTestSupport.digest("d"),
            scope: [try PunchItemProjectionV1(
                scopeItemID: "draft.scope",
                disposition: .reviewedNoItemRecorded
            )],
            scopeAndTimeLimitation: "Draft scope is not a closeout."
        )
        XCTAssertThrowsError(try ActivitySessionEnvelopeV2(
            activityID: C47ActivityTestSupport.id(194),
            workspaceID: C47ActivityTestSupport.workspace(),
            kind: .punchReview,
            state: .draft,
            reviewState: .notRequested,
            subjectID: C47ActivityTestSupport.id(195),
            title: "Draft punch closeout is forbidden",
            readiness: C47ActivityTestSupport.readiness(),
            punchReviewCloseout: draftPunchCloseout,
            revision: 1,
            mutationID: C47ActivityTestSupport.mutation(196)
        )) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .unsupportedClaim)
        }

        let draft = try C47ActivityTestSupport.envelope(kind: .installation, mutationSlot: 37)
        let variation = try ActivityVariationV1(
            variationID: C47ActivityTestSupport.id(38),
            workspaceID: C47ActivityTestSupport.workspace(),
            revision: 1,
            kind: .recordedScopeChanged,
            predecessorBasisSHA256: C47ActivityTestSupport.digest("8"),
            successorBasisSHA256: C47ActivityTestSupport.digest("9"),
            reason: "Recorded scope changed without rewriting the accepted basis.",
            actor: C47ActivityTestSupport.actor(slot: 82),
            occurredAt: C47ActivityTestSupport.fixedDate,
            mutationID: C47ActivityTestSupport.mutation(38)
        )
        let withVariation = try C47ActivityTestSupport.envelope(
            kind: .installation,
            state: .preflightRequired,
            revision: 2,
            mutationSlot: 38,
            predecessor: draft,
            variations: [variation]
        )
        try withVariation.validateSuccessor(of: draft)
        let removedVariation = try C47ActivityTestSupport.envelope(
            kind: .installation,
            state: .deferred,
            revision: 3,
            mutationSlot: 39,
            predecessor: withVariation,
            variations: []
        )
        XCTAssertThrowsError(try removedVariation.validateSuccessor(of: withVariation)) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .invalidTransition)
        }

        let started = try C47ActivityTestSupport.envelope(
            kind: .installation,
            state: .fieldComplete,
            mutationSlot: 40
        )
        let wrongKind = try C47ActivityTestSupport.envelope(
            kind: .punchReview,
            state: .readyForReview,
            revision: 2,
            mutationSlot: 41,
            predecessor: started
        )
        XCTAssertThrowsError(try wrongKind.validateSuccessor(of: started)) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .kindFrozen)
        }

        let mismatchedTransition = try ActivityStateTransitionV2(
            transitionID: C47ActivityTestSupport.id(42),
            workspaceID: withVariation.workspaceID,
            activityID: withVariation.activityID,
            kind: .installation,
            fromState: .draft,
            toState: .preflightRequired,
            actor: C47ActivityTestSupport.actor(slot: 84),
            occurredAt: C47ActivityTestSupport.fixedDate,
            revision: 999,
            mutationID: withVariation.mutationID
        )
        XCTAssertThrowsError(try ActivityContractMutationV2(
            workspaceID: withVariation.workspaceID,
            expectedRevision: WorkspaceExpectedRevisionV1(
                workspaceID: withVariation.workspaceID,
                generationID: C47ActivityTestSupport.id(43),
                writerInstanceID: C47ActivityTestSupport.id(44),
                workspaceRevision: 1,
                entityRevisions: [
                    WorkspaceEntityRevisionV1(
                        identity: try WorkspaceEntityIdentityV1(
                            kind: .activitySessionEnvelope,
                            id: draft.activityID
                        ),
                        revision: 1
                    ),
                    WorkspaceEntityRevisionV1(
                        identity: try WorkspaceEntityIdentityV1(
                            kind: .activityStateTransition,
                            id: mismatchedTransition.transitionID
                        ),
                        revision: 0
                    ),
                ]
            ),
            mutationID: withVariation.mutationID,
            predecessorEnvelope: draft,
            successorEnvelope: withVariation,
            transition: mismatchedTransition
        )) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .invalidValue)
        }

        let finding = try PunchFindingLinkV1(
            findingID: C47ActivityTestSupport.id(45),
            findingRevision: 1,
            findingSHA256: C47ActivityTestSupport.digest("1"),
            sourceContext: FindingSourceContextV1(
                workspaceID: C47ActivityTestSupport.workspace(),
                activityID: C47ActivityTestSupport.id(46),
                activityKind: .punchReview,
                activityRevision: 1,
                activitySHA256: C47ActivityTestSupport.digest("2"),
                taskOrScopeID: "scope.one"
            )
        )
        XCTAssertThrowsError(try PunchItemProjectionV1(
            scopeItemID: "scope.one",
            disposition: .reviewedWithItems,
            findingLinks: [finding, finding]
        )) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .invalidValue)
        }
        XCTAssertFalse(
            ActivityContractPersistenceEnrollmentV2
                .completionClaimsCommissioningComplianceApprovalOrCertification
        )
        XCTAssertTrue(ActivityContractPersistenceEnrollmentV2.inspectionNamedCanonicalStorageForbidden)
    }

    func testV23P03C47I01ThreeReceiptWriterInterruptionRecoversWithoutCrossFamilyMutation() async throws {
        let fallback = try NoPlanFallbackV1(limitation: "Retry remains manual and plan-independent.")
        let sharedDigest = C47ActivityTestSupport.digest("2")
        let installationDigest = C47ActivityTestSupport.digest("3")
        let punchDigest = C47ActivityTestSupport.digest("4")
        let firstShared = try SharedActivityEnvelopeReceiptV1(sharedContractSHA256: sharedDigest)
        let replayedShared = try SharedActivityEnvelopeReceiptV1(sharedContractSHA256: sharedDigest)
        let firstInstallation = try InstallationActivityContractReceiptV1(
            sharedContractSHA256: sharedDigest,
            installationContractSHA256: installationDigest,
            noPlanFallbackSHA256: fallback.fallbackSHA256
        )
        let replayedInstallation = try InstallationActivityContractReceiptV1(
            sharedContractSHA256: sharedDigest,
            installationContractSHA256: installationDigest,
            noPlanFallbackSHA256: fallback.fallbackSHA256
        )
        let firstPunch = try PunchActivityContractReceiptV1(
            sharedContractSHA256: sharedDigest,
            punchContractSHA256: punchDigest,
            noPlanFallbackSHA256: fallback.fallbackSHA256
        )
        let replayedPunch = try PunchActivityContractReceiptV1(
            sharedContractSHA256: sharedDigest,
            punchContractSHA256: punchDigest,
            noPlanFallbackSHA256: fallback.fallbackSHA256
        )
        XCTAssertEqual(firstShared, replayedShared)
        XCTAssertEqual(firstInstallation, replayedInstallation)
        XCTAssertEqual(firstPunch, replayedPunch)
        XCTAssertNotEqual(firstInstallation.receiptSHA256, firstPunch.receiptSHA256)
        XCTAssertEqual(
            Set(ActivityContractPersistenceEnrollmentV2.nonpersistentFamilies),
            Set([
                "SharedActivityEnvelopeReceiptV1",
                "InstallationActivityContractReceiptV1",
                "PunchActivityContractReceiptV1"
            ])
        )

        let applicationSupportURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "c47-writer-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }
        let session = try StoreGenerationFactory(
            applicationSupportURL: applicationSupportURL
        ).openOrBootstrapCurrent()
        let packageAuthority = try C47ActivityTestSupport.packageAuthority(
            workspaceID: session.workspaceID,
            slot: 520
        )
        session.modelContext.insert(try PromotedPackageReleaseRow(packageAuthority.promoted))
        session.modelContext.insert(try ActivePackageRegistryPointerRow(packageAuthority.pointer))
        try session.modelContext.save()
        XCTAssertEqual(
            try session.modelContext.fetch(FetchDescriptor<PromotedPackageReleaseRow>()).count,
            1
        )
        XCTAssertEqual(
            try session.modelContext.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>()).count,
            1
        )
        let writerInstanceID = C47ActivityTestSupport.id(60)
        let failure = MutationJournalFailureInjectionV1(failOnceAt: .afterEffectBeforeReceipt)
        let failingJournal = try MutationJournalStoreV1(
            modelContext: session.modelContext,
            identity: session.workspaceIdentity,
            generationID: session.generationID,
            failureInjection: failure
        )
        let current = try failingJournal.currentRevision(writerInstanceID: writerInstanceID)
        let seedMutationID = try C47ActivityTestSupport.mutation(58)
        let canonicalMutationID = try C47ActivityTestSupport.mutation(61)
        let canonicalActivityID = C47ActivityTestSupport.id(62)
        let canonicalSubjectID = C47ActivityTestSupport.id(3)
        let envelopeIdentity = try WorkspaceEntityIdentityV1(
            kind: .activitySessionEnvelope,
            id: canonicalActivityID
        )
        let taskEvidence = try C47ActivityTestSupport.evidenceFixture(
            workspaceID: session.workspaceID,
            slot: 263,
            recordSlot: 264
        )
        session.modelContext.insert(taskEvidence.file)
        try session.modelContext.save()
        let taskResult = try InstallationTaskResultV1(
            resultID: C47ActivityTestSupport.id(63),
            workspaceID: session.workspaceID,
            activityID: canonicalActivityID,
            taskID: "identify-subject",
            outcome: .completed,
            note: "The declared subject task survives effect-before-receipt recovery.",
            evidenceReferences: [taskEvidence.reference],
            revision: 1,
            mutationID: canonicalMutationID
        )
        let placementTaskResult = try InstallationTaskResultV1(
            resultID: C47ActivityTestSupport.id(66),
            workspaceID: session.workspaceID,
            activityID: canonicalActivityID,
            taskID: "record-placement",
            outcome: .completed,
            note: "The declared placement task survives effect-before-receipt recovery.",
            evidenceReferences: [taskEvidence.reference],
            revision: 1,
            mutationID: canonicalMutationID
        )
        let asBuiltTaskResult = try InstallationTaskResultV1(
            resultID: C47ActivityTestSupport.id(67),
            workspaceID: session.workspaceID,
            activityID: canonicalActivityID,
            taskID: "record-as-built",
            outcome: .completed,
            note: "The declared as-built task survives effect-before-receipt recovery.",
            evidenceReferences: [taskEvidence.reference],
            revision: 1,
            mutationID: canonicalMutationID
        )
        let taskResults = [taskResult, placementTaskResult, asBuiltTaskResult]
        let shippingPackage = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let workflowRegistry = try InspectionPackageRegistryV2(packages: [shippingPackage])
        let installationWorkflowRelease = try C47ActivityTestSupport.installationRelease(
            registry: workflowRegistry,
            workspaceID: session.workspaceID
        )
        let installationBasis = try InstallationBasisSnapshotV1(
            basisID: C47ActivityTestSupport.id(64),
            workspaceID: session.workspaceID,
            activityID: canonicalActivityID,
            subjectID: canonicalSubjectID,
            workflowReleaseReference: ActivityWorkflowReleaseReferenceV2(
                installation: installationWorkflowRelease,
                package: shippingPackage
            ),
            source: .noPlan(fallback),
            capturedAt: C47ActivityTestSupport.fixedDate,
            revision: 1,
            mutationID: seedMutationID
        )
        let seedEnvelope = try ActivitySessionEnvelopeV2(
            activityID: canonicalActivityID,
            workspaceID: session.workspaceID,
            kind: .installation,
            state: .draft,
            reviewState: .notRequested,
            subjectID: canonicalSubjectID,
            title: "Recorded field activity",
            readiness: C47ActivityTestSupport.readiness(),
            currentBasisReference: .installation(
                try InstallationBasisReferenceV1(installationBasis)
            ),
            revision: 1,
            mutationID: seedMutationID
        )
        let seedExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: current.entityRevisions + [
                WorkspaceEntityRevisionV1(identity: envelopeIdentity, revision: 0)
            ]
        )
        let seedMutation = try ActivityContractMutationV2(
            workspaceID: session.workspaceID,
            expectedRevision: seedExpected,
            mutationID: seedMutationID,
            successorEnvelope: seedEnvelope,
            installationBasisSnapshot: installationBasis
        )
        let seedJournal = try MutationJournalStoreV1(
            modelContext: session.modelContext,
            identity: session.workspaceIdentity,
            generationID: session.generationID
        )
        let seedWriter = try WorkspaceWriterV1(
            identity: session.workspaceIdentity,
            generationID: session.generationID,
            initialRevision: seedJournal.currentRevision(writerInstanceID: writerInstanceID),
            clock: C47ActivityClock(value: C47ActivityTestSupport.fixedDate),
            idSource: C47ActivityIDSource(value: writerInstanceID),
            fileAuthority: C47ActivityFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext),
            journalStore: seedJournal
        )
        _ = try await seedWriter.commitActivityContract(seedMutation)
        let reviewMutationID = try C47ActivityTestSupport.mutation(59)
        let reviewEnvelope = try ActivitySessionEnvelopeV2(
            activityID: canonicalActivityID,
            workspaceID: session.workspaceID,
            kind: .installation,
            state: .readyForReview,
            reviewState: .pending,
            subjectID: canonicalSubjectID,
            title: seedEnvelope.title,
            readiness: seedEnvelope.readiness,
            currentBasisReference: seedEnvelope.currentBasisReference,
            startedAt: C47ActivityTestSupport.fixedDate,
            revision: 2,
            mutationID: reviewMutationID,
            predecessorEnvelopeSHA256: seedEnvelope.envelopeSHA256
        )
        let reviewTransition = try ActivityStateTransitionV2(
            transitionID: C47ActivityTestSupport.id(68),
            workspaceID: session.workspaceID,
            activityID: canonicalActivityID,
            kind: .installation,
            fromState: .draft,
            toState: .readyForReview,
            actor: C47ActivityTestSupport.actor(workspaceID: session.workspaceID, slot: 69),
            occurredAt: C47ActivityTestSupport.fixedDate.addingTimeInterval(30),
            revision: 2,
            mutationID: reviewMutationID
        )
        let afterSeed = try seedWriter.currentRevision()
        let reviewExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: afterSeed.workspaceID,
            generationID: afterSeed.generationID,
            writerInstanceID: afterSeed.writerInstanceID,
            workspaceRevision: afterSeed.revision,
            entityRevisions: afterSeed.entityRevisions + [
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .activityStateTransition,
                        id: reviewTransition.transitionID
                    ),
                    revision: 0
                )
            ]
        )
        let reviewMutation = try ActivityContractMutationV2(
            workspaceID: session.workspaceID,
            expectedRevision: reviewExpected,
            mutationID: reviewMutationID,
            predecessorEnvelope: seedEnvelope,
            successorEnvelope: reviewEnvelope,
            transition: reviewTransition
        )
        _ = try await seedWriter.commitActivityContract(reviewMutation)
        let asBuilt = try InstallationAsBuiltSnapshotV1(
            snapshotID: C47ActivityTestSupport.id(65),
            workspaceID: session.workspaceID,
            activityID: canonicalActivityID,
            basisReference: try InstallationBasisReferenceV1(installationBasis),
            taskResultSHA256s: taskResults.map(\.resultSHA256),
            completion: .completedAsRecorded,
            revision: 1,
            mutationID: canonicalMutationID
        )
        let canonicalCloseout = try InstallationCloseoutV1(
            completion: .completedAsRecorded,
            asBuiltSnapshotSHA256: asBuilt.snapshotSHA256
        )
        let completedReport = try C47ActivityTestSupport.completedReportFixture(
            workspaceID: session.workspaceID,
            activityID: canonicalActivityID,
            assetID: canonicalSubjectID,
            sourceRevision: 3
        )
        let completedReference = try CompletedActivitySnapshotV2CompatibilityReferenceV1(
            completedReport.snapshot,
            activityCloseoutSHA256: canonicalCloseout.closeoutSHA256
        )
        let canonicalEnvelope = try ActivitySessionEnvelopeV2(
            activityID: canonicalActivityID,
            workspaceID: session.workspaceID,
            kind: .installation,
            state: .finalized,
            reviewState: .acceptedRecordedFacts,
            subjectID: canonicalSubjectID,
            title: "Recorded field activity",
            readiness: C47ActivityTestSupport.readiness(),
            currentBasisReference: .installation(
                try InstallationBasisReferenceV1(installationBasis)
            ),
            installationCloseout: canonicalCloseout,
            completedSnapshotReference: completedReference,
            startedAt: C47ActivityTestSupport.fixedDate,
            finalizedAt: C47ActivityTestSupport.fixedDate.addingTimeInterval(60),
            revision: 3,
            mutationID: canonicalMutationID,
            predecessorEnvelopeSHA256: reviewEnvelope.envelopeSHA256
        )
        let canonicalTransition = try ActivityStateTransitionV2(
            transitionID: C47ActivityTestSupport.id(70),
            workspaceID: session.workspaceID,
            activityID: canonicalActivityID,
            kind: .installation,
            fromState: .readyForReview,
            toState: .finalized,
            actor: C47ActivityTestSupport.actor(workspaceID: session.workspaceID, slot: 71),
            occurredAt: C47ActivityTestSupport.fixedDate.addingTimeInterval(60),
            revision: 3,
            mutationID: canonicalMutationID
        )
        let afterReview = try seedWriter.currentRevision()
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: afterReview.workspaceID,
            generationID: afterReview.generationID,
            writerInstanceID: afterReview.writerInstanceID,
            workspaceRevision: afterReview.revision,
            entityRevisions: afterReview.entityRevisions + [
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .activityStateTransition,
                        id: canonicalTransition.transitionID
                    ),
                    revision: 0
                ),
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .installationTaskResult,
                        id: taskResult.resultID
                    ),
                    revision: 0
                ),
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .installationTaskResult,
                        id: placementTaskResult.resultID
                    ),
                    revision: 0
                ),
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .installationTaskResult,
                        id: asBuiltTaskResult.resultID
                    ),
                    revision: 0
                ),
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .installationAsBuiltSnapshot,
                        id: asBuilt.snapshotID
                    ),
                    revision: 0
                )
            ]
        )
        let canonicalMutation = try ActivityContractMutationV2(
            workspaceID: session.workspaceID,
            expectedRevision: expected,
            mutationID: canonicalMutationID,
            predecessorEnvelope: reviewEnvelope,
            successorEnvelope: canonicalEnvelope,
            transition: canonicalTransition,
            completedSnapshotReference: completedReference,
            installationTaskResults: taskResults,
            installationAsBuiltSnapshot: asBuilt
        )
        let canonicalPostImages = try canonicalMutation.mutationPostImages
        let canonicalImageIdentities = try canonicalPostImages.map { try $0.identity }
        let canonicalConcurrencyIdentities = try canonicalPostImages.map {
            try $0.concurrencyIdentity
        }
        XCTAssertEqual(canonicalPostImages.count, 6)
        XCTAssertEqual(
            Set(canonicalImageIdentities).count,
            canonicalImageIdentities.count
        )
        XCTAssertEqual(
            Set(canonicalConcurrencyIdentities).count,
            canonicalConcurrencyIdentities.count
        )
        XCTAssertEqual(canonicalImageIdentities, canonicalConcurrencyIdentities)
        XCTAssertEqual(
            try canonicalMutation.concurrencyIdentities,
            canonicalImageIdentities
        )
        let priorActivityReceiptCount = try session.modelContext.fetch(
            FetchDescriptor<MutationReceiptRow>()
        ).filter {
            $0.commandKind == WorkspaceCommandKindV1.applyActivityContract.rawValue
        }.count
        let resolvedContentContext = try ActivityInstallationReferenceResolutionContextV2(
            contentReferences: [taskEvidence.reference],
            planPlacements: [],
            poseEvents: []
        )
        try resolvedContentContext.validate(canonicalMutation)
        func makeWriter(_ journal: MutationJournalStoreV1) throws -> WorkspaceWriterV1 {
            try WorkspaceWriterV1(
                identity: session.workspaceIdentity,
                generationID: session.generationID,
                initialRevision: journal.currentRevision(writerInstanceID: writerInstanceID),
                clock: C47ActivityClock(value: C47ActivityTestSupport.fixedDate),
                idSource: C47ActivityIDSource(value: writerInstanceID),
                fileAuthority: C47ActivityFileAuthority(),
                adapter: WorkspaceWriterAdapterV1(
                    modelContext: session.modelContext,
                    completedActivitySnapshotResolver: { reference in
                        try CompletedActivitySnapshotResolutionContextV2(
                            reference: reference,
                            snapshot: completedReport.snapshot
                        )
                    }
                ),
                journalStore: journal
            )
        }
        do {
            _ = try await makeWriter(failingJournal).commitActivityContract(canonicalMutation)
            XCTFail("Effect-before-receipt interruption must fail the first attempt")
        } catch {
            XCTAssertEqual(
                error as? MutationJournalFailureV1,
                .injected(.afterEffectBeforeReceipt)
            )
        }
        XCTAssertEqual(
            try session.modelContext.fetch(FetchDescriptor<ActivitySessionEnvelopeRow>()).count,
            1
        )
        XCTAssertEqual(
            try session.modelContext.fetch(FetchDescriptor<InstallationTaskResultRow>()).count,
            3
        )
        XCTAssertEqual(
            try session.modelContext.fetch(FetchDescriptor<InstallationAsBuiltSnapshotRow>()).count,
            1
        )
        XCTAssertTrue(
            try session.modelContext.fetch(FetchDescriptor<PunchReviewBasisSnapshotRow>()).isEmpty
        )
        XCTAssertEqual(
            try session.modelContext.fetch(FetchDescriptor<MutationReceiptRow>())
                .filter { $0.commandKind == WorkspaceCommandKindV1.applyActivityContract.rawValue }
                .count,
            priorActivityReceiptCount
        )
        let recoveryJournal = try MutationJournalStoreV1(
            modelContext: session.modelContext,
            identity: session.workspaceIdentity,
            generationID: session.generationID
        )
        let recoveryWriter = try makeWriter(recoveryJournal)
        let canonicalReceipt = try await recoveryWriter.commitActivityContract(canonicalMutation)
        let effectBeforeReceiptReplay = try await recoveryWriter.commitActivityContract(canonicalMutation)
        XCTAssertEqual(effectBeforeReceiptReplay, canonicalReceipt)
        let durableReceipt = try await recoveryWriter.durableActivityContractReceipt(
            workspaceID: session.workspaceID,
            mutationID: canonicalMutationID
        )
        XCTAssertEqual(durableReceipt, canonicalReceipt)
        let storedEnvelope = try XCTUnwrap(
            session.modelContext.fetch(FetchDescriptor<ActivitySessionEnvelopeRow>()).first
        )
        XCTAssertEqual(try storedEnvelope.value(), canonicalEnvelope)
        XCTAssertEqual(
            try session.modelContext.fetch(FetchDescriptor<ActivitySessionEnvelopeRow>()).count,
            1
        )
        XCTAssertEqual(
            try session.modelContext.fetch(FetchDescriptor<InstallationTaskResultRow>()).map {
                try $0.value()
            }.sorted(),
            taskResults.sorted()
        )
        XCTAssertEqual(
            try session.modelContext.fetch(FetchDescriptor<InstallationAsBuiltSnapshotRow>()).map {
                try $0.value()
            },
            [asBuilt]
        )
        XCTAssertTrue(
            try session.modelContext.fetch(FetchDescriptor<PunchReviewBasisSnapshotRow>()).isEmpty
        )
        try recoveryJournal.validateAll()
        let activityQuery = ActivityContractRowQueryV2(
            modelContext: session.modelContext,
            workspaceID: session.workspaceID,
            writer: recoveryWriter
        )
        let queriedCurrent = try await activityQuery.currentActivityContract(
            workspaceID: session.workspaceID,
            activityID: canonicalActivityID
        )
        let queriedState = try XCTUnwrap(queriedCurrent)
        let queriedEnvelope = try XCTUnwrap(queriedState.envelope)
        XCTAssertEqual(queriedState.activityID, canonicalActivityID)
        XCTAssertEqual(queriedEnvelope, canonicalEnvelope)
        let queriedEnvelopeRevision = try XCTUnwrap(
            queriedState.expectedRevision.entityRevisions.first {
                $0.identity.kind == .activitySessionEnvelope
                    && $0.identity.id == canonicalActivityID
            }
        )
        XCTAssertEqual(queriedEnvelopeRevision.revision, canonicalEnvelope.revision)
        let unrelatedCurrentValue = try await activityQuery.currentActivityContract(
            workspaceID: session.workspaceID,
            activityID: taskResult.resultID
        )
        let unrelatedCurrent = try XCTUnwrap(unrelatedCurrentValue)
        XCTAssertEqual(unrelatedCurrent.activityID, taskResult.resultID)
        XCTAssertNil(unrelatedCurrent.envelope)
        XCTAssertEqual(
            unrelatedCurrent.expectedRevision.entityRevisions.first {
                $0.identity.kind == .activitySessionEnvelope
                    && $0.identity.id == taskResult.resultID
            }?.revision,
            0
        )
    }

    func testV23P03C47R01BackupRestoreReplayDeleteEraseSearchReportAndForwardFixRemainExact() async throws {
        XCTAssertEqual(ActivityContractPersistenceEnrollmentV2.persistentFamilies.count, 6)
        XCTAssertEqual(
            ActivityContractPersistenceEnrollmentV2.persistentFamilies,
            [
                "ActivitySessionEnvelopeV2",
                "ActivityStateTransitionV2",
                "CompletedActivitySnapshotV2",
                "InstallationTaskResultV1",
                "InstallationAsBuiltSnapshotV1",
                "PunchReviewBasisSnapshotV1"
            ]
        )
        XCTAssertTrue(ActivityContractPersistenceEnrollmentV2.usesSoleWorkspaceWriter)
        XCTAssertFalse(ActivityContractPersistenceEnrollmentV2.planOrScanProviderRequired)
        for legacy in ActivityKindV1.allCases {
            let v2 = ActivityKindV1CompatibilityAdapterV2.v2(legacy)
            XCTAssertEqual(ActivityKindV1CompatibilityAdapterV2.v1(v2), legacy)
            XCTAssertEqual(ActivityKindV1CompatibilityAdapterV2.disposition(v2), .exactV1)
        }
        XCTAssertEqual(ActivityKindV1CompatibilityAdapterV2.disposition(.installation), .v2Only)
        XCTAssertEqual(ActivityKindV1CompatibilityAdapterV2.disposition(.punchReview), .v2Only)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "c47-lifecycle-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceSupport = root.appendingPathComponent("source", isDirectory: true)
        let source = try StoreGenerationFactory(applicationSupportURL: sourceSupport)
            .openOrBootstrapCurrent()
        let shippingPackage = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let packageAuthority = try C47ActivityTestSupport.packageAuthority(
            workspaceID: source.workspaceID,
            slot: 540
        )
        source.modelContext.insert(try PromotedPackageReleaseRow(packageAuthority.promoted))
        source.modelContext.insert(try ActivePackageRegistryPointerRow(packageAuthority.pointer))
        let subjectSiteID = C47ActivityTestSupport.id(90)
        let subjectAssetID = C47ActivityTestSupport.id(91)
        let sourceRecordID = C47ActivityTestSupport.id(416)
        let sourcePacketID = C47ActivityTestSupport.id(415)
        source.modelContext.insert(Site(
            id: subjectSiteID,
            label: "C47 activity site",
            address: "47 Activity Way",
            timeZoneID: "UTC",
            createdAt: C47ActivityTestSupport.fixedDate
        ))
        source.modelContext.insert(Asset(
            id: subjectAssetID,
            siteID: subjectSiteID,
            packID: shippingPackage.packageID,
            packSchemaVersion: 1,
            packContentVersion: shippingPackage.contentVersion,
            label: "C47 activity asset",
            createdAt: C47ActivityTestSupport.fixedDate
        ))
        source.modelContext.insert(Packet(
            id: sourcePacketID,
            stableRootID: C47ActivityTestSupport.id(418),
            currentRecordID: sourceRecordID,
            evaluationCounted: true,
            contentDeletedAt: nil,
            createdAt: C47ActivityTestSupport.fixedDate
        ))
        source.modelContext.insert(WorkflowRecord(
            id: sourceRecordID,
            assetID: subjectAssetID,
            packetID: sourcePacketID,
            issueID: nil,
            parentRecordID: nil,
            recordRevisionRootID: sourceRecordID,
            revisesRecordID: nil,
            evidenceSourceRecordID: nil,
            revisionKind: .original,
            stage: .check,
            state: .draft,
            draftStepKey: .wide,
            startedAt: C47ActivityTestSupport.fixedDate,
            completedAt: nil,
            observedAtUTC: C47ActivityTestSupport.fixedDate,
            timeZoneID: "UTC",
            utcOffsetMinutes: 0,
            localDate: "2027-01-15",
            localTime: "08:00",
            afterDarkAcknowledgementKey: nil,
            afterDarkAcknowledgementCopy: nil,
            afterDarkAcknowledgementVersion: nil,
            afterDarkAcknowledgementAccepted: nil,
            safePositionAcknowledgementKey: nil,
            safePositionAcknowledgementCopy: nil,
            safePositionAcknowledgementVersion: nil,
            safePositionAcknowledgementAccepted: nil,
            packID: shippingPackage.packageID,
            packSchemaVersion: 1,
            packContentVersion: shippingPackage.contentVersion,
            pdfTemplateID: "field.evidence.pdf.worklight.v1",
            pdfTemplateVersion: 1,
            outcomeKey: nil,
            couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil,
            couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: nil,
            workDescription: nil,
            note: "C47 source activity owner",
            finalizationMutationID: nil
        ))
        let observationBasis = try ObservationBasisV1(
            kind: .directlyObserved,
            method: try ObservationMethodV1(key: "manual"),
            source: try ObservationSourceReferenceV1(kind: .observer)
        )
        let temporalContext = try TemporalContextV1(
            occurredAtUTC: C47ActivityTestSupport.fixedDate,
            recordedAtUTC: C47ActivityTestSupport.fixedDate,
            localDate: "2027-01-15",
            localTime: "08:00:00",
            utcOffsetSeconds: 0,
            ianaTimeZoneIdentifier: "UTC",
            localTimeDisposition: .unambiguous
        )
        source.modelContext.insert(try ObservationAndTimeRow(
            recordID: sourceRecordID,
            observationBasis: observationBasis,
            temporalContext: temporalContext
        ))
        source.modelContext.insert(try RequirementAssuranceRow.blockingUnknownBackfill(
            workflowRecordID: sourceRecordID,
            workspaceID: source.workspaceID.rawValue,
            evaluatedRevision: 1,
            requirementID: "legacy_assurance_unknown",
            requirementVersion: 1,
            requirementTypeID: "legacy_assurance_unknown",
            policySHA256: StoreMigrationCanonicalJSONV1.sha256(
                Data("legacy-assurance-unknown-v1".utf8)
            ),
            mutationID: sourceRecordID,
            timestamp: C47ActivityTestSupport.fixedDate
        ))
        try source.modelContext.save()
        XCTAssertEqual(
            try source.modelContext.fetch(FetchDescriptor<PromotedPackageReleaseRow>()).count,
            1
        )
        XCTAssertEqual(
            try source.modelContext.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>()).count,
            1
        )

        let writerInstanceID = C47ActivityTestSupport.id(92)
        let journal = try MutationJournalStoreV1(
            modelContext: source.modelContext,
            identity: source.workspaceIdentity,
            generationID: source.generationID
        )
        let initial = try journal.currentRevision(writerInstanceID: writerInstanceID)
        let activityID = C47ActivityTestSupport.id(93)
        let mutationID = try C47ActivityTestSupport.mutation(94)
        let completedReport = try C47ActivityTestSupport.completedReportFixture(
            workspaceID: source.workspaceID,
            activityID: activityID,
            assetID: subjectAssetID,
            sourceRevision: 7
        )
        var completedReference: CompletedActivitySnapshotV2CompatibilityReferenceV1?
        let sourceEvidence = try C47ActivityTestSupport.evidenceFixture(
            workspaceID: source.workspaceID,
            slot: 430,
            recordSlot: 416
        )
        source.modelContext.insert(sourceEvidence.file)
        let evidenceDirectory = source.generationRootURL.appendingPathComponent(
            "evidence/\(sourceEvidence.file.id.uuidString.lowercased())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        try sourceEvidence.originalJPEG.write(
            to: evidenceDirectory.appendingPathComponent("original.jpg"),
            options: .atomic
        )
        try sourceEvidence.thumbnailJPEG.write(
            to: evidenceDirectory.appendingPathComponent("thumbnail.jpg"),
            options: .atomic
        )
        try source.modelContext.save()
        let completedSnapshotBytes = try CompletedActivitySnapshotCanonicalCodecV2.encode(
            completedReport.snapshot
        )
        let snapshotRelativePath = "snapshots/c47-completed-activity-v2.json"
        let snapshotURL = source.generationRootURL.appendingPathComponent(snapshotRelativePath)
        try FileManager.default.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try completedSnapshotBytes.write(to: snapshotURL, options: .atomic)
        source.modelContext.insert(Report(
            id: C47ActivityTestSupport.id(414),
            packetID: sourcePacketID,
            sourceRecordID: sourceRecordID,
            snapshotSchemaVersion: CompletedActivitySnapshotV2.schemaVersion,
            snapshotRelativePath: snapshotRelativePath,
            snapshotSHA256: completedReport.snapshot.snapshotSHA256,
            pdfState: .pending,
            pdfRelativePath: nil,
            pdfSHA256: nil,
            createdAt: C47ActivityTestSupport.fixedDate,
            replacesReportID: nil
        ))
        try source.modelContext.save()
        let sourceEnvelopeSeed = try ActivitySessionEnvelopeV2(
            activityID: activityID,
            workspaceID: source.workspaceID,
            kind: .installation,
            state: .draft,
            reviewState: .notRequested,
            subjectID: subjectAssetID,
            title: "Lifecycle installation activity",
            readiness: C47ActivityTestSupport.readiness(),
            revision: 1,
            mutationID: mutationID
        )
        let envelopeIdentity = try WorkspaceEntityIdentityV1(
            kind: .activitySessionEnvelope,
            id: activityID
        )
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: initial.workspaceID,
            generationID: initial.generationID,
            writerInstanceID: initial.writerInstanceID,
            workspaceRevision: initial.revision,
            entityRevisions: initial.entityRevisions + [
                WorkspaceEntityRevisionV1(identity: envelopeIdentity, revision: 0)
            ]
        )
        let sourceWorkflowRegistry = try InspectionPackageRegistryV2(packages: [shippingPackage])
        let sourceInstallationRelease = try C47ActivityTestSupport.installationRelease(
            registry: sourceWorkflowRegistry,
            workspaceID: source.workspaceID
        )
        let sourceInstallationBasis = try InstallationBasisSnapshotV1(
            basisID: C47ActivityTestSupport.id(417),
            workspaceID: source.workspaceID,
            activityID: activityID,
            subjectID: subjectAssetID,
            workflowReleaseReference: ActivityWorkflowReleaseReferenceV2(
                installation: sourceInstallationRelease,
                package: shippingPackage
            ),
            source: .noPlan(NoPlanFallbackV1(
                limitation: "Recorded installation uses the bundled release without plan authority."
            )),
            capturedAt: C47ActivityTestSupport.fixedDate,
            revision: 1,
            mutationID: mutationID
        )
        let sourceBasisReference = ActivityBasisHeadReferenceV2.installation(
            try InstallationBasisReferenceV1(sourceInstallationBasis)
        )
        let sourceEnvelope = try ActivitySessionEnvelopeV2(
            activityID: sourceEnvelopeSeed.activityID,
            workspaceID: sourceEnvelopeSeed.workspaceID,
            kind: sourceEnvelopeSeed.kind,
            state: sourceEnvelopeSeed.state,
            reviewState: sourceEnvelopeSeed.reviewState,
            subjectID: sourceEnvelopeSeed.subjectID,
            title: sourceEnvelopeSeed.title,
            readiness: sourceEnvelopeSeed.readiness,
            currentBasisReference: sourceBasisReference,
            revision: sourceEnvelopeSeed.revision,
            mutationID: sourceEnvelopeSeed.mutationID
        )
        let mutation = try ActivityContractMutationV2(
            workspaceID: source.workspaceID,
            expectedRevision: expected,
            mutationID: mutationID,
            successorEnvelope: sourceEnvelope,
            installationBasisSnapshot: sourceInstallationBasis
        )
        let writer = try WorkspaceWriterV1(
            identity: source.workspaceIdentity,
            generationID: source.generationID,
            initialRevision: initial,
            clock: C47ActivityClock(value: C47ActivityTestSupport.fixedDate),
            idSource: C47ActivityIDSource(value: writerInstanceID),
            fileAuthority: C47ActivityFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(
                modelContext: source.modelContext,
                completedActivitySnapshotResolver: { reference in
                    try CompletedActivitySnapshotResolutionContextV2(
                        reference: reference,
                        snapshot: completedReport.snapshot
                    )
                }
            ),
            journalStore: journal
        )
        let sourceReceipt = try await writer.commitActivityContract(mutation)
        let replayedSourceReceipt = try await writer.commitActivityContract(mutation)
        XCTAssertEqual(replayedSourceReceipt, sourceReceipt)
        let revisionTwoMutationID = try C47ActivityTestSupport.mutation(96)
        let revisionTwoEnvelope = try ActivitySessionEnvelopeV2(
            activityID: activityID,
            workspaceID: source.workspaceID,
            kind: .installation,
            state: .preflightRequired,
            reviewState: .notRequested,
            subjectID: subjectAssetID,
            title: sourceEnvelope.title,
            readiness: sourceEnvelope.readiness,
            currentBasisReference: sourceBasisReference,
            revision: 2,
            mutationID: revisionTwoMutationID,
            predecessorEnvelopeSHA256: sourceEnvelope.envelopeSHA256
        )
        let revisionTwoTransition = try ActivityStateTransitionV2(
            transitionID: C47ActivityTestSupport.id(97),
            workspaceID: source.workspaceID,
            activityID: activityID,
            kind: .installation,
            fromState: .draft,
            toState: .preflightRequired,
            actor: C47ActivityTestSupport.actor(workspaceID: source.workspaceID, slot: 120),
            occurredAt: C47ActivityTestSupport.fixedDate.addingTimeInterval(10),
            revision: 2,
            mutationID: revisionTwoMutationID
        )
        let afterRevisionOne = try writer.currentRevision()
        let transitionIdentity = try WorkspaceEntityIdentityV1(
            kind: .activityStateTransition,
            id: revisionTwoTransition.transitionID
        )
        let revisionTwoExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: afterRevisionOne.workspaceID,
            generationID: afterRevisionOne.generationID,
            writerInstanceID: afterRevisionOne.writerInstanceID,
            workspaceRevision: afterRevisionOne.revision,
            entityRevisions: afterRevisionOne.entityRevisions + [
                WorkspaceEntityRevisionV1(identity: transitionIdentity, revision: 0)
            ]
        )
        let revisionTwoMutation = try ActivityContractMutationV2(
            workspaceID: source.workspaceID,
            expectedRevision: revisionTwoExpected,
            mutationID: revisionTwoMutationID,
            predecessorEnvelope: sourceEnvelope,
            successorEnvelope: revisionTwoEnvelope,
            transition: revisionTwoTransition
        )
        let revisionTwoReceipt = try await writer.commitActivityContract(revisionTwoMutation)
        let replayedRevisionTwoReceipt = try await writer.commitActivityContract(revisionTwoMutation)
        XCTAssertEqual(replayedRevisionTwoReceipt, revisionTwoReceipt)
        XCTAssertNotEqual(revisionTwoReceipt, sourceReceipt)
        var sourceMutations = [mutation, revisionTwoMutation]
        var currentEnvelope = revisionTwoEnvelope
        let readinessPolicy = ActivityReadinessPolicyBindingV2.installation(
            try InstallationReadinessPolicyV1(requiredFacets: [.access])
        )
        let remainingStates: [ActivityStateV2] = [
            .ready, .inProgress, .fieldComplete, .readyForReview, .finalized,
        ]
        for (offset, state) in remainingStates.enumerated() {
            let revision = UInt64(offset + 3)
            let nextMutationID = try C47ActivityTestSupport.mutation(200 + offset)
            let finalTasks: [InstallationTaskResultV1]
            let finalAsBuilt: InstallationAsBuiltSnapshotV1?
            let finalCloseout: InstallationCloseoutV1?
            if state == .finalized {
                let subjectTask = try InstallationTaskResultV1(
                    resultID: C47ActivityTestSupport.id(230),
                    workspaceID: source.workspaceID,
                    activityID: activityID,
                    taskID: "identify-subject",
                    outcome: .completed,
                    note: "The released subject task is covered before terminal closeout.",
                    evidenceReferences: [sourceEvidence.reference],
                    revision: 1,
                    mutationID: nextMutationID
                )
                let placementTask = try InstallationTaskResultV1(
                    resultID: C47ActivityTestSupport.id(232),
                    workspaceID: source.workspaceID,
                    activityID: activityID,
                    taskID: "record-placement",
                    outcome: .completed,
                    note: "The released placement task is covered before terminal closeout.",
                    evidenceReferences: [sourceEvidence.reference],
                    revision: 1,
                    mutationID: nextMutationID
                )
                let asBuiltTask = try InstallationTaskResultV1(
                    resultID: C47ActivityTestSupport.id(233),
                    workspaceID: source.workspaceID,
                    activityID: activityID,
                    taskID: "record-as-built",
                    outcome: .completed,
                    note: "The released as-built task is covered before terminal closeout.",
                    evidenceReferences: [sourceEvidence.reference],
                    revision: 1,
                    mutationID: nextMutationID
                )
                let tasks = [subjectTask, placementTask, asBuiltTask]
                let asBuilt = try InstallationAsBuiltSnapshotV1(
                    snapshotID: C47ActivityTestSupport.id(231),
                    workspaceID: source.workspaceID,
                    activityID: activityID,
                    basisReference: try InstallationBasisReferenceV1(sourceInstallationBasis),
                    taskResultSHA256s: tasks.map(\.resultSHA256),
                    completion: .completedAsRecorded,
                    revision: 1,
                    mutationID: nextMutationID
                )
                finalTasks = tasks
                finalAsBuilt = asBuilt
                let closeout = try InstallationCloseoutV1(
                    completion: .completedAsRecorded,
                    asBuiltSnapshotSHA256: asBuilt.snapshotSHA256
                )
                finalCloseout = closeout
                completedReference = try CompletedActivitySnapshotV2CompatibilityReferenceV1(
                    completedReport.snapshot,
                    activityCloseoutSHA256: closeout.closeoutSHA256
                )
            } else {
                finalTasks = []
                finalAsBuilt = nil
                finalCloseout = nil
            }
            let nextEnvelope = try ActivitySessionEnvelopeV2(
                activityID: activityID,
                workspaceID: source.workspaceID,
                kind: .installation,
                state: state,
                reviewState: state == .readyForReview
                    ? .pending
                    : state == .finalized ? .acceptedRecordedFacts : .notRequested,
                subjectID: subjectAssetID,
                title: sourceEnvelope.title,
                readiness: sourceEnvelope.readiness,
                readinessPolicy: readinessPolicy,
                currentBasisReference: sourceBasisReference,
                installationCloseout: finalCloseout,
                completedSnapshotReference: state == .finalized ? completedReference : nil,
                startedAt: state.hasStarted ? C47ActivityTestSupport.fixedDate : nil,
                finalizedAt: state == .finalized
                    ? C47ActivityTestSupport.fixedDate.addingTimeInterval(60) : nil,
                revision: revision,
                mutationID: nextMutationID,
                predecessorEnvelopeSHA256: currentEnvelope.envelopeSHA256
            )
            let transition = try ActivityStateTransitionV2(
                transitionID: C47ActivityTestSupport.id(210 + offset),
                workspaceID: source.workspaceID,
                activityID: activityID,
                kind: .installation,
                fromState: currentEnvelope.state,
                toState: state,
                actor: C47ActivityTestSupport.actor(
                    workspaceID: source.workspaceID,
                    slot: 220 + offset * 2
                ),
                occurredAt: C47ActivityTestSupport.fixedDate.addingTimeInterval(Double(20 + offset)),
                revision: revision,
                mutationID: nextMutationID
            )
            let currentRevision = try writer.currentRevision()
            var addedRevisions = [
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .activityStateTransition,
                        id: transition.transitionID
                    ),
                    revision: 0
                )
            ]
            for finalTask in finalTasks {
                addedRevisions.append(WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .installationTaskResult,
                        id: finalTask.resultID
                    ),
                    revision: 0
                ))
            }
            if let finalAsBuilt {
                addedRevisions.append(WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .installationAsBuiltSnapshot,
                        id: finalAsBuilt.snapshotID
                    ),
                    revision: 0
                ))
            }
            let nextExpected = try WorkspaceExpectedRevisionV1(
                workspaceID: currentRevision.workspaceID,
                generationID: currentRevision.generationID,
                writerInstanceID: currentRevision.writerInstanceID,
                workspaceRevision: currentRevision.revision,
                entityRevisions: currentRevision.entityRevisions + addedRevisions
            )
            let nextMutation = try ActivityContractMutationV2(
                workspaceID: source.workspaceID,
                expectedRevision: nextExpected,
                mutationID: nextMutationID,
                predecessorEnvelope: currentEnvelope,
                successorEnvelope: nextEnvelope,
                transition: transition,
                completedSnapshotReference: state == .finalized ? completedReference : nil,
                installationTaskResults: finalTasks,
                installationAsBuiltSnapshot: finalAsBuilt
            )
            let receipt = try await writer.commitActivityContract(nextMutation)
            let replayedReceipt = try await writer.commitActivityContract(nextMutation)
            XCTAssertEqual(replayedReceipt, receipt)
            sourceMutations.append(nextMutation)
            currentEnvelope = nextEnvelope
        }
        let finalizedEnvelope = currentEnvelope
        XCTAssertEqual(finalizedEnvelope.state, .finalized)
        let completedReference = try XCTUnwrap(completedReference)
        let resolvedSnapshot = try CompletedActivitySnapshotResolutionContextV2(
            reference: completedReference,
            snapshot: completedReport.snapshot
        )
        let finalMutation = try XCTUnwrap(sourceMutations.last)
        let sourceWorkflowContext = try ActivityWorkflowReleaseResolutionContextV2(
            reference: sourceInstallationBasis.workflowReleaseReference,
            installation: sourceInstallationRelease,
            package: shippingPackage,
            availability: try ActivityWorkflowFamilyAvailabilityV2(
                reference: sourceInstallationBasis.workflowReleaseReference,
                disposition: .availableForStart
            )
        )
        let sourceReferenceContext = try ActivityInstallationReferenceResolutionContextV2(
            contentReferences: [sourceEvidence.reference],
            planPlacements: [],
            poseEvents: []
        )
        let sourceCloseoutContext = try ActivityCloseoutResolutionContextV2(
            findings: [],
            supportingRecords: [],
            sourceEnvelopes: [],
            installationAsBuiltSnapshot: try XCTUnwrap(finalMutation.installationAsBuiltSnapshot)
        )
        try finalMutation.validateResolved(
            completedSnapshot: resolvedSnapshot,
            installationTaskHeads: InstallationTaskCurrentHeadContextV1(
                workspaceID: source.workspaceID,
                activityID: activityID,
                currentHeads: []
            ),
            currentInstallationBasis: sourceInstallationBasis,
            workflowReleaseContext: sourceWorkflowContext,
            installationReferenceContext: sourceReferenceContext,
            closeoutContext: sourceCloseoutContext
        )
        try journal.validateAll()

        let reportProjection = try ActivityContractReportProjectionV2(
            envelope: finalizedEnvelope,
            completed: completedReport.snapshot
        )
        try C47ActivityContractConformance_FieldEvidenceApp_Infrastructure_Reporting_ReportProjectionRegistryV1_swift
            .validate(reportProjection)
        let openJSONMetadata = try C47ActivityContractConformance_FieldEvidenceApp_Infrastructure_Reporting_DeterministicOpenJSONRendererV1_swift
            .metadata(reportProjection)
        XCTAssertEqual(openJSONMetadata["activity_kind"], ActivityKindV2.installation.rawValue)
        XCTAssertEqual(openJSONMetadata["activity_state"], ActivityStateV2.finalized.rawValue)
        XCTAssertEqual(
            try C47ActivityContractConformance_FieldEvidenceApp_Infrastructure_Reporting_DeterministicPDFRendererV1_swift
                .c47ActivityLines(reportProjection),
            [finalizedEnvelope.title, finalizedEnvelope.kind.rawValue, finalizedEnvelope.state.rawValue]
        )
        let renderedReport = try ReportRenderService(
            modelContext: source.modelContext,
            generationRootURL: source.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
        ).renderActivityContract(
            reportProjection,
            manifest: completedReport.manifest,
            reportProfile: completedReport.layout,
            exportProfile: completedReport.export
        )
        let reopenedReport = try ReportRecoveryService.reopenActivityContract(
            reportProjection,
            manifest: completedReport.manifest,
            reportProfile: completedReport.layout,
            exportProfile: completedReport.export,
            storedBundle: renderedReport
        )
        XCTAssertEqual(reopenedReport, renderedReport)
        XCTAssertEqual(renderedReport.snapshotSHA256, completedReport.snapshot.snapshotSHA256)
        XCTAssertEqual(renderedReport.pdf.format, .pdf)
        XCTAssertEqual(renderedReport.openJSON.format, .openJSON)
        XCTAssertEqual(renderedReport.structuredText.format, .structuredText)

        let searchRevision = try SearchSourceRevisionV1(
            workspaceID: source.workspaceID.rawValue,
            generationID: source.generationID,
            commitRevision: try writer.currentRevision().revision
        )
        let searchSource = try SwiftDataSearchCanonicalProjectionSourceV1(
            modelContext: source.modelContext,
            workspaceID: source.workspaceID.rawValue,
            generationID: source.generationID,
            revisionProvider: { searchRevision },
            includeAccountability: true
        )
        let searchStore = try LocalSearchIndexStoreV1(
            applicationSupportURL: root.appendingPathComponent("search", isDirectory: true)
        )
        let searchRebuild = try SearchIndexRebuildCoordinatorV1(
            store: searchStore,
            source: searchSource,
            registry: searchSource.registry,
            makeOperationID: { C47ActivityTestSupport.id(95) }
        )
        _ = try await searchRebuild.rebuildIfNeeded()
        let search = SearchCoordinatorV1(index: searchStore)
        let searchPlan = try search.makePlan(
            query: "lifecycle installation",
            scope: .work,
            sourceRevision: searchRevision.commitRevision
        )
        let searchResponse = try await search.search(
            searchPlan,
            source: searchRevision,
            registry: searchSource.registry
        )
        XCTAssertEqual(searchResponse.results.map(\.displayIdentity), [finalizedEnvelope.title])
        XCTAssertEqual(searchResponse.results.map(\.status), [finalizedEnvelope.state.rawValue])

        let sourceActivityReceiptRows = try source.modelContext.fetch(
            FetchDescriptor<MutationReceiptRow>()
        )
        .filter { $0.commandKind == WorkspaceCommandKindV1.applyActivityContract.rawValue }
        .sorted { $0.localSequence < $1.localSequence }
        XCTAssertEqual(sourceActivityReceiptRows.count, sourceMutations.count)
        let sourceSequences = sourceActivityReceiptRows.map(\.localSequence)
        XCTAssertEqual(sourceSequences, sourceSequences.sorted())
        XCTAssertTrue(zip(sourceSequences, sourceSequences.dropFirst()).allSatisfy { prior, next in
            prior < next
        })
        let sourceCausalRevisions = try sourceActivityReceiptRows.map {
            try MutationReceiptV1.decodeCanonical(from: $0.receiptData)
                .resultingRevision.workspaceRevision
        }
        XCTAssertEqual(sourceCausalRevisions, sourceCausalRevisions.sorted())
        XCTAssertTrue(zip(sourceCausalRevisions, sourceCausalRevisions.dropFirst()).allSatisfy {
            prior, next in prior < next
        })
        let sourceActivityEnvelopeBytes = sourceActivityReceiptRows.map(\.envelopeData)
        let sourceActivityReceiptBytes = sourceActivityReceiptRows.map(\.receiptData)

        let exportRoot = root.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let exporter = BackupExportService(
            modelContext: source.modelContext,
            generationRootURL: source.generationRootURL,
            now: { C47ActivityTestSupport.fixedDate }
        )
        let exportPreview = try exporter.prepare()
        let package = try exporter.export(previewID: exportPreview.id, to: exportRoot)
        var eraseCandidate: (support: URL, session: StoreGenerationSession)?
        for (index, mode) in [BackupRestoreMode.emptyInstall, .clone, .fork].enumerated() {
            let support = root.appendingPathComponent("restore-\(index)", isDirectory: true)
            let current = try StoreGenerationFactory(applicationSupportURL: support)
                .openOrBootstrapCurrent()
            let validated = try BackupImportService(
                generationRootURL: current.generationRootURL,
                makeUUID: { C47ActivityTestSupport.id(100 + index) },
                scopedAccess: .alreadyAuthorized
            ).stageAndValidate(selectedPackageURL: package)
            let archivedValues = try validated.records.validateC47ActivityContracts()
            XCTAssertEqual(archivedValues.envelopes, [finalizedEnvelope])
            XCTAssertEqual(
                Set(archivedValues.transitions.map(\.transitionSHA256)),
                Set(sourceMutations.compactMap(\.transition).map(\.transitionSHA256))
            )
            let restored = try await BackupRestoreService(
                applicationSupportURL: support,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
            ).restore(
                validatedPackage: validated,
                currentModelContext: current.modelContext,
                currentGenerationID: current.generationID,
                currentGenerationRootURL: current.generationRootURL,
                mode: mode
            )
            let restoredRow = try XCTUnwrap(
                restored.modelContext.fetch(FetchDescriptor<ActivitySessionEnvelopeRow>()).first
            )
            let restoredEnvelope = try restoredRow.value()
            XCTAssertEqual(restoredEnvelope.activityID, finalizedEnvelope.activityID)
            XCTAssertEqual(restoredEnvelope.title, finalizedEnvelope.title)
            XCTAssertEqual(restoredEnvelope.kind, finalizedEnvelope.kind)
            XCTAssertEqual(restoredEnvelope.revision, finalizedEnvelope.revision)
            if mode == .emptyInstall {
                XCTAssertEqual(restoredEnvelope, finalizedEnvelope)
                XCTAssertEqual(
                    restoredRow.canonicalData,
                    try finalizedEnvelope.canonicalData()
                )
            } else {
                XCTAssertEqual(restoredEnvelope.workspaceID, restored.workspaceID)
                XCTAssertNotEqual(restoredEnvelope.workspaceID, finalizedEnvelope.workspaceID)
                XCTAssertNotEqual(restoredEnvelope.envelopeSHA256, finalizedEnvelope.envelopeSHA256)
            }
            let restoredJournal = try MutationJournalStoreV1(
                modelContext: restored.modelContext,
                identity: restored.workspaceIdentity,
                generationID: restored.generationID,
                allowStateBootstrap: false
            )
            try restoredJournal.validateAll()
            let restoredActivityRows = try restored.modelContext.fetch(
                FetchDescriptor<MutationReceiptRow>()
            )
            .filter { $0.commandKind == WorkspaceCommandKindV1.applyActivityContract.rawValue }
            .sorted { $0.localSequence < $1.localSequence }
            XCTAssertEqual(restoredActivityRows.count, sourceMutations.count)
            let restoredSequences = restoredActivityRows.map(\.localSequence)
            XCTAssertEqual(restoredSequences, restoredSequences.sorted())
            XCTAssertTrue(zip(restoredSequences, restoredSequences.dropFirst()).allSatisfy { prior, next in
                prior < next
            })
            let restoredCausalRevisions = try restoredActivityRows.map {
                try MutationReceiptV1.decodeCanonical(from: $0.receiptData)
                    .resultingRevision.workspaceRevision
            }
            XCTAssertEqual(restoredCausalRevisions, restoredCausalRevisions.sorted())
            XCTAssertTrue(zip(restoredCausalRevisions, restoredCausalRevisions.dropFirst()).allSatisfy {
                prior, next in prior < next
            })
            var restoredMutations: [ActivityContractMutationV2] = []
            for row in restoredActivityRows {
                let envelope = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData)
                guard case let .applyActivityContract(value) = envelope.command else {
                    XCTFail("Expected an activity-contract receipt")
                    return
                }
                let receipt = try MutationReceiptV1.decodeCanonical(from: row.receiptData)
                _ = try ActivityContractMutationReceiptV2(
                    mutation: value,
                    mutationReceipt: receipt
                )
                XCTAssertEqual(receipt.postImages, try value.mutationPostImages)
                restoredMutations.append(value)
            }
            XCTAssertEqual(
                restoredMutations.map { $0.successorEnvelope.revision },
                Array(1...UInt64(sourceMutations.count))
            )
            XCTAssertNil(restoredMutations[0].successorEnvelope.predecessorEnvelopeSHA256)
            for index in restoredMutations.indices.dropFirst() {
                let predecessor = restoredMutations[index - 1].successorEnvelope
                let successor = restoredMutations[index].successorEnvelope
                XCTAssertEqual(restoredMutations[index].predecessorEnvelope, predecessor)
                XCTAssertEqual(successor.predecessorEnvelopeSHA256, predecessor.envelopeSHA256)
                try successor.validateSuccessor(of: predecessor)
            }
            XCTAssertEqual(restoredEnvelope, restoredMutations.last?.successorEnvelope)
            let restoredInstallationBasis = try XCTUnwrap(
                restoredMutations[0].installationBasisSnapshot
            )
            if mode == .emptyInstall {
                XCTAssertEqual(restoredInstallationBasis, sourceInstallationBasis)
            } else {
                let targetRegistry = try InspectionPackageRegistryV2(packages: [shippingPackage])
                let targetInstallationRelease = try C47ActivityTestSupport.installationRelease(
                    registry: targetRegistry,
                    workspaceID: restored.workspaceID
                )
                XCTAssertEqual(
                    restoredInstallationBasis.workflowReleaseReference.sourceReleaseSHA256,
                    sourceInstallationBasis.workflowReleaseReference.sourceReleaseSHA256
                )
                XCTAssertEqual(
                    restoredInstallationBasis.workflowReleaseReference.targetWorkspaceID,
                    restored.workspaceID
                )
                try restoredInstallationBasis.workflowReleaseReference.validateTarget(
                    installation: targetInstallationRelease,
                    package: shippingPackage
                )
            }
            let restoredReportRow = try XCTUnwrap(
                restored.modelContext.fetch(FetchDescriptor<Report>()).first {
                    $0.snapshotSchemaVersion == CompletedActivitySnapshotV2.schemaVersion
                }
            )
            let restoredSnapshotBytes = try ReportPDFAnchoredFile.readRegularFile(
                at: restored.generationRootURL.appendingPathComponent(
                    restoredReportRow.snapshotRelativePath
                ),
                within: restored.generationRootURL,
                rootIdentity: ReportPDFAnchoredFile.rootIdentity(at: restored.generationRootURL)
            )
            XCTAssertEqual(restoredSnapshotBytes, completedSnapshotBytes)
            let restoredSnapshot = try CompletedActivitySnapshotCanonicalCodecV2.decode(
                restoredSnapshotBytes
            )
            XCTAssertEqual(restoredSnapshot, completedReport.snapshot)
            XCTAssertEqual(restoredSnapshot.snapshotSHA256, completedReport.snapshot.snapshotSHA256)
            let restoredCompletedReference = try XCTUnwrap(
                restoredEnvelope.completedSnapshotReference
            )
            XCTAssertEqual(restoredCompletedReference.workspaceID, restored.workspaceID)
            XCTAssertEqual(restoredCompletedReference.activityID, restoredEnvelope.activityID)
            XCTAssertEqual(restoredCompletedReference.sourceWorkspaceID, source.workspaceID)
            XCTAssertEqual(
                restoredCompletedReference.sourceCloseoutSHA256,
                completedReference.sourceCloseoutSHA256
            )
            if mode == .emptyInstall {
                XCTAssertEqual(
                    restoredCompletedReference.targetCloseoutSHA256,
                    completedReference.targetCloseoutSHA256
                )
            } else {
                let restoredCloseout = try XCTUnwrap(restoredEnvelope.installationCloseout)
                XCTAssertEqual(
                    restoredCompletedReference.targetCloseoutSHA256,
                    restoredCloseout.closeoutSHA256
                )
                XCTAssertNotEqual(
                    restoredCompletedReference.targetCloseoutSHA256,
                    completedReference.targetCloseoutSHA256
                )
            }
            try restoredCompletedReference.validate(snapshot: restoredSnapshot)
            let restoredReportProjection = try ActivityContractReportProjectionV2(
                envelope: restoredEnvelope,
                completed: restoredSnapshot
            )
            let restoredRenderedReport = try ReportRenderService(
                modelContext: restored.modelContext,
                generationRootURL: restored.generationRootURL,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
            ).renderActivityContract(
                restoredReportProjection,
                manifest: completedReport.manifest,
                reportProfile: completedReport.layout,
                exportProfile: completedReport.export
            )
            XCTAssertEqual(
                try ReportRecoveryService.reopenActivityContract(
                    restoredReportProjection,
                    manifest: completedReport.manifest,
                    reportProfile: completedReport.layout,
                    exportProfile: completedReport.export,
                    storedBundle: restoredRenderedReport
                ),
                restoredRenderedReport
            )
            if mode == .emptyInstall {
                XCTAssertEqual(restoredActivityRows.map(\.envelopeData), sourceActivityEnvelopeBytes)
                XCTAssertEqual(restoredActivityRows.map(\.receiptData), sourceActivityReceiptBytes)
                XCTAssertEqual(restoredMutations, sourceMutations)
            } else {
                let targetPointer = RestorePointerIdentityV1(
                    generationID: restored.generationID,
                    generationManifestSHA256: C47ActivityTestSupport.digest("a"),
                    workspaceID: restored.workspaceID.rawValue,
                    replicaID: restored.replicaID.rawValue
                )
                let restoreIdentity = RestoreIdentityV1(
                    mode: mode,
                    source: RestoreSourceIdentityV1(
                        workspaceID: source.workspaceID.rawValue,
                        replicaID: source.replicaID.rawValue
                    ),
                    oldPointer: targetPointer,
                    targetPointer: targetPointer,
                    recordIdentityDisposition: .preserve
                )
                XCTAssertEqual(
                    restoredMutations.map(\.mutationID),
                    try sourceMutations.map {
                        try restoreIdentity.destinationActivityContractMutationID(for: $0.mutationID)
                    }
                )
                XCTAssertTrue(restoredMutations.allSatisfy { $0.workspaceID == restored.workspaceID })
            }
            if mode == .fork { eraseCandidate = (support, restored) }
        }

        let replaceValidated = try BackupImportService(
            generationRootURL: source.generationRootURL,
            makeUUID: { C47ActivityTestSupport.id(110) },
            scopedAccess: .alreadyAuthorized
        ).stageAndValidate(selectedPackageURL: package)
        let replaced = try await BackupRestoreService(
            applicationSupportURL: sourceSupport,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
        ).restore(
            validatedPackage: replaceValidated,
            currentModelContext: source.modelContext,
            currentGenerationID: source.generationID,
            currentGenerationRootURL: source.generationRootURL,
            mode: .replaceExisting
        )
        let replacedRow = try XCTUnwrap(
            replaced.modelContext.fetch(FetchDescriptor<ActivitySessionEnvelopeRow>()).first
        )
        XCTAssertEqual(try replacedRow.value(), finalizedEnvelope)
        XCTAssertEqual(
            replacedRow.canonicalData,
            try finalizedEnvelope.canonicalData()
        )
        let replacedActivityRows = try replaced.modelContext.fetch(
            FetchDescriptor<MutationReceiptRow>()
        )
        .filter { $0.commandKind == WorkspaceCommandKindV1.applyActivityContract.rawValue }
        .sorted { $0.localSequence < $1.localSequence }
        XCTAssertEqual(replacedActivityRows.map(\.envelopeData), sourceActivityEnvelopeBytes)
        XCTAssertEqual(replacedActivityRows.map(\.receiptData), sourceActivityReceiptBytes)
        let replacedJournal = try MutationJournalStoreV1(
            modelContext: replaced.modelContext,
            identity: replaced.workspaceIdentity,
            generationID: replaced.generationID,
            allowStateBootstrap: false
        )
        try replacedJournal.validateAll()

        let deletion = try await WholeSignDeletionService(
            modelContext: replaced.modelContext,
            generationRootURL: replaced.generationRootURL
        ).delete(assetID: subjectAssetID)
        XCTAssertEqual(deletion.assetID, subjectAssetID)
        let retainedFinalized = try replaced.modelContext.fetch(
            FetchDescriptor<ActivitySessionEnvelopeRow>()
        )
        XCTAssertEqual(retainedFinalized.count, 1)
        XCTAssertEqual(try retainedFinalized[0].value(), finalizedEnvelope)
        XCTAssertEqual(
            try replaced.modelContext.fetch(FetchDescriptor<ActivityStateTransitionRow>()).count,
            sourceMutations.compactMap(\.transition).count
        )
        XCTAssertEqual(
            try replaced.modelContext.fetch(FetchDescriptor<InstallationTaskResultRow>()).count,
            3
        )
        XCTAssertEqual(
            try replaced.modelContext.fetch(FetchDescriptor<InstallationAsBuiltSnapshotRow>()).count,
            1
        )
        XCTAssertTrue(
            try replaced.modelContext.fetch(FetchDescriptor<PunchReviewBasisSnapshotRow>()).isEmpty
        )

        let eraseTarget = try XCTUnwrap(eraseCandidate)
        let caches = root.appendingPathComponent("erase-caches", isDirectory: true)
        let temporary = root.appendingPathComponent("erase-temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let coordinator = StoreSessionCoordinator(session: eraseTarget.session)
        let diagnostics = DiagnosticsStore(applicationSupportURL: eraseTarget.support)
        await diagnostics.prepare()
        let suiteName = "C47-R01-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let erase = EraseAllService(
            applicationSupportURL: eraseTarget.support,
            cachesDirectoryURL: caches,
            temporaryDirectoryURL: temporary,
            userDefaults: defaults,
            bundleIdentifier: suiteName
        )
        let erased = try await erase.erase(
            confirmation: EraseAllService.requiredConfirmation,
            coordinator: coordinator,
            diagnosticsStore: diagnostics
        ) { replacement in
            coordinator.activate(session: replacement)
        }
        try erase.validateActivityContractEraseClosure(session: erased.session)
    }
}

private struct C47ActivityClock: ApplicationClock {
    let value: Date
    func now() -> Date { value }
}

private struct C47ActivityIDSource: ApplicationIDSource {
    let value: UUID
    func makeID() -> UUID { value }
}

private struct C47ActivityFileAuthority: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(
        mutationID: MutationIDV1,
        component: String
    ) throws -> String {
        "c47/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}
